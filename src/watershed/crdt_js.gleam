//// The browser-facing CRDT facade: one peer-to-peer document, typed
//// handles onto its channels, and nothing that needs a server.
////
//// This is the p2p counterpart of `watershed_js`, and it is deliberately
//// a *separate* vocabulary. Every type here — `CrdtDocument`, `Handle`,
//// `CrdtConnection` — is opaque and shares no constructor with the
//// sequenced facade, so a p2p handle cannot be passed to a function that
//// expects a server-backed one, or the other way round. The two stacks
//// have different lifecycles (there is no ack, no summary, and no client
//// id here) and mixing them would be a type error rather than a runtime
//// surprise.
////
//// ## What `connect` does
////
//// `connect` is synchronous. It builds the configured root through
//// `crdt_core.new` and joins signaling before it returns, so the document
//// exists and is editable from the first frame — there is no sequencer to
//// wait for and nothing to hand back later.
////
//// Readiness is reported exactly once:
////
//// - the signaling adapter's roster says the room was empty, so this
////   replica is alone in it: ready immediately, with the empty
////   configured root;
//// - the roster named peers: ready after one of them has passed the
////   `hello` check and answered a `stateRequest` with a `state` message
////   that merged.
////
//// Both wait for the *complete* roster, which is the one thing an
//// adapter must report (see `p2p_transport_js.Signaling`). "No peer has
//// been announced yet" and "the room is empty" are the same picture from
//// inside a replica, and a facade that guessed would hand every late
//// joiner an empty document a moment before the room's state arrived.
//// An adapter that knows the room inside `join` — the in-page hub the
//// tests use — makes this synchronous; one that learns it over a round
//// trip — `crdt_signaling_js`, and any real service — takes a moment
//// longer to become ready and holds an empty document for exactly that
//// long, rather than announcing one.
////
//// A signaling failure before readiness resolves it once, with
//// `Error(SignalingFailed(...))` — whether `join` itself failed or the
//// socket died before the roster arrived. Everything after readiness — a
//// peer that fails its handshake, a room that empties, a merge that is
//// rejected, signaling that goes away — is a `Status`, never a second
//// readiness result.
////
//// A room whose members all greet and then go quiet is the one case that
//// waits indefinitely, and deliberately: this replica has neither the
//// room's state nor grounds to claim it is alone, so "ready" would be a
//// lie and "failed" would be wrong. An application that wants a bound
//// puts its own timer on `close`, which resolves readiness once with
//// `Error(DocumentClosed)`.
////
//// ## Application callbacks
////
//// `on_ready`, `on_status`, and every subscriber are application code
//// and are contained: an exception from one is caught and dropped rather
//// than allowed to skip a bootstrap request, suppress a readiness
//// result, or unwind the browser event that was delivering a merge. The
//// document, the transport, and the protocol's own control flow are
//// identical whether a callback returns or throws.
////
//// ## Trust boundaries
////
//// Everything that arrives on a data channel is hostile until proven
//// otherwise. Each payload is decoded by `crdt_wire`, checked to have
//// come from the peer that sent it, required to have opened with a
//// `hello` that agrees about protocol, room, compatibility tag and root,
//// and only then merged by `crdt_core`. A peer that breaks any of those
//// rules is told why, closed, and forgotten — one peer at a time. The
//// local document is never touched by a rejected message, and the
//// remaining peers are unaffected.
////
//// ## Identity
////
//// `replica_label` is an application label and appears only in status
//// reporting. The identity that authors CRDT writes and addresses
//// signaling is `label-<random session id>`, minted per connection, so
//// two tabs of the same application never share an author identity and a
//// replica that reconnects is a new writer rather than a resurrected one.
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
import watershed/ids
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
/// Everything needed to build a document and join a room. The phantom
/// `root` is the channel kind of the document's root, carried from the
/// `p2p.CrdtKind` given to `config` all the way to `root`'s handle.
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
    /// The clock every delay this document measures is measured on: the
    /// mesh anti-entropy heartbeat, the relay's digest coalescer, its
    /// reconnect and resync backoff, and the `SequencedOnly` readiness
    /// deadline. Defaults to the real clock; tests substitute a logical
    /// one and step it by hand.
    scheduler: Scheduler,
    /// The anti-entropy interval, serving both lanes: how often the mesh
    /// heartbeat checks whether the peers are owed a digest, and how long
    /// the relay path coalesces peer digests over while it is primary.
    /// `default_anti_entropy_ms` unless overridden.
    anti_entropy_interval_ms: Int,
  )
}

@target(javascript)
/// Which transports a document is allowed to use.
///
/// The choice is about *durability and reach*, never about semantics:
/// all three run the same `crdt_core` document over the same
/// `crdt_wire` envelopes, so a snapshot exported under one imports under
/// another and a room may hold replicas of more than one policy at once.
pub type TransportPolicy {
  /// Both, independently. The mesh comes up on its own schedule and the
  /// relay on its own, readiness waits only for the mesh, and the relay
  /// becomes the durable delta path if and when it proves itself.
  Auto
  /// The relay alone. No signaling, no `RTCPeerConnection`, no data
  /// channels — and readiness that waits for the relay, under a bounded
  /// deadline, because there is nothing else to be ready on.
  SequencedOnly
  /// The mesh alone. No relay is opened, no reconnect is scheduled, and
  /// a configured sequencer is ignored rather than contacted.
  P2pOnly
}

@target(javascript)
/// Where a document's durable traffic is going right now.
pub type TransportPath {
  /// Deltas go to the mesh. Every document starts here, including one
  /// that is about to attach a relay.
  PeerToPeer
  /// Deltas go to the relay, which is durable and reaches replicas this
  /// one has no peer connection to. The mesh stays open underneath.
  Sequenced
}

@target(javascript)
/// How to reach an optional sequencer relay, and how patient to be with
/// it. Timing — the reconnect backoff, the digest coalescer, the
/// readiness deadline — runs on the document's one scheduler and one
/// anti-entropy interval (`with_scheduler`, `with_anti_entropy_interval_ms`).
pub opaque type SequencerConfig {
  SequencerConfig(
    url: String,
    driver: crdt_sequencer_js.Driver,
    readiness_deadline_ms: Int,
  )
}

@target(javascript)
/// How long `SequencedOnly` waits for a relay to become primary before
/// giving up. Generous: it covers a socket handshake, a capability
/// exchange, a state replay, and a digest round trip.
pub const default_readiness_deadline_ms = 10_000

@target(javascript)
/// The anti-entropy interval, on both lanes.
///
/// This is **anti-entropy, not repair**. While the relay is primary a
/// new delta goes to the relay and the peers hear a `digest`, which is
/// how a replica that is not on this relay learns it is behind. That
/// digest must not overtake the relay's own fan-out of the same delta:
/// if it does, every peer answers a digest it is about to satisfy with a
/// `stateRequest`, and the room pays a whole-state transfer per edit.
/// So the digest waits — long enough for an ordinary relay round trip to
/// land first, short enough that a peer the relay cannot reach finds out
/// in the same breath a human would call immediate.
///
/// On the mesh path the same interval paces the recurring heartbeat —
/// but there the interval alone is not what keeps an idle room quiet:
/// the beat broadcasts only when the digest has moved since the peers
/// were last told, so a quarter-second cadence costs a quiet mesh
/// nothing while giving a moved one repair a human would call immediate.
///
/// A quarter of a second is the number, it is injectable
/// (`with_anti_entropy_interval_ms`), and it is measured on the
/// document's scheduler so tests step it rather than wait for it.
/// Failover repair does not go through it at all: that is a
/// `stateRequest` to every peer, sent in the same breath as the
/// fallback, with no delay of any kind.
pub const default_anti_entropy_ms = 250

@target(javascript)
/// A relay at `url`, speaking `crdt_relay_v1` over a real `WebSocket`.
pub fn sequencer(url: String) -> SequencerConfig {
  SequencerConfig(
    url: url,
    driver: crdt_sequencer_js.native_driver(),
    readiness_deadline_ms: default_readiness_deadline_ms,
  )
}

@target(javascript)
/// Substitute the socket layer. The seam the deterministic tests attach
/// a scripted relay to, and the same shape `p2p_transport_js.Rtc` has,
/// for the same reason.
pub fn with_relay_driver(
  config: SequencerConfig,
  driver: crdt_sequencer_js.Driver,
) -> SequencerConfig {
  SequencerConfig(..config, driver: driver)
}

