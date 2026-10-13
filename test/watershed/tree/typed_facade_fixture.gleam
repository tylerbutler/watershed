import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import watershed/handle
import watershed/tree/schema
import watershed/tree/typed
import watershed/tree/types

pub const root_type = "org.watershed.typed.Root"

pub const child_type = "org.watershed.typed.Child"

pub const items_type = "org.watershed.typed.Items"

pub const entries_type = "org.watershed.typed.Entries"

const raw_definition = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.handle\":{\"kind\":{\"leaf\":3}},\"com.fluidframework.leaf.null\":{\"kind\":{\"leaf\":4}},\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"org.watershed.typed.Child\":{\"kind\":{\"object\":{\"id\":{\"kind\":\"Identifier\",\"types\":[\"com.fluidframework.leaf.string\"]},\"text\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}}},\"org.watershed.typed.Entries\":{\"kind\":{\"map\":{\"kind\":\"Optional\",\"types\":[\"org.watershed.typed.Child\"]}}},\"org.watershed.typed.Items\":{\"kind\":{\"object\":{\"\":{\"kind\":\"Sequence\",\"types\":[\"org.watershed.typed.Child\"]}}}},\"org.watershed.typed.Root\":{\"kind\":{\"object\":{\"child\":{\"kind\":\"Value\",\"types\":[\"org.watershed.typed.Child\"]},\"entries\":{\"kind\":\"Value\",\"types\":[\"org.watershed.typed.Entries\"]},\"handle\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.handle\"]},\"items\":{\"kind\":\"Value\",\"types\":[\"org.watershed.typed.Items\"]},\"maybeNull\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.null\"]},\"note\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\"]},\"nothing\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.null\"]},\"title\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"org.watershed.typed.Root\"]}}"

pub type Root

pub type Child

pub type RootState {
  RootState(title: String)
}

pub type ChildState {
  ChildState(id: String, text: String)
}

pub type ChildInput {
  ChildInput(id: Option(String), text: String)
}

pub type RootInput {
  RootInput(
    title: String,
    note: Option(String),
    maybe_null: Option(Nil),
    handle: handle.Reference,
    child: ChildInput,
    items: List(ChildInput),
    entries: List(#(String, ChildInput)),
  )
}

pub fn view() -> schema.ViewSchema {
  let assert Ok(value) = schema.view_from_string(raw_definition)
  value
}

pub fn stored() -> schema.StoredSchema {
  schema.view_to_stored(view())
}

pub fn root_codec() -> typed.NodeCodec(Root, RootState) {
  let assert Ok(value) =
    typed.node(root_type, fn(value) {
      let assert types.ObjectValue(_, fields) = value
      use title <- result.try(required(fields, "title", typed.string()))
      Ok(RootState(title: title))
    })
  value
}

pub fn root_builder() -> typed.Builder(Root, RootInput) {
  let assert Ok(value) =
    typed.builder(root_type, fn(input: RootInput) {
      let fields =
        list.flatten([
          [#("title", types.StringValue(input.title))],
          optional("note", input.note, types.StringValue),
          optional("maybeNull", input.maybe_null, fn(_) { types.NullValue }),
          [
            #("nothing", types.NullValue),
            #("handle", types.HandleValue(input.handle)),
            #("child", encode_child(input.child)),
            #(
              "items",
              types.ArrayValue(items_type, list.map(input.items, encode_child)),
            ),
            #(
              "entries",
              types.MapValue(
                entries_type,
                list.map(input.entries, fn(entry) {
                  #(entry.0, encode_child(entry.1))
                }),
              ),
            ),
          ],
        ])
      Ok(types.ObjectValue(root_type, fields))
    })
  value
}

pub fn definition() -> typed.Schema(Root, RootState) {
  let assert Ok(value) = typed.schema(view(), root_codec())
  value
}

pub fn initial_root() -> types.TreeValue {
  let assert Ok(reference) = handle.reference_from_path("/A/root")
  let assert Ok(value) =
    typed.build(
      root_builder(),
      RootInput(
        title: "Title",
        note: Some("Note"),
        maybe_null: Some(Nil),
        handle: reference,
        child: ChildInput(Some("child"), "Child"),
        items: [
          ChildInput(Some("first"), "First"),
          ChildInput(Some("second"), "Second"),
        ],
        entries: [#("first", ChildInput(Some("mapped"), "Mapped"))],
      ),
    )
  value
}

pub fn child_codec() -> typed.NodeCodec(Child, ChildState) {
  let assert Ok(value) =
    typed.node(child_type, fn(value) {
      let assert types.ObjectValue(_, fields) = value
      use id <- result.try(required(fields, "id", typed.string()))
      use text <- result.try(required(fields, "text", typed.string()))
      Ok(ChildState(id:, text:))
    })
  value
}

pub fn child_builder() -> typed.Builder(Child, ChildInput) {
  let assert Ok(value) =
    typed.builder(child_type, fn(input: ChildInput) { Ok(encode_child(input)) })
  value
}

pub fn title() -> typed.Field(Root, String, typed.Required) {
  typed.required("title", typed.string())
}

pub fn note() -> typed.Field(Root, String, typed.Optional) {
  typed.optional("note", typed.string())
}

pub fn maybe_null() -> typed.Field(Root, Nil, typed.Optional) {
  typed.optional("maybeNull", typed.null())
}

pub fn nothing() -> typed.Field(Root, Nil, typed.Required) {
  typed.required("nothing", typed.null())
}

pub fn handle_field() -> typed.Field(Root, handle.Reference, typed.Required) {
  typed.required("handle", typed.handle())
}

pub fn child() -> typed.ChildField(Root, Child, ChildState, typed.Required) {
  typed.required_child("child", child_codec())
}

pub fn items() -> typed.ArrayField(Root, Child, ChildState) {
  typed.array_field("items", items_type, child_codec())
}

pub fn entries() -> typed.MapField(Root, Child, ChildState) {
  typed.map_field("entries", entries_type, child_codec())
}

pub fn child_id() -> typed.IdentifierField(Child) {
  typed.identifier("id")
}

pub fn child_text() -> typed.Field(Child, String, typed.Required) {
  typed.required("text", typed.string())
}

fn encode_child(input: ChildInput) -> types.TreeValue {
  let fields = case input.id {
    None -> [#("text", types.StringValue(input.text))]
    Some(id) -> [
      #("id", types.StringValue(id)),
      #("text", types.StringValue(input.text)),
    ]
  }
  types.ObjectValue(child_type, fields)
}

fn optional(
  key: String,
  value: Option(a),
  encode: fn(a) -> types.TreeValue,
) -> List(#(String, types.TreeValue)) {
  case value {
    None -> []
    Some(value) -> [#(key, encode(value))]
  }
}

fn required(
  fields: List(#(String, types.TreeValue)),
  key: String,
  codec: typed.Codec(a),
) -> Result(a, typed.Error) {
  case list.key_find(fields, key) {
    Ok(value) -> typed.decode(codec, value)
    Error(Nil) -> Error(typed.MissingRequired(key))
  }
}
