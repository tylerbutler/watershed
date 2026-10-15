import gleam/io
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import watershed/container
import watershed/tree/client_protocol
import watershed/tree/facade_fixture
import watershed/tree/schema
import watershed/tree/typed
import watershed/tree/types.{type TreeValue}

@target(erlang)
import envoy
@target(javascript)
import envoy as javascript_envoy
@target(javascript)
import gleam/javascript/promise.{type Promise}
@target(javascript)
import watershed as watershed_javascript
@target(erlang)
import watershed_beam

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
) -> #(
  container.CreateConfig,
  typed.Schema(facade_fixture.Dynamic, TreeValue),
  typed.Builder(facade_fixture.Dynamic, TreeValue),
  Option(TreeValue),
  String,
) {
  let assert Ok(stored) = schema.stored_from_string(schema_json)
  let assert Ok(view) = schema.view_from_json(schema.stored_to_json(stored))
  let assert Ok(definition) = facade_fixture.definition(view)
  let assert Ok(root) = client_protocol.decode_tree_value(root_json)
  let assert Ok(builder) = facade_fixture.builder(root)
  #(
    container.CreateConfig(base_url, tenant, token),
    definition,
    builder,
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
  let #(config, definition, builder, root, expected) =
    inputs(base_url, tenant, token, schema_json, root_json, expected)
  let outcome = case envoy.get("WATERSHED_TREE_CREATION_LAYOUT") {
    Error(_) ->
      watershed_beam.create_tree_container(config, definition, builder, root)
    Ok("graph") -> {
      use layout <- result.try(watershed_beam.with_initial_tree(
        graph_layout(),
        "B",
        "items",
        definition,
        builder,
        root,
      ))
      watershed_beam.create_tree_container_with_layout(
        config,
        definition,
        builder,
        root,
        layout,
      )
    }
    Ok(_) -> Error(typed.AccessFailed("unsupported creation probe layout"))
  }
  outcome
  |> result.map_error(string.inspect)
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
  let #(config, definition, builder, root, expected) =
    inputs(base_url, tenant, token, schema_json, root_json, expected)
  let pending = case javascript_envoy.get("WATERSHED_TREE_CREATION_LAYOUT") {
    Error(_) ->
      watershed_javascript.create_tree_container(
        config,
        definition,
        builder,
        root,
      )
    Ok("graph") -> {
      case
        watershed_javascript.with_initial_tree(
          graph_layout(),
          "B",
          "items",
          definition,
          builder,
          root,
        )
      {
        Error(error) -> promise.resolve(Error(error))
        Ok(layout) ->
          watershed_javascript.create_tree_container_with_layout(
            config,
            definition,
            builder,
            root,
            layout,
          )
      }
    }
    Ok(_) ->
      promise.resolve(
        Error(typed.AccessFailed("unsupported creation probe layout")),
      )
  }
  use outcome <- promise.await(pending)
  publish(result.map_error(outcome, string.inspect), expected)
  promise.resolve(Nil)
}
