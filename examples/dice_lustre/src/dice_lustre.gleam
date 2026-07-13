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
import lustre/attribute.{class}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import watershed/map_kernel
import watershed_js.{type Document}
import watershed_lustre

// ── Dev config for `just server` (levee dev mode) ────────────────────────────

const socket_url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

const document_id = "dice"

const die_key = "die"

pub fn main() {
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
    doc: Option(Document),
    user_id: String,
    die: Option(String),
    entries: List(#(String, String)),
    diagnostics: Option(watershed_js.Diagnostics),
    diagnostic_log: List(String),
  )
}

type Msg {
  GotHandle(Document)
  Connected(Result(Nil, String))
  MapChanged(map_kernel.MapEvent)
  DiagnosticsTick
  RollClicked
  ClearClicked
  ReconnectClicked
}

fn init(_args) -> #(Model, Effect(Msg)) {
  // A distinct user per tab so the two clients are separate connections.
  let user_id = "web-" <> int.to_string(1000 + int.random(9000))
  let model =
    Model(
      status: Connecting,
      doc: None,
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
    // The handle is ready: subscribe to the root map. Local and remote edits
    // both surface as `MapChanged`; the binding defers each dispatch so a local
    // edit made from inside `update` can't clobber the running cycle.
    GotHandle(doc) -> {
      let diagnostics = watershed_js.diagnostics(doc)
      let model =
        Model(..model, doc: Some(doc), diagnostics: Some(diagnostics))
        |> add_diagnostic(
          "document handle acquired · " <> diagnostic_line(diagnostics),
        )
      #(
        model,
        effect.batch([
          watershed_lustre.subscribe(watershed_js.root(doc), MapChanged),
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
      let diagnostics = case model.doc {
        Some(doc) -> Some(watershed_js.diagnostics(doc))
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
      let next = case model.doc {
        Some(doc) -> Some(watershed_js.diagnostics(doc))
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
      case model.doc {
        Some(doc) ->
          watershed_js.set(watershed_js.root(doc), die_key, json.int(roll))
        None -> Nil
      }
      #(model, effect.none())
    }

    ClearClicked -> {
      case model.doc {
        Some(doc) -> watershed_js.clear(watershed_js.root(doc))
        None -> Nil
      }
      #(model, effect.none())
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

/// Re-read the optimistic map state into the model for rendering.
fn snapshot(model: Model) -> Model {
  case model.doc {
    None -> model
    Some(doc) -> {
      let map = watershed_js.root(doc)
      let die =
        watershed_js.get(map, die_key)
        |> option.map(json.to_string)
      let entries =
        watershed_js.entries(map)
        |> list.map(fn(pair) { #(pair.0, json.to_string(pair.1)) })
      Model(..model, die: die, entries: entries)
    }
  }
}

fn add_diagnostic(model: Model, line: String) -> Model {
  let tagged = "[" <> model.user_id <> "] " <> line
  io.println(tagged)
  Model(..model, diagnostic_log: take([tagged, ..model.diagnostic_log], 40))
}

fn take(items: List(a), count: Int) -> List(a) {
  case items, count {
    _, count if count <= 0 -> []
    [], _ -> []
    [first, ..rest], _ -> [first, ..take(rest, count - 1)]
  }
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

fn diagnostic_line(diagnostics: watershed_js.Diagnostics) -> String {
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
  <> bool_string(diagnostics.synced)
}

fn option_int(value: Option(Int)) -> String {
  value
  |> option.map(int.to_string)
  |> option.unwrap("none")
}

fn bool_string(value: Bool) -> String {
  case value {
    True -> "true"
    False -> "false"
  }
}

// ── View ─────────────────────────────────────────────────────────────────────

fn view(model: Model) -> Element(Msg) {
  html.main([class("wrap")], [
    html.h1([], [html.text("watershed · collaborative dice")]),
    status_line(model),
    html.div([class("die")], [html.text(option.unwrap(model.die, "–"))]),
    html.div([class("controls")], [
      html.button([event.on_click(RollClicked)], [html.text("Roll")]),
      html.button([event.on_click(ClearClicked)], [html.text("Clear")]),
      html.button([event.on_click(ReconnectClicked)], [
        html.text("Force reconnect"),
      ]),
    ]),
    entries_view(model.entries),
    diagnostics_view(model),
    html.p([class("hint")], [
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
  html.p([class("status")], [html.text(text)])
}

fn entries_view(entries: List(#(String, String))) -> Element(Msg) {
  case entries {
    [] -> html.p([class("empty")], [html.text("(map is empty)")])
    _ ->
      html.ul(
        [class("entries")],
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
  html.section([class("diagnostics")], [
    html.h2([], [html.text("Diagnostics")]),
    html.p([], [
      html.text(
        "Compare this panel across tabs. Browser DevTools receives the same trace.",
      ),
    ]),
    html.pre([class("diagnostic-current")], [html.text(current)]),
    html.pre([class("diagnostic-log")], [html.text(log)]),
  ])
}
