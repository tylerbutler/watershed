//// [`watershed_lustre/textarea`](./textarea.html) as a `<watershed-textarea>`
//// custom element, for hosts that are not Lustre apps.
////
//// The nested MVU triple is the component's real shape: fully typed, no
//// boundary to smuggle a live handle across. This module wraps that same
//// triple in a custom element via `lustre.component`, because a plain
//// JavaScript page — or a React, Svelte, or server-rendered host — cannot
//// hold a child model and route messages, but it *can* set a property and
//// listen for events. Nothing here reimplements the bridge; every keystroke,
//// caret, IME session, and peer cursor still goes through
//// [`textarea.update`](./textarea.html#update).
////
//// ## Passing the channel
////
//// A `SharedText` is a live handle closed over the running client — it cannot
//// be serialized, so it cannot travel as an attribute. It crosses as a
//// **property** instead, which carries any JavaScript value:
////
//// ```js
//// import { register } from "./watershed_lustre/textarea_element.mjs";
////
//// register();                                   // once, before creating any
//// const editor = document.createElement("watershed-textarea");
//// editor.channel = text;                        // the live SharedText handle
//// document.body.append(editor);
//// ```
////
//// From a Lustre host the same property is set declaratively — and typed:
////
//// ```gleam
//// textarea_element.element(channel: text, attrs: [attribute.rows(10)])
//// ```
////
//// This is the one place the opaque handle passes through an untyped seam.
//// The property decoder checks the value has a `SharedText`'s shape (a string
//// `address` and a `runtime`) before the single contained coercion; garbage
//// assigned to `.channel` is ignored rather than crashing the component.
////
//// Assigning the same handle again is a no-op. Assigning a *different* handle
//// rebinds the element to the new channel. (The old channel's subscription
//// cannot be cancelled — `subscribe_text` has no unsubscribe — but its events
//// only re-snapshot the current channel, so the leak is idle, not wrong.)
////
//// > **Register before you create.** The `channel` and `peers` setters live on
//// > the registered class's prototype. A property assigned to an element that
//// > has not been upgraded yet becomes a plain own property that *shadows* the
//// > setter, and the component never hears about it. Call [`register`](#register)
//// > at startup, before any `<watershed-textarea>` exists.
////
//// ## Outbound: events
////
//// The triple's accessors become `CustomEvent`s (bubbling, composed), since an
//// element cannot be polled for a Gleam model. Each fires only when its value
//// actually changed:
////
//// | event      | `detail`                                  | when                                    |
//// | ---------- | ----------------------------------------- | --------------------------------------- |
//// | `"change"` | `{ value: string, length: number }`       | the text moved — locally or remotely    |
//// | `"error"`  | `{ message: string \| null }`             | an edit was rejected; `null` clears it  |
//// | `"cursor"` | [`cursor_to_json`](./textarea.html#cursor_to_json) shape, or `null` | this user's selection moved |
////
//// `length` is grapheme clusters, not code units. The `"cursor"` payload is
//// ready to nest in a presence message and hand to peers — announcing it is
//// the host's job, exactly as it is for the triple.
////
//// ## Inbound: peer cursors
////
//// The `peers` property takes plain data — the wire shape, not Gleam values —
//// so a JavaScript host can forward what its transport delivered:
////
//// ```js
//// editor.peers = [
////   { id: "user-b", label: "Blake", colour: "#e4573d", cursor },
//// ];
//// ```
////
//// where `cursor` is another element's `"cursor"` event detail, delivered by
//// whatever presence channel the host runs. A Lustre host builds the same
//// payload with [`peer`](#peer) and [`peers`](#peers).
////
//// ## Presentation
////
//// `rows`, `cols`, and `placeholder` forward to the inner `<textarea>` as
//// ordinary attributes; `disabled` disables it when set to exactly `"true"`
//// (a bare `disabled` attribute is indistinguishable from a removed one by
//// the time it reaches the component, so presence alone cannot toggle it).
//// For everything else the inner textarea carries `part="textarea"`:
////
//// ```css
//// watershed-textarea::part(textarea) { font: inherit; min-height: 12rem; }
//// ```
////
//// The component also adopts the document's stylesheets into its shadow root
//// (Lustre's default), so plain `textarea { … }` rules reach it too.

import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}

import lustre
import lustre/attribute.{type Attribute}
import lustre/component
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import watershed_js.{type SharedText}

import watershed_lustre/textarea

/// The registered tag. Valid custom-element names must contain a hyphen; this
/// one is fixed so hosts and stylesheets can rely on it.
pub const name = "watershed-textarea"

/// Define `<watershed-textarea>` in the browser's custom element registry.
/// Call once at startup, before creating or rendering any instance — see the
/// module docs for why order matters. Fails with `ComponentAlreadyRegistered`
/// if called twice, and `NotABrowser` outside one.
pub fn register() -> Result(Nil, lustre.Error) {
  lustre.register(lustre.component(init, update, view, options()), name)
}

