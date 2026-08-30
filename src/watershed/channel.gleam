//// The closed sum of the channel kernels that the runtime can host, with the
//// dispatch in one module. There are parallel sums for the state, the
//// operations, the events, and the snapshots, with one dispatch function for
//// each operation that `runtime_core` needs.
////
//// The runtime routes everything through these sums, and it never names a
//// kernel directly. To add a kernel, add a variant to each sum here, and then
//// follow the compiler to every dispatch site. The compiler cannot point at
//// the sites that are not type-driven. Use this checklist for those:
//// - `wire/op`: add the wire codec for the channel operation.
//// - `channel`: extend the encode and decode of the summary payload, in
////   `encode_snapshot` and `snapshot_decoder`.
//// - `runtime_beam` and `runtime`: add the actor and runtime functions for the
////   edits and the reads.
//// - The fuzz model: extend the generators and the oracles for the behaviour of
////   the new channel.
////
//// A kernel stays pure and knows nothing about the runtime. This module wraps
//// the kernels only.

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

/// The kinds of channel that a document can host. `type_to_string` and
/// `string_to_type` convert between this type and the `channelType` strings
/// of the wire.
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

/// The parameters that create a channel. Most channel types need their channel
/// type only. An OR-map also needs its value mode.
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

pub fn string_to_type(raw: String) -> Result(ChannelType, Nil) {
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

/// Whether the merge behaviour of a channel is correct without a server
/// sequencer.
pub fn supports_p2p(channel_type: ChannelType) -> Bool {
  case channel_type {
    PnCounterChannel
    | OrMapChannel
    | OrSetChannel
    | GSetChannel
    | TwoPSetChannel
    | SequenceChannel
    | TextChannel -> True
    MapChannel
    | CounterChannel
    | RegisterCollectionChannel
    | ClaimsChannel
    | TaskManagerChannel
    | PactMapChannel
    | JsonOtChannel
    | DirectoryChannel
    | OrderedCollectionChannel
    | RichTextChannel -> False
  }
}

/// The kernel state of one channel.
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

/// A kernel operation as it goes through the runtime, in the in-flight queue
/// and in the ack matching, and over the wire, through `wire/op`.
pub type ChannelOperation {
  MapOperation(map_kernel.MapOperation)
  CounterOperation(counter_kernel.CounterOperation)
  PnCounterOperation(pn_counter_kernel.PnCounterOperation)
  OrMapOperation(or_map_kernel.OrMapOperation)
  OrSetOperation(or_set_kernel.OrSetOperation)
  GSetOperation(g_set_kernel.GSetOperation)
  TwoPSetOperation(two_p_set_kernel.TwoPSetOperation)
  RegisterCollectionOperation(register_collection_kernel.WriteOperation)
  ClaimsOperation(claims_kernel.ClaimOperation)
  TaskManagerOperation(task_manager_kernel.TaskManagerOperation)
  PactMapOperation(pact_map_kernel.PactMapOperation)
  JsonOtOperation(json_ot_kernel.JsonOtWireOperation)
  /// A directory operation with the kernel `message_id` value that identifies
  /// this submission. Unlike the other kernels, the id travels *in the
  /// operation*. A remote client needs the client-sequence identity of the
  /// author to run the stale-instance filter (D12) and the sibling order (D9).
  /// The csn of the runtime counts the operations of every channel together,
  /// and it would thus not equal the counter that the kernel keeps for each
  /// directory.
  DirectoryOperation(
    operation: directory_kernel.DirectoryOperation,
    message_id: Int,
  )
  OrderedCollectionOperation(ordered_collection_kernel.OrderedOperation)
  SequenceOperation(sequence_kernel.SequenceOperation)
  RichTextOperation(rich_text_kernel.RichTextWireOperation)
  TextOperation(text_kernel.TextOperation)
}

/// A local mutation for the ack-free p2p lifecycle. See `apply_p2p_local`.
/// There is one variant for each public mutation of every kernel that
/// `supports_p2p` accepts. This is the smallest closed sum that can express
/// them, and each variant carries the same parameters as the kernel function.
/// Only those seven kernels accept a `P2pEdit` value. Every other channel
/// refuses one with `UnsupportedP2p`.
pub type P2pEdit {
  PnCounterEdit(amount: Int)
  OrMapIncrementEdit(key: String, amount: Int)
  OrMapSetRegisterEdit(key: String, value: String, timestamp: Int)
  OrMapRemoveEdit(key: String)
  OrSetAddEdit(element: String)
  OrSetRemoveEdit(element: String)
  GSetAddEdit(element: String)
  TwoPSetAddEdit(element: String)
  TwoPSetRemoveEdit(element: String)
  SequenceInsertEdit(index: Int, value: Json)
  SequenceDeleteEdit(index: Int)
  SequenceMoveEdit(from_index: Int, to_index: Int)
  SequenceReplaceEdit(index: Int, value: Json)
  TextInsertEdit(index: Int, value: String)
  TextDeleteRangeEdit(start: Int, end: Int)
  TextReplaceRangeEdit(start: Int, end: Int, value: String)
  TextAppendEdit(value: String)
}

/// A kernel event. The runtime adds the address to it before the fan-out.
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

/// The state of a channel, in the form that the stored formats carry. Those
/// forms are the `snapshot` payload of the attach operation, and the `data`
/// payload of each channel in the summary blob.
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
  AcquireResolved(
    acquire_id: String,
    outcome: ordered_collection_kernel.AcquireOutcome,
  )
}

/// The *local* metadata of one kernel, which an in-flight operation carries
/// with the wire operation. Nothing serializes this metadata. A map operation
/// carries none. A counter checks the local message id that Fluid gives to each
/// pending increment.
pub type LocalOperationMeta {
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

/// The metadata that the sequencer assigns to a sequenced operation. The map
/// kernel and the counter kernel ignore it. A kernel that stores sequence
/// numbers reads `seq`. Every path passes this value, so a new kernel of that
/// kind needs no other change.
pub type SequencedMeta {
  SequencedMeta(
    seq: Int,
    last_seen_sn: Int,
    min_seq: Int,
    author: Int,
    self: Int,
    /// The set that a consensus proposal freezes its signoff list from. That
    /// set is the roster. On the live path it also contains this client and
    /// the author of the operation, which the runtime adds as a protection. To
    /// include too many clients is the safe direction here, because a signoff
    /// list without a connected client accepts too early.
    quorum: List(Int),
    /// The clients that are in the room at the sequence point of this
    /// operation. This is the roster itself, with no added clients.
    ///
    /// This field is separate from `quorum`, because the safe direction is the
    /// opposite one. A membership *test* that includes too many clients passes
    /// for a client that is not in the room, and it reports nothing.
    /// `TaskManager` uses this field to refuse a volunteer that is not a
    /// member. A lock queue thus stays a subset of the room, and the
    /// leave-driven release is thus complete.
    roster: List(Int),
    /// The reference sequence number of the author of the operation, which is
    /// what that client had seen at submit time. The stale-instance filter of
    /// the directory kernel (D12) reads it. The other kernels ignore it.
    /// `last_seen_sn` is the watermark of the *local* client, and you cannot
    /// use it in place of this field.
    reference_sequence_number: Int,
  )
}

pub type ChannelError {
  /// An ack did not agree with the pending queue of the kernel. This error is
  /// fatal. The runtime routed an ack for an operation that the kernel never
  /// submitted, or it routed the acks out of order.
  UnexpectedAck(detail: String)
  /// The runtime dispatched an operation to a channel of a different kernel
  /// type. This error is fatal. The decoder reads an operation against the
  /// registry type for its address, so a mismatch here is a routing fault, and
  /// not bad input.
  WrongChannelType(detail: String)
  CorruptRemoteOperation(detail: String)
  /// A `P2pEdit` value or an operation does not match the kernel of the
  /// channel, or that kernel does not support ack-free p2p at all. See
  /// `supports_p2p`.
  ///
  /// This error also covers a refusal at the edit level from a kernel that
  /// does support p2p, for example an OR-map mode mismatch, or a sequence or
  /// text edit that is out of bounds. The p2p path has no pending queue to
  /// protect, so those refusals arrive here, and not in an error type of that
  /// kernel.
  UnsupportedP2p(detail: String)
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

/// Build an empty channel for one client identity. The map kernel and the
/// counter kernel ignore `replica`. A kernel that is identified by replica uses
/// it as the local CRDT author. A reconnect keeps each existing channel state
/// under its original identity. A load from a summary or an attach calls
/// `from_snapshot` with the current id of the joining client, so that client
/// writes the future deltas.
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
    InitJsonOt -> JsonOtState(json_ot_kernel.new())
    InitDirectory -> DirectoryState(directory_kernel.new())
    InitOrderedCollection ->
      OrderedCollectionState(ordered_collection_kernel.new())
    InitSequence -> SequenceState(sequence_kernel.new(replica_id.new(replica)))
    InitRichText -> RichTextState(rich_text_kernel.new())
    InitText -> TextState(text_kernel.new(replica_id.new(replica)))
  }
}

