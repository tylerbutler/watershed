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
    pending: List(PendingOperation),
    next_pending_message_id: Int,
  )
}

pub type PendingOperation {
  PendingOperation(operation: SequenceOperation, message_id: Int)
}

pub type SequenceOperation {
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
  operation: SequenceOperation,
) -> #(SequenceState, List(SequenceEvent), SequenceOperation, Int) {
  let before = values(state)
  let message_id = state.next_pending_message_id
  let state =
    SequenceState(
      ..state,
      optimistic: optimistic,
      pending: list.append(state.pending, [
        PendingOperation(operation, message_id),
      ]),
      next_pending_message_id: message_id + 1,
    )
  #(state, changed_event(before, values(state)), operation, message_id)
}

fn changed_event(before: List(Json), after: List(Json)) -> List(SequenceEvent) {
  case same_json_list(before, after) {
    True -> []
    False -> [SequenceChanged(after)]
  }
}

/// Two equal encoded strings are two equal values. Thus the cheap comparison
/// answers the usual no-change case. Only a mismatch runs the comparison of
/// each element, which normalizes the elements and thus accepts a different
/// object key order.
fn same_json_list(before: List(Json), after: List(Json)) -> Bool {
  list.map(before, json.to_string) == list.map(after, json.to_string)
  || same_normalized_list(before, after)
}

