import gleam/option.{None, Some}
import gleam/string
import startest/expect
import watershed/fluid_ids
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/schema
import watershed/tree/types.{NumberValue, ObjectValue}
import watershed/tree_kernel

const tree_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"Point\":{\"kind\":{\"object\":{\"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]}}}},\"Root\":{\"kind\":{\"object\":{\"point\":{\"kind\":\"Value\",\"types\":[\"Point\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}"

fn session() -> fluid_ids.SessionId {
  let assert Ok(id) =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000001")
  id
}

fn view_id() -> fluid_ids.StableId {
  let assert Ok(id) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000002")
  id
}

fn root() -> types.TreeValue {
  ObjectValue("Root", [
    #("point", ObjectValue("Point", [#("x", NumberValue(1.0))])),
  ])
}

pub fn shared_tree_kernel_restores_checked_snapshot_test() {
  let assert Ok(stored) = schema.stored_from_string(tree_schema)
  let assert Ok(view) = schema.view_from_string(tree_schema)
  let initial = history.inspect(history.new(session())).sequenced
  let assert Ok(snapshot) =
    tree_kernel.snapshot_from_parts(
      view_id(),
      stored,
      forest.ForestData(Some(root()), [], 0),
      initial,
    )
  let assert Ok(state) =
    tree_kernel.restore(snapshot, view_id(), session(), view)
  tree_kernel.read(state, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(1.0))))
  tree_kernel.snapshot(state) |> expect.to_equal(Ok(snapshot))
}

pub fn shared_tree_kernel_rejects_incompatible_view_test() {
  let assert Ok(stored) = schema.stored_from_string(tree_schema)
  let assert Ok(view) =
    schema.view_from_string(string.replace(
      tree_schema,
      "\"Value\"",
      "\"Optional\"",
    ))
  let initial = history.inspect(history.new(session())).sequenced
  let assert Ok(snapshot) =
    tree_kernel.snapshot_from_parts(
      view_id(),
      stored,
      forest.ForestData(Some(root()), [], 0),
      initial,
    )
  tree_kernel.restore(snapshot, view_id(), session(), view)
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_kernel_rejects_corrupt_forest_test() {
  let assert Ok(stored) = schema.stored_from_string(tree_schema)
  let initial = history.inspect(history.new(session())).sequenced
  tree_kernel.snapshot_from_parts(
    view_id(),
    stored,
    forest.ForestData(None, [], 0),
    initial,
  )
  |> expect.to_be_error
  Nil
}
