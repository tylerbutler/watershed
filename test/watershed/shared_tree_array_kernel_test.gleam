import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import spillway/types as document
import startest/expect
import watershed/channel
import watershed/fluid_ids
import watershed/runtime_core
import watershed/tree/array_fixture
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/runtime as tree_runtime
import watershed/tree/runtime_fixture
import watershed/tree/types
import watershed/tree_kernel
import watershed/wire

const items_type = "org.watershed.shared-tree.m3.Items"

fn core() -> runtime_core.Core {
  core_for(
    "array-writer",
    "30000000-0000-4000-8000-000000000003",
    types.ArrayValue(items_type, [
      types.StringValue("A"),
      types.StringValue("B"),
    ]),
  )
}

fn core_for(
  client: String,
  session: String,
  root: types.TreeValue,
) -> runtime_core.Core {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert [view] = input.tree_views
  let assert Some(compressor) = input.compressor
  let assert Ok(serialized) = fluid_ids.serialize(compressor, False)
  let assert Ok(session) = fluid_ids.session_id(session)
  let assert Ok(compressor) = fluid_ids.deserialize(serialized, session)
  let assert Ok(snapshot) =
    tree_kernel.snapshot_from_parts(
      view.view_id,
      array_fixture.stored("rootArray"),
      forest.ForestData(Some(root), [], 0),
      history.HistorySnapshot(history.InitialBase, [], [], 0, 0),
    )
  let assert Ok(seed) =
    runtime_core.bootstrap_seed(
      runtime_core.BootstrapSeedInput(
        ..input,
        sequence_number: 0,
        minimum_sequence_number: 0,
        compressor: Some(compressor),
        tree_views: [
          runtime_core.TreeViewSeed(
            ..view,
            view: array_fixture.view("rootArray"),
          ),
        ],
        channels: list.map(input.channels, fn(seed) {
          case seed.route == view.route {
            True ->
              runtime_core.ChannelSeed(
                ..seed,
                snapshot: channel.TreeSnapshot(snapshot),
              )
            False -> seed
          }
        }),
      ),
    )
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap_seeded(
      runtime_fixture.connected(client, [], 0),
      seed,
    )
  core
}

fn state(core: runtime_core.Core) -> tree_kernel.TreeState {
  let assert Ok(channel.TreeState(state)) = dict.get(core.channels, "A/_C")
  state
}

fn message(
  sender: runtime_core.Core,
  outbound: wire.OutboundOperation,
  sequence: Int,
) -> document.SequencedDocumentMessage {
  let assert Ok(contents) =
    json.parse(json.to_string(outbound.contents), decode.dynamic)
  let metadata = case outbound.metadata {
    None -> None
    Some(value) -> {
      let assert Ok(value) = json.parse(json.to_string(value), decode.dynamic)
      Some(value)
    }
  }
  document.SequencedDocumentMessage(
    client_id: Some(sender.client_id),
    client_sequence_number: outbound.client_sequence_number,
    contents: contents,
    metadata: metadata,
    minimum_sequence_number: 0,
    reference_sequence_number: outbound.reference_sequence_number,
    sequence_number: sequence,
    message_type: "op",
    server_metadata: None,
    origin: None,
    traces: None,
    data: None,
    timestamp: 0,
  )
}

fn point() -> types.TreeValue {
  types.ObjectValue("org.watershed.shared-tree.m3.Point", [
    #("label", types.StringValue("equal")),
    #("x", types.NumberValue(1.0)),
  ])
}

