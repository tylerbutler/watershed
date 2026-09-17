import gleam/dict
import gleam/json
import gleam/list
import gleam/set
import gleam/string
import lattice_core/replica_id
import lattice_core/version_vector
import lattice_maps/crdt
import lattice_maps/or_map
import lattice_sets/or_set
import startest/expect
import watershed/or_map_set_leaf as leaf_adapter

fn new_map(author: String) -> or_map.ORMap(String) {
  or_map.new(replica_id.new(author), crdt.OrSetSpec)
}

fn add(
  map: or_map.ORMap(String),
  author: String,
  key: String,
  member: String,
) -> #(or_map.ORMap(String), or_map.ORMapDelta(String)) {
  let assert Ok(#(delta, _)) =
    leaf_adapter.add(
      map,
      leaf_adapter.new_clocks(),
      replica_id.new(author),
      key,
      member,
    )
  let assert Ok(applied) = leaf_adapter.apply_delta(map, delta)
  #(applied, delta)
}

fn remove_key(
  map: or_map.ORMap(String),
  author: String,
  key: String,
) -> #(or_map.ORMap(String), or_map.ORMapDelta(String)) {
  let assert Ok(#(delta, _)) =
    leaf_adapter.remove_key(
      map,
      leaf_adapter.new_clocks(),
      replica_id.new(author),
      key,
    )
  let assert Ok(applied) = leaf_adapter.apply_delta(map, delta)
  #(applied, delta)
}

fn expect_members(
  map: or_map.ORMap(String),
  key: String,
  members: List(String),
) -> Nil {
  let assert Ok(crdt.CrdtOrSet(leaf)) = or_map.get(map, key)
  or_set.value(leaf) |> expect.to_equal(set.from_list(members))
}

fn permutations(items: List(a)) -> List(List(a)) {
  case items {
    [] -> [[]]
    _ ->
      items
      |> list.index_map(fn(item, index) {
        let rest =
          list.append(list.take(items, index), list.drop(items, index + 1))
        permutations(rest) |> list.map(fn(tail) { [item, ..tail] })
      })
      |> list.flatten
  }
}

fn expect_deliveries(
  initial: or_map.ORMap(String),
  deltas: List(or_map.ORMapDelta(String)),
  check: fn(or_map.ORMap(String)) -> Nil,
) -> Nil {
  list.each(permutations(deltas), fn(order) {
    let assert Ok(applied) =
      list.try_fold(order, initial, leaf_adapter.apply_delta)
    check(applied)
    let assert Ok(replayed) =
      list.try_fold(order, applied, leaf_adapter.apply_delta)
    replayed |> expect.to_equal(applied)
    let assert Ok(batch) =
      list.try_fold(order, or_map.empty_delta(initial), or_map.merge_deltas)
    let assert Ok(batched) = leaf_adapter.apply_delta(initial, batch)
    check(batched)
  })
}

pub fn native_set_state_and_delta_round_trip_test() -> Nil {
  let #(map, delta) = add(new_map("a"), "a", "doc", "draft")
  expect_members(map, "doc", ["draft"])
  leaf_adapter.decode_state(or_map.to_json(map) |> json.to_string)
  |> expect.to_equal(Ok(map))
  leaf_adapter.decode_delta(or_map.delta_to_json(delta) |> json.to_string)
  |> expect.to_equal(Ok(delta))
  leaf_adapter.validate_state(map) |> expect.to_equal(Ok(Nil))
  leaf_adapter.validate_intent(delta, "doc", leaf_adapter.AddMember("draft"))
  |> expect.to_equal(Ok(Nil))
  let assert Error(leaf_adapter.InvalidState(_)) =
    leaf_adapter.validate_intent(
      delta,
      "other",
      leaf_adapter.AddMember("draft"),
    )
  let assert Error(leaf_adapter.InvalidState(_)) =
    leaf_adapter.validate_intent(
      delta,
      "doc",
      leaf_adapter.RemoveMember("draft"),
    )
  Nil
}

