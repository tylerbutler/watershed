//// The oracle selects per-key winners from intent and routed timestamps.
//// It reads only captured write provenance from deltas and never calls merge.

import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string
import lattice_core/replica_id
import lattice_maps/crdt
import lattice_maps/lww_map
import lattice_registers/lww_register
import qcheck
import watershed/canonical_json
import watershed/fuzz/kernel_fuzz.{
  type KernelModel, type LogEntry, Capabilities, KernelModel,
}
import watershed/lww_map_kernel as kernel

pub type MapCommand {
  MapCommand(
    key: String,
    value: Option(String),
    wall_clock: Int,
    timestamp: Option(Int),
    delta: Option(kernel.LWWMap),
  )
}

pub type Observation =
  List(#(String, Option(String), Int))

fn operation(command: MapCommand) -> kernel.LwwMapOperation {
  let assert Some(timestamp) = command.timestamp
  let assert Some(delta) = command.delta
  case command.value {
    Some(value) -> kernel.Set(command.key, value, timestamp, delta)
    None -> kernel.Remove(command.key, timestamp, delta)
  }
}

fn routed(
  command: MapCommand,
  operation: kernel.LwwMapOperation,
) -> MapCommand {
  let #(timestamp, delta) = case operation {
    kernel.Set(_, _, timestamp, delta) | kernel.Remove(_, timestamp, delta) -> #(
      timestamp,
      delta,
    )
  }
  MapCommand(..command, timestamp: Some(timestamp), delta: Some(delta))
}

fn observe(state: kernel.LwwMapState) -> Observation {
  let decoder =
    decode.at(
      ["state", "entries"],
      decode.list({
        use key <- decode.field("key", decode.string)
        use value <- decode.field("value", decode.optional(decode.string))
        use timestamp <- decode.field("timestamp", decode.int)
        decode.success(#(key, value, timestamp))
      }),
    )
  let assert Ok(entries) =
    json.parse(lww_map.to_json(state.optimistic) |> json.to_string, decoder)
  entries
  |> list.map(fn(entry) {
    let value = case entry.1 {
      None -> None
      Some(encoded) -> {
        let assert Ok(crdt.CrdtLwwRegister(register)) = crdt.from_json(encoded)
        Some(lww_register.value(register))
      }
    }
    #(entry.0, value, entry.2)
  })
  |> list.sort(fn(a, b) { canonical_json.compare(a.0, b.0) })
}

fn winner(
  previous: #(Option(String), Int, String),
  incoming: #(Option(String), Int, String),
) -> #(Option(String), Int, String) {
  case int.compare(incoming.1, previous.1) {
    order.Gt -> incoming
    order.Lt -> previous
    order.Eq ->
      case previous.0, incoming.0 {
        None, _ -> previous
        _, None -> incoming
        Some(_), Some(_) ->
          case canonical_json.compare(previous.2, incoming.2) {
            order.Lt -> incoming
            order.Eq | order.Gt -> previous
          }
      }
  }
}

fn identity(command: MapCommand, author: Int) -> String {
  case command.delta {
    None -> "client-" <> int.to_string(author)
    Some(delta) -> {
      let decoder =
        decode.at(
          ["state", "entries"],
          decode.list(
            decode.at(["provenance"], {
              use writer <- decode.field("writer", decode.string)
              decode.success(writer)
            }),
          ),
        )
      let assert Ok([identity]) =
        json.parse(lww_map.to_json(delta) |> json.to_string, decoder)
      identity
    }
  }
}

