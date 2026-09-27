import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import startest/expect
import watershed/fluid_ids
import watershed/tree/array_fixture
import watershed/tree/array_forest_fixture
import watershed/tree/fixtures
import watershed/tree/forest
import watershed/tree/types

const items_type = "org.watershed.shared-tree.m3.Items"

pub fn shared_tree_array_counted_delta_matches_upstream_test() {
  fixtures.assert_case("array-forest-delta", array_forest_fixture.run)
}

fn point(x: Float) -> types.TreeValue {
  types.ObjectValue("org.watershed.shared-tree.m3.Point", [
    #("label", types.StringValue("same")),
    #("x", types.NumberValue(x)),
  ])
}

fn array_root(
  left: List(types.TreeValue),
  right: List(types.TreeValue),
) -> types.TreeValue {
  types.ObjectValue("org.watershed.shared-tree.m3.Root", [
    #("left", types.ArrayValue(items_type, left)),
    #("right", types.ArrayValue(items_type, right)),
    #("byKey", types.MapValue("org.watershed.shared-tree.m3.ArrayMap", [])),
    #("narrow", types.ArrayValue("org.watershed.shared-tree.m3.Points", [])),
  ])
}

fn atom(local_id: Int) -> types.AtomId {
  types.AtomId(None, local_id)
}

fn empty_delta() -> forest.DeltaData {
  forest.DeltaData(None, [], [], [], [], [], [])
}

fn replace_field(
  key: String,
  source: types.AtomId,
  removed: types.AtomId,
) -> #(String, forest.FieldDelta) {
  #(
    key,
    forest.FieldDelta([
      forest.Mark(1, Some(source), Some(removed), []),
    ]),
  )
}

fn root_array_delta(
  marks: List(forest.Mark),
) -> List(#(String, forest.FieldDelta)) {
  [
    #(
      "rootFieldKey",
      forest.FieldDelta([
        forest.Mark(1, None, None, [
          #("", forest.FieldDelta(marks)),
        ]),
      ]),
    ),
  ]
}

pub fn shared_tree_array_forest_moves_counted_duplicate_objects_by_identity_test() {
  let first = point(1.0)
  let second = point(1.0)
  let assert Ok(initial) =
    forest.new(
      array_fixture.view_id(),
      array_fixture.stored("objectArrays"),
      Some(array_root([point(0.0), first, second], [])),
    )
  let assert Ok(first_reference) = forest.locate(initial, ["left", "1"])
  let assert Ok(second_reference) = forest.locate(initial, ["left", "2"])
  let move = case
    forest.delta(
      forest.DeltaData(..empty_delta(), fields: [
        #(
          "rootFieldKey",
          forest.FieldDelta([
            forest.Mark(1, None, None, [
              #(
                "right",
                forest.FieldDelta([
                  forest.Mark(1, None, None, [
                    #(
                      "",
                      forest.FieldDelta([
                        forest.Mark(2, Some(atom(10)), None, []),
                      ]),
                    ),
                  ]),
                ]),
              ),
              #(
                "left",
                forest.FieldDelta([
                  forest.Mark(1, None, None, [
                    #(
                      "",
                      forest.FieldDelta([
                        forest.Mark(1, None, None, []),
                        forest.Mark(2, None, Some(atom(10)), []),
                      ]),
                    ),
                  ]),
                ]),
              ),
            ]),
          ]),
        ),
      ]),
    )
  {
    Ok(move) -> move
    Error(error) -> panic as { "move delta: " <> string.inspect(error) }
  }
  let moved = case forest.apply_delta(initial, move) {
    Ok(moved) -> moved
    Error(error) -> panic as { "move apply: " <> string.inspect(error) }
  }
  forest.locate(moved, ["right", "0"])
  |> expect.to_equal(Ok(first_reference))
  forest.locate(moved, ["right", "1"])
  |> expect.to_equal(Ok(second_reference))
  forest.array_values(moved, ["left"]) |> expect.to_equal(Ok([point(0.0)]))
  forest.array_values(moved, ["right"])
  |> expect.to_equal(Ok([first, second]))

  let change_second = case
    forest.delta(
      forest.DeltaData(
        ..empty_delta(),
        build: [forest.Build(atom(20), [types.NumberValue(42.0)])],
        fields: [
          #(
            "rootFieldKey",
            forest.FieldDelta([
              forest.Mark(1, None, None, [
                #(
                  "right",
                  forest.FieldDelta([
                    forest.Mark(1, None, None, [
                      #(
                        "",
                        forest.FieldDelta([
                          forest.Mark(1, None, None, []),
                          forest.Mark(1, None, None, [
                            replace_field("x", atom(20), atom(21)),
                          ]),
                        ]),
                      ),
                    ]),
                  ]),
                ),
              ]),
            ]),
          ),
        ],
      ),
    )
  {
    Ok(change) -> change
    Error(error) -> panic as { "child delta: " <> string.inspect(error) }
  }
  let changed = case forest.apply_delta(moved, change_second) {
    Ok(changed) -> changed
    Error(error) -> panic as { "child apply: " <> string.inspect(error) }
  }
  forest.read_node(changed, first_reference) |> expect.to_equal(Ok(first))
  forest.read_node(changed, second_reference)
  |> expect.to_equal(Ok(point(42.0)))
}

