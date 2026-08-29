//// Deterministic tests for the WebRTC transport, driven by the fake
//// browser and fake signaling hub in `p2p_fake`.
////
//// Nothing here needs a browser. `p2p_transport_js.start_with_rtc` takes
//// the `Rtc` seam, and the fake models exactly what the transport is
//// entitled to depend on: signaling state transitions, implicit rollback,
//// one offerer-created data channel per link, string delivery, and
//// asynchronous failures. That is enough to pin down negotiation roles,
//// glare, candidate queueing, the room cap, duplicate signals, error
//// propagation, and cleanup.
////
//// The real-browser counterpart is `p2p_browser_smoke.gleam`, run by
//// `smoke/p2p_browser.mjs`. These tests are the mandatory ones: they run
//// in the normal JavaScript suite, browser or no browser.

@target(javascript)
import exception
@target(javascript)
import gleam/int
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{type Option, None, Some}
@target(javascript)
import gleam/string
@target(javascript)
import startest/expect

@target(javascript)
import watershed/p2p
@target(javascript)
import watershed/p2p_fake
@target(javascript)
import watershed/p2p_transport_js.{
  type Callbacks, type Signal, type Status, type Transport, Answer, Callbacks,
  Candidate, Message, Offer, PeerJoined, PeerLeft, Signaling,
}
@target(javascript)
import watershed/transport_js.{type Cell}

// ─────────────────────────────────────────────────────────────────────────────
// Harness
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
const room = "trip-planning"

@target(javascript)
fn recorder() -> #(Cell(List(String)), Callbacks) {
  let events = transport_js.new_cell([])
  #(
    events,
    Callbacks(
      on_peer_open: fn(peer) { push(events, "open " <> peer) },
      on_peer_close: fn(peer) { push(events, "close " <> peer) },
      on_document: fn(peer, data) {
        push(events, "doc " <> peer <> " " <> data)
      },
      on_status: fn(status) { push(events, "status " <> render_status(status)) },
      on_error: fn(error) { push(events, "error " <> render_error(error)) },
    ),
  )
}

@target(javascript)
fn push(cell: Cell(List(String)), entry: String) -> Nil {
  transport_js.set_cell(cell, [entry, ..transport_js.get_cell(cell)])
}

@target(javascript)
fn entries(cell: Cell(List(String))) -> List(String) {
  list.reverse(transport_js.get_cell(cell))
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

@target(javascript)
fn saw(cell: Cell(List(String)), fragment: String) -> Bool {
  list.any(entries(cell), fn(entry) { string.contains(entry, fragment) })
}

@target(javascript)
fn count(entries: List(String), fragment: String) -> Int {
  entries
  |> list.filter(fn(entry) { string.contains(entry, fragment) })
  |> list.length
}

@target(javascript)
/// Rendered by hand rather than with `string.inspect`, so an assertion
/// pins the status a transport reported and not the compiler's current
/// spelling of a labelled record.
fn render_status(status: Status) -> String {
  case status {
    p2p_transport_js.SignalingJoined(joined_room, peer_id) ->
      "SignalingJoined " <> joined_room <> " " <> peer_id
    p2p_transport_js.SignalingRoster(peers) ->
      "SignalingRoster " <> string.join(peers, ",")
    p2p_transport_js.SignalingLeft -> "SignalingLeft"
    p2p_transport_js.PeerConnecting(peer) -> "PeerConnecting " <> peer
    p2p_transport_js.PeerOpen(peer) -> "PeerOpen " <> peer
    p2p_transport_js.PeerClosed(peer) -> "PeerClosed " <> peer
    p2p_transport_js.PeerFailed(peer, detail) ->
      "PeerFailed " <> peer <> " " <> detail
    p2p_transport_js.IceState(peer, ice) -> "IceState " <> peer <> " " <> ice
    p2p_transport_js.PeerCount(open) -> "PeerCount " <> int.to_string(open)
  }
}

@target(javascript)
fn render_error(error: p2p.P2pError) -> String {
  case error {
    p2p.RoomFull(limit) -> "RoomFull " <> int.to_string(limit)
    p2p.SignalingFailed(detail) -> "SignalingFailed " <> detail
    p2p.PeerConnectionFailed(peer, detail) ->
      "PeerConnectionFailed " <> peer <> " " <> detail
    p2p.InvalidEnvelope(peer, detail) ->
      "InvalidEnvelope " <> peer <> " " <> detail
    p2p.UnsupportedChannel(_)
    | p2p.RootMismatch(..)
    | p2p.ChannelTypeMismatch(..)
    | p2p.DocumentClosed
    | p2p.CompatibilityMismatch(..)
    | p2p.ProtocolMismatch(..)
    | p2p.RoomMismatch
    | p2p.SequencerUnavailable(_)
    | p2p.SequencerUnsupported
    | p2p.SnapshotTooLarge(..)
    | p2p.ReplicaCollision(_) -> string.inspect(error)
  }
}

@target(javascript)
/// A transport wired to the shared signaling hub, so several of them form
/// a mesh under one `settle`.
fn start_meshed(
  world: p2p_fake.World,
  peer_id: String,
) -> #(Transport, Cell(List(String))) {
  let #(events, callbacks) = recorder()
  let assert Ok(transport) =
    p2p_transport_js.start_with_rtc(
      room: room,
      peer_id: peer_id,
      signaling: p2p_fake.signaling(world),
      ice_servers: [],
      callbacks: callbacks,
      rtc: p2p_fake.rtc(world, peer_id),
    )
  #(transport, events)
}

@target(javascript)
/// A transport whose inbound signals the test delivers by hand.
fn start_scripted(
  world: p2p_fake.World,
  peer_id: String,
) -> #(Transport, fn(Signal) -> Nil, Cell(List(String))) {
  start_scripted_with_ice(world, peer_id, [])
}

@target(javascript)
/// `start_scripted` with caller-supplied ICE servers.
fn start_scripted_with_ice(
  world: p2p_fake.World,
  peer_id: String,
  ice_servers: List(p2p_transport_js.IceServer),
) -> #(Transport, fn(Signal) -> Nil, Cell(List(String))) {
  let inbox = transport_js.new_cell(fn(_signal: Signal) { Nil })
  let #(events, callbacks) = recorder()
  let assert Ok(transport) =
    p2p_transport_js.start_with_rtc(
      room: room,
      peer_id: peer_id,
      signaling: p2p_fake.scripted_signaling(world, fn(on_signal) {
        transport_js.set_cell(inbox, on_signal)
      }),
      ice_servers: ice_servers,
      callbacks: callbacks,
      rtc: p2p_fake.rtc(world, peer_id),
    )
  #(transport, fn(signal) { transport_js.get_cell(inbox)(signal) }, events)
}

@target(javascript)
/// Drive one scripted peer all the way to an open channel: it is the
/// offerer, so it offers, and the remote answers.
fn negotiate_as_offerer(
  world: p2p_fake.World,
  deliver: fn(Signal) -> Nil,
  remote: String,
) -> Nil {
  deliver(PeerJoined(remote))
  p2p_fake.settle(world)
  deliver(Message(remote, Answer("sdp:their-answer")))
  p2p_fake.settle(world)
}

// ─────────────────────────────────────────────────────────────────────────────
// Configuration
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn ice_configuration_ships_no_defaults_test() -> Nil {
  p2p_transport_js.rtc_configuration_json([])
  |> expect.to_equal("{\"iceServers\":[]}")
}

