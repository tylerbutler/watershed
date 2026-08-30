//// Four collaborative apps in one document.
////
//// The examples gallery this borrows from — Liveblocks', PartyKit's — is a
//// *list of separate apps*: each demo is its own document, its own connection,
//// its own roster. This is one document whose panels are separate apps. The
//// panel switcher is instant because nothing reconnects, and one presence
//// roster spans all four, so "Tyler is in the sudoku panel" is a sentence the
//// gallery form cannot say.
////
//// The mechanism is `ChildField` (`showcase_lustre/document_schema`): the root
//// map holds a handle to each panel's sub-document, each carrying its own
//// phantom tag and its own decode boundary. Every panel is a nested MVU triple
//// — `init(document, map)`, `update`, `view` — living in its own package and
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
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import watershed.{type Document, type TypedMap}
import watershed/browser
import watershed/presence
import watershed/presence_js.{type Handle}
import watershed/summary_policy
import watershed_lustre

import pixel_canvas_lustre/component as canvas_panel
import pixel_canvas_lustre/document_schema as canvas_schema
import playlist_lustre/component as playlist_panel
import playlist_lustre/document_schema as playlist_schema
import showcase_lustre/document_schema
import showcase_lustre/roster.{type ShowcasePresence, ShowcasePresence}
import sudoku_lustre/component as sudoku_panel
import sudoku_lustre/document_schema as sudoku_schema
import text_lustre/component as text_panel
import text_lustre/document_schema as text_schema
import watershed_lustre/textarea

// ── Dev config for `just server` (floodgate dev mode) ────────────────────────

const socket_url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

/// Operations past the checkpoint before a summary is attempted.
///
/// One policy per document, set once, here. `auto_summarize` stores a single
/// policy on the runtime rather than a list, so a panel that installed its own
/// would set it for the whole showcase — and with panels initialised lazily,
/// *which* policy won would depend on the order someone clicked. The number is
/// the drum machine's, chosen because a jam writes one operation per step
/// toggle; the canvas, which emits operations by the thousand, has strictly
/// more reason to want it, and this document carries every panel's operations
/// in one log.
const summary_threshold = 200

pub fn main() -> Nil {
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
    text: Option(TypedMap(text_schema.TextDocument)),
    playlist: Option(TypedMap(playlist_schema.PlaylistDocument)),
    sudoku: Option(TypedMap(sudoku_schema.SudokuDocument)),
    canvas: Option(TypedMap(canvas_schema.CanvasDocument)),
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
  Panels(
    text: Option(text_panel.Model),
    playlist: Option(playlist_panel.Model),
    sudoku: Option(sudoku_panel.Model),
    canvas: Option(canvas_panel.Model),
  )
}

fn no_panels() -> Panels {
  Panels(text: None, playlist: None, sudoku: None, canvas: None)
}

type Model {
  Model(
    status: Status,
    document: Option(Document(document_schema.Showcase)),
    user_id: String,
    panel: Panel,
    maps: Maps,
    panels: Panels,
    color: String,
    /// The one presence driver for the whole document, and the last payload
    /// announced through it — kept so a re-announce only fires on a real move.
    presence: Option(Handle(ShowcasePresence)),
    peers: List(presence.PresenceEntry(ShowcasePresence)),
    announced: Option(ShowcasePresence),
    /// Promoted out of the canvas panel: both describe the document, and
    /// neither can be scoped to a channel.
    offline: Bool,
    diagnostics: Option(watershed.Diagnostics),
    error: Option(String),
  )
}

type Msg {
  GotHandle(Document(document_schema.Showcase))
  Connected(Result(Nil, String))
  EnsuredText(Result(TypedMap(text_schema.TextDocument), String))
  EnsuredPlaylist(Result(TypedMap(playlist_schema.PlaylistDocument), String))
  EnsuredSudoku(Result(TypedMap(sudoku_schema.SudokuDocument), String))
  EnsuredCanvas(Result(TypedMap(canvas_schema.CanvasDocument), String))
  PanelPicked(Panel)
  PresenceStarted(Handle(ShowcasePresence))
  PresenceEvent(presence.Event(ShowcasePresence))
  TextMsg(text_panel.Msg)
  PlaylistMsg(playlist_panel.Msg)
  SudokuMsg(sudoku_panel.Msg)
  CanvasMsg(canvas_panel.Msg)
  ToggledOffline(Bool)
  DiagnosticsTick
}

