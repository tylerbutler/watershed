import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import lattice_core/replica_id
import lattice_maps/crdt
import lattice_maps/lww_map
import lattice_registers/lww_register
import startest/expect
import watershed/lww_clock
import watershed/lww_map_kernel as kernel

fn map_fragment(
  key: String,
  value: Option(String),
  timestamp: Int,
  writer: String,
) -> kernel.LWWMap {
  let writer = replica_id.new(writer)
  let map = lww_map.new(writer, crdt.LwwRegisterSpec(""))
  let assert Ok(map) = case value {
    Some(value) ->
      lww_map.set(
        map,
        key,
        crdt.CrdtLwwRegister(lww_register.new(value, timestamp, writer)),
        timestamp,
      )
    None -> lww_map.remove(map, key, timestamp)
  }
  map
}

fn merged_value(
  left: kernel.LWWMap,
  right: kernel.LWWMap,
) -> Result(String, Nil) {
  let assert Ok(merged) = lww_map.merge(left, right)
  case lww_map.get(merged, "k") {
    Ok(crdt.CrdtLwwRegister(register)) -> Ok(lww_register.value(register))
    _ -> Error(Nil)
  }
}

pub fn unicode_key_order_is_target_independent_test() -> Nil {
  let assert Ok(#(state, _, _)) =
    kernel.p2p_set(kernel.new(replica_id.new("a")), "\u{10000}", "astral", 1)
  let assert Ok(#(state, _, _)) = kernel.p2p_set(state, "\u{e000}", "bmp", 1)
  kernel.keys(state) |> expect.to_equal(["\u{e000}", "\u{10000}"])
  kernel.entries(state)
  |> expect.to_equal([#("\u{e000}", "bmp"), #("\u{10000}", "astral")])
  let assert Ok(#(_, events)) =
    kernel.p2p_merge(kernel.new(replica_id.new("b")), state.sequenced)
  events
  |> expect.to_equal([
    kernel.ValueChanged("\u{e000}", None, Some("bmp")),
    kernel.ValueChanged("\u{10000}", None, Some("astral")),
  ])
}

pub fn equal_timestamp_remove_wins_test() -> Nil {
  let a = map_fragment("k", Some("value"), 10, "a")
  let b = map_fragment("k", None, 10, "b")
  merged_value(a, b) |> expect.to_equal(Error(Nil))
  merged_value(b, a) |> expect.to_equal(Error(Nil))
  let assert Ok(merged) = lww_map.merge(a, b)
  merged_value(merged, a) |> expect.to_equal(Error(Nil))
}

pub fn edits_sort_keys_and_retain_absent_removals_test() -> Nil {
  let state = kernel.new(replica_id.new("a"))
  let assert Ok(#(state, [], kernel.Remove("gone", 100, delta), _)) =
    kernel.remove(state, "gone", 100)
  lww_map.tombstone_count(delta) |> expect.to_equal(1)
  let assert Ok(#(state, _, _, _)) = kernel.set(state, "z", "", 1)
  let assert Ok(#(state, events, _, _)) = kernel.set(state, "a", "first", 1)
  events |> expect.to_equal([kernel.ValueChanged("a", None, Some("first"))])
  kernel.entries(state) |> expect.to_equal([#("a", "first"), #("z", "")])
  kernel.keys(state) |> expect.to_equal(["a", "z"])
  let assert Ok(#(state, [], kernel.Set("a", "first", 2, _), _)) =
    kernel.set(state, "a", "first", 0)
  let assert Ok(#(state, events, _, _)) = kernel.remove(state, "a", 0)
  events |> expect.to_equal([kernel.ValueChanged("a", Some("first"), None)])
  kernel.get(state, "a") |> expect.to_equal(Error(Nil))
  kernel.check_cache_coherence(state) |> expect.to_equal(Ok(Nil))
}

pub fn reload_observes_tombstone_time_test() -> Nil {
  let removed = map_fragment("k", None, 100, "a")
  let assert Ok(state) =
    kernel.from_summary(
      json.to_string(lww_map.to_json(removed)),
      replica_id.new("b"),
    )
  let assert Ok(#(state, _, kernel.Set(_, _, timestamp, _), _)) =
    kernel.set(state, "k", "restored", 1)
  timestamp |> expect.to_equal(101)
  kernel.get(state, "k") |> expect.to_equal(Ok("restored"))
}

pub fn ack_rollback_replay_and_summary_preserve_clocks_test() -> Nil {
  let initial = kernel.new(replica_id.new("a"))
  let assert Ok(#(state, _, first, first_id)) =
    kernel.set(initial, "k", "first", 10)
  let assert Ok(#(state, _, second, second_id)) = kernel.remove(state, "k", 20)
  kernel.summary(state) |> expect.to_equal(kernel.summary(initial))
  let assert Error(kernel.UnexpectedAck(_, _)) = kernel.ack_local(state, second)
  let assert Error(kernel.UnexpectedAck(_, _)) =
    kernel.ack_local_with_message_id(state, first, second_id)
  let assert Error(kernel.UnexpectedRollback(_, _)) =
    kernel.rollback(state, first, first_id)
  let assert Error(kernel.UnexpectedRollback(_, _)) =
    kernel.rollback(state, second, first_id)
  let assert Ok(state) =
    kernel.ack_local_with_message_id(state, first, first_id)
  let assert Ok(#(state, events)) = kernel.rollback(state, second, second_id)
  events |> expect.to_equal([kernel.ValueChanged("k", None, Some("first"))])
  let assert Ok(#(state, _, kernel.Set(_, _, 21, _), id)) =
    kernel.set(state, "k", "next", 0)
  id |> expect.to_equal(2)
  kernel.check_cache_coherence(state) |> expect.to_equal(Ok(Nil))
  let assert Ok(#(replayed, [], replayed_op, _)) =
    kernel.apply_stashed_operation(initial, second)
  replayed_op |> expect.to_equal(second)
  let assert Ok(replayed) = kernel.ack_local(replayed, second)
  let assert Ok(#(_, _, kernel.Set(_, _, 21, _), _)) =
    kernel.set(replayed, "k", "restored", 0)
  let assert Error(kernel.UnexpectedAck(_, _)) =
    kernel.ack_local(initial, first)
  let assert Error(kernel.UnexpectedRollback(_, _)) =
    kernel.rollback(initial, first, first_id)
  Nil
}

pub fn remote_and_full_merges_converge_and_observe_losing_metadata_test() -> Nil {
  let initial = kernel.new(replica_id.new("a"))
  let a = kernel.Set("k", "a", 10, map_fragment("k", Some("a"), 10, "a"))
  let b = kernel.Set("k", "b", 10, map_fragment("k", Some("b"), 10, "b"))
  let remove = kernel.Remove("k", 10, map_fragment("k", None, 10, "c"))
  let merge = fn(operations) {
    list.fold(operations, initial, fn(state, operation) {
      let assert Ok(#(state, _)) = kernel.apply_remote(state, operation)
      state
    })
  }
  let left = merge([a, b, remove, a])
  let right = merge([remove, b, a, remove])
  left.sequenced |> expect.to_equal(right.sequenced)
  kernel.entries(left) |> expect.to_equal([])
  let assert Ok(#(loaded, [])) = kernel.p2p_merge(initial, left.sequenced)
  let assert Ok(#(loaded, _, kernel.Set(_, _, 11, _))) =
    kernel.p2p_set(loaded, "k", "restored", 0)
  let assert Ok(#(loaded, _, kernel.Remove("k", 12, _))) =
    kernel.p2p_remove(loaded, "k", 0)
  loaded.pending |> expect.to_equal([])
  kernel.check_cache_coherence(loaded) |> expect.to_equal(Ok(Nil))
  let assert Ok(#(pending, _, _, _)) = kernel.set(initial, "k", "local", 100)
  let assert Ok(#(pending, [])) = kernel.apply_remote(pending, remove)
  kernel.check_cache_coherence(pending) |> expect.to_equal(Ok(Nil))
}

pub fn rollback_keeps_observed_clocks_and_stash_never_restamps_test() -> Nil {
  let initial = kernel.new(replica_id.new("a"))
  let assert Ok(#(state, _, local, message_id)) =
    kernel.set(initial, "k", "local", 100)
  let remote = kernel.Remove("k", 200, map_fragment("k", None, 200, "b"))
  let assert Ok(#(state, _)) = kernel.apply_remote(state, remote)
  let assert Ok(#(state, [])) = kernel.rollback(state, local, message_id)
  let assert Ok(#(state, [], original, id)) =
    kernel.apply_stashed_operation(state, local)
  original |> expect.to_equal(local)
  id |> expect.to_equal(1)
  kernel.get(state, "k") |> expect.to_equal(Error(Nil))
  let assert Ok(state) = kernel.ack_local_with_message_id(state, original, id)
  let assert Ok(#(state, _, kernel.Set(_, _, 201, _), _)) =
    kernel.set(state, "k", "restored", 0)
  kernel.check_cache_coherence(state) |> expect.to_equal(Ok(Nil))
}

pub fn full_merge_events_are_sorted_and_cache_check_detects_corruption_test() -> Nil {
  let initial = kernel.new(replica_id.new("a"))
  let assert Ok(map) =
    [
      map_fragment("z", Some("last"), 1, "z"),
      map_fragment("a", Some("first"), 1, "a"),
      map_fragment("hidden", None, 100, "hidden"),
    ]
    |> list.try_fold(initial.sequenced, lww_map.merge)
  let assert Ok(#(state, events)) = kernel.p2p_merge(initial, map)
  events
  |> expect.to_equal([
    kernel.ValueChanged("a", None, Some("first")),
    kernel.ValueChanged("z", None, Some("last")),
  ])
  let assert Ok(#(state, _, operation, id)) = kernel.remove(state, "a", 2)
  let assert Ok(#(state, _)) = kernel.rollback(state, operation, id)
  let attached = kernel.promote_attach(state)
  let assert Ok(#(_, _, kernel.Set("a", "next", 3, _), _)) =
    kernel.set(attached, "a", "next", 0)
  let assert Error(_) =
    kernel.check_cache_coherence(
      kernel.LwwMapState(..state, optimistic: initial.sequenced),
    )
  Nil
}

pub fn strict_decoder_rejects_old_versions_and_invalid_metadata_test() -> Nil {
  [
    "{\"type\":\"lww_map\",\"v\":1,\"state\":{\"entries\":[{\"key\":\"k\",\"value\":null,\"timestamp\":1}]}}",
    "{\"type\":\"lww_map\",\"v\":2,\"state\":{\"entries\":[],\"pruned_timestamp\":0}}",
    "{\"type\":\"wrong\",\"v\":2,\"state\":{\"entries\":[],\"pruned_timestamp\":0}}",
    "{\"type\":\"lww_map\",\"v\":3,\"state\":{\"entries\":[],\"pruned_timestamp\":0}}",
    "{\"type\":\"lww_map\",\"v\":2,\"state\":{\"entries\":[]}}",
    "{\"type\":\"lww_map\",\"v\":2,\"state\":{\"entries\":[],\"pruned_timestamp\":null}}",
    "{\"type\":\"lww_map\",\"v\":2,\"state\":{\"entries\":[],\"pruned_timestamp\":1}}",
    "{\"type\":\"lww_map\",\"v\":1,\"state\":{\"entries\":[],\"pruned_timestamp\":1}}",
    "{\"type\":\"lww_map\",\"v\":1,\"state\":{\"entries\":[],\"pruned_timestamp\":\"0\"}}",
    "{\"type\":\"lww_map\",\"v\":2,\"state\":{\"entries\":[{\"key\":\"k\",\"value\":\"v\",\"timestamp\":0}],\"pruned_timestamp\":0}}",
    "{\"type\":\"lww_map\",\"v\":2,\"state\":{\"entries\":[{\"key\":\"k\",\"value\":null,\"timestamp\":-1}],\"pruned_timestamp\":0}}",
    "{\"type\":\"lww_map\",\"v\":2,\"state\":{\"entries\":[{\"key\":\"k\",\"value\":null,\"timestamp\":9007199254740992}],\"pruned_timestamp\":0}}",
    "{\"type\":\"lww_map\",\"v\":2,\"state\":{\"entries\":[{\"key\":\"k\",\"value\":42,\"timestamp\":1}],\"pruned_timestamp\":0}}",
    "{\"type\":\"lww_map\",\"v\":2,\"state\":{\"entries\":[{\"key\":\"k\",\"timestamp\":1}],\"pruned_timestamp\":0}}",
    "{\"type\":\"lww_map\",\"v\":2,\"state\":{\"entries\":[{\"key\":\"k\",\"value\":\"a\",\"timestamp\":1},{\"key\":\"k\",\"value\":null,\"timestamp\":2}],\"pruned_timestamp\":0}}",
  ]
  |> list.each(fn(source) {
    let assert Error(_) = json.parse(source, kernel.decoder())
    let assert Error(_) = kernel.from_summary(source, replica_id.new("a"))
    Nil
  })
}

pub fn native_snapshots_and_operations_cannot_bypass_validation_test() -> Nil {
  let initial = kernel.new(replica_id.new("a"))
  [
    lww_map.prune(initial.sequenced, 1),
    lww_map.new(replica_id.new("a"), crdt.OrSetSpec),
    lww_map.new(replica_id.new("a"), crdt.LwwRegisterSpec("wrong default")),
  ]
  |> list.each(fn(invalid) {
    let assert Error(_) = kernel.from_sequenced(invalid, replica_id.new("a"))
    let assert Error(_) = kernel.p2p_merge(initial, invalid)
    Nil
  })
  let invalid =
    kernel.Set("wrong", "v", 1, map_fragment("k", Some("v"), 1, "a"))
  let assert Error(_) = kernel.apply_remote(initial, invalid)
  let assert Error(_) = kernel.apply_stashed_operation(initial, invalid)
  let assert Error(kernel.Clock(lww_clock.InvalidTimestamp(-1))) =
    kernel.set(initial, "k", "v", -1)
  let assert Ok(#(state, _, _, _)) =
    kernel.remove(initial, "k", lww_clock.max_safe_timestamp)
  let assert Error(kernel.Clock(lww_clock.ClockExhausted)) =
    kernel.remove(state, "k", 0)
  Nil
}

pub fn writes_round_trip_rebind_and_use_writer_ties_test() -> Nil {
  let assert Ok(#(a, _, _)) =
    kernel.p2p_set(kernel.new(replica_id.new("a")), "k", "z", 10)
  let assert Ok(#(b, _, _)) =
    kernel.p2p_set(kernel.new(replica_id.new("b")), "k", "a", 10)
  let assert Ok(#(merged, _)) = kernel.p2p_merge(a, b.sequenced)
  kernel.get(merged, "k") |> expect.to_equal(Ok("a"))
  let assert Ok(#(reverse, _)) = kernel.p2p_merge(b, a.sequenced)
  kernel.entries(reverse) |> expect.to_equal(kernel.entries(merged))
  let assert Ok(loaded) =
    kernel.from_summary(
      kernel.summary(merged) |> json.to_string,
      replica_id.new("c"),
    )
  kernel.entries(loaded) |> expect.to_equal([#("k", "a")])
  lww_map.replica_id(loaded.sequenced) |> expect.to_equal(replica_id.new("c"))
  let assert Ok(#(loaded, _, operation, _)) = kernel.set(loaded, "k", "next", 0)
  kernel.validate_operation(operation) |> expect.to_equal(Ok(Nil))
  let assert Ok(loaded) = kernel.ack_local(loaded, operation)
  kernel.check_cache_coherence(loaded) |> expect.to_equal(Ok(Nil))
  let assert Ok(decoded) =
    json.parse(kernel.summary(loaded) |> json.to_string, kernel.decoder())
  decoded |> expect.to_equal(loaded.sequenced)
}

pub fn conflicting_write_returns_error_without_changing_state_test() -> Nil {
  let initial = kernel.new(replica_id.new("a"))
  let assert Ok(#(state, _, _, _)) = kernel.set(initial, "k", "first", 10)
  let assert Ok(#(_, _, conflicting, _)) =
    kernel.set(initial, "k", "different", 10)
  let assert Error(kernel.InvalidState(_)) =
    kernel.apply_remote(state, conflicting)
  let assert Error(kernel.InvalidState(_)) =
    kernel.apply_stashed_operation(state, conflicting)
  kernel.get(state, "k") |> expect.to_equal(Ok("first"))
  kernel.check_cache_coherence(state) |> expect.to_equal(Ok(Nil))
  let assert Ok(#(_, _, removed)) = kernel.p2p_remove(initial, "k", 10)
  let assert Ok(#(state, _)) = kernel.apply_remote(state, removed)
  kernel.get(state, "k") |> expect.to_equal(Error(Nil))
}
