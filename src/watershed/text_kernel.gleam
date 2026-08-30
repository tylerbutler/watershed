import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import lattice_core/replica_id.{type ReplicaId}
import lattice_sequence/sequence
import lattice_text/text.{type Text}

/// Pure state for a collaborative plain-text CRDT. It does not depend on a
/// runtime.
///
/// The structure is the same as `sequence_kernel.SequenceState`. `sequenced`
/// holds the acked local deltas and the remote deltas, and a summary stores
/// it. `optimistic` holds `sequenced` with every local delta that is still
/// pending, and a read uses it. `pending` is a FIFO queue of the local
/// operations that wait for an ack.
pub type TextState {
  TextState(
    replica_id: ReplicaId,
    sequenced: Text,
    optimistic: Text,
    pending: List(PendingOperation),
    next_pending_message_id: Int,
  )
}

pub type PendingOperation {
  PendingOperation(operation: TextOperation, message_id: Int)
}

/// Every grapheme index in these constructors records the intent of the
/// author, for diagnostics only. `delta` is the authoritative CRDT payload. A
/// remote replica applies `delta`. It never applies a diagnostic index field
/// or value field.
pub type TextOperation {
  Insert(index: Int, value: String, delta: Text)
  DeleteRange(start: Int, end: Int, delta: Text)
  ReplaceRange(start: Int, end: Int, value: String, delta: Text)
  Append(value: String, delta: Text)
}

/// The kernel emits this event only when the visible optimistic string
/// changes. The event carries state, and not an index. It thus does not report
/// a stale index of an author as the final position after concurrent edits.
pub type TextEvent {
  TextChanged(value: String)
}

pub type EditError {
  InsertOutOfBounds(index: Int, length: Int)
  DeleteRangeOutOfBounds(start: Int, end: Int, length: Int)
  ReplaceRangeOutOfBounds(start: Int, end: Int, length: Int)
  SubstringOutOfBounds(start: Int, end: Int, length: Int)
}

pub type KernelError {
  UnexpectedAck(detail: String)
  UnexpectedRollback(detail: String)
}

/// An error that the kernel returns when it cannot create or resolve an
/// anchor.
///
/// `UnknownAnchorTarget` means that the anchor references a grapheme that this
/// replica has never seen. A remote replica created that grapheme and this
/// replica has not merged it yet. Or the kernel compacted that grapheme away
/// and its forwarding entry has expired. In both conditions the anchor is
/// unusable, and the holder must create a new anchor.
pub type AnchorError {
  AnchorOutOfBounds(index: Int, length: Int)
  UnknownAnchorTarget
}

/// The `Bias` sum type of the lattice, re-exported here. A caller thus needs
/// no direct dependency on `lattice_sequence` to build an anchor. `Before`
/// attaches an anchor to the grapheme after the gap, so an insert at the gap
/// moves the anchor to the right. `After` attaches the anchor to the grapheme
/// before the gap, so an insert at the gap goes after the anchor. Construct a
/// value with `sequence.Before` or `sequence.After`.
pub type Bias =
  sequence.Bias

/// A stable position in the optimistic text of a `TextState` value. It stays
/// correct across concurrent edits and merges. The type is opaque, so a caller
/// must use `anchor_at`, `start_anchor`, `end_anchor`, or `anchor_from_json`
/// to construct one.
pub opaque type TextAnchor {
  TextAnchor(anchor: sequence.Anchor)
}

/// The operation and the local message id that the kernel submitted for a real
/// edit. The value is `None` when the mutation was a valid change of nothing.
/// See the module docs on an empty edit. The kernel then queued no pending
/// entry, emitted no event, and the caller must send no channel operation.
pub type Submission {
  Submission(operation: TextOperation, message_id: Int)
}

pub fn new(replica_id: ReplicaId) -> TextState {
  let empty = text.new(replica_id)
  TextState(
    replica_id: replica_id,
    sequenced: empty,
    optimistic: empty,
    pending: [],
    next_pending_message_id: 0,
  )
}

