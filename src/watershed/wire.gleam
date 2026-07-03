//// Pure encoders/decoders for levee's document-channel payloads.
////
//// Types are reused from `spillway/types` and `spillway/message` so the
//// client and server can't drift; this module only owns the JSON codecs.
//// Wire-key quirks confirmed against `document_channel.ex` / `session.ex`:
////
//// - `ConnectMessage.document_id` maps to wire key `id`, not `documentId`.
//// - Sequenced ops carry exactly the 9 keys spillway's
////   `session_logic.build_sequenced_op` emits; everything else is optional.
//// - `lastSeenSequenceNumber` is a levee extension to `connect_document`
////   (triggers automatic delta catch-up), so it is a separate argument
////   rather than a `ConnectMessage` field.
////
//// Outbound client ops use the local `OutboundOp` type (with `Json`
//// contents we construct ourselves) instead of `spillway/types.
//// DocumentMessage`, whose `Dynamic` contents suit the server's parse-side.
////
//// The map op format inside the `{address, contents}` envelope is
//// byte-identical to TS `@fluidframework/map` ops (`set`/`delete`/`clear`,
//// values wrapped as `{"type": "Plain", "value": ...}`).

import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

import spillway/message.{
  type ConnectError, type ConnectMessage, type ConnectedMessage, type OpMessage,
  type SignalMessage, type SummaryContext, ConnectError, ConnectedMessage,
  OpMessage, SignalMessage, SummaryContext,
}
import spillway/nack.{type Nack, type NackContent, Nack, NackContent}
import spillway/types.{
  type Client, type ClientDetails, type ConnectionMode, type DocumentMessage,
  type SequencedDocumentMessage, type ServiceConfiguration, type SignalClient,
  type TokenClaims, type User, Client, ClientCapabilities, ClientDetails,
  DocumentMessage, ReadMode, SequencedDocumentMessage, ServiceConfiguration,
  SignalClient, TokenClaims, User, WriteMode,
}

import watershed/map_kernel.{type MapOp, Clear, Delete, Set}

// ─────────────────────────────────────────────────────────────────────────────
// Outbound op representation
// ─────────────────────────────────────────────────────────────────────────────

/// A client-authored op ready for `submitOp`. Mirrors the fields the TS
/// driver's `submitCore` puts on the wire.
pub type OutboundOp {
  OutboundOp(
    client_sequence_number: Int,
    reference_sequence_number: Int,
    op_type: String,
    contents: Json,
    metadata: Option(Json),
  )
}

