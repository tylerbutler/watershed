import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import lattice_core/replica_id.{type ReplicaId}
import lattice_sequence/sequence
import lattice_text/text.{type Text}

/// Pure, runtime-independent state for a collaborative plain-text CRDT.
///
/// Mirrors `sequence_kernel.SequenceState`: `sequenced` holds acknowledged
/// local and remote deltas (and is what summaries persist), `optimistic`
/// holds `sequenced` plus every still-pending local delta (and is what reads
/// use), and `pending` is a FIFO queue of local operations awaiting
/// acknowledgement.
pub type TextState {
  TextState(
    replica_id: ReplicaId,
    sequenced: Text,
    optimistic: Text,
    pending: List(PendingOp),
    next_pending_message_id: Int,
  )
}

pub type PendingOp {
  PendingOp(op: TextOp, message_id: Int)
}

/// Every grapheme index in these constructors records author intent for
/// diagnostics only. `delta` is the authoritative CRDT payload; a remote
/// replica applies `delta`, never the diagnostic index/value fields.
pub type TextOp {
  Insert(index: Int, value: String, delta: Text)
  DeleteRange(start: Int, end: Int, delta: Text)
  ReplaceRange(start: Int, end: Int, value: String, delta: Text)
  Append(value: String, delta: Text)
}

/// Emitted only when the visible optimistic string actually changes. A
/// state-shaped event avoids reporting an author's stale index as the final
/// position after concurrent edits.
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

/// An error returned when an anchor cannot be created or resolved.
///
/// `UnknownAnchorTarget` means the anchor references a grapheme this replica
/// has never seen (created remotely and not yet merged), or one that was
/// compacted away and whose forwarding entry has since expired. Either way
/// the anchor is unusable and the holder should re-anchor.
pub type AnchorError {
  AnchorOutOfBounds(index: Int, length: Int)
  UnknownAnchorTarget
}

/// The lattice `Bias` sum, re-exported so callers don't need a direct
/// `lattice_sequence` dependency just to build anchors. `Before` attaches an
/// anchor to the following grapheme (inserts at the gap push it right);
/// `After` attaches it to the preceding grapheme (inserts at the gap land
/// after it). Construct values with `sequence.Before` / `sequence.After`.
pub type Bias =
  sequence.Bias

/// A stable position in a `TextState`'s optimistic text that survives
/// concurrent edits and merges. Opaque so callers can't construct one
/// without going through `anchor_at`, `start_anchor`, `end_anchor`, or
/// `anchor_from_json`.
pub opaque type TextAnchor {
  TextAnchor(anchor: sequence.Anchor)
}

/// The op and local message ID submitted for a real edit. `None` when the
/// mutation was a valid no-op (see module docs on empty edits): no pending
/// entry was queued, no event fired, and no channel op should be sent.
pub type Submission {
  Submission(op: TextOp, message_id: Int)
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

/// The optimistic (sequenced + pending) visible string. Reads use this.
pub fn value(state: TextState) -> String {
  text.value(state.optimistic)
}

/// The sequenced (acknowledged) visible string.
pub fn sequenced_value(state: TextState) -> String {
  text.value(state.sequenced)
}

/// The optimistic grapheme count.
pub fn length(state: TextState) -> Int {
  text.length(state.optimistic)
}

/// Return the graphemes in `[start, end)` from the optimistic text, or an
/// error when the range does not satisfy `0 <= start <= end <= length`.
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
  op: TextOp,
) -> #(TextState, List(TextEvent), TextOp, Int) {
  let before = value(state)
  let message_id = state.next_pending_message_id
  let state =
    TextState(
      ..state,
      optimistic: optimistic,
      pending: list.append(state.pending, [PendingOp(op, message_id)]),
      next_pending_message_id: message_id + 1,
    )
  #(state, changed_event(before, value(state)), op, message_id)
}

fn submitted(
  result: #(TextState, List(TextEvent), TextOp, Int),
) -> #(TextState, List(TextEvent), Option(Submission)) {
  let #(state, events, op, message_id) = result
  #(state, events, Some(Submission(op, message_id)))
}

