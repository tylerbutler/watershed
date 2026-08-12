//// Collaborative clap counter — Medium-style claps on a `PnCounter`.
////
//// A Lustre single-page app: one channel, one `PnCounter`, one button. Hold
//// the button down in four tabs at once and watch the number stay correct —
//// the most direct possible stress test of a single counter under
//// concurrency, since a `PnCounter` merges as a state-based CRDT rather than
//// serializing through last-write-wins.
////
//// This app only ever increments. The kernel underneath can also decrement
//// (it's a full P/N counter, not a dedicated grow-only one — see
//// `doc_schema.gleam`), but nothing here calls that path.

import gleam/int
import gleam/io
import gleam/option.{type Option, None, Some}
import gleam/string

import lustre
import lustre/attribute.{class}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import doc_schema
import watershed/browser
import watershed/pn_counter_kernel
import watershed_js.{type Document, type PnCounter}
import watershed_lustre

// ── Dev config for `just integration-up` (floodgate dev server) ─────────────

const socket_url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

pub fn main() {
  let app = lustre.application(init, update, view)
  let document = browser.document_on_navigate("clap-counter")
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
    doc: Option(Document(doc_schema.ClapDoc)),
    user_id: String,
    counter: Option(PnCounter),
    claps: Int,
    diagnostics: Option(watershed_js.Diagnostics),
    diagnostic_log: List(String),
  )
}

type Msg {
  GotHandle(Document(doc_schema.ClapDoc))
  Connected(Result(Nil, String))
  EnsuredCounter(Result(PnCounter, String))
  CounterChanged(pn_counter_kernel.PnCounterEvent)
  DiagnosticsTick
  ClapClicked
  ReconnectClicked
}

fn init(document: String) -> #(Model, Effect(Msg)) {
  // A distinct user per tab so the two clients are separate connections.
  let user_id = "web-" <> int.to_string(1000 + int.random(9000))
  let model =
    Model(
      status: Connecting,
      doc: None,
      user_id: user_id,
      counter: None,
      claps: 0,
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
    GotHandle(doc) -> {
      let model = Model(..model, doc: Some(doc))
      case model.status, model.counter {
        Ready, None -> #(model, bootstrap_effect(doc))
        _, _ -> #(model, effect.none())
      }
    }

    Connected(Ok(_)) -> {
      let model = Model(..model, status: Ready)
      let model = add_diagnostic(model, "initial handshake complete")
      case model.doc, model.counter {
        Some(doc), None -> #(model, bootstrap_effect(doc))
        _, _ -> #(model, effect.none())
      }
    }
    Connected(Error(reason)) -> {
      let model =
        Model(..model, status: Failed(reason))
        |> add_diagnostic("connection failed · " <> reason)
      #(model, effect.none())
    }

    EnsuredCounter(Ok(counter)) -> {
      let diagnostics = case model.doc {
        Some(doc) -> Some(watershed_js.diagnostics(doc))
        None -> None
      }
      let model =
        Model(..model, counter: Some(counter), diagnostics: diagnostics)
        |> add_diagnostic("counter ready")
      #(
        snapshot(model),
        effect.batch([
          watershed_lustre.subscribe_pn_counter(counter, CounterChanged),
          watershed_lustre.after(250, DiagnosticsTick),
        ]),
      )
    }
    EnsuredCounter(Error(reason)) -> {
      let model =
        Model(..model, status: Failed(reason))
        |> add_diagnostic("ensure counter failed · " <> reason)
      #(model, effect.none())
    }

    CounterChanged(pn_counter_kernel.Updated(applied, new_value)) -> {
      let diagnostics = case model.doc {
        Some(doc) -> Some(watershed_js.diagnostics(doc))
        None -> None
      }
      let detail =
        "applied="
        <> int.to_string(applied)
        <> " value="
        <> int.to_string(new_value)
      let model =
        Model(..model, claps: new_value, diagnostics: diagnostics)
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

    ClapClicked -> {
      case model.counter {
        Some(counter) -> watershed_js.pn_counter_update(counter, 1)
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

/// Bootstrap the document: adopt-or-seed the counter and watch it.
fn bootstrap_effect(doc: Document(doc_schema.ClapDoc)) -> Effect(Msg) {
  let root = watershed_js.root_typed(doc)
  watershed_lustre.ensure_pn_counter(
    doc,
    root,
    doc_schema.claps(),
    EnsuredCounter,
  )
}

/// Re-read the optimistic counter value into the model for rendering.
fn snapshot(model: Model) -> Model {
  case model.counter {
    None -> model
    Some(counter) -> {
      let value =
        watershed_js.pn_counter_value(counter) |> option.unwrap(model.claps)
      Model(..model, claps: value)
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
    html.h1([], [html.text("watershed · collaborative claps")]),
    status_line(model),
    html.div([class("count")], [html.text(int.to_string(model.claps))]),
    html.div([class("controls")], [
      html.button([class("clap-button"), event.on_click(ClapClicked)], [
        html.text("👏 Clap"),
      ]),
      html.button([event.on_click(ReconnectClicked)], [
        html.text("Force reconnect"),
      ]),
    ]),
    diagnostics_view(model),
    html.p([class("hint")], [
      html.text(
        "Open a second tab on the same document and hold the button down in both. "
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
