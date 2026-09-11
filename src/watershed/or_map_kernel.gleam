//// A lattice-backed observed-remove map kernel.
////
//// This kernel holds one `lattice_maps/or_map.ORMap` in one of four value
//// modes. The first mode holds signed tallies, which are PN-counter leaves.
//// The second mode holds string registers, which are LWW-register leaves.
//// The third mode holds observed-remove sets of strings.
//// The fourth mode holds string MV-registers with concurrent alternatives.
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
import lattice_core/version_vector
import lattice_counters/pn_counter.{type PNCounter}
import lattice_maps/crdt
import lattice_maps/or_map.{type ORMap, type ORMapDelta}
import lattice_registers/lww_register
import lattice_registers/mv_register.{type MVRegister}
import lattice_sets/or_set
import watershed/canonical_json
import watershed/mv_register_kernel
import watershed/or_map_set_leaf

pub type OrMapMode {
  TallyMode
  RegisterMode
  OrSetMode
  MvRegisterMode
}

pub type OrMapValue {
  Tally(Int)
  Register(String)
  SetMembers(List(String))
  MvRegister(List(String))
}

pub type OrMapState {
  OrMapState(
    replica_id: ReplicaId,
    mode: OrMapMode,
    sequenced: ORMap,
    optimistic: ORMap,
    /// Retain issued key tags across rollback. Use only to author writes,
    /// never for reads, removes, or summaries.
    authored: ORMap,
    own_tallies: Dict(String, #(Int, Int)),
    /// Retain issued tags across rollback and key removal.
    authored_mv_registers: Dict(String, MVRegister(String)),
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
  SetMvRegister(key: String, value: String, delta: ORMapDelta)
  Remove(key: String, delta: ORMapDelta)
  AddMember(key: String, member: String, delta: ORMapDelta)
  RemoveMember(key: String, member: String, delta: ORMapDelta)
}

pub type OrMapEvent {
  TallyUpdated(key: String, applied: Int, new_value: Int)
  RegisterUpdated(key: String, value: String)
  SetMembersUpdated(key: String, members: List(String))
  MvRegisterUpdated(key: String, values: List(String))
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
    MvRegisterMode -> crdt.MvRegisterSpec
  }
}

pub fn spec_string_to_mode(spec: String) -> Result(OrMapMode, Nil) {
  case spec {
    "pn_counter" -> Ok(TallyMode)
    "lww_register" -> Ok(RegisterMode)
    "or_set" -> Ok(OrSetMode)
    "mv_register" -> Ok(MvRegisterMode)
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
    authored: empty,
    own_tallies: dict.new(),
    authored_mv_registers: dict.new(),
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
    RegisterMode | OrSetMode | MvRegisterMode ->
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
      use #(authored, delta) <- result.try(update_with_delta(
        state,
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
          authored: authored,
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
    TallyMode | OrSetMode | MvRegisterMode ->
      Error(ModeMismatch("set_register requires RegisterMode"))
    RegisterMode -> {
      let before = entries(state)
      let timestamp = stamp(state.register_clock, key, timestamp)
      let register = lww_register.new(value, timestamp, state.replica_id)
      use #(authored, delta) <- result.try(update_with_delta(
        state,
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
          authored: authored,
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
    | SetMvRegister(_, _, _)
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
    TallyMode | RegisterMode | MvRegisterMode -> remove_legacy(state, key)
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
    RegisterMode | OrSetMode | MvRegisterMode ->
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
      use #(authored, delta) <- result.try(update_with_delta(
        state,
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
          authored: authored,
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
    TallyMode | OrSetMode | MvRegisterMode ->
      Error(ModeMismatch("set_register requires RegisterMode"))
    RegisterMode -> {
      let before = entries(state)
      let timestamp = stamp(state.register_clock, key, timestamp)
      let register = lww_register.new(value, timestamp, state.replica_id)
      use #(authored, delta) <- result.try(update_with_delta(
        state,
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
          authored: authored,
          register_clock: observe(state.register_clock, key, timestamp),
        )
      Ok(#(new_state, events_between(before, entries(new_state)), operation))
    }
  }
}

pub fn set_mv_register(
  state: OrMapState,
  key: String,
  value: String,
) -> Result(#(OrMapState, List(OrMapEvent), OrMapOperation, Int), KernelError) {
  use #(authored_map, delta, authored) <- result.try(write_mv_register(
    state,
    key,
    value,
  ))
  use optimistic <- result.try(apply_delta(state.optimistic, delta))
  let message_id = state.next_pending_message_id
  let operation = SetMvRegister(key, value, delta)
  let next =
    OrMapState(
      ..state,
      optimistic: optimistic,
      authored: authored_map,
      authored_mv_registers: dict.insert(
        state.authored_mv_registers,
        key,
        authored,
      ),
      pending: list.append(state.pending, [
        PendingOperation(operation, message_id),
      ]),
      next_pending_message_id: message_id + 1,
    )
  Ok(#(
    next,
    events_between(entries(state), entries(next)),
    operation,
    message_id,
  ))
}

