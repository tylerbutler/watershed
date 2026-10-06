import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import spillway/types
import startest/expect
import watershed/channel
import watershed/fluid_ids
import watershed/runtime_core
import watershed/tree/branch
import watershed/tree/identifier_fixture
import watershed/tree/runtime_fixture
import watershed/tree/types as tree_types
import watershed/tree_kernel
import watershed/wire
import watershed/wire/fluid_container
import watershed/wire/fluid_document

const address = "A/_C"

fn identifier_core(client_id: String, session_id: String) -> runtime_core.Core {
  let session = fluid_ids.session_id(session_id) |> expect.to_be_ok
  let view =
    fluid_ids.stable_id("10000000-0000-4000-8000-000000000001")
    |> expect.to_be_ok
  let summary =
    fluid_document.initial_tree(
      identifier_fixture.full_stored(),
      Some(
        identifier_fixture.full_root(
          identifier_fixture.point("child", "child"),
          [],
          [],
          [],
        ),
      ),
      session,
      view,
    )
    |> expect.to_be_ok
  let assert runtime_core.Complete(core) =
    runtime_core.bootstrap_document(
      runtime_fixture.connected(client_id, [], 0),
      summary,
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

fn load_summary(
  summary: fluid_document.DocumentSummary,
  client_id: String,
  session_id: String,
  view_id: String,
) -> runtime_core.Core {
  let encoded = fluid_document.encode(summary) |> expect.to_be_ok
  let session = fluid_ids.session_id(session_id) |> expect.to_be_ok
  let view = fluid_ids.stable_id(view_id) |> expect.to_be_ok
  let decoded =
    fluid_document.decode(encoded, None, session, view) |> expect.to_be_ok
  let assert runtime_core.Complete(core) =
    runtime_core.bootstrap_document(
      runtime_fixture.connected(
        client_id,
        [],
        fluid_document.sequence_number(decoded),
      ),
      decoded,
    )
    |> expect.to_be_ok
  core
}

fn pending_summary(core: runtime_core.Core) -> fluid_document.DocumentSummary {
  let channels = runtime_core.summary_channels(core) |> expect.to_be_ok
  case core.persistence {
    Some(previous) ->
      fluid_document.capture(
        previous,
        channels,
        core.compressor,
        fluid_document.CaptureRouting(
          dict.to_list(core.routing.aliases),
          dict.to_list(core.routing.datastores),
          dict.to_list(core.routing.channel_attributes),
        ),
      )
      |> expect.to_be_ok
    None ->
      fluid_document.native(
        core.last_seen_sequence_number,
        core.minimum_sequence_number,
        runtime_core.summary_members(core),
        channels,
      )
      |> expect.to_be_ok
  }
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

pub fn local_branch_reconnect_preserves_pending_origin_test() {
  let core =
    identifier_core("pending-origin", "50000000-0000-4000-8000-000000000005")
  let assert #(core, main_events, [original]) =
    runtime_core.submit_tree_edits_on(
      core,
      address,
      tree_types.DocumentCheckout,
      [
        tree_types.ArrayInsert(["right"], 0, [
          tree_types.ObjectValue(identifier_fixture.point_type, [
            #("label", tree_types.StringValue("pending-origin")),
          ]),
        ]),
      ],
    )
    |> expect.to_be_ok
  let main_revision = applied_revision(main_events)
  let assert Ok(Some(tree_types.StringValue(node_id))) =
    runtime_core.tree_read(core, address, ["right", "0", "id"])
  let #(core, branch_id) =
    runtime_core.fork_tree(
      core,
      address,
      tree_types.DocumentCheckout,
      identifier_fixture.full_view(),
    )
    |> expect.to_be_ok
  let selector = tree_types.LocalCheckout(branch_id)
  let assert Ok(forest) = dict.get(core.tree_checkouts, address)
  let checkout = branch.checkout(forest, selector) |> expect.to_be_ok
  let node_reference =
    branch.reference_at(forest, checkout, ["right", "0"]) |> expect.to_be_ok
  let local = branch.local_history(forest, checkout) |> expect.to_be_ok
  local.commits
  |> list.map(fn(commit) { commit.revision })
  |> expect.to_equal([main_revision])

  let before_branch_allocation = core.compressor
  let assert #(core, branch_events, []) =
    runtime_core.submit_tree_edits_on(core, address, selector, [
      tree_types.SetField(
        ["right", "0", "label"],
        tree_types.StringValue("branch-local"),
      ),
    ])
    |> expect.to_be_ok
  let branch_revision = applied_revision(branch_events)
  core.compressor |> expect.to_not_equal(before_branch_allocation)
  runtime_core.tree_read_on(core, address, selector, ["right", "0", "id"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue(node_id))))

  let reconnected =
    runtime_core.adopt_reconnect(
      core,
      runtime_fixture.connected("pending-origin-next", [], 0),
    )
    |> expect.to_be_ok
  let assert #(resubmitted, [resent]) =
    runtime_core.resubmit(runtime_core.go_live(reconnected))
    |> expect.to_be_ok
  let assert [runtime_core.InFlightBatch(batch_id: old_batch, ..)] =
    core.in_flight
  let assert [
    runtime_core.InFlightBatch(
      client_id: "pending-origin-next",
      batch_id: new_batch,
      ..,
    ),
  ] = resubmitted.in_flight
  new_batch |> expect.to_equal(old_batch)
  resent.reference_sequence_number |> expect.to_equal(0)
  resent.client_sequence_number
  |> expect.to_equal(reconnected.next_client_sequence_number)
  let resent_batch =
    fluid_container.decode(resent.contents, resent.metadata) |> expect.to_be_ok
  list.length(resent_batch.messages) |> expect.to_equal(3)
  resent.metadata |> expect.to_not_equal(None)
  original.metadata |> expect.to_not_equal(None)

  let assert Ok(forest) = dict.get(resubmitted.tree_checkouts, address)
  let checkout = branch.checkout(forest, selector) |> expect.to_be_ok
  branch.reference_at(forest, checkout, ["right", "0"])
  |> expect.to_equal(Ok(node_reference))
  runtime_core.tree_read_on(resubmitted, address, selector, [
    "right",
    "0",
    "label",
  ])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("branch-local"))))

  let peer =
    identifier_core("pending-peer", "60000000-0000-4000-8000-000000000006")
  let #(settled, _) =
    runtime_core.handle_sequenced(
      resubmitted,
      sequenced(resent, resubmitted.client_id, 1, 0),
    )
    |> expect.to_be_ok
  let #(peer, _) =
    runtime_core.handle_sequenced(
      peer,
      sequenced(resent, resubmitted.client_id, 1, 0),
    )
    |> expect.to_be_ok
  let assert #(merged, merge_events, [merge]) =
    runtime_core.merge_tree(
      settled,
      address,
      tree_types.DocumentCheckout,
      selector,
      False,
    )
    |> expect.to_be_ok
  applied_revision(merge_events) |> expect.to_equal(branch_revision)
  let #(merged, _) =
    runtime_core.handle_sequenced(
      merged,
      sequenced(merge, merged.client_id, 2, 0),
    )
    |> expect.to_be_ok
  let #(peer, received) =
    runtime_core.handle_sequenced(
      peer,
      sequenced(merge, merged.client_id, 2, 0),
    )
    |> expect.to_be_ok
  list.length(received.events) |> expect.to_equal(2)
  runtime_core.tree_read(merged, address, ["right", "0", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("branch-local"))))
  runtime_core.tree_read(peer, address, ["right", "0", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("branch-local"))))
}