@target(javascript)
pub fn ice_configuration_uses_browser_rtc_configuration_shape_test() -> Nil {
  [
    p2p_transport_js.ice_server(urls: ["stun:stun.example:3478"]),
    p2p_transport_js.ice_server(urls: [
      "turn:turn.example:3478",
      "turns:turn.example:5349",
    ])
      |> p2p_transport_js.with_credentials(
        username: "alice",
        credential: "s3cret",
      ),
  ]
  |> p2p_transport_js.rtc_configuration_json
  |> expect.to_equal(
    "{\"iceServers\":["
    <> "{\"urls\":[\"stun:stun.example:3478\"]},"
    <> "{\"urls\":[\"turn:turn.example:3478\",\"turns:turn.example:5349\"],"
    <> "\"username\":\"alice\",\"credential\":\"s3cret\"}"
    <> "]}",
  )
}

@target(javascript)
pub fn public_stun_preset_is_stun_only_and_credential_free_test() -> Nil {
  // The preset must never grow a TURN url or a credential: it is the
  // "nothing deployed, nothing secret" option, and a credential in a
  // shipped library would be everyone's credential.
  p2p_transport_js.public_stun_servers()
  |> p2p_transport_js.rtc_configuration_json
  |> expect.to_equal(
    "{\"iceServers\":["
    <> "{\"urls\":[\"stun:stun.l.google.com:19302\"]},"
    <> "{\"urls\":[\"stun:stun.cloudflare.com:3478\"]}"
    <> "]}",
  )
}

@target(javascript)
pub fn document_channel_is_unordered_and_reliable_test() -> Nil {
  p2p_transport_js.document_channel_label
  |> expect.to_equal("watershed-crdt-v1")

  // Reliability is the *absence* of both lossy options, so the encoded
  // init must carry `ordered` and nothing else.
  p2p_transport_js.document_channel_options_json()
  |> expect.to_equal("{\"ordered\":false}")
}

@target(javascript)
pub fn room_limit_is_the_core_default_test() -> Nil {
  p2p_transport_js.room_limit() |> expect.to_equal(8)
}

@target(javascript)
pub fn caller_ice_configuration_reaches_every_connection_test() -> Nil {
  let world = p2p_fake.new_world()
  let servers = [
    p2p_transport_js.ice_server(urls: ["stun:stun.example:3478"]),
    p2p_transport_js.ice_server(urls: ["turn:turn.example:3478"])
      |> p2p_transport_js.with_credentials(
        username: "alice",
        credential: "s3cret",
      ),
  ]
  let #(_, deliver, _) = start_scripted_with_ice(world, "peer-a", servers)

  deliver(PeerJoined("peer-z"))
  deliver(PeerJoined("peer-y"))
  p2p_fake.settle(world)

  // Not "some configuration was passed": the exact `RTCConfiguration` the
  // caller's servers encode to, for every connection the transport builds.
  let expected = p2p_transport_js.rtc_configuration_json(servers)
  expected
  |> expect.to_equal(
    "{\"iceServers\":["
    <> "{\"urls\":[\"stun:stun.example:3478\"]},"
    <> "{\"urls\":[\"turn:turn.example:3478\"],"
    <> "\"username\":\"alice\",\"credential\":\"s3cret\"}"
    <> "]}",
  )
  p2p_fake.configurations(world)
  |> expect.to_equal([
    #("peer-a->peer-z", expected),
    #("peer-a->peer-y", expected),
  ])
}

@target(javascript)
pub fn empty_room_or_peer_id_is_rejected_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(_, callbacks) = recorder()

  p2p_transport_js.start_with_rtc(
    room: "",
    peer_id: "peer-a",
    signaling: p2p_fake.signaling(world),
    ice_servers: [],
    callbacks: callbacks,
    rtc: p2p_fake.rtc(world, "peer-a"),
  )
  |> expect.to_equal(Error(p2p.SignalingFailed("room id must not be empty")))

  p2p_transport_js.start_with_rtc(
    room: room,
    peer_id: "",
    signaling: p2p_fake.signaling(world),
    ice_servers: [],
    callbacks: callbacks,
    rtc: p2p_fake.rtc(world, ""),
  )
  |> expect.to_equal(Error(p2p.SignalingFailed("peer id must not be empty")))
}

@target(javascript)
pub fn signaling_join_failure_is_typed_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(_, callbacks) = recorder()
  p2p_fake.fail_join(world, "room admission refused")

  p2p_transport_js.start_with_rtc(
    room: room,
    peer_id: "peer-a",
    signaling: p2p_fake.signaling(world),
    ice_servers: [],
    callbacks: callbacks,
    rtc: p2p_fake.rtc(world, "peer-a"),
  )
  |> expect.to_equal(Error(p2p.SignalingFailed("room admission refused")))
}

// ─────────────────────────────────────────────────────────────────────────────
// Negotiation
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn two_peers_negotiate_and_open_one_channel_each_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(a, events_a) = start_meshed(world, "peer-a")
  let #(b, events_b) = start_meshed(world, "peer-b")
  p2p_fake.settle(world)

  p2p_transport_js.open_peers(a) |> expect.to_equal(["peer-b"])
  p2p_transport_js.open_peers(b) |> expect.to_equal(["peer-a"])
  p2p_transport_js.open_peer_count(a) |> expect.to_equal(1)

  saw(events_a, "status PeerConnecting") |> expect.to_be_true()
  saw(events_a, "open peer-b") |> expect.to_be_true()
  saw(events_b, "open peer-a") |> expect.to_be_true()
  saw(events_a, "status PeerCount 1") |> expect.to_be_true()

  // Exactly one document channel, created by the lexicographically smaller
  // peer and received by the other.
  p2p_fake.channel_specs(world)
  |> expect.to_equal([#("peer-a", "watershed-crdt-v1", "{\"ordered\":false}")])
}

@target(javascript)
pub fn only_the_smaller_peer_offers_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(_, _) = start_meshed(world, "peer-z")
  let #(_, _) = start_meshed(world, "peer-a")
  p2p_fake.settle(world)

  p2p_fake.called(world, "peer-a offer peer-z") |> expect.to_be_true()
  p2p_fake.called(world, "peer-z offer peer-a") |> expect.to_be_false()
  p2p_fake.called(world, "peer-z accept_offer peer-a") |> expect.to_be_true()
  p2p_fake.called(world, "peer-a accept_answer peer-z") |> expect.to_be_true()
}

@target(javascript)
pub fn document_strings_cross_the_data_channel_verbatim_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(a, _) = start_meshed(world, "peer-a")
  let #(b, events_b) = start_meshed(world, "peer-b")
  p2p_fake.settle(world)

  let envelope =
    "{\"v\":1,\"room\":\"trip-planning\",\"from\":\"replica-a\","
    <> "\"session\":\"s1\",\"message\":{\"type\":\"delta\"}}"

  p2p_transport_js.send(a, "peer-b", envelope) |> expect.to_be_true()
  p2p_fake.settle(world)
  saw(events_b, "doc peer-a " <> envelope) |> expect.to_be_true()

  // And nothing about it reached signaling.
  p2p_transport_js.broadcast(b, envelope) |> expect.to_equal(1)
  p2p_fake.settle(world)
  p2p_fake.signaling_payloads(world)
  |> list.any(fn(payload) { string.contains(payload, "delta") })
  |> expect.to_be_false()
}

