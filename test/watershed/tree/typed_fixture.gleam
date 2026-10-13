import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import watershed/tree/schema as tree_schema
import watershed/tree/typed
import watershed/tree/types

pub const checklist_type = "shared_tree_checklist.Checklist"

pub const items_type = "shared_tree_checklist.Items"

pub const item_type = "shared_tree_checklist.Item"

pub const generated_item_type = "shared_tree_checklist.GeneratedItem"

const definition = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.boolean\":{\"kind\":{\"leaf\":2}},\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"shared_tree_checklist.Checklist\":{\"kind\":{\"object\":{\"items\":{\"kind\":\"Value\",\"types\":[\"shared_tree_checklist.Items\"]},\"title\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}}},\"shared_tree_checklist.Item\":{\"kind\":{\"object\":{\"completed\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.boolean\"]},\"id\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]},\"text\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}}},\"shared_tree_checklist.Items\":{\"kind\":{\"object\":{\"\":{\"kind\":\"Sequence\",\"types\":[\"shared_tree_checklist.Item\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"shared_tree_checklist.Checklist\"]}}"

const identifier_definition = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"shared_tree_checklist.GeneratedItem\":{\"kind\":{\"object\":{\"id\":{\"kind\":\"Identifier\",\"types\":[\"com.fluidframework.leaf.string\"]},\"text\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"shared_tree_checklist.GeneratedItem\"]}}"

pub type ChecklistTag {
  ChecklistTag
}

pub type ItemTag {
  ItemTag
}

pub type GeneratedItemTag {
  GeneratedItemTag
}

pub type Checklist {
  Checklist(title: String, items: List(Item))
}

pub type Item {
  Item(id: String, text: String, completed: Bool)
}

pub type ItemInput {
  ItemInput(id: String, text: String, completed: Bool)
}

pub type GeneratedItem {
  GeneratedItem(id: String, text: String)
}

pub type GeneratedItemInput {
  GeneratedItemInput(text: String)
}

pub fn view() -> tree_schema.ViewSchema {
  let assert Ok(value) = tree_schema.view_from_string(definition)
  value
}

pub fn identifier_view() -> tree_schema.ViewSchema {
  let assert Ok(value) = tree_schema.view_from_string(identifier_definition)
  value
}

pub fn item_codec() -> typed.NodeCodec(ItemTag, Item) {
  let assert Ok(value) = typed.node(item_type, decode_item)
  value
}

pub fn item_builder() -> typed.Builder(ItemTag, ItemInput) {
  let assert Ok(value) = typed.builder(item_type, encode_item)
  value
}

pub fn checklist_codec() -> typed.NodeCodec(ChecklistTag, Checklist) {
  let assert Ok(value) = typed.node(checklist_type, decode_checklist)
  value
}

pub fn checklist_schema() -> typed.Schema(ChecklistTag, Checklist) {
  let assert Ok(value) = typed.schema(view(), checklist_codec())
  value
}

pub fn checklist_title() -> typed.Field(ChecklistTag, String, typed.Required) {
  typed.required("title", typed.string())
}

pub fn checklist_items() -> typed.ArrayField(ChecklistTag, ItemTag, Item) {
  typed.array_field("items", items_type, item_codec())
}

pub fn item_id() -> typed.Field(ItemTag, String, typed.Required) {
  typed.required("id", typed.string())
}

pub fn item_text() -> typed.Field(ItemTag, String, typed.Required) {
  typed.required("text", typed.string())
}

pub fn item_completed() -> typed.Field(ItemTag, Bool, typed.Required) {
  typed.required("completed", typed.boolean())
}

pub fn generated_item_codec() -> typed.NodeCodec(
  GeneratedItemTag,
  GeneratedItem,
) {
  let assert Ok(value) = typed.node(generated_item_type, decode_generated_item)
  value
}

pub fn generated_item_builder() -> typed.Builder(
  GeneratedItemTag,
  GeneratedItemInput,
) {
  let assert Ok(value) =
    typed.builder(generated_item_type, encode_generated_item)
  value
}

pub fn generated_item_identifier() -> typed.IdentifierField(GeneratedItemTag) {
  typed.identifier("id")
}

pub fn generated_item_text() -> typed.Field(
  GeneratedItemTag,
  String,
  typed.Required,
) {
  typed.required("text", typed.string())
}

fn decode_checklist(value: types.TreeValue) -> Result(Checklist, typed.Error) {
  let assert types.ObjectValue(_, fields) = value
  use title <- result.try(required_field(fields, "title", typed.string()))
  use items_value <- result.try(find_field(fields, "items"))
  use items <- result.try(case items_value {
    Some(types.ArrayValue(identifier, values)) if identifier == items_type ->
      list.try_map(values, fn(value) { typed.decode_node(item_codec(), value) })
    Some(_) -> Error(typed.DecodeFailed("expected checklist items"))
    None -> Error(typed.DecodeFailed("expected checklist items"))
  })
  Ok(Checklist(title:, items:))
}

fn decode_item(value: types.TreeValue) -> Result(Item, typed.Error) {
  let assert types.ObjectValue(_, fields) = value
  use id <- result.try(required_field(fields, "id", typed.string()))
  use text <- result.try(required_field(fields, "text", typed.string()))
  use completed <- result.try(required_field(
    fields,
    "completed",
    typed.boolean(),
  ))
  Ok(Item(id:, text:, completed:))
}

fn encode_item(value: ItemInput) -> Result(types.TreeValue, typed.Error) {
  Ok(
    types.ObjectValue(item_type, [
      #("id", types.StringValue(value.id)),
      #("text", types.StringValue(value.text)),
      #("completed", types.BooleanValue(value.completed)),
    ]),
  )
}

fn decode_generated_item(
  value: types.TreeValue,
) -> Result(GeneratedItem, typed.Error) {
  let assert types.ObjectValue(_, fields) = value
  use id <- result.try(required_field(fields, "id", typed.string()))
  use text <- result.try(required_field(fields, "text", typed.string()))
  Ok(GeneratedItem(id:, text:))
}

fn encode_generated_item(
  value: GeneratedItemInput,
) -> Result(types.TreeValue, typed.Error) {
  Ok(
    types.ObjectValue(generated_item_type, [
      #("text", types.StringValue(value.text)),
    ]),
  )
}

fn required_field(
  fields: List(#(String, types.TreeValue)),
  key: String,
  codec: typed.Codec(a),
) -> Result(a, typed.Error) {
  use value <- result.try(find_field(fields, key))
  case value {
    Some(value) -> typed.decode(codec, value)
    None -> Error(typed.DecodeFailed("expected field " <> key))
  }
}

fn find_field(
  fields: List(#(String, types.TreeValue)),
  key: String,
) -> Result(Option(types.TreeValue), typed.Error) {
  case list.key_find(fields, key) {
    Ok(value) -> Ok(Some(value))
    Error(Nil) -> Ok(None)
  }
}
