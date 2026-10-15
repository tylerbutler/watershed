import gleam/option.{Some}
import watershed/tree/schema
import watershed/tree/schema_builder as builder
import watershed/tree/typed
import watershed/tree/types

pub type Counter

pub type Item

// docs:snippet-start item-counter-watershed-definition
pub const array_type = "shared_tree_item_counter.StringArray"

// docs:snippet-end item-counter-watershed-definition

// docs:snippet-start item-counter-watershed-schema
pub fn definition() -> Result(builder.Compiled(List(String)), types.TreeError) {
  builder.array(
    builder.factory("shared_tree_item_counter"),
    "StringArray",
    builder.string(),
  )
  |> builder.root
  |> builder.compile
}

fn compiled() -> builder.Compiled(List(String)) {
  let assert Ok(value) = definition()
  value
}

pub fn stored() -> schema.StoredSchema {
  builder.stored(compiled())
}

pub fn view() -> schema.ViewSchema {
  builder.view(compiled())
}

pub fn initial() -> types.TreeValue {
  let assert Ok(Some(value)) = builder.encode(compiled(), [])
  value
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
