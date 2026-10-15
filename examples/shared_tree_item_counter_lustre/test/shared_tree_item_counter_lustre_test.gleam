import gleam/option.{None, Some}
import gleeunit
import shared_tree_item_counter_lustre/counter
import shared_tree_item_counter_lustre/schema as document_schema
import watershed/tree/schema
import watershed/tree/typed
import watershed/tree/types

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn initial_root_is_a_valid_empty_string_array_test() {
  let assert Ok(Nil) =
    schema.validate_root(document_schema.stored(), document_schema.initial())
  let assert Ok([]) = counter.decode(document_schema.initial())
}

pub fn typed_creation_preserves_the_original_root_schema_test() {
  let assert Ok(value) =
    typed.build(document_schema.builder(), document_schema.initial())
  let stored =
    document_schema.declaration()
    |> typed.schema_view
    |> schema.view_to_stored
  let assert Ok(Nil) = schema.validate_root(stored, value)
  let assert Error(_) =
    typed.build(document_schema.builder(), types.StringValue("not an array"))
}

pub fn typed_string_items_reject_non_string_values_test() {
  let assert Ok(value) = typed.build(document_schema.item_builder(), "")
  let assert types.StringValue("") = value
  let assert Ok("") = typed.decode_node(document_schema.item_decoder(), value)
  let assert Error(_) =
    typed.decode_node(document_schema.item_decoder(), types.NumberValue(1.0))
}

pub fn insert_matches_the_fluid_insert_at_start_test() {
  let assert Ok(Some(types.ArrayInsert([], 0, [types.StringValue("")]))) =
    counter.prepare(document_schema.initial(), counter.Insert)
}

pub fn remove_empty_is_a_no_op_test() {
  let assert Ok(None) =
    counter.prepare(document_schema.initial(), counter.Remove)
}

pub fn remove_targets_the_first_entry_only_test() {
  let value =
    types.ArrayValue("shared_tree_item_counter.StringArray", [
      types.StringValue("first"),
      types.StringValue("second"),
    ])
  let assert Ok(["first", "second"]) = counter.decode(value)
  let assert Ok(Some(types.ArrayRemove([], 0, 1))) =
    counter.prepare(value, counter.Remove)
}

pub fn malformed_roots_do_not_turn_into_zero_test() {
  let assert Error(_) = counter.decode(types.StringValue("not an array"))
  let assert Error(_) = counter.decode(types.ArrayValue("wrong.Array", []))
  let assert Error(_) =
    counter.decode(
      types.ArrayValue("shared_tree_item_counter.StringArray", [
        types.NumberValue(1.0),
      ]),
    )
}
