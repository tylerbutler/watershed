//// The cell-key codec, exhaustively.
////
//// Every key in the document goes through `grid.encode`, and every remote
//// event comes back through `grid.decode`, so a bug here is a bug in every
//// pixel at once. The domain is 4096 pairs — small enough to check all of
//// them, which is stronger than any amount of sampling and needs no property
//// library (an example package only has gleeunit).

import gleam/list
import gleam/string
import gleeunit/should

import pixel_canvas_lustre/grid

/// Every cell in the grid, in the order `encode` is documented to sort into.
fn all_cells() -> List(#(Int, Int)) {
  grid.cells()
}

pub fn every_cell_round_trips_test() {
  all_cells()
  |> list.each(fn(cell) {
    let #(x, y) = cell
    grid.encode(x, y) |> grid.decode |> should.equal(Ok(#(x, y)))
  })
}

pub fn keys_are_zero_padded_to_a_fixed_width_test() {
  // Fixed width is what makes the keys sortable at all; without it "7,0" lands
  // between "60,0" and "8,0".
  grid.encode(7, 31) |> should.equal("07,31")
  grid.encode(0, 0) |> should.equal("00,00")
  grid.encode(63, 63) |> should.equal("63,63")

  all_cells()
  |> list.each(fn(cell) {
    grid.encode(cell.0, cell.1) |> string.length |> should.equal(5)
  })
}

pub fn encoded_keys_sort_into_grid_order_test() {
  let encoded = all_cells() |> list.map(fn(c) { grid.encode(c.0, c.1) })
  encoded |> list.sort(string.compare) |> should.equal(encoded)
}

pub fn decode_rejects_malformed_keys_test() {
  ["", "12", "12,", ",12", "a,b", "12,34,56", "1,2", "12 34"]
  |> list.each(fn(key) { grid.decode(key) |> should.equal(Error(Nil)) })
}

pub fn decode_rejects_out_of_range_cells_test() {
  // A peer on a larger grid must not be able to write past the end of the
  // buffer, so the bound is enforced on the way in rather than trusted.
  ["64,00", "00,64", "99,99"]
  |> list.each(fn(key) { grid.decode(key) |> should.equal(Error(Nil)) })
}

pub fn negative_coordinates_are_not_encodable_test() {
  // Pointer maths off the top-left edge produces these; they must not silently
  // become a key that decodes to somewhere else.
  grid.in_bounds(-1, 0) |> should.be_false
  grid.in_bounds(0, -1) |> should.be_false
  grid.in_bounds(0, 0) |> should.be_true
  grid.in_bounds(grid.size - 1, grid.size - 1) |> should.be_true
  grid.in_bounds(grid.size, 0) |> should.be_false
}
