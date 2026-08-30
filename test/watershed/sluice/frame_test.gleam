//// Round-trip tests pinning the sluice's inverse codecs against the client's
//// codecs in `wire/socket`. Each test drives one direction across the seam:
//// what the client *encodes*, the sluice *decodes*, and vice versa. A drift in
//// either module's wire shape breaks a test here — the mismatch surfaces as a
//// local failure rather than as silent protocol divergence in production.

import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import startest/expect

import signet/types as token
import spillway/message
import spillway/types

import watershed/presence
import watershed/sluice/frame
import watershed/wire
import watershed/wire/socket

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Serialize a `Json` value and re-parse it as a `Dynamic`, the same trip a
/// pushed frame takes over the wire before the sluice decodes it.
fn json_to_dynamic(value: json.Json) -> decode.Dynamic {
  let assert Ok(dynamic) = json.parse(json.to_string(value), decode.dynamic)
  dynamic
}

fn test_client() -> types.Client {
  types.Client(
    mode: types.WriteMode,
    details: types.ClientDetails(
      capabilities: types.ClientCapabilities(interactive: True),
      client_type: Some("browser"),
      environment: None,
      device: None,
    ),
    permission: [],
    user: token.User(id: "user-1", properties: dict.new()),
    scopes: ["doc:read", "doc:write"],
    timestamp: None,
  )
}

fn test_connect_message() -> message.ConnectMessage {
  message.ConnectMessage(
    tenant_id: "default",
    document_id: "dice",
    token: Some("jwt-token"),
    client: test_client(),
    versions: ["^0.1.0"],
    driver_version: None,
    mode: types.WriteMode,
    nonce: None,
    epoch: None,
    supported_features: None,
    relay_user_agent: None,
  )
}

