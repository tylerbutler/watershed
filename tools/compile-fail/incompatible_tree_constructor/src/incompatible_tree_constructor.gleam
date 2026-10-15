import gleam/int
import watershed/tree/schema_builder as builder

pub type Note {
  Note(count: Int)
}

pub fn invalid() -> builder.Node(Note) {
  builder.object1(
    builder.factory("com.example"),
    "Note",
    Note,
    builder.required("count", builder.string(), fn(note: Note) {
      int.to_string(note.count)
    }),
  )
}
