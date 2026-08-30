//// Deterministic tests for the relay client.
////
//// No socket and no clock: `relay_fake.driver` runs the real
//// `crdt_relay` protocol over a queue, and `relay_fake.scheduler` is a
//// logical millisecond counter a test steps by hand. So the reconnect
//// sequence, the cap, the reset, and every generation guard are
//// assertions about a list rather than waits.
////
//// The client's job is narrow — one socket, the capability handshake,
//// opaque strings in both directions, and bounded reconnection — and
//// that is exactly what is pinned here. What a document does with the
//// strings is `crdt_relay_lifecycle_test`.

@target(javascript)
import gleam/int
@target(javascript)
import gleam/json
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{None, Some}
@target(javascript)
import gleam/string
@target(javascript)
import startest/expect

@target(javascript)
import watershed/crdt_core
@target(javascript)
import watershed/crdt_relay
@target(javascript)
import watershed/crdt_sequencer_js.{
  type Relay, RelayClosed, RelayNotReady, SendFailed,
}
@target(javascript)
import watershed/p2p
@target(javascript)
import watershed/relay_fake.{type Clock, type Hub}
@target(javascript)
import watershed/transport_js.{type Cell}

@target(javascript)
const room = "trip-planning"

// ─────────────────────────────────────────────────────────────────────────────
// A recording client
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
type Client {
  Client(relay: Relay, events: Cell(List(String)), connects: Cell(Int))
}

@target(javascript)
fn spawn(hub: Hub, clock: Clock) -> Client {
  let events = transport_js.new_cell([])
  let connects = transport_js.new_cell(0)
  let relay =
    crdt_sequencer_js.start(
      url: "ws://relay.test/",
      driver: relay_fake.driver(hub),
      scheduler: relay_fake.scheduler(clock),
      events: crdt_sequencer_js.Events(
        on_connecting: fn() {
          transport_js.set_cell(connects, transport_js.get_cell(connects) + 1)
        },
        on_ready: fn() { note(events, "ready") },
        on_envelope: fn(raw) {
          note(events, "envelope " <> summarize(raw))
          True
        },
        on_synced: fn() { note(events, "synced") },
        on_attested: fn(digest) { note(events, "attested " <> short(digest)) },
        on_checkpoint_requested: fn() { note(events, "checkpointRequested") },
        on_unsupported: fn(_detail) { note(events, "unsupported") },
        on_dropped: fn(_detail) { note(events, "dropped") },
        on_retry: fn(delay) { note(events, "retry " <> int.to_string(delay)) },
        on_error: fn(error) { note(events, "error " <> error_tag(error)) },
      ),
    )
  crdt_sequencer_js.connect(relay)
  relay_fake.settle(hub)
  Client(relay: relay, events: events, connects: connects)
}

@target(javascript)
fn note(cell: Cell(List(String)), entry: String) -> Nil {
  transport_js.set_cell(cell, [entry, ..transport_js.get_cell(cell)])
}

@target(javascript)
fn events(client: Client) -> List(String) {
  list.reverse(transport_js.get_cell(client.events))
}

@target(javascript)
/// An envelope, named by the one thing a test cares about: its message
/// type. The client is not allowed to know more than that either.
fn summarize(raw: String) -> String {
  case crdt_relay.decode_client(raw) {
    Ok(crdt_relay.Document(_, _, from, _, message)) ->
      crdt_relay.message_kind_to_string(message) <> " from " <> from
    Ok(crdt_relay.Control(_)) | Error(_) -> "opaque"
  }
}

@target(javascript)
fn short(digest: String) -> String {
  string.slice(digest, 0, 8)
}

@target(javascript)
fn error_tag(error: p2p.P2pError) -> String {
  case error {
    p2p.SequencerUnavailable(_) -> "sequencerUnavailable"
    p2p.SequencerUnsupported -> "sequencerUnsupported"
    p2p.InvalidEnvelope(_, _) -> "invalidEnvelope"
    p2p.UnsupportedChannel(_)
    | p2p.RootMismatch(..)
    | p2p.ChannelTypeMismatch(..)
    | p2p.DocumentClosed
    | p2p.CompatibilityMismatch(..)
    | p2p.ProtocolMismatch(..)
    | p2p.RoomMismatch
    | p2p.RoomFull(_)
    | p2p.SignalingFailed(_)
    | p2p.PeerConnectionFailed(..)
    | p2p.SnapshotTooLarge(..)
    | p2p.ReplicaCollision(_) -> "other"
  }
}