pub fn shared_tree_array_forest_rejects_overlapping_counted_owners_test() {
  let attach =
    forest.DeltaData(
      ..empty_delta(),
      fields: root_array_delta([
        forest.Mark(2, Some(atom(0)), None, []),
        forest.Mark(2, Some(atom(1)), None, []),
      ]),
    )
  let detach =
    forest.DeltaData(
      ..empty_delta(),
      fields: root_array_delta([
        forest.Mark(2, None, Some(atom(0)), []),
        forest.Mark(2, None, Some(atom(1)), []),
      ]),
    )
  let build =
    forest.DeltaData(..empty_delta(), build: [
      forest.Build(atom(0), [
        types.StringValue("A"),
        types.StringValue("B"),
      ]),
      forest.Build(atom(1), [
        types.StringValue("C"),
        types.StringValue("D"),
      ]),
    ])
  let rename =
    forest.DeltaData(..empty_delta(), rename: [
      forest.Rename(atom(0), atom(10), 2),
      forest.Rename(atom(1), atom(20), 2),
    ])
  let destroy =
    forest.DeltaData(..empty_delta(), destroy: [
      forest.Destroy(atom(0), 2),
      forest.Destroy(atom(1), 2),
    ])
  [attach, detach, build, rename, destroy]
  |> list.each(fn(data) {
    let assert Error(types.CorruptData(_, "overlapping identifier ranges")) =
      forest.delta(data)
    Nil
  })
}

pub fn shared_tree_array_forest_counted_rename_preserves_overlapping_chain_test() {
  let assert Ok(initial) =
    forest.new(
      array_fixture.view_id(),
      array_fixture.stored("rootArray"),
      Some(types.ArrayValue(items_type, [])),
    )
  let assert Ok(build) =
    forest.delta(
      forest.DeltaData(..empty_delta(), build: [
        forest.Build(atom(0), [
          types.StringValue("A"),
          types.StringValue("B"),
          types.StringValue("C"),
        ]),
      ]),
    )
  let assert Ok(built) = forest.apply_delta(initial, build)
  let assert Ok(first) = forest.locate_detached(built, atom(0))
  let assert Ok(second) = forest.locate_detached(built, atom(1))
  let assert Ok(third) = forest.locate_detached(built, atom(2))
  let assert Ok(rename) =
    forest.delta(
      forest.DeltaData(..empty_delta(), rename: [
        forest.Rename(atom(0), atom(1), 3),
      ]),
    )
  let assert Ok(renamed) = forest.apply_delta(built, rename)
  forest.locate_detached(renamed, atom(1)) |> expect.to_equal(Ok(first))
  forest.locate_detached(renamed, atom(2)) |> expect.to_equal(Ok(second))
  forest.locate_detached(renamed, atom(3)) |> expect.to_equal(Ok(third))
}

