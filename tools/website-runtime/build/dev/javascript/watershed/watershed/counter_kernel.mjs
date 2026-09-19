/// <reference types="./counter_kernel.d.mts" />
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import {
  Ok,
  Error,
  toList,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
} from "../gleam.mjs";

export class CounterState extends $CustomType {
  constructor(value, pending, next_pending_message_id) {
    super();
    this.value = value;
    this.pending = pending;
    this.next_pending_message_id = next_pending_message_id;
  }
}
export const CounterState$CounterState = (value, pending, next_pending_message_id) =>
  new CounterState(value, pending, next_pending_message_id);
export const CounterState$isCounterState = (value) =>
  value instanceof CounterState;
export const CounterState$CounterState$value = (value) => value.value;
export const CounterState$CounterState$0 = (value) => value.value;
export const CounterState$CounterState$pending = (value) => value.pending;
export const CounterState$CounterState$1 = (value) => value.pending;
export const CounterState$CounterState$next_pending_message_id = (value) =>
  value.next_pending_message_id;
export const CounterState$CounterState$2 = (value) =>
  value.next_pending_message_id;

export class PendingIncrement extends $CustomType {
  constructor(increment_amount, message_id) {
    super();
    this.increment_amount = increment_amount;
    this.message_id = message_id;
  }
}
export const PendingOperation$PendingIncrement = (increment_amount, message_id) =>
  new PendingIncrement(increment_amount, message_id);
export const PendingOperation$isPendingIncrement = (value) =>
  value instanceof PendingIncrement;
export const PendingOperation$PendingIncrement$increment_amount = (value) =>
  value.increment_amount;
export const PendingOperation$PendingIncrement$0 = (value) =>
  value.increment_amount;
export const PendingOperation$PendingIncrement$message_id = (value) =>
  value.message_id;
export const PendingOperation$PendingIncrement$1 = (value) => value.message_id;

export class Increment extends $CustomType {
  constructor(increment_amount) {
    super();
    this.increment_amount = increment_amount;
  }
}
export const CounterOperation$Increment = (increment_amount) =>
  new Increment(increment_amount);
export const CounterOperation$isIncrement = (value) =>
  value instanceof Increment;
export const CounterOperation$Increment$increment_amount = (value) =>
  value.increment_amount;
export const CounterOperation$Increment$0 = (value) => value.increment_amount;

export class Incremented extends $CustomType {
  constructor(increment_amount, new_value) {
    super();
    this.increment_amount = increment_amount;
    this.new_value = new_value;
  }
}
export const CounterEvent$Incremented = (increment_amount, new_value) =>
  new Incremented(increment_amount, new_value);
export const CounterEvent$isIncremented = (value) =>
  value instanceof Incremented;
export const CounterEvent$Incremented$increment_amount = (value) =>
  value.increment_amount;
export const CounterEvent$Incremented$0 = (value) => value.increment_amount;
export const CounterEvent$Incremented$new_value = (value) => value.new_value;
export const CounterEvent$Incremented$1 = (value) => value.new_value;

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

export function new$() {
  return new CounterState(0, $List$Empty$const, 0);
}

/**
 * Build a state from a stored summary value. A counter that you load has no
 * pending local operations.
 */
export function from_summary(value) {
  return new CounterState(value, $List$Empty$const, 0);
}

/**
 * The value to store in a summary after the runtime is synchronized.
 */
export function summary_value(state) {
  return state.value;
}

/**
 * Apply a local increment optimistically, and return the outbound operation
 * with its local message id. The Gleam `Int` type enforces the whole-number
 * constraint of Fluid.
 */
export function increment(state, increment_amount) {
  let message_id = state.next_pending_message_id;
  let new_value = state.value + increment_amount;
  return [
    new CounterState(
      new_value,
      $list.append(
        state.pending,
        toList([new PendingIncrement(increment_amount, message_id)]),
      ),
      message_id + 1,
    ),
    toList([new Incremented(increment_amount, new_value)]),
    new Increment(increment_amount),
    message_id,
  ];
}

/**
 * Apply a sequenced operation from another client.
 */
export function apply_remote(state, operation) {
  let increment_amount = operation.increment_amount;
  let new_value = state.value + increment_amount;
  return [
    new CounterState(new_value, state.pending, state.next_pending_message_id),
    toList([new Incremented(increment_amount, new_value)]),
  ];
}

/**
 * Retire the oldest pending operation when the local operation returns
 * sequenced. The value and the events do not change, because the kernel
 * already applied the operation optimistically.
 */
export function ack_local(state, operation) {
  let $ = state.pending;
  if ($ instanceof $Empty) {
    return new Error(new UnexpectedAck(operation, "pending queue is empty"));
  } else {
    let rest = $.tail;
    let amount = $.head.increment_amount;
    let increment_amount = operation.increment_amount;
    if (increment_amount === amount) {
      return new Ok(
        new CounterState(state.value, rest, state.next_pending_message_id),
      );
    } else {
      let increment_amount = operation.increment_amount;
      return new Error(
        new UnexpectedAck(
          operation,
          (("expected pending increment " + $int.to_string(amount)) + ", got ") + $int.to_string(
            increment_amount,
          ),
        ),
      );
    }
  }
}

/**
 * Retire the oldest pending operation and check the local operation metadata
 * of Fluid.
 */
export function ack_local_with_message_id(state, operation, message_id) {
  let $ = state.pending;
  if ($ instanceof $Empty) {
    return new Error(new UnexpectedAck(operation, "pending queue is empty"));
  } else {
    let rest = $.tail;
    let amount = $.head.increment_amount;
    let pending_message_id = $.head.message_id;
    let increment_amount = operation.increment_amount;
    if ((increment_amount === amount) && (message_id === pending_message_id)) {
      return new Ok(
        new CounterState(state.value, rest, state.next_pending_message_id),
      );
    } else {
      let increment_amount = operation.increment_amount;
      return new Error(
        new UnexpectedAck(
          operation,
          (((((("expected pending increment " + $int.to_string(amount)) + " with message id ") + $int.to_string(
            pending_message_id,
          )) + ", got increment ") + $int.to_string(increment_amount)) + " with message id ") + $int.to_string(
            message_id,
          ),
        ),
      );
    }
  }
}

/**
 * Apply a stashed operation again after a reconnect. Fluid sends it through
 * `increment` again. The operation is thus visible optimistically, and it
 * becomes pending again.
 */
export function apply_stashed_operation(state, operation) {
  let increment_amount = operation.increment_amount;
  return increment(state, increment_amount);
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
 * Roll back the newest pending operation and remove its optimistic effect.
 * Fluid emits a usual `incremented` event with the negated amount.
 */
export function rollback(state, operation, message_id) {
  let $ = pop_last(state.pending);
  if ($ instanceof Ok) {
    let rest = $[0][1];
    let amount = $[0][0].increment_amount;
    let pending_message_id = $[0][0].message_id;
    let increment_amount = operation.increment_amount;
    if ((increment_amount === amount) && (message_id === pending_message_id)) {
      let rollback_amount = 0 - increment_amount;
      let new_value = state.value + rollback_amount;
      return new Ok(
        [
          new CounterState(new_value, rest, state.next_pending_message_id),
          toList([new Incremented(rollback_amount, new_value)]),
        ],
      );
    } else {
      let increment_amount = operation.increment_amount;
      return new Error(
        new UnexpectedRollback(
          operation,
          (((((("expected newest pending increment " + $int.to_string(amount)) + " with message id ") + $int.to_string(
            pending_message_id,
          )) + ", got increment ") + $int.to_string(increment_amount)) + " with message id ") + $int.to_string(
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
