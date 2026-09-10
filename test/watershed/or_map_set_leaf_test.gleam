import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/set
import gleam/string
import lattice_core/replica_id
import lattice_core/version_vector
import lattice_maps/crdt
import lattice_maps/or_map
import lattice_sets/or_set
import startest/expect
import watershed/or_map_set_leaf as leaf_adapter

type NativeError {
  DecodeFailed(json.DecodeError)
  MergeFailed(crdt.MergeError)
  AdapterFailed(leaf_adapter.LeafError)
}

type SetMetadata {
  SetMetadata(
    author: String,
    counter: Int,
    entries: dict.Dict(String, set.Set(#(String, Int))),
    tombstones: set.Set(#(String, Int)),
    pruned: version_vector.VersionVector,
  )
}

type MapSnapshot {
  MapSnapshot(
    author: String,
    spec: String,
    key_set: or_set.ORSet(String),
    leaves: dict.Dict(String, or_set.ORSet(String)),
    remove_bounds: dict.Dict(String, version_vector.VersionVector),
  )
}

type CausalSet {
  CausalSet(
    entries: dict.Dict(String, set.Set(#(String, Int))),
    tombstones: set.Set(#(String, Int)),
    pruned: version_vector.VersionVector,
  )
}

type CausalMap {
  CausalMap(
    spec: String,
    key_set: CausalSet,
    leaves: dict.Dict(String, CausalSet),
    remove_bounds: dict.Dict(String, version_vector.VersionVector),
  )
}

fn new_map(author: String) -> or_map.ORMap {
  or_map.new(replica_id.new(author), crdt.OrSetSpec)
}

fn new_leaf(author: String) -> or_set.ORSet(String) {
  or_set.new(replica_id.new(author))
}

fn set_metadata(
  leaf: or_set.ORSet(String),
) -> Result(SetMetadata, json.DecodeError) {
  let tag = {
    use author <- decode.field("r", decode.string)
    use counter <- decode.field("c", decode.int)
    decode.success(#(author, counter))
  }
  let tags = decode.map(decode.list(tag), set.from_list)
  let decoder = {
    use metadata <- decode.field("state", {
      use author <- decode.field("replica_id", decode.string)
      use counter <- decode.field("counter", decode.int)
      use entries <- decode.field("entries", decode.dict(decode.string, tags))
      use tombstones <- decode.field("tombstones", tags)
      use pruned <- decode.field("pruned", version_vector.decoder())
      decode.success(SetMetadata(author, counter, entries, tombstones, pruned))
    })
    decode.success(metadata)
  }
  json.parse(or_set.to_json(leaf) |> json.to_string, decoder)
}

fn map_snapshot(map: or_map.ORMap) -> Result(MapSnapshot, json.DecodeError) {
  let value_decoder = {
    use key <- decode.field("key", decode.string)
    use leaf <- decode.field("crdt", decode.string)
    decode.success(#(key, leaf))
  }
  let decoder = {
    use snapshot <- decode.field("state", {
      use author <- decode.field("replica_id", decode.string)
      use spec <- decode.field("crdt_spec", decode.string)
      use key_set <- decode.field("key_set", decode.string)
      use leaves <- decode.field("values", decode.list(value_decoder))
      use bounds <- decode.field(
        "remove_bounds",
        decode.dict(decode.string, version_vector.decoder()),
      )
      decode.success(#(author, spec, key_set, leaves, bounds))
    })
    decode.success(snapshot)
  }
  use #(author, spec, key_set, leaves, bounds) <- result.try(json.parse(
    or_map.to_json(map) |> json.to_string,
    decoder,
  ))
  use key_set <- result.try(or_set.from_json(key_set))
  use leaves <- result.try(
    list.try_map(leaves, fn(pair) {
      use leaf <- result.try(or_set.from_json(pair.1))
      Ok(#(pair.0, leaf))
    }),
  )
  Ok(MapSnapshot(author, spec, key_set, dict.from_list(leaves), bounds))
}

fn causal_set(
  leaf: or_set.ORSet(String),
) -> Result(CausalSet, json.DecodeError) {
  use metadata <- result.try(set_metadata(leaf))
  Ok(CausalSet(metadata.entries, metadata.tombstones, metadata.pruned))
}

// Exclude only local authoring cursors. Keep inactive leaves and removal bounds.
fn causal_map(map: or_map.ORMap) -> Result(CausalMap, json.DecodeError) {
  use snapshot <- result.try(map_snapshot(map))
  use key_set <- result.try(causal_set(snapshot.key_set))
  use leaves <- result.try(
    snapshot.leaves
    |> dict.to_list
    |> list.try_map(fn(pair) {
      use leaf <- result.try(causal_set(pair.1))
      Ok(#(pair.0, leaf))
    }),
  )
  Ok(CausalMap(
    snapshot.spec,
    key_set,
    dict.from_list(leaves),
    snapshot.remove_bounds,
  ))
}

fn expect_same_causality(actual: or_map.ORMap, expected: or_map.ORMap) -> Nil {
  let assert Ok(actual) = causal_map(actual)
  let assert Ok(expected) = causal_map(expected)
  actual |> expect.to_equal(expected)
}

fn expect_members(
  map: or_map.ORMap,
  key: String,
  members: List(String),
) -> Nil {
  let assert Ok(crdt.CrdtOrSet(leaf)) = or_map.get(map, key)
  or_set.value(leaf) |> expect.to_equal(set.from_list(members))
}

fn counter_seed_json(author: String, counter: Int) -> json.Json {
  json.object([
    #("type", json.string("or_set")),
    #("v", json.int(2)),
    #(
      "state",
      json.object([
        #("replica_id", json.string(author)),
        #("counter", json.int(counter)),
        #("entries", json.object([])),
        #("tombstones", json.array([], json.string)),
        #("pruned", version_vector.to_json(version_vector.new())),
      ]),
    ),
  ])
}

fn leaf_seed(
  author: String,
  counter: Int,
) -> Result(or_set.ORSet(String), json.DecodeError) {
  counter_seed_json(author, counter) |> json.to_string |> or_set.from_json
}

fn map_seed(
  author: String,
  counter: Int,
) -> Result(or_map.ORMap, json.DecodeError) {
  json.object([
    #("type", json.string("or_map")),
    #("v", json.int(2)),
    #(
      "state",
      json.object([
        #("replica_id", json.string(author)),
        #("crdt_spec", json.string("or_set")),
        #(
          "key_set",
          json.string(counter_seed_json(author, counter) |> json.to_string),
        ),
        #("values", json.array([], json.string)),
        #("remove_bounds", json.object([])),
      ]),
    ),
  ])
  |> json.to_string
  |> or_map.from_json
}

fn update_leaf(
  map: or_map.ORMap,
  key: String,
  leaf: or_set.ORSet(String),
) -> Result(#(or_map.ORMap, or_map.ORMapDelta), NativeError) {
  use #(_, delta) <- result.try(
    or_map.update_with_delta(map, key, fn(_) { crdt.CrdtOrSet(leaf) })
    |> result.map_error(MergeFailed),
  )
  use applied <- result.try(
    leaf_adapter.apply_delta(map, delta) |> result.map_error(AdapterFailed),
  )
  Ok(#(applied, delta))
}

// The caller supplies observed history, never an abandoned optimistic leaf.
fn add_member(
  map: or_map.ORMap,
  author: String,
  key: String,
  observed: or_set.ORSet(String),
  floor: Int,
  member: String,
) -> Result(#(or_map.ORMap, or_map.ORMapDelta), NativeError) {
  use outer_seed <- result.try(
    map_seed(author, floor) |> result.map_error(DecodeFailed),
  )
  use inner_seed <- result.try(
    leaf_seed(author, floor) |> result.map_error(DecodeFailed),
  )
  use working <- result.try(
    leaf_adapter.merge(outer_seed, map) |> result.map_error(AdapterFailed),
  )
  let leaf = or_set.merge(inner_seed, observed) |> or_set.add(member)
  use #(_, delta) <- result.try(
    or_map.update_with_delta(working, key, fn(_) { crdt.CrdtOrSet(leaf) })
    |> result.map_error(MergeFailed),
  )
  use applied <- result.try(
    leaf_adapter.apply_delta(map, delta) |> result.map_error(AdapterFailed),
  )
  Ok(#(applied, delta))
}

fn remove_key(
  map: or_map.ORMap,
  author: String,
  key: String,
  observed: or_set.ORSet(String),
) -> Result(#(or_map.ORMap, or_map.ORMapDelta), NativeError) {
  let cleared =
    or_set.merge(new_leaf(author), observed)
    |> or_set.remove_where(fn(_) { True })
  use #(cleared_map, clear_delta) <- result.try(
    or_map.update_with_delta(map, key, fn(_) { crdt.CrdtOrSet(cleared) })
    |> result.map_error(MergeFailed),
  )
  let #(_, key_delta) = or_map.remove_with_delta(cleared_map, key)
  use delta <- result.try(
    or_map.merge_deltas(clear_delta, key_delta) |> result.map_error(MergeFailed),
  )
  use applied <- result.try(
    leaf_adapter.apply_delta(map, delta) |> result.map_error(AdapterFailed),
  )
  Ok(#(applied, delta))
}

fn deliver(
  initial: or_map.ORMap,
  deltas: List(or_map.ORMapDelta),
) -> Result(or_map.ORMap, leaf_adapter.LeafError) {
  list.try_fold(deltas, initial, leaf_adapter.apply_delta)
}

fn permutations(items: List(a)) -> List(List(a)) {
  case items {
    [] -> [[]]
    _ ->
      list.flat_map(
        list.index_map(items, fn(item, index) { #(item, index) }),
        fn(pair) {
          let rest =
            items
            |> list.index_map(fn(item, index) { #(item, index) })
            |> list.filter(fn(other) { other.1 != pair.1 })
            |> list.map(fn(other) { other.0 })
          permutations(rest) |> list.map(fn(tail) { [pair.0, ..tail] })
        },
      )
  }
}

fn expect_deliveries(
  initial: or_map.ORMap,
  deltas: List(or_map.ORMapDelta),
  expected: or_map.ORMap,
) -> Nil {
  list.each(permutations(deltas), fn(order) {
    let assert Ok(applied) = deliver(initial, order)
    expect_same_causality(applied, expected)
    let assert Ok(replayed) = deliver(applied, list.reverse(order))
    expect_same_causality(replayed, expected)
    let assert Ok(duplicated) =
      deliver(initial, list.flat_map(order, fn(delta) { [delta, delta] }))
    expect_same_causality(duplicated, expected)
    let assert Ok(batch) =
      list.try_fold(order, or_map.empty_delta(initial), or_map.merge_deltas)
    let assert Ok(batched) = leaf_adapter.apply_delta(initial, batch)
    expect_same_causality(batched, expected)
  })
}

fn expect_full_merges(
  left: or_map.ORMap,
  right: or_map.ORMap,
  expected: or_map.ORMap,
) -> Nil {
  let assert Ok(forward) = leaf_adapter.merge(left, right)
  let assert Ok(reverse) = leaf_adapter.merge(right, left)
  expect_same_causality(forward, expected)
  expect_same_causality(reverse, expected)
}

pub fn native_set_spec_and_leaf_delta_round_trips_test() -> Nil {
  let empty = new_map("a")
  let default = crdt.default_crdt(crdt.OrSetSpec, replica_id.new("a"))
  crdt.matches_spec(default, crdt.OrSetSpec) |> expect.to_be_true
  crdt.type_name(default) |> expect.to_equal("or_set")
  let assert Ok(#(replacement, delta)) =
    or_map.update_with_delta(empty, "doc", fn(value) {
      let assert crdt.CrdtOrSet(leaf) = value
      crdt.CrdtOrSet(or_set.add(leaf, "draft"))
    })
  let assert Ok(applied) = leaf_adapter.apply_delta(empty, delta)
  expect_members(applied, "doc", ["draft"])
  applied |> expect.to_equal(replacement)
  let assert Ok(crdt.CrdtOrSet(leaf)) = or_map.get(applied, "doc")
  crdt.to_json(crdt.CrdtOrSet(leaf))
  |> json.to_string
  |> crdt.from_json
  |> expect.to_equal(Ok(crdt.CrdtOrSet(leaf)))
  or_map.to_json(applied)
  |> json.to_string
  |> or_map.from_json
  |> expect.to_equal(Ok(applied))
  or_map.delta_to_json(delta)
  |> json.to_string
  |> or_map.delta_from_json
  |> expect.to_equal(Ok(delta))
  let assert Ok(snapshot) = map_snapshot(applied)
  snapshot.spec |> expect.to_equal("or_set")
}

pub fn native_or_set_add_and_remove_deltas_round_trip_test() -> Nil {
  let empty = new_leaf("a")
  let #(added, add_delta) = or_set.add_with_delta(empty, "old")
  let #(removed, remove_delta) = or_set.remove_with_delta(added, "old")
  list.each([added, add_delta, removed, remove_delta], fn(leaf) {
    leaf
    |> or_set.to_json
    |> json.to_string
    |> or_set.from_json
    |> expect.to_equal(Ok(leaf))
  })
  let assert Ok(expected) = causal_set(removed)
  list.each(permutations([add_delta, remove_delta]), fn(order) {
    let applied = list.fold(order, new_leaf("observer"), or_set.merge)
    or_set.value(applied) |> expect.to_equal(set.new())
    let assert Ok(actual) = causal_set(applied)
    actual |> expect.to_equal(expected)
    let replayed = list.fold(order, applied, or_set.merge)
    replayed |> expect.to_equal(applied)
  })
}

pub fn native_leaf_merge_uses_left_author_and_maximum_counter_test() -> Nil {
  let observed = new_leaf("a") |> or_set.add("old")
  let local = or_set.merge(new_leaf("b"), observed) |> or_set.add("new")
  let assert Ok(metadata) = set_metadata(local)
  metadata.author |> expect.to_equal("b")
  metadata.counter |> expect.to_equal(2)
  metadata.entries
  |> expect.to_equal(
    dict.from_list([
      #("old", set.from_list([#("a", 1)])),
      #("new", set.from_list([#("b", 2)])),
    ]),
  )
  let wrong_order = or_set.merge(observed, new_leaf("b")) |> or_set.add("new")
  let assert Ok(wrong_metadata) = set_metadata(wrong_order)
  dict.get(wrong_metadata.entries, "new")
  |> expect.to_equal(Ok(set.from_list([#("a", 2)])))
  let assert Ok(seed) = leaf_seed("b", 7)
  let seeded = or_set.merge(seed, observed) |> or_set.add("new")
  let assert Ok(seeded_metadata) = set_metadata(seeded)
  dict.get(seeded_metadata.entries, "new")
  |> expect.to_equal(Ok(set.from_list([#("b", 8)])))
}

pub fn upstream_native_inactive_leaf_and_naive_readd_discrepancy_test() -> Nil {
  let assert Ok(#(added, _)) =
    add_member(new_map("a"), "a", "doc", new_leaf("a"), 0, "old")
  let #(removed, _) = or_map.remove_with_delta(added, "doc")
  or_map.get(removed, "doc") |> expect.to_equal(Error(Nil))
  let assert Ok(snapshot) = map_snapshot(removed)
  let assert Ok(retained) = dict.get(snapshot.leaves, "doc")
  or_set.value(retained) |> expect.to_equal(set.from_list(["old"]))
  let assert Ok(bound) = dict.get(snapshot.remove_bounds, "doc")
  version_vector.get(bound, replica_id.new("a")) |> expect.to_equal(1)
  let assert Ok(#(replacement, delta)) =
    or_map.update_with_delta(removed, "doc", fn(value) {
      let assert crdt.CrdtOrSet(fresh) = value
      fresh |> expect.to_equal(new_leaf("a"))
      crdt.CrdtOrSet(or_set.add(fresh, "new"))
    })
  let assert Ok(applied) = or_map.apply_delta(removed, delta)
  expect_members(replacement, "doc", ["new"])
  expect_members(applied, "doc", ["old", "new"])
  let assert Ok(crdt.CrdtOrSet(leaf)) = or_map.get(applied, "doc")
  let assert Ok(metadata) = set_metadata(leaf)
  metadata.entries
  |> expect.to_equal(
    dict.from_list([
      #("old", set.from_list([#("a", 1)])),
      #("new", set.from_list([#("a", 1)])),
    ]),
  )
  let assert Ok(forward) = or_map.merge(removed, replacement)
  let assert Ok(reverse) = or_map.merge(replacement, removed)
  expect_same_causality(forward, applied)
  expect_same_causality(reverse, applied)
}

pub fn counter_only_checkpoint_discards_abandoned_members_test() -> Nil {
  let empty = new_map("a")
  let assert Ok(#(abandoned, _)) =
    add_member(empty, "a", "doc", new_leaf("a"), 6, "abandoned")
  let assert Ok(abandoned_snapshot) = map_snapshot(abandoned)
  let assert Ok(abandoned_keys) = set_metadata(abandoned_snapshot.key_set)
  let assert Ok(abandoned_leaf) = dict.get(abandoned_snapshot.leaves, "doc")
  let assert Ok(abandoned_members) = set_metadata(abandoned_leaf)
  abandoned_keys.counter |> expect.to_equal(7)
  abandoned_members.counter |> expect.to_equal(7)
  let assert Ok(seed) = map_seed("a", 7)
  let assert Ok(checkpoint) = leaf_adapter.merge(seed, empty)
  expect_same_causality(checkpoint, empty)
  let assert Ok(restored) =
    checkpoint |> or_map.to_json |> json.to_string |> or_map.from_json
  let assert Ok(snapshot) = map_snapshot(restored)
  dict.size(snapshot.leaves) |> expect.to_equal(0)
  let assert Ok(key_metadata) = set_metadata(snapshot.key_set)
  key_metadata.counter |> expect.to_equal(7)
  key_metadata.entries |> expect.to_equal(dict.new())
  key_metadata.tombstones |> expect.to_equal(set.new())
  key_metadata.pruned |> expect.to_equal(version_vector.new())
  list.each(["doc", "previously-unseen"], fn(key) {
    let assert Ok(#(fresh, _)) =
      add_member(restored, "a", key, new_leaf("a"), key_metadata.counter, "new")
    expect_members(fresh, key, ["new"])
    let assert Ok(fresh_snapshot) = map_snapshot(fresh)
    let assert Ok(keys) = set_metadata(fresh_snapshot.key_set)
    let assert Ok(leaf) = dict.get(fresh_snapshot.leaves, key)
    let assert Ok(members) = set_metadata(leaf)
    keys.entries
    |> expect.to_equal(
      dict.from_list([
        #(key, set.from_list([#("a", 8)])),
      ]),
    )
    members.entries
    |> expect.to_equal(
      dict.from_list([
        #("new", set.from_list([#("a", 8)])),
      ]),
    )
    keys.counter |> expect.to_equal(8)
    members.counter |> expect.to_equal(8)
  })
}

pub fn counter_only_seed_preserves_confirmed_history_test() -> Nil {
  let assert Ok(#(confirmed, _)) =
    add_member(new_map("a"), "a", "doc", new_leaf("a"), 0, "kept")
  let assert Ok(crdt.CrdtOrSet(leaf)) = or_map.get(confirmed, "doc")
  let assert Ok(#(abandoned, _)) =
    add_member(confirmed, "a", "doc", leaf, 6, "abandoned")
  expect_members(abandoned, "doc", ["kept", "abandoned"])
  let assert Ok(seed) = map_seed("a", 7)
  let assert Ok(checkpoint) = leaf_adapter.merge(seed, confirmed)
  expect_same_causality(checkpoint, confirmed)
  let assert Ok(restored) =
    checkpoint |> or_map.to_json |> json.to_string |> or_map.from_json
  let assert Ok(snapshot) = map_snapshot(restored)
  let assert Ok(leaf) = dict.get(snapshot.leaves, "doc")
  let assert Ok(keys) = set_metadata(snapshot.key_set)
  let assert Ok(#(fresh, _)) =
    add_member(restored, "a", "doc", leaf, keys.counter, "new")
  expect_members(fresh, "doc", ["kept", "new"])
  let assert Ok(crdt.CrdtOrSet(leaf)) = or_map.get(fresh, "doc")
  let assert Ok(metadata) = set_metadata(leaf)
  metadata.entries
  |> expect.to_equal(
    dict.from_list([
      #("kept", set.from_list([#("a", 1)])),
      #("new", set.from_list([#("a", 8)])),
    ]),
  )
}

pub fn composite_remove_clears_observed_tags_and_round_trips_test() -> Nil {
  let assert Ok(#(added, _)) =
    add_member(new_map("a"), "a", "doc", new_leaf("a"), 0, "old")
  let assert Ok(crdt.CrdtOrSet(leaf)) = or_map.get(added, "doc")
  let assert Ok(#(removed, delta)) = remove_key(added, "a", "doc", leaf)
  or_map.get(removed, "doc") |> expect.to_equal(Error(Nil))
  let assert Ok(snapshot) = map_snapshot(removed)
  let assert Ok(keys) = set_metadata(snapshot.key_set)
  let assert Ok(retained) = dict.get(snapshot.leaves, "doc")
  let assert Ok(members) = set_metadata(retained)
  keys.entries |> expect.to_equal(dict.new())
  keys.tombstones |> expect.to_equal(set.from_list([#("a", 1), #("a", 2)]))
  members.entries |> expect.to_equal(dict.new())
  members.tombstones |> expect.to_equal(set.from_list([#("a", 1)]))
  let assert Ok(restored) =
    removed |> or_map.to_json |> json.to_string |> or_map.from_json
  restored |> expect.to_equal(removed)
  let assert Ok(decoded_delta) =
    delta |> or_map.delta_to_json |> json.to_string |> or_map.delta_from_json
  decoded_delta |> expect.to_equal(delta)
  let assert Ok(remote) = leaf_adapter.apply_delta(added, decoded_delta)
  expect_same_causality(remote, removed)
  expect_deliveries(new_map("observer"), [delta], removed)
  expect_full_merges(added, removed, removed)
}

pub fn composite_remove_readd_and_stale_replay_converge_test() -> Nil {
  let empty = new_map("a")
  let assert Ok(#(added, old_delta)) =
    add_member(empty, "a", "doc", new_leaf("a"), 0, "old")
  let assert Ok(crdt.CrdtOrSet(leaf)) = or_map.get(added, "doc")
  let assert Ok(#(removed, remove_delta)) = remove_key(added, "a", "doc", leaf)
  let assert Ok(snapshot) = map_snapshot(removed)
  let assert Ok(retained) = dict.get(snapshot.leaves, "doc")
  let assert Ok(#(readded, new_delta)) =
    add_member(removed, "a", "doc", retained, 2, "new")
  expect_members(readded, "doc", ["new"])
  let assert Ok(crdt.CrdtOrSet(leaf)) = or_map.get(readded, "doc")
  let assert Ok(metadata) = set_metadata(leaf)
  metadata.entries
  |> expect.to_equal(
    dict.from_list([
      #("new", set.from_list([#("a", 3)])),
    ]),
  )
  metadata.tombstones |> expect.to_equal(set.from_list([#("a", 1)]))
  expect_deliveries(
    new_map("observer"),
    [old_delta, remove_delta, new_delta],
    readded,
  )
  expect_full_merges(added, readded, readded)
  expect_full_merges(removed, readded, readded)
}

pub fn concurrent_member_add_survives_observed_key_removal_test() -> Nil {
  let assert Ok(#(first, first_delta)) =
    add_member(new_map("a"), "a", "doc", new_leaf("a"), 0, "old")
  let assert Ok(crdt.CrdtOrSet(first_leaf)) = or_map.get(first, "doc")
  let assert Ok(#(base, second_delta)) =
    add_member(first, "a", "doc", first_leaf, 0, "also-old")
  let assert Ok(crdt.CrdtOrSet(leaf)) = or_map.get(base, "doc")
  let assert Ok(#(removed, remove_delta)) = remove_key(base, "a", "doc", leaf)
  let assert Ok(#(added, add_delta)) =
    add_member(base, "b", "doc", leaf, 0, "new")
  let assert Ok(expected) = leaf_adapter.apply_delta(removed, add_delta)
  expect_members(expected, "doc", ["new"])
  let assert Ok(crdt.CrdtOrSet(leaf)) = or_map.get(expected, "doc")
  let assert Ok(metadata) = set_metadata(leaf)
  metadata.entries
  |> expect.to_equal(
    dict.from_list([
      #("new", set.from_list([#("b", 3)])),
    ]),
  )
  metadata.tombstones |> expect.to_equal(set.from_list([#("a", 1), #("a", 2)]))
  expect_deliveries(
    new_map("observer"),
    [first_delta, second_delta, remove_delta, add_delta],
    expected,
  )
  expect_full_merges(removed, added, expected)
}

pub fn concurrent_adds_use_distinct_local_leaf_tags_test() -> Nil {
  let empty = new_map("observer")
  let assert Ok(#(left, left_delta)) =
    add_member(empty, "a", "doc", new_leaf("a"), 0, "same")
  let assert Ok(#(right, right_delta)) =
    add_member(empty, "b", "doc", new_leaf("b"), 0, "same")
  let assert Ok(expected) = leaf_adapter.apply_delta(left, right_delta)
  expect_members(expected, "doc", ["same"])
  let assert Ok(crdt.CrdtOrSet(leaf)) = or_map.get(expected, "doc")
  let assert Ok(metadata) = set_metadata(leaf)
  metadata.entries
  |> expect.to_equal(
    dict.from_list([
      #("same", set.from_list([#("a", 1), #("b", 1)])),
    ]),
  )
  expect_deliveries(empty, [left_delta, right_delta], expected)
  expect_full_merges(left, right, expected)
}

pub fn independent_concurrent_member_adds_form_union_test() -> Nil {
  let empty = new_map("observer")
  let assert Ok(#(left, left_delta)) =
    add_member(empty, "a", "doc", new_leaf("a"), 0, "draft")
  let assert Ok(#(right, right_delta)) =
    add_member(empty, "b", "doc", new_leaf("b"), 0, "reviewed")
  let assert Ok(expected) = leaf_adapter.apply_delta(left, right_delta)
  expect_members(expected, "doc", ["draft", "reviewed"])
  let assert Ok(crdt.CrdtOrSet(leaf)) = or_map.get(expected, "doc")
  let assert Ok(metadata) = set_metadata(leaf)
  metadata.entries
  |> expect.to_equal(
    dict.from_list([
      #("draft", set.from_list([#("a", 1)])),
      #("reviewed", set.from_list([#("b", 1)])),
    ]),
  )
  expect_deliveries(empty, [left_delta, right_delta], expected)
  expect_full_merges(left, right, expected)
}

pub fn duplicate_visible_add_is_not_duplicate_delta_test() -> Nil {
  let assert Ok(#(first, first_delta)) =
    add_member(new_map("a"), "a", "doc", new_leaf("a"), 0, "same")
  let assert Ok(crdt.CrdtOrSet(leaf)) = or_map.get(first, "doc")
  let assert Ok(#(second, second_delta)) =
    add_member(first, "a", "doc", leaf, 0, "same")
  expect_members(first, "doc", ["same"])
  expect_members(second, "doc", ["same"])
  let assert Ok(first_causal) = causal_map(first)
  let assert Ok(second_causal) = causal_map(second)
  { first_causal == second_causal } |> expect.to_be_false
  let assert Ok(crdt.CrdtOrSet(leaf)) = or_map.get(second, "doc")
  let assert Ok(metadata) = set_metadata(leaf)
  metadata.entries
  |> expect.to_equal(
    dict.from_list([
      #("same", set.from_list([#("a", 1), #("a", 2)])),
    ]),
  )
  expect_deliveries(new_map("observer"), [first_delta, second_delta], second)
}

pub fn concurrent_member_remove_and_fresh_add_preserve_unobserved_tag_test() -> Nil {
  let assert Ok(#(base, original_delta)) =
    add_member(new_map("a"), "a", "doc", new_leaf("a"), 0, "same")
  let assert Ok(crdt.CrdtOrSet(leaf)) = or_map.get(base, "doc")
  let assert Ok(#(removed, remove_delta)) =
    update_leaf(base, "doc", or_set.remove(leaf, "same"))
  let assert Ok(#(added, add_delta)) =
    add_member(base, "b", "doc", leaf, 0, "same")
  let assert Ok(expected) = leaf_adapter.apply_delta(removed, add_delta)
  expect_members(expected, "doc", ["same"])
  let assert Ok(crdt.CrdtOrSet(leaf)) = or_map.get(expected, "doc")
  let assert Ok(metadata) = set_metadata(leaf)
  metadata.entries
  |> expect.to_equal(
    dict.from_list([
      #("same", set.from_list([#("b", 2)])),
    ]),
  )
  metadata.tombstones |> expect.to_equal(set.from_list([#("a", 1)]))
  expect_deliveries(
    new_map("observer"),
    [original_delta, remove_delta, add_delta],
    expected,
  )
  expect_full_merges(removed, added, expected)
}

pub fn independent_concurrent_member_removes_leave_present_empty_key_test() -> Nil {
  let assert Ok(#(first, first_delta)) =
    add_member(new_map("a"), "a", "doc", new_leaf("a"), 0, "one")
  let assert Ok(crdt.CrdtOrSet(leaf)) = or_map.get(first, "doc")
  let assert Ok(#(base, second_delta)) =
    add_member(first, "a", "doc", leaf, 0, "two")
  let assert Ok(crdt.CrdtOrSet(leaf)) = or_map.get(base, "doc")
  let assert Ok(#(left, left_delta)) =
    update_leaf(base, "doc", or_set.remove(leaf, "one"))
  let assert Ok(right_base) = leaf_adapter.merge(new_map("b"), base)
  let right_leaf = or_set.merge(new_leaf("b"), leaf) |> or_set.remove("two")
  let assert Ok(#(right, right_delta)) =
    update_leaf(right_base, "doc", right_leaf)
  let assert Ok(expected) = leaf_adapter.apply_delta(left, right_delta)
  expect_members(expected, "doc", [])
  or_map.keys(expected) |> expect.to_equal(["doc"])
  let assert Ok(crdt.CrdtOrSet(leaf)) = or_map.get(expected, "doc")
  let assert Ok(metadata) = set_metadata(leaf)
  metadata.tombstones |> expect.to_equal(set.from_list([#("a", 1), #("a", 2)]))
  expect_deliveries(
    new_map("observer"),
    [first_delta, second_delta, left_delta, right_delta],
    expected,
  )
  expect_full_merges(left, right, expected)
}

pub fn independent_keys_add_and_remove_converge_test() -> Nil {
  let assert Ok(#(base, original_delta)) =
    add_member(new_map("a"), "a", "old-doc", new_leaf("a"), 0, "old")
  let assert Ok(crdt.CrdtOrSet(leaf)) = or_map.get(base, "old-doc")
  let assert Ok(#(removed, remove_delta)) =
    remove_key(base, "a", "old-doc", leaf)
  let assert Ok(#(added, add_delta)) =
    add_member(base, "b", "new-doc", new_leaf("b"), 0, "new")
  let assert Ok(expected) = leaf_adapter.apply_delta(removed, add_delta)
  or_map.get(expected, "old-doc") |> expect.to_equal(Error(Nil))
  expect_members(expected, "new-doc", ["new"])
  expect_deliveries(
    new_map("observer"),
    [original_delta, remove_delta, add_delta],
    expected,
  )
  expect_full_merges(removed, added, expected)
}

pub fn imported_inactive_live_leaf_is_cleared_before_readd_test() -> Nil {
  let assert Ok(#(added, old_delta)) =
    add_member(new_map("a"), "a", "doc", new_leaf("a"), 0, "old")
  let native_removed = or_map.remove(added, "doc")
  let assert Ok(imported) =
    native_removed |> or_map.to_json |> json.to_string |> or_map.from_json
  imported |> expect.to_equal(native_removed)
  let assert Ok(snapshot) = map_snapshot(imported)
  let assert Ok(retained) = dict.get(snapshot.leaves, "doc")
  or_map.get(imported, "doc") |> expect.to_equal(Error(Nil))
  or_set.value(retained) |> expect.to_equal(set.from_list(["old"]))
  let cleared = or_set.remove_where(retained, fn(_) { True })
  let assert Ok(#(readded, new_delta)) =
    add_member(imported, "b", "doc", cleared, 7, "new")
  expect_members(readded, "doc", ["new"])
  let assert Ok(crdt.CrdtOrSet(leaf)) = or_map.get(readded, "doc")
  let assert Ok(metadata) = set_metadata(leaf)
  metadata.entries
  |> expect.to_equal(
    dict.from_list([
      #("new", set.from_list([#("b", 8)])),
    ]),
  )
  metadata.tombstones |> expect.to_equal(set.from_list([#("a", 1)]))
  expect_deliveries(imported, [old_delta, new_delta], readded)
  expect_full_merges(imported, readded, readded)
}

pub fn upstream_native_removal_subdeltas_have_order_sensitive_bounds_test() -> Nil {
  let assert Ok(#(added, _)) =
    add_member(new_map("a"), "a", "doc", new_leaf("a"), 0, "old")
  let assert Ok(crdt.CrdtOrSet(leaf)) = or_map.get(added, "doc")
  let cleared = or_set.remove_where(leaf, fn(_) { True })
  let assert Ok(#(cleared_map, clear_delta)) =
    or_map.update_with_delta(added, "doc", fn(_) { crdt.CrdtOrSet(cleared) })
  let #(replacement, key_delta) = or_map.remove_with_delta(cleared_map, "doc")
  let assert Ok(composite) = or_map.merge_deltas(clear_delta, key_delta)
  let assert Ok(applied) = or_map.apply_delta(added, composite)
  let assert Ok(forward) =
    list.try_fold([clear_delta, key_delta], added, or_map.apply_delta)
  let assert Ok(reverse) =
    list.try_fold([key_delta, clear_delta], added, or_map.apply_delta)
  expect_same_causality(forward, replacement)
  expect_same_causality(reverse, applied)
  let assert Ok(forward_snapshot) = map_snapshot(forward)
  let assert Ok(applied_snapshot) = map_snapshot(applied)
  let assert Ok(bound) = dict.get(forward_snapshot.remove_bounds, "doc")
  version_vector.get(bound, replica_id.new("a")) |> expect.to_equal(2)
  applied_snapshot.remove_bounds |> expect.to_equal(dict.new())
  or_map.get(forward, "doc") |> expect.to_equal(Error(Nil))
  or_map.get(applied, "doc") |> expect.to_equal(Error(Nil))
}

pub fn imported_removal_history_full_merge_matches_composite_delta_test() -> Nil {
  let assert Ok(#(added, _)) =
    add_member(new_map("a"), "a", "doc", new_leaf("a"), 0, "old")
  let assert Ok(imported) =
    or_map.remove(added, "doc")
    |> or_map.to_json
    |> json.to_string
    |> or_map.from_json
  let assert Ok(snapshot) = map_snapshot(imported)
  let assert Ok(retained) = dict.get(snapshot.leaves, "doc")
  let cleared = or_set.remove_where(retained, fn(_) { True })
  let assert Ok(#(readded, _)) =
    add_member(imported, "b", "doc", cleared, 7, "new")
  let assert Ok(crdt.CrdtOrSet(leaf)) = or_map.get(readded, "doc")
  let assert Ok(local) = leaf_adapter.merge(new_map("b"), readded)
  let assert Ok(#(removed, delta)) = remove_key(local, "b", "doc", leaf)
  let assert Ok(remote) = leaf_adapter.apply_delta(imported, delta)
  or_map.get(remote, "doc") |> expect.to_equal(Error(Nil))
  expect_same_causality(remote, removed)
  expect_full_merges(imported, removed, remote)
}

pub fn imported_removal_history_full_merges_are_associative_test() -> Nil {
  let assert Ok(#(added, _)) =
    add_member(new_map("a"), "a", "doc", new_leaf("a"), 0, "old")
  let assert Ok(imported) =
    or_map.remove(added, "doc")
    |> or_map.to_json
    |> json.to_string
    |> or_map.from_json
  let assert Ok(snapshot) = map_snapshot(imported)
  let assert Ok(retained) = dict.get(snapshot.leaves, "doc")
  let cleared = or_set.remove_where(retained, fn(_) { True })
  let assert Ok(#(readded, _)) =
    add_member(imported, "b", "doc", cleared, 7, "new")
  let assert Ok(crdt.CrdtOrSet(leaf)) = or_map.get(readded, "doc")
  let assert Ok(local) = leaf_adapter.merge(new_map("b"), readded)
  let assert Ok(#(removed, _)) = remove_key(local, "b", "doc", leaf)
  let assert Ok(import_then_readd) = leaf_adapter.merge(imported, readded)
  let assert Ok(left_associated) =
    leaf_adapter.merge(import_then_readd, removed)
  let assert Ok(readd_then_remove) = leaf_adapter.merge(readded, removed)
  let assert Ok(right_associated) =
    leaf_adapter.merge(imported, readd_then_remove)
  or_map.get(left_associated, "doc") |> expect.to_equal(Error(Nil))
  or_map.get(right_associated, "doc") |> expect.to_equal(Error(Nil))
  expect_same_causality(right_associated, left_associated)
  list.each(permutations([imported, readded, removed]), fn(order) {
    let assert Ok(results) = associations(order, leaf_adapter.merge)
    list.length(results) |> expect.to_equal(2)
    list.each(results, fn(merged) { expect_same_causality(merged, removed) })
  })
}

fn expect_bounds(
  map: or_map.ORMap,
  expected: List(#(String, List(#(String, Int)))),
) -> Nil {
  let assert Ok(snapshot) = map_snapshot(map)
  let expected =
    expected
    |> list.map(fn(pair) {
      #(
        pair.0,
        pair.1
          |> list.map(fn(clock) { #(replica_id.new(clock.0), clock.1) })
          |> dict.from_list
          |> version_vector.from_dict,
      )
    })
    |> dict.from_list
  snapshot.remove_bounds |> expect.to_equal(expected)
}

// Each fixture includes a raw native inactive leaf and its removal bound.
fn native_removal(
  author: String,
  key: String,
  floor: Int,
) -> #(or_map.ORMap, or_map.ORMapDelta) {
  let assert Ok(seed) = map_seed(author, floor)
  let assert Ok(leaf) = leaf_seed(author, floor)
  let assert Ok(#(added, add_delta)) =
    or_map.update_with_delta(seed, key, fn(_) {
      crdt.CrdtOrSet(or_set.add(leaf, "old"))
    })
  let #(removed, remove_delta) = or_map.remove_with_delta(added, key)
  let assert Ok(delta) = or_map.merge_deltas(add_delta, remove_delta)
  let assert Ok(imported) =
    removed |> or_map.to_json |> json.to_string |> or_map.from_json
  #(imported, delta)
}

fn associations(
  items: List(a),
  combine: fn(a, a) -> Result(a, error),
) -> Result(List(a), error) {
  case items {
    [] -> Ok([])
    [item] -> Ok([item])
    _ -> {
      let splits =
        items
        |> list.index_map(fn(_, index) { index })
        |> list.drop(1)
      use groups <- result.try(
        list.try_map(splits, fn(split) {
          use left <- result.try(associations(list.take(items, split), combine))
          use right <- result.try(associations(list.drop(items, split), combine))
          use combined <- result.try(
            list.try_map(left, fn(left) {
              list.try_map(right, fn(right) { combine(left, right) })
            }),
          )
          Ok(list.flatten(combined))
        }),
      )
      Ok(list.flatten(groups))
    }
  }
}

pub fn active_key_retains_bounds_through_merge_apply_seed_and_rebrand_test() -> Nil {
  let #(imported, old_delta) = native_removal("a", "doc", 0)
  let assert Ok(snapshot) = map_snapshot(imported)
  let assert Ok(retained) = dict.get(snapshot.leaves, "doc")
  let cleared = or_set.remove_where(retained, fn(_) { True })
  let assert Ok(#(readded, new_delta)) =
    add_member(imported, "b", "doc", cleared, 7, "new")
  expect_bounds(readded, [#("doc", [#("a", 1)])])
  expect_members(readded, "doc", ["new"])
  let assert Ok(seed) = map_seed("c", 20)
  let assert Ok(rebranded) = leaf_adapter.merge(seed, readded)
  expect_same_causality(rebranded, readded)
  let assert Ok(rebranded_snapshot) = map_snapshot(rebranded)
  rebranded_snapshot.author |> expect.to_equal("c")
  let assert Ok(keys) = set_metadata(rebranded_snapshot.key_set)
  keys.author |> expect.to_equal("c")
  keys.counter |> expect.to_equal(20)
  expect_full_merges(imported, readded, readded)
  expect_deliveries(imported, [old_delta, new_delta], readded)
  let assert Ok(identity) =
    leaf_adapter.apply_delta(readded, or_map.empty_delta(readded))
  identity |> expect.to_equal(readded)
}

pub fn combined_removal_preserves_newer_multiwriter_bounds_test() -> Nil {
  let #(imported, _) = native_removal("a", "doc", 0)
  let assert Ok(snapshot) = map_snapshot(imported)
  let assert Ok(retained) = dict.get(snapshot.leaves, "doc")
  let assert Ok(#(readded, _)) =
    add_member(
      imported,
      "b",
      "doc",
      or_set.remove_where(retained, fn(_) { True }),
      7,
      "new",
    )
  let assert Ok(crdt.CrdtOrSet(leaf)) = or_map.get(readded, "doc")
  let assert Ok(local) = leaf_adapter.merge(new_map("b"), readded)
  let assert Ok(#(removed, delta)) = remove_key(local, "b", "doc", leaf)
  expect_bounds(removed, [#("doc", [#("a", 1), #("b", 9)])])
  let assert Ok(remote) = leaf_adapter.apply_delta(imported, delta)
  expect_same_causality(remote, removed)
  expect_full_merges(imported, removed, removed)
  expect_deliveries(imported, [delta, delta], removed)
}

pub fn divergent_bounds_join_maxima_in_every_order_and_association_test() -> Nil {
  let #(first, first_delta) = native_removal("a", "doc", 1)
  let #(second, second_delta) = native_removal("a", "doc", 4)
  let #(third, third_delta) = native_removal("b", "doc", 3)
  let #(fourth, fourth_delta) = native_removal("c", "other", 6)
  let expected_bounds = [
    #("doc", [#("a", 5), #("b", 4)]),
    #("other", [#("c", 7)]),
  ]
  let states = [first, second, third, fourth]
  let deltas = [first_delta, second_delta, third_delta, fourth_delta]
  let assert Ok(expected) =
    list.try_fold(states, new_map("observer"), leaf_adapter.merge)
  expect_bounds(expected, expected_bounds)
  or_map.keys(expected) |> expect.to_equal([])
  let assert Ok(snapshot) = map_snapshot(expected)
  dict.size(snapshot.leaves) |> expect.to_equal(2)
  list.each(dict.values(snapshot.leaves), fn(leaf) {
    or_set.value(leaf) |> expect.to_equal(set.from_list(["old"]))
  })
  list.each(permutations(states), fn(order) {
    let assert Ok(results) = associations(order, leaf_adapter.merge)
    list.length(results) |> expect.to_equal(5)
    list.each(results, fn(merged) {
      expect_same_causality(merged, expected)
      let assert Ok(replayed) =
        list.try_fold(list.append(order, order), merged, leaf_adapter.merge)
      expect_same_causality(replayed, expected)
      let assert Ok(duplicate) = leaf_adapter.merge(merged, merged)
      duplicate |> expect.to_equal(merged)
    })
  })
  expect_deliveries(new_map("observer"), deltas, expected)
  list.each(permutations(deltas), fn(order) {
    let assert Ok(batches) = associations(order, or_map.merge_deltas)
    list.length(batches) |> expect.to_equal(5)
    list.each(batches, fn(batch) {
      // Read native delta bounds directly, before the adapter can affect them.
      let decoder =
        decode.at(
          ["state", "remove_bounds_delta"],
          decode.dict(decode.string, version_vector.decoder()),
        )
      let assert Ok(bounds) =
        json.parse(or_map.delta_to_json(batch) |> json.to_string, decoder)
      bounds |> expect.to_equal(snapshot.remove_bounds)
      let assert Ok(applied) =
        leaf_adapter.apply_delta(new_map("observer"), batch)
      expect_same_causality(applied, expected)
      let assert Ok(replayed) = leaf_adapter.apply_delta(applied, batch)
      replayed |> expect.to_equal(applied)
    })
  })
}

pub fn disjoint_bounds_survive_value_deltas_and_retained_leaf_imports_test() -> Nil {
  let #(left, left_delta) = native_removal("a", "left", 1)
  let #(right, right_delta) = native_removal("b", "right", 3)
  let assert Ok(merged) = leaf_adapter.merge(left, right)
  expect_bounds(merged, [#("left", [#("a", 2)]), #("right", [#("b", 4)])])
  let assert Ok(snapshot) = map_snapshot(merged)
  let assert Ok(retained) = dict.get(snapshot.leaves, "left")
  let assert Ok(#(active, active_delta)) =
    add_member(
      merged,
      "c",
      "left",
      or_set.remove_where(retained, fn(_) { True }),
      8,
      "new",
    )
  expect_bounds(active, [#("left", [#("a", 2)]), #("right", [#("b", 4)])])
  expect_members(active, "left", ["new"])
  or_map.get(active, "right") |> expect.to_equal(Error(Nil))
  expect_deliveries(
    new_map("observer"),
    [left_delta, right_delta, active_delta],
    active,
  )
  expect_full_merges(merged, active, active)
}

pub fn adapter_propagates_native_merge_and_delta_errors_test() -> Nil {
  let set_map = new_map("a")
  let counter_map = or_map.new(replica_id.new("b"), crdt.GCounterSpec)
  let delta = or_map.empty_delta(counter_map)
  or_map.merge(set_map, counter_map)
  |> expect.to_equal(Error(crdt.TypeMismatch("or_set", "g_counter")))
  or_map.apply_delta(set_map, delta)
  |> expect.to_equal(Error(crdt.TypeMismatch("or_set", "g_counter")))
  leaf_adapter.merge(set_map, counter_map)
  |> expect.to_equal(
    Error(leaf_adapter.InvalidState("Expected or_set, found g_counter.")),
  )
  leaf_adapter.apply_delta(set_map, delta)
  |> expect.to_equal(
    Error(leaf_adapter.InvalidState("Expected or_set, found g_counter.")),
  )
  leaf_adapter.merge(counter_map, set_map)
  |> expect.to_equal(
    Error(leaf_adapter.InvalidState("Expected g_counter, found or_set.")),
  )
}

pub fn removal_subdeltas_converge_at_adapter_boundary_test() -> Nil {
  let assert Ok(#(added, _)) =
    add_member(new_map("a"), "a", "doc", new_leaf("a"), 0, "old")
  let assert Ok(crdt.CrdtOrSet(leaf)) = or_map.get(added, "doc")
  let cleared = or_set.remove_where(leaf, fn(_) { True })
  let assert Ok(#(cleared_map, clear_delta)) =
    or_map.update_with_delta(added, "doc", fn(_) { crdt.CrdtOrSet(cleared) })
  let #(replacement, key_delta) = or_map.remove_with_delta(cleared_map, "doc")
  expect_bounds(replacement, [#("doc", [#("a", 2)])])
  expect_deliveries(added, [clear_delta, key_delta], replacement)
}

pub fn correction_preserves_all_other_native_snapshot_fields_test() -> Nil {
  let #(imported, _) = native_removal("a", "doc", 0)
  let assert Ok(seed) = map_seed("b", 8)
  let assert Ok(working) = or_map.merge(seed, imported)
  let assert Ok(leaf) = leaf_seed("b", 8)
  let assert Ok(#(_, delta)) =
    or_map.update_with_delta(working, "doc", fn(_) {
      crdt.CrdtOrSet(or_set.add(leaf, "new"))
    })
  let assert Ok(native_applied) = or_map.apply_delta(imported, delta)
  let assert Ok(applied) = leaf_adapter.apply_delta(imported, delta)
  let assert Ok(native_merged) = or_map.merge(imported, native_applied)
  let assert Ok(merged) = leaf_adapter.merge(imported, native_applied)
  let assert Ok(original) = map_snapshot(imported)
  list.each([#(applied, native_applied), #(merged, native_merged)], fn(pair) {
    let assert Ok(corrected) = map_snapshot(pair.0)
    let assert Ok(native) = map_snapshot(pair.1)
    corrected
    |> expect.to_equal(
      MapSnapshot(..native, remove_bounds: original.remove_bounds),
    )
    expect_bounds(pair.0, [#("doc", [#("a", 1)])])
  })
  // A codec pass alone must also preserve a retained inactive leaf exactly.
  leaf_adapter.apply_delta(imported, or_map.empty_delta(imported))
  |> expect.to_equal(Ok(imported))
  leaf_adapter.merge(imported, imported) |> expect.to_equal(Ok(imported))
}

pub fn metadata_codec_preserves_preexisting_native_pruning_vectors_test() -> Nil {
  let stable =
    version_vector.new() |> version_vector.increment(replica_id.new("a"))
  let leaf =
    new_leaf("a")
    |> or_set.add("discarded")
    |> or_set.remove("discarded")
    |> or_set.prune(stable)
    |> or_set.add("retained")
  let #(removed, _) = native_removal("a", "discarded", 0)
  let compacted = or_map.prune(removed, stable)
  let assert Ok(#(added, _)) =
    or_map.update_with_delta(compacted, "doc", fn(_) { crdt.CrdtOrSet(leaf) })
  let imported = or_map.remove(added, "doc")
  let assert Ok(snapshot) = map_snapshot(imported)
  let assert Ok(keys) = set_metadata(snapshot.key_set)
  keys.pruned |> expect.to_equal(stable)
  let assert Ok(retained) = dict.get(snapshot.leaves, "doc")
  let assert Ok(members) = set_metadata(retained)
  members.pruned |> expect.to_equal(stable)
  // This checks codec preservation, not support for pruning in the set mode.
  leaf_adapter.apply_delta(imported, or_map.empty_delta(imported))
  |> expect.to_equal(Ok(imported))
  let assert Ok(native) = or_map.merge(imported, new_map("b"))
  leaf_adapter.merge(imported, new_map("b"))
  |> expect.to_equal(Ok(native))
}

fn raw_native_import_readd_remove() -> #(
  or_map.ORMap,
  or_map.ORMap,
  or_map.ORMap,
  or_map.ORMapDelta,
) {
  let #(imported, _) = native_removal("a", "doc", 0)
  let assert Ok(snapshot) = map_snapshot(imported)
  let assert Ok(retained) = dict.get(snapshot.leaves, "doc")
  let assert Ok(seed) = map_seed("b", 7)
  let assert Ok(leaf_seed) = leaf_seed("b", 7)
  let leaf =
    or_set.merge(leaf_seed, retained)
    |> or_set.remove_where(fn(_) { True })
    |> or_set.add("new")
  let assert Ok(working) = or_map.merge(seed, imported)
  let assert Ok(#(_, add_delta)) =
    or_map.update_with_delta(working, "doc", fn(_) { crdt.CrdtOrSet(leaf) })
  let assert Ok(readded) = or_map.apply_delta(imported, add_delta)
  let assert Ok(local) = or_map.merge(new_map("b"), readded)
  let cleared = or_set.remove_where(leaf, fn(_) { True })
  let assert Ok(#(cleared_map, clear_delta)) =
    or_map.update_with_delta(local, "doc", fn(_) { crdt.CrdtOrSet(cleared) })
  let #(_, key_delta) = or_map.remove_with_delta(cleared_map, "doc")
  let assert Ok(delta) = or_map.merge_deltas(clear_delta, key_delta)
  let assert Ok(removed) = or_map.apply_delta(local, delta)
  #(imported, readded, removed, delta)
}

pub fn upstream_native_full_merge_diverges_from_composite_delta_test() -> Nil {
  let #(imported, _, removed, delta) = raw_native_import_readd_remove()
  let assert Ok(applied) = or_map.apply_delta(imported, delta)
  let assert Ok(merged) = or_map.merge(imported, removed)
  expect_bounds(applied, [])
  expect_bounds(merged, [#("doc", [#("a", 1)])])
  let assert Ok(applied_causal) = causal_map(applied)
  let assert Ok(merged_causal) = causal_map(merged)
  { applied_causal == merged_causal } |> expect.to_be_false
}

pub fn upstream_native_full_merges_are_not_associative_test() -> Nil {
  let #(imported, readded, removed, _) = raw_native_import_readd_remove()
  let assert Ok(first) = or_map.merge(imported, readded)
  let assert Ok(left) = or_map.merge(first, removed)
  let assert Ok(last) = or_map.merge(readded, removed)
  let assert Ok(right) = or_map.merge(imported, last)
  expect_bounds(left, [])
  expect_bounds(right, [#("doc", [#("a", 1)])])
  let assert Ok(left_causal) = causal_map(left)
  let assert Ok(right_causal) = causal_map(right)
  { left_causal == right_causal } |> expect.to_be_false
}

pub fn helper_preserves_writer_and_all_issued_counter_floors_test() -> Nil {
  let assert Ok(seed) = map_seed("a", 40)
  let clocks = leaf_adapter.new_clocks()
  let assert Ok(#(delta, clocks)) =
    leaf_adapter.add(seed, clocks, replica_id.new("b"), "doc", "first")
  clocks.key_counter |> expect.to_equal(41)
  dict.get(clocks.member_counters, "doc") |> expect.to_equal(Ok(41))
  let assert Ok(added) = leaf_adapter.apply_delta(seed, delta)
  let assert Ok(snapshot) = map_snapshot(added)
  let assert Ok(leaf) = dict.get(snapshot.leaves, "doc")
  let assert Ok(metadata) = set_metadata(leaf)
  metadata.author |> expect.to_equal("b")
  dict.get(metadata.entries, "first")
  |> expect.to_equal(Ok(set.from_list([#("b", 41)])))
  let assert Ok(checkpoint) =
    leaf_adapter.retain_counter_floor(new_map("b"), clocks, replica_id.new("b"))
  let assert Ok(restored) =
    leaf_adapter.decode_state(or_map.to_json(checkpoint) |> json.to_string)
  expect_same_causality(restored, new_map("b"))
  let assert Ok(#(fresh, _)) =
    leaf_adapter.add(
      restored,
      leaf_adapter.new_clocks(),
      replica_id.new("b"),
      "other",
      "fresh",
    )
  let assert Ok(applied) = leaf_adapter.apply_delta(restored, fresh)
  let assert Ok(snapshot) = map_snapshot(applied)
  let assert Ok(leaf) = dict.get(snapshot.leaves, "other")
  let assert Ok(metadata) = set_metadata(leaf)
  dict.get(metadata.entries, "fresh")
  |> expect.to_equal(Ok(set.from_list([#("b", 42)])))
}

fn strict_map_json(
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

pub fn strict_decoder_rejects_invalid_live_and_retained_leaves_test() -> Nil {
  let empty_vector = version_vector.to_json(version_vector.new())
  let invalid = [
    strict_leaf_json(-1, [], [], empty_vector),
    strict_leaf_json(9_007_199_254_740_992, [], [], empty_vector),
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
  let active_keys = new_leaf("a") |> or_set.add("doc") |> or_set.to_json
  list.each([active_keys, counter_seed_json("a", 1)], fn(keys) {
    list.each(invalid, fn(leaf) {
      let encoded = strict_map_json(keys, [#("doc", leaf)], json.object([]))
      let assert Error(leaf_adapter.InvalidState(_)) =
        leaf_adapter.decode_state(encoded)
    })
  })
}

pub fn strict_decoder_validates_versions_bounds_and_unique_value_keys_test() -> Nil {
  let keys = new_leaf("a") |> or_set.add("doc") |> or_set.to_json
  let member = new_leaf("a") |> or_set.add("draft") |> or_set.to_json
  let duplicate =
    strict_map_json(keys, [#("doc", member), #("doc", member)], json.object([]))
  let assert Error(leaf_adapter.InvalidState(_)) =
    leaf_adapter.decode_state(duplicate)
  let missing = strict_map_json(keys, [], json.object([]))
  let assert Error(leaf_adapter.InvalidState(_)) =
    leaf_adapter.decode_state(missing)
  let encoded = strict_map_json(keys, [#("doc", member)], json.object([]))
  list.each(
    [
      string.replace(encoded, "\"v\":2", "\"v\":3"),
      string.replace(
        encoded,
        "\"crdt_spec\":\"or_set\"",
        "\"crdt_spec\":\"pn_counter\"",
      ),
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
  list.each([-1, 9_007_199_254_740_992], fn(counter) {
    let bound =
      dict.from_list([#(replica_id.new("a"), counter)])
      |> version_vector.from_dict
      |> version_vector.to_json
    let invalid =
      strict_map_json(keys, [#("doc", member)], json.object([#("doc", bound)]))
    let assert Error(leaf_adapter.InvalidState(_)) =
      leaf_adapter.decode_state(invalid)
  })
}

pub fn strict_decoder_accepts_native_v1_and_full_leaf_history_test() -> Nil {
  let assert Ok(#(map, _)) =
    add_member(new_map("a"), "a", "doc", new_leaf("a"), 0, "draft")
  let assert Ok(crdt.CrdtOrSet(leaf)) = or_map.get(map, "doc")
  let leaf = or_set.add(leaf, "reviewed")
  let assert Ok(#(map, delta)) = update_leaf(map, "doc", leaf)
  let v1 =
    strict_map_json(
      counter_seed_json("a", 2),
      [#("hidden", or_set.to_json(leaf))],
      json.object([]),
    )
    |> string.replace("\"v\":2", "\"v\":1")
    |> string.replace("\\\"v\\\":2", "\\\"v\\\":1")
  let assert Ok(_) = leaf_adapter.decode_state(v1)
  leaf_adapter.decode_delta(or_map.delta_to_json(delta) |> json.to_string)
  |> expect.to_equal(Ok(delta))
  leaf_adapter.validate_intent(delta, "doc", leaf_adapter.AddMember("reviewed"))
  |> expect.to_equal(Ok(Nil))
  leaf_adapter.decode_state(or_map.to_json(map) |> json.to_string)
  |> expect.to_equal(Ok(map))
}

pub fn helper_exhaustion_precedes_native_outer_or_inner_increment_test() -> Nil {
  let limit = 9_007_199_254_740_991
  let assert Ok(map) = map_seed("a", limit - 1)
  let assert Ok(#(delta, clocks)) =
    leaf_adapter.add(
      map,
      leaf_adapter.new_clocks(),
      replica_id.new("a"),
      "doc",
      "last",
    )
  let assert Ok(map) = leaf_adapter.apply_delta(map, delta)
  list.each(
    [
      leaf_adapter.add(map, clocks, replica_id.new("a"), "doc", "last"),
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
}
