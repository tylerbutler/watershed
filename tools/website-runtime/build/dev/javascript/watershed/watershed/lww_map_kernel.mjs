/// <reference types="./lww_map_kernel.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import * as $replica_id from "../../lattice_core/lattice_core/replica_id.mjs";
import * as $crdt from "../../lattice_maps/lattice_maps/crdt.mjs";
import * as $lww_map from "../../lattice_maps/lattice_maps/lww_map.mjs";
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
import * as $canonical_json from "../watershed/canonical_json.mjs";
import * as $json_ot from "../watershed/json_ot.mjs";
import * as $lww_clock from "../watershed/lww_clock.mjs";

export class LwwMapState extends $CustomType {
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
export const LwwMapState$LwwMapState = (replica_id, sequenced, optimistic, pending, next_pending_message_id, last_seen) =>
  new LwwMapState(replica_id,
  sequenced,
  optimistic,
  pending,
  next_pending_message_id,
  last_seen);
export const LwwMapState$isLwwMapState = (value) =>
  value instanceof LwwMapState;
export const LwwMapState$LwwMapState$replica_id = (value) => value.replica_id;
export const LwwMapState$LwwMapState$0 = (value) => value.replica_id;
export const LwwMapState$LwwMapState$sequenced = (value) => value.sequenced;
export const LwwMapState$LwwMapState$1 = (value) => value.sequenced;
export const LwwMapState$LwwMapState$optimistic = (value) => value.optimistic;
export const LwwMapState$LwwMapState$2 = (value) => value.optimistic;
export const LwwMapState$LwwMapState$pending = (value) => value.pending;
export const LwwMapState$LwwMapState$3 = (value) => value.pending;
export const LwwMapState$LwwMapState$next_pending_message_id = (value) =>
  value.next_pending_message_id;
export const LwwMapState$LwwMapState$4 = (value) =>
  value.next_pending_message_id;
export const LwwMapState$LwwMapState$last_seen = (value) => value.last_seen;
export const LwwMapState$LwwMapState$5 = (value) => value.last_seen;

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
  constructor(key, value, timestamp, delta) {
    super();
    this.key = key;
    this.value = value;
    this.timestamp = timestamp;
    this.delta = delta;
  }
}
export const LwwMapOperation$Set = (key, value, timestamp, delta) =>
  new Set(key, value, timestamp, delta);
export const LwwMapOperation$isSet = (value) => value instanceof Set;
export const LwwMapOperation$Set$key = (value) => value.key;
export const LwwMapOperation$Set$0 = (value) => value.key;
export const LwwMapOperation$Set$value = (value) => value.value;
export const LwwMapOperation$Set$1 = (value) => value.value;
export const LwwMapOperation$Set$timestamp = (value) => value.timestamp;
export const LwwMapOperation$Set$2 = (value) => value.timestamp;
export const LwwMapOperation$Set$delta = (value) => value.delta;
export const LwwMapOperation$Set$3 = (value) => value.delta;

export class Remove extends $CustomType {
  constructor(key, timestamp, delta) {
    super();
    this.key = key;
    this.timestamp = timestamp;
    this.delta = delta;
  }
}
export const LwwMapOperation$Remove = (key, timestamp, delta) =>
  new Remove(key, timestamp, delta);
export const LwwMapOperation$isRemove = (value) => value instanceof Remove;
export const LwwMapOperation$Remove$key = (value) => value.key;
export const LwwMapOperation$Remove$0 = (value) => value.key;
export const LwwMapOperation$Remove$timestamp = (value) => value.timestamp;
export const LwwMapOperation$Remove$1 = (value) => value.timestamp;
export const LwwMapOperation$Remove$delta = (value) => value.delta;
export const LwwMapOperation$Remove$2 = (value) => value.delta;

export const LwwMapOperation$key = (value) => value.key;

export class ValueChanged extends $CustomType {
  constructor(key, previous_value, value) {
    super();
    this.key = key;
    this.previous_value = previous_value;
    this.value = value;
  }
}
export const LwwMapEvent$ValueChanged = (key, previous_value, value) =>
  new ValueChanged(key, previous_value, value);
export const LwwMapEvent$isValueChanged = (value) =>
  value instanceof ValueChanged;
