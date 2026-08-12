//// The collaborative Sudoku board as a nested MVU triple.
////
//// The heaviest of the showcase panels, and the one that proves depth: four
//// nested channels of four different kinds — a `SharedMap` of filled cells, an
//// `OrSet` of pencil notes, a `Claims` channel of givens, and a `SharedCounter`
//// of mistakes — all hanging off one typed map. Composed, that map is itself a
//// child of the showcase root, so every one of those channels is a
//// *grandchild*, which is the depth claim this panel exists to make.
////
//// Two root-bound lines had to go for that to work. Bootstrap named
//// `root_typed(doc)`, and so did the puzzle read on every snapshot; both now
//// address the map they were handed. The `Document` parameter survives only
//// because `ensure_*` needs it to attach a channel.
////
//// Presence is split at the seam between "who you are" and "what you are
//// doing here". This component broadcasts a [`Cursor`](#Cursor) — the selected
//// cell and whether the user is typing — and receives [`Peer`](#Peer)s that
//// carry a name and colour alongside those two fields. It never starts a
//// driver: a driver is document-scoped, so two panels each starting one would
//// receive each other's envelopes. The owner of the document starts one driver
//// and hands each panel its share.

import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}

import lustre/attribute.{
  aria_label, aria_pressed, aria_selected, class, classes, role, tabindex,
}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import watershed_js.{
  type Claims, type Document, type OrSet, type SharedCounter, type SharedMap,
  type TypedMap,
}
import watershed_lustre

import sudoku_lustre/doc_schema
import sudoku_lustre/puzzles.{type Puzzle}

// ── Presence seam ────────────────────────────────────────────────────────────

/// What this panel contributes to a presence payload: where the user is and
/// whether they are typing. Identity — name, colour — belongs to whoever owns
/// the document, which is why it is not in here.
pub type Cursor {
  Cursor(
    /// The `r{r}c{c}` key of the selected cell, if any.
    cell: Option(String),
    /// Whether the user is actively typing into their selected cell.
    editing: Bool,
  )
}

/// A peer to draw on the board: this panel's two fields, plus the identity the
/// owner resolved.
pub type Peer {
  Peer(name: String, color: String, cell: Option(String), editing: Bool)
}

pub fn encode_cursor(cursor: Cursor) -> Json {
  json.object([
    #("cell", case cursor.cell {
      Some(key) -> json.string(key)
      None -> json.null()
    }),
    #("editing", json.bool(cursor.editing)),
  ])
}

pub fn cursor_decoder() -> Decoder(Cursor) {
  use cell <- decode.optional_field(
    "cell",
    None,
    decode.optional(decode.string),
  )
  use editing <- decode.optional_field("editing", False, decode.bool)
  decode.success(Cursor(cell:, editing:))
}

// ── Model ────────────────────────────────────────────────────────────────────

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

