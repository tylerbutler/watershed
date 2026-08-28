export type ExampleGroup =
  | "foundation"
  | "conflicts"
  | "composition"
  | "specialized";

export interface Example {
  id: string;
  name: string;
  group: ExampleGroup;
  summary: string;
  structures: string[];
  payoff: string;
}

export const exampleGroups: {
  id: ExampleGroup;
  title: string;
  description: string;
}[] = [
  {
    id: "foundation",
    title: "Foundation and lifecycle",
    description:
      "Small applications that make connection, bootstrap, subscription, and one shared structure easy to trace.",
  },
  {
    id: "conflicts",
    title: "Conflict semantics",
    description:
      "The same-looking interaction under different merge and arbitration rules.",
  },
  {
    id: "composition",
    title: "Composition and presence",
    description:
      "Documents with several channels, nested applications, or a transient collaboration tier.",
  },
  {
    id: "specialized",
    title: "Specialized interaction",
    description:
      "Editors and visual surfaces where the browser boundary is part of the engineering claim.",
  },
];

export const examples: Example[] = [
  {
    id: "flowboard_lustre",
    name: "Flowboard",
    group: "foundation",
    summary:
      "A shared kanban board: typed bootstrap, shared cards, a counter, and presence.",
    structures: ["SharedMap", "SharedCounter", "Presence"],
    payoff:
      "Local and remote card moves pass through one declared Lustre effect loop.",
  },
  {
    id: "dice_lustre",
    name: "Collaborative dice",
    group: "foundation",
    summary:
      "The smallest end-to-end Gleam browser client, sharing one last-write-wins die value.",
    structures: ["SharedMap"],
    payoff:
      "Two tabs converge through the same pure core used by the BEAM client and survive reconnect.",
  },
  {
    id: "clap_counter_lustre",
    name: "Clap counter",
    group: "foundation",
    summary:
      "A one-channel stress test for concurrent increments using a state-based PN counter, peer to peer over WebRTC with no server sequencing it.",
    structures: ["PnCounter"],
    payoff:
      "Held buttons in several tabs add every clap without a lost update, and no server ever sees one.",
  },
  {
    id: "grocery_triptych_lustre",
    name: "Grocery triptych",
    group: "conflicts",
    summary:
      "One add/remove interaction applied to three set kinds so their semantics cannot hide behind different UIs.",
    structures: ["GSet", "TwoPSet", "OrSet"],
    payoff:
      "Remove and re-add milk: grow-only, tombstone, and observed-remove behavior diverge exactly as modeled.",
  },
  {
    id: "drum_machine_lustre",
    name: "Drum machine",
    group: "conflicts",
    summary:
      "A shared step sequencer pairing uncoordinated pattern edits with quorum-controlled tempo.",
    structures: ["OrSet", "PactMap"],
    payoff:
      "Pattern edits land immediately while tempo waits for every connected signer; convergence becomes audible.",
  },
  {
    id: "tournament_bracket_lustre",
    name: "Tournament bracket",
    group: "conflicts",
    summary:
      "Seven atomic registers retain every submitted match result while settling one official winner per match.",
    structures: ["RegisterCollection", "Presence"],
    payoff:
      "Conflicting reports converge on one CAS winner without discarding the losing submission.",
  },
  {
    id: "work_queue_lustre",
    name: "Work queue",
    group: "conflicts",
    summary:
      "A job-dispatch board whose columns are consensus queues and locks rather than collaborative card lists.",
    structures: ["OrderedCollection", "TaskManager", "SharedSequence"],
    payoff:
      "One worker wins each claim, and queued work plus dispatcher ownership recover when a client dies.",
  },
  {
    id: "release_checklist_lustre",
    name: "Release checklist",
    group: "conflicts",
    summary:
      "A go/no-go room pairing an uncoordinated OR-set checklist with a first-writer-wins captain seat and a quorum-gated release target.",
    structures: ["OrSet", "Claims", "PactMap"],
    payoff:
      "Checks converge immediately, exactly one captain seat survives concurrent claims, and only the captain can publish once every gate signs off.",
  },
  {
    id: "retro_board_lustre",
    name: "Retro board",
    group: "composition",
    summary:
      "A five-channel sticky-note wall with add-wins notes, conflict-free vote tallies, ordered columns, and presence.",
    structures: ["OrMap", "SharedSequence", "Presence"],
    payoff:
      "Concurrent notes and votes survive; cross-channel moves render honestly without pretending to be atomic.",
  },
  {
    id: "sudoku_lustre",
    name: "Collaborative Sudoku",
    group: "composition",
    summary:
      "A typed document combining four durable structures with cursors and typing indicators in the presence tier.",
    structures: ["SharedMap", "OrSet", "Claims", "SharedCounter", "Presence"],
    payoff:
      "Cell edits, pencil marks, givens, mistakes, and live awareness each use the conflict model they need.",
  },
  {
    id: "showcase_lustre",
    name: "Nested app showcase",
    group: "composition",
    summary:
      "Four independently runnable applications mounted as typed child maps inside one document and one presence roster.",
    structures: ["Child maps", "SharedText", "SharedSequence", "Claims", "OrMap"],
    payoff:
      "Panels switch without reconnecting, stay namespace-isolated, and share document-wide services safely.",
  },
  {
    id: "playlist_lustre",
    name: "Collaborative playlist",
    group: "specialized",
    summary:
      "A reorderable list built around SharedSequence's convergent move, replace, insert, and delete operations.",
    structures: ["SharedSequence"],
    payoff:
      "Concurrent moves and replacements converge while stale indices surface as rejected edits.",
  },
  {
    id: "text_lustre",
    name: "Shared text editor",
    group: "specialized",
    summary:
      "A grapheme-aware textarea bridge with anchors, IME handling, shared cursors, and a composable MVU component.",
    structures: ["SharedText", "Presence"],
    payoff:
      "Minimal text operations converge without replacing the whole document or losing the local caret.",
  },
  {
    id: "pixel_canvas_lustre",
    name: "Pixel canvas",
    group: "specialized",
    summary:
      "A 64×64 bitmap that makes high-volume offline OR-map convergence visible without reading an assertion.",
    structures: ["OrMap"],
    payoff:
      "Two disconnected painters rejoin and produce the same picture by joining sparse deltas.",
  },
];

const repositoryBase =
  "https://github.com/tylerbutler/watershed/tree/main/examples";

export function exampleSource(example: Example): string {
  return `${repositoryBase}/${example.id}`;
}
