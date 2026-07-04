//// The closed sum of channel kernels the runtime can host, dispatched in
//// one module: parallel sums for state, ops, events, and snapshots, plus
//// one dispatch function per operation `runtime_core` needs.
////
//// The runtime routes everything through these sums instead of naming a
//// kernel directly, so onboarding a kernel is: add a variant to each sum
//// here, then follow the compiler to every dispatch site. The compiler
//// can't point at the non-type sites. Adding a kernel checklist:
//// - `wire/ops`: add the channel-op wire codec.
//// - `channel`: extend summary payload encode/decode
////   (`encode_snapshot`/`snapshot_decoder`).
//// - `runtime` and `runtime_js`: add actor/runtime verbs for edits + reads.
//// - fuzz model: extend generators/oracles for the new channel behavior.
////
//// Kernels stay pure and runtime-unaware; this module only wraps them.

import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}

import lattice_core/replica_id
import lattice_maps/or_map.{type ORMap}
import lattice_sets/or_set.{type ORSet}
import watershed/claims_kernel
import watershed/counter_kernel
import watershed/handle
import watershed/map_kernel
import watershed/or_map_kernel
import watershed/or_set_kernel
import watershed/register_collection_kernel
import watershed/wire

/// The kinds of channel a document can host. Maps to/from the wire's
/// `channelType` strings via `type_to_string`/`type_from_string`.
pub type ChannelType {
  MapChannel
  CounterChannel
  OrMapChannel
  OrSetChannel
  RegisterCollectionChannel
  ClaimsChannel
}

/// Creation parameters for a channel. Most channel types need only their
/// channel type; OR-map also needs its value mode.
pub type ChannelInit {
  InitMap
  InitCounter
  InitOrMap(mode: or_map_kernel.OrMapMode)
  InitOrSet
  InitRegisterCollection
  InitClaims
}

pub fn type_to_string(channel_type: ChannelType) -> String {
  case channel_type {
    MapChannel -> wire.channel_type_map
    CounterChannel -> wire.channel_type_counter
    OrMapChannel -> wire.channel_type_or_map
    OrSetChannel -> wire.channel_type_or_set
    RegisterCollectionChannel -> wire.channel_type_register_collection
    ClaimsChannel -> wire.channel_type_claims
  }
}

pub fn type_from_string(raw: String) -> Result(ChannelType, Nil) {
  case raw {
    _ if raw == wire.channel_type_map -> Ok(MapChannel)
    _ if raw == wire.channel_type_counter -> Ok(CounterChannel)
    _ if raw == wire.channel_type_or_map -> Ok(OrMapChannel)
    _ if raw == wire.channel_type_or_set -> Ok(OrSetChannel)
    _ if raw == wire.channel_type_register_collection ->
      Ok(RegisterCollectionChannel)
    _ if raw == wire.channel_type_claims -> Ok(ClaimsChannel)
    _ -> Error(Nil)
  }
}

pub fn init_type(init: ChannelInit) -> ChannelType {
  case init {
    InitMap -> MapChannel
    InitCounter -> CounterChannel
    InitOrMap(_) -> OrMapChannel
    InitOrSet -> OrSetChannel
    InitRegisterCollection -> RegisterCollectionChannel
    InitClaims -> ClaimsChannel
  }
}

/// One channel's kernel state.
pub type ChannelState {
  MapState(map_kernel.MapState)
  CounterState(counter_kernel.CounterState)
  OrMapState(or_map_kernel.OrMapState)
  OrSetState(or_set_kernel.OrSetState)
  RegisterCollectionState(register_collection_kernel.RegisterState)
  ClaimsState(claims_kernel.ClaimsState)
}

/// A kernel op as it travels through the runtime (in-flight queue, ack
/// matching) and, via `wire/ops`, over the wire.
pub type ChannelOp {
  MapOp(map_kernel.MapOp)
  CounterOp(counter_kernel.CounterOp)
  OrMapOp(or_map_kernel.OrMapOp)
  OrSetOp(or_set_kernel.OrSetOp)
  RegisterCollectionOp(register_collection_kernel.WriteOp)
  ClaimsOp(claims_kernel.ClaimOp)
}

