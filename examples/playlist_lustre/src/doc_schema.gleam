//// Typed schema for the collaborative playlist root document.
////
//// The root map carries one plain value (`title`) and one handle to the
//// nested `tracks` sequence. Declaring both slots here lets `ensure_field` and
//// `ensure_sequence` bootstrap the document from the field alone, with no
//// hand-written key constants in the app.
////
//// `tracks` is a `ChannelField(SequenceChannel)`: an ordered list of arbitrary
//// JSON values. Track records are encoded and decoded by `track.gleam` rather
//// than by the schema, because a sequence's element type is not part of a
//// field declaration the way a `Field(s, a)`'s value type is.

import gleam/dynamic/decode
import gleam/json
import watershed/schema.{type ChannelField, type Field, type SequenceChannel}

/// Phantom tag scoping every field below to the playlist root map.
pub type PlaylistDoc

/// The playlist's display name, shown in the header.
pub fn title() -> Field(PlaylistDoc, String) {
  schema.field("title", json.string, decode.string)
}

/// The ordered track list — the sequence this example exists to demonstrate.
pub fn tracks() -> ChannelField(PlaylistDoc, SequenceChannel) {
  schema.channel_field("tracks")
}
