/// <reference types="./lww_map.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $replica_id from "../../lattice_core/lattice_core/replica_id.mjs";
import * as $crdt from "../lattice_maps/crdt.mjs";

/**
 * Create an empty map for the local writer.
 *
 * ## Examples
 *
 * ```gleam
 * lww_map.new(replica_id.new("A"), crdt.TextSpec)
 * ```
 */
export function new$(replica, spec) {
  return $crdt.lww_new(replica, spec);
}

/**
 * Return the local writer identity.
 *
 * ## Examples
 *
 * ```gleam
 * let local = replica_id.new("A")
 * let map = lww_map.new(local, crdt.TextSpec)
 * lww_map.replica_id(map) // -> local
 * ```
 */
export function replica_id(map) {
  return $crdt.lww_replica(map);
}

/**
 * Return the complete child schema.
 *
 * ## Examples
 *
 * ```gleam
 * let schema = crdt.OrMapSpec(crdt.LwwRegisterSpec(42))
 * let map = lww_map.new(replica_id.new("A"), schema)
 * lww_map.spec(map) // -> schema
 * ```
 */
export function spec(map) {
  return $crdt.lww_spec(map);
}

/**
 * Set the local writer without changing stored assignment payloads or authors.
 *
 * Queries return bound copies. Use `update` to prepare edits under the new
 * assignment's identity, rather than editing under a historical writer.
 *
 * ## Examples
 *
 * ```gleam
 * let source = lww_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(""))
 * let snapshot = source |> lww_map.to_json |> json.to_string
 * let assert Ok(loaded) = lww_map.from_json(snapshot)
 * let local = lww_map.bind(loaded, replica_id.new("B"))
 * lww_map.replica_id(local) // -> replica_id.new("B")
 * ```
 */
export function bind(map, replica) {
  return $crdt.lww_bind(map, replica);
}

/**
 * Get a locally bound copy of an active child, without modifying its assignment.
 *
 * ## Examples
 *
 * ```gleam
 * let local = replica_id.new("A")
 * let map = lww_map.new(local, crdt.LwwRegisterSpec(""))
 * let child = crdt.CrdtLwwRegister(lww_register.new("Ready", 1, local))
 * let assert Ok(map) = lww_map.set(map, "status", child, 1)
 * let assert Ok(crdt.CrdtLwwRegister(status)) = lww_map.get(map, "status")
 * lww_register.value(status) // -> "Ready"
 * ```
 */
export function get(map, key) {
  return $crdt.lww_get(map, key);
}

/**
 * Assign a complete immutable child snapshot.
 *
 * For Sequence/Text edits or fresh replacements, prefer `update` and its new
 * assignment context to prevent allocation-ID reuse.
 *
 * The timestamp must not precede the key's timestamp and must exceed the prune
 * floor. An equal-time assignment uses the same tombstone, provenance, and
 * writer order as `merge`; generic child payloads are never compared. Reusing
 * one modern timestamp/writer for different active children returns
 * `ConflictingWrite`.
 *
 * ## Examples
 *
 * ```gleam
 * let local = replica_id.new("A")
 * let map = lww_map.new(local, crdt.LwwRegisterSpec(0))
 * let child = crdt.CrdtLwwRegister(lww_register.new(42, 1, local))
 * let assert Ok(map) = lww_map.set(map, "answer", child, 1)
 * lww_map.set(map, "answer", child, 1)
 * // -> Ok(map)
 * ```
 */
export function set(map, key, value, timestamp) {
  return $crdt.lww_set(map, key, value, timestamp);
}