/// The visible optimistic string, which is `sequenced` with the pending
/// deltas. A read uses this function.
pub fn value(state: TextState) -> String {
  text.value(state.optimistic)
}

/// The visible sequenced string, which contains the acked deltas only.
pub fn sequenced_value(state: TextState) -> String {
  text.value(state.sequenced)
}

/// The optimistic grapheme count.
pub fn length(state: TextState) -> Int {
  text.length(state.optimistic)
}

/// Return the graphemes in `[start, end)` from the optimistic text. The
/// function returns an error when the range does not satisfy
/// `0 <= start <= end <= length`.
pub fn substring(
  state: TextState,
  start: Int,
  end: Int,
) -> Result(String, EditError) {
  case text.try_substring(state.optimistic, start, end) {
    Ok(value) -> Ok(value)
    Error(text.RangeOutOfBounds(start, end, length)) ->
      Error(SubstringOutOfBounds(start, end, length))
  }
}

fn finish_local(
  state: TextState,
  optimistic: Text,
  operation: TextOperation,
) -> #(TextState, List(TextEvent), TextOperation, Int) {
  let before = value(state)
  let message_id = state.next_pending_message_id
  let state =
    TextState(
      ..state,
      optimistic: optimistic,
      pending: list.append(state.pending, [
        PendingOperation(operation, message_id),
      ]),
      next_pending_message_id: message_id + 1,
    )
  #(state, changed_event(before, value(state)), operation, message_id)
}

fn submitted(
  result: #(TextState, List(TextEvent), TextOperation, Int),
) -> #(TextState, List(TextEvent), Option(Submission)) {
  let #(state, events, operation, message_id) = result
  #(state, events, Some(Submission(operation, message_id)))
}

fn no_operation(
  state: TextState,
) -> #(TextState, List(TextEvent), Option(Submission)) {
  #(state, [], None)
}

fn changed_event(before: String, after: String) -> List(TextEvent) {
  case before == after {
    True -> []
    False -> [TextChanged(after)]
  }
}

