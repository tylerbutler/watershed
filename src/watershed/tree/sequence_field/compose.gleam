//// Counted composition for sequence-field changes.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Gt, Lt}
import gleam/result
import watershed/fluid_ids.{type StableId}
import watershed/tree/sequence_field
import watershed/tree/sequence_field/moves
import watershed/tree/types.{type AtomId, type TreeError, AtomId, CorruptData}

type CellOrder {
  SameCell
  OldThenNew
  NewThenOld
}

pub fn compose(
  first: sequence_field.Changeset,
  second: sequence_field.Changeset,
  state: state,
  compose_child: fn(Option(AtomId), Option(AtomId), state) ->
    Result(#(AtomId, state), TreeError),
  algebra: sequence_field.AlgebraContext,
  field: moves.FieldId,
  move_context: moves.Context,
) -> Result(#(sequence_field.Changeset, state, moves.Context), TreeError) {
  compose_with_context(
    first,
    second,
    state,
    fn(left, right, state, context) {
      use #(child, state) <- result.try(compose_child(left, right, state))
      Ok(#(child, state, context))
    },
    algebra,
    field,
    move_context,
  )
}

pub fn compose_with_context(
  first: sequence_field.Changeset,
  second: sequence_field.Changeset,
  state: state,
  compose_child: fn(Option(AtomId), Option(AtomId), state, moves.Context) ->
    Result(#(AtomId, state, moves.Context), TreeError),
  algebra: sequence_field.AlgebraContext,
  field: moves.FieldId,
  move_context: moves.Context,
) -> Result(#(sequence_field.Changeset, state, moves.Context), TreeError) {
  let first_marks = sequence_field.to_marks(first)
  let second_marks = sequence_field.to_marks(second)
  let first_sources = cell_sources(first_marks, sequence_field.output_cell_id)
  let second_sources = cell_sources(second_marks, fn(mark) { mark.cell_id })
  use #(marks, state, move_context) <- result.try(
    compose_loop(
      first_marks,
      second_marks,
      first_sources,
      second_sources,
      state,
      compose_child,
      algebra,
      field,
      move_context,
      [],
    ),
  )
  use change <- result.try(sequence_field.from_marks(list.reverse(marks)))
  Ok(#(change, state, move_context))
}

fn compose_loop(
  first: List(sequence_field.Mark),
  second: List(sequence_field.Mark),
  first_sources: List(Option(StableId)),
  second_sources: List(Option(StableId)),
  state: state,
  compose_child: fn(Option(AtomId), Option(AtomId), state, moves.Context) ->
    Result(#(AtomId, state, moves.Context), TreeError),
  algebra: sequence_field.AlgebraContext,
  field: moves.FieldId,
  move_context: moves.Context,
  output: List(sequence_field.Mark),
) -> Result(#(List(sequence_field.Mark), state, moves.Context), TreeError) {
  use #(first, move_context) <- result.try(prepare(first, field, move_context))
  use #(second, move_context) <- result.try(prepare(second, field, move_context))
  case first, second {
    [], [] -> Ok(#(output, state, move_context))
    [], [new_mark, ..new_rest] -> {
      let base_mark = noop(new_mark.count, None, new_mark.cell_id)
      use #(mark, state, move_context) <- result.try(compose_pair(
        base_mark,
        settle(new_mark),
        state,
        compose_child,
        field,
        move_context,
      ))
      compose_loop(
        [],
        new_rest,
        first_sources,
        second_sources,
        state,
        compose_child,
        algebra,
        field,
        move_context,
        [mark, ..output],
      )
    }
    [base_mark, ..base_rest], [] -> {
      use #(moved_child, move_context) <- result.try(moved_child(
        base_mark,
        field,
        move_context,
      ))
      let new_mark =
        noop(
          base_mark.count,
          moved_child,
          sequence_field.output_cell_id(base_mark),
        )
      use #(mark, state, move_context) <- result.try(compose_pair(
        settle(base_mark),
        new_mark,
        state,
        compose_child,
        field,
        move_context,
      ))
      compose_loop(
        base_rest,
        [],
        first_sources,
        second_sources,
        state,
        compose_child,
        algebra,
        field,
        move_context,
        [mark, ..output],
      )
    }
    [base_mark, ..base_rest], [new_mark, ..new_rest] -> {
      use choice <- result.try(next_choice(
        base_mark,
        new_mark,
        first_sources,
        second_sources,
        algebra,
      ))
      case choice {
        OldThenNew -> {
          use #(moved_child, move_context) <- result.try(moved_child(
            base_mark,
            field,
            move_context,
          ))
          let counterpart =
            noop(
              base_mark.count,
              moved_child,
              sequence_field.output_cell_id(base_mark),
            )
          use #(mark, state, move_context) <- result.try(compose_pair(
            settle(base_mark),
            counterpart,
            state,
            compose_child,
            field,
            move_context,
          ))
          compose_loop(
            base_rest,
            second,
            first_sources,
            second_sources,
            state,
            compose_child,
            algebra,
            field,
            move_context,
            [mark, ..output],
          )
        }
        NewThenOld -> {
          let counterpart = noop(new_mark.count, None, new_mark.cell_id)
          use #(mark, state, move_context) <- result.try(compose_pair(
            counterpart,
            settle(new_mark),
            state,
            compose_child,
            field,
            move_context,
          ))
          compose_loop(
            first,
            new_rest,
            first_sources,
            second_sources,
            state,
            compose_child,
            algebra,
            field,
            move_context,
            [mark, ..output],
          )
        }
        SameCell -> {
          let length = int.min(base_mark.count, new_mark.count)
          use #(base_part, base_rest) <- result.try(take(first, length))
          use #(new_part, new_rest) <- result.try(take(second, length))
          use #(moved_child, move_context) <- result.try(moved_child(
            base_part,
            field,
            move_context,
          ))
          let new_part = case moved_child, new_part.child {
            Some(child), None ->
              sequence_field.Mark(..new_part, child: Some(child))
            None, _ -> new_part
            Some(_), Some(_) -> new_part
          }
          use #(mark, state, move_context) <- result.try(compose_pair(
            settle(base_part),
            settle(new_part),
            state,
            compose_child,
            field,
            move_context,
          ))
          compose_loop(
            base_rest,
            new_rest,
            first_sources,
            second_sources,
            state,
            compose_child,
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
      use #(attach_length, context) <- result.try(first_attach_length(
        attach,
        count,
        field,
        context,
      ))
      use #(detach_length, context) <- result.try(first_detach_length(
        detach,
        count,
        field,
        context,
      ))
      Ok(#(int.min(attach_length, detach_length), context))
    }
    _ -> Ok(#(count, context))
  }
}