fn no_op(
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
/// Validates `index` against the optimistic length even when `value` is
/// empty. An empty insert at a valid index succeeds without a pending
/// entry, event, or submission (see `Submission`).
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
        "" -> Ok(no_op(state))
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
/// An empty range at valid bounds succeeds without a pending entry, event,
/// or submission.
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
        True -> Ok(no_op(state))
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
/// Only an empty range replaced with the empty string is a no-op: a
/// non-empty range replaced with the empty string is a real deletion, and an
/// empty range replaced with a non-empty value is a real insertion.
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
        True -> Ok(no_op(state))
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

/// Insert `value` at the end of the optimistic text. Appending is always
/// valid, so this never fails. An empty append is a no-op.
pub fn append(
  state: TextState,
  value: String,
) -> #(TextState, List(TextEvent), Option(Submission)) {
  case value {
    "" -> no_op(state)
    _ -> {
      let #(optimistic, delta) = text.append_with_delta(state.optimistic, value)
      submitted(finish_local(state, optimistic, Append(value, delta)))
    }
  }
}

pub fn apply_remote(
  state: TextState,
  op: TextOp,
) -> #(TextState, List(TextEvent)) {
  let before = value(state)
  let sequenced = text.merge(state.sequenced, op_delta(op))
  let optimistic = replay_pending(sequenced, state.pending)
  let state = TextState(..state, sequenced: sequenced, optimistic: optimistic)
  #(state, changed_event(before, value(state)))
}

pub fn ack_local(
  state: TextState,
  op: TextOp,
) -> Result(TextState, KernelError) {
  do_ack(state, op, None)
}

pub fn ack_local_with_message_id(
  state: TextState,
  op: TextOp,
  message_id: Int,
) -> Result(TextState, KernelError) {
  do_ack(state, op, Some(message_id))
}

fn do_ack(
  state: TextState,
  op: TextOp,
  expected_message_id: Option(Int),
) -> Result(TextState, KernelError) {
  case state.pending {
    [] -> Error(UnexpectedAck("pending queue is empty"))
    [PendingOp(pending_op, pending_message_id), ..rest] -> {
      let id_matches = case expected_message_id {
        None -> True
        Some(message_id) -> message_id == pending_message_id
      }
      case pending_op == op && id_matches {
        True ->
          Ok(
            TextState(
              ..state,
              sequenced: text.merge(state.sequenced, op_delta(op)),
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

/// Roll back the newest pending local op. Only the newest entry may be
/// rolled back (LIFO); rolling back anything else is a consistency error.
pub fn rollback(
  state: TextState,
  op: TextOp,
  message_id: Int,
) -> Result(#(TextState, List(TextEvent)), KernelError) {
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
          let before = value(state)
          let optimistic = replay_pending(state.sequenced, rest)
          let state = TextState(..state, optimistic: optimistic, pending: rest)
          Ok(#(state, changed_event(before, value(state))))
        }
      }
  }
}

/// Replay a previously-submitted local op (for example after a reconnect
/// stashed it) as a fresh pending entry. Unlike `insert`/`delete_range`/etc,
/// this always queues a pending entry: the op was already decided to be a
/// real edit before it reached the stash.
pub fn apply_stashed_op(
  state: TextState,
  op: TextOp,
) -> #(TextState, List(TextEvent), TextOp, Int) {
  let optimistic = text.merge(state.optimistic, op_delta(op))
  finish_local(state, optimistic, op)
}

/// Promote the optimistic text to sequenced state and clear pending ops,
/// matching the attach behavior of the other optimistic lattice kernels.
pub fn promote_attach(state: TextState) -> TextState {
  TextState(..state, sequenced: state.optimistic, pending: [])
}

pub fn summary(state: TextState) -> Json {
  text.to_json(state.sequenced)
}

/// Load a summary and rebrand it to `replica_id`, so future local deltas use
/// the joining replica's identity rather than whichever replica produced the
/// summary.
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

/// An anchor at the end of the text. Always resolves to the current
/// grapheme length, tracking growth.
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

fn op_delta(op: TextOp) -> Text {
  case op {
    Insert(_, _, delta)
    | DeleteRange(_, _, delta)
    | ReplaceRange(_, _, _, delta)
    | Append(_, delta) -> delta
  }
}

fn replay_pending(sequenced: Text, pending: List(PendingOp)) -> Text {
  list.fold(pending, sequenced, fn(acc, pending) {
    text.merge(acc, op_delta(pending.op))
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