/// Render the element from a Lustre host, with the channel already attached.
/// Extra attributes land on the *host* element — presentation for the inner
/// textarea goes through the `rows`/`cols`/`placeholder` attributes or
/// `::part(textarea)`.
pub fn element(
  channel channel: SharedText,
  attrs attrs: List(Attribute(msg)),
) -> Element(msg) {
  element.element(name, [channel_property(channel), ..attrs], [])
}

/// The `channel` property as a typed attribute, for hosts that render the tag
/// themselves. This is the module's single unsafe seam: the live handle is
/// passed through as a property value, and validated shape-first on the other
/// side.
pub fn channel_property(channel: SharedText) -> Attribute(msg) {
  attribute.property("channel", as_json(channel))
}

/// One peer cursor in the `peers` property's wire shape. `id` must be stable
/// per user; `colour` is any CSS colour; `cursor` is what you decoded off your
/// presence channel — the other side's `"cursor"` event detail.
pub fn peer(
  id id: String,
  label label: String,
  colour colour: String,
  cursor cursor: textarea.Cursor,
) -> Json {
  json.object([
    #("id", json.string(id)),
    #("label", json.string(label)),
    #("colour", json.string(colour)),
    #("cursor", textarea.cursor_to_json(cursor)),
  ])
}

/// The `peers` property as a typed attribute: the full roster to draw, built
/// with [`peer`](#peer). Replaces the previous roster wholesale, like
/// [`textarea.set_peers`](./textarea.html#set_peers) — because it is one.
pub fn peers(peers: List(Json)) -> Attribute(msg) {
  attribute.property("peers", json.preprocessed_array(peers))
}

// ── The component ────────────────────────────────────────────────────────────

type Model {
  Model(
    /// The wrapped triple. `None` until a channel is assigned; the view
    /// renders an inert placeholder so the element has its size from the
    /// start.
    editor: Option(textarea.Model),
    /// The last roster assigned, kept outside the editor so a roster that
    /// arrives before the channel does is applied when it turns up.
    peers: List(textarea.Peer),
    /// The last cursor emitted, so `"cursor"` fires on movement rather than
    /// on every keystroke — anchors compare by value, and a caret that
    /// tracked the same content re-anchors equal.
    announced: Option(textarea.Cursor),
    rows: Option(Int),
    cols: Option(Int),
    placeholder: Option(String),
    disabled: Bool,
  )
}

type Msg {
  ChannelReceived(SharedText)
  PeersReceived(List(textarea.Peer))
  RowsChanged(Option(Int))
  ColsChanged(Option(Int))
  PlaceholderChanged(Option(String))
  DisabledChanged(Bool)
  Inner(textarea.Msg)
}

fn options() -> List(component.Option(Msg)) {
  [
    component.on_property_change("channel", channel_decoder()),
    component.on_property_change("peers", peers_decoder()),
    component.on_attribute_change("rows", count(RowsChanged)),
    component.on_attribute_change("cols", count(ColsChanged)),
    component.on_attribute_change("placeholder", fn(value) {
      Ok(
        PlaceholderChanged(case value {
          "" -> None
          text -> Some(text)
        }),
      )
    }),
    component.on_attribute_change("disabled", fn(value) {
      Ok(DisabledChanged(value == "true"))
    }),
    // Focusing the host focuses the textarea, and clicks on the host's inert
    // sliver of padding land in the editor rather than nowhere.
    component.delegates_focus(True),
  ]
}

fn count(to_msg: fn(Option(Int)) -> Msg) -> fn(String) -> Result(Msg, Nil) {
  fn(value) { Ok(to_msg(option.from_result(int.parse(value)))) }
}

fn init(_) -> #(Model, Effect(Msg)) {
  #(
    Model(
      editor: None,
      peers: [],
      announced: None,
      rows: None,
      cols: None,
      placeholder: None,
      disabled: False,
    ),
    effect.none(),
  )
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    ChannelReceived(channel) -> {
      // The same handle assigned again is a host re-render, not a rebind.
      // Handles holding the same runtime instance compare cheaply.
      let rebound = case model.editor {
        Some(editor) -> textarea.channel(editor) != channel
        None -> True
      }
      case rebound {
        False -> #(model, effect.none())
        True -> {
          let #(editor, started) = textarea.init(channel)
          let #(editor, placed) = case model.peers {
            [] -> #(editor, effect.none())
            roster -> textarea.set_peers(editor, roster)
          }
          #(
            Model(..model, editor: Some(editor), announced: None),
            effect.batch([
              effect.map(started, Inner),
              effect.map(placed, Inner),
              // The first snapshot is a change the host has not seen — a
              // joiner's existing text arrives through this.
              changed(editor),
            ]),
          )
        }
      }
    }

    PeersReceived(roster) ->
      case model.editor {
        None -> #(Model(..model, peers: roster), effect.none())
        Some(editor) -> {
          let #(editor, fx) = textarea.set_peers(editor, roster)
          #(
            Model(..model, peers: roster, editor: Some(editor)),
            effect.map(fx, Inner),
          )
        }
      }

    Inner(inner) ->
      case model.editor {
        None -> #(model, effect.none())
        Some(editor) -> {
          let #(after, fx) = textarea.update(editor, inner)
          let #(announced, events) = emitted(editor, after, model.announced)
          #(
            Model(..model, editor: Some(after), announced:),
            effect.batch([effect.map(fx, Inner), events]),
          )
        }
      }

    RowsChanged(rows) -> #(Model(..model, rows:), effect.none())
    ColsChanged(cols) -> #(Model(..model, cols:), effect.none())
    PlaceholderChanged(placeholder) -> #(
      Model(..model, placeholder:),
      effect.none(),
    )
    DisabledChanged(disabled) -> #(Model(..model, disabled:), effect.none())
  }
}

