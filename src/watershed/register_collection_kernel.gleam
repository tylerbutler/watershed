//// Pure port of FluidFramework's ConsensusRegisterCollection core semantics.
////
//// Like `claims_kernel`, this kernel is non-optimistic: local writes are not
//// visible until their op sequences. Unlike claims, every sequenced write is
//// retained as a version; the atomic slot is updated only when the write knew
//// the current atomic version (`ref_seq >= atomic.sequence_number`).

import gleam/dict.{type Dict}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type RegisterState {
  RegisterState(registers: Dict(String, Register))
}

pub type Register {
  /// `atomic` is the linearizable winner; `versions` contains every still-
  /// concurrent value in sequence order, oldest first. Non-empty by invariant.
  Register(atomic: VersionedValue, versions: List(VersionedValue))
}

pub type VersionedValue {
  VersionedValue(value: Json, sequence_number: Int)
}

/// The single register-collection op. `ref_seq` is the author's last-seen
/// sequence number at submit time and is preserved across resubmits.
pub type WriteOp {
  Write(key: String, value: Json, ref_seq: Int)
}

pub type RegisterEvent {
  /// Emitted only when the atomic/linearizable value changes.
  AtomicChanged(key: String, value: Json, local: Bool)
  /// Emitted for every sequenced write, including atomic losers.
  VersionChanged(key: String, value: Json, local: Bool)
}

pub type ReadPolicy {
  Atomic
  Lww
}

pub fn new() -> RegisterState {
  RegisterState(registers: dict.new())
}

/// Build committed state from summary entries. Sequence numbers are part of
/// the summary so atomic CAS and version pruning keep working after load.
pub fn from_summary(entries: List(#(String, Register))) -> RegisterState {
  let registers =
    list.fold(entries, dict.new(), fn(acc, entry) {
      let #(key, register) = entry
      dict.insert(acc, key, register)
    })
  RegisterState(registers: registers)
}

/// Stable summary entries sorted by key.
pub fn summary_registers(state: RegisterState) -> List(#(String, Register)) {
  dict.to_list(state.registers)
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
}

/// The committed value for `key` under `policy`, or `None` if the key has no
/// sequenced data. Committed-only: pending local writes are invisible.
pub fn read(
  state: RegisterState,
  key: String,
  policy: ReadPolicy,
) -> Option(Json) {
  case dict.get(state.registers, key) {
    Error(_) -> None
    Ok(Register(atomic, versions)) ->
      case policy {
        Atomic -> Some(atomic.value)
        Lww ->
          case list.last(versions) {
            Ok(VersionedValue(value, _)) -> Some(value)
            Error(_) -> None
          }
      }
  }
}

/// All committed versions for `key`, oldest to newest, or `None` if absent.
pub fn read_versions(state: RegisterState, key: String) -> Option(List(Json)) {
  case dict.get(state.registers, key) {
    Error(_) -> None
    Ok(Register(_, versions)) ->
      versions
      |> list.map(fn(version) { version.value })
      |> Some
  }
}

pub fn keys(state: RegisterState) -> List(String) {
  dict.keys(state.registers) |> list.sort(string.compare)
}

/// Attached submit path: build an op with the runtime-provided last-seen
/// sequence number. State is unchanged because reads are non-optimistic.
pub fn write(
  _state: RegisterState,
  key: String,
  value: Json,
  last_seen_seq: Int,
) -> WriteOp {
  Write(key, value, last_seen_seq)
}

/// Detached apply: no sequencer exists yet, so both refSeq and seq are zero.
pub fn write_detached(
  state: RegisterState,
  key: String,
  value: Json,
) -> #(RegisterState, List(RegisterEvent)) {
  let #(state, _is_winner, events) = apply_write(state, key, value, 0, 0, True)
  #(state, events)
}

pub fn apply_remote(
  state: RegisterState,
  op: WriteOp,
  seq: Int,
) -> #(RegisterState, List(RegisterEvent)) {
  let #(state, _is_winner, events) =
    apply_write(state, op.key, op.value, op.ref_seq, seq, False)
  #(state, events)
}

pub fn ack_local(
  state: RegisterState,
  op: WriteOp,
  seq: Int,
) -> #(RegisterState, List(RegisterEvent), Bool) {
  let #(state, is_winner, events) =
    apply_write(state, op.key, op.value, op.ref_seq, seq, True)
  #(state, events, is_winner)
}

/// Rollback resolves the deferred write outcome as false. There is no pending
/// kernel state to undo because writes are invisible until ack.
pub fn rollback(state: RegisterState, _op: WriteOp) -> #(RegisterState, Bool) {
  #(state, False)
}

/// Stashed ops are resubmitted verbatim; in particular, `ref_seq` is preserved.
pub fn apply_stashed_op(
  state: RegisterState,
  op: WriteOp,
) -> #(RegisterState, WriteOp) {
  #(state, op)
}

fn apply_write(
  state: RegisterState,
  key: String,
  value: Json,
  ref_seq: Int,
  seq: Int,
  local: Bool,
) -> #(RegisterState, Bool, List(RegisterEvent)) {
  let new_version = VersionedValue(value, seq)
  let #(register, is_winner) = case dict.get(state.registers, key) {
    Error(_) -> #(Register(new_version, [new_version]), True)
    Ok(Register(atomic, versions)) -> {
      let is_winner = ref_seq >= atomic.sequence_number
      let atomic = case is_winner {
        True -> new_version
        False -> atomic
      }
      let versions =
        versions
        |> list.drop_while(fn(version) { version.sequence_number <= ref_seq })
        |> list.append([new_version])
      #(Register(atomic, versions), is_winner)
    }
  }
  let state =
    RegisterState(registers: dict.insert(state.registers, key, register))
  let events = case is_winner {
    True -> [
      AtomicChanged(key, value, local),
      VersionChanged(key, value, local),
    ]
    False -> [VersionChanged(key, value, local)]
  }
  #(state, is_winner, events)
}
