//// Counted rebase for sequence-field changes.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Gt, Lt}
import gleam/result
import watershed/fluid_ids.{type StableId}
import watershed/tree/sequence_field
import watershed/tree/sequence_field/moves
import watershed/tree/types.{type AtomId, type TreeError, CorruptData}

type CellOrder {
  SameCell
  OldThenNew
  NewThenOld
}

pub fn rebase(
  authored: sequence_field.Changeset,
  over: sequence_field.Changeset,
  state: state,
  rebase_child: fn(
    Option(AtomId),
    Option(AtomId),
    sequence_field.AttachState,
    state,
  ) -> Result(#(Option(AtomId), state), TreeError),
  algebra: sequence_field.AlgebraContext,
  field: moves.FieldId,
  move_context: moves.Context,
) -> Result(#(sequence_field.Changeset, state, moves.Context), TreeError) {
  let authored_marks = sequence_field.to_marks(authored)
  let over_marks = sequence_field.to_marks(over)
  let authored_sources = cell_sources(authored_marks)
  let over_sources = cell_sources(over_marks)
  use #(marks, state, move_context) <- result.try(
    rebase_loop(
      authored_marks,
      over_marks,
      authored_sources,
      over_sources,
      state,
      rebase_child,
      algebra,
      field,
      move_context,
      [],
    ),
  )
  use change <- result.try(sequence_field.from_marks(list.reverse(marks)))
  Ok(#(change, state, move_context))
}

fn rebase_loop(
  authored: List(sequence_field.Mark),
  over: List(sequence_field.Mark),
  authored_sources: List(Option(StableId)),
  over_sources: List(Option(StableId)),
  state: state,
  rebase_child: fn(
    Option(AtomId),
    Option(AtomId),
    sequence_field.AttachState,
    state,
  ) -> Result(#(Option(AtomId), state), TreeError),
  algebra: sequence_field.AlgebraContext,
  field: moves.FieldId,
  move_context: moves.Context,
  output: List(sequence_field.Mark),
) -> Result(#(List(sequence_field.Mark), state, moves.Context), TreeError) {
  use #(authored, move_context) <- result.try(prepare(
    authored,
    field,
    move_context,
  ))
  use #(over, move_context) <- result.try(prepare(over, field, move_context))
  case authored, over {
    [], [] -> Ok(#(output, state, move_context))
    [authored_mark, ..authored_rest], [] -> {
      let base_mark = noop(authored_mark.count, authored_mark.cell_id)
      use #(mark, state, move_context) <- result.try(rebase_pair(
        authored_mark,
        base_mark,
        state,
        rebase_child,
        field,
        move_context,
      ))
      rebase_loop(
        authored_rest,
        [],
        authored_sources,
        over_sources,
        state,
        rebase_child,
        algebra,
        field,
        move_context,
        [mark, ..output],
      )
    }
    [], [base_mark, ..base_rest] -> {
      use #(authored_mark, move_context) <- result.try(counterpart_for_base(
        base_mark,
        field,
        move_context,
      ))
      use #(mark, state, move_context) <- result.try(rebase_pair(
        authored_mark,
        base_mark,
        state,
        rebase_child,
        field,
        move_context,
      ))
      rebase_loop(
        [],
        base_rest,
        authored_sources,
        over_sources,
        state,
        rebase_child,
        algebra,
        field,
        move_context,
        [mark, ..output],
      )
    }
    [authored_mark, ..authored_rest], [base_mark, ..base_rest] -> {
      use choice <- result.try(next_choice(
        base_mark,
        authored_mark,
        over_sources,
        authored_sources,
        algebra,
      ))
      case choice {
        OldThenNew -> {
          use #(authored_mark, move_context) <- result.try(counterpart_for_base(
            base_mark,
            field,
            move_context,
          ))
          use #(mark, state, move_context) <- result.try(rebase_pair(
            authored_mark,
            base_mark,
            state,
            rebase_child,
            field,
            move_context,
          ))
          rebase_loop(
            authored,
            base_rest,
            authored_sources,
            over_sources,
            state,
            rebase_child,
            algebra,
            field,
            move_context,
            [mark, ..output],
          )
        }
        NewThenOld -> {
          let base_mark = noop(authored_mark.count, authored_mark.cell_id)
          use #(mark, state, move_context) <- result.try(rebase_pair(
            authored_mark,
            base_mark,
            state,
            rebase_child,
            field,
            move_context,
          ))
          rebase_loop(
            authored_rest,
            over,
            authored_sources,
            over_sources,
            state,
            rebase_child,
            algebra,
            field,
            move_context,
            [mark, ..output],
          )
        }
        SameCell -> {
          let length = int.min(authored_mark.count, base_mark.count)
          use #(authored_mark, authored_rest) <- result.try(take(
            authored,
            length,
          ))
          use #(base_mark, base_rest) <- result.try(take(over, length))
          use #(authored_mark, move_context) <- result.try(add_moved_effect(
            authored_mark,
            base_mark,
            field,
            move_context,
          ))
          use #(mark, state, move_context) <- result.try(rebase_pair(
            authored_mark,
            base_mark,
            state,
            rebase_child,
            field,
            move_context,
          ))
          rebase_loop(
            authored_rest,
            base_rest,
            authored_sources,
            over_sources,
            state,
            rebase_child,
            algebra,
            field,
            move_context,
            [mark, ..output],
          )
        }
      }
    }
  }
}

