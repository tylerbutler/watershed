//// A shared 64x64 bitmap: convergence you can check with your eyes.
////
//// Every other example in this repo proves convergence by assertion — the dice
//// example shows a number, sudoku a grid of digits, the scoreboard a total —
//// and the reader has to accept that the number is right. Two tabs painting
//// over each other either produce the same picture or they do not, and nobody
//// has to read a line of Gleam to adjudicate it.
////
//// It is also the one example that stresses op volume. Dragging the brush
//// emits an op per cell crossed, so a few seconds of scribbling in two tabs is
//// thousands of ops through a path that elsewhere only ever sees one keystroke
//// at a time. Two things keep that honest: cells are deduped, so a drag emits
//// one op per cell entered rather than one per pointer event, and the pixels
//// live in a `<canvas>` the FFI owns outright rather than in 4096 vdom nodes.
////
//// The offline toggle is the point, not a bonus. `or_map_kernel` advances by
//// joining sparse deltas, so two clients that paint disjoint regions while
//// disconnected converge by *join* when they come back — no rebase, no op
//// replay, no server arbitration.
////
//// The toggle lives *here* rather than in `pixel_canvas_lustre/component`, and
//// that placement is load-bearing. `go_offline` takes a `Document`: it stops
//// sync for everything in the document, not for the canvas. On a one-panel app
//// those are the same thing, which is exactly why it reads as a canvas control
//// and why moving it was easy to miss — mounted in `showcase_lustre` beside
//// three other demos, the same button would disconnect all four. Anything
//// taking a `Document` rather than a channel belongs to whoever owns the
//// document; the diagnostics line below it is here for the same reason.

import gleam/int
import gleam/option.{type Option, None, Some}

import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import watershed.{type Document}
import watershed_lustre

import pixel_canvas_lustre/component
import pixel_canvas_lustre/doc_schema

// ── Dev config for `just integration-up` (floodgate dev mode) ────────────────

const socket_url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

const document_id = "pixel-canvas"

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
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
    doc: Option(Document(doc_schema.CanvasDoc)),
    /// The canvas panel. `None` until the handshake completes.
    canvas: Option(component.Model),
    user_id: String,
    offline: Bool,
    diagnostics: Option(watershed.Diagnostics),
    last_error: Option(String),
  )
}

type Msg {
  GotHandle(Document(doc_schema.CanvasDoc))
  Connected(Result(Nil, String))
  DiagnosticsTick
  Canvas(component.Msg)
  ToggledOffline(Bool)
}

fn init(_arguments: Nil) -> #(Model, Effect(Msg)) {
  // A distinct user per tab, so two tabs are two clients rather than one.
  let user_id = "web-" <> int.to_string(1000 + int.random(9000))
  let model =
    Model(
      status: Connecting,
      doc: None,
      canvas: None,
      user_id: user_id,
      offline: False,
      diagnostics: None,
      last_error: None,
    )
  #(
    model,
    watershed_lustre.connect_dev(
      url: socket_url,
      tenant: tenant,
      secret: tenant_secret,
      document: document_id,
      user_id: user_id,
      got_document: GotHandle,
      connected: Connected,
    ),
  )
}

// ── Update ───────────────────────────────────────────────────────────────────

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    // The handle exists, but the handshake has not landed yet — so there is
    // nothing to bootstrap on here, only diagnostics to start polling.
    GotHandle(doc) -> #(
      Model(
        ..model,
        doc: Some(doc),
        diagnostics: Some(watershed.diagnostics(doc)),
      ),
      watershed_lustre.after(250, DiagnosticsTick),
    )

    // `root_typed` is the line that makes this the standalone app rather than a
    // panel: it is the only place the document's root is named.
    Connected(Ok(_)) ->
      case model.doc {
        None -> #(Model(..model, status: Ready), effect.none())
        Some(doc) -> {
          let #(canvas, canvas_effect) =
            component.init(doc, watershed.root_typed(doc))
          #(
            Model(..model, status: Ready, canvas: Some(canvas)),
            effect.map(canvas_effect, Canvas),
          )
        }
      }
    Connected(Error(reason)) -> #(
      Model(..model, status: Failed(reason), last_error: Some(reason)),
      effect.none(),
    )

    Canvas(inner) ->
      case model.canvas {
        None -> #(model, effect.none())
        Some(canvas) -> {
          let #(canvas, canvas_effect) = component.update(canvas, inner)
          #(
            Model(..model, canvas: Some(canvas)),
            effect.map(canvas_effect, Canvas),
          )
        }
      }

    DiagnosticsTick ->
      case model.doc {
        None -> #(model, effect.none())
        Some(doc) -> #(
          Model(..model, diagnostics: Some(watershed.diagnostics(doc))),
          watershed_lustre.after(250, DiagnosticsTick),
        )
      }

    // Document-scoped, and therefore this module's. See the note at the top.
    ToggledOffline(offline) ->
      case model.doc {
        None -> #(model, effect.none())
        Some(doc) -> #(Model(..model, offline: offline), case offline {
          True -> watershed_lustre.go_offline(doc)
          False -> watershed_lustre.go_online(doc)
        })
      }
  }
}

// ── View ─────────────────────────────────────────────────────────────────────

fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("app")], [
    html.h1([], [html.text("watershed · pixel canvas")]),
    html.p([attribute.class("status")], [html.text(status_line(model))]),
    panel_view(model),
    toolbar(model),
    html.p([attribute.class("hint")], [
      html.text(
        "Open a second tab on the same URL and paint over the same cells. "
        <> "Go offline in one, keep painting in both, then come back.",
      ),
    ]),
    error_line(model),
  ])
}

fn panel_view(model: Model) -> Element(Msg) {
  case model.canvas {
    Some(canvas) -> component.view(canvas) |> element.map(Canvas)
    None -> html.p([attribute.class("status")], [html.text("connecting…")])
  }
}

fn toolbar(model: Model) -> Element(Msg) {
  let connected = option.is_some(model.doc)
  html.div([attribute.class("toolbar")], [
    html.button(
      [
        event.on_click(ToggledOffline(!model.offline)),
        attribute.attribute("aria-pressed", bool_text(model.offline)),
        attribute.disabled(!connected),
      ],
      [
        html.span([], [
          html.text(case model.offline {
            True -> "Come back online"
            False -> "Go offline"
          }),
        ]),
      ],
    ),
  ])
}

fn status_line(model: Model) -> String {
  let phase = case model.status, model.diagnostics {
    Failed(reason), _ -> "failed · " <> reason
    _, Some(diagnostics) -> diagnostics.phase
    Connecting, None -> "connecting"
    Ready, None -> "ready"
  }
  // `in_flight_count` is the real "waiting to reach the server" number: while
  // the socket is held, every painted cell lands there and stays.
  let waiting = case model.offline, model.diagnostics {
    True, Some(diagnostics) ->
      " · offline, "
      <> int.to_string(diagnostics.in_flight_count)
      <> " cells held"
    True, None -> " · offline"
    False, _ -> ""
  }
  "you are " <> model.user_id <> " · " <> phase <> waiting
}

fn error_line(model: Model) -> Element(Msg) {
  let reason = case model.last_error, model.canvas {
    Some(reason), _ -> Some(reason)
    None, Some(canvas) -> component.error(canvas)
    None, None -> None
  }
  case reason {
    None -> element.none()
    Some(reason) -> html.p([attribute.class("error")], [html.text(reason)])
  }
}

fn bool_text(value: Bool) -> String {
  case value {
    True -> "true"
    False -> "false"
  }
}