fn init(document: String) -> #(Model, Effect(Msg)) {
  // A distinct user per tab so two tabs are two clients.
  let user_id = "web-" <> int.to_string(1000 + int.random(9000))
  let model =
    Model(
      status: Connecting,
      document: None,
      user_id: user_id,
      panel: TextPanel,
      maps: no_maps(),
      panels: no_panels(),
      color: presence.color_for(user_id),
      presence: None,
      peers: [],
      announced: None,
      offline: False,
      diagnostics: None,
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
    GotHandle(document) -> {
      let model =
        Model(
          ..model,
          document: Some(document),
          diagnostics: Some(watershed.diagnostics(document)),
        )
      #(
        model,
        effect.batch([
          presence_effect(model, document),
          watershed_lustre.after(250, DiagnosticsTick),
        ]),
      )
    }

    Connected(Ok(_)) -> {
      let model = Model(..model, status: Ready)
      case model.document {
        None -> #(model, effect.none())
        Some(document) -> #(model, bootstrap_effect(document))
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
      open_current(
        Model(..model, maps: Maps(..model.maps, playlist: Some(map))),
      )
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

    // Switching panels moves this client, which is a presence change: the
    // roster's whole point is that it can say which panel someone is in.
    PanelPicked(panel) -> {
      let #(model, opened) = open_current(Model(..model, panel: panel))
      let #(model, announce) = announce(model)
      #(model, effect.batch([opened, announce]))
    }

    PresenceStarted(handle) -> announce(Model(..model, presence: Some(handle)))

    PresenceEvent(event) ->
      case event {
        presence.State(entries) | presence.Changed(_, entries) -> {
          push_peers(Model(..model, peers: remote_peers(model, entries)))
        }
        // A peer whose payload will not decode is dropped by the driver. A
        // rejected join is worth surfacing: presence silently not working is
        // exactly the failure this one-driver design exists to avoid.
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

    TextMsg(inner) ->
      case model.panels.text {
        None -> #(model, effect.none())
        Some(panel) -> {
          let #(panel, panel_effect) = text_panel.update(panel, inner)
          let #(model, announce) =
            announce(
              Model(..model, panels: Panels(..model.panels, text: Some(panel))),
            )
          #(model, effect.batch([effect.map(panel_effect, TextMsg), announce]))
        }
      }

    PlaylistMsg(inner) ->
      case model.panels.playlist {
        None -> #(model, effect.none())
        Some(panel) -> {
          let #(panel, panel_effect) = playlist_panel.update(panel, inner)
          #(
            Model(
              ..model,
              panels: Panels(..model.panels, playlist: Some(panel)),
            ),
            effect.map(panel_effect, PlaylistMsg),
          )
        }
      }

    SudokuMsg(inner) ->
      case model.panels.sudoku {
        None -> #(model, effect.none())
        Some(panel) -> {
          let #(panel, panel_effect) = sudoku_panel.update(panel, inner)
          let #(model, announce) =
            announce(
              Model(
                ..model,
                panels: Panels(..model.panels, sudoku: Some(panel)),
              ),
            )
          #(
            model,
            effect.batch([effect.map(panel_effect, SudokuMsg), announce]),
          )
        }
      }

    CanvasMsg(inner) ->
      case model.panels.canvas {
        None -> #(model, effect.none())
        Some(panel) -> {
          let #(panel, panel_effect) = canvas_panel.update(panel, inner)
          let #(model, announce) =
            announce(
              Model(
                ..model,
                panels: Panels(..model.panels, canvas: Some(panel)),
              ),
            )
          #(
            model,
            effect.batch([effect.map(panel_effect, CanvasMsg), announce]),
          )
        }
      }

    // Document-scoped, and therefore the shell's. As a panel button this would
    // disconnect the other three panels along with the one it appears in.
    ToggledOffline(offline) ->
      case model.document {
        None -> #(model, effect.none())
        Some(document) -> #(Model(..model, offline: offline), case offline {
          True -> watershed_lustre.go_offline(document)
          False -> watershed_lustre.go_online(document)
        })
      }

    DiagnosticsTick ->
      case model.document {
        None -> #(model, effect.none())
        Some(document) -> #(
          Model(..model, diagnostics: Some(watershed.diagnostics(document))),
          watershed_lustre.after(250, DiagnosticsTick),
        )
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
  case model.document {
    None -> #(model, effect.none())
    Some(document) ->
      case model.panel {
        TextPanel ->
          case model.panels.text, model.maps.text {
            None, Some(map) -> {
              let #(panel, panel_effect) = text_panel.init(document, map)
              #(
                Model(
                  ..model,
                  panels: Panels(..model.panels, text: Some(panel)),
                ),
                effect.map(panel_effect, TextMsg),
              )
            }
            _, _ -> #(model, effect.none())
          }
        PlaylistPanel ->
          case model.panels.playlist, model.maps.playlist {
            None, Some(map) -> {
              let #(panel, panel_effect) =
                playlist_panel.init(document, map, model.user_id)
              #(
                Model(
                  ..model,
                  panels: Panels(..model.panels, playlist: Some(panel)),
                ),
                effect.map(panel_effect, PlaylistMsg),
              )
            }
            _, _ -> #(model, effect.none())
          }
        SudokuPanel ->
          case model.panels.sudoku, model.maps.sudoku {
            None, Some(map) -> {
              let #(panel, panel_effect) = sudoku_panel.init(document, map)
              #(
                Model(
                  ..model,
                  panels: Panels(..model.panels, sudoku: Some(panel)),
                ),
                effect.map(panel_effect, SudokuMsg),
              )
            }
            _, _ -> #(model, effect.none())
          }
        CanvasPanel ->
          case model.panels.canvas, model.maps.canvas {
            None, Some(map) -> {
              let #(panel, panel_effect) = canvas_panel.init(document, map)
              #(
                Model(
                  ..model,
                  panels: Panels(..model.panels, canvas: Some(panel)),
                ),
                effect.map(panel_effect, CanvasMsg),
              )
            }
            _, _ -> #(model, effect.none())
          }
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
fn bootstrap_effect(
  document: Document(document_schema.Showcase),
) -> Effect(Msg) {
  let root = watershed.root_typed(document)
  effect.batch([
    watershed_lustre.auto_summarize(
      document: document,
      policy: summary_policy.policy()
        |> summary_policy.with_threshold(summary_threshold),
    ),
    watershed_lustre.ensure_child(
      document,
      root,
      document_schema.text(),
      EnsuredText,
    ),
    watershed_lustre.ensure_child(
      document,
      root,
      document_schema.playlist(),
      EnsuredPlaylist,
    ),
    watershed_lustre.ensure_child(
      document,
      root,
      document_schema.sudoku(),
      EnsuredSudoku,
    ),
    watershed_lustre.ensure_child(
      document,
      root,
      document_schema.canvas(),
      EnsuredCanvas,
    ),
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

// ── Presence: one driver, four panels ────────────────────────────────────────

/// Start the document's only presence driver.
///
/// It needs the handle, not the handshake, so it starts as soon as the document
/// exists. Every panel's peers are derived from this one roster: a second
/// driver anywhere in the app would cross-talk with this one, because they
/// share a ripple kind and differ only in payload.
fn presence_effect(
  model: Model,
  document: Document(document_schema.Showcase),
) -> Effect(Msg) {
  watershed_lustre.presence(
    document: document,
    config: presence.config(roster.encode, roster.decoder()),
    initial: current_presence(model),
    started: PresenceStarted,
    on_event: PresenceEvent,
  )
}

/// Broadcast this client's presence, but only when it actually changed.
///
/// Panel messages arrive constantly — every keystroke routes through `update` —
/// and most of them move nothing a peer can see. Comparing the whole payload
/// keeps the wire quiet without any per-panel bookkeeping.
fn announce(model: Model) -> #(Model, Effect(Msg)) {
  let current = current_presence(model)
  case model.presence, Some(current) == model.announced {
    _, True -> #(model, effect.none())
    None, _ -> #(Model(..model, announced: Some(current)), effect.none())
    Some(handle), False -> #(
      Model(..model, announced: Some(current)),
      watershed_lustre.update_presence(handle, current),
    )
  }
}

/// This client's identity, plus whatever the open panel says about where it is.
fn current_presence(model: Model) -> ShowcasePresence {
  ShowcasePresence(
    name: presence.short_name(model.user_id),
    color: model.color,
    where: case model.panel {
      TextPanel ->
        roster.InText(case model.panels.text {
          Some(panel) -> text_panel.cursor(panel)
          None -> None
        })
      PlaylistPanel -> roster.InPlaylist
      SudokuPanel ->
        roster.InSudoku(case model.panels.sudoku {
          Some(panel) -> sudoku_panel.cursor(panel)
          None -> sudoku_panel.Cursor(cell: None, editing: False)
        })
      CanvasPanel ->
        roster.InCanvas(case model.panels.canvas {
          Some(panel) -> canvas_panel.cursor(panel)
          None -> None
        })
    },
  )
}

/// Everyone but this tab. Presence state includes the local session by design,
/// so the roster is filtered here rather than in the driver.
fn remote_peers(
  model: Model,
  entries: List(presence.PresenceEntry(ShowcasePresence)),
) -> List(presence.PresenceEntry(ShowcasePresence)) {
  case model.presence {
    Some(handle) ->
      case presence_js.local_session(handle) {
        Some(session) -> presence.remote_entries(entries, session)
        None -> entries
      }
    None -> entries
  }
}

/// Hand each panel the peers that are actually in it.
///
/// This is the filtering the plan calls for, and it is the reason a panel never
/// needs to know that other panels exist: a text peer is invisible to the
/// board, and a sudoku peer is invisible to the editor, because neither
/// survives the other's `case`.
fn push_peers(model: Model) -> #(Model, Effect(Msg)) {
  let text_peers =
    list.filter_map(model.peers, fn(peer) {
      case peer.meta.where {
        roster.InText(Some(cursor)) ->
          Ok(textarea.peer(
            id: peer.session_id,
            label: peer.meta.name,
            colour: peer.meta.color,
            cursor: cursor,
          ))
        roster.InText(None)
        | roster.InPlaylist
        | roster.InSudoku(_)
        | roster.InCanvas(_) -> Error(Nil)
      }
    })
  let sudoku_peers =
    list.filter_map(model.peers, fn(peer) {
      case peer.meta.where {
        roster.InSudoku(cursor) ->
          Ok(sudoku_panel.Peer(
            name: peer.meta.name,
            color: peer.meta.color,
            cell: cursor.cell,
            editing: cursor.editing,
          ))
        roster.InText(_) | roster.InPlaylist | roster.InCanvas(_) -> Error(Nil)
      }
    })

  let canvas_peers =
    list.filter_map(model.peers, fn(peer) {
      case peer.meta.where {
        roster.InCanvas(Some(cell)) ->
          Ok(canvas_panel.Peer(
            name: peer.meta.name,
            color: peer.meta.color,
            cell: cell,
          ))
        roster.InCanvas(None)
        | roster.InText(_)
        | roster.InPlaylist
        | roster.InSudoku(_) -> Error(Nil)
      }
    })

  // The board's and the canvas's `set_peers` are pure model updates; the
  // editor's returns an effect, because drawing a peer's caret means
  // re-resolving its anchors against the live channel.
  let panels = case model.panels.sudoku {
    Some(board) ->
      Panels(
        ..model.panels,
        sudoku: Some(sudoku_panel.set_peers(board, sudoku_peers)),
      )
    None -> model.panels
  }
  let panels = case panels.canvas {
    Some(canvas) ->
      Panels(
        ..panels,
        canvas: Some(canvas_panel.set_peers(canvas, canvas_peers)),
      )
    None -> panels
  }
  case panels.text {
    None -> #(Model(..model, panels: panels), effect.none())
    Some(editor) -> {
      let #(editor, panel_effect) = text_panel.set_peers(editor, text_peers)
      #(
        Model(..model, panels: Panels(..panels, text: Some(editor))),
        effect.map(panel_effect, TextMsg),
      )
    }
  }
}

