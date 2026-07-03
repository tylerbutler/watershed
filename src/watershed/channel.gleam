//// The closed sum of channel kernels the runtime can host, dispatched in
//// one module: parallel sums for state, ops, events, and snapshots, plus
//// one dispatch function per operation `runtime_core` needs.
////
//// The runtime routes everything through these sums instead of naming a
//// kernel directly, so onboarding a kernel is: add a variant to each sum
//// here, then follow the compiler to every dispatch site. The compiler
//// can't point at the non-type sites — the op codec in `wire/ops`, the
//// summary payload codec here (`encode_snapshot`/`snapshot_decoder`), the
//// actor verbs in `runtime`/`runtime_js`, and the fuzz model — those need
//// a manual pass.
////
//// Kernels stay pure and runtime-unaware; this module only wraps them.

import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/list

import watershed/handle
import watershed/map_kernel
import watershed/wire

/// The kinds of channel a document can host. Maps to/from the wire's
/// `channelType` strings via `type_to_string`/`type_from_string`.
pub type ChannelType {
  MapChannel
}

pub fn type_to_string(channel_type: ChannelType) -> String {
  case channel_type {
    MapChannel -> wire.channel_type_map
  }
}

pub fn type_from_string(raw: String) -> Result(ChannelType, Nil) {
  case raw == wire.channel_type_map {
    True -> Ok(MapChannel)
    False -> Error(Nil)
  }
}

/// One channel's kernel state.
pub type ChannelState {
  MapState(map_kernel.MapState)
}

/// A kernel op as it travels through the runtime (in-flight queue, ack
/// matching) and, via `wire/ops`, over the wire.
pub type ChannelOp {
  MapOp(map_kernel.MapOp)
}

/// A kernel event, address-tagged by the runtime before fan-out.
pub type ChannelEvent {
  MapEvent(map_kernel.MapEvent)
}

/// A channel's state as the persisted formats carry it: the attach op's
/// `snapshot` payload and the summary blob's per-channel `data` payload.
pub type Snapshot {
  MapSnapshot(entries: List(#(String, Json)))
}

/// Per-kernel *local* metadata an in-flight op carries alongside the wire
/// op (never serialized). Map ops carry none; counter local message ids
/// arrive with the counter kernel.
pub type LocalOpMeta {
  NoMeta
}

/// Sequencer-assigned metadata for a sequenced op. Map ignores it; kernels
/// that persist sequence numbers (claims) consume `seq`. Threaded from day
/// one so adding such a kernel is additive.
pub type SequencedMeta {
  SequencedMeta(seq: Int, last_seen_sn: Int)
}

pub type ChannelError {
  /// An ack did not line up with the kernel's pending queue. Fatal: the
  /// runtime routed an ack the kernel never submitted (or out of order).
  UnexpectedAck(detail: String)
}

pub fn channel_type(state: ChannelState) -> ChannelType {
  case state {
    MapState(_) -> MapChannel
  }
}

pub fn snapshot_type(snapshot: Snapshot) -> ChannelType {
  case snapshot {
    MapSnapshot(_) -> MapChannel
  }
}

pub fn new(channel_type: ChannelType) -> ChannelState {
  case channel_type {
    MapChannel -> MapState(map_kernel.new())
  }
}

/// Rebuild a channel from a persisted snapshot, `from_sequenced` semantics:
/// the snapshot's contents become confirmed state with nothing pending.
pub fn from_snapshot(snapshot: Snapshot) -> ChannelState {
  case snapshot {
    MapSnapshot(entries) -> MapState(map_kernel.from_sequenced(entries))
  }
}

/// The confirmed (sequenced-only) state, as a summary captures it.
pub fn snapshot(state: ChannelState) -> Snapshot {
  case state {
    MapState(kernel) -> MapSnapshot(map_kernel.sequenced_entries(kernel))
  }
}

/// The current optimistic view, as an attach op captures it. A detached
/// channel's local edits are all pending, so unlike `snapshot` this must
/// include them.
pub fn attach_snapshot(state: ChannelState) -> Snapshot {
  case state {
    MapState(kernel) -> MapSnapshot(map_kernel.entries(kernel))
  }
}

/// Apply a sequenced op from another client.
pub fn apply_remote(
  state: ChannelState,
  op: ChannelOp,
  _meta: SequencedMeta,
) -> Result(#(ChannelState, List(ChannelEvent)), ChannelError) {
  case state, op {
    MapState(kernel), MapOp(op) -> {
      let #(kernel, events) = map_kernel.apply_remote(kernel, op)
      Ok(#(MapState(kernel), list.map(events, MapEvent)))
    }
  }
}

/// Commit an acked local op: pending → sequenced.
pub fn ack_local(
  state: ChannelState,
  op: ChannelOp,
  _local: LocalOpMeta,
  _meta: SequencedMeta,
) -> Result(#(ChannelState, List(ChannelEvent)), ChannelError) {
  case state, op {
    MapState(kernel), MapOp(op) ->
      case map_kernel.ack_local(kernel, op) {
        Ok(kernel) -> Ok(#(MapState(kernel), []))
        Error(map_kernel.UnexpectedAck(_, detail)) ->
          Error(UnexpectedAck(detail))
      }
  }
}

/// Whether a sequenced echo of our own op has the shape we submitted
/// (the FIFO ack-matching sanity check).
pub fn same_shape(ours: ChannelOp, echoed: ChannelOp) -> Bool {
  case ours, echoed {
    MapOp(ours), MapOp(echoed) -> same_map_shape(ours, echoed)
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

/// Whether a sequenced echo of our own attach carries the snapshot we
/// submitted (values compared structurally, not byte-wise).
pub fn same_snapshot(ours: Snapshot, echoed: Snapshot) -> Bool {
  case ours, echoed {
    MapSnapshot(ours), MapSnapshot(echoed) -> same_entries(ours, echoed)
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
/// attach-dependency ordering.
pub fn handle_addresses(state: ChannelState) -> List(String) {
  case state {
    MapState(kernel) ->
      list.flat_map(map_kernel.entries(kernel), fn(entry) {
        handle.collect_handle_addresses(entry.1)
      })
      |> list.unique
  }
}

/// Encode a snapshot's type-dependent payload (the attach op's `snapshot`
/// field, the summary blob channel's `data` field).
pub fn encode_snapshot(snapshot: Snapshot) -> Json {
  case snapshot {
    MapSnapshot(entries) -> wire.encode_entries(entries)
  }
}

/// Decoder for a snapshot payload, selected by channel type (the field the
/// carrying envelope names the type in).
pub fn snapshot_decoder(channel_type: ChannelType) -> Decoder(Snapshot) {
  case channel_type {
    MapChannel -> decode.list(wire.entry_decoder()) |> decode.map(MapSnapshot)
  }
}