@target(javascript)
pub fn signaling_carries_only_offers_answers_and_candidates_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(a, _) = start_meshed(world, "peer-a")
  let #(_, _) = start_meshed(world, "peer-b")
  p2p_fake.settle(world)
  p2p_transport_js.broadcast(a, "{\"v\":1,\"message\":{\"type\":\"state\"}}")
  p2p_fake.settle(world)

  let payloads = p2p_fake.signaling_payloads(world)
  payloads |> list.is_empty |> expect.to_be_false()
  payloads
  |> list.all(fn(payload) {
    string.contains(payload, " offer ")
    || string.contains(payload, " answer ")
    || string.contains(payload, " candidate ")
  })
  |> expect.to_be_true()
  payloads
  |> list.any(fn(payload) { string.contains(payload, "\"v\":1") })
  |> expect.to_be_false()
}

@target(javascript)
pub fn broadcast_reaches_every_open_peer_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(a, _) = start_meshed(world, "peer-a")
  let #(_, events_b) = start_meshed(world, "peer-b")
  let #(_, events_c) = start_meshed(world, "peer-c")
  p2p_fake.settle(world)

  p2p_transport_js.open_peers(a) |> expect.to_equal(["peer-b", "peer-c"])
  p2p_transport_js.broadcast(a, "hello") |> expect.to_equal(2)
  p2p_fake.settle(world)
  saw(events_b, "doc peer-a hello") |> expect.to_be_true()
  saw(events_c, "doc peer-a hello") |> expect.to_be_true()
}

@target(javascript)
pub fn send_to_a_peer_without_an_open_channel_reports_not_delivered_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(a, _, deliver) = swap(start_scripted(world, "peer-a"))
  deliver(PeerJoined("peer-z"))
  p2p_fake.settle(world)

  p2p_transport_js.known_peers(a) |> expect.to_equal(["peer-z"])
  p2p_transport_js.open_peers(a) |> expect.to_equal([])
  p2p_transport_js.send(a, "peer-z", "hello") |> expect.to_be_false()
  p2p_transport_js.send(a, "nobody", "hello") |> expect.to_be_false()
  p2p_transport_js.broadcast(a, "hello") |> expect.to_equal(0)
}

@target(javascript)
/// `start_scripted` returns `#(transport, deliver, events)`; several tests
/// want the events last, so this reorders once instead of at every call.
fn swap(
  triple: #(Transport, fn(Signal) -> Nil, Cell(List(String))),
) -> #(Transport, Cell(List(String)), fn(Signal) -> Nil) {
  #(triple.0, triple.2, triple.1)
}