fn prepare(
  marks: List(sequence_field.Mark),
  field: moves.FieldId,
  context: moves.Context,
) -> Result(#(List(sequence_field.Mark), moves.Context), TreeError) {
  case marks {
    [] -> Ok(#([], context))
    [mark, ..rest] -> {
      use #(length, context) <- result.try(first_effect_length(
        mark.effect,
        mark.count,
        field,
        context,
      ))
      case length < mark.count {
        False -> Ok(#(marks, context))
        True -> {
          use #(first, second) <- result.try(sequence_field.split_mark(
            mark,
            length,
          ))
          Ok(#([first, second, ..rest], context))
        }
      }
    }
  }
}

fn first_effect_length(
  effect: sequence_field.Effect,
  count: Int,
  field: moves.FieldId,
  context: moves.Context,
) -> Result(#(Int, moves.Context), TreeError) {
  case effect {
    sequence_field.Attach(sequence_field.MoveIn(id, _)) ->
      query_length(moves.Destination, id, count, field, context)
    sequence_field.Detach(sequence_field.MoveOut(id, _, _)) ->
      query_length(moves.Source, id, count, field, context)
    sequence_field.AttachAndDetach(attach, detach) -> {
      use #(attach_length, context) <- result.try(case attach {
        sequence_field.MoveIn(id, _) ->
          query_length(moves.Destination, id, count, field, context)
        _ -> Ok(#(count, context))
      })
      use #(detach_length, context) <- result.try(case detach {
        sequence_field.MoveOut(id, _, _) ->
          query_length(moves.Source, id, count, field, context)
        _ -> Ok(#(count, context))
      })
      Ok(#(int.min(attach_length, detach_length), context))
    }
    _ -> Ok(#(count, context))
  }
}

fn query_length(
  side: moves.Side,
  id: AtomId,
  count: Int,
  field: moves.FieldId,
  context: moves.Context,
) -> Result(#(Int, moves.Context), TreeError) {
  use #(moves.Query(length, _), context) <- result.try(moves.get(
    context,
    key(side, id),
    count,
    Some(field),
  ))
  Ok(#(length, context))
}

fn counterpart_for_base(
  base: sequence_field.Mark,
  field: moves.FieldId,
  context: moves.Context,
) -> Result(#(sequence_field.Mark, moves.Context), TreeError) {
  let mark = noop(base.count, base.cell_id)
  add_moved_effect(mark, base, field, context)
}

