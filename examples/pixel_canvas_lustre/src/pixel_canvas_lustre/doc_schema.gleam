//// Typed schema for the pixel canvas's root document.
////
//// One channel, `pixels`: an `OrMap` in register mode, keyed by cell (see
//// `grid`) with a palette index as the value.
////
//// The choice of kind is the whole argument the demo makes. A `SharedMap`
//// would work and has been demonstrated three times over. A `PactMap` would be
//// actively wrong — it is the quorum protocol, where a value stays pending
//// until a frozen signoff list drains, and requiring the room to agree before
//// a pixel changes colour is the opposite of what a paint canvas wants.
//// `OrMap` register leaves are last-writer-wins per key with no coordination
//// at all, which is exactly right: two people painting different cells never
//// interact, and two people painting the same cell settle on one colour
//// without anybody waiting.

import gleam/dynamic/decode
import gleam/json
import watershed/schema.{type ChannelField, type Field, type OrMapChannel}

/// Phantom tag scoping every field below to the canvas's root map.
pub type CanvasDoc

/// The canvas's display name, shown in the header.
pub fn title() -> Field(CanvasDoc, String) {
  schema.field("title", json.string, decode.string)
}

/// One register leaf per painted cell: `grid.encode(x, y)` to a palette index
/// as a decimal string.
///
/// The value is a `String` because that is what a register leaf holds, and
/// keeping it to one or two characters matters here more than it does
/// elsewhere — this is the one example that emits operations by the thousand.
pub fn pixels() -> ChannelField(CanvasDoc, OrMapChannel) {
  schema.channel_field("pixels")
}
