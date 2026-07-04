//// A lattice-backed two-phase set kernel for string elements.
////
//// Add and remove deltas are monotonic. A remove is a permanent tombstone, so
//// re-adding a removed element records the add but never makes it active again.

import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set
import gleam/string
import lattice_sets/two_p_set.{type TwoPSet}

pub type TwoPSetState {
  TwoPSetState(
    sequenced: TwoPSet(String),
    optimistic: TwoPSet(String),
    pending: List(PendingOp),
    next_pending_message_id: Int,
  )
}

pub type PendingOp {
  PendingOp(op: TwoPSetOp, message_id: Int)
}

pub type TwoPSetOp {
  Add(element: String, delta: TwoPSet(String))
  Remove(element: String, delta: TwoPSet(String))
}

pub type TwoPSetEvent {
  ElementAdded(element: String)
  ElementRemoved(element: String)
}

pub type KernelError {
  UnexpectedAck(detail: String)
  UnexpectedRollback(detail: String)
}

pub fn new() -> TwoPSetState {
  let empty = two_p_set.new()
  TwoPSetState(
    sequenced: empty,
    optimistic: empty,
    pending: [],
    next_pending_message_id: 0,
  )
}

pub fn contains(state: TwoPSetState, element: String) -> Bool {
  two_p_set.contains(state.optimistic, element)
}

pub fn values(state: TwoPSetState) -> List(String) {
  two_p_set.value(state.optimistic)
  |> set.to_list
  |> list.sort(string.compare)
}

pub fn sequenced_values(state: TwoPSetState) -> List(String) {
  two_p_set.value(state.sequenced)
  |> set.to_list
  |> list.sort(string.compare)
}

pub fn add(
  state: TwoPSetState,
  element: String,
) -> #(TwoPSetState, List(TwoPSetEvent), TwoPSetOp, Int) {
  let before = values(state)
  let #(optimistic, delta) = two_p_set.add_with_delta(state.optimistic, element)
  let message_id = state.next_pending_message_id
  let op = Add(element, delta)
  let state =
    TwoPSetState(
      ..state,
      optimistic: optimistic,
      pending: list.append(state.pending, [PendingOp(op, message_id)]),
      next_pending_message_id: message_id + 1,
    )
  #(state, events_between(before, values(state)), op, message_id)
}

pub fn remove(
  state: TwoPSetState,
  element: String,
) -> #(TwoPSetState, List(TwoPSetEvent), TwoPSetOp, Int) {
  let before = values(state)
  let #(optimistic, delta) =
    two_p_set.remove_with_delta(state.optimistic, element)
  let message_id = state.next_pending_message_id
  let op = Remove(element, delta)
  let state =
    TwoPSetState(
      ..state,
      optimistic: optimistic,
      pending: list.append(state.pending, [PendingOp(op, message_id)]),
      next_pending_message_id: message_id + 1,
    )
  #(state, events_between(before, values(state)), op, message_id)
}

pub fn apply_remote(
  state: TwoPSetState,
  op: TwoPSetOp,
) -> #(TwoPSetState, List(TwoPSetEvent)) {
  let before = values(state)
  let delta = op_delta(op)
  let sequenced = two_p_set.merge(state.sequenced, delta)
  let optimistic = replay_pending(sequenced, state.pending)
  let state =
    TwoPSetState(..state, sequenced: sequenced, optimistic: optimistic)
  #(state, events_between(before, values(state)))
}

pub fn ack_local(
  state: TwoPSetState,
  op: TwoPSetOp,
) -> Result(TwoPSetState, KernelError) {
  do_ack(state, op, None)
}

pub fn ack_local_with_message_id(
  state: TwoPSetState,
  op: TwoPSetOp,
  message_id: Int,
) -> Result(TwoPSetState, KernelError) {
  do_ack(state, op, Some(message_id))
}

fn do_ack(
  state: TwoPSetState,
  op: TwoPSetOp,
  expected_message_id: Option(Int),
) -> Result(TwoPSetState, KernelError) {
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
            TwoPSetState(
              ..state,
              sequenced: two_p_set.merge(state.sequenced, op_delta(op)),
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
  state: TwoPSetState,
  op: TwoPSetOp,
  message_id: Int,
) -> Result(#(TwoPSetState, List(TwoPSetEvent)), KernelError) {
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
          let state =
            TwoPSetState(..state, optimistic: optimistic, pending: rest)
          Ok(#(state, events_between(before, values(state))))
        }
      }
  }
}

pub fn apply_stashed_op(
  state: TwoPSetState,
  op: TwoPSetOp,
) -> #(TwoPSetState, List(TwoPSetEvent), TwoPSetOp, Int) {
  let before = values(state)
  let optimistic = two_p_set.merge(state.optimistic, op_delta(op))
  let message_id = state.next_pending_message_id
  let state =
    TwoPSetState(
      ..state,
      optimistic: optimistic,
      pending: list.append(state.pending, [PendingOp(op, message_id)]),
      next_pending_message_id: message_id + 1,
    )
  #(state, events_between(before, values(state)), op, message_id)
}

pub fn promote_attach(state: TwoPSetState) -> TwoPSetState {
  TwoPSetState(..state, sequenced: state.optimistic, pending: [])
}

pub fn summary(state: TwoPSetState) -> Json {
  two_p_set.to_json(state.sequenced)
}

pub fn from_summary(
  summary_json: String,
) -> Result(TwoPSetState, json.DecodeError) {
  case two_p_set.from_json(summary_json) {
    Error(error) -> Error(error)
    Ok(parsed) -> Ok(from_sequenced(parsed))
  }
}

pub fn from_sequenced(sequenced: TwoPSet(String)) -> TwoPSetState {
  TwoPSetState(
    sequenced: sequenced,
    optimistic: sequenced,
    pending: [],
    next_pending_message_id: 0,
  )
}

pub fn check_cache_coherence(state: TwoPSetState) -> Result(Nil, String) {
  let recomputed = replay_pending(state.sequenced, state.pending)
  case recomputed == state.optimistic {
    True -> Ok(Nil)
    False -> Error("optimistic cache diverged from sequenced + pending")
  }
}

fn op_delta(op: TwoPSetOp) -> TwoPSet(String) {
  case op {
    Add(_, delta) | Remove(_, delta) -> delta
  }
}

fn replay_pending(
  sequenced: TwoPSet(String),
  pending: List(PendingOp),
) -> TwoPSet(String) {
  list.fold(pending, sequenced, fn(acc, pending) {
    two_p_set.merge(acc, op_delta(pending.op))
  })
}

fn events_between(
  before: List(String),
  after: List(String),
) -> List(TwoPSetEvent) {
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
