//// The browser-facing CRDT facade: one peer-to-peer document, typed
//// handles onto its channels, and nothing that needs a server.
////
//// This module is the p2p equivalent of `watershed`, and its vocabulary is
//// *separate* on purpose. Every type here is opaque, and none of them shares a
//// constructor with the sequenced facade. Those types are `CrdtDocument`,
//// `Handle`, and `CrdtConnection`. You thus cannot pass a p2p handle to a
//// function that needs a server-backed one, or the reverse. The two stacks
//// have different lifecycles: this one has no ack, no summary, and no client
//// id. To mix them is a type error, and not a surprise at run time.
////
//// ## What `connect` does
////
//// `connect` is synchronous. It builds the configured root with
//// `crdt_core.new` and joins the signaling room before it returns. The
//// document thus exists and accepts an edit from the first frame. There is no
//// sequencer to wait for, and nothing to return later.
////
//// The module reports the readiness exactly one time:
////
//// - The roster of the signaling adapter says that the room was empty, so this
////   replica is alone in it. The document is ready immediately, with the empty
////   configured root.
//// - The roster named one peer or more. The document is ready after one of
////   those peers passes the `hello` check and answers a `stateRequest` with a
////   `state` message that merges.
////
//// Both conditions wait for the *complete* roster, which is the one thing that
//// an adapter must report. See `p2p_transport_js.Signaling`. From inside a
//// replica, "no peer is announced yet" and "the room is empty" look the same.
//// A facade that guessed would give every late joiner an empty document, a
//// moment before the state of the room arrived.
////
//// An adapter that knows the room inside `join`, such as the in-page hub that
//// the tests use, makes this step synchronous. An adapter that learns the room
//// over a round trip, such as `crdt_signaling_js` and every real service,
//// needs a moment longer to become ready. It holds an empty document for
//// exactly that interval, and it announces no document.
////
//// A signaling failure before the readiness resolves that readiness one time,
//// with `Error(SignalingFailed(...))`. That result covers a failure of `join`
//// itself, and a socket that closed before the roster arrived. Everything
//// after the readiness is a `Status` value, and never a second readiness
//// result. That includes a peer that fails its handshake, a room that becomes
//// empty, a merge that the module refuses, and signaling that becomes
//// unavailable.
////
//// One condition waits without an end, and that is deliberate: a room whose
//// members all greet and then send nothing. This replica has neither the state
//// of the room nor a reason to claim that it is alone. "Ready" would thus be
//// incorrect, and "failed" would be incorrect too. An application that wants a
//// limit adds its own timer on `close`, which resolves the readiness one time,
//// with `Error(DocumentClosed)`.
////
//// ## Application callbacks
////
//// `on_ready`, `on_status`, and every subscriber are application code, and this
//// module contains them. It catches an exception from one of them and drops
//// it. That exception thus cannot skip a bootstrap request, suppress a
//// readiness result, or unwind the browser event that delivered a merge. The
//// document, the transport, and the control flow of the protocol are the same
//// whether a callback returns or throws.
////
//// ## Trust boundaries
////
//// Everything that arrives on a data channel is hostile until the module
//// proves otherwise. `crdt_wire` decodes each payload. The module checks that
//// the payload came from the peer that sent it, and that this peer opened with
//// a `hello` message that agrees about the protocol, the room, the
//// compatibility tag, and the root. Only then does `crdt_core` merge that
//// payload. A peer that breaks one of those rules receives the reason, and the
//// module closes and removes that peer, one peer at a time. A refused message
//// never changes the local document, and it never changes the other peers.
////
//// ## Identity
////
//// `replica_label` is a label of the application, and it appears in the status
//// reports only. The identity that writes the CRDT edits and addresses the
//// signaling is `label-<random session id>`, and the module creates it for
//// each connection. Two tabs of one application thus never share an author
//// identity, and a replica that reconnects is a new writer, and not the same
//// writer again.
////
//// JavaScript target only.

@target(javascript)
import gleam/dict.{type Dict}
@target(javascript)
import gleam/int
@target(javascript)
import gleam/json.{type Json}
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{type Option, None, Some}
@target(javascript)
import gleam/result

@target(javascript)
import gleam/string
@target(javascript)
import lattice_sequence/sequence.{After, Before}
@target(javascript)
import watershed/channel.{type ChannelEvent, type ChannelInit, type ChannelType}
@target(javascript)
import watershed/crdt_core
@target(javascript)
import watershed/crdt_sequencer_js
@target(javascript)
import watershed/crdt_wire.{type Message}
@target(javascript)
import watershed/g_set_kernel
@target(javascript)
import watershed/id
@target(javascript)
import watershed/or_map_kernel.{type OrMapValue}
@target(javascript)
import watershed/or_set_kernel
@target(javascript)
import watershed/p2p.{type P2pError}
@target(javascript)
import watershed/p2p_transport_js.{
  type IceServer, type Signaling, type Transport,
}
@target(javascript)
import watershed/pn_counter_kernel
@target(javascript)
import watershed/schema
@target(javascript)
import watershed/sequence_kernel
@target(javascript)
import watershed/text_kernel
@target(javascript)
import watershed/timer_js
@target(javascript)
import watershed/transport_js.{type Cell, type Scheduler}
@target(javascript)
import watershed/two_p_set_kernel
@target(javascript)
import watershed/wire

// ─────────────────────────────────────────────────────────────────────────────
// Configuration
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// Everything that the module needs to build a document and join a room. The
/// phantom `root` type is the channel kind of the root of that document. It
/// travels from the `p2p.CrdtKind` value that you give to `config`, all the way
/// to the handle that `root` returns.
pub opaque type Config(root) {
  Config(
    room: String,
    label: String,
    compatibility: String,
    root: ChannelInit,
    signaling: Signaling,
    ice_servers: List(IceServer),
    policy: TransportPolicy,
    sequencer: Option(SequencerConfig),
    /// The clock that measures every delay of this document. Those delays are
    /// the anti-entropy heartbeat of the mesh, the digest coalescer of the
    /// relay, the reconnect and resync backoff of that relay, and the
    /// readiness deadline of `SequencedOnly`. The default is the real clock. A
    /// test substitutes a logical clock and steps it by hand.
    scheduler: Scheduler,
    /// The anti-entropy interval, which both lanes use. It is the interval at
    /// which the mesh heartbeat checks whether the peers need a digest. It is
    /// also the interval over which the relay path collects the peer digests
    /// while that path is primary. The value is
    /// `default_anti_entropy_milliseconds` unless a caller replaces it.
    anti_entropy_interval_milliseconds: Int,
  )
}

@target(javascript)
/// The transports that a document can use.
///
/// The choice is about *durability and reach*, and never about behaviour. All
/// three policies run the same `crdt_core` document over the same `crdt_wire`
/// envelopes. A snapshot that you export under one policy thus imports under
/// another, and one room can hold replicas of more than one policy at the same
/// time.
pub type TransportPolicy {
  /// Both transports, and each one on its own schedule. The mesh starts by
  /// itself, and the relay starts by itself. The readiness waits for the mesh
  /// only. The relay becomes the durable delta path when it proves that it
  /// works, and not before.
  Auto
  /// The relay only. There is no signaling, no `RTCPeerConnection`, and no
  /// data channel. The readiness waits for the relay, under a bounded
  /// deadline, because there is no other path to be ready on.
  SequencedOnly
  /// The mesh only. The module opens no relay, it schedules no reconnect, and
  /// it ignores a sequencer that the config names. It does not contact that
  /// sequencer.
  P2pOnly
}

@target(javascript)
/// The path that the durable traffic of a document takes now.
pub type TransportPath {
  /// The deltas go to the mesh. Every document starts on this path, and that
  /// includes a document that is about to attach a relay.
  PeerToPeer
  /// The deltas go to the relay. That relay is durable, and it reaches a
  /// replica that this one has no peer connection to. The mesh stays open
  /// below it.
  Sequenced
}

@target(javascript)
/// How to reach an optional sequencer relay, and how long to wait for it. The
/// timing runs on the one scheduler and the one anti-entropy interval of the
/// document, from `with_scheduler` and
/// `with_anti_entropy_interval_milliseconds`. That timing covers the reconnect
/// backoff, the digest coalescer, and the readiness deadline.
pub opaque type SequencerConfig {
  SequencerConfig(
    url: String,
    driver: crdt_sequencer_js.Driver,
    readiness_deadline_milliseconds: Int,
  )
}

@target(javascript)
/// How long `SequencedOnly` waits for a relay to become primary, before it
/// stops. The value is generous. It covers a socket handshake, a capability
/// exchange, a state replay, and a digest round trip.
pub const default_readiness_deadline_milliseconds = 10_000

@target(javascript)
/// The anti-entropy interval, on both lanes.
///
/// This interval is for **anti-entropy, and not for repair**. While the relay
/// is primary, a new delta goes to the relay, and the peers receive a `digest`
/// message. That digest is how a replica that is not on this relay learns that
/// it is behind.
///
/// That digest must not arrive before the fan-out of the same delta from the
/// relay. If it does, every peer answers with a `stateRequest` for a digest
/// that it is about to satisfy, and the room pays for a whole-state transfer on
/// every edit. The digest thus waits. The wait is long enough for an ordinary
/// relay round trip to land first, and short enough that a peer that the relay
/// cannot reach learns the change in an interval that a person calls
/// immediate.
///
/// On the mesh path, the same interval paces the recurring heartbeat. There the
/// interval alone does not keep an idle room quiet. The heartbeat broadcasts
/// only when the digest moves after the last message to the peers. A cadence of
/// one quarter of a second thus costs a quiet mesh nothing, and it gives a mesh
/// that moved a repair in an interval that a person calls immediate.
///
/// The value is one quarter of a second. A caller can replace it, with
/// `with_anti_entropy_interval_milliseconds`. The scheduler of the document
/// measures it, so a test steps that scheduler and does not wait.
///
/// A repair after a failover does not use this interval at all. That repair is
/// a `stateRequest` message to every peer, which the module sends with the
/// fallback, and with no delay.
pub const default_anti_entropy_milliseconds = 250

@target(javascript)
/// A relay at `url`, which uses `crdt_relay_v1` over a real `WebSocket`.
pub fn sequencer(url: String) -> SequencerConfig {
  SequencerConfig(
    url: url,
    driver: crdt_sequencer_js.native_driver(),
    readiness_deadline_milliseconds: default_readiness_deadline_milliseconds,
  )
}

@target(javascript)
/// Replace the socket layer. The deterministic tests attach a scripted relay to
/// this seam. It has the same shape as `p2p_transport_js.Rtc`, for the same
/// reason.
pub fn with_relay_driver(
  config: SequencerConfig,
  driver: crdt_sequencer_js.Driver,
) -> SequencerConfig {
  SequencerConfig(..config, driver: driver)
}

@target(javascript)
/// Change the time that `SequencedOnly` waits. A deadline of zero or less never
/// expires. That value is correct only for a caller that limits the wait
/// itself.
pub fn with_readiness_deadline_milliseconds(
  config: SequencerConfig,
  deadline_milliseconds: Int,
) -> SequencerConfig {
  SequencerConfig(
    ..config,
    readiness_deadline_milliseconds: deadline_milliseconds,
  )
}

@target(javascript)
pub fn sequencer_url(config: SequencerConfig) -> String {
  config.url
}

@target(javascript)
/// Configure a document.
///
/// `room_id` names the signaling room, and the module checks it on every
/// envelope. `replica_label` is a label for a person to read, and nothing else.
/// See the module docs on identity. That label must contain no `:` character,
/// because `:` separates the two halves of a channel address.
/// `compatibility_tag` is the schema version of the application. Two peers
/// whose tags differ refuse each other, and they do not merge two documents
/// that have different meanings.
pub fn config(
  room_id room_id: String,
  replica_label replica_label: String,
  compatibility_tag compatibility_tag: String,
  root root: p2p.CrdtKind(root),
  signaling signaling: Signaling,
) -> Config(root) {
  Config(
    room: room_id,
    label: replica_label,
    compatibility: compatibility_tag,
    root: p2p.kind_init(root),
    signaling: signaling,
    ice_servers: [],
    policy: Auto,
    sequencer: None,
    scheduler: transport_js.real_scheduler(),
    anti_entropy_interval_milliseconds: default_anti_entropy_milliseconds,
  )
}

@target(javascript)
/// Select the transports that this document can use. The default is `Auto`.
pub fn with_transport_policy(
  config: Config(root),
  policy: TransportPolicy,
) -> Config(root) {
  Config(..config, policy: policy)
}

@target(javascript)
/// Attach an optional sequencer relay. The module ignores this relay under
/// `P2pOnly`, and it requires one under `SequencedOnly`. A `SequencedOnly`
/// document with no sequencer fails its readiness one time, with
/// `SequencerUnavailable`. It does not wait for a component that no caller
/// configured.
pub fn with_sequencer(
  config: Config(root),
  sequencer: SequencerConfig,
) -> Config(root) {
  Config(..config, sequencer: Some(sequencer))
}

@target(javascript)
/// Supply the STUN servers and TURN servers that the peer connections are built
/// with. watershed supplies none. An empty list is correct for a LAN and for a
/// same-origin loopback. The application supplies every other server.
pub fn with_ice_servers(
  config: Config(root),
  servers: List(IceServer),
) -> Config(root) {
  Config(..config, ice_servers: servers)
}

@target(javascript)
/// Replace the clock that measures every delay of this document. Those delays
/// are the mesh heartbeat, the coalescer of the relay, the reconnect and resync
/// backoff of that relay, and the readiness deadline. A test thus steps a
/// logical clock, and it does not wait for the real time.
pub fn with_scheduler(
  config: Config(root),
  scheduler: Scheduler,
) -> Config(root) {
  Config(..config, scheduler: scheduler)
}

@target(javascript)
/// Change the anti-entropy interval. That interval is the cadence of the mesh
/// heartbeat, and it is the period over which the relay path collects the peer
/// digests while that path is primary. An interval of zero or less still goes
/// through the scheduler, and the module does not send the message
/// immediately.
pub fn with_anti_entropy_interval_milliseconds(
  config: Config(root),
  interval_milliseconds: Int,
) -> Config(root) {
  Config(..config, anti_entropy_interval_milliseconds: interval_milliseconds)
}

@target(javascript)
/// The signaling room that this config joins.
pub fn config_room(config: Config(root)) -> String {
  config.room
}

@target(javascript)
/// The compatibility tag of the application that this config applies.
pub fn config_compatibility(config: Config(root)) -> String {
  config.compatibility
}

// ─────────────────────────────────────────────────────────────────────────────
// Documents, handles, connections
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// A live CRDT document. One cell holds all of it: the pure
/// `crdt_core.Document` value, the transport, the peer table, and the list of
/// subscribers. Every handle, subscription, and callback on that document thus
/// sees the same state, for the whole life of the connection.
pub opaque type CrdtDocument(root) {
  CrdtDocument(cell: Cell(State))
}

@target(javascript)
/// A typed reference to one channel of a document. `kind` is the phantom
/// channel-kind tag from `watershed/schema`. You thus cannot apply an OR-set
/// operation to a text handle.
pub opaque type Handle(kind) {
  Handle(cell: Cell(State), address: String)
}

@target(javascript)
/// What a document holds on the signaling and on its peers. `close` releases
/// it.
pub opaque type CrdtConnection {
  CrdtConnection(cell: Option(Cell(State)))
}

@target(javascript)
/// An event subscription for one address, which a caller can remove.
pub opaque type Subscription {
  Subscription(cell: Cell(State), id: Int)
}

@target(javascript)
/// A stable position in the optimistic string of a text channel. It stays
/// correct across concurrent edits and merges. The type is opaque. Construct
/// one with `text_anchor_at`, `text_start_anchor`, or `text_end_anchor`, or
/// decode one with `text_anchor_from_json`.
pub type TextAnchor =
  text_kernel.TextAnchor

@target(javascript)
/// The grapheme that a `TextAnchor` value binds to across a concurrent insert
/// at its gap. `Before` binds it to the grapheme after the gap, so an insert at
/// the gap moves the anchor to the right. `After` binds it to the grapheme
/// before the gap, so an insert at the gap goes after the anchor. This type is
/// re-exported here, so a caller needs no direct dependency on
/// `lattice_sequence` to build an anchor.
pub type Bias =
  text_kernel.Bias

@target(javascript)
pub const bias_before: Bias = Before

@target(javascript)
pub const bias_after: Bias = After

