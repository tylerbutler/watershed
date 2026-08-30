//// Inverse wire codecs for the in-memory sluice.
////
//// `wire/socket.gleam` holds the *client* half of the floodgate protocol. It
//// encodes each client-to-server push, and it decodes each server-to-client
//// frame. The sluice is the server, so it needs the opposite: it decodes what
//// the client encodes, and it encodes what the client decodes. Those inverse
//// codecs are in this module.
////
//// These codecs sit beside round-trip tests against `socket`. A change in a
//// wire shape thus fails a test here, and it does not become a silent protocol
//// mismatch in production. The two modules together are the executable
//// protocol documentation that the sluice plan asks for.
////
//// The module is target-agnostic: JSON in, JSON out, and no FFI. The
//// `contents` of an operation pass through as `Json`, and never as `Dynamic`,
//// so the encode path behaves the same way on the BEAM and on JavaScript.

import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

import spillway/types.{type Client}

import watershed/presence
import watershed/wire
import watershed/wire/socket

// ─────────────────────────────────────────────────────────────────────────────
// Server-side view of one sequenced operation
// ─────────────────────────────────────────────────────────────────────────────

/// A sequenced operation, as the sluice stores it and broadcasts it. This is
/// the server-side equivalent of `types.SequencedDocumentMessage`. It keeps
/// `contents` and `metadata` as `Json`, so a re-encode needs no coercion from
/// `Dynamic`, and thus no FFI. A `client_id` of `None` marks a system message.
pub type Sequenced {
  Sequenced(
    client_id: Option(String),
    sequence_number: Int,
    minimum_sequence_number: Int,
    client_sequence_number: Int,
    reference_sequence_number: Int,
    operation_type: String,
    contents: Json,
    metadata: Option(Json),
    timestamp: Int,
    /// The payload of a system message, as JSON *text*. An operation leaves
    /// this field `None` and carries its payload in `contents`. A `"join"`
    /// message and a `"leave"` message do the opposite: `contents` is null and
    /// the payload is here. That difference comes from the server, not from
    /// this module. See `system_join_data` and `system_leave_data`.
    data: Option(String),
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Decoders: client → server (inverse of socket's encoders)
// ─────────────────────────────────────────────────────────────────────────────

/// The necessary parts of a `connect_document` push. A reconnect supplies
/// `last_seen_sequence_number`, and the delta catch-up uses it.
pub type ConnectRequest {
  ConnectRequest(
    tenant_id: String,
    document_id: String,
    client: Client,
    last_seen_sequence_number: Option(Int),
  )
}

/// One operation in a `submitOp` batch. This is the inverse of
/// `socket.encode_outbound_operation`.
pub type SubmittedOperation {
  SubmittedOperation(
    operation_type: String,
    contents: Json,
    client_sequence_number: Int,
    reference_sequence_number: Int,
    metadata: Option(Json),
  )
}

/// A complete `submitOp` push: a client id with its batches of operations.
pub type SubmitOperation {
  SubmitOperation(client_id: String, batches: List(List(SubmittedOperation)))
}

/// An ephemeral `submitSignal` push, reduced to its one content entry.
pub type SignalSubmission {
  SignalSubmission(
    client_id: String,
    content: Json,
    signal_type: Option(String),
  )
}

/// Decode a `connect_document` payload. This is the inverse of
/// `socket.encode_connect_document`.
pub fn decode_connect_document(
  payload: Dynamic,
) -> Result(ConnectRequest, String) {
  run(payload, connect_document_decoder(), "connect_document payload")
}

fn connect_document_decoder() -> Decoder(ConnectRequest) {
  use tenant_id <- decode.field("tenantId", decode.string)
  use document_id <- decode.field("id", decode.string)
  use client <- decode.field("client", socket.client_decoder())
  use last_seen <- decode.optional_field(
    "lastSeenSequenceNumber",
    None,
    decode.optional(decode.int),
  )
  decode.success(ConnectRequest(
    tenant_id: tenant_id,
    document_id: document_id,
    client: client,
    last_seen_sequence_number: last_seen,
  ))
}

/// Decode a `submitOp` payload. This is the inverse of
/// `socket.encode_submit_operation`.
pub fn decode_submit_operation(
  payload: Dynamic,
) -> Result(SubmitOperation, String) {
  run(payload, submit_operation_decoder(), "submitOp payload")
}

fn submit_operation_decoder() -> Decoder(SubmitOperation) {
  use client_id <- decode.field("clientId", decode.string)
  use batches <- decode.field(
    "messageBatches",
    decode.list(decode.list(submitted_operation_decoder())),
  )
  decode.success(SubmitOperation(client_id: client_id, batches: batches))
}

fn submitted_operation_decoder() -> Decoder(SubmittedOperation) {
  use operation_type <- decode.field("type", decode.string)
  use contents <- decode.field("contents", wire.json_value_decoder())
  use client_sequence_number <- decode.field("clientSequenceNumber", decode.int)
  use reference_sequence_number <- decode.field(
    "referenceSequenceNumber",
    decode.int,
  )
  use metadata <- decode.optional_field(
    "metadata",
    None,
    decode.optional(wire.json_value_decoder()),
  )
  decode.success(SubmittedOperation(
    operation_type: operation_type,
    contents: contents,
    client_sequence_number: client_sequence_number,
    reference_sequence_number: reference_sequence_number,
    metadata: metadata,
  ))
}

/// Decode a `requestOps` payload and return the `from` sequence number. This
/// is the inverse of `socket.encode_request_operations`.
pub fn decode_request_operations(payload: Dynamic) -> Result(Int, String) {
  run(payload, decode.field("from", decode.int, decode.success), "requestOps")
}

/// Decode a `noop` heartbeat and return `(clientId, referenceSequenceNumber)`.
/// This is the inverse of `socket.encode_noop`.
pub fn decode_noop(payload: Dynamic) -> Result(#(String, Int), String) {
  run(payload, noop_decoder(), "noop payload")
}

fn noop_decoder() -> Decoder(#(String, Int)) {
  use client_id <- decode.field("clientId", decode.string)
  use reference_sequence_number <- decode.field(
    "referenceSequenceNumber",
    decode.int,
  )
  decode.success(#(client_id, reference_sequence_number))
}

/// Decode a `submitSignal` payload and reduce it to its first content batch
/// entry. This is the inverse of `socket.encode_submit_ripple`.
pub fn decode_submit_signal(
  payload: Dynamic,
) -> Result(SignalSubmission, String) {
  run(payload, submit_signal_decoder(), "submitSignal payload")
}

fn submit_signal_decoder() -> Decoder(SignalSubmission) {
  use client_id <- decode.field("clientId", decode.string)
  use entries <- decode.field(
    "contentBatches",
    decode.list(signal_entry_decoder()),
  )
  case entries {
    [first, ..] ->
      decode.success(SignalSubmission(
        client_id: client_id,
        content: first.0,
        signal_type: first.1,
      ))
    [] ->
      decode.failure(SignalSubmission(client_id, json.null(), None), "signal")
  }
}

fn signal_entry_decoder() -> Decoder(#(Json, Option(String))) {
  use content <- decode.field("content", wire.json_value_decoder())
  use signal_type <- decode.optional_field(
    "type",
    None,
    decode.optional(decode.string),
  )
  decode.success(#(content, signal_type))
}

// ─────────────────────────────────────────────────────────────────────────────
// Encoders: server → client (inverse of socket's decoders)
// ─────────────────────────────────────────────────────────────────────────────

/// Build a `connect_document_success` payload that the
/// `socket.connected_message_decoder` function of the client accepts. It
/// carries the assigned client id, the connected roster, the catch-up
/// `initial_messages`, and the current sequence checkpoint. The sluice serves
/// no summary, which is plan decision 5, so the payload omits
/// `summaryContext`.
///
/// `initial_clients` fills the membership roster of a client, and thus the
/// quorum that its consensus kernels freeze a signoff list from. An empty
/// roster here reports no error. It makes every pact a one-member pact that
/// accepts immediately.
pub fn encode_connected(
  client_id client_id: String,
  tenant_id tenant_id: String,
  document_id document_id: String,
  scopes scopes: List(String),
  checkpoint_sequence_number checkpoint_sequence_number: Int,
  initial_clients initial_clients: List(String),
  initial_messages initial_messages: List(Sequenced),
  timestamp timestamp: Int,
  presence_v1 presence_v1: Bool,
) -> Json {
  json.object([
    #(
      "claims",
      json.object([
        #("documentId", json.string(document_id)),
        #("scopes", json.array(scopes, json.string)),
        #("tenantId", json.string(tenant_id)),
        #("user", json.object([#("id", json.string(client_id))])),
        #("iat", json.int(timestamp)),
        #("exp", json.int(timestamp + 3600)),
        #("ver", json.string("1.0")),
      ]),
    ),
    #("clientId", json.string(client_id)),
    #("existing", json.bool(True)),
    #("maxMessageSize", json.int(max_message_size)),
    #("mode", json.string("write")),
    #(
      "serviceConfiguration",
      json.object([
        #("blockSize", json.int(block_size)),
        #("maxMessageSize", json.int(max_message_size)),
      ]),
    ),
    #("initialClients", json.array(initial_clients, encode_roster_entry)),
    #("initialMessages", json.array(initial_messages, encode_sequenced)),
    #("initialSignals", json.preprocessed_array([])),
    #("supportedVersions", json.array(["1.0"], json.string)),
    #(
      "supportedFeatures",
      json.object([#(socket.feature_presence_v1, json.bool(presence_v1))]),
    ),
    #("version", json.string("1.0")),
    #("checkpointSequenceNumber", json.int(checkpoint_sequence_number)),
  ])
}

/// One `initialClients` entry. Every field of the nested `client` record is
/// optional to the decoder of the client, so the roster must carry the
/// identity only.
fn encode_roster_entry(client_id: String) -> Json {
  json.object([
    #("clientId", json.string(client_id)),
    #("client", json.object([#("mode", json.string("write"))])),
  ])
}

/// Build an `operation` event payload: the bare `[Sequenced...]` array. This is
/// the inverse of `socket.operation_message_decoder`.
///
/// floodgate pushes this shape on every operation path. levee wrapped the
/// messages in `{documentId, operation: [...]}`. The channel topic already
/// gives the document id, and the sluice models the server that watershed
/// connects to.
pub fn encode_operation_event(operations operations: List(Sequenced)) -> Json {
  json.array(operations, encode_sequenced)
}

/// Encode one sequenced operation, in the shape that
/// `socket.sequenced_document_message_decoder` accepts.
pub fn encode_sequenced(operation: Sequenced) -> Json {
  json.object(
    list.flatten([
      [
        #("clientId", json.nullable(operation.client_id, json.string)),
        #("sequenceNumber", json.int(operation.sequence_number)),
        #("minimumSequenceNumber", json.int(operation.minimum_sequence_number)),
        #("clientSequenceNumber", json.int(operation.client_sequence_number)),
        #(
          "referenceSequenceNumber",
          json.int(operation.reference_sequence_number),
        ),
        #("type", json.string(operation.operation_type)),
        #("contents", operation.contents),
        #("timestamp", json.int(operation.timestamp)),
      ],
      case operation.metadata {
        Some(metadata) -> [#("metadata", metadata)]
        None -> []
      },
      case operation.data {
        Some(data) -> [#("data", json.string(data))]
        None -> []
      },
    ]),
  )
}

/// The payload of a sequenced `"join"` message: an object that names the
/// client that arrived, serialized to JSON text. On a real server, `detail` is
/// the client record. No reader of the sluice needs that record, so the field
/// stays empty.
pub fn system_join_data(client_id: String) -> String {
  json.object([
    #("clientId", json.string(client_id)),
    #("detail", json.object([])),
  ])
  |> json.to_string
}

/// The payload of a sequenced `"leave"` message: the id of the client that
/// left, as a bare JSON string, serialized to JSON text. The shape differs
/// from `system_join_data` on purpose. That difference comes from the server,
/// and the client decodes each shape correctly.
pub fn system_leave_data(client_id: String) -> String {
  json.string(client_id) |> json.to_string
}

/// Build a `signal` broadcast. This is the inverse of
/// `socket.ripple_message_decoder`. floodgate removes the `type` field of a
/// ripple on a broadcast, for compatibility with Fluid, so this function omits
/// that field on purpose. A consumer separates the kinds by the content
/// envelope.
pub fn encode_signal(
  from_client from_client: String,
  content content: Json,
) -> Json {
  json.object([
    #("clientId", json.string(from_client)),
    #("content", content),
  ])
}

// ─────────────────────────────────────────────────────────────────────────────
// Presence (Phoenix-compatible)
// ─────────────────────────────────────────────────────────────────────────────

/// One tracked presence, as the sluice stores it. The metadata stays in
/// separate fields, and not in one `Json` value. The sluice must add `phx_ref`
/// and `client_id` beside the fields of the application on the way out, and it
/// cannot merge those keys into a `Json` value.
pub type PresenceMeta {
  PresenceMeta(key: String, phx_ref: String, fields: List(#(String, Json)))
}

/// Read the `meta` object from a `joinPresence` push or an `updatePresence`
/// push.
///
/// The metadata must be a JSON *object*. The Phoenix `metas` shape puts
/// `phx_ref` and `client_id` beside the fields of the application, and a scalar
/// or an array has no position for them. The function drops each key that the
/// server owns, and it does not trust such a key. A client cannot select its
/// own reference_sequence_number, session, or presence key.
pub fn decode_presence_meta(
  payload: Dynamic,
) -> Result(List(#(String, Json)), String) {
  use fields <- result.try(run(
    payload,
    presence_meta_decoder(),
    "presence command",
  ))
  Ok(list.filter(fields, fn(field) { !is_reserved_meta_field(field.0) }))
}

fn presence_meta_decoder() -> Decoder(List(#(String, Json))) {
  use fields <- decode.field(
    "meta",
    decode.dict(decode.string, wire.json_value_decoder()),
  )
  decode.success(dict.to_list(fields))
}

/// Whether a key that a client supplied at the top level of a presence command
/// is a key that the server owns. The sluice uses this function to refuse a
/// spoofing attempt, and not to ignore it quietly.
pub fn names_reserved_field(payload: Dynamic) -> Bool {
  case decode.run(payload, decode.dict(decode.string, decode.dynamic)) {
    Error(_) -> False
    Ok(fields) ->
      list.any(dict.keys(fields), fn(name) {
        is_reserved_meta_field(name) || name == "key"
      })
  }
}

fn is_reserved_meta_field(name: String) -> Bool {
  list.contains(presence.reserved_meta_fields, name)
  || name == "key"
  || name == "session_id"
  || name == "clientId"
}

/// A `presence_state` snapshot: `{key: {metas: [...]}}`. The keys are sorted,
/// so a test can compare two frames without a normalization step.
pub fn encode_presence_state(entries: List(#(String, PresenceMeta))) -> Json {
  encode_metas_by_key(entries)
}

/// A `presence_diff`: `{joins: {...}, leaves: {...}}`.
pub fn encode_presence_diff(
  joins joins: List(#(String, PresenceMeta)),
  leaves leaves: List(#(String, PresenceMeta)),
) -> Json {
  json.object([
    #("joins", encode_metas_by_key(joins)),
    #("leaves", encode_metas_by_key(leaves)),
  ])
}

/// A `presence_error`, which is the only failure channel of the presence lane.
/// A presence command is a push with no reply, so a rejection must arrive as
/// its own frame.
pub fn encode_presence_error(
  code code: String,
  message message: String,
) -> Json {
  json.object([
    #("code", json.string(code)),
    #("message", json.string(message)),
  ])
}

/// Group the tracked presences into `{key: {metas: [...]}}`, and add the
/// server-owned `phx_ref` and `client_id` to each meta. The entries arrive
/// keyed by session id. Several sessions can share one presence key, which is
/// how two tabs of one user appear.
fn encode_metas_by_key(entries: List(#(String, PresenceMeta))) -> Json {
  entries
  |> list.fold(dict.new(), fn(grouped, entry) {
    let #(session_id, meta) = entry
    let stamped =
      json.object([
        #("phx_ref", json.string(meta.phx_ref)),
        #("client_id", json.string(session_id)),
        ..meta.fields
      ])
    dict.upsert(grouped, meta.key, fn(existing) {
      case existing {
        Some(metas) -> [stamped, ..metas]
        None -> [stamped]
      }
    })
  })
  |> dict.to_list
  |> list.sort(fn(left, right) { string.compare(left.0, right.0) })
  |> list.map(fn(group) {
    #(
      group.0,
      json.object([
        #("metas", json.preprocessed_array(list.reverse(group.1))),
      ]),
    )
  })
  |> json.object
}

// ─────────────────────────────────────────────────────────────────────────────
// Internals
// ─────────────────────────────────────────────────────────────────────────────

/// The development defaults of floodgate. The client needs these values to be
/// present and more than zero, and nothing else.
const block_size = 65_536

const max_message_size = 16_384

fn run(
  payload: Dynamic,
  decoder: Decoder(a),
  what: String,
) -> Result(a, String) {
  decode.run(payload, decoder)
  |> result.map_error(fn(_) { "malformed " <> what })
}
