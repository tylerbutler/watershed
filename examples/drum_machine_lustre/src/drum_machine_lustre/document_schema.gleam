//// Typed schema for the collaborative drum machine's root document.
////
//// Four `OrSetChannel` slots hold the pattern — one per track, each an OR-set
//// of enabled step indices as decimal strings, `"0"`–`"15"`. Add-wins is the
//// right merge rule here: two people enabling the same step concurrently is
//// not a conflict, and toggling a step off and back on has to work, which is
//// exactly what a `TwoPSet` would break.
////
//// `settings` is a `PactMapChannel` holding one key, `"bpm"`. Tempo is the one
//// piece of state in this app where uncoordinated last-write-wins is genuinely
//// bad — two people dragging a BPM slider in opposite directions produces a
//// room that lurches — so it is the one piece that requires the room to sign
//// off before it changes. Everything else is deliberately uncoordinated so the
//// contrast is visible.

import gleam/dynamic/decode
import gleam/json
import watershed/schema.{
  type ChannelField, type Field, type OrSetChannel, type PactMapChannel,
}

/// Phantom tag scoping every field below to the drum machine's root map.
pub type Machine

/// The document title, shown in the status line.
pub fn title() -> Field(Machine, String) {
  schema.field("title", json.string, decode.string)
}

/// Enabled kick steps, as decimal step indices `"0"`–`"15"`.
pub fn kick() -> ChannelField(Machine, OrSetChannel) {
  schema.channel_field("kick")
}

/// Enabled snare steps.
pub fn snare() -> ChannelField(Machine, OrSetChannel) {
  schema.channel_field("snare")
}

/// Enabled hat steps.
pub fn hat() -> ChannelField(Machine, OrSetChannel) {
  schema.channel_field("hat")
}

/// Enabled clap steps.
pub fn clap() -> ChannelField(Machine, OrSetChannel) {
  schema.channel_field("clap")
}

/// Quorum-gated room settings. One key today, `"bpm"`, as a JSON number.
pub fn settings() -> ChannelField(Machine, PactMapChannel) {
  schema.channel_field("settings")
}
