//// A lattice-backed observed-remove map kernel.
////
//// This kernel holds one `lattice_maps/or_map.ORMap` in one of two value
//// modes. The first mode holds signed tallies, which are PN-counter leaves.
//// The second mode holds string registers, which are LWW-register leaves.
////
//// A local mutation calls `update_with_delta` or `remove_with_delta` to
//// produce a sparse delta only. The kernel then advances the state by applying
//// that delta with `apply_delta`. The author and the peers thus all store the
//// same join-of-deltas view.

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lattice_core/replica_id.{type ReplicaId}
import lattice_counters/pn_counter.{type PNCounter}
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
    /// The highest register timestamp that this replica has seen for each key,
    /// from a local write or a remote write. This is the logical half of a
    /// hybrid logical clock.
    ///
    /// The timestamp on a register write comes from a wall clock, and
    /// `lww_register` accepts a write only when its timestamp is *more* than
    /// the timestamp that it holds. A wall clock is not a logical clock. It
    /// does not move for a millisecond at a time, and it sometimes moves
    /// backwards. Either condition can leave two writes unordered when their
    /// order was never in doubt. This clock keeps the maximum for each key, so
    /// the kernel can stamp a local write above everything that it has seen
    /// for that key. A second write in the same millisecond thus applies
    /// instead of disappearing.
    ///
    /// The clock is per key, and not per channel. A key that changes often
    /// must not move an unchanged key into the future, where that key would
    /// win against a later write from a peer.
    ///
    /// `from_summary` and `from_sequenced` start this clock empty, because
    /// they cannot fill it. `lww_register` is opaque, so those paths have no
    /// timestamp to read. A client that joins against a *server* checkpoint
    /// can thus still lose its first write to a key, if the replica that wrote
    /// that checkpoint had a clock that ran ahead. The p2p path does not have
    /// that fault. `p2p_merge` reads the timestamp of each merged register
    /// through `lww_register.to_json` and adds it to this clock.
    register_clock: Dict(String, Int),
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
  /// The own tally of this replica for one key moved below zero. Both halves
  /// of a PN-counter are grow-only, so a count below zero is a broken state.
  NegativeTally(detail: String)
}

pub fn mode_to_spec(mode: OrMapMode) -> crdt.CrdtSpec {
  case mode {
    TallyMode -> crdt.PnCounterSpec
    RegisterMode -> crdt.LwwRegisterSpec
  }
}

pub fn spec_string_to_mode(spec: String) -> Result(OrMapMode, Nil) {
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
    register_clock: dict.new(),
    pending: [],
    next_pending_message_id: 0,
  )
}

pub fn keys(state: OrMapState) -> List(String) {
  entries(state) |> list.map(fn(entry) { entry.0 })
}