// New op contents shape for M7a: either a kernel Channel op or an Attach
// envelope carrying a channel snapshot.
pub type OpContents {
  ChannelOp(address: String, op: MapOp)
  AttachOp(
    address: String,
    channel_type: String,
    snapshot: List(#(String, Json)),
  )
}

/// Wrap a kernel op in the document envelope as an outbound `"op"` message.
pub fn outbound_map_op(
  address address: String,
  client_sequence_number client_sequence_number: Int,
  reference_sequence_number reference_sequence_number: Int,
  op op: MapOp,
) -> OutboundOp {
  OutboundOp(
    client_sequence_number: client_sequence_number,
    reference_sequence_number: reference_sequence_number,
    op_type: "op",
    contents: encode_map_envelope(address, op),
    metadata: None,
  )
}

/// Attach op encoder and outbound helper. Attach envelopes carry the full
/// channel snapshot as `{type:"attach", address, channelType, snapshot}`.
pub const channel_type_map = "map"

pub fn encode_attach(
  address: String,
  channel_type: String,
  snapshot: List(#(String, Json)),
) -> Json {
  json.object([
    #("type", json.string("attach")),
    #("address", json.string(address)),
    #("channelType", json.string(channel_type)),
    #(
      "snapshot",
      json.array(snapshot, fn(entry) {
        json.object([#("key", json.string(entry.0)), #("value", entry.1)])
      }),
    ),
  ])
}

pub fn outbound_attach_op(
  address address: String,
  client_sequence_number client_sequence_number: Int,
  reference_sequence_number reference_sequence_number: Int,
  snapshot snapshot: List(#(String, Json)),
) -> OutboundOp {
  OutboundOp(
    client_sequence_number: client_sequence_number,
    reference_sequence_number: reference_sequence_number,
    op_type: "op",
    contents: encode_attach(address, channel_type_map, snapshot),
    metadata: None,
  )
}

/// A `"summarize"` op announcing a stored snapshot. Contents carry the fields
/// the server's `validate_summarize_contents` requires: `handle` (storage
/// handle for the snapshot), `message` (commit message), `parents` (parent
/// summary handles), and `head` (the git tree SHA the client uploaded). We set
/// `handle == head` so a loading client can fetch the tree directly by handle.
pub fn outbound_summarize_op(
  client_sequence_number client_sequence_number: Int,
  reference_sequence_number reference_sequence_number: Int,
  handle handle: String,
  message message: String,
  parents parents: List(String),
  head head: String,
) -> OutboundOp {
  OutboundOp(
    client_sequence_number: client_sequence_number,
    reference_sequence_number: reference_sequence_number,
    op_type: "summarize",
    contents: json.object([
      #("handle", json.string(handle)),
      #("message", json.string(message)),
      #("parents", json.array(parents, json.string)),
      #("head", json.string(head)),
    ]),
    metadata: None,
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Encoders (client → server)
// ─────────────────────────────────────────────────────────────────────────────

/// `connect_document` payload. The server requires `tenantId`, `id`,
/// `client`, `mode`, and `token`; `versions` drives protocol negotiation.
/// Pass `last_seen_sequence_number` on reconnect to get automatic delta
/// catch-up pushed as a normal `op` event.
pub fn encode_connect_document(
  msg: ConnectMessage,
  last_seen_sequence_number: Option(Int),
) -> Json {
  json.object(
    list.flatten([
      [
        #("tenantId", json.string(msg.tenant_id)),
        #("id", json.string(msg.document_id)),
        #("token", json.nullable(msg.token, json.string)),
        #("client", encode_client(msg.client)),
        #("mode", json.string(mode_to_string(msg.mode))),
        #("versions", json.array(msg.versions, json.string)),
      ],
      optional_field("driverVersion", msg.driver_version, json.string),
      optional_field("nonce", msg.nonce, json.string),
      optional_field("epoch", msg.epoch, json.string),
      case msg.supported_features {
        Some(features) -> [
          #("supportedFeatures", encode_dynamic_dict(features)),
        ]
        None -> []
      },
      optional_field("relayUserAgent", msg.relay_user_agent, json.string),
      optional_field(
        "lastSeenSequenceNumber",
        last_seen_sequence_number,
        json.int,
      ),
    ]),
  )
}

/// `submitOp` payload: `{clientId, messageBatches}`. The server nacks
/// submissions above 100 total ops; the runtime enforces that cap.
pub fn encode_submit_op(
  client_id: String,
  batches: List(List(OutboundOp)),
) -> Json {
  json.object([
    #("clientId", json.string(client_id)),
    #(
      "messageBatches",
      json.array(batches, fn(batch) { json.array(batch, encode_outbound_op) }),
    ),
  ])
}

fn encode_outbound_op(op: OutboundOp) -> Json {
  json.object(
    list.flatten([
      [
        #("type", json.string(op.op_type)),
        #("contents", op.contents),
        #("clientSequenceNumber", json.int(op.client_sequence_number)),
        #("referenceSequenceNumber", json.int(op.reference_sequence_number)),
      ],
      optional_field("metadata", op.metadata, fn(metadata) { metadata }),
    ]),
  )
}

/// `requestOps` payload for in-band delta catch-up; the response arrives as
/// a normal `op` event.
pub fn encode_request_ops(from from: Int) -> Json {
  json.object([#("from", json.int(from))])
}

/// `noop` heartbeat payload, advancing the server's MSN while idle.
pub fn encode_noop(
  client_id: String,
  reference_sequence_number reference_sequence_number: Int,
) -> Json {
  json.object([
    #("clientId", json.string(client_id)),
    #("referenceSequenceNumber", json.int(reference_sequence_number)),
  ])
}

pub fn encode_client(client: Client) -> Json {
  json.object(
    list.flatten([
      [
        #("mode", json.string(mode_to_string(client.mode))),
        #("details", encode_client_details(client.details)),
        #("permission", json.array(client.permission, json.string)),
        #("user", encode_user(client.user)),
        #("scopes", json.array(client.scopes, json.string)),
      ],
      optional_field("timestamp", client.timestamp, json.int),
    ]),
  )
}

fn encode_client_details(details: ClientDetails) -> Json {
  json.object(
    list.flatten([
      [
        #(
          "capabilities",
          json.object([
            #("interactive", json.bool(details.capabilities.interactive)),
          ]),
        ),
      ],
      optional_field("type", details.client_type, json.string),
      optional_field("environment", details.environment, json.string),
      optional_field("device", details.device, json.string),
    ]),
  )
}

fn encode_user(user: User) -> Json {
  json.object([
    #("id", json.string(user.id)),
    ..list.map(dict.to_list(user.properties), fn(property) {
      #(property.0, dynamic_to_json(property.1))
    })
  ])
}

fn encode_dynamic_dict(values: dict.Dict(String, Dynamic)) -> Json {
  json.object(
    list.map(dict.to_list(values), fn(pair) {
      #(pair.0, dynamic_to_json(pair.1))
    }),
  )
}

fn optional_field(
  key: String,
  value: Option(a),
  encode: fn(a) -> Json,
) -> List(#(String, Json)) {
  case value {
    Some(inner) -> [#(key, encode(inner))]
    None -> []
  }
}

fn mode_to_string(mode: ConnectionMode) -> String {
  case mode {
    WriteMode -> "write"
    ReadMode -> "read"
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Decoders (server → client)
// ─────────────────────────────────────────────────────────────────────────────

fn mode_decoder() -> Decoder(ConnectionMode) {
  decode.string
  |> decode.then(fn(mode) {
    case mode {
      "write" -> decode.success(WriteMode)
      "read" -> decode.success(ReadMode)
      _ -> decode.failure(WriteMode, "ConnectionMode")
    }
  })
}

/// `connect_document_success` payload.
pub fn connected_message_decoder() -> Decoder(ConnectedMessage) {
  use claims <- decode.field("claims", token_claims_decoder())
  use client_id <- decode.field("clientId", decode.string)
  use existing <- decode.optional_field("existing", True, decode.bool)
  use max_message_size <- decode.field("maxMessageSize", decode.int)
  use mode <- decode.field("mode", mode_decoder())
  use service_configuration <- decode.field(
    "serviceConfiguration",
    service_configuration_decoder(),
  )
  use initial_clients <- decode.optional_field(
    "initialClients",
    [],
    decode.list(signal_client_decoder()),
  )
  use initial_messages <- decode.optional_field(
    "initialMessages",
    [],
    decode.list(sequenced_document_message_decoder()),
  )
  use initial_signals <- decode.optional_field(
    "initialSignals",
    [],
    decode.list(signal_message_decoder()),
  )
  use supported_versions <- decode.optional_field(
    "supportedVersions",
    [],
    decode.list(decode.string),
  )
  use supported_features <- decode.optional_field(
    "supportedFeatures",
    dict.new(),
    decode.dict(decode.string, decode.dynamic),
  )
  use version <- decode.field("version", decode.string)
  use timestamp <- decode.optional_field(
    "timestamp",
    None,
    decode.optional(decode.int),
  )
  use checkpoint_sequence_number <- decode.optional_field(
    "checkpointSequenceNumber",
    None,
    decode.optional(decode.int),
  )
  use epoch <- decode.optional_field(
    "epoch",
    None,
    decode.optional(decode.string),
  )
  use relay_service_agent <- decode.optional_field(
    "relayServiceAgent",
    None,
    decode.optional(decode.string),
  )
  use summary_context <- decode.optional_field(
    "summaryContext",
    None,
    decode.optional(summary_context_decoder()),
  )
  decode.success(ConnectedMessage(
    claims: claims,
    client_id: client_id,
    existing: existing,
    max_message_size: max_message_size,
    mode: mode,
    service_configuration: service_configuration,
    initial_clients: initial_clients,
    initial_messages: initial_messages,
    initial_signals: initial_signals,
    supported_versions: supported_versions,
    supported_features: supported_features,
    version: version,
    timestamp: timestamp,
    checkpoint_sequence_number: checkpoint_sequence_number,
    epoch: epoch,
    relay_service_agent: relay_service_agent,
    summary_context: summary_context,
  ))
}

/// `summaryContext` sub-object of `connect_document_success`:
/// `{handle, sequenceNumber}`.
pub fn summary_context_decoder() -> Decoder(SummaryContext) {
  use handle <- decode.field("handle", decode.string)
  use sequence_number <- decode.field("sequenceNumber", decode.int)
  decode.success(SummaryContext(
    handle: handle,
    sequence_number: sequence_number,
  ))
}

/// `connect_document_error` payload: HTTP-style `{code, message}`.
pub fn connect_error_decoder() -> Decoder(ConnectError) {
  use code <- decode.field("code", decode.int)
  use error_message <- decode.field("message", decode.string)
  decode.success(ConnectError(code: code, message: error_message))
}

/// `op` event payload: `{documentId, op: [SequencedDocumentMessage]}`.
pub fn op_message_decoder() -> Decoder(OpMessage) {
  use document_id <- decode.field("documentId", decode.string)
  use ops <- decode.field(
    "op",
    decode.list(sequenced_document_message_decoder()),
  )
  decode.success(OpMessage(document_id: document_id, ops: ops))
}

/// One sequenced message as built by spillway's
/// `session_logic.build_sequenced_op`. `clientId` is null for system
/// messages (join/leave/summary*).
pub fn sequenced_document_message_decoder() -> Decoder(SequencedDocumentMessage) {
  use client_id <- decode.field("clientId", decode.optional(decode.string))
  use sequence_number <- decode.field("sequenceNumber", decode.int)
  use minimum_sequence_number <- decode.field(
    "minimumSequenceNumber",
    decode.int,
  )
  use client_sequence_number <- decode.field("clientSequenceNumber", decode.int)
  use reference_sequence_number <- decode.field(
    "referenceSequenceNumber",
    decode.int,
  )
  use message_type <- decode.field("type", decode.string)
  use contents <- decode.field("contents", decode.dynamic)
  use metadata <- decode.optional_field(
    "metadata",
    None,
    decode.optional(decode.dynamic),
  )
  use server_metadata <- decode.optional_field(
    "serverMetadata",
    None,
    decode.optional(decode.dynamic),
  )
  use timestamp <- decode.field("timestamp", decode.int)
  use data <- decode.optional_field(
    "data",
    None,
    decode.optional(decode.string),
  )
  decode.success(SequencedDocumentMessage(
    client_id: client_id,
    sequence_number: sequence_number,
    minimum_sequence_number: minimum_sequence_number,
    client_sequence_number: client_sequence_number,
    reference_sequence_number: reference_sequence_number,
    message_type: message_type,
    contents: contents,
    metadata: metadata,
    server_metadata: server_metadata,
    origin: None,
    traces: None,
    timestamp: timestamp,
    data: data,
  ))
}

/// `nack` event payload: `{clientId, nacks}`; decodes just the nack list.
pub fn nacks_decoder() -> Decoder(List(Nack)) {
  use nacks <- decode.field("nacks", decode.list(nack_decoder()))
  decode.success(nacks)
}

fn nack_decoder() -> Decoder(Nack) {
  use operation <- decode.optional_field(
    "operation",
    None,
    decode.optional(document_message_decoder()),
  )
  use sequence_number <- decode.field("sequenceNumber", decode.int)
  use content <- decode.field("content", nack_content_decoder())
  decode.success(Nack(
    operation: operation,
    sequence_number: sequence_number,
    content: content,
  ))
}

fn nack_content_decoder() -> Decoder(NackContent) {
  use code <- decode.field("code", decode.int)
  use error_type <- decode.field("type", nack_error_type_decoder())
  use nack_message <- decode.field("message", decode.string)
  use retry_after <- decode.optional_field(
    "retryAfter",
    None,
    decode.optional(decode.int),
  )
  decode.success(NackContent(
    code: code,
    error_type: error_type,
    message: nack_message,
    retry_after: retry_after,
  ))
}

fn nack_error_type_decoder() -> Decoder(nack.NackErrorType) {
  decode.string
  |> decode.then(fn(text) {
    case nack.nack_error_type_from_string(text) {
      Ok(error_type) -> decode.success(error_type)
      Error(Nil) -> decode.failure(nack.BadRequestError, "NackErrorType")
    }
  })
}

/// A client-authored op as echoed back inside a nack.
pub fn document_message_decoder() -> Decoder(DocumentMessage) {
  use client_sequence_number <- decode.field("clientSequenceNumber", decode.int)
  use reference_sequence_number <- decode.field(
    "referenceSequenceNumber",
    decode.int,
  )
  use message_type <- decode.field("type", decode.string)
  use contents <- decode.field("contents", decode.dynamic)
  use metadata <- decode.optional_field(
    "metadata",
    None,
    decode.optional(decode.dynamic),
  )
  use server_metadata <- decode.optional_field(
    "serverMetadata",
    None,
    decode.optional(decode.dynamic),
  )
  use compression <- decode.optional_field(
    "compression",
    None,
    decode.optional(decode.string),
  )
  decode.success(DocumentMessage(
    client_sequence_number: client_sequence_number,
    reference_sequence_number: reference_sequence_number,
    message_type: message_type,
    contents: contents,
    metadata: metadata,
    server_metadata: server_metadata,
    traces: None,
    compression: compression,
  ))
}

pub fn token_claims_decoder() -> Decoder(TokenClaims) {
  use document_id <- decode.field("documentId", decode.string)
  use scopes <- decode.field("scopes", decode.list(decode.string))
  use tenant_id <- decode.field("tenantId", decode.string)
  use user <- decode.field("user", user_decoder())
  use issued_at <- decode.field("iat", decode.int)
  use expiration <- decode.field("exp", decode.int)
  use version <- decode.field("ver", decode.string)
  use jti <- decode.optional_field("jti", None, decode.optional(decode.string))
  decode.success(TokenClaims(
    document_id: document_id,
    scopes: scopes,
    tenant_id: tenant_id,
    user: user,
    issued_at: issued_at,
    expiration: expiration,
    version: version,
    jti: jti,
  ))
}

fn service_configuration_decoder() -> Decoder(ServiceConfiguration) {
  use block_size <- decode.field("blockSize", decode.int)
  use max_message_size <- decode.field("maxMessageSize", decode.int)
  use noop_time_frequency <- decode.optional_field(
    "noopTimeFrequency",
    None,
    decode.optional(decode.int),
  )
  use noop_count_frequency <- decode.optional_field(
    "noopCountFrequency",
    None,
    decode.optional(decode.int),
  )
  decode.success(ServiceConfiguration(
    block_size: block_size,
    max_message_size: max_message_size,
    noop_time_frequency: noop_time_frequency,
    noop_count_frequency: noop_count_frequency,
  ))
}

fn signal_client_decoder() -> Decoder(SignalClient) {
  use client_id <- decode.field("clientId", decode.string)
  use client <- decode.field("client", client_decoder())
  use client_connection_number <- decode.optional_field(
    "clientConnectionNumber",
    None,
    decode.optional(decode.int),
  )
  use reference_sequence_number <- decode.optional_field(
    "referenceSequenceNumber",
    None,
    decode.optional(decode.int),
  )
  decode.success(SignalClient(
    client_id: client_id,
    client: client,
    client_connection_number: client_connection_number,
    reference_sequence_number: reference_sequence_number,
  ))
}

fn signal_message_decoder() -> Decoder(SignalMessage) {
  use client_id <- decode.optional_field(
    "clientId",
    None,
    decode.optional(decode.string),
  )
  use content <- decode.field("content", decode.dynamic)
  use signal_type <- decode.optional_field(
    "type",
    None,
    decode.optional(decode.string),
  )
  use client_connection_number <- decode.optional_field(
    "clientConnectionNumber",
    None,
    decode.optional(decode.int),
  )
  use reference_sequence_number <- decode.optional_field(
    "referenceSequenceNumber",
    None,
    decode.optional(decode.int),
  )
  use target_client_id <- decode.optional_field(
    "targetClientId",
    None,
    decode.optional(decode.string),
  )
  decode.success(SignalMessage(
    client_id: client_id,
    content: content,
    signal_type: signal_type,
    client_connection_number: client_connection_number,
    reference_sequence_number: reference_sequence_number,
    target_client_id: target_client_id,
  ))
}

/// Lenient `Client` decoder: the server echoes back whatever shape the
/// joining client sent, so missing fields fall back to sensible defaults.
pub fn client_decoder() -> Decoder(Client) {
  use mode <- decode.optional_field("mode", WriteMode, mode_decoder())
  use details <- decode.optional_field(
    "details",
    default_client_details(),
    client_details_decoder(),
  )
  use permission <- decode.optional_field(
    "permission",
    [],
    decode.list(decode.string),
  )
  use user <- decode.optional_field(
    "user",
    User(id: "", properties: dict.new()),
    user_decoder(),
  )
  use scopes <- decode.optional_field("scopes", [], decode.list(decode.string))
  use timestamp <- decode.optional_field(
    "timestamp",
    None,
    decode.optional(decode.int),
  )
  decode.success(Client(
    mode: mode,
    details: details,
    permission: permission,
    user: user,
    scopes: scopes,
    timestamp: timestamp,
  ))
}

fn default_client_details() -> ClientDetails {
  ClientDetails(
    capabilities: ClientCapabilities(interactive: True),
    client_type: None,
    environment: None,
    device: None,
  )
}

fn client_details_decoder() -> Decoder(ClientDetails) {
  use interactive <- decode.optional_field(
    "capabilities",
    True,
    decode.field("interactive", decode.bool, decode.success),
  )
  use client_type <- decode.optional_field(
    "type",
    None,
    decode.optional(decode.string),
  )
  use environment <- decode.optional_field(
    "environment",
    None,
    decode.optional(decode.string),
  )
  use device <- decode.optional_field(
    "device",
    None,
    decode.optional(decode.string),
  )
  decode.success(ClientDetails(
    capabilities: ClientCapabilities(interactive: interactive),
    client_type: client_type,
    environment: environment,
    device: device,
  ))
}

fn user_decoder() -> Decoder(User) {
  use id <- decode.field("id", decode.string)
  use all_fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  decode.success(User(id: id, properties: dict.delete(all_fields, "id")))
}

// ─────────────────────────────────────────────────────────────────────────────
// Map op envelope
// ─────────────────────────────────────────────────────────────────────────────

/// `{address, contents}` document envelope around a map op.
pub fn encode_map_envelope(address: String, op: MapOp) -> Json {
  json.object([
    #("address", json.string(address)),
    #("contents", encode_map_op(op)),
  ])
}

pub fn encode_map_op(op: MapOp) -> Json {
  case op {
    Set(key, value) ->
      json.object([
        #("type", json.string("set")),
        #("key", json.string(key)),
        #(
          "value",
          json.object([
            #("type", json.string("Plain")),
            #("value", value),
          ]),
        ),
      ])
    Delete(key) ->
      json.object([
        #("type", json.string("delete")),
        #("key", json.string(key)),
      ])
    Clear -> json.object([#("type", json.string("clear"))])
  }
}

/// Decode the `contents` of a sequenced `"op"` message into
/// `#(address, MapOp)`.
pub fn decode_map_envelope(
  contents: Dynamic,
) -> Result(#(String, MapOp), List(decode.DecodeError)) {
  decode.run(contents, map_envelope_decoder())
}

pub fn map_envelope_decoder() -> Decoder(#(String, MapOp)) {
  use address <- decode.field("address", decode.string)
  use op <- decode.field("contents", map_op_decoder())
  decode.success(#(address, op))
}

pub fn map_op_decoder() -> Decoder(MapOp) {
  use op_type <- decode.field("type", decode.string)
  case op_type {
    "set" -> {
      use key <- decode.field("key", decode.string)
      use value <- decode.field("value", plain_value_decoder())
      decode.success(Set(key, value))
    }
    "delete" -> {
      use key <- decode.field("key", decode.string)
      decode.success(Delete(key))
    }
    "clear" -> decode.success(Clear)
    _ -> decode.failure(Clear, "MapOp")
  }
}

/// `Plain` values carry an opaque kernel `Json` payload. Handle-like markers
/// (e.g., `{"type":"Shared", ...}`) are not interpreted here — they must be
/// materialized by the full runtime. We only accept `Plain` markers.
fn plain_value_decoder() -> Decoder(Json) {
  use value_type <- decode.field("type", decode.string)
  case value_type {
    "Plain" -> decode.field("value", json_value_decoder(), decode.success)
    _ -> decode.failure(json.null(), "PlainValue")
  }
}

pub fn attach_envelope_decoder() -> Decoder(OpContents) {
  use t <- decode.field("type", decode.string)
  case t {
    "attach" -> {
      use address <- decode.field("address", decode.string)
      use channel_type <- decode.field("channelType", decode.string)
      case channel_type == channel_type_map {
        True -> {
          use snapshot <- decode.field(
            "snapshot",
            decode.list(summary_entry_decoder()),
          )
          decode.success(AttachOp(
            address: address,
            channel_type: channel_type,
            snapshot: snapshot,
          ))
        }
        False ->
          decode.failure(
            AttachOp(address: "", channel_type: "", snapshot: []),
            "ChannelType",
          )
      }
    }
    _ ->
      decode.failure(
        AttachOp(address: "", channel_type: "", snapshot: []),
        "AttachEnvelope",
      )
  }
}

pub fn decode_op_contents(
  contents: Dynamic,
) -> Result(OpContents, List(decode.DecodeError)) {
  // An explicit top-level `type: "attach"` must decode as an attach envelope
  // (no fallback); anything else decodes as the map envelope.
  case decode.run(contents, decode.at(["type"], decode.string)) {
    Ok("attach") -> decode.run(contents, attach_envelope_decoder())
    _ ->
      decode.run(contents, map_envelope_decoder())
      |> result.map(fn(pair) { ChannelOp(pair.0, pair.1) })
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dynamic → Json
// ─────────────────────────────────────────────────────────────────────────────

/// Decode any parsed-JSON `Dynamic` back into a `Json` value, so decoded op
/// contents can flow into the kernel (which stores values as `Json`).
pub fn json_value_decoder() -> Decoder(Json) {
  let non_null =
    decode.one_of(decode.string |> decode.map(json.string), or: [
      decode.bool |> decode.map(json.bool),
      decode.int |> decode.map(json.int),
      decode.float |> decode.map(json.float),
      decode.list(decode.recursive(json_value_decoder))
        |> decode.map(json.preprocessed_array),
      decode.dict(decode.string, decode.recursive(json_value_decoder))
        |> decode.map(fn(object) { json.object(dict.to_list(object)) }),
    ])
  decode.optional(non_null)
  |> decode.map(fn(value) {
    case value {
      Some(inner) -> inner
      None -> json.null()
    }
  })
}

fn dynamic_to_json(value: Dynamic) -> Json {
  case decode.run(value, json_value_decoder()) {
    Ok(decoded) -> decoded
    Error(_) -> json.null()
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary snapshot blob (v2)
// ─────────────────────────────────────────────────────────────────────────────

/// Current on-disk format version for a watershed summary blob. Loaders reject
/// anything they don't recognise rather than misread a foreign snapshot.
pub const summary_blob_version = 2

pub fn encode_summary_blob_channels(
  sequence_number: Int,
  channels: List(#(String, List(#(String, Json)))),
) -> Json {
  json.object([
    #("watershedSummaryVersion", json.int(summary_blob_version)),
    #("sequenceNumber", json.int(sequence_number)),
    #(
      "channels",
      json.array(channels, fn(channel) {
        let #(address, entries) = channel
        json.object([
          #("address", json.string(address)),
          #("type", json.string(channel_type_map)),
          #(
            "entries",
            json.array(entries, fn(entry) {
              json.object([
                #("key", json.string(entry.0)),
                #("value", entry.1),
              ])
            }),
          ),
        ])
      }),
    ),
  ])
}

pub type SummaryBlob {
  SummaryBlob(sequence_number: Int, channels: List(ChannelSnapshot))
}

pub type ChannelSnapshot {
  ChannelSnapshot(
    address: String,
    channel_type: String,
    entries: List(#(String, Json)),
  )
}

/// Decode a summary blob produced by `encode_summary_blob_channels`. Reject
/// unknown versions and unknown channel types.
pub fn decode_summary_blob(
  raw: String,
) -> Result(SummaryBlob, json.DecodeError) {
  json.parse(raw, summary_blob_decoder())
}

pub fn summary_blob_decoder() -> Decoder(SummaryBlob) {
  use version <- decode.field("watershedSummaryVersion", decode.int)
  case version == summary_blob_version {
    True -> {
      use sequence_number <- decode.field("sequenceNumber", decode.int)
      use channels <- decode.field(
        "channels",
        decode.list(channel_snapshot_decoder()),
      )
      decode.success(SummaryBlob(
        sequence_number: sequence_number,
        channels: channels,
      ))
    }
    False ->
      decode.failure(
        SummaryBlob(sequence_number: 0, channels: []),
        "watershedSummaryVersion " <> int.to_string(summary_blob_version),
      )
  }
}

fn channel_snapshot_decoder() -> Decoder(ChannelSnapshot) {
  use address <- decode.field("address", decode.string)
  use channel_type <- decode.field("type", decode.string)
  // Only recognize known channel types.
  case channel_type == channel_type_map {
    True -> {
      use entries <- decode.field(
        "entries",
        decode.list(summary_entry_decoder()),
      )
      decode.success(ChannelSnapshot(
        address: address,
        channel_type: channel_type,
        entries: entries,
      ))
    }
    False ->
      decode.failure(
        ChannelSnapshot(address: "", channel_type: "", entries: []),
        "ChannelType",
      )
  }
}

fn summary_entry_decoder() -> Decoder(#(String, Json)) {
  use key <- decode.field("key", decode.string)
  use value <- decode.field("value", json_value_decoder())
  decode.success(#(key, value))
}
