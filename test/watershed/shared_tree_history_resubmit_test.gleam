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
  type TreeCommitKind, DefaultCommit, NumberValue, ObjectValue, RedoCommit,
  SetField, StringValue, UndoCommit,
}
import watershed/tree_kernel
import watershed/wire

@target(erlang)
import watershed/shared_tree_runtime_beam_test as native_runtime
@target(javascript)
import watershed/shared_tree_runtime_js_test as native_runtime

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

pub fn pending_multi_edit_transaction_resubmits_once_test() {
  native_runtime.assert_pending_multi_edit_transaction_resubmit()
}

pub fn accepted_transaction_before_drop_deduplicates_by_revision_test() {
  native_runtime.assert_accepted_transaction_before_drop()
}

pub fn accepted_before_drop_settles_pending_revision_once_in_runtime_core_test() {
  let core = runtime_fixture.routed_core() |> expect.to_be_ok
  let address = "A/_C"
  let #(pending, events, outbound) =
    runtime_core.submit_tree_edits(core, address, [
      SetField(["title"], StringValue("accepted")),
    ])
    |> expect.to_be_ok
  let revision = applied_commit(events).0
  let outbound = list.first(outbound) |> expect.to_be_ok
  let accepted_message = sequenced(pending, outbound, 3)
  let reconnected =
    runtime_core.adopt_reconnect(
      pending,
      runtime_fixture.connected("rejoined", [], 3),
    )
    |> expect.to_be_ok
  let #(accepted, first) =
    runtime_core.handle_sequenced(reconnected, accepted_message)
    |> expect.to_be_ok

  first.events
  |> list.filter(fn(event) {
    case event.1 {
      channel.TreeCommitSettled(settled, _) -> settled == revision
      _ -> False
    }
  })
  |> list.length
  |> expect.to_equal(1)
  let #(ready, resubmitted) =
    runtime_core.resubmit(runtime_core.go_live(accepted))
    |> expect.to_be_ok
  resubmitted |> expect.to_equal([])
  let #(_, duplicate) =
    runtime_core.handle_sequenced(ready, accepted_message)
    |> expect.to_be_ok
  duplicate.events
  |> list.filter(fn(event) {
    case event.1 {
      channel.TreeCommitSettled(settled, _) -> settled == revision
      _ -> False
    }
  })
  |> expect.to_equal([])
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

pub fn retained_revertible_survives_runtime_reconnect_test() {
  let core = runtime_fixture.routed_core() |> expect.to_be_ok
  let address = "A/_C"
  let #(pending, events, outbound) =
    runtime_core.submit_tree_edits(core, address, [
      SetField(["title"], StringValue("after")),
    ])
    |> expect.to_be_ok
  let revision = applied_commit(events).0
  let outbound = list.first(outbound) |> expect.to_be_ok
  let #(settled, _) =
    runtime_core.handle_sequenced(pending, sequenced(pending, outbound, 3))
    |> expect.to_be_ok
  let #(retained, id) =
    runtime_core.retain_tree_revertible(
      settled,
      address,
      revision,
      DefaultCommit,
    )
    |> expect.to_be_ok
  let reconnected =
    runtime_core.adopt_reconnect(
      retained,
      runtime_fixture.connected("rejoined", [], 3),
    )
    |> expect.to_be_ok

  runtime_core.tree_revertible_is_valid(reconnected, address, id)
  |> expect.to_be_true
}

pub fn pending_undo_resubmit_keeps_revision_kind_and_settles_once_test() {
  let core = runtime_fixture.routed_core() |> expect.to_be_ok
  let address = "A/_C"
  let #(edited, edit_events, _) =
    runtime_core.submit_tree_edits(core, address, [
      SetField(["title"], StringValue("after")),
    ])
    |> expect.to_be_ok
  let original_revision = applied_commit(edit_events).0
  let #(retained, original) =
    runtime_core.retain_tree_revertible(
      edited,
      address,
      original_revision,
      DefaultCommit,
    )
    |> expect.to_be_ok
  let #(undone, undo_events, _) =
    runtime_core.revert_tree(retained, address, original) |> expect.to_be_ok
  let #(undo_revision, undo_kind) = applied_commit(undo_events)
  undo_kind |> expect.to_equal(UndoCommit)
  let #(undone, undo) =
    runtime_core.retain_tree_revertible(
      undone,
      address,
      undo_revision,
      undo_kind,
    )
    |> expect.to_be_ok
  let reconnected =
    runtime_core.adopt_reconnect(
      undone,
      runtime_fixture.connected("rejoined", [], 2),
    )
    |> expect.to_be_ok
  let #(resubmitted, outbound) =
    runtime_core.resubmit(runtime_core.go_live(reconnected))
    |> expect.to_be_ok
  runtime_core.tree_revertible_is_valid(resubmitted, address, original)
  |> expect.to_be_true
  runtime_core.tree_revertible_is_valid(resubmitted, address, undo)
  |> expect.to_be_true
  let assert Ok(channel.TreeState(tree)) =
    dict.get(resubmitted.channels, address)
  tree_kernel.history_view(tree).pending
  |> list.map(fn(commit) { commit.revision })
  |> expect.to_equal([original_revision, undo_revision])
  let assert [original_outbound, undo_outbound] = outbound
  let #(accepted, first) =
    runtime_core.handle_sequenced(
      resubmitted,
      sequenced(resubmitted, original_outbound, 3),
    )
    |> expect.to_be_ok
  first.events |> list.length |> expect.to_equal(1)
  let undo_message = sequenced(accepted, undo_outbound, 4)
  let #(settled, second) =
    runtime_core.handle_sequenced(accepted, undo_message)
    |> expect.to_be_ok
  second.events
  |> list.filter(fn(event) {
    case event.1 {
      channel.TreeCommitSettled(revision, _) -> revision == undo_revision
      _ -> False
    }
  })
  |> list.length
  |> expect.to_equal(1)
  let #(_, duplicate) =
    runtime_core.handle_sequenced(settled, undo_message)
    |> expect.to_be_ok
  duplicate.events |> expect.to_equal([])
  let #(_, redo_events, _) =
    runtime_core.revert_tree(settled, address, undo) |> expect.to_be_ok
  applied_commit(redo_events).1
  |> expect.to_equal(RedoCommit)
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

fn applied_commit(
  events: List(#(String, channel.ChannelEvent)),
) -> #(fluid_ids.StableId, TreeCommitKind) {
  events
  |> list.find_map(fn(event) {
    case event.1 {
      channel.TreeCommitApplied(revision, kind, _, _) -> Ok(#(revision, kind))
      _ -> Error(Nil)
    }
  })
  |> expect.to_be_ok
}

fn sequenced(
  core: runtime_core.Core,
  outbound: wire.OutboundOperation,
  sequence_number: Int,
) -> spillway_types.SequencedDocumentMessage {
  let assert Ok(contents) =
    json.parse(json.to_string(outbound.contents), decode.dynamic)
  let metadata = case outbound.metadata {
    None -> None
    Some(metadata) -> {
      let assert Ok(metadata) =
        json.parse(json.to_string(metadata), decode.dynamic)
      Some(metadata)
    }
  }
  spillway_types.SequencedDocumentMessage(
    client_id: Some(core.client_id),
    sequence_number: sequence_number,
    minimum_sequence_number: core.minimum_sequence_number,
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
