import gleam/option.{None, Some}
import gleam/result
import startest/expect
import watershed/fluid_ids
import watershed/tree/array_change_fixture
import watershed/tree/array_fixture
import watershed/tree/change
import watershed/tree/fixtures
import watershed/tree/forest
import watershed/tree/types

const items_type = "org.watershed.shared-tree.m3.Items"

const point_type = "org.watershed.shared-tree.m3.Point"

fn revision() -> fluid_ids.StableId {
  let assert Ok(id) =
    fluid_ids.stable_id("20000000-0000-4000-8000-000000000001")
  id
}

fn identity_order() -> change.IdentityOrder {
  let assert Ok(order) = change.identity_order([#(revision(), 0)])
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
