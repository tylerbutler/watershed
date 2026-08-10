//// Pure-core behavior tests for the in-memory sluice (plan HM2). Each drives the
//// state machine through `handle`/`take` and decodes the queued frames with
//// the client's own codecs, so the assertions are on real wire shapes.

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
import watershed/sluice/core.{type Outbound, type Sluice}
import watershed/sluice/frames as frames_codec
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

  // Exactly one frame: the handshake. The joiner's own join op is *not* pushed
  // back to it — floodgate broadcasts that one with `broadcast_from`, which
  // excludes the joiner, so its only copy is the one in `initialMessages`.
  let assert [frame] = frames
  frame.client_id |> expect.to_equal(client_id)
  frame.event |> expect.to_equal("connect_document_success")

  let assert Ok(connected) =
    json.parse(
      json.to_string(frame.payload),
      socket.connected_message_decoder(),
    )
  connected.client_id |> expect.to_equal(client_id)
  // The client's own join is sequenced as SN 1, so the handshake checkpoint is
  // 1 rather than 0 — membership occupies the op stream like any other message.
  connected.checkpoint_sequence_number |> expect.to_equal(Some(1))
  // The roster seeds the client's quorum. It must name the joiner even though
  // it is the only member, or its consensus kernels start from an empty room.
  connected.initial_clients
  |> list.map(fn(client) { client.client_id })
  |> expect.to_equal([client_id])
}

/// A second client's arrival is broadcast to the room as a sequenced `"join"`,
/// so an already-connected replica widens its roster rather than staying on the
/// membership it was handed at connect time.
pub fn join_is_broadcast_to_the_existing_room_test() {
  let sluice = core.new("default", "dice")
  let #(sluice, c1) = connect(sluice, None)
  let #(sluice, _) = drain(sluice)

  let #(sluice, c2) = connect(sluice, None)
  let #(_hub, frames) = drain(sluice)

  // Only the client already in the room hears it as a live op; c2 gets its own
  // arrival through `initialMessages`, not as a push.
  let assert [broadcast] = of_event(frames, "op")
  broadcast.client_id |> expect.to_equal(c1)
  let join = op_of(broadcast)
  join.message_type |> expect.to_equal("join")
  join.client_id |> expect.to_equal(None)
  join.data
  |> expect.to_equal(Some(frames_codec.system_join_data(c2)))

  let assert [handshake] = of_event(frames, "connect_document_success")
  let assert Ok(connected) =
    json.parse(
      json.to_string(handshake.payload),
      socket.connected_message_decoder(),
    )
  connected.initial_clients
  |> list.map(fn(client) { client.client_id })
  |> list.sort(string.compare)
  |> expect.to_equal(list.sort([c1, c2], string.compare))
}

/// A departing client is announced to the room as a sequenced `"leave"`. This
/// is what drains a consensus signoff and re-releases a held queue job on every
/// surviving replica, at one agreed sequence point.
pub fn disconnect_broadcasts_a_leave_test() {
  let sluice = core.new("default", "dice")
  let #(sluice, c1) = connect(sluice, None)
  let #(sluice, c2) = connect(sluice, None)
  let #(sluice, _) = drain(sluice)

  let sluice = core.disconnect(sluice, c2)
  let #(_hub, frames) = drain(sluice)

  let assert [broadcast] = of_event(frames, "op")
  broadcast.client_id |> expect.to_equal(c1)
  let leave = op_of(broadcast)
  leave.message_type |> expect.to_equal("leave")
  leave.data |> expect.to_equal(Some(frames_codec.system_leave_data(c2)))
}

/// A connection that never completed `connect_document` is not in the roster,
/// so dropping it announces nothing — there is no membership change to report.
pub fn disconnect_before_handshake_sequences_nothing_test() {
  let sluice = core.new("default", "dice")
  let #(sluice, c1) = connect(sluice, None)
  let #(sluice, _) = drain(sluice)
  let before = core.sequence_number(sluice)

  let #(sluice, unconnected) = core.register(sluice)
  let sluice = core.disconnect(sluice, unconnected)
  let #(_hub, frames) = drain(sluice)

  core.sequence_number(sluice) |> expect.to_equal(before)
  of_event(frames, "op") |> expect.to_equal([])
  core.connected_ids(sluice) |> expect.to_equal([c1])
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
  // The two handshakes sequenced a join apiece (SN 1 and 2), so the first op's
  // echoes carry SN 3 and the second's SN 4 — still monotone, which is the
  // property under test.
  sns |> expect.to_equal([3, 3, 4, 4])
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
  // SN 1 went to c1's own join, so the first op is SN 2.
  op.sequence_number |> expect.to_equal(2)
}

