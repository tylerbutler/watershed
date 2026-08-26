//// A `<textarea>` bound to a [`SharedText`](watershed) channel.
////
//// To connect a textarea to a text CRDT appears simple, and it is not. The
//// `input` event gives you the *whole* new value. A simple bridge writes that
//// value back as one replace-the-document op, and that op overwrites every
//// concurrent remote keystroke.
////
//// The correct method is to diff against the current optimistic value of the
//// channel, and to send the one minimal op that the keystroke implies. That op
//// addresses the text in grapheme clusters, and not in the UTF-16 offsets that
//// the browser reports.
////
//// The runtime can then refuse a stale index, when a peer edits the text
//// between the render and the keystroke. Every write thus needs its `Result`
//// value in a place where the user can see it.
////
//// A remote edit also rewrites the value of the element below the person who
//// types. The component must thus derive the caret again, from a position that
//// followed that edit. The offset of the browser points into a string that no
//// longer exists.
////
//// This module owns all of that work, so that an application does not have to
//// find it again.
////
//// This module is a nested MVU triple, and it is not a custom element. `init`
//// takes the live channel handle, which cannot cross the property boundary of
//// a custom element without an unsafe coercion. The parent holds the child
//// model and routes the messages through it:
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
//// There is no `on_change` callback and no `on_error` callback to connect.
//// Every message already passes through the `update` function of the parent.
//// Read [`value`](#value), [`length`](#length), [`error`](#error), and
//// [`selection`](#selection) from the model after each call.
////
//// The parent can continue to edit the channel directly, with `text_append` or
//// any other mutation, and it does not have to tell the component. The
//// subscription delivers the local edits too, so the next `TextChanged` event
//// makes the model take a new snapshot.
////
//// ## How the caret survives a remote edit
////
//// The component holds the selection of the user as a pair of `TextAnchor`
//// values, and not as two offsets. An anchor binds to *content*. When a peer
//// inserts or deletes text, the anchor thus moves with the characters around
//// it. To resolve that anchor afterwards gives the grapheme index of the
//// current caret position. The component converts that index back to UTF-16
//// and writes it into the element from `effect.before_paint`. That effect runs
//// after the vdom writes the value and before the browser paints, so the caret
//// never moves visibly.
////
//// Two decisions are part of this design. They are here, so that a bug report
//// does not have to open them again. A **collapsed caret** attaches to the
//// grapheme before it, at both ends. A remote insert exactly at the caret thus
//// leaves the typing position of the user before the inserted text. A **range**
//// holds its content: the head has the bias `Before` and the tail has the bias
//// `After`. An insert at either edge thus falls outside the selection, and an
//// edit inside the range makes that range larger or smaller. These rules agree
//// with the association conventions of ProseMirror and Yjs.
////
//// Local typing needs no restoration at all. The browser already placed the
//// caret, and the snapshot that the component renders is the same string that
//// the element holds, so the vdom write changes nothing. The restoration runs
//// only when the rendered value changes below the element.
////
//// The component also skips the restoration when the element does not have the
//// focus. To take the focus to place a caret is worse than to lose that
//// position. The anchors continue to track the content. But an element without
//// the focus keeps the offsets that the browser last held. A remote edit that
//// arrives while the user is elsewhere thus leaves the caret of the *browser*
//// stale, until that user places it again.
////
//// ## How an IME composition survives a remote edit
////
//// To type 拼音 or かな runs a *composition session*. The browser puts
//// provisional text in the element and fires an `input` event for each
//// intermediate value. None of those values is an edit that the document must
//// see. A write to the `value` of the element during a session also cancels
//// that session in most browsers. A controlled textarea that renders the
//// keystroke of a peer would thus destroy the text that the user composes.
////
//// For the length of a session, the component thus renders the textarea with
//// no value binding at all, and it records the string that the element held
//// when the session opened. To hold that string is not sufficient by itself.
//// Lustre treats a textarea that dispatched an event as *controlled*, and it
//// writes the `value` again on every diff, whether that value changed or not.
//// A render during a session would thus overwrite the provisional text,
//// whatever value the component supplied. To remove the binding leaves the
//// vdom nothing to write, and it leaves the element to the IME. The channel
//// continues to apply the remote edits, and the model continues to snapshot
//// them. Only the element waits.
////
//// The commit at `compositionend` thus reads the final value of the element
//// against that frozen base, which is in the coordinates of a document that is
//// several remote keystrokes out of date. Two questions separate at that
//// point, and the component answers them separately.
////
//// *What did the user type?* The answer is the graphemes that are now in the
//// region that the session opened over.
//// [`grapheme_diff.replacement`](./grapheme_diff.html#replacement) recovers
//// them.
////
//// *Where does that text go, and what does it replace?* The answer is the
//// current position of that region. **Both ends of the region are anchored**
//// for that reason, and not the caret alone. A peer that inserts inside the
//// composed-over region moves the tail of that region and not its head. One
//// offset cannot report that difference, and a commit that assumed one offset
//// would replace an extent that no user selected.
////
//// The two answers meet in
//// [`grapheme_diff.splice`](./grapheme_diff.html#splice), and they become one
//// op.
////
//// To compose over a selection thus replaces that selection *in its current
//// form*, and it consumes a concurrent edit of a peer inside it. To type over
//// a selection does the same thing. That is the reason that the component
//// tracks the selection, and not its old text.
////
//// Version 1 has one limitation, and this documentation states it. A browser
//// that reports a stale value at `compositionend` commits part of the
//// composition. The next `input` event diffs the remainder, so the document
//// still catches up. The mature collaborative editors make the same trade.
////
//// ## Shared cursors
////
//// [`cursor`](#cursor) gives the selection of this client as a pair of
//// anchors, and [`set_peers`](#set_peers) takes the selections of the other
//// clients back. The broadcast is your work, because the component never
//// touches presence. But the *shape* of what travels is fixed. A grapheme
//// index means nothing to a peer, because the replica of that peer moved on
//// before the index arrived. An anchor binds to content, so the receiver
//// resolves it against its own copy and gets the position that you meant. That
//// is the same property that holds your own caret still under a remote edit.
////
//// The component draws the cursors, because a `<textarea>` element does not
//// draw them, and it does not even report the position of its own text. Its
//// glyphs are in a shadow DOM that the page cannot reach, and no API converts
//// offset 37 into a pixel position.
////
//// [`view`](#view) thus returns a wrapper. That wrapper holds the textarea, an
//// overlay for the drawn cursors, and a hidden **mirror**. The mirror holds the
//// same string in a normal element, with the same typography. A DOM `Range`
//// answers the position question there directly, and `getClientRects` splits a
//// selection across several lines into one rect for each line.
////
//// The measurement runs in the same `before_paint` window as the caret
//// restoration, and it reports back as a message. A cursor thus never appears
//// at a stale position, and the loop cannot repeat without an end, because the
//// reply writes geometry and requests nothing.
////
//// The component does not draw a peer whose anchors this replica cannot
//// resolve yet, which occurs for content that the peer just created. It draws
//// that peer after the op arrives.

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

