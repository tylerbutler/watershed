//// Collaborative clap counter — Medium-style claps on a peer-to-peer
//// `PnCounter`.
////
//// A Lustre single-page app with no server behind it. The document's root
//// *is* the counter: `crdt_js` connects it to the other tabs in the room
//// over WebRTC data channels, and a small reference signaling service
//// introduces them. Nothing sequences the claps, nothing acknowledges
//// them, and no server ever sees one — two tabs clapping at the same
//// instant both land, because a `PnCounter` merges as a state-based CRDT
//// rather than serializing through last-write-wins.
////
//// Open two tabs on the same room and hold the button down in both.
////
//// ## What this demo does not ship
////
//// - **No STUN or TURN.** Two tabs on one machine, or two machines on one
////   LAN, connect on host candidates alone. Anything across a NAT needs
////   ICE servers, which are yours to supply: `?ice=stun:host:3478`, with
////   `?iceUser=` and `?icePass=` for a TURN credential.
//// - **No durable signaling.** The reference service holds rooms in
////   memory. Restart it and every room is gone.
//// - **No room persistence at all**, unless you point it at a relay. The
////   document lives in the tabs, and when the last one closes the claps
////   are gone. Start `node tools/relay/server.mjs` and pass
////   `?relay=ws://localhost:4500/` and the room survives: the relay is
////   durable, the claps go through it once it has merged and matched
////   digests, and if it dies the tabs carry on over WebRTC and merge the
////   outage's claps back when it returns.
//// - **Eight peers per room.** The mesh is full: every peer holds a
////   connection to every other, and the ninth is refused.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import watershed/browser
import watershed/crdt_js.{type CrdtDocument, type Handle}
import watershed/crdt_signaling_js
import watershed/p2p.{type P2pError}
import watershed/p2p_transport_js.{type IceServer}
import watershed/pn_counter_kernel
import watershed/schema.{type PnCounterChannel}

import watershed_lustre/crdt

/// The application's own schema version. Two peers whose tags differ
/// refuse each other rather than merging documents that mean different
/// things.
const compatibility = "clap-counter/v1"

/// Where `node tools/signaling/server.mjs` listens by default. Override
/// with `?signaling=ws://host:port/`.
const default_signaling = "ws://localhost:4400/"

/// A relay is entirely optional and off unless asked for: `?relay=` with
/// a URL attaches one, and everything else about the app is unchanged.
const relay_param = "relay"

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) =
    lustre.start(app, "#app", browser.document_on_navigate("clap"))
  Nil
}

// ── Model ────────────────────────────────────────────────────────────────────

type Phase {
  Connecting
  Ready
  Failed(detail: String)
}

type Model {
  Model(
    room: String,
    phase: Phase,
    counter: Option(Handle(PnCounterChannel)),
    document: Option(CrdtDocument(PnCounterChannel)),
    claps: Int,
    peers: Int,
    bootstrap: String,
    /// What the optional relay is doing, or `""` when none was
    /// configured. Reporting only — the claps do not depend on it.
    relay: String,
    errors: List(String),
  )
}

type Msg {
  Connected(Result(CrdtDocument(PnCounterChannel), P2pError))
  StatusChanged(crdt_js.Status)
  ClapsChanged(Int)
  ClapClicked
  Clapped(Result(Nil, P2pError))
  /// The handles the bindings insist on delivering — the `CrdtConnection`
  /// and the counter's `Subscription` — discarded. This SPA lives exactly
  /// as long as its page, so nothing ever calls `close` or `unsubscribe`;
  /// fire-and-forget is the whole lifecycle.
  Ignored
}

fn init(room: String) -> #(Model, Effect(Msg)) {
  let model =
    Model(
      room: room,
      phase: Connecting,
      counter: None,
      document: None,
      claps: 0,
      peers: 0,
      bootstrap: "joining",
      relay: case query(relay_param, "") {
        "" -> ""
        _ -> "connecting"
      },
      errors: [],
    )
  #(model, connect(room))
}

