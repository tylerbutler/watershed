import gleam/dynamic/decode
@target(erlang)
import gleam/erlang/process
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import startest/expect
@target(javascript)
import watershed
import watershed/fluid_ids
@target(javascript)
import watershed/runtime
@target(erlang)
import watershed/runtime_beam
import watershed/runtime_core
import watershed/sluice/frame
@target(javascript)
import watershed/transport_js
import watershed/tree/runtime_fixture
import watershed/tree/types
import watershed/tree_kernel
@target(erlang)
import watershed_beam

const map_type = "org.watershed.shared-tree.m2.DynamicMap"

fn input(root_map: Bool) -> runtime_core.BootstrapSeedInput {
  let #(schema, root) = case root_map {
    True -> #("rootMap", types.MapValue(map_type, []))
    False -> #(
      "objectContainedMap",
      types.ObjectValue("org.watershed.shared-tree.m2.Root", [
        #("items", types.MapValue(map_type, [])),
      ]),
    )
  }
  runtime_fixture.routed_map_seed_input(schema, root) |> expect.to_be_ok()
}

fn connected(client: String, checkpoint: Int) -> json.Json {
  frame.encode_connected(
    client_id: client,
    tenant_id: "default",
    document_id: "tree",
    scopes: ["doc:read", "doc:write"],
    checkpoint_sequence_number: checkpoint,
    initial_clients: [client],
    initial_messages: [],
    timestamp: 0,
    presence_v1: False,
  )
}

fn rejected() -> json.Json {
  json.object([
    #("code", json.int(401)),
    #("message", json.string("authorization revoked")),
  ])
}

fn peer_input(
  input: runtime_core.BootstrapSeedInput,
) -> runtime_core.BootstrapSeedInput {
  let assert Some(compressor) = input.compressor
  let serialized = fluid_ids.serialize(compressor, False) |> expect.to_be_ok()
  let session =
    fluid_ids.session_id("50000000-0000-4000-8000-000000000005")
    |> expect.to_be_ok()
  let compressor =
    fluid_ids.deserialize(serialized, session) |> expect.to_be_ok()
  runtime_core.BootstrapSeedInput(..input, compressor: Some(compressor))
}

fn acknowledgement(payload: json.Json) -> json.Json {
  let assert Ok(dynamic) = json.parse(json.to_string(payload), decode.dynamic)
  let assert Ok(frame.SubmitOperation(sender, [[submitted]])) =
    frame.decode_submit_operation(dynamic)
  frame.encode_operation_event([
    frame.Sequenced(
      client_id: Some(sender),
      sequence_number: submitted.client_sequence_number,
      minimum_sequence_number: 0,
      client_sequence_number: submitted.client_sequence_number,
      reference_sequence_number: submitted.reference_sequence_number,
      operation_type: submitted.operation_type,
      contents: submitted.contents,
      metadata: submitted.metadata,
      timestamp: 0,
      data: None,
    ),
  ])
}

