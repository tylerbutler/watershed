import watershed/tree/schema
import watershed/tree/schema_builder as builder
import watershed/tree/types

// docs:snippet-start item-counter-watershed-definition
// This identifier names the array type, as SchemaFactory names StringArray.
pub const array_type = "shared_tree_item_counter.StringArray"

// docs:snippet-end item-counter-watershed-definition

// docs:snippet-start item-counter-watershed-schema
// Declare a root array of strings, as sf.array("StringArray", sf.string) does.
// Compile the stored schema for creation and the view schema for loading.
pub fn definition() -> Result(builder.Compiled(List(String)), types.TreeError) {
  builder.array(
    builder.factory("shared_tree_item_counter"),
    "StringArray",
    builder.string(),
  )
  |> builder.root
  |> builder.compile
}

pub fn compiled() -> builder.Compiled(List(String)) {
  let assert Ok(value) = definition()
  value
}

pub fn stored() -> schema.StoredSchema {
  builder.stored(compiled())
}

pub fn view() -> schema.ViewSchema {
  builder.view(compiled())
}

// Start with an empty array, as appData.initialize([]) does.
pub fn initial() -> List(String) {
  []
}
// docs:snippet-end item-counter-watershed-schema
