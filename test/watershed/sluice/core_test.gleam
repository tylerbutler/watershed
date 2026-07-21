//// Pure-core behavior tests for the in-memory sluice (plan HM2). Each drives the
//// state machine through `handle`/`take` and decodes the queued frames with
//// the client's own codecs, so the assertions are on real wire shapes.

import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import startest/expect

import signet/types as token
import spillway/message
import spillway/types

import watershed/sluice/core.{type Outbound, type Sluice}
import watershed/wire
import watershed/wire/socket

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

fn to_dynamic(value: json.Json) -> decode.Dynamic {
  let assert Ok(dynamic) = json.parse(json.to_string(value), decode.dynamic)
  dynamic
}

fn test_client() -> types.Client {
  types.Client(
    mode: types.WriteMode,
    details: types.ClientDetails(
      capabilities: types.ClientCapabilities(interactive: True),
      client_type: None,
      environment: None,
      device: None,
    ),
    permission: [],
    user: token.User(id: "user", properties: dict.new()),
    scopes: ["doc:read", "doc:write"],
    timestamp: None,
  )
}

fn connect_message() -> message.ConnectMessage {
  message.ConnectMessage(
    tenant_id: "default",
    document_id: "dice",
    token: Some("jwt"),
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

/// Register a client and drive its `connect_document` handshake.
fn connect(sluice: Sluice, last_seen: option.Option(Int)) -> #(Sluice, String) {
  let #(sluice, client_id) = core.register(sluice)
  let payload = socket.encode_connect_document(connect_message(), last_seen)
  let sluice =
    core.handle(sluice, client_id, "connect_document", to_dynamic(payload))
  #(sluice, client_id)
}

/// Submit a single map op from `client_id`.
fn submit(sluice: Sluice, client_id: String, csn: Int, rsn: Int) -> Sluice {
  let op =
    wire.OutboundOp(
      client_sequence_number: csn,
      reference_sequence_number: rsn,
      op_type: "op",
      contents: json.object([#("n", json.int(csn))]),
      metadata: None,
    )
  let payload = socket.encode_submit_op(client_id, [[op]])
  core.handle(sluice, client_id, "submitOp", to_dynamic(payload))
}

/// Drain every deliverable frame, oldest first.
fn drain(sluice: Sluice) -> #(Sluice, List(Outbound)) {
  case core.take(sluice) {
    #(sluice, None) -> #(sluice, [])
    #(sluice, Some(frame)) -> {
      let #(sluice, rest) = drain(sluice)
      #(sluice, [frame, ..rest])
    }
  }
}

fn of_event(frames: List(Outbound), event: String) -> List(Outbound) {
  list.filter(frames, fn(frame) { frame.event == event })
}

fn op_of(frame: Outbound) -> types.SequencedDocumentMessage {
  let assert Ok(message) =
    json.parse(json.to_string(frame.payload), socket.op_message_decoder())
  let assert [op] = message.ops
  op
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

pub fn connect_replies_with_connected_frame_test() {
  let #(sluice, client_id) = connect(core.new("default", "dice"), None)
  let #(_hub, frames) = drain(sluice)

  let assert [frame] = frames
  frame.client_id |> expect.to_equal(client_id)
  frame.event |> expect.to_equal("connect_document_success")

  let assert Ok(connected) =
    json.parse(
      json.to_string(frame.payload),
      socket.connected_message_decoder(),
    )
  connected.client_id |> expect.to_equal(client_id)
  connected.checkpoint_sequence_number |> expect.to_equal(Some(0))
}

pub fn sequencing_is_monotone_per_document_test() {
  let sluice = core.new("default", "dice")
  let #(sluice, c1) = connect(sluice, None)
  let #(sluice, c2) = connect(sluice, None)
  // Drain the two handshake replies.
  let #(sluice, _) = drain(sluice)

  let sluice = submit(sluice, c1, 1, 0)
  let sluice = submit(sluice, c2, 1, 0)
  let #(_hub, frames) = drain(sluice)

  let ops = of_event(frames, "op")
  // Each op is broadcast to both clients: 2 ops × 2 clients = 4 frames.
  list.length(ops) |> expect.to_equal(4)
  let sns = list.map(ops, fn(frame) { op_of(frame).sequence_number })
  // First op's echoes carry SN 1, the second op's carry SN 2, monotone.
  sns |> expect.to_equal([1, 1, 2, 2])
}

pub fn author_echo_carries_client_sequence_number_test() {
  let sluice = core.new("default", "dice")
  let #(sluice, c1) = connect(sluice, None)
  let #(sluice, _) = drain(sluice)

  let sluice = submit(sluice, c1, 7, 0)
  let #(_hub, frames) = drain(sluice)

  let assert [frame] = of_event(frames, "op")
  let op = op_of(frame)
  frame.client_id |> expect.to_equal(c1)
  // The echo the author's kernel acks on carries the CSN it submitted.
  op.client_sequence_number |> expect.to_equal(7)
  op.client_id |> expect.to_equal(Some(c1))
  op.sequence_number |> expect.to_equal(1)
}

pub fn reconnect_catch_up_replays_exactly_the_gap_test() {
  let sluice = core.new("default", "dice")
  let #(sluice, c1) = connect(sluice, None)
  let #(sluice, _) = drain(sluice)

  // Log three ops (SN 1, 2, 3).
  let sluice = submit(sluice, c1, 1, 0)
  let sluice = submit(sluice, c1, 2, 1)
  let sluice = submit(sluice, c1, 3, 2)
  let #(sluice, _) = drain(sluice)

  // A late joiner that has seen up to SN 1 catches up on 2 and 3 only.
  let #(sluice, _c2) = connect(sluice, Some(1))
  let #(_hub, frames) = drain(sluice)

  let assert [frame] = frames
  let assert Ok(connected) =
    json.parse(
      json.to_string(frame.payload),
      socket.connected_message_decoder(),
    )
  let sns = list.map(connected.initial_messages, fn(op) { op.sequence_number })
  sns |> expect.to_equal([2, 3])
  connected.checkpoint_sequence_number |> expect.to_equal(Some(3))
}

pub fn signal_fan_out_excludes_author_and_strips_type_test() {
  let sluice = core.new("default", "dice")
  let #(sluice, c1) = connect(sluice, None)
  let #(sluice, c2) = connect(sluice, None)
  let #(sluice, _) = drain(sluice)

  let signal =
    socket.encode_submit_ripple(
      client_id: c1,
      ripple_type: "presence",
      content: json.object([#("kind", json.string("presence"))]),
    )
  let sluice = core.handle(sluice, c1, "submitSignal", to_dynamic(signal))
  let #(_hub, frames) = drain(sluice)

  let signals = of_event(frames, "signal")
  // Exactly one recipient — the author never hears its own ripple.
  let assert [frame] = signals
  frame.client_id |> expect.to_equal(c2)

  let assert Ok(ripple) =
    json.parse(json.to_string(frame.payload), socket.ripple_message_decoder())
  ripple.signal_type |> expect.to_equal(None)
}

pub fn peek_reveals_next_frame_without_consuming_test() {
  let sluice = core.new("default", "dice")
  let #(sluice, c1) = connect(sluice, None)
  let #(sluice, _) = drain(sluice)

  let sluice = submit(sluice, c1, 1, 0)

  // Peek reports the pending echo but leaves it queued...
  let assert Some(peeked) = core.peek(sluice)
  peeked.client_id |> expect.to_equal(c1)
  peeked.event |> expect.to_equal("op")

  // ...so a subsequent take still delivers the same frame.
  let #(sluice, taken) = core.take(sluice)
  let assert Some(frame) = taken
  frame.client_id |> expect.to_equal(c1)

  // With the queue drained, peek agrees nothing is deliverable.
  core.peek(sluice) |> expect.to_equal(None)
}

pub fn peek_skips_paused_clients_test() {
  let sluice = core.new("default", "dice")
  let #(sluice, c1) = connect(sluice, None)
  let #(sluice, c2) = connect(sluice, None)
  let #(sluice, _) = drain(sluice)

  // Hold c1, then have it author an op both should receive. c1's echo is
  // queued first but held, so peek surfaces c2's copy instead.
  let sluice = core.pause(sluice, c1)
  let sluice = submit(sluice, c1, 1, 0)

  let assert Some(peeked) = core.peek(sluice)
  peeked.client_id |> expect.to_equal(c2)
}

pub fn pause_holds_a_clients_frames_until_resume_test() {
  let sluice = core.new("default", "dice")
  let #(sluice, c1) = connect(sluice, None)
  let #(sluice, c2) = connect(sluice, None)
  let #(sluice, _) = drain(sluice)

  // Hold c2, then let c1 author an op both should receive.
  let sluice = core.pause(sluice, c2)
  let sluice = submit(sluice, c1, 1, 0)

  // With c2 paused, only c1's echo is deliverable.
  let #(sluice, delivered) = drain(sluice)
  let recipients = list.map(delivered, fn(frame) { frame.client_id })
  recipients |> expect.to_equal([c1])

  // Releasing c2 makes its held frame deliverable.
  let sluice = core.resume(sluice, c2)
  let #(_hub, after_resume) = drain(sluice)
  let recipients2 = list.map(after_resume, fn(frame) { frame.client_id })
  recipients2 |> expect.to_equal([c2])
}