/// Insert `value` at the optimistic grapheme `index`.
///
/// The function checks `index` against the optimistic length, also when
/// `value` is empty. An empty insert at a valid index succeeds, and it
/// produces no pending entry, no event, and no submission. See `Submission`.
pub fn insert(
  state: TextState,
  index: Int,
  value: String,
) -> Result(#(TextState, List(TextEvent), Option(Submission)), EditError) {
  case text.try_insert_with_delta(state.optimistic, index, value) {
    Error(sequence.IndexOutOfBounds(index, length)) ->
      Error(InsertOutOfBounds(index, length))
    Ok(#(optimistic, delta)) ->
      case value {
        "" -> Ok(no_operation(state))
        _ ->
          Ok(
            submitted(finish_local(
              state,
              optimistic,
              Insert(index, value, delta),
            )),
          )
      }
  }
}

/// Delete the graphemes in `[start, end)` from the optimistic text.
///
/// An empty range with valid bounds succeeds, and it produces no pending
/// entry, no event, and no submission.
pub fn delete_range(
  state: TextState,
  start: Int,
  end: Int,
) -> Result(#(TextState, List(TextEvent), Option(Submission)), EditError) {
  case text.try_delete_range_with_delta(state.optimistic, start, end) {
    Error(text.RangeOutOfBounds(start, end, length)) ->
      Error(DeleteRangeOutOfBounds(start, end, length))
    Ok(#(optimistic, delta)) ->
      case start == end {
        True -> Ok(no_operation(state))
        False ->
          Ok(
            submitted(finish_local(
              state,
              optimistic,
              DeleteRange(start, end, delta),
            )),
          )
      }
  }
}

/// Replace the graphemes in `[start, end)` with `value`.
///
/// Only an empty range that you replace with the empty string changes nothing.
/// A non-empty range that you replace with the empty string is a real
/// deletion. An empty range that you replace with a non-empty value is a real
/// insertion.
pub fn replace_range(
  state: TextState,
  start: Int,
  end: Int,
  value: String,
) -> Result(#(TextState, List(TextEvent), Option(Submission)), EditError) {
  case text.try_replace_range_with_delta(state.optimistic, start, end, value) {
    Error(text.RangeOutOfBounds(start, end, length)) ->
      Error(ReplaceRangeOutOfBounds(start, end, length))
    Ok(#(optimistic, delta)) ->
      case start == end && value == "" {
        True -> Ok(no_operation(state))
        False ->
          Ok(
            submitted(finish_local(
              state,
              optimistic,
              ReplaceRange(start, end, value, delta),
            )),
          )
      }
  }
}

/// Insert `value` at the end of the optimistic text. An append is always
/// valid, so this function never fails. An empty append changes nothing.
pub fn append(
  state: TextState,
  value: String,
) -> #(TextState, List(TextEvent), Option(Submission)) {
  case value {
    "" -> no_operation(state)
    _ -> {
      let #(optimistic, delta) = text.append_with_delta(state.optimistic, value)
      submitted(finish_local(state, optimistic, Append(value, delta)))
    }
  }
}

/// Merge a new local delta into `sequenced` and `optimistic` in one step. The
/// delta gets no pending entry, because a p2p commit needs no ack.
///
/// Unlike `finish_local`, this function never needs the `Option(Submission)`
/// path for an empty edit. The p2p mode has no pending queue to protect from
/// an entry with no content. Every call thus reports its operation for the
/// broadcast, also a call whose delta changes nothing, for example an insert of
/// `""`.
fn commit_p2p(
  state: TextState,
  operation: TextOperation,
) -> #(TextState, List(TextEvent), TextOperation) {
  let before = value(state)
  let delta = operation_delta(operation)
  let state =
    TextState(
      ..state,
      sequenced: text.merge(state.sequenced, delta),
      optimistic: text.merge(state.optimistic, delta),
    )
  #(state, changed_event(before, value(state)), operation)
}

/// The ack-free p2p form of `insert`. It writes the same delta, but it merges
/// that delta into the confirmed state and the visible state immediately. See
/// `commit_p2p`. It queues no pending entry for a later ack.
pub fn p2p_insert(
  state: TextState,
  index: Int,
  value: String,
) -> Result(#(TextState, List(TextEvent), TextOperation), EditError) {
  case text.try_insert_with_delta(state.optimistic, index, value) {
    Error(sequence.IndexOutOfBounds(index, length)) ->
      Error(InsertOutOfBounds(index, length))
    Ok(#(_, delta)) -> Ok(commit_p2p(state, Insert(index, value, delta)))
  }
}

/// The ack-free p2p form of `delete_range`. See `p2p_insert`.
pub fn p2p_delete_range(
  state: TextState,
  start: Int,
  end: Int,
) -> Result(#(TextState, List(TextEvent), TextOperation), EditError) {
  case text.try_delete_range_with_delta(state.optimistic, start, end) {
    Error(text.RangeOutOfBounds(start, end, length)) ->
      Error(DeleteRangeOutOfBounds(start, end, length))
    Ok(#(_, delta)) -> Ok(commit_p2p(state, DeleteRange(start, end, delta)))
  }
}

/// The ack-free p2p form of `replace_range`. See `p2p_insert`.
pub fn p2p_replace_range(
  state: TextState,
  start: Int,
  end: Int,
  value: String,
) -> Result(#(TextState, List(TextEvent), TextOperation), EditError) {
  case text.try_replace_range_with_delta(state.optimistic, start, end, value) {
    Error(text.RangeOutOfBounds(start, end, length)) ->
      Error(ReplaceRangeOutOfBounds(start, end, length))
    Ok(#(_, delta)) ->
      Ok(commit_p2p(state, ReplaceRange(start, end, value, delta)))
  }
}

/// The ack-free p2p form of `append`. It is always valid, the same as
/// `append`.
pub fn p2p_append(
  state: TextState,
  value: String,
) -> #(TextState, List(TextEvent), TextOperation) {
  let #(_, delta) = text.append_with_delta(state.optimistic, value)
  commit_p2p(state, Append(value, delta))
}

/// Merge the full confirmed CRDT state of a peer into this state. This is
/// the ack-free equivalent of `apply_remote`. It takes a `state` or
/// `channel` snapshot, not one delta.
///
/// A lattice merge is a join, so it never discards a winner. The result is
/// the least upper bound of the two sides.
pub fn p2p_merge(
  state: TextState,
  other: Text,
) -> #(TextState, List(TextEvent)) {
  let before = value(state)
  let sequenced = text.merge(state.sequenced, other)
  let optimistic = replay_pending(sequenced, state.pending)
  let state = TextState(..state, sequenced: sequenced, optimistic: optimistic)
  #(state, changed_event(before, value(state)))
}

pub fn apply_remote(
  state: TextState,
  operation: TextOperation,
) -> #(TextState, List(TextEvent)) {
  let before = value(state)
  let sequenced = text.merge(state.sequenced, operation_delta(operation))
  let optimistic = replay_pending(sequenced, state.pending)
  let state = TextState(..state, sequenced: sequenced, optimistic: optimistic)
  #(state, changed_event(before, value(state)))
}

pub fn ack_local(
  state: TextState,
  operation: TextOperation,
) -> Result(TextState, KernelError) {
  do_ack(state, operation, None)
}

pub fn ack_local_with_message_id(
  state: TextState,
  operation: TextOperation,
  message_id: Int,
) -> Result(TextState, KernelError) {
  do_ack(state, operation, Some(message_id))
}

fn do_ack(
  state: TextState,
  operation: TextOperation,
  expected_message_id: Option(Int),
) -> Result(TextState, KernelError) {
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
            TextState(
              ..state,
              sequenced: text.merge(state.sequenced, operation_delta(operation)),
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

/// Roll back the newest pending local operation. The kernel can roll back the
/// newest entry only, which is LIFO order. To roll back any other entry is a
/// consistency error.
pub fn rollback(
  state: TextState,
  operation: TextOperation,
  message_id: Int,
) -> Result(#(TextState, List(TextEvent)), KernelError) {
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
          let before = value(state)
          let optimistic = replay_pending(state.sequenced, rest)
          let state = TextState(..state, optimistic: optimistic, pending: rest)
          Ok(#(state, changed_event(before, value(state))))
        }
      }
  }
}

/// Replay a local operation that the kernel submitted before, for example an
/// operation that a reconnect put in the stash, as a new pending entry. Unlike
/// `insert` and `delete_range`, this function always queues a pending entry.
/// The kernel already decided that the operation is a real edit, before that
/// operation reached the stash.
pub fn apply_stashed_operation(
  state: TextState,
  operation: TextOperation,
) -> #(TextState, List(TextEvent), TextOperation, Int) {
  let optimistic = text.merge(state.optimistic, operation_delta(operation))
  finish_local(state, optimistic, operation)
}

