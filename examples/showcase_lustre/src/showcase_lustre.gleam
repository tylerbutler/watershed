//// Four collaborative apps in one document.
////
//// The examples gallery this borrows from — Liveblocks', PartyKit's — is a
//// *list of separate apps*: each demo is its own document, its own connection,
//// its own roster. This is one document whose panels are separate apps. The
//// panel switcher is instant because nothing reconnects, and one presence
//// roster spans all four, so "Tyler is in the sudoku panel" is a sentence the
//// gallery form cannot say.
////
//// The mechanism is `ChildField` (`showcase_lustre/doc_schema`): the root map
//// holds a handle to each panel's sub-document, each carrying its own phantom
//// tag and its own decode boundary. Every panel is a nested MVU triple —
//// `init(document, map)`, `update`, `view` — living in its own package and
//// still runnable on its own, exactly as `watershed_lustre/textarea` already
//// works inside `text_lustre`.
////
//// Two rules hold this together, and both are load-bearing:
////
////   1. **Only this package's schema touches the root map.** A panel that
////      reaches for `root_typed` silently shares one key namespace with three
////      others. `Document(Showcase)` makes that a type error at the root, and
////      the root-purity test catches what the types cannot.
////   2. **Document-scoped effects belong to the shell.** Anything whose API
////      takes a `Document` rather than a channel — presence, `auto_summarize`,
////      `go_offline`, diagnostics — is document-wide no matter which panel
////      calls it. The canvas's offline toggle is the clearest case: as a panel
////      button it disconnects all four panels, so it lives in the chrome here,
////      labelled as what it is.
////
//// Open two tabs on the same document, switch panels independently, and watch
//// each panel converge on its own while the connection underneath stays put.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

import lustre
import lustre/attribute.{class}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import watershed/browser
import watershed/summary_policy
import watershed_js.{type Document, type TypedMap}
import watershed_lustre

import pixel_canvas_lustre/doc_schema as canvas_schema
import playlist_lustre/doc_schema as playlist_schema
import showcase_lustre/doc_schema
import sudoku_lustre/doc_schema as sudoku_schema
import text_lustre/component as text_panel
import text_lustre/doc_schema as text_schema

// ── Dev config for `just server` (floodgate dev mode) ────────────────────────

const socket_url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

/// Ops past the checkpoint before a summary is attempted.
///
/// One policy per document, set once, here. `auto_summarize` stores a single
/// policy on the runtime rather than a list, so a panel that installed its own
/// would set it for the whole showcase — and with panels initialised lazily,
/// *which* policy won would depend on the order someone clicked. The number is
/// the drum machine's, chosen because a jam writes one op per step toggle; the
/// canvas, which emits ops by the thousand, has strictly more reason to want
/// it, and this document carries every panel's ops in one log.
const summary_threshold = 200

pub fn main() {
  let app = lustre.application(init, update, view)
  let document = browser.document_on_navigate("showcase")
  let assert Ok(_) = lustre.start(app, "#app", document)
  Nil
}

// ── Panels ───────────────────────────────────────────────────────────────────

pub type Panel {
  TextPanel
  PlaylistPanel
  SudokuPanel
  CanvasPanel
}

fn panels() -> List(Panel) {
  [TextPanel, PlaylistPanel, SudokuPanel, CanvasPanel]
}

fn panel_name(panel: Panel) -> String {
  case panel {
    TextPanel -> "Text"
    PlaylistPanel -> "Playlist"
    SudokuPanel -> "Sudoku"
    CanvasPanel -> "Canvas"
  }
}

fn panel_blurb(panel: Panel) -> String {
  case panel {
    TextPanel -> "SharedText · one minimal grapheme op per keystroke"
    PlaylistPanel -> "SharedSequence · ordered move"
    SudokuPanel -> "Claims, OR-set, counter, and a nested map"
    CanvasPanel -> "OrMap register leaves · converges by join"
  }
}

// ── Model ────────────────────────────────────────────────────────────────────

type Status {
  Connecting
  Ready
  Failed(reason: String)
}

/// The four child maps, each filled by its own `ensure_child`.
///
/// They are ensured eagerly and all at once so the document's shape is
/// declarative in one place, and they arrive independently — a panel is
/// openable the moment its own map lands, not when the last one does.
type Maps {
  Maps(
    text: Option(TypedMap(text_schema.TextDoc)),
    playlist: Option(TypedMap(playlist_schema.PlaylistDoc)),
    sudoku: Option(TypedMap(sudoku_schema.SudokuDoc)),
    canvas: Option(TypedMap(canvas_schema.CanvasDoc)),
  )
}