fn same_normalized_list(before: List(Json), after: List(Json)) -> Bool {
  case before, after {
    [], [] -> True
    [before_head, ..before_tail], [after_head, ..after_tail] ->
      same_json_value(before_head, after_head)
      && same_normalized_list(before_tail, after_tail)
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
  #(SequenceState, List(SequenceEvent), SequenceOperation, Int),
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
  #(SequenceState, List(SequenceEvent), SequenceOperation, Int),
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
  #(SequenceState, List(SequenceEvent), SequenceOperation, Int),
  EditError,
) {
  case sequence.try_move_with_delta(state.optimistic, from_index, to_index) {
    Ok(#(optimistic, delta)) ->
      Ok(finish_local(state, optimistic, Move(from_index, to_index, delta)))
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
  #(SequenceState, List(SequenceEvent), SequenceOperation, Int),
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

/// Merge the full confirmed CRDT state of a peer into this state. This is
/// the ack-free equivalent of `apply_remote`. It takes a `state` or
/// `channel` snapshot, not one delta.
///
/// A lattice merge is a join, so it never discards a winner. The result is
/// the least upper bound of the two sides.
pub fn p2p_merge(
  state: SequenceState,
  other: Sequence(Json),
) -> #(SequenceState, List(SequenceEvent)) {
  let before = values(state)
  let sequenced = sequence.merge(state.sequenced, other)
  let optimistic = replay_pending(sequenced, state.pending)
  let state =
    SequenceState(..state, sequenced: sequenced, optimistic: optimistic)
  #(state, changed_event(before, values(state)))
}

pub fn apply_remote(
  state: SequenceState,
  operation: SequenceOperation,
) -> #(SequenceState, List(SequenceEvent)) {
  let before = values(state)
  let sequenced = sequence.merge(state.sequenced, operation_delta(operation))
  let optimistic = replay_pending(sequenced, state.pending)
  let state =
    SequenceState(..state, sequenced: sequenced, optimistic: optimistic)
  #(state, changed_event(before, values(state)))
}

/// Merge a new local delta into `sequenced` and `optimistic` in one step.
/// The delta gets no pending entry, because a p2p commit needs no ack.
/// This function has the same behaviour as `text_kernel.commit_p2p`.
fn commit_p2p(
  state: SequenceState,
  operation: SequenceOperation,
) -> #(SequenceState, List(SequenceEvent), SequenceOperation) {
  let before = values(state)
  let delta = operation_delta(operation)
  let state =
    SequenceState(
      ..state,
      sequenced: sequence.merge(state.sequenced, delta),
      optimistic: sequence.merge(state.optimistic, delta),
    )
  #(state, changed_event(before, values(state)), operation)
}

/// The ack-free p2p form of `insert`. It writes the same delta, but it merges
/// that delta into the confirmed state and the visible state immediately. See
/// `commit_p2p`. It queues no pending entry for a later ack.
pub fn p2p_insert(
  state: SequenceState,
  index: Int,
  value: Json,
) -> Result(#(SequenceState, List(SequenceEvent), SequenceOperation), EditError) {
  case sequence.try_insert_with_delta(state.optimistic, index, value) {
    Ok(#(_, delta)) -> Ok(commit_p2p(state, Insert(index, value, delta)))
    Error(sequence.IndexOutOfBounds(index, length)) ->
      Error(InsertOutOfBounds(index, length))
  }
}

/// The ack-free p2p form of `delete`. See `p2p_insert`.
pub fn p2p_delete(
  state: SequenceState,
  index: Int,
) -> Result(#(SequenceState, List(SequenceEvent), SequenceOperation), EditError) {
  case sequence.try_delete_with_delta(state.optimistic, index) {
    Ok(#(_, delta)) -> Ok(commit_p2p(state, Delete(index, delta)))
    Error(sequence.DeleteIndexOutOfBounds(index, length)) ->
      Error(DeleteOutOfBounds(index, length))
  }
}

/// The ack-free p2p form of `move`. See `p2p_insert`.
pub fn p2p_move(
  state: SequenceState,
  from_index: Int,
  to_index: Int,
) -> Result(#(SequenceState, List(SequenceEvent), SequenceOperation), EditError) {
  case sequence.try_move_with_delta(state.optimistic, from_index, to_index) {
    Ok(#(_, delta)) -> Ok(commit_p2p(state, Move(from_index, to_index, delta)))
    Error(sequence.MoveFromIndexOutOfBounds(index, length)) ->
      Error(MoveFromOutOfBounds(index, length))
    Error(sequence.MoveToIndexOutOfBounds(index, length_after_removal)) ->
      Error(MoveToOutOfBounds(index, length_after_removal))
  }
}

/// The ack-free p2p form of `replace`. See `p2p_insert`.
pub fn p2p_replace(
  state: SequenceState,
  index: Int,
  value: Json,
) -> Result(#(SequenceState, List(SequenceEvent), SequenceOperation), EditError) {
  case sequence.try_delete_with_delta(state.optimistic, index) {
    Error(sequence.DeleteIndexOutOfBounds(index, length)) ->
      Error(ReplaceOutOfBounds(index, length))
    Ok(#(after_delete, delete_delta)) ->
      case sequence.try_insert_with_delta(after_delete, index, value) {
        Error(sequence.IndexOutOfBounds(_, length)) ->
          Error(ReplaceOutOfBounds(index, length))
        Ok(#(_, insert_delta)) -> {
          let delta = sequence.merge(delete_delta, insert_delta)
          Ok(commit_p2p(state, Replace(index, value, delta)))
        }
      }
  }
}

pub fn ack_local(
  state: SequenceState,
  operation: SequenceOperation,
) -> Result(SequenceState, KernelError) {
  do_ack(state, operation, None)
}

pub fn ack_local_with_message_id(
  state: SequenceState,
  operation: SequenceOperation,
  message_id: Int,
) -> Result(SequenceState, KernelError) {
  do_ack(state, operation, Some(message_id))
}

fn do_ack(
  state: SequenceState,
  operation: SequenceOperation,
  expected_message_id: Option(Int),
) -> Result(SequenceState, KernelError) {
  case state.pending {
    [] -> Error(UnexpectedAck("pending queue is empty"))
    [PendingOperation(pending_operation, pending_message_id), ..rest] -> {
      let id_matches = case expected_message_id {
        None -> True
        Some(message_id) -> message_id == pending_message_id
      }
      case pending_operation == operation && id_matches {
        True ->
          Ok(
            SequenceState(
              ..state,
              sequenced: sequence.merge(
                state.sequenced,
                operation_delta(operation),
              ),
              pending: rest,
            ),
          )
        False ->
          Error(UnexpectedAck(
            "expected pending message " <> int.to_string(pending_message_id),
          ))
      }
    }
  }
}

pub fn rollback(
  state: SequenceState,
  operation: SequenceOperation,
  message_id: Int,
) -> Result(#(SequenceState, List(SequenceEvent)), KernelError) {
  case pop_last(state.pending) {
    Error(_) -> Error(UnexpectedRollback("pending queue is empty"))
    Ok(#(PendingOperation(pending_operation, pending_message_id), rest)) ->
      case pending_operation == operation && pending_message_id == message_id {
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

pub fn apply_stashed_operation(
  state: SequenceState,
  operation: SequenceOperation,
) -> #(SequenceState, List(SequenceEvent), SequenceOperation, Int) {
  let optimistic = sequence.merge(state.optimistic, operation_delta(operation))
  finish_local(state, optimistic, operation)
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
      "insert index "
      <> int.to_string(index)
      <> " outside 0.."
      <> int.to_string(length)
    DeleteOutOfBounds(index, length) ->
      "delete index "
      <> int.to_string(index)
      <> " invalid for length "
      <> int.to_string(length)
    MoveFromOutOfBounds(index, length) ->
      "move source index "
      <> int.to_string(index)
      <> " invalid for length "
      <> int.to_string(length)
    MoveToOutOfBounds(index, length_after_removal) ->
      "move destination index "
      <> int.to_string(index)
      <> " outside 0.."
      <> int.to_string(length_after_removal)
    ReplaceOutOfBounds(index, length) ->
      "replace index "
      <> int.to_string(index)
      <> " invalid for length "
      <> int.to_string(length)
  }
}

fn operation_delta(operation: SequenceOperation) -> Sequence(Json) {
  case operation {
    Insert(_, _, delta)
    | Delete(_, delta)
    | Move(_, _, delta)
    | Replace(_, _, delta) -> delta
  }
}

fn replay_pending(
  sequenced: Sequence(Json),
  pending: List(PendingOperation),
) -> Sequence(Json) {
  list.fold(pending, sequenced, fn(acc, pending) {
    sequence.merge(acc, operation_delta(pending.operation))
  })
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