fn add_moved_effect(
  authored: sequence_field.Mark,
  base: sequence_field.Mark,
  field: moves.FieldId,
  context: moves.Context,
) -> Result(#(sequence_field.Mark, moves.Context), TreeError) {
  case move_in(base.effect) {
    None -> Ok(#(authored, context))
    Some(id) -> {
      use #(moves.Query(length, effect), context) <- result.try(moves.get(
        context,
        key(moves.Destination, id),
        base.count,
        Some(field),
      ))
      use _ <- result.try(check(
        length == base.count,
        "moved effect does not cover the base mark",
      ))
      case effect {
        Some(moves.MoveEffect(moved_effect: Some(effect), ..)) -> {
          use context <- result.try(case effect {
            sequence_field.MoveOut(id, _, _) ->
              moves.move_key(context, key(moves.Source, id), base.count, field)
            _ -> Ok(context)
          })
          use mark <- result.try(combine_moved_effect(authored, effect))
          Ok(#(mark, context))
        }
        _ -> Ok(#(authored, context))
      }
    }
  }
}

fn combine_moved_effect(
  mark: sequence_field.Mark,
  effect: sequence_field.Detach,
) -> Result(sequence_field.Mark, TreeError) {
  case mark.effect, effect {
    sequence_field.Attach(sequence_field.MoveIn(id, _)),
      sequence_field.MoveOut(_, _, _)
    ->
      Ok(
        sequence_field.Mark(
          ..mark,
          effect: sequence_field.Attach(sequence_field.Insert(id)),
        ),
      )
    sequence_field.Rename(id_override), sequence_field.MoveOut(_, _, _) ->
      Ok(
        sequence_field.Mark(
          ..mark,
          effect: sequence_field.Detach(with_override(effect, id_override)),
        ),
      )
    sequence_field.AttachAndDetach(sequence_field.MoveIn(_, _), detach),
      sequence_field.MoveOut(_, _, _)
    -> Ok(sequence_field.Mark(..mark, effect: sequence_field.Detach(detach)))
    sequence_field.Noop, _ if mark.cell_id != None ->
      Ok(sequence_field.Mark(..mark, effect: sequence_field.Detach(effect)))
    _, _ ->
      Error(CorruptData(
        "sequence rebase",
        "unexpected moved effect at the destination",
      ))
  }
}

fn rebase_pair(
  authored: sequence_field.Mark,
  base: sequence_field.Mark,
  state: state,
  rebase_child: fn(
    Option(AtomId),
    Option(AtomId),
    sequence_field.AttachState,
    state,
  ) -> Result(#(Option(AtomId), state), TreeError),
  field: moves.FieldId,
  context: moves.Context,
) -> Result(#(sequence_field.Mark, state, moves.Context), TreeError) {
  use #(child, state) <- result.try(case authored.child, base.child {
    None, None -> Ok(#(None, state))
    authored_child, base_child ->
      rebase_child(authored_child, base_child, node_state_after(base), state)
  })
  let authored = sequence_field.Mark(..authored, child:)
  use #(moved_child, context) <- result.try(moved_child(base, field, context))
  use authored <- result.try(case moved_child, authored.child {
    None, _ -> Ok(authored)
    Some(child), None -> Ok(sequence_field.Mark(..authored, child: Some(child)))
    Some(_), Some(_) ->
      Error(CorruptData(
        "sequence rebase",
        "moved child collides with an authored child",
      ))
  })
  use context <- result.try(case moved_child {
    Some(child) -> moves.on_move_in(context, child, field)
    None -> Ok(context)
  })
  use #(mark, context) <- result.try(rebase_effect(authored, base, context))
  Ok(#(mark, state, context))
}

fn moved_child(
  base: sequence_field.Mark,
  field: moves.FieldId,
  context: moves.Context,
) -> Result(#(Option(AtomId), moves.Context), TreeError) {
  case move_in(base.effect) {
    None -> Ok(#(None, context))
    Some(id) -> {
      use #(moves.Query(length, effect), context) <- result.try(moves.get(
        context,
        key(moves.Destination, id),
        base.count,
        Some(field),
      ))
      use _ <- result.try(check(
        length == base.count,
        "moved child effect does not cover the base mark",
      ))
      Ok(#(
        case effect {
          Some(moves.MoveEffect(rebased_child: child, ..)) -> child
          _ -> None
        },
        context,
      ))
    }
  }
}

