import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import startest/expect
import watershed/fluid_ids
import watershed/tree/array_change_fixture
import watershed/tree/array_fixture
import watershed/tree/change
import watershed/tree/fixtures
import watershed/tree/forest
import watershed/tree/sequence_field
import watershed/tree/sequence_field/moves
import watershed/tree/types

const items_type = "org.watershed.shared-tree.m3.Items"

const point_type = "org.watershed.shared-tree.m3.Point"

fn revision() -> fluid_ids.StableId {
  let assert Ok(id) =
    fluid_ids.stable_id("20000000-0000-4000-8000-000000000001")
  id
}

fn revision_b() -> fluid_ids.StableId {
  let assert Ok(id) =
    fluid_ids.stable_id("20000000-0000-4000-8000-000000000002")
  id
}

fn identity_order() -> change.IdentityOrder {
  let assert Ok(order) =
    change.identity_order([#(revision(), 0), #(revision_b(), 1)])
  order
}

fn apply_edit(
  schema_name: String,
  root: types.TreeValue,
  edit: types.Edit,
) -> Result(forest.Forest, types.TreeError) {
  let stored = array_fixture.stored(schema_name)
  use initial <- result.try(forest.new(
    array_fixture.view_id(),
    stored,
    Some(root),
  ))
  use authored <- result.try(change.edit(
    stored,
    initial,
    revision(),
    edit,
    identity_order(),
  ))
  use delta <- result.try(
    change.into_delta(change.TaggedChange(Some(revision()), None, authored)),
  )
  forest.apply_delta(initial, delta)
}

pub fn shared_tree_array_modular_algebra_matches_source_test() {
  fixtures.assert_case("array-modular-algebra", array_change_fixture.run)
}

pub fn shared_tree_array_change_authors_root_insert_remove_and_move_test() {
  let root =
    types.ArrayValue(items_type, [
      types.StringValue("A"),
      types.StringValue("B"),
      types.StringValue("C"),
    ])
  let assert Ok(inserted) =
    apply_edit(
      "rootArray",
      root,
      types.ArrayInsert([], 1, [
        types.StringValue("X"),
        types.StringValue("Y"),
      ]),
    )
  forest.array_values(inserted, [])
  |> expect.to_equal(
    Ok([
      types.StringValue("A"),
      types.StringValue("X"),
      types.StringValue("Y"),
      types.StringValue("B"),
      types.StringValue("C"),
    ]),
  )

  let assert Ok(removed) =
    apply_edit("rootArray", root, types.ArrayRemove([], 1, 3))
  forest.array_values(removed, [])
  |> expect.to_equal(Ok([types.StringValue("A")]))

  let assert Ok(moved) =
    apply_edit("rootArray", root, types.ArrayMove([], 0, 1, [], 3))
  forest.array_values(moved, [])
  |> expect.to_equal(
    Ok([
      types.StringValue("B"),
      types.StringValue("C"),
      types.StringValue("A"),
    ]),
  )
}

pub fn shared_tree_array_change_wraps_nonzero_array_ancestor_test() {
  let point = fn(label, x) {
    types.ObjectValue(point_type, [
      #("label", types.StringValue(label)),
      #("x", types.NumberValue(x)),
    ])
  }
  let root =
    types.ArrayValue(items_type, [
      point("first", 1.0),
      point("second", 2.0),
      point("third", 3.0),
    ])
  let assert Ok(changed) =
    apply_edit(
      "rootArray",
      root,
      types.SetField(["2", "x"], types.NumberValue(9.0)),
    )
  forest.array_values(changed, [])
  |> expect.to_equal(
    Ok([
      point("first", 1.0),
      point("second", 2.0),
      point("third", 9.0),
    ]),
  )
}

pub fn shared_tree_array_change_moves_between_arrays_without_reallocating_nodes_test() {
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
  let stored = array_fixture.stored("objectArrays")
  let assert Ok(initial) =
    forest.new(array_fixture.view_id(), stored, Some(root))
  let assert Ok(retained) = forest.locate(initial, ["left", "1"])
  let assert Ok(authored) =
    change.edit(
      stored,
      initial,
      revision(),
      types.ArrayMove(["left"], 1, 2, ["right"], 1),
      identity_order(),
    )
  let assert Ok(delta) =
    change.into_delta(change.TaggedChange(Some(revision()), None, authored))
  let assert Ok(moved) = forest.apply_delta(initial, delta)
  forest.array_values(moved, ["left"])
  |> expect.to_equal(Ok([types.StringValue("A")]))
  forest.array_values(moved, ["right"])
  |> expect.to_equal(Ok([types.StringValue("C"), types.StringValue("B")]))
  forest.locate(moved, ["right", "1"]) |> expect.to_equal(Ok(retained))
}

pub fn shared_tree_array_change_validates_ranges_content_cycles_and_capacity_test() {
  let root =
    types.ObjectValue("org.watershed.shared-tree.m3.Root", [
      #(
        "left",
        types.ArrayValue(items_type, [
          types.StringValue("A"),
          types.ArrayValue(items_type, [types.StringValue("nested")]),
        ]),
      ),
      #("right", types.ArrayValue(items_type, [])),
      #("byKey", types.MapValue("org.watershed.shared-tree.m3.ArrayMap", [])),
      #("narrow", types.ArrayValue("org.watershed.shared-tree.m3.Points", [])),
    ])
  let stored = array_fixture.stored("objectArrays")
  let assert Ok(initial) =
    forest.new(array_fixture.view_id(), stored, Some(root))
  let assert Ok(before) = forest.export_data(initial)

  change.validate_edit(stored, initial, types.ArrayInsert(["left"], -1, []))
  |> expect.to_equal(
    Error(types.InvalidEdit(["left"], "array gap is outside the valid range")),
  )
  change.validate_edit(stored, initial, types.ArrayRemove(["left"], 0, 3))
  |> expect.to_equal(
    Error(types.InvalidEdit(["left"], "array range is outside the valid range")),
  )
  change.validate_edit(
    stored,
    initial,
    types.ArrayInsert(["narrow"], 0, [types.StringValue("bad")]),
  )
  |> expect.to_equal(
    Error(types.InvalidEdit(
      ["0"],
      "node type is not allowed: com.fluidframework.leaf.string",
    )),
  )
  change.validate_edit(
    stored,
    initial,
    types.ArrayMove(["left"], 1, 2, ["left", "1"], 0),
  )
  |> expect.to_equal(
    Error(types.InvalidEdit(
      ["left"],
      "move destination is inside moved content",
    )),
  )
  change.edit_from(
    stored,
    initial,
    revision(),
    types.ArrayInsert(["right"], 0, [
      types.StringValue("A"),
      types.StringValue("B"),
    ]),
    identity_order(),
    9_007_199_254_740_991,
  )
  |> expect.to_equal(
    Error(types.CorruptData("change allocator", "identifiers are exhausted")),
  )
  forest.export_data(initial) |> expect.to_equal(Ok(before))
}

pub fn shared_tree_array_change_rejects_atomic_move_validation_failures_test() {
  let root =
    types.ObjectValue("org.watershed.shared-tree.m3.Root", [
      #("left", types.ArrayValue(items_type, [types.StringValue("A")])),
      #("right", types.ArrayValue(items_type, [])),
      #("byKey", types.MapValue("org.watershed.shared-tree.m3.ArrayMap", [])),
      #("narrow", types.ArrayValue("org.watershed.shared-tree.m3.Points", [])),
    ])
  let stored = array_fixture.stored("objectArrays")
  let assert Ok(initial) =
    forest.new(array_fixture.view_id(), stored, Some(root))
  let assert Ok(before) = forest.export_data(initial)
  let assert Ok(unsafe) = int.parse("9007199254740992")

  change.edit(
    stored,
    initial,
    revision(),
    types.ArrayMove(["left"], unsafe, unsafe, ["right"], 0),
    identity_order(),
  )
  |> expect.to_equal(
    Error(types.InvalidEdit(["left"], "array range is outside the valid range")),
  )
  forest.export_data(initial) |> expect.to_equal(Ok(before))

  change.edit(
    stored,
    initial,
    revision(),
    types.ArrayMove(["left"], 0, 1, ["right"], 1),
    identity_order(),
  )
  |> expect.to_equal(
    Error(types.InvalidEdit(["right"], "array gap is outside the valid range")),
  )
  forest.export_data(initial) |> expect.to_equal(Ok(before))

  change.edit(
    stored,
    initial,
    revision(),
    types.ArrayMove(["left"], 0, 1, ["narrow"], 0),
    identity_order(),
  )
  |> expect.to_equal(
    Error(types.InvalidEdit(
      ["0"],
      "node type is not allowed: com.fluidframework.leaf.string",
    )),
  )
  forest.export_data(initial) |> expect.to_equal(Ok(before))
}

pub fn shared_tree_array_change_uses_contextual_numeric_map_keys_test() {
  let root =
    types.ObjectValue("org.watershed.shared-tree.m3.Root", [
      #("left", types.ArrayValue(items_type, [])),
      #("right", types.ArrayValue(items_type, [])),
      #(
        "byKey",
        types.MapValue("org.watershed.shared-tree.m3.ArrayMap", [
          #("0", types.ArrayValue(items_type, [types.StringValue("zero")])),
        ]),
      ),
      #("narrow", types.ArrayValue("org.watershed.shared-tree.m3.Points", [])),
    ])
  let assert Ok(changed) =
    apply_edit(
      "objectArrays",
      root,
      types.ArrayInsert(["byKey", "0"], 1, [types.StringValue("after")]),
    )
  forest.array_values(changed, ["byKey", "0"])
  |> expect.to_equal(
    Ok([types.StringValue("zero"), types.StringValue("after")]),
  )
}

