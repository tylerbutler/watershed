/// <reference types="./text_kernel.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $replica_id from "../../lattice_core/lattice_core/replica_id.mjs";
import * as $sequence from "../../lattice_sequence/lattice_sequence/sequence.mjs";
import * as $text from "../../lattice_text/lattice_text/text.mjs";
import {
  Ok,
  Error,
  toList,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
  makeError,
  isEqual,
} from "../gleam.mjs";

const FILEPATH = "src/watershed/text_kernel.gleam";

export class TextState extends $CustomType {
  constructor(replica_id, sequenced, optimistic, pending, next_pending_message_id) {
    super();
    this.replica_id = replica_id;
    this.sequenced = sequenced;
    this.optimistic = optimistic;
    this.pending = pending;
    this.next_pending_message_id = next_pending_message_id;
  }
}
export const TextState$TextState = (replica_id, sequenced, optimistic, pending, next_pending_message_id) =>
  new TextState(replica_id,
  sequenced,
  optimistic,
  pending,
  next_pending_message_id);
export const TextState$isTextState = (value) => value instanceof TextState;
export const TextState$TextState$replica_id = (value) => value.replica_id;
export const TextState$TextState$0 = (value) => value.replica_id;
export const TextState$TextState$sequenced = (value) => value.sequenced;
export const TextState$TextState$1 = (value) => value.sequenced;
export const TextState$TextState$optimistic = (value) => value.optimistic;
export const TextState$TextState$2 = (value) => value.optimistic;
export const TextState$TextState$pending = (value) => value.pending;
export const TextState$TextState$3 = (value) => value.pending;
export const TextState$TextState$next_pending_message_id = (value) =>
  value.next_pending_message_id;
export const TextState$TextState$4 = (value) => value.next_pending_message_id;

export class PendingOperation extends $CustomType {
  constructor(operation, message_id) {
    super();
    this.operation = operation;
    this.message_id = message_id;
  }
}
export const PendingOperation$PendingOperation = (operation, message_id) =>
  new PendingOperation(operation, message_id);
export const PendingOperation$isPendingOperation = (value) =>
  value instanceof PendingOperation;
export const PendingOperation$PendingOperation$operation = (value) =>
  value.operation;
export const PendingOperation$PendingOperation$0 = (value) => value.operation;
export const PendingOperation$PendingOperation$message_id = (value) =>
  value.message_id;
export const PendingOperation$PendingOperation$1 = (value) => value.message_id;

export class Insert extends $CustomType {
  constructor(index, value, delta) {
    super();
    this.index = index;
    this.value = value;
    this.delta = delta;
  }
}
export const TextOperation$Insert = (index, value, delta) =>
  new Insert(index, value, delta);
export const TextOperation$isInsert = (value) => value instanceof Insert;
export const TextOperation$Insert$index = (value) => value.index;
export const TextOperation$Insert$0 = (value) => value.index;
export const TextOperation$Insert$value = (value) => value.value;
export const TextOperation$Insert$1 = (value) => value.value;
export const TextOperation$Insert$delta = (value) => value.delta;
export const TextOperation$Insert$2 = (value) => value.delta;

export class DeleteRange extends $CustomType {
  constructor(start, end, delta) {
    super();
    this.start = start;
    this.end = end;
    this.delta = delta;
  }
}
export const TextOperation$DeleteRange = (start, end, delta) =>
  new DeleteRange(start, end, delta);
export const TextOperation$isDeleteRange = (value) =>
  value instanceof DeleteRange;
export const TextOperation$DeleteRange$start = (value) => value.start;
export const TextOperation$DeleteRange$0 = (value) => value.start;
export const TextOperation$DeleteRange$end = (value) => value.end;
export const TextOperation$DeleteRange$1 = (value) => value.end;
export const TextOperation$DeleteRange$delta = (value) => value.delta;
export const TextOperation$DeleteRange$2 = (value) => value.delta;

export class ReplaceRange extends $CustomType {
  constructor(start, end, value, delta) {
    super();
    this.start = start;
    this.end = end;
    this.value = value;
    this.delta = delta;
  }
}
export const TextOperation$ReplaceRange = (start, end, value, delta) =>
  new ReplaceRange(start, end, value, delta);
export const TextOperation$isReplaceRange = (value) =>
  value instanceof ReplaceRange;