@target(javascript)
type State {
  State(
    label: String,
    signaling: Signaling,
    ice_servers: List(IceServer),
    document: crdt_core.Document,
    /// The value is `None` until `attach` has a transport, and `None` again
    /// after `close`.
    transport: Option(Transport),
    peers: Dict(String, Peer),
    subscriptions: List(Subscriber),
    next_subscription: Int,
    on_status: fn(Status) -> Nil,
    /// `attach` sets this field. The closure holds the typed document, so
    /// `State` itself does not carry the root tag.
    on_ready: fn(Result(Nil, P2pError)) -> Nil,
    /// The value is `None` until the readiness resolves. After that it is the
    /// result that the module delivered. "Exactly one time" is thus a fact
    /// about the state, and not a promise about the code.
    readiness: Option(Result(Nil, P2pError)),
    /// The module sets this flag when the adapter reports the complete
    /// membership of the room. Before that, this replica cannot separate an
    /// empty room from a room that has not answered, and it must not conclude
    /// that it is alone.
    roster: Bool,
    bootstrap: BootstrapState,
    /// The transport callbacks that ran from inside `p2p_transport_js.start`,
    /// before that call returned the transport that they need to answer. The
    /// list holds the newest one first. The module runs them in arrival order,
    /// at the moment that it stores the transport.
    deferred: List(Deferred),
    /// The module loaded this document from an imported snapshot, and it did
    /// not build it from the configured root only. A synchronous refusal of an
    /// attach thus leaves this document detached, and the restored local state
    /// stays usable.
    imported: Bool,
    attached: Bool,
    closed: Bool,
    policy: TransportPolicy,
    sequencer: Option(SequencerConfig),
    /// The relay lane, after `attach` opens one. The value is `None` under
    /// `P2pOnly`, under `Auto` with no sequencer in the config, and after
    /// `close`.
    relay: Option(crdt_sequencer_js.Relay),
    phase: RelayPhase,
    /// The path that the durable traffic takes. The module changes this field
    /// *before* the status that reports the change. A handler that reads the
    /// field thus agrees with the status that it just received.
    path: TransportPath,
    /// The digest of the state that the module last published to the relay. It
    /// is the only digest that an attestation echo is compared against.
    published: String,
    /// The number of consecutive attestations that returned an empty echo. The
    /// resync backoff uses that number as its index.
    resyncs: Int,
    /// The function that cancels a scheduled resync.
    resync_timer: Option(fn() -> Nil),
    /// Whether this document changed after the peers last received its digest.
    /// Every mutation sets this flag, and so does every relayed merge that
    /// moved the document. The flush that sends the digest clears it.
    nudge_dirty: Bool,
    /// Whether an anti-entropy flush is armed already. There is one digest for
    /// each interval while the relay is primary, whatever number of edits that
    /// interval held.
    nudge_armed: Bool,
    /// The function that cancels the armed digest flush.
    nudge_timer: Option(fn() -> Nil),
    /// Whether a merge that this replica learned from a *peer* moved the
    /// canonical state, and the relay does not know about that change. The
    /// relay carries the durability of the room, and a delta from a peer
    /// reaches that relay through no other route. The same coalesced flush
    /// that digests the mesh thus publishes the merged state to the relay
    /// again. That flush clears this flag, and so does a fallback. A lane that
    /// comes back publishes everything that it holds during its handshake.
    publish_owed: Bool,
    /// The one clock that measures every delay: the mesh heartbeat, the
    /// coalescer and the backoff of the relay, and the readiness deadline. This
    /// field also holds the anti-entropy interval that both lanes share.
    scheduler: Scheduler,
    anti_entropy_interval_milliseconds: Int,
    /// Whether a mesh anti-entropy digest is armed already. There is one
    /// digest for each interval on the WebRTC path, whatever number of merges
    /// that interval held.
    ///
    /// This field is separate from the `nudge_*` fields, which are the
    /// coalescer of the relay path. The two are never armed at the same time.
    /// The transport path is one or the other, and a failover cancels the
    /// coalescer of the relay before this heartbeat starts.
    sync_armed: Bool,
    /// The function that cancels the armed mesh digest flush.
    sync_timer: Option(fn() -> Nil),
    /// The digest that the module last announced to the peers. The value is
    /// `""` when those peers need a new one.
    ///
    /// This field is the gate of the heartbeat. A beat whose digest still
    /// equals this value broadcasts nothing. An idle mesh that converged thus
    /// becomes quiet, and it does not repeat itself in every interval. A digest
    /// from a peer that does not match clears this field, so a replica that is
    /// *ahead* continues to announce until the room catches up.
    last_sync_digest: String,
    /// The number of times that the digest of a peer told this replica that it
    /// was behind, and this replica then asked for the state. That number
    /// counts the partition-repair activity of the mesh.
    repairs: Int,
    /// The last peer digest that equalled the digest of this replica, if one
    /// exists. That value is a successful anti-entropy comparison, for
    /// diagnostics.
    last_match: Option(String),
    /// The canonical digest that this document already computed, with the
    /// document that it was computed from.
    ///
    /// This value has its own cell, and it is not a field of `State`. Every
    /// write to `State` is a `State(..state, ...)` expression, from a snapshot
    /// that the function read earlier. A memo that the code stored between that
    /// read and that write would thus disappear, and nothing would report it. A
    /// cell is one box that every snapshot shares.
    digest_cache: Cell(DigestCache),
    /// The function that cancels the readiness deadline of `SequencedOnly`.
    deadline: Option(fn() -> Nil),
    /// Whether the relay has ever been primary. That fact makes a later
    /// attachment a recovery, and not a first attachment.
    recovered: Bool,
  )
}

@target(javascript)
/// A canonical digest, with the document that it describes.
///
/// To canonicalize and hash a document costs time in proportion to the size of
/// that document. The code projects every channel snapshot, it sorts every key
/// and every set-shaped array into UTF-8 byte order, and it hashes the result.
/// The anti-entropy heartbeat asks for a digest in every interval, every
/// received `Digest` message is compared against one, and the relay lane
/// publishes, attests, and reports with one. In the usual case, all of those
/// requests describe a document that did not change after the previous
/// request.
///
/// The module thus keeps the answer, keyed on the document that produced it. A
/// `crdt_core.Document` value is immutable. The same reference is the same
/// state, and every transition returns a new value, which cannot match the old
/// key. Those transitions are a local edit, a merge, a channel creation, and an
/// import. There is thus no invalidation list to keep correct as the code
/// changes, and no state change that such a list can miss.
type DigestCache {
  DigestCache(
    /// The document that the code computed `value` from. The field is `None`
    /// before the first computation.
    taken_from: Option(crdt_core.Document),
    value: String,
    /// The number of times that this document canonicalized and hashed itself.
    /// A cache hit does not add to this count. `digest_computations` is thus
    /// evidence, and not an estimate.
    computations: Int,
  )
}

@target(javascript)
/// The position of the relay lane in its lifecycle. This value is separate from
/// the transport path. A relay can synchronize while WebRTC still carries the
/// deltas, and every attachment passes through that state.
type RelayPhase {
  /// There is no relay. The config names none, or the policy refuses one.
  RelayOff
  /// The lane opens a socket, or it opens one again after a drop.
  RelayOpening
  /// The relay accepted the capability, and the state handshake runs now.
  RelaySyncing
  /// The local digest and the relay digest are equal. The relay is the delta
  /// path.
  RelayPrimaryPhase
  /// The endpoint answered, and it does not support `crdt_relay_v1`. This
  /// phase is terminal.
  RelayUnsupportedPhase
}

@target(javascript)
/// A peer with an open document channel. A `hello` message that passes every
/// compatibility check sets `greeted`. Before that, the peer can send nothing
/// else.
type Peer {
  Peer(id: String, greeted: Bool)
}

@target(javascript)
/// The progress of this replica through a join into a room. The value reports
/// whether the replica still needs the state of a peer before it can become
/// ready. `bootstrap_state` gives it, as a diagnostic.
pub type BootstrapState {
  /// The replica joined the room. The roster has not arrived yet, or no peer
  /// passed its checks yet.
  Joining
  WaitingForState(peer_id: String)
  Bootstrapped
}

@target(javascript)
type Deferred {
  DeferredOpen(peer_id: String)
  DeferredDocument(peer_id: String, payload: String)
  DeferredClose(peer_id: String)
}

@target(javascript)
type Subscriber {
  Subscriber(id: Int, address: String, handler: fn(ChannelEvent) -> Nil)
}

// ─────────────────────────────────────────────────────────────────────────────
// Status
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// What a connection reports while it runs. `Transport` carries the transport
/// lifecycle, without a change. Every other constructor is at the document
/// level.
pub type Status {
  /// A `p2p_transport_js.Status` value, without a change. It reports the
  /// signaling membership, the peer connection state, the ICE state, and the
  /// number of open peers.
  Transport(status: p2p_transport_js.Status)
  /// A typed error that the transport reported, before that error reached a
  /// document.
  TransportError(error: P2pError)
  /// The module asked the signaling service to join. The document exists, and
  /// it accepts an edit.
  Joined(room: String, replica: String)
  /// The complete membership of the room, as the signaling adapter reported
  /// it. A replica is not ready before this status arrives. Before that, an
  /// empty peer list means "no client is announced", and it does not mean "no
  /// client is here".
  RosterKnown(peers: List(String))
  /// The replica waits for `peer_id` to answer the bootstrap `stateRequest`
  /// message.
  AwaitingState(peer_id: String)
  /// The readiness resolved with a success. The module emits this status
  /// before `on_ready` runs, and `readiness` already holds the result. A status
  /// handler and the readiness callback thus never disagree about the state of
  /// the document.
  Ready
  /// A peer completed the `hello` handshake.
  PeerReady(peer_id: String)
  /// The document channel of a peer closed.
  PeerGone(peer_id: String)
  /// The module closed a peer for the named protocol violation. The local
  /// document does not change, and no other peer changes.
  PeerRejected(peer_id: String, error: P2pError)
  /// A `state` message from `peer_id` merged, with `channels` channels. This
  /// status reports the bootstrap transfer, and it reports a later repair.
  StateMerged(peer_id: String, channels: Int)
  /// A peer reported that *it* refused something from this replica, with the
  /// reason and the detail of the protocol. Nothing local changed. This message
  /// is the one message that explains a link that is about to close, so the
  /// module reports it and does not drop it.
  RejectedByPeer(peer_id: String, reason: String, detail: String)
  /// A local operation failed. The module reports this status with the
  /// `Result` value that the caller already has, so a status log gives the
  /// whole account.
  Failed(error: P2pError)
  /// A subscriber callback threw an exception. The document and the transport
  /// are correct. The module reports that exception, and it does not hide
  /// it.
  SubscriberFailed(address: String, detail: String)
  /// The module opens a relay lane. There is one of these statuses for each
  /// attempt, so a reconnect sequence gives one of them for each
  /// `RelayRetry`.
  RelayConnecting(url: String)
  /// The endpoint answered, and it does not support `crdt_relay_v1`. Under
  /// `Auto` that is the whole result, and the document stays on WebRTC. Under
  /// `SequencedOnly` it is also the failure of the readiness.
  RelayUnsupported(detail: String)
  /// The relay accepted the capability, and the state handshake runs now. That
  /// handshake is a `hello` message, a `stateRequest` message, a merge, a
  /// publication, and a digest. The deltas still go to the mesh while it
  /// runs.
  RelaySyncingStatus
  /// The same handshake, after the relay was already primary one time. A
  /// recovery merges the edits of an outage, from both sides, before it can
  /// make a claim.
  RelayRecovering
  /// The local digest and the relay digest are equal. The relay is now the
  /// durable delta path. `path` already reads `Sequenced` when this status
  /// arrives.
  RelayPrimary(digest: String)
  /// The relay asked this client to checkpoint, because its live log
  /// approaches the bound at which it must start to refuse traffic. The answer
  /// is a publication of the current merged state, with an attestation of that
  /// state. Nothing about the document changes, and no code reads a number that
  /// the relay sent. This status carries no such number either.
  RelayCheckpointRequested
  /// A requested checkpoint completed. The relay echoed the digest of the state
  /// that this replica published, so the relay compacted the ordinary history
  /// of the room down to that state.
  RelayCheckpointed(digest: String)
  /// The relay is gone, and WebRTC is the delta path again. `path` already
  /// reads `PeerToPeer` when this status arrives. A mutation that races the
  /// drop is thus safe.
  RelayFallback(detail: String)
  /// The module armed a reconnect, `delay_milliseconds` milliseconds from now.
  RelayRetry(delay_milliseconds: Int)
  /// The module refused one envelope from the relay, and the local document
  /// did not change. One replica that behaves incorrectly does not cost the
  /// lane. Unlike a peer, this module cannot close a relay client. To close the
  /// relay would remove the lane from every other replica on it.
  RelayRejected(from: String, error: P2pError)
  /// The relay lane itself failed. That failure is a socket that did not open,
  /// a malformed frame, or a refusal from the service.
  RelayFailed(error: P2pError)
}

@target(javascript)
@external(javascript, "./crdt_js_ffi.mjs", "guard")
fn guard(work: fn() -> Nil, on_error: fn(String) -> Nil) -> Nil

@target(javascript)
/// Whether two documents are the same immutable value, by reference. The
/// `crdt_core.Document` type is opaque, and `==` would walk it. That walk is
/// the work that the digest cache removes.
@external(javascript, "./crdt_js_ffi.mjs", "sameDocument")
fn same_document(left: crdt_core.Document, right: crdt_core.Document) -> Bool

// ─────────────────────────────────────────────────────────────────────────────
// The canonical digest, computed once per document state
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// The canonical digest of this document. The function computes it when the
/// document moved after the last digest, and it reuses the earlier value when
/// the document did not move.
///
/// Every digest that this facade uses goes through this function: the mesh
/// heartbeat, the coalesced digest of the relay, the comparison against the
/// digest of a peer, the publication with its attestation, and the public
/// `digest` function. There is thus one canonicalization for each document
/// state, whatever number of callers ask for it. The cache uses the document
/// itself as its key, so a state change cannot leave a stale digest. Such a
/// change misses the cache.
fn document_digest(cell: Cell(State)) -> String {
  let state = transport_js.get_cell(cell)
  let cache = transport_js.get_cell(state.digest_cache)
  let hit = case cache.taken_from {
    Some(document) ->
      case same_document(document, state.document) {
        True -> Some(cache.value)
        False -> None
      }
    None -> None
  }
  case hit {
    Some(value) -> value
    None -> {
      let value = crdt_core.digest(state.document)
      transport_js.set_cell(
        state.digest_cache,
        DigestCache(
          taken_from: Some(state.document),
          value: value,
          computations: cache.computations + 1,
        ),
      )
      value
    }
  }
}

@target(javascript)
/// `crdt_core.digest_message`, from the digest that this document already
/// computed. The message is the same in both routes. This function removes the
/// hash step only.
fn digest_message(cell: Cell(State)) -> Message {
  crdt_wire.Digest(document_digest(cell))
}

// ─────────────────────────────────────────────────────────────────────────────
// Lifecycle
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// Build the document that a `Config` value describes, and join nothing.
///
/// The function creates the root from the config, and it never learns that root
/// from a peer. Two replicas that agree on the config thus agree on the root
/// before they exchange a message. Give the result to `attach` to connect
/// it.
pub fn new_document(
  config: Config(root),
) -> Result(CrdtDocument(root), P2pError) {
  let session = id.uuid_v4()
  let replica = config.label <> "-" <> session
  let core =
    crdt_core.config(
      room: config.room,
      compatibility: config.compatibility,
      replica: replica,
      session: session,
      root: config.root,
    )
  use document <- result.try(crdt_core.new(core))
  Ok(
    CrdtDocument(
      cell: transport_js.new_cell(State(
        label: config.label,
        signaling: config.signaling,
        ice_servers: config.ice_servers,
        document: document,
        transport: None,
        peers: dict.new(),
        subscriptions: [],
        next_subscription: 0,
        on_status: fn(_) { Nil },
        on_ready: fn(_) { Nil },
        readiness: None,
        roster: False,
        bootstrap: Joining,
        deferred: [],
        imported: False,
        attached: False,
        closed: False,
        policy: config.policy,
        sequencer: config.sequencer,
        relay: None,
        phase: RelayOff,
        path: PeerToPeer,
        published: "",
        resyncs: 0,
        resync_timer: None,
        nudge_dirty: False,
        nudge_armed: False,
        nudge_timer: None,
        publish_owed: False,
        scheduler: config.scheduler,
        anti_entropy_interval_milliseconds: config.anti_entropy_interval_milliseconds,
        sync_armed: False,
        sync_timer: None,
        last_sync_digest: "",
        repairs: 0,
        last_match: None,
        digest_cache: transport_js.new_cell(DigestCache(
          taken_from: None,
          value: "",
          computations: 0,
        )),
        deadline: None,
        recovered: False,
      )),
    ),
  )
}

@target(javascript)
/// Build the configured document and join its room.
///
/// The function returns after it asks the signaling service to join.
/// `on_ready` runs exactly one time. The module docs describe the conditions.
/// `on_status` runs for the whole life of the connection.
pub fn connect(
  config: Config(root),
  on_ready on_ready: fn(Result(CrdtDocument(root), P2pError)) -> Nil,
  on_status on_status: fn(Status) -> Nil,
) -> CrdtConnection {
  case new_document(config) {
    Error(error) -> {
      contained(fn() { on_status(Failed(error)) })
      contained(fn() { on_ready(Error(error)) })
      CrdtConnection(cell: None)
    }
    Ok(document) -> attach(document, on_ready, on_status)
  }
}

@target(javascript)
/// Run one application callback, and do not let an exception from it enter the
/// call stack of the protocol. The contract of this facade is that a callback
/// cannot change what the document does, and cannot change what the transport
/// does.
fn contained(work: fn() -> Nil) -> Nil {
  guard(work, fn(_detail) { Nil })
}

@target(javascript)
/// Join a room with a document that already exists. `connect` uses this
/// function internally, and it is also the way to bring the result of
/// `import_snapshot` online.
///
/// The document keeps its cell. A handle and a subscription that you took
/// before the attach thus stay valid. The channels of the snapshot go to the
/// peers in the ordinary `state` exchange. A synchronous refusal at startup
/// leaves a restored snapshot detached, so its local state stays editable and
/// the caller can try again.
pub fn attach(
  document: CrdtDocument(root),
  on_ready on_ready: fn(Result(CrdtDocument(root), P2pError)) -> Nil,
  on_status on_status: fn(Status) -> Nil,
) -> CrdtConnection {
  attach_with_rtc(
    document,
    on_ready: on_ready,
    on_status: on_status,
    rtc: p2p_transport_js.real_rtc(),
  )
}