@target(javascript)
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

// ─────────────────────────────────────────────────────────────────────────────
// The handshake
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn a_compatible_relay_is_ready_after_its_greeting_test() -> Nil {
  let hub = relay_fake.new_hub()
  let client = spawn(hub, relay_fake.new_clock())

  events(client) |> expect.to_equal(["ready"])
  crdt_sequencer_js.is_ready(client.relay) |> expect.to_be_true()
  crdt_sequencer_js.is_retrying(client.relay) |> expect.to_be_false()
}

@target(javascript)
pub fn a_sequencer_without_the_lane_is_unsupported_and_final_test() -> Nil {
  let hub = relay_fake.new_hub()
  relay_fake.set_capability(hub, False)
  let clock = relay_fake.new_clock()
  let client = spawn(hub, clock)
  relay_fake.settle(hub)

  events(client) |> expect.to_equal(["unsupported", "dropped"])
  crdt_sequencer_js.is_ready(client.relay) |> expect.to_be_false()
  // Terminal: asking the same endpoint again would get the same answer.
  crdt_sequencer_js.is_retrying(client.relay) |> expect.to_be_false()
  relay_fake.advance(clock, 60_000)
  relay_fake.settle(hub)
  relay_fake.opens(hub) |> expect.to_equal(1)
}

@target(javascript)
pub fn a_malformed_greeting_drops_the_socket_test() -> Nil {
  let hub = relay_fake.new_hub()
  relay_fake.set_greeting(hub, Some("{\"type\":"))
  let client = spawn(hub, relay_fake.new_clock())
  relay_fake.settle(hub)

  events(client)
  |> expect.to_equal(["error invalidEnvelope", "dropped", "retry 250"])
}

@target(javascript)
pub fn traffic_before_the_greeting_is_a_handshake_violation_test() -> Nil {
  let hub = relay_fake.new_hub()
  relay_fake.set_greeting(
    hub,
    Some(crdt_relay.server_to_string(crdt_relay.Frame(1, "{\"v\":1}"))),
  )
  let client = spawn(hub, relay_fake.new_clock())
  relay_fake.settle(hub)

  events(client)
  |> expect.to_equal(["error invalidEnvelope", "dropped", "retry 250"])
}

@target(javascript)
pub fn an_oversize_frame_is_refused_before_it_is_parsed_test() -> Nil {
  let hub = relay_fake.new_hub()
  let client = spawn(hub, relay_fake.new_clock())
  let assert [connection] = relay_fake.open_sockets(hub)

  relay_fake.inject(
    hub,
    connection,
    string.repeat("x", crdt_relay.max_frame_bytes() + 1),
  )
  relay_fake.settle(hub)

  events(client)
  |> expect.to_equal(["ready", "error invalidEnvelope", "dropped", "retry 250"])
}

@target(javascript)
pub fn a_refusal_from_the_relay_is_reported_and_ends_the_socket_test() -> Nil {
  let hub = relay_fake.new_hub()
  let client = spawn(hub, relay_fake.new_clock())
  let assert [connection] = relay_fake.open_sockets(hub)

  relay_fake.inject(
    hub,
    connection,
    crdt_relay.server_to_string(crdt_relay.Refused("roomFull", "32 clients")),
  )
  relay_fake.settle(hub)

  events(client)
  |> expect.to_equal([
    "ready", "error sequencerUnavailable", "dropped", "retry 250",
  ])
}

