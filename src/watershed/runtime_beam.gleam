//// Runtime actor: one per document connection.
////
//// This actor owns the `runtime_core` state, which holds the kernels, and the
//// list of subscribers. A dedicated receiver process owns the aquamarine
//// channel, because the transport delivers only to the process that opened it.
//// That receiver forwards every inbound frame to this actor. The actor itself
//// can push safely.
////
//// Resilience (M4):
////
//// - **Gaps.** `runtime_core` buffers an operation that arrives out of order,
////   and it asks this actor to send a `requestOps` frame for an in-band
////   catch-up. The buffer empties as it fills.
//// - **Reconnect.** A channel that closes in the middle of a session, or a
////   nack that permits a retry, causes a rejoin and a new handshake with a new
////   client id. The handshake sends `lastSeenSequenceNumber`, so the server
////   pushes the delta only. The actor reconciles the old operations that are
////   still in flight against the catch-up stream, and it resubmits the
////   remainder with new CSN values after it reaches the reconnect checkpoint.
////   The actor applies an edit from the connecting interval optimistically,
////   and it delays the push of that edit to the same resubmit.
//// - **Nacks.** A fatal nack, which reports a bad scope, a bad size, or a hard
////   limit, crashes the actor. Every other nack causes a reconnect and a
////   reconcile.
//// - **Heartbeat.** A periodic `noop` frame advances the MSN of the server
////   while the client is idle.
////
//// ## Why this module panics
////
//// A library must not panic. This module is the one exception in the package,
//// because it is an OTP actor. The panics are all inside the message loop, and
//// they all report a fault that the actor cannot repair: a channel push that
//// the transport refused, a summary or a history fetch that failed, a
//// bootstrap that the core refused, a fatal nack, and a server frame that does
//// not decode. Each one crashes the actor, which is the OTP way to report such
//// a fault. Place the runtime under a supervisor to restart it. The
//// synchronous API of the package returns a `Result` instead, so a caller
//// never meets a panic on a normal path.

@target(erlang)
import gleam/dict.{type Dict}
@target(erlang)
import gleam/dynamic.{type Dynamic}
@target(erlang)
import gleam/erlang/process.{type Subject}
@target(erlang)
import gleam/int
@target(erlang)
import gleam/json.{type Json}
@target(erlang)
import gleam/list
@target(erlang)
import gleam/option.{type Option, None, Some}
@target(erlang)
import gleam/otp/actor
@target(erlang)
import gleam/result
@target(erlang)
import gleam/string

@target(erlang)
import aquamarine
@target(erlang)
import aquamarine/channel.{type Channel}
@target(erlang)
import aquamarine/phoenix

@target(erlang)
import spillway/message.{
  type ConnectMessage, type SignalMessage, type SummaryContext,
}
@target(erlang)
import spillway/nack.{type Nack}
@target(erlang)
import spillway/types.{type SequencedDocumentMessage}

@target(erlang)
import watershed/channel.{
  type ChannelEvent, type ChannelInit, type Resolution, AcquireResolved,
  ClaimResolved, InitClaims, InitCounter, InitDirectory, InitGSet, InitJsonOt,
  InitMap, InitOrMap, InitOrSet, InitOrderedCollection, InitPactMap,
  InitPnCounter, InitRegisterCollection, InitRichText, InitSequence,
  InitTaskManager, InitText, InitTwoPSet, SequenceChannel, TextChannel,
} as _watershed_channel
@target(erlang)
import watershed/claims_kernel
@target(erlang)
import watershed/git_storage
@target(erlang)
import watershed/id
@target(erlang)
import watershed/json_ot
@target(erlang)
import watershed/or_map_kernel.{type OrMapMode, type OrMapValue}
@target(erlang)
import watershed/ordered_collection_kernel

@target(erlang)
import watershed/pact_map_kernel
@target(erlang)
import watershed/register_collection_kernel.{type ReadPolicy}
@target(erlang)
import watershed/rich_text
@target(erlang)
import watershed/runtime_core
@target(erlang)
import watershed/summary_policy
@target(erlang)
import watershed/task_manager_kernel
@target(erlang)
import watershed/text_kernel
@target(erlang)
import watershed/wire
@target(erlang)
import watershed/wire/socket
@target(erlang)
import watershed/wire/summary_blob

@target(erlang)
const connect_timeout_milliseconds = 10_000

@target(erlang)
const heartbeat_interval_milliseconds = 30_000

@target(erlang)
/// The server nacks a submission of more than 100 operations. Split a resubmit
/// into chunks to stay below that limit.
const max_operations_per_submission = 100

// ─────────────────────────────────────────────────────────────────────────────
// Transport seam
//
// The runtime talks to floodgate through an injectable `Transport` rather than
// calling aquamarine directly. The default transport (`aquamarine_transport`)
// reproduces the historical behavior exactly; the in-memory hub (see
// `watershed/hub`) supplies an alternate transport so app authors can run
// deterministic multi-client tests with no server. Every concrete link type
// (an aquamarine `Channel`, a hub subject) is captured inside the closures of
// a `TransportHandle`, so no connection-specific type leaks into `State`/`Msg`
// or the public facade.
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// The outbound operations of a live connection. Each function closes over the
/// concrete link, so the runtime holds a `TransportHandle` value and never
/// names the transport that it came from. `push` carries the wire event name
/// and its JSON payload. `close` is a deliberate teardown. `drop` forces a
/// reconnect. For the real transport the last two do the same thing.
pub type TransportHandle {
  TransportHandle(
    push: fn(String, Json) -> Nil,
    close: fn() -> Nil,
    drop: fn() -> Nil,
  )
}

@target(erlang)
/// How a transport reports its lifecycle and its inbound frames back to the
/// runtime actor. The default transport calls these functions from its receiver
/// process. The hub calls them synchronously at delivery time.
pub type TransportCallbacks {
  TransportCallbacks(
    /// The channel joined and can push now. This callback carries the handle
    /// for every later outbound frame.
    on_ready: fn(TransportHandle) -> Nil,
    /// An inbound frame: the wire event name with its JSON payload. A
    /// transport decodes its own foreign representation into `Json` before it
    /// calls this function, so no foreign value reaches the runtime actor.
    on_event: fn(String, Json) -> Nil,
    /// The first connect or join failed. The runtime treats this event as
    /// fatal.
    on_fail: fn(String) -> Nil,
    /// A ready session closed. The runtime enters its reconnect path.
    on_close: fn(String) -> Nil,
  )
}

@target(erlang)
/// A replaceable connection to a floodgate-shaped server. `connect` opens the
/// link, and it starts whatever process it needs. It then calls the callbacks.
/// It returns immediately, and it never blocks the actor.
pub type Transport {
  Transport(connect: fn(TransportCallbacks) -> Nil)
}

@target(erlang)
pub type ClaimSubmitReply {
  Pending(outcome: Subject(claims_kernel.ClaimOutcome))
  AlreadyClaimed(current_value: Json)
  AlreadyPendingLocally
  WrongChannelType
}

