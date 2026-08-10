//// A shared 64x64 bitmap: convergence you can check with your eyes.
////
//// Every other example in this repo proves convergence by assertion — the dice
//// example shows a number, sudoku a grid of digits, the scoreboard a total —
//// and the reader has to accept that the number is right. Two tabs painting
//// over each other either produce the same picture or they do not, and nobody
//// has to read a line of Gleam to adjudicate it.
////
//// It is also the one example that stresses op volume. Dragging the brush
//// emits an op per cell crossed, so a few seconds of scribbling in two tabs is
//// thousands of ops through a path that elsewhere only ever sees one keystroke
//// at a time. Two things keep that honest: cells are deduped, so a drag emits
//// one op per cell entered rather than one per pointer event, and the pixels
//// live in a `<canvas>` the FFI owns outright rather than in 4096 vdom nodes.
////
//// The offline toggle is the point, not a bonus. `or_map_kernel` advances by
//// joining sparse deltas, so two clients that paint disjoint regions while
//// disconnected converge by *join* when they come back — no rebase, no op
//// replay, no server arbitration.

import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

import lustre
import lustre/attribute.{class, id}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import watershed/or_map_kernel
import watershed_js.{type Document, type OrMap}
import watershed_lustre

import canvas.{type Canvas}
import doc_schema
import grid

// ── Dev config for `just integration-up` (floodgate dev mode) ────────────────

const socket_url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

const document_id = "pixel-canvas"

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

// ── Model ────────────────────────────────────────────────────────────────────

type Status {
  Connecting
  Ready
  Failed(reason: String)
}

type Model {
  Model(
    status: Status,
    doc: Option(Document),
    pixels: Option(OrMap),
    /// The pixel buffer. Not part of the model's value in any meaningful
    /// sense — it is a handle to mutable JS state — but it has to be reachable
    /// from `update`, which is where document events arrive.
    canvas: Canvas,
    user_id: String,
    color: Int,
    /// The last cell painted in this stroke. The pointer fires far more often
    /// than it crosses a cell boundary, and this is the difference between
    /// tens of ops a second and hundreds.
    last_cell: Option(#(Int, Int)),
    offline: Bool,
    diagnostics: Option(watershed_js.Diagnostics),
    last_error: Option(String),
  )
}

type Msg {
  GotHandle(Document)
  Connected(Result(Nil, String))
  EnsuredPixels(Result(OrMap, String))
  PixelsChanged(or_map_kernel.OrMapEvent)
  DiagnosticsTick
  PalettePicked(Int)
  PointerDown(Int, Int)
  PointerPainted(Int, Int)
  PointerUp
  ToggledOffline(Bool)
}

fn init(_args) -> #(Model, Effect(Msg)) {
  // A distinct user per tab, so two tabs are two clients rather than one.
  let user_id = "web-" <> int.to_string(1000 + int.random(9000))
  let model =
    Model(
      status: Connecting,
      doc: None,
      pixels: None,
      canvas: canvas.create(),
      user_id: user_id,
      color: 1,
      last_cell: None,
      offline: False,
      diagnostics: None,
      last_error: None,
    )
  #(
    model,
    watershed_lustre.connect_dev(
      url: socket_url,
      tenant: tenant,
      secret: tenant_secret,
      document: document_id,
      user_id: user_id,
      got_document: GotHandle,
      connected: Connected,
    ),
  )
}

