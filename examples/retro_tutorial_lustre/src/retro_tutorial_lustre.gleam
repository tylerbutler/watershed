//// Small collaborative retro board for the tutorial track.
////
//// This example keeps one root field (`title`), one RegisterMode OR-map for
//// notes, one TallyMode OR-map for votes, and presence for the focused note.
//// It omits sequences, drag and drop, edit/delete, and vote budgets.

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import watershed.{type Document, type OrMap}
import watershed/browser
import watershed/or_map_kernel
import watershed/presence
import watershed/presence_js.{type Handle}
import watershed/transport_js
import watershed_lustre

import retro_tutorial_lustre/board.{type Column, type NoteCard}
import retro_tutorial_lustre/document_schema

// docs:snippet-start guide-connect-dev-constants
/// These dev constants match `just integration-up`.
/// Change them when you point the example at another server.
const socket_url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

// docs:snippet-end guide-connect-dev-constants

// docs:snippet-start retro-app-main
pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let document = browser.document_on_navigate("retro-tutorial")
  let assert Ok(_) = lustre.start(app, "#app", document)
  Nil
}

// docs:snippet-end retro-app-main

// docs:snippet-start retro-app-presence-type
pub type BoardPresence {
  BoardPresence(color: String, name: String, focused_note: Option(String))
}

// docs:snippet-end retro-app-presence-type

// docs:snippet-start retro-app-encode-presence
fn encode_presence(presence: BoardPresence) -> json.Json {
  json.object([
    #("color", json.string(presence.color)),
    #("name", json.string(presence.name)),
    #("focused_note", case presence.focused_note {
      Some(id) -> json.string(id)
      None -> json.null()
    }),
  ])
}

// docs:snippet-end retro-app-encode-presence

// docs:snippet-start retro-app-presence-decoder
fn presence_decoder() -> decode.Decoder(BoardPresence) {
  use color <- decode.field("color", decode.string)
  use name <- decode.field("name", decode.string)
  use focused_note <- decode.optional_field(
    "focused_note",
    None,
    decode.optional(decode.string),
  )
  decode.success(BoardPresence(color:, name:, focused_note:))
}

// docs:snippet-end retro-app-presence-decoder

type Status {
  Connecting
  Ready
  Failed(reason: String)
}

type SharedState {
  SharedState(notes: OrMap, votes: OrMap)
}

type PendingShared {
  PendingShared(notes: Option(OrMap), votes: Option(OrMap))
}

type Model {
  Model(
    status: Status,
    document: Option(Document(document_schema.BoardDocument)),
    shared: Option(SharedState),
    pending: PendingShared,
    user_id: String,
    color: String,
    focus: Option(String),
    presence: Option(Handle(BoardPresence)),
    peers: List(presence.PresenceEntry(BoardPresence)),
    board: board.Snapshot,
    drafts: Dict(String, String),
    last_error: Option(String),
  )
}

type Msg {
  GotDocument(Document(document_schema.BoardDocument))
  Connected(Result(Nil, String))
  EnsuredNotes(Result(OrMap, String))
  EnsuredVotes(Result(OrMap, String))
  SharedChanged
  DraftChanged(Column, String)
  AddClicked(Column)
  UpvoteClicked(String)
  DownvoteClicked(String)
  FocusClicked(String)
  FocusCleared
  PresenceStarted(Handle(BoardPresence))
  PresenceEvent(presence.Event(BoardPresence))
  ReconnectClicked
}

