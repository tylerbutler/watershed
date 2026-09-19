-module(lattice_sets@two_p_set).
-compile([no_auto_import, nowarn_ignored, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-export([new/0, add_with_delta/2, add/2, remove_with_delta/2, remove/2, contains/2, value/1, merge/2, to_json_with/2, to_json/1, from_json_with/2, from_json/1]).
-export_type([two_p_set/1]).
-moduledoc(~" A two-phase set (2P-Set) CRDT.

 Supports both add and remove, but an element can only be removed once. Once
 removed (tombstoned), an element can never be re-added. Internally tracks
 two sets: `added` and `removed`. An element is active if it is in `added`
 but not in `removed`. Use `ORSet` if you need re-add after remove.

 ## Example

 ```gleam
 import lattice_sets/two_p_set

 let set = two_p_set.new()
   |> two_p_set.add(\"alice\")
   |> two_p_set.add(\"bob\")
   |> two_p_set.remove(\"bob\")
 two_p_set.contains(set, \"alice\")  // -> True
 two_p_set.contains(set, \"bob\")    // -> False (tombstoned)
 ```").

-opaque two_p_set(ENZ) :: {two_p_set, gleam@set:set(ENZ), gleam@set:set(ENZ)}.

-file("src/lattice_sets/two_p_set.gleam", 37).
-spec new() -> two_p_set(any()).
-doc(~" Create a new empty 2P-Set.").
new() ->
    {two_p_set, gleam@set:new(), gleam@set:new()}.

-file("src/lattice_sets/two_p_set.gleam", 60).
-spec add_with_delta(two_p_set(EOF), EOF) -> {two_p_set(EOF), two_p_set(EOF)}.
-doc(~" Add an element and return both the new state and a delta.

 The returned delta is a `TwoPSet` whose `added` set contains only the
 inserted element and whose `removed` set is empty. Merging the delta
 into a remote via `merge` (union of both halves) produces the same
 result as merging the full new state.").
add_with_delta(Two_p_set, Element) ->
    Updated = {two_p_set, gleam@set:insert(erlang:element(2, Two_p_set), Element), erlang:element(3, Two_p_set)},
    Delta = {two_p_set, gleam@set:from_list([Element]), gleam@set:new()},
    {Updated, Delta}.

-file("src/lattice_sets/two_p_set.gleam", 49).
-spec add(two_p_set(EOC), EOC) -> two_p_set(EOC).
-doc(~" Add an element to the set.

 If the element has already been tombstoned (removed), this call records the
 element in `added` but the element will not be considered active because
 the tombstone takes precedence.

 See `add_with_delta` for the delta-state variant that also returns a
 small payload suitable for incremental sync (e.g. over websockets).").
add(Two_p_set, Element) ->
    {Updated, _} = add_with_delta(Two_p_set, Element),
    Updated.

-file("src/lattice_sets/two_p_set.gleam", 90).
-spec remove_with_delta(two_p_set(EOM), EOM) -> {two_p_set(EOM), two_p_set(EOM)}.
-doc(~" Remove an element and return both the new state and a delta.

 The returned delta is a `TwoPSet` whose `removed` set contains only the
 tombstoned element and whose `added` set is empty. Merging the delta into
 a remote via `merge` propagates the tombstone, deactivating the element
 in the remote replica regardless of its prior state.").
remove_with_delta(Two_p_set, Element) ->
    Updated = {two_p_set, erlang:element(2, Two_p_set), gleam@set:insert(erlang:element(3, Two_p_set), Element)},
    Delta = {two_p_set, gleam@set:new(), gleam@set:from_list([Element])},
    {Updated, Delta}.

-file("src/lattice_sets/two_p_set.gleam", 79).
-spec remove(two_p_set(EOJ), EOJ) -> two_p_set(EOJ).
-doc(~" Remove an element from the set by adding it to the tombstone set.

 Once tombstoned, the element is permanently inactive. Removing an element
 that was never added is also valid and creates a preemptive tombstone.

 See `remove_with_delta` for the delta-state variant.").
remove(Two_p_set, Element) ->
    {Updated, _} = remove_with_delta(Two_p_set, Element),
    Updated.

-file("src/lattice_sets/two_p_set.gleam", 106).
-spec contains(two_p_set(EOQ), EOQ) -> boolean().
-doc(~" Check if the set currently contains the given element.

 Returns `True` only if `element` is in `added` and NOT in `removed`.").
contains(Two_p_set, Element) ->
    gleam@set:contains(erlang:element(2, Two_p_set), Element) andalso not gleam@set:contains(erlang:element(3, Two_p_set), Element).

-file("src/lattice_sets/two_p_set.gleam", 115).
-spec value(two_p_set(EOS)) -> gleam@set:set(EOS).
-doc(~" Return the set of all currently active elements.

 Active elements are those in `added` that have not been tombstoned.
 Equivalent to `added ∖ removed`.").
value(Two_p_set) ->
    gleam@set:filter(erlang:element(2, Two_p_set), fun(Element) ->
        not gleam@set:contains(erlang:element(3, Two_p_set), Element)
    end).

-file("src/lattice_sets/two_p_set.gleam", 125).
-spec merge(two_p_set(EOV), two_p_set(EOV)) -> two_p_set(EOV).
-doc(~" Merge two 2P-Sets by taking the union of both added sets and both removed sets.

 A tombstone on any replica propagates to all replicas after merge.
 Merge is commutative, associative, and idempotent (a valid CRDT join).").
merge(A, B) ->
    {two_p_set, gleam@set:union(erlang:element(2, A), erlang:element(2, B)), gleam@set:union(erlang:element(3, A), erlang:element(3, B))}.

-file("src/lattice_sets/two_p_set.gleam", 149).
-spec to_json_with(two_p_set(EPA), fun((EPA) -> gleam@json:json())) -> gleam@json:json().
-doc(~" Encode generic elements and permanent tombstones in the v1 envelope.

 ## Examples

 ```gleam
 let set = two_p_set.new() |> two_p_set.add(42) |> two_p_set.remove(42)
 two_p_set.to_json_with(set, json.int)
 ```").
to_json_with(Two_p_set, Encode) ->
    gleam@json:object([{~"type", gleam@json:string(~"two_p_set")}, {~"v", gleam@json:int(1)}, {~"state", gleam@json:object([{~"added", gleam@json:array(gleam@set:to_list(erlang:element(2, Two_p_set)), Encode)}, {~"removed", gleam@json:array(gleam@set:to_list(erlang:element(3, Two_p_set)), Encode)}])}]).

-file("src/lattice_sets/two_p_set.gleam", 137).
-spec to_json(two_p_set(binary())) -> gleam@json:json().
-doc(~" Encode a `TwoPSet(String)` as a self-describing JSON value.

 Format: `{\"type\": \"two_p_set\", \"v\": 1, \"state\": {\"added\": [...], \"removed\": [...]}}`

 The encoded value can be restored with `from_json`.").
to_json(Two_p_set) ->
    to_json_with(Two_p_set, fun gleam@json:string/1).

-file("src/lattice_sets/two_p_set.gleam", 187).
-spec from_json_with(binary(), gleam@dynamic@decode:decoder(EPF)) -> {ok, two_p_set(EPF)} | {error, gleam@json:decode_error()}.
-doc(~" Decode generic elements and permanent tombstones from the v1 envelope.

 Invalid envelopes or elements return `Error`.

 ## Examples

 ```gleam
 let set = two_p_set.new() |> two_p_set.remove(42)
 let encoded = two_p_set.to_json_with(set, json.int) |> json.to_string
 two_p_set.from_json_with(encoded, decode.int)  // -> Ok(set)
 ```").
from_json_with(Json_string, Decoder) ->
    State_decoder = begin
        gleam@dynamic@decode:field(~"state", begin
            gleam@dynamic@decode:field(~"added", gleam@dynamic@decode:list(Decoder), fun(Added) ->
                gleam@dynamic@decode:field(~"removed", gleam@dynamic@decode:list(Decoder), fun(Removed) ->
                    gleam@dynamic@decode:success({two_p_set, gleam@set:from_list(Added), gleam@set:from_list(Removed)})
                end)
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
            case (Type_tag =:= ~"two_p_set") andalso (Version =:= 1) of
                true ->
                    gleam@json:parse(Json_string, State_decoder);

                false ->
                    {error, {unable_to_decode, [{decode_error, ~"type=two_p_set and v=1", <<<<Type_tag/binary, " v="/utf8>>/binary, (erlang:integer_to_binary(Version))/binary>>, []}]}}
            end
    end.

-file("src/lattice_sets/two_p_set.gleam", 170).
-spec from_json(binary()) -> {ok, two_p_set(binary())} | {error, gleam@json:decode_error()}.
-doc(~" Decode a `TwoPSet(String)` from a JSON string produced by `to_json`.

 Returns `Error` if the string is not valid JSON or does not match the
 expected format.").
from_json(Json_string) ->
    from_json_with(Json_string, {decoder, fun gleam@dynamic@decode:decode_string/1}).

