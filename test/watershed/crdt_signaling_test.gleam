//// Deterministic tests for the reference signaling protocol.
////
//// Nothing here opens a real socket. `crdt_signaling` is a pure frame
//// codec and a pure room registry, which is what lets the room cap, the
//// discovery contract, duplicate ids, cross-room targeting, and every
//// rejection path be pinned down exactly, in one process, with no
//// timing. The browser adapter (`crdt_signaling_js`) is exercised here
//// too, against a scripted `WebSocket` stub, for the lifecycle rules a
//// real socket makes non-deterministic.
////
//// The service that runs this protocol over `ws` is tested in
//// `tools/signaling/test.mjs`; the two suites are deliberately split
//// along that seam.

@target(javascript)
import gleam/int
@target(javascript)
import gleam/json
@target(javascript)
import gleam/list
@target(javascript)
import gleam/string
@target(javascript)
import startest/expect

@target(javascript)
import watershed/channel
@target(javascript)
import watershed/crdt_core
@target(javascript)
import watershed/crdt_signaling.{
  type Action, type Rooms, Close, Join, Leave, Send, Signal,
}
@target(javascript)
import watershed/crdt_signaling_js
@target(javascript)
import watershed/crdt_wire
@target(javascript)
import watershed/p2p_transport_js.{type Signal, Answer, Candidate, Offer}
@target(javascript)
import watershed/transport_js.{type Cell}

@target(javascript)
const room = "trip-planning"

// ─────────────────────────────────────────────────────────────────────────────
// Frame vocabulary
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn client_frames_round_trip_test() -> Nil {
  [
    Join(room: room, peer: "alpha"),
    Signal(to: "beta", payload: Offer("v=0 offer")),
    Signal(to: "beta", payload: Answer("v=0 answer")),
    Signal(to: "beta", payload: Candidate("{\"candidate\":\"host\"}")),
    Leave,
  ]
  |> list.each(fn(frame) {
    crdt_signaling.client_to_string(frame)
    |> crdt_signaling.decode_client
    |> expect.to_equal(Ok(frame))
  })
}

@target(javascript)
pub fn server_frames_round_trip_test() -> Nil {
  [
    crdt_signaling.Joined(room: room, peer: "beta", peers: ["alpha"]),
    crdt_signaling.PeerJoined("gamma"),
    crdt_signaling.PeerLeft("gamma"),
    crdt_signaling.Forwarded("alpha", Candidate("{}")),
    crdt_signaling.Rejected("roomFull", "8"),
    crdt_signaling.Dropped("unknownTarget", "beta"),
  ]
  |> list.each(fn(frame) {
    crdt_signaling.server_to_string(frame)
    |> crdt_signaling.decode_server
    |> expect.to_equal(Ok(frame))
  })
}

