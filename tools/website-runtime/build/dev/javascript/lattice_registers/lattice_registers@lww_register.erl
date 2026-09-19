-module(lattice_registers@lww_register).
-compile([no_auto_import, nowarn_ignored, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-export([new/3, set_with_delta/4, set/4, value/1, timestamp/1, replica_id/1, merge/2, to_json_with/2, to_json/1, from_json_with/2, from_json/1]).
-export_type([l_w_w_register/1]).
-moduledoc(~" A last-writer-wins register (LWW-Register) CRDT.

 Stores a single value with an associated timestamp. When two replicas
 conflict, the value with the strictly higher timestamp wins. On equal
 timestamps, the replica with the lexicographically greater `replica_id`
 wins, ensuring fully commutative merge.

 ## Example

 ```gleam
 import lattice_core/replica_id
 import lattice_registers/lww_register

 let a = lww_register.new(\"hello\", 1, replica_id.new(\"node-a\"))
 let b = lww_register.new(\"world\", 2, replica_id.new(\"node-b\"))
 let merged = lww_register.merge(a, b)
 lww_register.value(merged)  // -> \"world\"
 ```").

-opaque l_w_w_register(DSH) :: {l_w_w_register, DSH, integer(), lattice_core@replica_id:replica_id()}.

-file("src/lattice_registers/lww_register.gleam", 46).
-spec new(DSI, integer(), lattice_core@replica_id:replica_id()) -> l_w_w_register(DSI).
-doc(~" Create a new LWW-Register with an initial value, timestamp, and replica ID.

 `timestamp` should be a positive integer representing the logical time of
 the write. Use a monotonically increasing source (e.g., wall-clock
 milliseconds or a Lamport clock) so that later writes have higher values.
 `replica_id` identifies the writing node and is used as a deterministic
 tie-breaker when two registers have equal timestamps during merge.").
new(Value, Timestamp, Replica_id) ->
    {l_w_w_register, Value, Timestamp, Replica_id}.

-file("src/lattice_registers/lww_register.gleam", 103).
-spec set_with_delta(l_w_w_register(DSN), DSN, integer(), lattice_core@replica_id:replica_id()) -> {l_w_w_register(DSN), l_w_w_register(DSN)}.
-doc(~" Set a value and return both the new state and a delta.

 The returned delta is an `LWWRegister` carrying the write that was
 actually accepted locally. When `timestamp` strictly exceeds the current
 timestamp the delta carries the new (value, timestamp, replica_id);
 otherwise the local set is a no-op and the delta carries the unchanged
 register so that no rejected write can win on a remote replica.

 Merging the delta into a remote via `merge` produces the same result as
 merging the new local state, preserving convergence.").
set_with_delta(Register, Value, Timestamp, Replica_id) ->
    gleam@bool:guard(Timestamp =< erlang:element(3, Register), {Register, Register}, fun() ->
        Updated = {l_w_w_register, Value, Timestamp, Replica_id},
        {Updated, Updated}
    end).

-file("src/lattice_registers/lww_register.gleam", 83).
-spec set(l_w_w_register(DSK), DSK, integer(), lattice_core@replica_id:replica_id()) -> l_w_w_register(DSK).
-doc(~" Write a value as `replica_id` if `timestamp` is strictly greater.

 If `timestamp > register.timestamp`, replaces the stored value and
 write metadata. Otherwise returns the register unchanged. Supplying the
 writer explicitly prevents a local write after `merge` from inheriting the
 winning remote writer's identity.

 Note that the comparison is *strict*, so a wall clock is not a safe source
 on its own: it stalls for a millisecond at a time, and a second write
 inside the same tick is silently dropped even when it came from this same
 replica. Callers that write faster than their clock ticks should stamp
 `int.max(wall_clock, timestamp(register) + 1)`, which keeps every local
 write ordered while leaving `merge` commutative.

 A writer must not reuse the same `(timestamp, replica_id)` for different
 values. After a restart, use a fresh replica ID or restore a durable logical
 clock that advances beyond every prior write from that ID.

 See `set_with_delta` for the delta-state variant that also returns a
 small payload suitable for incremental sync (e.g. over websockets).

 ## Examples

 ```gleam
 let local = replica_id.new(\"B\")
 let adopted = lww_register.new(\"old\", 1, replica_id.new(\"A\"))
 let updated = lww_register.set(adopted, \"new\", 2, local)
 lww_register.replica_id(updated)  // -> local
 ```").
set(Register, Value, Timestamp, Replica_id) ->
    {Updated, _} = set_with_delta(Register, Value, Timestamp, Replica_id),
    Updated.

-file("src/lattice_registers/lww_register.gleam", 118).
-spec value(l_w_w_register(DSR)) -> DSR.
-doc(~" Return the current value of the register.

 Provided for a uniform functional API since the type is opaque.").
value(Register) ->
    erlang:element(2, Register).

-file("src/lattice_registers/lww_register.gleam", 139).
-spec timestamp(l_w_w_register(any())) -> integer().
-doc(~" Return the timestamp of the write the register currently holds.

 Because `set` accepts only strictly greater timestamps, a caller stamping
 writes from a wall clock needs to know the timestamp already held in order
 to stay ahead of it — two writes inside the same clock tick are otherwise
 unordered and the second is dropped. Reading this back from a decoded
 snapshot lets such a caller seed its logical clock before its first write.

 ## Examples

 ```gleam
 let register = lww_register.new(\"hello\", 42, replica_id.new(\"node-a\"))
 lww_register.timestamp(register)  // -> 42

 // Stamp the next write so it cannot collide with the one held.
 let next = int.max(wall_clock_ms(), lww_register.timestamp(register) + 1)
 ```").
timestamp(Register) ->
    erlang:element(3, Register).

-file("src/lattice_registers/lww_register.gleam", 148).
-spec replica_id(l_w_w_register(any())) -> lattice_core@replica_id:replica_id().
-doc(~" Return the replica that owns the value the register currently holds.

 `set` records its supplied author only for an accepted write. After `merge`
 this is the replica whose write won, which makes it useful for provenance
 and for tie-breaking consistently with `merge` in downstream code.").
replica_id(Register) ->
    erlang:element(4, Register).

-file("src/lattice_registers/lww_register.gleam", 158).
-spec merge(l_w_w_register(DSX), l_w_w_register(DSX)) -> l_w_w_register(DSX).
-doc(~" Merge two LWW-Registers by returning the one with the higher timestamp.

 When `a.timestamp > b.timestamp`, returns `a`. When `b.timestamp >
 a.timestamp`, returns `b`. On equal timestamps, the register whose
 `replica_id` is lexicographically greater wins, providing a fully
 commutative, associative, and idempotent merge.").
merge(A, B) ->
    gleam@bool:guard(erlang:element(3, A) > erlang:element(3, B), A, fun() ->
        gleam@bool:guard(erlang:element(3, A) < erlang:element(3, B), B, fun() ->
            case lattice_core@replica_id:compare(erlang:element(4, A), erlang:element(4, B)) of
                gt ->
                    A;

                lt ->
                    B;

                eq ->
                    A
            end
        end)
    end).

-file("src/lattice_registers/lww_register.gleam", 189).
-spec to_json_with(l_w_w_register(DTC), fun((DTC) -> gleam@json:json())) -> gleam@json:json().
-doc(~" Encode a register with a custom payload encoder, preserving write metadata.

 Uses the same v2 envelope as `to_json`.

 ## Examples

 ```gleam
 let register = lww_register.new(42, 1, replica_id.new(\"A\"))
 lww_register.to_json_with(register, json.int)
 ```").
to_json_with(Register, Encode) ->
    gleam@json:object([{~"type", gleam@json:string(~"lww_register")}, {~"v", gleam@json:int(2)}, {~"state", gleam@json:object([{~"value", Encode(erlang:element(2, Register))}, {~"timestamp", gleam@json:int(erlang:element(3, Register))}, {~"replica_id", gleam@json:string(lattice_core@replica_id:to_string(erlang:element(4, Register)))}])}]).

-file("src/lattice_registers/lww_register.gleam", 175).
-spec to_json(l_w_w_register(binary())) -> gleam@json:json().
-doc(~" Encode a LWWRegister(String) as a self-describing JSON value.

 Produces an envelope with `type`, `v` (schema version = 2), and `state`.
 Format: `{\"type\": \"lww_register\", \"v\": 2, \"state\": {\"value\": \"...\", \"timestamp\": ..., \"replica_id\": \"...\"}}`

 Use `from_json` to decode the result back into a `LWWRegister(String)`.").
to_json(Register) ->
    to_json_with(Register, fun gleam@json:string/1).

-file("src/lattice_registers/lww_register.gleam", 234).
-spec from_json_with(binary(), gleam@dynamic@decode:decoder(DTH)) -> {ok, l_w_w_register(DTH)} | {error, gleam@json:decode_error()}.
-doc(~" Decode a register with a custom payload decoder.

 Accepts v1 and v2 envelopes, with the same metadata rules as `from_json`.
 V2 requires `replica_id` to be present and contain a string, including when
 that string is empty. Invalid payloads or envelopes return `Error`.

 ## Examples

 ```gleam
 let register = lww_register.new(42, 1, replica_id.new(\"A\"))
 let encoded = lww_register.to_json_with(register, json.int) |> json.to_string
 lww_register.from_json_with(encoded, decode.int)  // -> Ok(register)
 ```").
from_json_with(Json_string, Decoder) ->
    V1_state_decoder = begin
        gleam@dynamic@decode:field(~"state", begin
            gleam@dynamic@decode:field(~"value", Decoder, fun(Value) ->
                gleam@dynamic@decode:field(~"timestamp", {decoder, fun gleam@dynamic@decode:decode_int/1}, fun(Timestamp) ->
                    gleam@dynamic@decode:optional_field(~"replica_id", ~"", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(Replica_id_str) ->
                        gleam@dynamic@decode:success({l_w_w_register, Value, Timestamp, lattice_core@replica_id:new(Replica_id_str)})
                    end)
                end)
            end)
        end, fun(State) ->
            gleam@dynamic@decode:success(State)
        end)
    end,
    V2_state_decoder = begin
        gleam@dynamic@decode:field(~"state", begin
            gleam@dynamic@decode:field(~"value", Decoder, fun(Value) ->
                gleam@dynamic@decode:field(~"timestamp", {decoder, fun gleam@dynamic@decode:decode_int/1}, fun(Timestamp) ->
                    gleam@dynamic@decode:field(~"replica_id", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(Replica_id_str) ->
                        gleam@dynamic@decode:success({l_w_w_register, Value, Timestamp, lattice_core@replica_id:new(Replica_id_str)})
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
            case {Type_tag, Version} of
                {~"lww_register", 1} ->
                    gleam@json:parse(Json_string, V1_state_decoder);

                {~"lww_register", 2} ->
                    gleam@json:parse(Json_string, V2_state_decoder);

                {_, _} ->
                    {error, {unable_to_decode, [{decode_error, ~"type=lww_register and v=1 or v=2", <<<<Type_tag/binary, " v="/utf8>>/binary, (erlang:integer_to_binary(Version))/binary>>, []}]}}
            end
    end.

-file("src/lattice_registers/lww_register.gleam", 215).
-spec from_json(binary()) -> {ok, l_w_w_register(binary())} | {error, gleam@json:decode_error()}.
-doc(~" Decode a LWWRegister(String) from a JSON string produced by `to_json`.

 Supports both v1 (no replica_id, uses the legacy `\"\"` placeholder) and v2
 (requires a string replica_id) envelopes. The v1 placeholder does not prove
 the identity of the historical writer; pass the local replica ID to `set`
 for every subsequent write. Returns `Ok(LWWRegister(String))` on success, or
 `Error(json.DecodeError)` if the input is not a valid LWW-Register JSON
 envelope.").
from_json(Json_string) ->
    from_json_with(Json_string, {decoder, fun gleam@dynamic@decode:decode_string/1}).

