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
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}

import lustre
import lustre/attribute.{class}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import watershed/map_kernel.{type MapEvent}
import watershed_js.{type Document, WatershedConfig}

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
  )
}

type Msg {
  GotHandle(Document)
  Connected(Result(Nil, String))
  MapChanged
  RollClicked
  ClearClicked
  ReconnectClicked
}

fn init(_args) -> #(Model, Effect(Msg)) {
  // A distinct user per tab so the two clients are separate connections.
  let user_id = "web-" <> int.to_string(watershed_js.random_int(1000, 9999))
  let model =
    Model(
      status: Connecting,
      doc: None,
      user_id: user_id,
      die: None,
      entries: [],
    )
  #(model, connect_effect(user_id))
}

/// Connect, then bridge watershed's callbacks into Lustre's dispatch.
fn connect_effect(user_id: String) -> Effect(Msg) {
  use dispatch <- effect.from
  let token =
    watershed_js.dev_token(
      secret: tenant_secret,
      tenant: tenant,
      document: document_id,
      user_id: user_id,
    )
  let doc =
    watershed_js.connect(
      WatershedConfig(
        url: socket_url,
        tenant: tenant,
        document: document_id,
        token: token,
        user_id: user_id,
      ),
      on_ready: fn(result) { dispatch(Connected(result)) },
    )
  let map = watershed_js.root(doc)
  // Local and remote edits both surface here; we re-read the map on each.
  watershed_js.subscribe(map, fn(_event: MapEvent) { dispatch(MapChanged) })
  dispatch(GotHandle(doc))
}

// ── Update ───────────────────────────────────────────────────────────────────

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    GotHandle(doc) -> #(Model(..model, doc: Some(doc)), effect.none())

    Connected(Ok(_)) -> #(
      snapshot(Model(..model, status: Ready)),
      effect.none(),
    )
    Connected(Error(reason)) -> #(
      Model(..model, status: Failed(reason)),
      effect.none(),
    )

    // A map event fired (local or remote): refresh our view of the state.
    MapChanged -> #(snapshot(model), effect.none())

    RollClicked -> {
      case model.doc {
        Some(doc) ->
          watershed_js.set(
            watershed_js.root(doc),
            die_key,
            json.int(watershed_js.random_int(1, 6)),
          )
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

    ReconnectClicked -> {
      case model.doc {
        Some(doc) -> watershed_js.force_reconnect(doc)
        None -> Nil
      }
      #(model, effect.none())
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
  let text = case model.status {
    Connecting -> "connecting…"
    Ready -> "connected"
    Failed(reason) -> "failed: " <> reason
  }
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
