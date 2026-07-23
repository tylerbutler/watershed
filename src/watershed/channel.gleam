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
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}

import lattice_core/replica_id
import lattice_counters/pn_counter.{type PNCounter}
import lattice_maps/or_map.{type ORMap}
import lattice_sequence/sequence.{type Sequence}
import lattice_sets/g_set.{type GSet}
import lattice_sets/or_set.{type ORSet}
import lattice_sets/two_p_set.{type TwoPSet}
import lattice_text/text.{type Text}
import watershed/claims_kernel
import watershed/client_id
import watershed/counter_kernel
import watershed/directory_kernel
import watershed/g_set_kernel
import watershed/handle
import watershed/json_ot
import watershed/json_ot_kernel
import watershed/map_kernel
import watershed/or_map_kernel
import watershed/or_set_kernel
import watershed/ordered_collection_kernel
import watershed/pact_map_kernel
import watershed/pn_counter_kernel
import watershed/register_collection_kernel
import watershed/rich_text
import watershed/rich_text_kernel
import watershed/sequence_kernel
import watershed/task_manager_kernel
import watershed/text_kernel
import watershed/two_p_set_kernel
import watershed/wire

/// The kinds of channel a document can host. Maps to/from the wire's
/// `channelType` strings via `type_to_string`/`type_from_string`.
pub type ChannelType {
  MapChannel
  CounterChannel
  PnCounterChannel
  OrMapChannel
  OrSetChannel
  GSetChannel
  TwoPSetChannel
  RegisterCollectionChannel
  ClaimsChannel
  TaskManagerChannel
  PactMapChannel
  JsonOtChannel
  DirectoryChannel
  OrderedCollectionChannel
  SequenceChannel
  RichTextChannel
  TextChannel
}

/// Creation parameters for a channel. Most channel types need only their
/// channel type; OR-map also needs its value mode.
pub type ChannelInit {
  InitMap
  InitCounter
  InitPnCounter
  InitOrMap(mode: or_map_kernel.OrMapMode)
  InitOrSet
  InitGSet
  InitTwoPSet
  InitRegisterCollection
  InitClaims
  InitTaskManager
  InitPactMap
  InitJsonOt
  InitDirectory
  InitOrderedCollection
  InitSequence
  InitRichText
  InitText
}

pub fn type_to_string(channel_type: ChannelType) -> String {
  case channel_type {
    MapChannel -> wire.channel_type_map
    CounterChannel -> wire.channel_type_counter
    PnCounterChannel -> wire.channel_type_pn_counter
    OrMapChannel -> wire.channel_type_or_map
    OrSetChannel -> wire.channel_type_or_set
    GSetChannel -> wire.channel_type_g_set
    TwoPSetChannel -> wire.channel_type_two_p_set
    RegisterCollectionChannel -> wire.channel_type_register_collection
    ClaimsChannel -> wire.channel_type_claims
    TaskManagerChannel -> wire.channel_type_task_manager
    PactMapChannel -> wire.channel_type_pact_map
    JsonOtChannel -> wire.channel_type_json_ot
    DirectoryChannel -> wire.channel_type_directory
    OrderedCollectionChannel -> wire.channel_type_ordered_collection
    SequenceChannel -> wire.channel_type_sequence
    RichTextChannel -> wire.channel_type_rich_text
    TextChannel -> wire.channel_type_text
  }
}

pub fn type_from_string(raw: String) -> Result(ChannelType, Nil) {
  case raw {
    _ if raw == wire.channel_type_map -> Ok(MapChannel)
    _ if raw == wire.channel_type_counter -> Ok(CounterChannel)
    _ if raw == wire.channel_type_pn_counter -> Ok(PnCounterChannel)
    _ if raw == wire.channel_type_or_map -> Ok(OrMapChannel)
    _ if raw == wire.channel_type_or_set -> Ok(OrSetChannel)
    _ if raw == wire.channel_type_g_set -> Ok(GSetChannel)
    _ if raw == wire.channel_type_two_p_set -> Ok(TwoPSetChannel)
    _ if raw == wire.channel_type_register_collection ->
      Ok(RegisterCollectionChannel)
    _ if raw == wire.channel_type_claims -> Ok(ClaimsChannel)
    _ if raw == wire.channel_type_task_manager -> Ok(TaskManagerChannel)
    _ if raw == wire.channel_type_pact_map -> Ok(PactMapChannel)
    _ if raw == wire.channel_type_json_ot -> Ok(JsonOtChannel)
    _ if raw == wire.channel_type_directory -> Ok(DirectoryChannel)
    _ if raw == wire.channel_type_ordered_collection ->
      Ok(OrderedCollectionChannel)
    _ if raw == wire.channel_type_sequence -> Ok(SequenceChannel)
    _ if raw == wire.channel_type_rich_text -> Ok(RichTextChannel)
    _ if raw == wire.channel_type_text -> Ok(TextChannel)
    _ -> Error(Nil)
  }
}

pub fn init_type(init: ChannelInit) -> ChannelType {
  case init {
    InitMap -> MapChannel
    InitCounter -> CounterChannel
    InitPnCounter -> PnCounterChannel
    InitOrMap(_) -> OrMapChannel
    InitOrSet -> OrSetChannel
    InitGSet -> GSetChannel
    InitTwoPSet -> TwoPSetChannel
    InitRegisterCollection -> RegisterCollectionChannel
    InitClaims -> ClaimsChannel
    InitTaskManager -> TaskManagerChannel
    InitPactMap -> PactMapChannel
    InitJsonOt -> JsonOtChannel
    InitDirectory -> DirectoryChannel
    InitOrderedCollection -> OrderedCollectionChannel
    InitSequence -> SequenceChannel
    InitRichText -> RichTextChannel
    InitText -> TextChannel
  }
}

/// One channel's kernel state.
pub type ChannelState {
  MapState(map_kernel.MapState)
  CounterState(counter_kernel.CounterState)
  PnCounterState(pn_counter_kernel.PnCounterState)
  OrMapState(or_map_kernel.OrMapState)
  OrSetState(or_set_kernel.OrSetState)
  GSetState(g_set_kernel.GSetState)
  TwoPSetState(two_p_set_kernel.TwoPSetState)
  RegisterCollectionState(register_collection_kernel.RegisterState)
  ClaimsState(claims_kernel.ClaimsState)
  TaskManagerState(task_manager_kernel.TaskManagerState)
  PactMapState(pact_map_kernel.PactMapState)
  JsonOtState(json_ot_kernel.JsonOtState)
  DirectoryState(directory_kernel.DirectoryState)
  OrderedCollectionState(ordered_collection_kernel.OrderedState)
  SequenceState(sequence_kernel.SequenceState)
  RichTextState(rich_text_kernel.RichTextState)
  TextState(text_kernel.TextState)
}

/// A kernel op as it travels through the runtime (in-flight queue, ack
/// matching) and, via `wire/ops`, over the wire.
pub type ChannelOp {
  MapOp(map_kernel.MapOp)
  CounterOp(counter_kernel.CounterOp)
  PnCounterOp(pn_counter_kernel.PnCounterOp)
  OrMapOp(or_map_kernel.OrMapOp)
  OrSetOp(or_set_kernel.OrSetOp)
  GSetOp(g_set_kernel.GSetOp)
  TwoPSetOp(two_p_set_kernel.TwoPSetOp)
  RegisterCollectionOp(register_collection_kernel.WriteOp)
  ClaimsOp(claims_kernel.ClaimOp)
  TaskManagerOp(task_manager_kernel.TaskManagerOp)
  PactMapOp(pact_map_kernel.PactMapOp)
  JsonOtOp(json_ot_kernel.JsonOtWireOp)
  /// A directory op plus the kernel `message_id` that identifies this
  /// submission. Unlike other kernels the id travels *in the op* because a
  /// remote client needs the author's client-sequence identity to run the
  /// stale-instance filter (D12) and sibling ordering (D9); the runtime's own
  /// csn counts every channel's ops together and would not match the kernel's
  /// per-directory counter.
  DirectoryOp(op: directory_kernel.DirectoryOp, message_id: Int)
  OrderedCollectionOp(ordered_collection_kernel.OrderedOp)
  SequenceOp(sequence_kernel.SequenceOp)
  RichTextOp(rich_text_kernel.RichTextWireOp)
  TextOp(text_kernel.TextOp)
}

