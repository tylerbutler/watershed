import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import startest/expect
import watershed/fluid_ids
import watershed/tree/fixtures
import watershed/tree/forest
import watershed/tree/forest_fixture
import watershed/tree/schema
import watershed/tree/types

const forest_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"Point\":{\"kind\":{\"object\":{\"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]},\"y\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]}}}},\"Root\":{\"kind\":{\"object\":{\"point\":{\"kind\":\"Value\",\"types\":[\"Point\"]},\"note\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}"

fn view_a() -> fluid_ids.StableId {
  let assert Ok(id) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000001")
  id
}

fn view_b() -> fluid_ids.StableId {
  let assert Ok(id) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000002")
  id
}

fn point(x: Float, y: Float) -> types.TreeValue {
  types.ObjectValue("Point", [
    #("x", types.NumberValue(x)),
    #("y", types.NumberValue(y)),
  ])
}

fn root() -> types.TreeValue {
  types.ObjectValue("Root", [#("point", point(0.0, 0.0))])
}

fn stored_schema() -> schema.StoredSchema {
  let assert Ok(stored) = schema.stored_from_string(forest_schema)
  stored
}

pub fn shared_tree_forest_rejects_foreign_reference_test() -> Nil {
  let assert Ok(first) = forest.new(view_a(), stored_schema(), Some(root()))
  let assert Ok(second) = forest.new(view_b(), stored_schema(), Some(root()))
  let assert Ok(reference) = forest.locate(first, ["point"])
  forest.read_node(first, reference) |> expect.to_equal(Ok(point(0.0, 0.0)))
  forest.is_attached(first, reference) |> expect.to_equal(Ok(True))
  let assert Error(types.InvalidEdit(_, _)) =
    forest.read_node(second, reference)
  let assert Error(types.InvalidEdit(_, _)) =
    forest.is_attached(second, reference)
  Nil
}

pub fn shared_tree_forest_paths_distinguish_absence_test() -> Nil {
  let assert Ok(state) = forest.new(view_a(), stored_schema(), Some(root()))
  forest.read(state, []) |> expect.to_equal(Ok(Some(root())))
  forest.read(state, ["note"]) |> expect.to_equal(Ok(None))
  forest.read(state, ["point", "x"])
  |> expect.to_equal(Ok(Some(types.NumberValue(0.0))))
  [
    ["unknown"],
    ["note", "child"],
    ["point", "unknown"],
    ["point", "x", "child"],
  ]
  |> list.each(fn(path) {
    let assert Error(types.InvalidEdit(actual, _)) = forest.read(state, path)
    actual |> expect.to_equal(path)
  })
  let assert Error(types.InvalidEdit(_, _)) = forest.locate(state, ["note"])
  let assert Ok(reference) = forest.locate(state, ["point", "y"])
  forest.read_node(state, reference)
  |> expect.to_equal(Ok(types.NumberValue(0.0)))
}

pub fn shared_tree_forest_validates_root_presence_and_content_test() -> Nil {
  [None, Some(types.NullValue), Some(types.ObjectValue("Root", []))]
  |> list.each(fn(value) {
    let assert Error(types.InvalidEdit(_, _)) =
      forest.new(view_a(), stored_schema(), value)
    Nil
  })
  let assert Ok(optional) =
    schema.stored_from_string(string.replace(
      forest_schema,
      "\"root\":{\"kind\":\"Value\"",
      "\"root\":{\"kind\":\"Optional\"",
    ))
  let assert Ok(empty) = forest.new(view_a(), optional, None)
  forest.visible_root(empty) |> expect.to_equal(Ok(None))
  let assert Error(types.InvalidEdit(_, _)) = forest.locate(empty, [])
  Nil
}

pub fn shared_tree_forest_subtree_validation_does_not_use_root_types_test() -> Nil {
  let stored = stored_schema()
  schema.validate_subtree(stored, types.NumberValue(1.0))
  |> expect.to_equal(Ok(Nil))
  schema.validate_subtree(stored, point(1.0, 2.0))
  |> expect.to_equal(Ok(Nil))
  schema.validate_root(stored, types.NumberValue(1.0))
  |> expect.to_be_error
  [
    types.ObjectValue("Point", []),
    types.ObjectValue("Unknown", []),
    types.ObjectValue("Point", [
      #("x", types.NumberValue(0.0)),
      #("x", types.NumberValue(1.0)),
      #("y", types.NumberValue(0.0)),
    ]),
  ]
  |> list.each(fn(value) {
    schema.validate_subtree(stored, value) |> expect.to_be_error
  })
}

fn atom(local_id: Int) -> types.AtomId {
  let assert Ok(revision) =
    fluid_ids.stable_id("00000000-0000-4000-8000-0000000000f0")
  types.AtomId(Some(revision), local_id)
}

fn empty_delta() -> forest.DeltaData {
  forest.DeltaData(
    latest_revision: atom(0).revision,
    fields: [],
    build: [],
    refreshers: [],
    global: [],
    rename: [],
    destroy: [],
  )
}

fn apply(state: forest.Forest, data: forest.DeltaData) -> forest.Forest {
  let assert Ok(delta) = forest.delta(data)
  let assert Ok(state) = forest.apply_delta(state, delta)
  state
}

pub fn shared_tree_forest_self_rename_does_not_conflict_with_transfer_test() -> Nil {
  let assert Ok(initial) = forest.new(view_a(), stored_schema(), Some(root()))
  let state =
    apply(
      initial,
      forest.DeltaData(..empty_delta(), build: [
        forest.Build(atom(10), [types.NumberValue(1.0)]),
      ]),
    )
  let assert Ok(reference) = forest.locate_detached(state, atom(10))
  let moved =
    apply(
      state,
      forest.DeltaData(..empty_delta(), rename: [
        forest.Rename(atom(10), atom(11), 1),
        forest.Rename(atom(11), atom(11), 1),
      ]),
    )
  forest.locate_detached(moved, atom(10)) |> expect.to_be_error
  forest.locate_detached(moved, atom(11)) |> expect.to_equal(Ok(reference))
}

pub fn shared_tree_forest_duplicate_attach_cannot_clone_a_refresher_test() -> Nil {
  let duplicate =
    forest.delta(
      forest.DeltaData(
        ..empty_delta(),
        refreshers: [forest.Build(atom(1), [types.NumberValue(9.0)])],
        fields: [
          #(
            "rootFieldKey",
            forest.FieldDelta([
              forest.Mark(1, None, None, [
                #(
                  "point",
                  forest.FieldDelta([
                    forest.Mark(1, None, None, [
                      replace_field("x", atom(1), atom(2)),
                      replace_field("y", atom(1), atom(3)),
                    ]),
                  ]),
                ),
              ]),
            ]),
          ),
        ],
      ),
    )
  let assert Error(types.CorruptData(_, _)) = duplicate
  Nil
}

