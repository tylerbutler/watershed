import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/string

import doc_schema
import watershed_js.{
  type Document, type GSet, type OrSet, type TwoPSet, WatershedConfig,
}

const url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const secret = "levee-dev-secret-change-in-production"

const wait_attempts = 30

@external(javascript, "./smoke_ffi.mjs", "delay")
fn delay(ms: Int, cb: fn() -> Nil) -> Nil

@external(javascript, "./smoke_ffi.mjs", "log")
fn log(message: String) -> Nil

@external(javascript, "./smoke_ffi.mjs", "exit")
fn exit(code: Int) -> Nil

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
  let document =
    "grocery-smoke-" <> int.to_string(100_000 + int.random(900_000))
  log("smoke: document " <> document)

  let _ = {
    use doc_a <- promise.await(connect_client(document, "user-a"))
    use doc_b <- promise.map(connect_client(document, "user-b"))
    bootstrap(doc_a, doc_b)
  }
  Nil
}

fn bootstrap(doc_a: Document, doc_b: Document) -> Nil {
  use <- delay(2000)
  log("smoke: ensuring pantry channels on A")
  use grow_only_a <- ensure_grow_only(doc_a, "A")
  use two_phase_a <- ensure_two_phase(doc_a, "A")
  use observed_a <- ensure_observed(doc_a, "A")

  use <- delay(1500)
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

fn ensure_grow_only(doc: Document, who: String, then: fn(GSet) -> Nil) -> Nil {
  watershed_js.ensure_g_set(
    doc,
    watershed_js.root_typed(doc),
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
  doc: Document,
  who: String,
  then: fn(TwoPSet) -> Nil,
) -> Nil {
  watershed_js.ensure_two_p_set(
    doc,
    watershed_js.root_typed(doc),
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

fn ensure_observed(doc: Document, who: String, then: fn(OrSet) -> Nil) -> Nil {
  watershed_js.ensure_or_set(
    doc,
    watershed_js.root_typed(doc),
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
  watershed_js.g_set_add(client.grow_only, item)
  watershed_js.two_p_set_add(client.two_phase, item)
  watershed_js.or_set_add(client.observed, item)
}

fn remove_shared(client: Client, item: String) -> Nil {
  watershed_js.two_p_set_remove(client.two_phase, item)
  watershed_js.or_set_remove(client.observed, item)
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
  watershed_js.g_set_values(set) |> sort_values
}

fn two_p_set_values(set: TwoPSet) -> List(String) {
  watershed_js.two_p_set_values(set) |> sort_values
}

fn or_set_values(set: OrSet) -> List(String) {
  watershed_js.or_set_values(set) |> sort_values
}

fn sort_values(values: List(String)) -> List(String) {
  list.sort(values, string.compare)
}

fn wait_until(
  attempts: Int,
  check: fn() -> Bool,
  then: fn(Bool) -> Nil,
) -> Nil {
  case check() {
    True -> then(True)
    False ->
      case attempts <= 0 {
        True -> then(False)
        False -> {
          use <- delay(250)
          wait_until(attempts - 1, check, then)
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
