//// Gleam-end-to-end collaborative dice roller.
////
//// A Lustre single-page app whose entire client — UI, optimistic SharedMap,
//// wire codecs, reconnect state machine — is Gleam compiled to JavaScript.
//// The only non-Gleam pieces are the FFI shim over the official Phoenix JS
//// client and Lustre's own runtime.
////
//// Open two browser tabs against the same `just server` document and watch
//// rolls converge. Roll during a forced reconnect and nothing is lost.

import gleam/int
import gleam/io
import gleam/json
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
import watershed/map_kernel
import watershed_lustre

import dice_lustre/document_schema

// ── Dev config for `just server` (levee dev mode) ────────────────────────────

const socket_url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

const die_key = "die"

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let document = browser.document_on_navigate("dice")
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
    document: Option(Document(document_schema.DiceDocument)),
    user_id: String,
    die: Option(String),
    entries: List(#(String, String)),
    diagnostics: Option(watershed.Diagnostics),
    diagnostic_log: List(String),
  )
}

type Msg {
  GotHandle(Document(document_schema.DiceDocument))
  Connected(Result(Nil, String))
  MapChanged(map_kernel.MapEvent)
  DiagnosticsTick
  RollClicked
  ClearClicked
  ReconnectClicked
}

fn init(document: String) -> #(Model, Effect(Msg)) {
  // A distinct user per tab so the two clients are separate connections.
  let user_id = "web-" <> int.to_string(1000 + int.random(9000))
  let model =
    Model(
      status: Connecting,
      document: None,
      user_id: user_id,
      die: None,
      entries: [],
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
    // The handle is ready: subscribe to the root map. Local and remote edits
    // both surface as `MapChanged`; the binding defers each dispatch so a local
    // edit made from inside `update` can't clobber the running cycle.
    GotHandle(document) -> {
      let diagnostics = watershed.diagnostics(document)
      let model =
        Model(..model, document: Some(document), diagnostics: Some(diagnostics))
        |> add_diagnostic(
          "document handle acquired · " <> diagnostic_line(diagnostics),
        )
      #(
        model,
        effect.batch([
          watershed_lustre.subscribe(watershed.root(document), MapChanged),
          watershed_lustre.after(250, DiagnosticsTick),
        ]),
      )
    }

    Connected(Ok(_)) -> {
      let model =
        snapshot(Model(..model, status: Ready))
        |> add_diagnostic("initial handshake complete")
      #(model, effect.none())
    }
    Connected(Error(reason)) -> {
      let model =
        Model(..model, status: Failed(reason))
        |> add_diagnostic("connection failed · " <> reason)
      #(model, effect.none())
    }

    // A map event fired (local or remote): refresh our view of the state.
    MapChanged(event) -> {
      let diagnostics = case model.document {
        Some(document) -> Some(watershed.diagnostics(document))
        None -> None
      }
      let detail = case diagnostics {
        Some(diagnostics) ->
          event_line(event) <> " · " <> diagnostic_line(diagnostics)
        None -> event_line(event)
      }
      let model =
        snapshot(Model(..model, diagnostics: diagnostics))
        |> add_diagnostic(detail)
      #(model, effect.none())
    }

    DiagnosticsTick -> {
      let next = case model.document {
        Some(document) -> Some(watershed.diagnostics(document))
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

    RollClicked -> {
      let roll = 1 + int.random(6)
      case model.document {
        Some(document) ->
          watershed.set(watershed.root(document), die_key, json.int(roll))
        None -> Nil
      }
      #(model, effect.none())
    }

    ClearClicked -> {
      case model.document {
        Some(document) -> watershed.clear(watershed.root(document))
        None -> Nil
      }
      #(model, effect.none())
    }

    ReconnectClicked ->
      case model.document {
        Some(document) -> #(
          add_diagnostic(model, "force reconnect requested"),
          watershed_lustre.force_reconnect(document),
        )
        None -> #(model, effect.none())
      }
  }
}

/// Re-read the optimistic map state into the model for rendering.
fn snapshot(model: Model) -> Model {
  case model.document {
    None -> model
    Some(document) -> {
      let map = watershed.root(document)
      let die =
        watershed.get(map, die_key)
        |> option.from_result
        |> option.map(json.to_string)
      let entries =
        watershed.entries(map)
        |> list.map(fn(pair) { #(pair.0, json.to_string(pair.1)) })
      Model(..model, die: die, entries: entries)
    }
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

fn event_line(event: map_kernel.MapEvent) -> String {
  case event {
    map_kernel.ValueChanged(key, previous, value, local) ->
      origin(local)
      <> " valueChanged key="
      <> key
      <> " previous="
      <> option_json(previous)
      <> " value="
      <> option_json(value)
    map_kernel.Cleared(local) -> origin(local) <> " cleared"
  }
}

fn origin(local: Bool) -> String {
  case local {
    True -> "local"
    False -> "remote"
  }
}

fn option_json(value: Option(json.Json)) -> String {
  case value {
    Some(value) -> json.to_string(value)
    None -> "none"
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
    html.h1([], [html.text("watershed · collaborative dice")]),
    status_line(model),
    html.div([attribute.class("die")], [
      html.text(option.unwrap(model.die, "–")),
    ]),
    html.div([attribute.class("controls")], [
      html.button([event.on_click(RollClicked)], [html.text("Roll")]),
      html.button([event.on_click(ClearClicked)], [html.text("Clear")]),
      html.button([event.on_click(ReconnectClicked)], [
        html.text("Force reconnect"),
      ]),
    ]),
    entries_view(model.entries),
    diagnostics_view(model),
    html.p([attribute.class("hint")], [
      html.text(
        "Open a second tab on the same document to see rolls converge. "
        <> "Client: "
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
  let text = connection <> runtime
  html.p([attribute.class("status")], [html.text(text)])
}

fn entries_view(entries: List(#(String, String))) -> Element(Msg) {
  case entries {
    [] -> html.p([attribute.class("empty")], [html.text("(map is empty)")])
    _ ->
      html.ul(
        [attribute.class("entries")],
        list.map(entries, fn(pair) {
          html.li([], [html.text(pair.0 <> " = " <> pair.1)])
        }),
      )
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
