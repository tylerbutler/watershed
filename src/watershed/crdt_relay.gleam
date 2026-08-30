//// The `crdt_relay_v1` protocol: the lane an optional sequencer opens
//// for CRDT documents, and the pure room state machine a relay runs it
//// with.
////
//// A relay is a durable fan-out point. It is not a sequencer for these
//// documents. It stamps a diagnostic order, it keeps a log that it can replay,
//// it broadcasts what it accepts, and it answers a `stateRequest` from what it
//// holds. It never merges, it never decides which of two replicas is correct,
//// and it never reads inside a kernel payload. A `crdt_wire.Envelope` value
//// arrives at this module as an opaque string, and it leaves as the same
//// string, byte for byte. The module reads the preamble of the envelope only,
//// which is the protocol version, the room, the sender, the session, and the
//// `type` tag of the message. Admission and the list of accepted types need
//// exactly those five fields, and nothing more.
////
//// ## The lane
////
//// One WebSocket, opened per document, distinct from any signaling lane
//// and from any legacy sequenced document lane. The relay speaks first:
////
//// ```json
//// {"type": "connected", "capabilities": {"crdt_relay_v1": true}}
//// ```
////
//// A client that does not receive `crdt_relay_v1` treats the endpoint as a
//// relay that it cannot use. That is the whole capability negotiation.
////
//// After that, the client writes **bare encoded envelope strings** on the
//// document side, and nothing else. Those strings are `hello`, `channel`,
//// `delta`, `stateRequest`, `state`, and `digest`. The relay writes back:
////
//// ```json
//// {"type": "frame",    "order": 12, "envelope": "<the same string>"}
//// {"type": "attested", "order": 13, "digest": "<echo, or empty>"}
//// {"type": "error",    "reason": "...", "detail": "..."}
//// ```
////
//// `order` is a diagnostic value. It is outside the envelope, no code writes
//// it into one, and a client passes it to nothing. The kernels, the message
//// ids, the digests, and the events are all computed as if that value did not
//// exist.
////
//// ## Attestation, and why the client sends one extra frame
////
//// A relay that cannot merge cannot know whether the state that it holds is
//// the join of everything that it received. A client can know that. It merges
//// every entry that the relay replays, it publishes the merged result, and it
//// then reports what that result covers.
////
//// ```json
//// {"type": "attest", "digest": "<local digest>", "upTo": 12}
//// ```
////
//// `upTo` is the highest `order` value that the client *accounted for*, which
//// means that it merged that entry into the state that it just published, or
//// that it reported that entry as skipped, as described below. Only the client
//// holds that fact. The relay knows what it sent, and it does not know what the
//// client made of it.
////
//// **This is an attestation by a trusted client, and it is not a proof.** A
//// relay that never merges cannot check the attestation, and it does not try.
//// It accepts the statement of the client that the published state *claims to
//// contain* the entries at `upTo` or below it, and it retires those log entries
//// on that statement. Arithmetic does not make that safe. The trust boundary
//// makes it safe: **admission and authentication are the trust boundary of the
//// checkpoint**. A deployment that admits a client decides that the client can
//// move the log point of the room. The admission rules of the reference service
//// are limited examples, and they are not a security model. A real deployment
//// substitutes its own authentication and keeps every other part of this
//// module.
////
//// The module keeps every mechanical protection that it *can* keep. It clamps
//// `upTo` to the orders that it sent to this connection. A connection can speak
//// for its own room and its own session only. And no attestation ever deletes a
//// record that its author reported as unreadable.
////
//// After the relay retires the entries, it compares what remains. If that
//// remainder is exactly the published state with the entries that this client
//// reported as unreadable, then the content of the relay and the content of the
//// client are the same document, with a remainder that neither of them
//// discarded. The relay then echoes the digest back. Every other condition, for
//// example a concurrent state or a delta that raced the publication, leaves the
//// log complete and the echo empty. The client then merges what it missed and
//// tries again.
////
//// This design keeps two rules from a contradiction: "never select a winning
//// replica" and "checkpoint the canonical state". Two clients that attach at the
//// same time publish two different states. The relay logs both, it broadcasts
//// both, and it refuses neither. The log becomes one entry only after an
//// admitted client claims that the one entry contains the others.
////
//// ## Refusals, and why a client may skip
////
//// A relay accepts an envelope on its preamble alone, so it can hold an
//// envelope that no client will ever merge. Three examples: a delta for a
//// channel type that this build does not have, a frame from a replica whose
//// address does not name that replica, and a body that is correct JSON and has
//// no meaning to a kernel. Nothing on the relay can detect those conditions. A
//// client that stopped counting at such an entry could never attest again, and
//// that would stop the log, the checkpoint, and every `SequencedOnly` replica
//// in the room.
////
//// ```json
//// {"type": "skip", "order": 7}
//// ```
////
//// The client thus reports the exact order that it refused. The relay checks
//// that claim against the orders that it *sent that connection*, it records the
//// claim against that connection only, and it lets the next checkpoint of that
//// client proceed **without a delete of the entry**. The relay writes a skipped
//// record into the compaction beside the checkpoint, in order, and it replays
//// that record to every client afterwards, exactly as it was.
////
//// A skip means "this state does not contain that entry". That statement is a
//// reason to carry the entry, and not permission to drop it. A client that
//// cannot read something, and a client that reports a false claim, thus can
//// never make the history of the room shorter. The entry goes away when a
//// client that *did* merge it publishes a state that covers it, and that client
//// has no skip of its own to keep the entry alive.
////
//// The relay ignores a skip for an order that it never sent to that connection.
//// Such a claim can only come from a relay that stamped something that it did
//// not account for, and there is nothing to carry. The rule "a client cannot
//// decide the fate of an entry that it never saw" thus holds in both
//// directions.
////
//// ## The hard log bound
////
//// The live log of a room stops growing at `max_room_records`. Before the log
//// reaches that bound, the relay asks the attached clients that declared
//// support to checkpoint, with a `CheckpointRequest` frame. At the bound, the
//// relay still admits one frame: a `state` frame from a client that declared
//// support, which is the answer that compacts the room. It refuses every other
//// durable frame with `roomAtCapacity`, and it closes the sender of that frame.
//// The room thus bounds a flood from an admitted client. The other half of that
//// protection, which separates an attacker from a customer, belongs to the
//// deployment that admitted the client, and not to this module.
////
//// ## Durability
////
//// A `Storage` action is an append-only JSONL line, or a rewrite of a whole
//// file. The module emits a compaction only *after* the append that carries the
//// checkpoint that the compaction keeps. The data is thus durable in its new
//// position before the old position can go away. `replay` rebuilds a room from
//// its lines, and that function makes a restart of a relay a merge, and not a
//// loss of data.

import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/set
import gleam/string

import watershed/crdt_wire

/// The capability that a relay must announce before a client can use it. An
/// endpoint that omits it is a sequencer without this lane. In `Auto` mode that
/// condition is a status, and it is not a failure.
pub const capability = "crdt_relay_v1"

/// The largest frame that the module accepts, in bytes, in both directions of
/// the lane. This is the same limit as the CRDT envelope itself. A frame that
/// could never hold a valid envelope is thus refused before the module parses
/// it.
pub fn max_frame_bytes() -> Int {
  crdt_wire.default_limits().envelope_bytes
}

/// The number of clients that one room admits. A relay is not a mesh. It fans
/// out, and it does not connect every client to every other client. This limit
/// is thus much higher than the room limit of WebRTC. It exists to bound the
/// memory, and not to control a topology.
pub const max_room_clients = 32

/// The longest accepted room name, in UTF-8 bytes.
pub const max_room_bytes = 128

/// The longest session identifier that the module accepts, in UTF-8 bytes. A
/// client supplies the session, the relay holds it for the life of a
/// connection, and the relay writes it into every durable record. It thus has a
/// limit, for the same reason as a room name.
pub const max_session_bytes = 128

/// The largest number of skipped orders that one connection can hold at one
/// time. The relay removes from that list every order that the log of the room
/// no longer holds, and it does that every time a skip arrives and every time a
/// checkpoint lands. `max_room_records` also bounds the log itself. This value
/// is thus a backstop, and it is not a rule that a connection must meet. It is
/// `max_room_records` or more, so a client that refuses *every* entry in a
/// completely full room still does not get a closed connection for the number
/// of its claims.
///
/// It is still a real operational limit. The relay closes a connection that
/// reports more live skips than this number, with the reason `tooManySkips`,
/// and that client must connect again.
pub const max_client_skips = 1024

/// The hard bound on the *active log* of a room. The relay applies it **before**
/// an append, and not after one.
///
/// An admitted client that is alone in a room can write correct records, and no
/// other client is there to refuse them. 100 000 such records are 100 000 lines
/// on disk and 100 000 entries in the heap of this process, and the relay
/// replays all of them to the next client that attaches. The live log of a room
/// thus stops growing at this bound.
///
/// Before the log reaches the bound, the relay asks the compatible clients to
/// checkpoint. See `checkpoint_pressure_records`. If the log still reaches the
/// bound, the relay refuses the *sender* of the frame that would cross it, with
/// the reason `roomAtCapacity`, and it closes that connection. The relay
/// changes nothing that is already durable. A refusal at the bound writes
/// nothing and deletes nothing.
pub const max_room_records = 1024

/// The log size at which a room starts to ask for a checkpoint, instead of a
/// wait until it must refuse one. The value is three quarters of
/// `max_room_records`.
///
/// A room that reaches its hard bound with a correct client attached is a fault
/// of this repository, and not of that client. An ordinary editing session that
/// passes the bound must not stop in the middle of the work. At this mark the
/// relay thus sends a `CheckpointRequest` frame to every attached client that
/// declared that it understands one. A correct client answers with a
/// publication of its merged state and an attestation of that state, and the
/// relay then compacts the ordinary valid history of the room down to that one
/// record. The last quarter is the space in which the client can answer that
/// request.
pub const checkpoint_pressure_records = 768

