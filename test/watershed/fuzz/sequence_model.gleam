import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import lattice_core/replica_id
import lattice_sequence/sequence.{type Sequence}
import qcheck
import watershed/fuzz/kernel_fuzz.{type KernelModel, Capabilities, KernelModel}
import watershed/sequence_kernel
import watershed/wire

pub type SequenceCommand {
  InsertCommand(index_seed: Int, value: String, delta: Option(Sequence(Json)))
  DeleteCommand(index_seed: Int, delta: Option(Sequence(Json)))
  MoveCommand(from_seed: Int, to_seed: Int, delta: Option(Sequence(Json)))
  ReplaceCommand(index_seed: Int, value: String, delta: Option(Sequence(Json)))
}

fn delta_to_json(delta: Option(Sequence(Json))) -> Json {
  case delta {
    None -> json.null()
    Some(delta) ->
      json.string(json.to_string(sequence.to_json(delta, fn(value) { value })))
  }
}

fn delta_decoder() -> decode.Decoder(Option(Sequence(Json))) {
  decode.optional(decode.string)
  |> decode.then(fn(maybe_encoded) {
    case maybe_encoded {
      None -> decode.success(None)
      Some(encoded) ->
        case sequence.from_json(encoded, wire.json_value_decoder()) {
          Ok(delta) -> decode.success(Some(delta))
          Error(_) -> decode.failure(None, "sequence delta")
        }
    }
  })
}

fn op_to_json(command: SequenceCommand) -> Json {
  case command {
    InsertCommand(index_seed, value, delta) ->
      json.object([
        #("tag", json.string("Insert")),
        #("index_seed", json.int(index_seed)),
        #("value", json.string(value)),
        #("delta", delta_to_json(delta)),
      ])
    DeleteCommand(index_seed, delta) ->
      json.object([
        #("tag", json.string("Delete")),
        #("index_seed", json.int(index_seed)),
        #("delta", delta_to_json(delta)),
      ])
    MoveCommand(from_seed, to_seed, delta) ->
      json.object([
        #("tag", json.string("Move")),
        #("from_seed", json.int(from_seed)),
        #("to_seed", json.int(to_seed)),
        #("delta", delta_to_json(delta)),
      ])
    ReplaceCommand(index_seed, value, delta) ->
      json.object([
        #("tag", json.string("Replace")),
        #("index_seed", json.int(index_seed)),
        #("value", json.string(value)),
        #("delta", delta_to_json(delta)),
      ])
  }
}

fn op_decoder() -> decode.Decoder(SequenceCommand) {
  use tag <- decode.field("tag", decode.string)
  case tag {
    "Insert" -> {
      use index_seed <- decode.field("index_seed", decode.int)
      use value <- decode.field("value", decode.string)
      use delta <- decode.field("delta", delta_decoder())
      decode.success(InsertCommand(index_seed, value, delta))
    }
    "Delete" -> {
      use index_seed <- decode.field("index_seed", decode.int)
      use delta <- decode.field("delta", delta_decoder())
      decode.success(DeleteCommand(index_seed, delta))
    }
    "Move" -> {
      use from_seed <- decode.field("from_seed", decode.int)
      use to_seed <- decode.field("to_seed", decode.int)
      use delta <- decode.field("delta", delta_decoder())
      decode.success(MoveCommand(from_seed, to_seed, delta))
    }
    "Replace" -> {
      use index_seed <- decode.field("index_seed", decode.int)
      use value <- decode.field("value", decode.string)
      use delta <- decode.field("delta", delta_decoder())
      decode.success(ReplaceCommand(index_seed, value, delta))
    }
    _ -> decode.failure(InsertCommand(0, "", None), "sequence command")
  }
}

fn op_generator() -> qcheck.Generator(SequenceCommand) {
  qcheck.tuple4(
    qcheck.small_non_negative_int(),
    qcheck.small_non_negative_int(),
    qcheck.small_non_negative_int(),
    qcheck.small_non_negative_int(),
  )
  |> qcheck.map(fn(parts) {
    let value = "v" <> int.to_string(parts.3 % 5)
    case parts.0 % 4 {
      0 -> InsertCommand(parts.1, value, None)
      1 -> DeleteCommand(parts.1, None)
      2 -> MoveCommand(parts.1, parts.2, None)
      _ -> ReplaceCommand(parts.1, value, None)
    }
  })
}

fn fallback_value(seed: Int) -> String {
  "v" <> int.to_string(seed % 5)
}

fn routed_value(value: String) -> Json {
  json.string(value)
}

fn command_value(value: String, context: String) -> Json {
  case json.parse(value, wire.json_value_decoder()) {
    Ok(value) -> value
    Error(_) ->
      panic as { context <> " received a command value that is not JSON" }
  }
}

fn command_to_kernel_op(
  command: SequenceCommand,
  context: String,
) -> sequence_kernel.SequenceOp {
  case command {
    InsertCommand(index, value, Some(delta)) ->
      sequence_kernel.Insert(index, command_value(value, context), delta)
    DeleteCommand(index, Some(delta)) -> sequence_kernel.Delete(index, delta)
    MoveCommand(from, to, Some(delta)) -> sequence_kernel.Move(from, to, delta)
    ReplaceCommand(index, value, Some(delta)) ->
      sequence_kernel.Replace(index, command_value(value, context), delta)
    InsertCommand(_, _, None)
    | DeleteCommand(_, None)
    | MoveCommand(_, _, None)
    | ReplaceCommand(_, _, None) ->
      panic as {
        context
        <> " received an op without a delta — submit/apply_stashed must rewrite ops before routing"
      }
  }
}

