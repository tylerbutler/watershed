//// Headless smoke test: drive two `watershed` clients against a live
//// floodgate dev server (`just integration-up`) from Node and assert that
//// the workspace converges end to end — the directory kernel, the JSON-OT
//// kernel, their wire codecs, the JS runtime, the Phoenix FFI transport, and
//// the pure core, all working together the way the browser app uses them.
////
//// The headline assertion is the demo's second race: two clients open the
//// same document, go offline, each edits a different key, and both edits
//// present on both clients after they reconnect. The deterministic
//// same-name-creation and stale-recreate races live in
//// `test/convergence_test.gleam` against the in-memory sluice, which can
//// force the exact interleaving those races need; this smoke test only has
//// wall-clock delays to work with, so it exercises the reconnect happy path
//// a live server actually round-trips through.
////
//// Run via `smoke/run.mjs`, which supplies a WebSocket global.

import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/option.{None, Some}

import doc_schema
import watershed.{
  type Document, type JsonOt, type SharedDirectory, WatershedConfig,
}
import watershed/json_ot.{type JsonValue, Key}

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
) -> Promise(Document(doc_schema.Workspace)) {
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
    "json-workspace-smoke-" <> int.to_string(100_000 + int.random(900_000))
  log("smoke: document " <> document)

  let _ = {
    use doc_a <- promise.await(connect_client(document, "user-a"))
    use doc_b <- promise.map(connect_client(document, "user-b"))
    start(doc_a, doc_b)
  }
  Nil
}

fn start(
  doc_a: Document(doc_schema.Workspace),
  doc_b: Document(doc_schema.Workspace),
) -> Nil {
  // Let both handshakes land before anyone attaches the tree channel.
  use <- delay(2000)
  log("smoke: A seeds the tree")
  watershed.ensure_directory(
    doc_a,
    watershed.root_typed(doc_a),
    doc_schema.tree(),
    fn(result) {
      case result {
        Error(reason) -> fail("A could not ensure the tree: " <> reason)
        Ok(dir_a) -> adopt_on_b(doc_a, doc_b, dir_a)
      }
    },
  )
}

fn adopt_on_b(
  doc_a: Document(doc_schema.Workspace),
  doc_b: Document(doc_schema.Workspace),
  dir_a: SharedDirectory,
) -> Nil {
  use <- delay(1500)
  log("smoke: B adopts the tree")
  watershed.ensure_directory(
    doc_b,
    watershed.root_typed(doc_b),
    doc_schema.tree(),
    fn(result) {
      case result {
        Error(reason) -> fail("B could not adopt the tree: " <> reason)
        Ok(dir_b) -> create_and_open(doc_a, doc_b, dir_a, dir_b)
      }
    },
  )
}

fn create_and_open(
  doc_a: Document(doc_schema.Workspace),
  doc_b: Document(doc_schema.Workspace),
  dir_a: SharedDirectory,
  dir_b: SharedDirectory,
) -> Nil {
  log("smoke: A creates /specs and /specs/api")
  watershed.directory_create_subdirectory(dir_a, "/", "specs")

  let assert Ok(a) = watershed.create_json_ot(doc_a)
  watershed.directory_set(
    dir_a,
    "/specs",
    "api",
    watershed.json_ot_handle_of(a),
  )

  use <- delay(2000)
  log("smoke: B opens /specs/api")
  case watershed.directory_get(dir_b, "/specs", "api") {
    Some(value) ->
      case watershed.resolve_json_ot(doc_b, value) {
        Ok(b) -> run_scenario(doc_a, doc_b, a, b)
        Error(reason) -> fail("B could not resolve the document: " <> reason)
      }
    None -> fail("B did not see /specs/api")
  }
}

fn run_scenario(
  doc_a: Document(doc_schema.Workspace),
  doc_b: Document(doc_schema.Workspace),
  a: JsonOt,
  b: JsonOt,
) -> Nil {
  log("smoke: both go offline and edit different keys")
  watershed.go_offline(doc_a)
  watershed.go_offline(doc_b)
  watershed.submit_json_ot(a, [
    json_ot.obj_insert([Key("title")], json_ot.VString("field notes")),
  ])
  watershed.submit_json_ot(b, [
    json_ot.obj_insert([Key("version")], json_ot.VNumber(json_ot.NInt(1))),
  ])

  use <- delay(500)
  let isolated =
    member(view(b), "title") == Error(Nil)
    && member(view(a), "version") == Error(Nil)
  log("  A while offline: " <> ok_or_missing(member(view(a), "title")))

  log("smoke: both reconnect")
  watershed.go_online(doc_a)
  watershed.go_online(doc_b)

  use <- delay(3000)
  let converged_a =
    member(view(a), "title") == Ok(json_ot.VString("field notes"))
    && member(view(a), "version") == Ok(json_ot.VNumber(json_ot.NInt(1)))
  let converged_b =
    member(view(b), "title") == Ok(json_ot.VString("field notes"))
    && member(view(b), "version") == Ok(json_ot.VNumber(json_ot.NInt(1)))
  log("  A after rejoin: " <> ok_or_missing(member(view(a), "version")))
  log("  B after rejoin: " <> ok_or_missing(member(view(b), "title")))

  case isolated && converged_a && converged_b {
    True -> {
      log(
        "SMOKE PASS: the workspace converged, and divergent edits survived a reconnect",
      )
      exit(0)
    }
    False -> {
      log(
        "SMOKE FAIL: isolated="
        <> bool_str(isolated)
        <> " converged_a="
        <> bool_str(converged_a)
        <> " converged_b="
        <> bool_str(converged_b),
      )
      exit(1)
    }
  }
}

fn view(channel: JsonOt) -> JsonValue {
  case watershed.json_ot_view(channel) {
    Some(value) -> value
    _ -> json_ot.VObject([])
  }
}

fn member(value: JsonValue, key: String) -> Result(JsonValue, Nil) {
  case value {
    json_ot.VObject(members) ->
      case list_key_find(members, key) {
        Ok(v) -> Ok(v)
        Error(_) -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

fn list_key_find(
  members: List(#(String, JsonValue)),
  key: String,
) -> Result(JsonValue, Nil) {
  case members {
    [] -> Error(Nil)
    [#(k, v), ..rest] ->
      case k == key {
        True -> Ok(v)
        False -> list_key_find(rest, key)
      }
  }
}

fn ok_or_missing(result: Result(JsonValue, Nil)) -> String {
  case result {
    Ok(value) -> json_ot_inspect(value)
    Error(Nil) -> "(missing)"
  }
}

fn json_ot_inspect(value: JsonValue) -> String {
  case value {
    json_ot.VString(s) -> s
    json_ot.VNumber(json_ot.NInt(n)) -> int.to_string(n)
    _ -> "?"
  }
}

fn fail(reason: String) -> Nil {
  log("SMOKE FAIL: " <> reason)
  exit(1)
}

fn bool_str(b: Bool) -> String {
  case b {
    True -> "true"
    False -> "false"
  }
}
