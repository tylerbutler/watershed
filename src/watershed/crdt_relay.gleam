//// The `crdt_relay_v1` protocol: the lane an optional sequencer opens
//// for CRDT documents, and the pure room state machine a relay runs it
//// with.
////
//// A relay is a durable fan-out point, not a sequencer for these
//// documents. It stamps a diagnostic order, keeps a log it can replay,
//// broadcasts what it accepts, and answers a `stateRequest` from what it
//// holds. It never merges, never decides which of two replicas is right,
//// and never looks inside a kernel payload: a `crdt_wire.Envelope`
//// reaches this module as an opaque string and leaves as the same
//// string, byte for byte. Only the envelope's own preamble — protocol
//// version, room, sender, session, and the message's `type` tag — is
//// ever read, which is exactly what admission and the accepted-type list
//// need and nothing more.
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
//// A client that does not see `crdt_relay_v1` treats the endpoint as a
//// relay it cannot use, which is the whole of capability negotiation.
////
//// After that the client writes **bare encoded envelope strings** —
//// `hello`, `channel`, `delta`, `stateRequest`, `state`, `digest` — and
//// nothing else on the document side. The relay writes back:
////
//// ```json
//// {"type": "frame",    "order": 12, "envelope": "<the same string>"}
//// {"type": "attested", "order": 13, "digest": "<echo, or empty>"}
//// {"type": "error",    "reason": "...", "detail": "..."}
//// ```
////
//// `order` is diagnostic. It lives outside the envelope, is never
//// rewritten into one, and a client passes it to nothing: kernels,
//// message ids, digests, and events are all computed as if it did not
//// exist.
////
//// ## Attestation, and why the client sends one extra frame
////
//// A relay that cannot merge cannot know whether the state it holds is
//// the join of everything it was given. The client can: it merges every
//// entry the relay replays, publishes the merged result, and then says
//// what it has covered.
////
//// ```json
//// {"type": "attest", "digest": "<local digest>", "upTo": 12}
//// ```
////
//// `upTo` is the highest `order` the client has *accounted for* — merged
//// into the state it just published, or reported as skipped below — and
//// it is a fact only the client holds, since the relay knows what it sent
//// and not what was made of it.
////
//// **This is an attestation by a trusted client, not a proof.** A relay
//// that never merges cannot verify it and does not try: it takes the
//// client's word that the state it published *claims to contain* the
//// entries at or below `upTo`, and retires those log entries on that
//// word. What makes that safe is not arithmetic, it is the trust
//// boundary: **admission and authentication are the checkpoint's trust
//// boundary**, and a deployment that admits a client is deciding that
//// client may check the room's log point. The reference service's
//// admission rules are bounded examples, not a security model — a real
//// deployment substitutes its own authentication and keeps everything
//// else here. Every mechanical defence that *can* be kept is still kept:
//// `upTo` is clamped to what this connection was actually sent, a
//// connection can only speak for its own room and session, and no
//// attestation ever deletes a record its author said it could not read.
////
//// If what remains after retiring is exactly the published state plus the
//// entries this client said it could not read, the relay's content and
//// the client's are the same document plus a remainder neither of them
//// has thrown away, and it echoes the digest back. Anything else — a
//// concurrent state, a delta that raced the publication — leaves the log
//// intact and the echo empty, and the client tries again after merging
//// what it missed.
////
//// This is what keeps "never pick a winning replica" and "checkpoint the
//// canonical state" from contradicting each other. Two clients attaching
//// at once publish two different states; both are logged, both are
//// broadcast, neither is refused, and the log collapses to one entry only
//// when an admitted client has claimed the one entry contains the others.
////
//// ## Refusals, and why a client may skip
////
//// A relay accepts an envelope on its preamble alone, so it can hold one
//// no client will ever merge: a delta for a channel type this build does
//// not have, a frame from a replica whose address does not name it, a
//// body that is well-formed JSON and nonsense to a kernel. Nothing on
//// the relay can detect that, and a client that simply stopped counting
//// at such an entry could never attest again — which would freeze the
//// log, the checkpoint, and every `SequencedOnly` replica in the room.
////
//// ```json
//// {"type": "skip", "order": 7}
//// ```
////
//// So a client says so, naming the exact order it refused. The relay
//// validates the claim against what it actually *sent that connection*,
//// records it against that connection alone, and lets that client's next
//// checkpoint proceed **without deleting the entry**: a skipped record is
//// written into the compaction beside the checkpoint, in order, and
//// replayed to everybody afterwards exactly as it was. A skip says "this
//// state does not contain that entry", which is a reason to carry it, not
//// a licence to drop it — so a client that cannot read something, or lies
//// about being able to, can never shorten the room's history. The entry
//// goes away when a client that *did* merge it publishes a state that
//// covers it with no skip of its own to keep it alive.
////
//// A skip for an order the connection was never sent is ignored rather
//// than honoured — it can only be a relay that stamped something it did
//// not account for, and there is nothing to carry — which is what keeps
//// "a client cannot decide the fate of an entry it never saw" true in
//// both directions.
////
//// ## The hard log bound
////
//// A room's live log stops growing at `max_room_records`. Before it gets
//// there the relay asks attached clients that declared support to
//// checkpoint (`CheckpointRequest`); at the bound, the one frame still
//// admitted is a `state` from a supports-declaring client — the answer
//// that compacts the room — and everything else durable is refused with
//// `roomAtCapacity` and its sender closed. A flood from an admitted
//// client is therefore bounded by the room, and the rest of that defence
//// — telling an attacker from a customer — belongs to the deployment
//// that admitted it, not to this module.
////
//// ## Durability
////
//// `Storage` actions are append-only JSONL lines plus whole-file
//// rewrites. A compaction is only ever emitted *after* the append that
//// carries the checkpoint it keeps, so the data is durable in its new
//// home before the old one is allowed to go away. `replay` rebuilds a
//// room from its lines, which is what makes a relay restart a merge
//// rather than a data loss.

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

