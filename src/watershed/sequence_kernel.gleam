import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import lattice_core/replica_id.{type ReplicaId}
import lattice_sequence/sequence.{type Sequence}
import watershed/wire

pub type SequenceState {
  SequenceState(
    replica_id: ReplicaId,
    sequenced: Sequence(Json),
    optimistic: Sequence(Json),
    pending: List(PendingOp),
    next_pending_message_id: Int,
  )
}

pub type PendingOp {
  PendingOp(op: SequenceOp, message_id: Int)
}

pub type SequenceOp {
  Insert(index: Int, value: Json, delta: Sequence(Json))
  Delete(index: Int, delta: Sequence(Json))
  Move(from_index: Int, to_index: Int, delta: Sequence(Json))
  Replace(index: Int, value: Json, delta: Sequence(Json))
}

pub type SequenceEvent {
  SequenceChanged(values: List(Json))
}

pub type EditError {
  InsertOutOfBounds(index: Int, length: Int)
  DeleteOutOfBounds(index: Int, length: Int)
  MoveFromOutOfBounds(index: Int, length: Int)
  MoveToOutOfBounds(index: Int, length_after_removal: Int)
  ReplaceOutOfBounds(index: Int, length: Int)
}

pub type KernelError {
  UnexpectedAck(detail: String)
  UnexpectedRollback(detail: String)
}

pub fn new(replica_id: ReplicaId) -> SequenceState {
  let empty = sequence.new(replica_id)
  SequenceState(
    replica_id: replica_id,
    sequenced: empty,
    optimistic: empty,
    pending: [],
    next_pending_message_id: 0,
  )
}

pub fn values(state: SequenceState) -> List(Json) {
  sequence.values(state.optimistic)
}

pub fn sequenced_values(state: SequenceState) -> List(Json) {
  sequence.values(state.sequenced)
}

pub fn length(state: SequenceState) -> Int {
  sequence.length(state.optimistic)
}

fn finish_local(
  state: SequenceState,
  optimistic: Sequence(Json),
  op: SequenceOp,
) -> #(SequenceState, List(SequenceEvent), SequenceOp, Int) {
  let before = values(state)
  let message_id = state.next_pending_message_id
  let state =
    SequenceState(
      ..state,
      optimistic: optimistic,
      pending: list.append(state.pending, [PendingOp(op, message_id)]),
      next_pending_message_id: message_id + 1,
    )
  #(state, changed_event(before, values(state)), op, message_id)
}

fn changed_event(before: List(Json), after: List(Json)) -> List(SequenceEvent) {
  case same_json_list(before, after) {
    True -> []
    False -> [SequenceChanged(after)]
  }
}

fn same_json_list(before: List(Json), after: List(Json)) -> Bool {
  case before, after {
    [], [] -> True
    [before_head, ..before_tail], [after_head, ..after_tail] ->
      same_json_value(before_head, after_head)
      && same_json_list(before_tail, after_tail)
    _, _ -> False
  }
}

fn same_json_value(before: Json, after: Json) -> Bool {
  case json.parse(json.to_string(before), wire.json_value_decoder()) {
    Ok(normalized_before) ->
      case json.parse(json.to_string(after), wire.json_value_decoder()) {
        Ok(normalized_after) -> normalized_before == normalized_after
        Error(_) -> False
      }
    Error(_) -> False
  }
}

