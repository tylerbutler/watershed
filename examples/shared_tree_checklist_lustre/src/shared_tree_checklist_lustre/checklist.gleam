import gleam/list
import gleam/string

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
