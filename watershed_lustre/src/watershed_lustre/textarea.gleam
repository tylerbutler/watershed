//// A `<textarea>` bound to a [`SharedText`](watershed) channel.
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
//// Committing at `compositionend` therefore means reading the element's final
//// value against that frozen base, which is in the coordinates of a document
//// several remote keystrokes out of date. Two questions come apart there, and
//// the component answers them separately. *What did the user type?* — the
//// graphemes now sitting in the region the session opened over, recovered by
//// [`grapheme_diff.replacement`](./grapheme_diff.html#replacement). *Where does
//// it go, and what does it replace?* — wherever that region has got to, which
//// is why **both of its ends are anchored**, not just the caret. A peer
//// inserting inside the composed-over region moves its tail without moving its
//// head; one offset cannot say so, and a commit that assumed otherwise would
//// replace an extent nobody chose. The two answers meet in
//// [`grapheme_diff.splice`](./grapheme_diff.html#splice) and land as one op.
////
//// Composing over a selection therefore replaces that selection *as it now
//// stands*, consuming a peer's concurrent edit inside it — the same thing
//// typing over a selection does, and the reason it is the selection rather
//// than its old text that is tracked.
////
//// One v1 limitation, documented rather than papered over: a browser that
//// reports a stale value at `compositionend` commits a partial composition.
//// The next `input` event diffs the remainder, so the document still catches
//// up. Mature collaborative editors ship the same trade.
////
//// ## Shared cursors
////
//// [`cursor`](#cursor) hands out this client's selection as a pair of anchors,
//// and [`set_peers`](#set_peers) takes everyone else's back. Broadcasting them
//// is yours — the component never touches presence — but the *shape* of what
//// travels is not negotiable: a grapheme index means nothing to a peer, whose
//// replica has moved on by the time it lands. Anchors bind to content, so the
//// receiver resolves them against their own copy and gets the position you
//// meant, which is the same reason your own caret survives a remote edit.
////
//// Drawing them is the component's, because a `<textarea>` will not do it and
//// will not even say where its own text is: the glyphs live in shadow DOM the
//// page cannot reach, and there is no API mapping offset 37 to a pixel. So
//// [`view`](#view) returns a wrapper holding the textarea, an overlay for the
//// drawn cursors, and a hidden **mirror** — the same string in a normal element
//// with the same typography, where a DOM `Range` answers the question directly
//// and `getClientRects` splits a wrapped selection into one rect per line for
//// free. Measuring happens in the same `before_paint` window as caret
//// restoration and reports back as a message, so a cursor is never painted at a
//// stale position and the loop cannot run away: the reply writes geometry and
//// asks for nothing.
////
//// A peer whose anchors this replica cannot resolve yet — content they have
//// only just created — is simply not drawn until the op arrives.

import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}

import lustre/attribute.{type Attribute}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import watershed/crdt_js.{type Handle, type Subscription}
import watershed/schema
import watershed/text_kernel
import watershed.{type Bias, type SharedText, type TextAnchor}

import watershed_lustre
import watershed_lustre/crdt
import watershed_lustre/grapheme_diff.{type Edit}
import watershed_lustre/grapheme_offset

@external(javascript, "./textarea_ffi.mjs", "restore_selection")
fn restore_selection(
  root: Dynamic,
  instance: String,
  start: Int,
  end: Int,
) -> Nil

/// Measure peer cursor ranges against the mirror. Takes and returns JSON rather
/// than Gleam lists so the boundary stays a plain string on both sides.
@external(javascript, "./textarea_ffi.mjs", "measure_cursors")
fn measure_cursors(root: Dynamic, instance: String, request: String) -> String

/// The attribute the caret restorer finds the element by. Stamped after the
/// caller's attributes, so it cannot be overridden.
const instance_attribute = "data-watershed-textarea"

/// The attribute the measurer finds this instance's mirror by.
const mirror_attribute = "data-watershed-mirror"

/// What a caret decoder yields when the element reported no selection at all.
/// Distinct from `0`, which is a real caret at the head of the document.
const unknown_caret = -1