fn first_attach_length(
  attach: sequence_field.Attach,
  count: Int,
  field: moves.FieldId,
  context: moves.Context,
) -> Result(#(Int, moves.Context), TreeError) {
  case attach {
    sequence_field.MoveIn(id, _) ->
      query_length(moves.Destination, id, count, field, context)
    _ -> Ok(#(count, context))
  }
}

fn first_detach_length(
  detach: sequence_field.Detach,
  count: Int,
  field: moves.FieldId,
  context: moves.Context,
) -> Result(#(Int, moves.Context), TreeError) {
  case detach {
    sequence_field.MoveOut(id, _, _) ->
      query_length(moves.Source, id, count, field, context)
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
    moves.Key(side, id.revision, id.local_id),
    count,
    Some(field),
  ))
  Ok(#(length, context))
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

fn next_choice(
  base: sequence_field.Mark,
  new: sequence_field.Mark,
  base_sources: List(Option(StableId)),
  new_sources: List(Option(StableId)),
  algebra: sequence_field.AlgebraContext,
) -> Result(CellOrder, TreeError) {
  case output_empty(base), input_empty(new) {
    True, True -> {
      let assert Some(base_id) = sequence_field.output_cell_id(base)
      let assert Some(new_id) = new.cell_id
      compare_cells(base_id, new_id, base_sources, new_sources, algebra)
    }
    True, False -> Ok(OldThenNew)
    False, True -> Ok(NewThenOld)
    False, False -> Ok(SameCell)
  }
}

fn compare_cells(
  old: AtomId,
  new: AtomId,
  old_sources: List(Option(StableId)),
  new_sources: List(Option(StableId)),
  algebra: sequence_field.AlgebraContext,
) -> Result(CellOrder, TreeError) {
  case old == new {
    True -> Ok(SameCell)
    False -> {
      let old_knows_new = list.contains(old_sources, new.revision)
      let new_knows_old = list.contains(new_sources, old.revision)
      case old_knows_new, new_knows_old {
        True, True ->
          case old.revision == new.revision {
            True -> Ok(NewThenOld)
            False ->
              Error(CorruptData(
                "sequence compose",
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
                "sequence compose",
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
                    "sequence compose",
                    "cell revisions are outside the metadata window",
                  ))
              }
            }
          }
      }
    }
  }
}

