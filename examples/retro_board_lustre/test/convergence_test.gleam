//// The demo's claims, executed: two clients over the in-memory sluice.
////
//// Each headline the README makes — concurrent adds both survive, concurrent
//// votes sum, concurrent cross-column moves render exactly once, edit-vs-
//// delete converges — is asserted here against the same ops the buttons
//// issue, so a regression fails a test instead of quietly looking wrong.
////
//// The app bootstraps its channels with `ensure_*`, which resolves through a
//// retry loop on a timer. That is right in a browser and wrong here — the
//// sluice's whole point is synchronous, deterministic delivery — so the
//// harness seeds all five handles directly and keeps the assertions free of
//// waiting.
////
//// Register leaves are wall-clock LWW tie-broken by replica id, so no test
//// asserts *which* value wins a race — only that the room agrees.

import doc_schema
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import gleeunit/should

import watershed.{type Document}
import watershed/or_map_kernel
import watershed/sluice_js.{type Sluice}

import board
import column.{type Column}
import note.{type Note, Note}

// ── Harness ──────────────────────────────────────────────────────────────────

/// One client's view of the five channels, mirroring the app's `SharedState`.
type Channels {
  Channels(
    notes: watershed.OrMap,
    votes: watershed.OrMap,
    went_well: watershed.SharedSequence,
    to_improve: watershed.SharedSequence,
    action_items: watershed.SharedSequence,
  )
}

/// A room with all five channels seeded on client A and resolved on both.
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

  let root = watershed.root(doc_a)
  let assert Ok(notes) =
    watershed.create_or_map(doc_a, or_map_kernel.RegisterMode)
  watershed.set(root, "notes", watershed.or_map_handle_of(notes))
  let assert Ok(votes) = watershed.create_or_map(doc_a, or_map_kernel.TallyMode)
  watershed.set(root, "votes", watershed.or_map_handle_of(votes))
  list.each(column.all(), fn(col) {
    let assert Ok(sequence) = watershed.create_sequence(doc_a)
    watershed.set(root, column.id(col), watershed.sequence_handle_of(sequence))
  })
  sluice_js.settle(sluice)

  #(sluice, doc_a, doc_b, channels_of(doc_a), channels_of(doc_b))
}

fn channels_of(doc: Document(doc_schema.BoardDoc)) -> Channels {
  let root = watershed.root(doc)
  let assert Some(notes_handle) = watershed.get(root, "notes")
  let assert Ok(notes) = watershed.resolve_or_map(doc, notes_handle)
  let assert Some(votes_handle) = watershed.get(root, "votes")
  let assert Ok(votes) = watershed.resolve_or_map(doc, votes_handle)
  let assert [went_well, to_improve, action_items] =
    list.map(column.all(), fn(col) {
      let assert Some(handle) = watershed.get(root, column.id(col))
      let assert Ok(sequence) = watershed.resolve_sequence(doc, handle)
      sequence
    })
  Channels(notes:, votes:, went_well:, to_improve:, action_items:)
}

fn sequence_for(channels: Channels, col: Column) -> watershed.SharedSequence {
  case col {
    column.WentWell -> channels.went_well
    column.ToImprove -> channels.to_improve
    column.ActionItems -> channels.action_items
  }
}

/// Add a card exactly as the app does: one register write keyed by a fresh
/// note id, plus an append to the column's sequence.
fn add_note(channels: Channels, id: String, text: String, col: Column) -> Nil {
  let entry =
    Note(text: text, column: column.id(col), author: id, created: 1000)
  watershed.or_map_set_json(channels.notes, id, note.to_json(entry))
  let sequence = sequence_for(channels, col)
  let assert Ok(Nil) =
    watershed.sequence_insert(
      sequence,
      watershed.sequence_length(sequence),
      json.string(id),
    )
  Nil
}

/// The rendered board as one client sees it — the same render rule the view
/// uses, fed from the real channels. The convergence oracle.
fn board_of(channels: Channels) -> board.RenderedBoard {
  board.render(note_entries(channels.notes), vote_entries(channels.votes), [
    #(column.WentWell, sequence_ids(channels.went_well)),
    #(column.ToImprove, sequence_ids(channels.to_improve)),
    #(column.ActionItems, sequence_ids(channels.action_items)),
  ])
}