// ─────────────────────────────────────────────────────────────────────────────
// Peer discovery
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// A roster to the newcomer and nothing to the room: the shape of an
/// adapter that answers "who is here?" on join and never announces.
pub fn only_the_newcomer_being_told_still_opens_the_link_test() -> Nil {
  let world = p2p_fake.new_world()
  p2p_fake.set_join_notice(world, p2p_fake.NotifyNewcomer)
  let #(z, _) = start_meshed(world, "peer-z")
  // The newcomer sorts first, so it is the side that offers.
  let #(a, _) = start_meshed(world, "peer-a")
  p2p_fake.settle(world)

  p2p_transport_js.open_peers(a) |> expect.to_equal(["peer-z"])
  p2p_transport_js.open_peers(z) |> expect.to_equal(["peer-a"])
  // peer-z was told nothing at all: it learned of peer-a from the offer,
  // and still ended up with exactly one channel between them.
  p2p_fake.channel_specs(world)
  |> expect.to_equal([#("peer-a", "watershed-crdt-v1", "{\"ordered\":false}")])
}

@target(javascript)
/// The mirror shape: only the members already in the room hear about a
/// newcomer. It carries the pair whose existing member offers.
pub fn only_the_existing_member_being_told_still_opens_the_link_test() -> Nil {
  let world = p2p_fake.new_world()
  p2p_fake.set_join_notice(world, p2p_fake.NotifyExistingMembers)
  let #(a, _) = start_meshed(world, "peer-a")
  let #(z, _) = start_meshed(world, "peer-z")
  p2p_fake.settle(world)

  p2p_transport_js.open_peers(a) |> expect.to_equal(["peer-z"])
  p2p_transport_js.open_peers(z) |> expect.to_equal(["peer-a"])
  p2p_fake.channel_specs(world)
  |> expect.to_equal([#("peer-a", "watershed-crdt-v1", "{\"ordered\":false}")])
}

@target(javascript)
/// And the pair that shape does *not* carry, which is the one case the
/// discovery contract in `Signaling` calls out: the side that offers was
/// told nothing, so the link waits for it to learn — by any route, once,
/// with nothing repeated on the side that already knew.
pub fn a_link_only_the_larger_side_knows_about_opens_when_the_smaller_learns_test() -> Nil {
  let world = p2p_fake.new_world()
  p2p_fake.set_join_notice(world, p2p_fake.NotifyExistingMembers)
  let #(z, events_z) = start_meshed(world, "peer-z")
  let #(a, _) = start_meshed(world, "peer-a")
  p2p_fake.settle(world)

  p2p_transport_js.known_peers(z) |> expect.to_equal(["peer-a"])
  p2p_transport_js.open_peers(z) |> expect.to_equal([])
  p2p_transport_js.known_peers(a) |> expect.to_equal([])
  saw(events_z, "status PeerConnecting peer-a") |> expect.to_be_true()

  p2p_fake.announce_peer(world, "peer-a", "peer-z")
  p2p_fake.settle(world)

  p2p_transport_js.open_peers(a) |> expect.to_equal(["peer-z"])
  p2p_transport_js.open_peers(z) |> expect.to_equal(["peer-a"])
  // The waiting side needed no second `PeerJoined`, and built no second
  // connection.
  count(p2p_fake.calls(world), "peer-z open peer-a") |> expect.to_equal(1)
  p2p_fake.channel_specs(world)
  |> expect.to_equal([#("peer-a", "watershed-crdt-v1", "{\"ordered\":false}")])
}

@target(javascript)
/// The mirror, and the reason the contract does not call either one-sided
/// shape sufficient: a roster carries only the pairs whose newcomer sorts
/// first, exactly as a notice to the room carries only the pairs whose
/// existing member does.
pub fn a_roster_does_not_carry_a_newcomer_that_sorts_last_test() -> Nil {
  let world = p2p_fake.new_world()
  p2p_fake.set_join_notice(world, p2p_fake.NotifyNewcomer)
  let #(a, _) = start_meshed(world, "peer-a")
  let #(z, events_z) = start_meshed(world, "peer-z")
  p2p_fake.settle(world)

  // peer-z was handed the roster, but it is the larger ID, so it does not
  // offer; peer-a was told nothing and cannot.
  p2p_transport_js.known_peers(z) |> expect.to_equal(["peer-a"])
  p2p_transport_js.open_peers(z) |> expect.to_equal([])
  p2p_transport_js.known_peers(a) |> expect.to_equal([])
  saw(events_z, "status PeerConnecting peer-a") |> expect.to_be_true()
  p2p_fake.channel_specs(world) |> expect.to_equal([])

  p2p_fake.announce_peer(world, "peer-a", "peer-z")
  p2p_fake.settle(world)

  p2p_transport_js.open_peers(a) |> expect.to_equal(["peer-z"])
  p2p_transport_js.open_peers(z) |> expect.to_equal(["peer-a"])
}

@target(javascript)
/// An offer that overtakes its `PeerJoined` is enough on its own, and the
/// `PeerJoined` behind it adds nothing.
pub fn an_offer_that_arrives_before_its_peer_joined_is_answered_once_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(transport, _, deliver) = swap(start_scripted(world, "peer-z"))

  deliver(Message("peer-a", Offer("sdp:their-offer")))
  p2p_fake.settle(world)
  deliver(PeerJoined("peer-a"))
  p2p_fake.settle(world)

  p2p_transport_js.known_peers(transport) |> expect.to_equal(["peer-a"])
  count(p2p_fake.calls(world), "peer-z open peer-a") |> expect.to_equal(1)
  count(p2p_fake.calls(world), "peer-z accept_offer peer-a")
  |> expect.to_equal(1)
  count(p2p_fake.signaling_payloads(world), " answer ") |> expect.to_equal(1)
}

@target(javascript)
/// The same ordering on the offering side. A peer that has already offered
/// is sending its own channel in-band, so the late `PeerJoined` must not
/// add a second one — whatever the peer IDs sort to.
pub fn a_peer_that_offered_first_gets_no_second_channel_test() -> Nil {
  let world = p2p_fake.new_world()
  // "peer-a" < "peer-z", so peer-a would normally create the channel.
  let #(transport, _, deliver) = swap(start_scripted(world, "peer-a"))

  deliver(Message("peer-z", Offer("sdp:their-offer")))
  p2p_fake.settle(world)
  deliver(PeerJoined("peer-z"))
  deliver(PeerJoined("peer-z"))
  p2p_fake.settle(world)

  p2p_transport_js.known_peers(transport) |> expect.to_equal(["peer-z"])
  p2p_fake.called(world, "peer-a open_channel peer-z") |> expect.to_be_false()
  p2p_fake.channel_specs(world) |> expect.to_equal([])
  count(p2p_fake.calls(world), "peer-a accept_offer peer-z")
  |> expect.to_equal(1)
}

@target(javascript)
/// A `createDataChannel` that fails leaves the peer connected and channel-
/// less, so the next time the adapter mentions that peer the channel is
/// attempted again rather than assumed to exist.
pub fn a_channel_that_could_not_be_created_is_retried_on_the_next_notice_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(transport, events, deliver) = swap(start_scripted(world, "peer-a"))
  p2p_fake.set_channel_failure(world, True)

  deliver(PeerJoined("peer-z"))
  p2p_fake.settle(world)

  saw(events, "error PeerConnectionFailed peer-z channel: fake channel refusal")
  |> expect.to_be_true()
  p2p_fake.called(world, "peer-a offer peer-z") |> expect.to_be_false()
  p2p_transport_js.open_peers(transport) |> expect.to_equal([])

  p2p_fake.set_channel_failure(world, False)
  deliver(PeerJoined("peer-z"))
  p2p_fake.settle(world)

  p2p_fake.called(world, "peer-a offer peer-z") |> expect.to_be_true()
  count(p2p_fake.calls(world), "peer-a open peer-z") |> expect.to_equal(1)
  count(p2p_fake.signaling_payloads(world), " offer ") |> expect.to_equal(1)
}

// ─────────────────────────────────────────────────────────────────────────────
// Perfect negotiation
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn impolite_peer_ignores_a_colliding_offer_test() -> Nil {
  let world = p2p_fake.new_world()
  // "peer-a" < "peer-z": peer-a offers, and is the impolite side.
  let #(_, _, deliver) = swap(start_scripted(world, "peer-a"))
  deliver(PeerJoined("peer-z"))
  p2p_fake.settle(world)
  p2p_fake.link_state(world, "peer-a", "peer-z")
  |> expect.to_equal("have-local-offer")

  deliver(Message("peer-z", Offer("sdp:their-offer")))
  p2p_fake.settle(world)

  // The offer is dropped: no answer is produced and the local offer stands.
  p2p_fake.called(world, "peer-a accept_offer peer-z") |> expect.to_be_false()
  p2p_fake.link_state(world, "peer-a", "peer-z")
  |> expect.to_equal("have-local-offer")
  p2p_fake.rollbacks(world) |> expect.to_equal([])
}

@target(javascript)
pub fn polite_peer_rolls_back_on_a_colliding_offer_test() -> Nil {
  let world = p2p_fake.new_world()
  // "peer-z" > "peer-a": peer-z answers, and is the polite side.
  let #(_, _, deliver) = swap(start_scripted(world, "peer-z"))
  deliver(PeerJoined("peer-a"))
  p2p_fake.settle(world)
  // It made no offer of its own, so nothing has collided yet.
  p2p_fake.called(world, "peer-z offer peer-a") |> expect.to_be_false()

  // A renegotiation puts a local offer outstanding, and the remote offer
  // then collides with it.
  p2p_fake.force_negotiation(world, "peer-z", "peer-a")
  p2p_fake.settle(world)
  p2p_fake.link_state(world, "peer-z", "peer-a")
  |> expect.to_equal("have-local-offer")

  deliver(Message("peer-a", Offer("sdp:their-offer")))
  p2p_fake.settle(world)

  p2p_fake.called(world, "peer-z accept_offer peer-a") |> expect.to_be_true()
  p2p_fake.rollbacks(world) |> expect.to_equal(["peer-z<-peer-a"])
  p2p_fake.link_state(world, "peer-z", "peer-a") |> expect.to_equal("stable")
}

@target(javascript)
pub fn an_ignored_offer_suppresses_only_its_own_candidate_failure_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(_, events, deliver) = swap(start_scripted(world, "peer-a"))
  negotiate_as_offerer(world, deliver, "peer-z")

  // A renegotiation collision, refused by the impolite side.
  p2p_fake.force_negotiation(world, "peer-a", "peer-z")
  p2p_fake.settle(world)
  deliver(Message("peer-z", Offer("sdp:their-offer")))
  p2p_fake.settle(world)

  // The candidates of the refused description cannot apply, and that is
  // expected rather than an error.
  p2p_fake.set_candidate_failure(world, True)
  deliver(Message("peer-z", Candidate("{\"candidate\":\"c1\"}")))
  p2p_fake.settle(world)
  saw(events, "error PeerConnectionFailed") |> expect.to_be_false()
}

@target(javascript)
pub fn a_candidate_failure_with_no_ignored_offer_is_reported_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(_, events, deliver) = swap(start_scripted(world, "peer-a"))
  negotiate_as_offerer(world, deliver, "peer-z")

  p2p_fake.set_candidate_failure(world, True)
  deliver(Message("peer-z", Candidate("{\"candidate\":\"c1\"}")))
  p2p_fake.settle(world)

  saw(events, "error PeerConnectionFailed") |> expect.to_be_true()
  saw(events, "fake candidate rejection") |> expect.to_be_true()
}

@target(javascript)
/// A failed offer must not leave the collision guard armed.
///
/// `making_offer` is set before `setLocalDescription` and cleared when the
/// description arrives. If a rejection skipped that clearing, this peer —
/// the impolite side — would read every later remote offer as a collision
/// and refuse all of them, and the link would never open again.
pub fn a_failed_offer_does_not_wedge_the_collision_guard_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(transport, events, deliver) = swap(start_scripted(world, "peer-a"))
  p2p_fake.set_offer_failure(world, True)

  deliver(PeerJoined("peer-z"))
  p2p_fake.settle(world)

  saw(events, "error PeerConnectionFailed peer-z offer: fake offer rejection")
  |> expect.to_be_true()
  count(p2p_fake.signaling_payloads(world), " offer ") |> expect.to_equal(0)
  // Reported, not terminal: a description can fail without the link being
  // beyond repair.
  p2p_transport_js.known_peers(transport) |> expect.to_equal(["peer-z"])

  p2p_fake.set_offer_failure(world, False)
  deliver(Message("peer-z", Offer("sdp:their-offer")))
  p2p_fake.settle(world)

  p2p_fake.called(world, "peer-a accept_offer peer-z") |> expect.to_be_true()
  count(p2p_fake.signaling_payloads(world), " answer ") |> expect.to_equal(1)
}

@target(javascript)
/// The same "finally" for the answer stage: an offer that could not be
/// applied is not remembered as applied, so its retransmission is answered
/// instead of dropped as a duplicate.
pub fn a_failed_answer_stage_forgets_the_offer_it_could_not_apply_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(_, events, deliver) = swap(start_scripted(world, "peer-z"))
  deliver(PeerJoined("peer-a"))
  p2p_fake.settle(world)

  deliver(Message("peer-a", Offer("sdp:their-offer")))
  p2p_fake.settle(world)
  p2p_fake.fire_failure(
    world,
    "peer-z",
    "peer-a",
    "answer",
    "InvalidStateError",
  )
  p2p_fake.settle(world)
  saw(events, "error PeerConnectionFailed peer-a answer: InvalidStateError")
  |> expect.to_be_true()

  deliver(Message("peer-a", Offer("sdp:their-offer")))
  p2p_fake.settle(world)

  count(p2p_fake.calls(world), "peer-z accept_offer peer-a")
  |> expect.to_equal(2)
}

