import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import watershed/tree
import watershed/tree/error

pub type Item {
  Item(id: String, text: String, completed: Bool)
}

pub type Checklist {
  Checklist(title: String, items: List(Item))
}

pub fn empty() -> Checklist {
  Checklist("SharedTree checklist", [])
}

pub fn normalize_text(text: String) -> Result(String, String) {
  case string.trim(text) {
    "" -> Error("checklist item text is empty")
    text -> Ok(text)
  }
}

pub fn validate_unique_ids(items: List(Item)) -> Result(Nil, String) {
  unique_ids(items, [])
}

pub fn new_item(
  id: String,
  text: String,
  completed: Bool,
) -> Result(Item, String) {
  normalize_text(text) |> result.map(fn(text) { Item(id, text, completed) })
}

pub fn nodes(
  array: tree.Ref(List(Item)),
) -> Result(List(tree.Ref(Item)), error.Error) {
  use values <- result.try(tree.read(array))
  values
  |> list.index_map(fn(_, index) { index })
  |> list.try_map(fn(index) {
    use node <- result.try(tree.array_node(array, index))
    case node {
      Some(node) -> Ok(node)
      None ->
        Error(error.RuntimeFailure("The checklist changed while it was read"))
    }
  })
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
