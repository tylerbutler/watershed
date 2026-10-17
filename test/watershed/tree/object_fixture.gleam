import gleam/dict.{type Dict}
import gleam/option.{type Option, Some}
import gleam/result
import watershed/handle
import watershed/tree/schema_builder as builder

pub type Child {
  Child(id: builder.Identifier, text: String)
}

pub type Root {
  Root(
    title: String,
    note: Option(String),
    maybe_null: Option(Nil),
    nothing: Nil,
    handle: handle.Reference,
    child: Child,
    optional_child: Option(Child),
    items: List(Child),
    other_items: List(Child),
    entries: Dict(String, Child),
  )
}

fn factory() -> builder.Factory {
  builder.factory("org.watershed.typed")
}

pub fn child_id() -> builder.Property(Child, builder.Identifier) {
  builder.identifier("id", fn(value: Child) { value.id })
}

pub fn child_text() -> builder.Property(Child, String) {
  builder.required("text", builder.string(), fn(value: Child) { value.text })
}

pub fn child_node() -> builder.Node(Child) {
  builder.object2(factory(), "Child", Child, child_id(), child_text())
}

pub fn title() -> builder.Property(Root, String) {
  builder.required("title", builder.string(), fn(value: Root) { value.title })
}

pub fn note() -> builder.Property(Root, Option(String)) {
  builder.optional("note", builder.string(), fn(value: Root) { value.note })
}

pub fn maybe_null() -> builder.Property(Root, Option(Nil)) {
  builder.optional("maybeNull", builder.null(), fn(value: Root) {
    value.maybe_null
  })
}

pub fn nothing() -> builder.Property(Root, Nil) {
  builder.required("nothing", builder.null(), fn(value: Root) { value.nothing })
}

pub fn handle_field() -> builder.Property(Root, handle.Reference) {
  builder.required("handle", builder.handle(), fn(value: Root) { value.handle })
}

pub fn child() -> builder.Property(Root, Child) {
  builder.required("child", child_node(), fn(value: Root) { value.child })
}

pub fn optional_child() -> builder.Property(Root, Option(Child)) {
  builder.optional("optionalChild", child_node(), fn(value: Root) {
    value.optional_child
  })
}

fn array() -> builder.Node(List(Child)) {
  builder.array(factory(), "Items", child_node())
}

pub fn items() -> builder.Property(Root, List(Child)) {
  builder.required("items", array(), fn(value: Root) { value.items })
}

pub fn other_items() -> builder.Property(Root, List(Child)) {
  builder.required("otherItems", array(), fn(value: Root) { value.other_items })
}

pub fn entries() -> builder.Property(Root, Dict(String, Child)) {
  builder.required(
    "entries",
    builder.map(factory(), "Entries", child_node()),
    fn(value: Root) { value.entries },
  )
}

pub fn node() -> builder.Node(Root) {
  builder.object(
    factory(),
    "Root",
    [
      builder.property(title()),
      builder.property(note()),
      builder.property(maybe_null()),
      builder.property(nothing()),
      builder.property(handle_field()),
      builder.property(child()),
      builder.property(optional_child()),
      builder.property(items()),
      builder.property(other_items()),
      builder.property(entries()),
    ],
    fn(reader) {
      use title <- result.try(builder.read_property(reader, title()))
      use note <- result.try(builder.read_property(reader, note()))
      use maybe_null <- result.try(builder.read_property(reader, maybe_null()))
      use nothing <- result.try(builder.read_property(reader, nothing()))
      use handle <- result.try(builder.read_property(reader, handle_field()))
      use child <- result.try(builder.read_property(reader, child()))
      use optional_child <- result.try(builder.read_property(
        reader,
        optional_child(),
      ))
      use items <- result.try(builder.read_property(reader, items()))
      use other_items <- result.try(builder.read_property(reader, other_items()))
      use entries <- result.try(builder.read_property(reader, entries()))
      Ok(Root(
        title,
        note,
        maybe_null,
        nothing,
        handle,
        child,
        optional_child,
        items,
        other_items,
        entries,
      ))
    },
  )
}

pub fn initial() -> Root {
  let assert Ok(reference) = handle.reference_from_path("/A/root")
  Root(
    title: "Title",
    note: Some("Note"),
    maybe_null: Some(Nil),
    nothing: Nil,
    handle: reference,
    child: Child(builder.Assigned("child"), "Child"),
    optional_child: Some(Child(builder.Assigned("optional"), "Optional")),
    items: [
      Child(builder.Assigned("first"), "First"),
      Child(builder.Assigned("second"), "Second"),
    ],
    other_items: [],
    entries: dict.from_list([
      #("first", Child(builder.Assigned("mapped"), "Mapped")),
    ]),
  )
}
