//// Version-1 JSON envelopes for the ack-free CRDT p2p protocol.
////
//// This is the vocabulary WebRTC peers (P2P4) and an optional sequencer
//// relay (P2P6) both speak. It is deliberately separate from the Fluid DDS
//// wire in `watershed/wire`: nothing here carries client or server sequence
//// numbers, reference sequence numbers, or acknowledgements, because the
//// CRDT lifecycle has none.
////
//// Every envelope looks like:
////
//// ```json
//// {"v":1,"room":"trip-planning","from":"replica-a","session":"4e65…",
////  "message":{"type":"delta", …}}
//// ```
////
//// Encoding is deterministic: fields are emitted in a fixed order and
//// `state` channel entries are sorted by address, so two peers holding the
//// same logical value produce byte-identical JSON and therefore identical
//// digests.
////
//// Decoding is a trust boundary. `decode_envelope` is total: it returns a
//// typed `p2p.P2pError` for oversize payloads, malformed JSON, unknown
//// message types, unsupported or unknown channel types, malformed
//// addresses, forged descriptors, non-positive message counters, and
//// payload/type mismatches. It never panics and never silently drops a
//// field.

import gleam/bit_array
import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/order
import gleam/result
import gleam/string

import watershed/canonical_json
import watershed/channel.{type ChannelOp, type ChannelType, type Snapshot}
import watershed/p2p.{type P2pError}
import watershed/wire
import watershed/wire/ops

/// The only protocol version this module speaks. A peer announcing anything
/// else is rejected with `ProtocolMismatch` before its message is read.
pub const protocol_version = 1

/// The reserved root channel address. Every peer derives the root from its
/// own `Config` rather than learning it from a peer, so no replica ever
/// owns it.
pub const root_address = "root"

const type_hello = "hello"

const type_channel = "channel"

const type_delta = "delta"

const type_state_request = "stateRequest"

const type_state = "state"

const type_digest = "digest"

const type_error = "error"

/// Protocol limits enforced at the trust boundary. Version-one defaults
/// come from `default_limits`; every peer derives its limits from
/// configuration rather than learning them from a `hello`.
pub type Limits {
  Limits(
    /// Peers allowed in one room. Stored here; enforcing it is the
    /// transport's job, since only the transport counts connections.
    room_peers: Int,
    /// Largest accepted encoded envelope, in bytes.
    envelope_bytes: Int,
    /// Largest accepted encoded channel snapshot, in bytes.
    snapshot_bytes: Int,
    /// Most channels one document may register.
    channels: Int,
    /// Most deltas buffered while waiting for their channel descriptor.
    buffered_deltas: Int,
    /// Most recently seen message IDs kept for duplicate suppression.
    recent_message_ids: Int,
  )
}

/// The version-1 defaults.
pub fn default_limits() -> Limits {
  Limits(
    room_peers: 8,
    envelope_bytes: 262_144,
    snapshot_bytes: 4_194_304,
    channels: 1024,
    buffered_deltas: 256,
    recent_message_ids: 4096,
  )
}

/// A message's stable identity: who authored it and their local counter at
/// the time. Used for duplicate suppression and diagnostics only —
/// correctness comes from idempotent CRDT merge.
pub type MessageId {
  MessageId(replica: String, counter: Int)
}

/// An immutable fact about one channel. `address` is `root` or
/// `<replica-id>:<positive-local-counter>`, and for a non-root channel
/// `created_by` must equal the address's replica prefix — the address
/// carries its creator, so a mismatch is forgery, not a race.
pub type ChannelDescriptor {
  ChannelDescriptor(
    address: String,
    channel_type: ChannelType,
    created_by: String,
  )
}

/// A descriptor paired with a channel snapshot, as `channel` and `state`
/// messages and canonical document snapshots all carry it.
pub type ChannelEntry {
  ChannelEntry(descriptor: ChannelDescriptor, snapshot: Snapshot)
}

