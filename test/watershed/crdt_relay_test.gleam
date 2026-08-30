//// Deterministic tests for the `crdt_relay_v1` protocol.
////
//// Nothing here opens a socket. `crdt_relay` is a pure frame codec and a
//// pure room state machine, which is what lets admission, the accepted
//// message types, the order stamping, the attestation arithmetic, the log
//// compaction and every refusal path be pinned down exactly, in one
//// process, with no timing.
////
//// Two claims get most of the attention, because they are the two the
//// whole design turns on: the relay never picks a winner between two
//// states, and it never reads a kernel payload. The first is asserted by
//// keeping both states and refusing the attestation; the second by
//// carrying an envelope whose message body is deliberate nonsense to a
//// merger and finding it relayed and logged byte for byte.
////
//// The service that runs this protocol over `ws` and a disk is tested in
//// `tools/relay/test.mjs`; the two suites are split along that seam.

import gleam/int
import gleam/list
import gleam/string
import startest/expect

import watershed/channel
import watershed/crdt_core
import watershed/crdt_relay.{
  type Action, type Relay, Append, Close, Compact, Send,
}
import watershed/crdt_wire
import watershed/p2p

const room = "trip-planning"

// ─────────────────────────────────────────────────────────────────────────────
// Replicas
// ─────────────────────────────────────────────────────────────────────────────

fn document(replica: String) -> crdt_core.Document {
  let assert Ok(document) =
    crdt_core.new(crdt_core.config(
      room: room,
      compatibility: "relay-test/v1",
      replica: replica,
      session: replica <> "-session",
      root: p2p.kind_init(p2p.pn_counter_root()),
    ))
  document
}

