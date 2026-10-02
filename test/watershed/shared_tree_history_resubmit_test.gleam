import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import spillway/types as spillway_types
import startest/expect
import watershed/channel
import watershed/fluid_ids
import watershed/json_ot.{type JsonValue, VArray, VObject, VString}
import watershed/runtime_core
import watershed/tree/change
import watershed/tree/fixtures
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/identifier_fixture
import watershed/tree/runtime_fixture
import watershed/tree/schema
import watershed/tree/shared_change
import watershed/tree/types.{
  ArrayInsert, NumberValue, ObjectValue, SetField, StringValue,
}
import watershed/tree_kernel
import watershed/wire
import watershed/wire/fluid_container

const tree_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"Point\":{\"kind\":{\"object\":{\"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]},\"y\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]}}}},\"Root\":{\"kind\":{\"object\":{\"point\":{\"kind\":\"Value\",\"types\":[\"Point\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}"

const title_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"Root\":{\"kind\":{\"object\":{\"title\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}"

const title_score_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"Root\":{\"kind\":{\"object\":{\"score\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.number\"]},\"title\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}"

fn session() -> fluid_ids.SessionId {
  let assert Ok(value) =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000001")
  value
}

fn revision(suffix: String) -> fluid_ids.StableId {
  let assert Ok(value) =
    fluid_ids.stable_id("00000000-0000-4000-8000-0000000000" <> suffix)
  value
}

