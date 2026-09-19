-module(lattice_counters@g_counter).
-compile([no_auto_import, nowarn_ignored, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-export([new/1, increment_with_delta/2, increment/2, value/1, merge/2, to_json/1, from_json/1, to_parts/1, from_parts/2]).
-export_type([g_counter/0, increment_error/0]).
-moduledoc(~" A grow-only counter (G-Counter) CRDT.

 Each replica maintains its own monotonically increasing count. The global
 value is the sum across all replicas. Merge takes the pairwise maximum
 of each replica's count, guaranteeing convergence.

 G-Counter is opaque: use the provided functions to interact with it.
 `pn_counter` in the same package can access internal fields directly.

 ## Example

 ```gleam
 import lattice_core/replica_id
 import lattice_counters/g_counter

 let assert Ok(a) = g_counter.new(replica_id.new(\"node-a\")) |> g_counter.increment(3)
 let assert Ok(b) = g_counter.new(replica_id.new(\"node-b\")) |> g_counter.increment(5)
 let merged = g_counter.merge(a, b)
 g_counter.value(merged)  // -> 8
 ```").

-opaque g_counter() :: {g_counter, gleam@dict:dict(lattice_core@replica_id:replica_id(), integer()), lattice_core@replica_id:replica_id()}.

-type increment_error() :: {negative_delta, integer()}.

-file("src/lattice_counters/g_counter.gleam", 47).
-spec new(lattice_core@replica_id:replica_id()) -> g_counter().
-doc(~" Create a new G-Counter for the given replica.

 Returns a fresh counter where all per-replica counts are zero.
 The `replica_id` identifies this node and is used when incrementing.").
new(Replica_id) ->
    {g_counter, maps:new(), Replica_id}.

-file("src/lattice_counters/g_counter.gleam", 74).
-spec increment_with_delta(g_counter(), integer()) -> {ok, {g_counter(), g_counter()}} | {error, increment_error()}.
-doc(~" Increment the counter by `delta` and return both the new state and a delta.

 The returned delta is itself a `GCounter` containing only this replica's
 new count. Merging the delta into a remote replica via `merge` produces
 the same result as merging the full new state — but the delta is a
 minimal payload suitable for incremental sync (e.g., over websockets).

 Returns `Error(NegativeDelta(delta))` if `delta` is negative.").
increment_with_delta(Counter, Delta) ->
    gleam@bool:guard(Delta < 0, {error, {negative_delta, Delta}}, fun() ->
        {g_counter, Dict, Self_id} = Counter,
        Current = gleam@result:unwrap(gleam_stdlib:map_get(Dict, Self_id), 0),
        New_count = Current + Delta,
        Updated = {g_counter, gleam@dict:insert(Dict, Self_id, New_count), Self_id},
        Delta_state = {g_counter, maps:from_list([{Self_id, New_count}]), Self_id},
        {ok, {Updated, Delta_state}}
    end).

-file("src/lattice_counters/g_counter.gleam", 58).
-spec increment(g_counter(), integer()) -> {ok, g_counter()} | {error, increment_error()}.
-doc(~" Increment the counter by `delta`.

 Adds `delta` to this replica's count.
 Returns `Error(NegativeDelta(delta))` if `delta` is negative.

 See `increment_with_delta` for the delta-state variant that also returns
 a small payload suitable for incremental sync (e.g. over websockets).").
increment(Counter, Delta) ->
    _pipe = increment_with_delta(Counter, Delta),
    gleam@result:map(_pipe, fun(Pair) ->
        erlang:element(1, Pair)
    end).

-file("src/lattice_counters/g_counter.gleam", 91).
-spec value(g_counter()) -> integer().
-doc(~" Get the current value of the counter.

 Returns the sum of all per-replica counts, which represents the total
 number of increments applied across all replicas observed by this counter.").
value(Counter) ->
    {g_counter, Dict, _} = Counter,
    gleam@dict:fold(Dict, 0, fun(Acc, _, Value) ->
        Acc + Value
    end).

-file("src/lattice_counters/g_counter.gleam", 187).
-spec merge_helper(gleam@dict:dict(lattice_core@replica_id:replica_id(), integer()), gleam@dict:dict(lattice_core@replica_id:replica_id(), integer()), list(lattice_core@replica_id:replica_id()), gleam@dict:dict(lattice_core@replica_id:replica_id(), integer())) -> gleam@dict:dict(lattice_core@replica_id:replica_id(), integer()).
merge_helper(A, B, Keys, Acc) ->
    case Keys of
        [] ->
            Acc;

        [Key | Rest] ->
            A_val = gleam@result:unwrap(gleam_stdlib:map_get(A, Key), 0),
            B_val = gleam@result:unwrap(gleam_stdlib:map_get(B, Key), 0),
            Merged_val = case A_val > B_val of
                true ->
                    A_val;

                false ->
                    B_val
            end,
            New_acc = gleam@dict:insert(Acc, Key, Merged_val),
            merge_helper(A, B, Rest, New_acc)
    end.

-file("src/lattice_counters/g_counter.gleam", 104).
-spec merge(g_counter(), g_counter()) -> g_counter().
-doc(~" Merge two G-Counters using pairwise maximum.

 For each replica, the merged count is the maximum of the two inputs.
 The result's `self_id` is taken from `a`.

 This operation is commutative, associative, and idempotent, satisfying
 the CRDT join-semilattice laws. Any ordering of concurrent merges will
 produce the same final state.").
merge(A, B) ->
    {g_counter, Dict_a, Self_id_a} = A,
    {g_counter, Dict_b, _} = B,
    A_keys = maps:keys(Dict_a),
    B_keys = maps:keys(Dict_b),
    All_keys = gleam@list:unique(lists:append(A_keys, B_keys)),
    Merged_dict = merge_helper(Dict_a, Dict_b, All_keys, maps:new()),
    {g_counter, Merged_dict, Self_id_a}.

-file("src/lattice_counters/g_counter.gleam", 124).
-spec to_json(g_counter()) -> gleam@json:json().
-doc(~" Encode a G-Counter as a self-describing JSON value.

 Produces an envelope with `type`, `v` (schema version), and `state`.
 Format: `{\"type\": \"g_counter\", \"v\": 1, \"state\": {\"self_id\": \"...\", \"counts\": {...}}}`

 Use `from_json` to decode the result back into a `GCounter`.").
to_json(Counter) ->
    {g_counter, D, Self_id} = Counter,
    gleam@json:object([{~"type", gleam@json:string(~"g_counter")}, {~"v", gleam@json:int(1)}, {~"state", gleam@json:object([{~"self_id", lattice_core@replica_id:to_json(Self_id)}, {~"counts", gleam@json:dict(D, fun(K) ->
        lattice_core@replica_id:to_string(K)
    end, fun gleam@json:int/1)}])}]).

-file("src/lattice_counters/g_counter.gleam", 143).
-spec from_json(binary()) -> {ok, g_counter()} | {error, gleam@json:decode_error()}.
-doc(~" Decode a G-Counter from a JSON string produced by `to_json`.

 Returns `Ok(GCounter)` on success, or `Error(json.DecodeError)` if the
 input is not a valid G-Counter JSON envelope.").
from_json(Json_string) ->
    State_decoder = begin
        gleam@dynamic@decode:field(~"state", begin
            gleam@dynamic@decode:field(~"self_id", lattice_core@replica_id:decoder(), fun(Self_id) ->
                Non_negative_int = begin
                    _pipe = {decoder, fun gleam@dynamic@decode:decode_int/1},
                    gleam@dynamic@decode:then(_pipe, fun(Val) ->
                        case Val >= 0 of
                            true ->
                                gleam@dynamic@decode:success(Val);

                            false ->
                                gleam@dynamic@decode:failure(Val, ~"a non-negative integer")
                        end
                    end)
                end,
                gleam@dynamic@decode:field(~"counts", gleam@dynamic@decode:dict(lattice_core@replica_id:decoder(), Non_negative_int), fun(Counts) ->
                    gleam@dynamic@decode:success({g_counter, Counts, Self_id})
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
            case (Type_tag =:= ~"g_counter") andalso (Version =:= 1) of
                true ->
                    gleam@json:parse(Json_string, State_decoder);

                false ->
                    {error, {unable_to_decode, [{decode_error, ~"type=g_counter and v=1", <<<<Type_tag/binary, " v="/utf8>>/binary, (erlang:integer_to_binary(Version))/binary>>, []}]}}
            end
    end.

-file("src/lattice_counters/g_counter.gleam", 210).
-spec to_parts(g_counter()) -> {gleam@dict:dict(lattice_core@replica_id:replica_id(), integer()), lattice_core@replica_id:replica_id()}.
-doc(false).
to_parts(Counter) ->
    {g_counter, Dict, Self_id} = Counter,
    {Dict, Self_id}.

-file("src/lattice_counters/g_counter.gleam", 217).
-spec from_parts(gleam@dict:dict(lattice_core@replica_id:replica_id(), integer()), lattice_core@replica_id:replica_id()) -> g_counter().
-doc(false).
from_parts(Dict, Self_id) ->
    {g_counter, Dict, Self_id}.