/// The growth in the log of a room before that room asks again.
///
/// A request is idempotent for each connection: a client with one outstanding
/// request does not get a second one. The relay arms the request again only
/// after the log grows by this amount. A room under pressure thus sends
/// `(max_room_records - checkpoint_pressure_records) /
/// checkpoint_request_interval` rounds at most, before it starts to refuse. An
/// attacker thus cannot use a client that ignores those requests to generate
/// traffic.
pub const checkpoint_request_interval = 64

// ─────────────────────────────────────────────────────────────────────────────
// Frames
// ─────────────────────────────────────────────────────────────────────────────

/// Everything that a relay can send. The document traffic is in `Frame`, as the
/// encoded envelope of the sender. Every other constructor is a control frame,
/// and it carries no document data at all.
pub type ServerFrame {
  /// The greeting, which the relay writes at the moment that a socket opens.
  /// `supports` reports whether that greeting announced the capability of this
  /// lane. The wire carries an object of capabilities, and this client reads
  /// exactly one entry from that object. One `Bool` value thus survives the
  /// decode.
  Connected(supports: Bool, envelope_bytes: Int)
  /// One relayed envelope, with the diagnostic order outside it.
  Frame(order: Int, envelope: String)
  /// The end of the group of frames that a `stateRequest` produced. Without
  /// this frame, a client cannot separate "the relay replayed everything that
  /// it holds" from "the next entry has not arrived yet", and it would have to
  /// guess the moment at which to publish its merged state.
  Synced(order: Int)
  /// The answer to an `attest` frame. The value is the digest of the client,
  /// echoed back, when the content of the relay is exactly the state that the
  /// client published. It is the empty string in every other condition.
  Attested(order: Int, digest: String)
  /// A request to publish the merged state of the client and to attest it.
  ///
  /// The relay sends this frame to a connection that declared that it
  /// understands one. See `Supports`. It sends the frame only after the live
  /// log of a room passes `checkpoint_pressure_records`, and one time for each
  /// connection, until that connection publishes a `state` frame or the log
  /// grows by another `checkpoint_request_interval`.
  ///
  /// The frame carries nothing at all: no order, no digest, and no envelope. A
  /// client answers it from its *own* state, so nothing that a relay stamped
  /// can enter a document through this frame.
  CheckpointRequest
  /// A refusal. This frame is terminal, and the relay closes the connection
  /// after it.
  Refused(reason: String, detail: String)
}

/// Everything that a client can send that is not an envelope.
pub type ControlFrame {
  Attest(digest: String, up_to: Int)
  /// One delivered order that this client could not process. This frame is
  /// never a decision about a document. The relay learns *that* the client
  /// refused an entry, and it learns nothing about the reason.
  Skip(order: Int)
  /// The optional relay control features that this connection understands. The
  /// client sends this frame one time, after the `hello` frame that admits the
  /// connection.
  ///
  /// The relay never sends a `CheckpointRequest` frame to a client that does
  /// not send this frame. That rule makes the request safe to add to a lane
  /// that is already in use. An older client would treat an unknown server
  /// frame as a handshake violation, and that client never receives one.
  Supports(checkpoint_requests: Bool)
}

/// One inbound frame, in its classified form. `Envelope` keeps the raw string
/// with the four preamble facts that admission needs, because the relay
/// forwards that string and not a new encoding of it.
pub type ClientFrame {
  Document(
    raw: String,
    room: String,
    from: String,
    session: String,
    message: MessageKind,
  )
  Control(frame: ControlFrame)
}

/// The envelope message types that this lane accepts. The list is closed on
/// purpose, and the module reads the `type` tag against it. `error` is not on
/// the list, because a relay is not a peer, and no client can refuse it.
pub type MessageKind {
  HelloMessage
  ChannelMessage
  DeltaMessage
  StateRequestMessage
  StateMessage
  DigestMessage
}

pub fn message_kind_to_string(kind: MessageKind) -> String {
  case kind {
    HelloMessage -> "hello"
    ChannelMessage -> "channel"
    DeltaMessage -> "delta"
    StateRequestMessage -> "stateRequest"
    StateMessage -> "state"
    DigestMessage -> "digest"
  }
}

fn string_to_message_kind(raw: String) -> Result(MessageKind, Nil) {
  case raw {
    "hello" -> Ok(HelloMessage)
    "channel" -> Ok(ChannelMessage)
    "delta" -> Ok(DeltaMessage)
    "stateRequest" -> Ok(StateRequestMessage)
    "state" -> Ok(StateMessage)
    "digest" -> Ok(DigestMessage)
    _ -> Error(Nil)
  }
}

/// The reason that the module refused a frame. Every reason here is terminal.
/// The relay tells the connection the reason and then closes it, and the room
/// does not change.
pub type Refusal {
  FrameTooLarge(bytes: Int)
  Malformed(detail: String)
  UnsupportedMessage(tag: String)
  /// A document frame that arrived before the `hello` frame that admits the
  /// connection.
  NotAdmitted
  InvalidRoom(detail: String)
  RoomFull(limit: Int)
  /// A frame whose room, sender, or session is not the one that this
  /// connection was admitted with. This refusal isolates a client that speaks
  /// to the wrong room.
  IdentityChanged(detail: String)
  DuplicateSession(session: String)
  /// A connection reported more outstanding skips than the module permits.
  /// This limit bounds the memory, and the refusal is terminal for that
  /// connection only.
  TooManySkips(limit: Int)
  /// The live log of the room is at `max_room_records`, and this frame would
  /// have taken it past that bound. The refusal is terminal for the sender
  /// only. The durable records of the room do not change, and every other
  /// connection keeps its lane.
  RoomAtCapacity(limit: Int)
}

pub fn refusal_parts(refusal: Refusal) -> #(String, String) {
  case refusal {
    FrameTooLarge(bytes) -> #(
      "frameTooLarge",
      int.to_string(bytes)
        <> " bytes exceeds the "
        <> int.to_string(max_frame_bytes())
        <> " byte limit",
    )
    Malformed(detail) -> #("malformed", detail)
    UnsupportedMessage(tag) -> #(
      "unsupportedMessage",
      tag <> " is not carried by " <> capability,
    )
    NotAdmitted -> #(
      "notAdmitted",
      "the first frame on a relay lane must be a hello envelope",
    )
    InvalidRoom(detail) -> #("invalidRoom", detail)
    RoomFull(limit) -> #(
      "roomFull",
      "the room already holds " <> int.to_string(limit) <> " clients",
    )
    IdentityChanged(detail) -> #("identityChanged", detail)
    DuplicateSession(session) -> #(
      "duplicateSession",
      session <> " is already attached to this room",
    )
    TooManySkips(limit) -> #(
      "tooManySkips",
      "a connection may hold at most " <> int.to_string(limit) <> " skips",
    )
    RoomAtCapacity(limit) -> #(
      "roomAtCapacity",
      "the room's live log already holds " <> int.to_string(limit) <> " records",
    )
  }
}

/// What a relay must do after a frame. Each action names a connection by the
/// integer id that the service assigned to it, so the state machine never holds
/// a socket. Each action also describes a storage operation and does not perform
/// it, so the state machine never holds a file handle.
pub type Action {
  Send(connection: Int, frame: ServerFrame)
  /// Close a connection, after every `Send` action that the module already
  /// emitted for it.
  Close(connection: Int, reason: String)
  /// Append one JSONL line to the log of the room.
  Append(room: String, line: String)
  /// Replace the log of the room with exactly these lines. The module emits
  /// this action only after the `Append` action that carries the checkpoint
  /// that it keeps.
  Compact(room: String, lines: List(String))
}

// ─────────────────────────────────────────────────────────────────────────────
// Encoding
// ─────────────────────────────────────────────────────────────────────────────