// ─────────────────────────────────────────────────────────────────────────────
// ICE candidate queueing
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn remote_candidates_queue_until_a_remote_description_exists_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(_, _, deliver) = swap(start_scripted(world, "peer-z"))
  deliver(PeerJoined("peer-a"))
  p2p_fake.settle(world)

  deliver(Message("peer-a", Candidate("{\"candidate\":\"c1\"}")))
  deliver(Message("peer-a", Candidate("{\"candidate\":\"c2\"}")))
  deliver(Message("peer-a", Candidate("{\"candidate\":\"c3\"}")))
  p2p_fake.settle(world)
  p2p_fake.applied_candidates(world, "peer-z", "peer-a") |> expect.to_equal([])

  deliver(Message("peer-a", Offer("sdp:their-offer")))
  p2p_fake.settle(world)

  // Flushed in arrival order, not reversed and not reordered.
  p2p_fake.applied_candidates(world, "peer-z", "peer-a")
  |> expect.to_equal([
    "{\"candidate\":\"c1\"}",
    "{\"candidate\":\"c2\"}",
    "{\"candidate\":\"c3\"}",
  ])
}

@target(javascript)
pub fn candidates_after_a_remote_description_apply_immediately_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(_, _, deliver) = swap(start_scripted(world, "peer-z"))
  deliver(PeerJoined("peer-a"))
  p2p_fake.settle(world)
  deliver(Message("peer-a", Offer("sdp:their-offer")))
  p2p_fake.settle(world)

  deliver(Message("peer-a", Candidate("{\"candidate\":\"late\"}")))
  p2p_fake.settle(world)
  p2p_fake.applied_candidates(world, "peer-z", "peer-a")
  |> expect.to_equal(["{\"candidate\":\"late\"}"])
}

@target(javascript)
pub fn a_candidate_flood_before_a_description_closes_the_peer_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(transport, events, deliver) = swap(start_scripted(world, "peer-z"))
  deliver(PeerJoined("peer-a"))
  p2p_fake.settle(world)

  upto(200)
  |> list.each(fn(index) {
    deliver(Message(
      "peer-a",
      Candidate("{\"candidate\":\"c" <> int.to_string(index) <> "\"}"),
    ))
  })
  p2p_fake.settle(world)

  saw(events, "error PeerConnectionFailed") |> expect.to_be_true()
  saw(events, "ice candidates before describing itself") |> expect.to_be_true()
  p2p_transport_js.known_peers(transport) |> expect.to_equal([])
}

// ─────────────────────────────────────────────────────────────────────────────
// Idempotence
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn duplicate_peer_joined_creates_one_connection_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(transport, events, deliver) = swap(start_scripted(world, "peer-a"))
  deliver(PeerJoined("peer-z"))
  deliver(PeerJoined("peer-z"))
  deliver(PeerJoined("peer-z"))
  p2p_fake.settle(world)

  count(p2p_fake.calls(world), "peer-a open peer-z") |> expect.to_equal(1)
  count(p2p_fake.calls(world), "peer-a open_channel peer-z")
  |> expect.to_equal(1)
  count(entries(events), "status PeerConnecting") |> expect.to_equal(1)
  p2p_transport_js.known_peers(transport) |> expect.to_equal(["peer-z"])
}

@target(javascript)
pub fn our_own_join_echo_is_ignored_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(transport, _, deliver) = swap(start_scripted(world, "peer-a"))
  deliver(PeerJoined("peer-a"))
  p2p_fake.settle(world)
  p2p_transport_js.known_peers(transport) |> expect.to_equal([])
}

@target(javascript)
pub fn a_duplicate_offer_is_answered_once_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(_, _, deliver) = swap(start_scripted(world, "peer-z"))
  deliver(PeerJoined("peer-a"))
  p2p_fake.settle(world)

  deliver(Message("peer-a", Offer("sdp:their-offer")))
  deliver(Message("peer-a", Offer("sdp:their-offer")))
  p2p_fake.settle(world)

  count(p2p_fake.calls(world), "peer-z accept_offer peer-a")
  |> expect.to_equal(1)
  count(p2p_fake.signaling_payloads(world), " answer ") |> expect.to_equal(1)
}

@target(javascript)
pub fn a_duplicate_answer_is_applied_once_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(_, _, deliver) = swap(start_scripted(world, "peer-a"))
  deliver(PeerJoined("peer-z"))
  p2p_fake.settle(world)

  deliver(Message("peer-z", Answer("sdp:their-answer")))
  deliver(Message("peer-z", Answer("sdp:their-answer")))
  p2p_fake.settle(world)

  // The second answer finds a stable connection and is dropped rather than
  // pushed into the browser, which would reject it.
  count(p2p_fake.calls(world), "peer-a accept_answer peer-z")
  |> expect.to_equal(1)
}

@target(javascript)
pub fn an_unsolicited_answer_is_dropped_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(_, _, deliver) = swap(start_scripted(world, "peer-z"))
  deliver(PeerJoined("peer-a"))
  p2p_fake.settle(world)

  deliver(Message("peer-a", Answer("sdp:unsolicited")))
  p2p_fake.settle(world)
  p2p_fake.called(world, "peer-z accept_answer peer-a") |> expect.to_be_false()
}

@target(javascript)
pub fn a_duplicate_candidate_is_queued_once_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(_, _, deliver) = swap(start_scripted(world, "peer-z"))
  deliver(PeerJoined("peer-a"))
  p2p_fake.settle(world)

  deliver(Message("peer-a", Candidate("{\"candidate\":\"c1\"}")))
  deliver(Message("peer-a", Candidate("{\"candidate\":\"c1\"}")))
  deliver(Message("peer-a", Offer("sdp:their-offer")))
  p2p_fake.settle(world)

  p2p_fake.applied_candidates(world, "peer-z", "peer-a")
  |> expect.to_equal(["{\"candidate\":\"c1\"}"])
}

@target(javascript)
pub fn a_duplicate_peer_left_closes_once_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(transport, events, deliver) = swap(start_scripted(world, "peer-a"))
  negotiate_as_offerer(world, deliver, "peer-z")
  p2p_transport_js.open_peers(transport) |> expect.to_equal(["peer-z"])

  deliver(PeerLeft("peer-z"))
  deliver(PeerLeft("peer-z"))
  p2p_fake.settle(world)

  count(entries(events), "close peer-z") |> expect.to_equal(1)
  count(p2p_fake.calls(world), "peer-a close peer-z") |> expect.to_equal(1)
  p2p_transport_js.open_peers(transport) |> expect.to_equal([])
  p2p_transport_js.known_peers(transport) |> expect.to_equal([])
}

