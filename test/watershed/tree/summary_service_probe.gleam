//// Exercises ordinary summary load and publication over Floodgate.

import gleam/dict
import gleam/option.{None, Some}
@target(javascript)
import gleam/result
import gleam/string
import signet/types as token
import spillway/message
import spillway/types as spillway_types

@target(javascript)
import gleam/javascript/promise.{type Promise}
@target(javascript)
import watershed/runtime
import watershed/tree/types.{SetField, StringValue}

@target(javascript)
@external(javascript, "./summary_service_ffi.mjs", "waitUntil")
fn wait_until(ready: fn() -> Bool) -> Promise(Bool)

@target(erlang)
import envoy
@target(erlang)
import gleam/erlang/process
@target(erlang)
import gleam/int
@target(erlang)
import gleam/io
@target(erlang)
import watershed/runtime_beam
@target(erlang)
import watershed/summary_policy

fn tree_address(root: String) -> Result(String, String) {
  case string.split(root, "/") {
    [store, _] -> Ok(store <> "/_C")
    _ -> Error("root map address has no datastore")
  }
}

fn connect_message(document: String, jwt: String) -> message.ConnectMessage {
  message.ConnectMessage(
    tenant_id: "fluid",
    document_id: document,
    token: Some(jwt),
    client: spillway_types.Client(
      mode: spillway_types.WriteMode,
      details: spillway_types.ClientDetails(
        capabilities: spillway_types.ClientCapabilities(interactive: True),
        client_type: None,
        environment: None,
        device: None,
      ),
      permission: [],
      user: token.User("summary-probe", dict.new()),
      scopes: ["doc:read", "doc:write", "summary:write"],
      timestamp: None,
    ),
    versions: ["^0.1.0"],
    driver_version: None,
    mode: spillway_types.WriteMode,
    nonce: None,
    epoch: None,
    supported_features: None,
    relay_user_agent: None,
  )
}

@target(javascript)
pub fn publish_javascript(
  socket_url: String,
  document: String,
  jwt: String,
) -> Promise(Result(String, String)) {
  edit_javascript(socket_url, document, jwt, "native-javascript-edit", True)
}

@target(javascript)
pub fn edit_javascript(
  socket_url: String,
  document: String,
  jwt: String,
  title: String,
  publish: Bool,
) -> Promise(Result(String, String)) {
  let #(ready, signal) = promise.start()
  let actor =
    runtime.start(
      url: socket_url,
      topic: "document:fluid:" <> document,
      connect_message: connect_message(document, jwt),
      on_ready: signal,
    )
  use ready_result <- promise.await(ready)
  case ready_result {
    Error(detail) -> {
      runtime.close(actor)
      promise.resolve(Error(detail))
    }
    Ok(Nil) -> {
      let edit = {
        use root <- result.try(runtime.resolve_root(actor))
        use address <- result.try(tree_address(root))
        runtime.tree_edit(
          actor,
          address,
          SetField(["title"], StringValue(title)),
        )
      }
      case edit {
        Error(detail) -> {
          runtime.close(actor)
          promise.resolve(Error(detail))
        }
        Ok(Nil) -> publish_after_edit(actor, title, publish)
      }
    }
  }
}

@target(javascript)
fn publish_after_edit(
  actor: runtime.Runtime,
  title: String,
  publish: Bool,
) -> Promise(Result(String, String)) {
  use synced <- promise.await(
    wait_until(fn() { runtime.diagnostics(actor).synced }),
  )
  case synced {
    False -> {
      runtime.close(actor)
      promise.resolve(Error("native edit was not acknowledged"))
    }
    True ->
      case publish {
        True -> {
          use result <- promise.await(runtime.summarize(actor))
          runtime.close(actor)
          promise.resolve(result)
        }
        False -> {
          runtime.close(actor)
          promise.resolve(Ok(title))
        }
      }
  }
}

@target(erlang)
pub fn main() {
  let assert Ok(host) = envoy.get("WATERSHED_TREE_HOST")
  let assert Ok(raw_port) = envoy.get("WATERSHED_TREE_PORT")
  let assert Ok(port) = int.parse(raw_port)
  let assert Ok(document) = envoy.get("WATERSHED_TREE_DOCUMENT")
  let assert Ok(jwt) = envoy.get("WATERSHED_TREE_TOKEN")
  let assert Ok(actor) =
    runtime_beam.start(
      host: host,
      port: port,
      path: "/socket/websocket?vsn=2.0.0",
      tenant: "fluid",
      document: document,
      connect_message: connect_message(document, jwt),
    )
  let assert Ok(Nil) = runtime_beam.await_ready(actor)
  let assert Ok(versions) = runtime_beam.get_versions(actor, 1)
  let assert [latest] = versions
  let assert Ok(snapshot) = runtime_beam.load_version(actor, latest.id)
  let assert True = snapshot.sequence_number > 0
  let assert Ok(root) = runtime_beam.resolve_root(actor)
  let assert Ok(address) = tree_address(root)
  let assert Ok(title) = envoy.get("WATERSHED_TREE_TITLE")
  let assert Ok(publish) = envoy.get("WATERSHED_TREE_PUBLISH")
  let assert Ok(auto_summary) = envoy.get("WATERSHED_TREE_AUTO")
  case auto_summary {
    "true" ->
      runtime_beam.auto_summarize(
        actor,
        Some(
          summary_policy.policy()
          |> summary_policy.with_threshold(1)
          |> summary_policy.with_jitter_milliseconds(0),
        ),
      )
    "false" -> Nil
    _ -> panic as "WATERSHED_TREE_AUTO must be true or false"
  }
  let assert Ok(Nil) =
    runtime_beam.tree_edit(
      actor,
      address,
      SetField(["title"], StringValue(title)),
    )
  let assert Ok(Nil) = wait_synced(actor, 400)
  case publish {
    "true" -> {
      let assert Ok(version) = runtime_beam.summarize(actor)
      io.println("WATERSHED_TREE_VERSION=" <> version)
    }
    "false" -> {
      case auto_summary {
        "true" -> process.sleep(2000)
        "false" -> Nil
        _ -> panic as "WATERSHED_TREE_AUTO must be true or false"
      }
      io.println("WATERSHED_TREE_EDITED=" <> title)
    }
    _ -> panic as "WATERSHED_TREE_PUBLISH must be true or false"
  }
}

@target(erlang)
fn wait_synced(
  actor: process.Subject(runtime_beam.Msg),
  remaining: Int,
) -> Result(Nil, String) {
  case runtime_beam.is_synced(actor), remaining {
    True, _ -> Ok(Nil)
    False, 0 -> Error("native edit was not acknowledged")
    False, _ -> {
      process.sleep(25)
      wait_synced(actor, remaining - 1)
    }
  }
}
