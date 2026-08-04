//// A `<textarea>` bound to a [`SharedText`](watershed_js) channel.
////
//// Wiring a textarea to a text CRDT looks trivial and isn't. The `input` event
//// hands you the *whole* new value, so the naïve bridge writes it back as one
//// replace-the-document op — which clobbers every concurrent remote keystroke.
//// The fix is to diff against the channel's current optimistic value and send
//// the one minimal op the keystroke implies, addressed in grapheme clusters
//// rather than the UTF-16 offsets the browser reports. Then, because the
//// runtime can reject a stale index when a peer edits between render and
//// keystroke, every write needs its `Result` folded somewhere the user can see
//// it. And because a remote edit rewrites the element's value out from under
//// whoever is typing, the caret has to be re-derived from a position that
//// tracked that edit — the browser's own offset points into a string that no
//// longer exists. This module owns all of that so an app doesn't rediscover it.
////
//// It is a nested MVU triple, not a custom element: `init` takes the live
//// channel handle, which cannot cross a custom-element property boundary
//// without an unsafe coercion. The parent holds the child model and routes
//// messages through it:
////
//// ```gleam
//// // update, once `ensure_text` has resolved:
//// EnsuredBody(Ok(channel)) -> {
////   let #(editor, fx) = textarea.init(channel)
////   #(Model(..model, editor: Some(editor)), effect.map(fx, Editor))
//// }
//// Editor(inner) -> {
////   let #(editor, fx) = textarea.update(editor, inner)
////   #(Model(..model, editor: Some(editor)), effect.map(fx, Editor))
//// }
////
//// // view:
//// textarea.view(editor, [rows(10), class("editor")]) |> element.map(Editor)
//// ```
////
//// There are no `on_change`/`on_error` callbacks to plumb: every message
//// already passes through the parent's `update`, so read [`value`](#value),
//// [`length`](#length), [`error`](#error), and [`selection`](#selection) off
//// the model after each call.
////
//// The parent may keep editing the channel directly — `text_append`, or any
//// other mutation — without telling the component. The subscription delivers
//// local edits too, so the next `TextChanged` re-snapshots the model.
////
//// ## How the caret survives a remote edit
////
//// The component holds the user's selection as a pair of `TextAnchor`s rather
//// than as offsets. An anchor binds to *content*, so when a peer inserts or
//// deletes text the anchor moves with the characters around it; resolving it
//// afterwards gives the grapheme index the caret should now be at. The
//// component converts that back to UTF-16 and writes it into the element from
//// `effect.before_paint`, which runs after the vdom has patched the value and
//// before the browser paints — so the caret never visibly jumps.
////
//// Two judgment calls are baked in, noted here so they aren't relitigated per
//// bug report. A **collapsed caret** hangs off the preceding grapheme at both
//// ends, so a remote insert exactly at the caret leaves the user's typing
//// position before the inserted text. A **range** hugs its content — head
//// biased `Before`, tail `After` — so an insert at either edge lands outside
//// the selection while an interior edit grows or shrinks it. This matches
//// ProseMirror and Yjs association conventions.
////
//// Local typing needs no restoration at all: the browser has already placed
//// the caret, and the snapshot the component renders is the same string the
//// element already holds, so the vdom write is a no-op. Restoration runs only
//// when the rendered value actually changes underneath the element.
////
//// Restoration is also skipped when the element is not focused — stealing
//// focus to place a caret is worse than losing the position. The anchors keep
//// tracking regardless, but note that a blurred element retains the offsets
//// the browser last had, so a remote edit that lands while the user is
//// elsewhere leaves the *browser's* caret stale until they next place it.
////
//// ## How an IME composition survives a remote edit
////
//// Typing 拼音 or かな runs a *composition session*: the browser puts provisional
//// text in the element and fires `input` for each intermediate, none of which
//// is an edit the document should see. Worse, writing to the element's `value`
//// mid-session cancels the session outright in most browsers — so a controlled
//// textarea re-rendering a peer's keystroke would destroy whatever the user was
//// in the middle of composing.
////
//// So for the duration of a session the component renders the textarea with no
//// value binding at all, and remembers the string the element held when the
//// session opened. Merely holding that string still would not be enough: Lustre
//// classes a textarea that has dispatched events as *controlled* and re-applies
//// its `value` on every diff, changed or not, so any re-render during a session
//// would overwrite the provisional text whatever value the component picked.
//// Dropping the binding leaves the vdom nothing to re-apply and the element to
//// the IME. The channel goes on applying remote edits and the model goes on
//// snapshotting them — only the element is held back.
////
//// Committing at `compositionend` therefore means diffing the element's final
//// value against that frozen base, which yields the composed edit in the
//// coordinates of a document several remote keystrokes out of date. A second
//// anchor, pinned at the caret when the session opened, measures how far the
//// composition site drifted; [`grapheme_diff.shift`](./grapheme_diff.html#shift)
//// carries the edit that far, and it lands as one op.
////
//// Two v1 limitations, documented rather than papered over. A remote edit
//// landing *inside* the region being composed over can interleave oddly — the
//// CRDT still converges, but the local visual during that window is
//// best-effort. And a browser that reports a stale value at `compositionend`
//// commits a partial composition; the next `input` event diffs the remainder,
//// so the document still catches up. Mature collaborative editors ship the same
//// trade.