pub fn shared_tree_array_forest_counted_failures_are_atomic_test() {
  let root =
    types.ArrayValue(items_type, [
      types.StringValue("A"),
      types.StringValue("B"),
      types.StringValue("C"),
    ])
  let assert Ok(initial) =
    forest.new(
      array_fixture.view_id(),
      array_fixture.stored("rootArray"),
      Some(root),
    )
  let assert Ok(before) = forest.export_data(initial)
  let assert Ok(reference) = forest.locate(initial, ["1"])
  [
    forest.DeltaData(
      ..empty_delta(),
      fields: root_array_delta([
        forest.Mark(4, None, None, []),
      ]),
    ),
    forest.DeltaData(
      ..empty_delta(),
      fields: root_array_delta([
        forest.Mark(4, None, Some(atom(0)), []),
      ]),
    ),
    forest.DeltaData(
      ..empty_delta(),
      fields: root_array_delta([
        forest.Mark(2, Some(atom(100)), None, []),
      ]),
    ),
    forest.DeltaData(
      ..empty_delta(),
      build: [forest.Build(atom(20), [types.StringValue("built")])],
      fields: root_array_delta([
        forest.Mark(4, None, Some(atom(30)), []),
      ]),
    ),
  ]
  |> list.each(fn(data) {
    let assert Ok(delta) = forest.delta(data)
    forest.apply_delta(initial, delta) |> expect.to_be_error
    forest.export_data(initial) |> expect.to_equal(Ok(before))
    forest.read_node(initial, reference)
    |> expect.to_equal(Ok(types.StringValue("B")))
    forest.is_attached(initial, reference) |> expect.to_equal(Ok(True))
  })

  let assert Ok(build_gapped) =
    forest.delta(
      forest.DeltaData(..empty_delta(), build: [
        forest.Build(atom(200), [types.StringValue("first")]),
        forest.Build(atom(202), [types.StringValue("last")]),
      ]),
    )
  let assert Ok(gapped) = forest.apply_delta(initial, build_gapped)
  let assert Ok(gapped_before) = forest.export_data(gapped)
  let assert Ok(attach_gap) =
    forest.delta(
      forest.DeltaData(
        ..empty_delta(),
        fields: root_array_delta([
          forest.Mark(3, Some(atom(200)), None, []),
        ]),
      ),
    )
  forest.apply_delta(gapped, attach_gap) |> expect.to_be_error
  forest.export_data(gapped) |> expect.to_equal(Ok(gapped_before))
  forest.locate_detached(gapped, atom(200)) |> expect.to_be_ok
  forest.locate_detached(gapped, atom(202)) |> expect.to_be_ok

  let maximum = atom(9_007_199_254_740_991)
  [
    forest.DeltaData(
      ..empty_delta(),
      fields: root_array_delta([
        forest.Mark(2, Some(maximum), None, []),
      ]),
    ),
    forest.DeltaData(
      ..empty_delta(),
      fields: root_array_delta([
        forest.Mark(2, None, Some(maximum), []),
      ]),
    ),
    forest.DeltaData(
      ..empty_delta(),
      fields: root_array_delta([
        forest.Mark(2, None, None, [
          #("child", forest.FieldDelta([])),
        ]),
      ]),
    ),
  ]
  |> list.each(fn(data) { forest.delta(data) |> expect.to_be_error })
}

pub fn shared_tree_array_forest_round_trip_preserves_counted_atom_identity_test() {
  let duplicate = point(1.0)
  let assert Ok(initial) =
    forest.new(
      array_fixture.view_id(),
      array_fixture.stored("rootArray"),
      Some(types.ArrayValue(items_type, [duplicate, duplicate])),
    )
  let assert Ok(first) = forest.locate(initial, ["0"])
  let assert Ok(second) = forest.locate(initial, ["1"])
  let assert Ok(delta) =
    forest.delta(
      forest.DeltaData(
        ..empty_delta(),
        fields: root_array_delta([
          forest.Mark(2, None, Some(atom(30)), []),
        ]),
      ),
    )
  let assert Ok(detached) = forest.apply_delta(initial, delta)
  forest.locate_detached(detached, atom(30)) |> expect.to_equal(Ok(first))
  forest.locate_detached(detached, atom(31)) |> expect.to_equal(Ok(second))
  let assert Ok(data) = forest.export_data(detached)
  let assert Ok(other_view) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000099")
  let assert Ok(loaded) =
    forest.import_data(other_view, array_fixture.stored("rootArray"), data)
  forest.export_data(loaded) |> expect.to_equal(Ok(data))
  forest.read_node(loaded, first) |> expect.to_be_error
  forest.read_node(loaded, second) |> expect.to_be_error
  let assert Ok(loaded_first) = forest.locate_detached(loaded, atom(30))
  let assert Ok(loaded_second) = forest.locate_detached(loaded, atom(31))
  { loaded_first == loaded_second } |> expect.to_be_false
  forest.read_node(loaded, loaded_first) |> expect.to_equal(Ok(duplicate))
  forest.read_node(loaded, loaded_second) |> expect.to_equal(Ok(duplicate))
}