pub fn shared_tree_forest_delta_shape_refusals_test() -> Nil {
  [
    forest.DeltaData(..empty_delta(), build: [
      forest.Build(atom(-1), [types.NumberValue(1.0)]),
    ]),
    forest.DeltaData(..empty_delta(), rename: [
      forest.Rename(atom(9_007_199_254_740_991), atom(0), 2),
    ]),
    forest.DeltaData(..empty_delta(), destroy: [
      forest.Destroy(atom(0), 0),
    ]),
    forest.DeltaData(..empty_delta(), fields: [
      #("rootFieldKey", forest.FieldDelta([forest.Mark(0, None, None, [])])),
    ]),
    forest.DeltaData(..empty_delta(), fields: [
      #("rootFieldKey", forest.FieldDelta([forest.Mark(2, None, None, [])])),
    ]),
    forest.DeltaData(..empty_delta(), fields: [
      #(
        "rootFieldKey",
        forest.FieldDelta([
          forest.Mark(1, None, None, [
            #("point", forest.FieldDelta([])),
            #("point", forest.FieldDelta([])),
          ]),
        ]),
      ),
    ]),
    forest.DeltaData(..empty_delta(), fields: [
      #("rootFieldKey", forest.FieldDelta([])),
      #("rootFieldKey", forest.FieldDelta([])),
    ]),
    forest.DeltaData(..empty_delta(), build: [
      forest.Build(atom(0), [types.NumberValue(1.0), types.NumberValue(2.0)]),
      forest.Build(atom(1), [types.NumberValue(3.0)]),
    ]),
  ]
  |> list.each(fn(data) {
    let assert Error(types.CorruptData(_, _)) = forest.delta(data)
    Nil
  })
}

