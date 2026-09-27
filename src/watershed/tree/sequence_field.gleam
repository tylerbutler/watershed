//// Checked sequence-field marks, editors, and delta conversion.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{type Order}
import gleam/result
import watershed/fluid_ids.{type StableId}
import watershed/tree/forest
import watershed/tree/types.{type AtomId, type TreeError, AtomId, CorruptData}

const max_safe_integer = 9_007_199_254_740_991

pub type Attach {
  Insert(id: AtomId)
  MoveIn(id: AtomId, final_endpoint: Option(AtomId))
}

pub type Detach {
  Remove(id: AtomId, id_override: Option(AtomId))
  MoveOut(
    id: AtomId,
    final_endpoint: Option(AtomId),
    id_override: Option(AtomId),
  )
}

pub type Effect {
  Noop
  Attach(Attach)
  Detach(Detach)
  AttachAndDetach(attach: Attach, detach: Detach)
  Rename(id_override: AtomId)
}

pub type Mark {
  Mark(
    count: Int,
    cell_id: Option(AtomId),
    effect: Effect,
    child: Option(AtomId),
  )
}

pub opaque type Changeset {
  Changeset(marks: List(Mark))
}

pub type DeltaResult {
  DeltaResult(
    local: Option(forest.FieldDelta),
    global: List(forest.DetachedChange),
    rename: List(forest.Rename),
  )
}

pub type AlgebraContext {
  AlgebraContext(
    compare_atoms: fn(AtomId, AtomId) -> Result(Order, TreeError),
    revision_index: fn(StableId) -> Result(Int, TreeError),
    rollback_of: fn(StableId) -> Result(Option(StableId), TreeError),
  )
}