/// Join the room through the `watershed_lustre/crdt` bindings. The bindings
/// own the effect and defer every callback; this app only supplies its `Msg`
/// constructors and the `Config`. `crdt_js.connect` is synchronous — the
/// document exists before the effect returns — but readiness and status
/// arrive as deferred messages. The `CrdtConnection` is discarded: see
/// `Ignored`.
fn connect(room: String) -> Effect(Msg) {
  let signaling =
    crdt_signaling_js.websocket_signaling(
      url: query("signaling", default_signaling),
      // A signaling failure is reported through the status stream as
      // `TransportError(SignalingFailed(_))` — which `apply_status` already
      // renders — so the adapter needs no separate failure hook here.
      on_failure: fn(_detail) { Nil },
    )
  // docs:snippet-start practice-relay-config
  let config =
    crdt_js.config(
      room_id: room,
      replica_label: "tab",
      compatibility_tag: compatibility,
      root: p2p.pn_counter_root(),
      signaling: signaling,
    )
    |> crdt_js.with_ice_servers(ice_servers())
    |> with_relay
  // docs:snippet-end practice-relay-config
  crdt.connect(
    config,
    connection: fn(_connection) { Ignored },
    ready: Connected,
    status: StatusChanged,
  )
}

/// Attach the optional relay named by `?relay=`, and nothing at all
/// without one. The policy stays `Auto` either way: readiness never waits
/// for a relay, so a URL pointing at a service that is down costs a
/// status line and no claps.
fn with_relay(
  config: crdt_js.Config(PnCounterChannel),
) -> crdt_js.Config(PnCounterChannel) {
  case query(relay_param, "") {
    "" -> config
    url -> crdt_js.with_sequencer(config, crdt_js.sequencer(url))
  }
}

/// ICE servers, entirely from the URL: watershed ships none, and a demo
/// that quietly used somebody else's STUN server would be lying about
/// what it needs.
fn ice_servers() -> List(IceServer) {
  let urls =
    string.split(query("ice", ""), ",")
    |> list.map(string.trim)
    |> list.filter(fn(url) { url != "" })

  case urls, query("iceUser", ""), query("icePass", "") {
    [], _, _ -> []
    urls, "", _ -> [p2p_transport_js.ice_server(urls: urls)]
    urls, user, password -> [
      p2p_transport_js.ice_server(urls: urls)
      |> p2p_transport_js.with_credentials(username: user, credential: password),
    ]
  }
}

@external(javascript, "./app_ffi.mjs", "queryParam")
fn query(name: String, fallback: String) -> String

// ── Update ───────────────────────────────────────────────────────────────────

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    Ignored -> #(model, effect.none())

    Connected(Ok(document)) -> {
      let counter = crdt_js.root(document)
      let claps = case crdt_js.pn_counter_value(counter) {
        Ok(value) -> value
        Error(_) -> model.claps
      }
      #(
        Model(
          ..model,
          phase: Ready,
          document: Some(document),
          counter: Some(counter),
          claps: claps,
          peers: crdt_js.peer_count(document),
          bootstrap: "ready",
        ),
        watch(counter),
      )
    }
    Connected(Error(error)) -> #(
      Model(..model, phase: Failed(crdt_js.describe_error(error))),
      effect.none(),
    )

    StatusChanged(status) -> #(apply_status(model, status), effect.none())

    ClapsChanged(claps) -> #(Model(..model, claps: claps), effect.none())

    ClapClicked ->
      case model.counter {
        None -> #(model, effect.none())
        Some(counter) -> #(model, clap(counter))
      }

    // The subscription reports the new total; a success needs nothing more. A
    // failure is shown exactly as before, as a `Failed` status line.
    Clapped(Ok(Nil)) -> #(model, effect.none())
    Clapped(Error(error)) -> #(
      apply_status(model, crdt_js.Failed(error)),
      effect.none(),
    )
  }
}

/// Watch the counter through the bindings. Every change — this tab's claps and
/// every peer's — arrives as a deferred `ClapsChanged`. The `Subscription` is
/// discarded: see `Ignored`.
fn watch(counter: Handle(PnCounterChannel)) -> Effect(Msg) {
  crdt.subscribe_pn_counter(
    counter,
    subscribed: fn(_subscription) { Ignored },
    event: fn(event) {
      let pn_counter_kernel.Updated(_applied, total) = event
      ClapsChanged(total)
    },
  )
}

fn clap(counter: Handle(PnCounterChannel)) -> Effect(Msg) {
  crdt.perform(fn() { crdt_js.pn_counter_update(counter, 1) }, Clapped)
}