fn no_maps() -> Maps {
  Maps(text: None, playlist: None, sudoku: None, canvas: None)
}

/// The panels that have been opened, each holding its component's model.
///
/// A panel is initialised the first time it is opened, so an unopened panel
/// holds no subscriptions — and once opened it is *kept*, because switching
/// away only hides a panel's view. Dropping it would discard whatever the
/// component owns beyond the document: the canvas's pixel buffer, a caret, a
/// draft in an input.
type Panels {
  Panels(text: Option(text_panel.Model))
}

fn no_panels() -> Panels {
  Panels(text: None)
}

type Model {
  Model(
    status: Status,
    doc: Option(Document(doc_schema.Showcase)),
    user_id: String,
    panel: Panel,
    maps: Maps,
    panels: Panels,
    error: Option(String),
  )
}

type Msg {
  GotHandle(Document(doc_schema.Showcase))
  Connected(Result(Nil, String))
  EnsuredText(Result(TypedMap(text_schema.TextDoc), String))
  EnsuredPlaylist(Result(TypedMap(playlist_schema.PlaylistDoc), String))
  EnsuredSudoku(Result(TypedMap(sudoku_schema.SudokuDoc), String))
  EnsuredCanvas(Result(TypedMap(canvas_schema.CanvasDoc), String))
  PanelPicked(Panel)
  TextMsg(text_panel.Msg)
}

fn init(document: String) -> #(Model, Effect(Msg)) {
  // A distinct user per tab so two tabs are two clients.
  let user_id = "web-" <> int.to_string(1000 + int.random(9000))
  let model =
    Model(
      status: Connecting,
      doc: None,
      user_id: user_id,
      panel: TextPanel,
      maps: no_maps(),
      panels: no_panels(),
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
    // The handle arrives before the handshake. Good for reads, not yet for
    // *creating* channels — `ensure_child` attaches, so it waits for
    // `Connected`.
    GotHandle(doc) -> #(Model(..model, doc: Some(doc)), effect.none())

    Connected(Ok(_)) -> {
      let model = Model(..model, status: Ready)
      case model.doc {
        None -> #(model, effect.none())
        Some(doc) -> #(model, bootstrap_effect(doc))
      }
    }
    Connected(Error(reason)) -> #(
      Model(..model, status: Failed(reason)),
      effect.none(),
    )

    // Each child map arrives on its own. `open_current` is called after every
    // one because the panel showing right now may have been waiting for it.
    EnsuredText(Ok(map)) ->
      open_current(Model(..model, maps: Maps(..model.maps, text: Some(map))))
    EnsuredPlaylist(Ok(map)) ->
      open_current(Model(
        ..model,
        maps: Maps(..model.maps, playlist: Some(map)),
      ))
    EnsuredSudoku(Ok(map)) ->
      open_current(Model(..model, maps: Maps(..model.maps, sudoku: Some(map))))
    EnsuredCanvas(Ok(map)) ->
      open_current(Model(..model, maps: Maps(..model.maps, canvas: Some(map))))

    EnsuredText(Error(reason))
    | EnsuredPlaylist(Error(reason))
    | EnsuredSudoku(Error(reason))
    | EnsuredCanvas(Error(reason)) -> #(
      Model(..model, error: Some(reason)),
      effect.none(),
    )

    PanelPicked(panel) -> open_current(Model(..model, panel: panel))

    TextMsg(inner) ->
      case model.panels.text {
        None -> #(model, effect.none())
        Some(panel) -> {
          let #(panel, fx) = text_panel.update(panel, inner)
          #(
            Model(..model, panels: Panels(text: Some(panel))),
            effect.map(fx, TextMsg),
          )
        }
      }
  }
}

