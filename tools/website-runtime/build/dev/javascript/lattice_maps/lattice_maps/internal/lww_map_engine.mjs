/// <reference types="./lww_map_engine.d.mts" />
import * as $bit_array from "../../../gleam_stdlib/gleam/bit_array.mjs";
import * as $dict from "../../../gleam_stdlib/gleam/dict.mjs";
import * as $int from "../../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../../gleam_stdlib/gleam/option.mjs";
import * as $order from "../../../gleam_stdlib/gleam/order.mjs";
import { Eq, Gt, Lt } from "../../../gleam_stdlib/gleam/order.mjs";
import * as $result from "../../../gleam_stdlib/gleam/result.mjs";
import * as $replica_id from "../../../lattice_core/lattice_core/replica_id.mjs";
import { Ok, Error, CustomType as $CustomType, isEqual, toBitArray, stringBits } from "../../gleam.mjs";

export class Modern extends $CustomType {
  constructor(writer) {
    super();
    this.writer = writer;
  }
}
export const Provenance$Modern = (writer) => new Modern(writer);
export const Provenance$isModern = (value) => value instanceof Modern;
export const Provenance$Modern$writer = (value) => value.writer;
export const Provenance$Modern$0 = (value) => value.writer;

export class Legacy extends $CustomType {
  constructor(tie_key) {
    super();
    this.tie_key = tie_key;
  }
}
export const Provenance$Legacy = (tie_key) => new Legacy(tie_key);
export const Provenance$isLegacy = (value) => value instanceof Legacy;
export const Provenance$Legacy$tie_key = (value) => value.tie_key;
export const Provenance$Legacy$0 = (value) => value.tie_key;

export class Entry extends $CustomType {
  constructor(value, timestamp, provenance) {
    super();
    this.value = value;
    this.timestamp = timestamp;
    this.provenance = provenance;
  }
}
export const Entry$Entry = (value, timestamp, provenance) =>
  new Entry(value, timestamp, provenance);
export const Entry$isEntry = (value) => value instanceof Entry;
export const Entry$Entry$value = (value) => value.value;
export const Entry$Entry$0 = (value) => value.value;
export const Entry$Entry$timestamp = (value) => value.timestamp;
export const Entry$Entry$1 = (value) => value.timestamp;
export const Entry$Entry$provenance = (value) => value.provenance;
export const Entry$Entry$2 = (value) => value.provenance;

export class State extends $CustomType {
  constructor(entries, pruned_timestamp) {
    super();
    this.entries = entries;
    this.pruned_timestamp = pruned_timestamp;
  }
}
export const State$State = (entries, pruned_timestamp) =>
  new State(entries, pruned_timestamp);
export const State$isState = (value) => value instanceof State;
export const State$State$entries = (value) => value.entries;
export const State$State$0 = (value) => value.entries;
export const State$State$pruned_timestamp = (value) => value.pruned_timestamp;
export const State$State$1 = (value) => value.pruned_timestamp;

export class TimestampNotAdvanced extends $CustomType {
  constructor(key, timestamp, floor) {
    super();
    this.key = key;
    this.timestamp = timestamp;
    this.floor = floor;
  }
}
export const Error$TimestampNotAdvanced = (key, timestamp, floor) =>
  new TimestampNotAdvanced(key, timestamp, floor);
export const Error$isTimestampNotAdvanced = (value) =>
  value instanceof TimestampNotAdvanced;
export const Error$TimestampNotAdvanced$key = (value) => value.key;
export const Error$TimestampNotAdvanced$0 = (value) => value.key;
export const Error$TimestampNotAdvanced$timestamp = (value) => value.timestamp;
export const Error$TimestampNotAdvanced$1 = (value) => value.timestamp;
export const Error$TimestampNotAdvanced$floor = (value) => value.floor;
export const Error$TimestampNotAdvanced$2 = (value) => value.floor;

export class ConflictingWrite extends $CustomType {
  constructor(key, timestamp) {
    super();
    this.key = key;
    this.timestamp = timestamp;
  }
}
export const Error$ConflictingWrite = (key, timestamp) =>
  new ConflictingWrite(key, timestamp);
export const Error$isConflictingWrite = (value) =>
  value instanceof ConflictingWrite;
export const Error$ConflictingWrite$key = (value) => value.key;
export const Error$ConflictingWrite$0 = (value) => value.key;
export const Error$ConflictingWrite$timestamp = (value) => value.timestamp;
export const Error$ConflictingWrite$1 = (value) => value.timestamp;

export class InvalidTimestamp extends $CustomType {
  constructor(key, timestamp) {
    super();
    this.key = key;
    this.timestamp = timestamp;
  }
}
export const Error$InvalidTimestamp = (key, timestamp) =>
  new InvalidTimestamp(key, timestamp);
export const Error$isInvalidTimestamp = (value) =>
  value instanceof InvalidTimestamp;
export const Error$InvalidTimestamp$key = (value) => value.key;
export const Error$InvalidTimestamp$0 = (value) => value.key;
export const Error$InvalidTimestamp$timestamp = (value) => value.timestamp;
export const Error$InvalidTimestamp$1 = (value) => value.timestamp;

export const Error$key = (value) => value.key;
export const Error$timestamp = (value) => value.timestamp;

export function new$() {
  return new State($dict.new$(), 0);
}

