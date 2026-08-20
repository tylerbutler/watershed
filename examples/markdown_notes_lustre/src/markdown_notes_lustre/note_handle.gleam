//// The read half of the handle-in-register round trip.
////
//// A note's `SharedText` handle is stored with
//// `or_map_set_json(notes, name, text_handle_of(text))`, and `or_map_set_json`
//// stringifies — so the register reads back as the handle marker's JSON
//// *string*, while `resolve_text` takes a `Json` value. This module bridges
//// the two: parse the register string's flat object and re-encode it.
////
//// Strictness stays in the library: `resolve_text` rejects anything that is
//// not exactly a handle marker, so this parse only has to be faithful, not
//// suspicious. A register that is not a flat string-valued object cannot be a
//// handle marker and is reported as corrupt (`Error(Nil)`).

import gleam/dict
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/result

pub fn parse(register: String) -> Result(Json, Nil) {
  json.parse(register, decode.dict(decode.string, decode.string))
  |> result.map(fn(fields) {
    json.object(
      dict.to_list(fields)
      |> list.map(fn(field) { #(field.0, json.string(field.1)) }),
    )
  })
  |> result.replace_error(Nil)
}