import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

import lustre/attribute.{type Attribute}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import watershed/text_kernel
import watershed_js.{type SharedText, type TextAnchor}

import watershed_lustre
import watershed_lustre/grapheme_diff.{type Edit}
import watershed_lustre/grapheme_offset

@external(javascript, "./textarea_ffi.mjs", "restore_selection")
fn restore_selection(
  root: Dynamic,
  instance: String,
  start: Int,
  end: Int,
) -> Nil

/// The attribute the caret restorer finds the element by. Stamped after the
/// caller's attributes, so it cannot be overridden.
const instance_attribute = "data-watershed-textarea"

/// What a caret decoder yields when the element reported no selection at all.
/// Distinct from `0`, which is a real caret at the head of the document.
const unknown_caret = -1

/// The component's state: the channel it is bound to, the optimistic snapshot
/// the view renders, the anchored selection, and the last rejected edit.
pub opaque type Model {
  Model(
    channel: SharedText,
    /// Stamped into the DOM so caret restoration can find *this* element among
    /// however many instances an app renders.
    instance: String,
    value: String,
    length: Int,
    selection: Option(Selection),
    /// The IME session in flight, if any. While this is `Some` the view renders
    /// its frozen value instead of `value`, and user input is left alone.
    composing: Option(Composition),
    /// The value the element held at the last composition commit.
    ///
    /// Browsers disagree on whether `input` fires before or after
    /// `compositionend`; the ones that fire it after report this same value a
    /// moment later. Diffing it again would re-apply the composition and, when
    /// a peer edited during the session, undo their work — the channel has
    /// moved on but the element has not been repainted yet. Suppressing exactly
    /// one echo is safe: any real keystroke produces a different value.
    committed: Option(String),
    error: Option(String),
  )
}

/// An IME session in flight.
type Composition {
  Composition(
    /// The element's value when the session opened — what the view keeps
    /// rendering, so the vdom never writes to the element and cancels the
    /// session, and what the final value is diffed against to recover the
    /// composed edit.
    frozen: String,
    /// Where the caret sat when the session opened, in graphemes into `frozen`.
    origin: Int,
    /// The same position, but tracking content, so a remote edit during the
    /// session can be measured. `None` if the runtime would not name that
    /// position: the session still runs, just without drift correction.
    site: Option(TextAnchor),
  )
}

/// The user's selection, held as content-bound anchors plus the two coordinate
/// systems it has to be readable in: grapheme indices for callers and the CRDT,
/// UTF-16 offsets for the element.
type Selection {
  Selection(
    start: TextAnchor,
    end: TextAnchor,
    /// Where the anchors resolved as of the last snapshot.
    range: #(Int, Int),
    /// The same position in the code units the element speaks — what gets
    /// written back on restore, and what an incoming selection event is
    /// compared against to skip redundant re-anchoring.
    raw: #(Int, Int),
  )
}

pub opaque type Msg {
  /// The channel changed — locally or remotely. Carries the post-edit string,
  /// but the model re-reads the channel anyway so what renders is always
  /// committed optimistic state rather than an event payload.
  KernelEvent(text_kernel.TextEvent)
  /// The user typed. Carries the textarea's whole new value and the caret it
  /// left behind, in UTF-16 code units.
  UserInput(value: String, sel_start: Int, sel_end: Int)
  /// The user moved the caret or changed the selection without editing.
  UserSelect(sel_start: Int, sel_end: Int)
  /// An IME session opened. Carries the element's value and caret as they stood
  /// before any provisional text was inserted.
  CompositionStarted(value: String, sel_start: Int, sel_end: Int)
  /// An IME session committed. Carries the element's final value and caret.
  CompositionEnded(value: String, sel_start: Int, sel_end: Int)
}

