//// The real-browser smoke harness for `p2p_transport_js`, run by
//// `smoke/p2p_browser.mjs`.
////
//// Two `crdt_core` documents, two `RTCPeerConnection`s, one real data
//// channel between them, and an in-memory signaling adapter that never
//// leaves the page. No sequencer, no server, no `runtime_core`.
////
//// The scenario is the one the plan's P2P4 gate names:
////
//// 1. the first peer starts with an empty root and no sequencer;
//// 2. a second peer joins through the in-memory signaling adapter;
//// 3. they exchange `hello`, `stateRequest`, and `state` over the real
////    data channel;
//// 4. both author eligible CRDT edits before either has seen the other's,
////    including a channel one peer creates and the other has never heard
////    of;
//// 5. their canonical snapshots and digests converge;
//// 6. the channel really is reliable and unordered, and signaling carried
////    no document delta.
////
//// This is not a `gleam test` case. startest's test body is `fn() -> Nil`
//// with nowhere to return a promise, and every step here waits on the
//// browser; a runner would score the assertions the moment the first
//// `await` suspended. So it is a `run` that resolves to a report string,
//// driven from outside the page. The deterministic fake-browser tests in
//// `p2p_transport_js_test.gleam` are the ones in the normal suite.

@target(javascript)
import gleam/int
@target(javascript)
import gleam/javascript/promise.{type Promise}
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{type Option, None, Some}
@target(javascript)
import gleam/string

@target(javascript)
import watershed/channel
@target(javascript)
import watershed/crdt_core
@target(javascript)
import watershed/crdt_wire
@target(javascript)
import watershed/p2p.{type P2pError}
@target(javascript)
import watershed/p2p_transport_js.{
  type Signal, type SignalPayload, type Signaling, type Transport, Answer,
  Callbacks, Candidate, Message, Offer, PeerJoined, PeerLeft, Signaling,
}
@target(javascript)
import watershed/transport_js.{type Cell}

@target(javascript)
const room = "watershed-p2p-smoke"

@target(javascript)
const compatibility = "watershed-crdt-v1"

@target(javascript)
/// How long each wait may take before the harness gives up. Generous: a
/// headless browser gathering host candidates is not fast, and a hang is
/// far more useful reported than timed out at the first hiccup.
const wait_ms = 15_000

@target(javascript)
@external(javascript, "./p2p_browser_smoke_ffi.mjs", "sleep")
fn sleep(ms: Int) -> Promise(Nil)

@target(javascript)
@external(javascript, "./p2p_browser_smoke_ffi.mjs", "nowMs")
fn now_ms() -> Int

// ─────────────────────────────────────────────────────────────────────────────
// In-memory signaling
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// A signaling adapter that lives entirely in this page. It records every
/// payload it carries, which is what lets the harness prove no document
/// data ever entered it.
type Hub {
  Hub(cell: Cell(HubState))
}

