import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{Some}
import lattice_core/replica_id
import lattice_maps/crdt
import lattice_maps/or_map
import startest/expect
import watershed/or_map_kernel.{
  Increment, KeyRemoved, Register, RegisterMode, RegisterUpdated, Remove, Tally,
  TallyMode, TallyUpdated,
}

fn rid(name: String) -> replica_id.ReplicaId {
  replica_id.new(name)
}

fn new_tally(name: String) -> or_map_kernel.OrMapState {
  or_map_kernel.new(rid(name), TallyMode)
}

fn new_register(name: String) -> or_map_kernel.OrMapState {
  or_map_kernel.new(rid(name), RegisterMode)
}

fn expect_coherent(state: or_map_kernel.OrMapState) -> Nil {
  case or_map_kernel.check_cache_coherence(state) {
    Ok(Nil) -> Nil
    Error(detail) -> panic as detail
  }
}

fn inc(
  state: or_map_kernel.OrMapState,
  key: String,
  amount: Int,
) -> #(
  or_map_kernel.OrMapState,
  List(or_map_kernel.OrMapEvent),
  or_map_kernel.OrMapOp,
  Int,
) {
  let assert Ok(result) = or_map_kernel.increment(state, key, amount)
  result
}

fn set_reg(
  state: or_map_kernel.OrMapState,
  key: String,
  value: String,
  timestamp: Int,
) -> #(
  or_map_kernel.OrMapState,
  List(or_map_kernel.OrMapEvent),
  or_map_kernel.OrMapOp,
  Int,
) {
  let assert Ok(result) =
    or_map_kernel.set_register(state, key, value, timestamp)
  result
}

fn remote(
  state: or_map_kernel.OrMapState,
  op: or_map_kernel.OrMapOp,
) -> #(or_map_kernel.OrMapState, List(or_map_kernel.OrMapEvent)) {
  let assert Ok(result) = or_map_kernel.apply_remote(state, op)
  result
}

fn ack(
  state: or_map_kernel.OrMapState,
  op: or_map_kernel.OrMapOp,
) -> or_map_kernel.OrMapState {
  let assert Ok(state) = or_map_kernel.ack_local(state, op)
  state
}

fn rollback(
  state: or_map_kernel.OrMapState,
  op: or_map_kernel.OrMapOp,
  message_id: Int,
) -> #(or_map_kernel.OrMapState, List(or_map_kernel.OrMapEvent)) {
  let assert Ok(result) = or_map_kernel.rollback(state, op, message_id)
  result
}

fn expect_unexpected_ack(
  result: Result(or_map_kernel.OrMapState, or_map_kernel.KernelError),
) {
  case result {
    Error(or_map_kernel.UnexpectedAck(_)) -> Nil
    _ -> panic as "expected UnexpectedAck"
  }
}

fn expect_unexpected_rollback(
  result: Result(
    #(or_map_kernel.OrMapState, List(or_map_kernel.OrMapEvent)),
    or_map_kernel.KernelError,
  ),
) {
  case result {
    Error(or_map_kernel.UnexpectedRollback(_)) -> Nil
    _ -> panic as "expected UnexpectedRollback"
  }
}

