//// The oracle selects a winner from routed timestamps and log authors.
//// It does not read deltas or use the lattice merge or digest helpers.

import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string
import lattice_core/replica_id
import lattice_registers/lww_register.{type LWWRegister}
import qcheck
import watershed/fuzz/kernel_fuzz.{
  type KernelModel, type LogEntry, Capabilities, KernelModel,
}
import watershed/lww_register_kernel as kernel

pub type LwwCommand {
  LwwCommand(
    value: String,
    wall_clock: Int,
    timestamp: Option(Int),
    delta: Option(LWWRegister(String)),
  )
}

pub type Observation {
  Observation(value: String, timestamp: Int, author: String)
}

fn client_author(id: Int) -> String {
  "client-" <> int.to_string(id)
}

fn operation(command: LwwCommand) -> kernel.LwwRegisterOperation {
  case command.timestamp, command.delta {
    Some(timestamp), Some(delta) -> kernel.Set(command.value, timestamp, delta)
    _, _ -> panic as "routed LWW-register command has no timestamp or delta"
  }
}

fn observe(state: kernel.LwwRegisterState) -> Observation {
  let decoder =
    decode.at(["state"], {
      use value <- decode.field("value", decode.string)
      use timestamp <- decode.field("timestamp", decode.int)
      use author <- decode.field("replica_id", decode.string)
      decode.success(Observation(value, timestamp, author))
    })
  // Summaries omit pending writes. Ack transparency needs optimistic metadata.
  let assert Ok(observation) =
    json.parse(
      lww_register.to_json(state.optimistic) |> json.to_string,
      decoder,
    )
  observation
}

fn oracle(entries: List(LogEntry(LwwCommand))) -> Observation {
  kernel_fuzz.log_operations(entries)
  |> list.fold(Observation("", 0, ""), fn(winner, entry) {
    let #(client, command) = entry
    let assert Some(timestamp) = command.timestamp
    let author = client_author(client)
    case
      timestamp > winner.timestamp
      || {
        timestamp == winner.timestamp
        && string.compare(author, winner.author) == order.Gt
      }
    {
      True -> Observation(command.value, timestamp, author)
      False -> winner
    }
  })
}

fn submit(
  state: kernel.LwwRegisterState,
  command: LwwCommand,
  _meta: kernel_fuzz.SubmitMeta,
) -> #(kernel.LwwRegisterState, Option(LwwCommand)) {
  let assert Ok(#(state, _, kernel.Set(value, timestamp, delta), _)) =
    kernel.set(state, command.value, command.wall_clock)
  #(
    state,
    Some(LwwCommand(value, command.wall_clock, Some(timestamp), Some(delta))),
  )
}

fn rollback(
  state: kernel.LwwRegisterState,
  command: LwwCommand,
) -> kernel.LwwRegisterState {
  let assert Ok(pending) = list.last(state.pending)
  let assert Ok(#(state, _)) =
    kernel.rollback(state, operation(command), pending.message_id)
  state
}

fn apply_stashed(
  state: kernel.LwwRegisterState,
  command: LwwCommand,
  meta: kernel_fuzz.SubmitMeta,
) -> #(kernel.LwwRegisterState, LwwCommand) {
  let command = case command.timestamp, command.delta {
    None, None -> {
      // Generated stashes have no captured operation. Prepare one once in a
      // discarded state, then replay it through the real stash lifecycle.
      let #(_, routed) = submit(state, command, meta)
      let assert Some(prepared) = routed
      prepared
    }
    Some(_), Some(_) -> command
    _, _ -> panic as "stashed LWW-register command has incomplete metadata"
  }
  let assert Ok(#(state, _, _, _)) =
    kernel.apply_stashed_operation(state, operation(command))
  #(state, command)
}

fn encode(command: LwwCommand) -> json.Json {
  json.object([
    #("value", json.string(command.value)),
    #("wall_clock", json.int(command.wall_clock)),
    #("timestamp", case command.timestamp {
      None -> json.null()
      Some(timestamp) -> json.int(timestamp)
    }),
    #("delta", case command.delta {
      None -> json.null()
      Some(delta) ->
        lww_register.to_json(delta) |> json.to_string |> json.string
    }),
  ])
}

fn decoder() -> decode.Decoder(LwwCommand) {
  use value <- decode.field("value", decode.string)
  use wall_clock <- decode.field("wall_clock", decode.int)
  use timestamp <- decode.field("timestamp", decode.optional(decode.int))
  use delta <- decode.field("delta", decode.optional(decode.string))
  let empty = LwwCommand(value, wall_clock, None, None)
  case timestamp, delta {
    None, None -> decode.success(empty)
    Some(timestamp), Some(encoded) ->
      case lww_register.from_json(encoded) {
        Ok(delta) ->
          decode.success(LwwCommand(
            value,
            wall_clock,
            Some(timestamp),
            Some(delta),
          ))
        Error(_) -> decode.failure(empty, "LWW-register delta")
      }
    _, _ -> decode.failure(empty, "both timestamp and delta, or neither")
  }
}

fn operation_generator() -> qcheck.Generator(LwwCommand) {
  qcheck.tuple2(
    qcheck.small_non_negative_int(),
    qcheck.bounded_int(from: 0, to: 7),
  )
  |> qcheck.map(fn(pair) {
    let value = case pair.0 % 3 {
      0 -> ""
      1 -> "same"
      _ -> "next"
    }
    LwwCommand(value, pair.1, None, None)
  })
}

pub fn model() -> KernelModel(kernel.LwwRegisterState, LwwCommand, Observation) {
  KernelModel(
    name: "lww_register",
    init: fn(id) { kernel.new(replica_id.new(client_author(id))) },
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
            replica_id.new(client_author(id)),
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
