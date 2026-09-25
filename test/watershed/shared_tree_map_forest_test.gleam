import gleam/list
import gleam/option.{None, Some}
import startest/expect
import watershed/fluid_ids
import watershed/tree/forest
import watershed/tree/schema
import watershed/tree/types

const map_type = "org.watershed.shared-tree.m2.DynamicMap"

const point_type = "org.watershed.shared-tree.m2.Point"

const map_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"org.watershed.shared-tree.m2.DynamicMap\":{\"kind\":{\"map\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.number\",\"com.fluidframework.leaf.string\",\"org.watershed.shared-tree.m2.DynamicMap\",\"org.watershed.shared-tree.m2.Point\"]}}},\"org.watershed.shared-tree.m2.Point\":{\"kind\":{\"object\":{\"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]},\"y\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\",\"org.watershed.shared-tree.m2.DynamicMap\",\"org.watershed.shared-tree.m2.Point\"]}}"

fn view() -> fluid_ids.StableId {
  let assert Ok(id) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000003")
  id
}

fn stored_schema() -> schema.StoredSchema {
  let assert Ok(stored) = schema.stored_from_string(map_schema)
  stored
}

fn point(x: Float, y: Float) -> types.TreeValue {
  types.ObjectValue(point_type, [
    #("x", types.NumberValue(x)),
    #("y", types.NumberValue(y)),
  ])
}

