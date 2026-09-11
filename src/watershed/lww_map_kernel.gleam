//// A string-valued LWW map with retained tombstones and per-key clocks.

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lattice_core/replica_id.{type ReplicaId}
import lattice_maps/crdt
import lattice_maps/lww_map
import lattice_registers/lww_register
import watershed/canonical_json
import watershed/json_ot
import watershed/lww_clock

pub type LWWMap =
  lww_map.LWWMap(String)

pub type LwwMapState {
  LwwMapState(
    replica_id: ReplicaId,
    sequenced: LWWMap,
    optimistic: LWWMap,
    pending: List(PendingOp),
    next_pending_message_id: Int,
    last_seen: Dict(String, Int),
  )
}

pub type PendingOp {
  PendingOp(operation: LwwMapOperation, message_id: Int)
}

pub type LwwMapOperation {
  Set(key: String, value: String, timestamp: Int, delta: LWWMap)
  Remove(key: String, timestamp: Int, delta: LWWMap)
}

pub type LwwMapEvent {
  ValueChanged(
    key: String,
    previous_value: Option(String),
    value: Option(String),
  )
}

pub type KernelError {
  UnexpectedAck(operation: LwwMapOperation, detail: String)
  UnexpectedRollback(operation: LwwMapOperation, detail: String)
  Clock(error: lww_clock.ClockError)
  InvalidState(detail: String)
  UnsupportedPruning(timestamp: Int)
  DecodeError(error: json.DecodeError)
}

pub fn new(replica_id: ReplicaId) -> LwwMapState {
  let map = new_map(replica_id)
  LwwMapState(replica_id, map, map, [], 0, dict.new())
}

fn new_map(replica: ReplicaId) -> LWWMap {
  lww_map.new(replica, crdt.LwwRegisterSpec(""))
}

fn string_value(value: crdt.Crdt(String)) -> Result(String, Nil) {
  case value {
    crdt.CrdtLwwRegister(register) -> Ok(lww_register.value(register))
    _ -> Error(Nil)
  }
}

fn merge_error(error: crdt.MergeError) -> KernelError {
  InvalidState("Invalid LWW map operation: " <> string.inspect(error))
}

pub fn get(state: LwwMapState, key: String) -> Result(String, Nil) {
  lww_map.get(state.optimistic, key) |> result.try(string_value)
}

pub fn entries(state: LwwMapState) -> List(#(String, String)) {
  map_entries(state.optimistic)
}

pub fn sequenced_entries(state: LwwMapState) -> List(#(String, String)) {
  map_entries(state.sequenced)
}

pub fn keys(state: LwwMapState) -> List(String) {
  lww_map.keys(state.optimistic) |> list.sort(canonical_json.compare)
}