/// A kernel event, address-tagged by the runtime before fan-out.
pub type ChannelEvent {
  MapEvent(map_kernel.MapEvent)
  CounterEvent(counter_kernel.CounterEvent)
  OrMapEvent(or_map_kernel.OrMapEvent)
  OrSetEvent(or_set_kernel.OrSetEvent)
  RegisterCollectionEvent(register_collection_kernel.RegisterEvent)
  ClaimsEvent(claims_kernel.ClaimEvent)
}

/// A channel's state as the persisted formats carry it: the attach op's
/// `snapshot` payload and the summary blob's per-channel `data` payload.
pub type Snapshot {
  MapSnapshot(entries: List(#(String, Json)))
  CounterSnapshot(value: Int)
  OrMapSnapshot(mode: or_map_kernel.OrMapMode, state: ORMap)
  OrSetSnapshot(state: ORSet(String))
  RegisterCollectionSnapshot(
    registers: List(#(String, register_collection_kernel.Register)),
  )
  ClaimsSnapshot(entries: List(#(String, Json, Int)))
}

pub type Resolution {
  ClaimResolved(key: String, outcome: claims_kernel.ClaimOutcome)
}

/// Per-kernel *local* metadata an in-flight op carries alongside the wire
/// op (never serialized). Map ops carry none; counters validate the local
/// message id Fluid pairs with each pending increment.
pub type LocalOpMeta {
  NoMeta
  CounterMeta(message_id: Int)
  OrMapMeta(message_id: Int)
  OrSetMeta(message_id: Int)
}

/// Sequencer-assigned metadata for a sequenced op. Map and counter ignore
/// it; kernels that persist sequence numbers consume `seq`.
/// Threaded from day one so adding such a kernel is additive.
pub type SequencedMeta {
  SequencedMeta(seq: Int, last_seen_sn: Int)
}

pub type ChannelError {
  /// An ack did not line up with the kernel's pending queue. Fatal: the
  /// runtime routed an ack the kernel never submitted (or out of order).
  UnexpectedAck(detail: String)
  /// The runtime dispatched an op to a channel of a different kernel type.
  /// Fatal: ops are decoded against the registry's type for their address,
  /// so a mismatch here is a routing bug, not bad input.
  WrongChannelType(detail: String)
  CorruptRemoteOp(detail: String)
}

pub fn channel_type(state: ChannelState) -> ChannelType {
  case state {
    MapState(_) -> MapChannel
    CounterState(_) -> CounterChannel
    OrMapState(_) -> OrMapChannel
    OrSetState(_) -> OrSetChannel
    RegisterCollectionState(_) -> RegisterCollectionChannel
    ClaimsState(_) -> ClaimsChannel
  }
}

pub fn snapshot_type(snapshot: Snapshot) -> ChannelType {
  case snapshot {
    MapSnapshot(_) -> MapChannel
    CounterSnapshot(_) -> CounterChannel
    OrMapSnapshot(_, _) -> OrMapChannel
    OrSetSnapshot(_) -> OrSetChannel
    RegisterCollectionSnapshot(_) -> RegisterCollectionChannel
    ClaimsSnapshot(_) -> ClaimsChannel
  }
}

/// Build an empty channel for a client identity. Map/counter ignore
/// `replica`; replica-identified kernels use it for their local CRDT author.
/// Reconnect keeps existing channel states under their original identities,
/// while summary/attach loads call `from_snapshot` with the joining client's
/// current id so future deltas are authored by the loader.
pub fn new(init: ChannelInit, replica replica: String) -> ChannelState {
  case init {
    InitMap -> MapState(map_kernel.new())
    InitCounter -> CounterState(counter_kernel.new())
    InitOrMap(mode) ->
      OrMapState(or_map_kernel.new(replica_id.new(replica), mode))
    InitOrSet -> OrSetState(or_set_kernel.new(replica_id.new(replica)))
    InitRegisterCollection ->
      RegisterCollectionState(register_collection_kernel.new())
    InitClaims -> ClaimsState(claims_kernel.new())
  }
}

/// Rebuild a channel from a persisted snapshot, `from_sequenced` semantics:
/// the snapshot's contents become confirmed state with nothing pending.
pub fn from_snapshot(
  snapshot: Snapshot,
  replica replica: String,
) -> ChannelState {
  case snapshot {
    MapSnapshot(entries) -> MapState(map_kernel.from_sequenced(entries))
    CounterSnapshot(value) -> CounterState(counter_kernel.from_summary(value))
    OrMapSnapshot(mode, state) -> {
      let assert Ok(kernel) =
        or_map_kernel.from_sequenced(state, mode, replica_id.new(replica))
      OrMapState(kernel)
    }
    OrSetSnapshot(state) ->
      OrSetState(or_set_kernel.from_sequenced(state, replica_id.new(replica)))
    RegisterCollectionSnapshot(registers) ->
      RegisterCollectionState(register_collection_kernel.from_summary(registers))
    ClaimsSnapshot(entries) -> ClaimsState(claims_kernel.from_summary(entries))
  }
}

/// The confirmed (sequenced-only) state, as a summary captures it.
pub fn snapshot(state: ChannelState) -> Snapshot {
  case state {
    MapState(kernel) -> MapSnapshot(map_kernel.sequenced_entries(kernel))
    CounterState(kernel) -> CounterSnapshot(counter_sequenced_value(kernel))
    OrMapState(kernel) -> OrMapSnapshot(kernel.mode, kernel.sequenced)
    OrSetState(kernel) -> OrSetSnapshot(kernel.sequenced)
    RegisterCollectionState(kernel) ->
      RegisterCollectionSnapshot(register_collection_kernel.summary_registers(
        kernel,
      ))
    ClaimsState(kernel) -> ClaimsSnapshot(claims_kernel.summary_entries(kernel))
  }
}

/// The counter kernel's value is optimistic (pending increments applied);
/// back the un-acked amounts out for the sequenced-only view.
fn counter_sequenced_value(kernel: counter_kernel.CounterState) -> Int {
  list.fold(kernel.pending, kernel.value, fn(value, pending) {
    value - pending.increment_amount
  })
}

/// The current optimistic view, as an attach op captures it. A detached
/// channel's local edits are all pending, so unlike `snapshot` this must
/// include them.
pub fn attach_snapshot(state: ChannelState) -> Snapshot {
  case state {
    MapState(kernel) -> MapSnapshot(map_kernel.entries(kernel))
    CounterState(kernel) -> CounterSnapshot(kernel.value)
    OrMapState(kernel) -> OrMapSnapshot(kernel.mode, kernel.optimistic)
    OrSetState(kernel) -> OrSetSnapshot(kernel.optimistic)
    RegisterCollectionState(kernel) ->
      RegisterCollectionSnapshot(register_collection_kernel.summary_registers(
        kernel,
      ))
    ClaimsState(kernel) -> ClaimsSnapshot(claims_kernel.summary_entries(kernel))
  }
}

pub fn attach_state(
  state: ChannelState,
  replica replica: String,
) -> ChannelState {
  case state {
    OrMapState(kernel) -> OrMapState(or_map_kernel.promote_attach(kernel))
    OrSetState(kernel) -> OrSetState(or_set_kernel.promote_attach(kernel))
    RegisterCollectionState(_) ->
      from_snapshot(attach_snapshot(state), replica:)
    _ -> from_snapshot(attach_snapshot(state), replica: replica)
  }
}

/// Apply a sequenced op from another client.
pub fn apply_remote(
  state: ChannelState,
  op: ChannelOp,
  meta: SequencedMeta,
) -> Result(#(ChannelState, List(ChannelEvent)), ChannelError) {
  case state, op {
    MapState(kernel), MapOp(op) -> {
      let #(kernel, events) = map_kernel.apply_remote(kernel, op)
      Ok(#(MapState(kernel), list.map(events, MapEvent)))
    }
    CounterState(kernel), CounterOp(op) -> {
      let #(kernel, events) = counter_kernel.apply_remote(kernel, op)
      Ok(#(CounterState(kernel), list.map(events, CounterEvent)))
    }
    OrMapState(kernel), OrMapOp(op) ->
      case or_map_kernel.apply_remote(kernel, op) {
        Ok(#(kernel, events)) ->
          Ok(#(OrMapState(kernel), list.map(events, OrMapEvent)))
        Error(or_map_kernel.CorruptDelta(detail))
        | Error(or_map_kernel.ModeMismatch(detail)) ->
          Error(CorruptRemoteOp(detail))
        Error(or_map_kernel.UnexpectedAck(detail))
        | Error(or_map_kernel.UnexpectedRollback(detail)) ->
          Error(UnexpectedAck(detail))
      }
    OrSetState(kernel), OrSetOp(op) -> {
      let #(kernel, events) = or_set_kernel.apply_remote(kernel, op)
      Ok(#(OrSetState(kernel), list.map(events, OrSetEvent)))
    }
    RegisterCollectionState(kernel), RegisterCollectionOp(op) -> {
      let #(kernel, events) =
        register_collection_kernel.apply_remote(kernel, op, meta.seq)
      Ok(#(
        RegisterCollectionState(kernel),
        list.map(events, RegisterCollectionEvent),
      ))
    }
    ClaimsState(kernel), ClaimsOp(op) -> {
      let #(kernel, events) = claims_kernel.apply_remote(kernel, op, meta.seq)
      Ok(#(ClaimsState(kernel), list.map(events, ClaimsEvent)))
    }
    state, _ -> Error(wrong_channel_type(state, "remote op"))
  }
}

/// Commit an acked local op: pending → sequenced.
pub fn ack_local(
  state: ChannelState,
  op: ChannelOp,
  local: LocalOpMeta,
  meta: SequencedMeta,
) -> Result(
  #(ChannelState, List(ChannelEvent), Option(Resolution)),
  ChannelError,
) {
  case state, op {
    MapState(kernel), MapOp(op) ->
      case map_kernel.ack_local(kernel, op) {
        Ok(kernel) -> Ok(#(MapState(kernel), [], None))
        Error(map_kernel.UnexpectedAck(_, detail)) ->
          Error(UnexpectedAck(detail))
      }
    CounterState(kernel), CounterOp(op) ->
      case local {
        CounterMeta(message_id) ->
          case
            counter_kernel.ack_local_with_message_id(kernel, op, message_id)
          {
            Ok(kernel) -> Ok(#(CounterState(kernel), [], None))
            Error(counter_kernel.UnexpectedAck(_, detail))
            | Error(counter_kernel.UnexpectedRollback(_, detail)) ->
              Error(UnexpectedAck(detail))
          }
        NoMeta ->
          Error(UnexpectedAck("counter ack is missing its local message id"))
        OrMapMeta(_) -> Error(UnexpectedAck("counter ack has or-map metadata"))
        OrSetMeta(_) -> Error(UnexpectedAck("counter ack has or-set metadata"))
      }
    OrMapState(kernel), OrMapOp(op) ->
      case local {
        OrMapMeta(message_id) ->
          case or_map_kernel.ack_local_with_message_id(kernel, op, message_id) {
            Ok(kernel) -> Ok(#(OrMapState(kernel), [], None))
            Error(or_map_kernel.UnexpectedAck(detail))
            | Error(or_map_kernel.UnexpectedRollback(detail)) ->
              Error(UnexpectedAck(detail))
            Error(or_map_kernel.ModeMismatch(detail))
            | Error(or_map_kernel.CorruptDelta(detail)) ->
              Error(CorruptRemoteOp(detail))
          }
        NoMeta | CounterMeta(_) ->
          Error(UnexpectedAck("or-map ack is missing its local message id"))
        OrSetMeta(_) -> Error(UnexpectedAck("or-map ack has or-set metadata"))
      }
    OrSetState(kernel), OrSetOp(op) ->
      case local {
        OrSetMeta(message_id) ->
          case or_set_kernel.ack_local_with_message_id(kernel, op, message_id) {
            Ok(kernel) -> Ok(#(OrSetState(kernel), [], None))
            Error(or_set_kernel.UnexpectedAck(detail))
            | Error(or_set_kernel.UnexpectedRollback(detail)) ->
              Error(UnexpectedAck(detail))
          }
        NoMeta | CounterMeta(_) | OrMapMeta(_) ->
          Error(UnexpectedAck("or-set ack is missing its local message id"))
      }
    RegisterCollectionState(kernel), RegisterCollectionOp(op) -> {
      let #(kernel, events, _is_winner) =
        register_collection_kernel.ack_local(kernel, op, meta.seq)
      Ok(#(
        RegisterCollectionState(kernel),
        list.map(events, RegisterCollectionEvent),
        None,
      ))
    }
    ClaimsState(kernel), ClaimsOp(op) ->
      case claims_kernel.ack_local(kernel, op, meta.seq) {
        Ok(#(kernel, events, outcome)) ->
          Ok(#(
            ClaimsState(kernel),
            list.map(events, ClaimsEvent),
            Some(ClaimResolved(op.key, outcome)),
          ))
        Error(claims_kernel.UnexpectedAck(_, detail))
        | Error(claims_kernel.UnexpectedRollback(_, detail))
        | Error(claims_kernel.AlreadyPendingLocally(detail)) ->
          Error(UnexpectedAck(detail))
      }
    state, _ -> Error(wrong_channel_type(state, "local ack"))
  }
}

fn wrong_channel_type(state: ChannelState, context: String) -> ChannelError {
  WrongChannelType(
    context
    <> " does not match the "
    <> type_to_string(channel_type(state))
    <> " channel it was routed to",
  )
}

/// Whether a sequenced echo of our own op has the shape we submitted
/// (the FIFO ack-matching sanity check).
pub fn same_shape(ours: ChannelOp, echoed: ChannelOp) -> Bool {
  case ours, echoed {
    MapOp(ours), MapOp(echoed) -> same_map_shape(ours, echoed)
    CounterOp(counter_kernel.Increment(ours)),
      CounterOp(counter_kernel.Increment(echoed))
    -> ours == echoed
    OrMapOp(ours), OrMapOp(echoed) -> same_or_map_shape(ours, echoed)
    OrSetOp(ours), OrSetOp(echoed) -> same_or_set_shape(ours, echoed)
    RegisterCollectionOp(ours), RegisterCollectionOp(echoed) ->
      ours.key == echoed.key
      && ours.value == echoed.value
      && ours.ref_seq == echoed.ref_seq
    ClaimsOp(ours), ClaimsOp(echoed) ->
      ours.key == echoed.key
      && ours.value == echoed.value
      && ours.ref_seq == echoed.ref_seq
    _, _ -> False
  }
}

fn same_map_shape(ours: map_kernel.MapOp, echoed: map_kernel.MapOp) -> Bool {
  case ours, echoed {
    map_kernel.Set(our_key, _), map_kernel.Set(echoed_key, _) ->
      our_key == echoed_key
    map_kernel.Delete(our_key), map_kernel.Delete(echoed_key) ->
      our_key == echoed_key
    map_kernel.Clear, map_kernel.Clear -> True
    _, _ -> False
  }
}

fn same_or_map_shape(
  ours: or_map_kernel.OrMapOp,
  echoed: or_map_kernel.OrMapOp,
) -> Bool {
  case ours, echoed {
    or_map_kernel.Increment(our_key, our_amount, _),
      or_map_kernel.Increment(echoed_key, echoed_amount, _)
    -> our_key == echoed_key && our_amount == echoed_amount
    or_map_kernel.SetRegister(our_key, our_value, our_ts, _),
      or_map_kernel.SetRegister(echoed_key, echoed_value, echoed_ts, _)
    -> our_key == echoed_key && our_value == echoed_value && our_ts == echoed_ts
    or_map_kernel.Remove(our_key, _), or_map_kernel.Remove(echoed_key, _) ->
      our_key == echoed_key
    _, _ -> False
  }
}

fn same_or_set_shape(
  ours: or_set_kernel.OrSetOp,
  echoed: or_set_kernel.OrSetOp,
) -> Bool {
  case ours, echoed {
    or_set_kernel.Add(our_element, _), or_set_kernel.Add(echoed_element, _) ->
      our_element == echoed_element
    or_set_kernel.Remove(our_element, _),
      or_set_kernel.Remove(echoed_element, _)
    -> our_element == echoed_element
    _, _ -> False
  }
}

/// Whether a sequenced echo of our own attach carries the snapshot we
/// submitted (values compared structurally, not byte-wise).
pub fn same_snapshot(ours: Snapshot, echoed: Snapshot) -> Bool {
  case ours, echoed {
    MapSnapshot(ours), MapSnapshot(echoed) -> same_entries(ours, echoed)
    CounterSnapshot(ours), CounterSnapshot(echoed) -> ours == echoed
    OrMapSnapshot(our_mode, ours), OrMapSnapshot(echoed_mode, echoed) ->
      our_mode == echoed_mode && ours == echoed
    OrSetSnapshot(ours), OrSetSnapshot(echoed) -> ours == echoed
    RegisterCollectionSnapshot(ours), RegisterCollectionSnapshot(echoed) ->
      ours == echoed
    ClaimsSnapshot(ours), ClaimsSnapshot(echoed) -> ours == echoed
    _, _ -> False
  }
}

fn same_entries(
  ours: List(#(String, Json)),
  echoed: List(#(String, Json)),
) -> Bool {
  case ours, echoed {
    [], [] -> True
    [our, ..our_rest], [echoed, ..echoed_rest] ->
      our.0 == echoed.0
      && same_json_value(our.1, echoed.1)
      && same_entries(our_rest, echoed_rest)
    _, _ -> False
  }
}

fn same_json_value(ours: Json, echoed: Json) -> Bool {
  case json.parse(json.to_string(ours), wire.json_value_decoder()) {
    Ok(normalized_ours) ->
      case json.parse(json.to_string(echoed), wire.json_value_decoder()) {
        Ok(normalized_echoed) -> normalized_ours == normalized_echoed
        Error(_) -> False
      }
    Error(_) -> False
  }
}

/// Handle addresses reachable from the channel's current values, for
/// attach-dependency ordering. Counters hold no handles.
pub fn handle_addresses(state: ChannelState) -> List(String) {
  case state {
    MapState(kernel) ->
      list.flat_map(map_kernel.entries(kernel), fn(entry) {
        handle.collect_handle_addresses(entry.1)
      })
      |> list.unique
    CounterState(_) -> []
    OrMapState(kernel) ->
      case kernel.mode {
        or_map_kernel.TallyMode -> []
        or_map_kernel.RegisterMode ->
          list.flat_map(or_map_kernel.entries(kernel), fn(entry) {
            case entry.1 {
              or_map_kernel.Register(raw) ->
                case json.parse(raw, wire.json_value_decoder()) {
                  Ok(value) -> handle.collect_handle_addresses(value)
                  Error(_) -> []
                }
              or_map_kernel.Tally(_) -> []
            }
          })
          |> list.unique
      }
    OrSetState(_) -> []
    RegisterCollectionState(kernel) ->
      list.flat_map(
        register_collection_kernel.summary_registers(kernel),
        fn(entry) {
          let #(_, register_collection_kernel.Register(atomic, versions)) =
            entry
          [atomic, ..versions]
          |> list.flat_map(fn(version) {
            handle.collect_handle_addresses(version.value)
          })
        },
      )
      |> list.unique
    ClaimsState(kernel) ->
      list.append(
        claims_kernel.summary_entries(kernel)
          |> list.flat_map(fn(entry) {
            handle.collect_handle_addresses(entry.1)
          }),
        claims_kernel.pending_values(kernel)
          |> list.flat_map(handle.collect_handle_addresses),
      )
      |> list.unique
  }
}

/// Encode a snapshot's type-dependent payload (the attach op's `snapshot`
/// field, the summary blob channel's `data` field).
pub fn encode_snapshot(snapshot: Snapshot) -> Json {
  case snapshot {
    MapSnapshot(entries) -> wire.encode_entries(entries)
    CounterSnapshot(value) -> json.int(value)
    OrMapSnapshot(_, state) -> or_map.to_json(state)
    OrSetSnapshot(state) -> or_set.to_json(state)
    RegisterCollectionSnapshot(registers) -> encode_registers(registers)
    ClaimsSnapshot(entries) -> encode_claims(entries)
  }
}

/// Decoder for a snapshot payload, selected by channel type (the field the
/// carrying envelope names the type in).
pub fn snapshot_decoder(channel_type: ChannelType) -> Decoder(Snapshot) {
  case channel_type {
    MapChannel -> decode.list(wire.entry_decoder()) |> decode.map(MapSnapshot)
    CounterChannel -> decode.int |> decode.map(CounterSnapshot)
    OrMapChannel -> or_map_snapshot_decoder()
    OrSetChannel -> or_set_snapshot_decoder()
    RegisterCollectionChannel ->
      decode.list(register_entry_decoder())
      |> decode.map(RegisterCollectionSnapshot)
    ClaimsChannel ->
      decode.list(claim_entry_decoder()) |> decode.map(ClaimsSnapshot)
  }
}

fn encode_registers(
  registers: List(#(String, register_collection_kernel.Register)),
) -> Json {
  json.array(registers, fn(entry) {
    let #(key, register_collection_kernel.Register(atomic, versions)) = entry
    json.object([
      #("key", json.string(key)),
      #("atomic", encode_versioned(atomic)),
      #("versions", json.array(versions, encode_versioned)),
    ])
  })
}

fn encode_claims(entries: List(#(String, Json, Int))) -> Json {
  json.array(entries, fn(entry) {
    let #(key, value, sequence_number) = entry
    json.object([
      #("key", json.string(key)),
      #("value", value),
      #("sequenceNumber", json.int(sequence_number)),
    ])
  })
}

fn claim_entry_decoder() -> Decoder(#(String, Json, Int)) {
  use key <- decode.field("key", decode.string)
  use value <- decode.field("value", wire.json_value_decoder())
  use sequence_number <- decode.field("sequenceNumber", decode.int)
  decode.success(#(key, value, sequence_number))
}

fn encode_versioned(
  version: register_collection_kernel.VersionedValue,
) -> Json {
  json.object([
    #("value", version.value),
    #("sequenceNumber", json.int(version.sequence_number)),
  ])
}

fn register_entry_decoder() -> Decoder(
  #(String, register_collection_kernel.Register),
) {
  use key <- decode.field("key", decode.string)
  use atomic <- decode.field("atomic", versioned_decoder())
  use versions <- decode.field("versions", decode.list(versioned_decoder()))
  decode.success(#(key, register_collection_kernel.Register(atomic, versions)))
}

fn versioned_decoder() -> Decoder(register_collection_kernel.VersionedValue) {
  use value <- decode.field("value", wire.json_value_decoder())
  use sequence_number <- decode.field("sequenceNumber", decode.int)
  decode.success(register_collection_kernel.VersionedValue(
    value,
    sequence_number,
  ))
}

fn or_map_snapshot_decoder() -> Decoder(Snapshot) {
  use value <- decode.then(wire.json_value_decoder())
  let encoded = json.to_string(value)
  case json.parse(encoded, decode.at(["state", "crdt_spec"], decode.string)) {
    Ok(spec) ->
      case
        or_map_kernel.mode_from_spec_string(spec),
        or_map.from_json(encoded)
      {
        Ok(mode), Ok(state) -> decode.success(OrMapSnapshot(mode, state))
        Error(_), _ -> decode.failure(MapSnapshot([]), "ORMapSnapshot")
        _, Error(_) -> decode.failure(MapSnapshot([]), "ORMapSnapshot")
      }
    Error(_) -> decode.failure(MapSnapshot([]), "ORMapSnapshot")
  }
}

fn or_set_snapshot_decoder() -> Decoder(Snapshot) {
  use value <- decode.then(wire.json_value_decoder())
  let encoded = json.to_string(value)
  case or_set.from_json(encoded) {
    Ok(state) -> decode.success(OrSetSnapshot(state))
    Error(_) -> decode.failure(MapSnapshot([]), "ORSetSnapshot")
  }
}
