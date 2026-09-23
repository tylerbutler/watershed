import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None}
import spillway/types
import startest/expect
import watershed/channel
import watershed/fluid_ids
import watershed/handle
import watershed/map_kernel
import watershed/runtime_core
import watershed/tree/fixtures
import watershed/tree/runtime_fixture
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
  let assert Ok(decoded) = fluid_container.decode(contents, None)
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