@target(javascript)
/// `attach` against a replacement browser seam. A test can thus drive the
/// bootstrap order, a handshake refusal, and the merge behaviour
/// deterministically, and it needs no browser. This is the same seam that
/// `p2p_transport_js.start_with_rtc` gives, for the same reason.
pub fn attach_with_rtc(
  document: CrdtDocument(root),
  on_ready on_ready: fn(Result(CrdtDocument(root), P2pError)) -> Nil,
  on_status on_status: fn(Status) -> Nil,
  rtc rtc: p2p_transport_js.Rtc,
) -> CrdtConnection {
  let cell = document.cell
  let state = transport_js.get_cell(cell)
  let room = crdt_core.room(state.document)
  let replica = crdt_core.replica(state.document)
  case state.closed, state.attached {
    True, _ -> {
      contained(fn() { on_status(Failed(p2p.DocumentClosed)) })
      contained(fn() { on_ready(Error(p2p.DocumentClosed)) })
      CrdtConnection(cell: None)
    }
    False, True -> {
      let error =
        p2p.InvalidEnvelope(
          replica,
          "document is already attached to a connection",
        )
      contained(fn() { on_status(Failed(error)) })
      contained(fn() { on_ready(Error(error)) })
      CrdtConnection(cell: None)
    }
    False, False -> {
      transport_js.set_cell(
        cell,
        State(
          ..state,
          attached: True,
          on_status: on_status,
          on_ready: fn(outcome) {
            case outcome {
              Ok(Nil) -> on_ready(Ok(document))
              Error(error) -> on_ready(Error(error))
            }
          },
        ),
      )
      emit(cell, Joined(room: room, replica: replica))
      case state.policy {
        // No mesh at all: no signaling join, no `RTCPeerConnection`, no
        // data channel. Readiness belongs entirely to the relay, under a
        // deadline, because nothing else can resolve it.
        SequencedOnly ->
          case state.sequencer {
            None -> {
              let error =
                p2p.SequencerUnavailable(
                  "sequencedOnly needs a sequencer, and none was configured",
                )
              fail_attach_attempt(cell, error)
              CrdtConnection(cell: None)
            }
            Some(_) -> {
              arm_deadline(cell)
              start_relay(cell)
              CrdtConnection(cell: Some(cell))
            }
          }
        Auto | P2pOnly ->
          case
            p2p_transport_js.start_with_rtc(
              room: room,
              peer_id: replica,
              signaling: state.signaling,
              ice_servers: state.ice_servers,
              callbacks: callbacks(cell),
              rtc: rtc,
            )
          {
            Error(error) -> {
              fail_attach_attempt(cell, error)
              CrdtConnection(cell: None)
            }
            Ok(transport) -> {
              let joined = transport_js.get_cell(cell)
              transport_js.set_cell(
                cell,
                State(..joined, transport: Some(transport), deferred: []),
              )
              list.each(list.reverse(joined.deferred), fn(entry) {
                run_deferred(cell, entry)
              })
              // An adapter that reported its roster from inside `join` has
              // already told this replica whether the room was empty; one
              // that has not will, and readiness waits for it.
              settle_readiness(cell)
              // Concurrently, and never before: the mesh has had its
              // chance to resolve readiness by the time the relay is
              // even asked for a socket, so `Auto` keeps exactly the
              // no-sequencer readiness behaviour it had without one.
              start_relay(cell)
              CrdtConnection(cell: Some(cell))
            }
          }
      }
    }
  }
}

@target(javascript)
/// Leave the signaling room, close every peer, and stop the document from
/// accepting a read or a write. A second call has no more effect.
///
/// A close before the readiness resolves `on_ready` one time, with
/// `Error(DocumentClosed)`. A caller that waits on that callback needs an
/// answer, also when the answer is that the module abandoned the document.
pub fn close(connection: CrdtConnection) -> Nil {
  case connection.cell {
    None -> Nil
    Some(cell) -> {
      let state = transport_js.get_cell(cell)
      case state.closed {
        True -> Nil
        False -> {
          mark_closed(cell)
          case state.transport {
            Some(transport) -> p2p_transport_js.close(transport)
            None -> Nil
          }
          case state.relay {
            Some(relay) -> crdt_sequencer_js.close(relay)
            None -> Nil
          }
          resolve_ready(cell, Error(p2p.DocumentClosed))
        }
      }
    }
  }
}

@target(javascript)
fn mark_closed(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  cancel(state.resync_timer)
  cancel(state.nudge_timer)
  cancel(state.sync_timer)
  cancel(state.deadline)
  transport_js.set_cell(
    cell,
    State(
      ..state,
      closed: True,
      transport: None,
      peers: dict.new(),
      phase: RelayOff,
      path: PeerToPeer,
      resync_timer: None,
      nudge_dirty: False,
      nudge_armed: False,
      nudge_timer: None,
      publish_owed: False,
      sync_armed: False,
      sync_timer: None,
      deadline: None,
    ),
  )
}

@target(javascript)
/// Remove one attach attempt, and keep the document itself.
///
/// The local state, the handles, and the subscriptions all stay. The function
/// clears the transport code and the callbacks of that attempt only. A caller
/// can thus continue to edit offline, and it can call `attach` again later.
fn mark_detached(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  cancel(state.resync_timer)
  cancel(state.nudge_timer)
  cancel(state.sync_timer)
  cancel(state.deadline)
  transport_js.set_cell(
    cell,
    State(
      ..state,
      transport: None,
      peers: dict.new(),
      on_status: fn(_) { Nil },
      on_ready: fn(_) { Nil },
      readiness: None,
      roster: False,
      bootstrap: Joining,
      deferred: [],
      attached: False,
      relay: None,
      phase: RelayOff,
      path: PeerToPeer,
      published: "",
      resyncs: 0,
      resync_timer: None,
      nudge_dirty: False,
      nudge_armed: False,
      nudge_timer: None,
      publish_owed: False,
      sync_armed: False,
      sync_timer: None,
      last_sync_digest: "",
      last_match: None,
      deadline: None,
    ),
  )
}

@target(javascript)
/// A synchronous failure at startup ends that attempt only, for a restored
/// snapshot. A document that the module just built keeps the earlier
/// fail-closed behaviour.
fn fail_attach_attempt(cell: Cell(State), error: P2pError) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.imported {
    True -> {
      mark_detached(cell)
      contained(fn() { state.on_status(Failed(error)) })
      contained(fn() { state.on_ready(Error(error)) })
    }
    False -> {
      mark_closed(cell)
      resolve_ready(cell, Error(error))
    }
  }
}

@target(javascript)
fn cancel(timer: Option(fn() -> Nil)) -> Nil {
  case timer {
    Some(stop) -> stop()
    None -> Nil
  }
}

@target(javascript)
/// Resolve the readiness one time at most, for the whole life of the
/// connection.
///
/// The function writes the result and emits the status *before* the application
/// callback runs. `readiness` and the status stream thus already agree with
/// that result before any code observes it. A callback that throws also cannot
/// leave a connection that tries to resolve the readiness a second time,
/// because the module guards both callbacks and neither one runs before the
/// write.
fn resolve_ready(cell: Cell(State), outcome: Result(Nil, P2pError)) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.readiness {
    Some(_) -> Nil
    None -> {
      transport_js.set_cell(cell, State(..state, readiness: Some(outcome)))
      case outcome {
        Ok(Nil) -> emit(cell, Ready)
        Error(error) -> emit(cell, Failed(error))
      }
      // An application's readiness callback is application code: it may
      // throw, and if it does the protocol has already recorded the one
      // result it will ever deliver. Containing it here is what stops an
      // exception unwinding a browser event mid-merge.
      contained(fn() { state.on_ready(outcome) })
    }
  }
}

@target(javascript)
fn resolved(state: State) -> Bool {
  state.readiness != None
}

@target(javascript)
/// The complete membership of the room arrived. The function records it, and
/// the module has not always stored the transport at that point, because an
/// adapter can report the roster from inside `join`. `attach` then settles the
/// readiness after it stores the transport.
fn note_roster(cell: Cell(State), peers: List(String)) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.roster {
    True -> Nil
    False -> {
      transport_js.set_cell(cell, State(..state, roster: True))
      emit(cell, RosterKnown(peers))
      settle_readiness(cell)
    }
  }
}

@target(javascript)
/// Become ready when nothing remains to wait for. Three conditions must hold:
/// the membership of the room is completely known, no peer is still in a
/// negotiation, and no peer owes this replica a `state` transfer.
///
/// The roster is the necessary condition. An adapter that learns its room over
/// a network round trip has announced no client when `join` returns. A replica
/// that read that condition as "the room is empty" would call back ready with
/// an empty document, a moment before the state of the room arrived. Every
/// late joiner would see that result.
fn settle_readiness(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  case resolved(state), state.roster {
    True, _ -> Nil
    _, False -> Nil
    False, True ->
      case state.bootstrap, state.transport {
        WaitingForState(_), _ -> Nil
        Joining, None | Bootstrapped, None -> Nil
        Joining, Some(transport) | Bootstrapped, Some(transport) ->
          case p2p_transport_js.known_peers(transport) {
            [] -> {
              let state = transport_js.get_cell(cell)
              transport_js.set_cell(
                cell,
                State(..state, bootstrap: Bootstrapped),
              )
              resolve_ready(cell, Ok(Nil))
            }
            _ -> Nil
          }
      }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The relay lane
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// Open the configured relay, if the policy permits one.
///
/// Nothing in this function can delay the readiness. `Auto` calls it *after*
/// the mesh has its opportunity to settle. The events of the relay resolve the
/// readiness for `SequencedOnly` only, and that policy has no other source.
fn start_relay(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.closed, state.policy, state.sequencer {
    True, _, _ -> Nil
    // A configured sequencer is ignored rather than contacted: `P2pOnly`
    // opens no socket and schedules no attempt.
    _, P2pOnly, _ -> Nil
    _, _, None -> Nil
    _, _, Some(config) -> {
      let relay =
        crdt_sequencer_js.start(
          url: config.url,
          driver: config.driver,
          scheduler: state.scheduler,
          events: relay_events(cell),
        )
      transport_js.set_cell(
        cell,
        State(..state, relay: Some(relay), phase: RelayOpening),
      )
      // Stored before connected, so a driver that answers from inside
      // `open` finds a relay the document already knows about — and so
      // does the `RelayConnecting` the attempt itself reports.
      crdt_sequencer_js.connect(relay)
    }
  }
}

@target(javascript)
fn relay_events(cell: Cell(State)) -> crdt_sequencer_js.Events {
  crdt_sequencer_js.Events(
    on_connecting: fn() { relay_connecting(cell) },
    on_ready: fn() { relay_attached(cell) },
    on_envelope: fn(raw) { relay_document(cell, raw) },
    on_synced: fn() { publish_state(cell) },
    on_attested: fn(digest) { relay_attested(cell, digest) },
    on_checkpoint_requested: fn() { relay_checkpoint_requested(cell) },
    on_unsupported: fn(detail) { relay_unsupported(cell, detail) },
    on_dropped: fn(detail) { relay_dropped(cell, detail) },
    on_retry: fn(delay) { emit(cell, RelayRetry(delay)) },
    on_error: fn(error) { emit(cell, RelayFailed(error)) },
  )
}

@target(javascript)
/// One relay connection attempt starts. This function runs for every attempt,
/// and not for the first one only. A reconnect sequence thus gives one
/// `RelayConnecting` status for each `RelayRetry` status. The status stream is
/// therefore a complete account of the actions of the lane.
fn relay_connecting(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.closed, state.sequencer {
    True, _ -> Nil
    _, None -> Nil
    _, Some(config) -> emit(cell, RelayConnecting(config.url))
  }
}

@target(javascript)
/// The relay announced `crdt_relay_v1`. Send the introduction of this replica,
/// and ask for everything that the relay holds. The module publishes nothing
/// until that reply completes, because a publication before it would give the
/// relay a state that did not merge the state of the room.
///
/// A write that does not reach an open socket ends the attachment at that
/// point. To continue would leave this document in the `RelaySyncing` phase,
/// against a socket that cannot answer. There would then be no `synced`
/// message, no publication, no fallback, and no reconnect. That is the one
/// failure that this lane must never have.
fn relay_attached(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.closed {
    True -> Nil
    False -> {
      transport_js.set_cell(
        cell,
        State(..state, phase: RelaySyncing, published: "", resyncs: 0),
      )
      emit(cell, case state.recovered {
        True -> RelayRecovering
        False -> RelaySyncingStatus
      })
      case relay_write(cell, crdt_core.hello_message(state.document)) {
        False -> Nil
        True -> {
          // After the `hello` that admits the connection and before
          // anything else: a relay's first frame must be an envelope, and
          // a relay that has not been told this client understands a
          // checkpoint request will never send one.
          case state.relay {
            Some(relay) -> {
              let _ = crdt_sequencer_js.declare_support(relay)
              Nil
            }
            None -> Nil
          }
          let _ = relay_write(cell, crdt_core.state_request_message())
          Nil
        }
      }
    }
  }
}

@target(javascript)
/// Publish the whole merged local state, and attest its digest in the same
/// step.
///
/// The two go together on purpose. The digest describes the state that the
/// module just wrote, so the echo of the relay is an acknowledgement of a
/// document that the relay holds. It is not a claim that this replica invented.
/// If either write fails, the function retires the socket. It does not wait for
/// an echo that cannot arrive.
fn publish_state(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.closed, state.relay, state.phase {
    _, None, _ -> Nil
    True, _, _ -> Nil
    _, Some(relay), RelaySyncing -> {
      cancel(state.resync_timer)
      let digest = document_digest(cell)
      transport_js.set_cell(
        cell,
        State(..state, published: digest, resync_timer: None),
      )
      publish(cell, relay, digest, state.document)
    }
    _, Some(_), RelayOff
    | _, Some(_), RelayOpening
    | _, Some(_), RelayPrimaryPhase
    | _, Some(_), RelayUnsupportedPhase
    -> Nil
  }
}

@target(javascript)
/// The two frames of a publication, whatever caller asked for it: the whole
/// merged state, and an attestation of the digest that describes that state.
///
/// This function is separate because three callers owe the relay exactly these
/// two frames, and those callers must not drift apart. They are the attachment
/// handshake, a requested checkpoint, and a merge that this replica learned
/// from a peer while the relay was primary. If either write fails, the function
/// retires the socket. It does not wait for an echo that cannot arrive.
fn publish(
  cell: Cell(State),
  relay: crdt_sequencer_js.Relay,
  digest: String,
  document: crdt_core.Document,
) -> Nil {
  case relay_write(cell, crdt_core.state_message(document)) {
    False -> Nil
    True ->
      case crdt_sequencer_js.attest(relay, digest) {
        Ok(Nil) -> Nil
        Error(_) -> relay_unwritable(cell)
      }
  }
}

@target(javascript)
/// Publish the current merged state while the relay is *primary*, and attest
/// that state.
///
/// The function writes the same two frames as the attachment handshake, in the
/// same order, and it records the digest as `published`. The echo of the relay
/// thus completes the checkpoint in the usual way. An echo that matches gives a
/// `RelayCheckpointed` status and a compacted log. An empty echo means that the
/// relay holds traffic that a client published after this state, and the next
/// checkpoint request of that relay asks about it again.
///
/// Nothing retries from this function. That rule keeps a busy room from a loop
/// of publications.
///
/// The function reads the document again, and it does not take a snapshot from
/// its caller. A status handler that closed the document, or that dropped the
/// lane, between the decision and this line is owed no frame.
fn publish_while_primary(cell: Cell(State)) -> Nil {
  let digest = document_digest(cell)
  let state = transport_js.get_cell(cell)
  case state.closed, state.relay, state.phase {
    False, Some(relay), RelayPrimaryPhase -> {
      transport_js.set_cell(cell, State(..state, published: digest))
      publish(cell, relay, digest, state.document)
    }
    True, _, _
    | _, None, _
    | _, Some(_), RelayOff
    | _, Some(_), RelayOpening
    | _, Some(_), RelaySyncing
    | _, Some(_), RelayUnsupportedPhase
    -> Nil
  }
}

@target(javascript)
/// The relay asked for a checkpoint.
///
/// The live log of a relay is bounded, and a room that fills that log makes the
/// relay refuse traffic, and that includes the traffic of a correct client. The
/// relay thus asks the clients that understand the request to publish what they
/// hold, before it reaches the bound. A correct client answers with exactly the
/// two frames that it publishes during an attachment: the whole merged state,
/// and an attestation of the digest of that state. The checkpoint of the relay
/// then compacts the ordinary valid history of the room down to that one
/// record. A long editing session thus never reaches the bound.
///
/// Nothing about the document changes here, and this function reads nothing
/// that the relay sent. The published state is the state of this replica,
/// exactly as it would be at an attachment.
///
/// There are three conditions, and one of them writes a frame:
///
///   * **syncing**: the attachment handshake already publishes and attests, so
///     the module already answers the request. This function reports the
///     request and does nothing more.
///   * **primary**: publish and attest now.
///   * **every other condition**: there is no lane to answer on.
fn relay_checkpoint_requested(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.closed, state.relay, state.phase {
    True, _, _ -> Nil
    _, None, _ -> Nil
    _, Some(_), RelaySyncing -> emit(cell, RelayCheckpointRequested)
    _, Some(_), RelayPrimaryPhase -> {
      emit(cell, RelayCheckpointRequested)
      // A handler that closed the document, or that dropped the lane, is
      // owed no frames — `publish_while_primary` re-reads both.
      publish_while_primary(cell)
      // A publication the room asked for is a publication: whatever the
      // coalescer owed the relay has just been written.
      clear_publication(cell)
    }
    _, Some(_), RelayOff
    | _, Some(_), RelayOpening
    | _, Some(_), RelayUnsupportedPhase
    -> Nil
  }
}

@target(javascript)
/// The answer of the relay to an attestation.
///
/// An echoed digest means that the whole content of the relay is the state that
/// this replica published. An empty echo means that the relay holds more, for
/// example a concurrent attachment or a delta that raced the publication. The
/// answer to an empty echo is to merge what arrives and to try again. The
/// answer is never to overwrite what the relay holds.
///
/// While the relay is *primary*, the same echo answers a requested checkpoint.
/// The function reports it and does nothing more. The lane is already primary,
/// the document does not change in either condition, and an empty echo means
/// that the relay holds traffic that this replica published after the state.
/// The next request of the relay, which that same growth arms, asks about it
/// again. To retry here would be a loop of publications, with no bound, against
/// a busy room.
fn relay_attested(cell: Cell(State), attested: String) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.closed, state.phase {
    True, _ -> Nil
    _, RelaySyncing -> {
      let local = document_digest(cell)
      case attested != "" && attested == state.published, attested == local {
        // The relay holds exactly what we hold. Nothing else in this
        // protocol is allowed to claim that.
        True, True -> relay_primary(cell, local)
        // Ours moved on between publishing and being answered — a local
        // edit, or a merge. We are strictly ahead, so publish again now
        // rather than waiting on a timer.
        True, False -> publish_state(cell)
        _, _ -> schedule_resync(cell)
      }
    }
    _, RelayPrimaryPhase ->
      case attested != "" && attested == state.published {
        True -> emit(cell, RelayCheckpointed(attested))
        False -> Nil
      }
    _, RelayOff | _, RelayOpening | _, RelayUnsupportedPhase -> Nil
  }
}

@target(javascript)
/// The relay is now the durable delta path.
///
/// The function changes the path before it emits the status. A handler that
/// reads `effective_path` thus agrees with the status that it just received,
/// and a mutation from that handler takes the new route.
fn relay_primary(cell: Cell(State), digest: String) -> Nil {
  let state = transport_js.get_cell(cell)
  cancel(state.resync_timer)
  cancel(state.deadline)
  // The mesh is no longer the delta path, so its anti-entropy timer must
  // not fire against a relay-primary document; the relay carries repair
  // now. The canceller is called here and the flags cleared in the same
  // write as the flip, so a later failover re-arms from a clean slate.
  // `nudge_peers` below is the relay path's own coalescer.
  cancel(state.sync_timer)
  transport_js.set_cell(
    cell,
    State(
      ..state,
      phase: RelayPrimaryPhase,
      path: Sequenced,
      recovered: True,
      resyncs: 0,
      resync_timer: None,
      sync_armed: False,
      sync_timer: None,
      deadline: None,
    ),
  )
  case state.relay {
    Some(relay) -> crdt_sequencer_js.healthy(relay)
    None -> Nil
  }
  emit(cell, RelayPrimary(digest))
  // Readiness for a `SequencedOnly` document, and already resolved for
  // every other one — `resolve_ready` is once for the connection's life.
  resolve_ready(cell, Ok(Nil))
  // The mesh has just stopped carrying this document's deltas. Every
  // peer is told what this replica now holds, so a peer that is not on
  // this relay — `P2pOnly`, an unsupported endpoint, a partition — finds
  // out it is behind at the moment the path changes rather than at the
  // next local edit.
  nudge_peers(cell)
}

@target(javascript)
/// Try the publish and attest handshake again, later.
///
/// The retry has a backoff, and it is not immediate. It is also event-driven,
/// and it does not poll. Two replicas that attach at the same time can each
/// hold something that the other has not merged yet. A pair that retried
/// immediately would invalidate the attestation of the other one, without an
/// end. The delay separates them, and any change to the local document ends the
/// wait early.
fn schedule_resync(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.closed, state.phase {
    True, _ -> Nil
    False, RelaySyncing -> {
      cancel(state.resync_timer)
      timer_js.arm(
        scheduler: state.scheduler,
        delay_milliseconds: crdt_sequencer_js.backoff_milliseconds(
          state.resyncs,
        ),
        action: fn() { publish_state(cell) },
        wanted: fn() {
          let armed = transport_js.get_cell(cell)
          armed.phase == RelaySyncing && !armed.closed
        },
        store: fn(stop) {
          let armed = transport_js.get_cell(cell)
          transport_js.set_cell(
            cell,
            State(..armed, resyncs: armed.resyncs + 1, resync_timer: Some(stop)),
          )
        },
      )
    }
    False, _ -> Nil
  }
}

@target(javascript)
/// The endpoint is a sequencer without this lane.
///
/// Under `Auto` that condition is a status and nothing more. The document
/// continues on the mesh, exactly as it would with no sequencer in the config.
/// Under `SequencedOnly` it is the failure of the readiness, because there is
/// no other path to be ready on.
fn relay_unsupported(cell: Cell(State), detail: String) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.closed {
    True -> Nil
    False -> {
      cancel(state.resync_timer)
      transport_js.set_cell(
        cell,
        State(
          ..state,
          phase: RelayUnsupportedPhase,
          path: PeerToPeer,
          resync_timer: None,
        ),
      )
      emit(cell, RelayUnsupported(detail))
      case state.policy {
        SequencedOnly -> abandon(cell, p2p.SequencerUnsupported)
        Auto | P2pOnly -> Nil
      }
    }
  }
}

