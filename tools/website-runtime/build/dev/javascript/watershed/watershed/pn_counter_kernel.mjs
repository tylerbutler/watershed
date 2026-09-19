/// <reference types="./pn_counter_kernel.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $replica_id from "../../lattice_core/lattice_core/replica_id.mjs";
import * as $pn_counter from "../../lattice_counters/lattice_counters/pn_counter.mjs";
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

const FILEPATH = "src/watershed/pn_counter_kernel.gleam";

export class PnCounterState extends $CustomType {
  constructor(replica_id, sequenced, optimistic, pending, next_pending_message_id) {
    super();
    this.replica_id = replica_id;
    this.sequenced = sequenced;
    this.optimistic = optimistic;
    this.pending = pending;
    this.next_pending_message_id = next_pending_message_id;
  }
}
export const PnCounterState$PnCounterState = (replica_id, sequenced, optimistic, pending, next_pending_message_id) =>
  new PnCounterState(replica_id,
  sequenced,
  optimistic,
  pending,
  next_pending_message_id);
export const PnCounterState$isPnCounterState = (value) =>
  value instanceof PnCounterState;
export const PnCounterState$PnCounterState$replica_id = (value) =>
  value.replica_id;
export const PnCounterState$PnCounterState$0 = (value) => value.replica_id;
export const PnCounterState$PnCounterState$sequenced = (value) =>
  value.sequenced;
export const PnCounterState$PnCounterState$1 = (value) => value.sequenced;
export const PnCounterState$PnCounterState$optimistic = (value) =>
  value.optimistic;
export const PnCounterState$PnCounterState$2 = (value) => value.optimistic;
export const PnCounterState$PnCounterState$pending = (value) => value.pending;
export const PnCounterState$PnCounterState$3 = (value) => value.pending;
export const PnCounterState$PnCounterState$next_pending_message_id = (value) =>
  value.next_pending_message_id;
export const PnCounterState$PnCounterState$4 = (value) =>
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

export class Update extends $CustomType {
  constructor(amount, delta) {
    super();
    this.amount = amount;
    this.delta = delta;
  }
}
export const PnCounterOperation$Update = (amount, delta) =>
  new Update(amount, delta);
export const PnCounterOperation$isUpdate = (value) => value instanceof Update;
export const PnCounterOperation$Update$amount = (value) => value.amount;
export const PnCounterOperation$Update$0 = (value) => value.amount;
export const PnCounterOperation$Update$delta = (value) => value.delta;
export const PnCounterOperation$Update$1 = (value) => value.delta;

/**
 * `applied` is the observed change of the value. For a remote delta it can
 * differ from the nominal amount of the operation, when the state already
 * contained part of that delta. The kernel emits no event at all when the
 * whole merge changed nothing, which occurs for an idempotent duplicate. A
 * local update always reports its amount, and zero is an amount.
 * `counter_kernel` behaves the same way.
 */
export class Updated extends $CustomType {
  constructor(applied, new_value) {
    super();
    this.applied = applied;
    this.new_value = new_value;
  }
}
export const PnCounterEvent$Updated = (applied, new_value) =>
  new Updated(applied, new_value);
export const PnCounterEvent$isUpdated = (value) => value instanceof Updated;
export const PnCounterEvent$Updated$applied = (value) => value.applied;
export const PnCounterEvent$Updated$0 = (value) => value.applied;
export const PnCounterEvent$Updated$new_value = (value) => value.new_value;
export const PnCounterEvent$Updated$1 = (value) => value.new_value;

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

export function new$(replica_id) {
  let zero = $pn_counter.new$(replica_id);
  return new PnCounterState(replica_id, zero, zero, $List$Empty$const, 0);
}

/**
 * An optimistic read: the sequenced state with the pending local deltas.
 * `counter_kernel` behaves the same way.
 */
export function value(state) {
  return $pn_counter.value(state.optimistic);
}

/**
 * A committed-only read: the value that a summary would contain now.
 */
export function sequenced_value(state) {
  return $pn_counter.value(state.sequenced);
}

/**
 * The state and the sparse delta for one signed local update. The function
 * splits the sign here, so the grow-only halves of the counter each receive a
 * magnitude of zero or more.
 * 
 * @ignore
 */