pub fn insert(
  state: SequenceState,
  index: Int,
  value: Json,
) -> Result(
  #(SequenceState, List(SequenceEvent), SequenceOp, Int),
  EditError,
) {
  case sequence.try_insert_with_delta(state.optimistic, index, value) {
    Ok(#(optimistic, delta)) ->
      Ok(finish_local(state, optimistic, Insert(index, value, delta)))
    Error(sequence.IndexOutOfBounds(index, length)) ->
      Error(InsertOutOfBounds(index, length))
  }
}

pub fn delete(
  state: SequenceState,
  index: Int,
) -> Result(
  #(SequenceState, List(SequenceEvent), SequenceOp, Int),
  EditError,
) {
  case sequence.try_delete_with_delta(state.optimistic, index) {
    Ok(#(optimistic, delta)) ->
      Ok(finish_local(state, optimistic, Delete(index, delta)))
    Error(sequence.DeleteIndexOutOfBounds(index, length)) ->
      Error(DeleteOutOfBounds(index, length))
  }
}

pub fn move(
  state: SequenceState,
  from_index: Int,
  to_index: Int,
) -> Result(
  #(SequenceState, List(SequenceEvent), SequenceOp, Int),
  EditError,
) {
  case sequence.try_move_with_delta(state.optimistic, from_index, to_index) {
    Ok(#(optimistic, delta)) ->
      Ok(finish_local(
        state,
        optimistic,
        Move(from_index, to_index, delta),
      ))
    Error(sequence.MoveFromIndexOutOfBounds(index, length)) ->
      Error(MoveFromOutOfBounds(index, length))
    Error(sequence.MoveToIndexOutOfBounds(index, length_after_removal)) ->
      Error(MoveToOutOfBounds(index, length_after_removal))
  }
}

pub fn replace(
  state: SequenceState,
  index: Int,
  value: Json,
) -> Result(
  #(SequenceState, List(SequenceEvent), SequenceOp, Int),
  EditError,
) {
  case sequence.try_delete_with_delta(state.optimistic, index) {
    Error(sequence.DeleteIndexOutOfBounds(index, length)) ->
      Error(ReplaceOutOfBounds(index, length))
    Ok(#(after_delete, delete_delta)) ->
      case sequence.try_insert_with_delta(after_delete, index, value) {
        Error(sequence.IndexOutOfBounds(_, length)) ->
          Error(ReplaceOutOfBounds(index, length))
        Ok(#(optimistic, insert_delta)) -> {
          let delta = sequence.merge(delete_delta, insert_delta)
          Ok(finish_local(state, optimistic, Replace(index, value, delta)))
        }
      }
  }
}

pub fn apply_remote(
  state: SequenceState,
  op: SequenceOp,
) -> #(SequenceState, List(SequenceEvent)) {
  let before = values(state)
  let sequenced = sequence.merge(state.sequenced, op_delta(op))
  let optimistic = replay_pending(sequenced, state.pending)
  let state =
    SequenceState(..state, sequenced: sequenced, optimistic: optimistic)
  #(state, changed_event(before, values(state)))
}

pub fn ack_local(
  state: SequenceState,
  op: SequenceOp,
) -> Result(SequenceState, KernelError) {
  do_ack(state, op, None)
}

pub fn ack_local_with_message_id(
  state: SequenceState,
  op: SequenceOp,
  message_id: Int,
) -> Result(SequenceState, KernelError) {
  do_ack(state, op, Some(message_id))
}

fn do_ack(
  state: SequenceState,
  op: SequenceOp,
  expected_message_id: Option(Int),
) -> Result(SequenceState, KernelError) {
  case state.pending {
    [] -> Error(UnexpectedAck("pending queue is empty"))
    [PendingOp(pending_op, pending_message_id), ..rest] -> {
      let id_matches = case expected_message_id {
        None -> True
        Some(message_id) -> message_id == pending_message_id
      }
      case pending_op == op && id_matches {
        True ->
          Ok(SequenceState(
            ..state,
            sequenced: sequence.merge(state.sequenced, op_delta(op)),
            pending: rest,
          ))
        False ->
          Error(UnexpectedAck(
            "expected pending message "
            <> int.to_string(pending_message_id),
          ))
      }
    }
  }
}

pub fn rollback(
  state: SequenceState,
  op: SequenceOp,
  message_id: Int,
) -> Result(#(SequenceState, List(SequenceEvent)), KernelError) {
  case pop_last(state.pending) {
    Error(_) -> Error(UnexpectedRollback("pending queue is empty"))
    Ok(#(PendingOp(pending_op, pending_message_id), rest)) ->
      case pending_op == op && pending_message_id == message_id {
        False ->
          Error(UnexpectedRollback(
            "expected newest pending message "
            <> int.to_string(pending_message_id),
          ))
        True -> {
          let before = values(state)
          let optimistic = replay_pending(state.sequenced, rest)
          let state =
            SequenceState(..state, optimistic: optimistic, pending: rest)
          Ok(#(state, changed_event(before, values(state))))
        }
      }
  }
}

pub fn apply_stashed_op(
  state: SequenceState,
  op: SequenceOp,
) -> #(SequenceState, List(SequenceEvent), SequenceOp, Int) {
  let optimistic = sequence.merge(state.optimistic, op_delta(op))
  finish_local(state, optimistic, op)
}

pub fn promote_attach(state: SequenceState) -> SequenceState {
  SequenceState(..state, sequenced: state.optimistic, pending: [])
}

pub fn summary(state: SequenceState) -> Json {
  sequence.to_json(state.sequenced, fn(value) { value })
}

pub fn from_summary(
  summary_json: String,
  replica_id: ReplicaId,
) -> Result(SequenceState, json.DecodeError) {
  case sequence.from_json(summary_json, wire.json_value_decoder()) {
    Ok(parsed) -> Ok(from_sequenced(parsed, replica_id))
    Error(error) -> Error(error)
  }
}

pub fn from_sequenced(
  sequenced: Sequence(Json),
  replica_id: ReplicaId,
) -> SequenceState {
  let rebranded = sequence.merge(sequence.new(replica_id), sequenced)
  SequenceState(
    replica_id: replica_id,
    sequenced: rebranded,
    optimistic: rebranded,
    pending: [],
    next_pending_message_id: 0,
  )
}

pub fn check_cache_coherence(state: SequenceState) -> Result(Nil, String) {
  case replay_pending(state.sequenced, state.pending) == state.optimistic {
    True -> Ok(Nil)
    False -> Error("optimistic cache diverged from sequenced + pending")
  }
}

pub fn edit_error_detail(error: EditError) -> String {
  case error {
    InsertOutOfBounds(index, length) ->
      "insert index " <> int.to_string(index) <> " outside 0.."
      <> int.to_string(length)
    DeleteOutOfBounds(index, length) ->
      "delete index " <> int.to_string(index) <> " invalid for length "
      <> int.to_string(length)
    MoveFromOutOfBounds(index, length) ->
      "move source index " <> int.to_string(index) <> " invalid for length "
      <> int.to_string(length)
    MoveToOutOfBounds(index, length_after_removal) ->
      "move destination index " <> int.to_string(index) <> " outside 0.."
      <> int.to_string(length_after_removal)
    ReplaceOutOfBounds(index, length) ->
      "replace index " <> int.to_string(index) <> " invalid for length "
      <> int.to_string(length)
  }
}

fn op_delta(op: SequenceOp) -> Sequence(Json) {
  case op {
    Insert(_, _, delta)
    | Delete(_, delta)
    | Move(_, _, delta)
    | Replace(_, _, delta) -> delta
  }
}

fn replay_pending(
  sequenced: Sequence(Json),
  pending: List(PendingOp),
) -> Sequence(Json) {
  list.fold(pending, sequenced, fn(acc, pending) {
    sequence.merge(acc, op_delta(pending.op))
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
