//// Typed schema for the tournament bracket root document.
////
//// One channel: `matches`, a `RegisterCollection` keyed by match id
//// (`"r1m1"` .. `"r3m1"`, see `bracket.gleam`) with each register holding a
//// JSON `{"winner": ..., "score": ...}` value. Bracket topology and
//// advancement are plain data (`bracket.gleam`) — the only thing this
//// document needs to carry collaboratively is who won each match.

import watershed/schema.{type ChannelField, type RegisterCollectionChannel}

/// Phantom tag scoping the field below to the bracket root map.
pub type BracketDocument

/// Match id -> reported result. One register per match, seven total.
pub fn matches() -> ChannelField(BracketDocument, RegisterCollectionChannel) {
  schema.channel_field("matches")
}
