//// Required and optional field change algebra.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import watershed/fluid_ids.{type StableId}
import watershed/tree/forest
import watershed/tree/types.{type AtomId, type TreeError, AtomId, CorruptData}

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

type RegisterGroup {
  ActiveGroup
  DetachedGroup(Int)
}

pub type FieldChangeDelta {
  FieldChangeDelta(
    local: Option(forest.FieldDelta),
    global: List(forest.DetachedChange),
    rename: List(forest.Rename),
  )
}

pub fn validate(change: FieldChange) -> Result(Nil, TreeError) {
  let FieldChange(moves, children, replacement) = change
  use _ <- result.try(
    list.try_each(moves, fn(move) {
      use _ <- result.try(validate_atom(move.0))
      validate_atom(move.1)
    }),
  )
  use _ <- result.try(unique(
    list.map(moves, fn(move) { move.0 }),
    "move sources",
  ))
  use _ <- result.try(unique(
    list.map(moves, fn(move) { move.1 }),
    "move destinations",
  ))
  use _ <- result.try(
    list.try_each(children, fn(child) {
      use _ <- result.try(validate_register(child.0))
      validate_atom(child.1)
    }),
  )
  use _ <- result.try(unique(
    list.map(children, fn(child) { child.0 }),
    "child registers",
  ))
  case replacement {
    None -> Ok(Nil)
    Some(Replacement(_, source, detach_id)) -> {
      use _ <- result.try(validate_atom(detach_id))
      case source {
        None -> Ok(Nil)
        Some(register) -> validate_register(register)
      }
    }
  }
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

pub fn compose(
  first: FieldChange,
  second: FieldChange,
  state: s,
  compose_child: fn(Option(AtomId), Option(AtomId), s) ->
    Result(#(AtomId, s), TreeError),
) -> Result(#(FieldChange, s), TreeError) {
  use _ <- result.try(validate(first))
  use _ <- result.try(validate(second))
  let FieldChange(first_moves, first_children, first_replacement) = first
  let FieldChange(second_moves, second_children, second_replacement) = second
  let first_source = replacement_source(first_replacement)
  let first_destination = effectful_destination(first_replacement)
  let second_source = replacement_source(second_replacement)
  let composed_source =
    compose_source(
      first_source,
      first_destination,
      second_source,
      second_replacement,
      first_moves,
    )
  let remapped_second_children =
    list.fold(second_children, [], fn(children, child) {
      let register =
        trace_register_back(
          child.0,
          first_source,
          first_destination,
          first_moves,
        )
      put_child(children, register, child.1)
    })
  use #(children, remaining_children, state) <- result.try(
    compose_first_children(
      first_children,
      remapped_second_children,
      state,
      compose_child,
      [],
    ),
  )
  let remaining_children =
    register_map_entries(remapped_second_children, remaining_children)
  use #(children, state) <- result.try(compose_remaining_children(
    remaining_children,
    state,
    compose_child,
    children,
  ))
  let #(moves, remaining_first_moves) =
    compose_second_moves(second_moves, first_moves, first_destination, [])
  let moves =
    list.fold(remaining_first_moves, moves, fn(moves, move) {
      case composed_source == Some(Detached(move.0)) {
        True -> moves
        False -> list.append(moves, [move])
      }
    })
  let moves = case first_source, second_replacement {
    Some(Detached(source)), Some(replacement) ->
      case
        replacement_effectful(replacement) && source != replacement.detach_id
      {
        True -> list.append(moves, [#(source, replacement.detach_id)])
        False -> moves
      }
    _, _ -> moves
  }
  use replacement <- result.try(compose_replacement(
    first_replacement,
    second_replacement,
    second_moves,
    composed_source,
  ))
  let composed = FieldChange(moves, children, replacement)
  use _ <- result.try(validate(composed))
  Ok(#(composed, state))
}

pub fn invert(
  change: FieldChange,
  is_rollback: Bool,
  inverse_revision: Option(StableId),
  max_local_id: Int,
) -> Result(#(FieldChange, Int), TreeError) {
  use _ <- result.try(validate(change))
  use _ <- result.try(check_allocator(max_local_id))
  let FieldChange(moves, children, replacement) = change
  let register_map =
    list.fold(moves, [], fn(mapping, move) {
      put_register(mapping, Detached(move.0), Detached(move.1))
    })
  let register_map = case effectful_destination(replacement) {
    None -> register_map
    Some(destination) ->
      put_register(register_map, Active, Detached(destination))
  }
  let register_map = case replacement_source(replacement) {
    None -> register_map
    Some(source) -> put_register(register_map, source, Active)
  }
  let moves = list.map(moves, fn(move) { #(move.1, move.0) })
  let children =
    list.map(children, fn(child) {
      #(
        lookup_register(register_map, child.0)
          |> option_value(child.0),
        child.1,
      )
    })
  use #(replacement, max_local_id) <- result.try(invert_replacement(
    replacement,
    is_rollback,
    inverse_revision,
    max_local_id,
  ))
  let inverted = FieldChange(moves, children, replacement)
  use _ <- result.try(validate(inverted))
  Ok(#(inverted, max_local_id))
}

pub fn rebase(
  change: FieldChange,
  over: FieldChange,
  state: s,
  rebase_child: fn(Option(AtomId), Option(AtomId), AttachState, s) ->
    Result(#(Option(AtomId), s), TreeError),
) -> Result(#(FieldChange, s), TreeError) {
  use _ <- result.try(validate(change))
  use _ <- result.try(validate(over))
  let FieldChange(moves, children, replacement) = change
  let FieldChange(over_moves, over_children, over_replacement) = over
  let forward =
    list.fold(over_moves, [], fn(mapping, move) {
      put_register(mapping, Detached(move.0), Detached(move.1))
    })
  let forward = case effectful_destination(over_replacement) {
    None -> forward
    Some(destination) -> put_register(forward, Active, Detached(destination))
  }
  let forward = case replacement_source(over_replacement) {
    None -> forward
    Some(source) -> put_register(forward, source, Active)
  }
  let moves =
    list.map(moves, fn(move) {
      #(move.0, lookup_source(over_moves, move.0) |> option_value(move.1))
    })
  use #(children, remaining_over, state) <- result.try(
    rebase_authored_children(
      children,
      over_children,
      forward,
      state,
      rebase_child,
      [],
    ),
  )
  let remaining_over = register_map_entries(over_children, remaining_over)
  use #(children, state) <- result.try(rebase_base_children(
    remaining_over,
    forward,
    state,
    rebase_child,
    children,
  ))
  let replacement = case replacement {
    None -> None
    Some(replacement) -> {
      let was_empty = case over_replacement {
        None -> replacement.was_empty
        Some(over_replacement) -> over_replacement.source == None
      }
      let source = case replacement.source {
        None -> None
        Some(source) ->
          Some(lookup_register(forward, source) |> option_value(source))
      }
      Some(Replacement(was_empty, source, replacement.detach_id))
    }
  }
  let rebased = FieldChange(moves, children, replacement)
  use _ <- result.try(validate(rebased))
  Ok(#(rebased, state))
}

pub fn replace_revisions(
  change: FieldChange,
  replace: fn(AtomId) -> Result(AtomId, TreeError),
) -> Result(FieldChange, TreeError) {
  use _ <- result.try(validate(change))
  let FieldChange(moves, children, replacement) = change
  use moves <- result.try(
    list.try_map(moves, fn(move) {
      use source <- result.try(replace(move.0))
      use destination <- result.try(replace(move.1))
      Ok(#(source, destination))
    }),
  )
  use children <- result.try(
    list.try_map(children, fn(child) {
      use register <- result.try(replace_register(child.0, replace))
      use child_change <- result.try(replace(child.1))
      Ok(#(register, child_change))
    }),
  )
  use replacement <- result.try(case replacement {
    None -> Ok(None)
    Some(replacement) -> {
      use source <- result.try(case replacement.source {
        None -> Ok(None)
        Some(register) ->
          replace_register(register, replace) |> result.map(Some)
      })
      use destination <- result.try(replace(replacement.detach_id))
      Ok(Some(Replacement(replacement.was_empty, source, destination)))
    }
  })
  let changed = FieldChange(moves, children, replacement)
  use _ <- result.try(validate(changed))
  Ok(changed)
}

pub fn into_delta(
  change: FieldChange,
  delta_from_child: fn(AtomId) ->
    Result(List(#(String, forest.FieldDelta)), TreeError),
) -> Result(FieldChangeDelta, TreeError) {
  use _ <- result.try(validate(change))
  let FieldChange(moves, children, replacement) = change
  let #(attach, detach, has_local) = case replacement {
    Some(replacement) ->
      case replacement_effectful(replacement) {
        False -> #(None, None, False)
        True -> {
          let attach = case replacement.source {
            Some(Detached(id)) -> Some(id)
            _ -> None
          }
          let detach = case replacement.was_empty {
            True -> None
            False -> Some(replacement.detach_id)
          }
          #(attach, detach, True)
        }
      }
    None -> #(None, None, False)
  }
  use #(local_fields, global, has_local_child) <- result.try(
    list.try_fold(children, #([], [], False), fn(output, child) {
      use fields <- result.try(delta_from_child(child.1))
      case child.0 {
        Active -> Ok(#(fields, output.1, True))
        Detached(id) ->
          Ok(#(
            output.0,
            list.append(output.1, [forest.DetachedChange(id, fields)]),
            output.2,
          ))
      }
    }),
  )
  let local = case has_local || has_local_child {
    True ->
      Some(
        forest.FieldDelta([
          forest.Mark(1, attach, detach, local_fields),
        ]),
      )
    False -> None
  }
  let rename = list.map(moves, fn(move) { forest.Rename(move.0, move.1, 1) })
  Ok(FieldChangeDelta(local, global, rename))
}

fn validate_register(register: RegisterId) -> Result(Nil, TreeError) {
  case register {
    Active -> Ok(Nil)
    Detached(id) -> validate_atom(id)
  }
}

fn validate_atom(id: AtomId) -> Result(Nil, TreeError) {
  case id.local_id >= 0 && id.local_id <= max_safe_integer {
    True -> Ok(Nil)
    False -> Error(CorruptData("field change", "invalid atom identifier"))
  }
}

fn unique(values: List(a), location: String) -> Result(Nil, TreeError) {
  use _ <- result.try(
    list.try_fold(values, [], fn(seen, value) {
      case list.contains(seen, value) {
        True -> Error(CorruptData(location, "duplicate entry"))
        False -> Ok([value, ..seen])
      }
    }),
  )
  Ok(Nil)
}

fn replacement_source(replacement: Option(Replacement)) -> Option(RegisterId) {
  case replacement {
    None -> None
    Some(replacement) -> replacement.source
  }
}

fn effectful_destination(replacement: Option(Replacement)) -> Option(AtomId) {
  case replacement {
    Some(Replacement(False, source, destination)) if source != Some(Active) ->
      Some(destination)
    _ -> None
  }
}

fn replacement_effectful(replacement: Replacement) -> Bool {
  case replacement.source {
    Some(Active) -> False
    source -> !replacement.was_empty || source != None
  }
}

fn compose_source(
  first_source: Option(RegisterId),
  first_destination: Option(AtomId),
  second_source: Option(RegisterId),
  second_replacement: Option(Replacement),
  first_moves: List(#(AtomId, AtomId)),
) -> Option(RegisterId) {
  case second_source {
    Some(Active) -> option_or(second_source, first_source)
    Some(Detached(id)) ->
      case first_destination == Some(id) {
        True -> Some(Active)
        False ->
          Some(Detached(
            lookup_by_destination(first_moves, id)
            |> option_value(id),
          ))
      }
    None ->
      case first_source, second_replacement {
        Some(source), None -> Some(source)
        _, _ -> None
      }
  }
}

fn trace_register_back(
  register: RegisterId,
  first_source: Option(RegisterId),
  first_destination: Option(AtomId),
  first_moves: List(#(AtomId, AtomId)),
) -> RegisterId {
  case register {
    Active -> option_value(first_source, Active)
    Detached(id) ->
      case first_destination == Some(id) {
        True -> Active
        False ->
          Detached(lookup_by_destination(first_moves, id) |> option_value(id))
      }
  }
}

fn compose_first_children(
  children: List(#(RegisterId, AtomId)),
  second: List(#(RegisterId, AtomId)),
  state: s,
  compose_child: fn(Option(AtomId), Option(AtomId), s) ->
    Result(#(AtomId, s), TreeError),
  output: List(#(RegisterId, AtomId)),
) -> Result(
  #(List(#(RegisterId, AtomId)), List(#(RegisterId, AtomId)), s),
  TreeError,
) {
  case children {
    [] -> Ok(#(list.reverse(output), second, state))
    [child, ..rest] -> {
      let #(other, second) = take_child(second, child.0)
      use #(combined, state) <- result.try(compose_child(
        Some(child.1),
        other,
        state,
      ))
      compose_first_children(rest, second, state, compose_child, [
        #(child.0, combined),
        ..output
      ])
    }
  }
}

fn compose_remaining_children(
  children: List(#(RegisterId, AtomId)),
  state: s,
  compose_child: fn(Option(AtomId), Option(AtomId), s) ->
    Result(#(AtomId, s), TreeError),
  output: List(#(RegisterId, AtomId)),
) -> Result(#(List(#(RegisterId, AtomId)), s), TreeError) {
  case children {
    [] -> Ok(#(output, state))
    [child, ..rest] -> {
      use #(combined, state) <- result.try(compose_child(
        None,
        Some(child.1),
        state,
      ))
      compose_remaining_children(
        rest,
        state,
        compose_child,
        list.append(output, [#(child.0, combined)]),
      )
    }
  }
}

fn compose_second_moves(
  moves: List(#(AtomId, AtomId)),
  first_moves: List(#(AtomId, AtomId)),
  first_destination: Option(AtomId),
  output: List(#(AtomId, AtomId)),
) -> #(List(#(AtomId, AtomId)), List(#(AtomId, AtomId))) {
  case moves {
    [] -> #(list.reverse(output), first_moves)
    [move, ..rest] ->
      case lookup_by_destination(first_moves, move.0) {
        Some(original) ->
          compose_second_moves(
            rest,
            remove_source(first_moves, original),
            first_destination,
            [#(original, move.1), ..output],
          )
        None ->
          case first_destination == Some(move.0) {
            True ->
              compose_second_moves(rest, first_moves, first_destination, output)
            False ->
              compose_second_moves(rest, first_moves, first_destination, [
                move,
                ..output
              ])
          }
      }
  }
}

fn compose_replacement(
  first: Option(Replacement),
  second: Option(Replacement),
  second_moves: List(#(AtomId, AtomId)),
  source: Option(RegisterId),
) -> Result(Option(Replacement), TreeError) {
  case first, second {
    None, None -> Ok(None)
    _, _ -> {
      let first_change = case first {
        Some(replacement) -> replacement
        None -> {
          let assert Some(replacement) = second
          replacement
        }
      }
      use destination <- result.try(composed_destination(
        first,
        second,
        second_moves,
      ))
      Ok(Some(Replacement(first_change.was_empty, source, destination)))
    }
  }
}

fn composed_destination(
  first: Option(Replacement),
  second: Option(Replacement),
  second_moves: List(#(AtomId, AtomId)),
) -> Result(AtomId, TreeError) {
  case first, second {
    Some(first), None ->
      Ok(
        lookup_source(second_moves, first.detach_id)
        |> option_value(first.detach_id),
      )
    None, Some(second) -> Ok(second.detach_id)
    Some(first), Some(second) ->
      case
        first.source == Some(Active)
        || second.source == Some(Detached(first.detach_id))
      {
        True -> Ok(second.detach_id)
        False ->
          Ok(
            lookup_source(second_moves, first.detach_id)
            |> option_value(first.detach_id),
          )
      }
    None, None -> Error(CorruptData("field change", "replacement is missing"))
  }
}

fn lookup_source(
  moves: List(#(AtomId, AtomId)),
  source: AtomId,
) -> Option(AtomId) {
  case moves {
    [] -> None
    [move, ..rest] ->
      case move.0 == source {
        True -> Some(move.1)
        False -> lookup_source(rest, source)
      }
  }
}

fn lookup_by_destination(
  moves: List(#(AtomId, AtomId)),
  destination: AtomId,
) -> Option(AtomId) {
  case moves {
    [] -> None
    [move, ..rest] ->
      case move.1 == destination {
        True -> Some(move.0)
        False -> lookup_by_destination(rest, destination)
      }
  }
}

fn remove_source(
  moves: List(#(AtomId, AtomId)),
  source: AtomId,
) -> List(#(AtomId, AtomId)) {
  list.filter(moves, fn(move) { move.0 != source })
}

fn put_child(
  children: List(#(RegisterId, AtomId)),
  register: RegisterId,
  change: AtomId,
) -> List(#(RegisterId, AtomId)) {
  case children {
    [] -> [#(register, change)]
    [child, ..rest] ->
      case child.0 == register {
        True -> [#(register, change), ..rest]
        False -> [child, ..put_child(rest, register, change)]
      }
  }
}

fn take_child(
  children: List(#(RegisterId, AtomId)),
  register: RegisterId,
) -> #(Option(AtomId), List(#(RegisterId, AtomId))) {
  case children {
    [] -> #(None, [])
    [child, ..rest] ->
      case child.0 == register {
        True -> #(Some(child.1), rest)
        False -> {
          let #(found, rest) = take_child(rest, register)
          #(found, [child, ..rest])
        }
      }
  }
}

fn option_or(first: Option(a), second: Option(a)) -> Option(a) {
  case second {
    Some(_) -> second
    None -> first
  }
}

fn register_map_entries(
  original: List(#(RegisterId, AtomId)),
  remaining: List(#(RegisterId, AtomId)),
) -> List(#(RegisterId, AtomId)) {
  let groups =
    list.fold(original, [], fn(groups, child) {
      let group = register_group(child.0)
      case list.contains(groups, group) {
        True -> groups
        False -> list.append(groups, [group])
      }
    })
  list.flat_map(groups, fn(group) {
    list.filter(remaining, fn(child) { register_group(child.0) == group })
  })
}

fn register_group(register: RegisterId) -> RegisterGroup {
  case register {
    Active -> ActiveGroup
    Detached(id) -> DetachedGroup(id.local_id)
  }
}

fn option_value(value: Option(a), default: a) -> a {
  case value {
    Some(value) -> value
    None -> default
  }
}

fn check_allocator(value: Int) -> Result(Nil, TreeError) {
  case value >= -1 && value <= max_safe_integer {
    True -> Ok(Nil)
    False ->
      Error(CorruptData("field allocator", "invalid allocation watermark"))
  }
}

fn allocate(
  revision: Option(StableId),
  max_local_id: Int,
) -> Result(#(AtomId, Int), TreeError) {
  case max_local_id < max_safe_integer {
    True -> {
      let next = max_local_id + 1
      Ok(#(AtomId(revision, next), next))
    }
    False -> Error(CorruptData("field allocator", "identifiers are exhausted"))
  }
}

fn invert_replacement(
  replacement: Option(Replacement),
  is_rollback: Bool,
  revision: Option(StableId),
  max_local_id: Int,
) -> Result(#(Option(Replacement), Int), TreeError) {
  case replacement {
    None -> Ok(#(None, max_local_id))
    Some(replacement) ->
      case replacement_effectful(replacement) {
        True -> {
          use #(destination, max_local_id) <- result.try(
            case replacement.source {
              None -> allocate(revision, max_local_id)
              Some(Detached(source)) ->
                case is_rollback {
                  True -> Ok(#(source, max_local_id))
                  False -> allocate(revision, max_local_id)
                }
              Some(Active) ->
                Error(CorruptData("field change", "active source is effectful"))
            },
          )
          let source = case replacement.was_empty {
            True -> None
            False -> Some(Detached(replacement.detach_id))
          }
          Ok(#(
            Some(Replacement(replacement.source == None, source, destination)),
            max_local_id,
          ))
        }
        False ->
          case !is_rollback && replacement.source == Some(Active) {
            False -> Ok(#(None, max_local_id))
            True -> {
              use #(destination, max_local_id) <- result.try(allocate(
                revision,
                max_local_id,
              ))
              Ok(#(
                Some(Replacement(False, Some(Active), destination)),
                max_local_id,
              ))
            }
          }
      }
  }
}

fn put_register(
  mapping: List(#(RegisterId, RegisterId)),
  source: RegisterId,
  destination: RegisterId,
) -> List(#(RegisterId, RegisterId)) {
  case mapping {
    [] -> [#(source, destination)]
    [entry, ..rest] ->
      case entry.0 == source {
        True -> [#(source, destination), ..rest]
        False -> [entry, ..put_register(rest, source, destination)]
      }
  }
}

fn lookup_register(
  mapping: List(#(RegisterId, RegisterId)),
  source: RegisterId,
) -> Option(RegisterId) {
  case mapping {
    [] -> None
    [entry, ..rest] ->
      case entry.0 == source {
        True -> Some(entry.1)
        False -> lookup_register(rest, source)
      }
  }
}

fn rebase_authored_children(
  children: List(#(RegisterId, AtomId)),
  over_children: List(#(RegisterId, AtomId)),
  forward: List(#(RegisterId, RegisterId)),
  state: s,
  rebase_child: fn(Option(AtomId), Option(AtomId), AttachState, s) ->
    Result(#(Option(AtomId), s), TreeError),
  output: List(#(RegisterId, AtomId)),
) -> Result(
  #(List(#(RegisterId, AtomId)), List(#(RegisterId, AtomId)), s),
  TreeError,
) {
  case children {
    [] -> Ok(#(list.reverse(output), over_children, state))
    [child, ..rest] -> {
      let #(over_child, over_children) = take_child(over_children, child.0)
      let register = lookup_register(forward, child.0) |> option_value(child.0)
      use #(rebased, state) <- result.try(rebase_child(
        Some(child.1),
        over_child,
        attach_state(register),
        state,
      ))
      let output = case rebased {
        None -> output
        Some(rebased) -> [#(register, rebased), ..output]
      }
      rebase_authored_children(
        rest,
        over_children,
        forward,
        state,
        rebase_child,
        output,
      )
    }
  }
}

fn rebase_base_children(
  children: List(#(RegisterId, AtomId)),
  forward: List(#(RegisterId, RegisterId)),
  state: s,
  rebase_child: fn(Option(AtomId), Option(AtomId), AttachState, s) ->
    Result(#(Option(AtomId), s), TreeError),
  output: List(#(RegisterId, AtomId)),
) -> Result(#(List(#(RegisterId, AtomId)), s), TreeError) {
  case children {
    [] -> Ok(#(output, state))
    [child, ..rest] -> {
      let register = lookup_register(forward, child.0) |> option_value(child.0)
      use #(rebased, state) <- result.try(rebase_child(
        None,
        Some(child.1),
        attach_state(register),
        state,
      ))
      let output = case rebased {
        None -> output
        Some(rebased) -> list.append(output, [#(register, rebased)])
      }
      rebase_base_children(rest, forward, state, rebase_child, output)
    }
  }
}

fn attach_state(register: RegisterId) -> AttachState {
  case register {
    Active -> Attached
    Detached(_) -> DetachedNode
  }
}

fn replace_register(
  register: RegisterId,
  replace: fn(AtomId) -> Result(AtomId, TreeError),
) -> Result(RegisterId, TreeError) {
  case register {
    Active -> Ok(Active)
    Detached(id) -> replace(id) |> result.map(Detached)
  }
}
