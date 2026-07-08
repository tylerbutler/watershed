//// Runtime actor: one per document connection.
////
//// Owns the kernel-bearing `runtime_core` state and the subscriber list.
//// The aquamarine channel is owned by a dedicated receiver process (the
//// transport only delivers to the process that opened it); the receiver
//// forwards every inbound frame to this actor, while pushes are safe from
//// the actor itself.
////
//// Resilience (M4):
////
//// - **Gaps** — out-of-order ops are buffered by `runtime_core`, which asks
////   us to `requestOps` an in-band catch-up; the buffer drains as it fills.
//// - **Reconnect** — a mid-session channel close (or a retryable nack)
////   rejoins and re-handshakes with a fresh client_id, passing
////   `lastSeenSequenceNumber` so the server pushes just the delta. Old ops
////   still in flight are reconciled against the catch-up stream and the
////   remainder resubmitted with fresh CSNs once we reach the reconnect
////   checkpoint. Edits made while (re)connecting are applied optimistically
////   and their push is deferred to that resubmit.
//// - **Nacks** — fatal ones (bad scope, size, hard limit) crash the actor;
////   everything else reconnects and reconciles.
//// - **Heartbeat** — a periodic `noop` advances the server's MSN while idle.

@target(erlang)
import gleam/dict.{type Dict}
@target(erlang)
import gleam/dynamic.{type Dynamic}
@target(erlang)
import gleam/dynamic/decode
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
  type ChannelEvent, type ChannelInit, type Resolution, ClaimResolved,
  InitClaims, InitCounter, InitDirectory, InitGSet, InitJsonOt, InitMap,
  InitOrMap, InitOrSet, InitOrderedCollection, InitPactMap, InitPnCounter,
  InitRegisterCollection, InitTaskManager, InitTwoPSet,
} as _watershed_channel
@target(erlang)
import watershed/claims_kernel
@target(erlang)
import watershed/git_storage
@target(erlang)
import watershed/ids
@target(erlang)
import watershed/json_ot
@target(erlang)
import watershed/or_map_kernel.{type OrMapMode, type OrMapValue}
@target(erlang)
import watershed/register_collection_kernel.{type ReadPolicy}
@target(erlang)
import watershed/runtime_core
@target(erlang)
import watershed/task_manager_kernel
@target(erlang)
import watershed/wire
@target(erlang)
import watershed/wire/socket
@target(erlang)
import watershed/wire/summary_blob

@target(erlang)
const connect_timeout_ms = 10_000

@target(erlang)
const heartbeat_interval_ms = 30_000

@target(erlang)
/// Server nacks submissions above 100 ops; chunk resubmits to stay under it.
const max_ops_per_submission = 100

// ─────────────────────────────────────────────────────────────────────────────
// Transport seam
//
// The runtime talks to levee through an injectable `Transport` rather than
// calling aquamarine directly. The default transport (`aquamarine_transport`)
// reproduces the historical behavior exactly; the in-memory hub (see
// `watershed/hub`) supplies an alternate transport so app authors can run
// deterministic multi-client tests with no server. Every concrete link type
// (an aquamarine `Channel`, a hub subject) is captured inside the closures of
// a `TransportHandle`, so no connection-specific type leaks into `State`/`Msg`
// or the public facade.
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// A live connection's outbound operations. Each function closes over the
/// concrete link, so the runtime holds `TransportHandle` without naming the
/// transport it came from. `push` carries the wire event name and its JSON
/// payload; `close` is an intentional teardown; `drop` forces a reconnect
/// (for the real transport the two coincide).
pub type TransportHandle {
  TransportHandle(
    push: fn(String, Json) -> Nil,
    close: fn() -> Nil,
    drop: fn() -> Nil,
  )
}

@target(erlang)
/// How a transport reports lifecycle and inbound frames back to the runtime
/// actor. The default transport drives these from its receiver process; the
/// hub drives them synchronously on delivery.
pub type TransportCallbacks {
  TransportCallbacks(
    /// The channel joined and is ready to push. Carries the handle used for
    /// all subsequent outbound frames.
    on_ready: fn(TransportHandle) -> Nil,
    /// An inbound frame: the wire event name and its still-`Dynamic` payload.
    on_event: fn(String, Dynamic) -> Nil,
    /// The initial connect/join failed; the runtime treats this as fatal.
    on_fail: fn(String) -> Nil,
    /// A ready session closed; the runtime enters its reconnect path.
    on_close: fn(String) -> Nil,
  )
}