/**
 * Edit once under the new assignment's namespace, then atomically assign.
 *
 * To replace a child from empty, construct its default with `context.replica_id`.
 * Inherited historical IDs remain intact. Failures leave the map unchanged.
 * Do not use a fixed replica ID to construct a replacement Sequence or Text:
 * each accepted assignment needs its own allocation namespace.
 *
 * ## Examples
 *
 * Replace Text from empty on each write, using the new assignment's context:
 *
 * ```gleam
 * import gleam/result
 * import lattice_text/text
 *
 * let map: lww_map.LWWMap(String) =
 *   lww_map.new(replica_id.new("A"), crdt.TextSpec)
 * let replace = fn(_, context: crdt.EditContext) {
 *   text.append(text.new(context.replica_id), "Replacement")
 *   |> result.map(crdt.CrdtText)
 * }
 * let assert Ok(first) = lww_map.update(map, "body", 1, replace)
 * let assert Ok(second) = lww_map.update(first, "body", 2, replace)
 * let assert Ok(crdt.CrdtText(body)) = lww_map.get(second, "body")
 * text.value(body) // -> "Replacement"
 * ```
 *
 * The same pattern gives a generic Sequence fresh item identities:
 *
 * ```gleam
 * import gleam/result
 * import lattice_sequence/sequence
 *
 * let map: lww_map.LWWMap(Int) =
 *   lww_map.new(replica_id.new("A"), crdt.SequenceSpec)
 * let assert Ok(map) = lww_map.update(map, "items", 1, fn(_, context) {
 *   sequence.insert_many(sequence.new(context.replica_id), 0, [10, 20])
 *   |> result.map(crdt.CrdtSequence)
 * })
 * let assert Ok(crdt.CrdtSequence(items)) = lww_map.get(map, "items")
 * sequence.values(items) // -> [10, 20]
 * ```
 *
 * To edit an existing child instead, use the callback's first argument. For an
 * LWWRegister, also pass `context.replica_id` to `lww_register.set`.
 * Equal-time callback results follow `set` conflict selection.
 */
export function update(map, key, timestamp, callback) {
  return $crdt.lww_update(map, key, timestamp, callback);
}

/**
 * Write a tombstone above the prune floor and at or after the existing write.
 *
 * At an equal timestamp, the tombstone wins even when the active assignment has
 * the same writer. A timestamp at or below the prune floor is rejected.
 *
 * ## Examples
 *
 * ```gleam
 * let map = lww_map.new(replica_id.new("A"), crdt.TextSpec)
 * let assert Ok(removed) = lww_map.remove(map, "body", 1)
 * lww_map.get(removed, "body") // -> Error(Nil)
 * ```
 */
export function remove(map, key, timestamp) {
  return $crdt.lww_remove(map, key, timestamp);
}

/**
 * Return active keys in unspecified order.
 *
 * ## Examples
 *
 * ```gleam
 * let map = lww_map.new(replica_id.new("A"), crdt.TextSpec)
 * lww_map.keys(map) // -> []
 * ```
 */
export function keys(map) {
  return $crdt.lww_keys(map);
}

/**
 * Return locally bound active children in unspecified order.
 *
 * ## Examples
 *
 * ```gleam
 * let map = lww_map.new(replica_id.new("A"), crdt.TextSpec)
 * lww_map.values(map) // -> []
 * ```
 */
export function values(map) {
  return $crdt.lww_values(map);
}

/**
 * Return the number of retained tombstones.
 *
 * ## Examples
 *
 * ```gleam
 * let map = lww_map.new(replica_id.new("A"), crdt.TextSpec)
 * let assert Ok(map) = lww_map.remove(map, "body", 1)
 * lww_map.tombstone_count(map) // -> 1
 * ```
 */
export function tombstone_count(map) {
  return $crdt.lww_tombstone_count(map);
}

/**
 * Return the stable timestamp floor.
 *
 * ## Examples
 *
 * ```gleam
 * let map = lww_map.new(replica_id.new("A"), crdt.TextSpec)
 * lww_map.prune(map, 10) |> lww_map.pruned_timestamp // -> 10
 * ```
 */
export function pruned_timestamp(map) {
  return $crdt.lww_pruned_timestamp(map);
}

/**
 * Prune stable tombstones, without compacting child states.
 *
 * Only advance the floor after every participating replica has observed the
 * covered writes and removals. Older remote-only entries can then be rejected.
 *
 * ## Examples
 *
 * ```gleam
 * let map = lww_map.new(replica_id.new("A"), crdt.TextSpec)
 * let assert Ok(map) = lww_map.remove(map, "body", 5)
 * // After all replicas have observed the removal at timestamp 5:
 * let pruned = lww_map.prune(map, 5)
 * lww_map.tombstone_count(pruned) // -> 0
 * lww_map.pruned_timestamp(pruned) // -> 5
 * ```
 */
export function prune(map, stable) {
  return $crdt.lww_prune(map, stable);
}

/**
 * Merge into an explicit receiving identity.
 *
 * The chosen assignment retains its historical writer. The receiving identity
 * applies to future writes and to bound query results.
 *
 * ## Examples
 *
 * ```gleam
 * let a = lww_map.new(replica_id.new("A"), crdt.TextSpec)
 * let b = lww_map.new(replica_id.new("B"), crdt.TextSpec)
 * let local = replica_id.new("C")
 * let assert Ok(merged) = lww_map.merge_as(a, b, local)
 * lww_map.replica_id(merged) // -> local
 * ```
 */
