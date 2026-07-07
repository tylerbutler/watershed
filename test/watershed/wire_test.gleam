//// Codec tests for `watershed/wire`.
////
//// Inbound fixtures mirror the exact frames levee produces:
//// - `connect_document_success` from `session.ex` `build_connected_response`
//// - sequenced ops from spillway `session_logic.build_sequenced_op` (9 keys,
////   `metadata: null`, nullable `clientId`)
//// - nacks from `document_channel.ex` `push_nack`
////
//// Outbound expectations mirror what the server / TS driver accept:
//// - `connect_document` requires `tenantId`, `id`, `client`, `mode`, `token`
//// - `submitOp` is `{clientId, messageBatches: [[op]]}` with per-op keys as
////   in `leveeDeltaConnection.ts` `submitCore`

import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import startest/expect

import spillway/message
import spillway/nack
import spillway/types

import lattice_core/replica_id
import watershed/channel
import watershed/claims_kernel
import watershed/counter_kernel
import watershed/map_kernel.{Clear, Delete, Set}
import watershed/or_map_kernel
import watershed/pact_map_kernel
import watershed/pn_counter_kernel
import watershed/register_collection_kernel
import watershed/wire
import watershed/wire/ops
import watershed/wire/socket
import watershed/wire/summary_blob

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

fn parse(text: String, decoder: decode.Decoder(t)) -> t {
  case json.parse(text, decoder) {
    Ok(value) -> value
    Error(_) -> panic as { "fixture failed to decode: " <> text }
  }
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

// ─────────────────────────────────────────────────────────────────────────────
// connect_document encoding
// ─────────────────────────────────────────────────────────────────────────────

pub fn encode_connect_document_has_required_fields_test() {
  let encoded =
    socket.encode_connect_document(test_connect_message(), None)
    |> json.to_string

  encoded
  |> expect.to_equal(
    "{\"tenantId\":\"default\",\"id\":\"dice\",\"token\":\"jwt-token\","
    <> "\"client\":{\"mode\":\"write\","
    <> "\"details\":{\"capabilities\":{\"interactive\":true},\"type\":\"browser\"},"
    <> "\"permission\":[],\"user\":{\"id\":\"user-1\"},"
    <> "\"scopes\":[\"doc:read\",\"doc:write\"]},"
    <> "\"mode\":\"write\",\"versions\":[\"^0.1.0\"]}",
  )
}

pub fn encode_connect_document_includes_last_seen_sn_test() {
  let encoded =
    socket.encode_connect_document(test_connect_message(), Some(42))
    |> json.to_string

  // Reconnects carry lastSeenSequenceNumber so the server pushes catch-up.
  encoded
  |> string_contains("\"lastSeenSequenceNumber\":42")
  |> expect.to_be_true()
}

pub fn encode_connect_document_null_token_test() {
  let msg = message.ConnectMessage(..test_connect_message(), token: None)
  socket.encode_connect_document(msg, None)
  |> json.to_string
  |> string_contains("\"token\":null")
  |> expect.to_be_true()
}

// ─────────────────────────────────────────────────────────────────────────────
// connect_document_success decoding
// ─────────────────────────────────────────────────────────────────────────────

fn connected_fixture() -> String {
  "{
    \"claims\": {
      \"documentId\": \"dice\",
      \"scopes\": [\"doc:read\", \"doc:write\"],
      \"tenantId\": \"default\",
      \"user\": {\"id\": \"user-1\"},
      \"iat\": 1000,
      \"exp\": 2000,
      \"ver\": \"1.0\"
    },
    \"clientId\": \"default_dice_1\",
    \"existing\": true,
    \"maxMessageSize\": 16000,
    \"mode\": \"write\",
    \"serviceConfiguration\": {\"blockSize\": 65536, \"maxMessageSize\": 16000},
    \"initialClients\": [
      {\"clientId\": \"default_dice_0\",
       \"client\": {\"mode\": \"write\",
                    \"details\": {\"capabilities\": {\"interactive\": true}},
                    \"permission\": [],
                    \"user\": {\"id\": \"user-0\"},
                    \"scopes\": []},
       \"mode\": \"write\"}
    ],
    \"initialMessages\": [
      {\"clientId\": \"default_dice_0\",
       \"sequenceNumber\": 1,
       \"minimumSequenceNumber\": 0,
       \"clientSequenceNumber\": 1,
       \"referenceSequenceNumber\": 0,
       \"type\": \"op\",
       \"contents\": {\"address\": \"root\",
                      \"contents\": {\"type\": \"set\", \"key\": \"die\",
                                     \"value\": {\"type\": \"Plain\", \"value\": 4}}},
       \"metadata\": null,
       \"timestamp\": 1234}
    ],
    \"initialSignals\": [],
    \"supportedVersions\": [\"^0.1.0\", \"^1.0.0\"],
    \"supportedFeatures\": {},
    \"version\": \"^0.1.0\",
    \"checkpointSequenceNumber\": 1
  }"
}

