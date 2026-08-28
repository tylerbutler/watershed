//// Shared board ops for the tutorial example.
////
//// The UI and the deterministic tests build the same pure ops here.
//// One apply step writes them to the real shared maps.

import gleam/list

import watershed.{type OrMap}
import watershed/or_map_kernel

import board.{type Column}
import note.{type Note, Note}

pub type Operation {
  PutNote(id: String, note: Note)
  ChangeVotes(id: String, amount: Int)
}

pub fn add_note(
  author: String,
  text: String,
  column: Column,
  created: Int,
  nonce: Int,
) -> #(String, Operation) {
  let id = note.id(author, created, nonce)
  let entry =
    Note(
      text: text,
      column: board.column_id(column),
      author: author,
      created: created,
    )
  #(id, PutNote(id, entry))
}

pub fn upvote(id: String) -> Operation {
  ChangeVotes(id, 1)
}

pub fn downvote(id: String) -> Operation {
  ChangeVotes(id, -1)
}

pub fn apply(notes: OrMap, votes: OrMap, operation: Operation) -> Nil {
  case operation {
    PutNote(id, entry) ->
      watershed.or_map_set_json(notes, id, note.to_json(entry))
    ChangeVotes(id, amount) -> watershed.or_map_increment(votes, id, amount)
  }
}

pub fn snapshot(title: String, notes: OrMap, votes: OrMap) -> board.Snapshot {
  board.snapshot(title, note_entries(notes), vote_entries(votes))
}

fn note_entries(notes: OrMap) -> List(#(String, Note)) {
  watershed.or_map_entries(notes)
  |> list.filter_map(fn(entry) {
    case entry.1 {
      or_map_kernel.Register(value) -> Ok(#(entry.0, note.from_register(value)))
      or_map_kernel.Tally(_) -> Error(Nil)
    }
  })
}

fn vote_entries(votes: OrMap) -> List(#(String, Int)) {
  watershed.or_map_entries(votes)
  |> list.filter_map(fn(entry) {
    case entry.1 {
      or_map_kernel.Tally(count) -> Ok(#(entry.0, count))
      or_map_kernel.Register(_) -> Error(Nil)
    }
  })
}