pub fn shared_tree_forest_failure_after_build_preserves_all_state_test() -> Nil {
  let assert Ok(initial) = forest.new(view_a(), stored_schema(), Some(root()))
  let assert Ok(before) = forest.export_data(initial)
  let assert Ok(original) = forest.locate(initial, ["point"])
  let build =
    forest.DeltaData(..empty_delta(), build: [
      forest.Build(atom(0), [point(1.0, 2.0)]),
    ])
  let failures = [
    forest.DeltaData(..build, fields: [
      #(
        "rootFieldKey",
        forest.FieldDelta([
          forest.Mark(1, None, None, [
            replace_field("point", atom(999), atom(2)),
          ]),
        ]),
      ),
    ]),
    forest.DeltaData(..build, fields: [
      #(
        "rootFieldKey",
        forest.FieldDelta([
          forest.Mark(1, None, Some(atom(3)), []),
        ]),
      ),
    ]),
    forest.DeltaData(..build, fields: [
      #(
        "rootFieldKey",
        forest.FieldDelta([
          forest.Mark(1, None, None, [#("unknown", forest.FieldDelta([]))]),
        ]),
      ),
    ]),
    forest.DeltaData(..empty_delta(), build: [
      forest.Build(atom(0), [types.ObjectValue("Point", [])]),
    ]),
    forest.DeltaData(..build, destroy: [forest.Destroy(atom(999), 1)]),
  ]
  list.each(failures, fn(data) {
    let assert Ok(delta) = forest.delta(data)
    let assert Error(types.CorruptData(_, _)) =
      forest.apply_delta(initial, delta)
    forest.export_data(initial) |> expect.to_equal(Ok(before))
    forest.read_node(initial, original) |> expect.to_equal(Ok(point(0.0, 0.0)))
    let allocated = apply(initial, build)
    let assert Ok(data) = forest.export_data(allocated)
    data.next_detached_root_id |> expect.to_equal(1)
    let assert [entry] = data.detached
    entry.forest_root_id |> expect.to_equal(0)
  })
}

pub fn shared_tree_forest_import_refuses_invalid_metadata_test() -> Nil {
  let assert Ok(initial) = forest.new(view_a(), stored_schema(), Some(root()))
  let state =
    apply(
      initial,
      forest.DeltaData(..empty_delta(), build: [
        forest.Build(atom(0), [types.NumberValue(1.0)]),
      ]),
    )
  let assert Ok(data) = forest.export_data(state)
  let assert [entry] = data.detached
  let assert Ok(too_large) = int.parse("9007199254740992")
  [
    forest.ForestData(..data, next_detached_root_id: -1),
    forest.ForestData(..data, next_detached_root_id: 0),
    forest.ForestData(..data, next_detached_root_id: too_large),
    forest.ForestData(..data, root: None),
    forest.ForestData(..data, detached: [entry, entry]),
    forest.ForestData(..data, detached: [
      entry,
      forest.DetachedTreeData(..entry, id: atom(1)),
    ]),
    forest.ForestData(..data, detached: [
      forest.DetachedTreeData(..entry, id: atom(-1)),
    ]),
    forest.ForestData(..data, detached: [
      forest.DetachedTreeData(..entry, value: types.ObjectValue("Unknown", [])),
    ]),
  ]
  |> list.each(fn(data) {
    let assert Error(types.CorruptData(_, _)) =
      forest.import_data(view_b(), stored_schema(), data)
    Nil
  })
}

pub fn shared_tree_forest_destroy_preserves_watermark_and_invalidates_reference_test() -> Nil {
  let assert Ok(initial) = forest.new(view_a(), stored_schema(), Some(root()))
  let state =
    apply(
      initial,
      forest.DeltaData(..empty_delta(), build: [
        forest.Build(atom(10), [point(1.0, 2.0), point(3.0, 4.0)]),
      ]),
    )
  let assert Ok(old) = forest.locate_detached(state, atom(11))
  let destroyed =
    apply(
      state,
      forest.DeltaData(..empty_delta(), destroy: [forest.Destroy(atom(11), 1)]),
    )
  forest.read_node(destroyed, old) |> expect.to_be_error
  let assert Ok(data) = forest.export_data(destroyed)
  data.next_detached_root_id |> expect.to_equal(2)
  let assert Ok(loaded) = forest.import_data(view_b(), stored_schema(), data)
  let rebuilt =
    apply(
      loaded,
      forest.DeltaData(..empty_delta(), build: [
        forest.Build(atom(12), [types.NumberValue(5.0)]),
      ]),
    )
  let assert Ok(final) = forest.export_data(rebuilt)
  final.next_detached_root_id |> expect.to_equal(3)
  let assert [first, last] = final.detached
  first.forest_root_id |> expect.to_equal(0)
  last.forest_root_id |> expect.to_equal(2)
}

