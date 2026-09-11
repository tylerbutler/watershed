//// Key dots come from the sequenced log, not the CRDT delta. A remove retires
//// dots in its observed prefix and earlier dots from its own author.
//// Value dots and causal vectors come from the leaf codec. A write retires
//// value dots in its causal vector. The oracle uses no lattice merge.

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lattice_core/replica_id
import lattice_maps/or_map.{type ORMapDelta}
import qcheck
import watershed/fuzz/kernel_fuzz.{
  type KernelModel, type LogEntry, Capabilities, KernelModel,
}
import watershed/or_map_kernel as kernel

pub type OrMapMvCommand {
  CommandWrite(key: String, value: String, delta: Option(ORMapDelta))
  CommandRemove(
    key: String,
    reference_sequence_number: Int,
    delta: Option(ORMapDelta),
  )
}

type Dot =
  #(String, Int)

type Write {
  Write(key: String, value: String, dot: Dot, observed: Dict(String, Int))
}

fn replica(id: Int) -> replica_id.ReplicaId {
  replica_id.new("client-" <> int.to_string(id))
}

fn operation(command: OrMapMvCommand) -> kernel.OrMapOperation {
  case command {
    CommandWrite(key, value, Some(delta)) ->
      kernel.SetMvRegister(key, value, delta)
    CommandRemove(key, _, Some(delta)) -> kernel.Remove(key, delta)
    CommandWrite(_, _, None) | CommandRemove(_, _, None) ->
      panic as "routed MV-register OR-map command has no delta"
  }
}

fn submit(
  state: kernel.OrMapState,
  command: OrMapMvCommand,
  meta: kernel_fuzz.SubmitMeta,
) -> #(kernel.OrMapState, Option(OrMapMvCommand)) {
  case command {
    CommandWrite(key, value, _) -> {
      let assert Ok(#(state, _, kernel.SetMvRegister(_, _, delta), _)) =
        kernel.set_mv_register(state, key, value)
      #(state, Some(CommandWrite(key, value, Some(delta))))
    }
    CommandRemove(key, _, _) -> {
      let assert Ok(#(state, _, kernel.Remove(_, delta), _)) =
        kernel.remove(state, key)
      #(
        state,
        Some(CommandRemove(key, meta.last_seen_sequence_number, Some(delta))),
      )
    }
  }
}

fn apply_stashed(
  state: kernel.OrMapState,
  command: OrMapMvCommand,
  meta: kernel_fuzz.SubmitMeta,
) -> #(kernel.OrMapState, OrMapMvCommand) {
  case command.delta {
    None -> {
      let assert #(state, Some(routed)) = submit(state, command, meta)
      #(state, routed)
    }
    Some(_) -> {
      let assert Ok(#(state, _, _, _)) =
        kernel.apply_stashed_operation(state, operation(command))
      #(state, command)
    }
  }
}