/// The capability a relay must advertise for a client to use it. An
/// endpoint that omits it is a sequencer without this lane, which is a
/// status rather than a failure under `Auto`.
pub const capability = "crdt_relay_v1"

/// The largest accepted frame, in bytes, on either direction of the lane.
/// The same bound the CRDT envelope itself carries, so a frame that could
/// never hold a legal envelope is refused before it is parsed.
pub fn max_frame_bytes() -> Int {
  crdt_wire.default_limits().envelope_bytes
}

/// Clients admitted to one room. A relay is not a mesh — it fans out
/// rather than connecting everyone to everyone — so this is far higher
/// than the WebRTC room cap, and it is here to bound memory rather than
/// to shape a topology.
pub const max_room_clients = 32

/// The longest accepted room name, in UTF-8 bytes.
pub const max_room_bytes = 128

/// The longest accepted session identifier, in UTF-8 bytes. A session is
/// client-supplied, is held for the life of a connection, and is written
/// into every durable record, so it is bounded for the same reason a room
/// name is.
pub const max_session_bytes = 128

/// The most skipped orders one connection may hold at once. Skips are
/// pruned to the orders still in the room's log every time one arrives
/// and every time a checkpoint lands, and the log itself is bounded by
/// `max_room_records`, so this is a backstop rather than a rule any
/// connection is expected to meet: it is at least `max_room_records`, so
/// a client that refuses *every* entry in a completely full room is
/// still not closed for having too many claims.
///
/// It is still a real operational limit. A connection that reports one
/// more than this many live skips is closed with `tooManySkips` and has
/// to reconnect.
pub const max_client_skips = 1024

/// The hard bound on a room's *active log*, enforced **before** an
/// append rather than after it.
///
/// An admitted client alone in a room can write well-formed records
/// nobody is there to refuse, and 100 000 of them are 100 000 lines on
/// disk and 100 000 entries in this process's heap, replayed to whoever
/// attaches next. So a room's live log stops growing here. Past this
/// bound the relay first asks compatible clients to checkpoint (see
/// `checkpoint_pressure_records`), and if the log still reaches the
/// bound the *sender* of the frame that would cross it is refused with
/// `roomAtCapacity` and closed. Nothing already durable is touched: a
/// refusal at the bound writes nothing and deletes nothing.
pub const max_room_records = 1024

/// Where a room starts asking for a checkpoint instead of waiting to
/// refuse one: three quarters of `max_room_records`.
///
/// A room reaching its hard bound with an honest client attached is a
/// failure of this repository, not of the client — an ordinary editing
/// session that outruns the bound must not be cut off mid-sentence. So
/// at this mark the relay sends `CheckpointRequest` to every attached
/// client that declared it understands one, and an honest client answers
/// by publishing its merged state and attesting it, which compacts the
/// room's ordinary valid history down to that one record. The remaining
/// quarter is the headroom that request has to be answered in.
pub const checkpoint_pressure_records = 768

/// How much a room's log must grow before it asks again.
///
/// Requests are idempotent per connection — a client with one
/// outstanding is not asked twice — and re-armed only by this much
/// further growth, so a room under pressure sends at most
/// `(max_room_records - checkpoint_pressure_records) /
/// checkpoint_request_interval` rounds before it starts refusing, and a
/// client that ignores them cannot be used to generate traffic.
pub const checkpoint_request_interval = 64

