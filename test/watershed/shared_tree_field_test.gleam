import gleam/list
import gleam/option.{type Option, None, Some}
import startest/expect
import watershed/fluid_ids
import watershed/tree/forest
import watershed/tree/optional_field as field
import watershed/tree/schema
import watershed/tree/types

const max_id = 9_007_199_254_740_991

fn revision(suffix: String) -> fluid_ids.StableId {
  let assert Ok(id) =
    fluid_ids.stable_id("00000000-0000-4000-8000-0000000000" <> suffix)
  id
}

fn atom(id: Int) -> types.AtomId {
  types.AtomId(Some(revision("01")), id)
}

fn no_child_delta(
  _: types.AtomId,
) -> Result(List(#(String, forest.FieldDelta)), types.TreeError) {
  Error(types.CorruptData("test.child", "Unexpected child callback"))
}

fn new_forest(required: Bool, root: Option(types.TreeValue)) -> forest.Forest {
  let kind = case required {
    True -> "Value"
    False -> "Optional"
  }
  let assert Ok(stored) =
    schema.stored_from_string(
      "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"com.fluidframework.leaf.null\":{\"kind\":{\"leaf\":4}}},\"root\":{\"kind\":\""
      <> kind
      <> "\",\"types\":[\"com.fluidframework.leaf.string\",\"com.fluidframework.leaf.null\"]}}",
    )
  let assert Ok(state) = forest.new(revision("ff"), stored, root)
  state
}

fn apply(
  state: forest.Forest,
  change: field.FieldChange,
  builds: List(forest.Build),
) -> Result(forest.Forest, types.TreeError) {
  let assert Ok(delta) = field.into_delta(change, no_child_delta)
  let fields = case delta.local {
    None -> []
    Some(local) -> [#("rootFieldKey", local)]
  }
  let assert Ok(delta) =
    forest.delta(
      forest.DeltaData(
        latest_revision: Some(revision("01")),
        fields:,
        build: builds,
        refreshers: [],
        global: delta.global,
        rename: delta.rename,
        destroy: [],
      ),
    )
  forest.apply_delta(state, delta)
}

pub fn shared_tree_field_clear_empty_keeps_reservation_test() -> Nil {
  let change = field.clear(True, atom(1))
  change
  |> expect.to_equal(field.FieldChange(
    [],
    [],
    Some(field.Replacement(True, None, atom(1))),
  ))
  field.into_delta(change, no_child_delta)
  |> expect.to_equal(Ok(field.FieldDelta(None, [], [])))
}

pub fn shared_tree_field_set_and_clear_emit_singleton_marks_test() -> Nil {
  [
    #(
      field.set(True, atom(0), atom(1)),
      forest.Mark(1, Some(atom(0)), None, []),
    ),
    #(
      field.set(False, atom(0), atom(1)),
      forest.Mark(1, Some(atom(0)), Some(atom(1)), []),
    ),
    #(field.clear(False, atom(1)), forest.Mark(1, None, Some(atom(1)), [])),
  ]
  |> list.each(fn(pair) {
    field.into_delta(pair.0, no_child_delta)
    |> expect.to_equal(
      Ok(field.FieldDelta(Some(forest.FieldDelta([pair.1])), [], [])),
    )
  })
}

pub fn shared_tree_field_active_pin_differs_from_clear_test() -> Nil {
  let pin =
    field.FieldChange(
      [],
      [],
      Some(field.Replacement(False, Some(field.Active), atom(2))),
    )
  field.into_delta(pin, no_child_delta)
  |> expect.to_equal(Ok(field.FieldDelta(None, [], [])))
  field.into_delta(field.clear(False, atom(2)), no_child_delta)
  |> expect.to_equal(
    Ok(
      field.FieldDelta(
        Some(forest.FieldDelta([forest.Mark(1, None, Some(atom(2)), [])])),
        [],
        [],
      ),
    ),
  )
}