export const TextOperation$ReplaceRange$start = (value) => value.start;
export const TextOperation$ReplaceRange$0 = (value) => value.start;
export const TextOperation$ReplaceRange$end = (value) => value.end;
export const TextOperation$ReplaceRange$1 = (value) => value.end;
export const TextOperation$ReplaceRange$value = (value) => value.value;
export const TextOperation$ReplaceRange$2 = (value) => value.value;
export const TextOperation$ReplaceRange$delta = (value) => value.delta;
export const TextOperation$ReplaceRange$3 = (value) => value.delta;

export class Append extends $CustomType {
  constructor(value, delta) {
    super();
    this.value = value;
    this.delta = delta;
  }
}
export const TextOperation$Append = (value, delta) => new Append(value, delta);
export const TextOperation$isAppend = (value) => value instanceof Append;
export const TextOperation$Append$value = (value) => value.value;
export const TextOperation$Append$0 = (value) => value.value;
export const TextOperation$Append$delta = (value) => value.delta;
export const TextOperation$Append$1 = (value) => value.delta;

export class TextChanged extends $CustomType {
  constructor(value) {
    super();
    this.value = value;
  }
}
export const TextEvent$TextChanged = (value) => new TextChanged(value);
export const TextEvent$isTextChanged = (value) => value instanceof TextChanged;
export const TextEvent$TextChanged$value = (value) => value.value;
export const TextEvent$TextChanged$0 = (value) => value.value;

export class InsertOutOfBounds extends $CustomType {
  constructor(index, length) {
    super();
    this.index = index;
    this.length = length;
  }
}
export const EditError$InsertOutOfBounds = (index, length) =>
  new InsertOutOfBounds(index, length);
export const EditError$isInsertOutOfBounds = (value) =>
  value instanceof InsertOutOfBounds;
export const EditError$InsertOutOfBounds$index = (value) => value.index;
export const EditError$InsertOutOfBounds$0 = (value) => value.index;
export const EditError$InsertOutOfBounds$length = (value) => value.length;
export const EditError$InsertOutOfBounds$1 = (value) => value.length;

export class DeleteRangeOutOfBounds extends $CustomType {
  constructor(start, end, length) {
    super();
    this.start = start;
    this.end = end;
    this.length = length;
  }
}
export const EditError$DeleteRangeOutOfBounds = (start, end, length) =>
  new DeleteRangeOutOfBounds(start, end, length);
export const EditError$isDeleteRangeOutOfBounds = (value) =>
  value instanceof DeleteRangeOutOfBounds;
export const EditError$DeleteRangeOutOfBounds$start = (value) => value.start;
export const EditError$DeleteRangeOutOfBounds$0 = (value) => value.start;
export const EditError$DeleteRangeOutOfBounds$end = (value) => value.end;
export const EditError$DeleteRangeOutOfBounds$1 = (value) => value.end;
export const EditError$DeleteRangeOutOfBounds$length = (value) => value.length;
export const EditError$DeleteRangeOutOfBounds$2 = (value) => value.length;

export class ReplaceRangeOutOfBounds extends $CustomType {
  constructor(start, end, length) {
    super();
    this.start = start;
    this.end = end;
    this.length = length;
  }
}
export const EditError$ReplaceRangeOutOfBounds = (start, end, length) =>
  new ReplaceRangeOutOfBounds(start, end, length);
export const EditError$isReplaceRangeOutOfBounds = (value) =>
  value instanceof ReplaceRangeOutOfBounds;
export const EditError$ReplaceRangeOutOfBounds$start = (value) => value.start;
export const EditError$ReplaceRangeOutOfBounds$0 = (value) => value.start;
export const EditError$ReplaceRangeOutOfBounds$end = (value) => value.end;
export const EditError$ReplaceRangeOutOfBounds$1 = (value) => value.end;
export const EditError$ReplaceRangeOutOfBounds$length = (value) => value.length;
export const EditError$ReplaceRangeOutOfBounds$2 = (value) => value.length;

export class SubstringOutOfBounds extends $CustomType {
  constructor(start, end, length) {
    super();
    this.start = start;
    this.end = end;
    this.length = length;
  }
}
export const EditError$SubstringOutOfBounds = (start, end, length) =>
  new SubstringOutOfBounds(start, end, length);
export const EditError$isSubstringOutOfBounds = (value) =>
  value instanceof SubstringOutOfBounds;
