//// Canonical board state for the tutorial app.
////
//// There are no sequences in this rung. Notes group by the `column` register
//// and sort by `(created, id)` so every client renders the same order.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/order.{type Order}
import gleam/result
import gleam/string

import retro_tutorial_lustre/note.{type Note}

pub type Column {
  WentWell
  ToImprove
  ActionItems
}

pub fn all_columns() -> List(Column) {
  [WentWell, ToImprove, ActionItems]
}

pub fn column_id(column: Column) -> String {
  case column {
    WentWell -> "went_well"
    ToImprove -> "to_improve"
    ActionItems -> "action_items"
  }
}

pub fn from_id(id: String) -> Result(Column, Nil) {
  case id {
    "went_well" -> Ok(WentWell)
    "to_improve" -> Ok(ToImprove)
    "action_items" -> Ok(ActionItems)
    _ -> Error(Nil)
  }
}

pub fn column_label(column: Column) -> String {
  case column {
    WentWell -> "Went well"
    ToImprove -> "To improve"
    ActionItems -> "Action items"
  }
}

pub fn column_hint(column: Column) -> String {
  case column {
    WentWell -> "What helped the sprint?"
    ToImprove -> "What slowed the sprint down?"
    ActionItems -> "What should we do next?"
  }
}

pub type NoteCard {
  NoteCard(id: String, note: Note, votes: Int)
}

pub type Snapshot {
  Snapshot(
    title: String,
    went_well: List(NoteCard),
    to_improve: List(NoteCard),
    action_items: List(NoteCard),
    unfiled: List(NoteCard),
  )
}

pub fn empty(title: String) -> Snapshot {
  Snapshot(title:, went_well: [], to_improve: [], action_items: [], unfiled: [])
}

pub fn snapshot(
  title: String,
  notes: List(#(String, Note)),
  votes: List(#(String, Int)),
) -> Snapshot {
  let votes_by_id = dict.from_list(votes)
  Snapshot(
    title: title,
    went_well: notes_in_column(notes, votes_by_id, WentWell),
    to_improve: notes_in_column(notes, votes_by_id, ToImprove),
    action_items: notes_in_column(notes, votes_by_id, ActionItems),
    unfiled: unfiled(notes, votes_by_id),
  )
}

pub fn cards_for(snapshot: Snapshot, column: Column) -> List(NoteCard) {
  case column {
    WentWell -> snapshot.went_well
    ToImprove -> snapshot.to_improve
    ActionItems -> snapshot.action_items
  }
}

pub fn find_card(snapshot: Snapshot, id: String) -> Result(NoteCard, Nil) {
  [
    snapshot.went_well,
    snapshot.to_improve,
    snapshot.action_items,
    snapshot.unfiled,
  ]
  |> list.flatten
  |> list.find(fn(card) { card.id == id })
}

pub fn note_count(snapshot: Snapshot) -> Int {
  [
    snapshot.went_well,
    snapshot.to_improve,
    snapshot.action_items,
    snapshot.unfiled,
  ]
  |> list.flatten
  |> list.length
}

fn notes_in_column(
  notes: List(#(String, Note)),
  votes_by_id: Dict(String, Int),
  column: Column,
) -> List(NoteCard) {
  let wanted = column_id(column)
  notes
  |> list.filter(fn(entry) { entry.1.column == wanted })
  |> list.sort(by_created_then_id)
  |> list.map(fn(entry) { card(entry.0, entry.1, votes_by_id) })
}

fn unfiled(
  notes: List(#(String, Note)),
  votes_by_id: Dict(String, Int),
) -> List(NoteCard) {
  notes
  |> list.filter(fn(entry) { result.is_error(from_id(entry.1.column)) })
  |> list.sort(by_created_then_id)
  |> list.map(fn(entry) { card(entry.0, entry.1, votes_by_id) })
}

fn card(id: String, note: Note, votes_by_id: Dict(String, Int)) -> NoteCard {
  NoteCard(
    id: id,
    note: note,
    votes: dict.get(votes_by_id, id) |> result.unwrap(0),
  )
}

fn by_created_then_id(a: #(String, Note), b: #(String, Note)) -> Order {
  case int.compare(a.1.created, b.1.created) {
    order.Eq -> string.compare(a.0, b.0)
    other -> other
  }
}
