import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import lattice_core/replica_id
import lattice_maps/crdt
import lattice_maps/or_map
import lattice_sets/or_set
import startest/expect
import watershed/or_map_kernel as kernel

fn fresh(name: String) -> kernel.OrMapState {
  kernel.new(replica_id.new(name), kernel.OrSetMode)
}

fn coherent(state: kernel.OrMapState) -> Nil {
  kernel.check_cache_coherence(state) |> expect.to_equal(Ok(Nil))
}

pub fn missing_empty_and_noop_removals_test() -> Nil {
  let empty = fresh("a")
  let assert Ok(#(state, events, operation)) =
    kernel.p2p_remove_member(empty, "missing", "member")
  state |> expect.to_equal(empty)
  events |> expect.to_equal([])
  operation
  |> expect.to_equal(kernel.RemoveMember(
    "missing",
    "member",
    or_map.empty_delta(empty.optimistic),
  ))
  let assert Ok(#(state, events, _)) = kernel.p2p_remove(state, "missing")
  state |> expect.to_equal(empty)
  events |> expect.to_equal([])
  let assert Ok(#(state, _, _)) = kernel.p2p_add_member(state, "", "")
  let assert Ok(#(state, events, _)) = kernel.p2p_remove_member(state, "", "")
  kernel.get(state, "") |> expect.to_equal(Ok(kernel.SetMembers([])))
  events |> expect.to_equal([kernel.SetMembersUpdated("", [])])
  let assert Ok(#(unchanged, events, _)) =
    kernel.p2p_remove_member(state, "", "absent")
  unchanged |> expect.to_equal(state)
  events |> expect.to_equal([])
  coherent(unchanged)
  let assert Ok(loaded) =
    kernel.from_summary(
      kernel.summary(state) |> json.to_string,
      replica_id.new("b"),
    )
  kernel.get(loaded, "") |> expect.to_equal(Ok(kernel.SetMembers([])))
  kernel.get(loaded, "missing") |> expect.to_equal(Error(Nil))
  coherent(loaded)
}

pub fn duplicate_add_has_fresh_metadata_without_visible_event_test() -> Nil {
  let assert Ok(#(first, _, original)) =
    kernel.p2p_add_member(fresh("a"), "doc", "draft")
  let assert Ok(#(second, events, repeated)) =
    kernel.p2p_add_member(first, "doc", "draft")
  events |> expect.to_equal([])
  { first.optimistic == second.optimistic } |> expect.to_be_false
  { original == repeated } |> expect.to_be_false
  kernel.entries(first) |> expect.to_equal(kernel.entries(second))
  let assert Ok(#(removed, _, removal)) =
    kernel.p2p_remove_member(first, "doc", "draft")
  let assert Ok(#(survivor, _)) = kernel.apply_remote(removed, repeated)
  let assert Ok(#(reverse, _)) = kernel.apply_remote(second, removal)
  kernel.get(survivor, "doc")
  |> expect.to_equal(Ok(kernel.SetMembers(["draft"])))
  kernel.entries(reverse) |> expect.to_equal(kernel.entries(survivor))
  coherent(survivor)
  coherent(reverse)
}

pub fn concurrent_key_removal_keeps_only_unobserved_members_test() -> Nil {
  let assert Ok(#(base, _, original)) =
    kernel.p2p_add_member(fresh("seed"), "doc", "old")
  let assert Ok(left) =
    kernel.from_sequenced(base.sequenced, kernel.OrSetMode, replica_id.new("a"))
  let assert Ok(right) =
    kernel.from_sequenced(base.sequenced, kernel.OrSetMode, replica_id.new("b"))
  let assert Ok(#(left, _, removal)) = kernel.p2p_remove(left, "doc")
  let assert Ok(#(right, _, addition)) =
    kernel.p2p_add_member(right, "doc", "new")
  let assert Ok(#(left, _)) = kernel.apply_remote(left, addition)
  let assert Ok(#(right, _)) = kernel.apply_remote(right, removal)
  let assert Ok(#(left, _)) = kernel.apply_remote(left, original)
  let assert Ok(#(right, _)) = kernel.apply_remote(right, original)
  kernel.get(left, "doc") |> expect.to_equal(Ok(kernel.SetMembers(["new"])))
  kernel.entries(right) |> expect.to_equal(kernel.entries(left))
  let assert Ok(#(merged, _)) = kernel.p2p_merge(left, right.sequenced)
  kernel.entries(merged) |> expect.to_equal(kernel.entries(left))
  coherent(left)
  coherent(right)
  coherent(merged)
}

pub fn concurrent_writers_and_reordered_delivery_test() -> Nil {
  let assert Ok(#(left, _, left_add)) =
    kernel.p2p_add_member(fresh("a"), "doc", "a")
  let assert Ok(#(right, _, right_add)) =
    kernel.p2p_add_member(fresh("b"), "doc", "b")
  let assert Ok(#(left, _, left_other)) =
    kernel.p2p_add_member(left, "other", "a")
  let assert Ok(#(left, _)) = kernel.apply_remote(left, right_add)
  let assert Ok(#(right, _)) = kernel.apply_remote(right, left_other)
  let assert Ok(#(right, _)) = kernel.apply_remote(right, left_add)
  let assert Ok(#(right, events)) = kernel.apply_remote(right, left_add)
  events |> expect.to_equal([])
  kernel.entries(left)
  |> expect.to_equal([
    #("doc", kernel.SetMembers(["a", "b"])),
    #("other", kernel.SetMembers(["a"])),
  ])
  kernel.entries(right) |> expect.to_equal(kernel.entries(left))
  coherent(left)
  coherent(right)
}

pub fn rollback_checkpoint_reserves_absent_leaf_counter_test() -> Nil {
  let assert Ok(#(pending, _, abandoned, message_id)) =
    kernel.add_member(fresh("a"), "doc", "abandoned")
  kernel.sequenced_entries(pending) |> expect.to_equal([])
  let assert Ok(#(rolled, events)) =
    kernel.rollback(pending, abandoned, message_id)
  events |> expect.to_equal([kernel.KeyRemoved("doc")])
  kernel.entries(rolled) |> expect.to_equal([])
  coherent(rolled)
  let assert Ok(reloaded) =
    kernel.from_summary(
      kernel.summary(rolled) |> json.to_string,
      replica_id.new("a"),
    )
  let assert Ok(#(reloaded, _, fresh_add)) =
    kernel.p2p_add_member(reloaded, "doc", "fresh")
  let assert Ok(#(reloaded, _)) = kernel.apply_remote(reloaded, abandoned)
  kernel.get(reloaded, "doc")
  |> expect.to_equal(Ok(kernel.SetMembers(["abandoned", "fresh"])))
  { abandoned == fresh_add } |> expect.to_be_false
  coherent(reloaded)
}

pub fn rollback_without_reload_preserves_counter_and_exact_stash_test() -> Nil {
  let assert Ok(#(state, _, first, first_id)) =
    kernel.add_member(fresh("a"), "doc", "first")
  let assert Ok(#(state, _, second, second_id)) =
    kernel.add_member(state, "doc", "second")
  coherent(state)
  let assert Error(kernel.UnexpectedAck(_)) =
    kernel.ack_local_with_message_id(state, second, second_id)
  let assert Error(kernel.UnexpectedRollback(_)) =
    kernel.rollback(state, first, first_id)
  let assert Error(kernel.UnexpectedAck(_)) =
    kernel.ack_local_with_message_id(state, first, first_id + 1)
  let assert Ok(#(state, _)) = kernel.rollback(state, second, second_id)
  coherent(state)
  let assert Ok(#(state, _, third, _)) =
    kernel.add_member(state, "doc", "third")
  let assert Ok(#(state, _, stashed, stashed_id)) =
    kernel.apply_stashed_operation(state, second)
  stashed |> expect.to_equal(second)
  stashed_id |> expect.to_equal(3)
  coherent(state)
  let assert Ok(state) =
    kernel.ack_local_with_message_id(state, first, first_id)
  coherent(state)
  let assert Ok(state) = kernel.ack_local(state, third)
  let assert Ok(state) = kernel.ack_local(state, stashed)
  kernel.entries(state)
  |> expect.to_equal([
    #("doc", kernel.SetMembers(["first", "second", "third"])),
  ])
  coherent(state)
}

pub fn summary_restores_removed_history_for_each_writer_test() -> Nil {
  let assert Ok(#(state, _, original)) =
    kernel.p2p_add_member(fresh("a"), "doc", "old")
  let assert Ok(#(state, _, _)) = kernel.p2p_remove(state, "doc")
  list.each(["a", "b"], fn(writer) {
    let assert Ok(loaded) =
      kernel.from_summary(
        kernel.summary(state) |> json.to_string,
        replica_id.new(writer),
      )
    let assert Ok(#(loaded, _, _)) = kernel.p2p_add_member(loaded, "doc", "new")
    let assert Ok(#(loaded, _)) = kernel.apply_remote(loaded, original)
    kernel.get(loaded, "doc")
    |> expect.to_equal(Ok(kernel.SetMembers(["new"])))
    coherent(loaded)
  })
}

pub fn canonical_unicode_keys_members_and_events_test() -> Nil {
  let assert Ok(state) =
    list.try_fold(["😀", "", "a", ""], fresh("a"), fn(state, key) {
      use #(state, _, _) <- result.try(kernel.p2p_add_member(state, key, key))
      Ok(state)
    })
  let assert Ok(#(state, _, _)) = kernel.p2p_add_member(state, "", "😀")
  let assert Ok(#(state, _, _)) = kernel.p2p_add_member(state, "", "")
  kernel.keys(state) |> expect.to_equal(["", "a", "", "😀"])
  kernel.get(state, "")
  |> expect.to_equal(Ok(kernel.SetMembers(["", "", "😀"])))
  let assert Ok(#(peer, events)) = kernel.p2p_merge(fresh("b"), state.sequenced)
  events
  |> expect.to_equal([
    kernel.SetMembersUpdated("", ["", "", "😀"]),
    kernel.SetMembersUpdated("a", ["a"]),
    kernel.SetMembersUpdated("", [""]),
    kernel.SetMembersUpdated("😀", ["😀"]),
  ])
  coherent(peer)
}

pub fn mode_mismatch_rejects_member_operations_test() -> Nil {
  list.each([kernel.TallyMode, kernel.RegisterMode], fn(mode) {
    let state = kernel.new(replica_id.new("a"), mode)
    let assert Error(kernel.ModeMismatch(_)) =
      kernel.add_member(state, "doc", "member")
    let assert Error(kernel.ModeMismatch(_)) =
      kernel.remove_member(state, "doc", "member")
    let assert Error(kernel.ModeMismatch(_)) =
      kernel.p2p_add_member(state, "doc", "member")
    let assert Error(kernel.ModeMismatch(_)) =
      kernel.p2p_remove_member(state, "doc", "member")
  })
  let state = fresh("a")
  let assert Error(kernel.ModeMismatch(_)) = kernel.increment(state, "doc", 1)
  let assert Error(kernel.ModeMismatch(_)) =
    kernel.set_register(state, "doc", "value", 1)
  Nil
}

pub fn typed_operation_rejects_wrong_key_member_and_intent_test() -> Nil {
  let assert Ok(#(_, _, kernel.AddMember(_, _, delta))) =
    kernel.p2p_add_member(fresh("a"), "doc", "draft")
  let invalid = [
    kernel.AddMember("other", "draft", delta),
    kernel.AddMember("doc", "not-present", delta),
    kernel.RemoveMember("doc", "draft", delta),
    kernel.Remove("doc", delta),
  ]
  list.each(invalid, fn(operation) {
    let state = fresh("b")
    let assert Error(kernel.InvalidSetState(_)) =
      kernel.validate_operation(kernel.OrSetMode, operation)
    let assert Error(kernel.InvalidSetState(_)) =
      kernel.apply_remote(state, operation)
    let assert Error(kernel.InvalidSetState(_)) =
      kernel.apply_stashed_operation(state, operation)
    let poisoned =
      kernel.OrMapState(..state, pending: [
        kernel.PendingOperation(operation, 0),
      ])
    let assert Error(kernel.InvalidSetState(_)) =
      kernel.ack_local_with_message_id(poisoned, operation, 0)
    let assert Error(kernel.InvalidSetState(_)) =
      kernel.rollback(poisoned, operation, 0)
    let assert Error(_) = kernel.check_cache_coherence(poisoned)
  })
}

pub fn typed_operation_rejects_multiple_declared_keys_test() -> Nil {
  let assert Ok(#(state, _, kernel.AddMember(_, _, first))) =
    kernel.p2p_add_member(fresh("a"), "doc", "draft")
  let assert Ok(#(_, _, kernel.AddMember(_, _, second))) =
    kernel.p2p_add_member(state, "other", "draft")
  let assert Ok(batched) = or_map.merge_deltas(first, second)
  let assert Error(kernel.InvalidSetState(_)) =
    kernel.apply_remote(fresh("b"), kernel.AddMember("doc", "draft", batched))
  Nil
}

pub fn native_inactive_live_leaf_import_does_not_revive_members_test() -> Nil {
  let native = or_map.new(replica_id.new("a"), crdt.OrSetSpec)
  let assert Ok(#(native, _)) =
    or_map.update_with_delta(native, "doc", fn(_) {
      crdt.CrdtOrSet(or_set.new(replica_id.new("a")) |> or_set.add("old"))
    })
  let #(native, _) = or_map.remove_with_delta(native, "doc")
  list.each(["a", "b"], fn(writer) {
    let assert Ok(loaded) =
      kernel.from_sequenced(native, kernel.OrSetMode, replica_id.new(writer))
    let assert Ok(#(loaded, _, _)) = kernel.p2p_add_member(loaded, "doc", "new")
    kernel.get(loaded, "doc")
    |> expect.to_equal(Ok(kernel.SetMembers(["new"])))
    coherent(loaded)
  })
}

fn seed_json(counter: Int) -> String {
  or_map.new(replica_id.new("a"), crdt.OrSetSpec)
  |> or_map.to_json
  |> json.to_string
  |> string.replace("\"clock\":0", "\"clock\":" <> int.to_string(counter))
}

fn native_with_leaf_clock(counter: Int) -> #(kernel.ORMap, kernel.ORMapDelta) {
  let author = replica_id.new("a")
  let assert Ok(leaf) =
    or_set.new(author)
    |> or_set.add("absent")
    |> or_set.remove("absent")
    |> or_set.to_json
    |> json.to_string
    |> string.replace("\"counter\":1", "\"counter\":" <> int.to_string(counter))
    |> or_set.from_json
  // Native bind raises a negative counter to zero, still below the retained
  // removal tag. The snapshot and the original delta must both be rejected.
  let assert Ok(pair) =
    or_map.update_with_delta(
      or_map.new(author, crdt.OrSetSpec),
      "absent",
      fn(_) { crdt.CrdtOrSet(leaf) },
    )
  pair
}

pub fn counter_exhaustion_is_fallible_but_noop_removal_is_allowed_test() -> Nil {
  let assert Ok(state) =
    kernel.from_summary(seed_json(9_007_199_254_740_991), replica_id.new("a"))
  let assert Error(kernel.CounterExhausted(_)) =
    kernel.add_member(state, "doc", "member")
  let assert Error(kernel.CounterExhausted(_)) =
    kernel.p2p_add_member(state, "doc", "member")
  let assert Ok(#(unchanged, events, _)) =
    kernel.p2p_remove_member(state, "doc", "member")
  unchanged |> expect.to_equal(state)
  events |> expect.to_equal([])
  let assert Ok(#(unchanged, _, _)) = kernel.p2p_remove(state, "doc")
  unchanged |> expect.to_equal(state)
}

pub fn unsafe_typed_snapshots_rejected_before_native_merge_test() -> Nil {
  list.each([-1, 9_007_199_254_740_992], fn(counter) {
    kernel.from_summary(seed_json(counter), replica_id.new("b"))
    |> expect.to_be_error()
    let #(native, _) = native_with_leaf_clock(counter)
    let encoded = or_map.to_json(native) |> json.to_string
    let assert Error(_) = kernel.from_summary(encoded, replica_id.new("b"))
    let assert Error(kernel.InvalidSetState(_)) =
      kernel.from_sequenced(native, kernel.OrSetMode, replica_id.new("b"))
    let assert Error(kernel.InvalidSetState(_)) =
      kernel.p2p_merge(fresh("b"), native)
  })
  let native = or_map.new(replica_id.new("a"), crdt.PnCounterSpec)
  let assert Error(kernel.ModeMismatch(_)) =
    kernel.from_sequenced(native, kernel.OrSetMode, replica_id.new("b"))
  let assert Error(kernel.ModeMismatch(_)) =
    kernel.p2p_merge(fresh("b"), native)
  Nil
}

pub fn issued_clock_seed_contains_no_pending_leaf_and_survives_reload_test() -> Nil {
  let assert Ok(#(state, _, operation, message_id)) =
    kernel.add_member(fresh("a"), "doc", "member")
  let assert Ok(entries) =
    json.parse(
      kernel.summary(state) |> json.to_string,
      decode.at(["state", "entries"], decode.list(decode.dynamic)),
    )
  entries |> expect.to_equal([])
  let assert Ok(counter) =
    json.parse(
      kernel.summary(state) |> json.to_string,
      decode.at(["state", "clock"], decode.int),
    )
  { counter > 0 } |> expect.to_be_true
  let assert Ok(#(state, _)) = kernel.rollback(state, operation, message_id)
  let assert Ok(state) =
    kernel.from_summary(
      kernel.summary(state) |> json.to_string,
      replica_id.new("a"),
    )
  let assert Ok(#(state, _, _)) = kernel.p2p_add_member(state, "other", "fresh")
  let assert Ok(next_counter) =
    json.parse(
      kernel.summary(state) |> json.to_string,
      decode.at(["state", "clock"], decode.int),
    )
  { next_counter > counter } |> expect.to_be_true
  coherent(state)
}

pub fn remote_remove_and_pending_add_rebuild_exact_cache_test() -> Nil {
  let assert Ok(#(base, _, _)) =
    kernel.p2p_add_member(fresh("seed"), "doc", "old")
  let assert Ok(left) =
    kernel.from_sequenced(base.sequenced, kernel.OrSetMode, replica_id.new("a"))
  let assert Ok(right) =
    kernel.from_sequenced(base.sequenced, kernel.OrSetMode, replica_id.new("b"))
  let assert Ok(#(left, _, addition, message_id)) =
    kernel.add_member(left, "doc", "new")
  let assert Ok(#(_, _, removal)) = kernel.p2p_remove(right, "doc")
  let assert Ok(#(left, events)) = kernel.apply_remote(left, removal)
  events |> expect.to_equal([kernel.SetMembersUpdated("doc", ["new"])])
  coherent(left)
  let assert Ok(left) =
    kernel.ack_local_with_message_id(left, addition, message_id)
  kernel.sequenced_entries(left)
  |> expect.to_equal([#("doc", kernel.SetMembers(["new"]))])
  coherent(left)
}

pub fn promotion_and_noop_pending_operations_preserve_cache_test() -> Nil {
  let assert Ok(#(state, events, noop, message_id)) =
    kernel.remove_member(fresh("a"), "missing", "member")
  events |> expect.to_equal([])
  kernel.entries(state) |> expect.to_equal([])
  coherent(state)
  let assert Ok(state) =
    kernel.ack_local_with_message_id(state, noop, message_id)
  let assert Ok(#(state, _, _, _)) = kernel.add_member(state, "doc", "member")
  let state = kernel.promote_attach(state)
  state.pending |> expect.to_equal([])
  kernel.sequenced_entries(state)
  |> expect.to_equal([#("doc", kernel.SetMembers(["member"]))])
  coherent(state)
}

pub fn stashed_delta_keeps_original_writer_and_observed_clock_floor_test() -> Nil {
  let assert Ok(author) =
    kernel.from_summary(seed_json(100), replica_id.new("a"))
  let assert Ok(#(_, _, original, _)) =
    kernel.add_member(author, "doc", "stashed")
  let assert Ok(#(restored, _, replayed, message_id)) =
    kernel.apply_stashed_operation(fresh("b"), original)
  replayed |> expect.to_equal(original)
  kernel.sequenced_entries(restored) |> expect.to_equal([])
  coherent(restored)
  let assert Ok(restored) =
    kernel.ack_local_with_message_id(restored, replayed, message_id)
  let assert Ok(#(restored, _, kernel.AddMember(_, _, delta))) =
    kernel.p2p_add_member(restored, "other", "fresh")
  let assert Ok(author) =
    json.parse(
      or_map.delta_to_json(delta) |> json.to_string,
      decode.at(["state", "replica_id"], decode.string),
    )
  author |> expect.to_equal("b")
  let assert Ok(counter) =
    json.parse(
      kernel.summary(restored) |> json.to_string,
      decode.at(["state", "clock"], decode.int),
    )
  { counter > 101 } |> expect.to_be_true
  coherent(restored)
}

pub fn typed_unsafe_delta_rejected_even_for_noop_intent_test() -> Nil {
  let #(_, safe_delta) = native_with_leaf_clock(1)
  kernel.validate_operation(
    kernel.OrSetMode,
    kernel.RemoveMember("absent", "absent", safe_delta),
  )
  |> expect.to_equal(Ok(Nil))
  list.each([-1, 9_007_199_254_740_992], fn(counter) {
    let #(_, delta) = native_with_leaf_clock(counter)
    let operation = kernel.RemoveMember("absent", "absent", delta)
    let assert Error(kernel.InvalidSetState(_)) =
      kernel.validate_operation(kernel.OrSetMode, operation)
    let assert Error(kernel.InvalidSetState(_)) =
      kernel.apply_remote(fresh("b"), operation)
    let assert Error(kernel.InvalidSetState(_)) =
      kernel.apply_stashed_operation(fresh("b"), operation)
    Nil
  })
}

pub fn set_key_readd_does_not_revive_members_test() -> Nil {
  let state = kernel.new(replica_id.new("a"), kernel.OrSetMode)
  let assert Ok(#(state, _, original)) =
    kernel.p2p_add_member(state, "doc", "old")
  let assert Ok(#(state, _, _)) = kernel.p2p_remove(state, "doc")
  kernel.get(state, "doc") |> expect.to_equal(Error(Nil))
  let assert Ok(#(state, _, _)) = kernel.p2p_add_member(state, "doc", "new")
  let assert Ok(#(state, events)) = kernel.apply_remote(state, original)
  events |> expect.to_equal([])
  kernel.get(state, "doc")
  |> expect.to_equal(Ok(kernel.SetMembers(["new"])))
  kernel.check_cache_coherence(state) |> expect.to_equal(Ok(Nil))
}
