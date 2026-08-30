//// Collaborative reorderable playlist — a `SharedSequence` demo.
////
//// Where `dice_lustre` edits one key on a map and `sudoku_lustre` fans out
//// across four nested channels, this example exercises the one thing no other
//// watershed DDS offers: **`move`**, an ordered-list reorder that converges
//// under concurrency. Two tabs dragging the same track to different positions
//// land on the same order rather than duplicating or dropping it.
////
//// Operation coverage, all against a single sequence:
////
//// - `sequence_insert` — append a track (index == current length)
//// - `sequence_move`   — the ↑/↓ buttons; **destination is interpreted after
////                       the element is removed**, so moving down one is
////                       `to = from + 1` and moving up one is `to = from - 1`
//// - `sequence_replace`— rename a track in place
//// - `sequence_delete` — drop a track
////
//// Every mutation returns `Result(Nil, String)`: unlike map `set`, a sequence
//// edit can legitimately fail when an index is stale — a peer may have deleted
//// the row out from under this tab between render and click. The app surfaces
//// that error instead of asserting, which is the honest shape for index-
//// addressed operations on a shared list.
////
//// All of that lives in `playlist_lustre/component`, a nested MVU triple that
//// takes a `TypedMap(PlaylistDoc)` and never reaches for a root. This module
//// is what an application owns and a panel must not: the connection, the
//// runtime diagnostics, and force reconnect — every one of them
//// document-scoped. Mounted in `showcase_lustre`, the same component is handed
//// a child map instead of this document's root, and nothing else changes.
////
//// Open two browser tabs against the same `just server` document to watch
//// reorders converge.

import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import watershed.{type Document}
import watershed/browser
import watershed/sequence_kernel
import watershed_lustre

import playlist_lustre/component
import playlist_lustre/doc_schema
import playlist_lustre/track

// ── Dev config for `just server` (levee dev mode) ────────────────────────────

const socket_url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let document = browser.document_on_navigate("playlist")
  let assert Ok(_) = lustre.start(app, "#app", document)
  Nil
}

// ── Model ────────────────────────────────────────────────────────────────────

type Status {
  Connecting
  Ready
  Failed(reason: String)
}

type Model {
  Model(
    status: Status,
    doc: Option(Document(doc_schema.PlaylistDoc)),
    /// The playlist panel. `None` until the handshake completes.
    playlist: Option(component.Model),
    /// Whether this app has taken its own subscription on the tracks channel.
    /// The component takes one too; a channel fans out to every subscriber.
    traced: Bool,
    user_id: String,
    diagnostics: Option(watershed.Diagnostics),
    diagnostic_log: List(String),
  )
}

type Msg {
  GotHandle(Document(doc_schema.PlaylistDoc))
  Connected(Result(Nil, String))
  DiagnosticsTick
  TracksChanged(sequence_kernel.SequenceEvent)
  Playlist(component.Msg)
  ReconnectClicked
}

fn init(document: String) -> #(Model, Effect(Msg)) {
  // A distinct user per tab so the two clients are separate connections.
  let user_id = "web-" <> int.to_string(1000 + int.random(9000))
  let model =
    Model(
      status: Connecting,
      doc: None,
      playlist: None,
      traced: False,
      user_id: user_id,
      diagnostics: None,
      diagnostic_log: [],
    )
  #(
    model,
    watershed_lustre.connect_dev(
      url: socket_url,
      tenant: tenant,
      secret: tenant_secret,
      document: document,
      user_id: user_id,
      got_document: GotHandle,
      connected: Connected,
    ),
  )
}

// ── Update ───────────────────────────────────────────────────────────────────

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    // The handle arrives before the handshake completes, so it can be retained
    // for diagnostics but cannot create the tracks sequence yet.
    GotHandle(doc) -> {
      let diagnostics = watershed.diagnostics(doc)
      let model =
        Model(..model, doc: Some(doc), diagnostics: Some(diagnostics))
        |> add_diagnostic(
          "document handle acquired · " <> diagnostic_line(diagnostics),
        )
      #(model, watershed_lustre.after(250, DiagnosticsTick))
    }

    // `root_typed` is the line that makes this the standalone app rather than a
    // panel: it is the only place the document's root is named.
    Connected(Ok(_)) -> {
      let model =
        Model(..model, status: Ready)
        |> add_diagnostic("initial handshake complete")
      case model.doc {
        None -> #(model, effect.none())
        Some(doc) -> {
          let #(playlist, playlist_effect) =
            component.init(doc, watershed.root_typed(doc), model.user_id)
          #(
            Model(..model, playlist: Some(playlist)),
            effect.map(playlist_effect, Playlist),
          )
        }
      }
    }
    Connected(Error(reason)) -> {
      let model =
        Model(..model, status: Failed(reason))
        |> add_diagnostic("connection failed · " <> reason)
      #(model, effect.none())
    }

    Playlist(inner) ->
      case model.playlist {
        None -> #(model, effect.none())
        Some(playlist) -> {
          let #(playlist, playlist_effect) = component.update(playlist, inner)
          let #(model, trace) =
            trace_tracks(Model(..model, playlist: Some(playlist)))
          #(model, effect.batch([effect.map(playlist_effect, Playlist), trace]))
        }
      }

    // The app's share of a sequence event: the diagnostics trace. The component
    // re-renders itself off its own subscription.
    TracksChanged(event) -> {
      let diagnostics = case model.doc {
        Some(doc) -> Some(watershed.diagnostics(doc))
        None -> None
      }
      let detail = case diagnostics {
        Some(diagnostics) ->
          event_line(event) <> " · " <> diagnostic_line(diagnostics)
        None -> event_line(event)
      }
      let model =
        Model(..model, diagnostics: diagnostics)
        |> add_diagnostic(detail)
      #(model, effect.none())
    }

    DiagnosticsTick -> {
      let next = case model.doc {
        Some(doc) -> Some(watershed.diagnostics(doc))
        None -> None
      }
      let model = case next, model.diagnostics {
        Some(current), Some(previous) if current != previous ->
          Model(..model, diagnostics: next)
          |> add_diagnostic("runtime · " <> diagnostic_line(current))
        _, _ -> Model(..model, diagnostics: next)
      }
      #(model, watershed_lustre.after(250, DiagnosticsTick))
    }

    ReconnectClicked ->
      case model.doc {
        Some(doc) -> #(
          add_diagnostic(model, "force reconnect requested"),
          watershed_lustre.force_reconnect(doc),
        )
        None -> #(model, effect.none())
      }
  }
}

