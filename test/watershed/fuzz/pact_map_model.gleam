//// `KernelModel` for `pact_map_kernel`.
////
//// Generated ops are set/delete commands; accept ops are emitted reactively by
//// every client whose post-apply pending signoff set contains its id.

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string
import qcheck
import watershed/fuzz/kernel_fuzz.{
  type KernelModel, type LogEntry, Capabilities, KernelModel,
}
import watershed/pact_map_kernel.{
  type Pact, type PactMapState, Accept, Accepted, NoReaction, OweAccept, Pact,
  Pending, Set,
}

pub type PactCommand {
  CmdSet(key: String, value: Option(Json), ref_seq: Int)
  CmdAccept(key: String)
}

type OracleState {
  OracleState(values: Dict(String, Pact))
}

pub type ModelState {
  ModelState(kernel: PactMapState, last_reaction: Option(PactCommand))
}

fn new_state() -> ModelState {
  ModelState(kernel: pact_map_kernel.new(), last_reaction: None)
}

fn to_kernel_op(cmd: PactCommand) -> pact_map_kernel.PactMapOp {
  case cmd {
    CmdSet(key, value, ref_seq) -> Set(key, value, ref_seq)
    CmdAccept(key) -> Accept(key)
  }
}

fn from_kernel_op(op: pact_map_kernel.PactMapOp) -> PactCommand {
  case op {
    Set(key, value, ref_seq) -> CmdSet(key, value, ref_seq)
    Accept(key) -> CmdAccept(key)
  }
}

