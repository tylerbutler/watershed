//// Pure nested transaction state for one SharedTree.

import gleam/list
import gleam/option.{None, Some}
import gleam/result
import watershed/fluid_ids
import watershed/tree/change
import watershed/tree/history
import watershed/tree/runtime
import watershed/tree/shared_change
import watershed/tree/types.{type Edit, type TreeError}
import watershed/tree_kernel

type AuthoredChange {
  AuthoredChange(revision: fluid_ids.StableId, change: shared_change.Changeset)
}

type Savepoint {
  Savepoint(state: tree_kernel.TreeState, change_count: Int, event_count: Int)
}

pub opaque type Transaction {
  Transaction(
    base_state: tree_kernel.TreeState,
    current_state: tree_kernel.TreeState,
    base_compressor: fluid_ids.Compressor,
    current_compressor: fluid_ids.Compressor,
    constraints: List(change.ConstraintTarget),
    changes: List(AuthoredChange),
    events: List(tree_kernel.ChangeEvents),
    savepoints: List(Savepoint),
  )
}

pub type Finish {
  NoCommit
  Commit(
    state: tree_kernel.TreeState,
    compressor: fluid_ids.Compressor,
    commit: history.Commit,
  )
}

pub fn begin(
  state: tree_kernel.TreeState,
  compressor: fluid_ids.Compressor,
  constraints: List(change.ConstraintTarget),
) -> Result(Transaction, TreeError) {
  use _ <- result.try(tree_kernel.validate_constraints(state, constraints))
  Ok(Transaction(state, state, compressor, compressor, constraints, [], [], []))
}

pub fn begin_nested(value: Transaction) -> Transaction {
  Transaction(..value, savepoints: [
    Savepoint(
      value.current_state,
      list.length(value.changes),
      list.length(value.events),
    ),
    ..value.savepoints
  ])
}

pub fn state(value: Transaction) -> tree_kernel.TreeState {
  value.current_state
}

pub fn compressor(value: Transaction) -> fluid_ids.Compressor {
  value.current_compressor
}

pub fn apply_edit(
  value: Transaction,
  edit: Edit,
) -> Result(Transaction, TreeError) {
  use authored <- result.try(runtime.author_edit_change(
    value.current_state,
    edit,
    value.current_compressor,
  ))
  case authored {
    None -> Ok(value)
    Some(authored) -> {
      use revision <- result.try(authored_revision(authored.change))
      Ok(
        Transaction(
          ..value,
          current_state: authored.state,
          current_compressor: authored.compressor,
          changes: list.append(value.changes, [
            AuthoredChange(revision, authored.change),
          ]),
          events: list.append(value.events, [authored.events]),
        ),
      )
    }
  }
}

pub fn commit_nested(value: Transaction) -> Result(Transaction, TreeError) {
  case value.savepoints {
    [] -> Error(types.InvalidHistory("tree transaction has no nested scope"))
    [_, ..rest] -> Ok(Transaction(..value, savepoints: rest))
  }
}

pub fn abort_nested(value: Transaction) -> Result(Transaction, TreeError) {
  case value.savepoints {
    [] -> Error(types.InvalidHistory("tree transaction has no nested scope"))
    [savepoint, ..rest] ->
      Ok(
        Transaction(
          ..value,
          current_state: savepoint.state,
          changes: list.take(value.changes, savepoint.change_count),
          events: list.take(value.events, savepoint.event_count),
          savepoints: rest,
        ),
      )
  }
}

pub fn finish(
  value: Transaction,
) -> Result(#(Finish, tree_kernel.ChangeEvents), TreeError) {
  use _ <- result.try(require_outer_scope(value))
  case value.changes {
    [] -> Ok(#(NoCommit, tree_kernel.ChangeEvents([], False)))
    [first, ..] -> {
      use outer <- result.try(
        value.changes
        |> list.map(fn(authored) {
          shared_change.TaggedChange(
            Some(authored.revision),
            None,
            authored.change,
          )
        })
        |> shared_change.compose,
      )
      case shared_change.to_changes(outer) {
        [] -> Ok(#(NoCommit, tree_kernel.ChangeEvents([], False)))
        _ -> finish_change(value, first.revision, outer)
      }
    }
  }
}

pub fn abort(
  value: Transaction,
) -> Result(#(tree_kernel.TreeState, fluid_ids.Compressor), TreeError) {
  use _ <- result.try(require_outer_scope(value))
  Ok(#(value.base_state, value.current_compressor))
}

fn finish_change(
  value: Transaction,
  revision: fluid_ids.StableId,
  outer: shared_change.Changeset,
) -> Result(#(Finish, tree_kernel.ChangeEvents), TreeError) {
  use _ <- result.try(reject_schema_changes(outer))
  let draft =
    history.Commit(
      revision,
      fluid_ids.local_session(value.current_compressor),
      outer,
    )
  use order <- result.try(runtime.identity_order(
    value.base_state,
    draft,
    value.current_compressor,
  ))
  use outer <- result.try(tree_kernel.add_node_exists_constraints(
    value.base_state,
    outer,
    value.constraints,
    revision,
    order,
  ))
  use #(state, commit, events) <- result.try(tree_kernel.apply_local_change(
    value.base_state,
    revision,
    order,
    outer,
  ))
  Ok(#(
    Commit(state, value.current_compressor, commit),
    preserve_array_events(value.events, events),
  ))
}

fn authored_revision(
  value: shared_change.Changeset,
) -> Result(fluid_ids.StableId, TreeError) {
  case
    shared_change.revision_infos(shared_change.TaggedChange(None, None, value))
  {
    [info] -> Ok(info.revision)
    [] -> Error(types.InvalidHistory("authored edit has no revision"))
    _ -> Error(types.InvalidHistory("authored edit has multiple revisions"))
  }
}

fn reject_schema_changes(
  value: shared_change.Changeset,
) -> Result(Nil, TreeError) {
  case
    list.any(shared_change.to_changes(value), fn(item) {
      case item {
        shared_change.SchemaChange(_, _, _) -> True
        shared_change.DataChange(_) -> False
      }
    })
  {
    True ->
      Error(types.UnsupportedFeature(
        "tree.transaction",
        "schema changes are not supported",
      ))
    False -> Ok(Nil)
  }
}

fn require_outer_scope(value: Transaction) -> Result(Nil, TreeError) {
  case value.savepoints {
    [] -> Ok(Nil)
    _ -> Error(types.InvalidHistory("tree transaction has open nested scopes"))
  }
}

fn preserve_array_events(
  previews: List(tree_kernel.ChangeEvents),
  committed: tree_kernel.ChangeEvents,
) -> tree_kernel.ChangeEvents {
  let array_changed =
    committed.array_changed
    || list.any(previews, fn(events) { events.array_changed })
  let events = case
    array_changed
    && !list.contains(committed.events, tree_kernel.TreeChanged(True))
  {
    True -> list.append(committed.events, [tree_kernel.TreeChanged(True)])
    False -> committed.events
  }
  tree_kernel.ChangeEvents(events, array_changed)
}