pub opaque type AliasContext {
  AliasContext(
    reservations: List(#(Option(StableId), Int, Int)),
    max_local_id: Int,
  )
}

pub fn new_alias_context(
  reservations: List(#(Option(StableId), Int)),
) -> Result(AliasContext, TreeError) {
  list.try_fold(reservations, AliasContext([], -1), fn(context, reservation) {
    reserve_alias(context, reservation.0, reservation.1)
  })
}

pub fn alias(
  id: AtomId,
  context: AliasContext,
) -> Result(#(Int, AliasContext), TreeError) {
  let AliasContext(reservations, _) = context
  case list.find(reservations, fn(entry) { entry.0 == id.revision }) {
    Error(Nil) ->
      Error(CorruptData("sequence aliases", "revision is not reserved"))
    Ok(#(_, original_max, offset)) -> {
      use _ <- result.try(check(
        id.local_id >= 0 && id.local_id <= original_max,
        "alias source exceeds its reservation",
      ))
      use _ <- result.try(check(
        id.local_id <= max_safe_integer - offset,
        "alias exceeds the safe integer range",
      ))
      Ok(#(id.local_id + offset, context))
    }
  }
}

pub fn alias_max_id(context: AliasContext) -> Int {
  context.max_local_id
}

pub fn from_marks(marks: List(Mark)) -> Result(Changeset, TreeError) {
  use normalized <- result.try(normalize_marks(marks, [], 0, 0))
  Ok(Changeset(trim_trailing_skips(normalized)))
}

pub fn to_marks(change: Changeset) -> List(Mark) {
  change.marks
}

pub fn split_mark(mark: Mark, split: Int) -> Result(#(Mark, Mark), TreeError) {
  use _ <- result.try(validate_mark(mark))
  use _ <- result.try(check(
    split > 0 && split < mark.count,
    "split is outside the mark",
  ))
  let second_count = mark.count - split
  let #(first_effect, second_effect) = split_effect(mark.effect, split)
  let first = Mark(split, mark.cell_id, first_effect, mark.child)
  let second =
    Mark(
      second_count,
      option.map(mark.cell_id, offset_atom(_, split)),
      second_effect,
      mark.child,
    )
  use _ <- result.try(validate_mark(first))
  use _ <- result.try(validate_mark(second))
  Ok(#(first, second))
}

pub fn insert(
  index: Int,
  count: Int,
  first_cell: AtomId,
  revision: Option(StableId),
) -> Result(Changeset, TreeError) {
  use _ <- result.try(validate_editor_range(index, count, "insert"))
  use _ <- result.try(validate_atom(first_cell, int.max(1, count)))
  case count {
    0 -> Ok(Changeset([]))
    _ ->
      from_marks(mark_at(
        index,
        Mark(
          count,
          Some(first_cell),
          Attach(Insert(AtomId(revision, first_cell.local_id))),
          None,
        ),
      ))
  }
}

pub fn remove(
  index: Int,
  count: Int,
  first_id: AtomId,
) -> Result(Changeset, TreeError) {
  use _ <- result.try(validate_editor_range(index, count, "remove"))
  use _ <- result.try(validate_atom(first_id, int.max(1, count)))
  case count {
    0 -> Ok(Changeset([]))
    _ ->
      from_marks(mark_at(
        index,
        Mark(count, None, Detach(Remove(first_id, None)), None),
      ))
  }
}

pub fn move(
  source: Int,
  count: Int,
  destination_gap: Int,
  detach_id: AtomId,
  attach_id: AtomId,
) -> Result(Changeset, TreeError) {
  use _ <- result.try(validate_editor_range(source, count, "move source"))
  use _ <- result.try(validate_index(destination_gap, "move destination"))
  use _ <- result.try(validate_atom(detach_id, int.max(1, count)))
  use _ <- result.try(validate_atom(attach_id, int.max(1, count)))
  case count {
    0 -> Ok(Changeset([]))
    _ -> {
      let detach =
        Mark(count, None, Detach(MoveOut(detach_id, None, None)), None)
      let attach =
        Mark(count, Some(attach_id), Attach(MoveIn(detach_id, None)), None)
      let end = source + count
      case destination_gap <= source, destination_gap >= end {
        True, _ ->
          from_marks(
            marks_with_gap(
              int.min(source, destination_gap),
              [attach],
              source - destination_gap,
              [detach],
            ),
          )
        False, True ->
          from_marks(
            marks_with_gap(
              int.min(source, destination_gap),
              [detach],
              destination_gap - end,
              [attach],
            ),
          )
        False, False -> {
          use #(first, second) <- result.try(split_mark(
            detach,
            destination_gap - source,
          ))
          from_marks(marks_with_gap(source, [first, attach, second], 0, []))
        }
      }
    }
  }
}

pub fn move_out(
  index: Int,
  count: Int,
  id: AtomId,
) -> Result(Changeset, TreeError) {
  use _ <- result.try(validate_editor_range(index, count, "move-out"))
  use _ <- result.try(validate_atom(id, int.max(1, count)))
  case count {
    0 -> Ok(Changeset([]))
    _ ->
      from_marks(mark_at(
        index,
        Mark(count, None, Detach(MoveOut(id, None, None)), None),
      ))
  }
}

pub fn move_in(
  index: Int,
  count: Int,
  id: AtomId,
  cell_id: AtomId,
) -> Result(Changeset, TreeError) {
  use _ <- result.try(validate_editor_range(index, count, "move-in"))
  use _ <- result.try(validate_atom(id, int.max(1, count)))
  use _ <- result.try(validate_atom(cell_id, int.max(1, count)))
  case count {
    0 -> Ok(Changeset([]))
    _ ->
      from_marks(mark_at(
        index,
        Mark(count, Some(cell_id), Attach(MoveIn(id, None)), None),
      ))
  }
}

pub fn build_child_changes(
  changes: List(#(Int, AtomId)),
) -> Result(Changeset, TreeError) {
  use marks <- result.try(build_children(changes, 0, []))
  from_marks(list.reverse(marks))
}

pub fn into_delta(
  change: Changeset,
  child_delta: fn(AtomId) ->
    Result(List(#(String, forest.FieldDelta)), TreeError),
) -> Result(DeltaResult, TreeError) {
  use _ <- result.try(validate_changeset(change))
  use output <- result.try(
    list.try_fold(change.marks, #([], [], []), fn(output, mark) {
      use fields <- result.try(case mark.child {
        None -> Ok([])
        Some(child) -> child_delta(child)
      })
      let #(local_fields, global) = case mark.cell_id, fields {
        _, [] -> #([], output.1)
        None, fields -> #(fields, output.1)
        Some(id), fields -> #([], [
          forest.DetachedChange(id, fields),
          ..output.1
        ])
      }

      delta_mark(mark, local_fields, output.0, global, output.2)
    }),
  )
  let local_marks =
    output.0
    |> list.reverse
    |> trim_trailing_delta_skips
  let local = case local_marks {
    [] -> None
    marks -> Some(forest.FieldDelta(marks))
  }
  Ok(DeltaResult(local, list.reverse(output.1), list.reverse(output.2)))
}

pub fn replace_revisions(
  change: Changeset,
  replace: fn(AtomId, Int) -> Result(AtomId, TreeError),
) -> Result(Changeset, TreeError) {
  use marks <- result.try(
    list.try_map(change.marks, fn(mark) {
      use cell_id <- result.try(replace_optional(
        mark.cell_id,
        mark.count,
        replace,
      ))
      use effect <- result.try(replace_effect(mark.effect, mark.count, replace))
      use child <- result.try(replace_optional(mark.child, 1, replace))
      Ok(Mark(mark.count, cell_id, effect, child))
    }),
  )
  from_marks(marks)
}

pub fn prune(
  change: Changeset,
  prune_child: fn(AtomId) -> Result(Option(AtomId), TreeError),
) -> Result(Changeset, TreeError) {
  use marks <- result.try(
    list.try_map(change.marks, fn(mark) {
      use child <- result.try(case mark.child {
        None -> Ok(None)
        Some(child) -> prune_child(child)
      })
      Ok(Mark(..mark, child:))
    }),
  )
  from_marks(marks)
}

pub fn relevant_removed_roots(
  change: Changeset,
  roots_from_child: fn(AtomId) -> Result(List(AtomId), TreeError),
) -> Result(List(AtomId), TreeError) {
  list.try_fold(change.marks, [], fn(roots, mark) {
    let own = case mark.cell_id, refers_to_removed_root(mark) {
      Some(id), True -> atom_range(id, mark.count)
      _, _ -> []
    }
    use child_roots <- result.try(case mark.child {
      None -> Ok([])
      Some(child) -> roots_from_child(child)
    })
    Ok(list.append(roots, list.append(own, child_roots)))
  })
}

fn normalize_marks(
  marks: List(Mark),
  output: List(Mark),
  input_total: Int,
  output_total: Int,
) -> Result(List(Mark), TreeError) {
  case marks {
    [] -> Ok(list.reverse(output))
    [mark, ..rest] -> {
      use _ <- result.try(validate_mark(mark))
      let input_count = input_length(mark)
      let output_count = output_length(mark)
      use _ <- result.try(check(
        input_total <= max_safe_integer - input_count,
        "mark input length overflows",
      ))
      use _ <- result.try(check(
        output_total <= max_safe_integer - output_count,
        "mark output length overflows",
      ))
      case output {
        [previous, ..output_rest] ->
          case merge_marks(previous, mark) {
            Some(merged) ->
              normalize_marks(
                rest,
                [merged, ..output_rest],
                input_total + input_count,
                output_total + output_count,
              )
            None ->
              normalize_marks(
                rest,
                [mark, ..output],
                input_total + input_count,
                output_total + output_count,
              )
          }
        [] ->
          normalize_marks(
            rest,
            [mark],
            input_total + input_count,
            output_total + output_count,
          )
      }
    }
  }
}

fn validate_changeset(change: Changeset) -> Result(Nil, TreeError) {
  use _ <- result.try(normalize_marks(change.marks, [], 0, 0))
  Ok(Nil)
}

fn validate_mark(mark: Mark) -> Result(Nil, TreeError) {
  use _ <- result.try(check(
    mark.count > 0 && mark.count <= max_safe_integer,
    "mark count is outside the safe range",
  ))
  use _ <- result.try(validate_optional_atom(mark.cell_id, mark.count))
  use _ <- result.try(validate_effect(mark.effect, mark.count))
  use _ <- result.try(case mark.child {
    None -> Ok(Nil)
    Some(child) -> {
      use _ <- result.try(check(
        mark.count == 1,
        "a child change must target one cell",
      ))
      validate_atom(child, 1)
    }
  })
  case mark.effect {
    Attach(MoveIn(_, _)) | AttachAndDetach(_, _) | Rename(_) ->
      check(mark.cell_id != None, "an empty-cell effect requires a cell ID")
    _ -> Ok(Nil)
  }
}

fn validate_effect(effect: Effect, count: Int) -> Result(Nil, TreeError) {
  case effect {
    Noop -> Ok(Nil)
    Attach(attach) -> validate_attach(attach, count)
    Detach(detach) -> validate_detach_range(detach, count)
    AttachAndDetach(attach, detach) -> {
      use _ <- result.try(validate_attach(attach, count))
      validate_detach_range(detach, count)
    }
    Rename(id) -> validate_atom(id, count)
  }
}

fn validate_attach(attach: Attach, count: Int) -> Result(Nil, TreeError) {
  case attach {
    Insert(id) -> validate_atom(id, count)
    MoveIn(id, endpoint) -> {
      use _ <- result.try(validate_atom(id, count))
      validate_optional_atom(endpoint, count)
    }
  }
}

@internal
pub fn validate_detach_range(
  detach: Detach,
  count: Int,
) -> Result(Nil, TreeError) {
  case detach {
    Remove(id, id_override) -> {
      use _ <- result.try(validate_atom(id, count))
      validate_optional_atom(id_override, count)
    }

    MoveOut(id, final_endpoint, id_override) -> {
      use _ <- result.try(validate_atom(id, count))
      use _ <- result.try(validate_optional_atom(final_endpoint, count))
      validate_optional_atom(id_override, count)
    }
  }
}

@internal
pub fn offset_detach(detach: Detach, split: Int) -> Detach {
  split_detach(detach, split).1
}

fn validate_optional_atom(
  id: Option(AtomId),
  count: Int,
) -> Result(Nil, TreeError) {
  case id {
    None -> Ok(Nil)
    Some(id) -> validate_atom(id, count)
  }
}

fn validate_atom(id: AtomId, count: Int) -> Result(Nil, TreeError) {
  check(
    id.local_id >= 0
      && id.local_id <= max_safe_integer
      && count > 0
      && count <= max_safe_integer
      && count - 1 <= max_safe_integer - id.local_id,
    "identifier range is outside the safe range",
  )
}

fn validate_editor_range(
  index: Int,
  count: Int,
  location: String,
) -> Result(Nil, TreeError) {
  use _ <- result.try(validate_index(index, location))
  use _ <- result.try(check(
    count >= 0 && count <= max_safe_integer,
    location <> " count is outside the safe range",
  ))
  check(count <= max_safe_integer - index, location <> " range overflows")
}

fn validate_index(index: Int, location: String) -> Result(Nil, TreeError) {
  check(
    index >= 0 && index <= max_safe_integer,
    location <> " index is outside the safe range",
  )
}

fn check(valid: Bool, detail: String) -> Result(Nil, TreeError) {
  case valid {
    True -> Ok(Nil)
    False -> Error(CorruptData("sequence field", detail))
  }
}

fn mark_at(index: Int, mark: Mark) -> List(Mark) {
  case index {
    0 -> [mark]
    _ -> [Mark(index, None, Noop, None), mark]
  }
}

fn marks_with_gap(
  start: Int,
  first: List(Mark),
  gap: Int,
  second: List(Mark),
) -> List(Mark) {
  let prefix = case start {
    0 -> []
    _ -> [Mark(start, None, Noop, None)]
  }
  let middle = case gap {
    0 -> []
    _ -> [Mark(gap, None, Noop, None)]
  }
  list.append(prefix, list.append(first, list.append(middle, second)))
}

fn split_effect(effect: Effect, split: Int) -> #(Effect, Effect) {
  case effect {
    Noop -> #(Noop, Noop)
    Attach(attach) -> {
      let #(first, second) = split_attach(attach, split)
      #(Attach(first), Attach(second))
    }
    Detach(detach) -> {
      let #(first, second) = split_detach(detach, split)
      #(Detach(first), Detach(second))
    }
    AttachAndDetach(attach, detach) -> {
      let #(first_attach, second_attach) = split_attach(attach, split)
      let #(first_detach, second_detach) = split_detach(detach, split)
      #(
        AttachAndDetach(first_attach, first_detach),
        AttachAndDetach(second_attach, second_detach),
      )
    }
    Rename(id_override) -> #(
      Rename(id_override),
      Rename(offset_atom(id_override, split)),
    )
  }
}