fn op_to_json(cmd: PactCommand) -> Json {
  case cmd {
    CmdSet(key, value, ref_seq) ->
      json.object([
        #("tag", json.string("Set")),
        #("key", json.string(key)),
        #("value", option_json(value)),
        #("ref_seq", json.int(ref_seq)),
      ])
    CmdAccept(key) ->
      json.object([#("tag", json.string("Accept")), #("key", json.string(key))])
  }
}

fn option_json(value: Option(Json)) -> Json {
  case value {
    Some(value) -> value
    None -> json.null()
  }
}

fn option_decoder() -> decode.Decoder(Option(Json)) {
  decode.optional(decode.int)
  |> decode.map(fn(value) {
    case value {
      Some(value) -> Some(json.int(value))
      None -> None
    }
  })
}

fn op_decoder() -> decode.Decoder(PactCommand) {
  use tag <- decode.field("tag", decode.string)
  case tag {
    "Set" -> {
      use key <- decode.field("key", decode.string)
      use value <- decode.field("value", option_decoder())
      use ref_seq <- decode.field("ref_seq", decode.int)
      decode.success(CmdSet(key, value, ref_seq))
    }
    "Accept" -> {
      use key <- decode.field("key", decode.string)
      decode.success(CmdAccept(key))
    }
    _ -> decode.failure(CmdSet("", None, 0), "pact-map op")
  }
}

fn key_from_int(n: Int) -> String {
  case n % 2 {
    0 -> "a"
    _ -> "b"
  }
}

fn op_generator() -> qcheck.Generator(PactCommand) {
  qcheck.tuple3(
    qcheck.small_non_negative_int(),
    qcheck.small_non_negative_int(),
    qcheck.small_non_negative_int(),
  )
  |> qcheck.map(fn(ints) {
    let key = key_from_int(ints.1)
    case ints.0 % 5 {
      0 -> CmdSet(key, None, 0)
      _ -> CmdSet(key, Some(json.int(ints.2 % 8)), 0)
    }
  })
}

fn submit(
  state: ModelState,
  cmd: PactCommand,
  meta: kernel_fuzz.SubmitMeta,
) -> #(ModelState, Option(PactCommand)) {
  case cmd {
    CmdAccept(_) -> #(state, None)
    CmdSet(key, None, _) ->
      case pact_map_kernel.delete(state.kernel, key, meta.last_seen_seq) {
        Some(op) -> #(state, Some(from_kernel_op(op)))
        None -> #(state, None)
      }
    CmdSet(key, Some(value), _) ->
      case
        pact_map_kernel.set(state.kernel, key, Some(value), meta.last_seen_seq)
      {
        Some(op) -> #(state, Some(from_kernel_op(op)))
        None -> #(state, None)
      }
  }
}

fn apply_set_for_client(
  state: ModelState,
  cmd: PactCommand,
  meta: kernel_fuzz.SequencedMeta,
  self_id: Int,
) -> ModelState {
  case cmd {
    CmdSet(_, _, _) -> {
      let #(kernel, _events, reaction) =
        pact_map_kernel.apply_set(
          state.kernel,
          to_kernel_op(cmd),
          meta.sequence_number,
          meta.connected_clients,
          self_id,
        )
      let last_reaction = case reaction {
        OweAccept(op) -> Some(from_kernel_op(op))
        NoReaction -> None
      }
      ModelState(kernel:, last_reaction:)
    }
    CmdAccept(_) -> state
  }
}

fn apply_remote(
  state: ModelState,
  cmd: PactCommand,
  meta: kernel_fuzz.SequencedMeta,
) -> Result(ModelState, String) {
  case cmd {
    CmdSet(_, _, _) -> Ok(apply_set_for_client(state, cmd, meta, meta.self_id))
    CmdAccept(key) -> {
      case
        pact_map_kernel.apply_accept(
          state.kernel,
          key,
          meta.client_id,
          meta.sequence_number,
        )
      {
        Ok(#(kernel, _events)) -> Ok(ModelState(kernel:, last_reaction: None))
        Error(pact_map_kernel.UnexpectedAccept(_, _, detail)) -> Error(detail)
      }
    }
  }
}

fn ack_local(
  state: ModelState,
  cmd: PactCommand,
  meta: kernel_fuzz.SequencedMeta,
) -> Result(ModelState, String) {
  case cmd {
    CmdSet(_, _, _) ->
      Ok(apply_set_for_client(state, cmd, meta, meta.client_id))
    CmdAccept(key) ->
      case
        pact_map_kernel.apply_accept(
          state.kernel,
          key,
          meta.client_id,
          meta.sequence_number,
        )
      {
        Ok(#(kernel, _events)) -> Ok(ModelState(kernel:, last_reaction: None))
        Error(pact_map_kernel.UnexpectedAccept(_, _, detail)) -> Error(detail)
      }
  }
}

fn react(
  state: ModelState,
  cmd: PactCommand,
  _meta: kernel_fuzz.SequencedMeta,
  _self_id: Int,
  _is_local: Bool,
) -> List(PactCommand) {
  case cmd {
    CmdSet(_, _, _) ->
      case state.last_reaction {
        Some(op) -> [op]
        None -> []
      }
    CmdAccept(_) -> []
  }
}

fn remove_member(
  state: ModelState,
  leaver: Int,
  meta: kernel_fuzz.SequencedMeta,
) -> ModelState {
  let #(kernel, _events) =
    pact_map_kernel.remove_member(state.kernel, leaver, meta.sequence_number)
  ModelState(kernel:, last_reaction: None)
}

fn load_from_synced(state: ModelState, _id: Int) -> ModelState {
  ModelState(
    kernel: pact_map_kernel.from_summary(pact_map_kernel.summary_entries(
      state.kernel,
    )),
    last_reaction: None,
  )
}

fn valid_set(state: OracleState, key: String, ref_seq: Int) -> Bool {
  case dict.get(state.values, key) {
    Error(_) -> True
    Ok(Pact(_, Some(_))) -> False
    Ok(Pact(Some(Accepted(_, seq)), None)) -> seq <= ref_seq
    Ok(Pact(None, None)) -> True
  }
}

fn oracle_set(
  state: OracleState,
  key: String,
  value: Option(Json),
  ref_seq: Int,
  seq: Int,
  connected: List(Int),
) -> OracleState {
  case valid_set(state, key, ref_seq) {
    False -> state
    True -> {
      let accepted = case dict.get(state.values, key) {
        Ok(Pact(accepted, _)) -> accepted
        Error(_) -> None
      }
      let signoffs = connected |> list.sort(int_compare)
      case signoffs {
        [] ->
          OracleState(values: dict.insert(
            state.values,
            key,
            Pact(Some(Accepted(value, seq)), None),
          ))
        _ ->
          OracleState(values: dict.insert(
            state.values,
            key,
            Pact(accepted, Some(Pending(value, signoffs))),
          ))
      }
    }
  }
}

fn oracle_accept(
  state: OracleState,
  key: String,
  client: Int,
  seq: Int,
) -> OracleState {
  case dict.get(state.values, key) {
    Ok(Pact(accepted, Some(Pending(value, signoffs)))) -> {
      let signoffs = list.filter(signoffs, fn(id) { id != client })
      let pact = case signoffs {
        [] -> Pact(Some(Accepted(value, seq)), None)
        _ -> Pact(accepted, Some(Pending(value, signoffs)))
      }
      OracleState(values: dict.insert(state.values, key, pact))
    }
    _ -> state
  }
}

fn oracle_leave(state: OracleState, client: Int, seq: Int) -> OracleState {
  dict.to_list(state.values)
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  |> list.fold(state, fn(state, entry) {
    let #(key, pact) = entry
    case pact {
      Pact(accepted, Some(Pending(value, signoffs))) -> {
        let signoffs = list.filter(signoffs, fn(id) { id != client })
        let pact = case signoffs {
          [] -> Pact(Some(Accepted(value, seq)), None)
          _ -> Pact(accepted, Some(Pending(value, signoffs)))
        }
        OracleState(values: dict.insert(state.values, key, pact))
      }
      _ -> state
    }
  })
}

fn connected_after_disconnect(connected: List(Int), client: Int) -> List(Int) {
  list.filter(connected, fn(id) { id != client })
}

fn oracle(entries: List(LogEntry(PactCommand))) -> List(#(String, Pact)) {
  let #(state, _) =
    entries
    |> list.index_fold(
      #(OracleState(values: dict.new()), [0, 1, 2]),
      fn(acc, entry, i) {
        let #(state, connected) = acc
        let seq = i + 1
        case entry {
          kernel_fuzz.OpEntry(_author, CmdSet(key, value, ref_seq), connected) -> #(
            oracle_set(state, key, value, ref_seq, seq, connected),
            connected,
          )
          kernel_fuzz.OpEntry(author, CmdAccept(key), _) -> #(
            oracle_accept(state, key, author, seq),
            connected,
          )
          kernel_fuzz.LeaveEntry(client) -> #(
            oracle_leave(state, client, seq),
            connected_after_disconnect(connected, client),
          )
        }
      },
    )
  dict.to_list(state.values) |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
}