// docs:snippet-start retro-app-init
fn init(document: String) -> #(Model, Effect(Msg)) {
  let user_id = "web-" <> int.to_string(1000 + int.random(9000))
  let model =
    Model(
      status: Connecting,
      document: None,
      shared: None,
      pending: PendingShared(None, None),
      user_id: user_id,
      color: presence.color_for(user_id),
      focus: None,
      presence: None,
      peers: [],
      board: board.empty("Sprint retro"),
      drafts: dict.new(),
      last_error: None,
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

// docs:snippet-end retro-app-init

// docs:snippet-start retro-app-bootstrap-effect
fn bootstrap_effect(
  document: Document(document_schema.BoardDocument),
) -> Effect(Msg) {
  let root = watershed.root_typed(document)
  effect.batch([
    watershed_lustre.ensure_field(root, document_schema.title(), "Sprint retro"),
    watershed_lustre.ensure_or_map(
      document,
      root,
      document_schema.notes(),
      or_map_kernel.RegisterMode,
      EnsuredNotes,
    ),
    watershed_lustre.ensure_or_map(
      document,
      root,
      document_schema.votes(),
      or_map_kernel.TallyMode,
      EnsuredVotes,
    ),
    watershed_lustre.subscribe(watershed.root(document), fn(_event) {
      SharedChanged
    }),
  ])
}

// docs:snippet-end retro-app-bootstrap-effect

// docs:snippet-start retro-app-presence-effect
fn presence_effect(
  model: Model,
  document: Document(document_schema.BoardDocument),
) -> Effect(Msg) {
  watershed_lustre.presence(
    document: document,
    config: presence.config(encode_presence, presence_decoder()),
    initial: current_presence(model),
    started: PresenceStarted,
    on_event: PresenceEvent,
  )
}

// docs:snippet-end retro-app-presence-effect

// docs:snippet-start retro-app-current-presence
fn current_presence(model: Model) -> BoardPresence {
  BoardPresence(
    color: model.color,
    name: presence.short_name(model.user_id),
    focused_note: model.focus,
  )
}

// docs:snippet-end retro-app-current-presence

// docs:snippet-start retro-app-announce-focus
fn announce_focus(model: Model) -> Effect(Msg) {
  case model.presence {
    Some(handle) ->
      watershed_lustre.update_presence(handle, current_presence(model))
    None -> effect.none()
  }
}

// docs:snippet-end retro-app-announce-focus

// docs:snippet-start retro-app-assemble
fn assemble(model: Model) -> #(Model, Effect(Msg)) {
  case model.shared, model.pending {
    None, PendingShared(Some(notes), Some(votes)) -> {
      let shared = SharedState(notes:, votes:)
      let model = snapshot(Model(..model, shared: Some(shared)))
      #(
        model,
        effect.batch([
          watershed_lustre.subscribe_or_map(shared.notes, fn(_) {
            SharedChanged
          }),
          watershed_lustre.subscribe_or_map(shared.votes, fn(_) {
            SharedChanged
          }),
        ]),
      )
    }
    _, _ -> #(model, effect.none())
  }
}