@target(javascript)
/// Change how long `SequencedOnly` waits. A non-positive deadline never
/// expires, which is only ever right for a caller bounding the wait
/// itself.
pub fn with_readiness_deadline_ms(
  config: SequencerConfig,
  deadline_ms: Int,
) -> SequencerConfig {
  SequencerConfig(..config, readiness_deadline_ms: deadline_ms)
}

@target(javascript)
pub fn sequencer_url(config: SequencerConfig) -> String {
  config.url
}

@target(javascript)
/// Configure a document.
///
/// `room_id` names the signaling room and is checked on every envelope.
/// `replica_label` is a human-facing label only (see the module docs on
/// identity) and must not contain `:`, which separates the two halves of
/// a channel address. `compatibility_tag` is the application's own
/// schema version: two peers whose tags differ refuse each other rather
/// than merging documents that mean different things.
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
    anti_entropy_interval_ms: default_anti_entropy_ms,
  )
}

@target(javascript)
/// Choose which transports this document may use. `Auto` by default.
pub fn with_transport_policy(
  config: Config(root),
  policy: TransportPolicy,
) -> Config(root) {
  Config(..config, policy: policy)
}

@target(javascript)
/// Attach an optional sequencer relay. Ignored under `P2pOnly`, and
/// required under `SequencedOnly` — a `SequencedOnly` document with no
/// sequencer fails readiness once, with `SequencerUnavailable`, rather
/// than waiting for something nobody configured.
pub fn with_sequencer(
  config: Config(root),
  sequencer: SequencerConfig,
) -> Config(root) {
  Config(..config, sequencer: Some(sequencer))
}

@target(javascript)
/// Supply the STUN/TURN servers peer connections are built with.
/// Watershed ships none: an empty list is right for a LAN and for
/// same-origin loopback, and anything else is the application's to
/// provide.
pub fn with_ice_servers(
  config: Config(root),
  servers: List(IceServer),
) -> Config(root) {
  Config(..config, ice_servers: servers)
}

@target(javascript)
/// Substitute the clock every delay this document measures is measured
/// on — the mesh heartbeat, the relay's coalescer, its reconnect and
/// resync backoff, and the readiness deadline — so a test steps a
/// logical clock rather than waiting out real time.
pub fn with_scheduler(
  config: Config(root),
  scheduler: Scheduler,
) -> Config(root) {
  Config(..config, scheduler: scheduler)
}

@target(javascript)
/// Change the anti-entropy interval — the mesh heartbeat's cadence, and
/// how long the relay path coalesces peer digests over while it is
/// primary. A non-positive interval still goes through the scheduler
/// rather than sending inline.
pub fn with_anti_entropy_interval_ms(
  config: Config(root),
  interval_ms: Int,
) -> Config(root) {
  Config(..config, anti_entropy_interval_ms: interval_ms)
}

@target(javascript)
/// The signaling room this config will join.
pub fn config_room(config: Config(root)) -> String {
  config.room
}

@target(javascript)
/// The application compatibility tag this config will enforce.
pub fn config_compatibility(config: Config(root)) -> String {
  config.compatibility
}

// ─────────────────────────────────────────────────────────────────────────────
// Documents, handles, connections
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// A live CRDT document. One cell holds the whole of it — the pure
/// `crdt_core.Document`, the transport, the peer table, and the
/// subscriber list — so every handle, subscription, and callback made
/// against a document sees the same state for the connection's lifetime.
pub opaque type CrdtDocument(root) {
  CrdtDocument(cell: Cell(State))
}

@target(javascript)
/// A typed reference to one channel of a document. `kind` is the phantom
/// channel-kind tag from `watershed/schema`, so an OR-set operation
/// cannot be applied to a text handle.
pub opaque type Handle(kind) {
  Handle(cell: Cell(State), address: String)
}

@target(javascript)
/// A document's grip on signaling and its peers. `close` releases it.
pub opaque type CrdtConnection {
  CrdtConnection(cell: Option(Cell(State)))
}

@target(javascript)
/// A removable, address-scoped event subscription.
pub opaque type Subscription {
  Subscription(cell: Cell(State), id: Int)
}

@target(javascript)
/// A stable position in a text channel's optimistic string that survives
/// concurrent edits and merges. Opaque — construct one with `text_anchor_at`,
/// `text_start_anchor`, or `text_end_anchor`, or decode one with
/// `text_anchor_from_json`.
pub type TextAnchor =
  text_kernel.TextAnchor

@target(javascript)
/// Which grapheme a `TextAnchor` binds to across concurrent inserts at its
/// gap. `Before` binds to the following grapheme (inserts at the gap push it
/// right); `After` binds to the preceding grapheme (inserts at the gap land
/// after it). Re-exported so callers don't need a direct `lattice_sequence`
/// dependency to build one.
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
    /// `None` until `attach` has a transport, and again after `close`.
    transport: Option(Transport),
    peers: Dict(String, Peer),
    subscriptions: List(Subscriber),
    next_subscription: Int,
    on_status: fn(Status) -> Nil,
    /// Set by `attach`; closes over the typed document so `State` itself
    /// need not carry the root tag.
    on_ready: fn(Result(Nil, P2pError)) -> Nil,
    /// `None` until readiness resolves, and then the result that was
    /// delivered — which is what makes "exactly once" a fact about the
    /// state rather than a promise about the code.
    readiness: Option(Result(Nil, P2pError)),
    /// Set when the adapter has reported the room's complete membership.
    /// Until then this replica cannot tell an empty room from an
    /// unanswered one, and must not conclude it is alone.
    roster: Bool,
    bootstrap: BootstrapState,
    /// Transport callbacks that fired from inside
    /// `p2p_transport_js.start`, before it had returned the transport
    /// they need to answer. Newest first; drained in arrival order the
    /// moment the transport is stored.
    deferred: List(Deferred),
    /// Loaded from an imported snapshot rather than built only from the
    /// configured root. A synchronous attach refusal leaves this document
    /// detached so the restored local state stays usable.
    imported: Bool,
    attached: Bool,
    closed: Bool,
    policy: TransportPolicy,
    sequencer: Option(SequencerConfig),
    /// The relay lane, once `attach` has opened one. `None` under
    /// `P2pOnly`, under `Auto` with no sequencer configured, and after
    /// `close`.
    relay: Option(crdt_sequencer_js.Relay),
    phase: RelayPhase,
    /// Where durable traffic goes. Flipped *before* the status that
    /// reports the flip, so a handler that reads it back agrees with
    /// what it was just told.
    path: TransportPath,
    /// The digest of the state last published to the relay, and the
    /// only digest an attestation echo is ever compared against.
    published: String,
    /// Consecutive attestations that came back empty, which is what the
    /// resync backoff indexes.
    resyncs: Int,
    /// Cancels a scheduled resync.
    resync_timer: Option(fn() -> Nil),
    /// Whether this document has changed since its peers were last told
    /// its digest. Set by every mutation and every relayed merge that
    /// moved it; cleared by the flush that tells them.
    nudge_dirty: Bool,
    /// Whether an anti-entropy flush is already armed. One digest per
    /// interval while the relay is primary, however many edits the
    /// interval held.
    nudge_armed: Bool,
    /// Cancels the armed digest flush.
    nudge_timer: Option(fn() -> Nil),
    /// Whether a merge this replica learned from a *peer* moved canonical
    /// state that the relay has not been told about. The relay carries
    /// the room's durability, and a peer's delta reaches it through
    /// nobody else, so the same coalesced flush that digests the mesh
    /// republishes the merged state to the relay. Cleared by that flush,
    /// and by a fallback — a lane that comes back publishes everything it
    /// holds during its handshake.
    publish_owed: Bool,
    /// The one clock every delay is measured on — the mesh heartbeat, the
    /// relay's coalescer and backoff, the readiness deadline — and the
    /// anti-entropy interval both lanes share.
    scheduler: Scheduler,
    anti_entropy_interval_ms: Int,
    /// Whether a mesh anti-entropy digest is already armed. One digest per
    /// interval on the WebRTC path, however many merges the interval held.
    /// Distinct from `nudge_*`, which is the relay path's coalescer; the
    /// two never arm at once because the transport path is one or the
    /// other and a failover cancels the relay's before this one takes over.
    sync_armed: Bool,
    /// Cancels the armed mesh digest flush.
    sync_timer: Option(fn() -> Nil),
    /// The digest last announced to the peers, or `""` when they are owed
    /// a fresh one. The heartbeat's dirty gate: a beat whose digest still
    /// matches this broadcasts nothing, so an idle converged mesh goes
    /// quiet instead of repeating itself every interval. Cleared by a
    /// peer's mismatching digest, so a replica that is *ahead* keeps
    /// announcing until the room has caught up.
    last_sync_digest: String,
    /// How many times a peer's digest told this replica it was behind and
    /// it asked for state — mesh partition-repair activity, as a count.
    repairs: Int,
    /// The last peer digest that matched this replica's own, if any: a
    /// successful anti-entropy comparison, for diagnostics.
    last_match: Option(String),
    /// The canonical digest this document has already computed, and the
    /// document it was computed from.
    ///
    /// Its own cell rather than a field of `State`: every write here is
    /// `State(..state, ...)` from a snapshot read earlier in the same
    /// function, so a memo stored between the read and the write would be
    /// silently dropped by it. A cell is one box every snapshot shares.
    digest_cache: Cell(DigestCache),
    /// Cancels the `SequencedOnly` readiness deadline.
    deadline: Option(fn() -> Nil),
    /// Whether the relay has ever been primary, which is what makes a
    /// later attachment a recovery rather than a first attachment.
    recovered: Bool,
  )
}

