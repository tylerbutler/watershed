import gleam/list
import gleam/option.{None, Some}
import startest/expect
import watershed/fluid_ids
import watershed/tree/change
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/schema
import watershed/tree/shared_change
import watershed/tree/types.{NumberValue, ObjectValue, SetField}

const tree_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"Point\":{\"kind\":{\"object\":{\"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]},\"y\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]}}}},\"Root\":{\"kind\":{\"object\":{\"point\":{\"kind\":\"Value\",\"types\":[\"Point\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}"

type Allocation {
  Allocation(revisions: List(fluid_ids.StableId), order: change.IdentityOrder)
}

fn session() -> fluid_ids.SessionId {
  let assert Ok(id) =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000001")
  id
}

fn peer_session() -> fluid_ids.SessionId {
  let assert Ok(id) =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000002")
  id
}

fn revision(suffix: String) -> fluid_ids.StableId {
  let assert Ok(id) =
    fluid_ids.stable_id("00000000-0000-4000-8000-0000000000" <> suffix)
  id
}

fn empty_commit(suffix: String) -> history.Commit {
  let revision = revision(suffix)
  let assert Ok(order) = change.identity_order([#(revision, -1)])
  empty_commit_with_order(revision, order)
}

fn empty_commit_with_order(
  revision: fluid_ids.StableId,
  order: change.IdentityOrder,
) -> history.Commit {
  let assert Ok(change) =
    change.from_data(change.to_data(change.empty()), order)
  history.Commit(revision, session(), shared_change.from_data(change))
}

fn repair_commit(suffix: String) -> history.Commit {
  edit_commit(suffix, session(), 7.0)
}

fn edit_commit(
  suffix: String,
  originator: fluid_ids.SessionId,
  value: Float,
) -> history.Commit {
  let commit_revision = revision(suffix)
  let assert Ok(order) = change.identity_order([#(commit_revision, -1)])
  edit_commit_with_order(commit_revision, originator, value, order)
}

fn edit_commit_with_order(
  commit_revision: fluid_ids.StableId,
  originator: fluid_ids.SessionId,
  value: Float,
  order: change.IdentityOrder,
) -> history.Commit {
  edit_field_commit_with_order(commit_revision, originator, "x", value, order)
}

fn edit_field_commit_with_order(
  commit_revision: fluid_ids.StableId,
  originator: fluid_ids.SessionId,
  field: String,
  value: Float,
  order: change.IdentityOrder,
) -> history.Commit {
  let assert Ok(stored) = schema.stored_from_string(tree_schema)
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
  let assert Ok(state) = forest.new(revision("99"), stored, Some(root))
  let assert Ok(authored) =
    change.edit(
      stored,
      state,
      commit_revision,
      SetField(["point", field], NumberValue(value)),
      order,
    )
  history.Commit(commit_revision, originator, shared_change.from_data(authored))
}

fn repair_roots(commit: history.Commit) {
  commit.change
  |> shared_change.to_changes
  |> list.flat_map(fn(item) {
    case item {
      shared_change.SchemaChange(_, _, _) -> []
      shared_change.DataChange(data) ->
        data
        |> change.to_data
        |> fn(data) { data.builds }
        |> list.map(fn(build) { build.id })
    }
  })
}

fn no_mint(state: Nil) {
  let _ = state
  panic as "unexpected rollback allocation"
}

fn mint(state: Allocation) {
  let assert [revision, ..rest] = state.revisions
  Ok(#(revision, state.order, Allocation(rest, state.order)))
}

fn commit_effects(commit: history.Commit) {
  let tagged =
    shared_change.TaggedChange(Some(commit.revision), None, commit.change)
  let composed = shared_change.compose([tagged]) |> expect.to_be_ok
  shared_change.effects(shared_change.TaggedChange(None, None, composed))
  |> expect.to_be_ok
}

fn replayed_revision_branches() {
  let replayed_revision = revision("0a")
  let target_revision = revision("0b")
  let assert Ok(order) =
    change.identity_order([
      #(replayed_revision, -2),
      #(target_revision, -1),
    ])
  let replayed =
    edit_field_commit_with_order(replayed_revision, session(), "x", 7.0, order)
  let target =
    edit_field_commit_with_order(
      target_revision,
      peer_session(),
      "y",
      9.0,
      order,
    )
  let appended =
    history.append_local(history.new(session()), replayed) |> expect.to_be_ok
  let #(sequenced, Nil) =
    history.receive(
      appended.history,
      replayed,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
    |> expect.to_be_ok
  let #(with_old, old) =
    history.fork_local(sequenced.history, types.DocumentCheckout)
    |> expect.to_be_ok
  let #(with_target, Nil) =
    history.receive(
      with_old,
      target,
      types.SequencePoint(2, 0),
      1,
      0,
      Nil,
      no_mint,
    )
    |> expect.to_be_ok
  let #(with_replay, Nil) =
    history.receive(
      with_target.history,
      replayed,
      types.SequencePoint(3, 0),
      2,
      0,
      Nil,
      no_mint,
    )
    |> expect.to_be_ok
  let #(state, current) =
    history.fork_local(with_replay.history, types.DocumentCheckout)
    |> expect.to_be_ok
  #(state, old, current, replayed, target)
}

fn replayed_revision_branches_after_original_trim() {
  let replayed_revision = revision("0a")
  let target_revision = revision("0b")
  let assert Ok(order) =
    change.identity_order([
      #(replayed_revision, -2),
      #(target_revision, -1),
    ])
  let replayed =
    edit_field_commit_with_order(replayed_revision, session(), "x", 7.0, order)
  let target =
    edit_field_commit_with_order(
      target_revision,
      peer_session(),
      "y",
      9.0,
      order,
    )
  let appended =
    history.append_local(history.new(session()), replayed) |> expect.to_be_ok
  let #(sequenced, Nil) =
    history.receive(
      appended.history,
      replayed,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
    |> expect.to_be_ok
  let #(with_target, Nil) =
    history.receive(
      sequenced.history,
      target,
      types.SequencePoint(2, 0),
      1,
      0,
      Nil,
      no_mint,
    )
    |> expect.to_be_ok
  let #(with_old, old) =
    history.fork_local(with_target.history, types.DocumentCheckout)
    |> expect.to_be_ok
  let #(with_replay, Nil) =
    history.receive(
      with_old,
      replayed,
      types.SequencePoint(3, 0),
      2,
      0,
      Nil,
      no_mint,
    )
    |> expect.to_be_ok
  let #(with_current, current) =
    history.fork_local(with_replay.history, types.DocumentCheckout)
    |> expect.to_be_ok
  let #(trimmed, Nil) =
    history.advance_minimum(with_current, 3, 3, Nil, no_mint)
    |> expect.to_be_ok
  trimmed.trimmed_revisions |> expect.to_equal([replayed.revision])
  #(trimmed.history, old, current, replayed, target)
}

pub fn local_branch_fork_pins_optimistic_head_test() -> Nil {
  let trunk = empty_commit("0a")
  let pending = repair_commit("0b")
  let assert Ok(appended) = history.append_local(history.new(session()), trunk)
  let assert Ok(#(acked, Nil)) =
    history.receive(
      appended.history,
      trunk,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  let assert Ok(optimistic) = history.append_local(acked.history, pending)
  let assert Ok(#(forked, id)) =
    history.fork_local(optimistic.history, types.DocumentCheckout)
  let assert types.LocalCheckoutId(0) = id
  let assert Ok(#(advanced, Nil)) =
    history.advance_minimum(forked, 1, 1, Nil, no_mint)

  advanced.trimmed_revisions |> expect.to_equal([])
  history.inspect(advanced.history).sequenced.trunk
  |> expect.to_equal([history.SequencedCommit(trunk, types.SequencePoint(1, 0))])
  history.inspect_local(advanced.history, id)
  |> expect.to_equal(
    Ok(history.LocalBranch(id, Some(trunk.revision), [pending])),
  )
  repair_roots(pending)
  |> list.length
  |> fn(length) { length > 0 }
  |> expect.to_equal(True)
  let assert Ok(history.LocalBranch(_, _, [retained])) =
    history.inspect_local(advanced.history, id)
  repair_roots(retained) |> expect.to_equal(repair_roots(pending))
}

pub fn local_branch_descendant_survives_parent_disposal_test() -> Nil {
  let trunk = empty_commit("0a")
  let assert Ok(appended) = history.append_local(history.new(session()), trunk)
  let assert Ok(#(acked, Nil)) =
    history.receive(
      appended.history,
      trunk,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  let assert Ok(#(with_parent, parent)) =
    history.fork_local(acked.history, types.DocumentCheckout)
  let assert Ok(#(with_child, child)) =
    history.fork_local(with_parent, types.LocalCheckout(parent))
  let assert Ok(without_parent) = history.dispose_local(with_child, parent)
  let assert Ok(#(advanced, Nil)) =
    history.advance_minimum(without_parent, 1, 1, Nil, no_mint)

  history.inspect_local(advanced.history, parent) |> expect.to_be_error()
  history.inspect_local(advanced.history, child)
  |> expect.to_equal(Ok(history.LocalBranch(child, Some(trunk.revision), [])))
  advanced.trimmed_revisions |> expect.to_equal([])

  let assert Ok(disposed_again) =
    history.dispose_local(advanced.history, parent)
  disposed_again |> expect.to_equal(advanced.history)
  let assert Ok(without_child) = history.dispose_local(disposed_again, child)
  let assert Ok(#(released, Nil)) =
    history.advance_minimum(without_child, 1, 1, Nil, no_mint)
  released.trimmed_revisions |> expect.to_equal([trunk.revision])
}

pub fn local_branch_dispose_preserves_revertible_pin_test() -> Nil {
  let first = empty_commit("0a")
  let second = empty_commit("0b")
  let assert Ok(appended_first) =
    history.append_local(history.new(session()), first)
  let assert Ok(appended_second) =
    history.append_local(appended_first.history, second)
  let assert Ok(#(acked_first, Nil)) =
    history.receive(
      appended_second.history,
      first,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  let assert Ok(#(acked_second, Nil)) =
    history.receive(
      acked_first.history,
      second,
      types.SequencePoint(2, 0),
      1,
      0,
      Nil,
      no_mint,
    )
  let assert Ok(#(forked, branch)) =
    history.fork_local(acked_second.history, types.DocumentCheckout)
  let assert Ok(#(retained, revertible)) =
    history.retain_revertible(forked, second.revision, types.DefaultCommit)
  let assert Ok(disposed_branch) = history.dispose_local(retained, branch)
  let assert Ok(#(pinned, Nil)) =
    history.advance_minimum(disposed_branch, 2, 2, Nil, no_mint)

  pinned.trimmed_revisions |> expect.to_equal([first.revision])
  history.inspect(pinned.history).sequenced.trunk
  |> expect.to_equal([
    history.SequencedCommit(second, types.SequencePoint(2, 0)),
  ])
  history.revertible_is_valid(pinned.history, revertible)
  |> expect.to_equal(True)

  let assert Ok(released) =
    history.dispose_revertible(pinned.history, revertible)
  let assert Ok(#(trimmed, Nil)) =
    history.advance_minimum(released, 2, 2, Nil, no_mint)
  trimmed.trimmed_revisions |> expect.to_equal([second.revision])
}

pub fn local_branch_rebase_advances_only_its_pin_test() -> Nil {
  let trunk_revision = revision("0a")
  let target_revision = revision("0b")
  let source_revision = revision("0c")
  let rollback_revision = revision("0d")
  let assert Ok(order) =
    change.identity_order([
      #(trunk_revision, -4),
      #(target_revision, -3),
      #(source_revision, -2),
      #(rollback_revision, -1),
    ])
  let trunk = empty_commit_with_order(trunk_revision, order)
  let target = empty_commit_with_order(target_revision, order)
  let source = empty_commit_with_order(source_revision, order)
  let assert Ok(appended) = history.append_local(history.new(session()), trunk)
  let assert Ok(#(acked_trunk, Nil)) =
    history.receive(
      appended.history,
      trunk,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  let assert Ok(#(with_source, source_id)) =
    history.fork_local(acked_trunk.history, types.DocumentCheckout)
  let assert Ok(source_authored) =
    history.append_local_checkout(with_source, source_id, source)
  let assert Ok(#(with_sibling, sibling_id)) =
    history.fork_local(source_authored.history, types.DocumentCheckout)
  let assert Ok(target_pending) = history.append_local(with_sibling, target)
  let assert Ok(#(target_acked, Nil)) =
    history.receive(
      target_pending.history,
      target,
      types.SequencePoint(2, 0),
      1,
      0,
      Nil,
      no_mint,
    )
  let assert Ok(#(with_rebase_target, rebase_target)) =
    history.fork_local(target_acked.history, types.DocumentCheckout)
  let target_before = history.inspect_local(with_rebase_target, rebase_target)
  let allocation = Allocation([rollback_revision], order)
  let source_before = history.inspect_local(with_rebase_target, source_id)
  let assert Ok(#(self_rebased, Allocation([_], _))) =
    history.rebase_local(
      with_rebase_target,
      source_id,
      types.LocalCheckout(source_id),
      allocation,
      mint,
    )
  history.inspect_local(self_rebased.history, source_id)
  |> expect.to_equal(source_before)
  let assert Ok(#(rebased, Allocation([], _))) =
    history.rebase_local(
      self_rebased.history,
      source_id,
      types.LocalCheckout(rebase_target),
      allocation,
      mint,
    )

  history.inspect_local(rebased.history, rebase_target)
  |> expect.to_equal(target_before)
  let assert Ok(history.LocalBranch(_, source_base, source_commits)) =
    history.inspect_local(rebased.history, source_id)
  source_base |> expect.to_equal(Some(target_revision))
  source_commits
  |> fn(commits) { commits |> list.map(fn(commit) { commit.revision }) }
  |> expect.to_equal([source_revision])
  history.inspect_local(rebased.history, sibling_id)
  |> expect.to_equal(
    Ok(history.LocalBranch(sibling_id, Some(trunk_revision), [])),
  )
  history.inspect_rollback_revisions(rebased.history)
  |> expect.to_equal([rollback_revision])

  let assert Ok(#(sibling_pinned, Allocation([], _))) =
    history.advance_minimum(rebased.history, 2, 2, Allocation([], order), mint)
  sibling_pinned.trimmed_revisions |> expect.to_equal([])
  let assert Ok(without_sibling) =
    history.dispose_local(sibling_pinned.history, sibling_id)
  let assert Ok(#(source_pinned, Allocation([], _))) =
    history.advance_minimum(without_sibling, 2, 2, Allocation([], order), mint)
  source_pinned.trimmed_revisions |> expect.to_equal([trunk_revision])
  history.inspect_rollback_revisions(source_pinned.history)
  |> expect.to_equal([])
}

pub fn local_branch_merge_removes_common_revisions_test() -> Nil {
  let trunk = empty_commit("0a")
  let common = empty_commit("0b")
  let source_only = empty_commit("0c")
  let assert Ok(appended) = history.append_local(history.new(session()), trunk)
  let assert Ok(#(acked, Nil)) =
    history.receive(
      appended.history,
      trunk,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  let assert Ok(#(forked, source)) =
    history.fork_local(acked.history, types.DocumentCheckout)
  let assert Ok(common_update) =
    history.append_local_checkout(forked, source, common)
  let assert Ok(#(with_target, target)) =
    history.fork_local(common_update.history, types.LocalCheckout(source))
  let assert Ok(source_update) =
    history.append_local_checkout(with_target, source, source_only)
  let assert Ok(#(self_merged, [], Nil)) =
    history.merge_local(
      source_update.history,
      types.LocalCheckout(source),
      source,
      Nil,
      no_mint,
    )
  history.inspect_local(self_merged.history, source)
  |> expect.to_equal(history.inspect_local(source_update.history, source))
  let assert Ok(#(merged, surviving, Nil)) =
    history.merge_local(
      self_merged.history,
      types.LocalCheckout(target),
      source,
      Nil,
      no_mint,
    )

  surviving
  |> list.map(fn(commit) { commit.revision })
  |> expect.to_equal([source_only.revision])
  let assert Ok(history.LocalBranch(_, base, commits)) =
    history.inspect_local(merged.history, target)
  base |> expect.to_equal(Some(trunk.revision))
  commits
  |> list.map(fn(commit) { commit.revision })
  |> expect.to_equal([common.revision, source_only.revision])
  history.inspect_local(merged.history, source)
  |> expect.to_equal(
    Ok(history.LocalBranch(source, Some(trunk.revision), [common, source_only])),
  )

  let assert Ok(#(repeated, repeated_surviving, Nil)) =
    history.merge_local(
      merged.history,
      types.LocalCheckout(target),
      source,
      Nil,
      no_mint,
    )
  repeated_surviving |> expect.to_equal([])
  history.inspect_local(repeated.history, target)
  |> expect.to_equal(history.inspect_local(merged.history, target))
}

pub fn local_branch_repeated_divergent_merge_excludes_target_revisions_test() -> Nil {
  let trunk_revision = revision("0a")
  let source_revision = revision("0b")
  let target_revision = revision("0c")
  let rollback_revision = revision("0d")
  let assert Ok(order) =
    change.identity_order([
      #(trunk_revision, -4),
      #(source_revision, -3),
      #(target_revision, -2),
      #(rollback_revision, -1),
    ])
  let trunk = empty_commit_with_order(trunk_revision, order)
  let source_commit = empty_commit_with_order(source_revision, order)
  let target_commit = empty_commit_with_order(target_revision, order)
  let assert Ok(appended) = history.append_local(history.new(session()), trunk)
  let assert Ok(#(acked, Nil)) =
    history.receive(
      appended.history,
      trunk,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  let assert Ok(#(with_source, source)) =
    history.fork_local(acked.history, types.DocumentCheckout)
  let assert Ok(#(with_target, target)) =
    history.fork_local(with_source, types.DocumentCheckout)
  let assert Ok(source_authored) =
    history.append_local_checkout(with_target, source, source_commit)
  let assert Ok(target_authored) =
    history.append_local_checkout(
      source_authored.history,
      target,
      target_commit,
    )
  let allocation = Allocation([rollback_revision], order)
  let assert Ok(#(merged, surviving, Allocation([], _))) =
    history.merge_local(
      target_authored.history,
      types.LocalCheckout(target),
      source,
      allocation,
      mint,
    )

  surviving
  |> list.map(fn(commit) { commit.revision })
  |> expect.to_equal([source_revision])
  let target_after_first = history.inspect_local(merged.history, target)
  let assert Ok(#(repeated, repeated_surviving, Allocation([], _))) =
    history.merge_local(
      merged.history,
      types.LocalCheckout(target),
      source,
      Allocation([], order),
      mint,
    )
  repeated_surviving |> expect.to_equal([])
  history.inspect_local(repeated.history, target)
  |> expect.to_equal(target_after_first)
}

pub fn local_branch_pending_revision_is_not_replayed_after_sequencing_test() -> Nil {
  let pending_revision = revision("0a")
  let remote_revision = revision("0b")
  let rollback_revision = revision("0c")
  let assert Ok(order) =
    change.identity_order([
      #(pending_revision, -3),
      #(remote_revision, -2),
      #(rollback_revision, -1),
    ])
  let pending = empty_commit_with_order(pending_revision, order)
  let remote =
    history.Commit(
      ..empty_commit_with_order(remote_revision, order),
      originator: peer_session(),
    )
  let assert Ok(appended) =
    history.append_local(history.new(session()), pending)
  let assert Ok(#(forked, source)) =
    history.fork_local(appended.history, types.DocumentCheckout)
  let assert Ok(#(remote_received, Allocation([], _))) =
    history.receive(
      forked,
      remote,
      types.SequencePoint(1, 0),
      0,
      0,
      Allocation([rollback_revision], order),
      mint,
    )
  let assert Ok(#(sequenced, Allocation([], _))) =
    history.receive(
      remote_received.history,
      pending,
      types.SequencePoint(2, 0),
      1,
      0,
      Allocation([], order),
      mint,
    )
  let assert Ok(#(rebased, Allocation([], _))) =
    history.rebase_local(
      sequenced.history,
      source,
      types.DocumentCheckout,
      Allocation([], order),
      mint,
    )

  history.inspect_local(rebased.history, source)
  |> expect.to_equal(
    Ok(history.LocalBranch(source, Some(pending_revision), [])),
  )
}

pub fn local_branch_replay_keeps_original_sequence_pin_test() -> Nil {
  let first_revision = revision("0a")
  let remote_revision = revision("0b")
  let assert Ok(order) =
    change.identity_order([
      #(first_revision, -2),
      #(remote_revision, -1),
    ])
  let first = empty_commit_with_order(first_revision, order)
  let remote =
    edit_commit_with_order(remote_revision, peer_session(), 9.0, order)
  let appended =
    history.append_local(history.new(session()), first) |> expect.to_be_ok
  let #(sequenced, Nil) =
    history.receive(
      appended.history,
      first,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
    |> expect.to_be_ok
  let #(forked, fork) =
    history.fork_local(sequenced.history, types.DocumentCheckout)
    |> expect.to_be_ok
  let #(with_remote, Nil) =
    history.receive(
      forked,
      remote,
      types.SequencePoint(2, 0),
      1,
      0,
      Nil,
      no_mint,
    )
    |> expect.to_be_ok
  let #(with_replay, Nil) =
    history.receive(
      with_remote.history,
      first,
      types.SequencePoint(3, 0),
      2,
      0,
      Nil,
      no_mint,
    )
    |> expect.to_be_ok
  let #(pinned, Nil) =
    history.advance_minimum(with_replay.history, 3, 3, Nil, no_mint)
    |> expect.to_be_ok

  pinned.trimmed_revisions |> expect.to_equal([])
  let #(rebased, Nil) =
    history.rebase_local(
      pinned.history,
      fork,
      types.DocumentCheckout,
      Nil,
      no_mint,
    )
    |> expect.to_be_ok
  rebased.effects
  |> list.length
  |> fn(length) { length > 0 }
  |> expect.to_equal(True)

  let disposed = history.dispose_local(rebased.history, fork) |> expect.to_be_ok
  let #(released, Nil) =
    history.advance_minimum(disposed, 3, 3, Nil, no_mint)
    |> expect.to_be_ok
  released.trimmed_revisions
  |> expect.to_equal([first.revision, remote.revision, first.revision])
}

pub fn local_branch_merge_ignores_replayed_source_receipt_test() -> Nil {
  let #(state, old, current, replayed, target) = replayed_revision_branches()
  let #(merged, surviving, Nil) =
    history.merge_local(state, types.LocalCheckout(old), current, Nil, no_mint)
    |> expect.to_be_ok

  surviving
  |> list.map(fn(commit) { commit.revision })
  |> expect.to_equal([target.revision])
  merged.effects |> expect.to_equal(commit_effects(target))
  history.inspect_local(merged.history, old)
  |> expect.to_equal(
    Ok(history.LocalBranch(old, Some(replayed.revision), [target])),
  )
  history.inspect_local(merged.history, current)
  |> expect.to_equal(
    Ok(history.LocalBranch(current, Some(replayed.revision), [])),
  )
}

pub fn local_branch_reverse_merge_ignores_replayed_target_receipt_test() -> Nil {
  let #(state, old, current, replayed, _) = replayed_revision_branches()
  let #(merged, surviving, Nil) =
    history.merge_local(state, types.LocalCheckout(current), old, Nil, no_mint)
    |> expect.to_be_ok

  surviving |> expect.to_equal([])
  merged.effects |> expect.to_equal([])
  history.inspect_local(merged.history, current)
  |> expect.to_equal(
    Ok(history.LocalBranch(current, Some(replayed.revision), [])),
  )
  history.inspect_local(merged.history, old)
  |> expect.to_equal(Ok(history.LocalBranch(old, Some(replayed.revision), [])))
}

pub fn local_branch_rebase_ignores_replayed_target_receipt_test() -> Nil {
  let #(state, old, current, replayed, target) = replayed_revision_branches()
  let #(rebased, Nil) =
    history.rebase_local(state, old, types.LocalCheckout(current), Nil, no_mint)
    |> expect.to_be_ok

  rebased.effects |> expect.to_equal(commit_effects(target))
  history.inspect_local(rebased.history, old)
  |> expect.to_equal(Ok(history.LocalBranch(old, Some(replayed.revision), [])))
  history.inspect_local(rebased.history, current)
  |> expect.to_equal(
    Ok(history.LocalBranch(current, Some(replayed.revision), [])),
  )
}

pub fn local_branch_trimmed_original_still_ignores_replay_receipt_test() -> Nil {
  let #(state, old, current, _replayed, target) =
    replayed_revision_branches_after_original_trim()
  let #(merged, surviving, Nil) =
    history.merge_local(state, types.LocalCheckout(old), current, Nil, no_mint)
    |> expect.to_be_ok

  surviving |> expect.to_equal([])
  merged.effects |> expect.to_equal([])
  history.inspect_local(merged.history, old)
  |> expect.to_equal(Ok(history.LocalBranch(old, Some(target.revision), [])))

  let #(rebased, Nil) =
    history.rebase_local(state, old, types.LocalCheckout(current), Nil, no_mint)
    |> expect.to_be_ok
  rebased.effects |> expect.to_equal([])
  history.inspect_local(rebased.history, old)
  |> expect.to_equal(Ok(history.LocalBranch(old, None, [])))
}