fn map_entries(map: LWWMap) -> List(#(String, String)) {
  lww_map.keys(map)
  |> list.sort(canonical_json.compare)
  |> list.filter_map(fn(key) {
    lww_map.get(map, key)
    |> result.try(string_value)
    |> result.map(fn(value) { #(key, value) })
  })
}

fn metadata_decoder() -> decode.Decoder(List(#(String, Option(String), Int))) {
  use tag <- decode.field("type", decode.string)
  use version <- decode.field("v", decode.int)
  use entries <- decode.then(decode.at(
    ["state", "entries"],
    decode.list({
      use key <- decode.field("key", decode.string)
      use value <- decode.field("value", decode.optional(decode.string))
      use timestamp <- decode.field("timestamp", decode.int)
      decode.success(#(key, value, timestamp))
    }),
  ))
  use watermark <- decode.field("state", case version {
    1 -> {
      use watermark <- decode.optional_field("pruned_timestamp", 0, decode.int)
      decode.success(watermark)
    }
    _ -> {
      use watermark <- decode.field("pruned_timestamp", decode.int)
      decode.success(watermark)
    }
  })
  let distinct =
    entries |> list.map(fn(entry) { entry.0 }) |> list.unique |> list.length
  case
    tag == "lww_map"
    && { version == 1 || version == 2 || version == 3 }
    && watermark == 0
    && distinct == list.length(entries)
    && list.all(entries, fn(entry) {
      entry.2 > 0 && entry.2 <= lww_clock.max_safe_timestamp
    })
  {
    True ->
      case version {
        3 -> {
          let decoded =
            list.try_map(entries, fn(entry) {
              case entry.1 {
                None -> Ok(entry)
                Some(encoded) -> {
                  use child <- result.try(
                    crdt.from_json(encoded) |> result.replace_error(Nil),
                  )
                  use value <- result.try(string_value(child))
                  Ok(#(entry.0, Some(value), entry.2))
                }
              }
            })
          case decoded {
            Ok(entries) -> decode.success(entries)
            Error(Nil) -> decode.failure([], "String LWW register children")
          }
        }
        _ -> decode.success(entries)
      }
    False ->
      decode.failure(
        [],
        "unpruned LWW map with distinct keys and positive safe timestamps",
      )
  }
}

/// Validate raw entries before Lattice converts them to a dictionary.
/// Legacy v1/v2 snapshots are imported with their original String tie keys.
/// Modern writes use writer identity to break ties and emit v3 snapshots.
pub fn decoder() -> decode.Decoder(LWWMap) {
  use _ <- decode.then(metadata_decoder())
  use version <- decode.field("v", decode.int)
  use payload <- decode.then(json_ot.decoder())
  let encoded = json_ot.to_json(payload) |> json.to_string
  let decoded = case version {
    1 | 2 ->
      lww_map.import_legacy(
        encoded,
        crdt.LwwRegisterSpec(""),
        replica_id.new(""),
      )
    _ -> lww_map.from_json(encoded)
  }
  case decoded {
    Ok(map) ->
      case lww_map.spec(map) == crdt.LwwRegisterSpec("") {
        True -> decode.success(map)
        False -> decode.failure(map, "String LWW map with empty default")
      }
    Error(_) -> decode.failure(new_map(replica_id.new("")), "LWW map")
  }
}

fn metadata(
  map: LWWMap,
) -> Result(List(#(String, Option(String), Int)), KernelError) {
  use _ <- result.try(case lww_map.spec(map) == crdt.LwwRegisterSpec("") {
    True -> Ok(Nil)
    False -> Error(InvalidState("Expected String LWW map with empty default."))
  })
  case lww_map.pruned_timestamp(map) {
    0 ->
      json.parse(lww_map.to_json(map) |> json.to_string, metadata_decoder())
      |> result.map_error(DecodeError)
    timestamp -> Error(UnsupportedPruning(timestamp))
  }
}

fn observe(
  state: LwwMapState,
  map: LWWMap,
) -> Result(LwwMapState, KernelError) {
  use entries <- result.try(metadata(map))
  let clock =
    list.fold(entries, state.last_seen, fn(clock, entry) {
      let previous = dict.get(clock, entry.0) |> result.unwrap(0)
      dict.insert(clock, entry.0, int.max(previous, entry.2))
    })
  Ok(LwwMapState(..state, last_seen: clock))
}

fn events_between(
  before: LwwMapState,
  after: LwwMapState,
) -> List(LwwMapEvent) {
  list.append(keys(before), keys(after))
  |> list.unique
  |> list.sort(canonical_json.compare)
  |> list.filter_map(fn(key) {
    let previous = get(before, key) |> option.from_result
    let value = get(after, key) |> option.from_result
    case previous == value {
      True -> Error(Nil)
      False -> Ok(ValueChanged(key, previous, value))
    }
  })
}

fn operation_delta(operation: LwwMapOperation) -> LWWMap {
  case operation {
    Set(_, _, _, delta) | Remove(_, _, delta) -> delta
  }
}

/// Check the fragment and its intent together, including tombstone metadata.
pub fn validate_operation(
  operation: LwwMapOperation,
) -> Result(Nil, KernelError) {
  use entries <- result.try(metadata(operation_delta(operation)))
  let expected = case operation {
    Set(key, value, timestamp, _) -> #(key, Some(value), timestamp)
    Remove(key, timestamp, _) -> #(key, None, timestamp)
  }
  case entries == [expected] {
    True -> Ok(Nil)
    False ->
      Error(InvalidState("LWW map fragment does not match its operation"))
  }
}

fn next_timestamp(
  state: LwwMapState,
  key: String,
  wall_clock: Int,
) -> Result(Int, KernelError) {
  lww_clock.next(dict.get(state.last_seen, key) |> result.unwrap(0), wall_clock)
  |> result.map_error(Clock)
}

pub fn set(
  state: LwwMapState,
  key: String,
  value: String,
  wall_clock: Int,
) -> Result(
  #(LwwMapState, List(LwwMapEvent), LwwMapOperation, Int),
  KernelError,
) {
  use timestamp <- result.try(next_timestamp(state, key, wall_clock))
  use delta <- result.try(set_delta(state.replica_id, key, value, timestamp))
  apply_stashed_operation(state, Set(key, value, timestamp, delta))
}

pub fn remove(
  state: LwwMapState,
  key: String,
  wall_clock: Int,
) -> Result(
  #(LwwMapState, List(LwwMapEvent), LwwMapOperation, Int),
  KernelError,
) {
  use timestamp <- result.try(next_timestamp(state, key, wall_clock))
  use delta <- result.try(
    lww_map.remove(new_map(state.replica_id), key, timestamp)
    |> result.map_error(merge_error),
  )
  apply_stashed_operation(state, Remove(key, timestamp, delta))
}

pub fn p2p_set(
  state: LwwMapState,
  key: String,
  value: String,
  wall_clock: Int,
) -> Result(#(LwwMapState, List(LwwMapEvent), LwwMapOperation), KernelError) {
  use timestamp <- result.try(next_timestamp(state, key, wall_clock))
  use delta <- result.try(set_delta(state.replica_id, key, value, timestamp))
  use #(state, events) <- result.try(p2p_merge(state, delta))
  Ok(#(state, events, Set(key, value, timestamp, delta)))
}

pub fn p2p_remove(
  state: LwwMapState,
  key: String,
  wall_clock: Int,
) -> Result(#(LwwMapState, List(LwwMapEvent), LwwMapOperation), KernelError) {
  use timestamp <- result.try(next_timestamp(state, key, wall_clock))
  use delta <- result.try(
    lww_map.remove(new_map(state.replica_id), key, timestamp)
    |> result.map_error(merge_error),
  )
  use #(state, events) <- result.try(p2p_merge(state, delta))
  Ok(#(state, events, Remove(key, timestamp, delta)))
}

fn set_delta(
  replica: ReplicaId,
  key: String,
  value: String,
  timestamp: Int,
) -> Result(LWWMap, KernelError) {
  lww_map.set(
    new_map(replica),
    key,
    crdt.CrdtLwwRegister(lww_register.new(value, timestamp, replica)),
    timestamp,
  )
  |> result.map_error(merge_error)
}

pub fn apply_stashed_operation(
  state: LwwMapState,
  operation: LwwMapOperation,
) -> Result(
  #(LwwMapState, List(LwwMapEvent), LwwMapOperation, Int),
  KernelError,
) {
  use Nil <- result.try(validate_operation(operation))
  let delta = operation_delta(operation)
  use state <- result.try(observe(state, delta))
  use optimistic <- result.try(
    lww_map.merge(state.optimistic, delta) |> result.map_error(merge_error),
  )
  let message_id = state.next_pending_message_id
  let next =
    LwwMapState(
      ..state,
      optimistic: optimistic,
      pending: list.append(state.pending, [PendingOp(operation, message_id)]),
      next_pending_message_id: message_id + 1,
    )
  Ok(#(next, events_between(state, next), operation, message_id))
}

pub fn apply_remote(
  state: LwwMapState,
  operation: LwwMapOperation,
) -> Result(#(LwwMapState, List(LwwMapEvent)), KernelError) {
  use Nil <- result.try(validate_operation(operation))
  p2p_merge(state, operation_delta(operation))
}

pub fn p2p_merge(
  state: LwwMapState,
  other: LWWMap,
) -> Result(#(LwwMapState, List(LwwMapEvent)), KernelError) {
  use state <- result.try(observe(state, other))
  use sequenced <- result.try(
    lww_map.merge(state.sequenced, other) |> result.map_error(merge_error),
  )
  use optimistic <- result.try(
    lww_map.merge(state.optimistic, other) |> result.map_error(merge_error),
  )
  let next = LwwMapState(..state, sequenced: sequenced, optimistic: optimistic)
  Ok(#(next, events_between(state, next)))
}

pub fn ack_local(
  state: LwwMapState,
  operation: LwwMapOperation,
) -> Result(LwwMapState, KernelError) {
  do_ack(state, operation, None)
}

pub fn ack_local_with_message_id(
  state: LwwMapState,
  operation: LwwMapOperation,
  message_id: Int,
) -> Result(LwwMapState, KernelError) {
  do_ack(state, operation, Some(message_id))
}

fn do_ack(
  state: LwwMapState,
  operation: LwwMapOperation,
  expected_message_id: Option(Int),
) -> Result(LwwMapState, KernelError) {
  case state.pending {
    [] -> Error(UnexpectedAck(operation, "pending queue is empty"))
    [PendingOp(expected, message_id), ..rest] -> {
      let id_matches = case expected_message_id {
        None -> True
        Some(actual) -> actual == message_id
      }
      case operation == expected && id_matches {
        False ->
          Error(UnexpectedAck(
            operation,
            "ack does not match oldest pending operation",
          ))
        True -> {
          use Nil <- result.try(validate_operation(operation))
          let delta = operation_delta(operation)
          use state <- result.try(observe(state, delta))
          use sequenced <- result.try(
            lww_map.merge(state.sequenced, delta)
            |> result.map_error(merge_error),
          )
          Ok(LwwMapState(..state, sequenced: sequenced, pending: rest))
        }
      }
    }
  }
}

pub fn rollback(
  state: LwwMapState,
  operation: LwwMapOperation,
  message_id: Int,
) -> Result(#(LwwMapState, List(LwwMapEvent)), KernelError) {
  case list.reverse(state.pending) {
    [] -> Error(UnexpectedRollback(operation, "pending queue is empty"))
    [PendingOp(expected, expected_id), ..rest] ->
      case operation == expected && message_id == expected_id {
        False ->
          Error(UnexpectedRollback(
            operation,
            "rollback does not match newest pending operation",
          ))
        True -> {
          let pending = list.reverse(rest)
          use optimistic <- result.try(replay(state.sequenced, pending))
          let next =
            LwwMapState(..state, pending: pending, optimistic: optimistic)
          Ok(#(next, events_between(state, next)))
        }
      }
  }
}

fn replay(
  sequenced: LWWMap,
  pending: List(PendingOp),
) -> Result(LWWMap, KernelError) {
  list.try_fold(pending, sequenced, fn(map, pending) {
    lww_map.merge(map, operation_delta(pending.operation))
    |> result.map_error(merge_error)
  })
}

pub fn promote_attach(state: LwwMapState) -> LwwMapState {
  LwwMapState(..state, sequenced: state.optimistic, pending: [])
}

pub fn summary(state: LwwMapState) -> Json {
  lww_map.to_json(state.sequenced)
}

pub fn from_summary(
  source: String,
  replica_id: ReplicaId,
) -> Result(LwwMapState, KernelError) {
  use map <- result.try(
    json.parse(source, decoder()) |> result.map_error(DecodeError),
  )
  from_sequenced(map, replica_id)
}

pub fn from_sequenced(
  map: LWWMap,
  replica_id: ReplicaId,
) -> Result(LwwMapState, KernelError) {
  let map = lww_map.bind(map, replica_id)
  observe(LwwMapState(..new(replica_id), sequenced: map, optimistic: map), map)
}

pub fn check_cache_coherence(state: LwwMapState) -> Result(Nil, String) {
  use optimistic <- result.try(
    replay(state.sequenced, state.pending) |> result.map_error(string.inspect),
  )
  case optimistic == state.optimistic {
    True -> Ok(Nil)
    False ->
      Error("optimistic LWWMap cache does not match sequenced plus pending")
  }
}
