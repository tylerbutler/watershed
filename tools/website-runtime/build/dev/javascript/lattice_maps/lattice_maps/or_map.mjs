/// <reference types="./or_map.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $replica_id from "../../lattice_core/lattice_core/replica_id.mjs";
import * as $version_vector from "../../lattice_core/lattice_core/version_vector.mjs";
import * as $crdt from "../lattice_maps/crdt.mjs";

/**
 * Create an empty map.
 *
 * ## Examples
 *
 * ```gleam
 * or_map.new(replica_id.new("A"), crdt.OrMapSpec(crdt.TextSpec))
 * ```
 */
export function new$(replica, spec) {
  return $crdt.or_new(replica, spec);
}

/**
 * Return the local editing identity.
 *
 * ## Examples
 *
 * ```gleam
 * let local = replica_id.new("A")
 * let map = or_map.new(local, crdt.TextSpec)
 * or_map.replica_id(map) // -> local
 * ```
 */
export function replica_id(map) {
  return $crdt.or_replica(map);
}

/**
 * Return the complete child schema.
 *
 * ## Examples
 *
 * ```gleam
 * let schema = crdt.OrMapSpec(crdt.LwwRegisterSpec(42))
 * let map = or_map.new(replica_id.new("A"), schema)
 * or_map.spec(map) // -> schema
 * ```
 */
export function spec(map) {
  return $crdt.or_spec(map);
}

/**
 * Bind a loaded or received map to the local writer without rewriting history.
 *
 * Child callbacks receive identities scoped by key and generation. Keep each
 * independent writer's logical replica ID distinct.
 *
 * ## Examples
 *
 * ```gleam
 * let source = or_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(""))
 * let snapshot = source |> or_map.to_json |> json.to_string
 * let assert Ok(loaded) = or_map.from_json(snapshot)
 * let local = or_map.bind(loaded, replica_id.new("B"))
 * or_map.replica_id(local) // -> replica_id.new("B")
 * ```
 */
export function bind(map, replica) {
  return $crdt.or_bind(map, replica);
}

/**
 * Get an active child bound to this map's local editing scope.
 *
 * ## Examples
 *
 * ```gleam
 * let map = or_map.new(replica_id.new("A"), crdt.GCounterSpec)
 * let assert Ok(map) = or_map.update(map, "score", fn(value) { value })
 * let assert Ok(crdt.CrdtGCounter(counter)) = or_map.get(map, "score")
 * g_counter.value(counter) // -> 0
 * ```
 */
export function get(map, key) {
  return $crdt.or_get(map, key);
}

/**
 * Return active keys, in unspecified order.
 *
 * ## Examples
 *
 * ```gleam
 * let map = or_map.new(replica_id.new("A"), crdt.TextSpec)
 * let assert Ok(map) = or_map.update(map, "body", fn(value) { value })
 * or_map.keys(map) // -> ["body"]
 * ```
 */
export function keys(map) {
  return $crdt.or_keys(map);
}

/**
 * Return active, locally bound children, in unspecified order.
 *
 * ## Examples
 *
 * ```gleam
 * let map = or_map.new(replica_id.new("A"), crdt.TextSpec)
 * or_map.values(map) // -> []
 * ```
 */
export function values(map) {
  return $crdt.or_values(map);
}

/**
 * Run a full-value callback once and return the touched-key state delta.
 *
 * The delta carries the complete returned child state. For large Sequence/Text
 * children, use `update_delta` instead.
 *
 * ## Examples
 *
 * ```gleam
 * let map = or_map.new(replica_id.new("A"), crdt.GSetSpec)
 * let assert Ok(#(updated, delta)) =
 *   or_map.update_with_delta(map, "tags", fn(value) {
 *     let assert crdt.CrdtGSet(tags) = value
 *     crdt.CrdtGSet(g_set.add(tags, "ready"))
 *   })
 * or_map.apply_delta(map, delta) // -> Ok(updated)
 * ```
 */
export function update_with_delta(map, key, callback) {
  return $crdt.or_update_with_delta(map, key, callback);
}

