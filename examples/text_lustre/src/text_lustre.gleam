//// Collaborative plain-text editor — a `SharedText` demo.
////
//// Where `playlist_lustre` exercises a `SharedSequence`'s ordered `move`, this
//// example exercises the one DDS whose edits are addressed by **grapheme index
//// into a live string**: `SharedText`. A `<textarea>` only ever reports its
//// whole new value on `input`, so the naïve bridge — write the whole string
//// back as one replace — clobbers every concurrent remote keystroke. Instead,
//// each `input` event is diffed against the channel's *current optimistic
//// value* and exactly one minimal op is sent:
////
//// - `text_insert`       — you typed a character (or pasted a run)
//// - `text_delete_range` — you deleted a selection or backspaced
//// - `text_replace_range`— you typed over a selection
//// - `text_append`       — the explicit **Append** action (its own family)
////
//// The diff unit is the Unicode extended grapheme cluster, never the browser's
//// UTF-16 code units: an emoji or a combining mark is one CRDT index, so ops
//// land where the user meant them to.
////
//// That whole bridge lives two levels down now. `watershed_lustre/textarea`
//// owns the snapshot-diff-one-op loop and the caret; `text_lustre/component`
//// owns the document state around it — the body channel, the append action,
//// and the pinned anchor — as a nested MVU triple.
////
//// What is left in *this* module is what an application owns and a panel must
//// not: the connection, the runtime diagnostics, and the presence driver. All
//// three take a `Document` rather than a channel, so they are document-wide
//// wherever they are called from — which is why the same component, mounted in
//// `showcase_lustre` beside three other demos, is handed their results by the
//// shell instead of starting them. Standalone, this module *is* that shell,
//// with one panel and no switcher.
////
//// A pinned **anchor** tracks a stable position as remote edits move text
//// around it, which is the property that makes shared cursors possible — and
//// the presence payload below is that property cashed in: every peer's caret,
//// broadcast as a pair of anchors and drawn in everyone else's editor.
////
//// Open two browser tabs against the same `just server` document to watch edits
//// converge grapheme-for-grapheme.

import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/io
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import watershed.{type Document}
import watershed/browser
import watershed/presence
import watershed/presence_js.{type Handle}
import watershed/text_kernel
import watershed_lustre
import watershed_lustre/textarea

import text_lustre/component
import text_lustre/doc_schema

// ── Dev config for `just server` (levee dev mode) ────────────────────────────

const socket_url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

// ── Presence payload: where everyone's cursor is ─────────────────────────────
//
// The component hands out its selection as a `textarea.Cursor` — a pair of
// anchors, not indices, because an index means nothing to a peer whose replica
// has moved on since. Everything here is app-owned: what else rides along, and
// what each peer is called and coloured.

type Editing {
  Editing(cursor: Option(textarea.Cursor))
}

fn encode_editing(editing: Editing) -> Json {
  json.object([
    #("cursor", case editing.cursor {
      Some(cursor) -> textarea.cursor_to_json(cursor)
      None -> json.null()
    }),
  ])
}

fn editing_decoder() -> Decoder(Editing) {
  use cursor <- decode.field(
    "cursor",
    decode.optional(textarea.cursor_decoder()),
  )
  decode.success(Editing(cursor:))
}

/// A stable colour per user, so a peer keeps the same one across a session.
fn colour_for(user_id: String) -> String {
  let palette = [
    "#e5484d", "#0090ff", "#30a46c", "#f76b15", "#8e4ec6", "#e93d82",
  ]
  let index =
    user_id
    |> string.to_utf_codepoints
    |> list.fold(0, fn(total, point) {
      total + string.utf_codepoint_to_int(point)
    })
  let count = list.length(palette)
  case list.drop(palette, index % count) {
    [colour, ..] -> colour
    [] -> "#0090ff"
  }
}

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let document = browser.document_on_navigate("text")
  let assert Ok(_) = lustre.start(app, "#app", document)
  Nil
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
    doc: Option(Document(doc_schema.TextDoc)),
    /// The editor panel. `None` until the handshake completes — the component
    /// is constructed with a live map, never an empty one.
    editor: Option(component.Model),
    /// Whether this app has taken its own subscription on the body channel.
    /// The component takes one too; a channel fans out to every subscriber.
    traced: Bool,
    user_id: String,
    diagnostics: Option(watershed.Diagnostics),
    diagnostic_log: List(String),
    /// The presence driver, once started, and the last cursor announced
    /// through it — kept so a re-announce only fires when it actually moved.
    presence: Option(Handle(Editing)),
    announced: Option(textarea.Cursor),
  )
}

type Msg {
  GotHandle(Document(doc_schema.TextDoc))
  Connected(Result(Nil, String))
  DiagnosticsTick
  BodyChanged(text_kernel.TextEvent)
  Editor(component.Msg)
  ReconnectClicked
  PresenceStarted(Handle(Editing))
  PresenceEvent(presence.Event(Editing))
}

