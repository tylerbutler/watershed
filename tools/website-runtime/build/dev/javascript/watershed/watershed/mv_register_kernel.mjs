/// <reference types="./mv_register_kernel.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import * as $replica_id from "../../lattice_core/lattice_core/replica_id.mjs";
import * as $mv_register from "../../lattice_registers/lattice_registers/mv_register.mjs";
import {
  Ok,
  Error,
  toList,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  CustomType as $CustomType,
  isEqual,
} from "../gleam.mjs";

export class MvRegisterState extends $CustomType {
  constructor(replica_id, sequenced, optimistic, pending, next_pending_message_id, authored) {
    super();
    this.replica_id = replica_id;
    this.sequenced = sequenced;
    this.optimistic = optimistic;
    this.pending = pending;
    this.next_pending_message_id = next_pending_message_id;
    this.authored = authored;
  }
}
export const MvRegisterState$MvRegisterState = (replica_id, sequenced, optimistic, pending, next_pending_message_id, authored) =>
  new MvRegisterState(replica_id,
  sequenced,
  optimistic,
  pending,
  next_pending_message_id,
  authored);
export const MvRegisterState$isMvRegisterState = (value) =>
  value instanceof MvRegisterState;
export const MvRegisterState$MvRegisterState$replica_id = (value) =>
  value.replica_id;
export const MvRegisterState$MvRegisterState$0 = (value) => value.replica_id;
export const MvRegisterState$MvRegisterState$sequenced = (value) =>
  value.sequenced;
export const MvRegisterState$MvRegisterState$1 = (value) => value.sequenced;
export const MvRegisterState$MvRegisterState$optimistic = (value) =>
  value.optimistic;
export const MvRegisterState$MvRegisterState$2 = (value) => value.optimistic;
export const MvRegisterState$MvRegisterState$pending = (value) => value.pending;
export const MvRegisterState$MvRegisterState$3 = (value) => value.pending;
export const MvRegisterState$MvRegisterState$next_pending_message_id = (value) =>
  value.next_pending_message_id;
export const MvRegisterState$MvRegisterState$4 = (value) =>
  value.next_pending_message_id;
export const MvRegisterState$MvRegisterState$authored = (value) =>
  value.authored;
export const MvRegisterState$MvRegisterState$5 = (value) => value.authored;

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
  constructor(value, delta) {
    super();
    this.value = value;
    this.delta = delta;
  }
}
export const MvRegisterOperation$Set = (value, delta) => new Set(value, delta);
export const MvRegisterOperation$isSet = (value) => value instanceof Set;
export const MvRegisterOperation$Set$value = (value) => value.value;
export const MvRegisterOperation$Set$0 = (value) => value.value;
export const MvRegisterOperation$Set$delta = (value) => value.delta;
export const MvRegisterOperation$Set$1 = (value) => value.delta;

export class ValuesChanged extends $CustomType {
  constructor(values) {
    super();
    this.values = values;
  }
}
export const MvRegisterEvent$ValuesChanged = (values) =>
  new ValuesChanged(values);
export const MvRegisterEvent$isValuesChanged = (value) =>
  value instanceof ValuesChanged;
export const MvRegisterEvent$ValuesChanged$values = (value) => value.values;
export const MvRegisterEvent$ValuesChanged$0 = (value) => value.values;

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

export function from_sequenced(register, replica_id) {
  let sequenced = $mv_register.merge($mv_register.new$(replica_id), register);
  return new MvRegisterState(
    replica_id,
    sequenced,
    sequenced,
    $List$Empty$const,
    0,
    sequenced,
  );
}

export function new$(replica_id) {
  return from_sequenced($mv_register.new$(replica_id), replica_id);
}

function visible(register) {
  let _pipe = register;
  let _pipe$1 = $mv_register.value(_pipe);
  return $list.sort(_pipe$1, $string.compare);
}

export function values(state) {
  return visible(state.optimistic);
}

export function sequenced_values(state) {
  return visible(state.sequenced);
}

function events_between(before, after) {
  let $ = isEqual(values(before), values(after));
  if ($) {
    return $List$Empty$const;
  } else {
    return toList([new ValuesChanged(values(after))]);
  }
}

export function apply_stashed_operation(state, operation) {
  let delta = operation.delta;
  let message_id = state.next_pending_message_id;
  let next = new MvRegisterState(
    state.replica_id,
    state.sequenced,
    $mv_register.merge(state.optimistic, delta),
    $list.append(state.pending, toList([new PendingOp(operation, message_id)])),
    message_id + 1,
    $mv_register.merge(state.authored, delta),
  );
  return [next, events_between(state, next), operation, message_id];
}