@target(javascript)
/// A canonical digest and the document it describes.
///
/// Canonicalizing and hashing a document is O(document): every channel
/// snapshot is projected, every key and set-shaped array is sorted into
/// UTF-8 byte order, and the result is hashed. The anti-entropy heartbeat
/// asks for one every interval, every received `Digest` is compared
/// against one, and the relay lane publishes, attests and reports with
/// one — all of which normally describe a document that has not changed
/// since the last of them.
///
/// So the answer is kept, keyed on the document that produced it. A
/// `crdt_core.Document` is immutable: the same reference is the same
/// state, and every transition — a local edit, a merge, a channel
/// creation, an import — returns a new one, which cannot match. There is
/// no invalidation list to keep in step with the code, and no state
/// change that can be missed by one.
type DigestCache {
  DigestCache(
    /// The document `value` was computed from, or `None` before the first
    /// computation.
    taken_from: Option(crdt_core.Document),
    value: String,
    /// How many times this document has actually canonicalized and
    /// hashed itself. A cache hit does not count, which is what makes
    /// `digest_computations` evidence rather than a guess.
    computations: Int,
  )
}

@target(javascript)
/// Where the relay lane is in its lifecycle. Distinct from the transport
/// path: a relay can be syncing while WebRTC is still carrying deltas,
/// which is exactly the state every attachment passes through.
type RelayPhase {
  /// No relay: not configured, or refused by policy.
  RelayOff
  /// A socket is being opened, or reopened after a drop.
  RelayOpening
  /// The capability was accepted and the state handshake is running.
  RelaySyncing
  /// Local and relay digests matched. The relay is the delta path.
  RelayPrimaryPhase
  /// The endpoint answered without `crdt_relay_v1`. Terminal.
  RelayUnsupportedPhase
}

@target(javascript)
/// A peer with an open document channel. `greeted` is set by a `hello`
/// that passed every compatibility check; until then the peer may send
/// nothing else.
type Peer {
  Peer(id: String, greeted: Bool)
}