fn rebase_effect(
  authored: sequence_field.Mark,
  base: sequence_field.Mark,
  context: moves.Context,
) -> Result(#(sequence_field.Mark, moves.Context), TreeError) {
  case is_detach(base.effect) {
    True -> {
      let authored = case base.cell_id {
        Some(_) -> sequence_field.Mark(..authored, cell_id: None)
        None -> authored
      }
      use _ <- result.try(check(
        !is_new_attach(authored),
        "a new attach cannot be rebased over an emptied cell",
      ))
      let assert Some(base_cell) = sequence_field.output_cell_id(base)
      use #(authored, context) <- result.try(case move_out(base.effect) {
        None -> Ok(#(authored, context))
        Some(endpoint) ->
          rebase_over_move(authored, endpoint, base.count, context)
      })
      Ok(#(sequence_field.Mark(..authored, cell_id: Some(base_cell)), context))
    }
    False ->
      case fills(base) {
        True ->
          case authored.effect {
            sequence_field.AttachAndDetach(_, detach) ->
              Ok(#(
                sequence_field.Mark(
                  authored.count,
                  None,
                  sequence_field.Detach(detach),
                  authored.child,
                ),
                context,
              ))
            _ -> Ok(#(sequence_field.Mark(..authored, cell_id: None), context))
          }
        False ->
          case base.effect {
            sequence_field.AttachAndDetach(attach, detach) -> {
              let assert Some(cell) = base.cell_id
              let attach_mark =
                sequence_field.Mark(
                  base.count,
                  Some(cell),
                  sequence_field.Attach(attach),
                  None,
                )
              use #(half, context) <- result.try(rebase_effect(
                authored,
                attach_mark,
                context,
              ))
              rebase_effect(
                half,
                sequence_field.Mark(
                  base.count,
                  None,
                  sequence_field.Detach(detach),
                  None,
                ),
                context,
              )
            }
            sequence_field.Rename(id) ->
              Ok(#(sequence_field.Mark(..authored, cell_id: Some(id)), context))
            _ -> Ok(#(authored, context))
          }
      }
  }
}

fn rebase_over_move(
  authored: sequence_field.Mark,
  destination: AtomId,
  count: Int,
  context: moves.Context,
) -> Result(#(sequence_field.Mark, moves.Context), TreeError) {
  let #(remains, follows) = separate_for_move(authored.effect)
  use context <- result.try(case follows {
    None -> Ok(context)
    Some(effect) -> send_effect(effect, destination, count, context)
  })
  use context <- result.try(case authored.child {
    None -> Ok(context)
    Some(child) -> move_child(child, destination, context)
  })
  Ok(#(
    sequence_field.Mark(
      authored.count,
      authored.cell_id,
      option_effect(remains),
      None,
    ),
    context,
  ))
}

fn separate_for_move(
  effect: sequence_field.Effect,
) -> #(Option(sequence_field.Effect), Option(sequence_field.Detach)) {
  case effect {
    sequence_field.Detach(detach) ->
      case detach {
        sequence_field.Remove(id, Some(id_override)) -> #(
          Some(sequence_field.Rename(id_override)),
          Some(sequence_field.Remove(id, None)),
        )
        sequence_field.MoveOut(id, endpoint, Some(id_override)) -> #(
          Some(sequence_field.Rename(id_override)),
          Some(sequence_field.MoveOut(id, endpoint, None)),
        )
        _ -> #(None, Some(detach))
      }
    sequence_field.AttachAndDetach(attach, detach) -> #(
      Some(sequence_field.Attach(attach)),
      Some(detach),
    )
    sequence_field.Attach(sequence_field.MoveIn(_, _))
    | sequence_field.Rename(_) -> #(Some(effect), None)
    sequence_field.Noop -> #(None, None)
    sequence_field.Attach(sequence_field.Insert(id)) -> #(
      Some(sequence_field.Attach(sequence_field.MoveIn(id, None))),
      Some(sequence_field.MoveOut(id, None, None)),
    )
  }
}

fn send_effect(
  detach: sequence_field.Detach,
  destination: AtomId,
  count: Int,
  context: moves.Context,
) -> Result(moves.Context, TreeError) {
  use #(moves.Query(length, found), context) <- result.try(moves.get(
    context,
    key(moves.Destination, destination),
    count,
    None,
  ))
  let effect =
    move_effect(found)
    |> with_moved_effect(detach)
  use context <- result.try(moves.set(
    context,
    key(moves.Destination, destination),
    length,
    effect,
  ))
  case length < count {
    False -> Ok(context)
    True ->
      send_effect(
        sequence_field.offset_detach(detach, length),
        sequence_field.offset_atom(destination, length),
        count - length,
        context,
      )
  }
}

