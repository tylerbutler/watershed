//// Pure state for the fixed SharedTree object profile.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import watershed/fluid_ids
import watershed/tree/change
import watershed/tree/codec/summary as summary_codec
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/schema
import watershed/tree/types.{
  type Edit, type FieldPath, type SequencePoint, type TreeError, type TreeValue,
}

pub opaque type TreeSnapshot {
  TreeSnapshot(
    stored: schema.StoredSchema,
    forest_data: forest.ForestData,
    history_snapshot: history.HistorySnapshot,
    retained_wire: summary_codec.EditManagerSummary,
  )
}

pub opaque type TreeState {
  TreeState(
    stored: schema.StoredSchema,
    visible: forest.Forest,
    sequenced: forest.Forest,
    history: history.History,
    local_session: fluid_ids.SessionId,
    next_local_id: Int,
    retained_wire: summary_codec.EditManagerSummary,
  )
}

pub type TreeEvent {
  TreeChanged(local: Bool)
}

pub fn snapshot_from_parts(
  view_id: fluid_ids.StableId,
  stored: schema.StoredSchema,
  forest_data: forest.ForestData,
  history_snapshot: history.HistorySnapshot,
) -> Result(TreeSnapshot, TreeError) {
  use _ <- result.try(forest.import_data(view_id, stored, forest_data))
  Ok(TreeSnapshot(
    stored,
    forest_data,
    history_snapshot,
    summary_codec.EditManagerSummary([], []),
  ))
}

pub fn snapshot_from_summary(
  view_id: fluid_ids.StableId,
  stored: schema.StoredSchema,
  forest_data: forest.ForestData,
  history_snapshot: history.HistorySnapshot,
  retained_wire: summary_codec.EditManagerSummary,
) -> Result(TreeSnapshot, TreeError) {
  use snapshot <- result.try(snapshot_from_parts(
    view_id,
    stored,
    forest_data,
    history_snapshot,
  ))
  Ok(TreeSnapshot(..snapshot, retained_wire:))
}

pub fn restore(
  snapshot: TreeSnapshot,
  view_id: fluid_ids.StableId,
  local_session: fluid_ids.SessionId,
  view: schema.ViewSchema,
) -> Result(TreeState, TreeError) {
  use _ <- result.try(schema.can_view(snapshot.stored, view))
  use visible <- result.try(forest.import_data(
    view_id,
    snapshot.stored,
    snapshot.forest_data,
  ))
  use history <- result.try(history.restore(
    snapshot.history_snapshot,
    local_session,
  ))
  Ok(TreeState(
    snapshot.stored,
    visible,
    visible,
    history,
    local_session,
    0,
    snapshot.retained_wire,
  ))
}

pub fn read(
  state: TreeState,
  path: FieldPath,
) -> Result(Option(TreeValue), TreeError) {
  forest.read(state.visible, path)
}

pub fn reference_at(
  state: TreeState,
  path: FieldPath,
) -> Result(forest.NodeRef, TreeError) {
  forest.locate(state.visible, path)
}

pub fn read_reference(
  state: TreeState,
  reference: forest.NodeRef,
) -> Result(TreeValue, TreeError) {
  forest.read_node(state.visible, reference)
}

pub fn ensure_attached(
  state: TreeState,
  reference: forest.NodeRef,
) -> Result(Nil, TreeError) {
  use attached <- result.try(forest.is_attached(state.visible, reference))
  case attached {
    True -> Ok(Nil)
    False -> Error(types.InvalidEdit([], "cannot edit a detached node"))
  }
}

pub fn snapshot(state: TreeState) -> Result(TreeSnapshot, TreeError) {
  use data <- result.try(forest.export_data(state.sequenced))
  Ok(TreeSnapshot(
    state.stored,
    data,
    history.inspect(state.history).sequenced,
    state.retained_wire,
  ))
}

pub fn retained_wire(
  snapshot: TreeSnapshot,
) -> summary_codec.EditManagerSummary {
  snapshot.retained_wire
}

pub fn snapshot_parts(
  snapshot: TreeSnapshot,
) -> #(schema.StoredSchema, forest.ForestData, history.HistorySnapshot) {
  #(snapshot.stored, snapshot.forest_data, snapshot.history_snapshot)
}

pub fn visible_data(state: TreeState) -> Result(forest.ForestData, TreeError) {
  forest.export_data(state.visible)
}

pub fn history_view(state: TreeState) -> history.HistoryView {
  history.inspect(state.history)
}

/// Rebuild repair content from the forest before each pending commit.
pub fn resubmit_commits(
  state: TreeState,
) -> Result(List(history.Commit), TreeError) {
  use #(scratch, repair) <- result.try(
    list.try_fold(
      history.pending(state.history),
      #(state.sequenced, []),
      fn(acc, commit) {
        let #(before, repairs) = acc
        use roots <- result.try(change.relevant_removed_roots(commit.change))
        let builds = change.to_data(commit.change).builds
        use external <- result.try(
          roots
          |> list.filter(fn(root) {
            !list.any(builds, fn(build) { history.build_covers(build, root) })
          })
          |> list.try_map(fn(root) {
            use reference <- result.try(forest.locate_detached(before, root))
            use value <- result.try(forest.read_node(before, reference))
            Ok(forest.Build(root, [value]))
          }),
        )
        use enriched <- result.try(change.update_refreshers(
          commit.change,
          roots,
          external,
        ))
        use delta <- result.try(
          change.into_delta(change.TaggedChange(
            Some(commit.revision),
            None,
            enriched,
          )),
        )
        use after <- result.try(forest.apply_delta(before, delta))
        Ok(#(after, list.append(repairs, [#(commit.revision, external)])))
      },
    ),
  )
  use expected <- result.try(forest.visible_root(state.visible))
  use actual <- result.try(forest.visible_root(scratch))
  use _ <- result.try(case expected == actual {
    True -> Ok(Nil)
    False ->
      Error(types.InvalidHistory("pending replay does not match visible tree"))
  })
  history.resubmit(state.history, repair)
}

