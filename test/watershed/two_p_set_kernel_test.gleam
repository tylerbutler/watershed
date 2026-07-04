import gleam/json
import startest/expect
import watershed/two_p_set_kernel.{ElementAdded, ElementRemoved}

fn expect_coherent(state: two_p_set_kernel.TwoPSetState) -> Nil {
  case two_p_set_kernel.check_cache_coherence(state) {
    Ok(Nil) -> Nil
    Error(detail) -> panic as detail
  }
}

fn ack(
  state: two_p_set_kernel.TwoPSetState,
  op: two_p_set_kernel.TwoPSetOp,
) -> two_p_set_kernel.TwoPSetState {
  let assert Ok(state) = two_p_set_kernel.ack_local(state, op)
  state
}

pub fn add_is_optimistically_visible_test() {
  let #(state, events, op, message_id) =
    two_p_set_kernel.add(two_p_set_kernel.new(), "stake-3")

  two_p_set_kernel.values(state) |> expect.to_equal(["stake-3"])
  two_p_set_kernel.sequenced_values(state) |> expect.to_equal([])
  events |> expect.to_equal([ElementAdded("stake-3")])
  message_id |> expect.to_equal(0)
  let assert two_p_set_kernel.Add("stake-3", _) = op
  expect_coherent(state)
}

pub fn add_then_remove_removes_active_membership_test() {
  let #(state, _, add_op, _) =
    two_p_set_kernel.add(two_p_set_kernel.new(), "stake-3")
  let state = ack(state, add_op)
  let #(state, events, remove_op, _) = two_p_set_kernel.remove(state, "stake-3")
  let state = ack(state, remove_op)

  two_p_set_kernel.values(state) |> expect.to_equal([])
  two_p_set_kernel.contains(state, "stake-3") |> expect.to_equal(False)
  events |> expect.to_equal([ElementRemoved("stake-3")])
  expect_coherent(state)
}

pub fn remove_then_add_keeps_element_inactive_test() {
  let #(state, remove_events, remove_op, _) =
    two_p_set_kernel.remove(two_p_set_kernel.new(), "stake-3")
  let state = ack(state, remove_op)
  let #(state, add_events, add_op, _) = two_p_set_kernel.add(state, "stake-3")
  let state = ack(state, add_op)

  two_p_set_kernel.values(state) |> expect.to_equal([])
  remove_events |> expect.to_equal([])
  add_events |> expect.to_equal([])
  expect_coherent(state)
}

pub fn concurrent_add_remove_converges_to_removed_test() {
  let #(_, _, add_op, _) =
    two_p_set_kernel.add(two_p_set_kernel.new(), "stake-3")
  let #(_, _, remove_op, _) =
    two_p_set_kernel.remove(two_p_set_kernel.new(), "stake-3")

  let #(observer, add_events) =
    two_p_set_kernel.apply_remote(two_p_set_kernel.new(), add_op)
  let #(observer, remove_events) =
    two_p_set_kernel.apply_remote(observer, remove_op)
  let #(other_order, _) =
    two_p_set_kernel.apply_remote(two_p_set_kernel.new(), remove_op)
  let #(other_order, other_add_events) =
    two_p_set_kernel.apply_remote(other_order, add_op)

  two_p_set_kernel.values(observer) |> expect.to_equal([])
  two_p_set_kernel.values(other_order) |> expect.to_equal([])
  add_events |> expect.to_equal([ElementAdded("stake-3")])
  remove_events |> expect.to_equal([ElementRemoved("stake-3")])
  other_add_events |> expect.to_equal([])
  expect_coherent(observer)
  expect_coherent(other_order)
}

pub fn duplicate_remove_is_idempotent_test() {
  let #(_, _, op, _) =
    two_p_set_kernel.remove(two_p_set_kernel.new(), "stake-3")
  let #(state, first_events) =
    two_p_set_kernel.apply_remote(two_p_set_kernel.new(), op)
  let #(state, second_events) = two_p_set_kernel.apply_remote(state, op)

  two_p_set_kernel.values(state) |> expect.to_equal([])
  first_events |> expect.to_equal([])
  second_events |> expect.to_equal([])
  expect_coherent(state)
}

pub fn rollback_pending_remove_restores_active_membership_test() {
  let #(state, _, add_op, _) =
    two_p_set_kernel.add(two_p_set_kernel.new(), "stake-3")
  let state = ack(state, add_op)
  let #(state, _, remove_op, message_id) =
    two_p_set_kernel.remove(state, "stake-3")
  let assert Ok(#(state, events)) =
    two_p_set_kernel.rollback(state, remove_op, message_id)

  two_p_set_kernel.values(state) |> expect.to_equal(["stake-3"])
  events |> expect.to_equal([ElementAdded("stake-3")])
  expect_coherent(state)
}

pub fn summary_round_trips_tombstones_test() {
  let #(state, _, add_op, _) =
    two_p_set_kernel.add(two_p_set_kernel.new(), "stake-3")
  let state = ack(state, add_op)
  let #(state, _, remove_op, _) = two_p_set_kernel.remove(state, "stake-3")
  let state = ack(state, remove_op)

  let raw = json.to_string(two_p_set_kernel.summary(state))
  let assert Ok(loaded) = two_p_set_kernel.from_summary(raw)
  let #(loaded, events, add_again, _) = two_p_set_kernel.add(loaded, "stake-3")
  let loaded = ack(loaded, add_again)

  two_p_set_kernel.values(loaded) |> expect.to_equal([])
  events |> expect.to_equal([])
  loaded.pending |> expect.to_equal([])
}
