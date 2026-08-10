//// Live integration suite for the **JavaScript** runtime, against a floodgate
//// dev server. The erlang runtime has had `integration_test.gleam` since M3;
//// this is the JS counterpart, and until it existed the JS runtime had never
//// once been run against a real server outside of an example.
////
//// That gap is what let the reconnect catch-up stall ship: `sluice_js` fakes
//// the socket, and the sluice used to push a frame no real server sends, so
//// every reconnect test passed while the live path wedged forever.
////
//// ```sh
//// just integration-up
//// just integration-run-js
//// ```
////
//// **Why this is not a `gleam test` case.** startest's `TestBody` is
//// `fn() -> Nil` (`startest/test_case`), with nowhere to return a promise, so a
//// runner would report a pass the moment the first `await` suspended — every
//// assertion here would be scored before it ran. So the suite is a `main` that
//// exits 0 or 1, driven by `smoke/run.mjs`, which is also where the `WebSocket`
//// global the Phoenix client needs comes from.
////
//// Every scenario builds a **fresh document with fresh clients**. A wedged
//// client stays wedged, so sharing one across scenarios would make everything
//// after the first failure fail too, whatever its own cause.

@target(javascript)
import envoy
@target(javascript)
import gleam/int
@target(javascript)
import gleam/javascript/promise.{type Promise}
@target(javascript)
import gleam/json
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{type Option, None, Some}
@target(javascript)
import gleam/string

@target(javascript)
import watershed/summary_policy
@target(javascript)
import watershed_js.{type Document, type SharedMap, WatershedConfig}

@target(javascript)
const url = "ws://127.0.0.1:4000/socket/websocket?vsn=2.0.0"

@target(javascript)
const tenant = "dev-tenant"

@target(javascript)
const secret = "levee-dev-secret-change-in-production"

@target(javascript)
/// How long a socket teardown is given before the scenario treats the client as
/// genuinely offline. `force_reconnect` and `go_offline` return immediately, so
/// without this pause a peer's edit races the teardown and may be delivered
/// live — which would leave nothing to catch up on and silently void the test.
const teardown_ms = 800

@target(javascript)
@external(javascript, "./live_js_ffi.mjs", "sleep")
fn sleep(ms: Int) -> Promise(Nil)

@target(javascript)
@external(javascript, "./live_js_ffi.mjs", "log")
fn log(message: String) -> Nil

@target(javascript)
@external(javascript, "./live_js_ffi.mjs", "exit")
fn exit(code: Int) -> Nil

