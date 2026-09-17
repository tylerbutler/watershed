import gleam/list

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

pub fn component_model() -> List(Doc) {
  [
    Doc(
      "components",
      "Components and catalogs",
      "Let users, not the author, decide what is on the page: package each part of the app behind a versioned descriptor so it can be rebuilt from a saved document, and keep unlike parts in one catalog.",
      "Descriptor · Catalog · register · find · start",
    ),
    Doc(
      "ports",
      "Ports and dispatch",
      "Let a user connect two parts that were written apart: a port is a named connection point a component publishes, typed while you write it, erased once it is stored, and checked again before every event it carries.",
      "Output · Input · EffectiveGraph · LocalIntent · Delivery",
    ),
    Doc(
      "workspaces",
      "Workspaces and instances",
      "Save the finished board — which parts exist, where they sit, how they are wired — and reopen it safely next year, without deleting the parts this build cannot understand.",
      "ManifestEntry · Snapshot · Prepared · delete_instance",
    ),
  ]
}

pub fn for_path(path: String) -> List(Doc) {
  case path {
    "/component-model" -> component_model()
    _ -> all()
  }
}

pub fn get(slug: String) -> Result(Doc, Nil) {
  list.find(all(), fn(item) { item.slug == slug })
}

pub fn neighbours(slug: String) -> #(Result(Doc, Nil), Result(Doc, Nil)) {
  let assert [schema, topology, lifecycle] = all()
  case slug {
    "schema" -> #(Error(Nil), Ok(topology))
    "topology" -> #(Ok(schema), Ok(lifecycle))
    "lifecycle" -> #(Ok(topology), Error(Nil))
    _ -> #(Error(Nil), Error(Nil))
  }
}
