/// <reference types="./sequence_kernel.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $replica_id from "../../lattice_core/lattice_core/replica_id.mjs";
import * as $sequence from "../../lattice_sequence/lattice_sequence/sequence.mjs";
import {
  Ok,
  Error,
  toList,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
  isEqual,
} from "../gleam.mjs";
import * as $wire from "../watershed/wire.mjs";

export class SequenceState extends $CustomType {
  constructor(replica_id, sequenced, optimistic, pending, next_pending_message_id) {
    super();
    this.replica_id = replica_id;
    this.sequenced = sequenced;
    this.optimistic = optimistic;
    this.pending = pending;
    this.next_pending_message_id = next_pending_message_id;
  }
}
export const SequenceState$SequenceState = (replica_id, sequenced, optimistic, pending, next_pending_message_id) =>
  new SequenceState(replica_id,
  sequenced,
  optimistic,
  pending,
  next_pending_message_id);
export const SequenceState$isSequenceState = (value) =>
  value instanceof SequenceState;
export const SequenceState$SequenceState$replica_id = (value) =>
  value.replica_id;
export const SequenceState$SequenceState$0 = (value) => value.replica_id;
export const SequenceState$SequenceState$sequenced = (value) => value.sequenced;
export const SequenceState$SequenceState$1 = (value) => value.sequenced;
export const SequenceState$SequenceState$optimistic = (value) =>
  value.optimistic;
export const SequenceState$SequenceState$2 = (value) => value.optimistic;
export const SequenceState$SequenceState$pending = (value) => value.pending;
export const SequenceState$SequenceState$3 = (value) => value.pending;
export const SequenceState$SequenceState$next_pending_message_id = (value) =>
  value.next_pending_message_id;
export const SequenceState$SequenceState$4 = (value) =>
  value.next_pending_message_id;

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
export const SequenceOperation$Insert = (index, value, delta) =>
  new Insert(index, value, delta);
export const SequenceOperation$isInsert = (value) => value instanceof Insert;
export const SequenceOperation$Insert$index = (value) => value.index;
export const SequenceOperation$Insert$0 = (value) => value.index;
export const SequenceOperation$Insert$value = (value) => value.value;
export const SequenceOperation$Insert$1 = (value) => value.value;
export const SequenceOperation$Insert$delta = (value) => value.delta;
export const SequenceOperation$Insert$2 = (value) => value.delta;

export class Delete extends $CustomType {
  constructor(index, delta) {
    super();
    this.index = index;
    this.delta = delta;
  }
}
export const SequenceOperation$Delete = (index, delta) =>
  new Delete(index, delta);
export const SequenceOperation$isDelete = (value) => value instanceof Delete;
export const SequenceOperation$Delete$index = (value) => value.index;
export const SequenceOperation$Delete$0 = (value) => value.index;
export const SequenceOperation$Delete$delta = (value) => value.delta;
export const SequenceOperation$Delete$1 = (value) => value.delta;

export class Move extends $CustomType {
  constructor(from_index, to_index, delta) {
    super();
    this.from_index = from_index;
    this.to_index = to_index;
    this.delta = delta;
  }
}
export const SequenceOperation$Move = (from_index, to_index, delta) =>
  new Move(from_index, to_index, delta);
export const SequenceOperation$isMove = (value) => value instanceof Move;
export const SequenceOperation$Move$from_index = (value) => value.from_index;
export const SequenceOperation$Move$0 = (value) => value.from_index;
export const SequenceOperation$Move$to_index = (value) => value.to_index;
export const SequenceOperation$Move$1 = (value) => value.to_index;
export const SequenceOperation$Move$delta = (value) => value.delta;
export const SequenceOperation$Move$2 = (value) => value.delta;

export class Replace extends $CustomType {
  constructor(index, value, delta) {
    super();
    this.index = index;
    this.value = value;
    this.delta = delta;
  }
}
export const SequenceOperation$Replace = (index, value, delta) =>
  new Replace(index, value, delta);