fn cell_sources(
  marks: List(sequence_field.Mark),
  get: fn(sequence_field.Mark) -> Option(AtomId),
) -> List(Option(StableId)) {
  marks
  |> list.filter_map(fn(mark) {
    case get(mark) {
      Some(id) -> Ok(id.revision)
      None -> Error(Nil)
    }
  })
  |> list.unique
}

fn compose_pair(
  base: sequence_field.Mark,
  new: sequence_field.Mark,
  state: state,
  compose_child: fn(Option(AtomId), Option(AtomId), state, moves.Context) ->
    Result(#(AtomId, state, moves.Context), TreeError),
  field: moves.FieldId,
  context: moves.Context,
) -> Result(#(sequence_field.Mark, state, moves.Context), TreeError) {
  use #(child, state, context) <- result.try(compose_children(
    base,
    new,
    state,
    compose_child,
    field,
    context,
  ))
  use #(effect, context) <- result.try(compose_effects(base, new, context))
  use #(effect, context) <- result.try(updated_endpoint(
    effect,
    base.count,
    field,
    context,
  ))
  Ok(#(sequence_field.Mark(..effect, child:), state, context))
}

fn compose_children(
  base: sequence_field.Mark,
  new: sequence_field.Mark,
  state: state,
  compose_child: fn(Option(AtomId), Option(AtomId), state, moves.Context) ->
    Result(#(AtomId, state, moves.Context), TreeError),
  field: moves.FieldId,
  context: moves.Context,
) -> Result(#(Option(AtomId), state, moves.Context), TreeError) {
  use context <- result.try(case new.child {
    None -> Ok(context)
    Some(child) -> moves.on_move_in(context, child, field)
  })
  case new.child, move_in(base.effect) {
    Some(child), Some(source) -> {
      use context <- result.try(set_modify_after(
        context,
        endpoint(source),
        child,
      ))
      Ok(#(None, state, context))
    }
    _, _ ->
      case base.child, new.child {
        None, None -> Ok(#(None, state, context))
        left, right -> {
          use #(child, state, context) <- result.try(compose_child(
            left,
            right,
            state,
            context,
          ))
          Ok(#(Some(child), state, context))
        }
      }
  }
}

fn compose_effects(
  base: sequence_field.Mark,
  new: sequence_field.Mark,
  context: moves.Context,
) -> Result(#(sequence_field.Mark, moves.Context), TreeError) {
  case base.effect, new.effect {
    sequence_field.Noop, _ -> Ok(#(new, context))
    _, sequence_field.Noop -> Ok(#(base, context))
    sequence_field.Rename(_), sequence_field.Rename(id) ->
      Ok(#(
        sequence_field.Mark(..base, effect: sequence_field.Rename(id)),
        context,
      ))
    sequence_field.Rename(_), _ ->
      Ok(#(sequence_field.Mark(..new, cell_id: base.cell_id), context))
    _, sequence_field.Rename(id) ->
      case base.effect {
        sequence_field.Detach(detach) ->
          Ok(#(
            sequence_field.Mark(
              ..base,
              effect: sequence_field.Detach(with_override(detach, id)),
            ),
            context,
          ))
        sequence_field.AttachAndDetach(attach, detach) ->
          Ok(#(
            sequence_field.Mark(
              ..base,
              effect: sequence_field.AttachAndDetach(
                attach,
                with_override(detach, id),
              ),
            ),
            context,
          ))
        _ -> unexpected()
      }
    _, _ -> compose_non_rename(base, new, context)
  }
}

fn compose_non_rename(
  base: sequence_field.Mark,
  new: sequence_field.Mark,
  context: moves.Context,
) -> Result(#(sequence_field.Mark, moves.Context), TreeError) {
  case impactful_rename(new) {
    Some(#(cell, attach, detach)) ->
      case empties(base) {
        True -> {
          use #(detach, context) <- result.try(handle_cancelled_move(
            base,
            attach,
            detach,
            context,
          ))
          Ok(#(
            sequence_field.Mark(
              base.count,
              None,
              sequence_field.Detach(detach),
              None,
            ),
            context,
          ))
        }
        False ->
          case impactful_rename(base) {
            Some(#(base_cell, base_attach, _)) -> {
              use #(base_attach, detach, context) <- result.try(handle_pivot(
                base.count,
                base_attach,
                detach,
                context,
              ))
              case sequence_field.detach_output_id(detach) == base_cell {
                True -> Ok(#(noop(base.count, None, Some(base_cell)), context))
                False ->
                  Ok(#(
                    normalize_rename(base_cell, base.count, base_attach, detach),
                    context,
                  ))
              }
            }
            None ->
              Ok(#(normalize_rename(cell, new.count, attach, detach), context))
          }
      }
    None ->
      case impactful_rename(base) {
        Some(#(cell, attach, detach)) ->
          case fills(new) {
            True -> {
              use #(attach, context) <- result.try(handle_intermediate_refill(
                base.count,
                attach,
                detach,
                new,
                context,
              ))
              Ok(#(
                sequence_field.Mark(
                  base.count,
                  Some(cell),
                  sequence_field.Attach(attach),
                  None,
                ),
                context,
              ))
            }
            False -> Ok(#(base, context))
          }
        None ->
          case has_cell_effect(base), has_cell_effect(new), input_empty(base) {
            False, False, _ ->
              Ok(#(noop(new.count, None, base.cell_id), context))
            False, True, _ -> Ok(#(new, context))
            True, False, _ -> Ok(#(base, context))
            True, True, True -> {
              let assert sequence_field.Attach(attach) = base.effect
              let assert sequence_field.Detach(detach) = new.effect
              use #(attach, detach, context) <- result.try(handle_pivot(
                base.count,
                attach,
                detach,
                context,
              ))
              case sequence_field.output_cell_id(new) == base.cell_id {
                True -> Ok(#(noop(base.count, None, base.cell_id), context))
                False ->
                  Ok(#(
                    normalize_rename(
                      base.cell_id
                        |> option.unwrap(sequence_field.detached_id(detach)),
                      base.count,
                      attach,
                      detach,
                    ),
                    context,
                  ))
              }
            }
            True, True, False -> Ok(#(noop(base.count, None, None), context))
          }
      }
  }
}