// docs:snippet-end retro-app-assemble

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    // docs:snippet-start update-readiness
    GotDocument(document) -> {
      let model = Model(..model, document: Some(document))
      let presence_start = presence_effect(model, document)
      case model.status, model.shared {
        Ready, None -> #(
          model,
          effect.batch([bootstrap_effect(document), presence_start]),
        )
        _, _ -> #(model, presence_start)
      }
    }

    Connected(Ok(_)) -> {
      let model = Model(..model, status: Ready)
      case model.document, model.shared {
        Some(document), None -> #(model, bootstrap_effect(document))
        _, _ -> #(model, effect.none())
      }
    }

    Connected(Error(reason)) -> #(
      Model(..model, status: Failed(reason), last_error: Some(reason)),
      effect.none(),
    )

    // docs:snippet-end update-readiness
    // docs:snippet-start lifecycle-ensured-arms
    EnsuredNotes(Ok(notes)) ->
      Model(
        ..model,
        pending: PendingShared(..model.pending, notes: Some(notes)),
      )
      |> assemble
    EnsuredNotes(Error(reason)) -> #(
      Model(..model, last_error: Some("notes channel failed: " <> reason)),
      effect.none(),
    )

    EnsuredVotes(Ok(votes)) ->
      Model(
        ..model,
        pending: PendingShared(..model.pending, votes: Some(votes)),
      )
      |> assemble
    EnsuredVotes(Error(reason)) -> #(
      Model(..model, last_error: Some("votes channel failed: " <> reason)),
      effect.none(),
    )

    // docs:snippet-end lifecycle-ensured-arms
    SharedChanged -> #(snapshot(model), effect.none())

    DraftChanged(column, text) -> #(
      Model(
        ..model,
        drafts: dict.insert(model.drafts, board.column_id(column), text),
      ),
      effect.none(),
    )

    // docs:snippet-start guide-notes-add-clicked
    // These watershed mutations apply synchronously.
    // The subscriptions deliver the render message `SharedChanged`.
    // These branches do not need Lustre effect wrappers.
    AddClicked(column) -> {
      let text = string.trim(draft_for(model, column))
      case text, model.shared {
        "", _ -> #(model, effect.none())
        _, None -> #(model, effect.none())
        _, Some(shared) -> {
          let created = transport_js.now_milliseconds()
          let _ =
            board.add_note(
              shared.notes,
              model.user_id,
              text,
              column,
              created,
              int.random(10_000),
            )
          let model =
            Model(
              ..model,
              drafts: dict.delete(model.drafts, board.column_id(column)),
            )
          #(snapshot(model), effect.none())
        }
      }
    }

    // docs:snippet-end guide-notes-add-clicked
    // docs:snippet-start guide-votes-vote-clicks
    UpvoteClicked(id) ->
      case model.shared {
        Some(shared) -> {
          board.upvote(shared.votes, id)
          #(snapshot(model), effect.none())
        }
        None -> #(model, effect.none())
      }

    DownvoteClicked(id) ->
      case model.shared {
        Some(shared) -> {
          board.downvote(shared.votes, id)
          #(snapshot(model), effect.none())
        }
        None -> #(model, effect.none())
      }

    // docs:snippet-end guide-votes-vote-clicks
    // docs:snippet-start guide-presence-focus-clicked
    FocusClicked(id) -> {
      let focus = case model.focus {
        Some(current) if current == id -> None
        Some(_) | None -> Some(id)
      }
      let model = Model(..model, focus: focus)
      #(model, announce_focus(model))
    }

    FocusCleared -> {
      let model = Model(..model, focus: None)
      #(model, announce_focus(model))
    }

    // docs:snippet-end guide-presence-focus-clicked
    PresenceStarted(handle) -> {
      let model = Model(..model, presence: Some(handle))
      #(model, announce_focus(model))
    }

    // docs:snippet-start guide-presence-events
    PresenceEvent(event) ->
      case event {
        presence.State(entries) | presence.Changed(_, entries) -> #(
          Model(..model, peers: remote_peers(model, entries)),
          effect.none(),
        )
        presence.Failed(presence.DecodeFailed(_, _)) -> #(model, effect.none())
        presence.Failed(presence.UnsupportedPresence) -> #(
          Model(
            ..model,
            last_error: Some("presence unavailable on this server"),
          ),
          effect.none(),
        )
        presence.Failed(presence.Rejected(_, message)) -> #(
          Model(..model, last_error: Some("presence rejected: " <> message)),
          effect.none(),
        )
      }

    // docs:snippet-end guide-presence-events
    ReconnectClicked ->
      case model.document {
        Some(document) -> #(model, watershed_lustre.force_reconnect(document))
        None -> #(model, effect.none())
      }
  }
}

// docs:snippet-start retro-app-remote-peers
fn remote_peers(
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

// docs:snippet-end retro-app-remote-peers

fn snapshot(model: Model) -> Model {
  let #(title, error) = case model.document {
    Some(document) ->
      case
        watershed.get_field(
          watershed.root_typed(document),
          document_schema.title(),
        )
      {
        Ok(Some(title)) -> #(title, model.last_error)
        Ok(None) -> #(model.board.title, model.last_error)
        Error(_) -> #(
          model.board.title,
          Some("The shared title is not a string."),
        )
      }
    None -> #(model.board.title, model.last_error)
  }

  let #(board_state, error) = case model.shared {
    Some(shared) ->
      case board.snapshot_from_channels(title, shared.notes, shared.votes) {
        Ok(b) -> #(b, error)
        Error(reason) -> #(board.empty(title), Some(reason))
      }
    None -> #(board.empty(title), error)
  }

  Model(..model, board: board_state, last_error: error)
}