fn assert_map_operations(
  get: fn(List(String), String) -> Result(Option(types.TreeValue), String),
  set: fn(List(String), String, types.TreeValue) -> Result(Nil, String),
  delete: fn(List(String), String) -> Result(Nil, String),
  keys: fn(List(String)) -> Result(List(String), String),
  entries: fn(List(String)) -> Result(List(#(String, types.TreeValue)), String),
  set_field: fn(List(String), types.TreeValue) -> Result(Nil, String),
) -> Nil {
  keys(["items"]) |> expect.to_equal(Ok([]))
  entries(["items"]) |> expect.to_equal(Ok([]))
  get(["items"], "absent") |> expect.to_equal(Ok(None))
  let ordered = [
    "", "01", "10", "2", "__proto__", "\u{e9}", "\u{6c34}", "\u{fffd}",
    "\u{10000}",
  ]
  list.each(list.reverse(ordered), fn(key) {
    set(["items"], key, types.StringValue(key))
    |> expect.to_equal(Ok(Nil))
    get(["items"], key) |> expect.to_equal(Ok(Some(types.StringValue(key))))
  })
  keys(["items"]) |> expect.to_equal(Ok(ordered))
  entries(["items"])
  |> expect.to_equal(
    Ok(list.map(ordered, fn(key) { #(key, types.StringValue(key)) })),
  )
  set(["items"], "__proto__", types.StringValue("safe"))
  |> expect.to_equal(Ok(Nil))
  get(["items"], "__proto__")
  |> expect.to_equal(Ok(Some(types.StringValue("safe"))))
  delete(["items"], "__proto__") |> expect.to_equal(Ok(Nil))
  delete(["items"], "__proto__") |> expect.to_equal(Ok(Nil))
  get(["items"], "__proto__") |> expect.to_equal(Ok(None))
  let point =
    types.ObjectValue("org.watershed.shared-tree.m2.Point", [
      #("x", types.NumberValue(1.0)),
      #("y", types.NumberValue(2.0)),
    ])
  set(["items"], "point", point) |> expect.to_equal(Ok(Nil))
  set_field(["items", "point", "x"], types.NumberValue(3.0))
  |> expect.to_equal(Ok(Nil))
  get(["items"], "point")
  |> expect.to_equal(
    Ok(
      Some(
        types.ObjectValue("org.watershed.shared-tree.m2.Point", [
          #("x", types.NumberValue(3.0)),
          #("y", types.NumberValue(2.0)),
        ]),
      ),
    ),
  )
  set(["items"], "nested", types.MapValue(map_type, []))
  |> expect.to_equal(Ok(Nil))
  set(["items", "nested"], "a/b", types.NullValue)
  |> expect.to_equal(Ok(Nil))
  entries(["items", "nested"])
  |> expect.to_equal(Ok([#("a/b", types.NullValue)]))
  let before = entries(["items"])
  set(["items"], "invalid", types.ObjectValue("unknown", []))
  |> expect.to_be_error()
  set([], "invalid", types.StringValue("wrong target"))
  |> expect.to_be_error()
  delete(["items", "01"], "invalid") |> expect.to_be_error()
  get([], "items") |> expect.to_be_error()
  entries(["items", "missing"]) |> expect.to_be_error()
  keys([]) |> expect.to_be_error()
  entries(["items"]) |> expect.to_equal(before)
}

@target(javascript)
fn js_document(input: runtime_core.BootstrapSeedInput) {
  let seed = runtime_core.bootstrap_seed(input) |> expect.to_be_ok()
  let callbacks = transport_js.new_cell(None)
  let submissions = transport_js.new_cell([])
  let document =
    watershed.connect_via_seed(
      tenant: "default",
      document: "tree",
      user_id: "reader",
      seed: seed,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(event, payload) {
            case event {
              "submitOp" ->
                transport_js.set_cell(submissions, [
                  payload,
                  ..transport_js.get_cell(submissions)
                ])
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
  #(document, callbacks, submissions)
}

@target(javascript)
fn js_tree(
  document: watershed.Document(root),
  input: runtime_core.BootstrapSeedInput,
) -> watershed.SharedTree {
  let root = watershed.resolve_root(document) |> expect.to_be_ok()
  let marker = watershed.get(root, "tree") |> expect.to_be_ok()
  let assert [view] = input.tree_views
  watershed.resolve_tree(document, marker, view.view) |> expect.to_be_ok()
}

@target(javascript)
pub fn shared_tree_map_facade_js_operations_test() {
  let input = input(False)
  let #(document, callbacks, _) = js_document(input)
  callbacks.on_event(
    "connect_document_success",
    json.to_string(connected("reader", 0)),
  )
  let tree = js_tree(document, input)
  assert_map_operations(
    fn(path, key) { watershed.tree_map_get(tree, path, key) },
    fn(path, key, value) { watershed.tree_map_set(tree, path, key, value) },
    fn(path, key) { watershed.tree_map_delete(tree, path, key) },
    fn(path) { watershed.tree_map_keys(tree, path) },
    fn(path) { watershed.tree_map_entries(tree, path) },
    fn(path, value) { watershed.tree_set(tree, path, value) },
  )
  watershed.close(document)
}

@target(javascript)
pub fn shared_tree_map_facade_js_root_events_and_atomicity_test() {
  let input = input(True)
  let #(document, callbacks, submissions) = js_document(input)
  callbacks.on_event(
    "connect_document_success",
    json.to_string(connected("reader", 0)),
  )
  let tree = js_tree(document, input)
  let #(peer, peer_callbacks, _) = js_document(peer_input(input))
  peer_callbacks.on_event(
    "connect_document_success",
    json.to_string(connected("other", 0)),
  )
  let peer_tree = js_tree(peer, input)
  let remote_events = transport_js.new_cell([])
  let remote_subscription =
    watershed.subscribe_tree(peer_tree, fn(event) {
      transport_js.set_cell(remote_events, [
        event,
        ..transport_js.get_cell(remote_events)
      ])
    })
  let events = transport_js.new_cell([])
  let subscription =
    watershed.subscribe_tree(tree, fn(event) {
      transport_js.set_cell(events, [event, ..transport_js.get_cell(events)])
    })
  watershed.tree_map_set(tree, [], "", types.StringValue("value"))
  |> expect.to_equal(Ok(Nil))
  watershed.tree_map_keys(tree, []) |> expect.to_equal(Ok([""]))
  watershed.tree_map_entries(tree, [])
  |> expect.to_equal(Ok([#("", types.StringValue("value"))]))
  watershed.tree_map_get(tree, [], "")
  |> expect.to_equal(Ok(Some(types.StringValue("value"))))
  let assert [submitted] = transport_js.get_cell(submissions)
  peer_callbacks.on_event("op", json.to_string(acknowledgement(submitted)))
  peer_callbacks.on_event("op", json.to_string(acknowledgement(submitted)))
  watershed.tree_map_get(peer_tree, [], "")
  |> expect.to_equal(Ok(Some(types.StringValue("value"))))
  transport_js.get_cell(remote_events)
  |> expect.to_equal([tree_kernel.TreeChanged(False)])
  callbacks.on_event("op", json.to_string(acknowledgement(submitted)))
  callbacks.on_event("op", json.to_string(acknowledgement(submitted)))
  runtime.connection_observation(watershed.runtime_of(document)).pending_tree_count
  |> expect.to_equal(0)
  watershed.tree_map_delete(tree, [], "absent") |> expect.to_equal(Ok(Nil))
  watershed.tree_map_set(tree, [], "bad", types.ObjectValue("unknown", []))
  |> expect.to_be_error()
  watershed.tree_map_delete(tree, [""], "bad") |> expect.to_be_error()
  transport_js.get_cell(events)
  |> expect.to_equal([tree_kernel.TreeChanged(True)])
  transport_js.get_cell(submissions) |> list.length |> expect.to_equal(2)
  runtime.connection_observation(watershed.runtime_of(document)).pending_tree_count
  |> expect.to_equal(1)
  watershed.tree_map_entries(tree, [])
  |> expect.to_equal(Ok([#("", types.StringValue("value"))]))
  watershed.unsubscribe(subscription)
  watershed.unsubscribe(remote_subscription)
  watershed.close(peer)
  watershed.close(document)
}

@target(javascript)
pub fn shared_tree_map_facade_js_retained_reads_test() {
  let input = input(False)
  let #(document, callbacks, submissions) = js_document(input)
  let owner = watershed.runtime_of(document)
  runtime.tree_map_get(owner, "A/_C", ["items"], "key")
  |> expect.to_equal(Error("tree map read requires a ready document connection"))
  runtime.tree_map_entries(owner, "A/_C", ["items"])
  |> expect.to_equal(Error("tree map read requires a ready document connection"))
  callbacks.on_event(
    "connect_document_success",
    json.to_string(connected("reader", 0)),
  )
  let tree = js_tree(document, input)
  watershed.tree_map_set(tree, ["items"], "key", types.StringValue("retained"))
  |> expect.to_equal(Ok(Nil))
  callbacks.on_close()
  runtime.connection_observation(owner).phase |> expect.to_equal("reconnecting")
  watershed.tree_map_get(tree, ["items"], "key")
  |> expect.to_equal(Ok(Some(types.StringValue("retained"))))
  watershed.tree_map_delete(tree, ["items"], "key") |> expect.to_be_error()
  callbacks.on_join()
  callbacks.on_event(
    "connect_document_success",
    json.to_string(connected("rejoined", 1)),
  )
  runtime.connection_observation(owner).phase |> expect.to_equal("catching-up")
  watershed.tree_map_entries(tree, ["items"])
  |> expect.to_equal(Ok([#("key", types.StringValue("retained"))]))
  watershed.tree_map_set(tree, ["items"], "key", types.StringValue("lost"))
  |> expect.to_be_error()
  callbacks.on_close()
  callbacks.on_join()
  callbacks.on_event("connect_document_error", json.to_string(rejected()))
  runtime.connection_observation(owner).phase |> expect.to_equal("suspended")
  watershed.tree_map_keys(tree, ["items"]) |> expect.to_equal(Ok(["key"]))
  watershed.tree_map_get(tree, ["items"], "key")
  |> expect.to_equal(Ok(Some(types.StringValue("retained"))))
  watershed.tree_map_delete(tree, ["items"], "key")
  |> expect.to_equal(Error("authorization revoked"))
  transport_js.get_cell(submissions) |> list.length |> expect.to_equal(1)
  watershed.close(document)
}

@target(javascript)
pub fn shared_tree_map_facade_js_failed_reads_test() {
  let #(document, callbacks, _) = js_document(input(False))
  callbacks.on_event("connect_document_error", json.to_string(rejected()))
  let owner = watershed.runtime_of(document)
  runtime.connection_observation(owner).phase |> expect.to_equal("failed")
  runtime.tree_map_get(owner, "A/_C", ["items"], "key") |> expect.to_be_error()
  runtime.tree_map_entries(owner, "A/_C", ["items"]) |> expect.to_be_error()
  watershed.close(document)
}

@target(erlang)
fn beam_document(input: runtime_core.BootstrapSeedInput) {
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
  #(document, connections, submissions)
}

@target(erlang)
fn beam_transport(
  callbacks: runtime_beam.TransportCallbacks,
  submissions: process.Subject(json.Json),
) {
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, payload) {
        case event {
          "submitOp" -> process.send(submissions, payload)
          _ -> Nil
        }
        Ok(Nil)
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
}

@target(erlang)
fn beam_tree(
  document: watershed_beam.Document(root),
  input: runtime_core.BootstrapSeedInput,
) -> watershed_beam.SharedTree {
  runtime_beam.await_ready(watershed_beam.runtime_subject(document))
  |> expect.to_equal(Ok(Nil))
  let root = watershed_beam.resolve_root(document) |> expect.to_be_ok()
  let marker = watershed_beam.get(root, "tree") |> expect.to_be_ok()
  let assert [view] = input.tree_views
  watershed_beam.resolve_tree(document, marker, view.view) |> expect.to_be_ok()
}

@target(erlang)
pub fn shared_tree_map_facade_beam_operations_test() {
  let input = input(False)
  let #(document, connections, submissions) = beam_document(input)
  let callbacks = process.receive(connections, 1000) |> expect.to_be_ok()
  beam_transport(callbacks, submissions)
  callbacks.on_event("connect_document_success", connected("reader", 0))
  let tree = beam_tree(document, input)
  assert_map_operations(
    fn(path, key) { watershed_beam.tree_map_get(tree, path, key) },
    fn(path, key, value) { watershed_beam.tree_map_set(tree, path, key, value) },
    fn(path, key) { watershed_beam.tree_map_delete(tree, path, key) },
    fn(path) { watershed_beam.tree_map_keys(tree, path) },
    fn(path) { watershed_beam.tree_map_entries(tree, path) },
    fn(path, value) { watershed_beam.tree_set(tree, path, value) },
  )
  process.send(watershed_beam.runtime_subject(document), runtime_beam.Shutdown)
}

@target(erlang)
pub fn shared_tree_map_facade_beam_root_events_and_atomicity_test() {
  let input = input(True)
  let #(document, connections, submissions) = beam_document(input)
  let callbacks = process.receive(connections, 1000) |> expect.to_be_ok()
  beam_transport(callbacks, submissions)
  callbacks.on_event("connect_document_success", connected("reader", 0))
  let tree = beam_tree(document, input)
  let owner = watershed_beam.runtime_subject(document)
  let #(peer, peer_connections, peer_submissions) =
    beam_document(peer_input(input))
  let peer_callbacks =
    process.receive(peer_connections, 1000) |> expect.to_be_ok()
  beam_transport(peer_callbacks, peer_submissions)
  peer_callbacks.on_event("connect_document_success", connected("other", 0))
  let peer_tree = beam_tree(peer, input)
  let remote_events = watershed_beam.subscribe_tree(peer_tree)
  runtime_beam.resolve_root(watershed_beam.runtime_subject(peer))
  |> expect.to_be_ok()
  let events = watershed_beam.subscribe_tree(tree)
  runtime_beam.resolve_root(owner) |> expect.to_be_ok()
  watershed_beam.tree_map_set(tree, [], "", types.StringValue("value"))
  |> expect.to_equal(Ok(Nil))
  watershed_beam.tree_map_keys(tree, []) |> expect.to_equal(Ok([""]))
  watershed_beam.tree_map_entries(tree, [])
  |> expect.to_equal(Ok([#("", types.StringValue("value"))]))
  watershed_beam.tree_map_get(tree, [], "")
  |> expect.to_equal(Ok(Some(types.StringValue("value"))))
  let submitted = process.receive(submissions, 1000) |> expect.to_be_ok()
  peer_callbacks.on_event("op", acknowledgement(submitted))
  peer_callbacks.on_event("op", acknowledgement(submitted))
  watershed_beam.tree_map_get(peer_tree, [], "")
  |> expect.to_equal(Ok(Some(types.StringValue("value"))))
  process.receive(remote_events, 1000)
  |> expect.to_equal(Ok(tree_kernel.TreeChanged(False)))
  process.receive(remote_events, 0) |> expect.to_equal(Error(Nil))
  callbacks.on_event("op", acknowledgement(submitted))
  callbacks.on_event("op", acknowledgement(submitted))
  runtime_beam.connection_observation(owner).pending_tree_count
  |> expect.to_equal(0)
  watershed_beam.tree_map_delete(tree, [], "absent")
  |> expect.to_equal(Ok(Nil))
  watershed_beam.tree_map_set(tree, [], "bad", types.ObjectValue("unknown", []))
  |> expect.to_be_error()
  watershed_beam.tree_map_delete(tree, [""], "bad") |> expect.to_be_error()
  process.receive(events, 1000)
  |> expect.to_equal(Ok(tree_kernel.TreeChanged(True)))
  process.receive(events, 0) |> expect.to_equal(Error(Nil))
  process.receive(submissions, 1000) |> expect.to_be_ok()
  process.receive(submissions, 0) |> expect.to_equal(Error(Nil))
  runtime_beam.connection_observation(owner).pending_tree_count
  |> expect.to_equal(1)
  watershed_beam.tree_map_entries(tree, [])
  |> expect.to_equal(Ok([#("", types.StringValue("value"))]))
  process.send(owner, runtime_beam.Shutdown)
  process.send(watershed_beam.runtime_subject(peer), runtime_beam.Shutdown)
}

@target(erlang)
pub fn shared_tree_map_facade_beam_retained_reads_test() {
  let input = input(False)
  let #(document, connections, submissions) = beam_document(input)
  let owner = watershed_beam.runtime_subject(document)
  runtime_beam.tree_map_get(owner, "A/_C", ["items"], "key")
  |> expect.to_equal(Error("tree map read requires a ready document connection"))
  runtime_beam.tree_map_entries(owner, "A/_C", ["items"])
  |> expect.to_equal(Error("tree map read requires a ready document connection"))
  let callbacks = process.receive(connections, 1000) |> expect.to_be_ok()
  beam_transport(callbacks, submissions)
  callbacks.on_event("connect_document_success", connected("reader", 0))
  let tree = beam_tree(document, input)
  watershed_beam.tree_map_set(
    tree,
    ["items"],
    "key",
    types.StringValue("retained"),
  )
  |> expect.to_equal(Ok(Nil))
  callbacks.on_close("transport lost")
  let second = process.receive(connections, 1000) |> expect.to_be_ok()
  runtime_beam.connection_observation(owner).phase
  |> expect.to_equal("reconnecting")
  watershed_beam.tree_map_get(tree, ["items"], "key")
  |> expect.to_equal(Ok(Some(types.StringValue("retained"))))
  watershed_beam.tree_map_delete(tree, ["items"], "key") |> expect.to_be_error()
  beam_transport(second, submissions)
  second.on_event("connect_document_success", connected("rejoined", 1))
  runtime_beam.connection_observation(owner).phase
  |> expect.to_equal("catching-up")
  watershed_beam.tree_map_entries(tree, ["items"])
  |> expect.to_equal(Ok([#("key", types.StringValue("retained"))]))
  watershed_beam.tree_map_set(tree, ["items"], "key", types.StringValue("lost"))
  |> expect.to_be_error()
  second.on_close("transport lost")
  let third = process.receive(connections, 1000) |> expect.to_be_ok()
  beam_transport(third, submissions)
  third.on_event("connect_document_error", rejected())
  runtime_beam.connection_observation(owner).phase
  |> expect.to_equal("suspended")
  watershed_beam.tree_map_keys(tree, ["items"]) |> expect.to_equal(Ok(["key"]))
  watershed_beam.tree_map_get(tree, ["items"], "key")
  |> expect.to_equal(Ok(Some(types.StringValue("retained"))))
  watershed_beam.tree_map_delete(tree, ["items"], "key")
  |> expect.to_equal(Error("authorization revoked"))
  process.receive(submissions, 1000) |> expect.to_be_ok()
  process.receive(submissions, 0) |> expect.to_equal(Error(Nil))
  process.send(owner, runtime_beam.Shutdown)
}

@target(erlang)
pub fn shared_tree_map_facade_beam_failed_reads_test() {
  let #(document, connections, submissions) = beam_document(input(False))
  let callbacks = process.receive(connections, 1000) |> expect.to_be_ok()
  beam_transport(callbacks, submissions)
  callbacks.on_event("connect_document_error", rejected())
  let owner = watershed_beam.runtime_subject(document)
  runtime_beam.connection_observation(owner).phase |> expect.to_equal("failed")
  runtime_beam.tree_map_get(owner, "A/_C", ["items"], "key")
  |> expect.to_be_error()
  runtime_beam.tree_map_entries(owner, "A/_C", ["items"])
  |> expect.to_be_error()
  process.send(owner, runtime_beam.Shutdown)
}