export function set(state, value) {
  let _block;
  let _pipe = state.optimistic;
  let _pipe$1 = $mv_register.merge(_pipe, state.authored);
  _block = $mv_register.set_with_delta(_pipe$1, value);
  let $ = _block;
  let delta = $[1];
  return apply_stashed_operation(state, new Set(value, delta));
}

export function p2p_merge(state, other) {
  let next = new MvRegisterState(
    state.replica_id,
    $mv_register.merge(state.sequenced, other),
    $mv_register.merge(state.optimistic, other),
    state.pending,
    state.next_pending_message_id,
    state.authored,
  );
  return [next, events_between(state, next)];
}

export function p2p_set(state, value) {
  let _block;
  let _pipe = state.optimistic;
  let _pipe$1 = $mv_register.merge(_pipe, state.authored);
  _block = $mv_register.set_with_delta(_pipe$1, value);
  let $ = _block;
  let delta = $[1];
  let $1 = p2p_merge(state, delta);
  let next = $1[0];
  let events = $1[1];
  return [
    new MvRegisterState(
      next.replica_id,
      next.sequenced,
      next.optimistic,
      next.pending,
      next.next_pending_message_id,
      $mv_register.merge(state.authored, delta),
    ),
    events,
    new Set(value, delta),
  ];
}

export function apply_remote(state, operation) {
  let delta = operation.delta;
  return p2p_merge(state, delta);
}

function do_ack(state, operation, message_id) {
  let $ = state.pending;
  if ($ instanceof $Empty) {
    return new Error(new UnexpectedAck(operation, "pending queue is empty"));
  } else {
    let rest = $.tail;
    let expected = $.head.operation;
    let id = $.head.message_id;
    let _block;
    if (message_id instanceof Some) {
      let actual = message_id[0];
      _block = actual === id;
    } else {
      _block = true;
    }
    let matches_id = _block;
    let $1 = (isEqual(operation, expected)) && matches_id;
    if ($1) {
      let delta = operation.delta;
      return new Ok(
        new MvRegisterState(
          state.replica_id,
          $mv_register.merge(state.sequenced, delta),
          state.optimistic,
          rest,
          state.next_pending_message_id,
          state.authored,
        ),
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
      return $mv_register.merge(acc, pending.operation.delta);
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
    let id = $.head.message_id;
    let $1 = (isEqual(operation, expected)) && (message_id === id);
    if ($1) {
      let pending = $list.reverse(rest);
      let next = new MvRegisterState(
        state.replica_id,
        state.sequenced,
        replay(state.sequenced, pending),
        pending,
        state.next_pending_message_id,
        state.authored,
      );
      return new Ok([next, events_between(state, next)]);
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
  return $mv_register.to_json(state.sequenced);
}

/**
 * Validate causal metadata before the lattice decoder builds its dictionaries.
 * Duplicate tags must not disappear during dictionary construction.
 */
export function decode_crdt(source) {
  let tag_decoder = $decode.field(
    "r",
    $decode.string,
    (replica) => {
      return $decode.field(
        "c",
        $decode.int,
        (counter) => { return $decode.success([replica, counter]); },
      );
    },
  );
  let metadata_decoder = $decode.field(
    "state",
    $decode.field(
      "entries",
      $decode.list(
        $decode.field(
          "tag",
          tag_decoder,
          (tag) => { return $decode.success(tag); },
        ),
      ),
      (tags) => {
        return $decode.field(
          "vclock",
          $decode.dict($decode.string, $decode.int),
          (clock) => {
            let valid = ($list.all(
              $dict.values(clock),
              (counter) => { return counter >= 0; },
            ) && ($list.length($list.unique(tags)) === $list.length(tags))) && $list.all(
              tags,
              (tag) => {
                let replica = tag[0];
                let counter = tag[1];
                return (counter > 0) && (counter <= $result.unwrap(
                  $dict.get(clock, replica),
                  0,
                ));
              },
            );
            if (valid) {
              return $decode.success(undefined);
            } else {
              return $decode.failure(
                undefined,
                "unique tags within a nonnegative causal vector",
              );
            }
          },
        );
      },
    ),
    (metadata) => { return $decode.success(metadata); },
  );
  return $result.try$(
    $json.parse(source, metadata_decoder),
    (_) => { return $mv_register.from_json(source); },
  );
}

export function from_summary(source, replica_id) {
  let _pipe = decode_crdt(source);
  return $result.map(
    _pipe,
    (_capture) => { return from_sequenced(_capture, replica_id); },
  );
}

export function check_cache_coherence(state) {
  let $ = isEqual(replay(state.sequenced, state.pending), state.optimistic);
  if ($) {
    return new Ok(undefined);
  } else {
    return new Error(
      "optimistic cache differs from sequenced state and pending writes",
    );
  }
}