export const EditError$SubstringOutOfBounds$start = (value) => value.start;
export const EditError$SubstringOutOfBounds$0 = (value) => value.start;
export const EditError$SubstringOutOfBounds$end = (value) => value.end;
export const EditError$SubstringOutOfBounds$1 = (value) => value.end;
export const EditError$SubstringOutOfBounds$length = (value) => value.length;
export const EditError$SubstringOutOfBounds$2 = (value) => value.length;

export class UnexpectedAck extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}
export const KernelError$UnexpectedAck = (detail) => new UnexpectedAck(detail);
export const KernelError$isUnexpectedAck = (value) =>
  value instanceof UnexpectedAck;
export const KernelError$UnexpectedAck$detail = (value) => value.detail;
export const KernelError$UnexpectedAck$0 = (value) => value.detail;

export class UnexpectedRollback extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}
export const KernelError$UnexpectedRollback = (detail) =>
  new UnexpectedRollback(detail);
export const KernelError$isUnexpectedRollback = (value) =>
  value instanceof UnexpectedRollback;
export const KernelError$UnexpectedRollback$detail = (value) => value.detail;
export const KernelError$UnexpectedRollback$0 = (value) => value.detail;

export const KernelError$detail = (value) => value.detail;

export class AnchorOutOfBounds extends $CustomType {
  constructor(index, length) {
    super();
    this.index = index;
    this.length = length;
  }
}
export const AnchorError$AnchorOutOfBounds = (index, length) =>
  new AnchorOutOfBounds(index, length);
export const AnchorError$isAnchorOutOfBounds = (value) =>
  value instanceof AnchorOutOfBounds;
export const AnchorError$AnchorOutOfBounds$index = (value) => value.index;
export const AnchorError$AnchorOutOfBounds$0 = (value) => value.index;
export const AnchorError$AnchorOutOfBounds$length = (value) => value.length;
export const AnchorError$AnchorOutOfBounds$1 = (value) => value.length;

export class UnknownAnchorTarget extends $CustomType {}
export const AnchorError$UnknownAnchorTarget$const = new UnknownAnchorTarget();
export const AnchorError$UnknownAnchorTarget = () =>
  AnchorError$UnknownAnchorTarget$const;
export const AnchorError$isUnknownAnchorTarget = (value) =>
  value instanceof UnknownAnchorTarget;

class TextAnchor extends $CustomType {
  constructor(anchor) {
    super();
    this.anchor = anchor;
  }
}

export class Submission extends $CustomType {
  constructor(operation, message_id) {
    super();
    this.operation = operation;
    this.message_id = message_id;
  }
}
export const Submission$Submission = (operation, message_id) =>
  new Submission(operation, message_id);
export const Submission$isSubmission = (value) => value instanceof Submission;
export const Submission$Submission$operation = (value) => value.operation;
export const Submission$Submission$0 = (value) => value.operation;
export const Submission$Submission$message_id = (value) => value.message_id;
export const Submission$Submission$1 = (value) => value.message_id;

export function new$(replica_id) {
  let empty = $text.new$(replica_id);
  return new TextState(replica_id, empty, empty, $List$Empty$const, 0);
}

/**
 * The visible optimistic string, which is `sequenced` with the pending
 * deltas. A read uses this function.
 */
export function value(state) {
  return $text.value(state.optimistic);
}

/**
 * The visible sequenced string, which contains the acked deltas only.
 */
export function sequenced_value(state) {
  return $text.value(state.sequenced);
}

/**
 * The optimistic grapheme count.
 */
export function length(state) {
  return $text.length(state.optimistic);
}

/**
 * Return the graphemes in `[start, end)` from the optimistic text. The
 * function returns an error when the range does not satisfy
 * `0 <= start <= end <= length`.
 */
export function substring(state, start, end) {
  let $ = $text.try_substring(state.optimistic, start, end);
  if ($ instanceof Ok) {
    return $;
  } else {
    let start$1 = $[0].start;
    let end$1 = $[0].end;
    let length$1 = $[0].length;
    return new Error(new SubstringOutOfBounds(start$1, end$1, length$1));
  }
}

function changed_event(before, after) {
  let $ = before === after;
  if ($) {
    return $List$Empty$const;
  } else {
    return toList([new TextChanged(after)]);
  }
}

function finish_local(state, optimistic, operation) {
  let before = value(state);
  let message_id = state.next_pending_message_id;
  let state$1 = new TextState(
    state.replica_id,
    state.sequenced,
    optimistic,
    $list.append(
      state.pending,
      toList([new PendingOperation(operation, message_id)]),
    ),
    message_id + 1,
  );
  return [state$1, changed_event(before, value(state$1)), operation, message_id];
}

