//// Typed schema for the collaborative text root document.
////
//// The root map carries one plain value (`title`, the document's display name)
//// and one handle to the nested `body` text channel. Declaring both slots here
//// lets `ensure_field` and `ensure_text` bootstrap the document from the field
//// alone, with no hand-written key constants in the app — and, crucially, every
//// tab resolves the *same* `body` channel through `ensure_text`, so joiners
//// converge on one shared document instead of seeding rivals.

import gleam/dynamic/decode
import gleam/json
import watershed/schema.{type ChannelField, type Field, type TextChannel}

/// Phantom tag scoping every field below to the text-editor root map.
pub type TextDoc

/// The document's display name, shown in the header.
pub fn title() -> Field(TextDoc, String) {
  schema.field("title", json.string, decode.string)
}

/// The collaborative plain-text body — the `SharedText` this example exists to
/// demonstrate.
pub fn body() -> ChannelField(TextDoc, TextChannel) {
  schema.channel_field("body")
}
