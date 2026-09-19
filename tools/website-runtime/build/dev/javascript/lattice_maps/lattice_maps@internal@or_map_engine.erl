-module(lattice_maps@internal@or_map_engine).
-compile([no_auto_import, nowarn_ignored, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-export([new/0, compare/2, clock/1, active/2, prepare/3, singleton/3, remove/2, join/3, prune/2]).
-export_type([generation/0, entry/1, state/1]).
-moduledoc(false).

-type generation() :: initial | {generation, integer(), lattice_core@replica_id:replica_id()}.

-type entry(JNI) :: {entry, generation(), lattice_sets@or_set:o_r_set(binary()), gleam@option:option(JNI)}.

-type state(JNJ) :: {state, integer(), gleam@dict:dict(binary(), entry(JNJ))}.

-file("src/lattice_maps/internal/or_map_engine.gleam", 28).
-spec new() -> state(any()).
-doc(false).
new() ->
    {state, 0, maps:new()}.

-file("src/lattice_maps/internal/or_map_engine.gleam", 32).
-spec compare(generation(), generation()) -> gleam@order:order().
-doc(false).
compare(A, B) ->
    case {A, B} of
        {initial, initial} ->
            eq;

        {initial, _} ->
            lt;

        {_, initial} ->
            gt;

        {{generation, Ac, Ar}, {generation, Bc, Br}} ->
            case gleam@int:compare(Ac, Bc) of
                eq ->
                    lattice_core@replica_id:compare(Ar, Br);

                Other ->
                    Other
            end
    end.

-file("src/lattice_maps/internal/or_map_engine.gleam", 45).
-spec clock(generation()) -> integer().
-doc(false).
clock(Generation) ->
    case Generation of
        initial ->
            0;

        {generation, Clock, _} ->
            Clock
    end.

-file("src/lattice_maps/internal/or_map_engine.gleam", 52).
-spec active(entry(any()), binary()) -> boolean().
-doc(false).
active(Entry, Key) ->
    lattice_sets@or_set:contains(erlang:element(3, Entry), Key).

-file("src/lattice_maps/internal/or_map_engine.gleam", 56).
-spec prepare(state(JNO), binary(), lattice_core@replica_id:replica_id()) -> entry(JNO).
-doc(false).
prepare(State, Key, Writer) ->
    case gleam_stdlib:map_get(erlang:element(3, State), Key) of
        {error, nil} ->
            {entry, initial, lattice_sets@or_set:new(Writer), none};

        {ok, Entry} ->
            case active(Entry, Key) of
                true ->
                    {entry, erlang:element(2, Entry), lattice_sets@or_set:merge(lattice_sets@or_set:new(Writer), erlang:element(3, Entry)), erlang:element(4, Entry)};

                false ->
                    {entry, {generation, erlang:element(2, State) + 1, Writer}, lattice_sets@or_set:new(Writer), none}
            end
    end.

-file("src/lattice_maps/internal/or_map_engine.gleam", 76).
-spec singleton(binary(), entry(JNR), integer()) -> state(JNR).
-doc(false).
singleton(Key, Entry, High_water) ->
    {state, gleam@int:max(High_water, clock(erlang:element(2, Entry))), maps:from_list([{Key, Entry}])}.

-file("src/lattice_maps/internal/or_map_engine.gleam", 87).
-spec remove(state(JNU), binary()) -> {state(JNU), state(any())}.
-doc(false).
remove(State, Key) ->
    case gleam_stdlib:map_get(erlang:element(3, State), Key) of
        {error, nil} ->
            {State, new()};

        {ok, Entry} ->
            {Membership, Delta} = lattice_sets@or_set:remove_with_delta(erlang:element(3, Entry), Key),
            {{state, erlang:element(2, State), gleam@dict:insert(erlang:element(3, State), Key, {entry, erlang:element(2, Entry), Membership, erlang:element(4, Entry)})}, singleton(Key, {entry, erlang:element(2, Entry), Delta, none}, erlang:element(2, State))}
    end.

-file("src/lattice_maps/internal/or_map_engine.gleam", 111).
-spec join(state(JNZ), state(JOB), fun((binary(), generation(), gleam@option:option(JNZ), gleam@option:option(JOB)) -> {ok, gleam@option:option(JOF)} | {error, JOH})) -> {ok, state(JOF)} | {error, JOH}.
-doc(false).
join(A, B, Combine) ->
    Entries = begin
        _pipe = maps:to_list(erlang:element(3, A)),
        gleam@list:map(_pipe, fun(Pair) ->
            {erlang:element(1, Pair), erlang:element(2, Pair), gleam_stdlib:map_get(erlang:element(3, B), erlang:element(1, Pair))}
        end)
    end,
    Only_b = begin
        _pipe@1 = maps:to_list(erlang:element(3, B)),
        gleam@list:filter(_pipe@1, fun(Pair) ->
            not gleam@dict:has_key(erlang:element(3, A), erlang:element(1, Pair))
        end)
    end,
    gleam@result:'try'(gleam@list:try_fold(Entries, maps:new(), fun(Entries@1, Pair) ->
        {Key, A@1, B@1} = Pair,
        {Generation, Membership, Left, Right} = case B@1 of
            {ok, B@2} ->
                case compare(erlang:element(2, A@1), erlang:element(2, B@2)) of
                    gt ->
                        {erlang:element(2, A@1), erlang:element(3, A@1), erlang:element(4, A@1), none};

                    lt ->
                        {erlang:element(2, B@2), erlang:element(3, B@2), none, erlang:element(4, B@2)};

                    eq ->
                        {erlang:element(2, A@1), lattice_sets@or_set:merge(erlang:element(3, A@1), erlang:element(3, B@2)), erlang:element(4, A@1), erlang:element(4, B@2)}
                end;

            {error, nil} ->
                {erlang:element(2, A@1), erlang:element(3, A@1), erlang:element(4, A@1), none}
        end,
        gleam@result:'try'(Combine(Key, Generation, Left, Right), fun(Value) ->
            {ok, gleam@dict:insert(Entries@1, Key, {entry, Generation, Membership, Value})}
        end)
    end), fun(Entries@1) ->
        gleam@result:'try'(gleam@list:try_fold(Only_b, Entries@1, fun(Entries@2, Pair) ->
            {Key, Entry} = Pair,
            gleam@result:'try'(Combine(Key, erlang:element(2, Entry), none, erlang:element(4, Entry)), fun(Value) ->
                {ok, gleam@dict:insert(Entries@2, Key, {entry, erlang:element(2, Entry), erlang:element(3, Entry), Value})}
            end)
        end), fun(Entries@2) ->
            {ok, {state, gleam@int:max(erlang:element(2, A), erlang:element(2, B)), Entries@2}}
        end)
    end).

-file("src/lattice_maps/internal/or_map_engine.gleam", 158).
-spec prune(state(JON), lattice_core@version_vector:version_vector()) -> state(JON).
-doc(false).
prune(State, Stable) ->
    {state, erlang:element(2, State), gleam@dict:map_values(erlang:element(3, State), fun(_, Entry) ->
        {entry, erlang:element(2, Entry), lattice_sets@or_set:prune(erlang:element(3, Entry), Stable), erlang:element(4, Entry)}
    end)}.