// ─────────────────────────────────────────────────────────────────────────────
// Carrying strings
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn envelopes_are_carried_unchanged_in_both_directions_test() -> Nil {
  let hub = relay_fake.new_hub()
  let alpha = document("alpha")
  let beta = document("beta")
  let one = spawn(hub, relay_fake.new_clock())
  let two = spawn(hub, relay_fake.new_clock())

  crdt_sequencer_js.send_envelope(
    one.relay,
    crdt_core.encode(alpha, crdt_core.hello_message(alpha)),
  )
  |> expect.to_be_ok()
  crdt_sequencer_js.send_envelope(
    two.relay,
    crdt_core.encode(beta, crdt_core.hello_message(beta)),
  )
  |> expect.to_be_ok()
  relay_fake.settle(hub)

  // The second client's hello reaches the first, byte for byte.
  let hello_beta = crdt_core.encode(beta, crdt_core.hello_message(beta))
  relay_fake.outbound(hub)
  |> list.filter(fn(raw) { string.contains(raw, "\"type\":\"frame\"") })
  |> list.any(fn(raw) { string.contains(raw, escape(hello_beta)) })
  |> expect.to_be_true()

  events(one) |> expect.to_equal(["ready", "envelope hello from beta"])
}

@target(javascript)
fn escape(raw: String) -> String {
  // The envelope travels as a JSON string field, so what appears in the
  // frame is its escaped form.
  let encoded = json.to_string(json.string(raw))
  string.slice(encoded, 1, string.length(encoded) - 2)
}

@target(javascript)
pub fn a_state_request_is_answered_and_terminated_test() -> Nil {
  let hub = relay_fake.new_hub()
  let alpha = document("alpha")
  let client = spawn(hub, relay_fake.new_clock())

  let _ =
    crdt_sequencer_js.send_envelope(
      client.relay,
      crdt_core.encode(alpha, crdt_core.hello_message(alpha)),
    )
  let _ =
    crdt_sequencer_js.send_envelope(
      client.relay,
      crdt_core.encode(alpha, crdt_core.state_request_message()),
    )
  relay_fake.settle(hub)

  events(client) |> expect.to_equal(["ready", "synced"])
}

@target(javascript)
pub fn an_attestation_quotes_the_order_actually_processed_test() -> Nil {
  let hub = relay_fake.new_hub()
  let alpha = document("alpha")
  let client = spawn(hub, relay_fake.new_clock())

  let _ =
    crdt_sequencer_js.send_envelope(
      client.relay,
      crdt_core.encode(alpha, crdt_core.hello_message(alpha)),
    )
  let _ =
    crdt_sequencer_js.send_envelope(
      client.relay,
      crdt_core.encode(alpha, crdt_core.state_message(alpha)),
    )
  relay_fake.settle(hub)
  // The relay stamped hello 1 and state 2, and answered nothing, so
  // nothing has been processed yet.
  crdt_sequencer_js.last_order(client.relay) |> expect.to_equal(0)

  let _ = crdt_sequencer_js.attest(client.relay, crdt_core.digest(alpha))
  relay_fake.settle(hub)

  events(client)
  |> expect.to_equal([
    "ready",
    "attested " <> short(crdt_core.digest(alpha)),
  ])
  crdt_sequencer_js.last_order(client.relay) |> expect.to_equal(3)
  relay_fake.log_size(hub, room) |> expect.to_equal(1)
  relay_fake.attested(hub, room)
  |> expect.to_equal(crdt_core.digest(alpha))
}

@target(javascript)
/// A client that would never see the greeting keeps refusing every write:
/// before the handshake, and after `close`. The `SendError` names why in
/// each case, and neither is a queue.
pub fn nothing_is_written_before_the_handshake_or_after_a_close_test() -> Nil {
  let hub = relay_fake.new_hub()
  relay_fake.set_capability(hub, False)
  let alpha = document("alpha")
  let client = spawn(hub, relay_fake.new_clock())

  crdt_sequencer_js.send_envelope(
    client.relay,
    crdt_core.encode(alpha, crdt_core.hello_message(alpha)),
  )
  |> expect.to_equal(Error(RelayNotReady))
  crdt_sequencer_js.attest(client.relay, "abc")
  |> expect.to_equal(Error(RelayNotReady))

  let hub = relay_fake.new_hub()
  let client = spawn(hub, relay_fake.new_clock())
  crdt_sequencer_js.close(client.relay)
  relay_fake.settle(hub)
  crdt_sequencer_js.send_envelope(client.relay, "{}")
  |> expect.to_equal(Error(RelayClosed))
  relay_fake.inbound(hub) |> expect.to_equal([])
}

