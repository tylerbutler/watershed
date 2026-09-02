//// Typed schema for the collaborative Sudoku root document.
////
//// The root map carries two plain values (`puzzle`, `title`) and four handles
//// to nested channels (`cells`, `notes`, `givens`, `mistakes`). Declaring the
//// six slots once here replaces the hand-written key constants the example
//// used to carry, and lets `ensure_*` bootstrap each channel from the field
//// alone.
////
//// `cells` is a `ChannelField(MapChannel)` rather than a `ChildField`: it is a
//// dynamic map keyed by cell position (`r{row}c{column}`), with no per-key
//// record schema to derive, so `ensure_map` hands back the raw `SharedMap` the
//// grid reads and writes directly.

import gleam/dynamic/decode
import gleam/json
import watershed/schema.{
  type ChannelField, type ClaimsChannel, type CounterChannel, type Field,
  type MapChannel, type OrSetChannel,
}

// docs:snippet-start sharedtree-nest
/// Phantom tag scoping every field below to the Sudoku root map.
pub type SudokuDocument

/// The active puzzle's id (see `puzzle.by_id`).
pub fn puzzle() -> Field(SudokuDocument, String) {
  schema.field("puzzle", json.string, decode.string)
}

/// The document title, shown in the status line.
pub fn title() -> Field(SudokuDocument, String) {
  schema.field("title", json.string, decode.string)
}

/// The player-entered digits, keyed `r{row}c{column}` → digit.
pub fn cells() -> ChannelField(SudokuDocument, MapChannel) {
  schema.channel_field("cells")
  // last write wins, per key
}

/// The pencil-mark notes, as `r{row}c{column}={digit}` set elements.
pub fn notes() -> ChannelField(SudokuDocument, OrSetChannel) {
  schema.channel_field("notes")
  // add wins over a concurrent remove
}

/// The puzzle's immutable givens, first-writer-wins claims per cell.
pub fn givens() -> ChannelField(SudokuDocument, ClaimsChannel) {
  schema.channel_field("givens")
  // the first writer owns the slot
}

/// The shared mistake tally.
pub fn mistakes() -> ChannelField(SudokuDocument, CounterChannel) {
  schema.channel_field("mistakes")
  // commutative increments
}
// docs:snippet-end sharedtree-nest
