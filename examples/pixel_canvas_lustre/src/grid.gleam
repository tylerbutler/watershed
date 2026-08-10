//// The canvas geometry and its cell-key codec.
////
//// One document key per cell, `"<x>,<y>"`, zero-padded to the width of the
//// largest coordinate: `"07,31"`. The padding is not decoration. Unpadded keys
//// sort as text, which puts `"7,0"` between `"60,0"` and `"8,0"` — so a fixed
//// width is what makes a dump of the summary blob readable as a picture rather
//// than as scrambled coordinates.
////
//// Sorted, the keys walk the grid column by column (all of x=00 top to bottom,
//// then all of x=01), because the x coordinate is the leading field.
////
//// `decode` is total and range-checked. Keys arrive from other clients, and a
//// peer running a future version with a larger grid must not be able to write
//// past the end of a 64x64 buffer.

import gleam/int
import gleam/list
import gleam/result
import gleam/string

/// Cells per side. 4096 cells is enough to look like a picture and few enough
/// that reading the whole map stays honest.
pub const size = 64

/// Digits per coordinate. Derived by hand from `size` rather than computed:
/// Gleam constants cannot call functions, and a mismatch is caught by
/// `keys_are_zero_padded_to_a_fixed_width_test`.
const width = 2

/// Whether `#(x, y)` names a cell on the canvas. Pointer arithmetic near the
/// edges produces out-of-range values, and they must be rejected rather than
/// clamped — clamping would paint the wrong cell instead of no cell.
pub fn in_bounds(x: Int, y: Int) -> Bool {
  x >= 0 && y >= 0 && x < size && y < size
}

/// The document key for a cell. Callers are expected to have checked
/// `in_bounds` already; out-of-range coordinates still encode, they just do not
/// decode again.
pub fn encode(x: Int, y: Int) -> String {
  pad(x) <> "," <> pad(y)
}

/// The cell a document key names, or `Error(Nil)` for anything that is not a
/// well-formed in-range key.
pub fn decode(key: String) -> Result(#(Int, Int), Nil) {
  case string.split(key, ",") {
    [raw_x, raw_y] -> {
      use x <- result.try(coordinate(raw_x))
      use y <- result.try(coordinate(raw_y))
      Ok(#(x, y))
    }
    _ -> Error(Nil)
  }
}

/// One field of a key: exactly `width` digits, in range.
fn coordinate(raw: String) -> Result(Int, Nil) {
  case string.length(raw) == width {
    False -> Error(Nil)
    True ->
      case int.parse(raw) {
        // `int.parse` accepts a leading sign, which would let "-1" through as a
        // two-character field, so the range check has to do the real work.
        Ok(value) if value >= 0 && value < size -> Ok(value)
        _ -> Error(Nil)
      }
  }
}

fn pad(value: Int) -> String {
  int.to_string(value) |> string.pad_start(to: width, with: "0")
}

/// `0` to `size - 1`, ascending. Built by folding down to `-1` (the bound is
/// exclusive) and prepending, which lands the list in ascending order without a
/// reverse.
pub fn axis() -> List(Int) {
  int.range(from: size - 1, to: -1, with: [], run: list.prepend)
}

/// Every cell on the canvas, column by column — the order `encode` sorts into.
/// Used to seed a full repaint.
pub fn cells() -> List(#(Int, Int)) {
  list.flat_map(axis(), fn(x) { list.map(axis(), fn(y) { #(x, y) }) })
}
