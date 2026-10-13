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

const map_type = "org.watershed.shared-tree.m3.Map"

pub type Items

pub type Text

pub type Entries

fn input() -> runtime_core.BootstrapSeedInput {
  let raw =
    "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"org.watershed.shared-tree.m3.Items\":{\"kind\":{\"object\":{\"\":{\"kind\":\"Sequence\",\"types\":[\"com.fluidframework.leaf.string\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"org.watershed.shared-tree.m3.Items\"]}}"
  let stored = tree_schema.stored_from_string(raw) |> expect.to_be_ok()
  let view = tree_schema.view_from_string(raw) |> expect.to_be_ok()
  runtime_fixture.routed_tree_seed_input(
    stored,
    view,
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

fn leaf_definition() -> typed.Schema(Text, String) {
  let raw =
    "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}}},\"root\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}"
  let view = tree_schema.view_from_string(raw) |> expect.to_be_ok()
  typed.schema(view, text_codec()) |> expect.to_be_ok()
}

fn map_definition() -> typed.Schema(Entries, Nil) {
  let raw =
    "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"org.watershed.shared-tree.m3.Map\":{\"kind\":{\"map\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\"]}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"org.watershed.shared-tree.m3.Map\"]}}"
  let view = tree_schema.view_from_string(raw) |> expect.to_be_ok()
  let codec =
    typed.node(map_type, fn(value) {
      let assert types.MapValue(_, _) = value
      Ok(Nil)
    })
    |> expect.to_be_ok()
  typed.schema(view, codec) |> expect.to_be_ok()
}

fn map_builder() -> typed.Builder(Entries, List(#(String, String))) {
  typed.builder(map_type, fn(entries) {
    Ok(types.MapValue(
      map_type,
      list.map(entries, fn(entry: #(String, String)) {
        #(entry.0, types.StringValue(entry.1))
      }),
    ))
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
  let reference =
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
  let optional_child =
    watershed.tree_child(node, typed_facade_fixture.optional_child())
    |> expect.to_be_ok()
    |> expect.to_be_some
  watershed.tree_clear_child(node, typed_facade_fixture.optional_child())
  |> expect.to_equal(Ok(Nil))
  watershed.tree_read(optional_child) |> expect.to_be_error()
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
  let text_array =
    watershed.tree_array(node, typed_facade_fixture.items_text())
    |> expect.to_be_ok()
  watershed.tree_array_insert(
    text_array,
    3,
    typed_facade_fixture.child_builder(),
    [
      typed_facade_fixture.ChildInput(None, "Same"),
      typed_facade_fixture.ChildInput(None, "Same"),
    ],
  )
  |> expect.to_equal(Ok(Nil))
  let text_nodes = watershed.tree_array_nodes(text_array) |> expect.to_be_ok()
  let assert [same_one, same_two] = list.drop(text_nodes, 3)
  watershed.tree_read(same_one) |> expect.to_equal(Ok("Same"))
  watershed.tree_read(same_two) |> expect.to_equal(Ok("Same"))
  watershed.tree_array_move_before(
    text_array,
    same_two,
    text_array,
    Some(same_one),
  )
  |> expect.to_equal(Ok(Nil))
  watershed.tree_set(same_one, typed_facade_fixture.child_text(), "Moved")
  |> expect.to_equal(Ok(Nil))
  watershed.tree_array_values(text_array)
  |> expect.to_equal(Ok(["First", "Second", "Third", "Same", "Moved"]))
  let other =
    watershed.tree_array(node, typed_facade_fixture.other_items_text())
    |> expect.to_be_ok()
  watershed.tree_array_move_before(text_array, same_one, other, None)
  |> expect.to_equal(Ok(Nil))
  watershed.tree_array_values(other)
  |> expect.to_equal(Ok(["Moved"]))
  watershed.tree_array_remove_node(text_array, same_two)
  |> expect.to_equal(Ok(Nil))
  watershed.tree_read(same_two) |> expect.to_be_error()
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
  let mapped =
    watershed.tree_map_node(map, "first")
    |> expect.to_be_ok()
    |> expect.to_be_some
  watershed.tree_map_set(
    map,
    "first",
    typed_facade_fixture.child_builder(),
    typed_facade_fixture.ChildInput(None, "Replacement"),
  )
  |> expect.to_equal(Ok(Nil))
  watershed.tree_read(mapped) |> expect.to_be_error()
  let replacement =
    watershed.tree_map_node(map, "first")
    |> expect.to_be_ok()
    |> expect.to_be_some
  watershed.tree_map_delete(map, "first") |> expect.to_equal(Ok(Nil))
  watershed.tree_read(replacement) |> expect.to_be_error()
  let fork = watershed.tree_fork(tree) |> expect.to_be_ok()
  let fork_root =
    watershed.tree_root(fork) |> expect.to_be_ok() |> expect.to_be_some
  let fork_array =
    watershed.tree_array(fork_root, typed_facade_fixture.items())
    |> expect.to_be_ok()
  let fork_node =
    watershed.tree_array_nodes(fork_array)
    |> expect.to_be_ok()
    |> list.first()
    |> expect.to_be_ok()
  watershed.tree_array_remove_node(array, fork_node) |> expect.to_be_error()
  watershed.tree_dispose_branch(fork) |> expect.to_equal(Ok(Nil))
  let leaf_tree =
    watershed.create_tree(
      document,
      leaf_definition(),
      text_builder(),
      Some("leaf"),
    )
    |> expect.to_be_ok()
  watershed.tree_read_root(leaf_tree) |> expect.to_equal(Ok(Some("leaf")))
  watershed.tree_set_root(leaf_tree, text_builder(), "changed leaf")
  |> expect.to_equal(Ok(Nil))
  watershed.tree_clear_root(leaf_tree) |> expect.to_be_error()
  let map_tree =
    watershed.create_tree(
      document,
      map_definition(),
      map_builder(),
      Some([#("first", "value")]),
    )
    |> expect.to_be_ok()
  let map_root =
    watershed.tree_root(map_tree) |> expect.to_be_ok() |> expect.to_be_some
  let root_map =
    watershed.tree_as_map(map_root, text_codec()) |> expect.to_be_ok()
  watershed.tree_map_get(root_map, "first")
  |> expect.to_equal(Ok(Some("value")))
  watershed.tree_map_set(root_map, "second", text_builder(), "other")
  |> expect.to_equal(Ok(Nil))
  watershed.tree_map_delete(root_map, "first") |> expect.to_equal(Ok(Nil))
  let other_tree =
    watershed.create_tree(
      document,
      typed_facade_fixture.definition(),
      typed_facade_fixture.root_builder(),
      Some(
        typed_facade_fixture.RootInput(
          title: "Other channel",
          note: None,
          maybe_null: None,
          handle: reference,
          child: typed_facade_fixture.ChildInput(None, "Child"),
          optional_child: None,
          items: [typed_facade_fixture.ChildInput(None, "Foreign")],
          other_items: [],
          entries: [],
        ),
      ),
    )
    |> expect.to_be_ok()
  let other_root =
    watershed.tree_root(other_tree) |> expect.to_be_ok() |> expect.to_be_some
  let other_array =
    watershed.tree_array(other_root, typed_facade_fixture.items())
    |> expect.to_be_ok()
  let foreign_channel_node =
    watershed.tree_array_nodes(other_array)
    |> expect.to_be_ok()
    |> list.first()
    |> expect.to_be_ok()
  watershed.tree_array_remove_node(array, foreign_channel_node)
  |> expect.to_be_error()
  let foreign_callbacks = transport_js.new_cell(None)
  let foreign_document =
    watershed.connect_via_seed(
      tenant: "default",
      document: "foreign-tree",
      user_id: "foreign",
      seed: seed,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(foreign_callbacks, Some(handlers))
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
  let assert Some(foreign_callbacks) = transport_js.get_cell(foreign_callbacks)
  foreign_callbacks.on_event(
    "connect_document_success",
    connected("foreign") |> json.to_string,
  )
  let foreign_root =
    watershed.resolve_root(foreign_document) |> expect.to_be_ok()
  let foreign_marker = watershed.get(foreign_root, "tree") |> expect.to_be_ok()
  let foreign_tree =
    watershed.resolve_tree(
      foreign_document,
      foreign_marker,
      typed_facade_fixture.definition(),
    )
    |> expect.to_be_ok()
  let foreign_node =
    watershed.tree_root(foreign_tree)
    |> expect.to_be_ok()
    |> expect.to_be_some
  let foreign_array =
    watershed.tree_array(foreign_node, typed_facade_fixture.items())
    |> expect.to_be_ok()
  let foreign_runtime_node =
    watershed.tree_array_nodes(foreign_array)
    |> expect.to_be_ok()
    |> list.first()
    |> expect.to_be_ok()
  watershed.tree_array_remove_node(array, foreign_runtime_node)
  |> expect.to_be_error()
  watershed.tree_set_root(
    tree,
    typed_facade_fixture.root_builder(),
    typed_facade_fixture.RootInput(
      title: "Replacement root",
      note: None,
      maybe_null: None,
      handle: reference,
      child: typed_facade_fixture.ChildInput(None, "New child"),
      optional_child: None,
      items: [],
      other_items: [],
      entries: [],
    ),
  )
  |> expect.to_equal(Ok(Nil))
  watershed.tree_read(node) |> expect.to_be_error()
  watershed.tree_read(child) |> expect.to_be_error()
  watershed.tree_array_values(array) |> expect.to_be_error()
  watershed.tree_map_entries(map) |> expect.to_be_error()
  watershed.tree_clear_root(tree) |> expect.to_be_error()
  let wrong_field: typed.Field(typed_facade_fixture.Root, Nil, typed.Required) =
    typed.required("title", typed.null())
  watershed.tree_get(node, wrong_field)
  |> expect.to_be_error()
  let current =
    watershed.tree_root(tree) |> expect.to_be_ok() |> expect.to_be_some
  watershed.close(document)
  let assert Error(_) = watershed.tree_read(current)
  watershed.tree_read(foreign_node) |> expect.to_be_ok()
  watershed.close(foreign_document)
  Nil
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
  let reference =
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
  let optional_child =
    watershed_beam.tree_child(node, typed_facade_fixture.optional_child())
    |> expect.to_be_ok()
    |> expect.to_be_some
  watershed_beam.tree_clear_child(node, typed_facade_fixture.optional_child())
  |> expect.to_equal(Ok(Nil))
  watershed_beam.tree_read(optional_child) |> expect.to_be_error()
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
  let text_array =
    watershed_beam.tree_array(node, typed_facade_fixture.items_text())
    |> expect.to_be_ok()
  watershed_beam.tree_array_insert(
    text_array,
    3,
    typed_facade_fixture.child_builder(),
    [
      typed_facade_fixture.ChildInput(None, "Same"),
      typed_facade_fixture.ChildInput(None, "Same"),
    ],
  )
  |> expect.to_equal(Ok(Nil))
  let text_nodes =
    watershed_beam.tree_array_nodes(text_array) |> expect.to_be_ok()
  let assert [same_one, same_two] = list.drop(text_nodes, 3)
  watershed_beam.tree_read(same_one) |> expect.to_equal(Ok("Same"))
  watershed_beam.tree_read(same_two) |> expect.to_equal(Ok("Same"))
  watershed_beam.tree_array_move_before(
    text_array,
    same_two,
    text_array,
    Some(same_one),
  )
  |> expect.to_equal(Ok(Nil))
  watershed_beam.tree_set(same_one, typed_facade_fixture.child_text(), "Moved")
  |> expect.to_equal(Ok(Nil))
  watershed_beam.tree_array_values(text_array)
  |> expect.to_equal(Ok(["First", "Second", "Third", "Same", "Moved"]))
  let other =
    watershed_beam.tree_array(node, typed_facade_fixture.other_items_text())
    |> expect.to_be_ok()
  watershed_beam.tree_array_move_before(text_array, same_one, other, None)
  |> expect.to_equal(Ok(Nil))
  watershed_beam.tree_array_values(other)
  |> expect.to_equal(Ok(["Moved"]))
  watershed_beam.tree_array_remove_node(text_array, same_two)
  |> expect.to_equal(Ok(Nil))
  watershed_beam.tree_read(same_two) |> expect.to_be_error()
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
  let mapped =
    watershed_beam.tree_map_node(map, "first")
    |> expect.to_be_ok()
    |> expect.to_be_some
  watershed_beam.tree_map_set(
    map,
    "first",
    typed_facade_fixture.child_builder(),
    typed_facade_fixture.ChildInput(None, "Replacement"),
  )
  |> expect.to_equal(Ok(Nil))
  watershed_beam.tree_read(mapped) |> expect.to_be_error()
  let replacement =
    watershed_beam.tree_map_node(map, "first")
    |> expect.to_be_ok()
    |> expect.to_be_some
  watershed_beam.tree_map_delete(map, "first") |> expect.to_equal(Ok(Nil))
  watershed_beam.tree_read(replacement) |> expect.to_be_error()
  let fork = watershed_beam.tree_fork(tree) |> expect.to_be_ok()
  let fork_root =
    watershed_beam.tree_root(fork)
    |> expect.to_be_ok()
    |> expect.to_be_some
  let fork_array =
    watershed_beam.tree_array(fork_root, typed_facade_fixture.items())
    |> expect.to_be_ok()
  let fork_node =
    watershed_beam.tree_array_nodes(fork_array)
    |> expect.to_be_ok()
    |> list.first()
    |> expect.to_be_ok()
  watershed_beam.tree_array_remove_node(array, fork_node)
  |> expect.to_be_error()
  watershed_beam.tree_dispose_branch(fork) |> expect.to_equal(Ok(Nil))
  let leaf_tree =
    watershed_beam.create_tree(
      document,
      leaf_definition(),
      text_builder(),
      Some("leaf"),
    )
    |> expect.to_be_ok()
  watershed_beam.tree_read_root(leaf_tree)
  |> expect.to_equal(Ok(Some("leaf")))
  watershed_beam.tree_set_root(leaf_tree, text_builder(), "changed leaf")
  |> expect.to_equal(Ok(Nil))
  watershed_beam.tree_clear_root(leaf_tree) |> expect.to_be_error()
  let map_tree =
    watershed_beam.create_tree(
      document,
      map_definition(),
      map_builder(),
      Some([#("first", "value")]),
    )
    |> expect.to_be_ok()
  let map_root =
    watershed_beam.tree_root(map_tree)
    |> expect.to_be_ok()
    |> expect.to_be_some
  let root_map =
    watershed_beam.tree_as_map(map_root, text_codec()) |> expect.to_be_ok()
  watershed_beam.tree_map_get(root_map, "first")
  |> expect.to_equal(Ok(Some("value")))
  watershed_beam.tree_map_set(root_map, "second", text_builder(), "other")
  |> expect.to_equal(Ok(Nil))
  watershed_beam.tree_map_delete(root_map, "first")
  |> expect.to_equal(Ok(Nil))
  let other_tree =
    watershed_beam.create_tree(
      document,
      typed_facade_fixture.definition(),
      typed_facade_fixture.root_builder(),
      Some(
        typed_facade_fixture.RootInput(
          title: "Other channel",
          note: None,
          maybe_null: None,
          handle: reference,
          child: typed_facade_fixture.ChildInput(None, "Child"),
          optional_child: None,
          items: [typed_facade_fixture.ChildInput(None, "Foreign")],
          other_items: [],
          entries: [],
        ),
      ),
    )
    |> expect.to_be_ok()
  let other_root =
    watershed_beam.tree_root(other_tree)
    |> expect.to_be_ok()
    |> expect.to_be_some
  let other_array =
    watershed_beam.tree_array(other_root, typed_facade_fixture.items())
    |> expect.to_be_ok()
  let foreign_channel_node =
    watershed_beam.tree_array_nodes(other_array)
    |> expect.to_be_ok()
    |> list.first()
    |> expect.to_be_ok()
  watershed_beam.tree_array_remove_node(array, foreign_channel_node)
  |> expect.to_be_error()
  let foreign_connections = process.new_subject()
  let foreign_document =
    watershed_beam.connect_via_seed(
      tenant: "default",
      document: "foreign-tree",
      user_id: "foreign",
      seed: seed,
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(foreign_connections, callbacks)
      }),
    )
    |> expect.to_be_ok()
  let foreign_callbacks =
    process.receive(foreign_connections, 1000) |> expect.to_be_ok()
  foreign_callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  foreign_callbacks.on_event("connect_document_success", connected("foreign"))
  runtime_beam.await_ready(watershed_beam.runtime_subject(foreign_document))
  |> expect.to_equal(Ok(Nil))
  let foreign_root =
    watershed_beam.resolve_root(foreign_document) |> expect.to_be_ok()
  let foreign_marker =
    watershed_beam.get(foreign_root, "tree") |> expect.to_be_ok()
  let foreign_tree =
    watershed_beam.resolve_tree(
      foreign_document,
      foreign_marker,
      typed_facade_fixture.definition(),
    )
    |> expect.to_be_ok()
  let foreign_node =
    watershed_beam.tree_root(foreign_tree)
    |> expect.to_be_ok()
    |> expect.to_be_some
  let foreign_array =
    watershed_beam.tree_array(foreign_node, typed_facade_fixture.items())
    |> expect.to_be_ok()
  let foreign_runtime_node =
    watershed_beam.tree_array_nodes(foreign_array)
    |> expect.to_be_ok()
    |> list.first()
    |> expect.to_be_ok()
  watershed_beam.tree_array_remove_node(array, foreign_runtime_node)
  |> expect.to_be_error()
  watershed_beam.tree_set_root(
    tree,
    typed_facade_fixture.root_builder(),
    typed_facade_fixture.RootInput(
      title: "Replacement root",
      note: None,
      maybe_null: None,
      handle: reference,
      child: typed_facade_fixture.ChildInput(None, "New child"),
      optional_child: None,
      items: [],
      other_items: [],
      entries: [],
    ),
  )
  |> expect.to_equal(Ok(Nil))
  watershed_beam.tree_read(node) |> expect.to_be_error()
  watershed_beam.tree_read(child) |> expect.to_be_error()
  watershed_beam.tree_array_values(array) |> expect.to_be_error()
  watershed_beam.tree_map_entries(map) |> expect.to_be_error()
  watershed_beam.tree_clear_root(tree) |> expect.to_be_error()
  let wrong_field: typed.Field(typed_facade_fixture.Root, Nil, typed.Required) =
    typed.required("title", typed.null())
  watershed_beam.tree_get(node, wrong_field)
  |> expect.to_be_error()
  let current =
    watershed_beam.tree_root(tree)
    |> expect.to_be_ok()
    |> expect.to_be_some
  watershed_beam.close(document)
  let assert Error(_) = watershed_beam.tree_read(current)
  watershed_beam.tree_read(foreign_node) |> expect.to_be_ok()
  watershed_beam.close(foreign_document)
  Nil
}
