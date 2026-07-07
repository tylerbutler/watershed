//// Typed schema for the collaborative Sudoku root document.
////
//// The root map carries two plain values (`puzzle`, `title`) and four handles
//// to nested channels (`cells`, `notes`, `givens`, `mistakes`). Declaring the
//// six slots once here replaces the hand-written key constants the example used
//// to carry, and lets `ensure_*` bootstrap each channel from the field alone.
////
//// `cells` is a `ChannelField(MapChannel)` rather than a `ChildField`: it is a
//// dynamic map keyed by cell position (`r{row}c{col}`), with no per-key record
//// schema to derive, so `ensure_map` hands back the raw `SharedMap` the grid
//// reads and writes directly.

import gleam/dynamic/decode
import gleam/json
import watershed/schema.{
  type ChannelField, type ClaimsChannel, type CounterChannel, type Field,
  type MapChannel, type OrSetChannel,
}

/// Phantom tag scoping every field below to the Sudoku root map.
pub type SudokuDoc

/// The active puzzle's id (see `puzzles.by_id`).
pub fn puzzle() -> Field(SudokuDoc, String) {
  schema.field("puzzle", json.string, decode.string)
}

/// The document title, shown in the status line.
pub fn title() -> Field(SudokuDoc, String) {
  schema.field("title", json.string, decode.string)
}

/// The player-entered digits, keyed `r{row}c{col}` → digit.
pub fn cells() -> ChannelField(SudokuDoc, MapChannel) {
  schema.channel_field("cells")
}

/// The pencil-mark notes, as `r{row}c{col}={digit}` set elements.
pub fn notes() -> ChannelField(SudokuDoc, OrSetChannel) {
  schema.channel_field("notes")
}

/// The puzzle's immutable givens, first-writer-wins claims per cell.
pub fn givens() -> ChannelField(SudokuDoc, ClaimsChannel) {
  schema.channel_field("givens")
}

/// The shared mistake tally.
pub fn mistakes() -> ChannelField(SudokuDoc, CounterChannel) {
  schema.channel_field("mistakes")
}
