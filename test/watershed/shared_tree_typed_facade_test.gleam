@target(erlang)
import gleam/erlang/process
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import startest/expect
@target(javascript)
import watershed
@target(javascript)
import watershed/runtime
@target(erlang)
import watershed/runtime_beam
import watershed/runtime_core
import watershed/sluice/frame
@target(javascript)
import watershed/transport_js
import watershed/tree/runtime_fixture
import watershed/tree/schema as tree_schema
import watershed/tree/typed
import watershed/tree/typed_facade_fixture
import watershed/tree/types
@target(erlang)
import watershed_beam

const items_type = "org.watershed.shared-tree.m3.Items"

pub type Items

pub type Text

fn input() -> runtime_core.BootstrapSeedInput {
  runtime_fixture.routed_array_seed_input(
    "rootArray",
    types.ArrayValue(items_type, [
      types.StringValue("A"),
      types.StringValue("B"),
    ]),
  )
  |> expect.to_be_ok()
}

fn object_input() -> runtime_core.BootstrapSeedInput {
  runtime_fixture.routed_tree_seed_input(
    typed_facade_fixture.stored(),
    typed_facade_fixture.view(),
    typed_facade_fixture.initial_root(),
  )
  |> expect.to_be_ok()
}

fn definition(
  view: tree_schema.ViewSchema,
) -> typed.Schema(Items, List(String)) {
  let codec =
    typed.node(items_type, fn(value) {
      let assert types.ArrayValue(_, values) = value
      list.try_map(values, fn(value) { typed.decode(typed.string(), value) })
    })
    |> expect.to_be_ok()
  typed.schema(view, codec) |> expect.to_be_ok()
}

fn text_codec() -> typed.NodeCodec(Text, String) {
  typed.node("com.fluidframework.leaf.string", fn(value) {
    typed.decode(typed.string(), value)
  })
  |> expect.to_be_ok()
}

fn text_builder() -> typed.Builder(Text, String) {
  typed.builder("com.fluidframework.leaf.string", fn(value) {
    typed.encode(typed.string(), value)
  })
  |> expect.to_be_ok()
}

fn connected(client: String) -> json.Json {
  frame.encode_connected(
    client_id: client,
    tenant_id: "default",
    document_id: "tree",
    scopes: ["doc:read", "doc:write"],
    checkpoint_sequence_number: 0,
    initial_clients: [client],
    initial_messages: [],
    timestamp: 0,
    presence_v1: False,
  )
}

@target(javascript)
pub fn shared_tree_typed_facade_js_root_array_test() {
  let input = input()
  let seed = runtime_core.bootstrap_seed(input) |> expect.to_be_ok()
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
    connected("reader") |> json.to_string,
  )
  let root = watershed.resolve_root(document) |> expect.to_be_ok()
  let marker = watershed.get(root, "tree") |> expect.to_be_ok()
  let assert [view] = input.tree_views
  let tree =
    watershed.resolve_tree(document, marker, definition(view.view))
    |> expect.to_be_ok()
  watershed.tree_read_root(tree) |> expect.to_equal(Ok(Some(["A", "B"])))
  let root = watershed.tree_root(tree) |> expect.to_be_ok() |> expect.to_be_some
  let array = watershed.tree_as_array(root, text_codec()) |> expect.to_be_ok()
  watershed.tree_array_insert(array, 1, text_builder(), ["X"])
  |> expect.to_equal(Ok(Nil))
  watershed.tree_array_values(array)
  |> expect.to_equal(Ok(["A", "X", "B"]))
  watershed.close(document)
}

