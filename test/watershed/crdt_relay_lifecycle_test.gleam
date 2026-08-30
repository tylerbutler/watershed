//// Deterministic tests for the optional sequencer relay, end to end
//// through the public facade.
////
//// Three seams make this possible without a browser, a socket, or a
//// clock: `crdt_js.attach_with_rtc` takes the fake `RTCPeerConnection`
//// mesh the transport tests use, `crdt_js.with_relay_driver` takes a
//// relay driver, and `crdt_js.with_scheduler` takes a logical clock.
//// The relay behind the driver runs the *real* `crdt_relay` protocol,
//// so what is being tested is the contract a service has to implement
//// and not a convenient fiction about one.
////
//// What these tests are about, in one sentence each:
////
//// - a policy decides which transports open, and `Auto`'s readiness
////   never waits for a relay;
//// - attachment merges before it publishes and only claims the relay
////   after the digests agree;
//// - two replicas attaching at once both survive, and neither is
////   declared the winner;
//// - a delta that arrives twice is one state change and one event;
//// - a relay that dies mid-burst costs nothing — not a delta, not a
////   handle, not an identity, not a pause;
//// - and a relay that comes back merges both sides before it is trusted
////   again.

@target(javascript)
import gleam/int
@target(javascript)
import gleam/json
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{type Option, None, Some}
@target(javascript)
import gleam/string
@target(javascript)
import startest/expect

@target(javascript)
import watershed/channel
@target(javascript)
import watershed/crdt_core
@target(javascript)
import watershed/crdt_js.{
  type CrdtConnection, type CrdtDocument, type Status, Auto, P2pOnly, PeerToPeer,
  Sequenced, SequencedOnly,
}
@target(javascript)
import watershed/crdt_relay
@target(javascript)
import watershed/crdt_wire
@target(javascript)
import watershed/p2p
@target(javascript)
import watershed/p2p_fake
@target(javascript)
import watershed/p2p_transport_js.{
  type Signal, type Signaling, type Transport, Callbacks, Message, PeerJoined,
  PeerLeft, Roster, Signaling,
}
@target(javascript)
import watershed/pn_counter_kernel
@target(javascript)
import watershed/relay_fake.{type Clock, type Hub}
@target(javascript)
import watershed/schema
@target(javascript)
import watershed/transport_js.{type Cell}

@target(javascript)
const room = "trip-planning"

@target(javascript)
const tag = "clap-counter/v1"