pub fn shared_tree_forest_ownership_cycle_is_atomic_test() -> Nil {
  let assert Ok(stored) =
    schema.stored_from_string(
      "{\"version\":2,\"nodes\":{\"Node\":{\"kind\":{\"object\":{\"child\":{\"kind\":\"Optional\",\"types\":[\"Node\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Node\"]}}",
    )
  let leaf = types.ObjectValue("Node", [])
  let assert Ok(initial) =
    forest.new(
      view_a(),
      stored,
      Some(types.ObjectValue("Node", [#("child", leaf)])),
    )
  let detached =
    apply(
      initial,
      forest.DeltaData(..empty_delta(), fields: [
        #(
          "rootFieldKey",
          forest.FieldDelta([
            forest.Mark(1, None, None, [
              #(
                "child",
                forest.FieldDelta([forest.Mark(1, None, Some(atom(0)), [])]),
              ),
            ]),
          ]),
        ),
      ]),
    )
  let assert Ok(before) = forest.export_data(detached)
  let assert Ok(reference) = forest.locate_detached(detached, atom(0))
  let assert Ok(cycle) =
    forest.delta(
      forest.DeltaData(..empty_delta(), global: [
        forest.DetachedChange(atom(0), [
          #(
            "child",
            forest.FieldDelta([forest.Mark(1, Some(atom(0)), None, [])]),
          ),
        ]),
      ]),
    )
  let assert Error(types.CorruptData(_, _)) =
    forest.apply_delta(detached, cycle)
  forest.export_data(detached) |> expect.to_equal(Ok(before))
  forest.read_node(detached, reference) |> expect.to_equal(Ok(leaf))
}

pub fn shared_tree_forest_safe_integer_boundaries_test() -> Nil {
  let assert Ok(initial) = forest.new(view_a(), stored_schema(), Some(root()))
  let high = atom(9_007_199_254_740_991)
  let anonymous = types.AtomId(None, high.local_id)
  let built =
    apply(
      initial,
      forest.DeltaData(..empty_delta(), build: [
        forest.Build(high, [types.NumberValue(1.0)]),
        forest.Build(anonymous, [types.NumberValue(2.0)]),
      ]),
    )
  let assert Ok(first) = forest.locate_detached(built, high)
  let assert Ok(second) = forest.locate_detached(built, anonymous)
  forest.read_node(built, first) |> expect.to_equal(Ok(types.NumberValue(1.0)))
  forest.read_node(built, second) |> expect.to_equal(Ok(types.NumberValue(2.0)))
  let assert Ok(data) = forest.export_data(built)
  let assert Ok(exhausted) =
    forest.import_data(
      view_b(),
      stored_schema(),
      forest.ForestData(..data, next_detached_root_id: high.local_id),
    )
  let assert Ok(before) = forest.export_data(exhausted)
  let assert Ok(build) =
    forest.delta(
      forest.DeltaData(..empty_delta(), build: [
        forest.Build(atom(0), [point(0.0, 0.0)]),
      ]),
    )
  let assert Error(types.CorruptData(_, _)) =
    forest.apply_delta(exhausted, build)
  forest.export_data(exhausted) |> expect.to_equal(Ok(before))
}

pub fn shared_tree_forest_equal_replacement_changes_identity_test() -> Nil {
  let assert Ok(initial) = forest.new(view_a(), stored_schema(), Some(root()))
  let assert Ok(before) = forest.locate(initial, ["point"])
  let changed =
    apply(
      initial,
      forest.DeltaData(
        ..empty_delta(),
        build: [forest.Build(atom(0), [point(0.0, 0.0)])],
        fields: [
          #(
            "rootFieldKey",
            forest.FieldDelta([
              forest.Mark(1, None, None, [
                replace_field("point", atom(0), atom(1)),
              ]),
            ]),
          ),
        ],
      ),
    )
  let assert Ok(after) = forest.locate(changed, ["point"])
  { before == after } |> expect.to_be_false
  forest.is_attached(changed, before) |> expect.to_equal(Ok(False))
  forest.read_node(changed, before) |> expect.to_equal(Ok(point(0.0, 0.0)))
  forest.read_node(changed, after) |> expect.to_equal(Ok(point(0.0, 0.0)))
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

