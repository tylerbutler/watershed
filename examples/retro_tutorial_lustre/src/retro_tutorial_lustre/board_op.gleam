//// Shared board helpers for the tutorial example.
////
//// The UI and the deterministic tests call these same map writes.
//// Each helper takes only the channel it needs.

import gleam/list
import gleam/result

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
/// OR-map. Returns `Error` with a description when a channel has the wrong mode.
pub fn snapshot(
  title: String,
  notes: OrMap,
  votes: OrMap,
) -> Result(board.Snapshot, String) {
  use note_list <- result.try(note_entries(notes))
  use vote_list <- result.try(vote_entries(votes))
  Ok(board.snapshot(title, note_list, vote_list))
}

fn note_entries(notes: OrMap) -> Result(List(#(String, Note)), String) {
  watershed.or_map_entries(notes)
  |> list.try_map(fn(entry) {
    case entry.1 {
      or_map_kernel.Register(value) -> Ok(#(entry.0, note.from_register(value)))
      or_map_kernel.Tally(_) ->
        Error("notes channel has wrong mode; expected RegisterMode")
    }
  })
}

fn vote_entries(votes: OrMap) -> Result(List(#(String, Int)), String) {
  watershed.or_map_entries(votes)
  |> list.try_map(fn(entry) {
    case entry.1 {
      or_map_kernel.Tally(count) -> Ok(#(entry.0, count))
      or_map_kernel.Register(_) ->
        Error("votes channel has wrong mode; expected TallyMode")
    }
  })
}