export const SequenceOperation$isReplace = (value) => value instanceof Replace;
export const SequenceOperation$Replace$index = (value) => value.index;
export const SequenceOperation$Replace$0 = (value) => value.index;
export const SequenceOperation$Replace$value = (value) => value.value;
export const SequenceOperation$Replace$1 = (value) => value.value;
export const SequenceOperation$Replace$delta = (value) => value.delta;
export const SequenceOperation$Replace$2 = (value) => value.delta;

export class SequenceChanged extends $CustomType {
  constructor(values) {
    super();
    this.values = values;
  }
}
export const SequenceEvent$SequenceChanged = (values) =>
  new SequenceChanged(values);
export const SequenceEvent$isSequenceChanged = (value) =>
  value instanceof SequenceChanged;
export const SequenceEvent$SequenceChanged$values = (value) => value.values;
export const SequenceEvent$SequenceChanged$0 = (value) => value.values;

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

export class DeleteOutOfBounds extends $CustomType {
  constructor(index, length) {
    super();
    this.index = index;
    this.length = length;
  }
}
export const EditError$DeleteOutOfBounds = (index, length) =>
  new DeleteOutOfBounds(index, length);
export const EditError$isDeleteOutOfBounds = (value) =>
  value instanceof DeleteOutOfBounds;
export const EditError$DeleteOutOfBounds$index = (value) => value.index;
export const EditError$DeleteOutOfBounds$0 = (value) => value.index;
export const EditError$DeleteOutOfBounds$length = (value) => value.length;
export const EditError$DeleteOutOfBounds$1 = (value) => value.length;

export class MoveFromOutOfBounds extends $CustomType {
  constructor(index, length) {
    super();
    this.index = index;
    this.length = length;
  }
}
export const EditError$MoveFromOutOfBounds = (index, length) =>
  new MoveFromOutOfBounds(index, length);
export const EditError$isMoveFromOutOfBounds = (value) =>
  value instanceof MoveFromOutOfBounds;
export const EditError$MoveFromOutOfBounds$index = (value) => value.index;
export const EditError$MoveFromOutOfBounds$0 = (value) => value.index;
export const EditError$MoveFromOutOfBounds$length = (value) => value.length;
export const EditError$MoveFromOutOfBounds$1 = (value) => value.length;

export class MoveToOutOfBounds extends $CustomType {
  constructor(index, length_after_removal) {
    super();
    this.index = index;
    this.length_after_removal = length_after_removal;
  }
}
export const EditError$MoveToOutOfBounds = (index, length_after_removal) =>
  new MoveToOutOfBounds(index, length_after_removal);
export const EditError$isMoveToOutOfBounds = (value) =>
  value instanceof MoveToOutOfBounds;
export const EditError$MoveToOutOfBounds$index = (value) => value.index;
export const EditError$MoveToOutOfBounds$0 = (value) => value.index;
export const EditError$MoveToOutOfBounds$length_after_removal = (value) =>
  value.length_after_removal;
export const EditError$MoveToOutOfBounds$1 = (value) =>
  value.length_after_removal;

export class ReplaceOutOfBounds extends $CustomType {
  constructor(index, length) {
    super();
    this.index = index;
    this.length = length;
  }
}
export const EditError$ReplaceOutOfBounds = (index, length) =>
  new ReplaceOutOfBounds(index, length);
export const EditError$isReplaceOutOfBounds = (value) =>
  value instanceof ReplaceOutOfBounds;
export const EditError$ReplaceOutOfBounds$index = (value) => value.index;
export const EditError$ReplaceOutOfBounds$0 = (value) => value.index;
export const EditError$ReplaceOutOfBounds$length = (value) => value.length;
export const EditError$ReplaceOutOfBounds$1 = (value) => value.length;

export const EditError$index = (value) => value.index;

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

export function new$(replica_id) {
  let empty = $sequence.new$(replica_id);
  return new SequenceState(replica_id, empty, empty, $List$Empty$const, 0);
}

export function values(state) {
  return $sequence.values(state.optimistic);
}

