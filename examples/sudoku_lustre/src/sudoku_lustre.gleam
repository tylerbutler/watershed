//// Gleam-end-to-end collaborative Sudoku.
////
//// A Lustre single-page app whose nested watershed structures are bootstrapped
//// from handles stored on the root map. Open two tabs against the same
//// `just server` document and watch cells, notes, givens, and mistakes converge.
////
//// Ephemeral presence (cursors, typing) rides on the library's presence driver
//// (`watershed/presence_js`), which owns the heartbeat/TTL lifecycle; this app
//// keeps only its payload type (`SudokuPresence`) and the rendering.

import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}

import lustre
import lustre/attribute.{
  aria_label, aria_pressed, aria_selected, class, classes, role, tabindex,
}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import doc_schema
import puzzles.{type Puzzle}
import watershed_js.{
  type Claims, type Document, type OrSet, type SharedCounter, type SharedMap,
}
import watershed_lustre

import watershed/presence.{type Peer}
import watershed/presence_js.{type Handle}

// ── Dev config for `just server` (levee dev mode) ────────────────────────────

const socket_url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

const document_id = "sudoku"

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

// ── Presence payload ───────────────────────────────────────────────────────

/// This app's per-peer presence payload — everything but the user id, which the
/// library's envelope carries. Liveness/roster/TTL are the driver's job.
pub type SudokuPresence {
  SudokuPresence(
    color: String,
    name: String,
    /// The `r{r}c{c}` key of the peer's selected cell, if any.
    cell: Option(String),
    /// Whether the peer is actively typing into their selected cell.
    editing: Bool,
  )
}

fn encode_presence(p: SudokuPresence) -> Json {
  json.object([
    #("color", json.string(p.color)),
    #("name", json.string(p.name)),
    #("cell", case p.cell {
      Some(key) -> json.string(key)
      None -> json.null()
    }),
    #("editing", json.bool(p.editing)),
  ])
}

fn presence_decoder() -> Decoder(SudokuPresence) {
  use color <- decode.field("color", decode.string)
  use name <- decode.field("name", decode.string)
  use cell <- decode.optional_field(
    "cell",
    None,
    decode.optional(decode.string),
  )
  use editing <- decode.optional_field("editing", False, decode.bool)
  decode.success(SudokuPresence(color:, name:, cell:, editing:))
}

// ── Model ────────────────────────────────────────────────────────────────────

type Status {
  Connecting
  Ready
  Failed(reason: String)
}

type SharedState {
  SharedState(
    cells: SharedMap,
    notes: OrSet,
    givens: Claims,
    mistakes: SharedCounter,
  )
}

/// The nested channels as they resolve during bootstrap. Each `ensure_*` effect
/// fills one slot; when all four are present they assemble into `SharedState`.
type PendingShared {
  PendingShared(
    cells: Option(SharedMap),
    notes: Option(OrSet),
    givens: Option(Claims),
    mistakes: Option(SharedCounter),
  )
}

