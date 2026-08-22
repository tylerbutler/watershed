//// Codecs for the connection-level frames and the spillway message envelopes.
//// These wire keys are unusual, and `document_channel.ex` and `session.ex`
//// confirm them:
////
//// - `ConnectMessage.document_id` maps to the wire key `id`, and not to
////   `documentId`.
//// - A sequenced op carries exactly the 9 keys that
////   `session_logic.build_sequenced_op` of spillway emits. Every other key is
////   optional.
//// - `lastSeenSequenceNumber` is an extension of floodgate to
////   `connect_document`. It is thus a separate argument, and not a field of
////   `ConnectMessage`. It is advisory only. See `encode_connect_document`.

import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}

import signet/types as token
import spillway/message.{
  type ConnectError, type ConnectMessage, type ConnectedMessage, type OpMessage,
  type SignalMessage, type SummaryContext, ConnectError, ConnectedMessage,
  OpMessage, SignalMessage, SummaryContext,
}
import spillway/nack.{type Nack, type NackContent, Nack, NackContent}
import spillway/types.{
  type Client, type ClientDetails, type ConnectionMode, type DocumentMessage,
  type SequencedDocumentMessage, type ServiceConfiguration, type SignalClient,
  Client, ClientCapabilities, ClientDetails, DocumentMessage, ReadMode,
  SequencedDocumentMessage, ServiceConfiguration, SignalClient, WriteMode,
}

import watershed/wire.{type OutboundOp}

// ─────────────────────────────────────────────────────────────────────────────
// Encoders (client → server)
// ─────────────────────────────────────────────────────────────────────────────

/// The `connect_document` payload. The server requires `tenantId`, `id`,
/// `client`, `mode`, and `token`. `versions` controls the protocol
/// negotiation.
///
/// `last_seen_sequence_number` is **advisory**, and no server uses it. This
/// documentation gave a different promise before: an automatic delta catch-up,
/// pushed as a usual `op` event. floodgate does not do that. It does not read
/// the field, and it answers a reconnect with the same full bootstrap that it
/// gives a cold join. That incorrect promise made a reconnecting client wait
/// for a delta that no server sent. The client must do its own catch-up with
/// `requestOps`. See `runtime_core.catch_up_from`. The client still sends the
/// field, because the field costs nothing and a server that did use it would
/// need it.
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

/// The `submitOp` payload: `{clientId, messageBatches}`. The server nacks a
/// submission of more than 100 ops in total. The runtime applies that limit.
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

