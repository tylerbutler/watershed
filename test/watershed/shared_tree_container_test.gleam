import gleam/bit_array
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import startest/expect
import watershed/tree/container_fixture
import watershed/tree/fixtures
import watershed/wire
import watershed/wire/fluid_container.{
  ChannelAttach, ChannelOperation, ContainerMessage, DatastoreAlias,
  DatastoreAttach, DecodedBatch, IdAllocation, Route,
}

fn parse(raw: String) -> Json {
  let assert Ok(value) = json.parse(raw, wire.json_value_decoder())
  value
}

pub fn shared_tree_container_decodes_nested_channel_operation_test() -> Nil {
  let contents =
    parse(
      "{\"type\":\"component\",\"contents\":{\"address\":\"A\",\"contents\":{\"type\":\"op\",\"content\":{\"address\":\"root\",\"contents\":{\"type\":\"delete\",\"key\":\"tree\"}}}}}",
    )
  let metadata = Some(json.object([#("batchId", json.string("outer"))]))
  let assert Ok(DecodedBatch(
    False,
    decoded_metadata,
    [ContainerMessage(ChannelOperation(Route("A", "root"), payload), 0, inner)],
  )) = fluid_container.decode(contents, metadata)

  decoded_metadata |> expect.to_equal(metadata)
  inner |> expect.to_equal(metadata)
  wire.json_semantically_equal(
    payload,
    parse("{\"type\":\"delete\",\"key\":\"tree\"}"),
  )
  |> expect.to_be_true()
}

pub fn shared_tree_container_keeps_routes_scoped_to_datastores_test() -> Nil {
  let a =
    parse(
      "{\"type\":\"component\",\"contents\":{\"address\":\"A\",\"contents\":{\"type\":\"op\",\"content\":{\"address\":\"root\",\"contents\":{\"value\":1}}}}}",
    )
  let b =
    parse(
      "{\"type\":\"component\",\"contents\":{\"address\":\"B\",\"contents\":{\"type\":\"op\",\"content\":{\"address\":\"root\",\"contents\":{\"value\":2}}}}}",
    )
  let assert Ok(DecodedBatch(
    False,
    _,
    [ContainerMessage(ChannelOperation(route_a, _), 0, _)],
  )) = fluid_container.decode(a, None)
  let assert Ok(DecodedBatch(
    False,
    _,
    [ContainerMessage(ChannelOperation(route_b, _), 0, _)],
  )) = fluid_container.decode(b, None)

  route_a |> expect.to_equal(Route("A", "root"))
  route_b |> expect.to_equal(Route("B", "root"))
}

pub fn shared_tree_container_decodes_attach_and_alias_forms_test() -> Nil {
  let datastore =
    parse(
      "{\"type\":\"attach\",\"contents\":{\"id\":\"B\",\"type\":\"example-store\",\"snapshot\":{\"entries\":[]},\"extra\":true}}",
    )
  let alias =
    parse(
      "{\"type\":\"alias\",\"contents\":{\"internalId\":\"B\",\"alias\":\"secondary\",\"extra\":true}}",
    )
  let channel =
    parse(
      "{\"type\":\"component\",\"contents\":{\"address\":\"A\",\"contents\":{\"type\":\"attach\",\"content\":{\"id\":\"root\",\"type\":\"https://graph.microsoft.com/types/map\",\"snapshot\":{\"entries\":[]},\"extra\":true}}}}",
    )

  let assert Ok(DecodedBatch(
    False,
    _,
    [ContainerMessage(DatastoreAttach("B", attach), 0, _)],
  )) = fluid_container.decode(datastore, None)
  let assert Ok(DecodedBatch(
    False,
    _,
    [ContainerMessage(DatastoreAlias("B", "secondary"), 0, _)],
  )) = fluid_container.decode(alias, None)
  let assert Ok(DecodedBatch(
    False,
    _,
    [
      ContainerMessage(
        ChannelAttach(Route("A", "root"), channel_type, snapshot),
        0,
        _,
      ),
    ],
  )) = fluid_container.decode(channel, None)

  json.to_string(attach)
  |> string.contains("\"extra\":true")
  |> expect.to_be_true()
  channel_type
  |> expect.to_equal("https://graph.microsoft.com/types/map")
  json.to_string(snapshot) |> expect.to_equal("{\"entries\":[]}")
}

pub fn shared_tree_container_rejects_malformed_attach_snapshots_test() -> Nil {
  let snapshots = ["42", "{}", "{\"entries\":\"bad\"}"]
  snapshots
  |> list.each(fn(snapshot) {
    let attach =
      parse(
        "{\"id\":\"B\",\"type\":\"example-store\",\"snapshot\":"
        <> snapshot
        <> "}",
      )
    let datastore =
      parse(
        "{\"type\":\"attach\",\"contents\":" <> json.to_string(attach) <> "}",
      )
    let channel =
      parse(
        "{\"type\":\"component\",\"contents\":{\"address\":\"A\",\"contents\":{\"type\":\"attach\",\"content\":{\"id\":\"root\",\"type\":\"example-channel\",\"snapshot\":"
        <> snapshot
        <> "}}}}",
      )
    let _ = fluid_container.decode(datastore, None) |> expect.to_be_error()
    let _ = fluid_container.decode(channel, None) |> expect.to_be_error()
    let _ =
      fluid_container.encode(DatastoreAttach("B", attach))
      |> expect.to_be_error()
    let _ =
      fluid_container.encode(ChannelAttach(
        Route("A", "root"),
        "example-channel",
        parse(snapshot),
      ))
      |> expect.to_be_error()
    Nil
  })
}

pub fn shared_tree_container_accepts_structural_snapshot_extras_test() -> Nil {
  let snapshot =
    parse(
      "{\"entries\":[{\"path\":\"blob\",\"mode\":\"100644\",\"type\":\"Blob\",\"value\":{\"opaque\":true},\"extra\":true}],\"extra\":true}",
    )
  let datastore =
    parse(
      "{\"type\":\"attach\",\"contents\":{\"id\":\"B\",\"type\":\"example-store\",\"snapshot\":{\"entries\":[{\"path\":\"blob\",\"mode\":\"100644\",\"type\":\"Blob\",\"value\":{\"opaque\":true},\"extra\":true}],\"extra\":true}}}",
    )
  let assert Ok(_) = fluid_container.decode(datastore, None)
  let assert Ok(_) =
    fluid_container.encode(ChannelAttach(
      Route("A", "root"),
      "example-channel",
      snapshot,
    ))
  Nil
}

pub fn shared_tree_container_decodes_allocation_with_existing_codec_test() -> Nil {
  let contents =
    parse(
      "{\"type\":\"idAllocation\",\"contents\":{\"sessionId\":\"11111111-1111-4111-8111-111111111111\",\"ids\":{\"firstGenCount\":1,\"count\":1,\"requestedClusterSize\":512,\"localIdRanges\":[]}}}",
    )
  let assert Ok(DecodedBatch(
    False,
    _,
    [ContainerMessage(IdAllocation(_), 0, _)],
  )) = fluid_container.decode(contents, None)
  Nil
}

pub fn shared_tree_container_preserves_group_boundaries_and_metadata_test() -> Nil {
  let contents =
    parse(
      "{\"type\":\"groupedBatch\",\"contents\":[{\"contents\":{\"type\":\"idAllocation\",\"contents\":{\"sessionId\":\"11111111-1111-4111-8111-111111111111\",\"ids\":{\"firstGenCount\":1,\"count\":1,\"requestedClusterSize\":512,\"localIdRanges\":[]}}},\"metadata\":{\"batch\":true}},{\"contents\":{\"type\":\"component\",\"contents\":{\"address\":\"A\",\"contents\":{\"type\":\"op\",\"content\":{\"address\":\"_C\",\"contents\":{\"revision\":1}}}}},\"metadata\":{\"batch\":false}}],\"extra\":true}",
    )
  let outer = Some(json.object([#("groupedOpCount", json.int(2))]))
  let assert Ok(DecodedBatch(
    True,
    decoded_outer,
    [
      ContainerMessage(IdAllocation(_), 0, Some(first_metadata)),
      ContainerMessage(
        ChannelOperation(Route("A", "_C"), payload),
        1,
        Some(second_metadata),
      ),
    ],
  )) = fluid_container.decode(contents, outer)

  decoded_outer |> expect.to_equal(outer)
  json.to_string(first_metadata) |> expect.to_equal("{\"batch\":true}")
  json.to_string(second_metadata) |> expect.to_equal("{\"batch\":false}")
  json.to_string(payload) |> expect.to_equal("{\"revision\":1}")
}

pub fn shared_tree_container_keeps_empty_group_distinct_test() -> Nil {
  let contents = parse("{\"type\":\"groupedBatch\",\"contents\":[]}")
  let metadata = Some(json.object([#("groupedOpCount", json.int(0))]))
  fluid_container.decode(contents, metadata)
  |> expect.to_equal(Ok(DecodedBatch(True, metadata, [])))
}

pub fn shared_tree_container_rejects_malformed_group_without_prefix_test() -> Nil {
  let contents =
    parse(
      "{\"type\":\"groupedBatch\",\"contents\":[{\"contents\":{\"type\":\"component\",\"contents\":{\"address\":\"A\",\"contents\":{\"type\":\"op\",\"content\":{\"address\":\"root\",\"contents\":{\"ok\":true}}}}}},{\"contents\":{\"type\":\"component\",\"contents\":{\"address\":\"A\",\"contents\":{\"type\":\"op\",\"content\":{\"contents\":{\"bad\":true}}}}}}]}",
    )
  let _ = fluid_container.decode(contents, None) |> expect.to_be_error()
  Nil
}

pub fn shared_tree_container_rejects_malformed_attach_at_group_end_test() -> Nil {
  let contents =
    parse(
      "{\"type\":\"groupedBatch\",\"contents\":[{\"contents\":{\"type\":\"alias\",\"contents\":{\"internalId\":\"B\",\"alias\":\"secondary\"}}},{\"contents\":{\"type\":\"attach\",\"contents\":{\"id\":\"B\",\"type\":\"example-store\",\"snapshot\":42}}}]}",
    )
  let _ = fluid_container.decode(contents, None) |> expect.to_be_error()
  Nil
}

pub fn shared_tree_container_rejects_compression_and_unknown_semantics_test() -> Nil {
  let compressed =
    parse(
      "{\"type\":\"groupedBatch\",\"contents\":[{\"contents\":{\"type\":\"component\",\"contents\":{\"address\":\"A\",\"contents\":{\"type\":\"op\",\"content\":{\"address\":\"root\",\"contents\":{}}}}},\"compression\":\"lz4\"}]}",
    )
  let unknown = parse("{\"type\":\"GC\",\"contents\":{}}")

  fluid_container.decode(compressed, None)
  |> expect.to_equal(Error(fluid_container.UnsupportedCompression("lz4")))
  fluid_container.decode(unknown, None)
  |> expect.to_equal(Error(fluid_container.UnsupportedMessage("GC")))
}

pub fn shared_tree_container_encodes_envelopes_for_upstream_consumers_test() -> Nil {
  let payload =
    json.object([
      #("type", json.string("delete")),
      #("key", json.string("tree")),
    ])
  let assert Ok(encoded) =
    fluid_container.encode(ChannelOperation(Route("A", "root"), payload))
  wire.json_semantically_equal(
    encoded,
    parse(
      "{\"type\":\"component\",\"contents\":{\"address\":\"A\",\"contents\":{\"type\":\"op\",\"content\":{\"address\":\"root\",\"contents\":{\"type\":\"delete\",\"key\":\"tree\"}}}}}",
    ),
  )
  |> expect.to_be_true()

  let attach =
    parse(
      "{\"id\":\"B\",\"type\":\"example-store\",\"snapshot\":{\"entries\":[]},\"extra\":true}",
    )
  let assert Ok(encoded) = fluid_container.encode(DatastoreAttach("B", attach))
  json.to_string(encoded)
  |> string.contains("\"type\":\"attach\"")
  |> expect.to_be_true()
  json.to_string(encoded)
  |> string.contains("\"extra\":true")
  |> expect.to_be_true()

  let _ =
    fluid_container.encode(DatastoreAttach("C", attach))
    |> expect.to_be_error()
  Nil
}

pub fn shared_tree_container_encodes_grouped_batches_with_inner_metadata_test() -> Nil {
  let batch =
    DecodedBatch(True, Some(json.object([#("groupedOpCount", json.int(2))])), [
      ContainerMessage(
        ChannelOperation(Route("A", "root"), json.object([])),
        0,
        Some(json.object([#("batch", json.bool(True))])),
      ),
      ContainerMessage(
        DatastoreAlias("B", "secondary"),
        1,
        Some(json.object([#("batch", json.bool(False))])),
      ),
    ])
  let assert Ok(encoded) = fluid_container.encode_batch(batch)
  let expected =
    parse(
      "{\"type\":\"groupedBatch\",\"contents\":[{\"contents\":{\"type\":\"component\",\"contents\":{\"address\":\"A\",\"contents\":{\"type\":\"op\",\"content\":{\"address\":\"root\",\"contents\":{}}}}},\"metadata\":{\"batch\":true}},{\"contents\":{\"type\":\"alias\",\"contents\":{\"internalId\":\"B\",\"alias\":\"secondary\"}},\"metadata\":{\"batch\":false}}]}",
    )
  wire.json_semantically_equal(encoded, expected) |> expect.to_be_true()
}

pub fn shared_tree_container_requires_complete_ungrouped_batch_test() -> Nil {
  let _ =
    fluid_container.encode_batch(DecodedBatch(False, None, []))
    |> expect.to_be_error()
  let _ =
    fluid_container.encode_batch(
      DecodedBatch(False, None, [
        ContainerMessage(DatastoreAlias("A", "one"), 0, None),
        ContainerMessage(DatastoreAlias("B", "two"), 1, None),
      ]),
    )
    |> expect.to_be_error()
  Nil
}

pub fn shared_tree_container_oracle_test() -> Nil {
  fixtures.assert_case("container-foundations", container_fixture.run)
}

pub fn shared_tree_container_fixture_rejects_wrong_bootstrap_types_test() -> Nil {
  let assert Ok(_) =
    container_fixture.run(
      container_fixture_input(
        "https://graph.microsoft.com/types/map",
        "https://graph.microsoft.com/types/tree",
        "Plain",
        [empty_group_outer()],
      ),
    )
  let mutations = [
    container_fixture_input(
      "wrong-map-type",
      "https://graph.microsoft.com/types/tree",
      "Plain",
      [empty_group_outer()],
    ),
    container_fixture_input(
      "https://graph.microsoft.com/types/map",
      "wrong-tree-type",
      "Plain",
      [empty_group_outer()],
    ),
    container_fixture_input(
      "https://graph.microsoft.com/types/map",
      "https://graph.microsoft.com/types/tree",
      "not-Plain",
      [empty_group_outer()],
    ),
  ]
  mutations
  |> list.each(fn(input) {
    let _ = container_fixture.run(input) |> expect.to_be_error()
    Nil
  })
}

pub fn shared_tree_container_fixture_rejects_extra_grouped_messages_test() -> Nil {
  let extra =
    json.object([
      #("type", json.string("GC")),
      #("contents", json.object([])),
    ])
  let _ =
    container_fixture.run(
      container_fixture_input(
        "https://graph.microsoft.com/types/map",
        "https://graph.microsoft.com/types/tree",
        "Plain",
        [empty_group_outer(), outer_message(extra)],
      ),
    )
    |> expect.to_be_error()
  Nil
}

fn container_fixture_input(
  map_type: String,
  tree_type: String,
  value_type: String,
  grouped_messages: List(Json),
) -> Json {
  let map_header =
    json.object([
      #(
        "content",
        json.object([
          #(
            "tree",
            json.object([
              #("type", json.string(value_type)),
              #(
                "value",
                json.object([
                  #("type", json.string("__fluid_handle__")),
                  #("url", json.string("/A/_C")),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    ])
  let map_attributes = attributes(map_type, "0.2")
  let tree_attributes = attributes(tree_type, "0.0.0")
  json.object([
    #(
      "initialSnapshot",
      fixture_snapshot(map_header, map_attributes, tree_attributes),
    ),
    #("bootstrapMessages", json.array([], fn(value) { value })),
    #("groupedWireMessages", json.array(grouped_messages, fn(value) { value })),
    #("decodeCases", json.array([], fn(value) { value })),
    #("handleCases", json.array([], fn(value) { value })),
    #("encodeCases", json.array([], fn(value) { value })),
  ])
}

fn fixture_snapshot(
  map_header: Json,
  map_attributes: Json,
  tree_attributes: Json,
) -> Json {
  parse(
    "{\"tree\":{\"trees\":{\".channels\":{\"trees\":{\"A\":{\"trees\":{\".channels\":{\"trees\":{\"root\":{\"blobs\":{\"header\":\"header\",\".attributes\":\"map\"}},\"_C\":{\"blobs\":{\".attributes\":\"tree\"}}}}}}}}}},\"blobs\":{\"header\":\""
    <> encoded_blob(map_header)
    <> "\",\"map\":\""
    <> encoded_blob(map_attributes)
    <> "\",\"tree\":\""
    <> encoded_blob(tree_attributes)
    <> "\"}}",
  )
}

fn attributes(channel_type: String, format: String) -> Json {
  json.object([
    #("type", json.string(channel_type)),
    #("snapshotFormatVersion", json.string(format)),
    #("packageVersion", json.string("3.1.0")),
  ])
}

fn encoded_blob(value: Json) -> String {
  bit_array.base64_encode(<<json.to_string(value):utf8>>, True)
}

fn empty_group_outer() -> Json {
  outer_message(
    json.object([
      #("type", json.string("groupedBatch")),
      #("contents", json.array([], fn(value) { value })),
    ]),
  )
}

fn outer_message(contents: Json) -> Json {
  json.object([
    #("clientId", json.string("client")),
    #("clientSequenceNumber", json.int(1)),
    #("minimumSequenceNumber", json.int(0)),
    #("referenceSequenceNumber", json.int(0)),
    #("sequenceNumber", json.int(1)),
    #("contents", json.string(json.to_string(contents))),
  ])
}
