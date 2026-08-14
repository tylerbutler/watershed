//// The reference signaling protocol: a closed frame vocabulary and the
//// pure room registry a service runs it with.
////
//// A signaling service exists to introduce peers to each other and to
//// carry three kinds of opaque WebRTC blob between them. It is not part
//// of the document, and this module is what makes that structural rather
//// than a promise: `ClientFrame` has exactly three constructors, its
//// signal payload is `p2p_transport_js.SignalPayload` — the same closed
//// sum the transport speaks, `Offer | Answer | Candidate` — and the
//// decoder is total. There is no frame shape that carries a
//// `crdt_wire.Envelope`, so a document delta cannot be routed by a
//// service built on this, however the service is written. A peer that
//// sends one gets a `Rejected` and a closed socket.
////
//// `Rooms` is a pure state machine. `handle_frame` and `disconnect` take
//// a registry and a connection id and return a new registry plus the
//// `Action`s a service should perform; nothing here opens a socket,
//// writes a log, or reads a clock. That is what lets the room cap,
//// duplicate-id rejection, cross-room targeting, and every rejection
//// path be tested without a server.
////
//// What the service built on it must satisfy — the transport's discovery
//// contract — is that the smaller of any two peer ids learns about the
//// larger. `Joined` tells a newcomer every existing member and
//// `PeerJoined` tells every existing member about the newcomer, so both
//// directions are covered and the contract holds for every pair.
////
//// JavaScript target only: it shares the transport's payload type, and
//// the reference service runs on Node.

@target(javascript)
import gleam/bit_array
@target(javascript)
import gleam/dict.{type Dict}
@target(javascript)
import gleam/dynamic/decode.{type Decoder}
@target(javascript)
import gleam/int
@target(javascript)
import gleam/json.{type Json}
@target(javascript)
import gleam/list
@target(javascript)
import gleam/result
@target(javascript)
import gleam/string

@target(javascript)
import watershed/crdt_wire
@target(javascript)
import watershed/p2p_transport_js.{type SignalPayload, Answer, Candidate, Offer}

// ─────────────────────────────────────────────────────────────────────────────
// Limits
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// Peers allowed in one room, read from the core protocol limits so the
/// service, the transport, and the wire cannot disagree.
pub fn room_limit() -> Int {
  crdt_wire.default_limits().room_peers
}

@target(javascript)
/// The largest signaling frame accepted, in bytes.
///
/// An SDP offer with a handful of candidates is a few kilobytes; this is
/// generous for that and far below the 256 KiB a document envelope may
/// be, so the size guard alone already refuses anything document-shaped
/// before it is parsed.
pub const max_frame_bytes = 16_384

@target(javascript)
/// The longest accepted room or peer id, **in UTF-8 bytes**. Both are
/// echoed to other peers, so an unbounded one is an amplification vector
/// — and what is echoed is bytes, not graphemes: one emoji is four of
/// these, and a grapheme count would admit a frame four times the size it
/// promised.
pub const max_id_bytes = 128

// ─────────────────────────────────────────────────────────────────────────────
// Frames
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// Everything a client may say. Three constructors, and the only payload
/// is the transport's own closed signal sum.
pub type ClientFrame {
  Join(room: String, peer: String)
  Signal(to: String, payload: SignalPayload)
  Leave
}

@target(javascript)
/// Everything a service may say back.
pub type ServerFrame {
  /// Admission, with the room's existing members.
  Joined(room: String, peer: String, peers: List(String))
  PeerJoined(peer: String)
  PeerLeft(peer: String)
  Forwarded(from: String, payload: SignalPayload)
  /// A refusal that ends the connection. `reason` is a stable machine
  /// tag; `detail` is prose.
  Rejected(reason: String, detail: String)
  /// One frame could not be delivered, and the connection is fine. The
  /// only thing that produces it is a signal addressed to a peer that is
  /// no longer in the room — a candidate that lost a race with a leave —
  /// which is ordinary in a mesh and not a protocol violation.
  Dropped(reason: String, detail: String)
}

