import gleam/json
import gleam/list
import gleam/result
import lattice_core/replica_id
import lattice_registers/mv_register
import startest/expect
import watershed/mv_register_kernel as mv

// docs:snippet-start mv-register-concurrent-resolution
pub fn concurrent_writes_survive_until_observed_resolution_test() -> Nil {
  let #(a, _, write_a, id_a) =
    mv.set(mv.new(replica_id.new("a")), "raise crest")
  let #(b, _, write_b, id_b) = mv.set(mv.new(replica_id.new("b")), "arm pump")
  let assert Ok(a) = mv.ack_local_with_message_id(a, write_a, id_a)
  let assert Ok(b) = mv.ack_local_with_message_id(b, write_b, id_b)
  let #(a, _) = mv.apply_remote(a, write_b)
  let #(b, _) = mv.apply_remote(b, write_a)
  mv.values(a) |> expect.to_equal(["arm pump", "raise crest"])
  mv.values(b) |> expect.to_equal(["arm pump", "raise crest"])
  let #(a, _, resolved, resolved_id) = mv.set(a, "raise crest + arm pump")
  let assert Ok(a) = mv.ack_local_with_message_id(a, resolved, resolved_id)
  let #(b, _) = mv.apply_remote(b, resolved)
  mv.values(a) |> expect.to_equal(["raise crest + arm pump"])
  mv.values(b) |> expect.to_equal(["raise crest + arm pump"])
}

// docs:snippet-end mv-register-concurrent-resolution