pub fn stored_schema(state: TreeState) -> schema.StoredSchema {
  state.stored
}

pub fn identity_revisions(state: TreeState) -> List(fluid_ids.StableId) {
  history.identity_revisions(state.history)
}

pub fn rebind_identity_order(
  state: TreeState,
  order: change.IdentityOrder,
) -> Result(TreeState, TreeError) {
  use history <- result.try(history.rebind_identity_order(state.history, order))
  Ok(TreeState(..state, history:))
}

pub fn advance_document(
  state: TreeState,
  sequence_number: Int,
  minimum_sequence_number: Int,
  allocation: allocation,
  mint: history.MintRevision(allocation),
) -> Result(#(TreeState, allocation), TreeError) {
  use #(update, allocation) <- result.try(history.advance_minimum(
    state.history,
    sequence_number,
    minimum_sequence_number,
    allocation,
    mint,
  ))
  Ok(#(TreeState(..state, history: update.history), allocation))
}

pub fn advance_processed(
  state: TreeState,
  sequence_number: Int,
) -> Result(TreeState, TreeError) {
  use history <- result.try(history.advance_processed(
    state.history,
    sequence_number,
  ))
  Ok(TreeState(..state, history:))
}

pub fn validate_edit(state: TreeState, edit: Edit) -> Result(Nil, TreeError) {
  change.validate_edit(state.stored, state.visible, edit)
}

pub fn apply_local(
  state: TreeState,
  revision: fluid_ids.StableId,
  order: change.IdentityOrder,
  edit: Edit,
) -> Result(#(TreeState, history.Commit, List(TreeEvent)), TreeError) {
  use _ <- result.try(validate_edit(state, edit))
  use authored <- result.try(change.edit_from(
    state.stored,
    state.visible,
    revision,
    edit,
    order,
    state.next_local_id,
  ))
  let commit = history.Commit(revision, state.local_session, authored)
  use update <- result.try(history.append_local(state.history, commit))
  use delta <- result.try(case update.delta {
    Some(delta) -> Ok(delta)
    None -> Error(types.InvalidHistory("local edit has no delta"))
  })
  use visible <- result.try(forest.apply_delta(state.visible, delta))
  use events <- result.try(changed_events(state.visible, visible, True))
  Ok(#(
    TreeState(
      ..state,
      visible:,
      history: update.history,
      next_local_id: change.to_data(authored).max_local_id + 1,
    ),
    commit,
    events,
  ))
}

pub fn receive(
  state: TreeState,
  commit: history.Commit,
  point: SequencePoint,
  reference_sequence_number: Int,
  minimum_sequence_number: Int,
  allocation: allocation,
  mint: history.MintRevision(allocation),
) -> Result(#(TreeState, List(TreeEvent), allocation), TreeError) {
  use #(update, allocation) <- result.try(history.receive(
    state.history,
    commit,
    point,
    reference_sequence_number,
    minimum_sequence_number,
    allocation,
    mint,
  ))
  use sequenced <- result.try(apply_optional(
    state.sequenced,
    update.sequenced_delta,
  ))
  use visible <- result.try(apply_optional(state.visible, update.delta))
  use events <- result.try(changed_events(state.visible, visible, False))
  Ok(#(
    TreeState(..state, visible:, sequenced:, history: update.history),
    events,
    allocation,
  ))
}

pub fn receive_ordered(
  state: TreeState,
  commit: history.Commit,
  order: change.IdentityOrder,
  point: SequencePoint,
  reference_sequence_number: Int,
  minimum_sequence_number: Int,
  allocation: allocation,
  mint: history.MintRevision(allocation),
) -> Result(#(TreeState, List(TreeEvent), allocation), TreeError) {
  use state <- result.try(rebind_identity_order(state, order))
  use authored <- result.try(
    change.rebind_identity_order(commit.change, order, [commit.revision]),
  )
  receive(
    state,
    history.Commit(..commit, change: authored),
    point,
    reference_sequence_number,
    minimum_sequence_number,
    allocation,
    mint,
  )
}

fn apply_optional(
  state: forest.Forest,
  delta: Option(forest.Delta),
) -> Result(forest.Forest, TreeError) {
  case delta {
    None -> Ok(state)
    Some(delta) -> forest.apply_delta(state, delta)
  }
}

fn changed_events(
  before: forest.Forest,
  after: forest.Forest,
  local: Bool,
) -> Result(List(TreeEvent), TreeError) {
  use before <- result.try(forest.visible_root(before))
  use after <- result.try(forest.visible_root(after))
  case before == after {
    True -> Ok([])
    False -> Ok([TreeChanged(local)])
  }
}