// ─────────────────────────────────────────────────────────────────────────────
// A synchronous signaling hub, with a join counter
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
pub type SignalHub {
  SignalHub(
    members: Cell(List(#(String, fn(Signal) -> Nil))),
    joins: Cell(List(String)),
  )
}

@target(javascript)
fn new_signal_hub() -> SignalHub {
  SignalHub(
    members: transport_js.new_cell([]),
    joins: transport_js.new_cell([]),
  )
}

@target(javascript)
/// Announces membership in both directions from inside `join`, and
/// counts the joins — which is how "`SequencedOnly` does not join
/// signaling" is asserted rather than assumed.
fn hub_signaling(hub: SignalHub) -> Signaling {
  Signaling(
    join: fn(joined_room, peer_id, on_signal) {
      transport_js.set_cell(hub.joins, [
        peer_id,
        ..transport_js.get_cell(hub.joins)
      ])
      let existing = transport_js.get_cell(hub.members)
      transport_js.set_cell(hub.members, [#(peer_id, on_signal), ..existing])
      on_signal(Roster(
        existing
        |> list.map(fn(member) { member.0 })
        |> list.sort(string.compare),
      ))
      list.each(existing, fn(member) { member.1(PeerJoined(peer_id)) })
      Ok(p2p_transport_js.signaling_session(room: joined_room, peer_id: peer_id))
    },
    send: fn(session, to, payload) {
      let from = p2p_transport_js.session_peer_id(session)
      case
        list.find(transport_js.get_cell(hub.members), fn(member) {
          member.0 == to
        })
      {
        Ok(member) -> member.1(Message(from: from, payload: payload))
        Error(Nil) -> Nil
      }
    },
    leave: fn(session) {
      let peer_id = p2p_transport_js.session_peer_id(session)
      let remaining =
        list.filter(transport_js.get_cell(hub.members), fn(member) {
          member.0 != peer_id
        })
      transport_js.set_cell(hub.members, remaining)
      list.each(remaining, fn(member) { member.1(PeerLeft(peer_id)) })
    },
  )
}

@target(javascript)
fn joins(hub: SignalHub) -> Int {
  list.length(transport_js.get_cell(hub.joins))
}

// ─────────────────────────────────────────────────────────────────────────────
// Members
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
type Member {
  Member(
    document: CrdtDocument(schema.PnCounterChannel),
    connection: CrdtConnection,
    statuses: Cell(List(String)),
    readies: Cell(List(String)),
    events: Cell(List(String)),
    /// The effective path as it was at the moment each status was
    /// delivered. This is what proves the path flips *before* the status
    /// that reports it.
    paths: Cell(List(String)),
  )
}

@target(javascript)
type Setup {
  Setup(
    world: p2p_fake.World,
    signals: SignalHub,
    relay: Option(Hub),
    clock: Clock,
    policy: crdt_js.TransportPolicy,
    deadline_ms: Int,
    /// The anti-entropy interval every member here coalesces peer
    /// digests over. Injected rather than assumed, which is the point of
    /// it being a configuration value at all.
    anti_entropy_ms: Int,
  )
}

@target(javascript)
fn setup(policy: crdt_js.TransportPolicy) -> Setup {
  Setup(
    world: p2p_fake.new_world(),
    signals: new_signal_hub(),
    relay: Some(relay_fake.new_hub()),
    clock: relay_fake.new_clock(),
    policy: policy,
    deadline_ms: crdt_js.default_readiness_deadline_ms,
    anti_entropy_ms: crdt_js.default_anti_entropy_ms,
  )
}

@target(javascript)
fn spawn(env: Setup, label: String) -> Member {
  spawn_as(env, label, env.policy)
}

@target(javascript)
/// One member under a policy of its own, so a room can hold replicas of
/// more than one — which is the case a relay has to keep converging.
fn spawn_as(
  env: Setup,
  label: String,
  policy: crdt_js.TransportPolicy,
) -> Member {
  spawn_offline(env, label, policy, fn(_document) { Nil })
}

@target(javascript)
/// `spawn_as`, with a chance to edit the document *before* it attaches:
/// a replica that was working with no transport at all and brings its own
/// state to the room. What it holds reaches its peers as a `state`
/// transfer on the handshake rather than as deltas, which is a different
/// merge path owing the same durability.
fn spawn_offline(
  env: Setup,
  label: String,
  policy: crdt_js.TransportPolicy,
  offline: fn(CrdtDocument(schema.PnCounterChannel)) -> Nil,
) -> Member {
  let base =
    crdt_js.config(
      room_id: room,
      replica_label: label,
      compatibility_tag: tag,
      root: p2p.pn_counter_root(),
      signaling: hub_signaling(env.signals),
    )
    |> crdt_js.with_transport_policy(policy)
    |> crdt_js.with_scheduler(relay_fake.scheduler(env.clock))
    |> crdt_js.with_anti_entropy_interval_ms(env.anti_entropy_ms)
  let config = case env.relay {
    None -> base
    Some(hub) ->
      crdt_js.with_sequencer(
        base,
        crdt_js.sequencer("ws://relay.test/")
          |> crdt_js.with_relay_driver(relay_fake.driver(hub))
          |> crdt_js.with_readiness_deadline_ms(env.deadline_ms),
      )
  }
  let assert Ok(document) = crdt_js.new_document(config)
  offline(document)
  let statuses = transport_js.new_cell([])
  let readies = transport_js.new_cell([])
  let events = transport_js.new_cell([])
  let paths = transport_js.new_cell([])
  let connection =
    crdt_js.attach_with_rtc(
      document,
      on_ready: fn(outcome) {
        push(readies, case outcome {
          Ok(_) -> "ok"
          Error(error) -> "error " <> crdt_js.describe_error(error)
        })
      },
      on_status: fn(status) {
        push(statuses, render(status))
        push(paths, render(status) <> " @ " <> path_of(document))
      },
      rtc: p2p_fake.rtc(env.world, crdt_js.replica_id(document)),
    )
  let _ =
    crdt_js.subscribe_pn_counter(crdt_js.root(document), fn(event) {
      let pn_counter_kernel.Updated(applied, total) = event
      push(events, int.to_string(applied) <> "->" <> int.to_string(total))
    })
  Member(
    document: document,
    connection: connection,
    statuses: statuses,
    readies: readies,
    events: events,
    paths: paths,
  )
}

@target(javascript)
fn path_of(document: CrdtDocument(schema.PnCounterChannel)) -> String {
  case crdt_js.effective_path(document) {
    PeerToPeer -> "p2p"
    Sequenced -> "relay"
  }
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
fn relay_statuses(member: Member) -> List(String) {
  entries(member.statuses)
  |> list.filter(fn(entry) { string.starts_with(entry, "relay") })
}

@target(javascript)
fn saw(member: Member, fragment: String) -> Bool {
  list.any(entries(member.statuses), fn(entry) {
    string.starts_with(entry, fragment)
  })
}

@target(javascript)
fn render(status: Status) -> String {
  case status {
    crdt_js.Transport(_) -> "transport"
    crdt_js.TransportError(error) ->
      "transportError " <> crdt_js.describe_error(error)
    crdt_js.Joined(joined_room, _replica) -> "joined " <> joined_room
    crdt_js.RosterKnown(peers) ->
      "rosterKnown " <> int.to_string(list.length(peers))
    crdt_js.AwaitingState(_) -> "awaitingState"
    crdt_js.Ready -> "ready"
    crdt_js.PeerReady(_) -> "peerReady"
    crdt_js.PeerGone(_) -> "peerGone"
    crdt_js.PeerRejected(_, error) ->
      "peerRejected " <> crdt_js.describe_error(error)
    crdt_js.StateMerged(_, channels) ->
      "stateMerged " <> int.to_string(channels)
    crdt_js.RejectedByPeer(_, reason, _) -> "rejectedByPeer " <> reason
    crdt_js.Failed(error) -> "failed " <> crdt_js.describe_error(error)
    crdt_js.SubscriberFailed(_, _) -> "subscriberFailed"
    crdt_js.RelayConnecting(_) -> "relayConnecting"
    crdt_js.RelayUnsupported(_) -> "relayUnsupported"
    crdt_js.RelaySyncingStatus -> "relaySyncing"
    crdt_js.RelayRecovering -> "relayRecovering"
    crdt_js.RelayPrimary(_) -> "relayPrimary"
    crdt_js.RelayCheckpointRequested -> "relayCheckpointRequested"
    crdt_js.RelayCheckpointed(_) -> "relayCheckpointed"
    crdt_js.RelayFallback(_) -> "relayFallback"
    crdt_js.RelayRetry(delay) -> "relayRetry " <> int.to_string(delay)
    crdt_js.RelayRejected(_, error) ->
      "relayRejected " <> crdt_js.describe_error(error)
    crdt_js.RelayFailed(error) ->
      "relayFailed " <> crdt_js.describe_error(error)
  }
}

@target(javascript)
/// Drain both worlds until neither has anything left to deliver. The
/// mesh and the relay each enqueue into the other, so one pass of each
/// is not enough; the loop stops when a round changes nothing.
///
/// A round also runs the timers that are due *now*, which is what a
/// browser's task queue does between two turns of its event loop, and
/// what the coalesced peer digest is armed on. Nothing here moves the
/// clock forward: every backoff is still stepped explicitly with
/// `relay_fake.advance`.
fn settle(env: Setup) -> Nil {
  settle_rounds(env, 12)
}

@target(javascript)
fn settle_rounds(env: Setup, fuel: Int) -> Nil {
  case fuel <= 0 {
    True -> panic as "crdt_relay_lifecycle_test: the world did not settle"
    False -> {
      p2p_fake.settle(env.world)
      case env.relay {
        None -> Nil
        Some(hub) -> {
          relay_fake.settle(hub)
          let ticks = relay_fake.due(env.clock)
          relay_fake.advance(env.clock, 0)
          p2p_fake.settle(env.world)
          case relay_fake.pending(hub) > 0 || ticks > 0 {
            True -> settle_rounds(env, fuel - 1)
            False -> Nil
          }
        }
      }
    }
  }
}

@target(javascript)
/// Settle, then step the resync backoff a few times.
///
/// Two replicas attaching at once each hold something the other has not
/// merged, so neither can attest until the timer separates them — which
/// is the design, not an accident, and a test that wants convergence has
/// to let the clock run for it.
fn converge(env: Setup) -> Nil {
  settle(env)
  list.each([250, 500, 1000, 2000], fn(delay) {
    relay_fake.advance(env.clock, delay)
    settle(env)
  })
}

@target(javascript)
/// Settle, wait out one anti-entropy interval, and settle again — what a
/// document does between an edit and its peers hearing about it.
fn anti_entropy(env: Setup) -> Nil {
  settle(env)
  relay_fake.advance(env.clock, env.anti_entropy_ms)
  settle(env)
}

@target(javascript)
/// The message type of everything `from` has written to `to` over the
/// mesh, oldest first. The fake records every data-channel write, so
/// "the peer never asked for state" is an assertion rather than an
/// absence.
fn mesh_types(env: Setup, from: String, to: String) -> List(String) {
  p2p_fake.channel_payloads(env.world)
  |> list.filter(fn(entry) { entry.0 == from && entry.1 == to })
  |> list.map(fn(entry) {
    case crdt_relay.decode_client(entry.2) {
      Ok(crdt_relay.Document(_, _, _, _, message)) ->
        crdt_relay.message_kind_to_string(message)
      Ok(crdt_relay.Control(..)) | Error(_) -> "opaque"
    }
  })
}

@target(javascript)
/// How many messages of one kind `from` has written to `to` over the
/// mesh. A count rather than a membership test, because a room's
/// handshake legitimately carries one of most of them and what a later
/// assertion is about is what came *after* that.
fn mesh_kinds(env: Setup, link: #(String, String), kind: String) -> Int {
  mesh_types(env, link.0, link.1)
  |> list.filter(fn(found) { found == kind })
  |> list.length
}

@target(javascript)
fn hub_of(env: Setup) -> Hub {
  let assert Some(hub) = env.relay
  hub
}

@target(javascript)
/// How many `state` publications clients have written to this relay.
///
/// A publication is what makes a merge durable, and it is also the frame
/// a feedback loop would repeat: the relay fans every publication to the
/// room, so a client that answered one with another would publish for as
/// long as the room was open. Counting them is how "one per coalesced
/// interval, from the replicas that merged the mesh, and none in answer
/// to the relay's own fan-out" is a number rather than a hope.
fn publications(env: Setup) -> Int {
  relay_fake.inbound(hub_of(env))
  |> list.filter(fn(raw) {
    case crdt_relay.decode_client(raw) {
      Ok(crdt_relay.Document(_, _, _, _, crdt_relay.StateMessage)) -> True
      Ok(crdt_relay.Document(_, _, _, _, crdt_relay.HelloMessage))
      | Ok(crdt_relay.Document(_, _, _, _, crdt_relay.ChannelMessage))
      | Ok(crdt_relay.Document(_, _, _, _, crdt_relay.DeltaMessage))
      | Ok(crdt_relay.Document(_, _, _, _, crdt_relay.StateRequestMessage))
      | Ok(crdt_relay.Document(_, _, _, _, crdt_relay.DigestMessage))
      | Ok(crdt_relay.Control(..))
      | Error(_) -> False
    }
  })
  |> list.length
}

@target(javascript)
fn value(member: Member) -> Int {
  let assert Ok(total) = crdt_js.pn_counter_value(crdt_js.root(member.document))
  total
}

@target(javascript)
fn clap(member: Member, amount: Int) -> Nil {
  let assert Ok(Nil) =
    crdt_js.pn_counter_update(crdt_js.root(member.document), amount)
  Nil
}

// ─────────────────────────────────────────────────────────────────────────────
// The policy matrix
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// `P2pOnly` ignores a configured sequencer rather than contacting it.
pub fn p2p_only_opens_no_relay_test() -> Nil {
  let env = setup(P2pOnly)
  let alpha = spawn(env, "alpha")
  settle(env)

  entries(alpha.readies) |> expect.to_equal(["ok"])
  crdt_js.relay_attached_lane(alpha.document) |> expect.to_be_false()
  relay_fake.opens(hub_of(env)) |> expect.to_equal(0)
  crdt_js.effective_path(alpha.document) |> expect.to_equal(PeerToPeer)
  relay_statuses(alpha) |> expect.to_equal([])
  relay_fake.delays(env.clock) |> expect.to_equal([])
}

@target(javascript)
/// `Auto` keeps the Task 5 readiness behaviour exactly: the mesh decides
/// when the document is ready, and the relay has not even been asked for
/// a socket by the time it is.
pub fn auto_is_ready_before_the_relay_is_test() -> Nil {
  let env = setup(Auto)
  let alpha = spawn(env, "alpha")

  // No settle: readiness did not wait for an event queue, let alone a
  // relay handshake.
  entries(alpha.readies) |> expect.to_equal(["ok"])
  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_false()
  crdt_js.effective_path(alpha.document) |> expect.to_equal(PeerToPeer)
  saw(alpha, "relayPrimary") |> expect.to_be_false()

  settle(env)
  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_true()
  crdt_js.effective_path(alpha.document) |> expect.to_equal(Sequenced)
  relay_statuses(alpha)
  |> expect.to_equal(["relayConnecting", "relaySyncing", "relayPrimary"])
}

@target(javascript)
/// `Auto` with a relay that is down is `Auto` with no relay at all, as
/// far as the document is concerned.
pub fn auto_is_ready_with_a_relay_that_never_answers_test() -> Nil {
  let env = setup(Auto)
  relay_fake.stop(hub_of(env))
  let alpha = spawn(env, "alpha")
  settle(env)

  entries(alpha.readies) |> expect.to_equal(["ok"])
  crdt_js.effective_path(alpha.document) |> expect.to_equal(PeerToPeer)
  clap(alpha, 3)
  value(alpha) |> expect.to_equal(3)
  saw(alpha, "relayRetry") |> expect.to_be_true()
}

@target(javascript)
/// `SequencedOnly` joins no signaling and opens no data channel, and its
/// readiness is the relay's alone.
pub fn sequenced_only_skips_signaling_and_webrtc_test() -> Nil {
  let env = setup(SequencedOnly)
  let alpha = spawn(env, "alpha")

  joins(env.signals) |> expect.to_equal(0)
  entries(alpha.readies) |> expect.to_equal([])
  crdt_js.peers(alpha.document) |> expect.to_equal([])

  settle(env)
  entries(alpha.readies) |> expect.to_equal(["ok"])
  joins(env.signals) |> expect.to_equal(0)
  crdt_js.effective_path(alpha.document) |> expect.to_equal(Sequenced)
  // The document is the same one every other policy builds: same core,
  // same envelopes, same eligibility boundary.
  clap(alpha, 4)
  value(alpha) |> expect.to_equal(4)
}

@target(javascript)
/// `SequencedOnly` with nothing to sequence against fails once, at once.
pub fn sequenced_only_without_a_sequencer_fails_once_test() -> Nil {
  let env = Setup(..setup(SequencedOnly), relay: None)
  let alpha = spawn(env, "alpha")
  settle(env)

  entries(alpha.readies)
  |> expect.to_equal([
    "error sequencerUnavailable · sequencedOnly needs a sequencer, and none "
    <> "was configured",
  ])
  crdt_js.is_closed(alpha.document) |> expect.to_be_true()
  joins(env.signals) |> expect.to_equal(0)
}

@target(javascript)
/// The readiness deadline is a bound on the whole attachment, and firing
/// it is one failure and a close — not a retry loop nobody is watching.
pub fn sequenced_only_fails_at_its_deadline_test() -> Nil {
  let env = Setup(..setup(SequencedOnly), deadline_ms: 10_000)
  relay_fake.stop(hub_of(env))
  let alpha = spawn(env, "alpha")
  settle(env)
  entries(alpha.readies) |> expect.to_equal([])

  relay_fake.advance(env.clock, 9999)
  settle(env)
  entries(alpha.readies) |> expect.to_equal([])

  relay_fake.advance(env.clock, 1)
  settle(env)
  entries(alpha.readies)
  |> expect.to_equal([
    "error sequencerUnavailable · the sequencer did not become the durable "
    <> "path within 10000ms",
  ])
  crdt_js.is_closed(alpha.document) |> expect.to_be_true()

  // Closed means closed: no further attempt, and no second result.
  relay_fake.resume(hub_of(env))
  relay_fake.advance(env.clock, 60_000)
  settle(env)
  entries(alpha.readies) |> list.length |> expect.to_equal(1)
}

@target(javascript)
/// A relay that answers without the lane is a status under `Auto`.
pub fn auto_reports_an_unsupported_relay_and_stays_on_webrtc_test() -> Nil {
  let env = setup(Auto)
  relay_fake.set_capability(hub_of(env), False)
  let alpha = spawn(env, "alpha")
  settle(env)

  entries(alpha.readies) |> expect.to_equal(["ok"])
  crdt_js.effective_path(alpha.document) |> expect.to_equal(PeerToPeer)
  relay_statuses(alpha)
  |> expect.to_equal(["relayConnecting", "relayUnsupported"])
  clap(alpha, 2)
  value(alpha) |> expect.to_equal(2)

  // Terminal: a capability does not appear by being asked for again.
  relay_fake.advance(env.clock, 60_000)
  settle(env)
  relay_fake.opens(hub_of(env)) |> expect.to_equal(1)
}

@target(javascript)
/// The same answer is a readiness failure under `SequencedOnly`.
pub fn sequenced_only_fails_when_the_lane_is_missing_test() -> Nil {
  let env = setup(SequencedOnly)
  relay_fake.set_capability(hub_of(env), False)
  let alpha = spawn(env, "alpha")
  settle(env)

  entries(alpha.readies) |> expect.to_equal(["error sequencerUnsupported"])
  crdt_js.is_closed(alpha.document) |> expect.to_be_true()
  saw(alpha, "relayUnsupported") |> expect.to_be_true()
}

// ─────────────────────────────────────────────────────────────────────────────
// Attachment
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// The handshake, in order: merge what the relay holds, publish the
/// merged result, and claim the relay only once the digests agree.
pub fn a_late_attachment_merges_publishes_then_claims_the_relay_test() -> Nil {
  let env = setup(Auto)
  let alpha = spawn(env, "alpha")
  settle(env)
  clap(alpha, 3)
  settle(env)
  crdt_js.close(alpha.connection)
  settle(env)

  // The relay is all that is left of the room: an attested checkpoint,
  // and the delta alpha authored after it.
  relay_fake.log_size(hub_of(env), room) |> expect.to_equal(2)

  let beta = spawn(env, "beta")
  // Ready on its own empty root the instant it joins: nothing waited.
  entries(beta.readies) |> expect.to_equal(["ok"])
  value(beta) |> expect.to_equal(0)

  settle(env)
  value(beta) |> expect.to_equal(3)
  crdt_js.relay_is_primary(beta.document) |> expect.to_be_true()
  crdt_js.digest(beta.document)
  |> expect.to_equal(relay_fake.attested(hub_of(env), room))
  relay_statuses(beta)
  |> expect.to_equal(["relayConnecting", "relaySyncing", "relayPrimary"])
  // The merge reached the subscriber exactly once, as a merge and not as
  // a replacement.
  entries(beta.events) |> expect.to_equal(["3->3"])
}

@target(javascript)
/// Two replicas attaching at once publish two different states. The
/// relay keeps both, refuses to call either the winner, and the clients
/// converge by merging and republishing — which is the only thing that
/// can be true of a service that cannot merge.
pub fn two_concurrent_attachments_converge_without_a_winner_test() -> Nil {
  // Separate signaling, one relay: this is the relay's convergence, not
  // the mesh's.
  let hub = relay_fake.new_hub()
  let clock = relay_fake.new_clock()
  let one =
    Setup(
      world: p2p_fake.new_world(),
      signals: new_signal_hub(),
      relay: Some(hub),
      clock: clock,
      policy: Auto,
      deadline_ms: crdt_js.default_readiness_deadline_ms,
      anti_entropy_ms: crdt_js.default_anti_entropy_ms,
    )
  let two = Setup(..one, world: p2p_fake.new_world(), signals: new_signal_hub())

  let alpha = spawn(one, "alpha")
  let beta = spawn(two, "beta")
  clap(alpha, 2)
  clap(beta, 5)

  // Neither has seen the other, and both are about to publish. Two
  // attestations that each cover only their own author cancel out, and
  // the backoff is what separates them — so the clock has to run.
  list.each([0, 250, 500, 1000, 2000], fn(delay) {
    relay_fake.advance(clock, delay)
    settle(one)
    settle(two)
  })

  value(alpha) |> expect.to_equal(7)
  value(beta) |> expect.to_equal(7)
  crdt_js.digest(alpha.document)
  |> expect.to_equal(crdt_js.digest(beta.document))
  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_true()
  crdt_js.relay_is_primary(beta.document) |> expect.to_be_true()
  // The log collapsed to one attested checkpoint rather than keeping a
  // pile of states nobody could choose between.
  relay_fake.log_size(hub, room) |> expect.to_equal(1)
  relay_fake.attested(hub, room)
  |> expect.to_equal(crdt_js.digest(alpha.document))
}

@target(javascript)
/// Attachment does not replace anything. The document, its root handle,
/// its subscriptions, its replica identity and its message counter are
/// the same objects before and after.
pub fn attachment_replaces_nothing_test() -> Nil {
  let env = setup(Auto)
  let alpha = spawn(env, "alpha")
  let root = crdt_js.root(alpha.document)
  let replica = crdt_js.replica_id(alpha.document)
  clap(alpha, 1)
  settle(env)

  crdt_js.replica_id(alpha.document) |> expect.to_equal(replica)
  crdt_js.address(root) |> expect.to_equal(crdt_wire.root_address)
  crdt_js.pn_counter_value(root) |> expect.to_equal(Ok(1))
  clap(alpha, 1)
  entries(alpha.events) |> expect.to_equal(["1->1", "1->2"])
}

// ─────────────────────────────────────────────────────────────────────────────
// Duplicates
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// The same delta over WebRTC and over the relay is one state change and
/// one subscriber event, whichever arrives first.
pub fn a_duplicate_over_both_paths_changes_state_once_test() -> Nil {
  duplicate_case(webrtc_first: True)
  duplicate_case(webrtc_first: False)
}

@target(javascript)
fn duplicate_case(webrtc_first webrtc_first: Bool) -> Nil {
  let env = setup(Auto)
  let alpha = spawn(env, "alpha")
  let carol = raw_peer(env, "carol")
  settle(env)
  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_true()

  let target = crdt_js.replica_id(alpha.document)
  send_raw(
    carol,
    target,
    crdt_core.encode(carol.document, crdt_core.hello_message(carol.document)),
  )
  settle(env)

  let #(_carol, delta) = raw_delta(carol.document, 6)
  let assert [connection] = relay_fake.open_sockets(hub_of(env))
  let over_relay = fn() {
    relay_fake.inject(
      hub_of(env),
      connection,
      crdt_relay.server_to_string(crdt_relay.Frame(99, delta)),
    )
  }
  let over_webrtc = fn() { send_raw(carol, target, delta) }

  case webrtc_first {
    True -> {
      over_webrtc()
      settle(env)
      over_relay()
    }
    False -> {
      over_relay()
      settle(env)
      over_webrtc()
    }
  }
  settle(env)

  value(alpha) |> expect.to_equal(6)
  entries(alpha.events) |> expect.to_equal(["6->6"])
}

@target(javascript)
/// A relay client that sends something the local document refuses costs
/// its own envelope and nothing else: the lane stays up, because closing
/// it would punish every other replica for one replica's bad frame.
pub fn a_refused_relay_envelope_does_not_cost_the_lane_test() -> Nil {
  let env = setup(Auto)
  let alpha = spawn(env, "alpha")
  settle(env)
  clap(alpha, 2)
  settle(env)

  let assert [connection] = relay_fake.open_sockets(hub_of(env))
  let assert Ok(mismatched) =
    crdt_core.new(crdt_core.config(
      room: room,
      compatibility: "some-other-app/v9",
      replica: "mallory",
      session: "mallory-session",
      root: p2p.kind_init(p2p.pn_counter_root()),
    ))
  relay_fake.inject(
    hub_of(env),
    connection,
    crdt_relay.server_to_string(crdt_relay.Frame(
      99,
      crdt_core.encode(mismatched, crdt_core.hello_message(mismatched)),
    )),
  )
  settle(env)

  saw(alpha, "relayRejected") |> expect.to_be_true()
  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_true()
  value(alpha) |> expect.to_equal(2)
}

// ─────────────────────────────────────────────────────────────────────────────
// Failover
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// A relay that dies during a burst of local edits loses none of them
/// and pauses nothing. Every delta authored in the window reaches the
/// peer over WebRTC, and the document never stops accepting writes.
pub fn a_relay_failure_during_a_mutation_burst_loses_nothing_test() -> Nil {
  let env = setup(Auto)
  let alpha = spawn(env, "alpha")
  let beta = spawn(env, "beta")
  converge(env)
  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_true()
  crdt_js.relay_is_primary(beta.document) |> expect.to_be_true()

  clap(alpha, 1)
  relay_fake.stop(hub_of(env))
  // Authored with the socket already gone and the drop not yet observed.
  clap(alpha, 1)
  clap(alpha, 1)
  settle(env)
  clap(alpha, 1)
  clap(alpha, 1)
  settle(env)

  value(alpha) |> expect.to_equal(5)
  value(beta) |> expect.to_equal(5)
  crdt_js.effective_path(alpha.document) |> expect.to_equal(PeerToPeer)
  entries(alpha.events)
  |> expect.to_equal(["1->1", "1->2", "1->3", "1->4", "1->5"])
}

@target(javascript)
/// The path is the mesh again *before* the fallback is announced, so a
/// mutation authored from a status handler takes the surviving route.
pub fn the_path_flips_before_the_fallback_is_reported_test() -> Nil {
  let env = setup(Auto)
  let alpha = spawn(env, "alpha")
  settle(env)

  relay_fake.stop(hub_of(env))
  settle(env)

  entries(alpha.paths)
  |> list.filter(fn(entry) { string.starts_with(entry, "relayFallback") })
  |> expect.to_equal(["relayFallback @ p2p"])
  entries(alpha.paths)
  |> list.filter(fn(entry) { string.starts_with(entry, "relayPrimary") })
  |> expect.to_equal(["relayPrimary @ relay"])
}

@target(javascript)
/// A relay outage does not reset a session. Same replica id, same root
/// address, same subscription, same counter — a transport changed, not
/// an identity.
pub fn a_switch_keeps_the_document_handles_and_identity_test() -> Nil {
  let env = setup(Auto)
  let alpha = spawn(env, "alpha")
  let root = crdt_js.root(alpha.document)
  settle(env)
  let replica = crdt_js.replica_id(alpha.document)
  let label = crdt_js.replica_label(alpha.document)

  clap(alpha, 1)
  relay_fake.stop(hub_of(env))
  settle(env)
  clap(alpha, 1)
  relay_fake.resume(hub_of(env))
  relay_fake.advance(env.clock, 250)
  settle(env)
  clap(alpha, 1)
  settle(env)

  crdt_js.replica_id(alpha.document) |> expect.to_equal(replica)
  crdt_js.replica_label(alpha.document) |> expect.to_equal(label)
  crdt_js.address(root) |> expect.to_equal(crdt_wire.root_address)
  crdt_js.pn_counter_value(root) |> expect.to_equal(Ok(3))
  crdt_js.is_closed(alpha.document) |> expect.to_be_false()
  entries(alpha.readies) |> expect.to_equal(["ok"])
  entries(alpha.events) |> expect.to_equal(["1->1", "1->2", "1->3"])
}

@target(javascript)
/// Recovery merges the relay's state, the peers' state and the outage's
/// edits, republishes the join, and only then claims the relay again.
pub fn recovery_merges_both_sides_before_it_is_primary_test() -> Nil {
  let env = setup(Auto)
  let alpha = spawn(env, "alpha")
  let beta = spawn(env, "beta")
  converge(env)

  clap(alpha, 1)
  settle(env)
  relay_fake.stop(hub_of(env))
  settle(env)

  // An outage's worth of edits, on both replicas, over WebRTC only.
  clap(alpha, 2)
  clap(beta, 4)
  settle(env)
  value(alpha) |> expect.to_equal(7)
  value(beta) |> expect.to_equal(7)

  relay_fake.resume(hub_of(env))
  relay_fake.advance(env.clock, 250)
  converge(env)

  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_true()
  crdt_js.effective_path(alpha.document) |> expect.to_equal(Sequenced)
  // Recovery, not a first attachment — and it says so.
  saw(alpha, "relayRecovering") |> expect.to_be_true()
  // The relay ended up holding exactly what the replicas hold.
  relay_fake.attested(hub_of(env), room)
  |> expect.to_equal(crdt_js.digest(alpha.document))
  crdt_js.digest(alpha.document)
  |> expect.to_equal(crdt_js.digest(beta.document))
  value(alpha) |> expect.to_equal(7)
}

@target(javascript)
/// A relay restarted from its own durable log is a merge, not a reset:
/// the outage's edits are still on the replicas, the checkpoint is still
/// on the relay, and the two are joined before anything is primary.
pub fn a_restarted_relay_recovers_from_its_log_test() -> Nil {
  let env = setup(Auto)
  let alpha = spawn(env, "alpha")
  settle(env)
  clap(alpha, 3)
  settle(env)
  // A checkpoint, and the delta authored after it — which retires the
  // attestation, because the relay's content has moved past the state
  // that digest described.
  relay_fake.log_size(hub_of(env), room) |> expect.to_equal(2)
  relay_fake.attested(hub_of(env), room) |> expect.to_equal("")
  { list.length(relay_fake.lines(hub_of(env), room)) > 0 }
  |> expect.to_be_true()

  relay_fake.stop(hub_of(env))
  settle(env)
  clap(alpha, 4)
  settle(env)

  // Back from disk, with no memory of any client.
  relay_fake.restart(hub_of(env))
  relay_fake.advance(env.clock, 250)
  settle(env)

  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_true()
  value(alpha) |> expect.to_equal(7)
  relay_fake.attested(hub_of(env), room)
  |> expect.to_equal(crdt_js.digest(alpha.document))
  relay_fake.log_size(hub_of(env), room) |> expect.to_equal(1)
}

@target(javascript)
/// A late client joining a restarted relay sees everything, including
/// the edits made while the relay was not there to see them.
pub fn a_late_client_after_a_restart_sees_everything_test() -> Nil {
  let env = setup(Auto)
  let alpha = spawn(env, "alpha")
  settle(env)
  clap(alpha, 3)
  settle(env)
  relay_fake.stop(hub_of(env))
  settle(env)
  clap(alpha, 4)
  settle(env)
  relay_fake.restart(hub_of(env))
  relay_fake.advance(env.clock, 250)
  settle(env)

  // A different signaling room, so this replica has no peer at all: what
  // it learns, it learns from the relay.
  let elsewhere =
    Setup(..env, signals: new_signal_hub(), world: p2p_fake.new_world())
  let gamma = spawn(elsewhere, "gamma")
  settle(elsewhere)
  settle(env)
  settle(elsewhere)

  value(gamma) |> expect.to_equal(7)
  crdt_js.digest(gamma.document)
  |> expect.to_equal(crdt_js.digest(alpha.document))
  crdt_js.peers(gamma.document) |> expect.to_equal([])
}

@target(javascript)
/// Closing a connection closes its relay lane too, and schedules
/// nothing more.
pub fn closing_a_document_closes_its_relay_test() -> Nil {
  let env = setup(Auto)
  let alpha = spawn(env, "alpha")
  settle(env)
  relay_fake.open_sockets(hub_of(env)) |> list.length |> expect.to_equal(1)

  crdt_js.close(alpha.connection)
  settle(env)
  relay_fake.open_sockets(hub_of(env)) |> expect.to_equal([])

  relay_fake.advance(env.clock, 60_000)
  settle(env)
  relay_fake.opens(hub_of(env)) |> expect.to_equal(1)
  crdt_js.effective_path(alpha.document) |> expect.to_equal(PeerToPeer)
}

// ─────────────────────────────────────────────────────────────────────────────
// Raw peers
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
type RawPeer {
  RawPeer(transport: Transport, document: crdt_core.Document)
}

@target(javascript)
fn raw_peer(env: Setup, peer_id: String) -> RawPeer {
  let assert Ok(document) =
    crdt_core.new(crdt_core.config(
      room: room,
      compatibility: tag,
      replica: peer_id,
      session: "session-" <> peer_id,
      root: channel.InitPnCounter,
    ))
  let assert Ok(transport) =
    p2p_transport_js.start_with_rtc(
      room: room,
      peer_id: peer_id,
      signaling: hub_signaling(env.signals),
      ice_servers: [],
      callbacks: Callbacks(
        on_peer_open: fn(_peer) { Nil },
        on_peer_close: fn(_peer) { Nil },
        on_document: fn(_peer, _payload) { Nil },
        on_status: fn(_status) { Nil },
        on_error: fn(_error) { Nil },
      ),
      rtc: p2p_fake.rtc(env.world, peer_id),
    )
  RawPeer(transport: transport, document: document)
}

@target(javascript)
fn send_raw(peer: RawPeer, to: String, payload: String) -> Nil {
  let _ = p2p_transport_js.send(peer.transport, to, payload)
  Nil
}

@target(javascript)
fn raw_delta(
  document: crdt_core.Document,
  amount: Int,
) -> #(crdt_core.Document, String) {
  let assert Ok(#(document, outcome)) =
    crdt_core.edit(
      document,
      crdt_wire.root_address,
      channel.PnCounterEdit(amount),
    )
  let assert [message, ..] = outcome.broadcast
  #(document, crdt_core.encode(document, message))
}

// ─────────────────────────────────────────────────────────────────────────────
// A log entry no client can merge
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// An envelope a relay accepts and no document will ever merge: a
/// structurally impeccable `delta` for a kernel nobody has, so it passes
/// every check a relay can make without merging and fails at the wire
/// decoder in every replica it is handed to.
fn poison(from: String) -> String {
  poison_at(from, 1)
}

@target(javascript)
/// The same, with a distinct message id and address per index — a flood
/// of poison is a flood of *different* records, not one record repeated.
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

@target(javascript)
/// A relay whose durable log already holds one of those, before anybody
/// attaches.
fn poisoned_hub(clock: Clock) -> #(Hub, Clock) {
  let hub = relay_fake.new_hub()
  relay_fake.seed(hub, room, [
    crdt_relay.record_to_string(crdt_relay.TrafficRecord(
      1,
      "mallory-session",
      poison("mallory"),
    )),
  ])
  #(hub, clock)
}

@target(javascript)
/// The wedge, under `Auto`: a poisoned entry the client refuses must not
/// stop it attesting. It reports the exact order it refused, the relay
/// lets its checkpoint land *around* the entry rather than on top of it,
/// and the relay becomes primary — with the refusal reported, the
/// document untouched, and the entry nobody could read still on disk.
pub fn a_poisoned_log_entry_does_not_wedge_an_auto_document_test() -> Nil {
  let clock = relay_fake.new_clock()
  let #(hub, clock) = poisoned_hub(clock)
  let env =
    Setup(
      world: p2p_fake.new_world(),
      signals: new_signal_hub(),
      relay: Some(hub),
      clock: clock,
      policy: Auto,
      deadline_ms: crdt_js.default_readiness_deadline_ms,
      anti_entropy_ms: crdt_js.default_anti_entropy_ms,
    )
  let alpha = spawn(env, "alpha")
  converge(env)

  saw(alpha, "relayRejected") |> expect.to_be_true()
  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_true()
  crdt_js.effective_path(alpha.document) |> expect.to_equal(Sequenced)
  // The checkpoint landed, and the entry it could not read was carried
  // into it: the state, and the record this client never merged.
  relay_fake.log_size(hub, room) |> expect.to_equal(2)
  relay_fake.attested(hub, room)
  |> expect.to_equal(crdt_js.digest(alpha.document))
  relay_fake.lines(hub, room)
  |> list.any(fn(line) { string.contains(line, "nonsense") })
  |> expect.to_be_true()
  // Reported by order rather than silently dropped.
  relay_fake.inbound(hub)
  |> list.any(fn(raw) { string.contains(raw, "\"type\":\"skip\"") })
  |> expect.to_be_true()

  // And the document is entirely normal afterwards.
  clap(alpha, 3)
  converge(env)
  value(alpha) |> expect.to_equal(3)
  entries(alpha.events) |> expect.to_equal(["3->3"])
}

@target(javascript)
/// The same wedge is a readiness failure under `SequencedOnly`, which has
/// no other path to be ready on: the deadline would fire instead of the
/// document coming up at all.
pub fn a_poisoned_log_entry_does_not_wedge_a_sequenced_only_document_test() -> Nil {
  let clock = relay_fake.new_clock()
  let #(hub, clock) = poisoned_hub(clock)
  let env =
    Setup(
      world: p2p_fake.new_world(),
      signals: new_signal_hub(),
      relay: Some(hub),
      clock: clock,
      policy: SequencedOnly,
      deadline_ms: crdt_js.default_readiness_deadline_ms,
      anti_entropy_ms: crdt_js.default_anti_entropy_ms,
    )
  let alpha = spawn(env, "alpha")
  converge(env)

  entries(alpha.readies) |> expect.to_equal(["ok"])
  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_true()
  relay_fake.log_size(hub, room) |> expect.to_equal(2)

  // The deadline passes with nothing to fire on.
  relay_fake.advance(clock, 60_000)
  converge(env)
  entries(alpha.readies) |> expect.to_equal(["ok"])
  crdt_js.is_closed(alpha.document) |> expect.to_be_false()
}

@target(javascript)
/// A poisoned entry survives a reconnect and a restart the same way: the
/// skip is per socket, so it is made again on the next one, and the entry
/// is still there to be skipped, because no checkpoint is allowed to
/// throw away a record this client could not read.
pub fn a_poisoned_entry_is_skipped_again_after_a_reconnect_test() -> Nil {
  let clock = relay_fake.new_clock()
  let #(hub, clock) = poisoned_hub(clock)
  let env =
    Setup(
      world: p2p_fake.new_world(),
      signals: new_signal_hub(),
      relay: Some(hub),
      clock: clock,
      policy: Auto,
      deadline_ms: crdt_js.default_readiness_deadline_ms,
      anti_entropy_ms: crdt_js.default_anti_entropy_ms,
    )
  let alpha = spawn(env, "alpha")
  converge(env)
  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_true()
  let checkpointed = relay_fake.lines(hub, room)
  list.any(checkpointed, fn(line) { string.contains(line, "nonsense") })
  |> expect.to_be_true()

  // A socket outage, and back: nothing about the room has changed.
  relay_fake.stop(hub)
  converge(env)
  crdt_js.effective_path(alpha.document) |> expect.to_equal(PeerToPeer)
  clap(alpha, 2)
  relay_fake.resume(hub)
  // Long enough for whatever the backoff had reached while it was down.
  relay_fake.advance(clock, 5000)
  converge(env)
  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_true()

  // A restart from the compacted log: the poison replays off disk, is
  // refused and reported again on the new socket, and the new checkpoint
  // carries it forward once more.
  let before = list.length(relay_fake.inbound(hub))
  relay_fake.stop(hub)
  converge(env)
  relay_fake.restart(hub)
  relay_fake.advance(clock, 5000)
  converge(env)
  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_true()
  value(alpha) |> expect.to_equal(2)
  relay_fake.attested(hub, room)
  |> expect.to_equal(crdt_js.digest(alpha.document))
  relay_fake.log_size(hub, room) |> expect.to_equal(2)
  relay_fake.lines(hub, room)
  |> list.any(fn(line) { string.contains(line, "nonsense") })
  |> expect.to_be_true()
  relay_fake.inbound(hub)
  |> list.drop(before)
  |> list.any(fn(raw) { string.contains(raw, "\"type\":\"skip\"") })
  |> expect.to_be_true()
}

@target(javascript)
/// A client that attaches to a room whose poison is still on the relay —
/// because the first client never checkpointed — skips it too, rather
/// than inheriting the wedge.
pub fn a_second_client_skips_the_same_entry_test() -> Nil {
  let clock = relay_fake.new_clock()
  let #(hub, clock) = poisoned_hub(clock)
  let env =
    Setup(
      world: p2p_fake.new_world(),
      signals: new_signal_hub(),
      relay: Some(hub),
      clock: clock,
      policy: Auto,
      deadline_ms: crdt_js.default_readiness_deadline_ms,
      anti_entropy_ms: crdt_js.default_anti_entropy_ms,
    )
  let alpha = spawn(env, "alpha")
  let beta = spawn(env, "beta")
  converge(env)

  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_true()
  crdt_js.relay_is_primary(beta.document) |> expect.to_be_true()
  crdt_js.digest(alpha.document)
  |> expect.to_equal(crdt_js.digest(beta.document))
  // One checkpoint, and the entry neither of them could read.
  relay_fake.log_size(hub, room) |> expect.to_equal(2)
  relay_fake.lines(hub, room)
  |> list.any(fn(line) { string.contains(line, "nonsense") })
  |> expect.to_be_true()
}

// ─────────────────────────────────────────────────────────────────────────────
// Mixed policies, and the mesh underneath a primary relay
// ─────────────────────────────────────────────────────────────────────────────
@target(javascript)
/// A room may hold replicas of more than one policy. While the relay is
/// primary the durable delta goes to the relay and *not* to the mesh —
/// but its digest does, so the replica that never sees this relay finds
/// out it is behind, asks, and converges. One state change, one event,
/// one digest, everywhere.
pub fn a_p2p_only_peer_converges_while_the_relay_is_primary_test() -> Nil {
  let env = setup(Auto)
  let alpha = spawn(env, "alpha")
  let beta = spawn(env, "beta")
  let carol = spawn_as(env, "carol", P2pOnly)
  converge(env)

  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_true()
  crdt_js.relay_is_primary(beta.document) |> expect.to_be_true()
  crdt_js.relay_is_primary(carol.document) |> expect.to_be_false()
  crdt_js.effective_path(carol.document) |> expect.to_equal(PeerToPeer)

  clap(alpha, 3)
  converge(env)
  clap(carol, 4)
  converge(env)

  value(alpha) |> expect.to_equal(7)
  value(beta) |> expect.to_equal(7)
  value(carol) |> expect.to_equal(7)
  crdt_js.digest(alpha.document)
  |> expect.to_equal(crdt_js.digest(carol.document))
  crdt_js.digest(beta.document)
  |> expect.to_equal(crdt_js.digest(carol.document))
  // Merged, not replayed: each replica saw each change once.
  list.length(entries(carol.events)) |> expect.to_equal(2)
  list.length(entries(beta.events)) |> expect.to_equal(2)
}

@target(javascript)
/// A `P2pOnly` peer's edit is durable, not just convergent.
///
/// While the relay is primary a delta a peer sends over WebRTC is merged
/// and then carried by nobody: a received message never populates
/// `broadcast`, so the room's history, its checkpoint and every replica
/// that only ever talks to the relay would go on without it until an
/// unrelated publication happened to sweep it up. The merge that moved
/// this replica is what owes the relay a publication, and the coalesced
/// interval is when it pays.
pub fn a_p2p_only_edit_reaches_the_relays_durable_history_test() -> Nil {
  let env = setup(Auto)
  let alpha = spawn(env, "alpha")
  let carol = spawn_as(env, "carol", P2pOnly)
  converge(env)
  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_true()
  crdt_js.effective_path(carol.document) |> expect.to_equal(PeerToPeer)

  // The only edit in the room is authored where the relay cannot see it.
  clap(carol, 4)
  anti_entropy(env)
  converge(env)

  value(alpha) |> expect.to_equal(4)
  // The room's checkpoint is the room's state — not the state the relay
  // held before a peer's edit crossed the mesh.
  relay_fake.attested(hub_of(env), room)
  |> expect.to_equal(crdt_js.digest(alpha.document))
  relay_fake.replayable(hub_of(env), room)
  |> list.length
  |> expect.to_equal(relay_fake.log_size(hub_of(env), room))

  // And a replica with no mesh path at all, attaching afterwards, reads
  // it back from the relay alone.
  let dave = spawn_as(env, "dave", SequencedOnly)
  converge(env)
  crdt_js.peers(dave.document) |> expect.to_equal([])
  crdt_js.effective_path(dave.document) |> expect.to_equal(Sequenced)
  value(dave) |> expect.to_equal(4)
  crdt_js.digest(dave.document)
  |> expect.to_equal(crdt_js.digest(carol.document))
  // Durability, not a second delta: one state change and one event each.
  list.length(entries(alpha.events)) |> expect.to_equal(1)
  list.length(entries(carol.events)) |> expect.to_equal(1)
}

@target(javascript)
/// The same rule for a channel a peer created, which is a merge that can
/// move a document with no event at all.
///
/// Both replicas create one in the same breath, so neither announcement
/// has been heard when the other is made: one crosses the mesh into a
/// relay-primary document, the other goes down the relay itself. A late
/// relay-only replica has to find both channels, with both edits.
pub fn a_p2p_only_channel_reaches_the_relays_durable_history_test() -> Nil {
  let env = setup(Auto)
  let alpha = spawn(env, "alpha")
  let carol = spawn_as(env, "carol", P2pOnly)
  converge(env)
  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_true()

  let assert Ok(theirs) =
    crdt_js.create_channel(carol.document, p2p.or_set_root())
  let assert Ok(ours) =
    crdt_js.create_channel(alpha.document, p2p.or_set_root())
  let assert Ok(Nil) = crdt_js.or_set_add(theirs, "tent")
  let assert Ok(Nil) = crdt_js.or_set_add(ours, "map")
  anti_entropy(env)
  converge(env)

  let dave = spawn_as(env, "dave", SequencedOnly)
  converge(env)

  crdt_js.addresses(dave.document)
  |> expect.to_equal(crdt_js.addresses(carol.document))
  let assert Ok(from_mesh) =
    crdt_js.resolve_channel(
      dave.document,
      p2p.or_set_root(),
      crdt_js.address(theirs),
    )
  crdt_js.or_set_values(from_mesh) |> expect.to_equal(Ok(["tent"]))
  let assert Ok(from_relay) =
    crdt_js.resolve_channel(
      dave.document,
      p2p.or_set_root(),
      crdt_js.address(ours),
    )
  crdt_js.or_set_values(from_relay) |> expect.to_equal(Ok(["map"]))
  crdt_js.digest(dave.document)
  |> expect.to_equal(crdt_js.digest(carol.document))
}

@target(javascript)
/// And for a `state` transfer, which is the third way a peer moves this
/// document: a replica that edited before it had any transport at all
/// brings what it holds on the handshake, as one `state` message and no
/// deltas.
pub fn a_peers_state_transfer_reaches_the_relays_durable_history_test() -> Nil {
  let env = setup(Auto)
  let alpha = spawn(env, "alpha")
  converge(env)
  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_true()

  let carol =
    spawn_offline(env, "carol", P2pOnly, fn(document) {
      let assert Ok(Nil) = crdt_js.pn_counter_update(crdt_js.root(document), 6)
      Nil
    })
  anti_entropy(env)
  converge(env)

  value(alpha) |> expect.to_equal(6)
  mesh_types(
    env,
    crdt_js.replica_id(carol.document),
    crdt_js.replica_id(alpha.document),
  )
  |> list.contains("delta")
  |> expect.to_be_false()
  relay_fake.attested(hub_of(env), room)
  |> expect.to_equal(crdt_js.digest(alpha.document))

  let dave = spawn_as(env, "dave", SequencedOnly)
  converge(env)
  value(dave) |> expect.to_equal(6)
  crdt_js.digest(dave.document)
  |> expect.to_equal(crdt_js.digest(carol.document))
}

@target(javascript)
/// A burst of peer edits is one publication per relay client, and the
/// relay's fan-out of those publications is not answered with more.
///
/// Both halves matter. A publication per merged delta would write the
/// whole document to the relay once per keystroke; a client that
/// republished what the relay had just sent it would never stop. The
/// merge that owes a publication is a *peer's*, so a relay-carried one
/// arms nothing, and the interval that coalesces the mesh's digest
/// coalesces this too.
pub fn a_mesh_burst_publishes_once_per_client_and_does_not_echo_test() -> Nil {
  let env = setup(Auto)
  let alpha = spawn(env, "alpha")
  let beta = spawn(env, "beta")
  let carol = spawn_as(env, "carol", P2pOnly)
  converge(env)
  let attached = publications(env)
  let alpha_to_carol = #(
    crdt_js.replica_id(alpha.document),
    crdt_js.replica_id(carol.document),
  )
  // The handshake's own `state` transfer, so what is counted afterwards
  // is what the burst added and not what joining the room cost.
  let handshake_states = mesh_kinds(env, alpha_to_carol, "state")

  // Four deltas from the mesh-only peer, all inside one interval.
  clap(carol, 1)
  clap(carol, 1)
  clap(carol, 1)
  clap(carol, 1)
  converge(env)

  value(alpha) |> expect.to_equal(4)
  value(beta) |> expect.to_equal(4)
  value(carol) |> expect.to_equal(4)
  // One each from the two replicas that merged the mesh, and none at all
  // in answer to the relay carrying them.
  { publications(env) - attached } |> expect.to_equal(2)

  // The publication is durable traffic, not a mesh broadcast: the peer
  // that authored the deltas is sent no more of this document than it was
  // before, and certainly not the whole of it.
  mesh_kinds(env, alpha_to_carol, "state")
  |> expect.to_equal(handshake_states)

  // Quiet room, quiet lane: nothing further is published for as long as
  // nothing changes.
  let settled = publications(env)
  list.each([250, 500, 1000], fn(delay) {
    relay_fake.advance(env.clock, delay)
    settle(env)
  })
  publications(env) |> expect.to_equal(settled)
  // And an idle relay-primary document does not re-hash itself to say so.
  let hashes = crdt_js.digest_computations(alpha.document)
  list.each([250, 500], fn(delay) {
    relay_fake.advance(env.clock, delay)
    settle(env)
  })
  crdt_js.digest_computations(alpha.document) |> expect.to_equal(hashes)

  // Two concurrent publications may leave the room's attestation for the
  // next checkpoint to settle — but the history is complete either way,
  // which is what a replica that has only ever seen the relay reads.
  let dave = spawn_as(env, "dave", SequencedOnly)
  converge(env)
  value(dave) |> expect.to_equal(4)
}

@target(javascript)
/// The durable delta itself does not go to the mesh while a healthy
/// relay is primary — the digest does. A raw peer, which records exactly
/// what it was sent, is what proves it.
pub fn a_primary_relay_sends_peers_a_digest_and_not_the_delta_test() -> Nil {
  let env = setup(Auto)
  let alpha = spawn(env, "alpha")
  let heard = transport_js.new_cell([])
  let carol = recording_peer(env, "carol", heard)
  settle(env)
  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_true()

  send_raw(
    carol,
    crdt_js.replica_id(alpha.document),
    crdt_core.encode(carol.document, crdt_core.hello_message(carol.document)),
  )
  settle(env)
  transport_js.set_cell(heard, [])

  clap(alpha, 2)
  anti_entropy(env)

  let kinds = entries(heard)
  list.contains(kinds, "digest") |> expect.to_be_true()
  list.contains(kinds, "delta") |> expect.to_be_false()

  // And when the relay is gone, the delta goes to the mesh again — with
  // no interval to wait out, because that path is not anti-entropy.
  relay_fake.stop(hub_of(env))
  settle(env)
  transport_js.set_cell(heard, [])
  clap(alpha, 1)
  settle(env)
  entries(heard) |> list.contains("delta") |> expect.to_be_true()
}

@target(javascript)
/// A relay without the lane leaves the mesh exactly as it was: `Auto`
/// carries on over WebRTC and a `P2pOnly` replica beside it converges,
/// because the path never became `Sequenced`.
pub fn an_unsupported_relay_leaves_a_mixed_room_converging_test() -> Nil {
  let env = setup(Auto)
  relay_fake.set_capability(hub_of(env), False)
  let alpha = spawn(env, "alpha")
  let carol = spawn_as(env, "carol", P2pOnly)
  converge(env)

  saw(alpha, "relayUnsupported") |> expect.to_be_true()
  crdt_js.effective_path(alpha.document) |> expect.to_equal(PeerToPeer)

  clap(alpha, 2)
  clap(carol, 5)
  converge(env)

  value(alpha) |> expect.to_equal(7)
  value(carol) |> expect.to_equal(7)
  crdt_js.digest(alpha.document)
  |> expect.to_equal(crdt_js.digest(carol.document))
  list.length(entries(alpha.events)) |> expect.to_equal(2)
  list.length(entries(carol.events)) |> expect.to_equal(2)
}

// ─────────────────────────────────────────────────────────────────────────────
// A socket that is no longer writable
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// A relay write that does not reach an open socket is not a delta that
/// disappeared. The lane is dropped, the path flips to the mesh, the
/// fallback is reported, and the delta goes to the peers — all before the
/// mutation returns.
pub fn a_write_to_a_dead_socket_falls_back_at_once_test() -> Nil {
  let env = setup(Auto)
  let alpha = spawn(env, "alpha")
  let beta = spawn(env, "beta")
  converge(env)
  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_true()

  // The socket has left OPEN and its close has not been delivered: the
  // window in which a `send` that claimed success would lose the write.
  relay_fake.set_writable(hub_of(env), False)
  clap(alpha, 4)

  crdt_js.effective_path(alpha.document) |> expect.to_equal(PeerToPeer)
  saw(alpha, "relayFallback") |> expect.to_be_true()
  entries(alpha.paths)
  |> list.filter(fn(entry) { string.starts_with(entry, "relayFallback") })
  |> expect.to_equal(["relayFallback @ p2p"])

  settle(env)
  value(beta) |> expect.to_equal(4)
  value(alpha) |> expect.to_equal(4)
  // And a reconnect was armed, exactly as a reported close would arm one.
  relay_fake.delays(env.clock) |> list.contains(250) |> expect.to_be_true()
}

@target(javascript)
/// The same rule one step earlier: a `hello` that does not reach the
/// socket ends the attachment instead of leaving the document syncing
/// against something that will never answer. `RelaySyncing` with no
/// `synced`, no publication and no retry is the one state this lane must
/// never be able to sit in.
pub fn an_attachment_write_that_fails_does_not_strand_the_lane_test() -> Nil {
  let env = setup(Auto)
  // The greeting arrives; the first thing the client writes does not.
  relay_fake.set_write_budget(hub_of(env), 0)
  let alpha = spawn(env, "alpha")
  settle(env)

  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_false()
  crdt_js.effective_path(alpha.document) |> expect.to_equal(PeerToPeer)
  saw(alpha, "relayFallback") |> expect.to_be_true()
  relay_fake.delays(env.clock) |> list.contains(250) |> expect.to_be_true()

  // And it recovers on the retry, which is what "retry" has to mean.
  relay_fake.set_write_budget(hub_of(env), -1)
  relay_fake.advance(env.clock, 250)
  converge(env)
  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_true()
  crdt_js.effective_path(alpha.document) |> expect.to_equal(Sequenced)
}

@target(javascript)
/// A publication that does not reach the socket is the same: the
/// handshake cannot be completed on a socket that cannot carry it, so it
/// is retired rather than waited on.
pub fn a_publication_that_fails_to_write_falls_back_test() -> Nil {
  let env = setup(Auto)
  // `hello` and `stateRequest` land; the `state` does not.
  relay_fake.set_write_budget(hub_of(env), 2)
  let alpha = spawn(env, "alpha")
  settle(env)

  relay_statuses(alpha) |> list.contains("relaySyncing") |> expect.to_be_true()
  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_false()
  saw(alpha, "relayFallback") |> expect.to_be_true()
  crdt_js.effective_path(alpha.document) |> expect.to_equal(PeerToPeer)
  relay_fake.delays(env.clock) |> list.contains(250) |> expect.to_be_true()
}

@target(javascript)
/// And an attestation that does not reach the socket. The state was
/// written, the echo can never come, and a lane waiting for it forever is
/// a room that never checkpoints — so this one is retired too.
pub fn an_attestation_that_fails_to_write_falls_back_test() -> Nil {
  let env = setup(Auto)
  // `hello`, `stateRequest` and `state` land; the `attest` does not.
  relay_fake.set_write_budget(hub_of(env), 3)
  let alpha = spawn(env, "alpha")
  settle(env)

  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_false()
  saw(alpha, "relayFallback") |> expect.to_be_true()
  crdt_js.effective_path(alpha.document) |> expect.to_equal(PeerToPeer)
  relay_fake.delays(env.clock) |> list.contains(250) |> expect.to_be_true()

  // The room is not damaged by it: the state that *did* arrive is still
  // in the log, and the next attachment attests it.
  relay_fake.set_write_budget(hub_of(env), -1)
  relay_fake.advance(env.clock, 250)
  converge(env)
  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_true()
  relay_fake.attested(hub_of(env), room)
  |> expect.to_equal(crdt_js.digest(alpha.document))
}

// ─────────────────────────────────────────────────────────────────────────────
// Coalesced peer digests
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// While the relay is primary, a burst of local edits owes the mesh one
/// digest, not one per edit.
///
/// A digest per mutation is worse than noisy: it reaches a peer over the
/// data channel before the relay's own copy of the same delta does, so
/// the peer answers every one of them with a `stateRequest` and the room
/// pays a full state transfer for each edit. One per tick lets the
/// durable path arrive first and still tells a peer that is genuinely
/// behind, one tick later.
pub fn peer_digests_are_coalesced_while_the_relay_is_primary_test() -> Nil {
  let env = setup(Auto)
  let alpha = spawn(env, "alpha")
  let heard = transport_js.new_cell([])
  let carol = recording_peer(env, "carol", heard)
  settle(env)
  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_true()

  send_raw(
    carol,
    crdt_js.replica_id(alpha.document),
    crdt_core.encode(carol.document, crdt_core.hello_message(carol.document)),
  )
  settle(env)
  transport_js.set_cell(heard, [])

  // A burst, authored inside one turn of the event loop. Draining the
  // mesh alone shows nothing was written to it inline.
  clap(alpha, 1)
  clap(alpha, 1)
  clap(alpha, 1)
  p2p_fake.settle(env.world)
  entries(heard) |> expect.to_equal([])

  // Nor on the next task, nor on the one after that: a zero-delay tick
  // is not an interval, and the point is to be slower than the relay's
  // own fan-out rather than faster than a microtask.
  settle(env)
  entries(heard) |> expect.to_equal([])

  // Edits from *later* tasks join the same interval.
  clap(alpha, 1)
  relay_fake.advance(env.clock, crdt_js.default_anti_entropy_ms - 1)
  settle(env)
  entries(heard) |> expect.to_equal([])

  relay_fake.advance(env.clock, 1)
  settle(env)
  entries(heard) |> expect.to_equal(["digest"])

  // The next burst gets its own, so this is coalescing and not a
  // one-shot.
  transport_js.set_cell(heard, [])
  clap(alpha, 1)
  clap(alpha, 1)
  anti_entropy(env)
  entries(heard) |> expect.to_equal(["digest"])
  value(alpha) |> expect.to_equal(6)
}

@target(javascript)
/// Sustained editing costs one digest per interval, not one per edit and
/// not one per burst. Three intervals of continuous claps, three digests.
pub fn sustained_edits_cost_one_digest_per_interval_test() -> Nil {
  let env = setup(Auto)
  let alpha = spawn(env, "alpha")
  let heard = transport_js.new_cell([])
  let carol = recording_peer(env, "carol", heard)
  settle(env)
  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_true()
  send_raw(
    carol,
    crdt_js.replica_id(alpha.document),
    crdt_core.encode(carol.document, crdt_core.hello_message(carol.document)),
  )
  settle(env)
  transport_js.set_cell(heard, [])

  // Half an interval of editing, over and over, for three intervals.
  list.each([1, 2, 3, 4, 5, 6], fn(_step) {
    clap(alpha, 1)
    settle(env)
    relay_fake.advance(env.clock, crdt_js.default_anti_entropy_ms / 2)
    settle(env)
  })

  entries(heard) |> expect.to_equal(["digest", "digest", "digest"])
  value(alpha) |> expect.to_equal(6)
}

@target(javascript)
/// The reason the interval exists, asserted from both sides.
///
/// While the relay is primary the delta goes to the relay, which fans it
/// out to every other attached replica. The digest that follows must
/// arrive *after* that fan-out: a peer that already merged the delta
/// answers a matching digest with nothing at all, and a peer that has not
/// answers it with a `stateRequest` and pays for a whole `state` message.
pub fn a_digest_that_follows_the_relays_fan_out_costs_nothing_test() -> Nil {
  let env = setup(Auto)
  let alpha = spawn(env, "alpha")
  let beta = spawn(env, "beta")
  converge(env)
  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_true()
  crdt_js.relay_is_primary(beta.document) |> expect.to_be_true()

  // The ordinary case: the relay's copy lands first, because settling the
  // room is what a quarter of a second is long enough for.
  clap(alpha, 3)
  settle(env)
  value(beta) |> expect.to_equal(3)
  let asks = fn() {
    mesh_types(
      env,
      crdt_js.replica_id(beta.document),
      crdt_js.replica_id(alpha.document),
    )
    |> list.filter(fn(kind) { kind == "stateRequest" })
    |> list.length
  }
  let transfers = fn() {
    mesh_types(
      env,
      crdt_js.replica_id(alpha.document),
      crdt_js.replica_id(beta.document),
    )
    |> list.filter(fn(kind) { kind == "state" })
    |> list.length
  }
  let quiet = asks()
  let carried = transfers()
  anti_entropy(env)

  // The digest arrived, and cost nothing: no `stateRequest` back, and no
  // whole-state transfer out.
  mesh_types(
    env,
    crdt_js.replica_id(alpha.document),
    crdt_js.replica_id(beta.document),
  )
  |> list.contains("digest")
  |> expect.to_be_true()
  asks() |> expect.to_equal(quiet)
  transfers() |> expect.to_equal(carried)
  crdt_js.digest(alpha.document)
  |> expect.to_equal(crdt_js.digest(beta.document))

  // And the case the interval exists to avoid, forced by holding the
  // relay's fan-out back until after the timer: the peer is behind, so it
  // asks — which is exactly the whole-state transfer a per-mutation
  // digest would buy on every single edit.
  clap(alpha, 1)
  relay_fake.advance(env.clock, crdt_js.default_anti_entropy_ms)
  p2p_fake.settle(env.world)
  { asks() > quiet } |> expect.to_be_true()
  converge(env)
  { transfers() > carried } |> expect.to_be_true()
  value(beta) |> expect.to_equal(4)
}

@target(javascript)
/// The interval is a configuration value, not a constant in disguise: a
/// deployment that wants a different one gets a different one, and the
/// digest arrives on *its* schedule.
pub fn the_anti_entropy_interval_is_injectable_test() -> Nil {
  let env = Setup(..setup(Auto), anti_entropy_ms: 40)
  let alpha = spawn(env, "alpha")
  let heard = transport_js.new_cell([])
  let carol = recording_peer(env, "carol", heard)
  settle(env)
  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_true()
  send_raw(
    carol,
    crdt_js.replica_id(alpha.document),
    crdt_core.encode(carol.document, crdt_core.hello_message(carol.document)),
  )
  settle(env)
  transport_js.set_cell(heard, [])

  clap(alpha, 1)
  relay_fake.advance(env.clock, 39)
  settle(env)
  entries(heard) |> expect.to_equal([])
  relay_fake.advance(env.clock, 1)
  settle(env)
  entries(heard) |> expect.to_equal(["digest"])
  // And the default is the documented quarter of a second.
  crdt_js.default_anti_entropy_ms |> expect.to_equal(250)
}

@target(javascript)
/// A lane that drops flushes the digest it owed the mesh, exactly once,
/// and disarms the interval rather than letting it fire against a path
/// that has changed.
///
/// The `stateRequest` of failover repair is not a substitute for it: it
/// *pulls* each peer's state and tells the peer nothing, so a peer that
/// never saw the relay-only edits would answer with a state that does not
/// contain them, merge nothing, and stay behind. The digest is what makes
/// it ask.
pub fn a_fallback_flushes_the_digest_it_owed_test() -> Nil {
  let env = setup(Auto)
  let alpha = spawn(env, "alpha")
  let heard = transport_js.new_cell([])
  let carol = recording_peer(env, "carol", heard)
  settle(env)
  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_true()
  send_raw(
    carol,
    crdt_js.replica_id(alpha.document),
    crdt_core.encode(carol.document, crdt_core.hello_message(carol.document)),
  )
  settle(env)

  // An edit inside an armed anti-entropy window: the relay has it, the
  // peers do not, and the digest that would have told them is pending.
  clap(alpha, 1)
  settle(env)
  transport_js.set_cell(heard, [])

  relay_fake.stop(hub_of(env))
  settle(env)
  crdt_js.effective_path(alpha.document) |> expect.to_equal(PeerToPeer)
  // One digest, and the repair, both immediately.
  entries(heard)
  |> list.filter(fn(kind) { kind == "digest" })
  |> expect.to_equal(["digest"])
  entries(heard) |> list.contains("stateRequest") |> expect.to_be_true()

  // And the timer that was armed never fires: one final push, not two.
  transport_js.set_cell(heard, [])
  relay_fake.advance(env.clock, crdt_js.default_anti_entropy_ms * 4)
  p2p_fake.settle(env.world)
  entries(heard) |> list.contains("digest") |> expect.to_be_false()
}

@target(javascript)
/// A fallback with nothing owed says nothing extra: the digest is the
/// window's, not a fallback ritual.
pub fn a_fallback_with_a_clean_window_sends_no_digest_test() -> Nil {
  let env = setup(Auto)
  let alpha = spawn(env, "alpha")
  let heard = transport_js.new_cell([])
  let carol = recording_peer(env, "carol", heard)
  settle(env)
  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_true()
  send_raw(
    carol,
    crdt_js.replica_id(alpha.document),
    crdt_core.encode(carol.document, crdt_core.hello_message(carol.document)),
  )
  settle(env)

  // The edit's window closes on its own, so nothing is outstanding.
  clap(alpha, 1)
  anti_entropy(env)
  transport_js.set_cell(heard, [])

  relay_fake.stop(hub_of(env))
  settle(env)
  entries(heard) |> list.contains("digest") |> expect.to_be_false()
  entries(heard) |> list.contains("stateRequest") |> expect.to_be_true()
}

@target(javascript)
/// A closed document leaves no timer behind, armed or otherwise.
pub fn closing_cancels_the_armed_digest_test() -> Nil {
  let env = setup(Auto)
  let alpha = spawn(env, "alpha")
  settle(env)
  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_true()

  clap(alpha, 1)
  let armed = relay_fake.armed(env.clock)
  { armed > 0 } |> expect.to_be_true()
  crdt_js.close(alpha.connection)
  { relay_fake.armed(env.clock) < armed } |> expect.to_be_true()
  relay_fake.advance(env.clock, crdt_js.default_anti_entropy_ms * 4)
  settle(env)
}

@target(javascript)
/// Coalescing is not deferral of the repair. A relay that drops still
/// asks its peers for state immediately, in the same breath as the
/// fallback — no tick, no timer, no waiting.
pub fn failover_repair_is_not_coalesced_test() -> Nil {
  let env = setup(Auto)
  let alpha = spawn(env, "alpha")
  let heard = transport_js.new_cell([])
  let carol = recording_peer(env, "carol", heard)
  settle(env)
  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_true()
  send_raw(
    carol,
    crdt_js.replica_id(alpha.document),
    crdt_core.encode(carol.document, crdt_core.hello_message(carol.document)),
  )
  settle(env)
  transport_js.set_cell(heard, [])

  relay_fake.set_writable(hub_of(env), False)
  clap(alpha, 4)

  // The mesh alone, with no tick of the clock at all: the state request
  // and the delta are already queued on it.
  p2p_fake.settle(env.world)
  entries(heard) |> list.contains("stateRequest") |> expect.to_be_true()
  entries(heard) |> list.contains("delta") |> expect.to_be_true()
}

@target(javascript)
/// Every relay connection attempt is reported, not only the first.
pub fn every_relay_attempt_reports_itself_test() -> Nil {
  let env = setup(Auto)
  relay_fake.stop(hub_of(env))
  let alpha = spawn(env, "alpha")
  settle(env)

  list.each([250, 500], fn(delay) {
    relay_fake.advance(env.clock, delay)
    settle(env)
  })

  let attempts =
    entries(alpha.statuses)
    |> list.filter(fn(entry) { entry == "relayConnecting" })
  list.length(attempts) |> expect.to_equal(3)
  let retries =
    entries(alpha.statuses)
    |> list.filter(fn(entry) { string.starts_with(entry, "relayRetry") })
  list.length(retries) |> expect.to_equal(3)
}

@target(javascript)
/// A raw peer that records the message type of everything it is sent.
/// Its own document never merges anything: what is being asserted is
/// what crossed the data channel, not what it made of it.
fn recording_peer(
  env: Setup,
  peer_id: String,
  heard: Cell(List(String)),
) -> RawPeer {
  let assert Ok(document) =
    crdt_core.new(crdt_core.config(
      room: room,
      compatibility: tag,
      replica: peer_id,
      session: "session-" <> peer_id,
      root: channel.InitPnCounter,
    ))
  let assert Ok(transport) =
    p2p_transport_js.start_with_rtc(
      room: room,
      peer_id: peer_id,
      signaling: hub_signaling(env.signals),
      ice_servers: [],
      callbacks: Callbacks(
        on_peer_open: fn(_peer) { Nil },
        on_peer_close: fn(_peer) { Nil },
        on_document: fn(_peer, payload) {
          push(heard, case crdt_relay.decode_client(payload) {
            Ok(crdt_relay.Document(_, _, _, _, message)) ->
              crdt_relay.message_kind_to_string(message)
            Ok(crdt_relay.Control(..)) | Error(_) -> "opaque"
          })
        },
        on_status: fn(_status) { Nil },
        on_error: fn(_error) { Nil },
      ),
      rtc: p2p_fake.rtc(env.world, peer_id),
    )
  RawPeer(transport: transport, document: document)
}

// ─────────────────────────────────────────────────────────────────────────────
// An outage converges a mesh-only peer, whatever the kernel
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// One document of any root kind, attached with the same mesh and relay
/// seams the counter members use. Only the document and its connection
/// are handed back: these tests read a kernel's own value and its digest,
/// and nothing else.
fn spawn_kind(
  env: Setup,
  label: String,
  policy: crdt_js.TransportPolicy,
  kind: p2p.CrdtKind(root),
) -> #(CrdtDocument(root), CrdtConnection) {
  let base =
    crdt_js.config(
      room_id: room,
      replica_label: label,
      compatibility_tag: tag,
      root: kind,
      signaling: hub_signaling(env.signals),
    )
    |> crdt_js.with_transport_policy(policy)
    |> crdt_js.with_scheduler(relay_fake.scheduler(env.clock))
    |> crdt_js.with_anti_entropy_interval_ms(env.anti_entropy_ms)
  let config = case env.relay {
    None -> base
    Some(hub) ->
      crdt_js.with_sequencer(
        base,
        crdt_js.sequencer("ws://relay.test/")
          |> crdt_js.with_relay_driver(relay_fake.driver(hub))
          |> crdt_js.with_readiness_deadline_ms(env.deadline_ms),
      )
  }
  let assert Ok(document) = crdt_js.new_document(config)
  let connection =
    crdt_js.attach_with_rtc(
      document,
      on_ready: fn(_outcome) { Nil },
      on_status: fn(_status) { Nil },
      rtc: p2p_fake.rtc(env.world, crdt_js.replica_id(document)),
    )
  #(document, connection)
}

@target(javascript)
/// An OR-set edit authored while the relay is primary reaches a mesh-only
/// peer the moment the relay drops.
///
/// The delta went to the relay and not to the mesh, and the digest that
/// would have told the peer is still inside its anti-entropy window — so
/// without the fallback flushing that digest the peer would answer the
/// failover `stateRequest` with a state that does not contain the edit,
/// merge nothing, and stay behind until the room was edited again. No
/// clock is advanced here past the settling of the mesh: convergence is
/// the fallback's, not the interval's.
pub fn an_or_set_peer_converges_when_the_relay_drops_test() -> Nil {
  let env = setup(Auto)
  let #(alpha, _) = spawn_kind(env, "alpha", Auto, p2p.or_set_root())
  let #(carol, _) = spawn_kind(env, "carol", P2pOnly, p2p.or_set_root())
  settle(env)
  crdt_js.relay_is_primary(alpha) |> expect.to_be_true()

  let assert Ok(Nil) = crdt_js.or_set_add(crdt_js.root(alpha), "tent")
  settle(env)
  crdt_js.or_set_values(crdt_js.root(carol)) |> expect.to_equal(Ok([]))

  relay_fake.stop(hub_of(env))
  settle(env)
  crdt_js.or_set_values(crdt_js.root(carol)) |> expect.to_equal(Ok(["tent"]))
  crdt_js.digest(carol) |> expect.to_equal(crdt_js.digest(alpha))
}

@target(javascript)
/// The same for a sequence, whose deltas carry positions rather than
/// elements: the peer that never saw them rebuilds from the state it asks
/// for, and the two agree.
pub fn a_sequence_peer_converges_when_the_relay_drops_test() -> Nil {
  let env = setup(Auto)
  let #(alpha, _) = spawn_kind(env, "alpha", Auto, p2p.sequence_root())
  let #(carol, _) = spawn_kind(env, "carol", P2pOnly, p2p.sequence_root())
  settle(env)
  crdt_js.relay_is_primary(alpha) |> expect.to_be_true()

  let assert Ok(Nil) =
    crdt_js.sequence_insert(crdt_js.root(alpha), 0, json.string("harbour"))
  let assert Ok(Nil) =
    crdt_js.sequence_insert(crdt_js.root(alpha), 1, json.string("ferry"))
  settle(env)
  let assert Ok(behind) = crdt_js.sequence_values(crdt_js.root(carol))
  list.length(behind) |> expect.to_equal(0)

  relay_fake.stop(hub_of(env))
  settle(env)
  let assert Ok(caught_up) = crdt_js.sequence_values(crdt_js.root(carol))
  list.length(caught_up) |> expect.to_equal(2)
  crdt_js.digest(carol) |> expect.to_equal(crdt_js.digest(alpha))
}

@target(javascript)
/// And for text, where a peer that misses a delta and then merges a
/// state has to end up with the same string rather than a plausible one.
pub fn a_text_peer_converges_when_the_relay_drops_test() -> Nil {
  let env = setup(Auto)
  let #(alpha, _) = spawn_kind(env, "alpha", Auto, p2p.text_root())
  let #(carol, _) = spawn_kind(env, "carol", P2pOnly, p2p.text_root())
  settle(env)
  crdt_js.relay_is_primary(alpha) |> expect.to_be_true()

  let assert Ok(Nil) = crdt_js.text_append(crdt_js.root(alpha), "harbour")
  settle(env)
  crdt_js.text_value(crdt_js.root(carol)) |> expect.to_equal(Ok(""))

  relay_fake.stop(hub_of(env))
  settle(env)
  crdt_js.text_value(crdt_js.root(carol)) |> expect.to_equal(Ok("harbour"))
  crdt_js.digest(carol) |> expect.to_equal(crdt_js.digest(alpha))
}

// ─────────────────────────────────────────────────────────────────────────────
// Checkpoint pressure: an honest session past the hard bound
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// An ordinary editing session that outruns the relay's hard log bound.
///
/// A thousand mutations is an afternoon, not an attack, and a room that
/// simply refused the next one would be cutting off exactly the client it
/// exists to serve. So before the bound the relay *asks*: a typed control
/// request to the clients that said they understand one, answered by
/// publishing the merged state and attesting it, which compacts the
/// room's ordinary valid history down to that one record.
///
/// Nothing is refused, nothing is lost, and the room never reaches the
/// bound at all.
pub fn an_ordinary_session_past_the_bound_checkpoints_and_continues_test() -> Nil {
  let mutations = crdt_relay.max_room_records + 200
  let env = setup(SequencedOnly)
  let hub = hub_of(env)
  let alpha = spawn(env, "alpha")
  converge(env)
  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_true()
  relay_fake.supports_checkpoints(hub, 1) |> expect.to_be_true()

  claps(env, alpha, mutations)
  converge(env)

  // The room asked, the client answered, and the log came back down.
  { relay_fake.checkpoint_requests(hub, room) >= 1 } |> expect.to_be_true()
  saw(alpha, "relayCheckpointRequested") |> expect.to_be_true()
  saw(alpha, "relayCheckpointed") |> expect.to_be_true()
  relay_fake.checkpoints_pending(hub, room) |> expect.to_equal([])
  { relay_fake.log_size(hub, room) < crdt_relay.max_room_records }
  |> expect.to_be_true()
  { relay_fake.checkpoint_order(hub, room) > 0 } |> expect.to_be_true()

  // Nothing was refused and nothing was lost: the session ran straight
  // through the bound without noticing it.
  saw(alpha, "relayFallback") |> expect.to_be_false()
  saw(alpha, "relayFailed") |> expect.to_be_false()
  crdt_js.relay_is_primary(alpha.document) |> expect.to_be_true()
  value(alpha) |> expect.to_equal(mutations)

  // A restart replays what the checkpoints wrote, and a later client sees
  // every one of the edits they compacted.
  relay_fake.stop(hub)
  converge(env)
  relay_fake.restart(hub)
  relay_fake.advance(env.clock, 5000)
  converge(env)
  { relay_fake.log_size(hub, room) < crdt_relay.max_room_records }
  |> expect.to_be_true()
  value(alpha) |> expect.to_equal(mutations)

  let beta = spawn(env, "beta")
  converge(env)
  entries(beta.readies) |> expect.to_equal(["ok"])
  value(beta) |> expect.to_equal(mutations)
  crdt_js.digest(beta.document)
  |> expect.to_equal(crdt_js.digest(alpha.document))
}

@target(javascript)
fn claps(env: Setup, member: Member, times: Int) -> Nil {
  case times <= 0 {
    True -> Nil
    False -> {
      clap(member, 1)
      settle(env)
      claps(env, member, times - 1)
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Capacity recovery: a valid room already at the hard bound
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// `needed` encoded PnCounter increments from one seeder replica, each a
/// distinct operation a fresh client will *merge*. This is the valid content
/// that makes a full room a *recoverable* one rather than a wedged one:
/// there is nothing here to skip, so the drain-by-skip path that rescues
/// an unmergeable room never fires, and a checkpoint is the only way down.
fn valid_deltas(
  document: crdt_core.Document,
  needed: Int,
  carried: List(String),
) -> List(String) {
  case list.length(carried) >= needed {
    True -> list.reverse(carried) |> list.take(needed)
    False -> {
      let assert Ok(#(next, outcome)) =
        crdt_core.edit(
          document,
          crdt_wire.root_address,
          channel.PnCounterEdit(1),
        )
      let more =
        list.map(outcome.broadcast, fn(message) {
          crdt_core.encode(next, message)
        })
      valid_deltas(next, needed, list.append(list.reverse(more), carried))
    }
  }
}

@target(javascript)
/// `count` durable traffic records, orders `1..count`, that a fresh
/// client will merge into a value of `count` — the log a relay reads back
/// off disk when it restarts onto a room that was already full of valid
/// history, or simply the state of a room that filled before this client
/// arrived.
fn valid_lines(count: Int) -> List(String) {
  let assert Ok(seeder) =
    crdt_core.new(crdt_core.config(
      room: room,
      compatibility: tag,
      replica: "seeder",
      session: "seeder-session",
      root: p2p.kind_init(p2p.pn_counter_root()),
    ))
  valid_deltas(seeder, count, [])
  |> list.index_map(fn(envelope, index) {
    crdt_relay.record_to_string(crdt_relay.TrafficRecord(
      index + 1,
      "seeder-session",
      envelope,
    ))
  })
}

@target(javascript)
/// The P2P6 capacity-recovery gate, end to end.
///
/// A relay comes up on a *valid* log already at its hard bound: every
/// record is mergeable, so the drain-by-skip path that rescues an
/// unmergeable room never fires, and the room can never grow to ask for
/// a checkpoint from an append.
///
/// What drains it is the ordinary attach flow: the client declares
/// support, merges the whole room, publishes its merged state — admitted
/// at the bound *because* it declared support — and its attestation
/// compacts the room back under the bound, with nothing skipped and not
/// one of the seeded increments lost. `SequencedOnly` has no other lane
/// to be ready on, so coming up primary at all is the proof it
/// recovered.
pub fn a_valid_full_room_recovers_for_a_late_client_test() -> Nil {
  let count = crdt_relay.max_room_records
  let clock = relay_fake.new_clock()
  let hub = relay_fake.new_hub()
  relay_fake.seed(hub, room, valid_lines(count))
  relay_fake.log_size(hub, room) |> expect.to_equal(count)

  let env =
    Setup(
      world: p2p_fake.new_world(),
      signals: new_signal_hub(),
      relay: Some(hub),
      clock: clock,
      policy: SequencedOnly,
      deadline_ms: crdt_js.default_readiness_deadline_ms,
      anti_entropy_ms: crdt_js.default_anti_entropy_ms,
    )

  let honest = spawn(env, "honest")
  converge(env)

  // It came up on the relay, which under `SequencedOnly` it could not do
  // at all if the room had not drained: no reconnect-loop, no deadline.
  entries(honest.readies) |> expect.to_equal(["ok"])
  crdt_js.relay_is_primary(honest.document) |> expect.to_be_true()

  // The client published and attested, and the log came back down under
  // the bound with nothing owing and a checkpoint named.
  relay_fake.checkpoints_pending(hub, room) |> expect.to_equal([])
  { relay_fake.log_size(hub, room) < count } |> expect.to_be_true()
  { relay_fake.checkpoint_order(hub, room) > 0 } |> expect.to_be_true()

  // Nothing was refused and nothing was lost: every seeded increment is
  // in the merged value, and the lane never fell back or failed.
  saw(honest, "relayFallback") |> expect.to_be_false()
  saw(honest, "relayFailed") |> expect.to_be_false()
  value(honest) |> expect.to_equal(count)

  // Editing continues on the same connection, no reconnect: an ordinary
  // clap lands and the value moves on from the recovered total.
  clap(honest, 3)
  converge(env)
  value(honest) |> expect.to_equal(count + 3)
  crdt_js.relay_is_primary(honest.document) |> expect.to_be_true()

  // And it survives a restart: the compacted log replays, and a second
  // late client attaches to the same room and agrees on value and digest.
  relay_fake.stop(hub)
  converge(env)
  relay_fake.restart(hub)
  relay_fake.advance(clock, 5000)
  converge(env)
  crdt_js.relay_is_primary(honest.document) |> expect.to_be_true()
  value(honest) |> expect.to_equal(count + 3)
  { relay_fake.log_size(hub, room) < count } |> expect.to_be_true()

  let late = spawn(env, "late")
  converge(env)
  entries(late.readies) |> expect.to_equal(["ok"])
  crdt_js.relay_is_primary(late.document) |> expect.to_be_true()
  value(late) |> expect.to_equal(count + 3)
  crdt_js.digest(late.document)
  |> expect.to_equal(crdt_js.digest(honest.document))
}