@target(javascript)
/// How far this replica is through joining a room: whether it still needs
/// a peer's state before it can be called ready. Exposed by
/// `bootstrap_state` as a diagnostic.
pub type BootstrapState {
  /// Joined, and either the roster has not arrived or no peer has been
  /// validated yet.
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
/// What a connection reports as it runs. Transport lifecycle is passed
/// through unchanged in `Transport`; everything else is document-level.
pub type Status {
  /// A `p2p_transport_js.Status`, verbatim: signaling membership, peer
  /// connection and ICE state, open-peer count.
  Transport(status: p2p_transport_js.Status)
  /// A typed error the transport reported, before it reached a document.
  TransportError(error: P2pError)
  /// Signaling has been asked to join; the document exists and is
  /// editable.
  Joined(room: String, replica: String)
  /// The room's complete membership, as the signaling adapter reported
  /// it. A replica is not ready before this arrives: until then an empty
  /// peer list means "nobody has been announced", not "nobody is here".
  RosterKnown(peers: List(String))
  /// Waiting for `peer_id` to answer the bootstrap `stateRequest`.
  AwaitingState(peer_id: String)
  /// Readiness has resolved successfully. Emitted before `on_ready`
  /// runs, with `readiness` already resolved, so a status handler and the
  /// readiness callback never disagree about the document's state.
  Ready
  /// A peer completed the `hello` handshake.
  PeerReady(peer_id: String)
  /// A peer's document channel closed.
  PeerGone(peer_id: String)
  /// A peer was closed for the named protocol violation. The local
  /// document is unchanged and every other peer is untouched.
  PeerRejected(peer_id: String, error: P2pError)
  /// A `state` message from `peer_id` merged, carrying `channels`
  /// channels. This is both the bootstrap transfer and, later, a repair.
  StateMerged(peer_id: String, channels: Int)
  /// A peer told us *it* rejected something of ours, with the protocol's
  /// own reason and detail. Nothing local changed; this is the one
  /// message that explains a link that is about to go away, so it is
  /// reported rather than dropped.
  RejectedByPeer(peer_id: String, reason: String, detail: String)
  /// A local operation failed. Reported in addition to the `Result` the
  /// caller already has, so a status log tells the whole story.
  Failed(error: P2pError)
  /// A subscriber callback threw. The document and transport are intact;
  /// the exception is reported rather than swallowed.
  SubscriberFailed(address: String, detail: String)
  /// A relay lane is being opened. Emitted per attempt, so a reconnect
  /// sequence reads as one of these per `RelayRetry`.
  RelayConnecting(url: String)
  /// The endpoint answered without `crdt_relay_v1`. Under `Auto` this is
  /// the whole of it and the document stays on WebRTC; under
  /// `SequencedOnly` it is also the readiness failure.
  RelayUnsupported(detail: String)
  /// The capability was accepted and the state handshake is running:
  /// hello, `stateRequest`, merge, publish, digest. Deltas are still
  /// going to the mesh while this runs.
  RelaySyncingStatus
  /// The same handshake, after the relay had already been primary once.
  /// A recovery merges an outage's worth of edits from both sides before
  /// it can claim anything.
  RelayRecovering
  /// Local and relay digests matched: the relay is now the durable delta
  /// path. `path` already reads `Sequenced` when this arrives.
  RelayPrimary(digest: String)
  /// The relay asked this client to checkpoint, because its live log is
  /// approaching the bound past which it would have to start refusing
  /// traffic. The answer is to publish the current merged state and
  /// attest it; nothing about the document changes, and no number the
  /// relay sent is read by anything — not even this status.
  RelayCheckpointRequested
  /// A requested checkpoint landed: the relay echoed the digest of the
  /// state this replica had just published, so the room's ordinary
  /// history has been compacted down to it.
  RelayCheckpointed(digest: String)
  /// The relay is gone and WebRTC is the delta path again. `path`
  /// already reads `PeerToPeer` when this arrives, which is what makes a
  /// mutation racing the drop safe.
  RelayFallback(detail: String)
  /// A reconnect is armed, `delay_ms` from now.
  RelayRetry(delay_ms: Int)
  /// One envelope from the relay was refused, with the local document
  /// untouched. One misbehaving replica does not cost the lane: unlike a
  /// peer, a relay client cannot be closed from here, and closing the
  /// relay would punish every other replica on it.
  RelayRejected(from: String, error: P2pError)
  /// The relay lane itself failed — a socket that would not open, a
  /// malformed frame, a refusal from the service.
  RelayFailed(error: P2pError)
}

@target(javascript)
@external(javascript, "./crdt_js_ffi.mjs", "guard")
fn guard(work: fn() -> Nil, on_error: fn(String) -> Nil) -> Nil

@target(javascript)
/// Whether two documents are the same immutable value, by reference.
/// `crdt_core.Document` is opaque and `==` would walk it, which is the
/// work the digest cache exists to skip.
@external(javascript, "./crdt_js_ffi.mjs", "sameDocument")
fn same_document(left: crdt_core.Document, right: crdt_core.Document) -> Bool

// ─────────────────────────────────────────────────────────────────────────────
// The canonical digest, computed once per document state
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// This document's canonical digest, computed if the document has moved
/// since the last one and reused if it has not.
///
/// Every digest the facade uses goes through here — the mesh heartbeat,
/// the relay's coalesced digest, the comparison against a peer's digest,
/// the publication and its attestation, and the public `digest` — so
/// there is one canonicalization per document state however many of them
/// ask for it. The cache is keyed on the document itself, so a state
/// change cannot leave a stale digest behind: it simply misses.
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
/// `crdt_core.digest_message`, from the digest this document has already
/// computed. The message is the same one either way; only the hashing is
/// skipped.
fn digest_message(cell: Cell(State)) -> Message {
  crdt_wire.Digest(document_digest(cell))
}

// ─────────────────────────────────────────────────────────────────────────────
// Lifecycle
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// Build the document a `Config` describes, without joining anything.
///
/// The root is created from the config, never learned from a peer, so
/// two replicas that agree on the config agree on the root before they
/// have exchanged a message. Pass the result to `attach` to connect it.
pub fn new_document(
  config: Config(root),
) -> Result(CrdtDocument(root), P2pError) {
  let session = ids.uuid_v4()
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
        anti_entropy_interval_ms: config.anti_entropy_interval_ms,
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
/// Returns as soon as signaling has been asked to join. `on_ready` fires
/// exactly once — see the module docs for when — and `on_status` runs for
/// the connection's lifetime.
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
/// Run one application callback without letting its exception escape into
/// the protocol's own call stack. The facade's contract is that a
/// callback cannot change what the document or the transport does.
fn contained(work: fn() -> Nil) -> Nil {
  guard(work, fn(_detail) { Nil })
}

@target(javascript)
/// Join a room with a document that already exists — the one `connect`
/// uses internally, and the way an `import_snapshot` result is put back
/// online.
///
/// The document keeps its cell, so handles and subscriptions taken before
/// the attach stay valid, the snapshot's channels are broadcast to peers
/// as part of the ordinary `state` exchange, and a synchronous startup
/// refusal leaves a restored snapshot detached so its local state stays
/// editable and retryable.
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
/// `attach` against a substituted browser seam, so bootstrap ordering,
/// handshake rejection, and merge behaviour can be driven
/// deterministically without a browser. The same seam
/// `p2p_transport_js.start_with_rtc` exposes, for the same reason.
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
/// Leave signaling, close every peer, and stop the document accepting
/// reads and writes. Idempotent.
///
/// Closing before readiness resolves `on_ready` once, with
/// `Error(DocumentClosed)`: a caller waiting on it is owed an answer even
/// when the answer is that the document was abandoned.
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
/// Forget one attach attempt while keeping the document itself alive.
///
/// Local state, handles, and subscriptions survive; only the transport
/// plumbing and per-attempt callbacks are cleared so a caller may keep
/// editing offline and try `attach` again later.
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
/// A synchronous startup failure ends only that attempt for a restored
/// snapshot; a freshly built document keeps the older fail-closed
/// semantics.
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
/// Resolve readiness at most once for the whole connection lifetime.
///
/// The result is committed and the status is emitted *before* the
/// application callback runs, so `readiness` and the status stream
/// already agree with the result by the time anything observes it — and a
/// callback that throws cannot leave a connection that will try to
/// resolve readiness a second time, because both callbacks are guarded
/// and neither runs before the commit.
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
/// The room's complete membership has arrived. Recorded before the
/// transport is necessarily stored — an adapter may report the roster
/// from inside `join` — and `attach` settles readiness once it is.
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
/// Become ready if nothing is left to wait for: the room's membership is
/// completely known, no peer is still negotiating, and none owes us a
/// `state` transfer.
///
/// The roster is the essential condition. An adapter that learns its
/// room over a network round trip has announced nobody at all when `join`
/// returns, and a replica that read that as "the room is empty" would
/// call back ready with an empty document a moment before the room's
/// state arrived — which is what every late joiner would see.
fn settle_readiness(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  case resolved(state), state.roster, state.bootstrap, state.transport {
    True, _, _, _ -> Nil
    _, False, _, _ -> Nil
    _, _, WaitingForState(_), _ -> Nil
    _, _, _, None -> Nil
    _, _, _, Some(transport) ->
      case p2p_transport_js.known_peers(transport) {
        [] -> {
          let state = transport_js.get_cell(cell)
          transport_js.set_cell(cell, State(..state, bootstrap: Bootstrapped))
          resolve_ready(cell, Ok(Nil))
        }
        _ -> Nil
      }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The relay lane
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// Open the configured relay, if policy allows one.
///
/// Nothing here can delay readiness: `Auto` calls this *after* the mesh
/// has had its chance to settle, and the relay's own events only ever
/// resolve readiness for `SequencedOnly`, which has no other source.
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
/// One relay connection attempt is starting. Every attempt, not only the
/// first: a reconnect sequence reads as one `RelayConnecting` per
/// `RelayRetry`, which is what makes the status stream a complete account
/// of what the lane did.
fn relay_connecting(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.closed, state.sequencer {
    True, _ -> Nil
    _, None -> Nil
    _, Some(config) -> emit(cell, RelayConnecting(config.url))
  }
}

@target(javascript)
/// The relay advertised `crdt_relay_v1`. Introduce ourselves and ask for
/// everything it holds; nothing is published until that reply is
/// complete, because publishing first would hand the relay a state that
/// had not merged the room's.
///
/// A write that does not reach an open socket ends the attachment there
/// and then. Carrying on would leave this document in `RelaySyncing`
/// against a socket that cannot answer — no `synced`, no publication, no
/// fallback, and no reconnect — which is the one shape of failure this
/// lane must never have.
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
/// Publish the whole merged local state and attest its digest in the same
/// breath.
///
/// The two go together deliberately: the digest describes the state that
/// was just written, so the relay's echo is an acknowledgement of a
/// document it holds rather than a claim this replica invented. A write
/// that fails — either of them — retires the socket instead of waiting
/// for an echo that cannot come.
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
    _, Some(_), _ -> Nil
  }
}

@target(javascript)
/// The two frames a publication is, whatever asked for it: the whole
/// merged state, and an attestation of the digest that describes it.
///
/// Split out because three callers owe the relay exactly this and must
/// not drift apart — the attachment handshake, a requested checkpoint,
/// and a merge this replica learned from a peer while the relay was
/// primary. A write that fails, either of them, retires the socket rather
/// than waiting for an echo that cannot come.
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
        True -> Nil
        False -> relay_unwritable(cell)
      }
  }
}

@target(javascript)
/// Publish the current merged state while the relay is *primary*, and
/// attest it.
///
/// The same two frames the attachment handshake writes, in the same
/// order, recording the digest as `published` so the relay's echo
/// completes the checkpoint the ordinary way: an echo that matches is a
/// `RelayCheckpointed` and a compacted log, and an empty one means the
/// relay holds traffic published after this state — which its own next
/// checkpoint request asks about again. Nothing retries from here, which
/// is what keeps a busy room from turning into a publish loop.
///
/// Re-reads the document rather than taking a caller's snapshot: a status
/// handler that closed the document or dropped the lane between the
/// decision and this line is owed no frames.
fn publish_while_primary(cell: Cell(State)) -> Nil {
  let digest = document_digest(cell)
  let state = transport_js.get_cell(cell)
  case state.closed, state.relay, state.phase {
    False, Some(relay), RelayPrimaryPhase -> {
      transport_js.set_cell(cell, State(..state, published: digest))
      publish(cell, relay, digest, state.document)
    }
    _, _, _ -> Nil
  }
}

@target(javascript)
/// The relay asked for a checkpoint.
///
/// A relay's live log is bounded, and a room that fills it has to start
/// refusing traffic — including an honest client's. So before it gets
/// there it asks the clients that understand the request to publish what
/// they hold, and an honest client answers with exactly the same two
/// frames it publishes during attachment: the whole merged state, and an
/// attestation of that state's digest. The relay's checkpoint then
/// compacts the room's ordinary valid history down to that one record,
/// which is what keeps a long editing session from ever reaching the
/// bound.
///
/// Nothing about the document changes here, and nothing the relay sent
/// is read: the state published is this replica's own, exactly as it
/// would be published at attachment.
///
/// Three cases, and only one of them writes anything:
///
///   * **syncing** — the attachment handshake is already publishing and
///     attesting, so the request is already being answered. Reported and
///     otherwise ignored;
///   * **primary** — publish and attest now;
///   * **anything else** — no lane to answer on.
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
    _, Some(_), _ -> Nil
  }
}

