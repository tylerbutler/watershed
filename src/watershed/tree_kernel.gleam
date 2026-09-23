//// Pure state for the fixed SharedTree object profile.

import gleam/option.{type Option, None, Some}
import gleam/result
import watershed/fluid_ids
import watershed/tree/change
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
  )
}

pub opaque type TreeState {
  TreeState(
    stored: schema.StoredSchema,
    visible: forest.Forest,
    sequenced: forest.Forest,
    history: history.History,
    local_session: fluid_ids.SessionId,
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
  Ok(TreeSnapshot(stored, forest_data, history_snapshot))
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
  Ok(TreeState(snapshot.stored, visible, visible, history, local_session))
}

pub fn read(
  state: TreeState,
  path: FieldPath,
) -> Result(Option(TreeValue), TreeError) {
  forest.read(state.visible, path)
}

pub fn snapshot(state: TreeState) -> Result(TreeSnapshot, TreeError) {
  use data <- result.try(forest.export_data(state.sequenced))
  Ok(TreeSnapshot(state.stored, data, history.inspect(state.history).sequenced))
}

pub fn snapshot_parts(
  snapshot: TreeSnapshot,
) -> #(schema.StoredSchema, forest.ForestData, history.HistorySnapshot) {
  #(snapshot.stored, snapshot.forest_data, snapshot.history_snapshot)
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
  use authored <- result.try(change.edit(
    state.stored,
    state.visible,
    revision,
    edit,
    order,
  ))
  let commit = history.Commit(revision, state.local_session, authored)
  use update <- result.try(history.append_local(state.history, commit))
  use delta <- result.try(case update.delta {
    Some(delta) -> Ok(delta)
    None -> Error(types.InvalidHistory("local edit has no delta"))
  })
  use visible <- result.try(forest.apply_delta(state.visible, delta))
  use events <- result.try(changed_events(state.visible, visible, True))
  Ok(#(TreeState(..state, visible:, history: update.history), commit, events))
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