fn handle_intermediate_refill(
  count: Int,
  attach: sequence_field.Attach,
  detach: sequence_field.Detach,
  new: sequence_field.Mark,
  context: moves.Context,
) -> Result(#(sequence_field.Attach, moves.Context), TreeError) {
  case attach, detach, new.effect {
    sequence_field.MoveIn(attach_id, _),
      sequence_field.MoveOut(_, _, _),
      sequence_field.Attach(sequence_field.MoveIn(new_id, _))
    -> {
      let original_attach = AtomId(attach_id.revision, attach_id.local_id)
      use context <- result.try(set_truncated_inner(
        context,
        moves.Source,
        endpoint_from_attach(new.effect),
        count,
        original_attach,
      ))
      use #(new_endpoint, context) <- result.try(get_endpoint(
        context,
        moves.Destination,
        new_id,
        count,
      ))
      case new_endpoint {
        None -> Ok(#(attach, context))
        Some(new_endpoint) -> {
          let attach = set_attach_endpoint(attach, Some(new_endpoint))
          use context <- result.try(set_truncated(
            context,
            moves.Source,
            new_endpoint,
            count,
            original_attach,
          ))
          Ok(#(attach, context))
        }
      }
    }
    _, _, _ -> Ok(#(attach, context))
  }
}

fn handle_cancelled_move(
  base: sequence_field.Mark,
  attach: sequence_field.Attach,
  detach: sequence_field.Detach,
  context: moves.Context,
) -> Result(#(sequence_field.Detach, moves.Context), TreeError) {
  case base.effect, attach, detach {
    sequence_field.Detach(sequence_field.MoveOut(base_id, _, _)),
      sequence_field.MoveIn(_, _),
      sequence_field.MoveOut(new_id, _, _)
    -> {
      use context <- result.try(set_truncated_inner(
        context,
        moves.Destination,
        endpoint_from_mark(base),
        base.count,
        new_id,
      ))
      use #(found, context) <- result.try(get_endpoint(
        context,
        moves.Source,
        base_id,
        base.count,
      ))
      case found {
        None -> Ok(#(detach, context))
        Some(final) -> {
          let detach = set_detach_endpoint(detach, Some(final))
          use context <- result.try(set_truncated(
            context,
            moves.Destination,
            final,
            base.count,
            new_id,
          ))
          Ok(#(detach, context))
        }
      }
    }
    _, _, _ -> Ok(#(detach, context))
  }
}

fn handle_pivot(
  count: Int,
  attach: sequence_field.Attach,
  detach: sequence_field.Detach,
  context: moves.Context,
) -> Result(
  #(sequence_field.Attach, sequence_field.Detach, moves.Context),
  TreeError,
) {
  case attach, detach {
    sequence_field.MoveIn(attach_id, _), sequence_field.MoveOut(detach_id, _, _)
    -> {
      let source = endpoint(attach)
      let destination = detach_endpoint(detach)
      use context <- result.try(set_endpoint(
        context,
        moves.Source,
        source,
        count,
        destination,
      ))
      use #(first, context) <- result.try(get_truncated_inner(
        context,
        moves.Destination,
        attach_id,
        count,
      ))
      use context <- result.try(case first {
        None -> Ok(context)
        Some(value) ->
          set_truncated(context, moves.Destination, destination, count, value)
      })
      use context <- result.try(set_endpoint(
        context,
        moves.Destination,
        destination,
        count,
        source,
      ))
      use #(second, context) <- result.try(get_truncated_inner(
        context,
        moves.Source,
        detach_id,
        count,
      ))
      use context <- result.try(case second {
        None -> Ok(context)
        Some(value) ->
          set_truncated(context, moves.Source, source, count, value)
      })
      Ok(#(
        set_attach_endpoint(attach, None),
        set_detach_endpoint(detach, None),
        context,
      ))
    }
    _, _ -> Ok(#(attach, detach, context))
  }
}

