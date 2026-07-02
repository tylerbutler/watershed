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

import envoy
import gleam/bit_array
import gleam/crypto
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/json.{type Json}
import gleam/option.{None, Some}
import startest/expect

import watershed

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

const host = "localhost"

const port = 4000

pub fn two_clients_converge_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_convergence_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

/// M4 exit criterion: drop a client's channel mid-burst and assert both
/// clients still converge with no lost or duplicated ops.
pub fn reconnect_converges_test() {
  case envoy.get("WATERSHED_INTEGRATION") {
    Ok("1") -> run_reconnect_test()
    _ -> io.println("  (skipped: set WATERSHED_INTEGRATION=1 to run live)")
  }
}

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

/// Converged clients must agree on values AND iteration order, since both
/// derive insertion order from the same sequenced op stream.
fn same_entries(
  left: List(#(String, Json)),
  right: List(#(String, Json)),
) -> Bool {
  left == right
}

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

// ─────────────────────────────────────────────────────────────────────────────
// Dev JWT minting (HS256, matching levee's JOSE verification)
// ─────────────────────────────────────────────────────────────────────────────

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
      #("scopes", json.array(["doc:read", "doc:write"], json.string)),
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

fn base64url(data: BitArray) -> String {
  bit_array.base64_url_encode(data, False)
}

type TimeUnit {
  Second
}

@external(erlang, "os", "system_time")
fn system_time(unit: TimeUnit) -> Int
