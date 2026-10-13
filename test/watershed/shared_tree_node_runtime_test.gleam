import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import spillway/types
import startest/expect
import watershed/fluid_ids
import watershed/runtime_core
import watershed/tree/forest
import watershed/tree/identifier_fixture
import watershed/tree/node
import watershed/tree/runtime_fixture
import watershed/tree/schema as tree_schema
import watershed/tree/types as tree_types
import watershed/wire

fn root() -> tree_types.TreeValue {
  identifier_fixture.full_root(
    identifier_fixture.point("child", "child"),
    [
      identifier_fixture.point("first", "first"),
      identifier_fixture.point("second", "second"),
    ],
    [],
    [],
  )
}

fn core(client_id: String, session_id: String) -> runtime_core.Core {
  let input = identifier_fixture.full_seed_input(root())
  let assert Some(compressor) = input.compressor
  let serialized = fluid_ids.serialize(compressor, False) |> expect.to_be_ok()
  let session = fluid_ids.session_id(session_id) |> expect.to_be_ok()
  let compressor =
    fluid_ids.deserialize(serialized, session) |> expect.to_be_ok()
  let seed =
    runtime_core.BootstrapSeedInput(..input, compressor: Some(compressor))
    |> runtime_core.bootstrap_seed
    |> expect.to_be_ok()
  let assert runtime_core.Complete(core) =
    runtime_core.bootstrap_seeded(
      runtime_fixture.connected(client_id, [], 0),
      seed,
    )
    |> expect.to_be_ok()
  core
}

fn sequenced(
  outbound: wire.OutboundOperation,
  client_id: String,
  sequence_number: Int,
) -> types.SequencedDocumentMessage {
  let contents =
    json.parse(json.to_string(outbound.contents), decode.dynamic)
    |> expect.to_be_ok()
  let metadata = case outbound.metadata {
    None -> None
    Some(value) ->
      json.parse(json.to_string(value), decode.dynamic)
      |> expect.to_be_ok()
      |> Some
  }
  types.SequencedDocumentMessage(
    client_id: Some(client_id),
    sequence_number: sequence_number,
    minimum_sequence_number: 0,
    client_sequence_number: outbound.client_sequence_number,
    reference_sequence_number: outbound.reference_sequence_number,
    message_type: "op",
    contents: contents,
    metadata: metadata,
    server_metadata: None,
    origin: None,
    traces: None,
    timestamp: 0,
    data: None,
  )
}

fn attempt_node_edit(
  core: runtime_core.Core,
  reference: forest.NodeRef,
  view: tree_schema.ViewSchema,
) -> #(
  runtime_core.Core,
  List(runtime_core.ScopedTreeEvent),
  List(wire.OutboundOperation),
  Result(Nil, runtime_core.CoreError),
) {
  case
    runtime_core.submit_tree_node_edit_view_on(
      core,
      "A/_C",
      tree_types.DocumentCheckout,
      view,
      reference,
      node.SetField("label", tree_types.StringValue("rejected")),
    )
  {
    Ok(#(core, events, outbound)) -> #(core, events, outbound, Ok(Nil))
    Error(error) -> #(core, [], [], Error(error))
  }
}

pub fn shared_tree_node_peer_reorder_preserves_identity_and_sequenced_output_test() {
  let view = identifier_fixture.full_view()
  let reader = core("reader", "50000000-0000-4000-8000-000000000005")
  let peer = core("peer", "60000000-0000-4000-8000-000000000006")
  let reference =
    runtime_core.tree_node_reference_view_on(
      reader,
      "A/_C",
      tree_types.DocumentCheckout,
      view,
      ["left", "0"],
    )
    |> expect.to_be_ok()
    |> expect.to_be_some()
  let assert #(peer, _, [peer_outbound]) =
    runtime_core.submit_tree_edits_view_on(
      peer,
      "A/_C",
      tree_types.DocumentCheckout,
      view,
      [tree_types.ArrayMove(["left"], 0, 1, ["left"], 2)],
    )
    |> expect.to_be_ok()
  let #(reader, _) =
    runtime_core.handle_sequenced(reader, sequenced(peer_outbound, "peer", 1))
    |> expect.to_be_ok()

  runtime_core.tree_node_reference_view_on(
    reader,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    ["left", "1"],
  )
  |> expect.to_equal(Ok(Some(reference)))
  runtime_core.tree_node_read_view_on(
    reader,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    reference,
    ["label"],
  )
  |> expect.to_equal(Ok(Some(tree_types.StringValue("first"))))

  let assert #(_reader, _, [reader_outbound]) =
    runtime_core.submit_tree_node_edit_view_on(
      reader,
      "A/_C",
      tree_types.DocumentCheckout,
      view,
      reference,
      node.SetField("label", tree_types.StringValue("edited")),
    )
    |> expect.to_be_ok()
  let #(peer, _) =
    runtime_core.handle_sequenced(peer, sequenced(peer_outbound, "peer", 1))
    |> expect.to_be_ok()
  let #(peer, _) =
    runtime_core.handle_sequenced(peer, sequenced(reader_outbound, "reader", 2))
    |> expect.to_be_ok()
  runtime_core.tree_read_view_on(
    peer,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    ["left", "1", "label"],
  )
  |> expect.to_equal(Ok(Some(tree_types.StringValue("edited"))))
}

pub fn shared_tree_node_replaced_target_rejection_is_atomic_test() {
  let view = identifier_fixture.full_view()
  let core = core("reader", "50000000-0000-4000-8000-000000000005")
  let reference =
    runtime_core.tree_node_reference_view_on(
      core,
      "A/_C",
      tree_types.DocumentCheckout,
      view,
      ["left", "0"],
    )
    |> expect.to_be_ok()
    |> expect.to_be_some()
  let assert #(core, _, [_]) =
    runtime_core.submit_tree_edits_view_on(
      core,
      "A/_C",
      tree_types.DocumentCheckout,
      view,
      [
        tree_types.ArrayRemove(["left"], 0, 1),
        tree_types.ArrayInsert(["left"], 0, [
          identifier_fixture.point("replacement", "replacement"),
        ]),
      ],
    )
    |> expect.to_be_ok()
  let snapshot =
    runtime_core.tree_retained_snapshot(core, "A/_C") |> expect.to_be_ok()
  let history =
    runtime_core.tree_history_evidence(core, "A/_C") |> expect.to_be_ok()
  let assert Some(compressor) = core.compressor
  let compressor = fluid_ids.serialize(compressor, True) |> expect.to_be_ok()
  let pending = core.in_flight

  let #(after, events, outbound, outcome) =
    attempt_node_edit(core, reference, view)
  outcome |> expect.to_be_error()
  events |> expect.to_equal([])
  outbound |> expect.to_equal([])
  runtime_core.tree_retained_snapshot(after, "A/_C")
  |> expect.to_equal(Ok(snapshot))
  runtime_core.tree_history_evidence(after, "A/_C")
  |> expect.to_equal(Ok(history))
  let assert Some(current) = after.compressor
  fluid_ids.serialize(current, True) |> expect.to_equal(Ok(compressor))
  runtime_core.tree_read_view_on(
    after,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    ["left", "0", "label"],
  )
  |> expect.to_equal(Ok(Some(tree_types.StringValue("replacement"))))
  after.in_flight |> expect.to_equal(pending)
  list.length(after.in_flight) |> expect.to_equal(1)
}
