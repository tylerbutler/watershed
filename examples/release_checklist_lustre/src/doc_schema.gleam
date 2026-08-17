//// Typed schema for the collaborative release checklist's root document.
////
//// `checks` is an `OrSetChannel` of completed gate ids. Add-wins is the right
//// merge rule here: two people ticking the same gate concurrently is not a
//// conflict, and re-ticking a gate that someone else just reopened has to
//// win, which is exactly what a `TwoPSet` (remove-wins) would break. The
//// fixed list of gates itself — their ids and labels — is an app-local
//// constant (see `release_checklist_lustre.gates`/`gate_ids`); only completed
//// ids ever go on the wire.
////
//// `captain` is a `ClaimsChannel` holding one key, `"captain"`, whose value is
//// the release captain's client-assigned identity string. Claims give the
//// room first-writer-wins election plus compare-and-set take-over, so a
//// captain seat resolves to exactly one holder even when several people
//// claim it in the same instant — see `release_checklist_lustre`'s doc
//// comment for why this is a UI convenience, not an authorization boundary.
////
//// `release` is a `PactMapChannel` holding one key, `"target"`. Like the drum
//// machine's `"bpm"`, a release target is state where uncoordinated
//// last-write-wins is genuinely bad, so publishing one requires the room to
//// sign off before it takes effect.

import gleam/dynamic/decode
import gleam/json
import watershed/schema.{
  type ChannelField, type ClaimsChannel, type Field, type OrSetChannel,
  type PactMapChannel,
}

/// Phantom tag scoping every field below to the release checklist's root map.
pub type Checklist

/// The document title, shown in the status line.
pub fn title() -> Field(Checklist, String) {
  schema.field("title", json.string, decode.string)
}

/// Completed release-gate ids, as an add-wins set of strings.
pub fn checks() -> ChannelField(Checklist, OrSetChannel) {
  schema.channel_field("checks")
}

/// The release captain seat: one key, `"captain"`, first-writer-wins with
/// compare-and-set take-over.
pub fn captain() -> ChannelField(Checklist, ClaimsChannel) {
  schema.channel_field("captain")
}

/// Quorum-gated release target. One key today, `"target"`, as a JSON string.
pub fn release() -> ChannelField(Checklist, PactMapChannel) {
  schema.channel_field("release")
}