// ── View ─────────────────────────────────────────────────────────────────────

fn view(model: Model) -> Element(Msg) {
  html.main([attribute.class("shell")], [
    html.header([attribute.class("chrome")], [
      html.h1([], [html.text("watershed · showcase")]),
      status_line(model),
      roster_view(model),
    ]),
    switcher(model),
    connection_view(model),
    error_view(model),
    html.section([attribute.class("panel")], [panel_view(model)]),
    html.p([attribute.class("hint")], [
      html.text(
        "One connection, one document, four apps. Open a second tab and put it "
        <> "on a different panel — the connection underneath is shared, the "
        <> "panels are not. Client: "
        <> model.user_id,
      ),
    ]),
  ])
}

/// Who is here, and which panel each of them is in.
///
/// This is the sentence the gallery form cannot say. Four separate apps give
/// four separate rosters, each blind to the others; one document gives one
/// roster that spans panels, so "Dana is in the sudoku panel" is a fact this
/// chrome can state while you are looking at the text editor.
fn roster_view(model: Model) -> Element(Msg) {
  let self =
    chip(
      presence.short_name(model.user_id) <> " (you)",
      model.color,
      panel_name(model.panel),
    )
  let peers =
    list.map(model.peers, fn(peer) {
      chip(peer.meta.name, peer.meta.color, roster.panel_label(peer.meta.where))
    })
  html.div(
    [
      attribute.class("roster"),
      attribute.attribute("aria-label", "Who is here"),
    ],
    [self, ..peers],
  )
}