pub fn shared_tree_array_change_accepts_empty_edits_after_validation_test() {
  let root =
    types.ArrayValue(items_type, [
      types.StringValue("A"),
      types.StringValue("B"),
    ])
  let assert Ok(inserted) =
    apply_edit("rootArray", root, types.ArrayInsert([], 2, []))
  forest.array_values(inserted, [])
  |> expect.to_equal(Ok([types.StringValue("A"), types.StringValue("B")]))
  let assert Ok(removed) =
    apply_edit("rootArray", root, types.ArrayRemove([], 1, 1))
  forest.array_values(removed, [])
  |> expect.to_equal(Ok([types.StringValue("A"), types.StringValue("B")]))
  let assert Ok(moved) =
    apply_edit("rootArray", root, types.ArrayMove([], 1, 1, [], 0))
  forest.array_values(moved, [])
  |> expect.to_equal(Ok([types.StringValue("A"), types.StringValue("B")]))
}

pub fn shared_tree_array_change_accepts_compatible_distinct_array_types_test() {
  let point =
    types.ObjectValue(point_type, [
      #("label", types.StringValue("point")),
      #("x", types.NumberValue(1.0)),
    ])
  let root =
    types.ObjectValue("org.watershed.shared-tree.m3.Root", [
      #("left", types.ArrayValue(items_type, [point])),
      #("right", types.ArrayValue(items_type, [])),
      #("byKey", types.MapValue("org.watershed.shared-tree.m3.ArrayMap", [])),
      #("narrow", types.ArrayValue("org.watershed.shared-tree.m3.Points", [])),
    ])
  let assert Ok(moved) =
    apply_edit(
      "objectArrays",
      root,
      types.ArrayMove(["left"], 0, 1, ["narrow"], 0),
    )
  forest.array_values(moved, ["left"]) |> expect.to_equal(Ok([]))
  forest.array_values(moved, ["narrow"]) |> expect.to_equal(Ok([point]))
}

