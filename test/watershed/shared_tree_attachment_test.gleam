import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import spillway/types
import startest/expect
import watershed/channel
import watershed/fluid_ids
import watershed/handle
import watershed/runtime_core
import watershed/tree/fixtures
import watershed/tree/lifecycle_fixture
import watershed/tree/runtime_fixture
import watershed/wire
import watershed/wire/fluid_container
import watershed/wire/op as wire_op

pub fn shared_tree_live_channel_attachment_test() {
  fixtures.assert_case("live-channel-attachment", lifecycle_fixture.run_case(
    "live-channel-attachment",
    _,
  ))
}

pub fn shared_tree_cross_datastore_tree_attachment_test() {
  fixtures.assert_case("cross-datastore-attachment", lifecycle_fixture.run_case(
    "cross-datastore-attachment",
    _,
  ))
}

pub fn shared_tree_cross_datastore_map_attachment_test() {
  lifecycle_fixture.assert_scenario(
    "cross-datastore-attachment",
    "map-cross-datastore",
  )
}

pub fn shared_tree_cross_datastore_map_cycle_test() {
  lifecycle_fixture.assert_scenario("cross-datastore-attachment", "map-cycle")
}

pub fn shared_tree_attachment_evidence_rejects_changed_snapshot_bytes_test() {
  lifecycle_fixture.assert_scenario_rejects_evidence_mutation(
    "cross-datastore-attachment",
    "map-cross-datastore",
    lifecycle_fixture.SnapshotBytes,
  )
}

pub fn shared_tree_attachment_evidence_rejects_changed_route_test() {
  lifecycle_fixture.assert_scenario_rejects_evidence_mutation(
    "cross-datastore-attachment",
    "map-cross-datastore",
    lifecycle_fixture.Route,
  )
}

pub fn shared_tree_attachment_evidence_rejects_changed_order_test() {
  lifecycle_fixture.assert_scenario_rejects_evidence_mutation(
    "cross-datastore-attachment",
    "map-cross-datastore",
    lifecycle_fixture.Order,
  )
}

pub fn shared_tree_attachment_evidence_rejects_changed_allocation_test() {
  lifecycle_fixture.assert_scenario_rejects_evidence_mutation(
    "cross-datastore-attachment",
    "map-cross-datastore",
    lifecycle_fixture.Allocation,
  )
}

pub fn shared_tree_attachment_evidence_rejects_changed_csn_test() {
  lifecycle_fixture.assert_scenario_rejects_evidence_mutation(
    "cross-datastore-attachment",
    "map-cross-datastore",
    lifecycle_fixture.ClientSequenceNumber,
  )
}

pub fn shared_tree_attachment_evidence_rejects_changed_group_metadata_test() {
  lifecycle_fixture.assert_scenario_rejects_evidence_mutation(
    "cross-datastore-attachment",
    "map-cross-datastore",
    lifecycle_fixture.GroupMetadata,
  )
}

pub fn shared_tree_attachment_refuses_unknown_final_dependency_atomically_test() {
  let core = attachment_core()
  let assert Ok(core) = runtime_core.create_detached_data_store(core, "D")
  let before = fingerprint(core)
  let assert Ok(valid) = handle.reference_from_path("/D/root")
  let assert Ok(missing) = handle.reference_from_path("/missing/root")

  let assert Error(_) =
    runtime_core.prepare_attachments(core, "A/root", [valid, missing])
  fingerprint(core) |> expect.to_equal(before)
}

pub fn shared_tree_attachment_refuses_malformed_last_marker_atomically_test() {
  let core = attachment_core()
  let assert Ok(core) = runtime_core.create_detached_data_store(core, "D")
  let before = fingerprint(core)
  let value =
    json.object([
      #("valid", handle.encode_handle("D/root")),
      #(
        "late",
        json.object([
          #("type", json.string("__fluid_handle__")),
          #("url", json.int(1)),
        ]),
      ),
    ])

  let assert Error(_) = runtime_core.set(core, "A/root", "bad", value)
  fingerprint(core) |> expect.to_equal(before)
}