/// Bind a resolved text channel. Subscribes to it and takes the first snapshot,
/// so a tab joining an existing document renders its text immediately rather
/// than waiting for the first edit.
///
/// The channel is taken resolved, not as an `Option`: construct the component
/// at the `ensure_text` callback, so the model never carries an empty channel
/// and the view never renders a disabled ghost. Render whatever placeholder you
/// like before that moment.
pub fn init(channel: SharedText) -> #(Model, Effect(Msg)) {
  let model =
    snapshot(Model(
      channel:,
      instance: new_instance(),
      value: "",
      length: 0,
      selection: None,
      composing: None,
      committed: None,
      error: None,
    ))

  #(model, watershed_lustre.subscribe_text(channel, KernelEvent))
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    // Any edit, from anywhere: re-read rather than trust the payload.
    KernelEvent(_) -> {
      let rendered = model.value
      let model = snapshot(model)
      case model.composing {
        // The element belongs to the IME until the session commits. The model
        // still tracks the channel — it is authoritative, and the anchors have
        // to keep moving with the content — but the view goes on rendering the
        // frozen value and no caret is written. Doing either here would cancel
        // the composition the user is in the middle of.
        Some(_) -> #(resolve(model), effect.none())
        None -> settle(model, rendered)
      }
    }

    // The textarea handed over its whole new value.
    UserInput(value:, sel_start:, sel_end:) ->
      case model.composing, model.committed {
        // Provisional IME text, not an edit. The session owns the element until
        // it commits, and every intermediate it produces is superseded by the
        // next one.
        Some(_), _ -> #(model, effect.none())

        // The echo of a commit this component already applied — see `committed`.
        // Diffing it would re-apply the composition against a channel that has
        // moved on, undoing any remote edit made during the session.
        None, Some(committed) if committed == value -> #(
          Model(..model, committed: None),
          effect.none(),
        )

        // Diff against the channel's current optimistic string and send exactly
        // one minimal op.
        None, _ -> {
          let model = Model(..model, committed: None)
          let current = watershed_js.text_value(model.channel)
          let edit = grapheme_diff.diff(old: current, new: value)
          let result = apply(model.channel, edit)

          // Snapshot *after* applying: on success this is the text the user
          // just typed, and on a rejected index it snaps the textarea back to
          // the truth the runtime kept. Either way the local kernel event that
          // follows re-snapshots to the same string, so that write is a no-op.
          let model = record(snapshot(model), result, edit)

          // Re-anchor against the string the *browser* holds, which is the one
          // the reported offsets index into. It is the snapshot too, unless the
          // op was rejected — the one case where the two disagree.
          let model = anchor(model, value, sel_start, sel_end)

          case model.value == value {
            // Accepted: the browser already placed the caret and is rendering
            // the same string the model is. Nothing to restore.
            True -> #(model, effect.none())
            // Rejected: the view is about to snap back to the runtime's text,
            // so the caret needs placing in it.
            False -> #(model, restore(model))
          }
        }
      }

    UserSelect(sel_start:, sel_end:) ->
      case model.composing {
        // Caret moves inside an active composition are the IME walking its own
        // provisional text; those offsets index a string the document has never
        // seen, so anchoring from them would put the caret nowhere real.
        Some(_) -> #(model, effect.none())
        None -> #(anchor(model, model.value, sel_start, sel_end), effect.none())
      }

    // An IME session opened. Freeze what the view renders at the value the
    // element holds right now, so remote edits stop reaching the DOM, and pin
    // the site so their effect can still be accounted for at commit time.
    CompositionStarted(value:, sel_start:, ..) -> {
      let origin =
        int.clamp(
          grapheme_offset.from_utf16(value, int.max(sel_start, 0)),
          min: 0,
          max: model.length,
        )
      // The same association convention as a collapsed caret: attached to the
      // preceding grapheme, so a remote insert at the site leaves the composed
      // text before it rather than after.
      let site =
        watershed_js.text_anchor_at(
          model.channel,
          origin,
          watershed_js.bias_after,
        )

      #(
        Model(
          ..model,
          composing: Some(Composition(
            frozen: value,
            origin:,
            site: option.from_result(site),
          )),
          committed: None,
        ),
        effect.none(),
      )
    }

    // The session committed. Everything the user composed is the difference
    // between the frozen base and the element's final value.
    CompositionEnded(value:, sel_start:, sel_end:) ->
      case model.composing {
        // No session to close — a stray event, or one whose `compositionstart`
        // never decoded. Fall through to the ordinary input path so the text is
        // not silently dropped.
        None -> update(model, UserInput(value:, sel_start:, sel_end:))

        Some(composition) -> {
          // Measured once, before the op lands: applying the composition can
          // move or delete the very grapheme the site is anchored to, so a
          // second reading afterwards would answer a different question.
          let shift = drift(model, composition)
          let edit = grapheme_diff.diff(old: composition.frozen, new: value)
          let result =
            apply(model.channel, grapheme_diff.shift(edit, by: shift))

          // Unfreeze: from here the view renders the channel again.
          let model =
            Model(..model, composing: None, committed: Some(value))
            |> snapshot
            |> record(result, edit)

          // The reported offsets index `value`, which predates any remote edit
          // that landed during the session — so they need the same correction
          // the edit did. When the element reports nothing, fall back to
          // resolving the anchors, which are already in the right coordinates.
          let model = case sel_start < 0 || sel_end < 0 {
            True -> resolve(model)
            False ->
              pin(
                model,
                grapheme_offset.from_utf16(value, sel_start) + shift,
                grapheme_offset.from_utf16(value, sel_end) + shift,
              )
          }

          // The rendered value just went from frozen to live, so the vdom is
          // about to write the element and reset its caret to the end.
          #(model, restore(model))
        }
      }
  }
}

