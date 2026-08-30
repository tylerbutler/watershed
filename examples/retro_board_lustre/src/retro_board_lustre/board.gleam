//// The render rule: flat channel state → what each column shows.
////
//// A cross-column move is three operations across two channel kinds — delete
//// from one sequence, insert into another, rewrite the note's `column`
//// register — with no transaction spanning them. Under concurrent moves the
//// reachable states include a note id sitting in two column sequences at once,
//// or in none, or in a sequence that disagrees with its register. This module
//// makes every reachable state render sensibly, by one rule:
////
//// **The note's `column` register is authoritative.**
////
//// - A note id in a sequence whose column does not match its register is
////   skipped when rendering that sequence (the garbage entry stays in the
////   sequence — repair-on-render would mean every client issuing corrective
////   operations on every render, and those clients fighting each other).
//// - A note whose register names a column whose sequence does not contain its
////   id renders at the end of that column, ordered by `(created, id)`.
//// - A note whose register names no known column at all renders in the
////   `unfiled` strip rather than being dropped — dropping readable notes
////   would contradict the add-wins headline.
////
//// Pure module: plain lists in, `RenderedBoard` out. No watershed imports, so
//// the unit tests can feed it pathological states directly.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{type Order}
import gleam/result
import gleam/string

import retro_board_lustre/column.{type Column}
import retro_board_lustre/note.{type Note}

pub type NoteCard {
  NoteCard(
    id: String,
    note: Note,
    votes: Int,
    /// The id's **raw** index in its column's sequence — gaps included, since
    /// skipped garbage still occupies sequence positions and sequence
    /// operations address raw indexes. `None` for notes rendered from the
    /// register alone.
    seq_index: Option(Int),
  )
}

pub type RenderedBoard {
  RenderedBoard(
    went_well: List(NoteCard),
    to_improve: List(NoteCard),
    action_items: List(NoteCard),
    unfiled: List(NoteCard),
  )
}

pub fn empty() -> RenderedBoard {
  RenderedBoard(went_well: [], to_improve: [], action_items: [], unfiled: [])
}

pub fn render(
  notes: List(#(String, Note)),
  votes: List(#(String, Int)),
  sequences: List(#(Column, List(String))),
) -> RenderedBoard {
  let notes_by_id = dict.from_list(notes)
  let votes_by_id = dict.from_list(votes)
  let render_col = fn(column: Column) {
    let ids =
      sequences
      |> list.find(fn(entry) { entry.0 == column })
      |> result.map(fn(entry) { entry.1 })
      |> result.unwrap([])
    render_column(column, ids, notes, notes_by_id, votes_by_id)
  }
  RenderedBoard(
    went_well: render_col(column.WentWell),
    to_improve: render_col(column.ToImprove),
    action_items: render_col(column.ActionItems),
    unfiled: unfiled(notes, votes_by_id),
  )
}

pub fn cards_for(board: RenderedBoard, column: Column) -> List(NoteCard) {
  case column {
    column.WentWell -> board.went_well
    column.ToImprove -> board.to_improve
    column.ActionItems -> board.action_items
  }
}

/// How many times a note id appears anywhere on the rendered board. The
/// convergence tests' oracle for "renders exactly once".
pub fn total_occurrences(board: RenderedBoard, id: String) -> Int {
  [board.went_well, board.to_improve, board.action_items, board.unfiled]
  |> list.flatten
  |> list.count(fn(card) { card.id == id })
}

/// One column: the sequenced head in sequence order, then the unsequenced
/// tail in `(created, id)` order.
fn render_column(
  column: Column,
  ids: List(String),
  notes: List(#(String, Note)),
  notes_by_id: Dict(String, Note),
  votes_by_id: Dict(String, Int),
) -> List(NoteCard) {
  let column_id = column.id(column)
  // Sequenced head: keep an id only if its note exists (a deleted note's
  // sequence entry dies here), its register matches this column, and this is
  // its first occurrence in the sequence.
  let #(head, kept) =
    ids
    |> list.index_map(fn(id, index) { #(id, index) })
    |> list.fold(#([], dict.new()), fn(acc, entry) {
      let #(cards, kept) = acc
      let #(id, index) = entry
      case dict.has_key(kept, id), dict.get(notes_by_id, id) {
        False, Ok(n) if n.column == column_id -> #(
          [card(id, n, votes_by_id, Some(index)), ..cards],
          dict.insert(kept, id, Nil),
        )
        _, _ -> acc
      }
    })
  let head = list.reverse(head)
  // Unsequenced tail: notes claiming this column that the head did not keep.
  let tail =
    notes
    |> list.filter(fn(entry) {
      entry.1.column == column_id && !dict.has_key(kept, entry.0)
    })
    |> list.sort(by_created_then_id)
    |> list.map(fn(entry) { card(entry.0, entry.1, votes_by_id, None) })
  list.append(head, tail)
}

/// Notes whose register names no known column — codec fallbacks and documents
/// written by other builds. Rendered, not dropped.
fn unfiled(
  notes: List(#(String, Note)),
  votes_by_id: Dict(String, Int),
) -> List(NoteCard) {
  notes
  |> list.filter(fn(entry) { result.is_error(column.from_id(entry.1.column)) })
  |> list.sort(by_created_then_id)
  |> list.map(fn(entry) { card(entry.0, entry.1, votes_by_id, None) })
}

fn card(
  id: String,
  n: Note,
  votes_by_id: Dict(String, Int),
  seq_index: Option(Int),
) -> NoteCard {
  NoteCard(
    id: id,
    note: n,
    votes: dict.get(votes_by_id, id) |> result.unwrap(0),
    seq_index: seq_index,
  )
}

/// Deterministic across clients: same `created` ties break on id.
fn by_created_then_id(a: #(String, Note), b: #(String, Note)) -> Order {
  case int.compare(a.1.created, b.1.created) {
    order.Eq -> string.compare(a.0, b.0)
    other -> other
  }
}