/// The visible value for a key. The result is `Error(Nil)` when the map holds
/// no value for that key.
pub fn get(state: OrMapState, key: String) -> Result(OrMapValue, Nil) {
  case or_map.get(state.optimistic, key) {
    Ok(value) -> crdt_to_value(value)
    Error(_) -> Error(Nil)
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
      let #(positive, negative) =
        dict.get(state.own_tallies, key) |> result.unwrap(#(0, 0))
      let #(new_positive, new_negative) = case amount >= 0 {
        True -> #(positive + amount, negative)
        False -> #(positive, negative + { 0 - amount })
      }
      use own_counter <- result.try(own_tally_counter(
        state.replica_id,
        new_positive,
        new_negative,
      ))
      use #(_discarded, delta) <- result.try(update_with_delta(
        state.optimistic,
        key,
        crdt.CrdtPnCounter(own_counter),
      ))
      use optimistic <- result.try(apply_delta(state.optimistic, delta))
      let message_id = state.next_pending_message_id
      let op = Increment(key, amount, delta)
      let new_state =
        OrMapState(
          ..state,
          optimistic: optimistic,
          own_tallies: dict.insert(state.own_tallies, key, #(
            new_positive,
            new_negative,
          )),
          pending: list.append(state.pending, [PendingOp(op, message_id)]),
          next_pending_message_id: message_id + 1,
        )
      let new_value = tally_of(new_state, key)
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
      let timestamp = stamp(state.register_clock, key, timestamp)
      let register = lww_register.new(value, timestamp, state.replica_id)
      use #(_discarded, delta) <- result.try(update_with_delta(
        state.optimistic,
        key,
        crdt.CrdtLwwRegister(register),
      ))
      use optimistic <- result.try(apply_delta(state.optimistic, delta))
      let message_id = state.next_pending_message_id
      let op = SetRegister(key, value, timestamp, delta)
      let new_state =
        OrMapState(
          ..state,
          optimistic: optimistic,
          register_clock: observe(state.register_clock, key, timestamp),
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

/// The timestamp for a local register write. The result is the wall clock,
/// unless this replica has already seen that instant or a later one for this
/// key. In that condition the result is one tick after the newest timestamp
/// that it has seen.
///
/// This is the complete fix for a lost second write in the same millisecond.
/// You cannot make that fix by changing the more-than comparison of
/// `lww_register` to a more-than-or-equal comparison. That comparison makes the
/// merge commutative, and the `replica_id` tie-break below it settles the
/// writes from different replicas that are truly concurrent. Only the *stamping*
/// side knows that these two writes are ordered.
fn stamp(clock: Dict(String, Int), key: String, wall_clock: Int) -> Int {
  case dict.get(clock, key) {
    Ok(seen) if seen >= wall_clock -> seen + 1
    Ok(_) -> wall_clock
    Error(Nil) -> wall_clock
  }
}

/// Record a timestamp as seen for a key. The clock keeps the maximum.
fn observe(
  clock: Dict(String, Int),
  key: String,
  timestamp: Int,
) -> Dict(String, Int) {
  case dict.get(clock, key) {
    Ok(seen) if seen >= timestamp -> clock
    Ok(_) -> dict.insert(clock, key, timestamp)
    Error(Nil) -> dict.insert(clock, key, timestamp)
  }
}

/// Record the timestamp that the write of a peer used. The next local write to
/// that key is thus above it. Without this record the two writes could be
/// equal, and the replica-id tie-break would then decide.
fn observe_op(clock: Dict(String, Int), op: OrMapOp) -> Dict(String, Int) {
  case op {
    SetRegister(key, _, timestamp, _) -> observe(clock, key, timestamp)
    Increment(_, _, _) | Remove(_, _) -> clock
  }
}

pub fn remove(
  state: OrMapState,
  key: String,
) -> Result(#(OrMapState, List(OrMapEvent), OrMapOp, Int), KernelError) {
  let before = entries(state)
  let #(_discarded, delta) = or_map.remove_with_delta(state.optimistic, key)
  use optimistic <- result.try(apply_delta(state.optimistic, delta))
  let message_id = state.next_pending_message_id
  let op = Remove(key, delta)
  let new_state =
    OrMapState(
      ..state,
      optimistic: optimistic,
      pending: list.append(state.pending, [PendingOp(op, message_id)]),
      next_pending_message_id: message_id + 1,
    )
  Ok(#(new_state, events_between(before, entries(new_state)), op, message_id))
}

/// The ack-free p2p form of `increment`. It writes the same delta, but it
/// merges that delta into the confirmed state and the visible state
/// immediately. It queues no pending entry for a later ack.
pub fn p2p_increment(
  state: OrMapState,
  key: String,
  amount: Int,
) -> Result(#(OrMapState, List(OrMapEvent), OrMapOp), KernelError) {
  case state.mode {
    RegisterMode -> Error(ModeMismatch("increment requires TallyMode"))
    TallyMode -> {
      let #(positive, negative) =
        dict.get(state.own_tallies, key) |> result.unwrap(#(0, 0))
      let #(new_positive, new_negative) = case amount >= 0 {
        True -> #(positive + amount, negative)
        False -> #(positive, negative + { 0 - amount })
      }
      use own_counter <- result.try(own_tally_counter(
        state.replica_id,
        new_positive,
        new_negative,
      ))
      use #(_discarded, delta) <- result.try(update_with_delta(
        state.optimistic,
        key,
        crdt.CrdtPnCounter(own_counter),
      ))
      use sequenced <- result.try(apply_delta(state.sequenced, delta))
      use optimistic <- result.try(apply_delta(state.optimistic, delta))
      let op = Increment(key, amount, delta)
      let new_state =
        OrMapState(
          ..state,
          sequenced: sequenced,
          optimistic: optimistic,
          own_tallies: dict.insert(state.own_tallies, key, #(
            new_positive,
            new_negative,
          )),
        )
      let new_value = tally_of(new_state, key)
      Ok(#(new_state, [TallyUpdated(key, amount, new_value)], op))
    }
  }
}

