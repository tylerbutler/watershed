/// <reference types="./replica_id.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $bit_array from "../../gleam_stdlib/gleam/bit_array.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $order from "../../gleam_stdlib/gleam/order.mjs";
import { CustomType as $CustomType, toBitArray, stringBits } from "../gleam.mjs";

class ReplicaId extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

/**
 * Create a new ReplicaId from a string.
 */
export function new$(id) {
  return new ReplicaId(id);
}

/**
 * Extract the underlying string from a ReplicaId.
 */
export function to_string(replica_id) {
  let s = replica_id[0];
  return s;
}

/**
 * Compare two ReplicaId values by lexicographic UTF-8 byte order.
 *
 * Uses the same order on Erlang and JavaScript for deterministic tie-breaking
 * (e.g., in LWW-Register merge when timestamps are equal). Strings retain their
 * original form; no Unicode normalization is applied.
 *
 * ## Examples
 *
 * ```gleam
 * compare(new("\u{e000}"), new("\u{10000}"))
 * // -> order.Lt
 * ```
 */
export function compare(a, b) {
  let a$1 = a[0];
  let b$1 = b[0];
  return $bit_array.compare(
    toBitArray([stringBits(a$1)]),
    toBitArray([stringBits(b$1)]),
  );
}

/**
 * Encode a ReplicaId as a JSON string.
 */
export function to_json(replica_id) {
  return $json.string(to_string(replica_id));
}

/**
 * A decoder for ReplicaId values in JSON.
 *
 * Decodes a JSON string and wraps it in a ReplicaId. Useful as a building
 * block in `from_json` decoders across the library.
 */
export function decoder() {
  return $decode.map($decode.string, new$);
}