@target(javascript)
/// The relay lane is gone.
///
/// Nothing local stops. The function changes the path to the mesh *before* it
/// emits the fallback status. A mutation from a status handler, and a mutation
/// that was already in flight, thus both go to the peers, and neither one goes
/// into a socket that is not there. The document, its handles, its subscribers,
/// its replica identity, and its message counter all stay the same. A transport
/// changed, and a session did not.
fn relay_dropped(cell: Cell(State), detail: String) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.closed {
    True -> Nil
    False -> {
      let attached = case state.phase {
        RelaySyncing | RelayPrimaryPhase -> True
        RelayOff | RelayOpening | RelayUnsupportedPhase -> False
      }
      // Whether the peers are owed a digest for edits this document sent
      // to the relay and not to them. The window is closing with the
      // lane, so it is flushed here or never.
      let owed = state.nudge_dirty || state.nudge_armed
      cancel(state.resync_timer)
      transport_js.set_cell(
        cell,
        State(
          ..state,
          phase: case state.phase {
            RelayUnsupportedPhase -> RelayUnsupportedPhase
            RelayOff | RelayOpening | RelaySyncing | RelayPrimaryPhase ->
              RelayOpening
          },
          path: PeerToPeer,
          published: "",
          resyncs: 0,
          resync_timer: None,
        ),
      )
      // The armed interval is disarmed here rather than left to fire
      // against a path that has changed — but what it was going to say is
      // said now, synchronously, instead of being dropped.
      cancel_nudge(cell)
      case attached {
        False -> Nil
        True -> {
          emit(cell, RelayFallback(detail))
          final_nudge(cell, owed)
          repair_from_peers(cell)
        }
      }
      // The mesh is the delta path again. The failover `repair_from_peers`
      // above is the one-shot catch-up; this starts the recurring
      // heartbeat that keeps every validated peer converged from here on.
      refresh_sync(cell)
    }
  }
}

@target(javascript)
/// The one digest that a fallback owes the mesh.
///
/// While the relay is primary, a durable delta goes to the relay and *not* to
/// the peers. Those peers receive a coalesced digest on the anti-entropy
/// interval. Without this function, a drop inside that window would cancel the
/// digest and send a `stateRequest` message only. That message pulls the state
/// of each peer and tells that peer nothing. A peer that never saw the
/// relay-only edits would answer with a state that does not contain them, it
/// would merge nothing, and it would stay behind until the next local
/// mutation. In a room that became quiet, it would stay behind without an
/// end.
///
/// This function thus flushes a window that is dirty or armed exactly one time,
/// synchronously, before the failover sends its `stateRequest`. The peer
/// compares that digest, finds that it does not match, asks for the state on
/// the existing mismatch path of `crdt_core`, and converges with the fallback.
/// The module already cancelled the timer, so this is one push and not two.
fn final_nudge(cell: Cell(State), owed: Bool) -> Nil {
  case owed {
    False -> Nil
    True -> broadcast_digest(cell)
  }
}

@target(javascript)
/// Ask every validated peer for its state, so that an outage that started on
/// the relay does not also start with a gap. A merge is idempotent, and a
/// `state` message that changes nothing emits nothing. This function thus costs
/// one round trip, and it costs no correctness.
fn repair_from_peers(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  greeted_peers(state)
  |> list.each(fn(peer_id) {
    send(cell, peer_id, crdt_core.state_request_message())
  })
}

@target(javascript)
/// The ids of every peer that completed the `hello` handshake, sorted. This
/// function is the one definition of the peers that this document can send
/// to.
fn greeted_peers(state: State) -> List(String) {
  state.peers
  |> dict.values
  |> list.filter(fn(peer) { peer.greeted })
  |> list.map(fn(peer) { peer.id })
  |> list.sort(string.compare)
}

@target(javascript)
/// One envelope that the relay carried.
///
/// The `order` value of the relay never reaches this function. The lane removes
/// it, and what arrives is the encoded envelope of the author. The checks are
/// the same as for a peer, and so is the merge. The message-id window of
/// `crdt_core` suppresses a delta that arrived over WebRTC first, and a delta
/// that arrives here first suppresses the WebRTC copy. A duplicate is thus one
/// state change and one subscriber event, in either order.
///
/// A refusal costs the envelope of the sender, and nothing else. Unlike a peer,
/// this module cannot close a relay client, and to close the lane would remove
/// that lane from every other replica on it, for one bad frame from one
/// replica. The `False` result of this function stops the high-water mark of
/// the lane from moving past something that this document did not merge. Without
/// that result, a later attestation could tell the relay to retire that
/// entry.
fn relay_document(cell: Cell(State), raw: String) -> Bool {
  let state = transport_js.get_cell(cell)
  case state.closed {
    True -> False
    False ->
      case crdt_wire.decode_envelope(raw, crdt_core.limits(state.document)) {
        Error(error) -> {
          emit(cell, RelayRejected("", error))
          False
        }
        Ok(envelope) ->
          case receive_envelope(cell, envelope) {
            Error(error) -> {
              emit(cell, RelayRejected(envelope.from, error))
              False
            }
            Ok(#(document, outcome)) -> {
              // Only after something has been published: during the
              // initial replay burst there is nothing to be behind, and
              // publishing once per replayed entry would write the
              // document to the relay N times to say the same thing.
              let syncing = state.phase == RelaySyncing && state.published != ""
              let previous = state.published
              transport_js.set_cell(cell, State(..state, document: document))
              list.each(outcome.reply, fn(message) {
                let _ = relay_write(cell, message)
                Nil
              })
              list.each(outcome.broadcast, fn(message) {
                broadcast(cell, message)
              })
              dispatch(cell, outcome.events)
              // Something the relay carried changed this document, so
              // the peers that are *not* on this relay are now behind.
              // A digest is how they find out; the delta itself is not
              // repeated onto the mesh.
              case outcome.events != [] || outcome.created != [] {
                True -> nudge_peers(cell)
                False -> Nil
              }
              // Still syncing, and the merge moved us: publish again now
              // rather than waiting out the backoff. This is what makes
              // two concurrent attachments converge in a round trip
              // instead of a timer.
              case syncing, document_digest(cell) != previous {
                True, True -> publish_state(cell)
                _, _ -> Nil
              }
              True
            }
          }
      }
  }
}

@target(javascript)
/// Write one message to the relay, if a relay exists to write to.
fn relay_send(cell: Cell(State), message: Message) -> Bool {
  let state = transport_js.get_cell(cell)
  case state.relay {
    None -> False
    Some(relay) ->
      crdt_sequencer_js.send_envelope(
        relay,
        crdt_core.encode(state.document, message),
      )
      |> result.is_ok()
  }
}

@target(javascript)
/// `relay_send`, and this function handles the failure instead of an ignore.
///
/// Every write on this lane is one of four things: the `hello` and
/// `stateRequest` messages of the attachment, the published `state` message, a
/// reply to something that the relay carried, or a durable broadcast. A `False`
/// result means the same thing for all four: this socket is gone. The one
/// correct answer is to retire that socket. The function thus changes the path
/// to the mesh, reports the fallback, repairs from the peers, and arms the
/// reconnect of the policy. Every other answer leaves the document in the
/// middle of a handshake, on a socket that will never answer.
fn relay_write(cell: Cell(State), message: Message) -> Bool {
  case relay_send(cell, message) {
    True -> True
    False -> {
      relay_unwritable(cell)
      False
    }
  }
}

@target(javascript)
/// A write that did not reach an open socket. The function retires the lane on
/// the same path as a close that the driver reported. There is thus one
/// fallback sequence, and not two.
fn relay_unwritable(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.relay {
    None -> Nil
    Some(relay) ->
      crdt_sequencer_js.abort(relay, "the relay socket was not writable")
  }
}

@target(javascript)
/// Arm the readiness deadline of `SequencedOnly`.
///
/// The deadline bounds the whole attachment, which is the socket, the
/// capability, the state replay, and the digest. It does not bound one step of
/// that attachment, because a caller that waits on `on_ready` does not need to
/// know which step is slow.
fn arm_deadline(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.sequencer {
    None -> Nil
    Some(config) ->
      case config.readiness_deadline_milliseconds > 0 {
        False -> Nil
        True ->
          timer_js.arm(
            scheduler: state.scheduler,
            delay_milliseconds: config.readiness_deadline_milliseconds,
            action: fn() {
              abandon(
                cell,
                p2p.SequencerUnavailable(
                  "the sequencer did not become the durable path within "
                  <> int.to_string(config.readiness_deadline_milliseconds)
                  <> "ms",
                ),
              )
            },
            wanted: fn() {
              let armed = transport_js.get_cell(cell)
              !armed.closed && !resolved(armed)
            },
            store: fn(stop) {
              let armed = transport_js.get_cell(cell)
              transport_js.set_cell(cell, State(..armed, deadline: Some(stop)))
            },
          )
      }
  }
}

@target(javascript)
/// Stop with a document that can never become ready. The function resolves the
/// readiness one time, with the reason, and it closes everything that the
/// document holds.
fn abandon(cell: Cell(State), error: P2pError) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.closed, resolved(state) {
    True, _ -> Nil
    _, True -> Nil
    False, False -> {
      mark_closed(cell)
      case state.transport {
        Some(transport) -> p2p_transport_js.close(transport)
        None -> Nil
      }
      case state.relay {
        Some(relay) -> crdt_sequencer_js.close(relay)
        None -> Nil
      }
      resolve_ready(cell, Error(error))
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transport plumbing
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
fn callbacks(cell: Cell(State)) -> p2p_transport_js.Callbacks {
  p2p_transport_js.Callbacks(
    on_peer_open: fn(peer_id) { defer(cell, DeferredOpen(peer_id)) },
    on_peer_close: fn(peer_id) { defer(cell, DeferredClose(peer_id)) },
    on_document: fn(peer_id, payload) {
      defer(cell, DeferredDocument(peer_id, payload))
    },
    on_status: fn(status) {
      emit(cell, Transport(status))
      case status {
        // The room's membership is completely known, and the transport
        // has already tracked every peer in it: this is the moment a
        // replica may conclude it is alone.
        p2p_transport_js.SignalingRoster(peers) -> note_roster(cell, peers)
        // Readiness is settled from the status stream rather than from
        // `on_peer_close`, because the transport retires *every* announced
        // peer with a `PeerClosed` status but only calls `on_peer_close`
        // for peers whose data channel actually opened. A peer that was
        // announced during `join` and then vanished mid-negotiation is
        // exactly the case where a replica is provably alone and owed its
        // readiness result, and it never reaches the callback.
        p2p_transport_js.PeerClosed(peer_id) ->
          defer(cell, DeferredClose(peer_id))
        p2p_transport_js.SignalingJoined(..)
        | p2p_transport_js.SignalingLeft
        | p2p_transport_js.PeerConnecting(_)
        | p2p_transport_js.PeerOpen(_)
        | p2p_transport_js.PeerFailed(..)
        | p2p_transport_js.IceState(..)
        | p2p_transport_js.PeerCount(_) -> Nil
      }
    },
    on_error: fn(error) {
      emit(cell, TransportError(error))
      case error {
        // Signaling that died before the roster arrived would otherwise
        // leave a caller waiting for a readiness result it can never get.
        // After readiness this is status and nothing more: the mesh does
        // not need signaling to keep running.
        p2p.SignalingFailed(_) -> resolve_ready(cell, Error(error))
        p2p.UnsupportedChannel(_)
        | p2p.RootMismatch(..)
        | p2p.ChannelTypeMismatch(..)
        | p2p.DocumentClosed
        | p2p.CompatibilityMismatch(..)
        | p2p.ProtocolMismatch(..)
        | p2p.RoomMismatch
        | p2p.RoomFull(_)
        | p2p.SequencerUnavailable(_)
        | p2p.SequencerUnsupported
        | p2p.PeerConnectionFailed(..)
        | p2p.InvalidEnvelope(..)
        | p2p.SnapshotTooLarge(..)
        | p2p.ReplicaCollision(_) -> Nil
      }
    },
  )
}

@target(javascript)
/// Run a transport callback now, or hold it until `attach` stores the transport
/// that the callback needs to answer with. An adapter that opens a channel from
/// inside `join` is unusual, and it is valid. The module must drop nothing that
/// such an adapter delivers.
fn defer(cell: Cell(State), entry: Deferred) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.transport {
    Some(_) -> run_deferred(cell, entry)
    None ->
      transport_js.set_cell(
        cell,
        State(..state, deferred: [entry, ..state.deferred]),
      )
  }
}

@target(javascript)
fn run_deferred(cell: Cell(State), entry: Deferred) -> Nil {
  case entry {
    DeferredOpen(peer_id) -> handle_peer_open(cell, peer_id)
    DeferredDocument(peer_id, payload) ->
      handle_document(cell, peer_id, payload)
    DeferredClose(peer_id) -> handle_peer_close(cell, peer_id)
  }
}

@target(javascript)
/// The document channel of a peer is open. Send the introduction of this
/// replica. The module can send nothing else until the `hello` message of that
/// peer arrives and passes its checks.
fn handle_peer_open(cell: Cell(State), peer_id: String) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.closed {
    True -> Nil
    False -> {
      transport_js.set_cell(
        cell,
        State(
          ..state,
          peers: dict.insert(
            state.peers,
            peer_id,
            Peer(peer_id, greeted: False),
          ),
        ),
      )
      send(cell, peer_id, crdt_core.hello_message(state.document))
    }
  }
}

@target(javascript)
/// Retire a peer. A second call has no more effect. Two routes reach this
/// function: the `PeerClosed` status of the transport, which covers every
/// announced peer, and the `on_peer_close` callback of that transport, which
/// covers the peers that opened only. The route that arrives first does the
/// work. The second one finds nothing to report, and it settles the readiness
/// again, which also has no more effect.
fn handle_peer_close(cell: Cell(State), peer_id: String) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.closed {
    True -> Nil
    False -> {
      case dict.has_key(state.peers, peer_id) {
        False -> Nil
        True -> {
          transport_js.set_cell(
            cell,
            State(..state, peers: dict.delete(state.peers, peer_id)),
          )
          emit(cell, PeerGone(peer_id))
        }
      }
      // If that was the last validated peer, the heartbeat has nobody left
      // to tell and stops here.
      refresh_sync(cell)
      rebootstrap(cell, peer_id)
    }
  }
}

