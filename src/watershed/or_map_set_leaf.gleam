//// Native OR-map compatibility for the String set mode.
////
//// Generation floors retain removal history in lattice_maps 2.0.
//// Pruning is not supported in this mode.

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set
import gleam/string
import lattice_core/replica_id.{type ReplicaId}
import lattice_core/version_vector
import lattice_maps/crdt
import lattice_maps/or_map
import lattice_sets/or_set.{type ORSet}
import watershed/json_ot

type ORMap =
  or_map.ORMap(String)

type ORMapDelta =
  or_map.ORMapDelta(String)

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
  Snapshot(author: String, spec: String, clock: Int, entries: List(Entry))
}

type Entry {
  Entry(
    key: String,
    generation: json_ot.JsonValue,
    membership: String,
    value: Option(String),
  )
}

/// Native generation floors preserve removal history.
@internal
pub fn merge(left: ORMap, right: ORMap) -> Result(ORMap, LeafError) {
  or_map.merge(left, right) |> result.map_error(merge_error)
}

/// Apply a native delta without discarding removal history.
@internal
pub fn apply_delta(map: ORMap, delta: ORMapDelta) -> Result(ORMap, LeafError) {
  or_map.apply_delta(map, delta) |> result.map_error(merge_error)
}

fn snapshot_decoder() -> decode.Decoder(Snapshot) {
  let entry_decoder = {
    use key <- decode.field("key", decode.string)
    use generation <- decode.field("generation", json_ot.decoder())
    use membership <- decode.field("membership", decode.string)
    use value <- decode.field("value", decode.optional(decode.string))
    decode.success(Entry(key, generation, membership, value))
  }
  decode.at(["state"], {
    use author <- decode.field("replica_id", decode.string)
    use spec <- decode.field("spec", decode.string)
    use clock <- decode.field("clock", decode.int)
    use entries <- decode.field("entries", decode.list(entry_decoder))
    decode.success(Snapshot(author, spec, clock, entries))
  })
}

fn encode_snapshot(snapshot: Snapshot, delta: Bool) -> String {
  json.object([
    #(
      "type",
      json.string(case delta {
        True -> "or_map_delta"
        False -> "or_map"
      }),
    ),
    #(
      "v",
      json.int(case delta {
        True -> 2
        False -> 3
      }),
    ),
    #(
      "state",
      json.object([
        #("replica_id", json.string(snapshot.author)),
        #("spec", json.string(snapshot.spec)),
        #("clock", json.int(snapshot.clock)),
        #(
          "entries",
          json.array(snapshot.entries, fn(entry) {
            json.object([
              #("key", json.string(entry.key)),
              #("generation", json_ot.to_json(entry.generation)),
              #("membership", json.string(entry.membership)),
              #("value", case entry.value {
                None -> json.null()
                Some(value) -> json.string(value)
              }),
            ])
          }),
        ),
      ]),
    ),
  ])
  |> json.to_string
}

