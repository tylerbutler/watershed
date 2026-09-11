//// A string-valued LWW map with retained tombstones and per-key clocks.

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import lattice_core/replica_id.{type ReplicaId}
import lattice_maps/lww_map.{type LWWMap}
import watershed/canonical_json
import watershed/lww_clock

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
  LwwMapState(replica_id, lww_map.new(), lww_map.new(), [], 0, dict.new())
}

pub fn get(state: LwwMapState, key: String) -> Result(String, Nil) {
  lww_map.get(state.optimistic, key)
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
    lww_map.get(map, key) |> result.map(fn(value) { #(key, value) })
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
    && { version == 1 || version == 2 }
    && watermark == 0
    && distinct == list.length(entries)
    && list.all(entries, fn(entry) {
      entry.2 > 0 && entry.2 <= lww_clock.max_safe_timestamp
    })
  {
    True -> decode.success(entries)
    False ->
      decode.failure(
        [],
        "unpruned LWW map v1/v2 with distinct keys and positive safe timestamps",
      )
  }
}

/// Validate raw entries before Lattice converts them to a dictionary.
/// A v1 envelope may omit the watermark, but cannot supply a nonzero one.
pub fn decoder() -> decode.Decoder(LWWMap) {
  use entries <- decode.then(metadata_decoder())
  let encoded =
    json.object([
      #("type", json.string("lww_map")),
      #("v", json.int(2)),
      #(
        "state",
        json.object([
          #("pruned_timestamp", json.int(0)),
          #(
            "entries",
            json.array(entries, fn(entry) {
              json.object([
                #("key", json.string(entry.0)),
                #("value", case entry.1 {
                  None -> json.null()
                  Some(value) -> json.string(value)
                }),
                #("timestamp", json.int(entry.2)),
              ])
            }),
          ),
        ]),
      ),
    ])
    |> json.to_string
  case lww_map.from_json(encoded) {
    Ok(map) -> decode.success(map)
    Error(_) -> decode.failure(lww_map.new(), "LWW map")
  }
}

fn metadata(
  map: LWWMap,
) -> Result(List(#(String, Option(String), Int)), KernelError) {
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
  let delta = lww_map.set(lww_map.new(), key, value, timestamp)
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
  let delta = lww_map.remove(lww_map.new(), key, timestamp)
  apply_stashed_operation(state, Remove(key, timestamp, delta))
}

pub fn p2p_set(
  state: LwwMapState,
  key: String,
  value: String,
  wall_clock: Int,
) -> Result(#(LwwMapState, List(LwwMapEvent), LwwMapOperation), KernelError) {
  use timestamp <- result.try(next_timestamp(state, key, wall_clock))
  let delta = lww_map.set(lww_map.new(), key, value, timestamp)
  use #(state, events) <- result.try(p2p_merge(state, delta))
  Ok(#(state, events, Set(key, value, timestamp, delta)))
}

pub fn p2p_remove(
  state: LwwMapState,
  key: String,
  wall_clock: Int,
) -> Result(#(LwwMapState, List(LwwMapEvent), LwwMapOperation), KernelError) {
  use timestamp <- result.try(next_timestamp(state, key, wall_clock))
  let delta = lww_map.remove(lww_map.new(), key, timestamp)
  use #(state, events) <- result.try(p2p_merge(state, delta))
  Ok(#(state, events, Remove(key, timestamp, delta)))
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
  let message_id = state.next_pending_message_id
  let next =
    LwwMapState(
      ..state,
      optimistic: lww_map.merge(state.optimistic, delta),
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
  let next =
    LwwMapState(
      ..state,
      sequenced: lww_map.merge(state.sequenced, other),
      optimistic: lww_map.merge(state.optimistic, other),
    )
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
          Ok(
            LwwMapState(
              ..state,
              sequenced: lww_map.merge(state.sequenced, delta),
              pending: rest,
            ),
          )
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
          let next =
            LwwMapState(
              ..state,
              pending: pending,
              optimistic: replay(state.sequenced, pending),
            )
          Ok(#(next, events_between(state, next)))
        }
      }
  }
}

fn replay(sequenced: LWWMap, pending: List(PendingOp)) -> LWWMap {
  list.fold(pending, sequenced, fn(map, pending) {
    lww_map.merge(map, operation_delta(pending.operation))
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
  observe(LwwMapState(..new(replica_id), sequenced: map, optimistic: map), map)
}

pub fn check_cache_coherence(state: LwwMapState) -> Result(Nil, String) {
  case replay(state.sequenced, state.pending) == state.optimistic {
    True -> Ok(Nil)
    False ->
      Error("optimistic LWWMap cache does not match sequenced plus pending")
  }
}