fn moved_child(
  mark: sequence_field.Mark,
  field: moves.FieldId,
  context: moves.Context,
) -> Result(#(Option(AtomId), moves.Context), TreeError) {
  case move_out(mark.effect) {
    None -> Ok(#(None, context))
    Some(id) -> {
      use #(moves.Query(_, effect), context) <- result.try(moves.get(
        context,
        moves.Key(moves.Source, id.revision, id.local_id),
        mark.count,
        Some(field),
      ))
      case effect {
        Some(moves.MoveEffect(modify_after: Some(child), ..)) ->
          Ok(#(Some(child), context))
        _ -> Ok(#(None, context))
      }
    }
  }
}

fn updated_endpoint(
  mark: sequence_field.Mark,
  count: Int,
  field: moves.FieldId,
  context: moves.Context,
) -> Result(#(sequence_field.Mark, moves.Context), TreeError) {
  use #(effect, context) <- result.try(updated_effect_endpoint(
    mark.effect,
    count,
    field,
    context,
  ))
  Ok(#(sequence_field.Mark(..mark, effect:), context))
}

fn updated_effect_endpoint(
  effect: sequence_field.Effect,
  count: Int,
  field: moves.FieldId,
  context: moves.Context,
) -> Result(#(sequence_field.Effect, moves.Context), TreeError) {
  case effect {
    sequence_field.AttachAndDetach(attach, detach) -> {
      use #(attach, context) <- result.try(updated_attach_endpoint(
        attach,
        count,
        field,
        context,
      ))
      use #(detach, context) <- result.try(updated_detach_endpoint(
        detach,
        count,
        field,
        context,
      ))
      Ok(#(sequence_field.AttachAndDetach(attach, detach), context))
    }
    sequence_field.Attach(attach) -> {
      use #(attach, context) <- result.try(updated_attach_endpoint(
        attach,
        count,
        field,
        context,
      ))
      Ok(#(sequence_field.Attach(attach), context))
    }
    sequence_field.Detach(detach) -> {
      use #(detach, context) <- result.try(updated_detach_endpoint(
        detach,
        count,
        field,
        context,
      ))
      Ok(#(sequence_field.Detach(detach), context))
    }
    _ -> Ok(#(effect, context))
  }
}

fn updated_attach_endpoint(
  attach: sequence_field.Attach,
  count: Int,
  field: moves.FieldId,
  context: moves.Context,
) -> Result(#(sequence_field.Attach, moves.Context), TreeError) {
  case attach {
    sequence_field.MoveIn(id, _) -> {
      use #(value, context) <- result.try(get_endpoint_for_field(
        context,
        moves.Destination,
        id,
        count,
        field,
      ))
      Ok(#(
        case value {
          None -> attach
          Some(value) -> set_attach_endpoint(attach, Some(value))
        },
        context,
      ))
    }
    _ -> Ok(#(attach, context))
  }
}