/// Build a channel again from a stored snapshot, with the behaviour of
/// `from_sequenced`. The contents of the snapshot become the confirmed state,
/// and nothing is pending.
///
/// The error arm reports an OR-map snapshot whose value mode does not agree
/// with the mode that the snapshot names. Every other channel kind always
/// succeeds.
pub fn from_snapshot(
  snapshot: Snapshot,
  replica replica: String,
) -> Result(ChannelState, String) {
  case snapshot {
    MapSnapshot(entries) -> Ok(MapState(map_kernel.from_sequenced(entries)))
    CounterSnapshot(value) ->
      Ok(CounterState(counter_kernel.from_summary(value)))
    PnCounterSnapshot(state) ->
      Ok(
        PnCounterState(pn_counter_kernel.from_sequenced(
          state,
          replica_id.new(replica),
        )),
      )
    OrMapSnapshot(mode, state) ->
      case or_map_kernel.from_sequenced(state, mode, replica_id.new(replica)) {
        Ok(kernel) -> Ok(OrMapState(kernel))
        Error(error) -> Error(or_map_kernel_error_detail(error))
      }
    OrSetSnapshot(state) ->
      Ok(
        OrSetState(or_set_kernel.from_sequenced(state, replica_id.new(replica))),
      )
    GSetSnapshot(state) -> Ok(GSetState(g_set_kernel.from_sequenced(state)))
    TwoPSetSnapshot(state) ->
      Ok(TwoPSetState(two_p_set_kernel.from_sequenced(state)))
    RegisterCollectionSnapshot(registers) ->
      Ok(
        RegisterCollectionState(register_collection_kernel.from_summary(
          registers,
        )),
      )
    ClaimsSnapshot(entries) ->
      Ok(ClaimsState(claims_kernel.from_summary(entries)))
    TaskManagerSnapshot(queues) ->
      Ok(TaskManagerState(task_manager_kernel.from_summary(queues)))
    PactMapSnapshot(entries) ->
      Ok(PactMapState(pact_map_kernel.from_summary(entries)))
    JsonOtSnapshot(doc) -> Ok(JsonOtState(json_ot_kernel.from_summary(doc)))
    DirectorySnapshot(summary) ->
      Ok(DirectoryState(directory_kernel.from_summary(summary)))
    OrderedCollectionSnapshot(queue, jobs) ->
      Ok(
        OrderedCollectionState(ordered_collection_kernel.from_summary(
          queue,
          jobs,
        )),
      )
    SequenceSummary(state) ->
      Ok(
        SequenceState(sequence_kernel.from_sequenced(
          state,
          replica_id.new(replica),
        )),
      )
    RichTextSnapshot(document) ->
      Ok(RichTextState(rich_text_kernel.from_summary(document)))
    TextSummary(state) ->
      Ok(TextState(text_kernel.from_sequenced(state, replica_id.new(replica))))
  }
}

/// The detail text of an or-map kernel error, for a caller that reports a
/// String.
fn or_map_kernel_error_detail(error: or_map_kernel.KernelError) -> String {
  case error {
    or_map_kernel.UnexpectedAck(detail)
    | or_map_kernel.UnexpectedRollback(detail)
    | or_map_kernel.ModeMismatch(detail)
    | or_map_kernel.CorruptDelta(detail)
    | or_map_kernel.NegativeTally(detail) -> detail
  }
}

/// The confirmed state, which contains the sequenced data only, as a summary
/// captures it.
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

/// The value of the counter kernel is optimistic, because it contains the
/// pending increments. Subtract the amounts that have no ack, for the view of
/// the sequenced data only.
fn counter_sequenced_value(kernel: counter_kernel.CounterState) -> Int {
  list.fold(kernel.pending, kernel.value, fn(value, pending) {
    value - pending.increment_amount
  })
}

/// The current optimistic view, as an attach operation captures it. Every local
/// edit of a detached channel is pending, so this function must include them,
/// and `snapshot` does not.
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
    MapState(_)
    | CounterState(_)
    | PnCounterState(_)
    | RegisterCollectionState(_)
    | ClaimsState(_)
    | TaskManagerState(_)
    | PactMapState(_)
    | JsonOtState(_)
    | DirectoryState(_)
    | OrderedCollectionState(_)
    | RichTextState(_) ->
      case from_snapshot(attach_snapshot(state), replica: replica) {
        Ok(attached) -> attached
        // The snapshot comes from `state` itself, so its value mode always
        // agrees. The arm keeps the state as it is, because a channel must
        // not panic.
        Error(_) -> state
      }
  }
}

