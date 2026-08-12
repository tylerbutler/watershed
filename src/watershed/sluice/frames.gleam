//// Inverse wire codecs for the in-memory sluice.
////
//// `wire/socket.gleam` holds the *client's* half of the floodgate protocol: it
//// encodes client→server pushes and decodes server→client frames. The sluice is
//// the server, so it needs the mirror image — decode what the client encodes,
//// encode what the client decodes. Those inverse codecs live here.
////
//// Keeping them beside round-trip tests against `socket` means a wire-shape
//// drift surfaces as a failing test here rather than as a silent protocol
//// mismatch in production. The two modules together are the executable
//// protocol documentation the sluice plan calls for.
////
//// Target-agnostic: pure JSON in, pure JSON out, no FFI. Op `contents` flow
//// through as `Json` (never `Dynamic`), so the encode path works identically
//// on BEAM and JavaScript.

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
// Server-side view of one sequenced op
// ─────────────────────────────────────────────────────────────────────────────

/// A sequenced op as the sluice stores and broadcasts it — the server-side twin
/// of `types.SequencedDocumentMessage`, but with `contents`/`metadata` kept as
/// `Json` so re-encoding needs no `Dynamic` coercion (and thus no FFI). A
/// `None` `client_id` marks a system message.
pub type Sequenced {
  Sequenced(
    client_id: Option(String),
    sequence_number: Int,
    minimum_sequence_number: Int,
    client_sequence_number: Int,
    reference_sequence_number: Int,
    op_type: String,
    contents: Json,
    metadata: Option(Json),
    timestamp: Int,
    /// System-message payload, as JSON *text*. Ops leave this `None` and carry
    /// their payload in `contents`; `"join"` / `"leave"` are the other way
    /// round — `contents` is null and the payload rides here. That split is the
    /// server's, not ours (see `system_join_data` / `system_leave_data`).
    data: Option(String),
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Decoders: client → server (inverse of socket's encoders)
// ─────────────────────────────────────────────────────────────────────────────

/// The essentials of a `connect_document` push. `last_seen_sequence_number` is
/// present on reconnect and drives delta catch-up.
pub type ConnectRequest {
  ConnectRequest(
    tenant_id: String,
    document_id: String,
    client: Client,
    last_seen_sequence_number: Option(Int),
  )
}

/// One op inside a `submitOp` batch (inverse of `socket.encode_outbound_op`).
pub type SubmittedOp {
  SubmittedOp(
    op_type: String,
    contents: Json,
    client_sequence_number: Int,
    reference_sequence_number: Int,
    metadata: Option(Json),
  )
}

/// A whole `submitOp` push: a client id plus its batches of ops.
pub type SubmitOp {
  SubmitOp(client_id: String, batches: List(List(SubmittedOp)))
}

/// An ephemeral `submitSignal` push, flattened to its single content entry.
pub type SignalSubmission {
  SignalSubmission(
    client_id: String,
    content: Json,
    signal_type: Option(String),
  )
}

/// Decode a `connect_document` payload (inverse of
/// `socket.encode_connect_document`).
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

/// Decode a `submitOp` payload (inverse of `socket.encode_submit_op`).
pub fn decode_submit_op(payload: Dynamic) -> Result(SubmitOp, String) {
  run(payload, submit_op_decoder(), "submitOp payload")
}

fn submit_op_decoder() -> Decoder(SubmitOp) {
  use client_id <- decode.field("clientId", decode.string)
  use batches <- decode.field(
    "messageBatches",
    decode.list(decode.list(submitted_op_decoder())),
  )
  decode.success(SubmitOp(client_id: client_id, batches: batches))
}

fn submitted_op_decoder() -> Decoder(SubmittedOp) {
  use op_type <- decode.field("type", decode.string)
  use contents <- decode.field("contents", wire.json_value_decoder())
  use csn <- decode.field("clientSequenceNumber", decode.int)
  use rsn <- decode.field("referenceSequenceNumber", decode.int)
  use metadata <- decode.optional_field(
    "metadata",
    None,
    decode.optional(wire.json_value_decoder()),
  )
  decode.success(SubmittedOp(
    op_type: op_type,
    contents: contents,
    client_sequence_number: csn,
    reference_sequence_number: rsn,
    metadata: metadata,
  ))
}

/// Decode a `requestOps` payload, returning the `from` sequence number
/// (inverse of `socket.encode_request_ops`).
pub fn decode_request_ops(payload: Dynamic) -> Result(Int, String) {
  run(payload, decode.field("from", decode.int, decode.success), "requestOps")
}

/// Decode a `noop` heartbeat, returning `(clientId, referenceSequenceNumber)`
/// (inverse of `socket.encode_noop`).
pub fn decode_noop(payload: Dynamic) -> Result(#(String, Int), String) {
  run(payload, noop_decoder(), "noop payload")
}

fn noop_decoder() -> Decoder(#(String, Int)) {
  use client_id <- decode.field("clientId", decode.string)
  use rsn <- decode.field("referenceSequenceNumber", decode.int)
  decode.success(#(client_id, rsn))
}

/// Decode a `submitSignal` payload, flattening its first content batch entry
/// (inverse of `socket.encode_submit_ripple`).
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

/// Build a `connect_document_success` payload the client's
/// `socket.connected_message_decoder` accepts. Carries the assigned client id,
/// the connected roster, the catch-up `initial_messages`, and the current
/// sequence checkpoint. The sluice serves no summaries (plan decision 5), so
/// `summaryContext` is omitted.
///
/// `initial_clients` is what seeds a client's membership roster, and therefore
/// the quorum its consensus kernels freeze a signoff list from. An empty roster
/// here does not fail loudly — it silently makes every pact a one-member pact
/// that accepts immediately.
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
/// optional to the client's decoder, so the roster only has to carry identity.
fn encode_roster_entry(client_id: String) -> Json {
  json.object([
    #("clientId", json.string(client_id)),
    #("client", json.object([#("mode", json.string("write"))])),
  ])
}

/// Build an `op` event payload: the bare `[Sequenced...]` array (inverse of
/// `socket.op_message_decoder`).
///
/// This is the shape floodgate pushes on every op path. Levee wrapped the
/// messages in `{documentId, op: [...]}`; the document id was redundant with
/// the channel topic, and the sluice models the server watershed actually
/// talks to.
pub fn encode_op_event(ops ops: List(Sequenced)) -> Json {
  json.array(ops, encode_sequenced)
}

/// Encode one sequenced op to match `socket.sequenced_document_message_decoder`.
pub fn encode_sequenced(op: Sequenced) -> Json {
  json.object(
    list.flatten([
      [
        #("clientId", json.nullable(op.client_id, json.string)),
        #("sequenceNumber", json.int(op.sequence_number)),
        #("minimumSequenceNumber", json.int(op.minimum_sequence_number)),
        #("clientSequenceNumber", json.int(op.client_sequence_number)),
        #("referenceSequenceNumber", json.int(op.reference_sequence_number)),
        #("type", json.string(op.op_type)),
        #("contents", op.contents),
        #("timestamp", json.int(op.timestamp)),
      ],
      case op.metadata {
        Some(metadata) -> [#("metadata", metadata)]
        None -> []
      },
      case op.data {
        Some(data) -> [#("data", json.string(data))]
        None -> []
      },
    ]),
  )
}

/// The payload of a sequenced `"join"`: an object naming the arriving client,
/// serialized to JSON text. `detail` is the client record on a real server; the
/// sluice has no audience to satisfy, so it stays empty.
pub fn system_join_data(client_id: String) -> String {
  json.object([
    #("clientId", json.string(client_id)),
    #("detail", json.object([])),
  ])
  |> json.to_string
}

/// The payload of a sequenced `"leave"`: the departing client's id as a bare
/// JSON string, serialized to JSON text. Deliberately a different shape from
/// `system_join_data` — that asymmetry is the server's and the client decodes
/// each accordingly.
pub fn system_leave_data(client_id: String) -> String {
  json.string(client_id) |> json.to_string
}

/// Build a `signal` broadcast (inverse of `socket.ripple_message_decoder`).
/// floodgate strips the ripple `type` on broadcast for Fluid compatibility, so it
/// is deliberately omitted; consumers discriminate on the content envelope.
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

/// One tracked presence as the sluice stores it. Metadata is kept *decomposed*
/// into fields rather than as one `Json`, because `phx_ref` and `client_id` have
/// to be merged in beside the application's own fields on the way out, and a
/// `Json` value cannot be merged.
pub type PresenceMeta {
  PresenceMeta(key: String, phx_ref: String, fields: List(#(String, Json)))
}

/// Read the `meta` object out of a `joinPresence` / `updatePresence` push.
///
/// Metadata must be a JSON *object*: the Phoenix `metas` shape puts `phx_ref`
/// and `client_id` alongside the application's fields, and a scalar or array
/// leaves nowhere to put them. Server-owned keys are dropped rather than
/// trusted — a client cannot name its own ref, session, or presence key.
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

/// Whether a client-supplied key at the top level of a presence command is one
/// the server owns. Used to reject a spoofing attempt outright rather than
/// silently ignoring it.
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

/// A `presence_state` snapshot: `{key: {metas: [...]}}`, keys sorted so a test
/// can compare frames without normalizing them first.
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

/// A `presence_error`, the presence lane's only failure channel — presence
/// commands are pushes with no reply, so a rejection has to come back as a
/// frame of its own.
pub fn encode_presence_error(
  code code: String,
  message message: String,
) -> Json {
  json.object([
    #("code", json.string(code)),
    #("message", json.string(message)),
  ])
}

/// Group tracked presences into `{key: {metas: [...]}}`, stamping each meta with
/// the server-owned `phx_ref` and `client_id`. Entries arrive keyed by session
/// id; several sessions can share one presence key, which is exactly how two
/// tabs from one user appear.
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

/// floodgate's dev defaults; the client only needs these present and positive.
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