pub fn local_branch_merge_accepted_before_drop_is_not_duplicated_test() {
  let core =
    identifier_core("accepted-author", "70000000-0000-4000-8000-000000000007")
  let #(core, branch_id) =
    runtime_core.fork_tree(
      core,
      address,
      tree_types.DocumentCheckout,
      identifier_fixture.full_view(),
    )
    |> expect.to_be_ok
  let selector = tree_types.LocalCheckout(branch_id)
  let assert #(core, branch_events, []) =
    runtime_core.submit_tree_edits_on(core, address, selector, [
      tree_types.SetField(
        ["child", "label"],
        tree_types.StringValue("accepted-before-drop"),
      ),
    ])
    |> expect.to_be_ok
  let revision = applied_revision(branch_events)
  let assert #(pending, merge_events, [outbound]) =
    runtime_core.merge_tree(
      core,
      address,
      tree_types.DocumentCheckout,
      selector,
      False,
    )
    |> expect.to_be_ok
  applied_revision(merge_events) |> expect.to_equal(revision)
  let batch =
    fluid_container.decode(outbound.contents, outbound.metadata)
    |> expect.to_be_ok
  list.length(batch.messages) |> expect.to_equal(2)
  pending.in_flight |> list.length |> expect.to_equal(1)
  runtime_core.tree_branch_status(pending, address, selector)
  |> expect.to_equal(runtime_core.BranchValid)

  let peer =
    identifier_core("accepted-peer", "80000000-0000-4000-8000-000000000008")
  let accepted = sequenced(outbound, pending.client_id, 1, 0)
  let #(peer, peer_delivery) =
    runtime_core.handle_sequenced(peer, accepted) |> expect.to_be_ok
  peer_delivery.events
  |> expect.to_equal([
    #(
      address,
      channel.TreeCommitApplied(
        revision,
        tree_types.DefaultCommit,
        False,
        False,
      ),
    ),
    #(address, channel.TreeEvent(tree_kernel.TreeChanged(False))),
  ])

  // The old identity receives the accepted operation before a new join exists.
  let #(caught_up, author_delivery) =
    runtime_core.handle_sequenced(pending, accepted) |> expect.to_be_ok
  author_delivery.events
  |> expect.to_equal([
    #(address, channel.TreeCommitSettled(revision, tree_types.FullyApplied)),
  ])
  caught_up.in_flight |> expect.to_equal([])
  trunk_length(caught_up) |> expect.to_equal(1)
  let reconnected =
    runtime_core.adopt_reconnect(
      caught_up,
      runtime_fixture.connected("accepted-author-next", [], 1),
    )
    |> expect.to_be_ok
  let assert #(ready, []) =
    runtime_core.resubmit(runtime_core.go_live(reconnected))
    |> expect.to_be_ok
  ready.in_flight |> expect.to_equal([])
  runtime_core.tree_branch_status(ready, address, selector)
  |> expect.to_equal(runtime_core.BranchValid)

  let assert #(ready, repeated_events, []) =
    runtime_core.merge_tree(
      ready,
      address,
      tree_types.DocumentCheckout,
      selector,
      False,
    )
    |> expect.to_be_ok
  repeated_events |> expect.to_equal([])
  trunk_length(ready) |> expect.to_equal(1)
  runtime_core.tree_read(ready, address, ["child", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("accepted-before-drop"))))
  runtime_core.tree_read(peer, address, ["child", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("accepted-before-drop"))))
}

