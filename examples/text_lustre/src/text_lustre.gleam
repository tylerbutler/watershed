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
//// That whole bridge — snapshot, diff, one minimal op, error folding, and
//// holding the caret still while a peer edits around it — is
//// `watershed_lustre/textarea`, a nested MVU triple this app holds as
//// `editor` and routes messages through. What is left here is what an app
//// actually owns: connecting, bootstrapping the schema, layout, and the
//// mutations the component does not perform (append, anchors).
////
//// Every mutation returns `Result(Nil, String)` — an index can go stale when a
//// peer edits between render and keystroke — and the app surfaces the runtime's
//// message in a banner rather than asserting.
////
//// A pinned **anchor** (`text_anchor_at`) tracks a stable position in the
//// document: as remote edits insert and delete text before it, its resolved
//// grapheme index moves with the content, which is the property that makes
//// shared cursors possible (though broadcasting them is out of scope here).
//// The component uses the same primitive internally for the user's caret,
//// which is why a peer's keystroke no longer teleports it.
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
import lustre/attribute.{class, disabled, placeholder, rows, value}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import watershed/presence
import watershed/presence_js.{type Handle}
import watershed/text_kernel
import watershed_js.{type Document, type SharedText, type TextAnchor}
import watershed_lustre
import watershed_lustre/textarea

import doc_schema
import watershed/browser

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

pub fn main() {
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
    /// The bound `<textarea>`. `None` until `ensure_text` resolves — the
    /// component is constructed with a live channel, never an empty one.
    editor: Option(textarea.Model),
    user_id: String,
    draft_append: String,
    anchor: Option(TextAnchor),
    anchor_pos: Option(Int),
    last_error: Option(String),
    diagnostics: Option(watershed_js.Diagnostics),
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
  EnsuredBody(Result(SharedText, String))
  BodyChanged(text_kernel.TextEvent)
  DiagnosticsTick
  Editor(textarea.Msg)
  DraftAppendChanged(String)
  AppendClicked
  PinAnchorClicked
  ClearAnchorClicked
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
      user_id: user_id,
      draft_append: "",
      anchor: None,
      anchor_pos: None,
      last_error: None,
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
      let diagnostics = watershed_js.diagnostics(doc)
      let model =
        Model(..model, doc: Some(doc), diagnostics: Some(diagnostics))
        |> add_diagnostic(
          "document handle acquired · " <> diagnostic_line(diagnostics),
        )
      #(model, watershed_lustre.after(250, DiagnosticsTick))
    }

    // Handshake and history replay are done: now seed the title and bootstrap
    // the body text channel. `ensure_text` creates and attaches one only if the
    // slot is empty, so every tab runs this unconditionally without racing to a
    // duplicate — the property that makes joiners converge on the *same*
    // document. Attaching a channel needs a ready connection, which is why this
    // waits rather than firing alongside the handle.
    Connected(Ok(_)) -> {
      let model =
        Model(..model, status: Ready)
        |> add_diagnostic("initial handshake complete")
      case model.doc {
        None -> #(model, effect.none())
        Some(doc) -> {
          let root = watershed_js.root_typed(doc)
          #(
            model,
            effect.batch([
              watershed_lustre.ensure_field(
                root,
                doc_schema.title(),
                "watershed shared document",
              ),
              watershed_lustre.ensure_text(
                doc,
                root,
                doc_schema.body(),
                EnsuredBody,
              ),
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

    // The body resolved: hand the live channel to the component, which
    // subscribes and takes its own first snapshot so a tab joining an existing
    // document renders its text without waiting for an edit. The second
    // subscription here is this app's own — a channel fans out to every
    // subscriber — and drives the diagnostics panel and the pinned anchor.
    EnsuredBody(Ok(text)) -> {
      let #(editor, editor_effect) = textarea.init(text)
      let model =
        Model(..model, editor: Some(editor))
        |> refresh_anchor
        |> add_diagnostic("body text channel ready")
      #(
        model,
        effect.batch([
          effect.map(editor_effect, Editor),
          watershed_lustre.subscribe_text(text, BodyChanged),
        ]),
      )
    }
    EnsuredBody(Error(reason)) -> {
      let model = add_diagnostic(model, "body text channel failed · " <> reason)
      #(Model(..model, last_error: Some(reason)), effect.none())
    }

    // A text event fired (local or remote). The component re-renders itself off
    // its own subscription; this arm is the app's share of the same event — the
    // diagnostics trace and the pinned anchor's resolved position.
    BodyChanged(event) -> {
      let diagnostics = case model.doc {
        Some(doc) -> Some(watershed_js.diagnostics(doc))
        None -> None
      }
      let detail = case diagnostics {
        Some(diagnostics) ->
          event_line(event) <> " · " <> diagnostic_line(diagnostics)
        None -> event_line(event)
      }
      let model =
        Model(..model, diagnostics: diagnostics)
        |> refresh_anchor
        |> add_diagnostic(detail)
      #(model, effect.none())
    }

    DiagnosticsTick -> {
      let next = case model.doc {
        Some(doc) -> Some(watershed_js.diagnostics(doc))
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

    // The core of the demo, and now one line of routing: the component owns the
    // diff, the minimal op, and the rejected-index banner. Read
    // `textarea.value`/`length`/`error` off the returned model to see what it
    // did — no callbacks to plumb.
    Editor(inner) ->
      case model.editor {
        None -> #(model, effect.none())
        Some(editor) -> {
          let #(editor, editor_effect) = textarea.update(editor, inner)
          // Any message may have moved the caret, so this is where the cursor
          // gets broadcast. `announce_cursor` no-ops unless it actually moved:
          // re-anchoring after a remote edit yields the same anchor values when
          // the caret tracked the same content, so a peer typing does not make
          // every client re-announce.
          let #(model, announce) =
            announce_cursor(Model(..model, editor: Some(editor)))
          #(model, effect.batch([effect.map(editor_effect, Editor), announce]))
        }
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
              let #(editor, editor_effect) = textarea.set_peers(editor, cursors)
              #(
                Model(..model, editor: Some(editor)),
                effect.map(editor_effect, Editor),
              )
            }
          }
      }

    DraftAppendChanged(text) -> #(
      Model(..model, draft_append: text),
      effect.none(),
    )

    // The explicit append action — its own mutation family, distinct from the
    // insert the textarea diff would produce. Appends to the end regardless of
    // where the caret is.
    AppendClicked ->
      case model.editor, model.draft_append {
        _, "" -> #(model, effect.none())
        None, _ -> #(model, effect.none())
        Some(editor), value -> {
          // An edit the component does not own. It needs no notification: the
          // channel's own event re-snapshots the component a microtask later.
          let result = watershed_js.text_append(textarea.channel(editor), value)
          let model =
            Model(..model, draft_append: "")
            |> refresh_anchor
            |> record(result, "append")
          #(model, effect.none())
        }
      }

    // Pin an anchor at the current end of the text. As remote edits insert or
    // delete text before it, `text_resolve_anchor` reports its shifted grapheme
    // position — re-resolved on every snapshot.
    PinAnchorClicked ->
      case model.editor {
        None -> #(model, effect.none())
        Some(editor) -> {
          let text = textarea.channel(editor)
          let index = textarea.length(editor)
          case
            watershed_js.text_anchor_at(text, index, watershed_js.bias_before)
          {
            Ok(anchor) -> {
              let model =
                Model(..model, anchor: Some(anchor))
                |> refresh_anchor
                |> record(Ok(Nil), "anchor")
                |> add_diagnostic(
                  "anchor pinned at grapheme " <> int.to_string(index),
                )
              #(model, effect.none())
            }
            Error(reason) -> #(
              record(model, Error(reason), "anchor"),
              effect.none(),
            )
          }
        }
      }

    ClearAnchorClicked -> #(
      Model(..model, anchor: None, anchor_pos: None)
        |> add_diagnostic("anchor cleared"),
      effect.none(),
    )

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
    Some(editor) -> textarea.cursor(editor)
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