// ─────────────────────────────────────────────────────────────────────────────
// Frames
// ─────────────────────────────────────────────────────────────────────────────

/// Everything a relay may say. Document traffic is carried in `Frame`
/// as the sender's own encoded envelope; every other constructor is
/// control and carries no document data at all.
pub type ServerFrame {
  /// The greeting, written the moment a socket opens. `supports` is
  /// whether the greeting advertised this lane's capability — the wire
  /// carries a capabilities object, but this client reads exactly one
  /// entry from it, so one `Bool` is what survives decoding.
  Connected(supports: Bool, envelope_bytes: Int)
  /// One relayed envelope, with the diagnostic order stamped outside it.
  Frame(order: Int, envelope: String)
  /// The end of the burst a `stateRequest` produced. Without it a client
  /// cannot tell "the relay has replayed everything it holds" from "the
  /// next entry has not arrived yet", and it would have to guess when to
  /// publish its merged state.
  Synced(order: Int)
  /// The answer to an `attest`: the client's own digest echoed back when
  /// the relay's content is exactly the state that client published, and
  /// the empty string when it is not.
  Attested(order: Int, digest: String)
  /// Publish your merged state and attest it, please.
  ///
  /// Sent only to a connection that declared it understands one (see
  /// `Supports`), only when a room's live log has crossed
  /// `checkpoint_pressure_records`, and only once per connection until
  /// that connection publishes a `state` or the log grows by another
  /// `checkpoint_request_interval`. It carries nothing at all — no
  /// order, no digest, no envelope: a client answers it out of its
  /// *own* state, and nothing a relay stamped can enter a document
  /// through it.
  CheckpointRequest
  /// A refusal. Terminal: the connection is closed after it.
  Refused(reason: String, detail: String)
}

/// Everything a client may say that is not an envelope.
pub type ControlFrame {
  Attest(digest: String, up_to: Int)
  /// One delivered order this client could not process. Never a
  /// document decision: the relay learns *that* an entry was refused and
  /// nothing about why.
  Skip(order: Int)
  /// Optional relay control features this connection understands, sent
  /// once, after the `hello` that admits it.
  ///
  /// A client that never sends this is never sent a `CheckpointRequest`,
  /// which is what makes the request safe to add to a live lane: an
  /// older client that would treat an unknown server frame as a
  /// handshake violation is never given one.
  Supports(checkpoint_requests: Bool)
}

/// One inbound frame, classified. `Envelope` keeps the raw string
/// alongside the four preamble facts admission needs, because what is
/// relayed is the string and not a re-encoding of it.
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

/// The envelope message types this lane accepts. Deliberately a closed
/// list read off the `type` tag: `error` is not on it, because a relay
/// is not a peer and has nobody to be rejected by.
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