export function merge_as(a, b, replica) {
  return $crdt.lww_merge_as(a, b, replica);
}

/**
 * Merge atomic assignments using the left map's local identity.
 *
 * Child snapshots from competing assignments are never merged together.
 * At equal timestamps, tombstones win; otherwise modern writes use writer
 * identity and imported legacy writes use their original String tie keys.
 * Both comparisons use lexicographic UTF-8 byte order on both targets. Local
 * `set`, `update`, and `remove` use this same selection.
 *
 * ## Examples
 *
 * ```gleam
 * let a = lww_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(0))
 * let b = lww_map.new(replica_id.new("B"), crdt.LwwRegisterSpec(0))
 * let assert Ok(merged) = lww_map.merge(a, b)
 * lww_map.replica_id(merged) // -> replica_id.new("A")
 * ```
 */
export function merge(a, b) {
  return merge_as(a, b, replica_id(a));
}

/**
 * Encode a generic modern snapshot.
 *
 * The encoder also handles configured register defaults in recursive schemas.
 *
 * ## Examples
 *
 * ```gleam
 * let local = replica_id.new("A")
 * let map = lww_map.new(local, crdt.LwwRegisterSpec(0))
 * let child = crdt.CrdtLwwRegister(lww_register.new(42, 1, local))
 * let assert Ok(map) = lww_map.set(map, "answer", child, 1)
 * let encoded = lww_map.to_json_with(map, json.int) |> json.to_string
 * lww_map.from_json_with(encoded, decode.int) // -> Ok(map)
 * ```
 */
export function to_json_with(map, encode) {
  return $crdt.lww_to_json_with(map, encode);
}

/**
 * Encode a modern String-payload snapshot (version 3).
 *
 * ## Examples
 *
 * ```gleam
 * let map = lww_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(""))
 * let encoded = map |> lww_map.to_json |> json.to_string
 * lww_map.from_json(encoded) // -> Ok(map)
 * ```
 */
export function to_json(map) {
  return to_json_with(map, $json.string);
}

/**
 * Decode a generic snapshot, preserving historical writers and legacy provenance.
 *
 * Legacy scalar snapshots require `import_legacy`; they are not modern
 * replication messages.
 *
 * ## Examples
 *
 * ```gleam
 * let schema = crdt.OrMapSpec(crdt.LwwRegisterSpec(42))
 * let map = lww_map.new(replica_id.new("A"), schema)
 * let encoded = lww_map.to_json_with(map, json.int) |> json.to_string
 * let assert Ok(loaded) = lww_map.from_json_with(encoded, decode.int)
 * lww_map.spec(loaded) // -> schema
 * ```
 */
export function from_json_with(input, decoder) {
  return $crdt.lww_from_json_with(input, decoder);
}

/**
 * Decode a modern String snapshot.
 *
 * Bind the decoded map before making writes as a different replica.
 *
 * ## Examples
 *
 * ```gleam
 * let source = lww_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(""))
 * let encoded = source |> lww_map.to_json |> json.to_string
 * let assert Ok(loaded) = lww_map.from_json(encoded)
 * let local = lww_map.bind(loaded, replica_id.new("B"))
 * lww_map.replica_id(local) // -> replica_id.new("B")
 * ```
 */
export function from_json(input) {
  return from_json_with(input, $decode.string);
}

/**
 * Import old scalar String entries as LWWRegister children.
 *
 * Requires an explicit register schema/default. Original String tie keys are
 * persisted as legacy provenance and compared in lexicographic UTF-8 byte
 * order, without Unicode normalization. Import an agreed baseline before cutover.
 * Distribute the resulting modern snapshot before accepting modern writes;
 * importing old messages repeatedly is not a mixed-version replication scheme.
 *
 * ## Examples
 *
 * ```gleam
 * import gleam/result
 * import lattice_core/replica_id
 * import lattice_maps/crdt
 * import lattice_maps/lww_map
 *
 * pub fn migrate(legacy_snapshot: String) {
 *   use map <- result.try(lww_map.import_legacy(
 *     legacy_snapshot, crdt.LwwRegisterSpec(""),
 *     replica_id.new("cutover-writer"),
 *   ))
 *   Ok(lww_map.to_json(map))
 * }
 * ```
 */
export function import_legacy(input, spec, replica) {
  return $crdt.lww_import_legacy(input, spec, replica);
}