// ─────────────────────────────────────────────────────────────────────────────
// Reconnection
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn a_drop_retries_with_the_documented_backoff_and_cap_test() -> Nil {
  let hub = relay_fake.new_hub()
  let clock = relay_fake.new_clock()
  let client = spawn(hub, clock)

  relay_fake.stop(hub)
  relay_fake.settle(hub)

  // Five more attempts, each refused the moment it is made.
  list.each([250, 500, 1000, 2000, 5000], fn(delay) {
    relay_fake.advance(clock, delay)
    relay_fake.settle(hub)
  })

  relay_fake.delays(clock)
  |> expect.to_equal([250, 500, 1000, 2000, 5000, 5000])
  crdt_sequencer_js.attempts(client.relay) |> expect.to_equal(6)
  relay_fake.opens(hub) |> expect.to_equal(6)
  // One attempt reported per attempt made, the first one included.
  transport_js.get_cell(client.connects) |> expect.to_equal(6)

  events(client)
  |> list.filter(fn(entry) { string.starts_with(entry, "retry") })
  |> expect.to_equal([
    "retry 250", "retry 500", "retry 1000", "retry 2000", "retry 5000",
    "retry 5000",
  ])
}

@target(javascript)
pub fn a_healthy_session_resets_the_backoff_test() -> Nil {
  let hub = relay_fake.new_hub()
  let clock = relay_fake.new_clock()
  let client = spawn(hub, clock)

  relay_fake.stop(hub)
  relay_fake.settle(hub)
  relay_fake.advance(clock, 250)
  relay_fake.settle(hub)
  relay_fake.advance(clock, 500)
  relay_fake.settle(hub)
  crdt_sequencer_js.attempts(client.relay) |> expect.to_equal(3)

  relay_fake.resume(hub)
  relay_fake.advance(clock, 1000)
  relay_fake.settle(hub)
  crdt_sequencer_js.is_ready(client.relay) |> expect.to_be_true()
  crdt_sequencer_js.healthy(client.relay)
  crdt_sequencer_js.attempts(client.relay) |> expect.to_equal(0)

  relay_fake.stop(hub)
  relay_fake.settle(hub)
  // The sequence starts again rather than continuing where it left off.
  relay_fake.delays(clock)
  |> expect.to_equal([250, 500, 1000, 250])
}

@target(javascript)
pub fn a_socket_the_environment_refuses_is_a_failed_attempt_test() -> Nil {
  let hub = relay_fake.new_hub()
  relay_fake.stop(hub)
  let clock = relay_fake.new_clock()
  let client = spawn(hub, clock)
  relay_fake.settle(hub)

  events(client)
  |> expect.to_equal(["error sequencerUnavailable", "dropped", "retry 250"])
  crdt_sequencer_js.is_retrying(client.relay) |> expect.to_be_true()
}

@target(javascript)
pub fn a_closed_relay_stops_retrying_test() -> Nil {
  let hub = relay_fake.new_hub()
  let clock = relay_fake.new_clock()
  let client = spawn(hub, clock)

  relay_fake.stop(hub)
  relay_fake.settle(hub)
  crdt_sequencer_js.is_retrying(client.relay) |> expect.to_be_true()

  crdt_sequencer_js.close(client.relay)
  relay_fake.resume(hub)
  relay_fake.advance(clock, 60_000)
  relay_fake.settle(hub)

  relay_fake.opens(hub) |> expect.to_equal(1)
  crdt_sequencer_js.is_closed(client.relay) |> expect.to_be_true()
  crdt_sequencer_js.is_ready(client.relay) |> expect.to_be_false()
}

// ─────────────────────────────────────────────────────────────────────────────
// Generations
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn a_retired_socket_reports_nothing_test() -> Nil {
  let hub = relay_fake.new_hub()
  let clock = relay_fake.new_clock()
  let client = spawn(hub, clock)
  let assert [first] = relay_fake.open_sockets(hub)

  relay_fake.stop(hub)
  relay_fake.settle(hub)
  relay_fake.resume(hub)
  relay_fake.advance(clock, 250)
  relay_fake.settle(hub)
  crdt_sequencer_js.is_ready(client.relay) |> expect.to_be_true()

  let before = events(client)
  // The dead socket speaks: a frame, a refusal, and a close, all from a
  // generation that has been replaced.
  relay_fake.inject(
    hub,
    first,
    crdt_relay.server_to_string(crdt_relay.Frame(9, "{}")),
  )
  relay_fake.inject(
    hub,
    first,
    crdt_relay.server_to_string(crdt_relay.Refused("gone", "stale")),
  )
  relay_fake.settle(hub)

  events(client) |> expect.to_equal(before)
  crdt_sequencer_js.is_ready(client.relay) |> expect.to_be_true()
}

