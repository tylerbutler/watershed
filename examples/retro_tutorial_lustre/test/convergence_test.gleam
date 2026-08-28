//// Deterministic claims tests for the tutorial retro board.
////
//// The app runs these cases in a browser. The sluice runs them in memory.
//// That keeps the suite fast and stable.

import gleam/list
import gleam/option.{Some}
import gleeunit/should

import board
import board_ops
import doc_schema
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
  board_ops.snapshot(title, channels.notes, channels.votes)
}

fn add_note(
  channels: Channels,
  author: String,
  text: String,
  column: board.Column,
  created: Int,
  nonce: Int,
) -> String {
  let #(id, operation) =
    board_ops.add_note(author, text, column, created, nonce)
  board_ops.apply(channels.notes, channels.votes, operation)
  id
}

pub fn concurrent_adds_keep_both_notes_test() {
  let #(sluice, doc_a, doc_b, a, b) = room("retro-tutorial-adds")

  let first =
    add_note(a, "user-a", "deploys got faster", board.WentWell, 1000, 1)
  let second =
    add_note(b, "user-b", "standup stayed short", board.WentWell, 1000, 1)
  sluice_js.settle(sluice)

  let board_a = board_of(doc_a, a)
  let board_b = board_of(doc_b, b)

  board_a |> should.equal(board_b)
  board.note_count(board_a) |> should.equal(2)
  board_a.went_well
  |> list.map(fn(card) { card.id })
  |> should.equal([first, second])
}

pub fn concurrent_plus_plus_minus_votes_settle_at_plus_one_test() {
  let #(sluice, doc_a, doc_b, a, b) = room("retro-tutorial-votes")

  let id =
    add_note(a, "user-a", "ship week went smoothly", board.WentWell, 1000, 1)
  sluice_js.settle(sluice)

  board_ops.apply(a.notes, a.votes, board_ops.upvote(id))
  board_ops.apply(b.notes, b.votes, board_ops.upvote(id))
  board_ops.apply(b.notes, b.votes, board_ops.downvote(id))
  sluice_js.settle(sluice)

  let board_a = board_of(doc_a, a)
  let board_b = board_of(doc_b, b)

  board_a |> should.equal(board_b)
  let assert Ok(card) = board.find_card(board_a, id)
  card.votes |> should.equal(1)
}
