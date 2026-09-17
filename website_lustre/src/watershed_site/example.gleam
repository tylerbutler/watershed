import gleam/list
import gleam/option.{type Option, None, Some}
import watershed_site/structures

pub type GroupId {
  Foundation
  Conflicts
  Composition
  Specialized
}

pub type Group {
  Group(id: GroupId, title: String, description: String)
}

pub type Example {
  Example(
    id: String,
    name: String,
    group: GroupId,
    summary: String,
    structures: List(String),
    payoff: String,
  )
}

pub fn groups() -> List(Group) {
  [
    Group(
      Foundation,
      "Foundation and lifecycle",
      "Small applications that make connection, bootstrap, subscription, and one shared structure easy to trace.",
    ),
    Group(
      Conflicts,
      "Conflict semantics",
      "The same-looking interaction under different merge and arbitration rules.",
    ),
    Group(
      Composition,
      "Composition and presence",
      "Documents with several channels, nested applications, or a transient collaboration tier.",
    ),
    Group(
      Specialized,
      "Specialized interaction",
      "Editors and visual surfaces where the browser boundary is part of the engineering claim.",
    ),
  ]
}

pub fn all() -> List(Example) {
  [
    Example(
      "retro_tutorial_lustre",
      "Retro board (tutorial)",
      Foundation,
      "The board the build guide assembles: notes in a register OR-map, votes in a tally OR-map, and presence on the focused note.",
      ["OrMap", "Presence"],
      "Two people adding notes at once both keep theirs, and two votes on one note add up instead of overwriting.",
    ),
    Example(
      "dice_lustre",
      "Collaborative dice",
      Foundation,
      "The smallest end-to-end Gleam browser client, sharing one last-write-wins die value.",
      ["SharedMap"],
      "Two tabs converge through the same pure core used by the BEAM client and survive reconnect.",
    ),
    Example(
      "clap_counter_lustre",
      "Clap counter",
      Foundation,
      "A one-channel stress test for concurrent increments using a state-based PN counter, peer to peer over WebRTC with no server sequencing it.",
      ["PnCounter"],
      "Held buttons in several tabs add every clap without a lost update, and no server ever sees one.",
    ),
    Example(
      "grocery_triptych_lustre",
      "Grocery triptych",
      Conflicts,
      "One add/remove interaction applied to three set kinds so their semantics cannot hide behind different UIs.",
      ["GSet", "TwoPSet", "OrSet"],
      "Remove and re-add milk: grow-only, tombstone, and observed-remove behavior diverge exactly as modeled.",
    ),
    Example(
      "drum_machine_lustre",
      "Drum machine",
      Conflicts,
      "A shared step sequencer pairing uncoordinated pattern edits with quorum-controlled tempo.",
      ["OrSet", "PactMap"],
      "Pattern edits land immediately while tempo waits for every connected signer; convergence becomes audible.",
    ),
    Example(
      "tournament_bracket_lustre",
      "Tournament bracket",
      Conflicts,
      "Seven atomic registers retain every submitted match result while settling one official winner per match.",
      ["RegisterCollection", "Presence"],
      "Conflicting reports converge on one CAS winner without discarding the losing submission.",
    ),
    Example(
      "work_queue_lustre",
      "Work queue",
      Conflicts,
      "A job-dispatch board whose columns are consensus queues and locks rather than collaborative card lists.",
      ["OrderedCollection", "TaskManager", "SharedSequence"],
      "One worker wins each claim, and queued work plus dispatcher ownership recover when a client dies.",
    ),
    Example(
      "release_checklist_lustre",
      "Release checklist",
      Conflicts,
      "A go/no-go room pairing an uncoordinated OR-set checklist with a first-writer-wins captain seat and a quorum-gated release target.",
      ["OrSet", "Claims", "PactMap"],
      "Checks converge immediately, exactly one captain seat survives concurrent claims, and only the captain can publish once every gate signs off.",
    ),
    Example(
      "retro_board_lustre",
      "Retro board (full)",
      Composition,
      "What the tutorial board grows into: a five-channel sticky-note wall with add-wins notes, conflict-free vote tallies, ordered columns, and presence.",
      ["OrMap", "SharedSequence", "Presence"],
      "Concurrent notes and votes survive; cross-channel moves render honestly without pretending to be atomic.",
    ),
    Example(
      "sudoku_lustre",
      "Collaborative Sudoku",
      Composition,
      "A typed document combining four durable structures with cursors and typing indicators in the presence tier.",
      ["SharedMap", "OrSet", "Claims", "SharedCounter", "Presence"],
      "Cell edits, pencil marks, givens, mistakes, and live awareness each use the conflict model they need.",
    ),
    Example(
      "showcase_lustre",
      "Nested app showcase",
      Composition,
      "Four independently runnable applications mounted as typed child maps inside one document and one presence roster.",
      ["Child maps", "SharedText", "SharedSequence", "Claims", "OrMap"],
      "Panels switch without reconnecting, stay namespace-isolated, and share document-wide services safely.",
    ),
    Example(
      "playlist_lustre",
      "Collaborative playlist",
      Specialized,
      "A reorderable list built around SharedSequence's convergent move, replace, insert, and delete operations.",
      ["SharedSequence"],
      "Concurrent moves and replacements converge while stale indices surface as rejected edits.",
    ),
    Example(
      "text_lustre",
      "Shared text editor",
      Specialized,
      "A grapheme-aware textarea bridge with anchors, IME handling, shared cursors, and a composable MVU component.",
      ["SharedText", "Presence"],
      "Minimal text operations converge without replacing the whole document or losing the local caret.",
    ),
    Example(
      "pixel_canvas_lustre",
      "Pixel canvas",
      Specialized,
      "A 64×64 bitmap that makes high-volume offline OR-map convergence visible without reading an assertion.",
      ["OrMap"],
      "Two disconnected painters rejoin and produce the same picture by joining sparse deltas.",
    ),
  ]
}

pub fn by_group(group: GroupId) -> List(Example) {
  all() |> list.filter(fn(item) { item.group == group })
}

pub fn source(item: Example) -> String {
  "https://github.com/tylerbutler/watershed/tree/main/examples/" <> item.id
}

pub fn structure_link(name: String) -> Option(#(String, String)) {
  case
    structures.all()
    |> list.flat_map(fn(family) {
      family.entries
      |> list.map(fn(entry) { #(family.slug, entry.id, entry.name) })
    })
    |> list.find(fn(link) { link.2 == name })
  {
    Ok(link) -> Some(#(link.0, link.1))
    Error(Nil) -> None
  }
}