fn rollback(
  state: kernel.OrMapState,
  command: OrMapMvCommand,
) -> kernel.OrMapState {
  let assert Ok(pending) = list.last(state.pending)
  let assert Ok(#(state, _)) =
    kernel.rollback(state, operation(command), pending.message_id)
  state
}

fn error_detail(error: kernel.KernelError) -> String {
  case error {
    kernel.UnexpectedAck(detail)
    | kernel.UnexpectedRollback(detail)
    | kernel.ModeMismatch(detail)
    | kernel.CorruptDelta(detail)
    | kernel.InvalidSetState(detail)
    | kernel.CounterExhausted(detail)
    | kernel.NegativeTally(detail) -> detail
  }
}

fn tag_decoder() -> decode.Decoder(Dot) {
  use replica <- decode.field("r", decode.string)
  use counter <- decode.field("c", decode.int)
  decode.success(#(replica, counter))
}

fn value_writes(command: OrMapMvCommand) -> List(Write) {
  let assert Some(delta) = command.delta
  let decoder =
    decode.at(
      ["state", "value_deltas"],
      decode.list({
        use key <- decode.field("key", decode.string)
        use encoded <- decode.field("crdt", decode.string)
        decode.success(#(key, encoded))
      }),
    )
  let assert Ok(leaves) =
    json.parse(or_map.delta_to_json(delta) |> json.to_string, decoder)
  list.flat_map(leaves, fn(leaf) {
    let leaf_decoder =
      decode.at(["state"], {
        use entries <- decode.field(
          "entries",
          decode.list({
            use dot <- decode.field("tag", tag_decoder())
            use value <- decode.field("value", decode.string)
            decode.success(#(dot, value))
          }),
        )
        use observed <- decode.field(
          "vclock",
          decode.dict(decode.string, decode.int),
        )
        decode.success(
          list.map(entries, fn(entry) {
            Write(leaf.0, entry.1, entry.0, observed)
          }),
        )
      })
    let assert Ok(writes) = json.parse(leaf.1, leaf_decoder)
    writes
  })
}

fn oracle(
  log: List(LogEntry(OrMapMvCommand)),
) -> List(#(String, List(String))) {
  let operations = kernel_fuzz.log_operations(log)
  let dots =
    operations
    |> list.index_map(fn(entry, index) { #(index + 1, entry) })
    |> list.fold(dict.new(), fn(dots, entry) {
      let #(sequence_number, #(author, command)) = entry
      let existing = dict.get(dots, command.key) |> result.unwrap([])
      case command {
        CommandWrite(key, _, _) ->
          dict.insert(dots, key, [#(author, sequence_number), ..existing])
        CommandRemove(key, reference_sequence_number, _) -> {
          let remaining =
            list.filter(existing, fn(dot) {
              dot.1 > reference_sequence_number && dot.0 != author
            })
          case remaining {
            [] -> dict.delete(dots, key)
            _ -> dict.insert(dots, key, remaining)
          }
        }
      }
    })
  let writes =
    operations
    |> list.flat_map(fn(entry) {
      case entry.1 {
        CommandWrite(..) -> value_writes(entry.1)
        CommandRemove(..) -> []
      }
    })
    |> list.unique
  dict.keys(dots)
  |> list.sort(string.compare)
  |> list.map(fn(key) {
    let values =
      writes
      |> list.filter(fn(write) {
        write.key == key
        && !list.any(writes, fn(other) {
          other.key == key
          && other.dot != write.dot
          && result.unwrap(dict.get(other.observed, write.dot.0), 0)
          >= write.dot.1
        })
      })
      |> list.map(fn(write) { write.value })
      |> list.sort(string.compare)
    #(key, values)
  })
}

fn observe(state: kernel.OrMapState) -> List(#(String, List(String))) {
  kernel.entries(state)
  |> list.map(fn(entry) {
    let assert kernel.MvRegister(values) = entry.1
    #(entry.0, values)
  })
}

fn encode(command: OrMapMvCommand) -> json.Json {
  let fields = case command {
    CommandWrite(key, value, _) -> [
      #("tag", json.string("Write")),
      #("key", json.string(key)),
      #("value", json.string(value)),
    ]
    CommandRemove(key, reference_sequence_number, _) -> [
      #("tag", json.string("Remove")),
      #("key", json.string(key)),
      #("ref_seq", json.int(reference_sequence_number)),
    ]
  }
  json.object(
    list.append(fields, [
      #("delta", case command.delta {
        None -> json.null()
        Some(delta) ->
          or_map.delta_to_json(delta) |> json.to_string |> json.string
      }),
    ]),
  )
}

fn decoder() -> decode.Decoder(OrMapMvCommand) {
  use tag <- decode.field("tag", decode.string)
  use key <- decode.field("key", decode.string)
  use delta <- decode.field("delta", decode.optional(decode.string))
  use delta <- decode.then(case delta {
    None -> decode.success(None)
    Some(encoded) ->
      case or_map.delta_from_json(encoded) {
        Ok(delta) -> decode.success(Some(delta))
        Error(_) -> decode.failure(None, "OR-map delta")
      }
  })
  case tag {
    "Write" -> {
      use value <- decode.field("value", decode.string)
      decode.success(CommandWrite(key, value, delta))
    }
    "Remove" -> {
      use reference_sequence_number <- decode.field("ref_seq", decode.int)
      decode.success(CommandRemove(key, reference_sequence_number, delta))
    }
    _ -> decode.failure(CommandWrite("", "", None), "Write or Remove")
  }
}

pub fn model() -> KernelModel(
  kernel.OrMapState,
  OrMapMvCommand,
  List(#(String, List(String))),
) {
  KernelModel(
    name: "or_map_mv_register",
    init: fn(id) { kernel.new(replica(id), kernel.MvRegisterMode) },
    submit: submit,
    apply_remote: fn(state, command, _) {
      kernel.apply_remote(state, operation(command))
      |> result.map(fn(pair) { pair.0 })
      |> result.map_error(error_detail)
    },
    ack_local: fn(state, command, _) {
      kernel.ack_local(state, operation(command))
      |> result.map_error(error_detail)
    },
    observe: observe,
    gen_operation: qcheck.tuple3(
      qcheck.small_non_negative_int(),
      qcheck.small_non_negative_int(),
      qcheck.small_non_negative_int(),
    )
      |> qcheck.map(fn(ints) {
        let key = case ints.1 % 2 {
          0 -> "a"
          _ -> "b"
        }
        case ints.0 % 4 {
          0 -> CommandRemove(key, 0, None)
          _ -> CommandWrite(key, int.to_string(ints.2 % 3), None)
        }
      }),
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
            replica(id),
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