pub fn server_to_json(frame: ServerFrame) -> Json {
  case frame {
    Connected(supports, envelope_bytes) ->
      json.object([
        #("type", json.string("connected")),
        #(
          "capabilities",
          json.object(case supports {
            True -> [#(capability, json.bool(True))]
            False -> []
          }),
        ),
        #("limits", json.object([#("envelopeBytes", json.int(envelope_bytes))])),
      ])
    Frame(order, envelope) ->
      json.object([
        #("type", json.string("frame")),
        #("order", json.int(order)),
        #("envelope", json.string(envelope)),
      ])
    Synced(order) ->
      json.object([
        #("type", json.string("synced")),
        #("order", json.int(order)),
      ])
    Attested(order, digest) ->
      json.object([
        #("type", json.string("attested")),
        #("order", json.int(order)),
        #("digest", json.string(digest)),
      ])
    CheckpointRequest ->
      json.object([#("type", json.string("checkpointRequest"))])
    Refused(reason, detail) ->
      json.object([
        #("type", json.string("error")),
        #("reason", json.string(reason)),
        #("detail", json.string(detail)),
      ])
  }
}

pub fn server_to_string(frame: ServerFrame) -> String {
  json.to_string(server_to_json(frame))
}

pub fn control_to_string(frame: ControlFrame) -> String {
  case frame {
    Attest(digest, up_to) ->
      json.to_string(
        json.object([
          #("type", json.string("attest")),
          #("digest", json.string(digest)),
          #("upTo", json.int(up_to)),
        ]),
      )
    Skip(order) ->
      json.to_string(
        json.object([
          #("type", json.string("skip")),
          #("order", json.int(order)),
        ]),
      )
    Supports(checkpoint_requests) ->
      json.to_string(
        json.object([
          #("type", json.string("supports")),
          #("checkpointRequests", json.bool(checkpoint_requests)),
        ]),
      )
  }
}

/// The greeting that a compatible relay opens with.
pub fn connected_frame() -> ServerFrame {
  Connected(supports: True, envelope_bytes: max_frame_bytes())
}

// ─────────────────────────────────────────────────────────────────────────────
// Decoding
// ─────────────────────────────────────────────────────────────────────────────

type Preamble {
  Preamble(
    version: Int,
    room: String,
    from: String,
    session: String,
    message_type: String,
  )
}

/// Read the preamble of the envelope only. The decoder reads exactly one field
/// inside `message`, which is its `type` tag, and it never reads the payload of
/// that message. That rule keeps a relay outside the kernels.
fn preamble_decoder() -> Decoder(Preamble) {
  use version <- decode.field("v", decode.int)
  use room <- decode.field("room", decode.string)
  use from <- decode.field("from", decode.string)
  use session <- decode.field("session", decode.string)
  use message_type <- decode.subfield(["message", "type"], decode.string)
  decode.success(Preamble(version, room, from, session, message_type))
}

type ServerShape {
  ServerShape(
    kind: String,
    order: Int,
    envelope: String,
    digest: String,
    reason: String,
    detail: String,
    capabilities: Dict(String, Bool),
    envelope_bytes: Int,
  )
}

fn server_decoder() -> Decoder(ServerShape) {
  use kind <- decode.field("type", decode.string)
  use order <- decode.optional_field("order", 0, decode.int)
  use envelope <- decode.optional_field("envelope", "", decode.string)
  use digest <- decode.optional_field("digest", "", decode.string)
  use reason <- decode.optional_field("reason", "", decode.string)
  use detail <- decode.optional_field("detail", "", decode.string)
  use capabilities <- decode.optional_field(
    "capabilities",
    dict.new(),
    decode.dict(decode.string, decode.bool),
  )
  use envelope_bytes <- decode.optional_field(
    "limits",
    0,
    decode.optionally_at(["envelopeBytes"], 0, decode.int),
  )
  decode.success(ServerShape(
    kind,
    order,
    envelope,
    digest,
    reason,
    detail,
    capabilities,
    envelope_bytes,
  ))
}

/// Read one frame that a relay sent. This is the client half of the codec that
/// the relay encodes with, so the two cannot drift apart.
///
/// A relay that stamps nothing is valid. The function accepts a frame with no
/// top-level `type` field as a bare envelope, and it reports that frame with the
/// order `0`.
pub fn decode_server(raw: String) -> Result(ServerFrame, String) {
  case json.parse(raw, server_decoder()) {
    Ok(shape) ->
      case shape.kind {
        "connected" ->
          Ok(Connected(
            supports: dict.get(shape.capabilities, capability) == Ok(True),
            envelope_bytes: shape.envelope_bytes,
          ))
        "frame" ->
          case shape.envelope {
            "" -> Error("a relay frame carried no envelope")
            envelope -> Ok(Frame(shape.order, envelope))
          }
        "synced" -> Ok(Synced(shape.order))
        "attested" -> Ok(Attested(shape.order, shape.digest))
        "checkpointRequest" -> Ok(CheckpointRequest)
        "error" -> Ok(Refused(shape.reason, shape.detail))
        other -> Error("unknown relay frame " <> other)
      }
    Error(_) ->
      case json.parse(raw, preamble_decoder()) {
        Ok(_) -> Ok(Frame(0, raw))
        Error(_) -> Error("not a relay frame or a CRDT envelope")
      }
  }
}

/// Whether a `connected` frame announces the lane that this client uses.
pub fn supports_relay(frame: ServerFrame) -> Bool {
  case frame {
    Connected(supports, _) -> supports
    Frame(_, _)
    | Synced(_)
    | Attested(_, _)
    | CheckpointRequest
    | Refused(_, _) -> False
  }
}

type ControlShape {
  ControlShape(
    kind: String,
    digest: String,
    up_to: Int,
    order: Int,
    checkpoint_requests: Bool,
  )
}

fn control_decoder() -> Decoder(ControlShape) {
  use kind <- decode.field("type", decode.string)
  use digest <- decode.optional_field("digest", "", decode.string)
  use up_to <- decode.optional_field("upTo", 0, decode.int)
  use order <- decode.optional_field("order", 0, decode.int)
  use checkpoint_requests <- decode.optional_field(
    "checkpointRequests",
    False,
    decode.bool,
  )
  decode.success(ControlShape(kind, digest, up_to, order, checkpoint_requests))
}

/// Classify one raw inbound frame.
///
/// A control frame is a JSON object with a top-level `type` field. A document
/// frame is a version 1 CRDT envelope, and it has no such field. That
/// difference is the whole test, and it is the reason that a relay never has to
/// guess.
pub fn decode_client(raw: String) -> Result(ClientFrame, Refusal) {
  use _ <- result.try(case int.compare(byte_size(raw), max_frame_bytes()) {
    order.Gt -> Error(FrameTooLarge(byte_size(raw)))
    order.Lt -> Ok(Nil)
    order.Eq -> Ok(Nil)
  })
  case json.parse(raw, control_decoder()) {
    Ok(ControlShape("attest", digest, up_to, _, _)) ->
      Ok(Control(Attest(digest: digest, up_to: up_to)))
    Ok(ControlShape("skip", _, _, order, _)) -> Ok(Control(Skip(order: order)))
    Ok(ControlShape("supports", _, _, _, checkpoint_requests)) ->
      Ok(Control(Supports(checkpoint_requests: checkpoint_requests)))
    Ok(ControlShape(kind, _, _, _, _)) ->
      Error(Malformed("unknown control frame " <> kind))
    Error(_) -> decode_document(raw)
  }
}

fn decode_document(raw: String) -> Result(ClientFrame, Refusal) {
  use preamble <- result.try(
    json.parse(raw, preamble_decoder())
    |> result.replace_error(Malformed("not a v1 CRDT envelope")),
  )
  let Preamble(version, room, from, session, message_type) = preamble
  use _ <- result.try(case version == crdt_wire.protocol_version {
    True -> Ok(Nil)
    False ->
      Error(Malformed(
        "envelope is protocol v"
        <> int.to_string(version)
        <> ", not v"
        <> int.to_string(crdt_wire.protocol_version),
      ))
  })
  use _ <- result.try(
    case
      crdt_wire.valid_replica_id(from)
      && session != ""
      && byte_size(session) <= max_session_bytes
    {
      True -> Ok(Nil)
      False -> Error(Malformed("envelope has no usable sender identity"))
    },
  )
  use _ <- result.try(check_room(room))
  use kind <- result.try(
    string_to_message_kind(message_type)
    |> result.replace_error(UnsupportedMessage(message_type)),
  )
  use _ <- result.try(check_shape(raw, kind))
  Ok(Document(raw: raw, room: room, from: from, session: session, message: kind))
}

/// The inexpensive structural checks that a relay can make on a message
/// *without* a decode of a kernel payload.
///
/// Every check here reads a field that names or addresses a message. Those
/// fields are the id, the address, and the declared channel type of a delta, the
/// descriptor of a channel announcement, and the shape of the channel list of a
/// `state` message. No check here reads a `contents` field or a `snapshot`
/// field. Those two belong to the kernel, and they stay an opaque string all the
/// way to the log.
///
/// These checks are a *subset* of the checks that the decoder of `crdt_wire`
/// makes, and that is deliberate. A relay thus can never refuse an envelope that
/// a document would have accepted. The checks refuse the cheapest invalid input
/// at the socket, instead of a log, a replay, and a skip by every client
/// without an end. Four examples: a frame with a `delta` tag and no id, an
/// address that names no channel, a descriptor whose `createdBy` field
/// disagrees with its own address, and a `state` whose channels are not a list.
///
/// These checks do not remove every bad record. A correct delta whose op has no
/// meaning to any kernel still enters the log, and it always will, because only
/// a merge could detect it.
fn check_shape(raw: String, kind: MessageKind) -> Result(Nil, Refusal) {
  case kind {
    HelloMessage -> shaped(raw, hello_shape(), "hello")
    DigestMessage -> shaped(raw, digest_shape(), "digest")
    StateMessage -> shaped(raw, state_shape(), "state")
    StateRequestMessage -> Ok(Nil)
    ChannelMessage -> {
      use #(address, channel_type, created_by) <- result.try(shape(
        raw,
        channel_shape(),
        "channel",
      ))
      use creator <- result.try(
        crdt_wire.address_creator(address)
        |> result.replace_error(Malformed(
          "channel names the invalid address " <> address,
        )),
      )
      case creator == created_by, channel_type != "" {
        False, _ ->
          Error(Malformed(
            "channel " <> address <> " claims a creator its address denies",
          ))
        _, False -> Error(Malformed("channel declares an empty channel type"))
        True, True -> Ok(Nil)
      }
    }
    DeltaMessage -> {
      use #(#(replica, counter), address, channel_type) <- result.try(shape(
        raw,
        delta_shape(),
        "delta",
      ))
      use _ <- result.try(
        crdt_wire.address_creator(address)
        |> result.replace_error(Malformed(
          "delta names the invalid address " <> address,
        )),
      )
      case crdt_wire.valid_replica_id(replica) && counter >= 0, channel_type {
        False, _ -> Error(Malformed("delta has an invalid message id"))
        _, "" -> Error(Malformed("delta declares an empty channel type"))
        _, _ -> Ok(Nil)
      }
    }
  }
}

fn shape(raw: String, decoder: Decoder(a), what: String) -> Result(a, Refusal) {
  json.parse(raw, decoder)
  |> result.replace_error(Malformed("malformed " <> what <> " message"))
}

fn shaped(
  raw: String,
  decoder: Decoder(a),
  what: String,
) -> Result(Nil, Refusal) {
  shape(raw, decoder, what) |> result.replace(Nil)
}

