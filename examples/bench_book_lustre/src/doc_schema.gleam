import gleam/dynamic/decode
import gleam/json
import watershed/schema.{
  type ChannelField, type CounterChannel, type Field, type MapChannel,
}

pub type Survey

pub fn title() -> Field(Survey, String) {
  schema.field("title", json.string, decode.string)
}

pub fn readings() -> ChannelField(Survey, MapChannel) {
  schema.channel_field("readings")
}

pub fn flags() -> ChannelField(Survey, CounterChannel) {
  schema.channel_field("flags")
}