type Model {
  Model(
    status: Status,
    doc: Option(Document),
    shared: Option(SharedState),
    pending: PendingShared,
    user_id: String,
    color: String,
    puzzle: Puzzle,
    selected: Option(#(Int, Int)),
    notes_mode: Bool,
    cells: List(#(String, Int)),
    notes: List(String),
    givens: List(#(String, Int)),
    mistakes: Int,
    /// The live presence session, once started, and its current roster. The
    /// driver owns heartbeat + TTL expiry; we just re-render on `on_change`.
    presence: Option(Handle(SudokuPresence)),
    peers: List(Peer(SudokuPresence)),
    editing: Bool,
    error: Option(String),
  )
}

type Msg {
  GotHandle(Document)
  Connected(Result(Nil, String))
  EnsuredCells(Result(SharedMap, String))
  EnsuredNotes(Result(OrSet, String))
  EnsuredGivens(Result(Claims, String))
  EnsuredMistakes(Result(SharedCounter, String))
  SharedChanged
  CellSelected(Int, Int)
  KeyPressed(String)
  NotesModeClicked
  ReconnectClicked
  PresenceStarted(Handle(SudokuPresence))
  PresenceChanged(List(Peer(SudokuPresence)))
  EditingStopped
}

fn init(_args) -> #(Model, Effect(Msg)) {
  // A distinct user per tab so the two clients are separate connections.
  let user_id = "web-" <> int.to_string(1000 + int.random(9000))
  let model =
    Model(
      status: Connecting,
      doc: None,
      shared: None,
      pending: PendingShared(None, None, None, None),
      user_id: user_id,
      color: presence.color_for(user_id),
      puzzle: puzzles.default_puzzle(),
      selected: None,
      notes_mode: False,
      cells: [],
      notes: [],
      givens: [],
      mistakes: 0,
      presence: None,
      peers: [],
      editing: False,
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
      got_document: GotHandle,
      connected: Connected,
    ),
  )
}

/// Ephemeral presence rides on the library driver, independent of the DDS
/// streams: it owns the heartbeat/TTL loop; we only re-render on the roster.
fn presence_effect(model: Model, doc: Document) -> Effect(Msg) {
  watershed_lustre.presence(
    document: doc,
    user_id: model.user_id,
    config: presence.default_config,
    encode: encode_presence,
    decode: presence_decoder(),
    started: PresenceStarted,
    on_peers: PresenceChanged,
  )
}

/// Announce this client's current presence through the driver (broadcasts now
/// and keeps the heartbeat alive). A no-op until presence has started.
fn announce_effect(model: Model) -> Effect(Msg) {
  case model.presence {
    Some(handle) -> watershed_lustre.announce(handle, current_presence(model))
    None -> effect.none()
  }
}

fn current_presence(model: Model) -> SudokuPresence {
  SudokuPresence(
    color: model.color,
    name: presence.short_name(model.user_id),
    cell: option.map(model.selected, fn(rc) { cell_key(rc.0, rc.1) }),
    editing: model.editing,
  )
}

/// Bootstrap the document declaratively: seed the plain fields, adopt-or-seed
/// each nested channel, and watch the root — all as one batch of effects. Each
/// `ensure_*` dispatches its channel back as an `Ensured*` message; they
/// assemble into `SharedState` once all four have arrived (`assemble`). Plain
/// fields seed set-if-absent, LWW settling concurrent joins.
fn bootstrap_effect(doc: Document) -> Effect(Msg) {
  let root = watershed_js.root_typed(doc)
  effect.batch([
    watershed_lustre.ensure_field(
      root,
      doc_schema.title(),
      "Collaborative Sudoku",
    ),
    watershed_lustre.ensure_field(
      root,
      doc_schema.puzzle(),
      puzzles.default_puzzle().id,
    ),
    watershed_lustre.ensure_map(doc, root, doc_schema.cells(), EnsuredCells),
    watershed_lustre.ensure_or_set(doc, root, doc_schema.notes(), EnsuredNotes),
    watershed_lustre.ensure_claims(
      doc,
      root,
      doc_schema.givens(),
      EnsuredGivens,
    ),
    watershed_lustre.ensure_counter(
      doc,
      root,
      doc_schema.mistakes(),
      EnsuredMistakes,
    ),
    watershed_lustre.subscribe(watershed_js.root(doc), fn(_event) {
      SharedChanged
    }),
  ])
}

/// Assemble `SharedState` once all four nested channels have resolved: seed the
/// givens on the claims channel (first-writer-wins, so every client can run it
/// and later writers no-op) and start the per-channel subscriptions. A no-op
/// until the last channel arrives or once already assembled.
fn assemble(model: Model) -> #(Model, Effect(Msg)) {
  case model.shared, model.pending {
    None, PendingShared(Some(cells), Some(notes), Some(givens), Some(mistakes))
    -> {
      let shared = SharedState(cells:, notes:, givens:, mistakes:)
      seed_givens(givens, puzzles.default_puzzle(), 0, 0)
      #(
        snapshot(Model(..model, shared: Some(shared), error: None)),
        subscribe_shared_effect(shared),
      )
    }
    _, _ -> #(model, effect.none())
  }
}

