import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import spillway/types
import startest/expect
import watershed/channel
import watershed/fluid_ids
import watershed/runtime_core
import watershed/tree/identifier_fixture
import watershed/tree/runtime_fixture
import watershed/tree/types as tree_types
import watershed/tree_kernel
import watershed/wire

const address = "A/_C"

fn identifier_core(client_id: String, session_id: String) -> runtime_core.Core {
  let input =
    identifier_fixture.full_seed_input(
      identifier_fixture.full_root(
        identifier_fixture.point("child", "child"),
        [],
        [],
        [],
      ),
    )
  let assert Some(compressor) = input.compressor
  let serialized = fluid_ids.serialize(compressor, False) |> expect.to_be_ok
  let session = fluid_ids.session_id(session_id) |> expect.to_be_ok
  let compressor = fluid_ids.deserialize(serialized, session) |> expect.to_be_ok
  let seed =
    runtime_core.bootstrap_seed(
      runtime_core.BootstrapSeedInput(..input, compressor: Some(compressor)),
    )
    |> expect.to_be_ok
  let assert runtime_core.Complete(core) =
    runtime_core.bootstrap_seeded(
      runtime_fixture.connected(client_id, [], 0),
      seed,
    )
    |> expect.to_be_ok
  core
}

fn sequenced(
  outbound: wire.OutboundOperation,
  client_id: String,
  sequence_number: Int,
  minimum_sequence_number: Int,
) -> types.SequencedDocumentMessage {
  let contents =
    json.parse(json.to_string(outbound.contents), decode.dynamic)
    |> expect.to_be_ok
  let metadata = case outbound.metadata {
    None -> None
    Some(value) ->
      json.parse(json.to_string(value), decode.dynamic)
      |> expect.to_be_ok
      |> Some
  }
  types.SequencedDocumentMessage(
    client_id: Some(client_id),
    sequence_number: sequence_number,
    minimum_sequence_number: minimum_sequence_number,
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

fn applied_revision(
  events: List(runtime_core.ScopedTreeEvent),
) -> fluid_ids.StableId {
  events
  |> list.find_map(fn(event) {
    case event.2 {
      channel.TreeCommitApplied(revision, _, _, _) -> Ok(revision)
      _ -> Error(Nil)
    }
  })
  |> expect.to_be_ok
}

fn trunk_length(core: runtime_core.Core) -> Int {
  let assert Ok(channel.TreeState(state)) = dict.get(core.channels, address)
  tree_kernel.history_view(state).sequenced.trunk |> list.length
}

pub fn local_branch_msn_preserves_fork_and_revertible_repair_test() {
  let core =
    identifier_core("retention", "30000000-0000-4000-8000-000000000003")
  let assert #(core, base_events, [base_outbound]) =
    runtime_core.submit_tree_edits_on(
      core,
      address,
      tree_types.DocumentCheckout,
      [
        tree_types.SetField(
          ["child", "label"],
          tree_types.StringValue("retained-base"),
        ),
      ],
    )
    |> expect.to_be_ok
  let #(core, document_revertible) =
    runtime_core.retain_tree_revertible_on(
      core,
      address,
      tree_types.DocumentCheckout,
      applied_revision(base_events),
      tree_types.DefaultCommit,
    )
    |> expect.to_be_ok
  let #(core, _) =
    runtime_core.handle_sequenced(
      core,
      sequenced(base_outbound, core.client_id, 1, 0),
    )
    |> expect.to_be_ok
  let #(core, parent_id) =
    runtime_core.fork_tree(
      core,
      address,
      tree_types.DocumentCheckout,
      identifier_fixture.full_view(),
    )
    |> expect.to_be_ok
  let parent = tree_types.LocalCheckout(parent_id)
  let assert #(core, parent_events, []) =
    runtime_core.submit_tree_edits_on(core, address, parent, [
      tree_types.SetField(
        ["child", "label"],
        tree_types.StringValue("parent-repair"),
      ),
    ])
    |> expect.to_be_ok
  let parent_revision = applied_revision(parent_events)
  let #(core, child_id) =
    runtime_core.fork_tree(
      core,
      address,
      parent,
      identifier_fixture.full_view(),
    )
    |> expect.to_be_ok
  let child = tree_types.LocalCheckout(child_id)
  let #(core, child_revertible) =
    runtime_core.retain_tree_revertible_on(
      core,
      address,
      child,
      parent_revision,
      tree_types.DefaultCommit,
    )
    |> expect.to_be_ok
  let #(core, sibling_id) =
    runtime_core.fork_tree(
      core,
      address,
      tree_types.DocumentCheckout,
      identifier_fixture.full_view(),
    )
    |> expect.to_be_ok
  let sibling = tree_types.LocalCheckout(sibling_id)

  let assert #(core, _, [second]) =
    runtime_core.submit_tree_edits(core, address, [
      tree_types.SetField(
        ["child", "label"],
        tree_types.StringValue("main-second"),
      ),
    ])
    |> expect.to_be_ok
  let #(core, _) =
    runtime_core.handle_sequenced(core, sequenced(second, core.client_id, 2, 2))
    |> expect.to_be_ok
  #("pinned trunk", trunk_length(core) >= 2)
  |> expect.to_equal(#("pinned trunk", True))

  let core =
    runtime_core.dispose_tree_branch(core, address, parent)
    |> expect.to_be_ok
  runtime_core.tree_branch_status(core, address, child)
  |> expect.to_equal(runtime_core.BranchValid)
  runtime_core.tree_read_on(core, address, child, ["child", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("parent-repair"))))
  runtime_core.tree_revertible_is_valid_on(
    core,
    address,
    tree_types.DocumentCheckout,
    document_revertible,
  )
  |> expect.to_be_true
  runtime_core.tree_revertible_is_valid_on(
    core,
    address,
    child,
    child_revertible,
  )
  |> expect.to_be_true

  let assert #(core, _, []) =
    runtime_core.revert_tree_on(core, address, child, child_revertible)
    |> expect.to_be_ok
  runtime_core.tree_read_on(core, address, child, ["child", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("retained-base"))))
  let core =
    runtime_core.dispose_tree_revertible_on(
      core,
      address,
      tree_types.DocumentCheckout,
      document_revertible,
    )
    |> expect.to_be_ok
  let assert #(core, _, [third]) =
    runtime_core.submit_tree_edits(core, address, [
      tree_types.SetField(
        ["child", "label"],
        tree_types.StringValue("main-third"),
      ),
    ])
    |> expect.to_be_ok
  let #(core, _) =
    runtime_core.handle_sequenced(core, sequenced(third, core.client_id, 3, 3))
    |> expect.to_be_ok
  let #(core, _) =
    runtime_core.rebase_tree_onto(
      core,
      address,
      child,
      tree_types.DocumentCheckout,
    )
    |> expect.to_be_ok
  runtime_core.tree_read_on(core, address, child, ["child", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("retained-base"))))

  let before_release = trunk_length(core)
  let core =
    runtime_core.dispose_tree_branch(core, address, sibling)
    |> expect.to_be_ok
  let core =
    runtime_core.dispose_tree_branch(core, address, child)
    |> expect.to_be_ok
  let assert #(core, final_events, [final]) =
    runtime_core.submit_tree_edits_on(
      core,
      address,
      tree_types.DocumentCheckout,
      [
        tree_types.SetField(
          ["child", "label"],
          tree_types.StringValue("after-release"),
        ),
      ],
    )
    |> expect.to_be_ok
  let final_revision = applied_revision(final_events)
  let #(core, ingested) =
    runtime_core.handle_sequenced(core, sequenced(final, core.client_id, 4, 4))
    |> expect.to_be_ok
  ingested.events
  |> expect.to_equal([
    #(
      address,
      channel.TreeCommitSettled(final_revision, tree_types.FullyApplied),
    ),
  ])
  trunk_length(core) |> expect.to_equal(0)
  #("released trunk", trunk_length(core) < before_release)
  |> expect.to_equal(#("released trunk", True))
}
