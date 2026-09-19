-module(lattice_core@replica_id).
-compile([no_auto_import, nowarn_ignored, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-export([new/1, to_string/1, compare/2, to_json/1, decoder/0]).
-export_type([replica_id/0]).
-moduledoc(~" A globally unique identifier for a replica (node) in a distributed system.

 Replica IDs are opaque wrappers around strings. Use `new` to create one
 from a string and `to_string` to extract the underlying value. The opaque
 type prevents accidental use of arbitrary strings where a replica ID is
 expected.

 ## Example

 ```gleam
 import lattice_core/replica_id

 let rid = replica_id.new(\"node-a\")
 replica_id.to_string(rid)  // -> \"node-a\"
 ```").

-opaque replica_id() :: {replica_id, binary()}.

-file("src/lattice_core/replica_id.gleam", 32).
-spec new(binary()) -> replica_id().
-doc(~" Create a new ReplicaId from a string.").
new(Id) ->
    {replica_id, Id}.

-file("src/lattice_core/replica_id.gleam", 37).
-spec to_string(replica_id()) -> binary().
-doc(~" Extract the underlying string from a ReplicaId.").
to_string(Replica_id) ->
    {replica_id, S} = Replica_id,
    S.

-file("src/lattice_core/replica_id.gleam", 54).
-spec compare(replica_id(), replica_id()) -> gleam@order:order().
-doc(~" Compare two ReplicaId values by lexicographic UTF-8 byte order.

 Uses the same order on Erlang and JavaScript for deterministic tie-breaking
 (e.g., in LWW-Register merge when timestamps are equal). Strings retain their
 original form; no Unicode normalization is applied.

 ## Examples

 ```gleam
 compare(new(\"\\u{e000}\"), new(\"\\u{10000}\"))
 // -> order.Lt
 ```").
compare(A, B) ->
    {replica_id, A@1} = A,
    {replica_id, B@1} = B,
    gleam@bit_array:compare(<<A@1/binary>>, <<B@1/binary>>).

-file("src/lattice_core/replica_id.gleam", 61).
-spec to_json(replica_id()) -> gleam@json:json().
-doc(~" Encode a ReplicaId as a JSON string.").
to_json(Replica_id) ->
    gleam@json:string(to_string(Replica_id)).

-file("src/lattice_core/replica_id.gleam", 69).
-spec decoder() -> gleam@dynamic@decode:decoder(replica_id()).
-doc(~" A decoder for ReplicaId values in JSON.

 Decodes a JSON string and wraps it in a ReplicaId. Useful as a building
 block in `from_json` decoders across the library.").
decoder() ->
    gleam@dynamic@decode:map({decoder, fun gleam@dynamic@decode:decode_string/1}, fun new/1).

