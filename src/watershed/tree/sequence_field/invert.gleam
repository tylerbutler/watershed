//// Counted inversion for sequence-field changes.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import watershed/fluid_ids.{type StableId}
import watershed/tree/sequence_field
import watershed/tree/sequence_field/moves
import watershed/tree/types.{type AtomId, type TreeError, AtomId}

pub fn invert(
  change: sequence_field.Changeset,
  is_rollback: Bool,
  state: state,
  alias: fn(AtomId, state) -> Result(#(Int, state), TreeError),
  inverse_revision: Option(StableId),
  field: moves.FieldId,
  move_context: moves.Context,
) -> Result(#(sequence_field.Changeset, state, moves.Context), TreeError) {
  use #(marks, state, move_context) <- result.try(
    invert_marks(
      sequence_field.to_marks(change),
      is_rollback,
      state,
      alias,
      inverse_revision,
      field,
      move_context,
      [],
    ),
  )
  use inverse <- result.try(sequence_field.from_marks(list.reverse(marks)))
  Ok(#(inverse, state, move_context))
}

fn invert_marks(
  marks: List(sequence_field.Mark),
  is_rollback: Bool,
  state: state,
  alias: fn(AtomId, state) -> Result(#(Int, state), TreeError),
  inverse_revision: Option(StableId),
  field: moves.FieldId,
  move_context: moves.Context,
  output: List(sequence_field.Mark),
) -> Result(#(List(sequence_field.Mark), state, moves.Context), TreeError) {
  case marks {
    [] -> Ok(#(output, state, move_context))
    [mark, ..rest] -> {
      use #(inverted, state, move_context) <- result.try(invert_mark(
        mark,
        is_rollback,
        state,
        alias,
        inverse_revision,
        field,
        move_context,
      ))
      invert_marks(
        rest,
        is_rollback,
        state,
        alias,
        inverse_revision,
        field,
        move_context,
        list.append(list.reverse(inverted), output),
      )
    }
  }
}

fn invert_mark(
  mark: sequence_field.Mark,
  is_rollback: Bool,
  state: state,
  alias: fn(AtomId, state) -> Result(#(Int, state), TreeError),
  inverse_revision: Option(StableId),
  field: moves.FieldId,
  move_context: moves.Context,
) -> Result(#(List(sequence_field.Mark), state, moves.Context), TreeError) {
  case sequence_field.is_impactful(mark) {
    False ->
      Ok(#(
        [
          sequence_field.Mark(
            mark.count,
            mark.cell_id,
            sequence_field.Noop,
            mark.child,
          ),
        ],
        state,
        move_context,
      ))
    True ->
      case mark.effect {
        sequence_field.Noop -> Ok(#([mark], state, move_context))
        sequence_field.Rename(id_override) ->
          case is_rollback, mark.cell_id {
            True, Some(input) ->
              Ok(#(
                [
                  sequence_field.Mark(
                    mark.count,
                    Some(id_override),
                    sequence_field.Rename(input),
                    mark.child,
                  ),
                ],
                state,
                move_context,
              ))
            _, _ ->
              Ok(#(
                [
                  sequence_field.Mark(
                    mark.count,
                    Some(id_override),
                    sequence_field.Noop,
                    mark.child,
                  ),
                ],
                state,
                move_context,
              ))
          }
        sequence_field.Detach(sequence_field.Remove(id, _)) -> {
          use #(alias_id, state) <- result.try(alias(id, state))
          let output_id =
            sequence_field.output_cell_id(mark)
            |> option_or(id)
          let effect = case mark.cell_id {
            None ->
              sequence_field.Attach(
                sequence_field.Insert(AtomId(inverse_revision, alias_id)),
              )
            Some(input) ->
              sequence_field.Detach(
                sequence_field.Remove(
                  AtomId(inverse_revision, alias_id),
                  case is_rollback {
                    True -> Some(input)
                    False -> None
                  },
                ),
              )
          }
          Ok(#(
            [
              sequence_field.Mark(
                mark.count,
                Some(output_id),
                effect,
                mark.child,
              ),
            ],
            state,
            move_context,
          ))
        }
        sequence_field.Attach(sequence_field.Insert(id)) -> {
          use #(alias_id, state) <- result.try(alias(id, state))
          let effect =
            sequence_field.Detach(
              sequence_field.Remove(
                AtomId(inverse_revision, alias_id),
                case is_rollback {
                  True -> mark.cell_id
                  False -> None
                },
              ),
            )
          Ok(#(
            [sequence_field.Mark(mark.count, None, effect, mark.child)],
            state,
            move_context,
          ))
        }
        sequence_field.Detach(sequence_field.MoveOut(id, final, _)) -> {
          use move_context <- result.try(case mark.child {
            None -> Ok(move_context)
            Some(child) ->
              moves.set(
                move_context,
                key(moves.Destination, endpoint(id, final)),
                mark.count,
                moves.InvertedChild(child),
              )
          })
          use #(alias_id, state) <- result.try(alias(id, state))
          use #(final, state) <- result.try(alias_optional(
            final,
            state,
            alias,
            inverse_revision,
          ))
          let attach =
            sequence_field.MoveIn(AtomId(inverse_revision, alias_id), final)
          let effect = case mark.cell_id {
            None -> sequence_field.Attach(attach)
            Some(input) ->
              sequence_field.AttachAndDetach(
                attach,
                sequence_field.Remove(
                  AtomId(inverse_revision, alias_id),
                  case is_rollback {
                    True -> Some(input)
                    False -> None
                  },
                ),
              )
          }
          let output_id =
            sequence_field.output_cell_id(mark)
            |> option_or(id)
          Ok(#(
            [
              sequence_field.Mark(mark.count, Some(output_id), effect, None),
            ],
            state,
            move_context,
          ))
        }
        sequence_field.Attach(sequence_field.MoveIn(id, final)) -> {
          use #(alias_id, state) <- result.try(alias(id, state))
          use #(final, state) <- result.try(alias_optional(
            final,
            state,
            alias,
            inverse_revision,
          ))
          let detach =
            sequence_field.MoveOut(
              AtomId(inverse_revision, alias_id),
              final,
              case is_rollback {
                True -> mark.cell_id
                False -> None
              },
            )
          let inverted =
            sequence_field.Mark(
              mark.count,
              None,
              sequence_field.Detach(detach),
              None,
            )
          use #(marks, move_context) <- result.try(apply_moved_children(
            inverted,
            id,
            field,
            move_context,
          ))
          Ok(#(marks, state, move_context))
        }
        sequence_field.AttachAndDetach(attach, detach) -> {
          let attached =
            sequence_field.Mark(
              mark.count,
              mark.cell_id,
              sequence_field.Attach(attach),
              None,
            )
          let detached =
            sequence_field.Mark(
              mark.count,
              sequence_field.output_cell_id(attached),
              sequence_field.Detach(detach),
              mark.child,
            )
          use #(attach_inverse, state, move_context) <- result.try(invert_mark(
            attached,
            is_rollback,
            state,
            alias,
            inverse_revision,
            field,
            move_context,
          ))
          use #(detach_inverse, state, move_context) <- result.try(invert_mark(
            detached,
            is_rollback,
            state,
            alias,
            inverse_revision,
            field,
            move_context,
          ))
          use combined <- result.try(
            combine_inverses(attach_inverse, detach_inverse, []),
          )
          Ok(#(combined, state, move_context))
        }
      }
  }
}

