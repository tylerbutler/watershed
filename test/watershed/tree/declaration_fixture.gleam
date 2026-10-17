import watershed/tree/schema_builder as builder

pub const item_type = "shared_tree_checklist.Item"

pub const generated_item_type = "shared_tree_checklist.GeneratedItem"

pub type Item {
  Item(id: String, text: String, completed: Bool)
}

pub type GeneratedItem {
  GeneratedItem(id: builder.Identifier, text: String)
}

pub fn item() -> builder.Node(Item) {
  builder.object3(
    builder.factory("shared_tree_checklist"),
    "Item",
    Item,
    builder.required("id", builder.string(), fn(value: Item) { value.id }),
    builder.required("text", builder.string(), fn(value: Item) { value.text }),
    builder.required("completed", builder.boolean(), fn(value: Item) {
      value.completed
    }),
  )
}

pub fn generated_item() -> builder.Node(GeneratedItem) {
  builder.object2(
    builder.factory("shared_tree_checklist"),
    "GeneratedItem",
    GeneratedItem,
    builder.identifier("id", fn(value: GeneratedItem) { value.id }),
    builder.required("text", builder.string(), fn(value: GeneratedItem) {
      value.text
    }),
  )
}
