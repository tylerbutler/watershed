//// The tutorial note record and its register codec.
////
//// The `notes` channel is an OR-map in RegisterMode. Each leaf is a raw
//// string, so the app writes JSON in and decodes a register string back out.

import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}

pub type Note {
  Note(
    text: String,
    /// The column id. Unknown values stay visible in `unfiled`.
    column: String,
    author: String,
    /// Client wall-clock ms. Used only as a stable render tiebreaker.
    created: Int,
  )
}

/// Stable note identity. Edits and votes use this id for the life of the note.
/// The nonce keeps two notes from one author distinct in one ms tick.
pub fn id(author: String, created: Int, nonce: Int) -> String {
  "note-"
  <> author
  <> "-"
  <> int.to_string(created)
  <> "-"
  <> int.to_string(nonce)
}

pub fn to_json(note: Note) -> Json {
  json.object([
    #("text", json.string(note.text)),
    #("column", json.string(note.column)),
    #("author", json.string(note.author)),
    #("created", json.int(note.created)),
  ])
}

pub fn decoder() -> Decoder(Note) {
  use text <- decode.field("text", decode.string)
  use column <- decode.field("column", decode.string)
  use author <- decode.field("author", decode.string)
  use created <- decode.field("created", decode.int)
  decode.success(Note(text:, column:, author:, created:))
}

/// Decode a raw register value. A bad payload stays visible and does not crash.
pub fn from_register(value: String) -> Note {
  case json.parse(value, decoder()) {
    Ok(note) -> note
    Error(_) ->
      Note(text: "(unreadable note)", column: "", author: "—", created: 0)
  }
}