@target(javascript)
pub fn a_reconnect_timer_that_fires_late_does_nothing_test() -> Nil {
  let hub = relay_fake.new_hub()
  let clock = relay_fake.new_clock()
  let client = spawn(hub, clock)

  relay_fake.stop(hub)
  relay_fake.settle(hub)
  crdt_sequencer_js.is_retrying(client.relay) |> expect.to_be_true()

  // Closed while a reconnect was armed. The timer still fires.
  crdt_sequencer_js.close(client.relay)
  relay_fake.resume(hub)
  relay_fake.advance(clock, 5000)
  relay_fake.settle(hub)

  relay_fake.opens(hub) |> expect.to_equal(1)
  relay_fake.open_sockets(hub) |> expect.to_equal([])
}

@target(javascript)
/// The order high-water mark belongs to one socket. A relay that
/// restarts rebuilds its counter from its log and hands out orders it
/// has used before, so a number carried across a reconnect would be
/// meaningless — and loudly so, because a relay retires log entries at
/// or below the one an attestation quotes.
pub fn the_order_high_water_mark_resets_with_every_socket_test() -> Nil {
  let hub = relay_fake.new_hub()
  let clock = relay_fake.new_clock()
  let alpha = document("alpha")
  let client = spawn(hub, clock)

  let _ =
    crdt_sequencer_js.send_envelope(
      client.relay,
      crdt_core.encode(alpha, crdt_core.hello_message(alpha)),
    )
  let _ =
    crdt_sequencer_js.send_envelope(
      client.relay,
      crdt_core.encode(alpha, crdt_core.state_request_message()),
    )
  relay_fake.settle(hub)
  { crdt_sequencer_js.last_order(client.relay) > 0 } |> expect.to_be_true()

  relay_fake.stop(hub)
  relay_fake.settle(hub)
  crdt_sequencer_js.last_order(client.relay) |> expect.to_equal(0)

  relay_fake.resume(hub)
  relay_fake.advance(clock, 250)
  relay_fake.settle(hub)
  crdt_sequencer_js.is_ready(client.relay) |> expect.to_be_true()
  crdt_sequencer_js.last_order(client.relay) |> expect.to_equal(0)
}

@target(javascript)
/// An envelope the owner refuses is reported to the relay as a `skip`
/// naming its exact order, and only then does the high-water mark move
/// past it. A client that stopped counting instead could never attest
/// again, which would freeze the log, the checkpoint, and every
/// `SequencedOnly` replica in the room behind one entry nobody can
/// merge.
pub fn a_refused_envelope_is_skipped_by_order_test() -> Nil {
  let hub = relay_fake.new_hub()
  let events = transport_js.new_cell([])
  let refuse = transport_js.new_cell([])
  let relay = refusing_client(hub, refuse, events)
  let alpha = document("alpha")
  let payload = crdt_core.encode(alpha, crdt_core.hello_message(alpha))

  // Admitted, so the relay knows what it has delivered to this socket.
  let _ = crdt_sequencer_js.send_envelope(relay, payload)
  let _ =
    crdt_sequencer_js.send_envelope(
      relay,
      crdt_core.encode(alpha, crdt_core.state_request_message()),
    )
  relay_fake.settle(hub)
  let assert [connection] = relay_fake.open_sockets(hub)

  let beta = document("beta")
  let carried = crdt_core.encode(beta, crdt_core.hello_message(beta))
  relay_fake.inject(
    hub,
    connection,
    crdt_relay.server_to_string(crdt_relay.Frame(2, carried)),
  )
  relay_fake.settle(hub)
  crdt_sequencer_js.last_order(relay) |> expect.to_equal(2)

  transport_js.set_cell(refuse, ["now"])
  relay_fake.inject(
    hub,
    connection,
    crdt_relay.server_to_string(crdt_relay.Frame(3, carried)),
  )
  relay_fake.settle(hub)

  // Reported by order, and the mark moved past it — so a later
  // attestation covers the entry rather than being wedged behind it.
  relay_fake.inbound(hub)
  |> list.any(fn(raw) {
    raw == crdt_relay.control_to_string(crdt_relay.Skip(3))
  })
  |> expect.to_be_true()
  crdt_sequencer_js.skipped_orders(relay) |> expect.to_equal([3])
  crdt_sequencer_js.last_order(relay) |> expect.to_equal(3)

  // And the next one is processed normally: a skip is one entry's
  // problem, not the socket's.
  transport_js.set_cell(refuse, [])
  relay_fake.inject(
    hub,
    connection,
    crdt_relay.server_to_string(crdt_relay.Frame(4, carried)),
  )
  relay_fake.settle(hub)
  crdt_sequencer_js.last_order(relay) |> expect.to_equal(4)
  list.reverse(transport_js.get_cell(events))
  |> expect.to_equal(["ready", "synced"])
}