@target(javascript)
pub fn shared_tree_typed_facade_js_object_test() {
  let input = object_input()
  let seed = runtime_core.bootstrap_seed(input) |> expect.to_be_ok()
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
    connected("reader") |> json.to_string,
  )
  let root = watershed.resolve_root(document) |> expect.to_be_ok()
  let marker = watershed.get(root, "tree") |> expect.to_be_ok()
  let tree =
    watershed.resolve_tree(document, marker, typed_facade_fixture.definition())
    |> expect.to_be_ok()
  let node = watershed.tree_root(tree) |> expect.to_be_ok() |> expect.to_be_some
  watershed.tree_get(node, typed_facade_fixture.title())
  |> expect.to_equal(Ok("Title"))
  watershed.tree_get_optional(node, typed_facade_fixture.note())
  |> expect.to_equal(Ok(Some("Note")))
  watershed.tree_clear(node, typed_facade_fixture.note())
  |> expect.to_equal(Ok(Nil))
  watershed.tree_get_optional(node, typed_facade_fixture.note())
  |> expect.to_equal(Ok(None))
  watershed.tree_get_optional(node, typed_facade_fixture.maybe_null())
  |> expect.to_equal(Ok(Some(Nil)))
  watershed.tree_get(node, typed_facade_fixture.nothing())
  |> expect.to_equal(Ok(Nil))
  watershed.tree_get(node, typed_facade_fixture.handle_field())
  |> expect.to_be_ok()
  let child =
    watershed.tree_child(node, typed_facade_fixture.child())
    |> expect.to_be_ok()
    |> expect.to_be_some
  watershed.tree_read(child)
  |> expect.to_equal(Ok(typed_facade_fixture.ChildState("child", "Child")))
  watershed.tree_identifier(child, typed_facade_fixture.child_id())
  |> expect.to_be_ok()
  |> expect.to_not_equal("")
  watershed.tree_set(child, typed_facade_fixture.child_text(), "Changed")
  |> expect.to_equal(Ok(Nil))
  let array =
    watershed.tree_array(node, typed_facade_fixture.items())
    |> expect.to_be_ok()
  watershed.tree_array_values(array)
  |> expect.to_equal(
    Ok([
      typed_facade_fixture.ChildState("first", "First"),
      typed_facade_fixture.ChildState("second", "Second"),
    ]),
  )
  watershed.tree_array_insert(array, 2, typed_facade_fixture.child_builder(), [
    typed_facade_fixture.ChildInput(None, "Third"),
  ])
  |> expect.to_equal(Ok(Nil))
  let map =
    watershed.tree_map(node, typed_facade_fixture.entries())
    |> expect.to_be_ok()
  watershed.tree_map_get(map, "first")
  |> expect.to_equal(
    Ok(Some(typed_facade_fixture.ChildState("mapped", "Mapped"))),
  )
  watershed.tree_map_set(
    map,
    "second",
    typed_facade_fixture.child_builder(),
    typed_facade_fixture.ChildInput(None, "Other"),
  )
  |> expect.to_equal(Ok(Nil))
  let wrong_field: typed.Field(typed_facade_fixture.Root, Nil, typed.Required) =
    typed.required("title", typed.null())
  watershed.tree_get(node, wrong_field)
  |> expect.to_be_error()
  watershed.close(document)
}

@target(erlang)
pub fn shared_tree_typed_facade_beam_root_array_test() {
  let input = input()
  let seed = runtime_core.bootstrap_seed(input) |> expect.to_be_ok()
  let connections = process.new_subject()
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
  callbacks.on_event("connect_document_success", connected("reader"))
  runtime_beam.await_ready(watershed_beam.runtime_subject(document))
  |> expect.to_equal(Ok(Nil))
  let root = watershed_beam.resolve_root(document) |> expect.to_be_ok()
  let marker = watershed_beam.get(root, "tree") |> expect.to_be_ok()
  let assert [view] = input.tree_views
  let tree =
    watershed_beam.resolve_tree(document, marker, definition(view.view))
    |> expect.to_be_ok()
  watershed_beam.tree_read_root(tree)
  |> expect.to_equal(Ok(Some(["A", "B"])))
  let root =
    watershed_beam.tree_root(tree) |> expect.to_be_ok() |> expect.to_be_some
  let array =
    watershed_beam.tree_as_array(root, text_codec()) |> expect.to_be_ok()
  watershed_beam.tree_array_insert(array, 1, text_builder(), ["X"])
  |> expect.to_equal(Ok(Nil))
  watershed_beam.tree_array_values(array)
  |> expect.to_equal(Ok(["A", "X", "B"]))
  watershed_beam.close(document)
}