pub fn local_branch_unmerged_changes_do_not_enter_summary_test() {
  let core =
    identifier_core("summary-writer", "90000000-0000-4000-8000-000000000009")
  let assert #(core, _, [main]) =
    runtime_core.submit_tree_edits(core, address, [
      tree_types.SetField(
        ["child", "label"],
        tree_types.StringValue("sequenced-main"),
      ),
    ])
    |> expect.to_be_ok
  let #(core, _) =
    runtime_core.handle_sequenced(core, sequenced(main, core.client_id, 1, 0))
    |> expect.to_be_ok
  let #(core, branch_id) =
    runtime_core.fork_tree(
      core,
      address,
      tree_types.DocumentCheckout,
      identifier_fixture.full_view(),
    )
    |> expect.to_be_ok
  let selector = tree_types.LocalCheckout(branch_id)
  let assert #(core, _, []) =
    runtime_core.submit_tree_edits_on(core, address, selector, [
      tree_types.ArrayInsert(["right"], 0, [
        tree_types.ObjectValue(identifier_fixture.point_type, [
          #("label", tree_types.StringValue("unmerged-private")),
        ]),
      ]),
    ])
    |> expect.to_be_ok
  let assert Ok(Some(tree_types.StringValue(private_id))) =
    runtime_core.tree_read_on(core, address, selector, ["right", "0", "id"])
  runtime_core.tree_read(core, address, ["right", "0"])
  |> expect.to_equal(Ok(None))

  let summary = runtime_core.capture_summary(core) |> expect.to_be_ok
  let encoded =
    fluid_document.encode(summary)
    |> expect.to_be_ok
    |> string.inspect
  string.contains(encoded, "unmerged-private") |> expect.to_be_false
  string.contains(encoded, private_id) |> expect.to_be_false
  string.contains(encoded, "LocalCheckout") |> expect.to_be_false

  let fresh =
    load_summary(
      summary,
      "summary-reader",
      "a0000000-0000-4000-8000-00000000000a",
      "b0000000-0000-4000-8000-00000000000b",
    )
  runtime_core.tree_read(fresh, address, ["child", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("sequenced-main"))))
  runtime_core.tree_read(fresh, address, ["right", "0"])
  |> expect.to_equal(Ok(None))
  runtime_core.tree_branch_status(fresh, address, selector)
  |> expect.to_equal(runtime_core.BranchDisposed)
}

