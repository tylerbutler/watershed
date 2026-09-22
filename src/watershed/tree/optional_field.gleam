//// Required and optional field changes for the Fluid 3.1.0 object profile.
////
//// Child changes refer to registers in the input context. Detached moves
//// apply simultaneously. The forest checks whether their content exists.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set as unique_set
import watershed/fluid_ids.{type StableId}
import watershed/tree/forest
import watershed/tree/types.{type AtomId, type TreeError, CorruptData}

const max_safe_integer = 9_007_199_254_740_991

pub type RegisterId {
  Active
  Detached(AtomId)
}

pub type Replacement {
  Replacement(was_empty: Bool, source: Option(RegisterId), detach_id: AtomId)
}

pub type FieldChange {
  FieldChange(
    moves: List(#(AtomId, AtomId)),
    child_changes: List(#(RegisterId, AtomId)),
    replacement: Option(Replacement),
  )
}

pub type AttachState {
  Attached
  DetachedNode
}

pub type FieldDelta {
  FieldDelta(
    local: Option(forest.FieldDelta),
    global: List(forest.DetachedChange),
    rename: List(forest.Rename),
  )
}

pub fn empty() -> FieldChange {
  FieldChange([], [], None)
}

pub fn set(was_empty: Bool, fill: AtomId, detach: AtomId) -> FieldChange {
  FieldChange(
    [],
    [],
    Some(Replacement(was_empty, Some(Detached(fill)), detach)),
  )
}

pub fn clear(was_empty: Bool, detach: AtomId) -> FieldChange {
  FieldChange([], [], Some(Replacement(was_empty, None, detach)))
}

pub fn validate(change: FieldChange) -> Result(FieldChange, TreeError) {
  use _ <- result.try(unique(
    list.map(change.moves, fn(move) { move.0 }),
    "field.moves.source",
  ))
  use _ <- result.try(unique(
    list.map(change.moves, fn(move) { move.1 }),
    "field.moves.destination",
  ))
  use _ <- result.try(unique(
    list.map(change.child_changes, fn(child) { child.0 }),
    "field.child_changes.register",
  ))
  use _ <- result.try(
    change.moves
    |> list.index_map(fn(move, index) { #(move, int.to_string(index)) })
    |> list.try_each(fn(entry) {
      use _ <- result.try(validate_atom(
        entry.0.0,
        "field.moves[" <> entry.1 <> "].source",
      ))
      validate_atom(entry.0.1, "field.moves[" <> entry.1 <> "].destination")
    }),
  )
  use _ <- result.try(
    change.child_changes
    |> list.index_map(fn(child, index) { #(child, int.to_string(index)) })
    |> list.try_each(fn(entry) {
      let location = "field.child_changes[" <> entry.1 <> "]"
      use _ <- result.try(validate_register(entry.0.0, location <> ".register"))
      validate_atom(entry.0.1, location <> ".node")
    }),
  )
  use _ <- result.try(case change.replacement {
    None -> Ok(Nil)
    Some(replacement) -> {
      use _ <- result.try(validate_atom(
        replacement.detach_id,
        "field.replacement.detach_id",
      ))
      case replacement.source {
        None -> Ok(Nil)
        Some(source) -> validate_register(source, "field.replacement.source")
      }
    }
  })
  Ok(change)
}

fn validate_atom(id: AtomId, location: String) -> Result(Nil, TreeError) {
  case id.local_id >= 0 && id.local_id <= max_safe_integer {
    True -> Ok(Nil)
    False -> Error(CorruptData(location, "Invalid local identifier"))
  }
}

fn validate_register(
  id: RegisterId,
  location: String,
) -> Result(Nil, TreeError) {
  case id {
    Active -> Ok(Nil)
    Detached(id) -> validate_atom(id, location)
  }
}

fn unique(values: List(a), location: String) -> Result(Nil, TreeError) {
  use _ <- result.try(
    values
    |> list.index_map(fn(value, index) { #(value, index) })
    |> list.try_fold(unique_set.new(), fn(seen, entry) {
      case unique_set.contains(seen, entry.0) {
        True ->
          Error(CorruptData(
            location <> "[" <> int.to_string(entry.1) <> "]",
            "Duplicate identifier",
          ))
        False -> Ok(unique_set.insert(seen, entry.0))
      }
    }),
  )
  Ok(Nil)
}

pub fn replace_revisions(
  change: FieldChange,
  obsolete: List(Option(StableId)),
  updated: Option(StableId),
) -> Result(FieldChange, TreeError) {
  use change <- result.try(validate(change))
  let replace_atom = fn(id: AtomId) {
    case list.contains(obsolete, id.revision) {
      True -> types.AtomId(..id, revision: updated)
      False -> id
    }
  }
  let replace_register = fn(register) {
    case register {
      Active -> Active
      Detached(id) -> Detached(replace_atom(id))
    }
  }
  validate(FieldChange(
    moves: list.map(change.moves, fn(move) {
      #(replace_atom(move.0), replace_atom(move.1))
    }),
    child_changes: list.map(change.child_changes, fn(child) {
      #(replace_register(child.0), replace_atom(child.1))
    }),
    replacement: option.map(change.replacement, fn(replacement) {
      Replacement(
        ..replacement,
        source: option.map(replacement.source, replace_register),
        detach_id: replace_atom(replacement.detach_id),
      )
    }),
  ))
}

fn effectful(replacement: Replacement) -> Bool {
  replacement.source != Some(Active)
  && { !replacement.was_empty || replacement.source != None }
}

pub fn into_delta(
  change: FieldChange,
  delta_from_child: fn(AtomId) ->
    Result(List(#(String, forest.FieldDelta)), TreeError),
) -> Result(FieldDelta, TreeError) {
  use change <- result.try(validate(change))
  let mark = case change.replacement {
    Some(replacement) if replacement.source != Some(Active) -> {
      case effectful(replacement) {
        False -> None
        True -> {
          let detach = case replacement.was_empty {
            True -> None
            False -> Some(replacement.detach_id)
          }
          let attach = case replacement.source {
            Some(Detached(id)) -> Some(id)
            _ -> None
          }
          Some(forest.Mark(1, attach, detach, []))
        }
      }
    }
    _ -> None
  }
  use #(mark, globals) <- result.try(
    list.try_fold(change.child_changes, #(mark, []), fn(acc, child) {
      use fields <- result.try(delta_from_child(child.1))
      case child.0 {
        Active -> {
          let mark = option.unwrap(acc.0, forest.Mark(1, None, None, []))
          Ok(#(Some(forest.Mark(..mark, fields:)), acc.1))
        }
        Detached(id) ->
          Ok(#(acc.0, [forest.DetachedChange(id, fields), ..acc.1]))
      }
    }),
  )
  let delta =
    FieldDelta(
      local: option.map(mark, fn(mark) { forest.FieldDelta([mark]) }),
      global: list.reverse(globals),
      rename: list.map(change.moves, fn(move) {
        forest.Rename(move.0, move.1, 1)
      }),
    )
  use _ <- result.try(
    forest.delta(
      forest.DeltaData(
        latest_revision: None,
        fields: case delta.local {
          None -> []
          Some(local) -> [#("rootFieldKey", local)]
        },
        build: [],
        refreshers: [],
        global: delta.global,
        rename: delta.rename,
        destroy: [],
      ),
    ),
  )
  Ok(delta)
}
