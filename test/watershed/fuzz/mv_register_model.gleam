//// The oracle retains a logged write unless another write observed its tag.
//// It does not use the lattice merge or the production digest projection.

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string
import lattice_core/replica_id
import lattice_registers/mv_register.{type MVRegister}
import qcheck
import watershed/fuzz/kernel_fuzz.{
  type KernelModel, type LogEntry, Capabilities, KernelModel,
}
import watershed/mv_register_kernel as mv

pub type MvCommand {
  MvCommand(value: String, delta: Option(MVRegister(String)))
}

pub type Observation {
  Observation(
    values: List(String),
    entries: List(#(String, Int, String)),
    clock: List(#(String, Int)),
  )
}

fn replica(id: Int) -> replica_id.ReplicaId {
  replica_id.new("client-" <> int.to_string(id))
}

fn operation(command: MvCommand) -> mv.MvRegisterOperation {
  case command.delta {
    Some(delta) -> mv.Set(command.value, delta)
    None -> panic as "routed MV-register command has no delta"
  }
}

fn metadata(
  register: MVRegister(String),
) -> #(List(#(String, Int, String)), Dict(String, Int)) {
  let decoder = {
    use state <- decode.field("state", {
      use entries <- decode.field(
        "entries",
        decode.list({
          use tag <- decode.field("tag", {
            use replica <- decode.field("r", decode.string)
            use counter <- decode.field("c", decode.int)
            decode.success(#(replica, counter))
          })
          use value <- decode.field("value", decode.string)
          decode.success(#(tag.0, tag.1, value))
        }),
      )
      use clock <- decode.field(
        "vclock",
        decode.dict(decode.string, decode.int),
      )
      decode.success(#(entries, clock))
    })
    decode.success(state)
  }
  let assert Ok(metadata) =
    json.parse(mv_register.to_json(register) |> json.to_string, decoder)
  metadata
}

fn observation(
  entries: List(#(String, Int, String)),
  clock: Dict(String, Int),
) -> Observation {
  Observation(
    values: list.map(entries, fn(entry) { entry.2 })
      |> list.sort(string.compare),
    entries: list.sort(entries, fn(a, b) {
      case string.compare(a.0, b.0) {
        order.Eq -> int.compare(a.1, b.1)
        other -> other
      }
    }),
    clock: dict.to_list(clock)
      |> list.sort(fn(a, b) { string.compare(a.0, b.0) }),
  )
}

fn observe(state: mv.MvRegisterState) -> Observation {
  let #(entries, clock) = metadata(state.optimistic)
  observation(entries, clock)
}

fn oracle(log: List(LogEntry(MvCommand))) -> Observation {
  let writes =
    kernel_fuzz.log_operations(log)
    |> list.map(fn(entry) {
      let #(entries, clock) = metadata(operation(entry.1).delta)
      let assert [tagged] = entries
      #(tagged, clock)
    })
    |> list.unique
  let survivors =
    list.filter(writes, fn(write) {
      let #(tag, _) = write
      !list.any(writes, fn(other) {
        let #(other_tag, observed) = other
        #(other_tag.0, other_tag.1) != #(tag.0, tag.1)
        && result.unwrap(dict.get(observed, tag.0), 0) >= tag.1
      })
    })
    |> list.map(fn(write) { write.0 })
    |> list.unique
  let clock =
    list.fold(writes, dict.new(), fn(clock, write) {
      dict.fold(write.1, clock, fn(clock, replica, count) {
        dict.insert(
          clock,
          replica,
          int.max(count, result.unwrap(dict.get(clock, replica), 0)),
        )
      })
    })
  observation(survivors, clock)
}

fn submit(
  state: mv.MvRegisterState,
  command: MvCommand,
  _meta: kernel_fuzz.SubmitMeta,
) -> #(mv.MvRegisterState, Option(MvCommand)) {
  let #(state, _, operation, _) = mv.set(state, command.value)
  #(state, Some(MvCommand(command.value, Some(operation.delta))))
}

fn apply_stashed(
  state: mv.MvRegisterState,
  command: MvCommand,
  meta: kernel_fuzz.SubmitMeta,
) -> #(mv.MvRegisterState, MvCommand) {
  case command.delta {
    None -> {
      let #(state, submitted) = submit(state, command, meta)
      let assert Some(submitted) = submitted
      #(state, submitted)
    }
    Some(_) -> {
      let #(state, _, _, _) =
        mv.apply_stashed_operation(state, operation(command))
      #(state, command)
    }
  }
}

fn error_detail(error: mv.KernelError) -> String {
  case error {
    mv.UnexpectedAck(_, detail) | mv.UnexpectedRollback(_, detail) -> detail
  }
}

fn rollback(
  state: mv.MvRegisterState,
  command: MvCommand,
) -> mv.MvRegisterState {
  let assert Ok(pending) = list.last(state.pending)
  let assert Ok(#(state, _)) =
    mv.rollback(state, operation(command), pending.message_id)
  state
}

fn encode(command: MvCommand) -> json.Json {
  json.object([
    #("value", json.string(command.value)),
    #("delta", case command.delta {
      None -> json.null()
      Some(delta) -> mv_register.to_json(delta) |> json.to_string |> json.string
    }),
  ])
}

fn decoder() -> decode.Decoder(MvCommand) {
  use value <- decode.field("value", decode.string)
  use delta <- decode.field("delta", decode.optional(decode.string))
  case delta {
    None -> decode.success(MvCommand(value, None))
    Some(encoded) ->
      case mv.decode_crdt(encoded) {
        Ok(delta) -> decode.success(MvCommand(value, Some(delta)))
        Error(_) -> decode.failure(MvCommand(value, None), "MV-register delta")
      }
  }
}

pub fn model() -> KernelModel(mv.MvRegisterState, MvCommand, Observation) {
  KernelModel(
    name: "mv_register",
    init: fn(id) { mv.new(replica(id)) },
    submit: submit,
    apply_remote: fn(state, command, _) {
      let #(state, _) = mv.apply_remote(state, operation(command))
      Ok(state)
    },
    ack_local: fn(state, command, _) {
      mv.ack_local(state, operation(command)) |> result.map_error(error_detail)
    },
    observe: observe,
    gen_operation: qcheck.small_non_negative_int()
      |> qcheck.map(fn(n) { MvCommand(int.to_string(n % 4), None) }),
    check: Some(mv.check_cache_coherence),
    canonicalize: None,
    ack_preserves_view: True,
    operation_to_json: encode,
    operation_decoder: decoder(),
    capabilities: Capabilities(
      load_from_synced: Some(fn(state, id) {
        let assert Ok(loaded) =
          mv.from_summary(mv.summary(state) |> json.to_string, replica(id))
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
