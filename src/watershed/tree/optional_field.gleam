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

fn source(change: FieldChange) -> Option(RegisterId) {
  option.then(change.replacement, fn(replacement) { replacement.source })
}

fn effectful_destination(change: FieldChange) -> Option(AtomId) {
  case change.replacement {
    Some(replacement)
      if !replacement.was_empty && replacement.source != Some(Active)
    -> Some(replacement.detach_id)
    _ -> None
  }
}

fn lookup(entries: List(#(a, b)), key: a) -> Option(b) {
  entries |> list.key_find(key) |> option.from_result
}

fn put(entries: List(#(a, b)), key: a, value: b) -> List(#(a, b)) {
  case list.key_find(entries, key) {
    Error(Nil) -> list.append(entries, [#(key, value)])
    Ok(_) ->
      list.map(entries, fn(entry) {
        case entry.0 == key {
          True -> #(key, value)
          False -> entry
        }
      })
  }
}

// Nested maps preserve the first occurrence of each outer key.
fn grouped(entries: List(a), key: fn(a) -> b) -> List(a) {
  let keys = entries |> list.map(key) |> list.unique
  list.flat_map(keys, fn(group) {
    list.filter(entries, fn(entry) { key(entry) == group })
  })
}

fn register_group(entry: #(RegisterId, a)) -> Option(Int) {
  case entry.0 {
    Active -> None
    Detached(id) -> Some(id.local_id)
  }
}

fn moved(id: AtomId, moves: List(#(AtomId, AtomId))) -> AtomId {
  option.unwrap(lookup(moves, id), id)
}

fn before_move(id: AtomId, moves: List(#(AtomId, AtomId))) -> AtomId {
  case list.find(moves, fn(move) { move.1 == id }) {
    Ok(move) -> move.0
    Error(Nil) -> id
  }
}

pub fn compose(
  first: FieldChange,
  second: FieldChange,
  context: context,
  compose_child: fn(Option(AtomId), Option(AtomId), context) ->
    Result(#(AtomId, context), TreeError),
) -> Result(#(FieldChange, context), TreeError) {
  use first <- result.try(validate(first))
  use second <- result.try(validate(second))
  let first_source = source(first)
  let first_destination = effectful_destination(first)
  let composed_source = case source(second) {
    Some(Active) -> Some(option.unwrap(first_source, Active))
    Some(Detached(id)) -> {
      case first_destination == Some(id) {
        True -> Some(Active)
        False -> Some(Detached(before_move(id, first.moves)))
      }
    }
    None -> {
      case second.replacement {
        None -> first_source
        Some(_) -> None
      }
    }
  }
  let second_children =
    list.fold(second.child_changes, [], fn(children, child) {
      let original = case child.0 {
        Active -> option.unwrap(first_source, Active)
        Detached(id) -> {
          case first_destination == Some(id) {
            True -> Active
            False -> Detached(before_move(id, first.moves))
          }
        }
      }
      put(children, original, child.1)
    })
    |> grouped(register_group)
  use #(children, remaining, context) <- result.try(
    list.try_fold(
      first.child_changes,
      #([], second_children, context),
      fn(acc, child) {
        use #(node, context) <- result.try(compose_child(
          Some(child.1),
          lookup(acc.1, child.0),
          acc.2,
        ))
        Ok(#(
          [#(child.0, node), ..acc.0],
          list.filter(acc.1, fn(entry) { entry.0 != child.0 }),
          context,
        ))
      },
    ),
  )
  use #(children, context) <- result.try(
    list.try_fold(remaining, #(children, context), fn(acc, child) {
      use #(node, context) <- result.try(compose_child(
        None,
        Some(child.1),
        acc.1,
      ))
      Ok(#([#(child.0, node), ..acc.0], context))
    }),
  )
  let first_moves = grouped(first.moves, fn(move) { move.0.revision })
  let #(moves, remaining_moves) =
    list.fold(second.moves, #([], first_moves), fn(acc, move) {
      case list.find(acc.1, fn(prior) { prior.1 == move.0 }) {
        Ok(prior) -> #(
          [#(prior.0, move.1), ..acc.0],
          list.filter(acc.1, fn(entry) { entry.0 != prior.0 }),
        )
        Error(Nil) -> {
          case first_destination == Some(move.0) {
            True -> acc
            False -> #([move, ..acc.0], acc.1)
          }
        }
      }
    })
  let moves =
    list.append(
      list.reverse(moves),
      list.filter(remaining_moves, fn(move) {
        composed_source != Some(Detached(move.0))
      }),
    )
  let moves = case first_source, second.replacement {
    Some(Detached(fill)), Some(replacement) -> {
      case effectful(replacement) && fill != replacement.detach_id {
        True -> list.append(moves, [#(fill, replacement.detach_id)])
        False -> moves
      }
    }
    _, _ -> moves
  }
  let replacement = case first.replacement, second.replacement {
    None, None -> None
    None, Some(replacement) ->
      Some(Replacement(..replacement, source: composed_source))
    Some(replacement), None ->
      Some(
        Replacement(
          ..replacement,
          source: composed_source,
          detach_id: moved(replacement.detach_id, second.moves),
        ),
      )
    Some(prior), Some(next) -> {
      let detach_id = case
        prior.source == Some(Active)
        || next.source == Some(Detached(prior.detach_id))
      {
        True -> next.detach_id
        False -> moved(prior.detach_id, second.moves)
      }
      Some(Replacement(prior.was_empty, composed_source, detach_id))
    }
  }
  use change <- result.try(
    validate(FieldChange(moves, list.reverse(children), replacement)),
  )
  Ok(#(change, context))
}

fn forward_map(change: FieldChange) -> List(#(RegisterId, RegisterId)) {
  let mapping =
    list.map(change.moves, fn(move) { #(Detached(move.0), Detached(move.1)) })
  let mapping = case effectful_destination(change) {
    None -> mapping
    Some(id) -> put(mapping, Active, Detached(id))
  }
  case source(change) {
    None -> mapping
    Some(source) -> put(mapping, source, Active)
  }
}

fn allocate_id(
  revision: Option(StableId),
  last_local_id: Int,
) -> Result(#(AtomId, Int), TreeError) {
  case last_local_id < max_safe_integer {
    True -> {
      let id = last_local_id + 1
      Ok(#(types.AtomId(revision, id), id))
    }
    False ->
      Error(CorruptData(
        "field.invert.allocation",
        "Local identifier space is exhausted",
      ))
  }
}

/// Return the inverse and its candidate allocation counter.
/// The caller must accept both results together.
pub fn invert(
  change: FieldChange,
  is_rollback: Bool,
  inverse_revision: Option(StableId),
  last_local_id: Int,
) -> Result(#(FieldChange, Int), TreeError) {
  use change <- result.try(validate(change))
  use _ <- result.try(
    case last_local_id >= -1 && last_local_id <= max_safe_integer {
      True -> Ok(Nil)
      False ->
        Error(CorruptData(
          "field.invert.allocation",
          "Invalid allocation counter",
        ))
    },
  )
  let mapping = forward_map(change)
  let children =
    list.map(change.child_changes, fn(child) {
      #(option.unwrap(lookup(mapping, child.0), child.0), child.1)
    })
  use #(replacement, last_local_id) <- result.try(case change.replacement {
    None -> Ok(#(None, last_local_id))
    Some(replacement) -> {
      case effectful(replacement) {
        True -> {
          use #(detach_id, last_local_id) <- result.try(
            case replacement.source, is_rollback {
              Some(Detached(id)), True -> Ok(#(id, last_local_id))
              _, _ -> allocate_id(inverse_revision, last_local_id)
            },
          )
          let source = case replacement.was_empty {
            True -> None
            False -> Some(Detached(replacement.detach_id))
          }
          Ok(#(
            Some(Replacement(replacement.source == None, source, detach_id)),
            last_local_id,
          ))
        }
        False -> {
          case !is_rollback && replacement.source == Some(Active) {
            False -> Ok(#(None, last_local_id))
            True -> {
              use #(id, last_local_id) <- result.try(allocate_id(
                inverse_revision,
                last_local_id,
              ))
              Ok(#(Some(Replacement(False, Some(Active), id)), last_local_id))
            }
          }
        }
      }
    }
  })
  use inverse <- result.try(
    validate(FieldChange(
      list.map(change.moves, fn(move) { #(move.1, move.0) }),
      children,
      replacement,
    )),
  )
  Ok(#(inverse, last_local_id))
}

pub fn rebase(
  change: FieldChange,
  over: FieldChange,
  context: context,
  rebase_child: fn(Option(AtomId), Option(AtomId), AttachState, context) ->
    Result(#(Option(AtomId), context), TreeError),
) -> Result(#(FieldChange, context), TreeError) {
  use change <- result.try(validate(change))
  use over <- result.try(validate(over))
  let mapping = forward_map(over)
  let over_children = grouped(over.child_changes, register_group)
  use #(children, remaining, context) <- result.try(
    list.try_fold(
      change.child_changes,
      #([], over_children, context),
      fn(acc, child) {
        let register = option.unwrap(lookup(mapping, child.0), child.0)
        use #(node, context) <- result.try(rebase_child(
          Some(child.1),
          lookup(acc.1, child.0),
          attachment(register),
          acc.2,
        ))
        let children = case node {
          None -> acc.0
          Some(node) -> [#(register, node), ..acc.0]
        }
        Ok(#(
          children,
          list.filter(acc.1, fn(entry) { entry.0 != child.0 }),
          context,
        ))
      },
    ),
  )
  use #(children, context) <- result.try(
    list.try_fold(remaining, #(children, context), fn(acc, child) {
      let register = option.unwrap(lookup(mapping, child.0), child.0)
      use #(node, context) <- result.try(rebase_child(
        None,
        Some(child.1),
        attachment(register),
        acc.1,
      ))
      let children = case node {
        None -> acc.0
        Some(node) -> [#(register, node), ..acc.0]
      }
      Ok(#(children, context))
    }),
  )
  let moves =
    list.map(change.moves, fn(move) {
      #(move.0, option.unwrap(lookup(over.moves, move.0), move.1))
    })
  let replacement =
    option.map(change.replacement, fn(replacement) {
      let was_empty = case over.replacement {
        None -> replacement.was_empty
        Some(base) -> base.source == None
      }
      Replacement(
        ..replacement,
        was_empty:,
        source: option.map(replacement.source, fn(register) {
          option.unwrap(lookup(mapping, register), register)
        }),
      )
    })
  use change <- result.try(
    validate(FieldChange(moves, list.reverse(children), replacement)),
  )
  Ok(#(change, context))
}

fn attachment(register: RegisterId) -> AttachState {
  case register {
    Active -> Attached
    Detached(_) -> DetachedNode
  }
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
