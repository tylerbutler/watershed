/// <reference types="./g_counter_kernel.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $replica_id from "../../lattice_core/lattice_core/replica_id.mjs";
import * as $g_counter from "../../lattice_counters/lattice_counters/g_counter.mjs";
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

export class GCounterState extends $CustomType {
  constructor(replica_id, sequenced, optimistic, pending, next_pending_message_id) {
    super();
    this.replica_id = replica_id;
    this.sequenced = sequenced;
    this.optimistic = optimistic;
    this.pending = pending;
    this.next_pending_message_id = next_pending_message_id;
  }
}
export const GCounterState$GCounterState = (replica_id, sequenced, optimistic, pending, next_pending_message_id) =>
  new GCounterState(replica_id,
  sequenced,
  optimistic,
  pending,
  next_pending_message_id);
export const GCounterState$isGCounterState = (value) =>
  value instanceof GCounterState;
export const GCounterState$GCounterState$replica_id = (value) =>
  value.replica_id;
export const GCounterState$GCounterState$0 = (value) => value.replica_id;
export const GCounterState$GCounterState$sequenced = (value) => value.sequenced;
export const GCounterState$GCounterState$1 = (value) => value.sequenced;
export const GCounterState$GCounterState$optimistic = (value) =>
  value.optimistic;
export const GCounterState$GCounterState$2 = (value) => value.optimistic;
export const GCounterState$GCounterState$pending = (value) => value.pending;
export const GCounterState$GCounterState$3 = (value) => value.pending;
export const GCounterState$GCounterState$next_pending_message_id = (value) =>
  value.next_pending_message_id;
export const GCounterState$GCounterState$4 = (value) =>
  value.next_pending_message_id;

export class PendingDelta extends $CustomType {
  constructor(delta, amount, message_id) {
    super();
    this.delta = delta;
    this.amount = amount;
    this.message_id = message_id;
  }
}
export const PendingDelta$PendingDelta = (delta, amount, message_id) =>
  new PendingDelta(delta, amount, message_id);
export const PendingDelta$isPendingDelta = (value) =>
  value instanceof PendingDelta;
export const PendingDelta$PendingDelta$delta = (value) => value.delta;
export const PendingDelta$PendingDelta$0 = (value) => value.delta;
export const PendingDelta$PendingDelta$amount = (value) => value.amount;
export const PendingDelta$PendingDelta$1 = (value) => value.amount;
export const PendingDelta$PendingDelta$message_id = (value) => value.message_id;
export const PendingDelta$PendingDelta$2 = (value) => value.message_id;

export class Increment extends $CustomType {
  constructor(amount, delta) {
    super();
    this.amount = amount;
    this.delta = delta;
  }
}
export const GCounterOperation$Increment = (amount, delta) =>
  new Increment(amount, delta);
export const GCounterOperation$isIncrement = (value) =>
  value instanceof Increment;
export const GCounterOperation$Increment$amount = (value) => value.amount;
export const GCounterOperation$Increment$0 = (value) => value.amount;
export const GCounterOperation$Increment$delta = (value) => value.delta;
export const GCounterOperation$Increment$1 = (value) => value.delta;

/**
 * `applied` is the observed change of the value. For a remote fragment it
 * can differ from the nominal amount of the operation, when the state
 * contained part of that fragment already. The kernel emits no event when
 * the merge changed nothing, which occurs for an idempotent duplicate and
 * for an increment of zero.
 */
export class Updated extends $CustomType {
  constructor(applied, new_value) {
    super();
    this.applied = applied;
    this.new_value = new_value;
  }
}
export const GCounterEvent$Updated = (applied, new_value) =>
  new Updated(applied, new_value);
export const GCounterEvent$isUpdated = (value) => value instanceof Updated;
export const GCounterEvent$Updated$applied = (value) => value.applied;
export const GCounterEvent$Updated$0 = (value) => value.applied;
export const GCounterEvent$Updated$new_value = (value) => value.new_value;
export const GCounterEvent$Updated$1 = (value) => value.new_value;

export class NegativeIncrement extends $CustomType {
  constructor(amount) {
    super();
    this.amount = amount;
  }
}
export const EditError$NegativeIncrement = (amount) =>
  new NegativeIncrement(amount);
