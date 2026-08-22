//// The shared bitmap as a nested MVU triple.
////
//// The panel owns the palette, the pointer arithmetic, the `OrMap` of painted
//// cells, and the pixel buffer the FFI draws into. It does not own the offline
//// toggle or the diagnostics line that used to sit under it, and that is the
//// whole lesson of this rung: both take a `Document`, not a channel.
////
//// `go_offline` disconnects the *document*. As a button on this panel it reads
//// like "stop syncing the canvas"; composed, it stops syncing all four panels
//// at once — the same blast radius `clear(root)` has, arriving through a
//// completely different door. It cannot be scoped down, because the connection
//// is per-document and always was, so it is promoted instead: the owner puts it
//// in its chrome and labels it for what it is. Standalone that costs nothing;
//// composed it turns a one-panel demo into a four-panel one, where a single
//// click partitions a text buffer, a sequence, a claims grid, and this OR-map,
//// and coming back converges all four.
////
//// Peers are drawn as markers over the canvas rather than into it: the FFI owns
//// that surface outright, and Lustre must never diff its contents.

import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

import lustre/attribute.{class, id}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import watershed/or_map_kernel
import watershed.{type Document, type OrMap, type TypedMap}
import watershed_lustre

import pixel_canvas_lustre/canvas.{type Canvas}
import pixel_canvas_lustre/doc_schema
import pixel_canvas_lustre/grid

// ── Presence seam ────────────────────────────────────────────────────────────

/// A peer to mark on the canvas: the identity its owner resolved, and the cell
/// they last painted.
pub type Peer {
  Peer(name: String, color: String, cell: String)
}

// ── Model ────────────────────────────────────────────────────────────────────

pub opaque type Model {
  Model(
    pixels: Option(OrMap),
    /// The pixel buffer. Not part of the model's value in any meaningful
    /// sense — it is a handle to mutable JS state — but it has to be reachable
    /// from `update`, which is where document events arrive. It is also why an
    /// owner must keep this model once it exists: dropping it discards every
    /// painted cell this client has seen.
    canvas: Canvas,
    color: Int,
    /// The last cell painted in this stroke. The pointer fires far more often
    /// than it crosses a cell boundary, and this is the difference between
    /// tens of ops a second and hundreds.
    last_cell: Option(#(Int, Int)),
    /// The last cell painted at all, which is what a peer is shown standing on.
    /// Unlike `last_cell` it survives the end of a stroke, so a peer who has
    /// stopped painting does not blink out of the roster.
    cursor_cell: Option(#(Int, Int)),
    peers: List(Peer),
    last_error: Option(String),
  )
}

pub opaque type Msg {
  EnsuredPixels(Result(OrMap, String))
  PixelsChanged(or_map_kernel.OrMapEvent)
  PalettePicked(Int)
  PointerDown(Int, Int)
  PointerPainted(Int, Int)
  PointerUp
}

/// Seed the title and bootstrap the pixels `OrMap` under `map`.
///
/// Bootstrap belongs after the handshake, not on the handle. `ensure_*` retries
/// while *resolving* a channel someone else published, but seeding a new one is
/// a single attempt: against a document that is not ready, `create_or_map`
/// refuses outright with "requires a ready document connection" and the
/// callback fails for good. Waiting costs nothing, and is the difference
/// between a canvas that shares and one that silently paints only for itself.
pub fn init(
  document: Document(root),
  map: TypedMap(doc_schema.CanvasDoc),
) -> #(Model, Effect(Msg)) {
  let model =
    Model(
      pixels: None,
      canvas: canvas.create(),
      color: 1,
      last_cell: None,
      cursor_cell: None,
      peers: [],
      last_error: None,
    )
  #(
    model,
    effect.batch([
      watershed_lustre.ensure_field(
        map,
        doc_schema.title(),
        "watershed pixel canvas",
      ),
      watershed_lustre.ensure_or_map(
        document,
        map,
        doc_schema.pixels(),
        or_map_kernel.RegisterMode,
        EnsuredPixels,
      ),
    ]),
  )
}

// ── Update ───────────────────────────────────────────────────────────────────

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    EnsuredPixels(Ok(pixels)) -> {
      // The state a joiner walks in on, in one blit rather than 4096.
      canvas.paint_many(model.canvas, existing_cells(pixels))
      #(
        Model(..model, pixels: Some(pixels)),
        watershed_lustre.subscribe_or_map(pixels, PixelsChanged),
      )
    }
    EnsuredPixels(Error(reason)) -> #(
      Model(..model, last_error: Some(reason)),
      effect.none(),
    )

    PixelsChanged(event) -> {
      apply_event(model, event)
      #(model, effect.none())
    }

    PalettePicked(color) -> #(Model(..model, color: color), effect.none())

    PointerDown(x, y) -> #(
      paint(Model(..model, last_cell: None), x, y),
      effect.none(),
    )
    PointerPainted(x, y) -> #(paint(model, x, y), effect.none())
    PointerUp -> #(Model(..model, last_cell: None), effect.none())
  }
}

