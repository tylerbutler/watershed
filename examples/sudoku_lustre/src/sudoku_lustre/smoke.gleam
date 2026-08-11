//// Headless smoke test for the watershed presence driver: drive two
//// `watershed_js` clients against a live levee dev server (`just server`) from
//// Node and assert that a presence payload announced by one client reaches the
//// other's roster via `watershed/presence_js`. This exercises the full ripple
//// path end-to-end — the transport FFI `signal` listener + `submitSignal` push,
//// `runtime_js` send/receive, the `wire/socket` codecs, and the presence driver
//// (heartbeat, envelope decode, roster fold, `on_change`).
////
//// Run via `smoke/run.mjs`, which supplies a WebSocket global.

import sudoku_lustre/doc_schema
import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json.{type Json}
import gleam/list

import watershed/presence
import watershed/presence_js
import watershed/transport_js
import watershed_js.{type Document, WatershedConfig}

const url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const secret = "levee-dev-secret-change-in-production"

@external(javascript, "./smoke_ffi.mjs", "delay")
fn delay(ms: Int, cb: fn() -> Nil) -> Nil

@external(javascript, "./smoke_ffi.mjs", "log")
fn log(message: String) -> Nil

@external(javascript, "./smoke_ffi.mjs", "exit")
fn exit(code: Int) -> Nil

/// A minimal presence payload for the harness (the app's real one is
/// `sudoku_lustre.SudokuPresence`).
type Ping {
  Ping(cell: String, editing: Bool)
}

fn encode_ping(p: Ping) -> Json {
  json.object([
    #("cell", json.string(p.cell)),
    #("editing", json.bool(p.editing)),
  ])
}

fn ping_decoder() -> Decoder(Ping) {
  use cell <- decode.field("cell", decode.string)
  use editing <- decode.field("editing", decode.bool)
  decode.success(Ping(cell:, editing:))
}

fn connect_client(
  document: String,
  user: String,
) -> Promise(Document(doc_schema.SudokuDoc)) {
  use token <- promise.map(watershed_js.dev_token(
    secret,
    tenant,
    document,
    user,
  ))
  watershed_js.connect(
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

pub fn main() {
  let document = "sudoku-smoke-" <> int.to_string(100_000 + int.random(900_000))
  log("ripples smoke: document " <> document)

  let _ = {
    use doc_a <- promise.await(connect_client(document, "user-a"))
    use doc_b <- promise.map(connect_client(document, "user-b"))
    run_scenario(doc_a, doc_b)
  }
  Nil
}

fn ping_config() -> presence.Config(Ping) {
  presence.config(encode_ping, ping_decoder())
}

fn run_scenario(
  doc_a: Document(doc_schema.SudokuDoc),
  doc_b: Document(doc_schema.SudokuDoc),
) -> Nil {
  // B tracks its roster through the driver; A joins with one payload and then
  // updates it. Whether that rides the server lane or the ripple heartbeat is
  // the driver's business — this harness asserts the same outcome either way.
  let roster = transport_js.new_cell([])
  let _b =
    presence_js.start(
      document: doc_b,
      config: ping_config(),
      initial: Ping(cell: "", editing: False),
      on_event: fn(event) {
        case event {
          presence.State(entries) | presence.Changed(_, entries) ->
            transport_js.set_cell(roster, entries)
          presence.Failed(_) -> Nil
        }
      },
    )
  let handle_a =
    presence_js.start(
      document: doc_a,
      config: ping_config(),
      initial: Ping(cell: "", editing: False),
      on_event: fn(_event) { Nil },
    )

  // Give both handshakes time to settle (the driver joins on the first one),
  // then A moves and we check B's roster.
  delay(1500, fn() {
    presence_js.update(handle_a, Ping(cell: "r0c0", editing: True))
    delay(600, fn() { assert_received(transport_js.get_cell(roster)) })
  })
}

fn assert_received(peers: List(presence.PresenceEntry(Ping))) -> Nil {
  case list.find(peers, fn(peer) { peer.key == "user-a" }) {
    Ok(peer) ->
      case peer.meta.cell == "r0c0" && peer.meta.editing {
        True -> {
          log("RIPPLES SMOKE PASS: B received A's presence (cell r0c0, typing)")
          exit(0)
        }
        False -> {
          log("RIPPLES SMOKE FAIL: unexpected payload for user-a")
          exit(1)
        }
      }
    Error(_) -> {
      log("RIPPLES SMOKE FAIL: B received no presence ripple")
      exit(1)
    }
  }
}