pub fn shared_tree_array_forest_reads_ordered_elements_test() -> Nil {
  let root =
    types.ArrayValue(items_type, [
      types.StringValue("B"),
      types.StringValue("A"),
      types.StringValue("B"),
    ])
  let assert Ok(state) =
    forest.new(
      array_fixture.view_id(),
      array_fixture.stored("rootArray"),
      Some(root),
    )
  forest.read(state, []) |> expect.to_equal(Ok(Some(root)))
  forest.array_get(state, [], 1)
  |> expect.to_equal(Ok(Some(types.StringValue("A"))))
  forest.read(state, ["1"])
  |> expect.to_equal(Ok(Some(types.StringValue("A"))))
  forest.array_get(state, [], 3) |> expect.to_equal(Ok(None))
  forest.read(state, ["01"]) |> expect.to_be_error
  forest.node_path(state, ["1"])
  |> expect.to_equal(
    Ok([
      forest.FieldStep("rootFieldKey", 0),
      forest.FieldStep("", 1),
    ]),
  )
}

pub fn shared_tree_array_forest_preserves_literal_map_keys_test() -> Nil {
  let root =
    types.MapValue("org.watershed.shared-tree.m3.ArrayMap", [
      #(
        "0",
        types.ArrayValue(items_type, [
          types.StringValue("zero"),
          types.ArrayValue(items_type, [types.StringValue("deep")]),
        ]),
      ),
      #("01", types.StringValue("leading-zero")),
      #("", types.ArrayValue(items_type, [types.StringValue("empty")])),
    ])
  let assert Ok(state) =
    forest.new(
      array_fixture.view_id(),
      array_fixture.stored("mapArrays"),
      Some(root),
    )
  forest.read(state, ["0", "1", "0"])
  |> expect.to_equal(Ok(Some(types.StringValue("deep"))))
  forest.read(state, ["01"])
  |> expect.to_equal(Ok(Some(types.StringValue("leading-zero"))))
  forest.read(state, ["", "0"])
  |> expect.to_equal(Ok(Some(types.StringValue("empty"))))
}

pub fn shared_tree_array_forest_rejects_invalid_indices_test() -> Nil {
  let root = types.ArrayValue(items_type, [types.StringValue("value")])
  let assert Ok(state) =
    forest.new(
      array_fixture.view_id(),
      array_fixture.stored("rootArray"),
      Some(root),
    )
  ["", "-1", "+1", "01", "1.0", " 0", "9007199254740992"]
  |> list.each(fn(segment) {
    forest.read(state, [segment]) |> expect.to_be_error
  })
  forest.array_get(state, [], -1) |> expect.to_be_error
  let assert Ok(unsafe) = int.parse("9007199254740992")
  forest.array_get(state, [], unsafe) |> expect.to_be_error
  forest.read(state, ["1"]) |> expect.to_equal(Ok(None))
  let _ = forest.read(state, ["1", "child"]) |> expect.to_be_error
  Nil
}

pub fn shared_tree_array_forest_reports_types_values_and_nested_steps_test() -> Nil {
  let root =
    types.ObjectValue("org.watershed.shared-tree.m3.Root", [
      #(
        "left",
        types.ArrayValue(items_type, [
          types.ObjectValue("org.watershed.shared-tree.m3.Point", [
            #("label", types.StringValue("point")),
            #("x", types.NumberValue(2.0)),
          ]),
        ]),
      ),
      #("right", types.ArrayValue(items_type, [])),
      #("byKey", types.MapValue("org.watershed.shared-tree.m3.ArrayMap", [])),
      #("narrow", types.ArrayValue("org.watershed.shared-tree.m3.Points", [])),
    ])
  let assert Ok(state) =
    forest.new(
      array_fixture.view_id(),
      array_fixture.stored("objectArrays"),
      Some(root),
    )
  forest.array_type(state, ["left"]) |> expect.to_equal(Ok(items_type))
  forest.array_values(state, ["left"])
  |> expect.to_equal(
    Ok([
      types.ObjectValue("org.watershed.shared-tree.m3.Point", [
        #("label", types.StringValue("point")),
        #("x", types.NumberValue(2.0)),
      ]),
    ]),
  )
  forest.node_path(state, ["left", "0", "label"])
  |> expect.to_equal(
    Ok([
      forest.FieldStep("rootFieldKey", 0),
      forest.FieldStep("left", 0),
      forest.FieldStep("", 0),
      forest.FieldStep("label", 0),
    ]),
  )
  forest.node_path(state, ["right", "0"]) |> expect.to_be_error
  let _ = forest.array_values(state, []) |> expect.to_be_error
  Nil
}
