//// Headless smoke test: drive two `watershed_js` SharedMap clients against a
//// live levee dev server (`just server`) from Node, asserting convergence and
//// reconnect safety. This exercises the JS runtime (`runtime_js`), the Phoenix
//// FFI transport, the wire codecs, and the pure core — the whole JS stack.
////
//// Run via `smoke/run.mjs`, which supplies a WebSocket global.

import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json.{type Json}
import gleam/option.{None, Some}
import gleam/string

import watershed/channel
import watershed/map_kernel
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
  let document = "js-smoke-" <> int.to_string(100_000 + int.random(900_000))
  log("smoke: document " <> document)

  let _ = {
    use doc_a <- promise.await(connect_client(document, "user-a"))
    use doc_b <- promise.map(connect_client(document, "user-b"))
    run_scenario(doc_a, doc_b)
  }
  Nil
}

fn run_scenario(doc_a: Document, doc_b: Document) -> Nil {
  let map_a = watershed_js.root(doc_a)
  let map_b = watershed_js.root(doc_b)

  // The runtime must commit an edit before notifying subscribers: a handler
  // that reads the map during the event must observe the just-applied value,
  // for local edits and remote ops alike (the Lustre app re-reads the map from
  // inside the subscription callback).
  let local_probe = transport_js.new_cell(False)
  let remote_probe = transport_js.new_cell(False)
  watershed_js.subscribe(map_a, fn(event) {
    case event {
      channel.MapEvent(map_kernel.ValueChanged("local_probe", _, True)) ->
        transport_js.set_cell(
          local_probe,
          watershed_js.get(map_a, "local_probe") == Some(json.int(7)),
        )
      channel.MapEvent(map_kernel.ValueChanged("remote_probe", _, False)) ->
        transport_js.set_cell(
          remote_probe,
          watershed_js.get(map_a, "remote_probe") == Some(json.int(9)),
        )
      _ -> Nil
    }
  })

  // Give both clients time to handshake, then issue concurrent edits including
  // a same-key LWW race the server must resolve identically on both sides.
  use <- delay(2000)
  log("smoke: editing")
  watershed_js.set(map_a, "local_probe", json.int(7))
  watershed_js.set(map_b, "remote_probe", json.int(9))
  watershed_js.set(map_a, "die", json.int(4))
  watershed_js.set(map_b, "color", json.string("blue"))
  watershed_js.set(map_a, "shared", json.string("from-a"))
  watershed_js.set(map_b, "shared", json.string("from-b"))

  // Drop A's socket mid-session; edits during reconnect must survive.
  use <- delay(800)
  log("smoke: forcing reconnect on A")
  watershed_js.force_reconnect(doc_a)
  watershed_js.set(map_a, "after_drop", json.bool(True))
  watershed_js.delete(map_a, "die")

  use <- delay(3000)
  let die = watershed_js.get(map_b, "die")
  let color = watershed_js.get(map_a, "color")
  let after = watershed_js.get(map_b, "after_drop")
  let shared_a = watershed_js.get(map_a, "shared")
  let shared_b = watershed_js.get(map_b, "shared")
  let entries_a = watershed_js.entries(map_a)
  let entries_b = watershed_js.entries(map_b)

  log("smoke: A entries = " <> inspect_entries(entries_a))
  log("smoke: B entries = " <> inspect_entries(entries_b))

  let converged = entries_a == entries_b && entries_a != []
  let die_deleted = die == None
  let color_ok = color == Some(json.string("blue"))
  let after_ok = after == Some(json.bool(True))
  let lww_ok = shared_a == shared_b && shared_a != None
  let events_ok =
    transport_js.get_cell(local_probe) && transport_js.get_cell(remote_probe)

  case converged && die_deleted && color_ok && after_ok && lww_ok && events_ok {
    True -> {
      log("SMOKE PASS: clients converged across a reconnect")
      exit(0)
    }
    False -> {
      log(
        "SMOKE FAIL: converged="
        <> bool_str(converged)
        <> " die_deleted="
        <> bool_str(die_deleted)
        <> " color_ok="
        <> bool_str(color_ok)
        <> " after_ok="
        <> bool_str(after_ok)
        <> " lww_ok="
        <> bool_str(lww_ok)
        <> " local_event_read_ok="
        <> bool_str(transport_js.get_cell(local_probe))
        <> " remote_event_read_ok="
        <> bool_str(transport_js.get_cell(remote_probe)),
      )
      exit(1)
    }
  }
}

fn inspect_entries(entries: List(#(String, Json))) -> String {
  entries
  |> list_map(fn(pair) { pair.0 <> "=" <> json.to_string(pair.1) })
  |> string.join(", ")
}

fn list_map(items: List(a), f: fn(a) -> b) -> List(b) {
  case items {
    [] -> []
    [first, ..rest] -> [f(first), ..list_map(rest, f)]
  }
}

fn bool_str(b: Bool) -> String {
  case b {
    True -> "true"
    False -> "false"
  }
}
