import gleam/list
import gleam/option.{None, Some}
import startest/expect
import watershed/fluid_ids
import watershed/tree/change
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/schema
import watershed/tree/types.{
  type TreeError, InvalidHistory, NumberValue, ObjectValue, SetField,
}

const tree_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"Point\":{\"kind\":{\"object\":{\"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]},\"y\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]}}}},\"Root\":{\"kind\":{\"object\":{\"point\":{\"kind\":\"Value\",\"types\":[\"Point\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}"

fn session(value: String) -> fluid_ids.SessionId {
  let assert Ok(id) = fluid_ids.session_id(value)
  id
}

fn revision(value: String) -> fluid_ids.StableId {
  let assert Ok(id) = fluid_ids.stable_id(value)
  id
}

fn local_session() -> fluid_ids.SessionId {
  session("00000000-0000-4000-8000-000000000001")
}

fn peer_session() -> fluid_ids.SessionId {
  session("00000000-0000-4000-8000-000000000002")
}

fn revision_a() -> fluid_ids.StableId {
  revision("00000000-0000-4000-8000-00000000000a")
}

fn revision_b() -> fluid_ids.StableId {
  revision("00000000-0000-4000-8000-00000000000b")
}

fn revision_r() -> fluid_ids.StableId {
  revision("00000000-0000-4000-8000-00000000000c")
}

type Allocation {
  Allocation(
    revisions: List(fluid_ids.StableId),
    order: change.IdentityOrder,
    consumed: Int,
  )
}

fn no_mint(
  state: Nil,
) -> Result(#(fluid_ids.StableId, change.IdentityOrder, Nil), TreeError) {
  let _ = state
  Error(InvalidHistory("unexpected rollback allocation"))
}

fn mint(
  state: Allocation,
) -> Result(#(fluid_ids.StableId, change.IdentityOrder, Allocation), TreeError) {
  case state.revisions {
    [] -> Error(InvalidHistory("rollback allocation is exhausted"))
    [revision, ..rest] ->
      Ok(#(
        revision,
        state.order,
        Allocation(rest, state.order, state.consumed + 1),
      ))
  }
}