function submitted(result) {
  let state = result[0];
  let events = result[1];
  let operation = result[2];
  let message_id = result[3];
  return [state, events, new Some(new Submission(operation, message_id))];
}

function no_operation(state) {
  return [state, $List$Empty$const, Option$None$const];
}

/**
 * Insert `value` at the optimistic grapheme `index`.
 *
 * The function checks `index` against the optimistic length, also when
 * `value` is empty. An empty insert at a valid index succeeds, and it
 * produces no pending entry, no event, and no submission. See `Submission`.
 */
export function insert(state, index, value) {
  let $ = $text.insert_with_delta(state.optimistic, index, value);
  if ($ instanceof Ok) {
    let optimistic = $[0][0];
    let delta = $[0][1];
    if (value === "") {
      return new Ok(no_operation(state));
    } else {
      return new Ok(
        submitted(
          finish_local(state, optimistic, new Insert(index, value, delta)),
        ),
      );
    }
  } else {
    let index$1 = $[0].index;
    let length$1 = $[0].length;
    return new Error(new InsertOutOfBounds(index$1, length$1));
  }
}

/**
 * Delete the graphemes in `[start, end)` from the optimistic text.
 *
 * An empty range with valid bounds succeeds, and it produces no pending
 * entry, no event, and no submission.
 */
export function delete_range(state, start, end) {
  let $ = $text.delete_range_with_delta(state.optimistic, start, end);
  if ($ instanceof Ok) {
    let optimistic = $[0][0];
    let delta = $[0][1];
    let $1 = start === end;
    if ($1) {
      return new Ok(no_operation(state));
    } else {
      return new Ok(
        submitted(
          finish_local(state, optimistic, new DeleteRange(start, end, delta)),
        ),
      );
    }
  } else {
    let start$1 = $[0].start;
    let end$1 = $[0].end;
    let length$1 = $[0].length;
    return new Error(new DeleteRangeOutOfBounds(start$1, end$1, length$1));
  }
}

/**
 * Replace the graphemes in `[start, end)` with `value`.
 *
 * Only an empty range that you replace with the empty string changes nothing.
 * A non-empty range that you replace with the empty string is a real
 * deletion. An empty range that you replace with a non-empty value is a real
 * insertion.
 */
export function replace_range(state, start, end, value) {
  let $ = $text.replace_range_with_delta(state.optimistic, start, end, value);
  if ($ instanceof Ok) {
    let optimistic = $[0][0];
    let delta = $[0][1];
    let $1 = (start === end) && (value === "");
    if ($1) {
      return new Ok(no_operation(state));
    } else {
      return new Ok(
        submitted(
          finish_local(
            state,
            optimistic,
            new ReplaceRange(start, end, value, delta),
          ),
        ),
      );
    }
  } else {
    let start$1 = $[0].start;
    let end$1 = $[0].end;
    let length$1 = $[0].length;
    return new Error(new ReplaceRangeOutOfBounds(start$1, end$1, length$1));
  }
}

/**
 * Insert `value` at the end of the optimistic text. An append is always
 * valid, so this function never fails. An empty append changes nothing.
 */
export function append(state, value) {
  if (value === "") {
    return no_operation(state);
  } else {
    let $ = $text.append_with_delta(state.optimistic, value);
    let optimistic;
    let delta;
    if ($ instanceof Ok) {
      optimistic = $[0][0];
      delta = $[0][1];
    } else {
      throw makeError(
        "let_assert",
        FILEPATH,
        "watershed/text_kernel",
        275,
        "append",
        "Pattern match failed, no pattern matched the value.",
        {
          value: $,
          start: 9040,
          end: 9133,
          pattern_start: 9051,
          pattern_end: 9075
        }
      )
    }
    return submitted(finish_local(state, optimistic, new Append(value, delta)));
  }
}

function operation_delta(operation) {
  if (operation instanceof Insert) {
    let delta = operation.delta;
    return delta;
  } else if (operation instanceof DeleteRange) {
    let delta = operation.delta;
    return delta;
  } else if (operation instanceof ReplaceRange) {
    let delta = operation.delta;
    return delta;
  } else {
    let delta = operation.delta;
    return delta;
  }
}

