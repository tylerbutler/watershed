//// Collaborative plain-text editor — a `SharedText` demo.
////
//// Where `playlist_lustre` exercises a `SharedSequence`'s ordered `move`, this
//// example exercises the one DDS whose edits are addressed by **grapheme index
//// into a live string**: `SharedText`. A `<textarea>` only ever reports its
//// whole new value on `input`, so the naïve bridge — write the whole string
//// back as one replace — clobbers every concurrent remote keystroke. Instead,
//// each `input` event is diffed against the channel's *current optimistic
//// value* ([`grapheme_diff`](grapheme_diff.gleam)), and exactly one minimal op
//// is sent:
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
//// Every mutation returns `Result(Nil, String)` — an index can go stale when a
//// peer edits between render and keystroke — and the app surfaces the runtime's
//// message in a banner rather than asserting.
////
//// A pinned **anchor** (`text_anchor_at`) tracks a stable position in the
//// document: as remote edits insert and delete text before it, its resolved
//// grapheme index moves with the content, which is the property that makes
//// shared cursors possible (though broadcasting them is out of scope here).
////
//// Open two browser tabs against the same `just server` document to watch edits
//// converge grapheme-for-grapheme.

import gleam/int
import gleam/io
import gleam/option.{type Option, None, Some}
import gleam/string

import lustre
import lustre/attribute.{class, disabled, placeholder, rows, value}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import watershed/text_kernel
import watershed_js.{type Document, type SharedText, type TextAnchor}
import watershed_lustre

import doc_schema
import grapheme_diff.{type Edit}

// ── Dev config for `just server` (levee dev mode) ────────────────────────────

const socket_url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

const document_id = "text"

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

type Model {
  Model(
    status: Status,
    doc: Option(Document),
    body_channel: Option(SharedText),
    user_id: String,
    text: String,
    length: Int,
    draft_append: String,
    anchor: Option(TextAnchor),
    anchor_pos: Option(Int),
    last_error: Option(String),
    diagnostics: Option(watershed_js.Diagnostics),
    diagnostic_log: List(String),
  )
}

type Msg {
  GotHandle(Document)
  Connected(Result(Nil, String))
  EnsuredBody(Result(SharedText, String))
  BodyChanged(text_kernel.TextEvent)
  DiagnosticsTick
  InputChanged(String)
  DraftAppendChanged(String)
  AppendClicked
  PinAnchorClicked
  ClearAnchorClicked
  ReconnectClicked
}

