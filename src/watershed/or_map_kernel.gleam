//// A lattice-backed observed-remove map kernel.
////
//// This kernel hosts an `lattice_maps/or_map.ORMap` in one of two value modes:
//// signed tallies (PN-counter leaves) or string registers (LWW-register
//// leaves). Local mutations use `update_with_delta`/`remove_with_delta` only to
//// produce sparse deltas; state is advanced by applying those deltas back with
//// `apply_delta`, so authors and peers both store the same join-of-deltas view.

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lattice_core/replica_id.{type ReplicaId}
import lattice_counters/pn_counter
import lattice_maps/crdt
import lattice_maps/or_map.{type ORMap, type ORMapDelta}
import lattice_registers/lww_register

pub type OrMapMode {
  TallyMode
  RegisterMode
}

pub type OrMapValue {
  Tally(Int)
  Register(String)
}

pub type OrMapState {
  OrMapState(
    replica_id: ReplicaId,
    mode: OrMapMode,
    sequenced: ORMap,
    optimistic: ORMap,
    own_tallies: Dict(String, #(Int, Int)),
    pending: List(PendingOp),
    next_pending_message_id: Int,
  )
}

pub type PendingOp {
  PendingOp(op: OrMapOp, message_id: Int)
}

pub type OrMapOp {
  Increment(key: String, amount: Int, delta: ORMapDelta)
  SetRegister(key: String, value: String, timestamp: Int, delta: ORMapDelta)
  Remove(key: String, delta: ORMapDelta)
}

pub type OrMapEvent {
  TallyUpdated(key: String, applied: Int, new_value: Int)
  RegisterUpdated(key: String, value: String)
  KeyRemoved(key: String)
}

pub type KernelError {
  UnexpectedAck(detail: String)
  UnexpectedRollback(detail: String)
  ModeMismatch(detail: String)
  CorruptDelta(detail: String)
}

pub fn mode_to_spec(mode: OrMapMode) -> crdt.CrdtSpec {
  case mode {
    TallyMode -> crdt.PnCounterSpec
    RegisterMode -> crdt.LwwRegisterSpec
  }
}

pub fn mode_from_spec_string(spec: String) -> Result(OrMapMode, Nil) {
  case spec {
    "pn_counter" -> Ok(TallyMode)
    "lww_register" -> Ok(RegisterMode)
    _ -> Error(Nil)
  }
}

pub fn new(replica_id: ReplicaId, mode: OrMapMode) -> OrMapState {
  let empty = or_map.new(replica_id, mode_to_spec(mode))
  OrMapState(
    replica_id: replica_id,
    mode: mode,
    sequenced: empty,
    optimistic: empty,
    own_tallies: dict.new(),
    pending: [],
    next_pending_message_id: 0,
  )
}

pub fn keys(state: OrMapState) -> List(String) {
  entries(state) |> list.map(fn(entry) { entry.0 })
}

pub fn get(state: OrMapState, key: String) -> Option(OrMapValue) {
  case or_map.get(state.optimistic, key) {
    Ok(value) -> Some(crdt_to_value(value))
    Error(_) -> None
  }
}

pub fn entries(state: OrMapState) -> List(#(String, OrMapValue)) {
  map_entries(state.optimistic)
}

pub fn sequenced_entries(state: OrMapState) -> List(#(String, OrMapValue)) {
  map_entries(state.sequenced)
}

pub fn increment(
  state: OrMapState,
  key: String,
  amount: Int,
) -> Result(#(OrMapState, List(OrMapEvent), OrMapOp, Int), KernelError) {
  case state.mode {
    RegisterMode -> Error(ModeMismatch("increment requires TallyMode"))
    TallyMode -> {
      let #(pos, neg) =
        dict.get(state.own_tallies, key) |> result.unwrap(#(0, 0))
      let #(new_pos, new_neg) = case amount >= 0 {
        True -> #(pos + amount, neg)
        False -> #(pos, neg + { 0 - amount })
      }
      let own_counter = own_tally_counter(state.replica_id, new_pos, new_neg)
      let assert Ok(#(_discarded, delta)) =
        or_map.update_with_delta(state.optimistic, key, fn(_) {
          crdt.CrdtPnCounter(own_counter)
        })
      let assert Ok(optimistic) = or_map.apply_delta(state.optimistic, delta)
      let message_id = state.next_pending_message_id
      let op = Increment(key, amount, delta)
      let new_state =
        OrMapState(
          ..state,
          optimistic: optimistic,
          own_tallies: dict.insert(state.own_tallies, key, #(new_pos, new_neg)),
          pending: list.append(state.pending, [PendingOp(op, message_id)]),
          next_pending_message_id: message_id + 1,
        )
      let new_value = case get(new_state, key) {
        Some(Tally(value)) -> value
        _ -> 0
      }
      Ok(#(new_state, [TallyUpdated(key, amount, new_value)], op, message_id))
    }
  }
}

pub fn set_register(
  state: OrMapState,
  key: String,
  value: String,
  timestamp: Int,
) -> Result(#(OrMapState, List(OrMapEvent), OrMapOp, Int), KernelError) {
  case state.mode {
    TallyMode -> Error(ModeMismatch("set_register requires RegisterMode"))
    RegisterMode -> {
      let before = entries(state)
      let register = lww_register.new(value, timestamp, state.replica_id)
      let assert Ok(#(_discarded, delta)) =
        or_map.update_with_delta(state.optimistic, key, fn(_) {
          crdt.CrdtLwwRegister(register)
        })
      let assert Ok(optimistic) = or_map.apply_delta(state.optimistic, delta)
      let message_id = state.next_pending_message_id
      let op = SetRegister(key, value, timestamp, delta)
      let new_state =
        OrMapState(
          ..state,
          optimistic: optimistic,
          pending: list.append(state.pending, [PendingOp(op, message_id)]),
          next_pending_message_id: message_id + 1,
        )
      Ok(#(
        new_state,
        events_between(before, entries(new_state)),
        op,
        message_id,
      ))
    }
  }
}

pub fn remove(
  state: OrMapState,
  key: String,
) -> #(OrMapState, List(OrMapEvent), OrMapOp, Int) {
  let before = entries(state)
  let #(_discarded, delta) = or_map.remove_with_delta(state.optimistic, key)
  let assert Ok(optimistic) = or_map.apply_delta(state.optimistic, delta)
  let message_id = state.next_pending_message_id
  let op = Remove(key, delta)
  let new_state =
    OrMapState(
      ..state,
      optimistic: optimistic,
      pending: list.append(state.pending, [PendingOp(op, message_id)]),
      next_pending_message_id: message_id + 1,
    )
  #(new_state, events_between(before, entries(new_state)), op, message_id)
}

pub fn apply_remote(
  state: OrMapState,
  op: OrMapOp,
) -> Result(#(OrMapState, List(OrMapEvent)), KernelError) {
  let before = entries(state)
  let delta = op_delta(op)
  use sequenced <- result.try(apply_delta(state.sequenced, delta))
  let optimistic = replay_pending(sequenced, state.pending)
  let new_state =
    OrMapState(..state, sequenced: sequenced, optimistic: optimistic)
  Ok(#(new_state, events_between(before, entries(new_state))))
}

pub fn ack_local(
  state: OrMapState,
  op: OrMapOp,
) -> Result(OrMapState, KernelError) {
  do_ack(state, op, None)
}

pub fn ack_local_with_message_id(
  state: OrMapState,
  op: OrMapOp,
  message_id: Int,
) -> Result(OrMapState, KernelError) {
  do_ack(state, op, Some(message_id))
}

fn do_ack(
  state: OrMapState,
  op: OrMapOp,
  expected_message_id: Option(Int),
) -> Result(OrMapState, KernelError) {
  case state.pending {
    [] -> Error(UnexpectedAck("pending queue is empty"))
    [PendingOp(pending_op, pending_message_id), ..rest] -> {
      let message_id_matches = case expected_message_id {
        None -> True
        Some(message_id) -> message_id == pending_message_id
      }
      case pending_op == op && message_id_matches {
        True -> {
          use sequenced <- result.try(apply_delta(state.sequenced, op_delta(op)))
          Ok(OrMapState(..state, sequenced: sequenced, pending: rest))
        }
        False ->
          Error(UnexpectedAck(
            "expected pending op with message id "
            <> int.to_string(pending_message_id)
            <> ", got message id "
            <> case expected_message_id {
              Some(message_id) -> int.to_string(message_id)
              None -> "unvalidated"
            },
          ))
      }
    }
  }
}

pub fn rollback(
  state: OrMapState,
  op: OrMapOp,
  message_id: Int,
) -> Result(#(OrMapState, List(OrMapEvent)), KernelError) {
  case pop_last(state.pending) {
    Error(_) -> Error(UnexpectedRollback("pending queue is empty"))
    Ok(#(PendingOp(pending_op, pending_message_id), rest)) ->
      case pending_op == op && pending_message_id == message_id {
        False ->
          Error(UnexpectedRollback(
            "expected newest pending op with message id "
            <> int.to_string(pending_message_id)
            <> ", got message id "
            <> int.to_string(message_id),
          ))
        True -> {
          let before = entries(state)
          let own_tallies = rollback_own_tallies(state.own_tallies, op)
          let optimistic = replay_pending(state.sequenced, rest)
          let new_state =
            OrMapState(
              ..state,
              optimistic: optimistic,
              own_tallies: own_tallies,
              pending: rest,
            )
          Ok(#(new_state, events_between(before, entries(new_state))))
        }
      }
  }
}

pub fn apply_stashed_op(
  state: OrMapState,
  op: OrMapOp,
) -> #(OrMapState, List(OrMapEvent), OrMapOp, Int) {
  let before = entries(state)
  let delta = op_delta(op)
  let assert Ok(optimistic) = or_map.apply_delta(state.optimistic, delta)
  let message_id = state.next_pending_message_id
  let new_state =
    OrMapState(
      ..state,
      optimistic: optimistic,
      pending: list.append(state.pending, [PendingOp(op, message_id)]),
      next_pending_message_id: message_id + 1,
    )
  #(new_state, events_between(before, entries(new_state)), op, message_id)
}

pub fn promote_attach(state: OrMapState) -> OrMapState {
  OrMapState(..state, sequenced: state.optimistic, pending: [])
}

pub fn summary(state: OrMapState) -> Json {
  or_map.to_json(state.sequenced)
}

pub fn from_summary(
  summary_json: String,
  replica_id: ReplicaId,
) -> Result(OrMapState, json.DecodeError) {
  use spec <- result.try(json.parse(
    summary_json,
    decode.at(["state", "crdt_spec"], decode.string),
  ))
  use mode <- result.try(
    mode_from_spec_string(spec)
    |> result.map_error(fn(_) { unsupported_spec_error(spec) }),
  )
  use parsed <- result.try(or_map.from_json(summary_json))
  let assert Ok(sequenced) =
    or_map.merge(or_map.new(replica_id, mode_to_spec(mode)), parsed)
  Ok(OrMapState(
    replica_id: replica_id,
    mode: mode,
    sequenced: sequenced,
    optimistic: sequenced,
    own_tallies: dict.new(),
    pending: [],
    next_pending_message_id: 0,
  ))
}

pub fn from_sequenced(
  sequenced: ORMap,
  mode: OrMapMode,
  replica_id: ReplicaId,
) -> Result(OrMapState, KernelError) {
  case mode_of_map(sequenced) {
    Error(_) -> Error(CorruptDelta("could not read ORMap crdt_spec"))
    Ok(actual) if actual != mode ->
      Error(ModeMismatch("summary value spec does not match requested mode"))
    Ok(_) -> {
      let assert Ok(rebranded) =
        or_map.merge(or_map.new(replica_id, mode_to_spec(mode)), sequenced)
      Ok(OrMapState(
        replica_id: replica_id,
        mode: mode,
        sequenced: rebranded,
        optimistic: rebranded,
        own_tallies: dict.new(),
        pending: [],
        next_pending_message_id: 0,
      ))
    }
  }
}

pub fn check_cache_coherence(state: OrMapState) -> Result(Nil, String) {
  let recomputed = replay_pending(state.sequenced, state.pending)
  case recomputed == state.optimistic {
    True -> Ok(Nil)
    False -> Error("optimistic cache diverged from sequenced + pending")
  }
}

fn own_tally_counter(replica_id: ReplicaId, pos: Int, neg: Int) {
  let assert Ok(counter) =
    pn_counter.new(replica_id)
    |> pn_counter.try_increment(pos)
  let assert Ok(counter) = pn_counter.try_decrement(counter, neg)
  counter
}

fn rollback_own_tallies(
  own_tallies: Dict(String, #(Int, Int)),
  op: OrMapOp,
) -> Dict(String, #(Int, Int)) {
  case op {
    Increment(key, amount, _) -> {
      let #(pos, neg) = dict.get(own_tallies, key) |> result.unwrap(#(0, 0))
      let next = case amount >= 0 {
        True -> #(pos - amount, neg)
        False -> #(pos, neg - { 0 - amount })
      }
      dict.insert(own_tallies, key, next)
    }
    _ -> own_tallies
  }
}

fn op_delta(op: OrMapOp) -> ORMapDelta {
  case op {
    Increment(_, _, delta) -> delta
    SetRegister(_, _, _, delta) -> delta
    Remove(_, delta) -> delta
  }
}

fn apply_delta(map: ORMap, delta: ORMapDelta) -> Result(ORMap, KernelError) {
  case or_map.apply_delta(map, delta) {
    Ok(map) -> Ok(map)
    Error(crdt.TypeMismatch(expected, found)) ->
      Error(CorruptDelta("expected " <> expected <> " delta, found " <> found))
  }
}

fn replay_pending(sequenced: ORMap, pending: List(PendingOp)) -> ORMap {
  list.fold(pending, sequenced, fn(acc, pending) {
    let assert Ok(next) = or_map.apply_delta(acc, op_delta(pending.op))
    next
  })
}

fn map_entries(map: ORMap) -> List(#(String, OrMapValue)) {
  or_map.keys(map)
  |> list.sort(by: string.compare)
  |> list.filter_map(fn(key) {
    case or_map.get(map, key) {
      Ok(value) -> Ok(#(key, crdt_to_value(value)))
      Error(_) -> Error(Nil)
    }
  })
}

fn crdt_to_value(value: crdt.Crdt) -> OrMapValue {
  case value {
    crdt.CrdtPnCounter(counter) -> Tally(pn_counter.value(counter))
    crdt.CrdtLwwRegister(register) -> Register(lww_register.value(register))
    _ -> panic as "ORMap value did not match the kernel mode"
  }
}

fn events_between(
  before: List(#(String, OrMapValue)),
  after: List(#(String, OrMapValue)),
) -> List(OrMapEvent) {
  let keys =
    list.append(
      list.map(before, fn(entry) { entry.0 }),
      list.map(after, fn(entry) { entry.0 }),
    )
    |> list.unique
    |> list.sort(by: string.compare)

  list.filter_map(keys, fn(key) {
    case entry_value(before, key), entry_value(after, key) {
      None, None -> Error(Nil)
      Some(_), None -> Ok(KeyRemoved(key))
      None, Some(Tally(value)) -> Ok(TallyUpdated(key, value, value))
      Some(Tally(old)), Some(Tally(new)) if old != new ->
        Ok(TallyUpdated(key, new - old, new))
      None, Some(Register(value)) -> Ok(RegisterUpdated(key, value))
      Some(Register(old)), Some(Register(new)) if old != new ->
        Ok(RegisterUpdated(key, new))
      _, _ -> Error(Nil)
    }
  })
}

fn entry_value(
  entries: List(#(String, OrMapValue)),
  key: String,
) -> Option(OrMapValue) {
  entries
  |> list.find(fn(entry) { entry.0 == key })
  |> result.map(fn(entry) { entry.1 })
  |> option.from_result
}

fn pop_last(
  pending: List(PendingOp),
) -> Result(#(PendingOp, List(PendingOp)), Nil) {
  case pending {
    [] -> Error(Nil)
    [only] -> Ok(#(only, []))
    [head, ..rest] ->
      case pop_last(rest) {
        Error(_) -> Error(Nil)
        Ok(#(last, init)) -> Ok(#(last, [head, ..init]))
      }
  }
}

fn mode_of_map(map: ORMap) -> Result(OrMapMode, json.DecodeError) {
  let json_string = json.to_string(or_map.to_json(map))
  use spec <- result.try(json.parse(
    json_string,
    decode.at(["state", "crdt_spec"], decode.string),
  ))
  mode_from_spec_string(spec)
  |> result.map_error(fn(_) { unsupported_spec_error(spec) })
}

fn unsupported_spec_error(spec: String) -> json.DecodeError {
  json.UnableToDecode([
    decode.DecodeError(
      expected: "pn_counter or lww_register",
      found: spec,
      path: ["state", "crdt_spec"],
    ),
  ])
}