/// Take this app's own subscription on the tracks channel, once, as soon as the
/// component has one to share.
fn trace_tracks(model: Model) -> #(Model, Effect(Msg)) {
  case model.traced, model.playlist {
    False, Some(playlist) ->
      case component.channel(playlist) {
        Some(sequence) -> #(
          Model(..model, traced: True)
            |> add_diagnostic("tracks sequence ready"),
          watershed_lustre.subscribe_sequence(sequence, TracksChanged),
        )
        None -> #(model, effect.none())
      }
    _, _ -> #(model, effect.none())
  }
}

fn add_diagnostic(model: Model, line: String) -> Model {
  let tagged = "[" <> model.user_id <> "] " <> line
  io.println(tagged)
  Model(
    ..model,
    diagnostic_log: list.take([tagged, ..model.diagnostic_log], 40),
  )
}

fn event_line(event: sequence_kernel.SequenceEvent) -> String {
  case event {
    sequence_kernel.SequenceChanged(values) ->
      "sequenceChanged length="
      <> int.to_string(list.length(values))
      <> " ["
      <> {
        values
        |> list.map(fn(value) { track.from_json(value).title })
        |> string.join(", ")
      }
      <> "]"
  }
}

fn diagnostic_line(diagnostics: watershed.Diagnostics) -> String {
  "phase="
  <> diagnostics.phase
  <> " client="
  <> option.unwrap(diagnostics.client_id, "none")
  <> " sn="
  <> option_int(diagnostics.last_seen_sequence_number)
  <> " next_csn="
  <> option_int(diagnostics.next_client_sequence_number)
  <> " in_flight="
  <> int.to_string(diagnostics.in_flight_count)
  <> " buffered="
  <> int.to_string(diagnostics.buffered_out_of_order_count)
  <> " resubmit_at="
  <> option_int(diagnostics.resubmit_checkpoint)
  <> " synced="
  <> bool_to_string(diagnostics.synced)
}

fn option_int(value: Option(Int)) -> String {
  value
  |> option.map(int.to_string)
  |> option.unwrap("none")
}

fn bool_to_string(value: Bool) -> String {
  case value {
    True -> "true"
    False -> "false"
  }
}

// ── View ─────────────────────────────────────────────────────────────────────

fn view(model: Model) -> Element(Msg) {
  html.main([attribute.class("wrap")], [
    html.h1([], [html.text("watershed · collaborative playlist")]),
    status_line(model),
    panel_view(model),
    html.div([attribute.class("compose")], [
      html.button([event.on_click(ReconnectClicked)], [
        html.text("Force reconnect"),
      ]),
    ]),
    diagnostics_view(model),
    html.p([attribute.class("hint")], [
      html.text(
        "Open a second tab on the same document and reorder from both — "
        <> "concurrent moves converge on one order. Client: "
        <> model.user_id,
      ),
    ]),
  ])
}

fn status_line(model: Model) -> Element(Msg) {
  let connection = case model.status {
    Connecting -> "connecting…"
    Ready -> "connected"
    Failed(reason) -> "failed: " <> reason
  }
  let runtime = case model.diagnostics {
    Some(diagnostics) -> " · " <> diagnostics.phase
    None -> ""
  }
  let tracks = case model.playlist {
    Some(playlist) -> component.track_count(playlist)
    None -> 0
  }
  html.p([attribute.class("status")], [
    html.text(
      connection <> runtime <> " · " <> int.to_string(tracks) <> " tracks",
    ),
  ])
}

fn panel_view(model: Model) -> Element(Msg) {
  case model.playlist {
    Some(playlist) -> component.view(playlist) |> element.map(Playlist)
    None -> html.p([attribute.class("status")], [html.text("connecting…")])
  }
}

fn diagnostics_view(model: Model) -> Element(Msg) {
  let current = case model.diagnostics {
    Some(diagnostics) -> diagnostic_line(diagnostics)
    None -> "runtime diagnostics unavailable"
  }
  let log = model.diagnostic_log |> string.join("\n")
  html.section([attribute.class("diagnostics")], [
    html.h2([], [html.text("Diagnostics")]),
    html.p([], [
      html.text(
        "Compare this panel across tabs. Browser DevTools receives the same trace.",
      ),
    ]),
    html.pre([attribute.class("diagnostic-current")], [html.text(current)]),
    html.pre([attribute.class("diagnostic-log")], [html.text(log)]),
  ])
}