/// The ack-free p2p form of `set_mv_register`.
pub fn p2p_set_mv_register(
  state: OrMapState,
  key: String,
  value: String,
) -> Result(#(OrMapState, List(OrMapEvent), OrMapOperation), KernelError) {
  use #(authored_map, delta, authored) <- result.try(write_mv_register(
    state,
    key,
    value,
  ))
  use optimistic <- result.try(apply_delta(state.optimistic, delta))
  use sequenced <- result.try(apply_delta(state.sequenced, delta))
  let next =
    OrMapState(
      ..state,
      sequenced: sequenced,
      optimistic: optimistic,
      authored: authored_map,
      authored_mv_registers: dict.insert(
        state.authored_mv_registers,
        key,
        authored,
      ),
    )
  Ok(#(
    next,
    events_between(entries(state), entries(next)),
    SetMvRegister(key, value, delta),
  ))
}

fn write_mv_register(
  state: OrMapState,
  key: String,
  value: String,
) -> Result(#(ORMap, ORMapDelta, MVRegister(String)), KernelError) {
  case state.mode {
    TallyMode | RegisterMode | OrSetMode ->
      Error(ModeMismatch("set_mv_register requires MvRegisterMode"))
    MvRegisterMode -> {
      let authored =
        dict.get(state.authored_mv_registers, key)
        |> result.unwrap(mv_register.new(state.replica_id))
      let assert crdt.CrdtMvRegister(visible) =
        or_map.get(state.optimistic, key)
        |> result.unwrap(crdt.CrdtMvRegister(mv_register.new(state.replica_id)))
      // Merge with the local register first to retain the author identity.
      let #(written, _) =
        mv_register.merge(authored, visible)
        |> mv_register.set_with_delta(value)
      use #(updated, delta) <- result.try(update_with_delta(
        state,
        key,
        crdt.CrdtMvRegister(written),
      ))
      Ok(#(updated, delta, written))
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
    TallyMode | RegisterMode | MvRegisterMode -> p2p_remove_legacy(state, key)
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
    TallyMode | RegisterMode | MvRegisterMode ->
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
    | MvRegisterMode, SetMvRegister(_, _, _)
    | TallyMode, Remove(_, _)
    | RegisterMode, Remove(_, _)
    | MvRegisterMode, Remove(_, _)
    -> validated_key_delta(operation) |> result.replace(Nil)
    OrSetMode, Increment(_, _, _)
    | OrSetMode, SetRegister(_, _, _, _)
    | OrSetMode, SetMvRegister(_, _, _)
    | TallyMode, SetRegister(_, _, _, _)
    | TallyMode, SetMvRegister(_, _, _)
    | RegisterMode, Increment(_, _, _)
    | RegisterMode, SetMvRegister(_, _, _)
    | MvRegisterMode, Increment(_, _, _)
    | MvRegisterMode, SetRegister(_, _, _, _)
    | TallyMode, AddMember(_, _, _)
    | RegisterMode, AddMember(_, _, _)
    | MvRegisterMode, AddMember(_, _, _)
    | TallyMode, RemoveMember(_, _, _)
    | RegisterMode, RemoveMember(_, _, _)
    | MvRegisterMode, RemoveMember(_, _, _)
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
    TallyMode | RegisterMode | MvRegisterMode -> Ok(state)
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
    TallyMode | RegisterMode | MvRegisterMode -> Ok(state)
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
      use authored <- result.try(observe_mv_registers(
        state.authored_mv_registers,
        state.mode,
        other,
        state.replica_id,
      ))
      use optimistic <- result.try(replay_pending(sequenced, state.pending))
      use authored <- result.try(observe_mv_registers(
        authored,
        state.mode,
        optimistic,
        state.replica_id,
      ))
      let new_state =
        OrMapState(
          ..state,
          sequenced: sequenced,
          optimistic: optimistic,
          authored_mv_registers: authored,
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
    TallyMode | OrSetMode | MvRegisterMode -> clock
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
  use _ <- result.try(validate_state_operation(state, operation))
  use state <- result.try(observe_set_operation(state, operation))
  let delta = operation_delta(operation)
  use sequenced <- result.try(apply_delta(state.sequenced, delta))
  use optimistic <- result.try(replay_pending(sequenced, state.pending))
  use authored <- result.try(observe_mv_registers(
    state.authored_mv_registers,
    state.mode,
    optimistic,
    state.replica_id,
  ))
  let new_state =
    OrMapState(
      ..state,
      sequenced: sequenced,
      optimistic: optimistic,
      authored_mv_registers: authored,
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
          use _ <- result.try(validate_state_operation(state, operation))
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
          use _ <- result.try(validate_state_operation(state, operation))
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
  use _ <- result.try(validate_state_operation(state, operation))
  use optimistic <- result.try(apply_delta(state.optimistic, delta))
  use authored_map <- result.try(apply_delta(state.authored, delta))
  use authored <- result.try(observe_mv_registers(
    state.authored_mv_registers,
    state.mode,
    optimistic,
    state.replica_id,
  ))
  let message_id = state.next_pending_message_id
  let new_state =
    OrMapState(
      ..state,
      optimistic: optimistic,
      authored: authored_map,
      authored_mv_registers: authored,
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
  use authored <- result.try(case mode {
    MvRegisterMode -> decode_mv_registers(summary_json, replica_id)
    TallyMode | RegisterMode | OrSetMode -> Ok(dict.new())
  })
  use parsed <- result.try(case mode {
    OrSetMode ->
      or_map_set_leaf.decode_state(summary_json)
      |> result.map_error(fn(error) { set_decode_error(set_error(error)) })
    TallyMode | RegisterMode | MvRegisterMode -> or_map.from_json(summary_json)
  })
  case mode {
    OrSetMode ->
      from_sequenced(parsed, mode, replica_id)
      |> result.map_error(set_decode_error)
    TallyMode | RegisterMode | MvRegisterMode ->
      from_legacy_summary(parsed, mode, replica_id, spec, authored)
  }
}

fn from_legacy_summary(
  parsed: ORMap,
  mode: OrMapMode,
  replica_id: ReplicaId,
  spec: String,
  authored: Dict(String, MVRegister(String)),
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
    authored: sequenced,
    own_tallies: dict.new(),
    authored_mv_registers: authored,
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
    Ok(rebranded) -> {
      use authored <- result.try(observe_mv_registers(
        dict.new(),
        mode,
        rebranded,
        replica_id,
      ))
      retain_set_clocks(OrMapState(
        replica_id: replica_id,
        mode: mode,
        sequenced: rebranded,
        optimistic: rebranded,
        authored: rebranded,
        own_tallies: dict.new(),
        authored_mv_registers: authored,
        register_clock: dict.new(),
        set_clocks: or_map_set_leaf.new_clocks(),
        pending: [],
        next_pending_message_id: 0,
      ))
    }
  }
}

pub fn check_cache_coherence(state: OrMapState) -> Result(Nil, String) {
  case replay_pending(state.sequenced, state.pending) {
    Error(_) -> Error("a pending operation has an invalid delta")
    Ok(recomputed) ->
      case recomputed == state.optimistic {
        True -> Ok(Nil)
        False -> Error("optimistic cache diverged from sequenced + pending")
      }
  }
}

fn decode_mv_registers(
  source: String,
  replica_id: ReplicaId,
) -> Result(Dict(String, MVRegister(String)), json.DecodeError) {
  let decoder =
    decode.at(
      ["state", "values"],
      decode.list({
        use key <- decode.field("key", decode.string)
        use encoded <- decode.field("crdt", decode.string)
        decode.success(#(key, encoded))
      }),
    )
  use leaves <- result.try(json.parse(source, decoder))
  list.try_fold(leaves, dict.new(), fn(registers, leaf) {
    use register <- result.try(mv_register_kernel.decode_crdt(leaf.1))
    Ok(dict.insert(
      registers,
      leaf.0,
      mv_register.merge(mv_register.new(replica_id), register),
    ))
  })
}

fn observe_mv_registers(
  authored: Dict(String, MVRegister(String)),
  mode: OrMapMode,
  map: ORMap,
  replica_id: ReplicaId,
) -> Result(Dict(String, MVRegister(String)), KernelError) {
  case mode {
    TallyMode | RegisterMode | OrSetMode -> Ok(authored)
    MvRegisterMode -> {
      // The JSON codec includes removed leaves that `or_map.keys` omits.
      use registers <- result.try(
        decode_mv_registers(or_map.to_json(map) |> json.to_string, replica_id)
        |> result.map_error(fn(error) { CorruptDelta(string.inspect(error)) }),
      )
      Ok(dict.combine(authored, registers, mv_register.merge))
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
    | SetMvRegister(_, _, _)
    | Remove(_, _)
    | AddMember(_, _, _)
    | RemoveMember(_, _, _) -> own_tallies
  }
}

fn operation_delta(operation: OrMapOperation) -> ORMapDelta {
  case operation {
    Increment(_, _, delta) -> delta
    SetRegister(_, _, _, delta) -> delta
    SetMvRegister(_, _, delta) -> delta
    Remove(_, delta) -> delta
    AddMember(_, _, delta) | RemoveMember(_, _, delta) -> delta
  }
}

type KeyDelta {
  KeyDelta(
    author: String,
    counter: Int,
    entries: Dict(String, List(#(String, Int))),
    tombstones: List(#(String, Int)),
    pruned: version_vector.VersionVector,
  )
}

fn tag_decoder() -> decode.Decoder(#(String, Int)) {
  use author <- decode.field("r", decode.string)
  use counter <- decode.field("c", decode.int)
  decode.success(#(author, counter))
}

fn key_delta_decoder() -> decode.Decoder(KeyDelta) {
  decode.at(["state"], {
    use author <- decode.field("replica_id", decode.string)
    use counter <- decode.field("counter", decode.int)
    use entries <- decode.field(
      "entries",
      decode.dict(decode.string, decode.list(tag_decoder())),
    )
    use tombstones <- decode.field("tombstones", decode.list(tag_decoder()))
    use pruned <- decode.field("pruned", version_vector.decoder())
    decode.success(KeyDelta(author, counter, entries, tombstones, pruned))
  })
}

/// Bind the operation intent to one sparse delta. Call this for decoded wire
/// operations and direct kernel input. Validation does not depend on delivery
/// order, so duplicate delivery and stash replay remain valid.
pub fn validate_operation_intent(
  operation: OrMapOperation,
) -> Result(Nil, KernelError) {
  use spec <- result.try(
    json.parse(
      operation_delta(operation) |> or_map.delta_to_json |> json.to_string,
      decode.at(["state", "crdt_spec"], decode.string),
    )
    |> result.map_error(fn(error) { CorruptDelta(string.inspect(error)) }),
  )
  use mode <- result.try(
    spec_string_to_mode(spec)
    |> result.replace_error(ModeMismatch("unsupported delta value spec")),
  )
  validate_operation(mode, operation)
}

fn validated_key_delta(
  operation: OrMapOperation,
) -> Result(KeyDelta, KernelError) {
  let metadata =
    decode.at(["state"], {
      use author <- decode.field("replica_id", decode.string)
      use spec <- decode.field("crdt_spec", decode.string)
      use keys <- decode.field("key_set_delta", decode.string)
      use leaves <- decode.field(
        "value_deltas",
        decode.list({
          use key <- decode.field("key", decode.string)
          use leaf <- decode.field("crdt", decode.string)
          decode.success(#(key, leaf))
        }),
      )
      use bounds <- decode.field(
        "remove_bounds_delta",
        decode.dict(decode.string, version_vector.decoder()),
      )
      decode.success(#(author, spec, keys, leaves, bounds))
    })
  use #(author, spec, encoded_keys, leaves, bounds) <- result.try(
    json.parse(
      operation_delta(operation) |> or_map.delta_to_json |> json.to_string,
      metadata,
    )
    |> result.map_error(fn(error) { CorruptDelta(string.inspect(error)) }),
  )
  use keys <- result.try(
    json.parse(encoded_keys, key_delta_decoder())
    |> result.map_error(fn(error) { CorruptDelta(string.inspect(error)) }),
  )
  let valid =
    keys.author == author
    && keys.counter >= 0
    && version_vector.is_empty(keys.pruned)
    && result.is_ok(spec_string_to_mode(spec))
    && case
      operation,
      leaves,
      dict.to_list(keys.entries),
      dict.to_list(bounds)
    {
      Remove(_, _), [], [], [] -> keys.tombstones == []
      Remove(key, _), [], [], [#(removed_key, bound)] -> {
        let expected_bound =
          list.fold(keys.tombstones, version_vector.new(), fn(bound, tag) {
            version_vector.set_max(bound, replica_id.new(tag.0), tag.1)
          })
        key == removed_key
        && keys.tombstones != []
        && list.all(keys.tombstones, fn(tag) {
          tag.1 > 0 && tag.1 <= keys.counter
        })
        && bound == expected_bound
      }
      _, [#(key, leaf)], [#(added_key, [#(tag_author, counter)])], [] ->
        key == added_key
        && tag_author == author
        && counter > 0
        && counter == keys.counter
        && keys.tombstones == []
        && write_matches(operation, spec, author, key, leaf)
      _, _, _, _ -> False
    }
  case valid {
    True -> Ok(keys)
    False -> Error(CorruptDelta("operation intent does not match its delta"))
  }
}

fn write_matches(
  operation: OrMapOperation,
  spec: String,
  author: String,
  key: String,
  leaf: String,
) -> Bool {
  case operation {
    Increment(intent_key, amount, _) -> {
      let half = {
        use self <- decode.field("self_id", decode.string)
        use counts <- decode.field(
          "counts",
          decode.dict(decode.string, decode.int),
        )
        decode.success(#(self, counts))
      }
      let decoder =
        decode.at(["state"], {
          use positive <- decode.field("positive", half)
          use negative <- decode.field("negative", half)
          decode.success(
            positive.0 == author
            && negative.0 == author
            && list.all(
              list.append(dict.to_list(positive.1), dict.to_list(negative.1)),
              fn(count) { count.0 == author && count.1 >= 0 },
            )
            // The leaf holds cumulative own counts, not this operation's amount.
            // A missing earlier operation or a duplicate prevents an exact diff.
            && case amount >= 0 {
              True -> result.unwrap(dict.get(positive.1, author), 0) >= amount
              False ->
                result.unwrap(dict.get(negative.1, author), 0) >= 0 - amount
            },
          )
        })
      spec == "pn_counter"
      && key == intent_key
      && json.parse(leaf, decoder) == Ok(True)
    }
    SetRegister(intent_key, value, timestamp, _) -> {
      let decoder =
        decode.at(["state"], {
          use actual_author <- decode.field("replica_id", decode.string)
          use actual_value <- decode.field("value", decode.string)
          use actual_timestamp <- decode.field("timestamp", decode.int)
          decode.success(
            actual_author == author
            && actual_value == value
            && actual_timestamp == timestamp,
          )
        })
      spec == "lww_register"
      && key == intent_key
      && json.parse(leaf, decoder) == Ok(True)
    }
    SetMvRegister(intent_key, value, _) -> {
      let decoder =
        decode.at(["state"], {
          use actual_author <- decode.field("replica_id", decode.string)
          use entries <- decode.field(
            "entries",
            decode.list({
              use tag <- decode.field("tag", tag_decoder())
              use value <- decode.field("value", decode.string)
              decode.success(#(tag, value))
            }),
          )
          use clock <- decode.field(
            "vclock",
            decode.dict(decode.string, decode.int),
          )
          decode.success(case entries {
            [#(#(tag_author, counter), actual_value)] ->
              actual_author == author
              && tag_author == author
              && actual_value == value
              && dict.get(clock, author) == Ok(counter)
            _ -> False
          })
        })
      spec == "mv_register"
      && key == intent_key
      && result.is_ok(mv_register_kernel.decode_crdt(leaf))
      && json.parse(leaf, decoder) == Ok(True)
    }
    Remove(_, _) | AddMember(_, _, _) | RemoveMember(_, _, _) -> False
  }
}

fn apply_operation(
  map: ORMap,
  operation: OrMapOperation,
) -> Result(ORMap, KernelError) {
  use mode <- result.try(native_mode(map))
  use _ <- result.try(validate_operation(mode, operation))
  use _ <- result.try(case mode {
    OrSetMode -> Ok(Nil)
    TallyMode | RegisterMode | MvRegisterMode -> {
      use keys <- result.try(validated_key_delta(operation))
      validate_key_target(map, operation, keys)
    }
  })
  apply_delta(map, operation_delta(operation))
}

fn validate_state_operation(
  state: OrMapState,
  operation: OrMapOperation,
) -> Result(Nil, KernelError) {
  use _ <- result.try(validate_operation(state.mode, operation))
  case state.mode {
    OrSetMode -> Ok(Nil)
    TallyMode | RegisterMode | MvRegisterMode -> {
      use keys <- result.try(validated_key_delta(operation))
      list.try_fold(
        [state.sequenced, state.optimistic, state.authored],
        Nil,
        fn(_, map) { validate_key_target(map, operation, keys) },
      )
    }
  }
}

fn validate_key_target(
  map: ORMap,
  operation: OrMapOperation,
  keys: KeyDelta,
) -> Result(Nil, KernelError) {
  case operation {
    Remove(key, _) -> {
      // Tombstones have no key labels. Reject a claim that retires a tag
      // known to belong to another key, without requiring the removed add
      // to have arrived before its removal.
      use encoded <- result.try(
        json.parse(
          or_map.to_json(map) |> json.to_string,
          decode.at(["state", "key_set"], decode.string),
        )
        |> result.map_error(fn(error) { CorruptDelta(string.inspect(error)) }),
      )
      use current <- result.try(
        json.parse(encoded, key_delta_decoder())
        |> result.map_error(fn(error) { CorruptDelta(string.inspect(error)) }),
      )
      case
        list.all(dict.to_list(current.entries), fn(entry) {
          entry.0 == key
          || list.all(entry.1, fn(tag) { !list.contains(keys.tombstones, tag) })
        })
      {
        True -> Ok(Nil)
        False -> Error(CorruptDelta("removal targets a different key"))
      }
    }
    Increment(_, _, _)
    | SetRegister(_, _, _, _)
    | SetMvRegister(_, _, _)
    | AddMember(_, _, _)
    | RemoveMember(_, _, _) -> Ok(Nil)
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
    TallyMode | RegisterMode | MvRegisterMode -> apply_legacy_delta(map, delta)
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
        TallyMode | RegisterMode | MvRegisterMode ->
          or_map.merge(left, right)
          |> result.replace_error(ModeMismatch(
            "merged value spec does not match the channel mode",
          ))
      }
  }
}

/// Keep the key counter above all issued and observed tags. The authored map
/// can contain rolled-back values, so only its sparse delta updates the view.
fn update_with_delta(
  state: OrMapState,
  key: String,
  value: crdt.Crdt,
) -> Result(#(ORMap, ORMapDelta), KernelError) {
  use map <- result.try(
    or_map.merge(state.authored, state.optimistic)
    |> result.replace_error(ModeMismatch("authored map has a different mode")),
  )
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
    TallyMode | RegisterMode | MvRegisterMode -> Ok(Nil)
  })
  list.try_fold(pending, sequenced, fn(acc, pending) {
    apply_operation(acc, pending.operation)
  })
}

/// The visible tally for a key. The result is zero when the map holds no
/// tally there.
fn tally_of(state: OrMapState, key: String) -> Int {
  case get(state, key) {
    Ok(Tally(value)) -> value
    Ok(Register(_)) | Ok(SetMembers(_)) | Ok(MvRegister(_)) | Error(Nil) -> 0
  }
}

fn map_entries(map: ORMap, mode: OrMapMode) -> List(#(String, OrMapValue)) {
  or_map.keys(map)
  |> list.sort(by: case mode {
    OrSetMode -> canonical_json.compare
    TallyMode | RegisterMode | MvRegisterMode -> string.compare
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
    crdt.CrdtMvRegister(register) ->
      Ok(MvRegister(mv_register.value(register) |> list.sort(string.compare)))
    crdt.CrdtGCounter(_)
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
        Tally(_) | Register(_) | MvRegister(_) -> False
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
      Error(Nil), Ok(MvRegister(values)) -> Ok(MvRegisterUpdated(key, values))
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
      Ok(MvRegister(old)), Ok(MvRegister(new)) ->
        case old == new {
          True -> Error(Nil)
          False -> Ok(MvRegisterUpdated(key, new))
        }
      // One map holds one value mode, so a key never changes mode. The arm
      // reports no event, the same as an unchanged key.
      Ok(Tally(_)), Ok(Register(_))
      | Ok(Register(_)), Ok(Tally(_))
      | Ok(Tally(_)), Ok(SetMembers(_))
      | Ok(SetMembers(_)), Ok(Tally(_))
      | Ok(Register(_)), Ok(SetMembers(_))
      | Ok(SetMembers(_)), Ok(Register(_))
      | Ok(MvRegister(_)), Ok(Tally(_))
      | Ok(MvRegister(_)), Ok(Register(_))
      | Ok(Tally(_)), Ok(MvRegister(_))
      | Ok(Register(_)), Ok(MvRegister(_))
      | Ok(MvRegister(_)), Ok(SetMembers(_))
      | Ok(SetMembers(_)), Ok(MvRegister(_))
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
      expected: "pn_counter, lww_register, or_set, or mv_register",
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
