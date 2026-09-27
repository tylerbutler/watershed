import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string
import startest/expect
import watershed/fluid_ids
import watershed/json_ot
import watershed/tree/array_fixture
import watershed/tree/fixtures
import watershed/tree/forest
import watershed/tree/sequence_field
import watershed/tree/sequence_field/compose
import watershed/tree/sequence_field/invert
import watershed/tree/sequence_field/moves
import watershed/tree/sequence_field_fixture
import watershed/tree/types

const max_safe_integer = 9_007_199_254_740_991

const items_type = "org.watershed.shared-tree.m3.Items"

fn revision(suffix: String) -> fluid_ids.StableId {
  let assert Ok(id) =
    fluid_ids.stable_id("10000000-0000-4000-8000-0000000000" <> suffix)
  id
}

fn atom(revision: Option(fluid_ids.StableId), local_id: Int) -> types.AtomId {
  types.AtomId(revision, local_id)
}

fn no_child(_: types.AtomId) {
  Ok([])
}

fn no_child_compose(
  left: Option(types.AtomId),
  right: Option(types.AtomId),
  state: Nil,
) -> Result(#(types.AtomId, Nil), types.TreeError) {
  case left, right {
    Some(id), _ | None, Some(id) -> Ok(#(id, state))
    None, None -> Error(types.CorruptData("test", "missing child"))
  }
}

fn test_algebra() -> sequence_field.AlgebraContext {
  sequence_field.AlgebraContext(
    compare_atoms: fn(first, second) {
      Ok(case first.revision == second.revision {
        True -> int.compare(first.local_id, second.local_id)
        False -> order.Lt
      })
    },
    revision_index: fn(_) { Ok(0) },
    rollback_of: fn(_) { Ok(None) },
  )
}

fn compose_changes(
  first: sequence_field.Changeset,
  second: sequence_field.Changeset,
) -> Result(sequence_field.Changeset, types.TreeError) {
  use #(change, _, context) <- result.try(compose.compose(
    first,
    second,
    Nil,
    no_child_compose,
    test_algebra(),
    moves.FieldId(None, "field"),
    moves.new(),
  ))
  let #(invalidated, context) = moves.take_invalidated(context)
  case invalidated {
    [] -> Ok(change)
    _ -> {
      use #(change, _, _) <- result.try(compose.compose(
        first,
        second,
        Nil,
        no_child_compose,
        test_algebra(),
        moves.FieldId(None, "field"),
        context,
      ))
      Ok(change)
    }
  }
}

pub fn shared_tree_sequence_editor_matches_upstream_test() {
  fixtures.assert_case(
    "sequence-field-editor",
    sequence_field_fixture.run_editor,
  )
}

pub fn shared_tree_sequence_compose_invert_matches_upstream_test() {
  fixtures.assert_case(
    "sequence-compose-invert",
    sequence_field_fixture.run_compose_invert,
  )
}

pub fn shared_tree_sequence_compose_invert_uses_only_fixture_input_test() {
  let assert Ok(fixture) = fixtures.load("sequence-compose-invert")
  let assert Ok(original) =
    sequence_field_fixture.run_compose_invert(fixture.input)
  let raw = json.to_string(fixture.input)
  let changed = string.replace(raw, "\"id\":20", "\"id\":120")
  let assert False = changed == raw
  let assert Ok(changed) = json_ot.parse_json(changed)
  let assert Ok(mutated) =
    sequence_field_fixture.run_compose_invert(json_ot.to_json(changed))
  fixtures.first_difference(original, mutated) |> expect.to_be_error
  Nil
}

pub fn shared_tree_sequence_fixture_child_composition_cancels_inverses_test() {
  let input =
    "{\"scenarios\":[{\"id\":\"child-cancel\",\"operation\":\"compose\",\"revisions\":[1,2],\"operands\":{\"changes\":[{\"revision\":1,\"change\":[{\"count\":1,\"changes\":{\"localId\":30,\"testChange\":{\"inputContext\":[],\"intentions\":[7],\"outputContext\":[7]}}}]},{\"revision\":2,\"change\":[{\"count\":1,\"changes\":{\"localId\":31,\"testChange\":{\"inputContext\":[7],\"intentions\":[-7],\"outputContext\":[]}}}]}],\"childComposer\":\"test-node\"}}]}"
  let assert Ok(value) = json_ot.parse_json(input)
  let assert Ok(output) =
    sequence_field_fixture.run_compose_invert(json_ot.to_json(value))
  json.to_string(output)
  |> string.contains("\"intentions\":[]")
  |> expect.to_be_true
}