fn split_attach(attach: Attach, split: Int) -> #(Attach, Attach) {
  case attach {
    Insert(id) -> #(Insert(id), Insert(offset_atom(id, split)))
    MoveIn(id, final_endpoint) -> #(
      MoveIn(id, final_endpoint),
      MoveIn(
        offset_atom(id, split),
        option.map(final_endpoint, offset_atom(_, split)),
      ),
    )
  }
}

fn split_detach(detach: Detach, split: Int) -> #(Detach, Detach) {
  case detach {
    Remove(id, id_override) -> #(
      Remove(id, id_override),
      Remove(
        offset_atom(id, split),
        option.map(id_override, offset_atom(_, split)),
      ),
    )
    MoveOut(id, final_endpoint, id_override) -> #(
      MoveOut(id, final_endpoint, id_override),
      MoveOut(
        offset_atom(id, split),
        option.map(final_endpoint, offset_atom(_, split)),
        option.map(id_override, offset_atom(_, split)),
      ),
    )
  }
}

@internal
pub fn offset_atom(id: AtomId, amount: Int) -> AtomId {
  AtomId(..id, local_id: id.local_id + amount)
}

fn trim_trailing_skips(marks: List(Mark)) -> List(Mark) {
  marks
  |> list.reverse
  |> drop_plain_skips
  |> list.reverse
}

