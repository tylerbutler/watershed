import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string
import lattice_core/replica_id
import lattice_maps/crdt
import lattice_maps/or_map
import startest/expect
import watershed/channel
import watershed/or_map_kernel.{
  Increment, KeyRemoved, MvRegister, MvRegisterMode, MvRegisterUpdated, Register,
  RegisterMode, RegisterUpdated, Remove, SetMvRegister, Tally, TallyMode,
  TallyUpdated,
}

fn replica(name: String) -> replica_id.ReplicaId {
  replica_id.new(name)
}

fn new_tally(name: String) -> or_map_kernel.OrMapState {
  or_map_kernel.new(replica(name), TallyMode)
}

fn new_register(name: String) -> or_map_kernel.OrMapState {
  or_map_kernel.new(replica(name), RegisterMode)
}

fn expect_coherent(state: or_map_kernel.OrMapState) -> Nil {
  case or_map_kernel.check_cache_coherence(state) {
    Ok(Nil) -> Nil
    Error(detail) -> panic as detail
  }
}

fn increment(
  state: or_map_kernel.OrMapState,
  key: String,
  amount: Int,
) -> #(
  or_map_kernel.OrMapState,
  List(or_map_kernel.OrMapEvent),
  or_map_kernel.OrMapOperation,
  Int,
) {
  let assert Ok(result) = or_map_kernel.increment(state, key, amount)
  result
}

fn remove(
  state: or_map_kernel.OrMapState,
  key: String,
) -> #(
  or_map_kernel.OrMapState,
  List(or_map_kernel.OrMapEvent),
  or_map_kernel.OrMapOperation,
  Int,
) {
  let assert Ok(result) = or_map_kernel.remove(state, key)
  result
}

fn set_register(
  state: or_map_kernel.OrMapState,
  key: String,
  value: String,
  timestamp: Int,
) -> #(
  or_map_kernel.OrMapState,
  List(or_map_kernel.OrMapEvent),
  or_map_kernel.OrMapOperation,
  Int,
) {
  let assert Ok(result) =
    or_map_kernel.set_register(state, key, value, timestamp)
  result
}

fn remote(
  state: or_map_kernel.OrMapState,
  operation: or_map_kernel.OrMapOperation,
) -> #(or_map_kernel.OrMapState, List(or_map_kernel.OrMapEvent)) {
  let assert Ok(result) = or_map_kernel.apply_remote(state, operation)
  result
}

fn ack(
  state: or_map_kernel.OrMapState,
  operation: or_map_kernel.OrMapOperation,
) -> or_map_kernel.OrMapState {
  let assert Ok(state) = or_map_kernel.ack_local(state, operation)
  state
}

fn rollback(
  state: or_map_kernel.OrMapState,
  operation: or_map_kernel.OrMapOperation,
  message_id: Int,
) -> #(or_map_kernel.OrMapState, List(or_map_kernel.OrMapEvent)) {
  let assert Ok(result) = or_map_kernel.rollback(state, operation, message_id)
  result
}

fn expect_unexpected_ack(
  result: Result(or_map_kernel.OrMapState, or_map_kernel.KernelError),
) -> Nil {
  case result {
    Error(or_map_kernel.UnexpectedAck(_)) -> Nil
    Ok(_)
    | Error(or_map_kernel.UnexpectedRollback(_))
    | Error(or_map_kernel.ModeMismatch(_))
    | Error(or_map_kernel.CorruptDelta(_))
    | Error(or_map_kernel.NegativeTally(_))
    | Error(or_map_kernel.InvalidSetState(_))
    | Error(or_map_kernel.CounterExhausted(_)) ->
      panic as "expected UnexpectedAck"
  }
}

fn expect_unexpected_rollback(
  result: Result(
    #(or_map_kernel.OrMapState, List(or_map_kernel.OrMapEvent)),
    or_map_kernel.KernelError,
  ),
) -> Nil {
  case result {
    Error(or_map_kernel.UnexpectedRollback(_)) -> Nil
    Ok(_)
    | Error(or_map_kernel.UnexpectedAck(_))
    | Error(or_map_kernel.ModeMismatch(_))
    | Error(or_map_kernel.CorruptDelta(_))
    | Error(or_map_kernel.NegativeTally(_))
    | Error(or_map_kernel.InvalidSetState(_))
    | Error(or_map_kernel.CounterExhausted(_)) ->
      panic as "expected UnexpectedRollback"
  }
}