@target(erlang)
pub type Msg {
  Heartbeat
  /// A wake-up from the automatic summarization policy, after a delay that
  /// differs for each client. The message carries no state. The actor makes the
  /// decision again against the core as it is at that moment, so a summary from
  /// a peer that arrives in the window makes this message do nothing.
  MaybeSummarize
  /// Install the automatic summarization policy, or clear it. A value of
  /// `None` turns the policy off.
  SetAutoSummary(policy: Option(summary_policy.Policy))
  /// The operations that sequenced after the newest checkpoint that this client
  /// knows about.
  OperationsSinceSummary(reply: Subject(Int))
  // Receiver-process lifecycle
  ChannelReady(TransportHandle)
  ChannelFailed(String)
  Inbound(event: String, payload: Json)
  ChannelClosed(String)
  // Local edits
  Put(address: String, key: String, value: Json)
  Remove(address: String, key: String)
  RemoveAll(address: String)
  IncrementCounter(address: String, amount: Int)
  UpdatePnCounter(address: String, amount: Int)
  SetPactMap(address: String, key: String, value: Json)
  DeletePactMap(address: String, key: String)
  AddOrderedItem(address: String, value: Json)
  AcquireOrderedItem(address: String, reply: Subject(String))
  /// The same as `AcquireOrderedItem`, and `outcome` also receives the
  /// consensus result of the acquire when the operation sequences, or
  /// immediately when the channel is detached.
  AcquireOrderedItemWithOutcome(
    address: String,
    outcome: Subject(ordered_collection_kernel.AcquireOutcome),
    reply: Subject(String),
  )
  CompleteOrderedItem(address: String, acquire_id: String)
  ReleaseOrderedItem(address: String, acquire_id: String)
  InsertSequenceItem(
    address: String,
    index: Int,
    value: Json,
    reply: Subject(Result(Nil, String)),
  )
  DeleteSequenceItem(
    address: String,
    index: Int,
    reply: Subject(Result(Nil, String)),
  )
  MoveSequenceItem(
    address: String,
    from_index: Int,
    to_index: Int,
    reply: Subject(Result(Nil, String)),
  )
  ReplaceSequenceItem(
    address: String,
    index: Int,
    value: Json,
    reply: Subject(Result(Nil, String)),
  )
  /// Insert `value` at the grapheme `index`, counted from zero. An empty
  /// edit, where `value` is `""`, changes nothing. It succeeds, and it
  /// produces no event and no outbound operation.
  InsertText(
    address: String,
    index: Int,
    value: String,
    reply: Subject(Result(Nil, String)),
  )
  /// Delete the graphemes in `[start, end)`. An empty range changes nothing.
  DeleteRangeText(
    address: String,
    start: Int,
    end: Int,
    reply: Subject(Result(Nil, String)),
  )
  /// Replace the graphemes in `[start, end)` with `value`, as one
  /// collaborative operation. To replace an empty range with `""` changes
  /// nothing.
  ReplaceRangeText(
    address: String,
    start: Int,
    end: Int,
    value: String,
    reply: Subject(Result(Nil, String)),
  )
  /// Append `value` to the end of the text. To append `""` changes nothing.
  AppendText(
    address: String,
    value: String,
    reply: Subject(Result(Nil, String)),
  )
  SubmitJsonOt(address: String, components: json_ot.Operation)
  SubmitRichText(address: String, delta: rich_text.Delta)
  IncrementOrMap(address: String, key: String, amount: Int)
  SetOrMapKey(address: String, key: String, value: String)
  RemoveOrMapKey(address: String, key: String)
  AddOrSetElement(address: String, element: String)
  RemoveOrSetElement(address: String, element: String)
  AddGSetElement(address: String, element: String)
  AddTwoPSetElement(address: String, element: String)
  RemoveTwoPSetElement(address: String, element: String)
  WriteRegister(address: String, key: String, value: Json)
  VolunteerTask(
    address: String,
    task_id: String,
    reply: Subject(task_manager_kernel.VolunteerOutcome),
  )
  AbandonTask(address: String, task_id: String)
  CompleteTask(
    address: String,
    task_id: String,
    reply: Subject(Result(Nil, String)),
  )
  ClaimOnce(
    address: String,
    key: String,
    value: Json,
    outcome: Subject(claims_kernel.ClaimOutcome),
    reply: Subject(ClaimSubmitReply),
  )
  CompareAndSetClaim(
    address: String,
    key: String,
    value: Json,
    outcome: Subject(claims_kernel.ClaimOutcome),
    reply: Subject(ClaimSubmitReply),
  )
  /// Create a new detached map channel. It is local only, until a caller
  /// stores its handle into an attached map. The reply carries the address
  /// that the runtime generated.
  CreateMap(reply: Subject(Result(String, String)))
  /// Create a new detached counter channel. The lifecycle is the same as for
  /// `CreateMap`.
  CreateCounter(reply: Subject(Result(String, String)))
  /// Create a new detached PN-counter channel. The lifecycle is the same as
  /// for `CreateMap`.
  CreatePnCounter(reply: Subject(Result(String, String)))
  /// Create a new detached PactMap channel, which is a consensus map. The
  /// lifecycle is the same as for `CreateMap`.
  CreatePactMap(reply: Subject(Result(String, String)))
  /// Create a new detached ConsensusOrderedCollection channel. The lifecycle
  /// is the same as for `CreateMap`.
  CreateOrderedCollection(reply: Subject(Result(String, String)))
  CreateSequence(reply: Subject(Result(String, String)))
  /// Create a new detached text channel. The lifecycle is the same as for
  /// `CreateMap`.
  CreateText(reply: Subject(Result(String, String)))
  /// Create a new detached OR-map channel in the requested value mode.
  CreateOrMap(mode: OrMapMode, reply: Subject(Result(String, String)))
  CreateOrSet(reply: Subject(Result(String, String)))
  CreateGSet(reply: Subject(Result(String, String)))
  CreateTwoPSet(reply: Subject(Result(String, String)))
  CreateRegisterCollection(reply: Subject(Result(String, String)))
  CreateClaims(reply: Subject(Result(String, String)))
  CreateJsonOt(reply: Subject(Result(String, String)))
  CreateRichText(reply: Subject(Result(String, String)))
  CreateTaskManager(reply: Subject(Result(String, String)))
  /// Whether a channel exists at `address`, attached or detached. A caller
  /// can retry after an error, because an attach from another client can
  /// still be in flight.
  ResolveAddress(address: String, reply: Subject(Result(Nil, String)))
  ResolveSequence(address: String, reply: Subject(Result(Nil, String)))
  ResolveText(address: String, reply: Subject(Result(Nil, String)))
  /// Summarize the current confirmed state to the storage of floodgate. On a
  /// success the reply carries the summary handle, which is a git tree SHA.
  Summarize(reply: Subject(Result(String, String)))
  /// List the stored summary versions of the document, newest first.
  GetVersions(
    count: Int,
    reply: Subject(Result(List(git_storage.SummaryVersion), String)),
  )
  /// Read the snapshot that a summary version captured, by the handle of that
  /// version.
  LoadVersion(
    handle: String,
    reply: Subject(Result(summary_blob.SummaryBlob, String)),
  )
  // Reads
  GetValue(address: String, key: String, reply: Subject(Result(Json, Nil)))
  /// The optimistic value of the counter. The reply is `Error(Nil)` when the address
  /// does not exist, and when it does not name a counter channel.
  GetCounterValue(address: String, reply: Subject(Result(Int, Nil)))
  /// The optimistic value of the PN-counter. The reply is `Error(Nil)` when the
  /// address does not exist, and when it does not name a PN-counter channel.
  GetPnCounterValue(address: String, reply: Subject(Result(Int, Nil)))
  /// The accepted value of the PactMap for `key`. The reply is `Error(Nil)` when the
  /// value is pending, when the key is absent, and when the address does not
  /// name a PactMap channel.
  GetPactMapValue(
    address: String,
    key: String,
    reply: Subject(Result(Json, Nil)),
  )
  /// Every key with an accepted pact or a pending pact, in the PactMap at
  /// `address`.
  GetPactMapKeys(address: String, reply: Subject(List(String)))
  /// Whether `key` has a pending value, which a client proposed and no room
  /// has accepted yet.
  GetPactMapPending(address: String, key: String, reply: Subject(Bool))
  /// The pending proposal for `key`, which is the value with the signoff list
  /// that it waits on. The reply is `Error(Nil)` when nothing is pending, and when
  /// the address does not name a PactMap.
  GetPactMapPendingDetails(
    address: String,
    key: String,
    reply: Subject(Result(pact_map_kernel.Pending, Nil)),
  )
  /// The accepted entry for `key`, which is the value with its sequence
  /// number. The reply is `Error(Nil)` when the key has no accepted value.
  GetPactMapAccepted(
    address: String,
    key: String,
    reply: Subject(Result(pact_map_kernel.Accepted, Nil)),
  )
  /// The number of items in the queue of the ordered collection at `address`,
  /// which are the items that no client acquired yet. The reply is `Error(Nil)` when
  /// the address does not exist, and when it does not name an
  /// ordered-collection channel.
  GetOrderedSize(address: String, reply: Subject(Result(Int, Nil)))
  /// The values in the queue at `address`, which no client acquired yet, front
  /// first.
  GetOrderedQueue(address: String, reply: Subject(List(Json)))
  /// The jobs that clients hold at `address` now, keyed by acquire id and
  /// sorted by that id.
  GetOrderedJobs(
    address: String,
    reply: Subject(List(#(String, ordered_collection_kernel.JobEntry))),
  )
  /// The optimistic document of the json0 channel. The reply is `Error(Nil)` when
  /// the address does not exist, and when it does not name a json0 channel.
  GetJsonOtView(address: String, reply: Subject(Result(json_ot.JsonValue, Nil)))
  /// The optimistic document of the rich-text channel. The reply is `Error(Nil)`
  /// when the address does not exist, and when it does not name a rich-text
  /// channel.
  GetRichTextView(
    address: String,
    reply: Subject(Result(rich_text.Document, Nil)),
  )
  GetOrMapValue(
    address: String,
    key: String,
    reply: Subject(Result(OrMapValue, Nil)),
  )
  GetOrMapEntries(address: String, reply: Subject(List(#(String, OrMapValue))))
  GetOrMapKeys(address: String, reply: Subject(List(String)))
  OrSetContains(address: String, element: String, reply: Subject(Bool))
  GetOrSetValues(address: String, reply: Subject(List(String)))
  GSetContains(address: String, element: String, reply: Subject(Bool))
  GetGSetValues(address: String, reply: Subject(List(String)))
  GetSequenceValues(address: String, reply: Subject(List(Json)))
  GetSequenceLength(address: String, reply: Subject(Int))
  /// The current visible optimistic string of the text channel. The reply is
  /// `""` when the address does not exist, and when it does not name a text
  /// channel.
  GetTextValue(address: String, reply: Subject(String))
  /// The current optimistic grapheme count of the text channel. The reply is
  /// `0` when the address does not exist, and when it does not name a text
  /// channel.
  GetTextLength(address: String, reply: Subject(Int))
  /// The graphemes in `[start, end)` of the optimistic string of the text
  /// channel. The reply is an error string when the range `start..end` is
  /// invalid, when the address does not exist, and when the address does not
  /// name a text channel.
  GetTextSubstring(
    address: String,
    start: Int,
    end: Int,
    reply: Subject(Result(String, String)),
  )
  /// Create a stable anchor at the gap before or after the optimistic grapheme
  /// at `index`, as `bias` selects. The reply is an error string when the
  /// index is out of bounds, when the address does not exist, and when the
  /// address does not name a text channel.
  TextAnchorAt(
    address: String,
    index: Int,
    bias: text_kernel.Bias,
    reply: Subject(Result(text_kernel.TextAnchor, String)),
  )
  /// Resolve an anchor to its current optimistic grapheme index. The reply is
  /// an error string when the anchor target is stale or unknown, when the
  /// address does not exist, and when the address does not name a text
  /// channel.
  TextResolveAnchor(
    address: String,
    anchor: text_kernel.TextAnchor,
    reply: Subject(Result(Int, String)),
  )
  TwoPSetContains(address: String, element: String, reply: Subject(Bool))
  GetTwoPSetValues(address: String, reply: Subject(List(String)))
  DirectorySet(address: String, path: String, key: String, value: Json)
  DirectoryDelete(address: String, path: String, key: String)
  DirectoryClear(address: String, path: String)
  DirectoryCreateSubdirectory(address: String, path: String, name: String)
  DirectoryDeleteSubdirectory(address: String, path: String, name: String)
  CreateDirectory(reply: Subject(Result(String, String)))
  DirectoryGet(
    address: String,
    path: String,
    key: String,
    reply: Subject(Result(Json, Nil)),
  )
  DirectoryEntries(
    address: String,
    path: String,
    reply: Subject(List(#(String, Json))),
  )
  DirectorySubdirectories(
    address: String,
    path: String,
    reply: Subject(List(String)),
  )
  DirectoryHasSubdirectory(
    address: String,
    path: String,
    name: String,
    reply: Subject(Bool),
  )
  GetRegisterValue(
    address: String,
    key: String,
    policy: ReadPolicy,
    reply: Subject(Result(Json, Nil)),
  )
  GetRegisterVersions(
    address: String,
    key: String,
    reply: Subject(Result(List(Json), Nil)),
  )
  GetRegisterKeys(address: String, reply: Subject(List(String)))
  GetClaim(address: String, key: String, reply: Subject(Result(Json, Nil)))
  HasClaim(address: String, key: String, reply: Subject(Bool))
  TaskAssigned(address: String, task_id: String, reply: Subject(Bool))
  TaskQueued(address: String, task_id: String, reply: Subject(Bool))
  TaskQueues(address: String, reply: Subject(List(#(String, List(Int)))))
  GetEntries(address: String, reply: Subject(List(#(String, Json))))
  GetKeys(address: String, reply: Subject(List(String)))
  GetSize(address: String, reply: Subject(Int))
  /// Whether the server acked every local edit, which is true when the
  /// in-flight queue is empty. The confirmed state is then complete and
  /// stable.
  IsSynced(reply: Subject(Bool))
  /// The client id that the server assigned. The reply is `None` before the
  /// first handshake.
  ClientId(reply: Subject(Option(String)))
  /// Broadcast an ephemeral ripple to this document, with a `type` tag and any
  /// JSON content. The message expects no reply. There is no order, no ack,
  /// and no catch-up. The message does nothing until the handshake assigns a
  /// client id.
  SubmitRipple(ripple_type: String, content: Json)
  /// Register a subscriber that the runtime calls for every inbound ripple on
  /// the document.
  SubscribeRipple(subscriber: fn(SignalMessage) -> Nil)
  /// Push a command on the presence lane, which is `joinPresence`,
  /// `updatePresence`, or `leavePresence`. Unlike a ripple, this command needs
  /// no client id. The payload carries no identity, because the server derives
  /// the key and the session from the authenticated connection.
  SubmitPresence(event: String, payload: Json)
  /// Register a subscriber that the runtime calls for every frame on the
  /// presence lane.
  SubscribePresence(subscriber: fn(PresenceFrame) -> Nil)
  // Lifecycle
  Subscribe(address: String, subscriber: fn(ChannelEvent) -> Nil)
  AwaitReady(reply: Subject(Result(Nil, String)))
  /// A hook that injects a fault, for a test. It closes the live channel, so
  /// that the runtime runs its reconnect and reconcile path.
  DropChannel
  Shutdown
}

@target(erlang)
/// One ordered inbox for the presence lane. It carries the data frames and the
/// connection lifecycle events that a presence driver must react to.
///
/// The two share one channel on purpose. A driver that learned about a lost
/// session from one source, and about the diffs from another source, could
/// apply a diff that belongs to a dead session. One stream cannot represent
/// that order.
pub type PresenceFrame {
  /// A `presence_state` snapshot, encoded as `Json`. The runtime does not
  /// decode it further, because it has no decoder for the metadata of the
  /// application, and the operation lane does have one.
  PresenceState(payload: Json)
  PresenceDiff(payload: Json)
  PresenceError(payload: Json)
  /// A new document session settled. The frame carries a new client id from
  /// the server, and the features that this handshake negotiated. The runtime
  /// sends it after the first handshake and after every reconnect, and a
  /// driver rejoins on it.
  PresenceSession(client_id: String, presence_v1: Bool)
  /// The session ended. Every presence that the server held for it is gone.
  PresenceSessionLost
}

@target(erlang)
type Phase {
  Connecting(waiters: List(Subject(Result(Nil, String))))
  /// The socket is closed and the runtime is doing the handshake again. This
  /// state holds the core from before the reconnect, so its kernels, its
  /// pending entries, and its in-flight operations all stay.
  Reconnecting(core: runtime_core.Core)
  /// The runtime is connected. `resubmit_at` is `Some(checkpoint)` while a
  /// reconnect still catches up to the point at which the runtime can
  /// resubmit the operations with no ack. It is `None` after the runtime is
  /// fully synchronized.
  Ready(core: runtime_core.Core, resubmit_at: Option(Int))
  Failed(reason: String)
}

@target(erlang)
type State {
  State(
    // `host`/`port` are retained for the REST summary API (git-storage), which
    // shares floodgate's origin. The websocket path/topic/join payload now live
    // inside the transport closure.
    host: String,
    port: Int,
    connect_message: ConnectMessage,
    transport: Transport,
    channel: Option(TransportHandle),
    phase: Phase,
    subscribers: List(#(String, fn(ChannelEvent) -> Nil)),
    ripple_subscribers: List(fn(SignalMessage) -> Nil),
    /// The subscribers on the presence lane. Presence does not sequence and
    /// never touches the core, the same as a ripple.
    presence_subscribers: List(fn(PresenceFrame) -> Nil),
    /// What the handshake of the *current* connection announced. This field is
    /// on `State`, and not on the core, and that is deliberate. The core stays
    /// intact across a reconnect. A capability on the core would thus outlive
    /// the connection that negotiated it, and it could claim support on a
    /// server that does not have it.
    supported_features: Dict(String, Dynamic),
    claim_waiters: Dict(#(String, String), Subject(claims_kernel.ClaimOutcome)),
    /// The pending acquires on an ordered collection, which wait for their
    /// sequenced outcome, keyed by `#(address, acquire_id)`.
    acquire_waiters: Dict(
      #(String, String),
      Subject(ordered_collection_kernel.AcquireOutcome),
    ),
    /// The automatic summarization policy. The value is `None` unless an
    /// application asked for one. This field is on `State`, and not on the
    /// core, because it is part of the configuration of this client, and not
    /// part of the document.
    auto_summary: Option(summary_policy.Policy),
    /// Whether a `MaybeSummarize` wake-up is scheduled already. Without this
    /// flag, a busy document would arm a new timer for every sequenced
    /// operation.
    summary_armed: Bool,
    self: Subject(Msg),
  )
}

@target(erlang)
/// Start a document runtime against a live floodgate server. The function
/// starts the actor and the channel receiver process, and it then returns the
/// subject of the actor. A caller must send `AwaitReady`, with `process.call`,
/// before it edits the document.
pub fn start(
  host host: String,
  port port: Int,
  path path: String,
  tenant tenant: String,
  document document: String,
  connect_message connect_message: ConnectMessage,
) -> Result(Subject(Msg), actor.StartError) {
  let topic = "document:" <> tenant <> ":" <> document
  let join_payload = case connect_message.token {
    Some(token) -> json.object([#("token", json.string(token))])
    None -> json.object([])
  }
  start_with_transport(
    host: host,
    port: port,
    connect_message: connect_message,
    transport: aquamarine_transport(host, port, path, topic, join_payload),
  )
}

@target(erlang)
/// Start a document runtime against any transport. The live `start` function,
/// which uses aquamarine, calls this function, and so does the in-memory hub
/// test driver. `host` and `port` supply the REST summary API only. A transport
/// that serves no such API can pass any value.
pub fn start_with_transport(
  host host: String,
  port port: Int,
  connect_message connect_message: ConnectMessage,
  transport transport: Transport,
) -> Result(Subject(Msg), actor.StartError) {
  actor.new_with_initialiser(1000, fn(self) {
    let state =
      State(
        host: host,
        port: port,
        connect_message: connect_message,
        transport: transport,
        channel: None,
        phase: Connecting([]),
        subscribers: [],
        ripple_subscribers: [],
        presence_subscribers: [],
        supported_features: dict.new(),
        claim_waiters: dict.new(),
        acquire_waiters: dict.new(),
        auto_summary: None,
        summary_armed: False,
        self: self,
      )
    let _ = process.send_after(self, heartbeat_interval_milliseconds, Heartbeat)
    connect_transport(transport, self)
    Ok(actor.initialised(state) |> actor.returning(self))
  })
  |> actor.on_message(handle)
  |> actor.start
  |> result.map(fn(started) { started.data })
}

@target(erlang)
/// Wait until the handshake completes or fails.
pub fn await_ready(runtime: Subject(Msg)) -> Result(Nil, String) {
  process.call(
    runtime,
    waiting: connect_timeout_milliseconds,
    sending: AwaitReady,
  )
}

@target(erlang)
pub fn resolve_sequence(
  runtime: Subject(Msg),
  address: String,
) -> Result(Nil, String) {
  process.call(
    runtime,
    waiting: connect_timeout_milliseconds,
    sending: fn(reply) { ResolveSequence(address, reply) },
  )
}

@target(erlang)
pub fn resolve_text(
  runtime: Subject(Msg),
  address: String,
) -> Result(Nil, String) {
  process.call(
    runtime,
    waiting: connect_timeout_milliseconds,
    sending: fn(reply) { ResolveText(address, reply) },
  )
}

@target(erlang)
/// An anchor at the start of the text. It always resolves to `0`. The function
/// is pure. It needs no message to the actor, because the anchor carries no
/// document state.
pub fn text_start_anchor() -> text_kernel.TextAnchor {
  runtime_core.text_start_anchor()
}

@target(erlang)
/// An anchor at the end of the text. It always resolves to the current grapheme
/// count, and it moves as the text becomes longer. The function is pure, the
/// same as `text_start_anchor`.
pub fn text_end_anchor() -> text_kernel.TextAnchor {
  runtime_core.text_end_anchor()
}

@target(erlang)
/// Encode an anchor as a self-describing JSON value, for example to send it
/// through presence for a shared cursor. The function is pure.
pub fn text_anchor_to_json(anchor: text_kernel.TextAnchor) -> Json {
  runtime_core.text_anchor_to_json(anchor)
}

@target(erlang)
/// Decode an anchor from a JSON string that `text_anchor_to_json` produced. The
/// result is an error string for malformed JSON. The function is pure.
pub fn text_anchor_from_json(
  json_string: String,
) -> Result(text_kernel.TextAnchor, String) {
  runtime_core.text_anchor_from_json(json_string)
}

@target(erlang)
/// Summarize the current confirmed state to the storage of floodgate. On a
/// success the function returns the summary handle, which is a git tree SHA.
/// The connection must be fully synchronized, and the token must carry the
/// `summary:write` scope.
pub fn summarize(runtime: Subject(Msg)) -> Result(String, String) {
  process.call(
    runtime,
    waiting: connect_timeout_milliseconds,
    sending: Summarize,
  )
}

@target(erlang)
/// Install the automatic summarization policy. A value of `None` clears it.
pub fn auto_summarize(
  runtime: Subject(Msg),
  policy: Option(summary_policy.Policy),
) -> Nil {
  process.send(runtime, SetAutoSummary(policy))
}

@target(erlang)
/// How far the document moved past the newest checkpoint that this client knows
/// about. The result is zero before the first handshake.
pub fn operations_since_summary(runtime: Subject(Msg)) -> Int {
  process.call(
    runtime,
    waiting: connect_timeout_milliseconds,
    sending: OperationsSinceSummary,
  )
}

@target(erlang)
/// Whether the client is caught up, which is true when the server acked every
/// local edit. The confirmed state is then complete and stable.
pub fn is_synced(runtime: Subject(Msg)) -> Bool {
  process.call(
    runtime,
    waiting: connect_timeout_milliseconds,
    sending: IsSynced,
  )
}

@target(erlang)
/// The client id that the server assigned to this connection. The result is
/// `None` before the first handshake completes.
///
/// A reconnect does not keep the value. There is always *a* current id, and
/// `adopt_reconnect` replaces it with the id that the new handshake assigns.
/// That id can differ from the previous one. A caller that holds the id across
/// a disconnect must read it again. It must not use a cached value.
pub fn client_id(runtime: Subject(Msg)) -> Option(String) {
  process.call(
    runtime,
    waiting: connect_timeout_milliseconds,
    sending: ClientId,
  )
}

@target(erlang)
fn client_id_of(state: State) -> Option(String) {
  case state.phase {
    Ready(core, _) -> Some(core.client_id)
    Reconnecting(core) -> Some(core.client_id)
    Connecting(_) | Failed(_) -> None
  }
}

@target(erlang)
pub fn claim_once(
  runtime: Subject(Msg),
  address: String,
  key: String,
  value: Json,
) -> ClaimSubmitReply {
  let outcome = process.new_subject()
  process.call(
    runtime,
    waiting: connect_timeout_milliseconds,
    sending: fn(reply) { ClaimOnce(address, key, value, outcome, reply) },
  )
}

@target(erlang)
pub fn compare_and_set_claim(
  runtime: Subject(Msg),
  address: String,
  key: String,
  value: Json,
) -> ClaimSubmitReply {
  let outcome = process.new_subject()
  process.call(
    runtime,
    waiting: connect_timeout_milliseconds,
    sending: fn(reply) {
      CompareAndSetClaim(address, key, value, outcome, reply)
    },
  )
}

@target(erlang)
pub fn get_claim(
  runtime: Subject(Msg),
  address: String,
  key: String,
) -> Result(Json, Nil) {
  process.call(
    runtime,
    waiting: connect_timeout_milliseconds,
    sending: fn(reply) { GetClaim(address, key, reply) },
  )
}

@target(erlang)
pub fn has_claim(runtime: Subject(Msg), address: String, key: String) -> Bool {
  process.call(
    runtime,
    waiting: connect_timeout_milliseconds,
    sending: fn(reply) { HasClaim(address, key, reply) },
  )
}

@target(erlang)
pub fn task_manager_volunteer(
  runtime: Subject(Msg),
  address: String,
  task_id: String,
) -> task_manager_kernel.VolunteerOutcome {
  process.call(
    runtime,
    waiting: connect_timeout_milliseconds,
    sending: fn(reply) { VolunteerTask(address, task_id, reply) },
  )
}

@target(erlang)
pub fn task_manager_abandon(
  runtime: Subject(Msg),
  address: String,
  task_id: String,
) -> Nil {
  process.send(runtime, AbandonTask(address, task_id))
}

@target(erlang)
pub fn task_manager_complete(
  runtime: Subject(Msg),
  address: String,
  task_id: String,
) -> Result(Nil, String) {
  process.call(
    runtime,
    waiting: connect_timeout_milliseconds,
    sending: fn(reply) { CompleteTask(address, task_id, reply) },
  )
}

@target(erlang)
pub fn task_manager_assigned(
  runtime: Subject(Msg),
  address: String,
  task_id: String,
) -> Bool {
  process.call(
    runtime,
    waiting: connect_timeout_milliseconds,
    sending: fn(reply) { TaskAssigned(address, task_id, reply) },
  )
}

@target(erlang)
pub fn task_manager_queued(
  runtime: Subject(Msg),
  address: String,
  task_id: String,
) -> Bool {
  process.call(
    runtime,
    waiting: connect_timeout_milliseconds,
    sending: fn(reply) { TaskQueued(address, task_id, reply) },
  )
}

@target(erlang)
pub fn task_manager_queues(
  runtime: Subject(Msg),
  address: String,
) -> List(#(String, List(Int))) {
  process.call(
    runtime,
    waiting: connect_timeout_milliseconds,
    sending: fn(reply) { TaskQueues(address, reply) },
  )
}

@target(erlang)
/// List the stored summary versions of the document, newest first. This is the
/// client half of the `getVersions` function of Fluid. The token must carry the
/// `doc:read` scope.
pub fn get_versions(
  runtime: Subject(Msg),
  count: Int,
) -> Result(List(git_storage.SummaryVersion), String) {
  process.call(
    runtime,
    waiting: connect_timeout_milliseconds,
    sending: fn(reply) { GetVersions(count, reply) },
  )
}

@target(erlang)
/// Read the snapshot that a summary version captured, by the handle of that
/// version. `get_versions` and the return value of `summarize` both give a
/// handle. The function does not change the live document. It reads the stored
/// blob at one point in time.
pub fn load_version(
  runtime: Subject(Msg),
  handle: String,
) -> Result(summary_blob.SummaryBlob, String) {
  process.call(
    runtime,
    waiting: connect_timeout_milliseconds,
    sending: fn(reply) { LoadVersion(handle, reply) },
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Receiver process / transport wiring
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Ask the transport to connect, and route its lifecycle callbacks into actor
/// messages. The runtime calls this function at startup and at every
/// reconnect.
fn connect_transport(transport: Transport, runtime: Subject(Msg)) -> Nil {
  transport.connect(
    TransportCallbacks(
      on_ready: fn(handle) { process.send(runtime, ChannelReady(handle)) },
      on_event: fn(event, payload) {
        process.send(runtime, Inbound(event, payload))
      },
      on_fail: fn(reason) { process.send(runtime, ChannelFailed(reason)) },
      on_close: fn(reason) { process.send(runtime, ChannelClosed(reason)) },
    ),
  )
}

@target(erlang)
/// The default transport: a dedicated receiver process that owns one aquamarine
/// channel. `connect` joins the channel, and it blocks in its own process while
/// it does that. It then announces the handle, and it forwards the inbound
/// frames until the channel closes.
fn aquamarine_transport(
  host: String,
  port: Int,
  path: String,
  topic: String,
  join_payload: Json,
) -> Transport {
  Transport(connect: fn(callbacks: TransportCallbacks) -> Nil {
    let _ =
      process.spawn_unlinked(fn() {
        case
          aquamarine.connect(
            host: host,
            port: port,
            path: path,
            topic: topic,
            payload: join_payload,
            codec: phoenix.codec(),
          )
        {
          Error(error) -> callbacks.on_fail(string.inspect(error))
          Ok(channel) -> {
            callbacks.on_ready(aquamarine_handle(channel))
            aquamarine_receive_loop(channel, callbacks)
          }
        }
      })
    Nil
  })
}

@target(erlang)
fn aquamarine_handle(channel: Channel) -> TransportHandle {
  let teardown = fn() {
    let _ = aquamarine.close(channel)
    Nil
  }
  TransportHandle(
    push: fn(event, payload) { aquamarine_push(channel, event, payload) },
    // A live aquamarine channel has no distinct "drop" — closing it triggers
    // the same receiver error that drives reconnect.
    close: teardown,
    drop: teardown,
  )
}

@target(erlang)
fn aquamarine_receive_loop(
  channel: Channel,
  callbacks: TransportCallbacks,
) -> Nil {
  case aquamarine.receive(channel) {
    Ok(incoming) -> {
      // aquamarine hands back its own `Dynamic` term from decoding the wire
      // text. Convert it to `Json` here, at the one place the foreign value
      // enters this module, so `TransportCallbacks` never carries a `Dynamic`.
      callbacks.on_event(incoming.event, wire.dynamic_to_json(incoming.payload))
      aquamarine_receive_loop(channel, callbacks)
    }
    Error(error) -> callbacks.on_close(string.inspect(error))
  }
}

@target(erlang)
fn aquamarine_push(channel: Channel, event: String, payload: Json) -> Nil {
  case aquamarine.push(channel, event, payload) {
    Ok(Nil) -> Nil
    Error(error) -> panic as { "channel push failed: " <> string.inspect(error) }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Actor
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
fn handle(state: State, msg: Msg) -> actor.Next(State, Msg) {
  case msg {
    Heartbeat -> {
      let _ =
        process.send_after(
          state.self,
          heartbeat_interval_milliseconds,
          Heartbeat,
        )
      case state.phase, state.channel {
        Ready(core, None), Some(channel) ->
          push(
            channel,
            "noop",
            socket.encode_noop(
              core.client_id,
              reference_sequence_number: core.last_seen_sequence_number,
            ),
          )
        Ready(_, None), None
        | Ready(_, Some(_)), _
        | Connecting(_), _
        | Reconnecting(_), _
        | Failed(_), _
        -> Nil
      }
      actor.continue(state)
    }

    OperationsSinceSummary(reply) -> {
      process.send(reply, read(state, 0, runtime_core.operations_since_summary))
      actor.continue(state)
    }

    SetAutoSummary(policy) ->
      // Arming waits for the next sequenced operation rather than happening
      // here: a document that is already past the threshold when the policy is
      // installed is the common case on a busy document, and the operation path
      // is the one place that knows the phase has settled.
      actor.continue(State(..state, auto_summary: policy))

    MaybeSummarize -> {
      let state = State(..state, summary_armed: False)
      case state.phase, state.channel, state.auto_summary {
        Ready(core, None), Some(channel), Some(policy) ->
          case runtime_core.wants_summary(core, policy) {
            // A peer summarized while we waited, or a local edit went out.
            // Either way the reason to summarize is gone.
            False -> actor.continue(state)
            True ->
              case do_summarize(state, core, channel) {
                Ok(#(core, _handle)) ->
                  actor.continue(State(..state, phase: Ready(core, None)))
                // A summarize operation carries no ack, so there is nothing to
                // reconcile on failure: the checkpoint simply did not move,
                // and the next sequenced operation arms another attempt.
                Error(_reason) -> actor.continue(state)
              }
          }
        Ready(_, None), Some(_), None
        | Ready(_, None), None, _
        | Ready(_, Some(_)), _, _
        | Connecting(_), _, _
        | Reconnecting(_), _, _
        | Failed(_), _, _
        -> actor.continue(state)
      }
    }

    ChannelReady(channel) -> {
      let last_seen = case state.phase {
        Reconnecting(core) -> Some(core.last_seen_sequence_number)
        Connecting(_) | Ready(_, _) | Failed(_) -> None
      }
      push(
        channel,
        "connect_document",
        socket.encode_connect_document(state.connect_message, last_seen),
      )
      actor.continue(State(..state, channel: Some(channel)))
    }

    ChannelFailed(reason) ->
      actor.continue(fail(state, "channel connect failed: " <> reason))

    ChannelClosed(reason) ->
      case state.phase {
        Ready(core, _) -> actor.continue(begin_reconnect(state, core))
        Reconnecting(core) -> actor.continue(begin_reconnect(state, core))
        Connecting(_) | Failed(_) ->
          actor.continue(fail(state, "channel closed: " <> reason))
      }

    Inbound(event, payload) -> handle_inbound(state, event, payload)

    Put(address, key, value) ->
      edit(state, fn(core) { runtime_core.set(core, address, key, value) })
    Remove(address, key) ->
      edit(state, fn(core) { runtime_core.delete(core, address, key) })
    RemoveAll(address) ->
      edit(state, fn(core) { runtime_core.clear(core, address) })
    IncrementCounter(address, amount) ->
      edit(state, fn(core) { runtime_core.increment(core, address, amount) })
    UpdatePnCounter(address, amount) ->
      edit(state, fn(core) {
        runtime_core.pn_counter_update(core, address, amount)
      })
    SetPactMap(address, key, value) ->
      edit(state, fn(core) {
        runtime_core.pact_map_set(core, address, key, value)
      })
    DeletePactMap(address, key) ->
      edit(state, fn(core) { runtime_core.pact_map_delete(core, address, key) })
    AddOrderedItem(address, value) ->
      edit(state, fn(core) { runtime_core.ordered_add(core, address, value) })
    AcquireOrderedItem(address, reply) ->
      handle_ordered_acquire(state, address, reply)
    AcquireOrderedItemWithOutcome(address, outcome, reply) ->
      handle_ordered_acquire_with_outcome(state, address, outcome, reply)
    CompleteOrderedItem(address, acquire_id) ->
      edit(state, fn(core) {
        runtime_core.ordered_complete(core, address, acquire_id)
      })
    ReleaseOrderedItem(address, acquire_id) ->
      edit(state, fn(core) {
        runtime_core.ordered_release(core, address, acquire_id)
      })
    InsertSequenceItem(address, index, value, reply) ->
      edit_sequence_with_result(
        state,
        reply,
        fn(core) { runtime_core.sequence_insert(core, address, index, value) },
        "sequence insert",
      )
    DeleteSequenceItem(address, index, reply) ->
      edit_sequence_with_result(
        state,
        reply,
        fn(core) { runtime_core.sequence_delete(core, address, index) },
        "sequence delete",
      )
    MoveSequenceItem(address, from_index, to_index, reply) ->
      edit_sequence_with_result(
        state,
        reply,
        fn(core) {
          runtime_core.sequence_move(core, address, from_index, to_index)
        },
        "sequence move",
      )
    ReplaceSequenceItem(address, index, value, reply) ->
      edit_sequence_with_result(
        state,
        reply,
        fn(core) { runtime_core.sequence_replace(core, address, index, value) },
        "sequence replace",
      )
    InsertText(address, index, value, reply) ->
      edit_text_with_result(
        state,
        reply,
        fn(core) { runtime_core.text_insert(core, address, index, value) },
        "text insert",
      )
    DeleteRangeText(address, start, end, reply) ->
      edit_text_with_result(
        state,
        reply,
        fn(core) { runtime_core.text_delete_range(core, address, start, end) },
        "text delete_range",
      )
    ReplaceRangeText(address, start, end, value, reply) ->
      edit_text_with_result(
        state,
        reply,
        fn(core) {
          runtime_core.text_replace_range(core, address, start, end, value)
        },
        "text replace_range",
      )
    AppendText(address, value, reply) ->
      edit_text_with_result(
        state,
        reply,
        fn(core) { runtime_core.text_append(core, address, value) },
        "text append",
      )
    SubmitJsonOt(address, components) ->
      edit(state, fn(core) {
        runtime_core.submit_json_ot(core, address, components)
      })
    SubmitRichText(address, delta) ->
      edit(state, fn(core) {
        runtime_core.submit_rich_text(core, address, delta)
      })
    IncrementOrMap(address, key, amount) ->
      edit(state, fn(core) {
        runtime_core.or_map_increment(core, address, key, amount)
      })
    SetOrMapKey(address, key, value) ->
      edit(state, fn(core) {
        runtime_core.or_map_set(core, address, key, value, now_milliseconds())
      })
    RemoveOrMapKey(address, key) ->
      edit(state, fn(core) { runtime_core.or_map_remove(core, address, key) })
    AddOrSetElement(address, element) ->
      edit(state, fn(core) { runtime_core.or_set_add(core, address, element) })
    RemoveOrSetElement(address, element) ->
      edit(state, fn(core) {
        runtime_core.or_set_remove(core, address, element)
      })
    AddGSetElement(address, element) ->
      edit(state, fn(core) { runtime_core.g_set_add(core, address, element) })
    AddTwoPSetElement(address, element) ->
      edit(state, fn(core) {
        runtime_core.two_p_set_add(core, address, element)
      })
    RemoveTwoPSetElement(address, element) ->
      edit(state, fn(core) {
        runtime_core.two_p_set_remove(core, address, element)
      })
    WriteRegister(address, key, value) ->
      edit(state, fn(core) {
        runtime_core.register_write(core, address, key, value)
      })
    VolunteerTask(address, task_id, reply) ->
      handle_task_volunteer(state, address, task_id, reply)
    AbandonTask(address, task_id) ->
      edit(state, fn(core) {
        runtime_core.task_manager_abandon(core, address, task_id)
      })
    CompleteTask(address, task_id, reply) ->
      handle_task_complete(state, address, task_id, reply)
    ClaimOnce(address, key, value, outcome, reply) ->
      handle_claim_submit(state, address, key, outcome, reply, fn(core) {
        runtime_core.claim_once(core, address, key, value)
      })
    CompareAndSetClaim(address, key, value, outcome, reply) ->
      handle_claim_submit(state, address, key, outcome, reply, fn(core) {
        runtime_core.compare_and_set_claim(core, address, key, value)
      })

    CreateMap(reply) -> create_channel(state, reply, InitMap, "create_map")
    CreateCounter(reply) ->
      create_channel(state, reply, InitCounter, "create_counter")
    CreatePnCounter(reply) ->
      create_channel(state, reply, InitPnCounter, "create_pn_counter")
    CreatePactMap(reply) ->
      create_channel(state, reply, InitPactMap, "create_pact_map")
    CreateOrderedCollection(reply) ->
      create_channel(
        state,
        reply,
        InitOrderedCollection,
        "create_ordered_collection",
      )
    CreateOrMap(mode, reply) ->
      create_channel(state, reply, InitOrMap(mode), "create_or_map")
    CreateOrSet(reply) ->
      create_channel(state, reply, InitOrSet, "create_or_set")
    CreateGSet(reply) -> create_channel(state, reply, InitGSet, "create_g_set")
    CreateSequence(reply) ->
      create_channel(state, reply, InitSequence, "create_sequence")
    CreateText(reply) -> create_channel(state, reply, InitText, "create_text")
    CreateDirectory(reply) ->
      create_channel(state, reply, InitDirectory, "create_directory")
    DirectorySet(address, path, key, value) ->
      edit(state, fn(core) {
        runtime_core.directory_set(core, address, path, key, value)
      })
    DirectoryDelete(address, path, key) ->
      edit(state, fn(core) {
        runtime_core.directory_delete(core, address, path, key)
      })
    DirectoryClear(address, path) ->
      edit(state, fn(core) { runtime_core.directory_clear(core, address, path) })
    DirectoryCreateSubdirectory(address, path, name) ->
      edit(state, fn(core) {
        runtime_core.directory_create_subdirectory(core, address, path, name)
      })
    DirectoryDeleteSubdirectory(address, path, name) ->
      edit(state, fn(core) {
        runtime_core.directory_delete_subdirectory(core, address, path, name)
      })
    CreateTwoPSet(reply) ->
      create_channel(state, reply, InitTwoPSet, "create_two_p_set")
    CreateRegisterCollection(reply) ->
      create_channel(
        state,
        reply,
        InitRegisterCollection,
        "create_register_collection",
      )
    CreateClaims(reply) ->
      create_channel(state, reply, InitClaims, "create_claims")
    CreateJsonOt(reply) ->
      create_channel(state, reply, InitJsonOt, "create_json_ot")
    CreateRichText(reply) ->
      create_channel(state, reply, InitRichText, "create_rich_text")
    CreateTaskManager(reply) ->
      create_channel(state, reply, InitTaskManager, "create_task_manager")

    ResolveAddress(address, reply) -> {
      let known = read(state, False, runtime_core.has_channel(_, address))
      let result = case known {
        True -> Ok(Nil)
        False ->
          Error(
            "unresolved handle: no channel at address "
            <> address
            <> " (a foreign attach may still be in flight; retry)",
          )
      }
      process.send(reply, result)
      actor.continue(state)
    }
    ResolveSequence(address, reply) -> {
      process.send(reply, resolve_sequence_address(state, address))
      actor.continue(state)
    }
    ResolveText(address, reply) -> {
      process.send(reply, resolve_text_address(state, address))
      actor.continue(state)
    }

    Summarize(reply) -> handle_summarize(state, reply)

    GetVersions(count, reply) -> {
      process.send(reply, fetch_document_versions(state, count))
      actor.continue(state)
    }
    LoadVersion(handle, reply) -> {
      process.send(reply, fetch_version_blob(state, handle))
      actor.continue(state)
    }

    GetValue(address, key, reply) -> {
      process.send(
        reply,
        read(state, Error(Nil), runtime_core.get(_, address, key)),
      )
      actor.continue(state)
    }
    GetCounterValue(address, reply) -> {
      process.send(
        reply,
        read(state, Error(Nil), runtime_core.counter_value(_, address)),
      )
      actor.continue(state)
    }
    GetPnCounterValue(address, reply) -> {
      process.send(
        reply,
        read(state, Error(Nil), runtime_core.pn_counter_value(_, address)),
      )
      actor.continue(state)
    }
    GetPactMapValue(address, key, reply) -> {
      process.send(
        reply,
        read(state, Error(Nil), runtime_core.pact_map_get(_, address, key)),
      )
      actor.continue(state)
    }
    GetPactMapKeys(address, reply) -> {
      process.send(
        reply,
        read(state, [], runtime_core.pact_map_keys(_, address)),
      )
      actor.continue(state)
    }
    GetPactMapPending(address, key, reply) -> {
      process.send(
        reply,
        read(state, False, runtime_core.pact_map_is_pending(_, address, key)),
      )
      actor.continue(state)
    }
    GetPactMapPendingDetails(address, key, reply) -> {
      process.send(
        reply,
        read(state, Error(Nil), runtime_core.pact_map_pending(_, address, key)),
      )
      actor.continue(state)
    }
    GetPactMapAccepted(address, key, reply) -> {
      process.send(
        reply,
        read(state, Error(Nil), runtime_core.pact_map_get_with_details(
          _,
          address,
          key,
        )),
      )
      actor.continue(state)
    }
    GetOrderedSize(address, reply) -> {
      process.send(
        reply,
        read(state, Error(Nil), runtime_core.ordered_size(_, address)),
      )
      actor.continue(state)
    }
    GetOrderedQueue(address, reply) -> {
      process.send(
        reply,
        read(state, [], runtime_core.ordered_queue(_, address)),
      )
      actor.continue(state)
    }
    GetOrderedJobs(address, reply) -> {
      process.send(
        reply,
        read(state, [], runtime_core.ordered_jobs(_, address)),
      )
      actor.continue(state)
    }
    GetJsonOtView(address, reply) -> {
      process.send(
        reply,
        read(state, Error(Nil), runtime_core.json_ot_view(_, address)),
      )
      actor.continue(state)
    }
    GetRichTextView(address, reply) -> {
      process.send(
        reply,
        read(state, Error(Nil), runtime_core.rich_text_view(_, address)),
      )
      actor.continue(state)
    }
    GetOrMapValue(address, key, reply) -> {
      process.send(
        reply,
        read(state, Error(Nil), runtime_core.or_map_value(_, address, key)),
      )
      actor.continue(state)
    }
    GetOrMapEntries(address, reply) -> {
      process.send(
        reply,
        read(state, [], runtime_core.or_map_entries(_, address)),
      )
      actor.continue(state)
    }
    GetOrMapKeys(address, reply) -> {
      process.send(reply, read(state, [], runtime_core.or_map_keys(_, address)))
      actor.continue(state)
    }
    OrSetContains(address, element, reply) -> {
      process.send(
        reply,
        read(state, False, runtime_core.or_set_contains(_, address, element)),
      )
      actor.continue(state)
    }
    GetOrSetValues(address, reply) -> {
      process.send(
        reply,
        read(state, [], runtime_core.or_set_values(_, address)),
      )
      actor.continue(state)
    }
    GSetContains(address, element, reply) -> {
      process.send(
        reply,
        read(state, False, runtime_core.g_set_contains(_, address, element)),
      )
      actor.continue(state)
    }
    GetGSetValues(address, reply) -> {
      process.send(
        reply,
        read(state, [], runtime_core.g_set_values(_, address)),
      )
      actor.continue(state)
    }
    GetSequenceValues(address, reply) -> {
      process.send(
        reply,
        read(state, [], runtime_core.sequence_values(_, address)),
      )
      actor.continue(state)
    }
    GetSequenceLength(address, reply) -> {
      process.send(
        reply,
        read(state, 0, runtime_core.sequence_length(_, address)),
      )
      actor.continue(state)
    }
    GetTextValue(address, reply) -> {
      process.send(reply, read(state, "", runtime_core.text_value(_, address)))
      actor.continue(state)
    }
    GetTextLength(address, reply) -> {
      process.send(reply, read(state, 0, runtime_core.text_length(_, address)))
      actor.continue(state)
    }
    GetTextSubstring(address, start, end, reply) -> {
      process.send(
        reply,
        read(
          state,
          Error("text substring requires a ready document connection"),
          runtime_core.text_substring(_, address, start, end),
        ),
      )
      actor.continue(state)
    }
    TextAnchorAt(address, index, bias, reply) -> {
      process.send(
        reply,
        read(
          state,
          Error("text anchor_at requires a ready document connection"),
          runtime_core.text_anchor_at(_, address, index, bias),
        ),
      )
      actor.continue(state)
    }
    TextResolveAnchor(address, anchor, reply) -> {
      process.send(
        reply,
        read(
          state,
          Error("text resolve_anchor requires a ready document connection"),
          runtime_core.text_resolve_anchor(_, address, anchor),
        ),
      )
      actor.continue(state)
    }
    DirectoryGet(address, path, key, reply) -> {
      process.send(
        reply,
        read(state, Error(Nil), runtime_core.directory_get(
          _,
          address,
          path,
          key,
        )),
      )
      actor.continue(state)
    }
    DirectoryEntries(address, path, reply) -> {
      process.send(
        reply,
        read(state, [], runtime_core.directory_entries(_, address, path)),
      )
      actor.continue(state)
    }
    DirectorySubdirectories(address, path, reply) -> {
      process.send(
        reply,
        read(state, [], runtime_core.directory_subdirectories(_, address, path)),
      )
      actor.continue(state)
    }
    DirectoryHasSubdirectory(address, path, name, reply) -> {
      process.send(
        reply,
        read(state, False, runtime_core.directory_has_subdirectory(
          _,
          address,
          path,
          name,
        )),
      )
      actor.continue(state)
    }
    TwoPSetContains(address, element, reply) -> {
      process.send(
        reply,
        read(state, False, runtime_core.two_p_set_contains(_, address, element)),
      )
      actor.continue(state)
    }
    GetTwoPSetValues(address, reply) -> {
      process.send(
        reply,
        read(state, [], runtime_core.two_p_set_values(_, address)),
      )
      actor.continue(state)
    }
    GetRegisterValue(address, key, policy, reply) -> {
      process.send(
        reply,
        read(state, Error(Nil), runtime_core.register_read(
          _,
          address,
          key,
          policy,
        )),
      )
      actor.continue(state)
    }
    GetRegisterVersions(address, key, reply) -> {
      process.send(
        reply,
        read(state, Error(Nil), runtime_core.register_versions(_, address, key)),
      )
      actor.continue(state)
    }
    GetRegisterKeys(address, reply) -> {
      process.send(
        reply,
        read(state, [], runtime_core.register_keys(_, address)),
      )
      actor.continue(state)
    }
    GetClaim(address, key, reply) -> {
      process.send(
        reply,
        read(state, Error(Nil), runtime_core.get_claim(_, address, key)),
      )
      actor.continue(state)
    }
    HasClaim(address, key, reply) -> {
      process.send(
        reply,
        read(state, False, runtime_core.has_claim(_, address, key)),
      )
      actor.continue(state)
    }
    TaskAssigned(address, task_id, reply) -> {
      process.send(
        reply,
        read(state, False, runtime_core.task_manager_assigned(
          _,
          address,
          task_id,
        )),
      )
      actor.continue(state)
    }
    TaskQueued(address, task_id, reply) -> {
      process.send(
        reply,
        read(state, False, runtime_core.task_manager_queued(_, address, task_id)),
      )
      actor.continue(state)
    }
    TaskQueues(address, reply) -> {
      process.send(
        reply,
        read(state, [], runtime_core.task_manager_queues(_, address)),
      )
      actor.continue(state)
    }
    GetEntries(address, reply) -> {
      process.send(reply, read(state, [], runtime_core.entries(_, address)))
      actor.continue(state)
    }
    GetKeys(address, reply) -> {
      process.send(reply, read(state, [], runtime_core.keys(_, address)))
      actor.continue(state)
    }
    GetSize(address, reply) -> {
      process.send(reply, read(state, 0, runtime_core.size(_, address)))
      actor.continue(state)
    }
    IsSynced(reply) -> {
      process.send(reply, read(state, False, runtime_core.is_synced))
      actor.continue(state)
    }

    ClientId(reply) -> {
      process.send(reply, client_id_of(state))
      actor.continue(state)
    }

    Subscribe(address, subscriber) ->
      actor.continue(
        State(..state, subscribers: [
          #(address, subscriber),
          ..state.subscribers
        ]),
      )

    SubmitRipple(ripple_type, content) -> {
      // Fire-and-forget: push straight to the channel, no kernel/in-flight
      // bookkeeping. No-operation until a handshake has assigned a client id.
      case state.channel, client_id_of(state) {
        Some(channel), Some(client_id) ->
          push(
            channel,
            "submitSignal",
            socket.encode_submit_ripple(
              client_id: client_id,
              ripple_type: ripple_type,
              content: content,
            ),
          )
        _, _ -> Nil
      }
      actor.continue(state)
    }

    SubscribeRipple(subscriber) ->
      actor.continue(
        State(..state, ripple_subscribers: [
          subscriber,
          ..state.ripple_subscribers
        ]),
      )

    SubmitPresence(event, payload) -> {
      case state.channel {
        Some(channel) -> push(channel, event, payload)
        None -> Nil
      }
      actor.continue(state)
    }

    SubscribePresence(subscriber) ->
      actor.continue(
        State(..state, presence_subscribers: [
          subscriber,
          ..state.presence_subscribers
        ]),
      )

    AwaitReady(reply) ->
      case state.phase {
        Ready(_, _) -> {
          process.send(reply, Ok(Nil))
          actor.continue(state)
        }
        Failed(reason) -> {
          process.send(reply, Error(reason))
          actor.continue(state)
        }
        Connecting(waiters) ->
          actor.continue(State(..state, phase: Connecting([reply, ..waiters])))
        // A reconnect can only start after we were Ready, i.e. after
        // await_ready already returned; treat as ready.
        Reconnecting(_) -> {
          process.send(reply, Ok(Nil))
          actor.continue(state)
        }
      }

    DropChannel ->
      case state.phase {
        // Reuse the retryable-nack path: close the channel and enter the
        // reconnecting phase; the receiver's ChannelClosed drives the rejoin.
        Ready(core, _) -> actor.continue(reconnect_after_nack(state, core))
        Connecting(_) | Reconnecting(_) | Failed(_) -> actor.continue(state)
      }

    Shutdown -> {
      let state = abort_outcome_waiters(state)
      case state.channel {
        Some(channel) -> channel.close()
        None -> Nil
      }
      actor.stop()
    }
  }
}

@target(erlang)
/// Create a detached channel of the supplied type, and reply with the address
/// that the runtime generated. A detached channel is local state only, so this
/// function works in every phase that has a connection.
fn create_channel(
  state: State,
  reply: Subject(Result(String, String)),
  init: ChannelInit,
  verb: String,
) -> actor.Next(State, Msg) {
  case state.phase {
    Ready(core, resubmit_at) -> {
      let address = id.uuid_v4()
      let core = runtime_core.create_detached(core, address, init)
      process.send(reply, Ok(address))
      actor.continue(State(..state, phase: Ready(core, resubmit_at)))
    }
    Reconnecting(core) -> {
      let address = id.uuid_v4()
      let core = runtime_core.create_detached(core, address, init)
      process.send(reply, Ok(address))
      actor.continue(State(..state, phase: Reconnecting(core)))
    }
    Connecting(_) | Failed(_) -> {
      process.send(
        reply,
        Error(verb <> " requires a ready document connection"),
      )
      actor.continue(state)
    }
  }
}

@target(erlang)
fn resolve_sequence_address(
  state: State,
  address: String,
) -> Result(Nil, String) {
  case state.phase {
    Ready(core, _) | Reconnecting(core) ->
      runtime_core.require_channel_type(core, address, SequenceChannel)
      |> result.map_error(string.inspect)
    Connecting(_) | Failed(_) ->
      Error("resolve_sequence requires a ready document connection")
  }
}

@target(erlang)
fn resolve_text_address(state: State, address: String) -> Result(Nil, String) {
  case state.phase {
    Ready(core, _) | Reconnecting(core) ->
      runtime_core.require_channel_type(core, address, TextChannel)
      |> result.map_error(string.inspect)
    Connecting(_) | Failed(_) ->
      Error("resolve_text requires a ready document connection")
  }
}

@target(erlang)
fn handle_inbound(
  state: State,
  event: String,
  payload: Json,
) -> actor.Next(State, Msg) {
  case event {
    "connect_document_success" -> {
      let connected =
        require(
          json.parse(
            json.to_string(payload),
            socket.connected_message_decoder(),
          ),
          "connect_document_success payload",
        )
      // Record what this connection negotiated before anything acts on it, and
      // on both paths — a reconnect may land on a different node with a
      // different answer.
      let state =
        State(..state, supported_features: connected.supported_features)
      case state.phase {
        Connecting(_) -> {
          let summary = case connected.summary_context {
            None -> None
            Some(context) ->
              case fetch_summary(state, context) {
                Ok(summary) -> Some(summary)
                Error(reason) -> panic as { "summary load failed: " <> reason }
              }
          }
          case runtime_core.bootstrap(connected, summary: summary) {
            Ok(bootstrapped) -> {
              let core = complete_bootstrap(state, bootstrapped)
              notify_waiters(state.phase, Ok(Nil))
              notify_presence_session(state, core)
              actor.continue(State(..state, phase: Ready(core, None)))
            }
            Error(core_error) ->
              panic as { "bootstrap failed: " <> string.inspect(core_error) }
          }
        }
        Reconnecting(core) -> {
          let core = runtime_core.adopt_reconnect(core, connected)
          let checkpoint =
            option.unwrap(
              connected.checkpoint_sequence_number,
              core.last_seen_sequence_number,
            )
          // Ask for the gap. Nothing else will: no server pushes it unprompted,
          // and the reactive `requestOps` in the `"op"` handler below needs an
          // operation to react to. See `runtime_core.catch_up_from`.
          maybe_request_operations(
            state.channel,
            runtime_core.catch_up_from(core, checkpoint),
          )
          // Presence is unsequenced, so it does not wait for the operation
          // catch-up `settle_reconnect` may still be pending — rejoining now is
          // both correct and the fastest way back to a roster.
          notify_presence_session(state, core)
          settle_reconnect(state, core, checkpoint)
        }
        // A late duplicate success; nothing to do.
        Ready(_, _) | Failed(_) -> actor.continue(state)
      }
    }

    "connect_document_error" -> {
      let connect_error =
        require(
          json.parse(json.to_string(payload), socket.connect_error_decoder()),
          "connect_document_error payload",
        )
      actor.continue(fail(state, connect_error.message))
    }

    "op" ->
      case state.phase {
        Ready(core, resubmit_at) -> {
          let #(core, events, resolutions, request_from, released) =
            apply_operations(core, operation_message(payload))
          let state = resolve_claim_waiters(state, resolutions)
          let state = resolve_acquire_waiters(state, resolutions)
          fan_out(state.subscribers, events)
          maybe_request_operations(state.channel, request_from)
          case resubmit_at {
            // Mid-reconnect: the operations a kernel just released are already
            // in the in-flight queue, and `settle_reconnect` is about to
            // restamp that whole queue with fresh client sequence numbers and
            // send it. Sending them here as well would put two copies of each
            // on the wire — the server sequences both, the client only expects
            // the restamped one, and the stale ack fails the FIFO match. Every
            // other submit path already gates on `resubmit_at`; this one is the
            // only route by which an operation reaches the wire without the
            // application asking, which is why only the consensus kernels
            // (whose `Accept`s are released, not submitted) could trip it.
            Some(checkpoint) -> settle_reconnect(state, core, checkpoint)
            None -> {
              send_outbound(state.channel, core.client_id, released)
              actor.continue(arm_summary(
                State(..state, phase: Ready(core, None)),
                core,
              ))
            }
          }
        }
        // Operations before/without a connected session (or while reconnecting)
        // carry no state we can trust; ignore them.
        Connecting(_) | Reconnecting(_) | Failed(_) -> actor.continue(state)
      }

    "nack" -> {
      let nacks =
        require(
          json.parse(json.to_string(payload), socket.nacks_decoder()),
          "nack payload",
        )
      case list.any(nacks, nack_is_fatal) {
        True ->
          panic as { "fatal nack from server: " <> json.to_string(payload) }
        False ->
          case state.phase {
            Ready(core, _) -> actor.continue(reconnect_after_nack(state, core))
            // Already tearing the channel down; the pending reconnect covers it.
            Connecting(_) | Reconnecting(_) | Failed(_) -> actor.continue(state)
          }
      }
    }

    // Ephemeral ripple broadcast: fan out to ripple subscribers. Malformed
    // payloads are dropped silently — ripples are best-effort.
    "signal" -> {
      case
        json.parse(json.to_string(payload), socket.ripple_message_decoder())
      {
        Error(_) -> Nil
        Ok(ripple) ->
          list.each(state.ripple_subscribers, fn(handler) { handler(ripple) })
      }
      actor.continue(state)
    }

    "presence_state" -> {
      notify_presence(state, PresenceState(payload))
      actor.continue(state)
    }

    "presence_diff" -> {
      notify_presence(state, PresenceDiff(payload))
      actor.continue(state)
    }

    "presence_error" -> {
      notify_presence(state, PresenceError(payload))
      actor.continue(state)
    }

    // Summary events, pongs: not part of the v1 surface.
    _ -> actor.continue(state)
  }
}

@target(erlang)
/// Resubmit the operations with no ack, after the catch-up reaches the
/// reconnect checkpoint. Before that point, stay in the catching-up state until
/// more operations arrive.
fn settle_reconnect(
  state: State,
  core: runtime_core.Core,
  checkpoint: Int,
) -> actor.Next(State, Msg) {
  case core.last_seen_sequence_number >= checkpoint {
    True -> {
      let #(core, outbound) = runtime_core.resubmit(runtime_core.go_live(core))
      send_outbound(state.channel, core.client_id, outbound)
      actor.continue(State(..state, phase: Ready(core, None)))
    }
    False ->
      actor.continue(State(..state, phase: Ready(core, Some(checkpoint))))
  }
}

@target(erlang)
fn operation_message(payload: Json) -> List(SequencedDocumentMessage) {
  let message =
    require(
      json.parse(json.to_string(payload), socket.operation_message_decoder()),
      "op payload",
    )
  message.ops
}

@target(erlang)
fn apply_operations(
  core: runtime_core.Core,
  operations: List(SequencedDocumentMessage),
) -> #(
  runtime_core.Core,
  List(#(String, ChannelEvent)),
  List(#(String, Resolution)),
  Option(Int),
  List(wire.OutboundOperation),
) {
  do_apply_operations(core, operations, [], [], None, [])
}

@target(erlang)
fn do_apply_operations(
  core: runtime_core.Core,
  operations: List(SequencedDocumentMessage),
  events: List(List(#(String, ChannelEvent))),
  resolutions: List(List(#(String, Resolution))),
  request_from: Option(Int),
  released: List(wire.OutboundOperation),
) -> #(
  runtime_core.Core,
  List(#(String, ChannelEvent)),
  List(#(String, Resolution)),
  Option(Int),
  List(wire.OutboundOperation),
) {
  case operations {
    [] -> #(
      core,
      list.reverse(events) |> list.flatten,
      list.reverse(resolutions) |> list.flatten,
      request_from,
      released,
    )
    [operation, ..rest] ->
      case runtime_core.handle_sequenced(core, operation) {
        Ok(#(core, ingested)) ->
          do_apply_operations(
            core,
            rest,
            [ingested.events, ..events],
            [ingested.resolutions, ..resolutions],
            option.or(request_from, ingested.request_operations_from),
            list.append(released, ingested.outbound),
          )
        Error(core_error) ->
          panic as {
            "sequenced op processing failed: " <> string.inspect(core_error)
          }
      }
  }
}

@target(erlang)
fn handle_claim_submit(
  state: State,
  address: String,
  key: String,
  outcome: Subject(claims_kernel.ClaimOutcome),
  reply: Subject(ClaimSubmitReply),
  operate: fn(runtime_core.Core) ->
    Result(runtime_core.ClaimSubmitResult, runtime_core.CoreError),
) -> actor.Next(State, Msg) {
  case state.phase {
    Ready(core, resubmit_at) ->
      case operate(core) {
        Error(runtime_core.WrongChannelType(..)) -> {
          process.send(reply, WrongChannelType)
          actor.continue(state)
        }
        // The core refused the claim for a reason that is not a channel type
        // mismatch. The actor reports the same refusal and stays alive: one
        // bad call must not take the whole document down.
        Error(_) -> {
          process.send(reply, WrongChannelType)
          actor.continue(state)
        }
        Ok(runtime_core.ClaimAlreadyClaimed(current_value)) -> {
          process.send(reply, AlreadyClaimed(current_value))
          actor.continue(state)
        }
        Ok(runtime_core.ClaimAlreadyPendingLocally) -> {
          process.send(reply, AlreadyPendingLocally)
          actor.continue(state)
        }
        Ok(runtime_core.ClaimPending(core, outbound, immediate_outcome)) -> {
          process.send(reply, Pending(outcome))
          let state =
            register_claim_waiter(
              state,
              address,
              key,
              outcome,
              immediate_outcome,
            )
          case resubmit_at, state.channel {
            None, Some(channel) ->
              send_outbound(Some(channel), core.client_id, outbound)
            _, _ -> Nil
          }
          actor.continue(State(..state, phase: Ready(core, resubmit_at)))
        }
      }

    Reconnecting(core) ->
      case operate(core) {
        Error(runtime_core.WrongChannelType(..)) -> {
          process.send(reply, WrongChannelType)
          actor.continue(state)
        }
        // The core refused the claim for a reason that is not a channel type
        // mismatch. The actor reports the same refusal and stays alive: one
        // bad call must not take the whole document down.
        Error(_) -> {
          process.send(reply, WrongChannelType)
          actor.continue(state)
        }
        Ok(runtime_core.ClaimAlreadyClaimed(current_value)) -> {
          process.send(reply, AlreadyClaimed(current_value))
          actor.continue(state)
        }
        Ok(runtime_core.ClaimAlreadyPendingLocally) -> {
          process.send(reply, AlreadyPendingLocally)
          actor.continue(state)
        }
        Ok(runtime_core.ClaimPending(core, _outbound, immediate_outcome)) -> {
          process.send(reply, Pending(outcome))
          let state =
            register_claim_waiter(
              state,
              address,
              key,
              outcome,
              immediate_outcome,
            )
          actor.continue(State(..state, phase: Reconnecting(core)))
        }
      }

    // The connection is not ready yet. The actor refuses the claim instead
    // of a crash.
    Connecting(_) | Failed(_) -> {
      process.send(reply, WrongChannelType)
      actor.continue(state)
    }
  }
}

@target(erlang)
fn register_claim_waiter(
  state: State,
  address: String,
  key: String,
  waiter: Subject(claims_kernel.ClaimOutcome),
  immediate_outcome: Option(claims_kernel.ClaimOutcome),
) -> State {
  case immediate_outcome {
    Some(outcome) -> {
      process.send(waiter, outcome)
      state
    }
    None ->
      State(
        ..state,
        claim_waiters: dict.insert(state.claim_waiters, #(address, key), waiter),
      )
  }
}

@target(erlang)
fn resolve_claim_waiters(
  state: State,
  resolutions: List(#(String, Resolution)),
) -> State {
  let claim_waiters =
    list.fold(resolutions, state.claim_waiters, fn(acc, item) {
      let #(address, resolution) = item
      case resolution {
        ClaimResolved(key, outcome) ->
          case dict.get(acc, #(address, key)) {
            Ok(waiter) -> {
              process.send(waiter, outcome)
              dict.delete(acc, #(address, key))
            }
            Error(_) -> acc
          }
        AcquireResolved(_, _) -> acc
      }
    })
  State(..state, claim_waiters: claim_waiters)
}

@target(erlang)
fn abort_outcome_waiters(state: State) -> State {
  dict.values(state.claim_waiters)
  |> list.each(fn(waiter) { process.send(waiter, claims_kernel.Aborted) })
  dict.values(state.acquire_waiters)
  |> list.each(fn(waiter) {
    process.send(waiter, ordered_collection_kernel.Aborted)
  })
  State(..state, claim_waiters: dict.new(), acquire_waiters: dict.new())
}

@target(erlang)
/// Create an acquire id, submit the `Acquire` operation, and reply with that
/// id, so that the caller can complete or release the job later. The acquired
/// item arrives in the sequenced `Acquired` event, because the queue is not
/// optimistic.
fn handle_ordered_acquire(
  state: State,
  address: String,
  reply: Subject(String),
) -> actor.Next(State, Msg) {
  let acquire_id = id.uuid_v4()
  process.send(reply, acquire_id)
  edit(state, fn(core) {
    runtime_core.ordered_acquire(core, address, acquire_id)
  })
}

@target(erlang)
/// The same as `handle_ordered_acquire`, and the function also registers
/// `outcome` to receive the consensus result of the acquire. That result
/// arrives immediately for a detached channel, in the `AcquireResolved`
/// resolution when the operation sequences, or as `Aborted` when the document
/// closes while the acquire is still in flight.
fn handle_ordered_acquire_with_outcome(
  state: State,
  address: String,
  outcome: Subject(ordered_collection_kernel.AcquireOutcome),
  reply: Subject(String),
) -> actor.Next(State, Msg) {
  let acquire_id = id.uuid_v4()
  process.send(reply, acquire_id)
  case state.phase {
    Ready(core, resubmit_at) ->
      case runtime_core.ordered_acquire_submit(core, address, acquire_id) {
        // The core refused the acquire, for example because the address
        // names another kernel. The actor resolves the waiter at once and
        // stays alive.
        Error(_) -> {
          process.send(outcome, ordered_collection_kernel.Aborted)
          actor.continue(state)
        }
        Ok(#(core, events, outbound, immediate_outcome)) -> {
          let state =
            register_acquire_waiter(
              state,
              address,
              acquire_id,
              outcome,
              immediate_outcome,
            )
          case resubmit_at, state.channel {
            None, Some(channel) ->
              send_outbound(Some(channel), core.client_id, outbound)
            _, _ -> Nil
          }
          fan_out(state.subscribers, events)
          actor.continue(State(..state, phase: Ready(core, resubmit_at)))
        }
      }
    Reconnecting(core) ->
      case runtime_core.ordered_acquire_submit(core, address, acquire_id) {
        // The core refused the acquire, for example because the address
        // names another kernel. The actor resolves the waiter at once and
        // stays alive.
        Error(_) -> {
          process.send(outcome, ordered_collection_kernel.Aborted)
          actor.continue(state)
        }
        Ok(#(core, events, _outbound, immediate_outcome)) -> {
          let state =
            register_acquire_waiter(
              state,
              address,
              acquire_id,
              outcome,
              immediate_outcome,
            )
          fan_out(state.subscribers, events)
          actor.continue(State(..state, phase: Reconnecting(core)))
        }
      }
    Connecting(_) | Failed(_) -> {
      process.send(outcome, ordered_collection_kernel.Aborted)
      actor.continue(state)
    }
  }
}

@target(erlang)
fn register_acquire_waiter(
  state: State,
  address: String,
  acquire_id: String,
  waiter: Subject(ordered_collection_kernel.AcquireOutcome),
  immediate_outcome: Option(ordered_collection_kernel.AcquireOutcome),
) -> State {
  case immediate_outcome {
    Some(outcome) -> {
      process.send(waiter, outcome)
      state
    }
    None ->
      State(
        ..state,
        acquire_waiters: dict.insert(
          state.acquire_waiters,
          #(address, acquire_id),
          waiter,
        ),
      )
  }
}

@target(erlang)
fn resolve_acquire_waiters(
  state: State,
  resolutions: List(#(String, Resolution)),
) -> State {
  let acquire_waiters =
    list.fold(resolutions, state.acquire_waiters, fn(acc, item) {
      let #(address, resolution) = item
      case resolution {
        AcquireResolved(acquire_id, outcome) ->
          case dict.get(acc, #(address, acquire_id)) {
            Ok(waiter) -> {
              process.send(waiter, outcome)
              dict.delete(acc, #(address, acquire_id))
            }
            Error(_) -> acc
          }
        ClaimResolved(_, _) -> acc
      }
    })
  State(..state, acquire_waiters: acquire_waiters)
}

@target(erlang)
fn handle_task_volunteer(
  state: State,
  address: String,
  task_id: String,
  reply: Subject(task_manager_kernel.VolunteerOutcome),
) -> actor.Next(State, Msg) {
  case state.phase {
    Ready(core, resubmit_at) ->
      case runtime_core.task_manager_volunteer(core, address, task_id) {
        // The core refused the volunteer, for example because the address
        // names another kernel. The actor reports no assignment and stays
        // alive.
        Error(_) -> {
          process.send(reply, task_manager_kernel.DisconnectedBeforeAssignment)
          actor.continue(state)
        }
        Ok(#(core, events, outbound, outcome)) -> {
          process.send(reply, outcome)
          case resubmit_at, state.channel {
            None, Some(channel) ->
              send_outbound(Some(channel), core.client_id, outbound)
            _, _ -> Nil
          }
          fan_out(state.subscribers, events)
          actor.continue(State(..state, phase: Ready(core, resubmit_at)))
        }
      }
    Reconnecting(core) ->
      case runtime_core.task_manager_volunteer(core, address, task_id) {
        // The core refused the volunteer, for example because the address
        // names another kernel. The actor reports no assignment and stays
        // alive.
        Error(_) -> {
          process.send(reply, task_manager_kernel.DisconnectedBeforeAssignment)
          actor.continue(state)
        }
        Ok(#(core, events, _outbound, outcome)) -> {
          process.send(reply, outcome)
          fan_out(state.subscribers, events)
          actor.continue(State(..state, phase: Reconnecting(core)))
        }
      }
    // The connection is not ready yet, so no assignment can happen.
    Connecting(_) | Failed(_) -> {
      process.send(reply, task_manager_kernel.DisconnectedBeforeAssignment)
      actor.continue(state)
    }
  }
}

@target(erlang)
fn handle_task_complete(
  state: State,
  address: String,
  task_id: String,
  reply: Subject(Result(Nil, String)),
) -> actor.Next(State, Msg) {
  edit_with_result(
    state,
    reply,
    fn(core) { runtime_core.task_manager_complete(core, address, task_id) },
    "complete_task",
  )
}

@target(erlang)
fn edit(
  state: State,
  operate: fn(runtime_core.Core) ->
    Result(
      #(
        runtime_core.Core,
        List(#(String, ChannelEvent)),
        List(wire.OutboundOperation),
      ),
      runtime_core.CoreError,
    ),
) -> actor.Next(State, Msg) {
  case state.phase {
    Ready(core, resubmit_at) -> {
      case operate(core) {
        // The core refused the edit, for example because the address names
        // another kernel, or because the edit is out of bounds. The actor
        // drops the edit and stays alive.
        Error(_) -> actor.continue(state)
        Ok(#(core, events, outbound)) -> {
          // Push immediately only when fully synced with a live channel;
          // otherwise the operation stays in-flight and `resubmit` sends it
          // once, so a reconnect can't drop or duplicate it.
          case resubmit_at, state.channel {
            None, Some(channel) ->
              send_outbound(Some(channel), core.client_id, outbound)
            _, _ -> Nil
          }
          fan_out(state.subscribers, events)
          actor.continue(State(..state, phase: Ready(core, resubmit_at)))
        }
      }
    }
    Reconnecting(core) -> {
      case operate(core) {
        // The core refused the edit, for example because the address names
        // another kernel, or because the edit is out of bounds. The actor
        // drops the edit and stays alive.
        Error(_) -> actor.continue(state)
        Ok(#(core, events, _outbound)) -> {
          fan_out(state.subscribers, events)
          actor.continue(State(..state, phase: Reconnecting(core)))
        }
      }
    }
    // Edits are only reachable through handles returned after await_ready,
    // so this is either a race with a failure or API misuse. The actor drops
    // the edit and stays alive.
    Connecting(_) | Failed(_) -> actor.continue(state)
  }
}

@target(erlang)
fn edit_sequence_with_result(
  state: State,
  reply: Subject(Result(Nil, String)),
  operate: fn(runtime_core.Core) ->
    Result(
      #(
        runtime_core.Core,
        List(#(String, ChannelEvent)),
        List(wire.OutboundOperation),
      ),
      runtime_core.CoreError,
    ),
  verb: String,
) -> actor.Next(State, Msg) {
  case state.phase {
    Ready(core, resubmit_at) ->
      case operate(core) {
        Ok(#(core, events, outbound)) -> {
          process.send(reply, Ok(Nil))
          case resubmit_at, state.channel {
            None, Some(channel) ->
              send_outbound(Some(channel), core.client_id, outbound)
            _, _ -> Nil
          }
          fan_out(state.subscribers, events)
          actor.continue(State(..state, phase: Ready(core, resubmit_at)))
        }
        Error(runtime_core.SequenceOperationFailed(_, detail)) -> {
          process.send(reply, Error(detail))
          actor.continue(state)
        }
        Error(error) -> {
          process.send(
            reply,
            Error(verb <> " failed: " <> string.inspect(error)),
          )
          actor.continue(state)
        }
      }
    Reconnecting(core) ->
      case operate(core) {
        Ok(#(core, events, _outbound)) -> {
          process.send(reply, Ok(Nil))
          fan_out(state.subscribers, events)
          actor.continue(State(..state, phase: Reconnecting(core)))
        }
        Error(runtime_core.SequenceOperationFailed(_, detail)) -> {
          process.send(reply, Error(detail))
          actor.continue(state)
        }
        Error(error) -> {
          process.send(
            reply,
            Error(verb <> " failed: " <> string.inspect(error)),
          )
          actor.continue(state)
        }
      }
    Connecting(_) | Failed(_) -> {
      process.send(
        reply,
        Error(verb <> " before the document connection is ready"),
      )
      actor.continue(state)
    }
  }
}

@target(erlang)
fn edit_text_with_result(
  state: State,
  reply: Subject(Result(Nil, String)),
  operate: fn(runtime_core.Core) ->
    Result(
      #(
        runtime_core.Core,
        List(#(String, ChannelEvent)),
        List(wire.OutboundOperation),
      ),
      runtime_core.CoreError,
    ),
  verb: String,
) -> actor.Next(State, Msg) {
  case state.phase {
    Ready(core, resubmit_at) ->
      case operate(core) {
        Ok(#(core, events, outbound)) -> {
          process.send(reply, Ok(Nil))
          case resubmit_at, state.channel {
            None, Some(channel) ->
              send_outbound(Some(channel), core.client_id, outbound)
            _, _ -> Nil
          }
          fan_out(state.subscribers, events)
          actor.continue(State(..state, phase: Ready(core, resubmit_at)))
        }
        Error(runtime_core.TextOperationFailed(_, detail)) -> {
          process.send(reply, Error(detail))
          actor.continue(state)
        }
        Error(error) -> {
          process.send(
            reply,
            Error(verb <> " failed: " <> string.inspect(error)),
          )
          actor.continue(state)
        }
      }
    Reconnecting(core) ->
      case operate(core) {
        Ok(#(core, events, _outbound)) -> {
          process.send(reply, Ok(Nil))
          fan_out(state.subscribers, events)
          actor.continue(State(..state, phase: Reconnecting(core)))
        }
        Error(runtime_core.TextOperationFailed(_, detail)) -> {
          process.send(reply, Error(detail))
          actor.continue(state)
        }
        Error(error) -> {
          process.send(
            reply,
            Error(verb <> " failed: " <> string.inspect(error)),
          )
          actor.continue(state)
        }
      }
    Connecting(_) | Failed(_) -> {
      process.send(
        reply,
        Error(verb <> " before the document connection is ready"),
      )
      actor.continue(state)
    }
  }
}

@target(erlang)
fn edit_with_result(
  state: State,
  reply: Subject(Result(Nil, String)),
  operate: fn(runtime_core.Core) ->
    Result(
      #(
        runtime_core.Core,
        List(#(String, ChannelEvent)),
        List(wire.OutboundOperation),
      ),
      runtime_core.CoreError,
    ),
  verb: String,
) -> actor.Next(State, Msg) {
  case state.phase {
    Ready(core, resubmit_at) -> {
      case operate(core) {
        Error(runtime_core.TaskNotAssigned(_, task_id)) -> {
          process.send(reply, Error("task is not assigned: " <> task_id))
          actor.continue(state)
        }
        Error(core_error) -> {
          process.send(
            reply,
            Error(verb <> " failed: " <> string.inspect(core_error)),
          )
          actor.continue(state)
        }
        Ok(#(core, events, outbound)) -> {
          process.send(reply, Ok(Nil))
          case resubmit_at, state.channel {
            None, Some(channel) ->
              send_outbound(Some(channel), core.client_id, outbound)
            _, _ -> Nil
          }
          fan_out(state.subscribers, events)
          actor.continue(State(..state, phase: Ready(core, resubmit_at)))
        }
      }
    }
    Reconnecting(core) -> {
      case operate(core) {
        Error(runtime_core.TaskNotAssigned(_, task_id)) -> {
          process.send(reply, Error("task is not assigned: " <> task_id))
          actor.continue(state)
        }
        Error(core_error) -> {
          process.send(
            reply,
            Error(verb <> " failed: " <> string.inspect(core_error)),
          )
          actor.continue(state)
        }
        Ok(#(core, events, _outbound)) -> {
          process.send(reply, Ok(Nil))
          fan_out(state.subscribers, events)
          actor.continue(State(..state, phase: Reconnecting(core)))
        }
      }
    }
    Connecting(_) | Failed(_) -> {
      process.send(
        reply,
        Error(verb <> " requires a ready document connection"),
      )
      actor.continue(state)
    }
  }
}

@target(erlang)
fn read(state: State, default: t, extract: fn(runtime_core.Core) -> t) -> t {
  case state.phase {
    Ready(core, _) -> extract(core)
    Reconnecting(core) -> extract(core)
    Connecting(_) | Failed(_) -> default
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reconnect helpers
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Enter the reconnecting phase after a channel closes. Drop the dead channel
/// and start a new receiver. That receiver does the handshake again, with the
/// last sequence number that this client saw.
fn begin_reconnect(state: State, core: runtime_core.Core) -> State {
  connect_transport(state.transport, state.self)
  notify_session_lost(state)
  State(..state, channel: None, phase: Reconnecting(core))
}

@target(erlang)
/// A nack that permits a retry. Close the channel and enter the reconnecting
/// phase. The `ChannelClosed` message from the receiver then drives the
/// reconnect, so this function does not start a second receiver.
fn reconnect_after_nack(state: State, core: runtime_core.Core) -> State {
  case state.channel {
    Some(channel) -> channel.close()
    None -> Nil
  }
  notify_session_lost(state)
  State(..state, channel: None, phase: Reconnecting(core))
}

@target(erlang)
fn nack_is_fatal(item: Nack) -> Bool {
  case item.content.error_type {
    nack.InvalidScopeError -> True
    nack.LimitExceededError -> True
    nack.ThrottlingError | nack.BadRequestError -> item.content.code == 413
  }
}

@target(erlang)
fn maybe_request_operations(
  channel: Option(TransportHandle),
  request_from: Option(Int),
) -> Nil {
  case channel, request_from {
    Some(channel), Some(from) ->
      push(channel, "requestOps", socket.encode_request_operations(from: from))
    _, _ -> Nil
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summaries
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Schedule an attempt to summarize, if the policy asks for one and no attempt
/// is pending.
///
/// The delay keeps the cost of a room low. Every client crosses the threshold
/// on the same operation. Each client then waits for a different interval,
/// which comes from its id. The first summary that sequences advances
/// `last_summary_sequence_number` on every client, and the rest of the room
/// checks again in `MaybeSummarize` and stops. A lost race costs one
/// unnecessary upload, and nothing more.
fn arm_summary(state: State, core: runtime_core.Core) -> State {
  case state.auto_summary, state.summary_armed {
    Some(policy), False ->
      case runtime_core.wants_summary(core, policy) {
        False -> state
        True -> {
          let _ =
            process.send_after(
              state.self,
              runtime_core.summary_jitter_milliseconds(core, policy),
              MaybeSummarize,
            )
          State(..state, summary_armed: True)
        }
      }
    _, _ -> state
  }
}

@target(erlang)
fn handle_summarize(
  state: State,
  reply: Subject(Result(String, String)),
) -> actor.Next(State, Msg) {
  // Summarizing is only well-defined while fully synced with a live channel:
  // the confirmed state is stable and the summarize operation can go out
  // immediately.
  case state.phase, state.channel {
    Ready(core, None), Some(channel) ->
      case do_summarize(state, core, channel) {
        Ok(#(core, tree_sha)) -> {
          process.send(reply, Ok(tree_sha))
          actor.continue(State(..state, phase: Ready(core, None)))
        }
        Error(reason) -> {
          process.send(reply, Error(reason))
          actor.continue(state)
        }
      }
    Ready(_, None), None
    | Ready(_, Some(_)), _
    | Connecting(_), _
    | Reconnecting(_), _
    | Failed(_), _
    -> {
      process.send(
        reply,
        Error("summarize is only available once the connection is fully synced"),
      )
      actor.continue(state)
    }
  }
}

@target(erlang)
/// Upload the confirmed state as a summary blob. Then stamp the summarize
/// operation that references that blob, and push it. The function returns the
/// new core and the tree SHA.
fn do_summarize(
  state: State,
  core: runtime_core.Core,
  channel: TransportHandle,
) -> Result(#(runtime_core.Core, String), String) {
  use token <- result.try(option.to_result(
    state.connect_message.token,
    "summarize requires an auth token",
  ))
  use _ <- result.try(case runtime_core.is_synced(core) {
    True -> Ok(Nil)
    False ->
      Error(
        "summarize requires the client to be caught up; retry once "
        <> "in-flight edits have been acknowledged",
      )
  })
  use tree_sha <- result.try(
    git_storage.upload_summary(
      base_url: http_base_url(state),
      tenant: state.connect_message.tenant_id,
      token: token,
      sequence_number: core.last_seen_sequence_number,
      members: runtime_core.summary_members(core),
      channels: runtime_core.summary_channels(core),
    )
    |> result.map_error(git_storage.error_to_string),
  )
  let #(core, outbound) =
    runtime_core.build_summarize(
      core,
      handle: tree_sha,
      message: "watershed summary",
      head: tree_sha,
    )
  push(
    channel,
    "submitOp",
    socket.encode_submit_operation(core.client_id, [[outbound]]),
  )
  Ok(#(core, tree_sha))
}

@target(erlang)
/// Close the gap between the seed point of the bootstrap and the earliest
/// operation that the server pushed in band. The function reads the missing
/// prefix from the deltas REST endpoint, one page at a time, until the history
/// has no gap. A bootstrap must not complete on a history with a gap, so every
/// failure here is fatal.
fn complete_bootstrap(
  state: State,
  bootstrapped: runtime_core.Bootstrapped,
) -> runtime_core.Core {
  case bootstrapped {
    runtime_core.Complete(core) -> core
    runtime_core.MissingPrefix(core, checkpoint, from, to) -> {
      let deltas = case fetch_missing_deltas(state, from, to) {
        Ok(deltas) -> deltas
        Error(reason) -> panic as { "history catch-up failed: " <> reason }
      }
      case
        runtime_core.resume_bootstrap(
          core,
          checkpoint: checkpoint,
          deltas: deltas,
        )
      {
        Ok(next) -> complete_bootstrap(state, next)
        Error(core_error) ->
          panic as { "bootstrap failed: " <> string.inspect(core_error) }
      }
    }
  }
}

@target(erlang)
fn fetch_missing_deltas(
  state: State,
  from: Int,
  to: Int,
) -> Result(List(SequencedDocumentMessage), String) {
  case state.connect_message.token {
    None -> Error("history catch-up requires an auth token")
    Some(token) ->
      git_storage.fetch_deltas(
        base_url: http_base_url(state),
        tenant: state.connect_message.tenant_id,
        token: token,
        document: state.connect_message.document_id,
        from: from,
        to: to,
      )
      |> result.map_error(git_storage.error_to_string)
  }
}

@target(erlang)
fn fetch_document_versions(
  state: State,
  count: Int,
) -> Result(List(git_storage.SummaryVersion), String) {
  case state.connect_message.token {
    None -> Error("listing versions requires an auth token")
    Some(token) ->
      git_storage.fetch_versions(
        base_url: http_base_url(state),
        tenant: state.connect_message.tenant_id,
        token: token,
        document: state.connect_message.document_id,
        count: count,
      )
      |> result.map_error(git_storage.error_to_string)
  }
}

@target(erlang)
fn fetch_version_blob(
  state: State,
  handle: String,
) -> Result(summary_blob.SummaryBlob, String) {
  case state.connect_message.token {
    None -> Error("loading a version requires an auth token")
    Some(token) ->
      git_storage.fetch_summary(
        base_url: http_base_url(state),
        tenant: state.connect_message.tenant_id,
        token: token,
        handle: handle,
      )
      |> result.map_error(git_storage.error_to_string)
  }
}

@target(erlang)
fn fetch_summary(
  state: State,
  context: SummaryContext,
) -> Result(runtime_core.Summary, String) {
  case state.connect_message.token {
    None -> Error("loading a summarized document requires an auth token")
    Some(token) ->
      git_storage.fetch_summary(
        base_url: http_base_url(state),
        tenant: state.connect_message.tenant_id,
        token: token,
        handle: context.handle,
      )
      |> result.map_error(git_storage.error_to_string)
      // `context` locates the blob; the blob says what it holds and when it was
      // captured. See `runtime_core.summary_from_blob` for why the context's
      // sequence number is deliberately not the load point.
      |> result.map(runtime_core.summary_from_blob)
  }
}

@target(erlang)
/// The base HTTP or HTTPS URL for the git-storage calls. It comes from the host
/// and the port of the socket. floodgate serves the Phoenix socket and the REST
/// API from the same origin.
fn http_base_url(state: State) -> String {
  "http://" <> state.host <> ":" <> int.to_string(state.port)
}

@target(erlang)
fn send_outbound(
  channel: Option(TransportHandle),
  client_id: String,
  outbound: List(wire.OutboundOperation),
) -> Nil {
  case channel, outbound {
    _, [] -> Nil
    Some(channel), _ ->
      list.each(
        list.sized_chunk(outbound, max_operations_per_submission),
        fn(chunk) {
          push(
            channel,
            "submitOp",
            socket.encode_submit_operation(client_id, [chunk]),
          )
        },
      )
    None, _ -> Nil
  }
}

@target(erlang)
fn push(channel: TransportHandle, event: String, payload: Json) -> Nil {
  channel.push(event, payload)
}

@target(erlang)
/// Route each event to the subscribers that registered for the channel address
/// on that event.
fn fan_out(
  subscribers: List(#(String, fn(ChannelEvent) -> Nil)),
  events: List(#(String, ChannelEvent)),
) -> Nil {
  list.each(events, fn(event) {
    let #(address, event) = event
    list.each(subscribers, fn(subscriber) {
      case subscriber.0 == address {
        True -> subscriber.1(event)
        False -> Nil
      }
    })
  })
}

@target(erlang)
fn fail(state: State, reason: String) -> State {
  let state = abort_outcome_waiters(state)
  notify_waiters(state.phase, Error(reason))
  notify_session_lost(state)
  State(..state, phase: Failed(reason))
}

@target(erlang)
fn notify_presence(state: State, frame: PresenceFrame) -> Nil {
  list.each(state.presence_subscribers, fn(handler) { handler(frame) })
}

@target(erlang)
/// Announce a handshake that settled. The message carries the id and the
/// capability that a driver needs to join.
fn notify_presence_session(state: State, core: runtime_core.Core) -> Nil {
  notify_presence(
    state,
    PresenceSession(
      client_id: core.client_id,
      presence_v1: socket.supports_feature(
        state.supported_features,
        socket.feature_presence_v1,
      ),
    ),
  )
}

@target(erlang)
/// Announce that a live session ended, and only when one was live. A socket
/// that never reached `Ready`, and a socket that the runtime already knows is
/// closed, both hold no presence. The runtime must not report a lost presence
/// two times.
fn notify_session_lost(state: State) -> Nil {
  case state.phase {
    Ready(_, _) -> notify_presence(state, PresenceSessionLost)
    Connecting(_) | Reconnecting(_) | Failed(_) -> Nil
  }
}

@target(erlang)
fn notify_waiters(phase: Phase, result: Result(Nil, String)) -> Nil {
  case phase {
    Connecting(waiters) -> list.each(waiters, process.send(_, result))
    Ready(_, _) | Reconnecting(_) | Failed(_) -> Nil
  }
}

@target(erlang)
fn require(result: Result(t, e), context: String) -> t {
  case result {
    Ok(value) -> value
    Error(error) ->
      panic as {
        "failed to decode " <> context <> ": " <> string.inspect(error)
      }
  }
}

@target(erlang)
fn now_milliseconds() -> Int {
  system_time(Millisecond)
}

@target(erlang)
type TimeUnit {
  Millisecond
}

@target(erlang)
@external(erlang, "os", "system_time")
fn system_time(unit: TimeUnit) -> Int