@target(javascript)
type HubState {
  HubState(members: List(#(String, fn(Signal) -> Nil)), payloads: List(String))
}

@target(javascript)
fn new_hub() -> Hub {
  Hub(cell: transport_js.new_cell(HubState(members: [], payloads: [])))
}

@target(javascript)
fn hub_signaling(hub: Hub) -> Signaling {
  Signaling(
    join: fn(joined_room, peer_id, on_signal) {
      let state = transport_js.get_cell(hub.cell)
      let existing = state.members
      transport_js.set_cell(
        hub.cell,
        HubState(..state, members: [#(peer_id, on_signal), ..existing]),
      )
      // Both directions, so an established peer learns about the newcomer
      // and the newcomer learns the room's current membership. The
      // transport buffers whatever arrives before `join` returns.
      list.each(existing, fn(member) {
        on_signal(PeerJoined(member.0))
        member.1(PeerJoined(peer_id))
      })
      Ok(p2p_transport_js.signaling_session(room: joined_room, peer_id: peer_id))
    },
    send: fn(session, to, payload) {
      let from = p2p_transport_js.session_peer_id(session)
      let state = transport_js.get_cell(hub.cell)
      transport_js.set_cell(
        hub.cell,
        HubState(..state, payloads: [
          from <> "->" <> to <> " " <> render_payload(payload),
          ..state.payloads
        ]),
      )
      case find_member(hub, to) {
        Ok(deliver) -> deliver(Message(from, payload))
        Error(Nil) -> Nil
      }
    },
    leave: fn(session) {
      let peer_id = p2p_transport_js.session_peer_id(session)
      let state = transport_js.get_cell(hub.cell)
      let remaining =
        list.filter(state.members, fn(member) { member.0 != peer_id })
      transport_js.set_cell(hub.cell, HubState(..state, members: remaining))
      list.each(remaining, fn(member) { member.1(PeerLeft(peer_id)) })
    },
  )
}

@target(javascript)
fn find_member(hub: Hub, peer_id: String) -> Result(fn(Signal) -> Nil, Nil) {
  case
    transport_js.get_cell(hub.cell).members
    |> list.filter(fn(member) { member.0 == peer_id })
  {
    [member, ..] -> Ok(member.1)
    [] -> Error(Nil)
  }
}

@target(javascript)
fn hub_payloads(hub: Hub) -> List(String) {
  list.reverse(transport_js.get_cell(hub.cell).payloads)
}

@target(javascript)
fn render_payload(payload: SignalPayload) -> String {
  case payload {
    Offer(sdp) -> "offer " <> sdp
    Answer(sdp) -> "answer " <> sdp
    Candidate(candidate) -> "candidate " <> candidate
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// One peer: a pure document plus a transport
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
type Node {
  Node(
    peer_id: String,
    document: Cell(crdt_core.Document),
    transport: Cell(Option(Transport)),
    /// The wire tag of every message this peer received, so the report can
    /// show the handshake actually happened over the data channel rather
    /// than inferring it from the outcome.
    received: Cell(List(String)),
    problems: Cell(List(String)),
  )
}

@target(javascript)
fn start_node(
  hub: Hub,
  peer_id: String,
  replica: String,
) -> Result(Node, String) {
  let config =
    crdt_core.config(
      room: room,
      compatibility: compatibility,
      replica: replica,
      session: peer_id,
      root: p2p.kind_init(p2p.or_set_root()),
    )
  case crdt_core.new(config) {
    Error(error) -> Error("document: " <> describe(error))
    Ok(document) -> {
      let node =
        Node(
          peer_id: peer_id,
          document: transport_js.new_cell(document),
          transport: transport_js.new_cell(None),
          received: transport_js.new_cell([]),
          problems: transport_js.new_cell([]),
        )
      let callbacks =
        Callbacks(
          // A new link is a peer that may know things we do not, and may
          // not know things we do: introduce ourselves and ask for state.
          on_peer_open: fn(peer) {
            let document = transport_js.get_cell(node.document)
            send_to(node, peer, crdt_core.hello_message(document))
            send_to(node, peer, crdt_core.state_request_message())
          },
          on_peer_close: fn(_peer) { Nil },
          on_document: fn(peer, raw) { receive(node, peer, raw) },
          on_status: fn(_status) { Nil },
          on_error: fn(error) { note(node, "transport: " <> describe(error)) },
        )
      case
        p2p_transport_js.start(
          room: room,
          peer_id: peer_id,
          signaling: hub_signaling(hub),
          ice_servers: [],
          callbacks: callbacks,
        )
      {
        Error(error) -> Error("transport: " <> describe(error))
        Ok(transport) -> {
          transport_js.set_cell(node.transport, Some(transport))
          Ok(node)
        }
      }
    }
  }
}

@target(javascript)
/// Decode one string off the data channel, merge it, and route whatever
/// the core asks for. A rejection is recorded rather than swallowed: this
/// harness fails if the protocol did.
fn receive(node: Node, from: String, raw: String) -> Nil {
  case crdt_wire.decode_envelope(raw, crdt_wire.default_limits()) {
    Ok(envelope) ->
      transport_js.set_cell(node.received, [
        crdt_wire.message_type(envelope.message),
        ..transport_js.get_cell(node.received)
      ])
    Error(_) -> Nil
  }
  case crdt_core.receive_encoded(transport_js.get_cell(node.document), raw) {
    Error(error) ->
      note(node, "receive from " <> from <> ": " <> describe(error))
    Ok(#(document, outcome)) -> {
      transport_js.set_cell(node.document, document)
      list.each(outcome.reply, fn(message) { send_to(node, from, message) })
      list.each(outcome.broadcast, fn(message) { broadcast(node, message) })
    }
  }
}

@target(javascript)
fn send_to(node: Node, peer: String, message: crdt_wire.Message) -> Nil {
  let document = transport_js.get_cell(node.document)
  case transport_js.get_cell(node.transport) {
    Some(transport) -> {
      case
        p2p_transport_js.send(
          transport,
          peer,
          crdt_core.encode(document, message),
        )
      {
        Ok(Nil) -> Nil
        Error(_) ->
          note(
            node,
            "send "
              <> crdt_wire.message_type(message)
              <> " to "
              <> peer
              <> " was not delivered",
          )
      }
    }
    None -> note(node, "send before the transport existed")
  }
}

@target(javascript)
fn broadcast(node: Node, message: crdt_wire.Message) -> Nil {
  let document = transport_js.get_cell(node.document)
  case transport_js.get_cell(node.transport) {
    Some(transport) -> {
      let _ =
        p2p_transport_js.broadcast(
          transport,
          crdt_core.encode(document, message),
        )
      Nil
    }
    None -> note(node, "broadcast before the transport existed")
  }
}

@target(javascript)
fn edit(node: Node, address: String, edit: channel.P2pEdit) -> Nil {
  case crdt_core.edit(transport_js.get_cell(node.document), address, edit) {
    Error(error) -> note(node, "edit: " <> describe(error))
    Ok(#(document, outcome)) -> {
      transport_js.set_cell(node.document, document)
      list.each(outcome.broadcast, fn(message) { broadcast(node, message) })
    }
  }
}

@target(javascript)
/// Create a channel and announce it, returning its address.
fn create_channel(
  node: Node,
  init: channel.ChannelInit,
) -> Result(String, String) {
  case crdt_core.create_channel(transport_js.get_cell(node.document), init) {
    Error(error) -> Error("create channel: " <> describe(error))
    Ok(#(document, outcome)) -> {
      transport_js.set_cell(node.document, document)
      list.each(outcome.broadcast, fn(message) { broadcast(node, message) })
      case outcome.created {
        [descriptor, ..] -> Ok(descriptor.address)
        [] -> Error("create channel: no descriptor was produced")
      }
    }
  }
}

@target(javascript)
fn note(node: Node, problem: String) -> Nil {
  transport_js.set_cell(node.problems, [
    node.peer_id <> ": " <> problem,
    ..transport_js.get_cell(node.problems)
  ])
}

@target(javascript)
fn received(node: Node) -> List(String) {
  list.reverse(transport_js.get_cell(node.received))
}

@target(javascript)
fn problems(node: Node) -> List(String) {
  list.reverse(transport_js.get_cell(node.problems))
}

@target(javascript)
fn digest(node: Node) -> String {
  crdt_core.digest(transport_js.get_cell(node.document))
}

@target(javascript)
/// The digest projection, not `canonical_json`: the full canonical form
/// embeds each replica's own authoring cursor, so two converged replicas
/// are *supposed* to differ there. This is the projection with those
/// cursors removed — the thing two peers holding the same logical and
/// causal state must agree on byte for byte.
fn snapshot(node: Node) -> String {
  crdt_core.digest_canonical_json(transport_js.get_cell(node.document))
}

@target(javascript)
fn open_count(node: Node) -> Int {
  case transport_js.get_cell(node.transport) {
    Some(transport) -> p2p_transport_js.open_peer_count(transport)
    None -> 0
  }
}

@target(javascript)
fn diagnostics(node: Node, peer: String) -> String {
  case transport_js.get_cell(node.transport) {
    Some(transport) -> p2p_transport_js.peer_diagnostics(transport, peer)
    None -> "{\"known\":false}"
  }
}

@target(javascript)
fn shutdown(node: Node) -> Nil {
  case transport_js.get_cell(node.transport) {
    Some(transport) -> p2p_transport_js.close(transport)
    None -> Nil
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The scenario
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// Run the scenario and resolve to a report. The first line is `PASS` or
/// `FAIL`; the rest is evidence either way.
pub fn run() -> Promise(String) {
  let hub = new_hub()
  case start_node(hub, "peer-a", "replica-a") {
    Error(detail) -> promise.resolve(report(["start peer-a: " <> detail], []))
    Ok(a) ->
      // The first peer is ready with an empty root and no sequencer before
      // anyone else exists.
      case crdt_core.channel_count(transport_js.get_cell(a.document)) == 1 {
        False ->
          promise.resolve(report(["peer-a did not start with a lone root"], []))
        True ->
          case start_node(hub, "peer-b", "replica-b") {
            Error(detail) ->
              promise.resolve(report(["start peer-b: " <> detail], []))
            Ok(b) -> connect_and_converge(hub, a, b)
          }
      }
  }
}

@target(javascript)
fn connect_and_converge(hub: Hub, a: Node, b: Node) -> Promise(String) {
  use connected <- promise.await(
    wait_until(fn() { open_count(a) == 1 && open_count(b) == 1 }),
  )
  case connected {
    False ->
      finish(hub, a, b, [
        "the data channels never opened (peer-a saw "
        <> int.to_string(open_count(a))
        <> " peers, peer-b saw "
        <> int.to_string(open_count(b))
        <> ")",
      ])
    True -> {
      // Both peers edit before either has seen the other's edit, and one
      // of them creates a channel the other has never heard of.
      edit(a, crdt_wire.root_address, channel.OrSetAddEdit("kayak"))
      edit(b, crdt_wire.root_address, channel.OrSetAddEdit("canoe"))
      edit(a, crdt_wire.root_address, channel.OrSetAddEdit("shared"))
      edit(b, crdt_wire.root_address, channel.OrSetAddEdit("shared"))

      case create_channel(b, channel.InitPnCounter) {
        Error(detail) -> finish(hub, a, b, [detail])
        Ok(address) -> {
          edit(b, address, channel.PnCounterEdit(3))
          edit(b, address, channel.PnCounterEdit(-1))
          use converged <- promise.await(
            wait_until(fn() {
              digest(a) == digest(b)
              && crdt_core.channel_count(transport_js.get_cell(a.document)) == 2
            }),
          )
          finish(hub, a, b, checks(hub, a, b, converged))
        }
      }
    }
  }
}

@target(javascript)
fn checks(hub: Hub, a: Node, b: Node, converged: Bool) -> List(String) {
  let failures = case converged {
    True -> []
    False -> [
      "the documents did not converge: peer-a "
      <> digest(a)
      <> ", peer-b "
      <> digest(b),
    ]
  }

  let failures = case snapshot(a) == snapshot(b) {
    True -> failures
    False -> ["comparable canonical snapshots differ", ..failures]
  }

  // Every concurrent edit survived on both sides, so this is a merge and
  // not one peer's state overwriting the other's.
  let failures =
    ["kayak", "canoe", "shared"]
    |> list.fold(failures, fn(failures, element) {
      case
        string.contains(snapshot(a), element)
        && string.contains(snapshot(b), element)
      {
        True -> failures
        False -> ["both peers should hold " <> element, ..failures]
      }
    })

  // A reliable, unordered channel is `ordered: false` with neither lossy
  // option set.
  let failures =
    [#(a, "peer-b"), #(b, "peer-a")]
    |> list.fold(failures, fn(failures, pair) {
      let report = diagnostics(pair.0, pair.1)
      [
        #("\"label\":\"watershed-crdt-v1\"", "label"),
        #("\"readyState\":\"open\"", "open channel"),
        #("\"ordered\":false", "unordered"),
        #("\"maxRetransmits\":null", "no retransmit limit"),
        #("\"maxPacketLifeTime\":null", "no packet lifetime"),
      ]
      |> list.fold(failures, fn(failures, expected) {
        case string.contains(report, expected.0) {
          True -> failures
          False -> [
            pair.0.peer_id <> " channel is not " <> expected.1 <> ": " <> report,
            ..failures
          ]
        }
      })
    })

  // The bootstrap handshake really crossed the data channel.
  let failures =
    [#(a, "hello"), #(b, "hello"), #(a, "stateRequest"), #(b, "stateRequest")]
    |> list.fold(failures, fn(failures, expected) {
      case list.contains(received(expected.0), expected.1) {
        True -> failures
        False -> [
          expected.0.peer_id <> " never received a " <> expected.1,
          ..failures
        ]
      }
    })
  let failures = case
    list.contains(received(a), "state") || list.contains(received(b), "state")
  {
    True -> failures
    False -> ["no state message was exchanged", ..failures]
  }

  let payloads = hub_payloads(hub)
  let failures = case payloads {
    [] -> ["signaling carried nothing at all", ..failures]
    _ -> failures
  }

  // Signaling is a closed sum of offer, answer, and candidate, so this
  // cannot fail by construction — which is exactly why it is worth
  // asserting: it is the property the whole adapter design exists for.
  let failures =
    payloads
    |> list.fold(failures, fn(failures, payload) {
      let signaling_shaped =
        string.contains(payload, " offer ")
        || string.contains(payload, " answer ")
        || string.contains(payload, " candidate ")
      let document_shaped =
        string.contains(payload, "\"v\":1")
        || string.contains(payload, "\"type\":\"delta\"")
        || string.contains(payload, "\"type\":\"state\"")
      case signaling_shaped && !document_shaped {
        True -> failures
        False -> [
          "signaling carried a non-signaling payload: " <> payload,
          ..failures
        ]
      }
    })

  list.append(failures, list.append(problems(a), problems(b)))
}

@target(javascript)
fn finish(
  hub: Hub,
  a: Node,
  b: Node,
  failures: List(String),
) -> Promise(String) {
  let evidence = [
    "peer-a digest: " <> digest(a),
    "peer-b digest: " <> digest(b),
    "peer-a open peers: " <> int.to_string(open_count(a)),
    "peer-b open peers: " <> int.to_string(open_count(b)),
    "peer-a channels: "
      <> int.to_string(
      crdt_core.channel_count(transport_js.get_cell(a.document)),
    ),
    "peer-b channels: "
      <> int.to_string(
      crdt_core.channel_count(transport_js.get_cell(b.document)),
    ),
    "peer-a channel: " <> diagnostics(a, "peer-b"),
    "peer-b channel: " <> diagnostics(b, "peer-a"),
    "peer-a received: " <> string.join(received(a), ","),
    "peer-b received: " <> string.join(received(b), ","),
    "signaling payloads: " <> int.to_string(list.length(hub_payloads(hub))),
    "signaling kinds: " <> string.join(payload_kinds(hub), ","),
  ]
  shutdown(a)
  shutdown(b)
  promise.resolve(report(failures, evidence))
}

@target(javascript)
fn payload_kinds(hub: Hub) -> List(String) {
  hub_payloads(hub)
  |> list.map(fn(payload) {
    case string.split(payload, " ") {
      [_, kind, ..] -> kind
      _ -> "?"
    }
  })
  |> list.unique
  |> list.sort(string.compare)
}

@target(javascript)
fn report(failures: List(String), evidence: List(String)) -> String {
  let header = case failures {
    [] -> "PASS"
    _ -> "FAIL"
  }
  [header, ..list.append(list.map(failures, fn(f) { "  ! " <> f }), evidence)]
  |> string.join("\n")
}

@target(javascript)
fn wait_until(predicate: fn() -> Bool) -> Promise(Bool) {
  poll(predicate, now_ms() + wait_ms)
}

@target(javascript)
fn poll(predicate: fn() -> Bool, deadline: Int) -> Promise(Bool) {
  case predicate() {
    True -> promise.resolve(True)
    False ->
      case now_ms() >= deadline {
        True -> promise.resolve(False)
        False -> {
          use _ <- promise.await(sleep(25))
          poll(predicate, deadline)
        }
      }
  }
}

@target(javascript)
fn describe(error: P2pError) -> String {
  string.inspect(error)
}