/// The handshake answers a reconnect exactly as it answers a cold join — the
/// whole retained history and a checkpoint — and volunteers nothing else. This
/// is floodgate's shape, and `lastSeenSequenceNumber` has no effect on it.
///
/// It is the *reason* a reconnecting client has to send `requestOps`: it ignores
/// `initialMessages` (its core already holds that history), so the handshake
/// alone leaves it below the checkpoint with nothing inbound to close the gap.
pub fn reconnect_handshake_ignores_last_seen_and_pushes_no_ops_test() {
  let sluice = core.new("default", "dice")
  let #(sluice, c1) = connect(sluice, None)
  let #(sluice, _) = drain(sluice)

  // SN 1 is c1's join; the three ops are SN 2, 3, 4.
  let sluice = submit(sluice, c1, 1, 0)
  let sluice = submit(sluice, c1, 2, 1)
  let sluice = submit(sluice, c1, 3, 2)
  let #(sluice, _) = drain(sluice)

  let #(sluice, c2) = connect(sluice, Some(2))
  let #(sluice, frames) = drain(sluice)

  let assert [frame] = of_event(frames, "connect_document_success")
  frame.client_id |> expect.to_equal(c2)
  let assert Ok(connected) =
    json.parse(
      json.to_string(frame.payload),
      socket.connected_message_decoder(),
    )
  // Everything, not the slice after `Some(2)` — plus c2's own join at SN 5.
  list.map(connected.initial_messages, fn(op) { op.sequence_number })
  |> expect.to_equal([1, 2, 3, 4, 5])
  connected.checkpoint_sequence_number |> expect.to_equal(Some(5))

  // And nothing was pushed to c2 alongside it. Its own join reached it only
  // inside the handshake above.
  of_event(frames, "op")
  |> list.filter(fn(frame) { frame.client_id == c2 })
  |> expect.to_equal([])

  // `requestOps` is the only way across the gap, and it delivers all of it.
  let sluice =
    core.handle(
      sluice,
      c2,
      "requestOps",
      to_dynamic(socket.encode_request_ops(from: 2)),
    )
  let #(_hub, frames) = drain(sluice)
  let assert [frame] = of_event(frames, "op")
  frame.client_id |> expect.to_equal(c2)
  let assert Ok(message) =
    json.parse(json.to_string(frame.payload), socket.op_message_decoder())
  list.map(message.ops, fn(op) { op.sequence_number })
  |> expect.to_equal([3, 4, 5])
  list.map(message.ops, fn(op) { op.message_type })
  |> expect.to_equal(["op", "op", "join"])
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

// ─────────────────────────────────────────────────────────────────────────────
// Presence
// ─────────────────────────────────────────────────────────────────────────────

type Panel {
  Panel(name: String)
}

fn panel_decoder() -> decode.Decoder(Panel) {
  use name <- decode.field("panel", decode.string)
  decode.success(Panel(name))
}

fn panel(name: String) -> json.Json {
  json.object([#("meta", json.object([#("panel", json.string(name))]))])
}

fn presence_push(
  sluice: Sluice,
  client_id: String,
  event: String,
  payload: json.Json,
) -> Sluice {
  core.handle(sluice, client_id, event, to_dynamic(payload))
}

fn state_of(frame: Outbound) -> List(presence.PresenceEntry(Panel)) {
  let assert Ok(snapshot) =
    json.parse(
      json.to_string(frame.payload),
      presence.presence_state_decoder(decode: panel_decoder()),
    )
  let #(tracker, _) = presence.apply_state(presence.tracker(), snapshot)
  presence.tracker_entries(tracker)
}

fn diff_of(frame: Outbound) -> presence.Diff(Panel) {
  let assert Ok(diff) =
    json.parse(
      json.to_string(frame.payload),
      presence.presence_diff_decoder(decode: panel_decoder()),
    )
  diff
}

fn error_of(frame: Outbound) -> presence.PresenceError {
  let assert Ok(error) =
    json.parse(json.to_string(frame.payload), presence.presence_error_decoder())
  error
}

fn sessions_of(entries: List(presence.PresenceEntry(Panel))) -> List(String) {
  list.map(entries, fn(entry) { entry.session_id })
}

pub fn handshake_advertises_presence_v1_test() {
  let #(sluice, _) = connect(core.new("default", "dice"), None)
  let #(_hub, frames) = drain(sluice)
  let assert [handshake, ..] = frames
  let assert Ok(connected) =
    json.parse(
      json.to_string(handshake.payload),
      socket.connected_message_decoder(),
    )

  socket.supports_feature(
    connected.supported_features,
    socket.feature_presence_v1,
  )
  |> expect.to_be_true
}

pub fn presence_capability_can_be_withheld_test() {
  let sluice = core.set_presence_supported(core.new("default", "dice"), False)
  let #(sluice, _) = connect(sluice, None)
  let #(_hub, frames) = drain(sluice)
  let assert [handshake, ..] = frames
  let assert Ok(connected) =
    json.parse(
      json.to_string(handshake.payload),
      socket.connected_message_decoder(),
    )

  socket.supports_feature(
    connected.supported_features,
    socket.feature_presence_v1,
  )
  |> expect.to_be_false
}

/// Phoenix's join ordering: the snapshot is taken *before* the joiner is
/// tracked, so it learns of its own session from the diff that follows. A
/// snapshot that already contained the joiner would make the diff a duplicate.
pub fn joining_presence_sends_state_then_broadcasts_a_diff_test() {
  let sluice = core.new("default", "dice")
  let #(sluice, c1) = connect(sluice, None)
  let #(sluice, _) = drain(sluice)
  let sluice = presence_push(sluice, c1, "joinPresence", panel("sudoku"))
  let #(_hub, frames) = drain(sluice)

  let assert [state, diff] = frames

  state.event |> expect.to_equal("presence_state")
  state.client_id |> expect.to_equal(c1)
  state_of(state) |> expect.to_equal([])

  diff.event |> expect.to_equal("presence_diff")
  presence.diff_joins(diff_of(diff))
  |> expect.to_equal([
    presence.PresenceEntry(session_id: c1, key: "user", meta: Panel("sudoku")),
  ])
}

/// The second joiner's snapshot carries the first — this is the whole point of
/// server presence: a late client gets the roster at once, with no heartbeat to
/// wait out.
pub fn a_late_joiner_receives_the_existing_roster_in_its_snapshot_test() {
  let sluice = core.new("default", "dice")
  let #(sluice, c1) = connect(sluice, None)
  let #(sluice, c2) = connect(sluice, None)
  let sluice = presence_push(sluice, c1, "joinPresence", panel("sudoku"))
  let #(sluice, _) = drain(sluice)

  let sluice = presence_push(sluice, c2, "joinPresence", panel("text"))
  let #(_hub, frames) = drain(sluice)

  let assert [state, ..] = of_event(frames, "presence_state")
  state.client_id |> expect.to_equal(c2)
  state_of(state) |> sessions_of |> expect.to_equal([c1])
}

/// Two connections authenticated as the same user are two sessions under one
/// key, not one entry overwriting the other.
pub fn two_connections_share_a_key_as_separate_sessions_test() {
  let sluice = core.new("default", "dice")
  let #(sluice, c1) = connect(sluice, None)
  let #(sluice, c2) = connect(sluice, None)
  let sluice = presence_push(sluice, c1, "joinPresence", panel("sudoku"))
  let sluice = presence_push(sluice, c2, "joinPresence", panel("text"))
  let #(sluice, _) = drain(sluice)

  // A third connection's snapshot is the roster as the server sees it.
  let #(sluice, c3) = connect(sluice, None)
  let sluice = presence_push(sluice, c3, "joinPresence", panel("board"))
  let #(_hub, frames) = drain(sluice)

  let assert [state, ..] = of_event(frames, "presence_state")
  let entries = state_of(state)

  sessions_of(entries) |> expect.to_equal([c1, c2])
  presence.by_key(entries, "user") |> list.length |> expect.to_equal(2)
}

pub fn updating_presence_is_one_leave_and_join_test() {
  let sluice = core.new("default", "dice")
  let #(sluice, c1) = connect(sluice, None)
  let sluice = presence_push(sluice, c1, "joinPresence", panel("sudoku"))
  let #(sluice, _) = drain(sluice)

  let sluice = presence_push(sluice, c1, "updatePresence", panel("text"))
  let #(_hub, frames) = drain(sluice)

  let assert [frame] = of_event(frames, "presence_diff")
  let diff = diff_of(frame)

  presence.diff_leaves(diff)
  |> list.map(fn(entry) { entry.meta })
  |> expect.to_equal([Panel("sudoku")])
  presence.diff_joins(diff)
  |> list.map(fn(entry) { entry.meta })
  |> expect.to_equal([Panel("text")])
}

pub fn leaving_presence_broadcasts_only_leaves_test() {
  let sluice = core.new("default", "dice")
  let #(sluice, c1) = connect(sluice, None)
  let sluice = presence_push(sluice, c1, "joinPresence", panel("sudoku"))
  let #(sluice, _) = drain(sluice)

  let sluice = presence_push(sluice, c1, "leavePresence", json.object([]))
  let #(sluice, frames) = drain(sluice)

  let assert [frame] = of_event(frames, "presence_diff")
  presence.diff_joins(diff_of(frame)) |> expect.to_equal([])
  presence.diff_leaves(diff_of(frame))
  |> sessions_of
  |> expect.to_equal([c1])

  // A duplicate leave is a no-op, not an error: it races the socket's own
  // cleanup often enough that erroring would be noise.
  let sluice = presence_push(sluice, c1, "leavePresence", json.object([]))
  let #(_hub, again) = drain(sluice)
  again |> expect.to_equal([])
}

/// Socket loss removes presence with no browser involvement — the property the
/// heartbeat fallback can only approximate with a TTL.
pub fn disconnect_removes_presence_for_the_survivors_test() {
  let sluice = core.new("default", "dice")
  let #(sluice, c1) = connect(sluice, None)
  let #(sluice, c2) = connect(sluice, None)
  let sluice = presence_push(sluice, c1, "joinPresence", panel("sudoku"))
  let #(sluice, _) = drain(sluice)

  let sluice = core.disconnect(sluice, c1)
  let #(_hub, frames) = drain(sluice)

  let assert [frame] = of_event(frames, "presence_diff")
  frame.client_id |> expect.to_equal(c2)
  presence.diff_leaves(diff_of(frame)) |> sessions_of |> expect.to_equal([c1])
}

/// Presence must never be attributable to a socket that has not authenticated —
/// there is no user to derive a key from.
pub fn joining_presence_before_the_handshake_is_rejected_test() {
  let sluice = core.new("default", "dice")
  let #(sluice, client_id) = core.register(sluice)
  let sluice = presence_push(sluice, client_id, "joinPresence", panel("sudoku"))
  let #(_hub, frames) = drain(sluice)

  let assert [frame] = frames
  frame.event |> expect.to_equal("presence_error")
  error_of(frame)
  |> expect.to_equal(presence.Rejected(
    code: "unauthenticated",
    message: "presence requires a completed document connection",
  ))
}

pub fn claiming_a_server_owned_field_is_rejected_test() {
  let sluice = core.new("default", "dice")
  let #(sluice, c1) = connect(sluice, None)
  let #(sluice, _) = drain(sluice)

  let spoofed =
    json.object([
      #("key", json.string("user:root")),
      #("meta", json.object([#("panel", json.string("sudoku"))])),
    ])
  let sluice = presence_push(sluice, c1, "joinPresence", spoofed)
  let #(_hub, frames) = drain(sluice)

  let assert [frame] = frames
  frame.event |> expect.to_equal("presence_error")
  let assert presence.Rejected(code: code, message: _) = error_of(frame)
  code |> expect.to_equal("invalid_meta")
}

/// A reserved field *inside* `meta` is stripped rather than rejected, and the
/// server's own value is what reaches the wire.
pub fn reserved_fields_inside_meta_are_replaced_test() {
  let sluice = core.new("default", "dice")
  let #(sluice, c1) = connect(sluice, None)
  let #(sluice, _) = drain(sluice)

  let smuggled =
    json.object([
      #(
        "meta",
        json.object([
          #("panel", json.string("sudoku")),
          #("client_id", json.string("client-impostor")),
          #("phx_ref", json.string("ref-impostor")),
        ]),
      ),
    ])
  let sluice = presence_push(sluice, c1, "joinPresence", smuggled)
  let #(_hub, frames) = drain(sluice)

  let assert [frame] = of_event(frames, "presence_diff")
  presence.diff_joins(diff_of(frame))
  |> expect.to_equal([
    presence.PresenceEntry(session_id: c1, key: "user", meta: Panel("sudoku")),
  ])
}

pub fn updating_presence_without_joining_is_rejected_test() {
  let sluice = core.new("default", "dice")
  let #(sluice, c1) = connect(sluice, None)
  let #(sluice, _) = drain(sluice)

  let sluice = presence_push(sluice, c1, "updatePresence", panel("text"))
  let #(_hub, frames) = drain(sluice)

  let assert [frame] = frames
  let assert presence.Rejected(code: code, message: _) = error_of(frame)
  code |> expect.to_equal("not_joined")
}
