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
import gleam/option.{None, Some}
@target(javascript)
import gleam/result
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
import watershed/lww_map_kernel
@target(javascript)
import watershed/lww_register_kernel
@target(javascript)
import watershed/or_map_kernel
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
import watershed/wire

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
pub fn create_mv_or_map(client: Client) -> String {
  case
    crdt_js.create_channel(
      client.document,
      p2p.or_map_root(or_map_kernel.MvRegisterMode),
    )
  {
    Ok(handle) -> crdt_js.address(handle)
    Error(error) -> "error " <> crdt_js.describe_error(error)
  }
}

@target(javascript)
pub fn mv_or_map_set(
  client: Client,
  address: String,
  key: String,
  value: String,
) -> String {
  let outcome = {
    use handle <- result.try(crdt_js.resolve_channel(
      client.document,
      p2p.or_map_root(or_map_kernel.MvRegisterMode),
      address,
    ))
    crdt_js.or_map_set_mv_register(handle, key, value)
  }
  case outcome {
    Ok(Nil) -> ""
    Error(error) -> crdt_js.describe_error(error)
  }
}

@target(javascript)
pub fn mv_or_map_values(
  client: Client,
  address: String,
  key: String,
) -> String {
  let outcome = {
    use handle <- result.try(crdt_js.resolve_channel(
      client.document,
      p2p.or_map_root(or_map_kernel.MvRegisterMode),
      address,
    ))
    crdt_js.or_map_values(handle, key)
  }
  case outcome {
    Ok(Ok(values)) -> json.array(values, json.string) |> json.to_string
    Ok(Error(Nil)) -> "error absent key"
    Error(error) -> "error " <> crdt_js.describe_error(error)
  }
}