pub fn shared_tree_attachment_refuses_nested_malformed_dependency_atomically_test() {
  let core = attachment_core()
  let assert Ok(core) = runtime_core.create_detached_data_store(core, "D")
  let assert Ok(core) = runtime_core.create_detached_data_store(core, "F")
  let malformed =
    json.object([
      #("valid", handle.encode_handle("F/root")),
      #(
        "late",
        json.object([
          #("type", json.string("__fluid_handle__")),
          #("url", json.int(1)),
        ]),
      ),
    ])
  let assert Ok(#(core, _, [])) =
    runtime_core.set(core, "D/root", "nested", malformed)
  let before = fingerprint(core)

  let assert Error(runtime_core.ContainerOperationFailed(fluid_container.InvalidRoute(
    "handle dependencies",
    _,
  ))) =
    runtime_core.set(
      core,
      "A/root",
      "published",
      handle.encode_handle("D/root"),
    )
  fingerprint(core) |> expect.to_equal(before)
  dict.has_key(core.detached, "F/root") |> expect.to_be_true()
}

pub fn shared_tree_attachment_refuses_duplicate_identities_atomically_test() {
  let core = attachment_core()
  let assert Ok(core) = runtime_core.create_detached_data_store(core, "D")
  let before = fingerprint(core)

  let assert Error(_) = runtime_core.create_detached_data_store(core, "D")
  let assert Error(_) = runtime_core.new_channel_address_in(core, "D", "root")
  let assert Error(_) = runtime_core.new_channel_address_in(core, "A", "root")
  fingerprint(core) |> expect.to_equal(before)
}