fn submit_insert(
  state: sequence_kernel.SequenceState,
  index_seed: Int,
  command_value: String,
) -> #(sequence_kernel.SequenceState, Option(SequenceCommand)) {
  let index = index_seed % { sequence_kernel.length(state) + 1 }
  let value = routed_value(command_value)
  let assert Ok(#(state, _, op, _)) =
    sequence_kernel.insert(state, index, value)
  let assert sequence_kernel.Insert(index, value, delta) = op
  #(state, Some(InsertCommand(index, json.to_string(value), Some(delta))))
}

fn submit(
  state: sequence_kernel.SequenceState,
  command: SequenceCommand,
  _meta: kernel_fuzz.SubmitMeta,
) -> #(sequence_kernel.SequenceState, Option(SequenceCommand)) {
  let length = sequence_kernel.length(state)
  case command {
    InsertCommand(index_seed, value, _) ->
      submit_insert(state, index_seed, value)
    DeleteCommand(index_seed, _) ->
      case length == 0 {
        True -> submit_insert(state, index_seed, fallback_value(index_seed))
        False -> {
          let index = index_seed % length
          let assert Ok(#(state, _, op, _)) =
            sequence_kernel.delete(state, index)
          let assert sequence_kernel.Delete(index, delta) = op
          #(state, Some(DeleteCommand(index, Some(delta))))
        }
      }
    MoveCommand(from_seed, to_seed, _) ->
      case length == 0 {
        True -> submit_insert(state, from_seed, fallback_value(from_seed))
        False -> {
          let from = from_seed % length
          let to = to_seed % length
          let assert Ok(#(state, _, op, _)) =
            sequence_kernel.move(state, from, to)
          let assert sequence_kernel.Move(from, to, delta) = op
          #(state, Some(MoveCommand(from, to, Some(delta))))
        }
      }
    ReplaceCommand(index_seed, value, _) ->
      case length == 0 {
        True -> submit_insert(state, index_seed, value)
        False -> {
          let index = index_seed % length
          let value = routed_value(value)
          let assert Ok(#(state, _, op, _)) =
            sequence_kernel.replace(state, index, value)
          let assert sequence_kernel.Replace(index, value, delta) = op
          #(
            state,
            Some(ReplaceCommand(index, json.to_string(value), Some(delta))),
          )
        }
      }
  }
}

fn apply_remote(
  state: sequence_kernel.SequenceState,
  command: SequenceCommand,
  _meta: kernel_fuzz.SequencedMeta,
) -> Result(sequence_kernel.SequenceState, String) {
  let #(state, _) =
    sequence_kernel.apply_remote(
      state,
      command_to_kernel_op(command, "apply_remote"),
    )
  Ok(state)
}

fn ack_local(
  state: sequence_kernel.SequenceState,
  command: SequenceCommand,
  _meta: kernel_fuzz.SequencedMeta,
) -> Result(sequence_kernel.SequenceState, String) {
  case
    sequence_kernel.ack_local(state, command_to_kernel_op(command, "ack_local"))
  {
    Ok(state) -> Ok(state)
    Error(sequence_kernel.UnexpectedAck(detail))
    | Error(sequence_kernel.UnexpectedRollback(detail)) -> Error(detail)
  }
}

fn rollback(
  state: sequence_kernel.SequenceState,
  command: SequenceCommand,
) -> sequence_kernel.SequenceState {
  case list.last(state.pending) {
    Error(_) -> state
    Ok(sequence_kernel.PendingOp(_, message_id)) ->
      case
        sequence_kernel.rollback(
          state,
          command_to_kernel_op(command, "rollback"),
          message_id,
        )
      {
        Ok(#(state, _)) -> state
        Error(_) -> state
      }
  }
}

fn apply_stashed(
  state: sequence_kernel.SequenceState,
  command: SequenceCommand,
  meta: kernel_fuzz.SubmitMeta,
) -> #(sequence_kernel.SequenceState, SequenceCommand) {
  case command {
    InsertCommand(_, _, Some(_))
    | DeleteCommand(_, Some(_))
    | MoveCommand(_, _, Some(_))
    | ReplaceCommand(_, _, Some(_)) -> {
      let #(state, _, _, _) =
        sequence_kernel.apply_stashed_op(
          state,
          command_to_kernel_op(command, "apply_stashed"),
        )
      #(state, command)
    }
    InsertCommand(_, _, None)
    | DeleteCommand(_, None)
    | MoveCommand(_, _, None)
    | ReplaceCommand(_, _, None) -> {
      let #(state, routed) = submit(state, command, meta)
      let assert Some(routed) = routed
      #(state, routed)
    }
  }
}

fn load_from_synced(
  state: sequence_kernel.SequenceState,
  id: Int,
) -> sequence_kernel.SequenceState {
  let raw = json.to_string(sequence_kernel.summary(state))
  let assert Ok(loaded) =
    sequence_kernel.from_summary(
      raw,
      replica_id.new("client-" <> int.to_string(id)),
    )
  loaded
}

pub fn model() -> KernelModel(
  sequence_kernel.SequenceState,
  SequenceCommand,
  List(Json),
) {
  KernelModel(
    name: "sequence",
    init: fn(id) {
      sequence_kernel.new(replica_id.new("client-" <> int.to_string(id)))
    },
    submit: submit,
    apply_remote: apply_remote,
    ack_local: ack_local,
    observe: sequence_kernel.values,
    gen_op: op_generator(),
    check: Some(sequence_kernel.check_cache_coherence),
    canonicalize: None,
    ack_preserves_view: True,
    op_to_json: op_to_json,
    op_decoder: op_decoder(),
    capabilities: Capabilities(
      load_from_synced: Some(load_from_synced),
      oracle: None,
      rollback: Some(rollback),
      resubmit: None,
      apply_stashed: Some(apply_stashed),
      react: None,
      remove_member: None,
    ),
  )
}
