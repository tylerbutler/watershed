import watershed/tree/schema_builder as builder

pub type Note {
  Note(count: Int)
}

pub fn invalid() -> builder.Property(Note, String) {
  builder.required("count", builder.string(), fn(note: Note) { note.count })
}