/// The component's state: the channel it is bound to, the optimistic snapshot
/// the view renders, the anchored selection, and the last rejected edit.
type Backend(channel) {
  Backend(
    snapshot: fn(channel) -> Result(#(String, Int), String),
    insert: fn(channel, Int, String) -> Result(Nil, String),
    delete_range: fn(channel, Int, Int) -> Result(Nil, String),
    replace_range: fn(channel, Int, Int, String) -> Result(Nil, String),
    anchor_at: fn(channel, Int, Bias) -> Option(TextAnchor),
    resolve_anchor: fn(channel, TextAnchor) -> Option(Int),
  )
}

pub opaque type Editor(channel) {
  Model(
    channel: channel,
    backend: Backend(channel),
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
    /// Peer cursors to draw, with their measured geometry. Set by
    /// [`set_peers`](#set_peers); the rects are filled in by the measuring
    /// effect a paint later.
    peers: List(Peer),
  )
}

/// A textarea model bound to a sequenced `SharedText` channel.
pub type Model =
  Editor(SharedText)

/// A textarea model bound to a peer-to-peer text handle.
pub type CrdtModel =
  Editor(Handle(schema.TextChannel))

/// Another user's selection, ready to draw.
///
/// Build one with [`peer`](#peer) from a [`Cursor`](#Cursor) you decoded off
/// your presence channel. Everything past `cursor` is the component's to fill:
/// where the anchors resolve in *this* replica, and where that lands on screen.
pub opaque type Peer {
  Peer(
    id: String,
    label: String,
    colour: String,
    cursor: Cursor,
    /// Where the cursor resolves here, in UTF-16 code units. `None` while an
    /// anchor references content this replica has not merged yet — the peer is
    /// simply not drawn until it does.
    range: Option(#(Int, Int)),
    /// A zero-width rect at a collapsed cursor, measured a paint later.
    caret: Option(Rect),
    /// One rect per line box of a selected range.
    bands: List(Rect),
  )
}

/// A rectangle in pixels, relative to the textarea's border box and already
/// corrected for its scroll position.
type Rect {
  Rect(x: Float, y: Float, width: Float, height: Float)
}

/// A position in the document, expressed the only way that survives being sent
/// to someone else.
///
/// A grapheme index is meaningless to a peer: by the time it arrives their
/// replica has moved on, and the index points somewhere else. A pair of anchors
/// binds to *content*, so the receiver resolves it against their own copy and
/// gets the position the sender meant. That is the same property the component
/// already relies on to hold your own caret still under a remote edit.
pub opaque type Cursor {
  Cursor(start: TextAnchor, end: TextAnchor)
}

/// An IME session in flight.
type Composition {
  Composition(
    /// The element's value when the session opened — what the view keeps
    /// rendering, so the vdom never writes to the element and cancels the
    /// session, and what the final value is read against to recover the
    /// composed text.
    frozen: String,
    /// The graphemes of `frozen` the session is composing over: whatever was
    /// selected when it opened, which the IME replaces wholesale. An ordinary
    /// caret is the collapsed case.
    region: #(Int, Int),
    /// The same region, but tracking content, so a remote edit made during the
    /// session can be accounted for at commit — including one landing *inside*
    /// the region, which moves its ends by different amounts. `None` if the
    /// runtime would not name those positions: the session still runs, just
    /// without correction.
    span: Option(#(TextAnchor, TextAnchor)),
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
  /// The p2p binding's subscription handle. The component keeps no teardown
  /// path, so this is intentionally ignored.
  P2pSubscribed(Subscription)
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
  /// Peer cursor geometry, measured off the mirror between the vdom patching
  /// it and the browser painting. Carries the FFI's JSON response.
  Measured(String)
}

/// Whether handling this message may write to the bound text channel.
///
/// Parents can use this to enforce a read-only mode without dropping remote
/// channel events, selection updates, or cursor measurements.
pub fn mutates_document(msg: Msg) -> Bool {
  case msg {
    UserInput(..) | CompositionStarted(..) | CompositionEnded(..) -> True
    KernelEvent(_) | P2pSubscribed(_) | UserSelect(..) | Measured(_) -> False
  }
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
  init_with(
    channel,
    sequenced_backend(),
    watershed_lustre.subscribe_text(channel, KernelEvent),
  )
}

/// Bind a resolved peer-to-peer text handle. Uses the same component logic as
/// [`init`](#init), but subscribes through `watershed_lustre/crdt`.
pub fn init_crdt(
  channel: Handle(schema.TextChannel),
) -> #(CrdtModel, Effect(Msg)) {
  init_with(
    channel,
    crdt_backend(),
    crdt.subscribe_text(channel, P2pSubscribed, KernelEvent),
  )
}

fn init_with(
  channel: channel,
  backend: Backend(channel),
  subscription: Effect(Msg),
) -> #(Editor(channel), Effect(Msg)) {
  let model =
    snapshot(
      Model(
        channel:,
        backend:,
        instance: new_instance(),
        value: "",
        length: 0,
        selection: None,
        composing: None,
        committed: None,
        error: None,
        peers: [],
      ),
    )

  #(model, subscription)
}

pub fn update(
  model: Editor(channel),
  msg: Msg,
) -> #(Editor(channel), Effect(Msg)) {
  case msg {
    P2pSubscribed(_) -> #(model, effect.none())

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

    // Geometry only — deliberately the one arm that starts nothing, so the
    // measure/paint loop terminates.
    Measured(response) -> #(place(model, response), effect.none())

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
          let edit = grapheme_diff.diff(old: current(model), new: value)
          let result = apply(model, edit)

          // Snapshot *after* applying: on success this is the text the user
          // just typed, and on a rejected index it snaps the textarea back to
          // the truth the runtime kept. Either way the local kernel event that
          // follows re-snapshots to the same string, so that write is a no-op.
          let model = record(snapshot(model), result, edit)

          // Re-anchor against the string the *browser* holds, which is the one
          // the reported offsets index into. It is the snapshot too, unless the
          // op was rejected — the one case where the two disagree.
          let model = locate(anchor(model, value, sel_start, sel_end))

          case model.value == value {
            // Accepted: the browser already placed the caret and is rendering
            // the same string the model is. Nothing to restore — but the text
            // grew or shrank, so the peers need re-measuring against it.
            True -> #(model, measure(model))
            // Rejected: the view is about to snap back to the runtime's text,
            // so the caret needs placing in it.
            False -> #(model, effect.batch([restore(model), measure(model)]))
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
    // element holds right now, so remote edits stop reaching the DOM, and
    // anchor the region being composed over so their effect can still be
    // accounted for at commit time.
    CompositionStarted(value:, sel_start:, sel_end:) -> {
      // What the IME replaces is the *selection*, not the caret — so that is
      // what the commit has to address, and a caret is simply the collapsed
      // case of it. Anchoring only one end would leave the far end of a
      // composed-over range addressed in stale coordinates.
      let head = reported(model, value, sel_start)
      let tail = case sel_end < 0 {
        True -> head
        False -> reported(model, value, sel_end)
      }
      let region = #(int.min(head, tail), int.max(head, tail))

      #(
        Model(
          ..model,
          composing: Some(Composition(
            frozen: value,
            region:,
            span: anchors(model, region.0, region.1),
          )),
          committed: None,
        ),
        effect.none(),
      )
    }

    // The session committed. What the user composed is whatever now sits in
    // the region the session opened over; where that region has got to is the
    // anchors' business.
    CompositionEnded(value:, sel_start:, sel_end:) ->
      case model.composing {
        // No session to close — a stray event, or one whose `compositionstart`
        // never decoded. Fall through to the ordinary input path so the text is
        // not silently dropped.
        None -> update(model, UserInput(value:, sel_start:, sel_end:))

        Some(composition) -> {
          // Read once, before the op lands: applying the composition can move
          // or delete the very graphemes the span is anchored to, so a second
          // reading afterwards would answer a different question.
          let #(start, end) = site(model, composition)
          let shift = start - composition.region.0
          let edit = commit(composition, value, start, end, shift)
          let result = apply(model, edit)

          // Unfreeze: from here the view renders the channel again.
          let model =
            Model(..model, composing: None, committed: Some(value))
            |> snapshot
            |> record(result, edit)

          // The reported offsets index `value`, which predates any remote edit
          // that landed during the session, so they need carrying by however
          // far the region's head moved — right for a caret sitting at or
          // inside the composed text, which is where an IME leaves it. When
          // the element reports nothing, fall back to resolving the anchors,
          // which are already in the right coordinates.
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
          let model = locate(model)
          #(model, effect.batch([restore(model), measure(model)]))
        }
      }
  }
}

/// Where the composed-over region lives *now*, in graphemes.
///
/// The session opened over a region of a string that peers may have edited
/// several times since, so both of its ends are re-read from the anchors rather
/// than assumed to have moved together. That is the whole point of anchoring a
/// span: an insert inside the region moves its tail without moving its head,
/// and a single offset cannot say so.
///
/// Every fallback keeps the region's width, because the width is the user's own
/// choice — the only question is where it landed. If neither end can be named,
/// the region stays where it was typed, which is right whenever no peer edited
/// before it and convergent either way.
fn site(model: Editor(channel), composition: Composition) -> #(Int, Int) {
  let #(origin_start, origin_end) = composition.region
  let width = origin_end - origin_start

  case composition.span {
    None -> composition.region
    Some(#(head, tail)) ->
      case
        model.backend.resolve_anchor(model.channel, head),
        model.backend.resolve_anchor(model.channel, tail)
      {
        // An interior edit is exactly the case where these two disagree by
        // something other than the same amount.
        Some(start), Some(end) -> #(start, int.max(start, end))
        // One end names content this replica cannot place — rare, since an
        // anchor on *deleted* content still resolves to the gap it left. Hang
        // the region off the end that survived.
        Some(start), None -> #(start, start + width)
        None, Some(end) -> #(int.max(0, end - width), end)
        None, None -> composition.region
      }
  }
}

/// The one op that lands everything the user composed.
///
/// The session's two halves answer separate questions and are kept separate
/// here: the element's final value says *what was typed*, the resolved span
/// says *where it goes and what it replaces*. Recovering the typed text against
/// a known region rather than diffing for it is what lets the region's extent
/// come from the anchors — a diff would re-derive an extent in the frozen
/// string's stale coordinates, which is only re-addressable when the whole
/// region moved as a block.
fn commit(
  composition: Composition,
  value: String,
  start: Int,
  end: Int,
  shift: Int,
) -> Edit {
  case value == composition.frozen {
    // An abandoned session — escaped, or committed to nothing. Replacing the
    // region with its own text would be a no-op on this replica and a deletion
    // of anything a peer put inside it meanwhile.
    True -> grapheme_diff.NoChange
    False ->
      case
        grapheme_diff.replacement(
          old: composition.frozen,
          new: value,
          region: composition.region,
        )
      {
        Ok(composed) -> grapheme_diff.splice(start:, end:, value: composed)
        // The element changed outside the region too, so the session is not
        // describable as "this region became that text" — a browser reporting
        // a stale value at `compositionstart`, say. Fall back to inferring the
        // edit and carrying it by however far the region's head moved, which
        // is right for everything except the interior case this span exists to
        // fix.
        Error(Nil) ->
          grapheme_diff.diff(old: composition.frozen, new: value)
          |> grapheme_diff.shift(by: shift)
      }
  }
}

/// Fold a fresh snapshot into the view: restore the caret only when the text
/// actually moved under the element.
fn settle(
  model: Editor(channel),
  rendered: String,
) -> #(Editor(channel), Effect(Msg)) {
  case model.value == rendered {
    // The ordinary case for a local keystroke: the channel is echoing text the
    // model already rendered, so the vdom write is a no-op and the browser's
    // own caret is exactly where the user put it. Touching the selection here
    // would be fighting them for it.
    True -> #(model, effect.none())
    // The text moved under the element. The anchors moved with it, so resolve
    // them and put the caret back before the browser paints — and re-place the
    // peers, whose cursors travelled with the same content.
    False -> {
      let model = locate(resolve(model))
      #(model, effect.batch([restore(model), measure(model)]))
    }
  }
}