pub fn shared_tree_array_change_rejects_scalar_slot_assignment_test() {
  let root =
    types.ArrayValue(items_type, [
      types.StringValue("A"),
      types.StringValue("B"),
    ])
  let stored = array_fixture.stored("rootArray")
  let assert Ok(initial) =
    forest.new(array_fixture.view_id(), stored, Some(root))
  change.validate_edit(
    stored,
    initial,
    types.SetField(["1"], types.StringValue("replacement")),
  )
  |> expect.to_equal(
    Error(types.InvalidEdit(["1"], "array slots cannot be assigned")),
  )
}

pub fn shared_tree_array_change_merges_sibling_array_paths_test() {
  let root =
    types.ArrayValue(items_type, [
      types.ArrayValue(items_type, [types.StringValue("A")]),
      types.ArrayValue(items_type, [types.StringValue("B")]),
      types.ArrayValue(items_type, [types.StringValue("C")]),
    ])
  let assert Ok(moved) =
    apply_edit("rootArray", root, types.ArrayMove(["0"], 0, 1, ["2"], 1))
  forest.array_values(moved, ["0"]) |> expect.to_equal(Ok([]))
  forest.array_values(moved, ["1"])
  |> expect.to_equal(Ok([types.StringValue("B")]))
  forest.array_values(moved, ["2"])
  |> expect.to_equal(Ok([types.StringValue("C"), types.StringValue("A")]))
}

pub fn shared_tree_array_change_moves_between_ancestor_and_child_arrays_test() {
  let nested =
    types.ArrayValue(items_type, [
      types.ArrayValue(items_type, [types.StringValue("A")]),
      types.ArrayValue(items_type, [types.StringValue("B")]),
    ])
  let assert Ok(to_ancestor) =
    apply_edit("rootArray", nested, types.ArrayMove(["0"], 0, 1, [], 2))
  forest.array_values(to_ancestor, [])
  |> expect.to_equal(
    Ok([
      types.ArrayValue(items_type, []),
      types.ArrayValue(items_type, [types.StringValue("B")]),
      types.StringValue("A"),
    ]),
  )

  let assert Ok(to_child) =
    apply_edit("rootArray", nested, types.ArrayMove([], 0, 1, ["1"], 1))
  forest.array_values(to_child, [])
  |> expect.to_equal(
    Ok([
      types.ArrayValue(items_type, [
        types.StringValue("B"),
        types.ArrayValue(items_type, [types.StringValue("A")]),
      ]),
    ]),
  )
}

fn object_arrays_root() -> types.TreeValue {
  let point = fn(label, x) {
    types.ObjectValue(point_type, [
      #("label", types.StringValue(label)),
      #("x", types.NumberValue(x)),
    ])
  }
  types.ObjectValue("org.watershed.shared-tree.m3.Root", [
    #("left", types.ArrayValue(items_type, [point("left", 1.0)])),
    #("right", types.ArrayValue(items_type, [point("right", 2.0)])),
    #("byKey", types.MapValue("org.watershed.shared-tree.m3.ArrayMap", [])),
    #("narrow", types.ArrayValue("org.watershed.shared-tree.m3.Points", [])),
  ])
}

