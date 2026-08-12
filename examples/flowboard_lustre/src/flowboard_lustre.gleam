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
import watershed/browser
import watershed/presence
import watershed/presence_js.{type Handle}
import watershed_js.{type Document, type SharedCounter, type SharedMap}
import watershed_lustre

const socket_url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

pub fn main() {
  let app = lustre.application(init, update, view)
  let document = browser.document_on_navigate("flowboard")
  let assert Ok(_) = lustre.start(app, "#app", document)
  Nil
}

pub type BoardPresence {
  BoardPresence(card: Option(String))
}

fn encode_presence(presence: BoardPresence) -> Json {
  json.object([
    #("card", case presence.card {
      Some(card) -> json.string(card)
      None -> json.null()
    }),
  ])
}

fn presence_decoder() -> Decoder(BoardPresence) {
  use card <- decode.optional_field(
    "card",
    None,
    decode.optional(decode.string),
  )
  decode.success(BoardPresence(card:))
}

type Status {
  Connecting
  Ready
  Failed(String)
}

type Model {
  Model(
    status: Status,
    doc: Option(Document(doc_schema.Board)),
    cards_channel: Option(SharedMap),
    breaches_channel: Option(SharedCounter),
    user_id: String,
    title: String,
    cards: List(#(String, String)),
    breaches: Int,
    focus: Option(String),
    presence: Option(Handle(BoardPresence)),
    peers: List(presence.PresenceEntry(BoardPresence)),
    error: Option(String),
  )
}

type Msg {
  GotDocument(Document(doc_schema.Board))
  Connected(Result(Nil, String))
  EnsuredCards(Result(SharedMap, String))
  EnsuredBreaches(Result(SharedCounter, String))
  SharedChanged
  MoveCard(String, String)
  ReportBreach
  FocusCard(String)
  PresenceStarted(Handle(BoardPresence))
  PresenceEvent(presence.Event(BoardPresence))
}

fn init(document: String) -> #(Model, Effect(Msg)) {
  let user_id = "teammate-" <> int.to_string(1000 + int.random(9000))
  let model =
    Model(
      status: Connecting,
      doc: None,
      cards_channel: None,
      breaches_channel: None,
      user_id:,
      title: "Flowboard",
      cards: [],
      breaches: 0,
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
      document: document,
      user_id: user_id,
      got_document: GotDocument,
      connected: Connected,
    ),
  )
}

fn bootstrap_effect(doc: Document(doc_schema.Board)) -> Effect(Msg) {
  let root = watershed_js.root_typed(doc)
  effect.batch([
    watershed_lustre.ensure_field(
      root,
      doc_schema.title(),
      "Sprint board",
    ),
    watershed_lustre.ensure_map(
      doc,
      root,
      doc_schema.cards(),
      EnsuredCards,
    ),
    watershed_lustre.ensure_counter(
      doc,
      root,
      doc_schema.wip_breaches(),
      EnsuredBreaches,
    ),
    watershed_lustre.subscribe(watershed_js.root(doc), fn(_event) {
      SharedChanged
    }),
  ])
}

fn presence_effect(
  model: Model,
  doc: Document(doc_schema.Board),
) -> Effect(Msg) {
  watershed_lustre.presence(
    document: doc,
    config: presence.config(encode_presence, presence_decoder()),
    initial: BoardPresence(card: model.focus),
    started: PresenceStarted,
    on_event: PresenceEvent,
  )
}

