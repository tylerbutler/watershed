import gleam/option.{None, Some}
import startest/expect
import watershed/tree/array_fixture
import watershed/tree/forest
import watershed/tree/types

const items_type = "org.watershed.shared-tree.m3.Items"

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