@target(javascript)
pub fn close_peer_is_idempotent_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(transport, events, deliver) = swap(start_scripted(world, "peer-a"))
  negotiate_as_offerer(world, deliver, "peer-z")

  p2p_transport_js.close_peer(transport, "peer-z")
  p2p_transport_js.close_peer(transport, "peer-z")
  p2p_transport_js.close_peer(transport, "never-seen")
  p2p_fake.settle(world)

  count(entries(events), "close peer-z") |> expect.to_equal(1)
  count(p2p_fake.calls(world), "peer-a close peer-z") |> expect.to_equal(1)
}

// ─────────────────────────────────────────────────────────────────────────────
// Room limit
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn a_ninth_room_member_is_rejected_with_room_full_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(transport, events, deliver) = swap(start_scripted(world, "peer-a"))

  // Seven remote peers plus this one is a full room of eight.
  upto(7)
  |> list.each(fn(index) {
    deliver(PeerJoined("peer-" <> int.to_string(index)))
  })
  p2p_fake.settle(world)
  p2p_transport_js.known_peers(transport) |> list.length |> expect.to_equal(7)
  saw(events, "error RoomFull") |> expect.to_be_false()

  deliver(PeerJoined("peer-8"))
  p2p_fake.settle(world)

  saw(events, "error RoomFull 8") |> expect.to_be_true()
  p2p_transport_js.known_peers(transport) |> list.length |> expect.to_equal(7)
  // Rejected *before* a connection existed.
  p2p_fake.called(world, "peer-a open peer-8") |> expect.to_be_false()
}

@target(javascript)
pub fn a_full_room_rejects_an_offer_from_a_new_peer_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(transport, events, deliver) = swap(start_scripted(world, "peer-a"))
  upto(7)
  |> list.each(fn(index) {
    deliver(PeerJoined("peer-" <> int.to_string(index)))
  })
  p2p_fake.settle(world)

  deliver(Message("peer-8", Offer("sdp:sneaking-in")))
  p2p_fake.settle(world)

  saw(events, "error RoomFull 8") |> expect.to_be_true()
  p2p_fake.called(world, "peer-a open peer-8") |> expect.to_be_false()
  p2p_transport_js.known_peers(transport) |> list.length |> expect.to_equal(7)
}

@target(javascript)
pub fn a_departure_frees_a_room_slot_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(transport, _, deliver) = swap(start_scripted(world, "peer-a"))
  upto(7)
  |> list.each(fn(index) {
    deliver(PeerJoined("peer-" <> int.to_string(index)))
  })
  deliver(PeerLeft("peer-3"))
  deliver(PeerJoined("peer-8"))
  p2p_fake.settle(world)

  p2p_transport_js.known_peers(transport) |> list.length |> expect.to_equal(7)
  p2p_fake.called(world, "peer-a open peer-8") |> expect.to_be_true()
}

// ─────────────────────────────────────────────────────────────────────────────
// Trust boundary and failures
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn a_non_string_message_closes_the_peer_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(transport, events, deliver) = swap(start_scripted(world, "peer-a"))
  negotiate_as_offerer(world, deliver, "peer-z")

  p2p_fake.deliver_binary(world, "peer-a", "peer-z")
  p2p_fake.settle(world)

  saw(events, "error InvalidEnvelope") |> expect.to_be_true()
  saw(events, "non-string data channel message") |> expect.to_be_true()
  p2p_transport_js.known_peers(transport) |> expect.to_equal([])
  p2p_fake.called(world, "peer-a close peer-z") |> expect.to_be_true()
}

@target(javascript)
pub fn asynchronous_failures_reach_the_typed_error_callback_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(_, events, deliver) = swap(start_scripted(world, "peer-a"))
  deliver(PeerJoined("peer-z"))
  p2p_fake.settle(world)

  p2p_fake.fire_failure(world, "peer-a", "peer-z", "offer", "InvalidStateError")
  p2p_fake.settle(world)

  saw(events, "error PeerConnectionFailed peer-z offer: InvalidStateError")
  |> expect.to_be_true()
  saw(events, "status PeerFailed") |> expect.to_be_true()
}

@target(javascript)
pub fn a_connection_that_cannot_be_constructed_is_dropped_test() -> Nil {
  let world = p2p_fake.new_world()
  p2p_fake.set_open_failure(world, True)
  let #(transport, events, deliver) = swap(start_scripted(world, "peer-a"))

  deliver(PeerJoined("peer-z"))
  p2p_fake.settle(world)

  saw(
    events,
    "error PeerConnectionFailed peer-z open: fake construction failure",
  )
  |> expect.to_be_true()
  p2p_transport_js.known_peers(transport) |> expect.to_equal([])
  // Nothing is attempted on a connection that was never built, and no
  // stale `PeerConnecting` trails the failure.
  p2p_fake.called(world, "peer-a open_channel peer-z") |> expect.to_be_false()
  saw(events, "status PeerConnecting") |> expect.to_be_false()
}

@target(javascript)
pub fn an_offer_from_a_peer_we_cannot_connect_to_is_not_answered_test() -> Nil {
  let world = p2p_fake.new_world()
  p2p_fake.set_open_failure(world, True)
  let #(transport, events, deliver) = swap(start_scripted(world, "peer-z"))

  deliver(Message("peer-a", Offer("sdp:their-offer")))
  p2p_fake.settle(world)

  saw(events, "error PeerConnectionFailed peer-a open") |> expect.to_be_true()
  p2p_fake.called(world, "peer-z accept_offer peer-a") |> expect.to_be_false()
  p2p_transport_js.known_peers(transport) |> expect.to_equal([])
}

@target(javascript)
/// A facade may well close a peer from inside `on_peer_open`. The status
/// stream must still end on the closure, not on the opening it replaced.
pub fn closing_a_peer_from_its_own_open_callback_ends_on_closed_test() -> Nil {
  let world = p2p_fake.new_world()
  let events = transport_js.new_cell([])
  let handle = transport_js.new_cell(None)
  let callbacks =
    Callbacks(
      on_peer_open: fn(peer) {
        push(events, "open " <> peer)
        case transport_js.get_cell(handle) {
          Some(transport) -> p2p_transport_js.close_peer(transport, peer)
          None -> Nil
        }
      },
      on_peer_close: fn(peer) { push(events, "close " <> peer) },
      on_document: fn(peer, data) {
        push(events, "doc " <> peer <> " " <> data)
      },
      on_status: fn(status) { push(events, "status " <> render_status(status)) },
      on_error: fn(error) { push(events, "error " <> render_error(error)) },
    )
  let inbox = transport_js.new_cell(fn(_signal: Signal) { Nil })
  let assert Ok(transport) =
    p2p_transport_js.start_with_rtc(
      room: room,
      peer_id: "peer-a",
      signaling: p2p_fake.scripted_signaling(world, fn(on_signal) {
        transport_js.set_cell(inbox, on_signal)
      }),
      ice_servers: [],
      callbacks: callbacks,
      rtc: p2p_fake.rtc(world, "peer-a"),
    )
  transport_js.set_cell(handle, Some(transport))
  let deliver = fn(signal) { transport_js.get_cell(inbox)(signal) }
  negotiate_as_offerer(world, deliver, "peer-z")

  let statuses =
    entries(events)
    |> list.filter(fn(entry) { string.starts_with(entry, "status Peer") })
  case list.last(statuses) {
    Ok(last) -> last |> expect.to_equal("status PeerCount 0")
    Error(Nil) -> panic as "no peer status was reported"
  }
  p2p_transport_js.open_peers(transport) |> expect.to_equal([])
}