import watershed.{type Bias, type SharedText, type TextAnchor}
import watershed/crdt_js.{type Handle, type Subscription}
import watershed/schema
import watershed/text_kernel

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

/// Measure the cursor ranges of the peers against the mirror. The function
/// takes JSON and returns JSON, and not Gleam lists, so that the boundary is a
/// plain string on both sides.
@external(javascript, "./textarea_ffi.mjs", "measure_cursors")
fn measure_cursors(root: Dynamic, instance: String, request: String) -> String

/// The attribute that the caret restorer uses to find the element. The
/// component writes it after the attributes of the caller, so a caller cannot
/// replace it.
const instance_attribute = "data-watershed-textarea"

/// The attribute that the measurer uses to find the mirror of this instance.
const mirror_attribute = "data-watershed-mirror"

/// The value that a caret decoder gives when the element reported no selection
/// at all. This value differs from `0`, which is a real caret at the start of
/// the document.
const unknown_caret = -1

/// The state of the component: the channel that it is bound to, the optimistic
/// snapshot that the view renders, the anchored selection, and the last edit
/// that the runtime refused.
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
    /// The component writes this value into the DOM, so that the caret
    /// restoration can find *this* element among every instance that an
    /// application renders.
    instance: String,
    value: String,
    length: Int,
    selection: Option(Selection),
    /// The IME session in flight, if one exists. While this field is `Some`,
    /// the view renders the frozen value of that session and not `value`, and
    /// the component does not change the input of the user.
    composing: Option(Composition),
    /// The value that the element held at the last commit of a composition.
    ///
    /// The browsers disagree about the order of the `input` event and the
    /// `compositionend` event. A browser that fires `input` after
    /// `compositionend` reports this same value a moment later. To diff that
    /// value again would apply the composition again. If a peer edited the text
    /// during the session, it would also remove the work of that peer, because
    /// the channel moved on and the browser has not painted the element yet. To
    /// suppress exactly one echo is safe, because any real keystroke produces a
    /// different value.
    committed: Option(String),
    error: Option(String),
    /// The peer cursors to draw, with their measured geometry.
    /// [`set_peers`](#set_peers) sets this list. The measuring effect fills in
    /// the rectangles one paint later.
    peers: List(Peer),
  )
}