@target(javascript)
/// A peer that this replica bootstrapped from is gone. Ask the next validated
/// peer instead. If no peer remains, this replica is the whole room, and the
/// document that it already holds is ready.
fn rebootstrap(cell: Cell(State), lost: String) -> Nil {
  let state = transport_js.get_cell(cell)
  case resolved(state), state.bootstrap {
    True, Joining | True, WaitingForState(_) | True, Bootstrapped -> Nil
    False, WaitingForState(peer_id) if peer_id == lost -> {
      case greeted_peers(state) {
        [peer_id, ..] -> request_state(cell, peer_id)
        [] -> {
          transport_js.set_cell(cell, State(..state, bootstrap: Joining))
          settle_readiness(cell)
        }
      }
    }
    False, Joining | False, WaitingForState(_) | False, Bootstrapped ->
      settle_readiness(cell)
  }
}

@target(javascript)
fn request_state(cell: Cell(State), peer_id: String) -> Nil {
  let state = transport_js.get_cell(cell)
  transport_js.set_cell(
    cell,
    State(..state, bootstrap: WaitingForState(peer_id)),
  )
  emit(cell, AwaitingState(peer_id))
  send(cell, peer_id, crdt_core.state_request_message())
}

// ─────────────────────────────────────────────────────────────────────────────
// Inbound document messages
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// One payload from the data channel of one peer. Every check that can refuse
/// that payload runs before the module asks `crdt_core` to merge anything.
fn handle_document(cell: Cell(State), peer_id: String, raw: String) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.closed, dict.get(state.peers, peer_id) {
    True, _ -> Nil
    // A peer we have already closed. Its payload was in flight; it is not
    // a protocol violation and there is nothing left to reject.
    _, Error(Nil) -> Nil
    _, Ok(peer) ->
      case crdt_wire.decode_envelope(raw, crdt_core.limits(state.document)) {
        Error(error) -> reject_peer(cell, peer_id, error)
        Ok(envelope) ->
          // In a full mesh every message arrives directly from its
          // author, so a peer speaking for someone else is forging.
          case envelope.from == peer_id {
            False ->
              reject_peer(
                cell,
                peer_id,
                p2p.InvalidEnvelope(
                  peer_id,
                  "envelope claims to be from " <> envelope.from,
                ),
              )
            True -> route(cell, peer, envelope)
          }
      }
  }
}

@target(javascript)
fn route(cell: Cell(State), peer: Peer, envelope: crdt_wire.Envelope) -> Nil {
  case envelope.message, peer.greeted {
    crdt_wire.Hello(..), False ->
      merge(cell, peer.id, envelope, fn(_) { greet(cell, peer.id) })
    // A second hello from a peer that already passed the handshake is
    // ignored, not merged and not answered. Re-running the greeting would
    // send it another full `state` transfer, so a peer that repeated its
    // hello could make this replica serialize and upload its whole
    // document as often as it liked.
    crdt_wire.Hello(..), True -> Nil
    _, False ->
      reject_peer(
        cell,
        peer.id,
        p2p.InvalidEnvelope(
          peer.id,
          "sent " <> crdt_wire.message_type(envelope.message) <> " before hello",
        ),
      )
    crdt_wire.State(entries), True -> {
      // A repair is counted when the catch-up `state` actually moves this
      // replica's canonical state, not when a digest asked for it — a
      // request that never gets an answer, or an answer this replica
      // already subsumes, is no repair. The digest is compared across the
      // merge rather than reading `outcome.events`, because a catch-up can
      // change the lattice (an OR-Set tag, a 2P-Set tombstone) with no
      // visible membership change and so no event at all.
      let before = document_digest(cell)
      merge(cell, peer.id, envelope, fn(_) {
        let after = document_digest(cell)
        case before != after {
          True -> note_repair(cell)
          False -> Nil
        }
        state_merged(cell, peer.id, list.length(entries))
      })
    }
    // A peer's digest is the anti-entropy comparison this replica answers
    // on `crdt_core`'s existing mismatch path: an empty outcome means the
    // two agree — recorded as the last successful match — and a
    // `stateRequest` reply means this replica is behind and has just asked
    // to catch up. The repair itself is counted when that state arrives,
    // not here.
    crdt_wire.Digest(remote), True ->
      merge(cell, peer.id, envelope, fn(outcome) {
        record_peer_digest(cell, remote, outcome)
      })
    crdt_wire.Rejected(reason, detail), True ->
      merge(cell, peer.id, envelope, fn(_) {
        emit(cell, RejectedByPeer(peer.id, reason, detail))
      })
    _, True -> merge(cell, peer.id, envelope, fn(_) { Nil })
  }
}

@target(javascript)
/// `crdt_core.receive`, with the local digest from the cache, for the one
/// message that reads it.
///
/// The module answers a `Digest` message by a comparison against the digest of
/// this document. The heartbeat makes the same comparison, in both directions.
/// Every other message computes no digest at all. This function reads the
/// document itself, and it does not take that document from its caller. The
/// value that it compares and the value that it compares against thus cannot
/// come from two different states.
fn receive_envelope(
  cell: Cell(State),
  envelope: crdt_wire.Envelope,
) -> Result(#(crdt_core.Document, crdt_core.Outcome), P2pError) {
  let document = transport_js.get_cell(cell).document
  case envelope.message {
    crdt_wire.Digest(_) ->
      crdt_core.receive_with_digest(document, envelope, document_digest(cell))
    crdt_wire.Hello(..)
    | crdt_wire.ChannelAnnounce(_)
    | crdt_wire.Delta(..)
    | crdt_wire.StateRequest
    | crdt_wire.State(_)
    | crdt_wire.Rejected(..) -> crdt_core.receive(document, envelope)
  }
}

@target(javascript)
/// Merge one envelope that passed its checks. The function writes the document
/// before it sends anything, and before a subscriber runs. A callback that
/// throws thus cannot leave the document behind the state that its peers
/// believe that it holds.
///
/// A merge that moves the canonical state while the *relay* is the durable path
/// also owes that state to the relay. No other route carries it. A received
/// message never fills `outcome.broadcast`. A delta or a channel that a
/// `P2pOnly` peer sent over WebRTC would thus converge across the mesh and
/// reach neither the history of the room, nor its checkpoint, nor a replica
/// that talks to the relay only.
///
/// The function compares the digest across the merge, and it does not read
/// `outcome.events`. A merge can move the lattice with no event at all, for
/// example with an OR-Set tag or a 2P-Set tombstone. A state that the relay
/// does not hold is a state that the relay does not hold, whether or not a
/// subscriber would have seen it.
fn merge(
  cell: Cell(State),
  peer_id: String,
  envelope: crdt_wire.Envelope,
  after: fn(crdt_core.Outcome) -> Nil,
) -> Nil {
  let state = transport_js.get_cell(cell)
  // Only while the relay is primary is anything owed to it, and only
  // then is the comparison worth making: on the mesh path the peers
  // already have what this merge carried, and the heartbeat covers what
  // they do not.
  let durable = state.path == Sequenced && state.phase == RelayPrimaryPhase
  let before = case durable {
    True -> document_digest(cell)
    False -> ""
  }
  case receive_envelope(cell, envelope) {
    Error(error) -> reject_peer(cell, peer_id, error)
    Ok(#(document, outcome)) -> {
      transport_js.set_cell(cell, State(..state, document: document))
      list.each(outcome.reply, fn(message) { send(cell, peer_id, message) })
      list.each(outcome.broadcast, fn(message) { broadcast(cell, message) })
      dispatch(cell, outcome.events)
      case durable && document_digest(cell) != before {
        True -> owe_publication(cell)
        False -> Nil
      }
      after(outcome)
    }
  }
}

@target(javascript)
/// A peer moved this document while the relay carried its durability. The relay
/// thus needs the merged state.
///
/// The module collects that publication onto the interval that the relay path
/// already has. It does not publish from inside the merge. A burst on the mesh
/// is thus one publication, and not one for each delta, and the digest for the
/// peers goes out in the same flush.
///
/// The publication itself is the ordinary one: a `state` frame with an
/// attestation. The relay logs it, sends it to the replicas that this one
/// cannot see, and checkpoints it, exactly as it would for a publication that
/// this replica wrote.
///
/// A merge that the relay carried does *not* come through this function, and
/// that is deliberate. The relay already holds what it sent, and a second
/// publication of it would make every client answer every publication with
/// another one.
fn owe_publication(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  transport_js.set_cell(cell, State(..state, publish_owed: True))
  nudge_peers(cell)
}

@target(javascript)
/// Remove an owed publication, because the module just wrote one, or because
/// there is no longer a lane to write it on. A lane that comes back publishes
/// the whole merged state during its handshake, so a fallback that drops this
/// value loses nothing.
fn clear_publication(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  transport_js.set_cell(cell, State(..state, publish_owed: False))
}

@target(javascript)
/// Record what the digest of a peer told this replica. An empty outcome is a
/// match, which means that the two already agree, so the module keeps that
/// digest as the last successful comparison. A `stateRequest` reply means that
/// this replica was behind, and `merge` already asked for the state. The module
/// counts the repair when that state arrives and moves the document, and not
/// here. A request that no peer answers thus adds nothing to the count.
fn record_peer_digest(
  cell: Cell(State),
  remote: String,
  outcome: crdt_core.Outcome,
) -> Nil {
  let state = transport_js.get_cell(cell)
  case outcome.reply {
    [] -> transport_js.set_cell(cell, State(..state, last_match: Some(remote)))
    // A mismatch: this replica has just asked the peer for state, and it
    // also clears the heartbeat's dirty gate. If the peer turns out to be
    // the one behind, only a re-announced digest from this side makes it
    // ask — a digest carries no ordering, so neither side knows which of
    // them is ahead until the next comparison.
    _ -> transport_js.set_cell(cell, State(..state, last_sync_digest: ""))
  }
}

@target(javascript)
/// Count one completed partition repair, which is a catch-up `state` message
/// that changed the canonical state of this replica.
fn note_repair(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  transport_js.set_cell(cell, State(..state, repairs: state.repairs + 1))
}

@target(javascript)
fn greet(cell: Cell(State), peer_id: String) -> Nil {
  let state = transport_js.get_cell(cell)
  case dict.get(state.peers, peer_id) {
    Error(Nil) -> Nil
    Ok(peer) -> {
      transport_js.set_cell(
        cell,
        State(
          ..state,
          peers: dict.insert(state.peers, peer_id, Peer(..peer, greeted: True)),
        ),
      )
      emit(cell, PeerReady(peer_id))
      // Every validated peer is asked for its state. Which of two
      // replicas joined first is not knowable from either side — an
      // adapter may report a roster synchronously or a round trip later
      // — so the exchange is symmetric rather than reserved for a
      // joiner. Merges are idempotent, the mesh is capped at eight, and
      // a `state` that changes nothing emits no events.
      case resolved(state), state.bootstrap {
        // The first validated peer of a replica that is not ready yet is
        // also its bootstrap source: readiness waits on this reply.
        False, Joining -> request_state(cell, peer_id)
        True, Joining | _, WaitingForState(_) | _, Bootstrapped ->
          send(cell, peer_id, crdt_core.state_request_message())
      }
      // And, while the relay is the delta path, what this replica holds
      // — so a peer that never sees this relay's traffic can ask for
      // whatever it is missing rather than wait for a local edit.
      case transport_js.get_cell(cell).path {
        Sequenced -> send(cell, peer_id, digest_message(cell))
        PeerToPeer -> Nil
      }
      // The mesh now has a validated peer to answer, so start (or leave
      // running) the anti-entropy heartbeat. A no-operation on the
      // relay-primary path, where `should_sync` is false and repair is the
      // relay's job.
      refresh_sync(cell)
    }
  }
}

@target(javascript)
/// A `state` transfer merged.
///
/// Any such transfer settles a bootstrap that still waits, and not the transfer
/// from the first peer that this replica asked only. The module sends a
/// `stateRequest` message to every peer that greeted it, and every one of those
/// peers answers. A replica that merged the state of a room is thus
/// bootstrapped, whichever answer arrived. To tie the readiness to one peer
/// would let a peer that greets and then sends nothing hold a joining client on
/// its loading screen, while the rest of the room synchronized that client.
fn state_merged(cell: Cell(State), peer_id: String, channels: Int) -> Nil {
  emit(cell, StateMerged(peer_id, channels))
  let state = transport_js.get_cell(cell)
  case resolved(state) {
    True -> Nil
    False -> {
      transport_js.set_cell(cell, State(..state, bootstrap: Bootstrapped))
      resolve_ready(cell, Ok(Nil))
    }
  }
}

@target(javascript)
/// Close one peer for a protocol violation, and tell that peer the reason
/// first. The local document does not change, and every other peer continues. A
/// hostile peer, and a peer that does not match, each cost their own connection
/// and nothing else.
fn reject_peer(cell: Cell(State), peer_id: String, error: P2pError) -> Nil {
  let #(reason, detail) = error_parts(error)
  send(cell, peer_id, crdt_core.rejection_message(reason, detail))
  let state = transport_js.get_cell(cell)
  transport_js.set_cell(
    cell,
    State(..state, peers: dict.delete(state.peers, peer_id)),
  )
  case state.transport {
    Some(transport) -> p2p_transport_js.close_peer(transport, peer_id)
    None -> Nil
  }
  emit(cell, PeerRejected(peer_id, error))
  // A rejected peer may have been the last validated one; if so the
  // heartbeat has nothing left to tell and stops.
  refresh_sync(cell)
  rebootstrap(cell, peer_id)
}

// ─────────────────────────────────────────────────────────────────────────────
// Outbound
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
fn send(cell: Cell(State), peer_id: String, message: Message) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.transport {
    None -> Nil
    Some(transport) -> {
      let payload = crdt_core.encode(state.document, message)
      let _ = p2p_transport_js.send(transport, peer_id, payload)
      Nil
    }
  }
}

@target(javascript)
/// Send one message on the path that is durable now.
///
/// While the relay is primary, that path is the relay. It is durable, and it
/// reaches a replica that this one has no peer connection to. The mesh stays
/// open below it, for the presence, the digests, the repair, and the failover,
/// which needs no negotiation.
///
/// The module does *not* also push the durable message to the peers. That is
/// the meaning of "one durable path". It does push the digest of that message,
/// so a peer that is not on this relay learns that it is behind.
///
/// A write that the relay could not make takes the mesh instead. That occurs
/// when the relay dropped between the mutation and this line, and when the
/// socket is no longer open. The module then drops the lane, and it does not
/// leave that lane with the appearance of health. A path that cannot carry a
/// delta is not the delta path.
fn broadcast(cell: Cell(State), message: Message) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.path, state.relay {
    Sequenced, Some(_) ->
      case relay_send(cell, message) {
        True -> nudge_peers(cell)
        False -> {
          // Fallback first: this marks the mesh as the delta path and
          // reports it before the message is written anywhere, so the
          // write below and any mutation authored from the status
          // handler take the same route.
          relay_unwritable(cell)
          peer_broadcast(cell, message)
        }
      }
    Sequenced, None | PeerToPeer, _ -> peer_broadcast(cell, message)
  }
}

@target(javascript)
/// Anti-entropy for the mesh, while the relay carries the durable traffic.
///
/// The module sends one `digest` message to every validated peer. A peer whose
/// digest matches answers nothing. A peer whose digest differs asks for the
/// state, and this replica serves that request from the same `crdt_core` path
/// as a bootstrap. Three kinds of replica thus converge: a `P2pOnly` replica, a
/// replica whose sequencer does not support this lane, and a replica that is
/// partitioned from the relay. No durable delta is duplicated onto the mesh,
/// and there is no second event, because a merge is idempotent and a `state`
/// message that changes nothing emits nothing.
///
/// The module collects the digests over a named interval, and it does not send
/// one from inside the mutation that caused it. That choice is deliberate.
///
/// A digest that arrives before the fan-out of the same delta from the relay
/// tells every peer that it is behind, at the exact moment at which that peer
/// stops being behind. The answer to such a digest is a full `state` transfer
/// across the mesh, for each mutation. A tick with no delay does not solve
/// that. A microtask, and one turn of the task queue, are both much faster than
/// a socket round trip, and either one collects the synchronous mutations
/// only.
///
/// This function thus marks the document dirty, and it arms one flush
/// `default_anti_entropy_milliseconds` ahead, on the scheduler of the document.
/// That value is 250 ms, and a caller can replace it. Edits across many tasks
/// collect into that flush. The copy of each edit from the relay usually
/// reaches the peers first. A peer that the relay could not reach receives a
/// digest one quarter of a second later, instead of a stale digest immediately.
/// Continuous editing thus costs exactly one digest for each interval.
///
/// This function is anti-entropy, and it is not repair. A failover does not use
/// it. The failover sends a `stateRequest` message to every peer, with the
/// fallback, and with no delay.
fn nudge_peers(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.closed, state.path, state.transport {
    False, Sequenced, Some(_) ->
      case state.nudge_armed {
        // This interval already has a digest coming, and the flush reads
        // the document when it runs — so everything dirtied between now
        // and then is inside the digest it sends.
        True -> transport_js.set_cell(cell, State(..state, nudge_dirty: True))
        False -> {
          transport_js.set_cell(
            cell,
            State(..state, nudge_dirty: True, nudge_armed: True),
          )
          timer_js.arm(
            scheduler: state.scheduler,
            delay_milliseconds: state.anti_entropy_interval_milliseconds,
            action: fn() { flush_nudge(cell) },
            wanted: fn() {
              let armed = transport_js.get_cell(cell)
              armed.nudge_armed && !armed.closed
            },
            store: fn(stop) {
              let armed = transport_js.get_cell(cell)
              transport_js.set_cell(
                cell,
                State(..armed, nudge_timer: Some(stop)),
              )
            },
          )
        }
      }
    False, Sequenced, None
    | False, PeerToPeer, _
    | True, Sequenced, _
    | True, PeerToPeer, _
    -> Nil
  }
}

