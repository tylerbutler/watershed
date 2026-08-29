//// Shared board helpers for the tutorial example.
////
//// The UI and the deterministic tests call these same map writes.
//// Each helper takes only the channel it needs.

import gleam/list

import watershed.{type OrMap}
import watershed/or_map_kernel

import retro_tutorial_lustre/board.{type Column}
import retro_tutorial_lustre/note.{type Note, Note}

pub fn add_note(
  notes: OrMap,
  author: String,
  text: String,
  column: Column,
  created: Int,
  nonce: Int,
) -> String {
  let id = note.id(author, created, nonce)
  let entry =
    Note(
      text: text,
      column: board.column_id(column),
      author: author,
      created: created,
    )
  watershed.or_map_set_json(notes, id, note.to_json(entry))
  id
}

pub fn upvote(votes: OrMap, id: String) -> Nil {
  change_votes(votes, id, 1)
}

pub fn downvote(votes: OrMap, id: String) -> Nil {
  change_votes(votes, id, -1)
}

fn change_votes(votes: OrMap, id: String, amount: Int) -> Nil {
  watershed.or_map_increment(votes, id, amount)
}

/// Read the board from the shared channels.
///
/// `notes` must be a RegisterMode OR-map and `votes` must be a TallyMode
/// OR-map. A wrong mode is a setup bug, not user data to ignore.
pub fn snapshot(title: String, notes: OrMap, votes: OrMap) -> board.Snapshot {
  board.snapshot(title, note_entries(notes), vote_entries(votes))
}

fn note_entries(notes: OrMap) -> List(#(String, Note)) {
  watershed.or_map_entries(notes)
  |> list.map(fn(entry) {
    let assert or_map_kernel.Register(value) = entry.1
    #(entry.0, note.from_register(value))
  })
}

fn vote_entries(votes: OrMap) -> List(#(String, Int)) {
  watershed.or_map_entries(votes)
  |> list.map(fn(entry) {
    let assert or_map_kernel.Tally(count) = entry.1
    #(entry.0, count)
  })
}