fn hello_shape() -> Decoder(#(String, String)) {
  use compatibility <- decode.subfield(
    ["message", "compatibility"],
    decode.string,
  )
  use root <- decode.subfield(["message", "root"], decode.string)
  decode.success(#(compatibility, root))
}

fn digest_shape() -> Decoder(String) {
  decode.at(["message", "digest"], decode.string)
}

/// The channels of a `state` message must be a list. The content of that list
/// belongs to a kernel. The elements stay dynamic values here, and this module
/// never reads them.
fn state_shape() -> Decoder(List(decode.Dynamic)) {
  decode.at(["message", "channels"], decode.list(decode.dynamic))
}

fn channel_shape() -> Decoder(#(String, String, String)) {
  use address <- decode.subfield(
    ["message", "descriptor", "address"],
    decode.string,
  )
  use channel_type <- decode.subfield(
    ["message", "descriptor", "channelType"],
    decode.string,
  )
  use created_by <- decode.subfield(
    ["message", "descriptor", "createdBy"],
    decode.string,
  )
  decode.success(#(address, channel_type, created_by))
}

fn delta_shape() -> Decoder(#(#(String, Int), String, String)) {
  use id <- decode.subfield(["message", "id"], message_id_shape())
  use address <- decode.subfield(["message", "address"], decode.string)
  use channel_type <- decode.subfield(["message", "channelType"], decode.string)
  decode.success(#(id, address, channel_type))
}

fn message_id_shape() -> Decoder(#(String, Int)) {
  use replica <- decode.field(0, decode.string)
  use counter <- decode.field(1, decode.int)
  decode.success(#(replica, counter))
}

fn byte_size(raw: String) -> Int {
  bit_array.byte_size(<<raw:utf8>>)
}

fn check_room(room: String) -> Result(Nil, Refusal) {
  case room == "", byte_size(room) > max_room_bytes {
    True, _ -> Error(InvalidRoom("room name is empty"))
    _, True ->
      Error(InvalidRoom(
        "room name is longer than " <> int.to_string(max_room_bytes) <> " bytes",
      ))
    False, False -> Ok(Nil)
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Durable records
// ─────────────────────────────────────────────────────────────────────────────

/// One line of the log of a room.
pub type LogRecord {
  /// A publication of a full state. It becomes a checkpoint after a client
  /// attests it.
  StateRecord(order: Int, session: String, envelope: String)
  /// A channel announcement or a delta.
  TrafficRecord(order: Int, session: String, envelope: String)
  /// The checkpoint marker of the room: the digest that a client attested,
  /// with the order of the `state` record that the attestation described.
  ///
  /// `checkpoint` survives a restart, and it says *which* `state` record of a
  /// log is the canonical record of the room. That record is the entry that a
  /// `stateRequest` rebuilds from. `digest` is current only while this marker
  /// is the newest record in the file. Anything that the relay logs after a
  /// checkpoint means that the checkpoint no longer describes the room. A
  /// marker that a later compaction rewrites carries `""` to report that, and
  /// it still names the canonical entry.
  DigestRecord(order: Int, digest: String, checkpoint: Int)
}

pub fn record_to_string(record: LogRecord) -> String {
  json.to_string(case record {
    StateRecord(order, session, envelope) ->
      json.object([
        #("o", json.int(order)),
        #("k", json.string("state")),
        #("s", json.string(session)),
        #("e", json.string(envelope)),
      ])
    TrafficRecord(order, session, envelope) ->
      json.object([
        #("o", json.int(order)),
        #("k", json.string("traffic")),
        #("s", json.string(session)),
        #("e", json.string(envelope)),
      ])
    DigestRecord(order, digest, checkpoint) ->
      json.object([
        #("o", json.int(order)),
        #("k", json.string("digest")),
        #("d", json.string(digest)),
        #("c", json.int(checkpoint)),
      ])
  })
}

type RawRecord {
  RawRecord(
    order: Int,
    kind: String,
    session: String,
    envelope: String,
    digest: String,
    checkpoint: Int,
  )
}

fn record_decoder() -> Decoder(RawRecord) {
  use order <- decode.field("o", decode.int)
  use kind <- decode.field("k", decode.string)
  use session <- decode.optional_field("s", "", decode.string)
  use envelope <- decode.optional_field("e", "", decode.string)
  use digest <- decode.optional_field("d", "", decode.string)
  // Optional, so a log written before checkpoint markers named their
  // entry still replays; `replay` falls back to the newest `state`
  // record when it reads a `0`.
  use checkpoint <- decode.optional_field("c", 0, decode.int)
  decode.success(RawRecord(order, kind, session, envelope, digest, checkpoint))
}

pub fn string_to_record(line: String) -> Result(LogRecord, Nil) {
  case json.parse(line, record_decoder()) {
    Error(_) -> Error(Nil)
    Ok(RawRecord(order, "state", session, envelope, _, _)) ->
      Ok(StateRecord(order, session, envelope))
    Ok(RawRecord(order, "traffic", session, envelope, _, _)) ->
      Ok(TrafficRecord(order, session, envelope))
    Ok(RawRecord(order, "digest", _, _, digest, checkpoint)) ->
      Ok(DigestRecord(order, digest, checkpoint))
    Ok(_) -> Error(Nil)
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The relay
// ─────────────────────────────────────────────────────────────────────────────

type Entry {
  Entry(
    order: Int,
    session: String,
    envelope: String,
    state: Bool,
    /// The durable line that the relay appended for this entry, without a
    /// change.
    ///
    /// A compaction rewrites every line that it keeps. To hold the original
    /// line is thus the correct answer, because the record leaves exactly as it
    /// arrived, byte for byte. It is also the answer that does not encode the
    /// whole log of a room again.
    line: String,
  )
}

type Client {
  Client(
    from: String,
    session: String,
    /// The highest order that the relay *sent* to this connection. An
    /// attestation cannot claim to have processed further than this value,
    /// whatever number it carries. A client that survived a restart of the
    /// relay quotes a number from an order sequence that no longer exists. This
    /// field prevents that number from retiring an entry that the client never
    /// saw.
    delivered: Int,
    /// The orders that the relay sent to this connection, that the connection
    /// reported as unreadable, and that the log still holds. A checkpoint from
    /// this connection can land around those entries: the compaction carries
    /// them, and it does not retire them. No claim from another connection can
    /// do that for them. A skip for an order that the relay never delivered
    /// never enters this list.
    skipped: List(Int),
    /// Whether this connection reported that it understands a
    /// `CheckpointRequest` frame. The relay sends nothing of that kind to a
    /// connection that did not report it. A client that a developer wrote
    /// against an earlier build of this lane thus receives exactly the frames
    /// that it always received.
    supports_checkpoints: Bool,
    /// Whether this connection has a `CheckpointRequest` frame with no answer.
    /// There is one at a time. A room under pressure asks a client one time,
    /// and it asks again only after that client publishes a `state` frame, or
    /// after the log grows by another `checkpoint_request_interval`.
    checkpoint_requested: Bool,
  )
}

type Room {
  Room(
    /// A map from a connection id to the identity that the relay admitted it
    /// with.
    clients: Dict(Int, Client),
    /// The next diagnostic order to stamp.
    next_order: Int,
    /// Everything that the relay accepted and that an attested state does not
    /// contain yet, oldest first. This list is the *live replay lane*. A
    /// `stateRequest` receives it, and `max_room_records` bounds it.
    log: List(Entry),
    /// The connection whose `state` frame waits for an attestation, with the
    /// order that the relay stamped that state with.
    pending: Option(#(Int, Int)),
    /// The digest that a client attested for the current checkpoint, or `""`.
    attested: String,
    /// The order that the relay wrote the digest record of the current
    /// checkpoint at. A compaction for another reason can thus rewrite that
    /// line without a change, and it does not drop the attestation of the
    /// room.
    attested_order: Int,
    /// The order of the `state` entry that the checkpoint of the room
    /// describes. The value is `0` for a room that has never checkpointed.
    ///
    /// That entry is the canonical state of the room, and a `stateRequest`
    /// rebuilds from it. This field outlives `attested`. Traffic that arrives
    /// after a checkpoint clears the digest, and the state that the checkpoint
    /// published is still the base that every later delta reads against.
    checkpoint_order: Int,
    /// The size of the live log at which the relay sent the last round of
    /// `CheckpointRequest` frames. The value is `0` for a room that has never
    /// asked. A room asks again only after its log grows another
    /// `checkpoint_request_interval` past this value. That rule bounds the
    /// number of requests that a flood can produce.
    pressure_at: Int,
    /// The number of `CheckpointRequest` frames that this room sent after the
    /// process started. This field is for metrics only.
    requests: Int,
  )
}

fn new_room() -> Room {
  Room(
    clients: dict.new(),
    next_order: 1,
    log: [],
    pending: None,
    attested: "",
    attested_order: 0,
    checkpoint_order: 0,
    pressure_at: 0,
    requests: 0,
  )
}

pub opaque type Relay {
  /// `connections` maps the id of a socket to the room that the relay admitted
  /// it to. Every other fact about that connection is in the `clients` field of
  /// that room.
  Relay(rooms: Dict(String, Room), connections: Dict(Int, String))
}

pub fn new_relay() -> Relay {
  Relay(rooms: dict.new(), connections: dict.new())
}

/// The room names that the relay holds now, sorted. A room with a log stays
/// after its last client leaves. That behaviour makes a relay durable, and not
/// a hub.
pub fn room_names(relay: Relay) -> List(String) {
  dict.keys(relay.rooms) |> list.sort(string.compare)
}

/// The connections that the relay admitted to a room, sorted.
pub fn clients(relay: Relay, room: String) -> List(Int) {
  case dict.get(relay.rooms, room) {
    Ok(found) -> dict.keys(found.clients) |> list.sort(int.compare)
    Error(Nil) -> []
  }
}

/// The sessions that the relay admitted to a room, sorted.
pub fn sessions(relay: Relay, room: String) -> List(String) {
  case dict.get(relay.rooms, room) {
    Ok(found) ->
      dict.values(found.clients)
      |> list.map(fn(client) { client.session })
      |> list.sort(string.compare)
    Error(Nil) -> []
  }
}

/// The next order that a room stamps. The value is one more than the order of
/// the last accepted frame, and it is `1` for a room that has accepted no
/// frame.
pub fn next_order(relay: Relay, room: String) -> Int {
  case dict.get(relay.rooms, room) {
    Ok(found) -> found.next_order
    Error(Nil) -> 1
  }
}

/// The number of entries in the log of a room. After a successful attestation,
/// that number is the checkpoint with every entry that the attesting connection
/// reported as unreadable. It is `1` in the usual case, where there was no such
/// entry.
pub fn log_size(relay: Relay, room: String) -> Int {
  case dict.get(relay.rooms, room) {
    Ok(found) -> list.length(found.log)
    Error(Nil) -> 0
  }
}

/// The digest that a client attested for the checkpoint of the room. The value
/// is `""` when the room has never checkpointed, and when the room changed
/// after that checkpoint.
///
/// The digest describes the checkpoint *entry*, which is not always the whole
/// log. A log that also carries the entries that the attesting client could not
/// read holds more than this digest names, and a client that can read those
/// entries holds more than the digest too. That is the correct reading. The
/// other option is a digest that claims to cover records that no client
/// merged.
pub fn attested_digest(relay: Relay, room: String) -> String {
  case dict.get(relay.rooms, room) {
    Ok(found) -> found.attested
    Error(Nil) -> ""
  }
}

/// Every envelope that a `stateRequest` would replay, oldest first.
pub fn replayable(relay: Relay, room: String) -> List(String) {
  case dict.get(relay.rooms, room) {
    Ok(found) -> list.map(found.log, fn(entry) { entry.envelope })
    Error(Nil) -> []
  }
}

/// The orders that one connection reported as unreadable, and that the log of
/// its room still holds, sorted. This function is a diagnostic. A service makes
/// it available, so that an operator can see the exact entries that the relay
/// carries past a checkpoint, and the connection that reported each one. The
/// operator thus does not have to guess at the reason that the log of a room
/// does not become one line.
pub fn skipped_orders(relay: Relay, connection: Int) -> List(Int) {
  case client_of(relay, connection) {
    Error(Nil) -> []
    Ok(#(_room, client)) -> list.sort(client.skipped, int.compare)
  }
}

/// The room and the per-room record of an admitted connection. A connection in
/// `connections` is always in the `clients` field of its room, because `admit`
/// inserts both entries and `disconnect` removes both. The inner lookup thus
/// fails only for a broken relay, and it reports `Error(Nil)` for that.
fn client_of(relay: Relay, connection: Int) -> Result(#(String, Client), Nil) {
  use room <- result.try(dict.get(relay.connections, connection))
  use client <- result.try(dict.get(room_of(relay, room).clients, connection))
  Ok(#(room, client))
}

/// Every order that this room carries now, which means that the log still holds
/// it and that one attached connection or more reported that it cannot merge
/// it. The list is sorted, oldest first, and the log of the room bounds it. This
/// function is a diagnostic. An operator reads it to see the entries that a
/// checkpoint lands around, and the reason that the log of a room does not
/// become one line.
pub fn carried_orders(relay: Relay, room: String) -> List(Int) {
  case dict.get(relay.rooms, room) {
    Error(Nil) -> []
    Ok(found) -> carriage(found)
  }
}

/// The order of the `state` entry that the checkpoint of this room describes.
/// The value is `0` when the room has never checkpointed. That entry is the
/// canonical state of the room. An operator reads this value to see what a new
/// attachment would rebuild from.
pub fn checkpoint_order(relay: Relay, room: String) -> Int {
  case dict.get(relay.rooms, room) {
    Error(Nil) -> 0
    Ok(found) -> found.checkpoint_order
  }
}

/// The number of `CheckpointRequest` frames that this room sent after this
/// process started. This function is for metrics. A room whose count grows
/// while its log stays large is a room whose clients do not answer those
/// requests.
pub fn checkpoint_requests(relay: Relay, room: String) -> Int {
  case dict.get(relay.rooms, room) {
    Error(Nil) -> 0
    Ok(found) -> found.requests
  }
}

/// The connections in this room that have a `CheckpointRequest` frame with no
/// answer, sorted.
pub fn checkpoints_pending(relay: Relay, room: String) -> List(Int) {
  case dict.get(relay.rooms, room) {
    Error(Nil) -> []
    Ok(found) ->
      dict.to_list(found.clients)
      |> list.filter(fn(entry) { { entry.1 }.checkpoint_requested })
      |> list.map(fn(entry) { entry.0 })
      |> list.sort(int.compare)
  }
}

/// Whether this connection told the relay that it understands a
/// `CheckpointRequest` frame.
pub fn supports_checkpoints(relay: Relay, connection: Int) -> Bool {
  case client_of(relay, connection) {
    Error(Nil) -> False
    Ok(#(_room, client)) -> client.supports_checkpoints
  }
}

fn carriage(found: Room) -> List(Int) {
  let claimed = claimed_orders(found)
  found.log
  |> list.filter(fn(entry) { set.contains(claimed, entry.order) })
  |> list.map(fn(entry) { entry.order })
  |> list.sort(int.compare)
}

/// Every order that a connection in this room reported as unreadable, as a set.
/// A flooded room calls this function one time for each refusal, so the function
/// does not scan one list inside another. That choice is deliberate.
fn claimed_orders(found: Room) -> set.Set(Int) {
  dict.fold(found.clients, set.new(), fn(carried, _connection, client) {
    list.fold(client.skipped, carried, fn(carried, order) {
      set.insert(carried, order)
    })
  })
}

/// The orders that the live log of a room holds, as a set.
fn log_orders(found: Room) -> set.Set(Int) {
  list.fold(found.log, set.new(), fn(carried, entry) {
    set.insert(carried, entry.order)
  })
}

// ─────────────────────────────────────────────────────────────────────────────
// Connection lifecycle
// ─────────────────────────────────────────────────────────────────────────────

/// A socket opened. The relay writes first, so the capability negotiation ends
/// before a client sends anything.
pub fn connect(relay: Relay, connection: Int) -> #(Relay, List(Action)) {
  #(relay, [Send(connection, connected_frame())])
}

/// A socket closed, for any reason. A second call has no more effect, and the
/// function never changes the log. The durable content of a room outlives every
/// client in that room.
pub fn disconnect(relay: Relay, connection: Int) -> #(Relay, List(Action)) {
  case dict.get(relay.connections, connection) {
    Error(Nil) -> #(relay, [])
    Ok(room) -> {
      let rooms = case dict.get(relay.rooms, room) {
        Error(Nil) -> relay.rooms
        Ok(found) ->
          dict.insert(
            relay.rooms,
            room,
            Room(
              ..found,
              clients: dict.delete(found.clients, connection),
              pending: case found.pending {
                Some(#(owner, _)) if owner == connection -> None
                other -> other
              },
            ),
          )
      }
      #(
        Relay(
          rooms: rooms,
          connections: dict.delete(relay.connections, connection),
        ),
        [],
      )
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Frames
// ─────────────────────────────────────────────────────────────────────────────

/// Apply one raw frame from one connection.
pub fn handle_frame(
  relay: Relay,
  connection: Int,
  raw: String,
) -> #(Relay, List(Action)) {
  let #(relay, actions, _tag) = serve(relay, connection, raw)
  #(relay, actions)
}

/// `handle_frame`, with the tag of the frame.
///
/// The tag is the whole instrumentation of a relay. It is `hello`, `channel`,
/// `delta`, `stateRequest`, `state`, `digest`, `attest`, `skip`,
/// `skip:undelivered`, or `rejected:<reason>`. It comes from the `type` tag of
/// the envelope, and from whether the relay refused the frame. It never comes
/// from a payload.
pub fn serve(
  relay: Relay,
  connection: Int,
  raw: String,
) -> #(Relay, List(Action), String) {
  case decode_client(raw) {
    Error(refusal) -> #(
      relay,
      refuse(connection, refusal),
      refusal_tag(refusal),
    )
    Ok(Control(frame)) ->
      case control(relay, connection, frame) {
        Ok(#(relay, actions, tag)) -> #(relay, actions, tag)
        Error(refusal) -> #(
          relay,
          refuse(connection, refusal),
          refusal_tag(refusal),
        )
      }
    Ok(Document(raw, room, from, session, message)) ->
      case admit(relay, connection, room, from, session, message) {
        Error(refusal) -> #(
          relay,
          refuse(connection, refusal),
          refusal_tag(refusal),
        )
        Ok(relay) ->
          // Capacity is checked here rather than inside `route` so that a
          // refusal is *reported* as one: a room at its bound closes the
          // sender, and a service's frame tags say `rejected:roomAtCapacity`
          // rather than counting the frame as ordinary traffic.
          case capacity(relay, connection, room, message) {
            Error(refusal) -> #(
              relay,
              refuse(connection, refusal),
              refusal_tag(refusal),
            )
            Ok(Nil) -> {
              let #(relay, actions) =
                route(relay, connection, room, session, message, raw)
              #(relay, actions, message_kind_to_string(message))
            }
          }
      }
  }
}

/// Whether this durable frame fits in the bounded live log of this room.
///
/// The function checks the three message kinds that the relay logs. It does not
/// check a `hello` frame, a `digest` frame, or a `stateRequest` frame. The relay
/// stamps or answers those three and never appends them. A room at its bound
/// thus still admits a client, still answers a replay, and still carries a
/// digest. A correct client can therefore attach to a full room, refuse what it
/// cannot read, and empty that room.
fn capacity(
  relay: Relay,
  connection: Int,
  room: String,
  message: MessageKind,
) -> Result(Nil, Refusal) {
  case message {
    HelloMessage | DigestMessage | StateRequestMessage -> Ok(Nil)
    ChannelMessage | DeltaMessage | StateMessage ->
      case room_has_capacity(room_of(relay, room), connection, message) {
        True -> Ok(Nil)
        False -> Error(RoomAtCapacity(max_room_records))
      }
  }
}

fn refusal_tag(refusal: Refusal) -> String {
  "rejected:" <> refusal_parts(refusal).0
}

/// One control frame, with the tag of that frame.
fn control(
  relay: Relay,
  connection: Int,
  frame: ControlFrame,
) -> Result(#(Relay, List(Action), String), Refusal) {
  case frame {
    Attest(_, _) -> {
      use #(relay, actions) <- result.try(attest(relay, connection, frame))
      Ok(#(relay, actions, "attest"))
    }
    Skip(order) -> {
      use #(relay, actions, honoured) <- result.try(skip(
        relay,
        connection,
        order,
      ))
      Ok(
        #(relay, actions, case honoured {
          True -> "skip"
          False -> "skip:undelivered"
        }),
      )
    }
    Supports(checkpoint_requests) -> {
      use #(relay, actions) <- result.try(declare_support(
        relay,
        connection,
        checkpoint_requests,
      ))
      Ok(#(relay, actions, "supports"))
    }
  }
}

/// A connection that reports which optional control frames it understands.
///
/// The relay accepts this frame from an admitted connection only. The frame is a
/// statement about a client in a room, and a connection that did not send
/// `hello` is in no room. The frame stamps no order, it logs nothing, and it
/// broadcasts nothing. To repeat it is to make the same statement two times.
///
/// A connection that never sends this frame never receives a
/// `CheckpointRequest` frame. At the hard bound, the relay admits a `state`
/// frame only from a client that declared support. See `room_has_capacity`.
/// Such a connection thus also never publishes past that bound.
fn declare_support(
  relay: Relay,
  connection: Int,
  checkpoint_requests: Bool,
) -> Result(#(Relay, List(Action)), Refusal) {
  use #(room, client) <- result.try(
    client_of(relay, connection) |> result.replace_error(NotAdmitted),
  )
  let found = room_of(relay, room)
  let found =
    Room(
      ..found,
      clients: dict.insert(
        found.clients,
        connection,
        Client(..client, supports_checkpoints: checkpoint_requests),
      ),
    )
  Ok(#(store(relay, room, found), []))
}

/// One order that this connection could not process.
///
/// The relay accepts the claim only when it sent that order to *this*
/// connection. A claim about any other order is a claim about an entry that
/// this client has no evidence of, and to act on it would let a client decide
/// the fate of something that it never saw.
///
/// The relay drops a claim that it does not accept, and that claim is not
/// fatal. A relay that stamps an order that it does not account for is at
/// fault, and the client that speaks to it is not. There is also nothing in the
/// log for such a claim to attach to.
///
/// A skip is a fact about a delivery, and never about the content. The relay
/// does not learn the reason that the client refused the entry, it does not stop
/// to carry that entry to the other clients, and it never deletes that entry on
/// one claim. The claim buys one thing: the next checkpoint of this connection
/// can land *around* the entry, and the compaction carries that entry beside the
/// checkpoint. Without the claim, that entry would block the checkpoint without
/// an end.
///
/// A claim that the relay does not accept changes nothing at all. The relay does
/// not accept a claim for an order that it never delivered, for an order outside
/// its range, and for an order that the log no longer holds. A repeated skip is
/// the same claim two times, and it also changes nothing.
fn skip(
  relay: Relay,
  connection: Int,
  order: Int,
) -> Result(#(Relay, List(Action), Bool), Refusal) {
  use #(room, client) <- result.try(
    client_of(relay, connection) |> result.replace_error(NotAdmitted),
  )
  let found = room_of(relay, room)
  case order >= 1 && order <= client.delivered {
    False -> Ok(#(relay, [], False))
    True -> {
      let claimed = case list.contains(client.skipped, order) {
        True -> client.skipped
        False -> [order, ..client.skipped]
      }
      // Pruned to what the log still holds, so a room that checkpoints
      // regularly never carries claims for entries that are already
      // gone — and a claim about an order that was stamped but never
      // logged, a `hello` or a `digest`, has nothing to attach to at all.
      //
      // Membership is a set rather than a scan: a room being flooded runs
      // this for every refusal, against a lane holding hundreds of
      // records, and a client attaching to one waits for all of it.
      let live = log_orders(found)
      let skipped =
        list.filter(claimed, fn(skipped) { set.contains(live, skipped) })
      case list.length(skipped) > max_client_skips {
        True -> Error(TooManySkips(max_client_skips))
        False -> {
          let relay =
            store(
              relay,
              room,
              Room(
                ..found,
                clients: dict.insert(
                  found.clients,
                  connection,
                  Client(..client, skipped: skipped),
                ),
              ),
            )
          Ok(#(relay, [], True))
        }
      }
    }
  }
}

/// Every line that the log file of a room must hold now: its live entries, in
/// order, with the checkpoint marker of that room, if the room has one. A
/// compaction that dropped that marker would make a restart forget the digest
/// that a client attested, and it would also forget *which* `state` record of
/// the log the room rebuilds from.
///
/// The marker carries `attested`, and that value is `""` after anything arrives
/// after the checkpoint. That is the correct reading: the entry is still the
/// canonical state of the room, and the digest no longer describes the room.
fn compaction_lines(found: Room) -> List(String) {
  let lines = list.map(found.log, fn(entry) { entry.line })
  case found.checkpoint_order > 0 || found.attested != "" {
    False -> lines
    True ->
      list.append(lines, [
        record_to_string(DigestRecord(
          // A room recovered from a log written before markers named
          // their entry has no marker order of its own; the entry it
          // names is a real, already-stamped order, so the rewrite can
          // never collide with one this room is yet to use.
          int.max(found.attested_order, found.checkpoint_order),
          found.attested,
          found.checkpoint_order,
        )),
      ])
  }
}

fn refuse(connection: Int, refusal: Refusal) -> List(Action) {
  let #(reason, detail) = refusal_parts(refusal)
  [Send(connection, Refused(reason, detail)), Close(connection, reason)]
}

/// Admission, with its one continuing obligation.
///
/// The first frame must be a `hello` frame, and that frame fixes the room, the
/// sender, and the session for the whole life of the connection. The relay
/// checks every later frame against those three values. A client thus cannot
/// change its room, it cannot forge the identity of another replica, and it
/// cannot use a session that is already attached. One connection has one
/// replica and one room.
fn admit(
  relay: Relay,
  connection: Int,
  room: String,
  from: String,
  session: String,
  message: MessageKind,
) -> Result(Relay, Refusal) {
  case dict.get(relay.connections, connection), message {
    Ok(admitted_room), _ -> {
      // `admit` and `disconnect` write the connection record and the client
      // record together, so a missing client record means a broken relay. The
      // frame is refused instead of a panic.
      use client <- result.try(
        dict.get(room_of(relay, admitted_room).clients, connection)
        |> result.replace_error(IdentityChanged(
          "the admitted connection has no client record",
        )),
      )
      case
        admitted_room == room,
        client.from == from,
        client.session == session
      {
        True, True, True -> Ok(relay)
        False, _, _ ->
          Error(IdentityChanged(
            "admitted to " <> admitted_room <> ", sent a frame for " <> room,
          ))
        _, False, _ ->
          Error(IdentityChanged(
            "admitted as " <> client.from <> ", sent a frame from " <> from,
          ))
        _, _, False ->
          Error(IdentityChanged(
            "admitted with session "
            <> client.session
            <> ", sent a frame for "
            <> session,
          ))
      }
    }
    Error(Nil), HelloMessage -> {
      let found = case dict.get(relay.rooms, room) {
        Ok(found) -> found
        Error(Nil) -> new_room()
      }
      let taken =
        dict.values(found.clients)
        |> list.any(fn(client) { client.session == session })
      case taken, dict.size(found.clients) >= max_room_clients {
        True, _ -> Error(DuplicateSession(session))
        _, True -> Error(RoomFull(max_room_clients))
        False, False -> {
          let client =
            Client(
              from: from,
              session: session,
              delivered: 0,
              skipped: [],
              supports_checkpoints: False,
              checkpoint_requested: False,
            )
          Ok(Relay(
            rooms: dict.insert(
              relay.rooms,
              room,
              Room(
                ..found,
                clients: dict.insert(found.clients, connection, client),
              ),
            ),
            connections: dict.insert(relay.connections, connection, room),
          ))
        }
      }
    }
    Error(Nil), _ -> Error(NotAdmitted)
  }
}

/// One admitted document frame.
///
/// The relay answers a `stateRequest` frame from its log, and it does not
/// forward that frame. The relay is the one participant that always has the
/// state of the room, and to ask a client for that state would make every
/// attachment a storm of broadcasts.
///
/// The relay stamps every other frame, it logs the frame when that frame is
/// durable, and it sends the frame to the other clients in the room. It never
/// sends the frame back to its sender, because that sender already has it.
///
/// The relay bounds a durable frame **before** it appends that frame. The live
/// log of a room stops at `max_room_records`, whether or not a client reported
/// that it cannot read those records. The half of a flood that no client
/// refused is still a flood. An admitted client that is alone in a room can
/// write correct traffic that no client will skip, and the carriage count,
/// which counts refused records only, would never see it.
///
/// After the log passes `checkpoint_pressure_records`, the relay asks the
/// compatible clients to checkpoint. At the bound, the relay refuses the sender
/// and closes it, and every record that is already on disk stays exactly as it
/// is.
fn route(
  relay: Relay,
  connection: Int,
  room: String,
  session: String,
  message: MessageKind,
  raw: String,
) -> #(Relay, List(Action)) {
  let found = room_of(relay, room)
  case message {
    StateRequestMessage -> {
      let high = found.next_order - 1
      #(
        store(relay, room, delivered(found, [connection], high)),
        list.append(
          list.map(found.log, fn(entry) {
            Send(connection, Frame(entry.order, entry.envelope))
          }),
          [Send(connection, Synced(high))],
        ),
      )
    }
    HelloMessage | DigestMessage -> {
      let order = found.next_order
      let found = Room(..found, next_order: order + 1)
      let recipients = others(found, connection)
      #(
        store(relay, room, delivered(found, recipients, order)),
        fan_out(recipients, order, raw),
      )
    }
    ChannelMessage | DeltaMessage -> {
      let order = found.next_order
      let line = record_to_string(TrafficRecord(order, session, raw))
      let found =
        Room(
          ..found,
          next_order: order + 1,
          log: list.append(found.log, [
            Entry(
              order: order,
              session: session,
              envelope: raw,
              state: False,
              line: line,
            ),
          ]),
          // A checkpoint stops describing the room the moment
          // anything lands after it, so the attestation goes with it.
          pending: None,
          attested: "",
        )
      let recipients = others(found, connection)
      let #(found, asked) = ask_for_checkpoints(found)
      #(store(relay, room, delivered(found, recipients, order)), [
        Append(room, line),
        ..list.append(fan_out(recipients, order, raw), asked)
      ])
    }
    StateMessage -> {
      let order = found.next_order
      let line = record_to_string(StateRecord(order, session, raw))
      let found =
        Room(
          ..found,
          next_order: order + 1,
          log: list.append(found.log, [
            Entry(
              order: order,
              session: session,
              envelope: raw,
              state: True,
              line: line,
            ),
          ]),
          pending: Some(#(connection, order)),
          attested: "",
          // A publication answers this connection's outstanding
          // request, whatever prompted it: the room asked for a
          // state and got one, so it may ask again.
          clients: answered(found.clients, connection),
        )
      let recipients = others(found, connection)
      // No `ask_for_checkpoints` here, deliberately: a publication is the
      // answer to pressure, and asking for a checkpoint off the very
      // frame that delivers one would leave a request outstanding that
      // nothing is going to answer.
      #(store(relay, room, delivered(found, recipients, order)), [
        Append(room, line),
        ..fan_out(recipients, order, raw)
      ])
    }
  }
}