@target(javascript)
pub fn a_terminal_connection_failure_closes_the_peer_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(transport, events, deliver) = swap(start_scripted(world, "peer-a"))
  negotiate_as_offerer(world, deliver, "peer-z")

  p2p_fake.fire_failure(
    world,
    "peer-a",
    "peer-z",
    "connection",
    "peer connection failed",
  )
  p2p_fake.settle(world)

  saw(
    events,
    "error PeerConnectionFailed peer-z connection: peer connection failed",
  )
  |> expect.to_be_true()
  p2p_transport_js.known_peers(transport) |> expect.to_equal([])
  p2p_fake.called(world, "peer-a close peer-z") |> expect.to_be_true()
}

@target(javascript)
pub fn ice_states_are_reported_and_failure_closes_the_peer_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(transport, events, deliver) = swap(start_scripted(world, "peer-a"))
  negotiate_as_offerer(world, deliver, "peer-z")

  p2p_fake.fire_ice(world, "peer-a", "peer-z", "disconnected")
  p2p_fake.settle(world)
  saw(events, "status IceState peer-z disconnected")
  |> expect.to_be_true()
  // `disconnected` recovers on its own, so the peer stays.
  p2p_transport_js.open_peers(transport) |> expect.to_equal(["peer-z"])

  p2p_fake.fire_ice(world, "peer-a", "peer-z", "failed")
  p2p_fake.settle(world)
  saw(events, "error PeerConnectionFailed peer-z ice connection failed")
  |> expect.to_be_true()
  p2p_transport_js.open_peers(transport) |> expect.to_equal([])
  p2p_transport_js.known_peers(transport) |> expect.to_equal([])
}

@target(javascript)
pub fn a_peer_channel_closing_drops_it_from_presence_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(a, _) = start_meshed(world, "peer-a")
  let #(b, events_b) = start_meshed(world, "peer-b")
  p2p_fake.settle(world)

  p2p_transport_js.close_peer(a, "peer-b")
  p2p_fake.settle(world)

  p2p_transport_js.open_peers(b) |> expect.to_equal([])
  saw(events_b, "close peer-a") |> expect.to_be_true()
  saw(events_b, "status PeerCount 0") |> expect.to_be_true()
}

// ─────────────────────────────────────────────────────────────────────────────
// Cleanup
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// A peer that dies while still negotiating is announced as closed all the
/// same. Ending its status stream on `PeerConnecting` would leave a facade
/// rendering a spinner for a peer that no longer exists.
pub fn a_connecting_peer_that_never_opened_still_reports_closed_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(transport, events, deliver) = swap(start_scripted(world, "peer-z"))
  deliver(PeerJoined("peer-a"))
  p2p_fake.settle(world)
  saw(events, "status PeerConnecting peer-a") |> expect.to_be_true()
  p2p_transport_js.open_peers(transport) |> expect.to_equal([])

  deliver(PeerLeft("peer-a"))
  p2p_fake.settle(world)

  count(entries(events), "status PeerClosed peer-a") |> expect.to_equal(1)
  // The callback half stays paired with `on_peer_open`, which never fired.
  saw(events, "close peer-a") |> expect.to_be_false()
  entries(events)
  |> list.filter(fn(entry) { string.starts_with(entry, "status Peer") })
  |> list.last
  |> expect.to_equal(Ok("status PeerCount 0"))
}

@target(javascript)
pub fn close_reports_closed_for_peers_that_never_opened_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(transport, events, deliver) = swap(start_scripted(world, "peer-z"))
  deliver(PeerJoined("peer-a"))
  p2p_fake.settle(world)

  p2p_transport_js.close(transport)
  p2p_fake.settle(world)

  count(entries(events), "status PeerClosed peer-a") |> expect.to_equal(1)
  saw(events, "close peer-a") |> expect.to_be_false()
  count(entries(events), "status SignalingLeft") |> expect.to_equal(1)
}

@target(javascript)
/// Application callbacks are the application's business, including the
/// ones that blow up. Whatever they do, the transport has already closed
/// every connection and left the room by the time the first one runs.
pub fn closing_leaves_signaling_even_when_a_status_callback_throws_test() -> Nil {
  let world = p2p_fake.new_world()
  let events = transport_js.new_cell([])
  let callbacks =
    Callbacks(
      on_peer_open: fn(peer) { push(events, "open " <> peer) },
      on_peer_close: fn(peer) { push(events, "close " <> peer) },
      on_document: fn(peer, data) {
        push(events, "doc " <> peer <> " " <> data)
      },
      on_status: fn(status) {
        push(events, "status " <> render_status(status))
        case status {
          p2p_transport_js.PeerClosed(_) ->
            panic as "the application's status callback blew up"
          p2p_transport_js.SignalingJoined(..)
          | p2p_transport_js.SignalingRoster(_)
          | p2p_transport_js.SignalingLeft
          | p2p_transport_js.PeerConnecting(_)
          | p2p_transport_js.PeerOpen(_)
          | p2p_transport_js.PeerFailed(..)
          | p2p_transport_js.IceState(..)
          | p2p_transport_js.PeerCount(_) -> Nil
        }
      },
      on_error: fn(error) { push(events, "error " <> render_error(error)) },
    )
  let inbox = transport_js.new_cell(fn(_signal: Signal) { Nil })
  let assert Ok(transport) =
    p2p_transport_js.start_with_rtc(
      room: room,
      peer_id: "peer-a",
      signaling: p2p_fake.scripted_signaling(world, fn(on_signal) {
        transport_js.set_cell(inbox, on_signal)
      }),
      ice_servers: [],
      callbacks: callbacks,
      rtc: p2p_fake.rtc(world, "peer-a"),
    )
  let deliver = fn(signal) { transport_js.get_cell(inbox)(signal) }
  negotiate_as_offerer(world, deliver, "peer-z")
  p2p_transport_js.open_peers(transport) |> expect.to_equal(["peer-z"])

  case exception.rescue(fn() { p2p_transport_js.close(transport) }) {
    Ok(_) -> panic as "expected the throwing status callback to propagate"
    Error(_) -> Nil
  }

  // The exception escaped, and the room was still left exactly once.
  count(p2p_fake.calls(world), "signaling.leave peer-a") |> expect.to_equal(1)
  count(p2p_fake.calls(world), "peer-a close peer-z") |> expect.to_equal(1)
  p2p_transport_js.is_closed(transport) |> expect.to_be_true()
  p2p_transport_js.known_peers(transport) |> expect.to_equal([])
  p2p_fake.links(world) |> expect.to_equal([])
}

@target(javascript)
pub fn close_clears_peers_and_leaves_signaling_once_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(a, events_a) = start_meshed(world, "peer-a")
  let #(b, _) = start_meshed(world, "peer-b")
  p2p_fake.settle(world)

  p2p_transport_js.close(a)
  p2p_transport_js.close(a)
  p2p_fake.settle(world)

  count(p2p_fake.calls(world), "signaling.leave peer-a") |> expect.to_equal(1)
  count(entries(events_a), "close peer-b") |> expect.to_equal(1)
  count(entries(events_a), "status SignalingLeft") |> expect.to_equal(1)
  p2p_transport_js.is_closed(a) |> expect.to_be_true()
  p2p_transport_js.known_peers(a) |> expect.to_equal([])
  p2p_transport_js.open_peers(a) |> expect.to_equal([])

  // Both halves of the link are gone: peer-a closed its own, and peer-b
  // closed its own on hearing the channel go.
  p2p_fake.links(world) |> expect.to_equal([])
  p2p_transport_js.open_peers(b) |> expect.to_equal([])
  p2p_fake.members(world) |> expect.to_equal(["peer-b"])
}