/// A controlled `<textarea>` bound to the channel.
///
/// Caller attributes go on the `<textarea>` itself, applied before the
/// component's own, so presentation — `rows`, `placeholder`, `class`,
/// `disabled`, ARIA — is yours to set while the value binding, the instance
/// marker, and the event handlers always win. `class` and `style` merge rather
/// than replace, so a caller class is additive.
///
/// **The returned element is a wrapper, not the textarea.** Peer cursors have
/// to be drawn *somewhere*, and a `<textarea>` renders only its own text — no
/// highlights, no carets but the user's. So the textarea ships inside a
/// `position: relative` box alongside two siblings it needs but you should not
/// style: a hidden mirror used to measure where a peer's range falls, and an
/// overlay holding the drawn cursors. Both are inert (`aria-hidden`,
/// `pointer-events: none`) and both collapse to nothing when no peer is
/// present. Layout still behaves, because the wrapper takes its size from the
/// textarea — but a selector like `.editor + p` now needs to look outside it.
pub fn view(
  model: Editor(channel),
  attrs: List(Attribute(Msg)),
) -> Element(Msg) {
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

  html.div(
    [
      attribute.style("position", "relative"),
      attribute.style("display", "block"),
    ],
    [mirror_view(model), overlay_view(model), field_view(model, bindings)],
  )
}