/**
 * Join the callback's full child state within the current generation.
 *
 * Removal/re-add, rather than a non-monotone callback, resets a child.
 * Use `update_delta` when a leaf operation can return a sparse delta, or when
 * a new LWWRegister write needs the callback's explicit author identity.
 *
 * ## Examples
 *
 * ```gleam
 * let map = or_map.new(replica_id.new("A"), crdt.GSetSpec)
 * let assert Ok(map) = or_map.update(map, "tags", fn(value) {
 *   let assert crdt.CrdtGSet(tags) = value
 *   crdt.CrdtGSet(g_set.add(tags, "reviewed"))
 * })
 * or_map.keys(map) // -> ["tags"]
 * ```
 */
export function update(map, key, callback) {
  let _pipe = update_with_delta(map, key, callback);
  return $result.map(_pipe, (pair) => { return pair[0]; });
}

/**
 * Run a sparse callback once, apply its delta, and return the resulting map/change.
 *
 * Errors are atomic. `NoChange` still refreshes membership, so it is an
 * add-wins update. The callback context supplies the scoped author for new
 * LWWRegister writes. Nested maps return `crdt.OrMapChange(child_delta)`.
 *
 * ## Examples
 *
 * Author a register write with the supplied scope, not the old write's author:
 *
 * ```gleam
 * import lattice_registers/lww_register
 *
 * let map = or_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(""))
 * let assert Ok(#(updated, delta)) =
 *   or_map.update_delta(map, "title", fn(value, context) {
 *     let assert crdt.CrdtLwwRegister(register) = value
 *     let #(_, change) = lww_register.set_with_delta(
 *       register, "New title", lww_register.timestamp(register) + 1,
 *       context.replica_id,
 *     )
 *     Ok(crdt.StateDelta(crdt.CrdtLwwRegister(change)))
 *   })
 * or_map.apply_delta(map, delta) // -> Ok(updated)
 * ```
 *
 * Keep an inner ORMap change sparse through the outer map:
 *
 * ```gleam
 * import gleam/result
 * import lattice_text/text
 *
 * let map: or_map.ORMap(String) =
 *   or_map.new(replica_id.new("A"), crdt.OrMapSpec(crdt.TextSpec))
 * let assert Ok(#(updated, delta)) =
 *   or_map.update_delta(map, "document", fn(value, _) {
 *     let assert crdt.CrdtOrMap(document) = value
 *     use #(_, change) <- result.try(
 *       or_map.update_delta(document, "body", fn(value, _) {
 *         let assert crdt.CrdtText(body) = value
 *         use #(_, change) <- result.try(text.append_with_delta(body, "Hello"))
 *         Ok(crdt.StateDelta(crdt.CrdtText(change)))
 *       }),
 *     )
 *     Ok(crdt.OrMapChange(change))
 *   })
 * or_map.apply_delta(map, delta) // -> Ok(updated)
 * ```
 */
export function update_delta(map, key, callback) {
  return $crdt.or_update_delta(map, key, callback);
}

/**
 * Remove observed membership and return a generation-bearing removal delta.
 *
 * ## Examples
 *
 * ```gleam
 * let map = or_map.new(replica_id.new("A"), crdt.TextSpec)
 * let assert Ok(map) = or_map.update(map, "body", fn(value) { value })
 * let #(removed, delta) = or_map.remove_with_delta(map, "body")
 * or_map.apply_delta(map, delta) // -> Ok(removed)
 * ```
 */
export function remove_with_delta(map, key) {
  return $crdt.or_remove_with_delta(map, key);
}

/**
 * Remove observed membership; keep current-generation child history.
 *
 * ## Examples
 *
 * ```gleam
 * let map = or_map.new(replica_id.new("A"), crdt.TextSpec)
 * let assert Ok(map) = or_map.update(map, "body", fn(value) { value })
 * or_map.remove(map, "body") |> or_map.get("body") // -> Error(Nil)
 * ```
 */
export function remove(map, key) {
  return remove_with_delta(map, key)[0];
}

/**
 * Merge into an explicit receiving identity, including remote-only children.
 *
 * ## Examples
 *
 * ```gleam
 * let a = or_map.new(replica_id.new("A"), crdt.SequenceSpec)
 * let b = or_map.new(replica_id.new("B"), crdt.SequenceSpec)
 * let local = replica_id.new("C")
 * let assert Ok(merged) = or_map.merge_as(a, b, local)
 * or_map.replica_id(merged) // -> local
 * ```
 */
