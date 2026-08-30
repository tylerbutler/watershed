//// Version-1 JSON envelopes for the ack-free CRDT p2p protocol.
////
//// This is the vocabulary that the WebRTC peers (P2P4) and an optional
//// sequencer relay (P2P6) both use. It is separate from the Fluid DDS wire in
//// `watershed/wire` on purpose. Nothing here carries a client sequence number,
//// a server sequence number, a reference sequence number, or an
//// acknowledgement, because the CRDT lifecycle has none of those.
////
//// Every envelope looks like:
////
//// ```json
//// {"v":1,"room":"trip-planning","from":"replica-a","session":"4e65…",
////  "message":{"type":"delta", …}}
//// ```
////
//// The encoding is deterministic. The fields go out in a fixed order, and the
//// channel entries of a `state` message are sorted by address. Two peers that
//// hold the same logical value thus produce the same JSON bytes, and thus the
//// same digest.
////
//// The decoding is a trust boundary. `decode_envelope` is total. It returns a
//// typed `p2p.P2pError` value for an oversize payload, malformed JSON, an
//// unknown message type, an unsupported or unknown channel type, a malformed
//// address, a forged descriptor, a message counter of zero or less, and a
//// payload that does not agree with its type. It never panics, and it never
//// drops a field quietly.

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
import watershed/wire/op as wire_op

/// The only protocol version that this module uses. A peer that announces any
/// other version gets a `ProtocolMismatch` error, before this module reads its
/// message.
pub const protocol_version = 1

/// The reserved root channel address. Every peer derives the root from its own
/// `Config` value, and never from a peer, so no replica owns the root.
pub const root_address = "root"

const type_hello = "hello"

const type_channel = "channel"

const type_delta = "delta"

const type_state_request = "stateRequest"

const type_state = "state"

const type_digest = "digest"

const type_error = "error"

/// The protocol limits that the trust boundary applies. `default_limits` gives
/// the version-1 defaults. Every peer derives its limits from its
/// configuration, and never from a `hello` message.
pub type Limits {
  Limits(
    /// The number of peers that one room permits. This module stores the
    /// value. The transport applies it, because only the transport counts the
    /// connections.
    room_peers: Int,
    /// The largest encoded envelope that the module accepts, in bytes.
    envelope_bytes: Int,
    /// The largest encoded channel snapshot that the module accepts, in
    /// bytes.
    snapshot_bytes: Int,
    /// The largest number of channels that one document can register.
    channels: Int,
    /// The largest number of deltas that the module buffers while it waits
    /// for their channel descriptor.
    buffered_deltas: Int,
    /// The largest number of recent message ids that the module keeps for
    /// duplicate suppression.
    recent_message_ids: Int,
  )
}

/// The version-1 default limits.
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

/// The stable identity of a message: the replica that wrote it, and the local
/// counter of that replica at the time. The module uses this identity for
/// duplicate suppression and for diagnostics only. Correctness comes from the
/// idempotent CRDT merge.
pub type MessageId {
  MessageId(replica: String, counter: Int)
}

/// An immutable fact about one channel. `address` is `root`, or it is
/// `<replica-id>:<positive-local-counter>`. For a channel that is not the
/// root, `created_by` must equal the replica prefix of the address. The
/// address carries its creator, so a mismatch is a forgery, and not a race.
pub type ChannelDescriptor {
  ChannelDescriptor(
    address: String,
    channel_type: ChannelType,
    created_by: String,
  )
}

/// A descriptor with a channel snapshot. A `channel` message, a `state`
/// message, and a canonical document snapshot all carry this pair.
pub type ChannelEntry {
  ChannelEntry(descriptor: ChannelDescriptor, snapshot: Snapshot)
}

pub type Message {
  /// The compatibility handshake: the two facts that a merge cannot
  /// reconcile if two peers disagree about them.
  Hello(compatibility: String, root: ChannelType)
  /// Announce an immutable channel descriptor with its initial snapshot.
  ChannelAnnounce(entry: ChannelEntry)
  /// Merge one channel delta.
  Delta(
    id: MessageId,
    address: String,
    channel_type: ChannelType,
    op: ChannelOp,
  )
  /// Ask a peer for its complete registry and its current snapshots.
  StateRequest
  /// A complete document that a peer can merge: every descriptor with its
  /// snapshot.
  State(entries: List(ChannelEntry))
  /// The canonical document digest, for anti-entropy.
  Digest(digest: String)
  /// Report a rejection to the peer that caused it. The name is `Rejected`
  /// here, because the wire tag `error` is also a constructor of `Result`.
  Rejected(reason: String, detail: String)
}

pub type Envelope {
  Envelope(room: String, from: String, session: String, message: Message)
}

/// The wire tag of a message, for diagnostics and for status reports.
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

/// The address of the nth channel of a replica. The address contains the
/// replica id, so two replicas cannot produce the same address, and they need
/// no coordination.
pub fn channel_address(replica: String, counter: Int) -> String {
  replica <> ":" <> int.to_string(counter)
}

/// The replica that created a channel, read from the address of that channel.
/// The root address gives `""`, because no replica creates the root.
pub fn address_creator(address: String) -> Result(String, Nil) {
  case address == root_address {
    True -> Ok("")
    False ->
      case string.split(address, ":") {
        [replica, counter] ->
          case valid_replica_id(replica), positive_counter(counter) {
            True, True -> Ok(replica)
            True, False | False, True | False, False -> Error(Nil)
          }
        _ -> Error(Nil)
      }
  }
}

/// Whether a string can identify a replica. Such a string is not empty, and it
/// contains no `:` character, because `:` separates the two halves of an
/// address.
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

/// Encode an envelope. The field order is fixed, so two equal envelopes encode
/// to two equal strings on both targets.
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
        #("contents", wire_op.encode_channel_op(op)),
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

/// The channel entries in canonical order, sorted by address. The insertion
/// order of the registry thus cannot change the encoded bytes.
///
/// The comparison is `canonical_json.compare`, and not `string.compare`. The
/// digest uses that comparison for the same reason. `string.compare` orders by
/// UTF-8 bytes on Erlang and by UTF-16 code units on JavaScript. A replica id
/// outside the basic plane would thus put the `state` messages of two peers in
/// different orders. The meaning of the message is the same in both orders.
/// The purpose is that one logical state has one encoding on both targets.
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

/// Decode one encoded envelope. The function returns a typed error for
/// anything malformed. It checks the size first, then the protocol version,
/// and then the message body. It thus never parses an oversize payload or a
/// wrong-version payload as a message.
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

/// Check one encoded channel entry, which is an element of a `state` message,
/// a `channel` announcement, or a channel of a canonical snapshot. Every
/// caller shares this function, so a snapshot from storage gets the same
/// checks as a snapshot from a peer.
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

/// The message shapes as they arrive. A channel type is still a string, and a
/// payload is still opaque JSON. To convert either one into a typed value can
/// fail in ways that a `Decoder` cannot report as a `P2pError` value.
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
          wire_op.channel_op_decoder(channel_type),
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

/// A `state` message that names one address two times has no unambiguous
/// merge, because the two entries can disagree on the type or on the creator.
/// The module thus refuses the whole message. It does not merge the entries in
/// list order.
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
    order.Lt -> Ok(Nil)
    order.Eq -> Ok(Nil)
  }
}

fn byte_size(raw: String) -> Int {
  bit_array.byte_size(<<raw:utf8>>)
}

fn invalid(from: String, detail: String) -> P2pError {
  p2p.InvalidEnvelope(from, detail)
}
