/// <reference types="./g_counter.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $bool from "../../gleam_stdlib/gleam/bool.mjs";
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $replica_id from "../../lattice_core/lattice_core/replica_id.mjs";
import {
  Ok,
  Error,
  toList,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  CustomType as $CustomType,
} from "../gleam.mjs";

class GCounter extends $CustomType {
  constructor(dict, self_id) {
    super();
    this.dict = dict;
    this.self_id = self_id;
  }
}

export class NegativeDelta extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const IncrementError$NegativeDelta = ($0) => new NegativeDelta($0);
export const IncrementError$isNegativeDelta = (value) =>
  value instanceof NegativeDelta;
export const IncrementError$NegativeDelta$0 = (value) => value[0];

/**
 * Create a new G-Counter for the given replica.
 *
 * Returns a fresh counter where all per-replica counts are zero.
 * The `replica_id` identifies this node and is used when incrementing.
 */
export function new$(replica_id) {
  return new GCounter($dict.new$(), replica_id);
}

/**
 * Increment the counter by `delta` and return both the new state and a delta.
 *
 * The returned delta is itself a `GCounter` containing only this replica's
 * new count. Merging the delta into a remote replica via `merge` produces
 * the same result as merging the full new state — but the delta is a
 * minimal payload suitable for incremental sync (e.g., over websockets).
 *
 * Returns `Error(NegativeDelta(delta))` if `delta` is negative.
 */
export function increment_with_delta(counter, delta) {
  return $bool.guard(
    delta < 0,
    new Error(new NegativeDelta(delta)),
    () => {
      let dict = counter.dict;
      let self_id = counter.self_id;
      let current = $result.unwrap($dict.get(dict, self_id), 0);
      let new_count = current + delta;
      let updated = new GCounter(
        $dict.insert(dict, self_id, new_count),
        self_id,
      );
      let delta_state = new GCounter(
        $dict.from_list(toList([[self_id, new_count]])),
        self_id,
      );
      return new Ok([updated, delta_state]);
    },
  );
}

/**
 * Increment the counter by `delta`.
 *
 * Adds `delta` to this replica's count.
 * Returns `Error(NegativeDelta(delta))` if `delta` is negative.
 *
 * See `increment_with_delta` for the delta-state variant that also returns
 * a small payload suitable for incremental sync (e.g. over websockets).
 */
export function increment(counter, delta) {
  let _pipe = increment_with_delta(counter, delta);
  return $result.map(_pipe, (pair) => { return pair[0]; });
}

/**
 * Get the current value of the counter.
 *
 * Returns the sum of all per-replica counts, which represents the total
 * number of increments applied across all replicas observed by this counter.
 */
export function value(counter) {
  let dict = counter.dict;
  return $dict.fold(dict, 0, (acc, _, value) => { return acc + value; });
}

function merge_helper(loop$a, loop$b, loop$keys, loop$acc) {
  while (true) {
    let a = loop$a;
    let b = loop$b;
    let keys = loop$keys;
    let acc = loop$acc;
    if (keys instanceof $Empty) {
      return acc;
    } else {
      let key = keys.head;
      let rest = keys.tail;
      let a_val = $result.unwrap($dict.get(a, key), 0);
      let b_val = $result.unwrap($dict.get(b, key), 0);
      let _block;
      let $ = a_val > b_val;
      if ($) {
        _block = a_val;
      } else {
        _block = b_val;
      }
      let merged_val = _block;
      let new_acc = $dict.insert(acc, key, merged_val);
      loop$a = a;
      loop$b = b;
      loop$keys = rest;
      loop$acc = new_acc;
    }
  }
}

/**
 * Merge two G-Counters using pairwise maximum.
 *
 * For each replica, the merged count is the maximum of the two inputs.
 * The result's `self_id` is taken from `a`.
 *
 * This operation is commutative, associative, and idempotent, satisfying
 * the CRDT join-semilattice laws. Any ordering of concurrent merges will
 * produce the same final state.
 */
export function merge(a, b) {
  let dict_a = a.dict;
  let self_id_a = a.self_id;
  let dict_b = b.dict;
  let a_keys = $dict.keys(dict_a);
  let b_keys = $dict.keys(dict_b);
  let all_keys = $list.unique($list.append(a_keys, b_keys));
  let merged_dict = merge_helper(dict_a, dict_b, all_keys, $dict.new$());
  return new GCounter(merged_dict, self_id_a);
}

/**
 * Encode a G-Counter as a self-describing JSON value.
 *
 * Produces an envelope with `type`, `v` (schema version), and `state`.
 * Format: `{"type": "g_counter", "v": 1, "state": {"self_id": "...", "counts": {...}}}`
 *
 * Use `from_json` to decode the result back into a `GCounter`.
 */
export function to_json(counter) {
  let d = counter.dict;
  let self_id = counter.self_id;
  return $json.object(
    toList([
      ["type", $json.string("g_counter")],
      ["v", $json.int(1)],
      [
        "state",
        $json.object(
          toList([
            ["self_id", $replica_id.to_json(self_id)],
            [
              "counts",
              $json.dict(
                d,
                (k) => { return $replica_id.to_string(k); },
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
 * Decode a G-Counter from a JSON string produced by `to_json`.
 *
 * Returns `Ok(GCounter)` on success, or `Error(json.DecodeError)` if the
 * input is not a valid G-Counter JSON envelope.
 */
export function from_json(json_string) {
  let state_decoder = $decode.field(
    "state",
    $decode.field(
      "self_id",
      $replica_id.decoder(),
      (self_id) => {
        let _block;
        let _pipe = $decode.int;
        _block = $decode.then$(
          _pipe,
          (val) => {
            let $ = val >= 0;
            if ($) {
              return $decode.success(val);
            } else {
              return $decode.failure(val, "a non-negative integer");
            }
          },
        );
        let non_negative_int = _block;
        return $decode.field(
          "counts",
          $decode.dict($replica_id.decoder(), non_negative_int),
          (counts) => { return $decode.success(new GCounter(counts, self_id)); },
        );
      },
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
    let $1 = (type_tag === "g_counter") && (version === 1);
    if ($1) {
      return $json.parse(json_string, state_decoder);
    } else {
      return new Error(
        new $json.UnableToDecode(
          toList([
            new $decode.DecodeError(
              "type=g_counter and v=1",
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
 * Extract the internal counts dictionary and self_id from a GCounter.
 * 
 * @ignore
 */
export function to_parts(counter) {
  let dict = counter.dict;
  let self_id = counter.self_id;
  return [dict, self_id];
}

/**
 * Construct a GCounter from a raw counts dictionary and self_id.
 * 
 * @ignore
 */
export function from_parts(dict, self_id) {
  return new GCounter(dict, self_id);
}
