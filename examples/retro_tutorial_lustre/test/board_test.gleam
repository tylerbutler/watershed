//// Canonical board state stays deterministic.

import gleam/list
import gleeunit/should

import retro_tutorial_lustre/board.{NoteCard}
import retro_tutorial_lustre/note.{type Note, Note}

fn note_in(column: String, created: Int, text: String) -> Note {
  Note(text: text, column: column, author: "web-1", created: created)
}

fn total_occurrences(snapshot: board.Snapshot, id: String) -> Int {
  [
    snapshot.went_well,
    snapshot.to_improve,
    snapshot.action_items,
    snapshot.unfiled,
  ]
  |> list.flatten
  |> list.count(fn(card) { card.id == id })
}

pub fn notes_group_by_column_and_sort_by_created_then_id_test() -> Nil {
  let snapshot =
    board.snapshot(
      "Sprint retro",
      [
        #("note-z", note_in("went_well", 2, "later")),
        #("note-b", note_in("went_well", 1, "first")),
        #("note-a", note_in("went_well", 2, "tie")),
      ],
      [],
    )

  snapshot.went_well
  |> list.map(fn(card) { card.id })
  |> should.equal(["note-b", "note-a", "note-z"])
}

pub fn tallies_attach_to_matching_notes_and_orphans_are_ignored_test() -> Nil {
  let snapshot =
    board.snapshot(
      "Sprint retro",
      [#("note-1", note_in("action_items", 1, "ship docs"))],
      [#("gone", 7), #("note-1", 2)],
    )

  snapshot.action_items
  |> should.equal([
    NoteCard(
      id: "note-1",
      note: note_in("action_items", 1, "ship docs"),
      votes: 2,
    ),
  ])
  total_occurrences(snapshot, "gone") |> should.equal(0)
}

pub fn unknown_columns_route_to_unfiled_test() -> Nil {
  let snapshot =
    board.snapshot(
      "Sprint retro",
      [
        #("note-2", note_in("parking_lot", 2, "future column")),
        #("note-1", note_in("", 1, "bad payload")),
      ],
      [],
    )

  snapshot.unfiled
  |> list.map(fn(card) { card.id })
  |> should.equal(["note-1", "note-2"])
}
