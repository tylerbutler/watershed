import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import shared_tree_checklist_lustre/checklist
import shared_tree_checklist_lustre/schema as document_schema
import watershed/tree/schema_builder as declaration
import watershed/tree/typed
import watershed/tree/types

const checklist_type = "shared_tree_checklist.Checklist"

const items_type = "shared_tree_checklist.Items"

const item_type = "shared_tree_checklist.Item"

pub type Checklist

pub type Item

pub type ChecklistInput {
  ChecklistInput(title: String, items: List(ItemInput))
}

pub type ItemInput {
  ItemInput(id: String, text: String, completed: Bool)
}

pub fn compiled() -> declaration.Compiled(checklist.Checklist) {
  let factory = declaration.factory("shared_tree_checklist")
  let item =
    declaration.object3(
      factory,
      "Item",
      checklist.Item,
      declaration.required("id", declaration.string(), fn(item: checklist.Item) {
        item.id
      }),
      declaration.required(
        "text",
        declaration.string(),
        fn(item: checklist.Item) { item.text },
      ),
      declaration.required(
        "completed",
        declaration.boolean(),
        fn(item: checklist.Item) { item.completed },
      ),
    )
  let assert Ok(compiled) =
    declaration.object2(
      factory,
      "Checklist",
      checklist.Checklist,
      declaration.required(
        "title",
        declaration.string(),
        fn(value: checklist.Checklist) { value.title },
      ),
      declaration.required(
        "items",
        declaration.array(factory, "Items", item),
        fn(value: checklist.Checklist) { value.items },
      ),
    )
    |> declaration.root
    |> declaration.compile
  compiled
}

pub fn definition() -> typed.Schema(Checklist, checklist.Checklist) {
  let assert Ok(value) = typed.schema(document_schema.view(), decoder())
  value
}

pub fn decoder() -> typed.NodeCodec(Checklist, checklist.Checklist) {
  let assert Ok(value) = typed.node(checklist_type, decode_checklist)
  value
}

pub fn builder() -> typed.Builder(Checklist, ChecklistInput) {
  let assert Ok(value) = typed.builder(checklist_type, encode_checklist)
  value
}

pub fn item_decoder() -> typed.NodeCodec(Item, checklist.Item) {
  let assert Ok(value) = typed.node(item_type, decode_item)
  value
}

pub fn item_builder() -> typed.Builder(Item, ItemInput) {
  let assert Ok(value) = typed.builder(item_type, encode_item)
  value
}

pub fn initial() -> ChecklistInput {
  ChecklistInput("SharedTree checklist", [])
}

pub fn title() -> typed.Field(Checklist, String, typed.Required) {
  typed.required("title", typed.string())
}

pub fn text() -> typed.Field(Item, String, typed.Required) {
  typed.required("text", typed.string())
}

pub fn completed() -> typed.Field(Item, Bool, typed.Required) {
  typed.required("completed", typed.boolean())
}

pub fn items() -> typed.ArrayField(Checklist, Item, checklist.Item) {
  typed.array_field("items", items_type, item_decoder())
}

fn decode_checklist(
  value: types.TreeValue,
) -> Result(checklist.Checklist, typed.Error) {
  let assert types.ObjectValue(_, fields) = value
  use title <- result.try(required(fields, "title", typed.string()))
  use items_value <- result.try(field(fields, "items"))
  use items <- result.try(case items_value {
    Some(types.ArrayValue(identifier, values)) if identifier == items_type ->
      list.try_map(values, fn(value) {
        typed.decode_node(item_decoder(), value)
      })
    Some(_) ->
      Error(typed.DecodeFailed("checklist items have an invalid value"))
    None -> Error(typed.DecodeFailed("checklist field items is absent"))
  })
  use _ <- result.try(
    checklist.validate_unique_ids(items)
    |> result.map_error(typed.DecodeFailed),
  )
  Ok(checklist.Checklist(title, items))
}

fn decode_item(value: types.TreeValue) -> Result(checklist.Item, typed.Error) {
  let assert types.ObjectValue(_, fields) = value
  use id <- result.try(required(fields, "id", typed.string()))
  use text <- result.try(required(fields, "text", typed.string()))
  use completed <- result.try(required(fields, "completed", typed.boolean()))
  Ok(checklist.Item(id, text, completed))
}

fn encode_checklist(
  input: ChecklistInput,
) -> Result(types.TreeValue, typed.Error) {
  use items <- result.try(list.try_map(input.items, encode_item))
  Ok(
    types.ObjectValue(checklist_type, [
      #("title", types.StringValue(input.title)),
      #("items", types.ArrayValue(items_type, items)),
    ]),
  )
}

fn encode_item(input: ItemInput) -> Result(types.TreeValue, typed.Error) {
  use text <- result.try(
    checklist.normalize_text(input.text)
    |> result.map_error(typed.DecodeFailed),
  )
  Ok(
    types.ObjectValue(item_type, [
      #("id", types.StringValue(input.id)),
      #("text", types.StringValue(text)),
      #("completed", types.BooleanValue(input.completed)),
    ]),
  )
}

fn required(
  fields: List(#(String, types.TreeValue)),
  key: String,
  codec: typed.Codec(value),
) -> Result(value, typed.Error) {
  use value <- result.try(field(fields, key))
  case value {
    Some(value) -> typed.decode(codec, value)
    None -> Error(typed.DecodeFailed("checklist field " <> key <> " is absent"))
  }
}

fn field(
  fields: List(#(String, types.TreeValue)),
  key: String,
) -> Result(Option(types.TreeValue), typed.Error) {
  case list.key_find(fields, key) {
    Ok(value) -> Ok(Some(value))
    Error(Nil) -> Ok(None)
  }
}
