//// Native OR-map compatibility for the set mode.
////
//// Keep removal bounds as a monotone per-key version-vector join. Native
//// merges can discard these bounds. Keep history for active keys too.
//// Pruning is not supported in this mode.

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/set
import gleam/string
import lattice_core/replica_id.{type ReplicaId}
import lattice_core/version_vector.{type VersionVector}
import lattice_maps/crdt
import lattice_maps/or_map.{type ORMap, type ORMapDelta}
import lattice_sets/or_set.{type ORSet}

const safe_counter = 9_007_199_254_740_991

@internal
pub type Clocks {
  Clocks(key_counter: Int, member_counters: Dict(String, Int))
}

@internal
pub type Intent {
  AddMember(member: String)
  RemoveMember(member: String)
  RemoveKey
}

@internal
pub type LeafError {
  InvalidState(detail: String)
  CounterExhausted(detail: String)
}

type Snapshot {
  Snapshot(
    author: String,
    spec: String,
    key_set: String,
    values: List(#(String, String)),
  )
}

/// Merge native state without discarding removal history.
@internal
pub fn merge(left: ORMap, right: ORMap) -> Result(ORMap, LeafError) {
  use left_bounds <- result.try(read_bounds(
    or_map.to_json(left),
    "remove_bounds",
  ))
  use right_bounds <- result.try(read_bounds(
    or_map.to_json(right),
    "remove_bounds",
  ))
  use merged <- result.try(
    or_map.merge(left, right) |> result.map_error(merge_error),
  )
  restore_bounds(
    merged,
    dict.combine(left_bounds, right_bounds, version_vector.merge),
  )
}

/// Apply a native delta without discarding removal history.
@internal
pub fn apply_delta(map: ORMap, delta: ORMapDelta) -> Result(ORMap, LeafError) {
  use map_bounds <- result.try(read_bounds(or_map.to_json(map), "remove_bounds"))
  use delta_bounds <- result.try(read_bounds(
    or_map.delta_to_json(delta),
    "remove_bounds_delta",
  ))
  use applied <- result.try(
    or_map.apply_delta(map, delta) |> result.map_error(merge_error),
  )
  restore_bounds(
    applied,
    dict.combine(map_bounds, delta_bounds, version_vector.merge),
  )
}

fn read_bounds(
  encoded: json.Json,
  field: String,
) -> Result(Dict(String, VersionVector), LeafError) {
  json.parse(
    json.to_string(encoded),
    decode.at(
      ["state", field],
      decode.dict(decode.string, version_vector.decoder()),
    ),
  )
  |> result.map_error(codec_error)
}

fn restore_bounds(
  map: ORMap,
  bounds: Dict(String, VersionVector),
) -> Result(ORMap, LeafError) {
  let value_decoder = {
    use key <- decode.field("key", decode.string)
    use value <- decode.field("crdt", decode.string)
    decode.success(#(key, value))
  }
  let snapshot_decoder =
    decode.at(["state"], {
      use author <- decode.field("replica_id", decode.string)
      use spec <- decode.field("crdt_spec", decode.string)
      use key_set <- decode.field("key_set", decode.string)
      use values <- decode.field("values", decode.list(value_decoder))
      decode.success(Snapshot(author, spec, key_set, values))
    })
  use snapshot <- result.try(
    json.parse(or_map.to_json(map) |> json.to_string, snapshot_decoder)
    |> result.map_error(codec_error),
  )
  // Preserve the native key and leaf payloads, including inactive leaves.
  json.object([
    #("type", json.string("or_map")),
    #("v", json.int(2)),
    #(
      "state",
      json.object([
        #("replica_id", json.string(snapshot.author)),
        #("crdt_spec", json.string(snapshot.spec)),
        #("key_set", json.string(snapshot.key_set)),
        #(
          "values",
          json.array(snapshot.values, fn(pair) {
            json.object([
              #("key", json.string(pair.0)),
              #("crdt", json.string(pair.1)),
            ])
          }),
        ),
        #(
          "remove_bounds",
          json.dict(bounds, fn(key) { key }, version_vector.to_json),
        ),
      ]),
    ),
  ])
  |> json.to_string
  |> or_map.from_json
  |> result.map_error(codec_error)
}

fn merge_error(error: crdt.MergeError) -> LeafError {
  let crdt.TypeMismatch(expected, found) = error
  InvalidState("Expected " <> expected <> ", found " <> found <> ".")
}