@target(javascript)
pub fn a_closed_transport_ignores_later_signals_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(a, events_a, deliver) = swap(start_scripted(world, "peer-a"))
  negotiate_as_offerer(world, deliver, "peer-z")
  p2p_transport_js.close(a)

  deliver(PeerJoined("peer-y"))
  deliver(Message("peer-y", Offer("sdp:late")))
  p2p_fake.settle(world)

  p2p_transport_js.known_peers(a) |> expect.to_equal([])
  p2p_fake.called(world, "peer-a open peer-y") |> expect.to_be_false()
  p2p_transport_js.send(a, "peer-z", "hello") |> expect.to_be_false()
  p2p_transport_js.broadcast(a, "hello") |> expect.to_equal(0)
  count(entries(events_a), "status SignalingLeft") |> expect.to_equal(1)
}

@target(javascript)
pub fn signals_delivered_during_join_are_handled_after_the_session_exists_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(events, callbacks) = recorder()
  let sent = transport_js.new_cell([])

  // An adapter that reports the room's existing members synchronously,
  // before it has returned the session that `send` needs.
  let signaling =
    Signaling(
      join: fn(joined_room, peer_id, on_signal) {
        on_signal(PeerJoined("peer-z"))
        on_signal(PeerJoined("peer-y"))
        Ok(p2p_transport_js.signaling_session(
          room: joined_room,
          peer_id: peer_id,
        ))
      },
      send: fn(_session, to, payload) {
        push(
          sent,
          to
            <> " "
            <> case payload {
            Offer(_) -> "offer"
            Answer(_) -> "answer"
            Candidate(_) -> "candidate"
          },
        )
      },
      leave: fn(_session) { Nil },
    )

  let assert Ok(transport) =
    p2p_transport_js.start_with_rtc(
      room: room,
      peer_id: "peer-a",
      signaling: signaling,
      ice_servers: [],
      callbacks: callbacks,
      rtc: p2p_fake.rtc(world, "peer-a"),
    )
  p2p_fake.settle(world)

  p2p_transport_js.known_peers(transport)
  |> expect.to_equal(["peer-y", "peer-z"])
  // Both offers went out, so neither signal was lost to the missing
  // session, and both arrived in the order the adapter reported them.
  entries(sent)
  |> list.filter(fn(entry) { string.contains(entry, "offer") })
  |> expect.to_equal(["peer-z offer", "peer-y offer"])
  // And the join status came before any peer status.
  case entries(events) {
    [first, ..] ->
      string.contains(first, "SignalingJoined") |> expect.to_be_true()
    [] -> panic as "no status was reported"
  }
}

@target(javascript)
/// The same guarantee on the two paths that report a peer's death before
/// it is gone. Both drop the peer first, so a callback that throws cannot
/// leave a dead connection tracked, addressable by `broadcast`, and
/// holding a room slot.
pub fn a_throwing_callback_cannot_keep_a_terminally_failed_peer_alive_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(transport, deliver) =
    start_with_exploding_callbacks(world, "peer-a", fn(status, _error) {
      case status {
        Some(p2p_transport_js.IceState(_, "failed")) ->
          panic as "the application's status callback blew up"
        Some(p2p_transport_js.IceState(..))
        | Some(p2p_transport_js.SignalingJoined(..))
        | Some(p2p_transport_js.SignalingRoster(_))
        | Some(p2p_transport_js.SignalingLeft)
        | Some(p2p_transport_js.PeerConnecting(_))
        | Some(p2p_transport_js.PeerOpen(_))
        | Some(p2p_transport_js.PeerClosed(_))
        | Some(p2p_transport_js.PeerFailed(..))
        | Some(p2p_transport_js.PeerCount(_))
        | None -> Nil
      }
    })
  negotiate_as_offerer(world, deliver, "peer-z")
  p2p_transport_js.open_peers(transport) |> expect.to_equal(["peer-z"])

  p2p_fake.fire_ice(world, "peer-a", "peer-z", "failed")
  case exception.rescue(fn() { p2p_fake.settle(world) }) {
    Ok(_) -> panic as "expected the throwing status callback to propagate"
    Error(_) -> Nil
  }

  p2p_transport_js.known_peers(transport) |> expect.to_equal([])
  p2p_transport_js.open_peers(transport) |> expect.to_equal([])
  p2p_fake.called(world, "peer-a close peer-z") |> expect.to_be_true()
  p2p_transport_js.broadcast(transport, "hello") |> expect.to_equal(0)
}

@target(javascript)
pub fn a_throwing_callback_cannot_keep_a_foreign_speaking_peer_alive_test() -> Nil {
  let world = p2p_fake.new_world()
  let #(transport, deliver) =
    start_with_exploding_callbacks(world, "peer-a", fn(_status, error) {
      case error {
        Some(p2p.InvalidEnvelope(_, _)) ->
          panic as "the application's error callback blew up"
        Some(p2p.UnsupportedChannel(_))
        | Some(p2p.RootMismatch(..))
        | Some(p2p.ChannelTypeMismatch(..))
        | Some(p2p.DocumentClosed)
        | Some(p2p.CompatibilityMismatch(..))
        | Some(p2p.ProtocolMismatch(..))
        | Some(p2p.RoomMismatch)
        | Some(p2p.RoomFull(_))
        | Some(p2p.SignalingFailed(_))
        | Some(p2p.SequencerUnavailable(_))
        | Some(p2p.SequencerUnsupported)
        | Some(p2p.PeerConnectionFailed(..))
        | Some(p2p.SnapshotTooLarge(..))
        | Some(p2p.ReplicaCollision(_))
        | None -> Nil
      }
    })
  negotiate_as_offerer(world, deliver, "peer-z")

  p2p_fake.deliver_binary(world, "peer-a", "peer-z")
  case exception.rescue(fn() { p2p_fake.settle(world) }) {
    Ok(_) -> panic as "expected the throwing error callback to propagate"
    Error(_) -> Nil
  }

  p2p_transport_js.known_peers(transport) |> expect.to_equal([])
  p2p_fake.called(world, "peer-a close peer-z") |> expect.to_be_true()
}

@target(javascript)
/// A scripted transport whose status and error callbacks run `explode`,
/// which panics for whichever report the test is interested in.
fn start_with_exploding_callbacks(
  world: p2p_fake.World,
  peer_id: String,
  explode: fn(Option(Status), Option(p2p.P2pError)) -> Nil,
) -> #(Transport, fn(Signal) -> Nil) {
  let callbacks =
    Callbacks(
      on_peer_open: fn(_peer) { Nil },
      on_peer_close: fn(_peer) { Nil },
      on_document: fn(_peer, _data) { Nil },
      on_status: fn(status) { explode(Some(status), None) },
      on_error: fn(error) { explode(None, Some(error)) },
    )
  let inbox = transport_js.new_cell(fn(_signal: Signal) { Nil })
  let assert Ok(transport) =
    p2p_transport_js.start_with_rtc(
      room: room,
      peer_id: peer_id,
      signaling: p2p_fake.scripted_signaling(world, fn(on_signal) {
        transport_js.set_cell(inbox, on_signal)
      }),
      ice_servers: [],
      callbacks: callbacks,
      rtc: p2p_fake.rtc(world, peer_id),
    )
  #(transport, fn(signal) { transport_js.get_cell(inbox)(signal) })
}