pub fn shared_tree_sequence_fixture_child_composition_rejects_context_mismatch_test() {
  let input =
    "{\"scenarios\":[{\"id\":\"child-context\",\"operation\":\"compose\",\"revisions\":[1,2],\"operands\":{\"changes\":[{\"revision\":1,\"change\":[{\"count\":1,\"changes\":{\"localId\":30,\"testChange\":{\"inputContext\":[],\"intentions\":[7],\"outputContext\":[7]}}}]},{\"revision\":2,\"change\":[{\"count\":1,\"changes\":{\"localId\":31,\"testChange\":{\"inputContext\":[99],\"intentions\":[8],\"outputContext\":[99,8]}}}]}],\"childComposer\":\"test-node\"}}]}"
  let assert Ok(value) = json_ot.parse_json(input)
  sequence_field_fixture.run_compose_invert(json_ot.to_json(value))
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_sequence_fixture_invert_reprocesses_moved_children_test() {
  let input =
    "{\"scenarios\":[{\"id\":\"invert-moved-child\",\"operation\":\"invert\",\"revisions\":[1,2],\"operands\":{\"change\":{\"revision\":1,\"change\":[{\"type\":\"MoveIn\",\"id\":10,\"count\":2,\"cellId\":{\"revision\":1,\"localId\":12},\"revision\":1},{\"type\":\"MoveOut\",\"id\":10,\"count\":1,\"revision\":1},{\"type\":\"MoveOut\",\"id\":11,\"count\":1,\"revision\":1,\"changes\":{\"localId\":30,\"testChange\":{\"inputContext\":[],\"intentions\":[7],\"outputContext\":[7]}}}]},\"inverseRevision\":2,\"isRollback\":false}}]}"
  let assert Ok(value) = json_ot.parse_json(input)
  let assert Ok(output) =
    sequence_field_fixture.run_compose_invert(json_ot.to_json(value))
  let encoded = json.to_string(output)
  encoded
  |> string.contains(
    "\"type\":\"MoveOut\",\"id\":10,\"revision\":2,\"count\":1",
  )
  |> expect.to_be_true
  encoded
  |> string.contains(
    "\"type\":\"MoveOut\",\"id\":11,\"revision\":2,\"count\":1,\"changes\"",
  )
  |> expect.to_be_true
  encoded |> string.contains("\"intentions\":[7]") |> expect.to_be_true
}

pub fn shared_tree_sequence_compose_preserves_unreplaced_final_endpoint_test() {
  let move_id = atom(Some(revision("10")), 10)
  let final_endpoint = atom(Some(revision("11")), 20)
  let mark =
    sequence_field.Mark(
      2,
      None,
      sequence_field.Detach(sequence_field.MoveOut(
        move_id,
        Some(final_endpoint),
        None,
      )),
      None,
    )
  let assert Ok(first) = sequence_field.from_marks([mark])
  let assert Ok(empty) = sequence_field.from_marks([])
  let assert Ok(composed) = compose_changes(first, empty)
  sequence_field.to_marks(composed) |> expect.to_equal([mark])
}

pub fn shared_tree_sequence_compose_chains_detached_renames_test() {
  let original = atom(Some(revision("12")), 10)
  let intermediate = atom(Some(revision("13")), 20)
  let final = atom(Some(revision("14")), 30)
  let assert Ok(first) =
    sequence_field.from_marks([
      sequence_field.Mark(
        2,
        Some(original),
        sequence_field.Detach(sequence_field.Remove(intermediate, None)),
        None,
      ),
    ])
  let assert Ok(second) =
    sequence_field.from_marks([
      sequence_field.Mark(
        2,
        Some(intermediate),
        sequence_field.Detach(sequence_field.Remove(final, None)),
        None,
      ),
    ])
  let assert Ok(composed) = compose_changes(first, second)
  sequence_field.to_marks(composed)
  |> expect.to_equal([
    sequence_field.Mark(
      2,
      Some(original),
      sequence_field.Detach(sequence_field.Remove(final, None)),
      None,
    ),
  ])
}

pub fn shared_tree_sequence_compose_keeps_same_cell_move_out_test() {
  let id = atom(Some(revision("15")), 10)
  let mark =
    sequence_field.Mark(
      2,
      Some(id),
      sequence_field.Detach(sequence_field.MoveOut(id, None, None)),
      None,
    )
  let assert Ok(first) = sequence_field.from_marks([mark])
  let assert Ok(empty) = sequence_field.from_marks([])
  let assert Ok(composed) = compose_changes(first, empty)
  sequence_field.to_marks(composed) |> expect.to_equal([mark])
}

pub fn shared_tree_sequence_invert_keeps_same_cell_move_out_test() {
  let original_revision = revision("16")
  let inverse_revision = revision("17")
  let id = atom(Some(original_revision), 10)
  let assert Ok(change) =
    sequence_field.from_marks([
      sequence_field.Mark(
        2,
        Some(id),
        sequence_field.Detach(sequence_field.MoveOut(id, None, None)),
        None,
      ),
    ])
  let assert Ok(aliases) =
    sequence_field.new_alias_context([#(Some(original_revision), 11)])
  let assert Ok(#(inverted, _, _)) =
    invert.invert(
      change,
      True,
      aliases,
      sequence_field.alias,
      Some(inverse_revision),
      moves.FieldId(None, "field"),
      moves.new(),
    )
  sequence_field.to_marks(inverted)
  |> expect.to_equal([
    sequence_field.Mark(
      2,
      Some(id),
      sequence_field.AttachAndDetach(
        sequence_field.MoveIn(atom(Some(inverse_revision), 10), None),
        sequence_field.Remove(atom(Some(inverse_revision), 10), Some(id)),
      ),
      None,
    ),
  ])
}

pub fn shared_tree_sequence_compose_routes_inner_truncation_to_refill_test() {
  let first_revision = revision("18")
  let second_revision = revision("19")
  let assert Ok(first) =
    sequence_field.from_marks([
      sequence_field.Mark(
        2,
        Some(atom(Some(first_revision), 30)),
        sequence_field.AttachAndDetach(
          sequence_field.MoveIn(atom(Some(first_revision), 10), None),
          sequence_field.MoveOut(atom(Some(first_revision), 20), None, None),
        ),
        None,
      ),
      sequence_field.Mark(
        2,
        None,
        sequence_field.Detach(sequence_field.MoveOut(
          atom(Some(first_revision), 10),
          None,
          None,
        )),
        None,
      ),
      sequence_field.Mark(
        2,
        Some(atom(Some(first_revision), 32)),
        sequence_field.Attach(sequence_field.MoveIn(
          atom(Some(first_revision), 20),
          None,
        )),
        None,
      ),
    ])
  let assert Ok(second) =
    sequence_field.from_marks([
      sequence_field.Mark(
        2,
        Some(atom(Some(first_revision), 20)),
        sequence_field.Attach(sequence_field.MoveIn(
          atom(Some(second_revision), 40),
          None,
        )),
        None,
      ),
      sequence_field.Mark(
        2,
        Some(atom(Some(first_revision), 10)),
        sequence_field.Noop,
        None,
      ),
      sequence_field.Mark(
        2,
        None,
        sequence_field.Detach(sequence_field.MoveOut(
          atom(Some(second_revision), 40),
          None,
          None,
        )),
        None,
      ),
    ])
  let assert Ok(composed) = compose_changes(first, second)
  let marks = sequence_field.to_marks(composed)
  marks
  |> list.any(fn(mark) {
    case mark.effect {
      sequence_field.Attach(sequence_field.MoveIn(_, endpoint)) ->
        endpoint == Some(atom(Some(first_revision), 20))
      _ -> False
    }
  })
  |> expect.to_be_true
  marks
  |> list.any(fn(mark) {
    case mark.effect {
      sequence_field.Detach(sequence_field.MoveOut(_, Some(endpoint), _)) ->
        endpoint == atom(Some(first_revision), 20)
      _ -> False
    }
  })
  |> expect.to_be_false
}

pub fn shared_tree_sequence_move_effect_ranges_invalidate_dependents_test() {
  let source = moves.Key(moves.Source, Some(revision("01")), 10)
  let field = moves.FieldId(None, "items")
  let effect =
    moves.MoveEffect(
      modify_after: None,
      moved_effect: None,
      rebased_child: None,
      endpoint: Some(atom(Some(revision("02")), 20)),
      truncated_endpoint: None,
      truncated_endpoint_for_inner: None,
    )
  let assert Ok(#(moves.Query(2, None), context)) =
    moves.get(moves.new(), source, 2, Some(field))
  let assert Ok(context) = moves.set(context, source, 2, effect)
  let #(invalidated, context) = moves.take_invalidated(context)
  invalidated |> expect.to_equal([field])
  let assert Ok(#(moves.Query(1, Some(found)), context)) =
    moves.get(
      context,
      moves.Key(moves.Source, Some(revision("01")), 11),
      1,
      None,
    )
  found
  |> expect.to_equal(moves.MoveEffect(
    modify_after: None,
    moved_effect: None,
    rebased_child: None,
    endpoint: Some(atom(Some(revision("02")), 21)),
    truncated_endpoint: None,
    truncated_endpoint_for_inner: None,
  ))
  let assert Ok(context) = moves.set(context, source, 2, effect)
  moves.take_invalidated(context).0 |> expect.to_equal([])
}

pub fn shared_tree_sequence_move_dependencies_do_not_shrink_test() {
  let revision = revision("1a")
  let key = moves.Key(moves.Source, Some(revision), 10)
  let field = moves.FieldId(None, "items")
  let effect =
    moves.MoveEffect(
      modify_after: None,
      moved_effect: None,
      rebased_child: None,
      endpoint: Some(atom(Some(revision), 20)),
      truncated_endpoint: None,
      truncated_endpoint_for_inner: None,
    )
  let assert Ok(#(_, context)) = moves.get(moves.new(), key, 3, Some(field))
  let assert Ok(#(_, context)) = moves.get(context, key, 1, Some(field))
  let assert Ok(context) =
    moves.set(context, moves.Key(moves.Source, Some(revision), 12), 1, effect)
  moves.take_invalidated(context).0 |> expect.to_equal([field])

  let assert Ok(segmented) =
    moves.set(
      moves.new(),
      moves.Key(moves.Source, Some(revision), 11),
      1,
      effect,
    )
  let assert Ok(#(moves.Query(1, None), segmented)) =
    moves.get(segmented, key, 3, Some(field))
  let assert Ok(segmented) =
    moves.set(segmented, moves.Key(moves.Source, Some(revision), 12), 1, effect)
  moves.take_invalidated(segmented).0 |> expect.to_equal([field])
}

pub fn shared_tree_sequence_move_effect_ranges_split_and_validate_test() {
  let revision = revision("03")
  let key = moves.Key(moves.Source, Some(revision), 10)
  let first =
    moves.MoveEffect(
      modify_after: None,
      moved_effect: None,
      rebased_child: None,
      endpoint: Some(atom(Some(revision), 20)),
      truncated_endpoint: None,
      truncated_endpoint_for_inner: None,
    )
  let middle =
    moves.MoveEffect(
      modify_after: Some(atom(None, 50)),
      moved_effect: None,
      rebased_child: None,
      endpoint: Some(atom(Some(revision), 30)),
      truncated_endpoint: None,
      truncated_endpoint_for_inner: None,
    )
  let assert Ok(context) = moves.set(moves.new(), key, 3, first)
  let assert Ok(context) =
    moves.set(context, moves.Key(moves.Source, Some(revision), 11), 1, middle)
  let assert Ok(#(moves.Query(1, Some(left)), context)) =
    moves.get(context, key, 3, None)
  left |> expect.to_equal(first)
  let assert Ok(#(moves.Query(1, Some(center)), context)) =
    moves.get(context, moves.Key(moves.Source, Some(revision), 11), 2, None)
  center |> expect.to_equal(middle)
  let assert Ok(#(moves.Query(1, Some(right)), _)) =
    moves.get(context, moves.Key(moves.Source, Some(revision), 12), 1, None)
  right
  |> expect.to_equal(
    moves.MoveEffect(..first, endpoint: Some(atom(Some(revision), 22))),
  )
  moves.get(context, key, 0, None) |> expect.to_be_error
  let _ =
    moves.set(
      context,
      moves.Key(moves.Source, None, max_safe_integer),
      2,
      first,
    )
    |> expect.to_be_error
  Nil
}

pub fn shared_tree_sequence_move_notifications_are_typed_and_deduplicated_test() {
  let field = moves.FieldId(Some(atom(None, 1)), "items")
  let node = atom(None, 2)
  let key = moves.Key(moves.Destination, None, 3)
  let assert Ok(context) = moves.on_move_in(moves.new(), node, field)
  let assert Ok(context) = moves.on_move_in(context, node, field)
  let assert Ok(context) = moves.move_key(context, key, 2, field)
  let assert Ok(context) = moves.move_key(context, key, 2, field)
  moves.notifications(context)
  |> expect.to_equal([
    moves.NodeMoved(node, field),
    moves.KeyMoved(key, 2, field),
  ])
  let _ = moves.compose_move_key(context, key, 2, field) |> expect.to_be_error
  Nil
}

pub fn shared_tree_sequence_aliases_reserve_revisions_once_test() {
  let a = revision("04")
  let b = revision("05")
  let assert Ok(aliases) =
    sequence_field.new_alias_context([
      #(Some(a), 5),
      #(Some(b), 5),
      #(Some(a), 5),
    ])
  let assert Ok(#(first, aliases)) =
    sequence_field.alias(atom(Some(a), 2), aliases)
  let assert Ok(#(second, aliases)) =
    sequence_field.alias(atom(Some(b), 2), aliases)
  let assert Ok(#(again, aliases)) =
    sequence_field.alias(atom(Some(a), 2), aliases)
  #(first, second, again, sequence_field.alias_max_id(aliases))
  |> expect.to_equal(#(2, 8, 2, 11))
  let _ =
    sequence_field.new_alias_context([
      #(Some(a), max_safe_integer),
      #(Some(b), 0),
    ])
    |> expect.to_be_error
  Nil
}

pub fn shared_tree_sequence_helpers_visit_ranges_and_nested_ids_test() {
  let old = revision("06")
  let replacement = revision("07")
  let child = atom(Some(old), 40)
  let assert Ok(change) =
    sequence_field.from_marks([
      sequence_field.Mark(
        2,
        Some(atom(Some(old), 10)),
        sequence_field.AttachAndDetach(
          sequence_field.MoveIn(atom(Some(old), 20), Some(atom(Some(old), 30))),
          sequence_field.MoveOut(
            atom(Some(old), 50),
            Some(atom(Some(old), 60)),
            Some(atom(Some(old), 70)),
          ),
        ),
        None,
      ),
      sequence_field.Mark(
        1,
        Some(atom(Some(old), 80)),
        sequence_field.Noop,
        Some(child),
      ),
    ])
  let assert Ok(replaced) =
    sequence_field.replace_revisions(change, fn(id, _) {
      Ok(types.AtomId(Some(replacement), id.local_id))
    })
  sequence_field.to_marks(replaced)
  |> list.each(fn(mark) {
    [mark.cell_id, mark.child]
    |> list.each(fn(id) {
      case id {
        Some(id) -> id.revision |> expect.to_equal(Some(replacement))
        None -> Nil
      }
    })
  })
  let assert Ok(pruned) = sequence_field.prune(change, fn(_) { Ok(None) })
  let marks = sequence_field.to_marks(pruned)
  let assert Ok(last) = list.last(marks)
  last.child |> expect.to_equal(None)

  let assert Ok(removed) =
    sequence_field.from_marks([
      sequence_field.Mark(
        2,
        Some(atom(Some(old), 90)),
        sequence_field.Attach(sequence_field.Insert(atom(Some(old), 90))),
        None,
      ),
      sequence_field.Mark(1, None, sequence_field.Noop, Some(child)),
    ])
  sequence_field.relevant_removed_roots(removed, fn(_) {
    Ok([atom(Some(old), 100)])
  })
  |> expect.to_equal(
    Ok([
      atom(Some(old), 90),
      atom(Some(old), 91),
      atom(Some(old), 100),
    ]),
  )
}

pub fn shared_tree_sequence_rejects_zero_count_marks_test() {
  sequence_field.from_marks([
    sequence_field.Mark(0, None, sequence_field.Noop, None),
  ])
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_sequence_rejects_invalid_ranges_and_children_test() {
  let a = atom(None, 0)
  [
    sequence_field.Mark(-1, None, sequence_field.Noop, None),
    sequence_field.Mark(
      2,
      None,
      sequence_field.Attach(sequence_field.Insert(atom(None, max_safe_integer))),
      None,
    ),
    sequence_field.Mark(2, None, sequence_field.Noop, Some(a)),
    sequence_field.Mark(1, None, sequence_field.Rename(a), None),
  ]
  |> list.each(fn(mark) {
    sequence_field.from_marks([mark]) |> expect.to_be_error
  })
}

pub fn shared_tree_sequence_split_offsets_all_range_identities_test() {
  let a = revision("01")
  let b = revision("02")
  let c = revision("03")
  let d = revision("04")
  let e = revision("05")
  let f = revision("06")
  let mark =
    sequence_field.Mark(
      3,
      Some(atom(Some(a), 10)),
      sequence_field.AttachAndDetach(
        sequence_field.MoveIn(atom(Some(b), 20), Some(atom(Some(c), 30))),
        sequence_field.MoveOut(
          atom(Some(d), 40),
          Some(atom(Some(e), 50)),
          Some(atom(Some(f), 60)),
        ),
      ),
      None,
    )
  sequence_field.split_mark(mark, 1)
  |> expect.to_equal(
    Ok(#(
      sequence_field.Mark(
        1,
        Some(atom(Some(a), 10)),
        sequence_field.AttachAndDetach(
          sequence_field.MoveIn(atom(Some(b), 20), Some(atom(Some(c), 30))),
          sequence_field.MoveOut(
            atom(Some(d), 40),
            Some(atom(Some(e), 50)),
            Some(atom(Some(f), 60)),
          ),
        ),
        None,
      ),
      sequence_field.Mark(
        2,
        Some(atom(Some(a), 11)),
        sequence_field.AttachAndDetach(
          sequence_field.MoveIn(atom(Some(b), 21), Some(atom(Some(c), 31))),
          sequence_field.MoveOut(
            atom(Some(d), 41),
            Some(atom(Some(e), 51)),
            Some(atom(Some(f), 61)),
          ),
        ),
        None,
      ),
    )),
  )
  sequence_field.split_mark(mark, 0) |> expect.to_be_error
  sequence_field.split_mark(mark, 3) |> expect.to_be_error
  Nil
}

pub fn shared_tree_sequence_split_marks_rejoin_only_matching_ranges_test() {
  let a = revision("0a")
  let b = revision("0b")
  let c = revision("0c")
  let families = [
    sequence_field.Mark(2, Some(atom(Some(a), 0)), sequence_field.Noop, None),
    sequence_field.Mark(
      2,
      Some(atom(Some(a), 2)),
      sequence_field.Attach(sequence_field.Insert(atom(Some(b), 10))),
      None,
    ),
    sequence_field.Mark(
      2,
      Some(atom(Some(a), 4)),
      sequence_field.Attach(sequence_field.MoveIn(
        atom(Some(b), 20),
        Some(atom(Some(c), 30)),
      )),
      None,
    ),
    sequence_field.Mark(
      2,
      None,
      sequence_field.Detach(sequence_field.Remove(
        atom(Some(b), 40),
        Some(atom(Some(c), 50)),
      )),
      None,
    ),
    sequence_field.Mark(
      2,
      None,
      sequence_field.Detach(sequence_field.MoveOut(
        atom(Some(b), 60),
        Some(atom(Some(c), 70)),
        Some(atom(Some(a), 80)),
      )),
      None,
    ),
    sequence_field.Mark(
      2,
      Some(atom(Some(a), 6)),
      sequence_field.AttachAndDetach(
        sequence_field.Insert(atom(Some(b), 90)),
        sequence_field.Remove(atom(Some(c), 100), None),
      ),
      None,
    ),
    sequence_field.Mark(
      2,
      Some(atom(Some(a), 8)),
      sequence_field.Rename(atom(Some(c), 110)),
      None,
    ),
  ]
  families
  |> list.each(fn(mark) {
    let assert Ok(#(first, second)) = sequence_field.split_mark(mark, 1)
    let assert Ok(rejoined) = sequence_field.from_marks([first, second])
    sequence_field.to_marks(rejoined) |> expect.to_equal([mark])
  })

  let assert Ok(unmerged) =
    sequence_field.from_marks([
      sequence_field.Mark(1, Some(atom(Some(a), 0)), sequence_field.Noop, None),
      sequence_field.Mark(1, Some(atom(Some(b), 1)), sequence_field.Noop, None),
    ])
  sequence_field.to_marks(unmerged)
  |> expect.to_equal([
    sequence_field.Mark(1, Some(atom(Some(a), 0)), sequence_field.Noop, None),
    sequence_field.Mark(1, Some(atom(Some(b), 1)), sequence_field.Noop, None),
  ])
}

pub fn shared_tree_sequence_does_not_create_unsafe_merged_mark_test() {
  let first =
    sequence_field.Mark(
      max_safe_integer,
      Some(atom(None, 0)),
      sequence_field.Noop,
      None,
    )
  let second =
    sequence_field.Mark(
      1,
      Some(atom(None, max_safe_integer)),
      sequence_field.Noop,
      None,
    )
  let assert Ok(change) = sequence_field.from_marks([first, second])
  sequence_field.to_marks(change) |> expect.to_equal([first, second])
  sequence_field.into_delta(change, no_child)
  |> expect.to_equal(Ok(sequence_field.DeltaResult(None, [], [])))
}

pub fn shared_tree_sequence_editors_preserve_pre_edit_gaps_test() {
  let move_id = atom(Some(revision("07")), 11)
  let cell_id = atom(Some(revision("08")), 14)
  let assert Ok(before) = sequence_field.move(2, 2, 0, move_id, cell_id)
  sequence_field.to_marks(before)
  |> expect.to_equal([
    sequence_field.Mark(
      2,
      Some(cell_id),
      sequence_field.Attach(sequence_field.MoveIn(move_id, None)),
      None,
    ),
    sequence_field.Mark(2, None, sequence_field.Noop, None),
    sequence_field.Mark(
      2,
      None,
      sequence_field.Detach(sequence_field.MoveOut(move_id, None, None)),
      None,
    ),
  ])

  let assert Ok(after) = sequence_field.move(0, 2, 4, move_id, cell_id)
  sequence_field.to_marks(after)
  |> expect.to_equal([
    sequence_field.Mark(
      2,
      None,
      sequence_field.Detach(sequence_field.MoveOut(move_id, None, None)),
      None,
    ),
    sequence_field.Mark(2, None, sequence_field.Noop, None),
    sequence_field.Mark(
      2,
      Some(cell_id),
      sequence_field.Attach(sequence_field.MoveIn(move_id, None)),
      None,
    ),
  ])

  let assert Ok(interior) = sequence_field.move(0, 3, 1, move_id, cell_id)
  sequence_field.to_marks(interior)
  |> expect.to_equal([
    sequence_field.Mark(
      1,
      None,
      sequence_field.Detach(sequence_field.MoveOut(move_id, None, None)),
      None,
    ),
    sequence_field.Mark(
      3,
      Some(cell_id),
      sequence_field.Attach(sequence_field.MoveIn(move_id, None)),
      None,
    ),
    sequence_field.Mark(
      2,
      None,
      sequence_field.Detach(sequence_field.MoveOut(
        atom(Some(revision("07")), 12),
        None,
        None,
      )),
      None,
    ),
  ])
}

pub fn shared_tree_sequence_interior_move_preserves_nonzero_source_skip_test() {
  let move_id = atom(Some(revision("14")), 120)
  let cell_id = atom(Some(revision("15")), 130)
  let assert Ok(change) = sequence_field.move(2, 3, 3, move_id, cell_id)
  sequence_field.to_marks(change)
  |> expect.to_equal([
    sequence_field.Mark(2, None, sequence_field.Noop, None),
    sequence_field.Mark(
      1,
      None,
      sequence_field.Detach(sequence_field.MoveOut(move_id, None, None)),
      None,
    ),
    sequence_field.Mark(
      3,
      Some(cell_id),
      sequence_field.Attach(sequence_field.MoveIn(move_id, None)),
      None,
    ),
    sequence_field.Mark(
      2,
      None,
      sequence_field.Detach(sequence_field.MoveOut(
        atom(Some(revision("14")), 121),
        None,
        None,
      )),
      None,
    ),
  ])
}

pub fn shared_tree_sequence_editors_validate_before_suppressing_empty_test() {
  let id = atom(None, 0)
  let unsafe = atom(None, max_safe_integer + 1)
  let assert Ok(empty_insert) = sequence_field.insert(0, 0, id, None)
  let assert Ok(empty_remove) = sequence_field.remove(0, 0, id)
  let assert Ok(empty_move) = sequence_field.move(0, 0, 0, id, id)
  sequence_field.to_marks(empty_insert) |> expect.to_equal([])
  sequence_field.to_marks(empty_remove) |> expect.to_equal([])
  sequence_field.to_marks(empty_move) |> expect.to_equal([])
  sequence_field.insert(-1, 0, id, None) |> expect.to_be_error
  sequence_field.remove(0, 0, unsafe) |> expect.to_be_error
  sequence_field.move(0, 0, max_safe_integer + 1, id, id)
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_sequence_validates_input_and_output_lengths_separately_test() {
  let id = atom(None, 0)
  let cell = atom(None, 10)
  sequence_field.move(max_safe_integer - 1, 1, 0, id, cell)
  |> expect.to_be_ok
  sequence_field.move(0, 1, max_safe_integer, id, cell)
  |> expect.to_be_ok
  sequence_field.insert(max_safe_integer, 1, cell, None)
  |> expect.to_be_error
  sequence_field.remove(max_safe_integer, 1, id)
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_sequence_builds_ordered_child_changes_test() {
  let first = atom(None, 20)
  let second = atom(None, 21)
  let assert Ok(change) =
    sequence_field.build_child_changes([#(1, first), #(4, second)])
  sequence_field.to_marks(change)
  |> expect.to_equal([
    sequence_field.Mark(1, None, sequence_field.Noop, None),
    sequence_field.Mark(1, None, sequence_field.Noop, Some(first)),
    sequence_field.Mark(2, None, sequence_field.Noop, None),
    sequence_field.Mark(1, None, sequence_field.Noop, Some(second)),
  ])
  sequence_field.build_child_changes([#(1, first), #(1, second)])
  |> expect.to_be_error
  sequence_field.build_child_changes([#(-1, first)]) |> expect.to_be_error
  Nil
}

pub fn shared_tree_sequence_into_delta_covers_effect_families_test() {
  let a = atom(None, 1)
  let b = atom(None, 10)
  let c = atom(None, 20)
  let child = atom(None, 30)
  let nested = [#("x", forest.FieldDelta([forest.Mark(1, None, None, [])]))]
  let callback = fn(id) {
    case id == child {
      True -> Ok(nested)
      False -> Error(types.CorruptData("test", "unexpected child"))
    }
  }
  let assert Ok(change) =
    sequence_field.from_marks([
      sequence_field.Mark(1, None, sequence_field.Noop, Some(child)),
      sequence_field.Mark(
        1,
        Some(a),
        sequence_field.Attach(sequence_field.Insert(b)),
        Some(child),
      ),
      sequence_field.Mark(
        1,
        None,
        sequence_field.Detach(sequence_field.Remove(b, Some(c))),
        None,
      ),
      sequence_field.Mark(
        1,
        Some(a),
        sequence_field.Detach(sequence_field.MoveOut(b, Some(c), None)),
        None,
      ),
      sequence_field.Mark(
        1,
        Some(a),
        sequence_field.Attach(sequence_field.MoveIn(b, Some(c))),
        None,
      ),
      sequence_field.Mark(
        1,
        Some(a),
        sequence_field.AttachAndDetach(
          sequence_field.Insert(b),
          sequence_field.Remove(c, None),
        ),
        None,
      ),
      sequence_field.Mark(1, Some(a), sequence_field.Rename(c), None),
    ])
  sequence_field.into_delta(change, callback)
  |> expect.to_equal(
    Ok(
      sequence_field.DeltaResult(
        Some(
          forest.FieldDelta([
            forest.Mark(1, None, None, nested),
            forest.Mark(1, Some(a), None, []),
            forest.Mark(1, None, Some(c), []),
            forest.Mark(1, Some(c), None, []),
          ]),
        ),
        [
          forest.DetachedChange(a, nested),
        ],
        [
          forest.Rename(a, b, 1),
          forest.Rename(a, c, 1),
        ],
      ),
    ),
  )
}

pub fn shared_tree_sequence_into_delta_propagates_child_error_test() {
  let child = atom(None, 30)
  let assert Ok(change) = sequence_field.build_child_changes([#(0, child)])
  sequence_field.into_delta(change, fn(_) {
    Error(types.CorruptData("child", "failed"))
  })
  |> expect.to_equal(Error(types.CorruptData("child", "failed")))
}

pub fn shared_tree_sequence_into_delta_handles_detached_children_and_renames_test() {
  let a = atom(None, 1)
  let b = atom(None, 2)
  let c = atom(None, 3)
  let child = atom(None, 4)
  let fields = [
    #("nested", forest.FieldDelta([forest.Mark(2, None, None, [])])),
  ]
  let assert Ok(change) =
    sequence_field.from_marks([
      sequence_field.Mark(1, Some(a), sequence_field.Noop, Some(child)),
      sequence_field.Mark(
        1,
        Some(a),
        sequence_field.Detach(sequence_field.Remove(a, None)),
        Some(child),
      ),
      sequence_field.Mark(
        1,
        Some(a),
        sequence_field.AttachAndDetach(
          sequence_field.MoveIn(b, Some(c)),
          sequence_field.MoveOut(b, None, None),
        ),
        None,
      ),
      sequence_field.Mark(1, Some(a), sequence_field.Rename(c), None),
    ])
  sequence_field.into_delta(change, fn(id) {
    case id == child {
      True -> Ok(fields)
      False -> Error(types.CorruptData("test", "unexpected child"))
    }
  })
  |> expect.to_equal(
    Ok(
      sequence_field.DeltaResult(
        None,
        [
          forest.DetachedChange(a, fields),
          forest.DetachedChange(a, fields),
        ],
        [],
      ),
    ),
  )
}

pub fn shared_tree_sequence_into_delta_routes_empty_cell_children_first_test() {
  let a = atom(None, 1)
  let b = atom(None, 2)
  let c = atom(None, 3)
  let d = atom(None, 4)
  let child = atom(None, 5)
  let fields = [
    #("nested", forest.FieldDelta([forest.Mark(2, None, None, [])])),
  ]
  let assert Ok(change) =
    sequence_field.from_marks([
      sequence_field.Mark(
        1,
        Some(a),
        sequence_field.AttachAndDetach(
          sequence_field.MoveIn(b, Some(c)),
          sequence_field.Remove(d, None),
        ),
        Some(child),
      ),
      sequence_field.Mark(
        1,
        Some(a),
        sequence_field.Detach(sequence_field.MoveOut(b, None, None)),
        Some(child),
      ),
    ])
  sequence_field.into_delta(change, fn(_) { Ok(fields) })
  |> expect.to_equal(
    Ok(
      sequence_field.DeltaResult(
        None,
        [
          forest.DetachedChange(a, fields),
          forest.DetachedChange(a, fields),
        ],
        [
          forest.Rename(c, d, 1),
          forest.Rename(a, b, 1),
        ],
      ),
    ),
  )
}

pub fn shared_tree_sequence_allows_populated_insert_with_child_change_test() {
  let insert_id = atom(Some(revision("16")), 140)
  let child = atom(None, 141)
  let fields = [
    #("nested", forest.FieldDelta([forest.Mark(1, None, None, [])])),
  ]
  let assert Ok(change) =
    sequence_field.from_marks([
      sequence_field.Mark(
        1,
        None,
        sequence_field.Attach(sequence_field.Insert(insert_id)),
        Some(child),
      ),
    ])
  sequence_field.into_delta(change, fn(_) { Ok(fields) })
  |> expect.to_equal(
    Ok(
      sequence_field.DeltaResult(
        Some(
          forest.FieldDelta([
            forest.Mark(1, None, None, fields),
          ]),
        ),
        [],
        [],
      ),
    ),
  )
}

pub fn shared_tree_sequence_delta_applies_counted_move_to_forest_test() {
  let assert Ok(initial) =
    forest.new(
      array_fixture.view_id(),
      array_fixture.stored("rootArray"),
      Some(
        types.ArrayValue(items_type, [
          types.StringValue("A"),
          types.StringValue("B"),
          types.StringValue("C"),
          types.StringValue("D"),
        ]),
      ),
    )
  let move_id = atom(None, 40)
  let cell_id = atom(Some(revision("09")), 50)
  let assert Ok(change) = sequence_field.move(0, 2, 4, move_id, cell_id)
  let assert Ok(parts) = sequence_field.into_delta(change, no_child)
  let assert Some(local) = parts.local
  let assert Ok(delta) =
    forest.delta(
      forest.DeltaData(
        None,
        [
          #(
            "rootFieldKey",
            forest.FieldDelta([
              forest.Mark(1, None, None, [#("", local)]),
            ]),
          ),
        ],
        [],
        [],
        parts.global,
        parts.rename,
        [],
      ),
    )
  let assert Ok(moved) = forest.apply_delta(initial, delta)
  forest.array_values(moved, [])
  |> expect.to_equal(
    Ok([
      types.StringValue("C"),
      types.StringValue("D"),
      types.StringValue("A"),
      types.StringValue("B"),
    ]),
  )
}

pub fn shared_tree_sequence_deltas_apply_insert_remove_and_interior_move_test() {
  let assert Ok(inserted) =
    apply_root_change(
      ["A", "B"],
      sequence_field.insert(
        1,
        2,
        atom(Some(revision("0d")), 60),
        Some(revision("0e")),
      ),
      [
        forest.Build(atom(Some(revision("0d")), 60), [
          types.StringValue("X"),
          types.StringValue("Y"),
        ]),
      ],
    )
  forest.array_values(inserted, [])
  |> expect.to_equal(
    Ok([
      types.StringValue("A"),
      types.StringValue("X"),
      types.StringValue("Y"),
      types.StringValue("B"),
    ]),
  )

  let removed_id = atom(Some(revision("0f")), 70)
  let assert Ok(removed) =
    apply_root_change(
      ["A", "B", "C", "D"],
      sequence_field.remove(1, 2, removed_id),
      [],
    )
  forest.array_values(removed, [])
  |> expect.to_equal(
    Ok([
      types.StringValue("A"),
      types.StringValue("D"),
    ]),
  )
  let assert Ok(removed_reference) = forest.locate_detached(removed, removed_id)
  forest.read_node(removed, removed_reference)
  |> expect.to_equal(Ok(types.StringValue("B")))

  let assert Ok(interior) =
    apply_root_change(
      ["A", "B", "C", "D"],
      sequence_field.move(
        0,
        3,
        1,
        atom(Some(revision("10")), 80),
        atom(Some(revision("11")), 90),
      ),
      [],
    )
  forest.array_values(interior, [])
  |> expect.to_equal(
    Ok([
      types.StringValue("A"),
      types.StringValue("B"),
      types.StringValue("C"),
      types.StringValue("D"),
    ]),
  )
}

pub fn shared_tree_sequence_paired_endpoints_apply_across_fields_test() {
  let root =
    types.ObjectValue("org.watershed.shared-tree.m3.Root", [
      #(
        "left",
        types.ArrayValue(items_type, [
          types.StringValue("A"),
          types.StringValue("B"),
        ]),
      ),
      #("right", types.ArrayValue(items_type, [types.StringValue("C")])),
      #("byKey", types.MapValue("org.watershed.shared-tree.m3.ArrayMap", [])),
      #("narrow", types.ArrayValue("org.watershed.shared-tree.m3.Points", [])),
    ])
  let assert Ok(initial) =
    forest.new(
      array_fixture.view_id(),
      array_fixture.stored("objectArrays"),
      Some(root),
    )
  let move_id = atom(Some(revision("12")), 100)
  let assert Ok(out) = sequence_field.move_out(0, 2, move_id)
  let assert Ok(into) =
    sequence_field.move_in(1, 2, move_id, atom(Some(revision("13")), 110))
  let assert Ok(out_delta) = sequence_field.into_delta(out, no_child)
  let assert Ok(in_delta) = sequence_field.into_delta(into, no_child)
  let assert Some(out_local) = out_delta.local
  let assert Some(in_local) = in_delta.local
  let assert Ok(delta) =
    forest.delta(
      forest.DeltaData(
        None,
        [
          #(
            "rootFieldKey",
            forest.FieldDelta([
              forest.Mark(1, None, None, [
                #(
                  "left",
                  forest.FieldDelta([
                    forest.Mark(1, None, None, [#("", out_local)]),
                  ]),
                ),
                #(
                  "right",
                  forest.FieldDelta([
                    forest.Mark(1, None, None, [#("", in_local)]),
                  ]),
                ),
              ]),
            ]),
          ),
        ],
        [],
        [],
        list.append(out_delta.global, in_delta.global),
        list.append(out_delta.rename, in_delta.rename),
        [],
      ),
    )
  let assert Ok(moved) = forest.apply_delta(initial, delta)
  forest.array_values(moved, ["left"]) |> expect.to_equal(Ok([]))
  forest.array_values(moved, ["right"])
  |> expect.to_equal(
    Ok([
      types.StringValue("C"),
      types.StringValue("A"),
      types.StringValue("B"),
    ]),
  )
}

pub fn shared_tree_sequence_inverse_restores_forest_identity_test() {
  let original_revision = revision("1b")
  let inverse_revision = revision("1c")
  let removed_id = atom(Some(original_revision), 10)
  let assert Ok(initial) =
    forest.new(
      array_fixture.view_id(),
      array_fixture.stored("rootArray"),
      Some(
        types.ArrayValue(items_type, [
          types.StringValue("A"),
          types.StringValue("B"),
          types.StringValue("C"),
        ]),
      ),
    )
  let assert Ok(retained) = forest.locate(initial, ["1"])
  let assert Ok(change) = sequence_field.remove(1, 1, removed_id)
  let assert Ok(aliases) =
    sequence_field.new_alias_context([#(Some(original_revision), 10)])
  let assert Ok(#(inverse, _, _)) =
    invert.invert(
      change,
      False,
      aliases,
      sequence_field.alias,
      Some(inverse_revision),
      moves.FieldId(None, "rootFieldKey"),
      moves.new(),
    )
  let assert Ok(removed) = apply_change_to_root(initial, change, [])
  forest.is_attached(removed, retained) |> expect.to_equal(Ok(False))
  let assert Ok(restored) = apply_change_to_root(removed, inverse, [])
  forest.array_values(restored, [])
  |> expect.to_equal(
    Ok([
      types.StringValue("A"),
      types.StringValue("B"),
      types.StringValue("C"),
    ]),
  )
  forest.locate(restored, ["1"]) |> expect.to_equal(Ok(retained))
  forest.read_node(restored, retained)
  |> expect.to_equal(Ok(types.StringValue("B")))
  forest.is_attached(restored, retained) |> expect.to_equal(Ok(True))
  forest.node_path(restored, ["1"])
  |> expect.to_equal(forest.node_path(initial, ["1"]))
}

pub fn shared_tree_sequence_aliases_span_fields_and_reprocessing_test() {
  let first_revision = revision("1d")
  let second_revision = revision("1e")
  let inverse_revision = revision("1f")
  let child = atom(None, 30)
  let assert Ok(first) =
    sequence_field.from_marks([
      sequence_field.Mark(
        2,
        Some(atom(Some(first_revision), 12)),
        sequence_field.Attach(sequence_field.MoveIn(
          atom(Some(first_revision), 10),
          None,
        )),
        None,
      ),
      sequence_field.Mark(
        1,
        None,
        sequence_field.Detach(sequence_field.MoveOut(
          atom(Some(first_revision), 10),
          None,
          None,
        )),
        None,
      ),
      sequence_field.Mark(
        1,
        None,
        sequence_field.Detach(sequence_field.MoveOut(
          atom(Some(first_revision), 11),
          None,
          None,
        )),
        Some(child),
      ),
    ])
  let assert Ok(second) =
    sequence_field.from_marks([
      sequence_field.Mark(
        1,
        None,
        sequence_field.Detach(sequence_field.MoveOut(
          atom(Some(second_revision), 10),
          Some(atom(Some(first_revision), 11)),
          None,
        )),
        None,
      ),
    ])
  let assert Ok(aliases) =
    sequence_field.new_alias_context([
      #(Some(first_revision), 12),
      #(Some(second_revision), 10),
    ])
  let assert Ok(#(first_inverse, aliases, move_context)) =
    invert_with_retry(
      first,
      aliases,
      Some(inverse_revision),
      moves.FieldId(None, "left"),
      moves.new(),
    )
  let after_first = sequence_field.alias_max_id(aliases)
  let assert Ok(#(second_inverse, aliases, _)) =
    invert_with_retry(
      second,
      aliases,
      Some(inverse_revision),
      moves.FieldId(None, "right"),
      move_context,
    )
  let after_second = sequence_field.alias_max_id(aliases)
  let assert Ok(#(first_alias, aliases)) =
    sequence_field.alias(atom(Some(first_revision), 10), aliases)
  let assert Ok(#(second_alias, aliases)) =
    sequence_field.alias(atom(Some(second_revision), 10), aliases)
  let assert Ok(#(first_again, aliases)) =
    sequence_field.alias(atom(Some(first_revision), 10), aliases)
  let aliases_collide = first_alias == second_alias
  aliases_collide |> expect.to_be_false
  first_again |> expect.to_equal(first_alias)
  sequence_field.alias_max_id(aliases)
  |> expect.to_equal(after_second)
  let allocation_is_monotonic = after_first <= after_second
  allocation_is_monotonic |> expect.to_be_true
  sequence_field.to_marks(first_inverse)
  |> list.any(fn(mark) { mark.count == 1 && mark.child == Some(child) })
  |> expect.to_be_true
  sequence_field.to_marks(second_inverse)
  |> list.any(fn(mark) {
    case mark.effect {
      sequence_field.Attach(sequence_field.MoveIn(_, Some(endpoint))) ->
        endpoint.revision == Some(inverse_revision)
        && endpoint.local_id != second_alias
      _ -> False
    }
  })
  |> expect.to_be_true
}

pub fn shared_tree_sequence_compose_uses_child_callback_result_and_error_test() {
  let left = atom(None, 1)
  let right = atom(None, 2)
  let replacement = atom(None, 3)
  let assert Ok(first) =
    sequence_field.from_marks([
      sequence_field.Mark(1, None, sequence_field.Noop, Some(left)),
    ])
  let assert Ok(second) =
    sequence_field.from_marks([
      sequence_field.Mark(1, None, sequence_field.Noop, Some(right)),
    ])
  let assert Ok(#(composed, 1, _)) =
    compose.compose(
      first,
      second,
      0,
      fn(actual_left, actual_right, calls) {
        actual_left |> expect.to_equal(Some(left))
        actual_right |> expect.to_equal(Some(right))
        Ok(#(replacement, calls + 1))
      },
      test_algebra(),
      moves.FieldId(None, "field"),
      moves.new(),
    )
  sequence_field.to_marks(composed)
  |> expect.to_equal([
    sequence_field.Mark(1, None, sequence_field.Noop, Some(replacement)),
  ])
  compose.compose(
    first,
    second,
    Nil,
    fn(_, _, _) { Error(types.CorruptData("test", "child composition failed")) },
    test_algebra(),
    moves.FieldId(None, "field"),
    moves.new(),
  )
  |> expect.to_equal(
    Error(types.CorruptData("test", "child composition failed")),
  )
}

fn apply_root_change(
  values: List(String),
  change: Result(sequence_field.Changeset, types.TreeError),
  builds: List(forest.Build),
) -> Result(forest.Forest, types.TreeError) {
  use initial <- result.try(forest.new(
    array_fixture.view_id(),
    array_fixture.stored("rootArray"),
    Some(types.ArrayValue(items_type, list.map(values, types.StringValue))),
  ))
  use change <- result.try(change)
  apply_change_to_root(initial, change, builds)
}

fn apply_change_to_root(
  initial: forest.Forest,
  change: sequence_field.Changeset,
  builds: List(forest.Build),
) -> Result(forest.Forest, types.TreeError) {
  use parts <- result.try(sequence_field.into_delta(change, no_child))
  let assert Some(local) = parts.local
  use delta <- result.try(
    forest.delta(
      forest.DeltaData(
        None,
        [
          #(
            "rootFieldKey",
            forest.FieldDelta([
              forest.Mark(1, None, None, [#("", local)]),
            ]),
          ),
        ],
        builds,
        [],
        parts.global,
        parts.rename,
        [],
      ),
    ),
  )
  forest.apply_delta(initial, delta)
}

fn invert_with_retry(
  change: sequence_field.Changeset,
  aliases: sequence_field.AliasContext,
  inverse_revision: Option(fluid_ids.StableId),
  field: moves.FieldId,
  move_context: moves.Context,
) -> Result(
  #(sequence_field.Changeset, sequence_field.AliasContext, moves.Context),
  types.TreeError,
) {
  use #(inverse, aliases, move_context) <- result.try(invert.invert(
    change,
    False,
    aliases,
    sequence_field.alias,
    inverse_revision,
    field,
    move_context,
  ))
  let #(invalidated, move_context) = moves.take_invalidated(move_context)
  case invalidated {
    [] -> Ok(#(inverse, aliases, move_context))
    _ ->
      invert.invert(
        change,
        False,
        aliases,
        sequence_field.alias,
        inverse_revision,
        field,
        move_context,
      )
  }
}
