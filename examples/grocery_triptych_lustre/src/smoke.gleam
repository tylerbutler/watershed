import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/string

import doc_schema
import watershed.{
  type Document, type GSet, type OrSet, type TwoPSet, WatershedConfig,
}

const url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const secret = "levee-dev-secret-change-in-production"

const readiness_attempts = 100

const readiness_poll_ms = 100

const root_channel_adoption_attempts = 50

const root_channel_adoption_poll_ms = 100

const wait_attempts = 30

@external(javascript, "./smoke_ffi.mjs", "delay")
fn delay(ms: Int, cb: fn() -> Nil) -> Nil

@external(javascript, "./smoke_ffi.mjs", "log")
fn log(message: String) -> Nil

@external(javascript, "./smoke_ffi.mjs", "exit")
fn exit(code: Int) -> Nil

@external(javascript, "./smoke_ffi.mjs", "reset_readiness")
fn reset_readiness() -> Nil

@external(javascript, "./smoke_ffi.mjs", "mark_ready")
fn mark_ready(user: String) -> Nil

@external(javascript, "./smoke_ffi.mjs", "mark_ready_error")
fn mark_ready_error(user: String, reason: String) -> Nil

@external(javascript, "./smoke_ffi.mjs", "readiness_status")
fn readiness_status(user: String) -> String

@external(javascript, "./smoke_ffi.mjs", "readiness_reason")
fn readiness_reason(user: String) -> String

type Client {
  Client(grow_only: GSet, two_phase: TwoPSet, observed: OrSet)
}

type Snapshot {
  Snapshot(
    grow_only: List(String),
    two_phase: List(String),
    observed: List(String),
  )
}

type Readiness {
  Ready
  Pending
  Failed(String)
}

fn connect_client(
  document: String,
  user: String,
) -> Promise(Document(doc_schema.Pantry)) {
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
        Ok(_) -> {
          log("  " <> user <> " ready")
          mark_ready(user)
        }
        Error(reason) -> {
          log("  " <> user <> " FAILED: " <> reason)
          mark_ready_error(user, reason)
        }
      }
    },
  )
}

pub fn main() {
  reset_readiness()

  let document =
    "grocery-smoke-" <> int.to_string(100_000 + int.random(900_000))
  log("smoke: document " <> document)

  let _ = {
    let user_a = "user-a"
    let user_b = "user-b"

    use doc_a <- promise.await(connect_client(document, user_a))
    use doc_b <- promise.map(connect_client(document, user_b))
    await_readiness(user_a, user_b, readiness_attempts, fn() {
      bootstrap(doc_a, doc_b)
    })
  }
  Nil
}

fn await_readiness(
  user_a: String,
  user_b: String,
  attempts: Int,
  then: fn() -> Nil,
) -> Nil {
  let readiness_a = readiness_state(user_a)
  let readiness_b = readiness_state(user_b)

  case readiness_a {
    Ready ->
      case readiness_b {
        Ready -> then()
        Pending -> readiness_retry(user_a, user_b, attempts, then)
        Failed(reason) -> fail_ready(user_b, reason)
      }
    Pending ->
      case readiness_b {
        Ready -> readiness_retry(user_a, user_b, attempts, then)
        Pending -> readiness_retry(user_a, user_b, attempts, then)
        Failed(reason) -> fail_ready(user_b, reason)
      }
    Failed(reason) -> fail_ready(user_a, reason)
  }
}

fn readiness_retry(
  user_a: String,
  user_b: String,
  attempts: Int,
  then: fn() -> Nil,
) -> Nil {
  case attempts <= 0 {
    True -> fail(readiness_timeout_message(user_a, user_b))
    False -> {
      use <- delay(readiness_poll_ms)
      await_readiness(user_a, user_b, attempts - 1, then)
    }
  }
}

fn readiness_timeout_message(user_a: String, user_b: String) -> String {
  let readiness_a = readiness_state(user_a)
  let readiness_b = readiness_state(user_b)

  case readiness_a {
    Pending ->
      case readiness_b {
        Pending ->
          "readiness timeout waiting for " <> user_a <> " and " <> user_b
        _ -> "readiness timeout waiting for " <> user_a
      }
    _ ->
      case readiness_b {
        Pending -> "readiness timeout waiting for " <> user_b
        _ -> "readiness timeout waiting for readiness"
      }
  }
}

fn readiness_state(user: String) -> Readiness {
  case readiness_status(user) {
    "ok" -> Ready
    "error" -> Failed(readiness_reason(user))
    _ -> Pending
  }
}

fn fail_ready(user: String, reason: String) -> Nil {
  fail("on_ready error for " <> user <> ": " <> reason)
}

