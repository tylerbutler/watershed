import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
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
import watershed/tree/shared_change
import watershed/tree/types.{
  type TreeError, CorruptData, InvalidHistory, NumberValue, ObjectValue,
  SequencePoint, SetField, StringValue,
}
import watershed/tree_kernel
import watershed/wire/fluid_container
import watershed/wire/op as wire_op

const schema_text = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"Root\":{\"kind\":{\"object\":{\"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}"

const note_schema_text = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"Root\":{\"kind\":{\"object\":{\"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]},\"note\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}"

const score_schema_text = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"Root\":{\"kind\":{\"object\":{\"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]},\"score\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.number\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}"

const extra_schema_text = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"Extra\":{\"kind\":{\"object\":{\"value\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}}},\"Root\":{\"kind\":{\"object\":{\"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]},\"extra\":{\"kind\":\"Optional\",\"types\":[\"Extra\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}"

const note_extra_schema_text = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"Extra\":{\"kind\":{\"object\":{\"value\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}}},\"Root\":{\"kind\":{\"object\":{\"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]},\"note\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\"]},\"extra\":{\"kind\":\"Optional\",\"types\":[\"Extra\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}"

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

pub fn shared_tree_bridge_retains_schema_changes_test() {
  let assert Ok(session) =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000001")
  let assert Ok(revision) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000003")
  let assert Ok(stored) = schema.stored_from_string(schema_text)
  let changes = [
    shared_change.DataChange(change.empty()),
    shared_change.SchemaChange(
      schema.FixedSchema(stored),
      schema.EmptySchema,
      False,
    ),
  ]
  let assert Ok(commit) =
    tree_runtime.wire_to_commit(codec.WireCommit(
      revision,
      session,
      changes,
      None,
    ))
  shared_change.to_changes(commit.change) |> expect.to_equal(changes)
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
  let assert [first_change] = shared_change.to_changes(first.change)
  let assert [second_change] = shared_change.to_changes(second.change)
  let assert Ok(composed) =
    tree_runtime.wire_to_commit(codec.WireCommit(
      second_revision,
      session,
      [first_change, second_change],
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
    channel.TreeOperation(history.Commit(
      revision,
      session,
      shared_change.from_data(change.empty()),
    )),
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
    history.Commit(revision, session, shared_change.from_data(change.empty())),
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
  let assert Ok(#(edited, Some(commit), _, compressor)) =
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

pub fn shared_tree_bridge_decodes_losing_peer_data_with_authored_schema_test() {
  let receiver_session =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000001")
    |> expect.to_be_ok()
  let sender_session =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000004")
    |> expect.to_be_ok()
  let winner_session =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000005")
    |> expect.to_be_ok()
  let view_id =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000002")
    |> expect.to_be_ok()
  let base = schema.stored_from_string(schema_text) |> expect.to_be_ok()
  let note = schema.stored_from_string(note_schema_text) |> expect.to_be_ok()
  let score = schema.stored_from_string(score_schema_text) |> expect.to_be_ok()
  let view = schema.view_from_string(note_schema_text) |> expect.to_be_ok()
  let sender_view =
    schema.view_from_string(score_schema_text) |> expect.to_be_ok()
  let #(sender_compressor, schema_id) =
    fluid_ids.generate(fluid_ids.new(sender_session)) |> expect.to_be_ok()
  let schema_revision =
    fluid_ids.decompress(sender_compressor, schema_id) |> expect.to_be_ok()
  let winner_revision =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000006")
    |> expect.to_be_ok()
  let winner =
    history.Commit(
      winner_revision,
      winner_session,
      shared_change.from_changes([
        shared_change.SchemaChange(
          schema.FixedSchema(base),
          schema.FixedSchema(note),
          False,
        ),
      ])
        |> expect.to_be_ok(),
    )
  let losing =
    history.Commit(
      schema_revision,
      sender_session,
      shared_change.from_changes([
        shared_change.SchemaChange(
          schema.FixedSchema(base),
          schema.FixedSchema(score),
          False,
        ),
      ])
        |> expect.to_be_ok(),
    )
  let muted =
    history.Commit(schema_revision, sender_session, shared_change.empty())
  let history_snapshot =
    history.HistorySnapshot(
      history.InitialBase,
      [
        history.SequencedCommit(winner, SequencePoint(1, 0)),
        history.SequencedCommit(muted, SequencePoint(2, 0)),
      ],
      [history.PeerBranch(sender_session, None, [losing])],
      2,
      0,
    )
  let data =
    forest.ForestData(
      Some(ObjectValue("Root", [#("x", NumberValue(1.0))])),
      [],
      0,
    )
  let receiver_snapshot =
    tree_kernel.snapshot_from_parts(view_id, note, data, history_snapshot)
    |> expect.to_be_ok()
  let receiver =
    tree_kernel.restore(receiver_snapshot, view_id, receiver_session, view)
    |> expect.to_be_ok()
  let sender_snapshot =
    tree_kernel.snapshot_from_parts(
      view_id,
      score,
      data,
      history.inspect(history.new(sender_session)).sequenced,
    )
    |> expect.to_be_ok()
  let sender =
    tree_kernel.restore(sender_snapshot, view_id, sender_session, sender_view)
    |> expect.to_be_ok()
  let assert Ok(#(sender, Some(commit), _, sender_compressor)) =
    tree_runtime.author_edit(
      sender,
      SetField(["score"], NumberValue(9.0)),
      sender_compressor,
    )
  let wire =
    tree_runtime.encode_commit(commit, sender, sender_compressor)
    |> expect.to_be_ok()
  let #(sender_compressor, range) =
    fluid_ids.take_creation_range(sender_compressor)
  let assert Some(range) = range
  let receiver_compressor =
    fluid_ids.finalize(fluid_ids.new(receiver_session), range)
    |> expect.to_be_ok()
  let assert Ok(#(decoded, _)) =
    tree_runtime.decode_sequenced_message(
      json.to_string(wire),
      receiver,
      0,
      receiver_compressor,
    )
  let assert Ok(#(received, _, _)) =
    tree_runtime.receive_commit(
      receiver,
      decoded,
      SequencePoint(3, 0),
      0,
      0,
      receiver_compressor,
    )
  let assert [_, _, rebased] =
    tree_kernel.history_view(received).sequenced.trunk
  shared_change.to_changes(rebased.commit.change) |> expect.to_equal([])
  let _ = sender_compressor
  Nil
}

pub fn shared_tree_bridge_decodes_after_duplicate_schema_replay_test() {
  let receiver_session =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000001")
    |> expect.to_be_ok()
  let sender_session =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000004")
    |> expect.to_be_ok()
  let view_id =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000002")
    |> expect.to_be_ok()
  let base = schema.stored_from_string(schema_text) |> expect.to_be_ok()
  let note = schema.stored_from_string(note_schema_text) |> expect.to_be_ok()
  let view = schema.view_from_string(note_schema_text) |> expect.to_be_ok()
  let schema_revision =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000006")
    |> expect.to_be_ok()
  let upgrade =
    history.Commit(
      schema_revision,
      sender_session,
      shared_change.from_changes([
        shared_change.SchemaChange(
          schema.FixedSchema(base),
          schema.FixedSchema(note),
          False,
        ),
      ])
        |> expect.to_be_ok(),
    )
  let history_snapshot =
    history.HistorySnapshot(
      history.InitialBase,
      [
        history.SequencedCommit(upgrade, SequencePoint(1, 0)),
        history.SequencedCommit(upgrade, SequencePoint(2, 0)),
      ],
      [],
      2,
      0,
    )
  let data =
    forest.ForestData(
      Some(ObjectValue("Root", [#("x", NumberValue(1.0))])),
      [],
      0,
    )
  let receiver_snapshot =
    tree_kernel.snapshot_from_parts(view_id, note, data, history_snapshot)
    |> expect.to_be_ok()
  let receiver =
    tree_kernel.restore(receiver_snapshot, view_id, receiver_session, view)
    |> expect.to_be_ok()
  let sender_snapshot =
    tree_kernel.snapshot_from_parts(
      view_id,
      note,
      data,
      history.inspect(history.new(sender_session)).sequenced,
    )
    |> expect.to_be_ok()
  let sender =
    tree_kernel.restore(sender_snapshot, view_id, sender_session, view)
    |> expect.to_be_ok()
  let assert Ok(#(sender, commit, _, sender_compressor)) =
    tree_runtime.author_edit(
      sender,
      SetField(["note"], StringValue("after duplicate")),
      fluid_ids.new(sender_session),
    )
  let wire =
    tree_runtime.encode_commit(commit, sender, sender_compressor)
    |> expect.to_be_ok()
  let #(_, range) = fluid_ids.take_unfinalized_range(sender_compressor)
  let assert Some(range) = range
  let receiver_compressor =
    fluid_ids.finalize(fluid_ids.new(receiver_session), range)
    |> expect.to_be_ok()

  let assert Ok(_) =
    tree_runtime.decode_sequenced_message(
      json.to_string(wire),
      receiver,
      2,
      receiver_compressor,
    )
  Nil
}

pub fn shared_tree_bridge_decodes_local_data_ack_after_same_reference_upgrade_test() {
  let session =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000001")
    |> expect.to_be_ok()
  let base = schema.stored_from_string(schema_text) |> expect.to_be_ok()
  let extra = schema.stored_from_string(extra_schema_text) |> expect.to_be_ok()
  let #(compressor, schema_id) =
    fluid_ids.generate(fluid_ids.new(session)) |> expect.to_be_ok()
  let schema_revision =
    fluid_ids.decompress(compressor, schema_id) |> expect.to_be_ok()
  let schema_change =
    shared_change.from_changes([
      shared_change.SchemaChange(
        schema.FixedSchema(base),
        schema.FixedSchema(extra),
        False,
      ),
    ])
    |> expect.to_be_ok()
  let order =
    change.identity_order([#(schema_revision, -1)]) |> expect.to_be_ok()
  let #(upgraded, upgrade, _) =
    tree_kernel.apply_local_change(
      tree_state(),
      schema_revision,
      order,
      schema_change,
    )
    |> expect.to_be_ok()
  let #(edited, data, _, compressor) =
    tree_runtime.author_edit(
      upgraded,
      SetField(
        ["extra"],
        ObjectValue("Extra", [#("value", StringValue("local"))]),
      ),
      compressor,
    )
    |> expect.to_be_ok()
  let data_wire =
    tree_runtime.encode_commit(data, edited, compressor) |> expect.to_be_ok()
  let assert Ok(#(acked, _, compressor)) =
    tree_runtime.receive_commit(
      edited,
      upgrade,
      SequencePoint(1, 0),
      0,
      0,
      compressor,
    )

  let assert Ok(_) =
    tree_runtime.decode_sequenced_message(
      json.to_string(data_wire),
      acked,
      0,
      compressor,
    )
  Nil
}

pub fn shared_tree_bridge_decodes_muted_local_schema_ack_after_remote_winner_test() {
  let #(rebased, upgrade_wire, _, compressor) =
    concurrent_local_upgrade_and_data()
  let #(upgrade, _) = case
    tree_runtime.decode_sequenced_message(
      json.to_string(upgrade_wire),
      rebased,
      0,
      compressor,
    )
  {
    Ok(value) -> value
    Error(error) -> panic as { "schema ack decode: " <> string.inspect(error) }
  }
  let #(acked, _, _) = case
    tree_runtime.receive_commit(
      rebased,
      upgrade,
      SequencePoint(2, 0),
      0,
      0,
      compressor,
    )
  {
    Ok(value) -> value
    Error(error) -> panic as { "schema ack receive: " <> string.inspect(error) }
  }
  let assert [_, muted] = tree_kernel.history_view(acked).sequenced.trunk
  shared_change.to_changes(muted.commit.change) |> expect.to_equal([])
}

pub fn shared_tree_bridge_decodes_rebased_local_data_ack_with_authored_schema_test() {
  let #(rebased, upgrade_wire, data_wire, compressor) =
    concurrent_local_upgrade_and_data()
  let #(upgrade, _) = case
    tree_runtime.decode_sequenced_message(
      json.to_string(upgrade_wire),
      rebased,
      0,
      compressor,
    )
  {
    Ok(value) -> value
    Error(error) -> panic as { "schema ack decode: " <> string.inspect(error) }
  }
  let #(acked, _, compressor) = case
    tree_runtime.receive_commit(
      rebased,
      upgrade,
      SequencePoint(2, 0),
      0,
      0,
      compressor,
    )
  {
    Ok(value) -> value
    Error(error) -> panic as { "schema ack receive: " <> string.inspect(error) }
  }

  tree_runtime.decode_sequenced_message(
    json.to_string(data_wire),
    acked,
    0,
    compressor,
  )
  |> expect.to_be_ok()
  Nil
}

pub fn shared_tree_bridge_keeps_local_ack_context_after_trim_test() {
  let #(rebased, upgrade_wire, _, compressor) =
    concurrent_local_upgrade_and_data()
  tree_runtime.decode_sequenced_message(
    json.to_string(upgrade_wire),
    rebased,
    0,
    compressor,
  )
  |> expect.to_be_ok()
  let #(trimmed, compressor) =
    tree_runtime.advance_document(rebased, 1, 1, compressor)
    |> expect.to_be_ok()

  tree_runtime.decode_sequenced_message(
    json.to_string(upgrade_wire),
    trimmed,
    0,
    compressor,
  )
  |> expect.to_be_ok()
  Nil
}

pub fn shared_tree_bridge_keeps_local_ack_context_after_restore_and_trim_test() {
  let initial = tree_state()
  let snapshot = tree_kernel.snapshot(initial) |> expect.to_be_ok()
  let local_session =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000001")
    |> expect.to_be_ok()
  let view = schema.view_from_string(schema_text) |> expect.to_be_ok()
  let restored =
    tree_kernel.restore(
      snapshot,
      fluid_ids.stable_id("00000000-0000-4000-8000-000000000002")
        |> expect.to_be_ok(),
      local_session,
      view,
    )
    |> expect.to_be_ok()
  let #(rebased, upgrade_wire, _, compressor) =
    concurrent_local_upgrade_and_data_from(restored)
  let #(trimmed, compressor) =
    tree_runtime.advance_document(rebased, 1, 1, compressor)
    |> expect.to_be_ok()

  tree_runtime.decode_sequenced_message(
    json.to_string(upgrade_wire),
    trimmed,
    0,
    compressor,
  )
  |> expect.to_be_ok()
  Nil
}

pub fn shared_tree_bridge_receives_authored_prefix_after_trim_test() {
  let local_session =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000001")
    |> expect.to_be_ok()
  let view_id =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000002")
    |> expect.to_be_ok()
  let base = schema.stored_from_string(note_schema_text) |> expect.to_be_ok()
  let extra =
    schema.stored_from_string(note_extra_schema_text) |> expect.to_be_ok()
  let view = schema.view_from_string(note_schema_text) |> expect.to_be_ok()
  let snapshot =
    tree_kernel.snapshot_from_parts(
      view_id,
      base,
      forest.ForestData(
        Some(ObjectValue("Root", [#("x", NumberValue(1.0))])),
        [],
        0,
      ),
      history.inspect(history.new(local_session)).sequenced,
    )
    |> expect.to_be_ok()
  let initial =
    tree_kernel.restore(snapshot, view_id, local_session, view)
    |> expect.to_be_ok()
  let #(first_state, first, _, compressor) =
    tree_runtime.author_edit(
      initial,
      SetField(["note"], StringValue("before upgrade")),
      fluid_ids.new(local_session),
    )
    |> expect.to_be_ok()
  let #(compressor, schema_id) =
    fluid_ids.generate(compressor) |> expect.to_be_ok()
  let schema_revision =
    fluid_ids.decompress(compressor, schema_id) |> expect.to_be_ok()
  let schema_change =
    shared_change.from_changes([
      shared_change.SchemaChange(
        schema.FixedSchema(base),
        schema.FixedSchema(extra),
        False,
      ),
    ])
    |> expect.to_be_ok()
  let order =
    codec.identity_order(
      [schema_revision, ..tree_kernel.identity_revisions(first_state)],
      compressor,
      "authored prefix schema order",
    )
    |> expect.to_be_ok()
  let #(upgraded, upgrade, _) =
    tree_kernel.apply_local_change(
      first_state,
      schema_revision,
      order,
      schema_change,
    )
    |> expect.to_be_ok()
  let #(edited, final_data, _, compressor) =
    tree_runtime.author_edit(
      upgraded,
      SetField(
        ["extra"],
        ObjectValue("Extra", [#("value", StringValue("local"))]),
      ),
      compressor,
    )
    |> expect.to_be_ok()
  let first_wire =
    tree_runtime.encode_commit(first, first_state, compressor)
    |> expect.to_be_ok()
  let upgrade_wire =
    codec.encode_message(
      codec.TreeMessage(
        codec.WireCommit(
          upgrade.revision,
          upgrade.originator,
          shared_change.to_changes(upgrade.change),
          None,
        ),
        [],
      ),
      codec.EncodeContext(codec.Fluid310, compressor, Some(extra)),
    )
    |> expect.to_be_ok()
  let final_wire =
    tree_runtime.encode_commit(final_data, edited, compressor)
    |> expect.to_be_ok()

  let #(first_ack, _) =
    tree_runtime.decode_sequenced_message(
      json.to_string(first_wire),
      edited,
      0,
      compressor,
    )
    |> expect.to_be_ok()
  let #(acked_first, _, compressor) =
    tree_runtime.receive_commit(
      edited,
      first_ack,
      SequencePoint(1, 0),
      0,
      0,
      compressor,
    )
    |> expect.to_be_ok()
  let #(trimmed, compressor) =
    tree_runtime.advance_document(acked_first, 1, 1, compressor)
    |> expect.to_be_ok()
  let #(schema_ack, _) =
    tree_runtime.decode_sequenced_message(
      json.to_string(upgrade_wire),
      trimmed,
      0,
      compressor,
    )
    |> expect.to_be_ok()
  let #(acked_schema, _, compressor) =
    tree_runtime.receive_commit(
      trimmed,
      schema_ack,
      SequencePoint(2, 0),
      0,
      1,
      compressor,
    )
    |> expect.to_be_ok()
  let #(data_ack, _) =
    tree_runtime.decode_sequenced_message(
      json.to_string(final_wire),
      acked_schema,
      0,
      compressor,
    )
    |> expect.to_be_ok()
  let #(acked_data, _, compressor) =
    tree_runtime.receive_commit(
      acked_schema,
      data_ack,
      SequencePoint(3, 0),
      0,
      1,
      compressor,
    )
    |> expect.to_be_ok()

  tree_kernel.history_view(acked_data).pending |> expect.to_equal([])
  let #(finished, _) =
    tree_runtime.advance_document(acked_data, 3, 3, compressor)
    |> expect.to_be_ok()
  tree_kernel.history_view(finished).sequenced.trunk |> expect.to_equal([])
  tree_kernel.identity_revisions(finished) |> expect.to_equal([])
}

fn concurrent_local_upgrade_and_data() -> #(
  tree_kernel.TreeState,
  json.Json,
  json.Json,
  fluid_ids.Compressor,
) {
  let #(state, upgrade_wire, data_wire, compressor) =
    concurrent_local_upgrade_and_data_from(tree_state())
  #(state, upgrade_wire, data_wire, compressor)
}

fn concurrent_local_upgrade_and_data_from(
  initial: tree_kernel.TreeState,
) -> #(tree_kernel.TreeState, json.Json, json.Json, fluid_ids.Compressor) {
  let local_session =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000001")
    |> expect.to_be_ok()
  let remote_session =
    fluid_ids.session_id("20000000-0000-4000-8000-000000000000")
    |> expect.to_be_ok()
  let base = schema.stored_from_string(schema_text) |> expect.to_be_ok()
  let extra = schema.stored_from_string(extra_schema_text) |> expect.to_be_ok()
  let note = schema.stored_from_string(note_schema_text) |> expect.to_be_ok()
  let #(compressor, schema_id) =
    fluid_ids.generate(fluid_ids.new(local_session)) |> expect.to_be_ok()
  let schema_revision =
    fluid_ids.decompress(compressor, schema_id) |> expect.to_be_ok()
  let schema_change =
    shared_change.from_changes([
      shared_change.SchemaChange(
        schema.FixedSchema(base),
        schema.FixedSchema(extra),
        False,
      ),
    ])
    |> expect.to_be_ok()
  let order =
    change.identity_order([#(schema_revision, -1)]) |> expect.to_be_ok()
  let assert Ok(#(upgraded, upgrade, _)) =
    tree_kernel.apply_local_change(
      initial,
      schema_revision,
      order,
      schema_change,
    )
  let assert Ok(#(edited, data, _, compressor)) =
    tree_runtime.author_edit(
      upgraded,
      SetField(
        ["extra"],
        ObjectValue("Extra", [#("value", StringValue("local"))]),
      ),
      compressor,
    )
  let upgrade_wire =
    codec.encode_message(
      codec.TreeMessage(
        codec.WireCommit(
          upgrade.revision,
          upgrade.originator,
          shared_change.to_changes(upgrade.change),
          None,
        ),
        [],
      ),
      codec.EncodeContext(codec.Fluid310, compressor, Some(extra)),
    )
    |> expect.to_be_ok()
  let data_wire =
    tree_runtime.encode_commit(data, edited, compressor) |> expect.to_be_ok()
  let remote_view = schema.view_from_string(schema_text) |> expect.to_be_ok()
  let snapshot = tree_kernel.snapshot(tree_state()) |> expect.to_be_ok()
  let remote =
    tree_kernel.restore(
      snapshot,
      fluid_ids.stable_id("00000000-0000-4000-8000-000000000002")
        |> expect.to_be_ok(),
      remote_session,
      remote_view,
    )
    |> expect.to_be_ok()
  let #(remote_compressor, remote_id) =
    fluid_ids.generate(fluid_ids.new(remote_session)) |> expect.to_be_ok()
  let remote_revision =
    fluid_ids.decompress(remote_compressor, remote_id) |> expect.to_be_ok()
  let remote_change =
    shared_change.from_changes([
      shared_change.SchemaChange(
        schema.FixedSchema(base),
        schema.FixedSchema(note),
        False,
      ),
    ])
    |> expect.to_be_ok()
  let remote_order =
    change.identity_order([#(remote_revision, -1)]) |> expect.to_be_ok()
  let #(_, winner, _) =
    tree_kernel.apply_local_change(
      remote,
      remote_revision,
      remote_order,
      remote_change,
    )
    |> expect.to_be_ok()
  let assert #(_, Some(remote_range)) =
    fluid_ids.take_unfinalized_range(remote_compressor)
  let compressor =
    fluid_ids.finalize(compressor, remote_range) |> expect.to_be_ok()
  let revisions = [
    winner.revision,
    ..list.append(
      shared_change.identity_revisions(winner.change),
      tree_kernel.identity_revisions(edited),
    )
  ]
  let receive_order =
    codec.identity_order(
      revisions,
      compressor,
      "concurrent local acknowledgement receive order",
    )
    |> expect.to_be_ok()
  let rollback_session =
    fluid_ids.session_id("30000000-0000-4000-8000-000000000000")
    |> expect.to_be_ok()
  let #(rollback_compressor, rollback_revisions) =
    channel_revisions(fluid_ids.new(rollback_session), 4, [])
    |> expect.to_be_ok()
  let assert #(_, Some(rollback_range)) =
    fluid_ids.take_unfinalized_range(rollback_compressor)
  let compressor =
    fluid_ids.finalize(compressor, rollback_range) |> expect.to_be_ok()
  let #(rebased, _, allocation) =
    tree_kernel.receive_ordered(
      edited,
      winner,
      receive_order,
      SequencePoint(1, 0),
      0,
      0,
      #(compressor, revisions, rollback_revisions),
      mint_channel_revision,
    )
    |> expect.to_be_ok()
  let #(compressor, _, _) = allocation
  #(rebased, upgrade_wire, data_wire, compressor)
}

fn mint_channel_revision(
  allocation: #(
    fluid_ids.Compressor,
    List(fluid_ids.StableId),
    List(fluid_ids.StableId),
  ),
) -> Result(
  #(
    fluid_ids.StableId,
    change.IdentityOrder,
    #(fluid_ids.Compressor, List(fluid_ids.StableId), List(fluid_ids.StableId)),
  ),
  TreeError,
) {
  let #(compressor, revisions, available) = allocation
  use #(revision, remaining) <- result.try(case available {
    [revision, ..remaining] -> Ok(#(revision, remaining))
    [] ->
      Error(CorruptData(
        "concurrent local acknowledgement rollback",
        "rollback identity pool is empty",
      ))
  })
  use order <- result.try(codec.identity_order(
    [revision, ..revisions],
    compressor,
    "concurrent local acknowledgement rollback order",
  ))
  Ok(#(revision, order, #(compressor, [revision, ..revisions], remaining)))
}

fn channel_revisions(
  compressor: fluid_ids.Compressor,
  remaining: Int,
  revisions: List(fluid_ids.StableId),
) -> Result(
  #(fluid_ids.Compressor, List(fluid_ids.StableId)),
  fluid_ids.IdError,
) {
  case remaining {
    0 -> Ok(#(compressor, list.reverse(revisions)))
    _ -> {
      use #(compressor, id) <- result.try(fluid_ids.generate(compressor))
      use revision <- result.try(fluid_ids.decompress(compressor, id))
      channel_revisions(compressor, remaining - 1, [revision, ..revisions])
    }
  }
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
  let assert Ok(#(_, Some(remote_commit), _, remote_compressor)) =
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
  let assert Ok(#(pending, Some(first), _, compressor)) =
    tree_runtime.author_edit(
      state,
      SetField(["x"], NumberValue(2.0)),
      fluid_ids.new(local),
    )
  let assert Ok(#(_, Some(second), _, remote_compressor)) =
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
