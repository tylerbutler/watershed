//// Live integration test against a levee dev server (M3 exit criterion:
//// two Gleam clients converge on concurrent edits).
////
//// Gated behind `WATERSHED_INTEGRATION=1` so the suite stays green without
//// a server. Run the server with `just server` in the levee repo (registers
//// tenant "dev-tenant" in dev mode), then:
////
//// ```sh
//// WATERSHED_INTEGRATION=1 gleam test
//// ```

@target(erlang)
import envoy
@target(erlang)
import gleam/bit_array
@target(erlang)
import gleam/crypto
@target(erlang)
import gleam/erlang/process
@target(erlang)
import gleam/int
@target(erlang)
import gleam/io
@target(erlang)
import gleam/json.{type Json}
@target(erlang)
import gleam/list
@target(erlang)
import gleam/option.{None, Some}
@target(erlang)
import startest/expect

@target(erlang)
import watershed
@target(erlang)
import watershed/git_storage

@target(erlang)
const tenant = "dev-tenant"

@target(erlang)
const tenant_secret = "levee-dev-secret-change-in-production"

// Use the IPv4 loopback literal, not "localhost". Erlang's inet resolver
// (httpc/gun default to the `inet6fb4` family) stalls ~8s resolving AAAA for
// "localhost" before falling back to IPv4, which would block the runtime actor
// long enough for levee to drop the socket as idle.
@target(erlang)
const host = "127.0.0.1"

@target(erlang)
const port = 4000

@target(erlang)
pub fn two_clients_converge_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_convergence_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// M4 exit criterion: drop a client's channel mid-burst and assert both
/// clients still converge with no lost or duplicated ops.
pub fn reconnect_converges_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_reconnect_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// Summaries exit criterion: a client summarizes the map, then a fresh client
/// bootstraps from the summary (its history starts above SN 1) and converges.
pub fn summary_bootstrap_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_summary_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// Pagination exit criterion: a document with more ops than the server's
/// in-band history window (1000 messages) serves `initialMessages` missing
/// its prefix, so a fresh client must page the gap from the deltas REST
/// endpoint during bootstrap.
pub fn large_history_bootstrap_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_large_history_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
/// getVersions exit criterion: every summarize stores a version; the client
/// lists them newest first and reads any historical snapshot back by handle.
pub fn summary_versions_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_versions_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

@target(erlang)
fn run_versions_test() -> Nil {
  let document = "watershed-ver-" <> int.to_string(system_time(Second))

  let doc = connect_or_panic(document, "user-a")
  let map = watershed.root(doc)

  // A document with no summaries yet lists no versions.
  watershed.get_versions(doc, count: 10) |> expect.to_equal(Ok([]))

  // First snapshot: {die: 4, color: blue}.
  watershed.set(map, "die", json.int(4))
  watershed.set(map, "color", json.string("blue"))
  wait_until(50, fn() { watershed.is_synced(doc) }) |> expect.to_be_true()
  let handle_1 = case wait_until_ok(50, fn() { watershed.summarize(doc) }) {
    Ok(handle) -> handle
    Error(reason) -> panic as { "first summarize failed: " <> reason }
  }

  // Second snapshot: color changed and a key added.
  watershed.set(map, "color", json.string("green"))
  watershed.set(map, "post", json.bool(True))
  wait_until(50, fn() { watershed.is_synced(doc) }) |> expect.to_be_true()
  let handle_2 = case wait_until_ok(50, fn() { watershed.summarize(doc) }) {
    Ok(handle) -> handle
    Error(reason) -> panic as { "second summarize failed: " <> reason }
  }

  // The server registers a version per summarize op (async relative to the
  // summarize reply), newest first.
  wait_until(50, fn() {
    case watershed.get_versions(doc, count: 10) {
      Ok(versions) ->
        list.map(versions, fn(v: git_storage.SummaryVersion) { v.handle })
        == [handle_2, handle_1]
      Error(_) -> False
    }
  })
  |> expect.to_be_true()

  let assert Ok([latest, previous]) = watershed.get_versions(doc, count: 10)
  { latest.sequence_number > previous.sequence_number } |> expect.to_be_true()

  // `count` keeps only the newest versions.
  let assert Ok([only]) = watershed.get_versions(doc, count: 1)
  only.handle |> expect.to_equal(handle_2)

  // Historical snapshot reads by handle: each version returns exactly the
  // confirmed state it captured, without affecting the live document.
  let assert Ok(blob_1) = watershed.load_version(doc, handle: handle_1)
  let entries_1 = list.flatten(list.map(blob_1.channels, fn(ch) { ch.entries }))
  entries_1
  |> expect.to_equal([
    #("die", json.int(4)),
    #("color", json.string("blue")),
  ])
  let assert Ok(blob_2) = watershed.load_version(doc, handle: handle_2)
  let entries_2 = list.flatten(list.map(blob_2.channels, fn(ch) { ch.entries }))
  entries_2
  |> expect.to_equal([
    #("die", json.int(4)),
    #("color", json.string("green")),
    #("post", json.bool(True)),
  ])
  { blob_2.sequence_number > blob_1.sequence_number } |> expect.to_be_true()

  // The live document still reflects the latest state.
  watershed.get(map, "color") |> expect.to_equal(Some(json.string("green")))

  watershed.close(doc)
}