/// A textarea model bound to a sequenced `SharedText` channel.
pub type Model =
  Editor(SharedText)

/// A textarea model bound to a peer-to-peer text handle.
pub type CrdtModel =
  Editor(Handle(schema.TextChannel))

/// The selection of another user, ready to draw.
///
/// Build one with [`peer`](#peer), from a [`Cursor`](#Cursor) value that you
/// decoded from your presence channel. The component fills in every field after
/// `cursor`: the position that the anchors resolve to in *this* replica, and the
/// position of that content on the screen.
pub opaque type Peer {
  Peer(
    id: String,
    label: String,
    colour: String,
    cursor: Cursor,
    /// The position that the cursor resolves to here, in UTF-16 code units. The
    /// value is `None` while an anchor references content that this replica has
    /// not merged yet. The component does not draw that peer until the merge
    /// happens.
    range: Option(#(Int, Int)),
    /// A rectangle with no width, at a collapsed cursor. The component
    /// measures it one paint later.
    caret: Option(Rect),
    /// One rectangle for each line box of a selected range.
    bands: List(Rect),
  )
}

/// A rectangle in pixels. Its origin is the border box of the textarea, and it
/// already includes the scroll position of that element.
type Rect {
  Rect(x: Float, y: Float, width: Float, height: Float)
}

/// A position in the document, in the one form that stays correct when you send
/// it to another client.
///
/// A grapheme index means nothing to a peer. Before that index arrives, the
/// replica of the peer moved on, and the index then points at other content. A
/// pair of anchors binds to *content*, so the receiver resolves it against its
/// own copy and gets the position that the sender meant. The component already
/// uses that property to hold your own caret still under a remote edit.
pub opaque type Cursor {
  Cursor(start: TextAnchor, end: TextAnchor)
}

/// An IME session in flight.
type Composition {
  Composition(
    /// The value of the element when the session opened. The view continues to
    /// render this value, so the vdom never writes to the element and cancels
    /// the session. The component also reads the final value against this
    /// value, to recover the composed text.
    frozen: String,
    /// The graphemes of `frozen` that the session composes over. Those
    /// graphemes are the selection at the moment that the session opened, and
    /// the IME replaces all of them. An ordinary caret is the collapsed
    /// case.
    region: #(Int, Int),
    /// The same region, but bound to content. The commit can thus account for a
    /// remote edit from the session, and that includes an edit *inside* the
    /// region, which moves the two ends by different amounts. The value is
    /// `None` when the runtime cannot name those positions. The session then
    /// still runs, and it has no correction.
    span: Option(#(TextAnchor, TextAnchor)),
  )
}

/// The selection of the user, as content-bound anchors, with the two coordinate
/// systems that it must be readable in. Those systems are the grapheme indices,
/// for a caller and for the CRDT, and the UTF-16 offsets, for the element.
type Selection {
  Selection(
    start: TextAnchor,
    end: TextAnchor,
    /// The position that the anchors resolved to at the last snapshot.
    range: #(Int, Int),
    /// The same position, in the code units of the element. The restore writes
    /// this value back. The component also compares an incoming selection event
    /// with it, so that it does not anchor the same position again.
    raw: #(Int, Int),
  )
}

pub opaque type Msg {
  /// The channel changed, from a local edit or from a remote one. The message
  /// carries the string after that edit. The model reads the channel again all
  /// the same, so the render always shows the committed optimistic state, and
  /// not the payload of an event.
  KernelEvent(text_kernel.TextEvent)
  /// The subscription handle of the p2p binding. The component has no teardown
  /// path, so it ignores this message on purpose.
  P2pSubscribed(Subscription)
  /// The user typed. The message carries the whole new value of the textarea,
  /// and the caret position after that input, in UTF-16 code units.
  UserInput(value: String, sel_start: Int, sel_end: Int)
  /// The user moved the caret, or changed the selection, and made no edit.
  UserSelect(sel_start: Int, sel_end: Int)
  /// An IME session opened. The message carries the value of the element and
  /// the caret position, as they were before the browser inserted any
  /// provisional text.
  CompositionStarted(value: String, sel_start: Int, sel_end: Int)
  /// An IME session committed. The message carries the final value of the
  /// element and the caret position.
  CompositionEnded(value: String, sel_start: Int, sel_end: Int)
  /// The geometry of the peer cursors, which the component measured on the
  /// mirror, between the vdom write and the paint of the browser. The message
  /// carries the JSON response of the FFI.
  Measured(String)
}

/// Whether the handler of this message can write to the bound text channel.
///
/// A parent can use this function to apply a read-only mode. It then keeps the
/// remote channel events, the selection updates, and the cursor
/// measurements.
pub fn mutates_document(msg: Msg) -> Bool {
  case msg {
    UserInput(..) | CompositionStarted(..) | CompositionEnded(..) -> True
    KernelEvent(_) | P2pSubscribed(_) | UserSelect(..) | Measured(_) -> False
  }
}

/// Bind a resolved text channel. The function subscribes to that channel and
/// takes the first snapshot. A tab that joins an existing document thus renders
/// the text immediately, and it does not wait for the first edit.
///
/// The argument is a resolved channel, and not an `Option` value. Construct the
/// component in the `ensure_text` callback. The model thus never holds an empty
/// channel, and the view never renders a disabled element. Render any
/// placeholder that you want before that moment.
pub fn init(channel: SharedText) -> #(Model, Effect(Msg)) {
  init_with(
    channel,
    sequenced_backend(),
    watershed_lustre.subscribe_text(channel, KernelEvent),
  )
}

/// Bind a resolved peer-to-peer text handle. The component logic is the same as
/// in [`init`](#init), and this function subscribes through
/// `watershed_lustre/crdt`.
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

/// The current position of the composed-over region, in graphemes.
///
/// The session opened over a region of a string, and the peers can have edited
/// that string several times after that. The function thus reads both ends of
/// the region from the anchors. It does not assume that the two ends moved
/// together. That is the purpose of an anchored span: an insert inside the
/// region moves its tail and not its head, and one offset cannot report that.
///
/// Every fallback keeps the width of the region, because the user chose that
/// width. Only the position is in question. If the function can name neither
/// end, the region stays at the position where the user typed it. That result
/// is correct whenever no peer edited the text before it, and it converges in
/// every case.
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

/// The one op that applies everything that the user composed.
///
/// The two halves of the session answer separate questions, and this function
/// keeps them separate. The final value of the element says *what the user
/// typed*. The resolved span says *where that text goes and what it replaces*.
///
/// The function recovers the typed text against a known region, and it does not
/// diff for that text. The extent of the region thus comes from the anchors. A
/// diff would derive an extent again in the stale coordinates of the frozen
/// string, and a caller can re-address such an extent only when the whole
/// region moved as one block.
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

/// Put a new snapshot into the view. The function restores the caret only when
/// the text moved below the element.
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

/// A controlled `<textarea>` element that is bound to the channel.
///
/// The attributes of the caller go on the `<textarea>` element itself, before
/// the attributes of the component. You thus control the presentation, which is
/// `rows`, `placeholder`, `class`, `disabled`, and the ARIA attributes. The
/// value binding, the instance marker, and the event handlers always come from
/// the component. `class` and `style` merge, and they do not replace, so a class
/// from the caller is an addition.
///
/// **The returned element is a wrapper, and not the textarea.** The component
/// must draw the peer cursors in some element, and a `<textarea>` element
/// renders its own text only, with no highlight and with no caret except the
/// caret of the user. The textarea thus goes inside a box with
/// `position: relative`, beside two elements that it needs and that you must not
/// style. Those two are a hidden mirror, which measures the position of the
/// range of a peer, and an overlay, which holds the drawn cursors. Both are
/// inert, with `aria-hidden` and `pointer-events: none`, and both have no size
/// when no peer is present. The layout still behaves correctly, because the
/// wrapper takes its size from the textarea. But a selector such as
/// `.editor + p` must now look outside the wrapper.
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

/// An invisible copy of the text, with the same layout as the textarea.
///
/// This element converts the position of a peer into pixels. The browser does
/// not report the position of offset 37 of a `<textarea>` element. There is no
/// API for it, because the text is in a shadow DOM that the page cannot reach.
/// A mirror puts the same string in a normal element, with the same typography
/// and the same wrapping. A DOM `Range` over the text node of that element
/// answers the question directly, and `getClientRects` also splits a selection
/// across several lines into one rectangle for each line.
///
/// The component renders the text as one child, so the FFI can depend on one
/// text node. The mirror stays in the tree when no peer is present. An empty
/// mirror costs one hidden div, and a mirror that stays in the tree is one that
/// the browser already laid out when the first cursor arrives.
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

/// The drawn cursors: one band for each line of the selection of each peer, a
/// caret where that selection is collapsed, and a name tag on that caret.
///
/// This element is inert by construction. It sits *over* the textarea, so an
/// element here that accepted a click would take that click from the user who
/// types below it.
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

/// The approximate height of a name tag. The component uses it only to select
/// the side of the caret that the tag attaches to, so an approximate value is
/// sufficient.
const label_height = 18.0

// ── Accessors ────────────────────────────────────────────────────────────────

/// The optimistic text that the component renders now.
pub fn value(model: Editor(channel)) -> String {
  model.value
}

/// The length of the channel, in grapheme clusters. That count is not in code
/// units, and it differs from the result of `string.length` on the rendered
/// value for a surrogate pair.
pub fn length(model: Editor(channel)) -> Int {
  model.length
}

/// The last edit that the runtime refused. The next edit that it accepts clears
/// this value. A refusal means that a peer moved the text below an index that
/// this client already computed. The model took a new snapshot, so the state is
/// consistent. Use this value to tell the user why the keystroke did not
/// apply.
pub fn error(model: Editor(channel)) -> Option(String) {
  model.error
}

/// The current selection of the user, as a half-open grapheme range. The result
/// is `None` before that user places a caret, and after a remote edit deletes
/// the content that both ends were anchored to. A collapsed caret is a range
/// whose two ends are equal.
///
/// These values are CRDT indices, so you can broadcast them directly. A
/// shared-cursor overlay needs this read.
pub fn selection(model: Editor(channel)) -> Option(#(Int, Int)) {
  option.map(model.selection, fn(selection) { selection.range })
}

// ── Shared cursors ───────────────────────────────────────────────────────────

/// The selection of this client, as a pair of anchors, ready for a broadcast.
/// The result is `None` before the user places a caret.
///
/// Send this value on every [`selection`](#selection) change. The announcement
/// is cheap, and a cursor that moves only when the user *types* looks broken to
/// every other client.
pub fn cursor(model: Editor(channel)) -> Option(Cursor) {
  option.map(model.selection, fn(selection) {
    Cursor(start: selection.start, end: selection.end)
  })
}

/// Encode a cursor for the wire.
///
/// The anchors travel as JSON strings inside the object.
/// `watershed.text_anchor_from_json` reads that shape back.
pub fn cursor_to_json(cursor: Cursor) -> Json {
  json.object([
    #("start", json.string(anchor_json(cursor.start))),
    #("end", json.string(anchor_json(cursor.end))),
  ])
}

fn anchor_json(anchor: TextAnchor) -> String {
  json.to_string(watershed.text_anchor_to_json(anchor))
}

/// Decode a cursor that [`cursor_to_json`](#cursor_to_json) produced. Put this
/// decoder inside your own decoder for a presence payload.
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

/// The cursor of a peer, to draw. `id` must be stable for each user, and the
/// presence user id is the usual choice. That id keeps a measurement attached to
/// the correct peer. `colour` is any CSS colour.
pub fn peer(
  id id: String,
  label label: String,
  colour colour: String,
  cursor cursor: Cursor,
) -> Peer {
  Peer(id:, label:, colour:, cursor:, range: None, caret: None, bands: [])
}

/// Replace the set of peer cursors that the component draws over the text, and
/// measure them.
///
/// Call this function from your handler for the presence roster. A peer whose
/// cursor did not move keeps its geometry, so a roster update from another
/// client does not make every cursor flicker.
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

/// Resolve the anchors of every peer against this replica, and convert the
/// result to the code units that the DOM measures in. The function runs when the
/// peers change, and when the text moves.
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

/// The channel that the component is bound to, for an edit that the component
/// does not own. Those edits are `text_append`, the anchors, and every other
/// function on `watershed`. To change the channel directly is safe, because the
/// subscription makes the model take a new snapshot.
pub fn channel(model: Editor(channel)) -> channel {
  model.channel
}

// ── Event decoding ───────────────────────────────────────────────────────────

fn input_decoder() -> Decoder(Msg) {
  value_decoder(UserInput)
}

/// The whole value of the element, with the caret position after that event.
/// The `input` event and the two composition events all report those two
/// values.
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

/// One edge of the selection of the element, in UTF-16 code units.
///
/// This decoder is total, and that is deliberate. Lustre drops an event whose
/// decoder fails. An element that reports no selection, or that reports it as
/// `null`, would thus cost the user a keystroke, and not only a refresh of an
/// anchor. The `unknown_caret` value keeps the edit and skips the anchor
/// step.
fn caret(name: String) -> Decoder(Int) {
  decode.optionally_at(
    ["target", name],
    unknown_caret,
    decode.one_of(decode.int, or: [decode.success(unknown_caret)]),
  )
}

// ── Selection tracking ───────────────────────────────────────────────────────

/// Anchor again, from the offsets that an element reported, read against
/// `text`. That string is the one that those offsets index into, and it is not
/// always the string that the model holds.
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

/// Resolve the held anchors against the current text of the channel, and pin
/// them again at their new positions.
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

/// Pin new anchors at a grapheme range, clamped into the current text, and
/// record that range in both coordinate systems.
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

/// Bind a grapheme range to the content that it covers.
///
/// The biases follow the association convention at the top of this module, and
/// this function is the only place that selects them. A collapsed position
/// attaches to the grapheme before it, at both ends, so a remote insert there
/// leaves that position before the inserted text. A range holds its content, so
/// an insert at either edge falls outside it, and an edit inside it makes the
/// range larger or smaller. The selection of the user and the region that an IME
/// composes over need the same rule, for the same reason.
///
/// The result is `None` for a position that the CRDT cannot name.
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

/// A UTF-16 offset that an element reported, as a grapheme index into the
/// current document. `text` is the string that those offsets index into, and it
/// is not always the string that the model holds.
fn reported(model: Editor(channel), text: String, offset: Int) -> Int {
  int.clamp(
    grapheme_offset.from_utf16(text, int.max(offset, 0)),
    min: 0,
    max: model.length,
  )
}

// ── Peer cursor measurement ──────────────────────────────────────────────────

/// Ask the mirror for the position of the range of each peer. The function runs
/// in the same `before_paint` window as the caret, after the vdom writes the
/// text of the mirror and before the browser paints anything. A cursor thus
/// never appears at a stale position.
///
/// The reply arrives as a message, and this function does not apply it. That
/// design keeps the loop finite: `Measured` writes geometry and nothing else, so
/// it cannot request another measurement.
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

/// Put the measured geometry back onto the peers that it belongs to. The
/// function matches by id, and not by position, because the roster can change
/// between the request and the answer.
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

/// Write the tracked selection back into the element, in the window between the
/// vdom write of its value and the paint of the browser.
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

/// A key that is unique to this instance of the component. An application that
/// renders several instances thus restores the caret of each one into its own
/// element.
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

/// Run a computed `Edit` value against the channel, as one minimal op.
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

/// The current optimistic string. If a read of the backend failed, the result is
/// the last correct snapshot.
fn current(model: Editor(channel)) -> String {
  case model.backend.snapshot(model.channel) {
    Ok(#(value, _)) -> value
    Error(_) -> model.value
  }
}

/// Read the optimistic state of the channel into the model again.
fn snapshot(model: Editor(channel)) -> Editor(channel) {
  case model.backend.snapshot(model.channel) {
    Ok(#(value, length)) -> Model(..model, value:, length:)
    Error(_) -> model
  }
}

/// Put the result of an edit into the model. The function clears the message on
/// a success, and it keeps the message of the runtime on a failure.
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
