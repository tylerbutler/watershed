//// A lattice-backed last-writer-wins register kernel.
////
//// The winning register carries its value, timestamp, and author. The kernel
//// keeps the local author and logical clock separately, because a merge can
//// make another replica the winner.

import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import lattice_core/replica_id.{type ReplicaId}
import lattice_registers/lww_register.{type LWWRegister}
import watershed/lww_clock

pub type LwwRegisterState {
  LwwRegisterState(
    replica_id: ReplicaId,
    sequenced: LWWRegister(String),
    optimistic: LWWRegister(String),
    pending: List(PendingOp),
    next_pending_message_id: Int,
    last_seen: Int,
  )
}

pub type PendingOp {
  PendingOp(operation: LwwRegisterOperation, message_id: Int)
}

pub type LwwRegisterOperation {
  Set(value: String, timestamp: Int, delta: LWWRegister(String))
}

pub type LwwRegisterEvent {
  Changed(previous_value: String, value: String)
}

pub type KernelError {
  UnexpectedAck(operation: LwwRegisterOperation, detail: String)
  UnexpectedRollback(operation: LwwRegisterOperation, detail: String)
  Clock(error: lww_clock.ClockError)
  InvalidState(detail: String)
  DecodeError(error: json.DecodeError)
}

pub fn new(replica_id: ReplicaId) -> LwwRegisterState {
  let empty = lww_register.new("", 0, replica_id.new(""))
  LwwRegisterState(
    replica_id: replica_id,
    sequenced: empty,
    optimistic: empty,
    pending: [],
    next_pending_message_id: 0,
    last_seen: 0,
  )
}

pub fn value(state: LwwRegisterState) -> String {
  lww_register.value(state.optimistic)
}

pub fn sequenced_value(state: LwwRegisterState) -> String {
  lww_register.value(state.sequenced)
}

fn timestamp(register: LWWRegister(String)) -> Result(Int, KernelError) {
  json.parse(
    json.to_string(lww_register.to_json(register)),
    decode.at(["state", "timestamp"], decode.int),
  )
  |> result.map_error(DecodeError)
  |> result.try(fn(value) {
    case value < 0 || value > lww_clock.max_safe_timestamp {
      True ->
        Error(InvalidState("register timestamp is outside the safe range"))
      False -> Ok(value)
    }
  })
}

fn observe(
  state: LwwRegisterState,
  register: LWWRegister(String),
) -> Result(LwwRegisterState, KernelError) {
  use seen <- result.try(timestamp(register))
  Ok(LwwRegisterState(..state, last_seen: int.max(state.last_seen, seen)))
}

fn event_between(
  before: LwwRegisterState,
  after: LwwRegisterState,
) -> List(LwwRegisterEvent) {
  let previous = value(before)
  let next = value(after)
  case previous == next {
    True -> []
    False -> [Changed(previous, next)]
  }
}

fn operation_register(operation: LwwRegisterOperation) -> LWWRegister(String) {
  let Set(_, _, delta) = operation
  delta
}

fn operation_timestamp(operation: LwwRegisterOperation) -> Int {
  let Set(_, timestamp, _) = operation
  timestamp
}

pub fn set(
  state: LwwRegisterState,
  next_value: String,
  wall_clock: Int,
) -> Result(
  #(LwwRegisterState, List(LwwRegisterEvent), LwwRegisterOperation, Int),
  KernelError,
) {
  case lww_clock.next(state.last_seen, wall_clock) {
    Error(error) -> Error(Clock(error))
    Ok(timestamp) -> {
      let delta = lww_register.new(next_value, timestamp, state.replica_id)
      let operation = Set(next_value, timestamp, delta)
      apply_stashed_operation(state, operation)
    }
  }
}

