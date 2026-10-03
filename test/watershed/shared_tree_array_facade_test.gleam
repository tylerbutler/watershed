@target(erlang)
import gleam/erlang/process
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import startest/expect
@target(javascript)
import watershed
import watershed/channel
@target(javascript)
import watershed/runtime
@target(erlang)
import watershed/runtime_beam
import watershed/runtime_core
import watershed/sluice/frame
@target(javascript)
import watershed/transport_js
import watershed/tree/identifier_fixture
import watershed/tree/runtime_fixture
import watershed/tree/schema as tree_schema
import watershed/tree/types
import watershed/tree_kernel
@target(erlang)
import watershed_beam

const items_type = "org.watershed.shared-tree.m3.Items"

fn input() -> runtime_core.BootstrapSeedInput {
  runtime_fixture.routed_array_seed_input(
    "rootArray",
    types.ArrayValue(items_type, [
      types.StringValue("A"),
      types.StringValue("B"),
      types.StringValue("C"),
    ]),
  )
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

fn identifier_root() -> types.TreeValue {
  identifier_fixture.full_root(
    identifier_fixture.point("child", "child"),
    [],
    [],
    [],
  )
}

fn missing_identifier_point(label: String) -> types.TreeValue {
  types.ObjectValue(identifier_fixture.point_type, [
    #("label", types.StringValue(label)),
  ])
}

fn expect_generated_identifier(value: Option(types.TreeValue), label: String) {
  let assert Some(types.ObjectValue(_, fields)) = value
  list.key_find(fields, "label")
  |> expect.to_equal(Ok(types.StringValue(label)))
  let assert Ok(types.StringValue(identifier)) = list.key_find(fields, "id")
  identifier |> expect.to_not_equal("")
}

fn wider_view(
  input: runtime_core.BootstrapSeedInput,
) -> tree_schema.ViewSchema {
  let tree =
    input.channels
    |> list.find(fn(seed) {
      case seed.snapshot {
        channel.TreeSnapshot(_) -> True
        _ -> False
      }
    })
    |> expect.to_be_ok()
  let assert channel.TreeSnapshot(snapshot) = tree.snapshot
  let #(stored, _, _) = tree_kernel.snapshot_parts(snapshot)
  stored
  |> tree_schema.stored_to_json
  |> json.to_string
  |> string.replace(
    "},\"root\":",
    ",\"org.watershed.shared-tree.m3.Extra\":{\"kind\":{\"object\":{\"value\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}}}},\"root\":",
  )
  |> tree_schema.view_from_string
  |> expect.to_be_ok
}

fn assert_array_operations(
  get: fn(List(String), Int) -> Result(Option(types.TreeValue), String),
  values: fn(List(String)) -> Result(List(types.TreeValue), String),
  insert: fn(List(String), Int, List(types.TreeValue)) -> Result(Nil, String),
  remove: fn(List(String), Int, Int) -> Result(Nil, String),
  move: fn(List(String), Int, Int, List(String), Int) -> Result(Nil, String),
) -> Nil {
  values([])
  |> expect.to_equal(
    Ok([
      types.StringValue("A"),
      types.StringValue("B"),
      types.StringValue("C"),
    ]),
  )
  get([], 1) |> expect.to_equal(Ok(Some(types.StringValue("B"))))
  get([], 3) |> expect.to_equal(Ok(None))
  insert([], 1, [types.StringValue("X"), types.StringValue("Y")])
  |> expect.to_equal(Ok(Nil))
  move([], 1, 3, [], 5) |> expect.to_equal(Ok(Nil))
  remove([], 1, 2) |> expect.to_equal(Ok(Nil))
  values([])
  |> expect.to_equal(
    Ok([
      types.StringValue("A"),
      types.StringValue("C"),
      types.StringValue("X"),
      types.StringValue("Y"),
    ]),
  )
  get([], -1) |> expect.to_be_error()
  insert([], 5, []) |> expect.to_be_error()
  remove([], 3, 2) |> expect.to_be_error()
  Nil
}

@target(javascript)
pub fn shared_tree_array_facade_js_operations_test() {
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
    watershed.resolve_tree(document, marker, view.view) |> expect.to_be_ok()
  assert_array_operations(
    fn(path, index) { watershed.tree_array_get(tree, path, index) },
    fn(path) { watershed.tree_array_values(tree, path) },
    fn(path, index, values) {
      watershed.tree_array_insert(tree, path, index, values)
    },
    fn(path, start, end) { watershed.tree_array_remove(tree, path, start, end) },
    fn(source_path, source_start, source_end, destination_path, destination_gap) {
      watershed.tree_array_move(
        tree,
        source_path,
        source_start,
        source_end,
        destination_path,
        destination_gap,
      )
    },
  )
  watershed.close(document)
}

@target(javascript)
pub fn shared_tree_array_facade_js_generates_identifier_defaults_test() {
  let input = identifier_fixture.full_seed_input(identifier_root())
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
    watershed.resolve_tree(document, marker, view.view) |> expect.to_be_ok()
  watershed.tree_array_insert(tree, ["left"], 0, [
    missing_identifier_point("array"),
  ])
  |> expect.to_equal(Ok(Nil))
  watershed.tree_array_get(tree, ["left"], 0)
  |> expect.to_be_ok()
  |> expect_generated_identifier("array")
  watershed.close(document)
}

@target(javascript)
pub fn shared_tree_array_facade_js_transaction_test() {
  let input = input()
  let seed = runtime_core.bootstrap_seed(input) |> expect.to_be_ok()
  let callbacks = transport_js.new_cell(None)
  let submissions = transport_js.new_cell(0)
  let document =
    watershed.connect_via_seed(
      tenant: "default",
      document: "tree",
      user_id: "reader",
      seed: seed,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(event, _) {
            case event {
              "submitOp" ->
                transport_js.set_cell(
                  submissions,
                  transport_js.get_cell(submissions) + 1,
                )
              _ -> Nil
            }
          },
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
    watershed.resolve_tree(document, marker, view.view) |> expect.to_be_ok()

  watershed.tree_transaction(tree, [], fn(tree) {
    use _ <- result.try(
      watershed.tree_array_insert(tree, [], 1, [types.StringValue("X")]),
    )
    use _ <- result.try(watershed.tree_array_move(tree, [], 1, 2, [], 4))
    use _ <- result.try(watershed.tree_array_remove(tree, [], 1, 2))
    Ok("commit")
  })
  |> expect.to_equal(Ok("commit"))
  watershed.tree_array_values(tree, [])
  |> expect.to_equal(
    Ok([
      types.StringValue("A"),
      types.StringValue("C"),
      types.StringValue("X"),
    ]),
  )
  transport_js.get_cell(submissions) |> expect.to_equal(1)
  watershed.close(document)
}

@target(javascript)
pub fn shared_tree_array_facade_js_transaction_revertible_test() {
  let input = input()
  let seed = runtime_core.bootstrap_seed(input) |> expect.to_be_ok()
  let callbacks = transport_js.new_cell(None)
  let submissions = transport_js.new_cell(0)
  let document =
    watershed.connect_via_seed(
      tenant: "default",
      document: "tree",
      user_id: "reader",
      seed: seed,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(event, _) {
            case event {
              "submitOp" ->
                transport_js.set_cell(
                  submissions,
                  transport_js.get_cell(submissions) + 1,
                )
              _ -> Nil
            }
          },
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
    watershed.resolve_tree(document, marker, view.view) |> expect.to_be_ok()
  let handles = transport_js.new_cell([])
  let events = transport_js.new_cell(0)
  let token =
    watershed.subscribe_tree_commits(tree, fn(event) {
      let assert runtime.TreeCommitEvent(_, True, Some(get_revertible), _) =
        event
      let handle = get_revertible() |> expect.to_be_ok()
      transport_js.set_cell(handles, [handle, ..transport_js.get_cell(handles)])
      transport_js.set_cell(events, transport_js.get_cell(events) + 1)
    })

  watershed.tree_array_insert(tree, [], 3, [types.StringValue("D")])
  |> expect.to_equal(Ok(Nil))
  let assert [first] = transport_js.get_cell(handles)
  watershed.tree_transaction(tree, [], fn(tree) {
    watershed.tree_revert(first, False) |> expect.to_be_error()
    watershed.tree_array_values(tree, [])
    |> expect.to_equal(
      Ok([
        types.StringValue("A"),
        types.StringValue("B"),
        types.StringValue("C"),
        types.StringValue("D"),
      ]),
    )
    use _ <- result.try(
      watershed.tree_array_insert(tree, [], 1, [types.StringValue("X")]),
    )
    use _ <- result.try(watershed.tree_array_remove(tree, [], 2, 3))
    Ok(Nil)
  })
  |> expect.to_equal(Ok(Nil))
  transport_js.get_cell(events) |> expect.to_equal(2)
  let assert [outer, retained] = transport_js.get_cell(handles)
  watershed.tree_revertible_status(outer)
  |> expect.to_equal(watershed.RevertibleValid)
  watershed.tree_revertible_status(retained)
  |> expect.to_equal(watershed.RevertibleValid)
  transport_js.get_cell(submissions) |> expect.to_equal(2)
  watershed.tree_array_values(tree, [])
  |> expect.to_equal(
    Ok([
      types.StringValue("A"),
      types.StringValue("X"),
      types.StringValue("C"),
      types.StringValue("D"),
    ]),
  )
  watershed.tree_dispose_revertible(outer) |> expect.to_equal(Ok(Nil))
  watershed.tree_dispose_revertible(retained) |> expect.to_equal(Ok(Nil))
  watershed.unsubscribe(token)
  watershed.close(document)
}

@target(javascript)
pub fn shared_tree_array_facade_js_transaction_rejects_other_view_test() {
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
    watershed.resolve_tree(document, marker, view.view) |> expect.to_be_ok()
  let other =
    watershed.open_tree(document, marker, wider_view(input))
    |> expect.to_be_ok()

  watershed.tree_transaction(tree, [], fn(_) {
    watershed.tree_array_get(other, [], 0) |> expect.to_be_error()
    watershed.tree_array_values(other, []) |> expect.to_be_error()
    watershed.tree_array_insert(other, [], 1, [types.StringValue("wrong view")])
    |> expect.to_be_error()
    watershed.tree_array_remove(other, [], 0, 1) |> expect.to_be_error()
    watershed.tree_array_move(other, [], 0, 1, [], 3)
    |> expect.to_be_error()
    watershed.tree_array_values(tree, [])
    |> expect.to_equal(
      Ok([
        types.StringValue("A"),
        types.StringValue("B"),
        types.StringValue("C"),
      ]),
    )
    Ok(Nil)
  })
  |> expect.to_equal(Ok(Nil))
  watershed.tree_array_values(tree, [])
  |> expect.to_equal(
    Ok([
      types.StringValue("A"),
      types.StringValue("B"),
      types.StringValue("C"),
    ]),
  )
  watershed.close(document)
}

@target(erlang)
pub fn shared_tree_array_facade_beam_operations_test() {
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
    watershed_beam.resolve_tree(document, marker, view.view)
    |> expect.to_be_ok()
  assert_array_operations(
    fn(path, index) { watershed_beam.tree_array_get(tree, path, index) },
    fn(path) { watershed_beam.tree_array_values(tree, path) },
    fn(path, index, values) {
      watershed_beam.tree_array_insert(tree, path, index, values)
    },
    fn(path, start, end) {
      watershed_beam.tree_array_remove(tree, path, start, end)
    },
    fn(source_path, source_start, source_end, destination_path, destination_gap) {
      watershed_beam.tree_array_move(
        tree,
        source_path,
        source_start,
        source_end,
        destination_path,
        destination_gap,
      )
    },
  )
  process.send(watershed_beam.runtime_subject(document), runtime_beam.Shutdown)
}

@target(erlang)
pub fn shared_tree_array_facade_beam_generates_identifier_defaults_test() {
  let input = identifier_fixture.full_seed_input(identifier_root())
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
    watershed_beam.resolve_tree(document, marker, view.view)
    |> expect.to_be_ok()
  watershed_beam.tree_array_insert(tree, ["left"], 0, [
    missing_identifier_point("array"),
  ])
  |> expect.to_equal(Ok(Nil))
  watershed_beam.tree_array_get(tree, ["left"], 0)
  |> expect.to_be_ok()
  |> expect_generated_identifier("array")
  process.send(watershed_beam.runtime_subject(document), runtime_beam.Shutdown)
}

@target(erlang)
pub fn shared_tree_array_facade_beam_transaction_test() {
  let input = input()
  let seed = runtime_core.bootstrap_seed(input) |> expect.to_be_ok()
  let connections = process.new_subject()
  let submissions = process.new_subject()
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
      push: fn(event, _) {
        case event {
          "submitOp" -> process.send(submissions, Nil)
          _ -> Nil
        }
        Ok(Nil)
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  callbacks.on_event("connect_document_success", connected("reader"))
  let root = watershed_beam.resolve_root(document) |> expect.to_be_ok()
  let marker = watershed_beam.get(root, "tree") |> expect.to_be_ok()
  let assert [view] = input.tree_views
  let tree =
    watershed_beam.resolve_tree(document, marker, view.view)
    |> expect.to_be_ok()

  watershed_beam.tree_transaction(tree, [], fn(tree) {
    use _ <- result.try(
      watershed_beam.tree_array_insert(tree, [], 1, [types.StringValue("X")]),
    )
    use _ <- result.try(watershed_beam.tree_array_move(tree, [], 1, 2, [], 4))
    use _ <- result.try(watershed_beam.tree_array_remove(tree, [], 1, 2))
    Ok("commit")
  })
  |> expect.to_equal(Ok("commit"))
  watershed_beam.tree_array_values(tree, [])
  |> expect.to_equal(
    Ok([
      types.StringValue("A"),
      types.StringValue("C"),
      types.StringValue("X"),
    ]),
  )
  process.receive(submissions, 1000) |> expect.to_equal(Ok(Nil))
  process.receive(submissions, 0) |> expect.to_equal(Error(Nil))
  process.send(watershed_beam.runtime_subject(document), runtime_beam.Shutdown)
}

@target(erlang)
pub fn shared_tree_array_facade_beam_transaction_rejects_other_view_test() {
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
  let root = watershed_beam.resolve_root(document) |> expect.to_be_ok()
  let marker = watershed_beam.get(root, "tree") |> expect.to_be_ok()
  let assert [view] = input.tree_views
  let tree =
    watershed_beam.resolve_tree(document, marker, view.view)
    |> expect.to_be_ok()
  let other =
    watershed_beam.open_tree(document, marker, wider_view(input))
    |> expect.to_be_ok()

  watershed_beam.tree_transaction(tree, [], fn(_) {
    watershed_beam.tree_array_get(other, [], 0) |> expect.to_be_error()
    watershed_beam.tree_array_values(other, []) |> expect.to_be_error()
    watershed_beam.tree_array_insert(other, [], 1, [
      types.StringValue("wrong view"),
    ])
    |> expect.to_be_error()
    watershed_beam.tree_array_remove(other, [], 0, 1)
    |> expect.to_be_error()
    watershed_beam.tree_array_move(other, [], 0, 1, [], 3)
    |> expect.to_be_error()
    watershed_beam.tree_array_values(tree, [])
    |> expect.to_equal(
      Ok([
        types.StringValue("A"),
        types.StringValue("B"),
        types.StringValue("C"),
      ]),
    )
    Ok(Nil)
  })
  |> expect.to_equal(Ok(Nil))
  watershed_beam.tree_array_values(tree, [])
  |> expect.to_equal(
    Ok([
      types.StringValue("A"),
      types.StringValue("B"),
      types.StringValue("C"),
    ]),
  )
  process.send(watershed_beam.runtime_subject(document), runtime_beam.Shutdown)
}