fn summary_counts(
  state: or_map_kernel.OrMapState,
  key: String,
  half: String,
) -> dict.Dict(String, Int) {
  let decoder =
    decode.at(
      ["state", "entries"],
      decode.list({
        use key <- decode.field("key", decode.string)
        use crdt <- decode.field("value", decode.string)
        decode.success(#(key, crdt))
      }),
    )
  let assert Ok(values) =
    json.parse(json.to_string(or_map_kernel.summary(state)), decoder)
  let assert Ok(#(_, crdt_json)) =
    values |> list.find(fn(entry) { entry.0 == key })
  let assert Ok(counts) =
    json.parse(
      crdt_json,
      decode.at(
        ["state", half, "counts"],
        decode.dict(decode.string, decode.int),
      ),
    )
  counts
}

pub fn new_state_is_empty_test() -> Nil {
  let state = new_tally("a")
  or_map_kernel.entries(state) |> expect.to_equal([])
  or_map_kernel.sequenced_entries(state) |> expect.to_equal([])
  state.pending |> expect.to_equal([])
}

pub fn increment_is_optimistically_visible_test() -> Nil {
  let #(state, events, operation, message_id) =
    increment(new_tally("a"), "spoil", 10)
  or_map_kernel.entries(state) |> expect.to_equal([#("spoil", Tally(10))])
  or_map_kernel.sequenced_entries(state) |> expect.to_equal([])
  events |> expect.to_equal([TallyUpdated("spoil", 10, 10)])
  message_id |> expect.to_equal(0)
  let assert Increment(key, amount, _) = operation
  key |> expect.to_equal("spoil")
  amount |> expect.to_equal(10)
  expect_coherent(state)
}

pub fn increment_mode_guard_test() -> Nil {
  case or_map_kernel.increment(new_register("a"), "spoil", 1) {
    Error(or_map_kernel.ModeMismatch(_)) -> Nil
    Ok(_)
    | Error(or_map_kernel.UnexpectedAck(_))
    | Error(or_map_kernel.UnexpectedRollback(_))
    | Error(or_map_kernel.CorruptDelta(_))
    | Error(or_map_kernel.NegativeTally(_))
    | Error(or_map_kernel.InvalidSetState(_))
    | Error(or_map_kernel.CounterExhausted(_)) ->
      panic as "expected ModeMismatch"
  }
}

pub fn set_register_mode_guard_test() -> Nil {
  case or_map_kernel.set_register(new_tally("a"), "handle", "x", 1) {
    Error(or_map_kernel.ModeMismatch(_)) -> Nil
    Ok(_)
    | Error(or_map_kernel.UnexpectedAck(_))
    | Error(or_map_kernel.UnexpectedRollback(_))
    | Error(or_map_kernel.CorruptDelta(_))
    | Error(or_map_kernel.NegativeTally(_))
    | Error(or_map_kernel.InvalidSetState(_))
    | Error(or_map_kernel.CounterExhausted(_)) ->
      panic as "expected ModeMismatch"
  }
}

pub fn remote_increment_applies_delta_and_emits_diff_test() -> Nil {
  let #(_, _, operation, _) = increment(new_tally("a"), "spoil", 7)
  let #(state, events) = remote(new_tally("b"), operation)
  or_map_kernel.entries(state) |> expect.to_equal([#("spoil", Tally(7))])
  or_map_kernel.sequenced_entries(state)
  |> expect.to_equal([#("spoil", Tally(7))])
  events |> expect.to_equal([TallyUpdated("spoil", 7, 7)])
  expect_coherent(state)
}

pub fn duplicate_remote_delta_is_idempotent_and_silent_test() -> Nil {
  let #(_, _, operation, _) = increment(new_tally("a"), "spoil", 3)
  let #(state, first_events) = remote(new_tally("b"), operation)
  let #(state, second_events) = remote(state, operation)
  or_map_kernel.entries(state) |> expect.to_equal([#("spoil", Tally(3))])
  first_events |> expect.to_equal([TallyUpdated("spoil", 3, 3)])
  second_events |> expect.to_equal([])
  expect_coherent(state)
}

pub fn ack_local_retires_pending_without_view_change_test() -> Nil {
  let #(state, _, operation, _) = increment(new_tally("a"), "spoil", 5)
  let state = ack(state, operation)
  or_map_kernel.entries(state) |> expect.to_equal([#("spoil", Tally(5))])
  or_map_kernel.sequenced_entries(state)
  |> expect.to_equal([#("spoil", Tally(5))])
  state.pending |> expect.to_equal([])
  expect_coherent(state)
}

pub fn ack_local_is_fifo_and_validates_message_id_test() -> Nil {
  let #(state, _, op1, id1) = increment(new_tally("a"), "a", 1)
  let #(state, _, op2, id2) = increment(state, "b", 2)
  expect_unexpected_ack(or_map_kernel.ack_local(state, op2))
  expect_unexpected_ack(or_map_kernel.ack_local_with_message_id(state, op1, id2))

  let assert Ok(state) =
    or_map_kernel.ack_local_with_message_id(state, op1, id1)
  let state = ack(state, op2)
  state.pending |> expect.to_equal([])
  or_map_kernel.entries(state)
  |> expect.to_equal([#("a", Tally(1)), #("b", Tally(2))])
}

pub fn ack_without_pending_is_an_error_test() -> Nil {
  let #(_, _, operation, _) = increment(new_tally("a"), "spoil", 1)
  expect_unexpected_ack(or_map_kernel.ack_local(new_tally("a"), operation))
}

pub fn rollback_undoes_newest_pending_and_reverts_own_tallies_test() -> Nil {
  let #(state, _, op1, _) = increment(new_tally("a"), "spoil", 12)
  let state = ack(state, op1)
  let #(state, _, remove_operation, _) = remove(state, "spoil")
  let state = ack(state, remove_operation)
  let #(state, _, op2, id2) = increment(state, "spoil", 5)

  let #(state, events) = rollback(state, op2, id2)
  or_map_kernel.entries(state) |> expect.to_equal([])
  events |> expect.to_equal([KeyRemoved("spoil")])

  let #(state, _, op3, _) = increment(state, "spoil", 1)
  let state = ack(state, op3)
  or_map_kernel.entries(state) |> expect.to_equal([#("spoil", Tally(13))])
  expect_coherent(state)
}

pub fn rollback_validates_newest_pending_metadata_test() -> Nil {
  let #(state, _, op1, id1) = increment(new_tally("a"), "a", 1)
  let #(state, _, op2, id2) = increment(state, "b", 2)
  expect_unexpected_rollback(or_map_kernel.rollback(state, op1, id1))
  expect_unexpected_rollback(or_map_kernel.rollback(state, op2, id2 + 1))
}

fn expect_rollback_preserves_key_tags(mode: or_map_kernel.OrMapMode) -> Nil {
  let write = case mode {
    TallyMode -> fn(state, key) { increment(state, key, 1) }
    RegisterMode -> fn(state, key) { set_register(state, key, "value", 1) }
    or_map_kernel.OrSetMode -> fn(state, key) {
      let assert Ok(submitted) = or_map_kernel.add_member(state, key, "value")
      submitted
    }
    MvRegisterMode -> fn(state, key) { write_mv(state, key, "value") }
  }
  let expected = case mode {
    TallyMode -> Tally(1)
    RegisterMode -> Register("value")
    or_map_kernel.OrSetMode -> or_map_kernel.SetMembers(["value"])
    MvRegisterMode -> MvRegister(["value"])
  }
  let #(state, _, first, message_id) =
    write(or_map_kernel.new(replica("author"), mode), "a")
  let #(state, _) = rollback(state, first, message_id)
  or_map_kernel.entries(state) |> expect.to_equal([])
  expect_coherent(state)
  let #(state, _, second, _) = write(state, "b")
  let assert Ok(#(state, _, replayed, _)) =
    or_map_kernel.apply_stashed_operation(state, first)
  replayed |> expect.to_equal(first)
  let #(state, events, removed, _) = remove(state, "a")
  or_map_kernel.entries(state) |> expect.to_equal([#("b", expected)])
  events |> expect.to_equal([KeyRemoved("a")])
  let state = ack(ack(ack(state, second), replayed), removed)
  expect_coherent(state)

  [[first, second, removed], [removed, second, first, removed]]
  |> list.each(fn(operations) {
    let peer =
      list.fold(
        operations,
        or_map_kernel.new(replica("peer"), mode),
        fn(peer, operation) { remote(peer, operation).0 },
      )
    or_map_kernel.entries(peer) |> expect.to_equal([#("b", expected)])
    expect_coherent(peer)
  })
}

pub fn mv_rollback_preserves_key_tags_test() -> Nil {
  expect_rollback_preserves_key_tags(MvRegisterMode)
}

pub fn tally_rollback_preserves_key_tags_test() -> Nil {
  expect_rollback_preserves_key_tags(TallyMode)
}

pub fn register_rollback_preserves_key_tags_test() -> Nil {
  expect_rollback_preserves_key_tags(RegisterMode)
}

pub fn set_rollback_preserves_key_tags_test() -> Nil {
  expect_rollback_preserves_key_tags(or_map_kernel.OrSetMode)
}

pub fn remove_of_present_key_hides_it_test() -> Nil {
  let #(state, _, operation, _) = increment(new_tally("a"), "spoil", 4)
  let state = ack(state, operation)
  let #(state, events, operation, _) = remove(state, "spoil")
  or_map_kernel.entries(state) |> expect.to_equal([])
  events |> expect.to_equal([KeyRemoved("spoil")])
  let assert Remove("spoil", _) = operation
  expect_coherent(state)
}

pub fn remove_of_absent_key_routes_without_event_test() -> Nil {
  let #(state, events, _, _) = remove(new_tally("a"), "missing")
  or_map_kernel.entries(state) |> expect.to_equal([])
  events |> expect.to_equal([])
  state.pending |> list.length |> expect.to_equal(1)
  expect_coherent(state)
}

pub fn concurrent_remove_and_increment_is_add_wins_in_both_orders_test() -> Nil {
  let #(a, _, seed, _) = increment(new_tally("a"), "spoil", 10)
  let a = ack(a, seed)
  let #(b, _) = remote(new_tally("b"), seed)

  let #(a_after_remove, _, remove_operation, _) = remove(a, "spoil")
  let #(b_after_increment, _, increment_operation, _) = increment(b, "spoil", 5)

  let #(a_observed, _) = remote(a_after_remove, increment_operation)
  let #(b_observed, _) = remote(b_after_increment, remove_operation)

  or_map_kernel.entries(a_observed) |> expect.to_equal([#("spoil", Tally(15))])
  or_map_kernel.entries(b_observed) |> expect.to_equal([#("spoil", Tally(15))])
  expect_coherent(a_observed)
  expect_coherent(b_observed)
}

pub fn remove_then_readd_resurrects_tally_test() -> Nil {
  let #(state, _, op1, _) = increment(new_tally("a"), "spoil", 12)
  let state = ack(state, op1)
  let #(state, _, op2, _) = remove(state, "spoil")
  let state = ack(state, op2)
  let #(state, _, op3, _) = increment(state, "spoil", 5)
  let state = ack(state, op3)

  or_map_kernel.entries(state) |> expect.to_equal([#("spoil", Tally(17))])
  expect_coherent(state)
}

pub fn author_and_peer_do_not_diverge_after_remove_then_readd_test() -> Nil {
  let #(author, _, seed, _) = increment(new_tally("a"), "spoil", 12)
  let author = ack(author, seed)
  let #(peer, _) = remote(new_tally("b"), seed)

  let #(author, _, remove_operation, _) = remove(author, "spoil")
  let author = ack(author, remove_operation)
  let #(peer, _) = remote(peer, remove_operation)
  let #(author, _, readd_operation, _) = increment(author, "spoil", 5)
  let author = ack(author, readd_operation)
  let #(peer, _) = remote(peer, readd_operation)

  or_map_kernel.entries(author) |> expect.to_equal([#("spoil", Tally(17))])
  or_map_kernel.entries(peer) |> expect.to_equal(or_map_kernel.entries(author))
}

pub fn register_lww_higher_timestamp_wins_test() -> Nil {
  let #(a, _, operation_a, _) =
    set_register(new_register("a"), "handle", "old", 10)
  let a = ack(a, operation_a)
  let #(b, _) = remote(new_register("b"), operation_a)
  let #(b, _, operation_b, _) = set_register(b, "handle", "new", 11)
  let b = ack(b, operation_b)
  let #(a, events) = remote(a, operation_b)

  or_map_kernel.get(a, "handle") |> expect.to_equal(Ok(Register("new")))
  or_map_kernel.entries(b) |> expect.to_equal([#("handle", Register("new"))])
  events |> expect.to_equal([RegisterUpdated("handle", "new")])
}

pub fn register_lww_equal_timestamp_uses_replica_id_tiebreak_test() -> Nil {
  let #(a, _, operation_a, _) =
    set_register(new_register("a"), "handle", "from-a", 10)
  let #(b, _, operation_b, _) =
    set_register(new_register("b"), "handle", "from-b", 10)
  let #(a, _) = remote(a, operation_b)
  let #(b, _) = remote(b, operation_a)

  or_map_kernel.entries(a) |> expect.to_equal([#("handle", Register("from-b"))])
  or_map_kernel.entries(b) |> expect.to_equal(or_map_kernel.entries(a))
}

pub fn summary_round_trip_rebrands_under_loader_identity_test() -> Nil {
  let #(state, _, operation_a, _) = increment(new_tally("a"), "spoil", 3)
  let state = ack(state, operation_a)
  let #(_, _, operation_b, _) = increment(new_tally("b"), "spoil", 4)
  let #(state, _) = remote(state, operation_b)

  let summary_json = json.to_string(or_map_kernel.summary(state))
  let assert Ok(loaded) = or_map_kernel.from_summary(summary_json, replica("c"))
  or_map_kernel.entries(loaded) |> expect.to_equal([#("spoil", Tally(7))])
  or_map.replica_id(loaded.sequenced) |> expect.to_equal(replica("c"))
  loaded.pending |> expect.to_equal([])

  let #(loaded, _, operation_c, _) = increment(loaded, "spoil", 1)
  let loaded = ack(loaded, operation_c)
  summary_counts(loaded, "spoil", "positive")
  |> expect.to_equal(dict.from_list([#("a", 3), #("b", 4), #("c", 1)]))
}

pub fn from_summary_rejects_invalid_or_unsupported_json_test() -> Nil {
  case or_map_kernel.from_summary("not json", replica("c")) {
    Error(_) -> Nil
    Ok(_) -> panic as "expected invalid JSON to fail"
  }

  let unsupported =
    or_map.new(replica("a"), crdt.GCounterSpec)
    |> or_map.to_json
    |> json.to_string
  case or_map_kernel.from_summary(unsupported, replica("c")) {
    Error(_) -> Nil
    Ok(_) -> panic as "expected unsupported spec to fail"
  }
}

pub fn summary_excludes_pending_and_later_delta_converges_test() -> Nil {
  let #(state, _, operation, _) = increment(new_tally("a"), "spoil", 9)
  let summary_json = json.to_string(or_map_kernel.summary(state))
  let assert Ok(loaded) = or_map_kernel.from_summary(summary_json, replica("b"))
  or_map_kernel.entries(loaded) |> expect.to_equal([])

  let #(loaded, _) = remote(loaded, operation)
  or_map_kernel.entries(loaded) |> expect.to_equal([#("spoil", Tally(9))])
  expect_coherent(loaded)
}

pub fn from_sequenced_rebrands_existing_map_test() -> Nil {
  let #(state, _, operation, _) = increment(new_tally("a"), "spoil", 2)
  let state = ack(state, operation)
  let assert Ok(loaded) =
    or_map_kernel.from_sequenced(state.sequenced, TallyMode, replica("c"))
  or_map.replica_id(loaded.sequenced) |> expect.to_equal(replica("c"))
  let #(loaded, _, operation_c, _) = increment(loaded, "spoil", 1)
  let loaded = ack(loaded, operation_c)
  summary_counts(loaded, "spoil", "positive")
  |> expect.to_equal(dict.from_list([#("a", 2), #("c", 1)]))
}

// ── Same-millisecond writes ──────────────────────────────────────────────────
//
// The timestamp a register is stamped with comes from the wall clock
// (`transport_js.now_milliseconds`), and `lww_register` accepts a write only
// when the timestamp is *strictly* greater than the one it holds. Two writes to
// one key inside the same millisecond therefore used to drop the second —
// silently, and even from the same replica, where "later" is not a matter of
// opinion.
//
// The kernel now keeps a per-key clock and stamps every local write above
// everything it has already seen for that key, from either end. That is a
// hybrid logical clock: wall-clock when the wall clock is moving, a counter
// when it is not.

pub fn a_second_write_in_the_same_millisecond_wins_test() -> Nil {
  let state = new_register("a")
  let #(state, _, _, _) = set_register(state, "cell", "7", 1000)
  let #(state, events, _, _) = set_register(state, "cell", "0", 1000)

  or_map_kernel.get(state, "cell")
  |> expect.to_equal(Ok(Register("0")))
  events
  |> expect.to_equal([RegisterUpdated("cell", "0")])
  expect_coherent(state)
}

/// A stalled clock must not stall the document: writes keep landing in order.
pub fn many_writes_in_one_millisecond_keep_their_order_test() -> Nil {
  let state =
    list.fold(["1", "2", "3", "4"], new_register("a"), fn(state, value) {
      let #(state, _, _, _) = set_register(state, "cell", value, 1000)
      state
    })

  or_map_kernel.get(state, "cell")
  |> expect.to_equal(Ok(Register("4")))
  expect_coherent(state)
}

/// A backwards clock — NTP correction, a suspended laptop — must not silently
/// freeze a key either.
pub fn a_write_with_an_older_timestamp_still_wins_locally_test() -> Nil {
  let state = new_register("a")
  let #(state, _, _, _) = set_register(state, "cell", "7", 5000)
  let #(state, _, _, _) = set_register(state, "cell", "0", 1000)

  or_map_kernel.get(state, "cell")
  |> expect.to_equal(Ok(Register("0")))
  expect_coherent(state)
}

/// The clock tracks what arrives from peers too, so a local write after a
/// remote one beats it rather than tying with it.
pub fn a_local_write_beats_a_remote_write_it_has_seen_test() -> Nil {
  let #(peer, _, remote_operation, _) =
    set_register(new_register("b"), "cell", "9", 4000)
  let _ = peer

  let #(state, _) = remote(new_register("a"), remote_operation)
  let #(state, _, _, _) = set_register(state, "cell", "3", 4000)

  or_map_kernel.get(state, "cell")
  |> expect.to_equal(Ok(Register("3")))
  expect_coherent(state)
}

/// Independent keys keep independent clocks: a busy key must not push an
/// untouched one into the future.
pub fn the_clock_is_per_key_test() -> Nil {
  let state = new_register("a")
  let #(state, _, _, _) = set_register(state, "busy", "1", 1000)
  let #(state, _, _, _) = set_register(state, "busy", "2", 1000)
  let #(state, _, quiet_operation, _) = set_register(state, "quiet", "x", 1000)

  case quiet_operation {
    or_map_kernel.SetRegister(_, _, timestamp, _) ->
      timestamp |> expect.to_equal(1000)
    or_map_kernel.Increment(..)
    | or_map_kernel.Remove(..)
    | or_map_kernel.AddMember(..)
    | or_map_kernel.SetMvRegister(..)
    | or_map_kernel.RemoveMember(..) -> panic as "expected a SetRegister op"
  }
  expect_coherent(state)
}

fn new_mv(name: String) -> or_map_kernel.OrMapState {
  or_map_kernel.new(replica(name), MvRegisterMode)
}

fn write_mv(
  state: or_map_kernel.OrMapState,
  key: String,
  value: String,
) -> #(
  or_map_kernel.OrMapState,
  List(or_map_kernel.OrMapEvent),
  or_map_kernel.OrMapOperation,
  Int,
) {
  let assert Ok(result) = or_map_kernel.set_mv_register(state, key, value)
  result
}

pub fn mv_write_is_optimistic_and_summary_excludes_pending_test() -> Nil {
  let empty = new_mv("a")
  or_map_kernel.entries(empty) |> expect.to_equal([])
  let #(state, events, operation, id) = write_mv(empty, "gate", "open")
  or_map_kernel.entries(state)
  |> expect.to_equal([#("gate", MvRegister(["open"]))])
  or_map_kernel.sequenced_entries(state) |> expect.to_equal([])
  events |> expect.to_equal([MvRegisterUpdated("gate", ["open"])])
  id |> expect.to_equal(0)
  let assert SetMvRegister("gate", "open", _) = operation
  let assert Ok(loaded) =
    or_map_kernel.from_summary(
      or_map_kernel.summary(state) |> json.to_string,
      replica("b"),
    )
  loaded.mode |> expect.to_equal(MvRegisterMode)
  or_map_kernel.entries(loaded) |> expect.to_equal([])
  expect_coherent(state)
}

pub fn mv_concurrent_writes_converge_and_resolution_replaces_both_test() -> Nil {
  let #(a, _, first, _) = write_mv(new_mv("a"), "gate", "z")
  let #(b, _, second, _) = write_mv(new_mv("b"), "gate", "a")
  let #(a, events) = remote(ack(a, first), second)
  let #(b, _) = remote(ack(b, second), first)
  or_map_kernel.get(a, "gate") |> expect.to_equal(Ok(MvRegister(["a", "z"])))
  or_map_kernel.entries(b) |> expect.to_equal(or_map_kernel.entries(a))
  events |> expect.to_equal([MvRegisterUpdated("gate", ["a", "z"])])
  let #(a, events, resolved, _) = write_mv(a, "gate", "chosen")
  let #(b, _) = remote(b, resolved)
  or_map_kernel.get(a, "gate") |> expect.to_equal(Ok(MvRegister(["chosen"])))
  or_map_kernel.entries(b) |> expect.to_equal(or_map_kernel.entries(a))
  events |> expect.to_equal([MvRegisterUpdated("gate", ["chosen"])])
  expect_coherent(a)
  expect_coherent(b)
}

pub fn mv_concurrent_equal_text_keeps_both_tags_test() -> Nil {
  let #(a, _, first, _) = write_mv(new_mv("a"), "gate", "same")
  let #(_, _, second, _) = write_mv(new_mv("b"), "gate", "same")
  let #(a, _) = remote(a, second)
  let a = ack(a, first)
  or_map_kernel.get(a, "gate")
  |> expect.to_equal(Ok(MvRegister(["same", "same"])))
  let #(a, events) = remote(a, second)
  events |> expect.to_equal([])
  or_map_kernel.get(a, "gate")
  |> expect.to_equal(Ok(MvRegister(["same", "same"])))
  expect_coherent(a)
}

pub fn mv_mutations_enforce_homogeneous_mode_test() -> Nil {
  let assert Error(or_map_kernel.ModeMismatch(_)) =
    or_map_kernel.increment(new_mv("a"), "gate", 1)
  let assert Error(or_map_kernel.ModeMismatch(_)) =
    or_map_kernel.set_register(new_mv("a"), "gate", "x", 1)
  let assert Error(or_map_kernel.ModeMismatch(_)) =
    or_map_kernel.p2p_increment(new_mv("a"), "gate", 1)
  let assert Error(or_map_kernel.ModeMismatch(_)) =
    or_map_kernel.p2p_set_register(new_mv("a"), "gate", "x", 1)
  [new_tally("a"), new_register("a")]
  |> list.each(fn(state) {
    let assert Error(or_map_kernel.ModeMismatch(_)) =
      or_map_kernel.set_mv_register(state, "gate", "x")
    let assert Error(or_map_kernel.ModeMismatch(_)) =
      or_map_kernel.p2p_set_mv_register(state, "gate", "x")
    Nil
  })
}

pub fn mv_remove_and_concurrent_write_is_add_wins_test() -> Nil {
  let #(a, _, seed, _) = write_mv(new_mv("a"), "gate", "old")
  let a = ack(a, seed)
  let #(b, _) = remote(new_mv("b"), seed)
  let #(a, _, removed, _) = remove(a, "gate")
  let #(b, _, written, _) = write_mv(b, "gate", "concurrent")
  let #(a, _) = remote(ack(a, removed), written)
  let #(b, _) = remote(ack(b, written), removed)
  or_map_kernel.get(a, "gate")
  |> expect.to_equal(Ok(MvRegister(["concurrent"])))
  or_map_kernel.entries(b) |> expect.to_equal(or_map_kernel.entries(a))
  expect_coherent(a)
  expect_coherent(b)
}

pub fn mv_remove_readd_does_not_resurrect_old_values_test() -> Nil {
  let #(a, _, first, _) = write_mv(new_mv("a"), "gate", "old")
  let a = ack(a, first)
  let #(a, _, removed, _) = remove(a, "gate")
  let a = ack(a, removed)
  let #(a, _, fresh, _) = write_mv(a, "gate", "fresh")
  let a = ack(a, fresh)
  let peer =
    list.fold([fresh, removed, first, first], new_mv("b"), fn(state, op) {
      remote(state, op).0
    })
  or_map_kernel.get(a, "gate") |> expect.to_equal(Ok(MvRegister(["fresh"])))
  or_map_kernel.entries(peer) |> expect.to_equal(or_map_kernel.entries(a))
  expect_coherent(peer)
}

pub fn mv_ack_is_fifo_and_rollback_is_lifo_without_tag_reuse_test() -> Nil {
  let #(a, _, first, first_id) = write_mv(new_mv("a"), "gate", "one")
  let #(a, _, second, second_id) = write_mv(a, "gate", "two")
  expect_unexpected_ack(or_map_kernel.ack_local(a, second))
  expect_unexpected_ack(or_map_kernel.ack_local_with_message_id(
    a,
    first,
    second_id,
  ))
  expect_unexpected_rollback(or_map_kernel.rollback(a, first, first_id))
  let #(a, events) = rollback(a, second, second_id)
  events |> expect.to_equal([MvRegisterUpdated("gate", ["one"])])
  let a = ack(a, first)
  let #(a, _, third, _) = write_mv(a, "gate", "three")
  let #(a, _) = remote(a, second)
  or_map_kernel.get(a, "gate") |> expect.to_equal(Ok(MvRegister(["three"])))
  let #(peer, _) = remote(new_mv("b"), second)
  let #(peer, _) = remote(peer, third)
  or_map_kernel.get(peer, "gate") |> expect.to_equal(Ok(MvRegister(["three"])))
  expect_coherent(a)
}

pub fn mv_stash_replays_original_delta_and_advances_author_clock_test() -> Nil {
  let #(_, _, stashed, _) = write_mv(new_mv("a"), "gate", "offline")
  let #(_, _, concurrent, _) = write_mv(new_mv("b"), "gate", "remote")
  let #(a, _) = remote(new_mv("a"), concurrent)
  let assert Ok(#(a, _, replayed, _)) =
    or_map_kernel.apply_stashed_operation(a, stashed)
  replayed |> expect.to_equal(stashed)
  or_map_kernel.get(a, "gate")
  |> expect.to_equal(Ok(MvRegister(["offline", "remote"])))
  let a = ack(a, replayed)
  let #(a, _, _, _) = write_mv(a, "gate", "resolved")
  let #(a, _) = remote(a, stashed)
  or_map_kernel.get(a, "gate") |> expect.to_equal(Ok(MvRegister(["resolved"])))
  expect_coherent(a)
}

pub fn mv_restart_and_full_merge_preserve_retired_history_test() -> Nil {
  let #(a, _, old, _) = write_mv(new_mv("a"), "gate", "old")
  let a = ack(a, old)
  let #(a, _, current, _) = write_mv(a, "gate", "current")
  let a = ack(a, current)
  let assert Ok(loaded) =
    or_map_kernel.from_summary(
      or_map_kernel.summary(a) |> json.to_string,
      replica("a"),
    )
  let assert Ok(attached) =
    or_map_kernel.from_sequenced(a.sequenced, MvRegisterMode, replica("b"))
  let assert Ok(#(merged, _)) =
    or_map_kernel.p2p_merge(new_mv("c"), a.sequenced)
  [loaded, attached, merged]
  |> list.each(fn(state) {
    let #(state, events) = remote(state, old)
    events |> expect.to_equal([])
    or_map_kernel.get(state, "gate")
    |> expect.to_equal(Ok(MvRegister(["current"])))
    let #(state, _, next, _) = write_mv(state, "gate", "next")
    let #(peer, _) = remote(a, next)
    or_map_kernel.get(peer, "gate") |> expect.to_equal(Ok(MvRegister(["next"])))
    expect_coherent(state)
  })
}

pub fn mv_removed_leaf_history_survives_restart_and_attach_test() -> Nil {
  let #(a, _, old, _) = write_mv(new_mv("a"), "gate", "old")
  let a = ack(a, old)
  let #(a, _, removed, _) = remove(a, "gate")
  let a = ack(a, removed)
  let assert Ok(loaded) =
    or_map_kernel.from_summary(
      or_map_kernel.summary(a) |> json.to_string,
      replica("a"),
    )
  let assert Ok(attached) =
    or_map_kernel.from_sequenced(a.sequenced, MvRegisterMode, replica("b"))
  let assert Ok(#(merged, _)) =
    or_map_kernel.p2p_merge(new_mv("c"), a.sequenced)
  [loaded, attached, merged]
  |> list.each(fn(state) {
    let #(state, _, next, _) = write_mv(state, "gate", "fresh")
    let #(state, _) = remote(state, old)
    or_map_kernel.get(state, "gate")
    |> expect.to_equal(Ok(MvRegister(["fresh"])))
    let #(peer, _) = remote(a, next)
    or_map_kernel.get(peer, "gate")
    |> expect.to_equal(Ok(MvRegister(["fresh"])))
    expect_coherent(state)
  })
}

pub fn mv_p2p_writes_are_confirmed_and_locally_branded_test() -> Nil {
  let assert Ok(#(a, events, first)) =
    or_map_kernel.p2p_set_mv_register(new_mv("a"), "gate", "one")
  events |> expect.to_equal([MvRegisterUpdated("gate", ["one"])])
  a.pending |> expect.to_equal([])
  a.next_pending_message_id |> expect.to_equal(0)
  let assert Ok(#(b, _)) = or_map_kernel.p2p_merge(new_mv("b"), a.sequenced)
  let assert Ok(#(a, _, second)) =
    or_map_kernel.p2p_set_mv_register(a, "gate", "two")
  let assert Ok(#(b, _, third)) =
    or_map_kernel.p2p_set_mv_register(b, "gate", "three")
  let #(a, _) = remote(a, third)
  let #(b, _) = remote(b, second)
  let #(b, _) = remote(b, first)
  or_map_kernel.get(a, "gate")
  |> expect.to_equal(Ok(MvRegister(["three", "two"])))
  or_map_kernel.entries(b) |> expect.to_equal(or_map_kernel.entries(a))
  expect_coherent(a)
  expect_coherent(b)
}

pub fn mv_summary_rejects_duplicate_tags_and_negative_counters_test() -> Nil {
  let #(state, _, operation, _) = write_mv(new_mv("a"), "gate", "one")
  let source = or_map_kernel.summary(ack(state, operation)) |> json.to_string
  let assert Ok(values) =
    json.parse(
      source,
      decode.at(
        ["state", "entries"],
        decode.list({
          use leaf <- decode.field("value", decode.string)
          decode.success(leaf)
        }),
      ),
    )
  let assert [leaf] = values
  let invalid_leaves = [
    "{\"type\":\"mv_register\",\"v\":1,\"state\":{\"replica_id\":\"a\",\"entries\":[{\"tag\":{\"r\":\"a\",\"c\":1},\"value\":\"one\"},{\"tag\":{\"r\":\"a\",\"c\":1},\"value\":\"other\"}],\"vclock\":{\"a\":1}}}",
    "{\"type\":\"mv_register\",\"v\":1,\"state\":{\"replica_id\":\"a\",\"entries\":[],\"vclock\":{\"a\":-1}}}",
  ]
  invalid_leaves
  |> list.each(fn(invalid) {
    let corrupted =
      string.replace(
        source,
        json.string(leaf) |> json.to_string,
        json.string(invalid) |> json.to_string,
      )
    corrupted |> expect.to_not_equal(source)
    or_map_kernel.from_summary(corrupted, replica("b"))
    |> expect.to_be_error()
  })
}

pub fn mv_full_merge_rejects_negative_clock_before_join_test() -> Nil {
  let #(state, _, operation, _) = write_mv(new_mv("a"), "gate", "one")
  let state = ack(state, operation)
  let source = or_map_kernel.summary(state) |> json.to_string
  let assert Ok(values) =
    json.parse(
      source,
      decode.at(
        ["state", "entries"],
        decode.list({
          use leaf <- decode.field("value", decode.string)
          decode.success(leaf)
        }),
      ),
    )
  let assert [leaf] = values
  let invalid =
    "{\"type\":\"mv_register\",\"v\":1,\"state\":{\"replica_id\":\"a\",\"entries\":[],\"vclock\":{\"a\":-1}}}"
  let corrupted =
    string.replace(
      source,
      json.string(leaf) |> json.to_string,
      json.string(invalid) |> json.to_string,
    )
  corrupted |> expect.to_not_equal(source)
  // The native decoder now rejects this clock before a typed map can reach a join.
  or_map.from_json(corrupted) |> expect.to_be_error()
  json.parse(corrupted, channel.snapshot_decoder(channel.OrMapChannel))
  |> expect.to_be_error()
  let assert Ok(snapshot) =
    json.parse(source, channel.snapshot_decoder(channel.OrMapChannel))
  let assert Ok(#(unchanged, events)) =
    channel.merge_p2p_snapshot(channel.OrMapState(state), snapshot)
  unchanged |> expect.to_equal(channel.OrMapState(state))
  events |> expect.to_equal([])
}
