import gleam/option.{None, Some}
import shared_tree_cli
import shared_tree_cli/schema as note
import startest
import startest/expect
import watershed/tree/schema
import watershed/tree/types

pub fn main() -> Nil {
  startest.run(startest.default_config())
}

pub fn initial_tree_matches_view_test() -> Nil {
  schema.validate_root_field(note.stored(), Some(note.initial()))
  |> expect.to_equal(Ok(Nil))
  schema.can_view(note.stored(), note.view()) |> expect.to_equal(Ok(Nil))
}

pub fn optional_note_can_be_absent_test() -> Nil {
  schema.validate_field(note.stored(), "shared_tree_cli.Note", "note", None)
  |> expect.to_equal(Ok(Nil))
}

pub fn incompatible_root_is_rejected_test() -> Nil {
  schema.validate_root(note.stored(), types.StringValue("not an object"))
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