/**
 * Merge a new local delta into `sequenced` and `optimistic` in one step. The
 * delta gets no pending entry, because a p2p commit needs no ack.
 *
 * Unlike `finish_local`, this function never needs the `Option(Submission)`
 * path for an empty edit. The p2p mode has no pending queue to protect from
 * an entry with no content. Every call thus reports its operation for the
 * broadcast, also a call whose delta changes nothing, for example an insert of
 * `""`.
 * 
 * @ignore
 */
function commit_p2p(state, operation) {
  let before = value(state);
  let delta = operation_delta(operation);
  let state$1 = new TextState(
    state.replica_id,
    $text.merge(state.sequenced, delta, state.replica_id),
    $text.merge(state.optimistic, delta, state.replica_id),
    state.pending,
    state.next_pending_message_id,
  );
  return [state$1, changed_event(before, value(state$1)), operation];
}

/**
 * The ack-free p2p form of `insert`. It writes the same delta, but it merges
 * that delta into the confirmed state and the visible state immediately. See
 * `commit_p2p`. It queues no pending entry for a later ack.
 */
export function p2p_insert(state, index, value) {
  let $ = $text.insert_with_delta(state.optimistic, index, value);
  if ($ instanceof Ok) {
    let delta = $[0][1];
    return new Ok(commit_p2p(state, new Insert(index, value, delta)));
  } else {
    let index$1 = $[0].index;
    let length$1 = $[0].length;
    return new Error(new InsertOutOfBounds(index$1, length$1));
  }
}

/**
 * The ack-free p2p form of `delete_range`. See `p2p_insert`.
 */
export function p2p_delete_range(state, start, end) {
  let $ = $text.delete_range_with_delta(state.optimistic, start, end);
  if ($ instanceof Ok) {
    let delta = $[0][1];
    return new Ok(commit_p2p(state, new DeleteRange(start, end, delta)));
  } else {
    let start$1 = $[0].start;
    let end$1 = $[0].end;
    let length$1 = $[0].length;
    return new Error(new DeleteRangeOutOfBounds(start$1, end$1, length$1));
  }
}

/**
 * The ack-free p2p form of `replace_range`. See `p2p_insert`.
 */
export function p2p_replace_range(state, start, end, value) {
  let $ = $text.replace_range_with_delta(state.optimistic, start, end, value);
  if ($ instanceof Ok) {
    let delta = $[0][1];
    return new Ok(commit_p2p(state, new ReplaceRange(start, end, value, delta)));
  } else {
    let start$1 = $[0].start;
    let end$1 = $[0].end;
    let length$1 = $[0].length;
    return new Error(new ReplaceRangeOutOfBounds(start$1, end$1, length$1));
  }
}

/**
 * The ack-free p2p form of `append`. It is always valid, the same as
 * `append`.
 */
export function p2p_append(state, value) {
  let $ = $text.append_with_delta(state.optimistic, value);
  let delta;
  if ($ instanceof Ok) {
    delta = $[0][1];
  } else {
    throw makeError(
      "let_assert",
      FILEPATH,
      "watershed/text_kernel",
      355,
      "p2p_append",
      "Pattern match failed, no pattern matched the value.",
      {
        value: $,
        start: 11987,
        end: 12063,
        pattern_start: 11998,
        pattern_end: 12013
      }
    )
  }
  return commit_p2p(state, new Append(value, delta));
}

function replay_pending(sequenced, pending, replica_id) {
  return $list.fold(
    pending,
    sequenced,
    (acc, pending) => {
      return $text.merge(acc, operation_delta(pending.operation), replica_id);
    },
  );
}

/**
 * Merge the full confirmed CRDT state of a peer into this state. This is
 * the ack-free equivalent of `apply_remote`. It takes a `state` or
 * `channel` snapshot, not one delta.
 *
 * A lattice merge is a join, so it never discards a winner. The result is
 * the least upper bound of the two sides.
 */
export function p2p_merge(state, other) {
  let before = value(state);
  let sequenced = $text.merge(state.sequenced, other, state.replica_id);
  let optimistic = replay_pending(sequenced, state.pending, state.replica_id);
  let state$1 = new TextState(
    state.replica_id,
    sequenced,
    optimistic,
    state.pending,
    state.next_pending_message_id,
  );
  return [state$1, changed_event(before, value(state$1))];
}