export function merge_as(a, b, replica) {
  return $crdt.or_merge_as(a, b, replica);
}

/**
 * Merge into the left map's local identity.
 *
 * ## Examples
 *
 * ```gleam
 * let a = or_map.new(replica_id.new("A"), crdt.GCounterSpec)
 * let b = or_map.new(replica_id.new("B"), crdt.GCounterSpec)
 * let assert Ok(merged) = or_map.merge(a, b)
 * or_map.replica_id(merged) // -> replica_id.new("A")
 * ```
 */
export function merge(a, b) {
  return merge_as(a, b, replica_id(a));
}

/**
 * Return an empty transport batch.
 *
 * ## Examples
 *
 * ```gleam
 * let map = or_map.new(replica_id.new("A"), crdt.TextSpec)
 * or_map.apply_delta(map, or_map.empty_delta(map)) // -> Ok(map)
 * ```
 */
export function empty_delta(map) {
  return $crdt.or_empty_delta(map);
}

/**
 * Apply only touched keys, selecting generations before child changes.
 *
 * Missing Sequence origins can produce an incomplete view until the required
 * baseline or earlier deltas arrive. Bind the receiving map before editing it.
 *
 * ## Examples
 *
 * ```gleam
 * let source = or_map.new(replica_id.new("A"), crdt.GCounterSpec)
 * let assert Ok(#(_, delta)) =
 *   or_map.update_with_delta(source, "score", fn(value) { value })
 * let receiver = or_map.new(replica_id.new("B"), crdt.GCounterSpec)
 * let assert Ok(receiver) = or_map.apply_delta(receiver, delta)
 * or_map.keys(receiver) // -> ["score"]
 * ```
 */
export function apply_delta(map, delta) {
  return $crdt.or_apply_delta(map, delta);
}

/**
 * Combine sparse changes without turning nested deltas into snapshots.
 *
 * ## Examples
 *
 * ```gleam
 * let map = or_map.new(replica_id.new("A"), crdt.TextSpec)
 * let assert Ok(#(first, a)) =
 *   or_map.update_with_delta(map, "first", fn(value) { value })
 * let assert Ok(#(updated, b)) =
 *   or_map.update_with_delta(first, "second", fn(value) { value })
 * let assert Ok(batch) = or_map.merge_deltas(a, b)
 * or_map.apply_delta(map, batch) // -> Ok(updated)
 * ```
 */
export function merge_deltas(a, b) {
  return $crdt.or_merge_deltas(a, b);
}

/**
 * Prune stable membership tombstones, but retain floors and current leaf history.
 *
 * Outer stability never compacts inner Sequence/Text history or forwardings.
 * The vector must cover the namespaced membership tags in map deltas, not the
 * logical writer's unrelated leaf clocks. Each key/generation is a causal scope.
 *
 * ## Examples
 *
 * ```gleam
 * let map = or_map.new(replica_id.new("A"), crdt.TextSpec)
 * // An empty frontier makes no events stable.
 * or_map.prune(map, version_vector.new()) // -> map
 * ```
 */
export function prune(map, stable) {
  return $crdt.or_prune(map, stable);
}

export function internal_value_count(map) {
  return $crdt.or_value_count(map);
}

/**
 * Encode a String-payload modern snapshot (version 3).
 *
 * ## Examples
 *
 * ```gleam
 * let map = or_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(""))
 * let encoded = map |> or_map.to_json |> json.to_string
 * or_map.from_json(encoded) // -> Ok(map)
 * ```
 */
export function to_json(map) {
  return $crdt.or_to_json_with(map, $json.string);
}

/**
 * Encode a generic modern snapshot.
 *
 * The encoder handles payloads and configured register defaults at every depth.
 * Text remains a concrete String/grapheme type.
 *
 * ## Examples
 *
 * ```gleam
 * let map = or_map.new(
 *   replica_id.new("A"), crdt.OrMapSpec(crdt.LwwRegisterSpec(42)),
 * )
 * let encoded = or_map.to_json_with(map, json.int) |> json.to_string
 * or_map.from_json_with(encoded, decode.int) // -> Ok(map)
 * ```
 */
export function to_json_with(map, encode) {
  return $crdt.or_to_json_with(map, encode);
}

