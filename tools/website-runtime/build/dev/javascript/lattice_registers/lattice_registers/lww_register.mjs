/// <reference types="./lww_register.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $bool from "../../gleam_stdlib/gleam/bool.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $order from "../../gleam_stdlib/gleam/order.mjs";
import * as $replica from "../../lattice_core/lattice_core/replica_id.mjs";
import {
  Ok,
  Error,
  toList,
  List$Empty$const as $List$Empty$const,
  CustomType as $CustomType,
} from "../gleam.mjs";

class LWWRegister extends $CustomType {
  constructor(value, timestamp, replica_id) {
    super();
    this.value = value;
    this.timestamp = timestamp;
    this.replica_id = replica_id;
  }
}

/**
 * Create a new LWW-Register with an initial value, timestamp, and replica ID.
 *
 * `timestamp` should be a positive integer representing the logical time of
 * the write. Use a monotonically increasing source (e.g., wall-clock
 * milliseconds or a Lamport clock) so that later writes have higher values.
 * `replica_id` identifies the writing node and is used as a deterministic
 * tie-breaker when two registers have equal timestamps during merge.
 */
export function new$(value, timestamp, replica_id) {
  return new LWWRegister(value, timestamp, replica_id);
}

/**
 * Set a value and return both the new state and a delta.
 *
 * The returned delta is an `LWWRegister` carrying the write that was
 * actually accepted locally. When `timestamp` strictly exceeds the current
 * timestamp the delta carries the new (value, timestamp, replica_id);
 * otherwise the local set is a no-op and the delta carries the unchanged
 * register so that no rejected write can win on a remote replica.
 *
 * Merging the delta into a remote via `merge` produces the same result as
 * merging the new local state, preserving convergence.
 */
export function set_with_delta(register, value, timestamp, replica_id) {
  return $bool.guard(
    timestamp <= register.timestamp,
    [register, register],
    () => {
      let updated = new LWWRegister(value, timestamp, replica_id);
      return [updated, updated];
    },
  );
}

/**
 * Write a value as `replica_id` if `timestamp` is strictly greater.
 *
 * If `timestamp > register.timestamp`, replaces the stored value and
 * write metadata. Otherwise returns the register unchanged. Supplying the
 * writer explicitly prevents a local write after `merge` from inheriting the
 * winning remote writer's identity.
 *
 * Note that the comparison is *strict*, so a wall clock is not a safe source
 * on its own: it stalls for a millisecond at a time, and a second write
 * inside the same tick is silently dropped even when it came from this same
 * replica. Callers that write faster than their clock ticks should stamp
 * `int.max(wall_clock, timestamp(register) + 1)`, which keeps every local
 * write ordered while leaving `merge` commutative.
 *
 * A writer must not reuse the same `(timestamp, replica_id)` for different
 * values. After a restart, use a fresh replica ID or restore a durable logical
 * clock that advances beyond every prior write from that ID.
 *
 * See `set_with_delta` for the delta-state variant that also returns a
 * small payload suitable for incremental sync (e.g. over websockets).
 *
 * ## Examples
 *
 * ```gleam
 * let local = replica_id.new("B")
 * let adopted = lww_register.new("old", 1, replica_id.new("A"))
 * let updated = lww_register.set(adopted, "new", 2, local)
 * lww_register.replica_id(updated)  // -> local
 * ```
 */
export function set(register, value, timestamp, replica_id) {
  let $ = set_with_delta(register, value, timestamp, replica_id);
  let updated = $[0];
  return updated;
}

/**
 * Return the current value of the register.
 *
 * Provided for a uniform functional API since the type is opaque.
 */
export function value(register) {
  return register.value;
}

/**
 * Return the timestamp of the write the register currently holds.
 *
 * Because `set` accepts only strictly greater timestamps, a caller stamping
 * writes from a wall clock needs to know the timestamp already held in order
 * to stay ahead of it — two writes inside the same clock tick are otherwise
 * unordered and the second is dropped. Reading this back from a decoded
 * snapshot lets such a caller seed its logical clock before its first write.
 *
 * ## Examples
 *
 * ```gleam
 * let register = lww_register.new("hello", 42, replica_id.new("node-a"))
 * lww_register.timestamp(register)  // -> 42
 *
 * // Stamp the next write so it cannot collide with the one held.
 * let next = int.max(wall_clock_ms(), lww_register.timestamp(register) + 1)
 * ```
 */
export function timestamp(register) {
  return register.timestamp;
}

/**
 * Return the replica that owns the value the register currently holds.
 *
 * `set` records its supplied author only for an accepted write. After `merge`
 * this is the replica whose write won, which makes it useful for provenance
 * and for tie-breaking consistently with `merge` in downstream code.
 */
export function replica_id(register) {
  return register.replica_id;
}

