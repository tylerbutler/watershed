@target(erlang)
import gleam/erlang/process
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
@target(erlang)
import watershed/tree/identifier_fixture
import watershed/tree/schema
import watershed/tree/types
@target(javascript)
import watershed/wire/fluid_document
@target(erlang)
import watershed/wire/fluid_document
@target(erlang)
import watershed_beam

fn stored() -> schema.StoredSchema {
  let assert Ok(stored) =
    schema.stored_from_string(
      "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}}},\"root\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}",
    )
  stored
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
  let root = watershed.resolve_root(document) |> expect.to_be_ok()
  let marker = watershed.get(root, "tree") |> expect.to_be_ok()
  let view =
    schema.view_from_json(schema.stored_to_json(stored))
    |> expect.to_be_ok()
  let tree = watershed.resolve_tree(document, marker, view) |> expect.to_be_ok()
  let handle = transport_js.new_cell(None)
  let token =
    watershed.subscribe_tree_commits(tree, fn(event) {
      let assert watershed.TreeCommitEvent(_, True, Some(get_revertible), _) =
        event
      transport_js.set_cell(handle, Some(get_revertible() |> expect.to_be_ok()))
    })
  watershed.tree_set(tree, [], types.StringValue("changed"))
  |> expect.to_equal(Ok(Nil))
  let assert Some(handle) = transport_js.get_cell(handle)
  watershed.tree_revert(handle, True) |> expect.to_equal(Ok(Nil))
  watershed.tree_get(tree, [])
  |> expect.to_equal(Ok(Some(types.StringValue("initial"))))
  watershed.unsubscribe(token)
  watershed.close(document)
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
  let root = watershed_beam.resolve_root(document) |> expect.to_be_ok()
  let marker = watershed_beam.get(root, "tree") |> expect.to_be_ok()
  let view =
    schema.view_from_json(schema.stored_to_json(stored))
    |> expect.to_be_ok()
  let tree =
    watershed_beam.resolve_tree(document, marker, view) |> expect.to_be_ok()
  let token =
    watershed_beam.subscribe_tree_commits(tree, fn(event) {
      let assert watershed_beam.TreeCommitEvent(_, True, Some(factory), _) =
        event
      process.send(handles, factory())
    })
  watershed_beam.tree_set(tree, [], types.StringValue("changed"))
  |> expect.to_equal(Ok(Nil))
  let handle =
    process.receive(handles, 1000) |> expect.to_be_ok() |> expect.to_be_ok()
  watershed_beam.tree_revert(handle, True) |> expect.to_equal(Ok(Nil))
  watershed_beam.tree_get(tree, [])
  |> expect.to_equal(Ok(Some(types.StringValue("initial"))))
  watershed_beam.unsubscribe(token)
  watershed_beam.close(document)
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