@target(javascript)
/// The relay's answer to an attestation.
///
/// An echoed digest means the relay's whole content is the state this
/// replica published. An empty one means it holds more — a concurrent
/// attachment, a delta that raced the publication — and the answer to
/// that is to merge what arrives and try again, never to overwrite what
/// is there.
///
/// While the relay is *primary* the same echo answers a requested
/// checkpoint. It is reported and nothing else: the lane is already
/// primary, the document is unchanged either way, and an empty echo
/// means the relay holds traffic this replica published after the state
/// — which the relay's next request, armed by that same growth, asks
/// about again. Retrying here instead would be an unbounded publish loop
/// against a busy room.
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
    _, _ -> Nil
  }
}

@target(javascript)
/// The relay is now the durable delta path.
///
/// The path flips before the status is emitted, so a handler that reads
/// `effective_path` back agrees with what it was just told, and a
/// mutation authored from that handler takes the new route.
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
/// Try the publish/attest handshake again later.
///
/// Backed off rather than immediate, and event-driven rather than
/// polling: two replicas attaching at once can each hold something the
/// other has not merged yet, and a pair that retried instantly would
/// invalidate each other's attestation forever. The delay separates
/// them, and anything that actually changes the local document
/// short-circuits it.
fn schedule_resync(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.closed, state.phase {
    True, _ -> Nil
    False, RelaySyncing -> {
      cancel(state.resync_timer)
      timer_js.arm(
        scheduler: state.scheduler,
        delay_ms: crdt_sequencer_js.backoff_ms(state.resyncs),
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
/// Under `Auto` that is a status and nothing more: the document keeps
/// running on the mesh, exactly as it would with no sequencer configured
/// at all. Under `SequencedOnly` it is the readiness failure, because
/// there is no other path to be ready on.
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
/// Nothing local pauses. The path flips to the mesh *before* the
/// fallback status is emitted, so a mutation authored from a status
/// handler — or one that was already in flight — goes to peers rather
/// than into a socket that is not there. The document, its handles, its
/// subscribers, its replica identity, and its message counter are all
/// untouched: a transport changed, not a session.
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
            _ -> RelayOpening
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
/// The one digest a fallback owes the mesh.
///
/// While the relay is primary a durable delta goes to the relay and *not*
/// to the peers; what the peers get is a coalesced digest on the
/// anti-entropy interval. A drop inside that window would otherwise
/// cancel the digest and send only a `stateRequest`, which pulls each
/// peer's state and tells it nothing: a peer that never saw the
/// relay-only edits would answer with a state that does not contain them,
/// merge nothing, and stay behind until the next local mutation — or
/// forever, in a room that has gone quiet.
///
/// So a dirty or armed window is flushed exactly once, synchronously,
/// before the failover `stateRequest`. The peer compares it, finds it
/// does not match, asks for state on `crdt_core`'s existing mismatch
/// path, and is converged in the same breath as the fallback. The timer
/// has already been cancelled, so this is one push and not two.
fn final_nudge(cell: Cell(State), owed: Bool) -> Nil {
  case owed {
    False -> Nil
    True -> broadcast_digest(cell)
  }
}

@target(javascript)
/// Ask every validated peer for its state, so an outage that started on
/// the relay does not also start with a gap. Merges are idempotent and a
/// `state` that changes nothing emits nothing, so this costs a round trip
/// and no correctness.
fn repair_from_peers(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  greeted_peers(state)
  |> list.each(fn(peer_id) {
    send(cell, peer_id, crdt_core.state_request_message())
  })
}

@target(javascript)
/// The ids of every peer that has completed the `hello` handshake,
/// sorted. The one definition of "the peers this document may talk to".
fn greeted_peers(state: State) -> List(String) {
  state.peers
  |> dict.values
  |> list.filter(fn(peer) { peer.greeted })
  |> list.map(fn(peer) { peer.id })
  |> list.sort(string.compare)
}

@target(javascript)
/// One envelope the relay carried.
///
/// The relay's `order` never reaches this function: the lane strips it,
/// and what arrives is the author's own encoded envelope. Validation is
/// the same as a peer's, and so is the merge — a delta that arrived over
/// WebRTC first is suppressed by `crdt_core`'s message-id window, and one
/// that arrives here first suppresses the WebRTC copy, so a duplicate is
/// one state change and one subscriber event whichever order it lands in.
///
/// A refusal costs the sender's envelope and nothing else. Unlike a peer,
/// a relay client cannot be closed from here, and closing the lane would
/// punish every other replica on it for one replica's bad frame. The
/// `False` it answers with is what stops the lane's order high-water mark
/// advancing past something this document did not merge — which would
/// otherwise let a later attestation tell the relay to retire it.
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
/// Write one message to the relay, if there is one to write to.
fn relay_send(cell: Cell(State), message: Message) -> Bool {
  let state = transport_js.get_cell(cell)
  case state.relay {
    None -> False
    Some(relay) ->
      crdt_sequencer_js.send_envelope(
        relay,
        crdt_core.encode(state.document, message),
      )
  }
}

@target(javascript)
/// `relay_send`, with the failure handled rather than ignored.
///
/// Every write on this lane is one of four things — the attachment's
/// `hello` and `stateRequest`, the published `state`, a reply to
/// something the relay carried, or a durable broadcast — and a `False`
/// means the same thing for all of them: this socket is gone. The one
/// answer that is always right is to retire it, which flips the path to
/// the mesh, reports the fallback, repairs from the peers and arms the
/// policy's reconnect. Anything else strands the document mid-handshake
/// on a socket that will never answer.
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
/// A write that did not reach an open socket. Retires the lane through
/// the same path a reported close takes, so there is one fallback
/// sequence and not two.
fn relay_unwritable(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.relay {
    None -> Nil
    Some(relay) ->
      crdt_sequencer_js.abort(relay, "the relay socket was not writable")
  }
}

@target(javascript)
/// Arm the `SequencedOnly` readiness deadline.
///
/// It bounds the whole attachment — socket, capability, state replay,
/// digest — rather than any one step of it, because a caller waiting on
/// `on_ready` does not care which step is slow.
fn arm_deadline(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.sequencer {
    None -> Nil
    Some(config) ->
      case config.readiness_deadline_ms > 0 {
        False -> Nil
        True ->
          timer_js.arm(
            scheduler: state.scheduler,
            delay_ms: config.readiness_deadline_ms,
            action: fn() {
              abandon(
                cell,
                p2p.SequencerUnavailable(
                  "the sequencer did not become the durable path within "
                  <> int.to_string(config.readiness_deadline_ms)
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
/// Give up on a document that can never become ready: resolve readiness
/// once with the reason, and close everything it holds.
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
        _ -> Nil
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
        _ -> Nil
      }
    },
  )
}

@target(javascript)
/// Run a transport callback now, or hold it until `attach` has stored the
/// transport it needs to answer with. An adapter that opens a channel
/// from inside `join` is unusual but legal, and nothing it delivers may
/// be dropped.
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
/// A peer's document channel is open. Introduce ourselves; nothing else
/// may be sent until its `hello` comes back and passes.
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
/// Retire a peer. Idempotent, and reached by two routes: the transport's
/// `PeerClosed` status, which covers every announced peer, and its
/// `on_peer_close` callback, which covers only the ones that opened.
/// Whichever arrives first does the work; the second finds nothing left
/// to report and only re-settles readiness, which is itself idempotent.
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
/// A peer we were bootstrapping from has gone. Ask the next validated
/// peer instead, and if there is nobody left to ask, this replica is the
/// room and the document it already holds is ready.
fn rebootstrap(cell: Cell(State), lost: String) -> Nil {
  let state = transport_js.get_cell(cell)
  case resolved(state), state.bootstrap {
    True, _ -> Nil
    False, WaitingForState(peer_id) if peer_id == lost -> {
      case greeted_peers(state) {
        [peer_id, ..] -> request_state(cell, peer_id)
        [] -> {
          transport_js.set_cell(cell, State(..state, bootstrap: Joining))
          settle_readiness(cell)
        }
      }
    }
    False, _ -> settle_readiness(cell)
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
/// One payload from one peer's data channel. Every check that can reject
/// it runs before `crdt_core` is asked to merge anything.
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
/// `crdt_core.receive`, with the local digest supplied from the cache for
/// the one message that reads it.
///
/// A `Digest` is answered by comparing it against this document's own,
/// which is the comparison the heartbeat makes in both directions; every
/// other message never computes a digest at all. The document is read
/// here rather than taken from a caller, so what is compared and what it
/// is compared against cannot be two different states.
fn receive_envelope(
  cell: Cell(State),
  envelope: crdt_wire.Envelope,
) -> Result(#(crdt_core.Document, crdt_core.Outcome), P2pError) {
  let document = transport_js.get_cell(cell).document
  case envelope.message {
    crdt_wire.Digest(_) ->
      crdt_core.receive_with_digest(document, envelope, document_digest(cell))
    _ -> crdt_core.receive(document, envelope)
  }
}

@target(javascript)
/// Merge one validated envelope. The document is written before anything
/// is sent and before any subscriber runs, so a throwing callback cannot
/// leave the document behind the state its peers believe it holds.
///
/// A merge that moves canonical state while the *relay* is the durable
/// path also owes the relay that state. Nothing else carries it: a
/// received message never populates `outcome.broadcast`, so a delta or a
/// channel a `P2pOnly` peer sent over WebRTC would converge across the
/// mesh and never reach the room's history, its checkpoint, or a replica
/// that only ever talks to the relay. The digest is compared across the
/// merge rather than read off `outcome.events`, because a merge can move
/// the lattice — an OR-Set tag, a 2P-Set tombstone — with no event at
/// all, and a state the relay does not hold is a state the relay does not
/// hold whether or not a subscriber would have noticed.
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
/// A peer moved this document while the relay was carrying its
/// durability, so the relay is owed the merged state.
///
/// Coalesced onto the interval the relay path already has rather than
/// published from inside the merge: a mesh burst is one publication, not
/// one per delta, and the peers' digest goes out in the same flush. The
/// publication itself is the ordinary one — a `state` frame and an
/// attestation — so the relay logs it, fans it to the replicas this one
/// cannot see, and checkpoints it exactly as it would a publication this
/// replica authored.
///
/// A relay-carried merge deliberately does *not* come through here. The
/// relay already holds what it sent us, and republishing it would have
/// every client answer every publication with another one.
fn owe_publication(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  transport_js.set_cell(cell, State(..state, publish_owed: True))
  nudge_peers(cell)
}

@target(javascript)
/// Forget an owed publication, because one has just been written or
/// because there is no longer a lane to write it on. A lane that comes
/// back publishes the whole merged state during its handshake, so
/// nothing is lost by dropping this on a fallback.
fn clear_publication(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  transport_js.set_cell(cell, State(..state, publish_owed: False))
}

@target(javascript)
/// Record what a peer's digest told this replica. An empty outcome is a
/// match — the two already agree — so the digest is kept as the last
/// successful comparison. A `stateRequest` reply means this replica was
/// behind and `merge` has already asked for state; the repair is counted
/// when that state arrives and moves the document, not here, so a request
/// that is never answered is never counted.
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
/// Count one completed partition repair: a catch-up `state` that changed
/// this replica's canonical state.
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
        _, _ -> send(cell, peer_id, crdt_core.state_request_message())
      }
      // And, while the relay is the delta path, what this replica holds
      // — so a peer that never sees this relay's traffic can ask for
      // whatever it is missing rather than wait for a local edit.
      case transport_js.get_cell(cell).path {
        Sequenced -> send(cell, peer_id, digest_message(cell))
        PeerToPeer -> Nil
      }
      // The mesh now has a validated peer to answer, so start (or leave
      // running) the anti-entropy heartbeat. A no-op on the relay-primary
      // path, where `should_sync` is false and repair is the relay's job.
      refresh_sync(cell)
    }
  }
}

@target(javascript)
/// A `state` transfer merged.
///
/// Any of them settles a bootstrap that is still waiting, not only the
/// one this replica asked first: every greeted peer is sent a
/// `stateRequest` and every one of them answers, so a replica that has
/// merged a room's state is bootstrapped whichever answer arrived.
/// Pinning readiness to one peer would let a peer that greets and then
/// goes quiet hold a joiner on its loading screen while the rest of the
/// room was busy syncing it.
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
/// Close one peer for a protocol violation, telling it why first. The
/// local document is untouched and every other peer keeps running: a
/// hostile or mismatched peer costs its own connection and nothing else.
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
/// Send one message down whichever path is durable right now.
///
/// While the relay is primary that is the relay: it is durable, it
/// reaches replicas this one has no peer connection to, and the mesh
/// stays open underneath for presence, digests, repair, and the failover
/// that needs no negotiation. The durable message itself is *not* also
/// pushed to the peers — that is what "one durable path" means — but its
/// digest is, so a peer that is not on this relay learns it is behind.
///
/// A write the relay could not make — it dropped between the mutation
/// and this line, or the socket is no longer open — takes the mesh
/// instead, and the lane is dropped rather than left looking healthy: a
/// path that cannot carry a delta is not the delta path.
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
    _, _ -> peer_broadcast(cell, message)
  }
}

@target(javascript)
/// Anti-entropy for the mesh while the relay carries the durable
/// traffic.
///
/// One `digest` to every validated peer. A peer whose digest matches
/// answers nothing; one that differs asks for state, which this replica
/// serves from the same `crdt_core` path a bootstrap uses — so a
/// `P2pOnly` replica, one whose sequencer turned out not to speak this
/// lane, and one partitioned from the relay all converge without a
/// durable delta ever being duplicated onto the mesh, and without a
/// second semantic event: merges are idempotent and a `state` that
/// changes nothing emits nothing.
///
/// Coalesced over a named interval, and deliberately not sent from
/// inside the mutation that caused it.
///
/// A digest that overtakes the relay's own fan-out of the same delta
/// tells every peer it is behind at the exact moment it is about to stop
/// being behind, and the answer to that is a full `state` transfer across
/// the mesh — per mutation. A zero-delay tick does not fix that: a
/// microtask or a task-queue turn still beats a socket round trip
/// comfortably, and it only coalesces the mutations that happened to be
/// synchronous.
///
/// So this marks the document dirty and arms one flush
/// `default_anti_entropy_ms` (250 ms, injectable) ahead on the document's
/// scheduler. Edits across many tasks coalesce into it, the relay's copy
/// of every one of them normally lands at the peers first, and a peer the
/// relay could not reach hears a digest a quarter of a second later
/// instead of a stale one immediately. Sustained editing costs exactly
/// one digest per interval.
///
/// This is anti-entropy, not repair. Failover does not come through here:
/// it sends every peer a `stateRequest` in the same breath as the
/// fallback, with no delay at all.
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
            delay_ms: state.anti_entropy_interval_ms,
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
    _, _, _ -> Nil
  }
}

@target(javascript)
/// Send the coalesced digest, if the document is still dirty and the
/// relay is still the delta path when the interval comes round — and
/// publish what a peer merged into this document while the relay was
/// primary, which is the only route that state has to the relay.
///
/// A lane that dropped in between has already sent its peers a
/// `stateRequest`, which is strictly more than the digest would be, and
/// will publish everything it holds when it comes back; a document that
/// was closed has no peers to tell and no lane to publish on.
///
/// The mesh is told first. A publication that turns out to be
/// unwritable retires the lane, and the fallback that follows sends every
/// peer a `stateRequest` — so ordering the digest first means the peers
/// hear once either way, rather than twice or not at all.
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
  case state.closed, state.nudge_dirty, state.path, state.transport {
    False, True, Sequenced, Some(_) -> broadcast_digest(cell)
    _, _, _, _ -> Nil
  }
  case state.closed, state.publish_owed {
    False, True -> publish_while_primary(cell)
    _, _ -> Nil
  }
}