fn a_sequenced(
  sequence_number: Int,
  client_sequence_number: Int,
  client_id: String,
) -> frame.Sequenced {
  frame.Sequenced(
    client_id: Some(client_id),
    sequence_number: sequence_number,
    minimum_sequence_number: 0,
    client_sequence_number: client_sequence_number,
    reference_sequence_number: sequence_number - 1,
    operation_type: "op",
    contents: json.object([#("address", json.string("root"))]),
    metadata: None,
    timestamp: 1234,
    data: None,
  )
}

/// A sequenced system message, in the server's shape: no author, null
/// `contents`, payload as JSON text in `data`.
fn a_system_message(
  sequence_number: Int,
  message_type: String,
  data: String,
) -> frame.Sequenced {
  frame.Sequenced(
    client_id: None,
    sequence_number: sequence_number,
    minimum_sequence_number: 0,
    client_sequence_number: -1,
    reference_sequence_number: sequence_number - 1,
    operation_type: message_type,
    contents: json.null(),
    metadata: None,
    timestamp: 1234,
    data: Some(data),
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// client → server: the sluice decodes what socket encodes
// ─────────────────────────────────────────────────────────────────────────────

pub fn decode_connect_document_round_trip_test() -> Nil {
  let encoded = socket.encode_connect_document(test_connect_message(), Some(42))
  let assert Ok(request) =
    frame.decode_connect_document(json_to_dynamic(encoded))

  request.tenant_id |> expect.to_equal("default")
  request.document_id |> expect.to_equal("dice")
  request.last_seen_sequence_number |> expect.to_equal(Some(42))
  request.client.scopes |> expect.to_equal(["doc:read", "doc:write"])
}

pub fn decode_connect_document_without_last_seen_test() -> Nil {
  let encoded = socket.encode_connect_document(test_connect_message(), None)
  let assert Ok(request) =
    frame.decode_connect_document(json_to_dynamic(encoded))
  request.last_seen_sequence_number |> expect.to_equal(None)
}

pub fn decode_submit_operation_round_trip_test() -> Nil {
  let operation =
    wire.OutboundOperation(
      client_sequence_number: 3,
      reference_sequence_number: 5,
      operation_type: "op",
      contents: json.object([#("address", json.string("root"))]),
      metadata: None,
    )
  let encoded = socket.encode_submit_operation("sluice-client-1", [[operation]])
  let assert Ok(submit) =
    frame.decode_submit_operation(json_to_dynamic(encoded))

  submit.client_id |> expect.to_equal("sluice-client-1")
  let assert [[decoded]] = submit.batches
  decoded.operation_type |> expect.to_equal("op")
  decoded.client_sequence_number |> expect.to_equal(3)
  decoded.reference_sequence_number |> expect.to_equal(5)
  // Operation contents survive the trip (compare canonical re-encodings).
  json.to_string(decoded.contents)
  |> expect.to_equal("{\"address\":\"root\"}")
}

pub fn decode_request_operations_round_trip_test() -> Nil {
  let encoded = socket.encode_request_operations(from: 10)
  frame.decode_request_operations(json_to_dynamic(encoded))
  |> expect.to_equal(Ok(10))
}

pub fn decode_noop_round_trip_test() -> Nil {
  let encoded =
    socket.encode_noop("sluice-client-1", reference_sequence_number: 12)
  frame.decode_noop(json_to_dynamic(encoded))
  |> expect.to_equal(Ok(#("sluice-client-1", 12)))
}

pub fn decode_submit_signal_round_trip_test() -> Nil {
  let encoded =
    socket.encode_submit_ripple(
      client_id: "sluice-client-2",
      ripple_type: "presence",
      content: json.object([#("selectedCell", json.string("r3c4"))]),
    )
  let assert Ok(signal) = frame.decode_submit_signal(json_to_dynamic(encoded))
  signal.client_id |> expect.to_equal("sluice-client-2")
  signal.signal_type |> expect.to_equal(Some("presence"))
  json.to_string(signal.content)
  |> expect.to_equal("{\"selectedCell\":\"r3c4\"}")
}

// ─────────────────────────────────────────────────────────────────────────────
// server → client: socket decodes what the sluice encodes
// ─────────────────────────────────────────────────────────────────────────────

pub fn encode_connected_is_decodable_test() -> Nil {
  let payload =
    frame.encode_connected(
      client_id: "sluice-client-1",
      tenant_id: "default",
      document_id: "dice",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 2,
      initial_clients: ["sluice-client-0", "sluice-client-1"],
      initial_messages: [
        a_sequenced(1, 1, "sluice-client-0"),
        a_sequenced(2, 1, "sluice-client-1"),
      ],
      timestamp: 1000,
      presence_v1: True,
    )
  let assert Ok(connected) =
    json.parse(json.to_string(payload), socket.connected_message_decoder())

  connected.client_id |> expect.to_equal("sluice-client-1")
  connected.mode |> expect.to_equal(types.WriteMode)
  connected.checkpoint_sequence_number |> expect.to_equal(Some(2))
  connected.claims.document_id |> expect.to_equal("dice")
  connected.summary_context |> expect.to_equal(None)

  connected.initial_clients
  |> list.map(fn(client) { client.client_id })
  |> expect.to_equal(["sluice-client-0", "sluice-client-1"])

  let assert [first, second] = connected.initial_messages
  first.sequence_number |> expect.to_equal(1)
  second.sequence_number |> expect.to_equal(2)
  second.client_id |> expect.to_equal(Some("sluice-client-1"))
}

/// The roster the sluice sends must survive the client's decoder — an
/// `initialClients` the client silently drops is the same as an empty one, and
/// an empty one makes every consensus pact a one-member pact.
pub fn encode_connected_roster_round_trips_test() -> Nil {
  let payload =
    frame.encode_connected(
      client_id: "sluice-client-2",
      tenant_id: "default",
      document_id: "dice",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["sluice-client-0", "sluice-client-1", "sluice-client-2"],
      initial_messages: [],
      timestamp: 1000,
      presence_v1: True,
    )
  let assert Ok(connected) =
    json.parse(json.to_string(payload), socket.connected_message_decoder())

  connected.initial_clients |> list.length |> expect.to_equal(3)
}

/// System messages carry their payload in `data`, not `contents`. Both shapes
/// must survive the client's decoder, because the runtime reads `data` and a
/// dropped field is an invisible no-operation rather than an error.
pub fn encode_system_message_round_trips_data_test() -> Nil {
  let join = a_system_message(4, "join", frame.system_join_data("client-9"))
  let leave = a_system_message(5, "leave", frame.system_leave_data("client-9"))

  let assert Ok(operation_message) =
    json.parse(
      json.to_string(frame.encode_operation_event([join, leave])),
      socket.operation_message_decoder(),
    )

  let assert [decoded_join, decoded_leave] = operation_message.ops
  decoded_join.message_type |> expect.to_equal("join")
  decoded_join.client_id |> expect.to_equal(None)
  decoded_join.data
  |> expect.to_equal(Some("{\"clientId\":\"client-9\",\"detail\":{}}"))
  decoded_leave.message_type |> expect.to_equal("leave")
  decoded_leave.data |> expect.to_equal(Some("\"client-9\""))
}

pub fn encode_operation_event_is_decodable_test() -> Nil {
  let payload =
    frame.encode_operation_event([a_sequenced(7, 2, "sluice-client-1")])
  let assert Ok(operation_message) =
    json.parse(json.to_string(payload), socket.operation_message_decoder())

  // The bare array carries no document id, matching floodgate. The topic
  // already established which document this is.
  operation_message.document_id |> expect.to_equal("")
  let assert [operation] = operation_message.ops
  operation.sequence_number |> expect.to_equal(7)
  operation.client_sequence_number |> expect.to_equal(2)
  operation.client_id |> expect.to_equal(Some("sluice-client-1"))
  operation.message_type |> expect.to_equal("op")
}

pub fn encode_signal_strips_type_test() -> Nil {
  let payload =
    frame.encode_signal(
      from_client: "sluice-client-1",
      content: json.object([#("kind", json.string("presence"))]),
    )
  let assert Ok(signal) =
    json.parse(json.to_string(payload), socket.ripple_message_decoder())

  signal.client_id |> expect.to_equal(Some("sluice-client-1"))
  // floodgate strips the ripple `type` on broadcast — consumers key on the content
  // envelope instead. The sluice reproduces that quirk.
  signal.signal_type |> expect.to_equal(None)
  signal.content
  |> decode.run(decode.at(["kind"], decode.string))
  |> expect.to_equal(Ok("presence"))
}

// ─────────────────────────────────────────────────────────────────────────────
// Presence frames
// ─────────────────────────────────────────────────────────────────────────────

type Panel {
  Panel(name: String)
}

fn panel_decoder() -> decode.Decoder(Panel) {
  use name <- decode.field("panel", decode.string)
  decode.success(Panel(name))
}

fn a_meta(key: String, phx_ref: String, panel: String) -> frame.PresenceMeta {
  frame.PresenceMeta(key: key, phx_ref: phx_ref, fields: [
    #("panel", json.string(panel)),
  ])
}

/// The Phoenix grouping is `{key: {metas: [...]}}`, so two sessions under one
/// key must land as *one* key holding two metas — not two keys. That grouping
/// is what makes "two tabs, one user" representable on the wire at all.
pub fn presence_state_groups_sessions_under_one_key_test() -> Nil {
  let payload =
    frame.encode_presence_state([
      #("client-1", a_meta("user:alice", "ref-1", "sudoku")),
      #("client-2", a_meta("user:alice", "ref-2", "text")),
      #("client-3", a_meta("user:bob", "ref-3", "board")),
    ])

  // The raw shape: two keys, and alice holds two metas.
  let assert Ok(groups) =
    json.parse(
      json.to_string(payload),
      decode.dict(
        decode.string,
        decode.at(["metas"], decode.list(decode.dynamic)),
      ),
    )
  dict.keys(groups)
  |> list.sort(string.compare)
  |> expect.to_equal(["user:alice", "user:bob"])
  let assert Ok(alice) = dict.get(groups, "user:alice")
  list.length(alice) |> expect.to_equal(2)

  // And the client's own decoder reads it back as three sessions.
  let assert Ok(snapshot) =
    json.parse(
      json.to_string(payload),
      presence.presence_state_decoder(decode: panel_decoder()),
    )
  let #(tracker, _) = presence.apply_state(presence.tracker(), snapshot)
  presence.tracker_entries(tracker)
  |> list.map(fn(entry) { #(entry.key, entry.session_id, entry.meta) })
  |> expect.to_equal([
    #("user:alice", "client-1", Panel("sudoku")),
    #("user:alice", "client-2", Panel("text")),
    #("user:bob", "client-3", Panel("board")),
  ])
}

pub fn presence_diff_round_trips_through_the_client_decoder_test() -> Nil {
  let payload =
    frame.encode_presence_diff(
      joins: [#("client-1", a_meta("user:alice", "ref-2", "text"))],
      leaves: [#("client-1", a_meta("user:alice", "ref-1", "sudoku"))],
    )

  let assert Ok(diff) =
    json.parse(
      json.to_string(payload),
      presence.presence_diff_decoder(decode: panel_decoder()),
    )

  presence.diff_joins(diff)
  |> list.map(fn(entry) { entry.meta })
  |> expect.to_equal([Panel("text")])
  presence.diff_leaves(diff)
  |> list.map(fn(entry) { entry.meta })
  |> expect.to_equal([Panel("sudoku")])
}

pub fn presence_error_round_trips_test() -> Nil {
  let payload =
    frame.encode_presence_error(code: "not_joined", message: "nothing here")

  json.parse(json.to_string(payload), presence.presence_error_decoder())
  |> expect.to_equal(
    Ok(presence.Rejected(code: "not_joined", message: "nothing here")),
  )
}