fn updated_detach_endpoint(
  detach: sequence_field.Detach,
  count: Int,
  field: moves.FieldId,
  context: moves.Context,
) -> Result(#(sequence_field.Detach, moves.Context), TreeError) {
  case detach {
    sequence_field.MoveOut(id, _, _) -> {
      use #(value, context) <- result.try(get_endpoint_for_field(
        context,
        moves.Source,
        id,
        count,
        field,
      ))
      Ok(#(
        case value {
          None -> detach
          Some(value) -> set_detach_endpoint(detach, Some(value))
        },
        context,
      ))
    }
    _ -> Ok(#(detach, context))
  }
}

fn get_endpoint_for_field(
  context: moves.Context,
  side: moves.Side,
  id: AtomId,
  count: Int,
  field: moves.FieldId,
) -> Result(#(Option(AtomId), moves.Context), TreeError) {
  use #(moves.Query(length, effect), context) <- result.try(moves.get(
    context,
    moves.Key(side, id.revision, id.local_id),
    count,
    Some(field),
  ))
  use _ <- result.try(check(length == count, "move effect does not cover mark"))
  Ok(#(effect_endpoint(effect), context))
}

fn get_endpoint(
  context: moves.Context,
  side: moves.Side,
  id: AtomId,
  count: Int,
) -> Result(#(Option(AtomId), moves.Context), TreeError) {
  use #(moves.Query(length, effect), context) <- result.try(moves.get(
    context,
    moves.Key(side, id.revision, id.local_id),
    count,
    None,
  ))
  use _ <- result.try(check(length == count, "move effect does not cover mark"))
  Ok(#(effect_endpoint(effect), context))
}

fn effect_endpoint(effect: Option(moves.Effect)) -> Option(AtomId) {
  case effect {
    Some(moves.MoveEffect(endpoint: endpoint, truncated_endpoint: truncated, ..)) ->
      option_or(truncated, endpoint)
    _ -> None
  }
}

fn get_truncated_inner(
  context: moves.Context,
  side: moves.Side,
  id: AtomId,
  count: Int,
) -> Result(#(Option(AtomId), moves.Context), TreeError) {
  use #(moves.Query(length, effect), context) <- result.try(moves.get(
    context,
    moves.Key(side, id.revision, id.local_id),
    count,
    None,
  ))
  use _ <- result.try(check(length == count, "move effect does not cover mark"))
  Ok(#(
    case effect {
      Some(moves.MoveEffect(truncated_endpoint_for_inner: value, ..)) -> value
      _ -> None
    },
    context,
  ))
}

fn set_modify_after(
  context: moves.Context,
  id: AtomId,
  child: AtomId,
) -> Result(moves.Context, TreeError) {
  update_effect(context, moves.Source, id, 1, fn(effect) {
    with_modify_after(effect, child)
  })
}

fn set_endpoint(
  context: moves.Context,
  side: moves.Side,
  id: AtomId,
  count: Int,
  endpoint: AtomId,
) -> Result(moves.Context, TreeError) {
  set_effect_range(context, side, id, count, endpoint, fn(effect, value) {
    with_endpoint(effect, value)
  })
}

fn set_truncated(
  context: moves.Context,
  side: moves.Side,
  id: AtomId,
  count: Int,
  endpoint: AtomId,
) -> Result(moves.Context, TreeError) {
  set_effect_range(context, side, id, count, endpoint, fn(effect, value) {
    with_truncated_endpoint(effect, value)
  })
}

fn set_truncated_inner(
  context: moves.Context,
  side: moves.Side,
  id: AtomId,
  count: Int,
  endpoint: AtomId,
) -> Result(moves.Context, TreeError) {
  set_effect_range(context, side, id, count, endpoint, fn(effect, value) {
    with_truncated_inner(effect, value)
  })
}

fn set_effect_range(
  context: moves.Context,
  side: moves.Side,
  id: AtomId,
  count: Int,
  value: AtomId,
  update: fn(moves.Effect, AtomId) -> moves.Effect,
) -> Result(moves.Context, TreeError) {
  use #(moves.Query(length, found), context) <- result.try(moves.get(
    context,
    moves.Key(side, id.revision, id.local_id),
    count,
    None,
  ))
  let effect = update(move_effect(found), value)
  use context <- result.try(moves.set(
    context,
    moves.Key(side, id.revision, id.local_id),
    length,
    effect,
  ))
  case count - length {
    0 -> Ok(context)
    remaining ->
      set_effect_range(
        context,
        side,
        sequence_field.offset_atom(id, length),
        remaining,
        sequence_field.offset_atom(value, length),
        update,
      )
  }
}