pub type Message {
  /// Compatibility handshake: the two facts a peer cannot merge its way
  /// out of disagreeing about.
  Hello(compatibility: String, root: ChannelType)
  /// Announce an immutable channel descriptor and its initial snapshot.
  ChannelAnnounce(entry: ChannelEntry)
  /// Merge one channel delta.
  Delta(
    id: MessageId,
    address: String,
    channel_type: ChannelType,
    op: ChannelOp,
  )
  /// Ask a peer for its whole registry and current snapshots.
  StateRequest
  /// A complete mergeable document: every descriptor with its snapshot.
  State(entries: List(ChannelEntry))
  /// The canonical document digest, for anti-entropy.
  Digest(digest: String)
  /// Report a rejection to the peer that caused it. Named `Rejected` here
  /// because the wire tag `error` collides with `Result`'s constructor.
  Rejected(reason: String, detail: String)
}

pub type Envelope {
  Envelope(room: String, from: String, session: String, message: Message)
}

/// The wire tag for a message, for diagnostics and status reporting.
pub fn message_type(message: Message) -> String {
  case message {
    Hello(..) -> type_hello
    ChannelAnnounce(_) -> type_channel
    Delta(..) -> type_delta
    StateRequest -> type_state_request
    State(_) -> type_state
    Digest(_) -> type_digest
    Rejected(..) -> type_error
  }
}

/// The address a replica's nth channel gets. Collision-free without
/// coordination because the replica ID is part of it.
pub fn channel_address(replica: String, counter: Int) -> String {
  replica <> ":" <> int.to_string(counter)
}

/// The replica that created a channel, read back out of its address. The
/// root address yields `""` — no replica creates the root.
pub fn address_creator(address: String) -> Result(String, Nil) {
  case address == root_address {
    True -> Ok("")
    False ->
      case string.split(address, ":") {
        [replica, counter] ->
          case valid_replica_id(replica), positive_counter(counter) {
            True, True -> Ok(replica)
            _, _ -> Error(Nil)
          }
        _ -> Error(Nil)
      }
  }
}

/// Whether a string can identify a replica: non-empty, and free of the `:`
/// that separates an address's two halves.
pub fn valid_replica_id(replica: String) -> Bool {
  replica != "" && !string.contains(replica, ":")
}

fn positive_counter(raw: String) -> Bool {
  case int.parse(raw) {
    // `int.to_string` round-trip rejects "+1", "01", and " 1", so one
    // logical channel can never be named by two different addresses.
    Ok(value) -> value > 0 && int.to_string(value) == raw
    Error(_) -> False
  }
}

// --- encoding -------------------------------------------------------------

/// Encode an envelope. Field order is fixed, so equal envelopes encode to
/// equal strings on both targets.
pub fn encode_envelope(envelope: Envelope) -> Json {
  json.object([
    #("v", json.int(protocol_version)),
    #("room", json.string(envelope.room)),
    #("from", json.string(envelope.from)),
    #("session", json.string(envelope.session)),
    #("message", encode_message(envelope.message)),
  ])
}

pub fn envelope_to_string(envelope: Envelope) -> String {
  json.to_string(encode_envelope(envelope))
}