fn codec_error(error: json.DecodeError) -> LeafError {
  InvalidState("Invalid native OR-map metadata: " <> string.inspect(error))
}

type VectorMetadata {
  VectorMetadata(type_tag: String, version: Int, clocks: Dict(String, Int))
}

type SetMetadata {
  SetMetadata(
    native: ORSet(String),
    counter: Int,
    entries: Dict(String, List(#(String, Int))),
    tombstones: List(#(String, Int)),
  )
}

type MapMetadata {
  MapMetadata(
    keys: SetMetadata,
    values: Dict(String, SetMetadata),
    bounds: Dict(String, VectorMetadata),
  )
}

fn require(condition: Bool, detail: String) -> Result(Nil, LeafError) {
  case condition {
    True -> Ok(Nil)
    False -> Error(InvalidState(detail))
  }
}

fn valid_counter(counter: Int) -> Bool {
  counter >= 0 && counter <= safe_counter
}

fn vector_decoder() -> decode.Decoder(VectorMetadata) {
  use type_tag <- decode.field("type", decode.string)
  use version <- decode.field("v", decode.int)
  use clocks <- decode.then(decode.at(
    ["state", "clocks"],
    decode.dict(decode.string, decode.int),
  ))
  decode.success(VectorMetadata(type_tag, version, clocks))
}

fn validate_vector(vector: VectorMetadata) -> Result(Nil, LeafError) {
  require(
    vector.type_tag == "version_vector"
      && vector.version == 1
      && list.all(dict.values(vector.clocks), valid_counter),
    "Invalid version vector.",
  )
}

fn read_set(encoded: String) -> Result(SetMetadata, LeafError) {
  let tag_decoder = {
    use author <- decode.field("r", decode.string)
    use counter <- decode.field("c", decode.int)
    decode.success(#(author, counter))
  }
  let decoder = {
    use type_tag <- decode.field("type", decode.string)
    use version <- decode.field("v", decode.int)
    use state <- decode.field("state", {
      use _author <- decode.field("replica_id", decode.string)
      use counter <- decode.field("counter", decode.int)
      use entries <- decode.field(
        "entries",
        decode.dict(decode.string, decode.list(tag_decoder)),
      )
      use tombstones <- decode.optional_field(
        "tombstones",
        [],
        decode.list(tag_decoder),
      )
      use pruned <- decode.optional_field(
        "pruned",
        VectorMetadata("version_vector", 1, dict.new()),
        vector_decoder(),
      )
      decode.success(#(counter, entries, tombstones, pruned))
    })
    decode.success(#(type_tag, version, state))
  }
  use #(type_tag, version, #(counter, entries, tombstones, pruned)) <- result.try(
    json.parse(encoded, decoder) |> result.map_error(codec_error),
  )
  use _ <- result.try(require(
    type_tag == "or_set" && { version == 1 || version == 2 },
    "Expected OR-set v1 or v2.",
  ))
  use _ <- result.try(validate_vector(pruned))
  use _ <- result.try(require(
    dict.size(pruned.clocks) == 0,
    "OR-set pruning is not supported.",
  ))
  use _ <- result.try(require(valid_counter(counter), "Invalid OR-set counter."))
  let live = dict.values(entries) |> list.flatten
  use _ <- result.try(require(
    list.all(list.append(live, tombstones), fn(dot) {
      dot.1 > 0 && dot.1 <= counter && dot.1 <= safe_counter
    }),
    "OR-set tags must have positive safe counters at or below the state counter.",
  ))
  use _ <- result.try(require(
    set.is_empty(set.intersection(
      set.from_list(live),
      set.from_list(tombstones),
    )),
    "An OR-set tag cannot be both live and removed.",
  ))
  use _ <- result.try(
    list.try_fold(dict.to_list(entries), dict.new(), fn(owners, pair) {
      use _ <- result.try(require(
        !list.is_empty(pair.1),
        "A live OR-set member must have a tag.",
      ))
      list.try_fold(pair.1, owners, fn(owners, dot) {
        case dict.get(owners, dot) {
          Ok(member) if member != pair.0 ->
            Error(InvalidState(
              "An OR-set tag belongs to distinct live members.",
            ))
          Ok(_) | Error(Nil) -> Ok(dict.insert(owners, dot, pair.0))
        }
      })
    }),
  )
  use native <- result.try(
    or_set.from_json(encoded) |> result.map_error(codec_error),
  )
  Ok(SetMetadata(native, counter, entries, tombstones))
}

fn read_map(encoded: String, delta: Bool) -> Result(MapMetadata, LeafError) {
  let #(expected_type, key_field, value_field, bound_field) = case delta {
    True -> #(
      "or_map_delta",
      "key_set_delta",
      "value_deltas",
      "remove_bounds_delta",
    )
    False -> #("or_map", "key_set", "values", "remove_bounds")
  }
  let value_decoder = {
    use key <- decode.field("key", decode.string)
    use value <- decode.field("crdt", decode.string)
    decode.success(#(key, value))
  }
  let decoder = {
    use type_tag <- decode.field("type", decode.string)
    use version <- decode.field("v", decode.int)
    use state <- decode.field("state", {
      use _author <- decode.field("replica_id", decode.string)
      use spec <- decode.field("crdt_spec", decode.string)
      use keys <- decode.field(key_field, decode.string)
      use values <- decode.field(value_field, decode.list(value_decoder))
      use bounds <- decode.optional_field(
        bound_field,
        dict.new(),
        decode.dict(decode.string, vector_decoder()),
      )
      decode.success(#(spec, keys, values, bounds))
    })
    decode.success(#(type_tag, version, state))
  }
  use #(type_tag, version, #(spec, keys, values, bounds)) <- result.try(
    json.parse(encoded, decoder) |> result.map_error(codec_error),
  )
  use _ <- result.try(require(
    type_tag == expected_type && { version == 1 || { !delta && version == 2 } },
    "Invalid OR-map envelope type or version.",
  ))
  use _ <- result.try(require(spec == "or_set", "Expected or_set value spec."))
  let value_keys = list.map(values, fn(pair) { pair.0 })
  use _ <- result.try(require(
    list.length(value_keys) == set.size(set.from_list(value_keys)),
    "Duplicate OR-map value keys.",
  ))
  use keys <- result.try(read_set(keys))
  use _ <- result.try(list.try_map(dict.values(bounds), validate_vector))
  use values <- result.try(
    list.try_map(values, fn(pair) {
      use value <- result.try(read_set(pair.1))
      Ok(#(pair.0, value))
    }),
  )
  let values = dict.from_list(values)
  use _ <- result.try(require(
    list.all(dict.keys(keys.entries), fn(key) { dict.has_key(values, key) }),
    "An active OR-map key has no set value.",
  ))
  Ok(MapMetadata(keys, values, bounds))
}

/// Validate raw lists before the native decoder constructs dictionaries.
@internal
pub fn decode_state(encoded: String) -> Result(ORMap, LeafError) {
  use _ <- result.try(read_map(encoded, False))
  or_map.from_json(encoded) |> result.map_error(codec_error)
}

@internal
pub fn decode_delta(encoded: String) -> Result(ORMapDelta, LeafError) {
  use _ <- result.try(read_map(encoded, True))
  or_map.delta_from_json(encoded) |> result.map_error(codec_error)
}

@internal
pub fn validate_state(map: ORMap) -> Result(Nil, LeafError) {
  read_map(or_map.to_json(map) |> json.to_string, False)
  |> result.replace(Nil)
}

/// Check the declared key and intent without discarding other member history.
@internal
pub fn validate_intent(
  delta: ORMapDelta,
  key: String,
  intent: Intent,
) -> Result(Nil, LeafError) {
  use metadata <- result.try(read_map(
    or_map.delta_to_json(delta) |> json.to_string,
    True,
  ))
  let mentioned_keys =
    list.append(
      dict.keys(metadata.keys.entries),
      list.append(dict.keys(metadata.values), dict.keys(metadata.bounds)),
    )
  use _ <- result.try(require(
    list.all(mentioned_keys, fn(mentioned) { mentioned == key }),
    "OR-map delta concerns a different key.",
  ))
  let empty =
    list.is_empty(mentioned_keys)
    && list.is_empty(metadata.keys.tombstones)
    && metadata.keys.counter == 0
  case intent, empty {
    RemoveMember(_), True | RemoveKey, True -> Ok(Nil)
    AddMember(_), _ | RemoveMember(_), False | RemoveKey, False -> {
      use leaf <- result.try(
        dict.get(metadata.values, key)
        |> result.replace_error(InvalidState(
          "OR-map operation has no set value.",
        )),
      )
      case intent {
        AddMember(member) | RemoveMember(member) -> {
          use _ <- result.try(require(
            dict.has_key(metadata.keys.entries, key)
              && list.is_empty(metadata.keys.tombstones)
              && dict.size(metadata.bounds) == 0,
            "Member operation must update only its declared key.",
          ))
          case intent {
            AddMember(_) ->
              require(
                or_set.contains(leaf.native, member),
                "Added member is absent from the delta.",
              )
            RemoveMember(_) ->
              require(
                !or_set.contains(leaf.native, member)
                  && !list.is_empty(leaf.tombstones),
                "Removed member is live or has no removal history.",
              )
            RemoveKey -> Error(InvalidState("Expected member operation."))
          }
        }
        RemoveKey -> {
          use bound <- result.try(
            dict.get(metadata.bounds, key)
            |> result.replace_error(InvalidState(
              "Key removal has no removal bound.",
            )),
          )
          require(
            dict.size(metadata.keys.entries) == 0
              && !list.is_empty(metadata.keys.tombstones)
              && dict.size(leaf.entries) == 0
              && list.all(metadata.keys.tombstones, fn(dot) {
              dot.1 <= result.unwrap(dict.get(bound.clocks, dot.0), 0)
            }),
            "Key removal must clear observed members and bound removed key tags.",
          )
        }
      }
    }
  }
}

@internal
pub fn new_clocks() -> Clocks {
  Clocks(0, dict.new())
}

fn checked_clocks(clocks: Clocks) -> Result(Clocks, LeafError) {
  use _ <- result.try(require(
    valid_counter(clocks.key_counter)
      && list.all(dict.values(clocks.member_counters), valid_counter),
    "Invalid OR-map counter floor.",
  ))
  Ok(
    Clocks(
      ..clocks,
      key_counter: list.fold(
        dict.values(clocks.member_counters),
        clocks.key_counter,
        int.max,
      ),
    ),
  )
}

fn observe_metadata(
  clocks: Clocks,
  metadata: MapMetadata,
) -> Result(Clocks, LeafError) {
  use clocks <- result.try(checked_clocks(clocks))
  let members =
    dict.fold(metadata.values, clocks.member_counters, fn(counters, key, leaf) {
      dict.insert(
        counters,
        key,
        int.max(result.unwrap(dict.get(counters, key), 0), leaf.counter),
      )
    })
  let bounds =
    metadata.bounds
    |> dict.values
    |> list.flat_map(fn(bound) { dict.values(bound.clocks) })
    |> list.fold(0, int.max)
  checked_clocks(Clocks(
    int.max(clocks.key_counter, int.max(metadata.keys.counter, bounds)),
    members,
  ))
}

@internal
pub fn observe_state(clocks: Clocks, map: ORMap) -> Result(Clocks, LeafError) {
  use metadata <- result.try(read_map(
    or_map.to_json(map) |> json.to_string,
    False,
  ))
  observe_metadata(clocks, metadata)
}

@internal
pub fn observe_delta(
  clocks: Clocks,
  delta: ORMapDelta,
) -> Result(Clocks, LeafError) {
  use metadata <- result.try(read_map(
    or_map.delta_to_json(delta) |> json.to_string,
    True,
  ))
  observe_metadata(clocks, metadata)
}

fn seed_json(replica: ReplicaId, counter: Int) -> json.Json {
  json.object([
    #("type", json.string("or_set")),
    #("v", json.int(2)),
    #(
      "state",
      json.object([
        #("replica_id", json.string(replica_id.to_string(replica))),
        #("counter", json.int(counter)),
        #("entries", json.object([])),
        #("tombstones", json.array([], json.string)),
        #("pruned", version_vector.to_json(version_vector.new())),
      ]),
    ),
  ])
}

/// Reserve only the authoring cursor. Do not copy pending tags or values.
@internal
pub fn retain_counter_floor(
  map: ORMap,
  clocks: Clocks,
  replica: ReplicaId,
) -> Result(ORMap, LeafError) {
  use clocks <- result.try(observe_state(clocks, map))
  use seed <- result.try(
    json.object([
      #("type", json.string("or_map")),
      #("v", json.int(2)),
      #(
        "state",
        json.object([
          #("replica_id", json.string(replica_id.to_string(replica))),
          #("crdt_spec", json.string("or_set")),
          #(
            "key_set",
            json.string(
              seed_json(replica, clocks.key_counter) |> json.to_string,
            ),
          ),
          #("values", json.array([], json.string)),
          #("remove_bounds", json.object([])),
        ]),
      ),
    ])
    |> json.to_string
    |> or_map.from_json
    |> result.map_error(codec_error),
  )
  merge(seed, map)
}

fn writable_leaf(
  metadata: MapMetadata,
  clocks: Clocks,
  replica: ReplicaId,
  key: String,
) -> Result(ORSet(String), LeafError) {
  use seed <- result.try(
    seed_json(replica, clocks.key_counter)
    |> json.to_string
    |> or_set.from_json
    |> result.map_error(codec_error),
  )
  let leaf = case dict.get(metadata.values, key) {
    Ok(retained) -> or_set.merge(seed, retained.native)
    Error(Nil) -> seed
  }
  Ok(case dict.has_key(metadata.keys.entries, key) {
    True -> leaf
    False -> or_set.remove_where(leaf, fn(_) { True })
  })
}

fn require_increment(clocks: Clocks) -> Result(Nil, LeafError) {
  case clocks.key_counter < safe_counter {
    True -> Ok(Nil)
    False -> Error(CounterExhausted("OR-map set counter is exhausted."))
  }
}

fn update_leaf(
  working: ORMap,
  clocks: Clocks,
  key: String,
  leaf: ORSet(String),
) -> Result(#(ORMapDelta, Clocks), LeafError) {
  use #(_, delta) <- result.try(
    or_map.update_with_delta(working, key, fn(_) { crdt.CrdtOrSet(leaf) })
    |> result.map_error(merge_error),
  )
  use clocks <- result.try(observe_delta(clocks, delta))
  Ok(#(delta, clocks))
}

@internal
pub fn add(
  map: ORMap,
  clocks: Clocks,
  replica: ReplicaId,
  key: String,
  member: String,
) -> Result(#(ORMapDelta, Clocks), LeafError) {
  use metadata <- result.try(read_map(
    or_map.to_json(map) |> json.to_string,
    False,
  ))
  use clocks <- result.try(observe_metadata(clocks, metadata))
  use _ <- result.try(require_increment(clocks))
  use working <- result.try(retain_counter_floor(map, clocks, replica))
  use leaf <- result.try(writable_leaf(metadata, clocks, replica, key))
  update_leaf(working, clocks, key, or_set.add(leaf, member))
}

@internal
pub fn remove_member(
  map: ORMap,
  clocks: Clocks,
  replica: ReplicaId,
  key: String,
  member: String,
) -> Result(#(ORMapDelta, Clocks), LeafError) {
  use metadata <- result.try(read_map(
    or_map.to_json(map) |> json.to_string,
    False,
  ))
  use observed <- result.try(observe_metadata(clocks, metadata))
  let present = case dict.get(metadata.values, key) {
    Ok(leaf) ->
      dict.has_key(metadata.keys.entries, key)
      && or_set.contains(leaf.native, member)
    Error(Nil) -> False
  }
  case present {
    False -> Ok(#(or_map.empty_delta(map), clocks))
    True -> {
      use _ <- result.try(require_increment(observed))
      use working <- result.try(retain_counter_floor(map, observed, replica))
      use leaf <- result.try(writable_leaf(metadata, observed, replica, key))
      update_leaf(working, observed, key, or_set.remove(leaf, member))
    }
  }
}

@internal
pub fn remove_key(
  map: ORMap,
  clocks: Clocks,
  replica: ReplicaId,
  key: String,
) -> Result(#(ORMapDelta, Clocks), LeafError) {
  use metadata <- result.try(read_map(
    or_map.to_json(map) |> json.to_string,
    False,
  ))
  use observed <- result.try(observe_metadata(clocks, metadata))
  case dict.has_key(metadata.keys.entries, key) {
    False -> Ok(#(or_map.empty_delta(map), clocks))
    True -> {
      use _ <- result.try(require_increment(observed))
      use working <- result.try(retain_counter_floor(map, observed, replica))
      use leaf <- result.try(writable_leaf(metadata, observed, replica, key))
      let cleared = or_set.remove_where(leaf, fn(_) { True })
      use #(cleared_map, clear_delta) <- result.try(
        or_map.update_with_delta(working, key, fn(_) { crdt.CrdtOrSet(cleared) })
        |> result.map_error(merge_error),
      )
      let #(_, key_delta) = or_map.remove_with_delta(cleared_map, key)
      use delta <- result.try(
        or_map.merge_deltas(clear_delta, key_delta)
        |> result.map_error(merge_error),
      )
      use clocks <- result.try(observe_delta(observed, delta))
      Ok(#(delta, clocks))
    }
  }
}