fn message_kind_from_string(raw: String) -> Result(MessageKind, Nil) {
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

/// Why a frame was refused. Every one of these is terminal: the
/// connection is told and then closed, and the room is left exactly as it
/// was.
pub type Refusal {
  FrameTooLarge(bytes: Int)
  Malformed(detail: String)
  UnsupportedMessage(tag: String)
  /// A document frame before the `hello` that admits the connection.
  NotAdmitted
  InvalidRoom(detail: String)
  RoomFull(limit: Int)
  /// A frame whose room, sender, or session is not the one this
  /// connection was admitted with — the wrong-room client, isolated.
  IdentityChanged(detail: String)
  DuplicateSession(session: String)
  /// More outstanding skips than a connection is allowed. Bounded
  /// memory, and terminal for that connection only.
  TooManySkips(limit: Int)
  /// The room's live log is at `max_room_records` and this frame would
  /// have taken it past. Terminal for the sender and for nothing else:
  /// the room's durable records are left exactly as they are, and every
  /// other connection keeps its lane.
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

/// What a relay should do after a frame. Connections are named by the
/// integer id the service assigned them, so the state machine never holds
/// a socket, and storage is described rather than performed, so it never
/// holds a file handle either.
pub type Action {
  Send(connection: Int, frame: ServerFrame)
  /// Close a connection, after any `Send` already emitted for it.
  Close(connection: Int, reason: String)
  /// Append one JSONL line to the room's log.
  Append(room: String, line: String)
  /// Replace the room's log with exactly these lines. Only ever emitted
  /// after the `Append` that carries the checkpoint it keeps.
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

/// The greeting a compatible relay opens with.
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

/// Read only the envelope's own preamble. `message` is descended into for
/// exactly one field — its `type` tag — and its payload is never
/// touched, which is what keeps a relay out of the kernels.
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

/// Read one frame a relay sent. The client half of the same codec the
/// relay encodes with, so the two cannot drift.
///
/// A relay that stamps nothing is legal: a frame with no top-level `type`
/// is accepted as a bare envelope, and reported with order `0`.
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

/// Whether a `connected` frame advertises the lane this client speaks.
pub fn supports_relay(frame: ServerFrame) -> Bool {
  case frame {
    Connected(supports, _) -> supports
    _ -> False
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
/// A control frame is a JSON object with a top-level `type`; a document
/// frame is a v1 CRDT envelope, which has none. That is the whole of the
/// disambiguation, and it is why a relay never has to guess.
pub fn decode_client(raw: String) -> Result(ClientFrame, Refusal) {
  use _ <- result.try(case int.compare(byte_size(raw), max_frame_bytes()) {
    order.Gt -> Error(FrameTooLarge(byte_size(raw)))
    _ -> Ok(Nil)
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
    message_kind_from_string(message_type)
    |> result.replace_error(UnsupportedMessage(message_type)),
  )
  use _ <- result.try(check_shape(raw, kind))
  Ok(Document(raw: raw, room: room, from: from, session: session, message: kind))
}

/// The cheap structural checks a relay can make on a message *without*
/// decoding a kernel payload.
///
/// Everything here reads fields that name or address a message — a
/// delta's id, address and declared channel type; a channel
/// announcement's descriptor; the shape of a `state`'s channel list — and
/// nothing here touches a `contents` or a `snapshot`, which are the
/// kernel's business and stay an opaque string all the way to the log.
///
/// The checks are deliberately a *subset* of the ones `crdt_wire`'s
/// decoder makes, so a relay can never refuse an envelope a document
/// would have accepted. What they buy is that the cheapest junk — a frame
/// with a `delta` tag and no id, an address that names no channel, a
/// descriptor whose `createdBy` contradicts its own address, a `state`
/// whose channels are not a list — is refused at the socket instead of
/// being logged, replayed, and skipped by every client forever. It
/// does not make poison
/// impossible: a well-formed delta whose op is nonsense to every kernel
/// still gets in, and it always will, because the only thing that could
/// detect it is a merge.
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
        _, _ -> Ok(Nil)
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

/// A `state`'s channels must be a list. What is *in* the list is a
/// kernel's business: the elements stay dynamic here and are never
/// looked at.
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
    _, _ -> Ok(Nil)
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Durable records
// ─────────────────────────────────────────────────────────────────────────────

/// One line of a room's log.
pub type LogRecord {
  /// A full state publication. A checkpoint once it has been attested.
  StateRecord(order: Int, session: String, envelope: String)
  /// A channel announcement or a delta.
  TrafficRecord(order: Int, session: String, envelope: String)
  /// The room's checkpoint marker: the digest a client attested, and the
  /// order of the `state` record that attestation described.
  ///
  /// `checkpoint` is what survives a restart knowing *which* of a log's
  /// `state` records is the room's canonical one — the entry a
  /// `stateRequest` rebuilds from. `digest` is only current while this marker is the
  /// newest record in the file: anything logged after a checkpoint means
  /// the checkpoint has stopped describing the room, and a marker
  /// rewritten by a later compaction carries `""` to say so while still
  /// naming the canonical entry.
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

pub fn record_from_string(line: String) -> Result(LogRecord, Nil) {
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
    /// The durable line this entry was appended as, kept verbatim.
    ///
    /// A compaction rewrites every line it keeps, so holding the
    /// original is both the honest answer — the record leaves exactly
    /// as it arrived, byte for byte — and the one that does not
    /// re-encode a room's whole log to do it.
    line: String,
  )
}

type Client {
  Client(
    from: String,
    session: String,
    /// The highest order this connection has been *sent*. An attestation
    /// cannot claim to have processed further than this, whatever it
    /// says: a client that survived a relay restart is quoting a number
    /// from an order sequence that no longer exists, and this is what
    /// stops that number retiring an entry it never saw.
    delivered: Int,
    /// Orders this connection was sent and reported it could not
    /// process, still present in the log. This connection's own
    /// checkpoints are allowed to land around them — they are carried
    /// into the compaction rather than retired by it — and nobody else's
    /// claim can do that for them. A skip for an order that was never
    /// delivered never reaches this list.
    skipped: List(Int),
    /// Whether this connection said it understands a
    /// `CheckpointRequest`. Nothing is ever sent to a connection that
    /// did not, so a client written against an earlier build of this
    /// lane sees exactly the frames it always saw.
    supports_checkpoints: Bool,
    /// Whether this connection has an unanswered `CheckpointRequest`.
    /// One at a time: a room under pressure asks a client once, and asks
    /// again only after the client published a `state` or the log grew by
    /// another `checkpoint_request_interval`.
    checkpoint_requested: Bool,
  )
}

type Room {
  Room(
    /// Connection id to the identity it was admitted with.
    clients: Dict(Int, Client),
    /// The next diagnostic order to stamp.
    next_order: Int,
    /// Everything accepted and not yet subsumed by an attested state,
    /// oldest first. The *live replay lane*: what a `stateRequest`
    /// gets, and what `max_room_records` bounds.
    log: List(Entry),
    /// The connection whose `state` is awaiting an attestation, and the
    /// order that state was stamped with.
    pending: Option(#(Int, Int)),
    /// The digest attested for the current checkpoint, or `""`.
    attested: String,
    /// The order the current checkpoint's digest record was written at,
    /// so a compaction for any other reason can rewrite that line
    /// unchanged rather than dropping the room's attestation.
    attested_order: Int,
    /// The order of the `state` entry the room's checkpoint describes,
    /// or `0` for a room that has never checkpointed.
    ///
    /// This is the room's canonical state: what a `stateRequest`
    /// rebuilds from. It outlives `attested` — traffic landing after a checkpoint
    /// clears the digest, and the state that checkpoint published is
    /// still the base every later delta is read against.
    checkpoint_order: Int,
    /// The live log size the last round of `CheckpointRequest`s was sent
    /// at, or `0` for a room that has never asked. A room asks again
    /// only once its log has grown another `checkpoint_request_interval`
    /// past this, which is what bounds the requests a flood can
    /// generate.
    pressure_at: Int,
    /// How many `CheckpointRequest` frames this room has sent since the
    /// process started. Metrics only.
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
  /// `connections` maps a socket's id to the room it was admitted to;
  /// everything else about the connection lives in that room's `clients`.
  Relay(rooms: Dict(String, Room), connections: Dict(Int, String))
}

pub fn new_relay() -> Relay {
  Relay(rooms: dict.new(), connections: dict.new())
}

/// Room names currently held, sorted. A room with a log survives its last
/// client leaving — that is what makes a relay durable rather than a hub.
pub fn room_names(relay: Relay) -> List(String) {
  dict.keys(relay.rooms) |> list.sort(string.compare)
}

/// Connections admitted to a room, sorted.
pub fn clients(relay: Relay, room: String) -> List(Int) {
  case dict.get(relay.rooms, room) {
    Ok(found) -> dict.keys(found.clients) |> list.sort(int.compare)
    Error(Nil) -> []
  }
}

/// Sessions admitted to a room, sorted.
pub fn sessions(relay: Relay, room: String) -> List(String) {
  case dict.get(relay.rooms, room) {
    Ok(found) ->
      dict.values(found.clients)
      |> list.map(fn(client) { client.session })
      |> list.sort(string.compare)
    Error(Nil) -> []
  }
}

/// The next order a room will stamp. One more than the last accepted
/// frame; `1` for a room that has accepted none.
pub fn next_order(relay: Relay, room: String) -> Int {
  case dict.get(relay.rooms, room) {
    Ok(found) -> found.next_order
    Error(Nil) -> 1
  }
}

/// How many entries a room's log holds. After a successful attestation:
/// the checkpoint, plus every entry the attesting connection reported it
/// could not read — `1` for the ordinary case where there were none.
pub fn log_size(relay: Relay, room: String) -> Int {
  case dict.get(relay.rooms, room) {
    Ok(found) -> list.length(found.log)
    Error(Nil) -> 0
  }
}

/// The digest attested for the room's checkpoint, or `""` if the room has
/// never been checkpointed or has moved on since.
///
/// It describes the checkpoint *entry*, which is not always the whole
/// log: a log that also carries entries the attesting client could not
/// read holds more than this digest names, and a client that can read
/// them will hold more than it too. That is the honest reading — the
/// alternative is a digest that claims to cover records nobody has
/// merged.
pub fn attested_digest(relay: Relay, room: String) -> String {
  case dict.get(relay.rooms, room) {
    Ok(found) -> found.attested
    Error(Nil) -> ""
  }
}

/// Every envelope a `stateRequest` would replay, oldest first.
pub fn replayable(relay: Relay, room: String) -> List(String) {
  case dict.get(relay.rooms, room) {
    Ok(found) -> list.map(found.log, fn(entry) { entry.envelope })
    Error(Nil) -> []
  }
}

/// The orders one connection has reported it could not process and that
/// are still in its room's log, sorted. Diagnostic: a service exposes it
/// so an operator can see exactly which entries are being carried past a
/// checkpoint, and by whom, rather than guessing at why a room's log will
/// not collapse to one line.
pub fn skipped_orders(relay: Relay, connection: Int) -> List(Int) {
  case client_of(relay, connection) {
    Error(Nil) -> []
    Ok(#(_room, client)) -> list.sort(client.skipped, int.compare)
  }
}

/// The room and per-room record for an admitted connection. A connection
/// in `connections` is always in its room's `clients` — `admit` inserts
/// both and `disconnect` removes both — so the inner lookup asserts.
fn client_of(relay: Relay, connection: Int) -> Result(#(String, Client), Nil) {
  case dict.get(relay.connections, connection) {
    Error(Nil) -> Error(Nil)
    Ok(room) -> {
      let found = room_of(relay, room)
      let assert Ok(client) = dict.get(found.clients, connection)
      Ok(#(room, client))
    }
  }
}

/// Every order this room is carrying live: still in the log, and
/// reported unmergeable by at least one connection currently attached.
/// Sorted, oldest first, and bounded by the room's log. Diagnostic: an
/// operator reads it to see which entries checkpoints are landing
/// around, and why a room's log will not collapse to one line.
pub fn carried_orders(relay: Relay, room: String) -> List(Int) {
  case dict.get(relay.rooms, room) {
    Error(Nil) -> []
    Ok(found) -> carriage(found)
  }
}

/// The order of the `state` entry this room's checkpoint describes, or
/// `0` if it has never checkpointed. The room's canonical state: an
/// operator reads it to see what a fresh attachment would rebuild from.
pub fn checkpoint_order(relay: Relay, room: String) -> Int {
  case dict.get(relay.rooms, room) {
    Error(Nil) -> 0
    Ok(found) -> found.checkpoint_order
  }
}

/// How many `CheckpointRequest` frames this room has sent since this
/// process started. Metrics: a room whose requests climb while its log
/// stays high is a room whose clients are not answering them.
pub fn checkpoint_requests(relay: Relay, room: String) -> Int {
  case dict.get(relay.rooms, room) {
    Error(Nil) -> 0
    Ok(found) -> found.requests
  }
}

/// Connections in this room with an unanswered `CheckpointRequest`,
/// sorted.
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

/// Whether this connection told the relay it understands a
/// `CheckpointRequest`.
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

/// Every order any connection in this room has claimed it could not
/// process, as a set. A flooded room asks this once per refusal, so it is
/// deliberately not a scan of one list inside another.
fn claimed_orders(found: Room) -> set.Set(Int) {
  dict.fold(found.clients, set.new(), fn(carried, _connection, client) {
    list.fold(client.skipped, carried, fn(carried, order) {
      set.insert(carried, order)
    })
  })
}

/// The orders a room's live log holds, as a set.
fn log_orders(found: Room) -> set.Set(Int) {
  list.fold(found.log, set.new(), fn(carried, entry) {
    set.insert(carried, entry.order)
  })
}

// ─────────────────────────────────────────────────────────────────────────────
// Connection lifecycle
// ─────────────────────────────────────────────────────────────────────────────

/// A socket opened. The relay speaks first, so capability negotiation is
/// finished before a client has said anything at all.
pub fn connect(relay: Relay, connection: Int) -> #(Relay, List(Action)) {
  #(relay, [Send(connection, connected_frame())])
}

/// A socket closed, for any reason. Idempotent, and it never touches the
/// log: a room's durable content outlives every client in it.
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

/// `handle_frame`, plus the tag the frame classified as.
///
/// The tag is a relay's whole instrumentation: `hello`, `channel`,
/// `delta`, `stateRequest`, `state`, `digest`, `attest`, `skip`,
/// `skip:undelivered`, or `rejected:<reason>`. It comes from the
/// envelope's own `type` tag and from whether the relay refused the
/// frame, never from a payload.
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
    Ok(Document(raw, room, from, session, message) as frame) ->
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
              let #(relay, actions) = route(relay, connection, frame, raw)
              #(relay, actions, message_kind_to_string(message))
            }
          }
      }
  }
}

/// Whether this durable frame fits in this room's bounded live log.
///
/// Only the three message kinds that are logged are checked: a `hello`, a
/// `digest` and a `stateRequest` are stamped or answered and never
/// appended, so a room at its bound still admits clients, still answers
/// their replay, and still carries their digests — which is what lets an
/// honest client attach to a full room, refuse what it cannot read, and
/// drain it.
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

/// One control frame, and the tag it classified as.
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

/// A connection saying which optional control frames it understands.
///
/// Admitted connections only — this is a statement about a client in a
/// room, and a connection that has not said `hello` has no room to be in.
/// It stamps no order, logs nothing, and broadcasts nothing, and
/// repeating it is the same statement twice. A connection that never
/// sends it is never sent a `CheckpointRequest` — and, because a `state`
/// at the hard bound is only admitted from a supports-declaring client
/// (see `room_has_capacity`), never publishes past the bound either.
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

/// One order this connection could not process.
///
/// Honoured only if the relay actually sent that order to *this*
/// connection: a claim about anything else is about an entry this client
/// has no evidence of, and acting on it would be letting a client decide
/// the fate of something it never saw. An unhonoured skip is dropped
/// rather than fatal — a relay that stamps orders it does not account for
/// is broken, not the client talking to it, and there is nothing in the
/// log for the claim to attach to either way. A repeated skip is the same
/// claim twice and changes nothing.
///
/// A skip is a fact about delivery, never about content: the relay does
/// not learn why the entry was refused, it does not stop carrying it to
/// anyone else, and it never deletes it on the strength of one. What the
/// claim buys is that this connection's next checkpoint may land *around*
/// the entry — carried into the compaction beside it — instead of being
/// blocked by it forever. An *unhonoured* skip — undelivered, out of
/// range, or for an order the log no longer holds — changes nothing at
/// all, and a repeated skip is the same claim twice.
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

/// Every line a room's log file should hold right now: its live entries
/// in order, and the room's checkpoint marker, if it has one. A
/// compaction that dropped that marker would make a restart forget both
/// the digest a client attested and *which* of the log's `state` records
/// the room is canonically rebuilt from.
///
/// The marker carries `attested`, which is `""` once anything has landed
/// after the checkpoint. That is the honest reading: the entry is still
/// the room's canonical state, and the digest no longer describes the
/// room.
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

/// Admission and its one continuing obligation.
///
/// The first frame must be a `hello`, and it fixes the room, the sender,
/// and the session for the connection's whole life. Every later frame is
/// checked against that triple, so a client cannot change room, forge
/// another replica's identity, or reuse a session already attached — one
/// connection, one replica, one room.
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
      let found = room_of(relay, admitted_room)
      let assert Ok(client) = dict.get(found.clients, connection)
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
        _, _ -> {
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
/// `stateRequest` is answered from the log rather than forwarded: the
/// relay is the one participant that always has the room's state, and
/// asking a client for it would make every attachment a broadcast storm.
/// Everything else is stamped, logged where it is durable, and fanned out
/// to the other clients in the room — never back to its sender, which
/// already has it.
///
/// A durable frame is bounded **before** it is appended. A room's live
/// log stops at `max_room_records`, whether or not anybody has claimed
/// it cannot read those records, because the half of the flood nobody
/// has refused is still a flood: an admitted client alone in a room can
/// write well-formed traffic nobody will ever skip, and carriage — which
/// only counts refused records — would never see it. Past
/// `checkpoint_pressure_records` the relay asks compatible clients to
/// checkpoint; at the bound the sender is refused and closed, and every
/// record already on disk stays exactly as it is.
fn route(
  relay: Relay,
  connection: Int,
  frame: ClientFrame,
  raw: String,
) -> #(Relay, List(Action)) {
  let assert Document(_, room, _from, session, message) = frame
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

/// Whether this room may append one more durable record for this
/// connection.
///
/// The bound is on the room, not on the connection, because the log is
/// the room's. The single exemption is a `state` from a connection that
/// declared `Supports(checkpoint_requests)`: that is the frame that can
/// compact a full room, and refusing it would strand exactly the honest
/// client the checkpoint machinery exists to protect. A client that
/// publishes past the bound and never attests earns nothing further —
/// its next non-`state` append is refused at the bound and closed.
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
        _, _ -> False
      }
  }
}

/// This connection answered whatever it was asked.
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

/// Send one connection a `CheckpointRequest`, if it is a candidate for
/// one: it declared `Supports(checkpoint_requests)`, and it has no request
/// already outstanding. Anything else — a connection that never declared
/// support, or one still owing an answer — is a no-op.
///
/// It advances `pressure_at` to the size it quoted so the very next
/// record does not re-evaluate a room that has just asked.
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
    _ -> #(found, [])
  }
}

