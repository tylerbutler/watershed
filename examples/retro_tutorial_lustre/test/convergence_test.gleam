//// Deterministic claims tests for the tutorial retro board.
////
//// The browser app and this suite share the same board helpers.
//// The sluice runs the shared state in memory.

import gleam/list
import gleam/option.{Some}
import gleeunit/should

import retro_tutorial_lustre/board
import retro_tutorial_lustre/board_op
import retro_tutorial_lustre/doc_schema
import watershed.{type Document, type OrMap}
import watershed/or_map_kernel
import watershed/sluice_js.{type Sluice}

type Channels {
  Channels(notes: OrMap, votes: OrMap)
}

fn room(
  name: String,
) -> #(
  Sluice,
  Document(doc_schema.BoardDoc),
  Document(doc_schema.BoardDoc),
  Channels,
  Channels,
) {
  let sluice = sluice_js.start(tenant: "default", document: name)
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  let root = watershed.root_typed(doc_a)
  watershed.set_field(root, doc_schema.title(), "Sprint retro")
  let assert Ok(notes) =
    watershed.create_or_map(doc_a, or_map_kernel.RegisterMode)
  watershed.set_or_map_field(root, doc_schema.notes(), notes)
  let assert Ok(votes) = watershed.create_or_map(doc_a, or_map_kernel.TallyMode)
  watershed.set_or_map_field(root, doc_schema.votes(), votes)
  sluice_js.settle(sluice)

  #(sluice, doc_a, doc_b, channels_of(doc_a), channels_of(doc_b))
}

fn channels_of(doc: Document(doc_schema.BoardDoc)) -> Channels {
  let root = watershed.root_typed(doc)
  let assert Ok(Some(notes)) =
    watershed.resolve_or_map_field(doc, root, doc_schema.notes())
  let assert Ok(Some(votes)) =
    watershed.resolve_or_map_field(doc, root, doc_schema.votes())
  Channels(notes:, votes:)
}

fn board_of(
  doc: Document(doc_schema.BoardDoc),
  channels: Channels,
) -> board.Snapshot {
  let root = watershed.root_typed(doc)
  let assert Ok(Some(title)) = watershed.get_field(root, doc_schema.title())
  board_op.snapshot(title, channels.notes, channels.votes)
}

pub fn concurrent_adds_keep_both_notes_test() -> Nil {
  let #(sluice, doc_a, doc_b, a, b) = room("retro-tutorial-adds")

  let first =
    board_op.add_note(
      a.notes,
      "user-a",
      "deploys got faster",
      board.WentWell,
      1000,
      1,
    )
  let second =
    board_op.add_note(
      b.notes,
      "user-b",
      "standup stayed short",
      board.WentWell,
      1000,
      1,
    )
  sluice_js.settle(sluice)

  let board_a = board_of(doc_a, a)
  let board_b = board_of(doc_b, b)

  board_a |> should.equal(board_b)
  board.note_count(board_a) |> should.equal(2)
  let assert Ok(_) = board.find_card(board_a, first)
  let assert Ok(_) = board.find_card(board_a, second)
  board.cards_for(board_a, board.WentWell)
  |> list.length
  |> should.equal(2)
}

pub fn concurrent_plus_plus_minus_votes_settle_at_plus_one_test() -> Nil {
  let #(sluice, doc_a, doc_b, a, b) = room("retro-tutorial-votes")

  let id =
    board_op.add_note(
      a.notes,
      "user-a",
      "ship week went smoothly",
      board.WentWell,
      1000,
      1,
    )
  sluice_js.settle(sluice)

  board_op.upvote(a.votes, id)
  board_op.upvote(b.votes, id)
  board_op.downvote(b.votes, id)
  sluice_js.settle(sluice)

  let board_a = board_of(doc_a, a)
  let board_b = board_of(doc_b, b)

  board_a |> should.equal(board_b)
  let assert Ok(card) = board.find_card(board_a, id)
  card.votes |> should.equal(1)
}
