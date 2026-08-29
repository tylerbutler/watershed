//// The collaborative text editor as a nested MVU triple.
////
//// This is the demo minus the things an *application* owns. Connecting,
//// diagnostics, presence, and the page around it belong to whoever mounts
//// this; what lives here is the editor and the document state behind it —
//// bootstrapping the body channel, the append action, and the pinned anchor.
////
//// The contract is `watershed_lustre/textarea`'s, one level up:
////
//// ```gleam
//// // in the parent's update, once the child map is in hand:
//// PanelOpened -> {
////   let #(panel, panel_effect) = component.init(doc, text_map)
////   #(Model(..model, text: Some(panel)), effect.map(panel_effect, TextMsg))
//// }
//// TextMsg(inner) -> {
////   let #(panel, panel_effect) = component.update(panel, inner)
////   #(Model(..model, text: Some(panel)), effect.map(panel_effect, TextMsg))
//// }
////
//// // in the parent's view:
//// component.view(panel) |> element.map(TextMsg)
//// ```
////
//// There are no callbacks to plumb: every message passes through the parent's
//// `update`, so read [`length`](#length), [`error`](#error), and
//// [`cursor`](#cursor) off the model after each call.
////
//// **`init` takes a `TypedMap(TextDoc)`, never a `Document`'s root.** The map
//// is the editor's whole world — standalone it happens to *be* the root, and
//// composed it is a child of a showcase root, and nothing in here can tell the
//// difference. That is what makes the same code a whole app and a panel in
//// one. The `Document` parameter is only what `ensure_text` needs to attach a
//// channel; it is never used to reach the root.
////
//// Peers arrive from above via [`set_peers`](#set_peers) rather than from a
//// presence driver started in here. A driver is document-scoped — two panels
//// each starting one would receive each other's envelopes — so the owner of
//// the document owns the driver, and this component is handed the result.

import gleam/int
import gleam/option.{type Option, None, Some}

import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import watershed.{type Document, type SharedText, type TextAnchor, type TypedMap}
import watershed/text_kernel
import watershed_lustre
import watershed_lustre/textarea

import text_lustre/doc_schema

// ── Model ────────────────────────────────────────────────────────────────────

pub opaque type Model {
  Model(
    /// The bound `<textarea>`. `None` until `ensure_text` resolves — the
    /// component is constructed with a live channel, never an empty one.
    editor: Option(textarea.Model),
    draft_append: String,
    anchor: Option(TextAnchor),
    anchor_pos: Option(Int),
    last_error: Option(String),
  )
}

pub opaque type Msg {
  EnsuredBody(Result(SharedText, String))
  BodyChanged(text_kernel.TextEvent)
  Editor(textarea.Msg)
  DraftAppendChanged(String)
  AppendClicked
  PinAnchorClicked
  ClearAnchorClicked
}

/// Seed the title and bootstrap the body text channel under `map`.
///
/// `ensure_text` creates and attaches a channel only if the slot is empty, so
/// every client runs this unconditionally without racing to a duplicate.
/// Attaching needs a ready connection, so the caller must not call this before
/// its handshake completes.
pub fn init(
  document: Document(root),
  map: TypedMap(doc_schema.TextDoc),
) -> #(Model, Effect(Msg)) {
  let model =
    Model(
      editor: None,
      draft_append: "",
      anchor: None,
      anchor_pos: None,
      last_error: None,
    )
  #(
    model,
    effect.batch([
      watershed_lustre.ensure_field(
        map,
        doc_schema.title(),
        "watershed shared document",
      ),
      watershed_lustre.ensure_text(
        document,
        map,
        doc_schema.body(),
        EnsuredBody,
      ),
    ]),
  )
}