/// The narrowed per-kind subscriptions as one batch. Each handler sees only its
/// channel's own event type; the whole-model `snapshot` stays the cheapest
/// re-read for an 81-cell grid, so every handler just bumps it.
fn subscribe_shared_effect(shared: SharedState) -> Effect(Msg) {
  effect.batch([
    watershed_lustre.subscribe(shared.cells, fn(_event) { SharedChanged }),
    watershed_lustre.subscribe_or_set(shared.notes, fn(_event) { SharedChanged }),
    watershed_lustre.subscribe_claims(shared.givens, fn(_event) {
      SharedChanged
    }),
    watershed_lustre.subscribe_counter(shared.mistakes, fn(_event) {
      SharedChanged
    }),
  ])
}

// ── Update ───────────────────────────────────────────────────────────────────

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    GotHandle(doc) -> {
      let model = Model(..model, doc: Some(doc))
      // The handle arrives before the handshake completes; start presence now
      // (it only needs the doc) and bootstrap once Connected has made us Ready.
      let presence = presence_effect(model, doc)
      case model.status, model.shared {
        Ready, None -> #(model, effect.batch([bootstrap_effect(doc), presence]))
        _, _ -> #(model, presence)
      }
    }

    Connected(Ok(_)) -> {
      let model = Model(..model, status: Ready)
      case model.doc, model.shared {
        Some(doc), None -> #(model, bootstrap_effect(doc))
        _, _ -> #(snapshot(model), effect.none())
      }
    }

    Connected(Error(reason)) -> #(
      Model(..model, status: Failed(reason), error: Some(reason)),
      effect.none(),
    )

    EnsuredCells(Ok(cells)) ->
      assemble(
        Model(
          ..model,
          pending: PendingShared(..model.pending, cells: Some(cells)),
        ),
      )
    EnsuredCells(Error(reason)) -> #(
      Model(..model, error: Some(reason)),
      effect.none(),
    )

    EnsuredNotes(Ok(notes)) ->
      assemble(
        Model(
          ..model,
          pending: PendingShared(..model.pending, notes: Some(notes)),
        ),
      )
    EnsuredNotes(Error(reason)) -> #(
      Model(..model, error: Some(reason)),
      effect.none(),
    )

    EnsuredGivens(Ok(givens)) ->
      assemble(
        Model(
          ..model,
          pending: PendingShared(..model.pending, givens: Some(givens)),
        ),
      )
    EnsuredGivens(Error(reason)) -> #(
      Model(..model, error: Some(reason)),
      effect.none(),
    )

    EnsuredMistakes(Ok(mistakes)) ->
      assemble(
        Model(
          ..model,
          pending: PendingShared(..model.pending, mistakes: Some(mistakes)),
        ),
      )
    EnsuredMistakes(Error(reason)) -> #(
      Model(..model, error: Some(reason)),
      effect.none(),
    )

    SharedChanged -> #(snapshot(model), effect.none())

    CellSelected(row, col) -> {
      let model = Model(..model, selected: Some(#(row, col)))
      #(model, announce_effect(model))
    }

    KeyPressed(key) -> {
      let model = handle_key(model, key)
      case model.selected {
        Some(_) -> {
          let model = Model(..model, editing: True)
          #(
            model,
            effect.batch([
              announce_effect(model),
              watershed_lustre.after(1200, EditingStopped),
            ]),
          )
        }
        None -> #(model, effect.none())
      }
    }

    NotesModeClicked -> #(
      Model(..model, notes_mode: !model.notes_mode),
      effect.none(),
    )

    ReconnectClicked ->
      case model.doc {
        Some(doc) -> #(model, watershed_lustre.force_reconnect(doc))
        None -> #(model, effect.none())
      }

    PresenceStarted(handle) -> {
      let model = Model(..model, presence: Some(handle))
      // Announce once so we appear to peers and the heartbeat begins.
      #(model, announce_effect(model))
    }

    PresenceChanged(peers) -> #(Model(..model, peers: peers), effect.none())

    EditingStopped -> {
      let model = Model(..model, editing: False)
      #(model, announce_effect(model))
    }
  }
}

