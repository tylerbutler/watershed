pub type Doc {
  Doc(slug: String, title: String, gloss: String, concept: String)
}

pub fn all() -> List(Doc) {
  [
    Doc(
      "schema",
      "Schemas and fields",
      "Declare the shape of a map once, at compile time, with a phantom tag the runtime never sees: a plain field, a handle to a nested map, or a handle to another channel entirely.",
      "Field · ChildField · ChannelField · FieldError",
    ),
    Doc(
      "topology",
      "Documents and handles",
      "A watershed document is not one tree — it's a root map plus whatever channels its values point to, each one independently addressed, attached, and resolved.",
      "root_typed · handle_of · create_map · resolve",
    ),
    Doc(
      "lifecycle",
      "Starting a document",
      "Every client runs the same bootstrap: get a handle, wait for the catch-up, ensure the channels it needs exist, and only render once they've all reported in.",
      "got_document · connected · ensure_* · subscribe",
    ),
  ]
}
