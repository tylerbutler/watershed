-module(lattice_sets@or_set).
-compile([no_auto_import, nowarn_ignored, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-export([new/1, add_with_delta/2, add/2, remove_with_delta/2, remove/2, remove_all/2, value/1, remove_where/2, contains/2, diff/2, merge/2, merge_with_diff/2, remove_with_bound/2, pruned_vv/1, prune/2, to_json/1, to_json_with/2, from_json/1, from_json_with/2]).
-export_type([tag/0, o_r_set/1, diff/1]).
-moduledoc(~" An observed-remove set (OR-Set) CRDT.

 The most flexible set CRDT: supports add, remove, and re-add. Each add
 creates a unique tag. Remove only deletes tags observed locally, so a
 concurrent add on another replica survives (add-wins semantics). This makes
 OR-Set suitable for collaborative data where elements may be toggled.

 ## Example

 ```gleam
 import lattice_core/replica_id
 import lattice_sets/or_set

 let a = or_set.new(replica_id.new(\"node-a\")) |> or_set.add(\"item\")
 let b = or_set.new(replica_id.new(\"node-b\")) |> or_set.add(\"item\") |> or_set.remove(\"item\")
 let merged = or_set.merge(a, b)
 or_set.contains(merged, \"item\")  // -> True (concurrent add wins)
 ```").

-opaque tag() :: {tag, lattice_core@replica_id:replica_id(), integer()}.

-opaque o_r_set(DVU) :: {o_r_set, lattice_core@replica_id:replica_id(), integer(), gleam@dict:dict(DVU, gleam@set:set(tag())), gleam@set:set(tag()), lattice_core@version_vector:version_vector()}.

-type diff(DVV) :: {diff, gleam@set:set(DVV), gleam@set:set(DVV)}.

-file("src/lattice_sets/or_set.gleam", 75).
-spec new(lattice_core@replica_id:replica_id()) -> o_r_set(any()).
-doc(~" Create a new empty OR-Set for the given replica.

 Each replica should have a unique `replica_id` to ensure that tags
 generated on different replicas never collide.").
new(Replica_id) ->
    {o_r_set, Replica_id, 0, maps:new(), gleam@set:new(), lattice_core@version_vector:new()}.

-file("src/lattice_sets/or_set.gleam", 108).
-spec add_with_delta(o_r_set(DWB), DWB) -> {o_r_set(DWB), o_r_set(DWB)}.
-doc(~" Add an element and return both the new state and a delta.

 The returned delta is an `ORSet` whose `entries` contains only the newly
 inserted element with its single fresh tag, with empty tombstones and
 pruned vector. Merging the delta into a remote via `merge` adds the new
 tag to the remote's entry for `element` (creating it if necessary),
 producing the same observable result as merging the full new state.

 The delta carries this replica's `replica_id` and the post-mutation
 `counter`, so successive deltas remain causally distinguishable.").
add_with_delta(Orset, Element) ->
    New_counter = erlang:element(3, Orset) + 1,
    Tag = {tag, erlang:element(2, Orset), New_counter},
    Existing_tags = gleam@result:unwrap(gleam_stdlib:map_get(erlang:element(4, Orset), Element), gleam@set:new()),
    New_tags = gleam@set:insert(Existing_tags, Tag),
    Updated = {o_r_set, erlang:element(2, Orset), New_counter, gleam@dict:insert(erlang:element(4, Orset), Element, New_tags), erlang:element(5, Orset), erlang:element(6, Orset)},
    Delta = {o_r_set, erlang:element(2, Orset), New_counter, maps:from_list([{Element, gleam@set:from_list([Tag])}]), gleam@set:new(), lattice_core@version_vector:new()},
    {Updated, Delta}.

-file("src/lattice_sets/or_set.gleam", 93).
-spec add(o_r_set(DVY), DVY) -> o_r_set(DVY).
-doc(~" Add an element to the set.

 Creates a fresh unique tag for this add operation using the replica's
 monotonically-increasing counter. The element may already be present;
 in that case a new tag is added alongside existing ones.

 See `add_with_delta` for the delta-state variant that also returns a
 small payload suitable for incremental sync (e.g. over websockets).").
add(Orset, Element) ->
    {Updated, _} = add_with_delta(Orset, Element),
    Updated.

-file("src/lattice_sets/or_set.gleam", 152).
-spec remove_with_delta(o_r_set(DWI), DWI) -> {o_r_set(DWI), o_r_set(DWI)}.
-doc(~" Remove an element and return both the new state and a delta.

 The returned delta is an `ORSet` whose `tombstones` contains exactly the
 tags that were live for `element` at the time of the remove, with empty
 entries and pruned vector. Merging the delta into a remote via `merge`
 retracts those tags from the remote's entry for `element`. Tags that the
 remote has but the delta source had not yet observed (concurrent adds)
 survive — preserving the add-wins property of OR-Set.").
remove_with_delta(Orset, Element) ->
    Removed_tags = gleam@result:unwrap(gleam_stdlib:map_get(erlang:element(4, Orset), Element), gleam@set:new()),
    Updated = {o_r_set, erlang:element(2, Orset), erlang:element(3, Orset), gleam@dict:delete(erlang:element(4, Orset), Element), gleam@set:union(erlang:element(5, Orset), Removed_tags), erlang:element(6, Orset)},
    Delta = {o_r_set, erlang:element(2, Orset), erlang:element(3, Orset), maps:new(), Removed_tags, lattice_core@version_vector:new()},
    {Updated, Delta}.

-file("src/lattice_sets/or_set.gleam", 139).
-spec remove(o_r_set(DWF), DWF) -> o_r_set(DWF).
-doc(~" Remove an element from the set.

 Removes all currently observed tags for the element (observed-remove
 semantics). Any concurrent add on another replica that created a new tag
 not yet observed here will survive this remove after merging.

 See `remove_with_delta` for the delta-state variant.").
remove(Orset, Element) ->
    {Updated, _} = remove_with_delta(Orset, Element),
    Updated.

-file("src/lattice_sets/or_set.gleam", 176).
-spec remove_all(o_r_set(DWM), list(DWM)) -> o_r_set(DWM).
-doc(~" Remove each element in `elements` using observed-remove semantics.

 Missing elements are ignored, matching `remove`.").
remove_all(Orset, Elements) ->
    gleam@list:fold(Elements, Orset, fun(Acc, Element) ->
        remove(Acc, Element)
    end).

-file("src/lattice_sets/or_set.gleam", 208).
-spec value(o_r_set(DWV)) -> gleam@set:set(DWV).
-doc(~" Return the set of all elements currently in the OR-Set.

 An element is included only when its tag set is non-empty.").
value(Orset) ->
    _pipe = maps:keys(erlang:element(4, Orset)),
    gleam@set:from_list(_pipe).

-file("src/lattice_sets/or_set.gleam", 184).
-spec remove_where(o_r_set(DWQ), fun((DWQ) -> boolean())) -> o_r_set(DWQ).
-doc(~" Remove every currently observable element matching `predicate`.

 The predicate is evaluated against `value(orset)`, then each matching value
 is removed with normal observed-remove semantics.").
remove_where(Orset, Predicate) ->
    Elements = begin
        _pipe = value(Orset),
        _pipe@1 = gleam@set:to_list(_pipe),
        gleam@list:filter(_pipe@1, Predicate)
    end,
    remove_all(Orset, Elements).

-file("src/lattice_sets/or_set.gleam", 198).
-spec contains(o_r_set(DWT), DWT) -> boolean().
-doc(~" Check if the set contains the given element.

 Returns `True` if the element has at least one live tag (i.e., it has
 been added and not yet removed on this replica, or a concurrent add
 survived a remove after merging).").
contains(Orset, Element) ->
    case gleam_stdlib:map_get(erlang:element(4, Orset), Element) of
        {error, nil} ->
            false;

        {ok, Tags} ->
            not gleam@set:is_empty(Tags)
    end.

-file("src/lattice_sets/or_set.gleam", 219).
-spec diff(o_r_set(DWY), o_r_set(DWY)) -> diff(DWY).
-doc(~" Compare the observable values of two OR-Sets.

 `added` contains values present in `after` but not `before`.
 `removed` contains values present in `before` but not `after`.").
diff(Before, After) ->
    Before_values = value(Before),
    After_values = value(After),
    {diff, gleam@set:difference(After_values, Before_values), gleam@set:difference(Before_values, After_values)}.

-file("src/lattice_sets/or_set.gleam", 315).
-spec pruned_on_side_without_live_tag(tag(), gleam@set:set(tag()), lattice_core@version_vector:version_vector()) -> boolean().
pruned_on_side_without_live_tag(Tag, Live_tags, Pruned) ->
    {tag, Replica, Counter} = Tag,
    (lattice_core@version_vector:get(Pruned, Replica) >= Counter) andalso not gleam@set:contains(Live_tags, Tag).

-file("src/lattice_sets/or_set.gleam", 304).
-spec is_pruned_zombie(tag(), gleam@set:set(tag()), lattice_core@version_vector:version_vector(), gleam@set:set(tag()), lattice_core@version_vector:version_vector()) -> boolean().
is_pruned_zombie(Tag, A_tags, A_pruned, B_tags, B_pruned) ->
    pruned_on_side_without_live_tag(Tag, A_tags, A_pruned) orelse pruned_on_side_without_live_tag(Tag, B_tags, B_pruned).

-file("src/lattice_sets/or_set.gleam", 297).
-spec counter_with_pruned_floor(integer(), lattice_core@version_vector:version_vector()) -> integer().
counter_with_pruned_floor(Counter, Pruned) ->
    _pipe = Pruned,
    _pipe@1 = lattice_core@version_vector:to_dict(_pipe),
    _pipe@2 = maps:values(_pipe@1),
    gleam@list:fold(_pipe@2, Counter, fun gleam@int:max/2).

-file("src/lattice_sets/or_set.gleam", 292).
-spec not_dominated(tag(), lattice_core@version_vector:version_vector()) -> boolean().
not_dominated(Tag, Pruned) ->
    {tag, Replica, Counter} = Tag,
    lattice_core@version_vector:get(Pruned, Replica) < Counter.

-file("src/lattice_sets/or_set.gleam", 240).
-spec merge(o_r_set(DXC), o_r_set(DXC)) -> o_r_set(DXC).
-doc(~" Merge two OR-Sets.

 For each element, the merged tag set is the union of both sides' tags,
 minus merged tombstones, and minus any tags dominated by the merged
 pruned vector that are not live on the side that pruned them (zombie
 detection). An element is present if it has at least one surviving tag.

 The merged counter covers both sides and the merged pruning frontier,
 ensuring future adds remain above retained allocation history.

 Merge is commutative, associative, and idempotent (a valid CRDT join).").
merge(A, B) ->
    Merged_pruned = lattice_core@version_vector:merge(erlang:element(6, A), erlang:element(6, B)),
    Merged_tombstones = begin
        _pipe = gleam@set:union(erlang:element(5, A), erlang:element(5, B)),
        gleam@set:filter(_pipe, fun(Tag) ->
            not_dominated(Tag, Merged_pruned)
        end)
    end,
    Merged_counter = counter_with_pruned_floor(gleam@int:max(erlang:element(3, A), erlang:element(3, B)), Merged_pruned),
    A_keys = maps:keys(erlang:element(4, A)),
    B_keys = maps:keys(erlang:element(4, B)),
    All_keys = gleam@list:unique(lists:append(A_keys, B_keys)),
    Merged_entries = gleam@list:fold(All_keys, maps:new(), fun(Acc, Element) ->
        A_tags = gleam@result:unwrap(gleam_stdlib:map_get(erlang:element(4, A), Element), gleam@set:new()),
        B_tags = gleam@result:unwrap(gleam_stdlib:map_get(erlang:element(4, B), Element), gleam@set:new()),
        Combined = begin
            _pipe@1 = gleam@set:union(A_tags, B_tags),
            gleam@set:filter(_pipe@1, fun(Tag) ->
                not gleam@set:contains(Merged_tombstones, Tag) andalso not is_pruned_zombie(Tag, A_tags, erlang:element(6, A), B_tags, erlang:element(6, B))
            end)
        end,
        case gleam@set:is_empty(Combined) of
            true ->
                Acc;

            false ->
                gleam@dict:insert(Acc, Element, Combined)
        end
    end),
    {o_r_set, erlang:element(2, A), Merged_counter, Merged_entries, Merged_tombstones, Merged_pruned}.

-file("src/lattice_sets/or_set.gleam", 284).
-spec merge_with_diff(o_r_set(DXG), o_r_set(DXG)) -> {o_r_set(DXG), diff(DXG)}.
-doc(~" Merge two OR-Sets and report observable value changes from `local`.

 The returned OR-Set is exactly the same as `merge(local, remote)`. The
 diff compares `value(local)` with `value(merged)`, so it reports only
 externally visible additions and removals.").
merge_with_diff(Local, Remote) ->
    Merged = merge(Local, Remote),
    {Merged, diff(Local, Merged)}.

-file("src/lattice_sets/or_set.gleam", 348).
-spec tags_to_bound(gleam@set:set(tag())) -> lattice_core@version_vector:version_vector().
tags_to_bound(Tags) ->
    gleam@set:fold(Tags, lattice_core@version_vector:new(), fun(Bound, Tag) ->
        {tag, Replica, Counter} = Tag,
        lattice_core@version_vector:set_max(Bound, Replica, Counter)
    end).

-file("src/lattice_sets/or_set.gleam", 333).
-spec remove_with_bound(o_r_set(DXO), DXO) -> {o_r_set(DXO), lattice_core@version_vector:version_vector()}.
-doc(~" Remove an element and return a causal bound for the removed tags.

 Behaves identically to `remove` but also returns a `VersionVector`
 representing the maximum counter per replica across all tags that were
 live for the element. This bound can be compared against a pruned vector
 to determine when the removal is causally stable.

 Returns an empty `VersionVector` if the element had no live tags.").
remove_with_bound(Orset, Element) ->
    Removed_tags = gleam@result:unwrap(gleam_stdlib:map_get(erlang:element(4, Orset), Element), gleam@set:new()),
    Bound = tags_to_bound(Removed_tags),
    Updated = {o_r_set, erlang:element(2, Orset), erlang:element(3, Orset), gleam@dict:delete(erlang:element(4, Orset), Element), gleam@set:union(erlang:element(5, Orset), Removed_tags), erlang:element(6, Orset)},
    {Updated, Bound}.

-file("src/lattice_sets/or_set.gleam", 360).
-spec pruned_vv(o_r_set(any())) -> lattice_core@version_vector:version_vector().
-doc(~" Return the pruned version vector.

 This is the causal horizon below which tombstones have been garbage
 collected. Useful for determining whether a remove bound is fully
 dominated (causally stable).").
pruned_vv(Orset) ->
    erlang:element(6, Orset).

-file("src/lattice_sets/or_set.gleam", 371).
-spec prune(o_r_set(DXU), lattice_core@version_vector:version_vector()) -> o_r_set(DXU).
-doc(~" Prune tombstones based on a stable version vector.

 Updates the `pruned` vector by merging it with `stable_vv`. Any tombstones
 dominated by the new `pruned` vector are removed. This function should only
 be called with a version vector representing events that have been seen by
 all replicas (causally stable), otherwise \"zombie\" updates might be
 incorrectly ignored.").
prune(Orset, Stable_vv) ->
    New_pruned = lattice_core@version_vector:merge(erlang:element(6, Orset), Stable_vv),
    Pruned_tombstones = gleam@set:filter(erlang:element(5, Orset), fun(Tag) ->
        not_dominated(Tag, New_pruned)
    end),
    {o_r_set, erlang:element(2, Orset), counter_with_pruned_floor(erlang:element(3, Orset), New_pruned), erlang:element(4, Orset), Pruned_tombstones, New_pruned}.

-file("src/lattice_sets/or_set.gleam", 644).
-spec encode_tag(tag()) -> gleam@json:json().
encode_tag(Tag) ->
    {tag, Replica, Counter} = Tag,
    gleam@json:object([{~"r", gleam@json:string(lattice_core@replica_id:to_string(Replica))}, {~"c", gleam@json:int(Counter)}]).

-file("src/lattice_sets/or_set.gleam", 430).
-spec encode_envelope(o_r_set(any()), integer(), gleam@json:json()) -> gleam@json:json().
encode_envelope(Orset, Version, Entries) ->
    gleam@json:object([{~"type", gleam@json:string(~"or_set")}, {~"v", gleam@json:int(Version)}, {~"state", gleam@json:object([{~"replica_id", lattice_core@replica_id:to_json(erlang:element(2, Orset))}, {~"counter", gleam@json:int(erlang:element(3, Orset))}, {~"entries", Entries}, {~"tombstones", gleam@json:array(gleam@set:to_list(erlang:element(5, Orset)), fun encode_tag/1)}, {~"pruned", lattice_core@version_vector:to_json(erlang:element(6, Orset))}])}]).

-file("src/lattice_sets/or_set.gleam", 394).
-spec to_json(o_r_set(binary())) -> gleam@json:json().
-doc(~" Encode an `ORSet(String)` as a self-describing JSON value.

 Entries are encoded as a JSON dict where values are arrays of tag objects
 `{\"r\": replica_id, \"c\": counter}`. Removed tags are encoded separately in
 `tombstones`. The `pruned` version vector tracks garbage-collected causal
 history.

 Format: `{\"type\": \"or_set\", \"v\": 2, \"state\": {\"replica_id\": \"...\", \"counter\": N, \"entries\": {...}, \"tombstones\": [...], \"pruned\": {...}}}`

 The encoded value can be restored with `from_json`.").
to_json(Orset) ->
    encode_envelope(Orset, 2, gleam@json:dict(erlang:element(4, Orset), fun(K) ->
        K
    end, fun(Tags) ->
        gleam@json:array(gleam@set:to_list(Tags), fun encode_tag/1)
    end)).

-file("src/lattice_sets/or_set.gleam", 416).
-spec to_json_with(o_r_set(DXY), fun((DXY) -> gleam@json:json())) -> gleam@json:json().
-doc(~" Encode generic elements and all causal metadata in a v3 envelope.

 `entries` is an array of `{\"value\": ..., \"tags\": [...]}` objects, so
 elements need not be JSON object keys. String `to_json` continues to
 write the legacy v2 object representation.

 ## Examples

 ```gleam
 let set = or_set.new(replica_id.new(\"A\")) |> or_set.add(42)
 or_set.to_json_with(set, json.int)
 ```").
to_json_with(Orset, Encode) ->
    encode_envelope(Orset, 3, gleam@json:array(maps:to_list(erlang:element(4, Orset)), fun(Entry) ->
        {Value, Tags} = Entry,
        gleam@json:object([{~"value", Encode(Value)}, {~"tags", gleam@json:array(gleam@set:to_list(Tags), fun encode_tag/1)}])
    end)).

-file("src/lattice_sets/or_set.gleam", 455).
-spec from_json(binary()) -> {ok, o_r_set(binary())} | {error, gleam@json:decode_error()}.
-doc(~" Decode an `ORSet(String)` from a JSON string produced by `to_json`.

 Supports both v1 (no pruned field) and v2 formats. Returns `Error` if the
 string is not valid JSON or does not match the expected format.").
from_json(Json_string) ->
    Tag_decoder = begin
        gleam@dynamic@decode:field(~"r", lattice_core@replica_id:decoder(), fun(R) ->
            gleam@dynamic@decode:field(~"c", {decoder, fun gleam@dynamic@decode:decode_int/1}, fun(C) ->
                gleam@dynamic@decode:success({tag, R, C})
            end)
        end)
    end,
    Tag_set_decoder = gleam@dynamic@decode:map(gleam@dynamic@decode:list(Tag_decoder), fun gleam@set:from_list/1),
    V1_state_decoder = begin
        gleam@dynamic@decode:field(~"state", begin
            gleam@dynamic@decode:field(~"replica_id", lattice_core@replica_id:decoder(), fun(Replica_id) ->
                gleam@dynamic@decode:field(~"counter", {decoder, fun gleam@dynamic@decode:decode_int/1}, fun(Counter) ->
                    gleam@dynamic@decode:field(~"entries", gleam@dynamic@decode:dict({decoder, fun gleam@dynamic@decode:decode_string/1}, Tag_set_decoder), fun(Entries) ->
                        gleam@dynamic@decode:optional_field(~"tombstones", [], gleam@dynamic@decode:list(Tag_decoder), fun(Tombstones) ->
                            gleam@dynamic@decode:success({o_r_set, Replica_id, Counter, Entries, gleam@set:from_list(Tombstones), lattice_core@version_vector:new()})
                        end)
                    end)
                end)
            end)
        end, fun(State) ->
            gleam@dynamic@decode:success(State)
        end)
    end,
    V2_state_decoder = begin
        gleam@dynamic@decode:field(~"state", begin
            gleam@dynamic@decode:field(~"replica_id", lattice_core@replica_id:decoder(), fun(Replica_id) ->
                gleam@dynamic@decode:field(~"counter", {decoder, fun gleam@dynamic@decode:decode_int/1}, fun(Counter) ->
                    gleam@dynamic@decode:field(~"entries", gleam@dynamic@decode:dict({decoder, fun gleam@dynamic@decode:decode_string/1}, Tag_set_decoder), fun(Entries) ->
                        gleam@dynamic@decode:field(~"tombstones", Tag_set_decoder, fun(Tombstones) ->
                            gleam@dynamic@decode:field(~"pruned", lattice_core@version_vector:decoder(), fun(Pruned) ->
                                gleam@dynamic@decode:success({o_r_set, Replica_id, Counter, Entries, Tombstones, Pruned})
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
            case Type_tag =:= ~"or_set" of
                false ->
                    {error, {unable_to_decode, [{decode_error, ~"type=or_set", Type_tag, []}]}};

                true ->
                    case Version of
                        1 ->
                            gleam@json:parse(Json_string, V1_state_decoder);

                        2 ->
                            gleam@json:parse(Json_string, V2_state_decoder);

                        _ ->
                            {error, {unable_to_decode, [{decode_error, ~"v=1 or v=2", erlang:integer_to_binary(Version), [~"v"]}]}}
                    end
            end
    end.

-file("src/lattice_sets/or_set.gleam", 563).
-spec from_json_with(binary(), gleam@dynamic@decode:decoder(DYF)) -> {ok, o_r_set(DYF)} | {error, gleam@json:decode_error()}.
-doc(~" Decode generic elements and all causal metadata from a v3 envelope.

 Rejects non-positive tags, repeated elements or live tags, and tags that
 are both live and tombstoned. The allocation counter is raised when
 retained tags or pruned clocks prove that higher counters were used.
 This prevents ID reuse after loading or rebinding a snapshot.
 Use String `from_json` to read legacy v1/v2 object-key envelopes.

 ## Examples

 ```gleam
 let set = or_set.new(replica_id.new(\"A\")) |> or_set.add(42)
 let encoded = or_set.to_json_with(set, json.int) |> json.to_string
 or_set.from_json_with(encoded, decode.int)  // -> Ok(set)
 ```").
from_json_with(Json_string, Decoder) ->
    Tag_decoder = begin
        gleam@dynamic@decode:field(~"r", lattice_core@replica_id:decoder(), fun(R) ->
            gleam@dynamic@decode:field(~"c", {decoder, fun gleam@dynamic@decode:decode_int/1}, fun(C) ->
                Tag = {tag, R, C},
                case C > 0 of
                    true ->
                        gleam@dynamic@decode:success(Tag);

                    false ->
                        gleam@dynamic@decode:failure(Tag, ~"a positive tag counter")
                end
            end)
        end)
    end,
    Entry_decoder = begin
        gleam@dynamic@decode:field(~"value", Decoder, fun(Value) ->
            gleam@dynamic@decode:field(~"tags", gleam@dynamic@decode:list(Tag_decoder), fun(Tags) ->
                gleam@dynamic@decode:success({Value, Tags})
            end)
        end)
    end,
    Envelope_decoder = begin
        gleam@dynamic@decode:field(~"type", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(Type_tag) ->
            gleam@dynamic@decode:field(~"v", {decoder, fun gleam@dynamic@decode:decode_int/1}, fun(Version) ->
                case (Type_tag =:= ~"or_set") andalso (Version =:= 3) of
                    false ->
                        gleam@dynamic@decode:failure(nil, ~"type=or_set and v=3");

                    true ->
                        gleam@dynamic@decode:success(nil)
                end
            end)
        end)
    end,
    gleam@result:'try'(gleam@json:parse(Json_string, Envelope_decoder), fun(_) ->
        gleam@json:parse(Json_string, begin
            gleam@dynamic@decode:field(~"state", begin
                gleam@dynamic@decode:field(~"replica_id", lattice_core@replica_id:decoder(), fun(Rid) ->
                    gleam@dynamic@decode:field(~"counter", {decoder, fun gleam@dynamic@decode:decode_int/1}, fun(Counter) ->
                        gleam@dynamic@decode:field(~"entries", gleam@dynamic@decode:list(Entry_decoder), fun(Entries_list) ->
                            gleam@dynamic@decode:field(~"tombstones", gleam@dynamic@decode:list(Tag_decoder), fun(Tombstone_list) ->
                                gleam@dynamic@decode:field(~"pruned", begin
                                    gleam@dynamic@decode:field(~"type", {decoder, fun gleam@dynamic@decode:decode_string/1}, fun(Type_tag) ->
                                        gleam@dynamic@decode:field(~"v", {decoder, fun gleam@dynamic@decode:decode_int/1}, fun(Version) ->
                                            case (Type_tag =:= ~"version_vector") andalso (Version =:= 1) of
                                                true ->
                                                    lattice_core@version_vector:decoder();

                                                false ->
                                                    gleam@dynamic@decode:failure(lattice_core@version_vector:new(), ~"type=version_vector and v=1")
                                            end
                                        end)
                                    end)
                                end, fun(Pruned) ->
                                    Live_tags = gleam@list:flat_map(Entries_list, fun(Entry) ->
                                        erlang:element(2, Entry)
                                    end),
                                    Tombstones = gleam@set:from_list(Tombstone_list),
                                    Entries = begin
                                        _pipe = Entries_list,
                                        _pipe@1 = gleam@list:map(_pipe, fun(Entry) ->
                                            {erlang:element(1, Entry), gleam@set:from_list(erlang:element(2, Entry))}
                                        end),
                                        maps:from_list(_pipe@1)
                                    end,
                                    Clocks = begin
                                        _pipe@2 = lattice_core@version_vector:to_dict(Pruned),
                                        maps:values(_pipe@2)
                                    end,
                                    Allocated = gleam@list:fold(lists:append(Live_tags, Tombstone_list), Counter, fun(Max, Tag) ->
                                        gleam@int:max(Max, erlang:element(3, Tag))
                                    end),
                                    State = {o_r_set, Rid, counter_with_pruned_floor(Allocated, Pruned), Entries, Tombstones, Pruned},
                                    Valid = (((((Counter >= 0) andalso gleam@list:all(Clocks, fun(Clock) ->
                                        Clock >= 0
                                    end)) andalso (maps:size(Entries) =:= erlang:length(Entries_list))) andalso gleam@list:all(Entries_list, fun(Entry) ->
                                        not gleam@list:is_empty(erlang:element(2, Entry))
                                    end)) andalso (gleam@set:size(gleam@set:from_list(Live_tags)) =:= erlang:length(Live_tags))) andalso gleam@list:all(Live_tags, fun(Tag) ->
                                        not gleam@set:contains(Tombstones, Tag)
                                    end),
                                    case Valid of
                                        true ->
                                            gleam@dynamic@decode:success(State);

                                        false ->
                                            gleam@dynamic@decode:failure(State, ~"non-negative clocks, unique non-empty entries, and disjoint live and removed tags")
                                    end
                                end)
                            end)
                        end)
                    end)
                end)
            end, fun(State) ->
                gleam@dynamic@decode:success(State)
            end)
        end)
    end).