fn bootstrap(
  doc_a: Document(doc_schema.Pantry),
  doc_b: Document(doc_schema.Pantry),
) -> Nil {
  log("smoke: ensuring pantry channels on A")
  use grow_only_a <- ensure_grow_only(doc_a, "A")
  use two_phase_a <- ensure_two_phase(doc_a, "A")
  use observed_a <- ensure_observed(doc_a, "A")

  use adoption_ok <- wait_until_polling(
    root_channel_adoption_attempts,
    root_channel_adoption_poll_ms,
    fn() { root_channel_fields_present(doc_b) },
  )
  case adoption_ok {
    False ->
      fail(
        "root-channel adoption timeout waiting for grow_only, two_phase, observed on B",
      )
    True -> Nil
  }

  log("smoke: adopting pantry channels on B")
  use grow_only_b <- ensure_grow_only(doc_b, "B")
  use two_phase_b <- ensure_two_phase(doc_b, "B")
  use observed_b <- ensure_observed(doc_b, "B")

  milk_phase(
    Client(grow_only: grow_only_a, two_phase: two_phase_a, observed: observed_a),
    Client(grow_only: grow_only_b, two_phase: two_phase_b, observed: observed_b),
  )
}

fn milk_phase(client_a: Client, client_b: Client) -> Nil {
  let seeded = expected(["milk"], ["milk"], ["milk"])
  let removed = expected(["milk"], [], [])
  let readded = expected(["milk"], [], ["milk"])

  log("smoke: A adds milk to all three sets")
  add_everywhere(client_a, "milk")

  use seed_ok <- wait_until(wait_attempts, fn() {
    both_match(client_a, client_b, seeded)
  })
  case seed_ok {
    False ->
      fail_expected(
        "milk never seeded on both clients",
        seeded,
        client_a,
        client_b,
      )
    True -> {
      log_snapshots("milk seeded", client_a, client_b)
      log("smoke: B performs shared remove of milk")
      remove_shared(client_b, "milk")

      use remove_ok <- wait_until(wait_attempts, fn() {
        both_match(client_a, client_b, removed)
      })
      case remove_ok {
        False ->
          fail_expected(
            "milk never converged to G present / TwoP absent / Or absent",
            removed,
            client_a,
            client_b,
          )
        True -> {
          log_snapshots("milk removed", client_a, client_b)
          log("smoke: A re-adds milk to all three sets")
          add_everywhere(client_a, "milk")

          use readd_ok <- wait_until(wait_attempts, fn() {
            both_match(client_a, client_b, readded)
          })
          case readd_ok {
            False ->
              fail_expected(
                "milk never converged to G present / TwoP absent / Or present",
                readded,
                client_a,
                client_b,
              )
            True -> {
              log_snapshots("milk re-added", client_a, client_b)
              eggs_phase(client_a, client_b)
            }
          }
        }
      }
    }
  }
}

fn eggs_phase(client_a: Client, client_b: Client) -> Nil {
  let seeded = expected(["milk", "eggs"], ["eggs"], ["milk", "eggs"])
  let concurrent = expected(["milk", "eggs"], [], ["milk", "eggs"])

  log("smoke: A seeds eggs in all three sets")
  add_everywhere(client_a, "eggs")

  use seed_ok <- wait_until(wait_attempts, fn() {
    both_match(client_a, client_b, seeded)
  })
  case seed_ok {
    False ->
      fail_expected(
        "eggs never seeded on both clients",
        seeded,
        client_a,
        client_b,
      )
    True -> {
      log_snapshots("eggs seeded", client_a, client_b)
      log("smoke: A removes eggs while B re-adds them back-to-back")
      remove_shared(client_a, "eggs")
      add_everywhere(client_b, "eggs")

      use concurrent_ok <- wait_until(wait_attempts, fn() {
        both_match(client_a, client_b, concurrent)
      })
      case concurrent_ok {
        False ->
          fail_expected(
            "eggs never converged to G present / TwoP absent / Or present",
            concurrent,
            client_a,
            client_b,
          )
        True -> {
          log_snapshots("eggs concurrent add/remove", client_a, client_b)
          log(
            "SMOKE PASS: grocery sets converged through remove, re-add, and concurrent churn",
          )
          exit(0)
        }
      }
    }
  }
}

fn ensure_grow_only(
  doc: Document(doc_schema.Pantry),
  who: String,
  then: fn(GSet) -> Nil,
) -> Nil {
  watershed.ensure_g_set(
    doc,
    watershed.root_typed(doc),
    doc_schema.grow_only(),
    fn(result) {
      case result {
        Ok(set) -> then(set)
        Error(reason) ->
          fail("could not ensure grow_only on " <> who <> ": " <> reason)
      }
    },
  )
}