export const LwwMapEvent$ValueChanged$key = (value) => value.key;
export const LwwMapEvent$ValueChanged$0 = (value) => value.key;
export const LwwMapEvent$ValueChanged$previous_value = (value) =>
  value.previous_value;
export const LwwMapEvent$ValueChanged$1 = (value) => value.previous_value;
export const LwwMapEvent$ValueChanged$value = (value) => value.value;
export const LwwMapEvent$ValueChanged$2 = (value) => value.value;

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

export class UnsupportedPruning extends $CustomType {
  constructor(timestamp) {
    super();
    this.timestamp = timestamp;
  }
}
export const KernelError$UnsupportedPruning = (timestamp) =>
  new UnsupportedPruning(timestamp);
export const KernelError$isUnsupportedPruning = (value) =>
  value instanceof UnsupportedPruning;
export const KernelError$UnsupportedPruning$timestamp = (value) =>
  value.timestamp;
export const KernelError$UnsupportedPruning$0 = (value) => value.timestamp;

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

function new_map(replica) {
  return $lww_map.new$(replica, new $crdt.LwwRegisterSpec(""));
}

export function new$(replica_id) {
  let map = new_map(replica_id);
  return new LwwMapState(
    replica_id,
    map,
    map,
    $List$Empty$const,
    0,
    $dict.new$(),
  );
}

function string_value(value) {
  if (value instanceof $crdt.CrdtLwwRegister) {
    let register = value[0];
    return new Ok($lww_register.value(register));
  } else {
    return new Error(undefined);
  }
}

function merge_error(error) {
  return new InvalidState(
    "Invalid LWW map operation: " + $string.inspect(error),
  );
}

export function get(state, key) {
  let _pipe = $lww_map.get(state.optimistic, key);
  return $result.try$(_pipe, string_value);
}

function map_entries(map) {
  let _pipe = $lww_map.keys(map);
  let _pipe$1 = $list.sort(_pipe, $canonical_json.compare);
  return $list.filter_map(
    _pipe$1,
    (key) => {
      let _pipe$2 = $lww_map.get(map, key);
      let _pipe$3 = $result.try$(_pipe$2, string_value);
      return $result.map(_pipe$3, (value) => { return [key, value]; });
    },
  );
}

export function entries(state) {
  return map_entries(state.optimistic);
}

export function sequenced_entries(state) {
  return map_entries(state.sequenced);
}

export function keys(state) {
  let _pipe = $lww_map.keys(state.optimistic);
  return $list.sort(_pipe, $canonical_json.compare);
}

