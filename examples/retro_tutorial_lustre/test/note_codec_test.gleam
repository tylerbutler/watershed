//// Round-trips for the tutorial note register codec.

import gleam/json
import gleam/list
import gleeunit/should

import retro_tutorial_lustre/note.{type Note, Note}

fn round_trip(entry: Note) -> Note {
  note.to_json(entry)
  |> json.to_string
  |> note.from_register
}

pub fn notes_round_trip_through_the_register_test() -> Nil {
  [
    Note(
      text: "deploys felt calm for once",
      column: "went_well",
      author: "web-4821",
      created: 1_754_000_000_000,
    ),
    Note(
      text: "line one\nline two",
      column: "to_improve",
      author: "web-1",
      created: 1,
    ),
    Note(
      text: "🎉 retro emoji",
      column: "action_items",
      author: "🦊",
      created: 42,
    ),
    Note(text: "", column: "", author: "", created: -1),
  ]
  |> list.each(fn(entry) { round_trip(entry) |> should.equal(entry) })
}

pub fn generated_ids_stay_stable_for_the_same_inputs_test() -> Nil {
  note.id("web-1", 17, 99)
  |> should.equal(note.id("web-1", 17, 99))
}

pub fn garbage_registers_fall_back_to_a_visible_placeholder_test() -> Nil {
  ["not json", "{\"text\": \"missing fields\"}", ""]
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