pub fn rollback_does_not_reuse_a_write_tag_test() -> Nil {
  let #(a, _, old, id) = mv.set(mv.new(replica_id.new("a")), "old")
  let assert Ok(#(a, _)) = mv.rollback(a, old, id)
  mv.check_cache_coherence(a) |> expect.to_equal(Ok(Nil))
  let #(a, _, next, id) = mv.set(a, "next")
  let assert Ok(a) = mv.ack_local_with_message_id(a, next, id)
  let #(b, _) = mv.apply_remote(mv.new(replica_id.new("b")), next)
  let #(b, _) = mv.apply_remote(b, old)
  mv.values(b) |> expect.to_equal(["next"])
  mv.values(a) |> expect.to_equal(["next"])
}

pub fn same_text_changes_causality_without_event_test() -> Nil {
  let #(a, _, _) = mv.p2p_set(mv.new(replica_id.new("a")), "same")
  let before = mv.summary(a) |> json.to_string
  let #(a, events, _) = mv.p2p_set(a, "same")
  events |> expect.to_equal([])
  { mv.summary(a) |> json.to_string != before } |> expect.to_be_true()
}

pub fn empty_text_and_sequential_supersession_test() -> Nil {
  let a = mv.new(replica_id.new("a"))
  mv.values(a) |> expect.to_equal([])
  let #(a, events, first, first_id) = mv.set(a, "")
  events |> expect.to_equal([mv.ValuesChanged([""])])
  let #(a, _, second, second_id) = mv.set(a, "next")
  mv.values(a) |> expect.to_equal(["next"])
  let assert Ok(a) = mv.ack_local_with_message_id(a, first, first_id)
  let assert Ok(a) = mv.ack_local_with_message_id(a, second, second_id)
  mv.sequenced_values(a) |> expect.to_equal(["next"])
  mv.check_cache_coherence(a) |> expect.to_equal(Ok(Nil))
}

pub fn concurrent_identical_text_retains_both_writes_test() -> Nil {
  let #(a, _, _) = mv.p2p_set(mv.new(replica_id.new("a")), "same")
  let #(_, _, b) = mv.p2p_set(mv.new(replica_id.new("b")), "same")
  let #(a, events) = mv.apply_remote(a, b)
  events |> expect.to_equal([mv.ValuesChanged(["same", "same"])])
  let #(a, events) = mv.apply_remote(a, b)
  events |> expect.to_equal([])
  mv.values(a) |> expect.to_equal(["same", "same"])
}

pub fn unicode_alternatives_are_sorted_test() -> Nil {
  let state =
    ["\u{e9}", "z", "a", "\u{3b1}"]
    |> list.index_fold(
      mv.new(replica_id.new("reader")),
      fn(state, value, index) {
        let #(_, _, operation) =
          mv.p2p_set(mv.new(replica_id.new(value)), value)
        let #(state, _) = mv.apply_remote(state, operation)
        let _ = index
        state
      },
    )
  mv.values(state) |> expect.to_equal(["a", "z", "\u{e9}", "\u{3b1}"])
}

pub fn pending_remote_merge_and_ack_are_coherent_test() -> Nil {
  let #(a, _, write, id) = mv.set(mv.new(replica_id.new("a")), "a")
  let #(_, _, remote) = mv.p2p_set(mv.new(replica_id.new("b")), "b")
  let #(a, _) = mv.apply_remote(a, remote)
  mv.values(a) |> expect.to_equal(["a", "b"])
  mv.sequenced_values(a) |> expect.to_equal(["b"])
  let assert Ok(acked) = mv.ack_local_with_message_id(a, write, id)
  mv.values(acked) |> expect.to_equal(mv.values(a))
  mv.check_cache_coherence(acked) |> expect.to_equal(Ok(Nil))
}

pub fn ack_and_rollback_require_exact_operations_and_queue_order_test() -> Nil {
  let empty = mv.new(replica_id.new("a"))
  let #(a, _, first, first_id) = mv.set(empty, "same")
  let #(a, _, second, second_id) = mv.set(a, "same")
  mv.ack_local(empty, first) |> result.is_error |> expect.to_be_true()
  mv.rollback(empty, first, first_id) |> result.is_error |> expect.to_be_true()
  mv.ack_local_with_message_id(a, first, second_id)
  |> result.is_error
  |> expect.to_be_true()
  mv.ack_local_with_message_id(a, second, first_id)
  |> result.is_error
  |> expect.to_be_true()
  mv.rollback(a, first, first_id) |> result.is_error |> expect.to_be_true()
  mv.rollback(a, second, first_id) |> result.is_error |> expect.to_be_true()
  let assert Ok(#(a, events)) = mv.rollback(a, second, second_id)
  events |> expect.to_equal([])
  mv.check_cache_coherence(a) |> expect.to_equal(Ok(Nil))
  let assert Ok(#(a, events)) = mv.rollback(a, first, first_id)
  events |> expect.to_equal([mv.ValuesChanged([])])
  mv.check_cache_coherence(a) |> expect.to_equal(Ok(Nil))
}

pub fn summary_omits_pending_and_stash_preserves_delta_test() -> Nil {
  let #(a, _, original, _) = mv.set(mv.new(replica_id.new("a")), "pending")
  let assert Ok(loaded) =
    mv.from_summary(mv.summary(a) |> json.to_string, replica_id.new("a"))
  mv.values(loaded) |> expect.to_equal([])
  let #(loaded, _, replayed, id) = mv.apply_stashed_operation(loaded, original)
  replayed |> expect.to_equal(original)
  let assert Ok(loaded) = mv.ack_local_with_message_id(loaded, replayed, id)
  mv.values(loaded) |> expect.to_equal(["pending"])
  let detached = mv.from_sequenced(a.optimistic, replica_id.new("b"))
  mv.sequenced_values(detached) |> expect.to_equal(["pending"])
  mv.check_cache_coherence(loaded) |> expect.to_equal(Ok(Nil))
}

pub fn partial_resolution_preserves_unseen_writer_and_rejects_stale_replay_test() -> Nil {
  let #(a, _, old_a) = mv.p2p_set(mv.new(replica_id.new("a")), "a")
  let #(_, _, old_b) = mv.p2p_set(mv.new(replica_id.new("b")), "b")
  let #(_, _, unseen) = mv.p2p_set(mv.new(replica_id.new("c")), "c")
  let #(a, _) = mv.apply_remote(a, old_b)
  let #(a, _, _) = mv.p2p_set(a, "resolved")
  let #(a, _) = mv.apply_remote(a, unseen)
  mv.values(a) |> expect.to_equal(["c", "resolved"])
  let #(a, events) = mv.apply_remote(a, old_a)
  events |> expect.to_equal([])
  let #(a, events, _, _) = mv.apply_stashed_operation(a, old_b)
  events |> expect.to_equal([])
  mv.values(a) |> expect.to_equal(["c", "resolved"])
  mv.check_cache_coherence(a) |> expect.to_equal(Ok(Nil))
}

pub fn summary_load_rebrands_the_writer_test() -> Nil {
  let #(a, _, _) = mv.p2p_set(mv.new(replica_id.new("a")), "base")
  let assert Ok(b) =
    mv.from_summary(mv.summary(a) |> json.to_string, replica_id.new("b"))
  let #(a, _, _) = mv.p2p_set(a, "a")
  let #(b, _, _) = mv.p2p_set(b, "b")
  let #(a, _) = mv.p2p_merge(a, b.sequenced)
  mv.values(a) |> expect.to_equal(["a", "b"])
  a.pending |> expect.to_equal([])
}

pub fn decoder_rejects_invalid_causal_metadata_test() -> Nil {
  let entry = "{\"tag\":{\"r\":\"a\",\"c\":1},\"value\":\"x\"}"
  let invalid = [
    "null",
    "{\"type\":\"other\",\"v\":1,\"state\":{\"replica_id\":\"a\",\"entries\":[],\"vclock\":{}}}",
    "{\"type\":\"mv_register\",\"v\":2,\"state\":{\"replica_id\":\"a\",\"entries\":[],\"vclock\":{}}}",
    envelope("[]", "{\"a\":-1}"),
    envelope("[" <> entry <> "," <> entry <> "]", "{\"a\":1}"),
    envelope("[" <> entry <> "]", "{}"),
    envelope("[{\"tag\":{\"r\":\"a\",\"c\":0},\"value\":\"x\"}]", "{\"a\":1}"),
    envelope("[{\"tag\":{\"r\":\"a\",\"c\":2},\"value\":\"x\"}]", "{\"a\":1}"),
    envelope("[{\"tag\":{\"r\":\"a\",\"c\":1},\"value\":1}]", "{\"a\":1}"),
  ]
  list.each(invalid, fn(source) {
    mv.decode_crdt(source) |> result.is_error |> expect.to_be_true()
  })
  list.each(["{}", "{\"a\":3,\"retired\":7}", "{\"a\":0}"], fn(clock) {
    let assert Ok(empty) = mv.decode_crdt(envelope("[]", clock))
    mv_register.value(empty) |> expect.to_equal([])
  })
}

fn envelope(entries: String, clock: String) -> String {
  "{\"type\":\"mv_register\",\"v\":1,\"state\":{\"replica_id\":\"a\",\"entries\":"
  <> entries
  <> ",\"vclock\":"
  <> clock
  <> "}}"
}