fn apply_status(model: Model, status: crdt_js.Status) -> Model {
  let peers = case model.document {
    Some(document) -> crdt_js.peer_count(document)
    None -> model.peers
  }
  let model = Model(..model, peers: peers)
  case status {
    crdt_js.Joined(_, _) -> Model(..model, bootstrap: "joined")
    crdt_js.RosterKnown([]) -> Model(..model, bootstrap: "alone")
    crdt_js.RosterKnown(_) -> Model(..model, bootstrap: "syncing")
    crdt_js.AwaitingState(_) -> Model(..model, bootstrap: "syncing")
    crdt_js.Ready | crdt_js.StateMerged(_, _) ->
      Model(..model, bootstrap: "ready")
    crdt_js.PeerRejected(peer, error) ->
      note(
        model,
        "peer " <> short(peer) <> " · " <> crdt_js.describe_error(error),
      )
    crdt_js.Failed(error) -> note(model, crdt_js.describe_error(error))
    crdt_js.TransportError(error) -> note(model, crdt_js.describe_error(error))
    crdt_js.SubscriberFailed(_, detail) -> note(model, detail)
    crdt_js.RejectedByPeer(peer, reason, detail) ->
      note(
        model,
        "peer " <> short(peer) <> " refused us · " <> reason <> " " <> detail,
      )
    // The relay vocabulary is deliberately collapsed to three states —
    // syncing, durable, offline — a status line, not a relay console. The
    // finer-grained statuses exist for apps that want them.
    crdt_js.RelayConnecting(_)
    | crdt_js.RelaySyncingStatus
    | crdt_js.RelayRecovering
    | crdt_js.RelayRetry(_) -> Model(..model, relay: "syncing")
    crdt_js.RelayPrimary(_)
    | crdt_js.RelayCheckpointRequested
    | crdt_js.RelayCheckpointed(_) -> Model(..model, relay: "durable")
    crdt_js.RelayFallback(_) | crdt_js.RelayUnsupported(_) ->
      Model(..model, relay: "offline · peer-to-peer")
    crdt_js.RelayFailed(error) ->
      note(Model(..model, relay: "offline"), crdt_js.describe_error(error))
    crdt_js.RelayRejected(who, error) ->
      note(
        model,
        "relay peer " <> short(who) <> " · " <> crdt_js.describe_error(error),
      )
    crdt_js.PeerReady(_) | crdt_js.PeerGone(_) | crdt_js.Transport(_) -> model
  }
}

fn note(model: Model, error: String) -> Model {
  Model(..model, errors: list.take([error, ..model.errors], 5))
}

/// A replica id is `tab-<uuid>`; the first block of the uuid is enough to
/// tell two tabs apart on screen.
fn short(replica: String) -> String {
  case string.split(replica, "-") {
    [_label, head, ..] -> head
    _ -> replica
  }
}

// ── View ─────────────────────────────────────────────────────────────────────

fn view(model: Model) -> Element(Msg) {
  html.main([attribute.class("wrap")], [
    html.h1([], [html.text("watershed · peer-to-peer claps")]),
    status_line(model),
    html.div([attribute.class("count")], [html.text(int.to_string(model.claps))]),
    html.div([attribute.class("controls")], [
      html.button(
        [attribute.class("clap-button"), event.on_click(ClapClicked)],
        [
          html.text("👏 Clap"),
        ],
      ),
    ]),
    errors_view(model),
    html.p([attribute.class("hint")], [
      html.text(
        "Open this URL in a second tab and hold the button down in both. "
        <> "No server sequences the claps; the tabs merge them directly. "
        <> "Room: "
        <> model.room,
      ),
    ]),
  ])
}

fn status_line(model: Model) -> Element(Msg) {
  let connection = case model.phase {
    Connecting -> "connecting…"
    Ready -> model.bootstrap
    Failed(detail) -> "failed: " <> detail
  }
  let peers = case model.peers {
    1 -> "1 peer"
    count -> int.to_string(count) <> " peers"
  }
  let relay = case model.relay {
    "" -> ""
    state -> " · relay " <> state
  }
  html.p([attribute.class("status")], [
    html.text(connection <> " · " <> peers <> relay),
  ])
}

fn errors_view(model: Model) -> Element(Msg) {
  case model.errors {
    [] -> element.none()
    errors ->
      html.section([attribute.class("errors")], [
        html.h2([], [html.text("Connection errors")]),
        html.pre([], [html.text(string.join(list.reverse(errors), "\n"))]),
      ])
  }
}