pub fn composite_remove_readd_and_stale_replay_converge_test() -> Nil {
  let #(added, old_delta) = add(new_map("a"), "a", "doc", "old")
  let #(removed, remove_delta) = remove_key(added, "a", "doc")
  or_map.get(removed, "doc") |> expect.to_equal(Error(Nil))
  leaf_adapter.validate_intent(remove_delta, "doc", leaf_adapter.RemoveKey)
  |> expect.to_equal(Ok(Nil))
  let #(readded, new_delta) = add(removed, "a", "doc", "new")
  expect_deliveries(
    new_map("observer"),
    [old_delta, remove_delta, new_delta],
    fn(map) { expect_members(map, "doc", ["new"]) },
  )
  list.each([#(removed, readded), #(readded, removed)], fn(pair) {
    let assert Ok(merged) = leaf_adapter.merge(pair.0, pair.1)
    expect_members(merged, "doc", ["new"])
  })
}

pub fn concurrent_member_add_survives_observed_key_removal_test() -> Nil {
  let #(added, old_delta) = add(new_map("a"), "a", "doc", "old")
  let #(_, remove_delta) = remove_key(added, "a", "doc")
  let #(_, concurrent_delta) = add(added, "b", "doc", "concurrent")
  expect_deliveries(
    new_map("observer"),
    [old_delta, remove_delta, concurrent_delta],
    fn(map) { expect_members(map, "doc", ["concurrent"]) },
  )
}

pub fn independent_concurrent_member_adds_form_union_test() -> Nil {
  let #(a, da) = add(new_map("a"), "a", "doc", "first")
  let #(b, db) = add(new_map("b"), "b", "doc", "second")
  expect_deliveries(new_map("observer"), [da, db], fn(map) {
    expect_members(map, "doc", ["first", "second"])
  })
  let assert Ok(merged) = leaf_adapter.merge(a, b)
  expect_members(merged, "doc", ["first", "second"])
}

