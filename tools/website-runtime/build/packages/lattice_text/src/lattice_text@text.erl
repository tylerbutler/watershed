-module(lattice_text@text).
-compile([no_auto_import, nowarn_ignored, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-export([new/1, insert_with_delta/3, insert/3, delete_with_delta/2, delete/2, values/1, value/1, length/1, substring/3, try_substring/3, delete_range_with_delta/3, delete_range/3, replace_range_with_delta/4, replace_range/4, move_with_delta/3, move/3, start_anchor/0, end_anchor/0, anchor_at/3, resolve_anchor/2, anchor_to_json/1, anchor_from_json/1, append_with_delta/2, append/2, compact/2, remove_forwardings/2, frontier/1, bind/2, merge/3, merge_as/3, to_json/1, from_json/1]).
-export_type([text/0, range_error/0]).
-moduledoc(~" A plain-text CRDT backed by `lattice_sequence`.

 Text is stored as a sequence of single-grapheme items: every inserted
 string is split into graphemes and each grapheme becomes one sequence
 item, so indices, anchors, and `length` are all grapheme-based. Insert,
 delete, merge, and delta operations delegate to `lattice_sequence`.
 Use `lattice_sequence/sequence` directly when you need a generic list CRDT.

 ## Example

 ```gleam
 import lattice_core/replica_id
 import lattice_text/text

 let doc = text.new(replica_id.new(\"node-a\"))
 text.value(doc)  // -> \"\"
 ```").

-opaque text() :: {text, lattice_sequence@sequence:sequence(binary())}.

-type range_error() :: {range_out_of_bounds, integer(), integer(), integer()}.

-file("src/lattice_text/text.gleam", 41).
-spec new(lattice_core@replica_id:replica_id()) -> text().
-doc(~" Create an empty text CRDT for a replica.").
new(Replica_id) ->
    {text, lattice_sequence@sequence:new(Replica_id)}.

-file("src/lattice_text/text.gleam", 441).
-spec insert_graphemes_with_delta(list(binary()), lattice_sequence@sequence:sequence(binary()), integer()) -> {ok, {lattice_sequence@sequence:sequence(binary()), lattice_sequence@sequence:sequence(binary())}} | {error, lattice_sequence@sequence:insert_error()}.
insert_graphemes_with_delta(Graphemes, Seq, Index) ->
    lattice_text_core@grapheme:insert_graphemes(Graphemes, Seq, Index, fun lattice_sequence@sequence:length/1, fun lattice_sequence@sequence:insert_many_with_delta/3, fun(_value, _value@1) ->
        {index_out_of_bounds, _value, _value@1}
    end).

-file("src/lattice_text/text.gleam", 60).
-spec insert_with_delta(text(), integer(), binary()) -> {ok, {text(), text()}} | {error, lattice_sequence@sequence:insert_error()}.
-doc(~" Insert a value and return both the updated text and insertion delta.

 Returns `IndexOutOfBounds` when `index` is outside `[0, length]`.").
insert_with_delta(Text, Index, Value) ->
    {text, Seq} = Text,
    _pipe = Value,
    _pipe@1 = gleam@string:to_graphemes(_pipe),
    _pipe@2 = insert_graphemes_with_delta(_pipe@1, Seq, Index),
    gleam@result:map(_pipe@2, fun(Pair) ->
        {Updated, Delta} = Pair,
        {{text, Updated}, {text, Delta}}
    end).

-file("src/lattice_text/text.gleam", 48).
-spec insert(text(), integer(), binary()) -> {ok, text()} | {error, lattice_sequence@sequence:insert_error()}.
-doc(~" Insert a value at the visible character index.

 Returns `IndexOutOfBounds` when `index` is outside `[0, length]`.").
insert(Text, Index, Value) ->
    _pipe = insert_with_delta(Text, Index, Value),
    gleam@result:map(_pipe, fun(Pair) ->
        erlang:element(1, Pair)
    end).

-file("src/lattice_text/text.gleam", 86).
-spec delete_with_delta(text(), integer()) -> {ok, {text(), text()}} | {error, lattice_sequence@sequence:delete_error()}.
-doc(~" Delete a value and return both the updated text and deletion delta.

 Returns `DeleteIndexOutOfBounds` when `index` is outside `[0, length)`.").
delete_with_delta(Text, Index) ->
    {text, Seq} = Text,
    case lattice_sequence@sequence:delete_with_delta(Seq, Index) of
        {ok, {Updated, Delta}} ->
            {ok, {{text, Updated}, {text, Delta}}};

        {error, Error} ->
            {error, Error}
    end.

-file("src/lattice_text/text.gleam", 78).
-spec delete(text(), integer()) -> {ok, text()} | {error, lattice_sequence@sequence:delete_error()}.
-doc(~" Delete the value at the visible character index.

 Returns `DeleteIndexOutOfBounds` when `index` is outside `[0, length)`.").
delete(Text, Index) ->
    _pipe = delete_with_delta(Text, Index),
    gleam@result:map(_pipe, fun(Pair) ->
        erlang:element(1, Pair)
    end).

-file("src/lattice_text/text.gleam", 98).
-spec values(text()) -> list(binary()).
-doc(~" Return the visible graphemes as a list.").
values(Text) ->
    {text, Seq} = Text,
    lattice_sequence@sequence:values(Seq).

-file("src/lattice_text/text.gleam", 104).
-spec value(text()) -> binary().
-doc(~" Return the visible text as a single string.").
value(Text) ->
    _pipe = Text,
    _pipe@1 = values(_pipe),
    erlang:list_to_binary(_pipe@1).

-file("src/lattice_text/text.gleam", 119).
-spec length(text()) -> integer().
-doc(~" Count the visible graphemes in the text.

 ## Examples

 ```gleam
 let assert Ok(doc) = text.insert(text.new(replica_id.new(\"A\")), 0, \"a👍\")
 text.length(doc)
 // -> 2
 ```").
length(Text) ->
    {text, Seq} = Text,
    lattice_sequence@sequence:length(Seq).

-file("src/lattice_text/text.gleam", 403).
-spec slice_values(text(), integer(), integer()) -> binary().
slice_values(Text, Start, End) ->
    lattice_text_core@grapheme:slice(values(Text), Start, End).

-file("src/lattice_text/text.gleam", 134).
-spec substring(text(), integer(), integer()) -> binary().
-doc(~" Return the graphemes in `[start, end)`, clamping both indexes to the
 text bounds. An empty range (including `start > end`) yields `\"\"`.

 ## Examples

 ```gleam
 let assert Ok(doc) = text.insert(text.new(replica_id.new(\"A\")), 0, \"abcd\")
 text.substring(doc, 1, 3)
 // -> \"bc\"
 ```").
substring(Text, Start, End) ->
    Len = length(Text),
    slice_values(Text, gleam@int:clamp(Start, 0, Len), gleam@int:clamp(End, 0, Len)).

-file("src/lattice_text/text.gleam", 391).
-spec validate_range(integer(), integer(), integer()) -> {ok, nil} | {error, range_error()}.
validate_range(Start, End, Length) ->
    _pipe = lattice_text_core@grapheme:validate_range(Start, End, Length),
    gleam@result:map_error(_pipe, fun(Error) ->
        {range_out_of_bounds, Start@1, End@1, Length@1} = Error,
        {range_out_of_bounds, Start@1, End@1, Length@1}
    end).

-file("src/lattice_text/text.gleam", 149).
-spec try_substring(text(), integer(), integer()) -> {ok, binary()} | {error, range_error()}.
-doc(~" Return the graphemes in `[start, end)`, or an error when the range does
 not satisfy `0 <= start <= end <= length`.

 ## Examples

 ```gleam
 let assert Ok(doc) = text.insert(text.new(replica_id.new(\"A\")), 0, \"abc\")
 text.try_substring(doc, 0, 4)
 // -> Error(text.RangeOutOfBounds(start: 0, end: 4, length: 3))
 ```").
try_substring(Text, Start, End) ->
    gleam@result:'try'(validate_range(Start, End, length(Text)), fun(_use0) ->
        nil = _use0,
        {ok, slice_values(Text, Start, End)}
    end).

-file("src/lattice_text/text.gleam", 430).
-spec delete_grapheme(lattice_sequence@sequence:sequence(binary()), integer()) -> {ok, {lattice_sequence@sequence:sequence(binary()), lattice_sequence@sequence:sequence(binary())}} | {error, range_error()}.
delete_grapheme(Seq, Index) ->
    case lattice_sequence@sequence:delete_with_delta(Seq, Index) of
        {ok, Pair} ->
            {ok, Pair};

        {error, {delete_index_out_of_bounds, Index@1, Length}} ->
            {error, {range_out_of_bounds, Index@1, Index@1, Length}}
    end.

-file("src/lattice_text/text.gleam", 424).
-spec empty_sequence_delta(lattice_sequence@sequence:sequence(binary())) -> lattice_sequence@sequence:sequence(binary()).
empty_sequence_delta(Seq) ->
    lattice_sequence@sequence:new(lattice_sequence@sequence:replica_id(Seq)).

-file("src/lattice_text/text.gleam", 412).
-spec delete_graphemes_with_delta(lattice_sequence@sequence:sequence(binary()), integer(), integer()) -> {ok, {lattice_sequence@sequence:sequence(binary()), lattice_sequence@sequence:sequence(binary())}} | {error, range_error()}.
delete_graphemes_with_delta(Seq, Start, End) ->
    gleam@bool:guard(Start =:= End, {ok, {Seq, empty_sequence_delta(Seq)}}, fun() ->
        Replica = lattice_sequence@sequence:replica_id(Seq),
        lattice_text_core@grapheme:delete_graphemes(Seq, Start, End, fun delete_grapheme/2, fun(A, B) ->
            lattice_sequence@sequence:merge(A, B, Replica)
        end)
    end).

-file("src/lattice_text/text.gleam", 185).
-spec delete_range_with_delta(text(), integer(), integer()) -> {ok, {text(), text()}} | {error, range_error()}.
-doc(~" Delete a grapheme range and return both the updated text and deletion
 delta.

 Returns `RangeOutOfBounds` when the range is outside `[0, length]`
 or `start > end`.").
delete_range_with_delta(Text, Start, End) ->
    {text, Seq} = Text,
    gleam@result:'try'(validate_range(Start, End, lattice_sequence@sequence:length(Seq)), fun(_use0) ->
        nil = _use0,
        _pipe = delete_graphemes_with_delta(Seq, Start, End),
        gleam@result:map(_pipe, fun(Pair) ->
            {Updated, Delta} = Pair,
            {{text, Updated}, {text, Delta}}
        end)
    end).

-file("src/lattice_text/text.gleam", 171).
-spec delete_range(text(), integer(), integer()) -> {ok, text()} | {error, range_error()}.
-doc(~" Delete the graphemes in `[start, end)`.

 ## Examples

 ```gleam
 let assert Ok(doc) = text.insert(text.new(replica_id.new(\"A\")), 0, \"abcd\")
 let assert Ok(doc) = text.delete_range(doc, 1, 3)
 text.value(doc)
 // -> \"ad\"
 ```

 Returns `RangeOutOfBounds` when the range is outside `[0, length]`
 or `start > end`.").
delete_range(Text, Start, End) ->
    _pipe = delete_range_with_delta(Text, Start, End),
    gleam@result:map(_pipe, fun(Pair) ->
        erlang:element(1, Pair)
    end).

-file("src/lattice_text/text.gleam", 407).
-spec insert_error_to_range_error(lattice_sequence@sequence:insert_error()) -> range_error().
insert_error_to_range_error(Error) ->
    {index_out_of_bounds, Index, Length} = Error,
    {range_out_of_bounds, Index, Index, Length}.

-file("src/lattice_text/text.gleam", 227).
-spec replace_range_with_delta(text(), integer(), integer(), binary()) -> {ok, {text(), text()}} | {error, range_error()}.
-doc(~" Replace a grapheme range and return both the updated text and
 replacement delta.

 Returns `RangeOutOfBounds` when the range is outside `[0, length]`
 or `start > end`.").
replace_range_with_delta(Text, Start, End, Value) ->
    {text, Seq} = Text,
    Replica = lattice_sequence@sequence:replica_id(Seq),
    gleam@result:'try'(validate_range(Start, End, lattice_sequence@sequence:length(Seq)), fun(_use0) ->
        nil = _use0,
        gleam@result:'try'(delete_graphemes_with_delta(Seq, Start, End), fun(_use0@1) ->
            {Deleted, Delete_delta} = _use0@1,
            Graphemes = gleam@string:to_graphemes(Value),
            gleam@result:'try'(begin
                _pipe = insert_graphemes_with_delta(Graphemes, Deleted, Start),
                gleam@result:map_error(_pipe, fun insert_error_to_range_error/1)
            end, fun(_use0@2) ->
                {Updated, Insert_delta} = _use0@2,
                Delta = case {Start =:= End, Graphemes} of
                    {true, _} ->
                        Insert_delta;

                    {false, []} ->
                        Delete_delta;

                    {false, _} ->
                        lattice_sequence@sequence:merge(Delete_delta, Insert_delta, Replica)
                end,
                {ok, {{text, Updated}, {text, Delta}}}
            end)
        end)
    end).

-file("src/lattice_text/text.gleam", 212).
-spec replace_range(text(), integer(), integer(), binary()) -> {ok, text()} | {error, range_error()}.
-doc(~" Replace the graphemes in `[start, end)` with a value.

 ## Examples

 ```gleam
 let assert Ok(doc) = text.insert(text.new(replica_id.new(\"A\")), 0, \"abcd\")
 let assert Ok(doc) = text.replace_range(doc, 1, 3, \"XY\")
 text.value(doc)
 // -> \"aXYd\"
 ```

 Returns `RangeOutOfBounds` when the range is outside `[0, length]`
 or `start > end`.").
replace_range(Text, Start, End, Value) ->
    _pipe = replace_range_with_delta(Text, Start, End, Value),
    gleam@result:map(_pipe, fun(Pair) ->
        erlang:element(1, Pair)
    end).

-file("src/lattice_text/text.gleam", 284).
-spec move_with_delta(text(), integer(), integer()) -> {ok, {text(), text()}} | {error, lattice_sequence@sequence:move_error()}.
-doc(~" Move a grapheme and return both the updated text and move delta.

 Returns a `MoveError` when either index is out of bounds.

 The `to_index` is interpreted after removing the grapheme from
 `from_index`.").
move_with_delta(Text, From_index, To_index) ->
    {text, Seq} = Text,
    case lattice_sequence@sequence:move_with_delta(Seq, From_index, To_index) of
        {ok, {Updated, Delta}} ->
            {ok, {{text, Updated}, {text, Delta}}};

        {error, Error} ->
            {error, Error}
    end.

-file("src/lattice_text/text.gleam", 269).
-spec move(text(), integer(), integer()) -> {ok, text()} | {error, lattice_sequence@sequence:move_error()}.
-doc(~" Move the grapheme at `from_index` to `to_index`.

 The `to_index` is interpreted after removing the grapheme from
 `from_index`.

 ## Examples

 ```gleam
 let assert Ok(doc) = text.insert(text.new(replica_id.new(\"A\")), 0, \"abc\")
 let assert Ok(doc) = text.move(doc, 0, 2)
 text.value(doc)
 // -> \"bca\"
 ```

 Returns a `MoveError` when either index is out of bounds.").
move(Text, From_index, To_index) ->
    _pipe = move_with_delta(Text, From_index, To_index),
    gleam@result:map(_pipe, fun(Pair) ->
        erlang:element(1, Pair)
    end).

-file("src/lattice_text/text.gleam", 297).
-spec start_anchor() -> lattice_sequence@sequence:anchor().
-doc(~" Create an anchor at the start of the text. Always resolves to 0.").
start_anchor() ->
    lattice_sequence@sequence:start_anchor().

-file("src/lattice_text/text.gleam", 303).
-spec end_anchor() -> lattice_sequence@sequence:anchor().
-doc(~" Create an anchor at the end of the text. Always resolves to the current
 grapheme length, tracking growth.").
end_anchor() ->
    lattice_sequence@sequence:end_anchor().

-file("src/lattice_text/text.gleam", 323).
-spec anchor_at(text(), integer(), lattice_sequence@sequence:bias()) -> {ok, lattice_sequence@sequence:anchor()} | {error, lattice_sequence@sequence:anchor_error()}.
-doc(~" Create an anchor at the gap before the grapheme at `index`.

 Anchors are stable positions that survive concurrent edits and merges:
 resolve one back to a current grapheme index with `resolve_anchor`.
 `Before` bias glues the anchor to the grapheme at `index`, so inserts at
 the gap push it right; `After` bias glues it to the grapheme at
 `index - 1`, so inserts at the gap land after it.

 ## Examples

 ```gleam
 let assert Ok(doc) = text.insert(text.new(replica_id.new(\"A\")), 0, \"hello\")
 let assert Ok(cursor) = text.anchor_at(doc, 5, sequence.After)
 let assert Ok(doc) = text.insert(doc, 0, \"say \")
 text.resolve_anchor(doc, cursor)  // -> Ok(9)
 ```").
anchor_at(Text, Index, Bias) ->
    {text, Seq} = Text,
    lattice_sequence@sequence:anchor_at(Seq, Index, Bias).

-file("src/lattice_text/text.gleam", 346).
-spec resolve_anchor(text(), lattice_sequence@sequence:anchor()) -> {ok, integer()} | {error, lattice_sequence@sequence:anchor_error()}.
-doc(~" Resolve an anchor to a current grapheme index in `[0, length]`.

 Anchors on deleted graphemes still resolve: they collapse to the gap
 where the grapheme used to be. Anchors follow moved graphemes.

 Anchors to compacted graphemes resolve through the forwarding map to the
 gap the grapheme left behind — semantically the same as tombstone
 collapse.

 Returns `Error(UnknownAnchorTarget)` when the anchor references a
 grapheme this replica has never seen (created remotely and not yet
 merged), or one that was compacted away and whose forwarding entry has
 since been removed by the host's retention policy. Either way the anchor
 is unusable and the holder should re-anchor.").
resolve_anchor(Text, Anchor) ->
    {text, Seq} = Text,
    lattice_sequence@sequence:resolve(Seq, Anchor).

-file("src/lattice_text/text.gleam", 355).
-spec anchor_to_json(lattice_sequence@sequence:anchor()) -> gleam@json:json().
-doc(~" Encode an anchor as a self-describing JSON value.").
anchor_to_json(Anchor) ->
    lattice_sequence@sequence:anchor_to_json(Anchor).

-file("src/lattice_text/text.gleam", 360).
-spec anchor_from_json(binary()) -> {ok, lattice_sequence@sequence:anchor()} | {error, gleam@json:decode_error()}.
-doc(~" Decode an anchor from a JSON string produced by `anchor_to_json`.").
anchor_from_json(Json_string) ->
    lattice_sequence@sequence:anchor_from_json(Json_string).

-file("src/lattice_text/text.gleam", 384).
-spec append_with_delta(text(), binary()) -> {ok, {text(), text()}} | {error, lattice_sequence@sequence:insert_error()}.
-doc(~" Append a value and return both the updated text and insertion delta.").
append_with_delta(Text, Value) ->
    insert_with_delta(Text, length(Text), Value).

-file("src/lattice_text/text.gleam", 378).
-spec append(text(), binary()) -> {ok, text()} | {error, lattice_sequence@sequence:insert_error()}.
-doc(~" Insert a value at the end of the text.

 Returns the insertion result, like `insert`.

 ## Examples

 ```gleam
 let assert Ok(doc) = text.insert(text.new(replica_id.new(\"A\")), 0, \"ab\")
 let assert Ok(doc) = text.append(doc, \"cd\")
 text.value(doc)
 // -> \"abcd\"
 ```").
append(Text, Value) ->
    _pipe = append_with_delta(Text, Value),
    gleam@result:map(_pipe, fun(Pair) ->
        erlang:element(1, Pair)
    end).

-file("src/lattice_text/text.gleam", 465).
-spec compact(text(), lattice_core@version_vector:version_vector()) -> {text(), lattice_sequence@sequence:forwarding_map()}.
-doc(~" Compact everything at or below a stability frontier.

 Delegates to `sequence.compact`: stable tombstones are dropped, runs of
 stable graphemes are merged into compact blocks, and every dropped ID
 gets a forwarding entry so anchors and rebased operations still resolve.
 See `lattice_sequence/sequence.compact` for the stability contract.").
compact(Text, Stable) ->
    {text, Seq} = Text,
    {Compacted, Forwardings} = lattice_sequence@sequence:compact(Seq, Stable),
    {{text, Compacted}, Forwardings}.

-file("src/lattice_text/text.gleam", 479).
-spec remove_forwardings(text(), lattice_sequence@sequence:forwarding_map()) -> text().
-doc(~" Remove previously emitted forwarding entries from the text.

 Forwardings are bounded by the host's retention policy: keep the map
 returned by each `compact` round and expire old rounds by passing them
 here.").
remove_forwardings(Text, Map) ->
    {text, Seq} = Text,
    {text, lattice_sequence@sequence:remove_forwardings(Seq, Map)}.

-file("src/lattice_text/text.gleam", 485).
-spec frontier(text()) -> lattice_core@version_vector:version_vector().
-doc(~" The stability frontier this text was last compacted at.").
frontier(Text) ->
    {text, Seq} = Text,
    lattice_sequence@sequence:frontier(Seq).

-file("src/lattice_text/text.gleam", 502).
-spec bind(text(), lattice_core@replica_id:replica_id()) -> text().
-doc(~" Select the local editor without rebuilding the underlying sequence.

 Preserves historical item IDs, counters, and compaction metadata.
 Independent writers must use distinct replica IDs.

 ## Examples

 ```gleam
 let assert Ok(remote) = text.insert(text.new(replica_id.new(\"A\")), 0, \"hello\")
 text.bind(remote, replica_id.new(\"B\")) |> text.value()
 // -> \"hello\"
 ```").
bind(Text, Replica) ->
    {text, Seq} = Text,
    {text, lattice_sequence@sequence:bind(Seq, Replica)}.

-file("src/lattice_text/text.gleam", 522).
-spec merge(text(), text(), lattice_core@replica_id:replica_id()) -> text().
-doc(~" Merge two text CRDT states.

 Pass the identity used for subsequent local edits. Operand order does not
 select the identity. Deltas and decoded snapshots retain their sender's
 identity; merge them under your local identity before editing. Independent
 writers must use distinct replica IDs.

 ## Examples

 ```gleam
 let local = replica_id.new(\"A\")
 text.merge(text.new(local), text.new(replica_id.new(\"B\")), local)
 |> text.value()
 // -> \"\"
 ```").
merge(A, B, Replica) ->
    {text, A_seq} = A,
    {text, B_seq} = B,
    {text, lattice_sequence@sequence:merge(A_seq, B_seq, Replica)}.

-file("src/lattice_text/text.gleam", 536).
-spec merge_as(text(), text(), lattice_core@replica_id:replica_id()) -> text().
-doc(~" Alias for `merge`, with the same explicit output replica identity.

 ## Examples

 ```gleam
 text.merge_as(a, b, local) == text.merge(a, b, local)
 // -> True
 ```").
merge_as(A, B, Replica) ->
    merge(A, B, Replica).

-file("src/lattice_text/text.gleam", 541).
-spec to_json(text()) -> gleam@json:json().
-doc(~" Encode text using the canonical sequence JSON envelope.").
to_json(Text) ->
    {text, Seq} = Text,
    lattice_sequence@sequence:to_json(Seq, fun gleam@json:string/1).

-file("src/lattice_text/text.gleam", 551).
-spec from_json(binary()) -> {ok, text()} | {error, gleam@json:decode_error()}.
-doc(~" Decode text from the canonical sequence JSON envelope.

 Retains historical IDs and raises an understated allocation counter to
 cover retained IDs and the compaction frontier, as `sequence.from_json`
 does. Use `bind` with the local identity before editing an adopted state.").
from_json(Json_string) ->
    case lattice_sequence@sequence:from_json(Json_string, {decoder, fun gleam@dynamic@decode:decode_string/1}) of
        {ok, Seq} ->
            {ok, {text, Seq}};

        {error, Error} ->
            {error, Error}
    end.