export function sequenced_values(state) {
  return $sequence.values(state.sequenced);
}

export function length(state) {
  return $sequence.length(state.optimistic);
}

function same_json_value(before, after) {
  let $ = $json.parse($json.to_string(before), $wire.json_value_decoder());
  if ($ instanceof Ok) {
    let normalized_before = $[0];
    let $1 = $json.parse($json.to_string(after), $wire.json_value_decoder());
    if ($1 instanceof Ok) {
      let normalized_after = $1[0];
      return isEqual(normalized_before, normalized_after);
    } else {
      return false;
    }
  } else {
    return false;
  }
}

function same_normalized_list(before, after) {
  if (before instanceof $Empty) {
    if (after instanceof $Empty) {
      return true;
    } else {
      return false;
    }
  } else if (after instanceof $Empty) {
    return false;
  } else {
    let before_head = before.head;
    let before_tail = before.tail;
    let after_head = after.head;
    let after_tail = after.tail;
    return same_json_value(before_head, after_head) && same_normalized_list(
      before_tail,
      after_tail,
    );
  }
}

/**
 * Two equal encoded strings are two equal values. Thus the cheap comparison
 * answers the usual no-change case. Only a mismatch runs the comparison of
 * each element, which normalizes the elements and thus accepts a different
 * object key order.
 * 
 * @ignore
 */
function same_json_list(before, after) {
  return (isEqual(
    $list.map(before, $json.to_string),
    $list.map(after, $json.to_string)
  )) || same_normalized_list(before, after);
}

function changed_event(before, after) {
  let $ = same_json_list(before, after);
  if ($) {
    return $List$Empty$const;
  } else {
    return toList([new SequenceChanged(after)]);
  }
}

function finish_local(state, optimistic, operation) {
  let before = values(state);
  let message_id = state.next_pending_message_id;
  let state$1 = new SequenceState(
    state.replica_id,
    state.sequenced,
    optimistic,
    $list.append(
      state.pending,
      toList([new PendingOperation(operation, message_id)]),
    ),
    message_id + 1,
  );
  return [
    state$1,
    changed_event(before, values(state$1)),
    operation,
    message_id,
  ];
}

export function insert(state, index, value) {
  let $ = $sequence.insert_with_delta(state.optimistic, index, value);
  if ($ instanceof Ok) {
    let optimistic = $[0][0];
    let delta = $[0][1];
    return new Ok(
      finish_local(state, optimistic, new Insert(index, value, delta)),
    );
  } else {
    let index$1 = $[0].index;
    let length$1 = $[0].length;
    return new Error(new InsertOutOfBounds(index$1, length$1));
  }
}

export function delete$(state, index) {
  let $ = $sequence.delete_with_delta(state.optimistic, index);
  if ($ instanceof Ok) {
    let optimistic = $[0][0];
    let delta = $[0][1];
    return new Ok(finish_local(state, optimistic, new Delete(index, delta)));
  } else {
    let index$1 = $[0].index;
    let length$1 = $[0].length;
    return new Error(new DeleteOutOfBounds(index$1, length$1));
  }
}

export function move(state, from_index, to_index) {
  let $ = $sequence.move_with_delta(state.optimistic, from_index, to_index);
  if ($ instanceof Ok) {
    let optimistic = $[0][0];
    let delta = $[0][1];
    return new Ok(
      finish_local(state, optimistic, new Move(from_index, to_index, delta)),
    );
  } else {
    let $1 = $[0];
    if ($1 instanceof $sequence.MoveFromIndexOutOfBounds) {
      let index = $1.index;
      let length$1 = $1.length;
      return new Error(new MoveFromOutOfBounds(index, length$1));
    } else {
      let index = $1.index;
      let length_after_removal = $1.length_after_removal;
      return new Error(new MoveToOutOfBounds(index, length_after_removal));
    }
  }
}

