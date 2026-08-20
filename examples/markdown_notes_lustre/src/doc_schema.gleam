//// Schema for the markdown notes document.
////
//// Three root-level channels, every one an ack-free-merge kind so the whole
//// data model is portable to p2p mode unchanged:
////
//// - `notes` — an OR-map of note name → serialized `SharedText` handle.
////   **RegisterMode** — the mode is not part of the schema; it is fixed at
////   creation by the `OrMapMode` passed to `ensure_or_map`, and the app's
////   `bootstrap_effect` is the single place it is named.
//// - `tags` — one document-wide OR-set of `"<note>\t<tag>"` pairs.
//// - `order` — a SharedSequence of note names, the sidebar order.
////
//// The tag set and the order sequence hold note *names*, not handles: the
//// OR-map stays the single source of what a name resolves to, and the other
//// two channels only annotate it.

import watershed/schema.{
  type ChannelField, type OrMapChannel, type OrSetChannel, type SequenceChannel,
}

pub type Notebook

/// Note name → register holding a serialized `SharedText` handle.
pub fn notes() -> ChannelField(Notebook, OrMapChannel) {
  schema.channel_field("notes")
}

/// Document-wide `"<note>\t<tag>"` pairs.
pub fn tags() -> ChannelField(Notebook, OrSetChannel) {
  schema.channel_field("tags")
}

/// Sidebar order: note names, append on create, `sequence_move` to reorder.
pub fn order() -> ChannelField(Notebook, SequenceChannel) {
  schema.channel_field("order")
}
