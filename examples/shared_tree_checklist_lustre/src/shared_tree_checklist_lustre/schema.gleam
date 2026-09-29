import gleam/list
import watershed/tree/schema
import watershed/tree/types

const checklist_type = "shared_tree_checklist.Checklist"

const items_type = "shared_tree_checklist.Items"

const item_type = "shared_tree_checklist.Item"

const definition = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.boolean\":{\"kind\":{\"leaf\":2}},\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"shared_tree_checklist.Checklist\":{\"kind\":{\"object\":{\"items\":{\"kind\":\"Value\",\"types\":[\"shared_tree_checklist.Items\"]},\"title\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}}},\"shared_tree_checklist.Item\":{\"kind\":{\"object\":{\"completed\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.boolean\"]},\"id\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]},\"text\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}}},\"shared_tree_checklist.Items\":{\"kind\":{\"object\":{\"\":{\"kind\":\"Sequence\",\"types\":[\"shared_tree_checklist.Item\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"shared_tree_checklist.Checklist\"]}}"

pub fn stored() -> schema.StoredSchema {
  let assert Ok(value) = schema.stored_from_string(definition)
  value
}

pub fn view() -> schema.ViewSchema {
  let assert Ok(value) = schema.view_from_string(definition)
  value
}

pub fn initial() -> types.TreeValue {
  checklist_value([])
}

pub fn checklist_value(
  items: List(#(String, String, Bool)),
) -> types.TreeValue {
  types.ObjectValue(checklist_type, [
    #("title", types.StringValue("SharedTree checklist")),
    #(
      "items",
      types.ArrayValue(
        items_type,
        list.map(items, fn(item) { item_value(item.0, item.1, item.2) }),
      ),
    ),
  ])
}

pub fn item_value(
  id: String,
  text: String,
  completed: Bool,
) -> types.TreeValue {
  types.ObjectValue(item_type, [
    #("id", types.StringValue(id)),
    #("text", types.StringValue(text)),
    #("completed", types.BooleanValue(completed)),
  ])
}
