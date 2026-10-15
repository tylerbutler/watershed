import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import shared_tree_item_counter_lustre/schema as document_schema
import watershed/tree/schema_builder as builder
import watershed/tree/types

pub type Action {
  Insert
  Remove
}

pub fn decode(value: types.TreeValue) -> Result(List(String), String) {
  use compiled <- result.try(
    document_schema.definition() |> result.map_error(string.inspect),
  )
  builder.decode(compiled, Some(value)) |> result.map_error(string.inspect)
}

// docs:snippet-start item-counter-watershed-edits
// Prepare the edits that StringArray.insertNew and removeFirst apply directly.
pub fn prepare(
  value: types.TreeValue,
  action: Action,
) -> Result(Option(types.Edit), String) {
  // Check the snapshot before preparing an edit. [] addresses the root.
  use values <- result.try(decode(value))
  case action, values {
    // Equivalent to insertAtStart("").
    Insert, _ -> Ok(Some(types.ArrayInsert([], 0, [types.StringValue("")])))
    // Equivalent to the length guard followed by removeAt(0).
    Remove, [] -> Ok(None)
    Remove, [_, ..] -> Ok(Some(types.ArrayRemove([], 0, 1)))
  }
}
// docs:snippet-end item-counter-watershed-edits
