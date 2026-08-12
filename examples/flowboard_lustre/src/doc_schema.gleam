import gleam/dynamic/decode
import gleam/json
import watershed/schema.{
  type ChannelField, type CounterChannel, type Field, type MapChannel,
}

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
