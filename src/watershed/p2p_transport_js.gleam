//// The browser WebRTC transport for the CRDT p2p runtime: one
//// `RTCPeerConnection` per remote peer, one reliable unordered data
//// channel each, and nothing else.
////
//// This layer moves **strings**. It negotiates links, validates the
//// transport lifecycle, and hands every payload that arrives on a data
//// channel straight up to its caller. It never decodes a
//// `crdt_wire.Envelope`, never touches a `crdt_core.Document`, and holds
//// no document semantics — a room's document state is the facade's
//// problem (P2P5), not the transport's.
////
//// Signaling is a callback adapter, not a WebSocket dependency. The three
//// closures in `Signaling` carry offers, answers, and ICE candidates and
//// nothing else: `SignalPayload` is a closed sum of exactly those three,
//// so a document message cannot reach a signaling service even by
//// mistake. Applications supply their own adapter — Phoenix, a hosted
//// signaling product, or a hand-rolled invitation exchange.
////
//// The `Rtc` record is the browser seam. `real_rtc()` returns the native
//// `RTCPeerConnection` implementation in `p2p_transport_ffi.mjs`; tests
//// pass a deterministic fake to `start_with_rtc` and drive negotiation,
//// glare, and failures without a browser. Every mutable browser object
//// lives behind that seam, keyed by peer ID — Gleam owns no
//// `RTCPeerConnection`, no `RTCDataChannel`, and no listener list.
////
//// Negotiation is the standard perfect-negotiation algorithm with a
//// deterministic role assignment layered on top:
////
//// - the lexicographically **smaller** peer ID creates the offer and the
////   one data channel, so exactly one channel exists per link — whichever
////   signal first made the peer known, and however many times it is
////   repeated (see `Signaling` for the exact discovery contract);
//// - that same peer is the **impolite** one, so its offer wins a
////   simultaneous-offer collision and the larger peer rolls back;
//// - remote ICE candidates are queued until a remote description exists
////   and then flushed in arrival order;
//// - duplicate `PeerJoined`, offer, answer, candidate, close, and leave
////   signals are all no-ops.
////
//// Every asynchronous browser rejection reaches `Callbacks.on_error` as a
//// typed `p2p.P2pError` naming the peer. Nothing is thrown into the event
//// loop and nothing is swallowed — the one suppression, an
//// `addIceCandidate` failure while an offer is being ignored, is the
//// suppression the perfect-negotiation algorithm itself prescribes.
////
//// JavaScript target only.

@target(javascript)
import gleam/dict.{type Dict}
@target(javascript)
import gleam/int
@target(javascript)
import gleam/json
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{type Option, None, Some}
@target(javascript)
import gleam/order
@target(javascript)
import gleam/result
@target(javascript)
import gleam/string

@target(javascript)
import watershed/crdt_wire
@target(javascript)
import watershed/p2p.{type P2pError}
@target(javascript)
import watershed/transport_js.{type Cell}

// ─────────────────────────────────────────────────────────────────────────────
// Signaling
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// The only three things that ever cross a signaling service. There is no
/// variant for document data, so `crdt_wire` envelopes cannot be routed
/// through signaling however the adapter is written.
///
/// `sdp` is the raw session description text. `candidate` is the JSON
/// serialization of an `RTCIceCandidateInit` — opaque to this module,
/// parsed only by the browser.
pub type SignalPayload {
  Offer(sdp: String)
  Answer(sdp: String)
  Candidate(candidate: String)
}

@target(javascript)
/// What a signaling adapter reports back to the transport.
pub type Signal {
  /// The room's membership at the moment this peer was admitted,
  /// *complete*: every id in it is a member, and no member is missing.
  ///
  /// This is the one signal an adapter must send exactly once per
  /// successful `join`, empty room included — it is the only way a caller
  /// can tell "nobody is here" from "nobody has been announced yet", and
  /// a document that cannot tell those apart either waits forever or
  /// declares itself alone in a room that is not empty. An adapter that
  /// knows the membership inside `join` reports it there; one that learns
  /// it over a round trip reports it when it arrives.
  Roster(peers: List(String))
  PeerJoined(peer_id: String)
  PeerLeft(peer_id: String)
  Message(from: String, payload: SignalPayload)
  /// Signaling failed *after* `join` returned: the service went away, the
  /// socket closed, the roster never arrived. Reported as a typed
  /// `SignalingFailed` through `Callbacks.on_error`, so a caller still
  /// waiting to be admitted is answered rather than left hanging.
  ///
  /// It does not close the transport: data channels that are already open
  /// keep working without signaling, which is the whole point of a mesh.
  Failed(detail: String)
}

@target(javascript)
/// The membership token an adapter's `join` hands back, and that `send`
/// and `leave` take again.
///
/// It carries the room and local peer ID rather than the adapter's own
/// socket, because the three `Signaling` closures are built together and
/// close over whatever state the adapter needs. Keeping the token free of
/// adapter internals is what lets it stay a plain, sound Gleam value
/// instead of an unchecked cast around a browser object.
pub opaque type SignalingSession {
  SignalingSession(room: String, peer_id: String)
}

@target(javascript)
pub fn signaling_session(
  room room: String,
  peer_id peer_id: String,
) -> SignalingSession {
  SignalingSession(room: room, peer_id: peer_id)
}

@target(javascript)
pub fn session_room(session: SignalingSession) -> String {
  session.room
}

@target(javascript)
pub fn session_peer_id(session: SignalingSession) -> String {
  session.peer_id
}