@target(javascript)
/// A refusal that cannot be reported freezes the mark instead. A relay
/// that stamps no order has given the client nothing to name, and a mark
/// that moved anyway would be telling that relay it may retire an entry
/// nobody merged and nobody mentioned.
pub fn an_unreportable_refusal_freezes_the_high_water_mark_test() -> Nil {
  let hub = relay_fake.new_hub()
  let events = transport_js.new_cell([])
  let refuse = transport_js.new_cell([])
  let relay = refusing_client(hub, refuse, events)
  let assert [connection] = relay_fake.open_sockets(hub)
  let alpha = document("alpha")
  let payload = crdt_core.encode(alpha, crdt_core.hello_message(alpha))

  relay_fake.inject(
    hub,
    connection,
    crdt_relay.server_to_string(crdt_relay.Frame(5, payload)),
  )
  relay_fake.settle(hub)
  crdt_sequencer_js.last_order(relay) |> expect.to_equal(5)

  // A bare envelope with no order at all, refused: nothing to skip.
  transport_js.set_cell(refuse, ["now"])
  relay_fake.inject(hub, connection, payload)
  relay_fake.settle(hub)
  crdt_sequencer_js.last_order(relay) |> expect.to_equal(5)
  crdt_sequencer_js.skipped_orders(relay) |> expect.to_equal([])

  // And it stays frozen, even for something that would have been fine.
  transport_js.set_cell(refuse, [])
  relay_fake.inject(
    hub,
    connection,
    crdt_relay.server_to_string(crdt_relay.Frame(7, payload)),
  )
  relay_fake.settle(hub)
  crdt_sequencer_js.last_order(relay) |> expect.to_equal(5)
}

@target(javascript)
/// A refusal whose skip cannot be *written* is a socket that is gone, not
/// a mark to freeze and carry on with. It is retired here, so the lane
/// falls back and retries instead of sitting on a connection that can
/// never attest again.
pub fn a_refusal_that_cannot_be_written_retires_the_socket_test() -> Nil {
  let hub = relay_fake.new_hub()
  let events = transport_js.new_cell([])
  let refuse = transport_js.new_cell([])
  let relay = refusing_client(hub, refuse, events)
  let assert [connection] = relay_fake.open_sockets(hub)
  let alpha = document("alpha")
  let payload = crdt_core.encode(alpha, crdt_core.hello_message(alpha))

  // The socket has left OPEN with no close delivered, and the next thing
  // it carries is something this document refuses.
  relay_fake.set_writable(hub, False)
  transport_js.set_cell(refuse, ["now"])
  relay_fake.inject(
    hub,
    connection,
    crdt_relay.server_to_string(crdt_relay.Frame(3, payload)),
  )
  relay_fake.settle(hub)

  crdt_sequencer_js.skipped_orders(relay) |> expect.to_equal([])
  crdt_sequencer_js.is_ready(relay) |> expect.to_be_false()
  relay_fake.open_sockets(hub) |> expect.to_equal([])
  list.reverse(transport_js.get_cell(events))
  |> list.contains("dropped")
  |> expect.to_be_true()
}

