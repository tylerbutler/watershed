//// The board's note record and its register codec.
////
//// `notes` is an OR-map in RegisterMode, and register leaves hold **strings**,
//// so a note crosses the wire as a JSON-encoded string value:
////
//// ```json
//// { "text": "deploys are still scary", "column": "to_improve",
////   "author": "web-4821", "created": 1754… }
//// ```
////
//// The codec is deliberately asymmetric — `to_json` on the way in (the app
//// writes with `or_map_set_json`, which stringifies), `from_register(String)`
//// on the way out (`or_map_value` hands back the raw register string). There
//// is no `from_json`: that shape belongs to sequence elements, and keeping it
//// absent makes the one-way stringification visible at the call sites.
////
//// Decoding is total on purpose: a peer on an older build or a hand-edited
//// document can leave a value here that doesn't parse. The fallback's empty
//// `column` routes it to the board's "unfiled" strip — visible, never
//// crashing, never misfiled into a real column.

import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}

pub type Note {
  Note(
    text: String,
    /// The authoritative column id (`column.id`), kept as the raw wire string
    /// so unknown ids can be routed to "unfiled" rather than dropped.
    column: String,
    author: String,
    /// Client wall-clock ms. Used **only** as a render tiebreaker for notes
    /// that are not (yet) in a column sequence — it is not trusted for
    /// ordering across clients; the sequences are the ordering authority.
    created: Int,
  )
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

/// Decode a raw register value, falling back to a visible placeholder so one
/// malformed note can't take the board down.
pub fn from_register(value: String) -> Note {
  case json.parse(value, decoder()) {
    Ok(note) -> note
    Error(_) ->
      Note(text: "(unreadable note)", column: "", author: "—", created: 0)
  }
}