pub fn local_branch_reloaded_summary_has_no_old_checkout_test() {
  let writer =
    identifier_core("tail-writer", "c0000000-0000-4000-8000-00000000000c")
  let #(writer, branch_id) =
    runtime_core.fork_tree(
      writer,
      address,
      tree_types.DocumentCheckout,
      identifier_fixture.full_view(),
    )
    |> expect.to_be_ok
  let selector = tree_types.LocalCheckout(branch_id)
  let assert #(writer, _, []) =
    runtime_core.submit_tree_edits_on(writer, address, selector, [
      tree_types.ArrayInsert(["right"], 0, [
        tree_types.ObjectValue(identifier_fixture.point_type, [
          #("label", tree_types.StringValue("pending-merge-tail")),
        ]),
      ]),
    ])
    |> expect.to_be_ok
  let assert Ok(Some(tree_types.StringValue(tail_id))) =
    runtime_core.tree_read_on(writer, address, selector, ["right", "0", "id"])
  let assert #(pending, merge_events, [tail]) =
    runtime_core.merge_tree(
      writer,
      address,
      tree_types.DocumentCheckout,
      selector,
      False,
    )
    |> expect.to_be_ok
  let merge_revision = applied_revision(merge_events)
  let summary = pending_summary(pending)
  let encoded =
    fluid_document.encode(summary)
    |> expect.to_be_ok
    |> string.inspect
  string.contains(encoded, "pending-merge-tail") |> expect.to_be_false
  string.contains(encoded, tail_id) |> expect.to_be_false
  string.contains(encoded, "LocalCheckout") |> expect.to_be_false

  let fresh =
    load_summary(
      summary,
      "tail-reader",
      "d0000000-0000-4000-8000-00000000000d",
      "e0000000-0000-4000-8000-00000000000e",
    )
  runtime_core.tree_read(fresh, address, ["right", "0"])
  |> expect.to_equal(Ok(None))
  runtime_core.tree_branch_status(fresh, address, selector)
  |> expect.to_equal(runtime_core.BranchDisposed)
  let #(after_tail, received) =
    runtime_core.handle_sequenced(
      fresh,
      sequenced(tail, pending.client_id, 1, 0),
    )
    |> expect.to_be_ok
  received.events
  |> expect.to_equal([
    #(
      address,
      channel.TreeCommitApplied(
        merge_revision,
        tree_types.DefaultCommit,
        False,
        False,
      ),
    ),
    #(address, channel.TreeEvent(tree_kernel.TreeChanged(False))),
  ])
  runtime_core.tree_read(after_tail, address, ["right", "0", "id"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue(tail_id))))
  runtime_core.tree_read(after_tail, address, ["right", "0", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("pending-merge-tail"))))
  trunk_length(after_tail) |> expect.to_equal(1)

  let merged_summary =
    runtime_core.capture_summary(after_tail) |> expect.to_be_ok
  let reloaded =
    load_summary(
      merged_summary,
      "merged-reader",
      "f0000000-0000-4000-8000-00000000000f",
      "11000000-0000-4000-8000-000000000011",
    )
  runtime_core.tree_branch_status(reloaded, address, selector)
  |> expect.to_equal(runtime_core.BranchDisposed)
  runtime_core.tree_read(reloaded, address, ["right", "0", "id"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue(tail_id))))
  let assert #(continued, continued_events, [continued_outbound]) =
    runtime_core.submit_tree_edits_on(
      reloaded,
      address,
      tree_types.DocumentCheckout,
      [
        tree_types.SetField(
          ["right", "0", "label"],
          tree_types.StringValue("continued-after-reload"),
        ),
      ],
    )
    |> expect.to_be_ok
  let continued_revision = applied_revision(continued_events)
  let #(continued, settled) =
    runtime_core.handle_sequenced(
      continued,
      sequenced(continued_outbound, continued.client_id, 2, 0),
    )
    |> expect.to_be_ok
  settled.events
  |> expect.to_equal([
    #(
      address,
      channel.TreeCommitSettled(continued_revision, tree_types.FullyApplied),
    ),
  ])
  runtime_core.tree_read(continued, address, ["right", "0", "id"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue(tail_id))))
  runtime_core.tree_read(continued, address, ["right", "0", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("continued-after-reload"))))
}