function signed_delta(counter, amount) {
  let _block;
  let $1 = amount >= 0;
  if ($1) {
    _block = $pn_counter.increment_with_delta(counter, amount);
  } else {
    _block = $pn_counter.decrement_with_delta(counter, 0 - amount);
  }
  let $ = _block;
  let delta;
  if ($ instanceof Ok) {
    delta = $[0];
  } else {
    throw makeError(
      "let_assert",
      FILEPATH,
      "watershed/pn_counter_kernel",
      389,
      "signed_delta",
      "Pattern match failed, no pattern matched the value.",
      {
        value: $,
        start: 14474,
        end: 14646,
        pattern_start: 14485,
        pattern_end: 14494
      }
    )
  }
  return delta;
}

/**
 * Apply a signed local update optimistically, and return the outbound
 * operation with its local message id. This function handles the sign, so the
 * lattice mutators always receive a magnitude of zero or more.
 */
export function update(state, amount) {
  let $ = signed_delta(state.optimistic, amount);
  let optimistic = $[0];
  let delta = $[1];
  let message_id = state.next_pending_message_id;
  let new_value = $pn_counter.value(optimistic);
  return [
    new PnCounterState(
      state.replica_id,
      state.sequenced,
      optimistic,
      $list.append(
        state.pending,
        toList([new PendingDelta(delta, amount, message_id)]),
      ),
      message_id + 1,
    ),
    toList([new Updated(amount, new_value)]),
    new Update(amount, delta),
    message_id,
  ];
}

/**
 * The ack-free p2p form of `update`. It writes the same delta, but it merges
 * that delta into the confirmed state and the visible state immediately. It
 * queues no pending entry for a later ack. It always reports `amount`, the
 * same as `update`, because this is still a local edit. `counter_kernel`
 * behaves the same way.
 */
export function p2p_update(state, amount) {
  let $ = signed_delta(state.optimistic, amount);
  let delta = $[1];
  let sequenced = $pn_counter.merge(state.sequenced, delta);
  let optimistic = $pn_counter.merge(state.optimistic, delta);
  let new_value = $pn_counter.value(optimistic);
  let new_state = new PnCounterState(
    state.replica_id,
    sequenced,
    optimistic,
    state.pending,
    state.next_pending_message_id,
  );
  return [
    new_state,
    toList([new Updated(amount, new_value)]),
    new Update(amount, delta),
  ];
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
  let before = $pn_counter.value(state.optimistic);
  let optimistic = $pn_counter.merge(state.optimistic, other);
  let after = $pn_counter.value(optimistic);
  let new_state = new PnCounterState(
    state.replica_id,
    $pn_counter.merge(state.sequenced, other),
    optimistic,
    state.pending,
    state.next_pending_message_id,
  );
  let $ = after === before;
  if ($) {
    return [new_state, $List$Empty$const];
  } else {
    return [new_state, toList([new Updated(after - before, after)])];
  }
}

/**
 * Apply a sequenced operation from another client. Merge its delta into the
 * sequenced base and into the optimistic cache. The lattice laws make the
 * order against the pending deltas unimportant: `(s ⊔ d) ⊔ P = (s ⊔ P) ⊔ d`.
 * The kernel emits the observed change of the optimistic value. A merge that
 * changes nothing, because the delta is a duplicate or the state already
 * contains it, emits no event.
 */
export function apply_remote(state, operation) {
  let delta = operation.delta;
  let before = $pn_counter.value(state.optimistic);
  let optimistic = $pn_counter.merge(state.optimistic, delta);
  let after = $pn_counter.value(optimistic);
  let new_state = new PnCounterState(
    state.replica_id,
    $pn_counter.merge(state.sequenced, delta),
    optimistic,
    state.pending,
    state.next_pending_message_id,
  );
  let $ = after === before;
  if ($) {
    return [new_state, $List$Empty$const];
  } else {
    return [new_state, toList([new Updated(after - before, after)])];
  }
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
        new PnCounterState(
          state.replica_id,
          $pn_counter.merge(state.sequenced, delta),
          state.optimistic,
          rest,
          state.next_pending_message_id,
        ),
      );
    } else {
      return new Error(
        new UnexpectedAck(
          operation,
          (((("expected pending update " + $int.to_string(amount)) + " with message id ") + $int.to_string(
            pending_message_id,
          )) + ", got update ") + $int.to_string(operation_amount),
        ),
      );
    }
  }
}