@target(javascript)
/// The diagnostic list of refused orders is bounded; the count is not.
///
/// A client attached to a room full of records it cannot read refuses one
/// per replayed entry. Keeping every order would make a diagnostic the
/// thing that runs a browser tab out of memory, and the relay holds the
/// claims that actually matter anyway — so this keeps the most recent
/// `max_reported_skips` and counts the rest.
pub fn the_reported_skip_list_is_bounded_test() -> Nil {
  let hub = relay_fake.new_hub()
  let events = transport_js.new_cell([])
  let refuse = transport_js.new_cell(["always"])
  let relay = refusing_client(hub, refuse, events)
  let alpha = document("alpha")
  let payload = crdt_core.encode(alpha, crdt_core.hello_message(alpha))

  // Admitted, so the relay honours the skips this socket reports rather
  // than closing it for talking out of turn.
  let _ = crdt_sequencer_js.send_envelope(relay, payload)
  relay_fake.settle(hub)
  let assert [connection] = relay_fake.open_sockets(hub)

  let refusals = crdt_sequencer_js.max_reported_skips * 3
  list.each(list.repeat(Nil, refusals), fn(_) {
    let order = crdt_sequencer_js.last_order(relay) + 1
    relay_fake.inject(
      hub,
      connection,
      crdt_relay.server_to_string(crdt_relay.Frame(order, payload)),
    )
    relay_fake.settle(hub)
  })

  crdt_sequencer_js.skip_count(relay) |> expect.to_equal(refusals)
  crdt_sequencer_js.skipped_orders(relay)
  |> list.length
  |> expect.to_equal(crdt_sequencer_js.max_reported_skips)
  // The newest are the ones kept: an operator looking at this wants what
  // just happened, not what happened first.
  crdt_sequencer_js.skipped_orders(relay)
  |> list.last
  |> expect.to_equal(Ok(crdt_sequencer_js.last_order(relay)))
  // Every one of them was still reported to the relay, which is where the
  // claim that matters lives.
  relay_fake.inbound(hub)
  |> list.filter(fn(raw) { string.contains(raw, "\"type\":\"skip\"") })
  |> list.length
  |> expect.to_equal(refusals)
}

@target(javascript)
/// A client whose `on_envelope` refuses whenever `refuse` is non-empty.
fn refusing_client(
  hub: Hub,
  refuse: Cell(List(String)),
  events: Cell(List(String)),
) -> Relay {
  let relay =
    crdt_sequencer_js.start(
      url: "ws://relay.test/",
      driver: relay_fake.driver(hub),
      scheduler: relay_fake.scheduler(relay_fake.new_clock()),
      events: crdt_sequencer_js.Events(
        on_connecting: fn() { Nil },
        on_ready: fn() { note(events, "ready") },
        on_envelope: fn(_raw) { transport_js.get_cell(refuse) == [] },
        on_synced: fn() { note(events, "synced") },
        on_attested: fn(_digest) { Nil },
        on_checkpoint_requested: fn() { note(events, "checkpointRequested") },
        on_unsupported: fn(_detail) { Nil },
        on_dropped: fn(_detail) { note(events, "dropped") },
        on_retry: fn(_delay) { Nil },
        on_error: fn(_error) { Nil },
      ),
    )
  crdt_sequencer_js.connect(relay)
  relay_fake.settle(hub)
  relay
}

@target(javascript)
/// A write that does not reach an open socket is reported as a `SendFailed`.
/// The caller's fallback depends on knowing, and a `send` that always claimed
/// success would make a silent hole in a document's durable path.
pub fn a_write_to_a_socket_that_is_gone_answers_false_test() -> Nil {
  let hub = relay_fake.new_hub()
  let client = spawn(hub, relay_fake.new_clock())
  let alpha = document("alpha")
  let payload = crdt_core.encode(alpha, crdt_core.hello_message(alpha))

  crdt_sequencer_js.send_envelope(client.relay, payload)
  |> expect.to_be_ok()

  relay_fake.set_writable(hub, False)
  crdt_sequencer_js.send_envelope(client.relay, payload)
  |> expect.to_equal(Error(SendFailed))
  crdt_sequencer_js.attest(client.relay, "abc")
  |> expect.to_equal(Error(SendFailed))
}

