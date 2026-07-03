//// Pure port of FluidFramework's `packages/dds/counter/src/counter.ts`.
////
//// SharedCounter is a delta-based integer DDS: every op is an increment
//// amount, and concurrent increments commute instead of overwriting each other.
//// Local increments are applied optimistically; acks only retire pending ops.

import gleam/int
import gleam/list

pub type CounterState {
  CounterState(
    value: Int,
    pending: List(PendingOperation),
    next_pending_message_id: Int,
  )
}

/// A submitted local op plus the local metadata Fluid uses to match acks and
/// rollbacks. The metadata is local-only; it is not part of the counter op.
pub type PendingOperation {
  PendingIncrement(increment_amount: Int, message_id: Int)
}

/// A counter operation as it travels over the wire.
pub type CounterOp {
  Increment(increment_amount: Int)
}

pub type CounterEvent {
  Incremented(increment_amount: Int, new_value: Int)
}

/// Returned when a local ack or rollback does not line up with the pending
/// queue. The TS counter assert-fails in these cases; runtime callers should
/// treat this as fatal rather than continue with divergent state.
pub type KernelError {
  UnexpectedAck(op: CounterOp, detail: String)
  UnexpectedRollback(op: CounterOp, detail: String)
}

pub fn new() -> CounterState {
  CounterState(value: 0, pending: [], next_pending_message_id: 0)
}

/// Build a state from a stored summary value. Freshly loaded counters have no
/// pending local ops.
pub fn from_summary(value: Int) -> CounterState {
  CounterState(value: value, pending: [], next_pending_message_id: 0)
}

/// The value to store in a summary once the runtime is synced.
pub fn summary_value(state: CounterState) -> Int {
  state.value
}

/// Optimistically apply a local increment and return the outbound op plus its
/// local message id. Gleam `Int` enforces Fluid's "whole number" constraint.
pub fn increment(
  state: CounterState,
  increment_amount: Int,
) -> #(CounterState, List(CounterEvent), CounterOp, Int) {
  let message_id = state.next_pending_message_id
  let new_value = state.value + increment_amount
  #(
    CounterState(
      value: new_value,
      pending: list.append(state.pending, [
        PendingIncrement(increment_amount, message_id),
      ]),
      next_pending_message_id: message_id + 1,
    ),
    [Incremented(increment_amount, new_value)],
    Increment(increment_amount),
    message_id,
  )
}

/// Apply a sequenced op from another client.
pub fn apply_remote(
  state: CounterState,
  op: CounterOp,
) -> #(CounterState, List(CounterEvent)) {
  case op {
    Increment(increment_amount) -> {
      let new_value = state.value + increment_amount
      #(CounterState(..state, value: new_value), [
        Incremented(increment_amount, new_value),
      ])
    }
  }
}

/// Retire the oldest pending op when our local op comes back sequenced. The
/// value and events do not change because the op already applied optimistically.
pub fn ack_local(
  state: CounterState,
  op: CounterOp,
) -> Result(CounterState, KernelError) {
  case state.pending {
    [] -> Error(UnexpectedAck(op, "pending queue is empty"))
    [PendingIncrement(amount, _), ..rest] ->
      case op {
        Increment(increment_amount) if increment_amount == amount ->
          Ok(CounterState(..state, pending: rest))
        Increment(increment_amount) ->
          Error(UnexpectedAck(
            op,
            "expected pending increment "
              <> int.to_string(amount)
              <> ", got "
              <> int.to_string(increment_amount),
          ))
      }
  }
}

/// Retire the oldest pending op and validate Fluid's local op metadata.
pub fn ack_local_with_message_id(
  state: CounterState,
  op: CounterOp,
  message_id: Int,
) -> Result(CounterState, KernelError) {
  case state.pending {
    [] -> Error(UnexpectedAck(op, "pending queue is empty"))
    [PendingIncrement(amount, pending_message_id), ..rest] ->
      case op {
        Increment(increment_amount)
          if increment_amount == amount && message_id == pending_message_id
        -> Ok(CounterState(..state, pending: rest))
        Increment(increment_amount) ->
          Error(UnexpectedAck(
            op,
            "expected pending increment "
              <> int.to_string(amount)
              <> " with message id "
              <> int.to_string(pending_message_id)
              <> ", got increment "
              <> int.to_string(increment_amount)
              <> " with message id "
              <> int.to_string(message_id),
          ))
      }
  }
}

/// Re-apply a stashed op after reconnect. Fluid routes this back through
/// `increment`, so it is optimistically visible and becomes pending again.
pub fn apply_stashed_op(
  state: CounterState,
  op: CounterOp,
) -> #(CounterState, List(CounterEvent), CounterOp, Int) {
  case op {
    Increment(increment_amount) -> increment(state, increment_amount)
  }
}

/// Roll back the newest pending op, undoing its optimistic effect. Fluid emits
/// a normal `incremented` event with the negated amount.
pub fn rollback(
  state: CounterState,
  op: CounterOp,
  message_id: Int,
) -> Result(#(CounterState, List(CounterEvent)), KernelError) {
  case pop_last(state.pending) {
    Error(_) -> Error(UnexpectedRollback(op, "pending queue is empty"))
    Ok(#(PendingIncrement(amount, pending_message_id), rest)) ->
      case op {
        Increment(increment_amount)
          if increment_amount == amount && message_id == pending_message_id
        -> {
          let rollback_amount = 0 - increment_amount
          let new_value = state.value + rollback_amount
          Ok(
            #(CounterState(..state, value: new_value, pending: rest), [
              Incremented(rollback_amount, new_value),
            ]),
          )
        }
        Increment(increment_amount) ->
          Error(UnexpectedRollback(
            op,
            "expected newest pending increment "
              <> int.to_string(amount)
              <> " with message id "
              <> int.to_string(pending_message_id)
              <> ", got increment "
              <> int.to_string(increment_amount)
              <> " with message id "
              <> int.to_string(message_id),
          ))
      }
  }
}

fn pop_last(
  pending: List(PendingOperation),
) -> Result(#(PendingOperation, List(PendingOperation)), Nil) {
  case pending {
    [] -> Error(Nil)
    [only] -> Ok(#(only, []))
    [head, ..rest] ->
      case pop_last(rest) {
        Error(_) -> Error(Nil)
        Ok(#(last, init)) -> Ok(#(last, [head, ..init]))
      }
  }
}
