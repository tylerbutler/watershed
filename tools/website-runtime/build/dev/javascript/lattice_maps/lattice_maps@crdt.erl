-module(lattice_maps@crdt).
-compile([no_auto_import, nowarn_ignored, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-export([type_name/1, spec_name/1, lww_new/2, or_new/2, default_crdt/2, matches_spec/2, default_delta/2, is_empty_delta/1, lww_bind/2, or_bind/2, bind/2, lww_merge_as/3, or_merge_as/3, merge/3, matches_delta/2, or_apply_delta/2, apply_delta/4, or_merge_deltas/2, merge_deltas/4, or_replica/1, or_spec/1, or_get/2, or_keys/1, or_values/1, or_value_count/1, or_empty_delta/1, or_update_delta/3, or_update_with_delta/3, or_remove_with_delta/2, or_prune/2, lww_replica/1, lww_spec/1, lww_get/2, lww_set/4, lww_update/4, lww_remove/3, lww_keys/1, lww_values/1, lww_tombstone_count/1, lww_pruned_timestamp/1, lww_prune/2, spec_to_json_with/2, spec_from_json_with/2, lww_to_json_with/2, or_to_json_with/2, to_json_with/2, to_json/1, lww_from_json_with/2, or_from_json_with/2, from_json_with/2, from_json/1, or_delta_to_json_with/2, delta_to_json_with/2, delta_to_json/1, or_delta_from_json_with/2, delta_from_json_with/2, delta_from_json/1, or_import_legacy/4, lww_import_legacy/3]).
-export_type([crdt/1, crdt_spec/1, crdt_delta/1, o_r_map/1, o_r_map_delta/1, l_w_w_map/1, merge_error/0, update_error/1, edit_context/0]).
-moduledoc(~" Typed recursive CRDT composition.

 Maps and dispatch share this module to keep the module graph acyclic.
 A map has one recursive child schema. Text has a concrete grapheme payload;
 the other parameterized leaves share the application's payload type.").

-type crdt(JVJ) :: {crdt_g_counter, lattice_counters@g_counter:g_counter()} | {crdt_pn_counter, lattice_counters@pn_counter:p_n_counter()} | {crdt_lww_register, lattice_registers@lww_register:l_w_w_register(JVJ)} | {crdt_mv_register, lattice_registers@mv_register:m_v_register(JVJ)} | {crdt_g_set, lattice_sets@g_set:g_set(JVJ)} | {crdt_two_p_set, lattice_sets@two_p_set:two_p_set(JVJ)} | {crdt_or_set, lattice_sets@or_set:o_r_set(JVJ)} | {crdt_version_vector, lattice_core@version_vector:version_vector()} | {crdt_sequence, lattice_sequence@sequence:sequence(JVJ)} | {crdt_text, lattice_text@text:text()} | {crdt_or_map, o_r_map(JVJ)} | {crdt_lww_map, l_w_w_map(JVJ)}.

-type crdt_spec(JVK) :: g_counter_spec | pn_counter_spec | {lww_register_spec, JVK} | mv_register_spec | g_set_spec | two_p_set_spec | or_set_spec | sequence_spec | text_spec | {or_map_spec, crdt_spec(JVK)} | {lww_map_spec, crdt_spec(JVK)}.

-type crdt_delta(JVL) :: {no_change, crdt_spec(JVL)} | {state_delta, crdt(JVL)} | {or_map_change, o_r_map_delta(JVL)}.

-opaque o_r_map(JVM) :: {o_r_map, lattice_core@replica_id:replica_id(), crdt_spec(JVM), lattice_maps@internal@or_map_engine:state(crdt(JVM))}.

-opaque o_r_map_delta(JVN) :: {o_r_map_delta, lattice_core@replica_id:replica_id(), crdt_spec(JVN), lattice_maps@internal@or_map_engine:state(crdt_delta(JVN))}.

-opaque l_w_w_map(JVO) :: {l_w_w_map, lattice_core@replica_id:replica_id(), crdt_spec(JVO), lattice_maps@internal@lww_map_engine:state(crdt(JVO))}.

-type merge_error() :: {type_mismatch, binary(), binary()} | schema_mismatch | {at_key, binary(), merge_error()} | {timestamp_not_advanced, binary(), integer(), integer()} | {conflicting_write, binary(), integer()} | {clock_exhausted, binary()} | {invalid_timestamp, binary(), integer()}.

-type update_error(JVP) :: {callback_error, JVP} | {composition_error, merge_error()}.

-type edit_context() :: {edit_context, lattice_core@replica_id:replica_id()}.

-file("src/lattice_maps/crdt.gleam", 230).
-spec type_name(crdt(any())) -> binary().
-doc(~" Return the dispatch discriminator.

 ## Examples

 ```gleam
 let state = crdt.default_crdt(crdt.TextSpec, replica_id.new(\"A\"))
 crdt.type_name(state) // -> \"text\"
 ```").
type_name(Value) ->
    case Value of
        {crdt_g_counter, _} ->
            ~"g_counter";

        {crdt_pn_counter, _} ->
            ~"pn_counter";

        {crdt_lww_register, _} ->
            ~"lww_register";

        {crdt_mv_register, _} ->
            ~"mv_register";

        {crdt_g_set, _} ->
            ~"g_set";

        {crdt_two_p_set, _} ->
            ~"two_p_set";

        {crdt_or_set, _} ->
            ~"or_set";

        {crdt_version_vector, _} ->
            ~"version_vector";

        {crdt_sequence, _} ->
            ~"sequence";

        {crdt_text, _} ->
            ~"text";

        {crdt_or_map, _} ->
            ~"or_map";

        {crdt_lww_map, _} ->
            ~"lww_map"
    end.

-file("src/lattice_maps/crdt.gleam", 256).
-spec spec_name(crdt_spec(any())) -> binary().
-doc(~" Return a schema's outer discriminator.

 This name alone does not identify a complete recursive schema or its defaults.

 ## Examples

 ```gleam
 crdt.spec_name(crdt.OrMapSpec(crdt.LwwRegisterSpec(42))) // -> \"or_map\"
 ```").
spec_name(Spec) ->
    case Spec of
        g_counter_spec ->
            ~"g_counter";

        pn_counter_spec ->
            ~"pn_counter";

        {lww_register_spec, _} ->
            ~"lww_register";

        mv_register_spec ->
            ~"mv_register";

        g_set_spec ->
            ~"g_set";

        two_p_set_spec ->
            ~"two_p_set";

        or_set_spec ->
            ~"or_set";

        sequence_spec ->
            ~"sequence";

        text_spec ->
            ~"text";

        {or_map_spec, _} ->
            ~"or_map";

        {lww_map_spec, _} ->
            ~"lww_map"
    end.

-file("src/lattice_maps/crdt.gleam", 862).
-spec lww_new(lattice_core@replica_id:replica_id(), crdt_spec(KAZ)) -> l_w_w_map(KAZ).
-doc(false).
lww_new(Replica, Spec) ->
    {l_w_w_map, Replica, Spec, lattice_maps@internal@lww_map_engine:new()}.

-file("src/lattice_maps/crdt.gleam", 604).
-spec or_new(lattice_core@replica_id:replica_id(), crdt_spec(JXZ)) -> o_r_map(JXZ).
-doc(false).
or_new(Replica, Spec) ->
    {o_r_map, Replica, Spec, lattice_maps@internal@or_map_engine:new()}.

-file("src/lattice_maps/crdt.gleam", 284).
-spec default_crdt(crdt_spec(JVU), lattice_core@replica_id:replica_id()) -> crdt(JVU).
-doc(~" Create a valid empty/default child for the configured schema.

 Maps start without entries; Sequence and Text start empty. A register uses
 its configured initial value at timestamp zero.

 ## Examples

 ```gleam
 let assert crdt.CrdtLwwRegister(register) =
   crdt.default_crdt(crdt.LwwRegisterSpec(42), replica_id.new(\"A\"))
 lww_register.value(register) // -> 42
 ```").
default_crdt(Spec, Replica) ->
    case Spec of
        g_counter_spec ->
            {crdt_g_counter, lattice_counters@g_counter:new(Replica)};

        pn_counter_spec ->
            {crdt_pn_counter, lattice_counters@pn_counter:new(Replica)};

        {lww_register_spec, Initial} ->
            {crdt_lww_register, lattice_registers@lww_register:new(Initial, 0, Replica)};

        mv_register_spec ->
            {crdt_mv_register, lattice_registers@mv_register:new(Replica)};

        g_set_spec ->
            {crdt_g_set, lattice_sets@g_set:new()};

        two_p_set_spec ->
            {crdt_two_p_set, lattice_sets@two_p_set:new()};

        or_set_spec ->
            {crdt_or_set, lattice_sets@or_set:new(Replica)};

        sequence_spec ->
            {crdt_sequence, lattice_sequence@sequence:new(Replica)};

        text_spec ->
            {crdt_text, lattice_text@text:new(Replica)};

        {or_map_spec, Child} ->
            {crdt_or_map, or_new(Replica, Child)};

        {lww_map_spec, Child@1} ->
            {crdt_lww_map, lww_new(Replica, Child@1)}
    end.

-file("src/lattice_maps/crdt.gleam", 314).
-spec matches_spec(crdt(JVX), crdt_spec(JVX)) -> boolean().
-doc(~" Check complete recursive schema agreement.

 ## Examples

 ```gleam
 let state = crdt.default_crdt(
   crdt.OrMapSpec(crdt.LwwRegisterSpec(42)), replica_id.new(\"A\"),
 )
 crdt.matches_spec(state, crdt.OrMapSpec(crdt.LwwRegisterSpec(42)))
 // -> True
 crdt.matches_spec(state, crdt.OrMapSpec(crdt.LwwRegisterSpec(0)))
 // -> False
 ```").
matches_spec(Value, Spec) ->
    case {Value, Spec} of
        {{crdt_or_map, Map}, {or_map_spec, Child}} ->
            erlang:element(3, Map) =:= Child;

        {{crdt_lww_map, Map@1}, {lww_map_spec, Child@1}} ->
            erlang:element(3, Map@1) =:= Child@1;

        {_, _} ->
            type_name(Value) =:= spec_name(Spec)
    end.

-file("src/lattice_maps/crdt.gleam", 322).
-spec check_spec(crdt(JWA), crdt_spec(JWA)) -> {ok, nil} | {error, merge_error()}.
check_spec(Value, Spec) ->
    gleam@bool:guard(matches_spec(Value, Spec), {ok, nil}, fun() ->
        case type_name(Value) =:= spec_name(Spec) of
            true ->
                {error, schema_mismatch};

            false ->
                {error, {type_mismatch, spec_name(Spec), type_name(Value)}}
        end
    end).

-file("src/lattice_maps/crdt.gleam", 330).
-spec same_spec(crdt_spec(JWF), crdt_spec(JWF)) -> {ok, nil} | {error, merge_error()}.
same_spec(A, B) ->
    gleam@bool:guard(A =:= B, {ok, nil}, fun() ->
        case spec_name(A) =:= spec_name(B) of
            true ->
                {error, schema_mismatch};

            false ->
                {error, {type_mismatch, spec_name(A), spec_name(B)}}
        end
    end).

-file("src/lattice_maps/crdt.gleam", 348).
-spec default_delta(crdt_spec(JWK), lattice_core@replica_id:replica_id()) -> crdt_delta(JWK).
-doc(~" The delta identity is explicit; configured initial values are not bottoms.

 The replica argument does not affect `NoChange`. It is not an authored write.

 ## Examples

 ```gleam
 crdt.default_delta(crdt.LwwRegisterSpec(42), replica_id.new(\"A\"))
 // -> crdt.NoChange(crdt.LwwRegisterSpec(42))
 ```").
default_delta(Spec, _) ->
    {no_change, Spec}.

-file("src/lattice_maps/crdt.gleam", 362).
-spec is_empty_delta(crdt_delta(any())) -> boolean().
-doc(~" Return whether this delta has no leaf or membership changes.

 A `StateDelta` is not treated as empty, even if its child looks like a default.
 An ORMap update that returns `NoChange` still refreshes outer membership.

 ## Examples

 ```gleam
 crdt.is_empty_delta(crdt.NoChange(crdt.LwwRegisterSpec(42))) // -> True
 ```").
is_empty_delta(Value) ->
    case Value of
        {no_change, _} ->
            true;

        {or_map_change, Delta} ->
            gleam@dict:is_empty(erlang:element(3, erlang:element(4, Delta))) andalso (erlang:element(2, erlang:element(4, Delta)) =:= 0);

        {state_delta, _} ->
            false
    end.

-file("src/lattice_maps/crdt.gleam", 877).
-spec lww_bind(l_w_w_map(KBH), lattice_core@replica_id:replica_id()) -> l_w_w_map(KBH).
-doc(false).
lww_bind(Map, Replica) ->
    {l_w_w_map, Replica, erlang:element(3, Map), erlang:element(4, Map)}.

-file("src/lattice_maps/crdt.gleam", 562).
-spec generation_parts(lattice_maps@internal@or_map_engine:generation()) -> list(binary()).
generation_parts(Generation) ->
    case Generation of
        initial ->
            [~"initial"];

        {generation, Clock, Creator} ->
            [~"generation", erlang:integer_to_binary(Clock), lattice_core@replica_id:to_string(Creator)]
    end.

-file("src/lattice_maps/crdt.gleam", 550).
-spec frame(binary()) -> binary().
frame(Value) ->
    <<<<(erlang:integer_to_binary(erlang:byte_size(Value)))/binary, ":"/utf8>>/binary, Value/binary>>.

-file("src/lattice_maps/crdt.gleam", 554).
-spec scope(lattice_core@replica_id:replica_id(), list(binary())) -> lattice_core@replica_id:replica_id().
scope(Replica, Parts) ->
    lattice_core@replica_id:new(<<<<"lattice-map:"/utf8, (frame(lattice_core@replica_id:to_string(Replica)))/binary>>/binary, (erlang:list_to_binary(gleam@list:map(Parts, fun frame/1)))/binary>>).

-file("src/lattice_maps/crdt.gleam", 573).
-spec or_identity(lattice_core@replica_id:replica_id(), binary(), lattice_maps@internal@or_map_engine:generation()) -> lattice_core@replica_id:replica_id().
or_identity(Replica, Key, Generation) ->
    scope(Replica, [~"or", Key | generation_parts(Generation)]).

-file("src/lattice_maps/crdt.gleam", 581).
-spec membership_identity(lattice_core@replica_id:replica_id(), binary(), lattice_maps@internal@or_map_engine:generation()) -> lattice_core@replica_id:replica_id().
membership_identity(Replica, Key, Generation) ->
    scope(Replica, [~"or-membership", Key | generation_parts(Generation)]).

-file("src/lattice_maps/crdt.gleam", 642).
-spec option_bind(gleam@option:option(crdt(JYK)), lattice_core@replica_id:replica_id()) -> gleam@option:option(crdt(JYK)).
option_bind(Value, Replica) ->
    case Value of
        {some, Value@1} ->
            {some, bind(Value@1, Replica)};

        none ->
            none
    end.

-file("src/lattice_maps/crdt.gleam", 619).
-spec or_bind(o_r_map(JYH), lattice_core@replica_id:replica_id()) -> o_r_map(JYH).
-doc(false).
or_bind(Map, Replica) ->
    {o_r_map, Replica, erlang:element(3, Map), begin
        _record = erlang:element(4, Map),
        {state, erlang:element(2, _record), gleam@dict:map_values(erlang:element(3, erlang:element(4, Map)), fun(Key, Entry) ->
            {entry, erlang:element(2, Entry), lattice_sets@or_set:merge(lattice_sets@or_set:new(membership_identity(Replica, Key, erlang:element(2, Entry))), erlang:element(3, Entry)), option_bind(erlang:element(4, Entry), or_identity(Replica, Key, erlang:element(2, Entry)))}
        end)}
    end}.

-file("src/lattice_maps/crdt.gleam", 384).
-spec bind(crdt(JWP), lattice_core@replica_id:replica_id()) -> crdt(JWP).
-doc(~" Bind local editing identity without changing historical IDs or write authors.

 Use this after loading or adopting a remote state. It does not author a new
 LWWRegister write; use `lww_register.set` for that operation.

 ## Examples

 ```gleam
 let original = crdt.CrdtLwwRegister(
   lww_register.new(\"Old write\", 1, replica_id.new(\"A\")),
 )
 crdt.bind(original, replica_id.new(\"B\")) // -> original
 ```").
bind(Value, Replica) ->
    case Value of
        {crdt_g_counter, C} ->
            {crdt_g_counter, lattice_counters@g_counter:merge(lattice_counters@g_counter:new(Replica), C)};

        {crdt_pn_counter, C@1} ->
            {crdt_pn_counter, lattice_counters@pn_counter:merge(lattice_counters@pn_counter:new(Replica), C@1)};

        {crdt_mv_register, C@2} ->
            {crdt_mv_register, lattice_registers@mv_register:merge(lattice_registers@mv_register:new(Replica), C@2)};

        {crdt_or_set, C@3} ->
            {crdt_or_set, lattice_sets@or_set:merge(lattice_sets@or_set:new(Replica), C@3)};

        {crdt_sequence, C@4} ->
            {crdt_sequence, lattice_sequence@sequence:bind(C@4, Replica)};

        {crdt_text, C@5} ->
            {crdt_text, lattice_text@text:bind(C@5, Replica)};

        {crdt_or_map, C@6} ->
            {crdt_or_map, or_bind(C@6, Replica)};

        {crdt_lww_map, C@7} ->
            {crdt_lww_map, lww_bind(C@7, Replica)};

        {crdt_lww_register, _} ->
            Value;

        {crdt_g_set, _} ->
            Value;

        {crdt_two_p_set, _} ->
            Value;

        {crdt_version_vector, _} ->
            Value
    end.

-file("src/lattice_maps/crdt.gleam", 881).
-spec lww_error(lattice_maps@internal@lww_map_engine:error()) -> merge_error().
lww_error(Error) ->
    case Error of
        {timestamp_not_advanced, Key, Timestamp, Floor} ->
            {timestamp_not_advanced, Key, Timestamp, Floor};

        {conflicting_write, Key@1, Timestamp@1} ->
            {conflicting_write, Key@1, Timestamp@1};

        {invalid_timestamp, Key@2, Timestamp@2} ->
            {invalid_timestamp, Key@2, Timestamp@2}
    end.

-file("src/lattice_maps/crdt.gleam", 1002).
-spec lww_merge_as(l_w_w_map(KCZ), l_w_w_map(KCZ), lattice_core@replica_id:replica_id()) -> {ok, l_w_w_map(KCZ)} | {error, merge_error()}.
-doc(false).
lww_merge_as(A, B, Replica) ->
    gleam@result:'try'(same_spec(erlang:element(3, A), erlang:element(3, B)), fun(_) ->
        gleam@result:'try'(begin
            _pipe = lattice_maps@internal@lww_map_engine:merge(erlang:element(4, A), erlang:element(4, B), fun(A@1, B@1) ->
                A@1 =:= B@1
            end),
            gleam@result:map_error(_pipe, fun lww_error/1)
        end, fun(State) ->
            {ok, {l_w_w_map, Replica, erlang:element(3, A), State}}
        end)
    end).

-file("src/lattice_maps/crdt.gleam", 779).
-spec or_merge_as(o_r_map(KAE), o_r_map(KAE), lattice_core@replica_id:replica_id()) -> {ok, o_r_map(KAE)} | {error, merge_error()}.
-doc(false).
or_merge_as(A, B, Replica) ->
    gleam@result:'try'(same_spec(erlang:element(3, A), erlang:element(3, B)), fun(_) ->
        gleam@result:'try'(lattice_maps@internal@or_map_engine:join(erlang:element(4, A), erlang:element(4, B), fun(Key, Generation, Left, Right) ->
            Identity = or_identity(Replica, Key, Generation),
            Value = case {Left, Right} of
                {{some, A@1}, {some, B@1}} ->
                    _pipe = merge(A@1, B@1, Identity),
                    gleam@result:map(_pipe, fun(_value) ->
                        {some, _value}
                    end);

                {{some, A@2}, none} ->
                    {ok, {some, bind(A@2, Identity)}};

                {none, {some, B@2}} ->
                    {ok, {some, bind(B@2, Identity)}};

                {none, none} ->
                    {ok, none}
            end,
            gleam@result:map_error(Value, fun(_capture) ->
                {at_key, Key, _capture}
            end)
        end), fun(State) ->
            {ok, or_bind({o_r_map, Replica, erlang:element(3, A), State}, Replica)}
        end)
    end).

-file("src/lattice_maps/crdt.gleam", 420).
-spec merge(crdt(JWS), crdt(JWS), lattice_core@replica_id:replica_id()) -> {ok, crdt(JWS)} | {error, merge_error()}.
-doc(~" Merge states with an explicit receiving identity, including incoming-only children.

 ORMaps join children within the winning generation. LWWMaps select atomic
 child assignments instead. Different variants or recursive schemas return
 `Error`; a mismatch is never replaced by a default state.

 ## Examples

 ```gleam
 let a = crdt.default_crdt(
   crdt.OrMapSpec(crdt.TextSpec), replica_id.new(\"A\"),
 )
 let b = crdt.default_crdt(
   crdt.OrMapSpec(crdt.TextSpec), replica_id.new(\"B\"),
 )
 let local = replica_id.new(\"C\")
 let assert Ok(crdt.CrdtOrMap(merged)) = crdt.merge(a, b, local)
 or_map.replica_id(merged) // -> local
 ```").
merge(A, B, Replica) ->
    Merged = case {A, B} of
        {{crdt_g_counter, A@1}, {crdt_g_counter, B@1}} ->
            {ok, {crdt_g_counter, lattice_counters@g_counter:merge(A@1, B@1)}};

        {{crdt_pn_counter, A@2}, {crdt_pn_counter, B@2}} ->
            {ok, {crdt_pn_counter, lattice_counters@pn_counter:merge(A@2, B@2)}};

        {{crdt_lww_register, A@3}, {crdt_lww_register, B@3}} ->
            {ok, {crdt_lww_register, lattice_registers@lww_register:merge(A@3, B@3)}};

        {{crdt_mv_register, A@4}, {crdt_mv_register, B@4}} ->
            {ok, {crdt_mv_register, lattice_registers@mv_register:merge(A@4, B@4)}};

        {{crdt_g_set, A@5}, {crdt_g_set, B@5}} ->
            {ok, {crdt_g_set, lattice_sets@g_set:merge(A@5, B@5)}};

        {{crdt_two_p_set, A@6}, {crdt_two_p_set, B@6}} ->
            {ok, {crdt_two_p_set, lattice_sets@two_p_set:merge(A@6, B@6)}};

        {{crdt_or_set, A@7}, {crdt_or_set, B@7}} ->
            {ok, {crdt_or_set, lattice_sets@or_set:merge(A@7, B@7)}};

        {{crdt_version_vector, A@8}, {crdt_version_vector, B@8}} ->
            {ok, {crdt_version_vector, lattice_core@version_vector:merge(A@8, B@8)}};

        {{crdt_sequence, A@9}, {crdt_sequence, B@9}} ->
            {ok, {crdt_sequence, lattice_sequence@sequence:merge(A@9, B@9, Replica)}};

        {{crdt_text, A@10}, {crdt_text, B@10}} ->
            {ok, {crdt_text, lattice_text@text:merge(A@10, B@10, Replica)}};

        {{crdt_or_map, A@11}, {crdt_or_map, B@11}} ->
            _pipe = or_merge_as(A@11, B@11, Replica),
            gleam@result:map(_pipe, fun(_value) ->
                {crdt_or_map, _value}
            end);

        {{crdt_lww_map, A@12}, {crdt_lww_map, B@12}} ->
            _pipe@1 = lww_merge_as(A@12, B@12, Replica),
            gleam@result:map(_pipe@1, fun(_value@1) ->
                {crdt_lww_map, _value@1}
            end);

        {_, _} ->
            {error, {type_mismatch, type_name(A), type_name(B)}}
    end,
    gleam@result:map(Merged, fun(_capture) ->
        bind(_capture, Replica)
    end).

-file("src/lattice_maps/crdt.gleam", 459).
-spec matches_delta(crdt_delta(JWY), crdt_spec(JWY)) -> boolean().
-doc(~" Validate a delta against the complete child schema.

 ## Examples

 ```gleam
 let delta = crdt.NoChange(crdt.LwwRegisterSpec(42))
 crdt.matches_delta(delta, crdt.LwwRegisterSpec(42)) // -> True
 crdt.matches_delta(delta, crdt.LwwRegisterSpec(0)) // -> False
 ```").
matches_delta(Delta, Spec) ->
    case Delta of
        {no_change, Given} ->
            Given =:= Spec;

        {state_delta, Value} ->
            matches_spec(Value, Spec);

        {or_map_change, Delta@1} ->
            Spec =:= {or_map_spec, erlang:element(3, Delta@1)}
    end.

-file("src/lattice_maps/crdt.gleam", 467).
-spec check_delta(crdt_delta(JXB), crdt_spec(JXB)) -> {ok, nil} | {error, merge_error()}.
check_delta(Delta, Spec) ->
    case Delta of
        {no_change, Given} ->
            same_spec(Spec, Given);

        {state_delta, Value} ->
            check_spec(Value, Spec);

        {or_map_change, Delta@1} ->
            same_spec(Spec, {or_map_spec, erlang:element(3, Delta@1)})
    end.

-file("src/lattice_maps/crdt.gleam", 589).
-spec map_default(crdt_spec(JXW), lattice_core@replica_id:replica_id()) -> crdt(JXW).
map_default(Spec, Identity) ->
    case Spec of
        {lww_register_spec, Initial} ->
            {crdt_lww_register, lattice_registers@lww_register:new(Initial, 0, lattice_core@replica_id:new(~"lattice-map:default"))};

        _ ->
            default_crdt(Spec, Identity)
    end.

-file("src/lattice_maps/crdt.gleam", 801).
-spec or_apply_delta(o_r_map(KAK), o_r_map_delta(KAK)) -> {ok, o_r_map(KAK)} | {error, merge_error()}.
-doc(false).
or_apply_delta(Map, Delta) ->
    gleam@result:'try'(same_spec(erlang:element(3, Map), erlang:element(3, Delta)), fun(_) ->
        gleam@result:'try'(lattice_maps@internal@or_map_engine:join(erlang:element(4, Map), erlang:element(4, Delta), fun(Key, Generation, Left, Right) ->
            Identity = or_identity(erlang:element(2, Map), Key, Generation),
            Value = case {Left, Right} of
                {none, {some, {state_delta, Value@1}}} ->
                    gleam@result:'try'(check_spec(Value@1, erlang:element(3, Map)), fun(_) ->
                        {ok, {some, bind(Value@1, Identity)}}
                    end);

                {_, {some, Change}} ->
                    Baseline = case Left of
                        {some, Value@2} ->
                            Value@2;

                        none ->
                            map_default(erlang:element(3, Map), Identity)
                    end,
                    _pipe = apply_delta(Baseline, Change, erlang:element(3, Map), Identity),
                    gleam@result:map(_pipe, fun(_value) ->
                        {some, _value}
                    end);

                {{some, Value@3}, none} ->
                    {ok, {some, bind(Value@3, Identity)}};

                {none, none} ->
                    {ok, none}
            end,
            gleam@result:map_error(Value, fun(_capture) ->
                {at_key, Key, _capture}
            end)
        end), fun(State) ->
            {ok, or_bind({o_r_map, erlang:element(2, Map), erlang:element(3, Map), State}, erlang:element(2, Map))}
        end)
    end).

-file("src/lattice_maps/crdt.gleam", 496).
-spec apply_delta(crdt(JXG), crdt_delta(JXG), crdt_spec(JXG), lattice_core@replica_id:replica_id()) -> {ok, crdt(JXG)} | {error, merge_error()}.
-doc(~" Apply a typed change without trusting a caller-supplied replacement state.

 The current state and the delta must both match `spec`. The returned state is
 bound to `replica`; nested ORMap changes retain their generation checks.

 ## Examples

 ```gleam
 let local = replica_id.new(\"A\")
 let before = sequence.new(local)
 let assert Ok(#(after, change)) =
   sequence.insert_with_delta(before, 0, 42)
 crdt.apply_delta(
   crdt.CrdtSequence(before), crdt.StateDelta(crdt.CrdtSequence(change)),
   crdt.SequenceSpec, local,
 )
 // -> Ok(crdt.CrdtSequence(after))
 ```").
apply_delta(Value, Delta, Spec, Replica) ->
    gleam@result:'try'(check_spec(Value, Spec), fun(_) ->
        gleam@result:'try'(check_delta(Delta, Spec), fun(_) ->
            case {Delta, Value} of
                {{no_change, _}, _} ->
                    {ok, bind(Value, Replica)};

                {{state_delta, Change}, _} ->
                    merge(Value, Change, Replica);

                {{or_map_change, Change@1}, {crdt_or_map, Map}} ->
                    _pipe = or_apply_delta(or_bind(Map, Replica), Change@1),
                    gleam@result:map(_pipe, fun(_value) ->
                        {crdt_or_map, _value}
                    end);

                {{or_map_change, _}, _} ->
                    {error, {type_mismatch, ~"or_map", type_name(Value)}}
            end
        end)
    end).

-file("src/lattice_maps/crdt.gleam", 831).
-spec or_merge_deltas(o_r_map_delta(KAQ), o_r_map_delta(KAQ)) -> {ok, o_r_map_delta(KAQ)} | {error, merge_error()}.
-doc(false).
or_merge_deltas(A, B) ->
    gleam@result:'try'(same_spec(erlang:element(3, A), erlang:element(3, B)), fun(_) ->
        gleam@result:'try'(lattice_maps@internal@or_map_engine:join(erlang:element(4, A), erlang:element(4, B), fun(Key, Generation, Left, Right) ->
            Value = case {Left, Right} of
                {{some, A_delta}, {some, B_delta}} ->
                    _pipe = merge_deltas(A_delta, B_delta, erlang:element(3, A), or_identity(erlang:element(2, A), Key, Generation)),
                    gleam@result:map(_pipe, fun(_value) ->
                        {some, _value}
                    end);

                {{some, Value@1}, none} ->
                    {ok, {some, Value@1}};

                {none, {some, Value@1}} ->
                    {ok, {some, Value@1}};

                {none, none} ->
                    {ok, none}
            end,
            gleam@result:map_error(Value, fun(_capture) ->
                {at_key, Key, _capture}
            end)
        end), fun(State) ->
            {ok, {o_r_map_delta, erlang:element(2, A), erlang:element(3, A), State}}
        end)
    end).

-file("src/lattice_maps/crdt.gleam", 530).
-spec merge_deltas(crdt_delta(JXN), crdt_delta(JXN), crdt_spec(JXN), lattice_core@replica_id:replica_id()) -> {ok, crdt_delta(JXN)} | {error, merge_error()}.
-doc(~" Batch sparse ORMap changes without expanding them to child snapshots.

 A batch that includes an explicit `StateDelta` snapshot may remain a snapshot.

 ## Examples

 ```gleam
 let local = replica_id.new(\"A\")
 let map = or_map.new(local, crdt.LwwRegisterSpec(42))
 let assert Ok(#(_, change)) =
   or_map.update_with_delta(map, \"answer\", fn(value) { value })
 let schema = crdt.OrMapSpec(crdt.LwwRegisterSpec(42))
 crdt.merge_deltas(
   crdt.NoChange(schema), crdt.OrMapChange(change), schema, local,
 )
 // -> Ok(crdt.OrMapChange(change))
 ```").
merge_deltas(A, B, Spec, Replica) ->
    gleam@result:'try'(check_delta(A, Spec), fun(_) ->
        gleam@result:'try'(check_delta(B, Spec), fun(_) ->
            case {A, B} of
                {{no_change, _}, _} ->
                    {ok, B};

                {_, {no_change, _}} ->
                    {ok, A};

                {{or_map_change, A@1}, {or_map_change, B@1}} ->
                    _pipe = or_merge_deltas(A@1, B@1),
                    gleam@result:map(_pipe, fun(_value) ->
                        {or_map_change, _value}
                    end);

                {{state_delta, A@2}, Other} ->
                    _pipe@1 = apply_delta(A@2, Other, Spec, Replica),
                    gleam@result:map(_pipe@1, fun(_value@1) ->
                        {state_delta, _value@1}
                    end);

                {Other@1, {state_delta, B@2}} ->
                    _pipe@2 = apply_delta(B@2, Other@1, Spec, Replica),
                    gleam@result:map(_pipe@2, fun(_value@2) ->
                        {state_delta, _value@2}
                    end)
            end
        end)
    end).

-file("src/lattice_maps/crdt.gleam", 609).
-spec or_replica(o_r_map(any())) -> lattice_core@replica_id:replica_id().
-doc(false).
or_replica(Map) ->
    erlang:element(2, Map).

-file("src/lattice_maps/crdt.gleam", 614).
-spec or_spec(o_r_map(JYE)) -> crdt_spec(JYE).
-doc(false).
or_spec(Map) ->
    erlang:element(3, Map).

-file("src/lattice_maps/crdt.gleam", 653).
-spec or_get(o_r_map(JYP), binary()) -> {ok, crdt(JYP)} | {error, nil}.
-doc(false).
or_get(Map, Key) ->
    gleam@result:'try'(gleam_stdlib:map_get(erlang:element(3, erlang:element(4, Map)), Key), fun(Entry) ->
        case {lattice_maps@internal@or_map_engine:active(Entry, Key), erlang:element(4, Entry)} of
            {true, {some, Value}} ->
                {ok, bind(Value, or_identity(erlang:element(2, Map), Key, erlang:element(2, Entry)))};

            {_, _} ->
                {error, nil}
        end
    end).

-file("src/lattice_maps/crdt.gleam", 663).
-spec or_keys(o_r_map(any())) -> list(binary()).
-doc(false).
or_keys(Map) ->
    gleam@dict:fold(erlang:element(3, erlang:element(4, Map)), [], fun(Keys, Key, Entry) ->
        case {lattice_maps@internal@or_map_engine:active(Entry, Key), erlang:element(4, Entry)} of
            {true, {some, _}} ->
                [Key | Keys];

            {_, _} ->
                Keys
        end
    end).

-file("src/lattice_maps/crdt.gleam", 673).
-spec or_values(o_r_map(JYX)) -> list(crdt(JYX)).
-doc(false).
or_values(Map) ->
    gleam@list:filter_map(or_keys(Map), fun(_capture) ->
        or_get(Map, _capture)
    end).

-file("src/lattice_maps/crdt.gleam", 678).
-spec or_value_count(o_r_map(any())) -> integer().
-doc(false).
or_value_count(Map) ->
    gleam@dict:fold(erlang:element(3, erlang:element(4, Map)), 0, fun(Count, _, Entry) ->
        case erlang:element(4, Entry) of
            {some, _} ->
                Count + 1;

            none ->
                Count
        end
    end).

-file("src/lattice_maps/crdt.gleam", 688).
-spec or_empty_delta(o_r_map(JZD)) -> o_r_map_delta(JZD).
-doc(false).
or_empty_delta(Map) ->
    {o_r_map_delta, erlang:element(2, Map), erlang:element(3, Map), lattice_maps@internal@or_map_engine:new()}.

-file("src/lattice_maps/crdt.gleam", 693).
-spec or_update_delta(o_r_map(JZG), binary(), fun((crdt(JZG), edit_context()) -> {ok, crdt_delta(JZG)} | {error, JZK})) -> {ok, {o_r_map(JZG), o_r_map_delta(JZG)}} | {error, update_error(JZK)}.
-doc(false).
or_update_delta(Map, Key, Callback) ->
    Needs_generation = case gleam_stdlib:map_get(erlang:element(3, erlang:element(4, Map)), Key) of
        {ok, Entry} ->
            not lattice_maps@internal@or_map_engine:active(Entry, Key);

        {error, nil} ->
            false
    end,
    gleam@bool:guard(Needs_generation andalso (erlang:element(2, erlang:element(4, Map)) >= 9007199254740991), {error, {composition_error, {clock_exhausted, Key}}}, fun() ->
        Entry@1 = lattice_maps@internal@or_map_engine:prepare(erlang:element(4, Map), Key, erlang:element(2, Map)),
        Identity = or_identity(erlang:element(2, Map), Key, erlang:element(2, Entry@1)),
        Current = case erlang:element(4, Entry@1) of
            {some, Value} ->
                bind(Value, Identity);

            none ->
                map_default(erlang:element(3, Map), Identity)
        end,
        gleam@result:'try'(begin
            _pipe = Callback(Current, {edit_context, Identity}),
            gleam@result:map_error(_pipe, fun(_value) ->
                {callback_error, _value}
            end)
        end, fun(Change) ->
            gleam@result:'try'(begin
                _pipe@1 = check_delta(Change, erlang:element(3, Map)),
                gleam@result:map_error(_pipe@1, fun(Error) ->
                    {composition_error, {at_key, Key, Error}}
                end)
            end, fun(_) ->
                gleam@result:'try'(begin
                    _pipe@2 = case {erlang:element(4, Entry@1), erlang:element(3, Map)} of
                        {none, {lww_register_spec, _}} ->
                            _pipe@3 = apply_delta(Current, Change, erlang:element(3, Map), Identity),
                            gleam@result:map(_pipe@3, fun(_value@1) ->
                                {state_delta, _value@1}
                            end);

                        {_, _} ->
                            {ok, Change}
                    end,
                    gleam@result:map_error(_pipe@2, fun(Error) ->
                        {composition_error, {at_key, Key, Error}}
                    end)
                end, fun(Change@1) ->
                    Membership = lattice_sets@or_set:merge(lattice_sets@or_set:new(membership_identity(erlang:element(2, Map), Key, erlang:element(2, Entry@1))), erlang:element(3, Entry@1)),
                    {_, Membership_delta} = lattice_sets@or_set:add_with_delta(Membership, Key),
                    Delta = {o_r_map_delta, erlang:element(2, Map), erlang:element(3, Map), lattice_maps@internal@or_map_engine:singleton(Key, {entry, erlang:element(2, Entry@1), Membership_delta, {some, Change@1}}, erlang:element(2, erlang:element(4, Map)))},
                    gleam@result:'try'(begin
                        _pipe@4 = or_apply_delta(Map, Delta),
                        gleam@result:map_error(_pipe@4, fun(_value@2) ->
                            {composition_error, _value@2}
                        end)
                    end, fun(Updated) ->
                        {ok, {Updated, Delta}}
                    end)
                end)
            end)
        end)
    end).

-file("src/lattice_maps/crdt.gleam", 753).
-spec or_update_with_delta(o_r_map(JZS), binary(), fun((crdt(JZS)) -> crdt(JZS))) -> {ok, {o_r_map(JZS), o_r_map_delta(JZS)}} | {error, merge_error()}.
-doc(false).
or_update_with_delta(Map, Key, Callback) ->
    Outcome = or_update_delta(Map, Key, fun(Value, _) ->
        {ok, {state_delta, Callback(Value)}}
    end),
    case Outcome of
        {ok, Value} ->
            {ok, Value};

        {error, {composition_error, {at_key, _, {type_mismatch, Expected, Found}}}} ->
            {error, {type_mismatch, Expected, Found}};

        {error, {composition_error, Error}} ->
            {error, Error};

        {error, {callback_error, Error@1}} ->
            {error, Error@1}
    end.

-file("src/lattice_maps/crdt.gleam", 770).
-spec or_remove_with_delta(o_r_map(KAA), binary()) -> {o_r_map(KAA), o_r_map_delta(KAA)}.
-doc(false).
or_remove_with_delta(Map, Key) ->
    {State, Delta} = lattice_maps@internal@or_map_engine:remove(erlang:element(4, Map), Key),
    {{o_r_map, erlang:element(2, Map), erlang:element(3, Map), State}, {o_r_map_delta, erlang:element(2, Map), erlang:element(3, Map), Delta}}.

-file("src/lattice_maps/crdt.gleam", 857).
-spec or_prune(o_r_map(KAW), lattice_core@version_vector:version_vector()) -> o_r_map(KAW).
-doc(false).
or_prune(Map, Stable) ->
    {o_r_map, erlang:element(2, Map), erlang:element(3, Map), lattice_maps@internal@or_map_engine:prune(erlang:element(4, Map), Stable)}.

-file("src/lattice_maps/crdt.gleam", 867).
-spec lww_replica(l_w_w_map(any())) -> lattice_core@replica_id:replica_id().
-doc(false).
lww_replica(Map) ->
    erlang:element(2, Map).

-file("src/lattice_maps/crdt.gleam", 872).
-spec lww_spec(l_w_w_map(KBE)) -> crdt_spec(KBE).
-doc(false).
lww_spec(Map) ->
    erlang:element(3, Map).

-file("src/lattice_maps/crdt.gleam", 891).
-spec lww_get(l_w_w_map(KBK), binary()) -> {ok, crdt(KBK)} | {error, nil}.
-doc(false).
lww_get(Map, Key) ->
    case gleam_stdlib:map_get(erlang:element(2, erlang:element(4, Map)), Key) of
        {ok, {entry, {some, Value}, Timestamp, _}} ->
            {ok, bind(Value, scope(erlang:element(2, Map), [~"lww-view", Key, erlang:integer_to_binary(Timestamp)]))};

        _ ->
            {error, nil}
    end.

-file("src/lattice_maps/crdt.gleam", 903).
-spec lww_set(l_w_w_map(KBP), binary(), crdt(KBP), integer()) -> {ok, l_w_w_map(KBP)} | {error, merge_error()}.
-doc(false).
lww_set(Map, Key, Value, Timestamp) ->
    gleam@result:'try'(begin
        _pipe = check_spec(Value, erlang:element(3, Map)),
        gleam@result:map_error(_pipe, fun(_capture) ->
            {at_key, Key, _capture}
        end)
    end, fun(_) ->
        Value@1 = case Value of
            {crdt_or_map, Child} ->
                {crdt_or_map, or_bind(Child, erlang:element(2, Child))};

            Other ->
                Other
        end,
        gleam@result:'try'(begin
            _pipe@1 = lattice_maps@internal@lww_map_engine:put(erlang:element(4, Map), Key, {entry, {some, Value@1}, Timestamp, {modern, erlang:element(2, Map)}}, fun(A, B) ->
                A =:= B
            end),
            gleam@result:map_error(_pipe@1, fun lww_error/1)
        end, fun(State) ->
            {ok, {l_w_w_map, erlang:element(2, Map), erlang:element(3, Map), State}}
        end)
    end).

-file("src/lattice_maps/crdt.gleam", 931).
-spec lww_update(l_w_w_map(KBV), binary(), integer(), fun((crdt(KBV), edit_context()) -> {ok, crdt(KBV)} | {error, KBZ})) -> {ok, l_w_w_map(KBV)} | {error, update_error(KBZ)}.
-doc(false).
lww_update(Map, Key, Timestamp, Callback) ->
    gleam@result:'try'(begin
        _pipe = lattice_maps@internal@lww_map_engine:check_timestamp(erlang:element(4, Map), Key, Timestamp),
        gleam@result:map_error(_pipe, fun(Error) ->
            {composition_error, lww_error(Error)}
        end)
    end, fun(_) ->
        Identity = scope(erlang:element(2, Map), [~"lww-write", Key, erlang:integer_to_binary(Timestamp)]),
        Current = case gleam_stdlib:map_get(erlang:element(2, erlang:element(4, Map)), Key) of
            {ok, {entry, {some, Value}, _, _}} ->
                bind(Value, Identity);

            _ ->
                default_crdt(erlang:element(3, Map), Identity)
        end,
        gleam@result:'try'(begin
            _pipe@1 = Callback(Current, {edit_context, Identity}),
            gleam@result:map_error(_pipe@1, fun(_value) ->
                {callback_error, _value}
            end)
        end, fun(Value@1) ->
            _pipe@2 = lww_set(Map, Key, Value@1, Timestamp),
            gleam@result:map_error(_pipe@2, fun(_value@1) ->
                {composition_error, _value@1}
            end)
        end)
    end).

-file("src/lattice_maps/crdt.gleam", 954).
-spec lww_remove(l_w_w_map(KCG), binary(), integer()) -> {ok, l_w_w_map(KCG)} | {error, merge_error()}.
-doc(false).
lww_remove(Map, Key, Timestamp) ->
    gleam@result:'try'(begin
        _pipe = lattice_maps@internal@lww_map_engine:put(erlang:element(4, Map), Key, {entry, none, Timestamp, {modern, erlang:element(2, Map)}}, fun(A, B) ->
            A =:= B
        end),
        gleam@result:map_error(_pipe, fun lww_error/1)
    end, fun(State) ->
        {ok, {l_w_w_map, erlang:element(2, Map), erlang:element(3, Map), State}}
    end).

-file("src/lattice_maps/crdt.gleam", 972).
-spec lww_keys(l_w_w_map(any())) -> list(binary()).
-doc(false).
lww_keys(Map) ->
    gleam@dict:fold(erlang:element(2, erlang:element(4, Map)), [], fun(Keys, Key, Entry) ->
        case erlang:element(2, Entry) of
            {some, _} ->
                [Key | Keys];

            none ->
                Keys
        end
    end).

-file("src/lattice_maps/crdt.gleam", 982).
-spec lww_values(l_w_w_map(KCO)) -> list(crdt(KCO)).
-doc(false).
lww_values(Map) ->
    gleam@list:filter_map(lww_keys(Map), fun(_capture) ->
        lww_get(Map, _capture)
    end).

-file("src/lattice_maps/crdt.gleam", 987).
-spec lww_tombstone_count(l_w_w_map(any())) -> integer().
-doc(false).
lww_tombstone_count(Map) ->
    maps:size(erlang:element(2, erlang:element(4, Map))) - erlang:length(lww_keys(Map)).

-file("src/lattice_maps/crdt.gleam", 992).
-spec lww_pruned_timestamp(l_w_w_map(any())) -> integer().
-doc(false).
lww_pruned_timestamp(Map) ->
    erlang:element(3, erlang:element(4, Map)).

-file("src/lattice_maps/crdt.gleam", 997).
-spec lww_prune(l_w_w_map(KCW), integer()) -> l_w_w_map(KCW).
-doc(false).
lww_prune(Map, Stable) ->
    {l_w_w_map, erlang:element(2, Map), erlang:element(3, Map), lattice_maps@internal@lww_map_engine:prune(erlang:element(4, Map), Stable)}.

-file("src/lattice_maps/crdt.gleam", 1015).
-spec invalid(binary(), binary(), list(binary())) -> gleam@json:decode_error().
invalid(Expected, Found, Path) ->
    {unable_to_decode, [{decode_error, Expected, Found, Path}]}.

-file("src/lattice_maps/crdt.gleam", 1023).
-spec json_at_key(gleam@json:decode_error(), binary()) -> gleam@json:decode_error().
json_at_key(Error, Key) ->
    case Error of
        {unable_to_decode, Errors} ->
            {unable_to_decode, gleam@list:map(Errors, fun(Error@1) ->
                {decode_error, erlang:element(2, Error@1), erlang:element(3, Error@1), [~"entries", Key | erlang:element(4, Error@1)]}
            end)};

        Other ->
            Other
    end.

-file("src/lattice_maps/crdt.gleam", 1035).
-spec envelope(binary(), integer(), gleam@json:json()) -> gleam@json:json().
envelope(Kind, Version, State) ->
    gleam@json:object([{~"type", gleam@json:string(Kind)}, {~"v", gleam@json:int(Version)}, {~"state", State}]).

-file("src/lattice_maps/crdt.gleam", 1043).
-spec check_envelope(binary(), binary(), list(integer())) -> {ok, nil} | {error, gleam@json:decode_error()}.
check_envelope(Input, Kind, Versions) ->
    Decoder = begin
        gleam@dynamic@decode:field(~"type", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(Tag) ->
            gleam@dynamic@decode:field(~"v", {decoder, fun gleam@dynamic@decode:decode_int/1}, fun(Version) ->
                gleam@dynamic@decode:success({Tag, Version})
            end)
        end)
    end,
    gleam@result:'try'(gleam@json:parse(Input, Decoder), fun(_use0) ->
        {Tag, Version} = _use0,
        case (Tag =:= Kind) andalso gleam@list:contains(Versions, Version) of
            true ->
                {ok, nil};

            false ->
                {error, invalid(<<Kind/binary, " supported protocol version"/utf8>>, <<<<Tag/binary, ":"/utf8>>/binary, (erlang:integer_to_binary(Version))/binary>>, [])}
        end
    end).

-file("src/lattice_maps/crdt.gleam", 1067).
-spec embedded(gleam@json:json()) -> gleam@json:json().
embedded(Value) ->
    gleam@json:string(gleam@json:to_string(Value)).

-file("src/lattice_maps/crdt.gleam", 1071).
-spec optional_json(gleam@option:option(KDJ), fun((KDJ) -> gleam@json:json())) -> gleam@json:json().
optional_json(Value, Encode) ->
    case Value of
        {some, Value@1} ->
            Encode(Value@1);

        none ->
            gleam@json:null()
    end.

-file("src/lattice_maps/crdt.gleam", 1078).
-spec parse_optional(gleam@option:option(binary()), fun((binary()) -> {ok, KDM} | {error, gleam@json:decode_error()})) -> {ok, gleam@option:option(KDM)} | {error, gleam@json:decode_error()}.
parse_optional(Value, Parser) ->
    case Value of
        {some, Value@1} ->
            gleam@result:map(Parser(Value@1), fun(_value) ->
                {some, _value}
            end);

        none ->
            {ok, none}
    end.

-file("src/lattice_maps/crdt.gleam", 1088).
-spec unique_pairs(list({binary(), KDS})) -> {ok, gleam@dict:dict(binary(), KDS)} | {error, gleam@json:decode_error()}.
unique_pairs(Pairs) ->
    Entries = maps:from_list(Pairs),
    case maps:size(Entries) =:= erlang:length(Pairs) of
        true ->
            {ok, Entries};

        false ->
            {error, invalid(~"unique keys", ~"duplicate key", [~"entries"])}
    end.

-file("src/lattice_maps/crdt.gleam", 1107).
-spec spec_to_json_with(crdt_spec(KDY), fun((KDY) -> gleam@json:json())) -> gleam@json:json().
-doc(~" Encode a recursive schema, including the register's configured initial value.

 ## Examples

 ```gleam
 let schema = crdt.OrMapSpec(crdt.LwwMapSpec(crdt.LwwRegisterSpec(42)))
 let encoded = crdt.spec_to_json_with(schema, json.int) |> json.to_string
 crdt.spec_from_json_with(encoded, decode.int) // -> Ok(schema)
 ```").
spec_to_json_with(Spec, Encode) ->
    Fields = case Spec of
        {lww_register_spec, Initial} ->
            [{~"initial", Encode(Initial)}];

        {or_map_spec, Child} ->
            [{~"child", embedded(spec_to_json_with(Child, Encode))}];

        {lww_map_spec, Child} ->
            [{~"child", embedded(spec_to_json_with(Child, Encode))}];

        _ ->
            []
    end,
    gleam@json:object([{~"type", gleam@json:string(spec_name(Spec))} | Fields]).

-file("src/lattice_maps/crdt.gleam", 1130).
-spec spec_from_json_with(binary(), gleam@dynamic@decode:decoder(KEA)) -> {ok, crdt_spec(KEA)} | {error, gleam@json:decode_error()}.
-doc(~" Decode a complete recursive schema.

 The payload decoder also decodes configured register initial values.

 ## Examples

 ```gleam
 let schema = crdt.OrMapSpec(crdt.LwwRegisterSpec(42))
 let encoded = crdt.spec_to_json_with(schema, json.int) |> json.to_string
 let assert Ok(decoded) = crdt.spec_from_json_with(encoded, decode.int)
 decoded == schema // -> True
 ```").
spec_from_json_with(Input, Decoder) ->
    gleam@result:'try'(gleam@json:parse(Input, begin
        gleam@dynamic@decode:field(~"type", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(Kind) ->
            gleam@dynamic@decode:success(Kind)
        end)
    end), fun(Kind) ->
        case Kind of
            ~"g_counter" ->
                {ok, g_counter_spec};

            ~"pn_counter" ->
                {ok, pn_counter_spec};

            ~"lww_register" ->
                gleam@json:parse(Input, begin
                    gleam@dynamic@decode:field(~"initial", Decoder, fun(Initial) ->
                        gleam@dynamic@decode:success({lww_register_spec, Initial})
                    end)
                end);

            ~"mv_register" ->
                {ok, mv_register_spec};

            ~"g_set" ->
                {ok, g_set_spec};

            ~"two_p_set" ->
                {ok, two_p_set_spec};

            ~"or_set" ->
                {ok, or_set_spec};

            ~"sequence" ->
                {ok, sequence_spec};

            ~"text" ->
                {ok, text_spec};

            ~"or_map" ->
                gleam@result:'try'(gleam@json:parse(Input, begin
                    gleam@dynamic@decode:field(~"child", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(Child) ->
                        gleam@dynamic@decode:success(Child)
                    end)
                end), fun(Child) ->
                    gleam@result:'try'(spec_from_json_with(Child, Decoder), fun(Child@1) ->
                        {ok, case Kind of
                            ~"or_map" ->
                                {or_map_spec, Child@1};

                            _ ->
                                {lww_map_spec, Child@1}
                        end}
                    end)
                end);

            ~"lww_map" ->
                gleam@result:'try'(gleam@json:parse(Input, begin
                    gleam@dynamic@decode:field(~"child", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(Child) ->
                        gleam@dynamic@decode:success(Child)
                    end)
                end), fun(Child) ->
                    gleam@result:'try'(spec_from_json_with(Child, Decoder), fun(Child@1) ->
                        {ok, case Kind of
                            ~"or_map" ->
                                {or_map_spec, Child@1};

                            _ ->
                                {lww_map_spec, Child@1}
                        end}
                    end)
                end);

            _ ->
                {error, invalid(~"known child schema", Kind, [~"type"])}
        end
    end).

-file("src/lattice_maps/crdt.gleam", 1631).
-spec provenance_json(lattice_maps@internal@lww_map_engine:provenance()) -> gleam@json:json().
provenance_json(Provenance) ->
    case Provenance of
        {modern, Writer} ->
            gleam@json:object([{~"kind", gleam@json:string(~"modern")}, {~"writer", gleam@json:string(lattice_core@replica_id:to_string(Writer))}]);

        {legacy, Tie_key} ->
            gleam@json:object([{~"kind", gleam@json:string(~"legacy")}, {~"tie_key", gleam@json:string(Tie_key)}])
    end.

-file("src/lattice_maps/crdt.gleam", 1409).
-spec generation_json(lattice_maps@internal@or_map_engine:generation()) -> gleam@json:json().
generation_json(Generation) ->
    case Generation of
        initial ->
            gleam@json:object([{~"clock", gleam@json:int(0)}, {~"creator", gleam@json:null()}]);

        {generation, Clock, Creator} ->
            gleam@json:object([{~"clock", gleam@json:int(Clock)}, {~"creator", gleam@json:string(lattice_core@replica_id:to_string(Creator))}])
    end.

-file("src/lattice_maps/crdt.gleam", 1436).
-spec or_state_json(lattice_core@replica_id:replica_id(), crdt_spec(KFJ), lattice_maps@internal@or_map_engine:state(KFL), fun((KFJ) -> gleam@json:json()), fun((KFL) -> gleam@json:json())) -> gleam@json:json().
or_state_json(Replica, Spec, State, Encode, Encode_child) ->
    gleam@json:object([{~"replica_id", gleam@json:string(lattice_core@replica_id:to_string(Replica))}, {~"spec", embedded(spec_to_json_with(Spec, Encode))}, {~"clock", gleam@json:int(erlang:element(2, State))}, {~"entries", gleam@json:array(maps:to_list(erlang:element(3, State)), fun(Pair) ->
        {Key, Entry} = Pair,
        gleam@json:object([{~"key", gleam@json:string(Key)}, {~"generation", generation_json(erlang:element(2, Entry))}, {~"membership", embedded(lattice_sets@or_set:to_json_with(erlang:element(3, Entry), fun gleam@json:string/1))}, {~"value", optional_json(erlang:element(4, Entry), fun(Child) ->
            embedded(Encode_child(Child))
        end)}])
    end)}]).

-file("src/lattice_maps/crdt.gleam", 1662).
-spec lww_to_json_with(l_w_w_map(KGS), fun((KGS) -> gleam@json:json())) -> gleam@json:json().
-doc(false).
lww_to_json_with(Map, Encode) ->
    envelope(~"lww_map", 3, gleam@json:object([{~"replica_id", gleam@json:string(lattice_core@replica_id:to_string(erlang:element(2, Map)))}, {~"spec", embedded(spec_to_json_with(erlang:element(3, Map), Encode))}, {~"pruned_timestamp", gleam@json:int(erlang:element(3, erlang:element(4, Map)))}, {~"entries", gleam@json:array(maps:to_list(erlang:element(2, erlang:element(4, Map))), fun(Pair) ->
        {Key, Entry} = Pair,
        gleam@json:object([{~"key", gleam@json:string(Key)}, {~"timestamp", gleam@json:int(erlang:element(3, Entry))}, {~"provenance", provenance_json(erlang:element(4, Entry))}, {~"value", optional_json(erlang:element(2, Entry), fun(Child) ->
            embedded(to_json_with(Child, Encode))
        end)}])
    end)}])).

-file("src/lattice_maps/crdt.gleam", 1471).
-spec or_to_json_with(o_r_map(KFN), fun((KFN) -> gleam@json:json())) -> gleam@json:json().
-doc(false).
or_to_json_with(Map, Encode) ->
    envelope(~"or_map", 3, or_state_json(erlang:element(2, Map), erlang:element(3, Map), erlang:element(4, Map), Encode, fun(_capture) ->
        to_json_with(_capture, Encode)
    end)).

-file("src/lattice_maps/crdt.gleam", 1204).
-spec to_json_with(crdt(KEG), fun((KEG) -> gleam@json:json())) -> gleam@json:json().
-doc(~" Encode generic payloads. Text has a distinct dispatch envelope.

 The encoder is used at every generic payload position, including map schema
 defaults. Generic ORSet values use their value/tag-entry protocol.

 ## Examples

 ```gleam
 let state = crdt.default_crdt(
   crdt.OrMapSpec(crdt.LwwRegisterSpec(42)), replica_id.new(\"A\"),
 )
 let encoded = crdt.to_json_with(state, json.int) |> json.to_string
 crdt.from_json_with(encoded, decode.int) // -> Ok(state)
 ```").
to_json_with(Value, Encode) ->
    case Value of
        {crdt_g_counter, Value@1} ->
            lattice_counters@g_counter:to_json(Value@1);

        {crdt_pn_counter, Value@2} ->
            lattice_counters@pn_counter:to_json(Value@2);

        {crdt_lww_register, Value@3} ->
            lattice_registers@lww_register:to_json_with(Value@3, Encode);

        {crdt_mv_register, Value@4} ->
            lattice_registers@mv_register:to_json_with(Value@4, Encode);

        {crdt_g_set, Value@5} ->
            lattice_sets@g_set:to_json_with(Value@5, Encode);

        {crdt_two_p_set, Value@6} ->
            lattice_sets@two_p_set:to_json_with(Value@6, Encode);

        {crdt_or_set, Value@7} ->
            lattice_sets@or_set:to_json_with(Value@7, Encode);

        {crdt_version_vector, Value@8} ->
            lattice_core@version_vector:to_json(Value@8);

        {crdt_sequence, Value@9} ->
            lattice_sequence@sequence:to_json(Value@9, Encode);

        {crdt_text, Value@10} ->
            envelope(~"text", 1, embedded(lattice_text@text:to_json(Value@10)));

        {crdt_or_map, Value@11} ->
            or_to_json_with(Value@11, Encode);

        {crdt_lww_map, Value@12} ->
            lww_to_json_with(Value@12, Encode)
    end.

-file("src/lattice_maps/crdt.gleam", 1183).
-spec to_json(crdt(binary())) -> gleam@json:json().
-doc(~" Encode String payloads, preserving existing standalone leaf formats.

 Maps use the modern recursive protocols. Text uses a distinct dispatch
 wrapper around its unchanged standalone Sequence envelope.

 ## Examples

 ```gleam
 let state = crdt.CrdtGSet(g_set.new() |> g_set.add(\"ready\"))
 let encoded = state |> crdt.to_json |> json.to_string
 crdt.from_json(encoded) // -> Ok(state)
 ```").
to_json(Value) ->
    case Value of
        {crdt_or_set, Value@1} ->
            lattice_sets@or_set:to_json(Value@1);

        _ ->
            to_json_with(Value, fun gleam@json:string/1)
    end.

-file("src/lattice_maps/crdt.gleam", 1646).
-spec provenance_decoder() -> gleam@dynamic@decode:decoder(lattice_maps@internal@lww_map_engine:provenance()).
provenance_decoder() ->
    gleam@dynamic@decode:field(~"kind", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(Kind) ->
        case Kind of
            ~"modern" ->
                gleam@dynamic@decode:field(~"writer", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(Writer) ->
                    gleam@dynamic@decode:success({modern, lattice_core@replica_id:new(Writer)})
                end);

            ~"legacy" ->
                gleam@dynamic@decode:field(~"tie_key", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(Tie_key) ->
                    gleam@dynamic@decode:success({legacy, Tie_key})
                end);

            _ ->
                gleam@dynamic@decode:failure({legacy, ~""}, ~"modern or legacy provenance")
        end
    end).

-file("src/lattice_maps/crdt.gleam", 1421).
-spec generation_decoder() -> gleam@dynamic@decode:decoder(lattice_maps@internal@or_map_engine:generation()).
generation_decoder() ->
    gleam@dynamic@decode:field(~"clock", {decoder, fun gleam@dynamic@decode:decode_int/1}, fun(Clock) ->
        gleam@dynamic@decode:field(~"creator", gleam@dynamic@decode:optional({decoder, fun gleam@dynamic@decode:decode_string/1}), fun(Creator) ->
            case {Clock, Creator} of
                {0, none} ->
                    gleam@dynamic@decode:success(initial);

                {Clock@1, {some, Creator@1}} when (Clock@1 > 0) andalso (Clock@1 =< 9007199254740991) ->
                    gleam@dynamic@decode:success({generation, Clock@1, lattice_core@replica_id:new(Creator@1)});

                {_, _} ->
                    gleam@dynamic@decode:failure(initial, ~"Initial or positive safe generation with creator")
            end
        end)
    end).

-file("src/lattice_maps/crdt.gleam", 1500).
-spec parse_or_state(binary(), gleam@dynamic@decode:decoder(KFR), fun((binary(), crdt_spec(KFR)) -> {ok, KFU} | {error, gleam@json:decode_error()})) -> {ok, {lattice_core@replica_id:replica_id(), crdt_spec(KFR), lattice_maps@internal@or_map_engine:state(KFU)}} | {error, gleam@json:decode_error()}.
parse_or_state(Input, Decoder, Parse_child) ->
    Entry_decoder = begin
        gleam@dynamic@decode:field(~"key", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(Key) ->
            gleam@dynamic@decode:field(~"generation", generation_decoder(), fun(Generation) ->
                gleam@dynamic@decode:field(~"membership", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(Membership) ->
                    gleam@dynamic@decode:field(~"value", gleam@dynamic@decode:optional({decoder, fun gleam@dynamic@decode:decode_string/1}), fun(Value) ->
                        gleam@dynamic@decode:success({Key, Generation, Membership, Value})
                    end)
                end)
            end)
        end)
    end,
    gleam@result:'try'(gleam@json:parse(Input, begin
        gleam@dynamic@decode:field(~"state", begin
            gleam@dynamic@decode:field(~"replica_id", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(Replica) ->
                gleam@dynamic@decode:field(~"spec", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(Spec) ->
                    gleam@dynamic@decode:field(~"clock", {decoder, fun gleam@dynamic@decode:decode_int/1}, fun(Clock) ->
                        gleam@dynamic@decode:field(~"entries", gleam@dynamic@decode:list(Entry_decoder), fun(Entries) ->
                            gleam@dynamic@decode:success({Replica, Spec, Clock, Entries})
                        end)
                    end)
                end)
            end)
        end, fun(State) ->
            gleam@dynamic@decode:success(State)
        end)
    end), fun(_use0) ->
        {Replica, Spec, Clock, Entries} = _use0,
        gleam@result:'try'(case (Clock >= 0) andalso (Clock =< 9007199254740991) of
            true ->
                {ok, nil};

            false ->
                {error, invalid(~"safe nonnegative allocation clock", erlang:integer_to_binary(Clock), [~"clock"])}
        end, fun(_) ->
            gleam@result:'try'(spec_from_json_with(Spec, Decoder), fun(Spec@1) ->
                gleam@result:'try'(gleam@list:try_map(Entries, fun(Entry) ->
                    {Key, Generation, Membership, Value} = Entry,
                    gleam@bool:guard(lattice_maps@internal@or_map_engine:clock(Generation) > Clock, {error, invalid(~"clock covering all generations", Key, [~"clock"])}, fun() ->
                        gleam@result:'try'(lattice_sets@or_set:from_json_with(Membership, {decoder, fun gleam@dynamic@decode:decode_string/1}), fun(Membership@1) ->
                            gleam@bool:guard(begin
                                _pipe = gleam@set:to_list(lattice_sets@or_set:value(Membership@1)),
                                gleam@list:any(_pipe, fun(Member) ->
                                    Member /= Key
                                end)
                            end, {error, invalid(~"membership only for entry key", Key, [~"entries", Key, ~"membership"])}, fun() ->
                                gleam@result:'try'(begin
                                    _pipe@1 = parse_optional(Value, fun(_capture) ->
                                        Parse_child(_capture, Spec@1)
                                    end),
                                    gleam@result:map_error(_pipe@1, fun(_capture) ->
                                        json_at_key(_capture, Key)
                                    end)
                                end, fun(Value@1) ->
                                    {ok, {Key, {entry, Generation, Membership@1, Value@1}}}
                                end)
                            end)
                        end)
                    end)
                end), fun(Entries@1) ->
                    gleam@result:'try'(unique_pairs(Entries@1), fun(Entries@2) ->
                        {ok, {lattice_core@replica_id:new(Replica), Spec@1, {state, Clock, Entries@2}}}
                    end)
                end)
            end)
        end)
    end).

-file("src/lattice_maps/crdt.gleam", 1251).
-spec dispatch_tag(binary()) -> {ok, binary()} | {error, gleam@json:decode_error()}.
dispatch_tag(Input) ->
    gleam@json:parse(Input, begin
        gleam@dynamic@decode:field(~"type", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(Kind) ->
            gleam@dynamic@decode:success(Kind)
        end)
    end).

-file("src/lattice_maps/crdt.gleam", 1567).
-spec parse_checked_child(binary(), crdt_spec(KGB), gleam@dynamic@decode:decoder(KGB)) -> {ok, crdt(KGB)} | {error, gleam@json:decode_error()}.
parse_checked_child(Input, Spec, Decoder) ->
    gleam@result:'try'(from_json_with(Input, Decoder), fun(Value) ->
        case matches_spec(Value, Spec) of
            true ->
                {ok, Value};

            false ->
                {error, invalid(~"matching recursive child schema", type_name(Value), [~"value"])}
        end
    end).

-file("src/lattice_maps/crdt.gleam", 1692).
-spec lww_from_json_with(binary(), gleam@dynamic@decode:decoder(KGU)) -> {ok, l_w_w_map(KGU)} | {error, gleam@json:decode_error()}.
-doc(false).
lww_from_json_with(Input, Decoder) ->
    gleam@result:'try'(check_envelope(Input, ~"lww_map", [3]), fun(_) ->
        Entry_decoder = begin
            gleam@dynamic@decode:field(~"key", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(Key) ->
                gleam@dynamic@decode:field(~"timestamp", {decoder, fun gleam@dynamic@decode:decode_int/1}, fun(Timestamp) ->
                    gleam@dynamic@decode:field(~"provenance", provenance_decoder(), fun(Provenance) ->
                        gleam@dynamic@decode:field(~"value", gleam@dynamic@decode:optional({decoder, fun gleam@dynamic@decode:decode_string/1}), fun(Value) ->
                            gleam@dynamic@decode:success({Key, Timestamp, Provenance, Value})
                        end)
                    end)
                end)
            end)
        end,
        gleam@result:'try'(gleam@json:parse(Input, begin
            gleam@dynamic@decode:field(~"state", begin
                gleam@dynamic@decode:field(~"replica_id", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(Replica) ->
                    gleam@dynamic@decode:field(~"spec", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(Spec) ->
                        gleam@dynamic@decode:field(~"pruned_timestamp", {decoder, fun gleam@dynamic@decode:decode_int/1}, fun(Pruned) ->
                            gleam@dynamic@decode:field(~"entries", gleam@dynamic@decode:list(Entry_decoder), fun(Entries) ->
                                gleam@dynamic@decode:success({Replica, Spec, Pruned, Entries})
                            end)
                        end)
                    end)
                end)
            end, fun(State) ->
                gleam@dynamic@decode:success(State)
            end)
        end), fun(_use0) ->
            {Replica, Spec, Pruned, Entries} = _use0,
            gleam@bool:guard((Pruned < 0) orelse (Pruned > 9007199254740991), {error, invalid(~"nonnegative prune floor", erlang:integer_to_binary(Pruned), [~"pruned_timestamp"])}, fun() ->
                gleam@result:'try'(spec_from_json_with(Spec, Decoder), fun(Spec@1) ->
                    gleam@result:'try'(gleam@list:try_map(Entries, fun(Entry) ->
                        {Key, Timestamp, Provenance, Value} = Entry,
                        Modern = case Provenance of
                            {modern, _} ->
                                true;

                            {legacy, _} ->
                                false
                        end,
                        gleam@bool:guard(((Modern andalso (Timestamp =< 0)) orelse (Timestamp > 9007199254740991)) orelse (Timestamp < -9007199254740991), {error, invalid(~"positive write timestamp", Key, [~"entries", Key])}, fun() ->
                            gleam@result:'try'(begin
                                _pipe = parse_optional(Value, fun(_capture) ->
                                    parse_checked_child(_capture, Spec@1, Decoder)
                                end),
                                gleam@result:map_error(_pipe, fun(_capture) ->
                                    json_at_key(_capture, Key)
                                end)
                            end, fun(Value@1) ->
                                {ok, {Key, {entry, Value@1, Timestamp, Provenance}}}
                            end)
                        end)
                    end), fun(Entries@1) ->
                        gleam@result:'try'(unique_pairs(Entries@1), fun(Entries@2) ->
                            {ok, {l_w_w_map, lattice_core@replica_id:new(Replica), Spec@1, {state, Entries@2, Pruned}}}
                        end)
                    end)
                end)
            end)
        end)
    end).

-file("src/lattice_maps/crdt.gleam", 1583).
-spec or_from_json_with(binary(), gleam@dynamic@decode:decoder(KGH)) -> {ok, o_r_map(KGH)} | {error, gleam@json:decode_error()}.
-doc(false).
or_from_json_with(Input, Decoder) ->
    gleam@result:'try'(check_envelope(Input, ~"or_map", [3]), fun(_) ->
        gleam@result:'try'(parse_or_state(Input, Decoder, fun(Input@1, Spec) ->
            parse_checked_child(Input@1, Spec, Decoder)
        end), fun(_use0) ->
            {Replica, Spec, State} = _use0,
            gleam@result:'try'(gleam@list:try_fold(maps:to_list(erlang:element(3, State)), nil, fun(_, Pair) ->
                {Key, Entry} = Pair,
                case {lattice_maps@internal@or_map_engine:active(Entry, Key), erlang:element(4, Entry)} of
                    {true, none} ->
                        {error, invalid(~"value for active membership", ~"null", [~"entries", Key, ~"value"])};

                    {_, _} ->
                        {ok, nil}
                end
            end), fun(_) ->
                {ok, or_bind({o_r_map, Replica, Spec, State}, Replica)}
            end)
        end)
    end).

-file("src/lattice_maps/crdt.gleam", 1282).
-spec from_json_with(binary(), gleam@dynamic@decode:decoder(KES)) -> {ok, crdt(KES)} | {error, gleam@json:decode_error()}.
-doc(~" Decode a generic state; bare Sequence envelopes always dispatch as Sequence.

 Bind the result before editing as another writer. A bare Sequence of Strings
 is not inferred to be Text; only the explicit Text dispatch wrapper is Text.

 ## Examples

 ```gleam
 let state = crdt.default_crdt(crdt.LwwRegisterSpec(42), replica_id.new(\"A\"))
 let encoded = crdt.to_json_with(state, json.int) |> json.to_string
 let assert Ok(decoded) = crdt.from_json_with(encoded, decode.int)
 crdt.matches_spec(decoded, crdt.LwwRegisterSpec(42)) // -> True
 ```").
from_json_with(Input, Decoder) ->
    gleam@result:'try'(dispatch_tag(Input), fun(Kind) ->
        case Kind of
            ~"g_counter" ->
                _pipe = lattice_counters@g_counter:from_json(Input),
                gleam@result:map(_pipe, fun(_value) ->
                    {crdt_g_counter, _value}
                end);

            ~"pn_counter" ->
                _pipe@1 = lattice_counters@pn_counter:from_json(Input),
                gleam@result:map(_pipe@1, fun(_value@1) ->
                    {crdt_pn_counter, _value@1}
                end);

            ~"lww_register" ->
                _pipe@2 = lattice_registers@lww_register:from_json_with(Input, Decoder),
                gleam@result:map(_pipe@2, fun(_value@2) ->
                    {crdt_lww_register, _value@2}
                end);

            ~"mv_register" ->
                _pipe@3 = lattice_registers@mv_register:from_json_with(Input, Decoder),
                gleam@result:map(_pipe@3, fun(_value@3) ->
                    {crdt_mv_register, _value@3}
                end);

            ~"g_set" ->
                _pipe@4 = lattice_sets@g_set:from_json_with(Input, Decoder),
                gleam@result:map(_pipe@4, fun(_value@4) ->
                    {crdt_g_set, _value@4}
                end);

            ~"two_p_set" ->
                _pipe@5 = lattice_sets@two_p_set:from_json_with(Input, Decoder),
                gleam@result:map(_pipe@5, fun(_value@5) ->
                    {crdt_two_p_set, _value@5}
                end);

            ~"or_set" ->
                _pipe@6 = lattice_sets@or_set:from_json_with(Input, Decoder),
                gleam@result:map(_pipe@6, fun(_value@6) ->
                    {crdt_or_set, _value@6}
                end);

            ~"version_vector" ->
                _pipe@7 = lattice_core@version_vector:from_json(Input),
                gleam@result:map(_pipe@7, fun(_value@7) ->
                    {crdt_version_vector, _value@7}
                end);

            ~"sequence" ->
                _pipe@8 = lattice_sequence@sequence:from_json(Input, Decoder),
                gleam@result:map(_pipe@8, fun(_value@8) ->
                    {crdt_sequence, _value@8}
                end);

            ~"text" ->
                gleam@result:'try'(check_envelope(Input, ~"text", [1]), fun(_) ->
                    gleam@result:'try'(gleam@json:parse(Input, begin
                        gleam@dynamic@decode:field(~"state", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(Payload) ->
                            gleam@dynamic@decode:success(Payload)
                        end)
                    end), fun(Payload) ->
                        _pipe@9 = lattice_text@text:from_json(Payload),
                        gleam@result:map(_pipe@9, fun(_value@9) ->
                            {crdt_text, _value@9}
                        end)
                    end)
                end);

            ~"or_map" ->
                _pipe@9 = or_from_json_with(Input, Decoder),
                gleam@result:map(_pipe@9, fun(_value@10) ->
                    {crdt_or_map, _value@10}
                end);

            ~"lww_map" ->
                _pipe@10 = lww_from_json_with(Input, Decoder),
                gleam@result:map(_pipe@10, fun(_value@11) ->
                    {crdt_lww_map, _value@11}
                end);

            _ ->
                {error, invalid(~"known CRDT type", Kind, [~"type"])}
        end
    end).

-file("src/lattice_maps/crdt.gleam", 1258).
-spec legacy_or_set(binary(), gleam@dynamic@decode:decoder(KEN)) -> {ok, lattice_sets@or_set:o_r_set(KEN)} | {error, gleam@json:decode_error()}.
legacy_or_set(Input, Decoder) ->
    gleam@result:'try'(lattice_sets@or_set:from_json(Input), fun(Legacy) ->
        lattice_sets@or_set:from_json_with(begin
            _pipe = lattice_sets@or_set:to_json_with(Legacy, fun gleam@json:string/1),
            gleam@json:to_string(_pipe)
        end, Decoder)
    end).

-file("src/lattice_maps/crdt.gleam", 1232).
-spec from_json(binary()) -> {ok, crdt(binary())} | {error, gleam@json:decode_error()}.
-doc(~" Decode String states, including legacy String leaf codecs (not legacy maps).

 Use the map facades' explicit import adapters for legacy map baselines.

 ## Examples

 ```gleam
 let state = crdt.default_crdt(crdt.LwwRegisterSpec(\"\"), replica_id.new(\"A\"))
 let encoded = state |> crdt.to_json |> json.to_string
 crdt.from_json(encoded) // -> Ok(state)
 ```").
from_json(Input) ->
    gleam@result:'try'(dispatch_tag(Input), fun(Kind) ->
        case Kind of
            ~"or_set" ->
                gleam@result:'try'(gleam@json:parse(Input, begin
                    gleam@dynamic@decode:field(~"v", {decoder, fun gleam@dynamic@decode:decode_int/1}, fun(Version) ->
                        gleam@dynamic@decode:success(Version)
                    end)
                end), fun(Version) ->
                    case Version of
                        1 ->
                            _pipe = legacy_or_set(Input, {decoder, fun gleam@dynamic@decode:decode_string/1}),
                            gleam@result:map(_pipe, fun(_value) ->
                                {crdt_or_set, _value}
                            end);

                        2 ->
                            _pipe = legacy_or_set(Input, {decoder, fun gleam@dynamic@decode:decode_string/1}),
                            gleam@result:map(_pipe, fun(_value@1) ->
                                {crdt_or_set, _value@1}
                            end);

                        _ ->
                            from_json_with(Input, {decoder, fun gleam@dynamic@decode:decode_string/1})
                    end
                end);

            _ ->
                from_json_with(Input, {decoder, fun gleam@dynamic@decode:decode_string/1})
        end
    end).

-file("src/lattice_maps/crdt.gleam", 1483).
-spec or_delta_to_json_with(o_r_map_delta(KFP), fun((KFP) -> gleam@json:json())) -> gleam@json:json().
-doc(false).
or_delta_to_json_with(Delta, Encode) ->
    envelope(~"or_map_delta", 2, or_state_json(erlang:element(2, Delta), erlang:element(3, Delta), erlang:element(4, Delta), Encode, fun(_capture) ->
        delta_to_json_with(_capture, Encode)
    end)).

-file("src/lattice_maps/crdt.gleam", 1340).
-spec delta_to_json_with(crdt_delta(KEY), fun((KEY) -> gleam@json:json())) -> gleam@json:json().
-doc(~" Encode a typed dispatch delta without expanding nested ORMap changes.

 ## Examples

 ```gleam
 let map = or_map.new(replica_id.new(\"A\"), crdt.LwwRegisterSpec(42))
 let delta = crdt.OrMapChange(or_map.empty_delta(map))
 let encoded = crdt.delta_to_json_with(delta, json.int) |> json.to_string
 crdt.delta_from_json_with(encoded, decode.int) // -> Ok(delta)
 ```").
delta_to_json_with(Delta, Encode) ->
    {Kind, Payload} = case Delta of
        {no_change, Spec} ->
            {~"none", spec_to_json_with(Spec, Encode)};

        {state_delta, Value} ->
            {~"state", to_json_with(Value, Encode)};

        {or_map_change, Value@1} ->
            {~"or_map", or_delta_to_json_with(Value@1, Encode)}
    end,
    envelope(~"crdt_delta", 1, gleam@json:object([{~"kind", gleam@json:string(Kind)}, {~"payload", embedded(Payload)}])).

-file("src/lattice_maps/crdt.gleam", 1326).
-spec delta_to_json(crdt_delta(binary())) -> gleam@json:json().
-doc(~" Encode a String-payload dispatch delta.

 ## Examples

 ```gleam
 let delta = crdt.NoChange(crdt.LwwRegisterSpec(\"\"))
 let encoded = delta |> crdt.delta_to_json |> json.to_string
 crdt.delta_from_json(encoded) // -> Ok(delta)
 ```").
delta_to_json(Delta) ->
    delta_to_json_with(Delta, fun gleam@json:string/1).

-file("src/lattice_maps/crdt.gleam", 1611).
-spec or_delta_from_json_with(binary(), gleam@dynamic@decode:decoder(KGM)) -> {ok, o_r_map_delta(KGM)} | {error, gleam@json:decode_error()}.
-doc(false).
or_delta_from_json_with(Input, Decoder) ->
    gleam@result:'try'(check_envelope(Input, ~"or_map_delta", [2]), fun(_) ->
        gleam@result:'try'(parse_or_state(Input, Decoder, fun(Input@1, Spec) ->
            gleam@result:'try'(delta_from_json_with(Input@1, Decoder), fun(Delta) ->
                case matches_delta(Delta, Spec) of
                    true ->
                        {ok, Delta};

                    false ->
                        {error, invalid(~"matching recursive delta schema", ~"mismatch", [~"value"])}
                end
            end)
        end), fun(_use0) ->
            {Replica, Spec, State} = _use0,
            {ok, {o_r_map_delta, Replica, Spec, State}}
        end)
    end).

-file("src/lattice_maps/crdt.gleam", 1385).
-spec delta_from_json_with(binary(), gleam@dynamic@decode:decoder(KFD)) -> {ok, crdt_delta(KFD)} | {error, gleam@json:decode_error()}.
-doc(~" Decode a typed dispatch delta.

 Apply it with `apply_delta` and the receiver's expected schema. Decoding a
 change does not establish that it belongs to a particular receiving map.

 ## Examples

 ```gleam
 let local = replica_id.new(\"A\")
 let schema = crdt.LwwRegisterSpec(42)
 let delta = crdt.NoChange(schema)
 let encoded = crdt.delta_to_json_with(delta, json.int) |> json.to_string
 let assert Ok(decoded) = crdt.delta_from_json_with(encoded, decode.int)
 let state = crdt.default_crdt(schema, local)
 crdt.apply_delta(state, decoded, schema, local) // -> Ok(state)
 ```").
delta_from_json_with(Input, Decoder) ->
    gleam@result:'try'(check_envelope(Input, ~"crdt_delta", [1]), fun(_) ->
        gleam@result:'try'(gleam@json:parse(Input, begin
            gleam@dynamic@decode:field(~"state", begin
                gleam@dynamic@decode:field(~"kind", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(Kind) ->
                    gleam@dynamic@decode:field(~"payload", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(Payload) ->
                        gleam@dynamic@decode:success({Kind, Payload})
                    end)
                end)
            end, fun(State) ->
                gleam@dynamic@decode:success(State)
            end)
        end), fun(_use0) ->
            {Kind, Payload} = _use0,
            case Kind of
                ~"none" ->
                    _pipe = spec_from_json_with(Payload, Decoder),
                    gleam@result:map(_pipe, fun(_value) ->
                        {no_change, _value}
                    end);

                ~"state" ->
                    _pipe@1 = from_json_with(Payload, Decoder),
                    gleam@result:map(_pipe@1, fun(_value@1) ->
                        {state_delta, _value@1}
                    end);

                ~"or_map" ->
                    _pipe@2 = or_delta_from_json_with(Payload, Decoder),
                    gleam@result:map(_pipe@2, fun(_value@2) ->
                        {or_map_change, _value@2}
                    end);

                _ ->
                    {error, invalid(~"none, state, or or_map delta", Kind, [~"kind"])}
            end
        end)
    end).

-file("src/lattice_maps/crdt.gleam", 1363).
-spec delta_from_json(binary()) -> {ok, crdt_delta(binary())} | {error, gleam@json:decode_error()}.
-doc(~" Decode a String-payload dispatch delta.

 ## Examples

 ```gleam
 let delta = crdt.NoChange(crdt.LwwRegisterSpec(\"\"))
 let encoded = delta |> crdt.delta_to_json |> json.to_string
 let assert Ok(decoded) = crdt.delta_from_json(encoded)
 crdt.is_empty_delta(decoded) // -> True
 ```").
delta_from_json(Input) ->
    delta_from_json_with(Input, {decoder, fun gleam@dynamic@decode:decode_string/1}).

-file("src/lattice_maps/crdt.gleam", 1750).
-spec or_import_legacy(binary(), crdt_spec(KGZ), gleam@dynamic@decode:decoder(KGZ), lattice_core@replica_id:replica_id()) -> {ok, o_r_map(KGZ)} | {error, gleam@json:decode_error()}.
-doc(false).
or_import_legacy(Input, Spec, Decoder, Replica) ->
    gleam@result:'try'(check_envelope(Input, ~"or_map", [1, 2]), fun(_) ->
        gleam@result:'try'(gleam@json:parse(Input, begin
            gleam@dynamic@decode:field(~"state", begin
                gleam@dynamic@decode:field(~"crdt_spec", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(Spec@1) ->
                    gleam@dynamic@decode:field(~"key_set", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(Membership) ->
                        gleam@dynamic@decode:field(~"values", gleam@dynamic@decode:list(begin
                            gleam@dynamic@decode:field(~"key", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(Key) ->
                                gleam@dynamic@decode:field(~"crdt", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(Child) ->
                                    gleam@dynamic@decode:success({Key, Child})
                                end)
                            end)
                        end), fun(Entries) ->
                            gleam@dynamic@decode:optional_field(~"remove_bounds", maps:new(), gleam@dynamic@decode:dict({decoder, fun gleam@dynamic@decode:decode_string/1}, lattice_core@version_vector:decoder()), fun(Bounds) ->
                                gleam@dynamic@decode:success({Spec@1, Membership, Entries, Bounds})
                            end)
                        end)
                    end)
                end)
            end, fun(State) ->
                gleam@dynamic@decode:success(State)
            end)
        end), fun(_use0) ->
            {Old_spec, Membership, Entries, Bounds} = _use0,
            gleam@bool:guard(Old_spec /= spec_name(Spec), {error, invalid(spec_name(Spec), Old_spec, [~"crdt_spec"])}, fun() ->
                gleam@result:'try'(legacy_or_set(Membership, {decoder, fun gleam@dynamic@decode:decode_string/1}), fun(Membership@1) ->
                    gleam@result:'try'(gleam@list:try_map(Entries, fun(Pair) ->
                        gleam@result:'try'(dispatch_tag(erlang:element(2, Pair)), fun(Kind) ->
                            gleam@result:'try'(case Kind of
                                ~"or_set" ->
                                    _pipe = legacy_or_set(erlang:element(2, Pair), Decoder),
                                    gleam@result:map(_pipe, fun(_value) ->
                                        {crdt_or_set, _value}
                                    end);

                                _ ->
                                    from_json_with(erlang:element(2, Pair), Decoder)
                            end, fun(Child) ->
                                gleam@bool:guard(not matches_spec(Child, Spec), {error, invalid(~"matching legacy child schema", Kind, [~"values", erlang:element(1, Pair)])}, fun() ->
                                    {ok, {erlang:element(1, Pair), Child}}
                                end)
                            end)
                        end)
                    end), fun(Pairs) ->
                        gleam@result:'try'(unique_pairs(Pairs), fun(Children) ->
                            Keys = begin
                                _pipe = maps:keys(Children),
                                _pipe@1 = lists:append(_pipe, gleam@set:to_list(lattice_sets@or_set:value(Membership@1))),
                                _pipe@2 = lists:append(_pipe@1, maps:keys(Bounds)),
                                gleam@list:unique(_pipe@2)
                            end,
                            gleam@result:'try'(gleam@list:try_map(Keys, fun(Key) ->
                                Child = case gleam_stdlib:map_get(Children, Key) of
                                    {ok, Child@1} ->
                                        {some, Child@1};

                                    {error, nil} ->
                                        none
                                end,
                                gleam@bool:guard(lattice_sets@or_set:contains(Membership@1, Key) andalso (Child =:= none), {error, invalid(~"active legacy child baseline", Key, [~"values"])}, fun() ->
                                    Per_key = lattice_sets@or_set:remove_where(Membership@1, fun(Other) ->
                                        Other /= Key
                                    end),
                                    {ok, {Key, {entry, initial, Per_key, Child}}}
                                end)
                            end), fun(Entries@1) ->
                                {ok, or_bind({o_r_map, Replica, Spec, {state, 0, maps:from_list(Entries@1)}}, Replica)}
                            end)
                        end)
                    end)
                end)
            end)
        end)
    end).

-file("src/lattice_maps/crdt.gleam", 1827).
-spec lww_import_legacy(binary(), crdt_spec(binary()), lattice_core@replica_id:replica_id()) -> {ok, l_w_w_map(binary())} | {error, gleam@json:decode_error()}.
-doc(false).
lww_import_legacy(Input, Spec, Replica) ->
    gleam@result:'try'(check_envelope(Input, ~"lww_map", [1, 2]), fun(_) ->
        gleam@bool:guard(spec_name(Spec) /= ~"lww_register", {error, invalid(~"explicit LwwRegisterSpec", spec_name(Spec), [~"spec"])}, fun() ->
            gleam@result:'try'(gleam@json:parse(Input, begin
                gleam@dynamic@decode:field(~"state", begin
                    gleam@dynamic@decode:field(~"entries", gleam@dynamic@decode:list(begin
                        gleam@dynamic@decode:field(~"key", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(Key) ->
                            gleam@dynamic@decode:field(~"value", gleam@dynamic@decode:optional({decoder, fun gleam@dynamic@decode:decode_string/1}), fun(Value) ->
                                gleam@dynamic@decode:field(~"timestamp", {decoder, fun gleam@dynamic@decode:decode_int/1}, fun(Timestamp) ->
                                    gleam@dynamic@decode:success({Key, Value, Timestamp})
                                end)
                            end)
                        end)
                    end), fun(Entries) ->
                        gleam@dynamic@decode:optional_field(~"pruned_timestamp", 0, {decoder, fun gleam@dynamic@decode:decode_int/1}, fun(Pruned) ->
                            gleam@dynamic@decode:success({Entries, Pruned})
                        end)
                    end)
                end, fun(State) ->
                    gleam@dynamic@decode:success(State)
                end)
            end), fun(_use0) ->
                {Entries, Pruned} = _use0,
                gleam@bool:guard((Pruned < 0) orelse (Pruned > 9007199254740991), {error, invalid(~"safe nonnegative prune floor", erlang:integer_to_binary(Pruned), [~"pruned_timestamp"])}, fun() ->
                    gleam@result:'try'(gleam@list:try_map(Entries, fun(Entry) ->
                        {Key, Value, Timestamp} = Entry,
                        gleam@bool:guard((Timestamp > 9007199254740991) orelse (Timestamp < -9007199254740991), {error, invalid(~"safe write timestamp", erlang:integer_to_binary(Timestamp), [~"entries", Key])}, fun() ->
                            {Child, Tie_key} = case Value of
                                {some, Value@1} ->
                                    {{some, {crdt_lww_register, lattice_registers@lww_register:new(Value@1, Timestamp, scope(lattice_core@replica_id:new(~"legacy"), [~"lww-import", Key, Value@1]))}}, Value@1};

                                none ->
                                    {none, ~""}
                            end,
                            {ok, {Key, {entry, Child, Timestamp, {legacy, Tie_key}}}}
                        end)
                    end), fun(Entries@1) ->
                        gleam@result:'try'(unique_pairs(Entries@1), fun(Entries@2) ->
                            {ok, {l_w_w_map, Replica, Spec, {state, Entries@2, Pruned}}}
                        end)
                    end)
                end)
            end)
        end)
    end).