pub opaque type Model {
  Model(
    map: TypedMap(doc_schema.SudokuDoc),
    shared: Option(SharedState),
    pending: PendingShared,
    puzzle: Puzzle,
    selected: Option(#(Int, Int)),
    notes_mode: Bool,
    cells: List(#(String, Int)),
    notes: List(String),
    givens: List(#(String, Int)),
    mistakes: Int,
    peers: List(Peer),
    editing: Bool,
    error: Option(String),
  )
}

pub opaque type Msg {
  EnsuredCells(Result(SharedMap, String))
  EnsuredNotes(Result(OrSet, String))
  EnsuredGivens(Result(Claims, String))
  EnsuredMistakes(Result(SharedCounter, String))
  SharedChanged
  CellSelected(Int, Int)
  KeyPressed(String)
  NotesModeClicked
  EditingStopped
}

/// Bootstrap the board declaratively: seed the plain fields, adopt-or-seed each
/// nested channel, and watch the map — all as one batch of effects. Each
/// `ensure_*` dispatches its channel back; they assemble into `SharedState`
/// once all four have arrived. Plain fields seed set-if-absent, LWW settling
/// concurrent joins.
///
/// Attaching channels needs a ready connection, so the caller must not call
/// this before its handshake completes.
pub fn init(
  document: Document(root),
  map: TypedMap(doc_schema.SudokuDoc),
) -> #(Model, Effect(Msg)) {
  let model =
    Model(
      map: map,
      shared: None,
      pending: PendingShared(None, None, None, None),
      puzzle: puzzles.default_puzzle(),
      selected: None,
      notes_mode: False,
      cells: [],
      notes: [],
      givens: [],
      mistakes: 0,
      peers: [],
      editing: False,
      error: None,
    )
  #(
    model,
    effect.batch([
      watershed_lustre.ensure_field(
        map,
        doc_schema.title(),
        "Collaborative Sudoku",
      ),
      watershed_lustre.ensure_field(
        map,
        doc_schema.puzzle(),
        puzzles.default_puzzle().id,
      ),
      watershed_lustre.ensure_map(
        document,
        map,
        doc_schema.cells(),
        EnsuredCells,
      ),
      watershed_lustre.ensure_or_set(
        document,
        map,
        doc_schema.notes(),
        EnsuredNotes,
      ),
      watershed_lustre.ensure_claims(
        document,
        map,
        doc_schema.givens(),
        EnsuredGivens,
      ),
      watershed_lustre.ensure_counter(
        document,
        map,
        doc_schema.mistakes(),
        EnsuredMistakes,
      ),
      // Watch the panel's own map, not the document's root. Composed, the root
      // carries three other panels' handles and none of this panel's state.
      watershed_lustre.subscribe(watershed_js.untyped(map), fn(_event) {
        SharedChanged
      }),
    ]),
  )
}

// ── Update ───────────────────────────────────────────────────────────────────

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
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

    CellSelected(row, col) -> #(
      Model(..model, selected: Some(#(row, col))),
      effect.none(),
    )

    KeyPressed(key) -> {
      let model = handle_key(model, key)
      case model.selected {
        Some(_) -> #(
          Model(..model, editing: True),
          watershed_lustre.after(1200, EditingStopped),
        )
        None -> #(model, effect.none())
      }
    }

    NotesModeClicked -> #(
      Model(..model, notes_mode: !model.notes_mode),
      effect.none(),
    )

    EditingStopped -> #(Model(..model, editing: False), effect.none())
  }
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

/// Draw these peers on the board. A driver is document-scoped, so the owner
/// starts one and hands each panel its share.
pub fn set_peers(model: Model, peers: List(Peer)) -> Model {
  Model(..model, peers: peers)
}

/// What this client is doing on the board, for the owner to broadcast.
pub fn cursor(model: Model) -> Cursor {
  Cursor(
    cell: option.map(model.selected, fn(rc) { cell_key(rc.0, rc.1) }),
    editing: model.editing,
  )
}

/// The mistake counter, for an owner that wants it in its own chrome.
pub fn mistakes(model: Model) -> Int {
  model.mistakes
}

/// The puzzle currently loaded, as agreed by the document.
pub fn puzzle_name(model: Model) -> String {
  model.puzzle.name
}

/// The last bootstrap failure, if any.
pub fn error(model: Model) -> Option(String) {
  model.error
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
  case model.shared {
    Some(shared) ->
      Model(
        ..model,
        puzzle: puzzle_from_map(model.map),
        cells: read_cells(shared.cells),
        notes: watershed_js.or_set_values(shared.notes),
        givens: read_givens(shared.givens),
        mistakes: watershed_js.counter_value(shared.mistakes)
          |> option.unwrap(0),
      )
    None -> model
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

pub fn view(model: Model) -> Element(Msg) {
  html.div([class("sudoku-panel")], [
    toolbar(model),
    grid(model),
    error_view(model.error),
  ])
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
  let peers_here = list.filter(model.peers, fn(peer) { peer.cell == Some(key) })
  let value = case given, player {
    0, Some(digit) -> int.to_string(digit)
    0, None -> ""
    _, _ -> int.to_string(given)
  }

  let peer_attrs = case peers_here {
    [peer, ..] -> [
      attribute.style("box-shadow", "inset 0 0 0 3px " <> peer.color),
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
fn peer_cursor(peers: List(Peer)) -> Element(Msg) {
  case peers {
    [] -> html.text("")
    [peer, ..] ->
      html.span([class("cursor"), attribute.style("background", peer.color)], [
        html.text(peer.name),
        case peer.editing {
          True -> html.text(" ✎")
          False -> html.text("")
        },
      ])
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

/// The agreed puzzle, read from the panel's own map.
///
/// Standalone that map is the document root; composed it is a child of the
/// showcase root. Reading `root_typed` here — as this did before the split —
/// would look up the puzzle id in a map that holds four panel handles.
fn puzzle_from_map(map: TypedMap(doc_schema.SudokuDoc)) -> Puzzle {
  case watershed_js.get_field(map, doc_schema.puzzle()) {
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
