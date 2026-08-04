import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

import lustre
import lustre/attribute.{class}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import doc_schema
import watershed/presence.{type Peer}
import watershed/presence_js.{type Handle}
import watershed_js.{type Document, type SharedCounter, type SharedMap}
import watershed_lustre

const socket_url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

const document_id = "bench-book"

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

pub type SurveyPresence {
  SurveyPresence(station: Option(String))
}

fn encode_presence(presence: SurveyPresence) -> Json {
  json.object([
    #("station", case presence.station {
      Some(station) -> json.string(station)
      None -> json.null()
    }),
  ])
}

fn presence_decoder() -> Decoder(SurveyPresence) {
  use station <- decode.optional_field(
    "station",
    None,
    decode.optional(decode.string),
  )
  decode.success(SurveyPresence(station:))
}

type Status {
  Connecting
  Ready
  Failed(String)
}

type Model {
  Model(
    status: Status,
    doc: Option(Document),
    readings_channel: Option(SharedMap),
    flags_channel: Option(SharedCounter),
    user_id: String,
    title: String,
    readings: List(#(String, String)),
    flags: Int,
    focus: Option(String),
    presence: Option(Handle(SurveyPresence)),
    peers: List(Peer(SurveyPresence)),
    error: Option(String),
  )
}

type Msg {
  GotDocument(Document)
  Connected(Result(Nil, String))
  EnsuredReadings(Result(SharedMap, String))
  EnsuredFlags(Result(SharedCounter, String))
  SharedChanged
  RecordReading(String, Float)
  AddFlag
  FocusStation(String)
  PresenceStarted(Handle(SurveyPresence))
  PeersChanged(List(Peer(SurveyPresence)))
}

fn init(_args) -> #(Model, Effect(Msg)) {
  let user_id = "surveyor-" <> int.to_string(1000 + int.random(9000))
  let model =
    Model(
      status: Connecting,
      doc: None,
      readings_channel: None,
      flags_channel: None,
      user_id:,
      title: "Bench Book",
      readings: [],
      flags: 0,
      focus: None,
      presence: None,
      peers: [],
      error: None,
    )

  #(
    model,
    watershed_lustre.connect_dev(
      url: socket_url,
      tenant: tenant,
      secret: tenant_secret,
      document: document_id,
      user_id: user_id,
      got_document: GotDocument,
      connected: Connected,
    ),
  )
}

fn bootstrap_effect(doc: Document) -> Effect(Msg) {
  let root = watershed_js.root_typed(doc)
  effect.batch([
    watershed_lustre.ensure_field(
      root,
      doc_schema.title(),
      "Mill Race spring survey",
    ),
    watershed_lustre.ensure_map(
      doc,
      root,
      doc_schema.readings(),
      EnsuredReadings,
    ),
    watershed_lustre.ensure_counter(doc, root, doc_schema.flags(), EnsuredFlags),
    watershed_lustre.subscribe(watershed_js.root(doc), fn(_event) {
      SharedChanged
    }),
  ])
}

fn presence_effect(model: Model, doc: Document) -> Effect(Msg) {
  watershed_lustre.presence(
    document: doc,
    user_id: model.user_id,
    config: presence.default_config,
    encode: encode_presence,
    decode: presence_decoder(),
    started: PresenceStarted,
    on_peers: PeersChanged,
  )
}

