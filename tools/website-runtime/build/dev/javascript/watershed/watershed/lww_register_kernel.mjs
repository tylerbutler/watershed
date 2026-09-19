/// <reference types="./lww_register_kernel.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $replica_id from "../../lattice_core/lattice_core/replica_id.mjs";
import * as $lww_register from "../../lattice_registers/lattice_registers/lww_register.mjs";
import {
  Ok,
  Error,
  toList,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  CustomType as $CustomType,
  isEqual,
} from "../gleam.mjs";
import * as $lww_clock from "../watershed/lww_clock.mjs";

export class LwwRegisterState extends $CustomType {
  constructor(replica_id, sequenced, optimistic, pending, next_pending_message_id, last_seen) {
    super();
    this.replica_id = replica_id;
    this.sequenced = sequenced;
    this.optimistic = optimistic;
    this.pending = pending;
    this.next_pending_message_id = next_pending_message_id;
    this.last_seen = last_seen;
  }
}
export const LwwRegisterState$LwwRegisterState = (replica_id, sequenced, optimistic, pending, next_pending_message_id, last_seen) =>
  new LwwRegisterState(replica_id,
  sequenced,
  optimistic,
  pending,
  next_pending_message_id,
  last_seen);
export const LwwRegisterState$isLwwRegisterState = (value) =>
  value instanceof LwwRegisterState;
export const LwwRegisterState$LwwRegisterState$replica_id = (value) =>
  value.replica_id;
export const LwwRegisterState$LwwRegisterState$0 = (value) => value.replica_id;
export const LwwRegisterState$LwwRegisterState$sequenced = (value) =>
  value.sequenced;
export const LwwRegisterState$LwwRegisterState$1 = (value) => value.sequenced;
export const LwwRegisterState$LwwRegisterState$optimistic = (value) =>
  value.optimistic;
export const LwwRegisterState$LwwRegisterState$2 = (value) => value.optimistic;
export const LwwRegisterState$LwwRegisterState$pending = (value) =>
  value.pending;
export const LwwRegisterState$LwwRegisterState$3 = (value) => value.pending;
export const LwwRegisterState$LwwRegisterState$next_pending_message_id = (value) =>
  value.next_pending_message_id;
export const LwwRegisterState$LwwRegisterState$4 = (value) =>
  value.next_pending_message_id;
export const LwwRegisterState$LwwRegisterState$last_seen = (value) =>
  value.last_seen;
export const LwwRegisterState$LwwRegisterState$5 = (value) => value.last_seen;

export class PendingOp extends $CustomType {
  constructor(operation, message_id) {
    super();
    this.operation = operation;
    this.message_id = message_id;
  }
}
export const PendingOp$PendingOp = (operation, message_id) =>
  new PendingOp(operation, message_id);
export const PendingOp$isPendingOp = (value) => value instanceof PendingOp;
export const PendingOp$PendingOp$operation = (value) => value.operation;
export const PendingOp$PendingOp$0 = (value) => value.operation;
export const PendingOp$PendingOp$message_id = (value) => value.message_id;
export const PendingOp$PendingOp$1 = (value) => value.message_id;

export class Set extends $CustomType {
  constructor(value, timestamp, delta) {
    super();
    this.value = value;
    this.timestamp = timestamp;
    this.delta = delta;
  }
}
export const LwwRegisterOperation$Set = (value, timestamp, delta) =>
  new Set(value, timestamp, delta);
export const LwwRegisterOperation$isSet = (value) => value instanceof Set;
export const LwwRegisterOperation$Set$value = (value) => value.value;
export const LwwRegisterOperation$Set$0 = (value) => value.value;
export const LwwRegisterOperation$Set$timestamp = (value) => value.timestamp;
export const LwwRegisterOperation$Set$1 = (value) => value.timestamp;
export const LwwRegisterOperation$Set$delta = (value) => value.delta;
export const LwwRegisterOperation$Set$2 = (value) => value.delta;

export class Changed extends $CustomType {
  constructor(previous_value, value) {
    super();
    this.previous_value = previous_value;
    this.value = value;
  }
}
export const LwwRegisterEvent$Changed = (previous_value, value) =>
  new Changed(previous_value, value);
export const LwwRegisterEvent$isChanged = (value) => value instanceof Changed;
export const LwwRegisterEvent$Changed$previous_value = (value) =>
  value.previous_value;
export const LwwRegisterEvent$Changed$0 = (value) => value.previous_value;
export const LwwRegisterEvent$Changed$value = (value) => value.value;
export const LwwRegisterEvent$Changed$1 = (value) => value.value;

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

