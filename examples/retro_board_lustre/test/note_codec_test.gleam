//// Round-trips for the note register codec.
////
//// The write path is `to_json |> json.to_string` (what `or_map_set_json`
//// does); the read path is `from_register` on the raw register string. The
//// table leans on text that has broken JSON codecs before: quotes, newlines,
//// emoji, and the empty-ish edges.

import gleam/json
import gleam/list
import gleeunit/should

import note.{type Note, Note}

fn round_trip(entry: Note) -> Note {
  note.to_json(entry)
  |> json.to_string
  |> note.from_register
}

pub fn notes_round_trip_through_the_register_test() {
  [
    Note(
      text: "deploys are still scary",
      column: "to_improve",
      author: "web-4821",
      created: 1_754_000_000_000,
    ),
    Note(
      text: "she said \"ship it\" and we did",
      column: "went_well",
      author: "web-1",
      created: 1,
    ),
    Note(
      text: "line one\nline two\n\ttabbed",
      column: "action_items",
      author: "web-2",
      created: 0,
    ),
    Note(
      text: "🎉 retro emoji 🚀✨",
      column: "went_well",
      author: "🦊",
      created: 42,
    ),
    Note(text: "", column: "", author: "", created: -1),
  ]
  |> list.each(fn(entry) { round_trip(entry) |> should.equal(entry) })
}

pub fn garbage_registers_fall_back_to_a_visible_placeholder_test() {
  [
    "not json at all",
    "{\"text\": \"missing the rest\"}",
    "{\"text\": 7, \"column\": \"went_well\", \"author\": \"a\", \"created\": 1}",
    "",
  ]
  |> list.each(fn(raw) {
    note.from_register(raw)
    |> should.equal(Note(
      text: "(unreadable note)",
      column: "",
      author: "—",
      created: 0,
    ))
  })
}

/// The fallback's empty `column` is load-bearing: it is what routes a corrupt
/// register to the board's "unfiled" strip instead of a real column.
pub fn fallback_column_is_not_a_real_column_test() {
  note.from_register("junk").column |> should.equal("")
}