fn map_root() -> types.TreeValue {
  types.MapValue(map_type, [
    #("__proto__", types.StringValue("safe")),
    #("水", point(1.0, 2.0)),
    #(
      "nested",
      types.MapValue(map_type, [#("answer", types.NumberValue(42.0))]),
    ),
  ])
}

fn atom(local_id: Int) -> types.AtomId {
  let assert Ok(revision) =
    fluid_ids.stable_id("00000000-0000-4000-8000-0000000000f1")
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

fn root_field(fields: List(#(String, forest.FieldDelta))) {
  #("rootFieldKey", forest.FieldDelta([forest.Mark(1, None, None, fields)]))
}

pub fn shared_tree_map_forest_allocates_and_reads_maps_test() -> Nil {
  let root = map_root()
  let assert Ok(state) = forest.new(view(), stored_schema(), Some(root))
  forest.export_data(state)
  |> expect.to_equal(
    Ok(forest.ForestData(
      Some(
        types.MapValue(map_type, [
          #("__proto__", types.StringValue("safe")),
          #(
            "nested",
            types.MapValue(map_type, [#("answer", types.NumberValue(42.0))]),
          ),
          #("水", point(1.0, 2.0)),
        ]),
      ),
      [],
      0,
    )),
  )
  forest.read(state, ["水", "x"])
  |> expect.to_equal(Ok(Some(types.NumberValue(1.0))))
  forest.read(state, ["nested", "answer"])
  |> expect.to_equal(Ok(Some(types.NumberValue(42.0))))
  forest.map_type(state, []) |> expect.to_equal(Ok(map_type))
  forest.map_get(state, [], "__proto__")
  |> expect.to_equal(Ok(Some(types.StringValue("safe"))))
  forest.map_get(state, [], "missing") |> expect.to_equal(Ok(None))
  forest.map_entries(state, [])
  |> expect.to_equal(
    Ok([
      #("__proto__", types.StringValue("safe")),
      #(
        "nested",
        types.MapValue(map_type, [#("answer", types.NumberValue(42.0))]),
      ),
      #("水", point(1.0, 2.0)),
    ]),
  )
}

pub fn shared_tree_map_forest_preserves_special_keys_test() -> Nil {
  let root =
    types.MapValue(map_type, [
      #("水", types.NumberValue(7.0)),
      #("2", types.NumberValue(4.0)),
      #("", types.NumberValue(1.0)),
      #("__proto__", types.NumberValue(5.0)),
      #("10", types.NumberValue(3.0)),
      #("é", types.NumberValue(6.0)),
      #("01", types.NumberValue(2.0)),
    ])
  let assert Ok(state) = forest.new(view(), stored_schema(), Some(root))
  forest.map_entries(state, [])
  |> expect.to_equal(
    Ok([
      #("", types.NumberValue(1.0)),
      #("01", types.NumberValue(2.0)),
      #("10", types.NumberValue(3.0)),
      #("2", types.NumberValue(4.0)),
      #("__proto__", types.NumberValue(5.0)),
      #("é", types.NumberValue(6.0)),
      #("水", types.NumberValue(7.0)),
    ]),
  )
}

pub fn shared_tree_map_forest_rejects_non_map_reads_test() -> Nil {
  [point(1.0, 2.0), types.StringValue("leaf")]
  |> list.each(fn(root) {
    let assert Ok(state) = forest.new(view(), stored_schema(), Some(root))
    let assert Error(types.InvalidEdit([], _)) = forest.map_entries(state, [])
    let assert Error(types.InvalidEdit([], _)) =
      forest.map_get(state, [], "key")
    let assert Error(types.InvalidEdit([], _)) = forest.map_type(state, [])
    Nil
  })
}

pub fn shared_tree_map_forest_delta_retains_detached_map_values_test() -> Nil {
  let root = types.MapValue(map_type, [#("point", point(1.0, 2.0))])
  let assert Ok(initial) = forest.new(view(), stored_schema(), Some(root))
  let assert Ok(reference) = forest.locate(initial, ["point"])
  let detached =
    apply(
      initial,
      forest.DeltaData(
        ..empty_delta(),
        build: [forest.Build(atom(0), [types.NumberValue(7.0)])],
        fields: [
          root_field([
            #(
              "point",
              forest.FieldDelta([
                forest.Mark(1, None, Some(atom(2)), [
                  #(
                    "x",
                    forest.FieldDelta([
                      forest.Mark(1, Some(atom(0)), Some(atom(1)), []),
                    ]),
                  ),
                ]),
              ]),
            ),
          ]),
        ],
      ),
    )
  forest.map_entries(detached, []) |> expect.to_equal(Ok([]))
  forest.read_node(detached, reference)
  |> expect.to_equal(Ok(point(7.0, 2.0)))
  forest.is_attached(detached, reference) |> expect.to_equal(Ok(False))

  let renamed =
    apply(
      detached,
      forest.DeltaData(..empty_delta(), rename: [
        forest.Rename(atom(2), atom(3), 1),
      ]),
    )
  let attached =
    apply(
      renamed,
      forest.DeltaData(..empty_delta(), fields: [
        root_field([
          #(
            "moved",
            forest.FieldDelta([
              forest.Mark(1, Some(atom(3)), None, []),
            ]),
          ),
        ]),
      ]),
    )
  forest.map_get(attached, [], "moved")
  |> expect.to_equal(Ok(Some(point(7.0, 2.0))))
  forest.is_attached(attached, reference) |> expect.to_equal(Ok(True))

  let removed =
    apply(
      attached,
      forest.DeltaData(..empty_delta(), fields: [
        root_field([
          #(
            "moved",
            forest.FieldDelta([
              forest.Mark(1, None, Some(atom(4)), []),
            ]),
          ),
        ]),
      ]),
    )
  let destroyed =
    apply(
      removed,
      forest.DeltaData(..empty_delta(), destroy: [
        forest.Destroy(atom(4), 1),
      ]),
    )
  let _ = forest.read_node(destroyed, reference) |> expect.to_be_error
  Nil
}

pub fn shared_tree_map_forest_attaches_refreshed_map_entries_test() -> Nil {
  let assert Ok(initial) =
    forest.new(view(), stored_schema(), Some(types.MapValue(map_type, [])))
  let state =
    apply(
      initial,
      forest.DeltaData(
        ..empty_delta(),
        refreshers: [
          forest.Build(atom(5), [
            types.MapValue(map_type, [#("answer", types.NumberValue(42.0))]),
          ]),
        ],
        fields: [
          root_field([
            #(
              "nested",
              forest.FieldDelta([
                forest.Mark(1, Some(atom(5)), None, []),
              ]),
            ),
          ]),
        ],
      ),
    )
  forest.read(state, ["nested", "answer"])
  |> expect.to_equal(Ok(Some(types.NumberValue(42.0))))
}