@target(javascript)
/// Disarm anti-entropy. The mesh is about to be, or has just been, told
/// something stronger than a digest — or there is nothing left to tell.
/// An owed publication goes with it: the only caller is a lane that has
/// gone, and a lane that comes back publishes the whole merged state
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
/// Whether any peer has completed the `hello` handshake. The mesh
/// anti-entropy digest is only ever sent to a validated peer, so an
/// unvalidated room is one this replica stays quiet in.
fn has_greeted_peer(state: State) -> Bool {
  greeted_peers(state) != []
}

@target(javascript)
/// Whether the mesh anti-entropy heartbeat should be running: an open
/// document whose delta path is WebRTC, with a transport and at least one
/// validated peer to tell. The single predicate `refresh_sync`, `arm_sync`,
/// and `tick_sync` all gate on, so "when a peer exists" has one meaning.
fn should_sync(state: State) -> Bool {
  case state.closed, state.path, state.transport {
    False, PeerToPeer, Some(_) -> has_greeted_peer(state)
    _, _, _ -> False
  }
}

@target(javascript)
/// Reconcile the heartbeat with the document's current shape: arm it if it
/// ought to be running and is not, cancel it if it is running and ought not
/// be. Idempotent, so every lifecycle edge that can change `should_sync` —
/// a greet, a failover to the mesh, a peer leaving — calls this and needs
/// to know nothing about the timer's prior state.
fn refresh_sync(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  case should_sync(state), state.sync_armed {
    True, False -> arm_sync(cell)
    False, True -> cancel_sync(cell)
    _, _ -> Nil
  }
}

