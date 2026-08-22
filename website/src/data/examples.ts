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
      "Small applications that show connection, bootstrap, subscription, and one shared structure.",
  },
  {
    id: "conflicts",
    title: "Conflict semantics",
    description:
      "Similar interactions that use different merge and arbitration rules.",
  },
  {
    id: "composition",
    title: "Composition and presence",
    description:
      "Documents with several channels, nested applications, or temporary collaboration data.",
  },
  {
    id: "specialized",
    title: "Specialized interaction",
    description:
      "Editors and visual interfaces that depend on browser behavior.",
  },
];

export const examples: Example[] = [
  {
    id: "flowboard_lustre",
    name: "Flowboard",
    group: "foundation",
    summary:
      "The complete build-guide application with typed bootstrap, shared cards, a counter, and presence.",
    structures: ["SharedMap", "SharedCounter", "Presence"],
    payoff:
      "One declared Lustre effect loop handles local and remote card moves.",
  },
  {
    id: "dice_lustre",
    name: "Collaborative dice",
    group: "foundation",
    summary:
      "A small Gleam browser client that shares one last-write-wins die value.",
    structures: ["SharedMap"],
    payoff:
      "Two tabs use the same pure core as the BEAM client, converge, and recover after reconnection.",
  },
  {
    id: "clap_counter_lustre",
    name: "Clap counter",
    group: "foundation",
    summary:
      "A one-channel test of concurrent PN-counter increments over WebRTC without server sequencing.",
    structures: ["PnCounter"],
    payoff:
      "Several tabs add all claps without a lost update or a server connection.",
  },
  {
    id: "grocery_triptych_lustre",
    name: "Grocery triptych",
    group: "conflicts",
    summary:
      "One add/remove interaction applied to three set types in the same user interface.",
    structures: ["GSet", "TwoPSet", "OrSet"],
    payoff:
      "Remove and add milk again to compare grow-only, tombstone, and observed-remove behavior.",
  },
  {
    id: "drum_machine_lustre",
    name: "Drum machine",
    group: "conflicts",
    summary:
      "A shared step sequencer with independent pattern edits and quorum-controlled tempo.",
    structures: ["OrSet", "PactMap"],
    payoff:
      "Pattern edits appear at once, but a tempo change waits for all connected signers.",
  },
  {
    id: "tournament_bracket_lustre",
    name: "Tournament bracket",
    group: "conflicts",
    summary:
      "Seven atomic registers retain all submitted match results and select one official winner per match.",
    structures: ["RegisterCollection", "Presence"],
    payoff:
      "Conflicting reports select one CAS winner and retain the losing submission.",
  },
  {
    id: "work_queue_lustre",
    name: "Work queue",
    group: "conflicts",
    summary:
      "A job-dispatch board that uses consensus queues and locks for its columns.",
    structures: ["OrderedCollection", "TaskManager", "SharedSequence"],
    payoff:
      "One worker wins each claim. Queued work and dispatcher ownership recover after a client disconnects.",
  },
  {
    id: "release_checklist_lustre",
    name: "Release checklist",
    group: "conflicts",
    summary:
      "A release room with an OR-set checklist, a first-writer-wins captain, and a quorum-controlled target.",
    structures: ["OrSet", "Claims", "PactMap"],
    payoff:
      "Checks converge at once. One captain wins concurrent claims and can publish after all gates approve.",
  },
  {
    id: "retro_board_lustre",
    name: "Retro board",
    group: "composition",
    summary:
      "A five-channel note wall with add-wins notes, conflict-free vote totals, ordered columns, and presence.",
    structures: ["OrMap", "SharedSequence", "Presence"],
    payoff:
      "Concurrent notes and votes remain. The interface shows cross-channel moves as non-atomic operations.",
  },
  {
    id: "sudoku_lustre",
    name: "Collaborative Sudoku",
    group: "composition",
    summary:
      "A typed document combining four durable structures with cursors and typing indicators in the presence tier.",
    structures: ["SharedMap", "OrSet", "Claims", "SharedCounter", "Presence"],
    payoff:
      "Each data type uses a suitable conflict model: cells, notes, givens, mistakes, and presence.",
  },
  {
    id: "showcase_lustre",
    name: "Nested app showcase",
    group: "composition",
    summary:
      "Four independent applications mounted as typed child maps in one document with one presence roster.",
    structures: ["Child maps", "SharedText", "SharedSequence", "Claims", "OrMap"],
    payoff:
      "Panels switch without reconnection, keep separate namespaces, and share document services.",
  },
  {
    id: "playlist_lustre",
    name: "Collaborative playlist",
    group: "specialized",
    summary:
      "A reorderable list that uses SharedSequence move, replace, insert, and delete operations.",
    structures: ["SharedSequence"],
    payoff:
      "Concurrent moves and replacements converge. The application reports edits that use stale indices.",
  },
  {
    id: "text_lustre",
    name: "Shared text editor",
    group: "specialized",
    summary:
      "A grapheme-aware text area with anchors, IME handling, shared cursors, and a reusable MVU component.",
    structures: ["SharedText", "Presence"],
    payoff:
      "Small text operations converge without replacing the document or losing the local caret.",
  },
  {
    id: "pixel_canvas_lustre",
    name: "Pixel canvas",
    group: "specialized",
    summary:
      "A 64×64 bitmap that shows high-volume offline OR-map convergence.",
    structures: ["OrMap"],
    payoff:
      "Two disconnected painters reconnect and produce the same image by merging sparse deltas.",
  },
];

const repositoryBase =
  "https://github.com/tylerbutler/watershed/tree/main/examples";

export function exampleSource(example: Example): string {
  return `${repositoryBase}/${example.id}`;
}