function metadata_decoder() {
  return $decode.field(
    "type",
    $decode.string,
    (tag) => {
      return $decode.field(
        "v",
        $decode.int,
        (version) => {
          return $decode.then$(
            $decode.at(
              toList(["state", "entries"]),
              $decode.list(
                $decode.field(
                  "key",
                  $decode.string,
                  (key) => {
                    return $decode.field(
                      "value",
                      $decode.optional($decode.string),
                      (value) => {
                        return $decode.field(
                          "timestamp",
                          $decode.int,
                          (timestamp) => {
                            return $decode.success([key, value, timestamp]);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            (entries) => {
              return $decode.field(
                "state",
                (() => {
                  if (version === 1) {
                    return $decode.optional_field(
                      "pruned_timestamp",
                      0,
                      $decode.int,
                      (watermark) => { return $decode.success(watermark); },
                    );
                  } else {
                    return $decode.field(
                      "pruned_timestamp",
                      $decode.int,
                      (watermark) => { return $decode.success(watermark); },
                    );
                  }
                })(),
                (watermark) => {
                  let _block;
                  let _pipe = entries;
                  let _pipe$1 = $list.map(
                    _pipe,
                    (entry) => { return entry[0]; },
                  );
                  let _pipe$2 = $list.unique(_pipe$1);
                  _block = $list.length(_pipe$2);
                  let distinct = _block;
                  let $ = ((((tag === "lww_map") && (((version === 1) || (version === 2)) || (version === 3))) && (watermark === 0)) && (distinct === $list.length(
                    entries,
                  ))) && $list.all(
                    entries,
                    (entry) => {
                      return (entry[2] > 0) && (entry[2] <= $lww_clock.max_safe_timestamp);
                    },
                  );
                  if ($) {
                    if (version === 3) {
                      let decoded = $list.try_map(
                        entries,
                        (entry) => {
                          let $1 = entry[1];
                          if ($1 instanceof Some) {
                            let encoded = $1[0];
                            return $result.try$(
                              (() => {
                                let _pipe$3 = $crdt.from_json(encoded);
                                return $result.replace_error(_pipe$3, undefined);
                              })(),
                              (child) => {
                                return $result.try$(
                                  string_value(child),
                                  (value) => {
                                    return new Ok(
                                      [entry[0], new Some(value), entry[2]],
                                    );
                                  },
                                );
                              },
                            );
                          } else {
                            return new Ok(entry);
                          }
                        },
                      );
                      if (decoded instanceof Ok) {
                        let entries$1 = decoded[0];
                        return $decode.success(entries$1);
                      } else {
                        return $decode.failure(
                          $List$Empty$const,
                          "String LWW register children",
                        );
                      }
                    } else {
                      return $decode.success(entries);
                    }
                  } else {
                    return $decode.failure(
                      $List$Empty$const,
                      "unpruned LWW map with distinct keys and positive safe timestamps",
                    );
                  }
                },
              );
            },
          );
        },
      );
    },
  );
}

/**
 * Validate raw entries before Lattice converts them to a dictionary.
 * Only v3 snapshots with writer provenance are accepted.
 */
export function decoder() {
  return $decode.then$(
    metadata_decoder(),
    (_) => {
      return $decode.field(
        "v",
        $decode.int,
        (version) => {
          if (version === 3) {
            return $decode.then$(
              $json_ot.decoder(),
              (payload) => {
                let _block;
                let _pipe = $json_ot.to_json(payload);
                _block = $json.to_string(_pipe);
                let encoded = _block;
                let $ = $lww_map.from_json(encoded);
                if ($ instanceof Ok) {
                  let map = $[0];
                  let $1 = isEqual(
                    $lww_map.spec(map),
                    new $crdt.LwwRegisterSpec("")
                  );
                  if ($1) {
                    return $decode.success(map);
                  } else {
                    return $decode.failure(
                      map,
                      "String LWW map with empty default",
                    );
                  }
                } else {
                  return $decode.failure(
                    new_map($replica_id.new$("")),
                    "LWW map",
                  );
                }
              },
            );
          } else {
            return $decode.failure(new_map($replica_id.new$("")), "LWW map v3");
          }
        },
      );
    },
  );
}

function metadata(map) {
  return $result.try$(
    (() => {
      let $ = isEqual($lww_map.spec(map), new $crdt.LwwRegisterSpec(""));
      if ($) {
        return new Ok(undefined);
      } else {
        return new Error(
          new InvalidState("Expected String LWW map with empty default."),
        );
      }
    })(),
    (_) => {
      let $ = $lww_map.pruned_timestamp(map);
      if ($ === 0) {
        let _pipe = $json.parse(
          (() => {
            let _pipe = $lww_map.to_json(map);
            return $json.to_string(_pipe);
          })(),
          metadata_decoder(),
        );
        return $result.map_error(
          _pipe,
          (var0) => { return new DecodeError(var0); },
        );
      } else {
        let timestamp = $;
        return new Error(new UnsupportedPruning(timestamp));
      }
    },
  );
}

function observe(state, map) {
  return $result.try$(
    metadata(map),
    (entries) => {
      let clock = $list.fold(
        entries,
        state.last_seen,
        (clock, entry) => {
          let _block;
          let _pipe = $dict.get(clock, entry[0]);
          _block = $result.unwrap(_pipe, 0);
          let previous = _block;
          return $dict.insert(clock, entry[0], $int.max(previous, entry[2]));
        },
      );
      return new Ok(
        new LwwMapState(
          state.replica_id,
          state.sequenced,
          state.optimistic,
          state.pending,
          state.next_pending_message_id,
          clock,
        ),
      );
    },
  );
}

function events_between(before, after) {
  let _pipe = $list.append(keys(before), keys(after));
  let _pipe$1 = $list.unique(_pipe);
  let _pipe$2 = $list.sort(_pipe$1, $canonical_json.compare);
  return $list.filter_map(
    _pipe$2,
    (key) => {
      let _block;
      let _pipe$3 = get(before, key);
      _block = $option.from_result(_pipe$3);
      let previous = _block;
      let _block$1;
      let _pipe$4 = get(after, key);
      _block$1 = $option.from_result(_pipe$4);
      let value = _block$1;
      let $ = isEqual(previous, value);
      if ($) {
        return new Error(undefined);
      } else {
        return new Ok(new ValueChanged(key, previous, value));
      }
    },
  );
}

function operation_delta(operation) {
  if (operation instanceof Set) {
    let delta = operation.delta;
    return delta;
  } else {
    let delta = operation.delta;
    return delta;
  }
}

/**
 * Check the fragment and its intent together, including tombstone metadata.
 */
export function validate_operation(operation) {
  return $result.try$(
    metadata(operation_delta(operation)),
    (entries) => {
      let _block;
      if (operation instanceof Set) {
        let key = operation.key;
        let value = operation.value;
        let timestamp = operation.timestamp;
        _block = [key, new Some(value), timestamp];
      } else {
        let key = operation.key;
        let timestamp = operation.timestamp;
        _block = [key, Option$None$const, timestamp];
      }
      let expected = _block;
      let $ = isEqual(entries, toList([expected]));
      if ($) {
        return new Ok(undefined);
      } else {
        return new Error(
          new InvalidState("LWW map fragment does not match its operation"),
        );
      }
    },
  );
}

function next_timestamp(state, key, wall_clock) {
  let _pipe = $lww_clock.next(
    (() => {
      let _pipe = $dict.get(state.last_seen, key);
      return $result.unwrap(_pipe, 0);
    })(),
    wall_clock,
  );
  return $result.map_error(_pipe, (var0) => { return new Clock(var0); });
}

export function apply_stashed_operation(state, operation) {
  return $result.try$(
    validate_operation(operation),
    (_use0) => {
      
      let delta = operation_delta(operation);
      return $result.try$(
        observe(state, delta),
        (state) => {
          return $result.try$(
            (() => {
              let _pipe = $lww_map.merge(state.optimistic, delta);
              return $result.map_error(_pipe, merge_error);
            })(),
            (optimistic) => {
              let message_id = state.next_pending_message_id;
              let next = new LwwMapState(
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
              return new Ok(
                [next, events_between(state, next), operation, message_id],
              );
            },
          );
        },
      );
    },
  );
}

function set_delta(replica, key, value, timestamp) {
  let _pipe = $lww_map.set(
    new_map(replica),
    key,
    new $crdt.CrdtLwwRegister($lww_register.new$(value, timestamp, replica)),
    timestamp,
  );
  return $result.map_error(_pipe, merge_error);
}

export function set(state, key, value, wall_clock) {
  return $result.try$(
    next_timestamp(state, key, wall_clock),
    (timestamp) => {
      return $result.try$(
        set_delta(state.replica_id, key, value, timestamp),
        (delta) => {
          return apply_stashed_operation(
            state,
            new Set(key, value, timestamp, delta),
          );
        },
      );
    },
  );
}

export function remove(state, key, wall_clock) {
  return $result.try$(
    next_timestamp(state, key, wall_clock),
    (timestamp) => {
      return $result.try$(
        (() => {
          let _pipe = $lww_map.remove(new_map(state.replica_id), key, timestamp);
          return $result.map_error(_pipe, merge_error);
        })(),
        (delta) => {
          return apply_stashed_operation(
            state,
            new Remove(key, timestamp, delta),
          );
        },
      );
    },
  );
}

export function p2p_merge(state, other) {
  return $result.try$(
    observe(state, other),
    (state) => {
      return $result.try$(
        (() => {
          let _pipe = $lww_map.merge(state.sequenced, other);
          return $result.map_error(_pipe, merge_error);
        })(),
        (sequenced) => {
          return $result.try$(
            (() => {
              let _pipe = $lww_map.merge(state.optimistic, other);
              return $result.map_error(_pipe, merge_error);
            })(),
            (optimistic) => {
              let next = new LwwMapState(
                state.replica_id,
                sequenced,
                optimistic,
                state.pending,
                state.next_pending_message_id,
                state.last_seen,
              );
              return new Ok([next, events_between(state, next)]);
            },
          );
        },
      );
    },
  );
}

export function p2p_set(state, key, value, wall_clock) {
  return $result.try$(
    next_timestamp(state, key, wall_clock),
    (timestamp) => {
      return $result.try$(
        set_delta(state.replica_id, key, value, timestamp),
        (delta) => {
          return $result.try$(
            p2p_merge(state, delta),
            (_use0) => {
              let state$1 = _use0[0];
              let events = _use0[1];
              return new Ok(
                [state$1, events, new Set(key, value, timestamp, delta)],
              );
            },
          );
        },
      );
    },
  );
}

export function p2p_remove(state, key, wall_clock) {
  return $result.try$(
    next_timestamp(state, key, wall_clock),
    (timestamp) => {
      return $result.try$(
        (() => {
          let _pipe = $lww_map.remove(new_map(state.replica_id), key, timestamp);
          return $result.map_error(_pipe, merge_error);
        })(),
        (delta) => {
          return $result.try$(
            p2p_merge(state, delta),
            (_use0) => {
              let state$1 = _use0[0];
              let events = _use0[1];
              return new Ok(
                [state$1, events, new Remove(key, timestamp, delta)],
              );
            },
          );
        },
      );
    },
  );
}

export function apply_remote(state, operation) {
  return $result.try$(
    validate_operation(operation),
    (_use0) => {
      
      return p2p_merge(state, operation_delta(operation));
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
    let message_id = $.head.message_id;
    let _block;
    if (expected_message_id instanceof Some) {
      let actual = expected_message_id[0];
      _block = actual === message_id;
    } else {
      _block = true;
    }
    let id_matches = _block;
    let $1 = (isEqual(operation, expected)) && id_matches;
    if ($1) {
      return $result.try$(
        validate_operation(operation),
        (_use0) => {
          
          let delta = operation_delta(operation);
          return $result.try$(
            observe(state, delta),
            (state) => {
              return $result.try$(
                (() => {
                  let _pipe = $lww_map.merge(state.sequenced, delta);
                  return $result.map_error(_pipe, merge_error);
                })(),
                (sequenced) => {
                  return new Ok(
                    new LwwMapState(
                      state.replica_id,
                      sequenced,
                      state.optimistic,
                      rest,
                      state.next_pending_message_id,
                      state.last_seen,
                    ),
                  );
                },
              );
            },
          );
        },
      );
    } else {
      return new Error(
        new UnexpectedAck(
          operation,
          "ack does not match oldest pending operation",
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

function replay(sequenced, pending) {
  return $list.try_fold(
    pending,
    sequenced,
    (map, pending) => {
      let _pipe = $lww_map.merge(map, operation_delta(pending.operation));
      return $result.map_error(_pipe, merge_error);
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
      return $result.try$(
        replay(state.sequenced, pending),
        (optimistic) => {
          let next = new LwwMapState(
            state.replica_id,
            state.sequenced,
            optimistic,
            pending,
            state.next_pending_message_id,
            state.last_seen,
          );
          return new Ok([next, events_between(state, next)]);
        },
      );
    } else {
      return new Error(
        new UnexpectedRollback(
          operation,
          "rollback does not match newest pending operation",
        ),
      );
    }
  }
}

export function promote_attach(state) {
  return new LwwMapState(
    state.replica_id,
    state.optimistic,
    state.optimistic,
    $List$Empty$const,
    state.next_pending_message_id,
    state.last_seen,
  );
}

export function summary(state) {
  return $lww_map.to_json(state.sequenced);
}

export function from_sequenced(map, replica_id) {
  let map$1 = $lww_map.bind(map, replica_id);
  return observe(
    (() => {
      let _record = new$(replica_id);
      return new LwwMapState(
        _record.replica_id,
        map$1,
        map$1,
        _record.pending,
        _record.next_pending_message_id,
        _record.last_seen,
      );
    })(),
    map$1,
  );
}

export function from_summary(source, replica_id) {
  return $result.try$(
    (() => {
      let _pipe = $json.parse(source, decoder());
      return $result.map_error(
        _pipe,
        (var0) => { return new DecodeError(var0); },
      );
    })(),
    (map) => { return from_sequenced(map, replica_id); },
  );
}

export function check_cache_coherence(state) {
  return $result.try$(
    (() => {
      let _pipe = replay(state.sequenced, state.pending);
      return $result.map_error(_pipe, $string.inspect);
    })(),
    (optimistic) => {
      let $ = isEqual(optimistic, state.optimistic);
      if ($) {
        return new Ok(undefined);
      } else {
        return new Error(
          "optimistic LWWMap cache does not match sequenced plus pending",
        );
      }
    },
  );
}