fn oracle(entries: List(LogEntry(MapCommand))) -> Observation {
  kernel_fuzz.log_operations(entries)
  |> list.fold(dict.new(), fn(winners, entry) {
    let #(author, command) = entry
    let assert Some(timestamp) = command.timestamp
    let incoming = #(command.value, timestamp, identity(command, author))
    let next = case dict.get(winners, command.key) {
      Error(Nil) -> incoming
      Ok(previous) -> winner(previous, incoming)
    }
    dict.insert(winners, command.key, next)
  })
  |> dict.to_list
  |> list.map(fn(entry) { #(entry.0, entry.1.0, entry.1.1) })
  |> list.sort(fn(a, b) { canonical_json.compare(a.0, b.0) })
}

fn submit(
  state: kernel.LwwMapState,
  command: MapCommand,
  _meta: kernel_fuzz.SubmitMeta,
) -> #(kernel.LwwMapState, Option(MapCommand)) {
  let applied = case command.value {
    Some(value) -> kernel.set(state, command.key, value, command.wall_clock)
    None -> kernel.remove(state, command.key, command.wall_clock)
  }
  let assert Ok(#(state, _, operation, _)) = applied
  #(state, Some(routed(command, operation)))
}

fn rollback(
  state: kernel.LwwMapState,
  command: MapCommand,
) -> kernel.LwwMapState {
  let assert Ok(pending) = list.last(state.pending)
  let assert Ok(#(state, _)) =
    kernel.rollback(state, operation(command), pending.message_id)
  state
}

fn apply_stashed(
  state: kernel.LwwMapState,
  command: MapCommand,
  _meta: kernel_fuzz.SubmitMeta,
) -> #(kernel.LwwMapState, MapCommand) {
  let command = case command.timestamp, command.delta {
    None, None -> {
      // Model an original write from an empty clock, not the replay clock.
      let timestamp = int.max(1, command.wall_clock)
      // Distinct captured intents cannot reuse an immutable write ID.
      let replica = replica_id.new("stash:" <> json.to_string(encode(command)))
      let map = lww_map.new(replica, crdt.LwwRegisterSpec(""))
      let assert Ok(delta) = case command.value {
        Some(value) ->
          lww_map.set(
            map,
            command.key,
            crdt.CrdtLwwRegister(lww_register.new(value, timestamp, replica)),
            timestamp,
          )
        None -> lww_map.remove(map, command.key, timestamp)
      }
      MapCommand(..command, timestamp: Some(timestamp), delta: Some(delta))
    }
    Some(_), Some(_) -> command
    _, _ -> panic as "stashed LWW-map command has incomplete metadata"
  }
  let assert Ok(#(state, _, _, _)) =
    kernel.apply_stashed_operation(state, operation(command))
  #(state, command)
}

fn encode(command: MapCommand) -> json.Json {
  json.object([
    #("key", json.string(command.key)),
    #("value", case command.value {
      None -> json.null()
      Some(value) -> json.string(value)
    }),
    #("wall_clock", json.int(command.wall_clock)),
    #("timestamp", case command.timestamp {
      None -> json.null()
      Some(timestamp) -> json.int(timestamp)
    }),
    #("delta", case command.delta {
      None -> json.null()
      Some(delta) -> lww_map.to_json(delta) |> json.to_string |> json.string
    }),
  ])
}

fn decoder() -> decode.Decoder(MapCommand) {
  use key <- decode.field("key", decode.string)
  use value <- decode.field("value", decode.optional(decode.string))
  use wall_clock <- decode.field("wall_clock", decode.int)
  use timestamp <- decode.field("timestamp", decode.optional(decode.int))
  use delta <- decode.field("delta", decode.optional(decode.string))
  let empty = MapCommand(key, value, wall_clock, None, None)
  case timestamp, delta {
    None, None -> decode.success(empty)
    Some(timestamp), Some(encoded) ->
      case json.parse(encoded, kernel.decoder()) {
        Error(_) -> decode.failure(empty, "LWW-map delta")
        Ok(delta) -> {
          let command =
            MapCommand(key, value, wall_clock, Some(timestamp), Some(delta))
          case kernel.validate_operation(operation(command)) {
            Ok(Nil) -> decode.success(command)
            Error(_) -> decode.failure(empty, "matching LWW-map intent")
          }
        }
      }
    _, _ -> decode.failure(empty, "both timestamp and delta, or neither")
  }
}

fn operation_generator() -> qcheck.Generator(MapCommand) {
  qcheck.tuple2(
    qcheck.small_non_negative_int(),
    qcheck.bounded_int(from: 0, to: 7),
  )
  |> qcheck.map(fn(pair) {
    let key = case pair.0 % 3 {
      0 -> "k"
      1 -> "a"
      _ -> ""
    }
    let value = case { pair.0 / 3 } % 4 {
      0 -> None
      1 -> Some("")
      2 -> Some("closed")
      _ -> Some("open")
    }
    MapCommand(key, value, pair.1, None, None)
  })
}

pub fn model() -> KernelModel(kernel.LwwMapState, MapCommand, Observation) {
  KernelModel(
    name: "lww_map",
    init: fn(id) { kernel.new(replica_id.new("client-" <> int.to_string(id))) },
    submit: submit,
    apply_remote: fn(state, command, _) {
      kernel.apply_remote(state, operation(command))
      |> result.map(fn(applied) { applied.0 })
      |> result.map_error(string.inspect)
    },
    ack_local: fn(state, command, _) {
      kernel.ack_local(state, operation(command))
      |> result.map_error(string.inspect)
    },
    observe: observe,
    gen_operation: operation_generator(),
    check: Some(kernel.check_cache_coherence),
    canonicalize: None,
    ack_preserves_view: True,
    operation_to_json: encode,
    operation_decoder: decoder(),
    capabilities: Capabilities(
      load_from_synced: Some(fn(state, id) {
        let assert Ok(loaded) =
          kernel.from_summary(
            kernel.summary(state) |> json.to_string,
            replica_id.new("client-" <> int.to_string(id)),
          )
        loaded
      }),
      oracle: Some(oracle),
      rollback: Some(rollback),
      resubmit: None,
      apply_stashed: Some(apply_stashed),
      react: None,
      remove_member: None,
    ),
  )
}