/// Fold the result of an app-owned mutation into the model: clear the banner on
/// success, surface the runtime's own message on failure. The component folds
/// its own edits the same way — see `current_error`.
fn record(model: Model, result: Result(Nil, String), verb: String) -> Model {
  case result {
    Ok(Nil) -> Model(..model, last_error: None)
    Error(reason) ->
      Model(..model, last_error: Some(verb <> " failed: " <> reason))
      |> add_diagnostic(verb <> " rejected · " <> reason)
  }
}

/// Resolve the pinned anchor to its current grapheme position, or drop it to
/// `None` if it has gone stale/unknown.
fn refresh_anchor(model: Model) -> Model {
  case model.editor, model.anchor {
    Some(editor), Some(anchor) ->
      case watershed_js.text_resolve_anchor(textarea.channel(editor), anchor) {
        Ok(pos) -> Model(..model, anchor_pos: Some(pos))
        Error(_) -> Model(..model, anchor_pos: None)
      }
    _, _ -> Model(..model, anchor_pos: None)
  }
}

/// The text's length in graphemes, or zero before the channel resolves.
fn text_length(model: Model) -> Int {
  case model.editor {
    Some(editor) -> textarea.length(editor)
    None -> 0
  }
}

/// The banner to show: a rejected keystroke from the component takes precedence
/// over an older app-owned failure.
fn current_error(model: Model) -> Option(String) {
  case model.editor {
    Some(editor) ->
      case textarea.error(editor) {
        Some(reason) -> Some(reason)
        None -> model.last_error
      }
    None -> model.last_error
  }
}

