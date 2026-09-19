-module(lattice_sequence@sequence).
-compile([no_auto_import, nowarn_ignored, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-export([new/1, replica_id/1, insert_many_with_delta/3, insert_with_delta/3, insert/3, insert_many/3, delete_with_delta/2, delete/2, move_with_delta/3, move/3, start_anchor/0, end_anchor/0, anchor_at/3, resolve/2, anchor_to_json/1, anchor_from_json/1, values/1, bind/2, length/1, frontier/1, forwarding_size/1, remove_forwardings/2, merge/3, merge_as/3, compact/2, translate_origins/2, to_json/2, from_json/2]).
-export_type([item_id/0, op_id/0, move/0, item/1, segment/1, element/1, forwarding/0, forwarding_map/0, sequence/1, insert_error/0, delete_error/0, move_error/0, translate_error/0, bias/0, anchor/0, anchor_error/0, move_target/0, classified/1, stability/0, scan_entry/0, scan_step/0]).
-moduledoc(~" A generic sequence CRDT using stable item IDs and YATA-style origins.

 Each live item is stored with a stable internal ID plus left and right
 origins for deterministic ordering. Deletes are represented as tombstones
 that record the delete's op ID; `values` returns only non-deleted items.

 The public editing API exposes index-based insert, delete, and move
 operations while resolving stable item IDs internally, so callers do not
 need to construct or manage item identifiers. Moves preserve item identity
 and converge with single-winner semantics for concurrent moves of the same
 item.

 ## Replica identity

 A sequence carries the replica ID it mints item IDs under. Both `merge`
 and its alias `merge_as` require that identity explicitly:
 `merge(state, incoming, local_replica)`. Operand order does not select
 the output identity. Deltas and decoded snapshots retain their sender's
 identity; merge them under your local identity before editing. Independent
 writers must use distinct replica IDs.

 ## Compaction

 Long-lived sequences never shrink on their own: every delete leaves a
 tombstone and every item carries origins. `compact` takes a stability
 frontier — a `VersionVector` meaning \"everything causally at or below
 this is stable; no in-flight or future op references it\" — and rewrites
 the stable region: stable tombstones are dropped, runs of adjacent stable
 items from the same replica with sequential counters are merged into
 compact blocks, and origins of stable items are discarded. Items above
 the frontier keep their full YATA representation.

 Every dropped ID gets a forwarding entry pointing at its retained
 neighbors, so anchors and rebased operations that still hold the ID can
 resolve to the gap it left behind. The forwarding map and the applied
 frontier travel with the state. Deriving a correct frontier is the
 host's job (e.g. from a global sequencer's acknowledgement floor); the
 frontier must be a causal cut over the ops applied to the sequence.

 ## Example

 ```gleam
 import lattice_core/replica_id
 import lattice_sequence/sequence

 let assert Ok(list) =
   sequence.insert_many(sequence.new(replica_id.new(\"node-a\")), 0, [
     \"hello\", \"world\",
   ])
 let assert Ok(list) = sequence.move(list, 0, 1)

 sequence.values(list)  // -> [\"world\", \"hello\"]
 ```").

-opaque item_id() :: {item_id, lattice_core@replica_id:replica_id(), integer()}.

-type op_id() :: {op_id, lattice_core@replica_id:replica_id(), integer()}.

-type move() :: {move, op_id(), gleam@option:option(item_id()), gleam@option:option(item_id())}.

-type item(DSH) :: {item, item_id(), gleam@option:option(item_id()), gleam@option:option(item_id()), DSH, gleam@option:option(op_id()), gleam@option:option(move())}.

-type segment(DSI) :: {block, item_id(), list(DSI)} | {live, item(DSI)}.

-type element(DSJ) :: {stable, item_id(), DSJ} | {live_el, item(DSJ)}.

-type forwarding() :: {forwarding, gleam@option:option(item_id()), gleam@option:option(item_id())}.

-opaque forwarding_map() :: {forwarding_map, gleam@dict:dict(item_id(), forwarding())}.

-opaque sequence(DSK) :: {sequence, lattice_core@replica_id:replica_id(), integer(), list(segment(DSK)), gleam@dict:dict(item_id(), forwarding()), lattice_core@version_vector:version_vector()}.

-type insert_error() :: {index_out_of_bounds, integer(), integer()}.

-type delete_error() :: {delete_index_out_of_bounds, integer(), integer()}.

-type move_error() :: {move_from_index_out_of_bounds, integer(), integer()} | {move_to_index_out_of_bounds, integer(), integer()}.

-type translate_error() :: unknown_origin_target.

-type bias() :: before | 'after'.

-opaque anchor() :: start | 'end' | {at_item, item_id(), bias()}.

-type anchor_error() :: {anchor_index_out_of_bounds, integer(), integer()} | unknown_anchor_target.

-type move_target() :: {before_element, item_id()} | {after_gap, gleam@option:option(item_id())} | at_end.

-type classified(DSL) :: {retained, element(DSL)} | {dropped, item_id()}.

-type stability() :: drop_tombstone | to_stable | keep_live.

-type scan_entry() :: {scan_entry, item_id(), gleam@option:option(item_id()), gleam@option:option(item_id()), boolean()}.

-type scan_step() :: stop_scan | take_as_left | advance_past.

-file("src/lattice_sequence/sequence.gleam", 190).
-spec new(lattice_core@replica_id:replica_id()) -> sequence(any()).
-doc(~" Create an empty sequence for a replica.").
new(Replica_id) ->
    {sequence, Replica_id, 0, [], maps:new(), lattice_core@version_vector:new()}.

-file("src/lattice_sequence/sequence.gleam", 2113).
-spec flush_run(gleam@option:option({item_id(), list(EFX), item_id()}), list(segment(EFX))) -> list(segment(EFX)).
flush_run(Run, Acc) ->
    case Run of
        none ->
            Acc;

        {some, {First, Values_rev, _}} ->
            [{block, First, lists:reverse(Values_rev)} | Acc]
    end.

-file("src/lattice_sequence/sequence.gleam", 2126).
-spec follows(item_id(), item_id()) -> boolean().
follows(Last, Next) ->
    {item_id, Last_rid, Last_counter} = Last,
    {item_id, Next_rid, Next_counter} = Next,
    (Last_rid =:= Next_rid) andalso (Next_counter =:= (Last_counter + 1)).

-file("src/lattice_sequence/sequence.gleam", 2082).
-spec chunk_elements(list(element(EFO)), gleam@option:option({item_id(), list(EFO), item_id()}), list(segment(EFO))) -> list(segment(EFO)).
chunk_elements(Elements, Run, Acc) ->
    case Elements of
        [] ->
            flush_run(Run, Acc);

        [{live_el, Item} | Rest] ->
            chunk_elements(Rest, none, [{live, Item} | flush_run(Run, Acc)]);

        [{stable, Id, Value} | Rest@1] ->
            case Run of
                {some, {First, Values_rev, Last}} ->
                    case follows(Last, Id) of
                        true ->
                            chunk_elements(Rest@1, {some, {First, [Value | Values_rev], Id}}, Acc);

                        false ->
                            chunk_elements(Rest@1, {some, {Id, [Value], Id}}, flush_run(Run, Acc))
                    end;

                none ->
                    chunk_elements(Rest@1, {some, {Id, [Value], Id}}, Acc)
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 2077).
-spec elements_to_segments(list(element(EFJ))) -> list(segment(EFJ)).
elements_to_segments(Elements) ->
    _pipe = chunk_elements(Elements, none, []),
    lists:reverse(_pipe).

-file("src/lattice_sequence/sequence.gleam", 2132).
-spec element_id(element(any())) -> item_id().
element_id(El) ->
    case El of
        {stable, Id, _} ->
            Id;

        {live_el, Item} ->
            erlang:element(2, Item)
    end.

-file("src/lattice_sequence/sequence.gleam", 361).
-spec insert_run_after_id(list(element(DUA)), item_id(), list(element(DUA)), list(element(DUA))) -> list(element(DUA)).
insert_run_after_id(Elements, After, Run, Prefix_reversed) ->
    case Elements of
        [] ->
            gleam@list:fold(Prefix_reversed, Run, fun(Tail, El) ->
                [El | Tail]
            end);

        [First | Rest] ->
            case element_id(First) =:= After of
                true ->
                    gleam@list:fold(Prefix_reversed, [First | lists:append(Run, Rest)], fun(Tail, El) ->
                        [El | Tail]
                    end);

                false ->
                    insert_run_after_id(Rest, After, Run, [First | Prefix_reversed])
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 350).
-spec splice_run_after(list(element(DTS)), gleam@option:option(item_id()), list(element(DTS))) -> list(element(DTS)).
-doc(~" Splice a run of elements into the stored order immediately after `after`
 (or at the head when `after` is `None`), preserving run order.").
splice_run_after(Elements, After, Run) ->
    case After of
        none ->
            lists:append(Run, Elements);

        {some, Id} ->
            insert_run_after_id(Elements, Id, Run, [])
    end.

-file("src/lattice_sequence/sequence.gleam", 317).
-spec build_insert_run(lattice_core@replica_id:replica_id(), integer(), list(DTM), gleam@option:option(item_id()), gleam@option:option(item_id())) -> {list(item(DTM)), integer()}.
-doc(~" Build a contiguous run of new items with chained left origins and a shared
 right origin, minting consecutive counters from `start_counter`. Returns
 the items in insertion order and the last counter used.").
build_insert_run(Replica_id, Start_counter, Values, Origin_left, Origin_right) ->
    Items = gleam@list:index_map(Values, fun(Value, Offset) ->
        Left = case Offset of
            0 ->
                Origin_left;

            _ ->
                {some, {item_id, Replica_id, (Start_counter + Offset) - 1}}
        end,
        {item, {item_id, Replica_id, Start_counter + Offset}, Left, Origin_right, Value, none, none}
    end),
    {Items, (Start_counter + erlang:length(Values)) - 1}.

-file("src/lattice_sequence/sequence.gleam", 2204).
-spec next_element_id(list(element(any()))) -> gleam@option:option(item_id()).
next_element_id(Elements) ->
    case Elements of
        [] ->
            none;

        [El | _] ->
            {some, element_id(El)}
    end.

-file("src/lattice_sequence/sequence.gleam", 2193).
-spec successor_of(list(element(any())), item_id()) -> gleam@option:option(item_id()).
successor_of(Elements, Id) ->
    case Elements of
        [] ->
            none;

        [El | Rest] ->
            case element_id(El) =:= Id of
                true ->
                    next_element_id(Rest);

                false ->
                    successor_of(Rest, Id)
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 2183).
-spec canonical_successor(list(element(any())), gleam@option:option(item_id())) -> gleam@option:option(item_id()).
-doc(~" The element that follows `left` in the canonical order (`None` means the
 head of the document, so the first canonical element).").
canonical_successor(Base, Left) ->
    case Left of
        none ->
            next_element_id(Base);

        {some, Id} ->
            successor_of(Base, Id)
    end.

-file("src/lattice_sequence/sequence.gleam", 2139).
-spec element_is_visible(element(any())) -> boolean().
element_is_visible(El) ->
    case El of
        {stable, _, _} ->
            true;

        {live_el, Item} ->
            erlang:element(6, Item) =:= none
    end.

-file("src/lattice_sequence/sequence.gleam", 2163).
-spec visible_element_id_at(list(element(any())), integer()) -> gleam@option:option(item_id()).
visible_element_id_at(Elements, Index) ->
    case Elements of
        [] ->
            none;

        [El | Rest] ->
            case element_is_visible(El) of
                true ->
                    case Index =:= 0 of
                        true ->
                            {some, element_id(El)};

                        false ->
                            visible_element_id_at(Rest, Index - 1)
                    end;

                false ->
                    visible_element_id_at(Rest, Index)
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 2039).
-spec empty_delta(lattice_core@replica_id:replica_id()) -> sequence(any()).
-doc(~" An empty delta carrying no items — the neutral element for `merge`,
 returned when an insert covers zero values.").
empty_delta(Replica_id) ->
    {sequence, Replica_id, 0, [], maps:new(), lattice_core@version_vector:new()}.

-file("src/lattice_sequence/sequence.gleam", 2153).
-spec visible_length_elements(list(element(any()))) -> integer().
visible_length_elements(Elements) ->
    _pipe = Elements,
    gleam@list:fold(_pipe, 0, fun(Count, El) ->
        case element_is_visible(El) of
            true ->
                Count + 1;

            false ->
                Count
        end
    end).

-file("src/lattice_sequence/sequence.gleam", 2226).
-spec insert_element_after_id(list(element(EHK)), item_id(), element(EHK)) -> list(element(EHK)).
insert_element_after_id(Elements, Left, El) ->
    case Elements of
        [] ->
            [El];

        [First | Rest] ->
            case element_id(First) =:= Left of
                true ->
                    [First, El | Rest];

                false ->
                    [First | insert_element_after_id(Rest, Left, El)]
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 1244).
-spec splice_into_gap(list(element(DZY)), {ok, item_id()} | {error, nil}, gleam@option:option(item_id()), element(DZY)) -> list(element(DZY)).
splice_into_gap(Elements, Previous_in_gap, Anchor, El) ->
    case {Previous_in_gap, Anchor} of
        {{ok, Previous}, _} ->
            insert_element_after_id(Elements, Previous, El);

        {{error, nil}, none} ->
            [El | Elements];

        {{error, nil}, {some, Left_id}} ->
            insert_element_after_id(Elements, Left_id, El)
    end.