fn observe(state: ModelState) -> List(#(String, Pact)) {
  pact_map_kernel.summary_entries(state.kernel)
}

fn check_signoffs(state: ModelState) -> Result(Nil, String) {
  pact_map_kernel.summary_entries(state.kernel)
  |> list.try_each(fn(entry) {
    let #(key, Pact(_, pending)) = entry
    case pending {
      None -> Ok(Nil)
      Some(Pending(_, signoffs)) ->
        case signoffs == list.sort(signoffs, int_compare) {
          True -> Ok(Nil)
          False -> Error("signoffs not sorted for key " <> key)
        }
    }
  })
}

fn int_compare(a: Int, b: Int) -> order.Order {
  case a < b {
    True -> order.Lt
    False ->
      case a > b {
        True -> order.Gt
        False -> order.Eq
      }
  }
}

pub fn model() -> KernelModel(ModelState, PactCommand, List(#(String, Pact))) {
  KernelModel(
    name: "pact_map",
    init: fn(_id) { new_state() },
    submit: submit,
    apply_remote: apply_remote,
    ack_local: ack_local,
    observe: observe,
    gen_op: op_generator(),
    check: Some(check_signoffs),
    canonicalize: None,
    ack_preserves_view: False,
    op_to_json: op_to_json,
    op_decoder: op_decoder(),
    capabilities: Capabilities(
      load_from_synced: Some(load_from_synced),
      oracle: Some(oracle),
      rollback: None,
      resubmit: None,
      apply_stashed: None,
      react: Some(react),
      remove_member: Some(remove_member),
    ),
  )
}
