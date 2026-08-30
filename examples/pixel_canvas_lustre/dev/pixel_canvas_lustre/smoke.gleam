//// Headless smoke test: drive two `watershed` clients against a live
//// floodgate dev server (`just integration-up`) from Node and assert that the
//// canvas converges — the OR-map kernel in register mode, its wire codecs, the
//// JS runtime, the Phoenix FFI transport, and the pure core, end to end.
////
//// There is deliberately no canvas here. The pixel buffer is a rendering
//// concern with no collaborative content and no DOM to draw into under Node;
//// convergence is what a smoke test can actually check.
////
//// The offline leg is the part the sluice cannot cover. `sluice_js` fakes the
//// socket, so it can prove the *kernel* joins correctly across a gap but not
//// that `go_offline` actually holds a phoenix socket down and that the rejoin
//// flushes what was painted meanwhile. That path only exists against a real
//// server, and this is where it runs for the canvas specifically — the runtime
//// behaviour underneath it is covered on its own by watershed's
//// `test/live_js.gleam` (`just integration-run-js`).
////
//// Run via `smoke/run.mjs`, which supplies a WebSocket global.

import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{type Option, Some}
import gleam/string

import watershed.{type Document, type OrMap, WatershedConfig}
import watershed/or_map_kernel

import pixel_canvas_lustre/document_schema
import pixel_canvas_lustre/grid

const url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const secret = "levee-dev-secret-change-in-production"

@external(javascript, "./smoke_ffi.mjs", "delay")
fn delay(milliseconds: Int, callback: fn() -> Nil) -> Nil

@external(javascript, "./smoke_ffi.mjs", "log")
fn log(message: String) -> Nil

@external(javascript, "./smoke_ffi.mjs", "exit")
fn exit(code: Int) -> Nil

fn connect_client(
  document: String,
  user: String,
) -> Promise(Document(document_schema.CanvasDocument)) {
  use token <- promise.map(watershed.dev_token(secret, tenant, document, user))
  watershed.connect(
    WatershedConfig(
      url: url,
      tenant: tenant,
      document: document,
      token: token,
      user_id: user,
    ),
    on_ready: fn(result) {
      case result {
        Ok(_) -> log("  " <> user <> " ready")
        Error(reason) -> log("  " <> user <> " FAILED: " <> reason)
      }
    },
  )
}

pub fn main() -> Nil {
  let document = "pixel-smoke-" <> int.to_string(100_000 + int.random(900_000))
  log("smoke: document " <> document)

  let _ = {
    use document_a <- promise.await(connect_client(document, "user-a"))
    use document_b <- promise.map(connect_client(document, "user-b"))
    run_scenario(document_a, document_b)
  }
  Nil
}

fn run_scenario(
  document_a: Document(document_schema.CanvasDocument),
  document_b: Document(document_schema.CanvasDocument),
) -> Nil {
  // Let both handshakes land before anyone attaches a channel.
  use <- delay(2000)
  log("smoke: ensuring the pixels channel on A")

  watershed.ensure_or_map(
    document_a,
    watershed.root_typed(document_a),
    document_schema.pixels(),
    or_map_kernel.RegisterMode,
    fn(result) {
      case result {
        Error(reason) -> {
          log("SMOKE FAIL: A could not ensure the pixels channel: " <> reason)
          exit(1)
        }
        Ok(pixels_a) -> adopt_on_b(document_a, document_b, pixels_a)
      }
    },
  )
}

fn adopt_on_b(
  document_a: Document(document_schema.CanvasDocument),
  document_b: Document(document_schema.CanvasDocument),
  pixels_a: OrMap,
) -> Nil {
  // B adopts the same channel rather than creating its own — `ensure_or_map`
  // resolves the handle A just published.
  use <- delay(1500)
  watershed.ensure_or_map(
    document_b,
    watershed.root_typed(document_b),
    document_schema.pixels(),
    or_map_kernel.RegisterMode,
    fn(result) {
      case result {
        Error(reason) -> {
          log("SMOKE FAIL: B could not adopt the pixels channel: " <> reason)
          exit(1)
        }
        Ok(pixels_b) -> paint_scenario(document_a, pixels_a, pixels_b)
      }
    },
  )
}