/// Whether this room can append one more durable record for this connection.
///
/// The bound is on the room, and not on the connection, because the log belongs
/// to the room. There is one exception: a `state` frame from a connection that
/// declared `Supports(checkpoint_requests)`. That frame can compact a full room,
/// and to refuse it would stop exactly the correct client that the checkpoint
/// machinery protects. A client that publishes past the bound and never attests
/// gains nothing more. The relay refuses the next append from that client that
/// is not a `state` frame, at the bound, and it closes that connection.
fn room_has_capacity(
  found: Room,
  connection: Int,
  message: MessageKind,
) -> Bool {
  case list.length(found.log) < max_room_records {
    True -> True
    False ->
      case message, dict.get(found.clients, connection) {
        StateMessage, Ok(client) -> client.supports_checkpoints
        StateMessage, Error(_)
        | HelloMessage, _
        | ChannelMessage, _
        | DeltaMessage, _
        | StateRequestMessage, _
        | DigestMessage, _
        -> False
      }
  }
}

/// This connection answered the request that the relay sent to it.
fn answered(clients: Dict(Int, Client), connection: Int) -> Dict(Int, Client) {
  case dict.get(clients, connection) {
    Error(Nil) -> clients
    Ok(client) ->
      dict.insert(
        clients,
        connection,
        Client(..client, checkpoint_requested: False),
      )
  }
}

