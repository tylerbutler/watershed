//// A lattice-backed observed-remove map kernel.
////
//// This kernel holds one `lattice_maps/or_map.ORMap` in one of three value
//// modes. The first mode holds signed tallies, which are PN-counter leaves.
//// The second mode holds string registers, which are LWW-register leaves.
//// The third mode holds observed-remove sets of strings.
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
import gleam/set
import gleam/string
import lattice_core/replica_id.{type ReplicaId}
import lattice_counters/pn_counter.{type PNCounter}
import lattice_maps/crdt
import lattice_maps/or_map.{type ORMap, type ORMapDelta}
import lattice_registers/lww_register
import lattice_sets/or_set
import watershed/canonical_json
import watershed/or_map_set_leaf

pub type OrMapMode {
  TallyMode
  RegisterMode
  OrSetMode
}

pub type OrMapValue {
  Tally(Int)
  Register(String)
  SetMembers(List(String))
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
    set_clocks: or_map_set_leaf.Clocks,
    pending: List(PendingOperation),
    next_pending_message_id: Int,
  )
}

pub type PendingOperation {
  PendingOperation(operation: OrMapOperation, message_id: Int)
}

pub type OrMapOperation {
  Increment(key: String, amount: Int, delta: ORMapDelta)
  SetRegister(key: String, value: String, timestamp: Int, delta: ORMapDelta)
  Remove(key: String, delta: ORMapDelta)
  AddMember(key: String, member: String, delta: ORMapDelta)
  RemoveMember(key: String, member: String, delta: ORMapDelta)
}

pub type OrMapEvent {
  TallyUpdated(key: String, applied: Int, new_value: Int)
  RegisterUpdated(key: String, value: String)
  SetMembersUpdated(key: String, members: List(String))
  KeyRemoved(key: String)
}

pub type KernelError {
  UnexpectedAck(detail: String)
  UnexpectedRollback(detail: String)
  ModeMismatch(detail: String)
  CorruptDelta(detail: String)
  InvalidSetState(detail: String)
  CounterExhausted(detail: String)
  /// The own tally of this replica for one key moved below zero. Both halves
  /// of a PN-counter are grow-only, so a count below zero is a broken state.
  NegativeTally(detail: String)
}

pub fn mode_to_spec(mode: OrMapMode) -> crdt.CrdtSpec {
  case mode {
    TallyMode -> crdt.PnCounterSpec
    RegisterMode -> crdt.LwwRegisterSpec
    OrSetMode -> crdt.OrSetSpec
  }
}

pub fn spec_string_to_mode(spec: String) -> Result(OrMapMode, Nil) {
  case spec {
    "pn_counter" -> Ok(TallyMode)
    "lww_register" -> Ok(RegisterMode)
    "or_set" -> Ok(OrSetMode)
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
    set_clocks: or_map_set_leaf.new_clocks(),
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
  map_entries(state.optimistic, state.mode)
}

pub fn sequenced_entries(state: OrMapState) -> List(#(String, OrMapValue)) {
  map_entries(state.sequenced, state.mode)
}

pub fn increment(
  state: OrMapState,
  key: String,
  amount: Int,
) -> Result(#(OrMapState, List(OrMapEvent), OrMapOperation, Int), KernelError) {
  case state.mode {
    RegisterMode | OrSetMode ->
      Error(ModeMismatch("increment requires TallyMode"))
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
      let operation = Increment(key, amount, delta)
      let new_state =
        OrMapState(
          ..state,
          optimistic: optimistic,
          own_tallies: dict.insert(state.own_tallies, key, #(
            new_positive,
            new_negative,
          )),
          pending: list.append(state.pending, [
            PendingOperation(operation, message_id),
          ]),
          next_pending_message_id: message_id + 1,
        )
      let new_value = tally_of(new_state, key)
      Ok(#(
        new_state,
        [TallyUpdated(key, amount, new_value)],
        operation,
        message_id,
      ))
    }
  }
}