/// How far the composition site travelled while the session was open, in
/// graphemes. Zero when the site could not be anchored or no longer resolves —
/// the composed text then lands where it was typed, which is right whenever no
/// peer edited before it, and the CRDT converges either way.
fn drift(model: Model, composition: Composition) -> Int {
  case composition.site {
    None -> 0
    Some(site) ->
      case watershed_js.text_resolve_anchor(model.channel, site) {
        Ok(now) -> now - composition.origin
        Error(_) -> 0
      }
  }
}

/// Fold a fresh snapshot into the view: restore the caret only when the text
/// actually moved under the element.
fn settle(model: Model, rendered: String) -> #(Model, Effect(Msg)) {
  case model.value == rendered {
    // The ordinary case for a local keystroke: the channel is echoing text the
    // model already rendered, so the vdom write is a no-op and the browser's
    // own caret is exactly where the user put it. Touching the selection here
    // would be fighting them for it.
    True -> #(model, effect.none())
    // The text moved under the element. The anchors moved with it, so resolve
    // them and put the caret back before the browser paints.
    False -> {
      let model = resolve(model)
      #(model, restore(model))
    }
  }
}

/// A controlled `<textarea>` bound to the channel.
///
/// Caller attributes are applied first and the component's own last, so
/// presentation — `rows`, `placeholder`, `class`, `disabled`, ARIA — is yours
/// to set, while the value binding, the instance marker, and the event handlers
/// always win. `class` and `style` merge rather than replace, so a caller class
/// is additive.
pub fn view(model: Model, attrs: List(Attribute(Msg))) -> Element(Msg) {
  let bindings =
    list.append(attrs, [
      attribute.attribute(instance_attribute, model.instance),
      event.on("input", input_decoder()),
      // Caret-only moves. `selectionchange` on the element would be one
      // listener instead of four, but its bubbling behaviour is inconsistent
      // enough across browsers that this set is the conservative choice: it
      // covers keyboard navigation, mouse selection, and arriving by click or
      // tab. Redundant reads cost one comparison — see `anchor`.
      event.on("select", select_decoder()),
      event.on("keyup", select_decoder()),
      event.on("mouseup", select_decoder()),
      event.on("focus", select_decoder()),
      // An IME session brackets its provisional text with these.
      event.on("compositionstart", value_decoder(CompositionStarted)),
      event.on("compositionend", value_decoder(CompositionEnded)),
    ])

  case model.composing {
    None -> html.textarea(bindings, model.value)

    // Mid-composition the element is rendered with **no value binding at all**.
    //
    // Holding the bound string still is not enough. Lustre classes a textarea
    // that has dispatched events as *controlled*, and a controlled element has
    // its `value` property re-applied on every diff whether or not the string
    // changed — that is what stops a model and a DOM node drifting apart. It
    // also means any re-render at all during a composition would write over the
    // IME's provisional text and cancel the session, no matter what value the
    // component chose to render.
    //
    // Dropping the property is what actually gets the vdom to keep its hands
    // off: there is nothing left for it to re-apply. Removing it is safe —
    // `value` is a property here, so the reconciler's removal path clears the
    // *content attribute* of that name, which a textarea does not use, and
    // leaves the live value alone. The child text node stays pinned at the
    // frozen string so it too produces no patch, and it could not affect the
    // display anyway: the element went dirty the first time Lustre assigned to
    // `.value`.
    //
    // At `compositionend` the binding comes back, the vdom writes the channel's
    // text in one go, and `restore` puts the caret where the anchors say.
    Some(composition) ->
      element.element("textarea", bindings, [element.text(composition.frozen)])
  }
}