/// Move the optimistic text into the sequenced state and remove the pending
/// operations. This is the same attach behaviour as in the other optimistic
/// lattice kernels.
pub fn promote_attach(state: TextState) -> TextState {
  TextState(..state, sequenced: state.optimistic, pending: [])
}

pub fn summary(state: TextState) -> Json {
  text.to_json(state.sequenced)
}

/// Load a summary and re-brand it with `replica_id`. The future local deltas
/// thus use the identity of the replica that joins, and not the identity of
/// the replica that wrote the summary.
pub fn from_summary(
  summary_json: String,
  replica_id: ReplicaId,
) -> Result(TextState, json.DecodeError) {
  case text.from_json(summary_json) {
    Ok(parsed) -> Ok(from_sequenced(parsed, replica_id))
    Error(error) -> Error(error)
  }
}

pub fn from_sequenced(sequenced: Text, replica_id: ReplicaId) -> TextState {
  let rebranded = text.merge(text.new(replica_id), sequenced)
  TextState(
    replica_id: replica_id,
    sequenced: rebranded,
    optimistic: rebranded,
    pending: [],
    next_pending_message_id: 0,
  )
}

pub fn check_cache_coherence(state: TextState) -> Result(Nil, String) {
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
    DeleteRangeOutOfBounds(start, end, length) ->
      "delete range "
      <> int.to_string(start)
      <> ".."
      <> int.to_string(end)
      <> " invalid for length "
      <> int.to_string(length)
    ReplaceRangeOutOfBounds(start, end, length) ->
      "replace range "
      <> int.to_string(start)
      <> ".."
      <> int.to_string(end)
      <> " invalid for length "
      <> int.to_string(length)
    SubstringOutOfBounds(start, end, length) ->
      "substring range "
      <> int.to_string(start)
      <> ".."
      <> int.to_string(end)
      <> " invalid for length "
      <> int.to_string(length)
  }
}

