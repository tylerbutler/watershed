import gleam/option.{None, Some}
import shared_tree_cli
import shared_tree_cli/schema as note
import startest
import startest/expect
import watershed/tree/schema
import watershed/tree/schema_builder as builder
import watershed/tree/types

pub fn main() -> Nil {
  startest.run(startest.default_config())
}

pub fn initial_tree_matches_view_test() -> Nil {
  let initial = note.initial()
  let assert Ok(Some(encoded)) = builder.encode_new(note.compiled(), initial)
  encoded
  |> expect.to_equal(
    types.ObjectValue("shared_tree_cli.Note", [
      #("title", types.StringValue("Created without an SDK seed")),
    ]),
  )
  builder.decode(note.compiled(), Some(encoded))
  |> expect.to_equal(Ok(note.Note("Created without an SDK seed", None)))
  schema.validate_root_field(note.stored(), Some(encoded))
  |> expect.to_equal(Ok(Nil))
  schema.can_view(note.stored(), note.view()) |> expect.to_equal(Ok(Nil))
}

pub fn optional_note_can_be_absent_test() -> Nil {
  schema.validate_field(note.stored(), "shared_tree_cli.Note", "note", None)
  |> expect.to_equal(Ok(Nil))
}

pub fn compiled_creation_preserves_the_declared_document_test() -> Nil {
  let compiled = note.compiled()
  let initial = note.Note("Created", Some("Present"))
  let assert Ok(Some(encoded)) = builder.encode_new(compiled, initial)
  schema.validate_root_field(note.stored(), Some(encoded))
  |> expect.to_equal(Ok(Nil))
  builder.decode(compiled, Some(encoded)) |> expect.to_equal(Ok(initial))
}

pub fn title_descriptor_matches_schema_test() -> Nil {
  let #(key, _) = builder.property_definition(note.title())
  key |> expect.to_equal("title")
  let assert Ok(compiled) =
    note.title() |> builder.property_root |> builder.compile
  builder.encode(compiled, "Edited")
  |> expect.to_equal(Ok(Some(types.StringValue("Edited"))))
}

pub fn incompatible_root_is_rejected_test() -> Nil {
  schema.validate_root(note.stored(), types.StringValue("not an object"))
  |> expect.to_be_error()
  builder.decode(note.compiled(), Some(types.StringValue("not an object")))
  |> expect.to_be_error()
  Nil
}

pub fn command_parsing_test() -> Nil {
  shared_tree_cli.parse(["create"])
  |> expect.to_equal(Ok(shared_tree_cli.Create))
  shared_tree_cli.parse(["open", "doc"])
  |> expect.to_equal(Ok(shared_tree_cli.Open("doc")))
  shared_tree_cli.parse(["set-title", "doc", "New title"])
  |> expect.to_equal(Ok(shared_tree_cli.SetTitle("doc", "New title")))
  shared_tree_cli.parse([]) |> expect.to_be_error()
  shared_tree_cli.parse(["open"]) |> expect.to_be_error()
  shared_tree_cli.parse(["open", ""]) |> expect.to_be_error()
  shared_tree_cli.parse(["create", "doc"]) |> expect.to_be_error()
  Nil
}