@target(erlang)
/// A pluggable connection to a levee-shaped server. `connect` establishes the
/// link (spawning whatever process it needs) and drives the callbacks; it
/// returns immediately, never blocking the actor.
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
  // Receiver-process lifecycle
  ChannelReady(TransportHandle)
  ChannelFailed(String)
  Inbound(event: String, payload: Dynamic)
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
  CompleteOrderedItem(address: String, acquire_id: String)
  ReleaseOrderedItem(address: String, acquire_id: String)
  SubmitJsonOt(address: String, components: json_ot.Op)
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
  TrySetClaim(
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
  /// Create a new detached map channel: local-only until its handle is first
  /// stored into an attached map. Replies with the generated address.
  CreateMap(reply: Subject(Result(String, String)))
  /// Create a new detached counter channel, same lifecycle as `CreateMap`.
  CreateCounter(reply: Subject(Result(String, String)))
  /// Create a new detached PN-counter channel, same lifecycle as `CreateMap`.
  CreatePnCounter(reply: Subject(Result(String, String)))
  /// Create a new detached PactMap (consensus map) channel, same lifecycle as
  /// `CreateMap`.
  CreatePactMap(reply: Subject(Result(String, String)))
  /// Create a new detached ConsensusOrderedCollection channel, same lifecycle
  /// as `CreateMap`.
  CreateOrderedCollection(reply: Subject(Result(String, String)))
  /// Create a new detached OR-map channel in the requested value mode.
  CreateOrMap(mode: OrMapMode, reply: Subject(Result(String, String)))
  CreateOrSet(reply: Subject(Result(String, String)))
  CreateGSet(reply: Subject(Result(String, String)))
  CreateTwoPSet(reply: Subject(Result(String, String)))
  CreateRegisterCollection(reply: Subject(Result(String, String)))
  CreateClaims(reply: Subject(Result(String, String)))
  CreateJsonOt(reply: Subject(Result(String, String)))
  CreateTaskManager(reply: Subject(Result(String, String)))
  /// Whether a channel exists at `address` (attached or detached). Errors are
  /// retryable — a foreign attach may still be in flight.
  ResolveAddress(address: String, reply: Subject(Result(Nil, String)))
  /// Summarize the current confirmed state to levee storage, replying with the
  /// summary handle (git tree SHA) on success.
  Summarize(reply: Subject(Result(String, String)))
  /// List the document's stored summary versions, newest first.
  GetVersions(
    count: Int,
    reply: Subject(Result(List(git_storage.SummaryVersion), String)),
  )
  /// Read the historical snapshot a summary version captured, by its handle.
  LoadVersion(
    handle: String,
    reply: Subject(Result(summary_blob.SummaryBlob, String)),
  )
  // Reads
  GetValue(address: String, key: String, reply: Subject(Option(Json)))
  /// The counter's optimistic value, `None` when the address is missing or
  /// not a counter channel.
  GetCounterValue(address: String, reply: Subject(Option(Int)))
  /// The PN-counter's optimistic value, `None` when the address is missing or
  /// not a pn-counter channel.
  GetPnCounterValue(address: String, reply: Subject(Option(Int)))
  /// The PactMap's accepted value for `key`, `None` when pending, absent, or
  /// not a PactMap channel.
  GetPactMapValue(address: String, key: String, reply: Subject(Option(Json)))
  /// All keys with an accepted or pending pact in the PactMap at `address`.
  GetPactMapKeys(address: String, reply: Subject(List(String)))
  /// Whether `key` has a pending (proposed but not-yet-accepted) value.
  GetPactMapPending(address: String, key: String, reply: Subject(Bool))
  /// The number of queued (not-yet-acquired) items in the ordered collection at
  /// `address`, `None` when missing or not an ordered-collection channel.
  GetOrderedSize(address: String, reply: Subject(Option(Int)))
  /// The json0 channel's optimistic document, `None` when the address is missing
  /// or not a json0 channel.
  GetJsonOtView(address: String, reply: Subject(Option(json_ot.JsonValue)))
  GetOrMapValue(
    address: String,
    key: String,
    reply: Subject(Option(OrMapValue)),
  )
  GetOrMapEntries(address: String, reply: Subject(List(#(String, OrMapValue))))
  GetOrMapKeys(address: String, reply: Subject(List(String)))
  OrSetContains(address: String, element: String, reply: Subject(Bool))
  GetOrSetValues(address: String, reply: Subject(List(String)))
  GSetContains(address: String, element: String, reply: Subject(Bool))
  GetGSetValues(address: String, reply: Subject(List(String)))
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
    reply: Subject(Option(Json)),
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
    reply: Subject(Option(Json)),
  )
  GetRegisterVersions(
    address: String,
    key: String,
    reply: Subject(Option(List(Json))),
  )
  GetRegisterKeys(address: String, reply: Subject(List(String)))
  GetClaim(address: String, key: String, reply: Subject(Option(Json)))
  HasClaim(address: String, key: String, reply: Subject(Bool))
  TaskAssigned(address: String, task_id: String, reply: Subject(Bool))
  TaskQueued(address: String, task_id: String, reply: Subject(Bool))
  TaskQueues(address: String, reply: Subject(List(#(String, List(Int)))))
  GetEntries(address: String, reply: Subject(List(#(String, Json))))
  GetKeys(address: String, reply: Subject(List(String)))
  GetSize(address: String, reply: Subject(Int))
  /// Whether every local edit has been acknowledged (in-flight queue empty),
  /// so the confirmed state is complete and stable.
  IsSynced(reply: Subject(Bool))
  /// Broadcast an ephemeral, document-scoped ripple (`type` tag + arbitrary
  /// JSON content). Fire-and-forget: no ordering, ack, or catch-up. A no-op
  /// until the handshake assigns a client id.
  SubmitRipple(ripple_type: String, content: Json)
  /// Register a subscriber invoked for every inbound ripple on the document.
  SubscribeRipple(subscriber: fn(SignalMessage) -> Nil)
  // Lifecycle
  Subscribe(address: String, subscriber: fn(ChannelEvent) -> Nil)
  AwaitReady(reply: Subject(Result(Nil, String)))
  /// Fault-injection hook (tests): drop the live channel to force the
  /// runtime through its reconnect/reconcile path.
  DropChannel
  Shutdown
}

@target(erlang)
type Phase {
  Connecting(waiters: List(Subject(Result(Nil, String))))
  /// Socket down and re-handshaking; holds the pre-reconnect core so its
  /// kernel/pending/in-flight survive the round trip.
  Reconnecting(core: runtime_core.Core)
  /// Connected. `resubmit_at` is `Some(checkpoint)` while a reconnect is
  /// still catching up to the point where un-acked ops can be resubmitted,
  /// and `None` once fully synced.
  Ready(core: runtime_core.Core, resubmit_at: Option(Int))
  Failed(reason: String)
}

@target(erlang)
type State {
  State(
    // `host`/`port` are retained for the REST summary API (git-storage), which
    // shares levee's origin. The websocket path/topic/join payload now live
    // inside the transport closure.
    host: String,
    port: Int,
    connect_message: ConnectMessage,
    transport: Transport,
    channel: Option(TransportHandle),
    phase: Phase,
    subscribers: List(#(String, fn(ChannelEvent) -> Nil)),
    ripple_subscribers: List(fn(SignalMessage) -> Nil),
    claim_waiters: Dict(#(String, String), Subject(claims_kernel.ClaimOutcome)),
    self: Subject(Msg),
  )
}

@target(erlang)
/// Start a document runtime against a live levee: spawns the actor and the
/// channel receiver process, then returns the actor subject. Callers should
/// `AwaitReady` (via `process.call`) before editing.
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
/// Start a document runtime against an arbitrary transport. Used by the live
/// `start` (aquamarine) and by the in-memory hub test driver. `host`/`port`
/// only feed the REST summary API and may be placeholders for transports that
/// don't serve one.
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
        claim_waiters: dict.new(),
        self: self,
      )
    let _ = process.send_after(self, heartbeat_interval_ms, Heartbeat)
    connect_transport(transport, self)
    Ok(actor.initialised(state) |> actor.returning(self))
  })
  |> actor.on_message(handle)
  |> actor.start
  |> result.map(fn(started) { started.data })
}

@target(erlang)
/// Block until the handshake completes (or fails).
pub fn await_ready(runtime: Subject(Msg)) -> Result(Nil, String) {
  process.call(runtime, waiting: connect_timeout_ms, sending: AwaitReady)
}

@target(erlang)
/// Summarize the current confirmed state to levee storage. Returns the summary
/// handle (git tree SHA) on success. Requires the connection to be fully synced
/// and the token to carry the `summary:write` scope.
pub fn summarize(runtime: Subject(Msg)) -> Result(String, String) {
  process.call(runtime, waiting: connect_timeout_ms, sending: Summarize)
}

@target(erlang)
/// Whether the client is caught up: every local edit has been acknowledged by
/// the server, so the confirmed state is complete and stable.
pub fn is_synced(runtime: Subject(Msg)) -> Bool {
  process.call(runtime, waiting: connect_timeout_ms, sending: IsSynced)
}

@target(erlang)
pub fn try_set_claim(
  runtime: Subject(Msg),
  address: String,
  key: String,
  value: Json,
) -> ClaimSubmitReply {
  let outcome = process.new_subject()
  process.call(runtime, waiting: connect_timeout_ms, sending: fn(reply) {
    TrySetClaim(address, key, value, outcome, reply)
  })
}

@target(erlang)
pub fn compare_and_set_claim(
  runtime: Subject(Msg),
  address: String,
  key: String,
  value: Json,
) -> ClaimSubmitReply {
  let outcome = process.new_subject()
  process.call(runtime, waiting: connect_timeout_ms, sending: fn(reply) {
    CompareAndSetClaim(address, key, value, outcome, reply)
  })
}

@target(erlang)
pub fn get_claim(
  runtime: Subject(Msg),
  address: String,
  key: String,
) -> Option(Json) {
  process.call(runtime, waiting: connect_timeout_ms, sending: fn(reply) {
    GetClaim(address, key, reply)
  })
}

@target(erlang)
pub fn has_claim(runtime: Subject(Msg), address: String, key: String) -> Bool {
  process.call(runtime, waiting: connect_timeout_ms, sending: fn(reply) {
    HasClaim(address, key, reply)
  })
}

@target(erlang)
pub fn volunteer_task(
  runtime: Subject(Msg),
  address: String,
  task_id: String,
) -> task_manager_kernel.VolunteerOutcome {
  process.call(runtime, waiting: connect_timeout_ms, sending: fn(reply) {
    VolunteerTask(address, task_id, reply)
  })
}

@target(erlang)
pub fn abandon_task(
  runtime: Subject(Msg),
  address: String,
  task_id: String,
) -> Nil {
  process.send(runtime, AbandonTask(address, task_id))
}

@target(erlang)
pub fn complete_task(
  runtime: Subject(Msg),
  address: String,
  task_id: String,
) -> Result(Nil, String) {
  process.call(runtime, waiting: connect_timeout_ms, sending: fn(reply) {
    CompleteTask(address, task_id, reply)
  })
}

@target(erlang)
pub fn task_assigned(
  runtime: Subject(Msg),
  address: String,
  task_id: String,
) -> Bool {
  process.call(runtime, waiting: connect_timeout_ms, sending: fn(reply) {
    TaskAssigned(address, task_id, reply)
  })
}

@target(erlang)
pub fn task_queued(
  runtime: Subject(Msg),
  address: String,
  task_id: String,
) -> Bool {
  process.call(runtime, waiting: connect_timeout_ms, sending: fn(reply) {
    TaskQueued(address, task_id, reply)
  })
}

@target(erlang)
pub fn task_queues(
  runtime: Subject(Msg),
  address: String,
) -> List(#(String, List(Int))) {
  process.call(runtime, waiting: connect_timeout_ms, sending: fn(reply) {
    TaskQueues(address, reply)
  })
}

@target(erlang)
/// List the document's stored summary versions, newest first (the client half
/// of Fluid's `getVersions`). Requires the token to carry `doc:read`.
pub fn get_versions(
  runtime: Subject(Msg),
  count: Int,
) -> Result(List(git_storage.SummaryVersion), String) {
  process.call(runtime, waiting: connect_timeout_ms, sending: fn(reply) {
    GetVersions(count, reply)
  })
}

@target(erlang)
/// Read the historical snapshot a summary version captured, by its handle
/// (from `get_versions` or a `summarize` return). The live document is
/// unaffected — this is a point-in-time read of the stored blob.
pub fn load_version(
  runtime: Subject(Msg),
  handle: String,
) -> Result(summary_blob.SummaryBlob, String) {
  process.call(runtime, waiting: connect_timeout_ms, sending: fn(reply) {
    LoadVersion(handle, reply)
  })
}

// ─────────────────────────────────────────────────────────────────────────────
// Receiver process / transport wiring
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Ask the transport to connect, routing its lifecycle callbacks into actor
/// messages. Called at startup and on every reconnect.
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
/// The default transport: a dedicated receiver process owning one aquamarine
/// channel. `connect` joins (blocking in its own process), announces the
/// handle, then pumps inbound frames until the channel closes.
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
          Error(err) -> callbacks.on_fail(string.inspect(err))
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
      callbacks.on_event(incoming.event, incoming.payload)
      aquamarine_receive_loop(channel, callbacks)
    }
    Error(err) -> callbacks.on_close(string.inspect(err))
  }
}

@target(erlang)
fn aquamarine_push(channel: Channel, event: String, payload: Json) -> Nil {
  case aquamarine.push(channel, event, payload) {
    Ok(Nil) -> Nil
    Error(err) -> panic as { "channel push failed: " <> string.inspect(err) }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Actor
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
fn handle(state: State, msg: Msg) -> actor.Next(State, Msg) {
  case msg {
    Heartbeat -> {
      let _ = process.send_after(state.self, heartbeat_interval_ms, Heartbeat)
      case state.phase, state.channel {
        Ready(core, None), Some(channel) ->
          push(
            channel,
            "noop",
            socket.encode_noop(
              core.client_id,
              reference_sequence_number: core.last_seen_sn,
            ),
          )
        _, _ -> Nil
      }
      actor.continue(state)
    }

    ChannelReady(channel) -> {
      let last_seen = case state.phase {
        Reconnecting(core) -> Some(core.last_seen_sn)
        _ -> None
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
        _ -> actor.continue(fail(state, "channel closed: " <> reason))
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
    CompleteOrderedItem(address, acquire_id) ->
      edit(state, fn(core) {
        runtime_core.ordered_complete(core, address, acquire_id)
      })
    ReleaseOrderedItem(address, acquire_id) ->
      edit(state, fn(core) {
        runtime_core.ordered_release(core, address, acquire_id)
      })
    SubmitJsonOt(address, components) ->
      edit(state, fn(core) {
        runtime_core.submit_json_ot(core, address, components)
      })
    IncrementOrMap(address, key, amount) ->
      edit(state, fn(core) {
        runtime_core.or_map_increment(core, address, key, amount)
      })
    SetOrMapKey(address, key, value) ->
      edit(state, fn(core) {
        runtime_core.or_map_set(core, address, key, value, now_ms())
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
    TrySetClaim(address, key, value, outcome, reply) ->
      handle_claim_submit(state, address, key, outcome, reply, fn(core) {
        runtime_core.try_set_claim(core, address, key, value)
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
      process.send(reply, read(state, None, runtime_core.get(_, address, key)))
      actor.continue(state)
    }
    GetCounterValue(address, reply) -> {
      process.send(
        reply,
        read(state, None, runtime_core.counter_value(_, address)),
      )
      actor.continue(state)
    }
    GetPnCounterValue(address, reply) -> {
      process.send(
        reply,
        read(state, None, runtime_core.pn_counter_value(_, address)),
      )
      actor.continue(state)
    }
    GetPactMapValue(address, key, reply) -> {
      process.send(
        reply,
        read(state, None, runtime_core.pact_map_get(_, address, key)),
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
    GetOrderedSize(address, reply) -> {
      process.send(
        reply,
        read(state, None, runtime_core.ordered_size(_, address)),
      )
      actor.continue(state)
    }
    GetJsonOtView(address, reply) -> {
      process.send(
        reply,
        read(state, None, runtime_core.json_ot_view(_, address)),
      )
      actor.continue(state)
    }
    GetOrMapValue(address, key, reply) -> {
      process.send(
        reply,
        read(state, None, runtime_core.or_map_value(_, address, key)),
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
    DirectoryGet(address, path, key, reply) -> {
      process.send(
        reply,
        read(state, None, runtime_core.directory_get(_, address, path, key)),
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
        read(state, None, runtime_core.register_read(_, address, key, policy)),
      )
      actor.continue(state)
    }
    GetRegisterVersions(address, key, reply) -> {
      process.send(
        reply,
        read(state, None, runtime_core.register_versions(_, address, key)),
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
        read(state, None, runtime_core.get_claim(_, address, key)),
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

    Subscribe(address, subscriber) ->
      actor.continue(
        State(..state, subscribers: [
          #(address, subscriber),
          ..state.subscribers
        ]),
      )

    SubmitRipple(ripple_type, content) -> {
      // Fire-and-forget: push straight to the channel, no kernel/in-flight
      // bookkeeping. No-op until a handshake has assigned a client id.
      let client_id = case state.phase {
        Ready(core, _) -> Some(core.client_id)
        Reconnecting(core) -> Some(core.client_id)
        _ -> None
      }
      case state.channel, client_id {
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
        _ -> actor.continue(state)
      }

    Shutdown -> {
      let state = abort_claim_waiters(state)
      case state.channel {
        Some(channel) -> channel.close()
        None -> Nil
      }
      actor.stop()
    }
  }
}

@target(erlang)
/// Create a detached channel of the given type, replying with its generated
/// address. Detached channels are pure local state, so this works in any
/// connected-ish phase.
fn create_channel(
  state: State,
  reply: Subject(Result(String, String)),
  init: ChannelInit,
  verb: String,
) -> actor.Next(State, Msg) {
  case state.phase {
    Ready(core, resubmit_at) -> {
      let address = ids.uuid_v4()
      let core = runtime_core.create_detached(core, address, init)
      process.send(reply, Ok(address))
      actor.continue(State(..state, phase: Ready(core, resubmit_at)))
    }
    Reconnecting(core) -> {
      let address = ids.uuid_v4()
      let core = runtime_core.create_detached(core, address, init)
      process.send(reply, Ok(address))
      actor.continue(State(..state, phase: Reconnecting(core)))
    }
    _ -> {
      process.send(
        reply,
        Error(verb <> " requires a ready document connection"),
      )
      actor.continue(state)
    }
  }
}

@target(erlang)
fn handle_inbound(
  state: State,
  event: String,
  payload: Dynamic,
) -> actor.Next(State, Msg) {
  case event {
    "connect_document_success" -> {
      let connected =
        require(
          decode.run(payload, socket.connected_message_decoder()),
          "connect_document_success payload",
        )
      case state.phase {
        Connecting(_) -> {
          let summary = case connected.summary_context {
            None -> None
            Some(ctx) ->
              case fetch_summary(state, ctx) {
                Ok(summary) -> Some(summary)
                Error(reason) -> panic as { "summary load failed: " <> reason }
              }
          }
          case runtime_core.bootstrap(connected, summary: summary) {
            Ok(bootstrapped) -> {
              let core = complete_bootstrap(state, bootstrapped)
              notify_waiters(state.phase, Ok(Nil))
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
              core.last_seen_sn,
            )
          settle_reconnect(state, core, checkpoint)
        }
        // A late duplicate success; nothing to do.
        _ -> actor.continue(state)
      }
    }

    "connect_document_error" -> {
      let connect_error =
        require(
          decode.run(payload, socket.connect_error_decoder()),
          "connect_document_error payload",
        )
      actor.continue(fail(state, connect_error.message))
    }

    "op" ->
      case state.phase {
        Ready(core, resubmit_at) -> {
          let #(core, events, resolutions, request_from, released) =
            apply_ops(core, op_message(payload))
          let state = resolve_claim_waiters(state, resolutions)
          fan_out(state.subscribers, events)
          maybe_request_ops(state.channel, request_from)
          send_outbound(state.channel, core.client_id, released)
          case resubmit_at {
            Some(checkpoint) -> settle_reconnect(state, core, checkpoint)
            None -> actor.continue(State(..state, phase: Ready(core, None)))
          }
        }
        // Ops before/without a connected session (or while reconnecting)
        // carry no state we can trust; ignore them.
        _ -> actor.continue(state)
      }

    "nack" -> {
      let nacks =
        require(decode.run(payload, socket.nacks_decoder()), "nack payload")
      case list.any(nacks, nack_is_fatal) {
        True ->
          panic as { "fatal nack from server: " <> string.inspect(payload) }
        False ->
          case state.phase {
            Ready(core, _) -> actor.continue(reconnect_after_nack(state, core))
            // Already tearing the channel down; the pending reconnect covers it.
            _ -> actor.continue(state)
          }
      }
    }

    // Ephemeral ripple broadcast: fan out to ripple subscribers. Malformed
    // payloads are dropped silently — ripples are best-effort.
    "signal" -> {
      case decode.run(payload, socket.ripple_message_decoder()) {
        Error(_) -> Nil
        Ok(ripple) ->
          list.each(state.ripple_subscribers, fn(handler) { handler(ripple) })
      }
      actor.continue(state)
    }

    // Summary events, pongs: not part of the v1 surface.
    _ -> actor.continue(state)
  }
}

@target(erlang)
/// Resubmit un-acked ops once catch-up has reached the reconnect checkpoint;
/// otherwise stay in the catching-up state until more ops arrive.
fn settle_reconnect(
  state: State,
  core: runtime_core.Core,
  checkpoint: Int,
) -> actor.Next(State, Msg) {
  case core.last_seen_sn >= checkpoint {
    True -> {
      let #(core, outbound) = runtime_core.resubmit(core)
      send_outbound(state.channel, core.client_id, outbound)
      actor.continue(State(..state, phase: Ready(core, None)))
    }
    False ->
      actor.continue(State(..state, phase: Ready(core, Some(checkpoint))))
  }
}

@target(erlang)
fn op_message(payload: Dynamic) -> List(SequencedDocumentMessage) {
  let message =
    require(decode.run(payload, socket.op_message_decoder()), "op payload")
  message.ops
}

@target(erlang)
fn apply_ops(
  core: runtime_core.Core,
  ops: List(SequencedDocumentMessage),
) -> #(
  runtime_core.Core,
  List(#(String, ChannelEvent)),
  List(#(String, Resolution)),
  Option(Int),
  List(wire.OutboundOp),
) {
  do_apply_ops(core, ops, [], [], None, [])
}

@target(erlang)
fn do_apply_ops(
  core: runtime_core.Core,
  ops: List(SequencedDocumentMessage),
  events: List(List(#(String, ChannelEvent))),
  resolutions: List(List(#(String, Resolution))),
  request_from: Option(Int),
  released: List(wire.OutboundOp),
) -> #(
  runtime_core.Core,
  List(#(String, ChannelEvent)),
  List(#(String, Resolution)),
  Option(Int),
  List(wire.OutboundOp),
) {
  case ops {
    [] -> #(
      core,
      list.reverse(events) |> list.flatten,
      list.reverse(resolutions) |> list.flatten,
      request_from,
      released,
    )
    [op, ..rest] ->
      case runtime_core.handle_sequenced(core, op) {
        Ok(#(core, ingested)) ->
          do_apply_ops(
            core,
            rest,
            [ingested.events, ..events],
            [ingested.resolutions, ..resolutions],
            option.or(request_from, ingested.request_ops_from),
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
        Error(core_error) ->
          panic as { "claim submit failed: " <> string.inspect(core_error) }
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
        Error(core_error) ->
          panic as { "claim submit failed: " <> string.inspect(core_error) }
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

    _ -> panic as "claim submit before the document connection is ready"
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
      }
    })
  State(..state, claim_waiters: claim_waiters)
}

@target(erlang)
fn abort_claim_waiters(state: State) -> State {
  dict.values(state.claim_waiters)
  |> list.each(fn(waiter) { process.send(waiter, claims_kernel.Aborted) })
  State(..state, claim_waiters: dict.new())
}

@target(erlang)
/// Mint an acquire id, submit the `Acquire` op, and reply with the id so the
/// caller can later complete/release the job. The acquired item itself arrives
/// via the sequenced `Acquired` event (the queue is non-optimistic).
fn handle_ordered_acquire(
  state: State,
  address: String,
  reply: Subject(String),
) -> actor.Next(State, Msg) {
  let acquire_id = ids.uuid_v4()
  process.send(reply, acquire_id)
  edit(state, fn(core) {
    runtime_core.ordered_acquire(core, address, acquire_id)
  })
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
        Error(core_error) ->
          panic as { "task volunteer failed: " <> string.inspect(core_error) }
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
        Error(core_error) ->
          panic as { "task volunteer failed: " <> string.inspect(core_error) }
        Ok(#(core, events, _outbound, outcome)) -> {
          process.send(reply, outcome)
          fan_out(state.subscribers, events)
          actor.continue(State(..state, phase: Reconnecting(core)))
        }
      }
    _ -> panic as "task volunteer before the document connection is ready"
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
      #(runtime_core.Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
      runtime_core.CoreError,
    ),
) -> actor.Next(State, Msg) {
  case state.phase {
    Ready(core, resubmit_at) -> {
      case operate(core) {
        Error(core_error) ->
          panic as { "local edit failed: " <> string.inspect(core_error) }
        Ok(#(core, events, outbound)) -> {
          // Push immediately only when fully synced with a live channel;
          // otherwise the op stays in-flight and `resubmit` sends it once, so a
          // reconnect can't drop or duplicate it.
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
        Error(core_error) ->
          panic as { "local edit failed: " <> string.inspect(core_error) }
        Ok(#(core, events, _outbound)) -> {
          fan_out(state.subscribers, events)
          actor.continue(State(..state, phase: Reconnecting(core)))
        }
      }
    }
    // Edits are only reachable through handles returned after await_ready,
    // so this is either a race with a failure or API misuse.
    _ -> panic as "edit before the document connection is ready"
  }
}

@target(erlang)
fn edit_with_result(
  state: State,
  reply: Subject(Result(Nil, String)),
  operate: fn(runtime_core.Core) ->
    Result(
      #(runtime_core.Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
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
        Error(core_error) ->
          panic as { verb <> " failed: " <> string.inspect(core_error) }
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
        Error(core_error) ->
          panic as { verb <> " failed: " <> string.inspect(core_error) }
        Ok(#(core, events, _outbound)) -> {
          process.send(reply, Ok(Nil))
          fan_out(state.subscribers, events)
          actor.continue(State(..state, phase: Reconnecting(core)))
        }
      }
    }
    _ -> panic as { verb <> " before the document connection is ready" }
  }
}

@target(erlang)
fn read(state: State, default: t, extract: fn(runtime_core.Core) -> t) -> t {
  case state.phase {
    Ready(core, _) -> extract(core)
    Reconnecting(core) -> extract(core)
    _ -> default
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reconnect helpers
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Enter the reconnecting phase after a channel close: drop the dead channel
/// and spawn a fresh receiver, which will re-handshake with our last-seen SN.
fn begin_reconnect(state: State, core: runtime_core.Core) -> State {
  connect_transport(state.transport, state.self)
  State(..state, channel: None, phase: Reconnecting(core))
}

@target(erlang)
/// Retryable nack: close the channel and enter the reconnecting phase. The
/// receiver's resulting `ChannelClosed` drives the actual reconnect, so we
/// don't spawn a second receiver here.
fn reconnect_after_nack(state: State, core: runtime_core.Core) -> State {
  case state.channel {
    Some(channel) -> channel.close()
    None -> Nil
  }
  State(..state, channel: None, phase: Reconnecting(core))
}

@target(erlang)
fn nack_is_fatal(item: Nack) -> Bool {
  case item.content.error_type {
    nack.InvalidScopeError -> True
    nack.LimitExceededError -> True
    _ -> item.content.code == 413
  }
}

@target(erlang)
fn maybe_request_ops(
  channel: Option(TransportHandle),
  request_from: Option(Int),
) -> Nil {
  case channel, request_from {
    Some(channel), Some(from) ->
      push(channel, "requestOps", socket.encode_request_ops(from: from))
    _, _ -> Nil
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summaries
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
fn handle_summarize(
  state: State,
  reply: Subject(Result(String, String)),
) -> actor.Next(State, Msg) {
  // Summarizing is only well-defined while fully synced with a live channel:
  // the confirmed state is stable and the summarize op can go out immediately.
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
    _, _ -> {
      process.send(
        reply,
        Error("summarize is only available once the connection is fully synced"),
      )
      actor.continue(state)
    }
  }
}

@target(erlang)
/// Upload the confirmed state as a summary blob, then stamp and push the
/// summarize op referencing it. Returns the updated core and the tree SHA.
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
  use tree_sha <- result.try(git_storage.upload_summary(
    base_url: http_base_url(state),
    tenant: state.connect_message.tenant_id,
    token: token,
    sequence_number: core.last_seen_sn,
    channels: runtime_core.summary_channels(core),
  ))
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
    socket.encode_submit_op(core.client_id, [[outbound]]),
  )
  Ok(#(core, tree_sha))
}

@target(erlang)
/// Close any gap between the bootstrap seed point and the earliest op the
/// server pushed in-band by paging the missing prefix from the deltas REST
/// endpoint until the history is contiguous. Bootstrap must not complete on
/// a gapped history, so any failure here is fatal.
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
  }
}

@target(erlang)
fn fetch_summary(
  state: State,
  ctx: SummaryContext,
) -> Result(runtime_core.Summary, String) {
  case state.connect_message.token {
    None -> Error("loading a summarized document requires an auth token")
    Some(token) ->
      git_storage.fetch_summary(
        base_url: http_base_url(state),
        tenant: state.connect_message.tenant_id,
        token: token,
        handle: ctx.handle,
      )
      |> result.map(fn(blob) {
        // The summary blob records the SN it was captured at, but the
        // authoritative load point is the server's summaryContext.
        let channels =
          list.map(blob.channels, fn(ch) { #(ch.address, ch.snapshot) })
        runtime_core.Summary(
          sequence_number: ctx.sequence_number,
          channels: channels,
        )
      })
  }
}

@target(erlang)
/// The HTTP(S) base URL for git-storage calls, derived from the socket host
/// and port. levee serves both the Phoenix socket and the REST API from the
/// same origin.
fn http_base_url(state: State) -> String {
  "http://" <> state.host <> ":" <> int.to_string(state.port)
}

@target(erlang)
fn send_outbound(
  channel: Option(TransportHandle),
  client_id: String,
  outbound: List(wire.OutboundOp),
) -> Nil {
  case channel, outbound {
    _, [] -> Nil
    Some(channel), _ ->
      list.each(list.sized_chunk(outbound, max_ops_per_submission), fn(chunk) {
        push(channel, "submitOp", socket.encode_submit_op(client_id, [chunk]))
      })
    None, _ -> Nil
  }
}

@target(erlang)
fn push(channel: TransportHandle, event: String, payload: Json) -> Nil {
  channel.push(event, payload)
}

@target(erlang)
/// Route each address-tagged event to the subscribers registered for that
/// channel address.
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
  let state = abort_claim_waiters(state)
  notify_waiters(state.phase, Error(reason))
  State(..state, phase: Failed(reason))
}

@target(erlang)
fn notify_waiters(phase: Phase, result: Result(Nil, String)) -> Nil {
  case phase {
    Connecting(waiters) -> list.each(waiters, process.send(_, result))
    _ -> Nil
  }
}

@target(erlang)
fn require(result: Result(t, e), context: String) -> t {
  case result {
    Ok(value) -> value
    Error(err) ->
      panic as { "failed to decode " <> context <> ": " <> string.inspect(err) }
  }
}

@target(erlang)
fn now_ms() -> Int {
  system_time(Millisecond)
}

@target(erlang)
type TimeUnit {
  Millisecond
}

@target(erlang)
@external(erlang, "os", "system_time")
fn system_time(unit: TimeUnit) -> Int