@target(javascript)
/// What a service should do after a frame. Connections are named by the
/// integer id the service assigned them, so the state machine never
/// holds a socket.
pub type Action {
  Send(connection: Int, frame: ServerFrame)
  /// Close a connection after any `Send` already emitted for it.
  Close(connection: Int, reason: String)
}

@target(javascript)
/// Why a frame was refused.
///
/// Most of these are protocol violations: the connection is told why and
/// then closed, and the room registry is left exactly as it was.
/// `UnknownTarget` is the exception — see `is_terminal`.
pub type Refusal {
  FrameTooLarge(bytes: Int)
  Malformed(detail: String)
  NotJoined
  AlreadyJoined
  DuplicatePeerId(peer: String)
  RoomFull(limit: Int)
  /// A signal addressed to a peer that is in *another* room. Rooms are
  /// the whole of the addressing, so naming across one is a violation.
  CrossRoomTarget(peer: String)
  /// A signal addressed to a peer that is in no room at all. Almost
  /// always a peer that left between the sender deciding to write and the
  /// frame arriving, which is a race every mesh runs constantly.
  UnknownTarget(peer: String)
  InvalidId(detail: String)
}

@target(javascript)
/// Whether a refusal ends the connection.
///
/// Everything a peer can be *wrong* about does: a malformed or oversize
/// frame, signalling before joining, a duplicate id, a full room, a
/// target in another room. A target that has simply gone is not one of
/// them — closing the sender for it would mean any peer could take
/// another down by leaving at the wrong moment, and the `peerLeft` that
/// explains it is already on its way.
pub fn is_terminal(refusal: Refusal) -> Bool {
  case refusal {
    UnknownTarget(_) -> False
    _ -> True
  }
}

