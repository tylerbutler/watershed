//// The browser WebRTC transport for the CRDT p2p runtime: one
//// `RTCPeerConnection` per remote peer, one reliable unordered data
//// channel each, and nothing else.
////
//// This layer moves **strings**. It negotiates the links, checks the
//// transport lifecycle, and passes every payload that arrives on a data
//// channel directly up to its caller. It never decodes a
//// `crdt_wire.Envelope` value, it never touches a `crdt_core.Document`
//// value, and it holds no document behaviour. The document state of a room
//// belongs to the facade (P2P5), and not to the transport.
////
//// Signaling is a callback adapter, and not a dependency on a WebSocket. The
//// three closures in `Signaling` carry an offer, an answer, and an ICE
//// candidate, and nothing else. `SignalPayload` is a closed sum of exactly
//// those three, so a document message cannot reach a signaling service, not
//// even by mistake. An application supplies its own adapter, over Phoenix,
//// over a hosted signaling product, or over an invitation exchange that the
//// application writes.
////
//// The `Rtc` record is the browser seam. `real_rtc()` returns the native
//// `RTCPeerConnection` implementation in `p2p_transport_ffi.mjs`. A test
//// gives a deterministic substitute to `start_with_rtc`, and it can then
//// drive the negotiation, a collision, and a failure, with no browser. Every
//// mutable browser object is behind that seam, keyed by peer id. Gleam owns
//// no `RTCPeerConnection`, no `RTCDataChannel`, and no list of listeners.
////
//// The negotiation is the standard perfect-negotiation algorithm, with a
//// deterministic assignment of the roles on top of it:
////
//// - The peer with the **smaller** id, in lexicographic order, creates the
////   offer and the one data channel. Exactly one channel thus exists on each
////   link, whichever signal first made that peer known, and whatever number
////   of times a signal repeats. See `Signaling` for the exact discovery
////   contract.
//// - That same peer is the **impolite** one. Its offer thus wins a collision
////   of two simultaneous offers, and the peer with the larger id rolls back.
//// - A remote ICE candidate waits in a queue until a remote description
////   exists. The transport then applies the queue in arrival order.
//// - A duplicate `PeerJoined`, offer, answer, candidate, close, and leave
////   signal all change nothing.
////
//// Every asynchronous rejection from the browser reaches `Callbacks.on_error`
//// as a typed `p2p.P2pError` value that names the peer. The transport throws
//// nothing into the event loop, and it hides nothing. There is one
//// suppression: a failure of `addIceCandidate` while the transport ignores an
//// offer. The perfect-negotiation algorithm prescribes that suppression.
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
/// The only three values that cross a signaling service. There is no variant
/// for document data, so a signaling service cannot route a `crdt_wire`
/// envelope, whatever the author of the adapter writes.
///
/// `sdp` is the raw text of a session description. `candidate` is the JSON
/// serialization of an `RTCIceCandidateInit` value. That string is opaque to
/// this module, and the browser is the only reader of it.
pub type SignalPayload {
  Offer(sdp: String)
  Answer(sdp: String)
  Candidate(candidate: String)
}

@target(javascript)
/// What a signaling adapter reports back to the transport.
pub type Signal {
  /// The membership of the room at the moment that the service admitted this
  /// peer. The list must be *complete*: every id in it is a member, and no
  /// member is absent.
  ///
  /// An adapter must send this one signal exactly one time for each
  /// successful `join` call, and that includes a join into an empty room.
  /// This signal is the only way for a caller to separate "no client is here"
  /// from "no client is announced yet". A document that cannot separate those
  /// two conditions either waits without an end, or it declares that it is
  /// alone in a room that is not empty. An adapter that knows the membership
  /// inside `join` reports it there. An adapter that learns the membership
  /// over a round trip reports it when that membership arrives.
  Roster(peers: List(String))
  PeerJoined(peer_id: String)
  PeerLeft(peer_id: String)
  Message(from: String, payload: SignalPayload)
  /// Signaling failed *after* `join` returned. The service became
  /// unavailable, the socket closed, or the roster never arrived. The
  /// transport reports this signal as a typed `SignalingFailed` value,
  /// through `Callbacks.on_error`. A caller that still waits for admission
  /// thus gets an answer, and it does not wait without an end.
  ///
  /// This signal does not close the transport. A data channel that is already
  /// open continues to work without signaling, and that property is the
  /// purpose of a mesh.
  Failed(detail: String)
}

