-module(lattice_maps@internal@lww_map_engine).
-compile([no_auto_import, nowarn_ignored, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-export([new/0, check_timestamp/3, put/4, prune/2, merge/3]).
-export_type([provenance/0, entry/1, state/1, error/0]).
-moduledoc(false).

-type provenance() :: {modern, lattice_core@replica_id:replica_id()} | {legacy, binary()}.

-type entry(JEJ) :: {entry, gleam@option:option(JEJ), integer(), provenance()}.

-type state(JEK) :: {state, gleam@dict:dict(binary(), entry(JEK)), integer()}.

-type error() :: {timestamp_not_advanced, binary(), integer(), integer()} | {conflicting_write, binary(), integer()} | {invalid_timestamp, binary(), integer()}.

-file("src/lattice_maps/internal/lww_map_engine.gleam", 31).
-spec new() -> state(any()).
-doc(false).
new() ->
    {state, maps:new(), 0}.

-file("src/lattice_maps/internal/lww_map_engine.gleam", 35).
-spec check_timestamp(state(any()), binary(), integer()) -> {ok, nil} | {error, error()}.
-doc(false).
check_timestamp(State, Key, Timestamp) ->
    Existing_timestamp = case gleam_stdlib:map_get(erlang:element(2, State), Key) of
        {ok, Entry} ->
            erlang:element(3, Entry);

        {error, nil} ->
            erlang:element(3, State)
    end,
    Floor = gleam@int:max(Existing_timestamp, erlang:element(3, State)),
    case (Timestamp > 9007199254740991) orelse (Timestamp < -9007199254740991) of
        true ->
            {error, {invalid_timestamp, Key, Timestamp}};

        false ->
            case (Timestamp =< erlang:element(3, State)) orelse (Timestamp < Existing_timestamp) of
                true ->
                    {error, {timestamp_not_advanced, Key, Timestamp, Floor}};

                false ->
                    {ok, nil}
            end
    end.

-file("src/lattice_maps/internal/lww_map_engine.gleam", 106).
-spec choose_provenance(entry(JFJ), entry(JFJ)) -> entry(JFJ).
-doc(false).
choose_provenance(A, B) ->
    case {erlang:element(4, A), erlang:element(4, B)} of
        {{modern, _}, {legacy, _}} ->
            A;

        {{legacy, _}, {modern, _}} ->
            B;

        {{legacy, Ak}, {legacy, Bk}} ->
            case gleam@bit_array:compare(<<Ak/binary>>, <<Bk/binary>>) of
                lt ->
                    B;

                _ ->
                    A
            end;

        {{modern, Aw}, {modern, Bw}} ->
            case lattice_core@replica_id:compare(Aw, Bw) of
                lt ->
                    B;

                _ ->
                    A
            end
    end.

-file("src/lattice_maps/internal/lww_map_engine.gleam", 84).
-spec choose_equal_timestamp(binary(), entry(JFD), entry(JFD), fun((JFD, JFD) -> boolean())) -> {ok, entry(JFD)} | {error, error()}.
-doc(false).
choose_equal_timestamp(Key, A, B, Equal) ->
    case {erlang:element(2, A), erlang:element(2, B)} of
        {none, {some, _}} ->
            {ok, A};

        {{some, _}, none} ->
            {ok, B};

        {none, none} ->
            {ok, choose_provenance(A, B)};

        {{some, Av}, {some, Bv}} ->
            case {erlang:element(4, A), erlang:element(4, B)} of
                {{modern, Aw}, {modern, Bw}} when Aw =:= Bw ->
                    case Equal(Av, Bv) of
                        true ->
                            {ok, A};

                        false ->
                            {error, {conflicting_write, Key, erlang:element(3, A)}}
                    end;

                {_, _} ->
                    {ok, choose_provenance(A, B)}
            end
    end.

-file("src/lattice_maps/internal/lww_map_engine.gleam", 71).
-spec choose(binary(), entry(JEX), entry(JEX), fun((JEX, JEX) -> boolean())) -> {ok, entry(JEX)} | {error, error()}.
-doc(false).
choose(Key, A, B, Equal) ->
    case gleam@int:compare(erlang:element(3, A), erlang:element(3, B)) of
        gt ->
            {ok, A};

        lt ->
            {ok, B};

        eq ->
            choose_equal_timestamp(Key, A, B, Equal)
    end.

-file("src/lattice_maps/internal/lww_map_engine.gleam", 57).
-spec put(state(JER), binary(), entry(JER), fun((JER, JER) -> boolean())) -> {ok, state(JER)} | {error, error()}.
-doc(false).
put(State, Key, Entry, Equal) ->
    gleam@result:'try'(check_timestamp(State, Key, erlang:element(3, Entry)), fun(_) ->
        gleam@result:'try'(case gleam_stdlib:map_get(erlang:element(2, State), Key) of
            {ok, Current} ->
                choose(Key, Current, Entry, Equal);

            {error, nil} ->
                {ok, Entry}
        end, fun(Winner) ->
            {ok, {state, gleam@dict:insert(erlang:element(2, State), Key, Winner), erlang:element(3, State)}}
        end)
    end).

-file("src/lattice_maps/internal/lww_map_engine.gleam", 156).
-spec prune(state(JFT), integer()) -> state(JFT).
-doc(false).
prune(State, Stable) ->
    Floor = gleam@int:max(erlang:element(3, State), Stable),
    {state, gleam@dict:filter(erlang:element(2, State), fun(_, Entry) ->
        case erlang:element(2, Entry) of
            {some, _} ->
                true;

            none ->
                erlang:element(3, Entry) > Floor
        end
    end), Floor}.

-file("src/lattice_maps/internal/lww_map_engine.gleam", 123).
-spec merge(state(JFN), state(JFN), fun((JFN, JFN) -> boolean())) -> {ok, state(JFN)} | {error, error()}.
-doc(false).
merge(A, B, Equal) ->
    Keys = begin
        _pipe = maps:keys(erlang:element(2, A)),
        _pipe@1 = lists:append(_pipe, maps:keys(erlang:element(2, B))),
        gleam@list:unique(_pipe@1)
    end,
    gleam@result:'try'(gleam@list:try_fold(Keys, maps:new(), fun(Entries, Key) ->
        Winner = case {gleam_stdlib:map_get(erlang:element(2, A), Key), gleam_stdlib:map_get(erlang:element(2, B), Key)} of
            {{ok, A@1}, {ok, B@1}} ->
                _pipe@2 = choose(Key, A@1, B@1, Equal),
                gleam@result:map(_pipe@2, fun(_value) ->
                    {some, _value}
                end);

            {{ok, Entry}, {error, nil}} ->
                {ok, case erlang:element(3, Entry) > erlang:element(3, B) of
                    true ->
                        {some, Entry};

                    false ->
                        none
                end};

            {{error, nil}, {ok, Entry@1}} ->
                {ok, case erlang:element(3, Entry@1) > erlang:element(3, A) of
                    true ->
                        {some, Entry@1};

                    false ->
                        none
                end};

            {{error, nil}, {error, nil}} ->
                {ok, none}
        end,
        gleam@result:'try'(Winner, fun(Winner@1) ->
            {ok, case Winner@1 of
                {some, Entry@2} ->
                    gleam@dict:insert(Entries, Key, Entry@2);

                none ->
                    Entries
            end}
        end)
    end), fun(Entries) ->
        {ok, prune({state, Entries, gleam@int:max(erlang:element(3, A), erlang:element(3, B))}, 0)}
    end).