fn handle_key(model: Model, key: String) -> Model {
  case model.selected, model.shared {
    Some(#(row, col)), Some(shared) ->
      case digit_from_key(key) {
        Some(digit) -> {
          case is_locked(model, row, col) {
            True -> model
            False -> {
              case model.notes_mode {
                True -> toggle_note(shared.notes, row, col, digit)
                False -> set_cell(shared, model.puzzle, row, col, digit)
              }
              model
            }
          }
        }
        None -> {
          case key == "Backspace" || key == "Delete" {
            True -> {
              case is_locked(model, row, col) {
                True -> Nil
                False -> watershed_js.delete(shared.cells, cell_key(row, col))
              }
              model
            }
            False -> model
          }
        }
      }
    _, _ -> model
  }
}

fn toggle_note(notes: OrSet, row: Int, col: Int, digit: Int) -> Nil {
  let key = note_key(row, col, digit)
  case watershed_js.or_set_contains(notes, key) {
    True -> watershed_js.or_set_remove(notes, key)
    False -> watershed_js.or_set_add(notes, key)
  }
}

fn set_cell(
  shared: SharedState,
  puzzle: Puzzle,
  row: Int,
  col: Int,
  digit: Int,
) -> Nil {
  watershed_js.set(shared.cells, cell_key(row, col), json.int(digit))
  case digit == puzzles.solution_at(puzzle, row, col) {
    True -> Nil
    False -> watershed_js.increment(shared.mistakes, 1)
  }
}

/// Re-read optimistic shared state into the model for rendering.
fn snapshot(model: Model) -> Model {
  case model.doc, model.shared {
    Some(doc), Some(shared) -> {
      Model(
        ..model,
        puzzle: puzzle_from_root(doc),
        cells: read_cells(shared.cells),
        notes: watershed_js.or_set_values(shared.notes),
        givens: read_givens(shared.givens),
        mistakes: watershed_js.counter_value(shared.mistakes)
          |> option.unwrap(0),
      )
    }
    _, _ -> model
  }
}

// ── Content seeding ──────────────────────────────────────────────────────────

fn seed_givens(claims: Claims, puzzle: Puzzle, row: Int, col: Int) -> Nil {
  case row >= 9 {
    True -> Nil
    False -> {
      let given = puzzles.given_at(puzzle, row, col)
      case given > 0 {
        True -> {
          let _ =
            watershed_js.try_set_claim(
              claims,
              cell_key(row, col),
              json.int(given),
            )
          Nil
        }
        False -> Nil
      }
      case col == 8 {
        True -> seed_givens(claims, puzzle, row + 1, 0)
        False -> seed_givens(claims, puzzle, row, col + 1)
      }
    }
  }
}

// ── View ─────────────────────────────────────────────────────────────────────

fn view(model: Model) -> Element(Msg) {
  html.main([class("wrap")], [
    html.h1([], [html.text("watershed · collaborative Sudoku")]),
    status_line(model),
    roster_view(model),
    toolbar(model),
    grid(model),
    error_view(model.error),
    html.p([class("hint")], [
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
  let self_chip =
    chip(
      presence.short_name(model.user_id) <> " (you)",
      model.color,
      model.editing,
    )
  let peer_chips =
    model.peers
    |> list.map(fn(peer) {
      chip(peer.payload.name, peer.payload.color, peer.payload.editing)
    })
  html.div([class("roster"), aria_label("Players online")], [
    self_chip,
    ..peer_chips
  ])
}

fn chip(name: String, color: String, editing: Bool) -> Element(Msg) {
  html.span(
    [
      class("chip"),
      attribute.style("border-color", color),
      attribute.style("color", color),
    ],
    [
      html.span([class("dot"), attribute.style("background", color)], []),
      html.text(name),
      case editing {
        True -> html.span([class("typing")], [html.text(" ✎")])
        False -> html.text("")
      },
    ],
  )
}

fn status_line(model: Model) -> Element(Msg) {
  let text = case model.status {
    Connecting -> "connecting…"
    Ready ->
      case model.doc {
        Some(doc) ->
          case watershed_js.is_synced(doc) {
            True -> "connected · synced · " <> model.puzzle.name
            False -> "connected · syncing… · " <> model.puzzle.name
          }
        None -> "connected · bootstrapping…"
      }
    Failed(reason) -> "failed: " <> reason
  }
  html.p([class("status")], [html.text(text)])
}

fn toolbar(model: Model) -> Element(Msg) {
  html.div([class("toolbar")], [
    html.span([class("mistakes")], [
      html.text("Mistakes: " <> int.to_string(model.mistakes)),
    ]),
    html.button(
      [
        event.on_click(NotesModeClicked),
        aria_pressed(bool_string(model.notes_mode)),
      ],
      [
        html.text(case model.notes_mode {
          True -> "Notes mode: on"
          False -> "Notes mode: off"
        }),
      ],
    ),
    html.button([event.on_click(ReconnectClicked)], [
      html.text("Force reconnect"),
    ]),
  ])
}

fn grid(model: Model) -> Element(Msg) {
  html.div(
    [
      class("grid"),
      role("grid"),
      tabindex(0),
      aria_label("Collaborative Sudoku grid"),
      event.on_keydown(KeyPressed),
    ],
    rows_and_cols()
      |> list.map(fn(cell) { cell_view(model, cell.0, cell.1) }),
  )
}

fn cell_view(model: Model, row: Int, col: Int) -> Element(Msg) {
  let key = cell_key(row, col)
  let given = given_value(model, row, col)
  let player = cell_value(model, key)
  let selected = model.selected == Some(#(row, col))
  let locked = given != 0
  let peers_here =
    list.filter(model.peers, fn(peer) { peer.payload.cell == Some(key) })
  let value = case given, player {
    0, Some(digit) -> int.to_string(digit)
    0, None -> ""
    _, _ -> int.to_string(given)
  }

  let peer_attrs = case peers_here {
    [peer, ..] -> [
      attribute.style("box-shadow", "inset 0 0 0 3px " <> peer.payload.color),
    ]
    [] -> []
  }

  html.button(
    list.append(
      [
        classes([
          #("cell", True),
          #("given", locked),
          #("selected", selected),
          #("peer", peers_here != []),
        ]),
        role("gridcell"),
        aria_selected(selected),
        aria_label(cell_label(row, col, value, locked)),
        event.on_click(CellSelected(row, col)),
      ],
      peer_attrs,
    ),
    [
      case value == "" {
        True -> notes_view(model, row, col)
        False -> html.span([class("digit")], [html.text(value)])
      },
      peer_cursor(peers_here),
    ],
  )
}

/// A small colored badge showing which peers have this cell selected, with a
/// pencil glyph while they're typing.
fn peer_cursor(peers: List(Peer(SudokuPresence))) -> Element(Msg) {
  case peers {
    [] -> html.text("")
    [peer, ..] ->
      html.span(
        [class("cursor"), attribute.style("background", peer.payload.color)],
        [
          html.text(peer.payload.name),
          case peer.payload.editing {
            True -> html.text(" ✎")
            False -> html.text("")
          },
        ],
      )
  }
}

fn notes_view(model: Model, row: Int, col: Int) -> Element(Msg) {
  html.div(
    [class("notes")],
    digits()
      |> list.map(fn(digit) {
        let text = case list.contains(model.notes, note_key(row, col, digit)) {
          True -> int.to_string(digit)
          False -> ""
        }
        html.span([class("note")], [html.text(text)])
      }),
  )
}

fn error_view(error: Option(String)) -> Element(Msg) {
  case error {
    Some(reason) -> html.p([class("status")], [html.text("Error: " <> reason)])
    None -> html.text("")
  }
}

// ── Read helpers ─────────────────────────────────────────────────────────────

fn puzzle_from_root(doc: Document) -> Puzzle {
  case
    watershed_js.get_field(watershed_js.root_typed(doc), doc_schema.puzzle())
  {
    Ok(Some(id)) -> puzzles.by_id(id) |> option.unwrap(puzzles.default_puzzle())
    _ -> puzzles.default_puzzle()
  }
}

fn read_cells(cells: SharedMap) -> List(#(String, Int)) {
  cells
  |> watershed_js.entries
  |> list.filter_map(fn(pair) {
    case json.parse(json.to_string(pair.1), decode.int) {
      Ok(digit) -> Ok(#(pair.0, digit))
      Error(_) -> Error(Nil)
    }
  })
}

fn read_givens(givens: Claims) -> List(#(String, Int)) {
  rows_and_cols()
  |> list.filter_map(fn(cell) {
    let key = cell_key(cell.0, cell.1)
    case watershed_js.get_claim(givens, key) {
      Some(value) ->
        case json.parse(json.to_string(value), decode.int) {
          Ok(digit) -> Ok(#(key, digit))
          Error(_) -> Error(Nil)
        }
      None -> Error(Nil)
    }
  })
}

fn given_value(model: Model, row: Int, col: Int) -> Int {
  value_from_pairs(model.givens, cell_key(row, col))
  |> option.unwrap(puzzles.given_at(model.puzzle, row, col))
}

fn cell_value(model: Model, key: String) -> Option(Int) {
  value_from_pairs(model.cells, key)
}

fn value_from_pairs(pairs: List(#(String, Int)), key: String) -> Option(Int) {
  case pairs {
    [] -> None
    [first, ..rest] ->
      case first.0 == key {
        True -> Some(first.1)
        False -> value_from_pairs(rest, key)
      }
  }
}

fn is_locked(model: Model, row: Int, col: Int) -> Bool {
  given_value(model, row, col) != 0
}

// ── Formatting helpers ──────────────────────────────────────────────────────

fn cell_key(row: Int, col: Int) -> String {
  "r" <> int.to_string(row) <> "c" <> int.to_string(col)
}

fn note_key(row: Int, col: Int, digit: Int) -> String {
  cell_key(row, col) <> "=" <> int.to_string(digit)
}

fn digit_from_key(key: String) -> Option(Int) {
  case int.parse(key) {
    Ok(digit) ->
      case digit >= 1 && digit <= 9 {
        True -> Some(digit)
        False -> None
      }
    Error(_) -> None
  }
}

fn cell_label(row: Int, col: Int, value: String, locked: Bool) -> String {
  let prefix =
    "Row " <> int.to_string(row + 1) <> ", column " <> int.to_string(col + 1)
  let value = case value == "" {
    True -> ", empty"
    False -> ", " <> value
  }
  let locked = case locked {
    True -> ", given"
    False -> ""
  }
  prefix <> value <> locked
}

fn rows_and_cols() -> List(#(Int, Int)) {
  let rows = range(0, 9)
  let cols = range(0, 9)
  rows
  |> list.flat_map(fn(row) { cols |> list.map(fn(col) { #(row, col) }) })
}

fn digits() -> List(Int) {
  range(1, 10)
}

fn range(from: Int, to: Int) -> List(Int) {
  int.range(from: from, to: to, with: [], run: fn(acc, i) { [i, ..acc] })
  |> list.reverse
}

fn bool_string(value: Bool) -> String {
  case value {
    True -> "true"
    False -> "false"
  }
}