/// The `requestOps` payload, for an in-band delta catch-up. The response
/// arrives as a usual `op` event.
pub fn encode_request_ops(from from: Int) -> Json {
  json.object([#("from", json.int(from))])
}

/// The `submitSignal` payload, for an ephemeral ripple that does not sequence.
/// It uses the V2 format that the `normalize_signal` function of levee needs:
/// a `contentBatches` list with one entry. That entry carries the application
/// `content`, which is any JSON, and a `type` tag. A ripple has no sequencing,
/// no persistence, no ack, and no catch-up.
pub fn encode_submit_ripple(
  client_id client_id: String,
  ripple_type ripple_type: String,
  content content: Json,
) -> Json {
  json.object([
    #("clientId", json.string(client_id)),
    #(
      "contentBatches",
      json.preprocessed_array([
        json.object([
          #("content", content),
          #("type", json.string(ripple_type)),
        ]),
      ]),
    ),
  ])
}

/// The `noop` heartbeat payload. It advances the MSN of the server while the
/// client is idle.
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

fn encode_user(user: token.User) -> Json {
  json.object([
    #("id", json.string(user.id)),
    ..list.map(dict.to_list(user.properties), fn(property) {
      #(property.0, wire.dynamic_to_json(property.1))
    })
  ])
}

fn encode_dynamic_dict(values: dict.Dict(String, Dynamic)) -> Json {
  json.object(
    list.map(dict.to_list(values), fn(pair) {
      #(pair.0, wire.dynamic_to_json(pair.1))
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

/// The `connect_document_success` payload.
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
    decode.list(ripple_client_decoder()),
  )
  use initial_messages <- decode.optional_field(
    "initialMessages",
    [],
    decode.list(sequenced_document_message_decoder()),
  )
  use initial_signals <- decode.optional_field(
    "initialSignals",
    [],
    decode.list(ripple_message_decoder()),
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

/// The `supportedFeatures` key that a server sets to announce the presence
/// lane.
pub const feature_presence_v1 = "presence_v1"

/// Whether the `supportedFeatures` field of a `connect_document_success`
/// message announces `feature`. The function takes the dict, and not the whole
/// message, so a runtime can answer the same question from the value that it
/// stored at handshake time.
///
/// The test is strict on purpose. The key must be present, *and* it must decode
/// as `True`. A server that does not know a feature omits the key. If this
/// function accepted a value that it cannot decode, the client would send that
/// server traffic that the server cannot answer.
pub fn supports_feature(
  features: dict.Dict(String, Dynamic),
  feature: String,
) -> Bool {
  case dict.get(features, feature) {
    Ok(value) -> decode.run(value, decode.bool) == Ok(True)
    Error(Nil) -> False
  }
}

/// The `summaryContext` sub-object of `connect_document_success`:
/// `{handle, sequenceNumber}`.
pub fn summary_context_decoder() -> Decoder(SummaryContext) {
  use handle <- decode.field("handle", decode.string)
  use sequence_number <- decode.field("sequenceNumber", decode.int)
  decode.success(SummaryContext(
    handle: handle,
    sequence_number: sequence_number,
  ))
}

/// The `connect_document_error` payload, in the HTTP form `{code, message}`.
pub fn connect_error_decoder() -> Decoder(ConnectError) {
  use code <- decode.field("code", decode.int)
  use error_message <- decode.field("message", decode.string)
  decode.success(ConnectError(code: code, message: error_message))
}

/// The `op` event payload, in the two shapes that a server can send.
///
/// levee wraps the messages: `{documentId, op: [SequencedDocumentMessage]}`.
/// floodgate pushes the bare `[SequencedDocumentMessage]` on every op path:
/// submit, join, leave, `requestOps`, and summary. It omits the document id,
/// which the channel topic already gives. This decoder accepts both shapes, so
/// one client works with either server. `document_id` is `""` for the bare
/// shape, and no caller reads it.
pub fn op_message_decoder() -> Decoder(OpMessage) {
  decode.one_of(wrapped_op_message_decoder(), [bare_op_message_decoder()])
}

fn wrapped_op_message_decoder() -> Decoder(OpMessage) {
  use document_id <- decode.field("documentId", decode.string)
  use ops <- decode.field(
    "op",
    decode.list(sequenced_document_message_decoder()),
  )
  decode.success(OpMessage(document_id: document_id, ops: ops))
}

fn bare_op_message_decoder() -> Decoder(OpMessage) {
  use ops <- decode.then(decode.list(sequenced_document_message_decoder()))
  decode.success(OpMessage(document_id: "", ops: ops))
}

/// One sequenced message, as the `session_logic.build_sequenced_op` function
/// of spillway builds it. `clientId` is null for a system message, which is a
/// join, a leave, or a summary message.
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

/// The `nack` event payload: `{clientId, nacks}`. This decoder reads the nack
/// list only.
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

/// An op that a client wrote, as a nack echoes it back.
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

pub fn token_claims_decoder() -> Decoder(token.TokenClaims) {
  use document_id <- decode.field("documentId", decode.string)
  use scopes <- decode.field("scopes", decode.list(scope_decoder()))
  use tenant_id <- decode.field("tenantId", decode.string)
  use user <- decode.field("user", user_decoder())
  use issued_at <- decode.field("iat", decode.int)
  use expiration <- decode.field("exp", decode.int)
  use version <- decode.field("ver", decode.string)
  use jti <- decode.optional_field("jti", None, decode.optional(decode.string))
  decode.success(token.TokenClaims(
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

fn scope_decoder() -> Decoder(token.Scope) {
  use value <- decode.then(decode.string)
  case token.scope_from_string(value) {
    Ok(scope) -> decode.success(scope)
    Error(_) -> decode.failure(token.DocRead, "Scope")
  }
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

fn ripple_client_decoder() -> Decoder(SignalClient) {
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

/// The decoder for an inbound `ripple` broadcast, which is a `SignalMessage`.
/// A ripple is ephemeral: the server does not sequence it, store it, or ack
/// it. `content` stays `Dynamic`, for the application to decode.
pub fn ripple_message_decoder() -> Decoder(SignalMessage) {
  use client_id <- decode.optional_field(
    "clientId",
    None,
    decode.optional(decode.string),
  )
  use content <- decode.field("content", decode.dynamic)
  use ripple_type <- decode.optional_field(
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
    signal_type: ripple_type,
    client_connection_number: client_connection_number,
    reference_sequence_number: reference_sequence_number,
    target_client_id: target_client_id,
  ))
}

/// A permissive `Client` decoder. The server echoes back the same structure
/// that the joining client sent, so a missing field takes a default value.
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
    token.User(id: "", properties: dict.new()),
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

fn user_decoder() -> Decoder(token.User) {
  use id <- decode.field("id", decode.string)
  use all_fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  decode.success(token.User(id: id, properties: dict.delete(all_fields, "id")))
}
