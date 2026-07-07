//// Gleam-end-to-end collaborative Sudoku.
////
//// A Lustre single-page app whose nested watershed structures are bootstrapped
//// from handles stored on the root map. Open two tabs against the same
//// `just server` document and watch cells, notes, givens, and mistakes converge.

import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise
import gleam/json
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

import doc_schema.{type SudokuDoc}
import puzzles.{type Puzzle}
import watershed_js.{
  type Document, type SharedClaims, type SharedCounter, type SharedMap,
  type SharedOrSet, type Signal, type TypedMap, WatershedConfig,
}

import presence.{type Peers, type Presence, Presence}

// ── Dev config for `just server` (levee dev mode) ────────────────────────────

const socket_url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

const document_id = "sudoku"

@external(javascript, "./sudoku_ffi.mjs", "queue_microtask")
fn queue_microtask(action: fn() -> Nil) -> Nil

@external(javascript, "./sudoku_ffi.mjs", "set_timeout")
fn set_timeout(action: fn() -> Nil, ms: Int) -> Nil

@external(javascript, "./sudoku_ffi.mjs", "now_ms")
fn now_ms() -> Int

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

type SharedState {
  SharedState(
    cells: SharedMap,
    notes: SharedOrSet,
    givens: SharedClaims,
    mistakes: SharedCounter,
  )
}

