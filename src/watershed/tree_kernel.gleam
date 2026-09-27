//// Pure state for the SharedTree object, map, and array profiles.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import watershed/fluid_ids
import watershed/tree/change
import watershed/tree/codec/summary as summary_codec
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/schema
import watershed/tree/shared_change
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

/// Preserve array mutations when a runtime batch has equal visible values.
pub type ChangeEvents {
  ChangeEvents(events: List(TreeEvent), array_changed: Bool)
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

pub fn map_get(
  state: TreeState,
  path: FieldPath,
  key: String,
) -> Result(Option(TreeValue), TreeError) {
  forest.map_get(state.visible, path, key)
}

pub fn map_entries(
  state: TreeState,
  path: FieldPath,
) -> Result(List(#(String, TreeValue)), TreeError) {
  forest.map_entries(state.visible, path)
}

pub fn array_get(
  state: TreeState,
  path: FieldPath,
  index: Int,
) -> Result(Option(TreeValue), TreeError) {
  forest.array_get(state.visible, path, index)
}

pub fn array_values(
  state: TreeState,
  path: FieldPath,
) -> Result(List(TreeValue), TreeError) {
  forest.array_values(state.visible, path)
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
        use roots <- result.try(removed_roots(commit.change))
        let builds = change_builds(commit.change)
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
        use enriched <- result.try(update_refreshers(commit.change, external))
        use effects <- result.try(
          shared_change.effects(shared_change.TaggedChange(
            Some(commit.revision),
            None,
            enriched,
          )),
        )
        use after <- result.try(apply_effects(before, effects))
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
) -> Result(#(TreeState, history.Commit, ChangeEvents), TreeError) {
  use _ <- result.try(validate_edit(state, edit))
  use authored <- result.try(change.edit_from(
    state.stored,
    state.visible,
    revision,
    edit,
    order,
    state.next_local_id,
  ))
  let outer = shared_change.from_data(authored)
  let commit = history.Commit(revision, state.local_session, outer)
  use update <- result.try(history.append_local(state.history, commit))
  use #(visible, array_changed) <- result.try(apply_effects_with_array_changes(
    state.visible,
    update.effects,
  ))
  use events <- result.try(changed_events(
    state.visible,
    visible,
    True,
    array_changed,
  ))
  Ok(#(
    TreeState(
      ..state,
      visible:,
      history: update.history,
      next_local_id: shared_change.max_local_id(outer) + 1,
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
) -> Result(#(TreeState, ChangeEvents, allocation), TreeError) {
  use #(update, allocation) <- result.try(history.receive(
    state.history,
    commit,
    point,
    reference_sequence_number,
    minimum_sequence_number,
    allocation,
    mint,
  ))
  use sequenced <- result.try(apply_effects(
    state.sequenced,
    update.sequenced_effects,
  ))
  use #(visible, array_changed) <- result.try(apply_effects_with_array_changes(
    state.visible,
    update.effects,
  ))
  use events <- result.try(changed_events(
    state.visible,
    visible,
    False,
    array_changed,
  ))
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
) -> Result(#(TreeState, ChangeEvents, allocation), TreeError) {
  use state <- result.try(rebind_identity_order(state, order))
  use authored <- result.try(shared_change.rebind_identity_order(
    commit.change,
    order,
    [commit.revision, ..shared_change.identity_revisions(commit.change)]
      |> list.unique,
  ))
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

fn apply_effects(
  state: forest.Forest,
  effects: List(shared_change.Effect),
) -> Result(forest.Forest, TreeError) {
  list.try_fold(effects, state, fn(state, effect) {
    case effect {
      shared_change.DataDelta(delta) -> forest.apply_delta(state, delta)
      shared_change.SchemaDelta(_, _, _) ->
        Error(types.UnsupportedFeature(
          "tree history effects",
          "schema effects are not supported before schema state migration",
        ))
    }
  })
}

fn apply_effects_with_array_changes(
  state: forest.Forest,
  effects: List(shared_change.Effect),
) -> Result(#(forest.Forest, Bool), TreeError) {
  list.try_fold(effects, #(state, False), fn(acc, effect) {
    case effect {
      shared_change.DataDelta(delta) -> {
        use #(state, changed) <- result.try(
          forest.apply_delta_with_array_changes(acc.0, delta),
        )
        Ok(#(state, acc.1 || changed))
      }
      shared_change.SchemaDelta(_, _, _) ->
        Error(types.UnsupportedFeature(
          "tree history effects",
          "schema effects are not supported before schema state migration",
        ))
    }
  })
}

fn removed_roots(
  changeset: shared_change.Changeset,
) -> Result(List(types.AtomId), TreeError) {
  changeset
  |> shared_change.to_changes
  |> list.try_fold([], fn(roots, item) {
    case item {
      shared_change.SchemaChange(_, _, _) -> Ok(roots)
      shared_change.DataChange(data) -> {
        use next <- result.try(change.relevant_removed_roots(data))
        Ok(list.append(roots, next))
      }
    }
  })
}

fn change_builds(changeset: shared_change.Changeset) -> List(forest.Build) {
  changeset
  |> shared_change.to_changes
  |> list.flat_map(fn(item) {
    case item {
      shared_change.SchemaChange(_, _, _) -> []
      shared_change.DataChange(data) -> change.to_data(data).builds
    }
  })
}

fn update_refreshers(
  changeset: shared_change.Changeset,
  repair: List(forest.Build),
) -> Result(shared_change.Changeset, TreeError) {
  use items <- result.try(
    changeset
    |> shared_change.to_changes
    |> list.try_map(fn(item) {
      case item {
        shared_change.SchemaChange(_, _, _) -> Ok(item)
        shared_change.DataChange(data) -> {
          use roots <- result.try(change.relevant_removed_roots(data))
          change.update_refreshers(data, roots, repair)
          |> result.map(shared_change.DataChange)
        }
      }
    }),
  )
  shared_change.from_changes(items)
}

fn changed_events(
  before: forest.Forest,
  after: forest.Forest,
  local: Bool,
  array_changed: Bool,
) -> Result(ChangeEvents, TreeError) {
  use before <- result.try(forest.visible_root(before))
  use after <- result.try(forest.visible_root(after))
  Ok(ChangeEvents(
    events: case before == after && !array_changed {
      True -> []
      False -> [TreeChanged(local)]
    },
    array_changed:,
  ))
}