pub fn anchor_error_detail(error: AnchorError) -> String {
  case error {
    AnchorOutOfBounds(index, length) ->
      "anchor index "
      <> int.to_string(index)
      <> " outside 0.."
      <> int.to_string(length)
    UnknownAnchorTarget -> "anchor target is unknown; re-anchor"
  }
}

/// Create an anchor at the gap before the optimistic grapheme at `index`.
///
/// Valid positions are `0 <= index <= length`.
pub fn anchor_at(
  state: TextState,
  index: Int,
  bias: Bias,
) -> Result(TextAnchor, AnchorError) {
  case text.try_anchor_at(state.optimistic, index, bias) {
    Ok(anchor) -> Ok(TextAnchor(anchor))
    Error(sequence.AnchorIndexOutOfBounds(index, length)) ->
      Error(AnchorOutOfBounds(index, length))
    Error(sequence.UnknownAnchorTarget) -> Error(UnknownAnchorTarget)
  }
}

/// Resolve an anchor to a current optimistic grapheme index in
/// `[0, length]`.
pub fn resolve_anchor(
  state: TextState,
  anchor: TextAnchor,
) -> Result(Int, AnchorError) {
  let TextAnchor(inner) = anchor
  case text.try_resolve_anchor(state.optimistic, inner) {
    Ok(index) -> Ok(index)
    Error(sequence.AnchorIndexOutOfBounds(index, length)) ->
      Error(AnchorOutOfBounds(index, length))
    Error(sequence.UnknownAnchorTarget) -> Error(UnknownAnchorTarget)
  }
}

/// An anchor at the start of the text. Always resolves to 0.
pub fn start_anchor() -> TextAnchor {
  TextAnchor(text.start_anchor())
}

/// An anchor at the end of the text. It always resolves to the current
/// grapheme count, and it moves as the text becomes longer.
pub fn end_anchor() -> TextAnchor {
  TextAnchor(text.end_anchor())
}

/// Encode an anchor as a self-describing JSON value.
pub fn anchor_to_json(anchor: TextAnchor) -> Json {
  let TextAnchor(inner) = anchor
  text.anchor_to_json(inner)
}

/// Decode an anchor from a JSON string produced by `anchor_to_json`.
pub fn anchor_from_json(
  json_string: String,
) -> Result(TextAnchor, json.DecodeError) {
  case text.anchor_from_json(json_string) {
    Ok(anchor) -> Ok(TextAnchor(anchor))
    Error(error) -> Error(error)
  }
}

fn operation_delta(operation: TextOperation) -> Text {
  case operation {
    Insert(_, _, delta)
    | DeleteRange(_, _, delta)
    | ReplaceRange(_, _, _, delta)
    | Append(_, delta) -> delta
  }
}

fn replay_pending(sequenced: Text, pending: List(PendingOperation)) -> Text {
  list.fold(pending, sequenced, fn(acc, pending) {
    text.merge(acc, operation_delta(pending.operation))
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