export const EditError$isNegativeIncrement = (value) =>
  value instanceof NegativeIncrement;
export const EditError$NegativeIncrement$amount = (value) => value.amount;
export const EditError$NegativeIncrement$0 = (value) => value.amount;

export class UnexpectedAck extends $CustomType {
  constructor(operation, detail) {
    super();
    this.operation = operation;
    this.detail = detail;
  }
}
export const KernelError$UnexpectedAck = (operation, detail) =>
  new UnexpectedAck(operation, detail);
export const KernelError$isUnexpectedAck = (value) =>
  value instanceof UnexpectedAck;
export const KernelError$UnexpectedAck$operation = (value) => value.operation;
export const KernelError$UnexpectedAck$0 = (value) => value.operation;
export const KernelError$UnexpectedAck$detail = (value) => value.detail;
export const KernelError$UnexpectedAck$1 = (value) => value.detail;

export class UnexpectedRollback extends $CustomType {
  constructor(operation, detail) {
    super();
    this.operation = operation;
    this.detail = detail;
  }
}
export const KernelError$UnexpectedRollback = (operation, detail) =>
  new UnexpectedRollback(operation, detail);
export const KernelError$isUnexpectedRollback = (value) =>
  value instanceof UnexpectedRollback;
export const KernelError$UnexpectedRollback$operation = (value) =>
  value.operation;
export const KernelError$UnexpectedRollback$0 = (value) => value.operation;
export const KernelError$UnexpectedRollback$detail = (value) => value.detail;
export const KernelError$UnexpectedRollback$1 = (value) => value.detail;

export const KernelError$detail = (value) => value.detail;
export const KernelError$operation = (value) => value.operation;

/**
 * A short description of an edit error, for a caller that reports text.
 */
export function edit_error_text(error) {
  let amount = error.amount;
  return "a grow-only counter does not accept the negative amount " + $int.to_string(
    amount,
  );
}

export function new$(replica_id) {
  let zero = $g_counter.new$(replica_id);
  return new GCounterState(replica_id, zero, zero, $List$Empty$const, 0);
}

/**
 * An optimistic read: the sequenced state with the pending local fragments.
 */
export function value(state) {
  return $g_counter.value(state.optimistic);
}

/**
 * A committed-only read: the value that a summary would contain now.
 */
export function sequenced_value(state) {
  return $g_counter.value(state.sequenced);
}

function change_events(before, after) {
  let $ = after === before;
  if ($) {
    return $List$Empty$const;
  } else {
    return toList([new Updated(after - before, after)]);
  }
}

/**
 * Apply a local increment optimistically, and return the outbound operation
 * with its local message id. A negative amount is an error, and the state
 * does not change. Zero is valid, and it emits no event.
 */
export function increment(state, amount) {
  let $ = $g_counter.increment_with_delta(state.optimistic, amount);
  if ($ instanceof Ok) {
    let optimistic = $[0][0];
    let delta = $[0][1];
    let before = $g_counter.value(state.optimistic);
    let after = $g_counter.value(optimistic);
    let message_id = state.next_pending_message_id;
    return new Ok(
      [
        new GCounterState(
          state.replica_id,
          state.sequenced,
          optimistic,
          $list.append(
            state.pending,
            toList([new PendingDelta(delta, amount, message_id)]),
          ),
          message_id + 1,
        ),
        change_events(before, after),
        new Increment(amount, delta),
        message_id,
      ],
    );
  } else {
    let delta = $[0][0];
    return new Error(new NegativeIncrement(delta));
  }
}

/**
 * The acknowledgment-free p2p form of `increment`. It writes the same
 * fragment, but it merges that fragment into the confirmed state and the
 * visible state immediately. It queues no pending entry for a later
 * acknowledgment.
 */
