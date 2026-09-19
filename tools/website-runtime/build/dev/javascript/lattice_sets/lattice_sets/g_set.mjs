/// <reference types="./g_set.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $set from "../../gleam_stdlib/gleam/set.mjs";
import {
  Ok,
  Error,
  toList,
  List$Empty$const as $List$Empty$const,
  CustomType as $CustomType,
} from "../gleam.mjs";

class GSet extends $CustomType {
  constructor(elements) {
    super();
    this.elements = elements;
  }
}

/**
 * Create a new empty G-Set.
 */
export function new$() {
  return new GSet($set.new$());
}

/**
 * Add an element to the set and return both the new state and a delta.
 *
 * The returned delta is a `GSet` containing only the inserted element.
 * Merging the delta into a remote replica via `merge` (set union) produces
 * the same result as merging the full new state, but ships only the change.
 */
export function add_with_delta(g_set, element) {
  let updated = new GSet($set.insert(g_set.elements, element));
  let delta = new GSet($set.from_list(toList([element])));
  return [updated, delta];
}

/**
 * Add an element to the set.
 *
 * This operation is idempotent: adding the same element multiple times is
 * equivalent to adding it once.
 *
 * See `add_with_delta` for the delta-state variant that also returns a
 * small payload suitable for incremental sync (e.g. over websockets).
 */
export function add(g_set, element) {
  let $ = add_with_delta(g_set, element);
  let updated = $[0];
  return updated;
}

/**
 * Check if the set contains the given element.
 *
 * Returns `True` if `element` was ever added to this set or any merged replica.
 */
export function contains(g_set, element) {
  return $set.contains(g_set.elements, element);
}

/**
 * Return the underlying set of all elements.
 *
 * Equivalent to inspecting the entire current state of the G-Set.
 */
export function value(g_set) {
  return g_set.elements;
}

/**
 * Merge two G-Sets by computing their union.
 *
 * The result contains every element that was ever added to either set.
 * Merge is commutative, associative, and idempotent (a valid CRDT join).
 */
export function merge(a, b) {
  return new GSet($set.union(a.elements, b.elements));
}

/**
 * Encode a set using a custom element encoder and the existing v1 envelope.
 *
 * ## Examples
 *
 * ```gleam
 * let set = g_set.new() |> g_set.add(42)
 * g_set.to_json_with(set, json.int)
 * ```
 */
export function to_json_with(g_set, encode) {
  return $json.object(
    toList([
      ["type", $json.string("g_set")],
      ["v", $json.int(1)],
      [
        "state",
        $json.object(
          toList([
            ["elements", $json.array($set.to_list(g_set.elements), encode)],
          ]),
        ),
      ],
    ]),
  );
}

/**
 * Encode a `GSet(String)` as a self-describing JSON value.
 *
 * Format: `{"type": "g_set", "v": 1, "state": {"elements": [...]}}`
 *
 * The encoded value can be restored with `from_json`.
 */
export function to_json(g_set) {
  return to_json_with(g_set, $json.string);
}

/**
 * Decode a v1 set using a custom element decoder.
 *
 * Invalid envelopes or elements return `Error`.
 *
 * ## Examples
 *
 * ```gleam
 * let set = g_set.new() |> g_set.add(42)
 * let encoded = g_set.to_json_with(set, json.int) |> json.to_string
 * g_set.from_json_with(encoded, decode.int)  // -> Ok(set)
 * ```
 */
export function from_json_with(json_string, decoder) {
  let state_decoder = $decode.field(
    "state",
    $decode.field(
      "elements",
      $decode.list(decoder),
      (elements) => {
        return $decode.success(new GSet($set.from_list(elements)));
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
    let $1 = (type_tag === "g_set") && (version === 1);
    if ($1) {
      return $json.parse(json_string, state_decoder);
    } else {
      return new Error(
        new $json.UnableToDecode(
          toList([
            new $decode.DecodeError(
              "type=g_set and v=1",
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
 * Decode a `GSet(String)` from a JSON string produced by `to_json`.
 *
 * Returns `Error` if the string is not valid JSON or does not match the
 * expected format.
 */
export function from_json(json_string) {
  return from_json_with(json_string, $decode.string);
}
