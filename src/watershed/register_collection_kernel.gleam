//// Pure port of FluidFramework's ConsensusRegisterCollection core semantics.
////
//// This kernel is not optimistic, the same as `claims_kernel`. A local write
//// is not visible until its op sequences. Unlike claims, the kernel keeps
//// every sequenced write as a version. It updates the atomic slot only if the
//// write knew the current atomic version
//// (`ref_seq >= atomic.sequence_number`).

import gleam/dict.{type Dict}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type RegisterState {
  RegisterState(registers: Dict(String, Register))
}

pub type Register {
  /// `atomic` is the linearizable winner. `versions` contains every value that
  /// is still concurrent, in sequence order, oldest first. An invariant keeps
  /// `versions` non-empty.
  Register(atomic: VersionedValue, versions: List(VersionedValue))
}

pub type VersionedValue {
  VersionedValue(value: Json, sequence_number: Int)
}

/// The one register-collection op. `ref_seq` is the last sequence number that
/// the author saw at submit time. A resubmit keeps that value.
pub type WriteOp {
  Write(key: String, value: Json, ref_seq: Int)
}

pub type RegisterEvent {
  /// The kernel emits this event only when the atomic (linearizable) value
  /// changes.
  AtomicChanged(key: String, value: Json, local: Bool)
  /// The kernel emits this event for every sequenced write, including a write
  /// that does not win the atomic slot.
  VersionChanged(key: String, value: Json, local: Bool)
}

pub type ReadPolicy {
  Atomic
  Lww
}

pub fn new() -> RegisterState {
  RegisterState(registers: dict.new())
}

/// Build the committed state from the summary entries. The summary contains
/// the sequence numbers, so the atomic compare-and-set and the version pruning
/// continue to work after a load.
pub fn from_summary(entries: List(#(String, Register))) -> RegisterState {
  let registers =
    list.fold(entries, dict.new(), fn(acc, entry) {
      let #(key, register) = entry
      dict.insert(acc, key, register)
    })
  RegisterState(registers: registers)
}

/// The summary entries in a stable order, sorted by key.
pub fn summary_registers(state: RegisterState) -> List(#(String, Register)) {
  dict.to_list(state.registers)
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
}

/// The committed value for `key` under `policy`. The result is `None` if the
/// key has no sequenced data. This read gives committed data only, and a
/// pending local write is not visible.
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

/// Every committed version for `key`, oldest first. The result is `None` if
/// the key is absent.
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

/// The attached submit path. Build an op with the last-seen sequence number
/// that the runtime supplies. The state does not change, because a read is not
/// optimistic.
pub fn write(
  _state: RegisterState,
  key: String,
  value: Json,
  last_seen_seq: Int,
) -> WriteOp {
  Write(key, value, last_seen_seq)
}

/// The detached apply path. There is no sequencer yet, so `ref_seq` and `seq`
/// are both zero.
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

/// A rollback resolves the deferred write result as false. There is no pending
/// kernel state to undo, because a write is not visible until its ack.
pub fn rollback(state: RegisterState, _op: WriteOp) -> #(RegisterState, Bool) {
  #(state, False)
}

/// The kernel resubmits a stashed op without a change. In particular, it keeps
/// `ref_seq`.
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
