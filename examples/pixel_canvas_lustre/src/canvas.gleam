//// Gleam bindings to the pixel buffer in `canvas_ffi.mjs`, plus the palette.
////
//// The split mirrors the drum machine's: watershed owns the collaborative
//// state, the FFI owns the pixels, and the FFI never calls back. Gleam pushes
//// cells in as document events land; nothing in the render path can make a
//// document read slower, and nothing in the document path can make a frame
//// drop.
////
//// Everything here mutates a JS object, so every function returns `Nil`.

import gleam/javascript/array.{type Array}
import gleam/json
import gleam/list

/// The pixel buffer and its drawing context. Opaque: nothing outside
/// `canvas_ffi.mjs` may look inside it.
pub type Canvas

/// Palette index `0`. Painting it clears the cell rather than filling it, so an
/// erased pixel shows the element's CSS background and the canvas follows
/// light/dark mode without the app knowing which one is in force.
pub const erase = 0

/// The palette, index `0` first. Fifteen colours plus erase: enough to draw
/// something recognisable, few enough to fit one row of swatches and to keep a
/// value one or two characters wide on the wire.
///
/// Index `0`'s entry is never drawn — it is the erase slot — but it is present
/// so the list index and the palette index stay the same number.
pub fn palette() -> List(String) {
  [
    "transparent", "#000000", "#ffffff", "#7f7f7f", "#e6194b", "#f58231",
    "#ffe119", "#bfef45", "#3cb44b", "#42d4f4", "#4363d8", "#911eb4", "#f032e6",
    "#fabed4", "#9a6324", "#469990",
  ]
}

/// The number of palette entries, erase included.
pub fn palette_size() -> Int {
  list.length(palette())
}

@external(javascript, "./canvas_ffi.mjs", "createCanvas")
fn create_ffi(palette_json: String) -> Canvas

/// Allocate the buffer. Called once, outside the effect system, exactly as the
/// drum machine creates its audio engine.
pub fn create() -> Canvas {
  create_ffi(json.to_string(json.array(palette(), json.string)))
}

/// Write one cell and draw it. Safe before the element exists — the write lands
/// in the buffer either way, and is flushed when the canvas turns up.
@external(javascript, "./canvas_ffi.mjs", "paintCell")
pub fn paint_cell(canvas: Canvas, x: Int, y: Int, color: Int) -> Nil

@external(javascript, "./canvas_ffi.mjs", "paintMany")
fn paint_many_ffi(
  canvas: Canvas,
  xs: Array(Int),
  ys: Array(Int),
  colors: Array(Int),
) -> Nil

/// Seed many cells at once, for the state a joiner receives in one go.
pub fn paint_many(canvas: Canvas, cells: List(#(Int, Int, Int))) -> Nil {
  paint_many_ffi(
    canvas,
    cells |> list.map(fn(c) { c.0 }) |> array.from_list,
    cells |> list.map(fn(c) { c.1 }) |> array.from_list,
    cells |> list.map(fn(c) { c.2 }) |> array.from_list,
  )
}

/// The palette index currently at a cell.
@external(javascript, "./canvas_ffi.mjs", "colorAt")
pub fn color_at(canvas: Canvas, x: Int, y: Int) -> Int
