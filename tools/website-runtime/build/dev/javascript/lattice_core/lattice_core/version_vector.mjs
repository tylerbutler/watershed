/// <reference types="./version_vector.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import {
  Ok,
  Error,
  toList,
  List$Empty$const as $List$Empty$const,
  CustomType as $CustomType,
} from "../gleam.mjs";
import * as $replica_id from "../lattice_core/replica_id.mjs";

export class Before extends $CustomType {}
export const Order$Before$const = new Before();
export const Order$Before = () => Order$Before$const;
export const Order$isBefore = (value) => value instanceof Before;

export class After extends $CustomType {}
export const Order$After$const = new After();
export const Order$After = () => Order$After$const;
export const Order$isAfter = (value) => value instanceof After;

export class Concurrent extends $CustomType {}
export const Order$Concurrent$const = new Concurrent();
export const Order$Concurrent = () => Order$Concurrent$const;
export const Order$isConcurrent = (value) => value instanceof Concurrent;

export class Equal extends $CustomType {}
export const Order$Equal$const = new Equal();
export const Order$Equal = () => Order$Equal$const;
export const Order$isEqual = (value) => value instanceof Equal;

class VersionVector extends $CustomType {
  constructor(dict) {
    super();
    this.dict = dict;
  }
}

/**
 * Create a new empty version vector.
 *
 * All replica clocks start at zero (missing entries are treated as zero).
 */
export function new$() {
  return new VersionVector($dict.new$());
}

/**
 * Increment the clock for a specific replica.
 *
 * Returns a new version vector with `replica_id`'s clock increased by one.
 * This is the standard way to record a new event at `replica_id`.
 */
export function increment(vector, replica_id) {
  let clocks = vector.dict;
  let current = $result.unwrap($dict.get(clocks, replica_id), 0);
  return new VersionVector($dict.insert(clocks, replica_id, current + 1));
}

/**
 * Get the clock value for a specific replica.
 *
 * Returns `0` if `replica_id` has not been seen (missing entries default
 * to zero, consistent with the version vector semantics).
 */
export function get(vector, replica_id) {
  let clocks = vector.dict;
  return $result.unwrap($dict.get(clocks, replica_id), 0);
}

/**
 * Compare two version vectors and return their causal ordering.
 *
 * Returns `Equal` if all clocks match, `Before` if `a` is strictly dominated
 * by `b`, `After` if `a` strictly dominates `b`, or `Concurrent` if neither
 * dominates the other.
 */
export function compare(a, b) {
  let a_clocks = a.dict;
  let b_clocks = b.dict;
  let $ = $dict.fold(
    a_clocks,
    [false, false],
    (acc, key, a_clock) => {
      let greater = acc[0];
      let less = acc[1];
      let b_clock = $result.unwrap($dict.get(b_clocks, key), 0);
      return [greater || (a_clock > b_clock), less || (a_clock < b_clock)];
    },
  );
  let greater = $[0];
  let less = $[1];
  let $1 = $dict.fold(
    b_clocks,
    [greater, less],
    (acc, key, _) => {
      let greater$1 = acc[0];
      let $2 = $dict.has_key(a_clocks, key);
      if ($2) {
        return acc;
      } else {
        return [greater$1, true];
      }
    },
  );
  let greater$1 = $1[0];
  let less$1 = $1[1];
  if (greater$1) {
    if (less$1) {
      return Order$Concurrent$const;
    } else {
      return Order$After$const;
    }
  } else if (less$1) {
    return Order$Before$const;
  } else {
    return Order$Equal$const;
  }
}

/**
 * Check whether version vector `a` dominates `b`.
 *
 * Returns `True` when every clock in `a` is greater than or equal to the
 * corresponding clock in `b`. Equivalently, `compare(a, b)` is `Equal` or
 * `After`.
 */
export function dominates(a, b) {
  let $ = compare(a, b);
  if ($ instanceof Before) {
    return false;
  } else if ($ instanceof After) {
    return true;
  } else if ($ instanceof Concurrent) {
    return false;
  } else {
    return true;
  }
}

/**
 * Check whether a version vector is empty (has no clock entries).
 */
export function is_empty(vector) {
  let clocks = vector.dict;
  return $dict.is_empty(clocks);
}

/**
 * Set the clock for a replica to the maximum of the current value and `value`.
 *
 * If the replica has no entry, `value` is used. This avoids round-tripping
 * through `to_dict`/`from_dict` when building a version vector incrementally.
 */
