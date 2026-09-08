//// A string register that preserves concurrent writes and their causal context.
//// Sequenced state excludes pending edits. Local operations retain their
//// original deltas through acknowledgement, rollback, and replay.

import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lattice_core/replica_id.{type ReplicaId}
import lattice_registers/mv_register.{type MVRegister}

pub type MvRegisterState {
  MvRegisterState(
    replica_id: ReplicaId,
    sequenced: MVRegister(String),
    optimistic: MVRegister(String),
    pending: List(PendingOp),
    next_pending_message_id: Int,
    /// Retain the authoring clock across rollback to prevent tag reuse.
    authored: MVRegister(String),
  )
}

pub type PendingOp {
  PendingOp(operation: MvRegisterOperation, message_id: Int)
}

pub type MvRegisterOperation {
  Set(value: String, delta: MVRegister(String))
}

pub type MvRegisterEvent {
  ValuesChanged(values: List(String))
}

pub type KernelError {
  UnexpectedAck(operation: MvRegisterOperation, detail: String)
  UnexpectedRollback(operation: MvRegisterOperation, detail: String)
}

pub fn new(replica_id: ReplicaId) -> MvRegisterState {
  from_sequenced(mv_register.new(replica_id), replica_id)
}

pub fn values(state: MvRegisterState) -> List(String) {
  visible(state.optimistic)
}

pub fn sequenced_values(state: MvRegisterState) -> List(String) {
  visible(state.sequenced)
}

fn visible(register: MVRegister(String)) -> List(String) {
  register |> mv_register.value |> list.sort(string.compare)
}

fn events_between(
  before: MvRegisterState,
  after: MvRegisterState,
) -> List(MvRegisterEvent) {
  case values(before) == values(after) {
    True -> []
    False -> [ValuesChanged(values(after))]
  }
}

pub fn set(
  state: MvRegisterState,
  value: String,
) -> #(MvRegisterState, List(MvRegisterEvent), MvRegisterOperation, Int) {
  let #(_, delta) =
    state.optimistic
    |> mv_register.merge(state.authored)
    |> mv_register.set_with_delta(value)
  apply_stashed_operation(state, Set(value, delta))
}

pub fn apply_stashed_operation(
  state: MvRegisterState,
  operation: MvRegisterOperation,
) -> #(MvRegisterState, List(MvRegisterEvent), MvRegisterOperation, Int) {
  let Set(_, delta) = operation
  let message_id = state.next_pending_message_id
  let next =
    MvRegisterState(
      ..state,
      optimistic: mv_register.merge(state.optimistic, delta),
      authored: mv_register.merge(state.authored, delta),
      pending: list.append(state.pending, [PendingOp(operation, message_id)]),
      next_pending_message_id: message_id + 1,
    )
  #(next, events_between(state, next), operation, message_id)
}

pub fn p2p_set(
  state: MvRegisterState,
  value: String,
) -> #(MvRegisterState, List(MvRegisterEvent), MvRegisterOperation) {
  let #(_, delta) =
    state.optimistic
    |> mv_register.merge(state.authored)
    |> mv_register.set_with_delta(value)
  let #(next, events) = p2p_merge(state, delta)
  #(
    MvRegisterState(..next, authored: mv_register.merge(state.authored, delta)),
    events,
    Set(value, delta),
  )
}

pub fn p2p_merge(
  state: MvRegisterState,
  other: MVRegister(String),
) -> #(MvRegisterState, List(MvRegisterEvent)) {
  let next =
    MvRegisterState(
      ..state,
      sequenced: mv_register.merge(state.sequenced, other),
      optimistic: mv_register.merge(state.optimistic, other),
    )
  #(next, events_between(state, next))
}

pub fn apply_remote(
  state: MvRegisterState,
  operation: MvRegisterOperation,
) -> #(MvRegisterState, List(MvRegisterEvent)) {
  let Set(_, delta) = operation
  p2p_merge(state, delta)
}

pub fn ack_local(
  state: MvRegisterState,
  operation: MvRegisterOperation,
) -> Result(MvRegisterState, KernelError) {
  do_ack(state, operation, None)
}

pub fn ack_local_with_message_id(
  state: MvRegisterState,
  operation: MvRegisterOperation,
  message_id: Int,
) -> Result(MvRegisterState, KernelError) {
  do_ack(state, operation, Some(message_id))
}