@target(javascript)
/// Send the collected digest, when the document is still dirty and the relay is
/// still the delta path at the end of the interval. The function also publishes
/// what a peer merged into this document while the relay was primary. That
/// publication is the only route from that state to the relay.
///
/// A lane that dropped in that interval already sent a `stateRequest` message to
/// its peers, which gives more than the digest, and that lane publishes
/// everything that it holds when it comes back. A document that a caller closed
/// has no peer to tell and no lane to publish on.
///
/// The function sends to the mesh first. A publication that the module cannot
/// write retires the lane, and the fallback that follows sends a `stateRequest`
/// message to every peer. To send the digest first thus means that the peers
/// receive one message in both conditions, and not two messages or no
/// message.
fn flush_nudge(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  transport_js.set_cell(
    cell,
    State(
      ..state,
      nudge_dirty: False,
      nudge_armed: False,
      nudge_timer: None,
      publish_owed: False,
    ),
  )
  case state.closed, state.nudge_dirty {
    False, True ->
      case state.path, state.transport {
        Sequenced, Some(_) -> broadcast_digest(cell)
        Sequenced, None | PeerToPeer, _ -> Nil
      }
    False, False | True, _ -> Nil
  }
  case state.closed, state.publish_owed {
    False, True -> publish_while_primary(cell)
    _, _ -> Nil
  }
}

@target(javascript)
/// Disarm the anti-entropy flush. The module is about to send the mesh
/// something larger than a digest, or it just sent that, or there is nothing
/// left to send. An owed publication also goes away. The only caller is a lane
/// that is gone, and a lane that comes back publishes the whole merged state
/// during its handshake.
fn cancel_nudge(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  cancel(state.nudge_timer)
  transport_js.set_cell(
    cell,
    State(
      ..state,
      nudge_dirty: False,
      nudge_armed: False,
      nudge_timer: None,
      publish_owed: False,
    ),
  )
}

@target(javascript)
/// Whether one peer or more completed the `hello` handshake. The module sends
/// the mesh anti-entropy digest to a validated peer only, so this replica sends
/// nothing in a room where no peer is validated.
fn has_greeted_peer(state: State) -> Bool {
  greeted_peers(state) != []
}

@target(javascript)
/// Whether the mesh anti-entropy heartbeat must run. Four conditions must hold:
/// the document is open, its delta path is WebRTC, it has a transport, and it
/// has one validated peer or more to send to. `refresh_sync`, `arm_sync`, and
/// `tick_sync` all use this one predicate, so "a peer exists" has one
/// meaning.
fn should_sync(state: State) -> Bool {
  case state.closed, state.path, state.transport {
    False, PeerToPeer, Some(_) -> has_greeted_peer(state)
    False, PeerToPeer, None
    | False, Sequenced, _
    | True, PeerToPeer, _
    | True, Sequenced, _
    -> False
  }
}

@target(javascript)
/// Reconcile the heartbeat with the current shape of the document. The function
/// arms the heartbeat when that heartbeat must run and does not run. It cancels
/// the heartbeat when that heartbeat runs and must not run. A second call has no
/// more effect. Every lifecycle event that can change `should_sync` thus calls
/// this function, and it needs to know nothing about the earlier state of the
/// timer. Those events are a greeting, a failover to the mesh, and a peer that
/// leaves.
fn refresh_sync(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  case should_sync(state), state.sync_armed {
    True, False -> arm_sync(cell)
    False, True -> cancel_sync(cell)
    True, True | False, False -> Nil
  }
}

@target(javascript)
/// Anti-entropy for the mesh, while WebRTC is the delta path. This function is
/// the recurring equivalent of `nudge_peers` on the relay path.
///
/// The canonical state can move with no new broadcast and with no visible
/// event. Three examples: a `state` transfer, a partition that heals on one
/// reconnected edge, and a concurrent OR-Set tag or 2P-Set tombstone that
/// changes the lattice and not the membership that a subscriber sees. None of
/// those changes fans out by itself, so the mesh cannot start a repair from
/// them.
///
/// Instead, while a validated peer exists, the document checks every
/// `anti_entropy_interval_milliseconds` whether its canonical digest moved
/// after the last message to the peers. It broadcasts that digest when the
/// digest moved. A peer whose digest matches answers nothing. A peer whose
/// digest differs asks for the state, on the existing mismatch path of
/// `crdt_core`, and it also clears its own gate. The side that is ahead thus
/// continues to announce until the room agrees. An idle mesh that converged
/// therefore costs one digest and then nothing, and not one broadcast in every
/// interval.
///
/// To reconnect one edge between two partitions thus repairs *every* remaining
/// peer, and not the two endpoints only. A quiet mesh that merged a change with
/// no event also converges. Neither condition needs a later edit with an event
/// to start a flush.
///
/// There is one live timer. `arm_sync` does nothing when a heartbeat is armed
/// already, and `tick_sync` clears the flag before it arms the timer again. The
/// `nudge_*` fields of the relay path are separate, and the module never arms
/// both at the same time. The transport path is one or the other, and a failover
/// cancels the coalescer of the relay before this heartbeat starts.
fn arm_sync(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  case should_sync(state), state.sync_armed {
    True, False -> {
      transport_js.set_cell(cell, State(..state, sync_armed: True))
      // A synchronous scheduler has already ticked before the canceller
      // comes back: `tick_sync` saw no stored timer, fired once, and did
      // not re-arm — so `sync_armed` is `False` again, `wanted` says no,
      // and nothing is stored. Re-arming here instead would be the tight
      // loop the synchronous case must avoid.
      timer_js.arm(
        scheduler: state.scheduler,
        delay_milliseconds: state.anti_entropy_interval_milliseconds,
        action: fn() { tick_sync(cell) },
        wanted: fn() {
          let armed = transport_js.get_cell(cell)
          armed.sync_armed && !armed.closed
        },
        store: fn(stop) {
          let armed = transport_js.get_cell(cell)
          transport_js.set_cell(cell, State(..armed, sync_timer: Some(stop)))
        },
      )
    }
    _, _ -> Nil
  }
}

@target(javascript)
/// One heartbeat. The function checks again that the document is still
/// eligible, sends the canonical digest to every validated peer, and arms the
/// timer for the next interval. A document that failed back onto a relay, that
/// lost its last peer, or that a caller closed after the timer was set, sends
/// nothing, and the heartbeat then ends.
///
/// The broadcast has a gate: the digest must have moved after the last
/// broadcast, or a mismatch from a peer must have cleared `last_sync_digest`.
/// The timer recurs, and an idle mesh that converged sends nothing. It does not
/// repeat the same digest in every interval without an end.
///
/// The function does not arm the timer again when this tick ran *synchronously*
/// from inside `arm_sync`. The function detects that condition because the
/// module has not stored the canceller yet, so `sync_timer` is still `None`. A
/// synchronous scheduler that armed the timer again here would recurse without
/// a bound. To run exactly one time instead is the only behaviour without a
/// loop that a clock which never advances can have. A real asynchronous
/// scheduler, and a logical one, both store the canceller before the tick. The
/// function thus arms the timer again, and the heartbeat recurs.
fn tick_sync(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  let armed_asynchronously = option.is_some(state.sync_timer)
  transport_js.set_cell(
    cell,
    State(..state, sync_armed: False, sync_timer: None),
  )
  case should_sync(state) {
    True -> {
      sync_digest(cell)
      case armed_asynchronously {
        True -> arm_sync(cell)
        False -> Nil
      }
    }
    False -> Nil
  }
}

@target(javascript)
/// The payload of one heartbeat, behind the dirty gate. The function broadcasts
/// the canonical digest only when that digest differs from the last one that the
/// peers received.
fn sync_digest(cell: Cell(State)) -> Nil {
  let digest = document_digest(cell)
  let state = transport_js.get_cell(cell)
  case digest == state.last_sync_digest {
    True -> Nil
    False -> broadcast_digest(cell)
  }
}

@target(javascript)
/// Send the canonical digest to every validated peer, and record it as the last
/// announced digest. The recurring heartbeat thus sends nothing until the
/// document moves again. Every broadcast of a digest to the whole mesh goes
/// through this function: the broadcast of the heartbeat, the flush of the relay
/// coalescer, and the final push of a failover. One of them thus cannot make the
/// gate incorrect.
fn broadcast_digest(cell: Cell(State)) -> Nil {
  let digest = document_digest(cell)
  let state = transport_js.get_cell(cell)
  transport_js.set_cell(cell, State(..state, last_sync_digest: digest))
  peer_broadcast(cell, crdt_wire.Digest(digest))
}

@target(javascript)
/// Stop the heartbeat and clear its flags. The module calls this function when
/// the last validated peer leaves, on a failover to a path where the relay is
/// primary, and on a close.
fn cancel_sync(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  cancel(state.sync_timer)
  transport_js.set_cell(
    cell,
    State(..state, sync_armed: False, sync_timer: None),
  )
}

@target(javascript)
/// Send one message to every peer that completed the handshake.
///
/// This function is not the broadcast of the transport, and that choice is
/// deliberate. A data channel can be open before the module checks its `hello`
/// message. A peer that has not proved that it agrees about the room, the
/// protocol, the compatibility tag, and the root must not receive the deltas of
/// this document.
fn peer_broadcast(cell: Cell(State), message: Message) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.transport {
    None -> Nil
    Some(transport) -> {
      let payload = crdt_core.encode(state.document, message)
      greeted_peers(state)
      |> list.each(fn(peer_id) {
        let _ = p2p_transport_js.send(transport, peer_id, payload)
        Nil
      })
    }
  }
}

@target(javascript)
/// Report one status. The handler is application code, and this function
/// contains it. An exception from a status handler must not skip a state
/// request, suppress a readiness result, or leave the peers after it. The
/// function does not report that exception again, because the only channel for
/// such a report is the channel that just threw.
fn emit(cell: Cell(State), status: Status) -> Nil {
  let state = transport_js.get_cell(cell)
  contained(fn() { state.on_status(status) })
}