export function p2p_increment(state, amount) {
  let $ = $g_counter.increment_with_delta(state.optimistic, amount);
  if ($ instanceof Ok) {
    let delta = $[0][1];
    let before = $g_counter.value(state.optimistic);
    let optimistic = $g_counter.merge(state.optimistic, delta);
    let after = $g_counter.value(optimistic);
    return new Ok(
      [
        new GCounterState(
          state.replica_id,
          $g_counter.merge(state.sequenced, delta),
          optimistic,
          state.pending,
          state.next_pending_message_id,
        ),
        change_events(before, after),
        new Increment(amount, delta),
      ],
    );
  } else {
    let delta = $[0][0];
    return new Error(new NegativeIncrement(delta));
  }
}

/**
 * Merge the full confirmed CRDT state of a peer into this state. This is the
 * acknowledgment-free equivalent of `apply_remote`. It takes a `state` or
 * `channel` snapshot, not one fragment.
 *
 * A lattice merge is a join, so it never discards a winner. The result is the
 * least upper bound of the two sides.
 */
export function p2p_merge(state, other) {
  let before = $g_counter.value(state.optimistic);
  let optimistic = $g_counter.merge(state.optimistic, other);
  let after = $g_counter.value(optimistic);
  return [
    new GCounterState(
      state.replica_id,
      $g_counter.merge(state.sequenced, other),
      optimistic,
      state.pending,
      state.next_pending_message_id,
    ),
    change_events(before, after),
  ];
}

/**
 * Apply a sequenced operation from another client. Merge its fragment into
 * the sequenced base and into the optimistic cache. The lattice laws make the
 * order against the pending fragments unimportant: `(s ⊔ d) ⊔ P = (s ⊔ P) ⊔ d`.
 * A merge that changes nothing emits no event.
 */
export function apply_remote(state, operation) {
  let delta = operation.delta;
  return p2p_merge(state, delta);
}

function do_ack(state, operation, expected_message_id) {
  let $ = state.pending;
  if ($ instanceof $Empty) {
    return new Error(new UnexpectedAck(operation, "pending queue is empty"));
  } else {
    let rest = $.tail;
    let delta = $.head.delta;
    let amount = $.head.amount;
    let pending_message_id = $.head.message_id;
    let operation_amount = operation.amount;
    let operation_delta = operation.delta;
    let _block;
    if (expected_message_id instanceof Some) {
      let message_id = expected_message_id[0];
      _block = message_id === pending_message_id;
    } else {
      _block = true;
    }
    let message_id_matches = _block;
    let $1 = ((operation_amount === amount) && (isEqual(operation_delta, delta))) && message_id_matches;
    if ($1) {
      return new Ok(
        new GCounterState(
          state.replica_id,
          $g_counter.merge(state.sequenced, delta),
          state.optimistic,
          rest,
          state.next_pending_message_id,
        ),
      );
    } else {
      return new Error(
        new UnexpectedAck(
          operation,
          (((("expected pending increment " + $int.to_string(amount)) + " with message id ") + $int.to_string(
            pending_message_id,
          )) + ", got increment ") + $int.to_string(operation_amount),
        ),
      );
    }
  }
}

/**
 * Retire the oldest pending operation when the local operation returns
 * sequenced. Merge its fragment into `sequenced` only. `optimistic` contains
 * that fragment already, so the observed value does not change. This is
 * acknowledgment transparency.
 */
export function ack_local(state, operation) {
  return do_ack(state, operation, Option$None$const);
}

/**
 * The same as `ack_local`, and it also checks the local operation metadata.
 */
export function ack_local_with_message_id(state, operation, message_id) {
  return do_ack(state, operation, new Some(message_id));
}