/// The triple's accessors, turned into events at the element boundary. Each
/// fires only on an actual transition, so a host repainting on `"change"` is
/// not repainting on every `keyup`.
fn emitted(
  before: textarea.Model,
  after: textarea.Model,
  announced: Option(textarea.Cursor),
) -> #(Option(textarea.Cursor), Effect(Msg)) {
  let change = case textarea.value(after) == textarea.value(before) {
    True -> effect.none()
    False -> changed(after)
  }

  let errored = case textarea.error(after) == textarea.error(before) {
    True -> effect.none()
    False ->
      event.emit(
        "error",
        json.object([
          #("message", json.nullable(textarea.error(after), json.string)),
        ]),
      )
  }

  let cursor = textarea.cursor(after)
  let #(announced, moved) = case cursor == announced {
    True -> #(announced, effect.none())
    False -> #(
      cursor,
      event.emit("cursor", case cursor {
        Some(cursor) -> textarea.cursor_to_json(cursor)
        None -> json.null()
      }),
    )
  }

  #(announced, effect.batch([change, errored, moved]))
}

fn changed(editor: textarea.Model) -> Effect(Msg) {
  event.emit(
    "change",
    json.object([
      #("value", json.string(textarea.value(editor))),
      #("length", json.int(textarea.length(editor))),
    ]),
  )
}

fn view(model: Model) -> Element(Msg) {
  case model.editor {
    Some(editor) ->
      textarea.view(editor, passthrough(model)) |> element.map(Inner)
    // No channel yet: an inert stand-in with the same presentation, so the
    // element takes up its final space and a caller's part styles apply from
    // the first paint.
    None -> html.textarea([attribute.disabled(True), ..passthrough(model)], "")
  }
}

fn passthrough(model: Model) -> List(Attribute(msg)) {
  let attrs = [component.part("textarea")]
  let attrs = case model.disabled {
    True -> [attribute.disabled(True), ..attrs]
    False -> attrs
  }
  let attrs = case model.placeholder {
    Some(text) -> [attribute.placeholder(text), ..attrs]
    None -> attrs
  }
  let attrs = case model.cols {
    Some(cols) -> [attribute.cols(cols), ..attrs]
    None -> attrs
  }
  case model.rows {
    Some(rows) -> [attribute.rows(rows), ..attrs]
    None -> attrs
  }
}

// ── Property decoding ────────────────────────────────────────────────────────

/// Accept a live `SharedText` off the `channel` property. Shape-checked before
/// the coercion: a handle carries its channel `address` and the `runtime` it
/// is bound to. A value without them decodes to nothing and the assignment is
/// ignored — the contained alternative to crashing on garbage.
fn channel_decoder() -> Decoder(Msg) {
  use _address <- decode.field("address", decode.string)
  use _runtime <- decode.field("runtime", decode.dynamic)
  use handle <- decode.then(decode.dynamic)
  decode.success(ChannelReceived(as_shared_text(handle)))
}

fn peers_decoder() -> Decoder(Msg) {
  decode.list(of: {
    use id <- decode.field("id", decode.string)
    use label <- decode.field("label", decode.string)
    use colour <- decode.field("colour", decode.string)
    use cursor <- decode.field("cursor", textarea.cursor_decoder())
    decode.success(textarea.peer(id:, label:, colour:, cursor:))
  })
  |> decode.map(PeersReceived)
}

// The two halves of the module's one unsafe seam, kept adjacent so it is
// auditable in a single screen: a handle leaves the typed world as a property
// value here, and re-enters it — shape-checked by `channel_decoder` — there.
@external(javascript, "./textarea_element_ffi.mjs", "identity")
fn as_json(channel: SharedText) -> Json

@external(javascript, "./textarea_element_ffi.mjs", "identity")
fn as_shared_text(value: Dynamic) -> SharedText