/// The bound element itself.
fn field_view(
  model: Editor(channel),
  bindings: List(Attribute(Msg)),
) -> Element(Msg) {
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

/// An invisible copy of the text, laid out exactly as the textarea lays it out.
///
/// This is how a peer's position becomes pixels. The browser will not tell you
/// where offset 37 of a `<textarea>` is — there is no API for it, because the
/// text lives in shadow DOM the page cannot reach. A mirror puts the same
/// string in a normal element with the same typography and wrapping, where a
/// DOM `Range` over its text node answers the question directly, and
/// `getClientRects` even splits a wrapped selection into one rect per line for
/// free.
///
/// The text is rendered as a single child so the FFI can rely on finding one
/// text node. It stays in the tree with no peers present — an empty mirror
/// costs one hidden div, and keeping it mounted means the first cursor to
/// arrive measures against a mirror the browser has already laid out.
fn mirror_view(model: Editor(channel)) -> Element(Msg) {
  html.div(
    [
      attribute.attribute(mirror_attribute, model.instance),
      attribute.attribute("aria-hidden", "true"),
      attribute.style("position", "absolute"),
      attribute.style("top", "0"),
      attribute.style("left", "0"),
      // Visible to layout, invisible to the eye, and untouchable by the mouse:
      // `display: none` would refuse to lay out and measure as zero.
      attribute.style("visibility", "hidden"),
      attribute.style("pointer-events", "none"),
      attribute.style("z-index", "-1"),
      // Everything else that decides where a glyph lands — font, padding,
    // border width, wrapping — is copied off the live textarea at measure
    // time, because only then is the caller's own CSS settled.
    ],
    [html.text(model.value)],
  )
}

/// The drawn cursors: one band per line of each peer's selection, a caret where
/// it is collapsed, and a name tag on the caret.
///
/// Inert by construction — this sits *over* the textarea, so anything here that
/// took a click would take it away from the user typing underneath.
fn overlay_view(model: Editor(channel)) -> Element(Msg) {
  html.div(
    [
      attribute.attribute("aria-hidden", "true"),
      attribute.style("position", "absolute"),
      attribute.style("inset", "0"),
      attribute.style("overflow", "hidden"),
      attribute.style("pointer-events", "none"),
    ],
    list.flat_map(model.peers, peer_view),
  )
}

fn peer_view(peer: Peer) -> List(Element(Msg)) {
  let bands =
    list.map(peer.bands, fn(band) {
      html.div(
        [
          attribute.style("position", "absolute"),
          attribute.style("left", px(band.x)),
          attribute.style("top", px(band.y)),
          attribute.style("width", px(band.width)),
          attribute.style("height", px(band.height)),
          attribute.style("background", peer.colour),
          // Legible over text without hiding it, and without needing the
          // caller to know the peer's colour is a highlight.
          attribute.style("opacity", "0.25"),
          attribute.style("border-radius", "0.125rem"),
        ],
        [],
      )
    })

  let caret = case peer.caret {
    None -> []
    Some(rect) -> [
      html.div(
        [
          attribute.style("position", "absolute"),
          attribute.style("left", px(rect.x)),
          attribute.style("top", px(rect.y)),
          attribute.style("width", "2px"),
          attribute.style("height", px(rect.height)),
          attribute.style("background", peer.colour),
        ],
        [
          html.span(
            [
              attribute.style("position", "absolute"),
              // Above the caret, except on the first line, where there is no
              // room and the overlay would clip it — then hang it below.
              case rect.y <. label_height {
                True -> attribute.style("top", "100%")
                False -> attribute.style("top", "-1.15em")
              },
              attribute.style("left", "-1px"),
              attribute.style("padding", "0 0.25rem"),
              attribute.style("border-radius", "0.25rem"),
              attribute.style("background", peer.colour),
              attribute.style("color", "white"),
              attribute.style("font-size", "0.7rem"),
              attribute.style("line-height", "1.5"),
              attribute.style("white-space", "nowrap"),
            ],
            [html.text(peer.label)],
          ),
        ],
      ),
    ]
  }

  list.append(bands, caret)
}

fn px(value: Float) -> String {
  float.to_string(value) <> "px"
}

/// Roughly how tall a name tag renders. Only used to decide which side of the
/// caret it hangs off, so an approximation is enough.
const label_height = 18.0

// ── Accessors ────────────────────────────────────────────────────────────────

/// The optimistic text the component is currently rendering.
pub fn value(model: Editor(channel)) -> String {
  model.value
}

/// The channel's length in grapheme clusters — not code units, and not what
/// `string.length` on the rendered value would tell you about surrogate pairs.
pub fn length(model: Editor(channel)) -> Int {
  model.length
}

/// The last edit the runtime rejected, cleared by the next one it accepts. A
/// rejection means a peer moved the text under an index this client had already
/// computed; the model has re-snapshotted, so the state is consistent — this is
/// for telling the user why their keystroke did not land.
pub fn error(model: Editor(channel)) -> Option(String) {
  model.error
}

/// The user's current selection as a half-open grapheme range, or `None` before
/// they have placed a caret (or after a remote edit deleted the content both
/// ends were anchored to). A collapsed caret is a range whose ends are equal.
///
/// These are CRDT indices, so they are directly broadcastable: this is the
/// read a shared-cursor overlay wants.
pub fn selection(model: Editor(channel)) -> Option(#(Int, Int)) {
  option.map(model.selection, fn(selection) { selection.range })
}

// ── Shared cursors ───────────────────────────────────────────────────────────

/// This client's selection as a pair of anchors, ready to broadcast, or `None`
/// before the user has placed a caret.
///
/// Send it on every [`selection`](#selection) change — announcing is cheap and
/// a cursor that only moves when you *type* reads as broken to everyone else.
pub fn cursor(model: Editor(channel)) -> Option(Cursor) {
  option.map(model.selection, fn(selection) {
    Cursor(start: selection.start, end: selection.end)
  })
}

/// Encode a cursor for the wire.
///
/// The anchors travel as embedded JSON strings, which is the shape
/// `watershed.text_anchor_from_json` reads back.
pub fn cursor_to_json(cursor: Cursor) -> Json {
  json.object([
    #("start", json.string(anchor_json(cursor.start))),
    #("end", json.string(anchor_json(cursor.end))),
  ])
}

fn anchor_json(anchor: TextAnchor) -> String {
  json.to_string(watershed.text_anchor_to_json(anchor))
}

/// Decode a cursor produced by [`cursor_to_json`](#cursor_to_json), for nesting
/// inside your own presence payload decoder.
pub fn cursor_decoder() -> Decoder(Cursor) {
  use start <- decode.field("start", anchor_decoder())
  use end <- decode.field("end", anchor_decoder())

  decode.success(Cursor(start:, end:))
}

fn anchor_decoder() -> Decoder(TextAnchor) {
  use encoded <- decode.then(decode.string)
  case watershed.text_anchor_from_json(encoded) {
    Ok(anchor) -> decode.success(anchor)
    // A malformed anchor is one peer's cursor, not a reason to drop the whole
    // roster — the zero value is discarded by `decode`'s error path anyway.
    Error(_) -> decode.failure(watershed.text_start_anchor(), "TextAnchor")
  }
}

/// A peer's cursor to draw. `id` must be stable per user (the presence user id
/// is the obvious choice) — it is what keeps a measurement attached to the
/// right peer. `colour` is any CSS colour.
pub fn peer(
  id id: String,
  label label: String,
  colour colour: String,
  cursor cursor: Cursor,
) -> Peer {
  Peer(id:, label:, colour:, cursor:, range: None, caret: None, bands: [])
}

/// Replace the set of peer cursors drawn over the text, and measure them.
///
/// Call this from your presence roster handler. Peers whose cursor has not
/// moved keep their existing geometry, so a roster update caused by someone
/// else does not make every cursor flicker.
pub fn set_peers(
  model: Editor(channel),
  peers: List(Peer),
) -> #(Editor(channel), Effect(Msg)) {
  let peers =
    list.map(peers, fn(peer) {
      case list.find(model.peers, fn(old) { old.id == peer.id }) {
        // Same peer, same cursor: keep what was already measured.
        Ok(old) if old.cursor == peer.cursor -> old
        _ -> peer
      }
    })

  let model = locate(Model(..model, peers:))
  #(model, measure(model))
}