/// The ack-free p2p form of `set_register`. See `p2p_increment`.
pub fn p2p_set_register(
  state: OrMapState,
  key: String,
  value: String,
  timestamp: Int,
) -> Result(#(OrMapState, List(OrMapEvent), OrMapOp), KernelError) {
  case state.mode {
    TallyMode -> Error(ModeMismatch("set_register requires RegisterMode"))
    RegisterMode -> {
      let before = entries(state)
      let timestamp = stamp(state.register_clock, key, timestamp)
      let register = lww_register.new(value, timestamp, state.replica_id)
      use #(_discarded, delta) <- result.try(update_with_delta(
        state.optimistic,
        key,
        crdt.CrdtLwwRegister(register),
      ))
      use sequenced <- result.try(apply_delta(state.sequenced, delta))
      use optimistic <- result.try(apply_delta(state.optimistic, delta))
      let op = SetRegister(key, value, timestamp, delta)
      let new_state =
        OrMapState(
          ..state,
          sequenced: sequenced,
          optimistic: optimistic,
          register_clock: observe(state.register_clock, key, timestamp),
        )
      Ok(#(new_state, events_between(before, entries(new_state)), op))
    }
  }
}

/// The ack-free p2p form of `remove`.
pub fn p2p_remove(
  state: OrMapState,
  key: String,
) -> Result(#(OrMapState, List(OrMapEvent), OrMapOp), KernelError) {
  let before = entries(state)
  let #(_discarded, delta) = or_map.remove_with_delta(state.optimistic, key)
  use sequenced <- result.try(apply_delta(state.sequenced, delta))
  use optimistic <- result.try(apply_delta(state.optimistic, delta))
  let op = Remove(key, delta)
  let new_state =
    OrMapState(..state, sequenced: sequenced, optimistic: optimistic)
  Ok(#(new_state, events_between(before, entries(new_state)), op))
}

/// Merge the full confirmed CRDT state of a peer into this state. This is the
/// ack-free equivalent of `apply_remote`. It takes a `state` or `channel`
/// snapshot, not one delta. A lattice merge is a join, so it never discards a
/// winner.
///
/// In `RegisterMode` the function adds the timestamp of each merged register to
/// `register_clock`. A replica that starts from a peer with a clock that ran
/// ahead thus still wins its own next write to those keys. It does not lose
/// that write. The function reads each timestamp through
/// `lww_register.to_json`, because `LWWRegister` is opaque and gives access to
/// `value` only. That is one JSON round trip for each register. The function
/// thus runs on a merge, which is a bootstrap or a repair, and not on the path
/// of each op.
pub fn p2p_merge(
  state: OrMapState,
  other: ORMap,
) -> Result(#(OrMapState, List(OrMapEvent)), KernelError) {
  let before = entries(state)
  // `or_map.merge` compares the two maps' `crdt_spec` itself, and
  // `state.sequenced` always carries the spec of `state.mode`, so its
  // `TypeMismatch` *is* the mode check.
  case or_map.merge(state.sequenced, other) {
    Error(crdt.TypeMismatch(_, _)) ->
      Error(ModeMismatch("merged value spec does not match the channel mode"))
    Ok(sequenced) -> {
      use optimistic <- result.try(replay_pending(sequenced, state.pending))
      let new_state =
        OrMapState(
          ..state,
          sequenced: sequenced,
          optimistic: optimistic,
          register_clock: observe_registers(
            state.register_clock,
            state.mode,
            optimistic,
          ),
        )
      Ok(#(new_state, events_between(before, entries(new_state))))
    }
  }
}

/// Add the timestamp of every merged register to the clock, and keep the
/// maximum for each key. A `TallyMode` map holds no register, so the function
/// skips the whole map and does not walk it.
fn observe_registers(
  clock: Dict(String, Int),
  mode: OrMapMode,
  map: ORMap,
) -> Dict(String, Int) {
  case mode {
    TallyMode -> clock
    RegisterMode ->
      list.fold(or_map.keys(map), clock, fn(clock, key) {
        case or_map.get(map, key) {
          Ok(crdt.CrdtLwwRegister(register)) ->
            case register_timestamp(register) {
              Ok(timestamp) -> observe(clock, key, timestamp)
              Error(Nil) -> clock
            }
          Ok(crdt.CrdtGCounter(_))
          | Ok(crdt.CrdtPnCounter(_))
          | Ok(crdt.CrdtMvRegister(_))
          | Ok(crdt.CrdtGSet(_))
          | Ok(crdt.CrdtTwoPSet(_))
          | Ok(crdt.CrdtOrSet(_))
          | Ok(crdt.CrdtVersionVector(_))
          | Error(Nil) -> clock
        }
      })
  }
}

/// `LWWRegister` is opaque and has no accessor for its timestamp. But `to_json`
/// publishes the timestamp that the register merged on. The clock is thus
/// rebuilt from the value of the register, and not from a value that this
/// module invents.
fn register_timestamp(
  register: lww_register.LWWRegister(String),
) -> Result(Int, Nil) {
  json.parse(
    json.to_string(lww_register.to_json(register)),
    decode.at(["state", "timestamp"], decode.int),
  )
  |> result.replace_error(Nil)
}

pub fn apply_remote(
  state: OrMapState,
  op: OrMapOp,
) -> Result(#(OrMapState, List(OrMapEvent)), KernelError) {
  let before = entries(state)
  let delta = op_delta(op)
  use sequenced <- result.try(apply_delta(state.sequenced, delta))
  use optimistic <- result.try(replay_pending(sequenced, state.pending))
  let new_state =
    OrMapState(
      ..state,
      sequenced: sequenced,
      optimistic: optimistic,
      register_clock: observe_op(state.register_clock, op),
    )
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
          use optimistic <- result.try(replay_pending(state.sequenced, rest))
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
) -> Result(#(OrMapState, List(OrMapEvent), OrMapOp, Int), KernelError) {
  let before = entries(state)
  let delta = op_delta(op)
  use optimistic <- result.try(apply_delta(state.optimistic, delta))
  let message_id = state.next_pending_message_id
  let new_state =
    OrMapState(
      ..state,
      optimistic: optimistic,
      pending: list.append(state.pending, [PendingOp(op, message_id)]),
      next_pending_message_id: message_id + 1,
    )
  Ok(#(new_state, events_between(before, entries(new_state)), op, message_id))
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
    spec_string_to_mode(spec)
    |> result.map_error(fn(_) { unsupported_spec_error(spec) }),
  )
  use parsed <- result.try(or_map.from_json(summary_json))
  // The spec of `parsed` was read above, so this merge agrees by
  // construction. The error arm reports the same decode failure, so this
  // module never panics.
  use sequenced <- result.try(
    or_map.merge(or_map.new(replica_id, mode_to_spec(mode)), parsed)
    |> result.map_error(fn(_) { unsupported_spec_error(spec) }),
  )
  Ok(OrMapState(
    replica_id: replica_id,
    mode: mode,
    sequenced: sequenced,
    optimistic: sequenced,
    own_tallies: dict.new(),
    register_clock: dict.new(),
    pending: [],
    next_pending_message_id: 0,
  ))
}

pub fn from_sequenced(
  sequenced: ORMap,
  mode: OrMapMode,
  replica_id: ReplicaId,
) -> Result(OrMapState, KernelError) {
  // The merge's own `crdt_spec` comparison is the mode check; see
  // `p2p_merge`.
  case or_map.merge(or_map.new(replica_id, mode_to_spec(mode)), sequenced) {
    Error(crdt.TypeMismatch(_, _)) ->
      Error(ModeMismatch("summary value spec does not match requested mode"))
    Ok(rebranded) ->
      Ok(OrMapState(
        replica_id: replica_id,
        mode: mode,
        sequenced: rebranded,
        optimistic: rebranded,
        own_tallies: dict.new(),
        register_clock: dict.new(),
        pending: [],
        next_pending_message_id: 0,
      ))
  }
}

pub fn check_cache_coherence(state: OrMapState) -> Result(Nil, String) {
  case replay_pending(state.sequenced, state.pending) {
    Error(_) -> Error("a pending delta does not match the value mode")
    Ok(recomputed) ->
      case recomputed == state.optimistic {
        True -> Ok(Nil)
        False -> Error("optimistic cache diverged from sequenced + pending")
      }
  }
}

/// Build the PN-counter leaf that holds the own tally of this replica for one
/// key. Both counts are magnitudes, so both must be zero or more.
fn own_tally_counter(
  replica_id: ReplicaId,
  positive: Int,
  negative: Int,
) -> Result(PNCounter, KernelError) {
  use counter <- result.try(
    pn_counter.new(replica_id)
    |> pn_counter.try_increment(positive)
    |> result.replace_error(NegativeTally(
      "positive tally is " <> int.to_string(positive),
    )),
  )
  pn_counter.try_decrement(counter, negative)
  |> result.replace_error(NegativeTally(
    "negative tally is " <> int.to_string(negative),
  ))
}

fn rollback_own_tallies(
  own_tallies: Dict(String, #(Int, Int)),
  op: OrMapOp,
) -> Dict(String, #(Int, Int)) {
  case op {
    Increment(key, amount, _) -> {
      let #(positive, negative) =
        dict.get(own_tallies, key) |> result.unwrap(#(0, 0))
      let next = case amount >= 0 {
        True -> #(positive - amount, negative)
        False -> #(positive, negative - { 0 - amount })
      }
      dict.insert(own_tallies, key, next)
    }
    SetRegister(_, _, _, _) | Remove(_, _) -> own_tallies
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

/// Write one value at a key and return the map together with the sparse delta
/// for that write. The error arm reports a value that does not agree with the
/// value mode of the map.
fn update_with_delta(
  map: ORMap,
  key: String,
  value: crdt.Crdt,
) -> Result(#(ORMap, ORMapDelta), KernelError) {
  case or_map.update_with_delta(map, key, fn(_) { value }) {
    Ok(pair) -> Ok(pair)
    Error(crdt.TypeMismatch(expected, found)) ->
      Error(ModeMismatch("expected " <> expected <> " value, found " <> found))
  }
}

fn replay_pending(
  sequenced: ORMap,
  pending: List(PendingOp),
) -> Result(ORMap, KernelError) {
  list.try_fold(pending, sequenced, fn(acc, pending) {
    apply_delta(acc, op_delta(pending.op))
  })
}

/// The visible tally for a key. The result is zero when the map holds no
/// tally there.
fn tally_of(state: OrMapState, key: String) -> Int {
  case get(state, key) {
    Ok(Tally(value)) -> value
    Ok(Register(_)) | Error(Nil) -> 0
  }
}

fn map_entries(map: ORMap) -> List(#(String, OrMapValue)) {
  or_map.keys(map)
  |> list.sort(by: string.compare)
  |> list.filter_map(fn(key) {
    case or_map.get(map, key) {
      Ok(value) ->
        crdt_to_value(value) |> result.map(fn(value) { #(key, value) })
      Error(_) -> Error(Nil)
    }
  })
}

/// Read a lattice value as a kernel value. The result is `Error(Nil)` for a
/// lattice value that neither map mode holds. The value mode of the map keeps
/// such a value out, so this arm reports a broken map instead of a panic.
fn crdt_to_value(value: crdt.Crdt) -> Result(OrMapValue, Nil) {
  case value {
    crdt.CrdtPnCounter(counter) -> Ok(Tally(pn_counter.value(counter)))
    crdt.CrdtLwwRegister(register) -> Ok(Register(lww_register.value(register)))
    crdt.CrdtGCounter(_)
    | crdt.CrdtMvRegister(_)
    | crdt.CrdtGSet(_)
    | crdt.CrdtTwoPSet(_)
    | crdt.CrdtOrSet(_)
    | crdt.CrdtVersionVector(_) -> Error(Nil)
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
      Error(Nil), Error(Nil) -> Error(Nil)
      Ok(_), Error(Nil) -> Ok(KeyRemoved(key))
      Error(Nil), Ok(Tally(value)) -> Ok(TallyUpdated(key, value, value))
      Error(Nil), Ok(Register(value)) -> Ok(RegisterUpdated(key, value))
      Ok(Tally(old)), Ok(Tally(new)) ->
        case old == new {
          True -> Error(Nil)
          False -> Ok(TallyUpdated(key, new - old, new))
        }
      Ok(Register(old)), Ok(Register(new)) ->
        case old == new {
          True -> Error(Nil)
          False -> Ok(RegisterUpdated(key, new))
        }
      // One map holds one value mode, so a key never changes mode. The arm
      // reports no event, the same as an unchanged key.
      Ok(Tally(_)), Ok(Register(_)) | Ok(Register(_)), Ok(Tally(_)) ->
        Error(Nil)
    }
  })
}

fn entry_value(
  entries: List(#(String, OrMapValue)),
  key: String,
) -> Result(OrMapValue, Nil) {
  entries
  |> list.find(fn(entry) { entry.0 == key })
  |> result.map(fn(entry) { entry.1 })
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

fn unsupported_spec_error(spec: String) -> json.DecodeError {
  json.UnableToDecode([
    decode.DecodeError(
      expected: "pn_counter or lww_register",
      found: spec,
      path: ["state", "crdt_spec"],
    ),
  ])
}