@target(javascript)
pub fn main() -> Nil {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run()
    _ -> log("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(javascript)
fn run() -> Nil {
  let _ = {
    use quiet <- promise.await(reconnect_into_a_quiet_room())
    use empty <- promise.await(reconnect_with_nothing_missed())
    use offline <- promise.await(offline_edits_flush_on_go_online())
    use summary <- promise.await(a_policy_summarizes_without_being_asked())
    report([
      #("reconnect_into_a_quiet_room", quiet),
      #("reconnect_with_nothing_missed", empty),
      #("offline_edits_flush_on_go_online", offline),
      #("a_policy_summarizes_without_being_asked", summary),
    ])
    promise.resolve(Nil)
  }
  Nil
}

// ─────────────────────────────────────────────────────────────────────────────
// Scenarios
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// B writes while A is away, and then the room goes quiet. A has nothing of its
/// own pending, so nothing about its return generates traffic.
///
/// This is the reported defect, reduced — `in_flight=0`, `buffered=0`,
/// `last_seen` frozen below `resubmit`. Nothing arrives after the rejoin, so
/// there is no live op to notice a gap with, and A must ask for what it missed.
///
/// The window is `go_offline`/`go_online` rather than `force_reconnect` on
/// purpose. `force_reconnect` is away and back inside a second, so a peer's
/// write almost always lands *after* the rejoin — where it is an ordinary
/// out-of-order op that triggers the reactive catch-up, and the scenario passes
/// whether or not the handshake requests anything. Holding the socket down is
/// what puts the write reliably inside the gap.
fn reconnect_into_a_quiet_room() -> Promise(Bool) {
  use #(doc_a, doc_b, map_a, map_b) <- promise.await(room("rq"))
  use settled <- promise.await(settle(map_a, map_b))

  watershed_js.go_offline(doc_a)
  use _ <- promise.await(sleep(teardown_ms))

  // The only write in the scenario, and it lands squarely in A's gap.
  watershed_js.set(map_b, "from-b", json.bool(True))
  use _ <- promise.await(sleep(teardown_ms))

  watershed_js.go_online(doc_a)

  use caught_up <- promise.await(
    wait_until(fn() {
      watershed_js.get(map_a, "from-b") == Some(json.bool(True))
    }),
  )

  // Caught up is not the same as live. An edit made now has to reach the wire,
  // which it cannot do from the catching-up holding state.
  watershed_js.set(map_a, "after", json.string("live"))
  use live <- promise.await(
    wait_until(fn() {
      watershed_js.get(map_b, "after") == Some(json.string("live"))
    }),
  )

  finish("reconnect_into_a_quiet_room", doc_a, doc_b, [
    #("settled", settled),
    #("caught_up", caught_up),
    #("live", live),
  ])
}

@target(javascript)
/// The same stall with an empty gap.
///
/// Floodgate sequences the rejoining client's own `join` and reports that SN as
/// the handshake checkpoint, so a reconnect starts out behind even when it
/// missed nothing. A client that reconnected into total silence wedged with an
/// empty gap — nothing to catch up on, and no way to find that out.
///
/// Note A cannot rescue itself: while catching up its edits are withheld from
/// the wire, so they generate no traffic to discover the gap with.
fn reconnect_with_nothing_missed() -> Promise(Bool) {
  use #(doc_a, doc_b, map_a, map_b) <- promise.await(room("rn"))
  use settled <- promise.await(settle(map_a, map_b))

  watershed_js.force_reconnect(doc_a)
  use _ <- promise.await(sleep(teardown_ms))

  watershed_js.set(map_a, "after", json.string("live"))
  use live <- promise.await(
    wait_until(fn() {
      watershed_js.get(map_b, "after") == Some(json.string("live"))
    }),
  )

  finish("reconnect_with_nothing_missed", doc_a, doc_b, [
    #("settled", settled),
    #("live", live),
  ])
}

@target(javascript)
/// The offline toggle, both legs. `go_offline` holds the socket down rather
/// than cycling it, so this covers a gap of arbitrary length with edits made on
/// both sides of it — the shape `examples/pixel_canvas_lustre` needs.
fn offline_edits_flush_on_go_online() -> Promise(Bool) {
  use #(doc_a, doc_b, map_a, map_b) <- promise.await(room("of"))
  use settled <- promise.await(settle(map_a, map_b))

  watershed_js.go_offline(doc_a)
  use _ <- promise.await(sleep(teardown_ms))
  let held = watershed_js.diagnostics(doc_a).phase == "reconnecting"

  watershed_js.set(map_a, "offline-a", json.string("a"))
  watershed_js.set(map_b, "offline-b", json.string("b"))
  use _ <- promise.await(sleep(teardown_ms))

  // Held means held, in both directions.
  let isolated =
    watershed_js.get(map_b, "offline-a") == None
    && watershed_js.get(map_a, "offline-b") == None

  watershed_js.go_online(doc_a)
  use merged <- promise.await(
    wait_until(fn() {
      watershed_js.get(map_b, "offline-a") == Some(json.string("a"))
      && watershed_js.get(map_a, "offline-b") == Some(json.string("b"))
    }),
  )

  finish("offline_edits_flush_on_go_online", doc_a, doc_b, [
    #("settled", settled),
    #("held", held),
    #("isolated", isolated),
    #("merged", merged),
  ])
}

@target(javascript)
/// The summary path on the JS runtime, which nothing has ever exercised
/// live — `sluice_js` serves no `summaryContext` and its documents carry no
/// token, so every in-memory test stops at the first gate.
///
/// Nothing here calls `summarize`. A is given a policy, writes past its
/// threshold, and the checkpoint moves on its own; then a fresh client joins
/// and has to bootstrap from a blob nobody asked for.
fn a_policy_summarizes_without_being_asked() -> Promise(Bool) {
  use #(document, doc_a, doc_b, map_a, map_b) <- promise.await(room_named("sm"))
  use settled <- promise.await(settle(map_a, map_b))

  watershed_js.auto_summarize(
    doc_a,
    summary_policy.policy()
      |> summary_policy.with_threshold(8)
      |> summary_policy.with_jitter_ms(0),
  )

  let before = watershed_js.ops_since_summary(doc_a)
  write_keys(map_a, 12)

  // The checkpoint moving is the observable: a client only knows about a
  // summary it wrote or saw sequenced.
  use summarized <- promise.await(
    wait_until(fn() { watershed_js.ops_since_summary(doc_a) < before }),
  )

  // A post-checkpoint edit, so the joiner applies a delta on top of the blob
  // rather than landing on it exactly.
  watershed_js.set(map_a, "post", json.string("after-summary"))
  use delivered <- promise.await(
    wait_until(fn() {
      watershed_js.get(map_b, "post") == Some(json.string("after-summary"))
    }),
  )

  use doc_c <- promise.await(connect_client(document, "user-c"))
  let map_c = watershed_js.root(doc_c)
  use joined <- promise.await(
    wait_until(fn() {
      watershed_js.get(map_c, "post") == Some(json.string("after-summary"))
      && watershed_js.get(map_c, "k12") == Some(json.int(12))
    }),
  )
  // It seeded from the checkpoint rather than replaying from zero.
  let from_checkpoint = watershed_js.ops_since_summary(doc_c) < 12

  watershed_js.close(doc_c)
  finish("a_policy_summarizes_without_being_asked", doc_a, doc_b, [
    #("settled", settled),
    #("summarized", summarized),
    #("delivered", delivered),
    #("joined", joined),
    #("from_checkpoint", from_checkpoint),
  ])
}

@target(javascript)
fn write_keys(map: SharedMap, count: Int) -> Nil {
  case count <= 0 {
    True -> Nil
    False -> {
      write_keys(map, count - 1)
      watershed_js.set(map, "k" <> int.to_string(count), json.int(count))
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Harness
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// Two clients on a document nobody has touched, named per scenario so a failed
/// run leaves a readable trail on the server.
fn room(
  prefix: String,
) -> Promise(#(Document, Document, SharedMap, SharedMap)) {
  use #(_document, doc_a, doc_b, map_a, map_b) <- promise.map(room_named(prefix))
  #(doc_a, doc_b, map_a, map_b)
}

@target(javascript)
/// `room`, plus the generated document id — for a scenario that has to connect
/// a third client to the same document later on.
fn room_named(
  prefix: String,
) -> Promise(#(String, Document, Document, SharedMap, SharedMap)) {
  let document =
    "watershed-js-"
    <> prefix
    <> "-"
    <> int.to_string(100_000 + int.random(900_000))
  log("live_js: document " <> document)

  use doc_a <- promise.await(connect_client(document, "user-a"))
  use doc_b <- promise.await(connect_client(document, "user-b"))
  promise.resolve(#(
    document,
    doc_a,
    doc_b,
    watershed_js.root(doc_a),
    watershed_js.root(doc_b),
  ))
}

@target(javascript)
/// Resolves once the handshake has actually landed, not merely once `connect`
/// has returned a `Document`.
///
/// `connect` is synchronous and hands back a document that is still
/// `Connecting`; the readiness signal is the `on_ready` callback. Editing before
/// that lands is a race the scenarios cannot afford — the setup writes would be
/// the thing under test rather than the reconnect.
fn connect_client(document: String, user: String) -> Promise(Document) {
  use token <- promise.await(watershed_js.dev_token(
    secret: secret,
    tenant: tenant,
    document: document,
    user_id: user,
  ))
  let #(ready, resolve) = promise.start()
  let doc =
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
          Ok(_) -> Nil
          Error(reason) -> log("  " <> user <> " FAILED to connect: " <> reason)
        }
        resolve(Nil)
      },
    )
  use _ <- promise.map(ready)
  doc
}

@target(javascript)
/// Establish the session and prove both sides are live before the scenario
/// starts breaking things.
fn settle(map_a: SharedMap, map_b: SharedMap) -> Promise(Bool) {
  watershed_js.set(map_a, "k1", json.int(1))
  wait_until(fn() { watershed_js.get(map_b, "k1") == Some(json.int(1)) })
}

@target(javascript)
/// Poll until `check` passes or the budget runs out. The erlang suite's
/// `wait_until` in the same shape — the JS side had nothing like it, and the
/// example smoke test's chain of hard-coded `delay`s is what it had instead.
fn wait_until(check: fn() -> Bool) -> Promise(Bool) {
  do_wait_until(100, check)
}

@target(javascript)
fn do_wait_until(attempts: Int, check: fn() -> Bool) -> Promise(Bool) {
  case check(), attempts <= 0 {
    True, _ -> promise.resolve(True)
    False, True -> promise.resolve(False)
    False, False -> {
      use _ <- promise.await(sleep(100))
      do_wait_until(attempts - 1, check)
    }
  }
}

@target(javascript)
/// Close the clients, report the scenario, and hand back whether it passed.
/// Diagnostics are printed on failure only — `phase` and `last_seen` against
/// `resubmit` are what distinguish a catch-up stall from an ordinary
/// convergence miss, and the difference is invisible without them.
fn finish(
  name: String,
  doc_a: Document,
  doc_b: Document,
  checks: List(#(String, Bool)),
) -> Promise(Bool) {
  let passed = list.all(checks, fn(check) { check.1 })
  case passed {
    True -> log("  PASS " <> name)
    False -> {
      log("  FAIL " <> name <> ": " <> failed_checks(checks))
      log("    A: " <> diagnostics(doc_a))
      log("    B: " <> diagnostics(doc_b))
    }
  }
  watershed_js.close(doc_a)
  watershed_js.close(doc_b)
  promise.resolve(passed)
}

@target(javascript)
fn failed_checks(checks: List(#(String, Bool))) -> String {
  checks
  |> list.filter(fn(check) { !check.1 })
  |> list.map(fn(check) { check.0 })
  |> string.join(", ")
}

@target(javascript)
fn diagnostics(doc: Document) -> String {
  let d = watershed_js.diagnostics(doc)
  d.phase
  <> " last_seen="
  <> opt_int(d.last_seen_sequence_number)
  <> " in_flight="
  <> int.to_string(d.in_flight_count)
  <> " buffered="
  <> int.to_string(d.buffered_out_of_order_count)
  <> " resubmit="
  <> opt_int(d.resubmit_checkpoint)
}

@target(javascript)
fn opt_int(value: Option(Int)) -> String {
  case value {
    Some(n) -> int.to_string(n)
    None -> "-"
  }
}

@target(javascript)
fn report(results: List(#(String, Bool))) -> Nil {
  let failed = list.filter(results, fn(result) { !result.1 })
  case failed {
    [] -> {
      log(
        "LIVE JS PASS: " <> int.to_string(list.length(results)) <> " scenarios",
      )
      exit(0)
    }
    _ -> {
      log("LIVE JS FAIL: " <> failed_checks(results))
      exit(1)
    }
  }
}