@target(javascript)
/// The membership token that the `join` function of an adapter returns, and
/// that `send` and `leave` take again.
///
/// The token carries the room and the local peer id, and not the socket of the
/// adapter. The three `Signaling` closures are built together, and they close
/// over whatever state the adapter needs. The token thus contains no adapter
/// internals, and it can stay a plain, sound Gleam value. It is not an
/// unchecked cast around a browser object.
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
/// A signaling adapter that the application supplies.
///
/// `join` receives the room, the local peer id, and the callback that the
/// adapter calls with every `Signal` value. It fails with a detail string for a
/// person to read, and the transport reports that string as
/// `SignalingFailed`. `send` addresses one peer. `close` calls `leave` exactly
/// one time.
///
/// ## The peer discovery contract
///
/// For each pair of members, exactly one side offers. That side is the peer
/// with the **smaller** id, in lexicographic order, and that peer also creates
/// the one data channel of the pair. An adapter must thus guarantee one thing
/// only:
///
/// > The smaller of any two peers learns about the larger one, through a
/// > `PeerJoined(larger)` signal, or through any `Message` from that peer.
///
/// Nothing more is necessary, and no event has to repeat. In particular:
///
/// - **The order does not matter.** An `Offer` that arrives before its
///   `PeerJoined` is sufficient by itself. The `PeerJoined` that follows adds
///   nothing, and it creates no second channel.
/// - **A duplicate costs nothing.** `PeerJoined`, `PeerLeft`, an offer, an
///   answer, and a candidate are all idempotent, and the transport does not
///   negotiate again with a member that an adapter announces a second time.
/// - **One side is sufficient, if it is the correct side.** Each one-sided
///   shape carries exactly the pairs whose *smaller* peer is the side that
///   receives the announcement, and it leaves the other pairs waiting, with no
///   report. A roster to the new peer carries every pair in which that new
///   peer sorts first. A notice to the members that are already in the room
///   carries every pair in which the existing member sorts first. Neither
///   shape covers a whole mesh by itself. To announce to both sides satisfies
///   the contract for every pair, and it costs one more event. That is the
///   usual shape, and the reference adapters use it.
///
/// A member that leaves and joins again under the same peer id is a new
/// membership, and the adapter must announce it again. A `PeerLeft` signal
/// closes the peer, and the `PeerJoined` signal after it rebuilds the link.
///
/// ## The roster contract
///
/// The rules above give connectivity. *Readiness*, which is a caller that
/// knows whether it is alone in the room, needs one more thing. That is the
/// one obligation that an adapter cannot omit:
///
/// > Exactly one `Roster` signal for each successful `join`, which lists the
/// > whole membership at admission, and which the adapter sends also for an
/// > empty room.
///
/// The adapter can report the roster from inside `join`, or one round trip
/// later. That roster can repeat a peer that the adapter already announced,
/// and a peer can join or leave before the roster arrives. The roster must not
/// be absent, and it must not omit a member. A caller that acts on "the room
/// is empty" cannot separate a late roster from a true one. An adapter that
/// finds that it cannot produce a roster, because the socket closed or the
/// service never answered, reports `Failed` instead. The wait thus ends in
/// both conditions.
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
/// One entry of the `RTCConfiguration.iceServers` list of the browser.
/// watershed supplies no default STUN server, no default TURN server, and no
/// credentials. A caller that wants NAT traversal supplies its own servers, or
/// it selects the `public_stun_servers` preset by name.
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
/// Add TURN credentials to an ICE server.
pub fn with_credentials(
  server: IceServer,
  username username: String,
  credential credential: String,
) -> IceServer {
  IceServer(..server, username: Some(username), credential: Some(credential))
}

