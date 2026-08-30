//// Deterministic tests for the public CRDT facade.
////
//// Two seams make this possible without a browser: `crdt_js.attach_with_rtc`
//// takes the same fake `RTCPeerConnection` mesh the transport tests use,
//// and signaling is an application-supplied adapter. The hub below is
//// deliberately *synchronous* — it announces a room's membership from
//// inside `join`, the way an in-page or already-connected adapter does —
//// because that is the case where a late joiner has to wait for a `state`
//// transfer before it is ready. The asynchronous case, where the roster
//// arrives after `join` returned, is covered too: it is what
//// `crdt_signaling_js` does over a real socket.
////
//// Peers that are not facades are built straight on
//// `p2p_transport_js` and speak raw `crdt_wire`. That is how the trust
//// boundary is tested: a peer that skips its `hello`, forges a sender, or
//// repeats a delta is not something the facade can be made to do to
//// itself.

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
  type CrdtConnection, type CrdtDocument, type Handle, type Status,
}
@target(javascript)
import watershed/crdt_wire
@target(javascript)
import watershed/g_set_kernel
@target(javascript)
import watershed/or_map_kernel
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
import watershed/relay_fake
@target(javascript)
import watershed/schema
@target(javascript)
import watershed/sequence_kernel
@target(javascript)
import watershed/text_kernel
@target(javascript)
import watershed/transport_js.{type Cell}

@target(javascript)
const room = "trip-planning"

@target(javascript)
const tag = "clap-counter/v1"

