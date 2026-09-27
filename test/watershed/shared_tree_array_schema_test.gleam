import startest/expect
import watershed/tree/array_fixture
import watershed/tree/schema
import watershed/tree/types

const items_type = "org.watershed.shared-tree.m3.Items"

pub fn shared_tree_array_schema_decodes_sequence_node_test() -> Nil {
  let stored = array_fixture.stored("rootArray")
  schema.node_schema(stored, items_type)
  |> expect.to_equal(
    Ok(
      schema.Array(
        schema.FieldSchema(schema.Sequence, [
          "com.fluidframework.leaf.boolean",
          "com.fluidframework.leaf.null",
          "com.fluidframework.leaf.number",
          "com.fluidframework.leaf.string",
          "org.watershed.shared-tree.m3.ArrayMap",
          items_type,
          "org.watershed.shared-tree.m3.Point",
        ]),
      ),
    ),
  )
}

pub fn shared_tree_array_schema_validates_empty_and_ordered_elements_test() -> Nil {
  let stored = array_fixture.stored("rootArray")
  schema.validate_array_elements(stored, items_type, [])
  |> expect.to_equal(Ok(Nil))
  schema.validate_array_elements(stored, items_type, [
    types.StringValue("B"),
    types.StringValue("A"),
    types.StringValue("B"),
  ])
  |> expect.to_equal(Ok(Nil))
}