@target(javascript)
/// Free public STUN servers, for a caller that wants NAT traversal and deploys
/// nothing. The list holds the servers of Google and of Cloudflare. Those two
/// operators are independent of each other, and each one publishes these
/// addresses for exactly this use. The servers are free, they need no
/// credentials, and they have been stable for years. A STUN server only tells
/// a peer its own public address, in a few request and response packets for
/// each connection. That small cost is the reason that STUN is free, and STUN
/// is sufficient for most NAT pairs.
///
/// This preset cannot cover one condition. Two peers behind *symmetric* NATs
/// have no direct path, and they need TURN. A TURN server carries the whole
/// stream, so there is no free public TURN service. A caller that needs those
/// pairs adds its own TURN server, with `ice_server` and `with_credentials`.
///
/// These are best-effort services from a third party, on the infrastructure of
/// another company. That is the trade of this preset. A deployment that needs
/// a service level runs its own servers instead, for example coturn.
pub fn public_stun_servers() -> List(IceServer) {
  [
    ice_server(urls: ["stun:stun.l.google.com:19302"]),
    ice_server(urls: ["stun:stun.cloudflare.com:3478"]),
  ]
}

@target(javascript)
/// The `RTCConfiguration` value that the peer connections are built with, as
/// JSON. This function emits the whole object, and the code does not pass one
/// field at a time. The FFI thus parses one object in the shape that the
/// browser needs, and a test can assert the exact configuration that the ICE
/// servers of a caller produce, with no browser.
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
/// The label of the document data channel. There is one such channel for each
/// peer, and no other channel.
pub const document_channel_label = "watershed-crdt-v1"

