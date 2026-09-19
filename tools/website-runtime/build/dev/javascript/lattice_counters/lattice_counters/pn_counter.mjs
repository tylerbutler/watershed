/// <reference types="./pn_counter.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $replica_id from "../../lattice_core/lattice_core/replica_id.mjs";
import {
  Ok,
  Error,
  toList,
  List$Empty$const as $List$Empty$const,
  CustomType as $CustomType,
} from "../gleam.mjs";
import * as $g_counter from "../lattice_counters/g_counter.mjs";

class PNCounter extends $CustomType {
  constructor(positive, negative) {
    super();
    this.positive = positive;
    this.negative = negative;
  }
}

export class NegativeDelta extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const UpdateError$NegativeDelta = ($0) => new NegativeDelta($0);
export const UpdateError$isNegativeDelta = (value) =>
  value instanceof NegativeDelta;
export const UpdateError$NegativeDelta$0 = (value) => value[0];

/**
 * Create a new PN-Counter for the given replica.
 *
 * Returns a fresh counter with a zero value. Both inner G-Counters are
 * initialized with `replica_id` as their node identifier.
 */
export function new$(replica_id) {
  return new PNCounter($g_counter.new$(replica_id), $g_counter.new$(replica_id));
}

function self_id_of(c) {
  let $ = $g_counter.to_parts(c);
  let self_id = $[1];
  return self_id;
}

/**
 * Increment the counter by `delta` and return both the new state and a delta.
 *
 * The returned delta is a `PNCounter` whose positive G-Counter contains
 * only this replica's new positive count and whose negative G-Counter is
 * empty. Merging the delta into a remote replica via `merge` produces the
 * same observable result as merging the full new state.
 *
 * Returns `Error(NegativeDelta(delta))` if `delta` is negative.
 */
export function increment_with_delta(counter, delta) {
  let positive = counter.positive;
  let negative = counter.negative;
  let $ = $g_counter.increment_with_delta(positive, delta);
  if ($ instanceof Ok) {
    let updated_positive = $[0][0];
    let positive_delta = $[0][1];
    let updated = new PNCounter(updated_positive, negative);
    let delta_state = new PNCounter(
      positive_delta,
      $g_counter.new$(self_id_of(negative)),
    );
    return new Ok([updated, delta_state]);
  } else {
    let d = $[0][0];
    return new Error(new NegativeDelta(d));
  }
}

/**
 * Increment the counter by `delta`.
 *
 * Adds `delta` to the positive G-Counter.
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
 * Decrement the counter by `delta` and return both the new state and a delta.
 *
 * The returned delta is a `PNCounter` whose negative G-Counter contains
 * only this replica's new negative count and whose positive G-Counter is
 * empty. Merging the delta into a remote replica via `merge` produces the
 * same observable result as merging the full new state.
 *
 * Returns `Error(NegativeDelta(delta))` if `delta` is negative.
 */
export function decrement_with_delta(counter, delta) {
  let positive = counter.positive;
  let negative = counter.negative;
  let $ = $g_counter.increment_with_delta(negative, delta);
  if ($ instanceof Ok) {
    let updated_negative = $[0][0];
    let negative_delta = $[0][1];
    let updated = new PNCounter(positive, updated_negative);
    let delta_state = new PNCounter(
      $g_counter.new$(self_id_of(positive)),
      negative_delta,
    );
    return new Ok([updated, delta_state]);
  } else {
    let d = $[0][0];
    return new Error(new NegativeDelta(d));
  }
}

/**
 * Decrement the counter by `delta`.
 *
 * Adds `delta` to the negative G-Counter (which reduces the visible value).
 * Returns `Error(NegativeDelta(delta))` if `delta` is negative.
 *
 * See `decrement_with_delta` for the delta-state variant.
 */
export function decrement(counter, delta) {
  let _pipe = decrement_with_delta(counter, delta);
  return $result.map(_pipe, (pair) => { return pair[0]; });
}

/**
 * Get the current value of the counter.
 *
 * Returns the sum of positive increments minus the sum of negative
 * decrements observed across all replicas.
 */
export function value(counter) {
  let positive = counter.positive;
  let negative = counter.negative;
  return $g_counter.value(positive) - $g_counter.value(negative);
}

/**
 * Merge two PN-Counters.
 *
 * Merges the positive G-Counters and negative G-Counters independently using
 * pairwise maximum. The result's `self_id` is taken from `a`'s positive
 * G-Counter.
 *
 * This operation is commutative, associative, and idempotent.
 */
export function merge(a, b) {
  let positive_a = a.positive;
  let negative_a = a.negative;
  let positive_b = b.positive;
  let negative_b = b.negative;
  return new PNCounter(
    $g_counter.merge(positive_a, positive_b),
    $g_counter.merge(negative_a, negative_b),
  );
}

/**
 * Encode a PN-Counter as a self-describing JSON value.
 *
 * Produces an envelope with `type`, `v` (schema version), and `state`.
 * Format: `{"type": "pn_counter", "v": 1, "state": {"positive": {...}, "negative": {...}}}`
 *
 * Use `from_json` to decode the result back into a `PNCounter`.
 */
export function to_json(counter) {
  let positive = counter.positive;
  let negative = counter.negative;
  let $ = $g_counter.to_parts(positive);
  let pos_dict = $[0];
  let pos_id = $[1];
  let $1 = $g_counter.to_parts(negative);
  let neg_dict = $1[0];
  let neg_id = $1[1];
  return $json.object(
    toList([
      ["type", $json.string("pn_counter")],
      ["v", $json.int(1)],
      [
        "state",
        $json.object(
          toList([
            [
              "positive",
              $json.object(
                toList([
                  ["self_id", $replica_id.to_json(pos_id)],
                  [
                    "counts",
                    $json.dict(
                      pos_dict,
                      (k) => { return $replica_id.to_string(k); },
                      $json.int,
                    ),
                  ],
                ]),
              ),
            ],
            [
              "negative",
              $json.object(
                toList([
                  ["self_id", $replica_id.to_json(neg_id)],
                  [
                    "counts",
                    $json.dict(
                      neg_dict,
                      (k) => { return $replica_id.to_string(k); },
                      $json.int,
                    ),
                  ],
                ]),
              ),
            ],
          ]),
        ),
      ],
    ]),
  );
}

/**
 * Decode a PN-Counter from a JSON string produced by `to_json`.
 *
 * Returns `Ok(PNCounter)` on success, or `Error(json.DecodeError)` if the
 * input is not a valid PN-Counter JSON envelope.
 */
export function from_json(json_string) {
  let g_counter_state_decoder = $decode.field(
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
        (counts) => {
          return $decode.success($g_counter.from_parts(counts, self_id));
        },
      );
    },
  );
  let state_decoder = $decode.field(
    "state",
    $decode.field(
      "positive",
      g_counter_state_decoder,
      (positive) => {
        return $decode.field(
          "negative",
          g_counter_state_decoder,
          (negative) => {
            return $decode.success(new PNCounter(positive, negative));
          },
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
    let $1 = (type_tag === "pn_counter") && (version === 1);
    if ($1) {
      return $json.parse(json_string, state_decoder);
    } else {
      return new Error(
        new $json.UnableToDecode(
          toList([
            new $decode.DecodeError(
              "type=pn_counter and v=1",
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