pub fn shared_tree_attachment_refuses_unsupported_package_identity_test() {
  wire_op.encode_datastore_attach(
    "D",
    ["unsupported"],
    [#("root", channel.MapSnapshot([]))],
    [],
  )
  |> expect.to_equal(
    Error(fluid_container.UnsupportedMessage(
      "unsupported declared datastore package",
    )),
  )
}

pub fn shared_tree_attachment_scopes_new_channel_addresses_test() {
  let core = attachment_core()
  let assert Ok(core) = runtime_core.create_detached_data_store(core, "D")
  runtime_core.new_channel_address_in(core, "D", "child")
  |> expect.to_equal(Ok("D/child"))
  let assert Error(_) =
    runtime_core.new_channel_address_in(core, "missing", "child")
  Nil
}

pub fn shared_tree_attachment_reconnect_resubmits_prepared_graph_test() {
  let core = attachment_core()
  let assert Ok(core) = runtime_core.create_detached_data_store(core, "D")
  let assert Ok(#(core, _, [original])) =
    runtime_core.set(
      core,
      "A/root",
      "secondary",
      handle.encode_handle("D/root"),
    )
  let original_client_id = core.client_id
  let assert Ok(core) =
    runtime_core.adopt_reconnect(
      core,
      runtime_fixture.connected(
        "reconnected",
        [],
        core.last_seen_sequence_number,
      ),
    )
  let resubmit_csn = core.next_client_sequence_number
  let assert Ok(#(core, [outbound])) = runtime_core.resubmit(core)
  let assert Ok(batch) =
    fluid_container.decode(outbound.contents, outbound.metadata)
  list.length(batch.messages) |> expect.to_equal(3)
  list.length(core.in_flight) |> expect.to_equal(1)
  outbound.client_sequence_number
  |> expect.to_equal(resubmit_csn)
  outbound.reference_sequence_number
  |> expect.to_equal(original.reference_sequence_number)
  outbound.operation_type |> expect.to_equal(original.operation_type)
  let old_batch_id =
    original_client_id
    <> "_["
    <> int.to_string(original.client_sequence_number)
    <> "]"
  let new_batch_id =
    core.client_id
    <> "_["
    <> int.to_string(outbound.client_sequence_number)
    <> "]"
  json.to_string(original.contents)
  |> string.replace(old_batch_id, new_batch_id)
  |> expect.to_equal(json.to_string(outbound.contents))
  let assert Some(original_metadata) = original.metadata
  let assert Some(outbound_metadata) = outbound.metadata
  json.to_string(original_metadata)
  |> string.replace(old_batch_id, new_batch_id)
  |> expect.to_equal(json.to_string(outbound_metadata))
  let assert Ok(#(core, _)) =
    runtime_core.handle_sequenced(core, sequenced(outbound, core.client_id, 3))
  core.in_flight |> expect.to_equal([])
  let assert Ok(value) = runtime_core.get(core, "A/root", "secondary")
  runtime_core.resolve_handle_address(core, value)
  |> expect.to_equal(Ok("D/root"))
}

pub fn shared_tree_attachment_published_store_child_attaches_before_reference_test() {
  let writer =
    runtime_fixture.routed_core_for(
      "writer",
      "30000000-0000-4000-8000-000000000003",
    )
    |> expect.to_be_ok()
  let receiver =
    runtime_fixture.routed_core_for(
      "receiver",
      "40000000-0000-4000-8000-000000000004",
    )
    |> expect.to_be_ok()
  let assert Ok(writer) = runtime_core.create_detached_data_store(writer, "D")
  let #(writer, _, published) =
    runtime_core.set(writer, "A/root", "store", handle.encode_handle("D/root"))
    |> expect.to_be_ok()
  list.length(published) |> expect.to_equal(1)
  let assert [publish] = published
  let published = sequenced(publish, writer.client_id, 3)
  let #(writer, _) =
    runtime_core.handle_sequenced(writer, published) |> expect.to_be_ok()
  let #(receiver, _) =
    runtime_core.handle_sequenced(receiver, published) |> expect.to_be_ok()
  let assert Ok(writer) =
    runtime_core.create_detached(writer, "D/child", channel.InitMap)
  let #(writer, _, referenced) =
    runtime_core.set(writer, "A/root", "child", handle.encode_handle("D/child"))
    |> expect.to_be_ok()
  let assert [attach, reference] = referenced
  let assert Ok(attach_batch) =
    fluid_container.decode(attach.contents, attach.metadata)
  let assert [
    fluid_container.ContainerMessage(
      fluid_container.ChannelAttach(fluid_container.Route("D", "child"), _, _),
      0,
      _,
    ),
  ] = attach_batch.messages
  let assert Ok(reference_batch) =
    fluid_container.decode(reference.contents, reference.metadata)
  let assert [
    fluid_container.ContainerMessage(
      fluid_container.ChannelOperation(fluid_container.Route("A", "root"), _),
      0,
      _,
    ),
  ] = reference_batch.messages
  let #(receiver, _) =
    runtime_core.handle_sequenced(
      receiver,
      sequenced(attach, writer.client_id, 4),
    )
    |> expect.to_be_ok()
  let #(receiver, _) =
    runtime_core.handle_sequenced(
      receiver,
      sequenced(reference, writer.client_id, 5),
    )
    |> expect.to_be_ok()
  let assert Ok(value) = runtime_core.get(receiver, "A/root", "child")
  runtime_core.resolve_handle_address(receiver, value)
  |> expect.to_equal(Ok("D/child"))
  runtime_core.has_channel(writer, "D/child") |> expect.to_be_true()
}

pub fn shared_tree_attachment_retains_serialized_removed_binding_test() {
  let core = attachment_core()
  let assert Ok(core) = runtime_core.create_detached_data_store(core, "D")
  let assert Ok(core) = runtime_core.create_detached_data_store(core, "F")
  let assert Ok(#(core, _, [])) =
    runtime_core.set(core, "D/root", "right", handle.encode_handle("F/root"))
  let assert Ok(#(core, _, [_])) =
    runtime_core.set(core, "A/root", "left", handle.encode_handle("D/root"))
  let assert Ok(#(core, _, [_])) = runtime_core.delete(core, "D/root", "right")
  runtime_core.entries(core, "D/root") |> expect.to_equal([])
  runtime_core.has_channel(core, "F/root") |> expect.to_be_true()
  let assert Ok(references) = dict.get(core.bindings, "D/root")
  list.map(references, handle.reference_path)
  |> expect.to_equal(["/F/root"])
}

type Fingerprint {
  Fingerprint(
    next_csn: Int,
    in_flight: Int,
    channels: List(String),
    detached: List(String),
    datastores: List(String),
    local_datastores: List(String),
    compressor: String,
  )
}

fn attachment_core() -> runtime_core.Core {
  runtime_fixture.routed_core() |> expect.to_be_ok()
}

fn fingerprint(core: runtime_core.Core) -> Fingerprint {
  let compressor = case core.compressor {
    Some(compressor) ->
      fluid_ids.serialize(compressor, True)
      |> result.map(json.to_string)
      |> result.unwrap("")
    None -> ""
  }
  Fingerprint(
    core.next_client_sequence_number,
    list.length(core.in_flight),
    dict.keys(core.channels) |> list.sort(string.compare),
    dict.keys(core.detached) |> list.sort(string.compare),
    dict.keys(core.routing.datastores) |> list.sort(string.compare),
    dict.keys(core.local_datastores) |> list.sort(string.compare),
    compressor,
  )
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
