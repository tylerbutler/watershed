//// `KernelModel` for `or_map_kernel` in TallyMode.
////
//// ## Oracle soundness
////
//// The oracle is independent of the CRDT merge. It models only the sequenced
//// log: every increment adds a live dot and contributes its amount to that
//// key's cumulative tally; every remove keeps only dots that the remover had
//// not observed when it submitted. A remover observes (i) all delivered ops
//// with sequence number `<= ref_seq` and (ii) its own pending ops, which are
//// exactly that same author's earlier log entries. Therefore a dot survives
//// `CmdRemove(key, ref_seq)` iff `dot.seq > ref_seq && dot.author != remover`.
////
//// Tallies never reset when a key is removed: the kernel's `own_tallies`
//// ledger makes every routed delta carry that replica's cumulative PN-counter
//// value for the key, so full sync observes the sum of all sequenced increment
//// amounts for each key, hidden only while no live dots remain.

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lattice_core/replica_id.{type ReplicaId}
import lattice_maps/or_map.{type ORMapDelta}
import qcheck
import watershed/fuzz/kernel_fuzz.{type KernelModel, Capabilities, KernelModel}
import watershed/or_map_kernel.{
  type OrMapState, Increment, PendingOp, Remove, TallyMode,
}

pub type OrMapCommand {
  CmdIncrement(key: String, amount: Int, delta: Option(ORMapDelta))
  CmdRemove(key: String, ref_seq: Int, delta: Option(ORMapDelta))
}

