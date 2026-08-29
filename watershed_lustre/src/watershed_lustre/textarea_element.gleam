//// [`watershed_lustre/textarea`](./textarea.html) as a `<watershed-textarea>`
//// custom element, for hosts that are not Lustre apps.
////
//// The nested MVU triple is the real shape of the component. It is fully
//// typed, and it has no boundary that a live handle must cross. This module
//// puts that same triple in a custom element, with `lustre.component`. A plain
//// JavaScript page cannot hold a child model and route the messages, and a
//// React, Svelte, or server-rendered host cannot either. But every one of them
//// *can* set a property and listen for an event. This module does not write
//// the bridge again. Every keystroke, caret, IME session, and peer cursor
//// still goes through [`textarea.update`](./textarea.html#update).
////
//// ## Passing the channel
////
//// A `SharedText` value is a live handle that closes over the running client.
//// Nothing can serialize it, so it cannot travel as an attribute. It crosses
//// as a **property** instead, and a property carries any JavaScript value:
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
//// A Lustre host sets the same property declaratively, and with types:
////
//// ```gleam
//// textarea_element.element(channel: text, attributes: [attribute.rows(10)])
//// ```
////
//// This is the one place at which the opaque handle passes through an untyped
//// seam. The property decoder checks that the value has the shape of a
//// `SharedText` value, which is a string `address` and a `runtime`. Only then
//// does it perform the one coercion. It ignores an invalid value that a host
//// assigns to `.channel`, and the component does not crash.
////
//// To assign the same handle again does nothing. To assign a *different*
//// handle binds the element to the new channel. The component cannot cancel
//// the subscription of the old channel, because `subscribe_text` has no
//// unsubscribe function. But an event from that subscription only takes a new
//// snapshot of the current channel, so the leak is idle and not incorrect.
////
//// > **Register the element before you create one.** The `channel` setter and
//// > the `peers` setter are on the prototype of the registered class. If a
//// > host assigns a property to an element that the browser has not upgraded
//// > yet, that property becomes a plain own property, which *hides* the
//// > setter, and the component never receives the value. Call
//// > [`register`](#register) at startup, before any `<watershed-textarea>`
//// > element exists.
////
//// ## Outbound: events
////
//// The accessors of the triple become `CustomEvent` objects, which bubble and
//// are composed. A host cannot read a Gleam model out of an element. Each
//// event occurs only when its value changes:
////
//// | event      | `detail`                                  | when                                    |
//// | ---------- | ----------------------------------------- | --------------------------------------- |
//// | `"change"` | `{ value: string, length: number }`       | the text moved — locally or remotely    |
//// | `"error"`  | `{ message: string \| null }`             | an edit was rejected; `null` clears it  |
//// | `"cursor"` | [`cursor_to_json`](./textarea.html#cursor_to_json) shape, or `null` | this user's selection moved |
////
//// `length` counts grapheme clusters, and not code units. The `"cursor"`
//// payload is ready to go into a presence message for the peers. The host must
//// send that message, exactly as it must for the triple.
////
//// ## Inbound: peer cursors
////
//// The `peers` property takes plain data in the wire shape, and not Gleam
//// values. A JavaScript host can thus forward what its transport delivered:
////
//// ```js
//// editor.peers = [
////   { id: "user-b", label: "Blake", colour: "#e4573d", cursor },
//// ];
//// ```
////
//// Here `cursor` is the `"cursor"` event detail of another element, which the
//// presence channel of the host delivered. A Lustre host builds the same
//// payload with [`peer`](#peer) and [`peers`](#peers).
////
//// ## Presentation
////
//// The component forwards `rows`, `cols`, and `placeholder` to the inner
//// `<textarea>` element as ordinary attributes. `disabled` disables that
//// element when its value is exactly `"true"`. A bare `disabled` attribute
//// looks the same as a removed one when it reaches the component, so its
//// presence alone cannot control the state. For everything else, the inner
//// textarea carries `part="textarea"`:
////
//// ```css
//// watershed-textarea::part(textarea) { font: inherit; min-height: 12rem; }
//// ```
////
//// The component also adopts the stylesheets of the document into its shadow
//// root, which is the default in Lustre. A plain `textarea { … }` rule thus
//// reaches it too.

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

import watershed.{type SharedText}

import watershed_lustre/textarea

/// The registered tag. The name of a custom element must contain a hyphen.
/// This name is fixed, so a host and a stylesheet can depend on it.
pub const name = "watershed-textarea"

/// Define `<watershed-textarea>` in the custom element registry of the browser.
/// Call this function one time at startup, before you create or render an
/// instance. The module docs explain why the order is important. The function
/// fails with `ComponentAlreadyRegistered` on a second call, and with
/// `NotABrowser` outside a browser.
pub fn register() -> Result(Nil, lustre.Error) {
  lustre.register(lustre.component(init, update, view, options()), name)
}

