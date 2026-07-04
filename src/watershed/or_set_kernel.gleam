//// A lattice-backed observed-remove set kernel for string elements.
////
//// Local adds/removes produce sparse OR-Set deltas. Confirmed state is the
//// sequenced join of acked local and remote deltas; reads use an optimistic
//// cache that replays pending local deltas over that sequenced base.

import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set
import gleam/string
import lattice_core/replica_id.{type ReplicaId}
import lattice_sets/or_set.{type ORSet}

pub type OrSetState {
  OrSetState(
    replica_id: ReplicaId,
    sequenced: ORSet(String),
    optimistic: ORSet(String),
    pending: List(PendingOp),
    next_pending_message_id: Int,
  )
}

pub type PendingOp {
  PendingOp(op: OrSetOp, message_id: Int)
}

pub type OrSetOp {
  Add(element: String, delta: ORSet(String))
  Remove(element: String, delta: ORSet(String))
}

pub type OrSetEvent {
  ElementAdded(element: String)
  ElementRemoved(element: String)
}

pub type KernelError {
  UnexpectedAck(detail: String)
  UnexpectedRollback(detail: String)
}

pub fn new(replica_id: ReplicaId) -> OrSetState {
  let empty = or_set.new(replica_id)
  OrSetState(
    replica_id: replica_id,
    sequenced: empty,
    optimistic: empty,
    pending: [],
    next_pending_message_id: 0,
  )
}

pub fn contains(state: OrSetState, element: String) -> Bool {
  or_set.contains(state.optimistic, element)
}

pub fn values(state: OrSetState) -> List(String) {
  set.to_list(or_set.value(state.optimistic))
  |> list.sort(string.compare)
}

pub fn sequenced_values(state: OrSetState) -> List(String) {
  set.to_list(or_set.value(state.sequenced))
  |> list.sort(string.compare)
}

pub fn add(
  state: OrSetState,
  element: String,
) -> #(OrSetState, List(OrSetEvent), OrSetOp, Int) {
  let before = values(state)
  let #(optimistic, delta) = or_set.add_with_delta(state.optimistic, element)
  let message_id = state.next_pending_message_id
  let op = Add(element, delta)
  let state =
    OrSetState(
      ..state,
      optimistic: optimistic,
      pending: list.append(state.pending, [PendingOp(op, message_id)]),
      next_pending_message_id: message_id + 1,
    )
  #(state, events_between(before, values(state)), op, message_id)
}

pub fn remove(
  state: OrSetState,
  element: String,
) -> #(OrSetState, List(OrSetEvent), OrSetOp, Int) {
  let before = values(state)
  let #(optimistic, delta) = or_set.remove_with_delta(state.optimistic, element)
  let message_id = state.next_pending_message_id
  let op = Remove(element, delta)
  let state =
    OrSetState(
      ..state,
      optimistic: optimistic,
      pending: list.append(state.pending, [PendingOp(op, message_id)]),
      next_pending_message_id: message_id + 1,
    )
  #(state, events_between(before, values(state)), op, message_id)
}

pub fn apply_remote(
  state: OrSetState,
  op: OrSetOp,
) -> #(OrSetState, List(OrSetEvent)) {
  let before = values(state)
  let delta = op_delta(op)
  let sequenced = or_set.merge(state.sequenced, delta)
  let optimistic = replay_pending(sequenced, state.pending)
  let state = OrSetState(..state, sequenced: sequenced, optimistic: optimistic)
  #(state, events_between(before, values(state)))
}

pub fn ack_local(
  state: OrSetState,
  op: OrSetOp,
) -> Result(OrSetState, KernelError) {
  do_ack(state, op, None)
}

pub fn ack_local_with_message_id(
  state: OrSetState,
  op: OrSetOp,
  message_id: Int,
) -> Result(OrSetState, KernelError) {
  do_ack(state, op, Some(message_id))
}