@target(javascript)
pub fn refusal_parts(refusal: Refusal) -> #(String, String) {
  case refusal {
    FrameTooLarge(bytes) -> #(
      "frameTooLarge",
      int.to_string(bytes) <> " bytes, limit " <> int.to_string(max_frame_bytes),
    )
    Malformed(detail) -> #("malformed", detail)
    NotJoined -> #("notJoined", "join before signalling")
    AlreadyJoined -> #("alreadyJoined", "this connection has already joined")
    DuplicatePeerId(peer) -> #("duplicatePeerId", peer)
    RoomFull(limit) -> #("roomFull", int.to_string(limit))
    CrossRoomTarget(peer) -> #("crossRoomTarget", peer)
    UnknownTarget(peer) -> #("unknownTarget", peer)
    InvalidId(detail) -> #("invalidId", detail)
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Encoding
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn encode_client(frame: ClientFrame) -> Json {
  case frame {
    Join(room, peer) ->
      json.object([
        #("t", json.string("join")),
        #("room", json.string(room)),
        #("peer", json.string(peer)),
      ])
    Signal(to, payload) ->
      json.object([
        #("t", json.string("signal")),
        #("to", json.string(to)),
        #("payload", encode_payload(payload)),
      ])
    Leave -> json.object([#("t", json.string("leave"))])
  }
}

@target(javascript)
pub fn client_to_string(frame: ClientFrame) -> String {
  json.to_string(encode_client(frame))
}

@target(javascript)
pub fn encode_server(frame: ServerFrame) -> Json {
  case frame {
    Joined(room, peer, peers) ->
      json.object([
        #("t", json.string("joined")),
        #("room", json.string(room)),
        #("peer", json.string(peer)),
        #("peers", json.array(peers, json.string)),
      ])
    PeerJoined(peer) ->
      json.object([
        #("t", json.string("peerJoined")),
        #("peer", json.string(peer)),
      ])
    PeerLeft(peer) ->
      json.object([
        #("t", json.string("peerLeft")),
        #("peer", json.string(peer)),
      ])
    Forwarded(from, payload) ->
      json.object([
        #("t", json.string("signal")),
        #("from", json.string(from)),
        #("payload", encode_payload(payload)),
      ])
    Rejected(reason, detail) ->
      json.object([
        #("t", json.string("error")),
        #("reason", json.string(reason)),
        #("detail", json.string(detail)),
      ])
    Dropped(reason, detail) ->
      json.object([
        #("t", json.string("dropped")),
        #("reason", json.string(reason)),
        #("detail", json.string(detail)),
      ])
  }
}

@target(javascript)
pub fn server_to_string(frame: ServerFrame) -> String {
  json.to_string(encode_server(frame))
}

@target(javascript)
fn encode_payload(payload: SignalPayload) -> Json {
  case payload {
    Offer(sdp) ->
      json.object([#("t", json.string("offer")), #("sdp", json.string(sdp))])
    Answer(sdp) ->
      json.object([#("t", json.string("answer")), #("sdp", json.string(sdp))])
    Candidate(candidate) ->
      json.object([
        #("t", json.string("candidate")),
        #("candidate", json.string(candidate)),
      ])
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Decoding — the trust boundary
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// Decode a client frame. Total: size first, then JSON, then the closed
/// tag set. Anything else — including every shape a `crdt_wire.Envelope`
/// can take — is a `Refusal`, never a routed frame.
pub fn decode_client(raw: String) -> Result(ClientFrame, Refusal) {
  use _ <- result.try(check_size(raw))
  use frame <- result.try(
    json.parse(raw, client_decoder())
    |> result.replace_error(Malformed("not a signaling frame")),
  )
  validate_client(frame)
}

@target(javascript)
/// Decode a server frame, for the browser adapter.
pub fn decode_server(raw: String) -> Result(ServerFrame, Refusal) {
  use _ <- result.try(check_size(raw))
  json.parse(raw, server_decoder())
  |> result.replace_error(Malformed("not a signaling frame"))
}

@target(javascript)
fn check_size(raw: String) -> Result(Nil, Refusal) {
  let bytes = bit_array.byte_size(<<raw:utf8>>)
  case bytes > max_frame_bytes {
    True -> Error(FrameTooLarge(bytes))
    False -> Ok(Nil)
  }
}

@target(javascript)
fn client_decoder() -> Decoder(ClientFrame) {
  use tag <- decode.field("t", decode.string)
  case tag {
    "join" -> {
      use room <- decode.field("room", decode.string)
      use peer <- decode.field("peer", decode.string)
      decode.success(Join(room, peer))
    }
    "signal" -> {
      use to <- decode.field("to", decode.string)
      use payload <- decode.field("payload", payload_decoder())
      decode.success(Signal(to, payload))
    }
    "leave" -> decode.success(Leave)
    _ -> decode.failure(Leave, "signaling frame")
  }
}

@target(javascript)
fn server_decoder() -> Decoder(ServerFrame) {
  use tag <- decode.field("t", decode.string)
  case tag {
    "joined" -> {
      use room <- decode.field("room", decode.string)
      use peer <- decode.field("peer", decode.string)
      use peers <- decode.field("peers", decode.list(decode.string))
      decode.success(Joined(room, peer, peers))
    }
    "peerJoined" -> {
      use peer <- decode.field("peer", decode.string)
      decode.success(PeerJoined(peer))
    }
    "peerLeft" -> {
      use peer <- decode.field("peer", decode.string)
      decode.success(PeerLeft(peer))
    }
    "signal" -> {
      use from <- decode.field("from", decode.string)
      use payload <- decode.field("payload", payload_decoder())
      decode.success(Forwarded(from, payload))
    }
    "error" -> {
      use reason <- decode.field("reason", decode.string)
      use detail <- decode.field("detail", decode.string)
      decode.success(Rejected(reason, detail))
    }
    "dropped" -> {
      use reason <- decode.field("reason", decode.string)
      use detail <- decode.field("detail", decode.string)
      decode.success(Dropped(reason, detail))
    }
    _ -> decode.failure(PeerLeft(""), "signaling frame")
  }
}

@target(javascript)
fn payload_decoder() -> Decoder(SignalPayload) {
  use tag <- decode.field("t", decode.string)
  case tag {
    "offer" -> {
      use sdp <- decode.field("sdp", decode.string)
      decode.success(Offer(sdp))
    }
    "answer" -> {
      use sdp <- decode.field("sdp", decode.string)
      decode.success(Answer(sdp))
    }
    "candidate" -> {
      use candidate <- decode.field("candidate", decode.string)
      decode.success(Candidate(candidate))
    }
    _ -> decode.failure(Candidate(""), "signal payload")
  }
}

@target(javascript)
fn validate_client(frame: ClientFrame) -> Result(ClientFrame, Refusal) {
  case frame {
    Join(room, peer) -> {
      use _ <- result.try(valid_id(room, "room"))
      use _ <- result.try(valid_id(peer, "peer"))
      Ok(frame)
    }
    Signal(to, _) -> {
      use _ <- result.try(valid_id(to, "target"))
      Ok(frame)
    }
    Leave -> Ok(frame)
  }
}

@target(javascript)
fn valid_id(value: String, what: String) -> Result(Nil, Refusal) {
  case value == "", bit_array.byte_size(<<value:utf8>>) > max_id_bytes {
    True, _ -> Error(InvalidId(what <> " id is empty"))
    _, True ->
      Error(InvalidId(
        what <> " id is longer than " <> int.to_string(max_id_bytes) <> " bytes",
      ))
    _, _ -> Ok(Nil)
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The room registry
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// Every room and every connection in them. Purely a membership table:
/// it holds ids, never payloads.
pub opaque type Rooms {
  Rooms(
    /// Room name to the peer ids in it, each with the connection that
    /// owns it.
    rooms: Dict(String, Dict(String, Int)),
    /// Connection to the room and peer id it joined as.
    members: Dict(Int, #(String, String)),
    /// How many rooms hold each peer id. Ids are unique within a room and
    /// not across them, so this is a count rather than a room name — and
    /// it is what makes "is this target in *another* room?" a lookup
    /// instead of a scan of every room on the service, on a path a peer
    /// can now repeat without being closed.
    occupancy: Dict(String, Int),
  )
}

@target(javascript)
pub fn new_rooms() -> Rooms {
  Rooms(rooms: dict.new(), members: dict.new(), occupancy: dict.new())
}

@target(javascript)
/// Peer ids in a room, sorted.
pub fn members(rooms: Rooms, room: String) -> List(String) {
  case dict.get(rooms.rooms, room) {
    Ok(peers) -> dict.keys(peers) |> list.sort(string.compare)
    Error(Nil) -> []
  }
}

@target(javascript)
/// Room names currently held, sorted. An emptied room is deleted, so a
/// room that appears here has at least one member.
pub fn room_names(rooms: Rooms) -> List(String) {
  dict.keys(rooms.rooms) |> list.sort(string.compare)
}

@target(javascript)
/// The room and peer id a connection joined as.
pub fn membership(
  rooms: Rooms,
  connection: Int,
) -> Result(#(String, String), Nil) {
  dict.get(rooms.members, connection)
}

@target(javascript)
/// Apply one raw frame from one connection.
///
/// Every rejection is the same shape — tell the peer why, then close it
/// — and none of them mutates the registry, so a hostile connection
/// cannot disturb the room it was refused from.
pub fn handle_frame(
  rooms: Rooms,
  connection: Int,
  raw: String,
) -> #(Rooms, List(Action)) {
  case decode_client(raw) {
    Error(refusal) -> #(rooms, refuse(connection, refusal))
    Ok(frame) -> {
      let #(rooms, actions, _outcome) = apply_frame(rooms, connection, frame)
      #(rooms, actions)
    }
  }
}

@target(javascript)
/// Apply one decoded frame, carrying out whether the registry refused it.
///
/// The refusal is carried out rather than inferred from the actions,
/// because a service's instrumentation has to be able to tell a routed
/// `signal` from one that was refused without inspecting either — and
/// looking at what came back would mean reading frames it must not read.
fn apply_frame(
  rooms: Rooms,
  connection: Int,
  frame: ClientFrame,
) -> #(Rooms, List(Action), Result(Nil, Refusal)) {
  case frame, dict.get(rooms.members, connection) {
    Join(_, _), Ok(_) -> refused(rooms, connection, AlreadyJoined)
    Join(room, peer), Error(Nil) -> join(rooms, connection, room, peer)
    Signal(_, _), Error(Nil) -> refused(rooms, connection, NotJoined)
    Signal(to, payload), Ok(#(room, peer)) ->
      forward(rooms, connection, room, peer, to, payload)
    Leave, Error(Nil) -> #(rooms, [], Ok(Nil))
    Leave, Ok(_) -> {
      let #(rooms, actions) = disconnect(rooms, connection)
      #(rooms, actions, Ok(Nil))
    }
  }
}

@target(javascript)
fn join(
  rooms: Rooms,
  connection: Int,
  room: String,
  peer: String,
) -> #(Rooms, List(Action), Result(Nil, Refusal)) {
  let occupants = case dict.get(rooms.rooms, room) {
    Ok(peers) -> peers
    Error(Nil) -> dict.new()
  }
  case dict.has_key(occupants, peer), dict.size(occupants) >= room_limit() {
    True, _ -> refused(rooms, connection, DuplicatePeerId(peer))
    _, True -> refused(rooms, connection, RoomFull(room_limit()))
    _, _ -> {
      let existing = dict.keys(occupants) |> list.sort(string.compare)
      let rooms =
        Rooms(
          rooms: dict.insert(
            rooms.rooms,
            room,
            dict.insert(occupants, peer, connection),
          ),
          members: dict.insert(rooms.members, connection, #(room, peer)),
          occupancy: adjust(rooms.occupancy, peer, 1),
        )
      // Both directions of the discovery contract: the newcomer learns
      // the room, the room learns the newcomer.
      let announcements =
        dict.to_list(occupants)
        |> list.sort(fn(left, right) { string.compare(left.0, right.0) })
        |> list.map(fn(entry) { Send(entry.1, PeerJoined(peer)) })
      #(
        rooms,
        [
          Send(connection, Joined(room: room, peer: peer, peers: existing)),
          ..announcements
        ],
        Ok(Nil),
      )
    }
  }
}

@target(javascript)
/// Route one opaque payload to one named peer in the sender's own room.
///
/// Two ways to miss, and they are not the same mistake. A target that is
/// a member of some other room is a peer naming across a room boundary,
/// which is a violation and closes it. A target that is in no room at all
/// is a peer that left mid-negotiation: the frame is dropped, the sender
/// is told so, and its membership is untouched.
fn forward(
  rooms: Rooms,
  connection: Int,
  room: String,
  peer: String,
  to: String,
  payload: SignalPayload,
) -> #(Rooms, List(Action), Result(Nil, Refusal)) {
  let occupants = case dict.get(rooms.rooms, room) {
    Ok(occupants) -> occupants
    Error(Nil) -> dict.new()
  }
  case dict.get(occupants, to) {
    Ok(target) -> #(rooms, [Send(target, Forwarded(peer, payload))], Ok(Nil))
    Error(Nil) ->
      case elsewhere(rooms, room, to) {
        True -> refused(rooms, connection, CrossRoomTarget(to))
        False -> refused(rooms, connection, UnknownTarget(to))
      }
  }
}

@target(javascript)
/// Whether `peer` is a member of any room other than `room`. Only ever
/// asked about a peer the sender's own room does not hold, so any
/// occupancy at all is occupancy somewhere else.
fn elsewhere(rooms: Rooms, room: String, peer: String) -> Bool {
  let here = case dict.get(rooms.rooms, room) {
    Ok(occupants) -> dict.has_key(occupants, peer)
    Error(Nil) -> False
  }
  case here, dict.get(rooms.occupancy, peer) {
    True, _ -> False
    False, Ok(count) -> count > 0
    False, Error(Nil) -> False
  }
}

@target(javascript)
/// Move a peer id's room count by `delta`, dropping it at zero so the
/// index holds only ids that are somewhere.
fn adjust(
  occupancy: Dict(String, Int),
  peer: String,
  delta: Int,
) -> Dict(String, Int) {
  let count = case dict.get(occupancy, peer) {
    Ok(count) -> count
    Error(Nil) -> 0
  }
  case count + delta {
    total if total <= 0 -> dict.delete(occupancy, peer)
    total -> dict.insert(occupancy, peer, total)
  }
}

@target(javascript)
/// Remove a connection, tell its room, and delete the room when it
/// empties. Idempotent: a connection that is not a member produces no
/// actions.
pub fn disconnect(rooms: Rooms, connection: Int) -> #(Rooms, List(Action)) {
  case dict.get(rooms.members, connection) {
    Error(Nil) -> #(rooms, [])
    Ok(#(room, peer)) -> {
      let occupants = case dict.get(rooms.rooms, room) {
        Ok(peers) -> dict.delete(peers, peer)
        Error(Nil) -> dict.new()
      }
      let rooms =
        Rooms(
          rooms: case dict.size(occupants) {
            0 -> dict.delete(rooms.rooms, room)
            _ -> dict.insert(rooms.rooms, room, occupants)
          },
          members: dict.delete(rooms.members, connection),
          occupancy: adjust(rooms.occupancy, peer, -1),
        )
      let notices =
        dict.to_list(occupants)
        |> list.sort(fn(left, right) { string.compare(left.0, right.0) })
        |> list.map(fn(entry) { Send(entry.1, PeerLeft(peer)) })
      #(rooms, notices)
    }
  }
}

@target(javascript)
/// A refusal: tell the connection why, close it if the refusal is
/// terminal, and leave the registry exactly as it was.
fn refused(
  rooms: Rooms,
  connection: Int,
  refusal: Refusal,
) -> #(Rooms, List(Action), Result(Nil, Refusal)) {
  #(rooms, refuse(connection, refusal), Error(refusal))
}

@target(javascript)
fn refuse(connection: Int, refusal: Refusal) -> List(Action) {
  let #(reason, detail) = refusal_parts(refusal)
  case is_terminal(refusal) {
    True -> [
      Send(connection, Rejected(reason, detail)),
      Close(connection, reason),
    ]
    False -> [Send(connection, Dropped(reason, detail))]
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The service seam
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// `handle_frame` in the shape a JavaScript service can consume without
/// touching a single Gleam value: the new registry, the actions rendered
/// by `render_actions`, and the tag the frame classified as.
///
/// The tag is the whole of a service's instrumentation: `join`,
/// `signal`, `leave`, `rejected:<reason>`, or `dropped:<reason>`. It is
/// derived from the frame's own type and from whether the protocol
/// refused it, never from its contents, so counting frames does not
/// require looking inside one. Every refusal is tagged — the decoder's
/// and the registry's alike — so a room that is quietly turning peers
/// away cannot look like healthy traffic. `dropped:` is kept apart from
/// `rejected:` because the one refusal that does not close a connection
/// is also the one that is nobody's fault: a signal to a peer that left.
/// A document envelope is `rejected:malformed`, which is how a test
/// proves none arrived.
pub fn serve(
  rooms: Rooms,
  connection: Int,
  raw: String,
) -> #(Rooms, List(#(Int, String, String)), String) {
  case decode_client(raw) {
    Error(refusal) -> #(
      rooms,
      render_actions(refuse(connection, refusal)),
      refusal_tag(refusal),
    )
    Ok(frame) -> {
      let #(rooms, actions, outcome) = apply_frame(rooms, connection, frame)
      let tag = case outcome {
        Ok(Nil) -> frame_tag(frame)
        Error(refusal) -> refusal_tag(refusal)
      }
      #(rooms, render_actions(actions), tag)
    }
  }
}

@target(javascript)
fn refusal_tag(refusal: Refusal) -> String {
  let prefix = case is_terminal(refusal) {
    True -> "rejected:"
    False -> "dropped:"
  }
  prefix <> refusal_parts(refusal).0
}

@target(javascript)
/// Actions as `#(connection, payload, close_reason)`. A `Send` carries
/// its encoded frame and an empty close reason; a `Close` carries an
/// empty payload and its reason. Order is preserved, so a refusal's
/// `Rejected` is always written before its `Close`.
pub fn render_actions(actions: List(Action)) -> List(#(Int, String, String)) {
  list.map(actions, fn(action) {
    case action {
      Send(connection, frame) -> #(connection, server_to_string(frame), "")
      Close(connection, reason) -> #(connection, "", reason)
    }
  })
}

@target(javascript)
fn frame_tag(frame: ClientFrame) -> String {
  case frame {
    Join(_, _) -> "join"
    Signal(_, _) -> "signal"
    Leave -> "leave"
  }
}
