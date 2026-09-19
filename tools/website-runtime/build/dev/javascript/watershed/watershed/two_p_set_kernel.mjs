/// <reference types="./two_p_set_kernel.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $set from "../../gleam_stdlib/gleam/set.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import * as $two_p_set from "../../lattice_sets/lattice_sets/two_p_set.mjs";
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

export class TwoPSetState extends $CustomType {
  constructor(sequenced, optimistic, pending, next_pending_message_id) {
    super();
    this.sequenced = sequenced;
    this.optimistic = optimistic;
    this.pending = pending;
    this.next_pending_message_id = next_pending_message_id;
  }
}
export const TwoPSetState$TwoPSetState = (sequenced, optimistic, pending, next_pending_message_id) =>
  new TwoPSetState(sequenced, optimistic, pending, next_pending_message_id);
export const TwoPSetState$isTwoPSetState = (value) =>
  value instanceof TwoPSetState;
export const TwoPSetState$TwoPSetState$sequenced = (value) => value.sequenced;
export const TwoPSetState$TwoPSetState$0 = (value) => value.sequenced;
export const TwoPSetState$TwoPSetState$optimistic = (value) => value.optimistic;
export const TwoPSetState$TwoPSetState$1 = (value) => value.optimistic;
export const TwoPSetState$TwoPSetState$pending = (value) => value.pending;
export const TwoPSetState$TwoPSetState$2 = (value) => value.pending;
export const TwoPSetState$TwoPSetState$next_pending_message_id = (value) =>
  value.next_pending_message_id;
export const TwoPSetState$TwoPSetState$3 = (value) =>
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

export class Add extends $CustomType {
  constructor(element, delta) {
    super();
    this.element = element;
    this.delta = delta;
  }
}
export const TwoPSetOperation$Add = (element, delta) => new Add(element, delta);
export const TwoPSetOperation$isAdd = (value) => value instanceof Add;
export const TwoPSetOperation$Add$element = (value) => value.element;
export const TwoPSetOperation$Add$0 = (value) => value.element;
export const TwoPSetOperation$Add$delta = (value) => value.delta;
export const TwoPSetOperation$Add$1 = (value) => value.delta;

export class Remove extends $CustomType {
  constructor(element, delta) {
    super();
    this.element = element;
    this.delta = delta;
  }
}
export const TwoPSetOperation$Remove = (element, delta) =>
  new Remove(element, delta);
export const TwoPSetOperation$isRemove = (value) => value instanceof Remove;
export const TwoPSetOperation$Remove$element = (value) => value.element;
export const TwoPSetOperation$Remove$0 = (value) => value.element;
export const TwoPSetOperation$Remove$delta = (value) => value.delta;
export const TwoPSetOperation$Remove$1 = (value) => value.delta;

export const TwoPSetOperation$delta = (value) => value.delta;
export const TwoPSetOperation$element = (value) => value.element;

export class ElementAdded extends $CustomType {
  constructor(element) {
    super();
    this.element = element;
  }
}
export const TwoPSetEvent$ElementAdded = (element) => new ElementAdded(element);
export const TwoPSetEvent$isElementAdded = (value) =>
  value instanceof ElementAdded;
export const TwoPSetEvent$ElementAdded$element = (value) => value.element;
export const TwoPSetEvent$ElementAdded$0 = (value) => value.element;

export class ElementRemoved extends $CustomType {
  constructor(element) {
    super();
    this.element = element;
  }
}
export const TwoPSetEvent$ElementRemoved = (element) =>
  new ElementRemoved(element);
export const TwoPSetEvent$isElementRemoved = (value) =>
  value instanceof ElementRemoved;
export const TwoPSetEvent$ElementRemoved$element = (value) => value.element;
export const TwoPSetEvent$ElementRemoved$0 = (value) => value.element;

export const TwoPSetEvent$element = (value) => value.element;

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

export function new$() {
  let empty = $two_p_set.new$();
  return new TwoPSetState(empty, empty, $List$Empty$const, 0);
}

export function contains(state, element) {
  return $two_p_set.contains(state.optimistic, element);
}

export function values(state) {
  let _pipe = $two_p_set.value(state.optimistic);
  let _pipe$1 = $set.to_list(_pipe);
  return $list.sort(_pipe$1, $string.compare);
}

export function sequenced_values(state) {
  let _pipe = $two_p_set.value(state.sequenced);
  let _pipe$1 = $set.to_list(_pipe);
  return $list.sort(_pipe$1, $string.compare);
}

function events_between(before, after) {
  let _block;
  let _pipe = $list.append(before, after);
  let _pipe$1 = $list.unique(_pipe);
  _block = $list.sort(_pipe$1, $string.compare);
  let keys = _block;
  return $list.filter_map(
    keys,
    (element) => {
      let was_present = $list.any(
        before,
        (value) => { return value === element; },
      );
      let is_present = $list.any(
        after,
        (value) => { return value === element; },
      );
      if (was_present) {
        if (is_present) {
          return new Error(undefined);
        } else {
          return new Ok(new ElementRemoved(element));
        }
      } else if (is_present) {
        return new Ok(new ElementAdded(element));
      } else {
        return new Error(undefined);
      }
    },
  );
}

export function add(state, element) {
  let before = values(state);
  let $ = $two_p_set.add_with_delta(state.optimistic, element);
  let optimistic = $[0];
  let delta = $[1];
  let message_id = state.next_pending_message_id;
  let operation = new Add(element, delta);
  let state$1 = new TwoPSetState(
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
    events_between(before, values(state$1)),
    operation,
    message_id,
  ];
}