@target(erlang)
pub fn shared_tree_typed_facade_beam_object_test() {
  let input = object_input()
  let seed = runtime_core.bootstrap_seed(input) |> expect.to_be_ok()
  let connections = process.new_subject()
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
  callbacks.on_event("connect_document_success", connected("reader"))
  runtime_beam.await_ready(watershed_beam.runtime_subject(document))
  |> expect.to_equal(Ok(Nil))
  let root = watershed_beam.resolve_root(document) |> expect.to_be_ok()
  let marker = watershed_beam.get(root, "tree") |> expect.to_be_ok()
  let tree =
    watershed_beam.resolve_tree(
      document,
      marker,
      typed_facade_fixture.definition(),
    )
    |> expect.to_be_ok()
  let node =
    watershed_beam.tree_root(tree)
    |> expect.to_be_ok()
    |> expect.to_be_some
  watershed_beam.tree_get(node, typed_facade_fixture.title())
  |> expect.to_equal(Ok("Title"))
  watershed_beam.tree_get_optional(node, typed_facade_fixture.note())
  |> expect.to_equal(Ok(Some("Note")))
  watershed_beam.tree_clear(node, typed_facade_fixture.note())
  |> expect.to_equal(Ok(Nil))
  watershed_beam.tree_get_optional(node, typed_facade_fixture.note())
  |> expect.to_equal(Ok(None))
  watershed_beam.tree_get_optional(node, typed_facade_fixture.maybe_null())
  |> expect.to_equal(Ok(Some(Nil)))
  watershed_beam.tree_get(node, typed_facade_fixture.nothing())
  |> expect.to_equal(Ok(Nil))
  watershed_beam.tree_get(node, typed_facade_fixture.handle_field())
  |> expect.to_be_ok()
  let child =
    watershed_beam.tree_child(node, typed_facade_fixture.child())
    |> expect.to_be_ok()
    |> expect.to_be_some
  watershed_beam.tree_read(child)
  |> expect.to_equal(Ok(typed_facade_fixture.ChildState("child", "Child")))
  watershed_beam.tree_identifier(child, typed_facade_fixture.child_id())
  |> expect.to_be_ok()
  |> expect.to_not_equal("")
  watershed_beam.tree_set(child, typed_facade_fixture.child_text(), "Changed")
  |> expect.to_equal(Ok(Nil))
  let array =
    watershed_beam.tree_array(node, typed_facade_fixture.items())
    |> expect.to_be_ok()
  watershed_beam.tree_array_values(array)
  |> expect.to_equal(
    Ok([
      typed_facade_fixture.ChildState("first", "First"),
      typed_facade_fixture.ChildState("second", "Second"),
    ]),
  )
  watershed_beam.tree_array_insert(
    array,
    2,
    typed_facade_fixture.child_builder(),
    [typed_facade_fixture.ChildInput(None, "Third")],
  )
  |> expect.to_equal(Ok(Nil))
  let map =
    watershed_beam.tree_map(node, typed_facade_fixture.entries())
    |> expect.to_be_ok()
  watershed_beam.tree_map_get(map, "first")
  |> expect.to_equal(
    Ok(Some(typed_facade_fixture.ChildState("mapped", "Mapped"))),
  )
  watershed_beam.tree_map_set(
    map,
    "second",
    typed_facade_fixture.child_builder(),
    typed_facade_fixture.ChildInput(None, "Other"),
  )
  |> expect.to_equal(Ok(Nil))
  let wrong_field: typed.Field(typed_facade_fixture.Root, Nil, typed.Required) =
    typed.required("title", typed.null())
  watershed_beam.tree_get(node, wrong_field)
  |> expect.to_be_error()
  watershed_beam.close(document)
}