fn merge_error(error: crdt.MergeError) -> LeafError {
  case error {
    crdt.TypeMismatch(expected, found) ->
      InvalidState("Expected " <> expected <> ", found " <> found <> ".")
    _ ->
      InvalidState("Invalid native OR-map operation: " <> string.inspect(error))
  }
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
    counter: Int,
    key_entries: Dict(String, List(#(String, Int))),
    key_tombstones: List(#(String, Int)),
    mentioned_keys: List(String),
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
      use entries <- decode.field("entries", case version {
        3 -> {
          use entries <- decode.then(
            decode.list({
              use value <- decode.field("value", decode.string)
              use tags <- decode.field("tags", decode.list(tag_decoder))
              decode.success(#(value, tags))
            }),
          )
          let unique = dict.from_list(entries)
          case dict.size(unique) == list.length(entries) {
            True -> decode.success(unique)
            False -> decode.failure(unique, "distinct OR-set members")
          }
        }
        _ -> decode.dict(decode.string, decode.list(tag_decoder))
      })
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
    type_tag == "or_set" && { version == 1 || version == 2 || version == 3 },
    "Expected OR-set v1, v2, or v3.",
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
    case version {
      3 -> or_set.from_json_with(encoded, decode.string)
      _ -> or_set.from_json(encoded)
    }
    |> result.map_error(codec_error),
  )
  Ok(SetMetadata(native, counter, entries, tombstones))
}

fn read_legacy_map(encoded: String) -> Result(MapMetadata, LeafError) {
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
      use keys <- decode.field("key_set", decode.string)
      use values <- decode.field("values", decode.list(value_decoder))
      use bounds <- decode.optional_field(
        "remove_bounds",
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
    type_tag == "or_map" && { version == 1 || version == 2 },
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
  Ok(MapMetadata(
    keys.counter,
    keys.entries,
    keys.tombstones,
    list.append(
      dict.keys(keys.entries),
      list.append(value_keys, dict.keys(bounds)),
    ),
    values,
    bounds,
  ))
}

fn read_map(encoded: String, delta: Bool) -> Result(MapMetadata, LeafError) {
  // Validate the native envelope, schema, generations, and unique keys first.
  use _ <- result.try(
    case delta {
      True -> or_map.delta_from_json(encoded) |> result.replace(Nil)
      False -> or_map.from_json(encoded) |> result.replace(Nil)
    }
    |> result.map_error(codec_error),
  )
  use snapshot <- result.try(
    json.parse(encoded, snapshot_decoder()) |> result.map_error(codec_error),
  )
  use spec <- result.try(
    crdt.spec_from_json_with(snapshot.spec, decode.string)
    |> result.map_error(codec_error),
  )
  use _ <- result.try(require(
    spec == crdt.OrSetSpec,
    "Expected or_set value spec.",
  ))
  use memberships <- result.try(
    list.try_map(snapshot.entries, fn(entry) {
      use membership <- result.try(read_set(entry.membership))
      Ok(#(entry.key, membership))
    }),
  )
  // Membership contexts are per key. Joining their native sets would let
  // an imported key's tombstones remove another key's live membership.
  let counter =
    list.fold(memberships, snapshot.clock, fn(counter, pair) {
      int.max(counter, pair.1.counter)
    })
  let key_entries =
    list.fold(memberships, dict.new(), fn(entries, pair) {
      dict.combine(entries, pair.1.entries, list.append)
    })
  let key_tombstones =
    list.flat_map(memberships, fn(pair) { pair.1.tombstones })
  use values <- result.try(
    list.try_fold(snapshot.entries, dict.new(), fn(values, entry) {
      case entry.value {
        None -> Ok(values)
        Some(encoded) -> {
          use child <- result.try(case delta {
            False -> Ok(encoded)
            True -> {
              use change <- result.try(
                crdt.delta_from_json_with(encoded, decode.string)
                |> result.map_error(codec_error),
              )
              case change {
                crdt.StateDelta(crdt.CrdtOrSet(_)) -> {
                  json.parse(
                    encoded,
                    decode.at(["state", "payload"], decode.string),
                  )
                  |> result.map_error(codec_error)
                }
                _ ->
                  Error(InvalidState("Expected a complete OR-set leaf delta."))
              }
            }
          })
          use leaf <- result.try(read_set(child))
          Ok(dict.insert(values, entry.key, leaf))
        }
      }
    }),
  )
  let bounds =
    memberships
    |> list.filter_map(fn(pair) {
      case list.is_empty(pair.1.tombstones) {
        True -> Error(Nil)
        False ->
          Ok(#(
            pair.0,
            VectorMetadata(
              "version_vector",
              1,
              list.fold(pair.1.tombstones, dict.new(), fn(clocks, dot) {
                dict.insert(
                  clocks,
                  dot.0,
                  int.max(result.unwrap(dict.get(clocks, dot.0), 0), dot.1),
                )
              }),
            ),
          ))
      }
    })
    |> dict.from_list
  Ok(MapMetadata(
    counter,
    key_entries,
    key_tombstones,
    list.map(snapshot.entries, fn(entry) { entry.key }),
    values,
    bounds,
  ))
}

/// Import legacy baselines or decode modern snapshots with strict metadata.
/// Legacy deltas are not valid modern replication messages.
@internal
pub fn decode_state(encoded: String) -> Result(ORMap, LeafError) {
  use version <- result.try(
    json.parse(encoded, {
      use version <- decode.field("v", decode.int)
      decode.success(version)
    })
    |> result.map_error(codec_error),
  )
  case version {
    1 | 2 -> {
      use metadata <- result.try(read_legacy_map(encoded))
      use author <- result.try(
        json.parse(encoded, decode.at(["state", "replica_id"], decode.string))
        |> result.map_error(codec_error),
      )
      let replica = replica_id.new(author)
      use map <- result.try(
        or_map.import_legacy(encoded, crdt.OrSetSpec, decode.string, replica)
        |> result.map_error(codec_error),
      )
      use clocks <- result.try(observe_metadata(new_clocks(), metadata))
      retain_counter_floor(map, clocks, replica)
    }
    _ -> {
      use _ <- result.try(read_map(encoded, False))
      or_map.from_json(encoded) |> result.map_error(codec_error)
    }
  }
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
  let mentioned_keys = metadata.mentioned_keys
  use _ <- result.try(require(
    list.all(mentioned_keys, fn(mentioned) { mentioned == key }),
    "OR-map delta concerns a different key.",
  ))
  let empty =
    list.is_empty(mentioned_keys)
    && list.is_empty(metadata.key_tombstones)
    && metadata.counter == 0
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
            dict.has_key(metadata.key_entries, key)
              && list.is_empty(metadata.key_tombstones)
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
            dict.size(metadata.key_entries) == 0
              && !list.is_empty(metadata.key_tombstones)
              && dict.size(leaf.entries) == 0
              && list.all(metadata.key_tombstones, fn(dot) {
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
    int.max(clocks.key_counter, int.max(metadata.counter, bounds)),
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
  use snapshot <- result.try(
    json.parse(or_map.to_json(map) |> json.to_string, snapshot_decoder())
    |> result.map_error(codec_error),
  )
  encode_snapshot(
    Snapshot(
      ..snapshot,
      author: replica_id.to_string(replica),
      clock: clocks.key_counter,
    ),
    False,
  )
  |> or_map.from_json
  |> result.map_error(codec_error)
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
  Ok(case dict.has_key(metadata.key_entries, key) {
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
  use delta <- result.try(reserve_membership(delta, clocks.key_counter))
  use clocks <- result.try(observe_delta(clocks, delta))
  Ok(#(delta, clocks))
}

// A rolled-back add must not reuse its membership tag, even for a new key.
fn reserve_membership(
  delta: ORMapDelta,
  floor: Int,
) -> Result(ORMapDelta, LeafError) {
  use snapshot <- result.try(
    json.parse(
      or_map.delta_to_json(delta) |> json.to_string,
      snapshot_decoder(),
    )
    |> result.map_error(codec_error),
  )
  use entries <- result.try(
    list.try_map(snapshot.entries, fn(entry) {
      use author <- result.try(
        json.parse(
          entry.membership,
          decode.at(["state", "replica_id"], decode.string),
        )
        |> result.map_error(codec_error),
      )
      use seed <- result.try(
        seed_json(replica_id.new(author), floor)
        |> json.to_string
        |> or_set.from_json
        |> result.map_error(codec_error),
      )
      let membership = or_set.add(seed, entry.key)
      Ok(
        Entry(
          ..entry,
          membership: or_set.to_json_with(membership, json.string)
            |> json.to_string,
        ),
      )
    }),
  )
  encode_snapshot(
    Snapshot(..snapshot, clock: floor + 1, entries: entries),
    True,
  )
  |> or_map.delta_from_json
  |> result.map_error(codec_error)
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
      dict.has_key(metadata.key_entries, key)
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
  case dict.has_key(metadata.key_entries, key) {
    False -> Ok(#(or_map.empty_delta(map), clocks))
    True -> {
      use _ <- result.try(require_increment(observed))
      use working <- result.try(retain_counter_floor(map, observed, replica))
      use leaf <- result.try(writable_leaf(metadata, observed, replica, key))
      let cleared = or_set.remove_where(leaf, fn(_) { True })
      use #(_, clear_delta) <- result.try(
        or_map.update_with_delta(working, key, fn(_) { crdt.CrdtOrSet(cleared) })
        |> result.map_error(merge_error),
      )
      use clear_delta <- result.try(reserve_membership(
        clear_delta,
        observed.key_counter,
      ))
      use cleared_map <- result.try(apply_delta(working, clear_delta))
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