export class Clock extends $CustomType {
  constructor(error) {
    super();
    this.error = error;
  }
}
export const KernelError$Clock = (error) => new Clock(error);
export const KernelError$isClock = (value) => value instanceof Clock;
export const KernelError$Clock$error = (value) => value.error;
export const KernelError$Clock$0 = (value) => value.error;

export class InvalidState extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}
export const KernelError$InvalidState = (detail) => new InvalidState(detail);
export const KernelError$isInvalidState = (value) =>
  value instanceof InvalidState;
export const KernelError$InvalidState$detail = (value) => value.detail;
export const KernelError$InvalidState$0 = (value) => value.detail;

export class DecodeError extends $CustomType {
  constructor(error) {
    super();
    this.error = error;
  }
}
export const KernelError$DecodeError = (error) => new DecodeError(error);
export const KernelError$isDecodeError = (value) =>
  value instanceof DecodeError;
export const KernelError$DecodeError$error = (value) => value.error;
export const KernelError$DecodeError$0 = (value) => value.error;

export function new$(replica_id) {
  let empty = $lww_register.new$("", 0, $replica_id.new$(""));
  return new LwwRegisterState(replica_id, empty, empty, $List$Empty$const, 0, 0);
}

export function value(state) {
  return $lww_register.value(state.optimistic);
}

export function sequenced_value(state) {
  return $lww_register.value(state.sequenced);
}

function timestamp(register) {
  let _pipe = $json.parse(
    $json.to_string($lww_register.to_json(register)),
    $decode.at(toList(["state", "timestamp"]), $decode.int),
  );
  let _pipe$1 = $result.map_error(
    _pipe,
    (var0) => { return new DecodeError(var0); },
  );
  return $result.try$(
    _pipe$1,
    (value) => {
      let $ = (value < 0) || (value > $lww_clock.max_safe_timestamp);
      if ($) {
        return new Error(
          new InvalidState("register timestamp is outside the safe range"),
        );
      } else {
        return new Ok(value);
      }
    },
  );
}

function observe(state, register) {
  return $result.try$(
    timestamp(register),
    (seen) => {
      return new Ok(
        new LwwRegisterState(
          state.replica_id,
          state.sequenced,
          state.optimistic,
          state.pending,
          state.next_pending_message_id,
          $int.max(state.last_seen, seen),
        ),
      );
    },
  );
}

function event_between(before, after) {
  let previous = value(before);
  let next = value(after);
  let $ = previous === next;
  if ($) {
    return $List$Empty$const;
  } else {
    return toList([new Changed(previous, next)]);
  }
}

function operation_register(operation) {
  let delta = operation.delta;
  return delta;
}

function operation_timestamp(operation) {
  let timestamp$1 = operation.timestamp;
  return timestamp$1;
}

export function apply_stashed_operation(state, operation) {
  let delta = operation_register(operation);
  return $result.try$(
    observe(state, delta),
    (state) => {
      let optimistic = $lww_register.merge(state.optimistic, delta);
      let message_id = state.next_pending_message_id;
      let next = new LwwRegisterState(
        state.replica_id,
        state.sequenced,
        optimistic,
        $list.append(
          state.pending,
          toList([new PendingOp(operation, message_id)]),
        ),
        message_id + 1,
        state.last_seen,
      );
      return new Ok([next, event_between(state, next), operation, message_id]);
    },
  );
}

export function set(state, next_value, wall_clock) {
  let $ = $lww_clock.next(state.last_seen, wall_clock);
  if ($ instanceof Ok) {
    let timestamp$1 = $[0];
    let delta = $lww_register.new$(next_value, timestamp$1, state.replica_id);
    let operation = new Set(next_value, timestamp$1, delta);
    return apply_stashed_operation(state, operation);
  } else {
    let error = $[0];
    return new Error(new Clock(error));
  }
}

function apply_delta(state, delta) {
  return $result.try$(
    observe(state, delta),
    (state) => {
      let next = new LwwRegisterState(
        state.replica_id,
        $lww_register.merge(state.sequenced, delta),
        $lww_register.merge(state.optimistic, delta),
        state.pending,
        state.next_pending_message_id,
        state.last_seen,
      );
      return new Ok([next, event_between(state, next), delta]);
    },
  );
}

