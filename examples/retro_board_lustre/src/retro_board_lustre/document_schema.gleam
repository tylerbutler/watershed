//// Typed schema for the retro board root document.
////
//// The root map carries one plain value (`title`) and five channel handles:
//// two `OrMap`s and one `SharedSequence` per column. The two OR-maps have the
//// same field type — `ChannelField(BoardDocument, OrMapChannel)` — because a
//// channel's value mode is not part of the schema: it is fixed at creation
//// time by the `OrMapMode` passed to `ensure_or_map`, and nothing here can
//// stop a caller passing the wrong one. The app's `bootstrap_effect` is the
//// single place both modes are named; keep it that way.
////
//// The sequence field names must match `column.id` — the render rule compares
//// a note's `column` register against them to decide which sequence is
//// authoritative for the note.

import gleam/dynamic/decode
import gleam/json
import watershed/schema.{
  type ChannelField, type Field, type OrMapChannel, type SequenceChannel,
}

/// Phantom tag scoping every field below to the retro board root map.
pub type BoardDocument

/// The board's display name, shown in the header.
pub fn title() -> Field(BoardDocument, String) {
  schema.field("title", json.string, decode.string)
}

/// Note id → JSON-encoded note record. **RegisterMode** — see
/// `bootstrap_effect`.
pub fn notes() -> ChannelField(BoardDocument, OrMapChannel) {
  schema.channel_field("notes")
}

/// Note id → signed vote tally. **TallyMode** — see `bootstrap_effect`.
pub fn votes() -> ChannelField(BoardDocument, OrMapChannel) {
  schema.channel_field("votes")
}

/// Display order for the "Went well" column.
pub fn went_well() -> ChannelField(BoardDocument, SequenceChannel) {
  schema.channel_field("went_well")
}

/// Display order for the "To improve" column.
pub fn to_improve() -> ChannelField(BoardDocument, SequenceChannel) {
  schema.channel_field("to_improve")
}

/// Display order for the "Action items" column.
pub fn action_items() -> ChannelField(BoardDocument, SequenceChannel) {
  schema.channel_field("action_items")
}
