import watershed/tree/schema
import watershed/tree/typed
import watershed/tree/types

pub type Counter

pub type Item

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

pub fn declaration() -> typed.Schema(Counter, types.TreeValue) {
  let assert Ok(root) = typed.node(array_type, fn(value) { Ok(value) })
  let assert Ok(value) = typed.schema(view(), root)
  value
}

pub fn builder() -> typed.Builder(Counter, types.TreeValue) {
  let assert Ok(value) = typed.builder(array_type, fn(value) { Ok(value) })
  value
}

pub fn item_decoder() -> typed.NodeCodec(Item, String) {
  let assert Ok(value) =
    typed.node("com.fluidframework.leaf.string", fn(value) {
      typed.decode(typed.string(), value)
    })
  value
}

pub fn item_builder() -> typed.Builder(Item, String) {
  let assert Ok(value) =
    typed.builder("com.fluidframework.leaf.string", fn(value) {
      typed.encode(typed.string(), value)
    })
  value
}
// docs:snippet-end item-counter-watershed-schema
