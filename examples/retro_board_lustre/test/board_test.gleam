//// The render rule, fed the pathological states the non-atomic move can
//// actually reach. Pure — no runtime, no sluice — because `board.render`
//// takes plain lists; the convergence suite covers the same rule against
//// states produced by real concurrent ops.

import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

import board.{NoteCard}
import column
import note.{type Note, Note}

fn note_in(col: String, created: Int) -> Note {
  Note(text: "card", column: col, author: "web-1", created: created)
}

const no_votes = []

pub fn id_in_two_sequences_renders_once_in_the_register_column_test() {
  // A half-landed concurrent move: both sequences claim the note.
  let board =
    board.render([#("n1", note_in("to_improve", 1))], no_votes, [
      #(column.WentWell, ["n1"]),
      #(column.ToImprove, ["n1"]),
      #(column.ActionItems, []),
    ])
  board.total_occurrences(board, "n1") |> should.equal(1)
  board.went_well |> should.equal([])
  board.to_improve
  |> should.equal([
    NoteCard(
      id: "n1",
      note: note_in("to_improve", 1),
      votes: 0,
      seq_index: Some(0),
    ),
  ])
}

pub fn id_only_in_a_wrong_column_sequence_renders_at_the_register_columns_tail_test() {
  // The register says action_items but only went_well's sequence has the id.
  let board =
    board.render([#("n1", note_in("action_items", 5))], no_votes, [
      #(column.WentWell, ["n1"]),
      #(column.ToImprove, []),
      #(column.ActionItems, []),
    ])
  board.total_occurrences(board, "n1") |> should.equal(1)
  board.went_well |> should.equal([])
  board.action_items
  |> should.equal([
    NoteCard(
      id: "n1",
      note: note_in("action_items", 5),
      votes: 0,
      seq_index: None,
    ),
  ])
}

pub fn unsequenced_notes_render_in_created_order_with_id_tiebreak_test() {
  let board =
    board.render(
      [
        #("nz", note_in("went_well", 2)),
        #("nb", note_in("went_well", 1)),
        #("na", note_in("went_well", 2)),
      ],
      no_votes,
      [
        #(column.WentWell, []),
        #(column.ToImprove, []),
        #(column.ActionItems, []),
      ],
    )
  board.went_well
  |> list.map(fn(card) { card.id })
  |> should.equal(["nb", "na", "nz"])
  board.went_well
  |> list.map(fn(card) { card.seq_index })
  |> should.equal([None, None, None])
}

pub fn deleted_note_ids_are_skipped_and_raw_indexes_keep_their_gaps_test() {
  // "gone" was deleted from the notes map but its sequence entry remains.
  // The card after the gap must keep its RAW index (2, not 1) — sequence ops
  // address raw positions.
  let board =
    board.render(
      [#("n1", note_in("went_well", 1)), #("n2", note_in("went_well", 2))],
      no_votes,
      [
        #(column.WentWell, ["n1", "gone", "n2"]),
        #(column.ToImprove, []),
        #(column.ActionItems, []),
      ],
    )
  board.went_well
  |> list.map(fn(card) { #(card.id, card.seq_index) })
  |> should.equal([#("n1", Some(0)), #("n2", Some(2))])
  board.total_occurrences(board, "gone") |> should.equal(0)
}

pub fn duplicate_id_in_one_sequence_renders_once_at_its_first_index_test() {
  let board =
    board.render([#("n1", note_in("went_well", 1))], no_votes, [
      #(column.WentWell, ["n1", "n1"]),
      #(column.ToImprove, []),
      #(column.ActionItems, []),
    ])
  board.went_well
  |> list.map(fn(card) { #(card.id, card.seq_index) })
  |> should.equal([#("n1", Some(0))])
}

pub fn unknown_column_registers_route_to_unfiled_test() {
  // A future build's column id, and the codec fallback's empty string.
  let board =
    board.render(
      [
        #("n1", note_in("parking_lot", 2)),
        #("n2", note_in("", 1)),
      ],
      no_votes,
      [
        #(column.WentWell, ["n1"]),
        #(column.ToImprove, []),
        #(column.ActionItems, []),
      ],
    )
  board.unfiled
  |> list.map(fn(card) { card.id })
  |> should.equal(["n2", "n1"])
  board.went_well |> should.equal([])
  board.total_occurrences(board, "n1") |> should.equal(1)
}

pub fn orphan_votes_are_ignored_test() {
  // A tally for a deleted note: unreachable, not rendered, not crashing.
  let board =
    board.render(
      [#("n1", note_in("went_well", 1))],
      [#("gone", 4), #("n1", 2)],
      [
        #(column.WentWell, ["n1"]),
        #(column.ToImprove, []),
        #(column.ActionItems, []),
      ],
    )
  board.went_well
  |> list.map(fn(card) { #(card.id, card.votes) })
  |> should.equal([#("n1", 2)])
  board.total_occurrences(board, "gone") |> should.equal(0)
}

pub fn a_never_voted_note_defaults_to_zero_test() {
  let board =
    board.render([#("n1", note_in("action_items", 1))], no_votes, [
      #(column.WentWell, []),
      #(column.ToImprove, []),
      #(column.ActionItems, ["n1"]),
    ])
  board.action_items
  |> list.map(fn(card) { card.votes })
  |> should.equal([0])
}