fn drop_plain_skips(marks: List(Mark)) -> List(Mark) {
  case marks {
    [Mark(_, None, Noop, None), ..rest] -> drop_plain_skips(rest)
    _ -> marks
  }
}

fn merge_marks(first: Mark, second: Mark) -> Option(Mark) {
  case
    first.count <= max_safe_integer - second.count,
    first.child,
    second.child
  {
    True, None, None ->
      case
        merge_optional_atoms(first.cell_id, first.count, second.cell_id),
        merge_effects(first.effect, first.count, second.effect)
      {
        True, Some(effect) ->
          Some(Mark(first.count + second.count, first.cell_id, effect, None))
        _, _ -> None
      }
    _, _, _ -> None
  }
}

fn merge_effects(first: Effect, count: Int, second: Effect) -> Option(Effect) {
  case first, second {
    Noop, Noop -> Some(Noop)
    Attach(first), Attach(second) ->
      merge_attaches(first, count, second) |> option.map(Attach)
    Detach(first), Detach(second) ->
      merge_detaches(first, count, second) |> option.map(Detach)
    AttachAndDetach(first_attach, first_detach),
      AttachAndDetach(second_attach, second_detach)
    ->
      case
        merge_attaches(first_attach, count, second_attach),
        merge_detaches(first_detach, count, second_detach)
      {
        Some(attach), Some(detach) -> Some(AttachAndDetach(attach, detach))
        _, _ -> None
      }
    Rename(first), Rename(second) ->
      case adjacent_atoms(first, count, second) {
        True -> Some(Rename(first))
        False -> None
      }
    _, _ -> None
  }
}

