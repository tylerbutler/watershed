import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import spillway/types
import startest/expect
import watershed/channel
import watershed/fluid_ids
import watershed/handle
import watershed/map_kernel
import watershed/runtime_core
import watershed/tree/fixtures
import watershed/tree/runtime as tree_runtime
import watershed/tree/runtime_fixture
import watershed/tree/schema as tree_schema
import watershed/tree/types as tree_types
import watershed/tree_kernel
import watershed/wire
import watershed/wire/fluid_container
import watershed/wire/op as wire_op
import watershed/wire/socket

const peer_session = "30000000-0000-4000-8000-000000000003"

pub fn shared_tree_runtime_route_identity_test() -> Nil {
  fluid_container.route_key(fluid_container.Route("A", "root"))
  |> expect.to_equal(Ok("A/root"))
  fluid_container.route_key(fluid_container.Route("B", "root"))
  |> expect.to_equal(Ok("B/root"))
  let route = fluid_container.Route("A/B", "root+value%")
  fluid_container.route_key(route)
  |> expect.to_equal(Ok("A%2FB/root%2Bvalue%25"))
  fluid_container.route_from_path("/A%2fB/root%2Bvalue%25")
  |> expect.to_equal(Ok(route))
}

pub fn shared_tree_runtime_route_refuses_invalid_paths_test() -> Nil {
  list.each(
    ["root", "/root", "/A/root/child", "/A/..", "/A/%2f", "/A/%", "//A/root"],
    fn(path) { fluid_container.route_from_path(path) |> expect.to_be_error() },
  )
  fluid_container.route_key(fluid_container.Route("", "root"))
  |> expect.to_be_error()
  Nil
}

fn map_seed(datastore: String) -> runtime_core.ChannelSeed {
  runtime_core.ChannelSeed(
    fluid_container.Route(datastore, "root"),
    json.object([
      #("type", json.string(channel.fluid_type_to_string(channel.MapChannel))),
      #("snapshotFormatVersion", json.string("0.2")),
      #("packageVersion", json.string("3.1.0")),
    ]),
    channel.MapSnapshot([]),
  )
}