export function check_timestamp(state, key, timestamp) {
  let _block;
  let $ = $dict.get(state.entries, key);
  if ($ instanceof Ok) {
    let entry = $[0];
    _block = entry.timestamp;
  } else {
    _block = state.pruned_timestamp;
  }
  let existing_timestamp = _block;
  let floor = $int.max(existing_timestamp, state.pruned_timestamp);
  let $1 = (timestamp > 9_007_199_254_740_991) || (timestamp < -9_007_199_254_740_991);
  if ($1) {
    return new Error(new InvalidTimestamp(key, timestamp));
  } else {
    let $2 = (timestamp <= state.pruned_timestamp) || (timestamp < existing_timestamp);
    if ($2) {
      return new Error(new TimestampNotAdvanced(key, timestamp, floor));
    } else {
      return new Ok(undefined);
    }
  }
}

function choose_provenance(a, b) {
  let $ = a.provenance;
  let $1 = b.provenance;
  if ($ instanceof Modern) {
    if ($1 instanceof Modern) {
      let aw = $.writer;
      let bw = $1.writer;
      let $2 = $replica_id.compare(aw, bw);
      if ($2 instanceof Lt) {
        return b;
      } else {
        return a;
      }
    } else {
      return a;
    }
  } else if ($1 instanceof Modern) {
    return b;
  } else {
    let ak = $.tie_key;
    let bk = $1.tie_key;
    let $2 = $bit_array.compare(
      toBitArray([stringBits(ak)]),
      toBitArray([stringBits(bk)]),
    );
    if ($2 instanceof Lt) {
      return b;
    } else {
      return a;
    }
  }
}

function choose_equal_timestamp(key, a, b, equal) {
  let $ = a.value;
  let $1 = b.value;
  if ($ instanceof Some) {
    if ($1 instanceof Some) {
      let av = $[0];
      let bv = $1[0];
      let $2 = a.provenance;
      let $3 = b.provenance;
      if ($2 instanceof Modern && $3 instanceof Modern) {
        let aw = $2.writer;
        let bw = $3.writer;
        if (isEqual(aw, bw)) {
          let $4 = equal(av, bv);
          if ($4) {
            return new Ok(a);
          } else {
            return new Error(new ConflictingWrite(key, a.timestamp));
          }
        } else {
          return new Ok(choose_provenance(a, b));
        }
      } else {
        return new Ok(choose_provenance(a, b));
      }
    } else {
      return new Ok(b);
    }
  } else if ($1 instanceof Some) {
    return new Ok(a);
  } else {
    return new Ok(choose_provenance(a, b));
  }
}

function choose(key, a, b, equal) {
  let $ = $int.compare(a.timestamp, b.timestamp);
  if ($ instanceof Lt) {
    return new Ok(b);
  } else if ($ instanceof Eq) {
    return choose_equal_timestamp(key, a, b, equal);
  } else {
    return new Ok(a);
  }
}

export function put(state, key, entry, equal) {
  return $result.try$(
    check_timestamp(state, key, entry.timestamp),
    (_) => {
      return $result.try$(
        (() => {
          let $ = $dict.get(state.entries, key);
          if ($ instanceof Ok) {
            let current = $[0];
            return choose(key, current, entry, equal);
          } else {
            return new Ok(entry);
          }
        })(),
        (winner) => {
          return new Ok(
            new State(
              $dict.insert(state.entries, key, winner),
              state.pruned_timestamp,
            ),
          );
        },
      );
    },
  );
}

export function prune(state, stable) {
  let floor = $int.max(state.pruned_timestamp, stable);
  return new State(
    $dict.filter(
      state.entries,
      (_, entry) => {
        let $ = entry.value;
        if ($ instanceof Some) {
          return true;
        } else {
          return entry.timestamp > floor;
        }
      },
    ),
    floor,
  );
}

export function merge(a, b, equal) {
  let _block;
  let _pipe = $dict.keys(a.entries);
  let _pipe$1 = $list.append(_pipe, $dict.keys(b.entries));
  _block = $list.unique(_pipe$1);
  let keys = _block;
  return $result.try$(
    $list.try_fold(
      keys,
      $dict.new$(),
      (entries, key) => {
        let _block$1;
        let $ = $dict.get(a.entries, key);
        let $1 = $dict.get(b.entries, key);
        if ($ instanceof Ok) {
          if ($1 instanceof Ok) {
            let a$1 = $[0];
            let b$1 = $1[0];
            let _pipe$2 = choose(key, a$1, b$1, equal);
            _block$1 = $result.map(
              _pipe$2,
              (var0) => { return new Some(var0); },
            );
          } else {
            let entry = $[0];
            _block$1 = new Ok(
              (() => {
                let $2 = entry.timestamp > b.pruned_timestamp;
                if ($2) {
                  return new Some(entry);
                } else {
                  return Option$None$const;
                }
              })(),
            );
          }
        } else if ($1 instanceof Ok) {
          let entry = $1[0];
          _block$1 = new Ok(
            (() => {
              let $2 = entry.timestamp > a.pruned_timestamp;
              if ($2) {
                return new Some(entry);
              } else {
                return Option$None$const;
              }
            })(),
          );
        } else {
          _block$1 = new Ok(Option$None$const);
        }
        let winner = _block$1;
        return $result.try$(
          winner,
          (winner) => {
            return new Ok(
              (() => {
                if (winner instanceof Some) {
                  let entry = winner[0];
                  return $dict.insert(entries, key, entry);
                } else {
                  return entries;
                }
              })(),
            );
          },
        );
      },
    ),
    (entries) => {
      return new Ok(
        prune(
          new State(entries, $int.max(a.pruned_timestamp, b.pruned_timestamp)),
          0,
        ),
      );
    },
  );
}