@target(erlang)
fn run_large_history_test() -> Nil {
  let document = "watershed-lh-" <> int.to_string(system_time(Second))
  let op_count = 1050

  let doc_a = connect_or_panic(document, "user-a")
  let map_a = watershed.root(doc_a)

  // Write more distinct keys than the history window holds. The earliest
  // sets (k1, k2, ...) age out of the server's in-memory op history, so a
  // later bootstrap can only recover them via the deltas REST endpoint.
  write_keys(map_a, 1, op_count)
  wait_until(600, fn() { watershed.is_synced(doc_a) })
  |> expect.to_be_true()

  // A fresh client's initialMessages are missing the prefix; bootstrap must
  // page it in and converge on the full map.
  let doc_b = connect_or_panic(document, "user-b")
  let map_b = watershed.root(doc_b)
  wait_until(100, fn() {
    watershed.size(map_b) == op_count
    && same_entries(watershed.entries(map_b), watershed.entries(map_a))
  })
  |> expect.to_be_true()

  // Spot-check keys that only exist in the aged-out prefix.
  watershed.get(map_b, "k1") |> expect.to_equal(Some(json.int(1)))
  watershed.get(map_b, "k25") |> expect.to_equal(Some(json.int(25)))

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
fn write_keys(map: watershed.SharedMap, from: Int, to: Int) -> Nil {
  case from > to {
    True -> Nil
    False -> {
      watershed.set(map, "k" <> int.to_string(from), json.int(from))
      write_keys(map, from + 1, to)
    }
  }
}

@target(erlang)
fn run_summary_test() -> Nil {
  let document = "watershed-sum-" <> int.to_string(system_time(Second))

  let doc_a = connect_or_panic(document, "user-a")
  let map_a = watershed.root(doc_a)

  // Build up some confirmed state.
  watershed.set(map_a, "die", json.int(4))
  watershed.set(map_a, "color", json.string("blue"))
  watershed.set(map_a, "count", json.int(9))
  watershed.delete(map_a, "count")
  // Wait until every edit is acknowledged (in-flight drained) so the summary
  // captures the complete confirmed state.
  wait_until(50, fn() { watershed.is_synced(doc_a) })
  |> expect.to_be_true()

  // Summarize once the client is caught up. Retrying is safe: attempts made
  // before the client is synced reply Error and submit nothing; only the
  // successful attempt uploads and submits the summarize op.
  let handle = case wait_until_ok(50, fn() { watershed.summarize(doc_a) }) {
    Ok(handle) -> handle
    Error(reason) -> panic as { "summarize failed: " <> reason }
  }
  { handle != "" } |> expect.to_be_true()

  // Make a post-summary edit so the fresh client must replay a delta on top of
  // the summary (history above SN 1), and wait until it too is sequenced so it
  // is guaranteed to appear in the fresh client's post-summary history.
  watershed.set(map_a, "post", json.string("after-summary"))
  wait_until(50, fn() { watershed.is_synced(doc_a) })
  |> expect.to_be_true()

  // A fresh client connects; the server serves the summaryContext + only the
  // post-summary deltas, so watershed must load the summary and apply the
  // delta rather than fail with a HistoryGap.
  let doc_b = connect_or_panic(document, "user-b")
  let map_b = watershed.root(doc_b)
  let converged =
    wait_until(50, fn() {
      same_entries(watershed.entries(map_b), watershed.entries(map_a))
    })
  converged
  |> expect.to_be_true()

  // The summarized keys and the post-summary delta all made it across.
  watershed.get(map_b, "die") |> expect.to_equal(Some(json.int(4)))
  watershed.get(map_b, "color") |> expect.to_equal(Some(json.string("blue")))
  watershed.get(map_b, "count") |> expect.to_equal(None)
  watershed.get(map_b, "post")
  |> expect.to_equal(Some(json.string("after-summary")))

  watershed.close(doc_a)
  watershed.close(doc_b)
}

@target(erlang)
fn run_reconnect_test() -> Nil {
  let document = "watershed-rc-" <> int.to_string(system_time(Second))

  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  // Establish the session and confirm both sides are live.
  watershed.set(map_a, "k1", json.int(1))
  wait_until(50, fn() { watershed.get(map_b, "k1") == Some(json.int(1)) })
  |> expect.to_be_true()

  // Burst several edits from A, then yank its channel mid-flight so some ops
  // are in flight (possibly sequenced-but-unacked) when the socket drops.
  watershed.set(map_a, "k2", json.int(2))
  watershed.set(map_a, "k3", json.int(3))
  watershed.set(map_a, "k4", json.int(4))
  watershed.set(map_a, "k5", json.int(5))
  watershed.force_reconnect(doc_a)

  // Edits issued while A is reconnecting must be preserved and resubmitted.
  watershed.set(map_a, "k6", json.string("after-drop"))
  watershed.delete(map_a, "k2")

  // Meanwhile B keeps editing so the reconnect must also merge the delta A
  // missed while offline.
  watershed.set(map_b, "from-b", json.bool(True))

  let expected_a = Some(json.string("after-drop"))
  let converged =
    wait_until(100, fn() {
      let entries_a = watershed.entries(map_a)
      let entries_b = watershed.entries(map_b)
      entries_a != []
      && same_entries(entries_a, entries_b)
      && watershed.get(map_a, "k6") == expected_a
      && watershed.get(map_a, "from-b") == Some(json.bool(True))
      && watershed.get(map_a, "k2") == None
    })
  converged |> expect.to_be_true()

  // No op was lost: every surviving key made it across the reconnect.
  watershed.get(map_b, "k3") |> expect.to_equal(Some(json.int(3)))
  watershed.get(map_b, "k5") |> expect.to_equal(Some(json.int(5)))
  watershed.get(map_b, "k6") |> expect.to_equal(expected_a)
  // The delete issued during reconnect converged too (no duplicate re-add).
  watershed.get(map_b, "k2") |> expect.to_equal(None)

  // A fresh client bootstrapping from history sees the identical converged map.
  let doc_c = connect_or_panic(document, "user-c")
  let map_c = watershed.root(doc_c)
  wait_until(50, fn() {
    same_entries(watershed.entries(map_c), watershed.entries(map_a))
  })
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_b)
  watershed.close(doc_c)
}