fn draft_for(model: Model, column: Column) -> String {
  dict.get(model.drafts, board.column_id(column)) |> result.unwrap("")
}

fn view(model: Model) -> Element(Msg) {
  html.main([attribute.class("shell")], [
    html.header([attribute.class("masthead")], [
      html.div([], [
        html.h1([], [html.text(model.board.title)]),
        html.p([attribute.class("status")], [html.text(status_text(model))]),
      ]),
      html.div([attribute.class("masthead-actions")], [
        html.button(
          [
            event.on_click(FocusCleared),
            attribute.disabled(model.focus == None),
          ],
          [
            html.text("Clear focus"),
          ],
        ),
        html.button([event.on_click(ReconnectClicked)], [
          html.text("Force reconnect"),
        ]),
      ]),
    ]),
    error_view(model.last_error),
    html.div([attribute.class("top-row")], [
      presence_view(model),
      focused_view(model),
    ]),
    html.div(
      [attribute.class("board")],
      list.map(board.all_columns(), fn(column) { column_view(model, column) }),
    ),
    unfiled_view(model),
    html.p([attribute.class("hint")], [
      html.text(
        "Open the same document in a second tab. Add notes in both tabs, vote on them, and click Focus to watch presence follow the note.",
      ),
    ]),
  ])
}

fn status_text(model: Model) -> String {
  let connection = case model.status {
    Connecting -> "connecting…"
    Ready -> "connected"
    Failed(reason) -> "failed: " <> reason
  }
  let channels = case model.shared {
    Some(_) -> "board ready"
    None -> "channels " <> int.to_string(pending_count(model.pending)) <> "/2"
  }
  connection
  <> " · "
  <> channels
  <> " · "
  <> int.to_string(board.note_count(model.board))
  <> " notes"
}

fn pending_count(pending: PendingShared) -> Int {
  [option.is_some(pending.notes), option.is_some(pending.votes)]
  |> list.count(fn(ready) { ready })
}

fn presence_view(model: Model) -> Element(Msg) {
  let self_chip =
    chip(presence.short_name(model.user_id) <> " (you)", model.color)
  let peer_chips =
    model.peers
    |> list.map(fn(peer) { chip(peer.meta.name, peer.meta.color) })

  let copy = case model.peers {
    [] -> "No other teammates connected."
    peers ->
      peers |> list.map(peer_status(model.board, _)) |> string.join(" · ")
  }

  html.section([attribute.class("presence")], [
    html.h2([], [html.text("Presence")]),
    html.p([attribute.class("peer-copy")], [html.text(copy)]),
    html.div(
      [attribute.class("roster"), attribute.aria_label("Participants online")],
      [self_chip, ..peer_chips],
    ),
  ])
}

fn peer_status(
  board_state: board.Snapshot,
  peer: presence.PresenceEntry(BoardPresence),
) -> String {
  peer.meta.name
  <> case peer.meta.focused_note {
    Some(id) -> " is focused on " <> focus_label(board_state, id)
    None -> " is connected"
  }
}

fn focused_view(model: Model) -> Element(Msg) {
  let text = case model.focus {
    Some(id) -> "You are focused on " <> focus_label(model.board, id) <> "."
    None -> "Focus a note to publish lightweight presence to other tabs."
  }
  html.section([attribute.class("focus-panel")], [
    html.h2([], [html.text("Focused note")]),
    html.p([attribute.class("focus-copy")], [html.text(text)]),
  ])
}

fn focus_label(board_state: board.Snapshot, id: String) -> String {
  case board.find_card(board_state, id) {
    Ok(card) -> preview(card.note.text)
    Error(Nil) -> "a note that has not synced yet"
  }
}

fn preview(text: String) -> String {
  let clean = string.trim(text)
  case clean {
    "" -> "(blank note)"
    _ ->
      case string.length(clean) > 36 {
        True -> string.slice(clean, 0, 36) <> "…"
        False -> clean
      }
  }
}

fn chip(name: String, color: String) -> Element(Msg) {
  html.span(
    [
      attribute.class("chip"),
      attribute.style("border-color", color),
      attribute.style("color", color),
    ],
    [
      html.span(
        [attribute.class("dot"), attribute.style("background", color)],
        [],
      ),
      html.text(name),
    ],
  )
}

