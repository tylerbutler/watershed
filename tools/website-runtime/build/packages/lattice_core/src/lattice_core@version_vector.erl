-module(lattice_core@version_vector).
-compile([no_auto_import, nowarn_ignored, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-export([new/0, increment/2, get/2, compare/2, dominates/2, is_empty/1, set_max/3, merge/2, to_json/1, from_json/1, decoder/0, to_dict/1, from_dict/1]).
-export_type([order/0, version_vector/0]).
-moduledoc(~" A version vector for tracking causal ordering between replicas.

 Each replica has a logical clock (monotonically increasing integer). Version
 vectors enable detecting whether two states are causally ordered (one happened
 before the other) or concurrent (neither dominates). Merge takes the pairwise
 maximum of all clocks.

 ## Example

 ```gleam
 import lattice_core/replica_id
 import lattice_core/version_vector

 let node_a = replica_id.new(\"node-a\")
 let node_b = replica_id.new(\"node-b\")
 let a = version_vector.new()
   |> version_vector.increment(node_a)
   |> version_vector.increment(node_a)
 let b = version_vector.new()
   |> version_vector.increment(node_b)
 version_vector.compare(a, b)  // -> Concurrent
 ```").

-type order() :: before | 'after' | concurrent | equal.

-opaque version_vector() :: {version_vector, gleam@dict:dict(lattice_core@replica_id:replica_id(), integer())}.

-file("src/lattice_core/version_vector.gleam", 60).
-spec new() -> version_vector().
-doc(~" Create a new empty version vector.

 All replica clocks start at zero (missing entries are treated as zero).").
new() ->
    {version_vector, maps:new()}.

-file("src/lattice_core/version_vector.gleam", 68).
-spec increment(version_vector(), lattice_core@replica_id:replica_id()) -> version_vector().
-doc(~" Increment the clock for a specific replica.

 Returns a new version vector with `replica_id`'s clock increased by one.
 This is the standard way to record a new event at `replica_id`.").
increment(Vector, Replica_id) ->
    {version_vector, Clocks} = Vector,
    Current = gleam@result:unwrap(gleam_stdlib:map_get(Clocks, Replica_id), 0),
    {version_vector, gleam@dict:insert(Clocks, Replica_id, Current + 1)}.

-file("src/lattice_core/version_vector.gleam", 81).
-spec get(version_vector(), lattice_core@replica_id:replica_id()) -> integer().
-doc(~" Get the clock value for a specific replica.

 Returns `0` if `replica_id` has not been seen (missing entries default
 to zero, consistent with the version vector semantics).").
get(Vector, Replica_id) ->
    {version_vector, Clocks} = Vector,
    gleam@result:unwrap(gleam_stdlib:map_get(Clocks, Replica_id), 0).

-file("src/lattice_core/version_vector.gleam", 91).
-spec compare(version_vector(), version_vector()) -> order().
-doc(~" Compare two version vectors and return their causal ordering.

 Returns `Equal` if all clocks match, `Before` if `a` is strictly dominated
 by `b`, `After` if `a` strictly dominates `b`, or `Concurrent` if neither
 dominates the other.").
compare(A, B) ->
    {version_vector, A_clocks} = A,
    {version_vector, B_clocks} = B,
    {Greater, Less} = gleam@dict:fold(A_clocks, {false, false}, fun(Acc, Key, A_clock) ->
        {Greater@1, Less@1} = Acc,
        B_clock = gleam@result:unwrap(gleam_stdlib:map_get(B_clocks, Key), 0),
        {Greater@1 orelse (A_clock > B_clock), Less@1 orelse (A_clock < B_clock)}
    end),
    {Greater@1, Less@1} = gleam@dict:fold(B_clocks, {Greater, Less}, fun(Acc, Key, _) ->
        {Greater@2, _} = Acc,
        case gleam@dict:has_key(A_clocks, Key) of
            true ->
                Acc;

            false ->
                {Greater@2, true}
        end
    end),
    case {Greater@1, Less@1} of
        {false, false} ->
            equal;

        {true, false} ->
            'after';

        {false, true} ->
            before;

        {true, true} ->
            concurrent
    end.

-file("src/lattice_core/version_vector.gleam", 127).
-spec dominates(version_vector(), version_vector()) -> boolean().
-doc(~" Check whether version vector `a` dominates `b`.

 Returns `True` when every clock in `a` is greater than or equal to the
 corresponding clock in `b`. Equivalently, `compare(a, b)` is `Equal` or
 `After`.").
dominates(A, B) ->
    case compare(A, B) of
        equal ->
            true;

        'after' ->
            true;

        before ->
            false;

        concurrent ->
            false
    end.

-file("src/lattice_core/version_vector.gleam", 135).
-spec is_empty(version_vector()) -> boolean().
-doc(~" Check whether a version vector is empty (has no clock entries).").
is_empty(Vector) ->
    {version_vector, Clocks} = Vector,
    gleam@dict:is_empty(Clocks).

-file("src/lattice_core/version_vector.gleam", 144).
-spec set_max(version_vector(), lattice_core@replica_id:replica_id(), integer()) -> version_vector().
-doc(~" Set the clock for a replica to the maximum of the current value and `value`.

 If the replica has no entry, `value` is used. This avoids round-tripping
 through `to_dict`/`from_dict` when building a version vector incrementally.").
set_max(Vv, Replica_id, Value) ->
    {version_vector, Clocks} = Vv,
    Current = gleam@result:unwrap(gleam_stdlib:map_get(Clocks, Replica_id), 0),
    case Value > Current of
        true ->
            {version_vector, gleam@dict:insert(Clocks, Replica_id, Value)};

        false ->
            Vv
    end.

-file("src/lattice_core/version_vector.gleam", 161).
-spec merge(version_vector(), version_vector()) -> version_vector().
-doc(~" Merge two version vectors using pairwise maximum.

 For each replica, the merged clock is the maximum of the two inputs.
 This operation is commutative, associative, and idempotent.").
merge(A, B) ->
    {version_vector, A_clocks} = A,
    {version_vector, B_clocks} = B,
    Merged = gleam@dict:fold(B_clocks, A_clocks, fun(Acc, Key, B_clock) ->
        case gleam_stdlib:map_get(Acc, Key) of
            {ok, A_clock} ->
                gleam@dict:insert(Acc, Key, gleam@int:max(A_clock, B_clock));

            {error, nil} ->
                gleam@dict:insert(Acc, Key, B_clock)
        end
    end),
    {version_vector, Merged}.

-file("src/lattice_core/version_vector.gleam", 182).
-spec to_json(version_vector()) -> gleam@json:json().
-doc(~" Encode a VersionVector as a self-describing JSON value.

 Produces an envelope with `type`, `v` (schema version), and `state`.
 Format: `{\"type\": \"version_vector\", \"v\": 1, \"state\": {\"clocks\": {...}}}`

 Use `from_json` to decode the result back into a `VersionVector`.").
to_json(Vector) ->
    {version_vector, Clocks} = Vector,
    gleam@json:object([{~"type", gleam@json:string(~"version_vector")}, {~"v", gleam@json:int(1)}, {~"state", gleam@json:object([{~"clocks", gleam@json:dict(Clocks, fun(Key) ->
        lattice_core@replica_id:to_string(Key)
    end, fun gleam@json:int/1)}])}]).

-file("src/lattice_core/version_vector.gleam", 203).
-spec from_json(binary()) -> {ok, version_vector()} | {error, gleam@json:decode_error()}.
-doc(~" Decode a VersionVector from a JSON string produced by `to_json`.

 Returns `Ok(VersionVector)` on success, or `Error(json.DecodeError)` if
 the input is not a valid version-vector JSON envelope.").
from_json(Json_string) ->
    State_decoder = begin
        gleam@dynamic@decode:field(~"state", begin
            gleam@dynamic@decode:field(~"clocks", gleam@dynamic@decode:dict(lattice_core@replica_id:decoder(), {decoder, fun gleam@dynamic@decode:decode_int/1}), fun(Clocks) ->
                gleam@dynamic@decode:success({version_vector, Clocks})
            end)
        end, fun(State) ->
            gleam@dynamic@decode:success(State)
        end)
    end,
    Envelope_decoder = begin
        gleam@dynamic@decode:field(~"type", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(Type_tag) ->
            gleam@dynamic@decode:field(~"v", {decoder, fun gleam@dynamic@decode:decode_int/1}, fun(Version) ->
                gleam@dynamic@decode:success({Type_tag, Version})
            end)
        end)
    end,
    case gleam@json:parse(Json_string, Envelope_decoder) of
        {error, E} ->
            {error, E};

        {ok, {Type_tag, Version}} ->
            case (Type_tag =:= ~"version_vector") andalso (Version =:= 1) of
                true ->
                    gleam@json:parse(Json_string, State_decoder);

                false ->
                    {error, {unable_to_decode, [{decode_error, ~"type=version_vector and v=1", <<<<Type_tag/binary, " v="/utf8>>/binary, (erlang:integer_to_binary(Version))/binary>>, []}]}}
            end
    end.

-file("src/lattice_core/version_vector.gleam", 245).
-spec decoder() -> gleam@dynamic@decode:decoder(version_vector()).
-doc(~" A JSON decoder for VersionVector values.

 Decodes the self-describing envelope format produced by `to_json`.
 Useful as a building block in `from_json` decoders when a VersionVector
 is embedded inline within another JSON structure.").
decoder() ->
    gleam@dynamic@decode:field(~"type", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(_) ->
        gleam@dynamic@decode:field(~"v", {decoder, fun gleam@dynamic@decode:decode_int/1}, fun(_) ->
            gleam@dynamic@decode:field(~"state", begin
                gleam@dynamic@decode:field(~"clocks", gleam@dynamic@decode:dict(lattice_core@replica_id:decoder(), {decoder, fun gleam@dynamic@decode:decode_int/1}), fun(Clocks) ->
                    gleam@dynamic@decode:success(Clocks)
                end)
            end, fun(Clocks) ->
                gleam@dynamic@decode:success({version_vector, Clocks})
            end)
        end)
    end).

-file("src/lattice_core/version_vector.gleam", 264).
-spec to_dict(version_vector()) -> gleam@dict:dict(lattice_core@replica_id:replica_id(), integer()).
-doc(~" Extract the internal clock dictionary from a VersionVector.

 Returns a `Dict(ReplicaId, Int)` mapping replica IDs to their clock values.
 Useful for serialization or when you need direct access to the raw clock
 data. Prefer the higher-level API (`get`, `compare`, `merge`) for most
 use cases.").
to_dict(Vector) ->
    {version_vector, Clocks} = Vector,
    Clocks.

-file("src/lattice_core/version_vector.gleam", 275).
-spec from_dict(gleam@dict:dict(lattice_core@replica_id:replica_id(), integer())) -> version_vector().
-doc(~" Construct a VersionVector from a raw clock dictionary.

 Creates a version vector from a `Dict(ReplicaId, Int)` mapping replica IDs
 to clock values. Useful for deserialization or constructing a version
 vector from external data. Prefer `new` and `increment` for most use
 cases.").
from_dict(Clocks) ->
    {version_vector, Clocks}.

