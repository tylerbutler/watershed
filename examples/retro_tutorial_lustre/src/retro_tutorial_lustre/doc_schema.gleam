//// Typed schema for the tutorial retro board.
////
//// The root map carries one field (`title`) and two nested OR-map channels.
//// `notes` uses RegisterMode for whole-note writes. `votes` uses TallyMode
//// for per-note signed tallies.

import gleam/dynamic/decode
import gleam/json
import watershed/schema.{type ChannelField, type Field, type OrMapChannel}

/// Phantom tag for the root map.
pub type BoardDoc

/// The board title shown in the header.
pub fn title() -> Field(BoardDoc, String) {
  schema.field("title", json.string, decode.string)
}

/// Note id → JSON note string in RegisterMode.
pub fn notes() -> ChannelField(BoardDoc, OrMapChannel) {
  schema.channel_field("notes")
}

/// Note id → signed tally in TallyMode.
pub fn votes() -> ChannelField(BoardDoc, OrMapChannel) {
  schema.channel_field("votes")
}