/// Author `times` local increments, and hand back the deltas alongside
/// the document that produced them.
fn clapped(
  document: crdt_core.Document,
  times: Int,
) -> #(crdt_core.Document, List(String)) {
  case times <= 0 {
    True -> #(document, [])
    False -> {
      let assert Ok(#(next, outcome)) =
        crdt_core.edit(
          document,
          crdt_wire.root_address,
          channel.PnCounterEdit(1),
        )
      let encoded =
        list.map(outcome.broadcast, fn(message) {
          crdt_core.encode(next, message)
        })
      let #(final, rest) = clapped(next, times - 1)
      #(final, list.append(encoded, rest))
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Frames
// ─────────────────────────────────────────────────────────────────────────────

fn hello(document: crdt_core.Document) -> String {
  crdt_core.encode(document, crdt_core.hello_message(document))
}

fn state(document: crdt_core.Document) -> String {
  crdt_core.encode(document, crdt_core.state_message(document))
}

fn state_request(document: crdt_core.Document) -> String {
  crdt_core.encode(document, crdt_core.state_request_message())
}

fn digest(document: crdt_core.Document) -> String {
  crdt_core.encode(document, crdt_core.digest_message(document))
}

fn attest(document: crdt_core.Document, up_to: Int) -> String {
  crdt_relay.control_to_string(crdt_relay.Attest(
    digest: crdt_core.digest(document),
    up_to: up_to,
  ))
}

// ─────────────────────────────────────────────────────────────────────────────
// Driving
// ─────────────────────────────────────────────────────────────────────────────

type Run {
  Run(relay: Relay, actions: List(Action))
}

fn open(relay: Relay, connection: Int) -> Run {
  let #(relay, actions) = crdt_relay.connect(relay, connection)
  Run(relay, actions)
}

fn frame(relay: Relay, connection: Int, raw: String) -> Run {
  let #(relay, actions) = crdt_relay.handle_frame(relay, connection, raw)
  Run(relay, actions)
}

fn tag(relay: Relay, connection: Int, raw: String) -> String {
  let #(_relay, _actions, tag) = crdt_relay.serve(relay, connection, raw)
  tag
}

/// Every frame an action list would write, as `connection -> encoded`.
fn writes(actions: List(Action)) -> List(#(Int, String)) {
  list.filter_map(actions, fn(action) {
    case action {
      Send(connection, encoded) ->
        Ok(#(connection, crdt_relay.server_to_string(encoded)))
      Close(..) | Append(..) | Compact(..) -> Error(Nil)
    }
  })
}

fn closes(actions: List(Action)) -> List(#(Int, String)) {
  list.filter_map(actions, fn(action) {
    case action {
      Close(connection, reason) -> Ok(#(connection, reason))
      Send(..) | Append(..) | Compact(..) -> Error(Nil)
    }
  })
}

fn appends(actions: List(Action)) -> List(String) {
  list.filter_map(actions, fn(action) {
    case action {
      Append(_room, line) -> Ok(line)
      Send(..) | Close(..) | Compact(..) -> Error(Nil)
    }
  })
}

fn compactions(actions: List(Action)) -> List(List(String)) {
  list.filter_map(actions, fn(action) {
    case action {
      Compact(_room, lines) -> Ok(lines)
      Send(..) | Close(..) | Append(..) -> Error(Nil)
    }
  })
}

fn relayed(actions: List(Action)) -> List(#(Int, String)) {
  list.filter_map(actions, fn(action) {
    case action {
      Send(connection, crdt_relay.Frame(_order, envelope)) ->
        Ok(#(connection, envelope))
      Send(_, crdt_relay.Connected(..))
      | Send(_, crdt_relay.Synced(_))
      | Send(_, crdt_relay.Attested(..))
      | Send(_, crdt_relay.CheckpointRequest)
      | Send(_, crdt_relay.Refused(..))
      | Close(..)
      | Append(..)
      | Compact(..) -> Error(Nil)
    }
  })
}

fn orders(actions: List(Action)) -> List(Int) {
  list.filter_map(actions, fn(action) {
    case action {
      Send(_connection, crdt_relay.Frame(order, _)) -> Ok(order)
      Send(_connection, crdt_relay.Attested(order, _)) -> Ok(order)
      Send(_connection, crdt_relay.Synced(order)) -> Ok(order)
      Send(_, crdt_relay.Connected(..))
      | Send(_, crdt_relay.CheckpointRequest)
      | Send(_, crdt_relay.Refused(..))
      | Close(..)
      | Append(..)
      | Compact(..) -> Error(Nil)
    }
  })
}

fn attestations(actions: List(Action)) -> List(String) {
  list.filter_map(actions, fn(action) {
    case action {
      Send(_connection, crdt_relay.Attested(_order, digest)) -> Ok(digest)
      Send(_, crdt_relay.Connected(..))
      | Send(_, crdt_relay.Frame(..))
      | Send(_, crdt_relay.Synced(_))
      | Send(_, crdt_relay.CheckpointRequest)
      | Send(_, crdt_relay.Refused(..))
      | Close(..)
      | Append(..)
      | Compact(..) -> Error(Nil)
    }
  })
}

/// A room with one admitted client, ready to send document frames.
fn admitted(connection: Int, document: crdt_core.Document) -> Relay {
  let relay = crdt_relay.new_relay()
  let run = open(relay, connection)
  let run = frame(run.relay, connection, hello(document))
  run.relay
}

// ─────────────────────────────────────────────────────────────────────────────
// The greeting
// ─────────────────────────────────────────────────────────────────────────────

pub fn a_relay_advertises_its_capability_before_a_client_speaks_test() -> Nil {
  let run = open(crdt_relay.new_relay(), 1)
  let assert [#(1, encoded)] = writes(run.actions)
  let assert Ok(frame) = crdt_relay.decode_server(encoded)
  crdt_relay.supports_relay(frame) |> expect.to_be_true()
  string.contains(encoded, "crdt_relay_v1") |> expect.to_be_true()
}

pub fn a_greeting_without_the_capability_is_not_this_lane_test() -> Nil {
  let assert Ok(foreign) =
    crdt_relay.decode_server(
      "{\"type\":\"connected\",\"capabilities\":{\"fluidDds\":true}}",
    )
  foreign |> crdt_relay.supports_relay |> expect.to_be_false()

  let assert Ok(disavowed) =
    crdt_relay.decode_server(
      "{\"type\":\"connected\",\"capabilities\":{\"crdt_relay_v1\":false}}",
    )
  disavowed |> crdt_relay.supports_relay |> expect.to_be_false()
}

pub fn every_server_frame_round_trips_test() -> Nil {
  [
    crdt_relay.connected_frame(),
    crdt_relay.Frame(7, "{\"v\":1}"),
    crdt_relay.Synced(7),
    crdt_relay.Attested(8, "abc"),
    crdt_relay.Refused("malformed", "not a v1 CRDT envelope"),
  ]
  |> list.each(fn(frame) {
    crdt_relay.decode_server(crdt_relay.server_to_string(frame))
    |> expect.to_equal(Ok(frame))
  })
}

pub fn a_relay_that_stamps_nothing_is_still_understood_test() -> Nil {
  let raw = hello(document("alpha"))
  crdt_relay.decode_server(raw) |> expect.to_equal(Ok(crdt_relay.Frame(0, raw)))
}

// ─────────────────────────────────────────────────────────────────────────────
// Admission
// ─────────────────────────────────────────────────────────────────────────────

pub fn the_first_frame_must_be_a_hello_test() -> Nil {
  let alpha = document("alpha")
  let relay = crdt_relay.new_relay()
  let run = frame(relay, 1, state(alpha))

  closes(run.actions) |> expect.to_equal([#(1, "notAdmitted")])
  crdt_relay.clients(run.relay, room) |> expect.to_equal([])
  crdt_relay.log_size(run.relay, room) |> expect.to_equal(0)
}

pub fn a_hello_admits_one_session_test() -> Nil {
  let alpha = document("alpha")
  let relay = admitted(1, alpha)

  crdt_relay.clients(relay, room) |> expect.to_equal([1])
  crdt_relay.sessions(relay, room) |> expect.to_equal(["alpha-session"])
}

pub fn one_session_may_not_attach_twice_test() -> Nil {
  let alpha = document("alpha")
  let relay = admitted(1, alpha)
  let run = frame(relay, 2, hello(alpha))

  closes(run.actions) |> expect.to_equal([#(2, "duplicateSession")])
  crdt_relay.clients(run.relay, room) |> expect.to_equal([1])
}

pub fn a_client_may_not_change_room_sender_or_session_test() -> Nil {
  let alpha = document("alpha")
  let relay = admitted(1, alpha)

  let assert Ok(elsewhere) =
    crdt_core.new(crdt_core.config(
      room: "another-room",
      compatibility: "relay-test/v1",
      replica: "alpha",
      session: "alpha-session",
      root: p2p.kind_init(p2p.pn_counter_root()),
    ))
  let run = frame(relay, 1, state(elsewhere))
  closes(run.actions) |> expect.to_equal([#(1, "identityChanged")])
  crdt_relay.log_size(run.relay, room) |> expect.to_equal(0)
  crdt_relay.log_size(run.relay, "another-room") |> expect.to_equal(0)

  let beta = document("beta")
  let run = frame(relay, 1, state(beta))
  closes(run.actions) |> expect.to_equal([#(1, "identityChanged")])
}

pub fn an_oversize_frame_is_refused_before_it_is_parsed_test() -> Nil {
  let padding = string.repeat("x", crdt_relay.max_frame_bytes() + 1)
  let run = frame(crdt_relay.new_relay(), 1, padding)

  closes(run.actions) |> expect.to_equal([#(1, "frameTooLarge")])
  tag(crdt_relay.new_relay(), 1, padding)
  |> expect.to_equal("rejected:frameTooLarge")
}

pub fn a_malformed_frame_is_refused_test() -> Nil {
  ["", "{", "null", "{\"v\":1}", "{\"type\":\"whatever\"}"]
  |> list.each(fn(raw) {
    let run = frame(crdt_relay.new_relay(), 1, raw)
    list.length(closes(run.actions)) |> expect.to_equal(1)
  })
}

pub fn only_the_documented_message_types_are_carried_test() -> Nil {
  let alpha = document("alpha")
  let relay = admitted(1, alpha)
  let rejection =
    crdt_core.encode(alpha, crdt_core.rejection_message("nope", "not here"))

  let run = frame(relay, 1, rejection)
  closes(run.actions) |> expect.to_equal([#(1, "unsupportedMessage")])
  tag(relay, 1, rejection) |> expect.to_equal("rejected:unsupportedMessage")

  ["hello", "channel", "delta", "stateRequest", "state", "digest"]
  |> list.each(fn(name) {
    crdt_relay.message_kind_to_string(kind_named(name))
    |> expect.to_equal(name)
  })
}

fn kind_named(name: String) -> crdt_relay.MessageKind {
  case name {
    "hello" -> crdt_relay.HelloMessage
    "channel" -> crdt_relay.ChannelMessage
    "delta" -> crdt_relay.DeltaMessage
    "stateRequest" -> crdt_relay.StateRequestMessage
    "state" -> crdt_relay.StateMessage
    _ -> crdt_relay.DigestMessage
  }
}

pub fn a_room_name_outside_the_bound_is_refused_test() -> Nil {
  let assert Ok(huge) =
    crdt_core.new(crdt_core.config(
      room: string.repeat("r", crdt_relay.max_room_bytes + 1),
      compatibility: "relay-test/v1",
      replica: "alpha",
      session: "alpha-session",
      root: p2p.kind_init(p2p.pn_counter_root()),
    ))
  let run = frame(crdt_relay.new_relay(), 1, hello(huge))
  closes(run.actions) |> expect.to_equal([#(1, "invalidRoom")])
}

fn counting(from: Int, to: Int) -> List(Int) {
  case from > to {
    True -> []
    False -> [from, ..counting(from + 1, to)]
  }
}

pub fn a_room_admits_a_bounded_number_of_clients_test() -> Nil {
  let relay =
    counting(1, crdt_relay.max_room_clients)
    |> list.fold(crdt_relay.new_relay(), fn(relay, index) {
      let run =
        frame(relay, index, hello(document("replica" <> int.to_string(index))))
      run.relay
    })
  list.length(crdt_relay.clients(relay, room))
  |> expect.to_equal(crdt_relay.max_room_clients)

  let run = frame(relay, 99, hello(document("one-too-many")))
  closes(run.actions) |> expect.to_equal([#(99, "roomFull")])
}

// ─────────────────────────────────────────────────────────────────────────────
// Fan-out and the log
// ─────────────────────────────────────────────────────────────────────────────

pub fn accepted_traffic_is_broadcast_to_everyone_but_its_sender_test() -> Nil {
  let alpha = document("alpha")
  let beta = document("beta")
  let relay = admitted(1, alpha)
  let run = frame(relay, 2, hello(beta))
  let #(alpha, deltas) = clapped(alpha, 1)
  let assert [delta] = deltas

  let run = frame(run.relay, 1, delta)
  relayed(run.actions) |> expect.to_equal([#(2, delta)])

  let run = frame(run.relay, 1, state(alpha))
  relayed(run.actions) |> expect.to_equal([#(2, state(alpha))])
}

pub fn the_log_is_replayed_in_order_and_terminated_test() -> Nil {
  let alpha = document("alpha")
  let beta = document("beta")
  let relay = admitted(1, alpha)
  let #(_alpha, deltas) = clapped(alpha, 2)
  let assert [first, second] = deltas

  let run = frame(relay, 1, first)
  let run = frame(run.relay, 1, second)
  let run = frame(run.relay, 2, hello(beta))
  let run = frame(run.relay, 2, state_request(beta))

  writes(run.actions)
  |> list.map(fn(entry) { entry.0 })
  |> expect.to_equal([2, 2, 2])
  relayed(run.actions) |> expect.to_equal([#(2, first), #(2, second)])
  let assert [_, _, last] = writes(run.actions)
  string.contains(last.1, "\"type\":\"synced\"") |> expect.to_be_true()
}

pub fn a_state_request_from_an_empty_room_only_ends_the_burst_test() -> Nil {
  let alpha = document("alpha")
  let relay = admitted(1, alpha)
  let run = frame(relay, 1, state_request(alpha))

  relayed(run.actions) |> expect.to_equal([])
  let assert [#(1, only)] = writes(run.actions)
  string.contains(only, "\"type\":\"synced\"") |> expect.to_be_true()
}

pub fn order_is_monotonic_and_stays_outside_the_envelope_test() -> Nil {
  let alpha = document("alpha")
  let beta = document("beta")
  let relay = admitted(1, alpha)
  let run = frame(relay, 2, hello(beta))
  let #(_alpha, deltas) = clapped(alpha, 3)

  let #(relay, seen) =
    list.fold(deltas, #(run.relay, []), fn(carried, delta) {
      let #(relay, seen) = carried
      let run = frame(relay, 1, delta)
      #(run.relay, list.append(seen, orders(run.actions)))
    })
  seen |> expect.to_equal([3, 4, 5])
  crdt_relay.next_order(relay, room) |> expect.to_equal(6)

  // The stamp never enters the envelope: what comes back out is the exact
  // string that went in, and a document decoding it sees no order at all.
  crdt_relay.replayable(relay, room) |> expect.to_equal(deltas)
}

pub fn a_relay_never_decodes_a_kernel_payload_test() -> Nil {
  // A `delta` whose op is meaningless to any kernel. A merger would refuse
  // it; a relay has no opinion, because it never looks.
  let inscrutable =
    "{\"v\":1,\"room\":\""
    <> room
    <> "\",\"from\":\"alpha\",\"session\":\"alpha-session\","
    <> "\"message\":{\"type\":\"delta\",\"id\":[\"alpha\",1],"
    <> "\"address\":\"alpha:1\",\"channelType\":\"nobodysKernel\","
    <> "\"contents\":{\"nonsense\":[1,2,3]}}}"
  let alpha = document("alpha")
  let relay = admitted(1, alpha)
  let beta = document("beta")
  let run = frame(relay, 2, hello(beta))
  let run = frame(run.relay, 1, inscrutable)

  relayed(run.actions) |> expect.to_equal([#(2, inscrutable)])
  crdt_relay.replayable(run.relay, room) |> expect.to_equal([inscrutable])
  list.length(appends(run.actions)) |> expect.to_equal(1)
}

// ─────────────────────────────────────────────────────────────────────────────
// Attestation, checkpoints, and not picking a winner
// ─────────────────────────────────────────────────────────────────────────────

pub fn a_covering_publication_is_attested_and_checkpointed_test() -> Nil {
  let alpha = document("alpha")
  let relay = admitted(1, alpha)
  let #(alpha, _deltas) = clapped(alpha, 2)

  let run = frame(relay, 1, state(alpha))
  list.length(appends(run.actions)) |> expect.to_equal(1)

  let run = frame(run.relay, 1, attest(alpha, 1))
  attestations(run.actions) |> expect.to_equal([crdt_core.digest(alpha)])
  crdt_relay.attested_digest(run.relay, room)
  |> expect.to_equal(crdt_core.digest(alpha))
  crdt_relay.log_size(run.relay, room) |> expect.to_equal(1)

  // The digest line is appended before the compaction that keeps it, so a
  // crash between them leaves a longer log rather than a shorter one.
  list.length(appends(run.actions)) |> expect.to_equal(1)
  let assert [kept] = compactions(run.actions)
  list.length(kept) |> expect.to_equal(2)
}

pub fn two_concurrent_states_are_both_kept_and_neither_wins_test() -> Nil {
  let alpha = document("alpha")
  let beta = document("beta")
  let relay = admitted(1, alpha)
  let run = frame(relay, 2, hello(beta))
  let #(alpha, _) = clapped(alpha, 1)
  let #(beta, _) = clapped(beta, 5)

  let run = frame(run.relay, 1, state(alpha))
  let run = frame(run.relay, 2, state(beta))
  crdt_relay.log_size(run.relay, room) |> expect.to_equal(2)

  // Neither replica can attest: each has published something the other has
  // not been shown to contain, and the relay cannot merge to find out.
  let run = frame(run.relay, 1, attest(alpha, 2))
  attestations(run.actions) |> expect.to_equal([""])
  let run = frame(run.relay, 2, attest(beta, 2))
  attestations(run.actions) |> expect.to_equal([""])
  crdt_relay.log_size(run.relay, room) |> expect.to_equal(2)
  crdt_relay.attested_digest(run.relay, room) |> expect.to_equal("")
  crdt_relay.replayable(run.relay, room)
  |> expect.to_equal([state(alpha), state(beta)])
}

pub fn a_publication_that_covers_what_it_was_sent_collapses_the_log_test() -> Nil {
  let alpha = document("alpha")
  let beta = document("beta")
  let relay = admitted(1, alpha)
  let run = frame(relay, 2, hello(beta))
  let #(alpha, _) = clapped(alpha, 1)
  let #(beta, _) = clapped(beta, 5)

  // alpha publishes at order 3, beta at order 4.
  let run = frame(run.relay, 1, state(alpha))
  let run = frame(run.relay, 2, state(beta))

  // beta then merges alpha's state — it was relayed to it at order 3 — and
  // republishes the join, quoting the order it had processed.
  let assert Ok(#(merged, _outcome)) =
    crdt_core.receive_encoded(beta, state(alpha))
  let run = frame(run.relay, 2, state(merged))
  let run = frame(run.relay, 2, attest(merged, 3))

  attestations(run.actions) |> expect.to_equal([crdt_core.digest(merged)])
  crdt_relay.log_size(run.relay, room) |> expect.to_equal(1)
  crdt_relay.replayable(run.relay, room) |> expect.to_equal([state(merged)])
}

pub fn a_delta_after_a_publication_retires_the_attestation_test() -> Nil {
  let alpha = document("alpha")
  let beta = document("beta")
  let relay = admitted(1, alpha)
  let run = frame(relay, 2, hello(beta))
  let #(alpha, _) = clapped(alpha, 1)

  let run = frame(run.relay, 1, state(alpha))
  let #(_beta, deltas) = clapped(beta, 1)
  let assert [delta] = deltas
  let run = frame(run.relay, 2, delta)

  let run = frame(run.relay, 1, attest(alpha, 3))
  attestations(run.actions) |> expect.to_equal([""])
  crdt_relay.log_size(run.relay, room) |> expect.to_equal(2)
}

pub fn an_attestation_from_a_client_that_published_nothing_is_empty_test() -> Nil {
  let alpha = document("alpha")
  let relay = admitted(1, alpha)
  let run = frame(relay, 1, attest(alpha, 0))

  attestations(run.actions) |> expect.to_equal([""])
  crdt_relay.log_size(run.relay, room) |> expect.to_equal(0)
}

pub fn an_attestation_before_admission_is_refused_test() -> Nil {
  let alpha = document("alpha")
  let run = frame(crdt_relay.new_relay(), 1, attest(alpha, 0))
  closes(run.actions) |> expect.to_equal([#(1, "notAdmitted")])
}

pub fn a_digest_is_broadcast_and_answered_test() -> Nil {
  let alpha = document("alpha")
  let beta = document("beta")
  let relay = admitted(1, alpha)
  let run = frame(relay, 2, hello(beta))
  let #(alpha, _) = clapped(alpha, 1)

  let run = frame(run.relay, 1, digest(alpha))
  relayed(run.actions) |> expect.to_equal([#(2, digest(alpha))])
  // A digest is anti-entropy between replicas, not durable content.
  appends(run.actions) |> expect.to_equal([])
}

// ─────────────────────────────────────────────────────────────────────────────
// Durability
// ─────────────────────────────────────────────────────────────────────────────

pub fn every_record_round_trips_test() -> Nil {
  [
    crdt_relay.StateRecord(3, "alpha-session", "{\"v\":1}"),
    crdt_relay.TrafficRecord(4, "beta-session", "{\"v\":1}"),
    crdt_relay.DigestRecord(5, "abc123", 3),
  ]
  |> list.each(fn(record) {
    crdt_relay.string_to_record(crdt_relay.record_to_string(record))
    |> expect.to_equal(Ok(record))
  })
}

/// A marker written before markers named their entry still reads back,
/// with the entry it names left for `replay` to infer.
pub fn a_marker_without_a_checkpoint_still_reads_test() -> Nil {
  crdt_relay.string_to_record("{\"o\":5,\"k\":\"digest\",\"d\":\"abc123\"}")
  |> expect.to_equal(Ok(crdt_relay.DigestRecord(5, "abc123", 0)))
}

pub fn a_room_replays_from_its_lines_test() -> Nil {
  let alpha = document("alpha")
  let relay = admitted(1, alpha)
  let #(alpha, deltas) = clapped(alpha, 2)

  let #(relay, lines) =
    list.fold(deltas, #(relay, []), fn(carried, delta) {
      let #(relay, lines) = carried
      let run = frame(relay, 1, delta)
      #(run.relay, list.append(lines, appends(run.actions)))
    })
  let run = frame(relay, 1, state(alpha))
  let lines = list.append(lines, appends(run.actions))

  let restarted = crdt_relay.replay(crdt_relay.new_relay(), room, lines)
  crdt_relay.replayable(restarted, room)
  |> expect.to_equal(list.append(deltas, [state(alpha)]))
  crdt_relay.next_order(restarted, room) |> expect.to_equal(5)
  // A restart holds no clients, and nothing was attested, so a returning
  // replica has to earn the checkpoint again.
  crdt_relay.clients(restarted, room) |> expect.to_equal([])
  crdt_relay.attested_digest(restarted, room) |> expect.to_equal("")
}

pub fn a_compacted_log_replays_to_the_checkpoint_test() -> Nil {
  let alpha = document("alpha")
  let relay = admitted(1, alpha)
  let #(alpha, _) = clapped(alpha, 3)

  let run = frame(relay, 1, state(alpha))
  let run = frame(run.relay, 1, attest(alpha, 1))
  let assert [kept] = compactions(run.actions)

  let restarted = crdt_relay.replay(crdt_relay.new_relay(), room, kept)
  crdt_relay.replayable(restarted, room) |> expect.to_equal([state(alpha)])
  crdt_relay.attested_digest(restarted, room)
  |> expect.to_equal(crdt_core.digest(alpha))
  // And the marker names the entry the checkpoint is, so a restart
  // knows which record is canonical.
  crdt_relay.checkpoint_order(restarted, room) |> expect.to_equal(2)
}

/// A replay never rewinds a room's order.
///
/// It can be handed lines whose highest order is *below* one this relay
/// has already stamped and delivered. Reusing that order would make a
/// connection's `delivered` clamp meaningless — the guard that stops an
/// attestation retiring an entry nobody was ever sent — so orders only
/// move forward.
pub fn a_replay_never_rewinds_a_rooms_order_test() -> Nil {
  let alpha = document("alpha")
  let relay = admitted(1, alpha)
  let #(_alpha, deltas) = clapped(alpha, 3)
  let #(relay, lines) =
    list.fold(deltas, #(relay, []), fn(carried, delta) {
      let #(relay, lines) = carried
      let run = frame(relay, 1, delta)
      #(run.relay, list.append(lines, appends(run.actions)))
    })
  crdt_relay.next_order(relay, room) |> expect.to_equal(5)

  // Replaying a shorter history than the room has already stamped.
  let assert [oldest, ..] = lines
  let replayed = crdt_relay.replay(relay, room, [oldest])
  crdt_relay.next_order(replayed, room) |> expect.to_equal(5)

  // And a longer one still moves it on.
  let further =
    crdt_relay.replay(replayed, room, [
      crdt_relay.record_to_string(crdt_relay.TrafficRecord(
        9,
        "alpha-session",
        oldest,
      )),
    ])
  crdt_relay.next_order(further, room) |> expect.to_equal(10)
}

/// Records appended *behind* a checkpoint marker leave the checkpoint
/// alone. The marker is current while it is the newest record in the
/// file, and an older order landing back in the log is not news about
/// the checkpoint.
pub fn a_replay_keeps_a_checkpoint_older_records_are_restored_behind_test() -> Nil {
  let alpha = document("alpha")
  let beta = document("beta")
  let relay = admitted(1, alpha)
  let run = frame(relay, 2, hello(beta))
  let #(_beta, deltas) = clapped(beta, 1)
  let assert [delta] = deltas
  let run = frame(run.relay, 2, delta)
  let #(alpha, _) = clapped(alpha, 1)
  let run = frame(run.relay, 1, state(alpha))
  let run = frame(run.relay, 1, attest(alpha, 4))
  let assert [kept] = compactions(run.actions)

  // The room, and then the room with an older record restored into it.
  let restored =
    crdt_relay.replay(
      crdt_relay.new_relay(),
      room,
      list.append(kept, [
        crdt_relay.record_to_string(crdt_relay.TrafficRecord(
          3,
          "beta-session",
          delta,
        )),
      ]),
    )
  crdt_relay.attested_digest(restored, room)
  |> expect.to_equal(crdt_core.digest(alpha))
  crdt_relay.checkpoint_order(restored, room) |> expect.to_equal(4)
  crdt_relay.replayable(restored, room) |> list.length |> expect.to_equal(2)
  // Orders still only move forward from the highest the file holds.
  crdt_relay.next_order(restored, room) |> expect.to_equal(6)
}

/// Anything logged *after* a checkpoint means the checkpoint has stopped
/// describing the room, and the digest goes with it — while the entry it
/// named is still the room's canonical state.
pub fn a_replay_forgets_a_digest_something_was_logged_after_test() -> Nil {
  let alpha = document("alpha")
  let beta = document("beta")
  let relay = admitted(1, alpha)
  let run = frame(relay, 2, hello(beta))
  let #(alpha, _) = clapped(alpha, 1)
  let run = frame(run.relay, 1, state(alpha))
  let run = frame(run.relay, 1, attest(alpha, 3))
  let assert [kept] = compactions(run.actions)
  let #(_beta, deltas) = clapped(beta, 1)
  let assert [delta] = deltas
  let run = frame(run.relay, 2, delta)
  let lines = list.append(kept, appends(run.actions))

  let restarted = crdt_relay.replay(crdt_relay.new_relay(), room, lines)
  crdt_relay.attested_digest(restarted, room) |> expect.to_equal("")
  crdt_relay.checkpoint_order(restarted, room) |> expect.to_equal(3)
}

/// A log written before markers named their entry still replays, and
/// the room falls back to its newest `state` record as its canonical
/// entry.
pub fn an_older_marker_still_names_a_canonical_entry_test() -> Nil {
  let alpha = document("alpha")
  let restarted =
    crdt_relay.replay(crdt_relay.new_relay(), room, [
      crdt_relay.record_to_string(crdt_relay.TrafficRecord(
        1,
        "alpha-session",
        state(alpha),
      )),
      crdt_relay.record_to_string(crdt_relay.StateRecord(
        2,
        "alpha-session",
        state(alpha),
      )),
      "{\"o\":3,\"k\":\"digest\",\"d\":\"abc123\"}",
    ])
  crdt_relay.attested_digest(restarted, room) |> expect.to_equal("abc123")
  crdt_relay.checkpoint_order(restarted, room) |> expect.to_equal(2)
}

pub fn a_torn_line_costs_only_itself_test() -> Nil {
  let alpha = document("alpha")
  let relay = admitted(1, alpha)
  let #(alpha, _) = clapped(alpha, 1)
  let run = frame(relay, 1, state(alpha))
  let assert [line] = appends(run.actions)

  let torn = string.slice(line, 0, string.length(line) - 4)
  let restarted = crdt_relay.replay(crdt_relay.new_relay(), room, [line, torn])
  crdt_relay.replayable(restarted, room) |> expect.to_equal([state(alpha)])
}

pub fn a_disconnect_leaves_the_log_alone_test() -> Nil {
  let alpha = document("alpha")
  let relay = admitted(1, alpha)
  let #(alpha, _) = clapped(alpha, 1)
  let run = frame(relay, 1, state(alpha))

  let #(relay, actions) = crdt_relay.disconnect(run.relay, 1)
  actions |> expect.to_equal([])
  crdt_relay.clients(relay, room) |> expect.to_equal([])
  crdt_relay.replayable(relay, room) |> expect.to_equal([state(alpha)])
  crdt_relay.room_names(relay) |> expect.to_equal([room])
}

/// An attestation is a claim, and a claim is bounded by what the relay
/// actually sent that connection. A client quoting an order from an
/// order sequence that no longer exists — the shape a client that
/// outlived a relay restart produces — cannot retire an entry it was
/// never shown.
pub fn an_attestation_cannot_claim_more_than_it_was_sent_test() -> Nil {
  let alpha = document("alpha")
  let beta = document("beta")

  // Beta is first, and writes a delta into an otherwise empty room, so
  // it is broadcast to nobody.
  let relay = admitted(2, beta)
  let #(_beta, deltas) = clapped(beta, 1)
  let assert [delta] = deltas
  let run = frame(relay, 2, delta)

  // Alpha connects afterwards and never asks for state, so this
  // connection has been sent nothing at all.
  let run = frame(run.relay, 1, hello(alpha))
  let #(alpha, _) = clapped(alpha, 1)
  let run = frame(run.relay, 1, state(alpha))
  let run = frame(run.relay, 1, attest(alpha, 1_000_000))

  attestations(run.actions) |> expect.to_equal([""])
  crdt_relay.replayable(run.relay, room)
  |> expect.to_equal([delta, state(alpha)])
}

/// The same guarantee across a restart, which is where the stale claim
/// actually comes from: the relay rebuilds its counter from its log, so
/// it hands out orders it has used before, and a client that survived
/// the outage still remembers the old ones.
pub fn a_restarted_relay_does_not_honour_a_stale_high_water_mark_test() -> Nil {
  let alpha = document("alpha")
  let beta = document("beta")
  let relay = admitted(1, alpha)
  let run = frame(relay, 2, hello(beta))
  let #(_beta, deltas) = clapped(beta, 1)
  let assert [delta] = deltas
  let run = frame(run.relay, 2, delta)
  let assert [line] = appends(run.actions)

  // Back from disk: no clients, and a counter that starts below the
  // orders it issued before.
  let restarted = crdt_relay.replay(crdt_relay.new_relay(), room, [line])
  let run = frame(restarted, 7, hello(alpha))
  let #(alpha, _) = clapped(alpha, 1)
  let run = frame(run.relay, 7, state(alpha))
  let run = frame(run.relay, 7, attest(alpha, 99))

  attestations(run.actions) |> expect.to_equal([""])
  crdt_relay.replayable(run.relay, room)
  |> list.any(fn(envelope) { envelope == delta })
  |> expect.to_be_true()
}

// ─────────────────────────────────────────────────────────────────────────────
// Skips: an entry no client can merge
// ─────────────────────────────────────────────────────────────────────────────

fn skip(order: Int) -> String {
  crdt_relay.control_to_string(crdt_relay.Skip(order))
}

/// An envelope the relay accepts and no client can ever merge: a
/// structurally impeccable `delta` — a well-formed message id, an
/// address that names its own creator, a declared channel type — for a
/// kernel that does not exist, carrying an op that means nothing to any
/// kernel that does.
///
/// This is the shape a poisoned log entry has *after* the structural
/// checks, and the relay has no way to know: telling this from a delta
/// for a kernel some other build has would take a merge, which is the
/// one thing a relay never does.
fn poison(from: String) -> String {
  "{\"v\":1,\"room\":\""
  <> room
  <> "\",\"from\":\""
  <> from
  <> "\",\"session\":\""
  <> from
  <> "-session\","
  <> "\"message\":{\"type\":\"delta\",\"id\":[\""
  <> from
  <> "\",1],\"address\":\""
  <> from
  <> ":1\",\"channelType\":\"nobodysKernel\",\"contents\":{\"nonsense\":[1,2,3]}}}"
}

/// A relay admits on the preamble alone, so it can hold an entry no
/// client will ever merge. The client that refuses one says so by order,
/// and its next publication is allowed to land *around* it — which is
/// what stops one poisoned entry freezing the log, the checkpoint, and
/// every replica that has only this relay to sync from. The entry itself
/// is carried into the compaction rather than deleted by it: a client
/// that could not read something never gets to decide it never happened.
pub fn a_skipped_entry_is_carried_past_the_next_checkpoint_test() -> Nil {
  let alpha = document("alpha")
  let beta = document("beta")
  let relay = admitted(1, alpha)
  let run = frame(relay, 2, hello(beta))

  // Beta writes something alpha cannot merge. It is logged and relayed
  // exactly like anything else.
  let poisoned = poison("beta")
  let run = frame(run.relay, 2, poisoned)
  relayed(run.actions) |> expect.to_equal([#(1, poisoned)])
  crdt_relay.log_size(run.relay, room) |> expect.to_equal(1)

  // Alpha refuses it by order, publishes its own state, and attests.
  let run = frame(run.relay, 1, skip(3))
  crdt_relay.skipped_orders(run.relay, 1) |> expect.to_equal([3])
  let #(alpha, _) = clapped(alpha, 1)
  let run = frame(run.relay, 1, state(alpha))
  let run = frame(run.relay, 1, attest(alpha, 3))

  // The checkpoint is honoured — and the entry alpha could not read is
  // still there, in order, on the wire and on disk.
  attestations(run.actions) |> expect.to_equal([crdt_core.digest(alpha)])
  crdt_relay.log_size(run.relay, room) |> expect.to_equal(2)
  crdt_relay.replayable(run.relay, room)
  |> expect.to_equal([poisoned, state(alpha)])
  let assert [lines] = compactions(run.actions)
  list.length(lines) |> expect.to_equal(3)
  list.any(lines, fn(line) { string.contains(line, "nonsense") })
  |> expect.to_be_true()
  // The claim is still live, because the entry it names still is.
  crdt_relay.skipped_orders(run.relay, 1) |> expect.to_equal([3])

  // And it stays live across the next checkpoint from the same client,
  // rather than being quietly covered by a wider `upTo`.
  let #(alpha, _) = clapped(alpha, 1)
  let run = frame(run.relay, 1, state(alpha))
  let run = frame(run.relay, 1, attest(alpha, 1_000_000))
  attestations(run.actions) |> expect.to_equal([crdt_core.digest(alpha)])
  crdt_relay.replayable(run.relay, room)
  |> expect.to_equal([poisoned, state(alpha)])
}

/// A skip is not a delete, and it is not a vote. An entry every other
/// replica can merge survives a client that says it cannot — the log
/// keeps carrying it, and the client that *can* read it still gets it.
/// This is the malicious case: a client that skips perfectly valid
/// operations must not be able to erase them from the room's history.
pub fn a_skip_cannot_delete_an_entry_anyone_else_can_merge_test() -> Nil {
  let alpha = document("alpha")
  let beta = document("beta")
  let gamma = document("gamma")
  let relay = admitted(1, alpha)
  let run = frame(relay, 2, hello(beta))

  // Beta writes a perfectly ordinary delta.
  let #(_beta, deltas) = clapped(beta, 1)
  let assert [delta] = deltas
  let run = frame(run.relay, 2, delta)

  // Alpha claims it could not process it, publishes a state that does
  // not contain it, and attests.
  let run = frame(run.relay, 1, skip(3))
  let #(alpha, _) = clapped(alpha, 1)
  let run = frame(run.relay, 1, state(alpha))
  let run = frame(run.relay, 1, attest(alpha, 3))
  attestations(run.actions) |> expect.to_equal([crdt_core.digest(alpha)])

  // Beta's delta is still in the log, still on disk, and still replayed
  // to a client that arrives afterwards.
  crdt_relay.replayable(run.relay, room)
  |> expect.to_equal([delta, state(alpha)])
  let assert [lines] = compactions(run.actions)
  crdt_relay.replay(crdt_relay.new_relay(), room, lines)
  |> crdt_relay.replayable(room)
  |> expect.to_equal([delta, state(alpha)])

  let run = frame(run.relay, 3, hello(gamma))
  let run = frame(run.relay, 3, state_request(gamma))
  relayed(run.actions)
  |> expect.to_equal([#(3, delta), #(3, state(alpha))])
}

/// The same rule for the most valuable entry in the log: a client that
/// skips the *previous checkpoint* cannot make it disappear. Everything
/// the room ever agreed on lives in that record, and one connection's
/// claim about its own reading is not a reason to unlink it.
pub fn a_skip_cannot_delete_an_earlier_checkpoint_test() -> Nil {
  let alpha = document("alpha")
  let beta = document("beta")

  // Alpha checkpoints an ordinary room: one state, attested.
  let relay = admitted(1, alpha)
  let #(alpha, _) = clapped(alpha, 2)
  let run = frame(relay, 1, state(alpha))
  let run = frame(run.relay, 1, attest(alpha, 1))
  attestations(run.actions) |> expect.to_equal([crdt_core.digest(alpha)])
  crdt_relay.replayable(run.relay, room) |> expect.to_equal([state(alpha)])

  // Beta arrives, is replayed that checkpoint, and claims it could not
  // read it. Its own publication is honoured; the checkpoint stays.
  let run = frame(run.relay, 2, hello(beta))
  let run = frame(run.relay, 2, state_request(beta))
  relayed(run.actions) |> expect.to_equal([#(2, state(alpha))])
  let run = frame(run.relay, 2, skip(2))
  crdt_relay.skipped_orders(run.relay, 2) |> expect.to_equal([2])
  let #(beta, _) = clapped(beta, 1)
  let run = frame(run.relay, 2, state(beta))
  let run = frame(run.relay, 2, attest(beta, 1_000_000))

  attestations(run.actions) |> expect.to_equal([crdt_core.digest(beta)])
  crdt_relay.replayable(run.relay, room)
  |> expect.to_equal([state(alpha), state(beta)])
  crdt_relay.log_size(run.relay, room) |> expect.to_equal(2)
}

/// Two connections, two different sets of refusals. Each client's
/// checkpoint carries what *it* could not read, and retires what it
/// merged — including something the other connection had skipped, whose
/// content is now inside the checkpoint that replaced it.
pub fn concurrent_clients_keep_their_own_skips_test() -> Nil {
  let alpha = document("alpha")
  let beta = document("beta")
  let gamma = document("gamma")
  let relay = admitted(1, alpha)
  let run = frame(relay, 2, hello(beta))
  let run = frame(run.relay, 3, hello(gamma))

  // Gamma writes two entries: one nobody but alpha refuses, and one
  // ordinary delta that only beta refuses.
  let poisoned = poison("gamma")
  let run = frame(run.relay, 3, poisoned)
  let #(_gamma, deltas) = clapped(gamma, 1)
  let assert [delta] = deltas
  let run = frame(run.relay, 3, delta)

  let run = frame(run.relay, 1, skip(4))
  let run = frame(run.relay, 2, skip(5))
  crdt_relay.skipped_orders(run.relay, 1) |> expect.to_equal([4])
  crdt_relay.skipped_orders(run.relay, 2) |> expect.to_equal([5])

  // Alpha merged the delta and refused the poison, so its checkpoint
  // covers the one and carries the other.
  let #(alpha, _) = clapped(alpha, 1)
  let run = frame(run.relay, 1, state(alpha))
  let run = frame(run.relay, 1, attest(alpha, 5))
  attestations(run.actions) |> expect.to_equal([crdt_core.digest(alpha)])
  crdt_relay.replayable(run.relay, room)
  |> expect.to_equal([poisoned, state(alpha)])
  // Beta's claim named an entry that is gone — merged into the
  // checkpoint, not dropped — so it is pruned rather than remembered.
  crdt_relay.skipped_orders(run.relay, 1) |> expect.to_equal([4])
  let run = frame(run.relay, 2, skip(4))
  crdt_relay.skipped_orders(run.relay, 2) |> expect.to_equal([4])
}

/// The healing path. A client that can read the carried entry merges it,
/// publishes a state that contains it, and attests with no skip of its
/// own — and only then does the log finally collapse to one line.
pub fn a_client_that_merges_a_carried_entry_retires_it_test() -> Nil {
  let alpha = document("alpha")
  let beta = document("beta")
  let relay = admitted(1, alpha)
  let run = frame(relay, 2, hello(beta))
  let #(_beta, deltas) = clapped(beta, 1)
  let assert [delta] = deltas
  let run = frame(run.relay, 2, delta)

  // Alpha refuses it and checkpoints around it.
  let run = frame(run.relay, 1, skip(3))
  let #(alpha, _) = clapped(alpha, 1)
  let run = frame(run.relay, 1, state(alpha))
  let run = frame(run.relay, 1, attest(alpha, 3))
  crdt_relay.log_size(run.relay, room) |> expect.to_equal(2)

  // Beta reads everything, publishes the join, and reports no skip.
  let run = frame(run.relay, 2, state_request(beta))
  let #(beta, _) = clapped(beta, 1)
  let run = frame(run.relay, 2, state(beta))
  let run = frame(run.relay, 2, attest(beta, 1_000_000))

  attestations(run.actions) |> expect.to_equal([crdt_core.digest(beta)])
  crdt_relay.log_size(run.relay, room) |> expect.to_equal(1)
  crdt_relay.replayable(run.relay, room) |> expect.to_equal([state(beta)])
  crdt_relay.skipped_orders(run.relay, 2) |> expect.to_equal([])
}

/// A compaction is the room's whole file, so what it carries has to come
/// back. A restart from those lines holds the carried entry *and* the
/// checkpoint, in order, and replays both.
pub fn a_compacted_log_replays_what_it_carried_test() -> Nil {
  let alpha = document("alpha")
  let beta = document("beta")
  let relay = admitted(1, alpha)
  let run = frame(relay, 2, hello(beta))
  let poisoned = poison("beta")
  let run = frame(run.relay, 2, poisoned)
  let run = frame(run.relay, 1, skip(3))
  let #(alpha, _) = clapped(alpha, 1)
  let run = frame(run.relay, 1, state(alpha))
  let run = frame(run.relay, 1, attest(alpha, 3))
  let assert [lines] = compactions(run.actions)

  let restarted = crdt_relay.replay(crdt_relay.new_relay(), room, lines)
  crdt_relay.replayable(restarted, room)
  |> expect.to_equal([poisoned, state(alpha)])
  crdt_relay.attested_digest(restarted, room)
  |> expect.to_equal(crdt_core.digest(alpha))
  // Diagnostic orders stay monotonic for whatever is written next.
  crdt_relay.next_order(restarted, room)
  |> expect.to_equal(crdt_relay.next_order(run.relay, room))
}

/// Repeating a skip is the same claim twice. It cannot compound, and it
/// cannot make a second entry survive a checkpoint that covers it.
pub fn a_repeated_skip_is_one_claim_test() -> Nil {
  let alpha = document("alpha")
  let beta = document("beta")
  let relay = admitted(1, alpha)
  let run = frame(relay, 2, hello(beta))
  let #(_beta, deltas) = clapped(beta, 2)
  let assert [first, second] = deltas
  let run = frame(run.relay, 2, first)
  let run = frame(run.relay, 2, second)

  let run = frame(run.relay, 1, skip(3))
  let run = frame(run.relay, 1, skip(3))
  let run = frame(run.relay, 1, skip(3))
  crdt_relay.skipped_orders(run.relay, 1) |> expect.to_equal([3])

  let #(alpha, _) = clapped(alpha, 1)
  let run = frame(run.relay, 1, state(alpha))
  let run = frame(run.relay, 1, attest(alpha, 4))
  attestations(run.actions) |> expect.to_equal([crdt_core.digest(alpha)])
  crdt_relay.replayable(run.relay, room)
  |> expect.to_equal([first, state(alpha)])
}

/// The poisoned entry is above everything the client processed, which is
/// the case a high-water mark alone cannot answer: nothing arrives after
/// it to carry the mark past it, so without the skip the room would never
/// checkpoint again.
pub fn a_skip_covers_an_entry_no_later_frame_follows_test() -> Nil {
  let alpha = document("alpha")
  let beta = document("beta")
  let relay = admitted(1, alpha)
  let run = frame(relay, 2, hello(beta))
  let #(alpha, _) = clapped(alpha, 1)
  let run = frame(run.relay, 1, state(alpha))
  let poisoned = poison("beta")
  let run = frame(run.relay, 2, poisoned)

  // Without the skip, the publication cannot cover the entry that landed
  // after it.
  let held = frame(run.relay, 1, state(alpha))
  let held = frame(held.relay, 1, attest(alpha, 2))
  attestations(held.actions) |> expect.to_equal([""])

  let run = frame(run.relay, 1, skip(4))
  let run = frame(run.relay, 1, state(alpha))
  let run = frame(run.relay, 1, attest(alpha, 2))
  attestations(run.actions) |> expect.to_equal([crdt_core.digest(alpha)])
  // The checkpoint lands, and the entry it could not read is carried
  // beside it — in log order, whichever order the two were stamped in.
  crdt_relay.replayable(run.relay, room)
  |> expect.to_equal([poisoned, state(alpha)])
}

/// A skip is a claim about delivery, and it is checked. An order this
/// connection was never sent is ignored: honouring it would let a client
/// retire an entry it has no evidence of, which is the same rule the
/// attestation clamp keeps.
pub fn a_skip_for_something_never_delivered_is_ignored_test() -> Nil {
  let alpha = document("alpha")
  let beta = document("beta")

  // Beta writes a delta into an empty room, so it reaches nobody.
  let relay = admitted(2, beta)
  let #(_beta, deltas) = clapped(beta, 1)
  let assert [delta] = deltas
  let run = frame(relay, 2, delta)

  // Alpha connects afterwards, never asks for state, and claims a skip
  // for the order it was never shown.
  let run = frame(run.relay, 1, hello(alpha))
  let run = frame(run.relay, 1, skip(1))
  closes(run.actions) |> expect.to_equal([])
  crdt_relay.skipped_orders(run.relay, 1) |> expect.to_equal([])

  let #(alpha, _) = clapped(alpha, 1)
  let run = frame(run.relay, 1, state(alpha))
  let run = frame(run.relay, 1, attest(alpha, 1_000_000))

  attestations(run.actions) |> expect.to_equal([""])
  crdt_relay.replayable(run.relay, room)
  |> expect.to_equal([delta, state(alpha)])
}

/// One client's refusal is not a verdict on the entry. It keeps being
/// replayed to everyone else, right up until a checkpoint compacts it.
pub fn a_skip_does_not_stop_the_entry_reaching_another_client_test() -> Nil {
  let alpha = document("alpha")
  let beta = document("beta")
  let gamma = document("gamma")
  let relay = admitted(1, alpha)
  let run = frame(relay, 2, hello(beta))
  let #(_beta, deltas) = clapped(beta, 1)
  let assert [delta] = deltas
  let run = frame(run.relay, 2, delta)
  let run = frame(run.relay, 1, skip(3))
  crdt_relay.skipped_orders(run.relay, 1) |> expect.to_equal([3])

  let run = frame(run.relay, 3, hello(gamma))
  let run = frame(run.relay, 3, state_request(gamma))
  relayed(run.actions) |> expect.to_equal([#(3, delta)])
}

/// And one client's skip is not another's. Only the connection that
/// reported it may cover the entry.
pub fn a_skip_belongs_to_the_connection_that_reported_it_test() -> Nil {
  let alpha = document("alpha")
  let beta = document("beta")
  let relay = admitted(1, alpha)
  let run = frame(relay, 2, hello(beta))
  let poisoned = poison("gamma")
  let run = frame(run.relay, 3, hello(document("gamma")))
  let run = frame(run.relay, 3, poisoned)
  let run = frame(run.relay, 1, skip(4))

  // Beta was sent the same entry and refused nothing, so its own
  // publication does not cover it.
  let #(beta, _) = clapped(beta, 1)
  let run = frame(run.relay, 2, state(beta))
  let run = frame(run.relay, 2, attest(beta, 3))
  attestations(run.actions) |> expect.to_equal([""])
  crdt_relay.log_size(run.relay, room) |> expect.to_equal(2)
}

pub fn a_skip_before_admission_is_refused_test() -> Nil {
  let run = frame(crdt_relay.new_relay(), 1, skip(1))
  closes(run.actions) |> expect.to_equal([#(1, "notAdmitted")])
}

pub fn a_skip_is_tagged_by_whether_it_was_honoured_test() -> Nil {
  let alpha = document("alpha")
  let beta = document("beta")
  let relay = admitted(1, alpha)
  let run = frame(relay, 2, hello(beta))
  let #(_beta, deltas) = clapped(beta, 1)
  let assert [delta] = deltas
  let run = frame(run.relay, 2, delta)

  tag(run.relay, 1, skip(3)) |> expect.to_equal("skip")
  tag(run.relay, 1, skip(99)) |> expect.to_equal("skip:undelivered")
}

pub fn a_skip_round_trips_as_a_control_frame_test() -> Nil {
  crdt_relay.decode_client(skip(12))
  |> expect.to_equal(Ok(crdt_relay.Control(crdt_relay.Skip(12))))
  // And it is not an envelope: nothing about it reaches a document.
  skip(12) |> string.contains("\"room\"") |> expect.to_be_false()
}

// ─────────────────────────────────────────────────────────────────────────────
// The hard log bound, and the checkpoint pressure in front of it
// ─────────────────────────────────────────────────────────────────────────────

/// A delta that passes every check a relay can make without merging — a
/// well-formed message id, an address that names its own creator, a
/// declared channel type — and that no kernel in any build can read.
fn poison_at(from: String, index: Int) -> String {
  "{\"v\":1,\"room\":\""
  <> room
  <> "\",\"from\":\""
  <> from
  <> "\",\"session\":\""
  <> from
  <> "-session\","
  <> "\"message\":{\"type\":\"delta\",\"id\":[\""
  <> from
  <> "\","
  <> int.to_string(index)
  <> "],\"address\":\""
  <> from
  <> ":"
  <> int.to_string(index)
  <> "\",\"channelType\":\"nobodysKernel\",\"contents\":{\"nonsense\":[1,2,3]}}}"
}

/// A `state` envelope a relay accepts and no document will ever merge:
/// its channel list is a list, which is all a relay checks, and the
/// channel type in it belongs to no kernel, so every replica refuses it.
fn poison_state_at(from: String, index: Int) -> String {
  "{\"v\":1,\"room\":\""
  <> room
  <> "\",\"from\":\""
  <> from
  <> "\",\"session\":\""
  <> from
  <> "-session\","
  <> "\"message\":{\"type\":\"state\",\"channels\":[{\"descriptor\":{"
  <> "\"address\":\""
  <> from
  <> ":"
  <> int.to_string(index)
  <> "\",\"channelType\":\"nobodysKernel\",\"createdBy\":\""
  <> from
  <> "\"},\"snapshot\":{\"nonsense\":[1,2,3]}}]}}"
}

/// The bounds are chosen against each other. A client attaching to a
/// completely full room refuses every record in it, so the room bound —
/// `max_room_records` — must not be able to outrun the per-connection
/// skip bound; and a room asks for a checkpoint before it would have to
/// refuse one.
pub fn the_skip_bound_is_above_anything_an_attachment_can_hold_test() -> Nil {
  { crdt_relay.max_room_records <= crdt_relay.max_client_skips }
  |> expect.to_be_true()
  { crdt_relay.checkpoint_pressure_records < crdt_relay.max_room_records }
  |> expect.to_be_true()
}

/// A room's live log stops growing at `max_room_records`, and the frame
/// that would have crossed it is refused by name and its sender closed.
///
/// Without this bound one admitted session is unbounded disk and
/// unbounded heap: an admitted client alone in a room writes records
/// nobody is there to refuse.
pub fn a_room_stops_appending_at_its_hard_bound_test() -> Nil {
  let mallory = document("mallory")
  let relay = admitted(1, mallory)
  let run =
    flooded(crdt_relay.max_room_records, 1, "mallory", 2, Run(relay, []))

  crdt_relay.log_size(run.relay, room)
  |> expect.to_equal(crdt_relay.max_room_records)
  closes(run.actions) |> expect.to_equal([])

  // One more, and it is refused rather than appended.
  let order = 2 + crdt_relay.max_room_records
  let over = frame(run.relay, 1, poison_at("mallory", order))
  appends(over.actions) |> expect.to_equal([])
  compactions(over.actions) |> expect.to_equal([])
  closes(over.actions) |> expect.to_equal([#(1, "roomAtCapacity")])
  tag(run.relay, 1, poison_at("mallory", order))
  |> expect.to_equal("rejected:roomAtCapacity")

  // And the room is exactly what it was: a refusal preserves every
  // durable record it already holds.
  crdt_relay.log_size(over.relay, room)
  |> expect.to_equal(crdt_relay.max_room_records)
  crdt_relay.replayable(over.relay, room)
  |> expect.to_equal(crdt_relay.replayable(run.relay, room))
}

/// A `state` is no exemption on its own. At the bound it is admitted
/// only from a connection that declared `supports`, so a flood of
/// unmergeable `state` frames from a client that never did is refused
/// exactly like a flood of deltas.
pub fn a_state_at_the_bound_needs_a_support_declaration_test() -> Nil {
  let mallory = document("mallory")
  let relay = admitted(1, mallory)
  let run =
    flooded(crdt_relay.max_room_records, 1, "mallory", 2, Run(relay, []))

  let over = frame(run.relay, 1, poison_state_at("mallory", 9000))
  appends(over.actions) |> expect.to_equal([])
  closes(over.actions) |> expect.to_equal([#(1, "roomAtCapacity")])
  crdt_relay.log_size(over.relay, room)
  |> expect.to_equal(crdt_relay.max_room_records)
}

/// A full room still admits clients, still replays to them, and still
/// takes their skips — the whole path an honest client uses to
/// checkpoint one — and refusing an entire full room's worth of records
/// is exactly the most `max_client_skips` must allow without closing
/// the connection.
pub fn a_full_room_still_admits_and_replays_test() -> Nil {
  let mallory = document("mallory")
  let relay = admitted(1, mallory)
  let run =
    flooded(crdt_relay.max_room_records, 1, "mallory", 2, Run(relay, []))

  let honest = document("honest")
  let joined = frame(run.relay, 2, hello(honest))
  closes(joined.actions) |> expect.to_equal([])
  let replayed = frame(joined.relay, 2, state_request(honest))
  closes(replayed.actions) |> expect.to_equal([])
  list.length(relayed(replayed.actions))
  |> expect.to_equal(crdt_relay.max_room_records)

  // It refuses everything it was replayed and holds every claim.
  let drained =
    refuse_everything(crdt_relay.max_room_records, 2, replayed.relay)
  crdt_relay.skipped_orders(drained, 2)
  |> list.length
  |> expect.to_equal(crdt_relay.max_room_records)
  crdt_relay.carried_orders(drained, room)
  |> list.length
  |> expect.to_equal(crdt_relay.max_room_records)
  crdt_relay.log_size(drained, room)
  |> expect.to_equal(crdt_relay.max_room_records)
}

/// A room under pressure asks, and it asks only the clients that said
/// they would understand the question.
pub fn a_pressured_room_asks_compatible_clients_to_checkpoint_test() -> Nil {
  let alpha = document("alpha")
  let beta = document("beta")
  let relay = admitted(1, alpha)
  let run = frame(relay, 2, hello(beta))
  // Connection 1 speaks the request; connection 2 was built before it
  // existed and never says so.
  let run = frame(run.relay, 1, supports())
  crdt_relay.supports_checkpoints(run.relay, 1) |> expect.to_be_true()
  crdt_relay.supports_checkpoints(run.relay, 2) |> expect.to_be_false()

  // Below the mark: nothing is asked of anybody.
  let run =
    flooded(crdt_relay.checkpoint_pressure_records - 1, 2, "beta", 3, run)
  requests(run.actions) |> expect.to_equal([])
  crdt_relay.checkpoint_requests(run.relay, room) |> expect.to_equal(0)

  // Crossing it asks exactly the compatible client, exactly once.
  let crossing =
    flooded(1, 2, "beta", crdt_relay.checkpoint_pressure_records + 2, run)
  requests(crossing.actions) |> expect.to_equal([1])
  crdt_relay.checkpoints_pending(crossing.relay, room) |> expect.to_equal([1])

  // The next records ask nothing more: one outstanding request per
  // connection, and no new round until the log has grown an interval.
  let quiet =
    flooded(
      crdt_relay.checkpoint_request_interval,
      2,
      "beta",
      crdt_relay.checkpoint_pressure_records + 3,
      crossing,
    )
  requests(quiet.actions) |> expect.to_equal([])
  crdt_relay.checkpoint_requests(quiet.relay, room) |> expect.to_equal(1)
}

/// A supports-declaring client may always publish, even in a room that
/// has reached its hard bound: a `state` is the one frame that can
/// compact a full room, and refusing it would strand exactly the honest
/// client the checkpoint machinery exists to protect.
pub fn a_supports_declaring_client_may_always_publish_test() -> Nil {
  let alpha = document("alpha")
  let mallory = document("mallory")
  let relay = admitted(1, alpha)
  let run = frame(relay, 1, supports())
  let run = frame(run.relay, 2, hello(mallory))
  let run = flooded(crdt_relay.max_room_records, 2, "mallory", 3, run)
  crdt_relay.checkpoints_pending(run.relay, room) |> expect.to_equal([1])

  // The flooding connection is refused at the bound.
  let refused = frame(run.relay, 2, poison_at("mallory", 9000))
  closes(refused.actions) |> expect.to_equal([#(2, "roomAtCapacity")])

  // The supports-declaring client's publication is not.
  let #(alpha, _) = clapped(alpha, 1)
  let published = frame(run.relay, 1, state(alpha))
  closes(published.actions) |> expect.to_equal([])
  list.length(appends(published.actions)) |> expect.to_equal(1)
  crdt_relay.checkpoints_pending(published.relay, room) |> expect.to_equal([])

  // And the attestation that follows collapses the room back under the
  // mark it was asked at, with the checkpoint named and the pressure
  // spent.
  let attested =
    frame(published.relay, 1, attest(alpha, crdt_relay.max_room_records + 3))
  attestations(attested.actions) |> expect.to_equal([crdt_core.digest(alpha)])
  crdt_relay.log_size(attested.relay, room) |> expect.to_equal(1)
  { crdt_relay.checkpoint_order(attested.relay, room) > 0 }
  |> expect.to_be_true()
  // Spent, so the next pressure round is armed by growth from here: the
  // room asks a second time, once, when the log crosses the mark again.
  crdt_relay.checkpoint_requests(attested.relay, room) |> expect.to_equal(1)
  let regrown =
    flooded(
      crdt_relay.checkpoint_pressure_records,
      2,
      "mallory",
      9000,
      attested,
    )
  crdt_relay.checkpoint_requests(regrown.relay, room) |> expect.to_equal(2)
  crdt_relay.checkpoints_pending(regrown.relay, room) |> expect.to_equal([1])
}

/// A checkpoint request carries no order, no digest and no envelope. A
/// client answers out of its own state, so there is no path from a
/// relay's diagnostic sequence into a document through it.
pub fn a_checkpoint_request_carries_no_order_test() -> Nil {
  let encoded = crdt_relay.server_to_string(crdt_relay.CheckpointRequest)
  encoded |> string.contains("\"order\"") |> expect.to_be_false()
  encoded |> string.contains("\"envelope\"") |> expect.to_be_false()
  encoded |> string.contains("\"digest\"") |> expect.to_be_false()
  encoded |> string.contains("\"checkpointRequest\"") |> expect.to_be_true()
  // And the client half of the codec reads back exactly what was sent.
  crdt_relay.decode_server(encoded)
  |> expect.to_equal(Ok(crdt_relay.CheckpointRequest))
}

/// A `supports` frame is a statement about a client, so it needs a
/// client: before the `hello` that admits one it is `notAdmitted`, like
/// every other frame that is not that hello.
pub fn a_support_declaration_needs_an_admitted_connection_test() -> Nil {
  let relay = crdt_relay.new_relay()
  let run = open(relay, 1)
  let refused = frame(run.relay, 1, supports())
  closes(refused.actions) |> expect.to_equal([#(1, "notAdmitted")])

  // Once admitted it changes nothing durable, and repeating it changes
  // nothing at all.
  let alpha = document("alpha")
  let admitted = admitted(1, alpha)
  let once = frame(admitted, 1, supports())
  appends(once.actions) |> expect.to_equal([])
  writes(once.actions) |> expect.to_equal([])
  tag(admitted, 1, supports()) |> expect.to_equal("supports")
  let twice = frame(once.relay, 1, supports())
  crdt_relay.supports_checkpoints(twice.relay, 1) |> expect.to_be_true()
  crdt_relay.next_order(twice.relay, room)
  |> expect.to_equal(crdt_relay.next_order(admitted, room))
}

/// `count` durable traffic records, orders `1..count`, as a relay would
/// have written them to disk: the log a fresh process reads back when it
/// restarts onto a room that was already at its hard bound.
fn traffic_lines(count: Int) -> List(String) {
  counting(1, count)
  |> list.map(fn(order) {
    crdt_relay.record_to_string(crdt_relay.TrafficRecord(
      order,
      "resident-session",
      poison_at("resident", order),
    ))
  })
}

/// The capacity-recovery gate. A room recovered at its hard bound — read
/// back off a disk after a restart, or simply full before this client
/// arrived — can never grow, so no append will ever ask for a
/// checkpoint. What drains it is the ordinary attach flow: the client
/// declares support, is replayed the room, publishes its merged state —
/// admitted at the bound *because* it declared support — and attests,
/// which compacts the room back under the bound.
pub fn a_supports_declaring_client_drains_a_recovered_full_room_test() -> Nil {
  let restarted =
    crdt_relay.replay(
      crdt_relay.new_relay(),
      room,
      traffic_lines(crdt_relay.max_room_records),
    )
  crdt_relay.log_size(restarted, room)
  |> expect.to_equal(crdt_relay.max_room_records)

  // The honest client attaches and declares support. Nothing is asked —
  // a full room cannot grow to ask — and nothing needs to be.
  let honest = document("honest")
  let joined = frame(restarted, 2, hello(honest))
  closes(joined.actions) |> expect.to_equal([])
  let declared = frame(joined.relay, 2, supports())
  closes(declared.actions) |> expect.to_equal([])
  appends(declared.actions) |> expect.to_equal([])

  // It is replayed the whole room, then publishes the state that drains
  // it. At the bound that publication is admitted because — and only
  // because — this connection declared support.
  let replayed = frame(declared.relay, 2, state_request(honest))
  closes(replayed.actions) |> expect.to_equal([])
  list.length(relayed(replayed.actions))
  |> expect.to_equal(crdt_relay.max_room_records)
  let #(honest, _) = clapped(honest, 1)
  let published = frame(replayed.relay, 2, state(honest))
  closes(published.actions) |> expect.to_equal([])
  list.length(appends(published.actions)) |> expect.to_equal(1)

  // The attestation that follows collapses the room back under the
  // bound: the honest client merged the whole room and refused nothing,
  // so its checkpoint subsumes every record.
  let attested =
    frame(published.relay, 2, attest(honest, crdt_relay.max_room_records + 3))
  attestations(attested.actions) |> expect.to_equal([crdt_core.digest(honest)])
  crdt_relay.log_size(attested.relay, room) |> expect.to_equal(1)
  { crdt_relay.checkpoint_order(attested.relay, room) > 0 }
  |> expect.to_be_true()

  // And editing continues on the same connection, no reconnect: the room
  // has capacity again, so an ordinary delta is stamped and appended
  // rather than refused.
  let editing =
    frame(
      attested.relay,
      2,
      poison_at("honest", crdt_relay.max_room_records + 5),
    )
  closes(editing.actions) |> expect.to_equal([])
  list.length(appends(editing.actions)) |> expect.to_equal(1)
}

/// The bound stays hard against a client that publishes and never
/// attests. The publication itself is admitted — it is the one frame
/// that can compact the room — but it earns nothing else: the room is
/// still at its bound, so the same client's next ordinary append is
/// refused and its sender closed, exactly like any other over-bound
/// frame.
pub fn a_publication_without_an_attestation_earns_no_capacity_test() -> Nil {
  let restarted =
    crdt_relay.replay(
      crdt_relay.new_relay(),
      room,
      traffic_lines(crdt_relay.max_room_records),
    )
  let honest = document("honest")
  let joined = frame(restarted, 2, hello(honest))
  let declared = frame(joined.relay, 2, supports())
  let replayed = frame(declared.relay, 2, state_request(honest))
  let #(honest, _) = clapped(honest, 1)
  let published = frame(replayed.relay, 2, state(honest))
  closes(published.actions) |> expect.to_equal([])
  crdt_relay.log_size(published.relay, room)
  |> expect.to_equal(crdt_relay.max_room_records + 1)

  // No attestation, so the room is still over its bound: an ordinary
  // delta from the same connection is refused, and the sender closed.
  let refused =
    frame(
      published.relay,
      2,
      poison_at("honest", crdt_relay.max_room_records + 5),
    )
  appends(refused.actions) |> expect.to_equal([])
  closes(refused.actions) |> expect.to_equal([#(2, "roomAtCapacity")])
  crdt_relay.log_size(refused.relay, room)
  |> expect.to_equal(crdt_relay.max_room_records + 1)
}

/// One connection refusing every order it was replayed, oldest first.
fn refuse_everything(count: Int, connection: Int, relay: Relay) -> Relay {
  case count <= 0 {
    True -> relay
    False -> {
      let run = frame(relay, connection, skip(count + 1))
      refuse_everything(count - 1, connection, run.relay)
    }
  }
}

fn supports() -> String {
  crdt_relay.control_to_string(crdt_relay.Supports(checkpoint_requests: True))
}

/// The connection of every checkpoint request an action list holds.
fn requests(actions: List(Action)) -> List(Int) {
  list.filter_map(actions, fn(action) {
    case action {
      Send(connection, crdt_relay.CheckpointRequest) -> Ok(connection)
      Send(_, crdt_relay.Connected(..))
      | Send(_, crdt_relay.Frame(..))
      | Send(_, crdt_relay.Synced(_))
      | Send(_, crdt_relay.Attested(..))
      | Send(_, crdt_relay.Refused(..))
      | Close(..)
      | Append(..)
      | Compact(..) -> Error(Nil)
    }
  })
}

/// `count` unmergeable deltas from one connection, refused by nobody.
fn flooded(
  count: Int,
  connection: Int,
  from: String,
  first_index: Int,
  run: Run,
) -> Run {
  case count <= 0 {
    True -> run
    False -> {
      let run = frame(run.relay, connection, poison_at(from, first_index))
      flooded(count - 1, connection, from, first_index + 1, run)
    }
  }
}