fn init(document: String) -> #(Model, Effect(Msg)) {
  // A distinct user per tab so the two clients are separate connections.
  let user_id = "web-" <> int.to_string(1000 + int.random(9000))
  let model =
    Model(
      status: Connecting,
      doc: None,
      editor: None,
      traced: False,
      user_id: user_id,
      diagnostics: None,
      diagnostic_log: [],
      presence: None,
      announced: None,
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
    // The handle arrives before the handshake does, so it is good for reads and
    // optimistic edits but not yet for *creating* a channel. Start the
    // diagnostics poll and wait.
    GotHandle(doc) -> {
      let diagnostics = watershed.diagnostics(doc)
      let model =
        Model(..model, doc: Some(doc), diagnostics: Some(diagnostics))
        |> add_diagnostic(
          "document handle acquired · " <> diagnostic_line(diagnostics),
        )
      #(model, watershed_lustre.after(250, DiagnosticsTick))
    }

    // Handshake and history replay are done: mount the panel against this
    // document's root, and start the one presence driver. `root_typed` is the
    // line that makes this the standalone app rather than a panel — mounted in
    // the showcase, the component is handed a *child* map instead, and nothing
    // else about it changes.
    Connected(Ok(_)) -> {
      let model =
        Model(..model, status: Ready)
        |> add_diagnostic("initial handshake complete")
      case model.doc {
        None -> #(model, effect.none())
        Some(doc) -> {
          let #(editor, editor_effect) =
            component.init(doc, watershed.root_typed(doc))
          #(
            Model(..model, editor: Some(editor)),
            effect.batch([
              effect.map(editor_effect, Editor),
              watershed_lustre.presence(
                document: doc,
                config: presence.config(encode_editing, editing_decoder()),
                initial: Editing(cursor: None),
                started: PresenceStarted,
                on_event: PresenceEvent,
              ),
            ]),
          )
        }
      }
    }
    Connected(Error(reason)) -> {
      let model =
        Model(..model, status: Failed(reason))
        |> add_diagnostic("connection failed · " <> reason)
      #(model, effect.none())
    }

    // Every panel message routes through here, which is also where this app
    // notices the caret may have moved and where it picks up its own trace
    // subscription the first time the body channel exists.
    Editor(inner) ->
      case model.editor {
        None -> #(model, effect.none())
        Some(editor) -> {
          let #(editor, editor_effect) = component.update(editor, inner)
          let model = Model(..model, editor: Some(editor))
          let #(model, announce) = announce_cursor(model)
          let #(model, trace) = trace_body(model)
          #(
            model,
            effect.batch([effect.map(editor_effect, Editor), announce, trace]),
          )
        }
      }

    // The app's share of a text event: the diagnostics trace. The component
    // re-renders itself off its own subscription.
    BodyChanged(event) -> {
      let diagnostics = case model.doc {
        Some(doc) -> Some(watershed.diagnostics(doc))
        None -> None
      }
      let detail = case diagnostics {
        Some(diagnostics) ->
          event_line(event) <> " · " <> diagnostic_line(diagnostics)
        None -> event_line(event)
      }
      let model =
        Model(..model, diagnostics: diagnostics)
        |> add_diagnostic(detail)
      #(model, effect.none())
    }

    DiagnosticsTick -> {
      let next = case model.doc {
        Some(doc) -> Some(watershed.diagnostics(doc))
        None -> None
      }
      let model = case next, model.diagnostics {
        Some(current), Some(previous) if current != previous ->
          Model(..model, diagnostics: next)
          |> add_diagnostic("runtime · " <> diagnostic_line(current))
        _, _ -> Model(..model, diagnostics: next)
      }
      #(model, watershed_lustre.after(250, DiagnosticsTick))
    }

    PresenceStarted(handle) ->
      announce_cursor(Model(..model, presence: Some(handle)))

    // The roster changed. Rebuild the component's peer list from it — the
    // component owns resolving each cursor and drawing it; this owns who the
    // peers are and what they look like.
    PresenceEvent(event) ->
      case event {
        presence.Failed(_) -> #(model, effect.none())
        presence.State(entries) | presence.Changed(_, entries) ->
          case model.editor {
            None -> #(model, effect.none())
            Some(editor) -> {
              // Sessions, not users: two tabs from one person are two carets,
              // so the caret is keyed by session id.
              let cursors =
                remote_entries(model, entries)
                |> list.filter_map(fn(peer) {
                  case peer.meta.cursor {
                    Some(cursor) ->
                      Ok(textarea.peer(
                        id: peer.session_id,
                        label: peer.key,
                        colour: colour_for(peer.key),
                        cursor: cursor,
                      ))
                    None -> Error(Nil)
                  }
                })
              let #(editor, editor_effect) =
                component.set_peers(editor, cursors)
              #(
                Model(..model, editor: Some(editor)),
                effect.map(editor_effect, Editor),
              )
            }
          }
      }

    ReconnectClicked ->
      case model.doc {
        Some(doc) -> #(
          add_diagnostic(model, "force reconnect requested"),
          watershed_lustre.force_reconnect(doc),
        )
        None -> #(model, effect.none())
      }
  }
}

