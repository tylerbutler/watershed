//// Headless smoke test: drive three `watershed` clients against a live
//// floodgate dev server (`just integration-up`) from Node and assert that
//// the whole room converges end to end — the OR-set, Claims, and PactMap
//// kernels, their wire codecs, the JS runtime, the Phoenix FFI transport, and
//// the pure core, all three working together the way the browser app uses
//// them.
////
//// Three clients, not two: the release target's quorum is the connected
//// roster, and two clients cannot tell that apart from a hardcoded
//// `[self, author]` guess. The deterministic pause/resume/disconnect timing
//// that actually tests the quorum edge cases lives in `test/quorum_test.gleam`
//// against the in-memory sluice; this smoke test only has wall-clock delays
//// to work with, so it exercises the happy path a live server actually
//// round-trips through.
////
//// Run via `smoke/run.mjs`, which supplies a WebSocket global.

import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string

import doc_schema
import watershed.{
  type Claims, type Document, type OrSet, type PactMap, WatershedConfig,
}

const url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const secret = "levee-dev-secret-change-in-production"

const gate_ids = [
  "tests_passing", "changelog_updated", "security_review", "docs_updated",
]

const captain_key = "captain"

const target_key = "target"

@external(javascript, "./smoke_ffi.mjs", "delay")
fn delay(ms: Int, cb: fn() -> Nil) -> Nil

@external(javascript, "./smoke_ffi.mjs", "log")
fn log(message: String) -> Nil

@external(javascript, "./smoke_ffi.mjs", "exit")
fn exit(code: Int) -> Nil