pub fn shared_tree_array_compose_schedules_untouched_move_destination_test() {
  let stored = array_fixture.stored("objectArrays")
  let assert Ok(initial) =
    forest.new(array_fixture.view_id(), stored, Some(object_arrays_root()))
  let assert Ok(moved) =
    change.edit(
      stored,
      initial,
      revision(),
      types.ArrayMove(["left"], 0, 1, ["right"], 0),
      identity_order(),
    )
  let assert Ok(move_delta) =
    change.into_delta(change.TaggedChange(Some(revision()), None, moved))
  let assert Ok(after_move) = forest.apply_delta(initial, move_delta)
  forest.array_values(after_move, ["left"]) |> expect.to_equal(Ok([]))
  forest.array_values(after_move, ["right"])
  |> expect.to_equal(
    Ok([
      types.ObjectValue(point_type, [
        #("label", types.StringValue("left")),
        #("x", types.NumberValue(1.0)),
      ]),
      types.ObjectValue(point_type, [
        #("label", types.StringValue("right")),
        #("x", types.NumberValue(2.0)),
      ]),
    ]),
  )
  let assert Ok(edited) =
    change.edit(
      stored,
      after_move,
      revision_b(),
      types.SetField(["right", "0", "x"], types.NumberValue(9.0)),
      identity_order(),
    )
  let assert Ok(edited_delta) =
    change.into_delta(change.TaggedChange(Some(revision_b()), None, edited))
  let assert Ok(after_edit) = forest.apply_delta(after_move, edited_delta)
  forest.read(after_edit, ["right", "0", "x"])
  |> expect.to_equal(Ok(Some(types.NumberValue(9.0))))
  let composed =
    change.compose([
      change.TaggedChange(Some(revision()), None, moved),
      change.TaggedChange(Some(revision_b()), None, edited),
    ])
  let assert Ok(composed) = composed
  let assert Ok(delta) =
    change.into_delta(change.TaggedChange(None, None, composed))
  let assert Ok(updated) = forest.apply_delta(initial, delta)
  forest.read(updated, ["right", "0", "x"])
  |> expect.to_equal(Ok(Some(types.NumberValue(9.0))))
}

pub fn shared_tree_array_rebase_schedules_untouched_move_destination_test() {
  let stored = array_fixture.stored("objectArrays")
  let assert Ok(initial) =
    forest.new(array_fixture.view_id(), stored, Some(object_arrays_root()))
  let assert Ok(moved) =
    change.edit(
      stored,
      initial,
      revision(),
      types.ArrayMove(["left"], 0, 1, ["right"], 0),
      identity_order(),
    )
  let assert Ok(edited) =
    change.edit(
      stored,
      initial,
      revision_b(),
      types.SetField(["left", "0", "x"], types.NumberValue(9.0)),
      identity_order(),
    )
  let assert Ok(context) =
    change.rebase_context([
      change.RevisionInfo(revision(), None),
      change.RevisionInfo(revision_b(), None),
    ])
  let rebased =
    change.rebase(
      change.TaggedChange(Some(revision_b()), None, edited),
      change.TaggedChange(Some(revision()), None, moved),
      context,
    )
  let assert Ok(rebased) = rebased
  let assert Ok(move_delta) =
    change.into_delta(change.TaggedChange(Some(revision()), None, moved))
  let assert Ok(after_move) = forest.apply_delta(initial, move_delta)
  forest.array_values(after_move, ["left"]) |> expect.to_equal(Ok([]))
  forest.array_values(after_move, ["right"])
  |> expect.to_equal(
    Ok([
      types.ObjectValue(point_type, [
        #("label", types.StringValue("left")),
        #("x", types.NumberValue(1.0)),
      ]),
      types.ObjectValue(point_type, [
        #("label", types.StringValue("right")),
        #("x", types.NumberValue(2.0)),
      ]),
    ]),
  )
  let assert Ok(rebased_delta) =
    change.into_delta(change.TaggedChange(Some(revision_b()), None, rebased))
  let assert Ok(updated) = forest.apply_delta(after_move, rebased_delta)
  forest.read(updated, ["right", "0", "x"])
  |> expect.to_equal(Ok(Some(types.NumberValue(9.0))))
}

