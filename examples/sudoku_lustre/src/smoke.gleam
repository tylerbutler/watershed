//// Headless smoke test for watershed *signals*: drive two `watershed_js`
//// clients against a live levee dev server (`just server`) from Node and
//// assert that an ephemeral presence signal sent by one client is delivered to
//// the other. This exercises the new signal path end-to-end: the transport FFI
//// `signal` listener + `submitSignal` push, `runtime_js` send/receive, the
//// `wire/socket` codecs, and the `watershed_js` surface.
////
//// Run via `smoke/run.mjs`, which supplies a WebSocket global.

import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/option.{type Option, None, Some}

import presence.{type Presence, Presence}
import watershed/transport_js
import watershed_js.{type Document, type Signal, WatershedConfig}

const url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const secret = "levee-dev-secret-change-in-production"

@external(javascript, "./smoke_ffi.mjs", "delay")
fn delay(ms: Int, cb: fn() -> Nil) -> Nil

@external(javascript, "./smoke_ffi.mjs", "log")
fn log(message: String) -> Nil

@external(javascript, "./smoke_ffi.mjs", "exit")
fn exit(code: Int) -> Nil

fn connect_client(document: String, user: String) -> Promise(Document) {
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
  log("signals smoke: document " <> document)

  let _ = {
    use doc_a <- promise.await(connect_client(document, "user-a"))
    use doc_b <- promise.map(connect_client(document, "user-b"))
    run_scenario(doc_a, doc_b)
  }
  Nil
}

fn run_scenario(doc_a: Document, doc_b: Document) -> Nil {
  // B records the last presence it decodes from an inbound signal. levee
  // strips the signal `type` on broadcast, so we discriminate via the content.
  let received = transport_js.new_cell(None)
  watershed_js.subscribe_signals(doc_b, fn(signal: Signal) {
    case presence.decode(watershed_js.signal_content(signal)) {
      Ok(p) -> transport_js.set_cell(received, Some(p))
      Error(_) -> Nil
    }
  })

  // Give both handshakes time to complete and assign client ids, then A
  // announces (signals are a no-op until a client id exists).
  delay(1500, fn() {
    watershed_js.submit_signal(
      doc_a,
      signal_type: presence.signal_type,
      content: presence.encode(Presence(
        user: "user-a",
        color: "#e6194b",
        name: "a",
        cell: Some("r0c0"),
        editing: True,
      )),
    )

    delay(600, fn() { assert_received(transport_js.get_cell(received)) })
  })
}

fn assert_received(got: Option(Presence)) -> Nil {
  case got {
    Some(p) ->
      case p.user == "user-a" && p.cell == Some("r0c0") && p.editing {
        True -> {
          log("SIGNALS SMOKE PASS: B received A's presence (cell r0c0, typing)")
          exit(0)
        }
        False -> {
          log("SIGNALS SMOKE FAIL: unexpected presence " <> p.user)
          exit(1)
        }
      }
    None -> {
      log("SIGNALS SMOKE FAIL: B received no presence signal")
      exit(1)
    }
  }
}
