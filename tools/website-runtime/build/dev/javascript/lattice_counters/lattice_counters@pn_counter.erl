-module(lattice_counters@pn_counter).
-compile([no_auto_import, nowarn_ignored, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-export([new/1, increment_with_delta/2, increment/2, decrement_with_delta/2, decrement/2, value/1, merge/2, to_json/1, from_json/1]).
-export_type([p_n_counter/0, update_error/0]).
-moduledoc(~" A positive-negative counter (PN-Counter) CRDT.

 Supports both increment and decrement operations by pairing two G-Counters:
 one tracking increments and one tracking decrements. The value is the
 difference between the two totals. Merge delegates to G-Counter merge on
 each half independently.

 ## Example

 ```gleam
 import lattice_core/replica_id
 import lattice_counters/pn_counter

 let assert Ok(counter) = pn_counter.new(replica_id.new(\"node-a\"))
   |> pn_counter.increment(10)
 let assert Ok(counter) = pn_counter.decrement(counter, 3)
 pn_counter.value(counter)  // -> 7
 ```").

-opaque p_n_counter() :: {p_n_counter, lattice_counters@g_counter:g_counter(), lattice_counters@g_counter:g_counter()}.

-type update_error() :: {negative_delta, integer()}.

-file("src/lattice_counters/pn_counter.gleam", 43).
-spec new(lattice_core@replica_id:replica_id()) -> p_n_counter().
-doc(~" Create a new PN-Counter for the given replica.

 Returns a fresh counter with a zero value. Both inner G-Counters are
 initialized with `replica_id` as their node identifier.").
new(Replica_id) ->
    {p_n_counter, lattice_counters@g_counter:new(Replica_id), lattice_counters@g_counter:new(Replica_id)}.

-file("src/lattice_counters/pn_counter.gleam", 133).
-spec self_id_of(lattice_counters@g_counter:g_counter()) -> lattice_core@replica_id:replica_id().
self_id_of(C) ->
    {_, Self_id} = lattice_counters@g_counter:to_parts(C),
    Self_id.

-file("src/lattice_counters/pn_counter.gleam", 73).
-spec increment_with_delta(p_n_counter(), integer()) -> {ok, {p_n_counter(), p_n_counter()}} | {error, update_error()}.
-doc(~" Increment the counter by `delta` and return both the new state and a delta.

 The returned delta is a `PNCounter` whose positive G-Counter contains
 only this replica's new positive count and whose negative G-Counter is
 empty. Merging the delta into a remote replica via `merge` produces the
 same observable result as merging the full new state.

 Returns `Error(NegativeDelta(delta))` if `delta` is negative.").
increment_with_delta(Counter, Delta) ->
    {p_n_counter, Positive, Negative} = Counter,
    case lattice_counters@g_counter:increment_with_delta(Positive, Delta) of
        {ok, {Updated_positive, Positive_delta}} ->
            Updated = {p_n_counter, Updated_positive, Negative},
            Delta_state = {p_n_counter, Positive_delta, lattice_counters@g_counter:new(self_id_of(Negative))},
            {ok, {Updated, Delta_state}};

        {error, {negative_delta, D}} ->
            {error, {negative_delta, D}}
    end.

-file("src/lattice_counters/pn_counter.gleam", 57).
-spec increment(p_n_counter(), integer()) -> {ok, p_n_counter()} | {error, update_error()}.
-doc(~" Increment the counter by `delta`.

 Adds `delta` to the positive G-Counter.
 Returns `Error(NegativeDelta(delta))` if `delta` is negative.

 See `increment_with_delta` for the delta-state variant that also returns
 a small payload suitable for incremental sync (e.g. over websockets).").
increment(Counter, Delta) ->
    _pipe = increment_with_delta(Counter, Delta),
    gleam@result:map(_pipe, fun(Pair) ->
        erlang:element(1, Pair)
    end).

-file("src/lattice_counters/pn_counter.gleam", 114).
-spec decrement_with_delta(p_n_counter(), integer()) -> {ok, {p_n_counter(), p_n_counter()}} | {error, update_error()}.
-doc(~" Decrement the counter by `delta` and return both the new state and a delta.

 The returned delta is a `PNCounter` whose negative G-Counter contains
 only this replica's new negative count and whose positive G-Counter is
 empty. Merging the delta into a remote replica via `merge` produces the
 same observable result as merging the full new state.

 Returns `Error(NegativeDelta(delta))` if `delta` is negative.").
decrement_with_delta(Counter, Delta) ->
    {p_n_counter, Positive, Negative} = Counter,
    case lattice_counters@g_counter:increment_with_delta(Negative, Delta) of
        {ok, {Updated_negative, Negative_delta}} ->
            Updated = {p_n_counter, Positive, Updated_negative},
            Delta_state = {p_n_counter, lattice_counters@g_counter:new(self_id_of(Positive)), Negative_delta},
            {ok, {Updated, Delta_state}};

        {error, {negative_delta, D}} ->
            {error, {negative_delta, D}}
    end.

-file("src/lattice_counters/pn_counter.gleam", 98).
-spec decrement(p_n_counter(), integer()) -> {ok, p_n_counter()} | {error, update_error()}.
-doc(~" Decrement the counter by `delta`.

 Adds `delta` to the negative G-Counter (which reduces the visible value).
 Returns `Error(NegativeDelta(delta))` if `delta` is negative.

 See `decrement_with_delta` for the delta-state variant.").
decrement(Counter, Delta) ->
    _pipe = decrement_with_delta(Counter, Delta),
    gleam@result:map(_pipe, fun(Pair) ->
        erlang:element(1, Pair)
    end).

-file("src/lattice_counters/pn_counter.gleam", 142).
-spec value(p_n_counter()) -> integer().
-doc(~" Get the current value of the counter.

 Returns the sum of positive increments minus the sum of negative
 decrements observed across all replicas.").
value(Counter) ->
    {p_n_counter, Positive, Negative} = Counter,
    lattice_counters@g_counter:value(Positive) - lattice_counters@g_counter:value(Negative).

-file("src/lattice_counters/pn_counter.gleam", 154).
-spec merge(p_n_counter(), p_n_counter()) -> p_n_counter().
-doc(~" Merge two PN-Counters.

 Merges the positive G-Counters and negative G-Counters independently using
 pairwise maximum. The result's `self_id` is taken from `a`'s positive
 G-Counter.

 This operation is commutative, associative, and idempotent.").
merge(A, B) ->
    {p_n_counter, Positive_a, Negative_a} = A,
    {p_n_counter, Positive_b, Negative_b} = B,
    {p_n_counter, lattice_counters@g_counter:merge(Positive_a, Positive_b), lattice_counters@g_counter:merge(Negative_a, Negative_b)}.

-file("src/lattice_counters/pn_counter.gleam", 170).
-spec to_json(p_n_counter()) -> gleam@json:json().
-doc(~" Encode a PN-Counter as a self-describing JSON value.

 Produces an envelope with `type`, `v` (schema version), and `state`.
 Format: `{\"type\": \"pn_counter\", \"v\": 1, \"state\": {\"positive\": {...}, \"negative\": {...}}}`

 Use `from_json` to decode the result back into a `PNCounter`.").
to_json(Counter) ->
    {p_n_counter, Positive, Negative} = Counter,
    {Pos_dict, Pos_id} = lattice_counters@g_counter:to_parts(Positive),
    {Neg_dict, Neg_id} = lattice_counters@g_counter:to_parts(Negative),
    gleam@json:object([{~"type", gleam@json:string(~"pn_counter")}, {~"v", gleam@json:int(1)}, {~"state", gleam@json:object([{~"positive", gleam@json:object([{~"self_id", lattice_core@replica_id:to_json(Pos_id)}, {~"counts", gleam@json:dict(Pos_dict, fun(K) ->
        lattice_core@replica_id:to_string(K)
    end, fun gleam@json:int/1)}])}, {~"negative", gleam@json:object([{~"self_id", lattice_core@replica_id:to_json(Neg_id)}, {~"counts", gleam@json:dict(Neg_dict, fun(K) ->
        lattice_core@replica_id:to_string(K)
    end, fun gleam@json:int/1)}])}])}]).

-file("src/lattice_counters/pn_counter.gleam", 209).
-spec from_json(binary()) -> {ok, p_n_counter()} | {error, gleam@json:decode_error()}.
-doc(~" Decode a PN-Counter from a JSON string produced by `to_json`.

 Returns `Ok(PNCounter)` on success, or `Error(json.DecodeError)` if the
 input is not a valid PN-Counter JSON envelope.").
from_json(Json_string) ->
    G_counter_state_decoder = begin
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
                gleam@dynamic@decode:success(lattice_counters@g_counter:from_parts(Counts, Self_id))
            end)
        end)
    end,
    State_decoder = begin
        gleam@dynamic@decode:field(~"state", begin
            gleam@dynamic@decode:field(~"positive", G_counter_state_decoder, fun(Positive) ->
                gleam@dynamic@decode:field(~"negative", G_counter_state_decoder, fun(Negative) ->
                    gleam@dynamic@decode:success({p_n_counter, Positive, Negative})
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
            case (Type_tag =:= ~"pn_counter") andalso (Version =:= 1) of
                true ->
                    gleam@json:parse(Json_string, State_decoder);

                false ->
                    {error, {unable_to_decode, [{decode_error, ~"type=pn_counter and v=1", <<<<Type_tag/binary, " v="/utf8>>/binary, (erlang:integer_to_binary(Version))/binary>>, []}]}}
            end
    end.