pub fn shared_tree_array_ownership_survives_roundtrip_and_singleton_compose_test() {
  let stored = array_fixture.stored("objectArrays")
  let point = fn(label, x) {
    types.ObjectValue(point_type, [
      #("label", types.StringValue(label)),
      #("x", types.NumberValue(x)),
    ])
  }
  let root =
    types.ObjectValue("org.watershed.shared-tree.m3.Root", [
      #(
        "left",
        types.ArrayValue(items_type, [point("first", 1.0), point("second", 2.0)]),
      ),
      #("right", types.ArrayValue(items_type, [])),
      #("byKey", types.MapValue("org.watershed.shared-tree.m3.ArrayMap", [])),
      #("narrow", types.ArrayValue("org.watershed.shared-tree.m3.Points", [])),
    ])
  let assert Ok(initial) =
    forest.new(array_fixture.view_id(), stored, Some(root))
  let assert Ok(authored) =
    change.edit(
      stored,
      initial,
      revision(),
      types.ArrayMove(["left"], 0, 2, ["right"], 0),
      identity_order(),
    )
  let original = change.cross_field_keys(authored)
  original
  |> result.map(fn(keys) { list.map(keys, fn(key) { key.count }) })
  |> expect.to_equal(Ok([2, 2]))
  change.to_data(authored).cross_field_keys
  |> expect.to_equal(result.unwrap(original, []))
  let assert Ok(roundtripped) =
    change.from_data(change.to_data(authored), identity_order())
  change.cross_field_keys(roundtripped) |> expect.to_equal(original)
  let assert Ok(composed) =
    change.compose([
      change.TaggedChange(Some(revision()), None, authored),
    ])
  change.cross_field_keys(composed) |> expect.to_equal(original)
}