fn announce_effect(model: Model) -> Effect(Msg) {
  case model.presence {
    Some(handle) ->
      watershed_lustre.announce(handle, SurveyPresence(station: model.focus))
    None -> effect.none()
  }
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    GotDocument(doc) -> {
      let model = Model(..model, doc: Some(doc))
      #(model, presence_effect(model, doc))
    }

    Connected(Ok(_)) ->
      case model.doc {
        Some(doc) -> #(Model(..model, status: Ready), bootstrap_effect(doc))
        None -> #(model, effect.none())
      }

    Connected(Error(reason)) -> #(
      Model(..model, status: Failed(reason), error: Some(reason)),
      effect.none(),
    )

    EnsuredReadings(Ok(readings)) -> #(
      snapshot(Model(..model, readings_channel: Some(readings))),
      watershed_lustre.subscribe(readings, fn(_event) { SharedChanged }),
    )

    EnsuredReadings(Error(reason)) -> #(
      Model(..model, error: Some(reason)),
      effect.none(),
    )

    EnsuredFlags(Ok(flags)) -> #(
      snapshot(Model(..model, flags_channel: Some(flags))),
      watershed_lustre.subscribe_counter(flags, fn(_event) { SharedChanged }),
    )

    EnsuredFlags(Error(reason)) -> #(
      Model(..model, error: Some(reason)),
      effect.none(),
    )

    // Both optimistic local edits and applied remote edits use this path.
    SharedChanged -> #(snapshot(model), effect.none())

    RecordReading(station, depth) -> {
      case model.readings_channel {
        Some(readings) -> watershed_js.set(readings, station, json.float(depth))
        None -> Nil
      }
      #(model, effect.none())
    }

    AddFlag -> {
      case model.flags_channel {
        Some(flags) -> watershed_js.increment(flags, 1)
        None -> Nil
      }
      #(model, effect.none())
    }

    FocusStation(station) -> {
      let model = Model(..model, focus: Some(station))
      #(model, announce_effect(model))
    }

    PresenceStarted(handle) -> {
      let model = Model(..model, presence: Some(handle))
      #(model, announce_effect(model))
    }

    PeersChanged(peers) -> #(Model(..model, peers: peers), effect.none())
  }
}

fn snapshot(model: Model) -> Model {
  let #(title, error) = case model.doc {
    Some(doc) ->
      case
        watershed_js.get_field(watershed_js.root_typed(doc), doc_schema.title())
      {
        Ok(Some(title)) -> #(title, model.error)
        Ok(None) -> #(model.title, model.error)
        Error(_) -> #(model.title, Some("The shared title is not a string."))
      }
    None -> #(model.title, model.error)
  }

  let readings = case model.readings_channel {
    Some(channel) ->
      watershed_js.entries(channel)
      |> list.map(fn(entry) { #(entry.0, json.to_string(entry.1)) })
    None -> model.readings
  }

  let flags = case model.flags_channel {
    Some(channel) ->
      watershed_js.counter_value(channel)
      |> option.unwrap(model.flags)
    None -> model.flags
  }

  Model(..model, title:, readings:, flags:, error:)
}

fn view(model: Model) -> Element(Msg) {
  html.main([], [
    html.header([], [
      html.h1([], [html.text(model.title)]),
      html.span([class("status")], [html.text(status_text(model.status))]),
    ]),
    html.p([], [
      html.text(
        "Open a second tab. Local readings render at once; remote readings "
        <> "arrive through the same subscription.",
      ),
    ]),
    html.div([class("actions")], [
      html.button([event.on_click(RecordReading("station-7", 3.2))], [
        html.text("Record station-7: 3.2 m"),
      ]),
      html.button([event.on_click(RecordReading("station-4", 2.4))], [
        html.text("Record station-4: 2.4 m"),
      ]),
      html.button([event.on_click(AddFlag)], [
        html.text("Flag for re-check"),
      ]),
    ]),
    html.h2([], [html.text("Readings")]),
    readings_view(model.readings),
    html.p([], [html.text("Re-check flags: " <> int.to_string(model.flags))]),
    html.h2([], [html.text("Presence")]),
    html.p([class("peers")], [html.text(peers_text(model.peers))]),
    error_view(model.error),
  ])
}

fn readings_view(readings: List(#(String, String))) -> Element(Msg) {
  case readings {
    [] -> html.p([], [html.text("No readings yet.")])
    _ ->
      html.div(
        [],
        list.map(readings, fn(reading) {
          html.div([class("station")], [
            html.span([], [html.text(reading.0 <> ": " <> reading.1 <> " m")]),
            html.button([event.on_click(FocusStation(reading.0))], [
              html.text("Inspect"),
            ]),
          ])
        }),
      )
  }
}

fn peers_text(peers: List(Peer(SurveyPresence))) -> String {
  case peers {
    [] -> "No other surveyors connected."
    _ ->
      peers
      |> list.map(fn(peer) {
        let SurveyPresence(station:) = peer.payload
        peer.user
        <> case station {
          Some(station) -> " is inspecting " <> station
          None -> " is connected"
        }
      })
      |> string.join(", ")
  }
}

fn status_text(status: Status) -> String {
  case status {
    Connecting -> "connecting"
    Ready -> "connected"
    Failed(reason) -> "failed: " <> reason
  }
}

fn error_view(error: Option(String)) -> Element(Msg) {
  case error {
    Some(reason) -> html.p([class("error")], [html.text(reason)])
    None -> html.text("")
  }
}