@target(erlang)
fn run_convergence_test() -> Nil {
  let document = "watershed-it-" <> int.to_string(system_time(Second))

  let doc_a = connect_or_panic(document, "user-a")
  let doc_b = connect_or_panic(document, "user-b")
  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  // Concurrent edits from both clients, including a same-key race that
  // server sequencing must resolve identically on both sides.
  watershed.set(map_a, "die", json.int(4))
  watershed.set(map_b, "color", json.string("blue"))
  watershed.set(map_a, "shared", json.string("from-a"))
  watershed.set(map_b, "shared", json.string("from-b"))
  watershed.delete(map_a, "die")
  watershed.set(map_a, "die", json.int(6))

  let converged =
    wait_until(50, fn() {
      let entries_a = watershed.entries(map_a)
      let entries_b = watershed.entries(map_b)
      entries_a != []
      && same_entries(entries_a, entries_b)
      && watershed.get(map_a, "die") == Some(json.int(6))
      && watershed.get(map_a, "color") == Some(json.string("blue"))
    })
  converged |> expect.to_be_true()

  // Both clients must agree on the LWW winner for the raced key.
  watershed.get(map_a, "shared")
  |> expect.to_equal(watershed.get(map_b, "shared"))

  // A third client bootstrapping from history alone must see the same map.
  let doc_c = connect_or_panic(document, "user-c")
  let map_c = watershed.root(doc_c)
  same_entries(watershed.entries(map_c), watershed.entries(map_a))
  |> expect.to_be_true()

  watershed.close(doc_a)
  watershed.close(doc_b)
  watershed.close(doc_c)
}

