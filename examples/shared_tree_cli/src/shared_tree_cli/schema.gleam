import gleam/option.{type Option, None}
import watershed/tree/schema
import watershed/tree/schema_builder as builder

pub type Note {
  Note(title: String, note: Option(String))
}

pub fn title() -> builder.Property(Note, String) {
  builder.required("title", builder.string(), fn(note: Note) { note.title })
}

pub fn compiled() -> builder.Compiled(Note) {
  let assert Ok(compiled) =
    builder.object2(
      builder.factory("shared_tree_cli"),
      "Note",
      Note,
      title(),
      builder.optional("note", builder.string(), fn(note: Note) { note.note }),
    )
    |> builder.root
    |> builder.compile
  compiled
}

pub fn stored() -> schema.StoredSchema {
  builder.stored(compiled())
}

pub fn view() -> schema.ViewSchema {
  builder.view(compiled())
}

pub fn initial() -> Note {
  Note("Created without an SDK seed", None)
}
