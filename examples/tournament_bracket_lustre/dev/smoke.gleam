//// Headless smoke test: drive two `watershed` clients against a live
//// floodgate dev server (`just integration-up`) from Node and confirm a
//// reported match converges — the register-collection kernel, its wire
//// codecs, the JS runtime, and the Phoenix FFI transport, end to end.
////
//// Run via `smoke/run.mjs`, which supplies a WebSocket global.

import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/option.{Some}

import tournament_bracket_lustre/bracket
import tournament_bracket_lustre/doc_schema
import watershed.{type Document, type RegisterCollection, WatershedConfig}
import watershed/register_collection_kernel.{Atomic}

const url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const secret = "levee-dev-secret-change-in-production"

const readiness_attempts = 100

const readiness_poll_ms = 100

const root_channel_adoption_attempts = 50

const root_channel_adoption_poll_ms = 100

const wait_attempts = 30

@external(javascript, "./smoke_ffi.mjs", "delay")
fn delay(ms: Int, callback: fn() -> Nil) -> Nil

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

type Readiness {
  Ready
  Pending
  Failed(String)
}

fn connect_client(
  document: String,
  user: String,
) -> Promise(Document(doc_schema.BracketDoc)) {
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

pub fn main() -> Nil {
  reset_readiness()

  let document =
    "bracket-smoke-" <> int.to_string(100_000 + int.random(900_000))
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
  doc_a: Document(doc_schema.BracketDoc),
  doc_b: Document(doc_schema.BracketDoc),
) -> Nil {
  log("smoke: ensuring matches channel on A")
  use matches_a <- ensure_matches(doc_a, "A")

  use adoption_ok <- wait_until_polling(
    root_channel_adoption_attempts,
    root_channel_adoption_poll_ms,
    fn() { root_channel_field_present(doc_b) },
  )
  case adoption_ok {
    False -> fail("root-channel adoption timeout waiting for matches on B")
    True -> Nil
  }

  log("smoke: adopting matches channel on B")
  use matches_b <- ensure_matches(doc_b, "B")

  report_phase(matches_a, matches_b)
}

fn report_phase(
  matches_a: RegisterCollection,
  matches_b: RegisterCollection,
) -> Nil {
  log("smoke: A reports the first quarterfinal")
  watershed.register_write(
    matches_a,
    "r1m1",
    bracket.to_json(bracket.MatchResult("Alaric", "3-1")),
  )

  use converged <- wait_until(wait_attempts, fn() {
    official(matches_a, "r1m1") == Some(bracket.MatchResult("Alaric", "3-1"))
    && official(matches_b, "r1m1") == Some(bracket.MatchResult("Alaric", "3-1"))
  })
  case converged {
    False -> fail("r1m1 result never converged to both clients")
    True -> {
      log("SMOKE PASS: reported match converged across both clients")
      exit(0)
    }
  }
}

fn ensure_matches(
  doc: Document(doc_schema.BracketDoc),
  who: String,
  then: fn(RegisterCollection) -> Nil,
) -> Nil {
  watershed.ensure_register_collection(
    doc,
    watershed.root_typed(doc),
    doc_schema.matches(),
    fn(result) {
      case result {
        Ok(collection) -> then(collection)
        Error(reason) ->
          fail("could not ensure matches on " <> who <> ": " <> reason)
      }
    },
  )
}

fn root_channel_field_present(doc: Document(doc_schema.BracketDoc)) -> Bool {
  let root = watershed.untyped(watershed.root_typed(doc))
  watershed.has(root, "matches")
}

fn official(
  matches: RegisterCollection,
  key: String,
) -> option.Option(bracket.MatchResult) {
  case watershed.register_read(matches, key, Atomic) {
    Ok(value) -> Some(bracket.from_json(value))
    Error(_) -> option.None
  }
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

fn fail(reason: String) -> Nil {
  log("SMOKE FAIL: " <> reason)
  exit(1)
}