/// Ask attached clients to checkpoint, if the room needs one and has not
/// just asked.
///
/// Bounded and idempotent, both deliberately:
///
///   * nothing is asked below `checkpoint_pressure_records`, so an
///     ordinary room never sees one of these at all;
///   * a connection with an unanswered request is not asked again, so a
///     client that is slow to answer is not flooded with requests;
///   * a room that has asked does not ask again until its log has grown
///     another `checkpoint_request_interval`, so the frames a flood can
///     generate are bounded by the flood's own hard bound;
///   * only a connection that declared `Supports(checkpoint_requests)`
///     is asked, so a client built against an earlier version of this
///     lane is never sent a frame it would treat as a violation.
///
/// The request carries the room's live log size and a reason, and
/// nothing else. In particular it carries **no order**: a client answers
/// out of its own merged state, so there is no path from a relay's
/// diagnostic sequence into a document through it.
///
/// This is driven off an append: a room whose log is still climbing
/// toward the bound. A room already *at* the bound can climb no further
/// and is never asked from here; it drains anyway, because the ordinary
/// attach flow ends in a publication and a supports-declaring client's
/// `state` is always admitted at the bound (see `room_has_capacity`).
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

/// An attestation: the publisher's digest, and the highest order it had
/// accounted for when it published.
///
/// The relay cannot check any of this, and does not pretend to: it is a
/// **trusted client's attestation**, admitted by whatever authenticated
/// it, and admission is the trust boundary this rests on. What the relay
/// *can* enforce, it does — `upTo` is clamped to what this connection was
/// sent, and a record the publisher reported as skipped is never retired
/// by that publisher's own checkpoint.
///
/// Three kinds of entry, and only one of them goes away:
///
///   * **subsumed** — at or below the clamped `upTo`, or written by the
///     publisher itself. The published state *claims to contain* it, so
///     it is retired;
///   * **skipped** — reported by *this* connection as something it could
///     not process. The published state says it does *not* contain it, so
///     it is **kept**, beside the checkpoint, on disk and in memory;
///   * **outstanding** — anything else: a concurrent state, a delta that
///     raced the publication. The client has not accounted for it, so the
///     echo is empty and the log is left exactly as it was.
///
/// A checkpoint therefore never shortens the room's history. It replaces
/// what the publisher merged with the merge, and carries everything it
/// did not merge forward unchanged, so a later client that *can* read
/// those entries still gets them — and its own checkpoint, which has no
/// skips to keep them alive, is what finally retires them.
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
    _ -> {
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

/// Record that these connections have been sent everything up to `order`.
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
/// Unreadable lines are skipped here rather than fatal, because this
/// module is handed lines and cannot tell a torn tail from a corrupt
/// middle: that judgement belongs to whatever read the file. The
/// reference service makes it before calling this — it truncates a torn
/// trailing fragment and refuses to start, or quarantines the file, for
/// anything else — so what arrives here is already the log it means to
/// replay.
///
/// Three things about a room that is *already* here are never rewound
/// by what is read back:
///
///   * `next_order` only ever moves forward —
///     `max(existing, highest + 1)`. Reusing an order a live connection
///     has already been delivered would make its `delivered` clamp
///     meaningless and let a later attestation retire an entry nobody
///     ever saw;
///   * the room's **attestation** is taken from disk only when the disk
///     proves a *current* one: a checkpoint marker that is the newest
///     record in the file. Records logged after a checkpoint mean the
///     checkpoint has stopped describing the room;
///   * the room's **canonical checkpoint entry**, which the marker names
///     (`c`), so a restart cannot leave the room unable to say which of
///     its `state` records is canonical. A log written before markers
///     named their entry falls back to the newest `state` record it
///     holds.
pub fn replay(relay: Relay, room: String, lines: List(String)) -> Relay {
  // The line is kept beside the record it parsed to, so a record that
  // is later carried into a compaction leaves as the bytes this file
  // held rather than as a re-encoding of them.
  let read =
    list.filter_map(lines, fn(line) {
      record_from_string(line) |> result.map(fn(record) { #(line, record) })
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
        _, _ -> carried
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
    _ -> #("", 0, 0)
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

/// Socket actions as `#(connection, payload, close_reason)`. A `Send`
/// carries its encoded frame and an empty close reason; a `Close` carries
/// an empty payload and its reason. Order is preserved, so a refusal's
/// `error` frame is always written before its close.
pub fn render_sockets(actions: List(Action)) -> List(#(Int, String, String)) {
  list.filter_map(actions, fn(action) {
    case action {
      Send(connection, frame) -> Ok(#(connection, server_to_string(frame), ""))
      Close(connection, reason) -> Ok(#(connection, "", reason))
      _ -> Error(Nil)
    }
  })
}

/// Storage actions as `#(room, mode, lines)`, where `mode` is `append`
/// or `compact`.
///
/// Order is preserved, and it is the guarantee: the append that carries
/// a checkpoint always precedes the compaction that keeps it, so a
/// service that performs these in order, durably, cannot lose a record
/// to a crash between two of them.
pub fn render_storage(
  actions: List(Action),
) -> List(#(String, String, List(String))) {
  list.filter_map(actions, fn(action) {
    case action {
      Append(room, line) -> Ok(#(room, "append", [line]))
      Compact(room, lines) -> Ok(#(room, "compact", lines))
      _ -> Error(Nil)
    }
  })
}