fn chip(name: String, color: String, where: String) -> Element(Msg) {
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
      html.span([attribute.class("chip-where")], [html.text(" · " <> where)]),
    ],
  )
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
  html.p([attribute.class("status")], [
    html.text(
      connection <> " · " <> int.to_string(ready) <> " of 4 panels bootstrapped",
    ),
  ])
}

fn switcher(model: Model) -> Element(Msg) {
  html.nav(
    [attribute.class("switcher")],
    list.map(panels(), fn(panel) {
      let selected = panel == model.panel
      html.button(
        [
          attribute.class(case selected {
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

/// The two controls promoted out of the canvas panel.
///
/// `go_offline` and `diagnostics` both take a `Document`. As panel furniture
/// they read as "stop syncing the canvas" and "the canvas's in-flight count";
/// they are in fact the whole document's, so they belong to the shell and are
/// labelled that way. It also makes the better demo: one click partitions all
/// four panels, and coming back converges a text buffer, a sequence, a claims
/// grid, and an OR-map together.
fn connection_view(model: Model) -> Element(Msg) {
  let detail = case model.diagnostics {
    Some(diagnostics) ->
      diagnostics.phase
      <> " · "
      <> int.to_string(diagnostics.in_flight_count)
      <> " ops in flight"
    None -> "runtime diagnostics unavailable"
  }
  html.div([attribute.class("connection")], [
    html.button(
      [
        event.on_click(ToggledOffline(!model.offline)),
        attribute.attribute("aria-pressed", case model.offline {
          True -> "true"
          False -> "false"
        }),
        attribute.disabled(model.document == None),
      ],
      [
        html.text(case model.offline {
          True -> "Come back online"
          False -> "Take the document offline"
        }),
      ],
    ),
    html.span([attribute.class("connection-detail")], [html.text(detail)]),
  ])
}

fn error_view(model: Model) -> Element(Msg) {
  html.p([attribute.class("error"), attribute.attribute("role", "alert")], [
    html.text(option.unwrap(model.error, "")),
  ])
}

/// The open panel — the real component if it is mounted, a placeholder while
/// its child map is still being ensured.
fn panel_view(model: Model) -> Element(Msg) {
  case model.panel {
    TextPanel ->
      case model.panels.text {
        Some(panel) -> text_panel.view(panel) |> element.map(TextMsg)
        None -> waiting_view(model)
      }
    PlaylistPanel ->
      case model.panels.playlist {
        Some(panel) -> playlist_panel.view(panel) |> element.map(PlaylistMsg)
        None -> waiting_view(model)
      }
    SudokuPanel ->
      case model.panels.sudoku {
        Some(panel) -> sudoku_panel.view(panel) |> element.map(SudokuMsg)
        None -> waiting_view(model)
      }
    CanvasPanel ->
      case model.panels.canvas {
        Some(panel) -> canvas_panel.view(panel) |> element.map(CanvasMsg)
        None -> waiting_view(model)
      }
  }
}

fn waiting_view(model: Model) -> Element(Msg) {
  html.div([attribute.class("placeholder")], [
    html.h2([], [html.text(panel_name(model.panel))]),
    html.p([], [html.text(panel_blurb(model.panel))]),
    html.p([attribute.class("placeholder-state")], [
      html.text(case panel_ready(model, model.panel) {
        True -> "child map ready"
        False -> "waiting for the child map…"
      }),
    ]),
  ])
}