fn do_ack(
  state: OrSetState,
  op: OrSetOp,
  expected_message_id: Option(Int),
) -> Result(OrSetState, KernelError) {
  case state.pending {
    [] -> Error(UnexpectedAck("pending queue is empty"))
    [PendingOp(pending_op, pending_message_id), ..rest] -> {
      let message_id_matches = case expected_message_id {
        None -> True
        Some(message_id) -> message_id == pending_message_id
      }
      case pending_op == op && message_id_matches {
        True ->
          Ok(
            OrSetState(
              ..state,
              sequenced: or_set.merge(state.sequenced, op_delta(op)),
              pending: rest,
            ),
          )
        False ->
          Error(UnexpectedAck(
            "expected pending op with message id "
            <> int.to_string(pending_message_id)
            <> ", got message id "
            <> case expected_message_id {
              Some(message_id) -> int.to_string(message_id)
              None -> "unvalidated"
            },
          ))
      }
    }
  }
}

pub fn rollback(
  state: OrSetState,
  op: OrSetOp,
  message_id: Int,
) -> Result(#(OrSetState, List(OrSetEvent)), KernelError) {
  case pop_last(state.pending) {
    Error(_) -> Error(UnexpectedRollback("pending queue is empty"))
    Ok(#(PendingOp(pending_op, pending_message_id), rest)) ->
      case pending_op == op && pending_message_id == message_id {
        False ->
          Error(UnexpectedRollback(
            "expected newest pending op with message id "
            <> int.to_string(pending_message_id)
            <> ", got message id "
            <> int.to_string(message_id),
          ))
        True -> {
          let before = values(state)
          let optimistic = replay_pending(state.sequenced, rest)
          let state = OrSetState(..state, optimistic: optimistic, pending: rest)
          Ok(#(state, events_between(before, values(state))))
        }
      }
  }
}

pub fn apply_stashed_op(
  state: OrSetState,
  op: OrSetOp,
) -> #(OrSetState, List(OrSetEvent), OrSetOp, Int) {
  let before = values(state)
  let optimistic = or_set.merge(state.optimistic, op_delta(op))
  let message_id = state.next_pending_message_id
  let state =
    OrSetState(
      ..state,
      optimistic: optimistic,
      pending: list.append(state.pending, [PendingOp(op, message_id)]),
      next_pending_message_id: message_id + 1,
    )
  #(state, events_between(before, values(state)), op, message_id)
}

pub fn promote_attach(state: OrSetState) -> OrSetState {
  OrSetState(..state, sequenced: state.optimistic, pending: [])
}

pub fn summary(state: OrSetState) -> Json {
  or_set.to_json(state.sequenced)
}

pub fn from_summary(
  summary_json: String,
  replica_id: ReplicaId,
) -> Result(OrSetState, json.DecodeError) {
  case or_set.from_json(summary_json) {
    Error(error) -> Error(error)
    Ok(parsed) -> Ok(from_sequenced(parsed, replica_id))
  }
}

pub fn from_sequenced(
  sequenced: ORSet(String),
  replica_id: ReplicaId,
) -> OrSetState {
  let rebranded = or_set.merge(or_set.new(replica_id), sequenced)
  OrSetState(
    replica_id: replica_id,
    sequenced: rebranded,
    optimistic: rebranded,
    pending: [],
    next_pending_message_id: 0,
  )
}

pub fn check_cache_coherence(state: OrSetState) -> Result(Nil, String) {
  let recomputed = replay_pending(state.sequenced, state.pending)
  case recomputed == state.optimistic {
    True -> Ok(Nil)
    False -> Error("optimistic cache diverged from sequenced + pending")
  }
}

fn op_delta(op: OrSetOp) -> ORSet(String) {
  case op {
    Add(_, delta) | Remove(_, delta) -> delta
  }
}

fn replay_pending(
  sequenced: ORSet(String),
  pending: List(PendingOp),
) -> ORSet(String) {
  list.fold(pending, sequenced, fn(acc, pending) {
    or_set.merge(acc, op_delta(pending.op))
  })
}

fn events_between(
  before: List(String),
  after: List(String),
) -> List(OrSetEvent) {
  let keys =
    list.append(before, after) |> list.unique |> list.sort(string.compare)
  list.filter_map(keys, fn(element) {
    let was_present = list.any(before, fn(value) { value == element })
    let is_present = list.any(after, fn(value) { value == element })
    case was_present, is_present {
      False, True -> Ok(ElementAdded(element))
      True, False -> Ok(ElementRemoved(element))
      _, _ -> Error(Nil)
    }
  })
}

fn pop_last(
  pending: List(PendingOp),
) -> Result(#(PendingOp, List(PendingOp)), Nil) {
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
