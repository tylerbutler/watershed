-module(lattice_sets@g_set).
-compile([no_auto_import, nowarn_ignored, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-export([new/0, add_with_delta/2, add/2, contains/2, value/1, merge/2, to_json_with/2, to_json/1, from_json_with/2, from_json/1]).
-export_type([g_set/1]).
-moduledoc(~" A grow-only set (G-Set) CRDT.

 Elements can be added but never removed. Merge is set union, so any element
 added on any replica will eventually appear in all replicas. This is the
 simplest set CRDT — use `TwoPSet` or `ORSet` if you need removal.

 ## Example

 ```gleam
 import lattice_sets/g_set

 let a = g_set.new() |> g_set.add(\"alice\")
 let b = g_set.new() |> g_set.add(\"bob\")
 let merged = g_set.merge(a, b)
 g_set.contains(merged, \"alice\")  // -> True
 g_set.contains(merged, \"bob\")    // -> True
 ```").

-opaque g_set(DSH) :: {g_set, gleam@set:set(DSH)}.

-file("src/lattice_sets/g_set.gleam", 34).
-spec new() -> g_set(any()).
-doc(~" Create a new empty G-Set.").
new() ->
    {g_set, gleam@set:new()}.

-file("src/lattice_sets/g_set.gleam", 55).
-spec add_with_delta(g_set(DSN), DSN) -> {g_set(DSN), g_set(DSN)}.
-doc(~" Add an element to the set and return both the new state and a delta.

 The returned delta is a `GSet` containing only the inserted element.
 Merging the delta into a remote replica via `merge` (set union) produces
 the same result as merging the full new state, but ships only the change.").
add_with_delta(G_set, Element) ->
    Updated = {g_set, gleam@set:insert(erlang:element(2, G_set), Element)},
    Delta = {g_set, gleam@set:from_list([Element])},
    {Updated, Delta}.

-file("src/lattice_sets/g_set.gleam", 45).
-spec add(g_set(DSK), DSK) -> g_set(DSK).
-doc(~" Add an element to the set.

 This operation is idempotent: adding the same element multiple times is
 equivalent to adding it once.

 See `add_with_delta` for the delta-state variant that also returns a
 small payload suitable for incremental sync (e.g. over websockets).").
add(G_set, Element) ->
    {Updated, _} = add_with_delta(G_set, Element),
    Updated.

-file("src/lattice_sets/g_set.gleam", 64).
-spec contains(g_set(DSR), DSR) -> boolean().
-doc(~" Check if the set contains the given element.

 Returns `True` if `element` was ever added to this set or any merged replica.").
contains(G_set, Element) ->
    gleam@set:contains(erlang:element(2, G_set), Element).

-file("src/lattice_sets/g_set.gleam", 71).
-spec value(g_set(DST)) -> gleam@set:set(DST).
-doc(~" Return the underlying set of all elements.

 Equivalent to inspecting the entire current state of the G-Set.").
value(G_set) ->
    erlang:element(2, G_set).

-file("src/lattice_sets/g_set.gleam", 79).
-spec merge(g_set(DSW), g_set(DSW)) -> g_set(DSW).
-doc(~" Merge two G-Sets by computing their union.

 The result contains every element that was ever added to either set.
 Merge is commutative, associative, and idempotent (a valid CRDT join).").
merge(A, B) ->
    {g_set, gleam@set:union(erlang:element(2, A), erlang:element(2, B))}.

-file("src/lattice_sets/g_set.gleam", 100).
-spec to_json_with(g_set(DTB), fun((DTB) -> gleam@json:json())) -> gleam@json:json().
-doc(~" Encode a set using a custom element encoder and the existing v1 envelope.

 ## Examples

 ```gleam
 let set = g_set.new() |> g_set.add(42)
 g_set.to_json_with(set, json.int)
 ```").
to_json_with(G_set, Encode) ->
    gleam@json:object([{~"type", gleam@json:string(~"g_set")}, {~"v", gleam@json:int(1)}, {~"state", gleam@json:object([{~"elements", gleam@json:array(gleam@set:to_list(erlang:element(2, G_set)), Encode)}])}]).

-file("src/lattice_sets/g_set.gleam", 88).
-spec to_json(g_set(binary())) -> gleam@json:json().
-doc(~" Encode a `GSet(String)` as a self-describing JSON value.

 Format: `{\"type\": \"g_set\", \"v\": 1, \"state\": {\"elements\": [...]}}`

 The encoded value can be restored with `from_json`.").
to_json(G_set) ->
    to_json_with(G_set, fun gleam@json:string/1).

-file("src/lattice_sets/g_set.gleam", 134).
-spec from_json_with(binary(), gleam@dynamic@decode:decoder(DTG)) -> {ok, g_set(DTG)} | {error, gleam@json:decode_error()}.
-doc(~" Decode a v1 set using a custom element decoder.

 Invalid envelopes or elements return `Error`.

 ## Examples

 ```gleam
 let set = g_set.new() |> g_set.add(42)
 let encoded = g_set.to_json_with(set, json.int) |> json.to_string
 g_set.from_json_with(encoded, decode.int)  // -> Ok(set)
 ```").
from_json_with(Json_string, Decoder) ->
    State_decoder = begin
        gleam@dynamic@decode:field(~"state", begin
            gleam@dynamic@decode:field(~"elements", gleam@dynamic@decode:list(Decoder), fun(Elements) ->
                gleam@dynamic@decode:success({g_set, gleam@set:from_list(Elements)})
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
            case (Type_tag =:= ~"g_set") andalso (Version =:= 1) of
                true ->
                    gleam@json:parse(Json_string, State_decoder);

                false ->
                    {error, {unable_to_decode, [{decode_error, ~"type=g_set and v=1", <<<<Type_tag/binary, " v="/utf8>>/binary, (erlang:integer_to_binary(Version))/binary>>, []}]}}
            end
    end.

-file("src/lattice_sets/g_set.gleam", 117).
-spec from_json(binary()) -> {ok, g_set(binary())} | {error, gleam@json:decode_error()}.
-doc(~" Decode a `GSet(String)` from a JSON string produced by `to_json`.

 Returns `Error` if the string is not valid JSON or does not match the
 expected format.").
from_json(Json_string) ->
    from_json_with(Json_string, {decoder, fun gleam@dynamic@decode:decode_string/1}).