// ── Accessors ────────────────────────────────────────────────────────────────

/// The optimistic text the component is currently rendering.
pub fn value(model: Model) -> String {
  model.value
}

/// The channel's length in grapheme clusters — not code units, and not what
/// `string.length` on the rendered value would tell you about surrogate pairs.
pub fn length(model: Model) -> Int {
  model.length
}

/// The last edit the runtime rejected, cleared by the next one it accepts. A
/// rejection means a peer moved the text under an index this client had already
/// computed; the model has re-snapshotted, so the state is consistent — this is
/// for telling the user why their keystroke did not land.
pub fn error(model: Model) -> Option(String) {
  model.error
}

/// The user's current selection as a half-open grapheme range, or `None` before
/// they have placed a caret (or after a remote edit deleted the content both
/// ends were anchored to). A collapsed caret is a range whose ends are equal.
///
/// These are CRDT indices, so they are directly broadcastable: this is the
/// read a shared-cursor overlay wants.
pub fn selection(model: Model) -> Option(#(Int, Int)) {
  option.map(model.selection, fn(selection) { selection.range })
}

/// The channel the component is bound to, for edits it does not own —
/// `text_append`, anchors, or anything else on `watershed_js`. Mutating it
/// directly is safe: the subscription re-snapshots the model.
pub fn channel(model: Model) -> SharedText {
  model.channel
}

// ── Event decoding ───────────────────────────────────────────────────────────

fn input_decoder() -> Decoder(Msg) {
  value_decoder(UserInput)
}

/// The element's whole value plus the caret it left behind — what `input` and
/// both composition events all report.
fn value_decoder(to_msg: fn(String, Int, Int) -> Msg) -> Decoder(Msg) {
  use value <- decode.subfield(["target", "value"], decode.string)
  use sel_start <- decode.then(caret("selectionStart"))
  use sel_end <- decode.then(caret("selectionEnd"))

  decode.success(to_msg(value, sel_start, sel_end))
}

fn select_decoder() -> Decoder(Msg) {
  use sel_start <- decode.then(caret("selectionStart"))
  use sel_end <- decode.then(caret("selectionEnd"))

  decode.success(UserSelect(sel_start:, sel_end:))
}

/// One edge of the element's selection, in UTF-16 code units.
///
/// Deliberately total. Lustre drops an event whose decoder fails, so an element
/// that reports no selection — or reports it as `null` — would cost the user a
/// keystroke rather than an anchor refresh. Falling back to `unknown_caret`
/// keeps the edit and skips the re-anchor.
fn caret(name: String) -> Decoder(Int) {
  decode.optionally_at(
    ["target", name],
    unknown_caret,
    decode.one_of(decode.int, or: [decode.success(unknown_caret)]),
  )
}

// ── Selection tracking ───────────────────────────────────────────────────────

/// Re-anchor from the offsets an element reported, read against `text` — the
/// string those offsets index into, which is not always the one the model holds.
fn anchor(model: Model, text: String, sel_start: Int, sel_end: Int) -> Model {
  case sel_start < 0 || sel_end < 0 {
    // No selection reported. Keep the anchors already held rather than pin one
    // somewhere the user never put a caret.
    True -> model
    False ->
      case model.selection {
        // `select`, `keyup`, and `mouseup` all fire for a single interaction.
        // Anchoring is cheap but not free, and the first read already produced
        // the anchors the rest would.
        Some(selection) if selection.raw == #(sel_start, sel_end) -> model
        _ ->
          pin(
            model,
            grapheme_offset.from_utf16(text, sel_start),
            grapheme_offset.from_utf16(text, sel_end),
          )
      }
  }
}