fn do_ack(
  state: MvRegisterState,
  operation: MvRegisterOperation,
  message_id: Option(Int),
) -> Result(MvRegisterState, KernelError) {
  case state.pending {
    [] -> Error(UnexpectedAck(operation, "pending queue is empty"))
    [PendingOp(expected, id), ..rest] -> {
      let matches_id = case message_id {
        None -> True
        Some(actual) -> actual == id
      }
      case operation == expected && matches_id {
        False ->
          Error(UnexpectedAck(
            operation,
            "ack does not match oldest pending write",
          ))
        True -> {
          let Set(_, delta) = operation
          Ok(
            MvRegisterState(
              ..state,
              sequenced: mv_register.merge(state.sequenced, delta),
              pending: rest,
            ),
          )
        }
      }
    }
  }
}

pub fn rollback(
  state: MvRegisterState,
  operation: MvRegisterOperation,
  message_id: Int,
) -> Result(#(MvRegisterState, List(MvRegisterEvent)), KernelError) {
  case list.reverse(state.pending) {
    [] -> Error(UnexpectedRollback(operation, "pending queue is empty"))
    [PendingOp(expected, id), ..rest] ->
      case operation == expected && message_id == id {
        False ->
          Error(UnexpectedRollback(
            operation,
            "rollback does not match newest pending write",
          ))
        True -> {
          let pending = list.reverse(rest)
          let next =
            MvRegisterState(
              ..state,
              pending: pending,
              optimistic: replay(state.sequenced, pending),
            )
          Ok(#(next, events_between(state, next)))
        }
      }
  }
}

fn replay(
  sequenced: MVRegister(String),
  pending: List(PendingOp),
) -> MVRegister(String) {
  list.fold(pending, sequenced, fn(acc, pending) {
    mv_register.merge(acc, pending.operation.delta)
  })
}

pub fn summary(state: MvRegisterState) -> json.Json {
  mv_register.to_json(state.sequenced)
}

/// Validate causal metadata before the lattice decoder builds its dictionaries.
/// Duplicate tags must not disappear during dictionary construction.
pub fn decode_crdt(
  source: String,
) -> Result(MVRegister(String), json.DecodeError) {
  let tag_decoder = {
    use replica <- decode.field("r", decode.string)
    use counter <- decode.field("c", decode.int)
    decode.success(#(replica, counter))
  }
  let metadata_decoder = {
    use metadata <- decode.field("state", {
      use tags <- decode.field(
        "entries",
        decode.list({
          use tag <- decode.field("tag", tag_decoder)
          decode.success(tag)
        }),
      )
      use clock <- decode.field(
        "vclock",
        decode.dict(decode.string, decode.int),
      )
      let valid =
        list.all(dict.values(clock), fn(counter) { counter >= 0 })
        && list.length(list.unique(tags)) == list.length(tags)
        && list.all(tags, fn(tag) {
          let #(replica, counter) = tag
          counter > 0 && counter <= result.unwrap(dict.get(clock, replica), 0)
        })
      case valid {
        True -> decode.success(Nil)
        False ->
          decode.failure(Nil, "unique tags within a nonnegative causal vector")
      }
    })
    decode.success(metadata)
  }
  use _ <- result.try(json.parse(source, metadata_decoder))
  mv_register.from_json(source)
}

pub fn from_summary(
  source: String,
  replica_id: ReplicaId,
) -> Result(MvRegisterState, json.DecodeError) {
  decode_crdt(source) |> result.map(from_sequenced(_, replica_id))
}

pub fn from_sequenced(
  register: MVRegister(String),
  replica_id: ReplicaId,
) -> MvRegisterState {
  let sequenced = mv_register.merge(mv_register.new(replica_id), register)
  MvRegisterState(
    replica_id: replica_id,
    sequenced: sequenced,
    optimistic: sequenced,
    pending: [],
    next_pending_message_id: 0,
    authored: sequenced,
  )
}

pub fn check_cache_coherence(state: MvRegisterState) -> Result(Nil, String) {
  case replay(state.sequenced, state.pending) == state.optimistic {
    True -> Ok(Nil)
    False ->
      Error("optimistic cache differs from sequenced state and pending writes")
  }
}