/// Take this app's own subscription on the body channel, once, as soon as the
/// component has one to share. The component's subscription drives the editor;
/// this one drives the diagnostics trace.
fn trace_body(model: Model) -> #(Model, Effect(Msg)) {
  case model.traced, model.editor {
    False, Some(editor) ->
      case component.channel(editor) {
        Some(text) -> #(
          Model(..model, traced: True)
            |> add_diagnostic("body text channel ready"),
          watershed_lustre.subscribe_text(text, BodyChanged),
        )
        None -> #(model, effect.none())
      }
    _, _ -> #(model, effect.none())
  }
}

/// Everyone but this tab — a client must not draw a caret for itself.
fn remote_entries(
  model: Model,
  entries: List(presence.PresenceEntry(Editing)),
) -> List(presence.PresenceEntry(Editing)) {
  case model.presence {
    Some(handle) ->
      case presence_js.local_session(handle) {
        Some(session) -> presence.remote_entries(entries, session)
        None -> entries
      }
    None -> entries
  }
}

/// Broadcast this client's cursor, but only when it has actually moved.
///
/// The anchors are value-comparable, and re-anchoring after a remote edit
/// produces the *same* anchors whenever the caret tracked the same content — so
/// this stays quiet through a peer's typing and fires only on a real move.
fn announce_cursor(model: Model) -> #(Model, Effect(Msg)) {
  let current = case model.editor {
    Some(editor) -> component.cursor(editor)
    None -> None
  }

  case model.presence, current == model.announced {
    _, True -> #(model, effect.none())
    None, _ -> #(Model(..model, announced: current), effect.none())
    Some(handle), False -> #(
      Model(..model, announced: current),
      watershed_lustre.update_presence(handle, Editing(cursor: current)),
    )
  }
}

fn add_diagnostic(model: Model, line: String) -> Model {
  let tagged = "[" <> model.user_id <> "] " <> line
  io.println(tagged)
  Model(
    ..model,
    diagnostic_log: list.take([tagged, ..model.diagnostic_log], 40),
  )
}

fn event_line(event: text_kernel.TextEvent) -> String {
  case event {
    text_kernel.TextChanged(value) ->
      "textChanged length=" <> int.to_string(string.length(value))
  }
}

fn diagnostic_line(diagnostics: watershed.Diagnostics) -> String {
  "phase="
  <> diagnostics.phase
  <> " client="
  <> option.unwrap(diagnostics.client_id, "none")
  <> " sn="
  <> option_int(diagnostics.last_seen_sequence_number)
  <> " next_csn="
  <> option_int(diagnostics.next_client_sequence_number)
  <> " in_flight="
  <> int.to_string(diagnostics.in_flight_count)
  <> " buffered="
  <> int.to_string(diagnostics.buffered_out_of_order_count)
  <> " resubmit_at="
  <> option_int(diagnostics.resubmit_checkpoint)
  <> " synced="
  <> bool_to_string(diagnostics.synced)
}

fn option_int(value: Option(Int)) -> String {
  value
  |> option.map(int.to_string)
  |> option.unwrap("none")
}

fn bool_to_string(value: Bool) -> String {
  case value {
    True -> "true"
    False -> "false"
  }
}

// ── View ─────────────────────────────────────────────────────────────────────

fn view(model: Model) -> Element(Msg) {
  html.main([attribute.class("wrap")], [
    html.h1([], [html.text("watershed · collaborative text")]),
    status_line(model),
    panel_view(model),
    html.div([attribute.class("compose")], [
      html.button([event.on_click(ReconnectClicked)], [
        html.text("Force reconnect"),
      ]),
    ]),
    diagnostics_view(model),
    html.p([attribute.class("hint")], [
      html.text(
        "Open a second tab on the same document and type from both — every "
        <> "keystroke sends one minimal grapheme op, and concurrent edits "
        <> "converge. Client: "
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
  let runtime = case model.diagnostics {
    Some(diagnostics) -> " · " <> diagnostics.phase
    None -> ""
  }
  let graphemes = case model.editor {
    Some(editor) -> component.length(editor)
    None -> 0
  }
  html.p([attribute.class("status")], [
    html.text(
      connection <> runtime <> " · " <> int.to_string(graphemes) <> " graphemes",
    ),
  ])
}

fn panel_view(model: Model) -> Element(Msg) {
  case model.editor {
    Some(editor) -> component.view(editor) |> element.map(Editor)
    None -> html.p([attribute.class("status")], [html.text("connecting…")])
  }
}

fn diagnostics_view(model: Model) -> Element(Msg) {
  let current = case model.diagnostics {
    Some(diagnostics) -> diagnostic_line(diagnostics)
    None -> "runtime diagnostics unavailable"
  }
  let log = model.diagnostic_log |> string.join("\n")
  html.section([attribute.class("diagnostics")], [
    html.h2([], [html.text("Diagnostics")]),
    html.p([], [
      html.text(
        "Compare this panel across tabs. Browser DevTools receives the same trace.",
      ),
    ]),
    html.pre([attribute.class("diagnostic-current")], [html.text(current)]),
    html.pre([attribute.class("diagnostic-log")], [html.text(log)]),
  ])
}