@target(javascript)
pub fn merge_snapshot(client: Client, source: String) -> String {
  case json.parse(source, wire.json_value_decoder()) {
    Error(_) -> "invalid snapshot JSON"
    Ok(snapshot) ->
      case crdt_js.merge_snapshot(client.document, snapshot) {
        Ok(_) -> ""
        Error(error) -> crdt_js.describe_error(error)
      }
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

@target(javascript)
pub type LwwClient {
  LwwClient(
    document: CrdtDocument(schema.LwwRegisterChannel),
    connection: CrdtConnection,
    statuses: Cell(List(String)),
    readies: Cell(List(String)),
    events: Cell(List(String)),
  )
}

@target(javascript)
pub fn start_lww(
  harness: Harness,
  policy: String,
  room: String,
  label: String,
  signaling_url: String,
  relay_url: String,
) -> LwwClient {
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
      root: p2p.lww_register_root(),
      signaling: signaling,
    )
    |> crdt_js.with_transport_policy(case policy {
      "sequencedOnly" -> SequencedOnly
      "p2pOnly" -> P2pOnly
      _ -> Auto
    })
  let config = case relay_url {
    "" -> base
    url -> crdt_js.with_sequencer(base, crdt_js.sequencer(url))
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
    crdt_js.subscribe_lww_register(crdt_js.root(document), fn(event) {
      let lww_register_kernel.Changed(previous, value) = event
      push(events, previous <> "->" <> value)
    })
  LwwClient(
    document: document,
    connection: connection,
    statuses: statuses,
    readies: readies,
    events: events,
  )
}

@target(javascript)
pub fn lww_set(client: LwwClient, value: String) -> String {
  case crdt_js.lww_register_set(crdt_js.root(client.document), value) {
    Ok(Nil) -> ""
    Error(error) -> crdt_js.describe_error(error)
  }
}

@target(javascript)
pub fn lww_value(client: LwwClient) -> String {
  case crdt_js.lww_register_value(crdt_js.root(client.document)) {
    Ok(value) -> value
    Error(error) -> "error " <> crdt_js.describe_error(error)
  }
}

@target(javascript)
pub fn lww_digest(client: LwwClient) -> String {
  crdt_js.digest(client.document)
}

@target(javascript)
pub fn lww_events(client: LwwClient) -> List(String) {
  entries(client.events)
}

@target(javascript)
pub fn lww_readiness(client: LwwClient) -> List(String) {
  entries(client.readies)
}

@target(javascript)
pub fn lww_path(client: LwwClient) -> String {
  case crdt_js.effective_path(client.document) {
    PeerToPeer -> "p2p"
    Sequenced -> "relay"
  }
}

@target(javascript)
pub fn lww_is_primary(client: LwwClient) -> Bool {
  crdt_js.relay_is_primary(client.document)
}

@target(javascript)
pub fn lww_peer_count(client: LwwClient) -> Int {
  crdt_js.peer_count(client.document)
}

@target(javascript)
pub fn lww_close(client: LwwClient) -> Nil {
  crdt_js.close(client.connection)
}

@target(javascript)
pub type SetMapClient {
  SetMapClient(
    document: CrdtDocument(schema.OrMapChannel),
    connection: CrdtConnection,
    readies: Cell(List(String)),
    events: Cell(List(or_map_kernel.OrMapEvent)),
  )
}

@target(javascript)
pub type LwwMapClient {
  LwwMapClient(
    document: CrdtDocument(schema.LwwMapChannel),
    connection: CrdtConnection,
    readies: Cell(List(String)),
    events: Cell(List(String)),
  )
}

@target(javascript)
pub fn start_set_map(
  harness: Harness,
  policy: String,
  room: String,
  label: String,
  signaling_url: String,
  relay_url: String,
) -> SetMapClient {
  let config =
    crdt_js.config(
      room_id: room,
      replica_label: label,
      compatibility_tag: "relay-set-map/v1",
      root: p2p.or_map_root(or_map_kernel.OrSetMode),
      signaling: crdt_signaling_js.websocket_signaling(
        url: signaling_url,
        on_failure: fn(detail) { panic as detail },
      ),
    )
    |> crdt_js.with_transport_policy(case policy {
      "sequencedOnly" -> SequencedOnly
      "auto" -> Auto
      _ -> panic as "unsupported set-map test policy"
    })
    |> crdt_js.with_sequencer(crdt_js.sequencer(relay_url))
  let assert Ok(document) = crdt_js.new_document(config)
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
      on_status: fn(_) { Nil },
      rtc: p2p_fake.rtc(harness.world, crdt_js.replica_id(document)),
    )
  let _ =
    crdt_js.subscribe_or_map(crdt_js.root(document), fn(event) {
      transport_js.set_cell(events, [event, ..transport_js.get_cell(events)])
    })
  SetMapClient(document:, connection:, readies:, events:)
}

@target(javascript)
pub fn set_map_add(client: SetMapClient, key: String, member: String) -> Nil {
  let assert Ok(Nil) =
    crdt_js.or_map_add_member(crdt_js.root(client.document), key, member)
  Nil
}

@target(javascript)
pub fn set_map_remove_member(
  client: SetMapClient,
  key: String,
  member: String,
) -> Nil {
  let assert Ok(Nil) =
    crdt_js.or_map_remove_member(crdt_js.root(client.document), key, member)
  Nil
}

@target(javascript)
pub fn set_map_remove_key(client: SetMapClient, key: String) -> Nil {
  let assert Ok(Nil) =
    crdt_js.or_map_remove_key(crdt_js.root(client.document), key)
  Nil
}

@target(javascript)
pub fn set_map_values(client: SetMapClient) -> String {
  let assert Ok(values) = crdt_js.or_map_entries(crdt_js.root(client.document))
  values
  |> list.map(fn(entry) {
    let assert or_map_kernel.SetMembers(members) = entry.1
    #(entry.0, json.array(members, json.string))
  })
  |> json.object
  |> json.to_string
}

@target(javascript)
pub fn set_map_snapshot(client: SetMapClient) -> json.Json {
  let assert Ok(snapshot) = crdt_js.export_snapshot(client.document)
  snapshot
}

@target(javascript)
pub fn set_map_merge(client: SetMapClient, snapshot: json.Json) -> Nil {
  let assert Ok(_) = crdt_js.merge_snapshot(client.document, snapshot)
  Nil
}

@target(javascript)
pub fn set_map_digest(client: SetMapClient) -> String {
  crdt_js.digest(client.document)
}

@target(javascript)
pub fn start_lww_map(
  harness: Harness,
  policy: String,
  room: String,
  label: String,
  signaling_url: String,
  relay_url: String,
) -> LwwMapClient {
  let signaling =
    crdt_signaling_js.websocket_signaling(
      url: signaling_url,
      on_failure: fn(_detail) { Nil },
    )
  let config =
    crdt_js.config(
      room_id: room,
      replica_label: label,
      compatibility_tag: "relay-lww-map/v1",
      root: p2p.lww_map_root(),
      signaling: signaling,
    )
    |> crdt_js.with_transport_policy(case policy {
      "sequencedOnly" -> SequencedOnly
      "p2pOnly" -> P2pOnly
      _ -> Auto
    })
    |> crdt_js.with_sequencer(crdt_js.sequencer(relay_url))
  let assert Ok(document) = crdt_js.new_document(config)
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
      on_status: fn(_) { Nil },
      rtc: p2p_fake.rtc(harness.world, crdt_js.replica_id(document)),
    )
  let _ =
    crdt_js.subscribe_lww_map(crdt_js.root(document), fn(event) {
      let lww_map_kernel.ValueChanged(key, previous, value) = event
      push(
        events,
        json.to_string(
          json.object([
            #("key", json.string(key)),
            #("previous", case previous {
              None -> json.null()
              Some(value) -> json.string(value)
            }),
            #("value", case value {
              None -> json.null()
              Some(value) -> json.string(value)
            }),
          ]),
        ),
      )
    })
  LwwMapClient(document, connection, readies, events)
}