/// Initialise the open panel if it has a child map and no component yet.
///
/// This is the lazy half of decision 5: the maps are ensured eagerly, all at
/// once, so the document's shape is declarative in one place, but a panel's
/// `init` — and therefore its subscriptions — waits until someone looks at it.
/// Already-open panels are left exactly as they are.
fn open_current(model: Model) -> #(Model, Effect(Msg)) {
  case model.doc {
    None -> #(model, effect.none())
    Some(doc) ->
      case model.panel {
        TextPanel ->
          case model.panels.text, model.maps.text {
            None, Some(map) -> {
              let #(panel, fx) = text_panel.init(doc, map)
              #(
                Model(
                  ..model,
                  panels: Panels(text: Some(panel)),
                ),
                effect.map(fx, TextMsg),
              )
            }
            _, _ -> #(model, effect.none())
          }
        _ -> #(model, effect.none())
      }
  }
}

/// Bootstrap the document declaratively: one summarization policy and four
/// child maps, as one batch.
///
/// Every tab runs this unconditionally. `ensure_child` creates a map only if
/// the key is absent, so two tabs opening a *cold* document can both create one
/// and LWW settles a single handle — the loser is orphaned before anybody has
/// interacted with it, and every tab converges on the same four handles. That
/// race predates the showcase; what is new is running it four times per cold
/// start instead of once.
fn bootstrap_effect(doc: Document(doc_schema.Showcase)) -> Effect(Msg) {
  let root = watershed_js.root_typed(doc)
  effect.batch([
    watershed_lustre.auto_summarize(
      document: doc,
      policy: summary_policy.policy()
        |> summary_policy.with_threshold(summary_threshold),
    ),
    watershed_lustre.ensure_child(doc, root, doc_schema.text(), EnsuredText),
    watershed_lustre.ensure_child(
      doc,
      root,
      doc_schema.playlist(),
      EnsuredPlaylist,
    ),
    watershed_lustre.ensure_child(doc, root, doc_schema.sudoku(), EnsuredSudoku),
    watershed_lustre.ensure_child(doc, root, doc_schema.canvas(), EnsuredCanvas),
  ])
}

/// Whether a panel's child map has resolved yet.
fn panel_ready(model: Model, panel: Panel) -> Bool {
  case panel {
    TextPanel -> model.maps.text != None
    PlaylistPanel -> model.maps.playlist != None
    SudokuPanel -> model.maps.sudoku != None
    CanvasPanel -> model.maps.canvas != None
  }
}

// ── View ─────────────────────────────────────────────────────────────────────

fn view(model: Model) -> Element(Msg) {
  html.main([class("shell")], [
    html.header([class("chrome")], [
      html.h1([], [html.text("watershed · showcase")]),
      status_line(model),
    ]),
    switcher(model),
    error_view(model),
    html.section([class("panel")], [panel_view(model)]),
    html.p([class("hint")], [
      html.text(
        "One connection, one document, four apps. Open a second tab and put it "
        <> "on a different panel — the connection underneath is shared, the "
        <> "panels are not. Client: "
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
  let ready =
    panels()
    |> list.filter(panel_ready(model, _))
    |> list.length
  html.p([class("status")], [
    html.text(
      connection <> " · " <> int.to_string(ready) <> " of 4 panels bootstrapped",
    ),
  ])
}

fn switcher(model: Model) -> Element(Msg) {
  html.nav(
    [class("switcher")],
    list.map(panels(), fn(panel) {
      let selected = panel == model.panel
      html.button(
        [
          class(case selected {
            True -> "tab tab-selected"
            False -> "tab"
          }),
          attribute.attribute("aria-pressed", case selected {
            True -> "true"
            False -> "false"
          }),
          event.on_click(PanelPicked(panel)),
        ],
        [html.text(panel_name(panel))],
      )
    }),
  )
}

fn error_view(model: Model) -> Element(Msg) {
  html.p([class("error"), attribute.attribute("role", "alert")], [
    html.text(option.unwrap(model.error, "")),
  ])
}

/// The open panel — the real component if it is mounted, a placeholder while
/// its child map is still being ensured.
fn panel_view(model: Model) -> Element(Msg) {
  case model.panel, model.panels.text {
    TextPanel, Some(panel) -> text_panel.view(panel) |> element.map(TextMsg)
    _, _ -> waiting_view(model)
  }
}

fn waiting_view(model: Model) -> Element(Msg) {
  html.div([class("placeholder")], [
    html.h2([], [html.text(panel_name(model.panel))]),
    html.p([], [html.text(panel_blurb(model.panel))]),
    html.p([class("placeholder-state")], [
      html.text(case panel_ready(model, model.panel) {
        True -> "child map ready"
        False -> "waiting for the child map…"
      }),
    ]),
  ])
}
