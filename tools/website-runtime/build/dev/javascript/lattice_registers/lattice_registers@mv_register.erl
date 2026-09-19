-module(lattice_registers@mv_register).
-compile([no_auto_import, nowarn_ignored, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-export([new/1, set_with_delta/2, set/2, value/1, merge/2, to_json_with/2, to_json/1, from_json_with/2, from_json/1]).
-export_type([tag/0, m_v_register/1]).
-moduledoc(~" A multi-value register (MV-Register) CRDT.

 Preserves all concurrently written values using causal history tracked by
 version vectors. When one write causally supersedes another, only the newer
 value survives. When writes are concurrent, all values are retained — the
 application decides how to resolve the conflict.

 ## Example

 ```gleam
 import lattice_core/replica_id
 import lattice_registers/mv_register

 let a = mv_register.new(replica_id.new(\"node-a\")) |> mv_register.set(\"hello\")
 let b = mv_register.new(replica_id.new(\"node-b\")) |> mv_register.set(\"world\")
 let merged = mv_register.merge(a, b)
 mv_register.value(merged)  // -> [\"hello\", \"world\"] (concurrent writes)
 ```").

-opaque tag() :: {tag, lattice_core@replica_id:replica_id(), integer()}.

-opaque m_v_register(DWV) :: {m_v_register, lattice_core@replica_id:replica_id(), gleam@dict:dict(tag(), DWV), lattice_core@version_vector:version_vector()}.

-file("src/lattice_registers/mv_register.gleam", 57).
-spec new(lattice_core@replica_id:replica_id()) -> m_v_register(any()).
-doc(~" Create a new empty MV-Register for the given replica.

 Returns a register with no entries and an empty version vector.
 `replica_id` identifies this node and is used when writing new values.").
new(Replica_id) ->
    {m_v_register, Replica_id, maps:new(), lattice_core@version_vector:new()}.

-file("src/lattice_registers/mv_register.gleam", 91).
-spec set_with_delta(m_v_register(DXB), DXB) -> {m_v_register(DXB), m_v_register(DXB)}.
-doc(~" Write a new value and return both the new state and a delta.

 The returned delta is an `MVRegister` whose `entries` contains only the
 new tag→value pair, but whose `vclock` is the **full new vclock** of the
 writing replica. The vclock is essential: it encodes the causal context
 the local write supersedes, so that on merge into a remote replica every
 dominated tag (whether at the writer or any other replica observed by
 the writer) is correctly retracted.

 Merging the delta into a remote via `merge` produces the same result as
 merging the full new state, but is much smaller when the local register
 holds many concurrent values being collapsed by this write.").
set_with_delta(Register, Val) ->
    New_vclock = lattice_core@version_vector:increment(erlang:element(4, Register), erlang:element(2, Register)),
    New_counter = lattice_core@version_vector:get(New_vclock, erlang:element(2, Register)),
    Tag = {tag, erlang:element(2, Register), New_counter},
    New_state = {m_v_register, erlang:element(2, Register), gleam@dict:insert(maps:new(), Tag, Val), New_vclock},
    {New_state, New_state}.

-file("src/lattice_registers/mv_register.gleam", 74).
-spec set(m_v_register(DWY), DWY) -> m_v_register(DWY).
-doc(~" Write a new value to the register.

 Increments this replica's logical clock, creates a fresh tag for the write,
 clears all prior entries (this write causally supersedes everything in the
 current vclock), and inserts the new tag-value pair. After a `set`, calling
 `value` returns a single-element list containing `val`.

 See `set_with_delta` for the delta-state variant that also returns a
 small payload suitable for incremental sync (e.g. over websockets).").
set(Register, Val) ->
    {Updated, _} = set_with_delta(Register, Val),
    Updated.

-file("src/lattice_registers/mv_register.gleam", 115).
-spec value(m_v_register(DXF)) -> list(DXF).
-doc(~" Return all concurrent values in the register.

 Returns a list of all surviving values. An empty list means the register
 has never been written. A single-element list is the common case after a
 `set`. Multiple values indicate concurrent writes from different replicas
 that have not yet been causally superseded — the application must decide
 how to resolve them (e.g., pick one, merge, or surface the conflict).").
value(Register) ->
    maps:values(erlang:element(3, Register)).

-file("src/lattice_registers/mv_register.gleam", 134).
-spec merge(m_v_register(DXI), m_v_register(DXI)) -> m_v_register(DXI).
-doc(~" Merge two MV-Registers.

 An entry survives the merge if it is not dominated by the other register's
 version vector, or if both registers share the same entry (handles
 self-merge idempotency):

 - Entry `Tag(rid, counter)` from `a` survives if `b.vclock[rid] < counter`
   OR `b.entries` also contains that tag.
 - Entry `Tag(rid, counter)` from `b` survives if `a.vclock[rid] < counter`
   OR `a.entries` also contains that tag.

 The merged vclock is the pairwise maximum of both vclocks.
 The result's `replica_id` is taken from `a`.

 This operation is commutative, associative, and idempotent.").
merge(A, B) ->
    Surviving_from_a = gleam@dict:filter(erlang:element(3, A), fun(Tag, _) ->
        (lattice_core@version_vector:get(erlang:element(4, B), erlang:element(2, Tag)) < erlang:element(3, Tag)) orelse gleam@dict:has_key(erlang:element(3, B), Tag)
    end),
    Surviving_from_b = gleam@dict:filter(erlang:element(3, B), fun(Tag, _) ->
        (lattice_core@version_vector:get(erlang:element(4, A), erlang:element(2, Tag)) < erlang:element(3, Tag)) orelse gleam@dict:has_key(erlang:element(3, A), Tag)
    end),
    Merged_entries = maps:merge(Surviving_from_a, Surviving_from_b),
    {m_v_register, erlang:element(2, A), Merged_entries, lattice_core@version_vector:merge(erlang:element(4, A), erlang:element(4, B))}.

-file("src/lattice_registers/mv_register.gleam", 180).
-spec to_json_with(m_v_register(DXN), fun((DXN) -> gleam@json:json())) -> gleam@json:json().
-doc(~" Encode generic values, write tags, and the full causal clock.

 Uses the same v1 envelope as `to_json`.

 ## Examples

 ```gleam
 let register = mv_register.new(replica_id.new(\"A\")) |> mv_register.set(42)
 mv_register.to_json_with(register, json.int)
 ```").
to_json_with(Register, Encode) ->
    {m_v_register, Rid, Entries, Vclock} = Register,
    Entries_json = gleam@json:array(maps:to_list(Entries), fun(Pair) ->
        {{tag, Tag_rid, Counter}, Value} = Pair,
        gleam@json:object([{~"tag", gleam@json:object([{~"r", gleam@json:string(lattice_core@replica_id:to_string(Tag_rid))}, {~"c", gleam@json:int(Counter)}])}, {~"value", Encode(Value)}])
    end),
    Vclock_dict = lattice_core@version_vector:to_dict(Vclock),
    gleam@json:object([{~"type", gleam@json:string(~"mv_register")}, {~"v", gleam@json:int(1)}, {~"state", gleam@json:object([{~"replica_id", gleam@json:string(lattice_core@replica_id:to_string(Rid))}, {~"entries", Entries_json}, {~"vclock", gleam@json:dict(Vclock_dict, fun lattice_core@replica_id:to_string/1, fun gleam@json:int/1)}])}]).

-file("src/lattice_registers/mv_register.gleam", 166).
-spec to_json(m_v_register(binary())) -> gleam@json:json().
-doc(~" Encode a MVRegister(String) as a self-describing JSON value.

 Entries are serialized as an array of tag+value objects because `Tag` is a
 custom type that cannot serve as a JSON dictionary key.
 Format: `{\"type\": \"mv_register\", \"v\": 1, \"state\": {\"replica_id\": \"...\", \"entries\": [...], \"vclock\": {...}}}`

 Use `from_json` to decode the result back into a `MVRegister(String)`.").
to_json(Register) ->
    to_json_with(Register, fun gleam@json:string/1).

-file("src/lattice_registers/mv_register.gleam", 235).
-spec from_json_with(binary(), gleam@dynamic@decode:decoder(DXS)) -> {ok, m_v_register(DXS)} | {error, gleam@json:decode_error()}.
-doc(~" Decode generic values and validate their write tags against the causal clock.

 Accepts the v1 envelope. Invalid payloads or causal metadata return `Error`.

 ## Examples

 ```gleam
 let register = mv_register.new(replica_id.new(\"A\")) |> mv_register.set(42)
 let encoded = mv_register.to_json_with(register, json.int) |> json.to_string
 mv_register.from_json_with(encoded, decode.int)  // -> Ok(register)
 ```").
from_json_with(Json_string, Decoder) ->
    Entry_decoder = begin
        gleam@dynamic@decode:field(~"tag", begin
            gleam@dynamic@decode:field(~"r", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(R) ->
                gleam@dynamic@decode:field(~"c", {decoder, fun gleam@dynamic@decode:decode_int/1}, fun(C) ->
                    gleam@dynamic@decode:success({tag, lattice_core@replica_id:new(R), C})
                end)
            end)
        end, fun(Tag) ->
            gleam@dynamic@decode:field(~"value", Decoder, fun(Value) ->
                gleam@dynamic@decode:success({Tag, Value})
            end)
        end)
    end,
    State_decoder = begin
        gleam@dynamic@decode:field(~"state", begin
            gleam@dynamic@decode:field(~"replica_id", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(Rid_str) ->
                gleam@dynamic@decode:field(~"entries", gleam@dynamic@decode:list(Entry_decoder), fun(Entries_list) ->
                    gleam@dynamic@decode:field(~"vclock", gleam@dynamic@decode:dict({decoder, fun gleam@dynamic@decode:decode_string/1}, {decoder, fun gleam@dynamic@decode:decode_int/1}), fun(Vclock_dict) ->
                        Entries = maps:from_list(Entries_list),
                        Vclock_rid_dict = gleam@dict:fold(Vclock_dict, maps:new(), fun(Acc, K, V) ->
                            gleam@dict:insert(Acc, lattice_core@replica_id:new(K), V)
                        end),
                        Vclock = lattice_core@version_vector:from_dict(Vclock_rid_dict),
                        Is_valid = ((maps:size(Entries) =:= erlang:length(Entries_list)) andalso gleam@list:all(maps:values(Vclock_dict), fun(Counter) ->
                            Counter >= 0
                        end)) andalso gleam@list:all(Entries_list, fun(Pair) ->
                            {{tag, Rid, C}, _} = Pair,
                            Is_positive = C > 0,
                            Vclock_counter = lattice_core@version_vector:get(Vclock, Rid),
                            Is_causal = C =< Vclock_counter,
                            Is_positive andalso Is_causal
                        end),
                        Mvr = {m_v_register, lattice_core@replica_id:new(Rid_str), Entries, Vclock},
                        case Is_valid of
                            true ->
                                gleam@dynamic@decode:success(Mvr);

                            false ->
                                gleam@dynamic@decode:failure(Mvr, ~"unique causally consistent entries and non-negative clocks with positive tag counters")
                        end
                    end)
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
            case (Type_tag =:= ~"mv_register") andalso (Version =:= 1) of
                true ->
                    gleam@json:parse(Json_string, State_decoder);

                false ->
                    {error, {unable_to_decode, [{decode_error, ~"type=mv_register and v=1", <<<<Type_tag/binary, " v="/utf8>>/binary, (erlang:integer_to_binary(Version))/binary>>, []}]}}
            end
    end.

-file("src/lattice_registers/mv_register.gleam", 218).
-spec from_json(binary()) -> {ok, m_v_register(binary())} | {error, gleam@json:decode_error()}.
-doc(~" Decode a MVRegister(String) from a JSON string produced by `to_json`.

 Returns `Ok(MVRegister(String))` on success, or `Error(json.DecodeError)`
 if the input is not a valid MV-Register JSON envelope.").
from_json(Json_string) ->
    from_json_with(Json_string, {decoder, fun gleam@dynamic@decode:decode_string/1}).

