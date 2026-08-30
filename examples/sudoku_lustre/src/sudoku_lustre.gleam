//// Gleam-end-to-end collaborative Sudoku.
////
//// A Lustre single-page app whose nested watershed structures are bootstrapped
//// from handles stored on a typed map. Open two tabs against the same
//// `just server` document and watch cells, notes, givens, and mistakes converge.
////
//// The board itself is `sudoku_lustre/component`, a nested MVU triple that
//// takes a `TypedMap(SudokuDoc)` — this document's root standalone, a child of
//// the showcase root when mounted there. What is left here is the connection,
//// the sync status, and the presence driver, all three document-scoped.
////
//// Presence is split across that seam. The driver and the identity half of the
//// payload — name and colour — belong to this module, because they describe a
//// *client*, not a board. The component contributes the other half, a
//// `component.Cursor` of "which cell, and typing or not", and receives peers
//// back with both halves joined. Composed, the showcase supplies the same
//// identity to four panels from one driver, which is the thing four separate
//// apps cannot do.

import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}

import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import sudoku_lustre/component
import sudoku_lustre/doc_schema
import watershed.{type Document}
import watershed_lustre

import watershed/browser
import watershed/presence
import watershed/presence_js.{type Handle}

// ── Dev config for `just server` (levee dev mode) ────────────────────────────

const socket_url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let document = browser.document_on_navigate("sudoku")
  let assert Ok(_) = lustre.start(app, "#app", document)
  Nil
}

// ── Presence payload ───────────────────────────────────────────────────────
//
// Identity is this module's; the cell and the typing flag are the board's. The
// wire payload is both halves in one object, which is what lets a peer be drawn
// with a name and a colour on a cell.

/// This app's per-peer presence payload — everything but the user id, which the
/// library's envelope carries. Liveness/roster/TTL are the driver's job.
pub type SudokuPresence {
  SudokuPresence(color: String, name: String, cursor: component.Cursor)
}

fn encode_presence(p: SudokuPresence) -> Json {
  json.object([
    #("color", json.string(p.color)),
    #("name", json.string(p.name)),
    #("cursor", component.encode_cursor(p.cursor)),
  ])
}

fn presence_decoder() -> Decoder(SudokuPresence) {
  use color <- decode.field("color", decode.string)
  use name <- decode.field("name", decode.string)
  use cursor <- decode.field("cursor", component.cursor_decoder())
  decode.success(SudokuPresence(color:, name:, cursor:))
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
    doc: Option(Document(doc_schema.SudokuDoc)),
    /// The board panel. `None` until the handshake completes.
    board: Option(component.Model),
    user_id: String,
    color: String,
    /// The live presence session, once started, and its current roster. The
    /// driver owns heartbeat + TTL expiry; we just re-render on `on_change`.
    presence: Option(Handle(SudokuPresence)),
    peers: List(presence.PresenceEntry(SudokuPresence)),
    /// The last cursor announced, so a re-announce only fires on a real move.
    announced: Option(component.Cursor),
    error: Option(String),
  )
}

type Msg {
  GotHandle(Document(doc_schema.SudokuDoc))
  Connected(Result(Nil, String))
  Board(component.Msg)
  ReconnectClicked
  PresenceStarted(Handle(SudokuPresence))
  PresenceEvent(presence.Event(SudokuPresence))
}

fn init(document: String) -> #(Model, Effect(Msg)) {
  // A distinct user per tab so the two clients are separate connections.
  let user_id = "web-" <> int.to_string(1000 + int.random(9000))
  let model =
    Model(
      status: Connecting,
      doc: None,
      board: None,
      user_id: user_id,
      color: presence.color_for(user_id),
      presence: None,
      peers: [],
      announced: None,
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
      got_document: GotHandle,
      connected: Connected,
    ),
  )
}