pub fn p2p_set(
  state: LwwRegisterState,
  next_value: String,
  wall_clock: Int,
) -> Result(
  #(LwwRegisterState, List(LwwRegisterEvent), LwwRegisterOperation),
  KernelError,
) {
  case lww_clock.next(state.last_seen, wall_clock) {
    Error(error) -> Error(Clock(error))
    Ok(timestamp) -> {
      let delta = lww_register.new(next_value, timestamp, state.replica_id)
      let operation = Set(next_value, timestamp, delta)
      use #(next, events, _) <- result.try(apply_delta(state, delta))
      Ok(#(next, events, operation))
    }
  }
}

fn apply_delta(
  state: LwwRegisterState,
  delta: LWWRegister(String),
) -> Result(
  #(LwwRegisterState, List(LwwRegisterEvent), LWWRegister(String)),
  KernelError,
) {
  use state <- result.try(observe(state, delta))
  let next =
    LwwRegisterState(
      ..state,
      sequenced: lww_register.merge(state.sequenced, delta),
      optimistic: lww_register.merge(state.optimistic, delta),
    )
  Ok(#(next, event_between(state, next), delta))
}

pub fn apply_stashed_operation(
  state: LwwRegisterState,
  operation: LwwRegisterOperation,
) -> Result(
  #(LwwRegisterState, List(LwwRegisterEvent), LwwRegisterOperation, Int),
  KernelError,
) {
  let delta = operation_register(operation)
  use state <- result.try(observe(state, delta))
  let optimistic = lww_register.merge(state.optimistic, delta)
  let message_id = state.next_pending_message_id
  let next =
    LwwRegisterState(
      ..state,
      optimistic: optimistic,
      pending: list.append(state.pending, [PendingOp(operation, message_id)]),
      next_pending_message_id: message_id + 1,
    )
  Ok(#(next, event_between(state, next), operation, message_id))
}

pub fn apply_remote(
  state: LwwRegisterState,
  operation: LwwRegisterOperation,
) -> Result(#(LwwRegisterState, List(LwwRegisterEvent)), KernelError) {
  let delta = operation_register(operation)
  use state <- result.try(observe(state, delta))
  let next =
    LwwRegisterState(
      ..state,
      sequenced: lww_register.merge(state.sequenced, delta),
      optimistic: lww_register.merge(state.optimistic, delta),
    )
  Ok(#(next, event_between(state, next)))
}

pub fn p2p_merge(
  state: LwwRegisterState,
  other: LWWRegister(String),
) -> Result(#(LwwRegisterState, List(LwwRegisterEvent)), KernelError) {
  use state <- result.try(observe(state, other))
  let next =
    LwwRegisterState(
      ..state,
      sequenced: lww_register.merge(state.sequenced, other),
      optimistic: lww_register.merge(state.optimistic, other),
    )
  Ok(#(next, event_between(state, next)))
}

pub fn ack_local(
  state: LwwRegisterState,
  operation: LwwRegisterOperation,
) -> Result(LwwRegisterState, KernelError) {
  do_ack(state, operation, None)
}

pub fn ack_local_with_message_id(
  state: LwwRegisterState,
  operation: LwwRegisterOperation,
  message_id: Int,
) -> Result(LwwRegisterState, KernelError) {
  do_ack(state, operation, Some(message_id))
}

fn do_ack(
  state: LwwRegisterState,
  operation: LwwRegisterOperation,
  expected_message_id: Option(Int),
) -> Result(LwwRegisterState, KernelError) {
  case state.pending {
    [] -> Error(UnexpectedAck(operation, "pending queue is empty"))
    [PendingOp(expected, pending_message_id), ..rest] -> {
      let id_matches = case expected_message_id {
        None -> True
        Some(actual) -> actual == pending_message_id
      }
      case operation == expected && id_matches {
        False ->
          Error(UnexpectedAck(
            operation,
            "ack does not match oldest pending write",
          ))
        True -> {
          let delta = operation_register(operation)
          use state <- result.try(observe(state, delta))
          Ok(
            LwwRegisterState(
              ..state,
              sequenced: lww_register.merge(state.sequenced, delta),
              pending: rest,
            ),
          )
        }
      }
    }
  }
}

pub fn rollback(
  state: LwwRegisterState,
  operation: LwwRegisterOperation,
  message_id: Int,
) -> Result(#(LwwRegisterState, List(LwwRegisterEvent)), KernelError) {
  case list.reverse(state.pending) {
    [] -> Error(UnexpectedRollback(operation, "pending queue is empty"))
    [PendingOp(expected, expected_id), ..rest] ->
      case operation == expected && message_id == expected_id {
        False ->
          Error(UnexpectedRollback(
            operation,
            "rollback does not match newest pending write",
          ))
        True -> {
          let pending = list.reverse(rest)
          let optimistic = replay(state.sequenced, pending)
          let next =
            LwwRegisterState(..state, pending: pending, optimistic: optimistic)
          Ok(#(next, event_between(state, next)))
        }
      }
  }
}

fn replay(
  sequenced: LWWRegister(String),
  pending: List(PendingOp),
) -> LWWRegister(String) {
  list.fold(pending, sequenced, fn(acc, pending) {
    lww_register.merge(acc, operation_register(pending.operation))
  })
}

pub fn summary(state: LwwRegisterState) -> Json {
  lww_register.to_json(state.sequenced)
}

pub fn from_summary(
  source: String,
  replica_id: ReplicaId,
) -> Result(LwwRegisterState, KernelError) {
  case lww_register.from_json(source) {
    Error(error) -> Error(DecodeError(error))
    Ok(register) -> from_sequenced(register, replica_id)
  }
}

pub fn from_sequenced(
  register: LWWRegister(String),
  replica_id: ReplicaId,
) -> Result(LwwRegisterState, KernelError) {
  case timestamp(register) {
    Error(error) -> Error(error)
    Ok(last_seen) ->
      Ok(LwwRegisterState(
        replica_id: replica_id,
        sequenced: register,
        optimistic: register,
        pending: [],
        next_pending_message_id: 0,
        last_seen: last_seen,
      ))
  }
}

pub fn check_cache_coherence(state: LwwRegisterState) -> Result(Nil, String) {
  let expected = replay(state.sequenced, state.pending)
  case expected == state.optimistic {
    True -> Ok(Nil)
    False ->
      Error(
        "optimistic LWWRegister cache does not match sequenced plus pending",
      )
  }
}

pub fn pending_timestamp(operation: LwwRegisterOperation) -> Int {
  operation_timestamp(operation)
}
