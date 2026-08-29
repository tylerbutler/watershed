import watershed/schema.{
  type ChannelField, type GSetChannel, type OrSetChannel, type TwoPSetChannel,
}

pub type Pantry

pub fn grow_only() -> ChannelField(Pantry, GSetChannel) {
  schema.channel_field("grow_only")
}

pub fn two_phase() -> ChannelField(Pantry, TwoPSetChannel) {
  schema.channel_field("two_phase")
}

pub fn observed() -> ChannelField(Pantry, OrSetChannel) {
  schema.channel_field("observed")
}