/// Send a `CheckpointRequest` frame to one connection, if that connection is a
/// candidate for one. A candidate declared `Supports(checkpoint_requests)`, and
/// it has no request outstanding. The function does nothing for every other
/// connection, which is a connection that never declared support, and a
/// connection that still owes an answer.
///
/// The function moves `pressure_at` to the size that it quoted. The next record
/// thus does not evaluate a room that just asked.
fn send_checkpoint_request(
  found: Room,
  size: Int,
  connection: Int,
) -> #(Room, List(Action)) {
  case dict.get(found.clients, connection) {
    Ok(client) if client.supports_checkpoints && !client.checkpoint_requested -> #(
      Room(
        ..found,
        clients: dict.insert(
          found.clients,
          connection,
          Client(..client, checkpoint_requested: True),
        ),
        pressure_at: int.max(found.pressure_at, size),
        requests: found.requests + 1,
      ),
      [Send(connection, CheckpointRequest)],
    )
    Ok(_) -> #(found, [])
    Error(Nil) -> #(found, [])
  }
}

/// Ask the attached clients to checkpoint, if the room needs a checkpoint and
/// did not just ask for one.
///
/// The function is bounded and idempotent, and both properties are deliberate:
///
///   * The function asks nothing below `checkpoint_pressure_records`, so an
///     ordinary room never receives one of these frames.
///   * The function does not ask a connection that has a request with no
///     answer, so a client that answers slowly does not receive many requests.
///   * A room that asked does not ask again until its log grows another
///     `checkpoint_request_interval`. The hard bound of a flood thus also
///     bounds the frames that the flood can produce.
///   * The function asks a connection that declared
///     `Supports(checkpoint_requests)` only. A client that a developer built
///     against an earlier version of this lane thus never receives a frame that
///     it would treat as a violation.
///
/// The request carries the live log size of the room and a reason, and nothing
/// else. In particular it carries **no order**. A client answers from its own
/// merged state, so there is no path from the diagnostic sequence of a relay
/// into a document through this frame.
///
/// An append drives this function, in a room whose log still grows toward the
/// bound. A room that is already *at* the bound cannot grow, and this function
/// never asks it. That room still empties, because the ordinary attach flow ends
/// in a publication, and the relay always admits a `state` frame from a client
/// that declared support at the bound. See `room_has_capacity`.
fn ask_for_checkpoints(found: Room) -> #(Room, List(Action)) {
  let size = list.length(found.log)
  case
    size >= checkpoint_pressure_records
    && size >= found.pressure_at + checkpoint_request_interval
  {
    False -> #(found, [])
    True -> {
      let targets =
        dict.to_list(found.clients)
        |> list.filter(fn(entry) {
          { entry.1 }.supports_checkpoints && !{ entry.1 }.checkpoint_requested
        })
        |> list.map(fn(entry) { entry.0 })
        |> list.sort(int.compare)
      // The mark advances even when nobody is a candidate, so a room that
      // has asked does not re-evaluate its clients on every one of the
      // next `checkpoint_request_interval` records.
      list.fold(
        targets,
        #(Room(..found, pressure_at: size), []),
        fn(carried, connection) {
          let #(found, actions) = carried
          let #(found, more) = send_checkpoint_request(found, size, connection)
          #(found, list.append(actions, more))
        },
      )
    }
  }
}