// ── Update ───────────────────────────────────────────────────────────────────

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    // The handle arrives before the handshake completes; start presence now (it
    // only needs the doc) and mount the board once Connected has made us Ready.
    GotHandle(doc) -> {
      let model = Model(..model, doc: Some(doc))
      let presence = presence_effect(model, doc)
      case model.status, model.board {
        Ready, None -> {
          let #(model, mount) = mount_board(model, doc)
          #(model, effect.batch([mount, presence]))
        }
        _, _ -> #(model, presence)
      }
    }

    Connected(Ok(_)) -> {
      let model = Model(..model, status: Ready)
      case model.doc, model.board {
        Some(doc), None -> mount_board(model, doc)
        _, _ -> #(model, effect.none())
      }
    }

    Connected(Error(reason)) -> #(
      Model(..model, status: Failed(reason), error: Some(reason)),
      effect.none(),
    )

    // Any board message may have moved the selection or started a keystroke
    // timer, so this is where the cursor gets broadcast.
    Board(inner) ->
      case model.board {
        None -> #(model, effect.none())
        Some(board) -> {
          let #(board, board_effect) = component.update(board, inner)
          let #(model, announce) =
            announce_cursor(Model(..model, board: Some(board)))
          #(model, effect.batch([effect.map(board_effect, Board), announce]))
        }
      }

    ReconnectClicked ->
      case model.doc {
        Some(doc) -> #(model, watershed_lustre.force_reconnect(doc))
        None -> #(model, effect.none())
      }

    PresenceStarted(handle) ->
      announce_cursor(Model(..model, presence: Some(handle)))

    PresenceEvent(event) ->
      case event {
        presence.State(entries) | presence.Changed(_, entries) -> {
          let peers = remote_peers(model, entries)
          let model = Model(..model, peers: peers)
          #(push_peers(model), effect.none())
        }
        // A peer whose metadata we cannot read is dropped by the driver; a
        // rejected join is worth showing, since presence silently not working
        // is the failure mode this whole model exists to avoid.
        presence.Failed(presence.DecodeFailed(_, _)) -> #(model, effect.none())
        presence.Failed(presence.UnsupportedPresence) -> #(
          Model(..model, error: Some("presence unavailable on this server")),
          effect.none(),
        )
        presence.Failed(presence.Rejected(_, message)) -> #(
          Model(..model, error: Some("presence rejected: " <> message)),
          effect.none(),
        )
      }
  }
}

/// Mount the board against this document's root.
///
/// `root_typed` is the line that makes this the standalone app rather than a
/// panel: it is the only place the document's root is named.
fn mount_board(
  model: Model,
  doc: Document(doc_schema.SudokuDoc),
) -> #(Model, Effect(Msg)) {
  let #(board, board_effect) = component.init(doc, watershed.root_typed(doc))
  #(
    push_peers(Model(..model, board: Some(board))),
    effect.map(board_effect, Board),
  )
}

/// Hand the board the current roster, with each peer's two halves joined.
fn push_peers(model: Model) -> Model {
  case model.board {
    None -> model
    Some(board) ->
      Model(
        ..model,
        board: Some(component.set_peers(
          board,
          list.map(model.peers, fn(peer) {
            component.Peer(
              name: peer.meta.name,
              color: peer.meta.color,
              cell: peer.meta.cursor.cell,
              editing: peer.meta.cursor.editing,
            )
          }),
        )),
      )
  }
}

/// Ephemeral presence rides on the library driver, independent of the DDS
/// streams: it negotiates server or ripple mode, joins, and rejoins after a
/// reconnect; we only re-render on the roster it reports.
fn presence_effect(
  model: Model,
  doc: Document(doc_schema.SudokuDoc),
) -> Effect(Msg) {
  watershed_lustre.presence(
    document: doc,
    config: presence.config(encode_presence, presence_decoder()),
    initial: current_presence(model),
    started: PresenceStarted,
    on_event: PresenceEvent,
  )
}