fn replace_point(
  state: forest.Forest,
) -> Result(forest.Forest, types.TreeError) {
  let assert Ok(delta) =
    forest.delta(
      forest.DeltaData(
        ..empty_delta(),
        build: [forest.Build(atom(1), [point(10.0, 20.0)])],
        fields: [
          #(
            "rootFieldKey",
            forest.FieldDelta([
              forest.Mark(1, None, None, [
                replace_field("point", atom(1), atom(2)),
              ]),
            ]),
          ),
        ],
      ),
    )
  forest.apply_delta(state, delta)
}

fn change_old_x(
  state: forest.Forest,
) -> Result(forest.Forest, types.TreeError) {
  let assert Ok(delta) =
    forest.delta(
      forest.DeltaData(
        ..empty_delta(),
        build: [forest.Build(atom(3), [types.NumberValue(42.0)])],
        global: [
          forest.DetachedChange(atom(2), [replace_field("x", atom(3), atom(4))]),
        ],
      ),
    )
  forest.apply_delta(state, delta)
}

pub fn shared_tree_forest_detached_child_delta_preserves_replacement_test() -> Nil {
  let assert Ok(original) = forest.new(view_a(), stored_schema(), Some(root()))
  let assert Ok(old_point) = forest.locate(original, ["point"])
  let assert Ok(replaced) = replace_point(original)
  let assert Ok(changed) = change_old_x(replaced)
  forest.read(changed, ["point"])
  |> expect.to_equal(Ok(Some(point(10.0, 20.0))))
  forest.read_node(changed, old_point)
  |> expect.to_equal(Ok(point(42.0, 0.0)))
  forest.is_attached(changed, old_point) |> expect.to_equal(Ok(False))
  forest.read_node(original, old_point)
  |> expect.to_equal(Ok(point(0.0, 0.0)))
}

pub fn shared_tree_forest_direct_rename_cycle_is_atomic_test() -> Nil {
  let assert Ok(initial) = forest.new(view_a(), stored_schema(), Some(root()))
  let assert Ok(build) =
    forest.delta(
      forest.DeltaData(..empty_delta(), build: [
        forest.Build(atom(10), [types.NumberValue(1.0)]),
        forest.Build(atom(11), [types.NumberValue(2.0)]),
      ]),
    )
  let assert Ok(state) = forest.apply_delta(initial, build)
  let assert Ok(first) = forest.locate_detached(state, atom(10))
  let assert Ok(second) = forest.locate_detached(state, atom(11))
  let assert Ok(swap) =
    forest.delta(
      forest.DeltaData(..empty_delta(), rename: [
        forest.Rename(atom(10), atom(11), 1),
        forest.Rename(atom(11), atom(10), 1),
      ]),
    )
  let assert Error(types.CorruptData(_, _)) = forest.apply_delta(state, swap)
  forest.read_node(state, first)
  |> expect.to_equal(Ok(types.NumberValue(1.0)))
  forest.read_node(state, second)
  |> expect.to_equal(Ok(types.NumberValue(2.0)))
}

pub fn shared_tree_forest_round_trip_retains_detached_data_test() -> Nil {
  let assert Ok(initial) = forest.new(view_a(), stored_schema(), Some(root()))
  let assert Ok(old_reference) = forest.locate(initial, ["point"])
  let assert Ok(replaced) = replace_point(initial)
  let assert Ok(changed) = change_old_x(replaced)
  let assert Ok(data) = forest.export_data(changed)
  let assert Ok(loaded) = forest.import_data(view_b(), stored_schema(), data)
  forest.export_data(loaded) |> expect.to_equal(Ok(data))
  forest.read(loaded, ["point"])
  |> expect.to_equal(Ok(Some(point(10.0, 20.0))))
  let assert Error(types.InvalidEdit(_, _)) =
    forest.read_node(loaded, old_reference)
  let assert Ok(retained) = forest.locate_detached(loaded, atom(2))
  forest.read_node(loaded, retained)
  |> expect.to_equal(Ok(point(42.0, 0.0)))
}

pub fn shared_tree_forest_oracle_test() -> Nil {
  fixtures.assert_case("forest-delta", forest_fixture.run)
}