@target(javascript)
/// `abort` retires the socket the way a reported close would: one drop,
/// and the policy's reconnect scheduled behind it.
pub fn aborting_a_socket_drops_it_and_retries_test() -> Nil {
  let hub = relay_fake.new_hub()
  let clock = relay_fake.new_clock()
  let client = spawn(hub, clock)

  crdt_sequencer_js.abort(client.relay, "the relay socket was not writable")
  relay_fake.settle(hub)

  events(client)
  |> list.filter(fn(entry) { entry == "dropped" })
  |> expect.to_equal(["dropped"])
  relay_fake.delays(clock) |> expect.to_equal([250])

  relay_fake.advance(clock, 250)
  relay_fake.settle(hub)
  crdt_sequencer_js.is_ready(client.relay) |> expect.to_be_true()
  transport_js.get_cell(client.connects) |> expect.to_equal(2)
}

@target(javascript)
pub fn the_backoff_sequence_is_exactly_the_documented_one_test() -> Nil {
  [0, 1, 2, 3, 4, 5, 99]
  |> list.map(crdt_sequencer_js.backoff_ms)
  |> expect.to_equal([250, 500, 1000, 2000, 5000, 5000, 5000])
}

@target(javascript)
pub fn a_relay_that_stamps_no_order_is_still_read_test() -> Nil {
  let hub = relay_fake.new_hub()
  let alpha = document("alpha")
  let client = spawn(hub, relay_fake.new_clock())
  let assert [connection] = relay_fake.open_sockets(hub)

  // A bare envelope, with no wrapper and no order at all.
  relay_fake.inject(
    hub,
    connection,
    crdt_core.encode(alpha, crdt_core.hello_message(alpha)),
  )
  relay_fake.settle(hub)

  events(client) |> expect.to_equal(["ready", "envelope hello from alpha"])
  crdt_sequencer_js.last_order(client.relay) |> expect.to_equal(0)
  let _ = None
  Nil
}

// ─────────────────────────────────────────────────────────────────────────────
// Checkpoint requests
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// A client declares what it understands, once, after the `hello` that
/// admits it — and only then is it ever sent a `CheckpointRequest`.
pub fn support_is_declared_and_the_relay_records_it_test() -> Nil {
  let hub = relay_fake.new_hub()
  let alpha = document("alpha")
  let client = spawn(hub, relay_fake.new_clock())

  let _ =
    crdt_sequencer_js.send_envelope(
      client.relay,
      crdt_core.encode(alpha, crdt_core.hello_message(alpha)),
    )
  relay_fake.settle(hub)
  relay_fake.supports_checkpoints(hub, 1) |> expect.to_be_false()

  crdt_sequencer_js.declare_support(client.relay) |> expect.to_be_ok()
  relay_fake.settle(hub)
  relay_fake.supports_checkpoints(hub, 1) |> expect.to_be_true()
  // It is control, not content: nothing was logged and no order was
  // stamped for it.
  relay_fake.log_size(hub, room) |> expect.to_equal(0)
  relay_fake.next_order(hub, room) |> expect.to_equal(2)
}

@target(javascript)
/// A request reaches the owner as an event and nothing else: no order is
/// noted, so the client's high-water mark — the only number it ever
/// quotes back — is untouched by one.
pub fn a_checkpoint_request_is_reported_and_moves_no_mark_test() -> Nil {
  let hub = relay_fake.new_hub()
  let alpha = document("alpha")
  let client = spawn(hub, relay_fake.new_clock())

  let _ =
    crdt_sequencer_js.send_envelope(
      client.relay,
      crdt_core.encode(alpha, crdt_core.hello_message(alpha)),
    )
  relay_fake.settle(hub)
  let before = crdt_sequencer_js.last_order(client.relay)

  relay_fake.inject(
    hub,
    1,
    crdt_relay.server_to_string(crdt_relay.CheckpointRequest),
  )
  relay_fake.settle(hub)

  events(client) |> expect.to_equal(["ready", "checkpointRequested"])
  crdt_sequencer_js.last_order(client.relay) |> expect.to_equal(before)
}