fn move_child(
  child: AtomId,
  destination: AtomId,
  context: moves.Context,
) -> Result(moves.Context, TreeError) {
  use #(moves.Query(length, found), context) <- result.try(moves.get(
    context,
    key(moves.Destination, destination),
    1,
    None,
  ))
  use _ <- result.try(check(length == 1, "moved child range is invalid"))
  moves.set(
    context,
    key(moves.Destination, destination),
    1,
    with_rebased_child(move_effect(found), child),
  )
}

fn move_effect(effect: Option(moves.Effect)) -> moves.Effect {
  case effect {
    Some(moves.MoveEffect(..) as effect) -> effect
    _ ->
      moves.MoveEffect(
        modify_after: None,
        moved_effect: None,
        rebased_child: None,
        endpoint: None,
        truncated_endpoint: None,
        truncated_endpoint_for_inner: None,
      )
  }
}

fn with_moved_effect(
  effect: moves.Effect,
  detach: sequence_field.Detach,
) -> moves.Effect {
  let assert moves.MoveEffect(
    modify_after:,
    rebased_child:,
    endpoint:,
    truncated_endpoint:,
    truncated_endpoint_for_inner:,
    ..,
  ) = effect
  moves.MoveEffect(
    modify_after:,
    moved_effect: Some(detach),
    rebased_child:,
    endpoint:,
    truncated_endpoint:,
    truncated_endpoint_for_inner:,
  )
}

fn with_rebased_child(effect: moves.Effect, child: AtomId) -> moves.Effect {
  let assert moves.MoveEffect(
    modify_after:,
    moved_effect:,
    endpoint:,
    truncated_endpoint:,
    truncated_endpoint_for_inner:,
    ..,
  ) = effect
  moves.MoveEffect(
    modify_after:,
    moved_effect:,
    rebased_child: Some(child),
    endpoint:,
    truncated_endpoint:,
    truncated_endpoint_for_inner:,
  )
}

fn next_choice(
  base: sequence_field.Mark,
  authored: sequence_field.Mark,
  base_sources: List(Option(StableId)),
  authored_sources: List(Option(StableId)),
  algebra: sequence_field.AlgebraContext,
) -> Result(CellOrder, TreeError) {
  case base.cell_id, authored.cell_id {
    Some(base_id), Some(authored_id) ->
      compare_cells(
        base_id,
        authored_id,
        base_sources,
        authored_sources,
        algebra,
      )
    _, Some(_) -> Ok(NewThenOld)
    Some(_), _ -> Ok(OldThenNew)
    None, None -> Ok(SameCell)
  }
}

fn compare_cells(
  old: AtomId,
  new: AtomId,
  old_sources: List(Option(StableId)),
  new_sources: List(Option(StableId)),
  algebra: sequence_field.AlgebraContext,
) -> Result(CellOrder, TreeError) {
  use identity <- result.try(algebra.compare_atoms(old, new))
  case identity {
    Eq -> Ok(SameCell)
    Lt | Gt -> {
      let old_knows_new = list.contains(old_sources, new.revision)
      let new_knows_old = list.contains(new_sources, old.revision)
      case old_knows_new, new_knows_old {
        True, True ->
          case old.revision == new.revision {
            True -> Ok(NewThenOld)
            False ->
              Error(CorruptData(
                "sequence rebase",
                "changes contain inconsistent cell ordering",
              ))
          }
        _, True -> Ok(NewThenOld)
        True, _ -> Ok(OldThenNew)
        False, False ->
          case new.revision, old.revision {
            None, _ -> Ok(NewThenOld)
            Some(_), None ->
              Error(CorruptData(
                "sequence rebase",
                "an older cell has no revision",
              ))
            Some(new_revision), Some(old_revision) -> {
              use old_index <- result.try(algebra.revision_index(old_revision))
              use new_index <- result.try(algebra.revision_index(new_revision))
              case old_index, new_index {
                Some(old_index), Some(new_index) ->
                  Ok(case int.compare(new_index, old_index) {
                    Gt -> NewThenOld
                    Lt | Eq -> OldThenNew
                  })
                None, Some(_) -> Ok(NewThenOld)
                Some(_), None -> Ok(OldThenNew)
                None, None ->
                  Error(CorruptData(
                    "sequence rebase",
                    "cell revisions are outside the metadata window",
                  ))
              }
            }
          }
      }
    }
  }
}

