//// Schema for the sprint board comparison page (`/sharedtree`).
////
//// The phantom tag `Board` scopes every field definition below to one root
//// map shape. It exists only in the build and is erased at compile time.

import gleam/dynamic/decode
import gleam/json
import watershed/schema.{
  type ChannelField, type CounterChannel, type Field, type MapChannel,
}

// docs:snippet-start sharedtree-declare
// A phantom tag. It is erased at compile time — nothing about `Board`
// reaches the document, and no peer has to agree it exists.
pub type Board

pub fn title() -> Field(Board, String) {
  schema.field("title", json.string, decode.string)
}

pub fn cards() -> ChannelField(Board, MapChannel) {
  schema.channel_field("cards")
}

pub fn wip_breaches() -> ChannelField(Board, CounterChannel) {
  schema.channel_field("wip_breaches")
}
// docs:snippet-end sharedtree-declare