@target(javascript)
/// The options of the document channel: unordered and reliable.
///
/// `ordered: false` proves that the protocol does not depend on the delivery
/// order of one connection. The channel is reliable because the options omit
/// `maxRetransmits` and `maxPacketLifeTime`. To set either one makes a channel
/// lossy, so the correct encoding of "reliable" is the absence of both fields,
/// and not a large value.
pub fn document_channel_options_json() -> String {
  json.object([#("ordered", json.bool(False))]) |> json.to_string
}

@target(javascript)
/// The number of peers that one room permits, and that number includes the
/// local peer. The value comes from the core protocol limits, so the transport
/// and the wire agree by construction.
pub fn room_limit() -> Int {
  crdt_wire.default_limits().room_peers
}

// ─────────────────────────────────────────────────────────────────────────────
// Status and callbacks
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// The facts of the transport lifecycle. They are sufficient for the facade
/// above to render the connection state and to derive the presence.
///
/// The presence is `PeerOpen`, `PeerClosed`, and `PeerCount`, and nothing
/// else. A peer is present exactly while its document data channel is open.
/// None of this data goes into `crdt_core`.
pub type Status {
  SignalingJoined(room: String, peer_id: String)
  /// The `Roster` signal of the adapter, after the transport tracks every peer
  /// in it. The transport emits this status one time for each join. It is the
  /// only status that means that the membership of the room is now completely
  /// known. `known_peers` already holds every peer when this status arrives,
  /// so a caller can read that list and conclude that it is alone.
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
/// The place that the transport reports to. `on_document` receives the peer id
/// and the raw string that arrived on the data channel of that peer. The
/// transport does not read that string.
///
/// A `Status` value that describes a transition always goes out *before* the
/// application callback for that same transition. The status stream thus stays
/// complete and correctly ordered, whatever the callback does. That includes an
/// `on_peer_open` callback that immediately closes the peer that it received.
/// Every peer that the stream announced as `PeerConnecting` later gets a
/// `PeerClosed` status, whether or not that peer opened. `on_peer_close` is the
/// callback that pairs with `on_peer_open`, and it runs only for a peer that
/// opened.
///
/// These are application callbacks, and the transport does not catch what they
/// throw. An exception goes out of the call that ran the callback, which is a
/// `close` call, a `send` call, or a browser event, and it skips the callbacks
/// after that one. It cannot corrupt the transport. Every write to the state,
/// every teardown of an `RTCPeerConnection`, and the signaling `leave` all
/// happen before the callbacks that report them. A callback that throws thus
/// leaves nothing half-closed.
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
/// What one peer connection reports back. Every callback names the remote peer,
/// so one set of hooks serves the whole mesh.
///
/// `on_remote_description` runs after `setRemoteDescription` resolves, and
/// before the browser produces an answer. At that moment the queued ICE
/// candidates become applicable. That hook is thus separate, and a caller does
/// not derive the moment from `on_description`.
///
/// `on_failure` carries a stage tag, which is `open`, `offer`, `answer`,
/// `candidate`, `channel`, `connection`, or `send`. The transport can thus
/// classify a rejection before it converts that rejection into a `P2pError`
/// value.
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
/// The `RTCPeerConnection` operations that this transport needs, keyed by
/// remote peer id.
///
/// Most operations expect no reply. The promises of the browser are
/// asynchronous, so a result comes back through `PeerHooks` and not through a
/// return value. There are three exceptions. `signaling_state` and
/// `diagnostics` read the connection synchronously. `send` reports whether the
/// channel accepted the payload.
pub type Rtc {
  Rtc(
    /// Create the connection for `peer` from an `RTCConfiguration` JSON
    /// string, and connect the `PeerHooks` callbacks. A second call for the
    /// same peer has no more effect.
    open: fn(String, String, PeerHooks) -> Nil,
    /// Create the one document data channel, on the side that offers only,
    /// from a label and an `RTCDataChannelInit` JSON string.
    open_channel: fn(String, String, String) -> Nil,
    /// Set a local description and report it through `on_description`.
    offer: fn(String) -> Nil,
    /// Apply a remote offer, and then answer it. If a local offer is
    /// outstanding, the browser rolls that offer back first.
    accept_offer: fn(String, String) -> Nil,
    /// Apply a remote answer.
    accept_answer: fn(String, String) -> Nil,
    /// Apply one remote ICE candidate from its JSON serialization.
    add_candidate: fn(String, String) -> Nil,
    /// The connection's `signalingState`, or `"closed"` if unknown.
    signaling_state: fn(String) -> String,
    /// Send one string on the document channel. A `False` result means that
    /// the channel was not open, or that the browser refused the payload.
    send: fn(String, String) -> Bool,
    /// Remove every listener, close the channel and the connection, and
    /// remove the peer. A second call has no more effect.
    close: fn(String) -> Nil,
    /// A JSON description of the channel state and the connection state of the
    /// peer, for a status report, and for an assertion about the channel
    /// options against a real browser.
    diagnostics: fn(String) -> String,
  )
}

@target(javascript)
/// An opaque native registry of the peer connections. The FFI owns all of
/// it.
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
/// The native `RTCPeerConnection` backend. Each call returns a new registry, so
/// two transports on one page never share a connection.
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
    /// The value is `None` until `join` returns, and `None` again after
    /// `close`.
    session: Option(SignalingSession),
    rtc: Rtc,
    configuration: String,
    callbacks: Callbacks,
    peers: Dict(String, Peer),
    /// The signals that an adapter delivered synchronously from inside `join`,
    /// before that call returned the session that `send` needs. The transport
    /// applies them in arrival order, at the moment that it stores the
    /// session.
    pending_signals: List(Signal),
    closed: Bool,
  )
}

@target(javascript)
type Peer {
  Peer(
    id: String,
    /// The peer with the larger id yields in a collision. The offer of the peer
    /// with the smaller id thus always wins, and that offer is the only offer
    /// that either side must make.
    polite: Bool,
    /// The peer with the smaller id offers, and it creates the one data
    /// channel.
    offerer: Bool,
    /// Whether the transport reported `PeerConnecting` for this peer. A
    /// teardown thus knows whether it owes a `PeerClosed` status to the
    /// stream.
    announced: Bool,
    /// Whether the transport requested `open_channel`. The peer that offers
    /// creates its channel the first time that it observes the remote peer, by
    /// *any* route. This field prevents a second channel on a second
    /// observation.
    channel_requested: Bool,
    /// Whether this peer has ever sent an offer to this client. That offer
    /// carries its own data channel, which arrives in band. To create a channel
    /// here too would put two channels on the link.
    remote_offered: Bool,
    making_offer: Bool,
    /// The transport sets this flag when it drops an offer as an impolite
    /// collision, and the next accepted remote description clears it. While the
    /// flag is set, a failure to add a remote candidate is expected, and it is
    /// not an error. That candidate belongs to the description that the
    /// transport refused.
    ignore_offer: Bool,
    have_remote_description: Bool,
    /// The last remote offer that the transport applied. It can thus drop an
    /// exact duplicate, and it does not answer that offer two times.
    last_remote_offer: Option(String),
    /// The remote candidates that arrived before a remote description, oldest
    /// last. The transport reverses the list when it applies the queue, so it
    /// applies the candidates in arrival order.
    queued_candidates: List(String),
    open: Bool,
  )
}

@target(javascript)
/// The number of remote candidates that can wait for a remote description. A
/// peer that sends more than this number before it describes itself is flooding
/// the transport, and it is not negotiating.
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
/// Join a signaling room over real `RTCPeerConnection` objects.
///
/// `peer_id` is the session identity of this connection, and a collision
/// between two of them is very unlikely. That id is the signaling address and
/// the tie-break key, so two live members of a room must never share one.
/// `ice_servers` follows the `RTCConfiguration` behaviour of the browser, and
/// the list can be empty. An empty list is correct on a LAN, and for a
/// same-origin loopback.
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
/// `start` against a replacement browser seam. A test can thus drive the
/// negotiation, a collision, the candidate queue, and a failure
/// deterministically, and it needs no browser.
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
/// The local peer id of this transport.
pub fn local_peer_id(transport: Transport) -> String {
  transport_js.get_cell(transport.cell).peer_id
}

@target(javascript)
/// The room that this transport joined.
pub fn room(transport: Transport) -> String {
  transport_js.get_cell(transport.cell).room
}

@target(javascript)
/// The peers whose document data channel is open, sorted. This list is the
/// whole of the p2p presence.
pub fn open_peers(transport: Transport) -> List(String) {
  transport_js.get_cell(transport.cell).peers
  |> dict.values
  |> list.filter(fn(peer) { peer.open })
  |> list.map(fn(peer) { peer.id })
  |> list.sort(string.compare)
}

@target(javascript)
/// The number of peers that have an open document data channel.
pub fn open_peer_count(transport: Transport) -> Int {
  list.length(open_peers(transport))
}

@target(javascript)
/// Every peer that this transport tracks, open or still in a negotiation.
pub fn known_peers(transport: Transport) -> List(String) {
  transport_js.get_cell(transport.cell).peers
  |> dict.keys
  |> list.sort(string.compare)
}

@target(javascript)
/// Whether `close` ran.
pub fn is_closed(transport: Transport) -> Bool {
  transport_js.get_cell(transport.cell).closed
}

@target(javascript)
/// A JSON description of the channel state and the connection state of one
/// peer.
pub fn peer_diagnostics(transport: Transport, peer_id: String) -> String {
  let state = transport_js.get_cell(transport.cell)
  state.rtc.diagnostics(peer_id)
}

@target(javascript)
/// Send one encoded document message to one peer. A `False` result means that
/// the peer has no open channel. The caller decides whether that condition
/// needs a state exchange later, so this function returns a value and it
/// reports no error.
pub fn send(transport: Transport, peer_id: String, payload: String) -> Bool {
  let state = transport_js.get_cell(transport.cell)
  case state.closed, dict.get(state.peers, peer_id) {
    False, Ok(peer) if peer.open -> state.rtc.send(peer_id, payload)
    _, _ -> False
  }
}

@target(javascript)
/// Send one encoded document message to every open peer, and return the number
/// of peers that accepted it.
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
/// Close one peer. A second call has no more effect.
pub fn close_peer(transport: Transport, peer_id: String) -> Nil {
  teardown(transport.cell, peer_id, None)
}

@target(javascript)
/// Close every peer, release the browser objects that the transport holds, and
/// leave the signaling room exactly one time. A second call does nothing, and
/// the transport acts on no signal that arrives after it.
///
/// The transport releases everything that it owes to the outside world, which
/// is the browser objects and the signaling membership, *before* the first
/// application callback runs. An exception from a status callback or a peer
/// callback thus cannot leave a room joined or a connection open. That
/// exception still goes to the caller of `close`, and it skips the callbacks
/// after it. The transport is fully closed in both conditions.
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
/// The complete membership of the room. The transport tracks every member in
/// the same way as an announcement of one member at a time, and only then does
/// it report the roster. A caller that reads `known_peers` from the
/// `SignalingRoster` status thus sees the whole room, and an empty roster does
/// mean an empty room.
fn handle_roster(cell: Cell(State), peers: List(String)) -> Nil {
  list.each(peers, fn(peer_id) { handle_peer_joined(cell, peer_id) })
  emit(cell, SignalingRoster(peers))
}

@target(javascript)
/// Signaling failed after `join` returned. The transport reports a typed error
/// and does nothing more. An open data channel needs no signaling, so to close
/// the mesh here would destroy the connectivity that stayed.
fn signaling_failed(cell: Cell(State), detail: String) -> Nil {
  transport_js.get_cell(cell).callbacks.on_error(p2p.SignalingFailed(detail))
}

@target(javascript)
/// Track a peer and create its connection. When this client is the peer that
/// offers, also create the one data channel.
///
/// The function does not create a peer that it already tracks, and it still
/// checks the channel of that peer. An adapter can report a member that the
/// transport first met as an inbound signal, and it can report a member whose
/// `createDataChannel` call failed. Neither member can stay without the channel
/// that drives the negotiation.
///
/// The function checks the room limit first. The ninth member of a room gets no
/// `RTCPeerConnection`, and it gets a `RoomFull` error only.
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
/// Create the one document data channel for a peer that this client offers to,
/// if that peer has no channel yet.
///
/// The function is idempotent, and the route does not matter. The peer that
/// offers ends with exactly one channel, whichever event first made the remote
/// peer known. That event is a `PeerJoined` for a new peer, a `PeerJoined` for
/// a member that was already in the room, or a repeat of either one. The side
/// that answers receives the channel through `ondatachannel`.
///
/// The function does nothing for two kinds of peer. A peer that already offered
/// sends its own channel in band, so a second channel here would be one too
/// many. A peer whose channel is already open needs nothing.
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
/// Build the browser connection for a peer that the transport just started to
/// track, and report that peer as connecting. A `False` result means that the
/// construction of the peer failed.
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
/// Find a peer, or create one, and report whether the function created it. An
/// `Error(Nil)` result means that the peer must not exist. That occurs when the
/// peer is this client, when this transport is closed, and when the room is
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
/// Make sure that the peer which an inbound offer names exists, and record that
/// the peer offered.
///
/// A peer can arrive on this path in two ways: an offer that reached the
/// signaling service before its `PeerJoined` signal, and a member that no
/// adapter announced. Such a peer gets a connection, and it gets no data
/// channel from this client, whichever side it is. An offer carries the channel
/// of the peer that offers, and that channel arrives in band through
/// `ondatachannel`. To create a second channel here would put two channels on
/// one link. A `PeerJoined` signal that arrives after the offer also creates no
/// channel, for the same reason.
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
/// The collision guard of the perfect-negotiation algorithm.
///
/// A collision occurs when a remote offer arrives while this client has an
/// offer of its own outstanding. The impolite peer is the peer with the smaller
/// id, in lexicographic order, and that peer is also the only peer that must
/// offer. That peer refuses the remote offer, and it records that refusal, so
/// the candidates of the refused description can fail without a report. The
/// polite peer accepts the remote offer, and the browser rolls its own local
/// offer back as part of that step.
///
/// This rule also makes a duplicate offer and a reordered offer harmless. The
/// second copy arrives in a stable state, where to apply it again is a
/// renegotiation that changes nothing. Or it arrives in a collision, and the
/// same rule resolves it.
///
/// ponytail: this collision cannot occur between two *conforming* peers. The
/// deterministic assignment of the roles, where the peer with the smaller id is
/// the only peer that offers, already prevents two simultaneous offers. This
/// collision machinery stays as a protection against a peer that does not
/// conform and offers out of turn. You can delete it if the mesh ever checks
/// conformance at admission.
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
/// An answer has a meaning only against an outstanding local offer. The
/// function drops every other answer, which is a duplicate, a reordered copy,
/// and an answer to an offer that the browser rolled back. It does not give
/// such an answer to the browser. The browser would refuse it asynchronously,
/// and it would then report a failure that is not a failure.
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
/// A remote candidate has no use until a remote description exists, and the
/// browser refuses it before that point. Each candidate thus waits in a queue,
/// and the transport applies the queue in arrival order after a description
/// arrives.
///
/// The function drops a candidate for a peer that the transport does not know,
/// and it does not create that peer. A `PeerJoined` signal and an offer are the
/// two events that introduce a peer. A candidate that arrived before both of
/// them describes a connection that does not exist yet. To let that candidate
/// create a peer would also let a flooding peer return at the moment that its
/// flood closed it.
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
/// The document channel carries strings. Every other value comes from a peer
/// that uses a protocol that this transport does not have. The transport thus
/// reports that value and closes the peer, and it does not skip the value.
///
/// The function removes the peer before it sends the report. A foreign message
/// means that this connection is finished, and an `on_error` callback that
/// throws must not be able to keep that connection alive.
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
/// The transport reports the ICE state as a status. The `failed` state and the
/// `closed` state are terminal without a restart, so they also close the peer.
/// To keep such a peer in the peer set would report a mesh that is larger than
/// the real one.
///
/// A terminal state removes the peer before the transport emits the status, for
/// the same reason as a foreign message. The connection is over, whatever the
/// callback of the application does with the report.
///
/// The `disconnected` state is not terminal, and that is deliberate. The
/// browser recovers from it by itself, and to treat it as a loss would change
/// the presence on every short network fault.
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
/// Every asynchronous rejection from the browser arrives here, and it leaves as
/// a typed error that names the peer and the stage that failed.
///
/// A description stage that fails clears the negotiation flags that the attempt
/// set, and it clears them in every condition. Without that step,
/// `making_offer` would stay set after a rejected `setLocalDescription` call. A
/// peer whose `making_offer` flag stays set reads every later remote offer as a
/// collision. When that peer is the impolite side, it refuses every one of
/// them, and the link then never works again.
///
/// An answer stage that fails also removes the offer that it could not apply. A
/// second copy of that same offer thus gets an answer, and the transport does
/// not drop it as a duplicate.
///
/// A channel stage that fails removes the request. The transport thus tries the
/// channel again the next time that it observes the peer.
///
/// There is one exception to the report, and the perfect-negotiation algorithm
/// prescribes it. The browser cannot apply a candidate to a description that
/// this client refused. While `ignore_offer` is set, that one failure is
/// expected, and the transport does not report it. It reports every other
/// candidate failure.
///
/// Two stages are terminal, and they also close the peer. In the `open` stage
/// the transport never constructed a connection. In the `connection` stage the
/// browser declared that an established connection failed. The transport
/// reports every other stage and changes nothing. A description or a send can
/// fail while the link is still usable, and the facade decides whether to close
/// a peer, after it receives the error.
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
/// Remove the records that a failed stage left. The transport thus judges the
/// next signal against the real state of the connection, and not against an
/// attempt that never completed.
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
/// Run `action` only for a peer that this transport still tracks, and only on a
/// transport that is still open. A hook that runs for a peer that the transport
/// already closed is not an error. The browser can have a callback in flight
/// when `close` runs. There is simply nothing to do.
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
/// Remove one peer. The function removes the record first, then it closes the
/// browser objects, and then it reports. The order makes the function
/// idempotent under a re-entrant callback: a listener that runs while the
/// connection closes finds no peer, and it does nothing.
///
/// Every peer that the status stream announced as `PeerConnecting` gets a
/// `PeerClosed` status, whether or not it opened. A peer that fails during a
/// negotiation thus cannot leave a facade that renders it as connecting without
/// an end. The `on_peer_close` *callback* stays paired with `on_peer_open`, and
/// it runs only for a peer that opened.
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
/// The half of a teardown that must run before every application callback:
/// remove the peer and close its browser objects. A `None` result means that no
/// such peer existed, so the transport owes no report either.
///
/// This function is separate because two paths report the event *before* the
/// peer is gone. Those paths are a terminal ICE state and a foreign message. A
/// callback that throws there must not be able to leave a dead connection in
/// the peer set, where `broadcast` can address it and where it holds a place in
/// the room.
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
/// The reporting half of a teardown, for a peer that `drop_peer` already
/// removed.
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