-file("src/lattice_sequence/sequence.gleam", 1197).
-spec canonical_after_gap(gleam@option:option(item_id()), gleam@dict:dict(item_id(), gleam@option:option(item_id()))) -> gleam@option:option(item_id()).
-doc(~" Canonicalize an `AfterGap` key without changing its physical splice anchor.

 Base tombstones map to their preceding visible neighbour. An absent ID is
 a mover already placed in this pass, so it remains its own gap anchor.").
canonical_after_gap(Anchor, After_gap_anchors) ->
    case Anchor of
        none ->
            none;

        {some, Id} ->
            case gleam_stdlib:map_get(After_gap_anchors, Id) of
                {ok, Anchor@1} ->
                    Anchor@1;

                {error, nil} ->
                    {some, Id}
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 2211).
-spec insert_element_before_id(list(element(EHE)), item_id(), element(EHE)) -> list(element(EHE)).
insert_element_before_id(Elements, Right, El) ->
    case Elements of
        [] ->
            [El];

        [First | Rest] ->
            case element_id(First) =:= Right of
                true ->
                    [El, First | Rest];

                false ->
                    [First | insert_element_before_id(Rest, Right, El)]
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 1222).
-spec splice_before_and_record(list(element(DZJ)), gleam@dict:dict(gleam@option:option(item_id()), item_id()), gleam@dict:dict(item_id(), gleam@option:option(item_id())), item_id(), element(DZJ)) -> {list(element(DZJ)), gleam@dict:dict(gleam@option:option(item_id()), item_id())}.
-doc(~" Splice a `BeforeElement` landing after any earlier mover in the same gap,
 then record it as the gap's rightmost mover.

 Usually inserting immediately before `right_id` lands at the right end of
 its gap. Tombstones can put an earlier co-gap mover physically after that
 boundary while remaining in the same visible gap, though, so the tracked
 mover is authoritative when present.

 A `right_id` absent from the base is a mover placed earlier in this pass.
 Landing before it is not the gap's right end, so there is nothing to
 record and the previous entry stands.").
splice_before_and_record(Elements, Last_in_gap, Gap_anchors, Right_id, El) ->
    case gleam_stdlib:map_get(Gap_anchors, Right_id) of
        {ok, Anchor} ->
            {case gleam_stdlib:map_get(Last_in_gap, Anchor) of
                {ok, Previous} ->
                    insert_element_after_id(Elements, Previous, El);

                {error, nil} ->
                    insert_element_before_id(Elements, Right_id, El)
            end, gleam@dict:insert(Last_in_gap, Anchor, element_id(El))};

        {error, nil} ->
            {insert_element_before_id(Elements, Right_id, El), Last_in_gap}
    end.

-file("src/lattice_sequence/sequence.gleam", 2241).
-spec contains_element_id(list(element(any())), item_id()) -> boolean().
contains_element_id(Elements, Id) ->
    gleam@list:any(Elements, fun(El) ->
        element_id(El) =:= Id
    end).

-file("src/lattice_sequence/sequence.gleam", 2853).
-spec chase_left(gleam@option:option(item_id()), gleam@dict:dict(item_id(), forwarding()), integer()) -> gleam@option:option(item_id()).
chase_left(Target, Entries, Fuel) ->
    case {Target, Fuel =< 0} of
        {none, _} ->
            none;

        {_, true} ->
            Target;

        {{some, Id}, false} ->
            case gleam_stdlib:map_get(Entries, Id) of
                {ok, {forwarding, Left, _}} ->
                    chase_left(Left, Entries, Fuel - 1);

                {error, nil} ->
                    Target
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 1333).
-spec reclaimed_boundary_gap(list(element(any())), gleam@option:option(item_id()), gleam@dict:dict(item_id(), forwarding()), integer()) -> move_target().
-doc(~" The gap a reclaimed right boundary left behind, named by its left edge.

 The move targeted the gap immediately before that boundary, so once the
 boundary is gone the same gap is \"after whatever was retained to its
 left\". Falling back to the move's own left origin instead would aim at the
 far edge of the original gap and skip past everything inserted into it
 since the move was made — which is how a compacted replica and an
 uncompacted one end up ordering the mover differently.").
reclaimed_boundary_gap(Elements, Move_right, Forwardings, Fuel) ->
    case chase_left(Move_right, Forwardings, Fuel) of
        none ->
            {after_gap, none};

        {some, Left_id} ->
            case contains_element_id(Elements, Left_id) of
                true ->
                    {after_gap, {some, Left_id}};

                false ->
                    at_end
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 2869).
-spec chase_right(gleam@option:option(item_id()), gleam@dict:dict(item_id(), forwarding()), integer()) -> gleam@option:option(item_id()).
chase_right(Target, Entries, Fuel) ->
    case {Target, Fuel =< 0} of
        {none, _} ->
            none;

        {_, true} ->
            Target;

        {{some, Id}, false} ->
            case gleam_stdlib:map_get(Entries, Id) of
                {ok, {forwarding, _, Right}} ->
                    chase_right(Right, Entries, Fuel - 1);

                {error, nil} ->
                    Target
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 1305).
-spec reclaimed_boundary_target(list(element(any())), gleam@option:option(item_id()), gleam@dict:dict(item_id(), forwarding()), gleam@dict:dict(item_id(), nil), integer()) -> move_target().
-doc(~" Where a move lands when its right boundary was reclaimed by a pass.

 Prefer the nearest retained element to the boundary's right, so the move
 still splices before the same neighbour. A forwarded boundary that is
 itself being moved in this pass is not a faithful gap edge — a replica
 that still held the reclaimed target would not anchor on it — so that
 falls through to the gap's left edge instead.").
reclaimed_boundary_target(Elements, Move_right, Forwardings, Mover_ids, Fuel) ->
    case chase_right(Move_right, Forwardings, Fuel) of
        none ->
            reclaimed_boundary_gap(Elements, Move_right, Forwardings, Fuel);

        {some, Right_id} ->
            case not gleam@dict:has_key(Mover_ids, Right_id) andalso contains_element_id(Elements, Right_id) of
                true ->
                    {before_element, Right_id};

                false ->
                    reclaimed_boundary_gap(Elements, Move_right, Forwardings, Fuel)
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 1257).
-spec resolve_move_target(list(element(any())), gleam@option:option(item_id()), gleam@option:option(item_id()), gleam@dict:dict(item_id(), forwarding()), gleam@dict:dict(item_id(), nil)) -> move_target().
resolve_move_target(Elements, Move_left, Move_right, Forwardings, Mover_ids) ->
    Fuel = maps:size(Forwardings) + 1,
    Left_gap = case chase_left(Move_left, Forwardings, Fuel) of
        none ->
            {after_gap, none};

        {some, Left_id} ->
            case contains_element_id(Elements, Left_id) of
                true ->
                    {after_gap, {some, Left_id}};

                false ->
                    at_end
            end
    end,
    case Move_right of
        none ->
            Left_gap;

        {some, Raw_right} ->
            case contains_element_id(Elements, Raw_right) of
                true ->
                    {before_element, Raw_right};

                false ->
                    case gleam@dict:has_key(Forwardings, Raw_right) of
                        false ->
                            Left_gap;

                        true ->
                            reclaimed_boundary_target(Elements, Move_right, Forwardings, Mover_ids, Fuel)
                    end
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 1177).
-spec base_gap_anchors(list(element(any()))) -> {gleam@dict:dict(item_id(), gleam@option:option(item_id())), gleam@dict:dict(item_id(), gleam@option:option(item_id()))}.
-doc(~" Index the visible gaps on both sides of every element in the move-free base.

 Movers are spliced into the gaps of this base, so `BeforeElement(right)`
 and `AfterGap(left)` name the same gap exactly when `left` is `right`'s
 base predecessor. Keying both on that anchor is what lets co-gap movers
 stack in op order no matter which path each one resolved through.

 Tombstones do not split visible gaps and may disappear during compaction,
 so they keep the preceding visible anchor on both sides. This makes the
 gap key invariant when an unreferenced tombstone is reclaimed.").
base_gap_anchors(Elements) ->
    {Before, After, _} = gleam@list:fold(Elements, {maps:new(), maps:new(), none}, fun(Acc, El) ->
        {Before@1, After@1, Previous} = Acc,
        Id = element_id(El),
        Next = case element_is_visible(El) of
            true ->
                {some, Id};

            false ->
                Previous
        end,
        {gleam@dict:insert(Before@1, Id, Previous), gleam@dict:insert(After@1, Id, Next), Next}
    end),
    {Before, After}.

-file("src/lattice_sequence/sequence.gleam", 2256).
-spec remove_element_by_id(list(element(EHZ)), item_id()) -> list(element(EHZ)).
remove_element_by_id(Elements, Id) ->
    case Elements of
        [] ->
            [];

        [El | Rest] ->
            case element_id(El) =:= Id of
                true ->
                    Rest;

                false ->
                    [El | remove_element_by_id(Rest, Id)]
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 763).
-spec replica_id(sequence(any())) -> lattice_core@replica_id:replica_id().
-doc(~" Return the replica identity used for subsequent local edits.

 This accessor does not change the state. Use `bind` to adopt a snapshot
 without merging, or `merge` when combining state or deltas.

 ## Examples

 ```gleam
 let replica = replica_id.new(\"A\")
 sequence.replica_id(sequence.new(replica)) == replica
 // -> True
 ```").
replica_id(Sequence) ->
    erlang:element(2, Sequence).

-file("src/lattice_sequence/sequence.gleam", 2693).
-spec compare_item_ids(item_id(), item_id()) -> gleam@order:order().
compare_item_ids(A, B) ->
    {item_id, A_replica, A_counter} = A,
    {item_id, B_replica, B_counter} = B,
    case lattice_core@replica_id:compare(A_replica, B_replica) of
        eq ->
            gleam@int:compare(A_counter, B_counter);

        Other ->
            Other
    end.

-file("src/lattice_sequence/sequence.gleam", 2793).
-spec compare_op_ids(op_id(), op_id()) -> gleam@order:order().
compare_op_ids(A, B) ->
    {op_id, A_replica, A_counter} = A,
    {op_id, B_replica, B_counter} = B,
    case gleam@int:compare(A_counter, B_counter) of
        eq ->
            lattice_core@replica_id:compare(A_replica, B_replica);

        Other ->
            Other
    end.

-file("src/lattice_sequence/sequence.gleam", 2787).
-spec compare_moves(move(), move()) -> gleam@order:order().
compare_moves(A, B) ->
    {move, A_op_id, _, _} = A,
    {move, B_op_id, _, _} = B,
    compare_op_ids(A_op_id, B_op_id).

-file("src/lattice_sequence/sequence.gleam", 2680).
-spec compare_item_moves(item(EMV), item(EMV)) -> gleam@order:order().
compare_item_moves(A, B) ->
    case {erlang:element(7, A), erlang:element(7, B)} of
        {{some, A_move}, {some, B_move}} ->
            case compare_moves(A_move, B_move) of
                eq ->
                    compare_item_ids(erlang:element(2, A), erlang:element(2, B));

                Other ->
                    Other
            end;

        {{some, _}, none} ->
            gt;

        {none, {some, _}} ->
            lt;

        {none, none} ->
            compare_item_ids(erlang:element(2, A), erlang:element(2, B))
    end.

-file("src/lattice_sequence/sequence.gleam", 2676).
-spec has_move(item(any())) -> boolean().
has_move(Item) ->
    gleam@option:is_some(erlang:element(7, Item)).

-file("src/lattice_sequence/sequence.gleam", 2379).
-spec live_items_of(list(element(EJX))) -> list(item(EJX)).
live_items_of(Elements) ->
    gleam@list:filter_map(Elements, fun(El) ->
        case El of
            {live_el, Item} ->
                {ok, Item};

            {stable, _, _} ->
                {error, nil}
        end
    end).

-file("src/lattice_sequence/sequence.gleam", 1107).
-spec apply_moves(list(element(DYO)), gleam@dict:dict(item_id(), forwarding())) -> list(element(DYO)).
-doc(~" Re-place every moved item from a canonical base: strip all moved items
 first, then apply the moves in op order. Both merge directions therefore
 start from the same non-moved skeleton and converge, regardless of which
 side had already applied which move. Moves landing in the same gap stack
 left-to-right in op order, matching how they stack when the gap's right
 boundary still exists.").
apply_moves(Elements, Forwardings) ->
    Movers = begin
        _pipe = Elements,
        _pipe@1 = live_items_of(_pipe),
        _pipe@2 = gleam@list:filter(_pipe@1, fun has_move/1),
        gleam@list:sort(_pipe@2, fun compare_item_moves/2)
    end,
    Stripped = gleam@list:fold(Movers, Elements, fun(Current, Item) ->
        remove_element_by_id(Current, erlang:element(2, Item))
    end),
    Mover_ids = gleam@list:fold(Movers, maps:new(), fun(Acc, Item) ->
        gleam@dict:insert(Acc, erlang:element(2, Item), nil)
    end),
    {Before_gap_anchors, After_gap_anchors} = base_gap_anchors(Stripped),
    {Result, _} = gleam@list:fold(Movers, {Stripped, maps:new()}, fun(Acc, Item) ->
        {Current, Last_in_gap} = Acc,
        case erlang:element(7, Item) of
            none ->
                Acc;

            {some, {move, _, Move_left, Move_right}} ->
                case resolve_move_target(Current, Move_left, Move_right, Forwardings, Mover_ids) of
                    {before_element, Right_id} ->
                        splice_before_and_record(Current, Last_in_gap, Before_gap_anchors, Right_id, {live_el, Item});

                    at_end ->
                        {lists:append(Current, [{live_el, Item}]), Last_in_gap};

                    {after_gap, Anchor} ->
                        Gap = canonical_after_gap(Anchor, After_gap_anchors),
                        {splice_into_gap(Current, gleam_stdlib:map_get(Last_in_gap, Gap), Anchor, {live_el, Item}), gleam@dict:insert(Last_in_gap, Gap, erlang:element(2, Item))}
                end
        end
    end),
    Result.

-file("src/lattice_sequence/sequence.gleam", 2063).
-spec segments_to_elements(list(segment(EFE))) -> list(element(EFE)).
segments_to_elements(Segments) ->
    gleam@list:flat_map(Segments, fun(Segment) ->
        case Segment of
            {live, Item} ->
                [{live_el, Item}];

            {block, First_id, Values} ->
                {item_id, Rid, First_counter} = First_id,
                gleam@list:index_map(Values, fun(Value, Offset) ->
                    {stable, {item_id, Rid, First_counter + Offset}, Value}
                end)
        end
    end).

-file("src/lattice_sequence/sequence.gleam", 252).
-spec insert_many_with_delta(sequence(DTF), integer(), list(DTF)) -> {ok, {sequence(DTF), sequence(DTF)}} | {error, insert_error()}.
-doc(~" Insert several values and return both the updated sequence and the merged
 insertion delta covering every new item.

 Returns `IndexOutOfBounds` when `index` is outside `[0, length]`.

 Each new item's left origin is the previous new item (the first pins to the
 visible left neighbor) and every item shares the same right origin — the
 left neighbor's canonical successor — so the run integrates contiguously on
 every replica. When the state holds no live move record, stored order is
 already the canonical order, so the run is spliced directly in place rather
 than re-deriving the whole order; otherwise it falls back to a full rebuild.

 Apply the delta with `merge(peer_state, delta, peer_replica)`.").
insert_many_with_delta(Sequence, Index, Values) ->
    Elements = segments_to_elements(erlang:element(4, Sequence)),
    Visible = apply_moves(Elements, erlang:element(5, Sequence)),
    Size = visible_length_elements(Elements),
    case (Index < 0) orelse (Index > Size) of
        true ->
            {error, {index_out_of_bounds, Index, Size}};

        false ->
            case Values of
                [] ->
                    {ok, {Sequence, empty_delta(erlang:element(2, Sequence))}};

                _ ->
                    Origin_left = case Index of
                        0 ->
                            none;

                        _ ->
                            visible_element_id_at(Visible, Index - 1)
                    end,
                    Origin_right = canonical_successor(Elements, Origin_left),
                    {Items, Last_counter} = build_insert_run(erlang:element(2, Sequence), erlang:element(3, Sequence) + 1, Values, Origin_left, Origin_right),
                    New_elements = gleam@list:map(Items, fun(_value) ->
                        {live_el, _value}
                    end),
                    Updated_elements = splice_run_after(Elements, Origin_left, New_elements),
                    Updated = {sequence, erlang:element(2, Sequence), Last_counter, elements_to_segments(Updated_elements), erlang:element(5, Sequence), erlang:element(6, Sequence)},
                    Delta = {sequence, erlang:element(2, Sequence), Last_counter, gleam@list:map(Items, fun(_value@1) ->
                        {live, _value@1}
                    end), maps:new(), lattice_core@version_vector:new()},
                    {ok, {Updated, Delta}}
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 216).
-spec insert_with_delta(sequence(DST), integer(), DST) -> {ok, {sequence(DST), sequence(DST)}} | {error, insert_error()}.
-doc(~" Insert a value and return both the updated sequence and insertion delta.

 Returns `IndexOutOfBounds` when `index` is outside `[0, length]`.
 Apply the delta with `merge(peer_state, delta, peer_replica)`.").
insert_with_delta(Sequence, Index, Value) ->
    insert_many_with_delta(Sequence, Index, [Value]).

-file("src/lattice_sequence/sequence.gleam", 203).
-spec insert(sequence(DSO), integer(), DSO) -> {ok, sequence(DSO)} | {error, insert_error()}.
-doc(~" Insert a value at the visible item index.

 Returns `IndexOutOfBounds` when `index` is outside `[0, length]`.").
insert(Sequence, Index, Value) ->
    _pipe = insert_with_delta(Sequence, Index, Value),
    gleam@result:map(_pipe, fun(Pair) ->
        erlang:element(1, Pair)
    end).

-file("src/lattice_sequence/sequence.gleam", 230).
-spec insert_many(sequence(DSZ), integer(), list(DSZ)) -> {ok, sequence(DSZ)} | {error, insert_error()}.
-doc(~" Insert several values at consecutive visible indices starting at `index`.

 `values` are placed in order — the first at `index`, the next at
 `index + 1`, and so on — exactly as looping `insert` would, but the whole
 run is spliced in a single pass and reported as one delta. Returns
 `IndexOutOfBounds` when `index` is outside `[0, length]`.").
insert_many(Sequence, Index, Values) ->
    _pipe = insert_many_with_delta(Sequence, Index, Values),
    gleam@result:map(_pipe, fun(Pair) ->
        erlang:element(1, Pair)
    end).

-file("src/lattice_sequence/sequence.gleam", 2049).
-spec delta_sequence(lattice_core@replica_id:replica_id(), integer(), item(EFB)) -> sequence(EFB).
delta_sequence(Replica_id, Counter, Item) ->
    {sequence, Replica_id, Counter, [{live, Item}], maps:new(), lattice_core@version_vector:new()}.

-file("src/lattice_sequence/sequence.gleam", 2369).
-spec prepend_element_result(gleam@option:option({list(element(EJN)), item(EJN)}), element(EJN)) -> gleam@option:option({list(element(EJN)), item(EJN)}).
prepend_element_result(Result, El) ->
    case Result of
        {some, {Updated_rest, Item}} ->
            {some, {[El | Updated_rest], Item}};

        none ->
            none
    end.

-file("src/lattice_sequence/sequence.gleam", 2349).
-spec tombstone_of(element(EJI), gleam@option:option(item_id()), gleam@option:option(item_id()), op_id()) -> item(EJI).
tombstone_of(El, Prev, Next, Op) ->
    case El of
        {live_el, Item} ->
            {item, erlang:element(2, Item), erlang:element(3, Item), erlang:element(4, Item), erlang:element(5, Item), {some, Op}, erlang:element(7, Item)};

        {stable, Id, Value} ->
            {item, Id, Prev, Next, Value, {some, Op}, none}
    end.

-file("src/lattice_sequence/sequence.gleam", 2288).
-spec tombstone_element_by_id(list(element(EIN)), item_id(), gleam@option:option(item_id()), op_id()) -> gleam@option:option({list(element(EIN)), item(EIN)}).
tombstone_element_by_id(Elements, Id, Prev, Op) ->
    case Elements of
        [] ->
            none;

        [El | Rest] ->
            case element_id(El) =:= Id of
                true ->
                    Item = tombstone_of(El, Prev, next_element_id(Rest), Op),
                    {some, {[{live_el, Item} | Rest], Item}};

                false ->
                    _pipe = tombstone_element_by_id(Rest, Id, {some, element_id(El)}, Op),
                    prepend_element_result(_pipe, El)
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 2276).
-spec tombstone_in_base(list(element(EIE)), list(element(EIE)), integer(), op_id()) -> gleam@option:option({list(element(EIE)), item(EIE)}).
-doc(~" Walk to the visible element at `target`, replacing it with a tombstone.
 A stable block member is extracted to a live item with origins
 synthesized from its current neighbors so ordering keeps it in place.
 Tombstone the element sitting at visible index `target`, updating the
 CANONICAL base. A stable block member is extracted with its base
 neighbours as origins, not the neighbours the move overlay gave it.").
tombstone_in_base(Elements, Visible, Target, Op) ->
    case visible_element_id_at(Visible, Target) of
        none ->
            none;

        {some, Id} ->
            tombstone_element_by_id(Elements, Id, none, Op)
    end.

-file("src/lattice_sequence/sequence.gleam", 402).
-spec delete_with_delta(sequence(DUO), integer()) -> {ok, {sequence(DUO), sequence(DUO)}} | {error, delete_error()}.
-doc(~" Delete a value and return both the updated sequence and deletion delta.

 Returns `DeleteIndexOutOfBounds` when `index` is outside `[0, length)`.

 Deletes mint an op ID (bumping this replica's counter) so a compaction
 frontier can distinguish acknowledged deletes from in-flight ones.

 Apply the delta with `merge(peer_state, delta, peer_replica)`.").
delete_with_delta(Sequence, Index) ->
    Elements = segments_to_elements(erlang:element(4, Sequence)),
    Visible = apply_moves(Elements, erlang:element(5, Sequence)),
    Size = visible_length_elements(Elements),
    case (Index < 0) orelse (Index >= Size) of
        true ->
            {error, {delete_index_out_of_bounds, Index, Size}};

        false ->
            Next_counter = erlang:element(3, Sequence) + 1,
            Op = {op_id, erlang:element(2, Sequence), Next_counter},
            case tombstone_in_base(Elements, Visible, Index, Op) of
                {some, {Updated_elements, Deleted_item}} ->
                    Updated = {sequence, erlang:element(2, Sequence), Next_counter, elements_to_segments(Updated_elements), erlang:element(5, Sequence), erlang:element(6, Sequence)},
                    Delta = delta_sequence(erlang:element(2, Sequence), Next_counter, Deleted_item),
                    {ok, {Updated, Delta}};

                none ->
                    {error, {delete_index_out_of_bounds, Index, Size}}
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 386).
-spec delete(sequence(DUJ), integer()) -> {ok, sequence(DUJ)} | {error, delete_error()}.
-doc(~" Delete the value at the visible item index.

 Returns `DeleteIndexOutOfBounds` when `index` is outside `[0, length)`.").
delete(Sequence, Index) ->
    _pipe = delete_with_delta(Sequence, Index),
    gleam@result:map(_pipe, fun(Pair) ->
        erlang:element(1, Pair)
    end).

-file("src/lattice_sequence/sequence.gleam", 2245).
-spec swap_in_item(list(element(EHT)), item(EHT)) -> list(element(EHT)).
swap_in_item(Elements, Item) ->
    case Elements of
        [] ->
            [{live_el, Item}];

        [El | Rest] ->
            case element_id(El) =:= erlang:element(2, Item) of
                true ->
                    [{live_el, Item} | Rest];

                false ->
                    [El | swap_in_item(Rest, Item)]
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 2655).
-spec insert_element_at(list(element(EML)), integer(), element(EML), list(element(EML))) -> list(element(EML)).
insert_element_at(Elements, Index, El, Prefix_reversed) ->
    case Index =< 0 of
        true ->
            gleam@list:fold(Prefix_reversed, [El | Elements], fun(Tail, First) ->
                [First | Tail]
            end);

        false ->
            case Elements of
                [] ->
                    gleam@list:fold(Prefix_reversed, [El], fun(Tail, First) ->
                        [First | Tail]
                    end);

                [First | Rest] ->
                    insert_element_at(Rest, Index - 1, El, [First | Prefix_reversed])
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 2628).
-spec replica_of(item_id()) -> lattice_core@replica_id:replica_id().
replica_of(Id) ->
    {item_id, Rid, _} = Id,
    Rid.

-file("src/lattice_sequence/sequence.gleam", 2594).
-spec scan_step(scan_entry(), gleam@option:option(item_id()), gleam@option:option(item_id()), lattice_core@replica_id:replica_id(), gleam@dict:dict(item_id(), nil), gleam@dict:dict(item_id(), nil)) -> scan_step().
scan_step(Entry, Item_left, Item_right, Item_replica, Before_origin, Conflicting) ->
    case erlang:element(3, Entry) =:= Item_left of
        true ->
            case lattice_core@replica_id:compare(replica_of(erlang:element(2, Entry)), Item_replica) of
                lt ->
                    take_as_left;

                eq ->
                    case erlang:element(4, Entry) =:= Item_right of
                        true ->
                            stop_scan;

                        false ->
                            advance_past
                    end;

                gt ->
                    case erlang:element(4, Entry) =:= Item_right of
                        true ->
                            stop_scan;

                        false ->
                            advance_past
                    end
            end;

        false ->
            case erlang:element(3, Entry) of
                none ->
                    stop_scan;

                {some, Entry_left} ->
                    case {gleam@dict:has_key(Before_origin, Entry_left), gleam@dict:has_key(Conflicting, Entry_left)} of
                        {true, false} ->
                            take_as_left;

                        {true, true} ->
                            advance_past;

                        {false, _} ->
                            stop_scan
                    end
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 2528).
-spec yata_scan(list(scan_entry()), gleam@option:option(item_id()), gleam@option:option(item_id()), lattice_core@replica_id:replica_id(), integer(), integer(), gleam@dict:dict(item_id(), nil), gleam@dict:dict(item_id(), nil)) -> integer().
yata_scan(Window, Item_left, Item_right, Item_replica, Position, Dest, Before_origin, Conflicting) ->
    case Window of
        [] ->
            Dest;

        [Entry | Rest] ->
            case erlang:element(5, Entry) of
                true ->
                    Dest;

                false ->
                    Before_origin@1 = gleam@dict:insert(Before_origin, erlang:element(2, Entry), nil),
                    Conflicting@1 = gleam@dict:insert(Conflicting, erlang:element(2, Entry), nil),
                    case scan_step(Entry, Item_left, Item_right, Item_replica, Before_origin@1, Conflicting@1) of
                        stop_scan ->
                            Dest;

                        take_as_left ->
                            yata_scan(Rest, Item_left, Item_right, Item_replica, Position + 1, Position + 1, Before_origin@1, maps:new());

                        advance_past ->
                            yata_scan(Rest, Item_left, Item_right, Item_replica, Position + 1, Dest, Before_origin@1, Conflicting@1)
                    end
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 2494).
-spec scan_entry(element(any()), gleam@dict:dict(item_id(), forwarding()), integer()) -> scan_entry().
scan_entry(El, Forwardings, Fuel) ->
    case El of
        {stable, Id, _} ->
            {scan_entry, Id, none, none, true};

        {live_el, Other} ->
            {scan_entry, erlang:element(2, Other), chase_left(erlang:element(3, Other), Forwardings, Fuel), erlang:element(4, Other), false}
    end.

-file("src/lattice_sequence/sequence.gleam", 2640).
-spec index_of_element_loop(list(element(any())), item_id(), integer()) -> {ok, integer()} | {error, nil}.
index_of_element_loop(Elements, Id, Current) ->
    case Elements of
        [] ->
            {error, nil};

        [El | Rest] ->
            case element_id(El) =:= Id of
                true ->
                    {ok, Current};

                false ->
                    index_of_element_loop(Rest, Id, Current + 1)
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 2633).
-spec index_of_element(list(element(any())), item_id()) -> {ok, integer()} | {error, nil}.
index_of_element(Elements, Id) ->
    index_of_element_loop(Elements, Id, 0).

-file("src/lattice_sequence/sequence.gleam", 2514).
-spec resolve_origin(gleam@option:option(item_id()), list(element(any()))) -> gleam@option:option(item_id()).
-doc(~" Degrade origins that reference IDs this state has never seen (or whose
 forwardings expired) to the document boundary, mirroring how unmerged
 origins have always been treated.").
resolve_origin(Origin, Elements) ->
    case Origin of
        none ->
            none;

        {some, Id} ->
            case contains_element_id(Elements, Id) of
                true ->
                    {some, Id};

                false ->
                    none
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 2428).
-spec integrate_element(list(element(EKX)), item(EKX), gleam@dict:dict(item_id(), forwarding())) -> list(element(EKX)).
-doc(~" Place a new item into the element order using its origins.

 Follows the YATA/Yjs `integrate` algorithm: the item lands between its
 left and right origins, and the scan over the conflict window decides its
 position among concurrently inserted items. For causally valid ops the
 window never contains a stable (origin-stripped) element — those were
 visible when the op was created, so they cannot sit strictly between its
 visible-adjacent origins; a stale op that does hit one degrades by
 stopping the scan there.").
integrate_element(Elements, Item, Forwardings) ->
    Fuel = maps:size(Forwardings) + 1,
    Item_left = chase_left(erlang:element(3, Item), Forwardings, Fuel),
    Item_right = erlang:element(4, Item),
    Left = resolve_origin(Item_left, Elements),
    Right = resolve_origin(chase_right(erlang:element(4, Item), Forwardings, Fuel), Elements),
    Left_pos = case Left of
        none ->
            -1;

        {some, Id} ->
            case index_of_element(Elements, Id) of
                {ok, Pos} ->
                    Pos;

                {error, nil} ->
                    -1
            end
    end,
    Total = erlang:length(Elements),
    Right_pos = case Right of
        none ->
            Total;

        {some, Id@1} ->
            case index_of_element(Elements, Id@1) of
                {ok, Pos@1} ->
                    Pos@1;

                {error, nil} ->
                    Total
            end
    end,
    Window = begin
        _pipe = Elements,
        _pipe@1 = gleam@list:drop(_pipe, Left_pos + 1),
        _pipe@2 = gleam@list:take(_pipe@1, (Right_pos - Left_pos) - 1),
        gleam@list:map(_pipe@2, fun(_capture) ->
            scan_entry(_capture, Forwardings, Fuel)
        end)
    end,
    Offset = yata_scan(Window, Item_left, Item_right, replica_of(erlang:element(2, Item)), 0, 0, maps:new(), maps:new()),
    insert_element_at(Elements, (Left_pos + 1) + Offset, {live_el, Item}, []).

-file("src/lattice_sequence/sequence.gleam", 1349).
-spec compare_lamport(item(EBE), item(EBE)) -> gleam@order:order().
compare_lamport(X, Y) ->
    {item_id, X_rid, X_counter} = erlang:element(2, X),
    {item_id, Y_rid, Y_counter} = erlang:element(2, Y),
    case gleam@int:compare(X_counter, Y_counter) of
        eq ->
            lattice_core@replica_id:compare(X_rid, Y_rid);

        Other ->
            Other
    end.

-file("src/lattice_sequence/sequence.gleam", 2803).
-spec frontier_covers(lattice_core@version_vector:version_vector(), item_id()) -> boolean().
frontier_covers(Frontier, Id) ->
    {item_id, Rid, Counter} = Id,
    lattice_core@version_vector:get(Frontier, Rid) >= Counter.

-file("src/lattice_sequence/sequence.gleam", 1032).
-spec rebuild_base(list(element(DYE)), gleam@dict:dict(item_id(), forwarding()), lattice_core@version_vector:version_vector()) -> list(element(DYE)).
-doc(~" The canonical pre-move order: pinned covered elements in list order with
 everything else integrated in Lamport order.

 A covered element that carries a still-volatile move record is NOT
 pinned: its stored position reflects whichever moves this replica has
 already applied, which differs between replicas. It always carries its
 origins, so it re-integrates at its settled base position instead (its
 Lamport position sorts it before every volatile item automatically); the
 move overlay then re-places it.").
rebuild_base(Elements, Forwardings, Frontier) ->
    Pinned = gleam@list:filter(Elements, fun(El) ->
        case El of
            {stable, _, _} ->
                true;

            {live_el, Item} ->
                frontier_covers(Frontier, erlang:element(2, Item))
        end
    end),
    _pipe = Elements,
    _pipe@1 = live_items_of(_pipe),
    _pipe@2 = gleam@list:filter(_pipe@1, fun(Item) ->
        not frontier_covers(Frontier, erlang:element(2, Item))
    end),
    _pipe@3 = gleam@list:sort(_pipe@2, fun compare_lamport/2),
    gleam@list:fold(_pipe@3, Pinned, fun(Current, Item) ->
        integrate_element(Current, Item, Forwardings)
    end).

-file("src/lattice_sequence/sequence.gleam", 1005).
-spec rebuild(list(element(DXT)), gleam@dict:dict(item_id(), forwarding()), lattice_core@version_vector:version_vector()) -> list(element(DXT)).
-doc(~" Deterministically rebuild the element order.

 Everything at or below the frontier — stable elements and old live items
 alike — is pinned at its stored position: those positions converged on
 every replica before the frontier passed them, so the pinned skeleton is
 identical everywhere. Items above the frontier are integrated YATA-style
 one at a time in Lamport order (a canonical total order), which makes
 the result a pure function of the element set; finally moves are applied
 last-writer-wins. Every construction path (local edits and both merge
 directions) goes through this, so convergence holds by construction.

 Because ops record canonical-adjacent origins, a volatile item's
 conflict window can only ever contain other volatile items — never a
 pinned element — so integration never needs the origins compaction
 stripped.").
rebuild(Elements, Forwardings, Frontier) ->
    rebuild_base(Elements, Forwardings, Frontier).

-file("src/lattice_sequence/sequence.gleam", 2322).
-spec element_as_item_by_id(list(element(EJC)), item_id(), gleam@option:option(item_id())) -> gleam@option:option(item(EJC)).
element_as_item_by_id(Elements, Id, Prev) ->
    case Elements of
        [] ->
            none;

        [El | Rest] ->
            case element_id(El) =:= Id of
                true ->
                    case El of
                        {live_el, Item} ->
                            {some, Item};

                        {stable, Stable_id, Value} ->
                            {some, {item, Stable_id, Prev, next_element_id(Rest), Value, none, none}}
                    end;

                false ->
                    element_as_item_by_id(Rest, Id, {some, element_id(El)})
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 2311).
-spec base_item_at_visible_index(list(element(EIV)), list(element(EIV)), integer()) -> gleam@option:option(item(EIV)).
-doc(~" The item at visible index `target`, read out of the CANONICAL base so a
 stable block member gets its base neighbours as origins.").
base_item_at_visible_index(Elements, Visible, Target) ->
    case visible_element_id_at(Visible, Target) of
        none ->
            none;

        {some, Id} ->
            element_as_item_by_id(Elements, Id, none)
    end.

-file("src/lattice_sequence/sequence.gleam", 479).
-spec move_visible_element(sequence(DVF), list(element(DVF)), list(element(DVF)), integer(), integer()) -> {ok, {sequence(DVF), sequence(DVF)}} | {error, move_error()}.
move_visible_element(Sequence, Elements, Visible, From_index, To_index) ->
    case base_item_at_visible_index(Elements, Visible, From_index) of
        none ->
            {error, {move_from_index_out_of_bounds, From_index, visible_length_elements(Elements)}};

        {some, Item} ->
            Remaining = gleam@list:filter(Visible, fun(El) ->
                element_id(El) /= erlang:element(2, Item)
            end),
            Origin_left = case To_index of
                0 ->
                    none;

                _ ->
                    visible_element_id_at(Remaining, To_index - 1)
            end,
            Origin_right = visible_element_id_at(Remaining, To_index),
            Next_counter = erlang:element(3, Sequence) + 1,
            Moved_item = {item, erlang:element(2, Item), erlang:element(3, Item), erlang:element(4, Item), erlang:element(5, Item), erlang:element(6, Item), {some, {move, {op_id, erlang:element(2, Sequence), Next_counter}, Origin_left, Origin_right}}},
            Updated_elements = rebuild(swap_in_item(Elements, Moved_item), erlang:element(5, Sequence), erlang:element(6, Sequence)),
            Updated = {sequence, erlang:element(2, Sequence), Next_counter, elements_to_segments(Updated_elements), erlang:element(5, Sequence), erlang:element(6, Sequence)},
            Delta = delta_sequence(erlang:element(2, Sequence), Next_counter, Moved_item),
            {ok, {Updated, Delta}}
    end.

-file("src/lattice_sequence/sequence.gleam", 454).
-spec move_with_delta(sequence(DUZ), integer(), integer()) -> {ok, {sequence(DUZ), sequence(DUZ)}} | {error, move_error()}.
-doc(~" Move a visible item and return both the updated sequence and move delta.

 The `to_index` is interpreted after removing the item from `from_index`.

 Returns a `MoveError` when either index is out of bounds.
 Apply the delta with `merge(peer_state, delta, peer_replica)`.").
move_with_delta(Sequence, From_index, To_index) ->
    Elements = segments_to_elements(erlang:element(4, Sequence)),
    Visible = apply_moves(Elements, erlang:element(5, Sequence)),
    Size = visible_length_elements(Elements),
    Length_after_removal = Size - 1,
    case {(From_index < 0) orelse (From_index >= Size), (To_index < 0) orelse (To_index > Length_after_removal)} of
        {true, _} ->
            {error, {move_from_index_out_of_bounds, From_index, Size}};

        {_, true} ->
            {error, {move_to_index_out_of_bounds, To_index, Length_after_removal}};

        {false, false} ->
            move_visible_element(Sequence, Elements, Visible, From_index, To_index)
    end.

-file("src/lattice_sequence/sequence.gleam", 439).
-spec move(sequence(DUU), integer(), integer()) -> {ok, sequence(DUU)} | {error, move_error()}.
-doc(~" Move a visible item to another visible index.

 The `to_index` is interpreted after removing the item from `from_index`.

 Returns a `MoveError` when either index is out of bounds.").
move(Sequence, From_index, To_index) ->
    _pipe = move_with_delta(Sequence, From_index, To_index),
    gleam@result:map(_pipe, fun(Pair) ->
        erlang:element(1, Pair)
    end).

-file("src/lattice_sequence/sequence.gleam", 533).
-spec start_anchor() -> anchor().
-doc(~" Create an anchor at the start of the sequence. Always resolves to 0.").
start_anchor() ->
    start.

-file("src/lattice_sequence/sequence.gleam", 539).
-spec end_anchor() -> anchor().
-doc(~" Create an anchor at the end of the sequence. Always resolves to the
 current visible length, tracking growth.").
end_anchor() ->
    'end'.

-file("src/lattice_sequence/sequence.gleam", 1019).
-spec visible_elements(sequence(DYA)) -> list(element(DYA)).
-doc(~" The user-facing element order: the stored base with every move overlaid.

 Moves are an overlay, not part of the stored order, so every read that
 depends on position — values, index lookups, anchors — goes through here.
 Writes go the other way: they compute origins from this view and then
 update the base.").
visible_elements(Sequence) ->
    apply_moves(segments_to_elements(erlang:element(4, Sequence)), erlang:element(5, Sequence)).

-file("src/lattice_sequence/sequence.gleam", 550).
-spec anchor_at(sequence(any()), integer(), bias()) -> {ok, anchor()} | {error, anchor_error()}.
-doc(~" Create an anchor at the gap before the visible item at `index`.

 `Before` bias binds the anchor to the item at `index`; `After` bias binds
 it to the item at `index - 1`. Boundary positions with no item on the
 chosen side degrade to the start / end sentinels.

 Valid positions are `0 <= index <= length`.").
anchor_at(Sequence, Index, Bias) ->
    Elements = visible_elements(Sequence),
    Size = visible_length_elements(Elements),
    case (Index < 0) orelse (Index > Size) of
        true ->
            {error, {anchor_index_out_of_bounds, Index, Size}};

        false ->
            case Bias of
                before ->
                    case visible_element_id_at(Elements, Index) of
                        {some, Id} ->
                            {ok, {at_item, Id, before}};

                        none ->
                            {ok, 'end'}
                    end;

                'after' ->
                    case visible_element_id_at(Elements, Index - 1) of
                        {some, Id@1} ->
                            {ok, {at_item, Id@1, 'after'}};

                        none ->
                            {ok, start}
                    end
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 611).
-spec resolve_element_anchor(list(element(any())), item_id(), bias(), integer()) -> {ok, integer()} | {error, nil}.
resolve_element_anchor(Elements, Id, Bias, Visible_before) ->
    case Elements of
        [] ->
            {error, nil};

        [El | Rest] ->
            case element_id(El) =:= Id of
                true ->
                    case {Bias, element_is_visible(El)} of
                        {'after', true} ->
                            {ok, Visible_before + 1};

                        {_, _} ->
                            {ok, Visible_before}
                    end;

                false ->
                    case element_is_visible(El) of
                        true ->
                            resolve_element_anchor(Rest, Id, Bias, Visible_before + 1);

                        false ->
                            resolve_element_anchor(Rest, Id, Bias, Visible_before)
                    end
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 635).
-spec resolve_forwarded_gap(list(element(any())), gleam@option:option(item_id())) -> {ok, integer()} | {error, anchor_error()}.
resolve_forwarded_gap(Elements, Left) ->
    case Left of
        none ->
            {ok, 0};

        {some, Left_id} ->
            case resolve_element_anchor(Elements, Left_id, 'after', 0) of
                {ok, Index} ->
                    {ok, Index};

                {error, nil} ->
                    {error, unknown_anchor_target}
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 589).
-spec resolve(sequence(any()), anchor()) -> {ok, integer()} | {error, anchor_error()}.
-doc(~" Resolve an anchor to a current visible index in `[0, length]`.

 Anchors on deleted items still resolve: both biases collapse to the gap
 where the item used to be. Anchors follow moved items.

 Anchors to compacted items resolve through the forwarding map to the gap
 the item left behind — semantically the same as tombstone collapse.

 Returns `Error(UnknownAnchorTarget)` when the anchor references an item
 this replica has never seen (created remotely and not yet merged), or one
 that was compacted away and whose forwarding entry has since been removed
 by the host's retention policy. Either way the anchor is unusable and the
 holder should re-anchor.").
resolve(Sequence, Anchor) ->
    Elements = visible_elements(Sequence),
    case Anchor of
        start ->
            {ok, 0};

        'end' ->
            {ok, visible_length_elements(Elements)};

        {at_item, Id, Bias} ->
            case resolve_element_anchor(Elements, Id, Bias, 0) of
                {ok, Index} ->
                    {ok, Index};

                {error, nil} ->
                    case gleam_stdlib:map_get(erlang:element(5, Sequence), Id) of
                        {ok, {forwarding, Left, _}} ->
                            resolve_forwarded_gap(Elements, Left);

                        {error, nil} ->
                            {error, unknown_anchor_target}
                    end
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 718).
-spec encode_bias(bias()) -> gleam@json:json().
encode_bias(Bias) ->
    case Bias of
        before ->
            gleam@json:string(~"before");

        'after' ->
            gleam@json:string(~"after")
    end.

-file("src/lattice_sequence/sequence.gleam", 2024).
-spec encode_item_id(item_id()) -> gleam@json:json().
encode_item_id(Id) ->
    {item_id, Rid, Counter} = Id,
    gleam@json:object([{~"replica_id", gleam@json:string(lattice_core@replica_id:to_string(Rid))}, {~"counter", gleam@json:int(Counter)}]).

-file("src/lattice_sequence/sequence.gleam", 653).
-spec anchor_to_json(anchor()) -> gleam@json:json().
-doc(~" Encode an anchor as a self-describing JSON value.

 Produces an envelope with `type`, `v` (schema version), and `anchor`, so
 anchors can travel between replicas (e.g. shared cursors).").
anchor_to_json(Anchor) ->
    Encoded = case Anchor of
        start ->
            gleam@json:object([{~"kind", gleam@json:string(~"start")}]);

        'end' ->
            gleam@json:object([{~"kind", gleam@json:string(~"end")}]);

        {at_item, Id, Bias} ->
            gleam@json:object([{~"kind", gleam@json:string(~"item")}, {~"id", encode_item_id(Id)}, {~"bias", encode_bias(Bias)}])
    end,
    gleam@json:object([{~"type", gleam@json:string(~"anchor")}, {~"v", gleam@json:int(1)}, {~"anchor", Encoded}]).

-file("src/lattice_sequence/sequence.gleam", 725).
-spec bias_decoder() -> gleam@dynamic@decode:decoder(bias()).
bias_decoder() ->
    _pipe = {decoder, fun gleam@dynamic@decode:decode_string/1},
    gleam@dynamic@decode:then(_pipe, fun(Value) ->
        case Value of
            ~"before" ->
                gleam@dynamic@decode:success(before);

            ~"after" ->
                gleam@dynamic@decode:success('after');

            _ ->
                gleam@dynamic@decode:failure(before, ~"before or after")
        end
    end).

-file("src/lattice_sequence/sequence.gleam", 1973).
-spec non_negative_int_decoder() -> gleam@dynamic@decode:decoder(integer()).
non_negative_int_decoder() ->
    _pipe = {decoder, fun gleam@dynamic@decode:decode_int/1},
    gleam@dynamic@decode:then(_pipe, fun(Val) ->
        case Val >= 0 of
            true ->
                gleam@dynamic@decode:success(Val);

            false ->
                gleam@dynamic@decode:failure(Val, ~"a non-negative integer")
        end
    end).

-file("src/lattice_sequence/sequence.gleam", 1983).
-spec item_id_decoder() -> gleam@dynamic@decode:decoder(item_id()).
item_id_decoder() ->
    gleam@dynamic@decode:field(~"replica_id", lattice_core@replica_id:decoder(), fun(Rid) ->
        gleam@dynamic@decode:field(~"counter", non_negative_int_decoder(), fun(Counter) ->
            gleam@dynamic@decode:success({item_id, Rid, Counter})
        end)
    end).

-file("src/lattice_sequence/sequence.gleam", 673).
-spec anchor_from_json(binary()) -> {ok, anchor()} | {error, gleam@json:decode_error()}.
-doc(~" Decode an anchor from a JSON string produced by `anchor_to_json`.").
anchor_from_json(Json_string) ->
    Anchor_decoder = begin
        gleam@dynamic@decode:field(~"kind", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(Kind) ->
            case Kind of
                ~"start" ->
                    gleam@dynamic@decode:success(start);

                ~"end" ->
                    gleam@dynamic@decode:success('end');

                ~"item" ->
                    gleam@dynamic@decode:field(~"id", item_id_decoder(), fun(Id) ->
                        gleam@dynamic@decode:field(~"bias", bias_decoder(), fun(Bias) ->
                            gleam@dynamic@decode:success({at_item, Id, Bias})
                        end)
                    end);

                _ ->
                    gleam@dynamic@decode:failure(start, ~"one of start, end, item")
            end
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
            case (Type_tag =:= ~"anchor") andalso (Version =:= 1) of
                true ->
                    gleam@json:parse(Json_string, begin
                        gleam@dynamic@decode:field(~"anchor", Anchor_decoder, fun(Anchor) ->
                            gleam@dynamic@decode:success(Anchor)
                        end)
                    end);

                false ->
                    {error, {unable_to_decode, [{decode_error, ~"type=anchor and v=1", <<<<Type_tag/binary, " v="/utf8>>/binary, (erlang:integer_to_binary(Version))/binary>>, []}]}}
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 737).
-spec values(sequence(DWL)) -> list(DWL).
-doc(~" Return all visible values in sequence order.").
values(Sequence) ->
    _pipe = visible_elements(Sequence),
    gleam@list:filter_map(_pipe, fun(El) ->
        case El of
            {stable, _, Value} ->
                {ok, Value};

            {live_el, Item} ->
                case erlang:element(6, Item) of
                    none ->
                        {ok, erlang:element(5, Item)};

                    {some, _} ->
                        {error, nil}
                end
        end
    end).

-file("src/lattice_sequence/sequence.gleam", 781).
-spec bind(sequence(DWQ), lattice_core@replica_id:replica_id()) -> sequence(DWQ).
-doc(~" Select the identity for subsequent edits without rebuilding the sequence.

 Preserves item IDs, counters, stored order, and compaction metadata.
 Independent writers must use distinct replica IDs.

 ## Examples

 ```gleam
 let local = replica_id.new(\"B\")
 sequence.new(replica_id.new(\"A\"))
 |> sequence.bind(local)
 |> sequence.replica_id()
 // -> local
 ```").
bind(Sequence, Replica) ->
    {sequence, Replica, erlang:element(3, Sequence), erlang:element(4, Sequence), erlang:element(5, Sequence), erlang:element(6, Sequence)}.

-file("src/lattice_sequence/sequence.gleam", 786).
-spec length(sequence(any())) -> integer().
-doc(~" Return the count of visible values.").
length(Sequence) ->
    _pipe = erlang:element(4, Sequence),
    gleam@list:fold(_pipe, 0, fun(Count, Segment) ->
        case Segment of
            {block, _, Values} ->
                Count + erlang:length(Values);

            {live, Item} ->
                case erlang:element(6, Item) of
                    none ->
                        Count + 1;

                    {some, _} ->
                        Count
                end
        end
    end).

-file("src/lattice_sequence/sequence.gleam", 804).
-spec frontier(sequence(any())) -> lattice_core@version_vector:version_vector().
-doc(~" The stability frontier this sequence was last compacted at.

 Empty until the first `compact` call. Carried in the state so merging can
 tell which side is compacted further.").
frontier(Sequence) ->
    erlang:element(6, Sequence).

-file("src/lattice_sequence/sequence.gleam", 809).
-spec forwarding_size(forwarding_map()) -> integer().
-doc(~" The number of entries in a forwarding map.").
forwarding_size(Map) ->
    {forwarding_map, Entries} = Map,
    maps:size(Entries).

-file("src/lattice_sequence/sequence.gleam", 821).
-spec remove_forwardings(sequence(DWX), forwarding_map()) -> sequence(DWX).
-doc(~" Remove previously emitted forwarding entries from the sequence.

 Forwardings are bounded by the host's retention policy: keep the map
 returned by each `compact` round and expire old rounds by passing them
 here. Anchors and deltas referencing removed entries hard-fail
 (`UnknownAnchorTarget` / `UnknownOriginTarget`) and must re-anchor or
 resync.").
remove_forwardings(Sequence, Map) ->
    {forwarding_map, Entries} = Map,
    Remaining = gleam@dict:fold(Entries, erlang:element(5, Sequence), fun(Acc, Id, _) ->
        gleam@dict:delete(Acc, Id)
    end),
    {sequence, erlang:element(2, Sequence), erlang:element(3, Sequence), erlang:element(4, Sequence), Remaining, erlang:element(6, Sequence)}.

-file("src/lattice_sequence/sequence.gleam", 2773).
-spec merge_move(gleam@option:option(move()), gleam@option:option(move())) -> gleam@option:option(move()).
merge_move(A, B) ->
    case {A, B} of
        {none, none} ->
            none;

        {{some, Move}, none} ->
            {some, Move};

        {none, {some, Move@1}} ->
            {some, Move@1};

        {{some, A_move}, {some, B_move}} ->
            case compare_moves(A_move, B_move) of
                lt ->
                    {some, B_move};

                eq ->
                    {some, A_move};

                gt ->
                    {some, A_move}
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 2760).
-spec merge_deleted(gleam@option:option(op_id()), gleam@option:option(op_id())) -> gleam@option:option(op_id()).
merge_deleted(A, B) ->
    case {A, B} of
        {none, none} ->
            none;

        {{some, Op}, none} ->
            {some, Op};

        {none, {some, Op@1}} ->
            {some, Op@1};

        {{some, A_op}, {some, B_op}} ->
            case compare_op_ids(A_op, B_op) of
                gt ->
                    {some, B_op};

                lt ->
                    {some, A_op};

                eq ->
                    {some, A_op}
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 2751).
-spec compare_optional_id(gleam@option:option(item_id()), gleam@option:option(item_id())) -> gleam@order:order().
compare_optional_id(A, B) ->
    case {A, B} of
        {none, none} ->
            eq;

        {none, {some, _}} ->
            lt;

        {{some, _}, none} ->
            gt;

        {{some, A_id}, {some, B_id}} ->
            compare_item_ids(A_id, B_id)
    end.

-file("src/lattice_sequence/sequence.gleam", 2739).
-spec compare_origin_pair({gleam@option:option(item_id()), gleam@option:option(item_id())}, {gleam@option:option(item_id()), gleam@option:option(item_id())}) -> gleam@order:order().
compare_origin_pair(A, B) ->
    {A_left, A_right} = A,
    {B_left, B_right} = B,
    case compare_optional_id(A_left, B_left) of
        eq ->
            compare_optional_id(A_right, B_right);

        Other ->
            Other
    end.

-file("src/lattice_sequence/sequence.gleam", 2723).
-spec pick_origins(item(ENC), item(ENC)) -> {gleam@option:option(item_id()), gleam@option:option(item_id())}.
-doc(~" Origins are immutable in normal operation, but extracting a block member
 (for a volatile delete or move) synthesizes origins from local neighbors,
 so two replicas can disagree. Pick deterministically so merge commutes.").
pick_origins(A, B) ->
    gleam@bool:guard((erlang:element(3, A) =:= erlang:element(3, B)) andalso (erlang:element(4, A) =:= erlang:element(4, B)), {erlang:element(3, A), erlang:element(4, A)}, fun() ->
        case compare_origin_pair({erlang:element(3, A), erlang:element(4, A)}, {erlang:element(3, B), erlang:element(4, B)}) of
            gt ->
                {erlang:element(3, B), erlang:element(4, B)};

            lt ->
                {erlang:element(3, A), erlang:element(4, A)};

            eq ->
                {erlang:element(3, A), erlang:element(4, A)}
        end
    end).

-file("src/lattice_sequence/sequence.gleam", 2707).
-spec merge_item(item(EMY), item(EMY)) -> item(EMY).
merge_item(A, B) ->
    {Origin_left, Origin_right} = pick_origins(A, B),
    {item, erlang:element(2, A), Origin_left, Origin_right, erlang:element(5, A), merge_deleted(erlang:element(6, A), erlang:element(6, B)), merge_move(erlang:element(7, A), erlang:element(7, B))}.

-file("src/lattice_sequence/sequence.gleam", 983).
-spec stable_or_live(item(DXQ), lattice_core@version_vector:version_vector()) -> element(DXQ).
-doc(~" One side has the element compacted into a block, the other still holds a
 live item for it. A tombstone or a move keeps the item live and supersedes
 the block slot; only a plain copy collapses to the stable representation.
 The rule looks only at the live item, so both merge directions agree.

 A moved item is never collapsed into the block skeleton, even if the merged
 frontier covers its move op: `compact` refuses to stabilize any state that
 holds a move (see `compact`), so a covered-move block slot cannot legitimately
 arise, and baking one here would strip the origins a peer's concurrent
 above-frontier inserts integrate against and break merge commutativity.").
stable_or_live(Item, _) ->
    case {erlang:element(6, Item), erlang:element(7, Item)} of
        {none, none} ->
            {stable, erlang:element(2, Item), erlang:element(5, Item)};

        {_, _} ->
            {live_el, Item}
    end.

-file("src/lattice_sequence/sequence.gleam", 949).
-spec reconcile_element(element(DXI), gleam@dict:dict(item_id(), item(DXI)), gleam@dict:dict(item_id(), nil), lattice_core@version_vector:version_vector()) -> element(DXI).
reconcile_element(El, B_lives, B_stables, Frontier) ->
    case El of
        {live_el, Item} ->
            case gleam_stdlib:map_get(B_lives, erlang:element(2, Item)) of
                {ok, Other} ->
                    {live_el, merge_item(Item, Other)};

                {error, nil} ->
                    case gleam@dict:has_key(B_stables, erlang:element(2, Item)) of
                        true ->
                            stable_or_live(Item, Frontier);

                        false ->
                            El
                    end
            end;

        {stable, Id, _} ->
            case gleam_stdlib:map_get(B_lives, Id) of
                {ok, Other@1} ->
                    stable_or_live(Other@1, Frontier);

                {error, nil} ->
                    El
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 2146).
-spec is_stable_element(element(any())) -> boolean().
is_stable_element(El) ->
    case El of
        {stable, _, _} ->
            true;

        {live_el, _} ->
            false
    end.

-file("src/lattice_sequence/sequence.gleam", 2398).
-spec element_id_dict(list(element(any()))) -> gleam@dict:dict(item_id(), nil).
element_id_dict(Elements) ->
    gleam@list:fold(Elements, maps:new(), fun(Acc, El) ->
        gleam@dict:insert(Acc, element_id(El), nil)
    end).

-file("src/lattice_sequence/sequence.gleam", 2394).
-spec stable_elements_of(list(element(EKI))) -> list(element(EKI)).
stable_elements_of(Elements) ->
    gleam@list:filter(Elements, fun is_stable_element/1).

-file("src/lattice_sequence/sequence.gleam", 2404).
-spec stable_id_dict(list(element(any()))) -> gleam@dict:dict(item_id(), nil).
stable_id_dict(Elements) ->
    _pipe = Elements,
    _pipe@1 = stable_elements_of(_pipe),
    element_id_dict(_pipe@1).

-file("src/lattice_sequence/sequence.gleam", 2388).
-spec live_item_dict(list(element(EKC))) -> gleam@dict:dict(item_id(), item(EKC)).
live_item_dict(Elements) ->
    _pipe = Elements,
    _pipe@1 = live_items_of(_pipe),
    gleam@list:fold(_pipe@1, maps:new(), fun(Acc, Item) ->
        gleam@dict:insert(Acc, erlang:element(2, Item), Item)
    end).

-file("src/lattice_sequence/sequence.gleam", 1060).
-spec canonical_clocks(lattice_core@version_vector:version_vector()) -> list({lattice_core@replica_id:replica_id(), integer()}).
canonical_clocks(Vector) ->
    _pipe = lattice_core@version_vector:to_dict(Vector),
    _pipe@1 = maps:to_list(_pipe),
    gleam@list:sort(_pipe@1, fun(X, Y) ->
        lattice_core@replica_id:compare(erlang:element(1, X), erlang:element(1, Y))
    end).

-file("src/lattice_sequence/sequence.gleam", 1066).
-spec compare_clock_lists(list({lattice_core@replica_id:replica_id(), integer()}), list({lattice_core@replica_id:replica_id(), integer()})) -> gleam@order:order().
compare_clock_lists(A, B) ->
    case {A, B} of
        {[], []} ->
            eq;

        {[], _} ->
            lt;

        {_, []} ->
            gt;

        {[{Ra, Ca} | Ta], [{Rb, Cb} | Tb]} ->
            case lattice_core@replica_id:compare(Ra, Rb) of
                eq ->
                    case gleam@int:compare(Ca, Cb) of
                        eq ->
                            compare_clock_lists(Ta, Tb);

                        Other ->
                            Other
                    end;

                Other@1 ->
                    Other@1
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 1056).
-spec frontier_tiebreak(lattice_core@version_vector:version_vector(), lattice_core@version_vector:version_vector()) -> gleam@order:order().
-doc(~" A deterministic, direction-independent order on version vectors, used
 only to pick a covered-order source when merging states compacted at
 concurrent frontiers (which a sequencer host never produces).").
frontier_tiebreak(A, B) ->
    compare_clock_lists(canonical_clocks(A), canonical_clocks(B)).

-file("src/lattice_sequence/sequence.gleam", 2840).
-spec normalize_forwardings(gleam@dict:dict(item_id(), forwarding())) -> gleam@dict:dict(item_id(), forwarding()).
-doc(~" Collapse forwarding chains: a target that was itself dropped in a later
 pass (or on the other side of a merge) is chased to a retained ID, so a
 single lookup always lands on a live target.").
normalize_forwardings(Entries) ->
    Fuel = maps:size(Entries) + 1,
    gleam@dict:map_values(Entries, fun(_, Forwarding) ->
        {forwarding, Left, Right} = Forwarding,
        {forwarding, chase_left(Left, Entries, Fuel), chase_right(Right, Entries, Fuel)}
    end).

-file("src/lattice_sequence/sequence.gleam", 2830).
-spec pick_forwarding(forwarding(), forwarding()) -> forwarding().
pick_forwarding(A, B) ->
    case compare_origin_pair({erlang:element(2, A), erlang:element(3, A)}, {erlang:element(2, B), erlang:element(3, B)}) of
        gt ->
            B;

        lt ->
            A;

        eq ->
            A
    end.

-file("src/lattice_sequence/sequence.gleam", 2817).
-spec merge_forwarding_entries(gleam@dict:dict(item_id(), forwarding()), gleam@dict:dict(item_id(), forwarding())) -> gleam@dict:dict(item_id(), forwarding()).
merge_forwarding_entries(A, B) ->
    gleam@dict:fold(B, A, fun(Acc, Id, Forwarding) ->
        case gleam_stdlib:map_get(Acc, Id) of
            {ok, Existing} ->
                gleam@dict:insert(Acc, Id, pick_forwarding(Existing, Forwarding));

            {error, nil} ->
                gleam@dict:insert(Acc, Id, Forwarding)
        end
    end).

-file("src/lattice_sequence/sequence.gleam", 857).
-spec merge(sequence(DXA), sequence(DXA), lattice_core@replica_id:replica_id()) -> sequence(DXA).
-doc(~" Merge two sequence CRDT states.

 Items are joined by their stable IDs. Concurrent deletes are preserved by
 keeping the winning delete op, and the merged item set is deterministically
 reordered using each item's left and right origins. Stable blocks form a
 fixed skeleton that live items are ordered around.

 States compacted at different frontiers merge as long as one frontier
 dominates the other (with a global sequencer, floors are totally ordered
 so this always holds). An item absent from the further-compacted side and
 covered by its frontier is treated as compacted away and stays dropped.

 Pass the identity this replica edits under. The output uses `replica`
 regardless of operand order, and its counter is the maximum of both
 inputs. Independent writers must use distinct identities.

 ## Examples

 ```gleam
 let local = replica_id.new(\"A\")
 sequence.merge(sequence.new(local), sequence.new(replica_id.new(\"B\")), local)
 |> sequence.replica_id()
 // -> local
 ```").
merge(A, B, Replica) ->
    Forwardings = begin
        _pipe = merge_forwarding_entries(erlang:element(5, A), erlang:element(5, B)),
        normalize_forwardings(_pipe)
    end,
    Frontier = lattice_core@version_vector:merge(erlang:element(6, A), erlang:element(6, B)),
    A_elements = segments_to_elements(erlang:element(4, A)),
    B_elements = segments_to_elements(erlang:element(4, B)),
    A_ids = element_id_dict(A_elements),
    B_ids = element_id_dict(B_elements),
    B_lives = live_item_dict(B_elements),
    B_stables = stable_id_dict(B_elements),
    Dropped = fun(Id) ->
        (gleam@dict:has_key(Forwardings, Id) orelse (not gleam@dict:has_key(A_ids, Id) andalso frontier_covers(erlang:element(6, A), Id))) orelse (not gleam@dict:has_key(B_ids, Id) andalso frontier_covers(erlang:element(6, B), Id))
    end,
    Covered_source = case lattice_core@version_vector:compare(erlang:element(6, A), erlang:element(6, B)) of
        before ->
            B_elements;

        concurrent ->
            case frontier_tiebreak(erlang:element(6, A), erlang:element(6, B)) of
                gt ->
                    B_elements;

                lt ->
                    A_elements;

                eq ->
                    A_elements
            end;

        'after' ->
            A_elements;

        equal ->
            A_elements
    end,
    {Other_lives, Other_stables} = case Covered_source =:= A_elements of
        true ->
            {B_lives, B_stables};

        false ->
            {live_item_dict(A_elements), stable_id_dict(A_elements)}
    end,
    Covered_elements = begin
        _pipe@1 = Covered_source,
        _pipe@2 = gleam@list:filter(_pipe@1, fun(El) ->
            is_stable_element(El) orelse frontier_covers(Frontier, element_id(El))
        end),
        _pipe@3 = gleam@list:filter(_pipe@2, fun(El) ->
            not Dropped(element_id(El))
        end),
        gleam@list:map(_pipe@3, fun(_capture) ->
            reconcile_element(_capture, Other_lives, Other_stables, Frontier)
        end)
    end,
    Volatile_pool = begin
        _pipe@4 = lists:append(live_items_of(A_elements), live_items_of(B_elements)),
        _pipe@5 = gleam@list:filter(_pipe@4, fun(Item) ->
            not frontier_covers(Frontier, erlang:element(2, Item)) andalso not Dropped(erlang:element(2, Item))
        end),
        _pipe@6 = gleam@list:fold(_pipe@5, maps:new(), fun(Pool, Item) ->
            case gleam_stdlib:map_get(Pool, erlang:element(2, Item)) of
                {ok, Existing} ->
                    gleam@dict:insert(Pool, erlang:element(2, Item), merge_item(Existing, Item));

                {error, nil} ->
                    gleam@dict:insert(Pool, erlang:element(2, Item), Item)
            end
        end),
        _pipe@7 = maps:values(_pipe@6),
        gleam@list:map(_pipe@7, fun(_value) ->
            {live_el, _value}
        end)
    end,
    Elements = rebuild(lists:append(Covered_elements, Volatile_pool), Forwardings, Frontier),
    {sequence, Replica, gleam@int:max(erlang:element(3, A), erlang:element(3, B)), elements_to_segments(Elements), Forwardings, Frontier}.

-file("src/lattice_sequence/sequence.gleam", 941).
-spec merge_as(sequence(DXE), sequence(DXE), lattice_core@replica_id:replica_id()) -> sequence(DXE).
-doc(~" Alias for `merge`, with the same explicit output replica identity.

 ## Examples

 ```gleam
 sequence.merge_as(a, b, local) == sequence.merge(a, b, local)
 // -> True
 ```").
merge_as(A, B, Replica) ->
    merge(A, B, Replica).

-file("src/lattice_sequence/sequence.gleam", 1547).
-spec left_targets(list(classified(ECE)), gleam@option:option(item_id()), gleam@dict:dict(item_id(), gleam@option:option(item_id())), fun((element(ECE)) -> boolean())) -> gleam@dict:dict(item_id(), gleam@option:option(item_id())).
left_targets(Classified, Last_retained, Acc, Settled) ->
    case Classified of
        [] ->
            Acc;

        [{retained, El} | Rest] ->
            case Settled(El) of
                true ->
                    left_targets(Rest, {some, element_id(El)}, Acc, Settled);

                false ->
                    left_targets(Rest, Last_retained, Acc, Settled)
            end;

        [{dropped, Id} | Rest@1] ->
            left_targets(Rest@1, Last_retained, gleam@dict:insert(Acc, Id, Last_retained), Settled)
    end.

-file("src/lattice_sequence/sequence.gleam", 1519).
-spec forwarding_entries_for_pass(list(classified(any())), lattice_core@version_vector:version_vector()) -> gleam@dict:dict(item_id(), forwarding()).
-doc(~" Forwardings for one pass, naming only settled landmarks.

 A forwarding must resolve identically on every replica, and volatile
 membership does not: replicas compacting at the same frontier hold
 different above-frontier items, so a forwarding naming one would point
 somewhere the other cannot follow.

 Move anchors make this load-bearing: they splice at an exact position
 rather than searching a window, so the identity of the target decides the
 result outright.").
forwarding_entries_for_pass(Classified, Stable) ->
    Settled = fun(El) ->
        frontier_covers(Stable, element_id(El))
    end,
    Lefts = left_targets(Classified, none, maps:new(), Settled),
    {Rights, _} = gleam@list:fold_right(Classified, {maps:new(), none}, fun(Acc, Entry) ->
        {Targets, Next_retained} = Acc,
        case Entry of
            {retained, El} ->
                case Settled(El) of
                    true ->
                        {Targets, {some, element_id(El)}};

                    false ->
                        {Targets, Next_retained}
                end;

            {dropped, Id} ->
                {gleam@dict:insert(Targets, Id, Next_retained), Next_retained}
        end
    end),
    gleam@dict:fold(Lefts, maps:new(), fun(Acc, Id, Left) ->
        Right = case gleam_stdlib:map_get(Rights, Id) of
            {ok, Target} ->
                Target;

            {error, nil} ->
                none
        end,
        gleam@dict:insert(Acc, Id, {forwarding, Left, Right})
    end).

-file("src/lattice_sequence/sequence.gleam", 2808).
-spec frontier_covers_op(lattice_core@version_vector:version_vector(), op_id()) -> boolean().
frontier_covers_op(Frontier, Op) ->
    {op_id, Rid, Counter} = Op,
    lattice_core@version_vector:get(Frontier, Rid) >= Counter.

-file("src/lattice_sequence/sequence.gleam", 1494).
-spec item_stability(item(any()), lattice_core@version_vector:version_vector()) -> stability().
-doc(~" A settled tombstone is reclaimed and a settled plain item is baked into the
 skeleton; anything above the frontier or holding an unacknowledged delete
 stays live.").
item_stability(Item, Stable) ->
    gleam@bool:guard(not frontier_covers(Stable, erlang:element(2, Item)), keep_live, fun() ->
        case {erlang:element(6, Item), erlang:element(7, Item)} of
            {{some, Op}, _} ->
                case frontier_covers_op(Stable, Op) of
                    true ->
                        drop_tombstone;

                    false ->
                        keep_live
                end;

            {none, none} ->
                to_stable;

            {none, {some, _}} ->
                keep_live
        end
    end).

-file("src/lattice_sequence/sequence.gleam", 1475).
-spec insert_optional_id(gleam@dict:dict(item_id(), nil), gleam@option:option(item_id())) -> gleam@dict:dict(item_id(), nil).
insert_optional_id(Acc, Id) ->
    case Id of
        none ->
            Acc;

        {some, Id@1} ->
            gleam@dict:insert(Acc, Id@1, nil)
    end.

-file("src/lattice_sequence/sequence.gleam", 1461).
-spec move_anchor_ids(list(element(any()))) -> gleam@dict:dict(item_id(), nil).
-doc(~" Every ID a live move still names as one of its target-gap boundaries.

 Reclaiming one of these would leave the move anchoring on a gap that has
 to be reconstructed from forwardings, and the reconstruction is not
 position-identical: a compacted replica and an uncompacted one would
 splice the mover differently. Retaining them keeps move resolution exactly
 what it was before the pass, at a cost of at most two extra tombstones per
 live mover.").
move_anchor_ids(Elements) ->
    _pipe = Elements,
    _pipe@1 = live_items_of(_pipe),
    gleam@list:fold(_pipe@1, maps:new(), fun(Acc, Item) ->
        case erlang:element(7, Item) of
            none ->
                Acc;

            {some, {move, _, Move_left, Move_right}} ->
                _pipe@2 = Acc,
                _pipe@3 = insert_optional_id(_pipe@2, Move_left),
                insert_optional_id(_pipe@3, Move_right)
        end
    end).

-file("src/lattice_sequence/sequence.gleam", 1394).
-spec do_compact(sequence(EBK), lattice_core@version_vector:version_vector()) -> {sequence(EBK), forwarding_map()}.
do_compact(Sequence, Stable) ->
    Elements = segments_to_elements(erlang:element(4, Sequence)),
    Anchored = move_anchor_ids(Elements),
    Classified = gleam@list:map(Elements, fun(El) ->
        case El of
            {stable, _, _} ->
                {retained, El};

            {live_el, Item} ->
                case gleam@dict:has_key(Anchored, erlang:element(2, Item)) of
                    true ->
                        {retained, El};

                    false ->
                        case item_stability(Item, Stable) of
                            drop_tombstone ->
                                {dropped, erlang:element(2, Item)};

                            to_stable ->
                                {retained, {stable, erlang:element(2, Item), erlang:element(5, Item)}};

                            keep_live ->
                                {retained, El}
                        end
                end
        end
    end),
    New_entries = forwarding_entries_for_pass(Classified, Stable),
    Kept = gleam@list:filter_map(Classified, fun(Entry) ->
        case Entry of
            {retained, El} ->
                {ok, El};

            {dropped, _} ->
                {error, nil}
        end
    end),
    Updated_old = gleam@dict:map_values(erlang:element(5, Sequence), fun(_, Forwarding) ->
        {forwarding, Left, Right} = Forwarding,
        {forwarding, chase_left(Left, New_entries, maps:size(New_entries) + 1), chase_right(Right, New_entries, maps:size(New_entries) + 1)}
    end),
    All_forwardings = gleam@dict:fold(New_entries, Updated_old, fun(Acc, Id, Forwarding) ->
        gleam@dict:insert(Acc, Id, Forwarding)
    end),
    Compacted = {sequence, erlang:element(2, Sequence), erlang:element(3, Sequence), elements_to_segments(Kept), All_forwardings, Stable},
    {Compacted, {forwarding_map, New_entries}}.

-file("src/lattice_sequence/sequence.gleam", 1376).
-spec compact(sequence(EBH), lattice_core@version_vector:version_vector()) -> {sequence(EBH), forwarding_map()}.
-doc(~" Compact everything at or below a stability frontier.

 `stable` must describe a causal cut the host knows no in-flight or future
 op can reference (e.g. the version vector accumulated by replaying ops up
 to a global sequencer's acknowledgement floor). For the stable region the
 pass drops tombstones, merges runs of adjacent same-replica items with
 sequential counters into blocks, and strips origins and move slots.

 Returns the compacted sequence and the forwarding entries emitted by this
 pass (one per dropped ID). The cumulative forwarding map is also carried
 in the sequence; hosts bound its growth with `remove_forwardings`.

 Compacting at the current frontier, at an older one, or at one concurrent
 with it is a no-op — frontiers only advance.

 Moved items remain live so their move records and insertion origins survive.
 The pass can still stabilize unrelated items and reclaim tombstones, while
 retaining any target-gap boundaries referenced by a live move.").
compact(Sequence, Stable) ->
    case lattice_core@version_vector:compare(Stable, erlang:element(6, Sequence)) of
        'after' ->
            do_compact(Sequence, Stable);

        before ->
            {Sequence, {forwarding_map, maps:new()}};

        concurrent ->
            {Sequence, {forwarding_map, maps:new()}};

        equal ->
            {Sequence, {forwarding_map, maps:new()}}
    end.

-file("src/lattice_sequence/sequence.gleam", 1668).
-spec right_of(forwarding()) -> gleam@option:option(item_id()).
right_of(Forwarding) ->
    erlang:element(3, Forwarding).

-file("src/lattice_sequence/sequence.gleam", 1664).
-spec left_of(forwarding()) -> gleam@option:option(item_id()).
left_of(Forwarding) ->
    erlang:element(2, Forwarding).

-file("src/lattice_sequence/sequence.gleam", 1647).
-spec translate_move(gleam@option:option(move()), fun((gleam@option:option(item_id()), fun((forwarding()) -> gleam@option:option(item_id()))) -> {ok, gleam@option:option(item_id())} | {error, translate_error()})) -> {ok, gleam@option:option(move())} | {error, translate_error()}.
translate_move(Move, Translate) ->
    case Move of
        none ->
            {ok, none};

        {some, {move, Op, Move_left, Move_right}} ->
            gleam@result:'try'(Translate(Move_left, fun left_of/1), fun(Move_left@1) ->
                gleam@result:'try'(Translate(Move_right, fun right_of/1), fun(Move_right@1) ->
                    {ok, {some, {move, Op, Move_left@1, Move_right@1}}}
                end)
            end)
    end.

-file("src/lattice_sequence/sequence.gleam", 1624).
-spec translate_element(element(ECV), fun((gleam@option:option(item_id()), fun((forwarding()) -> gleam@option:option(item_id()))) -> {ok, gleam@option:option(item_id())} | {error, translate_error()})) -> {ok, element(ECV)} | {error, translate_error()}.
translate_element(El, Translate) ->
    case El of
        {stable, _, _} ->
            {ok, El};

        {live_el, Item} ->
            gleam@result:'try'(Translate(erlang:element(3, Item), fun left_of/1), fun(Origin_left) ->
                gleam@result:'try'(Translate(erlang:element(4, Item), fun right_of/1), fun(Origin_right) ->
                    gleam@result:'try'(translate_move(erlang:element(7, Item), Translate), fun(Move) ->
                        {ok, {live_el, {item, erlang:element(2, Item), Origin_left, Origin_right, erlang:element(5, Item), erlang:element(6, Item), Move}}}
                    end)
                end)
            end)
    end.

-file("src/lattice_sequence/sequence.gleam", 1579).
-spec translate_origins(sequence(ECP), sequence(ECP)) -> {ok, sequence(ECP)} | {error, translate_error()}.
-doc(~" Translate a delta's origins onto a compacted state.

 Rebase support for evicted clients: origins (including move origins)
 referencing compacted IDs are rewritten through `onto`'s forwarding map to
 the gap the ID left behind. Items whose own ID was compacted away are
 dropped from the delta — the op is already settled. Returns
 `Error(UnknownOriginTarget)` when an origin is neither present, part of
 the delta itself, nor forwarded (the forwarding expired); the host must
 degrade the op to a positional edit or discard it.").
translate_origins(Delta, Onto) ->
    Onto_ids = element_id_dict(segments_to_elements(erlang:element(4, Onto))),
    Delta_elements = segments_to_elements(erlang:element(4, Delta)),
    Delta_ids = element_id_dict(Delta_elements),
    Known = fun(Id) ->
        gleam@dict:has_key(Onto_ids, Id) orelse gleam@dict:has_key(Delta_ids, Id)
    end,
    Dropped = fun(Id) ->
        gleam@dict:has_key(erlang:element(5, Onto), Id) orelse (not gleam@dict:has_key(Onto_ids, Id) andalso frontier_covers(erlang:element(6, Onto), Id))
    end,
    Translate = fun(Origin, Pick) ->
        case Origin of
            none ->
                {ok, none};

            {some, Id} ->
                case Known(Id) of
                    true ->
                        {ok, Origin};

                    false ->
                        case gleam_stdlib:map_get(erlang:element(5, Onto), Id) of
                            {ok, Forwarding} ->
                                {ok, Pick(Forwarding)};

                            {error, nil} ->
                                {error, unknown_origin_target}
                        end
                end
        end
    end,
    Translated = begin
        _pipe = Delta_elements,
        _pipe@1 = gleam@list:filter(_pipe, fun(El) ->
            not Dropped(element_id(El))
        end),
        gleam@list:try_map(_pipe@1, fun(_capture) ->
            translate_element(_capture, Translate)
        end)
    end,
    case Translated of
        {ok, Elements} ->
            {ok, {sequence, erlang:element(2, Delta), erlang:element(3, Delta), elements_to_segments(Elements), erlang:element(5, Delta), erlang:element(6, Delta)}};

        {error, Error} ->
            {error, Error}
    end.

-file("src/lattice_sequence/sequence.gleam", 2017).
-spec encode_optional_item_id(gleam@option:option(item_id())) -> gleam@json:json().
encode_optional_item_id(Item_id) ->
    case Item_id of
        {some, Id} ->
            encode_item_id(Id);

        none ->
            gleam@json:null()
    end.

-file("src/lattice_sequence/sequence.gleam", 2008).
-spec encode_op_id(op_id()) -> gleam@json:json().
encode_op_id(Id) ->
    {op_id, Rid, Counter} = Id,
    gleam@json:object([{~"replica_id", gleam@json:string(lattice_core@replica_id:to_string(Rid))}, {~"counter", gleam@json:int(Counter)}]).

-file("src/lattice_sequence/sequence.gleam", 1989).
-spec encode_optional_move(gleam@option:option(move())) -> gleam@json:json().
encode_optional_move(Move) ->
    case Move of
        none ->
            gleam@json:null();

        {some, {move, Op_id, Origin_left, Origin_right}} ->
            gleam@json:object([{~"op_id", encode_op_id(Op_id)}, {~"origin_left", encode_optional_item_id(Origin_left)}, {~"origin_right", encode_optional_item_id(Origin_right)}])
    end.

-file("src/lattice_sequence/sequence.gleam", 2001).
-spec encode_optional_op_id(gleam@option:option(op_id())) -> gleam@json:json().
encode_optional_op_id(Op_id) ->
    case Op_id of
        {some, Op} ->
            encode_op_id(Op);

        none ->
            gleam@json:null()
    end.

-file("src/lattice_sequence/sequence.gleam", 1864).
-spec encode_segment(segment(EEL), fun((EEL) -> gleam@json:json())) -> gleam@json:json().
encode_segment(Segment, Encode_value) ->
    case Segment of
        {block, First_id, Values} ->
            gleam@json:object([{~"kind", gleam@json:string(~"block")}, {~"first_id", encode_item_id(First_id)}, {~"values", gleam@json:array(Values, Encode_value)}]);

        {live, Item} ->
            gleam@json:object([{~"kind", gleam@json:string(~"item")}, {~"id", encode_item_id(erlang:element(2, Item))}, {~"origin_left", encode_optional_item_id(erlang:element(3, Item))}, {~"origin_right", encode_optional_item_id(erlang:element(4, Item))}, {~"value", Encode_value(erlang:element(5, Item))}, {~"deleted", encode_optional_op_id(erlang:element(6, Item))}, {~"move", encode_optional_move(erlang:element(7, Item))}])
    end.

-file("src/lattice_sequence/sequence.gleam", 1934).
-spec encode_forwarding({item_id(), forwarding()}) -> gleam@json:json().
encode_forwarding(Entry) ->
    {Id, {forwarding, Left, Right}} = Entry,
    gleam@json:object([{~"id", encode_item_id(Id)}, {~"left", encode_optional_item_id(Left)}, {~"right", encode_optional_item_id(Right)}]).

-file("src/lattice_sequence/sequence.gleam", 1678).
-spec to_json(sequence(EDQ), fun((EDQ) -> gleam@json:json())) -> gleam@json:json().
-doc(~" Encode a sequence CRDT as a self-describing JSON value.

 Produces an envelope with `type`, `v` (schema version), and `state`. The
 state includes this replica ID, local counter, applied compaction
 frontier, forwarding entries, and every segment: compact blocks of stable
 values and full items including tombstones.").
to_json(Sequence, Encode_value) ->
    gleam@json:object([{~"type", gleam@json:string(~"sequence")}, {~"v", gleam@json:int(2)}, {~"state", gleam@json:object([{~"self_id", lattice_core@replica_id:to_json(erlang:element(2, Sequence))}, {~"counter", gleam@json:int(erlang:element(3, Sequence))}, {~"frontier", lattice_core@version_vector:to_json(erlang:element(6, Sequence))}, {~"forwardings", gleam@json:array(maps:to_list(erlang:element(5, Sequence)), fun encode_forwarding/1)}, {~"segments", gleam@json:array(erlang:element(4, Sequence), fun(_capture) ->
        encode_segment(_capture, Encode_value)
    end)}])}]).

-file("src/lattice_sequence/sequence.gleam", 1841).
-spec base_order_segments(integer(), list(segment(EEC)), gleam@dict:dict(item_id(), forwarding())) -> {ok, list(segment(EEC))} | {error, nil}.
-doc(~" Bring a decoded payload's segments into canonical base order.

 Version 2 stores the pre-move base and overlays moves on read, so its
 segments are already the base. Version 1 stored the move-APPLIED order, so
 a mover sits at its post-move slot and would be pinned there.

 A v1 payload with no move records never had an overlay, so its order is
 already the base. One with movers but no compacted segments still carries
 every origin, so the base re-derives exactly. One with both is
 unrecoverable — the compacted elements have no origins to re-integrate
 from, and replicas at different frontiers would reconstruct the mover's
 slot differently — so it is rejected and the holder must resync.").
base_order_segments(Version, Segments, Forwardings) ->
    Elements = segments_to_elements(Segments),
    case (Version >= 2) orelse not gleam@list:any(live_items_of(Elements), fun has_move/1) of
        true ->
            {ok, elements_to_segments(Elements)};

        false ->
            case gleam@list:any(Elements, fun is_stable_element/1) of
                true ->
                    {error, nil};

                false ->
                    {ok, elements_to_segments(rebuild_base(Elements, Forwardings, lattice_core@version_vector:new()))}
            end
    end.

-file("src/lattice_sequence/sequence.gleam", 1822).
-spec include_origin_counter(integer(), gleam@option:option(item_id())) -> integer().
include_origin_counter(Counter, Origin) ->
    case Origin of
        none ->
            Counter;

        {some, Id} ->
            gleam@int:max(Counter, erlang:element(3, Id))
    end.

-file("src/lattice_sequence/sequence.gleam", 1780).
-spec allocation_counter(integer(), list(segment(any())), list({item_id(), forwarding()}), lattice_core@version_vector:version_vector()) -> integer().
allocation_counter(Counter, Segments, Forwardings, Frontier) ->
    Counter@1 = begin
        _pipe = lattice_core@version_vector:to_dict(Frontier),
        _pipe@1 = maps:values(_pipe),
        gleam@list:fold(_pipe@1, Counter, fun gleam@int:max/2)
    end,
    Counter@2 = gleam@list:fold(Segments, Counter@1, fun(Max, Segment) ->
        case Segment of
            {block, First_id, Values} ->
                gleam@int:max(Max, erlang:element(3, First_id) + gleam@int:max(0, erlang:length(Values) - 1));

            {live, Item} ->
                Max@1 = begin
                    _pipe@2 = gleam@int:max(Max, erlang:element(3, erlang:element(2, Item))),
                    _pipe@3 = include_origin_counter(_pipe@2, erlang:element(3, Item)),
                    include_origin_counter(_pipe@3, erlang:element(4, Item))
                end,
                Max@2 = case erlang:element(6, Item) of
                    none ->
                        Max@1;

                    {some, Op} ->
                        gleam@int:max(Max@1, erlang:element(3, Op))
                end,
                case erlang:element(7, Item) of
                    none ->
                        Max@2;

                    {some, Move} ->
                        _pipe@4 = gleam@int:max(Max@2, erlang:element(3, erlang:element(2, Move))),
                        _pipe@5 = include_origin_counter(_pipe@4, erlang:element(3, Move)),
                        include_origin_counter(_pipe@5, erlang:element(4, Move))
                end
        end
    end),
    gleam@list:fold(Forwardings, Counter@2, fun(Max, Entry) ->
        {Id, Forwarding} = Entry,
        _pipe@2 = gleam@int:max(Max, erlang:element(3, Id)),
        _pipe@3 = include_origin_counter(_pipe@2, erlang:element(2, Forwarding)),
        include_origin_counter(_pipe@3, erlang:element(3, Forwarding))
    end).

-file("src/lattice_sequence/sequence.gleam", 1967).
-spec op_id_decoder() -> gleam@dynamic@decode:decoder(op_id()).
op_id_decoder() ->
    gleam@dynamic@decode:field(~"replica_id", lattice_core@replica_id:decoder(), fun(Rid) ->
        gleam@dynamic@decode:field(~"counter", non_negative_int_decoder(), fun(Counter) ->
            gleam@dynamic@decode:success({op_id, Rid, Counter})
        end)
    end).

-file("src/lattice_sequence/sequence.gleam", 1950).
-spec move_decoder() -> gleam@dynamic@decode:decoder(move()).
move_decoder() ->
    gleam@dynamic@decode:field(~"op_id", op_id_decoder(), fun(Op_id) ->
        gleam@dynamic@decode:field(~"origin_left", gleam@dynamic@decode:optional(item_id_decoder()), fun(Origin_left) ->
            gleam@dynamic@decode:field(~"origin_right", gleam@dynamic@decode:optional(item_id_decoder()), fun(Origin_right) ->
                gleam@dynamic@decode:success({move, Op_id, Origin_left, Origin_right})
            end)
        end)
    end).

-file("src/lattice_sequence/sequence.gleam", 1888).
-spec segment_decoder(gleam@dynamic@decode:decoder(EEN)) -> gleam@dynamic@decode:decoder(segment(EEN)).
segment_decoder(Value_decoder) ->
    gleam@dynamic@decode:field(~"kind", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(Kind) ->
        case Kind of
            ~"block" ->
                gleam@dynamic@decode:field(~"first_id", item_id_decoder(), fun(First_id) ->
                    gleam@dynamic@decode:field(~"values", gleam@dynamic@decode:list(Value_decoder), fun(Values) ->
                        gleam@dynamic@decode:success({block, First_id, Values})
                    end)
                end);

            ~"item" ->
                gleam@dynamic@decode:field(~"id", item_id_decoder(), fun(Id) ->
                    gleam@dynamic@decode:field(~"origin_left", gleam@dynamic@decode:optional(item_id_decoder()), fun(Origin_left) ->
                        gleam@dynamic@decode:field(~"origin_right", gleam@dynamic@decode:optional(item_id_decoder()), fun(Origin_right) ->
                            gleam@dynamic@decode:field(~"value", Value_decoder, fun(Value) ->
                                gleam@dynamic@decode:field(~"deleted", gleam@dynamic@decode:optional(op_id_decoder()), fun(Deleted) ->
                                    gleam@dynamic@decode:optional_field(~"move", none, gleam@dynamic@decode:optional(move_decoder()), fun(Move) ->
                                        gleam@dynamic@decode:success({live, {item, Id, Origin_left, Origin_right, Value, Deleted, Move}})
                                    end)
                                end)
                            end)
                        end)
                    end)
                end);

            _ ->
                gleam@dynamic@decode:failure({block, {item_id, lattice_core@replica_id:new(~""), 0}, []}, ~"segment kind of block or item")
        end
    end).

-file("src/lattice_sequence/sequence.gleam", 1943).
-spec forwarding_decoder() -> gleam@dynamic@decode:decoder({item_id(), forwarding()}).
forwarding_decoder() ->
    gleam@dynamic@decode:field(~"id", item_id_decoder(), fun(Id) ->
        gleam@dynamic@decode:field(~"left", gleam@dynamic@decode:optional(item_id_decoder()), fun(Left) ->
            gleam@dynamic@decode:field(~"right", gleam@dynamic@decode:optional(item_id_decoder()), fun(Right) ->
                gleam@dynamic@decode:success({Id, {forwarding, Left, Right}})
            end)
        end)
    end).

-file("src/lattice_sequence/sequence.gleam", 1712).
-spec from_json(binary(), gleam@dynamic@decode:decoder(EDS)) -> {ok, sequence(EDS)} | {error, gleam@json:decode_error()}.
-doc(~" Decode a sequence CRDT from a JSON string produced by `to_json`.

 Returns `Ok(Sequence)` on success, or `Error(json.DecodeError)` if the
 input is not a valid sequence JSON envelope. Live items are reordered
 deterministically from their stable origins before the `Sequence` is
 returned. If retained IDs or the compaction frontier exceed the encoded
 allocation counter, the counter is raised to that high-water mark. This
 prevents ID reuse when the snapshot is edited under any replica identity.").
from_json(Json_string, Value_decoder) ->
    State_decoder = fun(Version) ->
        gleam@dynamic@decode:field(~"state", begin
            gleam@dynamic@decode:field(~"self_id", lattice_core@replica_id:decoder(), fun(Self_id) ->
                gleam@dynamic@decode:field(~"counter", non_negative_int_decoder(), fun(Counter) ->
                    gleam@dynamic@decode:field(~"frontier", lattice_core@version_vector:decoder(), fun(Frontier) ->
                        gleam@dynamic@decode:field(~"forwardings", gleam@dynamic@decode:list(forwarding_decoder()), fun(Forwardings) ->
                            gleam@dynamic@decode:field(~"segments", gleam@dynamic@decode:list(segment_decoder(Value_decoder)), fun(Segments) ->
                                Counter@1 = allocation_counter(Counter, Segments, Forwardings, Frontier),
                                Forwarding_map = maps:from_list(Forwardings),
                                case base_order_segments(Version, Segments, Forwarding_map) of
                                    {ok, Base} ->
                                        gleam@dynamic@decode:success({sequence, Self_id, Counter@1, Base, Forwarding_map, Frontier});

                                    {error, nil} ->
                                        gleam@dynamic@decode:failure({sequence, Self_id, Counter@1, [], Forwarding_map, Frontier}, ~"a v1 payload whose moved items were not already compacted")
                                end
                            end)
                        end)
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
            case (Type_tag =:= ~"sequence") andalso ((Version =:= 1) orelse (Version =:= 2)) of
                true ->
                    gleam@json:parse(Json_string, State_decoder(Version));

                false ->
                    {error, {unable_to_decode, [{decode_error, ~"type=sequence and v=1 or v=2", <<<<Type_tag/binary, " v="/utf8>>/binary, (erlang:integer_to_binary(Version))/binary>>, []}]}}
            end
    end.