fn merge_attaches(first: Attach, count: Int, second: Attach) -> Option(Attach) {
  case first, second {
    Insert(first), Insert(second) ->
      case adjacent_atoms(first, count, second) {
        True -> Some(Insert(first))
        False -> None
      }
    MoveIn(first_id, first_endpoint), MoveIn(second_id, second_endpoint) ->
      case
        adjacent_atoms(first_id, count, second_id),
        merge_optional_atoms(first_endpoint, count, second_endpoint)
      {
        True, True -> Some(MoveIn(first_id, first_endpoint))
        _, _ -> None
      }
    _, _ -> None
  }
}

fn merge_detaches(first: Detach, count: Int, second: Detach) -> Option(Detach) {
  case first, second {
    Remove(first_id, first_override), Remove(second_id, second_override) ->
      case
        adjacent_atoms(first_id, count, second_id),
        merge_optional_atoms(first_override, count, second_override)
      {
        True, True -> Some(Remove(first_id, first_override))
        _, _ -> None
      }
    MoveOut(first_id, first_endpoint, first_override),
      MoveOut(second_id, second_endpoint, second_override)
    ->
      case
        adjacent_atoms(first_id, count, second_id),
        merge_optional_atoms(first_endpoint, count, second_endpoint),
        merge_optional_atoms(first_override, count, second_override)
      {
        True, True, True ->
          Some(MoveOut(first_id, first_endpoint, first_override))
        _, _, _ -> None
      }
    _, _ -> None
  }
}