fn commit(revision: fluid_ids.StableId) -> history.Commit {
  let assert Ok(order) = change.identity_order([#(revision, -1)])
  let assert Ok(checked) =
    change.from_data(change.to_data(change.empty()), order)
  history.Commit(revision, session(), shared_change.from_data(checked))
}

fn scalar_commit(commit_revision: fluid_ids.StableId) -> history.Commit {
  let assert Ok(stored) = schema.stored_from_string(tree_schema)
  let view = revision("99")
  let root =
    ObjectValue("Root", [
      #(
        "point",
        ObjectValue("Point", [
          #("x", NumberValue(1.0)),
          #("y", NumberValue(2.0)),
        ]),
      ),
    ])
  let assert Ok(state) = forest.new(view, stored, Some(root))
  let assert Ok(order) = change.identity_order([#(commit_revision, -1)])
  let assert Ok(authored) =
    change.edit(
      stored,
      state,
      commit_revision,
      SetField(["point", "x"], NumberValue(11.0)),
      order,
    )
  history.Commit(commit_revision, session(), shared_change.from_data(authored))
}

fn mixed_run_scalar_commit(
  commit_revision: fluid_ids.StableId,
) -> history.Commit {
  let history.Commit(_, _, change) = scalar_commit(commit_revision)
  let assert [shared_change.DataChange(authored)] =
    shared_change.to_changes(change)
  let data = change.to_data(authored)
  let assert Ok(order) = change.identity_order([#(commit_revision, -1)])
  let assert Ok(build) =
    change.from_data(
      change.ChangeData(
        ..data,
        fields: [],
        nodes: [],
        parents: [],
        aliases: [],
        destroys: [],
        refreshers: [],
      ),
      order,
    )
  let assert Ok(attach) =
    change.from_data(change.ChangeData(..data, builds: []), order)
  let assert Ok(outer) =
    shared_change.from_changes([
      shared_change.DataChange(build),
      shared_change.SchemaChange(schema.EmptySchema, schema.EmptySchema, False),
      shared_change.DataChange(attach),
    ])
  history.Commit(commit_revision, session(), outer)
}

fn title_state() -> tree_kernel.TreeState {
  let assert Ok(stored) = schema.stored_from_string(title_schema)
  let assert Ok(view) = schema.view_from_string(title_schema)
  let assert Ok(view_id) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000099")
  let initial = history.inspect(history.new(session())).sequenced
  let assert Ok(snapshot) =
    tree_kernel.snapshot_from_parts(
      view_id,
      stored,
      forest.ForestData(
        Some(ObjectValue("Root", [#("title", StringValue("before"))])),
        [],
        0,
      ),
      initial,
    )
  let assert Ok(state) = tree_kernel.restore(snapshot, view_id, session(), view)
  state
}

fn identifier_core(client_id: String, session_id: String) -> runtime_core.Core {
  let input =
    identifier_fixture.full_seed_input(
      identifier_fixture.full_root(
        identifier_fixture.point("child", "child"),
        [identifier_fixture.point("existing", "existing")],
        [],
        [],
      ),
    )
  let assert Some(compressor) = input.compressor
  let assert Ok(serialized) = fluid_ids.serialize(compressor, False)
  let assert Ok(local_session) = fluid_ids.session_id(session_id)
  let assert Ok(compressor) = fluid_ids.deserialize(serialized, local_session)
  let assert Ok(seed) =
    runtime_core.bootstrap_seed(
      runtime_core.BootstrapSeedInput(..input, compressor: Some(compressor)),
    )
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap_seeded(
      runtime_fixture.connected(client_id, [], 0),
      seed,
    )
  core
}

fn sequenced(
  outbound: wire.OutboundOperation,
  client_id: String,
  sequence_number: Int,
) -> spillway_types.SequencedDocumentMessage {
  let assert Ok(contents) =
    json.parse(json.to_string(outbound.contents), decode.dynamic)
  let metadata = case outbound.metadata {
    None -> None
    Some(value) -> {
      let assert Ok(value) = json.parse(json.to_string(value), decode.dynamic)
      Some(value)
    }
  }
  spillway_types.SequencedDocumentMessage(
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
    timestamp: 0,
    data: None,
  )
}

pub fn pending_multi_edit_transaction_resubmits_once_test() {
  let core = identifier_core("writer", "30000000-0000-4000-8000-000000000003")
  let address = "A/_C"
  let view = identifier_fixture.full_view()
  let assert Ok(active) =
    runtime_core.begin_tree_transaction(core, address, view, [])
  let assert Ok(#(active, [], [])) =
    runtime_core.submit_tree_edits_view(active, address, view, [
      ArrayInsert(["left"], 1, [
        ObjectValue(identifier_fixture.point_type, [
          #("label", StringValue("pending")),
        ]),
      ]),
      SetField(["left", "1", "label"], StringValue("pending-final")),
    ])
  let assert Ok(#(pending, local_events, [outbound])) =
    runtime_core.commit_tree_transaction(active, address)
  local_events
  |> expect.to_equal([
    #(address, channel.TreeEvent(tree_kernel.TreeChanged(True))),
  ])
  let assert Ok(channel.TreeState(pending_tree)) =
    dict.get(pending.channels, address)
  let assert Ok(reference) =
    tree_kernel.reference_at(pending_tree, ["left", "1"])
  let assert Ok(identifier) =
    tree_kernel.read(pending_tree, ["left", "1", "id"])
  let assert [pending_commit] = tree_kernel.history_view(pending_tree).pending

  let assert Ok(reconnected) =
    runtime_core.adopt_reconnect(
      pending,
      runtime_fixture.connected("rejoined", [], 0),
    )
  let assert Ok(#(resubmitted, [resent])) =
    runtime_core.resubmit(runtime_core.go_live(reconnected))
  let assert Ok(batch) =
    fluid_container.decode(resent.contents, resent.metadata)
  batch.messages
  |> list.count(fn(message) {
    case message.kind {
      fluid_container.ChannelOperation(_, _) -> True
      _ -> False
    }
  })
  |> expect.to_equal(1)
  let assert [runtime_core.InFlightBatch(pending: [], ..)] =
    resubmitted.in_flight

  let acknowledgement = sequenced(resent, "rejoined", 1)
  let assert Ok(#(acknowledged, received)) =
    runtime_core.handle_sequenced(resubmitted, acknowledgement)
  received.events |> expect.to_equal([])
  acknowledged.in_flight |> expect.to_equal([])
  let assert Ok(channel.TreeState(acknowledged_tree)) =
    dict.get(acknowledged.channels, address)
  tree_kernel.history_view(acknowledged_tree).pending |> expect.to_equal([])
  let assert [sequenced_commit] =
    tree_kernel.history_view(acknowledged_tree).sequenced.trunk
  sequenced_commit.commit.revision |> expect.to_equal(pending_commit.revision)
  tree_kernel.reference_at(acknowledged_tree, ["left", "1"])
  |> expect.to_equal(Ok(reference))
  tree_kernel.read(acknowledged_tree, ["left", "1", "id"])
  |> expect.to_equal(Ok(identifier))
  tree_kernel.read(acknowledged_tree, ["left", "1", "label"])
  |> expect.to_equal(Ok(Some(StringValue("pending-final"))))

  let assert Ok(#(duplicate, ignored)) =
    runtime_core.handle_sequenced(acknowledged, acknowledgement)
  ignored.events |> expect.to_equal([])
  duplicate.channels |> expect.to_equal(acknowledged.channels)
  tree_kernel.history_view(acknowledged_tree).sequenced.trunk
  |> list.length
  |> expect.to_equal(1)
  resent.client_sequence_number
  |> expect.to_equal(outbound.client_sequence_number + 1)
}

pub fn accepted_transaction_before_drop_deduplicates_by_revision_test() {
  let writer = identifier_core("writer", "30000000-0000-4000-8000-000000000003")
  let service =
    identifier_core("service", "50000000-0000-4000-8000-000000000005")
  let address = "A/_C"
  let view = identifier_fixture.full_view()
  let assert Ok(active) =
    runtime_core.begin_tree_transaction(writer, address, view, [])
  let assert Ok(#(active, [], [])) =
    runtime_core.submit_tree_edits_view(active, address, view, [
      ArrayInsert(["left"], 1, [
        ObjectValue(identifier_fixture.point_type, [
          #("label", StringValue("accepted")),
        ]),
      ]),
      SetField(["left", "1", "label"], StringValue("accepted-final")),
    ])
  let assert Ok(#(pending, local_events, [outbound])) =
    runtime_core.commit_tree_transaction(active, address)
  local_events
  |> expect.to_equal([
    #(address, channel.TreeEvent(tree_kernel.TreeChanged(True))),
  ])
  let assert Ok(channel.TreeState(pending_tree)) =
    dict.get(pending.channels, address)
  let assert [pending_commit] = tree_kernel.history_view(pending_tree).pending
  let assert Ok(pending_reference) =
    tree_kernel.reference_at(pending_tree, ["left", "1"])
  let assert Ok(pending_identifier) =
    tree_kernel.read(pending_tree, ["left", "1", "id"])

  let accepted = sequenced(outbound, pending.client_id, 1)
  let assert Ok(#(service, delivered)) =
    runtime_core.handle_sequenced(service, accepted)
  delivered.events
  |> expect.to_equal([
    #(address, channel.TreeEvent(tree_kernel.TreeChanged(False))),
  ])
  let assert Ok(channel.TreeState(service_tree)) =
    dict.get(service.channels, address)
  let assert Ok(reference) =
    tree_kernel.reference_at(service_tree, ["left", "1"])
  let assert Ok(identifier) =
    tree_kernel.read(service_tree, ["left", "1", "id"])
  let assert [service_commit] =
    tree_kernel.history_view(service_tree).sequenced.trunk
  service_commit.commit.revision |> expect.to_equal(pending_commit.revision)

  let assert Ok(reconnected) =
    runtime_core.adopt_reconnect(
      pending,
      runtime_fixture.connected("rejoined", [], 1),
    )
  let assert Ok(#(caught_up, acknowledged)) =
    runtime_core.handle_sequenced(reconnected, accepted)
  acknowledged.events |> expect.to_equal([])
  let assert Ok(#(ready, [])) =
    runtime_core.resubmit(runtime_core.go_live(caught_up))
  ready.in_flight |> expect.to_equal([])
  let assert Ok(channel.TreeState(ready_tree)) =
    dict.get(ready.channels, address)
  tree_kernel.history_view(ready_tree).pending |> expect.to_equal([])
  let assert [ready_commit] =
    tree_kernel.history_view(ready_tree).sequenced.trunk
  ready_commit.commit.revision |> expect.to_equal(pending_commit.revision)
  tree_kernel.reference_at(ready_tree, ["left", "1"])
  |> expect.to_equal(Ok(pending_reference))
  tree_kernel.read(ready_tree, ["left", "1", "id"])
  |> expect.to_equal(Ok(pending_identifier))

  tree_kernel.history_view(service_tree).sequenced.trunk
  |> list.length
  |> expect.to_equal(1)
  tree_kernel.reference_at(service_tree, ["left", "1"])
  |> expect.to_equal(Ok(reference))
  tree_kernel.read(service_tree, ["left", "1", "id"])
  |> expect.to_equal(Ok(identifier))
  tree_kernel.read(service_tree, ["left", "1", "label"])
  |> expect.to_equal(Ok(Some(StringValue("accepted-final"))))
  tree_kernel.array_values(service_tree, ["left"])
  |> expect.to_be_ok()
  |> list.length
  |> expect.to_equal(2)
}

pub fn identifier_retry_acknowledges_once_without_changing_id_test() {
  let retry = identifier_observation("retry-resubmit")
  let assert Ok(identifier) = list.key_find(retry, "identifier")
  list.key_find(retry, "acceptedIdentifier")
  |> expect.to_equal(Ok(identifier))
  list.key_find(retry, "peerObserved")
  |> expect.to_equal(Ok(json_ot.VBool(True)))
  list.key_find(retry, "pendingAfterAck")
  |> expect.to_equal(Ok(json_ot.VNumber(json_ot.NInt(0))))
}

pub fn shared_tree_history_resubmit_rejects_duplicate_repairs_test() -> Nil {
  let pending = commit(revision("01"))
  let assert Ok(local) = history.append_local(history.new(session()), pending)
  history.resubmit(local.history, [
    #(pending.revision, []),
    #(pending.revision, []),
  ])
  |> expect.to_be_error
  history.pending(local.history) |> expect.to_equal([pending])
}

pub fn shared_tree_history_resubmit_rejects_extraneous_commit_test() -> Nil {
  let pending = commit(revision("01"))
  let assert Ok(local) = history.append_local(history.new(session()), pending)
  history.resubmit(local.history, [#(revision("02"), [])])
  |> expect.to_be_error
  history.pending(local.history) |> expect.to_equal([pending])
}

pub fn shared_tree_history_resubmits_own_scalar_build_without_repair_test() -> Nil {
  let pending = scalar_commit(revision("01"))
  let assert Ok(local) = history.append_local(history.new(session()), pending)
  history.resubmit(local.history, []) |> expect.to_equal(Ok([pending]))
}

pub fn shared_tree_history_resubmits_prior_run_build_without_repair_test() -> Nil {
  let pending = mixed_run_scalar_commit(revision("01"))
  let assert Ok(local) = history.append_local(history.new(session()), pending)
  history.resubmit(local.history, []) |> expect.to_equal(Ok([pending]))
}

pub fn shared_tree_history_resubmit_reuses_root_detached_before_schema_test() {
  let state = title_state()
  let assert Ok(before) = schema.stored_from_string(title_schema)
  let assert Ok(after) = schema.stored_from_string(title_score_schema)
  let outer_revision = revision("01")
  let inverse_revision = revision("02")
  let assert Ok(order) =
    change.identity_order([
      #(outer_revision, -2),
      #(inverse_revision, -1),
    ])
  let assert Ok(base) =
    forest.new(
      revision("99"),
      before,
      Some(ObjectValue("Root", [#("title", StringValue("before"))])),
    )
  let assert Ok(replace) =
    change.edit(
      before,
      base,
      outer_revision,
      SetField(["title"], StringValue("temporary")),
      order,
    )
  let assert Ok(restore) =
    change.invert(
      change.TaggedChange(Some(outer_revision), None, replace),
      False,
      inverse_revision,
    )
  let assert Ok(outer) =
    shared_change.from_changes([
      shared_change.DataChange(replace),
      shared_change.SchemaChange(
        schema.FixedSchema(before),
        schema.FixedSchema(after),
        False,
      ),
      shared_change.DataChange(restore),
    ])
  let assert Ok(#(pending, _, _)) =
    tree_kernel.apply_local_change(state, outer_revision, order, outer)
  let assert Ok([rebuilt]) = tree_kernel.resubmit_commits(pending)
  let assert [
    shared_change.DataChange(_),
    shared_change.SchemaChange(_, _, _),
    shared_change.DataChange(restored),
  ] = shared_change.to_changes(rebuilt.change)

  change.to_data(restored).refreshers |> expect.to_equal([])
  tree_kernel.read(pending, ["title"])
  |> expect.to_equal(Ok(Some(StringValue("before"))))
}

pub fn shared_tree_history_resubmits_schema_only_commit_test() -> Nil {
  let assert Ok(before) = schema.stored_from_string(tree_schema)
  let after =
    tree_schema
    |> string.replace(
      "\"root\":{\"kind\":\"Value\"",
      "\"root\":{\"kind\":\"Optional\"",
    )
    |> schema.stored_from_string
    |> expect.to_be_ok
  let assert Ok(outer) =
    shared_change.from_changes([
      shared_change.SchemaChange(
        schema.FixedSchema(before),
        schema.FixedSchema(after),
        False,
      ),
    ])
  let pending = history.Commit(revision("01"), session(), outer)
  let assert Ok(local) = history.append_local(history.new(session()), pending)

  history.resubmit(local.history, [#(pending.revision, [])])
  |> expect.to_equal(Ok([pending]))
}

pub fn shared_tree_history_resubmits_empty_conflict_commit_test() -> Nil {
  let pending = history.Commit(revision("01"), session(), shared_change.empty())
  let assert Ok(local) = history.append_local(history.new(session()), pending)

  history.resubmit(local.history, [#(pending.revision, [])])
  |> expect.to_equal(Ok([pending]))
}

fn identifier_observation(id: String) -> List(#(String, JsonValue)) {
  let assert Ok(fixture) = fixtures.load("identifier-persistence")
  let output = case identifier_fixture.run(fixture.input) {
    Ok(value) -> value
    Error(error) -> panic as { error }
  }
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(output))
  let assert Ok(VArray(observations)) = list.key_find(root, "observations")
  let assert Ok(VObject(observation)) =
    list.find(observations, fn(value) {
      case value {
        VObject(fields) -> list.key_find(fields, "id") == Ok(VString(id))
        _ -> False
      }
    })
  observation
}
