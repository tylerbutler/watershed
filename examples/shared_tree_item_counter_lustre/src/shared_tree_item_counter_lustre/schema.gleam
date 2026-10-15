import watershed/tree/schema
import watershed/tree/types

// docs:snippet-start item-counter-watershed-definition
pub const array_type = "shared_tree_item_counter.StringArray"

const definition = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"shared_tree_item_counter.StringArray\":{\"kind\":{\"object\":{\"\":{\"kind\":\"Sequence\",\"types\":[\"com.fluidframework.leaf.string\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"shared_tree_item_counter.StringArray\"]}}"

// docs:snippet-end item-counter-watershed-definition

// docs:snippet-start item-counter-watershed-schema
pub fn stored() -> schema.StoredSchema {
  let assert Ok(value) = schema.stored_from_string(definition)
  value
}

pub fn view() -> schema.ViewSchema {
  let assert Ok(value) = schema.view_from_string(definition)
  value
}

pub fn initial() -> types.TreeValue {
  types.ArrayValue(array_type, [])
}
// docs:snippet-end item-counter-watershed-schema