/// Resolve every peer's anchors against this replica and convert to the code
/// units the DOM measures in. Runs whenever the peers change or the text moves.
fn locate(model: Editor(channel)) -> Editor(channel) {
  let peers =
    list.map(model.peers, fn(peer) {
      let range = case
        model.backend.resolve_anchor(model.channel, peer.cursor.start),
        model.backend.resolve_anchor(model.channel, peer.cursor.end)
      {
        Some(start), Some(end) ->
          Some(#(
            grapheme_offset.to_utf16(model.value, int.min(start, end)),
            grapheme_offset.to_utf16(model.value, int.max(start, end)),
          ))
        // An anchor this replica cannot name yet — usually content the peer
        // has only just created. Drop the cursor rather than guess; it comes
        // back on the next announce, by which time the op will have arrived.
        _, _ -> None
      }
      Peer(..peer, range:)
    })

  Model(..model, peers:)
}

/// The channel the component is bound to, for edits it does not own —
/// `text_append`, anchors, or anything else on `watershed`. Mutating it
/// directly is safe: the subscription re-snapshots the model.
pub fn channel(model: Editor(channel)) -> channel {
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
fn anchor(
  model: Editor(channel),
  text: String,
  sel_start: Int,
  sel_end: Int,
) -> Editor(channel) {
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
fn resolve(model: Editor(channel)) -> Editor(channel) {
  case model.selection {
    None -> model
    Some(selection) ->
      case
        model.backend.resolve_anchor(model.channel, selection.start),
        model.backend.resolve_anchor(model.channel, selection.end)
      {
        Some(start), Some(end) -> pin(model, start, end)
        // One edge's grapheme was deleted out from under it. Collapse onto the
        // edge that survived rather than guess where the range went.
        Some(index), None | None, Some(index) -> pin(model, index, index)
        // Both edges gone: there is no honest position left, so drop the
        // selection and leave the browser whatever caret it has.
        None, None -> Model(..model, selection: None)
      }
  }
}

/// Pin fresh anchors at a grapheme range, clamped into the current text, and
/// record the range in both coordinate systems.
fn pin(model: Editor(channel), start: Int, end: Int) -> Editor(channel) {
  let start = int.clamp(start, min: 0, max: model.length)
  let end = int.clamp(end, min: 0, max: model.length)

  case anchors(model, start, end) {
    Some(#(head, tail)) ->
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
    None -> Model(..model, selection: None)
  }
}

/// Bind a grapheme range to the content it covers.
///
/// The biases are the association convention documented at the top of this
/// module, and this is the only place they are chosen: a collapsed position
/// hangs off the preceding grapheme at both ends, so a remote insert there
/// leaves it before the inserted text; a range hugs its content, so an insert
/// at either edge falls outside it while an interior edit grows or shrinks it.
/// The user's selection and the region an IME composes over want the same rule
/// for the same reason.
///
/// `None` for a position the CRDT will not name.
fn anchors(
  model: Editor(channel),
  start: Int,
  end: Int,
) -> Option(#(TextAnchor, TextAnchor)) {
  let head_bias = case start == end {
    True -> watershed.bias_after
    False -> watershed.bias_before
  }

  case
    model.backend.anchor_at(model.channel, start, head_bias),
    model.backend.anchor_at(model.channel, end, watershed.bias_after)
  {
    Some(head), Some(tail) -> Some(#(head, tail))
    _, _ -> None
  }
}

/// A UTF-16 offset an element reported, as a grapheme index into the current
/// document. `text` is the string those offsets index into, which is not always
/// the one the model holds.
fn reported(model: Editor(channel), text: String, offset: Int) -> Int {
  int.clamp(
    grapheme_offset.from_utf16(text, int.max(offset, 0)),
    min: 0,
    max: model.length,
  )
}

// ── Peer cursor measurement ──────────────────────────────────────────────────

/// Ask the mirror where each peer's range lands, in the same `before_paint`
/// window the caret uses — after the vdom has written the mirror's text, before
/// anything is painted, so a cursor never shows up at a stale position.
///
/// The reply comes back as a message rather than being applied here, which is
/// what keeps this loop finite: `Measured` writes geometry and nothing else, so
/// it cannot ask for another measurement.
fn measure(model: Editor(channel)) -> Effect(Msg) {
  let drawable =
    list.filter_map(model.peers, fn(peer) {
      case peer.range {
        Some(#(start, end)) ->
          Ok(
            json.object([
              #("id", json.string(peer.id)),
              #("start", json.int(start)),
              #("end", json.int(end)),
            ]),
          )
        None -> Error(Nil)
      }
    })

  case drawable {
    [] -> effect.none()
    _ -> {
      let request = json.to_string(json.preprocessed_array(drawable))
      let instance = model.instance
      use dispatch, root <- effect.before_paint
      dispatch(Measured(measure_cursors(root, instance, request)))
    }
  }
}

/// Fold measured geometry back onto the peers it belongs to, matched by id
/// rather than by position — the roster can change between asking and answering.
fn place(model: Editor(channel), response: String) -> Editor(channel) {
  case json.parse(response, decode.list(measurement_decoder())) {
    Error(_) -> model
    Ok(measurements) -> {
      let peers =
        list.map(model.peers, fn(peer) {
          case list.find(measurements, fn(m) { m.0 == peer.id }) {
            Ok(#(_, caret, bands)) -> Peer(..peer, caret:, bands:)
            Error(_) -> Peer(..peer, caret: None, bands: [])
          }
        })
      Model(..model, peers:)
    }
  }
}

fn measurement_decoder() -> Decoder(#(String, Option(Rect), List(Rect))) {
  use id <- decode.field("id", decode.string)
  use caret <- decode.field("caret", decode.optional(rect_decoder()))
  use bands <- decode.field("bands", decode.list(rect_decoder()))

  decode.success(#(id, caret, bands))
}

fn rect_decoder() -> Decoder(Rect) {
  use x <- decode.field("x", decode.float)
  use y <- decode.field("y", decode.float)
  use width <- decode.field("width", decode.float)
  use height <- decode.field("height", decode.float)

  decode.success(Rect(x:, y:, width:, height:))
}

/// Write the tracked selection back into the element in the window between the
/// vdom patching its value and the browser painting it.
fn restore(model: Editor(channel)) -> Effect(Msg) {
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

fn sequenced_backend() -> Backend(SharedText) {
  Backend(
    snapshot: fn(channel) {
      Ok(#(watershed.text_value(channel), watershed.text_length(channel)))
    },
    insert: fn(channel, index, value) {
      watershed.text_insert(channel, index, value)
    },
    delete_range: fn(channel, start, end) {
      watershed.text_delete_range(channel, start, end)
    },
    replace_range: fn(channel, start, end, value) {
      watershed.text_replace_range(channel, start, end, value)
    },
    anchor_at: fn(channel, index, bias) {
      case watershed.text_anchor_at(channel, index, bias) {
        Ok(anchor) -> Some(anchor)
        Error(_) -> None
      }
    },
    resolve_anchor: fn(channel, anchor) {
      case watershed.text_resolve_anchor(channel, anchor) {
        Ok(index) -> Some(index)
        Error(_) -> None
      }
    },
  )
}

fn crdt_backend() -> Backend(Handle(schema.TextChannel)) {
  Backend(
    snapshot: crdt_snapshot,
    insert: fn(channel, index, value) {
      case crdt_js.text_insert(channel, index:, value:) {
        Ok(Nil) -> Ok(Nil)
        Error(reason) -> Error(crdt_js.describe_error(reason))
      }
    },
    delete_range: fn(channel, start, end) {
      case crdt_js.text_delete_range(channel, start:, end:) {
        Ok(Nil) -> Ok(Nil)
        Error(reason) -> Error(crdt_js.describe_error(reason))
      }
    },
    replace_range: fn(channel, start, end, value) {
      case crdt_js.text_replace_range(channel, start:, end:, value:) {
        Ok(Nil) -> Ok(Nil)
        Error(reason) -> Error(crdt_js.describe_error(reason))
      }
    },
    anchor_at: crdt_anchor_at,
    resolve_anchor: crdt_resolve_anchor,
  )
}

fn crdt_snapshot(
  channel: Handle(schema.TextChannel),
) -> Result(#(String, Int), String) {
  case crdt_js.text_value(channel), crdt_js.text_length(channel) {
    Ok(value), Ok(length) -> Ok(#(value, length))
    Error(reason), _ | _, Error(reason) -> Error(crdt_js.describe_error(reason))
  }
}

fn crdt_anchor_at(
  channel: Handle(schema.TextChannel),
  index: Int,
  bias: Bias,
) -> Option(TextAnchor) {
  case crdt_js.text_anchor_at(channel, index, bias) {
    Ok(anchor) -> Some(anchor)
    Error(_) -> None
  }
}

fn crdt_resolve_anchor(
  channel: Handle(schema.TextChannel),
  anchor: TextAnchor,
) -> Option(Int) {
  case crdt_js.text_resolve_anchor(channel, anchor) {
    Ok(index) -> Some(index)
    Error(_) -> None
  }
}

/// Run a computed `Edit` against the channel as one minimal op.
fn apply(model: Editor(channel), edit: Edit) -> Result(Nil, String) {
  case edit {
    grapheme_diff.NoChange -> Ok(Nil)
    grapheme_diff.Insert(index, value) ->
      model.backend.insert(model.channel, index, value)
    grapheme_diff.Delete(start, end) ->
      model.backend.delete_range(model.channel, start, end)
    grapheme_diff.Replace(start, end, value) ->
      model.backend.replace_range(model.channel, start, end, value)
  }
}

/// The current optimistic string, or the last good snapshot if a backend read
/// failed.
fn current(model: Editor(channel)) -> String {
  case model.backend.snapshot(model.channel) {
    Ok(#(value, _)) -> value
    Error(_) -> model.value
  }
}

/// Re-read the channel's optimistic state into the model.
fn snapshot(model: Editor(channel)) -> Editor(channel) {
  case model.backend.snapshot(model.channel) {
    Ok(#(value, length)) -> Model(..model, value:, length:)
    Error(_) -> model
  }
}

/// Fold an edit result into the model: clear the banner on success, keep the
/// runtime's own message on failure.
fn record(
  model: Editor(channel),
  result: Result(Nil, String),
  edit: Edit,
) -> Editor(channel) {
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