/**
 * Merge two LWW-Registers by returning the one with the higher timestamp.
 *
 * When `a.timestamp > b.timestamp`, returns `a`. When `b.timestamp >
 * a.timestamp`, returns `b`. On equal timestamps, the register whose
 * `replica_id` is lexicographically greater wins, providing a fully
 * commutative, associative, and idempotent merge.
 */
export function merge(a, b) {
  return $bool.guard(
    a.timestamp > b.timestamp,
    a,
    () => {
      return $bool.guard(
        a.timestamp < b.timestamp,
        b,
        () => {
          let $ = $replica.compare(a.replica_id, b.replica_id);
          if ($ instanceof $order.Lt) {
            return b;
          } else if ($ instanceof $order.Eq) {
            return a;
          } else {
            return a;
          }
        },
      );
    },
  );
}

/**
 * Encode a register with a custom payload encoder, preserving write metadata.
 *
 * Uses the same v2 envelope as `to_json`.
 *
 * ## Examples
 *
 * ```gleam
 * let register = lww_register.new(42, 1, replica_id.new("A"))
 * lww_register.to_json_with(register, json.int)
 * ```
 */
export function to_json_with(register, encode) {
  return $json.object(
    toList([
      ["type", $json.string("lww_register")],
      ["v", $json.int(2)],
      [
        "state",
        $json.object(
          toList([
            ["value", encode(register.value)],
            ["timestamp", $json.int(register.timestamp)],
            [
              "replica_id",
              $json.string($replica.to_string(register.replica_id)),
            ],
          ]),
        ),
      ],
    ]),
  );
}

/**
 * Encode a LWWRegister(String) as a self-describing JSON value.
 *
 * Produces an envelope with `type`, `v` (schema version = 2), and `state`.
 * Format: `{"type": "lww_register", "v": 2, "state": {"value": "...", "timestamp": ..., "replica_id": "..."}}`
 *
 * Use `from_json` to decode the result back into a `LWWRegister(String)`.
 */
export function to_json(register) {
  return to_json_with(register, $json.string);
}

/**
 * Decode a register with a custom payload decoder.
 *
 * Accepts v1 and v2 envelopes, with the same metadata rules as `from_json`.
 * V2 requires `replica_id` to be present and contain a string, including when
 * that string is empty. Invalid payloads or envelopes return `Error`.
 *
 * ## Examples
 *
 * ```gleam
 * let register = lww_register.new(42, 1, replica_id.new("A"))
 * let encoded = lww_register.to_json_with(register, json.int) |> json.to_string
 * lww_register.from_json_with(encoded, decode.int)  // -> Ok(register)
 * ```
 */
export function from_json_with(json_string, decoder) {
  let v1_state_decoder = $decode.field(
    "state",
    $decode.field(
      "value",
      decoder,
      (value) => {
        return $decode.field(
          "timestamp",
          $decode.int,
          (timestamp) => {
            return $decode.optional_field(
              "replica_id",
              "",
              $decode.string,
              (replica_id_str) => {
                return $decode.success(
                  new LWWRegister(
                    value,
                    timestamp,
                    $replica.new$(replica_id_str),
                  ),
                );
              },
            );
          },
        );
      },
    ),
    (state) => { return $decode.success(state); },
  );
  let v2_state_decoder = $decode.field(
    "state",
    $decode.field(
      "value",
      decoder,
      (value) => {
        return $decode.field(
          "timestamp",
          $decode.int,
          (timestamp) => {
            return $decode.field(
              "replica_id",
              $decode.string,
              (replica_id_str) => {
                return $decode.success(
                  new LWWRegister(
                    value,
                    timestamp,
                    $replica.new$(replica_id_str),
                  ),
                );
              },
            );
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
    if (type_tag === "lww_register") {
      if (version === 1) {
        return $json.parse(json_string, v1_state_decoder);
      } else if (version === 2) {
        return $json.parse(json_string, v2_state_decoder);
      } else {
        return new Error(
          new $json.UnableToDecode(
            toList([
              new $decode.DecodeError(
                "type=lww_register and v=1 or v=2",
                (type_tag + " v=") + $int.to_string(version),
                $List$Empty$const,
              ),
            ]),
          ),
        );
      }
    } else {
      return new Error(
        new $json.UnableToDecode(
          toList([
            new $decode.DecodeError(
              "type=lww_register and v=1 or v=2",
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
 * Decode a LWWRegister(String) from a JSON string produced by `to_json`.
 *
 * Supports both v1 (no replica_id, uses the legacy `""` placeholder) and v2
 * (requires a string replica_id) envelopes. The v1 placeholder does not prove
 * the identity of the historical writer; pass the local replica ID to `set`
 * for every subsequent write. Returns `Ok(LWWRegister(String))` on success, or
 * `Error(json.DecodeError)` if the input is not a valid LWW-Register JSON
 * envelope.
 */
export function from_json(json_string) {
  return from_json_with(json_string, $decode.string);
}
