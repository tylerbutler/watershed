import watershed/tree/schema_builder as builder

// docs:snippet-start item-counter-watershed-definition
// This identifier names the array type, as SchemaFactory names StringArray.
pub const array_type = "shared_tree_item_counter.StringArray"

// docs:snippet-end item-counter-watershed-definition

// docs:snippet-start item-counter-watershed-schema
// Declare a root array of strings, as sf.array("StringArray", sf.string) does.
pub fn configuration() -> builder.Root(List(String)) {
  builder.array(
    factory: builder.factory(scope: "shared_tree_item_counter"),
    name: "StringArray",
    element: builder.string(),
  )
  |> builder.root
}

// Start with an empty array, as appData.initialize([]) does.
pub fn initial() -> List(String) {
  []
}
// docs:snippet-end item-counter-watershed-schema