fn take(
  marks: List(sequence_field.Mark),
  length: Int,
) -> Result(#(sequence_field.Mark, List(sequence_field.Mark)), TreeError) {
  let assert [mark, ..rest] = marks
  case mark.count <= length {
    True -> Ok(#(mark, rest))
    False -> {
      use #(first, second) <- result.try(sequence_field.split_mark(mark, length))
      Ok(#(first, [second, ..rest]))
    }
  }
}

fn node_state_after(mark: sequence_field.Mark) -> sequence_field.AttachState {
  case empties(mark), fills(mark), mark.cell_id {
    True, _, _ -> sequence_field.DetachedNode
    _, True, _ -> sequence_field.Attached
    _, _, None -> sequence_field.Attached
    _, _, Some(_) -> sequence_field.DetachedNode
  }
}

fn cell_sources(marks: List(sequence_field.Mark)) -> List(Option(StableId)) {
  marks
  |> list.filter_map(fn(mark) {
    case mark.cell_id {
      Some(id) -> Ok(id.revision)
      None -> Error(Nil)
    }
  })
  |> list.unique
}

fn move_in(effect: sequence_field.Effect) -> Option(AtomId) {
  case effect {
    sequence_field.Attach(sequence_field.MoveIn(id, _))
    | sequence_field.AttachAndDetach(sequence_field.MoveIn(id, _), _) ->
      Some(id)
    _ -> None
  }
}

fn move_out(effect: sequence_field.Effect) -> Option(AtomId) {
  case effect {
    sequence_field.Detach(sequence_field.MoveOut(id, endpoint, _))
    | sequence_field.AttachAndDetach(_, sequence_field.MoveOut(id, endpoint, _)) ->
      Some(option_atom(endpoint, id))
    _ -> None
  }
}

fn is_detach(effect: sequence_field.Effect) -> Bool {
  case effect {
    sequence_field.Detach(_) -> True
    _ -> False
  }
}

fn is_new_attach(mark: sequence_field.Mark) -> Bool {
  case mark.cell_id, mark.effect {
    Some(cell), sequence_field.Attach(sequence_field.Insert(id)) ->
      cell.revision == id.revision
    Some(cell), sequence_field.Attach(sequence_field.MoveIn(id, _)) ->
      cell.revision == id.revision
    Some(cell), sequence_field.AttachAndDetach(sequence_field.Insert(id), _) ->
      cell.revision == id.revision
    Some(cell), sequence_field.AttachAndDetach(sequence_field.MoveIn(id, _), _)
    -> cell.revision == id.revision
    _, _ -> False
  }
}

fn fills(mark: sequence_field.Mark) -> Bool {
  mark.cell_id != None && sequence_field.output_length(mark) > 0
}

fn empties(mark: sequence_field.Mark) -> Bool {
  mark.cell_id == None && sequence_field.output_length(mark) == 0
}

fn with_override(
  detach: sequence_field.Detach,
  id_override: AtomId,
) -> sequence_field.Detach {
  case detach {
    sequence_field.Remove(id, _) -> sequence_field.Remove(id, Some(id_override))
    sequence_field.MoveOut(id, endpoint, _) ->
      sequence_field.MoveOut(id, endpoint, Some(id_override))
  }
}

fn option_effect(
  effect: Option(sequence_field.Effect),
) -> sequence_field.Effect {
  case effect {
    Some(effect) -> effect
    None -> sequence_field.Noop
  }
}

fn option_atom(value: Option(AtomId), default: AtomId) -> AtomId {
  case value {
    Some(value) -> value
    None -> default
  }
}

fn noop(count: Int, cell_id: Option(AtomId)) -> sequence_field.Mark {
  sequence_field.Mark(count, cell_id, sequence_field.Noop, None)
}

fn key(side: moves.Side, id: AtomId) -> moves.Key {
  moves.Key(side, id.revision, id.local_id)
}

fn check(valid: Bool, detail: String) -> Result(Nil, TreeError) {
  case valid {
    True -> Ok(Nil)
    False -> Error(CorruptData("sequence rebase", detail))
  }
}
