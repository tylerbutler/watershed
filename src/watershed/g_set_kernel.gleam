//// A lattice-backed grow-only set kernel for string elements.
////
//// G-set deltas are themselves G-sets containing newly added elements. Merge is
//// set union, so duplicate delivery and replay are no-ops.

import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set
import gleam/string
import lattice_sets/g_set.{type GSet}

pub type GSetState {
  GSetState(
    sequenced: GSet(String),
    optimistic: GSet(String),
    pending: List(PendingOp),
    next_pending_message_id: Int,
  )
}

pub type PendingOp {
  PendingOp(op: GSetOp, message_id: Int)
}

pub type GSetOp {
  Add(element: String, delta: GSet(String))
}

pub type GSetEvent {
  ElementAdded(element: String)
}

pub type KernelError {
  UnexpectedAck(detail: String)
  UnexpectedRollback(detail: String)
}

pub fn new() -> GSetState {
  let empty = g_set.new()
  GSetState(
    sequenced: empty,
    optimistic: empty,
    pending: [],
    next_pending_message_id: 0,
  )
}

pub fn contains(state: GSetState, element: String) -> Bool {
  g_set.contains(state.optimistic, element)
}

pub fn values(state: GSetState) -> List(String) {
  g_set.value(state.optimistic)
  |> set.to_list
  |> list.sort(string.compare)
}

pub fn sequenced_values(state: GSetState) -> List(String) {
  g_set.value(state.sequenced)
  |> set.to_list
  |> list.sort(string.compare)
}

pub fn add(
  state: GSetState,
  element: String,
) -> #(GSetState, List(GSetEvent), GSetOp, Int) {
  let before = values(state)
  let #(optimistic, delta) = g_set.add_with_delta(state.optimistic, element)
  let message_id = state.next_pending_message_id
  let op = Add(element, delta)
  let state =
    GSetState(
      ..state,
      optimistic: optimistic,
      pending: list.append(state.pending, [PendingOp(op, message_id)]),
      next_pending_message_id: message_id + 1,
    )
  #(state, events_between(before, values(state)), op, message_id)
}

pub fn apply_remote(
  state: GSetState,
  op: GSetOp,
) -> #(GSetState, List(GSetEvent)) {
  let before = values(state)
  let Add(_, delta) = op
  let sequenced = g_set.merge(state.sequenced, delta)
  let optimistic = replay_pending(sequenced, state.pending)
  let state = GSetState(..state, sequenced: sequenced, optimistic: optimistic)
  #(state, events_between(before, values(state)))
}

pub fn ack_local(
  state: GSetState,
  op: GSetOp,
) -> Result(GSetState, KernelError) {
  do_ack(state, op, None)
}

pub fn ack_local_with_message_id(
  state: GSetState,
  op: GSetOp,
  message_id: Int,
) -> Result(GSetState, KernelError) {
  do_ack(state, op, Some(message_id))
}

fn do_ack(
  state: GSetState,
  op: GSetOp,
  expected_message_id: Option(Int),
) -> Result(GSetState, KernelError) {
  case state.pending {
    [] -> Error(UnexpectedAck("pending queue is empty"))
    [PendingOp(pending_op, pending_message_id), ..rest] -> {
      let message_id_matches = case expected_message_id {
        None -> True
        Some(message_id) -> message_id == pending_message_id
      }
      case pending_op == op && message_id_matches {
        True -> {
          let Add(_, delta) = op
          Ok(
            GSetState(
              ..state,
              sequenced: g_set.merge(state.sequenced, delta),
              pending: rest,
            ),
          )
        }
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
  state: GSetState,
  op: GSetOp,
  message_id: Int,
) -> Result(#(GSetState, List(GSetEvent)), KernelError) {
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
          let state = GSetState(..state, optimistic: optimistic, pending: rest)
          Ok(#(state, events_between(before, values(state))))
        }
      }
  }
}

pub fn apply_stashed_op(
  state: GSetState,
  op: GSetOp,
) -> #(GSetState, List(GSetEvent), GSetOp, Int) {
  let before = values(state)
  let Add(_, delta) = op
  let optimistic = g_set.merge(state.optimistic, delta)
  let message_id = state.next_pending_message_id
  let state =
    GSetState(
      ..state,
      optimistic: optimistic,
      pending: list.append(state.pending, [PendingOp(op, message_id)]),
      next_pending_message_id: message_id + 1,
    )
  #(state, events_between(before, values(state)), op, message_id)
}

pub fn promote_attach(state: GSetState) -> GSetState {
  GSetState(..state, sequenced: state.optimistic, pending: [])
}

pub fn summary(state: GSetState) -> Json {
  g_set.to_json(state.sequenced)
}

pub fn from_summary(
  summary_json: String,
) -> Result(GSetState, json.DecodeError) {
  case g_set.from_json(summary_json) {
    Error(error) -> Error(error)
    Ok(parsed) -> Ok(from_sequenced(parsed))
  }
}

pub fn from_sequenced(sequenced: GSet(String)) -> GSetState {
  GSetState(
    sequenced: sequenced,
    optimistic: sequenced,
    pending: [],
    next_pending_message_id: 0,
  )
}

pub fn check_cache_coherence(state: GSetState) -> Result(Nil, String) {
  let recomputed = replay_pending(state.sequenced, state.pending)
  case recomputed == state.optimistic {
    True -> Ok(Nil)
    False -> Error("optimistic cache diverged from sequenced + pending")
  }
}

fn replay_pending(
  sequenced: GSet(String),
  pending: List(PendingOp),
) -> GSet(String) {
  list.fold(pending, sequenced, fn(acc, pending) {
    let Add(_, delta) = pending.op
    g_set.merge(acc, delta)
  })
}

fn events_between(
  before: List(String),
  after: List(String),
) -> List(GSetEvent) {
  list.filter(after, fn(element) {
    !list.any(before, fn(value) { value == element })
  })
  |> list.map(ElementAdded)
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
