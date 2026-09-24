import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import startest/expect
import watershed/channel
import watershed/crdt_core
import watershed/fluid_ids
import watershed/p2p
import watershed/runtime_core
import watershed/tree/change
import watershed/tree/codec
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/runtime as tree_runtime
import watershed/tree/schema
import watershed/tree/types.{
  InvalidHistory, NumberValue, ObjectValue, SequencePoint, SetField,
}
import watershed/tree_kernel
import watershed/wire/fluid_container
import watershed/wire/op as wire_op

const schema_text = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"Root\":{\"kind\":{\"object\":{\"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}"

fn tree_state() -> tree_kernel.TreeState {
  let assert Ok(session) =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000001")
  let assert Ok(view_id) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000002")
  let assert Ok(stored) = schema.stored_from_string(schema_text)
  let assert Ok(view) = schema.view_from_string(schema_text)
  let assert Ok(snapshot) =
    tree_kernel.snapshot_from_parts(
      view_id,
      stored,
      forest.ForestData(
        Some(ObjectValue("Root", [#("x", NumberValue(1.0))])),
        [],
        0,
      ),
      history.inspect(history.new(session)).sequenced,
    )
  let assert Ok(state) = tree_kernel.restore(snapshot, view_id, session, view)
  state
}

pub fn shared_tree_channel_dispatches_checked_restored_tree_test() {
  let state = tree_state()
  let wrapped = channel.new(channel.InitTree(state), replica: "reader")
  channel.channel_type(wrapped) |> expect.to_equal(channel.TreeChannel)
  channel.init_type(channel.InitTree(state))
  |> expect.to_equal(channel.TreeChannel)
  channel.supports_p2p(channel.TreeChannel) |> expect.to_equal(False)
  channel.fluid_type_to_string(channel.TreeChannel)
  |> expect.to_equal("https://graph.microsoft.com/types/tree")
  let assert Ok(snapshot) = channel.snapshot(wrapped)
  channel.snapshot_type(snapshot) |> expect.to_equal(channel.TreeChannel)
  channel.encode_snapshot(snapshot) |> expect.to_be_error()
  channel.from_snapshot(snapshot, replica: "reader") |> expect.to_be_error()
  channel.attach_state(wrapped, replica: "reader") |> expect.to_be_error()
  json.to_string(channel.fluid_attributes(channel.TreeChannel))
  |> string.contains("0.0.0")
  |> expect.to_equal(True)
}

pub fn shared_tree_bridge_rejects_schema_changes_test() {
  let assert Ok(session) =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000001")
  let assert Ok(revision) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000003")
  let assert Ok(stored) = schema.stored_from_string(schema_text)
  tree_runtime.wire_to_commit(codec.WireCommit(
    revision,
    session,
    [
      codec.DataChange(change.empty()),
      codec.SchemaChange(codec.FixedSchema(stored), codec.EmptySchema),
    ],
    None,
  ))
  |> expect.to_be_error()
  Nil
}

pub fn shared_tree_bridge_composes_data_changes_in_wire_order_test() {
  let state = tree_state()
  let assert Ok(session) =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000004")
  let assert Ok(view_id) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000002")
  let assert Ok(view) = schema.view_from_string(schema_text)
  let assert Ok(snapshot) = tree_kernel.snapshot(state)
  let assert Ok(peer) = tree_kernel.restore(snapshot, view_id, session, view)
  let assert Ok(first_revision) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000003")
  let assert Ok(second_revision) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000004")
  let assert Ok(order) =
    change.identity_order([
      #(first_revision, -2),
      #(second_revision, -1),
    ])
  let assert Ok(#(first_state, first, _)) =
    tree_kernel.apply_local(
      peer,
      first_revision,
      order,
      SetField(["x"], NumberValue(2.0)),
    )
  let assert Ok(#(_, second, _)) =
    tree_kernel.apply_local(
      first_state,
      second_revision,
      order,
      SetField(["x"], NumberValue(3.0)),
    )
  let assert Ok(composed) =
    tree_runtime.wire_to_commit(codec.WireCommit(
      second_revision,
      session,
      [
        codec.DataChange(first.change),
        codec.DataChange(second.change),
      ],
      None,
    ))
  let assert Ok(#(received, _, Nil)) =
    tree_kernel.receive_ordered(
      state,
      composed,
      order,
      SequencePoint(1, 0),
      0,
      0,
      Nil,
      fn(_) { Error(InvalidHistory("rollback not expected")) },
    )
  tree_kernel.read(received, ["x"])
  |> expect.to_equal(Ok(Some(NumberValue(3.0))))
}

pub fn shared_tree_snapshot_keeps_pending_changes_out_of_sequenced_data_test() {
  let state = tree_state()
  let assert Ok(session) =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000001")
  let assert Ok(before) = channel.snapshot(channel.TreeState(state))
  let assert Ok(#(edited, _, _, _)) =
    tree_runtime.author_edit(
      state,
      SetField(["x"], NumberValue(2.0)),
      fluid_ids.new(session),
    )
  tree_kernel.read(edited, ["x"])
  |> expect.to_equal(Ok(Some(NumberValue(2.0))))
  channel.snapshot(channel.TreeState(edited)) |> expect.to_equal(Ok(before))
  let assert channel.TreeSnapshot(snapshot) = before
  let #(_, _, history) = tree_kernel.snapshot_parts(snapshot)
  history.trunk |> expect.to_equal([])
  tree_kernel.history_view(edited).pending |> list.length |> expect.to_equal(1)
  Nil
}

pub fn shared_tree_generic_wire_and_summary_refuse_missing_context_test() {
  let state = tree_state()
  let assert Ok(channel.TreeSnapshot(snapshot)) =
    channel.snapshot(channel.TreeState(state))
  channel.encode_snapshot(channel.TreeSnapshot(snapshot))
  |> expect.to_be_error()
  wire_op.encode_attach("A/_C", channel.TreeSnapshot(snapshot))
  |> expect.to_be_error()
  channel.snapshot_decoder(channel.TreeChannel)
  |> expect.to_be_error()
  let assert Ok(session) =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000001")
  let assert Ok(revision) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000003")
  wire_op.encode_channel_operation(
    channel.TreeOperation(history.Commit(revision, session, change.empty())),
  )
  |> expect.to_be_error()
  wire_op.channel_operation_decoder(channel.TreeChannel)
  |> expect.to_be_error()
  Nil
}

pub fn shared_tree_bridge_refuses_unknown_compressor_revision_test() {
  let state = tree_state()
  let assert Ok(session) =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000001")
  let assert Ok(revision) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000003")
  let compressor = fluid_ids.new(session)
  tree_runtime.identity_order(
    state,
    history.Commit(revision, session, change.empty()),
    compressor,
  )
  |> expect.to_be_error()
  tree_runtime.decode_message(
    "{\"version\":7,\"revision\":-1,\"originatorId\":\"00000000-0000-4000-8000-000000000001\",\"changeset\":[]}",
    state,
    compressor,
  )
  |> expect.to_be_error()
  Nil
}

pub fn shared_tree_bridge_authors_without_finalizing_and_round_trips_test() {
  let state = tree_state()
  let assert Ok(session) =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000001")
  let assert Ok(#(edited, commit, _, compressor)) =
    tree_runtime.author_edit(
      state,
      SetField(["x"], NumberValue(2.0)),
      fluid_ids.new(session),
    )
  let #(_, range) = fluid_ids.take_unfinalized_range(compressor)
  let assert Some(_) = range
  let assert Ok(wire) = tree_runtime.encode_commit(commit, edited, compressor)
  let assert Ok(#(decoded, _)) =
    tree_runtime.decode_message(json.to_string(wire), edited, compressor)
  decoded.revision |> expect.to_equal(commit.revision)
  decoded.originator |> expect.to_equal(commit.originator)
  Nil
}

pub fn shared_tree_bridge_rebases_pending_with_allocated_rollback_identity_test() {
  let state = tree_state()
  let assert Ok(local) =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000001")
  let assert Ok(remote) =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000004")
  let assert Ok(view_id) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000002")
  let assert Ok(view) = schema.view_from_string(schema_text)
  let assert Ok(snapshot) = tree_kernel.snapshot(state)
  let assert Ok(peer) = tree_kernel.restore(snapshot, view_id, remote, view)
  let assert Ok(#(pending, _, _, compressor)) =
    tree_runtime.author_edit(
      state,
      SetField(["x"], NumberValue(2.0)),
      fluid_ids.new(local),
    )
  let assert Ok(#(_, remote_commit, _, remote_compressor)) =
    tree_runtime.author_edit(
      peer,
      SetField(["x"], NumberValue(3.0)),
      fluid_ids.new(remote),
    )
  let #(_, range) = fluid_ids.take_unfinalized_range(remote_compressor)
  let assert Some(range) = range
  let assert Ok(compressor) = fluid_ids.finalize(compressor, range)
  let assert Ok(#(received, _, compressor)) =
    tree_runtime.receive_commit(
      pending,
      remote_commit,
      SequencePoint(1, 0),
      0,
      0,
      compressor,
    )
  tree_kernel.history_view(received).sequenced.trunk
  |> list.length
  |> expect.to_equal(1)
  let #(_, range) = fluid_ids.take_unfinalized_range(compressor)
  let assert Some(_) = range
  Nil
}

pub fn shared_tree_p2p_creation_and_import_are_refused_test() {
  let assert Error(p2p.UnsupportedChannel(channel.TreeChannel)) =
    crdt_core.new(crdt_core.config(
      room: "tree",
      compatibility: "tree",
      replica: "reader",
      session: "reader-session",
      root: channel.InitTree(tree_state()),
    ))
  let assert Ok(document) =
    crdt_core.new(crdt_core.config(
      room: "tree",
      compatibility: "tree",
      replica: "reader",
      session: "reader-session",
      root: channel.InitOrSet,
    ))
  let assert Ok(raw) = crdt_core.canonical_json(document)
  let tree_root = string.replace(raw, "\"root\":\"orset\"", "\"root\":\"tree\"")
  tree_root |> expect.to_not_equal(raw)
  crdt_core.import_snapshot(document, tree_root)
  |> expect.to_equal(Error(p2p.UnsupportedChannel(channel.TreeChannel)))
}

fn concurrent_snapshot() -> #(tree_kernel.TreeSnapshot, fluid_ids.Compressor) {
  let state = tree_state()
  let assert Ok(local) =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000001")
  let assert Ok(remote) =
    fluid_ids.session_id("20000000-0000-4000-8000-000000000000")
  let assert Ok(view_id) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000002")
  let assert Ok(view) = schema.view_from_string(schema_text)
  let assert Ok(snapshot) = tree_kernel.snapshot(state)
  let assert Ok(peer) = tree_kernel.restore(snapshot, view_id, remote, view)
  let assert Ok(#(pending, first, _, compressor)) =
    tree_runtime.author_edit(
      state,
      SetField(["x"], NumberValue(2.0)),
      fluid_ids.new(local),
    )
  let assert Ok(#(_, second, _, remote_compressor)) =
    tree_runtime.author_edit(
      peer,
      SetField(["x"], NumberValue(3.0)),
      fluid_ids.new(remote),
    )
  let assert #(_, Some(first_range)) =
    fluid_ids.take_unfinalized_range(compressor)
  let assert #(_, Some(second_range)) =
    fluid_ids.take_unfinalized_range(remote_compressor)
  let assert Ok(compressor) = fluid_ids.finalize(compressor, first_range)
  let assert Ok(compressor) = fluid_ids.finalize(compressor, second_range)
  let #(state, _, compressor) =
    tree_runtime.receive_commit(
      pending,
      first,
      SequencePoint(1, 0),
      0,
      0,
      compressor,
    )
    |> expect.to_be_ok()
  let #(state, _, compressor) =
    tree_runtime.receive_commit(
      state,
      second,
      SequencePoint(2, 0),
      0,
      0,
      compressor,
    )
    |> expect.to_be_ok()
  let assert Ok(snapshot) = tree_kernel.snapshot(state)
  #(snapshot, compressor)
}

pub fn shared_tree_bridge_advances_restored_session_identity_order_test() {
  let #(snapshot, compressor) = concurrent_snapshot()
  let assert Ok(session) =
    fluid_ids.session_id("30000000-0000-4000-8000-000000000000")
  let assert Ok(view_id) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000002")
  let assert Ok(view) = schema.view_from_string(schema_text)
  let assert Ok(serialized) = fluid_ids.serialize(compressor, False)
  let assert Ok(compressor) = fluid_ids.deserialize(serialized, session)
  let assert Ok(state) = tree_kernel.restore(snapshot, view_id, session, view)
  let before = tree_kernel.visible_data(state)
  let #(advanced, _) =
    tree_runtime.advance_document(state, 3, 2, compressor)
    |> expect.to_be_ok()
  tree_kernel.visible_data(advanced) |> expect.to_equal(before)
  tree_kernel.history_view(advanced).sequenced.sequence_number
  |> expect.to_equal(3)
  tree_kernel.history_view(advanced).sequenced.minimum_sequence_number
  |> expect.to_equal(2)
}

pub fn shared_tree_seed_rejects_unresolvable_history_revisions_test() {
  let #(snapshot, compressor) = concurrent_snapshot()
  let assert Ok(view_id) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000002")
  let assert Ok(view) = schema.view_from_string(schema_text)
  let root = fluid_container.Route("A", "root")
  let tree = fluid_container.Route("A", "_C")
  let input =
    runtime_core.BootstrapSeedInput(
      profile: runtime_core.RoutedSeed,
      sequence_number: 2,
      minimum_sequence_number: 0,
      members: [],
      datastores: [runtime_core.DatastoreSeed("A", ["test"])],
      aliases: [],
      channels: [
        runtime_core.ChannelSeed(
          root,
          channel.fluid_attributes(channel.MapChannel),
          channel.MapSnapshot([]),
        ),
        runtime_core.ChannelSeed(
          tree,
          channel.fluid_attributes(channel.TreeChannel),
          channel.TreeSnapshot(snapshot),
        ),
      ],
      bootstrap_map: root,
      compressor: Some(compressor),
      tree_views: [runtime_core.TreeViewSeed(tree, view_id, view)],
    )
  runtime_core.bootstrap_seed(input) |> expect.to_be_ok()
  runtime_core.bootstrap_seed(
    runtime_core.BootstrapSeedInput(
      ..input,
      compressor: Some(fluid_ids.new(fluid_ids.local_session(compressor))),
    ),
  )
  |> expect.to_be_error()
  Nil
}