fn summary_counts(
  state: or_map_kernel.OrMapState,
  key: String,
  half: String,
) -> dict.Dict(String, Int) {
  let decoder =
    decode.at(
      ["state", "values"],
      decode.list({
        use key <- decode.field("key", decode.string)
        use crdt <- decode.field("crdt", decode.string)
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

pub fn new_state_is_empty_test() {
  let state = new_tally("a")
  or_map_kernel.entries(state) |> expect.to_equal([])
  or_map_kernel.sequenced_entries(state) |> expect.to_equal([])
  state.pending |> expect.to_equal([])
}

pub fn increment_is_optimistically_visible_test() {
  let #(state, events, op, message_id) = inc(new_tally("a"), "spoil", 10)
  or_map_kernel.entries(state) |> expect.to_equal([#("spoil", Tally(10))])
  or_map_kernel.sequenced_entries(state) |> expect.to_equal([])
  events |> expect.to_equal([TallyUpdated("spoil", 10, 10)])
  message_id |> expect.to_equal(0)
  let assert Increment(key, amount, _) = op
  key |> expect.to_equal("spoil")
  amount |> expect.to_equal(10)
  expect_coherent(state)
}

pub fn increment_mode_guard_test() {
  case or_map_kernel.increment(new_register("a"), "spoil", 1) {
    Error(or_map_kernel.ModeMismatch(_)) -> Nil
    _ -> panic as "expected ModeMismatch"
  }
}

pub fn set_register_mode_guard_test() {
  case or_map_kernel.set_register(new_tally("a"), "handle", "x", 1) {
    Error(or_map_kernel.ModeMismatch(_)) -> Nil
    _ -> panic as "expected ModeMismatch"
  }
}

pub fn remote_increment_applies_delta_and_emits_diff_test() {
  let #(_, _, op, _) = inc(new_tally("a"), "spoil", 7)
  let #(state, events) = remote(new_tally("b"), op)
  or_map_kernel.entries(state) |> expect.to_equal([#("spoil", Tally(7))])
  or_map_kernel.sequenced_entries(state)
  |> expect.to_equal([#("spoil", Tally(7))])
  events |> expect.to_equal([TallyUpdated("spoil", 7, 7)])
  expect_coherent(state)
}

pub fn duplicate_remote_delta_is_idempotent_and_silent_test() {
  let #(_, _, op, _) = inc(new_tally("a"), "spoil", 3)
  let #(state, first_events) = remote(new_tally("b"), op)
  let #(state, second_events) = remote(state, op)
  or_map_kernel.entries(state) |> expect.to_equal([#("spoil", Tally(3))])
  first_events |> expect.to_equal([TallyUpdated("spoil", 3, 3)])
  second_events |> expect.to_equal([])
  expect_coherent(state)
}

pub fn ack_local_retires_pending_without_view_change_test() {
  let #(state, _, op, _) = inc(new_tally("a"), "spoil", 5)
  let state = ack(state, op)
  or_map_kernel.entries(state) |> expect.to_equal([#("spoil", Tally(5))])
  or_map_kernel.sequenced_entries(state)
  |> expect.to_equal([#("spoil", Tally(5))])
  state.pending |> expect.to_equal([])
  expect_coherent(state)
}

pub fn ack_local_is_fifo_and_validates_message_id_test() {
  let #(state, _, op1, id1) = inc(new_tally("a"), "a", 1)
  let #(state, _, op2, id2) = inc(state, "b", 2)
  expect_unexpected_ack(or_map_kernel.ack_local(state, op2))
  expect_unexpected_ack(or_map_kernel.ack_local_with_message_id(state, op1, id2))

  let assert Ok(state) =
    or_map_kernel.ack_local_with_message_id(state, op1, id1)
  let state = ack(state, op2)
  state.pending |> expect.to_equal([])
  or_map_kernel.entries(state)
  |> expect.to_equal([#("a", Tally(1)), #("b", Tally(2))])
}

pub fn ack_without_pending_is_an_error_test() {
  let #(_, _, op, _) = inc(new_tally("a"), "spoil", 1)
  expect_unexpected_ack(or_map_kernel.ack_local(new_tally("a"), op))
}

pub fn rollback_undoes_newest_pending_and_reverts_own_tallies_test() {
  let #(state, _, op1, _) = inc(new_tally("a"), "spoil", 12)
  let state = ack(state, op1)
  let #(state, _, remove_op, _) = or_map_kernel.remove(state, "spoil")
  let state = ack(state, remove_op)
  let #(state, _, op2, id2) = inc(state, "spoil", 5)

  let #(state, events) = rollback(state, op2, id2)
  or_map_kernel.entries(state) |> expect.to_equal([])
  events |> expect.to_equal([KeyRemoved("spoil")])

  let #(state, _, op3, _) = inc(state, "spoil", 1)
  let state = ack(state, op3)
  or_map_kernel.entries(state) |> expect.to_equal([#("spoil", Tally(13))])
  expect_coherent(state)
}

pub fn rollback_validates_newest_pending_metadata_test() {
  let #(state, _, op1, id1) = inc(new_tally("a"), "a", 1)
  let #(state, _, op2, id2) = inc(state, "b", 2)
  expect_unexpected_rollback(or_map_kernel.rollback(state, op1, id1))
  expect_unexpected_rollback(or_map_kernel.rollback(state, op2, id2 + 1))
}

pub fn remove_of_present_key_hides_it_test() {
  let #(state, _, op, _) = inc(new_tally("a"), "spoil", 4)
  let state = ack(state, op)
  let #(state, events, op, _) = or_map_kernel.remove(state, "spoil")
  or_map_kernel.entries(state) |> expect.to_equal([])
  events |> expect.to_equal([KeyRemoved("spoil")])
  let assert Remove("spoil", _) = op
  expect_coherent(state)
}

pub fn remove_of_absent_key_routes_without_event_test() {
  let #(state, events, _, _) = or_map_kernel.remove(new_tally("a"), "missing")
  or_map_kernel.entries(state) |> expect.to_equal([])
  events |> expect.to_equal([])
  state.pending |> list.length |> expect.to_equal(1)
  expect_coherent(state)
}

pub fn concurrent_remove_and_increment_is_add_wins_in_both_orders_test() {
  let #(a, _, seed, _) = inc(new_tally("a"), "spoil", 10)
  let a = ack(a, seed)
  let #(b, _) = remote(new_tally("b"), seed)

  let #(a_after_remove, _, remove_op, _) = or_map_kernel.remove(a, "spoil")
  let #(b_after_increment, _, increment_op, _) = inc(b, "spoil", 5)

  let #(a_observed, _) = remote(a_after_remove, increment_op)
  let #(b_observed, _) = remote(b_after_increment, remove_op)

  or_map_kernel.entries(a_observed) |> expect.to_equal([#("spoil", Tally(15))])
  or_map_kernel.entries(b_observed) |> expect.to_equal([#("spoil", Tally(15))])
  expect_coherent(a_observed)
  expect_coherent(b_observed)
}

pub fn remove_then_readd_resurrects_tally_test() {
  let #(state, _, op1, _) = inc(new_tally("a"), "spoil", 12)
  let state = ack(state, op1)
  let #(state, _, op2, _) = or_map_kernel.remove(state, "spoil")
  let state = ack(state, op2)
  let #(state, _, op3, _) = inc(state, "spoil", 5)
  let state = ack(state, op3)

  or_map_kernel.entries(state) |> expect.to_equal([#("spoil", Tally(17))])
  expect_coherent(state)
}

pub fn author_and_peer_do_not_diverge_after_remove_then_readd_test() {
  let #(author, _, seed, _) = inc(new_tally("a"), "spoil", 12)
  let author = ack(author, seed)
  let #(peer, _) = remote(new_tally("b"), seed)

  let #(author, _, remove_op, _) = or_map_kernel.remove(author, "spoil")
  let author = ack(author, remove_op)
  let #(peer, _) = remote(peer, remove_op)
  let #(author, _, readd_op, _) = inc(author, "spoil", 5)
  let author = ack(author, readd_op)
  let #(peer, _) = remote(peer, readd_op)

  or_map_kernel.entries(author) |> expect.to_equal([#("spoil", Tally(17))])
  or_map_kernel.entries(peer) |> expect.to_equal(or_map_kernel.entries(author))
}

pub fn register_lww_higher_timestamp_wins_test() {
  let #(a, _, op_a, _) = set_reg(new_register("a"), "handle", "old", 10)
  let a = ack(a, op_a)
  let #(b, _) = remote(new_register("b"), op_a)
  let #(b, _, op_b, _) = set_reg(b, "handle", "new", 11)
  let b = ack(b, op_b)
  let #(a, events) = remote(a, op_b)

  or_map_kernel.get(a, "handle") |> expect.to_equal(Some(Register("new")))
  or_map_kernel.entries(b) |> expect.to_equal([#("handle", Register("new"))])
  events |> expect.to_equal([RegisterUpdated("handle", "new")])
}

pub fn register_lww_equal_timestamp_uses_replica_id_tiebreak_test() {
  let #(a, _, op_a, _) = set_reg(new_register("a"), "handle", "from-a", 10)
  let #(b, _, op_b, _) = set_reg(new_register("b"), "handle", "from-b", 10)
  let #(a, _) = remote(a, op_b)
  let #(b, _) = remote(b, op_a)

  or_map_kernel.entries(a) |> expect.to_equal([#("handle", Register("from-b"))])
  or_map_kernel.entries(b) |> expect.to_equal(or_map_kernel.entries(a))
}

pub fn summary_round_trip_rebrands_under_loader_identity_test() {
  let #(state, _, op_a, _) = inc(new_tally("a"), "spoil", 3)
  let state = ack(state, op_a)
  let #(_, _, op_b, _) = inc(new_tally("b"), "spoil", 4)
  let #(state, _) = remote(state, op_b)

  let summary_json = json.to_string(or_map_kernel.summary(state))
  let assert Ok(loaded) = or_map_kernel.from_summary(summary_json, rid("c"))
  or_map_kernel.entries(loaded) |> expect.to_equal([#("spoil", Tally(7))])
  loaded.pending |> expect.to_equal([])

  let #(loaded, _, op_c, _) = inc(loaded, "spoil", 1)
  let loaded = ack(loaded, op_c)
  summary_counts(loaded, "spoil", "positive")
  |> expect.to_equal(dict.from_list([#("a", 3), #("b", 4), #("c", 1)]))
}

pub fn from_summary_rejects_invalid_or_unsupported_json_test() {
  case or_map_kernel.from_summary("not json", rid("c")) {
    Error(_) -> Nil
    Ok(_) -> panic as "expected invalid JSON to fail"
  }

  let unsupported =
    or_map.new(rid("a"), crdt.GCounterSpec)
    |> or_map.to_json
    |> json.to_string
  case or_map_kernel.from_summary(unsupported, rid("c")) {
    Error(_) -> Nil
    Ok(_) -> panic as "expected unsupported spec to fail"
  }
}

pub fn summary_excludes_pending_and_later_delta_converges_test() {
  let #(state, _, op, _) = inc(new_tally("a"), "spoil", 9)
  let summary_json = json.to_string(or_map_kernel.summary(state))
  let assert Ok(loaded) = or_map_kernel.from_summary(summary_json, rid("b"))
  or_map_kernel.entries(loaded) |> expect.to_equal([])

  let #(loaded, _) = remote(loaded, op)
  or_map_kernel.entries(loaded) |> expect.to_equal([#("spoil", Tally(9))])
  expect_coherent(loaded)
}

pub fn from_sequenced_rebrands_existing_map_test() {
  let #(state, _, op, _) = inc(new_tally("a"), "spoil", 2)
  let state = ack(state, op)
  let assert Ok(loaded) =
    or_map_kernel.from_sequenced(state.sequenced, TallyMode, rid("c"))
  let #(loaded, _, op_c, _) = inc(loaded, "spoil", 1)
  let loaded = ack(loaded, op_c)
  summary_counts(loaded, "spoil", "positive")
  |> expect.to_equal(dict.from_list([#("a", 2), #("c", 1)]))
}