type Model {
  Model(
    status: Status,
    doc: Option(Document),
    shared: Option(SharedState),
    user_id: String,
    color: String,
    puzzle: Puzzle,
    selected: Option(#(Int, Int)),
    notes_mode: Bool,
    cells: List(#(String, Int)),
    notes: List(String),
    givens: List(#(String, Int)),
    mistakes: Int,
    /// Ephemeral peer presence (signals, not a DDS): who's here, their cursor,
    /// and whether they're typing. Expired by heartbeat TTL.
    peers: Peers,
    editing: Bool,
    error: Option(String),
  )
}

type Msg {
  GotHandle(Document)
  Connected(Result(Nil, String))
  Bootstrapped(Result(SharedState, String))
  SharedChanged
  CellSelected(Int, Int)
  KeyPressed(String)
  NotesModeClicked
  ReconnectClicked
  SignalReceived(Signal)
  Heartbeat
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
      user_id: user_id,
      color: presence.color_for(user_id),
      puzzle: puzzles.default_puzzle(),
      selected: None,
      notes_mode: False,
      cells: [],
      notes: [],
      givens: [],
      mistakes: 0,
      peers: presence.new_peers(),
      editing: False,
      error: None,
    )
  #(model, connect_effect(user_id))
}

/// Connect, then bridge watershed's callbacks into Lustre's dispatch.
fn connect_effect(user_id: String) -> Effect(Msg) {
  use dispatch <- effect.from
  let _ = {
    use token <- promise.map(watershed_js.dev_token(
      secret: tenant_secret,
      tenant: tenant,
      document: document_id,
      user_id: user_id,
    ))
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
    watershed_js.subscribe(watershed_js.root(doc), fn(_event) {
      queue_microtask(fn() { dispatch(SharedChanged) })
    })
    // Ephemeral presence rides on signals, independent of the DDS streams.
    watershed_js.subscribe_signals(doc, fn(signal: Signal) {
      queue_microtask(fn() { dispatch(SignalReceived(signal)) })
    })
    dispatch(GotHandle(doc))
  }
  Nil
}

/// A one-shot timer effect that dispatches `msg` after `ms`.
fn after(ms: Int, msg: Msg) -> Effect(Msg) {
  use dispatch <- effect.from
  set_timeout(fn() { dispatch(msg) }, ms)
}

/// Broadcast this client's presence as an ephemeral signal (fire-and-forget).
fn broadcast_presence(model: Model) -> Effect(Msg) {
  case model.doc {
    Some(doc) -> {
      use _dispatch <- effect.from
      let content =
        presence.encode(Presence(
          user: model.user_id,
          color: model.color,
          name: presence.short_name(model.user_id),
          cell: option.map(model.selected, fn(rc) { cell_key(rc.0, rc.1) }),
          editing: model.editing,
        ))
      watershed_js.submit_signal(
        doc,
        signal_type: presence.signal_type,
        content:,
      )
    }
    None -> effect.none()
  }
}

fn bootstrap_effect(doc: Document) -> Effect(Msg) {
  use dispatch <- effect.from
  let root = watershed_js.root_typed(doc)
  // Plain fields seed themselves set-if-absent; LWW settles concurrent joins.
  watershed_js.ensure_field(root, doc_schema.title(), "Collaborative Sudoku")
  watershed_js.ensure_field(
    root,
    doc_schema.puzzle(),
    puzzles.default_puzzle().id,
  )
  ensure_shared(doc, root, fn(result) {
    case result {
      Ok(shared) -> {
        // App-level content seed, on the channel `ensure_claims` handed back:
        // first-writer-wins claims make concurrent seeders converge, so every
        // client can run this and later writers no-op.
        seed_givens(shared.givens, puzzles.default_puzzle(), 0, 0)
        subscribe_shared(shared, dispatch)
        dispatch(Bootstrapped(Ok(shared)))
      }
      Error(reason) -> dispatch(Bootstrapped(Error(reason)))
    }
  })
  Nil
}

/// Adopt (or seed) all four nested channels, threading each `ensure_*`'s result
/// into the next and short-circuiting on the first error.
fn ensure_shared(
  doc: Document,
  root: TypedMap(SudokuDoc),
  done: fn(Result(SharedState, String)) -> Nil,
) -> Nil {
  use cells <- ensure_step(
    watershed_js.ensure_map(doc, root, doc_schema.cells(), _),
    done,
  )
  use notes <- ensure_step(
    watershed_js.ensure_or_set(doc, root, doc_schema.notes(), _),
    done,
  )
  use givens <- ensure_step(
    watershed_js.ensure_claims(doc, root, doc_schema.givens(), _),
    done,
  )
  use mistakes <- ensure_step(
    watershed_js.ensure_counter(doc, root, doc_schema.mistakes(), _),
    done,
  )
  done(Ok(SharedState(cells:, notes:, givens:, mistakes:)))
}

/// Run one callback-based `ensure_*` step: continue with `next` on success, or
/// short-circuit `done` with the error.
fn ensure_step(
  step: fn(fn(Result(a, String)) -> Nil) -> Nil,
  done: fn(Result(whole, String)) -> Nil,
  next: fn(a) -> Nil,
) -> Nil {
  step(fn(result) {
    case result {
      Ok(value) -> next(value)
      Error(reason) -> done(Error(reason))
    }
  })
}

fn subscribe_shared(shared: SharedState, dispatch: fn(Msg) -> Nil) -> Nil {
  let bump = fn() { queue_microtask(fn() { dispatch(SharedChanged) }) }
  // Narrowed per-kind subscriptions: each handler sees only its channel's own
  // event type. The whole-model `snapshot` stays the cheapest re-read for an
  // 81-cell grid, so every handler just bumps it.
  watershed_js.subscribe(shared.cells, fn(_event) { bump() })
  watershed_js.subscribe_or_set(shared.notes, fn(_event) { bump() })
  watershed_js.subscribe_claims(shared.givens, fn(_event) { bump() })
  watershed_js.subscribe_counter(shared.mistakes, fn(_event) { bump() })
}

// ── Update ───────────────────────────────────────────────────────────────────

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    GotHandle(doc) -> {
      let model = Model(..model, doc: Some(doc))
      case model.status, model.shared {
        Ready, None -> #(model, bootstrap_effect(doc))
        _, _ -> #(model, effect.none())
      }
    }

    Connected(Ok(_)) -> {
      let model = Model(..model, status: Ready)
      case model.doc, model.shared {
        Some(doc), None -> #(
          model,
          effect.batch([
            bootstrap_effect(doc),
            after(presence.heartbeat_ms, Heartbeat),
          ]),
        )
        _, _ -> #(snapshot(model), after(presence.heartbeat_ms, Heartbeat))
      }
    }

    Connected(Error(reason)) -> #(
      Model(..model, status: Failed(reason), error: Some(reason)),
      effect.none(),
    )

    Bootstrapped(Ok(shared)) -> #(
      snapshot(Model(..model, shared: Some(shared), error: None)),
      effect.none(),
    )

    Bootstrapped(Error(reason)) -> #(
      Model(..model, error: Some(reason)),
      effect.none(),
    )

    SharedChanged -> #(snapshot(model), effect.none())

    CellSelected(row, col) -> {
      let model = Model(..model, selected: Some(#(row, col)))
      #(model, broadcast_presence(model))
    }

    KeyPressed(key) -> {
      let model = handle_key(model, key)
      case model.selected {
        Some(_) -> {
          let model = Model(..model, editing: True)
          #(
            model,
            effect.batch([
              broadcast_presence(model),
              after(1200, EditingStopped),
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

    ReconnectClicked -> {
      case model.doc {
        Some(doc) -> watershed_js.force_reconnect(doc)
        None -> Nil
      }
      #(model, effect.none())
    }

    SignalReceived(signal) ->
      // levee strips the signal `type` on broadcast (Fluid compat), delivering
      // only clientId + content — so we discriminate by decoding the content.
      case presence.decode(watershed_js.signal_content(signal)) {
        Ok(p) if p.user != model.user_id -> #(
          Model(..model, peers: presence.observe(model.peers, p, now_ms())),
          effect.none(),
        )
        _ -> #(model, effect.none())
      }

    Heartbeat -> #(
      Model(..model, peers: presence.prune(model.peers, now_ms())),
      effect.batch([
        broadcast_presence(model),
        after(presence.heartbeat_ms, Heartbeat),
      ]),
    )

    EditingStopped -> {
      let model = Model(..model, editing: False)
      #(model, broadcast_presence(model))
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

fn toggle_note(notes: SharedOrSet, row: Int, col: Int, digit: Int) -> Nil {
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

fn seed_givens(
  claims: SharedClaims,
  puzzle: Puzzle,
  row: Int,
  col: Int,
) -> Nil {
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
/// entirely from ephemeral signals, so it self-heals when a tab goes away.
fn roster_view(model: Model) -> Element(Msg) {
  let self =
    Presence(
      user: model.user_id,
      color: model.color,
      name: presence.short_name(model.user_id) <> " (you)",
      cell: None,
      editing: model.editing,
    )
  let chips =
    [self, ..presence.roster(model.peers)]
    |> list.map(fn(p) {
      html.span(
        [
          class("chip"),
          attribute.style("border-color", p.color),
          attribute.style("color", p.color),
        ],
        [
          html.span([class("dot"), attribute.style("background", p.color)], []),
          html.text(p.name),
          case p.editing {
            True -> html.span([class("typing")], [html.text(" ✎")])
            False -> html.text("")
          },
        ],
      )
    })
  html.div([class("roster"), aria_label("Players online")], chips)
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
  let peers_here = presence.on_cell(model.peers, key)
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
fn peer_cursor(peers: List(Presence)) -> Element(Msg) {
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

fn read_givens(givens: SharedClaims) -> List(#(String, Int)) {
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