// ─────────────────────────────────────────────────────────────────────────────
// Events
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// Deliver each event to the subscribers of its own address. The function reads
/// the subscriber list again for each event, so a handler that removes its
/// subscription does not receive the next event.
fn dispatch(cell: Cell(State), events: List(#(String, ChannelEvent))) -> Nil {
  list.each(events, fn(entry) {
    let #(address, event) = entry
    transport_js.get_cell(cell).subscriptions
    |> list.filter(fn(subscriber) { subscriber.address == address })
    |> list.each(fn(subscriber) {
      guard(fn() { subscriber.handler(event) }, fn(detail) {
        emit(cell, SubscriberFailed(address, detail))
      })
    })
  })
}

@target(javascript)
/// Subscribe to every event on one channel, of every kind. The typed wrapper of
/// each kind, below, is the usual entry point.
pub fn subscribe(
  handle: Handle(kind),
  handler: fn(ChannelEvent) -> Nil,
) -> Subscription {
  let cell = handle.cell
  let state = transport_js.get_cell(cell)
  let id = state.next_subscription
  transport_js.set_cell(
    cell,
    State(..state, next_subscription: id + 1, subscriptions: [
      Subscriber(id: id, address: handle.address, handler: handler),
      ..state.subscriptions
    ]),
  )
  Subscription(cell: cell, id: id)
}

@target(javascript)
/// Remove a subscription. A second call has no more effect.
pub fn unsubscribe(subscription: Subscription) -> Nil {
  let cell = subscription.cell
  let state = transport_js.get_cell(cell)
  transport_js.set_cell(
    cell,
    State(
      ..state,
      subscriptions: list.filter(state.subscriptions, fn(subscriber) {
        subscriber.id != subscription.id
      }),
    ),
  )
}

@target(javascript)
fn subscribe_narrowed(
  handle: Handle(kind),
  handler: fn(a) -> Nil,
  narrow: fn(ChannelEvent) -> Option(a),
) -> Subscription {
  use event <- subscribe(handle)
  case narrow(event) {
    Some(narrowed) -> handler(narrowed)
    None -> Nil
  }
}

@target(javascript)
pub fn subscribe_pn_counter(
  handle: Handle(schema.PnCounterChannel),
  handler: fn(pn_counter_kernel.PnCounterEvent) -> Nil,
) -> Subscription {
  use event <- subscribe_narrowed(handle, handler)
  case event {
    channel.PnCounterEvent(inner) -> Some(inner)
    channel.MapEvent(_)
    | channel.CounterEvent(_)
    | channel.OrMapEvent(_)
    | channel.OrSetEvent(_)
    | channel.GSetEvent(_)
    | channel.TwoPSetEvent(_)
    | channel.RegisterCollectionEvent(_)
    | channel.ClaimsEvent(_)
    | channel.TaskManagerEvent(_)
    | channel.PactMapEvent(_)
    | channel.JsonOtEvent(_)
    | channel.DirectoryEvent(_)
    | channel.OrderedCollectionEvent(_)
    | channel.SequenceEvent(_)
    | channel.RichTextEvent(_)
    | channel.TextEvent(_) -> None
  }
}

@target(javascript)
pub fn subscribe_or_map(
  handle: Handle(schema.OrMapChannel),
  handler: fn(or_map_kernel.OrMapEvent) -> Nil,
) -> Subscription {
  use event <- subscribe_narrowed(handle, handler)
  case event {
    channel.OrMapEvent(inner) -> Some(inner)
    channel.MapEvent(_)
    | channel.CounterEvent(_)
    | channel.PnCounterEvent(_)
    | channel.OrSetEvent(_)
    | channel.GSetEvent(_)
    | channel.TwoPSetEvent(_)
    | channel.RegisterCollectionEvent(_)
    | channel.ClaimsEvent(_)
    | channel.TaskManagerEvent(_)
    | channel.PactMapEvent(_)
    | channel.JsonOtEvent(_)
    | channel.DirectoryEvent(_)
    | channel.OrderedCollectionEvent(_)
    | channel.SequenceEvent(_)
    | channel.RichTextEvent(_)
    | channel.TextEvent(_) -> None
  }
}

@target(javascript)
pub fn subscribe_or_set(
  handle: Handle(schema.OrSetChannel),
  handler: fn(or_set_kernel.OrSetEvent) -> Nil,
) -> Subscription {
  use event <- subscribe_narrowed(handle, handler)
  case event {
    channel.OrSetEvent(inner) -> Some(inner)
    channel.MapEvent(_)
    | channel.CounterEvent(_)
    | channel.PnCounterEvent(_)
    | channel.OrMapEvent(_)
    | channel.GSetEvent(_)
    | channel.TwoPSetEvent(_)
    | channel.RegisterCollectionEvent(_)
    | channel.ClaimsEvent(_)
    | channel.TaskManagerEvent(_)
    | channel.PactMapEvent(_)
    | channel.JsonOtEvent(_)
    | channel.DirectoryEvent(_)
    | channel.OrderedCollectionEvent(_)
    | channel.SequenceEvent(_)
    | channel.RichTextEvent(_)
    | channel.TextEvent(_) -> None
  }
}

@target(javascript)
pub fn subscribe_g_set(
  handle: Handle(schema.GSetChannel),
  handler: fn(g_set_kernel.GSetEvent) -> Nil,
) -> Subscription {
  use event <- subscribe_narrowed(handle, handler)
  case event {
    channel.GSetEvent(inner) -> Some(inner)
    channel.MapEvent(_)
    | channel.CounterEvent(_)
    | channel.PnCounterEvent(_)
    | channel.OrMapEvent(_)
    | channel.OrSetEvent(_)
    | channel.TwoPSetEvent(_)
    | channel.RegisterCollectionEvent(_)
    | channel.ClaimsEvent(_)
    | channel.TaskManagerEvent(_)
    | channel.PactMapEvent(_)
    | channel.JsonOtEvent(_)
    | channel.DirectoryEvent(_)
    | channel.OrderedCollectionEvent(_)
    | channel.SequenceEvent(_)
    | channel.RichTextEvent(_)
    | channel.TextEvent(_) -> None
  }
}

@target(javascript)
pub fn subscribe_two_p_set(
  handle: Handle(schema.TwoPSetChannel),
  handler: fn(two_p_set_kernel.TwoPSetEvent) -> Nil,
) -> Subscription {
  use event <- subscribe_narrowed(handle, handler)
  case event {
    channel.TwoPSetEvent(inner) -> Some(inner)
    channel.MapEvent(_)
    | channel.CounterEvent(_)
    | channel.PnCounterEvent(_)
    | channel.OrMapEvent(_)
    | channel.OrSetEvent(_)
    | channel.GSetEvent(_)
    | channel.RegisterCollectionEvent(_)
    | channel.ClaimsEvent(_)
    | channel.TaskManagerEvent(_)
    | channel.PactMapEvent(_)
    | channel.JsonOtEvent(_)
    | channel.DirectoryEvent(_)
    | channel.OrderedCollectionEvent(_)
    | channel.SequenceEvent(_)
    | channel.RichTextEvent(_)
    | channel.TextEvent(_) -> None
  }
}

@target(javascript)
pub fn subscribe_sequence(
  handle: Handle(schema.SequenceChannel),
  handler: fn(sequence_kernel.SequenceEvent) -> Nil,
) -> Subscription {
  use event <- subscribe_narrowed(handle, handler)
  case event {
    channel.SequenceEvent(inner) -> Some(inner)
    channel.MapEvent(_)
    | channel.CounterEvent(_)
    | channel.PnCounterEvent(_)
    | channel.OrMapEvent(_)
    | channel.OrSetEvent(_)
    | channel.GSetEvent(_)
    | channel.TwoPSetEvent(_)
    | channel.RegisterCollectionEvent(_)
    | channel.ClaimsEvent(_)
    | channel.TaskManagerEvent(_)
    | channel.PactMapEvent(_)
    | channel.JsonOtEvent(_)
    | channel.DirectoryEvent(_)
    | channel.OrderedCollectionEvent(_)
    | channel.RichTextEvent(_)
    | channel.TextEvent(_) -> None
  }
}

@target(javascript)
pub fn subscribe_text(
  handle: Handle(schema.TextChannel),
  handler: fn(text_kernel.TextEvent) -> Nil,
) -> Subscription {
  use event <- subscribe_narrowed(handle, handler)
  case event {
    channel.TextEvent(inner) -> Some(inner)
    channel.MapEvent(_)
    | channel.CounterEvent(_)
    | channel.PnCounterEvent(_)
    | channel.OrMapEvent(_)
    | channel.OrSetEvent(_)
    | channel.GSetEvent(_)
    | channel.TwoPSetEvent(_)
    | channel.RegisterCollectionEvent(_)
    | channel.ClaimsEvent(_)
    | channel.TaskManagerEvent(_)
    | channel.PactMapEvent(_)
    | channel.JsonOtEvent(_)
    | channel.DirectoryEvent(_)
    | channel.OrderedCollectionEvent(_)
    | channel.SequenceEvent(_)
    | channel.RichTextEvent(_) -> None
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Channels
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// The root of the document, typed by the `CrdtKind` value that the config
/// named.
pub fn root(document: CrdtDocument(root)) -> Handle(root) {
  Handle(cell: document.cell, address: crdt_wire.root_address)
}

@target(javascript)
/// The channel address of a handle. The value is `root` for the root. For every
/// other channel it is `<replica>:<counter>`, which names the creator of that
/// channel.
pub fn address(handle: Handle(kind)) -> String {
  handle.address
}

@target(javascript)
/// Register a new channel of the kind `kind`, and announce it to every peer.
/// The function checks that kind against the eligibility boundary. A channel
/// that cannot merge without a sequencer is thus refused here, and the replicas
/// do not diverge later.
pub fn create_channel(
  document: CrdtDocument(root),
  kind: p2p.CrdtKind(kind),
) -> Result(Handle(kind), P2pError) {
  let cell = document.cell
  let state = transport_js.get_cell(cell)
  use _ <- result.try(usable(cell, state))
  case crdt_core.create_channel(state.document, p2p.kind_init(kind)) {
    Error(error) -> {
      emit(cell, Failed(error))
      Error(error)
    }
    Ok(#(core, outcome)) -> {
      transport_js.set_cell(cell, State(..state, document: core))
      list.each(outcome.broadcast, fn(message) { broadcast(cell, message) })
      case outcome.created {
        [descriptor, ..] -> Ok(Handle(cell: cell, address: descriptor.address))
        [] -> {
          let error =
            p2p.InvalidEnvelope(
              crdt_core.replica(core),
              "channel creation announced no descriptor",
            )
          emit(cell, Failed(error))
          Error(error)
        }
      }
    }
  }
}

@target(javascript)
/// Take a typed handle onto a channel that exists. That channel is one that a
/// peer announced, or one that an imported snapshot carried. The address must be
/// registered, and its channel type must be exactly `kind`.
pub fn resolve_channel(
  document: CrdtDocument(root),
  kind: p2p.CrdtKind(kind),
  address address: String,
) -> Result(Handle(kind), P2pError) {
  let cell = document.cell
  let state = transport_js.get_cell(cell)
  use _ <- result.try(usable(cell, state))
  use found <- result.try(fail(
    cell,
    crdt_core.channel_type(state.document, address),
  ))
  let expected = p2p.kind_type(kind)
  case found == expected {
    True -> Ok(Handle(cell: cell, address: address))
    False -> {
      let error = p2p.ChannelTypeMismatch(address, expected, found)
      emit(cell, Failed(error))
      Error(error)
    }
  }
}

@target(javascript)
/// Every channel address that this document holds, in canonical order.
pub fn addresses(document: CrdtDocument(root)) -> List(String) {
  crdt_core.descriptors(transport_js.get_cell(document.cell).document)
  |> list.map(fn(descriptor) { descriptor.address })
}

// ─────────────────────────────────────────────────────────────────────────────
// Reads and mutations
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
fn usable(cell: Cell(State), state: State) -> Result(Nil, P2pError) {
  case state.closed {
    False -> Ok(Nil)
    True -> {
      emit(cell, Failed(p2p.DocumentClosed))
      Error(p2p.DocumentClosed)
    }
  }
}

@target(javascript)
/// Report a local operation that failed, on the status stream, and also return
/// that failure. A status log is thus a complete account of the document.
fn fail(
  cell: Cell(State),
  outcome: Result(a, P2pError),
) -> Result(a, P2pError) {
  case outcome {
    Ok(value) -> Ok(value)
    Error(error) -> {
      emit(cell, Failed(error))
      Error(error)
    }
  }
}

@target(javascript)
fn read(
  handle: Handle(kind),
  expected: ChannelType,
  reader: fn(channel.ChannelState) -> a,
) -> Result(a, P2pError) {
  let cell = handle.cell
  let state = transport_js.get_cell(cell)
  use _ <- result.try(usable(cell, state))
  use channel_state <- result.try(fail(
    cell,
    crdt_core.channel_state(state.document, handle.address),
  ))
  let found = channel.channel_type(channel_state)
  case found == expected {
    True -> Ok(reader(channel_state))
    False -> {
      let error = p2p.ChannelTypeMismatch(handle.address, expected, found)
      emit(cell, Failed(error))
      Error(error)
    }
  }
}

@target(javascript)
/// Write a local edit. The function merges it into the visible state
/// immediately, broadcasts it to every open peer, and reports it to the
/// subscribers of this address one time.
fn mutate(
  handle: Handle(kind),
  edit: channel.P2pEdit,
) -> Result(Nil, P2pError) {
  let cell = handle.cell
  let state = transport_js.get_cell(cell)
  use _ <- result.try(usable(cell, state))
  use #(core, outcome) <- result.try(fail(
    cell,
    crdt_core.edit(state.document, handle.address, edit),
  ))
  transport_js.set_cell(cell, State(..state, document: core))
  list.each(outcome.broadcast, fn(message) { broadcast(cell, message) })
  dispatch(cell, outcome.events)
  Ok(Nil)
}

// ── PN counter ───────────────────────────────────────────────────────────────

@target(javascript)
/// Add `amount` to the counter. A negative amount decrements it.
pub fn pn_counter_update(
  handle: Handle(schema.PnCounterChannel),
  amount: Int,
) -> Result(Nil, P2pError) {
  mutate(handle, channel.PnCounterEdit(amount))
}

@target(javascript)
pub fn pn_counter_increment(
  handle: Handle(schema.PnCounterChannel),
  amount: Int,
) -> Result(Nil, P2pError) {
  pn_counter_update(handle, amount)
}

@target(javascript)
pub fn pn_counter_decrement(
  handle: Handle(schema.PnCounterChannel),
  amount: Int,
) -> Result(Nil, P2pError) {
  pn_counter_update(handle, -amount)
}

@target(javascript)
pub fn pn_counter_value(
  handle: Handle(schema.PnCounterChannel),
) -> Result(Int, P2pError) {
  use state <- read(handle, channel.PnCounterChannel)
  case state {
    channel.PnCounterState(kernel) -> pn_counter_kernel.value(kernel)
    channel.MapState(_)
    | channel.CounterState(_)
    | channel.OrMapState(_)
    | channel.OrSetState(_)
    | channel.GSetState(_)
    | channel.TwoPSetState(_)
    | channel.RegisterCollectionState(_)
    | channel.ClaimsState(_)
    | channel.TaskManagerState(_)
    | channel.PactMapState(_)
    | channel.JsonOtState(_)
    | channel.DirectoryState(_)
    | channel.OrderedCollectionState(_)
    | channel.SequenceState(_)
    | channel.RichTextState(_)
    | channel.TextState(_) -> 0
  }
}

// ── OR-map ───────────────────────────────────────────────────────────────────

@target(javascript)
/// Write a register value. This function is valid on a `RegisterMode` map only.
/// A tally map returns the mode mismatch error of the kernel.
pub fn or_map_set(
  handle: Handle(schema.OrMapChannel),
  key key: String,
  value value: String,
) -> Result(Nil, P2pError) {
  mutate(
    handle,
    channel.OrMapSetRegisterEdit(key, value, transport_js.now_milliseconds()),
  )
}

@target(javascript)
/// Add to a tally. This function is valid on a `TallyMode` map only.
pub fn or_map_increment(
  handle: Handle(schema.OrMapChannel),
  key key: String,
  amount amount: Int,
) -> Result(Nil, P2pError) {
  mutate(handle, channel.OrMapIncrementEdit(key, amount))
}

@target(javascript)
pub fn or_map_remove(
  handle: Handle(schema.OrMapChannel),
  key key: String,
) -> Result(Nil, P2pError) {
  mutate(handle, channel.OrMapRemoveEdit(key))
}

@target(javascript)
pub fn or_map_value(
  handle: Handle(schema.OrMapChannel),
  key key: String,
) -> Result(Result(OrMapValue, Nil), P2pError) {
  use state <- read(handle, channel.OrMapChannel)
  case state {
    channel.OrMapState(kernel) -> or_map_kernel.get(kernel, key)
    channel.MapState(_)
    | channel.CounterState(_)
    | channel.PnCounterState(_)
    | channel.OrSetState(_)
    | channel.GSetState(_)
    | channel.TwoPSetState(_)
    | channel.RegisterCollectionState(_)
    | channel.ClaimsState(_)
    | channel.TaskManagerState(_)
    | channel.PactMapState(_)
    | channel.JsonOtState(_)
    | channel.DirectoryState(_)
    | channel.OrderedCollectionState(_)
    | channel.SequenceState(_)
    | channel.RichTextState(_)
    | channel.TextState(_) -> Error(Nil)
  }
}

@target(javascript)
/// The value of a tally key. The result is zero when the key is absent.
pub fn or_map_tally(
  handle: Handle(schema.OrMapChannel),
  key key: String,
) -> Result(Int, P2pError) {
  use value <- result.try(or_map_value(handle, key))
  case value {
    Ok(or_map_kernel.Tally(tally)) -> Ok(tally)
    Ok(or_map_kernel.Register(_)) ->
      Error(p2p.InvalidEnvelope(
        address(handle),
        "key " <> key <> " holds a register, not a tally",
      ))
    Error(Nil) -> Ok(0)
  }
}

@target(javascript)
pub fn or_map_entries(
  handle: Handle(schema.OrMapChannel),
) -> Result(List(#(String, OrMapValue)), P2pError) {
  use state <- read(handle, channel.OrMapChannel)
  case state {
    channel.OrMapState(kernel) -> or_map_kernel.entries(kernel)
    channel.MapState(_)
    | channel.CounterState(_)
    | channel.PnCounterState(_)
    | channel.OrSetState(_)
    | channel.GSetState(_)
    | channel.TwoPSetState(_)
    | channel.RegisterCollectionState(_)
    | channel.ClaimsState(_)
    | channel.TaskManagerState(_)
    | channel.PactMapState(_)
    | channel.JsonOtState(_)
    | channel.DirectoryState(_)
    | channel.OrderedCollectionState(_)
    | channel.SequenceState(_)
    | channel.RichTextState(_)
    | channel.TextState(_) -> []
  }
}

// ── OR-set ───────────────────────────────────────────────────────────────────

@target(javascript)
pub fn or_set_add(
  handle: Handle(schema.OrSetChannel),
  element: String,
) -> Result(Nil, P2pError) {
  mutate(handle, channel.OrSetAddEdit(element))
}

@target(javascript)
pub fn or_set_remove(
  handle: Handle(schema.OrSetChannel),
  element: String,
) -> Result(Nil, P2pError) {
  mutate(handle, channel.OrSetRemoveEdit(element))
}

@target(javascript)
pub fn or_set_contains(
  handle: Handle(schema.OrSetChannel),
  element: String,
) -> Result(Bool, P2pError) {
  use state <- read(handle, channel.OrSetChannel)
  case state {
    channel.OrSetState(kernel) -> or_set_kernel.contains(kernel, element)
    channel.MapState(_)
    | channel.CounterState(_)
    | channel.PnCounterState(_)
    | channel.OrMapState(_)
    | channel.GSetState(_)
    | channel.TwoPSetState(_)
    | channel.RegisterCollectionState(_)
    | channel.ClaimsState(_)
    | channel.TaskManagerState(_)
    | channel.PactMapState(_)
    | channel.JsonOtState(_)
    | channel.DirectoryState(_)
    | channel.OrderedCollectionState(_)
    | channel.SequenceState(_)
    | channel.RichTextState(_)
    | channel.TextState(_) -> False
  }
}

@target(javascript)
pub fn or_set_values(
  handle: Handle(schema.OrSetChannel),
) -> Result(List(String), P2pError) {
  use state <- read(handle, channel.OrSetChannel)
  case state {
    channel.OrSetState(kernel) -> or_set_kernel.values(kernel)
    channel.MapState(_)
    | channel.CounterState(_)
    | channel.PnCounterState(_)
    | channel.OrMapState(_)
    | channel.GSetState(_)
    | channel.TwoPSetState(_)
    | channel.RegisterCollectionState(_)
    | channel.ClaimsState(_)
    | channel.TaskManagerState(_)
    | channel.PactMapState(_)
    | channel.JsonOtState(_)
    | channel.DirectoryState(_)
    | channel.OrderedCollectionState(_)
    | channel.SequenceState(_)
    | channel.RichTextState(_)
    | channel.TextState(_) -> []
  }
}

// ── G-set ────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn g_set_add(
  handle: Handle(schema.GSetChannel),
  element: String,
) -> Result(Nil, P2pError) {
  mutate(handle, channel.GSetAddEdit(element))
}

@target(javascript)
pub fn g_set_contains(
  handle: Handle(schema.GSetChannel),
  element: String,
) -> Result(Bool, P2pError) {
  use state <- read(handle, channel.GSetChannel)
  case state {
    channel.GSetState(kernel) -> g_set_kernel.contains(kernel, element)
    channel.MapState(_)
    | channel.CounterState(_)
    | channel.PnCounterState(_)
    | channel.OrMapState(_)
    | channel.OrSetState(_)
    | channel.TwoPSetState(_)
    | channel.RegisterCollectionState(_)
    | channel.ClaimsState(_)
    | channel.TaskManagerState(_)
    | channel.PactMapState(_)
    | channel.JsonOtState(_)
    | channel.DirectoryState(_)
    | channel.OrderedCollectionState(_)
    | channel.SequenceState(_)
    | channel.RichTextState(_)
    | channel.TextState(_) -> False
  }
}

@target(javascript)
pub fn g_set_values(
  handle: Handle(schema.GSetChannel),
) -> Result(List(String), P2pError) {
  use state <- read(handle, channel.GSetChannel)
  case state {
    channel.GSetState(kernel) -> g_set_kernel.values(kernel)
    channel.MapState(_)
    | channel.CounterState(_)
    | channel.PnCounterState(_)
    | channel.OrMapState(_)
    | channel.OrSetState(_)
    | channel.TwoPSetState(_)
    | channel.RegisterCollectionState(_)
    | channel.ClaimsState(_)
    | channel.TaskManagerState(_)
    | channel.PactMapState(_)
    | channel.JsonOtState(_)
    | channel.DirectoryState(_)
    | channel.OrderedCollectionState(_)
    | channel.SequenceState(_)
    | channel.RichTextState(_)
    | channel.TextState(_) -> []
  }
}

// ── 2P-set ───────────────────────────────────────────────────────────────────

@target(javascript)
pub fn two_p_set_add(
  handle: Handle(schema.TwoPSetChannel),
  element: String,
) -> Result(Nil, P2pError) {
  mutate(handle, channel.TwoPSetAddEdit(element))
}

@target(javascript)
pub fn two_p_set_remove(
  handle: Handle(schema.TwoPSetChannel),
  element: String,
) -> Result(Nil, P2pError) {
  mutate(handle, channel.TwoPSetRemoveEdit(element))
}

@target(javascript)
pub fn two_p_set_contains(
  handle: Handle(schema.TwoPSetChannel),
  element: String,
) -> Result(Bool, P2pError) {
  use state <- read(handle, channel.TwoPSetChannel)
  case state {
    channel.TwoPSetState(kernel) -> two_p_set_kernel.contains(kernel, element)
    channel.MapState(_)
    | channel.CounterState(_)
    | channel.PnCounterState(_)
    | channel.OrMapState(_)
    | channel.OrSetState(_)
    | channel.GSetState(_)
    | channel.RegisterCollectionState(_)
    | channel.ClaimsState(_)
    | channel.TaskManagerState(_)
    | channel.PactMapState(_)
    | channel.JsonOtState(_)
    | channel.DirectoryState(_)
    | channel.OrderedCollectionState(_)
    | channel.SequenceState(_)
    | channel.RichTextState(_)
    | channel.TextState(_) -> False
  }
}

@target(javascript)
pub fn two_p_set_values(
  handle: Handle(schema.TwoPSetChannel),
) -> Result(List(String), P2pError) {
  use state <- read(handle, channel.TwoPSetChannel)
  case state {
    channel.TwoPSetState(kernel) -> two_p_set_kernel.values(kernel)
    channel.MapState(_)
    | channel.CounterState(_)
    | channel.PnCounterState(_)
    | channel.OrMapState(_)
    | channel.OrSetState(_)
    | channel.GSetState(_)
    | channel.RegisterCollectionState(_)
    | channel.ClaimsState(_)
    | channel.TaskManagerState(_)
    | channel.PactMapState(_)
    | channel.JsonOtState(_)
    | channel.DirectoryState(_)
    | channel.OrderedCollectionState(_)
    | channel.SequenceState(_)
    | channel.RichTextState(_)
    | channel.TextState(_) -> []
  }
}

// ── Sequence ─────────────────────────────────────────────────────────────────

@target(javascript)
pub fn sequence_insert(
  handle: Handle(schema.SequenceChannel),
  index index: Int,
  value value: Json,
) -> Result(Nil, P2pError) {
  mutate(handle, channel.SequenceInsertEdit(index, value))
}

@target(javascript)
pub fn sequence_delete(
  handle: Handle(schema.SequenceChannel),
  index index: Int,
) -> Result(Nil, P2pError) {
  mutate(handle, channel.SequenceDeleteEdit(index))
}

@target(javascript)
pub fn sequence_move(
  handle: Handle(schema.SequenceChannel),
  from from: Int,
  to to: Int,
) -> Result(Nil, P2pError) {
  mutate(handle, channel.SequenceMoveEdit(from, to))
}

@target(javascript)
pub fn sequence_replace(
  handle: Handle(schema.SequenceChannel),
  index index: Int,
  value value: Json,
) -> Result(Nil, P2pError) {
  mutate(handle, channel.SequenceReplaceEdit(index, value))
}

@target(javascript)
pub fn sequence_values(
  handle: Handle(schema.SequenceChannel),
) -> Result(List(Json), P2pError) {
  use state <- read(handle, channel.SequenceChannel)
  case state {
    channel.SequenceState(kernel) -> sequence_kernel.values(kernel)
    channel.MapState(_)
    | channel.CounterState(_)
    | channel.PnCounterState(_)
    | channel.OrMapState(_)
    | channel.OrSetState(_)
    | channel.GSetState(_)
    | channel.TwoPSetState(_)
    | channel.RegisterCollectionState(_)
    | channel.ClaimsState(_)
    | channel.TaskManagerState(_)
    | channel.PactMapState(_)
    | channel.JsonOtState(_)
    | channel.DirectoryState(_)
    | channel.OrderedCollectionState(_)
    | channel.RichTextState(_)
    | channel.TextState(_) -> []
  }
}

// ── Text ─────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn text_insert(
  handle: Handle(schema.TextChannel),
  index index: Int,
  value value: String,
) -> Result(Nil, P2pError) {
  mutate(handle, channel.TextInsertEdit(index, value))
}