pub fn decode_connected_message_test() {
  let connected = parse(connected_fixture(), socket.connected_message_decoder())

  connected.client_id |> expect.to_equal("default_dice_1")
  connected.existing |> expect.to_be_true()
  connected.max_message_size |> expect.to_equal(16_000)
  connected.mode |> expect.to_equal(types.WriteMode)
  connected.checkpoint_sequence_number |> expect.to_equal(Some(1))
  connected.version |> expect.to_equal("^0.1.0")
  connected.supported_versions |> expect.to_equal(["^0.1.0", "^1.0.0"])
  connected.claims.document_id |> expect.to_equal("dice")
  connected.claims.user.id |> expect.to_equal("user-1")
  connected.service_configuration.block_size |> expect.to_equal(65_536)

  let assert [initial_client] = connected.initial_clients
  initial_client.client_id |> expect.to_equal("default_dice_0")
  initial_client.client.user.id |> expect.to_equal("user-0")

  let assert [initial_op] = connected.initial_messages
  initial_op.sequence_number |> expect.to_equal(1)
  initial_op.client_id |> expect.to_equal(Some("default_dice_0"))

  // A never-summarized document carries no summaryContext.
  connected.summary_context |> expect.to_equal(None)
}

pub fn decode_connected_message_with_summary_context_test() {
  let fixture =
    "{
      \"claims\": {\"documentId\": \"dice\", \"scopes\": [], \"tenantId\": \"default\",
                   \"user\": {\"id\": \"u\"}, \"iat\": 0, \"exp\": 0, \"ver\": \"1.0\"},
      \"clientId\": \"default_dice_2\",
      \"maxMessageSize\": 16000,
      \"mode\": \"write\",
      \"serviceConfiguration\": {\"blockSize\": 65536, \"maxMessageSize\": 16000},
      \"initialMessages\": [],
      \"version\": \"^0.1.0\",
      \"checkpointSequenceNumber\": 42,
      \"summaryContext\": {\"handle\": \"tree-abc\", \"sequenceNumber\": 40}
    }"
  let connected = parse(fixture, socket.connected_message_decoder())
  connected.summary_context
  |> expect.to_equal(
    Some(message.SummaryContext(handle: "tree-abc", sequence_number: 40)),
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// summary blob codec
// ─────────────────────────────────────────────────────────────────────────────

pub fn summary_blob_round_trips_test() {
  let entries = [
    #("die", json.int(4)),
    #("label", json.string("hello")),
    #("nested", json.object([#("a", json.array([1, 2], json.int))])),
  ]
  let encoded =
    summary_blob.encode_channels(7, [#("root", channel.MapSnapshot(entries))])
    |> json.to_string
  let assert Ok(blob) = summary_blob.decode(encoded)
  blob.sequence_number |> expect.to_equal(7)
  let assert [decoded_channel] = blob.channels
  decoded_channel.address |> expect.to_equal("root")
  let assert channel.MapSnapshot(decoded_entries) = decoded_channel.snapshot
  // Values compare structurally by re-encoding through the same codec.
  let normalize = fn(pairs: List(#(String, json.Json))) {
    list.map(pairs, fn(pair) { #(pair.0, json.to_string(pair.1)) })
  }
  normalize(decoded_entries) |> expect.to_equal(normalize(entries))
}

pub fn summary_blob_rejects_unknown_version_test() {
  let raw =
    "{\"watershedSummaryVersion\": 999, \"address\": \"root\","
    <> " \"sequenceNumber\": 1, \"entries\": []}"
  case summary_blob.decode(raw) {
    Error(_) -> Nil
    Ok(_) -> panic as "expected unknown summary version to be rejected"
  }
}

pub fn encode_summarize_op_test() {
  let op =
    ops.outbound_summarize_op(
      client_sequence_number: 3,
      reference_sequence_number: 9,
      handle: "tree-abc",
      message: "watershed summary",
      parents: [],
      head: "tree-abc",
    )
  let encoded =
    socket.encode_submit_op("default_dice_1", [[op]]) |> json.to_string
  string_contains(encoded, "\"type\":\"summarize\"") |> expect.to_be_true()
  string_contains(encoded, "\"handle\":\"tree-abc\"") |> expect.to_be_true()
  string_contains(encoded, "\"head\":\"tree-abc\"") |> expect.to_be_true()
  string_contains(encoded, "\"parents\":[]") |> expect.to_be_true()
  string_contains(encoded, "\"clientSequenceNumber\":3") |> expect.to_be_true()
}

pub fn decode_connect_error_test() {
  let error =
    parse(
      "{\"code\": 401, \"message\": \"Token has expired\"}",
      socket.connect_error_decoder(),
    )
  error |> expect.to_equal(message.ConnectError(401, "Token has expired"))
}

// ─────────────────────────────────────────────────────────────────────────────
// op event decoding
// ─────────────────────────────────────────────────────────────────────────────

fn op_event_fixture() -> String {
  "{
    \"documentId\": \"dice\",
    \"op\": [
      {\"clientId\": \"default_dice_1\",
       \"sequenceNumber\": 7,
       \"minimumSequenceNumber\": 3,
       \"clientSequenceNumber\": 2,
       \"referenceSequenceNumber\": 5,
       \"type\": \"op\",
       \"contents\": {\"address\": \"root\",
                      \"contents\": {\"type\": \"delete\", \"key\": \"die\"}},
       \"metadata\": null,
       \"timestamp\": 1234},
      {\"clientId\": null,
       \"sequenceNumber\": 8,
       \"minimumSequenceNumber\": 3,
       \"clientSequenceNumber\": -1,
       \"referenceSequenceNumber\": 7,
       \"type\": \"join\",
       \"contents\": {\"clientId\": \"default_dice_2\"},
       \"metadata\": null,
       \"timestamp\": 1235}
    ]
  }"
}

pub fn decode_op_message_test() {
  let op_message = parse(op_event_fixture(), socket.op_message_decoder())

  op_message.document_id |> expect.to_equal("dice")
  let assert [op, join] = op_message.ops

  op.client_id |> expect.to_equal(Some("default_dice_1"))
  op.sequence_number |> expect.to_equal(7)
  op.client_sequence_number |> expect.to_equal(2)
  op.message_type |> expect.to_equal("op")

  // System messages carry a null clientId and only advance last_seen_sn.
  join.client_id |> expect.to_equal(None)
  join.message_type |> expect.to_equal("join")
}

pub fn decode_map_envelope_from_sequenced_contents_test() {
  let op_message = parse(op_event_fixture(), socket.op_message_decoder())
  let assert [op, _join] = op_message.ops

  ops.decode_map_envelope(op.contents)
  |> expect.to_equal(Ok(#("root", Delete("die"))))
}

// ─────────────────────────────────────────────────────────────────────────────
// map op envelope round-trips
// ─────────────────────────────────────────────────────────────────────────────

fn round_trip_map_op(op: map_kernel.MapOp) {
  let encoded = ops.encode_map_envelope("root", op) |> json.to_string
  let decoded = parse(encoded, ops.map_envelope_decoder())
  decoded |> expect.to_equal(#("root", op))
}

pub fn map_op_set_round_trip_test() {
  round_trip_map_op(Set("die", json.int(4)))
}

pub fn map_op_set_nested_value_round_trip_test() {
  round_trip_map_op(Set(
    "config",
    json.object([
      #("enabled", json.bool(True)),
      #("names", json.preprocessed_array([json.string("a"), json.null()])),
      #("ratio", json.float(0.5)),
    ]),
  ))
}

pub fn map_op_delete_round_trip_test() {
  round_trip_map_op(Delete("die"))
}

pub fn map_op_clear_round_trip_test() {
  round_trip_map_op(Clear)
}

pub fn map_op_set_wire_shape_test() {
  // Byte-identical to the TS `@fluidframework/map` op format.
  ops.encode_map_envelope("root", Set("die", json.int(4)))
  |> json.to_string
  |> expect.to_equal(
    "{\"address\":\"root\",\"contents\":"
    <> "{\"type\":\"set\",\"key\":\"die\","
    <> "\"value\":{\"type\":\"Plain\",\"value\":4}}}",
  )
}

pub fn map_op_rejects_non_plain_value_test() {
  let shared =
    "{\"address\": \"root\",
      \"contents\": {\"type\": \"set\", \"key\": \"k\",
                     \"value\": {\"type\": \"Shared\", \"value\": \"handle\"}}}"
  let _ =
    json.parse(shared, ops.map_envelope_decoder())
    |> expect.to_be_error()
  Nil
}

// ─────────────────────────────────────────────────────────────────────────────
// counter op envelope round-trips
// ─────────────────────────────────────────────────────────────────────────────

fn round_trip_counter_op(op: counter_kernel.CounterOp) {
  let encoded = ops.encode_counter_envelope("counter", op) |> json.to_string
  let decoded = parse(encoded, ops.counter_envelope_decoder())
  decoded |> expect.to_equal(#("counter", op))
}

pub fn counter_op_increment_round_trip_test() {
  round_trip_counter_op(counter_kernel.Increment(4))
}

pub fn counter_op_negative_increment_round_trip_test() {
  round_trip_counter_op(counter_kernel.Increment(-3))
}

pub fn counter_op_wire_shape_test() {
  ops.encode_counter_envelope("counter", counter_kernel.Increment(4))
  |> json.to_string
  |> expect.to_equal(
    "{\"address\":\"counter\",\"contents\":"
    <> "{\"type\":\"increment\",\"incrementAmount\":4}}",
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// pn-counter op envelope round-trips
// ─────────────────────────────────────────────────────────────────────────────

fn a_pn_counter_op(amount: Int) -> pn_counter_kernel.PnCounterOp {
  let #(_state, _events, op, _id) =
    pn_counter_kernel.update(
      pn_counter_kernel.new(replica_id.new("wire-test")),
      amount,
    )
  op
}

fn round_trip_pn_counter_op(op: pn_counter_kernel.PnCounterOp) {
  let encoded = ops.encode_pn_counter_envelope("pnc", op) |> json.to_string
  let decoded = parse(encoded, ops.pn_counter_envelope_decoder())
  decoded |> expect.to_equal(#("pnc", op))
}

pub fn pn_counter_op_increment_round_trip_test() {
  round_trip_pn_counter_op(a_pn_counter_op(7))
}

pub fn pn_counter_op_decrement_round_trip_test() {
  round_trip_pn_counter_op(a_pn_counter_op(-4))
}

// ─────────────────────────────────────────────────────────────────────────────
// pact-map op envelope round-trips
// ─────────────────────────────────────────────────────────────────────────────

fn round_trip_pact_map_op(op: pact_map_kernel.PactMapOp) {
  let encoded = ops.encode_pact_map_envelope("pm", op) |> json.to_string
  let assert Ok(#(address, decoded)) =
    json.parse(encoded, ops.pact_map_envelope_decoder())
  address |> expect.to_equal("pm")
  // `Json` values are opaque and not reliably equal across a decode; compare
  // canonical re-encodings instead.
  json.to_string(ops.encode_pact_map_op(decoded))
  |> expect.to_equal(json.to_string(ops.encode_pact_map_op(op)))
}

pub fn pact_map_op_set_round_trip_test() {
  round_trip_pact_map_op(pact_map_kernel.Set(
    "grade",
    Some(json.string("2.1%")),
    4,
  ))
}

pub fn pact_map_op_set_tombstone_round_trip_test() {
  round_trip_pact_map_op(pact_map_kernel.Set("grade", None, 7))
}

pub fn pact_map_op_set_null_value_round_trip_test() {
  // `Some(null)` (a real null value) must stay distinct from `None` (delete).
  round_trip_pact_map_op(pact_map_kernel.Set("grade", Some(json.null()), 2))
}

pub fn pact_map_op_accept_round_trip_test() {
  round_trip_pact_map_op(pact_map_kernel.Accept("grade"))
}

pub fn counter_op_rejects_fractional_increment_test() {
  let fractional =
    "{\"address\":\"counter\",\"contents\":{\"type\":\"increment\",\"incrementAmount\":1.5}}"
  let _ =
    json.parse(fractional, ops.counter_envelope_decoder())
    |> expect.to_be_error()
  Nil
}

// ─────────────────────────────────────────────────────────────────────────────
// submitOp / requestOps / noop encoding
// ─────────────────────────────────────────────────────────────────────────────

pub fn encode_submit_op_test() {
  let op =
    ops.outbound_channel_op(
      address: "root",
      client_sequence_number: 1,
      reference_sequence_number: 5,
      op: channel.MapOp(Set("die", json.int(4))),
    )

  socket.encode_submit_op("default_dice_1", [[op]])
  |> json.to_string
  |> expect.to_equal(
    "{\"clientId\":\"default_dice_1\",\"messageBatches\":[["
    <> "{\"type\":\"op\","
    <> "\"contents\":{\"address\":\"root\",\"contents\":"
    <> "{\"type\":\"set\",\"key\":\"die\","
    <> "\"value\":{\"type\":\"Plain\",\"value\":4}}},"
    <> "\"clientSequenceNumber\":1,"
    <> "\"referenceSequenceNumber\":5}"
    <> "]]}",
  )
}

pub fn encode_request_ops_test() {
  socket.encode_request_ops(from: 10)
  |> json.to_string
  |> expect.to_equal("{\"from\":10}")
}

pub fn encode_noop_test() {
  socket.encode_noop("default_dice_1", reference_sequence_number: 12)
  |> json.to_string
  |> expect.to_equal(
    "{\"clientId\":\"default_dice_1\",\"referenceSequenceNumber\":12}",
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// nack decoding
// ─────────────────────────────────────────────────────────────────────────────

pub fn decode_nack_event_test() {
  // Exact shape of document_channel.ex push_nack/4.
  let fixture =
    "{
      \"clientId\": \"\",
      \"nacks\": [
        {\"operation\": null,
         \"sequenceNumber\": -1,
         \"content\": {\"code\": 400,
                       \"type\": \"BadRequestError\",
                       \"message\": \"Client not connected\"}}
      ]
    }"

  let assert [rejected] = parse(fixture, socket.nacks_decoder())
  rejected.operation |> expect.to_equal(None)
  rejected.sequence_number |> expect.to_equal(-1)
  rejected.content.code |> expect.to_equal(400)
  rejected.content.error_type |> expect.to_equal(nack.BadRequestError)
  rejected.content.message |> expect.to_equal("Client not connected")
  rejected.content.retry_after |> expect.to_equal(None)
}

pub fn decode_nack_with_operation_test() {
  let fixture =
    "{
      \"clientId\": \"\",
      \"nacks\": [
        {\"operation\": {\"type\": \"op\",
                         \"contents\": {\"address\": \"root\",
                                        \"contents\": {\"type\": \"clear\"}},
                         \"clientSequenceNumber\": 3,
                         \"referenceSequenceNumber\": 9},
         \"sequenceNumber\": 12,
         \"content\": {\"code\": 429,
                       \"type\": \"ThrottlingError\",
                       \"message\": \"Rate limit exceeded\",
                       \"retryAfter\": 5}}
      ]
    }"

  let assert [nacked] = parse(fixture, socket.nacks_decoder())
  nacked.sequence_number |> expect.to_equal(12)
  nacked.content.error_type |> expect.to_equal(nack.ThrottlingError)
  nacked.content.retry_after |> expect.to_equal(Some(5))
  let assert Some(operation) = nacked.operation
  operation.client_sequence_number |> expect.to_equal(3)
  operation.message_type |> expect.to_equal("op")
}

// ─────────────────────────────────────────────────────────────────────────────
// JSON value decoding (Dynamic → Json)
// ─────────────────────────────────────────────────────────────────────────────

pub fn json_value_decoder_round_trips_scalars_test() {
  ["4", "4.5", "true", "null", "\"text\"", "[1,2,3]"]
  |> list_each(fn(text) {
    parse(text, wire.json_value_decoder())
    |> json.to_string
    |> expect.to_equal(text)
  })
}

pub fn json_value_decoder_handles_objects_test() {
  // Object key order is not preserved through Erlang maps, so compare
  // decoded structure rather than strings.
  let text = "{\"a\": 1, \"b\": [true, null]}"
  let decoded = parse(text, wire.json_value_decoder()) |> json.to_string
  let normalized = parse(decoded, wire.json_value_decoder()) |> json.to_string
  decoded |> expect.to_equal(normalized)
  string_contains(decoded, "\"a\":1") |> expect.to_be_true()
  string_contains(decoded, "\"b\":[true,null]") |> expect.to_be_true()
}

// ─────────────────────────────────────────────────────────────────────────────
// Local helpers
// ─────────────────────────────────────────────────────────────────────────────

fn string_contains(haystack: String, needle: String) -> Bool {
  string.contains(does: haystack, contain: needle)
}

fn list_each(items: List(a), run: fn(a) -> b) -> Nil {
  list.each(items, run)
}

// New tests for attach ops and the summary blob

pub fn attach_codec_round_trip_test() {
  let entries = [#("k", json.int(1)), #("s", json.string("v"))]
  let encoded =
    ops.encode_attach("root", channel.MapSnapshot(entries))
    |> json.to_string
  let dynamic = parse(encoded, decode.dynamic)
  case ops.decode_op_contents(dynamic) {
    Ok(attach) -> {
      let assert ops.AttachOp(address, snapshot) = attach
      address |> expect.to_equal("root")
      snapshot |> expect.to_equal(channel.MapSnapshot(entries))
    }
    Error(_) -> panic as "attach decode failed"
  }
}

pub fn decode_op_contents_discrimination_test() {
  // A map envelope decodes as ChannelOp, its payload left for stage-two
  // decoding against the addressed channel's registered type.
  let map_json =
    "{\"address\": \"root\", \"contents\": {\"type\": \"set\", \"key\": \"k\", \"value\": {\"type\": \"Plain\", \"value\": 4}}}"
  let dynamic = parse(map_json, decode.dynamic)
  case ops.decode_op_contents(dynamic) {
    Ok(contents) -> {
      let assert ops.ChannelOp(address, payload) = contents
      address |> expect.to_equal("root")
      case decode.run(payload, ops.channel_op_decoder(channel.MapChannel)) {
        Ok(channel.MapOp(Set(k, _))) -> k |> expect.to_equal("k")
        _ -> panic as "stage-two map op decode failed"
      }
    }
    Error(_) -> panic as "channel op decode failed"
  }
}

pub fn decode_op_contents_rejects_bad_attach_test() {
  // An explicit "attach" with an unknown channel type must be rejected.
  let bad =
    "{\"type\": \"attach\", \"address\": \"root\", \"channelType\": \"weird\", \"snapshot\": [{\"key\": \"k\", \"value\": 1}]}"
  let dynamic = parse(bad, decode.dynamic)
  case ops.decode_op_contents(dynamic) {
    Error(_) -> Nil
    Ok(_) ->
      panic as "expected bad attach to be rejected, not decoded as channel op"
  }
}

pub fn summary_blob_v3_round_trips_test() {
  let entries = [#("a", json.int(1))]
  let channel_json =
    json.object([
      #("address", json.string("root")),
      #("type", json.string(wire.channel_type_map)),
      #(
        "data",
        json.array(entries, fn(e) {
          json.object([#("key", json.string(e.0)), #("value", e.1)])
        }),
      ),
    ])
  let raw =
    json.object([
      #("watershedSummaryVersion", json.int(3)),
      #("sequenceNumber", json.int(5)),
      #("channels", json.array([channel_json], fn(c) { c })),
    ])
    |> json.to_string
  case summary_blob.decode(raw) {
    Ok(blob) -> {
      blob.sequence_number |> expect.to_equal(5)
      let assert [ch] = blob.channels
      ch.address |> expect.to_equal("root")
      ch.snapshot |> expect.to_equal(channel.MapSnapshot(entries))
    }
    Error(_) -> panic as "v3 decode failed"
  }
}

pub fn summary_blob_rejects_superseded_version_test() {
  // The v2 shape (per-channel `entries`, version 2) has no loader: formats
  // are cut clean while nothing external consumes them.
  let raw =
    "{\"watershedSummaryVersion\": 2, \"sequenceNumber\": 5,"
    <> " \"channels\": [{\"address\": \"root\", \"type\": \"map\","
    <> " \"entries\": [{\"key\": \"a\", \"value\": 1}]}]}"
  case summary_blob.decode(raw) {
    Error(_) -> Nil
    Ok(_) -> panic as "expected the superseded v2 format to be rejected"
  }
}

pub fn summary_blob_unknown_channel_type_rejected_test() {
  let entries = [#("a", json.int(1))]
  let channel_json =
    json.object([
      #("address", json.string("root")),
      #("type", json.string("weird")),
      #(
        "data",
        json.array(entries, fn(e) {
          json.object([#("key", json.string(e.0)), #("value", e.1)])
        }),
      ),
    ])
  let raw =
    json.object([
      #("watershedSummaryVersion", json.int(3)),
      #("sequenceNumber", json.int(5)),
      #("channels", json.array([channel_json], fn(c) { c })),
    ])
    |> json.to_string
  case summary_blob.decode(raw) {
    Error(_) -> Nil
    Ok(_) -> panic as "expected unknown channel type to be rejected"
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Counter channels (R2)
// ─────────────────────────────────────────────────────────────────────────────

pub fn counter_attach_codec_round_trip_test() {
  let encoded =
    ops.encode_attach("tally", channel.CounterSnapshot(41)) |> json.to_string
  string_contains(encoded, "\"channelType\":\"counter\"") |> expect.to_be_true()
  let dynamic = parse(encoded, decode.dynamic)
  case ops.decode_op_contents(dynamic) {
    Ok(ops.AttachOp(address, snapshot)) -> {
      address |> expect.to_equal("tally")
      snapshot |> expect.to_equal(channel.CounterSnapshot(41))
    }
    _ -> panic as "counter attach decode failed"
  }
}

pub fn counter_channel_op_stage_two_decode_test() {
  let encoded =
    ops.encode_channel_envelope(
      "tally",
      channel.CounterOp(counter_kernel.Increment(5)),
    )
    |> json.to_string
  let dynamic = parse(encoded, decode.dynamic)
  case ops.decode_op_contents(dynamic) {
    Ok(ops.ChannelOp(address, payload)) -> {
      address |> expect.to_equal("tally")
      decode.run(payload, ops.channel_op_decoder(channel.CounterChannel))
      |> expect.to_equal(Ok(channel.CounterOp(counter_kernel.Increment(5))))
      // The same payload must not decode against the map grammar.
      decode.run(payload, ops.channel_op_decoder(channel.MapChannel))
      |> expect.to_be_error()
      Nil
    }
    _ -> panic as "counter channel op decode failed"
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Claims channels (R3)
// ─────────────────────────────────────────────────────────────────────────────

pub fn claim_op_round_trip_test() {
  let op = claims_kernel.Claim("owner", json.string("alice"), 9)
  let encoded = ops.encode_claim_envelope("locks", op) |> json.to_string
  let decoded = parse(encoded, claim_envelope_decoder())
  decoded |> expect.to_equal(#("locks", op))
}

fn claim_envelope_decoder() -> decode.Decoder(#(String, claims_kernel.ClaimOp)) {
  use address <- decode.field("address", decode.string)
  use op <- decode.field("contents", ops.claim_op_decoder())
  decode.success(#(address, op))
}

pub fn claim_channel_op_stage_two_decode_test() {
  let op = claims_kernel.Claim("owner", json.string("alice"), 9)
  let encoded =
    ops.encode_channel_envelope("locks", channel.ClaimsOp(op))
    |> json.to_string
  let dynamic = parse(encoded, decode.dynamic)
  case ops.decode_op_contents(dynamic) {
    Ok(ops.ChannelOp(address, payload)) -> {
      address |> expect.to_equal("locks")
      decode.run(payload, ops.channel_op_decoder(channel.ClaimsChannel))
      |> expect.to_equal(Ok(channel.ClaimsOp(op)))
      decode.run(payload, ops.channel_op_decoder(channel.MapChannel))
      |> expect.to_be_error()
      decode.run(payload, ops.channel_op_decoder(channel.CounterChannel))
      |> expect.to_be_error()
      Nil
    }
    _ -> panic as "claim channel op decode failed"
  }
}

pub fn claims_attach_codec_round_trip_test() {
  let snapshot = channel.ClaimsSnapshot([#("owner", json.string("alice"), 7)])
  let encoded = ops.encode_attach("locks", snapshot) |> json.to_string
  string_contains(encoded, "\"channelType\":\"claims\"") |> expect.to_be_true()
  let dynamic = parse(encoded, decode.dynamic)
  case ops.decode_op_contents(dynamic) {
    Ok(ops.AttachOp(address, decoded)) -> {
      address |> expect.to_equal("locks")
      decoded |> expect.to_equal(snapshot)
    }
    _ -> panic as "claims attach decode failed"
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OR-map channels (OM4)
// ─────────────────────────────────────────────────────────────────────────────

fn sample_tally_op() -> or_map_kernel.OrMapOp {
  let state =
    or_map_kernel.new(replica_id.new("client-a"), or_map_kernel.TallyMode)
  let assert Ok(#(_, _, op, _)) = or_map_kernel.increment(state, "score", 4)
  op
}

fn sample_register_op() -> or_map_kernel.OrMapOp {
  let state =
    or_map_kernel.new(replica_id.new("client-a"), or_map_kernel.RegisterMode)
  let assert Ok(#(_, _, op, _)) =
    or_map_kernel.set_register(state, "name", "Ada", 123)
  op
}

fn sample_remove_op() -> or_map_kernel.OrMapOp {
  let state =
    or_map_kernel.new(replica_id.new("client-a"), or_map_kernel.TallyMode)
  let assert Ok(#(state, _, _, _)) = or_map_kernel.increment(state, "score", 4)
  let #(_, _, op, _) = or_map_kernel.remove(state, "score")
  op
}

fn round_trip_or_map_op(op: or_map_kernel.OrMapOp) {
  let encoded = ops.encode_or_map_envelope("scores", op) |> json.to_string
  let decoded = parse(encoded, or_map_envelope_decoder())
  decoded |> expect.to_equal(#("scores", op))
}

fn or_map_envelope_decoder() -> decode.Decoder(#(String, or_map_kernel.OrMapOp)) {
  use address <- decode.field("address", decode.string)
  use op <- decode.field("contents", ops.or_map_op_decoder())
  decode.success(#(address, op))
}

pub fn or_map_increment_op_round_trip_test() {
  round_trip_or_map_op(sample_tally_op())
}

pub fn or_map_register_op_round_trip_test() {
  round_trip_or_map_op(sample_register_op())
}

pub fn or_map_remove_op_round_trip_test() {
  round_trip_or_map_op(sample_remove_op())
}

pub fn or_map_channel_op_stage_two_decode_test() {
  let op = sample_tally_op()
  let encoded =
    ops.encode_channel_envelope("scores", channel.OrMapOp(op))
    |> json.to_string
  let dynamic = parse(encoded, decode.dynamic)
  case ops.decode_op_contents(dynamic) {
    Ok(ops.ChannelOp(address, payload)) -> {
      address |> expect.to_equal("scores")
      decode.run(payload, ops.channel_op_decoder(channel.OrMapChannel))
      |> expect.to_equal(Ok(channel.OrMapOp(op)))
      decode.run(payload, ops.channel_op_decoder(channel.MapChannel))
      |> expect.to_be_error()
      decode.run(payload, ops.channel_op_decoder(channel.CounterChannel))
      |> expect.to_be_error()
      Nil
    }
    _ -> panic as "or-map channel op decode failed"
  }
}

pub fn or_map_attach_codec_round_trip_test() {
  let state =
    or_map_kernel.new(replica_id.new("client-a"), or_map_kernel.TallyMode)
  let assert Ok(#(state, _, _, _)) = or_map_kernel.increment(state, "score", 4)
  let encoded =
    ops.encode_attach(
      "scores",
      channel.OrMapSnapshot(state.mode, state.optimistic),
    )
    |> json.to_string
  string_contains(encoded, "\"channelType\":\"ormap\"") |> expect.to_be_true()
  let dynamic = parse(encoded, decode.dynamic)
  case ops.decode_op_contents(dynamic) {
    Ok(ops.AttachOp(address, channel.OrMapSnapshot(mode, snapshot))) -> {
      address |> expect.to_equal("scores")
      mode |> expect.to_equal(or_map_kernel.TallyMode)
      let assert Ok(kernel) =
        or_map_kernel.from_sequenced(snapshot, mode, replica_id.new("loader"))
      or_map_kernel.entries(kernel)
      |> expect.to_equal([#("score", or_map_kernel.Tally(4))])
    }
    _ -> panic as "or-map attach decode failed"
  }
}

pub fn summary_blob_mixed_channel_types_round_trip_test() {
  let or_map =
    or_map_kernel.new(replica_id.new("client-a"), or_map_kernel.TallyMode)
  let assert Ok(#(or_map, _, _, _)) =
    or_map_kernel.increment(or_map, "score", 2)
  let encoded =
    summary_blob.encode_channels(9, [
      #("root", channel.MapSnapshot([#("k", json.int(1))])),
      #("tally", channel.CounterSnapshot(7)),
      #("scores", channel.OrMapSnapshot(or_map.mode, or_map.optimistic)),
      #("locks", channel.ClaimsSnapshot([#("owner", json.string("alice"), 9)])),
    ])
    |> json.to_string
  string_contains(encoded, "\"type\":\"counter\"") |> expect.to_be_true()
  string_contains(encoded, "\"type\":\"ormap\"") |> expect.to_be_true()
  string_contains(encoded, "\"type\":\"claims\"") |> expect.to_be_true()
  case summary_blob.decode(encoded) {
    Ok(blob) -> {
      blob.sequence_number |> expect.to_equal(9)
      let assert [
        root,
        tally,
        summary_blob.ChannelSnapshot(
          address: "scores",
          snapshot: channel.OrMapSnapshot(mode, snapshot),
        ),
        locks,
      ] = blob.channels
      root
      |> expect.to_equal(summary_blob.ChannelSnapshot(
        address: "root",
        snapshot: channel.MapSnapshot([#("k", json.int(1))]),
      ))
      tally
      |> expect.to_equal(summary_blob.ChannelSnapshot(
        address: "tally",
        snapshot: channel.CounterSnapshot(7),
      ))
      mode |> expect.to_equal(or_map_kernel.TallyMode)
      let assert Ok(kernel) =
        or_map_kernel.from_sequenced(snapshot, mode, replica_id.new("loader"))
      or_map_kernel.entries(kernel)
      |> expect.to_equal([#("score", or_map_kernel.Tally(2))])
      locks
      |> expect.to_equal(summary_blob.ChannelSnapshot(
        address: "locks",
        snapshot: channel.ClaimsSnapshot([
          #("owner", json.string("alice"), 9),
        ]),
      ))
    }

    Error(_) -> panic as "mixed summary decode failed"
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Register collection channels
// ─────────────────────────────────────────────────────────────────────────────

pub fn register_collection_op_round_trip_test() {
  let op =
    register_collection_kernel.Write("station", json.string("A"), ref_seq: 7)
  let encoded =
    ops.encode_register_collection_envelope("registers", op)
    |> json.to_string
  let decoded = parse(encoded, register_collection_envelope_decoder())
  decoded |> expect.to_equal(#("registers", op))
}

fn register_collection_envelope_decoder() -> decode.Decoder(
  #(String, register_collection_kernel.WriteOp),
) {
  use address <- decode.field("address", decode.string)
  use op <- decode.field("contents", ops.register_collection_op_decoder())
  decode.success(#(address, op))
}

pub fn register_collection_channel_op_stage_two_decode_test() {
  let op =
    register_collection_kernel.Write("station", json.string("A"), ref_seq: 7)
  let encoded =
    ops.encode_channel_envelope("registers", channel.RegisterCollectionOp(op))
    |> json.to_string
  let dynamic = parse(encoded, decode.dynamic)
  case ops.decode_op_contents(dynamic) {
    Ok(ops.ChannelOp(address, payload)) -> {
      address |> expect.to_equal("registers")
      decode.run(
        payload,
        ops.channel_op_decoder(channel.RegisterCollectionChannel),
      )
      |> expect.to_equal(Ok(channel.RegisterCollectionOp(op)))
      decode.run(payload, ops.channel_op_decoder(channel.MapChannel))
      |> expect.to_be_error()
      decode.run(payload, ops.channel_op_decoder(channel.CounterChannel))
      |> expect.to_be_error()
      Nil
    }
    _ -> panic as "register collection channel op decode failed"
  }
}

pub fn register_collection_snapshot_round_trip_test() {
  let version = register_collection_kernel.VersionedValue(json.string("A"), 5)
  let snapshot =
    channel.RegisterCollectionSnapshot([
      #("station", register_collection_kernel.Register(version, [version])),
    ])
  let encoded = ops.encode_attach("registers", snapshot) |> json.to_string
  string_contains(encoded, "\"channelType\":\"registerCollection\"")
  |> expect.to_be_true()
  let dynamic = parse(encoded, decode.dynamic)
  case ops.decode_op_contents(dynamic) {
    Ok(ops.AttachOp(address, decoded)) -> {
      address |> expect.to_equal("registers")
      decoded |> expect.to_equal(snapshot)
    }
    _ -> panic as "register collection attach decode failed"
  }
}
