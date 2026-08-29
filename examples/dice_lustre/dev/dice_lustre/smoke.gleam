//// Headless smoke test: drive two `watershed` SharedMap clients against a
//// live levee dev server (`just server`) from Node, asserting convergence and
//// reconnect safety. This exercises the JS runtime (`runtime`), the Phoenix
//// FFI transport, the wire codecs, and the pure core — the whole JS stack.
////
//// Run via `smoke/run.mjs`, which supplies a WebSocket global.

import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json.{type Json}
import gleam/list
import gleam/string

import watershed.{type Document, WatershedConfig}
import watershed/map_kernel
import watershed/transport_js

import dice_lustre/doc_schema

const url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const secret = "levee-dev-secret-change-in-production"

@external(javascript, "./smoke_ffi.mjs", "delay")
fn delay(ms: Int, callback: fn() -> Nil) -> Nil

@external(javascript, "./smoke_ffi.mjs", "log")
fn log(message: String) -> Nil

@external(javascript, "./smoke_ffi.mjs", "exit")
fn exit(code: Int) -> Nil

fn connect_client(
  document: String,
  user: String,
) -> Promise(Document(doc_schema.DiceDoc)) {
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
  let document = "js-smoke-" <> int.to_string(100_000 + int.random(900_000))
  log("smoke: document " <> document)

  let _ = {
    use doc_a <- promise.await(connect_client(document, "user-a"))
    use doc_b <- promise.map(connect_client(document, "user-b"))
    run_scenario(doc_a, doc_b)
  }
  Nil
}

fn run_scenario(
  doc_a: Document(doc_schema.DiceDoc),
  doc_b: Document(doc_schema.DiceDoc),
) -> Nil {
  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  // The runtime must commit an edit before notifying subscribers: a handler
  // that reads the map during the event must observe the just-applied value,
  // for local edits and remote ops alike (the Lustre app re-reads the map from
  // inside the subscription callback).
  let local_probe = transport_js.new_cell(False)
  let remote_probe = transport_js.new_cell(False)
  // `subscribe` narrows to `map_kernel.MapEvent`, so we match the variant
  // directly. `ValueChanged` now also carries the new `value`, ignored here.
  watershed.subscribe(map_a, fn(event) {
    case event {
      map_kernel.ValueChanged("local_probe", _, _, True) ->
        transport_js.set_cell(
          local_probe,
          watershed.get(map_a, "local_probe") == Ok(json.int(7)),
        )
      map_kernel.ValueChanged("remote_probe", _, _, False) ->
        transport_js.set_cell(
          remote_probe,
          watershed.get(map_a, "remote_probe") == Ok(json.int(9)),
        )
      _ -> Nil
    }
  })

  // Give both clients time to handshake, then issue concurrent edits including
  // a same-key LWW race the server must resolve identically on both sides.
  use <- delay(2000)
  log("smoke: editing")
  watershed.set(map_a, "local_probe", json.int(7))
  watershed.set(map_b, "remote_probe", json.int(9))
  watershed.set(map_a, "die", json.int(4))
  watershed.set(map_b, "color", json.string("blue"))
  watershed.set(map_a, "shared", json.string("from-a"))
  watershed.set(map_b, "shared", json.string("from-b"))

  // Drop A's socket mid-session; edits during reconnect must survive.
  use <- delay(800)
  log("smoke: forcing reconnect on A")
  watershed.force_reconnect(doc_a)
  watershed.set(map_a, "after_drop", json.bool(True))
  watershed.delete(map_a, "die")

  use <- delay(3000)
  let die = watershed.get(map_b, "die")
  let color = watershed.get(map_a, "color")
  let after = watershed.get(map_b, "after_drop")
  let shared_a = watershed.get(map_a, "shared")
  let shared_b = watershed.get(map_b, "shared")
  let entries_a = watershed.entries(map_a)
  let entries_b = watershed.entries(map_b)

  log("smoke: A entries = " <> inspect_entries(entries_a))
  log("smoke: B entries = " <> inspect_entries(entries_b))

  let converged = entries_a == entries_b && entries_a != []
  let die_deleted = die == Error(Nil)
  let color_ok = color == Ok(json.string("blue"))
  let after_ok = after == Ok(json.bool(True))
  let lww_ok = shared_a == shared_b && shared_a != Error(Nil)
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
  |> list.map(fn(pair) { pair.0 <> "=" <> json.to_string(pair.1) })
  |> string.join(", ")
}

fn bool_str(b: Bool) -> String {
  case b {
    True -> "true"
    False -> "false"
  }
}