export function p2p_set(state, next_value, wall_clock) {
  let $ = $lww_clock.next(state.last_seen, wall_clock);
  if ($ instanceof Ok) {
    let timestamp$1 = $[0];
    let delta = $lww_register.new$(next_value, timestamp$1, state.replica_id);
    let operation = new Set(next_value, timestamp$1, delta);
    return $result.try$(
      apply_delta(state, delta),
      (_use0) => {
        let next = _use0[0];
        let events = _use0[1];
        return new Ok([next, events, operation]);
      },
    );
  } else {
    let error = $[0];
    return new Error(new Clock(error));
  }
}

export function apply_remote(state, operation) {
  let delta = operation_register(operation);
  return $result.try$(
    observe(state, delta),
    (state) => {
      let next = new LwwRegisterState(
        state.replica_id,
        $lww_register.merge(state.sequenced, delta),
        $lww_register.merge(state.optimistic, delta),
        state.pending,
        state.next_pending_message_id,
        state.last_seen,
      );
      return new Ok([next, event_between(state, next)]);
    },
  );
}

export function p2p_merge(state, other) {
  return $result.try$(
    observe(state, other),
    (state) => {
      let next = new LwwRegisterState(
        state.replica_id,
        $lww_register.merge(state.sequenced, other),
        $lww_register.merge(state.optimistic, other),
        state.pending,
        state.next_pending_message_id,
        state.last_seen,
      );
      return new Ok([next, event_between(state, next)]);
    },
  );
}

function do_ack(state, operation, expected_message_id) {
  let $ = state.pending;
  if ($ instanceof $Empty) {
    return new Error(new UnexpectedAck(operation, "pending queue is empty"));
  } else {
    let rest = $.tail;
    let expected = $.head.operation;
    let pending_message_id = $.head.message_id;
    let _block;
    if (expected_message_id instanceof Some) {
      let actual = expected_message_id[0];
      _block = actual === pending_message_id;
    } else {
      _block = true;
    }
    let id_matches = _block;
    let $1 = (isEqual(operation, expected)) && id_matches;
    if ($1) {
      let delta = operation_register(operation);
      return $result.try$(
        observe(state, delta),
        (state) => {
          return new Ok(
            new LwwRegisterState(
              state.replica_id,
              $lww_register.merge(state.sequenced, delta),
              state.optimistic,
              rest,
              state.next_pending_message_id,
              state.last_seen,
            ),
          );
        },
      );
    } else {
      return new Error(
        new UnexpectedAck(operation, "ack does not match oldest pending write"),
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

function replay(sequenced, pending) {
  return $list.fold(
    pending,
    sequenced,
    (acc, pending) => {
      return $lww_register.merge(acc, operation_register(pending.operation));
    },
  );
}

export function rollback(state, operation, message_id) {
  let $ = $list.reverse(state.pending);
  if ($ instanceof $Empty) {
    return new Error(
      new UnexpectedRollback(operation, "pending queue is empty"),
    );
  } else {
    let rest = $.tail;
    let expected = $.head.operation;
    let expected_id = $.head.message_id;
    let $1 = (isEqual(operation, expected)) && (message_id === expected_id);
    if ($1) {
      let pending = $list.reverse(rest);
      let optimistic = replay(state.sequenced, pending);
      let next = new LwwRegisterState(
        state.replica_id,
        state.sequenced,
        optimistic,
        pending,
        state.next_pending_message_id,
        state.last_seen,
      );
      return new Ok([next, event_between(state, next)]);
    } else {
      return new Error(
        new UnexpectedRollback(
          operation,
          "rollback does not match newest pending write",
        ),
      );
    }
  }
}

export function summary(state) {
  return $lww_register.to_json(state.sequenced);
}

export function from_sequenced(register, replica_id) {
  let $ = timestamp(register);
  if ($ instanceof Ok) {
    let last_seen = $[0];
    return new Ok(
      new LwwRegisterState(
        replica_id,
        register,
        register,
        $List$Empty$const,
        0,
        last_seen,
      ),
    );
  } else {
    return $;
  }
}

export function from_summary(source, replica_id) {
  let $ = $lww_register.from_json(source);
  if ($ instanceof Ok) {
    let register = $[0];
    return from_sequenced(register, replica_id);
  } else {
    let error = $[0];
    return new Error(new DecodeError(error));
  }
}

export function check_cache_coherence(state) {
  let expected = replay(state.sequenced, state.pending);
  let $ = isEqual(expected, state.optimistic);
  if ($) {
    return new Ok(undefined);
  } else {
    return new Error(
      "optimistic LWWRegister cache does not match sequenced plus pending",
    );
  }
}

export function pending_timestamp(operation) {
  return operation_timestamp(operation);
}