pub fn set_register(
  state: OrMapState,
  key: String,
  value: String,
  timestamp: Int,
) -> Result(#(OrMapState, List(OrMapEvent), OrMapOperation, Int), KernelError) {
  case state.mode {
    TallyMode | OrSetMode ->
      Error(ModeMismatch("set_register requires RegisterMode"))
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
      let operation = SetRegister(key, value, timestamp, delta)
      let new_state =
        OrMapState(
          ..state,
          optimistic: optimistic,
          register_clock: observe(state.register_clock, key, timestamp),
          pending: list.append(state.pending, [
            PendingOperation(operation, message_id),
          ]),
          next_pending_message_id: message_id + 1,
        )
      Ok(#(
        new_state,
        events_between(before, entries(new_state)),
        operation,
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
fn observe_operation(
  clock: Dict(String, Int),
  operation: OrMapOperation,
) -> Dict(String, Int) {
  case operation {
    SetRegister(key, _, timestamp, _) -> observe(clock, key, timestamp)
    Increment(_, _, _)
    | Remove(_, _)
    | AddMember(_, _, _)
    | RemoveMember(_, _, _) -> clock
  }
}

pub fn remove(
  state: OrMapState,
  key: String,
) -> Result(#(OrMapState, List(OrMapEvent), OrMapOperation, Int), KernelError) {
  case state.mode {
    OrSetMode -> edit_set(state, key, or_map_set_leaf.RemoveKey, False)
    TallyMode | RegisterMode -> remove_legacy(state, key)
  }
}

fn remove_legacy(
  state: OrMapState,
  key: String,
) -> Result(#(OrMapState, List(OrMapEvent), OrMapOperation, Int), KernelError) {
  let before = entries(state)
  let #(_discarded, delta) = or_map.remove_with_delta(state.optimistic, key)
  use optimistic <- result.try(apply_delta(state.optimistic, delta))
  let message_id = state.next_pending_message_id
  let operation = Remove(key, delta)
  let new_state =
    OrMapState(
      ..state,
      optimistic: optimistic,
      pending: list.append(state.pending, [
        PendingOperation(operation, message_id),
      ]),
      next_pending_message_id: message_id + 1,
    )
  Ok(#(
    new_state,
    events_between(before, entries(new_state)),
    operation,
    message_id,
  ))
}

/// The ack-free p2p form of `increment`. It writes the same delta, but it
/// merges that delta into the confirmed state and the visible state
/// immediately. It queues no pending entry for a later ack.
pub fn p2p_increment(
  state: OrMapState,
  key: String,
  amount: Int,
) -> Result(#(OrMapState, List(OrMapEvent), OrMapOperation), KernelError) {
  case state.mode {
    RegisterMode | OrSetMode ->
      Error(ModeMismatch("increment requires TallyMode"))
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
      let operation = Increment(key, amount, delta)
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
      Ok(#(new_state, [TallyUpdated(key, amount, new_value)], operation))
    }
  }
}

/// The ack-free p2p form of `set_register`. See `p2p_increment`.
pub fn p2p_set_register(
  state: OrMapState,
  key: String,
  value: String,
  timestamp: Int,
) -> Result(#(OrMapState, List(OrMapEvent), OrMapOperation), KernelError) {
  case state.mode {
    TallyMode | OrSetMode ->
      Error(ModeMismatch("set_register requires RegisterMode"))
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
      let operation = SetRegister(key, value, timestamp, delta)
      let new_state =
        OrMapState(
          ..state,
          sequenced: sequenced,
          optimistic: optimistic,
          register_clock: observe(state.register_clock, key, timestamp),
        )
      Ok(#(new_state, events_between(before, entries(new_state)), operation))
    }
  }
}

/// The ack-free p2p form of `remove`.
pub fn p2p_remove(
  state: OrMapState,
  key: String,
) -> Result(#(OrMapState, List(OrMapEvent), OrMapOperation), KernelError) {
  case state.mode {
    OrSetMode ->
      edit_set(state, key, or_map_set_leaf.RemoveKey, True)
      |> result.map(fn(edit) { #(edit.0, edit.1, edit.2) })
    TallyMode | RegisterMode -> p2p_remove_legacy(state, key)
  }
}

fn p2p_remove_legacy(
  state: OrMapState,
  key: String,
) -> Result(#(OrMapState, List(OrMapEvent), OrMapOperation), KernelError) {
  let before = entries(state)
  let #(_discarded, delta) = or_map.remove_with_delta(state.optimistic, key)
  use sequenced <- result.try(apply_delta(state.sequenced, delta))
  use optimistic <- result.try(apply_delta(state.optimistic, delta))
  let operation = Remove(key, delta)
  let new_state =
    OrMapState(..state, sequenced: sequenced, optimistic: optimistic)
  Ok(#(new_state, events_between(before, entries(new_state)), operation))
}

pub fn add_member(
  state: OrMapState,
  key: String,
  member: String,
) -> Result(#(OrMapState, List(OrMapEvent), OrMapOperation, Int), KernelError) {
  edit_set(state, key, or_map_set_leaf.AddMember(member), False)
}

pub fn remove_member(
  state: OrMapState,
  key: String,
  member: String,
) -> Result(#(OrMapState, List(OrMapEvent), OrMapOperation, Int), KernelError) {
  edit_set(state, key, or_map_set_leaf.RemoveMember(member), False)
}

pub fn p2p_add_member(
  state: OrMapState,
  key: String,
  member: String,
) -> Result(#(OrMapState, List(OrMapEvent), OrMapOperation), KernelError) {
  edit_set(state, key, or_map_set_leaf.AddMember(member), True)
  |> result.map(fn(edit) { #(edit.0, edit.1, edit.2) })
}

pub fn p2p_remove_member(
  state: OrMapState,
  key: String,
  member: String,
) -> Result(#(OrMapState, List(OrMapEvent), OrMapOperation), KernelError) {
  edit_set(state, key, or_map_set_leaf.RemoveMember(member), True)
  |> result.map(fn(edit) { #(edit.0, edit.1, edit.2) })
}

fn edit_set(
  state: OrMapState,
  key: String,
  intent: or_map_set_leaf.Intent,
  confirmed: Bool,
) -> Result(#(OrMapState, List(OrMapEvent), OrMapOperation, Int), KernelError) {
  case state.mode {
    TallyMode | RegisterMode ->
      Error(ModeMismatch("member edits require OrSetMode"))
    OrSetMode -> {
      let before = entries(state)
      use state <- result.try(retain_set_clocks(state))
      use #(delta, clocks) <- result.try(
        case intent {
          or_map_set_leaf.AddMember(member) ->
            or_map_set_leaf.add(
              state.optimistic,
              state.set_clocks,
              state.replica_id,
              key,
              member,
            )
          or_map_set_leaf.RemoveMember(member) ->
            or_map_set_leaf.remove_member(
              state.optimistic,
              state.set_clocks,
              state.replica_id,
              key,
              member,
            )
          or_map_set_leaf.RemoveKey ->
            or_map_set_leaf.remove_key(
              state.optimistic,
              state.set_clocks,
              state.replica_id,
              key,
            )
        }
        |> result.map_error(set_error),
      )
      let operation = case intent {
        or_map_set_leaf.AddMember(member) -> AddMember(key, member, delta)
        or_map_set_leaf.RemoveMember(member) -> RemoveMember(key, member, delta)
        or_map_set_leaf.RemoveKey -> Remove(key, delta)
      }
      use _ <- result.try(validate_operation(state.mode, operation))
      // Reserve only the empty authoring seed in confirmed state.
      use state <- result.try(retain_set_clocks(
        OrMapState(..state, set_clocks: clocks),
      ))
      use optimistic <- result.try(apply_delta(state.optimistic, delta))
      use sequenced <- result.try(case confirmed {
        True -> apply_delta(state.sequenced, delta)
        False -> Ok(state.sequenced)
      })
      let message_id = state.next_pending_message_id
      let pending = case confirmed {
        True -> state.pending
        False ->
          list.append(state.pending, [PendingOperation(operation, message_id)])
      }
      use new_state <- result.try(retain_set_clocks(
        OrMapState(
          ..state,
          sequenced: sequenced,
          optimistic: optimistic,
          pending: pending,
          next_pending_message_id: case confirmed {
            True -> message_id
            False -> message_id + 1
          },
        ),
      ))
      Ok(#(
        new_state,
        events_between(before, entries(new_state)),
        operation,
        message_id,
      ))
    }
  }
}

/// Validate typed operations before native merges can normalize their state.
@internal
pub fn validate_operation(
  mode: OrMapMode,
  operation: OrMapOperation,
) -> Result(Nil, KernelError) {
  case mode, operation {
    OrSetMode, AddMember(key, member, delta) ->
      or_map_set_leaf.validate_intent(
        delta,
        key,
        or_map_set_leaf.AddMember(member),
      )
      |> result.map_error(set_error)
    OrSetMode, RemoveMember(key, member, delta) ->
      or_map_set_leaf.validate_intent(
        delta,
        key,
        or_map_set_leaf.RemoveMember(member),
      )
      |> result.map_error(set_error)
    OrSetMode, Remove(key, delta) ->
      or_map_set_leaf.validate_intent(delta, key, or_map_set_leaf.RemoveKey)
      |> result.map_error(set_error)
    TallyMode, Increment(_, _, _)
    | RegisterMode, SetRegister(_, _, _, _)
    | TallyMode, SetRegister(_, _, _, _)
    | RegisterMode, Increment(_, _, _)
    | TallyMode, Remove(_, _)
    | RegisterMode, Remove(_, _)
    -> Ok(Nil)
    OrSetMode, Increment(_, _, _)
    | OrSetMode, SetRegister(_, _, _, _)
    | TallyMode, AddMember(_, _, _)
    | RegisterMode, AddMember(_, _, _)
    | TallyMode, RemoveMember(_, _, _)
    | RegisterMode, RemoveMember(_, _, _)
    -> Error(ModeMismatch("operation does not match the channel mode"))
  }
}

fn set_error(error: or_map_set_leaf.LeafError) -> KernelError {
  case error {
    or_map_set_leaf.InvalidState(detail) -> InvalidSetState(detail)
    or_map_set_leaf.CounterExhausted(detail) -> CounterExhausted(detail)
  }
}

fn retain_set_clocks(state: OrMapState) -> Result(OrMapState, KernelError) {
  case state.mode {
    TallyMode | RegisterMode -> Ok(state)
    OrSetMode -> {
      use clocks <- result.try(
        or_map_set_leaf.observe_state(state.set_clocks, state.sequenced)
        |> result.map_error(set_error),
      )
      use clocks <- result.try(
        or_map_set_leaf.observe_state(clocks, state.optimistic)
        |> result.map_error(set_error),
      )
      use sequenced <- result.try(
        or_map_set_leaf.retain_counter_floor(
          state.sequenced,
          clocks,
          state.replica_id,
        )
        |> result.map_error(set_error),
      )
      use optimistic <- result.try(
        or_map_set_leaf.retain_counter_floor(
          state.optimistic,
          clocks,
          state.replica_id,
        )
        |> result.map_error(set_error),
      )
      Ok(
        OrMapState(
          ..state,
          sequenced: sequenced,
          optimistic: optimistic,
          set_clocks: clocks,
        ),
      )
    }
  }
}

fn observe_set_operation(
  state: OrMapState,
  operation: OrMapOperation,
) -> Result(OrMapState, KernelError) {
  use _ <- result.try(validate_operation(state.mode, operation))
  case state.mode {
    TallyMode | RegisterMode -> Ok(state)
    OrSetMode -> {
      use clocks <- result.try(
        or_map_set_leaf.observe_delta(
          state.set_clocks,
          operation_delta(operation),
        )
        |> result.map_error(set_error),
      )
      retain_set_clocks(OrMapState(..state, set_clocks: clocks))
    }
  }
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
/// of each operation.
pub fn p2p_merge(
  state: OrMapState,
  other: ORMap,
) -> Result(#(OrMapState, List(OrMapEvent)), KernelError) {
  let before = entries(state)
  use state <- result.try(retain_set_clocks(state))
  case merge_map(state.mode, state.sequenced, other) {
    Error(ModeMismatch(_)) ->
      Error(ModeMismatch("merged value spec does not match the channel mode"))
    Error(error) -> Error(error)
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
      use new_state <- result.try(retain_set_clocks(new_state))
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
    TallyMode | OrSetMode -> clock
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
  operation: OrMapOperation,
) -> Result(#(OrMapState, List(OrMapEvent)), KernelError) {
  let before = entries(state)
  use state <- result.try(observe_set_operation(state, operation))
  let delta = operation_delta(operation)
  use sequenced <- result.try(apply_delta(state.sequenced, delta))
  use optimistic <- result.try(replay_pending(sequenced, state.pending))
  let new_state =
    OrMapState(
      ..state,
      sequenced: sequenced,
      optimistic: optimistic,
      register_clock: observe_operation(state.register_clock, operation),
    )
  use new_state <- result.try(retain_set_clocks(new_state))
  Ok(#(new_state, events_between(before, entries(new_state))))
}

pub fn ack_local(
  state: OrMapState,
  operation: OrMapOperation,
) -> Result(OrMapState, KernelError) {
  do_ack(state, operation, None)
}

pub fn ack_local_with_message_id(
  state: OrMapState,
  operation: OrMapOperation,
  message_id: Int,
) -> Result(OrMapState, KernelError) {
  do_ack(state, operation, Some(message_id))
}

fn do_ack(
  state: OrMapState,
  operation: OrMapOperation,
  expected_message_id: Option(Int),
) -> Result(OrMapState, KernelError) {
  case state.pending {
    [] -> Error(UnexpectedAck("pending queue is empty"))
    [PendingOperation(pending_operation, pending_message_id), ..rest] -> {
      let message_id_matches = case expected_message_id {
        None -> True
        Some(message_id) -> message_id == pending_message_id
      }
      case pending_operation == operation && message_id_matches {
        True -> {
          use state <- result.try(observe_set_operation(state, operation))
          use sequenced <- result.try(apply_delta(
            state.sequenced,
            operation_delta(operation),
          ))
          retain_set_clocks(
            OrMapState(..state, sequenced: sequenced, pending: rest),
          )
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
  operation: OrMapOperation,
  message_id: Int,
) -> Result(#(OrMapState, List(OrMapEvent)), KernelError) {
  case pop_last(state.pending) {
    Error(_) -> Error(UnexpectedRollback("pending queue is empty"))
    Ok(#(PendingOperation(pending_operation, pending_message_id), rest)) ->
      case pending_operation == operation && pending_message_id == message_id {
        False ->
          Error(UnexpectedRollback(
            "expected newest pending op with message id "
            <> int.to_string(pending_message_id)
            <> ", got message id "
            <> int.to_string(message_id),
          ))
        True -> {
          let before = entries(state)
          use _ <- result.try(validate_operation(state.mode, operation))
          use state <- result.try(retain_set_clocks(state))
          let own_tallies = rollback_own_tallies(state.own_tallies, operation)
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

pub fn apply_stashed_operation(
  state: OrMapState,
  operation: OrMapOperation,
) -> Result(#(OrMapState, List(OrMapEvent), OrMapOperation, Int), KernelError) {
  let before = entries(state)
  use state <- result.try(observe_set_operation(state, operation))
  let delta = operation_delta(operation)
  use optimistic <- result.try(apply_delta(state.optimistic, delta))
  let message_id = state.next_pending_message_id
  let new_state =
    OrMapState(
      ..state,
      optimistic: optimistic,
      pending: list.append(state.pending, [
        PendingOperation(operation, message_id),
      ]),
      next_pending_message_id: message_id + 1,
    )
  use new_state <- result.try(retain_set_clocks(new_state))
  Ok(#(
    new_state,
    events_between(before, entries(new_state)),
    operation,
    message_id,
  ))
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
  use parsed <- result.try(case mode {
    OrSetMode ->
      or_map_set_leaf.decode_state(summary_json)
      |> result.map_error(fn(error) { set_decode_error(set_error(error)) })
    TallyMode | RegisterMode -> or_map.from_json(summary_json)
  })
  case mode {
    OrSetMode ->
      from_sequenced(parsed, mode, replica_id)
      |> result.map_error(set_decode_error)
    TallyMode | RegisterMode ->
      from_legacy_summary(parsed, mode, replica_id, spec)
  }
}

fn from_legacy_summary(
  parsed: ORMap,
  mode: OrMapMode,
  replica_id: ReplicaId,
  spec: String,
) -> Result(OrMapState, json.DecodeError) {
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
    set_clocks: or_map_set_leaf.new_clocks(),
    pending: [],
    next_pending_message_id: 0,
  ))
}

pub fn from_sequenced(
  sequenced: ORMap,
  mode: OrMapMode,
  replica_id: ReplicaId,
) -> Result(OrMapState, KernelError) {
  case merge_map(mode, or_map.new(replica_id, mode_to_spec(mode)), sequenced) {
    Error(error) -> Error(error)
    Ok(rebranded) ->
      retain_set_clocks(OrMapState(
        replica_id: replica_id,
        mode: mode,
        sequenced: rebranded,
        optimistic: rebranded,
        own_tallies: dict.new(),
        register_clock: dict.new(),
        set_clocks: or_map_set_leaf.new_clocks(),
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
  operation: OrMapOperation,
) -> Dict(String, #(Int, Int)) {
  case operation {
    Increment(key, amount, _) -> {
      let #(positive, negative) =
        dict.get(own_tallies, key) |> result.unwrap(#(0, 0))
      let next = case amount >= 0 {
        True -> #(positive - amount, negative)
        False -> #(positive, negative - { 0 - amount })
      }
      dict.insert(own_tallies, key, next)
    }
    SetRegister(_, _, _, _)
    | Remove(_, _)
    | AddMember(_, _, _)
    | RemoveMember(_, _, _) -> own_tallies
  }
}

fn operation_delta(operation: OrMapOperation) -> ORMapDelta {
  case operation {
    Increment(_, _, delta) -> delta
    SetRegister(_, _, _, delta) -> delta
    Remove(_, delta) -> delta
    AddMember(_, _, delta) | RemoveMember(_, _, delta) -> delta
  }
}

fn apply_delta(map: ORMap, delta: ORMapDelta) -> Result(ORMap, KernelError) {
  use mode <- result.try(native_mode(map))
  case mode {
    OrSetMode -> {
      use _ <- result.try(
        or_map_set_leaf.validate_state(map) |> result.map_error(set_error),
      )
      use _ <- result.try(
        or_map_set_leaf.decode_delta(
          or_map.delta_to_json(delta) |> json.to_string,
        )
        |> result.map_error(set_error),
      )
      or_map_set_leaf.apply_delta(map, delta) |> result.map_error(set_error)
    }
    TallyMode | RegisterMode -> apply_legacy_delta(map, delta)
  }
}

fn apply_legacy_delta(
  map: ORMap,
  delta: ORMapDelta,
) -> Result(ORMap, KernelError) {
  case or_map.apply_delta(map, delta) {
    Ok(map) -> Ok(map)
    Error(crdt.TypeMismatch(expected, found)) ->
      Error(CorruptDelta("expected " <> expected <> " delta, found " <> found))
  }
}

fn native_mode(map: ORMap) -> Result(OrMapMode, KernelError) {
  use spec <- result.try(
    json.parse(
      or_map.to_json(map) |> json.to_string,
      decode.at(["state", "crdt_spec"], decode.string),
    )
    |> result.replace_error(ModeMismatch("map has no value spec")),
  )
  spec_string_to_mode(spec)
  |> result.replace_error(ModeMismatch("unsupported map value spec: " <> spec))
}

fn merge_map(
  mode: OrMapMode,
  left: ORMap,
  right: ORMap,
) -> Result(ORMap, KernelError) {
  use left_mode <- result.try(native_mode(left))
  use right_mode <- result.try(native_mode(right))
  case left_mode == mode && right_mode == mode {
    False ->
      Error(ModeMismatch("summary value spec does not match requested mode"))
    True ->
      case mode {
        OrSetMode -> {
          use _ <- result.try(
            or_map_set_leaf.validate_state(left) |> result.map_error(set_error),
          )
          use _ <- result.try(
            or_map_set_leaf.validate_state(right) |> result.map_error(set_error),
          )
          or_map_set_leaf.merge(left, right) |> result.map_error(set_error)
        }
        TallyMode | RegisterMode ->
          or_map.merge(left, right)
          |> result.replace_error(ModeMismatch(
            "merged value spec does not match the channel mode",
          ))
      }
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
  pending: List(PendingOperation),
) -> Result(ORMap, KernelError) {
  use mode <- result.try(native_mode(sequenced))
  use _ <- result.try(case mode {
    OrSetMode ->
      or_map_set_leaf.validate_state(sequenced) |> result.map_error(set_error)
    TallyMode | RegisterMode -> Ok(Nil)
  })
  list.try_fold(pending, sequenced, fn(acc, pending) {
    use _ <- result.try(validate_operation(mode, pending.operation))
    apply_delta(acc, operation_delta(pending.operation))
  })
}

/// The visible tally for a key. The result is zero when the map holds no
/// tally there.
fn tally_of(state: OrMapState, key: String) -> Int {
  case get(state, key) {
    Ok(Tally(value)) -> value
    Ok(Register(_)) | Ok(SetMembers(_)) | Error(Nil) -> 0
  }
}

fn map_entries(map: ORMap, mode: OrMapMode) -> List(#(String, OrMapValue)) {
  or_map.keys(map)
  |> list.sort(by: case mode {
    OrSetMode -> canonical_json.compare
    TallyMode | RegisterMode -> string.compare
  })
  |> list.filter_map(fn(key) {
    case or_map.get(map, key) {
      Ok(value) ->
        crdt_to_value(value) |> result.map(fn(value) { #(key, value) })
      Error(_) -> Error(Nil)
    }
  })
}

/// Read a lattice value as a kernel value. The result is `Error(Nil)` for a
/// lattice value that no map mode holds. The value mode of the map keeps
/// such a value out, so this arm reports a broken map instead of a panic.
fn crdt_to_value(value: crdt.Crdt) -> Result(OrMapValue, Nil) {
  case value {
    crdt.CrdtPnCounter(counter) -> Ok(Tally(pn_counter.value(counter)))
    crdt.CrdtLwwRegister(register) -> Ok(Register(lww_register.value(register)))
    crdt.CrdtOrSet(members) ->
      Ok(SetMembers(
        or_set.value(members)
        |> set.to_list
        |> list.sort(canonical_json.compare),
      ))
    crdt.CrdtGCounter(_)
    | crdt.CrdtMvRegister(_)
    | crdt.CrdtGSet(_)
    | crdt.CrdtTwoPSet(_)
    | crdt.CrdtVersionVector(_) -> Error(Nil)
  }
}

fn events_between(
  before: List(#(String, OrMapValue)),
  after: List(#(String, OrMapValue)),
) -> List(OrMapEvent) {
  let compare = case
    list.any(list.append(before, after), fn(entry) {
      case entry.1 {
        SetMembers(_) -> True
        Tally(_) | Register(_) -> False
      }
    })
  {
    True -> canonical_json.compare
    False -> string.compare
  }
  let keys =
    list.append(
      list.map(before, fn(entry) { entry.0 }),
      list.map(after, fn(entry) { entry.0 }),
    )
    |> list.unique
    |> list.sort(by: compare)

  list.filter_map(keys, fn(key) {
    case entry_value(before, key), entry_value(after, key) {
      Error(Nil), Error(Nil) -> Error(Nil)
      Ok(_), Error(Nil) -> Ok(KeyRemoved(key))
      Error(Nil), Ok(Tally(value)) -> Ok(TallyUpdated(key, value, value))
      Error(Nil), Ok(Register(value)) -> Ok(RegisterUpdated(key, value))
      Error(Nil), Ok(SetMembers(members)) -> Ok(SetMembersUpdated(key, members))
      Ok(SetMembers(old)), Ok(SetMembers(new)) ->
        case old == new {
          True -> Error(Nil)
          False -> Ok(SetMembersUpdated(key, new))
        }
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
      Ok(Tally(_)), Ok(Register(_))
      | Ok(Register(_)), Ok(Tally(_))
      | Ok(Tally(_)), Ok(SetMembers(_))
      | Ok(SetMembers(_)), Ok(Tally(_))
      | Ok(Register(_)), Ok(SetMembers(_))
      | Ok(SetMembers(_)), Ok(Register(_))
      -> Error(Nil)
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
  pending: List(PendingOperation),
) -> Result(#(PendingOperation, List(PendingOperation)), Nil) {
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
      expected: "pn_counter, lww_register, or or_set",
      found: spec,
      path: ["state", "crdt_spec"],
    ),
  ])
}

fn set_decode_error(error: KernelError) -> json.DecodeError {
  json.UnableToDecode([
    decode.DecodeError(
      expected: "valid OR-set map state",
      found: string.inspect(error),
      path: ["state"],
    ),
  ])
}
