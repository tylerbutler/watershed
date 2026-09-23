//// Pure state for the fixed SharedTree object profile.

import gleam/option.{type Option}
import gleam/result
import watershed/fluid_ids
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/schema
import watershed/tree/types.{type FieldPath, type TreeError, type TreeValue}

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
  Ok(TreeState(snapshot.stored, visible, visible, history))
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
