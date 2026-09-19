/// <reference types="./two_p_set.d.mts" />
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

class TwoPSet extends $CustomType {
  constructor(added, removed) {
    super();
    this.added = added;
    this.removed = removed;
  }
}

/**
 * Create a new empty 2P-Set.
 */
export function new$() {
  return new TwoPSet($set.new$(), $set.new$());
}

/**
 * Add an element and return both the new state and a delta.
 *
 * The returned delta is a `TwoPSet` whose `added` set contains only the
 * inserted element and whose `removed` set is empty. Merging the delta
 * into a remote via `merge` (union of both halves) produces the same
 * result as merging the full new state.
 */
export function add_with_delta(two_p_set, element) {
  let updated = new TwoPSet(
    $set.insert(two_p_set.added, element),
    two_p_set.removed,
  );
  let delta = new TwoPSet($set.from_list(toList([element])), $set.new$());
  return [updated, delta];
}

/**
 * Add an element to the set.
 *
 * If the element has already been tombstoned (removed), this call records the
 * element in `added` but the element will not be considered active because
 * the tombstone takes precedence.
 *
 * See `add_with_delta` for the delta-state variant that also returns a
 * small payload suitable for incremental sync (e.g. over websockets).
 */
export function add(two_p_set, element) {
  let $ = add_with_delta(two_p_set, element);
  let updated = $[0];
  return updated;
}

/**
 * Remove an element and return both the new state and a delta.
 *
 * The returned delta is a `TwoPSet` whose `removed` set contains only the
 * tombstoned element and whose `added` set is empty. Merging the delta into
 * a remote via `merge` propagates the tombstone, deactivating the element
 * in the remote replica regardless of its prior state.
 */
export function remove_with_delta(two_p_set, element) {
  let updated = new TwoPSet(
    two_p_set.added,
    $set.insert(two_p_set.removed, element),
  );
  let delta = new TwoPSet($set.new$(), $set.from_list(toList([element])));
  return [updated, delta];
}

/**
 * Remove an element from the set by adding it to the tombstone set.
 *
 * Once tombstoned, the element is permanently inactive. Removing an element
 * that was never added is also valid and creates a preemptive tombstone.
 *
 * See `remove_with_delta` for the delta-state variant.
 */
export function remove(two_p_set, element) {
  let $ = remove_with_delta(two_p_set, element);
  let updated = $[0];
  return updated;
}

/**
 * Check if the set currently contains the given element.
 *
 * Returns `True` only if `element` is in `added` and NOT in `removed`.
 */
export function contains(two_p_set, element) {
  return $set.contains(two_p_set.added, element) && !$set.contains(
    two_p_set.removed,
    element,
  );
}

/**
 * Return the set of all currently active elements.
 *
 * Active elements are those in `added` that have not been tombstoned.
 * Equivalent to `added ∖ removed`.
 */
export function value(two_p_set) {
  return $set.filter(
    two_p_set.added,
    (element) => { return !$set.contains(two_p_set.removed, element); },
  );
}

/**
 * Merge two 2P-Sets by taking the union of both added sets and both removed sets.
 *
 * A tombstone on any replica propagates to all replicas after merge.
 * Merge is commutative, associative, and idempotent (a valid CRDT join).
 */
export function merge(a, b) {
  return new TwoPSet(
    $set.union(a.added, b.added),
    $set.union(a.removed, b.removed),
  );
}

/**
 * Encode generic elements and permanent tombstones in the v1 envelope.
 *
 * ## Examples
 *
 * ```gleam
 * let set = two_p_set.new() |> two_p_set.add(42) |> two_p_set.remove(42)
 * two_p_set.to_json_with(set, json.int)
 * ```
 */
export function to_json_with(two_p_set, encode) {
  return $json.object(
    toList([
      ["type", $json.string("two_p_set")],
      ["v", $json.int(1)],
      [
        "state",
        $json.object(
          toList([
            ["added", $json.array($set.to_list(two_p_set.added), encode)],
            ["removed", $json.array($set.to_list(two_p_set.removed), encode)],
          ]),
        ),
      ],
    ]),
  );
}

/**
 * Encode a `TwoPSet(String)` as a self-describing JSON value.
 *
 * Format: `{"type": "two_p_set", "v": 1, "state": {"added": [...], "removed": [...]}}`
 *
 * The encoded value can be restored with `from_json`.
 */
export function to_json(two_p_set) {
  return to_json_with(two_p_set, $json.string);
}

/**
 * Decode generic elements and permanent tombstones from the v1 envelope.
 *
 * Invalid envelopes or elements return `Error`.
 *
 * ## Examples
 *
 * ```gleam
 * let set = two_p_set.new() |> two_p_set.remove(42)
 * let encoded = two_p_set.to_json_with(set, json.int) |> json.to_string
 * two_p_set.from_json_with(encoded, decode.int)  // -> Ok(set)
 * ```
 */
export function from_json_with(json_string, decoder) {
  let state_decoder = $decode.field(
    "state",
    $decode.field(
      "added",
      $decode.list(decoder),
      (added) => {
        return $decode.field(
          "removed",
          $decode.list(decoder),
          (removed) => {
            return $decode.success(
              new TwoPSet($set.from_list(added), $set.from_list(removed)),
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
    let $1 = (type_tag === "two_p_set") && (version === 1);
    if ($1) {
      return $json.parse(json_string, state_decoder);
    } else {
      return new Error(
        new $json.UnableToDecode(
          toList([
            new $decode.DecodeError(
              "type=two_p_set and v=1",
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
 * Decode a `TwoPSet(String)` from a JSON string produced by `to_json`.
 *
 * Returns `Error` if the string is not valid JSON or does not match the
 * expected format.
 */
export function from_json(json_string) {
  return from_json_with(json_string, $decode.string);
}