pub fn encode_message(message: Message) -> Json {
  case message {
    Hello(compatibility, root) ->
      json.object([
        #("type", json.string(type_hello)),
        #("compatibility", json.string(compatibility)),
        #("root", json.string(channel.type_to_string(root))),
      ])
    ChannelAnnounce(entry) ->
      json.object([
        #("type", json.string(type_channel)),
        #("descriptor", encode_descriptor(entry.descriptor)),
        #("snapshot", channel.encode_snapshot(entry.snapshot)),
      ])
    Delta(id, address, channel_type, op) ->
      json.object([
        #("type", json.string(type_delta)),
        #("id", encode_message_id(id)),
        #("address", json.string(address)),
        #("channelType", json.string(channel.type_to_string(channel_type))),
        #("contents", ops.encode_channel_op(op)),
      ])
    StateRequest -> json.object([#("type", json.string(type_state_request))])
    State(entries) ->
      json.object([
        #("type", json.string(type_state)),
        #("channels", json.array(sort_entries(entries), encode_channel_entry)),
      ])
    Digest(digest) ->
      json.object([
        #("type", json.string(type_digest)),
        #("digest", json.string(digest)),
      ])
    Rejected(reason, detail) ->
      json.object([
        #("type", json.string(type_error)),
        #("reason", json.string(reason)),
        #("detail", json.string(detail)),
      ])
  }
}

/// Channel entries in canonical order: sorted by address, so registry
/// insertion order cannot change the encoded bytes.
///
/// The comparison is `canonical_json.compare`, not `string.compare`, for
/// the same reason the digest uses it — `string.compare` orders by UTF-8
/// bytes on Erlang and by UTF-16 code units on JavaScript, so a replica id
/// outside the basic plane puts two peers' `state` messages in different
/// orders. Nothing about the message's meaning changes either way; the
/// point is that one logical state has one encoding on both targets.
pub fn sort_entries(entries: List(ChannelEntry)) -> List(ChannelEntry) {
  list.sort(entries, fn(left, right) {
    canonical_json.compare(left.descriptor.address, right.descriptor.address)
  })
}

pub fn encode_channel_entry(entry: ChannelEntry) -> Json {
  json.object([
    #("descriptor", encode_descriptor(entry.descriptor)),
    #("snapshot", channel.encode_snapshot(entry.snapshot)),
  ])
}

pub fn encode_descriptor(descriptor: ChannelDescriptor) -> Json {
  json.object([
    #("address", json.string(descriptor.address)),
    #(
      "channelType",
      json.string(channel.type_to_string(descriptor.channel_type)),
    ),
    #("createdBy", json.string(descriptor.created_by)),
  ])
}

fn encode_message_id(id: MessageId) -> Json {
  json.preprocessed_array([json.string(id.replica), json.int(id.counter)])
}

// --- decoding -------------------------------------------------------------

/// Decode one encoded envelope, rejecting anything malformed with a typed
/// error. Size is checked first, then the protocol version, then the
/// message body — so an oversize or wrong-version payload is never parsed
/// as a message at all.
pub fn decode_envelope(
  raw: String,
  limits: Limits,
) -> Result(Envelope, P2pError) {
  use _ <- result.try(
    check_size(byte_size(raw), limits.envelope_bytes, fn(bytes, limit) {
      invalid(
        "",
        "envelope of "
          <> int.to_string(bytes)
          <> " bytes exceeds the "
          <> int.to_string(limit)
          <> " byte limit",
      )
    }),
  )
  use preamble <- result.try(
    json.parse(raw, preamble_decoder())
    |> result.replace_error(invalid("", "envelope is not a v1 CRDT envelope")),
  )
  let Preamble(version, room, from, session, message) = preamble
  use _ <- result.try(case version == protocol_version {
    True -> Ok(Nil)
    False -> Error(p2p.ProtocolMismatch(protocol_version, version))
  })
  use _ <- result.try(case valid_replica_id(from) && session != "" {
    True -> Ok(Nil)
    False -> Error(invalid(from, "envelope has no usable sender identity"))
  })
  use raw_message <- result.try(
    json.parse(json.to_string(message), raw_message_decoder())
    |> result.replace_error(invalid(from, "message is not a v1 CRDT message")),
  )
  use message <- result.try(validate_message(raw_message, from, limits))
  Ok(Envelope(room: room, from: from, session: session, message: message))
}

/// Validate one encoded channel entry — a `state` message's element, a
/// `channel` announcement, or a canonical snapshot's channel. Shared so a
/// snapshot loaded from disk faces exactly the same checks as one that
/// arrived from a peer.
pub fn decode_channel_entry(
  value: Json,
  from: String,
  limits: Limits,
) -> Result(ChannelEntry, P2pError) {
  use raw <- result.try(
    json.parse(json.to_string(value), raw_entry_decoder())
    |> result.replace_error(invalid(from, "malformed channel entry")),
  )
  validate_entry(raw, from, limits)
}

type Preamble {
  Preamble(
    version: Int,
    room: String,
    from: String,
    session: String,
    message: Json,
  )
}

fn preamble_decoder() -> Decoder(Preamble) {
  use version <- decode.field("v", decode.int)
  use room <- decode.field("room", decode.string)
  use from <- decode.field("from", decode.string)
  use session <- decode.field("session", decode.string)
  use message <- decode.field("message", wire.json_value_decoder())
  decode.success(Preamble(version, room, from, session, message))
}

/// The message shapes as they arrive: channel types are still strings and
/// payloads are still opaque JSON, because turning either into a typed
/// value can fail in ways a `Decoder` cannot report as a `P2pError`.
type RawMessage {
  RawHello(compatibility: String, root: String)
  RawChannel(entry: RawEntry)
  RawDelta(
    replica: String,
    counter: Int,
    address: String,
    channel_type: String,
    contents: Json,
  )
  RawStateRequest
  RawState(entries: List(Json))
  RawDigest(digest: String)
  RawRejected(reason: String, detail: String)
}

type RawEntry {
  RawEntry(
    address: String,
    channel_type: String,
    created_by: String,
    snapshot: Json,
  )
}

fn raw_message_decoder() -> Decoder(RawMessage) {
  use tag <- decode.field("type", decode.string)
  case tag {
    _ if tag == type_hello -> {
      use compatibility <- decode.field("compatibility", decode.string)
      use root <- decode.field("root", decode.string)
      decode.success(RawHello(compatibility, root))
    }
    _ if tag == type_channel -> {
      use entry <- decode.then(raw_entry_decoder())
      decode.success(RawChannel(entry))
    }
    _ if tag == type_delta -> {
      use id <- decode.field("id", message_id_decoder())
      use address <- decode.field("address", decode.string)
      use channel_type <- decode.field("channelType", decode.string)
      use contents <- decode.field("contents", wire.json_value_decoder())
      let #(replica, counter) = id
      decode.success(RawDelta(replica, counter, address, channel_type, contents))
    }
    _ if tag == type_state_request -> decode.success(RawStateRequest)
    _ if tag == type_state -> {
      use entries <- decode.field(
        "channels",
        decode.list(wire.json_value_decoder()),
      )
      decode.success(RawState(entries))
    }
    _ if tag == type_digest -> {
      use digest <- decode.field("digest", decode.string)
      decode.success(RawDigest(digest))
    }
    _ if tag == type_error -> {
      use reason <- decode.field("reason", decode.string)
      use detail <- decode.field("detail", decode.string)
      decode.success(RawRejected(reason, detail))
    }
    _ -> decode.failure(RawStateRequest, "CrdtMessage")
  }
}

fn raw_entry_decoder() -> Decoder(RawEntry) {
  use address <- decode.subfield(["descriptor", "address"], decode.string)
  use channel_type <- decode.subfield(
    ["descriptor", "channelType"],
    decode.string,
  )
  use created_by <- decode.subfield(["descriptor", "createdBy"], decode.string)
  use snapshot <- decode.field("snapshot", wire.json_value_decoder())
  decode.success(RawEntry(address, channel_type, created_by, snapshot))
}

fn message_id_decoder() -> Decoder(#(String, Int)) {
  use elements <- decode.then(decode.list(decode.dynamic))
  case elements {
    // Exactly two elements, decoded in place — anything longer, shorter,
    // or transposed fails here.
    [_, _] -> {
      use replica <- decode.subfield([0], decode.string)
      use counter <- decode.subfield([1], decode.int)
      decode.success(#(replica, counter))
    }
    _ -> decode.failure(#("", 0), "MessageId")
  }
}

fn validate_message(
  raw: RawMessage,
  from: String,
  limits: Limits,
) -> Result(Message, P2pError) {
  case raw {
    RawHello(compatibility, root) -> {
      use root <- result.try(eligible_type(root, from))
      Ok(Hello(compatibility, root))
    }
    RawChannel(entry) -> {
      use entry <- result.try(validate_entry(entry, from, limits))
      Ok(ChannelAnnounce(entry))
    }
    RawDelta(replica, counter, address, channel_type, contents) -> {
      // Counters start at 1, matching the `> 0` rule addresses enforce.
      use _ <- result.try(case valid_replica_id(replica) && counter > 0 {
        True -> Ok(Nil)
        False -> Error(invalid(from, "delta has an invalid message id"))
      })
      use _ <- result.try(
        address_creator(address)
        |> result.replace_error(invalid(
          from,
          "delta names the invalid address " <> address,
        )),
      )
      use channel_type <- result.try(eligible_type(channel_type, from))
      use op <- result.try(
        json.parse(
          json.to_string(contents),
          ops.channel_op_decoder(channel_type),
        )
        |> result.replace_error(invalid(
          from,
          "delta contents do not match channel type "
            <> channel.type_to_string(channel_type),
        )),
      )
      Ok(Delta(MessageId(replica, counter), address, channel_type, op))
    }
    RawStateRequest -> Ok(StateRequest)
    RawState(entries) -> {
      use entries <- result.try(
        list.try_map(entries, fn(entry) {
          decode_channel_entry(entry, from, limits)
        }),
      )
      use _ <- result.try(check_unique_addresses(entries, from))
      Ok(State(entries))
    }
    RawDigest(digest) -> Ok(Digest(digest))
    RawRejected(reason, detail) -> Ok(Rejected(reason, detail))
  }
}

fn validate_entry(
  raw: RawEntry,
  from: String,
  limits: Limits,
) -> Result(ChannelEntry, P2pError) {
  use creator <- result.try(
    address_creator(raw.address)
    |> result.replace_error(invalid(
      from,
      "channel names the invalid address " <> raw.address,
    )),
  )
  use _ <- result.try(case creator == raw.created_by {
    True -> Ok(Nil)
    False ->
      Error(invalid(
        from,
        "channel "
          <> raw.address
          <> " claims creator "
          <> raw.created_by
          <> " but its address names "
          <> creator,
      ))
  })
  use channel_type <- result.try(eligible_type(raw.channel_type, from))
  let encoded = json.to_string(raw.snapshot)
  use _ <- result.try(check_size(
    byte_size(encoded),
    limits.snapshot_bytes,
    p2p.SnapshotTooLarge,
  ))
  use snapshot <- result.try(
    json.parse(encoded, channel.snapshot_decoder(channel_type))
    |> result.replace_error(invalid(
      from,
      "snapshot for "
        <> raw.address
        <> " does not match channel type "
        <> channel.type_to_string(channel_type),
    )),
  )
  Ok(ChannelEntry(
    descriptor: ChannelDescriptor(
      address: raw.address,
      channel_type: channel_type,
      created_by: raw.created_by,
    ),
    snapshot: snapshot,
  ))
}

/// A `state` message naming one address twice cannot be merged
/// unambiguously — the two entries could disagree on type or creator — so
/// it is rejected whole rather than merged in list order.
fn check_unique_addresses(
  entries: List(ChannelEntry),
  from: String,
) -> Result(Nil, P2pError) {
  let addresses =
    list.map(entries, fn(entry) { entry.descriptor.address })
    |> list.sort(canonical_json.compare)
  let duplicated =
    list.window_by_2(addresses)
    |> list.any(fn(pair) { pair.0 == pair.1 })
  case duplicated {
    False -> Ok(Nil)
    True -> Error(invalid(from, "state repeats a channel address"))
  }
}

fn eligible_type(raw: String, from: String) -> Result(ChannelType, P2pError) {
  case channel.type_from_string(raw) {
    Error(_) -> Error(invalid(from, "unknown channel type " <> raw))
    Ok(channel_type) -> p2p.validate(channel_type)
  }
}

fn check_size(
  bytes: Int,
  limit: Int,
  to_error: fn(Int, Int) -> P2pError,
) -> Result(Nil, P2pError) {
  case int.compare(bytes, limit) {
    order.Gt -> Error(to_error(bytes, limit))
    _ -> Ok(Nil)
  }
}

fn byte_size(raw: String) -> Int {
  bit_array.byte_size(<<raw:utf8>>)
}

fn invalid(from: String, detail: String) -> P2pError {
  p2p.InvalidEnvelope(from, detail)
}