// ── Update ───────────────────────────────────────────────────────────────────

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    // The body resolved: hand the live channel to the textarea, which
    // subscribes and takes its own first snapshot so a client joining an
    // existing document renders its text without waiting for an edit. The
    // second subscription here is this component's own — a channel fans out to
    // every subscriber — and keeps the pinned anchor resolved.
    EnsuredBody(Ok(text)) -> {
      let #(editor, editor_effect) = textarea.init(text)
      let model = Model(..model, editor: Some(editor)) |> refresh_anchor
      #(
        model,
        effect.batch([
          effect.map(editor_effect, Editor),
          watershed_lustre.subscribe_text(text, BodyChanged),
        ]),
      )
    }
    EnsuredBody(Error(reason)) -> #(
      Model(..model, last_error: Some(reason)),
      effect.none(),
    )

    // A text event fired (local or remote). The textarea re-renders itself off
    // its own subscription; this arm is the component's share of the same
    // event — the pinned anchor's resolved position.
    BodyChanged(_) -> #(refresh_anchor(model), effect.none())

    // The core of the demo, and one line of routing: the textarea owns the
    // diff, the minimal op, and the rejected-index banner.
    Editor(inner) ->
      case model.editor {
        None -> #(model, effect.none())
        Some(editor) -> {
          let #(editor, editor_effect) = textarea.update(editor, inner)
          #(
            Model(..model, editor: Some(editor)),
            effect.map(editor_effect, Editor),
          )
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
          // An edit the textarea does not own. It needs no notification: the
          // channel's own event re-snapshots it a microtask later.
          let result = watershed.text_append(textarea.channel(editor), value)
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
          case watershed.text_anchor_at(text, index, watershed.bias_before) {
            Ok(anchor) -> #(
              Model(..model, anchor: Some(anchor))
                |> refresh_anchor
                |> record(Ok(Nil), "anchor"),
              effect.none(),
            )
            Error(reason) -> #(
              record(model, Error(reason), "anchor"),
              effect.none(),
            )
          }
        }
      }

    ClearAnchorClicked -> #(
      Model(..model, anchor: None, anchor_pos: None),
      effect.none(),
    )
  }
}

/// Draw these peers' carets in the editor.
///
/// Whoever owns the document owns the presence driver; this takes the result.
/// A no-op until the body channel resolves.
pub fn set_peers(
  model: Model,
  peers: List(textarea.Peer),
) -> #(Model, Effect(Msg)) {
  case model.editor {
    None -> #(model, effect.none())
    Some(editor) -> {
      let #(editor, editor_effect) = textarea.set_peers(editor, peers)
      #(Model(..model, editor: Some(editor)), effect.map(editor_effect, Editor))
    }
  }
}

/// This client's caret, as a pair of anchors — what the owner broadcasts.
///
/// Anchors rather than indices, because an index means nothing to a peer whose
/// replica has moved on. They are value-comparable, and re-anchoring after a
/// remote edit yields the *same* anchors whenever the caret tracked the same
/// content, so an owner can compare against the last announced value and stay
/// quiet through a peer's typing.
pub fn cursor(model: Model) -> Option(textarea.Cursor) {
  case model.editor {
    Some(editor) -> textarea.cursor(editor)
    None -> None
  }
}

/// The text's length in graphemes, or zero before the channel resolves.
pub fn length(model: Model) -> Int {
  case model.editor {
    Some(editor) -> textarea.length(editor)
    None -> 0
  }
}

/// The banner to show: a rejected keystroke from the textarea takes precedence
/// over an older component-owned failure.
pub fn error(model: Model) -> Option(String) {
  case model.editor {
    Some(editor) ->
      case textarea.error(editor) {
        Some(reason) -> Some(reason)
        None -> model.last_error
      }
    None -> model.last_error
  }
}

/// The live channel, once it exists — for an owner that wants its own
/// subscription to the same events (a channel fans out to every subscriber).
pub fn channel(model: Model) -> Option(SharedText) {
  case model.editor {
    Some(editor) -> Some(textarea.channel(editor))
    None -> None
  }
}

