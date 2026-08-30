//// The typed half of the reference relay's integration test.
////
//// `tools/relay/test.mjs` owns the processes — it starts and stops the
//// real relay and the real signaling service, and it owns the temporary
//// directory the relay writes to. This module owns the documents: it
//// builds real `crdt_js` connections over a real `crdt_sequencer_js`
//// socket and hands JavaScript a handful of plain values to assert on.
////
//// The one thing that is not real is `RTCPeerConnection`, because Node
//// has none. Peer connections come from `p2p_fake`; *signaling* is the
//// real service over a real socket, which is what makes "signaling never
//// carried a document frame" a claim about the shipped service rather
//// than about a fake. The data channels underneath it carry the same
//// `crdt_wire` envelopes a browser's would, and the browser gate
//// (`just p2p-clap`) is what proves the real ones do too.
////
//// JavaScript target only, and a test harness rather than a library.

@target(javascript)
import gleam/int
@target(javascript)
import gleam/json
@target(javascript)
import gleam/list
@target(javascript)
import gleam/string

@target(javascript)
import watershed/crdt_js.{
  type CrdtConnection, type CrdtDocument, type Status, Auto, P2pOnly, PeerToPeer,
  Sequenced, SequencedOnly,
}
@target(javascript)
import watershed/crdt_signaling_js
@target(javascript)
import watershed/p2p
@target(javascript)
import watershed/p2p_fake
@target(javascript)
import watershed/pn_counter_kernel
@target(javascript)
import watershed/schema
@target(javascript)
import watershed/transport_js.{type Cell}

@target(javascript)
const compatibility = "relay-integration/v1"

@target(javascript)
pub type Harness {
  Harness(world: p2p_fake.World)
}

@target(javascript)
pub fn new_harness() -> Harness {
  Harness(world: p2p_fake.new_world())
}

@target(javascript)
/// Run every queued browser effect. The fake mesh is an effect queue, so
/// a caller that has just delivered a signal steps it here.
pub fn settle(harness: Harness) -> Nil {
  p2p_fake.settle(harness.world)
}

@target(javascript)
pub type Client {
  Client(
    document: CrdtDocument(schema.PnCounterChannel),
    connection: CrdtConnection,
    statuses: Cell(List(String)),
    readies: Cell(List(String)),
    events: Cell(List(String)),
  )
}

@target(javascript)
/// Build and attach one document.
///
/// `policy` is `auto`, `sequencedOnly`, or `p2pOnly`; `relay_url` empty
/// means no sequencer is configured at all, which is the "relay process
/// absent" case the scenario opens with.
pub fn start(
  harness: Harness,
  policy: String,
  room: String,
  label: String,
  signaling_url: String,
  relay_url: String,
) -> Client {
  start_with_deadline(
    harness,
    policy,
    room,
    label,
    signaling_url,
    relay_url,
    crdt_js.default_readiness_deadline_milliseconds,
  )
}

@target(javascript)
/// The same, with `SequencedOnly`'s readiness deadline named.
///
/// A room whose durable log holds a thousand records a client cannot
/// merge takes a measurable while to attach to: every one of them is
/// replayed, refused and reported, and the relay bounds its lane a record
/// at a time as the refusals arrive. That is a real cost of the flood
/// rather than of this test, and a deployment's answer to it is this
/// number — which is why it is configuration and why a test that means to
/// prove the room comes up at all sets it rather than racing it.
pub fn start_with_deadline(
  harness: Harness,
  policy: String,
  room: String,
  label: String,
  signaling_url: String,
  relay_url: String,
  deadline_milliseconds: Int,
) -> Client {
  let signaling =
    crdt_signaling_js.websocket_signaling(
      url: signaling_url,
      on_failure: fn(_detail) { Nil },
    )
  let base =
    crdt_js.config(
      room_id: room,
      replica_label: label,
      compatibility_tag: compatibility,
      root: p2p.pn_counter_root(),
      signaling: signaling,
    )
    |> crdt_js.with_transport_policy(case policy {
      "sequencedOnly" -> SequencedOnly
      "p2pOnly" -> P2pOnly
      _ -> Auto
    })
  let config = case relay_url {
    "" -> base
    url ->
      crdt_js.with_sequencer(
        base,
        crdt_js.sequencer(url)
          |> crdt_js.with_readiness_deadline_milliseconds(deadline_milliseconds),
      )
  }
  let assert Ok(document) = crdt_js.new_document(config)
  let statuses = transport_js.new_cell([])
  let readies = transport_js.new_cell([])
  let events = transport_js.new_cell([])
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
      rtc: p2p_fake.rtc(harness.world, crdt_js.replica_id(document)),
    )
  let _ =
    crdt_js.subscribe_pn_counter(crdt_js.root(document), fn(event) {
      let pn_counter_kernel.Updated(applied, total) = event
      push(events, int.to_string(applied) <> "->" <> int.to_string(total))
    })
  Client(
    document: document,
    connection: connection,
    statuses: statuses,
    readies: readies,
    events: events,
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
pub fn clap(client: Client, amount: Int) -> String {
  case crdt_js.pn_counter_update(crdt_js.root(client.document), amount) {
    Ok(Nil) -> ""
    Error(error) -> crdt_js.describe_error(error)
  }
}

@target(javascript)
pub fn value(client: Client) -> Int {
  case crdt_js.pn_counter_value(crdt_js.root(client.document)) {
    Ok(total) -> total
    Error(_) -> -1
  }
}

@target(javascript)
pub fn digest(client: Client) -> String {
  crdt_js.digest(client.document)
}

@target(javascript)
pub fn snapshot(client: Client) -> String {
  case crdt_js.export_snapshot(client.document) {
    Ok(value) -> json.to_string(value)
    Error(error) -> "error " <> crdt_js.describe_error(error)
  }
}

@target(javascript)
pub fn path(client: Client) -> String {
  case crdt_js.effective_path(client.document) {
    PeerToPeer -> "p2p"
    Sequenced -> "relay"
  }
}

@target(javascript)
pub fn is_primary(client: Client) -> Bool {
  crdt_js.relay_is_primary(client.document)
}

@target(javascript)
pub fn readiness(client: Client) -> List(String) {
  entries(client.readies)
}

@target(javascript)
pub fn statuses(client: Client) -> List(String) {
  entries(client.statuses)
}

@target(javascript)
pub fn subscriber_events(client: Client) -> List(String) {
  entries(client.events)
}

@target(javascript)
pub fn replica(client: Client) -> String {
  crdt_js.replica_id(client.document)
}

@target(javascript)
pub fn addresses(client: Client) -> List(String) {
  crdt_js.addresses(client.document)
}

@target(javascript)
pub fn peer_count(client: Client) -> Int {
  crdt_js.peer_count(client.document)
}

@target(javascript)
pub fn is_closed(client: Client) -> Bool {
  crdt_js.is_closed(client.document)
}

@target(javascript)
pub fn close(client: Client) -> Nil {
  crdt_js.close(client.connection)
}

@target(javascript)
fn render(status: Status) -> String {
  case status {
    crdt_js.Transport(_) -> "transport"
    crdt_js.TransportError(error) ->
      "transportError " <> crdt_js.describe_error(error)
    crdt_js.Joined(room, _replica) -> "joined " <> room
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
/// Whether any status this client reported starts with `prefix`.
pub fn saw(client: Client, prefix: String) -> Bool {
  list.any(entries(client.statuses), fn(entry) {
    string.starts_with(entry, prefix)
  })
}
