import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import shared_tree_item_counter_lustre/schema as document_schema
import watershed/tree/types

pub type Action {
  Insert
  Remove
}

pub fn decode(value: types.TreeValue) -> Result(List(String), String) {
  case value {
    types.ArrayValue(identifier, values)
      if identifier == document_schema.array_type
    ->
      list.try_map(values, fn(value) {
        case value {
          types.StringValue(text) -> Ok(text)
          _ -> Error("SharedTree array contains a non-string value")
        }
      })
    _ -> Error("SharedTree root is not the expected string array")
  }
}

// docs:snippet-start item-counter-watershed-edits
pub fn prepare(
  value: types.TreeValue,
  action: Action,
) -> Result(Option(types.Edit), String) {
  use values <- result.try(decode(value))
  case action, values {
    Insert, _ -> Ok(Some(types.ArrayInsert([], 0, [types.StringValue("")])))
    Remove, [] -> Ok(None)
    Remove, [_, ..] -> Ok(Some(types.ArrayRemove([], 0, 1)))
  }
}
// docs:snippet-end item-counter-watershed-edits
