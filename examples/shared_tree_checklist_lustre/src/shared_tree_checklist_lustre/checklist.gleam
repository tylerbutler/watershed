import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import shared_tree_checklist_lustre/schema as document_schema
import watershed/tree/types

const checklist_type = "shared_tree_checklist.Checklist"

const items_type = "shared_tree_checklist.Items"

const item_type = "shared_tree_checklist.Item"

pub type Item {
  Item(id: String, text: String, completed: Bool)
}

pub type Checklist {
  Checklist(title: String, items: List(Item))
}

pub fn empty() -> Checklist {
  Checklist("SharedTree checklist", [])
}

pub fn decode(value: types.TreeValue) -> Result(Checklist, String) {
  case value {
    types.ObjectValue(id, fields) if id == checklist_type -> {
      use title <- result.try(string_field(fields, "title"))
      use items_value <- result.try(field(fields, "items"))
      use items <- result.try(case items_value {
        types.ArrayValue(id, values) if id == items_type ->
          list.try_map(values, decode_item)
        _ -> Error("checklist items have an invalid value")
      })
      use _ <- result.try(unique_ids(items, []))
      Ok(Checklist(title, items))
    }
    _ -> Error("SharedTree root is not a checklist")
  }
}

pub fn add(
  checklist: Checklist,
  id: String,
  text: String,
) -> Result(types.Edit, String) {
  let Checklist(items: items, ..) = checklist
  case string.trim(text) {
    "" -> Error("checklist item text is empty")
    text ->
      Ok(
        types.ArrayInsert(["items"], list.length(items), [
          document_schema.item_value(id, text, False),
        ]),
      )
  }
}

pub fn edit(
  checklist: Checklist,
  id: String,
  text: String,
) -> Result(types.Edit, String) {
  use index <- result.try(index_of(checklist, id))
  case string.trim(text) {
    "" -> Error("checklist item text is empty")
    text ->
      Ok(types.SetField(
        ["items", int.to_string(index), "text"],
        types.StringValue(text),
      ))
  }
}

pub fn toggle(checklist: Checklist, id: String) -> Result(types.Edit, String) {
  use #(index, item) <- result.try(item_at(checklist, id))
  Ok(types.SetField(
    ["items", int.to_string(index), "completed"],
    types.BooleanValue(!item.completed),
  ))
}

pub fn delete(checklist: Checklist, id: String) -> Result(types.Edit, String) {
  use index <- result.try(index_of(checklist, id))
  Ok(types.ArrayRemove(["items"], index, index + 1))
}

pub fn move_up(
  checklist: Checklist,
  id: String,
) -> Result(Option(types.Edit), String) {
  use index <- result.try(index_of(checklist, id))
  case index {
    0 -> Ok(None)
    _ ->
      Ok(
        Some(types.ArrayMove(["items"], index, index + 1, ["items"], index - 1)),
      )
  }
}

pub fn move_down(
  checklist: Checklist,
  id: String,
) -> Result(Option(types.Edit), String) {
  let Checklist(items: items, ..) = checklist
  use index <- result.try(index_of(checklist, id))
  case index == list.length(items) - 1 {
    True -> Ok(None)
    False ->
      Ok(
        Some(types.ArrayMove(["items"], index, index + 1, ["items"], index + 2)),
      )
  }
}

fn decode_item(value: types.TreeValue) -> Result(Item, String) {
  case value {
    types.ObjectValue(id, fields) if id == item_type -> {
      use item_id <- result.try(string_field(fields, "id"))
      use text <- result.try(string_field(fields, "text"))
      use completed_value <- result.try(field(fields, "completed"))
      case completed_value {
        types.BooleanValue(completed) -> Ok(Item(item_id, text, completed))
        _ -> Error("checklist item completed is not a boolean")
      }
    }
    _ -> Error("checklist item has an invalid value")
  }
}

fn string_field(
  fields: List(#(String, types.TreeValue)),
  name: String,
) -> Result(String, String) {
  use value <- result.try(field(fields, name))
  case value {
    types.StringValue(value) -> Ok(value)
    _ -> Error("checklist field " <> name <> " is not a string")
  }
}

fn field(
  fields: List(#(String, types.TreeValue)),
  name: String,
) -> Result(types.TreeValue, String) {
  case fields {
    [] -> Error("checklist field " <> name <> " is absent")
    [#(key, value), ..rest] ->
      case key == name {
        True -> Ok(value)
        False -> field(rest, name)
      }
  }
}

fn unique_ids(items: List(Item), seen: List(String)) -> Result(Nil, String) {
  case items {
    [] -> Ok(Nil)
    [item, ..rest] ->
      case list.contains(seen, item.id) {
        True -> Error("duplicate checklist item id " <> item.id)
        False -> unique_ids(rest, [item.id, ..seen])
      }
  }
}

fn index_of(checklist: Checklist, id: String) -> Result(Int, String) {
  use #(index, _) <- result.try(item_at(checklist, id))
  Ok(index)
}

fn item_at(checklist: Checklist, id: String) -> Result(#(Int, Item), String) {
  let Checklist(items: items, ..) = checklist
  find_item(items, id, 0)
}

fn find_item(
  items: List(Item),
  id: String,
  index: Int,
) -> Result(#(Int, Item), String) {
  case items {
    [] -> Error("checklist item " <> id <> " is no longer present")
    [item, ..rest] ->
      case item.id == id {
        True -> Ok(#(index, item))
        False -> find_item(rest, id, index + 1)
      }
  }
}