/// Apply a sequenced operation from another client.
///
/// The function returns the new state, the events that it produced, and the
/// follow-up operations that the kernel *owes*. The runtime submits an owed
/// operation by itself, with a new CSN and a new in-flight entry, in reaction
/// to this operation. For example, a consensus kernel emits its own `Accept`
/// operation after it reads a `Set` operation from a peer. Most kernels owe
/// nothing and return an empty list. The runtime buffers the owed operations of
/// each channel, and it sends them after the current sequenced batch. See
/// `runtime_core.collect_released_operations`.
pub fn apply_remote(
  state: ChannelState,
  operation: ChannelOperation,
  meta: SequencedMeta,
) -> Result(
  #(ChannelState, List(ChannelEvent), List(ChannelOperation)),
  ChannelError,
) {
  case state, operation {
    MapState(kernel), MapOperation(operation) -> {
      let #(kernel, events) = map_kernel.apply_remote(kernel, operation)
      Ok(#(MapState(kernel), list.map(events, MapEvent), []))
    }
    CounterState(kernel), CounterOperation(operation) -> {
      let #(kernel, events) = counter_kernel.apply_remote(kernel, operation)
      Ok(#(CounterState(kernel), list.map(events, CounterEvent), []))
    }
    PnCounterState(kernel), PnCounterOperation(operation) -> {
      let #(kernel, events) = pn_counter_kernel.apply_remote(kernel, operation)
      Ok(#(PnCounterState(kernel), list.map(events, PnCounterEvent), []))
    }
    OrMapState(kernel), OrMapOperation(operation) ->
      case or_map_kernel.apply_remote(kernel, operation) {
        Ok(#(kernel, events)) ->
          Ok(#(OrMapState(kernel), list.map(events, OrMapEvent), []))
        Error(or_map_kernel.CorruptDelta(detail))
        | Error(or_map_kernel.ModeMismatch(detail))
        | Error(or_map_kernel.NegativeTally(detail)) ->
          Error(CorruptRemoteOperation(detail))
        Error(or_map_kernel.UnexpectedAck(detail))
        | Error(or_map_kernel.UnexpectedRollback(detail)) ->
          Error(UnexpectedAck(detail))
      }
    OrSetState(kernel), OrSetOperation(operation) -> {
      let #(kernel, events) = or_set_kernel.apply_remote(kernel, operation)
      Ok(#(OrSetState(kernel), list.map(events, OrSetEvent), []))
    }
    GSetState(kernel), GSetOperation(operation) -> {
      let #(kernel, events) = g_set_kernel.apply_remote(kernel, operation)
      Ok(#(GSetState(kernel), list.map(events, GSetEvent), []))
    }
    TwoPSetState(kernel), TwoPSetOperation(operation) -> {
      let #(kernel, events) = two_p_set_kernel.apply_remote(kernel, operation)
      Ok(#(TwoPSetState(kernel), list.map(events, TwoPSetEvent), []))
    }
    RegisterCollectionState(kernel), RegisterCollectionOperation(operation) -> {
      let #(kernel, events) =
        register_collection_kernel.apply_remote(kernel, operation, meta.seq)
      Ok(
        #(
          RegisterCollectionState(kernel),
          list.map(events, RegisterCollectionEvent),
          [],
        ),
      )
    }
    ClaimsState(kernel), ClaimsOperation(operation) -> {
      let #(kernel, events) =
        claims_kernel.apply_remote(kernel, operation, meta.seq)
      Ok(#(ClaimsState(kernel), list.map(events, ClaimsEvent), []))
    }
    TaskManagerState(kernel), TaskManagerOperation(operation) -> {
      let #(kernel, events) =
        task_manager_kernel.apply_remote(
          kernel,
          operation,
          meta.author,
          meta.roster,
        )
      Ok(#(TaskManagerState(kernel), list.map(events, TaskManagerEvent), []))
    }
    PactMapState(kernel), PactMapOperation(operation) ->
      apply_pact_map(kernel, operation, meta)
    JsonOtState(kernel), JsonOtOperation(operation) ->
      case
        json_ot_kernel.apply_remote(kernel, operation, meta.seq, meta.min_seq)
      {
        Ok(#(kernel, events)) ->
          Ok(#(JsonOtState(kernel), list.map(events, JsonOtEvent), []))
        Error(json_ot_kernel.UnexpectedAck(detail)) ->
          Error(UnexpectedAck(detail))
        Error(json_ot_kernel.OtFailure(error)) ->
          Error(CorruptRemoteOperation(json_ot_error_detail(error)))
      }
    DirectoryState(kernel), DirectoryOperation(operation, message_id) -> {
      let #(kernel, events) =
        directory_kernel.apply_remote(
          kernel,
          operation,
          directory_sequenced_meta(meta, message_id),
          meta.self,
        )
      Ok(#(DirectoryState(kernel), list.map(events, DirectoryEvent), []))
    }
    OrderedCollectionState(kernel), OrderedCollectionOperation(operation) -> {
      let #(kernel, events) =
        ordered_collection_kernel.apply_remote(kernel, operation, meta.author)
      Ok(
        #(
          OrderedCollectionState(kernel),
          list.map(events, OrderedCollectionEvent),
          [],
        ),
      )
    }
    SequenceState(kernel), SequenceOperation(operation) -> {
      let #(kernel, events) = sequence_kernel.apply_remote(kernel, operation)
      Ok(#(SequenceState(kernel), list.map(events, SequenceEvent), []))
    }
    RichTextState(kernel), RichTextOperation(operation) ->
      case
        rich_text_kernel.apply_remote(kernel, operation, meta.seq, meta.min_seq)
      {
        Ok(#(kernel, events)) ->
          Ok(#(RichTextState(kernel), list.map(events, RichTextEvent), []))
        Error(rich_text_kernel.UnexpectedAck(detail)) ->
          Error(UnexpectedAck(detail))
        Error(rich_text_kernel.RichTextFailure(error)) ->
          Error(CorruptRemoteOperation(rich_text_error_detail(error)))
      }
    TextState(kernel), TextOperation(operation) -> {
      let #(kernel, events) = text_kernel.apply_remote(kernel, operation)
      Ok(#(TextState(kernel), list.map(events, TextEvent), []))
    }
    MapState(_), _
    | CounterState(_), _
    | PnCounterState(_), _
    | OrMapState(_), _
    | OrSetState(_), _
    | GSetState(_), _
    | TwoPSetState(_), _
    | RegisterCollectionState(_), _
    | ClaimsState(_), _
    | TaskManagerState(_), _
    | PactMapState(_), _
    | JsonOtState(_), _
    | DirectoryState(_), _
    | OrderedCollectionState(_), _
    | SequenceState(_), _
    | RichTextState(_), _
    | TextState(_), _
    -> Error(wrong_channel_type(state, "remote op"))
  }
}

/// Apply a sequenced PactMap operation. A `Set` operation goes to `apply_set`,
/// which can owe an `Accept` operation when this client is a signoff. An
/// `Accept` operation goes to `apply_accept`. A local operation and a remote
/// operation both take this path, and the runtime uses `is_own_operation` only
/// to reclaim the in-flight entry. The PactMap of FluidFramework applies an
/// operation at its sequence point, whoever wrote it.
fn apply_pact_map(
  kernel: pact_map_kernel.PactMapState,
  operation: pact_map_kernel.PactMapOperation,
  meta: SequencedMeta,
) -> Result(
  #(ChannelState, List(ChannelEvent), List(ChannelOperation)),
  ChannelError,
) {
  case operation {
    pact_map_kernel.Set(_, _, _) -> {
      let #(kernel, events, reaction) =
        pact_map_kernel.apply_set(
          kernel,
          operation,
          meta.seq,
          meta.quorum,
          meta.self,
        )
      Ok(#(
        PactMapState(kernel),
        list.map(events, PactMapEvent),
        pact_map_reaction_operations(reaction),
      ))
    }
    pact_map_kernel.Accept(key) ->
      case pact_map_kernel.apply_accept(kernel, key, meta.author, meta.seq) {
        Ok(#(kernel, events)) ->
          Ok(#(PactMapState(kernel), list.map(events, PactMapEvent), []))
        Error(pact_map_kernel.UnexpectedAccept(_, _, detail)) ->
          Error(CorruptRemoteOperation(detail))
      }
  }
}

/// The reaction to a PactMap `Set` operation, as an owed operation at the
/// channel level. The runtime submits it by itself.
fn pact_map_reaction_operations(
  reaction: pact_map_kernel.SetReaction,
) -> List(ChannelOperation) {
  case reaction {
    pact_map_kernel.OweAccept(operation) -> [PactMapOperation(operation)]
    pact_map_kernel.NoReaction -> []
  }
}

/// Whether a channel applies its *own* sequenced operations through
/// `apply_remote`, which is the path of a remote operation, and not through the
/// optimistic `ack_local`. A consensus kernel, such as PactMap, takes effect at
/// the sequence point only, whoever wrote the operation. The runtime thus
/// reclaims the in-flight entry and then applies the operation with
/// `apply_remote`. Every optimistic kernel returns `False` and acks the
/// operation locally.
pub fn applies_own_on_sequence(state: ChannelState) -> Bool {
  case state {
    PactMapState(_) -> True
    MapState(_)
    | CounterState(_)
    | PnCounterState(_)
    | OrMapState(_)
    | OrSetState(_)
    | GSetState(_)
    | TwoPSetState(_)
    | RegisterCollectionState(_)
    | ClaimsState(_)
    | TaskManagerState(_)
    | JsonOtState(_)
    | DirectoryState(_)
    | OrderedCollectionState(_)
    | SequenceState(_)
    | RichTextState(_)
    | TextState(_) -> False
  }
}

/// Apply a sequenced membership leave to a channel. The named client left the
/// collaboration session at `leave_seq`.
///
/// A consensus kernel or a queue kernel that tracks state for each client
/// settles that state deterministically. PactMap removes the outstanding
/// signoffs of that client, so a pending value that waits on it can settle.
/// ConsensusOrderedCollection returns the jobs of that client to the queue.
/// TaskManager removes that client from every task queue. A kernel with no
/// membership behaviour does nothing. The runtime calls this function on every
/// attached channel when it receives a `"leave"` system message.
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
    MapState(_)
    | CounterState(_)
    | PnCounterState(_)
    | OrMapState(_)
    | OrSetState(_)
    | GSetState(_)
    | TwoPSetState(_)
    | RegisterCollectionState(_)
    | ClaimsState(_)
    | JsonOtState(_)
    | DirectoryState(_)
    | SequenceState(_)
    | RichTextState(_)
    | TextState(_) -> #(state, [])
  }
}

/// Build the `SequencedMeta` value of the directory kernel, from the metadata
/// at the channel level and the kernel `message_id` of the operation, which is
/// its client-sequence identity.
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

fn directory_error_detail(error: directory_kernel.KernelError) -> String {
  case error {
    directory_kernel.UnexpectedAck(_, detail) -> "directory ack: " <> detail
    directory_kernel.UnexpectedRollback(_, detail) ->
      "directory rollback: " <> detail
    directory_kernel.PathNotFound(path) -> "directory path not found: " <> path
    directory_kernel.InvalidName(name) -> "directory invalid name: " <> name
    directory_kernel.InvariantViolation(detail) ->
      "directory invariant: " <> detail
  }
}

/// Commit an acked local operation, which moves it from `pending` to
/// `sequenced`.
pub fn ack_local(
  state: ChannelState,
  operation: ChannelOperation,
  local: LocalOperationMeta,
  meta: SequencedMeta,
) -> Result(
  #(ChannelState, List(ChannelEvent), Option(Resolution)),
  ChannelError,
) {
  case state, operation {
    MapState(kernel), MapOperation(operation) ->
      case map_kernel.ack_local(kernel, operation) {
        Ok(kernel) -> Ok(#(MapState(kernel), [], None))
        Error(map_kernel.UnexpectedAck(_, detail)) ->
          Error(UnexpectedAck(detail))
      }
    CounterState(kernel), CounterOperation(operation) ->
      case local {
        CounterMeta(message_id) ->
          case
            counter_kernel.ack_local_with_message_id(
              kernel,
              operation,
              message_id,
            )
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
    PnCounterState(kernel), PnCounterOperation(operation) ->
      case local {
        PnCounterMeta(message_id) ->
          case
            pn_counter_kernel.ack_local_with_message_id(
              kernel,
              operation,
              message_id,
            )
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
    OrMapState(kernel), OrMapOperation(operation) ->
      case local {
        OrMapMeta(message_id) ->
          case
            or_map_kernel.ack_local_with_message_id(
              kernel,
              operation,
              message_id,
            )
          {
            Ok(kernel) -> Ok(#(OrMapState(kernel), [], None))
            Error(or_map_kernel.UnexpectedAck(detail))
            | Error(or_map_kernel.UnexpectedRollback(detail)) ->
              Error(UnexpectedAck(detail))
            Error(or_map_kernel.ModeMismatch(detail))
            | Error(or_map_kernel.CorruptDelta(detail))
            | Error(or_map_kernel.NegativeTally(detail)) ->
              Error(CorruptRemoteOperation(detail))
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
    OrSetState(kernel), OrSetOperation(operation) ->
      case local {
        OrSetMeta(message_id) ->
          case
            or_set_kernel.ack_local_with_message_id(
              kernel,
              operation,
              message_id,
            )
          {
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
    GSetState(kernel), GSetOperation(operation) ->
      case local {
        GSetMeta(message_id) ->
          case
            g_set_kernel.ack_local_with_message_id(
              kernel,
              operation,
              message_id,
            )
          {
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
    TwoPSetState(kernel), TwoPSetOperation(operation) ->
      case local {
        TwoPSetMeta(message_id) ->
          case
            two_p_set_kernel.ack_local_with_message_id(
              kernel,
              operation,
              message_id,
            )
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
    RegisterCollectionState(kernel), RegisterCollectionOperation(operation) -> {
      let #(kernel, events, _is_winner) =
        register_collection_kernel.ack_local(kernel, operation, meta.seq)
      Ok(#(
        RegisterCollectionState(kernel),
        list.map(events, RegisterCollectionEvent),
        None,
      ))
    }
    ClaimsState(kernel), ClaimsOperation(operation) ->
      case claims_kernel.ack_local(kernel, operation, meta.seq) {
        Ok(#(kernel, events, outcome)) ->
          Ok(#(
            ClaimsState(kernel),
            list.map(events, ClaimsEvent),
            Some(ClaimResolved(operation.key, outcome)),
          ))
        Error(claims_kernel.UnexpectedAck(_, detail))
        | Error(claims_kernel.UnexpectedRollback(_, detail))
        | Error(claims_kernel.AlreadyPendingLocally(detail)) ->
          Error(UnexpectedAck(detail))
      }
    TaskManagerState(kernel), TaskManagerOperation(operation) ->
      case local {
        TaskManagerMeta(message_id) ->
          case
            task_manager_kernel.ack_local(
              kernel,
              operation,
              meta.self,
              message_id,
              meta.roster,
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
        NoMeta
        | CounterMeta(_)
        | PnCounterMeta(_)
        | OrMapMeta(_)
        | OrSetMeta(_)
        | GSetMeta(_)
        | TwoPSetMeta(_)
        | DirectoryMeta(_)
        | SequenceMeta(_)
        | TextMeta(_) ->
          Error(UnexpectedAck(
            "task-manager ack is missing its local message id",
          ))
      }
    JsonOtState(kernel), JsonOtOperation(operation) ->
      case json_ot_kernel.ack_local(kernel, operation, meta.seq, meta.min_seq) {
        Ok(#(kernel, events)) ->
          Ok(#(JsonOtState(kernel), list.map(events, JsonOtEvent), None))
        Error(json_ot_kernel.UnexpectedAck(detail)) ->
          Error(UnexpectedAck(detail))
        Error(json_ot_kernel.OtFailure(error)) ->
          Error(CorruptRemoteOperation(json_ot_error_detail(error)))
      }
    DirectoryState(kernel), DirectoryOperation(operation, message_id) ->
      case local {
        DirectoryMeta(_) ->
          case
            directory_kernel.ack_local(
              kernel,
              operation,
              directory_sequenced_meta(meta, message_id),
            )
          {
            Ok(kernel) -> Ok(#(DirectoryState(kernel), [], None))
            Error(error) -> Error(UnexpectedAck(directory_error_detail(error)))
          }
        NoMeta
        | CounterMeta(_)
        | PnCounterMeta(_)
        | OrMapMeta(_)
        | OrSetMeta(_)
        | GSetMeta(_)
        | TwoPSetMeta(_)
        | TaskManagerMeta(_)
        | SequenceMeta(_)
        | TextMeta(_) ->
          Error(UnexpectedAck("directory ack is missing its local metadata"))
      }
    OrderedCollectionState(kernel), OrderedCollectionOperation(operation) -> {
      // The queue kernel is non-optimistic: the own operation takes effect
      // here, on ack. An `Acquire` yields its outcome — won the head, or found
      // the queue empty — surfaced as an `AcquireResolved` resolution so the
      // submitting caller learns which, since a losing acquire emits no event.
      let #(kernel, events, outcome) =
        ordered_collection_kernel.ack_local(kernel, operation, meta.self)
      let resolution = case operation, outcome {
        ordered_collection_kernel.Acquire(acquire_id), Some(outcome) ->
          Some(AcquireResolved(acquire_id, outcome))
        ordered_collection_kernel.Acquire(_), None -> None
        ordered_collection_kernel.Add(_), _ -> None
        ordered_collection_kernel.Complete(_), _ -> None
        ordered_collection_kernel.Release(_), _ -> None
      }
      Ok(#(
        OrderedCollectionState(kernel),
        list.map(events, OrderedCollectionEvent),
        resolution,
      ))
    }
    SequenceState(kernel), SequenceOperation(operation) ->
      case local {
        SequenceMeta(message_id) ->
          case
            sequence_kernel.ack_local_with_message_id(
              kernel,
              operation,
              message_id,
            )
          {
            Ok(kernel) -> Ok(#(SequenceState(kernel), [], None))
            Error(sequence_kernel.UnexpectedAck(detail))
            | Error(sequence_kernel.UnexpectedRollback(detail)) ->
              Error(UnexpectedAck(detail))
          }
        NoMeta
        | CounterMeta(_)
        | PnCounterMeta(_)
        | OrMapMeta(_)
        | OrSetMeta(_)
        | GSetMeta(_)
        | TwoPSetMeta(_)
        | TaskManagerMeta(_)
        | DirectoryMeta(_)
        | TextMeta(_) ->
          Error(UnexpectedAck("sequence ack is missing its local message id"))
      }
    RichTextState(kernel), RichTextOperation(operation) ->
      case
        rich_text_kernel.ack_local(kernel, operation, meta.seq, meta.min_seq)
      {
        Ok(#(kernel, events)) ->
          Ok(#(RichTextState(kernel), list.map(events, RichTextEvent), None))
        Error(rich_text_kernel.UnexpectedAck(detail)) ->
          Error(UnexpectedAck(detail))
        Error(rich_text_kernel.RichTextFailure(error)) ->
          Error(CorruptRemoteOperation(rich_text_error_detail(error)))
      }
    TextState(kernel), TextOperation(operation) ->
      case local {
        TextMeta(message_id) ->
          case
            text_kernel.ack_local_with_message_id(kernel, operation, message_id)
          {
            Ok(kernel) -> Ok(#(TextState(kernel), [], None))
            Error(text_kernel.UnexpectedAck(detail))
            | Error(text_kernel.UnexpectedRollback(detail)) ->
              Error(UnexpectedAck(detail))
          }
        NoMeta
        | CounterMeta(_)
        | PnCounterMeta(_)
        | OrMapMeta(_)
        | OrSetMeta(_)
        | GSetMeta(_)
        | TwoPSetMeta(_)
        | TaskManagerMeta(_)
        | DirectoryMeta(_)
        | SequenceMeta(_) ->
          Error(UnexpectedAck("text ack is missing its local message id"))
      }
    MapState(_), _
    | CounterState(_), _
    | PnCounterState(_), _
    | OrMapState(_), _
    | OrSetState(_), _
    | GSetState(_), _
    | TwoPSetState(_), _
    | RegisterCollectionState(_), _
    | ClaimsState(_), _
    | TaskManagerState(_), _
    | PactMapState(_), _
    | JsonOtState(_), _
    | DirectoryState(_), _
    | OrderedCollectionState(_), _
    | SequenceState(_), _
    | RichTextState(_), _
    | TextState(_), _
    -> Error(wrong_channel_type(state, "local ack"))
  }
}

/// A detail string for a person to read, for a failure in the pure json0
/// algebra. The caller puts it in a `ChannelError` value.
fn json_ot_error_detail(error: json_ot.OtError) -> String {
  case error {
    json_ot.BadPath(detail) -> "json0 bad path: " <> detail
    json_ot.BadValue(detail) -> "json0 bad value: " <> detail
    json_ot.UnknownSubtype(name) -> "json0 unknown subtype: " <> name
  }
}

/// A detail string for a person to read, for a failure in the pure rich-text
/// algebra. The caller puts it in a `ChannelError` value.
fn rich_text_error_detail(error: rich_text.Error) -> String {
  case error {
    rich_text.Malformed(component, reason) ->
      "rich-text malformed " <> component <> ": " <> reason
    rich_text.InvalidApply(reason) -> "rich-text invalid apply: " <> reason
    rich_text.InvalidBoundary(offset) ->
      "rich-text invalid boundary at offset " <> int.to_string(offset)
  }
}

/// Write a local p2p edit and merge its delta into the confirmed state and the
/// visible state, in one transition. There is no pending entry and no
/// acknowledgement.
///
/// The function accepts a channel that `supports_p2p` permits, with the
/// `P2pEdit` variant of that channel. Every other combination returns
/// `UnsupportedP2p`, and it never does nothing quietly. Those combinations are
/// a channel that p2p does not support, and an edit for a different kernel.
///
/// Every kernel that p2p supports has its own `p2p_*` function, which writes
/// its delta and merges that delta into `sequenced` and `optimistic` directly.
/// See `text_kernel.commit_p2p` for an example. No such path touches `pending`
/// or calls an `ack_local` function.
pub fn apply_p2p_local(
  state: ChannelState,
  edit: P2pEdit,
) -> Result(#(ChannelState, List(ChannelEvent), ChannelOperation), ChannelError) {
  case state, edit {
    PnCounterState(kernel), PnCounterEdit(amount) -> {
      let #(kernel, events, operation) =
        pn_counter_kernel.p2p_update(kernel, amount)
      Ok(#(
        PnCounterState(kernel),
        list.map(events, PnCounterEvent),
        PnCounterOperation(operation),
      ))
    }
    OrMapState(kernel), OrMapIncrementEdit(key, amount) ->
      case or_map_kernel.p2p_increment(kernel, key, amount) {
        Ok(#(kernel, events, operation)) ->
          Ok(#(
            OrMapState(kernel),
            list.map(events, OrMapEvent),
            OrMapOperation(operation),
          ))
        Error(error) -> Error(or_map_p2p_error(error))
      }
    OrMapState(kernel), OrMapSetRegisterEdit(key, value, timestamp) ->
      case or_map_kernel.p2p_set_register(kernel, key, value, timestamp) {
        Ok(#(kernel, events, operation)) ->
          Ok(#(
            OrMapState(kernel),
            list.map(events, OrMapEvent),
            OrMapOperation(operation),
          ))
        Error(error) -> Error(or_map_p2p_error(error))
      }
    OrMapState(kernel), OrMapRemoveEdit(key) ->
      case or_map_kernel.p2p_remove(kernel, key) {
        Ok(#(kernel, events, operation)) ->
          Ok(#(
            OrMapState(kernel),
            list.map(events, OrMapEvent),
            OrMapOperation(operation),
          ))
        Error(error) -> Error(or_map_p2p_error(error))
      }
    OrSetState(kernel), OrSetAddEdit(element) -> {
      let #(kernel, events, operation) = or_set_kernel.p2p_add(kernel, element)
      Ok(#(
        OrSetState(kernel),
        list.map(events, OrSetEvent),
        OrSetOperation(operation),
      ))
    }
    OrSetState(kernel), OrSetRemoveEdit(element) -> {
      let #(kernel, events, operation) =
        or_set_kernel.p2p_remove(kernel, element)
      Ok(#(
        OrSetState(kernel),
        list.map(events, OrSetEvent),
        OrSetOperation(operation),
      ))
    }
    GSetState(kernel), GSetAddEdit(element) -> {
      let #(kernel, events, operation) = g_set_kernel.p2p_add(kernel, element)
      Ok(#(
        GSetState(kernel),
        list.map(events, GSetEvent),
        GSetOperation(operation),
      ))
    }
    TwoPSetState(kernel), TwoPSetAddEdit(element) -> {
      let #(kernel, events, operation) =
        two_p_set_kernel.p2p_add(kernel, element)
      Ok(#(
        TwoPSetState(kernel),
        list.map(events, TwoPSetEvent),
        TwoPSetOperation(operation),
      ))
    }
    TwoPSetState(kernel), TwoPSetRemoveEdit(element) -> {
      let #(kernel, events, operation) =
        two_p_set_kernel.p2p_remove(kernel, element)
      Ok(#(
        TwoPSetState(kernel),
        list.map(events, TwoPSetEvent),
        TwoPSetOperation(operation),
      ))
    }
    SequenceState(kernel), SequenceInsertEdit(index, value) ->
      case sequence_kernel.p2p_insert(kernel, index, value) {
        Ok(#(kernel, events, operation)) ->
          Ok(#(
            SequenceState(kernel),
            list.map(events, SequenceEvent),
            SequenceOperation(operation),
          ))
        Error(error) -> Error(sequence_p2p_error(error))
      }
    SequenceState(kernel), SequenceDeleteEdit(index) ->
      case sequence_kernel.p2p_delete(kernel, index) {
        Ok(#(kernel, events, operation)) ->
          Ok(#(
            SequenceState(kernel),
            list.map(events, SequenceEvent),
            SequenceOperation(operation),
          ))
        Error(error) -> Error(sequence_p2p_error(error))
      }
    SequenceState(kernel), SequenceMoveEdit(from_index, to_index) ->
      case sequence_kernel.p2p_move(kernel, from_index, to_index) {
        Ok(#(kernel, events, operation)) ->
          Ok(#(
            SequenceState(kernel),
            list.map(events, SequenceEvent),
            SequenceOperation(operation),
          ))
        Error(error) -> Error(sequence_p2p_error(error))
      }
    SequenceState(kernel), SequenceReplaceEdit(index, value) ->
      case sequence_kernel.p2p_replace(kernel, index, value) {
        Ok(#(kernel, events, operation)) ->
          Ok(#(
            SequenceState(kernel),
            list.map(events, SequenceEvent),
            SequenceOperation(operation),
          ))
        Error(error) -> Error(sequence_p2p_error(error))
      }
    TextState(kernel), TextInsertEdit(index, value) ->
      case text_kernel.p2p_insert(kernel, index, value) {
        Ok(#(kernel, events, operation)) ->
          Ok(#(
            TextState(kernel),
            list.map(events, TextEvent),
            TextOperation(operation),
          ))
        Error(error) -> Error(text_p2p_error(error))
      }
    TextState(kernel), TextDeleteRangeEdit(start, end) ->
      case text_kernel.p2p_delete_range(kernel, start, end) {
        Ok(#(kernel, events, operation)) ->
          Ok(#(
            TextState(kernel),
            list.map(events, TextEvent),
            TextOperation(operation),
          ))
        Error(error) -> Error(text_p2p_error(error))
      }
    TextState(kernel), TextReplaceRangeEdit(start, end, value) ->
      case text_kernel.p2p_replace_range(kernel, start, end, value) {
        Ok(#(kernel, events, operation)) ->
          Ok(#(
            TextState(kernel),
            list.map(events, TextEvent),
            TextOperation(operation),
          ))
        Error(error) -> Error(text_p2p_error(error))
      }
    TextState(kernel), TextAppendEdit(value) -> {
      let #(kernel, events, operation) = text_kernel.p2p_append(kernel, value)
      Ok(#(
        TextState(kernel),
        list.map(events, TextEvent),
        TextOperation(operation),
      ))
    }
    MapState(_), _
    | CounterState(_), _
    | PnCounterState(_), _
    | OrMapState(_), _
    | OrSetState(_), _
    | GSetState(_), _
    | TwoPSetState(_), _
    | RegisterCollectionState(_), _
    | ClaimsState(_), _
    | TaskManagerState(_), _
    | PactMapState(_), _
    | JsonOtState(_), _
    | DirectoryState(_), _
    | OrderedCollectionState(_), _
    | SequenceState(_), _
    | RichTextState(_), _
    | TextState(_), _
    -> Error(unsupported_p2p(state, "local p2p edit"))
  }
}

/// Merge a remote p2p operation directly into the confirmed state and the
/// visible state. There is no sequence metadata, and there is no pending entry
/// to reclaim. This is the ack-free equivalent of `apply_remote`.
///
/// None of the seven kernels that p2p supports reads `SequencedMeta`, and none
/// of them owes a follow-up operation. This function thus calls `apply_remote`
/// with a zeroed metadata value, and it discards the list of owed operations.
/// Any other channel, and an operation that does not match the kernel of the
/// channel, returns `UnsupportedP2p`.
pub fn apply_p2p_remote(
  state: ChannelState,
  operation: ChannelOperation,
) -> Result(#(ChannelState, List(ChannelEvent)), ChannelError) {
  case supports_p2p(channel_type(state)) {
    False -> Error(unsupported_p2p(state, "remote p2p op"))
    True ->
      case apply_remote(state, operation, zeroed_meta()) {
        Ok(#(state, events, _owed)) -> Ok(#(state, events))
        // A mismatched operation is bad p2p input here, not a runtime routing
        // bug.
        Error(WrongChannelType(_)) ->
          Error(unsupported_p2p(state, "remote p2p op"))
        Error(error) -> Error(error)
      }
  }
}

/// The metadata that `apply_remote` requires, for the p2p path, which has no
/// metadata. This value is safe, because every kernel that `supports_p2p`
/// permits ignores it.
fn zeroed_meta() -> SequencedMeta {
  SequencedMeta(
    seq: 0,
    last_seen_sn: 0,
    min_seq: 0,
    author: 0,
    self: 0,
    quorum: [],
    roster: [],
    reference_sequence_number: 0,
  )
}

/// Merge the whole channel snapshot of a peer into the state of this channel.
/// This is the full-state equivalent of `apply_p2p_remote`.
///
/// Every kernel that p2p supports merges the incoming CRDT state as a lattice
/// join, into the confirmed state and the visible state. A merge is thus
/// idempotent, and it never discards a winner or a local edit. A snapshot for
/// a different kernel, and a snapshot for a channel that does not support
/// ack-free p2p at all, both return `UnsupportedP2p`.
pub fn merge_p2p_snapshot(
  state: ChannelState,
  snapshot: Snapshot,
) -> Result(#(ChannelState, List(ChannelEvent)), ChannelError) {
  case state, snapshot {
    PnCounterState(kernel), PnCounterSnapshot(other) -> {
      let #(kernel, events) = pn_counter_kernel.p2p_merge(kernel, other)
      Ok(#(PnCounterState(kernel), list.map(events, PnCounterEvent)))
    }
    OrMapState(kernel), OrMapSnapshot(_, other) ->
      case or_map_kernel.p2p_merge(kernel, other) {
        Ok(#(kernel, events)) ->
          Ok(#(OrMapState(kernel), list.map(events, OrMapEvent)))
        Error(error) -> Error(or_map_p2p_error(error))
      }
    OrSetState(kernel), OrSetSnapshot(other) -> {
      let #(kernel, events) = or_set_kernel.p2p_merge(kernel, other)
      Ok(#(OrSetState(kernel), list.map(events, OrSetEvent)))
    }
    GSetState(kernel), GSetSnapshot(other) -> {
      let #(kernel, events) = g_set_kernel.p2p_merge(kernel, other)
      Ok(#(GSetState(kernel), list.map(events, GSetEvent)))
    }
    TwoPSetState(kernel), TwoPSetSnapshot(other) -> {
      let #(kernel, events) = two_p_set_kernel.p2p_merge(kernel, other)
      Ok(#(TwoPSetState(kernel), list.map(events, TwoPSetEvent)))
    }
    SequenceState(kernel), SequenceSummary(other) -> {
      let #(kernel, events) = sequence_kernel.p2p_merge(kernel, other)
      Ok(#(SequenceState(kernel), list.map(events, SequenceEvent)))
    }
    TextState(kernel), TextSummary(other) -> {
      let #(kernel, events) = text_kernel.p2p_merge(kernel, other)
      Ok(#(TextState(kernel), list.map(events, TextEvent)))
    }
    MapState(_), _
    | CounterState(_), _
    | PnCounterState(_), _
    | OrMapState(_), _
    | OrSetState(_), _
    | GSetState(_), _
    | TwoPSetState(_), _
    | RegisterCollectionState(_), _
    | ClaimsState(_), _
    | TaskManagerState(_), _
    | PactMapState(_), _
    | JsonOtState(_), _
    | DirectoryState(_), _
    | OrderedCollectionState(_), _
    | SequenceState(_), _
    | RichTextState(_), _
    | TextState(_), _
    -> Error(unsupported_p2p(state, "remote p2p snapshot"))
  }
}

/// Convert an error of the or-map kernel into a `ChannelError` value, for the
/// p2p paths. A mode mismatch is a refusal at the p2p level, because there is
/// no pending queue to protect. Every other error uses the same conversion as
/// the server-backed `apply_remote` and `ack_local` paths.
fn or_map_p2p_error(error: or_map_kernel.KernelError) -> ChannelError {
  case error {
    or_map_kernel.ModeMismatch(detail) -> UnsupportedP2p(detail)
    or_map_kernel.CorruptDelta(detail) | or_map_kernel.NegativeTally(detail) ->
      CorruptRemoteOperation(detail)
    or_map_kernel.UnexpectedAck(detail)
    | or_map_kernel.UnexpectedRollback(detail) -> UnexpectedAck(detail)
  }
}

fn sequence_p2p_error(error: sequence_kernel.EditError) -> ChannelError {
  UnsupportedP2p(sequence_kernel.edit_error_detail(error))
}

fn text_p2p_error(error: text_kernel.EditError) -> ChannelError {
  UnsupportedP2p(text_kernel.edit_error_detail(error))
}

fn unsupported_p2p(state: ChannelState, context: String) -> ChannelError {
  UnsupportedP2p(
    context
    <> " does not match the "
    <> type_to_string(channel_type(state))
    <> " channel it was routed to",
  )
}

/// Take an operation that the kernel released onto the wire while it processed
/// an ack. That operation comes from the one-operation-in-flight buffer
/// promotion of json0. A json0 channel produces such an operation. Every other
/// channel returns `None`.
pub fn take_outbound(
  state: ChannelState,
) -> #(ChannelState, Option(ChannelOperation)) {
  case state {
    JsonOtState(kernel) -> {
      let #(kernel, out) = json_ot_kernel.take_outbound(kernel)
      #(JsonOtState(kernel), option.map(out, JsonOtOperation))
    }
    RichTextState(kernel) -> {
      let #(kernel, out) = rich_text_kernel.take_outbound(kernel)
      #(RichTextState(kernel), option.map(out, RichTextOperation))
    }
    MapState(_)
    | CounterState(_)
    | PnCounterState(_)
    | OrMapState(_)
    | OrSetState(_)
    | GSetState(_)
    | TwoPSetState(_)
    | RegisterCollectionState(_)
    | ClaimsState(_)
    | TaskManagerState(_)
    | PactMapState(_)
    | DirectoryState(_)
    | OrderedCollectionState(_)
    | SequenceState(_)
    | TextState(_) -> #(state, None)
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

/// Whether the sequenced echo of a local operation has the shape that this
/// client submitted. This is the check on the FIFO ack matching.
pub fn same_shape(ours: ChannelOperation, echoed: ChannelOperation) -> Bool {
  case ours, echoed {
    MapOperation(ours), MapOperation(echoed) -> same_map_shape(ours, echoed)
    CounterOperation(counter_kernel.Increment(ours)),
      CounterOperation(counter_kernel.Increment(echoed))
    -> ours == echoed
    PnCounterOperation(pn_counter_kernel.Update(our_amount, our_delta)),
      PnCounterOperation(pn_counter_kernel.Update(echoed_amount, echoed_delta))
    -> our_amount == echoed_amount && our_delta == echoed_delta
    OrMapOperation(ours), OrMapOperation(echoed) ->
      same_or_map_shape(ours, echoed)
    OrSetOperation(ours), OrSetOperation(echoed) ->
      same_or_set_shape(ours, echoed)
    GSetOperation(ours), GSetOperation(echoed) -> same_g_set_shape(ours, echoed)
    TwoPSetOperation(ours), TwoPSetOperation(echoed) ->
      same_two_p_set_shape(ours, echoed)
    RegisterCollectionOperation(ours), RegisterCollectionOperation(echoed) ->
      ours.key == echoed.key
      && ours.value == echoed.value
      && ours.ref_seq == echoed.ref_seq
    ClaimsOperation(ours), ClaimsOperation(echoed) ->
      ours.key == echoed.key
      && ours.value == echoed.value
      && ours.ref_seq == echoed.ref_seq
    TaskManagerOperation(ours), TaskManagerOperation(echoed) ->
      same_task_manager_shape(ours, echoed)
    PactMapOperation(ours), PactMapOperation(echoed) ->
      same_pact_map_shape(ours, echoed)
    JsonOtOperation(ours), JsonOtOperation(echoed) ->
      ours.ref_seq == echoed.ref_seq && ours.components == echoed.components
    DirectoryOperation(ours, our_id), DirectoryOperation(echoed, echoed_id) ->
      our_id == echoed_id && same_directory_shape(ours, echoed)
    OrderedCollectionOperation(ours), OrderedCollectionOperation(echoed) ->
      same_ordered_shape(ours, echoed)
    SequenceOperation(ours), SequenceOperation(echoed) ->
      same_sequence_shape(ours, echoed)
    RichTextOperation(ours), RichTextOperation(echoed) ->
      ours.ref_seq == echoed.ref_seq && ours.delta == echoed.delta
    TextOperation(ours), TextOperation(echoed) -> same_text_shape(ours, echoed)
    MapOperation(_), _
    | CounterOperation(_), _
    | PnCounterOperation(_), _
    | OrMapOperation(_), _
    | OrSetOperation(_), _
    | GSetOperation(_), _
    | TwoPSetOperation(_), _
    | RegisterCollectionOperation(_), _
    | ClaimsOperation(_), _
    | TaskManagerOperation(_), _
    | PactMapOperation(_), _
    | JsonOtOperation(_), _
    | DirectoryOperation(_, _), _
    | OrderedCollectionOperation(_), _
    | SequenceOperation(_), _
    | RichTextOperation(_), _
    | TextOperation(_), _
    -> False
  }
}

fn same_sequence_shape(
  ours: sequence_kernel.SequenceOperation,
  echoed: sequence_kernel.SequenceOperation,
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
    sequence_kernel.Insert(_, _, _), _
    | sequence_kernel.Delete(_, _), _
    | sequence_kernel.Move(_, _, _), _
    | sequence_kernel.Replace(_, _, _), _
    -> False
  }
}

fn same_sequence_delta(ours: Sequence(Json), echoed: Sequence(Json)) -> Bool {
  wire.json_semantically_equal(
    sequence.to_json(ours, fn(value) { value }),
    sequence.to_json(echoed, fn(value) { value }),
  )
}

/// Whether two text operations carry the same diagnostic shape, which is the
/// index intent and the value intent, *and* the same authoritative CRDT delta.
/// The behaviour is the same as in `same_sequence_shape`.
///
/// The diagnostic fields alone would let a corrupt or changed delta pass the
/// check on the FIFO ack matching. The comparison of the delta keeps that
/// detection. It also treats a delta from a correct reconnect and resubmit as
/// equal, because that delta encodes to the same canonical JSON.
fn same_text_shape(
  ours: text_kernel.TextOperation,
  echoed: text_kernel.TextOperation,
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
    text_kernel.Insert(_, _, _), _
    | text_kernel.DeleteRange(_, _, _), _
    | text_kernel.ReplaceRange(_, _, _, _), _
    | text_kernel.Append(_, _), _
    -> False
  }
}

fn same_text_delta(ours: Text, echoed: Text) -> Bool {
  wire.json_semantically_equal(text.to_json(ours), text.to_json(echoed))
}

fn same_directory_shape(
  ours: directory_kernel.DirectoryOperation,
  echoed: directory_kernel.DirectoryOperation,
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
    directory_kernel.Set(_, _, _), _
    | directory_kernel.Delete(_, _), _
    | directory_kernel.Clear(_), _
    | directory_kernel.CreateSubDirectory(_, _), _
    | directory_kernel.DeleteSubDirectory(_, _), _
    -> False
  }
}

fn same_map_shape(
  ours: map_kernel.MapOperation,
  echoed: map_kernel.MapOperation,
) -> Bool {
  case ours, echoed {
    map_kernel.Set(our_key, _), map_kernel.Set(echoed_key, _) ->
      our_key == echoed_key
    map_kernel.Delete(our_key), map_kernel.Delete(echoed_key) ->
      our_key == echoed_key
    map_kernel.Clear, map_kernel.Clear -> True
    map_kernel.Set(_, _), _ | map_kernel.Delete(_), _ | map_kernel.Clear, _ ->
      False
  }
}

fn same_or_map_shape(
  ours: or_map_kernel.OrMapOperation,
  echoed: or_map_kernel.OrMapOperation,
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
    or_map_kernel.Increment(_, _, _), _
    | or_map_kernel.SetRegister(_, _, _, _), _
    | or_map_kernel.Remove(_, _), _
    -> False
  }
}

fn same_or_set_shape(
  ours: or_set_kernel.OrSetOperation,
  echoed: or_set_kernel.OrSetOperation,
) -> Bool {
  case ours, echoed {
    or_set_kernel.Add(our_element, _), or_set_kernel.Add(echoed_element, _) ->
      our_element == echoed_element
    or_set_kernel.Remove(our_element, _),
      or_set_kernel.Remove(echoed_element, _)
    -> our_element == echoed_element
    or_set_kernel.Add(_, _), _ | or_set_kernel.Remove(_, _), _ -> False
  }
}

fn same_g_set_shape(
  ours: g_set_kernel.GSetOperation,
  echoed: g_set_kernel.GSetOperation,
) -> Bool {
  case ours, echoed {
    g_set_kernel.Add(our_element, _), g_set_kernel.Add(echoed_element, _) ->
      our_element == echoed_element
  }
}

fn same_two_p_set_shape(
  ours: two_p_set_kernel.TwoPSetOperation,
  echoed: two_p_set_kernel.TwoPSetOperation,
) -> Bool {
  case ours, echoed {
    two_p_set_kernel.Add(our_element, _),
      two_p_set_kernel.Add(echoed_element, _)
    -> our_element == echoed_element
    two_p_set_kernel.Remove(our_element, _),
      two_p_set_kernel.Remove(echoed_element, _)
    -> our_element == echoed_element
    two_p_set_kernel.Add(_, _), _ | two_p_set_kernel.Remove(_, _), _ -> False
  }
}

fn same_task_manager_shape(
  ours: task_manager_kernel.TaskManagerOperation,
  echoed: task_manager_kernel.TaskManagerOperation,
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
    task_manager_kernel.Volunteer(_), _
    | task_manager_kernel.Abandon(_), _
    | task_manager_kernel.Complete(_), _
    -> False
  }
}

/// Whether the sequenced echo of a local attach carries the snapshot that this
/// client submitted. The function compares the values by structure, and not by
/// their bytes.
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
    MapSnapshot(_), _
    | CounterSnapshot(_), _
    | PnCounterSnapshot(_), _
    | OrMapSnapshot(_, _), _
    | OrSetSnapshot(_), _
    | GSetSnapshot(_), _
    | TwoPSetSnapshot(_), _
    | RegisterCollectionSnapshot(_), _
    | ClaimsSnapshot(_), _
    | TaskManagerSnapshot(_), _
    | PactMapSnapshot(_), _
    | JsonOtSnapshot(_), _
    | DirectorySnapshot(_), _
    | OrderedCollectionSnapshot(_, _), _
    | SequenceSummary(_), _
    | RichTextSnapshot(_), _
    | TextSummary(_), _
    -> False
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

/// The handle addresses that the current values of the channel reach, for the
/// order of the attach dependencies. A counter holds no handle.
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

/// Encode the payload of a snapshot, whose shape depends on the channel type.
/// That payload is the `snapshot` field of the attach operation, and the `data`
/// field of the channel in the summary blob.
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

/// The recursive JSON of a directory summary. Each node carries its ordered
/// storage entries, its create info, its creator ids, its detached flag, and
/// its named child directories, in directory order.
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

/// The decoder for a snapshot payload. The channel type selects it, and the
/// envelope that carries the payload names that type in a field.
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
  ours: pact_map_kernel.PactMapOperation,
  echoed: pact_map_kernel.PactMapOperation,
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
    pact_map_kernel.Set(_, _, _), _ | pact_map_kernel.Accept(_), _ -> False
  }
}

fn same_optional_json(a: Option(Json), b: Option(Json)) -> Bool {
  json.to_string(encode_optional_value(a))
  == json.to_string(encode_optional_value(b))
}

fn same_ordered_shape(
  ours: ordered_collection_kernel.OrderedOperation,
  echoed: ordered_collection_kernel.OrderedOperation,
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
    ordered_collection_kernel.Add(_), _
    | ordered_collection_kernel.Acquire(_), _
    | ordered_collection_kernel.Complete(_), _
    | ordered_collection_kernel.Release(_), _
    -> False
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

/// A PactMap value is an `Option(Json)` value. `None` is a true tombstone,
/// which is not the same as `Some(null)`. It thus gets its own `Absent` wire
/// tag, and not a JSON `null`.
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

/// `{queue: [value...], jobs: [{acquireId, value, owner}]}`. `owner` is an
/// integer client id, or `null` for a job that a local client acquired while
/// the collection was unattached.
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
      case or_map_kernel.spec_string_to_mode(spec), or_map.from_json(encoded) {
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