/// An attestation: the digest of the publisher, with the highest order that the
/// publisher accounted for when it published.
///
/// The relay cannot check any of that, and it does not claim to. This is the
/// **attestation of a trusted client**, which some component authenticated
/// before it admitted that client. Admission is the trust boundary that this
/// design rests on. The relay applies every rule that it *can* apply. It clamps
/// `upTo` to the orders that it sent to this connection, and the checkpoint of a
/// publisher never retires a record that the same publisher reported as
/// skipped.
///
/// There are three kinds of entry, and the relay removes one kind only:
///
///   * **subsumed**: an entry at the clamped `upTo` or below it, or an entry
///     that the publisher wrote. The published state *claims to contain* that
///     entry, so the relay retires it.
///   * **skipped**: an entry that *this* connection reported as unreadable. The
///     published state says that it does *not* contain that entry, so the relay
///     **keeps** it, beside the checkpoint, on disk and in memory.
///   * **outstanding**: every other entry, for example a concurrent state or a
///     delta that raced the publication. The client did not account for that
///     entry, so the echo is empty and the log does not change.
///
/// A checkpoint thus never makes the history of the room shorter. It replaces
/// the entries that the publisher merged with that merge, and it carries every
/// entry that the publisher did not merge forward, without a change. A later
/// client that *can* read those entries still receives them, and the checkpoint
/// of that client, which has no skip to keep them alive, finally retires
/// them.
fn attest(
  relay: Relay,
  connection: Int,
  frame: ControlFrame,
) -> Result(#(Relay, List(Action)), Refusal) {
  use #(digest, up_to) <- result.try(case frame {
    Attest(digest, up_to) -> Ok(#(digest, up_to))
    Skip(_) -> Error(Malformed("a skip is not an attestation"))
    Supports(_) -> Error(Malformed("a support list is not an attestation"))
  })
  use #(room, client) <- result.try(
    client_of(relay, connection) |> result.replace_error(NotAdmitted),
  )
  let found = room_of(relay, room)
  let order = found.next_order
  // A client cannot have accounted for an order this relay never sent
  // it. Clamping here is what makes a stale `upTo` — from a client that
  // outlived a relay restart, and whose order sequence therefore no
  // longer means anything — harmless rather than destructive.
  let bound = int.min(up_to, client.delivered)
  case found.pending {
    Some(#(owner, state_order)) if owner == connection -> {
      let refused = set.from_list(client.skipped)
      // Reported as unmergeable by this connection, and still here.
      // Preserved verbatim: a client's claim about what it could not read
      // is never a licence to delete what somebody else wrote.
      let preserved =
        list.filter(found.log, fn(entry) {
          entry.order != state_order && set.contains(refused, entry.order)
        })
      let outstanding =
        list.filter(found.log, fn(entry) {
          entry.order != state_order
          && !set.contains(refused, entry.order)
          && entry.order > bound
          && entry.session != client.session
        })
      let checkpoint =
        list.find(found.log, fn(entry) { entry.order == state_order })
      let kept = case checkpoint {
        Ok(entry) ->
          list.append(preserved, [entry])
          |> list.sort(fn(left, right) { int.compare(left.order, right.order) })
        Error(Nil) -> []
      }
      case outstanding, checkpoint {
        [], Ok(_) -> {
          let found =
            Room(
              ..found,
              next_order: order + 1,
              log: kept,
              pending: None,
              attested: digest,
              attested_order: order,
              // The room's canonical state is the entry this attestation
              // describes, and it stays canonical — named in the durable
              // marker — until a later checkpoint replaces it.
              checkpoint_order: state_order,
              // The log just collapsed to the checkpoint and what it
              // carried, so the pressure that asked for it is spent: the
              // next round is armed by growth from here rather than from
              // wherever the log had reached.
              pressure_at: 0,
              // The claims that are spent are exactly the ones whose
              // entries have gone; the rest are still holding an entry in
              // the log and must keep holding it at the next checkpoint.
              clients: {
                let held =
                  list.fold(kept, set.new(), fn(carried, entry) {
                    set.insert(carried, entry.order)
                  })
                dict.insert(
                  found.clients,
                  connection,
                  Client(
                    ..client,
                    skipped: list.filter(client.skipped, fn(skipped) {
                      set.contains(held, skipped)
                    }),
                  ),
                )
              },
            )
          Ok(
            #(store(relay, room, found), [
              Append(
                room,
                record_to_string(DigestRecord(order, digest, state_order)),
              ),
              Compact(room, compaction_lines(found)),
              Send(connection, Attested(order, digest)),
            ]),
          )
        }
        _, _ -> {
          let found = Room(..found, next_order: order + 1, attested: "")
          Ok(
            #(store(relay, room, found), [
              Send(connection, Attested(order, "")),
            ]),
          )
        }
      }
    }
    Some(_) | None -> {
      let found = Room(..found, next_order: order + 1)
      Ok(#(store(relay, room, found), [Send(connection, Attested(order, ""))]))
    }
  }
}

