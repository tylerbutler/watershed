//// Headless smoke test: drive two `watershed_js` clients against a live
//// floodgate dev server (`just integration-up`) from Node and assert that the
//// clap tally converges — the `PnCounter` kernel, its wire codecs, the JS
//// runtime, the Phoenix FFI transport, and the pure core, end to end.
////
//// The interesting assertion is concurrent, uncoordinated increments: two
//// clients clapping in the same window must both land, with no lost update —
//// the property a `PnCounter` merge (not last-write-wins) is supposed to
//// guarantee.
////
//// Run via `smoke/run.mjs`, which supplies a WebSocket global.

import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{None, Some}

import doc_schema
import watershed_js.{type Document, type PnCounter, WatershedConfig}

const url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const secret = "levee-dev-secret-change-in-production"

@external(javascript, "./smoke_ffi.mjs", "delay")
fn delay(ms: Int, cb: fn() -> Nil) -> Nil

@external(javascript, "./smoke_ffi.mjs", "log")
fn log(message: String) -> Nil

@external(javascript, "./smoke_ffi.mjs", "exit")
fn exit(code: Int) -> Nil

fn connect_client(
  document: String,
  user: String,
) -> Promise(Document(doc_schema.ClapDoc)) {
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
  let document = "clap-smoke-" <> int.to_string(100_000 + int.random(900_000))
  log("smoke: document " <> document)

  let _ = {
    use doc_a <- promise.await(connect_client(document, "user-a"))
    use doc_b <- promise.map(connect_client(document, "user-b"))
    run_scenario(doc_a, doc_b)
  }
  Nil
}

fn run_scenario(
  doc_a: Document(doc_schema.ClapDoc),
  doc_b: Document(doc_schema.ClapDoc),
) -> Nil {
  // Let both handshakes land before anyone attaches a channel.
  use <- delay(2000)

  log("smoke: ensuring the claps counter on A")
  watershed_js.ensure_pn_counter(
    doc_a,
    watershed_js.root_typed(doc_a),
    doc_schema.claps(),
    fn(result) {
      case result {
        Error(reason) -> {
          log("SMOKE FAIL: A could not ensure the counter: " <> reason)
          exit(1)
        }
        Ok(counter_a) -> adopt_on_b(doc_a, doc_b, counter_a)
      }
    },
  )
}

fn adopt_on_b(
  doc_a: Document(doc_schema.ClapDoc),
  doc_b: Document(doc_schema.ClapDoc),
  counter_a: PnCounter,
) -> Nil {
  // B adopts the same channel rather than creating its own — `ensure_pn_counter`
  // resolves the handle A just published.
  use <- delay(1500)
  watershed_js.ensure_pn_counter(
    doc_b,
    watershed_js.root_typed(doc_b),
    doc_schema.claps(),
    fn(result) {
      case result {
        Error(reason) -> {
          log("SMOKE FAIL: B could not adopt the counter: " <> reason)
          exit(1)
        }
        Ok(counter_b) -> clap_scenario(doc_a, counter_a, counter_b)
      }
    },
  )
}

fn clap_scenario(
  doc_a: Document(doc_schema.ClapDoc),
  counter_a: PnCounter,
  counter_b: PnCounter,
) -> Nil {
  // Both clients clap concurrently with no coordination. A lost-update bug
  // would show up as a converged value under 7.
  log("smoke: A claps 4 times, B claps 3 times, concurrently")
  list.each([1, 2, 3, 4], fn(_) { watershed_js.pn_counter_update(counter_a, 1) })
  list.each([1, 2, 3], fn(_) { watershed_js.pn_counter_update(counter_b, 1) })

  use <- delay(1500)
  let converged = value(counter_a) == value(counter_b)
  let total_ok = value(counter_a) == Some(7)

  // A reconnect must not resurrect or drop any claps: the value after the
  // handshake replays is the value before it.
  let before = value(counter_a)
  watershed_js.force_reconnect(doc_a)
  use <- delay(2500)
  let survived_reconnect =
    value(counter_a) == before && value(counter_b) == before

  // One more clap after reconnect, to prove the channel is still live.
  watershed_js.pn_counter_update(counter_a, 1)
  use <- delay(1500)
  let post_reconnect_ok = value(counter_b) == Some(8)

  case converged && total_ok && survived_reconnect && post_reconnect_ok {
    True -> {
      log("SMOKE PASS: concurrent claps converged with no lost update")
      exit(0)
    }
    False -> {
      log(
        "SMOKE FAIL: converged="
        <> bool_str(converged)
        <> " total_ok="
        <> bool_str(total_ok)
        <> " survived_reconnect="
        <> bool_str(survived_reconnect)
        <> " post_reconnect_ok="
        <> bool_str(post_reconnect_ok)
        <> " (A="
        <> value_str(counter_a)
        <> " B="
        <> value_str(counter_b)
        <> ")",
      )
      exit(1)
    }
  }
}

fn value(counter: PnCounter) -> option.Option(Int) {
  watershed_js.pn_counter_value(counter)
}

fn value_str(counter: PnCounter) -> String {
  case value(counter) {
    Some(n) -> int.to_string(n)
    None -> "none"
  }
}

fn bool_str(b: Bool) -> String {
  case b {
    True -> "true"
    False -> "false"
  }
}