@target(erlang)
fn connect_or_panic(document: String, user_id: String) -> watershed.Document {
  let token = mint_token(tenant, document, user_id)
  case
    watershed.connect(
      host: host,
      port: port,
      tenant: tenant,
      document: document,
      token: token,
      user_id: user_id,
    )
  {
    Ok(doc) -> doc
    Error(reason) -> panic as { "connect failed: " <> reason }
  }
}

@target(erlang)
/// Converged clients must agree on values AND iteration order, since both
/// derive insertion order from the same sequenced op stream.
fn same_entries(
  left: List(#(String, Json)),
  right: List(#(String, Json)),
) -> Bool {
  left == right
}

@target(erlang)
fn wait_until(attempts: Int, check: fn() -> Bool) -> Bool {
  case check() {
    True -> True
    False ->
      case attempts {
        0 -> False
        _ -> {
          process.sleep(100)
          wait_until(attempts - 1, check)
        }
      }
  }
}

@target(erlang)
/// Retry `check` until it returns `Ok`, polling every 100ms. Returns the last
/// result (the successful `Ok`, or the final `Error` once attempts run out).
fn wait_until_ok(attempts: Int, check: fn() -> Result(a, b)) -> Result(a, b) {
  case check() {
    Ok(value) -> Ok(value)
    Error(err) ->
      case attempts {
        0 -> Error(err)
        _ -> {
          process.sleep(100)
          wait_until_ok(attempts - 1, check)
        }
      }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dev JWT minting (HS256, matching levee's JOSE verification)
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
fn mint_token(tenant: String, document: String, user_id: String) -> String {
  let now = system_time(Second)
  let header =
    json.object([
      #("alg", json.string("HS256")),
      #("typ", json.string("JWT")),
    ])
  let payload =
    json.object([
      #("documentId", json.string(document)),
      #("tenantId", json.string(tenant)),
      #(
        "scopes",
        json.array(["doc:read", "doc:write", "summary:write"], json.string),
      ),
      #("user", json.object([#("id", json.string(user_id))])),
      #("iat", json.int(now)),
      #("exp", json.int(now + 3600)),
      #("ver", json.string("1.0")),
    ])
  let signing_input =
    base64url(<<json.to_string(header):utf8>>)
    <> "."
    <> base64url(<<json.to_string(payload):utf8>>)
  let signature =
    crypto.hmac(<<signing_input:utf8>>, crypto.Sha256, <<tenant_secret:utf8>>)
  signing_input <> "." <> base64url(signature)
}

@target(erlang)
fn base64url(data: BitArray) -> String {
  bit_array.base64_url_encode(data, False)
}

@target(erlang)
type TimeUnit {
  Second
}

@target(erlang)
@external(erlang, "os", "system_time")
fn system_time(unit: TimeUnit) -> Int