/**
 * Retire the oldest pending operation when the local operation returns
 * sequenced. Merge its delta into `sequenced` only. `optimistic` already
 * contains that delta, so the observed value does not change. This is ack
 * transparency.
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
 * deltas that remain. A compensating event reports the amount that the
 * rollback removed.
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
      let optimistic = $list.fold(
        rest,
        state.sequenced,
        (acc, pending) => { return $pn_counter.merge(acc, pending.delta); },
      );
      let new_value = $pn_counter.value(optimistic);
      return new Ok(
        [
          new PnCounterState(
            state.replica_id,
            state.sequenced,
            optimistic,
            rest,
            state.next_pending_message_id,
          ),
          toList([new Updated(0 - amount, new_value)]),
        ],
      );
    } else {
      return new Error(
        new UnexpectedRollback(
          operation,
          (((((("expected newest pending update " + $int.to_string(amount)) + " with message id ") + $int.to_string(
            pending_message_id,
          )) + ", got update ") + $int.to_string(operation_amount)) + " with message id ") + $int.to_string(
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
 * operation, for routing.
 *
 * The re-increment path of `counter_kernel` differs. This function merges the
 * cumulative delta of the operation. That merge is idempotent when the delta
 * already applied, for example when the summary that the client loaded already
 * contained it. That property is the CRDT benefit that this kernel proves. The
 * kernel emits the observed change of the value, and it emits nothing when the
 * merge changed nothing.
 */
export function apply_stashed_operation(state, operation) {
  let amount = operation.amount;
  let delta = operation.delta;
  let before = $pn_counter.value(state.optimistic);
  let optimistic = $pn_counter.merge(state.optimistic, delta);
  let after = $pn_counter.value(optimistic);
  let message_id = state.next_pending_message_id;
  let new_state = new PnCounterState(
    state.replica_id,
    state.sequenced,
    optimistic,
    $list.append(
      state.pending,
      toList([new PendingDelta(delta, amount, message_id)]),
    ),
    message_id + 1,
  );
  let _block;
  let $ = after === before;
  if ($) {
    _block = $List$Empty$const;
  } else {
    _block = toList([new Updated(after - before, after)]);
  }
  let events = _block;
  return [new_state, events, operation, message_id];
}

/**
 * The summary to store: the sequenced CRDT state only. It contains no pending
 * local delta, the same as `sequenced_entries` of the map kernel.
 */
export function summary(state) {
  return $pn_counter.to_json(state.sequenced);
}

/**
 * Build a new state from a stored summary. The parsed counter carries the
 * replica identity of the client that wrote the summary. The function thus
 * re-brands it with `merge(new(replica_id), parsed)`, because the lattice
 * merge keeps the self id of `a`. Without that step, the loading client would
 * submit its future deltas under the replica key of the summary writer, and
 * the two would collide.
 */
export function from_summary(summary_json, replica_id) {
  let $ = $pn_counter.from_json(summary_json);
  if ($ instanceof Ok) {
    let parsed = $[0];
    let sequenced = $pn_counter.merge($pn_counter.new$(replica_id), parsed);
    return new Ok(
      new PnCounterState(replica_id, sequenced, sequenced, $List$Empty$const, 0),
    );
  } else {
    return $;
  }
}

/**
 * Build a new state from a sequenced CRDT value that is already parsed. That
 * value is the snapshot payload of the channel layer. The function re-brands
 * it under the `replica_id` of the loading client with
 * `merge(new(replica_id), state)`, the same as `from_summary`, so that the
 * future deltas use the correct replica key.
 */
export function from_sequenced(state, replica_id) {
  let sequenced = $pn_counter.merge($pn_counter.new$(replica_id), state);
  return new PnCounterState(
    replica_id,
    sequenced,
    sequenced,
    $List$Empty$const,
    0,
  );
}

/**
 * An invariant for the tests: the cached `optimistic` state must equal
 * `sequenced` with every pending delta merged into it again. This function is
 * the `check` hook of the fuzz model, so a test finds a stale cache one
 * command after the fault.
 */
export function check_cache_coherence(state) {
  let recomputed = $list.fold(
    state.pending,
    state.sequenced,
    (acc, pending) => { return $pn_counter.merge(acc, pending.delta); },
  );
  let $ = isEqual(recomputed, state.optimistic);
  if ($) {
    return new Ok(undefined);
  } else {
    return new Error(
      (("optimistic cache diverged from sequenced + pending: cached value " + $int.to_string(
        $pn_counter.value(state.optimistic),
      )) + ", recomputed ") + $int.to_string($pn_counter.value(recomputed)),
    );
  }
}