fn merge_optional_atoms(
  first: Option(AtomId),
  count: Int,
  second: Option(AtomId),
) -> Bool {
  case first, second {
    None, None -> True
    Some(first), Some(second) -> adjacent_atoms(first, count, second)
    _, _ -> False
  }
}

fn adjacent_atoms(first: AtomId, count: Int, second: AtomId) -> Bool {
  first.revision == second.revision
  && first.local_id <= max_safe_integer - count
  && first.local_id + count == second.local_id
}

fn build_children(
  changes: List(#(Int, AtomId)),
  next_index: Int,
  marks: List(Mark),
) -> Result(List(Mark), TreeError) {
  case changes {
    [] -> Ok(marks)
    [#(index, child), ..rest] -> {
      use _ <- result.try(validate_index(index, "child"))
      use _ <- result.try(validate_atom(child, 1))
      use _ <- result.try(check(
        index >= next_index,
        "child indices must be strictly ordered",
      ))
      let marks = case index - next_index {
        0 -> marks
        gap -> [Mark(gap, None, Noop, None), ..marks]
      }
      build_children(rest, index + 1, [
        Mark(1, None, Noop, Some(child)),
        ..marks
      ])
    }
  }
}

fn delta_mark(
  mark: Mark,
  fields: List(#(String, forest.FieldDelta)),
  local: List(forest.Mark),
  global: List(forest.DetachedChange),
  renames: List(forest.Rename),
) -> Result(
  #(List(forest.Mark), List(forest.DetachedChange), List(forest.Rename)),
  TreeError,
) {
  let input_empty = mark.cell_id != None
  let output_empty = output_cells_empty(mark)
  case input_empty, output_empty, mark.effect {
    False, False, _ ->
      Ok(#(
        [forest.Mark(mark.count, None, None, fields), ..local],
        global,
        renames,
      ))
    True, True, AttachAndDetach(MoveIn(_, _), MoveOut(_, _, _)) ->
      check(mark.child == None, "paired move rename cannot contain a child")
      |> result.map(fn(_) { #(local, global, renames) })
    True, True, AttachAndDetach(attach, detach) -> {
      let assert Some(input_id) = mark.cell_id
      let output_id = detached_id(detach)
      let old_id = case attach {
        MoveIn(id, endpoint) -> option.unwrap(endpoint, id)
        Insert(_) -> input_id
      }
      let renames = case input_id == output_id {
        True -> renames
        False -> [forest.Rename(old_id, output_id, mark.count), ..renames]
      }
      Ok(#(local, global, renames))
    }
    _, _, Attach(MoveIn(id, endpoint)) -> {
      Ok(#(
        [
          forest.Mark(mark.count, Some(option.unwrap(endpoint, id)), None, []),
          ..local
        ],
        global,
        renames,
      ))
    }
    _, _, Attach(Insert(_)) -> {
      let assert Some(id) = mark.cell_id
      Ok(#(
        [forest.Mark(mark.count, Some(id), None, []), ..local],
        global,
        renames,
      ))
    }
    False, True, Detach(detach) ->
      Ok(#(
        [
          forest.Mark(mark.count, None, Some(detached_id(detach)), fields),
          ..local
        ],
        global,
        renames,
      ))
    True, True, Detach(Remove(_, _)) -> {
      let assert Some(old_id) = mark.cell_id
      let new_id = case mark.effect {
        Detach(detach) -> detached_id(detach)
        _ -> old_id
      }
      let renames = case old_id == new_id {
        True -> renames
        False -> [forest.Rename(old_id, new_id, mark.count), ..renames]
      }
      Ok(#(local, global, renames))
    }
    True, True, Detach(MoveOut(id, _, _)) -> {
      let assert Some(old_id) = mark.cell_id
      Ok(#(local, global, [forest.Rename(old_id, id, mark.count), ..renames]))
    }
    _, _, Noop | _, _, Rename(_) -> Ok(#(local, global, renames))
    True, False, Detach(_) ->
      Error(CorruptData("sequence field", "invalid detach state"))
    _, _, AttachAndDetach(_, _) ->
      Error(CorruptData("sequence field", "invalid attach-and-detach state"))
  }
}

fn output_cells_empty(mark: Mark) -> Bool {
  case mark.effect {
    Noop -> mark.cell_id != None
    Attach(_) -> False
    Detach(_) | AttachAndDetach(_, _) | Rename(_) -> True
  }
}

@internal
pub fn input_length(mark: Mark) -> Int {
  case mark.cell_id {
    None -> mark.count
    Some(_) -> 0
  }
}

@internal
pub fn output_length(mark: Mark) -> Int {
  case output_cells_empty(mark) {
    True -> 0
    False -> mark.count
  }
}

@internal
pub fn detached_id(detach: Detach) -> AtomId {
  case detach {
    Remove(_, Some(id_override)) -> id_override
    Remove(id, None) -> id
    MoveOut(id, _, _) -> id
  }
}

@internal
pub fn output_cell_id(mark: Mark) -> Option(AtomId) {
  case mark.effect {
    Detach(detach) -> Some(detached_id(detach))
    Rename(id) -> Some(id)
    AttachAndDetach(_, detach) -> Some(detached_id(detach))
    Attach(_) -> None
    Noop -> mark.cell_id
  }
}

fn trim_trailing_delta_skips(marks: List(forest.Mark)) -> List(forest.Mark) {
  marks
  |> list.reverse
  |> drop_delta_skips
  |> list.reverse
}

fn drop_delta_skips(marks: List(forest.Mark)) -> List(forest.Mark) {
  case marks {
    [forest.Mark(_, None, None, []), ..rest] -> drop_delta_skips(rest)
    _ -> marks
  }
}

fn reserve_alias(
  context: AliasContext,
  revision: Option(StableId),
  original_max: Int,
) -> Result(AliasContext, TreeError) {
  let AliasContext(reservations, max_local_id) = context
  use _ <- result.try(check(
    original_max >= -1 && original_max <= max_safe_integer,
    "alias reservation is outside the safe integer range",
  ))
  case list.find(reservations, fn(entry) { entry.0 == revision }) {
    Ok(#(_, found, _)) ->
      case found == original_max {
        True -> Ok(context)
        False ->
          Error(CorruptData(
            "sequence aliases",
            "revision has inconsistent reservations",
          ))
      }
    Error(Nil) -> {
      let count = original_max + 1
      let offset = max_local_id + 1
      use _ <- result.try(check(
        count == 0 || offset <= max_safe_integer - count,
        "alias reservation exceeds the safe integer range",
      ))
      Ok(AliasContext(
        list.append(reservations, [#(revision, original_max, offset)]),
        max_local_id + count,
      ))
    }
  }
}

fn replace_effect(
  effect: Effect,
  count: Int,
  replace: fn(AtomId, Int) -> Result(AtomId, TreeError),
) -> Result(Effect, TreeError) {
  case effect {
    Noop -> Ok(Noop)
    Rename(id) -> replace(id, count) |> result.map(Rename)
    Attach(attach) ->
      replace_attach(attach, count, replace) |> result.map(Attach)
    Detach(detach) ->
      replace_detach(detach, count, replace) |> result.map(Detach)
    AttachAndDetach(attach, detach) -> {
      use attach <- result.try(replace_attach(attach, count, replace))
      use detach <- result.try(replace_detach(detach, count, replace))
      Ok(AttachAndDetach(attach, detach))
    }
  }
}

fn replace_attach(
  attach: Attach,
  count: Int,
  replace: fn(AtomId, Int) -> Result(AtomId, TreeError),
) -> Result(Attach, TreeError) {
  case attach {
    Insert(id) -> replace(id, count) |> result.map(Insert)
    MoveIn(id, endpoint) -> {
      use id <- result.try(replace(id, count))
      use endpoint <- result.try(replace_optional(endpoint, count, replace))
      Ok(MoveIn(id, endpoint))
    }
  }
}

fn replace_detach(
  detach: Detach,
  count: Int,
  replace: fn(AtomId, Int) -> Result(AtomId, TreeError),
) -> Result(Detach, TreeError) {
  case detach {
    Remove(id, id_override) -> {
      use id <- result.try(replace(id, count))
      use id_override <- result.try(replace_optional(
        id_override,
        count,
        replace,
      ))
      Ok(Remove(id, id_override))
    }
    MoveOut(id, endpoint, id_override) -> {
      use id <- result.try(replace(id, count))
      use endpoint <- result.try(replace_optional(endpoint, count, replace))
      use id_override <- result.try(replace_optional(
        id_override,
        count,
        replace,
      ))
      Ok(MoveOut(id, endpoint, id_override))
    }
  }
}

fn replace_optional(
  id: Option(AtomId),
  count: Int,
  replace: fn(AtomId, Int) -> Result(AtomId, TreeError),
) -> Result(Option(AtomId), TreeError) {
  case id {
    None -> Ok(None)
    Some(id) -> replace(id, count) |> result.map(Some)
  }
}

fn refers_to_removed_root(mark: Mark) -> Bool {
  case mark.cell_id {
    None -> False
    Some(_) ->
      case mark.effect {
        Attach(Insert(_)) | AttachAndDetach(Insert(_), _) -> True
        Detach(_) -> True
        _ -> mark.child != None
      }
  }
}

fn atom_range(id: AtomId, count: Int) -> List(AtomId) {
  atom_range_loop(id, count, [])
}

fn atom_range_loop(
  id: AtomId,
  count: Int,
  output: List(AtomId),
) -> List(AtomId) {
  case count {
    0 -> list.reverse(output)
    _ ->
      atom_range_loop(AtomId(..id, local_id: id.local_id + 1), count - 1, [
        id,
        ..output
      ])
  }
}