fn add_diagnostic(model: Model, line: String) -> Model {
  let tagged = "[" <> model.user_id <> "] " <> line
  io.println(tagged)
  Model(..model, diagnostic_log: take([tagged, ..model.diagnostic_log], 40))
}

fn take(items: List(a), count: Int) -> List(a) {
  case items, count {
    _, count if count <= 0 -> []
    [], _ -> []
    [first, ..rest], _ -> [first, ..take(rest, count - 1)]
  }
}

fn event_line(event: text_kernel.TextEvent) -> String {
  case event {
    text_kernel.TextChanged(value) ->
      "textChanged length=" <> int.to_string(string.length(value))
  }
}

fn diagnostic_line(diagnostics: watershed_js.Diagnostics) -> String {
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
  <> bool_string(diagnostics.synced)
}

fn option_int(value: Option(Int)) -> String {
  value
  |> option.map(int.to_string)
  |> option.unwrap("none")
}

fn bool_string(b: Bool) -> String {
  case b {
    True -> "true"
    False -> "false"
  }
}

// ── View ─────────────────────────────────────────────────────────────────────

fn view(model: Model) -> Element(Msg) {
  html.main([class("wrap")], [
    html.h1([], [html.text("watershed · collaborative text")]),
    status_line(model),
    editor_view(model),
    error_view(model),
    append_view(model),
    anchor_view(model),
    diagnostics_view(model),
    html.p([class("hint")], [
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
  html.p([class("status")], [
    html.text(
      connection
      <> runtime
      <> " · "
      <> int.to_string(text_length(model))
      <> " graphemes",
    ),
  ])
}

/// All that is left of the editor here: presentation, plus the `element.map`
/// that lifts the component's messages into this app's `Msg`. The attributes
/// are the caller's to choose; the value binding and the input handler are the
/// component's.
fn editor_view(model: Model) -> Element(Msg) {
  case model.editor {
    Some(editor) ->
      textarea.view(editor, [
        class("editor"),
        rows(10),
        placeholder("Start typing — every keystroke is one grapheme op…"),
        attribute.attribute("aria-label", "collaborative document body"),
      ])
      |> element.map(Editor)

    None ->
      html.textarea(
        [
          class("editor"),
          rows(10),
          placeholder("connecting…"),
          attribute.attribute("aria-label", "collaborative document body"),
          disabled(True),
        ],
        "",
      )
  }
}

fn append_view(model: Model) -> Element(Msg) {
  html.div([class("compose")], [
    html.input([
      placeholder("Text to append (try an emoji 🌊 or accent é)"),
      value(model.draft_append),
      event.on_input(DraftAppendChanged),
      attribute.attribute("aria-label", "text to append"),
    ]),
    html.button(
      [event.on_click(AppendClicked), disabled(model.draft_append == "")],
      [html.text("Append")],
    ),
    html.button([event.on_click(ReconnectClicked)], [
      html.text("Force reconnect"),
    ]),
  ])
}

fn error_view(model: Model) -> Element(Msg) {
  html.p([class("error"), attribute.attribute("role", "alert")], [
    html.text(option.unwrap(current_error(model), "")),
  ])
}

fn anchor_view(model: Model) -> Element(Msg) {
  let detail = case model.anchor, model.anchor_pos {
    Some(_), Some(pos) ->
      "pinned · resolves to grapheme "
      <> int.to_string(pos)
      <> " of "
      <> int.to_string(text_length(model))
    Some(_), None -> "pinned · anchor target is currently unresolvable"
    None, _ -> "no anchor pinned"
  }
  html.section([class("anchor")], [
    html.h2([], [html.text("Pinned anchor")]),
    html.p([], [
      html.text(
        "Pin an anchor at the end of the text, then edit from another tab "
        <> "before it — its resolved position moves with the content.",
      ),
    ]),
    html.p([class("anchor-detail")], [html.text(detail)]),
    html.div([class("compose")], [
      html.button(
        [event.on_click(PinAnchorClicked), disabled(model.editor == None)],
        [html.text("Pin anchor at end")],
      ),
      html.button(
        [event.on_click(ClearAnchorClicked), disabled(model.anchor == None)],
        [html.text("Clear anchor")],
      ),
    ]),
  ])
}

fn diagnostics_view(model: Model) -> Element(Msg) {
  let current = case model.diagnostics {
    Some(diagnostics) -> diagnostic_line(diagnostics)
    None -> "runtime diagnostics unavailable"
  }
  let log = model.diagnostic_log |> string.join("\n")
  html.section([class("diagnostics")], [
    html.h2([], [html.text("Diagnostics")]),
    html.p([], [
      html.text(
        "Compare this panel across tabs. Browser DevTools receives the same trace.",
      ),
    ]),
    html.pre([class("diagnostic-current")], [html.text(current)]),
    html.pre([class("diagnostic-log")], [html.text(log)]),
  ])
}
