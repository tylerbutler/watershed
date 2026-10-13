import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import spillway/types
import startest/expect
import watershed/channel
import watershed/fluid_ids
import watershed/handle
import watershed/runtime_core
import watershed/tree/runtime_fixture
import watershed/tree/schema as tree_schema
import watershed/tree/types as tree_types
import watershed/wire
import watershed/wire/fluid_container
import watershed/wire/op as wire_op

pub fn tree_publication_consumes_prepared_attachments_test() {
  let writer =
    handle_tree_core_for("writer", "30000000-0000-4000-8000-000000000003")
  let receiver =
    handle_tree_core_for("receiver", "40000000-0000-4000-8000-000000000004")
  let assert Ok(#(writer, _, [bootstrap])) =
    runtime_core.set(writer, "A/root", "unrelated", json.string("kept"))
  let #(writer, receiver) = deliver(writer, receiver, bootstrap, 1)
  let assert Ok(writer) =
    runtime_core.create_detached(writer, "A/target", channel.InitMap)
  let assert Ok(#(writer, _, [])) =
    runtime_core.set(writer, "A/target", "private", json.string("accepted"))
  let target = reference("A/target")
  let assert Ok(#(writer, _, [publication])) =
    runtime_core.submit_tree_edits(writer, "A/_C", [
      tree_types.SetField([], tree_types.HandleValue(target)),
    ])
  let publication_messages = outbound_messages(publication)
  let assert [
    fluid_container.IdAllocation(_),
    fluid_container.ChannelAttach(
      fluid_container.Route("A", "target"),
      "https://graph.microsoft.com/types/map",
      _,
    ),
    fluid_container.ChannelOperation(fluid_container.Route("A", "_C"), _),
  ] = publication_messages
  writer.prepared_attachments |> expect.to_equal([])
  let #(writer, receiver) = deliver(writer, receiver, publication, 2)
  runtime_core.get(receiver, "A/target", "private")
  |> expect.to_equal(Ok(json.string("accepted")))
  runtime_core.tree_read(receiver, "A/_C", [])
  |> expect.to_equal(Ok(Some(tree_types.HandleValue(target))))

  let assert Ok(#(writer, _, [deletion])) =
    runtime_core.delete(writer, "A/root", "unrelated")
  let assert [
    fluid_container.ChannelOperation(fluid_container.Route("A", "root"), _),
  ] = outbound_messages(deletion)
  let #(_, receiver) = deliver(writer, receiver, deletion, 3)
  runtime_core.get(receiver, "A/root", "unrelated")
  |> expect.to_equal(Error(Nil))
  runtime_core.get(receiver, "A/target", "private")
  |> expect.to_equal(Ok(json.string("accepted")))
}

pub fn datastore_publication_excludes_unbound_siblings_test() {
  let writer = core_for("writer", "30000000-0000-4000-8000-000000000003")
  let receiver = core_for("receiver", "40000000-0000-4000-8000-000000000004")
  let assert Ok(writer) = runtime_core.create_detached_data_store(writer, "D")
  let assert Ok(writer) =
    runtime_core.create_detached(writer, "D/direct", channel.InitMap)
  let assert Ok(writer) =
    runtime_core.create_detached(writer, "D/bound", channel.InitMap)
  let assert Ok(writer) =
    runtime_core.create_detached(writer, "D/private", channel.InitMap)
  let assert Ok(#(writer, _, [])) =
    runtime_core.set(writer, "D/direct", "visible", json.string("direct"))
  let assert Ok(#(writer, _, [])) =
    runtime_core.set(writer, "D/bound", "visible", json.string("retained"))
  let assert Ok(#(writer, _, [])) =
    runtime_core.set(writer, "D/private", "private", json.string("detached"))
  let assert Ok(#(writer, _, [])) =
    runtime_core.set(
      writer,
      "D/root",
      "retained",
      handle.encode_handle("D/bound"),
    )
  let writer =
    runtime_core.capture_bindings(writer, "D/root") |> expect.to_be_ok()
  let assert Ok(#(writer, _, [])) =
    runtime_core.delete(writer, "D/root", "retained")
  let #(writer, active_view, active_view_id) =
    create_handle_tree(writer, "D/active", None)
  let assert Ok(writer) =
    runtime_core.begin_tree_transaction(writer, "D/active", active_view, [])

  let #(writer, _, publications) =
    runtime_core.set(
      writer,
      "A/root",
      "direct",
      handle.encode_handle("D/direct"),
    )
    |> expect.to_be_ok()
  list.length(publications) |> expect.to_equal(1)
  let publication = list.first(publications) |> expect.to_be_ok()
  let messages = outbound_messages(publication)
  let attaches =
    list.filter_map(messages, fn(message) {
      case message {
        fluid_container.DatastoreAttach("D", contents) -> Ok(contents)
        _ -> Error(Nil)
      }
    })
  list.length(attaches) |> expect.to_equal(1)
  let contents = list.first(attaches) |> expect.to_be_ok()
  let assert Some(compressor) = writer.compressor
  let #(_, snapshots) =
    wire_op.decode_datastore_attach_with_context(
      contents,
      compressor,
      active_view_id,
      "/D",
      1,
      0,
    )
    |> expect.to_be_ok()
  snapshots
  |> list.map(fn(snapshot) { snapshot.0 })
  |> list.sort(string.compare)
  |> expect.to_equal(["bound", "direct", "root"])
  ["D/root", "D/direct", "D/bound"]
  |> list.each(fn(address) {
    dict.has_key(writer.channels, address) |> expect.to_be_true()
    dict.has_key(writer.detached, address) |> expect.to_be_false()
  })
  ["D/private", "D/active"]
  |> list.each(fn(address) {
    dict.has_key(writer.channels, address) |> expect.to_be_false()
    dict.has_key(writer.detached, address) |> expect.to_be_true()
  })

  let #(receiver, _) =
    runtime_core.handle_sequenced(
      receiver,
      sequenced(publication, writer.client_id, 3),
    )
    |> expect.to_be_ok()
  runtime_core.get(receiver, "D/direct", "visible")
  |> expect.to_equal(Ok(json.string("direct")))
  runtime_core.get(receiver, "D/bound", "visible")
  |> expect.to_equal(Ok(json.string("retained")))
  runtime_core.has_channel(receiver, "D/private") |> expect.to_be_false()
  runtime_core.has_channel(receiver, "D/active") |> expect.to_be_false()
}

pub fn datastore_publication_refuses_reached_active_tree_test() {
  let core = core_for("writer", "30000000-0000-4000-8000-000000000003")
  let assert Ok(core) = runtime_core.create_detached_data_store(core, "D")
  let assert Ok(core) = runtime_core.create_detached_data_store(core, "E")
  let assert Ok(core) =
    runtime_core.create_detached(core, "D/private", channel.InitMap)
  let assert Ok(#(core, _, [])) =
    runtime_core.set(core, "D/private", "private", json.string("detached"))
  let #(core, view, _) = create_handle_tree(core, "D/active", None)
  let assert Ok(#(core, _, [])) =
    runtime_core.set(core, "D/root", "next", handle.encode_handle("E/root"))
  let core = runtime_core.capture_bindings(core, "D/root") |> expect.to_be_ok()
  let assert Ok(#(core, _, [])) = runtime_core.delete(core, "D/root", "next")
  let assert Ok(#(core, _, [])) =
    runtime_core.set(core, "E/root", "return", handle.encode_handle("D/active"))
  let core = runtime_core.capture_bindings(core, "E/root") |> expect.to_be_ok()
  let assert Ok(#(core, _, [])) = runtime_core.delete(core, "E/root", "return")
  let assert Ok(core) =
    runtime_core.begin_tree_transaction(core, "D/active", view, [])
  let before = core
  runtime_core.set(core, "A/root", "store", handle.encode_handle("D/root"))
  |> expect.to_be_error()
  core |> expect.to_equal(before)
  dict.has_key(core.detached, "D/root") |> expect.to_be_true()
  dict.has_key(core.detached, "D/active") |> expect.to_be_true()
}

pub fn datastore_publication_includes_later_direct_reference_test() {
  let writer = core_for("writer", "30000000-0000-4000-8000-000000000003")
  let receiver = core_for("receiver", "40000000-0000-4000-8000-000000000004")
  let assert Ok(writer) = runtime_core.create_detached_data_store(writer, "D")
  let assert Ok(writer) =
    runtime_core.create_detached(writer, "D/child", channel.InitMap)
  let assert Ok(writer) =
    runtime_core.create_detached(writer, "D/private", channel.InitMap)
  let assert Ok(#(writer, _, [])) =
    runtime_core.set(writer, "D/child", "value", json.string("child"))
  let assert Ok(#(writer, _, [])) =
    runtime_core.set(writer, "D/private", "private", json.string("detached"))
  let #(writer, _, view_id) = create_handle_tree(writer, "D/active", None)

  let pair =
    json.array(
      [handle.encode_handle("D/root"), handle.encode_handle("D/child")],
      fn(value) { value },
    )
  handle.collect_routed_addresses(pair, "/A")
  |> expect.to_equal(Ok(["D/root", "D/child"]))
  let #(writer, _, publications) =
    runtime_core.set(writer, "A/root", "pair", pair)
    |> expect.to_be_ok()
  let publication = list.first(publications) |> expect.to_be_ok()
  let assert [
    fluid_container.IdAllocation(_),
    fluid_container.DatastoreAttach("D", contents),
    fluid_container.ChannelOperation(fluid_container.Route("A", "root"), _),
  ] = outbound_messages(publication)
  datastore_snapshot_ids(writer, contents, view_id, "/D")
  |> expect.to_equal(["child", "root"])
  ["D/root", "D/child"]
  |> list.each(fn(address) {
    dict.has_key(writer.channels, address) |> expect.to_be_true()
    dict.has_key(writer.detached, address) |> expect.to_be_false()
  })
  ["D/private", "D/active"]
  |> list.each(fn(address) {
    dict.has_key(writer.channels, address) |> expect.to_be_false()
    dict.has_key(writer.detached, address) |> expect.to_be_true()
  })
  let #(receiver, _) =
    runtime_core.handle_sequenced(
      receiver,
      sequenced(publication, writer.client_id, 3),
    )
    |> expect.to_be_ok()
  ["D/root", "D/child"]
  |> list.filter(fn(address) { runtime_core.has_channel(receiver, address) })
  |> expect.to_equal(["D/root", "D/child"])
  runtime_core.resolve_handle_address(receiver, handle.encode_handle("D/root"))
  |> expect.to_equal(Ok("D/root"))
  runtime_core.resolve_handle_address(receiver, handle.encode_handle("D/child"))
  |> expect.to_equal(Ok("D/child"))
  runtime_core.get(receiver, "D/child", "value")
  |> expect.to_equal(Ok(json.string("child")))

  let reverse_writer =
    core_for("reverse-writer", "50000000-0000-4000-8000-000000000005")
  let reverse_receiver =
    core_for("reverse-receiver", "60000000-0000-4000-8000-000000000006")
  let assert Ok(reverse_writer) =
    runtime_core.create_detached_data_store(reverse_writer, "F")
  let assert Ok(reverse_writer) =
    runtime_core.create_detached(reverse_writer, "F/child", channel.InitMap)
  let assert Ok(reverse_writer) =
    runtime_core.create_detached(reverse_writer, "F/private", channel.InitMap)
  let assert Ok(#(reverse_writer, _, [])) =
    runtime_core.set(reverse_writer, "F/child", "value", json.string("reverse"))
  let #(reverse_writer, _, reverse_view_id) =
    create_handle_tree(reverse_writer, "F/active", None)
  let reverse_pair =
    json.array(
      [handle.encode_handle("F/child"), handle.encode_handle("F/root")],
      fn(value) { value },
    )
  handle.collect_routed_addresses(reverse_pair, "/A")
  |> expect.to_equal(Ok(["F/child", "F/root"]))
  let #(reverse_writer, _, reverse_publications) =
    runtime_core.set(reverse_writer, "A/root", "reverse", reverse_pair)
    |> expect.to_be_ok()
  let reverse = list.first(reverse_publications) |> expect.to_be_ok()
  let assert [
    fluid_container.IdAllocation(_),
    fluid_container.DatastoreAttach("F", reverse_contents),
    fluid_container.ChannelOperation(fluid_container.Route("A", "root"), _),
  ] = outbound_messages(reverse)
  datastore_snapshot_ids(
    reverse_writer,
    reverse_contents,
    reverse_view_id,
    "/F",
  )
  |> expect.to_equal(["child", "root"])
  let #(reverse_receiver, _) =
    runtime_core.handle_sequenced(
      reverse_receiver,
      sequenced(reverse, reverse_writer.client_id, 3),
    )
    |> expect.to_be_ok()
  runtime_core.resolve_handle_address(
    reverse_receiver,
    handle.encode_handle("F/root"),
  )
  |> expect.to_equal(Ok("F/root"))
  runtime_core.resolve_handle_address(
    reverse_receiver,
    handle.encode_handle("F/child"),
  )
  |> expect.to_equal(Ok("F/child"))
  runtime_core.has_channel(reverse_receiver, "F/private")
  |> expect.to_be_false()
}

pub fn datastore_publication_includes_cross_store_return_edge_test() {
  let writer = core_for("writer", "30000000-0000-4000-8000-000000000003")
  let receiver = core_for("receiver", "40000000-0000-4000-8000-000000000004")
  let assert Ok(writer) = runtime_core.create_detached_data_store(writer, "D")
  let assert Ok(writer) = runtime_core.create_detached_data_store(writer, "E")
  let assert Ok(writer) =
    runtime_core.create_detached(writer, "D/child", channel.InitMap)
  let assert Ok(writer) =
    runtime_core.create_detached(writer, "D/private", channel.InitMap)
  let assert Ok(#(writer, _, [])) =
    runtime_core.set(writer, "D/child", "value", json.string("returned"))
  let assert Ok(#(writer, _, [])) =
    runtime_core.set(writer, "D/private", "private", json.string("detached"))
  let assert Ok(#(writer, _, [])) =
    runtime_core.set(writer, "D/root", "next", handle.encode_handle("E/root"))
  let writer =
    runtime_core.capture_bindings(writer, "D/root") |> expect.to_be_ok()
  let assert Ok(#(writer, _, [])) =
    runtime_core.delete(writer, "D/root", "next")
  let assert Ok(#(writer, _, [])) =
    runtime_core.set(
      writer,
      "E/root",
      "return",
      handle.encode_handle("D/child"),
    )
  let writer =
    runtime_core.capture_bindings(writer, "E/root") |> expect.to_be_ok()
  let assert Ok(#(writer, _, [])) =
    runtime_core.delete(writer, "E/root", "return")
  let #(writer, _, view_id) = create_handle_tree(writer, "D/active", None)

  let #(writer, _, publications) =
    runtime_core.set(writer, "A/root", "store", handle.encode_handle("D/root"))
    |> expect.to_be_ok()
  let publication = list.first(publications) |> expect.to_be_ok()
  let assert [
    fluid_container.IdAllocation(_),
    fluid_container.DatastoreAttach("E", e_contents),
    fluid_container.DatastoreAttach("D", d_contents),
    fluid_container.ChannelOperation(fluid_container.Route("A", "root"), _),
  ] = outbound_messages(publication)
  datastore_snapshot_ids(writer, e_contents, view_id, "/E")
  |> expect.to_equal(["root"])
  datastore_snapshot_ids(writer, d_contents, view_id, "/D")
  |> expect.to_equal(["child", "root"])
  ["D/root", "D/child", "E/root"]
  |> list.each(fn(address) {
    dict.has_key(writer.channels, address) |> expect.to_be_true()
    dict.has_key(writer.detached, address) |> expect.to_be_false()
  })
  ["D/private", "D/active"]
  |> list.each(fn(address) {
    dict.has_key(writer.channels, address) |> expect.to_be_false()
    dict.has_key(writer.detached, address) |> expect.to_be_true()
  })

  let #(receiver, _) =
    runtime_core.handle_sequenced(
      receiver,
      sequenced(publication, writer.client_id, 3),
    )
    |> expect.to_be_ok()
  ["D/root", "D/child", "E/root"]
  |> list.filter(fn(address) { runtime_core.has_channel(receiver, address) })
  |> expect.to_equal(["D/root", "D/child", "E/root"])
  runtime_core.resolve_handle_address(receiver, handle.encode_handle("D/root"))
  |> expect.to_equal(Ok("D/root"))
  runtime_core.resolve_handle_address(receiver, handle.encode_handle("E/root"))
  |> expect.to_equal(Ok("E/root"))
  runtime_core.resolve_handle_address(receiver, handle.encode_handle("D/child"))
  |> expect.to_equal(Ok("D/child"))
  runtime_core.get(receiver, "D/child", "value")
  |> expect.to_equal(Ok(json.string("returned")))
  runtime_core.has_channel(receiver, "D/private") |> expect.to_be_false()
  runtime_core.has_channel(receiver, "D/active") |> expect.to_be_false()
}

pub fn tree_operations_bind_relative_handles_to_source_datastore_test() {
  let writer =
    handle_tree_core_for("writer", "30000000-0000-4000-8000-000000000003")
  let receiver =
    handle_tree_core_for("receiver", "40000000-0000-4000-8000-000000000004")
  let writer = clone_tree_channel(writer, "A/_C", "B/parent")
  let receiver = clone_tree_channel(receiver, "A/_C", "B/parent")
  let writer = clone_datastore_root(writer, "A", "B")
  let receiver = clone_datastore_root(receiver, "A", "B")
  let writer =
    runtime_core.create_detached(writer, "A/target", channel.InitMap)
    |> expect.to_be_ok()
  let #(writer, _, a_local) =
    runtime_core.set(writer, "A/target", "source", json.string("A"))
    |> expect.to_be_ok()
  a_local |> expect.to_equal([])
  let #(writer, _, a_target_publications) =
    runtime_core.set(
      writer,
      "A/root",
      "target",
      handle.encode_handle("A/target"),
    )
    |> expect.to_be_ok()
  list.length(a_target_publications) |> expect.to_equal(2)
  let a_target_attach = list.first(a_target_publications) |> expect.to_be_ok()
  let a_target_reference =
    list.drop(a_target_publications, 1) |> list.first |> expect.to_be_ok()
  let #(writer, receiver) = deliver(writer, receiver, a_target_attach, 1)
  let #(writer, receiver) = deliver(writer, receiver, a_target_reference, 2)

  let writer =
    runtime_core.create_detached(writer, "B/target", channel.InitMap)
    |> expect.to_be_ok()
  let #(writer, _, b_local) =
    runtime_core.set(writer, "B/target", "source", json.string("B"))
    |> expect.to_be_ok()
  b_local |> expect.to_equal([])
  let #(writer, _, b_target_attaches) =
    runtime_core.set(
      writer,
      "B/root",
      "target",
      handle.encode_handle("B/target"),
    )
    |> expect.to_be_ok()
  list.length(b_target_attaches) |> expect.to_equal(2)
  let b_target_attach = list.first(b_target_attaches) |> expect.to_be_ok()
  let b_target_reference =
    list.drop(b_target_attaches, 1) |> list.first |> expect.to_be_ok()
  let #(writer, receiver) = deliver(writer, receiver, b_target_attach, 3)
  let #(writer, receiver) = deliver(writer, receiver, b_target_reference, 4)

  let writer =
    runtime_core.Core(..writer, in_flight: [], prepared_attachments: [])
  let #(writer, _, a_absolutes) =
    runtime_core.submit_tree_edits(writer, "A/_C", [
      tree_types.SetField([], tree_types.HandleValue(reference("A/target"))),
    ])
    |> expect.to_be_ok()
  list.length(a_absolutes) |> expect.to_equal(1)
  let a_absolute = list.first(a_absolutes) |> expect.to_be_ok()
  let a_relative = relative_marker(a_absolute, "/A/target")
  runtime_core.handle_sequenced(
    writer,
    sequenced(a_relative, writer.client_id, 5),
  )
  |> expect.to_be_error()
  let #(writer, _, b_absolutes) =
    runtime_core.submit_tree_edits(writer, "B/parent", [
      tree_types.SetField([], tree_types.HandleValue(reference("B/target"))),
    ])
    |> expect.to_be_ok()
  list.length(b_absolutes) |> expect.to_equal(1)
  let b_absolute = list.first(b_absolutes) |> expect.to_be_ok()
  let b_relative = relative_marker(b_absolute, "/B/target")

  let #(absolute_receiver, _) =
    runtime_core.handle_sequenced(
      receiver,
      sequenced(a_absolute, writer.client_id, 5),
    )
    |> expect.to_be_ok()
  tree_handle_path(absolute_receiver, "A/_C") |> expect.to_equal("/A/target")
  runtime_core.get(absolute_receiver, "A/target", "source")
  |> expect.to_equal(Ok(json.string("A")))

  let #(receiver, _) =
    runtime_core.handle_sequenced(
      receiver,
      sequenced(a_relative, writer.client_id, 5),
    )
    |> expect.to_be_ok()
  let #(receiver, _) =
    runtime_core.handle_sequenced(
      receiver,
      sequenced(b_relative, writer.client_id, 6),
    )
    |> expect.to_be_ok()
  tree_handle_path(receiver, "A/_C") |> expect.to_equal("/A/target")
  tree_handle_path(receiver, "B/parent") |> expect.to_equal("/B/target")
  runtime_core.get(receiver, "A/target", "source")
  |> expect.to_equal(Ok(json.string("A")))
  runtime_core.get(receiver, "B/target", "source")
  |> expect.to_equal(Ok(json.string("B")))
}

fn create_handle_tree(
  core: runtime_core.Core,
  address: String,
  initial: Option(tree_types.TreeValue),
) -> #(runtime_core.Core, tree_schema.ViewSchema, fluid_ids.StableId) {
  let #(stored, view) = handle_tree_schema()
  let assert Some(compressor) = core.compressor
  let assert Ok(#(compressor, generated)) = fluid_ids.generate(compressor)
  let assert Ok(view_id) = fluid_ids.decompress(compressor, generated)
  let core = runtime_core.Core(..core, compressor: Some(compressor))
  let core =
    runtime_core.create_detached_tree(core, address, stored, initial, view_id)
    |> expect.to_be_ok()
  #(core, view, view_id)
}

fn handle_tree_core_for(
  client_id: String,
  session_id: String,
) -> runtime_core.Core {
  let #(stored, view) = handle_tree_schema()
  let input =
    runtime_fixture.routed_tree_seed_input(
      stored,
      view,
      tree_types.HandleValue(reference("A/root")),
    )
    |> expect.to_be_ok()
  let session = fluid_ids.session_id(session_id) |> expect.to_be_ok()
  let assert Some(compressor) = input.compressor
  let serialized = fluid_ids.serialize(compressor, False) |> expect.to_be_ok()
  let compressor =
    fluid_ids.deserialize(serialized, session) |> expect.to_be_ok()
  let seed =
    runtime_core.bootstrap_seed(
      runtime_core.BootstrapSeedInput(..input, compressor: Some(compressor)),
    )
    |> expect.to_be_ok()
  let assert runtime_core.Complete(core) =
    runtime_core.bootstrap_seeded(
      runtime_fixture.connected(client_id, [], 0),
      seed,
    )
    |> expect.to_be_ok()
  core
}

fn handle_tree_schema() -> #(tree_schema.StoredSchema, tree_schema.ViewSchema) {
  let schema =
    "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.handle\":{\"kind\":{\"leaf\":3}}},\"root\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.handle\"]}}"
  #(
    tree_schema.stored_from_string(schema) |> expect.to_be_ok(),
    tree_schema.view_from_string(schema) |> expect.to_be_ok(),
  )
}

fn core_for(client_id: String, session_id: String) -> runtime_core.Core {
  runtime_fixture.routed_core_for(client_id, session_id) |> expect.to_be_ok()
}

fn reference(address: String) -> handle.Reference {
  handle.reference_from_path("/" <> address) |> expect.to_be_ok()
}

fn clone_tree_channel(
  core: runtime_core.Core,
  source: String,
  target: String,
) -> runtime_core.Core {
  let state = dict.get(core.channels, source) |> expect.to_be_ok()
  let checkout = dict.get(core.tree_checkouts, source) |> expect.to_be_ok()
  let attributes =
    dict.get(core.routing.channel_attributes, source) |> expect.to_be_ok()
  runtime_core.Core(
    ..core,
    channels: dict.insert(core.channels, target, state),
    channel_order: list.append(core.channel_order, [target]),
    tree_checkouts: dict.insert(core.tree_checkouts, target, checkout),
    routing: runtime_core.Routing(
      ..core.routing,
      channel_attributes: dict.insert(
        core.routing.channel_attributes,
        target,
        attributes,
      ),
    ),
  )
}

fn clone_datastore_root(
  core: runtime_core.Core,
  source: String,
  target: String,
) -> runtime_core.Core {
  let source_address = source <> "/root"
  let target_address = target <> "/root"
  let package = dict.get(core.routing.datastores, source) |> expect.to_be_ok()
  let state = dict.get(core.channels, source_address) |> expect.to_be_ok()
  let attributes =
    dict.get(core.routing.channel_attributes, source_address)
    |> expect.to_be_ok()
  runtime_core.Core(
    ..core,
    channels: dict.insert(core.channels, target_address, state),
    channel_order: list.append(core.channel_order, [target_address]),
    routing: runtime_core.Routing(
      ..core.routing,
      datastores: dict.insert(core.routing.datastores, target, package),
      channel_attributes: dict.insert(
        core.routing.channel_attributes,
        target_address,
        attributes,
      ),
    ),
  )
}

fn outbound_messages(
  outbound: wire.OutboundOperation,
) -> List(fluid_container.MessageKind) {
  let batch =
    fluid_container.decode(outbound.contents, outbound.metadata)
    |> expect.to_be_ok()
  list.map(batch.messages, fn(message) { message.kind })
}

fn datastore_snapshot_ids(
  core: runtime_core.Core,
  contents: json.Json,
  view_id: fluid_ids.StableId,
  context: String,
) -> List(String) {
  let assert Some(compressor) = core.compressor
  let #(_, snapshots) =
    wire_op.decode_datastore_attach_with_context(
      contents,
      compressor,
      view_id,
      context,
      1,
      0,
    )
    |> expect.to_be_ok()
  snapshots
  |> list.map(fn(snapshot) { snapshot.0 })
  |> list.sort(string.compare)
}

fn deliver(
  writer: runtime_core.Core,
  receiver: runtime_core.Core,
  outbound: wire.OutboundOperation,
  sequence_number: Int,
) -> #(runtime_core.Core, runtime_core.Core) {
  let message = sequenced(outbound, writer.client_id, sequence_number)
  let writer = case runtime_core.handle_sequenced(writer, message) {
    Ok(#(writer, _)) -> writer
    Error(error) ->
      panic as {
        "writer sequence "
        <> int.to_string(sequence_number)
        <> ": "
        <> string.inspect(error)
      }
  }
  let receiver = case runtime_core.handle_sequenced(receiver, message) {
    Ok(#(receiver, _)) -> receiver
    Error(error) ->
      panic as {
        "receiver sequence "
        <> int.to_string(sequence_number)
        <> ": "
        <> string.inspect(error)
      }
  }
  #(writer, receiver)
}

fn sequenced(
  outbound: wire.OutboundOperation,
  client_id: String,
  sequence_number: Int,
) -> types.SequencedDocumentMessage {
  let assert Ok(contents) =
    json.parse(json.to_string(outbound.contents), decode.dynamic)
  let metadata = case outbound.metadata {
    None -> None
    Some(value) -> {
      let assert Ok(value) = json.parse(json.to_string(value), decode.dynamic)
      Some(value)
    }
  }
  types.SequencedDocumentMessage(
    client_id: Some(client_id),
    sequence_number: sequence_number,
    minimum_sequence_number: 0,
    client_sequence_number: outbound.client_sequence_number,
    reference_sequence_number: outbound.reference_sequence_number,
    message_type: outbound.operation_type,
    contents: contents,
    metadata: metadata,
    server_metadata: None,
    origin: None,
    traces: None,
    timestamp: 1_700_000_000_000,
    data: None,
  )
}

fn relative_marker(
  outbound: wire.OutboundOperation,
  absolute: String,
) -> wire.OutboundOperation {
  let encoded =
    json.to_string(outbound.contents)
    |> string.replace("\"url\":\"" <> absolute <> "\"", "\"url\":\"target\"")
  let contents =
    json.parse(encoded, wire.json_value_decoder()) |> expect.to_be_ok()
  wire.OutboundOperation(..outbound, contents:)
}

fn tree_handle_path(core: runtime_core.Core, address: String) -> String {
  let assert Ok(Some(tree_types.HandleValue(reference))) =
    runtime_core.tree_read(core, address, [])
  handle.reference_path(reference)
}