/// Broadcast this client's cursor, but only when it has actually moved. A
/// no-operation until presence has started — `start` already carried the
/// initial value.
fn announce_cursor(model: Model) -> #(Model, Effect(Msg)) {
  let current = case model.board {
    Some(board) -> Some(component.cursor(board))
    None -> None
  }
  case model.presence, current == model.announced {
    _, True -> #(model, effect.none())
    None, _ -> #(Model(..model, announced: current), effect.none())
    Some(handle), False -> #(
      Model(..model, announced: current),
      watershed_lustre.update_presence(handle, current_presence(model)),
    )
  }
}

/// Everyone but this tab. Presence state includes the local session by design,
/// so the roster is filtered here rather than in the driver.
fn remote_peers(
  model: Model,
  entries: List(presence.PresenceEntry(SudokuPresence)),
) -> List(presence.PresenceEntry(SudokuPresence)) {
  case model.presence {
    Some(handle) ->
      case presence_js.local_session(handle) {
        Some(session) -> presence.remote_entries(entries, session)
        None -> entries
      }
    None -> entries
  }
}

fn current_presence(model: Model) -> SudokuPresence {
  SudokuPresence(
    color: model.color,
    name: presence.short_name(model.user_id),
    cursor: case model.board {
      Some(board) -> component.cursor(board)
      None -> component.Cursor(cell: None, editing: False)
    },
  )
}

// ── View ─────────────────────────────────────────────────────────────────────

fn view(model: Model) -> Element(Msg) {
  html.main([attribute.class("wrap")], [
    html.h1([], [html.text("watershed · collaborative Sudoku")]),
    status_line(model),
    roster_view(model),
    panel_view(model),
    html.div([attribute.class("toolbar")], [
      html.button([event.on_click(ReconnectClicked)], [
        html.text("Force reconnect"),
      ]),
    ]),
    error_view(model.error),
    html.p([attribute.class("hint")], [
      html.text(
        "Open a second tab on the same document to solve together. Client: "
        <> model.user_id,
      ),
    ]),
  ])
}

/// The live-presence roster: self plus every peer seen within the TTL. Derived
/// entirely from the ephemeral driver, so it self-heals when a tab goes away.
fn roster_view(model: Model) -> Element(Msg) {
  let editing = case model.board {
    Some(board) -> component.cursor(board).editing
    None -> False
  }
  let self_chip =
    chip(presence.short_name(model.user_id) <> " (you)", model.color, editing)
  let peer_chips =
    model.peers
    |> list.map(fn(peer) {
      chip(peer.meta.name, peer.meta.color, peer.meta.cursor.editing)
    })
  html.div([attribute.class("roster"), attribute.aria_label("Players online")], [
    self_chip,
    ..peer_chips
  ])
}

fn chip(name: String, color: String, editing: Bool) -> Element(Msg) {
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
      case editing {
        True -> html.span([attribute.class("typing")], [html.text(" ✎")])
        False -> html.text("")
      },
    ],
  )
}

fn status_line(model: Model) -> Element(Msg) {
  let puzzle = case model.board {
    Some(board) -> component.puzzle_name(board)
    None -> "…"
  }
  let text = case model.status {
    Connecting -> "connecting…"
    Ready ->
      case model.doc {
        Some(doc) ->
          case watershed.is_synced(doc) {
            True -> "connected · synced · " <> puzzle
            False -> "connected · syncing… · " <> puzzle
          }
        None -> "connected · bootstrapping…"
      }
    Failed(reason) -> "failed: " <> reason
  }
  html.p([attribute.class("status")], [html.text(text)])
}

fn panel_view(model: Model) -> Element(Msg) {
  case model.board {
    Some(board) -> component.view(board) |> element.map(Board)
    None -> html.p([attribute.class("status")], [html.text("bootstrapping…")])
  }
}

fn error_view(error: Option(String)) -> Element(Msg) {
  case error {
    Some(reason) ->
      html.p([attribute.class("status")], [html.text("Error: " <> reason)])
    None -> html.text("")
  }
}