@target(javascript)
/// Anti-entropy for the mesh while WebRTC is the delta path — the
/// recurring twin of the relay's `nudge_peers`.
///
/// Canonical state moves without a re-broadcast and without a visible
/// event: a `state` transfer, a partition healing on one reconnected edge,
/// a concurrent OR-Set tag or a 2P-Set tombstone that changes the lattice
/// but not the membership a subscriber sees. None of these fan out on
/// their own, so the mesh cannot key repair off them. Instead, while a
/// validated peer exists the document checks every
/// `anti_entropy_interval_ms` whether its canonical digest has moved since
/// the peers were last told, and broadcasts it when it has; a peer whose
/// digest matches answers nothing, one that differs asks for state on
/// `crdt_core`'s existing mismatch path — and clears its own gate, so the
/// side that turns out to be ahead keeps announcing until the room agrees.
/// An idle converged mesh therefore costs one digest and then silence, not
/// a broadcast per interval forever.
/// Reconnecting one edge between two partitions therefore repairs *every*
/// remaining peer, not only the two endpoints, and a quiescent mesh that
/// merged an event-less change still converges — neither needs a later
/// event-ful edit to trigger a flush.
///
/// One live timer: `arm_sync` is a no-op if a heartbeat is already armed,
/// and `tick_sync` clears the flag before it re-arms. The relay path's
/// `nudge_*` fields are separate and never armed at the same time, because
/// the transport path is one or the other and a failover cancels the
/// relay's coalescer before this takes over.
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
        delay_ms: state.anti_entropy_interval_ms,
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
/// One heartbeat: re-check the document is still eligible, send the
/// canonical digest to every validated peer, and re-arm for the next
/// interval. A document that failed back onto a relay, lost its last peer,
/// or closed since the timer was set sends nothing and lets the heartbeat
/// lapse.
///
/// The broadcast is gated on the digest having moved since the last one
/// went out (or a peer's mismatch having cleared `last_sync_digest`): the
/// timer recurs, but an idle converged mesh sends nothing rather than
/// repeating the same digest every interval forever.
///
/// The re-arm is skipped when this tick ran *synchronously* from inside
/// `arm_sync` — detectable because the canceller was not stored yet, so
/// `sync_timer` is still `None`. A synchronous scheduler that re-armed here
/// would recurse without bound; firing exactly once instead is the only
/// non-looping behaviour a clock that never advances can have. A real or
/// logical asynchronous scheduler stored the canceller before the tick, so
/// it re-arms and the heartbeat recurs.
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
/// One heartbeat's payload, behind the dirty gate: broadcast the canonical
/// digest only if it differs from the last one the peers were told.
fn sync_digest(cell: Cell(State)) -> Nil {
  let digest = document_digest(cell)
  let state = transport_js.get_cell(cell)
  case digest == state.last_sync_digest {
    True -> Nil
    False -> broadcast_digest(cell)
  }
}

@target(javascript)
/// Send the canonical digest to every validated peer and remember it as
/// the last one announced, so the recurring heartbeat stays quiet until
/// the document moves again. Every whole-mesh digest broadcast goes
/// through here — the heartbeat's, the relay coalescer's flush, and the
/// failover's final push — so the gate cannot be fooled by one of them.
fn broadcast_digest(cell: Cell(State)) -> Nil {
  let digest = document_digest(cell)
  let state = transport_js.get_cell(cell)
  transport_js.set_cell(cell, State(..state, last_sync_digest: digest))
  peer_broadcast(cell, crdt_wire.Digest(digest))
}

@target(javascript)
/// Stop the heartbeat and clear its flags. Called when the last validated
/// peer leaves, on failover to a relay-primary path, and on close.
fn cancel_sync(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  cancel(state.sync_timer)
  transport_js.set_cell(
    cell,
    State(..state, sync_armed: False, sync_timer: None),
  )
}

@target(javascript)
/// Send one message to every peer that has completed the handshake.
///
/// Deliberately not the transport's own broadcast: a data channel can be
/// open before its `hello` has been validated, and a peer that has not
/// proved it agrees about the room, the protocol, the compatibility tag
/// and the root has no business receiving this document's deltas.
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
/// Report one status. Application code, and contained: an exception from
/// a status handler must not skip a state request, suppress a readiness
/// result, or abandon the peers after it. It is not re-reported, because
/// the only channel it could be reported on is the one that just threw.
fn emit(cell: Cell(State), status: Status) -> Nil {
  let state = transport_js.get_cell(cell)
  contained(fn() { state.on_status(status) })
}

// ─────────────────────────────────────────────────────────────────────────────
// Events
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// Deliver each event to the subscribers of its own address. The
/// subscriber list is re-read per event, so a handler that unsubscribes
/// is not called for the next one.
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
/// Subscribe to every event on one channel, whatever its kind. The typed
/// per-kind wrappers below are the usual way in.
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
/// Remove a subscription. Idempotent.
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
    _ -> None
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
    _ -> None
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
    _ -> None
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
    _ -> None
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
    _ -> None
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
    _ -> None
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
    _ -> None
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Channels
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// The document's root, typed by the `CrdtKind` the config named.
pub fn root(document: CrdtDocument(root)) -> Handle(root) {
  Handle(cell: document.cell, address: crdt_wire.root_address)
}

@target(javascript)
/// A handle's channel address. `root` for the root; otherwise
/// `<replica>:<counter>`, which names its creator.
pub fn address(handle: Handle(kind)) -> String {
  handle.address
}

@target(javascript)
/// Register a new channel of `kind` and announce it to every peer. The
/// kind is checked against the eligibility boundary, so a channel that
/// cannot merge without a sequencer is refused here rather than
/// diverging later.
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
/// Take a typed handle onto an existing channel — one a peer announced,
/// or one an imported snapshot carried. The address must be registered
/// and its channel type must be exactly `kind`.
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
/// Every channel address this document holds, in canonical order.
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
/// Report a failed local operation on the status stream as well as
/// returning it, so a status log is a complete account of the document.
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
/// Author a local edit: merged into visible state immediately, broadcast
/// to every open peer, and reported to this address's subscribers once.
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
/// Add `amount` to the counter. Negative amounts decrement.
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
    _ -> 0
  }
}

// ── OR-map ───────────────────────────────────────────────────────────────────

@target(javascript)
/// Write a register value. Only valid on a `RegisterMode` map; a tally
/// map returns the kernel's mode mismatch.
pub fn or_map_set(
  handle: Handle(schema.OrMapChannel),
  key key: String,
  value value: String,
) -> Result(Nil, P2pError) {
  mutate(
    handle,
    channel.OrMapSetRegisterEdit(key, value, transport_js.now_ms()),
  )
}

@target(javascript)
/// Add to a tally. Only valid on a `TallyMode` map.
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
) -> Result(Option(OrMapValue), P2pError) {
  use state <- read(handle, channel.OrMapChannel)
  case state {
    channel.OrMapState(kernel) -> or_map_kernel.get(kernel, key)
    _ -> None
  }
}

@target(javascript)
/// A tally key's value, or zero when the key is absent.
pub fn or_map_tally(
  handle: Handle(schema.OrMapChannel),
  key key: String,
) -> Result(Int, P2pError) {
  use value <- result.try(or_map_value(handle, key))
  case value {
    Some(or_map_kernel.Tally(tally)) -> Ok(tally)
    Some(or_map_kernel.Register(_)) ->
      Error(p2p.InvalidEnvelope(
        address(handle),
        "key " <> key <> " holds a register, not a tally",
      ))
    None -> Ok(0)
  }
}