export function replace(state, index, value) {
  let $ = $sequence.delete_with_delta(state.optimistic, index);
  if ($ instanceof Ok) {
    let after_delete = $[0][0];
    let delete_delta = $[0][1];
    let $1 = $sequence.insert_with_delta(after_delete, index, value);
    if ($1 instanceof Ok) {
      let optimistic = $1[0][0];
      let insert_delta = $1[0][1];
      let delta = $sequence.merge(delete_delta, insert_delta, state.replica_id);
      return new Ok(
        finish_local(state, optimistic, new Replace(index, value, delta)),
      );
    } else {
      let length$1 = $1[0].length;
      return new Error(new ReplaceOutOfBounds(index, length$1));
    }
  } else {
    let index$1 = $[0].index;
    let length$1 = $[0].length;
    return new Error(new ReplaceOutOfBounds(index$1, length$1));
  }
}

function operation_delta(operation) {
  if (operation instanceof Insert) {
    let delta = operation.delta;
    return delta;
  } else if (operation instanceof Delete) {
    let delta = operation.delta;
    return delta;
  } else if (operation instanceof Move) {
    let delta = operation.delta;
    return delta;
  } else {
    let delta = operation.delta;
    return delta;
  }
}

function replay_pending(sequenced, pending, replica_id) {
  return $list.fold(
    pending,
    sequenced,
    (acc, pending) => {
      return $sequence.merge(
        acc,
        operation_delta(pending.operation),
        replica_id,
      );
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
  let before = values(state);
  let sequenced = $sequence.merge(state.sequenced, other, state.replica_id);
  let optimistic = replay_pending(sequenced, state.pending, state.replica_id);
  let state$1 = new SequenceState(
    state.replica_id,
    sequenced,
    optimistic,
    state.pending,
    state.next_pending_message_id,
  );
  return [state$1, changed_event(before, values(state$1))];
}

export function apply_remote(state, operation) {
  let before = values(state);
  let sequenced = $sequence.merge(
    state.sequenced,
    operation_delta(operation),
    state.replica_id,
  );
  let optimistic = replay_pending(sequenced, state.pending, state.replica_id);
  let state$1 = new SequenceState(
    state.replica_id,
    sequenced,
    optimistic,
    state.pending,
    state.next_pending_message_id,
  );
  return [state$1, changed_event(before, values(state$1))];
}

/**
 * Merge a new local delta into `sequenced` and `optimistic` in one step.
 * The delta gets no pending entry, because a p2p commit needs no ack.
 * This function has the same behaviour as `text_kernel.commit_p2p`.
 * 
 * @ignore
 */
function commit_p2p(state, operation) {
  let before = values(state);
  let delta = operation_delta(operation);
  let state$1 = new SequenceState(
    state.replica_id,
    $sequence.merge(state.sequenced, delta, state.replica_id),
    $sequence.merge(state.optimistic, delta, state.replica_id),
    state.pending,
    state.next_pending_message_id,
  );
  return [state$1, changed_event(before, values(state$1)), operation];
}

/**
 * The ack-free p2p form of `insert`. It writes the same delta, but it merges
 * that delta into the confirmed state and the visible state immediately. See
 * `commit_p2p`. It queues no pending entry for a later ack.
 */
export function p2p_insert(state, index, value) {
  let $ = $sequence.insert_with_delta(state.optimistic, index, value);
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
 * The ack-free p2p form of `delete`. See `p2p_insert`.
 */
export function p2p_delete(state, index) {
  let $ = $sequence.delete_with_delta(state.optimistic, index);
  if ($ instanceof Ok) {
    let delta = $[0][1];
    return new Ok(commit_p2p(state, new Delete(index, delta)));
  } else {
    let index$1 = $[0].index;
    let length$1 = $[0].length;
    return new Error(new DeleteOutOfBounds(index$1, length$1));
  }
}

/**
 * The ack-free p2p form of `move`. See `p2p_insert`.
 */
export function p2p_move(state, from_index, to_index) {
  let $ = $sequence.move_with_delta(state.optimistic, from_index, to_index);
  if ($ instanceof Ok) {
    let delta = $[0][1];
    return new Ok(commit_p2p(state, new Move(from_index, to_index, delta)));
  } else {
    let $1 = $[0];
    if ($1 instanceof $sequence.MoveFromIndexOutOfBounds) {
      let index = $1.index;
      let length$1 = $1.length;
      return new Error(new MoveFromOutOfBounds(index, length$1));
    } else {
      let index = $1.index;
      let length_after_removal = $1.length_after_removal;
      return new Error(new MoveToOutOfBounds(index, length_after_removal));
    }
  }
}

/**
 * The ack-free p2p form of `replace`. See `p2p_insert`.
 */
export function p2p_replace(state, index, value) {
  let $ = $sequence.delete_with_delta(state.optimistic, index);
  if ($ instanceof Ok) {
    let after_delete = $[0][0];
    let delete_delta = $[0][1];
    let $1 = $sequence.insert_with_delta(after_delete, index, value);
    if ($1 instanceof Ok) {
      let insert_delta = $1[0][1];
      let delta = $sequence.merge(delete_delta, insert_delta, state.replica_id);
      return new Ok(commit_p2p(state, new Replace(index, value, delta)));
    } else {
      let length$1 = $1[0].length;
      return new Error(new ReplaceOutOfBounds(index, length$1));
    }
  } else {
    let index$1 = $[0].index;
    let length$1 = $[0].length;
    return new Error(new ReplaceOutOfBounds(index$1, length$1));
  }
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
        new SequenceState(
          state.replica_id,
          $sequence.merge(
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

export function rollback(state, operation, message_id) {
  let $ = pop_last(state.pending);
  if ($ instanceof Ok) {
    let rest = $[0][1];
    let pending_operation = $[0][0].operation;
    let pending_message_id = $[0][0].message_id;
    let $1 = (isEqual(pending_operation, operation)) && (pending_message_id === message_id);
    if ($1) {
      let before = values(state);
      let optimistic = replay_pending(state.sequenced, rest, state.replica_id);
      let state$1 = new SequenceState(
        state.replica_id,
        state.sequenced,
        optimistic,
        rest,
        state.next_pending_message_id,
      );
      return new Ok([state$1, changed_event(before, values(state$1))]);
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

export function apply_stashed_operation(state, operation) {
  let optimistic = $sequence.merge(
    state.optimistic,
    operation_delta(operation),
    state.replica_id,
  );
  return finish_local(state, optimistic, operation);
}

export function promote_attach(state) {
  return new SequenceState(
    state.replica_id,
    state.optimistic,
    state.optimistic,
    $List$Empty$const,
    state.next_pending_message_id,
  );
}

export function summary(state) {
  return $sequence.to_json(state.sequenced, (value) => { return value; });
}

export function from_sequenced(sequenced, replica_id) {
  let rebranded = $sequence.bind(sequenced, replica_id);
  return new SequenceState(
    replica_id,
    rebranded,
    rebranded,
    $List$Empty$const,
    0,
  );
}

export function from_summary(summary_json, replica_id) {
  let $ = $sequence.from_json(summary_json, $wire.json_value_decoder());
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
  } else if (error instanceof DeleteOutOfBounds) {
    let index = error.index;
    let length$1 = error.length;
    return (("delete index " + $int.to_string(index)) + " invalid for length ") + $int.to_string(
      length$1,
    );
  } else if (error instanceof MoveFromOutOfBounds) {
    let index = error.index;
    let length$1 = error.length;
    return (("move source index " + $int.to_string(index)) + " invalid for length ") + $int.to_string(
      length$1,
    );
  } else if (error instanceof MoveToOutOfBounds) {
    let index = error.index;
    let length_after_removal = error.length_after_removal;
    return (("move destination index " + $int.to_string(index)) + " outside 0..") + $int.to_string(
      length_after_removal,
    );
  } else {
    let index = error.index;
    let length$1 = error.length;
    return (("replace index " + $int.to_string(index)) + " invalid for length ") + $int.to_string(
      length$1,
    );
  }
}
