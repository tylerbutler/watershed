@target(erlang)
import gleam/erlang/process
@target(javascript)
import gleam/javascript/promise.{type Promise}
@target(javascript)
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import startest/expect
@target(javascript)
import watershed
import watershed/container
@target(javascript)
import watershed/fluid_ids
@target(erlang)
import watershed/fluid_ids
import watershed/git_storage
@target(javascript)
import watershed/runtime
@target(erlang)
import watershed/runtime_beam
@target(javascript)
import watershed/runtime_core
@target(erlang)
import watershed/runtime_core
@target(javascript)
import watershed/sluice/frame
@target(erlang)
import watershed/sluice/frame
@target(javascript)
import watershed/transport_js
import watershed/tree
import watershed/tree/error
@target(erlang)
import watershed/tree/identifier_fixture
import watershed/tree/schema
import watershed/tree/schema_builder as builder
import watershed/tree/types
@target(javascript)
import watershed/wire/fluid_document
@target(erlang)
import watershed/wire/fluid_document
import watershed/wire/fluid_summary
@target(erlang)
import watershed_beam

fn stored() -> schema.StoredSchema {
  let assert Ok(stored) =
    schema.stored_from_string(
      "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}}},\"root\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}",
    )
  stored
}

fn invalid_declaration() -> builder.Root(List(String)) {
  builder.array(builder.factory(""), "Items", builder.string())
  |> builder.root
}

@target(erlang)
pub fn tree_api_rejects_invalid_declaration_before_network_test() {
  let declaration = invalid_declaration()
  let expected =
    error.InvalidSchema(types.InvalidSchema(
      "Schema scope and name must not be empty",
    ))
  watershed_beam.create_tree_container(
    container.CreateConfig("http://127.0.0.1:1", "tenant", "not-a-secret"),
    declaration,
    [],
  )
  |> expect.to_equal(Error(expected))
  watershed_beam.with_initial_tree(
    container.layout(),
    "B",
    "items",
    declaration,
    [],
  )
  |> expect.to_equal(Error(expected))
}

@target(javascript)
pub fn check_invalid_declaration_api() -> Promise(Nil) {
  let declaration = invalid_declaration()
  let expected =
    error.InvalidSchema(types.InvalidSchema(
      "Schema scope and name must not be empty",
    ))
  watershed.with_initial_tree(container.layout(), "B", "items", declaration, [])
  |> expect.to_equal(Error(expected))
  watershed.create_tree_container(
    container.CreateConfig("http://127.0.0.1:1", "tenant", "not-a-secret"),
    declaration,
    [],
  )
  |> promise.map(fn(outcome) { outcome |> expect.to_equal(Error(expected)) })
}