/// A kernel event, address-tagged by the runtime before fan-out.
pub type ChannelEvent {
  MapEvent(map_kernel.MapEvent)
  CounterEvent(counter_kernel.CounterEvent)
  PnCounterEvent(pn_counter_kernel.PnCounterEvent)
  OrMapEvent(or_map_kernel.OrMapEvent)
  OrSetEvent(or_set_kernel.OrSetEvent)
  GSetEvent(g_set_kernel.GSetEvent)
  TwoPSetEvent(two_p_set_kernel.TwoPSetEvent)
  RegisterCollectionEvent(register_collection_kernel.RegisterEvent)
  ClaimsEvent(claims_kernel.ClaimEvent)
  TaskManagerEvent(task_manager_kernel.TaskManagerEvent)
  PactMapEvent(pact_map_kernel.PactMapEvent)
  JsonOtEvent(json_ot_kernel.JsonOtEvent)
  DirectoryEvent(directory_kernel.DirectoryEvent)
  OrderedCollectionEvent(ordered_collection_kernel.OrderedEvent)
  SequenceEvent(sequence_kernel.SequenceEvent)
  RichTextEvent(rich_text_kernel.RichTextEvent)
  TextEvent(text_kernel.TextEvent)
}

/// A channel's state as the persisted formats carry it: the attach op's
/// `snapshot` payload and the summary blob's per-channel `data` payload.
pub type Snapshot {
  MapSnapshot(entries: List(#(String, Json)))
  CounterSnapshot(value: Int)
  PnCounterSnapshot(state: PNCounter)
  OrMapSnapshot(mode: or_map_kernel.OrMapMode, state: ORMap)
  OrSetSnapshot(state: ORSet(String))
  GSetSnapshot(state: GSet(String))
  TwoPSetSnapshot(state: TwoPSet(String))
  RegisterCollectionSnapshot(
    registers: List(#(String, register_collection_kernel.Register)),
  )
  ClaimsSnapshot(entries: List(#(String, Json, Int)))
  TaskManagerSnapshot(queues: List(#(String, List(Int))))
  PactMapSnapshot(entries: List(#(String, pact_map_kernel.Pact)))
  JsonOtSnapshot(doc: json_ot.JsonValue)
  DirectorySnapshot(summary: directory_kernel.DirectorySummary)
  OrderedCollectionSnapshot(
    queue: List(Json),
    jobs: List(#(String, ordered_collection_kernel.JobEntry)),
  )
  SequenceSummary(state: Sequence(Json))
  RichTextSnapshot(document: rich_text.Document)
  TextSummary(state: Text)
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
  PnCounterMeta(message_id: Int)
  OrMapMeta(message_id: Int)
  OrSetMeta(message_id: Int)
  GSetMeta(message_id: Int)
  TwoPSetMeta(message_id: Int)
  TaskManagerMeta(message_id: Int)
  DirectoryMeta(message_id: Int)
  SequenceMeta(message_id: Int)
  TextMeta(message_id: Int)
}

/// Sequencer-assigned metadata for a sequenced op. Map and counter ignore
/// it; kernels that persist sequence numbers consume `seq`.
/// Threaded from day one so adding such a kernel is additive.
pub type SequencedMeta {
  SequencedMeta(
    seq: Int,
    last_seen_sn: Int,
    min_seq: Int,
    author: Int,
    self: Int,
    quorum: List(Int),
    /// The op author's reference sequence number — what they had seen when
    /// they submitted. The directory kernel's stale-instance filter (D12)
    /// consumes it; other kernels ignore it. `last_seen_sn` is the *local*
    /// client's watermark and is not a substitute.
    reference_sequence_number: Int,
  )
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
    PnCounterState(_) -> PnCounterChannel
    OrMapState(_) -> OrMapChannel
    OrSetState(_) -> OrSetChannel
    GSetState(_) -> GSetChannel
    TwoPSetState(_) -> TwoPSetChannel
    RegisterCollectionState(_) -> RegisterCollectionChannel
    ClaimsState(_) -> ClaimsChannel
    TaskManagerState(_) -> TaskManagerChannel
    PactMapState(_) -> PactMapChannel
    JsonOtState(_) -> JsonOtChannel
    DirectoryState(_) -> DirectoryChannel
    OrderedCollectionState(_) -> OrderedCollectionChannel
    SequenceState(_) -> SequenceChannel
    RichTextState(_) -> RichTextChannel
    TextState(_) -> TextChannel
  }
}

pub fn snapshot_type(snapshot: Snapshot) -> ChannelType {
  case snapshot {
    MapSnapshot(_) -> MapChannel
    CounterSnapshot(_) -> CounterChannel
    PnCounterSnapshot(_) -> PnCounterChannel
    OrMapSnapshot(_, _) -> OrMapChannel
    OrSetSnapshot(_) -> OrSetChannel
    GSetSnapshot(_) -> GSetChannel
    TwoPSetSnapshot(_) -> TwoPSetChannel
    RegisterCollectionSnapshot(_) -> RegisterCollectionChannel
    ClaimsSnapshot(_) -> ClaimsChannel
    TaskManagerSnapshot(_) -> TaskManagerChannel
    PactMapSnapshot(_) -> PactMapChannel
    JsonOtSnapshot(_) -> JsonOtChannel
    DirectorySnapshot(_) -> DirectoryChannel
    OrderedCollectionSnapshot(_, _) -> OrderedCollectionChannel
    SequenceSummary(_) -> SequenceChannel
    RichTextSnapshot(_) -> RichTextChannel
    TextSummary(_) -> TextChannel
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
    InitPnCounter ->
      PnCounterState(pn_counter_kernel.new(replica_id.new(replica)))
    InitOrMap(mode) ->
      OrMapState(or_map_kernel.new(replica_id.new(replica), mode))
    InitOrSet -> OrSetState(or_set_kernel.new(replica_id.new(replica)))
    InitGSet -> GSetState(g_set_kernel.new())
    InitTwoPSet -> TwoPSetState(two_p_set_kernel.new())
    InitRegisterCollection ->
      RegisterCollectionState(register_collection_kernel.new())
    InitClaims -> ClaimsState(claims_kernel.new())
    InitTaskManager -> TaskManagerState(task_manager_kernel.new())
    InitPactMap -> PactMapState(pact_map_kernel.new())
    InitJsonOt -> JsonOtState(json_ot_kernel.new(client_id.to_int(replica)))
    InitDirectory -> DirectoryState(directory_kernel.new())
    InitOrderedCollection ->
      OrderedCollectionState(ordered_collection_kernel.new())
    InitSequence -> SequenceState(sequence_kernel.new(replica_id.new(replica)))
    InitRichText ->
      RichTextState(rich_text_kernel.new(client_id.to_int(replica)))
    InitText -> TextState(text_kernel.new(replica_id.new(replica)))
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
    PnCounterSnapshot(state) ->
      PnCounterState(pn_counter_kernel.from_sequenced(
        state,
        replica_id.new(replica),
      ))
    OrMapSnapshot(mode, state) -> {
      let assert Ok(kernel) =
        or_map_kernel.from_sequenced(state, mode, replica_id.new(replica))
      OrMapState(kernel)
    }
    OrSetSnapshot(state) ->
      OrSetState(or_set_kernel.from_sequenced(state, replica_id.new(replica)))
    GSetSnapshot(state) -> GSetState(g_set_kernel.from_sequenced(state))
    TwoPSetSnapshot(state) ->
      TwoPSetState(two_p_set_kernel.from_sequenced(state))
    RegisterCollectionSnapshot(registers) ->
      RegisterCollectionState(register_collection_kernel.from_summary(registers))
    ClaimsSnapshot(entries) -> ClaimsState(claims_kernel.from_summary(entries))
    TaskManagerSnapshot(queues) ->
      TaskManagerState(task_manager_kernel.from_summary(queues))
    PactMapSnapshot(entries) ->
      PactMapState(pact_map_kernel.from_summary(entries))
    JsonOtSnapshot(doc) ->
      JsonOtState(json_ot_kernel.from_summary(client_id.to_int(replica), doc))
    DirectorySnapshot(summary) ->
      DirectoryState(directory_kernel.from_summary(summary))
    OrderedCollectionSnapshot(queue, jobs) ->
      OrderedCollectionState(ordered_collection_kernel.from_summary(queue, jobs))
    SequenceSummary(state) ->
      SequenceState(sequence_kernel.from_sequenced(
        state,
        replica_id.new(replica),
      ))
    RichTextSnapshot(document) ->
      RichTextState(rich_text_kernel.from_summary(
        client_id.to_int(replica),
        document,
      ))
    TextSummary(state) ->
      TextState(text_kernel.from_sequenced(state, replica_id.new(replica)))
  }
}

/// The confirmed (sequenced-only) state, as a summary captures it.
pub fn snapshot(state: ChannelState) -> Snapshot {
  case state {
    MapState(kernel) -> MapSnapshot(map_kernel.sequenced_entries(kernel))
    CounterState(kernel) -> CounterSnapshot(counter_sequenced_value(kernel))
    PnCounterState(kernel) -> PnCounterSnapshot(kernel.sequenced)
    OrMapState(kernel) -> OrMapSnapshot(kernel.mode, kernel.sequenced)
    OrSetState(kernel) -> OrSetSnapshot(kernel.sequenced)
    GSetState(kernel) -> GSetSnapshot(kernel.sequenced)
    TwoPSetState(kernel) -> TwoPSetSnapshot(kernel.sequenced)
    RegisterCollectionState(kernel) ->
      RegisterCollectionSnapshot(register_collection_kernel.summary_registers(
        kernel,
      ))
    ClaimsState(kernel) -> ClaimsSnapshot(claims_kernel.summary_entries(kernel))
    TaskManagerState(kernel) ->
      TaskManagerSnapshot(task_manager_kernel.summary_queues(kernel))
    PactMapState(kernel) ->
      PactMapSnapshot(pact_map_kernel.summary_entries(kernel))
    JsonOtState(kernel) -> JsonOtSnapshot(json_ot_kernel.summary(kernel))
    DirectoryState(kernel) ->
      DirectorySnapshot(directory_kernel.summary_tree(kernel))
    OrderedCollectionState(kernel) ->
      OrderedCollectionSnapshot(
        ordered_collection_kernel.summary_queue(kernel),
        ordered_collection_kernel.summary_jobs(kernel),
      )
    SequenceState(kernel) -> SequenceSummary(kernel.sequenced)
    RichTextState(kernel) -> RichTextSnapshot(rich_text_kernel.summary(kernel))
    TextState(kernel) -> TextSummary(kernel.sequenced)
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
    PnCounterState(kernel) -> PnCounterSnapshot(kernel.optimistic)
    OrMapState(kernel) -> OrMapSnapshot(kernel.mode, kernel.optimistic)
    OrSetState(kernel) -> OrSetSnapshot(kernel.optimistic)
    GSetState(kernel) -> GSetSnapshot(kernel.optimistic)
    TwoPSetState(kernel) -> TwoPSetSnapshot(kernel.optimistic)
    RegisterCollectionState(kernel) ->
      RegisterCollectionSnapshot(register_collection_kernel.summary_registers(
        kernel,
      ))
    ClaimsState(kernel) -> ClaimsSnapshot(claims_kernel.summary_entries(kernel))
    TaskManagerState(kernel) ->
      TaskManagerSnapshot(task_manager_kernel.summary_queues(kernel))
    // PactMap is a consensus kernel with no optimistic local state (like
    // task_manager); attach carries the confirmed summary.
    PactMapState(kernel) ->
      PactMapSnapshot(pact_map_kernel.summary_entries(kernel))
    JsonOtState(kernel) ->
      case json_ot_kernel.view(kernel) {
        Ok(doc) -> JsonOtSnapshot(doc)
        Error(_) -> JsonOtSnapshot(json_ot_kernel.summary(kernel))
      }
    // Directory attach carries the sequenced tree only; detached local edits
    // (pending, non-summarized) are treated like the other non-optimistic
    // kernels here. The demo and multi-client flows always attach first.
    DirectoryState(kernel) ->
      DirectorySnapshot(directory_kernel.summary_tree(kernel))
    // The queue kernel keeps a single state (no pending/sequenced split), so
    // the optimistic attach view equals the confirmed summary; detached
    // adds/acquires are already folded into it and travel in the attach.
    OrderedCollectionState(kernel) ->
      OrderedCollectionSnapshot(
        ordered_collection_kernel.summary_queue(kernel),
        ordered_collection_kernel.summary_jobs(kernel),
      )
    SequenceState(kernel) -> SequenceSummary(kernel.optimistic)
    RichTextState(kernel) ->
      case rich_text_kernel.view(kernel) {
        Ok(document) -> RichTextSnapshot(document)
        Error(_) -> RichTextSnapshot(rich_text_kernel.summary(kernel))
      }
    TextState(kernel) -> TextSummary(kernel.optimistic)
  }
}

pub fn attach_state(
  state: ChannelState,
  replica replica: String,
) -> ChannelState {
  case state {
    OrMapState(kernel) -> OrMapState(or_map_kernel.promote_attach(kernel))
    OrSetState(kernel) -> OrSetState(or_set_kernel.promote_attach(kernel))
    GSetState(kernel) -> GSetState(g_set_kernel.promote_attach(kernel))
    TwoPSetState(kernel) ->
      TwoPSetState(two_p_set_kernel.promote_attach(kernel))
    SequenceState(kernel) ->
      SequenceState(sequence_kernel.promote_attach(kernel))
    TextState(kernel) -> TextState(text_kernel.promote_attach(kernel))
    RegisterCollectionState(_) ->
      from_snapshot(attach_snapshot(state), replica:)
    _ -> from_snapshot(attach_snapshot(state), replica: replica)
  }
}

/// Apply a sequenced op from another client.
///
/// Returns the updated state, the events it produced, and any *owed* follow-up
/// ops the kernel wants the runtime to auto-submit (a fresh CSN + in-flight
/// entry) in reaction to this op — e.g. a consensus kernel emitting its own
/// `Accept` after seeing a peer's `Set`. Most kernels owe nothing and return
/// an empty list; the runtime buffers owed ops per channel and drains them
/// after the current sequenced batch (see `runtime_core.collect_released_ops`).
pub fn apply_remote(
  state: ChannelState,
  op: ChannelOp,
  meta: SequencedMeta,
) -> Result(#(ChannelState, List(ChannelEvent), List(ChannelOp)), ChannelError) {
  case state, op {
    MapState(kernel), MapOp(op) -> {
      let #(kernel, events) = map_kernel.apply_remote(kernel, op)
      Ok(#(MapState(kernel), list.map(events, MapEvent), []))
    }
    CounterState(kernel), CounterOp(op) -> {
      let #(kernel, events) = counter_kernel.apply_remote(kernel, op)
      Ok(#(CounterState(kernel), list.map(events, CounterEvent), []))
    }
    PnCounterState(kernel), PnCounterOp(op) -> {
      let #(kernel, events) = pn_counter_kernel.apply_remote(kernel, op)
      Ok(#(PnCounterState(kernel), list.map(events, PnCounterEvent), []))
    }
    OrMapState(kernel), OrMapOp(op) ->
      case or_map_kernel.apply_remote(kernel, op) {
        Ok(#(kernel, events)) ->
          Ok(#(OrMapState(kernel), list.map(events, OrMapEvent), []))
        Error(or_map_kernel.CorruptDelta(detail))
        | Error(or_map_kernel.ModeMismatch(detail)) ->
          Error(CorruptRemoteOp(detail))
        Error(or_map_kernel.UnexpectedAck(detail))
        | Error(or_map_kernel.UnexpectedRollback(detail)) ->
          Error(UnexpectedAck(detail))
      }
    OrSetState(kernel), OrSetOp(op) -> {
      let #(kernel, events) = or_set_kernel.apply_remote(kernel, op)
      Ok(#(OrSetState(kernel), list.map(events, OrSetEvent), []))
    }
    GSetState(kernel), GSetOp(op) -> {
      let #(kernel, events) = g_set_kernel.apply_remote(kernel, op)
      Ok(#(GSetState(kernel), list.map(events, GSetEvent), []))
    }
    TwoPSetState(kernel), TwoPSetOp(op) -> {
      let #(kernel, events) = two_p_set_kernel.apply_remote(kernel, op)
      Ok(#(TwoPSetState(kernel), list.map(events, TwoPSetEvent), []))
    }
    RegisterCollectionState(kernel), RegisterCollectionOp(op) -> {
      let #(kernel, events) =
        register_collection_kernel.apply_remote(kernel, op, meta.seq)
      Ok(
        #(
          RegisterCollectionState(kernel),
          list.map(events, RegisterCollectionEvent),
          [],
        ),
      )
    }
    ClaimsState(kernel), ClaimsOp(op) -> {
      let #(kernel, events) = claims_kernel.apply_remote(kernel, op, meta.seq)
      Ok(#(ClaimsState(kernel), list.map(events, ClaimsEvent), []))
    }
    TaskManagerState(kernel), TaskManagerOp(op) -> {
      let #(kernel, events) =
        task_manager_kernel.apply_remote(kernel, op, meta.author, meta.quorum)
      Ok(#(TaskManagerState(kernel), list.map(events, TaskManagerEvent), []))
    }
    PactMapState(kernel), PactMapOp(op) -> apply_pact_map(kernel, op, meta)
    JsonOtState(kernel), JsonOtOp(op) ->
      case
        json_ot_kernel.apply_remote(
          kernel,
          op,
          meta.seq,
          meta.author,
          meta.min_seq,
        )
      {
        Ok(#(kernel, events)) ->
          Ok(#(JsonOtState(kernel), list.map(events, JsonOtEvent), []))
        Error(json_ot_kernel.UnexpectedAck(detail)) ->
          Error(UnexpectedAck(detail))
        Error(json_ot_kernel.OtFailure(err)) ->
          Error(CorruptRemoteOp(json_ot_error_detail(err)))
      }
    DirectoryState(kernel), DirectoryOp(op, message_id) -> {
      let #(kernel, events) =
        directory_kernel.apply_remote(
          kernel,
          op,
          directory_sequenced_meta(meta, message_id),
          meta.self,
        )
      Ok(#(DirectoryState(kernel), list.map(events, DirectoryEvent), []))
    }
    OrderedCollectionState(kernel), OrderedCollectionOp(op) -> {
      let #(kernel, events) =
        ordered_collection_kernel.apply_remote(kernel, op, meta.author)
      Ok(
        #(
          OrderedCollectionState(kernel),
          list.map(events, OrderedCollectionEvent),
          [],
        ),
      )
    }
    SequenceState(kernel), SequenceOp(op) -> {
      let #(kernel, events) = sequence_kernel.apply_remote(kernel, op)
      Ok(#(SequenceState(kernel), list.map(events, SequenceEvent), []))
    }
    RichTextState(kernel), RichTextOp(op) ->
      case
        rich_text_kernel.apply_remote(
          kernel,
          op,
          meta.seq,
          meta.author,
          meta.min_seq,
        )
      {
        Ok(#(kernel, events)) ->
          Ok(#(RichTextState(kernel), list.map(events, RichTextEvent), []))
        Error(rich_text_kernel.UnexpectedAck(detail)) ->
          Error(UnexpectedAck(detail))
        Error(rich_text_kernel.RichTextFailure(err)) ->
          Error(CorruptRemoteOp(rich_text_error_detail(err)))
      }
    TextState(kernel), TextOp(op) -> {
      let #(kernel, events) = text_kernel.apply_remote(kernel, op)
      Ok(#(TextState(kernel), list.map(events, TextEvent), []))
    }
    state, _ -> Error(wrong_channel_type(state, "remote op"))
  }
}

/// Apply a sequenced PactMap op — `Set` via `apply_set` (which may owe an
/// `Accept` when this client is a signoff), `Accept` via `apply_accept`.
/// Own and remote ops route through here identically (the runtime uses
/// `is_own_op` only to reclaim the in-flight entry); FluidFramework's PactMap
/// applies on sequencing regardless of author.
fn apply_pact_map(
  kernel: pact_map_kernel.PactMapState,
  op: pact_map_kernel.PactMapOp,
  meta: SequencedMeta,
) -> Result(#(ChannelState, List(ChannelEvent), List(ChannelOp)), ChannelError) {
  case op {
    pact_map_kernel.Set(_, _, _) -> {
      let #(kernel, events, reaction) =
        pact_map_kernel.apply_set(kernel, op, meta.seq, meta.quorum, meta.self)
      Ok(#(
        PactMapState(kernel),
        list.map(events, PactMapEvent),
        pact_map_reaction_ops(reaction),
      ))
    }
    pact_map_kernel.Accept(key) ->
      case pact_map_kernel.apply_accept(kernel, key, meta.author, meta.seq) {
        Ok(#(kernel, events)) ->
          Ok(#(PactMapState(kernel), list.map(events, PactMapEvent), []))
        Error(pact_map_kernel.UnexpectedAccept(_, _, detail)) ->
          Error(CorruptRemoteOp(detail))
      }
  }
}

/// A PactMap `Set` reaction as a channel-level owed op the runtime auto-submits.
fn pact_map_reaction_ops(
  reaction: pact_map_kernel.SetReaction,
) -> List(ChannelOp) {
  case reaction {
    pact_map_kernel.OweAccept(op) -> [PactMapOp(op)]
    pact_map_kernel.NoReaction -> []
  }
}

/// Whether a channel applies its *own* sequenced ops through `apply_remote`
/// (the same path as remote ops) rather than an optimistic `ack_local`.
/// Consensus kernels (PactMap) take effect only on sequencing regardless of
/// author, so the runtime reclaims the in-flight entry and then applies via
/// `apply_remote`; every optimistic kernel returns `False` and acks locally.
pub fn applies_own_on_sequence(state: ChannelState) -> Bool {
  case state {
    PactMapState(_) -> True
    _ -> False
  }
}

/// Apply a sequenced membership-leave to a channel: the addressed client has
/// left the collaboration session at `leave_seq`. Consensus/queue kernels that
/// track per-client state settle it deterministically (PactMap drains the
/// leaver's outstanding signoffs so stuck pending values can settle;
/// ConsensusOrderedCollection re-releases the leaver's held jobs to the queue;
/// TaskManager drops the leaver from every task queue). Kernels with no
/// membership semantics are a no-op. Fanned out over every attached channel by
/// the runtime on a `"leave"` system message.
pub fn on_leave(
  state: ChannelState,
  client_id: Int,
  leave_seq: Int,
) -> #(ChannelState, List(ChannelEvent)) {
  case state {
    PactMapState(kernel) -> {
      let #(kernel, events) =
        pact_map_kernel.remove_member(kernel, client_id, leave_seq)
      #(PactMapState(kernel), list.map(events, PactMapEvent))
    }
    OrderedCollectionState(kernel) -> {
      let #(kernel, events) =
        ordered_collection_kernel.remove_client(kernel, Some(client_id))
      #(
        OrderedCollectionState(kernel),
        list.map(events, OrderedCollectionEvent),
      )
    }
    TaskManagerState(kernel) -> {
      let #(kernel, events) =
        task_manager_kernel.remove_client(kernel, client_id)
      #(TaskManagerState(kernel), list.map(events, TaskManagerEvent))
    }
    _ -> #(state, [])
  }
}

/// Build the directory kernel's `SequencedMeta` from the channel-level meta
/// plus the op's kernel `message_id` (its client-sequence identity).
fn directory_sequenced_meta(
  meta: SequencedMeta,
  message_id: Int,
) -> directory_kernel.SequencedMeta {
  directory_kernel.SequencedMeta(
    author: meta.author,
    sequence_number: meta.seq,
    reference_sequence_number: meta.reference_sequence_number,
    client_sequence_number: message_id,
  )
}

fn directory_error_detail(err: directory_kernel.KernelError) -> String {
  case err {
    directory_kernel.UnexpectedAck(_, detail) -> "directory ack: " <> detail
    directory_kernel.UnexpectedRollback(_, detail) ->
      "directory rollback: " <> detail
    directory_kernel.PathNotFound(path) -> "directory path not found: " <> path
    directory_kernel.InvalidName(name) -> "directory invalid name: " <> name
    directory_kernel.InvariantViolation(detail) ->
      "directory invariant: " <> detail
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
        PnCounterMeta(_) ->
          Error(UnexpectedAck("counter ack has pn-counter metadata"))
        OrMapMeta(_) -> Error(UnexpectedAck("counter ack has or-map metadata"))
        OrSetMeta(_) -> Error(UnexpectedAck("counter ack has or-set metadata"))
        GSetMeta(_) -> Error(UnexpectedAck("counter ack has g-set metadata"))
        TwoPSetMeta(_) ->
          Error(UnexpectedAck("counter ack has two-p-set metadata"))
        TaskManagerMeta(_) ->
          Error(UnexpectedAck("counter ack has task-manager metadata"))
        DirectoryMeta(_) ->
          Error(UnexpectedAck("counter ack has directory metadata"))
        SequenceMeta(_) ->
          Error(UnexpectedAck("counter ack has sequence metadata"))
        TextMeta(_) -> Error(UnexpectedAck("counter ack has text metadata"))
      }
    PnCounterState(kernel), PnCounterOp(op) ->
      case local {
        PnCounterMeta(message_id) ->
          case
            pn_counter_kernel.ack_local_with_message_id(kernel, op, message_id)
          {
            Ok(kernel) -> Ok(#(PnCounterState(kernel), [], None))
            Error(pn_counter_kernel.UnexpectedAck(_, detail))
            | Error(pn_counter_kernel.UnexpectedRollback(_, detail)) ->
              Error(UnexpectedAck(detail))
          }
        NoMeta ->
          Error(UnexpectedAck("pn-counter ack is missing its local message id"))
        CounterMeta(_) ->
          Error(UnexpectedAck("pn-counter ack has counter metadata"))
        OrMapMeta(_) ->
          Error(UnexpectedAck("pn-counter ack has or-map metadata"))
        OrSetMeta(_) ->
          Error(UnexpectedAck("pn-counter ack has or-set metadata"))
        GSetMeta(_) -> Error(UnexpectedAck("pn-counter ack has g-set metadata"))
        TwoPSetMeta(_) ->
          Error(UnexpectedAck("pn-counter ack has two-p-set metadata"))
        TaskManagerMeta(_) ->
          Error(UnexpectedAck("pn-counter ack has task-manager metadata"))
        DirectoryMeta(_) ->
          Error(UnexpectedAck("pn-counter ack has directory metadata"))
        SequenceMeta(_) ->
          Error(UnexpectedAck("pn-counter ack has sequence metadata"))
        TextMeta(_) -> Error(UnexpectedAck("pn-counter ack has text metadata"))
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
        NoMeta | CounterMeta(_) | PnCounterMeta(_) ->
          Error(UnexpectedAck("or-map ack is missing its local message id"))
        OrSetMeta(_) -> Error(UnexpectedAck("or-map ack has or-set metadata"))
        GSetMeta(_) -> Error(UnexpectedAck("or-map ack has g-set metadata"))
        TwoPSetMeta(_) ->
          Error(UnexpectedAck("or-map ack has two-p-set metadata"))
        TaskManagerMeta(_) ->
          Error(UnexpectedAck("or-map ack has task-manager metadata"))
        DirectoryMeta(_) ->
          Error(UnexpectedAck("or-map ack has directory metadata"))
        SequenceMeta(_) ->
          Error(UnexpectedAck("or-map ack has sequence metadata"))
        TextMeta(_) -> Error(UnexpectedAck("or-map ack has text metadata"))
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
        NoMeta
        | CounterMeta(_)
        | PnCounterMeta(_)
        | OrMapMeta(_)
        | GSetMeta(_)
        | TwoPSetMeta(_)
        | TaskManagerMeta(_)
        | DirectoryMeta(_)
        | SequenceMeta(_)
        | TextMeta(_) ->
          Error(UnexpectedAck("or-set ack is missing its local message id"))
      }
    GSetState(kernel), GSetOp(op) ->
      case local {
        GSetMeta(message_id) ->
          case g_set_kernel.ack_local_with_message_id(kernel, op, message_id) {
            Ok(kernel) -> Ok(#(GSetState(kernel), [], None))
            Error(g_set_kernel.UnexpectedAck(detail))
            | Error(g_set_kernel.UnexpectedRollback(detail)) ->
              Error(UnexpectedAck(detail))
          }
        NoMeta
        | CounterMeta(_)
        | PnCounterMeta(_)
        | OrMapMeta(_)
        | OrSetMeta(_)
        | TwoPSetMeta(_)
        | TaskManagerMeta(_)
        | DirectoryMeta(_)
        | SequenceMeta(_)
        | TextMeta(_) ->
          Error(UnexpectedAck("g-set ack is missing its local message id"))
      }
    TwoPSetState(kernel), TwoPSetOp(op) ->
      case local {
        TwoPSetMeta(message_id) ->
          case
            two_p_set_kernel.ack_local_with_message_id(kernel, op, message_id)
          {
            Ok(kernel) -> Ok(#(TwoPSetState(kernel), [], None))
            Error(two_p_set_kernel.UnexpectedAck(detail))
            | Error(two_p_set_kernel.UnexpectedRollback(detail)) ->
              Error(UnexpectedAck(detail))
          }
        NoMeta
        | CounterMeta(_)
        | PnCounterMeta(_)
        | OrMapMeta(_)
        | OrSetMeta(_)
        | GSetMeta(_)
        | TaskManagerMeta(_)
        | DirectoryMeta(_)
        | SequenceMeta(_)
        | TextMeta(_) ->
          Error(UnexpectedAck("two-p-set ack is missing its local message id"))
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
    TaskManagerState(kernel), TaskManagerOp(op) ->
      case local {
        TaskManagerMeta(message_id) ->
          case
            task_manager_kernel.ack_local(
              kernel,
              op,
              meta.self,
              message_id,
              meta.quorum,
            )
          {
            Ok(#(kernel, events)) ->
              Ok(#(
                TaskManagerState(kernel),
                list.map(events, TaskManagerEvent),
                None,
              ))
            Error(task_manager_kernel.UnexpectedAck(_, detail))
            | Error(task_manager_kernel.UnexpectedRollback(_, detail))
            | Error(task_manager_kernel.UnexpectedResubmit(_, detail))
            | Error(task_manager_kernel.NotAssigned(detail)) ->
              Error(UnexpectedAck(detail))
          }
        _ ->
          Error(UnexpectedAck(
            "task-manager ack is missing its local message id",
          ))
      }
    JsonOtState(kernel), JsonOtOp(op) ->
      case json_ot_kernel.ack_local(kernel, op, meta.seq, meta.min_seq) {
        Ok(#(kernel, events)) ->
          Ok(#(JsonOtState(kernel), list.map(events, JsonOtEvent), None))
        Error(json_ot_kernel.UnexpectedAck(detail)) ->
          Error(UnexpectedAck(detail))
        Error(json_ot_kernel.OtFailure(err)) ->
          Error(CorruptRemoteOp(json_ot_error_detail(err)))
      }
    DirectoryState(kernel), DirectoryOp(op, message_id) ->
      case local {
        DirectoryMeta(_) ->
          case
            directory_kernel.ack_local(
              kernel,
              op,
              directory_sequenced_meta(meta, message_id),
            )
          {
            Ok(kernel) -> Ok(#(DirectoryState(kernel), [], None))
            Error(err) -> Error(UnexpectedAck(directory_error_detail(err)))
          }
        _ -> Error(UnexpectedAck("directory ack is missing its local metadata"))
      }
    OrderedCollectionState(kernel), OrderedCollectionOp(op) -> {
      // The queue kernel is non-optimistic: the own op takes effect here, on
      // ack. An `Acquire` yields the acquired item, but it is surfaced through
      // the `Acquired` event (the caller subscribes), so the outcome is dropped.
      let #(kernel, events, _outcome) =
        ordered_collection_kernel.ack_local(kernel, op, meta.self)
      Ok(#(
        OrderedCollectionState(kernel),
        list.map(events, OrderedCollectionEvent),
        None,
      ))
    }
    SequenceState(kernel), SequenceOp(op) ->
      case local {
        SequenceMeta(message_id) ->
          case
            sequence_kernel.ack_local_with_message_id(kernel, op, message_id)
          {
            Ok(kernel) -> Ok(#(SequenceState(kernel), [], None))
            Error(sequence_kernel.UnexpectedAck(detail))
            | Error(sequence_kernel.UnexpectedRollback(detail)) ->
              Error(UnexpectedAck(detail))
          }
        _ ->
          Error(UnexpectedAck("sequence ack is missing its local message id"))
      }
    RichTextState(kernel), RichTextOp(op) ->
      case rich_text_kernel.ack_local(kernel, op, meta.seq, meta.min_seq) {
        Ok(#(kernel, events)) ->
          Ok(#(RichTextState(kernel), list.map(events, RichTextEvent), None))
        Error(rich_text_kernel.UnexpectedAck(detail)) ->
          Error(UnexpectedAck(detail))
        Error(rich_text_kernel.RichTextFailure(err)) ->
          Error(CorruptRemoteOp(rich_text_error_detail(err)))
      }
    TextState(kernel), TextOp(op) ->
      case local {
        TextMeta(message_id) ->
          case text_kernel.ack_local_with_message_id(kernel, op, message_id) {
            Ok(kernel) -> Ok(#(TextState(kernel), [], None))
            Error(text_kernel.UnexpectedAck(detail))
            | Error(text_kernel.UnexpectedRollback(detail)) ->
              Error(UnexpectedAck(detail))
          }
        _ -> Error(UnexpectedAck("text ack is missing its local message id"))
      }
    state, _ -> Error(wrong_channel_type(state, "local ack"))
  }
}

/// A human-readable detail string for a json0 pure-algebra failure, for
/// wrapping in a `ChannelError`.
fn json_ot_error_detail(err: json_ot.OtError) -> String {
  case err {
    json_ot.BadPath(detail) -> "json0 bad path: " <> detail
    json_ot.BadValue(detail) -> "json0 bad value: " <> detail
    json_ot.UnknownSubtype(name) -> "json0 unknown subtype: " <> name
  }
}

/// A human-readable detail string for a rich-text pure-algebra failure, for
/// wrapping in a `ChannelError`.
fn rich_text_error_detail(err: rich_text.Error) -> String {
  case err {
    rich_text.Malformed(component, reason) ->
      "rich-text malformed " <> component <> ": " <> reason
    rich_text.InvalidApply(reason) -> "rich-text invalid apply: " <> reason
    rich_text.InvalidBoundary(offset) ->
      "rich-text invalid boundary at offset " <> int.to_string(offset)
  }
}

/// Drain an op the kernel released onto the wire while an ack was ingested
/// (json0's single-in-flight buffer promotion). Only json0 channels produce
/// one; every other channel returns `None`.
pub fn take_outbound(
  state: ChannelState,
) -> #(ChannelState, Option(ChannelOp)) {
  case state {
    JsonOtState(kernel) -> {
      let #(kernel, out) = json_ot_kernel.take_outbound(kernel)
      #(JsonOtState(kernel), option.map(out, JsonOtOp))
    }
    RichTextState(kernel) -> {
      let #(kernel, out) = rich_text_kernel.take_outbound(kernel)
      #(RichTextState(kernel), option.map(out, RichTextOp))
    }
    _ -> #(state, None)
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
    PnCounterOp(pn_counter_kernel.Update(our_amount, our_delta)),
      PnCounterOp(pn_counter_kernel.Update(echoed_amount, echoed_delta))
    -> our_amount == echoed_amount && our_delta == echoed_delta
    OrMapOp(ours), OrMapOp(echoed) -> same_or_map_shape(ours, echoed)
    OrSetOp(ours), OrSetOp(echoed) -> same_or_set_shape(ours, echoed)
    GSetOp(ours), GSetOp(echoed) -> same_g_set_shape(ours, echoed)
    TwoPSetOp(ours), TwoPSetOp(echoed) -> same_two_p_set_shape(ours, echoed)
    RegisterCollectionOp(ours), RegisterCollectionOp(echoed) ->
      ours.key == echoed.key
      && ours.value == echoed.value
      && ours.ref_seq == echoed.ref_seq
    ClaimsOp(ours), ClaimsOp(echoed) ->
      ours.key == echoed.key
      && ours.value == echoed.value
      && ours.ref_seq == echoed.ref_seq
    TaskManagerOp(ours), TaskManagerOp(echoed) ->
      same_task_manager_shape(ours, echoed)
    PactMapOp(ours), PactMapOp(echoed) -> same_pact_map_shape(ours, echoed)
    JsonOtOp(ours), JsonOtOp(echoed) ->
      ours.ref_seq == echoed.ref_seq && ours.components == echoed.components
    DirectoryOp(ours, our_id), DirectoryOp(echoed, echoed_id) ->
      our_id == echoed_id && same_directory_shape(ours, echoed)
    OrderedCollectionOp(ours), OrderedCollectionOp(echoed) ->
      same_ordered_shape(ours, echoed)
    SequenceOp(ours), SequenceOp(echoed) -> same_sequence_shape(ours, echoed)
    RichTextOp(ours), RichTextOp(echoed) ->
      ours.ref_seq == echoed.ref_seq && ours.delta == echoed.delta
    TextOp(ours), TextOp(echoed) -> same_text_shape(ours, echoed)
    _, _ -> False
  }
}

fn same_sequence_shape(
  ours: sequence_kernel.SequenceOp,
  echoed: sequence_kernel.SequenceOp,
) -> Bool {
  case ours, echoed {
    sequence_kernel.Insert(i, value, delta),
      sequence_kernel.Insert(i2, value2, delta2)
    ->
      i == i2
      && same_json_value(value, value2)
      && same_sequence_delta(delta, delta2)
    sequence_kernel.Delete(i, delta), sequence_kernel.Delete(i2, delta2) ->
      i == i2 && same_sequence_delta(delta, delta2)
    sequence_kernel.Move(from, to, delta),
      sequence_kernel.Move(from2, to2, delta2)
    -> from == from2 && to == to2 && same_sequence_delta(delta, delta2)
    sequence_kernel.Replace(i, value, delta),
      sequence_kernel.Replace(i2, value2, delta2)
    ->
      i == i2
      && same_json_value(value, value2)
      && same_sequence_delta(delta, delta2)
    _, _ -> False
  }
}

fn same_sequence_delta(ours: Sequence(Json), echoed: Sequence(Json)) -> Bool {
  wire.json_semantically_equal(
    sequence.to_json(ours, fn(value) { value }),
    sequence.to_json(echoed, fn(value) { value }),
  )
}

/// Whether two text ops carry the same diagnostic shape (index/value
/// intent) *and* the same authoritative CRDT delta, mirroring
/// `same_sequence_shape`. The diagnostic fields alone would let a corrupted
/// or tampered delta slip past the FIFO ack-matching sanity check; comparing
/// the delta too preserves that tamper/corruption detection while still
/// treating a delta produced by honest reconnect/resubmit (which encodes to
/// the same canonical JSON) as equal.
fn same_text_shape(
  ours: text_kernel.TextOp,
  echoed: text_kernel.TextOp,
) -> Bool {
  case ours, echoed {
    text_kernel.Insert(i, value, delta), text_kernel.Insert(i2, value2, delta2)
    -> i == i2 && value == value2 && same_text_delta(delta, delta2)
    text_kernel.DeleteRange(s, e, delta),
      text_kernel.DeleteRange(s2, e2, delta2)
    -> s == s2 && e == e2 && same_text_delta(delta, delta2)
    text_kernel.ReplaceRange(s, e, value, delta),
      text_kernel.ReplaceRange(s2, e2, value2, delta2)
    -> s == s2 && e == e2 && value == value2 && same_text_delta(delta, delta2)
    text_kernel.Append(value, delta), text_kernel.Append(value2, delta2) ->
      value == value2 && same_text_delta(delta, delta2)
    _, _ -> False
  }
}

fn same_text_delta(ours: Text, echoed: Text) -> Bool {
  wire.json_semantically_equal(text.to_json(ours), text.to_json(echoed))
}

fn same_directory_shape(
  ours: directory_kernel.DirectoryOp,
  echoed: directory_kernel.DirectoryOp,
) -> Bool {
  case ours, echoed {
    directory_kernel.Set(p, k, _), directory_kernel.Set(p2, k2, _) ->
      p == p2 && k == k2
    directory_kernel.Delete(p, k), directory_kernel.Delete(p2, k2) ->
      p == p2 && k == k2
    directory_kernel.Clear(p), directory_kernel.Clear(p2) -> p == p2
    directory_kernel.CreateSubDirectory(p, n),
      directory_kernel.CreateSubDirectory(p2, n2)
    -> p == p2 && n == n2
    directory_kernel.DeleteSubDirectory(p, n),
      directory_kernel.DeleteSubDirectory(p2, n2)
    -> p == p2 && n == n2
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

fn same_g_set_shape(
  ours: g_set_kernel.GSetOp,
  echoed: g_set_kernel.GSetOp,
) -> Bool {
  case ours, echoed {
    g_set_kernel.Add(our_element, _), g_set_kernel.Add(echoed_element, _) ->
      our_element == echoed_element
  }
}

fn same_two_p_set_shape(
  ours: two_p_set_kernel.TwoPSetOp,
  echoed: two_p_set_kernel.TwoPSetOp,
) -> Bool {
  case ours, echoed {
    two_p_set_kernel.Add(our_element, _),
      two_p_set_kernel.Add(echoed_element, _)
    -> our_element == echoed_element
    two_p_set_kernel.Remove(our_element, _),
      two_p_set_kernel.Remove(echoed_element, _)
    -> our_element == echoed_element
    _, _ -> False
  }
}

fn same_task_manager_shape(
  ours: task_manager_kernel.TaskManagerOp,
  echoed: task_manager_kernel.TaskManagerOp,
) -> Bool {
  case ours, echoed {
    task_manager_kernel.Volunteer(our_task),
      task_manager_kernel.Volunteer(echoed_task)
    -> our_task == echoed_task
    task_manager_kernel.Abandon(our_task),
      task_manager_kernel.Abandon(echoed_task)
    -> our_task == echoed_task
    task_manager_kernel.Complete(our_task),
      task_manager_kernel.Complete(echoed_task)
    -> our_task == echoed_task
    _, _ -> False
  }
}

/// Whether a sequenced echo of our own attach carries the snapshot we
/// submitted (values compared structurally, not byte-wise).
pub fn same_snapshot(ours: Snapshot, echoed: Snapshot) -> Bool {
  case ours, echoed {
    MapSnapshot(ours), MapSnapshot(echoed) -> same_entries(ours, echoed)
    CounterSnapshot(ours), CounterSnapshot(echoed) -> ours == echoed
    PnCounterSnapshot(ours), PnCounterSnapshot(echoed) -> ours == echoed
    OrMapSnapshot(our_mode, ours), OrMapSnapshot(echoed_mode, echoed) ->
      our_mode == echoed_mode && ours == echoed
    OrSetSnapshot(ours), OrSetSnapshot(echoed) -> ours == echoed
    GSetSnapshot(ours), GSetSnapshot(echoed) -> ours == echoed
    TwoPSetSnapshot(ours), TwoPSetSnapshot(echoed) -> ours == echoed
    RegisterCollectionSnapshot(ours), RegisterCollectionSnapshot(echoed) ->
      ours == echoed
    ClaimsSnapshot(ours), ClaimsSnapshot(echoed) -> ours == echoed
    TaskManagerSnapshot(ours), TaskManagerSnapshot(echoed) -> ours == echoed
    PactMapSnapshot(ours), PactMapSnapshot(echoed) ->
      json.to_string(encode_pact_entries(ours))
      == json.to_string(encode_pact_entries(echoed))
    JsonOtSnapshot(ours), JsonOtSnapshot(echoed) -> ours == echoed
    DirectorySnapshot(ours), DirectorySnapshot(echoed) ->
      json.to_string(encode_directory_summary(ours))
      == json.to_string(encode_directory_summary(echoed))
    OrderedCollectionSnapshot(our_queue, our_jobs),
      OrderedCollectionSnapshot(echoed_queue, echoed_jobs)
    ->
      json.to_string(encode_ordered_snapshot(our_queue, our_jobs))
      == json.to_string(encode_ordered_snapshot(echoed_queue, echoed_jobs))
    SequenceSummary(ours), SequenceSummary(echoed) ->
      same_json_value(
        sequence.to_json(ours, fn(value) { value }),
        sequence.to_json(echoed, fn(value) { value }),
      )
    RichTextSnapshot(ours), RichTextSnapshot(echoed) -> ours == echoed
    TextSummary(ours), TextSummary(echoed) ->
      same_json_value(text.to_json(ours), text.to_json(echoed))
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
  wire.json_semantically_equal(ours, echoed)
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
    PnCounterState(_) -> []
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
    GSetState(_) -> []
    TwoPSetState(_) -> []
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
    TaskManagerState(_) -> []
    JsonOtState(_) -> []
    PactMapState(_) -> []
    // Directory handle serialization/GC is out of scope (see the kernel plan);
    // the demo stores plain values, so no handle addresses to collect.
    DirectoryState(_) -> []
    OrderedCollectionState(kernel) ->
      list.append(
        ordered_collection_kernel.summary_queue(kernel),
        list.map(ordered_collection_kernel.summary_jobs(kernel), fn(entry) {
          let #(_, ordered_collection_kernel.JobEntry(value, _)) = entry
          value
        }),
      )
      |> list.flat_map(handle.collect_handle_addresses)
      |> list.unique
    SequenceState(kernel) ->
      sequence_kernel.values(kernel)
      |> list.flat_map(handle.collect_handle_addresses)
      |> list.unique
    RichTextState(kernel) -> {
      let document = case rich_text_kernel.view(kernel) {
        Ok(document) -> document
        Error(_) -> rich_text_kernel.summary(kernel)
      }
      handle.collect_handle_addresses(rich_text.document_to_json(document))
    }
    // Text holds only graphemes, never nested DDS handles.
    TextState(_) -> []
  }
}

/// Encode a snapshot's type-dependent payload (the attach op's `snapshot`
/// field, the summary blob channel's `data` field).
pub fn encode_snapshot(snapshot: Snapshot) -> Json {
  case snapshot {
    MapSnapshot(entries) -> wire.encode_entries(entries)
    CounterSnapshot(value) -> json.int(value)
    PnCounterSnapshot(state) -> pn_counter.to_json(state)
    OrMapSnapshot(_, state) -> or_map.to_json(state)
    OrSetSnapshot(state) -> or_set.to_json(state)
    GSetSnapshot(state) -> g_set.to_json(state)
    TwoPSetSnapshot(state) -> two_p_set.to_json(state)
    RegisterCollectionSnapshot(registers) -> encode_registers(registers)
    ClaimsSnapshot(entries) -> encode_claims(entries)
    TaskManagerSnapshot(queues) -> encode_task_queues(queues)
    PactMapSnapshot(entries) -> encode_pact_entries(entries)
    JsonOtSnapshot(doc) -> json_ot.to_json(doc)
    DirectorySnapshot(summary) -> encode_directory_summary(summary)
    OrderedCollectionSnapshot(queue, jobs) ->
      encode_ordered_snapshot(queue, jobs)
    SequenceSummary(state) -> sequence.to_json(state, fn(value) { value })
    RichTextSnapshot(document) -> rich_text.document_to_json(document)
    TextSummary(state) -> text.to_json(state)
  }
}

/// Recursive JSON for a directory summary: each node carries its ordered
/// storage entries, create info, creator ids, detached flag, and named child
/// directories (in directory order).
fn encode_directory_summary(
  summary: directory_kernel.DirectorySummary,
) -> Json {
  json.object([
    #("storage", wire.encode_entries(summary.storage)),
    #("create", encode_create_info(summary.create)),
    #("creators", json.array(summary.creators, json.int)),
    #("detachedCreated", json.bool(summary.detached_created)),
    #(
      "subdirs",
      json.array(summary.subdirs, fn(entry) {
        json.object([
          #("name", json.string(entry.0)),
          #("dir", encode_directory_summary(entry.1)),
        ])
      }),
    ),
  ])
}

fn encode_create_info(create: directory_kernel.CreateInfo) -> Json {
  json.object([
    #("seq", json.int(create.seq)),
    #("clientSeq", json.int(create.client_seq)),
  ])
}

/// Decoder for a snapshot payload, selected by channel type (the field the
/// carrying envelope names the type in).
pub fn snapshot_decoder(channel_type: ChannelType) -> Decoder(Snapshot) {
  case channel_type {
    MapChannel -> decode.list(wire.entry_decoder()) |> decode.map(MapSnapshot)
    CounterChannel -> decode.int |> decode.map(CounterSnapshot)
    PnCounterChannel -> pn_counter_snapshot_decoder()
    OrMapChannel -> or_map_snapshot_decoder()
    OrSetChannel -> or_set_snapshot_decoder()
    GSetChannel -> g_set_snapshot_decoder()
    TwoPSetChannel -> two_p_set_snapshot_decoder()
    RegisterCollectionChannel ->
      decode.list(register_entry_decoder())
      |> decode.map(RegisterCollectionSnapshot)
    ClaimsChannel ->
      decode.list(claim_entry_decoder()) |> decode.map(ClaimsSnapshot)
    TaskManagerChannel ->
      decode.list(task_queue_decoder()) |> decode.map(TaskManagerSnapshot)
    PactMapChannel ->
      decode.list(pact_entry_decoder()) |> decode.map(PactMapSnapshot)
    JsonOtChannel -> json_ot.decoder() |> decode.map(JsonOtSnapshot)
    DirectoryChannel ->
      directory_summary_decoder() |> decode.map(DirectorySnapshot)
    OrderedCollectionChannel -> ordered_snapshot_decoder()
    SequenceChannel -> sequence_summary_decoder()
    RichTextChannel -> rich_text_snapshot_decoder()
    TextChannel -> text_summary_decoder()
  }
}

fn rich_text_snapshot_decoder() -> Decoder(Snapshot) {
  use value <- decode.then(json_ot.decoder())
  case rich_text.document_from_json(value) {
    Ok(document) -> decode.success(RichTextSnapshot(document))
    Error(_) -> decode.failure(MapSnapshot([]), "RichTextSnapshot")
  }
}

fn sequence_summary_decoder() -> Decoder(Snapshot) {
  use value <- decode.then(wire.json_value_decoder())
  let encoded = json.to_string(value)
  case sequence.from_json(encoded, wire.json_value_decoder()) {
    Ok(state) -> decode.success(SequenceSummary(state))
    Error(_) -> decode.failure(MapSnapshot([]), "SequenceSummary")
  }
}

fn text_summary_decoder() -> Decoder(Snapshot) {
  use value <- decode.then(wire.json_value_decoder())
  let encoded = json.to_string(value)
  case text.from_json(encoded) {
    Ok(state) -> decode.success(TextSummary(state))
    Error(_) -> decode.failure(MapSnapshot([]), "TextSummary")
  }
}

fn directory_summary_decoder() -> Decoder(directory_kernel.DirectorySummary) {
  use storage <- decode.field("storage", decode.list(wire.entry_decoder()))
  use create <- decode.field("create", create_info_decoder())
  use creators <- decode.field("creators", decode.list(decode.int))
  use detached_created <- decode.field("detachedCreated", decode.bool)
  use subdirs <- decode.field(
    "subdirs",
    decode.list(directory_subdir_decoder()),
  )
  decode.success(directory_kernel.DirectorySummary(
    storage: storage,
    create: create,
    creators: creators,
    detached_created: detached_created,
    subdirs: subdirs,
  ))
}

fn directory_subdir_decoder() -> Decoder(
  #(String, directory_kernel.DirectorySummary),
) {
  use name <- decode.field("name", decode.string)
  use dir <- decode.field("dir", decode.recursive(directory_summary_decoder))
  decode.success(#(name, dir))
}

fn create_info_decoder() -> Decoder(directory_kernel.CreateInfo) {
  use seq <- decode.field("seq", decode.int)
  use client_seq <- decode.field("clientSeq", decode.int)
  decode.success(directory_kernel.CreateInfo(seq: seq, client_seq: client_seq))
}

fn encode_task_queues(queues: List(#(String, List(Int)))) -> Json {
  json.array(queues, fn(entry) {
    let #(task_id, queue) = entry
    json.object([
      #("taskId", json.string(task_id)),
      #("queue", json.array(queue, json.int)),
    ])
  })
}

fn task_queue_decoder() -> Decoder(#(String, List(Int))) {
  use task_id <- decode.field("taskId", decode.string)
  use queue <- decode.field("queue", decode.list(decode.int))
  decode.success(#(task_id, queue))
}

fn same_pact_map_shape(
  ours: pact_map_kernel.PactMapOp,
  echoed: pact_map_kernel.PactMapOp,
) -> Bool {
  case ours, echoed {
    pact_map_kernel.Set(our_key, our_value, our_ref),
      pact_map_kernel.Set(echoed_key, echoed_value, echoed_ref)
    ->
      our_key == echoed_key
      && same_optional_json(our_value, echoed_value)
      && our_ref == echoed_ref
    pact_map_kernel.Accept(our_key), pact_map_kernel.Accept(echoed_key) ->
      our_key == echoed_key
    _, _ -> False
  }
}

fn same_optional_json(a: Option(Json), b: Option(Json)) -> Bool {
  json.to_string(encode_optional_value(a))
  == json.to_string(encode_optional_value(b))
}

fn same_ordered_shape(
  ours: ordered_collection_kernel.OrderedOp,
  echoed: ordered_collection_kernel.OrderedOp,
) -> Bool {
  case ours, echoed {
    ordered_collection_kernel.Add(our_value),
      ordered_collection_kernel.Add(echoed_value)
    -> same_json_value(our_value, echoed_value)
    ordered_collection_kernel.Acquire(our_id),
      ordered_collection_kernel.Acquire(echoed_id)
    -> our_id == echoed_id
    ordered_collection_kernel.Complete(our_id),
      ordered_collection_kernel.Complete(echoed_id)
    -> our_id == echoed_id
    ordered_collection_kernel.Release(our_id),
      ordered_collection_kernel.Release(echoed_id)
    -> our_id == echoed_id
    _, _ -> False
  }
}

fn encode_pact_entries(entries: List(#(String, pact_map_kernel.Pact))) -> Json {
  json.array(entries, fn(entry) {
    let #(key, pact) = entry
    json.object([#("key", json.string(key)), #("pact", encode_pact(pact))])
  })
}

fn encode_pact(pact: pact_map_kernel.Pact) -> Json {
  let pact_map_kernel.Pact(accepted, pending) = pact
  json.object([
    #("accepted", case accepted {
      Some(pact_map_kernel.Accepted(value, seq)) ->
        json.object([
          #("value", encode_optional_value(value)),
          #("sequenceNumber", json.int(seq)),
        ])
      None -> json.null()
    }),
    #("pending", case pending {
      Some(pact_map_kernel.Pending(value, signoffs)) ->
        json.object([
          #("value", encode_optional_value(value)),
          #("expectedSignoffs", json.array(signoffs, json.int)),
        ])
      None -> json.null()
    }),
  ])
}

/// A PactMap value is `Option(Json)`: `None` is a genuine tombstone, distinct
/// from `Some(null)`, so it gets its own `Absent` wire tag rather than a JSON
/// `null`.
fn encode_optional_value(value: Option(Json)) -> Json {
  case value {
    Some(inner) ->
      json.object([#("type", json.string("Plain")), #("value", inner)])
    None -> json.object([#("type", json.string("Absent"))])
  }
}

fn pact_entry_decoder() -> Decoder(#(String, pact_map_kernel.Pact)) {
  use key <- decode.field("key", decode.string)
  use pact <- decode.field("pact", pact_decoder())
  decode.success(#(key, pact))
}

fn pact_decoder() -> Decoder(pact_map_kernel.Pact) {
  use accepted <- decode.field("accepted", decode.optional(accepted_decoder()))
  use pending <- decode.field("pending", decode.optional(pending_decoder()))
  decode.success(pact_map_kernel.Pact(accepted, pending))
}

fn accepted_decoder() -> Decoder(pact_map_kernel.Accepted) {
  use value <- decode.field("value", optional_value_decoder())
  use seq <- decode.field("sequenceNumber", decode.int)
  decode.success(pact_map_kernel.Accepted(value, seq))
}

fn pending_decoder() -> Decoder(pact_map_kernel.Pending) {
  use value <- decode.field("value", optional_value_decoder())
  use signoffs <- decode.field("expectedSignoffs", decode.list(decode.int))
  decode.success(pact_map_kernel.Pending(value, signoffs))
}

fn optional_value_decoder() -> Decoder(Option(Json)) {
  use value_type <- decode.field("type", decode.string)
  case value_type {
    "Plain" ->
      decode.field("value", wire.json_value_decoder(), fn(inner) {
        decode.success(Some(inner))
      })
    "Absent" -> decode.success(None)
    _ -> decode.failure(None, "PactValue")
  }
}

/// `{queue: [value...], jobs: [{acquireId, value, owner}]}`. `owner` is an int
/// client id or `null` for a locally-acquired (unattached) job.
fn encode_ordered_snapshot(
  queue: List(Json),
  jobs: List(#(String, ordered_collection_kernel.JobEntry)),
) -> Json {
  json.object([
    #("queue", json.preprocessed_array(queue)),
    #(
      "jobs",
      json.array(jobs, fn(entry) {
        let #(acquire_id, ordered_collection_kernel.JobEntry(value, owner)) =
          entry
        json.object([
          #("acquireId", json.string(acquire_id)),
          #("value", value),
          #("owner", case owner {
            Some(id) -> json.int(id)
            None -> json.null()
          }),
        ])
      }),
    ),
  ])
}

fn ordered_snapshot_decoder() -> Decoder(Snapshot) {
  use queue <- decode.field("queue", decode.list(wire.json_value_decoder()))
  use jobs <- decode.field("jobs", decode.list(ordered_job_decoder()))
  decode.success(OrderedCollectionSnapshot(queue, jobs))
}

fn ordered_job_decoder() -> Decoder(
  #(String, ordered_collection_kernel.JobEntry),
) {
  use acquire_id <- decode.field("acquireId", decode.string)
  use value <- decode.field("value", wire.json_value_decoder())
  use owner <- decode.field("owner", decode.optional(decode.int))
  decode.success(#(acquire_id, ordered_collection_kernel.JobEntry(value, owner)))
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

fn pn_counter_snapshot_decoder() -> Decoder(Snapshot) {
  use value <- decode.then(wire.json_value_decoder())
  let encoded = json.to_string(value)
  case pn_counter.from_json(encoded) {
    Ok(state) -> decode.success(PnCounterSnapshot(state))
    Error(_) -> decode.failure(MapSnapshot([]), "PnCounterSnapshot")
  }
}

fn g_set_snapshot_decoder() -> Decoder(Snapshot) {
  use value <- decode.then(wire.json_value_decoder())
  let encoded = json.to_string(value)
  case g_set.from_json(encoded) {
    Ok(state) -> decode.success(GSetSnapshot(state))
    Error(_) -> decode.failure(MapSnapshot([]), "GSetSnapshot")
  }
}

fn two_p_set_snapshot_decoder() -> Decoder(Snapshot) {
  use value <- decode.then(wire.json_value_decoder())
  let encoded = json.to_string(value)
  case two_p_set.from_json(encoded) {
    Ok(state) -> decode.success(TwoPSetSnapshot(state))
    Error(_) -> decode.failure(MapSnapshot([]), "TwoPSetSnapshot")
  }
}