fn combine_inverses(
  attach_inverses: List(sequence_field.Mark),
  detach_inverses: List(sequence_field.Mark),
  output: List(sequence_field.Mark),
) -> Result(List(sequence_field.Mark), TreeError) {
  case attach_inverses, detach_inverses {
    [], [] -> Ok(list.reverse(output))
    [attach, ..attach_rest], [detach, ..detach_rest] -> {
      let length = int_min(attach.count, detach.count)
      use #(attach, attach_rest) <- result.try(split_head(
        attach,
        attach_rest,
        length,
      ))
      use #(detach, detach_rest) <- result.try(split_head(
        detach,
        detach_rest,
        length,
      ))
      let combined = case attach.effect {
        sequence_field.Noop ->
          sequence_field.Mark(
            ..detach,
            child: option_prefer(detach.child, attach.child),
          )
        sequence_field.Detach(attach_detach) -> {
          let assert sequence_field.Attach(detach_attach) = detach.effect
          let cell =
            detach.cell_id
            |> option_or(sequence_field.detached_id(attach_detach))
          sequence_field.Mark(
            length,
            Some(cell),
            normalize_effect(detach_attach, attach_detach),
            option_prefer(detach.child, attach.child),
          )
        }
        _ -> attach
      }
      combine_inverses(attach_rest, detach_rest, [combined, ..output])
    }
    [], rest -> Ok(list.append(list.reverse(output), rest))
    rest, [] -> Ok(list.append(list.reverse(output), rest))
  }
}