// ─────────────────────────────────────────────────────────────────────────────
// A synchronous signaling hub
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
type Hub {
  Hub(cell: Cell(List(#(String, fn(Signal) -> Nil))))
}

@target(javascript)
fn new_hub() -> Hub {
  Hub(cell: transport_js.new_cell([]))
}

@target(javascript)
/// Announces membership in both directions from inside `join`: the
/// newcomer gets the room's complete roster, and every member is told
/// about the newcomer. This is the synchronous shape — an in-page or
/// already-connected adapter — so the transport knows the room before
/// `start` returns.
fn hub_signaling(hub: Hub) -> Signaling {
  Signaling(
    join: fn(joined_room, peer_id, on_signal) {
      let existing = transport_js.get_cell(hub.cell)
      transport_js.set_cell(hub.cell, [#(peer_id, on_signal), ..existing])
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
        list.find(transport_js.get_cell(hub.cell), fn(member) { member.0 == to })
      {
        Ok(member) -> member.1(Message(from: from, payload: payload))
        Error(Nil) -> Nil
      }
    },
    leave: fn(session) {
      let peer_id = p2p_transport_js.session_peer_id(session)
      let remaining =
        list.filter(transport_js.get_cell(hub.cell), fn(member) {
          member.0 != peer_id
        })
      transport_js.set_cell(hub.cell, remaining)
      list.each(remaining, fn(member) { member.1(PeerLeft(peer_id)) })
    },
  )
}

@target(javascript)
/// A signaling adapter that can refuse `join` synchronously before
/// delegating to the live hub.
fn gated_signaling(base: Signaling, gate: Cell(Option(String))) -> Signaling {
  Signaling(
    join: fn(joined_room, peer_id, on_signal) {
      case transport_js.get_cell(gate) {
        Some(detail) -> Error(detail)
        None -> base.join(joined_room, peer_id, on_signal)
      }
    },
    send: base.send,
    leave: base.leave,
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Members
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
type Member(root) {
  Member(
    document: CrdtDocument(root),
    connection: CrdtConnection,
    statuses: Cell(List(String)),
    readies: Cell(List(String)),
  )
}

@target(javascript)
fn spawn(
  world: p2p_fake.World,
  signaling: Signaling,
  label: String,
  kind: p2p.CrdtKind(root),
  compatibility: String,
) -> Member(root) {
  let assert Ok(document) =
    crdt_js.new_document(crdt_js.config(
      room_id: room,
      replica_label: label,
      compatibility_tag: compatibility,
      root: kind,
      signaling: signaling,
    ))
  let statuses = transport_js.new_cell([])
  let readies = transport_js.new_cell([])
  let connection =
    crdt_js.attach_with_rtc(
      document,
      on_ready: fn(outcome) {
        push(readies, case outcome {
          Ok(_) -> "ok"
          Error(error) -> "error " <> crdt_js.describe_error(error)
        })
      },
      on_status: fn(status) { push(statuses, render(status)) },
      rtc: p2p_fake.rtc(world, crdt_js.replica_id(document)),
    )
  Member(
    document: document,
    connection: connection,
    statuses: statuses,
    readies: readies,
  )
}

@target(javascript)
/// A `spawn` whose mesh anti-entropy digest is measured on an injected
/// clock instead of `setTimeout`, so a test can step the interval and
/// watch a partition heal deterministically. Every synced member shares
/// one clock, so `relay_fake.advance` moves the whole mesh at once.
fn spawn_synced(
  world: p2p_fake.World,
  signaling: Signaling,
  label: String,
  kind: p2p.CrdtKind(root),
  compatibility: String,
  clock: relay_fake.Clock,
) -> Member(root) {
  let assert Ok(document) =
    crdt_js.new_document(
      crdt_js.config(
        room_id: room,
        replica_label: label,
        compatibility_tag: compatibility,
        root: kind,
        signaling: signaling,
      )
      |> crdt_js.with_scheduler(relay_fake.scheduler(clock)),
    )
  let statuses = transport_js.new_cell([])
  let readies = transport_js.new_cell([])
  let connection =
    crdt_js.attach_with_rtc(
      document,
      on_ready: fn(outcome) {
        push(readies, case outcome {
          Ok(_) -> "ok"
          Error(error) -> "error " <> crdt_js.describe_error(error)
        })
      },
      on_status: fn(status) { push(statuses, render(status)) },
      rtc: p2p_fake.rtc(world, crdt_js.replica_id(document)),
    )
  Member(
    document: document,
    connection: connection,
    statuses: statuses,
    readies: readies,
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
/// Rendered by hand rather than with `string.inspect`, so an assertion
/// pins the status a document reported and not the compiler's current
/// spelling of a record.
fn render(status: Status) -> String {
  case status {
    crdt_js.Transport(inner) -> "transport " <> string.inspect(inner)
    crdt_js.TransportError(error) ->
      "transportError " <> crdt_js.describe_error(error)
    crdt_js.Joined(joined_room, _replica) -> "joined " <> joined_room
    crdt_js.RosterKnown(peers) ->
      "rosterKnown [" <> string.join(list.map(peers, label_of), ",") <> "]"
    crdt_js.AwaitingState(peer) -> "awaitingState " <> label_of(peer)
    crdt_js.Ready -> "ready"
    crdt_js.PeerReady(peer) -> "peerReady " <> label_of(peer)
    crdt_js.PeerGone(peer) -> "peerGone " <> label_of(peer)
    crdt_js.PeerRejected(peer, error) ->
      "peerRejected " <> label_of(peer) <> " " <> crdt_js.describe_error(error)
    crdt_js.StateMerged(peer, channels) ->
      "stateMerged " <> label_of(peer) <> " " <> int.to_string(channels)
    crdt_js.RejectedByPeer(peer, reason, detail) ->
      "rejectedByPeer " <> label_of(peer) <> " " <> reason <> " " <> detail
    crdt_js.Failed(error) -> "failed " <> crdt_js.describe_error(error)
    crdt_js.SubscriberFailed(address, detail) ->
      "subscriberFailed " <> address <> " " <> detail
    crdt_js.RelayConnecting(url) -> "relayConnecting " <> url
    crdt_js.RelayUnsupported(detail) -> "relayUnsupported " <> detail
    crdt_js.RelaySyncingStatus -> "relaySyncing"
    crdt_js.RelayRecovering -> "relayRecovering"
    crdt_js.RelayPrimary(_digest) -> "relayPrimary"
    crdt_js.RelayCheckpointRequested -> "relayCheckpointRequested"
    crdt_js.RelayCheckpointed(_digest) -> "relayCheckpointed"
    crdt_js.RelayFallback(detail) -> "relayFallback " <> detail
    crdt_js.RelayRetry(delay) -> "relayRetry " <> int.to_string(delay)
    crdt_js.RelayRejected(from, error) ->
      "relayRejected " <> label_of(from) <> " " <> crdt_js.describe_error(error)
    crdt_js.RelayFailed(error) ->
      "relayFailed " <> crdt_js.describe_error(error)
  }
}

@target(javascript)
/// A replica id is `label-<uuid>`; tests care about the label.
fn label_of(replica: String) -> String {
  case string.split(replica, "-") {
    [label, ..] -> label
    [] -> replica
  }
}

@target(javascript)
fn tagged(cell: Cell(List(String)), prefix: String) -> List(String) {
  entries(cell) |> list.filter(fn(entry) { string.starts_with(entry, prefix) })
}

@target(javascript)
fn saw(cell: Cell(List(String)), fragment: String) -> Bool {
  list.any(entries(cell), fn(entry) { string.contains(entry, fragment) })
}

// ─────────────────────────────────────────────────────────────────────────────
// Configuration and root typing
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn the_root_is_the_configured_kind_test() -> Nil {
  let world = p2p_fake.new_world()
  let alpha =
    spawn(world, hub_signaling(new_hub()), "alpha", p2p.pn_counter_root(), tag)

  let root = crdt_js.root(alpha.document)
  crdt_js.address(root) |> expect.to_equal(crdt_wire.root_address)
  crdt_js.pn_counter_value(root) |> expect.to_equal(Ok(0))
  crdt_js.addresses(alpha.document) |> expect.to_equal(["root"])
  crdt_js.room(alpha.document) |> expect.to_equal(room)
}

@target(javascript)
/// The label is for people; the identity that authors writes is not it.
pub fn authorship_identity_is_label_plus_a_session_id_test() -> Nil {
  let world = p2p_fake.new_world()
  let hub = hub_signaling(new_hub())
  let one = spawn(world, hub, "alpha", p2p.pn_counter_root(), tag)
  let two = spawn(world, hub, "alpha", p2p.pn_counter_root(), tag)

  crdt_js.replica_label(one.document) |> expect.to_equal("alpha")
  crdt_js.replica_label(two.document) |> expect.to_equal("alpha")
  { crdt_js.replica_id(one.document) != crdt_js.replica_id(two.document) }
  |> expect.to_be_true()
  { string.starts_with(crdt_js.replica_id(one.document), "alpha-") }
  |> expect.to_be_true()
}

@target(javascript)
pub fn a_label_that_cannot_be_a_replica_id_is_refused_test() -> Nil {
  let world = p2p_fake.new_world()
  let readies = transport_js.new_cell([])
  let statuses = transport_js.new_cell([])
  let _ =
    crdt_js.connect(
      crdt_js.config(
        room_id: room,
        replica_label: "alpha:beta",
        compatibility_tag: tag,
        root: p2p.pn_counter_root(),
        signaling: hub_signaling(new_hub()),
      ),
      on_ready: fn(outcome) {
        push(readies, case outcome {
          Ok(_) -> "ok"
          Error(error) -> "error " <> crdt_js.describe_error(error)
        })
      },
      on_status: fn(status) { push(statuses, render(status)) },
    )
  p2p_fake.settle(world)

  entries(readies)
  |> expect.to_equal([
    "error invalidEnvelope · alpha:beta-"
    <> replica_suffix(entries(readies))
    <> ": replica id must be non-empty and free of ':'",
  ])
}

@target(javascript)
/// The session id in the reported replica is random; read it back out of
/// the message rather than pretending to know it.
fn replica_suffix(reported: List(String)) -> String {
  case reported {
    [entry, ..] ->
      case string.split(entry, "alpha:beta-") {
        [_, rest] ->
          case string.split(rest, ":") {
            [suffix, ..] -> suffix
            [] -> ""
          }
        _ -> ""
      }
    [] -> ""
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Readiness and bootstrap
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn a_lone_replica_is_ready_before_connect_returns_test() -> Nil {
  let world = p2p_fake.new_world()
  let alpha =
    spawn(world, hub_signaling(new_hub()), "alpha", p2p.pn_counter_root(), tag)

  // No settle: readiness did not wait for the event queue, let alone a
  // sequencer. The roster came from inside `join`, and it was empty.
  entries(alpha.readies) |> expect.to_equal(["ok"])
  crdt_js.readiness(alpha.document) |> expect.to_equal(Some(Ok(Nil)))
  entries(alpha.statuses)
  |> list.filter(fn(entry) { !string.starts_with(entry, "transport ") })
  |> expect.to_equal(["joined " <> room, "rosterKnown []", "ready"])

  p2p_fake.settle(world)
  entries(alpha.readies) |> expect.to_equal(["ok"])
}

@target(javascript)
pub fn a_late_replica_is_ready_only_after_a_state_transfer_test() -> Nil {
  let world = p2p_fake.new_world()
  let hub = hub_signaling(new_hub())
  let alpha = spawn(world, hub, "alpha", p2p.pn_counter_root(), tag)
  let assert Ok(Nil) =
    crdt_js.pn_counter_update(crdt_js.root(alpha.document), 7)

  let beta = spawn(world, hub, "beta", p2p.pn_counter_root(), tag)
  // The room was not empty, so nothing is resolved yet.
  entries(beta.readies) |> expect.to_equal([])
  crdt_js.readiness(beta.document) |> expect.to_equal(None)

  p2p_fake.settle(world)

  entries(beta.readies) |> expect.to_equal(["ok"])
  crdt_js.pn_counter_value(crdt_js.root(beta.document))
  |> expect.to_equal(Ok(7))
  crdt_js.digest(beta.document)
  |> expect.to_equal(crdt_js.digest(alpha.document))

  // The order the bootstrap took, with the transport's own statuses
  // filtered out.
  entries(beta.statuses)
  |> list.filter(fn(entry) { !string.starts_with(entry, "transport ") })
  |> expect.to_equal([
    "joined " <> room,
    "rosterKnown [alpha]",
    "peerReady alpha",
    "awaitingState alpha",
    "stateMerged alpha 1",
    "ready",
  ])
}

@target(javascript)
/// A peer announced during `join` that vanishes before its data channel
/// ever opens still owes this replica an answer: it is now provably
/// alone in the room, and the empty root it already holds is ready.
///
/// The transport retires such a peer with a `PeerClosed` *status* and
/// never calls `on_peer_close`, so a facade that only listened to the
/// callback would leave `on_ready` unresolved forever.
pub fn a_peer_that_vanishes_before_opening_still_settles_readiness_test() -> Nil {
  let world = p2p_fake.new_world()
  let hub = hub_signaling(new_hub())
  let alpha = spawn(world, hub, "alpha", p2p.pn_counter_root(), tag)
  let beta = spawn(world, hub, "beta", p2p.pn_counter_root(), tag)
  entries(beta.readies) |> expect.to_equal([])

  // alpha leaves before either side finished negotiating.
  crdt_js.close(alpha.connection)
  p2p_fake.settle(world)

  entries(beta.readies) |> expect.to_equal(["ok"])
  crdt_js.readiness(beta.document) |> expect.to_equal(Some(Ok(Nil)))
  crdt_js.peers(beta.document) |> expect.to_equal([])
  let assert Ok(Nil) = crdt_js.pn_counter_update(crdt_js.root(beta.document), 4)
  crdt_js.pn_counter_value(crdt_js.root(beta.document))
  |> expect.to_equal(Ok(4))
}

@target(javascript)
/// The status stream and the readiness callback must never disagree: by
/// the time either observer runs, the document is ready.
pub fn readiness_is_visible_from_the_status_that_announces_it_test() -> Nil {
  let world = p2p_fake.new_world()
  let observed = transport_js.new_cell([])
  let assert Ok(document) =
    crdt_js.new_document(crdt_js.config(
      room_id: room,
      replica_label: "alpha",
      compatibility_tag: tag,
      root: p2p.pn_counter_root(),
      signaling: hub_signaling(new_hub()),
    ))
  let _ =
    crdt_js.attach_with_rtc(
      document,
      on_ready: fn(_outcome) {
        push(
          observed,
          "ready callback " <> bool(crdt_js.readiness_resolved(document)),
        )
      },
      on_status: fn(status) {
        case status {
          crdt_js.Ready ->
            push(
              observed,
              "ready status " <> bool(crdt_js.readiness_resolved(document)),
            )
          crdt_js.Transport(..)
          | crdt_js.TransportError(..)
          | crdt_js.Joined(..)
          | crdt_js.RosterKnown(..)
          | crdt_js.AwaitingState(..)
          | crdt_js.PeerReady(..)
          | crdt_js.PeerGone(..)
          | crdt_js.PeerRejected(..)
          | crdt_js.StateMerged(..)
          | crdt_js.RejectedByPeer(..)
          | crdt_js.Failed(..)
          | crdt_js.SubscriberFailed(..)
          | crdt_js.RelayConnecting(..)
          | crdt_js.RelayUnsupported(..)
          | crdt_js.RelaySyncingStatus
          | crdt_js.RelayRecovering
          | crdt_js.RelayPrimary(..)
          | crdt_js.RelayCheckpointRequested
          | crdt_js.RelayCheckpointed(..)
          | crdt_js.RelayFallback(..)
          | crdt_js.RelayRetry(..)
          | crdt_js.RelayRejected(..)
          | crdt_js.RelayFailed(..) -> Nil
        }
      },
      rtc: p2p_fake.rtc(world, crdt_js.replica_id(document)),
    )

  entries(observed)
  |> expect.to_equal(["ready status True", "ready callback True"])
}

@target(javascript)
fn bool(value: Bool) -> String {
  case value {
    True -> "True"
    False -> "False"
  }
}

@target(javascript)
/// An application callback that throws. Named for what it is so the
/// tests that use it read as intent rather than plumbing.
fn boom(_reason: String) -> Nil {
  panic as "an application callback exploded"
}

@target(javascript)
pub fn readiness_resolves_exactly_once_test() -> Nil {
  let world = p2p_fake.new_world()
  let hub = hub_signaling(new_hub())
  let alpha = spawn(world, hub, "alpha", p2p.pn_counter_root(), tag)
  let beta = spawn(world, hub, "beta", p2p.pn_counter_root(), tag)
  p2p_fake.settle(world)

  // Peers arriving, leaving, and a document closing afterwards are all
  // status, not a second readiness result.
  let gamma = spawn(world, hub, "gamma", p2p.pn_counter_root(), tag)
  p2p_fake.settle(world)
  crdt_js.close(gamma.connection)
  p2p_fake.settle(world)
  crdt_js.close(alpha.connection)
  p2p_fake.settle(world)

  entries(alpha.readies) |> expect.to_equal(["ok"])
  entries(beta.readies) |> expect.to_equal(["ok"])
  entries(gamma.readies) |> expect.to_equal(["ok"])
}

@target(javascript)
pub fn closing_before_readiness_resolves_it_once_test() -> Nil {
  let world = p2p_fake.new_world()
  let hub = hub_signaling(new_hub())
  let _alpha = spawn(world, hub, "alpha", p2p.pn_counter_root(), tag)
  let beta = spawn(world, hub, "beta", p2p.pn_counter_root(), tag)
  entries(beta.readies) |> expect.to_equal([])

  crdt_js.close(beta.connection)
  p2p_fake.settle(world)

  entries(beta.readies) |> expect.to_equal(["error documentClosed"])
}

@target(javascript)
pub fn a_signaling_failure_before_readiness_is_typed_and_final_test() -> Nil {
  let world = p2p_fake.new_world()
  p2p_fake.fail_join(world, "no signaling service")
  let alpha =
    spawn(world, p2p_fake.signaling(world), "alpha", p2p.pn_counter_root(), tag)
  p2p_fake.settle(world)

  entries(alpha.readies)
  |> expect.to_equal(["error signalingFailed · no signaling service"])
  saw(alpha.statuses, "failed signalingFailed") |> expect.to_be_true()
}

@target(javascript)
/// The case a real service produces, and the one that matters: the
/// roster arrives a round trip after `join` returned. A late joiner must
/// not be told it is ready with an empty document just because nobody
/// has been announced *yet* — it waits for the roster, and then for one
/// valid `state`.
pub fn an_asynchronous_adapter_waits_for_its_roster_before_readiness_test() -> Nil {
  let world = p2p_fake.new_world()
  let alpha =
    spawn(world, p2p_fake.signaling(world), "alpha", p2p.pn_counter_root(), tag)
  // Even alone: the roster has not arrived, so nothing is resolved.
  entries(alpha.readies) |> expect.to_equal([])
  p2p_fake.settle(world)
  entries(alpha.readies) |> expect.to_equal(["ok"])

  let assert Ok(Nil) =
    crdt_js.pn_counter_update(crdt_js.root(alpha.document), 3)

  let beta =
    spawn(world, p2p_fake.signaling(world), "beta", p2p.pn_counter_root(), tag)
  entries(beta.readies) |> expect.to_equal([])
  crdt_js.readiness(beta.document) |> expect.to_equal(None)

  p2p_fake.settle(world)

  entries(beta.readies) |> expect.to_equal(["ok"])
  // Ready *after* the merge, not before it: the value was already there
  // when the callback ran, which is what the ordering below pins down.
  crdt_js.pn_counter_value(crdt_js.root(beta.document))
  |> expect.to_equal(Ok(3))
  entries(beta.statuses)
  |> list.filter(fn(entry) { !string.starts_with(entry, "transport ") })
  |> expect.to_equal([
    "joined " <> room,
    "rosterKnown [alpha]",
    "peerReady alpha",
    "awaitingState alpha",
    "stateMerged alpha 1",
    "ready",
  ])
}

@target(javascript)
/// The same adapter, watched from the callback itself: when `on_ready`
/// runs, the room's state is already merged. This is the property the
/// two-browser gate asserts, in one process.
pub fn a_late_joiner_sees_the_merged_state_from_on_ready_test() -> Nil {
  let world = p2p_fake.new_world()
  let alpha =
    spawn(world, p2p_fake.signaling(world), "alpha", p2p.pn_counter_root(), tag)
  p2p_fake.settle(world)
  let assert Ok(Nil) =
    crdt_js.pn_counter_update(crdt_js.root(alpha.document), 5)

  let observed = transport_js.new_cell([])
  let assert Ok(document) =
    crdt_js.new_document(crdt_js.config(
      room_id: room,
      replica_label: "beta",
      compatibility_tag: tag,
      root: p2p.pn_counter_root(),
      signaling: p2p_fake.signaling(world),
    ))
  let _ =
    crdt_js.attach_with_rtc(
      document,
      on_ready: fn(outcome) {
        push(observed, case outcome {
          Ok(ready_document) ->
            "ready with "
            <> int.to_string(
              case crdt_js.pn_counter_value(crdt_js.root(ready_document)) {
                Ok(total) -> total
                Error(_) -> -1
              },
            )
          Error(error) -> "error " <> crdt_js.describe_error(error)
        })
      },
      on_status: fn(status) {
        case status {
          crdt_js.StateMerged(_, _) -> push(observed, "merged")
          crdt_js.Transport(..)
          | crdt_js.TransportError(..)
          | crdt_js.Joined(..)
          | crdt_js.RosterKnown(..)
          | crdt_js.AwaitingState(..)
          | crdt_js.Ready
          | crdt_js.PeerReady(..)
          | crdt_js.PeerGone(..)
          | crdt_js.PeerRejected(..)
          | crdt_js.RejectedByPeer(..)
          | crdt_js.Failed(..)
          | crdt_js.SubscriberFailed(..)
          | crdt_js.RelayConnecting(..)
          | crdt_js.RelayUnsupported(..)
          | crdt_js.RelaySyncingStatus
          | crdt_js.RelayRecovering
          | crdt_js.RelayPrimary(..)
          | crdt_js.RelayCheckpointRequested
          | crdt_js.RelayCheckpointed(..)
          | crdt_js.RelayFallback(..)
          | crdt_js.RelayRetry(..)
          | crdt_js.RelayRejected(..)
          | crdt_js.RelayFailed(..) -> Nil
        }
      },
      rtc: p2p_fake.rtc(world, crdt_js.replica_id(document)),
    )
  p2p_fake.settle(world)

  entries(observed) |> expect.to_equal(["merged", "ready with 5"])
}

@target(javascript)
/// A roster that names peers who then all vanish leaves this replica
/// alone in the room, and owed its readiness result.
pub fn a_roster_whose_peers_all_vanish_still_settles_readiness_test() -> Nil {
  let world = p2p_fake.new_world()
  let hub = hub_signaling(new_hub())
  let alpha = spawn(world, hub, "alpha", p2p.pn_counter_root(), tag)
  let beta = spawn(world, hub, "beta", p2p.pn_counter_root(), tag)
  entries(beta.readies) |> expect.to_equal([])

  crdt_js.close(alpha.connection)
  p2p_fake.settle(world)

  entries(beta.readies) |> expect.to_equal(["ok"])
}

@target(javascript)
/// Signaling that dies after `join` returned and before the roster
/// arrives is the hang this contract exists to prevent: the wait ends
/// once, with the typed error.
pub fn signaling_that_fails_before_the_roster_resolves_readiness_test() -> Nil {
  let world = p2p_fake.new_world()
  let alpha =
    spawn(world, p2p_fake.signaling(world), "alpha", p2p.pn_counter_root(), tag)
  entries(alpha.readies) |> expect.to_equal([])

  p2p_fake.fail_signaling(
    world,
    crdt_js.replica_id(alpha.document),
    "the signaling socket closed (1006)",
  )
  p2p_fake.settle(world)

  entries(alpha.readies)
  |> expect.to_equal([
    "error signalingFailed · the signaling socket closed (1006)",
  ])
  // And a second failure afterwards is status, not a second result.
  p2p_fake.fail_signaling(
    world,
    crdt_js.replica_id(alpha.document),
    "and again",
  )
  p2p_fake.settle(world)
  entries(alpha.readies)
  |> expect.to_equal([
    "error signalingFailed · the signaling socket closed (1006)",
  ])
}

@target(javascript)
/// Signaling that fails *after* readiness is reported and nothing more:
/// an open mesh does not need signaling, and a second readiness result
/// would be a lie about a document that is already live.
pub fn signaling_that_fails_after_readiness_is_status_only_test() -> Nil {
  let world = p2p_fake.new_world()
  let alpha =
    spawn(world, p2p_fake.signaling(world), "alpha", p2p.pn_counter_root(), tag)
  p2p_fake.settle(world)
  entries(alpha.readies) |> expect.to_equal(["ok"])

  p2p_fake.fail_signaling(
    world,
    crdt_js.replica_id(alpha.document),
    "the signaling socket closed (1006)",
  )
  p2p_fake.settle(world)

  entries(alpha.readies) |> expect.to_equal(["ok"])
  saw(alpha.statuses, "transportError signalingFailed") |> expect.to_be_true()
  let assert Ok(Nil) =
    crdt_js.pn_counter_update(crdt_js.root(alpha.document), 2)
  crdt_js.pn_counter_value(crdt_js.root(alpha.document))
  |> expect.to_equal(Ok(2))
}

// ─────────────────────────────────────────────────────────────────────────────
// Throwing application callbacks
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// A status handler that throws while the bootstrap is being announced
/// must not cost the bootstrap. The `stateRequest` is sent after
/// `AwaitingState` is emitted, and the merge that follows is what makes
/// this replica ready.
pub fn a_throwing_status_handler_does_not_skip_the_state_request_test() -> Nil {
  let world = p2p_fake.new_world()
  let hub = hub_signaling(new_hub())
  let alpha = spawn(world, hub, "alpha", p2p.pn_counter_root(), tag)
  let assert Ok(Nil) =
    crdt_js.pn_counter_update(crdt_js.root(alpha.document), 6)

  let readies = transport_js.new_cell([])
  let seen = transport_js.new_cell([])
  let assert Ok(document) =
    crdt_js.new_document(crdt_js.config(
      room_id: room,
      replica_label: "beta",
      compatibility_tag: tag,
      root: p2p.pn_counter_root(),
      signaling: hub,
    ))
  let _ =
    crdt_js.attach_with_rtc(
      document,
      on_ready: fn(outcome) {
        push(readies, case outcome {
          Ok(_) -> "ok"
          Error(error) -> "error " <> crdt_js.describe_error(error)
        })
      },
      on_status: fn(status) {
        push(seen, render(status))
        case status {
          crdt_js.AwaitingState(_) -> boom("status handler exploded")
          crdt_js.Transport(..)
          | crdt_js.TransportError(..)
          | crdt_js.Joined(..)
          | crdt_js.RosterKnown(..)
          | crdt_js.Ready
          | crdt_js.PeerReady(..)
          | crdt_js.PeerGone(..)
          | crdt_js.PeerRejected(..)
          | crdt_js.StateMerged(..)
          | crdt_js.RejectedByPeer(..)
          | crdt_js.Failed(..)
          | crdt_js.SubscriberFailed(..)
          | crdt_js.RelayConnecting(..)
          | crdt_js.RelayUnsupported(..)
          | crdt_js.RelaySyncingStatus
          | crdt_js.RelayRecovering
          | crdt_js.RelayPrimary(..)
          | crdt_js.RelayCheckpointRequested
          | crdt_js.RelayCheckpointed(..)
          | crdt_js.RelayFallback(..)
          | crdt_js.RelayRetry(..)
          | crdt_js.RelayRejected(..)
          | crdt_js.RelayFailed(..) -> Nil
        }
      },
      rtc: p2p_fake.rtc(world, crdt_js.replica_id(document)),
    )
  p2p_fake.settle(world)

  entries(readies) |> expect.to_equal(["ok"])
  crdt_js.pn_counter_value(crdt_js.root(document)) |> expect.to_equal(Ok(6))
  saw(seen, "stateMerged alpha") |> expect.to_be_true()
  saw(seen, "ready") |> expect.to_be_true()
}

@target(javascript)
/// And one that throws on the readiness statuses themselves: readiness
/// still resolves, exactly once, and the callback still runs.
pub fn a_throwing_status_handler_does_not_suppress_readiness_test() -> Nil {
  let world = p2p_fake.new_world()
  let readies = transport_js.new_cell([])
  let assert Ok(document) =
    crdt_js.new_document(crdt_js.config(
      room_id: room,
      replica_label: "alpha",
      compatibility_tag: tag,
      root: p2p.pn_counter_root(),
      signaling: hub_signaling(new_hub()),
    ))
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
        case status {
          crdt_js.Ready -> boom("ready handler exploded")
          crdt_js.Failed(_) -> boom("failed handler exploded")
          crdt_js.Transport(..)
          | crdt_js.TransportError(..)
          | crdt_js.Joined(..)
          | crdt_js.RosterKnown(..)
          | crdt_js.AwaitingState(..)
          | crdt_js.PeerReady(..)
          | crdt_js.PeerGone(..)
          | crdt_js.PeerRejected(..)
          | crdt_js.StateMerged(..)
          | crdt_js.RejectedByPeer(..)
          | crdt_js.SubscriberFailed(..)
          | crdt_js.RelayConnecting(..)
          | crdt_js.RelayUnsupported(..)
          | crdt_js.RelaySyncingStatus
          | crdt_js.RelayRecovering
          | crdt_js.RelayPrimary(..)
          | crdt_js.RelayCheckpointRequested
          | crdt_js.RelayCheckpointed(..)
          | crdt_js.RelayFallback(..)
          | crdt_js.RelayRetry(..)
          | crdt_js.RelayRejected(..)
          | crdt_js.RelayFailed(..) -> Nil
        }
      },
      rtc: p2p_fake.rtc(world, crdt_js.replica_id(document)),
    )
  p2p_fake.settle(world)

  entries(readies) |> expect.to_equal(["ok"])
  crdt_js.readiness(document) |> expect.to_equal(Some(Ok(Nil)))

  // Closing afterwards emits `Failed` to the same throwing handler, and
  // still resolves nothing twice.
  crdt_js.close(connection)
  p2p_fake.settle(world)
  entries(readies) |> expect.to_equal(["ok"])
}

@target(javascript)
/// The failure path, where a throwing handler would otherwise swallow
/// the one answer a caller is owed.
pub fn a_throwing_status_handler_does_not_suppress_a_failed_readiness_test() -> Nil {
  let world = p2p_fake.new_world()
  p2p_fake.fail_join(world, "no signaling service")
  let readies = transport_js.new_cell([])
  let assert Ok(document) =
    crdt_js.new_document(crdt_js.config(
      room_id: room,
      replica_label: "alpha",
      compatibility_tag: tag,
      root: p2p.pn_counter_root(),
      signaling: p2p_fake.signaling(world),
    ))
  let _ =
    crdt_js.attach_with_rtc(
      document,
      on_ready: fn(outcome) {
        push(readies, case outcome {
          Ok(_) -> "ok"
          Error(error) -> "error " <> crdt_js.describe_error(error)
        })
      },
      on_status: fn(_status) { boom("every status explodes") },
      rtc: p2p_fake.rtc(world, crdt_js.replica_id(document)),
    )
  p2p_fake.settle(world)

  entries(readies)
  |> expect.to_equal(["error signalingFailed · no signaling service"])
}

@target(javascript)
/// A readiness callback that throws is contained too: the transport, the
/// document, and every status after it are untouched.
pub fn a_throwing_readiness_callback_does_not_stop_the_document_test() -> Nil {
  let world = p2p_fake.new_world()
  let hub = hub_signaling(new_hub())
  let alpha = spawn(world, hub, "alpha", p2p.pn_counter_root(), tag)
  let statuses = transport_js.new_cell([])
  let assert Ok(document) =
    crdt_js.new_document(crdt_js.config(
      room_id: room,
      replica_label: "beta",
      compatibility_tag: tag,
      root: p2p.pn_counter_root(),
      signaling: hub,
    ))
  let _ =
    crdt_js.attach_with_rtc(
      document,
      on_ready: fn(_outcome) { boom("readiness callback exploded") },
      on_status: fn(status) { push(statuses, render(status)) },
      rtc: p2p_fake.rtc(world, crdt_js.replica_id(document)),
    )
  p2p_fake.settle(world)

  crdt_js.readiness(document) |> expect.to_equal(Some(Ok(Nil)))
  let assert Ok(Nil) = crdt_js.pn_counter_update(crdt_js.root(document), 4)
  p2p_fake.settle(world)
  crdt_js.pn_counter_value(crdt_js.root(alpha.document))
  |> expect.to_equal(Ok(4))
}

// ─────────────────────────────────────────────────────────────────────────────
// Editing and convergence
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// A peer that greets and then goes quiet must not hold a joiner's
/// readiness hostage. Every greeted peer is asked for state, so the
/// first answer from *any* of them is the bootstrap — not only the one
/// that happened to greet first.
pub fn a_silent_bootstrap_peer_does_not_hold_readiness_test() -> Nil {
  let world = p2p_fake.new_world()
  let hub = hub_signaling(new_hub())
  // `carol` opens a channel, greets, and answers nothing after that.
  let carol = raw_peer(world, hub, "carol")
  let beta = spawn(world, hub, "beta", p2p.pn_counter_root(), tag)
  p2p_fake.settle(world)
  send_raw(
    carol,
    crdt_js.replica_id(beta.document),
    crdt_core.encode(carol.document, crdt_core.hello_message(carol.document)),
  )
  p2p_fake.settle(world)

  // Greeted, asked, and stuck: nothing has answered the state request.
  saw(beta.statuses, "awaitingState carol") |> expect.to_be_true()
  entries(beta.readies) |> expect.to_equal([])

  // A healthy peer joins and answers. That is a valid state transfer, so
  // it is the bootstrap, whoever was asked first.
  let alpha = spawn(world, hub, "alpha", p2p.pn_counter_root(), tag)
  let assert Ok(Nil) =
    crdt_js.pn_counter_update(crdt_js.root(alpha.document), 7)
  p2p_fake.settle(world)

  entries(beta.readies) |> expect.to_equal(["ok"])
  crdt_js.pn_counter_value(crdt_js.root(beta.document))
  |> expect.to_equal(Ok(7))
}

@target(javascript)
pub fn a_local_edit_is_visible_immediately_and_broadcast_test() -> Nil {
  let world = p2p_fake.new_world()
  let hub = hub_signaling(new_hub())
  let alpha = spawn(world, hub, "alpha", p2p.pn_counter_root(), tag)
  let beta = spawn(world, hub, "beta", p2p.pn_counter_root(), tag)
  let gamma = spawn(world, hub, "gamma", p2p.pn_counter_root(), tag)
  p2p_fake.settle(world)

  let assert Ok(Nil) =
    crdt_js.pn_counter_update(crdt_js.root(alpha.document), 1)
  // Visible before anything has been delivered.
  crdt_js.pn_counter_value(crdt_js.root(alpha.document))
  |> expect.to_equal(Ok(1))

  let assert Ok(Nil) = crdt_js.pn_counter_update(crdt_js.root(beta.document), 2)
  let assert Ok(Nil) =
    crdt_js.pn_counter_update(crdt_js.root(gamma.document), 4)
  p2p_fake.settle(world)

  [alpha.document, beta.document, gamma.document]
  |> list.each(fn(document) {
    crdt_js.pn_counter_value(crdt_js.root(document)) |> expect.to_equal(Ok(7))
    crdt_js.digest(document)
    |> expect.to_equal(crdt_js.digest(alpha.document))
  })
  crdt_js.peer_count(alpha.document) |> expect.to_equal(2)
}

@target(javascript)
pub fn a_peer_that_leaves_is_reported_and_the_document_survives_test() -> Nil {
  let world = p2p_fake.new_world()
  let hub = hub_signaling(new_hub())
  let alpha = spawn(world, hub, "alpha", p2p.pn_counter_root(), tag)
  let beta = spawn(world, hub, "beta", p2p.pn_counter_root(), tag)
  p2p_fake.settle(world)
  let assert Ok(Nil) = crdt_js.pn_counter_update(crdt_js.root(beta.document), 5)
  p2p_fake.settle(world)

  crdt_js.close(beta.connection)
  p2p_fake.settle(world)

  saw(alpha.statuses, "peerGone beta") |> expect.to_be_true()
  crdt_js.peer_count(alpha.document) |> expect.to_equal(0)
  let assert Ok(Nil) =
    crdt_js.pn_counter_update(crdt_js.root(alpha.document), 1)
  crdt_js.pn_counter_value(crdt_js.root(alpha.document))
  |> expect.to_equal(Ok(6))
}

// ─────────────────────────────────────────────────────────────────────────────
// The trust boundary
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn a_compatibility_mismatch_closes_only_that_peer_test() -> Nil {
  let world = p2p_fake.new_world()
  let hub = hub_signaling(new_hub())
  let alpha = spawn(world, hub, "alpha", p2p.pn_counter_root(), tag)
  let beta = spawn(world, hub, "beta", p2p.pn_counter_root(), "other-app/v9")
  let gamma = spawn(world, hub, "gamma", p2p.pn_counter_root(), tag)
  p2p_fake.settle(world)

  saw(alpha.statuses, "peerRejected beta compatibilityMismatch")
  |> expect.to_be_true()
  crdt_js.peers(alpha.document)
  |> list.map(label_of)
  |> expect.to_equal(["gamma"])

  // The local document is untouched and the surviving peer still works.
  let assert Ok(Nil) =
    crdt_js.pn_counter_update(crdt_js.root(alpha.document), 3)
  p2p_fake.settle(world)
  crdt_js.pn_counter_value(crdt_js.root(gamma.document))
  |> expect.to_equal(Ok(3))
  crdt_js.pn_counter_value(crdt_js.root(beta.document))
  |> expect.to_equal(Ok(0))
}

@target(javascript)
pub fn a_root_mismatch_is_rejected_test() -> Nil {
  let world = p2p_fake.new_world()
  let hub = hub_signaling(new_hub())
  let alpha = spawn(world, hub, "alpha", p2p.pn_counter_root(), tag)
  let beta = spawn(world, hub, "beta", p2p.or_set_root(), tag)
  p2p_fake.settle(world)

  saw(alpha.statuses, "peerRejected beta rootMismatch") |> expect.to_be_true()
  saw(beta.statuses, "peerRejected alpha rootMismatch") |> expect.to_be_true()
  crdt_js.peers(alpha.document) |> expect.to_equal([])
}

@target(javascript)
pub fn a_message_before_hello_closes_the_peer_test() -> Nil {
  let world = p2p_fake.new_world()
  let hub = hub_signaling(new_hub())
  let alpha = spawn(world, hub, "alpha", p2p.pn_counter_root(), tag)
  let raw = raw_peer(world, hub, "mallory")
  p2p_fake.settle(world)

  let #(_document, delta) = raw_delta(raw.document, 4)
  send_raw(raw, crdt_js.replica_id(alpha.document), delta)
  p2p_fake.settle(world)

  saw(alpha.statuses, "sent delta before hello") |> expect.to_be_true()
  crdt_js.pn_counter_value(crdt_js.root(alpha.document))
  |> expect.to_equal(Ok(0))
  crdt_js.peers(alpha.document) |> expect.to_equal([])
  // The rejected peer learns why.
  list.any(entries(raw.received), fn(entry) {
    string.contains(entry, "invalidEnvelope")
  })
  |> expect.to_be_true()
}

@target(javascript)
pub fn a_forged_sender_closes_the_peer_test() -> Nil {
  let world = p2p_fake.new_world()
  let hub = hub_signaling(new_hub())
  let alpha = spawn(world, hub, "alpha", p2p.pn_counter_root(), tag)
  let raw = raw_peer(world, hub, "mallory")
  p2p_fake.settle(world)

  // A hello that claims to be from somebody else.
  let assert Ok(forged) =
    crdt_core.new(crdt_core.config(
      room: room,
      compatibility: tag,
      replica: "someone-else",
      session: "forged",
      root: channel.InitPnCounter,
    ))
  send_raw(
    raw,
    crdt_js.replica_id(alpha.document),
    crdt_core.encode(forged, crdt_core.hello_message(forged)),
  )
  p2p_fake.settle(world)

  saw(alpha.statuses, "envelope claims to be from someone-else")
  |> expect.to_be_true()
  crdt_js.peers(alpha.document) |> expect.to_equal([])
}

@target(javascript)
pub fn a_repeated_delta_merges_once_and_reports_once_test() -> Nil {
  let world = p2p_fake.new_world()
  let hub = hub_signaling(new_hub())
  let alpha = spawn(world, hub, "alpha", p2p.pn_counter_root(), tag)
  let seen = transport_js.new_cell([])
  let _ =
    crdt_js.subscribe_pn_counter(crdt_js.root(alpha.document), fn(event) {
      let pn_counter_kernel.Updated(applied, value) = event
      push(seen, int.to_string(applied) <> "->" <> int.to_string(value))
    })
  let raw = raw_peer(world, hub, "carol")
  p2p_fake.settle(world)

  let target = crdt_js.replica_id(alpha.document)
  send_raw(
    raw,
    target,
    crdt_core.encode(raw.document, crdt_core.hello_message(raw.document)),
  )
  let #(_document, delta) = raw_delta(raw.document, 6)
  send_raw(raw, target, delta)
  send_raw(raw, target, delta)
  send_raw(raw, target, delta)
  p2p_fake.settle(world)

  crdt_js.pn_counter_value(crdt_js.root(alpha.document))
  |> expect.to_equal(Ok(6))
  entries(seen) |> expect.to_equal(["6->6"])
}

@target(javascript)
/// A peer that repeats its `hello` after being greeted is ignored. The
/// first one started a state transfer; every one after it would start
/// another, so a peer could make this replica serialize and upload its
/// whole document as often as it asked.
pub fn a_repeated_hello_does_not_repeat_the_state_transfer_test() -> Nil {
  let world = p2p_fake.new_world()
  let hub = hub_signaling(new_hub())
  let alpha = spawn(world, hub, "alpha", p2p.pn_counter_root(), tag)
  let assert Ok(Nil) =
    crdt_js.pn_counter_update(crdt_js.root(alpha.document), 2)
  let raw = raw_peer(world, hub, "carol")
  p2p_fake.settle(world)

  let target = crdt_js.replica_id(alpha.document)
  let hello =
    crdt_core.encode(raw.document, crdt_core.hello_message(raw.document))
  send_raw(raw, target, hello)
  p2p_fake.settle(world)
  let after_first = list.length(entries(raw.received))

  send_raw(raw, target, hello)
  send_raw(raw, target, hello)
  p2p_fake.settle(world)

  // Not one further byte, and the peer is still a good standing member.
  list.length(entries(raw.received)) |> expect.to_equal(after_first)
  crdt_js.peers(alpha.document) |> expect.to_equal(["carol"])
  tagged(alpha.statuses, "peerReady") |> expect.to_equal(["peerReady carol"])
  tagged(alpha.statuses, "peerRejected") |> expect.to_equal([])
}

@target(javascript)
/// A data channel can be open before its `hello` has been validated. A
/// peer in that state has proved nothing about the room, the protocol,
/// the tag or the root, so it is not sent this document's deltas.
pub fn deltas_are_not_broadcast_before_the_handshake_test() -> Nil {
  let world = p2p_fake.new_world()
  let hub = hub_signaling(new_hub())
  let alpha = spawn(world, hub, "alpha", p2p.pn_counter_root(), tag)
  let silent = raw_peer(world, hub, "silent")
  p2p_fake.settle(world)

  // The link is open — the facade greeted it — but `silent` never
  // answered.
  let greeting = entries(silent.received)
  { list.length(greeting) == 1 } |> expect.to_be_true()

  let assert Ok(Nil) =
    crdt_js.pn_counter_update(crdt_js.root(alpha.document), 3)
  p2p_fake.settle(world)

  entries(silent.received) |> expect.to_equal(greeting)
  crdt_js.peers(alpha.document) |> expect.to_equal([])

  // And once it does greet, it is inside the boundary and gets the
  // traffic.
  send_raw(
    silent,
    crdt_js.replica_id(alpha.document),
    crdt_core.encode(silent.document, crdt_core.hello_message(silent.document)),
  )
  p2p_fake.settle(world)
  let assert Ok(Nil) =
    crdt_js.pn_counter_update(crdt_js.root(alpha.document), 4)
  p2p_fake.settle(world)
  { list.length(entries(silent.received)) > list.length(greeting) }
  |> expect.to_be_true()
}

@target(javascript)
pub fn a_malformed_payload_closes_the_peer_test() -> Nil {
  let world = p2p_fake.new_world()
  let hub = hub_signaling(new_hub())
  let alpha = spawn(world, hub, "alpha", p2p.pn_counter_root(), tag)
  let raw = raw_peer(world, hub, "mallory")
  p2p_fake.settle(world)

  send_raw(
    raw,
    crdt_js.replica_id(alpha.document),
    "{\"v\":1,\"nonsense\":true}",
  )
  p2p_fake.settle(world)

  saw(alpha.statuses, "peerRejected mallory") |> expect.to_be_true()
  crdt_js.peers(alpha.document) |> expect.to_equal([])
  crdt_js.pn_counter_value(crdt_js.root(alpha.document))
  |> expect.to_equal(Ok(0))
}

@target(javascript)
/// The one message that explains a link about to disappear must reach the
/// application rather than being dropped as "no local state changed".
pub fn a_rejection_from_a_peer_is_reported_test() -> Nil {
  let world = p2p_fake.new_world()
  let hub = hub_signaling(new_hub())
  let alpha = spawn(world, hub, "alpha", p2p.pn_counter_root(), tag)
  let raw = raw_peer(world, hub, "carol")
  p2p_fake.settle(world)

  let target = crdt_js.replica_id(alpha.document)
  send_raw(
    raw,
    target,
    crdt_core.encode(raw.document, crdt_core.hello_message(raw.document)),
  )
  send_raw(
    raw,
    target,
    crdt_core.encode(
      raw.document,
      crdt_core.rejection_message("compatibilityMismatch", "yours differs"),
    ),
  )
  p2p_fake.settle(world)

  saw(
    alpha.statuses,
    "rejectedByPeer carol compatibilityMismatch yours differs",
  )
  |> expect.to_be_true()
  // Reported, not acted on: the local document and the link are intact.
  crdt_js.peers(alpha.document)
  |> list.map(label_of)
  |> expect.to_equal(["carol"])
}

// ─────────────────────────────────────────────────────────────────────────────
// Channels
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn a_created_channel_reaches_every_peer_test() -> Nil {
  let world = p2p_fake.new_world()
  let hub = hub_signaling(new_hub())
  let alpha = spawn(world, hub, "alpha", p2p.pn_counter_root(), tag)
  let beta = spawn(world, hub, "beta", p2p.pn_counter_root(), tag)
  p2p_fake.settle(world)

  let assert Ok(notes) =
    crdt_js.create_channel(alpha.document, p2p.or_set_root())
  let assert Ok(Nil) = crdt_js.or_set_add(notes, "book the ferry")
  p2p_fake.settle(world)

  let address = crdt_js.address(notes)
  { string.starts_with(address, crdt_js.replica_id(alpha.document) <> ":") }
  |> expect.to_be_true()

  let assert Ok(remote) =
    crdt_js.resolve_channel(beta.document, p2p.or_set_root(), address)
  crdt_js.or_set_values(remote) |> expect.to_equal(Ok(["book the ferry"]))
  crdt_js.or_set_contains(remote, "book the ferry") |> expect.to_equal(Ok(True))
}

@target(javascript)
pub fn resolving_with_the_wrong_kind_is_a_typed_error_test() -> Nil {
  let world = p2p_fake.new_world()
  let alpha =
    spawn(world, hub_signaling(new_hub()), "alpha", p2p.pn_counter_root(), tag)
  let assert Ok(notes) =
    crdt_js.create_channel(alpha.document, p2p.or_set_root())
  let address = crdt_js.address(notes)

  crdt_js.resolve_channel(alpha.document, p2p.text_root(), address)
  |> expect.to_equal(
    Error(p2p.ChannelTypeMismatch(
      address,
      channel.TextChannel,
      channel.OrSetChannel,
    )),
  )

  case crdt_js.resolve_channel(alpha.document, p2p.or_set_root(), "no-such:1") {
    Error(p2p.InvalidEnvelope(_, detail)) ->
      detail |> expect.to_equal("no channel registered at no-such:1")
    other ->
      panic as { "expected InvalidEnvelope, got " <> string.inspect(other) }
  }
}

@target(javascript)
/// Every eligible kind, created through the generic constructor, mutated
/// and read back through its own typed operations.
pub fn every_eligible_kind_mutates_and_reads_test() -> Nil {
  let world = p2p_fake.new_world()
  let alpha =
    spawn(world, hub_signaling(new_hub()), "alpha", p2p.pn_counter_root(), tag)
  let document = alpha.document

  let counter = crdt_js.root(document)
  let assert Ok(Nil) = crdt_js.pn_counter_increment(counter, 10)
  let assert Ok(Nil) = crdt_js.pn_counter_decrement(counter, 4)
  crdt_js.pn_counter_value(counter) |> expect.to_equal(Ok(6))

  let assert Ok(tally) =
    crdt_js.create_channel(document, p2p.or_map_root(or_map_kernel.TallyMode))
  let assert Ok(Nil) = crdt_js.or_map_increment(tally, key: "votes", amount: 3)
  let assert Ok(Nil) = crdt_js.or_map_increment(tally, key: "votes", amount: 2)
  crdt_js.or_map_tally(tally, key: "votes") |> expect.to_equal(Ok(5))
  crdt_js.or_map_value(tally, key: "votes")
  |> expect.to_equal(Ok(Ok(or_map_kernel.Tally(5))))
  crdt_js.or_map_entries(tally)
  |> expect.to_equal(Ok([#("votes", or_map_kernel.Tally(5))]))
  let assert Ok(Nil) = crdt_js.or_map_remove(tally, key: "votes")
  crdt_js.or_map_entries(tally) |> expect.to_equal(Ok([]))

  let assert Ok(registers) =
    crdt_js.create_channel(
      document,
      p2p.or_map_root(or_map_kernel.RegisterMode),
    )
  let assert Ok(Nil) = crdt_js.or_map_set(registers, key: "city", value: "Oslo")
  crdt_js.or_map_value(registers, key: "city")
  |> expect.to_equal(Ok(Ok(or_map_kernel.Register("Oslo"))))
  // A tally operation on a register map is the kernel's mode mismatch.
  case crdt_js.or_map_increment(registers, key: "city", amount: 1) {
    Error(p2p.InvalidEnvelope(_, detail)) ->
      { string.contains(detail, "TallyMode") } |> expect.to_be_true()
    other ->
      panic as { "expected a mode mismatch, got " <> string.inspect(other) }
  }
  case crdt_js.or_map_tally(registers, key: "city") {
    Error(p2p.InvalidEnvelope(_, detail)) ->
      { string.contains(detail, "register") } |> expect.to_be_true()
    other ->
      panic as { "expected a tally refusal, got " <> string.inspect(other) }
  }

  let assert Ok(observed) = crdt_js.create_channel(document, p2p.or_set_root())
  let assert Ok(Nil) = crdt_js.or_set_add(observed, "ferry")
  let assert Ok(Nil) = crdt_js.or_set_add(observed, "train")
  let assert Ok(Nil) = crdt_js.or_set_remove(observed, "ferry")
  crdt_js.or_set_values(observed) |> expect.to_equal(Ok(["train"]))
  crdt_js.or_set_contains(observed, "ferry") |> expect.to_equal(Ok(False))

  let assert Ok(grow) = crdt_js.create_channel(document, p2p.g_set_root())
  let assert Ok(Nil) = crdt_js.g_set_add(grow, "one")
  crdt_js.g_set_values(grow) |> expect.to_equal(Ok(["one"]))
  crdt_js.g_set_contains(grow, "one") |> expect.to_equal(Ok(True))

  let assert Ok(two_phase) =
    crdt_js.create_channel(document, p2p.two_p_set_root())
  let assert Ok(Nil) = crdt_js.two_p_set_add(two_phase, "seat")
  let assert Ok(Nil) = crdt_js.two_p_set_add(two_phase, "table")
  let assert Ok(Nil) = crdt_js.two_p_set_remove(two_phase, "seat")
  crdt_js.two_p_set_values(two_phase) |> expect.to_equal(Ok(["table"]))
  crdt_js.two_p_set_contains(two_phase, "seat") |> expect.to_equal(Ok(False))

  let assert Ok(order) = crdt_js.create_channel(document, p2p.sequence_root())
  let assert Ok(Nil) =
    crdt_js.sequence_insert(order, index: 0, value: json.string("b"))
  let assert Ok(Nil) =
    crdt_js.sequence_insert(order, index: 0, value: json.string("a"))
  let assert Ok(Nil) =
    crdt_js.sequence_insert(order, index: 2, value: json.string("c"))
  let assert Ok(Nil) = crdt_js.sequence_move(order, from: 2, to: 0)
  crdt_js.sequence_values(order)
  |> expect.to_equal(Ok([json.string("c"), json.string("a"), json.string("b")]))
  let assert Ok(Nil) = crdt_js.sequence_delete(order, index: 2)
  let assert Ok(Nil) =
    crdt_js.sequence_replace(order, index: 1, value: json.string("A"))
  crdt_js.sequence_values(order)
  |> expect.to_equal(Ok([json.string("c"), json.string("A")]))
  case crdt_js.sequence_delete(order, index: 9) {
    Error(p2p.InvalidEnvelope(_, detail)) ->
      { string.contains(detail, "invalid for length") } |> expect.to_be_true()
    other ->
      panic as {
        "expected an out-of-bounds error, got " <> string.inspect(other)
      }
  }

  let assert Ok(prose) = crdt_js.create_channel(document, p2p.text_root())
  let assert Ok(Nil) = crdt_js.text_append(prose, "hello")
  let assert Ok(Nil) = crdt_js.text_insert(prose, index: 5, value: " world")
  let assert Ok(Nil) =
    crdt_js.text_replace_range(prose, start: 0, end: 5, value: "goodbye")
  let assert Ok(Nil) = crdt_js.text_delete_range(prose, start: 7, end: 13)
  crdt_js.text_value(prose) |> expect.to_equal(Ok("goodbye"))
  case crdt_js.text_delete_range(prose, start: 0, end: 99) {
    Error(p2p.InvalidEnvelope(_, detail)) ->
      { string.contains(detail, "invalid for length") } |> expect.to_be_true()
    other ->
      panic as {
        "expected an out-of-bounds error, got " <> string.inspect(other)
      }
  }
}

@target(javascript)
pub fn text_length_and_anchors_track_positions_test() -> Nil {
  let assert Ok(document) =
    crdt_js.new_document(crdt_js.config(
      room_id: room,
      replica_label: "scribe",
      compatibility_tag: tag,
      root: p2p.text_root(),
      signaling: hub_signaling(new_hub()),
    ))
  let text = crdt_js.root(document)

  let assert Ok(Nil) = crdt_js.text_append(text, "hello")
  crdt_js.text_length(text) |> expect.to_equal(Ok(5))

  let assert Ok(anchor) = crdt_js.text_anchor_at(text, 5, crdt_js.bias_after)
  let assert Ok(decoded) =
    crdt_js.text_anchor_from_json(
      json.to_string(crdt_js.text_anchor_to_json(anchor)),
    )
  decoded |> expect.to_equal(anchor)

  let assert Ok(Nil) = crdt_js.text_insert(text, 0, "say ")
  crdt_js.text_resolve_anchor(text, anchor) |> expect.to_equal(Ok(9))
  crdt_js.text_resolve_anchor(text, decoded) |> expect.to_equal(Ok(9))
  crdt_js.text_resolve_anchor(text, crdt_js.text_start_anchor())
  |> expect.to_equal(Ok(0))
  crdt_js.text_resolve_anchor(text, crdt_js.text_end_anchor())
  |> expect.to_equal(Ok(9))

  let assert Ok(Nil) = crdt_js.text_append(text, "!")
  crdt_js.text_length(text) |> expect.to_equal(Ok(10))
  crdt_js.text_resolve_anchor(text, crdt_js.text_end_anchor())
  |> expect.to_equal(Ok(10))
}

@target(javascript)
pub fn text_anchor_errors_are_typed_p2p_errors_test() -> Nil {
  let assert Ok(document) =
    crdt_js.new_document(crdt_js.config(
      room_id: room,
      replica_label: "scribe",
      compatibility_tag: tag,
      root: p2p.text_root(),
      signaling: hub_signaling(new_hub()),
    ))
  let text = crdt_js.root(document)
  let assert Ok(Nil) = crdt_js.text_append(text, "abc")

  case crdt_js.text_anchor_at(text, 4, crdt_js.bias_before) {
    Error(p2p.InvalidEnvelope(_, detail)) ->
      detail |> expect.to_equal("anchor index 4 outside 0..3")
    other ->
      panic as { "expected InvalidEnvelope, got " <> string.inspect(other) }
  }

  case crdt_js.text_anchor_from_json("") {
    Error(p2p.InvalidEnvelope(_, detail)) ->
      detail |> expect.to_equal("invalid anchor JSON: unexpected end of input")
    other ->
      panic as { "expected InvalidEnvelope, got " <> string.inspect(other) }
  }
}

@target(javascript)
/// An ineligible kind has no `CrdtKind` to name it, so this is the only
/// route left: a snapshot claiming one. It is refused.
pub fn an_ineligible_channel_cannot_be_imported_test() -> Nil {
  let world = p2p_fake.new_world()
  let alpha =
    spawn(world, hub_signaling(new_hub()), "alpha", p2p.pn_counter_root(), tag)
  let _ = world

  crdt_js.resolve_channel(alpha.document, p2p.text_root(), "root")
  |> expect.to_equal(
    Error(p2p.ChannelTypeMismatch(
      "root",
      channel.TextChannel,
      channel.PnCounterChannel,
    )),
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Subscriptions
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn subscriptions_are_address_scoped_and_removable_test() -> Nil {
  let world = p2p_fake.new_world()
  let alpha =
    spawn(world, hub_signaling(new_hub()), "alpha", p2p.pn_counter_root(), tag)
  let assert Ok(prose) = crdt_js.create_channel(alpha.document, p2p.text_root())
  let assert Ok(order) =
    crdt_js.create_channel(alpha.document, p2p.sequence_root())

  let counter_events = transport_js.new_cell([])
  let text_events = transport_js.new_cell([])
  let sequence_events = transport_js.new_cell([])

  let subscription =
    crdt_js.subscribe_pn_counter(crdt_js.root(alpha.document), fn(event) {
      let pn_counter_kernel.Updated(_, value) = event
      push(counter_events, int.to_string(value))
    })
  let _ =
    crdt_js.subscribe_text(prose, fn(event) {
      let text_kernel.TextChanged(value) = event
      push(text_events, value)
    })
  let _ =
    crdt_js.subscribe_sequence(order, fn(event) {
      let sequence_kernel.SequenceChanged(values) = event
      push(sequence_events, int.to_string(list.length(values)))
    })

  let assert Ok(Nil) =
    crdt_js.pn_counter_update(crdt_js.root(alpha.document), 2)
  let assert Ok(Nil) = crdt_js.text_append(prose, "hi")
  let assert Ok(Nil) =
    crdt_js.sequence_insert(order, index: 0, value: json.int(1))

  entries(counter_events) |> expect.to_equal(["2"])
  entries(text_events) |> expect.to_equal(["hi"])
  entries(sequence_events) |> expect.to_equal(["1"])

  crdt_js.unsubscribe(subscription)
  let assert Ok(Nil) =
    crdt_js.pn_counter_update(crdt_js.root(alpha.document), 5)
  entries(counter_events) |> expect.to_equal(["2"])
  crdt_js.pn_counter_value(crdt_js.root(alpha.document))
  |> expect.to_equal(Ok(7))

  // Idempotent.
  crdt_js.unsubscribe(subscription)
}

@target(javascript)
pub fn a_throwing_subscriber_is_contained_test() -> Nil {
  let world = p2p_fake.new_world()
  let alpha =
    spawn(world, hub_signaling(new_hub()), "alpha", p2p.pn_counter_root(), tag)
  let survivor = transport_js.new_cell([])

  let _ =
    crdt_js.subscribe_pn_counter(crdt_js.root(alpha.document), fn(_event) {
      panic as "a subscriber that throws"
    })
  let _ =
    crdt_js.subscribe_pn_counter(crdt_js.root(alpha.document), fn(event) {
      let pn_counter_kernel.Updated(_, value) = event
      push(survivor, int.to_string(value))
    })

  let assert Ok(Nil) =
    crdt_js.pn_counter_update(crdt_js.root(alpha.document), 3)

  // The document committed, the other subscriber still ran, and the
  // exception was reported rather than swallowed.
  crdt_js.pn_counter_value(crdt_js.root(alpha.document))
  |> expect.to_equal(Ok(3))
  entries(survivor) |> expect.to_equal(["3"])
  saw(alpha.statuses, "subscriberFailed root") |> expect.to_be_true()
}

@target(javascript)
pub fn a_remote_merge_reports_each_event_once_test() -> Nil {
  let world = p2p_fake.new_world()
  let hub = hub_signaling(new_hub())
  let alpha = spawn(world, hub, "alpha", p2p.pn_counter_root(), tag)
  let beta = spawn(world, hub, "beta", p2p.pn_counter_root(), tag)
  let gamma = spawn(world, hub, "gamma", p2p.pn_counter_root(), tag)
  p2p_fake.settle(world)

  let seen = transport_js.new_cell([])
  let _ =
    crdt_js.subscribe_pn_counter(crdt_js.root(gamma.document), fn(event) {
      let pn_counter_kernel.Updated(applied, value) = event
      push(seen, int.to_string(applied) <> "->" <> int.to_string(value))
    })

  let assert Ok(Nil) =
    crdt_js.pn_counter_update(crdt_js.root(alpha.document), 1)
  let assert Ok(Nil) = crdt_js.pn_counter_update(crdt_js.root(beta.document), 2)
  p2p_fake.settle(world)

  // One event per authored edit, in a full mesh where both deltas and a
  // later state exchange carry the same values.
  entries(seen) |> expect.to_equal(["1->1", "2->3"])
  crdt_js.pn_counter_value(crdt_js.root(gamma.document))
  |> expect.to_equal(Ok(3))
}

// ─────────────────────────────────────────────────────────────────────────────
// Snapshots
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn a_snapshot_round_trips_and_reattaches_test() -> Nil {
  let world = p2p_fake.new_world()
  let hub = hub_signaling(new_hub())
  let alpha = spawn(world, hub, "alpha", p2p.pn_counter_root(), tag)
  let assert Ok(notes) =
    crdt_js.create_channel(alpha.document, p2p.or_set_root())
  let assert Ok(Nil) = crdt_js.or_set_add(notes, "pack")
  let assert Ok(Nil) =
    crdt_js.pn_counter_update(crdt_js.root(alpha.document), 9)

  let assert Ok(snapshot) = crdt_js.export_snapshot(alpha.document)

  let restored_config =
    crdt_js.config(
      room_id: room,
      replica_label: "restored",
      compatibility_tag: tag,
      root: p2p.pn_counter_root(),
      signaling: hub,
    )
  let assert Ok(restored) = crdt_js.import_snapshot(restored_config, snapshot)

  crdt_js.pn_counter_value(crdt_js.root(restored)) |> expect.to_equal(Ok(9))
  crdt_js.addresses(restored)
  |> expect.to_equal(crdt_js.addresses(alpha.document))
  let assert Ok(restored_notes) =
    crdt_js.resolve_channel(restored, p2p.or_set_root(), crdt_js.address(notes))
  crdt_js.or_set_values(restored_notes) |> expect.to_equal(Ok(["pack"]))

  // And the imported document joins the room through the same lifecycle.
  let readies = transport_js.new_cell([])
  let _ =
    crdt_js.attach_with_rtc(
      restored,
      on_ready: fn(outcome) {
        push(readies, case outcome {
          Ok(_) -> "ok"
          Error(error) -> "error " <> crdt_js.describe_error(error)
        })
      },
      on_status: fn(_status) { Nil },
      rtc: p2p_fake.rtc(world, crdt_js.replica_id(restored)),
    )
  p2p_fake.settle(world)

  entries(readies) |> expect.to_equal(["ok"])
  let assert Ok(Nil) = crdt_js.pn_counter_update(crdt_js.root(restored), 1)
  p2p_fake.settle(world)
  crdt_js.pn_counter_value(crdt_js.root(alpha.document))
  |> expect.to_equal(Ok(10))
  crdt_js.digest(alpha.document) |> expect.to_equal(crdt_js.digest(restored))
}

@target(javascript)
pub fn an_import_validates_room_tag_and_root_test() -> Nil {
  let world = p2p_fake.new_world()
  let hub = hub_signaling(new_hub())
  let alpha = spawn(world, hub, "alpha", p2p.pn_counter_root(), tag)
  let assert Ok(snapshot) = crdt_js.export_snapshot(alpha.document)

  crdt_js.import_snapshot(
    crdt_js.config(
      room_id: "another-room",
      replica_label: "restored",
      compatibility_tag: tag,
      root: p2p.pn_counter_root(),
      signaling: hub,
    ),
    snapshot,
  )
  |> expect.to_equal(Error(p2p.RoomMismatch))

  crdt_js.import_snapshot(
    crdt_js.config(
      room_id: room,
      replica_label: "restored",
      compatibility_tag: "other-app/v9",
      root: p2p.pn_counter_root(),
      signaling: hub,
    ),
    snapshot,
  )
  |> expect.to_equal(Error(p2p.CompatibilityMismatch("other-app/v9", tag)))

  crdt_js.import_snapshot(
    crdt_js.config(
      room_id: room,
      replica_label: "restored",
      compatibility_tag: tag,
      root: p2p.or_set_root(),
      signaling: hub,
    ),
    snapshot,
  )
  |> expect.to_equal(
    Error(p2p.RootMismatch(channel.OrSetChannel, channel.PnCounterChannel)),
  )
}

@target(javascript)
pub fn merge_snapshot_is_a_join_and_is_idempotent_test() -> Nil {
  let signaling = hub_signaling(new_hub())
  let assert Ok(source) =
    crdt_js.new_document(crdt_js.config(
      room_id: room,
      replica_label: "source",
      compatibility_tag: tag,
      root: p2p.g_set_root(),
      signaling: signaling,
    ))
  let assert Ok(target) =
    crdt_js.new_document(crdt_js.config(
      room_id: room,
      replica_label: "target",
      compatibility_tag: tag,
      root: p2p.g_set_root(),
      signaling: signaling,
    ))

  let assert Ok(Nil) = crdt_js.g_set_add(crdt_js.root(source), "from-source")
  let assert Ok(basket) = crdt_js.create_channel(source, p2p.or_set_root())
  let assert Ok(Nil) = crdt_js.or_set_add(basket, "apples")
  let basket_address = crdt_js.address(basket)

  let assert Ok(Nil) = crdt_js.g_set_add(crdt_js.root(target), "from-target")
  let seen = transport_js.new_cell([])
  let _ =
    crdt_js.subscribe_g_set(crdt_js.root(target), fn(event) {
      let g_set_kernel.ElementAdded(element) = event
      push(seen, element)
    })
  let assert Ok(target_before) = crdt_js.export_snapshot(target)
  let assert Ok(snapshot) = crdt_js.export_snapshot(source)

  let assert Ok(outcome) = crdt_js.merge_snapshot(target, snapshot)
  let crdt_core.Outcome(created:, events:, ..) = outcome
  list.length(created) |> expect.to_equal(1)
  list.length(events) |> expect.to_equal(2)
  entries(seen) |> expect.to_equal(["from-source"])
  let assert Ok(target_values) = crdt_js.g_set_values(crdt_js.root(target))
  target_values
  |> list.sort(string.compare)
  |> expect.to_equal(["from-source", "from-target"])
  let assert Ok(target_basket) =
    crdt_js.resolve_channel(target, p2p.or_set_root(), basket_address)
  crdt_js.or_set_values(target_basket) |> expect.to_equal(Ok(["apples"]))

  let assert Ok(_) = crdt_js.merge_snapshot(source, target_before)
  crdt_js.digest(source) |> expect.to_equal(crdt_js.digest(target))
  let assert Ok(source_values) = crdt_js.g_set_values(crdt_js.root(source))
  source_values
  |> list.sort(string.compare)
  |> expect.to_equal(["from-source", "from-target"])

  let digest = crdt_js.digest(target)
  let assert Ok(second) = crdt_js.merge_snapshot(target, snapshot)
  let crdt_core.Outcome(created: created_again, events: events_again, ..) =
    second
  created_again |> expect.to_equal([])
  events_again |> expect.to_equal([])
  crdt_js.digest(target) |> expect.to_equal(digest)
  entries(seen) |> expect.to_equal(["from-source"])
}

@target(javascript)
pub fn merge_snapshot_propagates_to_attached_peers_test() -> Nil {
  let world = p2p_fake.new_world()
  let clock = relay_fake.new_clock()
  let signaling = p2p_fake.signaling(world)
  let alpha =
    spawn_synced(world, signaling, "alpha", p2p.g_set_root(), tag, clock)
  let beta =
    spawn_synced(world, signaling, "beta", p2p.g_set_root(), tag, clock)
  p2p_fake.settle(world)

  let assert Ok(Nil) =
    crdt_js.g_set_add(crdt_js.root(beta.document), "from-beta")
  p2p_fake.settle(world)

  let assert Ok(source) =
    crdt_js.new_document(crdt_js.config(
      room_id: room,
      replica_label: "source",
      compatibility_tag: tag,
      root: p2p.g_set_root(),
      signaling: signaling,
    ))
  let assert Ok(Nil) = crdt_js.g_set_add(crdt_js.root(source), "from-snapshot")
  let assert Ok(basket) = crdt_js.create_channel(source, p2p.or_set_root())
  let assert Ok(Nil) = crdt_js.or_set_add(basket, "apples")
  let basket_address = crdt_js.address(basket)
  let assert Ok(snapshot) = crdt_js.export_snapshot(source)

  let assert Ok(_) = crdt_js.merge_snapshot(beta.document, snapshot)
  crdt_js.g_set_values(crdt_js.root(alpha.document))
  |> expect.to_equal(Ok(["from-beta"]))

  drive_convergence(
    world,
    clock,
    crdt_js.default_anti_entropy_milliseconds,
    [alpha.document, beta.document],
    12,
  )

  crdt_js.digest(alpha.document)
  |> expect.to_equal(crdt_js.digest(beta.document))
  let assert Ok(alpha_values) =
    crdt_js.g_set_values(crdt_js.root(alpha.document))
  alpha_values
  |> list.sort(string.compare)
  |> expect.to_equal(["from-beta", "from-snapshot"])
  let assert Ok(alpha_basket) =
    crdt_js.resolve_channel(alpha.document, p2p.or_set_root(), basket_address)
  crdt_js.or_set_values(alpha_basket) |> expect.to_equal(Ok(["apples"]))
}

@target(javascript)
pub fn a_detached_imported_document_can_edit_create_subscribe_export_and_attach_test() -> Nil {
  let world = p2p_fake.new_world()
  let clock = relay_fake.new_clock()
  let signaling = p2p_fake.signaling(world)

  let assert Ok(source) =
    crdt_js.new_document(crdt_js.config(
      room_id: room,
      replica_label: "source",
      compatibility_tag: tag,
      root: p2p.g_set_root(),
      signaling: signaling,
    ))
  let assert Ok(Nil) = crdt_js.g_set_add(crdt_js.root(source), "seed")
  let assert Ok(snapshot) = crdt_js.export_snapshot(source)

  let config =
    crdt_js.config(
      room_id: room,
      replica_label: "beta",
      compatibility_tag: tag,
      root: p2p.g_set_root(),
      signaling: signaling,
    )
    |> crdt_js.with_scheduler(relay_fake.scheduler(clock))
  let assert Ok(imported) = crdt_js.import_snapshot(config, snapshot)

  let seen = transport_js.new_cell([])
  let _ =
    crdt_js.subscribe_g_set(crdt_js.root(imported), fn(event) {
      let g_set_kernel.ElementAdded(element) = event
      push(seen, element)
    })
  let assert Ok(Nil) = crdt_js.g_set_add(crdt_js.root(imported), "offline")
  entries(seen) |> expect.to_equal(["offline"])

  let assert Ok(extras) = crdt_js.create_channel(imported, p2p.or_set_root())
  let extras_address = crdt_js.address(extras)
  let assert Ok(Nil) = crdt_js.or_set_add(extras, "bananas")

  let assert Ok(detached_snapshot) = crdt_js.export_snapshot(imported)
  let assert Ok(reloaded) =
    crdt_js.import_snapshot(
      crdt_js.config(
        room_id: room,
        replica_label: "check",
        compatibility_tag: tag,
        root: p2p.g_set_root(),
        signaling: signaling,
      ),
      detached_snapshot,
    )
  let assert Ok(reloaded_values) = crdt_js.g_set_values(crdt_js.root(reloaded))
  reloaded_values
  |> list.sort(string.compare)
  |> expect.to_equal(["offline", "seed"])
  let assert Ok(reloaded_extras) =
    crdt_js.resolve_channel(reloaded, p2p.or_set_root(), extras_address)
  crdt_js.or_set_values(reloaded_extras) |> expect.to_equal(Ok(["bananas"]))

  let alpha =
    spawn_synced(world, signaling, "alpha", p2p.g_set_root(), tag, clock)
  let readies = transport_js.new_cell([])
  let _ =
    crdt_js.attach_with_rtc(
      imported,
      on_ready: fn(outcome) {
        push(readies, case outcome {
          Ok(_) -> "ok"
          Error(error) -> "error " <> crdt_js.describe_error(error)
        })
      },
      on_status: fn(_status) { Nil },
      rtc: p2p_fake.rtc(world, crdt_js.replica_id(imported)),
    )
  p2p_fake.settle(world)
  drive_convergence(
    world,
    clock,
    crdt_js.default_anti_entropy_milliseconds,
    [alpha.document, imported],
    12,
  )

  entries(readies) |> expect.to_equal(["ok"])
  crdt_js.digest(alpha.document) |> expect.to_equal(crdt_js.digest(imported))
  let assert Ok(alpha_values) =
    crdt_js.g_set_values(crdt_js.root(alpha.document))
  alpha_values
  |> list.sort(string.compare)
  |> expect.to_equal(["offline", "seed"])
  let assert Ok(alpha_extras) =
    crdt_js.resolve_channel(alpha.document, p2p.or_set_root(), extras_address)
  crdt_js.or_set_values(alpha_extras) |> expect.to_equal(Ok(["bananas"]))
}

@target(javascript)
pub fn an_imported_snapshot_stays_detached_after_a_missing_sequencer_test() -> Nil {
  let world = p2p_fake.new_world()
  let hub = hub_signaling(new_hub())
  let assert Ok(source) =
    crdt_js.new_document(crdt_js.config(
      room_id: room,
      replica_label: "source",
      compatibility_tag: tag,
      root: p2p.pn_counter_root(),
      signaling: hub,
    ))
  let assert Ok(Nil) = crdt_js.pn_counter_update(crdt_js.root(source), 7)
  let assert Ok(snapshot) = crdt_js.export_snapshot(source)

  let assert Ok(imported) =
    crdt_js.import_snapshot(
      crdt_js.config(
        room_id: room,
        replica_label: "beta",
        compatibility_tag: tag,
        root: p2p.pn_counter_root(),
        signaling: hub,
      )
        |> crdt_js.with_transport_policy(crdt_js.SequencedOnly),
      snapshot,
    )
  let readies = transport_js.new_cell([])
  let statuses = transport_js.new_cell([])
  let _ =
    crdt_js.attach_with_rtc(
      imported,
      on_ready: fn(outcome) {
        push(readies, case outcome {
          Ok(_) -> "ok"
          Error(error) -> "error " <> crdt_js.describe_error(error)
        })
      },
      on_status: fn(status) { push(statuses, render(status)) },
      rtc: p2p_fake.rtc(world, crdt_js.replica_id(imported)),
    )

  entries(readies)
  |> expect.to_equal([
    "error sequencerUnavailable · sequencedOnly needs a sequencer, and none "
    <> "was configured",
  ])
  entries(statuses)
  |> expect.to_equal([
    "joined " <> room,
    "failed sequencerUnavailable · sequencedOnly needs a sequencer, and none "
      <> "was configured",
  ])
  crdt_js.is_closed(imported) |> expect.to_be_false()
  crdt_js.readiness(imported) |> expect.to_equal(None)
  crdt_js.pn_counter_value(crdt_js.root(imported)) |> expect.to_equal(Ok(7))
  let assert Ok(Nil) = crdt_js.pn_counter_update(crdt_js.root(imported), 2)
  crdt_js.pn_counter_value(crdt_js.root(imported)) |> expect.to_equal(Ok(9))
}

@target(javascript)
pub fn an_imported_snapshot_stays_detached_after_a_synchronous_attach_failure_and_can_retry_test() -> Nil {
  let world = p2p_fake.new_world()
  let hub = hub_signaling(new_hub())
  let gate = transport_js.new_cell(Some("no signaling service"))
  let signaling = gated_signaling(hub, gate)
  let assert Ok(source) =
    crdt_js.new_document(crdt_js.config(
      room_id: room,
      replica_label: "source",
      compatibility_tag: tag,
      root: p2p.pn_counter_root(),
      signaling: hub,
    ))
  let assert Ok(Nil) = crdt_js.pn_counter_update(crdt_js.root(source), 9)
  let assert Ok(snapshot) = crdt_js.export_snapshot(source)

  let assert Ok(imported) =
    crdt_js.import_snapshot(
      crdt_js.config(
        room_id: room,
        replica_label: "beta",
        compatibility_tag: tag,
        root: p2p.pn_counter_root(),
        signaling: signaling,
      ),
      snapshot,
    )
  let first_readies = transport_js.new_cell([])
  let first_statuses = transport_js.new_cell([])
  let _ =
    crdt_js.attach_with_rtc(
      imported,
      on_ready: fn(outcome) {
        push(first_readies, case outcome {
          Ok(_) -> "ok"
          Error(error) -> "error " <> crdt_js.describe_error(error)
        })
      },
      on_status: fn(status) { push(first_statuses, render(status)) },
      rtc: p2p_fake.rtc(world, crdt_js.replica_id(imported)),
    )

  entries(first_readies)
  |> expect.to_equal(["error signalingFailed · no signaling service"])
  entries(first_statuses)
  |> expect.to_equal([
    "joined " <> room,
    "failed signalingFailed · no signaling service",
  ])
  crdt_js.is_closed(imported) |> expect.to_be_false()
  crdt_js.readiness(imported) |> expect.to_equal(None)
  crdt_js.pn_counter_value(crdt_js.root(imported)) |> expect.to_equal(Ok(9))
  let assert Ok(Nil) = crdt_js.pn_counter_update(crdt_js.root(imported), 1)
  crdt_js.pn_counter_value(crdt_js.root(imported)) |> expect.to_equal(Ok(10))

  transport_js.set_cell(gate, None)
  let retry_readies = transport_js.new_cell([])
  let retry_statuses = transport_js.new_cell([])
  let _ =
    crdt_js.attach_with_rtc(
      imported,
      on_ready: fn(outcome) {
        push(retry_readies, case outcome {
          Ok(_) -> "ok"
          Error(error) -> "error " <> crdt_js.describe_error(error)
        })
      },
      on_status: fn(status) { push(retry_statuses, render(status)) },
      rtc: p2p_fake.rtc(world, crdt_js.replica_id(imported)),
    )
  let alpha = spawn(world, signaling, "alpha", p2p.pn_counter_root(), tag)
  p2p_fake.settle(world)

  entries(retry_readies) |> expect.to_equal(["ok"])
  entries(first_readies)
  |> expect.to_equal(["error signalingFailed · no signaling service"])
  entries(first_statuses)
  |> expect.to_equal([
    "joined " <> room,
    "failed signalingFailed · no signaling service",
  ])
  entries(retry_statuses)
  |> list.filter(fn(entry) { !string.starts_with(entry, "transport ") })
  |> expect.to_equal([
    "joined " <> room,
    "rosterKnown []",
    "ready",
    "peerReady alpha",
    "stateMerged alpha 1",
  ])
  crdt_js.readiness(imported) |> expect.to_equal(Some(Ok(Nil)))
  crdt_js.pn_counter_value(crdt_js.root(alpha.document))
  |> expect.to_equal(Ok(10))
  crdt_js.digest(alpha.document) |> expect.to_equal(crdt_js.digest(imported))
}

// ─────────────────────────────────────────────────────────────────────────────
// Closing
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn a_closed_document_refuses_reads_and_writes_test() -> Nil {
  let world = p2p_fake.new_world()
  let alpha =
    spawn(world, hub_signaling(new_hub()), "alpha", p2p.pn_counter_root(), tag)
  let root = crdt_js.root(alpha.document)
  let assert Ok(Nil) = crdt_js.pn_counter_update(root, 2)

  crdt_js.close(alpha.connection)
  p2p_fake.settle(world)

  crdt_js.is_closed(alpha.document) |> expect.to_be_true()
  crdt_js.pn_counter_update(root, 1)
  |> expect.to_equal(Error(p2p.DocumentClosed))
  crdt_js.pn_counter_value(root) |> expect.to_equal(Error(p2p.DocumentClosed))
  crdt_js.create_channel(alpha.document, p2p.or_set_root())
  |> expect.to_equal(Error(p2p.DocumentClosed))
  crdt_js.resolve_channel(alpha.document, p2p.pn_counter_root(), "root")
  |> expect.to_equal(Error(p2p.DocumentClosed))

  // Idempotent: a second close leaves signaling no second time.
  crdt_js.close(alpha.connection)
  p2p_fake.settle(world)
  tagged(alpha.statuses, "transport SignalingLeft")
  |> list.length
  |> expect.to_equal(1)
}

@target(javascript)
pub fn attaching_twice_is_refused_test() -> Nil {
  let world = p2p_fake.new_world()
  let hub = hub_signaling(new_hub())
  let alpha = spawn(world, hub, "alpha", p2p.pn_counter_root(), tag)
  let readies = transport_js.new_cell([])

  let _ =
    crdt_js.attach_with_rtc(
      alpha.document,
      on_ready: fn(outcome) {
        push(readies, case outcome {
          Ok(_) -> "ok"
          Error(error) -> "error " <> crdt_js.describe_error(error)
        })
      },
      on_status: fn(_status) { Nil },
      rtc: p2p_fake.rtc(world, crdt_js.replica_id(alpha.document)),
    )

  case entries(readies) {
    [entry] ->
      { string.contains(entry, "already attached") } |> expect.to_be_true()
    other -> panic as { "expected one refusal, got " <> string.inspect(other) }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Anti-entropy and partitions (P2P7)
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// Take stable handles onto the three registry channels a
/// `grocery_triptych` holds: the G-Set root, plus a 2P-Set and an OR-Set
/// resolved by the addresses their authors announced.
fn triptych(
  document: CrdtDocument(schema.GSetChannel),
  two_p_address: String,
  or_address: String,
) -> #(
  Handle(schema.GSetChannel),
  Handle(schema.TwoPSetChannel),
  Handle(schema.OrSetChannel),
) {
  let assert Ok(two_p) =
    crdt_js.resolve_channel(document, p2p.two_p_set_root(), two_p_address)
  let assert Ok(or) =
    crdt_js.resolve_channel(document, p2p.or_set_root(), or_address)
  #(crdt_js.root(document), two_p, or)
}

@target(javascript)
/// Read all three channels back through handles taken before a partition
/// and assert their converged membership, so the same handles that
/// survived the split are the ones proven correct after the repair.
fn expect_triptych(
  handles: #(
    Handle(schema.GSetChannel),
    Handle(schema.TwoPSetChannel),
    Handle(schema.OrSetChannel),
  ),
  grow: List(String),
  two_phase: List(String),
  observed: List(String),
) -> Nil {
  let #(g, two_p, or) = handles
  let assert Ok(grew) = crdt_js.g_set_values(g)
  grew |> list.sort(string.compare) |> expect.to_equal(grow)
  let assert Ok(two) = crdt_js.two_p_set_values(two_p)
  two |> list.sort(string.compare) |> expect.to_equal(two_phase)
  let assert Ok(obs) = crdt_js.or_set_values(or)
  obs |> list.sort(string.compare) |> expect.to_equal(observed)
}

@target(javascript)
/// Step the shared anti-entropy clock and settle the world until every
/// document shares a digest, or give up. One live coalesced flush per
/// document per interval, so a bounded number of intervals converges a
/// healed mesh; running out is a real failure, not a slow test.
fn drive_convergence(
  world: p2p_fake.World,
  clock: relay_fake.Clock,
  interval: Int,
  documents: List(CrdtDocument(root)),
  fuel: Int,
) -> Nil {
  let converged = case list.map(documents, crdt_js.digest) {
    [] -> True
    [first, ..rest] -> list.all(rest, fn(digest) { digest == first })
  }
  case converged, fuel {
    True, _ -> Nil
    False, 0 -> panic as "the mesh did not converge under anti-entropy"
    False, _ -> {
      relay_fake.advance(clock, interval)
      p2p_fake.settle(world)
      drive_convergence(world, clock, interval, documents, fuel - 1)
    }
  }
}

@target(javascript)
/// Step the clock a fixed number of intervals, settling after each. Unlike
/// `drive_convergence` this does not stop when the mesh agrees, so it
/// drives a one-shot anti-entropy timer to expiry and leaves the mesh
/// quiescent — the state a recurring heartbeat keeps beating in but a
/// per-merge timer falls silent in.
fn tick_intervals(
  world: p2p_fake.World,
  clock: relay_fake.Clock,
  interval: Int,
  times: Int,
) -> Nil {
  case times {
    0 -> Nil
    _ -> {
      relay_fake.advance(clock, interval)
      p2p_fake.settle(world)
      tick_intervals(world, clock, interval, times - 1)
    }
  }
}

@target(javascript)
/// The gate: a three-peer facade/transport mesh holding G-Set, 2P-Set and
/// OR-Set channels, split into two partitions, edited on both sides, then
/// healed on a single reconnected edge. Every peer reaches equal canonical
/// snapshots and digests — not only the two endpoints of the edge that
/// came back — and the handles and subscription taken before the split are
/// the ones read after it.
pub fn a_healed_edge_converges_every_peer_across_all_three_kinds_test() -> Nil {
  let world = p2p_fake.new_world()
  let clock = relay_fake.new_clock()
  let signaling = p2p_fake.signaling(world)
  let interval = crdt_js.default_anti_entropy_milliseconds

  let alpha =
    spawn_synced(world, signaling, "alpha", p2p.g_set_root(), tag, clock)
  let beta =
    spawn_synced(world, signaling, "beta", p2p.g_set_root(), tag, clock)
  let gamma =
    spawn_synced(world, signaling, "gamma", p2p.g_set_root(), tag, clock)
  p2p_fake.settle(world)

  let id_alpha = crdt_js.replica_id(alpha.document)
  let id_beta = crdt_js.replica_id(beta.document)
  let id_gamma = crdt_js.replica_id(gamma.document)

  // Two peers author a channel each in the same round: concurrent
  // creation the whole mesh must resolve.
  let assert Ok(pantry) =
    crdt_js.create_channel(alpha.document, p2p.two_p_set_root())
  let assert Ok(basket) =
    crdt_js.create_channel(gamma.document, p2p.or_set_root())
  p2p_fake.settle(world)
  let two_p_address = crdt_js.address(pantry)
  let or_address = crdt_js.address(basket)

  let alpha_handles = triptych(alpha.document, two_p_address, or_address)
  let beta_handles = triptych(beta.document, two_p_address, or_address)
  let gamma_handles = triptych(gamma.document, two_p_address, or_address)

  // A shared baseline, then flush it so the partition starts from an
  // agreed, quiet mesh.
  let assert Ok(Nil) = crdt_js.g_set_add(alpha_handles.0, "trip")
  drive_convergence(
    world,
    clock,
    interval,
    [alpha.document, beta.document, gamma.document],
    12,
  )

  // A subscription taken before the split. It must still fire for the
  // elements that arrive across the healed edge.
  let alpha_grew = transport_js.new_cell([])
  let _ =
    crdt_js.subscribe_g_set(alpha_handles.0, fn(event) {
      case event {
        g_set_kernel.ElementAdded(element) -> push(alpha_grew, element)
      }
    })

  // Split {alpha, beta} | {gamma} by cutting gamma from both.
  p2p_fake.sever(world, id_alpha, id_gamma)
  p2p_fake.sever(world, id_beta, id_gamma)
  p2p_fake.settle(world)
  crdt_js.peer_count(gamma.document) |> expect.to_equal(0)
  crdt_js.peer_count(alpha.document) |> expect.to_equal(1)
  crdt_js.peer_count(beta.document) |> expect.to_equal(1)

  // Both partitions stay writable. beta authors on its side, gamma on its
  // own, across all three kinds.
  let assert Ok(Nil) = crdt_js.g_set_add(beta_handles.0, "apples")
  let assert Ok(Nil) = crdt_js.two_p_set_add(beta_handles.1, "milk")
  let assert Ok(Nil) = crdt_js.or_set_add(beta_handles.2, "bread")
  let assert Ok(Nil) = crdt_js.g_set_add(gamma_handles.0, "oranges")
  let assert Ok(Nil) = crdt_js.two_p_set_add(gamma_handles.1, "eggs")
  let assert Ok(Nil) = crdt_js.or_set_add(gamma_handles.2, "butter")
  p2p_fake.settle(world)

  // The partitions really did diverge before the heal.
  { crdt_js.digest(alpha.document) == crdt_js.digest(beta.document) }
  |> expect.to_be_true()
  { crdt_js.digest(alpha.document) != crdt_js.digest(gamma.document) }
  |> expect.to_be_true()

  // Heal one edge only, then let anti-entropy carry the merge the rest of
  // the way.
  p2p_fake.reconnect(world, id_beta, id_gamma)
  p2p_fake.settle(world)
  drive_convergence(
    world,
    clock,
    interval,
    [alpha.document, beta.document, gamma.document],
    12,
  )

  // Equal canonical digests across every peer. The digest is the
  // canonical fingerprint: a raw snapshot still carries each replica's own
  // OR-Set tag seed, but the converged logical state is one digest.
  let converged = crdt_js.digest(alpha.document)
  crdt_js.digest(beta.document) |> expect.to_equal(converged)
  crdt_js.digest(gamma.document) |> expect.to_equal(converged)

  // Read back through the handles taken before the split.
  expect_triptych(
    alpha_handles,
    ["apples", "oranges", "trip"],
    ["eggs", "milk"],
    ["bread", "butter"],
  )
  expect_triptych(
    beta_handles,
    ["apples", "oranges", "trip"],
    ["eggs", "milk"],
    ["bread", "butter"],
  )
  expect_triptych(
    gamma_handles,
    ["apples", "oranges", "trip"],
    ["eggs", "milk"],
    ["bread", "butter"],
  )

  // The subscription survived: it saw the near element directly and the
  // far element once anti-entropy delivered it.
  entries(alpha_grew)
  |> list.sort(string.compare)
  |> expect.to_equal(["apples", "oranges"])

  // Identity, counters, and the healed topology are all preserved.
  crdt_js.replica_id(alpha.document) |> expect.to_equal(id_alpha)
  crdt_js.replica_id(beta.document) |> expect.to_equal(id_beta)
  crdt_js.replica_id(gamma.document) |> expect.to_equal(id_gamma)
  crdt_js.peer_count(beta.document) |> expect.to_equal(2)
  crdt_js.peer_count(alpha.document) |> expect.to_equal(1)
  crdt_js.peer_count(gamma.document) |> expect.to_equal(1)

  // Diagnostics: alpha was behind and repaired; a converged peer recorded
  // the digest it agreed on; the late joiner is bootstrapped.
  { crdt_js.repair_count(alpha.document) >= 1 } |> expect.to_be_true()
  crdt_js.last_digest_match(beta.document)
  |> expect.to_equal(Some(crdt_js.digest(beta.document)))
  crdt_js.bootstrap_state(gamma.document)
  |> expect.to_equal(crdt_js.Bootstrapped)
}

@target(javascript)
/// The regression the round-1 fix is for: canonical state can change with
/// no visible event, and the healed mesh must still carry it to a peer
/// that is not on the reconnected edge.
///
/// While `gamma` is partitioned it re-adds an element the OR-Set already
/// shows (a fresh tag under a value that stays visible) and adds then
/// removes a 2P-Set element (a tombstone under a value nobody else ever
/// saw). Merging either into a peer moves the lattice — and so the digest
/// — without changing the membership a subscriber observes, so it emits no
/// event. One edge is reconnected, `beta` to `gamma`; `alpha` is left on
/// the far side. No event-ful edit follows. Only the recurring heartbeat
/// can now reach `alpha`: an implementation that armed anti-entropy off
/// visible events would leave `alpha` behind forever. Advancing the
/// interval must converge all three, and `alpha` must count the catch-up
/// it pulled across the healed edge.
pub fn an_event_less_change_reaches_the_third_peer_across_a_healed_edge_test() -> Nil {
  let world = p2p_fake.new_world()
  let clock = relay_fake.new_clock()
  let signaling = p2p_fake.signaling(world)
  let interval = crdt_js.default_anti_entropy_milliseconds

  let alpha =
    spawn_synced(world, signaling, "alpha", p2p.g_set_root(), tag, clock)
  let beta =
    spawn_synced(world, signaling, "beta", p2p.g_set_root(), tag, clock)
  let gamma =
    spawn_synced(world, signaling, "gamma", p2p.g_set_root(), tag, clock)
  p2p_fake.settle(world)

  let id_alpha = crdt_js.replica_id(alpha.document)
  let id_gamma = crdt_js.replica_id(gamma.document)

  let assert Ok(pantry) =
    crdt_js.create_channel(alpha.document, p2p.two_p_set_root())
  let assert Ok(basket) =
    crdt_js.create_channel(gamma.document, p2p.or_set_root())
  p2p_fake.settle(world)
  let two_p_address = crdt_js.address(pantry)
  let or_address = crdt_js.address(basket)

  let alpha_handles = triptych(alpha.document, two_p_address, or_address)
  let beta_handles = triptych(beta.document, two_p_address, or_address)
  let gamma_handles = triptych(gamma.document, two_p_address, or_address)

  // A converged baseline: one OR-Set element every peer can see, and an
  // empty 2P-Set. The partition starts from an agreed, quiet mesh.
  let assert Ok(Nil) = crdt_js.or_set_add(alpha_handles.2, "shared")
  drive_convergence(
    world,
    clock,
    interval,
    [alpha.document, beta.document, gamma.document],
    12,
  )
  let baseline = crdt_js.digest(alpha.document)
  crdt_js.digest(beta.document) |> expect.to_equal(baseline)
  crdt_js.digest(gamma.document) |> expect.to_equal(baseline)

  // Beat the interval a few more times so the baseline leaves the mesh
  // quiescent. A per-merge timer has fired and fallen silent by now; a
  // recurring heartbeat is still beating. This is what the event-less
  // change below rides — or fails to.
  tick_intervals(world, clock, interval, 4)

  // Split {alpha, beta} | {gamma}. alpha will be the peer off the healed
  // edge.
  p2p_fake.sever(world, id_alpha, id_gamma)
  p2p_fake.sever(world, crdt_js.replica_id(beta.document), id_gamma)
  p2p_fake.settle(world)
  crdt_js.peer_count(gamma.document) |> expect.to_equal(0)

  // gamma makes two changes that are event-less once merged elsewhere: a
  // fresh OR-Set tag under the already-visible "shared", and a 2P-Set
  // element added then removed so it is only ever a tombstone.
  let assert Ok(Nil) = crdt_js.or_set_add(gamma_handles.2, "shared")
  let assert Ok(Nil) = crdt_js.two_p_set_add(gamma_handles.1, "temp")
  let assert Ok(Nil) = crdt_js.two_p_set_remove(gamma_handles.1, "temp")
  p2p_fake.settle(world)

  // The lattice really did diverge, though the membership did not: gamma's
  // digest now differs while alpha and beta hold the baseline.
  { crdt_js.digest(gamma.document) != baseline } |> expect.to_be_true()
  crdt_js.digest(alpha.document) |> expect.to_equal(baseline)
  crdt_js.digest(beta.document) |> expect.to_equal(baseline)

  // Heal one edge only: beta to gamma. beta merges gamma's event-less
  // change on the handshake — its digest moves, but the membership it
  // shows does not — while alpha, on the far side, is untouched and still
  // holds the baseline.
  let repairs_before = crdt_js.repair_count(alpha.document)
  p2p_fake.reconnect(world, crdt_js.replica_id(beta.document), id_gamma)
  p2p_fake.settle(world)
  { crdt_js.digest(beta.document) == crdt_js.digest(gamma.document) }
  |> expect.to_be_true()
  { crdt_js.digest(beta.document) != baseline } |> expect.to_be_true()
  crdt_js.digest(alpha.document) |> expect.to_equal(baseline)
  let assert Ok(beta_observed) = crdt_js.or_set_values(beta_handles.2)
  beta_observed |> expect.to_equal(["shared"])
  let assert Ok(beta_two_phase) = crdt_js.two_p_set_values(beta_handles.1)
  beta_two_phase |> expect.to_equal([])

  // No event-ful edit follows. Only the recurring heartbeat can carry the
  // event-less change from beta across to alpha; advancing the interval
  // must converge all three. A per-merge timer has nothing armed here and
  // never delivers it.
  drive_convergence(
    world,
    clock,
    interval,
    [alpha.document, beta.document, gamma.document],
    12,
  )
  let converged = crdt_js.digest(alpha.document)
  crdt_js.digest(beta.document) |> expect.to_equal(converged)
  crdt_js.digest(gamma.document) |> expect.to_equal(converged)

  // alpha pulled a fresh catch-up across the healed edge even though
  // nothing it can see changed: the repair count rose past where it stood
  // before the heal, and the membership is still exactly the baseline.
  { crdt_js.repair_count(alpha.document) > repairs_before }
  |> expect.to_be_true()
  expect_triptych(alpha_handles, [], [], ["shared"])
  expect_triptych(beta_handles, [], [], ["shared"])
  expect_triptych(gamma_handles, [], [], ["shared"])
}

@target(javascript)
/// re-arms itself every interval — exactly one live timer at a time, armed
/// the moment a peer is validated and not waiting on an edit. Local edits
/// fan out as their own deltas and ride the next beat rather than arming a
/// second timer. Each document is measured on its own clock, so the count
/// is the document's own and not the whole mesh's.
pub fn an_active_mesh_heartbeats_on_a_recurring_interval_test() -> Nil {
  let world = p2p_fake.new_world()
  let clock_alpha = relay_fake.new_clock()
  let clock_beta = relay_fake.new_clock()
  let signaling = p2p_fake.signaling(world)
  let alpha =
    spawn_synced(world, signaling, "alpha", p2p.g_set_root(), tag, clock_alpha)
  let _beta =
    spawn_synced(world, signaling, "beta", p2p.g_set_root(), tag, clock_beta)
  p2p_fake.settle(world)

  // The handshake validates a peer, so each side arms exactly one
  // heartbeat straight away — no edit required.
  relay_fake.armed(clock_alpha) |> expect.to_equal(1)
  relay_fake.delays(clock_alpha)
  |> expect.to_equal([crdt_js.default_anti_entropy_milliseconds])

  // The interval comes round: the beat fires and re-arms, so there is
  // still exactly one live timer and one more interval was requested.
  relay_fake.advance(clock_alpha, crdt_js.default_anti_entropy_milliseconds)
  p2p_fake.settle(world)
  relay_fake.armed(clock_alpha) |> expect.to_equal(1)
  relay_fake.delays(clock_alpha)
  |> expect.to_equal([
    crdt_js.default_anti_entropy_milliseconds,
    crdt_js.default_anti_entropy_milliseconds,
  ])

  // A second interval keeps the single timer recurring, not accumulating.
  relay_fake.advance(clock_alpha, crdt_js.default_anti_entropy_milliseconds)
  p2p_fake.settle(world)
  relay_fake.armed(clock_alpha) |> expect.to_equal(1)

  // Two edits in one interval ride the live beat; neither arms its own.
  let assert Ok(Nil) = crdt_js.g_set_add(crdt_js.root(alpha.document), "one")
  let assert Ok(Nil) = crdt_js.g_set_add(crdt_js.root(alpha.document), "two")
  p2p_fake.settle(world)
  relay_fake.armed(clock_alpha) |> expect.to_equal(1)
}

@target(javascript)
/// An idle mesh is a quiet mesh. The heartbeat timer keeps recurring, but
/// the broadcast is gated on the document having moved (or a mismatch
/// having been seen) since the digest last went out — so a converged,
/// untouched room costs one digest and then nothing, however many
/// intervals pass.
pub fn an_idle_document_does_not_keep_broadcasting_digests_test() -> Nil {
  let world = p2p_fake.new_world()
  let clock = relay_fake.new_clock()
  let hub = hub_signaling(new_hub())
  let alpha =
    spawn_synced(world, hub, "alpha", p2p.pn_counter_root(), tag, clock)
  // A raw peer records every payload it is sent, so "nothing further was
  // broadcast" is an assertion rather than an absence.
  let carol = raw_peer(world, hub, "carol")
  p2p_fake.settle(world)
  send_raw(
    carol,
    crdt_js.replica_id(alpha.document),
    crdt_core.encode(carol.document, crdt_core.hello_message(carol.document)),
  )
  p2p_fake.settle(world)

  // The first beat announces the digest once: nothing has gone out yet.
  relay_fake.advance(clock, crdt_js.default_anti_entropy_milliseconds)
  p2p_fake.settle(world)
  let after_first = list.length(entries(carol.received))

  // Ten more intervals over an untouched document: not one further byte,
  // while the timer itself keeps recurring.
  tick_intervals(world, clock, crdt_js.default_anti_entropy_milliseconds, 10)
  list.length(entries(carol.received)) |> expect.to_equal(after_first)
  relay_fake.armed(clock) |> expect.to_equal(1)

  // An edit moves the document, so the next beat speaks again — the gate
  // is on change, not a one-shot.
  let assert Ok(Nil) =
    crdt_js.pn_counter_update(crdt_js.root(alpha.document), 1)
  p2p_fake.settle(world)
  tick_intervals(world, clock, crdt_js.default_anti_entropy_milliseconds, 1)
  { list.length(entries(carol.received)) > after_first } |> expect.to_be_true()
  let after_edit = list.length(entries(carol.received))
  tick_intervals(world, clock, crdt_js.default_anti_entropy_milliseconds, 5)
  list.length(entries(carol.received)) |> expect.to_equal(after_edit)
}

@target(javascript)
/// When the last validated peer leaves, the heartbeat has nobody to tell
/// and cancels itself. The mesh goes quiet rather than beating into an
/// empty room, and the clock it armed on fires nothing thereafter.
pub fn the_last_validated_peer_leaving_cancels_the_heartbeat_test() -> Nil {
  let world = p2p_fake.new_world()
  let clock_alpha = relay_fake.new_clock()
  let clock_beta = relay_fake.new_clock()
  let signaling = p2p_fake.signaling(world)
  let alpha =
    spawn_synced(world, signaling, "alpha", p2p.g_set_root(), tag, clock_alpha)
  let beta =
    spawn_synced(world, signaling, "beta", p2p.g_set_root(), tag, clock_beta)
  p2p_fake.settle(world)
  relay_fake.armed(clock_alpha) |> expect.to_equal(1)
  relay_fake.armed(clock_beta) |> expect.to_equal(1)

  // Cut the one edge. Each side loses its only validated peer, so each
  // heartbeat cancels.
  p2p_fake.sever(
    world,
    crdt_js.replica_id(alpha.document),
    crdt_js.replica_id(beta.document),
  )
  p2p_fake.settle(world)
  relay_fake.armed(clock_alpha) |> expect.to_equal(0)
  relay_fake.armed(clock_beta) |> expect.to_equal(0)

  // A cancelled heartbeat stays cancelled: advancing the clock fires
  // nothing and arms nothing.
  relay_fake.advance(clock_alpha, crdt_js.default_anti_entropy_milliseconds)
  relay_fake.armed(clock_alpha) |> expect.to_equal(0)
}

@target(javascript)
/// Closing a document cancels the live heartbeat it armed, and the clock
/// it armed on fires nothing afterwards — a closed document is off the
/// mesh, not a timer that keeps waking.
pub fn closing_a_document_cancels_its_heartbeat_test() -> Nil {
  let world = p2p_fake.new_world()
  let clock_alpha = relay_fake.new_clock()
  let clock_beta = relay_fake.new_clock()
  let signaling = p2p_fake.signaling(world)
  let _alpha =
    spawn_synced(world, signaling, "alpha", p2p.g_set_root(), tag, clock_alpha)
  let beta =
    spawn_synced(world, signaling, "beta", p2p.g_set_root(), tag, clock_beta)
  p2p_fake.settle(world)
  relay_fake.armed(clock_beta) |> expect.to_equal(1)

  // Closing beta cancels the timer it armed.
  crdt_js.close(beta.connection)
  relay_fake.armed(clock_beta) |> expect.to_equal(0)

  // The closed document's clock fires nothing when it advances.
  relay_fake.advance(clock_beta, crdt_js.default_anti_entropy_milliseconds)
  relay_fake.armed(clock_beta) |> expect.to_equal(0)
}

@target(javascript)
/// A scheduler that runs its action the instant it is handed one — a
/// synchronous fake, or a pathological real timer — fires the heartbeat
/// exactly once and does not re-arm, so it cannot spin. The guard is the
/// canceller not yet being stored when the inline tick reads it: the tick
/// sees no live timer, sends one digest, and lapses instead of recursing.
pub fn a_synchronous_scheduler_fires_one_heartbeat_without_looping_test() -> Nil {
  let world = p2p_fake.new_world()
  let hub = hub_signaling(new_hub())
  let calls = transport_js.new_cell(0)
  let inline =
    transport_js.Scheduler(
      now_milliseconds: fn() { 0 },
      schedule: fn(action, _delay) {
        transport_js.set_cell(calls, transport_js.get_cell(calls) + 1)
        action()
        fn() { Nil }
      },
    )

  let assert Ok(alpha) =
    crdt_js.new_document(
      crdt_js.config(
        room_id: room,
        replica_label: "alpha",
        compatibility_tag: tag,
        root: p2p.pn_counter_root(),
        signaling: hub,
      )
      |> crdt_js.with_scheduler(inline),
    )
  let _ =
    crdt_js.attach_with_rtc(
      alpha,
      on_ready: fn(_outcome) { Nil },
      on_status: fn(_status) { Nil },
      rtc: p2p_fake.rtc(world, crdt_js.replica_id(alpha)),
    )
  let beta = raw_peer(world, hub, "beta")
  p2p_fake.settle(world)

  // beta greets alpha. Validating it arms the heartbeat, and the inline
  // scheduler ticks in place: one digest goes out, and it does not re-arm,
  // so the schedule count is bounded rather than spinning.
  send_raw(
    beta,
    crdt_js.replica_id(alpha),
    crdt_core.encode(beta.document, crdt_core.hello_message(beta.document)),
  )
  p2p_fake.settle(world)

  { transport_js.get_cell(calls) >= 1 } |> expect.to_be_true()
  { transport_js.get_cell(calls) < 8 } |> expect.to_be_true()
  crdt_js.peer_count(alpha) |> expect.to_equal(1)
}

@target(javascript)
/// A document with no validated peer fans its edits out to nobody and owes
/// nobody a digest, so it never touches the scheduler — no busy loop, no
/// idle chatter.
pub fn a_lone_mesh_document_never_arms_a_digest_test() -> Nil {
  let world = p2p_fake.new_world()
  let clock = relay_fake.new_clock()
  let alpha =
    spawn_synced(
      world,
      p2p_fake.signaling(world),
      "alpha",
      p2p.g_set_root(),
      tag,
      clock,
    )
  p2p_fake.settle(world)

  let assert Ok(Nil) = crdt_js.g_set_add(crdt_js.root(alpha.document), "alone")
  p2p_fake.settle(world)

  relay_fake.armed(clock) |> expect.to_equal(0)
  relay_fake.delays(clock) |> expect.to_equal([])
  crdt_js.repair_count(alpha.document) |> expect.to_equal(0)
  crdt_js.last_digest_match(alpha.document) |> expect.to_equal(None)
}

@target(javascript)
/// A peer whose digest matches records it as the last successful
/// comparison and counts no repair.
pub fn a_matching_digest_is_recorded_without_a_repair_test() -> Nil {
  let world = p2p_fake.new_world()
  let clock = relay_fake.new_clock()
  let signaling = p2p_fake.signaling(world)
  let alpha =
    spawn_synced(world, signaling, "alpha", p2p.g_set_root(), tag, clock)
  let _beta =
    spawn_synced(world, signaling, "beta", p2p.g_set_root(), tag, clock)
  p2p_fake.settle(world)

  let assert Ok(Nil) = crdt_js.g_set_add(crdt_js.root(alpha.document), "agree")
  p2p_fake.settle(world)

  // beta arms after merging alpha's delta; the digest it sends back is one
  // alpha already agrees with.
  relay_fake.advance(clock, crdt_js.default_anti_entropy_milliseconds)
  p2p_fake.settle(world)

  crdt_js.last_digest_match(alpha.document)
  |> expect.to_equal(Some(crdt_js.digest(alpha.document)))
  crdt_js.repair_count(alpha.document) |> expect.to_equal(0)
}

@target(javascript)
/// A peer left behind a merge it never saw counts the repair when a
/// digest tells it so, and catches up on the existing state path.
pub fn a_lagging_peer_counts_the_repair_it_pulls_test() -> Nil {
  let world = p2p_fake.new_world()
  let clock = relay_fake.new_clock()
  let signaling = p2p_fake.signaling(world)
  let alpha =
    spawn_synced(world, signaling, "alpha", p2p.g_set_root(), tag, clock)
  let beta =
    spawn_synced(world, signaling, "beta", p2p.g_set_root(), tag, clock)
  let gamma =
    spawn_synced(world, signaling, "gamma", p2p.g_set_root(), tag, clock)
  p2p_fake.settle(world)

  // Cut alpha off from gamma. gamma edits; beta hears it directly, alpha
  // does not, and a merge is not re-fanned, so alpha lags.
  p2p_fake.sever(
    world,
    crdt_js.replica_id(alpha.document),
    crdt_js.replica_id(gamma.document),
  )
  p2p_fake.settle(world)
  let assert Ok(Nil) = crdt_js.g_set_add(crdt_js.root(gamma.document), "late")
  p2p_fake.settle(world)
  crdt_js.repair_count(alpha.document) |> expect.to_equal(0)

  drive_convergence(
    world,
    clock,
    crdt_js.default_anti_entropy_milliseconds,
    [alpha.document, beta.document, gamma.document],
    12,
  )

  { crdt_js.repair_count(alpha.document) >= 1 } |> expect.to_be_true()
  crdt_js.g_set_values(crdt_js.root(alpha.document))
  |> expect.to_equal(Ok(["late"]))
}

@target(javascript)
/// A repair is a completed catch-up, not a request. A digest that says
/// this replica is behind arms a `stateRequest`, but until the state comes
/// back and actually moves the document nothing is repaired — so a request
/// that is never answered counts nothing, and a redundant answer that
/// changes nothing counts nothing either.
pub fn a_digest_that_is_never_answered_counts_no_repair_test() -> Nil {
  let world = p2p_fake.new_world()
  let hub = hub_signaling(new_hub())
  let alpha = spawn(world, hub, "alpha", p2p.pn_counter_root(), tag)
  let raw = raw_peer(world, hub, "carol")
  p2p_fake.settle(world)

  let target = crdt_js.replica_id(alpha.document)

  // A clean handshake on empty state: the two agree, so no repair and a
  // recorded match.
  send_raw(
    raw,
    target,
    crdt_core.encode(raw.document, crdt_core.hello_message(raw.document)),
  )
  p2p_fake.settle(world)
  crdt_js.repair_count(alpha.document) |> expect.to_equal(0)

  // carol moves its own state but never fans the delta. Its digest now
  // disagrees with alpha's.
  let #(raw_ahead, _withheld) = raw_delta(raw.document, 6)
  send_raw(
    raw,
    target,
    crdt_core.encode(raw_ahead, crdt_core.digest_message(raw_ahead)),
  )
  p2p_fake.settle(world)

  // alpha saw the mismatch and asked for state, but carol answers nothing.
  // No state arrives, so no repair is counted and no match is recorded.
  crdt_js.repair_count(alpha.document) |> expect.to_equal(0)
  crdt_js.last_digest_match(alpha.document) |> expect.to_equal(None)
  crdt_js.pn_counter_value(crdt_js.root(alpha.document))
  |> expect.to_equal(Ok(0))
}

@target(javascript)
/// A peer that boots from an imported snapshot carries that state into the
/// mesh: it reaches a peer on the handshake exchange, and anti-entropy
/// keeps the two converged.
pub fn an_imported_snapshot_reaches_the_mesh_test() -> Nil {
  let world = p2p_fake.new_world()
  let clock = relay_fake.new_clock()
  let signaling = p2p_fake.signaling(world)

  // Build a snapshot off to the side: a G-Set root with an element and a
  // created OR-Set channel carrying one of its own.
  let assert Ok(source) =
    crdt_js.new_document(crdt_js.config(
      room_id: room,
      replica_label: "source",
      compatibility_tag: tag,
      root: p2p.g_set_root(),
      signaling: signaling,
    ))
  let assert Ok(Nil) = crdt_js.g_set_add(crdt_js.root(source), "packed")
  let assert Ok(basket) = crdt_js.create_channel(source, p2p.or_set_root())
  let assert Ok(Nil) = crdt_js.or_set_add(basket, "apples")
  let basket_address = crdt_js.address(basket)
  let assert Ok(snapshot) = crdt_js.export_snapshot(source)

  // A peer boots from that snapshot and attaches into a fresh mesh.
  let assert Ok(imported) =
    crdt_js.import_snapshot(
      crdt_js.config(
        room_id: room,
        replica_label: "beta",
        compatibility_tag: tag,
        root: p2p.g_set_root(),
        signaling: signaling,
      )
        |> crdt_js.with_scheduler(relay_fake.scheduler(clock)),
      snapshot,
    )
  let _ =
    crdt_js.attach_with_rtc(
      imported,
      on_ready: fn(_outcome) { Nil },
      on_status: fn(_status) { Nil },
      rtc: p2p_fake.rtc(world, crdt_js.replica_id(imported)),
    )
  let alpha =
    spawn_synced(world, signaling, "alpha", p2p.g_set_root(), tag, clock)
  p2p_fake.settle(world)

  drive_convergence(
    world,
    clock,
    crdt_js.default_anti_entropy_milliseconds,
    [imported, alpha.document],
    12,
  )

  crdt_js.digest(alpha.document) |> expect.to_equal(crdt_js.digest(imported))
  crdt_js.g_set_values(crdt_js.root(alpha.document))
  |> expect.to_equal(Ok(["packed"]))
  let assert Ok(alpha_basket) =
    crdt_js.resolve_channel(alpha.document, p2p.or_set_root(), basket_address)
  crdt_js.or_set_values(alpha_basket) |> expect.to_equal(Ok(["apples"]))
}

// ─────────────────────────────────────────────────────────────────────────────
// The canonical digest, computed once per document state
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// An idle mesh does not re-canonicalize and re-hash the document to say
/// the same thing.
///
/// The heartbeat asks for a digest every interval, and every peer's
/// heartbeat arrives here to be compared against one. In a settled room
/// that is `peers + 1` full hashes of the whole document per interval,
/// forever, for a document nobody is editing. The count is the evidence:
/// a quiescent document hashes itself once and every digest after that is
/// the same answer.
pub fn an_idle_mesh_hashes_the_document_once_test() -> Nil {
  let world = p2p_fake.new_world()
  let clock = relay_fake.new_clock()
  let signaling = p2p_fake.signaling(world)
  let interval = crdt_js.default_anti_entropy_milliseconds
  let alpha =
    spawn_synced(world, signaling, "alpha", p2p.g_set_root(), tag, clock)
  let beta =
    spawn_synced(world, signaling, "beta", p2p.g_set_root(), tag, clock)
  let gamma =
    spawn_synced(world, signaling, "gamma", p2p.g_set_root(), tag, clock)
  p2p_fake.settle(world)
  crdt_js.peer_count(alpha.document) |> expect.to_equal(2)

  // One answer, however many ask for it.
  let digest = crdt_js.digest(alpha.document)
  let once = crdt_js.digest_computations(alpha.document)
  crdt_js.digest(alpha.document) |> expect.to_equal(digest)
  crdt_js.digest_computations(alpha.document) |> expect.to_equal(once)

  // Ten intervals against a document that has not moved: the beats after
  // the first broadcast nothing, and nothing hashes anything new.
  tick_intervals(world, clock, interval, 10)
  crdt_js.digest_computations(alpha.document) |> expect.to_equal(once)
  crdt_js.digest(alpha.document) |> expect.to_equal(digest)
  crdt_js.digest_computations(alpha.document) |> expect.to_equal(once)

  // A local edit moves the document. It hashes nothing by itself — the
  // delta is what fans out — and the next heartbeat hashes once.
  let assert Ok(Nil) = crdt_js.g_set_add(crdt_js.root(alpha.document), "tent")
  p2p_fake.settle(world)
  crdt_js.digest_computations(alpha.document) |> expect.to_equal(once)
  tick_intervals(world, clock, interval, 1)
  crdt_js.digest_computations(alpha.document) |> expect.to_equal(once + 1)
  tick_intervals(world, clock, interval, 5)
  crdt_js.digest_computations(alpha.document) |> expect.to_equal(once + 1)
  crdt_js.digest(alpha.document) |> expect.to_not_equal(digest)

  // A merge learned from a peer is the same rule from the other side: the
  // merge itself hashes nothing, and the heartbeat after it hashes once.
  let assert Ok(Nil) = crdt_js.g_set_add(crdt_js.root(beta.document), "map")
  p2p_fake.settle(world)
  crdt_js.digest_computations(alpha.document) |> expect.to_equal(once + 1)
  tick_intervals(world, clock, interval, 1)
  crdt_js.digest_computations(alpha.document) |> expect.to_equal(once + 2)
  tick_intervals(world, clock, interval, 4)
  crdt_js.digest_computations(alpha.document) |> expect.to_equal(once + 2)

  // And the cache never stood in for a state this replica did not hold:
  // every peer agrees on the value and on the digest.
  crdt_js.g_set_values(crdt_js.root(alpha.document))
  |> expect.to_equal(Ok(["map", "tent"]))
  crdt_js.digest(gamma.document)
  |> expect.to_equal(crdt_js.digest(alpha.document))
  crdt_js.digest(beta.document)
  |> expect.to_equal(crdt_js.digest(alpha.document))
}

@target(javascript)
/// A cached digest cannot suppress a repair.
///
/// The mesh repairs by comparing digests, so a stale one is not a slow
/// path — it is a peer that answers "we agree" about a state it no longer
/// holds and never converges. Here the lagging peer's every canonical
/// change is event-less on purpose: a 2P-Set tombstone for an element it
/// never saw added, and an OR-Set removal, neither of which changes the
/// membership a subscriber sees. The repair count and the equal digests
/// are what say the comparison was made against the document as it is.
pub fn a_cached_digest_still_repairs_an_event_less_change_test() -> Nil {
  let world = p2p_fake.new_world()
  let clock = relay_fake.new_clock()
  let signaling = p2p_fake.signaling(world)
  let interval = crdt_js.default_anti_entropy_milliseconds
  let alpha =
    spawn_synced(world, signaling, "alpha", p2p.two_p_set_root(), tag, clock)
  let beta =
    spawn_synced(world, signaling, "beta", p2p.two_p_set_root(), tag, clock)
  p2p_fake.settle(world)

  // Both sides hash themselves at their first heartbeat, and agree.
  tick_intervals(world, clock, interval, 1)
  crdt_js.digest(beta.document)
  |> expect.to_equal(crdt_js.digest(alpha.document))
  let hashes = crdt_js.digest_computations(beta.document)

  // Cut the edge, and remove on one side an element neither side ever
  // added: a tombstone, so the lattice moves and the membership does not.
  p2p_fake.sever(
    world,
    crdt_js.replica_id(alpha.document),
    crdt_js.replica_id(beta.document),
  )
  p2p_fake.settle(world)
  let assert Ok(Nil) =
    crdt_js.two_p_set_remove(crdt_js.root(alpha.document), "ghost")
  p2p_fake.settle(world)
  crdt_js.two_p_set_values(crdt_js.root(alpha.document))
  |> expect.to_equal(Ok([]))
  crdt_js.digest(alpha.document)
  |> expect.to_not_equal(crdt_js.digest(beta.document))

  // Heal it. Nothing about the merge is visible to a subscriber, so the
  // digests are the only thing that can carry it — and they do.
  p2p_fake.reconnect(
    world,
    crdt_js.replica_id(alpha.document),
    crdt_js.replica_id(beta.document),
  )
  p2p_fake.settle(world)
  drive_convergence(world, clock, interval, [alpha.document, beta.document], 12)
  crdt_js.digest(beta.document)
  |> expect.to_equal(crdt_js.digest(alpha.document))
  { crdt_js.repair_count(beta.document) >= 1 } |> expect.to_be_true()
  // The repair is a state change, so the digest behind it was recomputed
  // rather than served from the cache the comparison started with.
  { crdt_js.digest_computations(beta.document) > hashes }
  |> expect.to_be_true()
}

@target(javascript)
/// An imported snapshot carries no digest with it, and cannot be answered
/// from one. The document is new, so its first digest is computed from
/// what it imported and every one after that is reused.
pub fn an_imported_snapshot_hashes_itself_once_test() -> Nil {
  let world = p2p_fake.new_world()
  let signaling = p2p_fake.signaling(world)
  let assert Ok(source) =
    crdt_js.new_document(crdt_js.config(
      room_id: room,
      replica_label: "source",
      compatibility_tag: tag,
      root: p2p.g_set_root(),
      signaling: signaling,
    ))
  let empty = crdt_js.digest(source)
  let assert Ok(Nil) = crdt_js.g_set_add(crdt_js.root(source), "packed")
  crdt_js.digest(source) |> expect.to_not_equal(empty)
  crdt_js.digest_computations(source) |> expect.to_equal(2)
  let assert Ok(snapshot) = crdt_js.export_snapshot(source)

  let assert Ok(imported) =
    crdt_js.import_snapshot(
      crdt_js.config(
        room_id: room,
        replica_label: "beta",
        compatibility_tag: tag,
        root: p2p.g_set_root(),
        signaling: signaling,
      ),
      snapshot,
    )
  // Nothing has been hashed yet: importing does not pay for a digest
  // nobody asked for.
  crdt_js.digest_computations(imported) |> expect.to_equal(0)
  crdt_js.digest(imported) |> expect.to_equal(crdt_js.digest(source))
  crdt_js.digest_computations(imported) |> expect.to_equal(1)
  crdt_js.digest(imported) |> expect.to_equal(crdt_js.digest(source))
  crdt_js.digest_computations(imported) |> expect.to_equal(1)
}

// ─────────────────────────────────────────────────────────────────────────────
// A peer that is not a facade
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
type RawPeer {
  RawPeer(
    transport: Transport,
    document: crdt_core.Document,
    received: Cell(List(String)),
  )
}

@target(javascript)
/// A bare transport speaking `crdt_wire` by hand, so the facade's trust
/// boundary can be tested against a peer the facade did not write.
fn raw_peer(
  world: p2p_fake.World,
  signaling: Signaling,
  peer_id: String,
) -> RawPeer {
  let received = transport_js.new_cell([])
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
      signaling: signaling,
      ice_servers: [],
      callbacks: Callbacks(
        on_peer_open: fn(_peer) { Nil },
        on_peer_close: fn(_peer) { Nil },
        on_document: fn(_peer, payload) { push(received, payload) },
        on_status: fn(_status) { Nil },
        on_error: fn(_error) { Nil },
      ),
      rtc: p2p_fake.rtc(world, peer_id),
    )
  RawPeer(transport: transport, document: document, received: received)
}

@target(javascript)
fn send_raw(peer: RawPeer, to: String, payload: String) -> Nil {
  let _ = p2p_transport_js.send(peer.transport, to, payload)
  Nil
}

@target(javascript)
/// One authored delta, encoded, plus the document that authored it.
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
