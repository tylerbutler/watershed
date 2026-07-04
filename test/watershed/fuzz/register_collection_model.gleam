//// `KernelModel` for ConsensusRegisterCollection. The model is
//// non-optimistic, so acking a winning local write legitimately changes the
//// observed committed view.

import gleam/dict
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import qcheck
import watershed/fuzz/kernel_fuzz.{
  type KernelModel, type LogEntry, Capabilities, KernelModel,
}
import watershed/register_collection_kernel.{
  type Register, type RegisterState, Register, VersionedValue, Write,
}

pub type WriteCommand {
  WriteCommand(key: String, value: Json, ref_seq: Int)
}

fn to_write(cmd: WriteCommand) -> register_collection_kernel.WriteOp {
  Write(cmd.key, cmd.value, cmd.ref_seq)
}

fn op_to_json(cmd: WriteCommand) -> Json {
  json.object([
    #("key", json.string(cmd.key)),
    #("value", cmd.value),
    #("ref_seq", json.int(cmd.ref_seq)),
  ])
}

fn op_decoder() -> decode.Decoder(WriteCommand) {
  use key <- decode.field("key", decode.string)
  use value <- decode.field("value", decode.int)
  use ref_seq <- decode.field("ref_seq", decode.int)
  decode.success(WriteCommand(key, json.int(value), ref_seq))
}

fn op_generator() -> qcheck.Generator(WriteCommand) {
  qcheck.tuple2(
    qcheck.small_non_negative_int(),
    qcheck.small_non_negative_int(),
  )
  |> qcheck.map(fn(pair) {
    let #(a, b) = pair
    let key = case a % 2 {
      0 -> "a"
      _ -> "b"
    }
    WriteCommand(key, json.int(b % 5), 0)
  })
}

fn submit(
  state: RegisterState,
  cmd: WriteCommand,
  meta: kernel_fuzz.SubmitMeta,
) -> #(RegisterState, option.Option(WriteCommand)) {
  let op =
    register_collection_kernel.write(
      state,
      cmd.key,
      cmd.value,
      meta.last_seen_seq,
    )
  #(state, Some(WriteCommand(op.key, op.value, op.ref_seq)))
}

fn apply_remote(
  state: RegisterState,
  cmd: WriteCommand,
  meta: kernel_fuzz.SequencedMeta,
) -> Result(RegisterState, String) {
  let #(state, _events) =
    register_collection_kernel.apply_remote(
      state,
      to_write(cmd),
      meta.sequence_number,
    )
  Ok(state)
}

fn ack_local(
  state: RegisterState,
  cmd: WriteCommand,
  meta: kernel_fuzz.SequencedMeta,
) -> Result(RegisterState, String) {
  let #(state, _events, _outcome) =
    register_collection_kernel.ack_local(
      state,
      to_write(cmd),
      meta.sequence_number,
    )
  Ok(state)
}

fn oracle(entries: List(LogEntry(WriteCommand))) -> List(#(String, Register)) {
  list.index_fold(
    kernel_fuzz.log_ops(entries),
    dict.new(),
    fn(registers, entry, i) {
      let cmd = entry.1
      let seq = i + 1
      let version = VersionedValue(cmd.value, seq)
      let #(register, _is_winner) = case dict.get(registers, cmd.key) {
        Error(_) -> #(Register(version, [version]), True)
        Ok(Register(atomic, versions)) -> {
          let is_winner = cmd.ref_seq >= atomic.sequence_number
          let atomic = case is_winner {
            True -> version
            False -> atomic
          }
          let versions =
            versions
            |> list.drop_while(fn(existing) {
              existing.sequence_number <= cmd.ref_seq
            })
            |> list.append([version])
          #(Register(atomic, versions), is_winner)
        }
      }
      dict.insert(registers, cmd.key, register)
    },
  )
  |> dict.to_list
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
}

fn load_from_synced(state: RegisterState, _id: Int) -> RegisterState {
  register_collection_kernel.from_summary(
    register_collection_kernel.summary_registers(state),
  )
}

fn rollback(state: RegisterState, cmd: WriteCommand) -> RegisterState {
  let #(state, _outcome) =
    register_collection_kernel.rollback(state, to_write(cmd))
  state
}

fn apply_stashed(
  state: RegisterState,
  cmd: WriteCommand,
  _meta: kernel_fuzz.SubmitMeta,
) -> #(RegisterState, WriteCommand) {
  let #(state, op) =
    register_collection_kernel.apply_stashed_op(state, to_write(cmd))
  #(state, WriteCommand(op.key, op.value, op.ref_seq))
}

pub fn model() -> KernelModel(
  RegisterState,
  WriteCommand,
  List(#(String, Register)),
) {
  KernelModel(
    name: "register_collection",
    init: fn(_id) { register_collection_kernel.new() },
    submit: submit,
    apply_remote: apply_remote,
    ack_local: ack_local,
    observe: register_collection_kernel.summary_registers,
    gen_op: op_generator(),
    check: None,
    canonicalize: None,
    ack_preserves_view: False,
    op_to_json: op_to_json,
    op_decoder: op_decoder(),
    capabilities: Capabilities(
      load_from_synced: Some(load_from_synced),
      oracle: Some(oracle),
      rollback: Some(rollback),
      apply_stashed: Some(apply_stashed),
      react: None,
      remove_member: None,
    ),
  )
}
