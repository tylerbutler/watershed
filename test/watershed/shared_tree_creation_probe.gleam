import gleam/io
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/result
import watershed/container
import watershed/tree/client_protocol
import watershed/tree/schema
import watershed/tree/types.{type TreeValue}

@target(erlang)
import envoy
@target(javascript)
import envoy as javascript_envoy
@target(javascript)
import gleam/javascript/promise.{type Promise}

const marker = "WATERSHED_TREE_CREATION="

fn graph_layout() -> container.Layout {
  container.layout()
  |> container.with_data_store("B", Some("catalog"))
  |> container.with_data_store("C", None)
  |> container.with_map("B", "child", [#("value", json.string("initial child"))])
  |> container.with_binding("A", "root", "catalog", "B", "root")
  |> container.with_binding("B", "root", "tree", "B", "items")
  |> container.with_binding("B", "root", "child", "B", "child")
  |> container.with_binding("B", "child", "parent", "C", "root")
  |> container.with_binding("C", "root", "parent", "B", "root")
}

fn publish(result: Result(String, String), expected: String) -> Nil {
  let output = case result {
    Ok(document_id) ->
      json.object([
        #("ok", json.bool(True)),
        #("documentId", json.string(document_id)),
      ])
    Error(error) ->
      json.object([
        #("ok", json.bool(False)),
        #("error", json.string(error)),
      ])
  }
  io.println(marker <> json.to_string(output))
  let assert True = case expected, result {
    "success", Ok(_) | "failure", Error(_) -> True
    _, _ -> False
  }
  Nil
}

fn inputs(
  base_url: String,
  tenant: String,
  token: String,
  schema_json: String,
  root_json: String,
  expected: String,
) -> #(container.CreateConfig, schema.StoredSchema, Option(TreeValue), String) {
  let assert Ok(stored) = schema.stored_from_string(schema_json)
  let assert Ok(root) = client_protocol.decode_tree_value(root_json)
  #(
    container.CreateConfig(base_url, tenant, token),
    stored,
    Some(root),
    expected,
  )
}

@target(erlang)
pub fn main() -> Nil {
  let assert Ok(base_url) = envoy.get("WATERSHED_TREE_CREATION_URL")
  let assert Ok(tenant) = envoy.get("WATERSHED_TREE_CREATION_TENANT")
  let assert Ok(token) = envoy.get("WATERSHED_TREE_CREATION_TOKEN")
  let assert Ok(schema_json) = envoy.get("WATERSHED_TREE_CREATION_SCHEMA")
  let assert Ok(root_json) = envoy.get("WATERSHED_TREE_CREATION_ROOT")
  let assert Ok(expected) = envoy.get("WATERSHED_TREE_CREATION_EXPECT")
  let #(config, stored, root, expected) =
    inputs(base_url, tenant, token, schema_json, root_json, expected)
  let outcome = case envoy.get("WATERSHED_TREE_CREATION_LAYOUT") {
    Error(_) -> container.create_tree(config, stored, root)
    Ok("graph") -> {
      let layout =
        graph_layout() |> container.with_tree("B", "items", stored, root)
      container.create_tree_with_layout(config, stored, root, layout)
    }
    Ok(_) ->
      Error(container.InvalidConfiguration("Unsupported creation probe layout"))
  }
  outcome
  |> result.map_error(container.error_to_string)
  |> publish(expected)
}

@target(javascript)
pub fn main() -> Promise(Nil) {
  let assert Ok(base_url) = javascript_envoy.get("WATERSHED_TREE_CREATION_URL")
  let assert Ok(tenant) = javascript_envoy.get("WATERSHED_TREE_CREATION_TENANT")
  let assert Ok(token) = javascript_envoy.get("WATERSHED_TREE_CREATION_TOKEN")
  let assert Ok(schema_json) =
    javascript_envoy.get("WATERSHED_TREE_CREATION_SCHEMA")
  let assert Ok(root_json) =
    javascript_envoy.get("WATERSHED_TREE_CREATION_ROOT")
  let assert Ok(expected) =
    javascript_envoy.get("WATERSHED_TREE_CREATION_EXPECT")
  let #(config, stored, root, expected) =
    inputs(base_url, tenant, token, schema_json, root_json, expected)
  let pending = case javascript_envoy.get("WATERSHED_TREE_CREATION_LAYOUT") {
    Error(_) -> container.create_tree(config, stored, root)
    Ok("graph") -> {
      let layout =
        graph_layout() |> container.with_tree("B", "items", stored, root)
      container.create_tree_with_layout(config, stored, root, layout)
    }
    Ok(_) ->
      promise.resolve(
        Error(container.InvalidConfiguration(
          "Unsupported creation probe layout",
        )),
      )
  }
  use outcome <- promise.await(pending)
  publish(result.map_error(outcome, container.error_to_string), expected)
  promise.resolve(Nil)
}