fn init(_args) -> #(Model, Effect(Msg)) {
  // A distinct user per tab so the two clients are separate connections.
  let user_id = "web-" <> int.to_string(1000 + int.random(9000))
  let model =
    Model(
      status: Connecting,
      doc: None,
      body_channel: None,
      user_id: user_id,
      text: "",
      length: 0,
      draft_append: "",
      anchor: None,
      anchor_pos: None,
      last_error: None,
      diagnostics: None,
      diagnostic_log: [],
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

// ── Update ───────────────────────────────────────────────────────────────────

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    // The handle is ready: seed the title and bootstrap the body text channel.
    // `ensure_text` creates and attaches one only if the slot is empty, so
    // every tab runs this unconditionally without racing to a duplicate — the
    // property that makes joiners converge on the *same* document.
    GotHandle(doc) -> {
      let diagnostics = watershed_js.diagnostics(doc)
      let root = watershed_js.root_typed(doc)
      let model =
        Model(..model, doc: Some(doc), diagnostics: Some(diagnostics))
        |> add_diagnostic(
          "document handle acquired · " <> diagnostic_line(diagnostics),
        )
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
          watershed_lustre.after(250, DiagnosticsTick),
        ]),
      )
    }

    Connected(Ok(_)) -> {
      let model =
        snapshot(Model(..model, status: Ready))
        |> add_diagnostic("initial handshake complete")
      #(model, effect.none())
    }
    Connected(Error(reason)) -> {
      let model =
        Model(..model, status: Failed(reason))
        |> add_diagnostic("connection failed · " <> reason)
      #(model, effect.none())
    }

    // The body resolved: subscribe, then take a first snapshot so a tab joining
    // an existing document renders its text without waiting for an edit.
    EnsuredBody(Ok(text)) -> {
      let model =
        snapshot(Model(..model, body_channel: Some(text)))
        |> add_diagnostic("body text channel ready")
      #(model, watershed_lustre.subscribe_text(text, BodyChanged))
    }
    EnsuredBody(Error(reason)) -> {
      let model = add_diagnostic(model, "body text channel failed · " <> reason)
      #(Model(..model, last_error: Some(reason)), effect.none())
    }

    // A text event fired (local or remote). `TextChanged` carries the full
    // post-edit optimistic string, but we re-read the channel anyway so the
    // rendered value and the anchor position always reflect committed state.
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
        snapshot(Model(..model, diagnostics: diagnostics))
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

    // The core of the demo. The textarea handed us its *whole* new value; diff
    // it against the channel's current optimistic string and send exactly one
    // minimal op — never a whole-document replace, never a UTF-16 offset.
    InputChanged(new_value) ->
      case model.body_channel {
        None -> #(model, effect.none())
        Some(text) -> {
          let current = watershed_js.text_value(text)
          let edit = grapheme_diff.diff(old: current, new: new_value)
          let result = apply_edit(text, edit)
          let model = snapshot(model) |> record(result, edit_verb(edit))
          #(model, effect.none())
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
      case model.body_channel, model.draft_append {
        _, "" -> #(model, effect.none())
        None, _ -> #(model, effect.none())
        Some(text), value -> {
          let result = watershed_js.text_append(text, value)
          let model =
            snapshot(Model(..model, draft_append: ""))
            |> record(result, "append")
          #(model, effect.none())
        }
      }

    // Pin an anchor at the current end of the text. As remote edits insert or
    // delete text before it, `text_resolve_anchor` reports its shifted grapheme
    // position — re-resolved on every snapshot.
    PinAnchorClicked ->
      case model.body_channel {
        None -> #(model, effect.none())
        Some(text) -> {
          let index = watershed_js.text_length(text)
          case
            watershed_js.text_anchor_at(text, index, watershed_js.bias_before)
          {
            Ok(anchor) -> {
              let model =
                snapshot(Model(..model, anchor: Some(anchor)))
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

/// Run a computed `Edit` against the resolved channel as one minimal op.
fn apply_edit(text: SharedText, edit: Edit) -> Result(Nil, String) {
  case edit {
    grapheme_diff.NoChange -> Ok(Nil)
    grapheme_diff.Insert(index, value) ->
      watershed_js.text_insert(text, index, value)
    grapheme_diff.Delete(start, end) ->
      watershed_js.text_delete_range(text, start, end)
    grapheme_diff.Replace(start, end, value) ->
      watershed_js.text_replace_range(text, start, end, value)
  }
}

fn edit_verb(edit: Edit) -> String {
  case edit {
    grapheme_diff.NoChange -> "noop"
    grapheme_diff.Insert(..) -> "insert"
    grapheme_diff.Delete(..) -> "delete"
    grapheme_diff.Replace(..) -> "replace"
  }
}

/// Fold an edit result into the model: clear the banner on success, surface the
/// runtime's own message on failure.
fn record(model: Model, result: Result(Nil, String), verb: String) -> Model {
  case result {
    Ok(Nil) -> Model(..model, last_error: None)
    Error(reason) ->
      Model(..model, last_error: Some(verb <> " failed: " <> reason))
      |> add_diagnostic(verb <> " rejected · " <> reason)
  }
}

/// Re-read the optimistic text and re-resolve the pinned anchor into the model.
fn snapshot(model: Model) -> Model {
  case model.body_channel {
    None -> model
    Some(text) ->
      Model(
        ..model,
        text: watershed_js.text_value(text),
        length: watershed_js.text_length(text),
      )
      |> refresh_anchor
  }
}

/// Resolve the pinned anchor to its current grapheme position, or drop it to
/// `None` if it has gone stale/unknown.
fn refresh_anchor(model: Model) -> Model {
  case model.body_channel, model.anchor {
    Some(text), Some(anchor) ->
      case watershed_js.text_resolve_anchor(text, anchor) {
        Ok(pos) -> Model(..model, anchor_pos: Some(pos))
        Error(_) -> Model(..model, anchor_pos: None)
      }
    _, _ -> Model(..model, anchor_pos: None)
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
      <> int.to_string(model.length)
      <> " graphemes",
    ),
  ])
}

fn editor_view(model: Model) -> Element(Msg) {
  html.textarea(
    [
      class("editor"),
      rows(10),
      placeholder("Start typing — every keystroke is one grapheme op…"),
      event.on_input(InputChanged),
      attribute.attribute("aria-label", "collaborative document body"),
      disabled(model.body_channel == None),
    ],
    model.text,
  )
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
    html.text(option.unwrap(model.last_error, "")),
  ])
}

fn anchor_view(model: Model) -> Element(Msg) {
  let detail = case model.anchor, model.anchor_pos {
    Some(_), Some(pos) ->
      "pinned · resolves to grapheme "
      <> int.to_string(pos)
      <> " of "
      <> int.to_string(model.length)
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
        [event.on_click(PinAnchorClicked), disabled(model.body_channel == None)],
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
