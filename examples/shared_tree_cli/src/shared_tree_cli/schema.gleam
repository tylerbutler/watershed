import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import watershed/tree/schema
import watershed/tree/typed
import watershed/tree/types

const note_type = "shared_tree_cli.Note"

const definition_json = "{\"version\":2,\"nodes\":{
  \"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},
  \"shared_tree_cli.Note\":{\"kind\":{\"object\":{
    \"title\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]},
    \"note\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\"]}
  }}}
},\"root\":{\"kind\":\"Value\",\"types\":[\"shared_tree_cli.Note\"]}}"

pub type NoteSchema

pub type Note {
  Note(title: String, note: Option(String))
}

pub fn stored() -> schema.StoredSchema {
  let assert Ok(stored) = schema.stored_from_string(definition_json)
  stored
}

pub fn view() -> schema.ViewSchema {
  let assert Ok(view) = schema.view_from_string(definition_json)
  view
}

pub fn definition() -> typed.Schema(NoteSchema, Note) {
  let assert Ok(value) = typed.schema(view(), decoder())
  value
}

pub fn decoder() -> typed.NodeCodec(NoteSchema, Note) {
  let assert Ok(value) = typed.node(note_type, decode_note)
  value
}

pub fn builder() -> typed.Builder(NoteSchema, Note) {
  let assert Ok(value) = typed.builder(note_type, encode_note)
  value
}

pub fn initial() -> Note {
  Note("Created without an SDK seed", None)
}

pub fn title() -> typed.Field(NoteSchema, String, typed.Required) {
  typed.required("title", typed.string())
}

fn decode_note(value: types.TreeValue) -> Result(Note, typed.Error) {
  let assert types.ObjectValue(_, fields) = value
  use title <- result.try(required(fields, "title"))
  use note <- result.try(optional(fields, "note"))
  Ok(Note(title, note))
}

fn encode_note(value: Note) -> Result(types.TreeValue, typed.Error) {
  let fields = [#("title", types.StringValue(value.title))]
  let fields = case value.note {
    None -> fields
    Some(note) -> list.append(fields, [#("note", types.StringValue(note))])
  }
  Ok(types.ObjectValue(note_type, fields))
}

fn required(
  fields: List(#(String, types.TreeValue)),
  key: String,
) -> Result(String, typed.Error) {
  use value <- result.try(field(fields, key))
  case value {
    Some(value) -> typed.decode(typed.string(), value)
    None -> Error(typed.DecodeFailed("note field " <> key <> " is absent"))
  }
}

fn optional(
  fields: List(#(String, types.TreeValue)),
  key: String,
) -> Result(Option(String), typed.Error) {
  use value <- result.try(field(fields, key))
  case value {
    Some(value) -> typed.decode(typed.string(), value) |> result.map(Some)
    None -> Ok(None)
  }
}

fn field(
  fields: List(#(String, types.TreeValue)),
  key: String,
) -> Result(Option(types.TreeValue), typed.Error) {
  case list.key_find(fields, key) {
    Ok(value) -> Ok(Some(value))
    Error(Nil) -> Ok(None)
  }
}