/**
 * Decode a generic modern snapshot, including recursive configured defaults.
 *
 * Legacy map snapshots require `import_legacy` instead.
 *
 * ## Examples
 *
 * ```gleam
 * let map = or_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(42))
 * let encoded = or_map.to_json_with(map, json.int) |> json.to_string
 * let assert Ok(loaded) = or_map.from_json_with(encoded, decode.int)
 * or_map.spec(loaded) // -> crdt.LwwRegisterSpec(42)
 * ```
 */
export function from_json_with(input, decoder) {
  return $crdt.or_from_json_with(input, decoder);
}

/**
 * Decode a modern String snapshot. Call `bind` before editing as another writer.
 *
 * ## Examples
 *
 * ```gleam
 * let source = or_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(""))
 * let encoded = source |> or_map.to_json |> json.to_string
 * let assert Ok(loaded) = or_map.from_json(encoded)
 * let local = or_map.bind(loaded, replica_id.new("B"))
 * or_map.replica_id(local) // -> replica_id.new("B")
 * ```
 */
export function from_json(input) {
  return from_json_with(input, $decode.string);
}

/**
 * Encode a generic sparse delta.
 *
 * ## Examples
 *
 * ```gleam
 * let map = or_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(42))
 * let assert Ok(#(_, delta)) = or_map.update_delta(map, "answer", fn(_, _) {
 *   Ok(crdt.NoChange(crdt.LwwRegisterSpec(42)))
 * })
 * let encoded = or_map.delta_to_json_with(delta, json.int) |> json.to_string
 * or_map.delta_from_json_with(encoded, decode.int) // -> Ok(delta)
 * ```
 */
export function delta_to_json_with(delta, encode) {
  return $crdt.or_delta_to_json_with(delta, encode);
}

/**
 * Encode a String-payload sparse delta (version 2).
 *
 * ## Examples
 *
 * ```gleam
 * let map = or_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(""))
 * let delta = or_map.empty_delta(map)
 * let encoded = delta |> or_map.delta_to_json |> json.to_string
 * or_map.delta_from_json(encoded) // -> Ok(delta)
 * ```
 */
export function delta_to_json(delta) {
  return delta_to_json_with(delta, $json.string);
}

/**
 * Decode a generic sparse delta.
 *
 * ## Examples
 *
 * ```gleam
 * let map = or_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(42))
 * let delta = or_map.empty_delta(map)
 * let encoded = or_map.delta_to_json_with(delta, json.int) |> json.to_string
 * let assert Ok(decoded) = or_map.delta_from_json_with(encoded, decode.int)
 * or_map.apply_delta(map, decoded) // -> Ok(map)
 * ```
 */
export function delta_from_json_with(input, decoder) {
  return $crdt.or_delta_from_json_with(input, decoder);
}

/**
 * Decode a modern String delta. Legacy map deltas are intentionally rejected.
 *
 * ## Examples
 *
 * ```gleam
 * let map = or_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(""))
 * let delta = or_map.empty_delta(map)
 * let encoded = delta |> or_map.delta_to_json |> json.to_string
 * let assert Ok(decoded) = or_map.delta_from_json(encoded)
 * or_map.apply_delta(map, decoded) // -> Ok(map)
 * ```
 */
export function delta_from_json(input) {
  return delta_from_json_with(input, $decode.string);
}

/**
 * Import a coordinated legacy baseline into Initial generations.
 *
 * Supply the agreed schema/default and a fresh editing identity if old allocation
 * history is missing. Distribute a modern snapshot; do not mix old map deltas.
 *
 * ## Examples
 *
 * Convert an agreed legacy register-map baseline to a modern snapshot:
 *
 * ```gleam
 * import gleam/dynamic/decode
 * import gleam/result
 * import lattice_core/replica_id
 * import lattice_maps/crdt
 * import lattice_maps/or_map
 *
 * pub fn migrate(legacy_snapshot: String) {
 *   use map <- result.try(or_map.import_legacy(
 *     legacy_snapshot, crdt.LwwRegisterSpec(""), decode.string,
 *     replica_id.new("cutover-writer"),
 *   ))
 *   Ok(or_map.to_json(map))
 * }
 * ```
 */
export function import_legacy(input, spec, decoder, replica) {
  return $crdt.or_import_legacy(input, spec, decoder, replica);
}