fn update_effect(
  context: moves.Context,
  side: moves.Side,
  id: AtomId,
  count: Int,
  update: fn(moves.Effect) -> moves.Effect,
) -> Result(moves.Context, TreeError) {
  use #(moves.Query(length, found), context) <- result.try(moves.get(
    context,
    moves.Key(side, id.revision, id.local_id),
    count,
    None,
  ))
  use _ <- result.try(check(length == count, "move effect does not cover mark"))
  moves.set(
    context,
    moves.Key(side, id.revision, id.local_id),
    count,
    update(move_effect(found)),
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

fn with_modify_after(effect: moves.Effect, child: AtomId) -> moves.Effect {
  let assert moves.MoveEffect(
    moved_effect:,
    rebased_child:,
    endpoint:,
    truncated_endpoint:,
    truncated_endpoint_for_inner:,
    ..,
  ) = effect
  moves.MoveEffect(
    modify_after: Some(child),
    moved_effect:,
    rebased_child:,
    endpoint:,
    truncated_endpoint:,
    truncated_endpoint_for_inner:,
  )
}

fn with_endpoint(effect: moves.Effect, value: AtomId) -> moves.Effect {
  let assert moves.MoveEffect(
    modify_after:,
    moved_effect:,
    rebased_child:,
    truncated_endpoint:,
    truncated_endpoint_for_inner:,
    ..,
  ) = effect
  moves.MoveEffect(
    modify_after:,
    moved_effect:,
    rebased_child:,
    endpoint: Some(value),
    truncated_endpoint:,
    truncated_endpoint_for_inner:,
  )
}

fn with_truncated_endpoint(
  effect: moves.Effect,
  value: AtomId,
) -> moves.Effect {
  let assert moves.MoveEffect(
    modify_after:,
    moved_effect:,
    rebased_child:,
    endpoint:,
    truncated_endpoint_for_inner:,
    ..,
  ) = effect
  moves.MoveEffect(
    modify_after:,
    moved_effect:,
    rebased_child:,
    endpoint:,
    truncated_endpoint: Some(value),
    truncated_endpoint_for_inner:,
  )
}

fn with_truncated_inner(effect: moves.Effect, value: AtomId) -> moves.Effect {
  let assert moves.MoveEffect(
    modify_after:,
    moved_effect:,
    rebased_child:,
    endpoint:,
    truncated_endpoint:,
    ..,
  ) = effect
  moves.MoveEffect(
    modify_after:,
    moved_effect:,
    rebased_child:,
    endpoint:,
    truncated_endpoint:,
    truncated_endpoint_for_inner: Some(value),
  )
}

fn impactful_rename(
  mark: sequence_field.Mark,
) -> Option(#(AtomId, sequence_field.Attach, sequence_field.Detach)) {
  case mark.cell_id, mark.effect {
    Some(cell), sequence_field.AttachAndDetach(attach, detach) ->
      Some(#(cell, attach, detach))
    Some(cell), sequence_field.Detach(detach) ->
      case sequence_field.is_impactful(mark) {
        True ->
          Some(#(cell, sequence_field.Insert(primary_detach_id(detach)), detach))
        False -> None
      }
    _, _ -> None
  }
}

fn primary_detach_id(detach: sequence_field.Detach) -> AtomId {
  case detach {
    sequence_field.Remove(id, _) | sequence_field.MoveOut(id, _, _) -> id
  }
}

fn normalize_rename(
  cell: AtomId,
  count: Int,
  attach: sequence_field.Attach,
  detach: sequence_field.Detach,
) -> sequence_field.Mark {
  case attach, detach {
    sequence_field.MoveIn(_, _), sequence_field.MoveOut(_, _, _) ->
      sequence_field.Mark(
        count,
        Some(cell),
        sequence_field.Rename(sequence_field.detach_output_id(detach)),
        None,
      )
    sequence_field.Insert(_), _ ->
      sequence_field.Mark(
        count,
        Some(cell),
        sequence_field.Detach(detach),
        None,
      )
    _, _ ->
      sequence_field.Mark(
        count,
        Some(cell),
        sequence_field.AttachAndDetach(attach, detach),
        None,
      )
  }
}

fn settle(mark: sequence_field.Mark) -> sequence_field.Mark {
  case sequence_field.is_impactful(mark) {
    True -> mark
    False -> sequence_field.Mark(..mark, effect: sequence_field.Noop)
  }
}

fn noop(
  count: Int,
  child: Option(AtomId),
  cell: Option(AtomId),
) -> sequence_field.Mark {
  sequence_field.Mark(count, cell, sequence_field.Noop, child)
}

fn input_empty(mark: sequence_field.Mark) -> Bool {
  mark.cell_id != None
}

fn output_empty(mark: sequence_field.Mark) -> Bool {
  sequence_field.output_length(mark) == 0
}

fn empties(mark: sequence_field.Mark) -> Bool {
  !input_empty(mark) && output_empty(mark)
}

fn fills(mark: sequence_field.Mark) -> Bool {
  input_empty(mark) && !output_empty(mark)
}

fn has_cell_effect(mark: sequence_field.Mark) -> Bool {
  input_empty(mark) != output_empty(mark)
}

fn move_in(effect: sequence_field.Effect) -> Option(sequence_field.Attach) {
  case effect {
    sequence_field.Attach(sequence_field.MoveIn(_, _) as attach) -> Some(attach)
    sequence_field.AttachAndDetach(sequence_field.MoveIn(_, _) as attach, _) ->
      Some(attach)
    _ -> None
  }
}

fn move_out(effect: sequence_field.Effect) -> Option(AtomId) {
  case effect {
    sequence_field.Detach(sequence_field.MoveOut(id, _, _))
    | sequence_field.AttachAndDetach(_, sequence_field.MoveOut(id, _, _)) ->
      Some(id)
    _ -> None
  }
}

fn endpoint(attach: sequence_field.Attach) -> AtomId {
  case attach {
    sequence_field.MoveIn(_, Some(endpoint)) -> endpoint
    sequence_field.MoveIn(id, None) -> id
    sequence_field.Insert(id) -> id
  }
}

fn endpoint_from_mark(mark: sequence_field.Mark) -> AtomId {
  case mark.effect {
    sequence_field.Detach(sequence_field.MoveOut(_, Some(endpoint), _)) ->
      endpoint
    sequence_field.Detach(sequence_field.MoveOut(id, None, _)) -> id
    _ -> AtomId(None, 0)
  }
}

fn endpoint_from_attach(effect: sequence_field.Effect) -> AtomId {
  case effect {
    sequence_field.Attach(sequence_field.MoveIn(_, Some(endpoint))) -> endpoint
    sequence_field.Attach(sequence_field.MoveIn(id, None)) -> id
    _ -> AtomId(None, 0)
  }
}

fn detach_endpoint(detach: sequence_field.Detach) -> AtomId {
  case detach {
    sequence_field.MoveOut(_, Some(endpoint), _) -> endpoint
    sequence_field.MoveOut(id, None, _) -> id
    sequence_field.Remove(id, _) -> id
  }
}

fn set_attach_endpoint(
  attach: sequence_field.Attach,
  endpoint: Option(AtomId),
) -> sequence_field.Attach {
  case attach {
    sequence_field.MoveIn(id, _) ->
      case endpoint == Some(id) {
        True -> sequence_field.MoveIn(id, None)
        False -> sequence_field.MoveIn(id, endpoint)
      }
    _ -> attach
  }
}

fn set_detach_endpoint(
  detach: sequence_field.Detach,
  endpoint: Option(AtomId),
) -> sequence_field.Detach {
  case detach {
    sequence_field.MoveOut(id, _, id_override) ->
      case endpoint == Some(id) {
        True -> sequence_field.MoveOut(id, None, id_override)
        False -> sequence_field.MoveOut(id, endpoint, id_override)
      }
    _ -> detach
  }
}

fn with_override(
  detach: sequence_field.Detach,
  id: AtomId,
) -> sequence_field.Detach {
  case detach {
    sequence_field.Remove(detach_id, _) ->
      sequence_field.Remove(detach_id, Some(id))
    sequence_field.MoveOut(detach_id, endpoint, _) ->
      sequence_field.MoveOut(detach_id, endpoint, Some(id))
  }
}

fn option_or(first: Option(a), second: Option(a)) -> Option(a) {
  case first {
    Some(_) -> first
    None -> second
  }
}

fn unexpected() -> Result(a, TreeError) {
  Error(CorruptData("sequence compose", "unexpected mark combination"))
}

fn check(valid: Bool, detail: String) -> Result(Nil, TreeError) {
  case valid {
    True -> Ok(Nil)
    False -> Error(CorruptData("sequence compose", detail))
  }
}
