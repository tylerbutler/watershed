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
//// `root_typed(document)`, and so did the puzzle read on every snapshot; both
//// now address the map they were handed. The `Document` parameter survives
//// only because `ensure_*` needs it to attach a channel.
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
import gleam/result

import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import watershed.{
  type Claims, type Document, type OrSet, type SharedCounter, type SharedMap,
  type TypedMap,
}
import watershed_lustre

import sudoku_lustre/document_schema
import sudoku_lustre/puzzle.{type Puzzle}

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
    map: TypedMap(document_schema.SudokuDocument),
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
  map: TypedMap(document_schema.SudokuDocument),
) -> #(Model, Effect(Msg)) {
  let model =
    Model(
      map: map,
      shared: None,
      pending: PendingShared(None, None, None, None),
      puzzle: puzzle.default_puzzle(),
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
        document_schema.title(),
        "Collaborative Sudoku",
      ),
      watershed_lustre.ensure_field(
        map,
        document_schema.puzzle(),
        puzzle.default_puzzle().id,
      ),
      watershed_lustre.ensure_map(
        document,
        map,
        document_schema.cells(),
        EnsuredCells,
      ),
      watershed_lustre.ensure_or_set(
        document,
        map,
        document_schema.notes(),
        EnsuredNotes,
      ),
      watershed_lustre.ensure_claims(
        document,
        map,
        document_schema.givens(),
        EnsuredGivens,
      ),
      watershed_lustre.ensure_counter(
        document,
        map,
        document_schema.mistakes(),
        EnsuredMistakes,
      ),
      // Watch the panel's own map, not the document's root. Composed, the root
      // carries three other panels' handles and none of this panel's state.
      watershed_lustre.subscribe(watershed.untyped(map), fn(_event) {
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

    CellSelected(row, column) -> #(
      Model(..model, selected: Some(#(row, column))),
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
/// and later writers do nothing) and start the per-channel subscriptions. A
/// no-operation until the last channel arrives or once already assembled.
fn assemble(model: Model) -> #(Model, Effect(Msg)) {
  case model.shared, model.pending {
    None, PendingShared(Some(cells), Some(notes), Some(givens), Some(mistakes))
    -> {
      let shared = SharedState(cells:, notes:, givens:, mistakes:)
      seed_givens(givens, puzzle.default_puzzle(), 0, 0)
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
    cell: option.map(model.selected, fn(position) {
      cell_key(position.0, position.1)
    }),
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
    Some(#(row, column)), Some(shared) ->
      case digit_from_key(key) {
        Ok(digit) -> {
          case is_locked(model, row, column) {
            True -> model
            False -> {
              case model.notes_mode {
                True -> toggle_note(shared.notes, row, column, digit)
                False -> set_cell(shared, model.puzzle, row, column, digit)
              }
              model
            }
          }
        }
        Error(Nil) -> {
          case key == "Backspace" || key == "Delete" {
            True -> {
              case is_locked(model, row, column) {
                True -> Nil
                False -> watershed.delete(shared.cells, cell_key(row, column))
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

fn toggle_note(notes: OrSet, row: Int, column: Int, digit: Int) -> Nil {
  let key = note_key(row, column, digit)
  case watershed.or_set_contains(notes, key) {
    True -> watershed.or_set_remove(notes, key)
    False -> watershed.or_set_add(notes, key)
  }
}

fn set_cell(
  shared: SharedState,
  active_puzzle: Puzzle,
  row: Int,
  column: Int,
  digit: Int,
) -> Nil {
  watershed.set(shared.cells, cell_key(row, column), json.int(digit))
  case digit == puzzle.solution_at(active_puzzle, row, column) {
    True -> Nil
    False -> watershed.increment(shared.mistakes, 1)
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
        notes: watershed.or_set_values(shared.notes),
        givens: read_givens(shared.givens),
        mistakes: watershed.counter_value(shared.mistakes)
          |> result.unwrap(0),
      )
    None -> model
  }
}

// ── Content seeding ──────────────────────────────────────────────────────────

fn seed_givens(
  claims: Claims,
  active_puzzle: Puzzle,
  row: Int,
  column: Int,
) -> Nil {
  case row >= 9 {
    True -> Nil
    False -> {
      let given = puzzle.given_at(active_puzzle, row, column)
      case given > 0 {
        True -> {
          let _ =
            watershed.claim_once(claims, cell_key(row, column), json.int(given))
          Nil
        }
        False -> Nil
      }
      case column == 8 {
        True -> seed_givens(claims, active_puzzle, row + 1, 0)
        False -> seed_givens(claims, active_puzzle, row, column + 1)
      }
    }
  }
}

// ── View ─────────────────────────────────────────────────────────────────────

pub fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("sudoku-panel")], [
    toolbar(model),
    grid(model),
    error_view(model.error),
  ])
}

fn toolbar(model: Model) -> Element(Msg) {
  html.div([attribute.class("toolbar")], [
    html.span([attribute.class("mistakes")], [
      html.text("Mistakes: " <> int.to_string(model.mistakes)),
    ]),
    html.button(
      [
        event.on_click(NotesModeClicked),
        attribute.aria_pressed(bool_to_string(model.notes_mode)),
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
      attribute.class("grid"),
      attribute.role("grid"),
      attribute.tabindex(0),
      attribute.aria_label("Collaborative Sudoku grid"),
      event.on_keydown(KeyPressed),
    ],
    rows_and_cols()
      |> list.map(fn(cell) { cell_view(model, cell.0, cell.1) }),
  )
}

fn cell_view(model: Model, row: Int, column: Int) -> Element(Msg) {
  let key = cell_key(row, column)
  let given = given_value(model, row, column)
  let player = cell_value(model, key)
  let selected = model.selected == Some(#(row, column))
  let locked = given != 0
  let peers_here = list.filter(model.peers, fn(peer) { peer.cell == Some(key) })
  let value = case given, player {
    0, Ok(digit) -> int.to_string(digit)
    0, Error(Nil) -> ""
    _, _ -> int.to_string(given)
  }

  let peer_attributes = case peers_here {
    [peer, ..] -> [
      attribute.style("box-shadow", "inset 0 0 0 3px " <> peer.color),
    ]
    [] -> []
  }

  html.button(
    list.append(
      [
        attribute.classes([
          #("cell", True),
          #("given", locked),
          #("selected", selected),
          #("peer", peers_here != []),
        ]),
        attribute.role("gridcell"),
        attribute.aria_selected(selected),
        attribute.aria_label(cell_label(row, column, value, locked)),
        event.on_click(CellSelected(row, column)),
      ],
      peer_attributes,
    ),
    [
      case value == "" {
        True -> notes_view(model, row, column)
        False -> html.span([attribute.class("digit")], [html.text(value)])
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
      html.span(
        [attribute.class("cursor"), attribute.style("background", peer.color)],
        [
          html.text(peer.name),
          case peer.editing {
            True -> html.text(" ✎")
            False -> html.text("")
          },
        ],
      )
  }
}

fn notes_view(model: Model, row: Int, column: Int) -> Element(Msg) {
  html.div(
    [attribute.class("notes")],
    digits()
      |> list.map(fn(digit) {
        let text = case
          list.contains(model.notes, note_key(row, column, digit))
        {
          True -> int.to_string(digit)
          False -> ""
        }
        html.span([attribute.class("note")], [html.text(text)])
      }),
  )
}

fn error_view(error: Option(String)) -> Element(Msg) {
  case error {
    Some(reason) ->
      html.p([attribute.class("status")], [html.text("Error: " <> reason)])
    None -> html.text("")
  }
}

// ── Read helpers ─────────────────────────────────────────────────────────────

/// The agreed puzzle, read from the panel's own map.
///
/// Standalone that map is the document root; composed it is a child of the
/// showcase root. Reading `root_typed` here — as this did before the split —
/// would look up the puzzle id in a map that holds four panel handles.
fn puzzle_from_map(map: TypedMap(document_schema.SudokuDocument)) -> Puzzle {
  case watershed.get_field(map, document_schema.puzzle()) {
    Ok(Some(id)) -> puzzle.by_id(id) |> result.unwrap(puzzle.default_puzzle())
    _ -> puzzle.default_puzzle()
  }
}

fn read_cells(cells: SharedMap) -> List(#(String, Int)) {
  cells
  |> watershed.entries
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
    case watershed.get_claim(givens, key) {
      Ok(value) ->
        case json.parse(json.to_string(value), decode.int) {
          Ok(digit) -> Ok(#(key, digit))
          Error(_) -> Error(Nil)
        }
      Error(_) -> Error(Nil)
    }
  })
}

fn given_value(model: Model, row: Int, column: Int) -> Int {
  value_from_pairs(model.givens, cell_key(row, column))
  |> result.unwrap(puzzle.given_at(model.puzzle, row, column))
}

/// The digit a player wrote in this cell. The result is `Error(Nil)` when the
/// cell is empty.
fn cell_value(model: Model, key: String) -> Result(Int, Nil) {
  value_from_pairs(model.cells, key)
}

fn value_from_pairs(
  pairs: List(#(String, Int)),
  key: String,
) -> Result(Int, Nil) {
  list.key_find(pairs, key)
}

fn is_locked(model: Model, row: Int, column: Int) -> Bool {
  given_value(model, row, column) != 0
}

// ── Formatting helpers ──────────────────────────────────────────────────────

fn cell_key(row: Int, column: Int) -> String {
  "r" <> int.to_string(row) <> "c" <> int.to_string(column)
}

fn note_key(row: Int, column: Int, digit: Int) -> String {
  cell_key(row, column) <> "=" <> int.to_string(digit)
}

/// The digit that a key press names. The result is `Error(Nil)` when the key
/// is not a digit from 1 to 9.
fn digit_from_key(key: String) -> Result(Int, Nil) {
  case int.parse(key) {
    Ok(digit) ->
      case digit >= 1 && digit <= 9 {
        True -> Ok(digit)
        False -> Error(Nil)
      }
    Error(Nil) -> Error(Nil)
  }
}

fn cell_label(row: Int, column: Int, value: String, locked: Bool) -> String {
  let prefix =
    "Row " <> int.to_string(row + 1) <> ", column " <> int.to_string(column + 1)
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
  let columns = range(0, 9)
  rows
  |> list.flat_map(fn(row) {
    columns |> list.map(fn(column) { #(row, column) })
  })
}

fn digits() -> List(Int) {
  range(1, 10)
}

fn range(from: Int, to: Int) -> List(Int) {
  int.range(from: from, to: to, with: [], run: fn(acc, i) { [i, ..acc] })
  |> list.reverse
}

fn bool_to_string(value: Bool) -> String {
  case value {
    True -> "true"
    False -> "false"
  }
}