export function remove(state, element) {
  let before = values(state);
  let $ = $two_p_set.remove_with_delta(state.optimistic, element);
  let optimistic = $[0];
  let delta = $[1];
  let message_id = state.next_pending_message_id;
  let operation = new Remove(element, delta);
  let state$1 = new TwoPSetState(
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
    events_between(before, values(state$1)),
    operation,
    message_id,
  ];
}

function operation_delta(operation) {
  if (operation instanceof Add) {
    let delta = operation.delta;
    return delta;
  } else {
    let delta = operation.delta;
    return delta;
  }
}

/**
 * Merge a new local delta into `sequenced` and `optimistic` in one step.
 * The delta gets no pending entry, because a p2p commit needs no ack.
 * This function has the same behaviour as `sequence_kernel.commit_p2p`.
 * 
 * @ignore
 */
function commit_p2p(state, operation) {
  let before = values(state);
  let delta = operation_delta(operation);
  let state$1 = new TwoPSetState(
    $two_p_set.merge(state.sequenced, delta),
    $two_p_set.merge(state.optimistic, delta),
    state.pending,
    state.next_pending_message_id,
  );
  return [state$1, events_between(before, values(state$1)), operation];
}

/**
 * The ack-free p2p form of `add`. It commits immediately. See `commit_p2p`.
 */
export function p2p_add(state, element) {
  let $ = $two_p_set.add_with_delta(state.optimistic, element);
  let delta = $[1];
  return commit_p2p(state, new Add(element, delta));
}

/**
 * The ack-free p2p form of `remove`. It commits immediately. See `commit_p2p`.
 */
export function p2p_remove(state, element) {
  let $ = $two_p_set.remove_with_delta(state.optimistic, element);
  let delta = $[1];
  return commit_p2p(state, new Remove(element, delta));
}

function replay_pending(sequenced, pending) {
  return $list.fold(
    pending,
    sequenced,
    (acc, pending) => {
      return $two_p_set.merge(acc, operation_delta(pending.operation));
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
  let sequenced = $two_p_set.merge(state.sequenced, other);
  let optimistic = replay_pending(sequenced, state.pending);
  let state$1 = new TwoPSetState(
    sequenced,
    optimistic,
    state.pending,
    state.next_pending_message_id,
  );
  return [state$1, events_between(before, values(state$1))];
}

export function apply_remote(state, operation) {
  let before = values(state);
  let delta = operation_delta(operation);
  let sequenced = $two_p_set.merge(state.sequenced, delta);
  let optimistic = replay_pending(sequenced, state.pending);
  let state$1 = new TwoPSetState(
    sequenced,
    optimistic,
    state.pending,
    state.next_pending_message_id,
  );
  return [state$1, events_between(before, values(state$1))];
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
    let message_id_matches = _block;
    let $1 = (isEqual(pending_operation, operation)) && message_id_matches;
    if ($1) {
      return new Ok(
        new TwoPSetState(
          $two_p_set.merge(state.sequenced, operation_delta(operation)),
          state.optimistic,
          rest,
          state.next_pending_message_id,
        ),
      );
    } else {
      return new Error(
        new UnexpectedAck(
          (("expected pending op with message id " + $int.to_string(
            pending_message_id,
          )) + ", got message id ") + (() => {
            if (expected_message_id instanceof Some) {
              let message_id = expected_message_id[0];
              return $int.to_string(message_id);
            } else {
              return "unvalidated";
            }
          })(),
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
      let optimistic = replay_pending(state.sequenced, rest);
      let state$1 = new TwoPSetState(
        state.sequenced,
        optimistic,
        rest,
        state.next_pending_message_id,
      );
      return new Ok([state$1, events_between(before, values(state$1))]);
    } else {
      return new Error(
        new UnexpectedRollback(
          (("expected newest pending op with message id " + $int.to_string(
            pending_message_id,
          )) + ", got message id ") + $int.to_string(message_id),
        ),
      );
    }
  } else {
    return new Error(new UnexpectedRollback("pending queue is empty"));
  }
}

export function apply_stashed_operation(state, operation) {
  let before = values(state);
  let optimistic = $two_p_set.merge(
    state.optimistic,
    operation_delta(operation),
  );
  let message_id = state.next_pending_message_id;
  let state$1 = new TwoPSetState(
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
    events_between(before, values(state$1)),
    operation,
    message_id,
  ];
}

export function promote_attach(state) {
  return new TwoPSetState(
    state.optimistic,
    state.optimistic,
    $List$Empty$const,
    state.next_pending_message_id,
  );
}

export function summary(state) {
  return $two_p_set.to_json(state.sequenced);
}

export function from_sequenced(sequenced) {
  return new TwoPSetState(sequenced, sequenced, $List$Empty$const, 0);
}

export function from_summary(summary_json) {
  let $ = $two_p_set.from_json(summary_json);
  if ($ instanceof Ok) {
    let parsed = $[0];
    return new Ok(from_sequenced(parsed));
  } else {
    return $;
  }
}

export function check_cache_coherence(state) {
  let recomputed = replay_pending(state.sequenced, state.pending);
  let $ = isEqual(recomputed, state.optimistic);
  if ($) {
    return new Ok(undefined);
  } else {
    return new Error("optimistic cache diverged from sequenced + pending");
  }
}