function rebuild_optimistic(sequenced, pending) {
  return $list.fold(
    pending,
    sequenced,
    (acc, entry) => { return $g_counter.merge(acc, entry.delta); },
  );
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
 * Roll back the newest pending operation. A merge has no inverse, so the
 * kernel computes the optimistic cache again from `sequenced` and the pending
 * fragments that remain. A compensating event reports the amount that the
 * rollback removed. Confirmed state does not change, thus it stays grow-only.
 */
export function rollback(state, operation, message_id) {
  let $ = pop_last(state.pending);
  if ($ instanceof Ok) {
    let rest = $[0][1];
    let delta = $[0][0].delta;
    let amount = $[0][0].amount;
    let pending_message_id = $[0][0].message_id;
    let operation_amount = operation.amount;
    let operation_delta = operation.delta;
    let $1 = ((operation_amount === amount) && (isEqual(operation_delta, delta))) && (message_id === pending_message_id);
    if ($1) {
      let before = $g_counter.value(state.optimistic);
      let optimistic = rebuild_optimistic(state.sequenced, rest);
      let after = $g_counter.value(optimistic);
      return new Ok(
        [
          new GCounterState(
            state.replica_id,
            state.sequenced,
            optimistic,
            rest,
            state.next_pending_message_id,
          ),
          change_events(before, after),
        ],
      );
    } else {
      return new Error(
        new UnexpectedRollback(
          operation,
          (((((("expected newest pending increment " + $int.to_string(amount)) + " with message id ") + $int.to_string(
            pending_message_id,
          )) + ", got increment ") + $int.to_string(operation_amount)) + " with message id ") + $int.to_string(
            message_id,
          ),
        ),
      );
    }
  } else {
    return new Error(
      new UnexpectedRollback(operation, "pending queue is empty"),
    );
  }
}

/**
 * Apply a stashed operation again after a reconnect, so that it is visible
 * optimistically and is pending again. The function returns the *same*
 * operation, for routing. It does not generate another increment.
 *
 * The kernel merges the cumulative fragment of the operation. That merge is
 * idempotent when the fragment applied already, for example when the summary
 * that the client loaded contained it. The kernel emits the observed change
 * of the value, and it emits nothing when the merge changed nothing.
 */
export function apply_stashed_operation(state, operation) {
  let amount = operation.amount;
  let delta = operation.delta;
  let before = $g_counter.value(state.optimistic);
  let optimistic = $g_counter.merge(state.optimistic, delta);
  let after = $g_counter.value(optimistic);
  let message_id = state.next_pending_message_id;
  return [
    new GCounterState(
      state.replica_id,
      state.sequenced,
      optimistic,
      $list.append(
        state.pending,
        toList([new PendingDelta(delta, amount, message_id)]),
      ),
      message_id + 1,
    ),
    change_events(before, after),
    operation,
    message_id,
  ];
}

/**
 * The summary to store: the sequenced CRDT state only. It contains no pending
 * local fragment.
 */
export function summary(state) {
  return $g_counter.to_json(state.sequenced);
}

/**
 * Build a new state from a sequenced CRDT value that is parsed already. That
 * value is the snapshot payload of the channel layer. The function re-brands
 * it under the `replica_id` of the loading client, the same as
 * `from_summary`, so that the future fragments use the correct replica key.
 */
export function from_sequenced(state, replica_id) {
  let sequenced = $g_counter.merge($g_counter.new$(replica_id), state);
  return new GCounterState(
    replica_id,
    sequenced,
    sequenced,
    $List$Empty$const,
    0,
  );
}

/**
 * Build a new state from a stored summary. The parsed counter carries the
 * replica identity of the client that wrote the summary. The function thus
 * re-brands it with `merge(new(replica_id), parsed)`, because the lattice
 * merge keeps the self id of `a`. Without that step, the loading client would
 * submit its future fragments under the replica key of the summary writer,
 * and the two would collide.
 */
export function from_summary(summary_json, replica_id) {
  let $ = $g_counter.from_json(summary_json);
  if ($ instanceof Ok) {
    let parsed = $[0];
    return new Ok(from_sequenced(parsed, replica_id));
  } else {
    return $;
  }
}

/**
 * An invariant for the tests: the cached `optimistic` state must equal
 * `sequenced` with every pending fragment merged into it again. This function
 * is the `check` hook of the fuzz model, so a test finds a stale cache one
 * command after the fault.
 */
export function check_cache_coherence(state) {
  let recomputed = rebuild_optimistic(state.sequenced, state.pending);
  let $ = isEqual(recomputed, state.optimistic);
  if ($) {
    return new Ok(undefined);
  } else {
    return new Error(
      (("optimistic cache diverged from sequenced + pending: cached value " + $int.to_string(
        $g_counter.value(state.optimistic),
      )) + ", recomputed ") + $int.to_string($g_counter.value(recomputed)),
    );
  }
}