fn ensure_two_phase(
  doc: Document(doc_schema.Pantry),
  who: String,
  then: fn(TwoPSet) -> Nil,
) -> Nil {
  watershed.ensure_two_p_set(
    doc,
    watershed.root_typed(doc),
    doc_schema.two_phase(),
    fn(result) {
      case result {
        Ok(set) -> then(set)
        Error(reason) ->
          fail("could not ensure two_phase on " <> who <> ": " <> reason)
      }
    },
  )
}

fn ensure_observed(
  doc: Document(doc_schema.Pantry),
  who: String,
  then: fn(OrSet) -> Nil,
) -> Nil {
  watershed.ensure_or_set(
    doc,
    watershed.root_typed(doc),
    doc_schema.observed(),
    fn(result) {
      case result {
        Ok(set) -> then(set)
        Error(reason) ->
          fail("could not ensure observed on " <> who <> ": " <> reason)
      }
    },
  )
}

fn add_everywhere(client: Client, item: String) -> Nil {
  watershed.g_set_add(client.grow_only, item)
  watershed.two_p_set_add(client.two_phase, item)
  watershed.or_set_add(client.observed, item)
}

fn root_channel_fields_present(doc: Document(doc_schema.Pantry)) -> Bool {
  let root = watershed.untyped(watershed.root_typed(doc))

  watershed.has(root, "grow_only")
  && watershed.has(root, "two_phase")
  && watershed.has(root, "observed")
}

fn remove_shared(client: Client, item: String) -> Nil {
  watershed.two_p_set_remove(client.two_phase, item)
  watershed.or_set_remove(client.observed, item)
}

fn both_match(client_a: Client, client_b: Client, wanted: Snapshot) -> Bool {
  snapshot(client_a) == wanted && snapshot(client_b) == wanted
}

fn snapshot(client: Client) -> Snapshot {
  Snapshot(
    grow_only: g_set_values(client.grow_only),
    two_phase: two_p_set_values(client.two_phase),
    observed: or_set_values(client.observed),
  )
}

fn expected(
  grow_only: List(String),
  two_phase: List(String),
  observed: List(String),
) -> Snapshot {
  Snapshot(
    grow_only: sort_values(grow_only),
    two_phase: sort_values(two_phase),
    observed: sort_values(observed),
  )
}

fn g_set_values(set: GSet) -> List(String) {
  watershed.g_set_values(set) |> sort_values
}

fn two_p_set_values(set: TwoPSet) -> List(String) {
  watershed.two_p_set_values(set) |> sort_values
}

fn or_set_values(set: OrSet) -> List(String) {
  watershed.or_set_values(set) |> sort_values
}

fn sort_values(values: List(String)) -> List(String) {
  list.sort(values, string.compare)
}

fn wait_until(
  attempts: Int,
  check: fn() -> Bool,
  then: fn(Bool) -> Nil,
) -> Nil {
  wait_until_polling(attempts, 250, check, then)
}

fn wait_until_polling(
  attempts: Int,
  poll_ms: Int,
  check: fn() -> Bool,
  then: fn(Bool) -> Nil,
) -> Nil {
  case check() {
    True -> then(True)
    False ->
      case attempts <= 0 {
        True -> then(False)
        False -> {
          use <- delay(poll_ms)
          wait_until_polling(attempts - 1, poll_ms, check, then)
        }
      }
  }
}

fn log_snapshots(label: String, client_a: Client, client_b: Client) -> Nil {
  log("  " <> label <> " A " <> snapshot_string(snapshot(client_a)))
  log("  " <> label <> " B " <> snapshot_string(snapshot(client_b)))
}

fn fail_expected(
  reason: String,
  wanted: Snapshot,
  client_a: Client,
  client_b: Client,
) -> Nil {
  let actual_a = snapshot(client_a)
  let actual_b = snapshot(client_b)

  log(
    "SMOKE FAIL: "
    <> reason
    <> " a_matches="
    <> bool_str(actual_a == wanted)
    <> " b_matches="
    <> bool_str(actual_b == wanted)
    <> " converged="
    <> bool_str(actual_a == actual_b)
    <> " expected="
    <> snapshot_string(wanted)
    <> " A="
    <> snapshot_string(actual_a)
    <> " B="
    <> snapshot_string(actual_b),
  )
  exit(1)
}

fn fail(reason: String) -> Nil {
  log("SMOKE FAIL: " <> reason)
  exit(1)
}

fn snapshot_string(snapshot: Snapshot) -> String {
  "G=["
  <> string.join(snapshot.grow_only, ",")
  <> "] TwoP=["
  <> string.join(snapshot.two_phase, ",")
  <> "] Or=["
  <> string.join(snapshot.observed, ",")
  <> "]"
}

fn bool_str(b: Bool) -> String {
  case b {
    True -> "true"
    False -> "false"
  }
}
