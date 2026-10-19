import gleam/option.{type Option, None}
import watershed/tree/schema_builder as builder

pub type Note {
  Note(title: String, note: Option(String))
}

pub fn title() -> builder.Property(Note, String) {
  builder.required(key: "title", node: builder.string(), get: fn(note: Note) {
    note.title
  })
}

pub fn configuration() -> builder.Root(Note) {
  builder.object2(
    builder.factory(scope: "shared_tree_cli"),
    "Note",
    Note,
    title(),
    builder.optional(key: "note", node: builder.string(), get: fn(note: Note) {
      note.note
    }),
  )
  |> builder.root
}

pub fn initial() -> Note {
  Note("Created without an SDK seed", None)
}
