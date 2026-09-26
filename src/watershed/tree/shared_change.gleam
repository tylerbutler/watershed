//// Ordered schema and data changes for SharedTree.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import watershed/fluid_ids.{type StableId}
import watershed/tree/change
import watershed/tree/forest
import watershed/tree/schema
import watershed/tree/types.{type TreeError, InvalidHistory}

pub type TreeChange {
  DataChange(change.Changeset)
  SchemaChange(
    before: schema.SchemaState,
    after: schema.SchemaState,
    is_inverse: Bool,
  )
}

pub opaque type Changeset {
  Changeset(changes: List(TreeChange))
}

pub type TaggedChange {
  TaggedChange(
    revision: Option(StableId),
    rollback_of: Option(StableId),
    change: Changeset,
  )
}

pub type Effect {
  DataDelta(forest.Delta)
  SchemaDelta(
    before: schema.SchemaState,
    after: schema.SchemaState,
    is_inverse: Bool,
  )
}

pub fn empty() -> Changeset {
  Changeset([])
}

pub fn from_data(data: change.Changeset) -> Changeset {
  Changeset([DataChange(data)])
}

pub fn from_changes(items: List(TreeChange)) -> Result(Changeset, TreeError) {
  normalize([TaggedChange(None, None, Changeset(items))])
}

pub fn to_changes(value: Changeset) -> List(TreeChange) {
  value.changes
}

pub fn compose(changes: List(TaggedChange)) -> Result(Changeset, TreeError) {
  normalize(changes)
}

fn normalize(changes: List(TaggedChange)) -> Result(Changeset, TreeError) {
  use #(output, data_run) <- result.try(
    list.try_fold(changes, #([], []), fn(state, tagged) {
      list.try_fold(tagged.change.changes, state, fn(state, item) {
        case item {
          DataChange(data) ->
            Ok(#(
              state.0,
              list.append(state.1, [
                change.TaggedChange(tagged.revision, tagged.rollback_of, data),
              ]),
            ))
          SchemaChange(_, _, _) -> {
            use output <- result.try(flush_data(state.0, state.1))
            Ok(#(list.append(output, [item]), []))
          }
        }
      })
    }),
  )
  use output <- result.try(flush_data(output, data_run))
  Ok(Changeset(output))
}

fn flush_data(
  output: List(TreeChange),
  data_run: List(change.TaggedChange),
) -> Result(List(TreeChange), TreeError) {
  case data_run {
    [] -> Ok(output)
    _ ->
      change.compose(data_run)
      |> result.map(fn(data) { list.append(output, [DataChange(data)]) })
  }
}

pub fn invert(
  value: TaggedChange,
  is_rollback: Bool,
  inverse_revision: StableId,
) -> Result(Changeset, TreeError) {
  value.change.changes
  |> list.try_map(fn(item) {
    case item {
      DataChange(data) ->
        change.invert(
          change.TaggedChange(value.revision, value.rollback_of, data),
          is_rollback,
          inverse_revision,
        )
        |> result.map(DataChange)
      SchemaChange(before, after, _) -> Ok(SchemaChange(after, before, True))
    }
  })
  |> result.map(list.reverse)
  |> result.map(Changeset)
}

pub fn rebase(
  value: TaggedChange,
  over: TaggedChange,
  context: change.RebaseContext,
) -> Result(Changeset, TreeError) {
  case to_changes(value.change), to_changes(over.change) {
    [], _ -> Ok(value.change)
    _, [] -> Ok(value.change)
    value_items, over_items -> {
      case has_schema(value_items) || has_schema(over_items) {
        True -> Ok(empty())
        False -> rebase_data_pair(value, over, context)
      }
    }
  }
}

fn has_schema(items: List(TreeChange)) -> Bool {
  list.any(items, fn(item) {
    case item {
      SchemaChange(_, _, _) -> True
      DataChange(_) -> False
    }
  })
}

fn rebase_data_pair(
  value: TaggedChange,
  over: TaggedChange,
  context: change.RebaseContext,
) -> Result(Changeset, TreeError) {
  case value.change.changes, over.change.changes {
    [DataChange(value_change)], [DataChange(over_change)] ->
      change.rebase(
        change.TaggedChange(value.revision, value.rollback_of, value_change),
        change.TaggedChange(over.revision, over.rollback_of, over_change),
        context,
      )
      |> result.map(from_data)
    _, _ -> Error(InvalidHistory("outer data changes are not normalized"))
  }
}

pub fn effects(value: TaggedChange) -> Result(List(Effect), TreeError) {
  list.try_map(value.change.changes, fn(item) {
    case item {
      DataChange(data) ->
        change.into_delta(change.TaggedChange(
          value.revision,
          value.rollback_of,
          data,
        ))
        |> result.map(DataDelta)
      SchemaChange(before, after, is_inverse) ->
        Ok(SchemaDelta(before, after, is_inverse))
    }
  })
}

pub fn identity_revisions(value: Changeset) -> List(StableId) {
  value.changes
  |> list.flat_map(fn(item) {
    case item {
      DataChange(data) -> change.identity_revisions(data)
      SchemaChange(_, _, _) -> []
    }
  })
  |> list.unique
}

pub fn revision_infos(value: TaggedChange) -> List(change.RevisionInfo) {
  let outer = case value.revision {
    None -> []
    Some(revision) -> [change.RevisionInfo(revision, value.rollback_of)]
  }
  let inner =
    list.flat_map(value.change.changes, fn(item) {
      case item {
        DataChange(data) ->
          change.revision_infos(change.TaggedChange(
            value.revision,
            value.rollback_of,
            data,
          ))
        SchemaChange(_, _, _) -> []
      }
    })
  list.fold(inner, outer, fn(revisions, info) {
    case
      list.any(revisions, fn(existing) {
        existing.revision == info.revision
        && existing.rollback_of == info.rollback_of
      })
    {
      True -> revisions
      False -> list.append(revisions, [info])
    }
  })
}

pub fn max_local_id(value: Changeset) -> Int {
  list.fold(value.changes, -1, fn(maximum, item) {
    case item {
      SchemaChange(_, _, _) -> maximum
      DataChange(data) -> int_max(maximum, change.max_local_id(data))
    }
  })
}

pub fn rebind_identity_order(
  value: Changeset,
  order: change.IdentityOrder,
  tagged_revisions: List(StableId),
) -> Result(Changeset, TreeError) {
  value.changes
  |> list.try_map(fn(item) {
    case item {
      SchemaChange(_, _, _) -> Ok(item)
      DataChange(data) ->
        change.rebind_identity_order(data, order, tagged_revisions)
        |> result.map(DataChange)
    }
  })
  |> result.map(Changeset)
}

fn int_max(left: Int, right: Int) -> Int {
  case left > right {
    True -> left
    False -> right
  }
}