@target(javascript)
pub fn lww_map_set(client: LwwMapClient, key: String, value: String) -> String {
  case crdt_js.lww_map_set(crdt_js.root(client.document), key, value) {
    Ok(Nil) -> ""
    Error(error) -> crdt_js.describe_error(error)
  }
}

@target(javascript)
pub fn lww_map_remove(client: LwwMapClient, key: String) -> String {
  case crdt_js.lww_map_remove(crdt_js.root(client.document), key) {
    Ok(Nil) -> ""
    Error(error) -> crdt_js.describe_error(error)
  }
}

@target(javascript)
pub fn lww_map_entries(client: LwwMapClient) -> String {
  case crdt_js.lww_map_entries(crdt_js.root(client.document)) {
    Ok(entries) ->
      entries
      |> list.map(fn(entry) { #(entry.0, json.string(entry.1)) })
      |> json.object
      |> json.to_string
    Error(error) -> "error " <> crdt_js.describe_error(error)
  }
}

@target(javascript)
pub fn lww_map_snapshot(client: LwwMapClient) -> String {
  case crdt_js.export_snapshot(client.document) {
    Ok(snapshot) -> json.to_string(snapshot)
    Error(error) -> "error " <> crdt_js.describe_error(error)
  }
}

@target(javascript)
pub fn lww_map_digest(client: LwwMapClient) -> String {
  crdt_js.digest(client.document)
}

@target(javascript)
pub fn set_map_event_count(client: SetMapClient) -> Int {
  transport_js.get_cell(client.events) |> list.length
}

@target(javascript)
pub fn set_map_readiness(client: SetMapClient) -> List(String) {
  entries(client.readies)
}

@target(javascript)
pub fn lww_map_events(client: LwwMapClient) -> List(String) {
  entries(client.events)
}

@target(javascript)
pub fn lww_map_readiness(client: LwwMapClient) -> List(String) {
  entries(client.readies)
}

@target(javascript)
pub fn set_map_is_primary(client: SetMapClient) -> Bool {
  crdt_js.relay_is_primary(client.document)
}

@target(javascript)
pub fn set_map_peer_count(client: SetMapClient) -> Int {
  crdt_js.peer_count(client.document)
}

@target(javascript)
pub fn set_map_path(client: SetMapClient) -> String {
  case crdt_js.effective_path(client.document) {
    PeerToPeer -> "p2p"
    Sequenced -> "relay"
  }
}

@target(javascript)
pub fn lww_map_path(client: LwwMapClient) -> String {
  case crdt_js.effective_path(client.document) {
    PeerToPeer -> "p2p"
    Sequenced -> "relay"
  }
}

@target(javascript)
pub fn set_map_close(client: SetMapClient) -> Nil {
  crdt_js.close(client.connection)
}

@target(javascript)
pub fn lww_map_is_primary(client: LwwMapClient) -> Bool {
  crdt_js.relay_is_primary(client.document)
}

@target(javascript)
pub fn lww_map_peer_count(client: LwwMapClient) -> Int {
  crdt_js.peer_count(client.document)
}

@target(javascript)
pub fn lww_map_close(client: LwwMapClient) -> Nil {
  crdt_js.close(client.connection)
}