@target(javascript)
pub fn text_delete_range(
  handle: Handle(schema.TextChannel),
  start start: Int,
  end end: Int,
) -> Result(Nil, P2pError) {
  mutate(handle, channel.TextDeleteRangeEdit(start, end))
}

@target(javascript)
pub fn text_replace_range(
  handle: Handle(schema.TextChannel),
  start start: Int,
  end end: Int,
  value value: String,
) -> Result(Nil, P2pError) {
  mutate(handle, channel.TextReplaceRangeEdit(start, end, value))
}

@target(javascript)
pub fn text_append(
  handle: Handle(schema.TextChannel),
  value: String,
) -> Result(Nil, P2pError) {
  mutate(handle, channel.TextAppendEdit(value))
}

@target(javascript)
pub fn text_value(
  handle: Handle(schema.TextChannel),
) -> Result(String, P2pError) {
  use state <- read(handle, channel.TextChannel)
  case state {
    channel.TextState(kernel) -> text_kernel.value(kernel)
    channel.MapState(_)
    | channel.CounterState(_)
    | channel.PnCounterState(_)
    | channel.OrMapState(_)
    | channel.OrSetState(_)
    | channel.GSetState(_)
    | channel.TwoPSetState(_)
    | channel.RegisterCollectionState(_)
    | channel.ClaimsState(_)
    | channel.TaskManagerState(_)
    | channel.PactMapState(_)
    | channel.JsonOtState(_)
    | channel.DirectoryState(_)
    | channel.OrderedCollectionState(_)
    | channel.SequenceState(_)
    | channel.RichTextState(_) -> ""
  }
}

@target(javascript)
/// The current optimistic grapheme count of the text.
pub fn text_length(
  handle: Handle(schema.TextChannel),
) -> Result(Int, P2pError) {
  use state <- read(handle, channel.TextChannel)
  case state {
    channel.TextState(kernel) -> text_kernel.length(kernel)
    channel.MapState(_)
    | channel.CounterState(_)
    | channel.PnCounterState(_)
    | channel.OrMapState(_)
    | channel.OrSetState(_)
    | channel.GSetState(_)
    | channel.TwoPSetState(_)
    | channel.RegisterCollectionState(_)
    | channel.ClaimsState(_)
    | channel.TaskManagerState(_)
    | channel.PactMapState(_)
    | channel.JsonOtState(_)
    | channel.DirectoryState(_)
    | channel.OrderedCollectionState(_)
    | channel.SequenceState(_)
    | channel.RichTextState(_) -> 0
  }
}

@target(javascript)
/// Create a stable anchor at the gap before the optimistic grapheme at `index`.
/// `bias_before` and `bias_after` set the bias. The result is a typed error when
/// the index is out of bounds.
pub fn text_anchor_at(
  handle: Handle(schema.TextChannel),
  index: Int,
  bias: Bias,
) -> Result(TextAnchor, P2pError) {
  case read(handle, channel.TextChannel, fn(state) { state }) {
    Ok(channel.TextState(kernel)) ->
      text_kernel.anchor_at(kernel, index, bias)
      |> result.map_error(fn(error) {
        p2p.InvalidEnvelope(
          address(handle),
          text_kernel.anchor_error_detail(error),
        )
      })
    Ok(_) ->
      Error(p2p.InvalidEnvelope(
        address(handle),
        "registered text channel stored a non-text state",
      ))
    Error(error) -> Error(error)
  }
}

@target(javascript)
/// Resolve an anchor to a current optimistic grapheme index. The result is a
/// typed error when the anchor target is stale or unknown.
pub fn text_resolve_anchor(
  handle: Handle(schema.TextChannel),
  anchor: TextAnchor,
) -> Result(Int, P2pError) {
  case read(handle, channel.TextChannel, fn(state) { state }) {
    Ok(channel.TextState(kernel)) ->
      text_kernel.resolve_anchor(kernel, anchor)
      |> result.map_error(fn(error) {
        p2p.InvalidEnvelope(
          address(handle),
          text_kernel.anchor_error_detail(error),
        )
      })
    Ok(_) ->
      Error(p2p.InvalidEnvelope(
        address(handle),
        "registered text channel stored a non-text state",
      ))
    Error(error) -> Error(error)
  }
}

@target(javascript)
/// An anchor at the start of the text. It always resolves to 0. The function is
/// pure. It needs no handle, because the anchor carries no document state.
pub fn text_start_anchor() -> TextAnchor {
  text_kernel.start_anchor()
}

@target(javascript)
/// An anchor at the end of the text. It always resolves to the current grapheme
/// count, and it moves as the text becomes longer. The function is pure, the
/// same as `text_start_anchor`.
pub fn text_end_anchor() -> TextAnchor {
  text_kernel.end_anchor()
}

@target(javascript)
/// Encode an anchor as a self-describing JSON value.
pub fn text_anchor_to_json(anchor: TextAnchor) -> Json {
  text_kernel.anchor_to_json(anchor)
}

@target(javascript)
/// Decode an anchor from a JSON string that `text_anchor_to_json` produced. The
/// result is a typed error for malformed JSON.
pub fn text_anchor_from_json(
  json_string: String,
) -> Result(TextAnchor, P2pError) {
  case text_kernel.anchor_from_json(json_string) {
    Ok(anchor) -> Ok(anchor)
    Error(error) ->
      Error(p2p.InvalidEnvelope(
        "textAnchor",
        "invalid anchor JSON: " <> format_json_decode_error(error),
      ))
  }
}

@target(javascript)
fn format_json_decode_error(error: json.DecodeError) -> String {
  case error {
    json.UnexpectedEndOfInput -> "unexpected end of input"
    json.UnexpectedByte(byte) -> "unexpected byte: " <> byte
    json.UnexpectedSequence(bytes) -> "unexpected sequence: " <> bytes
    json.UnableToDecode(errors) ->
      "unable to decode: "
      <> string.join(
        list.map(errors, fn(e) {
          "expected "
          <> e.expected
          <> ", found "
          <> e.found
          <> case e.path {
            [] -> ""
            path -> " at " <> string.join(path, ".")
          }
        }),
        "; ",
      )
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Snapshots
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// The whole `crdt_core` snapshot that `import_snapshot` can read: the full
/// CRDT state of every channel, with the authoring cursors, in canonical
/// order.
///
/// The function returns a `Result` value, because every other option is worse.
/// The bytes come from `canonical_json`, and the function reads them again here
/// to reach the value type of `gleam/json`, which has no raw constructor. That
/// read cannot fail for anything that this library emits. But a public function
/// that panicked would be worse, and a public function that quietly returned a
/// snapshot with null in place of the parts that it could not decode would be
/// worse still. No caller could trust such a snapshot.
pub fn export_snapshot(document: CrdtDocument(root)) -> Result(Json, P2pError) {
  let state = transport_js.get_cell(document.cell)
  let raw = crdt_core.canonical_json(state.document)
  json.parse(raw, wire.json_value_decoder())
  |> result.replace_error(p2p.InvalidEnvelope(
    crdt_core.replica(state.document),
    "the exported snapshot could not be read back as JSON",
  ))
}

@target(javascript)
/// Merge an exported snapshot into a live document.
///
/// This merge is a join, the same as the import in the core. The local channels
/// and the local edits all stay. The subscriber events go out exactly one time.
/// A merged state on an attached document goes to the existing anti-entropy and
/// relay code, and it does not take a new path here.
pub fn merge_snapshot(
  document: CrdtDocument(root),
  snapshot: Json,
) -> Result(crdt_core.Outcome, P2pError) {
  let cell = document.cell
  let state = transport_js.get_cell(cell)
  use _ <- result.try(usable(cell, state))
  let durable = state.path == Sequenced && state.phase == RelayPrimaryPhase
  let before = case durable {
    True -> document_digest(cell)
    False -> ""
  }
  use #(core, outcome) <- result.try(fail(
    cell,
    crdt_core.import_snapshot(state.document, json.to_string(snapshot)),
  ))
  transport_js.set_cell(cell, State(..state, document: core))
  dispatch(cell, outcome.events)
  refresh_sync(cell)
  case durable && document_digest(cell) != before, state.transport {
    True, Some(_) -> owe_publication(cell)
    True, None -> publish_while_primary(cell)
    False, _ -> Nil
  }
  Ok(outcome)
}

@target(javascript)
/// Build a document again from an exported snapshot.
///
/// The function checks the size, the protocol version, the room, the
/// compatibility tag, the root type, and the eligibility of every channel,
/// before it loads one channel. The result is detached. Give it to `attach` to
/// bring it online.
pub fn import_snapshot(
  config: Config(root),
  snapshot: Json,
) -> Result(CrdtDocument(root), P2pError) {
  use document <- result.try(new_document(config))
  let cell = document.cell
  let state = transport_js.get_cell(cell)
  use #(core, _outcome) <- result.try(crdt_core.import_snapshot(
    state.document,
    json.to_string(snapshot),
  ))
  transport_js.set_cell(cell, State(..state, document: core, imported: True))
  Ok(document)
}

// ─────────────────────────────────────────────────────────────────────────────
// Diagnostics
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn room(document: CrdtDocument(root)) -> String {
  crdt_core.room(transport_js.get_cell(document.cell).document)
}

@target(javascript)
/// The signaling room that this document belongs to. This function is another
/// name for `room`, and the name suits a key in persistent storage.
pub fn room_id(document: CrdtDocument(root)) -> String {
  room(document)
}

@target(javascript)
/// The compatibility tag of the application that this document applies.
pub fn compatibility_tag(document: CrdtDocument(root)) -> String {
  crdt_core.compatibility(transport_js.get_cell(document.cell).document)
}

@target(javascript)
/// The authorship identity of this replica: the label from the config, with a
/// random session id for this connection after it.
pub fn replica_id(document: CrdtDocument(root)) -> String {
  crdt_core.replica(transport_js.get_cell(document.cell).document)
}

@target(javascript)
/// The label of the application, without the session id.
pub fn replica_label(document: CrdtDocument(root)) -> String {
  transport_js.get_cell(document.cell).label
}

@target(javascript)
/// The canonical digest of the document. Two replicas that hold the same
/// logical state and the same causal state get the same value, on either
/// compile target.
///
/// The module computes this value one time for each document state, and it
/// reuses that value until the document moves. To read it in a render loop thus
/// costs one comparison, and not a hash of the whole document.
pub fn digest(document: CrdtDocument(root)) -> String {
  document_digest(document.cell)
}

@target(javascript)
/// The number of times that this document canonicalized and hashed itself.
///
/// This function is a diagnostic. Every digest that this facade needs comes
/// from one computation for each document state. Those digests are the
/// heartbeat, the comparison against a peer, the publication and the
/// attestation of the relay, and the `digest` function itself. This count
/// reports that fact: it increases when the document moved after the last
/// digest, and it does not increase when the document did not move.
pub fn digest_computations(document: CrdtDocument(root)) -> Int {
  let state = transport_js.get_cell(document.cell)
  transport_js.get_cell(state.digest_cache).computations
}

@target(javascript)
/// The peers that completed the `hello` handshake, sorted.
pub fn peers(document: CrdtDocument(root)) -> List(String) {
  greeted_peers(transport_js.get_cell(document.cell))
}

@target(javascript)
pub fn peer_count(document: CrdtDocument(root)) -> Int {
  list.length(peers(document))
}

@target(javascript)
/// The progress of this replica through a join into its room. The value is
/// `Joining` until a peer passes its checks, `WaitingForState` while a bootstrap
/// `stateRequest` message has no answer, and `Bootstrapped` after the state of a
/// room merges. This function is a diagnostic that pairs with `peer_count`.
pub fn bootstrap_state(document: CrdtDocument(root)) -> BootstrapState {
  transport_js.get_cell(document.cell).bootstrap
}

@target(javascript)
/// The number of times that the anti-entropy digest of a peer told this replica
/// that it was behind, and this replica then asked for the state. That number
/// counts the partition-repair activity of the mesh. It is zero on a document
/// that always agreed with its peers.
pub fn repair_count(document: CrdtDocument(root)) -> Int {
  transport_js.get_cell(document.cell).repairs
}

@target(javascript)
/// The last peer digest that equalled the digest of this replica, if one
/// exists. That value is the most recent successful anti-entropy comparison.
/// The result is `None` until a peer confirms that the two agree.
pub fn last_digest_match(document: CrdtDocument(root)) -> Option(String) {
  transport_js.get_cell(document.cell).last_match
}

@target(javascript)
/// The readiness result that this connection delivered. The value is `None`
/// while the connection still waits for that result.
///
/// This function reports all three states correctly, and a plain boolean value
/// cannot do that. A document that failed to join and a document that is still
/// joining are two different conditions, and neither one is ready.
pub fn readiness(
  document: CrdtDocument(root),
) -> Option(Result(Nil, P2pError)) {
  transport_js.get_cell(document.cell).readiness
}

@target(javascript)
/// Whether the readiness resolved at all, in either direction. A closed document
/// gives `True`, because the module delivered its result in both
/// conditions.
pub fn readiness_resolved(document: CrdtDocument(root)) -> Bool {
  readiness(document) != None
}

@target(javascript)
pub fn is_closed(document: CrdtDocument(root)) -> Bool {
  transport_js.get_cell(document.cell).closed
}

@target(javascript)
/// The policy that the config of this document names.
pub fn policy(document: CrdtDocument(root)) -> TransportPolicy {
  transport_js.get_cell(document.cell).policy
}

@target(javascript)
/// The path that the durable traffic takes now.
///
/// The value is `PeerToPeer` until a relay merges, publishes, and matches the
/// digests. It is `PeerToPeer` again at the moment that a relay drops, before
/// the module emits the fallback status.
pub fn effective_path(document: CrdtDocument(root)) -> TransportPath {
  transport_js.get_cell(document.cell).path
}

@target(javascript)
/// Whether the relay is the durable delta path.
pub fn relay_is_primary(document: CrdtDocument(root)) -> Bool {
  transport_js.get_cell(document.cell).phase == RelayPrimaryPhase
}

@target(javascript)
/// Whether the module opened a relay lane at all. The result is `False` under
/// `P2pOnly`, and under `Auto` with no sequencer in the config.
pub fn relay_attached_lane(document: CrdtDocument(root)) -> Bool {
  transport_js.get_cell(document.cell).relay != None
}

@target(javascript)
/// A typed error on one line, for a status line and for a log.
pub fn describe_error(error: P2pError) -> String {
  let #(reason, detail) = error_parts(error)
  case detail {
    "" -> reason
    _ -> reason <> " · " <> detail
  }
}

@target(javascript)
/// The `reason` and `detail` pair on the wire, which a refusal to a peer
/// carries. These strings are stable. A peer logs them, and a test asserts on
/// them.
fn error_parts(error: P2pError) -> #(String, String) {
  case error {
    p2p.UnsupportedChannel(channel_type) -> #(
      "unsupportedChannel",
      channel.type_to_string(channel_type),
    )
    p2p.RootMismatch(expected, received) -> #(
      "rootMismatch",
      channel.type_to_string(expected)
        <> " expected, "
        <> channel.type_to_string(received)
        <> " offered",
    )
    p2p.ChannelTypeMismatch(address, expected, received) -> #(
      "channelTypeMismatch",
      address
        <> " is "
        <> channel.type_to_string(received)
        <> ", not "
        <> channel.type_to_string(expected),
    )
    p2p.DocumentClosed -> #("documentClosed", "")
    p2p.CompatibilityMismatch(expected, received) -> #(
      "compatibilityMismatch",
      expected <> " expected, " <> received <> " offered",
    )
    p2p.ProtocolMismatch(expected, received) -> #(
      "protocolMismatch",
      "v"
        <> int.to_string(expected)
        <> " expected, v"
        <> int.to_string(received),
    )
    p2p.RoomMismatch -> #("roomMismatch", "")
    p2p.RoomFull(limit) -> #("roomFull", int.to_string(limit))
    p2p.SignalingFailed(detail) -> #("signalingFailed", detail)
    p2p.SequencerUnavailable(detail) -> #("sequencerUnavailable", detail)
    p2p.SequencerUnsupported -> #("sequencerUnsupported", "")
    p2p.PeerConnectionFailed(peer_id, detail) -> #(
      "peerConnectionFailed",
      peer_id <> ": " <> detail,
    )
    p2p.InvalidEnvelope(peer_id, detail) -> #(
      "invalidEnvelope",
      peer_id <> ": " <> detail,
    )
    p2p.SnapshotTooLarge(bytes, limit) -> #(
      "snapshotTooLarge",
      int.to_string(bytes) <> " bytes, limit " <> int.to_string(limit),
    )
    p2p.ReplicaCollision(replica) -> #("replicaCollision", replica)
  }
}