/// Resolve the held anchors against the channel's current text and re-pin at
/// wherever they have travelled to.
fn resolve(model: Model) -> Model {
  case model.selection {
    None -> model
    Some(selection) ->
      case
        watershed_js.text_resolve_anchor(model.channel, selection.start),
        watershed_js.text_resolve_anchor(model.channel, selection.end)
      {
        Ok(start), Ok(end) -> pin(model, start, end)
        // One edge's grapheme was deleted out from under it. Collapse onto the
        // edge that survived rather than guess where the range went.
        Ok(index), Error(_) | Error(_), Ok(index) -> pin(model, index, index)
        // Both edges gone: there is no honest position left, so drop the
        // selection and leave the browser whatever caret it has.
        Error(_), Error(_) -> Model(..model, selection: None)
      }
  }
}

/// Pin fresh anchors at a grapheme range, clamped into the current text, and
/// record the range in both coordinate systems.
///
/// The biases are the association convention documented at the top of this
/// module: a collapsed caret hangs off the preceding grapheme at both ends; a
/// range hugs its content.
fn pin(model: Model, start: Int, end: Int) -> Model {
  let start = int.clamp(start, min: 0, max: model.length)
  let end = int.clamp(end, min: 0, max: model.length)

  let head_bias = case start == end {
    True -> watershed_js.bias_after
    False -> watershed_js.bias_before
  }

  case
    watershed_js.text_anchor_at(model.channel, start, head_bias),
    watershed_js.text_anchor_at(model.channel, end, watershed_js.bias_after)
  {
    Ok(head), Ok(tail) ->
      Model(
        ..model,
        selection: Some(
          Selection(start: head, end: tail, range: #(start, end), raw: #(
            grapheme_offset.to_utf16(model.value, start),
            grapheme_offset.to_utf16(model.value, end),
          )),
        ),
      )
    // An index the CRDT will not name is one no caret should be placed at.
    _, _ -> Model(..model, selection: None)
  }
}

/// Write the tracked selection back into the element in the window between the
/// vdom patching its value and the browser painting it.
fn restore(model: Model) -> Effect(Msg) {
  case model.selection {
    None -> effect.none()
    Some(selection) -> {
      let #(start, end) = selection.raw
      let instance = model.instance
      use _dispatch, root <- effect.before_paint
      restore_selection(root, instance, start, end)
    }
  }
}

// ── Internals ────────────────────────────────────────────────────────────────

/// A key unique to this component instance, so an app rendering several of them
/// restores each one's caret into its own element.
fn new_instance() -> String {
  "wst-"
  <> int.to_string(int.random(1_000_000_000))
  <> "-"
  <> int.to_string(int.random(1_000_000_000))
}

/// Run a computed `Edit` against the channel as one minimal op.
fn apply(channel: SharedText, edit: Edit) -> Result(Nil, String) {
  case edit {
    grapheme_diff.NoChange -> Ok(Nil)
    grapheme_diff.Insert(index, value) ->
      watershed_js.text_insert(channel, index, value)
    grapheme_diff.Delete(start, end) ->
      watershed_js.text_delete_range(channel, start, end)
    grapheme_diff.Replace(start, end, value) ->
      watershed_js.text_replace_range(channel, start, end, value)
  }
}

/// Re-read the channel's optimistic state into the model.
fn snapshot(model: Model) -> Model {
  Model(
    ..model,
    value: watershed_js.text_value(model.channel),
    length: watershed_js.text_length(model.channel),
  )
}

/// Fold an edit result into the model: clear the banner on success, keep the
/// runtime's own message on failure.
fn record(model: Model, result: Result(Nil, String), edit: Edit) -> Model {
  case result {
    Ok(Nil) -> Model(..model, error: None)
    Error(reason) ->
      Model(..model, error: Some(verb(edit) <> " failed: " <> reason))
  }
}

fn verb(edit: Edit) -> String {
  case edit {
    grapheme_diff.NoChange -> "noop"
    grapheme_diff.Insert(..) -> "insert"
    grapheme_diff.Delete(..) -> "delete"
    grapheme_diff.Replace(..) -> "replace"
  }
}
