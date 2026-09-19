-module(lattice_text_core@grapheme).
-compile([no_auto_import, nowarn_ignored, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-export([validate_range/3, value/1, slice/3, insert_graphemes/6, delete_graphemes/5]).
-export_type([range_error/0]).
-moduledoc(~" Backend-agnostic grapheme and range helpers shared by lattice text CRDTs.

 A text CRDT is a sequence CRDT of single-grapheme values plus a thin layer
 of grapheme/range bookkeeping: splitting inserted strings into graphemes,
 validating `[start, end)` ranges, slicing out substrings, and folding
 multi-grapheme inserts/deletes into a single mergeable delta. That layer is
 identical regardless of which sequence CRDT stores the graphemes, so it
 lives here and is shared by `lattice_text` (backed by `lattice_sequence`)
 and `lattice_text_fugue` (backed by `lattice_fugue`).

 The multi-grapheme fold helpers are generic over the backend's state type
 `s` and take the backend's `insert`, `delete`, and `merge` as ordinary
 function arguments, so no dependency on any particular sequence package is
 needed.").

-type range_error() :: {range_out_of_bounds, integer(), integer(), integer()}.

-file("src/lattice_text_core/grapheme.gleam", 37).
-spec validate_range(integer(), integer(), integer()) -> {ok, nil} | {error, range_error()}.
-doc(~" Validate that `[start, end)` is a range within `[0, length]`.

 ## Examples

 ```gleam
 validate_range(1, 3, 4)
 // -> Ok(Nil)
 validate_range(0, 5, 3)
 // -> Error(RangeOutOfBounds(start: 0, end: 5, length: 3))
 ```").
validate_range(Start, End, Length) ->
    gleam@bool:guard(((Start < 0) orelse (End > Length)) orelse (Start > End), {error, {range_out_of_bounds, Start, End, Length}}, fun() ->
        {ok, nil}
    end).

-file("src/lattice_text_core/grapheme.gleam", 50).
-spec value(list(binary())) -> binary().
-doc(~" Concatenate a list of graphemes into a single string.").
value(Graphemes) ->
    erlang:list_to_binary(Graphemes).

-file("src/lattice_text_core/grapheme.gleam", 58).
-spec slice(list(binary()), integer(), integer()) -> binary().
-doc(~" Return the graphemes in `[start, end)` as a string.

 Indexes are used as-is (no clamping); callers that need clamping or
 validation should apply it first with `validate_range`.").
slice(Graphemes, Start, End) ->
    _pipe = Graphemes,
    _pipe@1 = gleam@list:drop(_pipe, Start),
    _pipe@2 = gleam@list:take(_pipe@1, End - Start),
    erlang:list_to_binary(_pipe@2).

-file("src/lattice_text_core/grapheme.gleam", 78).
-spec insert_graphemes(list(binary()), DKY, integer(), fun((DKY) -> integer()), fun((DKY, integer(), list(binary())) -> {ok, {DKY, DKY}} | {error, DLA}), fun((integer(), integer()) -> DLA)) -> {ok, {DKY, DKY}} | {error, DLA}.
-doc(~" Insert a list of graphemes at `index` as a single batched operation,
 returning the updated state and one delta covering every inserted node.

 Generic over the backend state `s` and insert-error `e`:
 - `length` reports the backend's current visible length.
 - `insert_many` inserts the whole grapheme run starting at `index`,
   returning the updated state and its combined delta, or a backend error.
 - `index_out_of_bounds` builds the backend error for an invalid `index`.

 Returns `Error` (via `index_out_of_bounds`) when `index` is outside
 `[0, length]`, mirroring the backend's own bounds contract even when the
 grapheme list is empty. An empty grapheme list at a valid index is passed
 to `insert_many`, allowing the backend to return its neutral delta.").
insert_graphemes(Graphemes, State, Index, Length, Insert_many, Index_out_of_bounds) ->
    Len = Length(State),
    case (Index < 0) orelse (Index > Len) of
        true ->
            {error, Index_out_of_bounds(Index, Len)};

        false ->
            Insert_many(State, Index, Graphemes)
    end.

-file("src/lattice_text_core/grapheme.gleam", 104).
-spec delete_graphemes(DLF, integer(), integer(), fun((DLF, integer()) -> {ok, {DLF, DLF}} | {error, DLG}), fun((DLF, DLF) -> DLF)) -> {ok, {DLF, DLF}} | {error, DLG}.
-doc(~" Delete the graphemes in `[start, end)` one at a time, threading a merged
 delta of every deletion.

 Generic over the backend state `s` and delete-error `e`:
 - `delete` deletes the single grapheme at an index, returning the updated
   state and its delta, or the backend's own error.
 - `merge` joins two deltas.

 Repeatedly deletes at `start`, since each deletion shifts the following
 graphemes left. An empty range is a no-op whose delta is the unchanged
 state.").
delete_graphemes(State, Start, End, Delete, Merge) ->
    case End - Start of
        Count when Count =< 0 ->
            {ok, {State, State}};

        Count@1 ->
            gleam@result:'try'(Delete(State, Start), fun(_use0) ->
                {First_state, First_delta} = _use0,
                _pipe = gleam@list:repeat(nil, Count@1 - 1),
                gleam@list:try_fold(_pipe, {First_state, First_delta}, fun(Acc, _) ->
                    {Current, Delta} = Acc,
                    gleam@result:'try'(Delete(Current, Start), fun(_use0@1) ->
                        {Updated, Next_delta} = _use0@1,
                        {ok, {Updated, Merge(Delta, Next_delta)}}
                    end)
                end)
            end)
    end.