/// Where this client last painted, for the owner to broadcast.
pub fn cursor(model: Model) -> Option(String) {
  option.map(model.cursor_cell, fn(cell) { grid.encode(cell.0, cell.1) })
}

/// Mark these peers on the canvas.
pub fn set_peers(model: Model, peers: List(Peer)) -> Model {
  Model(..model, peers: peers)
}

/// The last bootstrap or paint failure, if any.
pub fn error(model: Model) -> Option(String) {
  model.last_error
}

/// Paint one cell, locally and in the document.
///
/// Three things are skipped, in order of how often they fire: cells outside the
/// grid (pointer maths near the edges), the cell already being painted in this
/// stroke, and a cell that is already the chosen colour. Only the last is
/// strictly about correctness — the other two exist because this is the one
/// example where the op rate is the thing being demonstrated.
fn paint(model: Model, x: Int, y: Int) -> Model {
  let fresh = model.last_cell != Some(#(x, y))
  case grid.in_bounds(x, y) && fresh {
    False -> model
    True -> {
      let model =
        Model(..model, last_cell: Some(#(x, y)), cursor_cell: Some(#(x, y)))
      case canvas.color_at(model.canvas, x, y) == model.color {
        True -> model
        False -> {
          // Optimistic: the cell is painted now, and the subscription confirms
          // it a microtask later.
          canvas.paint_cell(model.canvas, x, y, model.color)
          case model.pixels {
            None -> model
            Some(pixels) -> {
              watershed.or_map_set(
                pixels,
                grid.encode(x, y),
                int.to_string(model.color),
              )
              model
            }
          }
        }
      }
    }
  }
}

/// A remote (or re-confirmed local) change, straight into the pixel buffer.
fn apply_event(model: Model, event: or_map_kernel.OrMapEvent) -> Nil {
  case event {
    or_map_kernel.RegisterUpdated(key, value) ->
      case grid.decode(key), int.parse(value) {
        Ok(#(x, y)), Ok(color) if color >= 0 ->
          canvas.paint_cell(model.canvas, x, y, color)
        _, _ -> Nil
      }
    // This app never removes a key — erasing writes palette index 0 — but a
    // peer on a future version might, and clearing is the honest reading.
    or_map_kernel.KeyRemoved(key) ->
      case grid.decode(key) {
        Ok(#(x, y)) -> canvas.paint_cell(model.canvas, x, y, canvas.erase)
        Error(_) -> Nil
      }
    // Unreachable in `RegisterMode`; folded to nothing rather than crashed on.
    or_map_kernel.TallyUpdated(_, _, _) -> Nil
  }
}

/// Every painted cell in the document, as `#(x, y, colour)`.
fn existing_cells(pixels: OrMap) -> List(#(Int, Int, Int)) {
  watershed.or_map_entries(pixels)
  |> list.filter_map(fn(entry) {
    case entry.1 {
      or_map_kernel.Register(value) ->
        case grid.decode(entry.0), int.parse(value) {
          Ok(#(x, y)), Ok(color) -> Ok(#(x, y, color))
          _, _ -> Error(Nil)
        }
      or_map_kernel.Tally(_) -> Error(Nil)
    }
  })
}

// ── View ─────────────────────────────────────────────────────────────────────

pub fn view(model: Model) -> Element(Msg) {
  html.div([class("canvas-panel")], [
    palette_row(model),
    html.div([class("canvas-stage")], [
      canvas_element(),
      ..list.filter_map(model.peers, peer_marker)
    ]),
  ])
}

/// `canvas_ffi.mjs` owns the drawing surface, and Lustre has nothing here to
/// diff — `html.canvas` takes no children, so that much is enforced for us. The
/// `width` and `height` attributes are static for the same reason: re-setting
/// either one resets the surface and wipes the picture.
fn canvas_element() -> Element(Msg) {
  html.canvas([
    id("canvas"),
    attribute.attribute("width", int.to_string(grid.size)),
    attribute.attribute("height", int.to_string(grid.size)),
    attribute.attribute("role", "img"),
    attribute.attribute("aria-label", "Shared pixel canvas"),
    event.on("pointerdown", pointer_decoder(PointerDown)),
    event.on("pointermove", drag_decoder()),
    event.on("pointerup", decode.success(PointerUp)),
    event.on("pointerleave", decode.success(PointerUp)),
  ])
}

/// A peer's last cell, marked over the canvas rather than painted into it.
///
/// Percentage offsets rather than pixels, because the bitmap is 64x64 scaled up
/// by CSS and the rendered size is not known here.
fn peer_marker(peer: Peer) -> Result(Element(Msg), Nil) {
  case grid.decode(peer.cell) {
    Ok(#(x, y)) -> {
      let percent = fn(value: Int) {
        float.to_string(int.to_float(value) *. 100.0 /. int.to_float(grid.size))
        <> "%"
      }
      Ok(
        html.span(
          [
            class("peer-marker"),
            attribute.style("left", percent(x)),
            attribute.style("top", percent(y)),
            attribute.style("background", peer.color),
          ],
          [html.text(peer.name)],
        ),
      )
    }
    Error(_) -> Error(Nil)
  }
}

/// `pointermove`, but only while a button is held.
///
/// The filter belongs in the decoder rather than in `update`, because a decoder
/// that fails dispatches nothing at all — so merely hovering across the canvas
/// costs no messages and no re-renders. The obvious alternative, binding the
/// move listener only while a stroke is in progress, drops the start of every
/// stroke: the listener is not attached until Lustre has rendered the state
/// change that `pointerdown` caused, and moves arriving before that are lost.
fn drag_decoder() -> decode.Decoder(Msg) {
  use buttons <- decode.field("buttons", decode.int)
  case buttons {
    0 -> decode.failure(PointerUp, "not dragging")
    _ -> pointer_decoder(PointerPainted)
  }
}

/// The cell under the pointer.
///
/// `offsetX`/`offsetY` are in CSS pixels against the element's padding box, and
/// the element is a 64x64 bitmap scaled up by CSS, so the scale factor has to
/// come from the rendered size. Reading it here rather than in the FFI keeps
/// the arithmetic in Gleam and costs one property read per event.
fn pointer_decoder(to_msg: fn(Int, Int) -> Msg) -> decode.Decoder(Msg) {
  use offset_x <- decode.field("offsetX", number())
  use offset_y <- decode.field("offsetY", number())
  use width <- decode.subfield(["target", "clientWidth"], decode.int)
  use height <- decode.subfield(["target", "clientHeight"], decode.int)
  decode.success(to_msg(cell_of(offset_x, width), cell_of(offset_y, height)))
}

/// Pointer coordinates arrive as whole numbers as often as not, and Gleam's
/// JS runtime classifies those as `Int`, so a bare `decode.float` would fail
/// on exactly the common case.
fn number() -> decode.Decoder(Float) {
  decode.one_of(decode.float, [decode.int |> decode.map(int.to_float)])
}

/// Out-of-range values are returned as-is rather than clamped; `grid.in_bounds`
/// rejects them. Clamping would paint the edge cell when the pointer left the
/// canvas, which looks like a bug and is one.
fn cell_of(offset: Float, extent: Int) -> Int {
  case extent <= 0 {
    True -> -1
    False ->
      float.truncate(offset *. int.to_float(grid.size) /. int.to_float(extent))
  }
}

fn palette_row(model: Model) -> Element(Msg) {
  html.div([class("palette"), attribute.attribute("role", "group")], {
    use color <- list.map(indices(canvas.palette_size()))
    let name = case color == canvas.erase {
      True -> "Erase"
      False -> "Colour " <> int.to_string(color)
    }
    html.button(
      [
        class(case color == canvas.erase {
          True -> "swatch erase"
          False -> "swatch"
        }),
        attribute.attribute("style", swatch_style(color)),
        attribute.attribute("aria-pressed", bool_text(model.color == color)),
        attribute.attribute("aria-label", name),
        attribute.title(name),
        event.on_click(PalettePicked(color)),
      ],
      [],
    )
  })
}

fn swatch_style(color: Int) -> String {
  case list.drop(canvas.palette(), color) {
    [value, ..] if color != 0 -> "background:" <> value
    _ -> ""
  }
}

/// `0` to `count - 1`. See `grid.axis` for why this is a fold.
fn indices(count: Int) -> List(Int) {
  int.range(from: count - 1, to: -1, with: [], run: list.prepend)
}

fn bool_text(value: Bool) -> String {
  case value {
    True -> "true"
    False -> "false"
  }
}