fn empty_commit(
  revision: fluid_ids.StableId,
  originator: fluid_ids.SessionId,
) -> history.Commit {
  let assert Ok(order) = change.identity_order([#(revision, -1)])
  let assert Ok(checked) =
    change.from_data(change.to_data(change.empty()), order)
  history.Commit(revision, originator, checked)
}

fn stored_schema() -> schema.StoredSchema {
  let assert Ok(stored) = schema.stored_from_string(tree_schema)
  stored
}

fn point(x: Float, y: Float) {
  ObjectValue("Point", [
    #("x", NumberValue(x)),
    #("y", NumberValue(y)),
  ])
}

fn root() {
  ObjectValue("Root", [#("point", point(1.0, 2.0))])
}

fn real_commit() -> #(history.Commit, forest.Forest) {
  let view = revision("00000000-0000-4000-8000-000000000099")
  let assert Ok(state) = forest.new(view, stored_schema(), Some(root()))
  let assert Ok(order) = change.identity_order([#(revision_a(), -1)])
  let assert Ok(authored) =
    change.edit(
      stored_schema(),
      state,
      revision_a(),
      SetField(["point", "x"], NumberValue(7.0)),
      order,
    )
  #(history.Commit(revision_a(), local_session(), authored), state)
}

fn conflicting_commits() -> #(
  history.Commit,
  history.Commit,
  forest.Forest,
  Allocation,
) {
  let view = revision("00000000-0000-4000-8000-000000000099")
  let assert Ok(state) = forest.new(view, stored_schema(), Some(root()))
  let assert Ok(authored_order) =
    change.identity_order([#(revision_a(), -2), #(revision_b(), -1)])
  let assert Ok(rollback_order) =
    change.identity_order([
      #(revision_a(), -2),
      #(revision_b(), -1),
      #(revision_r(), 0),
    ])
  let assert Ok(local) =
    change.edit(
      stored_schema(),
      state,
      revision_a(),
      SetField(["point", "x"], NumberValue(7.0)),
      authored_order,
    )
  let assert Ok(remote) =
    change.edit(
      stored_schema(),
      state,
      revision_b(),
      SetField(["point", "x"], NumberValue(8.0)),
      authored_order,
    )
  #(
    history.Commit(revision_a(), local_session(), local),
    history.Commit(revision_b(), peer_session(), remote),
    state,
    Allocation([revision_r()], rollback_order, 0),
  )
}

fn peer_edit(value: Float) -> history.Commit {
  let view = revision("00000000-0000-4000-8000-000000000099")
  let assert Ok(state) = forest.new(view, stored_schema(), Some(root()))
  let assert Ok(order) = change.identity_order([#(revision_a(), -1)])
  let assert Ok(authored) =
    change.edit(
      stored_schema(),
      state,
      revision_a(),
      SetField(["point", "x"], NumberValue(value)),
      order,
    )
  history.Commit(revision_a(), peer_session(), authored)
}

pub fn shared_tree_history_starts_empty_test() -> Nil {
  let state = history.new(local_session())
  history.pending(state) |> expect.to_equal([])
  history.inspect(state)
  |> expect.to_equal(history.HistoryView(
    history.HistorySnapshot(
      history.InitialBase,
      [],
      [],
      0,
      -9_007_199_254_740_991,
    ),
    [],
    0,
  ))
}

pub fn shared_tree_history_ack_does_not_apply_twice_test() -> Nil {
  let #(commit, initial_forest) = real_commit()
  let assert Ok(local) =
    history.append_local(history.new(local_session()), commit)
  let assert Some(delta) = local.delta
  let assert Ok(optimistic_forest) = forest.apply_delta(initial_forest, delta)
  history.pending(local.history) |> expect.to_equal([commit])

  let assert Ok(#(ack, Nil)) =
    history.receive(
      local.history,
      commit,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  history.pending(ack.history) |> expect.to_equal([])
  ack.delta |> expect.to_equal(None)
  forest.export_data(optimistic_forest)
  |> expect.to_equal(forest.export_data(optimistic_forest))
}

pub fn shared_tree_history_local_contract_refusals_test() -> Nil {
  let first = empty_commit(revision_a(), local_session())
  let second = empty_commit(revision_b(), local_session())
  let peer = empty_commit(revision_b(), peer_session())
  let state = history.new(local_session())
  history.append_local(state, peer) |> expect.to_be_error
  let assert Ok(first_update) = history.append_local(state, first)
  history.append_local(first_update.history, first) |> expect.to_be_error
  let assert Ok(second_update) =
    history.append_local(first_update.history, second)
  let assert Error(InvalidHistory(_)) =
    history.receive(
      second_update.history,
      second,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  history.pending(second_update.history)
  |> expect.to_equal([first, second])
  let assert Error(InvalidHistory(_)) =
    history.receive(
      second_update.history,
      first,
      types.SequencePoint(1, -1),
      0,
      0,
      Nil,
      no_mint,
    )
  let assert Error(InvalidHistory(_)) =
    history.receive(
      second_update.history,
      first,
      types.SequencePoint(9_007_199_254_740_991 + 1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  Nil
}

pub fn shared_tree_history_retained_duplicate_does_not_ack_next_test() -> Nil {
  let first = empty_commit(revision_a(), local_session())
  let second = empty_commit(revision_b(), local_session())
  let assert Ok(first_update) =
    history.append_local(history.new(local_session()), first)
  let assert Ok(#(acked, Nil)) =
    history.receive(
      first_update.history,
      first,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  let assert Ok(second_update) = history.append_local(acked.history, second)
  let assert Ok(#(duplicate, Nil)) =
    history.receive(
      second_update.history,
      first,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  history.pending(duplicate.history) |> expect.to_equal([second])
  duplicate.delta |> expect.to_equal(None)
}

pub fn shared_tree_history_retained_duplicate_rejects_conflicts_test() -> Nil {
  let first = empty_commit(revision_a(), local_session())
  let assert Ok(first_update) =
    history.append_local(history.new(local_session()), first)
  let assert Ok(#(acked, Nil)) =
    history.receive(
      first_update.history,
      first,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  let changed = peer_edit(9.0)
  let conflicting_change =
    history.Commit(first.revision, first.originator, changed.change)
  history.receive(
    acked.history,
    conflicting_change,
    types.SequencePoint(1, 0),
    0,
    0,
    Nil,
    no_mint,
  )
  |> expect.to_be_error
  history.receive(
    acked.history,
    first,
    types.SequencePoint(1, 0),
    1,
    0,
    Nil,
    no_mint,
  )
  |> expect.to_be_error
  history.receive(
    acked.history,
    history.Commit(..first, originator: peer_session()),
    types.SequencePoint(1, 0),
    0,
    0,
    Nil,
    no_mint,
  )
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_history_rebased_ack_replay_does_not_ack_next_test() -> Nil {
  let #(local, remote, _, allocation) = conflicting_commits()
  let assert Ok(local_update) =
    history.append_local(history.new(local_session()), local)
  let assert Ok(#(remote_update, allocation)) =
    history.receive(
      local_update.history,
      remote,
      types.SequencePoint(1, 0),
      0,
      0,
      allocation,
      mint,
    )
  let assert Ok(#(acked, allocation)) =
    history.receive(
      remote_update.history,
      local,
      types.SequencePoint(2, 0),
      1,
      0,
      allocation,
      mint,
    )
  let next =
    empty_commit(
      revision("00000000-0000-4000-8000-00000000000d"),
      local_session(),
    )
  let assert Ok(pending) = history.append_local(acked.history, next)
  let assert Ok(#(duplicate, _)) =
    history.receive(
      pending.history,
      local,
      types.SequencePoint(2, 0),
      1,
      0,
      allocation,
      mint,
    )
  history.pending(duplicate.history) |> expect.to_equal([next])
  duplicate.delta |> expect.to_equal(None)
}

pub fn shared_tree_history_rebases_pending_over_remote_test() -> Nil {
  let #(local, remote, initial_forest, allocation) = conflicting_commits()
  let assert Ok(local_update) =
    history.append_local(history.new(local_session()), local)
  let assert Some(local_delta) = local_update.delta
  let assert Ok(optimistic) = forest.apply_delta(initial_forest, local_delta)
  let remote_result =
    history.receive(
      local_update.history,
      remote,
      types.SequencePoint(1, 0),
      0,
      0,
      allocation,
      mint,
    )
  remote_result |> expect.to_be_ok
  let assert Ok(#(remote_update, allocation)) = remote_result
  allocation.consumed |> expect.to_equal(1)
  let assert Some(remote_delta) = remote_update.delta
  let assert Ok(reconciled) = forest.apply_delta(optimistic, remote_delta)
  let view = history.inspect(remote_update.history)
  view.sequenced.trunk
  |> list.length
  |> expect.to_equal(1)
  history.pending(remote_update.history)
  |> list.length
  |> expect.to_equal(1)

  let assert Ok(#(ack, allocation)) =
    history.receive(
      remote_update.history,
      local,
      types.SequencePoint(2, 0),
      1,
      0,
      allocation,
      mint,
    )
  ack.delta |> expect.to_equal(None)
  allocation.consumed |> expect.to_equal(1)
  forest.export_data(reconciled)
  |> expect.to_equal(forest.export_data(reconciled))
}

pub fn shared_tree_history_remote_failure_is_atomic_test() -> Nil {
  let #(local, remote, _, _) = conflicting_commits()
  let assert Ok(local_update) =
    history.append_local(history.new(local_session()), local)
  let before = history.inspect(local_update.history)
  let assert Error(InvalidHistory(_)) =
    history.receive(
      local_update.history,
      remote,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  history.inspect(local_update.history) |> expect.to_equal(before)
}

pub fn shared_tree_history_snapshot_refuses_pending_test() -> Nil {
  let commit = empty_commit(revision_a(), local_session())
  let assert Ok(local) =
    history.append_local(history.new(local_session()), commit)
  history.snapshot(local.history) |> expect.to_be_error
  history.pending(local.history) |> expect.to_equal([commit])
}

pub fn shared_tree_history_restore_rejects_missing_peer_base_test() -> Nil {
  let invalid =
    history.HistorySnapshot(
      history.InitialBase,
      [],
      [history.PeerBranch(peer_session(), Some(revision_a()), [])],
      0,
      -9_007_199_254_740_991,
    )
  history.restore(invalid, local_session()) |> expect.to_be_error
  Nil
}

pub fn shared_tree_history_restore_allows_divergent_revision_copy_test() -> Nil {
  let trunk = peer_edit(7.0)
  let authored = peer_edit(8.0)
  let snapshot =
    history.HistorySnapshot(
      history.InitialBase,
      [history.SequencedCommit(trunk, types.SequencePoint(1, 0))],
      [history.PeerBranch(peer_session(), None, [authored])],
      1,
      -9_007_199_254_740_991,
    )
  history.restore(snapshot, local_session()) |> expect.to_be_ok
  Nil
}

pub fn shared_tree_history_restore_rejects_duplicate_trunk_revision_test() -> Nil {
  let commit = peer_edit(7.0)
  let snapshot =
    history.HistorySnapshot(
      history.InitialBase,
      [
        history.SequencedCommit(commit, types.SequencePoint(1, 0)),
        history.SequencedCommit(commit, types.SequencePoint(2, 0)),
      ],
      [],
      2,
      -9_007_199_254_740_991,
    )
  history.restore(snapshot, local_session()) |> expect.to_be_error
  Nil
}

pub fn shared_tree_history_rejects_receive_behind_processed_watermark_test() -> Nil {
  let assert Ok(#(advanced, Nil)) =
    history.advance_minimum(history.new(local_session()), 10, 5, Nil, no_mint)
  let remote = empty_commit(revision_b(), peer_session())
  history.receive(
    advanced.history,
    remote,
    types.SequencePoint(6, 0),
    5,
    5,
    Nil,
    no_mint,
  )
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_history_rejects_reused_trimmed_sequence_point_test() -> Nil {
  let first = empty_commit(revision_b(), peer_session())
  let assert Ok(#(received, Nil)) =
    history.receive(
      history.new(local_session()),
      first,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  let assert Ok(#(trimmed, Nil)) =
    history.advance_minimum(received.history, 10, 1, Nil, no_mint)
  let next = empty_commit(revision_r(), peer_session())
  history.receive(
    trimmed.history,
    next,
    types.SequencePoint(1, 1),
    1,
    1,
    Nil,
    no_mint,
  )
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_history_allows_same_sequence_continuation_and_gaps_test() -> Nil {
  let first = empty_commit(revision_b(), peer_session())
  let second = empty_commit(revision_r(), peer_session())
  let assert Ok(#(received, Nil)) =
    history.receive(
      history.new(local_session()),
      first,
      types.SequencePoint(5, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  let assert Ok(#(continued, Nil)) =
    history.receive(
      received.history,
      second,
      types.SequencePoint(5, 1),
      0,
      0,
      Nil,
      no_mint,
    )
  let gap =
    empty_commit(
      revision("00000000-0000-4000-8000-00000000000d"),
      peer_session(),
    )
  history.receive(
    continued.history,
    gap,
    types.SequencePoint(9, 0),
    5,
    0,
    Nil,
    no_mint,
  )
  |> expect.to_be_ok
  Nil
}

pub fn shared_tree_history_trim_rejects_unavailable_reference_test() -> Nil {
  let first = empty_commit(revision_b(), peer_session())
  let assert Ok(#(received, Nil)) =
    history.receive(
      history.new(local_session()),
      first,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  let assert Ok(#(trimmed, Nil)) =
    history.advance_minimum(received.history, 1, 1, Nil, no_mint)
  trimmed.trimmed_revisions |> expect.to_equal([revision_b()])
  let before = history.inspect(trimmed.history)
  let stale = empty_commit(revision_r(), peer_session())
  let assert Error(InvalidHistory(_)) =
    history.receive(
      trimmed.history,
      stale,
      types.SequencePoint(2, 0),
      0,
      1,
      Nil,
      no_mint,
    )
  history.inspect(trimmed.history) |> expect.to_equal(before)
}

pub fn shared_tree_history_resubmit_is_pure_and_stable_test() -> Nil {
  let commit = empty_commit(revision_a(), local_session())
  let assert Ok(local) =
    history.append_local(history.new(local_session()), commit)
  history.resubmit(local.history, []) |> expect.to_equal(Ok([commit]))
  history.resubmit(local.history, []) |> expect.to_equal(Ok([commit]))

  let extraneous =
    forest.Build(types.AtomId(Some(revision_a()), 0), [point(1.0, 2.0)])
  history.resubmit(local.history, [#(revision_a(), [extraneous])])
  |> expect.to_be_error

  let assert Ok(#(acked, Nil)) =
    history.receive(
      local.history,
      commit,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  history.resubmit(acked.history, []) |> expect.to_equal(Ok([]))
}
