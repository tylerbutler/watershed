//// Two clients painting the same canvas, with no server and no browser.
////
//// The demo makes its argument visually — two tabs either end up with the same
//// picture or they do not — and these are the same claims asserted, so a
//// regression fails a test instead of quietly looking slightly wrong. The
//// in-memory `sluice_js` delivers every frame explicitly, so `settle` drains
//// the room before the assertions read it and there is nothing to wait for.
////
//// The offline tests are the interesting ones. `or_map_kernel` advances by
//// joining sparse deltas, so a client that paints while disconnected does not
//// replay its ops on return — the two states *join*. That is the claim the
//// offline toggle exists to demonstrate, and it is asserted here through the
//// same `watershed.go_offline` the button calls.
////
//// The canvas FFI is deliberately untested: it is pure rendering, and these
//// tests cover the state it renders from.

import gleam/int
import gleam/list
import gleam/option.{type Option, Some}
import gleam/string
import gleeunit/should
import pixel_canvas_lustre/doc_schema

import watershed.{type Document, type OrMap}
import watershed/or_map_kernel
import watershed/sluice_js.{type Sluice}

import pixel_canvas_lustre/grid

// ── Harness ──────────────────────────────────────────────────────────────────

/// A room with the `pixels` channel seeded and both clients holding it.
///
/// The app bootstraps this with `ensure_or_map`, which resolves through a retry
/// loop on a timer. That is right in a browser and wrong here — the sluice's
/// whole point is synchronous, deterministic delivery — so the test seeds the
/// handle directly and keeps the assertions free of waiting.
fn room(
  name: String,
) -> #(
  Sluice,
  Document(doc_schema.CanvasDoc),
  Document(doc_schema.CanvasDoc),
  OrMap,
  OrMap,
) {
  let sluice = sluice_js.start(tenant: "default", document: name)
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  let assert Ok(seed) =
    watershed.create_or_map(doc_a, or_map_kernel.RegisterMode)
  watershed.set(
    watershed.root(doc_a),
    "pixels",
    watershed.or_map_handle_of(seed),
  )
  sluice_js.settle(sluice)

  #(sluice, doc_a, doc_b, pixels_of(doc_a), pixels_of(doc_b))
}

fn pixels_of(doc: Document(doc_schema.CanvasDoc)) -> OrMap {
  let assert Some(handle) = watershed.get(watershed.root(doc), "pixels")
  let assert Ok(pixels) = watershed.resolve_or_map(doc, handle)
  pixels
}

/// Paint a cell exactly as the app does.
fn paint(pixels: OrMap, x: Int, y: Int, color: Int) -> Nil {
  watershed.or_map_set(pixels, grid.encode(x, y), int.to_string(color))
}

/// The palette index at a cell, as the app reads it back.
fn color_at(pixels: OrMap, x: Int, y: Int) -> Option(String) {
  case watershed.or_map_value(pixels, grid.encode(x, y)) {
    Some(or_map_kernel.Register(value)) -> Some(value)
    _ -> option.None
  }
}

