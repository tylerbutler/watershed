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