fn note_entries(notes: watershed.OrMap) -> List(#(String, Note)) {
  watershed.or_map_entries(notes)
  |> list.filter_map(fn(entry) {
    case entry.1 {
      or_map_kernel.Register(value) -> Ok(#(entry.0, note.from_register(value)))
      or_map_kernel.Tally(_) -> Error(Nil)
    }
  })
}

fn vote_entries(votes: watershed.OrMap) -> List(#(String, Int)) {
  watershed.or_map_entries(votes)
  |> list.filter_map(fn(entry) {
    case entry.1 {
      or_map_kernel.Tally(count) -> Ok(#(entry.0, count))
      or_map_kernel.Register(_) -> Error(Nil)
    }
  })
}

fn sequence_ids(sequence: watershed.SharedSequence) -> List(String) {
  watershed.sequence_values(sequence)
  |> list.filter_map(fn(value) {
    json.parse(json.to_string(value), decode.string)
    |> result.replace_error(Nil)
  })
}

/// A note's converged tally, as the vote pill reads it.
fn tally(channels: Channels, id: String) -> Int {
  case watershed.or_map_value(channels.votes, id) {
    Some(or_map_kernel.Tally(count)) -> count
    _ -> 0
  }
}

// ── Concurrent add ───────────────────────────────────────────────────────────

/// The headline. Two people add a card in the same instant; under a naive
/// last-writer-wins map one card disappears, under the OR-map both survive.
pub fn concurrent_adds_in_same_column_both_survive_test() {
  let #(sluice, _doc_a, _doc_b, a, b) = room("retro-concurrent-add")

  // Same tick, no coordination — neither client has seen the other's add.
  add_note(a, "note-a", "deploys got faster", column.WentWell)
  add_note(b, "note-b", "standup stayed short", column.WentWell)
  sluice_js.settle(sluice)

  let keys_a = watershed.or_map_keys(a.notes) |> list.sort(string.compare)
  keys_a |> should.equal(["note-a", "note-b"])
  keys_a
  |> should.equal(watershed.or_map_keys(b.notes) |> list.sort(string.compare))

  board_of(a) |> should.equal(board_of(b))
  board_of(a).went_well |> list.length |> should.equal(2)
}

// ── Ordering ─────────────────────────────────────────────────────────────────

/// Two tabs reordering the same column at once land on one order — the
/// sequence kernel's business; the board just has to agree with itself.
pub fn concurrent_reorders_in_same_column_converge_test() {
  let #(sluice, _doc_a, _doc_b, a, b) = room("retro-concurrent-reorder")

  add_note(a, "note-1", "first", column.ActionItems)
  add_note(a, "note-2", "second", column.ActionItems)
  add_note(a, "note-3", "third", column.ActionItems)
  sluice_js.settle(sluice)

  // A pulls the last card to the top while B pushes the first to the bottom.
  let assert Ok(Nil) = watershed.sequence_move(a.action_items, 2, 0)
  let assert Ok(Nil) = watershed.sequence_move(b.action_items, 0, 2)
  sluice_js.settle(sluice)

  sequence_ids(a.action_items) |> should.equal(sequence_ids(b.action_items))
  sequence_ids(a.action_items)
  |> list.sort(string.compare)
  |> should.equal(["note-1", "note-2", "note-3"])
  board_of(a) |> should.equal(board_of(b))
}

// ── Cross-column move ────────────────────────────────────────────────────────

/// The three-op move as the app performs it: sweep the id out of every
/// sequence, append to the destination, rewrite the register last.
fn move_note(channels: Channels, id: String, dest: Column) -> Nil {
  case watershed.or_map_value(channels.notes, id) {
    Some(or_map_kernel.Register(value)) -> {
      list.each(column.all(), fn(col) {
        remove_from_sequence(sequence_for(channels, col), id)
      })
      let sequence = sequence_for(channels, dest)
      let assert Ok(Nil) =
        watershed.sequence_insert(
          sequence,
          watershed.sequence_length(sequence),
          json.string(id),
        )
      let moved = Note(..note.from_register(value), column: column.id(dest))
      watershed.or_map_set_json(channels.notes, id, note.to_json(moved))
    }
    _ -> panic as "move_note: note not present"
  }
}

fn remove_from_sequence(sequence: watershed.SharedSequence, id: String) -> Nil {
  let found =
    watershed.sequence_values(sequence)
    |> list.index_map(fn(value, index) { #(value, index) })
    |> list.find(fn(entry) {
      json.parse(json.to_string(entry.0), decode.string) == Ok(id)
    })
  case found {
    Ok(#(_, index)) -> {
      let assert Ok(Nil) = watershed.sequence_delete(sequence, index)
      remove_from_sequence(sequence, id)
    }
    Error(Nil) -> Nil
  }
}

/// The RB5 gate. Two tabs drag the same card to *different* columns at the
/// same instant — the reachable intermediate states include the id sitting in
/// two sequences — and both tabs must end up rendering it exactly once, in the
/// same column. Which column wins is wall-clock LWW and deliberately not
/// asserted.
pub fn concurrent_cross_column_moves_render_the_note_exactly_once_test() {
  let #(sluice, _doc_a, _doc_b, a, b) = room("retro-cross-column-race")

  add_note(a, "note-1", "flaky tests", column.WentWell)
  sluice_js.settle(sluice)

  move_note(a, "note-1", column.ToImprove)
  move_note(b, "note-1", column.ActionItems)
  sluice_js.settle(sluice)

  board_of(a) |> should.equal(board_of(b))
  board.total_occurrences(board_of(a), "note-1") |> should.equal(1)
}

/// A third participant joining after the dust settles sees the same board —
/// pins snapshot/replay of a five-channel document.
pub fn late_joiner_sees_the_full_board_test() {
  let #(sluice, _doc_a, _doc_b, a, _b) = room("retro-late-joiner")

  add_note(a, "note-1", "pairing worked", column.WentWell)
  add_note(a, "note-2", "docs lag", column.ToImprove)
  watershed.or_map_increment(a.votes, "note-1", 1)
  sluice_js.settle(sluice)
  move_note(a, "note-2", column.ActionItems)
  sluice_js.settle(sluice)

  let doc_c = sluice_js.connect(sluice, "user-c")
  sluice_js.settle(sluice)

  board_of(channels_of(doc_c)) |> should.equal(board_of(a))
  tally(channels_of(doc_c), "note-1") |> should.equal(1)
}

// ── Edit vs delete ───────────────────────────────────────────────────────────

/// One participant rewrites a card's text while another deletes it, in the
/// same tick. Tier 1 (unconditional): the room converges. Tier 2 (pinned
/// after observing a real run): the outcome the kernel's add-wins bias
/// produces.
pub fn edit_vs_delete_converges_test() {
  let #(sluice, _doc_a, _doc_b, a, b) = room("retro-edit-vs-delete")

  add_note(a, "note-1", "original text", column.WentWell)
  sluice_js.settle(sluice)

  // A edits exactly as the app's save path does: re-read the register,
  // rewrite only the text. B deletes exactly as the delete button does:
  // observed remove plus the sequence sweep.
  let assert Some(or_map_kernel.Register(value)) =
    watershed.or_map_value(a.notes, "note-1")
  let edited = Note(..note.from_register(value), text: "edited text")
  watershed.or_map_set_json(a.notes, "note-1", note.to_json(edited))
  watershed.or_map_remove(b.notes, "note-1")
  remove_from_sequence(b.went_well, "note-1")
  sluice_js.settle(sluice)

  // Tier 1 — the unconditional CRDT claim: whatever happens, both agree.
  watershed.or_map_value(a.notes, "note-1")
  |> should.equal(watershed.or_map_value(b.notes, "note-1"))
  board_of(a) |> should.equal(board_of(b))

  // Tier 2 — pins the OBSERVED outcome of a real run (2026-08-10), not a
  // behaviour asserted in advance. The kernel is an observed-remove map: B's
  // remove covers only the dots B had seen, and A's concurrent edit minted a
  // dot B never saw — so the edit survives and the note resurrects with the
  // edited text. Delete wins only when nobody is touching the note. If the
  // kernel's remove semantics ever change, this test documents the change.
  let assert Some(or_map_kernel.Register(survivor)) =
    watershed.or_map_value(a.notes, "note-1")
  note.from_register(survivor).text |> should.equal("edited text")

  // The app-level consequence: B's sequence sweep DID win (the edit never
  // touched the sequence), so the resurrected note is in no sequence and
  // reappears at its column's tail via the `created` tiebreaker — visible,
  // not ghostly, and exactly once.
  sequence_ids(a.went_well) |> should.equal([])
  let rendered = board_of(a)
  board.total_occurrences(rendered, "note-1") |> should.equal(1)
  rendered.went_well
  |> list.map(fn(card) { card.seq_index })
  |> should.equal([option.None])
}

// ── Concurrent vote ──────────────────────────────────────────────────────────

/// The counter-bug page's claim made executable: under `get → +1 → set` one of
/// these upvotes is silently lost; under tally mode they sum.
pub fn concurrent_upvotes_sum_to_two_test() {
  let #(sluice, _doc_a, _doc_b, a, b) = room("retro-concurrent-upvote")

  add_note(a, "note-1", "ship week went smoothly", column.WentWell)
  sluice_js.settle(sluice)

  watershed.or_map_increment(a.votes, "note-1", 1)
  watershed.or_map_increment(b.votes, "note-1", 1)
  sluice_js.settle(sluice)

  tally(a, "note-1") |> should.equal(2)
  tally(b, "note-1") |> should.equal(2)
  board_of(a) |> should.equal(board_of(b))
}

pub fn concurrent_up_and_down_net_zero_test() {
  let #(sluice, _doc_a, _doc_b, a, b) = room("retro-concurrent-up-down")

  add_note(a, "note-1", "retro ran long", column.ToImprove)
  sluice_js.settle(sluice)

  watershed.or_map_increment(a.votes, "note-1", 1)
  watershed.or_map_increment(b.votes, "note-1", -1)
  sluice_js.settle(sluice)

  tally(a, "note-1") |> should.equal(0)
  tally(b, "note-1") |> should.equal(0)
  // Net zero is a value, not an absence: the key survives.
  watershed.or_map_keys(a.votes) |> should.equal(["note-1"])
  board_of(a) |> should.equal(board_of(b))
}
