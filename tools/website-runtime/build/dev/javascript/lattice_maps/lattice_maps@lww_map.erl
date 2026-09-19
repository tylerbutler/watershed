-module(lattice_maps@lww_map).
-compile([no_auto_import, nowarn_ignored, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-export([new/2, replica_id/1, spec/1, bind/2, get/2, set/4, update/4, remove/3, keys/1, values/1, tombstone_count/1, pruned_timestamp/1, prune/2, merge_as/3, merge/2, to_json_with/2, to_json/1, from_json_with/2, from_json/1, import_legacy/3]).
-moduledoc(~" Recursive last-writer-wins maps of atomic child snapshots.

 Greater timestamps win; ties select tombstones, then modern provenance,
 then writer identity in UTF-8 byte order. Equal modern write IDs cannot name
 different active payloads.
 Competing child snapshots are not merged. Use ORMap for collaborative edits.").

-file("src/lattice_maps/lww_map.gleam", 34).
-spec new(lattice_core@replica_id:replica_id(), lattice_maps@crdt:crdt_spec(MYZ)) -> lattice_maps@crdt:l_w_w_map(MYZ).
-doc(~" Create an empty map for the local writer.

 ## Examples

 ```gleam
 lww_map.new(replica_id.new(\"A\"), crdt.TextSpec)
 ```").
new(Replica, Spec) ->
    lattice_maps@crdt:lww_new(Replica, Spec).

-file("src/lattice_maps/lww_map.gleam", 47).
-spec replica_id(lattice_maps@crdt:l_w_w_map(any())) -> lattice_core@replica_id:replica_id().
-doc(~" Return the local writer identity.

 ## Examples

 ```gleam
 let local = replica_id.new(\"A\")
 let map = lww_map.new(local, crdt.TextSpec)
 lww_map.replica_id(map) // -> local
 ```").
replica_id(Map) ->
    lattice_maps@crdt:lww_replica(Map).

-file("src/lattice_maps/lww_map.gleam", 60).
-spec spec(lattice_maps@crdt:l_w_w_map(MZE)) -> lattice_maps@crdt:crdt_spec(MZE).
-doc(~" Return the complete child schema.

 ## Examples

 ```gleam
 let schema = crdt.OrMapSpec(crdt.LwwRegisterSpec(42))
 let map = lww_map.new(replica_id.new(\"A\"), schema)
 lww_map.spec(map) // -> schema
 ```").
spec(Map) ->
    lattice_maps@crdt:lww_spec(Map).

-file("src/lattice_maps/lww_map.gleam", 78).
-spec bind(lattice_maps@crdt:l_w_w_map(MZH), lattice_core@replica_id:replica_id()) -> lattice_maps@crdt:l_w_w_map(MZH).
-doc(~" Set the local writer without changing stored assignment payloads or authors.

 Queries return bound copies. Use `update` to prepare edits under the new
 assignment's identity, rather than editing under a historical writer.

 ## Examples

 ```gleam
 let source = lww_map.new(replica_id.new(\"A\"), crdt.LwwRegisterSpec(\"\"))
 let snapshot = source |> lww_map.to_json |> json.to_string
 let assert Ok(loaded) = lww_map.from_json(snapshot)
 let local = lww_map.bind(loaded, replica_id.new(\"B\"))
 lww_map.replica_id(local) // -> replica_id.new(\"B\")
 ```").
bind(Map, Replica) ->
    lattice_maps@crdt:lww_bind(Map, Replica).

-file("src/lattice_maps/lww_map.gleam", 94).
-spec get(lattice_maps@crdt:l_w_w_map(MZK), binary()) -> {ok, lattice_maps@crdt:crdt(MZK)} | {error, nil}.
-doc(~" Get a locally bound copy of an active child, without modifying its assignment.

 ## Examples

 ```gleam
 let local = replica_id.new(\"A\")
 let map = lww_map.new(local, crdt.LwwRegisterSpec(\"\"))
 let child = crdt.CrdtLwwRegister(lww_register.new(\"Ready\", 1, local))
 let assert Ok(map) = lww_map.set(map, \"status\", child, 1)
 let assert Ok(crdt.CrdtLwwRegister(status)) = lww_map.get(map, \"status\")
 lww_register.value(status) // -> \"Ready\"
 ```").
get(Map, Key) ->
    lattice_maps@crdt:lww_get(Map, Key).

-file("src/lattice_maps/lww_map.gleam", 119).
-spec set(lattice_maps@crdt:l_w_w_map(MZP), binary(), lattice_maps@crdt:crdt(MZP), integer()) -> {ok, lattice_maps@crdt:l_w_w_map(MZP)} | {error, lattice_maps@crdt:merge_error()}.
-doc(~" Assign a complete immutable child snapshot.

 For Sequence/Text edits or fresh replacements, prefer `update` and its new
 assignment context to prevent allocation-ID reuse.

 The timestamp must not precede the key's timestamp and must exceed the prune
 floor. An equal-time assignment uses the same tombstone, provenance, and
 writer order as `merge`; generic child payloads are never compared. Reusing
 one modern timestamp/writer for different active children returns
 `ConflictingWrite`.

 ## Examples

 ```gleam
 let local = replica_id.new(\"A\")
 let map = lww_map.new(local, crdt.LwwRegisterSpec(0))
 let child = crdt.CrdtLwwRegister(lww_register.new(42, 1, local))
 let assert Ok(map) = lww_map.set(map, \"answer\", child, 1)
 lww_map.set(map, \"answer\", child, 1)
 // -> Ok(map)
 ```").
set(Map, Key, Value, Timestamp) ->
    lattice_maps@crdt:lww_set(Map, Key, Value, Timestamp).

-file("src/lattice_maps/lww_map.gleam", 174).
-spec update(lattice_maps@crdt:l_w_w_map(MZV), binary(), integer(), fun((lattice_maps@crdt:crdt(MZV), lattice_maps@crdt:edit_context()) -> {ok, lattice_maps@crdt:crdt(MZV)} | {error, MZZ})) -> {ok, lattice_maps@crdt:l_w_w_map(MZV)} | {error, lattice_maps@crdt:update_error(MZZ)}.
-doc(~" Edit once under the new assignment's namespace, then atomically assign.

 To replace a child from empty, construct its default with `context.replica_id`.
 Inherited historical IDs remain intact. Failures leave the map unchanged.
 Do not use a fixed replica ID to construct a replacement Sequence or Text:
 each accepted assignment needs its own allocation namespace.

 ## Examples

 Replace Text from empty on each write, using the new assignment's context:

 ```gleam
 import gleam/result
 import lattice_text/text

 let map: lww_map.LWWMap(String) =
   lww_map.new(replica_id.new(\"A\"), crdt.TextSpec)
 let replace = fn(_, context: crdt.EditContext) {
   text.append(text.new(context.replica_id), \"Replacement\")
   |> result.map(crdt.CrdtText)
 }
 let assert Ok(first) = lww_map.update(map, \"body\", 1, replace)
 let assert Ok(second) = lww_map.update(first, \"body\", 2, replace)
 let assert Ok(crdt.CrdtText(body)) = lww_map.get(second, \"body\")
 text.value(body) // -> \"Replacement\"
 ```

 The same pattern gives a generic Sequence fresh item identities:

 ```gleam
 import gleam/result
 import lattice_sequence/sequence

 let map: lww_map.LWWMap(Int) =
   lww_map.new(replica_id.new(\"A\"), crdt.SequenceSpec)
 let assert Ok(map) = lww_map.update(map, \"items\", 1, fn(_, context) {
   sequence.insert_many(sequence.new(context.replica_id), 0, [10, 20])
   |> result.map(crdt.CrdtSequence)
 })
 let assert Ok(crdt.CrdtSequence(items)) = lww_map.get(map, \"items\")
 sequence.values(items) // -> [10, 20]
 ```

 To edit an existing child instead, use the callback's first argument. For an
 LWWRegister, also pass `context.replica_id` to `lww_register.set`.
 Equal-time callback results follow `set` conflict selection.").
update(Map, Key, Timestamp, Callback) ->
    lattice_maps@crdt:lww_update(Map, Key, Timestamp, Callback).

-file("src/lattice_maps/lww_map.gleam", 195).
-spec remove(lattice_maps@crdt:l_w_w_map(NAG), binary(), integer()) -> {ok, lattice_maps@crdt:l_w_w_map(NAG)} | {error, lattice_maps@crdt:merge_error()}.
-doc(~" Write a tombstone above the prune floor and at or after the existing write.

 At an equal timestamp, the tombstone wins even when the active assignment has
 the same writer. A timestamp at or below the prune floor is rejected.

 ## Examples

 ```gleam
 let map = lww_map.new(replica_id.new(\"A\"), crdt.TextSpec)
 let assert Ok(removed) = lww_map.remove(map, \"body\", 1)
 lww_map.get(removed, \"body\") // -> Error(Nil)
 ```").
remove(Map, Key, Timestamp) ->
    lattice_maps@crdt:lww_remove(Map, Key, Timestamp).

-file("src/lattice_maps/lww_map.gleam", 211).
-spec keys(lattice_maps@crdt:l_w_w_map(any())) -> list(binary()).
-doc(~" Return active keys in unspecified order.

 ## Examples

 ```gleam
 let map = lww_map.new(replica_id.new(\"A\"), crdt.TextSpec)
 lww_map.keys(map) // -> []
 ```").
keys(Map) ->
    lattice_maps@crdt:lww_keys(Map).

-file("src/lattice_maps/lww_map.gleam", 223).
-spec values(lattice_maps@crdt:l_w_w_map(NAO)) -> list(lattice_maps@crdt:crdt(NAO)).
-doc(~" Return locally bound active children in unspecified order.

 ## Examples

 ```gleam
 let map = lww_map.new(replica_id.new(\"A\"), crdt.TextSpec)
 lww_map.values(map) // -> []
 ```").
values(Map) ->
    lattice_maps@crdt:lww_values(Map).

-file("src/lattice_maps/lww_map.gleam", 236).
-spec tombstone_count(lattice_maps@crdt:l_w_w_map(any())) -> integer().
-doc(~" Return the number of retained tombstones.

 ## Examples

 ```gleam
 let map = lww_map.new(replica_id.new(\"A\"), crdt.TextSpec)
 let assert Ok(map) = lww_map.remove(map, \"body\", 1)
 lww_map.tombstone_count(map) // -> 1
 ```").
tombstone_count(Map) ->
    lattice_maps@crdt:lww_tombstone_count(Map).

-file("src/lattice_maps/lww_map.gleam", 248).
-spec pruned_timestamp(lattice_maps@crdt:l_w_w_map(any())) -> integer().
-doc(~" Return the stable timestamp floor.

 ## Examples

 ```gleam
 let map = lww_map.new(replica_id.new(\"A\"), crdt.TextSpec)
 lww_map.prune(map, 10) |> lww_map.pruned_timestamp // -> 10
 ```").
pruned_timestamp(Map) ->
    lattice_maps@crdt:lww_pruned_timestamp(Map).

-file("src/lattice_maps/lww_map.gleam", 267).
-spec prune(lattice_maps@crdt:l_w_w_map(NAW), integer()) -> lattice_maps@crdt:l_w_w_map(NAW).
-doc(~" Prune stable tombstones, without compacting child states.

 Only advance the floor after every participating replica has observed the
 covered writes and removals. Older remote-only entries can then be rejected.

 ## Examples

 ```gleam
 let map = lww_map.new(replica_id.new(\"A\"), crdt.TextSpec)
 let assert Ok(map) = lww_map.remove(map, \"body\", 5)
 // After all replicas have observed the removal at timestamp 5:
 let pruned = lww_map.prune(map, 5)
 lww_map.tombstone_count(pruned) // -> 0
 lww_map.pruned_timestamp(pruned) // -> 5
 ```").
prune(Map, Stable) ->
    lattice_maps@crdt:lww_prune(Map, Stable).

-file("src/lattice_maps/lww_map.gleam", 305).
-spec merge_as(lattice_maps@crdt:l_w_w_map(NBF), lattice_maps@crdt:l_w_w_map(NBF), lattice_core@replica_id:replica_id()) -> {ok, lattice_maps@crdt:l_w_w_map(NBF)} | {error, lattice_maps@crdt:merge_error()}.
-doc(~" Merge into an explicit receiving identity.

 The chosen assignment retains its historical writer. The receiving identity
 applies to future writes and to bound query results.

 ## Examples

 ```gleam
 let a = lww_map.new(replica_id.new(\"A\"), crdt.TextSpec)
 let b = lww_map.new(replica_id.new(\"B\"), crdt.TextSpec)
 let local = replica_id.new(\"C\")
 let assert Ok(merged) = lww_map.merge_as(a, b, local)
 lww_map.replica_id(merged) // -> local
 ```").
merge_as(A, B, Replica) ->
    lattice_maps@crdt:lww_merge_as(A, B, Replica).

-file("src/lattice_maps/lww_map.gleam", 287).
-spec merge(lattice_maps@crdt:l_w_w_map(NAZ), lattice_maps@crdt:l_w_w_map(NAZ)) -> {ok, lattice_maps@crdt:l_w_w_map(NAZ)} | {error, lattice_maps@crdt:merge_error()}.
-doc(~" Merge atomic assignments using the left map's local identity.

 Child snapshots from competing assignments are never merged together.
 At equal timestamps, tombstones win; otherwise modern writes use writer
 identity and imported legacy writes use their original String tie keys.
 Both comparisons use lexicographic UTF-8 byte order on both targets. Local
 `set`, `update`, and `remove` use this same selection.

 ## Examples

 ```gleam
 let a = lww_map.new(replica_id.new(\"A\"), crdt.LwwRegisterSpec(0))
 let b = lww_map.new(replica_id.new(\"B\"), crdt.LwwRegisterSpec(0))
 let assert Ok(merged) = lww_map.merge(a, b)
 lww_map.replica_id(merged) // -> replica_id.new(\"A\")
 ```").
merge(A, B) ->
    merge_as(A, B, replica_id(A)).

-file("src/lattice_maps/lww_map.gleam", 340).
-spec to_json_with(lattice_maps@crdt:l_w_w_map(NBM), fun((NBM) -> gleam@json:json())) -> gleam@json:json().
-doc(~" Encode a generic modern snapshot.

 The encoder also handles configured register defaults in recursive schemas.

 ## Examples

 ```gleam
 let local = replica_id.new(\"A\")
 let map = lww_map.new(local, crdt.LwwRegisterSpec(0))
 let child = crdt.CrdtLwwRegister(lww_register.new(42, 1, local))
 let assert Ok(map) = lww_map.set(map, \"answer\", child, 1)
 let encoded = lww_map.to_json_with(map, json.int) |> json.to_string
 lww_map.from_json_with(encoded, decode.int) // -> Ok(map)
 ```").
to_json_with(Map, Encode) ->
    lattice_maps@crdt:lww_to_json_with(Map, Encode).

-file("src/lattice_maps/lww_map.gleam", 322).
-spec to_json(lattice_maps@crdt:l_w_w_map(binary())) -> gleam@json:json().
-doc(~" Encode a modern String-payload snapshot (version 3).

 ## Examples

 ```gleam
 let map = lww_map.new(replica_id.new(\"A\"), crdt.LwwRegisterSpec(\"\"))
 let encoded = map |> lww_map.to_json |> json.to_string
 lww_map.from_json(encoded) // -> Ok(map)
 ```").
to_json(Map) ->
    to_json_with(Map, fun gleam@json:string/1).

-file("src/lattice_maps/lww_map.gleam", 375).
-spec from_json_with(binary(), gleam@dynamic@decode:decoder(NBR)) -> {ok, lattice_maps@crdt:l_w_w_map(NBR)} | {error, gleam@json:decode_error()}.
-doc(~" Decode a generic snapshot, preserving historical writers and legacy provenance.

 Legacy scalar snapshots require `import_legacy`; they are not modern
 replication messages.

 ## Examples

 ```gleam
 let schema = crdt.OrMapSpec(crdt.LwwRegisterSpec(42))
 let map = lww_map.new(replica_id.new(\"A\"), schema)
 let encoded = lww_map.to_json_with(map, json.int) |> json.to_string
 let assert Ok(loaded) = lww_map.from_json_with(encoded, decode.int)
 lww_map.spec(loaded) // -> schema
 ```").
from_json_with(Input, Decoder) ->
    lattice_maps@crdt:lww_from_json_with(Input, Decoder).

-file("src/lattice_maps/lww_map.gleam", 357).
-spec from_json(binary()) -> {ok, lattice_maps@crdt:l_w_w_map(binary())} | {error, gleam@json:decode_error()}.
-doc(~" Decode a modern String snapshot.

 Bind the decoded map before making writes as a different replica.

 ## Examples

 ```gleam
 let source = lww_map.new(replica_id.new(\"A\"), crdt.LwwRegisterSpec(\"\"))
 let encoded = source |> lww_map.to_json |> json.to_string
 let assert Ok(loaded) = lww_map.from_json(encoded)
 let local = lww_map.bind(loaded, replica_id.new(\"B\"))
 lww_map.replica_id(local) // -> replica_id.new(\"B\")
 ```").
from_json(Input) ->
    from_json_with(Input, {decoder, fun gleam@dynamic@decode:decode_string/1}).

-file("src/lattice_maps/lww_map.gleam", 406).
-spec import_legacy(binary(), lattice_maps@crdt:crdt_spec(binary()), lattice_core@replica_id:replica_id()) -> {ok, lattice_maps@crdt:l_w_w_map(binary())} | {error, gleam@json:decode_error()}.
-doc(~" Import old scalar String entries as LWWRegister children.

 Requires an explicit register schema/default. Original String tie keys are
 persisted as legacy provenance and compared in lexicographic UTF-8 byte
 order, without Unicode normalization. Import an agreed baseline before cutover.
 Distribute the resulting modern snapshot before accepting modern writes;
 importing old messages repeatedly is not a mixed-version replication scheme.

 ## Examples

 ```gleam
 import gleam/result
 import lattice_core/replica_id
 import lattice_maps/crdt
 import lattice_maps/lww_map

 pub fn migrate(legacy_snapshot: String) {
   use map <- result.try(lww_map.import_legacy(
     legacy_snapshot, crdt.LwwRegisterSpec(\"\"),
     replica_id.new(\"cutover-writer\"),
   ))
   Ok(lww_map.to_json(map))
 }
 ```").
import_legacy(Input, Spec, Replica) ->
    lattice_maps@crdt:lww_import_legacy(Input, Spec, Replica).

