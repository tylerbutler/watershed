//// Pure port of FluidFramework's `packages/dds/counter/src/counter.ts`.
////
//// SharedCounter is a delta-based integer DDS. Every operation is an increment
//// amount. Concurrent increments commute, and they do not overwrite each
//// other. The kernel applies a local increment optimistically. An ack only
//// retires a pending operation.

import gleam/int
import gleam/list

pub type CounterState {
  CounterState(
    value: Int,
    pending: List(PendingOperation),
    next_pending_message_id: Int,
  )
}

/// A submitted local operation with the local metadata that Fluid uses to match
/// acks and rollbacks. The metadata is local only. It is not part of the
/// counter operation.
pub type PendingOperation {
  PendingIncrement(increment_amount: Int, message_id: Int)
}

/// A counter operation as it travels over the wire.
pub type CounterOperation {
  Increment(increment_amount: Int)
}

pub type CounterEvent {
  Incremented(increment_amount: Int, new_value: Int)
}

/// The kernel returns this error when a local ack or rollback does not agree
/// with the pending queue. The TypeScript counter fails an assert in these
/// conditions. A runtime caller must treat this error as fatal. It must not
/// continue with divergent state.
pub type KernelError {
  UnexpectedAck(operation: CounterOperation, detail: String)
  UnexpectedRollback(operation: CounterOperation, detail: String)
}

pub fn new() -> CounterState {
  CounterState(value: 0, pending: [], next_pending_message_id: 0)
}

/// Build a state from a stored summary value. A counter that you load has no
/// pending local operations.
pub fn from_summary(value: Int) -> CounterState {
  CounterState(value: value, pending: [], next_pending_message_id: 0)
}

/// The value to store in a summary after the runtime is synchronized.
pub fn summary_value(state: CounterState) -> Int {
  state.value
}

/// Apply a local increment optimistically, and return the outbound operation
/// with its local message id. The Gleam `Int` type enforces the whole-number
/// constraint of Fluid.
pub fn increment(
  state: CounterState,
  increment_amount: Int,
) -> #(CounterState, List(CounterEvent), CounterOperation, Int) {
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

/// Apply a sequenced operation from another client.
pub fn apply_remote(
  state: CounterState,
  operation: CounterOperation,
) -> #(CounterState, List(CounterEvent)) {
  case operation {
    Increment(increment_amount) -> {
      let new_value = state.value + increment_amount
      #(CounterState(..state, value: new_value), [
        Incremented(increment_amount, new_value),
      ])
    }
  }
}

/// Retire the oldest pending operation when the local operation returns
/// sequenced. The value and the events do not change, because the kernel
/// already applied the operation optimistically.
pub fn ack_local(
  state: CounterState,
  operation: CounterOperation,
) -> Result(CounterState, KernelError) {
  case state.pending {
    [] -> Error(UnexpectedAck(operation, "pending queue is empty"))
    [PendingIncrement(amount, _), ..rest] ->
      case operation {
        Increment(increment_amount) if increment_amount == amount ->
          Ok(CounterState(..state, pending: rest))
        Increment(increment_amount) ->
          Error(UnexpectedAck(
            operation,
            "expected pending increment "
              <> int.to_string(amount)
              <> ", got "
              <> int.to_string(increment_amount),
          ))
      }
  }
}

/// Retire the oldest pending operation and check the local operation metadata
/// of Fluid.
pub fn ack_local_with_message_id(
  state: CounterState,
  operation: CounterOperation,
  message_id: Int,
) -> Result(CounterState, KernelError) {
  case state.pending {
    [] -> Error(UnexpectedAck(operation, "pending queue is empty"))
    [PendingIncrement(amount, pending_message_id), ..rest] ->
      case operation {
        Increment(increment_amount)
          if increment_amount == amount && message_id == pending_message_id
        -> Ok(CounterState(..state, pending: rest))
        Increment(increment_amount) ->
          Error(UnexpectedAck(
            operation,
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

/// Apply a stashed operation again after a reconnect. Fluid sends it through
/// `increment` again. The operation is thus visible optimistically, and it
/// becomes pending again.
pub fn apply_stashed_operation(
  state: CounterState,
  operation: CounterOperation,
) -> #(CounterState, List(CounterEvent), CounterOperation, Int) {
  case operation {
    Increment(increment_amount) -> increment(state, increment_amount)
  }
}

/// Roll back the newest pending operation and remove its optimistic effect.
/// Fluid emits a usual `incremented` event with the negated amount.
pub fn rollback(
  state: CounterState,
  operation: CounterOperation,
  message_id: Int,
) -> Result(#(CounterState, List(CounterEvent)), KernelError) {
  case pop_last(state.pending) {
    Error(_) -> Error(UnexpectedRollback(operation, "pending queue is empty"))
    Ok(#(PendingIncrement(amount, pending_message_id), rest)) ->
      case operation {
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
            operation,
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