/// Render the element from a Lustre host, with the channel attached. Each
/// other attribute goes on the *host* element. To style the inner textarea, use
/// the `rows`, `cols`, and `placeholder` attributes, or `::part(textarea)`.
pub fn element(
  channel channel: SharedText,
  attributes attributes: List(Attribute(msg)),
) -> Element(msg) {
  element.element(name, [channel_property(channel), ..attributes], [])
}

/// The `channel` property as a typed attribute, for a host that renders the tag
/// itself. This is the one unsafe seam of the module. The live handle passes
/// through as a property value, and the other side checks its shape first.
pub fn channel_property(channel: SharedText) -> Attribute(msg) {
  attribute.property("channel", shared_text_to_json(channel))
}

/// One peer cursor, in the wire shape of the `peers` property. `id` must be
/// stable for each user. `colour` is any CSS colour. `cursor` is the value that
/// you decoded from your presence channel, which is the `"cursor"` event detail
/// of the other side.
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

/// The `peers` property as a typed attribute: the full roster to draw, which
/// you build with [`peer`](#peer). It replaces the whole previous roster, the
/// same as [`textarea.set_peers`](./textarea.html#set_peers), because it is
/// that function.
pub fn peers(peers: List(Json)) -> Attribute(msg) {
  attribute.property("peers", json.preprocessed_array(peers))
}

// ── The component ────────────────────────────────────────────────────────────

type Model {
  Model(
    /// The triple that this element wraps. The value is `None` until a host
    /// assigns a channel. The view then renders an inactive placeholder, so
    /// the element has its size from the start.
    editor: Option(textarea.Model),
    /// The most recent roster that a host assigned. It stays outside the
    /// editor, so the component can apply a roster that arrived before the
    /// channel when that channel arrives.
    peers: List(textarea.Peer),
    /// The most recent cursor that the element emitted. `"cursor"` thus occurs
    /// on a movement, and not on every keystroke. Two anchors compare by
    /// value, and a caret that followed the same content anchors to an equal
    /// value.
    announced: Option(textarea.Cursor),
    rows: Option(Int),
    columns: Option(Int),
    placeholder: Option(String),
    disabled: Bool,
  )
}

type Msg {
  ChannelReceived(SharedText)
  PeersReceived(List(textarea.Peer))
  RowsChanged(Option(Int))
  ColumnsChanged(Option(Int))
  PlaceholderChanged(Option(String))
  DisabledChanged(Bool)
  Inner(textarea.Msg)
}

fn options() -> List(component.Option(Msg)) {
  [
    component.on_property_change("channel", channel_decoder()),
    component.on_property_change("peers", peers_decoder()),
    component.on_attribute_change("rows", count(RowsChanged)),
    component.on_attribute_change("cols", count(ColumnsChanged)),
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

fn init(_arguments: Nil) -> #(Model, Effect(Msg)) {
  #(
    Model(
      editor: None,
      peers: [],
      announced: None,
      rows: None,
      columns: None,
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
    ColumnsChanged(columns) -> #(Model(..model, columns:), effect.none())
    PlaceholderChanged(placeholder) -> #(
      Model(..model, placeholder:),
      effect.none(),
    )
    DisabledChanged(disabled) -> #(Model(..model, disabled:), effect.none())
  }
}

/// The accessors of the triple, as events at the element boundary. Each event
/// occurs on a real transition only. A host that repaints on `"change"` thus
/// does not repaint on every `keyup`.
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
  let attributes = [component.part("textarea")]
  let attributes = case model.disabled {
    True -> [attribute.disabled(True), ..attributes]
    False -> attributes
  }
  let attributes = case model.placeholder {
    Some(text) -> [attribute.placeholder(text), ..attributes]
    None -> attributes
  }
  let attributes = case model.columns {
    Some(columns) -> [attribute.cols(columns), ..attributes]
    None -> attributes
  }
  case model.rows {
    Some(rows) -> [attribute.rows(rows), ..attributes]
    None -> attributes
  }
}

// ── Property decoding ────────────────────────────────────────────────────────

/// Accept a live `SharedText` value from the `channel` property. The decoder
/// checks the shape before the coercion: a handle carries its channel
/// `address` and the `runtime` that it is bound to. A value without those two
/// fields decodes to nothing, and the component ignores the assignment. That
/// behaviour contains the fault, and the component does not crash on an
/// invalid value.
fn channel_decoder() -> Decoder(Msg) {
  use _address <- decode.field("address", decode.string)
  use _runtime <- decode.field("runtime", decode.dynamic)
  use handle <- decode.then(decode.dynamic)
  decode.success(ChannelReceived(dynamic_to_shared_text(handle)))
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
fn shared_text_to_json(channel: SharedText) -> Json

@external(javascript, "./textarea_element_ffi.mjs", "identity")
fn dynamic_to_shared_text(value: Dynamic) -> SharedText