export function apply_remote(state, operation) {
  let before = value(state);
  let sequenced = $text.merge(
    state.sequenced,
    operation_delta(operation),
    state.replica_id,
  );
  let optimistic = replay_pending(sequenced, state.pending, state.replica_id);
  let state$1 = new TextState(
    state.replica_id,
    sequenced,
    optimistic,
    state.pending,
    state.next_pending_message_id,
  );
  return [state$1, changed_event(before, value(state$1))];
}

function do_ack(state, operation, expected_message_id) {
  let $ = state.pending;
  if ($ instanceof $Empty) {
    return new Error(new UnexpectedAck("pending queue is empty"));
  } else {
    let rest = $.tail;
    let pending_operation = $.head.operation;
    let pending_message_id = $.head.message_id;
    let _block;
    if (expected_message_id instanceof Some) {
      let message_id = expected_message_id[0];
      _block = message_id === pending_message_id;
    } else {
      _block = true;
    }
    let id_matches = _block;
    let $1 = (isEqual(pending_operation, operation)) && id_matches;
    if ($1) {
      return new Ok(
        new TextState(
          state.replica_id,
          $text.merge(
            state.sequenced,
            operation_delta(operation),
            state.replica_id,
          ),
          state.optimistic,
          rest,
          state.next_pending_message_id,
        ),
      );
    } else {
      return new Error(
        new UnexpectedAck(
          "expected pending message " + $int.to_string(pending_message_id),
        ),
      );
    }
  }
}

export function ack_local(state, operation) {
  return do_ack(state, operation, Option$None$const);
}

export function ack_local_with_message_id(state, operation, message_id) {
  return do_ack(state, operation, new Some(message_id));
}

function pop_last(pending) {
  if (pending instanceof $Empty) {
    return new Error(undefined);
  } else {
    let $ = pending.tail;
    if ($ instanceof $Empty) {
      let only = pending.head;
      return new Ok([only, $List$Empty$const]);
    } else {
      let head = pending.head;
      let rest = $;
      let $1 = pop_last(rest);
      if ($1 instanceof Ok) {
        let last = $1[0][0];
        let init = $1[0][1];
        return new Ok([last, listPrepend(head, init)]);
      } else {
        return new Error(undefined);
      }
    }
  }
}

/**
 * Roll back the newest pending local operation. The kernel can roll back the
 * newest entry only, which is LIFO order. To roll back any other entry is a
 * consistency error.
 */
export function rollback(state, operation, message_id) {
  let $ = pop_last(state.pending);
  if ($ instanceof Ok) {
    let rest = $[0][1];
    let pending_operation = $[0][0].operation;
    let pending_message_id = $[0][0].message_id;
    let $1 = (isEqual(pending_operation, operation)) && (pending_message_id === message_id);
    if ($1) {
      let before = value(state);
      let optimistic = replay_pending(state.sequenced, rest, state.replica_id);
      let state$1 = new TextState(
        state.replica_id,
        state.sequenced,
        optimistic,
        rest,
        state.next_pending_message_id,
      );
      return new Ok([state$1, changed_event(before, value(state$1))]);
    } else {
      return new Error(
        new UnexpectedRollback(
          "expected newest pending message " + $int.to_string(
            pending_message_id,
          ),
        ),
      );
    }
  } else {
    return new Error(new UnexpectedRollback("pending queue is empty"));
  }
}

/**
 * Replay a local operation that the kernel submitted before, for example an
 * operation that a reconnect put in the stash, as a new pending entry. Unlike
 * `insert` and `delete_range`, this function always queues a pending entry.
 * The kernel already decided that the operation is a real edit, before that
 * operation reached the stash.
 */
export function apply_stashed_operation(state, operation) {
  let optimistic = $text.merge(
    state.optimistic,
    operation_delta(operation),
    state.replica_id,
  );
  return finish_local(state, optimistic, operation);
}

/**
 * Move the optimistic text into the sequenced state and remove the pending
 * operations. This is the same attach behaviour as in the other optimistic
 * lattice kernels.
 */
export function promote_attach(state) {
  return new TextState(
    state.replica_id,
    state.optimistic,
    state.optimistic,
    $List$Empty$const,
    state.next_pending_message_id,
  );
}

export function summary(state) {
  return $text.to_json(state.sequenced);
}

export function from_sequenced(sequenced, replica_id) {
  let rebranded = $text.bind(sequenced, replica_id);
  return new TextState(replica_id, rebranded, rebranded, $List$Empty$const, 0);
}