// ── Update ───────────────────────────────────────────────────────────────────

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    // The handle exists, but the handshake has not landed yet — so there is
    // nothing to bootstrap on here, only diagnostics to start polling.
    GotHandle(doc) -> #(
      Model(
        ..model,
        doc: Some(doc),
        diagnostics: Some(watershed_js.diagnostics(doc)),
      ),
      watershed_lustre.after(250, DiagnosticsTick),
    )

    // Bootstrap belongs here rather than on `GotHandle`. `ensure_*` retries
    // while *resolving* a channel someone else published, but seeding a new one
    // is a single attempt: against a document whose root map is still empty,
    // `create_or_map` refuses outright with "requires a ready document
    // connection" and the callback fails for good. Waiting for the handshake
    // costs nothing, and is the difference between a canvas that shares and one
    // that silently paints only for itself.
    Connected(Ok(_)) ->
      case model.doc {
        None -> #(Model(..model, status: Ready), effect.none())
        Some(doc) -> {
          let root = watershed_js.root_typed(doc)
          #(
            Model(..model, status: Ready),
            effect.batch([
              watershed_lustre.ensure_field(
                root,
                doc_schema.title(),
                "watershed pixel canvas",
              ),
              watershed_lustre.ensure_or_map(
                doc,
                root,
                doc_schema.pixels(),
                or_map_kernel.RegisterMode,
                EnsuredPixels,
              ),
            ]),
          )
        }
      }
    Connected(Error(reason)) -> #(
      Model(..model, status: Failed(reason), last_error: Some(reason)),
      effect.none(),
    )

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

    DiagnosticsTick ->
      case model.doc {
        None -> #(model, effect.none())
        Some(doc) -> #(
          Model(..model, diagnostics: Some(watershed_js.diagnostics(doc))),
          watershed_lustre.after(250, DiagnosticsTick),
        )
      }

    PalettePicked(color) -> #(Model(..model, color: color), effect.none())

    PointerDown(x, y) -> #(
      paint(Model(..model, last_cell: None), x, y),
      effect.none(),
    )
    PointerPainted(x, y) -> #(paint(model, x, y), effect.none())
    PointerUp -> #(Model(..model, last_cell: None), effect.none())

    ToggledOffline(offline) ->
      case model.doc {
        None -> #(model, effect.none())
        Some(doc) -> #(Model(..model, offline: offline), case offline {
          True -> watershed_lustre.go_offline(doc)
          False -> watershed_lustre.go_online(doc)
        })
      }
  }
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
      let model = Model(..model, last_cell: Some(#(x, y)))
      case canvas.color_at(model.canvas, x, y) == model.color {
        True -> model
        False -> {
          // Optimistic: the cell is painted now, and the subscription confirms
          // it a microtask later.
          canvas.paint_cell(model.canvas, x, y, model.color)
          case model.pixels {
            None -> model
            Some(pixels) -> {
              watershed_js.or_map_set(
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
  watershed_js.or_map_entries(pixels)
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

fn view(model: Model) -> Element(Msg) {
  html.div([class("app")], [
    html.h1([], [html.text("watershed · pixel canvas")]),
    html.p([class("status")], [html.text(status_line(model))]),
    palette_row(model),
    canvas_element(),
    toolbar(model),
    html.p([class("hint")], [
      html.text(
        "Open a second tab on the same URL and paint over the same cells. "
        <> "Go offline in one, keep painting in both, then come back.",
      ),
    ]),
    error_line(model),
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

/// The cell under the pointer.
///
/// `offsetX`/`offsetY` are in CSS pixels against the element's padding box, and
/// the element is a 64x64 bitmap scaled up by CSS, so the scale factor has to
/// come from the rendered size. Reading it here rather than in the FFI keeps
/// the arithmetic in Gleam and costs one property read per event.
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

fn toolbar(model: Model) -> Element(Msg) {
  let connected = option.is_some(model.doc)
  html.div([class("toolbar")], [
    html.button(
      [
        event.on_click(ToggledOffline(!model.offline)),
        attribute.attribute("aria-pressed", bool_text(model.offline)),
        attribute.disabled(!connected),
      ],
      [
        html.span([], [
          html.text(case model.offline {
            True -> "Come back online"
            False -> "Go offline"
          }),
        ]),
      ],
    ),
  ])
}

fn status_line(model: Model) -> String {
  let phase = case model.status, model.diagnostics {
    Failed(reason), _ -> "failed · " <> reason
    _, Some(diagnostics) -> diagnostics.phase
    Connecting, None -> "connecting"
    Ready, None -> "ready"
  }
  // `in_flight_count` is the real "waiting to reach the server" number: while
  // the socket is held, every painted cell lands there and stays.
  let waiting = case model.offline, model.diagnostics {
    True, Some(diagnostics) ->
      " · offline, "
      <> int.to_string(diagnostics.in_flight_count)
      <> " cells held"
    True, None -> " · offline"
    False, _ -> ""
  }
  "you are " <> model.user_id <> " · " <> phase <> waiting
}

fn error_line(model: Model) -> Element(Msg) {
  case model.last_error {
    None -> element.none()
    Some(reason) -> html.p([class("error")], [html.text(reason)])
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