pub fn member_remove_and_fresh_add_preserve_unobserved_tag_test() -> Nil {
  let #(added, old_delta) = add(new_map("a"), "a", "doc", "member")
  let assert Ok(#(remove_delta, _)) =
    leaf_adapter.remove_member(
      added,
      leaf_adapter.new_clocks(),
      replica_id.new("a"),
      "doc",
      "member",
    )
  leaf_adapter.validate_intent(
    remove_delta,
    "doc",
    leaf_adapter.RemoveMember("member"),
  )
  |> expect.to_equal(Ok(Nil))
  let #(_, add_delta) = add(added, "b", "doc", "member")
  expect_deliveries(
    new_map("observer"),
    [old_delta, remove_delta, add_delta],
    fn(map) { expect_members(map, "doc", ["member"]) },
  )
  let assert Ok(removed) = leaf_adapter.apply_delta(added, remove_delta)
  expect_members(removed, "doc", [])
}

pub fn independent_keys_and_full_merges_are_associative_test() -> Nil {
  let #(a, da) = add(new_map("a"), "a", "left", "old")
  let #(b, db) = remove_key(a, "a", "left")
  let #(c, dc) = add(b, "b", "left", "new")
  let #(d, dd) = add(new_map("c"), "c", "right", "kept")
  expect_deliveries(new_map("observer"), [da, db, dc, dd], fn(map) {
    expect_members(map, "left", ["new"])
    expect_members(map, "right", ["kept"])
  })
  list.each(permutations([a, b, c, d]), fn(order) {
    let assert Ok(merged) =
      list.try_fold(order, new_map("observer"), leaf_adapter.merge)
    expect_members(merged, "left", ["new"])
    expect_members(merged, "right", ["kept"])
    let assert [first, second, third, fourth] = order
    let assert Ok(left) = leaf_adapter.merge(first, second)
    let assert Ok(right) = leaf_adapter.merge(third, fourth)
    let assert Ok(grouped) = leaf_adapter.merge(left, right)
    let assert Ok(grouped) = leaf_adapter.merge(new_map("observer"), grouped)
    grouped |> expect.to_equal(merged)
  })
}

pub fn counter_only_checkpoint_discards_abandoned_members_test() -> Nil {
  let empty = new_map("a")
  let clocks = leaf_adapter.Clocks(40, dict.new())
  let assert Ok(#(abandoned, clocks)) =
    leaf_adapter.add(empty, clocks, replica_id.new("a"), "doc", "abandoned")
  clocks.key_counter |> expect.to_equal(41)
  let assert Ok(checkpoint) =
    leaf_adapter.retain_counter_floor(empty, clocks, replica_id.new("a"))
  or_map.keys(checkpoint) |> expect.to_equal([])
  let assert Ok(restored) =
    leaf_adapter.decode_state(or_map.to_json(checkpoint) |> json.to_string)
  list.each(["doc", "unseen"], fn(key) {
    let assert Ok(#(fresh, clocks)) =
      leaf_adapter.add(
        restored,
        leaf_adapter.new_clocks(),
        replica_id.new("a"),
        key,
        "fresh",
      )
    clocks.key_counter |> expect.to_equal(42)
    let assert Ok(applied) = leaf_adapter.apply_delta(restored, fresh)
    expect_members(applied, key, ["fresh"])
    // Removing the abandoned tag must not remove the fresh membership or value.
    let assert Ok(abandoned_map) = leaf_adapter.apply_delta(empty, abandoned)
    let #(_, removed) = or_map.remove_with_delta(abandoned_map, "doc")
    let assert Ok(applied) = leaf_adapter.apply_delta(applied, removed)
    expect_members(applied, key, ["fresh"])
  })
}

pub fn checkpoint_preserves_confirmed_members_and_receiver_identity_test() -> Nil {
  let #(confirmed, _) = add(new_map("a"), "a", "doc", "kept")
  let assert Ok(#(_, clocks)) =
    leaf_adapter.add(
      confirmed,
      leaf_adapter.Clocks(7, dict.new()),
      replica_id.new("b"),
      "doc",
      "abandoned",
    )
  let assert Ok(checkpoint) =
    leaf_adapter.retain_counter_floor(confirmed, clocks, replica_id.new("b"))
  or_map.replica_id(checkpoint) |> expect.to_equal(replica_id.new("b"))
  let #(fresh, _) = add(checkpoint, "b", "doc", "new")
  expect_members(fresh, "doc", ["kept", "new"])
  let assert Ok(observed) =
    leaf_adapter.observe_state(leaf_adapter.new_clocks(), fresh)
  observed.key_counter |> expect.to_equal(9)
}

pub fn imported_inactive_leaf_is_cleared_before_readd_test() -> Nil {
  let #(added, _) = add(new_map("a"), "a", "doc", "old")
  let removed = or_map.remove(added, "doc")
  let assert Ok(imported) =
    leaf_adapter.decode_state(or_map.to_json(removed) |> json.to_string)
  let #(readded, delta) = add(imported, "b", "doc", "new")
  expect_members(readded, "doc", ["new"])
  let assert Ok(replayed) = leaf_adapter.apply_delta(readded, delta)
  replayed |> expect.to_equal(readded)
}

pub fn adapter_propagates_native_schema_errors_test() -> Nil {
  let set_map = new_map("a")
  let counter_map = or_map.new(replica_id.new("b"), crdt.GCounterSpec)
  let assert Error(leaf_adapter.InvalidState(_)) =
    leaf_adapter.merge(set_map, counter_map)
  let assert Error(leaf_adapter.InvalidState(_)) =
    leaf_adapter.apply_delta(set_map, or_map.empty_delta(counter_map))
  let assert Error(leaf_adapter.InvalidState(_)) =
    leaf_adapter.validate_state(counter_map)
  Nil
}

fn strict_leaf_json(
  counter: Int,
  entries: List(#(String, List(#(String, Int)))),
  tombstones: List(#(String, Int)),
  pruned: json.Json,
) -> json.Json {
  let tag = fn(dot: #(String, Int)) {
    json.object([#("r", json.string(dot.0)), #("c", json.int(dot.1))])
  }
  json.object([
    #("type", json.string("or_set")),
    #("v", json.int(2)),
    #(
      "state",
      json.object([
        #("replica_id", json.string("a")),
        #("counter", json.int(counter)),
        #(
          "entries",
          json.object(
            list.map(entries, fn(pair) { #(pair.0, json.array(pair.1, tag)) }),
          ),
        ),
        #("tombstones", json.array(tombstones, tag)),
        #("pruned", pruned),
      ]),
    ),
  ])
}

fn legacy_map_json(
  keys: json.Json,
  leaves: List(#(String, json.Json)),
  bounds: json.Json,
) -> String {
  json.object([
    #("type", json.string("or_map")),
    #("v", json.int(2)),
    #(
      "state",
      json.object([
        #("replica_id", json.string("a")),
        #("crdt_spec", json.string("or_set")),
        #("key_set", json.string(json.to_string(keys))),
        #(
          "values",
          json.array(leaves, fn(pair) {
            json.object([
              #("key", json.string(pair.0)),
              #("crdt", json.string(json.to_string(pair.1))),
            ])
          }),
        ),
        #("remove_bounds", bounds),
      ]),
    ),
  ])
  |> json.to_string
}

pub fn legacy_baselines_import_but_old_deltas_are_rejected_test() -> Nil {
  let keys =
    or_set.new(replica_id.new("a")) |> or_set.add("doc") |> or_set.to_json
  let leaf =
    or_set.new(replica_id.new("a")) |> or_set.add("draft") |> or_set.to_json
  let source = legacy_map_json(keys, [#("doc", leaf)], json.object([]))
  list.each([source, string.replace(source, "\"v\":2", "\"v\":1")], fn(encoded) {
    let assert Ok(map) = leaf_adapter.decode_state(encoded)
    expect_members(map, "doc", ["draft"])
    let #(map, _) = add(map, "b", "doc", "reviewed")
    expect_members(map, "doc", ["draft", "reviewed"])
  })
  let assert Error(leaf_adapter.InvalidState(_)) =
    leaf_adapter.decode_delta(
      "{\"type\":\"or_map_delta\",\"v\":1,\"state\":{}}",
    )
  Nil
}

pub fn legacy_multikey_memberships_remain_independent_test() -> Nil {
  let keys =
    or_set.new(replica_id.new("a"))
    |> or_set.add("left")
    |> or_set.add("right")
    |> or_set.to_json
  let leaf =
    or_set.new(replica_id.new("a")) |> or_set.add("kept") |> or_set.to_json
  let source =
    legacy_map_json(keys, [#("left", leaf), #("right", leaf)], json.object([]))
  let assert Ok(map) = leaf_adapter.decode_state(source)
  let assert Ok(#(delta, _)) =
    leaf_adapter.remove_member(
      map,
      leaf_adapter.new_clocks(),
      replica_id.new("b"),
      "left",
      "kept",
    )
  let assert Ok(removed) = leaf_adapter.apply_delta(map, delta)
  expect_members(removed, "left", [])
  expect_members(removed, "right", ["kept"])
}

pub fn modern_pruning_is_preserved_by_merge_but_rejected_by_validation_test() -> Nil {
  let stable =
    version_vector.new() |> version_vector.increment(replica_id.new("a"))
  let leaf =
    or_set.new(replica_id.new("a"))
    |> or_set.add("old")
    |> or_set.remove("old")
    |> or_set.prune(stable)
  let assert Ok(map) =
    or_map.update(new_map("a"), "doc", fn(_) { crdt.CrdtOrSet(leaf) })
  let assert Error(leaf_adapter.InvalidState(_)) =
    leaf_adapter.decode_state(or_map.to_json(map) |> json.to_string)
  let assert Error(leaf_adapter.InvalidState(_)) =
    leaf_adapter.validate_state(map)
  leaf_adapter.apply_delta(map, or_map.empty_delta(map))
  |> expect.to_equal(Ok(map))
  leaf_adapter.merge(map, map) |> expect.to_equal(Ok(map))
}

pub fn concurrent_member_removals_leave_a_present_empty_key_test() -> Nil {
  let #(map, _) = add(new_map("a"), "a", "doc", "first")
  let #(map, _) = add(map, "a", "doc", "second")
  let assert Ok(#(first, _)) =
    leaf_adapter.remove_member(
      map,
      leaf_adapter.new_clocks(),
      replica_id.new("a"),
      "doc",
      "first",
    )
  let assert Ok(#(second, _)) =
    leaf_adapter.remove_member(
      map,
      leaf_adapter.new_clocks(),
      replica_id.new("b"),
      "doc",
      "second",
    )
  expect_deliveries(map, [first, second], fn(map) {
    expect_members(map, "doc", [])
  })
}

pub fn strict_decoder_rejects_invalid_live_and_retained_leaves_test() -> Nil {
  let empty_vector = version_vector.to_json(version_vector.new())
  let invalid = [
    strict_leaf_json(-1, [], [], empty_vector),
    strict_leaf_json(9_007_199_254_740_991 + 1, [], [], empty_vector),
    strict_leaf_json(1, [#("draft", [#("a", 0)])], [], empty_vector),
    strict_leaf_json(1, [#("draft", [#("a", 2)])], [], empty_vector),
    strict_leaf_json(0, [], [#("a", 1)], empty_vector),
    strict_leaf_json(
      1,
      [#("draft", [#("a", 1)]), #("reviewed", [#("a", 1)])],
      [],
      empty_vector,
    ),
    strict_leaf_json(1, [#("draft", [#("a", 1)])], [#("a", 1)], empty_vector),
    strict_leaf_json(1, [#("draft", [])], [], empty_vector),
    strict_leaf_json(
      1,
      [],
      [],
      version_vector.new()
        |> version_vector.increment(replica_id.new("a"))
        |> version_vector.to_json,
    ),
  ]
  let active =
    or_set.new(replica_id.new("a")) |> or_set.add("doc") |> or_set.to_json
  let inactive = strict_leaf_json(1, [], [], empty_vector)
  list.each([active, inactive], fn(keys) {
    list.each(invalid, fn(leaf) {
      let assert Error(leaf_adapter.InvalidState(_)) =
        leaf_adapter.decode_state(legacy_map_json(
          keys,
          [#("doc", leaf)],
          json.object([]),
        ))
    })
  })
}

pub fn strict_decoder_rejects_duplicate_missing_and_invalid_metadata_test() -> Nil {
  let keys =
    or_set.new(replica_id.new("a")) |> or_set.add("doc") |> or_set.to_json
  let member =
    or_set.new(replica_id.new("a")) |> or_set.add("draft") |> or_set.to_json
  list.each(
    [
      legacy_map_json(
        keys,
        [#("doc", member), #("doc", member)],
        json.object([]),
      ),
      legacy_map_json(keys, [], json.object([])),
      legacy_map_json(
        keys,
        [#("doc", member)],
        json.object([
          #(
            "doc",
            version_vector.from_dict(
              dict.from_list([#(replica_id.new("a"), -1)]),
            )
              |> version_vector.to_json,
          ),
        ]),
      ),
    ],
    fn(encoded) {
      let assert Error(leaf_adapter.InvalidState(_)) =
        leaf_adapter.decode_state(encoded)
    },
  )
  let #(map, _) = add(new_map("a"), "a", "doc", "draft")
  let encoded = or_map.to_json(map) |> json.to_string
  list.each(
    [
      string.replace(encoded, "\"clock\":1", "\"clock\":-1"),
      string.replace(encoded, "\"v\":3", "\"v\":4"),
      string.replace(
        encoded,
        "\"type\":\"or_map\"",
        "\"type\":\"or_map_delta\"",
      ),
    ],
    fn(invalid) {
      let assert Error(leaf_adapter.InvalidState(_)) =
        leaf_adapter.decode_state(invalid)
    },
  )
}

pub fn exhaustion_precedes_native_increment_and_absent_removals_are_noops_test() -> Nil {
  let limit = 9_007_199_254_740_991
  let assert Ok(#(delta, clocks)) =
    leaf_adapter.add(
      new_map("a"),
      leaf_adapter.Clocks(limit - 1, dict.new()),
      replica_id.new("a"),
      "doc",
      "last",
    )
  let assert Ok(map) = leaf_adapter.apply_delta(new_map("a"), delta)
  list.each(
    [
      leaf_adapter.add(map, clocks, replica_id.new("a"), "doc", "next"),
      leaf_adapter.remove_member(
        map,
        clocks,
        replica_id.new("a"),
        "doc",
        "last",
      ),
      leaf_adapter.remove_key(map, clocks, replica_id.new("a"), "doc"),
    ],
    fn(outcome) {
      let assert Error(leaf_adapter.CounterExhausted(_)) = outcome
    },
  )
  leaf_adapter.remove_member(map, clocks, replica_id.new("a"), "doc", "absent")
  |> expect.to_equal(Ok(#(or_map.empty_delta(map), clocks)))
  leaf_adapter.remove_key(map, clocks, replica_id.new("a"), "absent")
  |> expect.to_equal(Ok(#(or_map.empty_delta(map), clocks)))
}