fn announce_effect(model: Model) -> Effect(Msg) {
  case model.presence {
    Some(handle) ->
      watershed_lustre.update_presence(
        handle,
        BoardPresence(card: model.focus),
      )
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

    EnsuredCards(Ok(cards)) -> #(
      snapshot(Model(..model, cards_channel: Some(cards))),
      watershed_lustre.subscribe(cards, fn(_event) { SharedChanged }),
    )

    EnsuredCards(Error(reason)) -> #(
      Model(..model, error: Some(reason)),
      effect.none(),
    )

    EnsuredBreaches(Ok(breaches)) -> #(
      snapshot(Model(..model, breaches_channel: Some(breaches))),
      watershed_lustre.subscribe_counter(breaches, fn(_event) { SharedChanged }),
    )

    EnsuredBreaches(Error(reason)) -> #(
      Model(..model, error: Some(reason)),
      effect.none(),
    )

    // Both optimistic local edits and applied remote edits use this path.
    SharedChanged -> #(snapshot(model), effect.none())

    MoveCard(card_id, column) -> {
      case model.cards_channel {
        Some(cards) -> watershed_js.set(cards, card_id, json.string(column))
        None -> Nil
      }
      #(model, effect.none())
    }

    ReportBreach -> {
      case model.breaches_channel {
        Some(breaches) -> watershed_js.increment(breaches, 1)
        None -> Nil
      }
      #(model, effect.none())
    }

    FocusCard(card_id) -> {
      let model = Model(..model, focus: Some(card_id))
      #(model, announce_effect(model))
    }

    PresenceStarted(handle) -> #(
      Model(..model, presence: Some(handle)),
      effect.none(),
    )

    PresenceEvent(event) ->
      case event {
        presence.Failed(_) -> #(model, effect.none())
        presence.State(entries) | presence.Changed(_, entries) -> #(
          Model(..model, peers: remote_entries(model, entries)),
          effect.none(),
        )
      }
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

  let cards = case model.cards_channel {
    Some(channel) ->
      watershed_js.entries(channel)
      |> list.map(fn(entry) { #(entry.0, json.to_string(entry.1)) })
    None -> model.cards
  }

  let breaches = case model.breaches_channel {
    Some(channel) ->
      watershed_js.counter_value(channel)
      |> option.unwrap(model.breaches)
    None -> model.breaches
  }

  Model(..model, title:, cards:, breaches:, error:)
}

fn view(model: Model) -> Element(Msg) {
  html.main([], [
    html.header([], [
      html.h1([], [html.text(model.title)]),
      html.span([class("status")], [html.text(status_text(model.status))]),
    ]),
    html.p([], [
      html.text(
        "Open a second tab. Local card moves render at once; remote moves "
        <> "arrive through the same subscription.",
      ),
    ]),
    html.div([class("actions")], [
      html.button([event.on_click(MoveCard("card-12", "Doing"))], [
        html.text("Move card-12 → Doing"),
      ]),
      html.button([event.on_click(MoveCard("card-7", "Done"))], [
        html.text("Move card-7 → Done"),
      ]),
      html.button([event.on_click(ReportBreach)], [
        html.text("Report WIP breach"),
      ]),
    ]),
    html.h2([], [html.text("Cards")]),
    cards_view(model.cards),
    html.p([], [html.text("WIP breaches: " <> int.to_string(model.breaches))]),
    html.h2([], [html.text("Presence")]),
    html.p([class("peers")], [html.text(peers_text(model.peers))]),
    error_view(model.error),
  ])
}

fn cards_view(cards: List(#(String, String))) -> Element(Msg) {
  case cards {
    [] -> html.p([], [html.text("No cards yet.")])
    _ ->
      html.div(
        [],
        list.map(cards, fn(card) {
          html.div([class("card")], [
            html.span([], [html.text(card.0 <> ": " <> card.1)]),
            html.button([event.on_click(FocusCard(card.0))], [
              html.text("Focus"),
            ]),
          ])
        }),
      )
  }
}

/// Everyone but this teammate. Presence state includes the local session by
/// design, so the roster is filtered here rather than in the driver.
fn remote_entries(
  model: Model,
  entries: List(presence.PresenceEntry(BoardPresence)),
) -> List(presence.PresenceEntry(BoardPresence)) {
  case model.presence {
    Some(handle) ->
      case presence_js.local_session(handle) {
        Some(session) -> presence.remote_entries(entries, session)
        None -> entries
      }
    None -> entries
  }
}

fn peers_text(peers: List(presence.PresenceEntry(BoardPresence))) -> String {
  case peers {
    [] -> "No other teammates connected."
    _ ->
      peers
      |> list.map(fn(peer) {
        let BoardPresence(card:) = peer.meta
        peer.key
        <> case card {
          Some(card) -> " is focused on " <> card
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