fn connect_client(
  document: String,
  user: String,
) -> Promise(Document(doc_schema.Checklist)) {
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

pub fn main() {
  let document =
    "checklist-smoke-" <> int.to_string(100_000 + int.random(900_000))
  log("smoke: document " <> document)

  let _ = {
    use doc_a <- promise.await(connect_client(document, "user-a"))
    use doc_b <- promise.await(connect_client(document, "user-b"))
    use doc_c <- promise.map(connect_client(document, "user-c"))
    start(doc_a, doc_b, doc_c)
  }
  Nil
}

/// The three resolved channels one client needs, mirroring the app's
/// `SharedState`.
type Handles {
  Handles(checks: OrSet, captain: Claims, release: PactMap)
}

/// Ensure (and, for the first caller, seed) all three channels on `doc`, in
/// the same order `release_checklist_lustre.bootstrap_effect` does. Every
/// `ensure_*` here is the same one the app calls — idempotent, so seeding on
/// A and adopting on B and C is only a matter of which one gets there first.
fn bootstrap(
  doc: Document(doc_schema.Checklist),
  label: String,
  on_ready: fn(Handles) -> Nil,
) -> Nil {
  watershed.ensure_or_set(
    doc,
    watershed.root_typed(doc),
    doc_schema.checks(),
    fn(result) {
      case result {
        Error(reason) -> fail(label <> " could not ensure checks: " <> reason)
        Ok(checks) -> bootstrap_captain(doc, label, checks, on_ready)
      }
    },
  )
}

fn bootstrap_captain(
  doc: Document(doc_schema.Checklist),
  label: String,
  checks: OrSet,
  on_ready: fn(Handles) -> Nil,
) -> Nil {
  watershed.ensure_claims(
    doc,
    watershed.root_typed(doc),
    doc_schema.captain(),
    fn(result) {
      case result {
        Error(reason) -> fail(label <> " could not ensure captain: " <> reason)
        Ok(captain) -> bootstrap_release(doc, label, checks, captain, on_ready)
      }
    },
  )
}

fn bootstrap_release(
  doc: Document(doc_schema.Checklist),
  label: String,
  checks: OrSet,
  captain: Claims,
  on_ready: fn(Handles) -> Nil,
) -> Nil {
  watershed.ensure_pact_map(
    doc,
    watershed.root_typed(doc),
    doc_schema.release(),
    fn(result) {
      case result {
        Error(reason) -> fail(label <> " could not ensure release: " <> reason)
        Ok(release) ->
          on_ready(Handles(checks: checks, captain: captain, release: release))
      }
    },
  )
}

fn fail(reason: String) -> Nil {
  log("SMOKE FAIL: " <> reason)
  exit(1)
}

fn start(
  doc_a: Document(doc_schema.Checklist),
  doc_b: Document(doc_schema.Checklist),
  doc_c: Document(doc_schema.Checklist),
) -> Nil {
  // Let all three handshakes land before anyone attaches a channel.
  use <- delay(2000)

  log("smoke: A seeds checks/captain/release")
  bootstrap(doc_a, "A", fn(a) {
    use <- delay(1500)
    log("smoke: B adopts checks/captain/release")
    bootstrap(doc_b, "B", fn(b) {
      use <- delay(1500)
      log("smoke: C adopts checks/captain/release")
      bootstrap(doc_c, "C", fn(c) { run_scenario(a, b, c) })
    })
  })
}

fn run_scenario(a: Handles, b: Handles, c: Handles) -> Nil {
  log("smoke: A and B complete the checklist between them")
  list.each(["tests_passing", "security_review"], fn(id) {
    watershed.or_set_add(a.checks, id)
  })
  list.each(["changelog_updated", "docs_updated"], fn(id) {
    watershed.or_set_add(b.checks, id)
  })

  use <- delay(1500)
  let checks_complete =
    completed(c.checks) == list.sort(gate_ids, string.compare)
  log("  C sees checks: " <> string.join(completed(c.checks), ","))

  log("smoke: A claims the captain seat")
  let _ = watershed.try_set_claim(a.captain, captain_key, json.string("user-a"))

  use <- delay(1500)
  let captain_settled_on_b = read_captain(b.captain) == Ok("user-a")
  let captain_settled_on_c = read_captain(c.captain) == Ok("user-a")
  log("  B sees captain: " <> string.inspect(read_captain(b.captain)))

  log("smoke: the captain publishes the release target")
  watershed.pact_map_set(a.release, target_key, json.string("v1.0.0"))

  use <- delay(2500)
  let accepted_on_a = read_target(a.release) == Ok("v1.0.0")
  let accepted_on_b = read_target(b.release) == Ok("v1.0.0")
  let accepted_on_c = read_target(c.release) == Ok("v1.0.0")
  let settled = !watershed.pact_map_is_pending(a.release, target_key)
  log("  C sees release target: " <> string.inspect(read_target(c.release)))

  case
    checks_complete
    && captain_settled_on_b
    && captain_settled_on_c
    && accepted_on_a
    && accepted_on_b
    && accepted_on_c
    && settled
  {
    True -> {
      log(
        "SMOKE PASS: the checklist, the captain seat, and the release target all converged",
      )
      exit(0)
    }
    False -> {
      log(
        "SMOKE FAIL: checks_complete="
        <> bool_str(checks_complete)
        <> " captain_on_b="
        <> bool_str(captain_settled_on_b)
        <> " captain_on_c="
        <> bool_str(captain_settled_on_c)
        <> " accepted_on_a="
        <> bool_str(accepted_on_a)
        <> " accepted_on_b="
        <> bool_str(accepted_on_b)
        <> " accepted_on_c="
        <> bool_str(accepted_on_c)
        <> " settled="
        <> bool_str(settled),
      )
      exit(1)
    }
  }
}

/// Sorted, because an OR-set's read order carries no meaning.
fn completed(set: OrSet) -> List(String) {
  watershed.or_set_values(set) |> list.sort(string.compare)
}

fn read_captain(claims: Claims) -> Result(String, Nil) {
  case watershed.get_claim(claims, captain_key) {
    Some(value) -> decode_string(value)
    None -> Error(Nil)
  }
}

fn read_target(release: PactMap) -> Result(String, Nil) {
  case watershed.pact_map_get(release, target_key) {
    Some(value) -> decode_string(value)
    None -> Error(Nil)
  }
}

fn decode_string(value: json.Json) -> Result(String, Nil) {
  case json.parse(json.to_string(value), decode.string) {
    Ok(text) -> Ok(text)
    Error(_) -> Error(Nil)
  }
}

fn bool_str(b: Bool) -> String {
  case b {
    True -> "true"
    False -> "false"
  }
}