pub fn shared_tree_array_empty_edits_preserve_runtime_submission_test() {
  let before = core()
  let edits = [
    types.ArrayInsert([], 2, []),
    types.ArrayRemove([], 1, 1),
    types.ArrayMove([], 1, 1, [], 0),
  ]
  list.each(edits, fn(edit) {
    runtime_core.submit_tree_edits(before, "A/_C", [edit])
    |> expect.to_equal(Ok(#(before, [], [])))
  })
  runtime_core.submit_tree_edits(before, "A/_C", edits)
  |> expect.to_equal(Ok(#(before, [], [])))
}

pub fn shared_tree_array_empty_authoring_does_not_allocate_revision_test() {
  let core = core()
  let assert Ok(channel.TreeState(state)) = dict.get(core.channels, "A/_C")
  let assert Some(compressor) = core.compressor
  let assert Ok(#(after, commit, events, allocated)) =
    tree_runtime.author_edit(state, types.ArrayInsert([], 0, []), compressor)
  after |> expect.to_equal(state)
  commit |> expect.to_equal(None)
  events.events |> expect.to_equal([])
  allocated |> expect.to_equal(compressor)
}

pub fn shared_tree_array_empty_invalid_batch_is_atomic_test() {
  let original = core()
  let real = types.ArrayInsert([], 0, [types.StringValue("C")])
  let invalid = [
    types.ArrayInsert([], 4, []),
    types.ArrayRemove([], 4, 4),
    types.ArrayMove([], 0, 0, [], 4),
    types.ArrayMove([], 0, 0, ["0"], 0),
    types.ArrayInsert(["missing"], 0, []),
    types.ArrayRemove([], 0, 9_007_199_254_740_992),
  ]
  list.each(invalid, fn(edit) {
    runtime_core.submit_tree_edits(original, "A/_C", [real, edit])
    |> expect.to_be_error()
    runtime_core.submit_tree_edits(original, "A/_C", [real])
    |> expect.to_equal(runtime_core.submit_tree_edits(core(), "A/_C", [real]))
  })
}

pub fn shared_tree_array_mixed_noops_preserve_real_commit_order_test() {
  let before = core()
  let insert = types.ArrayInsert([], 0, [types.StringValue("C")])
  let remove = types.ArrayRemove([], 2, 3)
  runtime_core.submit_tree_edits(before, "A/_C", [
    types.ArrayRemove([], 1, 1),
    insert,
    types.ArrayInsert([], 3, []),
    remove,
    types.ArrayMove([], 0, 0, [], 2),
  ])
  |> expect.to_equal(
    runtime_core.submit_tree_edits(before, "A/_C", [insert, remove]),
  )
}

pub fn shared_tree_array_empty_edits_leave_compressor_creation_range_test() {
  let core = core()
  let assert Some(compressor) = core.compressor
  let assert Ok(#(compressor, _)) = fluid_ids.generate(compressor)
  let before = runtime_core.Core(..core, compressor: Some(compressor))
  runtime_core.submit_tree_edits(before, "A/_C", [types.ArrayRemove([], 0, 0)])
  |> expect.to_equal(Ok(#(before, [], [])))
}

pub fn shared_tree_array_equal_value_moves_emit_once_locally_and_remotely_test() {
  let root = types.ArrayValue(items_type, [point(), point(), point()])
  list.each(
    [
      #(types.ArrayMove([], 1, 2, [], 3), ["0", "2", "1"]),
      #(types.ArrayMove([], 0, 3, [], 1), ["0", "1", "2"]),
    ],
    fn(entry) {
      let writer =
        core_for("writer", "30000000-0000-4000-8000-000000000003", root)
      let reader =
        core_for("reader", "50000000-0000-4000-8000-000000000005", root)
      let before = state(writer)
      let references =
        list.map(["0", "1", "2"], fn(index) {
          tree_kernel.reference_at(before, [index]) |> expect.to_be_ok()
        })
      let assert Some(compressor) = writer.compressor
      let assert Ok(#(_, Some(_), events, _)) =
        tree_runtime.author_edit(before, entry.0, compressor)
      events.events |> expect.to_equal([tree_kernel.TreeChanged(True)])
      let assert Ok(#(pending, local, [outbound])) =
        runtime_core.submit_tree_edits(writer, "A/_C", [entry.0])
      local
      |> expect.to_equal([
        #("A/_C", channel.TreeEvent(tree_kernel.TreeChanged(True))),
      ])
      list.map(entry.1, fn(index) {
        tree_kernel.reference_at(state(pending), [index]) |> expect.to_be_ok()
      })
      |> expect.to_equal(references)
      tree_kernel.read(state(pending), []) |> expect.to_equal(Ok(Some(root)))
      let wire = message(writer, outbound, 1)
      let assert Ok(#(received, incoming)) =
        runtime_core.handle_sequenced(reader, wire)
      incoming.events
      |> expect.to_equal([
        #("A/_C", channel.TreeEvent(tree_kernel.TreeChanged(False))),
      ])
      tree_kernel.read(state(received), []) |> expect.to_equal(Ok(Some(root)))
      let assert Ok(#(settled, acknowledged)) =
        runtime_core.handle_sequenced(pending, wire)
      acknowledged.events |> expect.to_equal([])
      tree_kernel.history_view(state(settled)).pending |> expect.to_equal([])
      let assert Ok(#(_, duplicate)) =
        runtime_core.handle_sequenced(received, wire)
      duplicate.events |> expect.to_equal([])
    },
  )
}

pub fn shared_tree_array_net_zero_batch_still_emits_one_event_test() {
  let writer = core()
  let root =
    types.ArrayValue(items_type, [
      types.StringValue("A"),
      types.StringValue("B"),
    ])
  let reader = core_for("reader", "50000000-0000-4000-8000-000000000005", root)
  let assert Ok(#(pending, events, [outbound])) =
    runtime_core.submit_tree_edits(writer, "A/_C", [
      types.ArrayInsert([], 1, [types.StringValue("C")]),
      types.ArrayRemove([], 1, 2),
    ])
  tree_kernel.read(state(pending), []) |> expect.to_equal(Ok(Some(root)))
  events
  |> expect.to_equal([
    #("A/_C", channel.TreeEvent(tree_kernel.TreeChanged(True))),
  ])
  let assert Ok(#(received, incoming)) =
    runtime_core.handle_sequenced(reader, message(writer, outbound, 1))
  tree_kernel.read(state(received), []) |> expect.to_equal(Ok(Some(root)))
  incoming.events
  |> expect.to_equal([
    #("A/_C", channel.TreeEvent(tree_kernel.TreeChanged(False))),
  ])
}

pub fn shared_tree_array_kernel_reads_pending_elements_test() {
  let original = core()
  let assert Ok(#(pending, _, _)) =
    runtime_core.submit_tree_edits(original, "A/_C", [
      types.ArrayInsert([], 1, [types.NullValue, point()]),
    ])
  tree_kernel.array_values(state(pending), [])
  |> expect.to_equal(
    Ok([
      types.StringValue("A"),
      types.NullValue,
      point(),
      types.StringValue("B"),
    ]),
  )
  tree_kernel.array_get(state(pending), [], 1)
  |> expect.to_equal(Ok(Some(types.NullValue)))
  tree_kernel.array_get(state(pending), [], 4) |> expect.to_equal(Ok(None))
  tree_kernel.array_get(state(pending), [], -1) |> expect.to_be_error()
  tree_kernel.array_get(state(pending), [], 9_007_199_254_740_992)
  |> expect.to_be_error()
  tree_kernel.array_values(state(pending), ["0"]) |> expect.to_be_error()
  tree_kernel.array_values(state(pending), ["4"]) |> expect.to_be_error()
  tree_kernel.snapshot(state(pending))
  |> expect.to_equal(tree_kernel.snapshot(state(original)))
}

pub fn shared_tree_array_nested_moves_preserve_empty_policy_and_events_test() {
  let root =
    types.ArrayValue(items_type, [
      types.ArrayValue(items_type, [point(), point()]),
      types.ArrayValue(items_type, []),
    ])
  let writer = core_for("writer", "30000000-0000-4000-8000-000000000003", root)
  runtime_core.submit_tree_edits(writer, "A/_C", [
    types.ArrayMove(["0"], 1, 1, ["1"], 0),
  ])
  |> expect.to_equal(Ok(#(writer, [], [])))
  let assert Ok(#(pending, events, [outbound])) =
    runtime_core.submit_tree_edits(writer, "A/_C", [
      types.ArrayMove(["0"], 0, 1, ["0"], 2),
    ])
  events
  |> expect.to_equal([
    #("A/_C", channel.TreeEvent(tree_kernel.TreeChanged(True))),
  ])
  tree_kernel.read(state(pending), []) |> expect.to_equal(Ok(Some(root)))
  let reader = core_for("reader", "50000000-0000-4000-8000-000000000005", root)
  let assert Ok(#(_, incoming)) =
    runtime_core.handle_sequenced(reader, message(writer, outbound, 1))
  incoming.events
  |> expect.to_equal([
    #("A/_C", channel.TreeEvent(tree_kernel.TreeChanged(False))),
  ])
}