pub fn shared_tree_array_ownership_only_revisions_survive_identity_rebind_test() {
  let assert Ok(empty_sequence) = sequence_field.from_marks([])
  let data =
    change.ChangeData(
      max_local_id: 1,
      revisions: [],
      fields: [#("root", change.SequenceField(empty_sequence))],
      nodes: [],
      parents: [],
      aliases: [],
      builds: [],
      destroys: [],
      refreshers: [],
      cross_field_keys: [
        change.CrossFieldKey(
          moves.Key(moves.Source, Some(revision()), 0),
          1,
          moves.FieldId(None, "root"),
        ),
        change.CrossFieldKey(
          moves.Key(moves.Destination, Some(revision_b()), 0),
          1,
          moves.FieldId(None, "root"),
        ),
      ],
    )
  let assert Ok(authored) = change.from_data(data, identity_order())
  change.rebind_identity_order(authored, identity_order(), [])
  |> expect.to_equal(Ok(authored))
}

pub fn shared_tree_array_compose_runs_move_chain_to_fixed_point_test() {
  let stored = array_fixture.stored("objectArrays")
  let assert Ok(initial) =
    forest.new(array_fixture.view_id(), stored, Some(object_arrays_root()))
  let assert Ok(first) =
    change.edit(
      stored,
      initial,
      revision(),
      types.ArrayMove(["left"], 0, 1, ["right"], 0),
      identity_order(),
    )
  let assert Ok(first_delta) =
    change.into_delta(change.TaggedChange(Some(revision()), None, first))
  let assert Ok(after_first) = forest.apply_delta(initial, first_delta)
  let assert Ok(second) =
    change.edit(
      stored,
      after_first,
      revision_b(),
      types.ArrayMove(["right"], 0, 1, ["narrow"], 0),
      identity_order(),
    )
  let assert Ok(#(composed, trace)) =
    change.compose_with_trace([
      change.TaggedChange(Some(revision()), None, first),
      change.TaggedChange(Some(revision_b()), None, second),
    ])
  trace
  |> list.filter_map(fn(event) {
    case event {
      moves.HandlerCalled("compose", field) -> Ok(field)
      _ -> Error(Nil)
    }
  })
  |> expect.to_equal([
    moves.FieldId(Some(types.AtomId(Some(revision()), 3)), ""),
    moves.FieldId(Some(types.AtomId(Some(revision()), 2)), ""),
    moves.FieldId(Some(types.AtomId(Some(revision_b()), 3)), ""),
  ])
  let assert Ok(delta) =
    change.into_delta(change.TaggedChange(None, None, composed))
  let assert Ok(updated) = forest.apply_delta(initial, delta)
  forest.array_values(updated, ["left"]) |> expect.to_equal(Ok([]))
  forest.array_values(updated, ["right"])
  |> expect.to_equal(
    Ok([
      types.ObjectValue(point_type, [
        #("label", types.StringValue("right")),
        #("x", types.NumberValue(2.0)),
      ]),
    ]),
  )
  forest.read(updated, ["narrow", "0", "label"])
  |> expect.to_equal(Ok(Some(types.StringValue("left"))))
}

pub fn shared_tree_array_retry_reserves_multi_revision_inverse_ids_test() {
  let move_in = fn(move_id, cell_id) {
    sequence_field.Mark(
      2,
      Some(cell_id),
      sequence_field.Attach(sequence_field.MoveIn(move_id, None)),
      None,
    )
  }
  let move_out = fn(move_id) {
    sequence_field.Mark(
      2,
      None,
      sequence_field.Detach(sequence_field.MoveOut(move_id, None, None)),
      None,
    )
  }
  let assert Ok(first_right) =
    sequence_field.from_marks([
      move_in(
        types.AtomId(Some(revision()), 40),
        types.AtomId(Some(revision()), 42),
      ),
    ])
  let assert Ok(first_left) =
    sequence_field.from_marks([
      move_out(types.AtomId(Some(revision()), 40)),
    ])
  let pivot = fn(local_id) {
    let id = types.AtomId(Some(revision_b()), local_id)
    let assert Ok(change) =
      sequence_field.from_marks([
        move_in(id, types.AtomId(Some(revision_b()), local_id + 2)),
        sequence_field.Mark(1, None, sequence_field.Noop, None),
        move_out(id),
      ])
    change
  }
  let first_data =
    change.ChangeData(
      max_local_id: 42,
      revisions: [change.RevisionInfo(revision(), None)],
      fields: [
        #("right", change.SequenceField(first_right)),
        #("left", change.SequenceField(first_left)),
      ],
      nodes: [],
      parents: [],
      aliases: [],
      builds: [],
      destroys: [],
      refreshers: [],
      cross_field_keys: [
        change.CrossFieldKey(
          moves.Key(moves.Source, Some(revision()), 40),
          2,
          moves.FieldId(None, "left"),
        ),
        change.CrossFieldKey(
          moves.Key(moves.Destination, Some(revision()), 40),
          2,
          moves.FieldId(None, "right"),
        ),
      ],
    )
  let second_data =
    change.ChangeData(
      max_local_id: 46,
      revisions: [change.RevisionInfo(revision_b(), None)],
      fields: [
        #("right", change.SequenceField(pivot(40))),
        #("left", change.SequenceField(pivot(44))),
      ],
      nodes: [],
      parents: [],
      aliases: [],
      builds: [],
      destroys: [],
      refreshers: [],
      cross_field_keys: [
        change.CrossFieldKey(
          moves.Key(moves.Source, Some(revision_b()), 40),
          2,
          moves.FieldId(None, "right"),
        ),
        change.CrossFieldKey(
          moves.Key(moves.Source, Some(revision_b()), 44),
          2,
          moves.FieldId(None, "left"),
        ),
        change.CrossFieldKey(
          moves.Key(moves.Destination, Some(revision_b()), 40),
          2,
          moves.FieldId(None, "right"),
        ),
        change.CrossFieldKey(
          moves.Key(moves.Destination, Some(revision_b()), 44),
          2,
          moves.FieldId(None, "left"),
        ),
      ],
    )
  let assert Ok(first) = change.from_data(first_data, identity_order())
  let assert Ok(second) = change.from_data(second_data, identity_order())
  let assert Ok(#(composed, trace)) =
    change.compose_with_trace([
      change.TaggedChange(Some(revision()), None, first),
      change.TaggedChange(Some(revision_b()), None, second),
    ])
  trace
  |> list.filter_map(fn(event) {
    case event {
      moves.HandlerCalled("compose", field) -> Ok(field.field)
      _ -> Error(Nil)
    }
  })
  |> expect.to_equal(["right", "left", "right"])
  let right = moves.FieldId(None, "right")
  let absent =
    moves.RangeRead(
      right,
      moves.Key(moves.Destination, Some(revision_b()), 40),
      2,
      True,
      False,
      2,
    )
  let write =
    moves.RangeWritten(
      right,
      moves.Key(moves.Destination, Some(revision_b()), 40),
      1,
      True,
    )
  let found =
    moves.RangeRead(
      right,
      moves.Key(moves.Destination, Some(revision_b()), 40),
      2,
      True,
      True,
      1,
    )
  let assert Ok(absent_index) = event_index(trace, absent, 0)
  let assert Ok(write_index) = event_index(trace, write, 0)
  let assert Ok(found_index) = event_index(trace, found, 0)
  let ordered = absent_index < write_index && write_index < found_index
  ordered |> expect.to_be_true
  list.contains(trace, moves.DependenciesInvalidated(right))
  |> expect.to_be_true
  let assert Ok(inverse_revision) =
    fluid_ids.stable_id("20000000-0000-4000-8000-000000000003")
  let assert Ok(inverse_order) =
    change.identity_order([
      #(revision(), 0),
      #(revision_b(), 1),
      #(inverse_revision, 2),
    ])
  let assert Ok(composed) = change.with_identity_order(composed, inverse_order)
  let assert Ok(inverted) =
    change.invert(
      change.TaggedChange(None, None, composed),
      False,
      inverse_revision,
    )
  change.to_data(inverted).max_local_id |> expect.to_equal(93)

  let root =
    types.ObjectValue("org.watershed.shared-tree.m3.Root", [
      #(
        "left",
        types.ArrayValue(items_type, [
          types.StringValue("A"),
          types.StringValue("B"),
          types.StringValue("C"),
          types.StringValue("D"),
          types.StringValue("E"),
        ]),
      ),
      #(
        "right",
        types.ArrayValue(items_type, [
          types.StringValue("F"),
          types.StringValue("G"),
          types.StringValue("H"),
        ]),
      ),
      #("byKey", types.MapValue("org.watershed.shared-tree.m3.ArrayMap", [])),
      #("narrow", types.ArrayValue("org.watershed.shared-tree.m3.Points", [])),
    ])
  let assert Ok(initial) =
    forest.new(
      array_fixture.view_id(),
      array_fixture.stored("objectArrays"),
      Some(root),
    )
  let stored = array_fixture.stored("objectArrays")
  let assert Ok(first_authored) =
    change.edit(
      stored,
      initial,
      revision(),
      types.ArrayMove(["left"], 0, 2, ["right"], 0),
      inverse_order,
    )
  let assert Ok(first_delta) =
    change.into_delta(change.TaggedChange(
      Some(revision()),
      None,
      first_authored,
    ))
  let assert Ok(after_first) = forest.apply_delta(initial, first_delta)
  forest.array_values(after_first, ["left"])
  |> expect.to_equal(
    Ok([
      types.StringValue("C"),
      types.StringValue("D"),
      types.StringValue("E"),
    ]),
  )
  forest.array_values(after_first, ["right"])
  |> expect.to_equal(
    Ok([
      types.StringValue("A"),
      types.StringValue("B"),
      types.StringValue("F"),
      types.StringValue("G"),
      types.StringValue("H"),
    ]),
  )
  let assert Ok(second_authored) =
    change.edit(
      stored,
      after_first,
      revision_b(),
      types.ArrayMove(["right"], 1, 3, ["left"], 1),
      inverse_order,
    )
  let assert Ok(second_delta) =
    change.into_delta(change.TaggedChange(
      Some(revision_b()),
      None,
      second_authored,
    ))
  let assert Ok(after_second) = forest.apply_delta(after_first, second_delta)
  forest.array_values(after_second, ["left"])
  |> expect.to_equal(
    Ok([
      types.StringValue("C"),
      types.StringValue("B"),
      types.StringValue("F"),
      types.StringValue("D"),
      types.StringValue("E"),
    ]),
  )
  forest.array_values(after_second, ["right"])
  |> expect.to_equal(
    Ok([
      types.StringValue("A"),
      types.StringValue("G"),
      types.StringValue("H"),
    ]),
  )
  let assert Ok(#(authored_composed, authored_trace)) =
    change.compose_with_trace([
      change.TaggedChange(Some(revision()), None, first_authored),
      change.TaggedChange(Some(revision_b()), None, second_authored),
    ])
  authored_trace
  |> list.filter_map(fn(event) {
    case event {
      moves.HandlerCalled("compose", field) -> Ok(field)
      _ -> Error(Nil)
    }
  })
  |> expect.to_equal([
    moves.FieldId(Some(types.AtomId(Some(revision()), 4)), ""),
    moves.FieldId(Some(types.AtomId(Some(revision()), 5)), ""),
    moves.FieldId(Some(types.AtomId(Some(revision_b()), 5)), ""),
    moves.FieldId(Some(types.AtomId(Some(revision()), 4)), ""),
  ])
  let assert Ok(composed_delta) =
    change.into_delta(change.TaggedChange(None, None, authored_composed))
  let assert Ok(updated) = forest.apply_delta(initial, composed_delta)
  forest.visible_root(updated)
  |> expect.to_equal(forest.visible_root(after_second))
  let assert Ok(authored_composed) =
    change.with_identity_order(authored_composed, inverse_order)
  let assert Ok(authored_inverse) =
    change.invert(
      change.TaggedChange(None, None, authored_composed),
      False,
      inverse_revision,
    )
  let assert Ok(inverted_delta) =
    change.into_delta(change.TaggedChange(
      Some(inverse_revision),
      None,
      authored_inverse,
    ))
  let assert Ok(restored) = forest.apply_delta(updated, inverted_delta)
  forest.visible_root(restored) |> expect.to_equal(Ok(Some(root)))
}

fn event_index(
  events: List(moves.TraceEvent),
  expected: moves.TraceEvent,
  index: Int,
) -> Result(Int, Nil) {
  case events {
    [] -> Error(Nil)
    [event, ..rest] ->
      case event == expected {
        True -> Ok(index)
        False -> event_index(rest, expected, index + 1)
      }
  }
}

pub fn shared_tree_array_change_preserves_duplicate_descendant_identity_test() {
  let point =
    types.ObjectValue(point_type, [
      #("label", types.StringValue("same")),
      #("x", types.NumberValue(1.0)),
    ])
  let root = types.ArrayValue(items_type, [point, point])
  let stored = array_fixture.stored("rootArray")
  let assert Ok(initial) =
    forest.new(array_fixture.view_id(), stored, Some(root))
  let assert Ok(first) = forest.locate(initial, ["0"])
  let assert Ok(second) = forest.locate(initial, ["1"])
  let assert Ok(first_label) = forest.locate(initial, ["0", "label"])
  let assert Ok(second_label) = forest.locate(initial, ["1", "label"])
  let assert Ok(authored) =
    change.edit(
      stored,
      initial,
      revision(),
      types.ArrayMove([], 1, 2, [], 0),
      identity_order(),
    )
  let assert Ok(delta) =
    change.into_delta(change.TaggedChange(Some(revision()), None, authored))
  let assert Ok(updated) = forest.apply_delta(initial, delta)
  forest.locate(updated, ["0"]) |> expect.to_equal(Ok(second))
  forest.locate(updated, ["1"]) |> expect.to_equal(Ok(first))
  forest.locate(updated, ["0", "label"]) |> expect.to_equal(Ok(second_label))
  forest.locate(updated, ["1", "label"]) |> expect.to_equal(Ok(first_label))
  let assert Ok(edited) =
    change.edit(
      stored,
      updated,
      revision_b(),
      types.SetField(["0", "x"], types.NumberValue(9.0)),
      identity_order(),
    )
  let assert Ok(edited_delta) =
    change.into_delta(change.TaggedChange(Some(revision_b()), None, edited))
  let assert Ok(edited) = forest.apply_delta(updated, edited_delta)
  forest.locate(edited, ["0"]) |> expect.to_equal(Ok(second))
  forest.locate(edited, ["1"]) |> expect.to_equal(Ok(first))
  forest.locate(edited, ["0", "label"])
  |> expect.to_equal(Ok(second_label))
  forest.locate(edited, ["1", "label"])
  |> expect.to_equal(Ok(first_label))
  forest.read(edited, ["0", "x"])
  |> expect.to_equal(Ok(Some(types.NumberValue(9.0))))
}

pub fn shared_tree_array_change_keeps_map_mutation_scoped_to_selected_item_test() {
  let map_type = "org.watershed.shared-tree.m3.ArrayMap"
  let root =
    types.ArrayValue(items_type, [
      types.MapValue(map_type, [#("existing", types.StringValue("first"))]),
      types.MapValue(map_type, [#("existing", types.StringValue("second"))]),
    ])
  let assert Ok(updated) =
    apply_edit(
      "rootArray",
      root,
      types.MapSet(["1"], "added", types.StringValue("value")),
    )
  forest.read(updated, ["0", "added"]) |> expect.to_equal(Ok(None))
  forest.read(updated, ["1", "added"])
  |> expect.to_equal(Ok(Some(types.StringValue("value"))))
}

pub fn shared_tree_array_change_keeps_map_and_field_mutators_separate_test() {
  let root =
    types.ObjectValue("org.watershed.shared-tree.m3.Root", [
      #(
        "left",
        types.ArrayValue(items_type, [
          types.ObjectValue(point_type, [
            #("label", types.StringValue("point")),
            #("x", types.NumberValue(1.0)),
          ]),
        ]),
      ),
      #("right", types.ArrayValue(items_type, [])),
      #(
        "byKey",
        types.MapValue("org.watershed.shared-tree.m3.ArrayMap", [
          #("0", types.ArrayValue(items_type, [types.StringValue("numeric")])),
        ]),
      ),
      #("narrow", types.ArrayValue("org.watershed.shared-tree.m3.Points", [])),
    ])
  let stored = array_fixture.stored("objectArrays")
  let assert Ok(initial) =
    forest.new(array_fixture.view_id(), stored, Some(root))
  let assert Ok(with_empty_key) =
    apply_edit(
      "objectArrays",
      root,
      types.MapSet(
        ["byKey"],
        "",
        types.ArrayValue(items_type, [types.StringValue("empty")]),
      ),
    )
  forest.array_values(with_empty_key, ["byKey", ""])
  |> expect.to_equal(Ok([types.StringValue("empty")]))
  let assert Ok(without_numeric_key) =
    apply_edit("objectArrays", root, types.MapDelete(["byKey"], "0"))
  forest.read(without_numeric_key, ["byKey", "0"]) |> expect.to_equal(Ok(None))

  change.validate_edit(
    stored,
    initial,
    types.SetField(
      ["byKey", "0"],
      types.ArrayValue(items_type, [types.StringValue("replacement")]),
    ),
  )
  |> expect.to_equal(
    Error(types.InvalidEdit(["byKey", "0"], "map entries require a map edit")),
  )
  change.validate_edit(stored, initial, types.ClearField(["byKey", ""]))
  |> expect.to_equal(
    Error(types.InvalidEdit(["byKey", ""], "map entries require a map edit")),
  )
  change.validate_edit(
    stored,
    initial,
    types.MapSet([], "field", types.StringValue("bad")),
  )
  |> expect.to_equal(Error(types.InvalidEdit([], "node is not a map")))
  change.validate_edit(stored, initial, types.MapDelete(["left", "0"], "field"))
  |> expect.to_equal(
    Error(types.InvalidEdit(["left", "0"], "node is not a map")),
  )
}