fn seed_input() -> runtime_core.BootstrapSeedInput {
  runtime_core.BootstrapSeedInput(
    profile: runtime_core.RoutedSeed,
    sequence_number: 0,
    minimum_sequence_number: 0,
    members: [],
    datastores: [
      runtime_core.DatastoreSeed("A", ["test"]),
      runtime_core.DatastoreSeed("B", ["test"]),
    ],
    aliases: [#("root", "A")],
    channels: [map_seed("A"), map_seed("B")],
    bootstrap_map: fluid_container.Route("A", "root"),
    compressor: None,
    tree_views: [],
  )
}

fn core_from(input: runtime_core.BootstrapSeedInput) -> runtime_core.Core {
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap_seeded(
      runtime_fixture.connected("reader", [], 0),
      seed,
    )
  core
}

fn batch_message(
  kinds: List(fluid_container.MessageKind),
) -> types.SequencedDocumentMessage {
  let assert Ok(encoded) =
    fluid_container.encode_batch(fluid_container.DecodedBatch(
      True,
      None,
      list.index_map(kinds, fn(kind, index) {
        fluid_container.ContainerMessage(kind, index, None)
      }),
    ))
  let assert Ok(contents) = json.parse(json.to_string(encoded), decode.dynamic)
  types.SequencedDocumentMessage(
    client_id: option.Some("writer"),
    sequence_number: 1,
    minimum_sequence_number: 0,
    client_sequence_number: 1,
    reference_sequence_number: 0,
    message_type: "op",
    contents: contents,
    metadata: None,
    server_metadata: None,
    origin: None,
    traces: None,
    timestamp: 0,
    data: None,
  )
}

fn captured_container_message(id: String) -> fluid_container.MessageKind {
  let assert Ok(fixture) = fixtures.load("container-foundations")
  let assert Ok(cases) =
    json.parse(
      json.to_string(fixture.input),
      decode.at(
        ["decodeCases"],
        decode.list({
          use id <- decode.field("id", decode.string)
          use contents <- decode.field("contents", wire.json_value_decoder())
          decode.success(#(id, contents))
        }),
      ),
    )
  let assert Ok(contents) = list.key_find(cases, id)
  let assert Ok(batch) = fluid_container.decode(contents, None)
  let assert [message] = batch.messages
  message.kind
}

pub fn shared_tree_runtime_datastore_attach_registers_channels_atomically_test() -> Nil {
  let input = seed_input()
  let core =
    core_from(
      runtime_core.BootstrapSeedInput(
        ..input,
        datastores: [runtime_core.DatastoreSeed("A", ["test"])],
        channels: [map_seed("A")],
      ),
    )
  let message =
    batch_message([
      captured_container_message("datastore-attach"),
      captured_container_message("datastore-alias"),
      fluid_container.ChannelOperation(
        fluid_container.Route("B", "root"),
        wire_op.encode_map_operation(map_kernel.Set("name", json.string("B"))),
      ),
    ])
  let assert Ok(#(next, ingested)) =
    runtime_core.handle_sequenced(core, message)
  next.last_seen_sequence_number |> expect.to_equal(1)
  runtime_core.get(next, "B/root", "name")
  |> expect.to_equal(Ok(json.string("B")))
  runtime_core.get(next, "A/root", "name") |> expect.to_equal(Error(Nil))
  runtime_core.resolve_handle_address(
    next,
    handle.encode_handle("secondary/root"),
  )
  |> expect.to_equal(Ok("B/root"))
  runtime_core.root_channel_address(next) |> expect.to_equal(Ok("A/root"))
  list.map(ingested.events, fn(entry) { entry.0 })
  |> expect.to_equal(["B/root"])
  dict.get(next.routing.datastores, "B")
  |> expect.to_equal(Ok(["org.watershed.shared-tree.m1.bootstrap"]))
  dict.has_key(next.routing.channel_attributes, "B/root") |> expect.to_be_true()
  runtime_core.handle_sequenced(
    next,
    types.SequencedDocumentMessage(..message, sequence_number: 2),
  )
  |> expect.to_be_error()
  Nil
}

pub fn shared_tree_runtime_bad_last_child_does_not_publish_prefix_test() -> Nil {
  let core = core_from(seed_input())
  let write =
    fluid_container.ChannelOperation(
      fluid_container.Route("A", "root"),
      wire_op.encode_map_operation(map_kernel.Set("name", json.string("A"))),
    )
  let bad =
    fluid_container.ChannelOperation(
      fluid_container.Route("missing", "root"),
      wire_op.encode_map_operation(map_kernel.Clear),
    )
  runtime_core.handle_sequenced(core, batch_message([write, bad]))
  |> expect.to_be_error()
  core.last_seen_sequence_number |> expect.to_equal(0)
  runtime_core.get(core, "A/root", "name") |> expect.to_equal(Error(Nil))
  let assert Ok(#(next, _)) =
    runtime_core.handle_sequenced(core, batch_message([write]))
  runtime_core.get(next, "A/root", "name")
  |> expect.to_equal(Ok(json.string("A")))
}

pub fn shared_tree_runtime_refuses_attach_to_unknown_datastore_test() -> Nil {
  let core = core_from(seed_input())
  let assert Ok(encoded) =
    wire_op.encode_attach("missing/child", channel.MapSnapshot([]))
  let assert Ok(batch) = fluid_container.decode(encoded, None)
  runtime_core.handle_sequenced(
    core,
    batch_message(list.map(batch.messages, fn(message) { message.kind })),
  )
  |> expect.to_be_error()
  Nil
}

pub fn shared_tree_runtime_alias_cannot_hide_datastore_identity_test() -> Nil {
  let input = seed_input()
  runtime_core.bootstrap_seed(
    runtime_core.BootstrapSeedInput(..input, aliases: [#("A", "B")]),
  )
  |> expect.to_be_error()
  let core = core_from(input)
  runtime_core.handle_sequenced(
    core,
    batch_message([fluid_container.DatastoreAlias("B", "A")]),
  )
  |> expect.to_be_error()
  runtime_core.resolve_handle_address(core, handle.encode_handle("A/root"))
  |> expect.to_equal(Ok("A/root"))
  Nil
}

pub fn shared_tree_runtime_alias_dependencies_attach_actual_route_test() -> Nil {
  let core = core_from(seed_input())
  let assert Ok(core) =
    runtime_core.create_detached(core, "A/child", channel.InitMap)
  dict.has_key(core.routing.channel_attributes, "A/child")
  |> expect.to_be_true()
  let assert Ok(#(next, _, [attach, _])) =
    runtime_core.set(
      core,
      "A/root",
      "child",
      handle.encode_handle("root/child"),
    )
  let assert Ok(batch) = fluid_container.decode(attach.contents, None)
  let assert [
    fluid_container.ContainerMessage(
      fluid_container.ChannelAttach(fluid_container.Route("A", "child"), _, _),
      _,
      _,
    ),
  ] = batch.messages
  dict.has_key(next.channels, "A/child") |> expect.to_be_true()
  dict.has_key(next.detached, "A/child") |> expect.to_be_false()
}

pub fn shared_tree_runtime_rejects_malformed_group_boundary_test() {
  let first =
    json.object([
      #("batch", json.bool(True)),
      #("batchId", json.string("group")),
    ])
  let assert Ok(contents) =
    fluid_container.encode_batch(
      fluid_container.DecodedBatch(
        True,
        Some(
          json.object([
            #("batchId", json.string("group")),
            #("groupedOpCount", json.int(2)),
          ]),
        ),
        [
          fluid_container.ContainerMessage(
            fluid_container.DatastoreAlias("A", "alias1"),
            0,
            Some(first),
          ),
          fluid_container.ContainerMessage(
            fluid_container.DatastoreAlias("A", "alias2"),
            1,
            None,
          ),
        ],
      ),
    )
  let assert Ok(batch) =
    fluid_container.decode(
      contents,
      Some(
        json.object([
          #("batchId", json.string("group")),
          #("groupedOpCount", json.int(2)),
        ]),
      ),
    )
  fluid_container.validate_profile_batch(batch)
  |> expect.to_equal(
    Error(fluid_container.MalformedMessage(
      "groupedBatch",
      "missing final batch marker",
    )),
  )
}

pub fn shared_tree_runtime_rejects_unfinished_outer_boundary_test() {
  let assert Ok(contents) =
    fluid_container.encode(fluid_container.DatastoreAlias("A", "alias"))
  let assert Ok(batch) =
    fluid_container.decode(
      contents,
      Some(json.object([#("batch", json.bool(True))])),
    )
  fluid_container.validate_profile_batch(batch)
  |> expect.to_equal(
    Error(fluid_container.MalformedMessage(
      "batch",
      "ungrouped batch boundary is not supported",
    )),
  )
}

pub fn shared_tree_runtime_relative_handle_cannot_cross_datastores_test() -> Nil {
  let core = core_from(seed_input())
  let assert Ok(core) =
    runtime_core.create_detached(core, "A/child", channel.InitMap)
  let assert Ok(core) =
    runtime_core.create_detached(core, "B/child", channel.InitMap)
  let relative =
    json.object([
      #("type", json.string("__fluid_handle__")),
      #("url", json.string("child")),
    ])
  let assert Ok(#(core, _, _)) =
    runtime_core.set(core, "B/root", "child", relative)
  let assert Ok(value) = runtime_core.get(core, "B/root", "child")
  case runtime_core.resolve_handle_address(core, value) {
    Ok(address) -> address |> expect.to_equal("B/child")
    Error(_) -> Nil
  }
  let assert Ok(bound) =
    runtime_core.bind_handle(core, handle.encode_handle("B/root"), value)
  runtime_core.resolve_handle_address(core, bound)
  |> expect.to_equal(Ok("B/child"))
  runtime_core.bind_handle(core, handle.encode_handle("missing/root"), value)
  |> expect.to_be_error()
  Nil
}

pub fn shared_tree_runtime_native_seed_requires_native_root_test() -> Nil {
  runtime_core.bootstrap_seed(
    runtime_core.BootstrapSeedInput(
      ..seed_input(),
      profile: runtime_core.NativeMapSeed,
    ),
  )
  |> expect.to_be_error()
  Nil
}

pub fn shared_tree_runtime_seed_checks_registry_test() -> Nil {
  let input = seed_input()
  runtime_core.bootstrap_seed(input) |> expect.to_be_ok()
  list.each(
    [
      runtime_core.BootstrapSeedInput(..input, channels: [map_seed("B")]),
      runtime_core.BootstrapSeedInput(..input, channels: [
        map_seed("A"),
        map_seed("A"),
      ]),
      runtime_core.BootstrapSeedInput(..input, aliases: [
        #("root", "A"),
        #("root", "B"),
      ]),
      runtime_core.BootstrapSeedInput(..input, aliases: [#("root", "missing")]),
      runtime_core.BootstrapSeedInput(..input, aliases: [#("..", "A")]),
      runtime_core.BootstrapSeedInput(..input, datastores: [
        runtime_core.DatastoreSeed("..", ["test"]),
        ..input.datastores
      ]),
      runtime_core.BootstrapSeedInput(..input, minimum_sequence_number: 1),
      runtime_core.BootstrapSeedInput(..input, channels: [
        runtime_core.ChannelSeed(
          ..map_seed("A"),
          snapshot: channel.CounterSnapshot(0),
        ),
      ]),
    ],
    fn(invalid) { runtime_core.bootstrap_seed(invalid) |> expect.to_be_error() },
  )
}

pub fn shared_tree_runtime_seed_rejects_missing_channel_versions_test() -> Nil {
  let input = seed_input()
  let invalid =
    runtime_core.ChannelSeed(
      ..map_seed("A"),
      attributes: json.object([
        #("type", json.string(channel.fluid_type_to_string(channel.MapChannel))),
      ]),
    )
  runtime_core.bootstrap_seed(
    runtime_core.BootstrapSeedInput(..input, channels: [
      invalid,
      map_seed("B"),
    ]),
  )
  |> expect.to_be_error()
  Nil
}

pub fn shared_tree_runtime_map_header_reads_plain_values_test() -> Nil {
  let header =
    json.object([
      #("blobs", json.preprocessed_array([])),
      #(
        "content",
        json.object([
          #(
            "tree",
            json.object([
              #("type", json.string("Plain")),
              #("value", json.string("value")),
            ]),
          ),
        ]),
      ),
    ])
  wire_op.decode_map_header(header)
  |> expect.to_equal(Ok([#("tree", json.string("value"))]))
  wire_op.decode_map_header(json.object([])) |> expect.to_be_error()
  Nil
}

pub fn shared_tree_runtime_map_attach_keeps_insertion_order_test() -> Nil {
  let snapshot =
    channel.MapSnapshot([
      #("z", json.int(1)),
      #("10", json.int(10)),
      #("2", json.int(2)),
      #("a:quoted\"", json.object([#("nested", json.string("comma,colon:"))])),
      #("a", json.int(2)),
      #("\u{0301}:,", json.string("\\\",:{}[]")),
    ])
  let assert Ok(encoded) = wire_op.encode_attach("A/child", snapshot)
  let assert Ok(contents) = json.parse(json.to_string(encoded), decode.dynamic)
  let assert Ok(wire_op.AttachOperation("A/child", decoded)) =
    wire_op.decode_operation_contents(contents)
  channel.same_snapshot(snapshot, decoded) |> expect.to_be_true()
}

pub fn shared_tree_runtime_map_header_uses_javascript_property_order_test() -> Nil {
  let assert Ok(entries) =
    wire_op.decode_map_header_string(
      "{\"blobs\":[],\"content\":{\"z\":{\"type\":\"Plain\",\"value\":0},\"10\":{\"type\":\"Plain\",\"value\":10},\"2\":{\"type\":\"Plain\",\"value\":2},\"01\":{\"type\":\"Plain\",\"value\":1},\"4294967295\":{\"type\":\"Plain\",\"value\":3}}}",
    )
  list.map(entries, fn(entry) { entry.0 })
  |> expect.to_equal(["2", "10", "z", "01", "4294967295"])
}

pub fn shared_tree_runtime_map_header_refuses_duplicate_members_test() -> Nil {
  list.each(
    [
      "{\"blobs\":[],\"content\":{\"a\":{\"type\":\"Plain\",\"value\":0},\"a\":{\"type\":\"Plain\",\"value\":1}}}",
      "{\"blobs\":[],\"content\":{},\"content\":{}}",
    ],
    fn(raw) { wire_op.decode_map_header_string(raw) |> expect.to_be_error() },
  )
}

pub fn shared_tree_runtime_socket_refuses_outer_compression_test() -> Nil {
  json.parse(
    "{\"clientId\":\"writer\",\"sequenceNumber\":1,\"minimumSequenceNumber\":0,\"clientSequenceNumber\":1,\"referenceSequenceNumber\":0,\"type\":\"op\",\"contents\":{},\"timestamp\":0,\"compression\":\"lz4\"}",
    socket.sequenced_document_message_decoder(),
  )
  |> expect.to_be_error()
  Nil
}

pub fn shared_tree_runtime_seed_refuses_unknown_native_channel_version_test() -> Nil {
  let input = seed_input()
  let counter =
    runtime_core.ChannelSeed(
      fluid_container.Route("B", "counter"),
      json.object([
        #("type", json.string("org.watershed/counter")),
        #("snapshotFormatVersion", json.string("99")),
        #("packageVersion", json.string("1")),
      ]),
      channel.CounterSnapshot(0),
    )
  runtime_core.bootstrap_seed(
    runtime_core.BootstrapSeedInput(..input, channels: [map_seed("A"), counter]),
  )
  |> expect.to_be_error()
  Nil
}

pub fn shared_tree_runtime_map_type_matches_upstream_test() -> Nil {
  channel.fluid_type_to_string(channel.MapChannel)
  |> expect.to_equal("https://graph.microsoft.com/types/map")
  channel.fluid_string_to_type("https://graph.microsoft.com/types/map")
  |> expect.to_equal(Ok(channel.MapChannel))
  channel.fluid_type_to_string(channel.CounterChannel)
  |> expect.to_equal("org.watershed/counter")
  channel.fluid_string_to_type("org.watershed/counter")
  |> expect.to_equal(Ok(channel.CounterChannel))
  channel.fluid_string_to_type("org.watershed/map") |> expect.to_be_error()
  channel.fluid_string_to_type("map") |> expect.to_be_error()
  channel.type_to_string(channel.MapChannel) |> expect.to_equal("map")
  Nil
}

pub fn shared_tree_runtime_writes_keep_datastore_routes_test() -> Nil {
  let assert Ok(seed) = runtime_core.bootstrap_seed(seed_input())
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap_seeded(
      runtime_fixture.connected("peer", [], 0),
      seed,
    )
  let assert Ok(#(next, _, [outbound])) =
    runtime_core.set(core, "B/root", "name", json.string("B"))
  let assert Ok(batch) =
    fluid_container.decode(outbound.contents, outbound.metadata)
  let assert [
    fluid_container.ContainerMessage(
      fluid_container.ChannelOperation(fluid_container.Route("B", "root"), _),
      0,
      _,
    ),
  ] = batch.messages
  runtime_core.has_channel(next, "A/root") |> expect.to_be_true()
  runtime_core.has_channel(next, "B/root") |> expect.to_be_true()
  fluid_container.decode(
    json.object([
      #("address", json.string("B/root")),
      #("contents", json.object([#("type", json.string("clear"))])),
    ]),
    None,
  )
  |> expect.to_be_error()
  Nil
}

pub fn shared_tree_runtime_seed_preserves_routes_without_phantom_root_test() -> Nil {
  let assert Ok(seed) = runtime_core.bootstrap_seed(seed_input())
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap_seeded(
      runtime_fixture.connected("peer", [], 0),
      seed,
    )
  runtime_core.root_channel_address(core) |> expect.to_equal(Ok("A/root"))
  runtime_core.has_channel(core, "A/root") |> expect.to_be_true()
  runtime_core.has_channel(core, "B/root") |> expect.to_be_true()
  runtime_core.has_channel(core, "root") |> expect.to_be_false()
  runtime_core.has_channel(core, "watershed/root") |> expect.to_be_false()
}

pub fn shared_tree_runtime_relative_dependencies_stay_in_datastore_test() -> Nil {
  let assert Ok(seed) = runtime_core.bootstrap_seed(seed_input())
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap_seeded(
      runtime_fixture.connected("writer", [], 0),
      seed,
    )
  let assert Ok(core) =
    runtime_core.create_detached(core, "B/child", channel.InitMap)
  let marker =
    json.object([
      #("type", json.string("__fluid_handle__")),
      #("url", json.string("child")),
    ])
  let assert Ok(#(core, _, [attach, write])) =
    runtime_core.set(core, "B/root", "child", marker)
  let assert Ok(batch) = fluid_container.decode(attach.contents, None)
  let assert [
    fluid_container.ContainerMessage(
      fluid_container.ChannelAttach(fluid_container.Route("B", "child"), _, _),
      0,
      _,
    ),
  ] = batch.messages
  let assert Ok(_) = runtime_core.get(core, "B/root", "child")
  runtime_core.get(core, "A/root", "child") |> expect.to_equal(Error(Nil))
  let assert Ok(peer) =
    runtime_core.bootstrap_seeded(
      runtime_fixture.connected("reader", [], 0),
      seed,
    )
  let assert runtime_core.Complete(peer) = peer
  let assert Ok(write_batch) = fluid_container.decode(write.contents, None)
  let assert [write_message] = write_batch.messages
  let assert Ok(group) =
    fluid_container.encode_batch(fluid_container.DecodedBatch(
      True,
      None,
      list.append(batch.messages, [
        fluid_container.ContainerMessage(..write_message, index_in_batch: 1),
      ]),
    ))
  let assert Ok(contents) = json.parse(json.to_string(group), decode.dynamic)
  let message =
    types.SequencedDocumentMessage(
      client_id: option.Some("writer"),
      sequence_number: 1,
      minimum_sequence_number: 0,
      client_sequence_number: 1,
      reference_sequence_number: 0,
      message_type: "op",
      contents: contents,
      metadata: None,
      server_metadata: None,
      origin: None,
      traces: None,
      timestamp: 0,
      data: None,
    )
  let assert Ok(#(peer, _)) = runtime_core.handle_sequenced(peer, message)
  runtime_core.has_channel(peer, "B/child") |> expect.to_be_true()
  runtime_core.get(peer, "B/root", "child") |> expect.to_be_ok()
  Nil
}

pub fn shared_tree_runtime_seed_does_not_skip_checkpoint_prefix_test() -> Nil {
  let assert Ok(seed) = runtime_core.bootstrap_seed(seed_input())
  let assert Ok(runtime_core.MissingPrefix(core, 2, 0, 2)) =
    runtime_core.bootstrap_seeded(
      runtime_fixture.connected("peer", [], 2),
      seed,
    )
  core.last_seen_sequence_number |> expect.to_equal(0)
}

pub fn shared_tree_runtime_seed_native_map_is_explicit_test() -> Nil {
  let input = seed_input()
  runtime_core.bootstrap_seed(
    runtime_core.BootstrapSeedInput(..input, channels: []),
  )
  |> expect.to_be_error()
  runtime_core.bootstrap_seed(
    runtime_core.BootstrapSeedInput(
      ..input,
      profile: runtime_core.NativeMapSeed,
      datastores: [runtime_core.DatastoreSeed("watershed", ["org.watershed"])],
      aliases: [#("root", "watershed")],
      bootstrap_map: fluid_container.Route("watershed", "root"),
      channels: [],
    ),
  )
  |> expect.to_be_ok()
  Nil
}

pub fn shared_tree_runtime_native_bootstrap_has_canonical_root_test() -> Nil {
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap(
      runtime_fixture.connected("native", [], 0),
      summary: None,
    )
  runtime_core.root_channel_address(core)
  |> expect.to_equal(Ok("watershed/root"))
  runtime_core.has_channel(core, "watershed/root") |> expect.to_be_true()
  runtime_core.has_channel(core, "root") |> expect.to_be_false()
}

pub fn shared_tree_runtime_fixture_reads_empty_trunk_and_prefix_test() -> Nil {
  let assert Ok(session) = fluid_ids.session_id(peer_session)
  list.each(["bootstrap-map-handles", "batched-commits"], fn(name) {
    let assert Ok(fixture) = fixtures.load(name)
    let assert Ok(input) = runtime_fixture.read(fixture.input, session)
    input.sequence_number |> expect.to_equal(0)
    input.minimum_sequence_number |> expect.to_equal(0)
    input.tree.history.trunk |> expect.to_equal([])
    input.tree.history.branches |> expect.to_equal([])
    let assert Ok([#("tree", value)]) =
      wire_op.decode_map_header(input.map_header)
    let assert Ok(path) =
      json.parse(json.to_string(value), decode.at(["url"], decode.string))
    fluid_container.route_from_path(path)
    |> expect.to_equal(Ok(fluid_container.Route("A", "_C")))
    list.map(input.prefix, fn(message) { message.sequence_number })
    |> expect.to_equal([1, 2])
    list.map(input.prefix, fn(message) { message.message_type })
    |> expect.to_equal(["join", "join"])
  })
}

pub fn shared_tree_runtime_routed_seed_restores_tree_with_document_session_test() {
  let assert Ok(core) = runtime_fixture.routed_core()
  runtime_core.root_channel_address(core) |> expect.to_equal(Ok("A/root"))
  runtime_core.has_channel(core, "A/_C") |> expect.to_equal(True)
  let assert Ok(channel.TreeState(state)) = dict.get(core.channels, "A/_C")
  let assert Some(compressor) = core.compressor
  let #(_, unsubmitted) = fluid_ids.take_unfinalized_range(compressor)
  unsubmitted |> expect.to_equal(None)
  tree_kernel.history_view(state).sequenced.trunk |> expect.to_equal([])
  Nil
}

pub fn seeded_runtime_preserves_saved_local_compressor_identity_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Some(compressor) = input.compressor
  let assert Ok(#(saved, _)) = fluid_ids.generate(compressor)
  let assert Ok(seed) =
    runtime_core.bootstrap_seed(
      runtime_core.BootstrapSeedInput(..input, compressor: Some(saved)),
    )
  let assert Ok(prepared) =
    runtime_core.prepare_seed(seed, fn() {
      panic as "saved local state must not create another session"
    })
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap_seeded(
      runtime_fixture.connected("reader", [], 0),
      prepared,
    )
  let assert Some(loaded) = core.compressor
  fluid_ids.local_session(loaded)
  |> expect.to_equal(fluid_ids.local_session(saved))
}

pub fn seeded_runtime_rejects_missing_and_wrong_kind_roots_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert [_, tree] = input.channels
  runtime_core.bootstrap_seed(
    runtime_core.BootstrapSeedInput(..input, channels: [tree]),
  )
  |> expect.to_equal(
    Error(runtime_core.BadBootstrapSeed("bootstrap map is not registered")),
  )
  runtime_core.bootstrap_seed(
    runtime_core.BootstrapSeedInput(
      ..input,
      bootstrap_map: fluid_container.Route("A", "_C"),
    ),
  )
  |> expect.to_equal(
    Error(runtime_core.BadBootstrapSeed("bootstrap route is not a map")),
  )
}

pub fn shared_tree_runtime_rejects_native_tree_creation_test() {
  let assert Ok(core) = runtime_fixture.routed_core()
  let assert Ok(channel.TreeState(state)) = dict.get(core.channels, "A/_C")
  runtime_core.create_detached(core, "A/other", channel.InitTree(state))
  |> expect.to_equal(
    Error(
      runtime_core.ChannelBoundaryFailed(channel.UnsupportedTreeOperation(
        "native tree creation is not supported",
      )),
    ),
  )
}

pub fn shared_tree_runtime_seed_requires_tree_context_and_unique_view_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert [view] = input.tree_views
  runtime_core.bootstrap_seed(
    runtime_core.BootstrapSeedInput(..input, compressor: None),
  )
  |> expect.to_equal(
    Error(runtime_core.BadBootstrapSeed(
      "tree seed requires a document compressor",
    )),
  )
  runtime_core.bootstrap_seed(
    runtime_core.BootstrapSeedInput(..input, tree_views: []),
  )
  |> expect.to_equal(
    Error(runtime_core.BadBootstrapSeed("tree channel has no matching view")),
  )
  runtime_core.bootstrap_seed(
    runtime_core.BootstrapSeedInput(..input, tree_views: [view, view]),
  )
  |> expect.to_equal(
    Error(runtime_core.BadBootstrapSeed("tree channel has duplicate views")),
  )
  let unmatched =
    runtime_core.TreeViewSeed(
      fluid_container.Route("A", "other"),
      view.view_id,
      view.view,
    )
  runtime_core.bootstrap_seed(
    runtime_core.BootstrapSeedInput(..input, tree_views: [view, unmatched]),
  )
  |> expect.to_equal(
    Error(runtime_core.BadBootstrapSeed("unmatched tree view")),
  )
}

pub fn shared_tree_runtime_seed_rejects_schema_and_sequence_mismatch_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert [view] = input.tree_views
  let assert Ok(incompatible) =
    tree_schema.view_from_string(
      "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"Root\":{\"kind\":{\"object\":{\"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}",
    )
  let mismatch =
    runtime_core.TreeViewSeed(view.route, view.view_id, incompatible)
  let error =
    runtime_core.bootstrap_seed(
      runtime_core.BootstrapSeedInput(..input, tree_views: [mismatch]),
    )
    |> expect.to_be_error()
  string.inspect(error) |> string.contains("Schema") |> expect.to_equal(True)
  runtime_core.bootstrap_seed(
    runtime_core.BootstrapSeedInput(..input, sequence_number: 1),
  )
  |> expect.to_equal(
    Error(runtime_core.BadBootstrapSeed(
      "tree history does not match the document sequence point",
    )),
  )
}

pub fn shared_tree_runtime_socket_normalizes_string_contents_test() -> Nil {
  let assert Ok(session) = fluid_ids.session_id(peer_session)
  let assert Ok(fixture) = fixtures.load("bootstrap-map-handles")
  let assert Ok(input) = runtime_fixture.read(fixture.input, session)
  let assert [first, ..] = input.operations
  let assert Ok(decoded) = socket.container_contents(first.contents)
  let assert Ok(batch) = fluid_container.decode(decoded, None)
  let assert [
    fluid_container.ContainerMessage(
      fluid_container.ChannelOperation(fluid_container.Route("A", "root"), _),
      0,
      _,
    ),
  ] = batch.messages
  Nil
}

pub fn shared_tree_runtime_socket_preserves_real_group_positions_test() -> Nil {
  let assert Ok(session) = fluid_ids.session_id(peer_session)
  let assert Ok(fixture) = fixtures.load("batched-commits")
  let assert Ok(input) = runtime_fixture.read(fixture.input, session)
  let assert [group] = input.operations
  let assert Ok(contents) = socket.container_contents(group.contents)
  let assert Some(raw_metadata) = group.metadata
  let assert Ok(metadata) = decode.run(raw_metadata, wire.json_value_decoder())
  let assert Ok(decoded) = fluid_container.decode(contents, Some(metadata))
  let assert [
    fluid_container.ContainerMessage(fluid_container.IdAllocation(_), 0, _),
    fluid_container.ContainerMessage(
      fluid_container.ChannelOperation(fluid_container.Route("A", "_C"), _),
      1,
      _,
    ),
    fluid_container.ContainerMessage(
      fluid_container.ChannelOperation(fluid_container.Route("A", "_C"), _),
      2,
      _,
    ),
    fluid_container.ContainerMessage(
      fluid_container.ChannelOperation(fluid_container.Route("A", "_C"), _),
      3,
      _,
    ),
  ] = decoded.messages
  decoded.grouped |> expect.to_be_true()
  group.client_sequence_number |> expect.to_equal(1)
  group.sequence_number |> expect.to_equal(3)
}

pub fn shared_tree_runtime_bootstrap_corpus_test() {
  fixtures.assert_case("bootstrap-map-handles", runtime_fixture.run_bootstrap)
}

pub fn shared_tree_runtime_batched_corpus_test() {
  fixtures.assert_case("batched-commits", runtime_fixture.run_batched)
}

pub fn shared_tree_runtime_expected_values_do_not_drive_replay_test() {
  let assert Ok(fixture) = fixtures.load("batched-commits")
  let changed_expected =
    json.object([
      #("observations", json.array([json.string("wrong")], fn(x) { x })),
    ])
  let assert Ok(actual) = runtime_fixture.run_batched(fixture.input)
  fixtures.first_difference(actual, fixture.expected)
  |> expect.to_equal(Ok(Nil))
  fixtures.first_difference(actual, changed_expected)
  |> expect.to_be_error()
  Nil
}

pub fn shared_tree_runtime_bridge_decodes_captured_group_with_allocation_test() {
  let assert Ok(core) = runtime_fixture.routed_core()
  let assert Ok(fixture) = fixtures.load("batched-commits")
  let assert Some(compressor) = core.compressor
  let assert Ok(input) =
    runtime_fixture.read(fixture.input, fluid_ids.local_session(compressor))
  let assert [group] = input.operations
  let assert Ok(contents) = socket.container_contents(group.contents)
  let assert Some(raw_metadata) = group.metadata
  let assert Ok(metadata) = decode.run(raw_metadata, wire.json_value_decoder())
  let assert Ok(decoded) = fluid_container.decode(contents, Some(metadata))
  let assert [
    fluid_container.ContainerMessage(fluid_container.IdAllocation(range), 0, _),
    fluid_container.ContainerMessage(
      fluid_container.ChannelOperation(fluid_container.Route("A", "_C"), first),
      1,
      _,
    ),
    ..
  ] = decoded.messages
  let assert Ok(compressor) = fluid_ids.finalize(compressor, range)
  let assert Ok(channel.TreeState(state)) = dict.get(core.channels, "A/_C")
  let assert Ok(#(commit, message)) =
    tree_runtime.decode_message(json.to_string(first), state, compressor)
  commit.revision |> expect.to_equal(message.commit.revision)
  commit.originator |> expect.to_equal(message.commit.originator)
  let assert Ok(_) = tree_runtime.identity_order(state, commit, compressor)
  let #(received, _, _) =
    tree_runtime.receive_commit(
      state,
      commit,
      tree_types.SequencePoint(group.sequence_number, 0),
      group.reference_sequence_number,
      group.minimum_sequence_number,
      compressor,
    )
    |> expect.to_be_ok
  tree_kernel.history_view(received).sequenced.trunk
  |> list.length
  |> expect.to_equal(1)
  Nil
}

pub fn shared_tree_runtime_allocates_before_content_test() {
  let assert Ok(core) = runtime_fixture.routed_core()
  let assert Ok(#(next, events, [outbound])) =
    runtime_core.submit_tree_edits(core, "A/_C", [
      tree_types.SetField(["title"], tree_types.StringValue("native")),
    ])
  let assert Ok(batch) =
    fluid_container.decode(outbound.contents, outbound.metadata)
  let assert [
    fluid_container.ContainerMessage(fluid_container.IdAllocation(_), 0, _),
    fluid_container.ContainerMessage(
      fluid_container.ChannelOperation(fluid_container.Route("A", "_C"), _),
      1,
      _,
    ),
  ] = batch.messages
  let assert Some(outer) = outbound.metadata
  json.parse(json.to_string(outer), decode.at(["groupedOpCount"], decode.int))
  |> expect.to_equal(Ok(2))
  let assert [
    fluid_container.ContainerMessage(_, _, Some(first)),
    fluid_container.ContainerMessage(_, _, Some(last)),
  ] = batch.messages
  json.parse(json.to_string(first), decode.at(["batch"], decode.bool))
  |> expect.to_equal(Ok(True))
  json.parse(json.to_string(last), decode.at(["batch"], decode.bool))
  |> expect.to_equal(Ok(False))
  next.next_client_sequence_number
  |> expect.to_equal(core.next_client_sequence_number + 1)
  list.length(next.in_flight) |> expect.to_equal(1)
  list.length(events) |> expect.to_equal(1)
  let assert Some(compressor) = next.compressor
  let #(_, unfinalized) = fluid_ids.take_unfinalized_range(compressor)
  let assert Some(fluid_ids.CreationRange(_, Some(_))) = unfinalized
  runtime_core.tree_read(next, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("native"))))
}

pub fn shared_tree_runtime_receives_captured_group_with_tree_ordinals_test() {
  let assert Ok(core) = runtime_fixture.routed_core()
  let assert Ok(fixture) = fixtures.load("batched-commits")
  let assert Some(compressor) = core.compressor
  let assert Ok(input) =
    runtime_fixture.read(fixture.input, fluid_ids.local_session(compressor))
  let assert [group] = input.operations
  let #(next, ingested) =
    runtime_core.handle_sequenced(core, group) |> expect.to_be_ok
  let assert Ok(channel.TreeState(tree)) = dict.get(next.channels, "A/_C")
  let history = tree_kernel.history_view(tree)
  list.map(history.sequenced.trunk, fn(entry) { entry.point })
  |> expect.to_equal([
    tree_types.SequencePoint(3, 0),
    tree_types.SequencePoint(3, 1),
    tree_types.SequencePoint(3, 2),
  ])
  next.last_seen_sequence_number |> expect.to_equal(3)
  next.minimum_sequence_number |> expect.to_equal(group.minimum_sequence_number)
  list.length(ingested.events) |> expect.to_equal(1)
}

pub fn shared_tree_runtime_tree_ordinals_ignore_other_routes_test() {
  let assert Ok(#(input, prefix)) = runtime_fixture.routed_seed_input()
  let assert [_, runtime_core.ChannelSeed(_, attributes, snapshot)] =
    input.channels
  let assert [view] = input.tree_views
  let route = fluid_container.Route("A", "_D")
  let assert Ok(second_id) =
    fluid_ids.stable_id("60000000-0000-4000-8000-000000000006")
  let assert Ok(seed) =
    runtime_core.bootstrap_seed(
      runtime_core.BootstrapSeedInput(
        ..input,
        channels: list.append(input.channels, [
          runtime_core.ChannelSeed(route, attributes, snapshot),
        ]),
        tree_views: list.append(input.tree_views, [
          runtime_core.TreeViewSeed(route, second_id, view.view),
        ]),
      ),
    )
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap_seeded(
      runtime_fixture.connected("reader", prefix, 2),
      seed,
    )
  let assert Some(compressor) = core.compressor
  let assert Ok(fixture) = fixtures.load("batched-commits")
  let assert Ok(fixture_input) =
    runtime_fixture.read(fixture.input, fluid_ids.local_session(compressor))
  let assert [group] = fixture_input.operations
  let assert Ok(contents) = socket.container_contents(group.contents)
  let assert Some(raw_metadata) = group.metadata
  let assert Ok(metadata) = decode.run(raw_metadata, wire.json_value_decoder())
  let assert Ok(batch) = fluid_container.decode(contents, Some(metadata))
  let assert [
    fluid_container.ContainerMessage(allocation, _, _),
    fluid_container.ContainerMessage(first, _, _),
    fluid_container.ContainerMessage(second, _, _),
    fluid_container.ContainerMessage(third, _, _),
  ] = batch.messages
  let assert fluid_container.ChannelOperation(_, first_contents) = first
  let also_first = fluid_container.ChannelOperation(route, first_contents)
  let map =
    fluid_container.ChannelOperation(
      fluid_container.Route("A", "root"),
      wire_op.encode_map_operation(map_kernel.Set("label", json.string("map"))),
    )
  let encoded =
    batch_message([allocation, first, map, also_first, second, third])
  let message =
    types.SequencedDocumentMessage(
      ..encoded,
      sequence_number: 3,
      reference_sequence_number: group.reference_sequence_number,
    )
  let #(next, _) =
    runtime_core.handle_sequenced(core, message) |> expect.to_be_ok
  let assert Ok(channel.TreeState(one)) = dict.get(next.channels, "A/_C")
  let assert Ok(channel.TreeState(two)) = dict.get(next.channels, "A/_D")
  list.map(tree_kernel.history_view(one).sequenced.trunk, fn(item) {
    item.point
  })
  |> expect.to_equal([
    tree_types.SequencePoint(3, 0),
    tree_types.SequencePoint(3, 1),
    tree_types.SequencePoint(3, 2),
  ])
  list.map(tree_kernel.history_view(two).sequenced.trunk, fn(item) {
    item.point
  })
  |> expect.to_equal([tree_types.SequencePoint(3, 0)])
}

pub fn shared_tree_runtime_refuses_invalid_local_batch_atomically_test() {
  let assert Ok(core) = runtime_fixture.routed_core()
  let assert Some(compressor) = core.compressor
  let assert Ok(before) = fluid_ids.serialize(compressor, True)
  runtime_core.submit_tree_edits(core, "A/_C", [
    tree_types.SetField(["title"], tree_types.StringValue("valid")),
    tree_types.ClearField(["title"]),
  ])
  |> expect.to_be_error()
  let assert Some(compressor) = core.compressor
  fluid_ids.serialize(compressor, True) |> expect.to_equal(Ok(before))
  core.in_flight |> expect.to_equal([])
  core.next_client_sequence_number |> expect.to_equal(1)
  runtime_core.tree_read(core, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue(""))))
}

pub fn shared_tree_runtime_invalid_edits_do_not_allocate_test() {
  let assert Ok(core) = runtime_fixture.routed_core()
  let assert Some(compressor) = core.compressor
  let assert Ok(before) = fluid_ids.serialize(compressor, True)
  let assert Ok(channel.TreeState(tree)) = dict.get(core.channels, "A/_C")
  let assert Ok(snapshot) = tree_kernel.snapshot(tree)
  let invalid = [
    tree_types.SetField(["title"], tree_types.BooleanValue(True)),
    tree_types.SetField(
      ["title"],
      tree_types.ObjectValue("not-in-stored-schema", []),
    ),
    tree_types.ClearField(["title"]),
    tree_types.SetField(["unknown"], tree_types.StringValue("bad")),
  ]
  list.each(invalid, fn(edit) {
    runtime_core.submit_tree_edits(core, "A/_C", [edit])
    |> expect.to_be_error()
    let assert Some(current) = core.compressor
    fluid_ids.serialize(current, True) |> expect.to_equal(Ok(before))
    let assert Ok(channel.TreeState(current_tree)) =
      dict.get(core.channels, "A/_C")
    tree_kernel.snapshot(current_tree) |> expect.to_equal(Ok(snapshot))
    core.in_flight |> expect.to_equal([])
    core.next_client_sequence_number |> expect.to_equal(1)
  })
}

pub fn shared_tree_runtime_reads_report_channel_and_path_errors_test() {
  let assert Ok(core) = runtime_fixture.routed_core()
  runtime_core.tree_read(core, "A/missing", [])
  |> expect.to_equal(Error(runtime_core.UnknownChannel("A/missing", 2)))
  runtime_core.tree_read(core, "A/root", [])
  |> expect.to_equal(
    Error(runtime_core.WrongChannelType(
      "A/root",
      channel.TreeChannel,
      channel.MapChannel,
    )),
  )
  runtime_core.tree_read(core, "A/_C", ["missing", "nested"])
  |> expect.to_equal(
    Error(runtime_core.TreeOperationFailed(
      "A/_C",
      tree_types.InvalidEdit(
        ["missing", "nested"],
        "field is not an optional field",
      ),
    )),
  )
}

pub fn shared_tree_runtime_acknowledges_local_group_once_test() {
  let assert Ok(core) = runtime_fixture.routed_core()
  let assert Ok(#(pending, _, [outbound])) =
    runtime_core.submit_tree_edits(core, "A/_C", [
      tree_types.SetField(["title"], tree_types.StringValue("new")),
      tree_types.SetField(["title"], tree_types.StringValue("final")),
    ])
  let assert Ok(contents) =
    json.parse(json.to_string(outbound.contents), decode.dynamic)
  let assert Some(raw_metadata) = outbound.metadata
  let assert Ok(metadata) =
    json.parse(json.to_string(raw_metadata), decode.dynamic)
  let message =
    types.SequencedDocumentMessage(
      ..batch_message([]),
      client_id: Some(pending.client_id),
      sequence_number: 3,
      client_sequence_number: outbound.client_sequence_number,
      reference_sequence_number: outbound.reference_sequence_number,
      contents: contents,
      metadata: Some(metadata),
    )
  let #(settled, ingested) =
    runtime_core.handle_sequenced(pending, message) |> expect.to_be_ok
  settled.in_flight |> expect.to_equal([])
  ingested.events |> expect.to_equal([])
  let assert Ok(channel.TreeState(tree)) = dict.get(settled.channels, "A/_C")
  list.length(tree_kernel.history_view(tree).sequenced.trunk)
  |> expect.to_equal(2)
}

pub fn shared_tree_runtime_foreign_author_cannot_ack_local_tree_test() {
  let assert Ok(core) = runtime_fixture.routed_core()
  let assert Ok(#(pending, _, [outbound])) =
    runtime_core.submit_tree_edits(core, "A/_C", [
      tree_types.SetField(["title"], tree_types.StringValue("local")),
    ])
  let foreign = from_outbound(outbound)
  runtime_core.handle_sequenced(pending, foreign) |> expect.to_be_error()
  let genuine =
    types.SequencedDocumentMessage(
      ..foreign,
      client_id: Some(pending.client_id),
    )
  let #(settled, ingested) =
    runtime_core.handle_sequenced(pending, genuine) |> expect.to_be_ok()
  settled.in_flight |> expect.to_equal([])
  ingested.events |> expect.to_equal([])
}

pub fn shared_tree_runtime_group_without_explicit_id_test() {
  let core = core_from(seed_input())
  let operation =
    fluid_container.ChannelOperation(
      fluid_container.Route("A", "root"),
      wire_op.encode_map_operation(map_kernel.Set("status", json.string("live"))),
    )
  let assert Ok(encoded) =
    fluid_container.encode_batch(
      fluid_container.DecodedBatch(True, None, [
        fluid_container.ContainerMessage(
          operation,
          0,
          Some(json.object([#("batch", json.bool(True))])),
        ),
        fluid_container.ContainerMessage(
          operation,
          1,
          Some(json.object([#("batch", json.bool(False))])),
        ),
      ]),
    )
  let assert Ok(contents) = json.parse(json.to_string(encoded), decode.dynamic)
  let assert Ok(metadata) = json.parse("{\"groupedOpCount\":2}", decode.dynamic)
  let #(next, _) =
    runtime_core.handle_sequenced(
      core,
      types.SequencedDocumentMessage(
        ..batch_message([]),
        contents: contents,
        metadata: Some(metadata),
      ),
    )
    |> expect.to_be_ok()
  next.last_seen_sequence_number |> expect.to_equal(1)
}

pub fn shared_tree_runtime_allocation_only_advances_document_test() {
  let assert Ok(core) = runtime_fixture.routed_core()
  let assert Ok(session) =
    fluid_ids.session_id("50000000-0000-4000-8000-000000000005")
  let assert Ok(#(compressor, _)) = fluid_ids.generate(fluid_ids.new(session))
  let assert #(_, Some(range)) = fluid_ids.take_creation_range(compressor)
  let message =
    types.SequencedDocumentMessage(
      ..batch_message([fluid_container.IdAllocation(range)]),
      sequence_number: 3,
    )
  let #(next, ingested) =
    runtime_core.handle_sequenced(core, message) |> expect.to_be_ok
  next.last_seen_sequence_number |> expect.to_equal(3)
  ingested.events |> expect.to_equal([])
  let assert Some(compressor) = next.compressor
  let assert Ok(_) = fluid_ids.serialize(compressor, False)
  let assert Ok(channel.TreeState(tree)) = dict.get(next.channels, "A/_C")
  tree_kernel.history_view(tree).sequenced.sequence_number |> expect.to_equal(3)
}

pub fn shared_tree_runtime_rejects_bad_later_child_without_allocation_test() {
  let assert Ok(core) = runtime_fixture.routed_core()
  let assert Some(compressor) = core.compressor
  let assert Ok(before) = fluid_ids.serialize(compressor, True)
  let assert Ok(#(_, _, [outbound])) =
    runtime_core.submit_tree_edits(core, "A/_C", [
      tree_types.SetField(["title"], tree_types.StringValue("candidate")),
    ])
  let assert Ok(batch) =
    fluid_container.decode(outbound.contents, outbound.metadata)
  let assert [fluid_container.ContainerMessage(allocation, _, _), ..] =
    batch.messages
  let bad =
    fluid_container.ChannelOperation(
      fluid_container.Route("A", "_C"),
      json.object([#("version", json.int(999))]),
    )
  let message =
    types.SequencedDocumentMessage(
      ..batch_message([allocation, bad]),
      sequence_number: 3,
    )
  runtime_core.handle_sequenced(core, message) |> expect.to_be_error()
  fluid_ids.serialize(compressor, True) |> expect.to_equal(Ok(before))
  core.last_seen_sequence_number |> expect.to_equal(2)
  core.in_flight |> expect.to_equal([])
}

pub fn shared_tree_runtime_bad_final_child_rolls_back_tree_and_map_test() {
  let assert Ok(reader) = runtime_fixture.routed_core()
  let writer = remote_writer_core()
  let assert Ok(#(_, _, [outbound])) =
    runtime_core.submit_tree_edits(writer, "A/_C", [
      tree_types.SetField(["title"], tree_types.StringValue("rejected")),
    ])
  let assert Ok(batch) =
    fluid_container.decode(outbound.contents, outbound.metadata)
  let assert [
    fluid_container.ContainerMessage(allocation, _, _),
    fluid_container.ContainerMessage(commit, _, _),
  ] = batch.messages
  let map =
    fluid_container.ChannelOperation(
      fluid_container.Route("A", "root"),
      wire_op.encode_map_operation(map_kernel.Set("marker", json.int(1))),
    )
  let invalid =
    fluid_container.ChannelOperation(
      fluid_container.Route("missing", "root"),
      wire_op.encode_map_operation(map_kernel.Clear),
    )
  let message =
    types.SequencedDocumentMessage(
      ..batch_message([allocation, commit, map, invalid]),
      sequence_number: 3,
      reference_sequence_number: 2,
    )
  runtime_core.handle_sequenced(reader, message)
  |> expect.to_equal(Error(runtime_core.UnknownChannel("missing/root", 3)))
  runtime_core.tree_read(reader, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue(""))))
  runtime_core.get(reader, "A/root", "marker") |> expect.to_equal(Error(Nil))
  reader.last_seen_sequence_number |> expect.to_equal(2)
  let assert Some(compressor) = reader.compressor
  let #(_, unsubmitted) = fluid_ids.take_unfinalized_range(compressor)
  unsubmitted |> expect.to_equal(None)
}

pub fn shared_tree_runtime_rejects_forged_own_child_test() {
  let assert Ok(core) = runtime_fixture.routed_core()
  let assert Ok(#(pending, _, [outbound])) =
    runtime_core.submit_tree_edits(core, "A/_C", [
      tree_types.SetField(["title"], tree_types.StringValue("one")),
    ])
  let assert Ok(batch) =
    fluid_container.decode(outbound.contents, outbound.metadata)
  let assert [fluid_container.ContainerMessage(allocation, _, _), _] =
    batch.messages
  let message =
    types.SequencedDocumentMessage(
      ..batch_message([allocation]),
      client_id: Some(pending.client_id),
      sequence_number: 3,
      client_sequence_number: outbound.client_sequence_number,
      reference_sequence_number: outbound.reference_sequence_number,
    )
  runtime_core.handle_sequenced(pending, message)
  |> expect.to_equal(
    Error(runtime_core.AckMismatch(
      "outer submission does not match pending items",
    )),
  )
  list.length(pending.in_flight) |> expect.to_equal(1)
}

pub fn shared_tree_runtime_refuses_tree_commit_without_allocation_test() {
  let assert Ok(core) = runtime_fixture.routed_core()
  let assert Ok(fixture) = fixtures.load("batched-commits")
  let assert Some(compressor) = core.compressor
  let assert Ok(input) =
    runtime_fixture.read(fixture.input, fluid_ids.local_session(compressor))
  let assert [group] = input.operations
  let assert Ok(contents) = socket.container_contents(group.contents)
  let assert Some(raw_metadata) = group.metadata
  let assert Ok(metadata) = decode.run(raw_metadata, wire.json_value_decoder())
  let assert Ok(batch) = fluid_container.decode(contents, Some(metadata))
  let assert [_, fluid_container.ContainerMessage(commit, _, _), ..] =
    batch.messages
  let message =
    types.SequencedDocumentMessage(
      ..batch_message([commit]),
      sequence_number: 3,
      reference_sequence_number: group.reference_sequence_number,
    )
  runtime_core.handle_sequenced(core, message) |> expect.to_be_error()
  core.last_seen_sequence_number |> expect.to_equal(2)
}

fn remote_writer_core() -> runtime_core.Core {
  let assert Ok(#(input, prefix)) = runtime_fixture.routed_seed_input()
  let assert Some(compressor) = input.compressor
  let assert Ok(serialized) = fluid_ids.serialize(compressor, False)
  let assert Ok(session) =
    fluid_ids.session_id("50000000-0000-4000-8000-000000000005")
  let assert Ok(remote_compressor) = fluid_ids.deserialize(serialized, session)
  let assert Ok(seed) =
    runtime_core.bootstrap_seed(
      runtime_core.BootstrapSeedInput(
        ..input,
        compressor: Some(remote_compressor),
      ),
    )
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap_seeded(
      runtime_fixture.connected("remote-writer", prefix, 2),
      seed,
    )
  core
}

fn from_outbound(
  outbound: wire.OutboundOperation,
) -> types.SequencedDocumentMessage {
  let assert Ok(contents) =
    json.parse(json.to_string(outbound.contents), decode.dynamic)
  let metadata = case outbound.metadata {
    None -> None
    Some(value) -> {
      let assert Ok(decoded) = json.parse(json.to_string(value), decode.dynamic)
      Some(decoded)
    }
  }
  types.SequencedDocumentMessage(
    ..batch_message([]),
    client_id: Some("remote-writer"),
    sequence_number: 3,
    client_sequence_number: outbound.client_sequence_number,
    reference_sequence_number: outbound.reference_sequence_number,
    contents: contents,
    metadata: metadata,
  )
}

pub fn shared_tree_runtime_remote_group_emits_one_tree_event_test() {
  let assert Ok(reader) = runtime_fixture.routed_core()
  let writer = remote_writer_core()
  let assert Ok(#(_, local_events, [outbound])) =
    runtime_core.submit_tree_edits(writer, "A/_C", [
      tree_types.SetField(["title"], tree_types.StringValue("first")),
      tree_types.SetField(["title"], tree_types.StringValue("second")),
      tree_types.SetField(["title"], tree_types.StringValue("third")),
    ])
  list.length(local_events) |> expect.to_equal(1)
  let #(reader, ingested) =
    runtime_core.handle_sequenced(reader, from_outbound(outbound))
    |> expect.to_be_ok
  ingested.events
  |> expect.to_equal([
    #("A/_C", channel.TreeEvent(tree_kernel.TreeChanged(False))),
  ])
  runtime_core.tree_read(reader, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("third"))))
  let assert Ok(channel.TreeState(tree)) = dict.get(reader.channels, "A/_C")
  list.length(tree_kernel.history_view(tree).sequenced.trunk)
  |> expect.to_equal(3)
}

pub fn shared_tree_runtime_net_zero_group_retains_history_without_events_test() {
  let assert Ok(reader) = runtime_fixture.routed_core()
  let writer = remote_writer_core()
  let assert Ok(#(_, local_events, [outbound])) =
    runtime_core.submit_tree_edits(writer, "A/_C", [
      tree_types.SetField(["title"], tree_types.StringValue("temporary")),
      tree_types.SetField(["title"], tree_types.StringValue("")),
    ])
  local_events |> expect.to_equal([])
  let #(reader, ingested) =
    runtime_core.handle_sequenced(reader, from_outbound(outbound))
    |> expect.to_be_ok
  ingested.events |> expect.to_equal([])
  let assert Ok(channel.TreeState(tree)) = dict.get(reader.channels, "A/_C")
  list.length(tree_kernel.history_view(tree).sequenced.trunk)
  |> expect.to_equal(2)
}

pub fn shared_tree_runtime_next_range_includes_rollback_revisions_test() {
  let writer = remote_writer_core()
  let assert Ok(#(pending, _, [_])) =
    runtime_core.submit_tree_edits(writer, "A/_C", [
      tree_types.SetField(["title"], tree_types.StringValue("pending")),
    ])
  let assert Ok(fixture) = fixtures.load("batched-commits")
  let assert Some(compressor) = pending.compressor
  let assert Ok(input) =
    runtime_fixture.read(fixture.input, fluid_ids.local_session(compressor))
  let assert [group] = input.operations
  let #(rebased, _) =
    runtime_core.handle_sequenced(pending, group) |> expect.to_be_ok
  let assert Some(compressor) = rebased.compressor
  let #(_, unsubmitted) = fluid_ids.take_creation_range(compressor)
  let assert Some(fluid_ids.CreationRange(_, Some(rollbacks))) = unsubmitted
  let assert Ok(#(_, _, [outbound])) =
    runtime_core.submit_tree_edits(rebased, "A/_C", [
      tree_types.SetField(["title"], tree_types.StringValue("next")),
    ])
  let assert Ok(batch) =
    fluid_container.decode(outbound.contents, outbound.metadata)
  let assert [
    fluid_container.ContainerMessage(
      fluid_container.IdAllocation(fluid_ids.CreationRange(_, Some(ids))),
      0,
      _,
    ),
    ..
  ] = batch.messages
  ids.first_gen_count |> expect.to_equal(rollbacks.first_gen_count)
  { ids.count > rollbacks.count } |> expect.to_be_true()
}

pub fn shared_tree_runtime_gap_drains_tree_batch_once_test() {
  let assert Ok(reader) = runtime_fixture.routed_core()
  let writer = remote_writer_core()
  let assert Ok(#(_, _, [outbound])) =
    runtime_core.submit_tree_edits(writer, "A/_C", [
      tree_types.SetField(["title"], tree_types.StringValue("after-gap")),
    ])
  let future =
    types.SequencedDocumentMessage(
      ..from_outbound(outbound),
      sequence_number: 4,
    )
  let #(buffered, ingested) =
    runtime_core.handle_sequenced(reader, future) |> expect.to_be_ok
  ingested.request_operations_from |> expect.to_equal(Some(2))
  ingested.events |> expect.to_equal([])
  let earlier =
    types.SequencedDocumentMessage(..batch_message([]), sequence_number: 3)
  let #(drained, ingested) =
    runtime_core.handle_sequenced(buffered, earlier) |> expect.to_be_ok
  drained.last_seen_sequence_number |> expect.to_equal(4)
  ingested.events
  |> expect.to_equal([
    #("A/_C", channel.TreeEvent(tree_kernel.TreeChanged(False))),
  ])
  let #(duplicate, ignored) =
    runtime_core.handle_sequenced(drained, future) |> expect.to_be_ok
  duplicate.last_seen_sequence_number |> expect.to_equal(4)
  ignored.events |> expect.to_equal([])
}

pub fn shared_tree_runtime_all_outer_messages_advance_tree_watermarks_test() {
  let assert Ok(reader) = runtime_fixture.routed_core()
  let assert Ok(#(_, prefix)) = runtime_fixture.routed_seed_input()
  let assert [joined, ..] = prefix
  let assert Ok(session) =
    fluid_ids.session_id("70000000-0000-4000-8000-000000000007")
  let assert Ok(#(compressor, _)) = fluid_ids.generate(fluid_ids.new(session))
  let assert #(_, Some(range)) = fluid_ids.take_creation_range(compressor)
  let map =
    fluid_container.ChannelOperation(
      fluid_container.Route("A", "root"),
      wire_op.encode_map_operation(map_kernel.Set("status", json.string("live"))),
    )
  let messages = [
    types.SequencedDocumentMessage(
      ..joined,
      sequence_number: 3,
      minimum_sequence_number: 1,
    ),
    types.SequencedDocumentMessage(
      ..batch_message([map]),
      sequence_number: 4,
      minimum_sequence_number: 1,
    ),
    types.SequencedDocumentMessage(
      ..batch_message([]),
      sequence_number: 5,
      minimum_sequence_number: 2,
      message_type: "noop",
    ),
    types.SequencedDocumentMessage(
      ..batch_message([]),
      sequence_number: 6,
      minimum_sequence_number: 2,
    ),
    types.SequencedDocumentMessage(
      ..batch_message([fluid_container.IdAllocation(range)]),
      sequence_number: 7,
      minimum_sequence_number: 3,
    ),
    types.SequencedDocumentMessage(
      ..batch_message([]),
      sequence_number: 8,
      minimum_sequence_number: 3,
      message_type: "leave",
      data: Some("\"departing\""),
    ),
    types.SequencedDocumentMessage(
      ..batch_message([]),
      sequence_number: 9,
      minimum_sequence_number: 9,
      message_type: "noClient",
      client_id: None,
    ),
  ]
  let #(reader, _) =
    list.fold(messages, #(reader, 2), fn(acc, message) {
      let #(core, previous) = acc
      let #(core, _) =
        runtime_core.handle_sequenced(core, message) |> expect.to_be_ok
      let assert Ok(channel.TreeState(tree)) = dict.get(core.channels, "A/_C")
      tree_kernel.history_view(tree).sequenced.sequence_number
      |> expect.to_equal(previous + 1)
      tree_kernel.history_view(tree).sequenced.minimum_sequence_number
      |> expect.to_equal(message.minimum_sequence_number)
      #(core, previous + 1)
    })
  reader.last_seen_sequence_number |> expect.to_equal(9)
}

pub fn shared_tree_runtime_empty_group_with_count_advances_tree_test() {
  let assert Ok(core) = runtime_fixture.routed_core()
  let assert Ok(metadata) =
    json.parse(
      "{\"batchId\":\"empty-batch\",\"groupedOpCount\":0}",
      decode.dynamic,
    )
  let empty =
    types.SequencedDocumentMessage(
      ..batch_message([]),
      sequence_number: 3,
      metadata: Some(metadata),
    )
  let #(core, ingested) =
    runtime_core.handle_sequenced(core, empty) |> expect.to_be_ok
  core.last_seen_sequence_number |> expect.to_equal(3)
  ingested.events |> expect.to_equal([])
  let assert Ok(channel.TreeState(tree)) = dict.get(core.channels, "A/_C")
  tree_kernel.history_view(tree).sequenced.sequence_number |> expect.to_equal(3)
}

pub fn shared_tree_runtime_rejects_regressing_document_minimum_test() {
  let assert Ok(core) = runtime_fixture.routed_core()
  let first =
    types.SequencedDocumentMessage(
      ..batch_message([]),
      sequence_number: 3,
      minimum_sequence_number: 2,
    )
  let #(core, _) = runtime_core.handle_sequenced(core, first) |> expect.to_be_ok
  let invalid =
    types.SequencedDocumentMessage(
      ..batch_message([]),
      sequence_number: 4,
      minimum_sequence_number: 1,
    )
  runtime_core.handle_sequenced(core, invalid)
  |> expect.to_equal(
    Error(runtime_core.TreeOperationFailed(
      "A/_C",
      tree_types.InvalidHistory("minimum sequence number regresses"),
    )),
  )
  core.last_seen_sequence_number |> expect.to_equal(3)
}

pub fn shared_tree_runtime_refuses_malformed_membership_message_test() {
  let assert Ok(core) = runtime_fixture.routed_core()
  list.each(["join", "leave"], fn(message_type) {
    let malformed =
      types.SequencedDocumentMessage(
        ..batch_message([]),
        sequence_number: 3,
        message_type: message_type,
        data: Some("{}"),
      )
    runtime_core.handle_sequenced(core, malformed)
    |> expect.to_equal(Error(runtime_core.BadOperationContents(3)))
  })
}

pub fn shared_tree_runtime_rejects_empty_edit_batch_test() {
  let assert Ok(core) = runtime_fixture.routed_core()
  runtime_core.submit_tree_edits(core, "A/_C", [])
  |> expect.to_equal(Error(runtime_core.EmptyTreeEditBatch))
}

pub fn shared_tree_runtime_rejects_ungrouped_compression_test() -> Nil {
  fluid_container.decode(
    json.object([
      #("type", json.string("idAllocation")),
      #("compression", json.string("lz4")),
      #("contents", json.object([])),
    ]),
    None,
  )
  |> expect.to_equal(Error(fluid_container.UnsupportedCompression("lz4")))
}

pub fn shared_tree_runtime_fixture_refuses_missing_prefix_test() -> Nil {
  let assert Ok(session) = fluid_ids.session_id(peer_session)
  let assert Ok(fixture) = fixtures.load("batched-commits")
  let assert Ok(fields) =
    json.parse(
      json.to_string(fixture.input),
      decode.dict(decode.string, wire.json_value_decoder()),
    )
  let assert Ok(decoder_input) = dict.get(fields, "decoderInput")
  let assert Ok(decoder_fields) =
    json.parse(
      json.to_string(decoder_input),
      decode.dict(decode.string, wire.json_value_decoder()),
    )
  list.each([False, True], fn(missing) {
    let decoder_fields = case missing {
      True -> dict.delete(decoder_fields, "deliveryPrefix")
      False ->
        dict.insert(
          decoder_fields,
          "deliveryPrefix",
          json.preprocessed_array([]),
        )
    }
    let input =
      fields
      |> dict.insert("decoderInput", json.object(dict.to_list(decoder_fields)))
      |> dict.to_list
      |> json.object
    runtime_fixture.read(input, session) |> expect.to_be_error()
  })
}