pub fn shared_tree_field_delta_routes_local_and_detached_children_test() -> Nil {
  let nested = [#("child", forest.FieldDelta([]))]
  let change =
    field.FieldChange(
      [#(atom(2), atom(3))],
      [#(field.Active, atom(40)), #(field.Detached(atom(2)), atom(41))],
      None,
    )
  let callback = fn(node) {
    case node {
      types.AtomId(_, 40) -> Ok([])
      types.AtomId(_, 41) -> Ok(nested)
      _ -> Error(types.CorruptData("test.child", "Unexpected node"))
    }
  }
  field.into_delta(change, callback)
  |> expect.to_equal(
    Ok(
      field.FieldDelta(
        Some(forest.FieldDelta([forest.Mark(1, None, None, [])])),
        [forest.DetachedChange(atom(2), nested)],
        [forest.Rename(atom(2), atom(3), 1)],
      ),
    ),
  )
}

pub fn shared_tree_field_delta_propagates_child_error_test() -> Nil {
  let error = types.CorruptData("child", "Invalid nested change")
  let change = field.FieldChange([], [#(field.Active, atom(40))], None)
  field.into_delta(change, fn(_) { Error(error) })
  |> expect.to_equal(Error(error))
}

pub fn shared_tree_field_validation_rejects_ambiguous_or_unsafe_ids_test() -> Nil {
  [
    field.FieldChange([#(atom(0), atom(2)), #(atom(0), atom(3))], [], None),
    field.FieldChange([#(atom(0), atom(2)), #(atom(1), atom(2))], [], None),
    field.FieldChange(
      [],
      [#(field.Active, atom(40)), #(field.Active, atom(41))],
      None,
    ),
    field.FieldChange([], [#(field.Detached(atom(-1)), atom(40))], None),
    field.FieldChange([], [#(field.Active, atom(-1))], None),
    field.set(True, atom(-1), atom(1)),
    field.set(True, atom(0), atom(max_id + 1)),
    field.FieldChange([#(atom(0), atom(max_id + 1))], [], None),
  ]
  |> list.each(fn(change) {
    let assert Error(types.CorruptData(location, _)) = field.validate(change)
    { location != "" } |> expect.to_be_true
  })
  field.validate(field.set(True, atom(max_id), atom(0)))
  |> expect.to_equal(Ok(field.set(True, atom(max_id), atom(0))))
}

pub fn shared_tree_field_revision_replacement_visits_every_atom_test() -> Nil {
  let anonymous = types.AtomId(None, 30)
  let other = types.AtomId(Some(revision("02")), 20)
  let updated = Some(revision("03"))
  let change =
    field.FieldChange(
      [#(atom(0), other)],
      [#(field.Active, anonymous), #(field.Detached(atom(4)), atom(40))],
      Some(field.Replacement(False, Some(field.Detached(atom(2))), atom(3))),
    )
  field.replace_revisions(change, [Some(revision("01")), None], updated)
  |> expect.to_equal(
    Ok(field.FieldChange(
      [#(types.AtomId(updated, 0), other)],
      [
        #(field.Active, types.AtomId(updated, 30)),
        #(field.Detached(types.AtomId(updated, 4)), types.AtomId(updated, 40)),
      ],
      Some(field.Replacement(
        False,
        Some(field.Detached(types.AtomId(updated, 2))),
        types.AtomId(updated, 3),
      )),
    )),
  )
  field.replace_revisions(change, [], updated) |> expect.to_equal(Ok(change))
}

pub fn shared_tree_field_revision_collision_is_rejected_test() -> Nil {
  let other = types.AtomId(Some(revision("02")), 0)
  let change =
    field.FieldChange([#(atom(0), atom(1)), #(other, atom(2))], [], None)
  let assert Error(types.CorruptData(_, _)) =
    field.replace_revisions(
      change,
      [Some(revision("02"))],
      Some(revision("01")),
    )
  Nil
}

pub fn shared_tree_field_null_and_absence_remain_distinct_test() -> Nil {
  let initial = new_forest(False, None)
  let assert Ok(filled) =
    apply(initial, field.set(True, atom(0), atom(1)), [
      forest.Build(atom(0), [types.NullValue]),
    ])
  forest.visible_root(filled) |> expect.to_equal(Ok(Some(types.NullValue)))
  let assert Ok(reference) = forest.locate(filled, [])
  let assert Ok(cleared) = apply(filled, field.clear(False, atom(2)), [])
  forest.visible_root(cleared) |> expect.to_equal(Ok(None))
  forest.is_attached(cleared, reference) |> expect.to_equal(Ok(False))
  forest.read_node(cleared, reference) |> expect.to_equal(Ok(types.NullValue))
}

pub fn shared_tree_field_required_clear_is_atomic_test() -> Nil {
  let initial = new_forest(True, Some(types.StringValue("original")))
  let before = forest.export_data(initial)
  let assert Ok(reference) = forest.locate(initial, [])
  let assert Error(types.CorruptData(_, _)) =
    apply(initial, field.clear(False, atom(1)), [])
  forest.export_data(initial) |> expect.to_equal(before)
  forest.is_attached(initial, reference) |> expect.to_equal(Ok(True))
  forest.read_node(initial, reference)
  |> expect.to_equal(Ok(types.StringValue("original")))
}

pub fn shared_tree_field_swap_is_valid_algebra_but_not_forest_rename_test() -> Nil {
  let initial = new_forest(False, None)
  let assert Ok(built) =
    apply(initial, field.empty(), [
      forest.Build(atom(4), [types.StringValue("four")]),
      forest.Build(atom(5), [types.StringValue("five")]),
    ])
  let change =
    field.FieldChange([#(atom(4), atom(5)), #(atom(5), atom(4))], [], None)
  field.validate(change) |> expect.to_equal(Ok(change))
  let before = forest.export_data(built)
  let assert Error(types.CorruptData("rename", _)) = apply(built, change, [])
  forest.export_data(built) |> expect.to_equal(before)
  let self_move = field.FieldChange([#(atom(4), atom(4))], [], None)
  field.validate(self_move) |> expect.to_equal(Ok(self_move))
  let assert Ok(unchanged) = apply(built, self_move, [])
  forest.export_data(unchanged) |> expect.to_equal(before)
}

pub fn shared_tree_field_unknown_attach_is_atomic_test() -> Nil {
  let initial = new_forest(False, Some(types.StringValue("original")))
  let before = forest.export_data(initial)
  let assert Error(types.CorruptData(_, _)) =
    apply(initial, field.set(False, atom(99), atom(1)), [
      forest.Build(atom(2), [types.StringValue("candidate")]),
    ])
  forest.export_data(initial) |> expect.to_equal(before)
}

fn no_compose(
  _: Option(types.AtomId),
  _: Option(types.AtomId),
  _: Nil,
) -> Result(#(types.AtomId, Nil), types.TreeError) {
  Error(types.CorruptData("test.child", "Unexpected child callback"))
}

pub fn shared_tree_field_compose_preserves_replaced_fill_test() -> Nil {
  field.compose(
    field.set(True, atom(0), atom(1)),
    field.set(False, atom(2), atom(3)),
    Nil,
    no_compose,
  )
  |> expect.to_equal(
    Ok(#(
      field.FieldChange(
        [#(atom(0), atom(3))],
        [],
        Some(field.Replacement(True, Some(field.Detached(atom(2))), atom(1))),
      ),
      Nil,
    )),
  )
}

pub fn shared_tree_field_compose_editor_pairs_test() -> Nil {
  [
    #(
      field.set(True, atom(0), atom(1)),
      field.clear(False, atom(2)),
      field.FieldChange(
        [#(atom(0), atom(2))],
        [],
        Some(field.Replacement(True, None, atom(1))),
      ),
    ),
    #(
      field.clear(False, atom(1)),
      field.set(True, atom(2), atom(3)),
      field.FieldChange(
        [],
        [],
        Some(field.Replacement(False, Some(field.Detached(atom(2))), atom(1))),
      ),
    ),
    #(
      field.clear(False, atom(1)),
      field.clear(True, atom(2)),
      field.clear(False, atom(1)),
    ),
    #(
      field.clear(False, atom(1)),
      field.set(True, atom(1), atom(2)),
      field.FieldChange(
        [],
        [],
        Some(field.Replacement(False, Some(field.Active), atom(2))),
      ),
    ),
  ]
  |> list.each(fn(item) {
    field.compose(item.0, item.1, Nil, no_compose)
    |> expect.to_equal(Ok(#(item.2, Nil)))
  })
}

pub fn shared_tree_field_compose_routes_children_to_input_registers_test() -> Nil {
  let first =
    field.FieldChange(
      [],
      [#(field.Active, atom(40)), #(field.Detached(atom(0)), atom(41))],
      Some(field.Replacement(False, Some(field.Detached(atom(0))), atom(1))),
    )
  let second =
    field.FieldChange(
      [],
      [
        #(field.Active, atom(42)),
        #(field.Detached(atom(1)), atom(43)),
        #(field.Detached(atom(9)), atom(44)),
      ],
      None,
    )
  let compose_child = fn(left, right, calls) {
    case left, right {
      Some(types.AtomId(_, 40)), Some(types.AtomId(_, 43)) ->
        Ok(#(atom(50), list.append(calls, [#(left, right)])))
      Some(types.AtomId(_, 41)), Some(types.AtomId(_, 42)) ->
        Ok(#(atom(51), list.append(calls, [#(left, right)])))
      None, Some(types.AtomId(_, 44)) ->
        Ok(#(atom(52), list.append(calls, [#(left, right)])))
      _, _ -> Error(types.CorruptData("callback", "Unexpected arguments"))
    }
  }
  let assert Ok(#(change, calls)) =
    field.compose(first, second, [], compose_child)
  calls
  |> expect.to_equal([
    #(Some(atom(40)), Some(atom(43))),
    #(Some(atom(41)), Some(atom(42))),
    #(None, Some(atom(44))),
  ])
  change.child_changes
  |> expect.to_equal([
    #(field.Active, atom(50)),
    #(field.Detached(atom(0)), atom(51)),
    #(field.Detached(atom(9)), atom(52)),
  ])
}

pub fn shared_tree_field_compose_moves_and_nested_map_order_test() -> Nil {
  let other = fn(id) { types.AtomId(Some(revision("02")), id) }
  let first =
    field.FieldChange(
      [
        #(atom(0), atom(1)),
        #(other(2), other(3)),
        #(atom(4), atom(5)),
      ],
      [],
      None,
    )
  let second =
    field.FieldChange(
      [#(atom(1), atom(6))],
      [
        #(field.Detached(atom(10)), atom(40)),
        #(field.Detached(atom(11)), atom(41)),
        #(field.Detached(other(10)), atom(42)),
      ],
      None,
    )
  let callback = fn(left, right, calls) {
    case left, right {
      None, Some(id) -> Ok(#(id, list.append(calls, [id])))
      _, _ -> Error(types.CorruptData("callback", "Unexpected arguments"))
    }
  }
  let assert Ok(#(change, calls)) = field.compose(first, second, [], callback)
  change.moves
  |> expect.to_equal([
    #(atom(0), atom(6)),
    #(atom(4), atom(5)),
    #(other(2), other(3)),
  ])
  calls |> expect.to_equal([atom(40), atom(42), atom(41)])
}

pub fn shared_tree_field_compose_failure_has_no_partial_context_test() -> Nil {
  let original = [atom(99)]
  let change =
    field.FieldChange(
      [],
      [#(field.Active, atom(40)), #(field.Detached(atom(1)), atom(41))],
      None,
    )
  let error = types.InvalidHistory("Child composition failed")
  let callback = fn(left, _, context) {
    case left {
      Some(types.AtomId(_, 40)) -> Ok(#(atom(50), [atom(50), ..context]))
      _ -> Error(error)
    }
  }
  field.compose(change, field.empty(), original, callback)
  |> expect.to_equal(Error(error))
  original |> expect.to_equal([atom(99)])
  let invalid = field.FieldChange([#(atom(-1), atom(0))], [], None)
  let assert Error(types.CorruptData(_, _)) =
    field.compose(invalid, change, original, fn(_, _, _) {
      Error(types.InvalidHistory("Input validation did not run"))
    })
  Nil
}

pub fn shared_tree_field_composition_matches_sequential_forest_test() -> Nil {
  let initial = new_forest(False, Some(types.StringValue("old")))
  let assert Ok(original) = forest.locate(initial, [])
  let first = field.set(False, atom(0), atom(1))
  let second = field.set(False, atom(2), atom(3))
  let builds = [
    forest.Build(atom(0), [types.StringValue("first")]),
    forest.Build(atom(2), [types.StringValue("second")]),
  ]
  let assert Ok(built) = apply(initial, field.empty(), builds)
  let assert Ok(first_state) = apply(built, first, [])
  let assert Ok(sequential) = apply(first_state, second, [])
  let assert Ok(#(composed, Nil)) =
    field.compose(first, second, Nil, no_compose)
  let assert Ok(composed_state) = apply(built, composed, [])
  forest.visible_root(composed_state)
  |> expect.to_equal(Ok(Some(types.StringValue("second"))))
  forest.visible_root(composed_state)
  |> expect.to_equal(forest.visible_root(sequential))
  list.each([composed_state, sequential], fn(state) {
    forest.is_attached(state, original) |> expect.to_equal(Ok(False))
    let assert Ok(old) = forest.locate_detached(state, atom(1))
    old |> expect.to_equal(original)
    forest.read_node(state, old)
    |> expect.to_equal(Ok(types.StringValue("old")))
    let assert Ok(replaced) = forest.locate_detached(state, atom(3))
    forest.read_node(state, replaced)
    |> expect.to_equal(Ok(types.StringValue("first")))
  })
}