fn others(room: Room, sender: Int) -> List(Int) {
  dict.keys(room.clients)
  |> list.sort(int.compare)
  |> list.filter(fn(connection) { connection != sender })
}

fn fan_out(recipients: List(Int), order: Int, raw: String) -> List(Action) {
  list.map(recipients, fn(connection) { Send(connection, Frame(order, raw)) })
}

/// Record that the relay sent everything up to `order` to these connections.
fn delivered(room: Room, recipients: List(Int), order: Int) -> Room {
  Room(
    ..room,
    clients: list.fold(recipients, room.clients, fn(clients, connection) {
      case dict.get(clients, connection) {
        Error(Nil) -> clients
        Ok(client) ->
          dict.insert(
            clients,
            connection,
            Client(..client, delivered: int.max(client.delivered, order)),
          )
      }
    }),
  )
}

fn room_of(relay: Relay, room: String) -> Room {
  case dict.get(relay.rooms, room) {
    Ok(found) -> found
    Error(Nil) -> new_room()
  }
}

fn store(relay: Relay, room: String, found: Room) -> Relay {
  Relay(..relay, rooms: dict.insert(relay.rooms, room, found))
}

// ─────────────────────────────────────────────────────────────────────────────
// Replay
// ─────────────────────────────────────────────────────────────────────────────

/// Rebuild one room from its durable lines.
///
/// This function skips a line that it cannot read, and such a line is not
/// fatal. The caller gives this module a list of lines, and the module cannot
/// separate an incomplete tail from a corrupt middle. That decision belongs to
/// the component that read the file. The reference service makes that decision
/// before it calls this function: it removes an incomplete trailing fragment and
/// refuses to start, or it quarantines the file, for every other fault. What
/// arrives here is thus already the log that the service intends to replay.
///
/// Three properties of a room that is *already* in memory never move backwards
/// when this function reads the lines:
///
///   * `next_order` only moves forward, to `max(existing, highest + 1)`. To
///     reuse an order that the relay already delivered to a live connection
///     would make the `delivered` clamp of that connection useless, and it
///     would let a later attestation retire an entry that no client saw.
///   * The function takes the **attestation** of the room from the disk only
///     when the disk proves a *current* one, which is a checkpoint marker that
///     is the newest record in the file. A record that the relay logged after a
///     checkpoint means that the checkpoint no longer describes the room.
///   * The function also takes the **canonical checkpoint entry** of the room,
///     which the marker names in its `c` field. A restart thus cannot leave the
///     room unable to say which of its `state` records is canonical. For a log
///     that a relay wrote before a marker named its entry, the function uses
///     the newest `state` record in that log.
pub fn replay(relay: Relay, room: String, lines: List(String)) -> Relay {
  // The line is kept beside the record it parsed to, so a record that
  // is later carried into a compaction leaves as the bytes this file
  // held rather than as a re-encoding of them.
  let read =
    list.filter_map(lines, fn(line) {
      string_to_record(line) |> result.map(fn(record) { #(line, record) })
    })
  let records = list.map(read, fn(pair) { pair.1 })
  let log =
    list.filter_map(read, fn(pair) {
      let #(line, record) = pair
      case record {
        StateRecord(order, session, envelope) ->
          Ok(Entry(
            order: order,
            session: session,
            envelope: envelope,
            state: True,
            line: line,
          ))
        TrafficRecord(order, session, envelope) ->
          Ok(Entry(
            order: order,
            session: session,
            envelope: envelope,
            state: False,
            line: line,
          ))
        DigestRecord(_, _, _) -> Error(Nil)
      }
    })
  let highest =
    list.fold(records, 0, fn(carried, record) {
      int.max(carried, record_order(record))
    })
  // The newest marker the file holds, whether or not it is still current.
  let marker =
    list.fold(records, None, fn(carried, record) {
      case record, carried {
        DigestRecord(order, _, _), Some(DigestRecord(held, _, _))
          if order <= held
        -> carried
        DigestRecord(_, _, _), _ -> Some(record)
        StateRecord(_, _, _), _ -> carried
        TrafficRecord(_, _, _), _ -> carried
      }
    })
  let #(attested, attested_order, marked) = case marker {
    Some(DigestRecord(order, digest, checkpoint)) if order == highest -> #(
      digest,
      order,
      checkpoint,
    )
    // A marker with anything logged after it: the digest has stopped
    // describing the room, and the entry it names is still the room's
    // canonical state.
    Some(DigestRecord(order, _, checkpoint)) -> #("", order, checkpoint)
    None -> #("", 0, 0)
    Some(StateRecord(_, _, _)) -> #("", 0, 0)
    Some(TrafficRecord(_, _, _)) -> #("", 0, 0)
  }
  let checkpoint_order = case
    marked > 0 && list.any(log, fn(entry) { entry.order == marked })
  {
    True -> marked
    // Either an older log, whose markers did not name their entry, or a
    // marker naming a record that is no longer here. The newest `state`
    // in the log is the room's best canonical answer, and pinning one
    // entry is cheap; pinning none risks a room losing the state a fresh
    // attachment rebuilds from.
    False ->
      log
      |> list.filter(fn(entry) { entry.state })
      |> list.fold(0, fn(carried, entry) { int.max(carried, entry.order) })
  }
  let existing = room_of(relay, room)
  store(
    relay,
    room,
    Room(
      ..existing,
      next_order: int.max(existing.next_order, highest + 1),
      log: log,
      pending: None,
      attested: attested,
      attested_order: attested_order,
      checkpoint_order: checkpoint_order,
      // A recovered room has asked nobody for anything yet, and a log
      // read back above the pressure mark should ask the first client
      // that attaches rather than waiting for growth it may never see.
      pressure_at: 0,
    ),
  )
}

fn record_order(record: LogRecord) -> Int {
  case record {
    StateRecord(order, _, _) -> order
    TrafficRecord(order, _, _) -> order
    DigestRecord(order, _, _) -> order
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The service seam
// ─────────────────────────────────────────────────────────────────────────────

/// The socket actions as `#(connection, payload, close_reason)` triples. A
/// `Send` action carries its encoded frame and an empty close reason. A `Close`
/// action carries an empty payload and its reason. The function keeps the order,
/// so the `error` frame of a refusal always goes out before its close.
pub fn render_sockets(actions: List(Action)) -> List(#(Int, String, String)) {
  list.filter_map(actions, fn(action) {
    case action {
      Send(connection, frame) -> Ok(#(connection, server_to_string(frame), ""))
      Close(connection, reason) -> Ok(#(connection, "", reason))
      Append(_, _) -> Error(Nil)
      Compact(_, _) -> Error(Nil)
    }
  })
}

/// The storage actions as `#(room, mode, lines)` triples, where `mode` is
/// `append` or `compact`.
///
/// The function keeps the order, and that order is the guarantee. The append
/// that carries a checkpoint always comes before the compaction that keeps that
/// checkpoint. A service that performs these actions in order, and durably,
/// thus cannot lose a record to a crash between two of them.
pub fn render_storage(
  actions: List(Action),
) -> List(#(String, String, List(String))) {
  list.filter_map(actions, fn(action) {
    case action {
      Append(room, line) -> Ok(#(room, "append", [line]))
      Compact(room, lines) -> Ok(#(room, "compact", lines))
      Send(_, _) -> Error(Nil)
      Close(_, _) -> Error(Nil)
    }
  })
}
