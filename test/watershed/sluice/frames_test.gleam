//// Round-trip tests pinning the sluice's inverse codecs against the client's
//// codecs in `wire/socket`. Each test drives one direction across the seam:
//// what the client *encodes*, the sluice *decodes*, and vice versa. A drift in
//// either module's wire shape breaks a test here — the mismatch surfaces as a
//// local failure rather than as silent protocol divergence in production.

import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/option.{None, Some}
import startest/expect

import spillway/message
import spillway/types

import watershed/sluice/frames
import watershed/wire
import watershed/wire/socket

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Serialize a `Json` value and re-parse it as a `Dynamic`, the same trip a
/// pushed frame takes over the wire before the sluice decodes it.
fn to_dynamic(value: json.Json) -> decode.Dynamic {
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
    user: types.User(id: "user-1", properties: dict.new()),
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

fn a_sequenced(sn: Int, csn: Int, client_id: String) -> frames.Sequenced {
  frames.Sequenced(
    client_id: Some(client_id),
    sequence_number: sn,
    minimum_sequence_number: 0,
    client_sequence_number: csn,
    reference_sequence_number: sn - 1,
    op_type: "op",
    contents: json.object([#("address", json.string("root"))]),
    metadata: None,
    timestamp: 1234,
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// client → server: the sluice decodes what socket encodes
// ─────────────────────────────────────────────────────────────────────────────

pub fn decode_connect_document_round_trip_test() {
  let encoded = socket.encode_connect_document(test_connect_message(), Some(42))
  let assert Ok(request) = frames.decode_connect_document(to_dynamic(encoded))

  request.tenant_id |> expect.to_equal("default")
  request.document_id |> expect.to_equal("dice")
  request.last_seen_sequence_number |> expect.to_equal(Some(42))
  request.client.scopes |> expect.to_equal(["doc:read", "doc:write"])
}

pub fn decode_connect_document_without_last_seen_test() {
  let encoded = socket.encode_connect_document(test_connect_message(), None)
  let assert Ok(request) = frames.decode_connect_document(to_dynamic(encoded))
  request.last_seen_sequence_number |> expect.to_equal(None)
}

pub fn decode_submit_op_round_trip_test() {
  let op =
    wire.OutboundOp(
      client_sequence_number: 3,
      reference_sequence_number: 5,
      op_type: "op",
      contents: json.object([#("address", json.string("root"))]),
      metadata: None,
    )
  let encoded = socket.encode_submit_op("sluice-client-1", [[op]])
  let assert Ok(submit) = frames.decode_submit_op(to_dynamic(encoded))

  submit.client_id |> expect.to_equal("sluice-client-1")
  let assert [[decoded]] = submit.batches
  decoded.op_type |> expect.to_equal("op")
  decoded.client_sequence_number |> expect.to_equal(3)
  decoded.reference_sequence_number |> expect.to_equal(5)
  // Op contents survive the trip (compare canonical re-encodings).
  json.to_string(decoded.contents)
  |> expect.to_equal("{\"address\":\"root\"}")
}

pub fn decode_request_ops_round_trip_test() {
  let encoded = socket.encode_request_ops(from: 10)
  frames.decode_request_ops(to_dynamic(encoded)) |> expect.to_equal(Ok(10))
}

pub fn decode_noop_round_trip_test() {
  let encoded =
    socket.encode_noop("sluice-client-1", reference_sequence_number: 12)
  frames.decode_noop(to_dynamic(encoded))
  |> expect.to_equal(Ok(#("sluice-client-1", 12)))
}

pub fn decode_submit_signal_round_trip_test() {
  let encoded =
    socket.encode_submit_ripple(
      client_id: "sluice-client-2",
      ripple_type: "presence",
      content: json.object([#("selectedCell", json.string("r3c4"))]),
    )
  let assert Ok(signal) = frames.decode_submit_signal(to_dynamic(encoded))
  signal.client_id |> expect.to_equal("sluice-client-2")
  signal.signal_type |> expect.to_equal(Some("presence"))
  json.to_string(signal.content)
  |> expect.to_equal("{\"selectedCell\":\"r3c4\"}")
}

// ─────────────────────────────────────────────────────────────────────────────
// server → client: socket decodes what the sluice encodes
// ─────────────────────────────────────────────────────────────────────────────

pub fn encode_connected_is_decodable_test() {
  let payload =
    frames.encode_connected(
      client_id: "sluice-client-1",
      tenant_id: "default",
      document_id: "dice",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 2,
      initial_messages: [
        a_sequenced(1, 1, "sluice-client-0"),
        a_sequenced(2, 1, "sluice-client-1"),
      ],
      timestamp: 1000,
    )
  let assert Ok(connected) =
    json.parse(json.to_string(payload), socket.connected_message_decoder())

  connected.client_id |> expect.to_equal("sluice-client-1")
  connected.mode |> expect.to_equal(types.WriteMode)
  connected.checkpoint_sequence_number |> expect.to_equal(Some(2))
  connected.claims.document_id |> expect.to_equal("dice")
  connected.summary_context |> expect.to_equal(None)

  let assert [first, second] = connected.initial_messages
  first.sequence_number |> expect.to_equal(1)
  second.sequence_number |> expect.to_equal(2)
  second.client_id |> expect.to_equal(Some("sluice-client-1"))
}

pub fn encode_op_event_is_decodable_test() {
  let payload =
    frames.encode_op_event("dice", [a_sequenced(7, 2, "sluice-client-1")])
  let assert Ok(op_message) =
    json.parse(json.to_string(payload), socket.op_message_decoder())

  op_message.document_id |> expect.to_equal("dice")
  let assert [op] = op_message.ops
  op.sequence_number |> expect.to_equal(7)
  op.client_sequence_number |> expect.to_equal(2)
  op.client_id |> expect.to_equal(Some("sluice-client-1"))
  op.message_type |> expect.to_equal("op")
}

pub fn encode_signal_strips_type_test() {
  let payload =
    frames.encode_signal(
      from_client: "sluice-client-1",
      content: json.object([#("kind", json.string("presence"))]),
    )
  let assert Ok(signal) =
    json.parse(json.to_string(payload), socket.ripple_message_decoder())

  signal.client_id |> expect.to_equal(Some("sluice-client-1"))
  // levee strips the ripple `type` on broadcast — consumers key on the content
  // envelope instead. The sluice reproduces that quirk.
  signal.signal_type |> expect.to_equal(None)
  signal.content
  |> decode.run(decode.at(["kind"], decode.string))
  |> expect.to_equal(Ok("presence"))
}