fn paint_scenario(
  document_a: Document(document_schema.CanvasDocument),
  a: OrMap,
  b: OrMap,
) -> Nil {
  log("smoke: A paints a short row")
  let row = [1, 2, 3, 4]
  list.each(row, fn(x) { paint(a, x, 5, 9) })

  use <- delay(1500)
  let seeded = list.all(row, fn(x) { color_at(b, x, 5) == Some("9") })
  log("  B sees " <> summarise(b))

  // Disjoint regions painted at the same time must not interfere: this is the
  // whole reason a canvas is an OR-map and not a single shared value.
  log("smoke: both paint different regions at once")
  paint(a, 10, 10, 4)
  paint(b, 50, 50, 12)
  use <- delay(1500)
  let disjoint =
    color_at(b, 10, 10) == Some("4") && color_at(a, 50, 50) == Some("12")

  // Erase is a colour, not a removal, so the key stays and both agree on it.
  log("smoke: A erases one cell")
  paint(a, 1, 5, 0)
  use <- delay(1500)
  let erased = color_at(b, 1, 5) == Some("0")

  // The offline toggle, against a real socket — both legs.
  //
  // This is the part the sluice cannot cover, and for a while it was only half
  // asserted: the JS runtime never finished catching up after a reconnect that
  // spanned sequenced operations, so the return leg was left out with a pointer
  // to `docs/plans/2026-08-09-js-reconnect-catchup-defect.md`. The runtime now
  // requests its own gap on the handshake, so coming back is checked here too.
  log("smoke: A goes offline and keeps painting")
  watershed.go_offline(document_a)
  use <- delay(500)
  let held = watershed.diagnostics(document_a).phase == "reconnecting"

  let stroke = [20, 21, 22, 23]
  list.each(stroke, fn(x) { paint(a, x, 30, 6) })
  // B paints too, so the return leg has to merge in both directions rather
  // than just flush A's backlog.
  paint(b, 40, 40, 11)
  use <- delay(1000)
  // Held means held: none of it has crossed, either way.
  let isolated =
    color_at(b, 21, 30) == option.None && color_at(a, 40, 40) == option.None
  log("  A while offline: " <> diagnostic_line(document_a))

  log("smoke: A comes back")
  watershed.go_online(document_a)
  use <- delay(3000)
  // Every cell of the offline stroke arrives, not just the last one — a flush
  // that dropped all but the newest write per key would still look like a
  // convergence if only one cell were checked.
  let flushed = list.all(stroke, fn(x) { color_at(b, x, 30) == Some("6") })
  let caught_up = color_at(a, 40, 40) == Some("11")
  log("  A after rejoin: " <> diagnostic_line(document_a))

  case
    seeded && disjoint && erased && held && isolated && flushed && caught_up
  {
    True -> {
      log(
        "SMOKE PASS: the canvas converged, and the offline toggle round-trips",
      )
      exit(0)
    }
    False -> {
      log(
        "SMOKE FAIL: seeded="
        <> bool_to_string(seeded)
        <> " disjoint="
        <> bool_to_string(disjoint)
        <> " erased="
        <> bool_to_string(erased)
        <> " held="
        <> bool_to_string(held)
        <> " isolated="
        <> bool_to_string(isolated)
        <> " flushed="
        <> bool_to_string(flushed)
        <> " caught_up="
        <> bool_to_string(caught_up)
        <> " (A="
        <> summarise(a)
        <> " B="
        <> summarise(b)
        <> ")",
      )
      exit(1)
    }
  }
}

fn paint(pixels: OrMap, x: Int, y: Int, color: Int) -> Nil {
  watershed.or_map_set(pixels, grid.encode(x, y), int.to_string(color))
}

fn color_at(pixels: OrMap, x: Int, y: Int) -> Option(String) {
  case watershed.or_map_value(pixels, grid.encode(x, y)) {
    Ok(or_map_kernel.Register(value)) -> Some(value)
    _ -> option.None
  }
}

/// A compact "how many cells, which colours" line for the failure message —
/// dumping 4096 keys would bury the thing that went wrong.
fn summarise(pixels: OrMap) -> String {
  let keys = watershed.or_map_keys(pixels)
  int.to_string(list.length(keys))
  <> " cells ["
  <> string.join(list.take(list.sort(keys, string.compare), 6), " ")
  <> "]"
}

fn diagnostic_line(
  document: Document(document_schema.CanvasDocument),
) -> String {
  let diagnostics = watershed.diagnostics(document)
  diagnostics.phase
  <> " last_seen="
  <> option_int(diagnostics.last_seen_sequence_number)
  <> " next_csn="
  <> option_int(diagnostics.next_client_sequence_number)
  <> " in_flight="
  <> int.to_string(diagnostics.in_flight_count)
  <> " buffered="
  <> int.to_string(diagnostics.buffered_out_of_order_count)
  <> " resubmit="
  <> option_int(diagnostics.resubmit_checkpoint)
  <> " synced="
  <> bool_to_string(diagnostics.synced)
}

fn option_int(value: Option(Int)) -> String {
  case value {
    Some(n) -> int.to_string(n)
    option.None -> "-"
  }
}

fn bool_to_string(b: Bool) -> String {
  case b {
    True -> "true"
    False -> "false"
  }
}
