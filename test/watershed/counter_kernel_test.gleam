import startest/expect
import watershed/counter_kernel.{Increment, Incremented, PendingIncrement}

fn ack(
  state: counter_kernel.CounterState,
  op: counter_kernel.CounterOp,
) -> counter_kernel.CounterState {
  case counter_kernel.ack_local(state, op) {
    Ok(state) -> state
    Error(_) -> panic as "expected ack to succeed"
  }
}

fn rollback(
  state: counter_kernel.CounterState,
  op: counter_kernel.CounterOp,
  message_id: Int,
) -> #(counter_kernel.CounterState, List(counter_kernel.CounterEvent)) {
  case counter_kernel.rollback(state, op, message_id) {
    Ok(result) -> result
    Error(_) -> panic as "expected rollback to succeed"
  }
}

fn expect_unexpected_ack(
  result: Result(counter_kernel.CounterState, counter_kernel.KernelError),
) {
  case result {
    Error(counter_kernel.UnexpectedAck(_, _)) -> Nil
    _ -> panic as "expected UnexpectedAck error"
  }
}

fn expect_unexpected_rollback(
  result: Result(
    #(counter_kernel.CounterState, List(counter_kernel.CounterEvent)),
    counter_kernel.KernelError,
  ),
) {
  case result {
    Error(counter_kernel.UnexpectedRollback(_, _)) -> Nil
    _ -> panic as "expected UnexpectedRollback error"
  }
}

pub fn new_counter_is_zero_test() {
  let state = counter_kernel.new()
  state.value |> expect.to_equal(0)
  state.pending |> expect.to_equal([])
  counter_kernel.summary_value(state) |> expect.to_equal(0)
}

pub fn increment_is_optimistically_visible_test() {
  let #(state, events, op, message_id) =
    counter_kernel.increment(counter_kernel.new(), 10)
  state.value |> expect.to_equal(10)
  state.pending |> expect.to_equal([PendingIncrement(10, 0)])
  op |> expect.to_equal(Increment(10))
  message_id |> expect.to_equal(0)
  events |> expect.to_equal([Incremented(10, 10)])
}

pub fn increment_accepts_negative_and_zero_amounts_test() {
  let #(state, _, _, _) = counter_kernel.increment(counter_kernel.new(), -3)
  state.value |> expect.to_equal(-3)
  let #(state, events, _, _) = counter_kernel.increment(state, 0)
  state.value |> expect.to_equal(-3)
  events |> expect.to_equal([Incremented(0, -3)])
}

pub fn remote_increment_applies_delta_and_emits_event_test() {
  let #(state, events) =
    counter_kernel.apply_remote(counter_kernel.new(), Increment(7))
  state.value |> expect.to_equal(7)
  state.pending |> expect.to_equal([])
  events |> expect.to_equal([Incremented(7, 7)])
}

pub fn concurrent_increments_converge_test() {
  let #(client_a, _, op_a, _) =
    counter_kernel.increment(counter_kernel.new(), 10)
  let #(client_b, _, op_b, _) =
    counter_kernel.increment(counter_kernel.new(), 20)

  let client_a = ack(client_a, op_a)
  let #(client_a, _) = counter_kernel.apply_remote(client_a, op_b)

  let #(client_b, _) = counter_kernel.apply_remote(client_b, op_a)
  let client_b = ack(client_b, op_b)

  client_a.value |> expect.to_equal(30)
  client_b.value |> expect.to_equal(30)
}

pub fn ack_local_removes_pending_without_event_or_value_change_test() {
  let #(state, _, op, _) = counter_kernel.increment(counter_kernel.new(), 5)
  let state = ack(state, op)
  state.value |> expect.to_equal(5)
  state.pending |> expect.to_equal([])
}

pub fn ack_local_is_fifo_test() {
  let #(state, _, op1, _) = counter_kernel.increment(counter_kernel.new(), 1)
  let #(state, _, op2, _) = counter_kernel.increment(state, 2)
  expect_unexpected_ack(counter_kernel.ack_local(state, op2))

  let state = ack(state, op1)
  state.pending |> expect.to_equal([PendingIncrement(2, 1)])
  let state = ack(state, op2)
  state.pending |> expect.to_equal([])
  state.value |> expect.to_equal(3)
}

pub fn ack_local_with_message_id_validates_metadata_test() {
  let #(state, _, op, message_id) =
    counter_kernel.increment(counter_kernel.new(), 4)
  expect_unexpected_ack(counter_kernel.ack_local_with_message_id(
    state,
    op,
    message_id + 1,
  ))

  let assert Ok(state) =
    counter_kernel.ack_local_with_message_id(state, op, message_id)
  state.pending |> expect.to_equal([])
}

pub fn ack_without_pending_is_an_error_test() {
  expect_unexpected_ack(counter_kernel.ack_local(
    counter_kernel.new(),
    Increment(1),
  ))
}

pub fn apply_stashed_op_reuses_increment_path_test() {
  let #(state, events, op, message_id) =
    counter_kernel.apply_stashed_op(counter_kernel.new(), Increment(9))
  state.value |> expect.to_equal(9)
  state.pending |> expect.to_equal([PendingIncrement(9, 0)])
  events |> expect.to_equal([Incremented(9, 9)])
  op |> expect.to_equal(Increment(9))
  message_id |> expect.to_equal(0)
}

pub fn rollback_undoes_newest_pending_increment_test() {
  let #(state, _, _, _) = counter_kernel.increment(counter_kernel.new(), 10)
  let #(state, _, op2, message_id2) = counter_kernel.increment(state, -3)

  let #(state, events) = rollback(state, op2, message_id2)
  state.value |> expect.to_equal(10)
  state.pending |> expect.to_equal([PendingIncrement(10, 0)])
  events |> expect.to_equal([Incremented(3, 10)])
}

pub fn rollback_validates_newest_pending_metadata_test() {
  let #(state, _, _op1, _) = counter_kernel.increment(counter_kernel.new(), 1)
  let #(state, _, op2, message_id2) = counter_kernel.increment(state, 2)

  expect_unexpected_rollback(counter_kernel.rollback(state, Increment(1), 0))
  expect_unexpected_rollback(counter_kernel.rollback(
    state,
    op2,
    message_id2 + 1,
  ))

  let #(state, _) = rollback(state, op2, message_id2)
  state.value |> expect.to_equal(1)
}

pub fn rollback_across_remote_ops_preserves_remote_delta_test() {
  let #(state, _, op, message_id) =
    counter_kernel.increment(counter_kernel.new(), 10)
  let #(state, _) = counter_kernel.apply_remote(state, Increment(20))

  let #(state, events) = rollback(state, op, message_id)
  state.value |> expect.to_equal(20)
  state.pending |> expect.to_equal([])
  events |> expect.to_equal([Incremented(-10, 20)])
}

pub fn rollback_without_pending_is_an_error_test() {
  expect_unexpected_rollback(counter_kernel.rollback(
    counter_kernel.new(),
    Increment(1),
    0,
  ))
}

pub fn from_summary_round_trips_value_test() {
  let state = counter_kernel.from_summary(42)
  state.value |> expect.to_equal(42)
  state.pending |> expect.to_equal([])
  counter_kernel.summary_value(state) |> expect.to_equal(42)
}
