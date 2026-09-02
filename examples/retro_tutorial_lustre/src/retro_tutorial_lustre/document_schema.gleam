//// Typed schema for the tutorial retro board.
////
//// The root map carries one field (`title`) and two nested OR-map channels.
//// `notes` uses RegisterMode for whole-note writes. `votes` uses TallyMode
//// for per-note signed tallies.

import gleam/dynamic/decode
import gleam/json
import watershed/schema.{type ChannelField, type Field, type OrMapChannel}

/// Phantom tag for the root map.
pub type BoardDocument

// docs:snippet-start retro-schema-title
/// The board title shown in the header.
pub fn title() -> Field(BoardDocument, String) {
  schema.field("title", json.string, decode.string)
}

// docs:snippet-end retro-schema-title

/// Note id → JSON note string in RegisterMode.
pub fn notes() -> ChannelField(BoardDocument, OrMapChannel) {
  schema.channel_field("notes")
}

/// Note id → signed tally in TallyMode.
pub fn votes() -> ChannelField(BoardDocument, OrMapChannel) {
  schema.channel_field("votes")
}