fn error_view(error: Option(String)) -> Element(Msg) {
  html.p([attribute.class("error")], [html.text(option.unwrap(error, ""))])
}

fn column_view(model: Model, column: Column) -> Element(Msg) {
  let draft = draft_for(model, column)
  let cards = board.cards_for(model.board, column)
  let list_view = case cards {
    [] -> html.p([attribute.class("empty")], [html.text("No notes yet.")])
    _ ->
      html.ul(
        [attribute.class("cards")],
        list.map(cards, fn(card) { note_view(model, card) }),
      )
  }

  html.section([attribute.class("column")], [
    html.h2([], [html.text(board.column_label(column))]),
    html.p([attribute.class("column-copy")], [
      html.text(board.column_hint(column)),
    ]),
    html.div([attribute.class("compose")], [
      html.input([
        attribute.placeholder(board.column_hint(column)),
        attribute.value(draft),
        event.on_input(fn(text) { DraftChanged(column, text) }),
        attribute.aria_label("New note for " <> board.column_label(column)),
      ]),
      html.button(
        [
          event.on_click(AddClicked(column)),
          attribute.disabled(string.trim(draft) == ""),
        ],
        [html.text("Add")],
      ),
    ]),
    list_view,
  ])
}

fn note_view(model: Model, card: NoteCard) -> Element(Msg) {
  let focused = focus_names(model, card.id)
  let focus_class = case focused {
    [] -> ""
    _ -> " focused"
  }
  let focus_line = case focused {
    [] -> html.text("")
    names ->
      html.p([attribute.class("focus-line")], [
        html.text("Focused by " <> string.join(names, ", ")),
      ])
  }

  html.li([], [
    html.article([attribute.class("card" <> focus_class)], [
      html.p([attribute.class("card-text")], [html.text(card.note.text)]),
      html.div([attribute.class("card-meta")], [
        html.span([attribute.class("author")], [html.text(card.note.author)]),
        html.span([attribute.class("tally")], [
          html.text("votes " <> int.to_string(card.votes)),
        ]),
      ]),
      html.div([attribute.class("card-actions")], [
        html.button(
          [
            event.on_click(UpvoteClicked(card.id)),
            attribute.aria_label("Upvote note"),
          ],
          [html.text("+1")],
        ),
        html.button(
          [
            event.on_click(DownvoteClicked(card.id)),
            attribute.aria_label("Downvote note"),
          ],
          [html.text("-1")],
        ),
        html.button([event.on_click(FocusClicked(card.id))], [
          html.text(focus_button_label(model, card.id)),
        ]),
      ]),
      focus_line,
    ]),
  ])
}

fn focus_button_label(model: Model, id: String) -> String {
  case model.focus {
    Some(current) if current == id -> "Focused"
    Some(_) | None -> "Focus"
  }
}

// docs:snippet-start retro-app-focus-names
fn focus_names(model: Model, id: String) -> List(String) {
  let local = case model.focus {
    Some(current) if current == id -> [
      presence.short_name(model.user_id) <> " (you)",
    ]
    Some(_) | None -> []
  }
  let peers =
    model.peers
    |> list.filter_map(fn(peer) {
      case peer.meta.focused_note {
        Some(current) if current == id -> Ok(peer.meta.name)
        Some(_) | None -> Error(Nil)
      }
    })
  list.append(local, peers)
}

// docs:snippet-end retro-app-focus-names

fn unfiled_view(model: Model) -> Element(Msg) {
  case model.board.unfiled {
    [] -> html.text("")
    notes ->
      html.section([attribute.class("unfiled")], [
        html.h2([], [html.text("Unfiled notes")]),
        html.p([attribute.class("column-copy")], [
          html.text(
            "Notes stay visible here if their column id is unknown or unreadable.",
          ),
        ]),
        html.ul(
          [attribute.class("cards")],
          list.map(notes, fn(card) { note_view(model, card) }),
        ),
      ])
  }
}