@target(javascript)
pub fn native_created_tree_supports_revertible_facade_test() {
  let stored = stored()
  let session =
    fluid_ids.session_id("30000000-0000-4000-8000-000000000003")
    |> expect.to_be_ok()
  let view_id =
    fluid_ids.stable_id("40000000-0000-4000-8000-000000000004")
    |> expect.to_be_ok()
  let summary =
    fluid_document.initial_tree(
      stored,
      Some(types.StringValue("initial")),
      session,
      view_id,
    )
    |> expect.to_be_ok()
  let seed = runtime_core.document_seed(summary) |> expect.to_be_ok()
  let callbacks = transport_js.new_cell(None)
  let document =
    watershed.connect_via_seed(
      tenant: "default",
      document: "tree",
      user_id: "reader",
      seed: seed,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(_, _) { Nil },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(_) { Nil },
    )
  let assert Some(callbacks) = transport_js.get_cell(callbacks)
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  let assert Error(error.InvalidSchema(_)) =
    watershed.open_tree(document, invalid_declaration())
  let assert Error(error.InvalidSchema(_)) =
    watershed.create_tree(document, invalid_declaration(), [])
  let tree =
    watershed.open_tree(document, builder.string() |> builder.root)
    |> expect.to_be_ok()
  tree.read_root(tree) |> expect.to_equal(Ok("initial"))
  let handle = transport_js.new_cell(None)
  let token =
    tree.subscribe_commits(tree, fn(event) {
      event.local |> expect.to_equal(True)
      let acquired =
        tree.get_revertible(event, fn(_) { Nil }) |> expect.to_be_ok()
      transport_js.set_cell(
        handle,
        Some(#(acquired, tree.revertible_revision(acquired))),
      )
    })
    |> expect.to_be_ok()
  tree.replace_root(tree, "changed")
  |> expect.to_equal(Ok(Nil))
  let assert Some(#(handle, revision)) = transport_js.get_cell(handle)
  tree.revert(handle, tree.DisposeRevertible) |> expect.to_equal(Ok(Nil))
  tree.read_root(tree) |> expect.to_equal(Ok("initial"))
  tree.revertible_revision(handle) |> expect.to_equal(revision)
  tree.unsubscribe(token)
  watershed.close(document)
  tree.revertible_revision(handle) |> expect.to_equal(revision)
}

@target(erlang)
pub fn native_created_tree_supports_beam_revertible_facade_test() {
  let stored = stored()
  let session =
    fluid_ids.session_id("30000000-0000-4000-8000-000000000003")
    |> expect.to_be_ok()
  let view_id =
    fluid_ids.stable_id("40000000-0000-4000-8000-000000000004")
    |> expect.to_be_ok()
  let summary =
    fluid_document.initial_tree(
      stored,
      Some(types.StringValue("initial")),
      session,
      view_id,
    )
    |> expect.to_be_ok()
  let seed = runtime_core.document_seed(summary) |> expect.to_be_ok()
  let connections = process.new_subject()
  let handles = process.new_subject()
  let document =
    watershed_beam.connect_via_seed(
      tenant: "default",
      document: "tree",
      user_id: "reader",
      seed: seed,
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(connections, callbacks)
      }),
    )
    |> expect.to_be_ok()
  let callbacks = process.receive(connections, 1000) |> expect.to_be_ok()
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  let assert Error(error.InvalidSchema(_)) =
    watershed_beam.open_tree(document, invalid_declaration())
  let assert Error(error.InvalidSchema(_)) =
    watershed_beam.create_tree(document, invalid_declaration(), [])
  let tree =
    watershed_beam.open_tree(document, builder.string() |> builder.root)
    |> expect.to_be_ok()
  tree.read_root(tree) |> expect.to_equal(Ok("initial"))
  let token =
    tree.subscribe_commits(tree, fn(event) {
      event.local |> expect.to_equal(True)
      let acquired =
        tree.get_revertible(event, fn(_) { Nil }) |> expect.to_be_ok()
      process.send(handles, #(acquired, tree.revertible_revision(acquired)))
    })
    |> expect.to_be_ok()
  tree.replace_root(tree, "changed")
  |> expect.to_equal(Ok(Nil))
  let #(handle, revision) = process.receive(handles, 1000) |> expect.to_be_ok()
  tree.revert(handle, tree.DisposeRevertible) |> expect.to_equal(Ok(Nil))
  tree.read_root(tree) |> expect.to_equal(Ok("initial"))
  tree.revertible_revision(handle) |> expect.to_equal(revision)
  tree.unsubscribe(token)
  watershed_beam.close(document)
  tree.revertible_revision(handle) |> expect.to_equal(revision)
}

@target(erlang)
pub fn shared_tree_creation_checks_initial_value_before_network_test() -> Nil {
  let assert Error(container.InvalidInitialTree(_)) =
    container.create_tree(
      container.CreateConfig("http://127.0.0.1:1", "tenant", "not-a-secret"),
      stored(),
      None,
    )
  Nil
}

@target(erlang)
pub fn shared_tree_creation_typed_layout_checks_graph_before_network_test() {
  let declaration = builder.string() |> builder.root
  let layout =
    container.layout()
    |> container.with_data_store("B", Some("public"))
    |> watershed_beam.with_initial_tree("B", "items", declaration, "secondary")
    |> expect.to_be_ok()
    |> container.with_binding("A", "root", "other", "B", "root")
    |> container.with_data_store("B", None)
  let assert Error(error.CreationFailed(container.InvalidSummary(fluid_summary.MalformedEntry(
    path,
    reason,
  )))) =
    watershed_beam.create_tree_container_with_layout(
      container.CreateConfig("http://127.0.0.1:1", "tenant", "not-a-secret"),
      declaration,
      "secondary",
      layout,
    )
  path |> expect.to_equal("/.channels/B")
  reason |> expect.to_equal("duplicate initial datastore")
}

@target(javascript)
pub fn check_declared_layout_api() -> Promise(Nil) {
  let declaration = builder.string() |> builder.root
  let layout =
    container.layout()
    |> container.with_data_store("B", Some("public"))
    |> watershed.with_initial_tree("B", "items", declaration, "secondary")
    |> expect.to_be_ok()
    |> container.with_binding("A", "root", "other", "B", "root")
    |> container.with_data_store("B", None)
  watershed.create_tree_container_with_layout(
    container.CreateConfig("http://127.0.0.1:1", "tenant", "not-a-secret"),
    declaration,
    "secondary",
    layout,
  )
  |> promise.map(fn(outcome) {
    let assert Error(error.CreationFailed(container.InvalidSummary(fluid_summary.MalformedEntry(
      path,
      reason,
    )))) = outcome
    path |> expect.to_equal("/.channels/B")
    reason |> expect.to_equal("duplicate initial datastore")
  })
}

type Initial {
  Text(String)
  Unsupported
}

fn partial_schema() -> builder.Root(Initial) {
  builder.union([
    builder.variant(builder.string(), Text, fn(value) {
      case value {
        Text(text) -> Some(text)
        Unsupported -> None
      }
    }),
  ])
  |> builder.root
}

@target(erlang)
pub fn tree_api_creation_preserves_invalid_value_before_network_test() {
  let declaration = partial_schema()
  let assert Ok(compiled) = builder.compile(declaration)
  let assert Error(original) = builder.encode_new(compiled, Unsupported)
  watershed_beam.create_tree_container(
    container.CreateConfig("http://127.0.0.1:1", "tenant", "not-a-secret"),
    declaration,
    Unsupported,
  )
  |> expect.to_equal(Error(error.InvalidValue(original)))
}

@target(erlang)
pub fn tree_api_creation_preserves_nested_storage_failure_test() {
  let declaration = builder.string() |> builder.root
  let assert Error(error.CreationFailed(container.StorageFailed(git_storage.RequestFailed(
    url,
    detail,
  )))) =
    watershed_beam.create_tree_container(
      container.CreateConfig("http://127.0.0.1:1", "tenant", "not-a-secret"),
      declaration,
      "Created",
    )
  string.contains(url, "/documents/tenant") |> expect.to_be_true
  expect.to_equal(detail == "", False)
}

@target(javascript)
pub fn check_creation_error_payloads() -> Promise(Nil) {
  let config =
    container.CreateConfig("http://127.0.0.1:1", "tenant", "not-a-secret")
  let partial = partial_schema()
  let assert Ok(compiled) = builder.compile(partial)
  let assert Error(original) = builder.encode_new(compiled, Unsupported)
  use invalid <- promise.await(watershed.create_tree_container(
    config,
    partial,
    Unsupported,
  ))
  invalid |> expect.to_equal(Error(error.InvalidValue(original)))
  let declaration = builder.string() |> builder.root
  use outcome <- promise.await(watershed.create_tree_container(
    config,
    declaration,
    "Created",
  ))
  let assert Error(error.CreationFailed(container.StorageFailed(git_storage.RequestFailed(
    url,
    detail,
  )))) = outcome
  string.contains(url, "/documents/tenant") |> expect.to_be_true
  expect.to_equal(detail == "", False)
  promise.resolve(Nil)
}

@target(erlang)
pub fn shared_tree_creation_accepts_missing_identifier_before_network_test() {
  let initial =
    types.ObjectValue(identifier_fixture.point_type, [
      #("label", types.StringValue("generated")),
    ])
  let assert Error(container.StorageFailed(_)) =
    container.create_tree(
      container.CreateConfig("http://127.0.0.1:1", "tenant", "not-a-secret"),
      identifier_fixture.stored(),
      Some(initial),
    )
  Nil
}

@target(erlang)
pub fn shared_tree_creation_rejects_unsafe_configuration_test() -> Nil {
  list.each(
    [
      container.CreateConfig("file:///tmp/create", "tenant", "token"),
      container.CreateConfig("http://user:pass@127.0.0.1", "tenant", "token"),
      container.CreateConfig("http://127.0.0.1?token=secret", "tenant", "token"),
      container.CreateConfig("http://127.0.0.1#fragment", "tenant", "token"),
      container.CreateConfig("http://127.0.0.1:65536", "tenant", "token"),
      container.CreateConfig("http://bad host", "tenant", "token"),
      container.CreateConfig("http://127.0.0.1", "", "token"),
      container.CreateConfig("http://127.0.0.1", "tenant", ""),
      container.CreateConfig("http://127.0.0.1:1", ".", "token"),
      container.CreateConfig("http://127.0.0.1:1", "..", "token"),
      container.CreateConfig("http://127.0.0.1:1", "tenant", "bad\u{0}token"),
      container.CreateConfig("http://127.0.0.1:1", "tenant", "bad token"),
      container.CreateConfig("http://127.0.0.1:1", "tenant", "bad\u{2603}token"),
    ],
    fn(config) {
      let assert Error(container.InvalidConfiguration(_)) =
        container.create_tree(
          config,
          stored(),
          Some(types.StringValue("initial")),
        )
      Nil
    },
  )
}

pub fn shared_tree_creation_storage_errors_do_not_echo_credentials_test() -> Nil {
  list.each(
    [
      git_storage.UnexpectedStatus("secret", 401, "secret"),
      git_storage.UnexpectedStatus("secret", 500, "secret"),
      git_storage.RequestFailed("secret", "secret"),
      git_storage.BodyReadFailed("secret", "secret"),
      git_storage.ResponseDecodeFailed("secret", "secret"),
      git_storage.BadRequestUrl("secret"),
    ],
    fn(error) {
      container.error_to_string(container.StorageFailed(error))
      |> string.contains("secret")
      |> expect.to_equal(False)
    },
  )
}