@target(javascript)
/// The whole security claim of the design, stated as a test: no document
/// envelope, and no fragment of one, decodes as a client frame.
pub fn document_envelopes_are_not_client_frames_test() -> Nil {
  let document = pn_counter_document("alpha")
  let assert Ok(#(document, outcome)) =
    crdt_core.edit(document, crdt_wire.root_address, channel.PnCounterEdit(1))

  let messages = [
    crdt_core.hello_message(document),
    crdt_core.state_message(document),
    crdt_core.state_request_message(),
    crdt_core.digest_message(document),
    ..outcome.broadcast
  ]

  list.each(messages, fn(message) {
    // The whole envelope, as it goes onto a data channel.
    crdt_core.encode(document, message)
    |> crdt_signaling.decode_client
    |> expect.to_equal(Error(crdt_signaling.Malformed("not a signaling frame")))

    // And the bare message, in case an adapter ever tried to hand one to
    // signaling without its envelope.
    json.to_string(crdt_wire.encode_message(message))
    |> crdt_signaling.decode_client
    |> expect.to_equal(Error(crdt_signaling.Malformed("not a signaling frame")))
  })
}

@target(javascript)
pub fn unknown_tags_and_broken_json_are_refused_test() -> Nil {
  [
    "{\"t\":\"relay\",\"payload\":\"anything\"}",
    "{\"t\":\"join\"}",
    "{\"t\":\"signal\",\"to\":\"beta\"}",
    "{\"t\":\"signal\",\"to\":\"beta\",\"payload\":{\"t\":\"delta\"}}",
    "{not json",
    "[]",
    "\"join\"",
  ]
  |> list.each(fn(raw) {
    crdt_signaling.decode_client(raw)
    |> expect.to_equal(Error(crdt_signaling.Malformed("not a signaling frame")))
  })
}

@target(javascript)
pub fn oversize_frames_are_refused_before_parsing_test() -> Nil {
  let padding = string.repeat("x", crdt_signaling.max_frame_bytes)
  let raw =
    crdt_signaling.client_to_string(Signal(to: "beta", payload: Offer(padding)))

  case crdt_signaling.decode_client(raw) {
    Error(crdt_signaling.FrameTooLarge(bytes)) ->
      { bytes > crdt_signaling.max_frame_bytes } |> expect.to_be_true()
    other -> panic as { "expected FrameTooLarge, got " <> string.inspect(other) }
  }
}

@target(javascript)
pub fn empty_and_overlong_ids_are_refused_test() -> Nil {
  crdt_signaling.client_to_string(Join(room: "", peer: "alpha"))
  |> crdt_signaling.decode_client
  |> expect.to_equal(Error(crdt_signaling.InvalidId("room id is empty")))

  crdt_signaling.client_to_string(Join(room: room, peer: ""))
  |> crdt_signaling.decode_client
  |> expect.to_equal(Error(crdt_signaling.InvalidId("peer id is empty")))

  let long = string.repeat("p", crdt_signaling.max_id_bytes + 1)
  crdt_signaling.client_to_string(Join(room: room, peer: long))
  |> crdt_signaling.decode_client
  |> expect.to_equal(
    Error(crdt_signaling.InvalidId("peer id is longer than 128 bytes")),
  )
}

@target(javascript)
/// The bound is bytes, not graphemes: 128 four-byte emoji are 512 bytes
/// of id echoed to every member of a room, however short they look.
pub fn ids_are_bounded_by_utf8_bytes_test() -> Nil {
  let emoji = string.repeat("🤝", 33)
  { string.length(emoji) <= crdt_signaling.max_id_bytes }
  |> expect.to_be_true()

  crdt_signaling.client_to_string(Join(room: room, peer: emoji))
  |> crdt_signaling.decode_client
  |> expect.to_equal(
    Error(crdt_signaling.InvalidId("peer id is longer than 128 bytes")),
  )

  // And one that fits in bytes is still admitted.
  let short = string.repeat("🤝", 32)
  crdt_signaling.client_to_string(Join(room: room, peer: short))
  |> crdt_signaling.decode_client
  |> expect.to_equal(Ok(Join(room: room, peer: short)))
}

// ─────────────────────────────────────────────────────────────────────────────
// Room membership
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn the_first_peer_joins_an_empty_room_test() -> Nil {
  let #(rooms, actions) =
    crdt_signaling.handle_frame(
      crdt_signaling.new_rooms(),
      1,
      crdt_signaling.client_to_string(Join(room: room, peer: "alpha")),
    )

  actions
  |> expect.to_equal([
    Send(1, crdt_signaling.Joined(room: room, peer: "alpha", peers: [])),
  ])
  crdt_signaling.members(rooms, room) |> expect.to_equal(["alpha"])
  crdt_signaling.room_names(rooms) |> expect.to_equal([room])
}

@target(javascript)
/// The transport's discovery contract: the smaller of any two peers must
/// learn about the larger. Announcing to both sides satisfies it for
/// every pair, which is what this asserts.
pub fn a_join_is_announced_in_both_directions_test() -> Nil {
  let rooms = joined(crdt_signaling.new_rooms(), [#(1, "alpha"), #(2, "beta")])
  let #(rooms, actions) = join(rooms, 3, "gamma")

  actions
  |> expect.to_equal([
    Send(
      3,
      crdt_signaling.Joined(room: room, peer: "gamma", peers: ["alpha", "beta"]),
    ),
    Send(1, crdt_signaling.PeerJoined("gamma")),
    Send(2, crdt_signaling.PeerJoined("gamma")),
  ])
  crdt_signaling.members(rooms, room)
  |> expect.to_equal(["alpha", "beta", "gamma"])
}

@target(javascript)
pub fn the_ninth_peer_is_refused_test() -> Nil {
  let limit = crdt_signaling.room_limit()
  let filled =
    upto(limit)
    |> list.map(fn(index) { #(index, "peer-" <> int.to_string(index)) })
    |> joined(crdt_signaling.new_rooms(), _)

  let #(rooms, actions) = join(filled, limit + 1, "one-too-many")

  actions
  |> expect.to_equal([
    Send(limit + 1, crdt_signaling.Rejected("roomFull", int.to_string(limit))),
    Close(limit + 1, "roomFull"),
  ])
  crdt_signaling.members(rooms, room)
  |> list.length
  |> expect.to_equal(limit)
}

@target(javascript)
pub fn a_duplicate_peer_id_is_refused_test() -> Nil {
  let rooms = joined(crdt_signaling.new_rooms(), [#(1, "alpha")])
  let #(rooms, actions) = join(rooms, 2, "alpha")

  actions
  |> expect.to_equal([
    Send(2, crdt_signaling.Rejected("duplicatePeerId", "alpha")),
    Close(2, "duplicatePeerId"),
  ])
  // The connection that already holds the id is untouched.
  crdt_signaling.members(rooms, room) |> expect.to_equal(["alpha"])
  crdt_signaling.membership(rooms, 1) |> expect.to_equal(Ok(#(room, "alpha")))
  crdt_signaling.membership(rooms, 2) |> expect.to_equal(Error(Nil))
}

@target(javascript)
pub fn joining_twice_on_one_connection_is_refused_test() -> Nil {
  let rooms = joined(crdt_signaling.new_rooms(), [#(1, "alpha")])
  let #(rooms, actions) = join(rooms, 1, "alpha-again")

  actions
  |> expect.to_equal([
    Send(
      1,
      crdt_signaling.Rejected(
        "alreadyJoined",
        "this connection has already joined",
      ),
    ),
    Close(1, "alreadyJoined"),
  ])
  crdt_signaling.members(rooms, room) |> expect.to_equal(["alpha"])
}

@target(javascript)
pub fn a_leave_is_announced_and_an_empty_room_is_deleted_test() -> Nil {
  let rooms = joined(crdt_signaling.new_rooms(), [#(1, "alpha"), #(2, "beta")])

  let #(rooms, actions) =
    crdt_signaling.handle_frame(
      rooms,
      2,
      crdt_signaling.client_to_string(Leave),
    )
  actions |> expect.to_equal([Send(1, crdt_signaling.PeerLeft("beta"))])
  crdt_signaling.members(rooms, room) |> expect.to_equal(["alpha"])

  // A disconnect after a leave is a no-op: the connection is already gone.
  let #(rooms, actions) = crdt_signaling.disconnect(rooms, 2)
  actions |> expect.to_equal([])

  let #(rooms, actions) = crdt_signaling.disconnect(rooms, 1)
  actions |> expect.to_equal([])
  crdt_signaling.members(rooms, room) |> expect.to_equal([])
  crdt_signaling.room_names(rooms) |> expect.to_equal([])
}

@target(javascript)
pub fn a_disconnect_notifies_the_room_test() -> Nil {
  let rooms =
    joined(crdt_signaling.new_rooms(), [
      #(1, "alpha"),
      #(2, "beta"),
      #(3, "gamma"),
    ])
  let #(rooms, actions) = crdt_signaling.disconnect(rooms, 2)

  actions
  |> expect.to_equal([
    Send(1, crdt_signaling.PeerLeft("beta")),
    Send(3, crdt_signaling.PeerLeft("beta")),
  ])
  crdt_signaling.members(rooms, room) |> expect.to_equal(["alpha", "gamma"])
}

// ─────────────────────────────────────────────────────────────────────────────
// Routing
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn a_payload_goes_to_one_named_peer_test() -> Nil {
  let rooms =
    joined(crdt_signaling.new_rooms(), [
      #(1, "alpha"),
      #(2, "beta"),
      #(3, "gamma"),
    ])

  let #(_rooms, actions) =
    crdt_signaling.handle_frame(
      rooms,
      1,
      crdt_signaling.client_to_string(Signal(
        to: "gamma",
        payload: Offer("v=0 alpha"),
      )),
    )

  actions
  |> expect.to_equal([
    Send(3, crdt_signaling.Forwarded("alpha", Offer("v=0 alpha"))),
  ])
}

@target(javascript)
/// Naming a peer in another room is a peer addressing across the only
/// boundary this protocol has. Terminal, and the target hears nothing.
pub fn a_target_in_another_room_closes_the_sender_test() -> Nil {
  let rooms = joined(crdt_signaling.new_rooms(), [#(1, "alpha")])
  let #(rooms, _) =
    crdt_signaling.handle_frame(
      rooms,
      2,
      crdt_signaling.client_to_string(Join(room: "other-room", peer: "beta")),
    )

  let #(rooms, actions) =
    crdt_signaling.handle_frame(
      rooms,
      2,
      crdt_signaling.client_to_string(Signal(
        to: "alpha",
        payload: Offer("v=0 cross-room"),
      )),
    )

  actions
  |> expect.to_equal([
    Send(2, crdt_signaling.Rejected("crossRoomTarget", "alpha")),
    Close(2, "crossRoomTarget"),
  ])
  crdt_signaling.members(rooms, room) |> expect.to_equal(["alpha"])
  crdt_signaling.members(rooms, "other-room") |> expect.to_equal(["beta"])
}

@target(javascript)
/// A target that is in no room at all is a peer that left between the
/// sender deciding to write and the frame arriving — an ICE candidate
/// racing a leave, which every mesh does constantly. The frame is
/// dropped and the sender keeps its membership: closing it would let any
/// peer take another down by leaving at the wrong moment.
pub fn a_signal_to_a_departed_peer_is_dropped_not_fatal_test() -> Nil {
  let rooms = joined(crdt_signaling.new_rooms(), [#(1, "alpha"), #(2, "beta")])
  let #(rooms, _) = crdt_signaling.disconnect(rooms, 2)

  let #(rooms, actions) =
    crdt_signaling.handle_frame(
      rooms,
      1,
      crdt_signaling.client_to_string(Signal(
        to: "beta",
        payload: Candidate("{\"candidate\":\"host\"}"),
      )),
    )

  actions
  |> expect.to_equal([Send(1, crdt_signaling.Dropped("unknownTarget", "beta"))])
  crdt_signaling.members(rooms, room) |> expect.to_equal(["alpha"])
  crdt_signaling.membership(rooms, 1)
  |> expect.to_equal(Ok(#(room, "alpha")))

  // And the sender can still route to a peer that is there.
  let #(rooms, _) = join(rooms, 3, "gamma")
  let #(_rooms, actions) =
    crdt_signaling.handle_frame(
      rooms,
      1,
      crdt_signaling.client_to_string(Signal(
        to: "gamma",
        payload: Offer("v=0 alpha"),
      )),
    )
  actions
  |> expect.to_equal([
    Send(3, crdt_signaling.Forwarded("alpha", Offer("v=0 alpha"))),
  ])
}

@target(javascript)
/// The cross-room check reads an index rather than scanning every room,
/// so the index has to stay honest as rooms fill and empty. Peer ids are
/// unique inside a room and not across them, which is why it counts.
pub fn a_departed_cross_room_target_becomes_a_drop_test() -> Nil {
  let rooms = joined(crdt_signaling.new_rooms(), [#(1, "alpha")])
  let #(rooms, _) =
    crdt_signaling.handle_frame(
      rooms,
      2,
      crdt_signaling.client_to_string(Join(room: "room-two", peer: "shared")),
    )
  let #(rooms, _) =
    crdt_signaling.handle_frame(
      rooms,
      3,
      crdt_signaling.client_to_string(Join(room: "room-three", peer: "shared")),
    )

  // Two rooms hold `shared`, and naming it from a third is a violation.
  let #(rooms, actions) =
    crdt_signaling.handle_frame(
      rooms,
      1,
      crdt_signaling.client_to_string(Signal(
        to: "shared",
        payload: Offer("v=0"),
      )),
    )
  actions
  |> expect.to_equal([
    Send(1, crdt_signaling.Rejected("crossRoomTarget", "shared")),
    Close(1, "crossRoomTarget"),
  ])

  // One of the two leaves: still elsewhere, still a violation.
  let #(rooms, _) = crdt_signaling.disconnect(rooms, 2)
  let #(rooms, actions) =
    crdt_signaling.handle_frame(
      rooms,
      1,
      crdt_signaling.client_to_string(Signal(
        to: "shared",
        payload: Offer("v=0"),
      )),
    )
  actions
  |> expect.to_equal([
    Send(1, crdt_signaling.Rejected("crossRoomTarget", "shared")),
    Close(1, "crossRoomTarget"),
  ])

  // And when the last one goes, the id is nowhere and the frame is a
  // drop — the index did not keep a ghost.
  let #(rooms, _) = crdt_signaling.disconnect(rooms, 3)
  let #(_rooms, actions) =
    crdt_signaling.handle_frame(
      rooms,
      1,
      crdt_signaling.client_to_string(Signal(
        to: "shared",
        payload: Offer("v=0"),
      )),
    )
  actions
  |> expect.to_equal([
    Send(1, crdt_signaling.Dropped("unknownTarget", "shared")),
  ])
}

@target(javascript)
/// Which refusals end a connection, stated once, as a list.
pub fn only_violations_are_terminal_test() -> Nil {
  [
    crdt_signaling.FrameTooLarge(99_999),
    crdt_signaling.Malformed("not a signaling frame"),
    crdt_signaling.NotJoined,
    crdt_signaling.AlreadyJoined,
    crdt_signaling.DuplicatePeerId("alpha"),
    crdt_signaling.RoomFull(8),
    crdt_signaling.CrossRoomTarget("alpha"),
    crdt_signaling.InvalidId("peer id is empty"),
  ]
  |> list.each(fn(refusal) {
    crdt_signaling.is_terminal(refusal) |> expect.to_be_true()
  })

  crdt_signaling.is_terminal(crdt_signaling.UnknownTarget("beta"))
  |> expect.to_be_false()
}

@target(javascript)
pub fn signalling_before_joining_is_refused_test() -> Nil {
  let #(rooms, actions) =
    crdt_signaling.handle_frame(
      crdt_signaling.new_rooms(),
      1,
      crdt_signaling.client_to_string(Signal(to: "alpha", payload: Offer("v=0"))),
    )

  actions
  |> expect.to_equal([
    Send(1, crdt_signaling.Rejected("notJoined", "join before signalling")),
    Close(1, "notJoined"),
  ])
  crdt_signaling.room_names(rooms) |> expect.to_equal([])
}

@target(javascript)
/// A refused frame must not disturb the room it was refused from, on any
/// of the paths that can refuse one.
pub fn refusals_leave_the_registry_untouched_test() -> Nil {
  let rooms = joined(crdt_signaling.new_rooms(), [#(1, "alpha"), #(2, "beta")])
  let before = crdt_signaling.members(rooms, room)

  [
    "{not json",
    "{\"t\":\"relay\"}",
    crdt_signaling.client_to_string(Join(room: room, peer: "alpha")),
    crdt_signaling.client_to_string(Signal(to: "nobody", payload: Offer("v=0"))),
  ]
  |> list.each(fn(raw) {
    let #(after, _) = crdt_signaling.handle_frame(rooms, 2, raw)
    crdt_signaling.members(after, room) |> expect.to_equal(before)
  })
}

// ─────────────────────────────────────────────────────────────────────────────
// The service seam
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// `serve` classifies by frame type, never by contents — which is what
/// makes a service's instrumentation honest.
pub fn serve_tags_frames_by_type_test() -> Nil {
  let rooms = crdt_signaling.new_rooms()
  let #(rooms, actions, tag) =
    crdt_signaling.serve(
      rooms,
      1,
      crdt_signaling.client_to_string(Join(room: room, peer: "alpha")),
    )
  tag |> expect.to_equal("join")
  actions
  |> expect.to_equal([
    #(
      1,
      crdt_signaling.server_to_string(
        crdt_signaling.Joined(room: room, peer: "alpha", peers: []),
      ),
      "",
    ),
  ])

  let #(rooms, _, tag) =
    crdt_signaling.serve(
      rooms,
      2,
      crdt_signaling.client_to_string(Join(room: room, peer: "beta")),
    )
  tag |> expect.to_equal("join")

  let #(rooms, _, tag) =
    crdt_signaling.serve(
      rooms,
      2,
      crdt_signaling.client_to_string(Signal(
        to: "alpha",
        payload: Answer("v=0"),
      )),
    )
  tag |> expect.to_equal("signal")

  let #(rooms, _, tag) =
    crdt_signaling.serve(rooms, 2, crdt_signaling.client_to_string(Leave))
  tag |> expect.to_equal("leave")

  let document = pn_counter_document("alpha")
  let #(_rooms, actions, tag) =
    crdt_signaling.serve(
      rooms,
      3,
      crdt_core.encode(document, crdt_core.hello_message(document)),
    )
  tag |> expect.to_equal("rejected:malformed")
  actions
  |> list.map(fn(action) { action.2 })
  |> expect.to_equal(["", "malformed"])
}

@target(javascript)
/// A registry-level refusal is a refusal, not a `join` that happened to
/// produce a close. A service whose instrumentation could not tell them
/// apart would report a room that is turning every peer away as healthy.
pub fn serve_tags_registry_refusals_as_rejections_test() -> Nil {
  let limit = crdt_signaling.room_limit()
  let rooms =
    upto(limit)
    |> list.map(fn(index) { #(index, "peer-" <> int.to_string(index)) })
    |> joined(crdt_signaling.new_rooms(), _)

  let #(rooms, _, tag) =
    crdt_signaling.serve(
      rooms,
      limit + 1,
      crdt_signaling.client_to_string(Join(room: room, peer: "one-too-many")),
    )
  tag |> expect.to_equal("rejected:roomFull")

  let #(rooms, _, tag) =
    crdt_signaling.serve(
      rooms,
      limit + 2,
      crdt_signaling.client_to_string(Join(room: room, peer: "peer-1")),
    )
  tag |> expect.to_equal("rejected:duplicatePeerId")

  let #(rooms, _, tag) =
    crdt_signaling.serve(
      rooms,
      1,
      crdt_signaling.client_to_string(Join(room: room, peer: "peer-1")),
    )
  tag |> expect.to_equal("rejected:alreadyJoined")

  let #(rooms, _, tag) =
    crdt_signaling.serve(
      rooms,
      1,
      crdt_signaling.client_to_string(Signal(
        to: "nobody",
        payload: Offer("v=0"),
      )),
    )
  // A drop is tagged apart from a rejection: it closes nothing, and a
  // service counting rejections must not count it as one.
  tag |> expect.to_equal("dropped:unknownTarget")

  let #(_rooms, _, tag) =
    crdt_signaling.serve(
      rooms,
      limit + 3,
      crdt_signaling.client_to_string(Signal(
        to: "peer-1",
        payload: Offer("v=0"),
      )),
    )
  tag |> expect.to_equal("rejected:notJoined")
}

// ─────────────────────────────────────────────────────────────────────────────
// The browser adapter, over a scripted WebSocket
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
@external(javascript, "./ws_stub_ffi.mjs", "install")
fn install_stub() -> Nil

@target(javascript)
@external(javascript, "./ws_stub_ffi.mjs", "restore")
fn restore_stub() -> Nil

@target(javascript)
@external(javascript, "./ws_stub_ffi.mjs", "closeSocket")
fn close_stub_socket(index: Int, code: Int) -> Nil

@target(javascript)
@external(javascript, "./ws_stub_ffi.mjs", "socketCount")
fn stub_socket_count() -> Int

@target(javascript)
fn record_failed(cell: Cell(List(String))) -> fn(Signal) -> Nil {
  fn(signal) {
    case signal {
      p2p_transport_js.Failed(detail) ->
        transport_js.set_cell(cell, [detail, ..transport_js.get_cell(cell)])
      p2p_transport_js.Roster(_)
      | p2p_transport_js.PeerJoined(_)
      | p2p_transport_js.PeerLeft(_)
      | p2p_transport_js.Message(_, _) -> Nil
    }
  }
}

@target(javascript)
/// Each `join` owns its socket's whole lifecycle. A dead socket from an
/// earlier join that reports its close late must neither disarm the
/// current join's roster deadline nor swallow the current socket's own
/// failure — the state a socket's callbacks act on has to be the state of
/// the join that opened it.
pub fn a_late_close_from_an_old_socket_does_not_swallow_the_new_joins_failure_test() -> Nil {
  install_stub()
  let failures = transport_js.new_cell([])
  let signaling =
    crdt_signaling_js.websocket_signaling_with_timeout(
      url: "ws://stub.test/",
      on_failure: fn(detail) {
        transport_js.set_cell(failures, [
          detail,
          ..transport_js.get_cell(failures)
        ])
      },
      // No deadline timer: everything here is driven by hand.
      roster_timeout_ms: 0,
    )

  let first = transport_js.new_cell([])
  let assert Ok(_) = signaling.join(room, "alpha", record_failed(first))
  let second = transport_js.new_cell([])
  let assert Ok(_) = signaling.join(room, "alpha", record_failed(second))
  stub_socket_count() |> expect.to_equal(2)

  // The first join's socket dies late, after the second join replaced it.
  // Its failure belongs to the first join and to nobody else.
  close_stub_socket(0, 1006)
  transport_js.get_cell(first) |> list.length |> expect.to_equal(1)
  transport_js.get_cell(second) |> expect.to_equal([])

  // The second join's own socket then fails, and its failure must be
  // reported — not swallowed by the first socket's earlier one.
  close_stub_socket(1, 1006)
  transport_js.get_cell(second) |> list.length |> expect.to_equal(1)
  transport_js.get_cell(first) |> list.length |> expect.to_equal(1)
  transport_js.get_cell(failures) |> list.length |> expect.to_equal(2)
  restore_stub()
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
fn join(rooms: Rooms, connection: Int, peer: String) -> #(Rooms, List(Action)) {
  crdt_signaling.handle_frame(
    rooms,
    connection,
    crdt_signaling.client_to_string(Join(room: room, peer: peer)),
  )
}

@target(javascript)
fn joined(rooms: Rooms, peers: List(#(Int, String))) -> Rooms {
  list.fold(peers, rooms, fn(rooms, entry) {
    let #(rooms, _) = join(rooms, entry.0, entry.1)
    rooms
  })
}

@target(javascript)
fn pn_counter_document(replica: String) -> crdt_core.Document {
  let assert Ok(document) =
    crdt_core.new(crdt_core.config(
      room: room,
      compatibility: "signaling-test/v1",
      replica: replica,
      session: "session-" <> replica,
      root: channel.InitPnCounter,
    ))
  document
}

@target(javascript)
/// `1..count`, since this stdlib has no `list.range`.
fn upto(count: Int) -> List(Int) {
  build_upto(count, [])
}

@target(javascript)
fn build_upto(remaining: Int, acc: List(Int)) -> List(Int) {
  case remaining <= 0 {
    True -> acc
    False -> build_upto(remaining - 1, [remaining, ..acc])
  }
}
