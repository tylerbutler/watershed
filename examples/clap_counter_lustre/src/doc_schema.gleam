//// The clap counter document's root tag, and its one channel field.
////
//// One `PnCounterChannel` slot, `"claps"`. The app only ever calls
//// `pn_counter_update` with positive amounts — claps only go up — but the
//// underlying kernel is the full P/N lattice CRDT (`lattice_counters/pn_counter`),
//// not a dedicated grow-only counter. Watershed doesn't have one: the vendored
//// `lattice_counters` package ships `g_counter.gleam`, but nothing in
//// `src/watershed/` wires it up. See `docs/demo-ideas.md` for the note.

import watershed/schema.{type ChannelField, type PnCounterChannel}

/// Phantom tag naming the clap counter's root map.
pub type ClapDoc

/// The room's clap tally.
pub fn claps() -> ChannelField(ClapDoc, PnCounterChannel) {
  schema.channel_field("claps")
}