/// Fold the result of a mutation into the model: clear the banner on success,
/// surface the runtime's own message on failure.
fn record(model: Model, result: Result(Nil, String), verb: String) -> Model {
  case result {
    Ok(Nil) -> Model(..model, last_error: None)
    Error(reason) ->
      Model(..model, last_error: Some(verb <> " failed: " <> reason))
  }
}

/// Resolve the pinned anchor to its current grapheme position, or drop it to
/// `None` if it has gone stale/unknown.
fn refresh_anchor(model: Model) -> Model {
  case model.editor, model.anchor {
    Some(editor), Some(anchor) ->
      case watershed.text_resolve_anchor(textarea.channel(editor), anchor) {
        Ok(pos) -> Model(..model, anchor_pos: Some(pos))
        Error(_) -> Model(..model, anchor_pos: None)
      }
    _, _ -> Model(..model, anchor_pos: None)
  }
}

// ── View ─────────────────────────────────────────────────────────────────────

pub fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("text-panel")], [
    editor_view(model),
    error_view(model),
    append_view(model),
    anchor_view(model),
  ])
}

/// All that is left of the editor here: presentation, plus the `element.map`
/// that lifts the textarea's messages into this component's `Msg`. The
/// attributes are the caller's to choose; the value binding and the input
/// handler are the textarea's.
fn editor_view(model: Model) -> Element(Msg) {
  case model.editor {
    Some(editor) ->
      textarea.view(editor, [
        attribute.class("editor"),
        attribute.rows(10),
        attribute.placeholder(
          "Start typing — every keystroke is one grapheme op…",
        ),
        attribute.attribute("aria-label", "collaborative document body"),
      ])
      |> element.map(Editor)

    None ->
      html.textarea(
        [
          attribute.class("editor"),
          attribute.rows(10),
          attribute.placeholder("connecting…"),
          attribute.attribute("aria-label", "collaborative document body"),
          attribute.disabled(True),
        ],
        "",
      )
  }
}

fn append_view(model: Model) -> Element(Msg) {
  html.div([attribute.class("compose")], [
    html.input([
      attribute.placeholder("Text to append (try an emoji 🌊 or accent é)"),
      attribute.value(model.draft_append),
      event.on_input(DraftAppendChanged),
      attribute.attribute("aria-label", "text to append"),
    ]),
    html.button(
      [
        event.on_click(AppendClicked),
        attribute.disabled(model.draft_append == ""),
      ],
      [html.text("Append")],
    ),
  ])
}

fn error_view(model: Model) -> Element(Msg) {
  html.p([attribute.class("error"), attribute.attribute("role", "alert")], [
    html.text(option.unwrap(error(model), "")),
  ])
}

fn anchor_view(model: Model) -> Element(Msg) {
  let detail = case model.anchor, model.anchor_pos {
    Some(_), Some(pos) ->
      "pinned · resolves to grapheme "
      <> int.to_string(pos)
      <> " of "
      <> int.to_string(length(model))
    Some(_), None -> "pinned · anchor target is currently unresolvable"
    None, _ -> "no anchor pinned"
  }
  html.section([attribute.class("anchor")], [
    html.h2([], [html.text("Pinned anchor")]),
    html.p([], [
      html.text(
        "Pin an anchor at the end of the text, then edit from another client "
        <> "before it — its resolved position moves with the content.",
      ),
    ]),
    html.p([attribute.class("anchor-detail")], [html.text(detail)]),
    html.div([attribute.class("compose")], [
      html.button(
        [
          event.on_click(PinAnchorClicked),
          attribute.disabled(model.editor == None),
        ],
        [html.text("Pin anchor at end")],
      ),
      html.button(
        [
          event.on_click(ClearAnchorClicked),
          attribute.disabled(model.anchor == None),
        ],
        [html.text("Clear anchor")],
      ),
    ]),
  ])
}
