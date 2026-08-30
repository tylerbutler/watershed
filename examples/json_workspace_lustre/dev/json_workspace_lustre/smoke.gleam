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
import gleam/list

import watershed.{
  type Document, type JsonOt, type SharedDirectory, WatershedConfig,
}
import watershed/json_ot.{type JsonValue, Key}

import json_workspace_lustre/document_schema

const url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const secret = "levee-dev-secret-change-in-production"

@external(javascript, "./smoke_ffi.mjs", "delay")
fn delay(milliseconds: Int, callback: fn() -> Nil) -> Nil

@external(javascript, "./smoke_ffi.mjs", "log")
fn log(message: String) -> Nil

@external(javascript, "./smoke_ffi.mjs", "exit")
fn exit(code: Int) -> Nil

fn connect_client(
  document: String,
  user: String,
) -> Promise(Document(document_schema.Workspace)) {
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
  let document =
    "json-workspace-smoke-" <> int.to_string(100_000 + int.random(900_000))
  log("smoke: document " <> document)

  let _ = {
    use document_a <- promise.await(connect_client(document, "user-a"))
    use document_b <- promise.map(connect_client(document, "user-b"))
    start(document_a, document_b)
  }
  Nil
}

fn start(
  document_a: Document(document_schema.Workspace),
  document_b: Document(document_schema.Workspace),
) -> Nil {
  // Let both handshakes land before anyone attaches the tree channel.
  use <- delay(2000)
  log("smoke: A seeds the tree")
  watershed.ensure_directory(
    document_a,
    watershed.root_typed(document_a),
    document_schema.tree(),
    fn(result) {
      case result {
        Error(reason) -> fail("A could not ensure the tree: " <> reason)
        Ok(directory_a) -> adopt_on_b(document_a, document_b, directory_a)
      }
    },
  )
}

fn adopt_on_b(
  document_a: Document(document_schema.Workspace),
  document_b: Document(document_schema.Workspace),
  directory_a: SharedDirectory,
) -> Nil {
  use <- delay(1500)
  log("smoke: B adopts the tree")
  watershed.ensure_directory(
    document_b,
    watershed.root_typed(document_b),
    document_schema.tree(),
    fn(result) {
      case result {
        Error(reason) -> fail("B could not adopt the tree: " <> reason)
        Ok(directory_b) ->
          create_and_open(document_a, document_b, directory_a, directory_b)
      }
    },
  )
}

fn create_and_open(
  document_a: Document(document_schema.Workspace),
  document_b: Document(document_schema.Workspace),
  directory_a: SharedDirectory,
  directory_b: SharedDirectory,
) -> Nil {
  log("smoke: A creates /specs and /specs/api")
  watershed.directory_create_subdirectory(directory_a, "/", "specs")

  let assert Ok(channel_a) = watershed.create_json_ot(document_a)
  watershed.directory_set(
    directory_a,
    "/specs",
    "api",
    watershed.json_ot_handle_of(channel_a),
  )

  use <- delay(2000)
  log("smoke: B opens /specs/api")
  case watershed.directory_get(directory_b, "/specs", "api") {
    Ok(value) ->
      case watershed.resolve_json_ot(document_b, value) {
        Ok(channel_b) ->
          run_scenario(document_a, document_b, channel_a, channel_b)
        Error(reason) -> fail("B could not resolve the document: " <> reason)
      }
    Error(Nil) -> fail("B did not see /specs/api")
  }
}

fn run_scenario(
  document_a: Document(document_schema.Workspace),
  document_b: Document(document_schema.Workspace),
  channel_a: JsonOt,
  channel_b: JsonOt,
) -> Nil {
  log("smoke: both go offline and edit different keys")
  watershed.go_offline(document_a)
  watershed.go_offline(document_b)
  watershed.submit_json_ot(channel_a, [
    json_ot.obj_insert([Key("title")], json_ot.VString("field notes")),
  ])
  watershed.submit_json_ot(channel_b, [
    json_ot.obj_insert([Key("version")], json_ot.VNumber(json_ot.NInt(1))),
  ])

  use <- delay(500)
  let isolated =
    member(view(channel_b), "title") == Error(Nil)
    && member(view(channel_a), "version") == Error(Nil)
  log("  A while offline: " <> ok_or_missing(member(view(channel_a), "title")))

  log("smoke: both reconnect")
  watershed.go_online(document_a)
  watershed.go_online(document_b)

  use <- delay(3000)
  let converged_a =
    member(view(channel_a), "title") == Ok(json_ot.VString("field notes"))
    && member(view(channel_a), "version")
    == Ok(json_ot.VNumber(json_ot.NInt(1)))
  let converged_b =
    member(view(channel_b), "title") == Ok(json_ot.VString("field notes"))
    && member(view(channel_b), "version")
    == Ok(json_ot.VNumber(json_ot.NInt(1)))
  log("  A after rejoin: " <> ok_or_missing(member(view(channel_a), "version")))
  log("  B after rejoin: " <> ok_or_missing(member(view(channel_b), "title")))

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
        <> bool_to_string(isolated)
        <> " converged_a="
        <> bool_to_string(converged_a)
        <> " converged_b="
        <> bool_to_string(converged_b),
      )
      exit(1)
    }
  }
}

fn view(channel: JsonOt) -> JsonValue {
  case watershed.json_ot_view(channel) {
    Ok(value) -> value
    Error(Nil) -> json_ot.VObject([])
  }
}

fn member(value: JsonValue, key: String) -> Result(JsonValue, Nil) {
  case value {
    json_ot.VObject(members) -> list.key_find(members, key)
    json_ot.VNull -> Error(Nil)
    json_ot.VBool(_) -> Error(Nil)
    json_ot.VNumber(_) -> Error(Nil)
    json_ot.VString(_) -> Error(Nil)
    json_ot.VArray(_) -> Error(Nil)
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
    json_ot.VString(text) -> text
    json_ot.VNumber(json_ot.NInt(integer)) -> int.to_string(integer)
    json_ot.VNumber(json_ot.NFloat(_)) -> "?"
    json_ot.VNull -> "?"
    json_ot.VBool(_) -> "?"
    json_ot.VArray(_) -> "?"
    json_ot.VObject(_) -> "?"
  }
}

fn fail(reason: String) -> Nil {
  log("SMOKE FAIL: " <> reason)
  exit(1)
}

fn bool_to_string(value: Bool) -> String {
  case value {
    True -> "true"
    False -> "false"
  }
}