/**
 * Load a summary and re-brand it with `replica_id`. The future local deltas
 * thus use the identity of the replica that joins, and not the identity of
 * the replica that wrote the summary.
 */
export function from_summary(summary_json, replica_id) {
  let $ = $text.from_json(summary_json);
  if ($ instanceof Ok) {
    let parsed = $[0];
    return new Ok(from_sequenced(parsed, replica_id));
  } else {
    return $;
  }
}

export function check_cache_coherence(state) {
  let $ = isEqual(
    replay_pending(state.sequenced, state.pending, state.replica_id),
    state.optimistic
  );
  if ($) {
    return new Ok(undefined);
  } else {
    return new Error("optimistic cache diverged from sequenced + pending");
  }
}

export function edit_error_detail(error) {
  if (error instanceof InsertOutOfBounds) {
    let index = error.index;
    let length$1 = error.length;
    return (("insert index " + $int.to_string(index)) + " outside 0..") + $int.to_string(
      length$1,
    );
  } else if (error instanceof DeleteRangeOutOfBounds) {
    let start = error.start;
    let end = error.end;
    let length$1 = error.length;
    return (((("delete range " + $int.to_string(start)) + "..") + $int.to_string(
      end,
    )) + " invalid for length ") + $int.to_string(length$1);
  } else if (error instanceof ReplaceRangeOutOfBounds) {
    let start = error.start;
    let end = error.end;
    let length$1 = error.length;
    return (((("replace range " + $int.to_string(start)) + "..") + $int.to_string(
      end,
    )) + " invalid for length ") + $int.to_string(length$1);
  } else {
    let start = error.start;
    let end = error.end;
    let length$1 = error.length;
    return (((("substring range " + $int.to_string(start)) + "..") + $int.to_string(
      end,
    )) + " invalid for length ") + $int.to_string(length$1);
  }
}

export function anchor_error_detail(error) {
  if (error instanceof AnchorOutOfBounds) {
    let index = error.index;
    let length$1 = error.length;
    return (("anchor index " + $int.to_string(index)) + " outside 0..") + $int.to_string(
      length$1,
    );
  } else {
    return "anchor target is unknown; re-anchor";
  }
}

/**
 * Create an anchor at the gap before the optimistic grapheme at `index`.
 *
 * Valid positions are `0 <= index <= length`.
 */
export function anchor_at(state, index, bias) {
  let $ = $text.anchor_at(state.optimistic, index, bias);
  if ($ instanceof Ok) {
    let anchor = $[0];
    return new Ok(new TextAnchor(anchor));
  } else {
    let $1 = $[0];
    if ($1 instanceof $sequence.AnchorIndexOutOfBounds) {
      let index$1 = $1.index;
      let length$1 = $1.length;
      return new Error(new AnchorOutOfBounds(index$1, length$1));
    } else {
      return new Error(AnchorError$UnknownAnchorTarget$const);
    }
  }
}

/**
 * Resolve an anchor to a current optimistic grapheme index in
 * `[0, length]`.
 */
export function resolve_anchor(state, anchor) {
  let inner = anchor.anchor;
  let $ = $text.resolve_anchor(state.optimistic, inner);
  if ($ instanceof Ok) {
    return $;
  } else {
    let $1 = $[0];
    if ($1 instanceof $sequence.AnchorIndexOutOfBounds) {
      let index = $1.index;
      let length$1 = $1.length;
      return new Error(new AnchorOutOfBounds(index, length$1));
    } else {
      return new Error(AnchorError$UnknownAnchorTarget$const);
    }
  }
}

/**
 * An anchor at the start of the text. Always resolves to 0.
 */
export function start_anchor() {
  return new TextAnchor($text.start_anchor());
}

/**
 * An anchor at the end of the text. It always resolves to the current
 * grapheme count, and it moves as the text becomes longer.
 */
export function end_anchor() {
  return new TextAnchor($text.end_anchor());
}

/**
 * Encode an anchor as a self-describing JSON value.
 */
export function anchor_to_json(anchor) {
  let inner = anchor.anchor;
  return $text.anchor_to_json(inner);
}

/**
 * Decode an anchor from a JSON string produced by `anchor_to_json`.
 */
export function anchor_from_json(json_string) {
  let $ = $text.anchor_from_json(json_string);
  if ($ instanceof Ok) {
    let anchor = $[0];
    return new Ok(new TextAnchor(anchor));
  } else {
    return $;
  }
}