export function set_max(vv, replica_id, value) {
  let clocks = vv.dict;
  let current = $result.unwrap($dict.get(clocks, replica_id), 0);
  let $ = value > current;
  if ($) {
    return new VersionVector($dict.insert(clocks, replica_id, value));
  } else {
    return vv;
  }
}

/**
 * Merge two version vectors using pairwise maximum.
 *
 * For each replica, the merged clock is the maximum of the two inputs.
 * This operation is commutative, associative, and idempotent.
 */
export function merge(a, b) {
  let a_clocks = a.dict;
  let b_clocks = b.dict;
  let merged = $dict.fold(
    b_clocks,
    a_clocks,
    (acc, key, b_clock) => {
      let $ = $dict.get(acc, key);
      if ($ instanceof Ok) {
        let a_clock = $[0];
        return $dict.insert(acc, key, $int.max(a_clock, b_clock));
      } else {
        return $dict.insert(acc, key, b_clock);
      }
    },
  );
  return new VersionVector(merged);
}

/**
 * Encode a VersionVector as a self-describing JSON value.
 *
 * Produces an envelope with `type`, `v` (schema version), and `state`.
 * Format: `{"type": "version_vector", "v": 1, "state": {"clocks": {...}}}`
 *
 * Use `from_json` to decode the result back into a `VersionVector`.
 */
export function to_json(vector) {
  let clocks = vector.dict;
  return $json.object(
    toList([
      ["type", $json.string("version_vector")],
      ["v", $json.int(1)],
      [
        "state",
        $json.object(
          toList([
            [
              "clocks",
              $json.dict(
                clocks,
                (key) => { return $replica_id.to_string(key); },
                $json.int,
              ),
            ],
          ]),
        ),
      ],
    ]),
  );
}

/**
 * Decode a VersionVector from a JSON string produced by `to_json`.
 *
 * Returns `Ok(VersionVector)` on success, or `Error(json.DecodeError)` if
 * the input is not a valid version-vector JSON envelope.
 */
export function from_json(json_string) {
  let state_decoder = $decode.field(
    "state",
    $decode.field(
      "clocks",
      $decode.dict($replica_id.decoder(), $decode.int),
      (clocks) => { return $decode.success(new VersionVector(clocks)); },
    ),
    (state) => { return $decode.success(state); },
  );
  let envelope_decoder = $decode.field(
    "type",
    $decode.string,
    (type_tag) => {
      return $decode.field(
        "v",
        $decode.int,
        (version) => { return $decode.success([type_tag, version]); },
      );
    },
  );
  let $ = $json.parse(json_string, envelope_decoder);
  if ($ instanceof Ok) {
    let type_tag = $[0][0];
    let version = $[0][1];
    let $1 = (type_tag === "version_vector") && (version === 1);
    if ($1) {
      return $json.parse(json_string, state_decoder);
    } else {
      return new Error(
        new $json.UnableToDecode(
          toList([
            new $decode.DecodeError(
              "type=version_vector and v=1",
              (type_tag + " v=") + $int.to_string(version),
              $List$Empty$const,
            ),
          ]),
        ),
      );
    }
  } else {
    return $;
  }
}

/**
 * A JSON decoder for VersionVector values.
 *
 * Decodes the self-describing envelope format produced by `to_json`.
 * Useful as a building block in `from_json` decoders when a VersionVector
 * is embedded inline within another JSON structure.
 */
export function decoder() {
  return $decode.field(
    "type",
    $decode.string,
    (_) => {
      return $decode.field(
        "v",
        $decode.int,
        (_) => {
          return $decode.field(
            "state",
            $decode.field(
              "clocks",
              $decode.dict($replica_id.decoder(), $decode.int),
              (clocks) => { return $decode.success(clocks); },
            ),
            (clocks) => { return $decode.success(new VersionVector(clocks)); },
          );
        },
      );
    },
  );
}

/**
 * Extract the internal clock dictionary from a VersionVector.
 *
 * Returns a `Dict(ReplicaId, Int)` mapping replica IDs to their clock values.
 * Useful for serialization or when you need direct access to the raw clock
 * data. Prefer the higher-level API (`get`, `compare`, `merge`) for most
 * use cases.
 */
export function to_dict(vector) {
  let clocks = vector.dict;
  return clocks;
}

/**
 * Construct a VersionVector from a raw clock dictionary.
 *
 * Creates a version vector from a `Dict(ReplicaId, Int)` mapping replica IDs
 * to clock values. Useful for deserialization or constructing a version
 * vector from external data. Prefer `new` and `increment` for most use
 * cases.
 */
export function from_dict(clocks) {
  return new VersionVector(clocks);
}
