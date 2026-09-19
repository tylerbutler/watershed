-module(lattice_maps@or_map).
-compile([no_auto_import, nowarn_ignored, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-export([new/2, replica_id/1, spec/1, bind/2, get/2, keys/1, values/1, update_with_delta/3, update/3, update_delta/3, remove_with_delta/2, remove/2, merge_as/3, merge/2, empty_delta/1, apply_delta/2, merge_deltas/2, prune/2, internal_value_count/1, to_json/1, to_json_with/2, from_json_with/2, from_json/1, delta_to_json_with/2, delta_to_json/1, delta_from_json_with/2, delta_from_json/1, import_legacy/4]).
-moduledoc(~" Generation-aware observed-remove maps.

 Concurrent updates join in one generation, with add-wins membership.
 Updating after an observed removal creates a fresh generation. The newest
 generation wins, even if it is removed; older values cannot return.
 Sparse synchronization needs a baseline or eventual delivery of all required
 deltas. An isolated later Sequence delta can temporarily have missing origins.").

-file("src/lattice_maps/or_map.gleam", 50).
-spec new(lattice_core@replica_id:replica_id(), lattice_maps@crdt:crdt_spec(NDA)) -> lattice_maps@crdt:o_r_map(NDA).
-doc(~" Create an empty map.

 ## Examples

 ```gleam
 or_map.new(replica_id.new(\"A\"), crdt.OrMapSpec(crdt.TextSpec))
 ```").
new(Replica, Spec) ->
    lattice_maps@crdt:or_new(Replica, Spec).

-file("src/lattice_maps/or_map.gleam", 63).
-spec replica_id(lattice_maps@crdt:o_r_map(any())) -> lattice_core@replica_id:replica_id().
-doc(~" Return the local editing identity.

 ## Examples

 ```gleam
 let local = replica_id.new(\"A\")
 let map = or_map.new(local, crdt.TextSpec)
 or_map.replica_id(map) // -> local
 ```").
replica_id(Map) ->
    lattice_maps@crdt:or_replica(Map).

-file("src/lattice_maps/or_map.gleam", 76).
-spec spec(lattice_maps@crdt:o_r_map(NDF)) -> lattice_maps@crdt:crdt_spec(NDF).
-doc(~" Return the complete child schema.

 ## Examples

 ```gleam
 let schema = crdt.OrMapSpec(crdt.LwwRegisterSpec(42))
 let map = or_map.new(replica_id.new(\"A\"), schema)
 or_map.spec(map) // -> schema
 ```").
spec(Map) ->
    lattice_maps@crdt:or_spec(Map).

-file("src/lattice_maps/or_map.gleam", 94).
-spec bind(lattice_maps@crdt:o_r_map(NDI), lattice_core@replica_id:replica_id()) -> lattice_maps@crdt:o_r_map(NDI).
-doc(~" Bind a loaded or received map to the local writer without rewriting history.

 Child callbacks receive identities scoped by key and generation. Keep each
 independent writer's logical replica ID distinct.

 ## Examples

 ```gleam
 let source = or_map.new(replica_id.new(\"A\"), crdt.LwwRegisterSpec(\"\"))
 let snapshot = source |> or_map.to_json |> json.to_string
 let assert Ok(loaded) = or_map.from_json(snapshot)
 let local = or_map.bind(loaded, replica_id.new(\"B\"))
 or_map.replica_id(local) // -> replica_id.new(\"B\")
 ```").
bind(Map, Replica) ->
    lattice_maps@crdt:or_bind(Map, Replica).

-file("src/lattice_maps/or_map.gleam", 108).
-spec get(lattice_maps@crdt:o_r_map(NDL), binary()) -> {ok, lattice_maps@crdt:crdt(NDL)} | {error, nil}.
-doc(~" Get an active child bound to this map's local editing scope.

 ## Examples

 ```gleam
 let map = or_map.new(replica_id.new(\"A\"), crdt.GCounterSpec)
 let assert Ok(map) = or_map.update(map, \"score\", fn(value) { value })
 let assert Ok(crdt.CrdtGCounter(counter)) = or_map.get(map, \"score\")
 g_counter.value(counter) // -> 0
 ```").
get(Map, Key) ->
    lattice_maps@crdt:or_get(Map, Key).

-file("src/lattice_maps/or_map.gleam", 121).
-spec keys(lattice_maps@crdt:o_r_map(any())) -> list(binary()).
-doc(~" Return active keys, in unspecified order.

 ## Examples

 ```gleam
 let map = or_map.new(replica_id.new(\"A\"), crdt.TextSpec)
 let assert Ok(map) = or_map.update(map, \"body\", fn(value) { value })
 or_map.keys(map) // -> [\"body\"]
 ```").
keys(Map) ->
    lattice_maps@crdt:or_keys(Map).

-file("src/lattice_maps/or_map.gleam", 133).
-spec values(lattice_maps@crdt:o_r_map(NDT)) -> list(lattice_maps@crdt:crdt(NDT)).
-doc(~" Return active, locally bound children, in unspecified order.

 ## Examples

 ```gleam
 let map = or_map.new(replica_id.new(\"A\"), crdt.TextSpec)
 or_map.values(map) // -> []
 ```").
values(Map) ->
    lattice_maps@crdt:or_values(Map).

-file("src/lattice_maps/or_map.gleam", 177).
-spec update_with_delta(lattice_maps@crdt:o_r_map(NEE), binary(), fun((lattice_maps@crdt:crdt(NEE)) -> lattice_maps@crdt:crdt(NEE))) -> {ok, {lattice_maps@crdt:o_r_map(NEE), lattice_maps@crdt:o_r_map_delta(NEE)}} | {error, lattice_maps@crdt:merge_error()}.
-doc(~" Run a full-value callback once and return the touched-key state delta.

 The delta carries the complete returned child state. For large Sequence/Text
 children, use `update_delta` instead.

 ## Examples

 ```gleam
 let map = or_map.new(replica_id.new(\"A\"), crdt.GSetSpec)
 let assert Ok(#(updated, delta)) =
   or_map.update_with_delta(map, \"tags\", fn(value) {
     let assert crdt.CrdtGSet(tags) = value
     crdt.CrdtGSet(g_set.add(tags, \"ready\"))
   })
 or_map.apply_delta(map, delta) // -> Ok(updated)
 ```").
update_with_delta(Map, Key, Callback) ->
    lattice_maps@crdt:or_update_with_delta(Map, Key, Callback).

-file("src/lattice_maps/or_map.gleam", 153).
-spec update(lattice_maps@crdt:o_r_map(NDX), binary(), fun((lattice_maps@crdt:crdt(NDX)) -> lattice_maps@crdt:crdt(NDX))) -> {ok, lattice_maps@crdt:o_r_map(NDX)} | {error, lattice_maps@crdt:merge_error()}.
-doc(~" Join the callback's full child state within the current generation.

 Removal/re-add, rather than a non-monotone callback, resets a child.
 Use `update_delta` when a leaf operation can return a sparse delta, or when
 a new LWWRegister write needs the callback's explicit author identity.

 ## Examples

 ```gleam
 let map = or_map.new(replica_id.new(\"A\"), crdt.GSetSpec)
 let assert Ok(map) = or_map.update(map, \"tags\", fn(value) {
   let assert crdt.CrdtGSet(tags) = value
   crdt.CrdtGSet(g_set.add(tags, \"reviewed\"))
 })
 or_map.keys(map) // -> [\"tags\"]
 ```").
update(Map, Key, Callback) ->
    _pipe = update_with_delta(Map, Key, Callback),
    gleam@result:map(_pipe, fun(Pair) ->
        erlang:element(1, Pair)
    end).

-file("src/lattice_maps/or_map.gleam", 233).
-spec update_delta(lattice_maps@crdt:o_r_map(NEM), binary(), fun((lattice_maps@crdt:crdt(NEM), lattice_maps@crdt:edit_context()) -> {ok, lattice_maps@crdt:crdt_delta(NEM)} | {error, NEQ})) -> {ok, {lattice_maps@crdt:o_r_map(NEM), lattice_maps@crdt:o_r_map_delta(NEM)}} | {error, lattice_maps@crdt:update_error(NEQ)}.
-doc(~" Run a sparse callback once, apply its delta, and return the resulting map/change.

 Errors are atomic. `NoChange` still refreshes membership, so it is an
 add-wins update. The callback context supplies the scoped author for new
 LWWRegister writes. Nested maps return `crdt.OrMapChange(child_delta)`.

 ## Examples

 Author a register write with the supplied scope, not the old write's author:

 ```gleam
 import lattice_registers/lww_register

 let map = or_map.new(replica_id.new(\"A\"), crdt.LwwRegisterSpec(\"\"))
 let assert Ok(#(updated, delta)) =
   or_map.update_delta(map, \"title\", fn(value, context) {
     let assert crdt.CrdtLwwRegister(register) = value
     let #(_, change) = lww_register.set_with_delta(
       register, \"New title\", lww_register.timestamp(register) + 1,
       context.replica_id,
     )
     Ok(crdt.StateDelta(crdt.CrdtLwwRegister(change)))
   })
 or_map.apply_delta(map, delta) // -> Ok(updated)
 ```

 Keep an inner ORMap change sparse through the outer map:

 ```gleam
 import gleam/result
 import lattice_text/text

 let map: or_map.ORMap(String) =
   or_map.new(replica_id.new(\"A\"), crdt.OrMapSpec(crdt.TextSpec))
 let assert Ok(#(updated, delta)) =
   or_map.update_delta(map, \"document\", fn(value, _) {
     let assert crdt.CrdtOrMap(document) = value
     use #(_, change) <- result.try(
       or_map.update_delta(document, \"body\", fn(value, _) {
         let assert crdt.CrdtText(body) = value
         use #(_, change) <- result.try(text.append_with_delta(body, \"Hello\"))
         Ok(crdt.StateDelta(crdt.CrdtText(change)))
       }),
     )
     Ok(crdt.OrMapChange(change))
   })
 or_map.apply_delta(map, delta) // -> Ok(updated)
 ```").
update_delta(Map, Key, Callback) ->
    lattice_maps@crdt:or_update_delta(Map, Key, Callback).

-file("src/lattice_maps/or_map.gleam", 264).
-spec remove_with_delta(lattice_maps@crdt:o_r_map(NFB), binary()) -> {lattice_maps@crdt:o_r_map(NFB), lattice_maps@crdt:o_r_map_delta(NFB)}.
-doc(~" Remove observed membership and return a generation-bearing removal delta.

 ## Examples

 ```gleam
 let map = or_map.new(replica_id.new(\"A\"), crdt.TextSpec)
 let assert Ok(map) = or_map.update(map, \"body\", fn(value) { value })
 let #(removed, delta) = or_map.remove_with_delta(map, \"body\")
 or_map.apply_delta(map, delta) // -> Ok(removed)
 ```").
remove_with_delta(Map, Key) ->
    lattice_maps@crdt:or_remove_with_delta(Map, Key).

-file("src/lattice_maps/or_map.gleam", 250).
-spec remove(lattice_maps@crdt:o_r_map(NEY), binary()) -> lattice_maps@crdt:o_r_map(NEY).
-doc(~" Remove observed membership; keep current-generation child history.

 ## Examples

 ```gleam
 let map = or_map.new(replica_id.new(\"A\"), crdt.TextSpec)
 let assert Ok(map) = or_map.update(map, \"body\", fn(value) { value })
 or_map.remove(map, \"body\") |> or_map.get(\"body\") // -> Error(Nil)
 ```").
remove(Map, Key) ->
    erlang:element(1, remove_with_delta(Map, Key)).

-file("src/lattice_maps/or_map.gleam", 296).
-spec merge_as(lattice_maps@crdt:o_r_map(NFL), lattice_maps@crdt:o_r_map(NFL), lattice_core@replica_id:replica_id()) -> {ok, lattice_maps@crdt:o_r_map(NFL)} | {error, lattice_maps@crdt:merge_error()}.
-doc(~" Merge into an explicit receiving identity, including remote-only children.

 ## Examples

 ```gleam
 let a = or_map.new(replica_id.new(\"A\"), crdt.SequenceSpec)
 let b = or_map.new(replica_id.new(\"B\"), crdt.SequenceSpec)
 let local = replica_id.new(\"C\")
 let assert Ok(merged) = or_map.merge_as(a, b, local)
 or_map.replica_id(merged) // -> local
 ```").
merge_as(A, B, Replica) ->
    lattice_maps@crdt:or_merge_as(A, B, Replica).

-file("src/lattice_maps/or_map.gleam", 281).
-spec merge(lattice_maps@crdt:o_r_map(NFF), lattice_maps@crdt:o_r_map(NFF)) -> {ok, lattice_maps@crdt:o_r_map(NFF)} | {error, lattice_maps@crdt:merge_error()}.
-doc(~" Merge into the left map's local identity.

 ## Examples

 ```gleam
 let a = or_map.new(replica_id.new(\"A\"), crdt.GCounterSpec)
 let b = or_map.new(replica_id.new(\"B\"), crdt.GCounterSpec)
 let assert Ok(merged) = or_map.merge(a, b)
 or_map.replica_id(merged) // -> replica_id.new(\"A\")
 ```").
merge(A, B) ->
    merge_as(A, B, replica_id(A)).

-file("src/lattice_maps/or_map.gleam", 312).
-spec empty_delta(lattice_maps@crdt:o_r_map(NFR)) -> lattice_maps@crdt:o_r_map_delta(NFR).
-doc(~" Return an empty transport batch.

 ## Examples

 ```gleam
 let map = or_map.new(replica_id.new(\"A\"), crdt.TextSpec)
 or_map.apply_delta(map, or_map.empty_delta(map)) // -> Ok(map)
 ```").
empty_delta(Map) ->
    lattice_maps@crdt:or_empty_delta(Map).

-file("src/lattice_maps/or_map.gleam", 331).
-spec apply_delta(lattice_maps@crdt:o_r_map(NFU), lattice_maps@crdt:o_r_map_delta(NFU)) -> {ok, lattice_maps@crdt:o_r_map(NFU)} | {error, lattice_maps@crdt:merge_error()}.
-doc(~" Apply only touched keys, selecting generations before child changes.

 Missing Sequence origins can produce an incomplete view until the required
 baseline or earlier deltas arrive. Bind the receiving map before editing it.

 ## Examples

 ```gleam
 let source = or_map.new(replica_id.new(\"A\"), crdt.GCounterSpec)
 let assert Ok(#(_, delta)) =
   or_map.update_with_delta(source, \"score\", fn(value) { value })
 let receiver = or_map.new(replica_id.new(\"B\"), crdt.GCounterSpec)
 let assert Ok(receiver) = or_map.apply_delta(receiver, delta)
 or_map.keys(receiver) // -> [\"score\"]
 ```").
apply_delta(Map, Delta) ->
    lattice_maps@crdt:or_apply_delta(Map, Delta).

-file("src/lattice_maps/or_map.gleam", 351).
-spec merge_deltas(lattice_maps@crdt:o_r_map_delta(NGA), lattice_maps@crdt:o_r_map_delta(NGA)) -> {ok, lattice_maps@crdt:o_r_map_delta(NGA)} | {error, lattice_maps@crdt:merge_error()}.
-doc(~" Combine sparse changes without turning nested deltas into snapshots.

 ## Examples

 ```gleam
 let map = or_map.new(replica_id.new(\"A\"), crdt.TextSpec)
 let assert Ok(#(first, a)) =
   or_map.update_with_delta(map, \"first\", fn(value) { value })
 let assert Ok(#(updated, b)) =
   or_map.update_with_delta(first, \"second\", fn(value) { value })
 let assert Ok(batch) = or_map.merge_deltas(a, b)
 or_map.apply_delta(map, batch) // -> Ok(updated)
 ```").
merge_deltas(A, B) ->
    lattice_maps@crdt:or_merge_deltas(A, B).

-file("src/lattice_maps/or_map.gleam", 371).
-spec prune(lattice_maps@crdt:o_r_map(NGG), lattice_core@version_vector:version_vector()) -> lattice_maps@crdt:o_r_map(NGG).
-doc(~" Prune stable membership tombstones, but retain floors and current leaf history.

 Outer stability never compacts inner Sequence/Text history or forwardings.
 The vector must cover the namespaced membership tags in map deltas, not the
 logical writer's unrelated leaf clocks. Each key/generation is a causal scope.

 ## Examples

 ```gleam
 let map = or_map.new(replica_id.new(\"A\"), crdt.TextSpec)
 // An empty frontier makes no events stable.
 or_map.prune(map, version_vector.new()) // -> map
 ```").
prune(Map, Stable) ->
    lattice_maps@crdt:or_prune(Map, Stable).

-file("src/lattice_maps/or_map.gleam", 376).
-spec internal_value_count(lattice_maps@crdt:o_r_map(any())) -> integer().
-doc(false).
internal_value_count(Map) ->
    lattice_maps@crdt:or_value_count(Map).

-file("src/lattice_maps/or_map.gleam", 389).
-spec to_json(lattice_maps@crdt:o_r_map(binary())) -> gleam@json:json().
-doc(~" Encode a String-payload modern snapshot (version 3).

 ## Examples

 ```gleam
 let map = or_map.new(replica_id.new(\"A\"), crdt.LwwRegisterSpec(\"\"))
 let encoded = map |> or_map.to_json |> json.to_string
 or_map.from_json(encoded) // -> Ok(map)
 ```").
to_json(Map) ->
    lattice_maps@crdt:or_to_json_with(Map, fun gleam@json:string/1).

-file("src/lattice_maps/or_map.gleam", 407).
-spec to_json_with(lattice_maps@crdt:o_r_map(NGM), fun((NGM) -> gleam@json:json())) -> gleam@json:json().
-doc(~" Encode a generic modern snapshot.

 The encoder handles payloads and configured register defaults at every depth.
 Text remains a concrete String/grapheme type.

 ## Examples

 ```gleam
 let map = or_map.new(
   replica_id.new(\"A\"), crdt.OrMapSpec(crdt.LwwRegisterSpec(42)),
 )
 let encoded = or_map.to_json_with(map, json.int) |> json.to_string
 or_map.from_json_with(encoded, decode.int) // -> Ok(map)
 ```").
to_json_with(Map, Encode) ->
    lattice_maps@crdt:or_to_json_with(Map, Encode).

-file("src/lattice_maps/or_map.gleam", 438).
-spec from_json_with(binary(), gleam@dynamic@decode:decoder(NGR)) -> {ok, lattice_maps@crdt:o_r_map(NGR)} | {error, gleam@json:decode_error()}.
-doc(~" Decode a generic modern snapshot, including recursive configured defaults.

 Legacy map snapshots require `import_legacy` instead.

 ## Examples

 ```gleam
 let map = or_map.new(replica_id.new(\"A\"), crdt.LwwRegisterSpec(42))
 let encoded = or_map.to_json_with(map, json.int) |> json.to_string
 let assert Ok(loaded) = or_map.from_json_with(encoded, decode.int)
 or_map.spec(loaded) // -> crdt.LwwRegisterSpec(42)
 ```").
from_json_with(Input, Decoder) ->
    lattice_maps@crdt:or_from_json_with(Input, Decoder).

-file("src/lattice_maps/or_map.gleam", 422).
-spec from_json(binary()) -> {ok, lattice_maps@crdt:o_r_map(binary())} | {error, gleam@json:decode_error()}.
-doc(~" Decode a modern String snapshot. Call `bind` before editing as another writer.

 ## Examples

 ```gleam
 let source = or_map.new(replica_id.new(\"A\"), crdt.LwwRegisterSpec(\"\"))
 let encoded = source |> or_map.to_json |> json.to_string
 let assert Ok(loaded) = or_map.from_json(encoded)
 let local = or_map.bind(loaded, replica_id.new(\"B\"))
 or_map.replica_id(local) // -> replica_id.new(\"B\")
 ```").
from_json(Input) ->
    from_json_with(Input, {decoder, fun gleam@dynamic@decode:decode_string/1}).

-file("src/lattice_maps/or_map.gleam", 471).
-spec delta_to_json_with(lattice_maps@crdt:o_r_map_delta(NGX), fun((NGX) -> gleam@json:json())) -> gleam@json:json().
-doc(~" Encode a generic sparse delta.

 ## Examples

 ```gleam
 let map = or_map.new(replica_id.new(\"A\"), crdt.LwwRegisterSpec(42))
 let assert Ok(#(_, delta)) = or_map.update_delta(map, \"answer\", fn(_, _) {
   Ok(crdt.NoChange(crdt.LwwRegisterSpec(42)))
 })
 let encoded = or_map.delta_to_json_with(delta, json.int) |> json.to_string
 or_map.delta_from_json_with(encoded, decode.int) // -> Ok(delta)
 ```").
delta_to_json_with(Delta, Encode) ->
    lattice_maps@crdt:or_delta_to_json_with(Delta, Encode).

-file("src/lattice_maps/or_map.gleam", 455).
-spec delta_to_json(lattice_maps@crdt:o_r_map_delta(binary())) -> gleam@json:json().
-doc(~" Encode a String-payload sparse delta (version 2).

 ## Examples

 ```gleam
 let map = or_map.new(replica_id.new(\"A\"), crdt.LwwRegisterSpec(\"\"))
 let delta = or_map.empty_delta(map)
 let encoded = delta |> or_map.delta_to_json |> json.to_string
 or_map.delta_from_json(encoded) // -> Ok(delta)
 ```").
delta_to_json(Delta) ->
    delta_to_json_with(Delta, fun gleam@json:string/1).

-file("src/lattice_maps/or_map.gleam", 503).
-spec delta_from_json_with(binary(), gleam@dynamic@decode:decoder(NHC)) -> {ok, lattice_maps@crdt:o_r_map_delta(NHC)} | {error, gleam@json:decode_error()}.
-doc(~" Decode a generic sparse delta.

 ## Examples

 ```gleam
 let map = or_map.new(replica_id.new(\"A\"), crdt.LwwRegisterSpec(42))
 let delta = or_map.empty_delta(map)
 let encoded = or_map.delta_to_json_with(delta, json.int) |> json.to_string
 let assert Ok(decoded) = or_map.delta_from_json_with(encoded, decode.int)
 or_map.apply_delta(map, decoded) // -> Ok(map)
 ```").
delta_from_json_with(Input, Decoder) ->
    lattice_maps@crdt:or_delta_from_json_with(Input, Decoder).

-file("src/lattice_maps/or_map.gleam", 486).
-spec delta_from_json(binary()) -> {ok, lattice_maps@crdt:o_r_map_delta(binary())} | {error, gleam@json:decode_error()}.
-doc(~" Decode a modern String delta. Legacy map deltas are intentionally rejected.

 ## Examples

 ```gleam
 let map = or_map.new(replica_id.new(\"A\"), crdt.LwwRegisterSpec(\"\"))
 let delta = or_map.empty_delta(map)
 let encoded = delta |> or_map.delta_to_json |> json.to_string
 let assert Ok(decoded) = or_map.delta_from_json(encoded)
 or_map.apply_delta(map, decoded) // -> Ok(map)
 ```").
delta_from_json(Input) ->
    delta_from_json_with(Input, {decoder, fun gleam@dynamic@decode:decode_string/1}).

-file("src/lattice_maps/or_map.gleam", 534).
-spec import_legacy(binary(), lattice_maps@crdt:crdt_spec(NHH), gleam@dynamic@decode:decoder(NHH), lattice_core@replica_id:replica_id()) -> {ok, lattice_maps@crdt:o_r_map(NHH)} | {error, gleam@json:decode_error()}.
-doc(~" Import a coordinated legacy baseline into Initial generations.

 Supply the agreed schema/default and a fresh editing identity if old allocation
 history is missing. Distribute a modern snapshot; do not mix old map deltas.

 ## Examples

 Convert an agreed legacy register-map baseline to a modern snapshot:

 ```gleam
 import gleam/dynamic/decode
 import gleam/result
 import lattice_core/replica_id
 import lattice_maps/crdt
 import lattice_maps/or_map

 pub fn migrate(legacy_snapshot: String) {
   use map <- result.try(or_map.import_legacy(
     legacy_snapshot, crdt.LwwRegisterSpec(\"\"), decode.string,
     replica_id.new(\"cutover-writer\"),
   ))
   Ok(or_map.to_json(map))
 }
 ```").
import_legacy(Input, Spec, Decoder, Replica) ->
    lattice_maps@crdt:or_import_legacy(Input, Spec, Decoder, Replica).