@target(javascript)
/// An application-supplied signaling adapter.
///
/// `join` receives the room, the local peer ID, and the callback the
/// adapter drives with every `Signal`; it fails with a human-readable
/// detail, which the transport reports as `SignalingFailed`. `send`
/// addresses one peer. `leave` is called exactly once, by `close`.
///
/// ## Peer discovery contract
///
/// For each pair of members, exactly one side offers: the one with the
/// lexicographically **smaller** peer ID, which also creates the pair's
/// single data channel. So the whole of what an adapter must guarantee is:
///
/// > the smaller of any two peers learns about the larger — by a
/// > `PeerJoined(larger)`, or by any `Message` from it.
///
/// Nothing more is required, and no event has to be repeated. In
/// particular:
///
/// - **Order does not matter.** An `Offer` that overtakes its
///   `PeerJoined` is enough on its own; the `PeerJoined` that follows adds
///   nothing and creates no second channel.
/// - **Duplicates are free.** `PeerJoined`, `PeerLeft`, offers, answers,
///   and candidates are all idempotent, and a re-announced member is not
///   renegotiated.
/// - **One side is enough, if it is the right one.** Each one-sided shape
///   carries exactly the pairs whose *smaller* peer is the side being
///   told, and silently leaves the rest waiting. A roster to the newcomer
///   carries every pair whose newcomer sorts first; a notice to the
///   members already in the room carries every pair whose existing member
///   sorts first. Neither covers a whole mesh on its own. Announcing to
///   both sides — the common shape, and what the reference adapters do —
///   satisfies the contract for every pair and costs one extra event.
///
/// A member that leaves and rejoins under the same peer ID is a new
/// membership and must be announced again; a `PeerLeft` closes the peer,
/// and the `PeerJoined` after it is what rebuilds the link.
///
/// ## Roster contract
///
/// Connectivity is all the above requires. *Readiness* — a caller
/// knowing whether it is alone in the room — needs one thing more, and it
/// is the one obligation an adapter cannot skip:
///
/// > exactly one `Roster` per successful `join`, listing the whole
/// > membership at admission, the empty room included.
///
/// The roster may be reported from inside `join` or a round trip later;
/// it may repeat peers already announced, and peers may join or leave
/// before it arrives. What it may not do is never arrive, or arrive
/// missing a member: a caller that acts on "the room is empty" cannot
/// distinguish a late roster from a true one. An adapter that discovers
/// it cannot produce a roster — the socket died, the service never
/// answered — reports `Failed` instead, so the wait ends either way.
pub type Signaling {
  Signaling(
    join: fn(String, String, fn(Signal) -> Nil) ->
      Result(SignalingSession, String),
    send: fn(SignalingSession, String, SignalPayload) -> Nil,
    leave: fn(SignalingSession) -> Nil,
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Configuration
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// One entry of the browser's `RTCConfiguration.iceServers`. Watershed
/// ships no STUN or TURN defaults and no credentials: a caller that wants
/// NAT traversal supplies its own servers.
pub type IceServer {
  IceServer(
    urls: List(String),
    username: Option(String),
    credential: Option(String),
  )
}

@target(javascript)
/// A credential-free ICE server.
pub fn ice_server(urls urls: List(String)) -> IceServer {
  IceServer(urls: urls, username: None, credential: None)
}

@target(javascript)
/// Attach TURN credentials to an ICE server.
pub fn with_credentials(
  server: IceServer,
  username username: String,
  credential credential: String,
) -> IceServer {
  IceServer(..server, username: Some(username), credential: Some(credential))
}

@target(javascript)
/// The `RTCConfiguration` the peer connections are built with, as JSON.
/// Emitted here rather than marshalled field by field so the FFI parses
/// one browser-shaped object, and so the exact configuration a caller's
/// ICE servers produce is assertable without a browser.
pub fn rtc_configuration_json(servers: List(IceServer)) -> String {
  json.object([
    #("iceServers", json.array(servers, encode_ice_server)),
  ])
  |> json.to_string
}

@target(javascript)
fn encode_ice_server(server: IceServer) -> json.Json {
  let base = [#("urls", json.array(server.urls, json.string))]
  let with_user = case server.username {
    Some(username) -> [#("username", json.string(username)), ..base]
    None -> base
  }
  let with_credential = case server.credential {
    Some(credential) -> [#("credential", json.string(credential)), ..with_user]
    None -> with_user
  }
  json.object(list.reverse(with_credential))
}

@target(javascript)
/// The document data channel's label. One per peer, no others.
pub const document_channel_label = "watershed-crdt-v1"

@target(javascript)
/// The document channel's options: unordered and reliable.
///
/// `ordered: false` proves the protocol does not lean on one connection's
/// delivery order. Reliability comes from omitting both `maxRetransmits`
/// and `maxPacketLifeTime` — setting either one is what makes a channel
/// lossy, so the correct encoding of "reliable" is their absence, not a
/// large value.
pub fn document_channel_options_json() -> String {
  json.object([#("ordered", json.bool(False))]) |> json.to_string
}

@target(javascript)
/// Peers allowed in one room, local peer included. Read from the core
/// protocol limits so the transport and the wire agree by construction.
pub fn room_limit() -> Int {
  crdt_wire.default_limits().room_peers
}

// ─────────────────────────────────────────────────────────────────────────────
// Status and callbacks
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// Transport lifecycle facts, enough for the later facade to render
/// connection state and derive presence.
///
/// Presence is `PeerOpen`/`PeerClosed`/`PeerCount` and nothing else: a
/// peer counts as present exactly while its document data channel is
/// open. None of this is written into `crdt_core`.
pub type Status {
  SignalingJoined(room: String, peer_id: String)
  /// The adapter's `Roster`, after every peer in it has been tracked.
  /// Emitted once per join, and the only status that means "the room's
  /// membership is now completely known" — `known_peers` is already
  /// populated when it arrives, so a caller may read it and conclude it
  /// is alone.
  SignalingRoster(peers: List(String))
  SignalingLeft
  PeerConnecting(peer_id: String)
  PeerOpen(peer_id: String)
  PeerClosed(peer_id: String)
  PeerFailed(peer_id: String, detail: String)
  IceState(peer_id: String, state: String)
  PeerCount(open: Int)
}

@target(javascript)
/// Where the transport reports to. `on_document` receives the peer ID and
/// the raw string that arrived on its data channel, uninspected.
///
/// A `Status` describing a transition is always emitted *before* the
/// application callback for that same transition, so the status stream
/// stays complete and correctly ordered however the callback behaves —
/// including an `on_peer_open` that immediately closes the peer it was
/// handed. Every peer the stream announced as `PeerConnecting` is
/// eventually retired with a `PeerClosed`, whether or not it ever opened;
/// `on_peer_close` is the callback half of `on_peer_open` and fires only
/// for peers that did.
///
/// These are application callbacks and the transport does not catch what
/// they throw: an exception propagates out of whatever call ran it — a
/// `close`, a `send`, or a browser event — and skips the callbacks after
/// it. It cannot corrupt the transport. Every state write, every
/// `RTCPeerConnection` teardown, and the signaling `leave` happen before
/// the callbacks that report them, so a throwing callback leaves nothing
/// half-closed.
pub type Callbacks {
  Callbacks(
    on_peer_open: fn(String) -> Nil,
    on_peer_close: fn(String) -> Nil,
    on_document: fn(String, String) -> Nil,
    on_status: fn(Status) -> Nil,
    on_error: fn(P2pError) -> Nil,
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// The browser seam
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// What one peer connection reports back. Every callback names the remote
/// peer, so one hook set serves the whole mesh.
///
/// `on_remote_description` fires after `setRemoteDescription` resolves and
/// before any answer is produced — that is the moment queued ICE
/// candidates become applicable, so it is a separate hook rather than an
/// inference from `on_description`.
///
/// `on_failure` carries a stage tag (`open`, `offer`, `answer`,
/// `candidate`, `channel`, `connection`, `send`) so a rejection can be
/// classified before it becomes a `P2pError`.
pub type PeerHooks {
  PeerHooks(
    on_negotiation_needed: fn(String) -> Nil,
    on_description: fn(String, String, String) -> Nil,
    on_remote_description: fn(String) -> Nil,
    on_candidate: fn(String, String) -> Nil,
    on_channel_open: fn(String) -> Nil,
    on_channel_close: fn(String) -> Nil,
    on_message: fn(String, String) -> Nil,
    on_invalid_message: fn(String, String) -> Nil,
    on_ice_state: fn(String, String) -> Nil,
    on_failure: fn(String, String, String) -> Nil,
  )
}

@target(javascript)
/// The `RTCPeerConnection` operations this transport needs, keyed by
/// remote peer ID.
///
/// Every operation is fire-and-forget: the browser's promises are
/// asynchronous, so results come back through `PeerHooks` rather than
/// through return values. The two exceptions are `signaling_state` and
/// `diagnostics`, which read the connection synchronously, and `send`,
/// which reports whether the channel accepted the payload.
pub type Rtc {
  Rtc(
    /// Create the connection for `peer` from an `RTCConfiguration` JSON
    /// string, wiring `PeerHooks`. Idempotent per peer.
    open: fn(String, String, PeerHooks) -> Nil,
    /// Create the one document data channel (offerer side only), from a
    /// label and an `RTCDataChannelInit` JSON string.
    open_channel: fn(String, String, String) -> Nil,
    /// Set a local description and report it through `on_description`.
    offer: fn(String) -> Nil,
    /// Apply a remote offer — rolling back a local offer if one is
    /// outstanding — then answer.
    accept_offer: fn(String, String) -> Nil,
    /// Apply a remote answer.
    accept_answer: fn(String, String) -> Nil,
    /// Apply one remote ICE candidate from its JSON serialization.
    add_candidate: fn(String, String) -> Nil,
    /// The connection's `signalingState`, or `"closed"` if unknown.
    signaling_state: fn(String) -> String,
    /// Send one string on the document channel. `False` means the channel
    /// was not open, or the browser refused the payload.
    send: fn(String, String) -> Bool,
    /// Detach every listener, close the channel and the connection, and
    /// forget the peer. Idempotent.
    close: fn(String) -> Nil,
    /// A JSON description of the peer's channel and connection state, for
    /// status reporting and for asserting channel options against a real
    /// browser.
    diagnostics: fn(String) -> String,
  )
}

@target(javascript)
/// An opaque native peer-connection registry, owned entirely by the FFI.
pub type NativeRtc

@target(javascript)
@external(javascript, "./p2p_transport_ffi.mjs", "newRtc")
fn new_native_rtc() -> NativeRtc

@target(javascript)
@external(javascript, "./p2p_transport_ffi.mjs", "open")
fn native_open(
  rtc: NativeRtc,
  peer: String,
  configuration: String,
  on_negotiation_needed: fn(String) -> Nil,
  on_description: fn(String, String, String) -> Nil,
  on_remote_description: fn(String) -> Nil,
  on_candidate: fn(String, String) -> Nil,
  on_channel_open: fn(String) -> Nil,
  on_channel_close: fn(String) -> Nil,
  on_message: fn(String, String) -> Nil,
  on_invalid_message: fn(String, String) -> Nil,
  on_ice_state: fn(String, String) -> Nil,
  on_failure: fn(String, String, String) -> Nil,
) -> Nil

@target(javascript)
@external(javascript, "./p2p_transport_ffi.mjs", "openChannel")
fn native_open_channel(
  rtc: NativeRtc,
  peer: String,
  label: String,
  options: String,
) -> Nil

@target(javascript)
@external(javascript, "./p2p_transport_ffi.mjs", "offer")
fn native_offer(rtc: NativeRtc, peer: String) -> Nil

@target(javascript)
@external(javascript, "./p2p_transport_ffi.mjs", "acceptOffer")
fn native_accept_offer(rtc: NativeRtc, peer: String, sdp: String) -> Nil

@target(javascript)
@external(javascript, "./p2p_transport_ffi.mjs", "acceptAnswer")
fn native_accept_answer(rtc: NativeRtc, peer: String, sdp: String) -> Nil

@target(javascript)
@external(javascript, "./p2p_transport_ffi.mjs", "addCandidate")
fn native_add_candidate(rtc: NativeRtc, peer: String, candidate: String) -> Nil

@target(javascript)
@external(javascript, "./p2p_transport_ffi.mjs", "signalingState")
fn native_signaling_state(rtc: NativeRtc, peer: String) -> String

@target(javascript)
@external(javascript, "./p2p_transport_ffi.mjs", "send")
fn native_send(rtc: NativeRtc, peer: String, payload: String) -> Bool

@target(javascript)
@external(javascript, "./p2p_transport_ffi.mjs", "closePeer")
fn native_close(rtc: NativeRtc, peer: String) -> Nil

@target(javascript)
@external(javascript, "./p2p_transport_ffi.mjs", "diagnostics")
fn native_diagnostics(rtc: NativeRtc, peer: String) -> String

@target(javascript)
/// The native `RTCPeerConnection` backend. Each call returns a fresh
/// registry, so two transports in one page never share connections.
pub fn real_rtc() -> Rtc {
  let native = new_native_rtc()
  Rtc(
    open: fn(peer, configuration, hooks) {
      native_open(
        native,
        peer,
        configuration,
        hooks.on_negotiation_needed,
        hooks.on_description,
        hooks.on_remote_description,
        hooks.on_candidate,
        hooks.on_channel_open,
        hooks.on_channel_close,
        hooks.on_message,
        hooks.on_invalid_message,
        hooks.on_ice_state,
        hooks.on_failure,
      )
    },
    open_channel: fn(peer, label, options) {
      native_open_channel(native, peer, label, options)
    },
    offer: fn(peer) { native_offer(native, peer) },
    accept_offer: fn(peer, sdp) { native_accept_offer(native, peer, sdp) },
    accept_answer: fn(peer, sdp) { native_accept_answer(native, peer, sdp) },
    add_candidate: fn(peer, candidate) {
      native_add_candidate(native, peer, candidate)
    },
    signaling_state: fn(peer) { native_signaling_state(native, peer) },
    send: fn(peer, payload) { native_send(native, peer, payload) },
    close: fn(peer) { native_close(native, peer) },
    diagnostics: fn(peer) { native_diagnostics(native, peer) },
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Transport state
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// A running transport. Stop it with `close`.
pub opaque type Transport {
  Transport(cell: Cell(State))
}

@target(javascript)
type State {
  State(
    room: String,
    peer_id: String,
    signaling: Signaling,
    /// `None` until `join` returns, and again after `close`.
    session: Option(SignalingSession),
    rtc: Rtc,
    configuration: String,
    callbacks: Callbacks,
    peers: Dict(String, Peer),
    /// Signals an adapter delivered synchronously from inside `join`,
    /// before it had returned the session `send` needs. Drained, in
    /// arrival order, the moment the session is stored.
    pending_signals: List(Signal),
    closed: Bool,
  )
}

@target(javascript)
type Peer {
  Peer(
    id: String,
    /// The larger peer ID yields in a collision, so the smaller peer's
    /// offer — the only offer either side should be making — always wins.
    polite: Bool,
    /// The smaller peer ID offers and creates the one data channel.
    offerer: Bool,
    /// Whether `PeerConnecting` has been reported for this peer, so a
    /// teardown knows whether it owes the status stream a `PeerClosed`.
    announced: Bool,
    /// Whether `open_channel` has been asked for. The offerer creates its
    /// channel the first time the peer is observed by *any* route, and
    /// this is what keeps a second observation from creating another.
    channel_requested: Bool,
    /// Whether this peer has ever sent us an offer. Its offer carries its
    /// own data channel, which arrives in-band, so creating one here as
    /// well would put two channels on the link.
    remote_offered: Bool,
    making_offer: Bool,
    /// Set when an offer is dropped as an impolite collision, cleared by
    /// the next accepted remote description. While set, a failure to add
    /// a remote candidate is expected rather than an error: the candidate
    /// belongs to the description that was refused.
    ignore_offer: Bool,
    have_remote_description: Bool,
    /// The last remote offer applied, so an exact duplicate can be dropped
    /// instead of answered twice.
    last_remote_offer: Option(String),
    /// Remote candidates that arrived before a remote description, oldest
    /// last. Reversed on flush so they are applied in arrival order.
    queued_candidates: List(String),
    open: Bool,
  )
}

@target(javascript)
/// How many remote candidates may wait for a remote description. A peer
/// that sends more than this before describing itself is flooding, not
/// negotiating.
const max_queued_candidates = 128

@target(javascript)
fn new_peer(local: String, remote: String) -> Peer {
  Peer(
    id: remote,
    polite: string.compare(local, remote) == order.Gt,
    offerer: string.compare(local, remote) == order.Lt,
    announced: False,
    channel_requested: False,
    remote_offered: False,
    making_offer: False,
    ignore_offer: False,
    have_remote_description: False,
    last_remote_offer: None,
    queued_candidates: [],
    open: False,
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Lifecycle
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// Join a signaling room over real `RTCPeerConnection`s.
///
/// `peer_id` is this connection's collision-resistant session identity;
/// it is both the signaling address and the tie-break key, so two live
/// members of a room must never share one. `ice_servers` is applied with
/// browser `RTCConfiguration` semantics and may be empty, which is the
/// right choice on a LAN and for same-origin loopback.
pub fn start(
  room room: String,
  peer_id peer_id: String,
  signaling signaling: Signaling,
  ice_servers ice_servers: List(IceServer),
  callbacks callbacks: Callbacks,
) -> Result(Transport, P2pError) {
  start_with_rtc(
    room: room,
    peer_id: peer_id,
    signaling: signaling,
    ice_servers: ice_servers,
    callbacks: callbacks,
    rtc: real_rtc(),
  )
}

@target(javascript)
/// `start` against a substituted browser seam, so negotiation, glare,
/// candidate queueing, and failures can be driven deterministically
/// without a browser.
pub fn start_with_rtc(
  room room: String,
  peer_id peer_id: String,
  signaling signaling: Signaling,
  ice_servers ice_servers: List(IceServer),
  callbacks callbacks: Callbacks,
  rtc rtc: Rtc,
) -> Result(Transport, P2pError) {
  use _ <- result.try(validate(room, peer_id))
  let cell =
    transport_js.new_cell(State(
      room: room,
      peer_id: peer_id,
      signaling: signaling,
      session: None,
      rtc: rtc,
      configuration: rtc_configuration_json(ice_servers),
      callbacks: callbacks,
      peers: dict.new(),
      pending_signals: [],
      closed: False,
    ))
  case
    signaling.join(room, peer_id, fn(signal) { handle_signal(cell, signal) })
  {
    Error(detail) -> {
      let state = transport_js.get_cell(cell)
      transport_js.set_cell(cell, State(..state, closed: True))
      Error(p2p.SignalingFailed(detail))
    }
    Ok(session) -> {
      let state = transport_js.get_cell(cell)
      let queued = list.reverse(state.pending_signals)
      transport_js.set_cell(
        cell,
        State(..state, session: Some(session), pending_signals: []),
      )
      emit(cell, SignalingJoined(room: room, peer_id: peer_id))
      list.each(queued, fn(signal) { handle_signal(cell, signal) })
      Ok(Transport(cell: cell))
    }
  }
}

@target(javascript)
fn validate(room: String, peer_id: String) -> Result(Nil, P2pError) {
  case room, peer_id {
    "", _ -> Error(p2p.SignalingFailed("room id must not be empty"))
    _, "" -> Error(p2p.SignalingFailed("peer id must not be empty"))
    _, _ -> Ok(Nil)
  }
}

@target(javascript)
/// This transport's local peer ID.
pub fn local_peer_id(transport: Transport) -> String {
  transport_js.get_cell(transport.cell).peer_id
}

@target(javascript)
/// The room this transport joined.
pub fn room(transport: Transport) -> String {
  transport_js.get_cell(transport.cell).room
}

@target(javascript)
/// Peers whose document data channel is open, sorted. This is the whole
/// of p2p presence.
pub fn open_peers(transport: Transport) -> List(String) {
  transport_js.get_cell(transport.cell).peers
  |> dict.values
  |> list.filter(fn(peer) { peer.open })
  |> list.map(fn(peer) { peer.id })
  |> list.sort(string.compare)
}

@target(javascript)
/// How many peers have an open document data channel.
pub fn open_peer_count(transport: Transport) -> Int {
  list.length(open_peers(transport))
}

@target(javascript)
/// Every peer this transport is tracking, open or still negotiating.
pub fn known_peers(transport: Transport) -> List(String) {
  transport_js.get_cell(transport.cell).peers
  |> dict.keys
  |> list.sort(string.compare)
}

@target(javascript)
/// Whether `close` has run.
pub fn is_closed(transport: Transport) -> Bool {
  transport_js.get_cell(transport.cell).closed
}

@target(javascript)
/// A JSON description of one peer's channel and connection state.
pub fn peer_diagnostics(transport: Transport, peer_id: String) -> String {
  let state = transport_js.get_cell(transport.cell)
  state.rtc.diagnostics(peer_id)
}

@target(javascript)
/// Send one encoded document message to one peer. `False` means the peer
/// has no open channel — the caller decides whether that warrants a state
/// exchange later, so it is a return value rather than an error report.
pub fn send(transport: Transport, peer_id: String, payload: String) -> Bool {
  let state = transport_js.get_cell(transport.cell)
  case state.closed, dict.get(state.peers, peer_id) {
    False, Ok(peer) if peer.open -> state.rtc.send(peer_id, payload)
    _, _ -> False
  }
}

@target(javascript)
/// Send one encoded document message to every open peer, returning how
/// many accepted it.
pub fn broadcast(transport: Transport, payload: String) -> Int {
  open_peers(transport)
  |> list.fold(0, fn(sent, peer_id) {
    case send(transport, peer_id, payload) {
      True -> sent + 1
      False -> sent
    }
  })
}

@target(javascript)
/// Close one peer. Idempotent.
pub fn close_peer(transport: Transport, peer_id: String) -> Nil {
  teardown(transport.cell, peer_id, None)
}

@target(javascript)
/// Close every peer, drop the transport's grip on the browser, and leave
/// signaling exactly once. Idempotent: a second call does nothing, and no
/// signal delivered afterwards is acted on.
///
/// Every release the transport owes the outside world — the browser
/// objects and the signaling membership — happens *before* the first
/// application callback runs, so an exception thrown by a status or peer
/// callback cannot leave a room joined or a connection open. An exception
/// still propagates to the caller of `close` and will skip the callbacks
/// after it; the transport itself is fully closed either way.
pub fn close(transport: Transport) -> Nil {
  let cell = transport.cell
  let state = transport_js.get_cell(cell)
  case state.closed {
    True -> Nil
    False -> {
      let peers = dict.values(state.peers)
      transport_js.set_cell(
        cell,
        State(..state, peers: dict.new(), session: None, closed: True),
      )
      list.each(peers, fn(peer) { state.rtc.close(peer.id) })
      case state.session {
        Some(session) -> state.signaling.leave(session)
        None -> Nil
      }
      list.each(peers, fn(peer) {
        case peer.open || peer.announced {
          True -> state.callbacks.on_status(PeerClosed(peer.id))
          False -> Nil
        }
        case peer.open {
          True -> state.callbacks.on_peer_close(peer.id)
          False -> Nil
        }
      })
      state.callbacks.on_status(PeerCount(0))
      state.callbacks.on_status(SignalingLeft)
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Signal handling
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
fn handle_signal(cell: Cell(State), signal: Signal) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.closed, state.session {
    True, _ -> Nil
    False, None ->
      transport_js.set_cell(
        cell,
        State(..state, pending_signals: [signal, ..state.pending_signals]),
      )
    False, Some(_) ->
      case signal {
        Roster(peers) -> handle_roster(cell, peers)
        PeerJoined(peer_id) -> handle_peer_joined(cell, peer_id)
        PeerLeft(peer_id) -> teardown(cell, peer_id, None)
        Message(from, Offer(sdp)) -> handle_offer(cell, from, sdp)
        Message(from, Answer(sdp)) -> handle_answer(cell, from, sdp)
        Message(from, Candidate(candidate)) ->
          handle_candidate(cell, from, candidate)
        Failed(detail) -> signaling_failed(cell, detail)
      }
  }
}

@target(javascript)
/// The room's complete membership. Every member is tracked exactly as if
/// it had been announced one at a time, and only then is the roster
/// reported — so a caller reading `known_peers` from the
/// `SignalingRoster` status sees the whole room, and an empty roster
/// really does mean an empty room.
fn handle_roster(cell: Cell(State), peers: List(String)) -> Nil {
  list.each(peers, fn(peer_id) { handle_peer_joined(cell, peer_id) })
  emit(cell, SignalingRoster(peers))
}

@target(javascript)
/// Signaling failed after `join` returned. Reported as a typed error and
/// nothing else: open data channels do not need signaling, so tearing the
/// mesh down here would destroy the connectivity that survived.
fn signaling_failed(cell: Cell(State), detail: String) -> Nil {
  transport_js.get_cell(cell).callbacks.on_error(p2p.SignalingFailed(detail))
}

@target(javascript)
/// Track a peer, creating its connection, and — when we are the offerer —
/// its one data channel.
///
/// A peer already tracked is not created again, but its channel is still
/// ensured: an adapter may report a member the transport first met as an
/// inbound signal, or re-report one whose `createDataChannel` failed, and
/// neither may be left without the channel that drives negotiation.
///
/// The room cap is checked first: the ninth member of a room never gets an
/// `RTCPeerConnection`, only a `RoomFull`.
fn handle_peer_joined(cell: Cell(State), peer_id: String) -> Nil {
  case ensure_peer(cell, peer_id) {
    Error(Nil) -> Nil
    Ok(#(_, False)) -> ensure_channel(cell, peer_id)
    Ok(#(_, True)) ->
      // Constructing the connection can fail synchronously — a malformed
      // `RTCConfiguration`, or no WebRTC in this context — and that
      // failure tears the peer down before `open` returns. Nothing after
      // it may assume the peer survived.
      case open_connection(cell, peer_id) {
        False -> Nil
        True -> ensure_channel(cell, peer_id)
      }
  }
}

@target(javascript)
/// Create the one document data channel for a peer we offer to, if it does
/// not have one already.
///
/// Idempotent and route-independent: whichever event first made this peer
/// known — a `PeerJoined` for a newcomer, a `PeerJoined` for a member that
/// was already there, or a repeat of either — the offerer ends up with
/// exactly one channel, and the answering side receives it through
/// `ondatachannel`.
///
/// Two peers are left alone. One that has already offered is sending its
/// own channel in-band, so a second here would be one too many; one whose
/// channel is already open needs nothing.
fn ensure_channel(cell: Cell(State), peer_id: String) -> Nil {
  with_peer(cell, peer_id, fn(state, peer) {
    case
      peer.offerer
      && !peer.channel_requested
      && !peer.remote_offered
      && !peer.open
    {
      False -> Nil
      True -> {
        update_peer(cell, peer_id, fn(peer) {
          Peer(..peer, channel_requested: True)
        })
        state.rtc.open_channel(
          peer_id,
          document_channel_label,
          document_channel_options_json(),
        )
      }
    }
  })
}

@target(javascript)
/// Build the browser connection for a freshly tracked peer and report it
/// as connecting. `False` means the peer did not survive construction.
fn open_connection(cell: Cell(State), peer_id: String) -> Bool {
  let state = transport_js.get_cell(cell)
  state.rtc.open(peer_id, state.configuration, hooks(cell))
  case tracked(cell, peer_id) {
    False -> False
    True -> {
      update_peer(cell, peer_id, fn(peer) { Peer(..peer, announced: True) })
      state.callbacks.on_status(PeerConnecting(peer_id))
      True
    }
  }
}

@target(javascript)
/// Find or create a peer, reporting whether it was created. `Error(Nil)`
/// means the peer must not exist: it is us, we are closed, or the room is
/// full.
fn ensure_peer(
  cell: Cell(State),
  peer_id: String,
) -> Result(#(Peer, Bool), Nil) {
  let state = transport_js.get_cell(cell)
  case state.closed || peer_id == state.peer_id || peer_id == "" {
    True -> Error(Nil)
    False ->
      case dict.get(state.peers, peer_id) {
        Ok(peer) -> Ok(#(peer, False))
        Error(Nil) -> {
          let limit = room_limit()
          case dict.size(state.peers) + 2 > limit {
            True -> {
              state.callbacks.on_error(p2p.RoomFull(limit))
              Error(Nil)
            }
            False -> {
              let peer = new_peer(state.peer_id, peer_id)
              transport_js.set_cell(
                cell,
                State(..state, peers: dict.insert(state.peers, peer_id, peer)),
              )
              Ok(#(peer, True))
            }
          }
        }
      }
  }
}

@target(javascript)
/// Ensure the peer an inbound offer names, marking that it has offered.
///
/// A peer can turn up this way — an offer that beat its `PeerJoined`
/// through the signaling service, or a member no adapter ever announced —
/// and it gets a connection but no data channel of ours, whichever side it
/// is: an offer carries the offerer's own channel, which arrives in-band
/// through `ondatachannel`, so creating a second one here would put two
/// channels on one link. A `PeerJoined` arriving afterwards will not create
/// one either, for the same reason.
fn ensure_peer_for_offer(
  cell: Cell(State),
  peer_id: String,
) -> Result(Peer, Nil) {
  let ensured = case ensure_peer(cell, peer_id) {
    Error(Nil) -> Error(Nil)
    Ok(#(peer, False)) -> Ok(peer)
    Ok(#(peer, True)) ->
      case open_connection(cell, peer_id) {
        True -> Ok(peer)
        False -> Error(Nil)
      }
  }
  case ensured {
    Error(Nil) -> Error(Nil)
    Ok(peer) -> {
      update_peer(cell, peer_id, fn(peer) { Peer(..peer, remote_offered: True) })
      Ok(peer)
    }
  }
}

@target(javascript)
/// Perfect negotiation's collision guard.
///
/// A collision is a remote offer arriving while we have an offer of our
/// own outstanding. The impolite peer — the lexicographically smaller ID,
/// which is also the only peer that should be offering — refuses it and
/// remembers that refusal so the candidates belonging to the refused
/// description can fail quietly. The polite peer accepts, and the browser
/// rolls its own local offer back as part of applying the remote one.
///
/// This is also what makes a duplicate or reordered offer harmless: the
/// second copy either lands in a stable state, where re-applying it is a
/// no-op renegotiation, or it lands in a collision and is resolved by the
/// same rule as the first.
///
/// ponytail: between *conforming* peers this collision cannot happen — the
/// deterministic role assignment (the smaller ID is the only offerer) already
/// excludes simultaneous offers. The glare/polite-peer machinery is kept as
/// belt-and-braces against a non-conforming peer that offers out of turn;
/// it becomes deletable if the mesh ever enforces conformance at admission.
fn handle_offer(cell: Cell(State), from: String, sdp: String) -> Nil {
  case ensure_peer_for_offer(cell, from) {
    Error(Nil) -> Nil
    // An exact repeat of the offer we already applied is a duplicated
    // signal, not a renegotiation: answering it again would put a second
    // answer on the wire for one description.
    Ok(peer) if peer.last_remote_offer == Some(sdp) -> Nil
    Ok(peer) -> {
      let state = transport_js.get_cell(cell)
      let collision =
        peer.making_offer || state.rtc.signaling_state(from) != "stable"
      case collision && !peer.polite {
        True ->
          update_peer(cell, from, fn(peer) { Peer(..peer, ignore_offer: True) })
        False -> {
          update_peer(cell, from, fn(peer) {
            Peer(
              ..peer,
              ignore_offer: False,
              making_offer: False,
              last_remote_offer: Some(sdp),
            )
          })
          state.rtc.accept_offer(from, sdp)
        }
      }
    }
  }
}

@target(javascript)
/// An answer is only meaningful against an outstanding local offer.
/// Anything else — a duplicate, a reordered copy, an answer to an offer
/// we rolled back — is dropped rather than pushed into the browser, which
/// would reject it asynchronously and report a failure that is not one.
fn handle_answer(cell: Cell(State), from: String, sdp: String) -> Nil {
  let state = transport_js.get_cell(cell)
  case dict.get(state.peers, from) {
    Error(Nil) -> Nil
    Ok(_) ->
      case state.rtc.signaling_state(from) == "have-local-offer" {
        False -> Nil
        True -> state.rtc.accept_answer(from, sdp)
      }
  }
}

@target(javascript)
/// Remote candidates are useless — and rejected by the browser — until a
/// remote description exists, so they queue until one does and are then
/// flushed in arrival order.
///
/// A candidate for a peer we do not know is dropped rather than allowed to
/// create one. `PeerJoined` and an offer are the two events that introduce
/// a peer; a candidate that beat both of them describes a connection that
/// does not exist yet, and letting it conjure a peer would also let a
/// flooding peer reappear the instant its flood closed it.
fn handle_candidate(cell: Cell(State), from: String, candidate: String) -> Nil {
  let known = transport_js.get_cell(cell).peers
  case dict.get(known, from) {
    Error(Nil) -> Nil
    Ok(peer) ->
      case peer.have_remote_description {
        // Re-adding a candidate the ICE agent already has is a no-op by
        // specification, so an applied duplicate needs no guard here.
        True -> {
          let state = transport_js.get_cell(cell)
          state.rtc.add_candidate(from, candidate)
        }
        False ->
          case list.contains(peer.queued_candidates, candidate) {
            True -> Nil
            False ->
              case
                list.length(peer.queued_candidates) >= max_queued_candidates
              {
                True ->
                  teardown(
                    cell,
                    from,
                    Some(
                      "queued more than "
                      <> int.to_string(max_queued_candidates)
                      <> " ice candidates before describing itself",
                    ),
                  )
                False ->
                  update_peer(cell, from, fn(peer) {
                    Peer(..peer, queued_candidates: [
                      candidate,
                      ..peer.queued_candidates
                    ])
                  })
              }
          }
      }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Browser hooks
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
fn hooks(cell: Cell(State)) -> PeerHooks {
  PeerHooks(
    on_negotiation_needed: fn(peer) { handle_negotiation_needed(cell, peer) },
    on_description: fn(peer, kind, sdp) {
      handle_local_description(cell, peer, kind, sdp)
    },
    on_remote_description: fn(peer) { handle_remote_description(cell, peer) },
    on_candidate: fn(peer, candidate) {
      handle_local_candidate(cell, peer, candidate)
    },
    on_channel_open: fn(peer) { handle_channel_open(cell, peer) },
    on_channel_close: fn(peer) { handle_channel_close(cell, peer) },
    on_message: fn(peer, data) { handle_message(cell, peer, data) },
    on_invalid_message: fn(peer, detail) {
      handle_invalid_message(cell, peer, detail)
    },
    on_ice_state: fn(peer, ice_state) {
      handle_ice_state(cell, peer, ice_state)
    },
    on_failure: fn(peer, stage, detail) {
      handle_failure(cell, peer, stage, detail)
    },
  )
}

@target(javascript)
fn handle_negotiation_needed(cell: Cell(State), peer_id: String) -> Nil {
  with_peer(cell, peer_id, fn(state, _peer) {
    update_peer(cell, peer_id, fn(peer) { Peer(..peer, making_offer: True) })
    state.rtc.offer(peer_id)
  })
}

@target(javascript)
fn handle_local_description(
  cell: Cell(State),
  peer_id: String,
  kind: String,
  sdp: String,
) -> Nil {
  with_peer(cell, peer_id, fn(state, _peer) {
    update_peer(cell, peer_id, fn(peer) { Peer(..peer, making_offer: False) })
    case kind {
      "offer" -> signal_to(state, peer_id, Offer(sdp))
      "answer" -> signal_to(state, peer_id, Answer(sdp))
      other ->
        state.callbacks.on_error(p2p.PeerConnectionFailed(
          peer_id,
          "unexpected local description type: " <> other,
        ))
    }
  })
}

@target(javascript)
fn handle_remote_description(cell: Cell(State), peer_id: String) -> Nil {
  with_peer(cell, peer_id, fn(state, peer) {
    let queued = list.reverse(peer.queued_candidates)
    update_peer(cell, peer_id, fn(peer) {
      Peer(
        ..peer,
        have_remote_description: True,
        ignore_offer: False,
        queued_candidates: [],
      )
    })
    list.each(queued, fn(candidate) {
      state.rtc.add_candidate(peer_id, candidate)
    })
  })
}

@target(javascript)
fn handle_local_candidate(
  cell: Cell(State),
  peer_id: String,
  candidate: String,
) -> Nil {
  with_peer(cell, peer_id, fn(state, _peer) {
    signal_to(state, peer_id, Candidate(candidate))
  })
}

@target(javascript)
fn handle_channel_open(cell: Cell(State), peer_id: String) -> Nil {
  with_peer(cell, peer_id, fn(state, peer) {
    case peer.open {
      True -> Nil
      False -> {
        update_peer(cell, peer_id, fn(peer) { Peer(..peer, open: True) })
        state.callbacks.on_status(PeerOpen(peer_id))
        emit_peer_count(cell)
        state.callbacks.on_peer_open(peer_id)
      }
    }
  })
}

@target(javascript)
fn handle_channel_close(cell: Cell(State), peer_id: String) -> Nil {
  teardown(cell, peer_id, None)
}

@target(javascript)
fn handle_message(cell: Cell(State), peer_id: String, data: String) -> Nil {
  with_peer(cell, peer_id, fn(state, _peer) {
    state.callbacks.on_document(peer_id, data)
  })
}

@target(javascript)
/// The document channel carries strings. Anything else is a peer speaking
/// a protocol this transport does not have, so it is reported and the
/// peer is closed rather than skipped.
///
/// The peer is dropped before the report goes out: a foreign message means
/// this connection is finished either way, and an `on_error` that throws
/// must not be able to keep it alive.
fn handle_invalid_message(
  cell: Cell(State),
  peer_id: String,
  detail: String,
) -> Nil {
  let state = transport_js.get_cell(cell)
  case dict.get(state.peers, peer_id) {
    Error(Nil) -> Nil
    Ok(_) -> {
      let dropped = drop_peer(cell, peer_id)
      state.callbacks.on_error(p2p.InvalidEnvelope(peer_id, detail))
      case dropped {
        None -> Nil
        Some(peer) -> report_teardown(cell, peer, None)
      }
    }
  }
}

@target(javascript)
/// ICE state is reported as status. `failed` and `closed` are terminal
/// without a restart, so they also tear the peer down — leaving it in the
/// peer set would overstate the mesh.
///
/// A terminal state drops the peer before the status is emitted, for the
/// same reason a foreign message does: the connection is over whatever the
/// application's callback does with the news.
///
/// `disconnected` is deliberately not terminal: the browser recovers from
/// it on its own, and treating it as a loss would churn presence on every
/// brief network hiccup.
fn handle_ice_state(cell: Cell(State), peer_id: String, ice: String) -> Nil {
  let state = transport_js.get_cell(cell)
  case dict.get(state.peers, peer_id) {
    Error(Nil) -> Nil
    Ok(_) ->
      case ice == "failed" || ice == "closed" {
        False -> state.callbacks.on_status(IceState(peer_id, ice))
        True -> {
          let dropped = drop_peer(cell, peer_id)
          state.callbacks.on_status(IceState(peer_id, ice))
          case dropped {
            None -> Nil
            Some(peer) ->
              report_teardown(cell, peer, case ice {
                "failed" -> Some("ice connection failed")
                _ -> None
              })
          }
        }
      }
  }
}

@target(javascript)
/// Every asynchronous browser rejection lands here and leaves as a typed
/// error naming the peer and the stage that failed.
///
/// A failed description stage clears the negotiation flags the attempt set,
/// with `finally` semantics: `making_offer` survives a rejected
/// `setLocalDescription` otherwise, and a peer whose `making_offer` is
/// stuck sees every later remote offer as a collision and — when it is the
/// impolite side — refuses all of them, which wedges the link for good. A
/// failed answer stage forgets the offer it could not apply too, so a
/// retransmission of that same offer is answered rather than dropped as a
/// duplicate. A failed channel stage forgets the request, so the next time
/// the peer is observed the channel is attempted again.
///
/// The one exception to reporting is the suppression perfect negotiation
/// prescribes: a candidate cannot be applied to a description we refused,
/// so while `ignore_offer` is set that particular failure is expected and
/// is not reported. Every other candidate failure is.
///
/// Two stages are terminal and also close the peer: `open`, where no
/// connection was ever constructed, and `connection`, where the browser
/// has declared the established one failed. The rest are reported and
/// left alone — a description or a send can fail without the link being
/// beyond repair, and closing a peer is the facade's call once it has the
/// error.
fn handle_failure(
  cell: Cell(State),
  peer_id: String,
  stage: String,
  detail: String,
) -> Nil {
  let state = transport_js.get_cell(cell)
  case dict.get(state.peers, peer_id) {
    Error(Nil) -> Nil
    Ok(peer) ->
      case stage == "candidate" && peer.ignore_offer {
        True -> Nil
        False -> {
          clear_negotiation_flags(cell, peer_id, stage)
          let described = stage <> ": " <> detail
          case stage == "open" || stage == "connection" {
            True -> teardown(cell, peer_id, Some(described))
            False -> {
              state.callbacks.on_status(PeerFailed(peer_id, described))
              state.callbacks.on_error(p2p.PeerConnectionFailed(
                peer_id,
                described,
              ))
            }
          }
        }
      }
  }
}

@target(javascript)
/// Undo the bookkeeping a failed stage left behind, so the next signal is
/// judged against what the connection actually is rather than against an
/// attempt that never landed.
fn clear_negotiation_flags(
  cell: Cell(State),
  peer_id: String,
  stage: String,
) -> Nil {
  case stage {
    "offer" ->
      update_peer(cell, peer_id, fn(peer) { Peer(..peer, making_offer: False) })
    "answer" ->
      update_peer(cell, peer_id, fn(peer) {
        Peer(..peer, making_offer: False, last_remote_offer: None)
      })
    "channel" ->
      update_peer(cell, peer_id, fn(peer) {
        Peer(..peer, channel_requested: False)
      })
    _ -> Nil
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// Run `action` only for a peer this transport still tracks on a
/// transport that is still open. A hook that fires for a peer we have
/// already torn down is not an error — the browser can have a callback in
/// flight when `close` runs — it is simply nothing to do.
fn with_peer(
  cell: Cell(State),
  peer_id: String,
  action: fn(State, Peer) -> Nil,
) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.closed, dict.get(state.peers, peer_id) {
    False, Ok(peer) -> action(state, peer)
    _, _ -> Nil
  }
}

@target(javascript)
fn tracked(cell: Cell(State), peer_id: String) -> Bool {
  case dict.get(transport_js.get_cell(cell).peers, peer_id) {
    Ok(_) -> True
    Error(Nil) -> False
  }
}

@target(javascript)
fn update_peer(
  cell: Cell(State),
  peer_id: String,
  change: fn(Peer) -> Peer,
) -> Nil {
  let state = transport_js.get_cell(cell)
  case dict.get(state.peers, peer_id) {
    Error(Nil) -> Nil
    Ok(peer) ->
      transport_js.set_cell(
        cell,
        State(..state, peers: dict.insert(state.peers, peer_id, change(peer))),
      )
  }
}

@target(javascript)
fn signal_to(state: State, peer_id: String, payload: SignalPayload) -> Nil {
  case state.session {
    Some(session) -> state.signaling.send(session, peer_id, payload)
    None -> Nil
  }
}

@target(javascript)
fn emit(cell: Cell(State), status: Status) -> Nil {
  transport_js.get_cell(cell).callbacks.on_status(status)
}

@target(javascript)
fn emit_peer_count(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  let open =
    state.peers
    |> dict.values
    |> list.filter(fn(peer) { peer.open })
    |> list.length
  state.callbacks.on_status(PeerCount(open))
}

@target(javascript)
/// Drop one peer: forget it first, then close the browser objects, then
/// report. Forgetting first is what makes this idempotent under
/// re-entrant callbacks — a listener that fires while the connection is
/// closing finds no peer and does nothing.
///
/// Every peer the status stream announced as `PeerConnecting` is closed
/// with a `PeerClosed`, open or not, so a peer that dies mid-negotiation
/// cannot leave a facade rendering it as connecting for ever. The
/// `on_peer_close` *callback* stays paired with `on_peer_open` and fires
/// only for a peer that opened.
fn teardown(
  cell: Cell(State),
  peer_id: String,
  failure: Option(String),
) -> Nil {
  case drop_peer(cell, peer_id) {
    None -> Nil
    Some(peer) -> report_teardown(cell, peer, failure)
  }
}

@target(javascript)
/// The half of a teardown that must happen before any application
/// callback: forget the peer and close its browser objects. `None` means
/// there was no such peer, so nothing is owed a report either.
///
/// Split out because two paths — a terminal ICE state and a foreign
/// message — report what happened *before* the peer is gone, and a
/// callback that throws there must not be able to leave a dead connection
/// tracked, addressable by `broadcast`, and holding a room slot.
fn drop_peer(cell: Cell(State), peer_id: String) -> Option(Peer) {
  let state = transport_js.get_cell(cell)
  case dict.get(state.peers, peer_id) {
    Error(Nil) -> None
    Ok(peer) -> {
      transport_js.set_cell(
        cell,
        State(..state, peers: dict.delete(state.peers, peer_id)),
      )
      state.rtc.close(peer_id)
      Some(peer)
    }
  }
}

@target(javascript)
/// The reporting half of a teardown, for a peer `drop_peer` has already
/// forgotten.
fn report_teardown(
  cell: Cell(State),
  peer: Peer,
  failure: Option(String),
) -> Nil {
  let state = transport_js.get_cell(cell)
  case failure {
    Some(detail) -> state.callbacks.on_status(PeerFailed(peer.id, detail))
    None -> Nil
  }
  case peer.open || peer.announced {
    True -> state.callbacks.on_status(PeerClosed(peer.id))
    False -> Nil
  }
  emit_peer_count(cell)
  case failure {
    Some(detail) ->
      state.callbacks.on_error(p2p.PeerConnectionFailed(peer.id, detail))
    None -> Nil
  }
  case peer.open {
    True -> state.callbacks.on_peer_close(peer.id)
    False -> Nil
  }
}