@target(javascript)
pub fn or_map_entries(
  handle: Handle(schema.OrMapChannel),
) -> Result(List(#(String, OrMapValue)), P2pError) {
  use state <- read(handle, channel.OrMapChannel)
  case state {
    channel.OrMapState(kernel) -> or_map_kernel.entries(kernel)
    _ -> []
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
    _ -> False
  }
}

@target(javascript)
pub fn or_set_values(
  handle: Handle(schema.OrSetChannel),
) -> Result(List(String), P2pError) {
  use state <- read(handle, channel.OrSetChannel)
  case state {
    channel.OrSetState(kernel) -> or_set_kernel.values(kernel)
    _ -> []
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
    _ -> False
  }
}

@target(javascript)
pub fn g_set_values(
  handle: Handle(schema.GSetChannel),
) -> Result(List(String), P2pError) {
  use state <- read(handle, channel.GSetChannel)
  case state {
    channel.GSetState(kernel) -> g_set_kernel.values(kernel)
    _ -> []
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
    _ -> False
  }
}

@target(javascript)
pub fn two_p_set_values(
  handle: Handle(schema.TwoPSetChannel),
) -> Result(List(String), P2pError) {
  use state <- read(handle, channel.TwoPSetChannel)
  case state {
    channel.TwoPSetState(kernel) -> two_p_set_kernel.values(kernel)
    _ -> []
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
    _ -> []
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
    _ -> ""
  }
}

@target(javascript)
/// The text's current optimistic grapheme count.
pub fn text_length(
  handle: Handle(schema.TextChannel),
) -> Result(Int, P2pError) {
  use state <- read(handle, channel.TextChannel)
  case state {
    channel.TextState(kernel) -> text_kernel.length(kernel)
    _ -> 0
  }
}

@target(javascript)
/// Create a stable anchor at the gap before the optimistic grapheme at
/// `index`, biased with `bias_before`/`bias_after`. A typed error on an
/// out-of-bounds index.
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
/// Resolve an anchor to a current optimistic grapheme index. A typed error on
/// a stale/unknown anchor target.
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
/// An anchor at the start of the text. Always resolves to 0. Pure — doesn't
/// need a handle since it carries no document state.
pub fn text_start_anchor() -> TextAnchor {
  text_kernel.start_anchor()
}

@target(javascript)
/// An anchor at the end of the text. Always resolves to the current grapheme
/// length, tracking growth. Pure, like `text_start_anchor`.
pub fn text_end_anchor() -> TextAnchor {
  text_kernel.end_anchor()
}

@target(javascript)
/// Encode an anchor as a self-describing JSON value.
pub fn text_anchor_to_json(anchor: TextAnchor) -> Json {
  text_kernel.anchor_to_json(anchor)
}

@target(javascript)
/// Decode an anchor from a JSON string produced by `text_anchor_to_json`. A
/// typed error on malformed JSON.
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
    json.UnexpectedSequence(seq) -> "unexpected sequence: " <> seq
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
/// The whole importable `crdt_core` snapshot: every channel's full CRDT
/// state, authoring cursors included, in canonical order.
///
/// It is a `Result` because the alternative is worse. The bytes come from
/// `canonical_json` and are re-read here to reach `gleam/json`'s value
/// type, which has no raw constructor; the read cannot fail for anything
/// this library can emit, but a public function that panicked — or worse,
/// quietly handed back a snapshot with the undecodable parts turned to
/// null — would be a snapshot nobody could trust.
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
/// Like the core import this is a join: local channels and local edits
/// survive it. Subscriber events fan out exactly once, and a merged state on an
/// attached document is handed to the existing anti-entropy / relay machinery
/// rather than taking a new path here.
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
/// Rebuild a document from an exported snapshot.
///
/// Size, protocol version, room, compatibility tag, root type, and every
/// channel's eligibility are checked before a single channel is loaded.
/// The result is detached — pass it to `attach` to bring it online.
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
/// The signaling room this document belongs to. Alias of `room`, named for
/// persistence storage keys.
pub fn room_id(document: CrdtDocument(root)) -> String {
  room(document)
}

@target(javascript)
/// The application compatibility tag this document enforces.
pub fn compatibility_tag(document: CrdtDocument(root)) -> String {
  crdt_core.compatibility(transport_js.get_cell(document.cell).document)
}

@target(javascript)
/// This replica's authorship identity: the configured label with a
/// per-connection random session id appended.
pub fn replica_id(document: CrdtDocument(root)) -> String {
  crdt_core.replica(transport_js.get_cell(document.cell).document)
}

@target(javascript)
/// The application label, without the session id.
pub fn replica_label(document: CrdtDocument(root)) -> String {
  transport_js.get_cell(document.cell).label
}

@target(javascript)
/// The canonical document digest. Two replicas holding the same logical
/// and causal state share it, on either compile target.
///
/// Computed once per document state and reused until the document moves,
/// so reading it in a render loop costs a comparison rather than a hash
/// of the whole document.
pub fn digest(document: CrdtDocument(root)) -> String {
  document_digest(document.cell)
}

@target(javascript)
/// How many times this document has canonicalized and hashed itself.
///
/// Diagnostic. Every digest this facade needs — the heartbeat, a peer's
/// comparison, the relay's publication and attestation, and `digest`
/// itself — is answered from one computation per document state, and this
/// is what says so: it advances when the document has moved since the
/// last digest, and does not when it has not.
pub fn digest_computations(document: CrdtDocument(root)) -> Int {
  let state = transport_js.get_cell(document.cell)
  transport_js.get_cell(state.digest_cache).computations
}

@target(javascript)
/// Peers that completed the `hello` handshake, sorted.
pub fn peers(document: CrdtDocument(root)) -> List(String) {
  greeted_peers(transport_js.get_cell(document.cell))
}

@target(javascript)
pub fn peer_count(document: CrdtDocument(root)) -> Int {
  list.length(peers(document))
}

@target(javascript)
/// How far this replica is through joining its room. `Joining` until a
/// peer has been validated, `WaitingForState` while a bootstrap
/// `stateRequest` is outstanding, `Bootstrapped` once a room's state has
/// merged. A diagnostic companion to `peer_count`.
pub fn bootstrap_state(document: CrdtDocument(root)) -> BootstrapState {
  transport_js.get_cell(document.cell).bootstrap
}

@target(javascript)
/// How many times a peer's anti-entropy digest told this replica it was
/// behind and it asked for state — mesh partition-repair activity, as a
/// running count. Zero on a document that has only ever agreed with its
/// peers.
pub fn repair_count(document: CrdtDocument(root)) -> Int {
  transport_js.get_cell(document.cell).repairs
}

@target(javascript)
/// The last peer digest that matched this replica's own, if any — the
/// most recent successful anti-entropy comparison. `None` until a peer
/// has confirmed the two agree.
pub fn last_digest_match(document: CrdtDocument(root)) -> Option(String) {
  transport_js.get_cell(document.cell).last_match
}

@target(javascript)
/// The readiness result this connection delivered, or `None` while it is
/// still being waited for.
///
/// Truthful about all three states, which a bare boolean cannot be: a
/// document that failed to join and one that is still joining are not the
/// same thing, and neither is ready.
pub fn readiness(
  document: CrdtDocument(root),
) -> Option(Result(Nil, P2pError)) {
  transport_js.get_cell(document.cell).readiness
}

@target(javascript)
/// Whether readiness has resolved at all, however it resolved. A closed
/// document reads `True`: its result was delivered either way.
pub fn readiness_resolved(document: CrdtDocument(root)) -> Bool {
  readiness(document) != None
}

@target(javascript)
pub fn is_closed(document: CrdtDocument(root)) -> Bool {
  transport_js.get_cell(document.cell).closed
}

@target(javascript)
/// The policy this document was configured with.
pub fn policy(document: CrdtDocument(root)) -> TransportPolicy {
  transport_js.get_cell(document.cell).policy
}

@target(javascript)
/// Where durable traffic is going right now.
///
/// `PeerToPeer` until a relay has merged, published, and matched digests;
/// `PeerToPeer` again the instant one drops, before the fallback status
/// is even emitted.
pub fn effective_path(document: CrdtDocument(root)) -> TransportPath {
  transport_js.get_cell(document.cell).path
}

@target(javascript)
/// Whether the relay is the durable delta path.
pub fn relay_is_primary(document: CrdtDocument(root)) -> Bool {
  transport_js.get_cell(document.cell).phase == RelayPrimaryPhase
}

@target(javascript)
/// Whether a relay lane has been opened at all. `False` under `P2pOnly`,
/// and under `Auto` with no sequencer configured.
pub fn relay_attached_lane(document: CrdtDocument(root)) -> Bool {
  transport_js.get_cell(document.cell).relay != None
}

@target(javascript)
/// A one-line rendering of a typed error, for status lines and logs.
pub fn describe_error(error: P2pError) -> String {
  let #(reason, detail) = error_parts(error)
  case detail {
    "" -> reason
    _ -> reason <> " · " <> detail
  }
}

@target(javascript)
/// The wire `reason`/`detail` pair a rejection is reported to a peer
/// with. Stable strings: a peer logs them, and a test asserts on them.
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
