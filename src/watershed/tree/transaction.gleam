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

type ConstraintSet {
  ConstraintSet(
    state: tree_kernel.TreeState,
    targets: List(change.ConstraintTarget),
  )
}

type Savepoint {
  Savepoint(
    state: tree_kernel.TreeState,
    constraint_set_count: Int,
    change_count: Int,
    event_count: Int,
  )
}

pub opaque type Transaction {
  Transaction(
    base_state: tree_kernel.TreeState,
    current_state: tree_kernel.TreeState,
    base_compressor: fluid_ids.Compressor,
    current_compressor: fluid_ids.Compressor,
    constraint_sets: List(ConstraintSet),
    changes: List(AuthoredChange),
    events: List(tree_kernel.ChangeEvents),
    savepoints: List(Savepoint),
  )
}

pub type Finish {
  NoCommit(state: tree_kernel.TreeState, compressor: fluid_ids.Compressor)
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
  Ok(
    Transaction(
      state,
      state,
      compressor,
      compressor,
      constraint_set(state, constraints),
      [],
      [],
      [],
    ),
  )
}

pub fn begin_nested(value: Transaction) -> Transaction {
  push_savepoint(value, [])
}

pub fn begin_nested_with_constraints(
  value: Transaction,
  constraints: List(change.ConstraintTarget),
) -> Result(Transaction, TreeError) {
  use _ <- result.try(tree_kernel.validate_constraints(
    value.current_state,
    constraints,
  ))
  Ok(push_savepoint(value, constraints))
}

fn push_savepoint(
  value: Transaction,
  constraints: List(change.ConstraintTarget),
) -> Transaction {
  Transaction(
    ..value,
    savepoints: [
      Savepoint(
        value.current_state,
        list.length(value.constraint_sets),
        list.length(value.changes),
        list.length(value.events),
      ),
      ..value.savepoints
    ],
    constraint_sets: list.append(
      value.constraint_sets,
      constraint_set(value.current_state, constraints),
    ),
  )
}

pub fn depth(value: Transaction) -> Int {
  list.length(value.savepoints) + 1
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
          current_state: tree_kernel.preserve_identity_allocation(
            savepoint.state,
            value.current_state,
          ),
          constraint_sets: list.take(
            value.constraint_sets,
            savepoint.constraint_set_count,
          ),
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
    [] -> Ok(finish_no_commit(value))
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
        [] -> Ok(finish_no_commit(value))
        _ -> finish_change(value, first.revision, outer)
      }
    }
  }
}

fn finish_no_commit(value: Transaction) -> #(Finish, tree_kernel.ChangeEvents) {
  #(
    NoCommit(
      tree_kernel.preserve_identity_allocation(
        value.base_state,
        value.current_state,
      ),
      value.base_compressor,
    ),
    tree_kernel.ChangeEvents([], False),
  )
}

pub fn abort(
  value: Transaction,
) -> Result(#(tree_kernel.TreeState, fluid_ids.Compressor), TreeError) {
  use _ <- result.try(require_outer_scope(value))
  Ok(#(
    tree_kernel.preserve_identity_allocation(
      value.base_state,
      value.current_state,
    ),
    value.current_compressor,
  ))
}

fn finish_change(
  value: Transaction,
  revision: fluid_ids.StableId,
  outer: shared_change.Changeset,
) -> Result(#(Finish, tree_kernel.ChangeEvents), TreeError) {
  use _ <- result.try(reject_schema_changes(outer))
  use outer <- result.try(squash_revisions(outer, revision))
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
  use outer <- result.try(
    list.try_fold(value.constraint_sets, outer, fn(outer, constraints) {
      tree_kernel.add_node_exists_constraints(
        constraints.state,
        outer,
        constraints.targets,
        revision,
        order,
      )
    }),
  )
  use #(state, commit, events) <- result.try(tree_kernel.commit_local_preview(
    value.base_state,
    value.current_state,
    revision,
    order,
    outer,
  ))
  Ok(#(
    Commit(state, value.current_compressor, commit),
    preserve_array_events(value.events, events),
  ))
}

fn squash_revisions(
  value: shared_change.Changeset,
  revision: fluid_ids.StableId,
) -> Result(shared_change.Changeset, TreeError) {
  case shared_change.to_changes(value) {
    [shared_change.DataChange(data)] -> {
      let obsolete =
        change.revision_infos(change.TaggedChange(None, None, data))
        |> list.map(fn(info) { Some(info.revision) })
      change.replace_revisions(data, obsolete, revision)
      |> result.map(shared_change.from_data)
    }
    _ ->
      Error(types.UnsupportedFeature(
        "tree.transaction",
        "schema changes are not supported",
      ))
  }
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

fn constraint_set(
  state: tree_kernel.TreeState,
  targets: List(change.ConstraintTarget),
) -> List(ConstraintSet) {
  case targets {
    [] -> []
    _ -> [ConstraintSet(state, targets)]
  }
}