type OracleState {
  OracleState(dots: Dict(String, List(#(Int, Int))), tallies: Dict(String, Int))
}

fn client_replica_id(id: Int) -> ReplicaId {
  replica_id.new("client-" <> int.to_string(id))
}

fn delta_to_json(delta: Option(ORMapDelta)) -> json.Json {
  case delta {
    None -> json.null()
    Some(delta) -> json.string(json.to_string(or_map.delta_to_json(delta)))
  }
}

pub fn op_to_json(cmd: OrMapCommand) -> json.Json {
  case cmd {
    CmdIncrement(key, amount, delta) ->
      json.object([
        #("tag", json.string("Increment")),
        #("key", json.string(key)),
        #("amount", json.int(amount)),
        #("delta", delta_to_json(delta)),
      ])
    CmdRemove(key, ref_seq, delta) ->
      json.object([
        #("tag", json.string("Remove")),
        #("key", json.string(key)),
        #("ref_seq", json.int(ref_seq)),
        #("delta", delta_to_json(delta)),
      ])
  }
}

fn delta_decoder() -> decode.Decoder(Option(ORMapDelta)) {
  decode.optional(decode.string)
  |> decode.then(fn(maybe_encoded) {
    case maybe_encoded {
      None -> decode.success(None)
      Some(encoded) ->
        case or_map.delta_from_json(encoded) {
          Ok(delta) -> decode.success(Some(delta))
          Error(_) -> decode.failure(None, "ORMapDelta")
        }
    }
  })
}

pub fn op_decoder() -> decode.Decoder(OrMapCommand) {
  use tag <- decode.field("tag", decode.string)
  case tag {
    "Increment" -> {
      use key <- decode.field("key", decode.string)
      use amount <- decode.field("amount", decode.int)
      use delta <- decode.field("delta", delta_decoder())
      decode.success(CmdIncrement(key, amount, delta))
    }
    "Remove" -> {
      use key <- decode.field("key", decode.string)
      use ref_seq <- decode.field("ref_seq", decode.int)
      use delta <- decode.field("delta", delta_decoder())
      decode.success(CmdRemove(key, ref_seq, delta))
    }
    _ -> decode.failure(CmdIncrement("", 0, None), "Increment or Remove")
  }
}

fn key_from_int(n: Int) -> String {
  case n % 2 {
    0 -> "a"
    _ -> "b"
  }
}

fn amount_from_int(n: Int) -> Int {
  n % 21 - 10
}

fn op_from_ints(kind: Int, key: Int, amount: Int) -> OrMapCommand {
  case kind % 4 {
    0 -> CmdRemove(key_from_int(key), 0, None)
    _ -> CmdIncrement(key_from_int(key), amount_from_int(amount), None)
  }
}

fn op_generator() -> qcheck.Generator(OrMapCommand) {
  qcheck.tuple3(
    qcheck.small_non_negative_int(),
    qcheck.small_non_negative_int(),
    qcheck.small_non_negative_int(),
  )
  |> qcheck.map(fn(ints) { op_from_ints(ints.0, ints.1, ints.2) })
}

fn to_kernel_op(cmd: OrMapCommand, context: String) -> or_map_kernel.OrMapOp {
  case cmd {
    CmdIncrement(key, amount, Some(delta)) -> Increment(key, amount, delta)
    CmdRemove(key, _ref_seq, Some(delta)) -> Remove(key, delta)
    CmdIncrement(_, _, None) | CmdRemove(_, _, None) ->
      panic as {
        context
        <> " received an op without a delta — submit/apply_stashed must rewrite ops before routing"
      }
  }
}

fn submit(
  state: OrMapState,
  cmd: OrMapCommand,
  meta: kernel_fuzz.SubmitMeta,
) -> #(OrMapState, Option(OrMapCommand)) {
  case cmd {
    CmdIncrement(key, amount, _) -> {
      let assert Ok(#(state, _events, op, _message_id)) =
        or_map_kernel.increment(state, key, amount)
      let assert Increment(_, _, delta) = op
      #(state, Some(CmdIncrement(key, amount, Some(delta))))
    }
    CmdRemove(key, _, _) -> {
      let #(state, _events, op, _message_id) = or_map_kernel.remove(state, key)
      let assert Remove(_, delta) = op
      #(state, Some(CmdRemove(key, meta.last_seen_seq, Some(delta))))
    }
  }
}

fn apply_remote(
  state: OrMapState,
  cmd: OrMapCommand,
  _meta: kernel_fuzz.SequencedMeta,
) -> OrMapState {
  case or_map_kernel.apply_remote(state, to_kernel_op(cmd, "apply_remote")) {
    Ok(#(state, _events)) -> state
    Error(_) -> panic as "apply_remote rejected a routed OR-map op"
  }
}

fn ack_local(
  state: OrMapState,
  cmd: OrMapCommand,
  _meta: kernel_fuzz.SequencedMeta,
) -> Result(OrMapState, String) {
  case or_map_kernel.ack_local(state, to_kernel_op(cmd, "ack_local")) {
    Ok(state) -> Ok(state)
    Error(or_map_kernel.UnexpectedAck(detail)) -> Error(detail)
    Error(or_map_kernel.UnexpectedRollback(detail)) -> Error(detail)
    Error(or_map_kernel.ModeMismatch(detail)) -> Error(detail)
    Error(or_map_kernel.CorruptDelta(detail)) -> Error(detail)
  }
}

fn rollback(state: OrMapState, cmd: OrMapCommand) -> OrMapState {
  case list.last(state.pending) {
    Error(_) -> state
    Ok(PendingOp(_, message_id)) ->
      case
        or_map_kernel.rollback(state, to_kernel_op(cmd, "rollback"), message_id)
      {
        Ok(#(new_state, _events)) -> new_state
        Error(_) -> state
      }
  }
}

fn apply_stashed(
  state: OrMapState,
  cmd: OrMapCommand,
  meta: kernel_fuzz.SubmitMeta,
) -> #(OrMapState, OrMapCommand) {
  case submit(state, cmd, meta) {
    #(state, Some(routed)) -> #(state, routed)
    #(state, None) -> #(state, cmd)
  }
}

fn add_dot(
  dots: Dict(String, List(#(Int, Int))),
  key: String,
  dot: #(Int, Int),
) -> Dict(String, List(#(Int, Int))) {
  let existing = dict.get(dots, key) |> result.unwrap([])
  dict.insert(dots, key, list.append(existing, [dot]))
}

fn add_tally(
  tallies: Dict(String, Int),
  key: String,
  amount: Int,
) -> Dict(String, Int) {
  dict.insert(
    tallies,
    key,
    { dict.get(tallies, key) |> result.unwrap(0) } + amount,
  )
}

fn remove_observed_dots(
  dots: Dict(String, List(#(Int, Int))),
  key: String,
  author: Int,
  ref_seq: Int,
) -> Dict(String, List(#(Int, Int))) {
  let remaining =
    dict.get(dots, key)
    |> result.unwrap([])
    |> list.filter(fn(dot) { dot.1 > ref_seq && dot.0 != author })
  case remaining {
    [] -> dict.delete(dots, key)
    _ -> dict.insert(dots, key, remaining)
  }
}

fn apply_oracle_op(
  state: OracleState,
  entry: #(Int, #(Int, OrMapCommand)),
) -> OracleState {
  let #(seq, #(author, cmd)) = entry
  case cmd {
    CmdIncrement(key, amount, _) ->
      OracleState(
        dots: add_dot(state.dots, key, #(author, seq)),
        tallies: add_tally(state.tallies, key, amount),
      )
    CmdRemove(key, ref_seq, _) ->
      OracleState(
        ..state,
        dots: remove_observed_dots(state.dots, key, author, ref_seq),
      )
  }
}

pub fn oracle(log: List(#(Int, OrMapCommand))) -> List(#(String, Int)) {
  let state =
    log
    |> list.index_map(fn(entry, i) { #(i + 1, entry) })
    |> list.fold(
      OracleState(dots: dict.new(), tallies: dict.new()),
      apply_oracle_op,
    )

  dict.keys(state.dots)
  |> list.sort(by: string.compare)
  |> list.filter_map(fn(key) {
    case dict.get(state.dots, key) {
      Ok([_, ..]) ->
        Ok(#(key, dict.get(state.tallies, key) |> result.unwrap(0)))
      _ -> Error(Nil)
    }
  })
}

fn observe(state: OrMapState) -> List(#(String, Int)) {
  or_map_kernel.entries(state)
  |> list.map(fn(entry) {
    let assert or_map_kernel.Tally(value) = entry.1
    #(entry.0, value)
  })
}

fn load_from_synced(state: OrMapState, id: Int) -> OrMapState {
  let summary_json = json.to_string(or_map_kernel.summary(state))
  case or_map_kernel.from_summary(summary_json, client_replica_id(id)) {
    Ok(loaded) -> loaded
    Error(_) ->
      panic as "load_from_synced could not decode the OR-map summary it just encoded"
  }
}

pub fn model() -> KernelModel(OrMapState, OrMapCommand, List(#(String, Int))) {
  KernelModel(
    name: "or_map",
    init: fn(id) { or_map_kernel.new(client_replica_id(id), TallyMode) },
    submit: submit,
    apply_remote: apply_remote,
    ack_local: ack_local,
    observe: observe,
    gen_op: op_generator(),
    check: Some(or_map_kernel.check_cache_coherence),
    canonicalize: None,
    ack_preserves_view: True,
    op_to_json: op_to_json,
    op_decoder: op_decoder(),
    capabilities: Capabilities(
      load_from_synced: Some(load_from_synced),
      oracle: Some(oracle),
      rollback: Some(rollback),
      apply_stashed: Some(apply_stashed),
    ),
  )
}