fn split_head(
  mark: sequence_field.Mark,
  rest: List(sequence_field.Mark),
  length: Int,
) -> Result(#(sequence_field.Mark, List(sequence_field.Mark)), TreeError) {
  case mark.count == length {
    True -> Ok(#(mark, rest))
    False -> {
      use #(first, second) <- result.try(sequence_field.split_mark(mark, length))
      Ok(#(first, [second, ..rest]))
    }
  }
}

fn normalize_effect(
  attach: sequence_field.Attach,
  detach: sequence_field.Detach,
) -> sequence_field.Effect {
  case attach, detach {
    sequence_field.MoveIn(_, _), sequence_field.MoveOut(_, _, _) ->
      sequence_field.Rename(sequence_field.detach_output_id(detach))
    sequence_field.Insert(_), _ -> sequence_field.Detach(detach)
    _, _ -> sequence_field.AttachAndDetach(attach, detach)
  }
}

fn apply_moved_children(
  mark: sequence_field.Mark,
  original_id: AtomId,
  field: moves.FieldId,
  context: moves.Context,
) -> Result(#(List(sequence_field.Mark), moves.Context), TreeError) {
  use #(moves.Query(length, effect), context) <- result.try(moves.get(
    context,
    key(moves.Destination, original_id),
    mark.count,
    Some(field),
  ))
  case length < mark.count {
    True -> {
      use #(first, second) <- result.try(sequence_field.split_mark(mark, length))
      use #(first, context) <- result.try(apply_inverted_child(
        first,
        effect,
        field,
        context,
      ))
      use #(rest, context) <- result.try(apply_moved_children(
        second,
        sequence_field.offset_atom(original_id, length),
        field,
        context,
      ))
      Ok(#([first, ..rest], context))
    }
    False -> {
      use #(mark, context) <- result.try(apply_inverted_child(
        mark,
        effect,
        field,
        context,
      ))
      Ok(#([mark], context))
    }
  }
}

fn apply_inverted_child(
  mark: sequence_field.Mark,
  effect: Option(moves.Effect),
  field: moves.FieldId,
  context: moves.Context,
) -> Result(#(sequence_field.Mark, moves.Context), TreeError) {
  case effect {
    Some(moves.InvertedChild(child)) -> {
      use context <- result.try(moves.on_move_in(context, child, field))
      Ok(#(sequence_field.Mark(..mark, child: Some(child)), context))
    }
    _ -> Ok(#(mark, context))
  }
}

fn alias_optional(
  id: Option(AtomId),
  state: state,
  alias: fn(AtomId, state) -> Result(#(Int, state), TreeError),
  inverse_revision: Option(StableId),
) -> Result(#(Option(AtomId), state), TreeError) {
  case id {
    None -> Ok(#(None, state))
    Some(id) -> {
      use #(local_id, state) <- result.try(alias(id, state))
      Ok(#(Some(AtomId(inverse_revision, local_id)), state))
    }
  }
}

fn endpoint(id: AtomId, final: Option(AtomId)) -> AtomId {
  option_or(final, id)
}

fn key(side: moves.Side, id: AtomId) -> moves.Key {
  moves.Key(side, id.revision, id.local_id)
}

fn option_or(value: Option(a), default: a) -> a {
  case value {
    Some(value) -> value
    None -> default
  }
}

fn option_prefer(first: Option(a), second: Option(a)) -> Option(a) {
  case first {
    Some(_) -> first
    None -> second
  }
}

fn int_min(first: Int, second: Int) -> Int {
  case first < second {
    True -> first
    False -> second
  }
}
