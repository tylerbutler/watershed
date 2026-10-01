import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import spillway/types as document
import startest/expect
import watershed/channel
import watershed/fluid_ids
import watershed/runtime_core
import watershed/tree/array_fixture
import watershed/tree/change
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/runtime as tree_runtime
import watershed/tree/runtime_fixture
import watershed/tree/shared_change
import watershed/tree/transaction
import watershed/tree/types
import watershed/tree_kernel
import watershed/wire
import watershed/wire/fluid_container

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
  point_with_x(1.0)
}

fn point_with_x(x: Float) -> types.TreeValue {
  types.ObjectValue("org.watershed.shared-tree.m3.Point", [
    #("label", types.StringValue("equal")),
    #("x", types.NumberValue(x)),
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

pub fn shared_tree_array_transaction_net_zero_mutation_still_emits_event_test() {
  let writer = core()
  let before = state(writer)
  let assert Some(compressor) = writer.compressor
  let assert Ok(value) = transaction.begin(before, compressor, [])
  let assert Ok(value) =
    transaction.apply_edit(
      value,
      types.ArrayInsert([], 1, [types.StringValue("C")]),
    )
  let assert Ok(value) =
    transaction.apply_edit(value, types.ArrayRemove([], 1, 2))
  tree_kernel.read(transaction.state(value), [])
  |> expect.to_equal(tree_kernel.read(before, []))
  let assert Ok(#(transaction.Commit(after, _, _), events)) =
    transaction.finish(value)
  tree_kernel.read(after, []) |> expect.to_equal(tree_kernel.read(before, []))
  events
  |> expect.to_equal(tree_kernel.ChangeEvents(
    [tree_kernel.TreeChanged(True)],
    True,
  ))
}

pub fn shared_tree_array_transaction_edits_newly_inserted_node_test() {
  let writer = core()
  let assert Some(compressor) = writer.compressor
  let assert Ok(value) = transaction.begin(state(writer), compressor, [])
  let assert Ok(value) =
    transaction.apply_edit(value, types.ArrayInsert([], 1, [point()]))
  let assert Ok(value) =
    transaction.apply_edit(
      value,
      types.SetField(["1", "x"], types.NumberValue(7.0)),
    )
  tree_kernel.read(transaction.state(value), ["1", "x"])
  |> expect.to_equal(Ok(Some(types.NumberValue(7.0))))
  let assert Ok(#(transaction.Commit(after, _, _), _)) =
    transaction.finish(value)
  tree_kernel.read(after, ["1", "x"])
  |> expect.to_equal(Ok(Some(types.NumberValue(7.0))))
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

fn root(core: runtime_core.Core) -> types.TreeValue {
  let assert Ok(Some(root)) = tree_kernel.read(state(core), [])
  root
}

fn sequenced_root(core: runtime_core.Core) -> types.TreeValue {
  let assert Ok(snapshot) = tree_kernel.snapshot(state(core))
  let #(_, forest, _) = tree_kernel.snapshot_parts(snapshot)
  let assert Some(root) = forest.root
  root
}

fn deliver(
  writer: runtime_core.Core,
  reader: runtime_core.Core,
  message: document.SequencedDocumentMessage,
) -> #(runtime_core.Core, runtime_core.Core) {
  let assert Ok(#(writer, writer_update)) =
    runtime_core.handle_sequenced(writer, message)
  let assert Ok(#(reader, reader_update)) =
    runtime_core.handle_sequenced(reader, message)
  case message.message_type, message.client_id {
    "op", Some(id) if id == writer.client_id ->
      writer_update.events |> expect.to_equal([])
    "op", Some(id) if id == reader.client_id ->
      reader_update.events |> expect.to_equal([])
    "noop", _ -> {
      writer_update.events |> expect.to_equal([])
      reader_update.events |> expect.to_equal([])
    }
    _, _ -> panic as "unexpected test message"
  }
  #(writer, reader)
}

pub fn shared_tree_array_pending_chain_reconciles_both_ack_orders_test() {
  let a = types.StringValue("A")
  let b = types.StringValue("B")
  let remote_value = types.StringValue("remote")
  let initial = types.ArrayValue(items_type, [a, b])
  let authored = [
    #(
      types.ArrayInsert([], 1, [point(), point(), point()]),
      types.ArrayValue(items_type, [a, point(), point(), point(), b]),
    ),
    #(
      types.ArrayMove([], 1, 3, [], 5),
      types.ArrayValue(items_type, [a, point(), b, point(), point()]),
    ),
    #(
      types.SetField(["3", "x"], types.NumberValue(9.0)),
      types.ArrayValue(items_type, [a, point(), b, point_with_x(9.0), point()]),
    ),
  ]
  list.each([False, True], fn(grouped) {
    list.each([False, True], fn(remote_first) {
      let writer = core()
      let reader =
        core_for("reader", "50000000-0000-4000-8000-000000000005", initial)
      let assert Ok(final) = list.last(authored)
      let groups = case grouped {
        True -> [#(list.map(authored, fn(entry) { entry.0 }), final.1)]
        False -> list.map(authored, fn(entry) { #([entry.0], entry.1) })
      }
      let #(pending, outbounds) =
        list.fold(groups, #(writer, []), fn(acc, group) {
          let assert Ok(#(pending, _, [outbound])) =
            runtime_core.submit_tree_edits(acc.0, "A/_C", group.0)
          root(pending) |> expect.to_equal(group.1)
          sequenced_root(pending) |> expect.to_equal(initial)
          #(pending, list.append(acc.1, [outbound]))
        })
      tree_kernel.history_view(state(pending)).pending
      |> list.length
      |> expect.to_equal(3)
      let pending_revisions =
        tree_kernel.history_view(state(pending)).pending
        |> list.map(fn(commit) { commit.revision })
      let assert Ok(moved_reference) =
        tree_kernel.reference_at(state(pending), ["3"])
      let assert Ok(#(reader, _, [remote])) =
        runtime_core.submit_tree_edits(reader, "A/_C", [
          types.ArrayInsert([], 0, [remote_value]),
        ])
      let #(pending, reader, sequence) = case remote_first {
        False -> #(pending, reader, 0)
        True -> {
          let #(pending, reader) =
            deliver(pending, reader, message(reader, remote, 1))
          let assert types.ArrayValue(_, visible) = root(pending)
          visible
          |> expect.to_equal([
            remote_value,
            a,
            point(),
            b,
            point_with_x(9.0),
            point(),
          ])
          sequenced_root(pending)
          |> expect.to_equal(types.ArrayValue(items_type, [remote_value, a, b]))
          tree_kernel.history_view(state(pending)).pending
          |> list.map(fn(commit) { commit.revision })
          |> expect.to_equal(pending_revisions)
          #(pending, reader, 1)
        }
      }
      let gap =
        document.SequencedDocumentMessage(
          ..message(reader, remote, sequence + 1),
          message_type: "noop",
          client_id: None,
        )
      let #(pending, reader) = deliver(pending, reader, gap)
      let #(pending, reader, sequence, acknowledged) =
        list.fold(
          list.zip(outbounds, groups),
          #(pending, reader, sequence + 1, 0),
          fn(acc, group) {
            let #(pending, reader, sequence, acknowledged) = acc
            let #(pending, reader) =
              deliver(pending, reader, message(writer, group.0, sequence + 1))
            let acknowledged = acknowledged + list.length(group.1.0)
            tree_kernel.history_view(state(pending)).pending
            |> list.map(fn(commit) { commit.revision })
            |> expect.to_equal(list.drop(pending_revisions, acknowledged))
            let assert types.ArrayValue(_, expected) = group.1.1
            let expected = case remote_first {
              True -> [remote_value, ..expected]
              False -> expected
            }
            sequenced_root(pending)
            |> expect.to_equal(types.ArrayValue(items_type, expected))
            sequenced_root(reader) |> expect.to_equal(sequenced_root(pending))
            #(pending, reader, sequence + 1, acknowledged)
          },
        )
      acknowledged |> expect.to_equal(3)
      let #(settled, reader) = case remote_first {
        True -> #(pending, reader)
        False -> deliver(pending, reader, message(reader, remote, sequence + 1))
      }
      root(settled)
      |> expect.to_equal(
        types.ArrayValue(items_type, [
          remote_value,
          a,
          point(),
          b,
          point_with_x(9.0),
          point(),
        ]),
      )
      root(reader) |> expect.to_equal(root(settled))
      sequenced_root(settled) |> expect.to_equal(root(settled))
      tree_kernel.reference_at(state(settled), ["4"])
      |> expect.to_equal(Ok(moved_reference))
      tree_kernel.read_reference(state(settled), moved_reference)
      |> expect.to_equal(Ok(point_with_x(9.0)))
      settled.in_flight |> expect.to_equal([])
      reader.in_flight |> expect.to_equal([])
      tree_kernel.history_view(state(settled)).sequenced.trunk
      |> list.length
      |> expect.to_equal(4)
    })
  })
}

pub fn shared_tree_array_reconnect_keeps_moves_across_interrupted_catchup_test() {
  let writer = core()
  let initial = root(writer)
  let reader =
    core_for("reader", "50000000-0000-4000-8000-000000000005", initial)
  let assert Ok(#(inserted, _, [accepted])) =
    runtime_core.submit_tree_edits(writer, "A/_C", [
      types.ArrayInsert([], 1, [point(), point()]),
    ])
  let assert Ok(moved_reference) =
    tree_kernel.reference_at(state(inserted), ["1"])
  let assert Ok(removed_reference) =
    tree_kernel.reference_at(state(inserted), ["3"])
  let assert Ok(#(pending, _, [_])) =
    runtime_core.submit_tree_edits(inserted, "A/_C", [
      types.ArrayMove([], 1, 3, [], 4),
      types.ArrayRemove([], 1, 2),
    ])
  let assert [_, original_batch] = pending.in_flight
  let pending_revisions =
    tree_kernel.history_view(state(pending)).pending
    |> list.drop(1)
    |> list.map(fn(commit) { commit.revision })
  let old_ack = message(writer, accepted, 1)
  let assert Ok(#(reader, _)) = runtime_core.handle_sequenced(reader, old_ack)
  let assert Ok(#(reader, _, [remote])) =
    runtime_core.submit_tree_edits(reader, "A/_C", [
      types.SetField(["1", "x"], types.NumberValue(7.0)),
      types.ArrayInsert([], 0, [types.StringValue("remote")]),
    ])
  let remote_message = message(reader, remote, 2)
  let first_rejoin =
    runtime_core.adopt_reconnect(
      pending,
      runtime_fixture.connected("first-rejoin", [], 2),
    )
  let assert Ok(#(caught_up_once, ack)) =
    runtime_core.handle_sequenced(first_rejoin, old_ack)
  ack.events |> expect.to_equal([])
  list.length(caught_up_once.in_flight) |> expect.to_equal(1)
  runtime_core.reconnect_ready(caught_up_once, 2) |> expect.to_equal(False)
  let second_rejoin =
    runtime_core.adopt_reconnect(
      caught_up_once,
      runtime_fixture.connected("second-rejoin", [], 5),
    )
  runtime_core.catch_up_from(second_rejoin, 5) |> expect.to_equal(Some(1))
  let old_leave =
    document.SequencedDocumentMessage(
      ..old_ack,
      message_type: "leave",
      client_id: None,
      sequence_number: 3,
      data: Some(json.to_string(json.string(writer.client_id))),
    )
  let first_leave =
    document.SequencedDocumentMessage(
      ..old_leave,
      sequence_number: 4,
      data: Some(json.to_string(json.string("first-rejoin"))),
    )
  let joined =
    document.SequencedDocumentMessage(
      ..old_leave,
      message_type: "join",
      sequence_number: 5,
      data: Some("{\"clientId\":\"second-rejoin\",\"detail\":{}}"),
    )
  let assert Ok(#(buffered, waiting)) =
    runtime_core.handle_sequenced(second_rejoin, first_leave)
  waiting.events |> expect.to_equal([])
  buffered.channels |> expect.to_equal(second_rejoin.channels)
  buffered.compressor |> expect.to_equal(second_rejoin.compressor)
  buffered.last_seen_sequence_number |> expect.to_equal(1)
  let assert Ok(#(rebased, incoming)) =
    runtime_core.handle_sequenced(buffered, remote_message)
  incoming.events
  |> expect.to_equal([
    #("A/_C", channel.TreeEvent(tree_kernel.TreeChanged(False))),
  ])
  let expected =
    types.ArrayValue(items_type, [
      types.StringValue("remote"),
      types.StringValue("A"),
      point_with_x(7.0),
      point(),
    ])
  root(rebased) |> expect.to_equal(expected)
  tree_kernel.reference_at(state(rebased), ["2"])
  |> expect.to_equal(Ok(moved_reference))
  tree_kernel.read_reference(state(rebased), removed_reference)
  |> expect.to_equal(Ok(types.StringValue("B")))
  tree_kernel.ensure_attached(state(rebased), removed_reference)
  |> expect.to_be_error()
  let assert Ok(#(closed, _)) =
    runtime_core.handle_sequenced(rebased, old_leave)
  closed.last_seen_sequence_number |> expect.to_equal(4)
  runtime_core.reconnect_ready(closed, 5) |> expect.to_equal(False)
  let assert Ok(#(caught_up, _)) = runtime_core.handle_sequenced(closed, joined)
  runtime_core.reconnect_ready(caught_up, 5) |> expect.to_equal(True)
  let assert Ok(#(resubmitted, [resent])) =
    runtime_core.resubmit(runtime_core.go_live(caught_up))
  resubmitted.channels |> expect.to_equal(caught_up.channels)
  tree_kernel.history_view(state(resubmitted)).pending
  |> list.map(fn(commit) { commit.revision })
  |> expect.to_equal(pending_revisions)
  let assert [new_batch] = resubmitted.in_flight
  let assert runtime_core.InFlightBatch(batch_id: original_id, ..) =
    original_batch
  let assert runtime_core.InFlightBatch(batch_id: new_id, ..) = new_batch
  new_id |> expect.to_equal(original_id)
  resent.reference_sequence_number |> expect.to_equal(5)
  let reader =
    list.fold(
      [remote_message, old_leave, first_leave, joined],
      reader,
      fn(reader, message) {
        let assert Ok(#(reader, _)) =
          runtime_core.handle_sequenced(reader, message)
        reader
      },
    )
  let #(settled, reader) =
    deliver(resubmitted, reader, message(resubmitted, resent, 6))
  root(settled) |> expect.to_equal(expected)
  root(reader) |> expect.to_equal(expected)
  sequenced_root(settled) |> expect.to_equal(expected)
  settled.in_flight |> expect.to_equal([])
  tree_kernel.history_view(state(settled)).pending |> expect.to_equal([])
  tree_kernel.reference_at(state(settled), ["2"])
  |> expect.to_equal(Ok(moved_reference))
  tree_kernel.read_reference(state(settled), removed_reference)
  |> expect.to_equal(Ok(types.StringValue("B")))
}

pub fn shared_tree_array_repair_uses_each_sequenced_predecessor_test() {
  let initial =
    types.ArrayValue(items_type, [
      types.StringValue("A"),
      types.StringValue("B"),
      point(),
    ])
  let writer =
    core_for("writer", "30000000-0000-4000-8000-000000000003", initial)
  let reader =
    core_for("reader", "50000000-0000-4000-8000-000000000005", initial)
  let assert Ok(reference) = tree_kernel.reference_at(state(writer), ["2"])
  let assert Ok(#(pending, _, [_])) =
    runtime_core.submit_tree_edits(writer, "A/_C", [
      types.ArrayMove([], 2, 3, [], 0),
      types.SetField(["0", "x"], types.NumberValue(7.0)),
    ])
  let replacement =
    types.ArrayValue(items_type, [types.StringValue("replacement")])
  let assert Ok(#(reader, _, [remote])) =
    runtime_core.submit_tree_edits(reader, "A/_C", [
      types.SetField([], replacement),
    ])
  let #(rebased, reader) = deliver(pending, reader, message(reader, remote, 1))
  root(rebased) |> expect.to_equal(replacement)
  tree_kernel.ensure_attached(state(rebased), reference) |> expect.to_be_error()
  tree_kernel.read_reference(state(rebased), reference)
  |> expect.to_equal(Ok(point_with_x(7.0)))
  let window =
    document.SequencedDocumentMessage(
      ..message(reader, remote, 2),
      message_type: "noop",
      client_id: None,
      minimum_sequence_number: 1,
    )
  let #(advanced, reader) = deliver(rebased, reader, window)
  tree_kernel.history_view(state(advanced)).pending
  |> list.length
  |> expect.to_equal(2)
  let assert Ok([move, edit]) = tree_kernel.resubmit_commits(state(advanced))
  refreshers(move.change)
  |> list.flat_map(fn(build) { build.trees })
  |> expect.to_equal([initial])
  refreshers(edit.change)
  |> list.flat_map(fn(build) { build.trees })
  |> expect.to_equal([
    types.ArrayValue(items_type, [
      point(),
      types.StringValue("A"),
      types.StringValue("B"),
    ]),
  ])
  let reconnected =
    runtime_core.adopt_reconnect(
      advanced,
      runtime_fixture.connected("rejoined", [], 2),
    )
  let assert Ok(#(resubmitted, [resent])) =
    runtime_core.resubmit(runtime_core.go_live(reconnected))
  let incoming =
    document.SequencedDocumentMessage(
      ..message(resubmitted, resent, 3),
      minimum_sequence_number: 1,
    )
  let #(settled, reader) = deliver(resubmitted, reader, incoming)
  root(settled) |> expect.to_equal(replacement)
  root(reader) |> expect.to_equal(replacement)
  tree_kernel.history_view(state(settled)).pending |> expect.to_equal([])
  tree_kernel.read_reference(state(settled), reference)
  |> expect.to_equal(Ok(point_with_x(7.0)))
}

fn refreshers(value: shared_change.Changeset) -> List(forest.Build) {
  value
  |> shared_change.to_changes
  |> list.flat_map(fn(item) {
    case item {
      shared_change.DataChange(value) -> change.to_data(value).refreshers
      shared_change.SchemaChange(_, _, _) -> []
    }
  })
}

pub fn shared_tree_array_bad_last_batch_child_preserves_runtime_state_test() {
  let writer = core()
  let reader =
    core_for("reader", "50000000-0000-4000-8000-000000000005", root(writer))
  let assert Ok(#(_, _, [outbound])) =
    runtime_core.submit_tree_edits(writer, "A/_C", [
      types.ArrayMove([], 0, 1, [], 2),
      types.ArrayInsert([], 0, [point(), point()]),
    ])
  let assert Ok(batch) =
    fluid_container.decode(outbound.contents, outbound.metadata)
  let assert [allocation, first, last] = batch.messages
  let assert fluid_container.ChannelOperation(route, contents) = last.kind
  let encoded = json.to_string(contents)
  let corrupt = string.replace(encoded, "\"count\":2", "\"count\":0")
  corrupt |> expect.to_not_equal(encoded)
  let assert Ok(corrupt) = json.parse(corrupt, wire.json_value_decoder())
  let assert Ok(contents) =
    fluid_container.encode_batch(
      fluid_container.DecodedBatch(..batch, messages: [
        allocation,
        first,
        fluid_container.ContainerMessage(
          ..last,
          kind: fluid_container.ChannelOperation(route, corrupt),
        ),
      ]),
    )
  let corrupt_message =
    message(writer, wire.OutboundOperation(..outbound, contents:), 1)
  let assert Error(runtime_core.TreeOperationFailed("A/_C", _)) =
    runtime_core.handle_sequenced(reader, corrupt_message)
  let valid = message(writer, outbound, 1)
  let assert Ok(#(received, result)) =
    runtime_core.handle_sequenced(reader, valid)
  let control =
    core_for("reader", "50000000-0000-4000-8000-000000000005", root(writer))
  runtime_core.handle_sequenced(control, valid)
  |> expect.to_equal(Ok(#(received, result)))
  root(received)
  |> expect.to_equal(
    types.ArrayValue(items_type, [
      point(),
      point(),
      types.StringValue("B"),
      types.StringValue("A"),
    ]),
  )
  tree_kernel.history_view(state(received)).sequenced.trunk
  |> list.length
  |> expect.to_equal(2)
  result.events
  |> expect.to_equal([
    #("A/_C", channel.TreeEvent(tree_kernel.TreeChanged(False))),
  ])
}