/// The whole picture, sorted — the comparison the demo makes by eye.
fn picture(pixels: OrMap) -> List(#(String, String)) {
  watershed.or_map_entries(pixels)
  |> list.filter_map(fn(entry) {
    case entry.1 {
      or_map_kernel.Register(value) -> Ok(#(entry.0, value))
      or_map_kernel.Tally(_) -> Error(Nil)
    }
  })
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
}

// ── Tests ────────────────────────────────────────────────────────────────────

pub fn two_clients_painting_disjoint_regions_converge_test() {
  let #(sluice, _doc_a, _doc_b, a, b) = room("pixel-disjoint")

  // A paints a short row, B paints a column somewhere else.
  list.each([0, 1, 2, 3], fn(x) { paint(a, x, 10, 4) })
  list.each([20, 21, 22], fn(y) { paint(b, 40, y, 9) })
  sluice_js.settle(sluice)

  picture(a) |> should.equal(picture(b))
  color_at(b, 2, 10) |> should.equal(Some("4"))
  color_at(a, 40, 21) |> should.equal(Some("9"))
}

pub fn painting_the_same_cell_settles_on_one_colour_test() {
  let #(sluice, _doc_a, _doc_b, a, b) = room("pixel-same-cell")

  // The most likely collision in the app: two people reaching for one pixel.
  // Which colour wins is the kernel's business and is deliberately not asserted
  // — only that the room agrees, which is what the reader checks by eye.
  paint(a, 32, 32, 4)
  paint(b, 32, 32, 8)
  sluice_js.settle(sluice)

  color_at(a, 32, 32) |> should.equal(color_at(b, 32, 32))
  color_at(a, 32, 32) |> option.is_some |> should.be_true
}

pub fn erasing_writes_a_colour_rather_than_removing_a_key_test() {
  let #(sluice, _doc_a, _doc_b, a, b) = room("pixel-erase")

  paint(a, 5, 5, 7)
  sluice_js.settle(sluice)
  color_at(b, 5, 5) |> should.equal(Some("7"))

  // A canvas has no notion of an absent pixel, so erase is palette index 0.
  // Keeping the key also avoids the remove/re-add tombstone paths, which are
  // not what this example is about.
  paint(a, 5, 5, 0)
  sluice_js.settle(sluice)
  color_at(b, 5, 5) |> should.equal(Some("0"))
  watershed.or_map_keys(b)
  |> list.contains(grid.encode(5, 5))
  |> should.be_true
}

pub fn a_late_joiner_replays_the_picture_test() {
  let #(sluice, _doc_a, _doc_b, a, _b) = room("pixel-late-join")

  list.each([1, 2, 3], fn(x) { paint(a, x, 1, 6) })
  sluice_js.settle(sluice)

  // Someone opening a third tab sees what is already on the canvas.
  let doc_c = sluice_js.connect(sluice, "user-c")
  sluice_js.settle(sluice)

  picture(pixels_of(doc_c)) |> should.equal(picture(a))
}

// ── The offline toggle ───────────────────────────────────────────────────────

pub fn regions_painted_while_offline_join_on_reconnect_test() {
  let #(sluice, doc_a, _doc_b, a, b) = room("pixel-offline-join")

  watershed.go_offline(doc_a)
  sluice_js.settle(sluice)

  // Both keep painting, in different places, neither hearing the other.
  list.each([0, 1, 2], fn(x) { paint(a, x, 0, 4) })
  list.each([0, 1, 2], fn(x) { paint(b, x, 63, 9) })
  sluice_js.settle(sluice)

  // Still apart: A's work is optimistically its own, and B has not seen it.
  color_at(a, 1, 0) |> should.equal(Some("4"))
  color_at(b, 1, 0) |> should.equal(option.None)

  watershed.go_online(doc_a)
  sluice_js.settle(sluice)

  // The union, on both — by join, with no rebase and no replay.
  picture(a) |> should.equal(picture(b))
  color_at(b, 1, 0) |> should.equal(Some("4"))
  color_at(a, 1, 63) |> should.equal(Some("9"))
}

pub fn a_cell_contested_across_an_offline_window_converges_test() {
  let #(sluice, doc_a, _doc_b, a, b) = room("pixel-offline-contested")

  watershed.go_offline(doc_a)
  sluice_js.settle(sluice)

  paint(a, 8, 8, 4)
  paint(b, 8, 8, 12)
  sluice_js.settle(sluice)

  watershed.go_online(doc_a)
  sluice_js.settle(sluice)

  // Same claim as the live collision, across a much wider window: the demo may
  // not promise which colour wins, only that both tabs show the same one.
  color_at(a, 8, 8) |> should.equal(color_at(b, 8, 8))
  color_at(a, 8, 8) |> option.is_some |> should.be_true
  picture(a) |> should.equal(picture(b))
}

pub fn a_whole_stroke_made_offline_arrives_on_reconnect_test() {
  let #(sluice, doc_a, _doc_b, a, b) = room("pixel-offline-stroke")

  paint(a, 0, 2, 4)
  sluice_js.settle(sluice)

  watershed.go_offline(doc_a)
  sluice_js.settle(sluice)

  // A drag's worth of cells, not one cell repainted: this is the shape an
  // offline stroke actually has, and every cell in it has to survive the gap.
  let stroke = [1, 2, 3, 4, 5, 6, 7, 8]
  list.each(stroke, fn(x) { paint(a, x, 2, 11) })
  sluice_js.settle(sluice)
  color_at(b, 4, 2) |> should.equal(option.None)

  watershed.go_online(doc_a)
  sluice_js.settle(sluice)

  list.each(stroke, fn(x) { color_at(b, x, 2) |> should.equal(Some("11")) })
  color_at(b, 0, 2) |> should.equal(Some("4"))
  picture(a) |> should.equal(picture(b))
}

pub fn repainting_one_cell_offline_converges_test() {
  let #(sluice, doc_a, _doc_b, a, b) = room("pixel-offline-repaint")

  watershed.go_offline(doc_a)
  sluice_js.settle(sluice)

  // Going back over a cell you have already painted, while away.
  //
  // Deliberately no assertion about *which* colour survives. Register leaves
  // are last-writer-wins on a millisecond wall clock, tie-broken by replica id,
  // and this loop writes far faster than the clock ticks — so among writes that
  // share a millisecond the winner is the earliest, not the latest. The demo
  // never promises which colour wins a race, only that the room agrees on one,
  // and that is what this pins.
  list.each([5, 6, 7, 11], fn(color) { paint(a, 2, 2, color) })
  sluice_js.settle(sluice)

  watershed.go_online(doc_a)
  sluice_js.settle(sluice)

  color_at(a, 2, 2) |> should.equal(color_at(b, 2, 2))
  color_at(a, 2, 2) |> option.is_some |> should.be_true
  picture(a) |> should.equal(picture(b))
}
