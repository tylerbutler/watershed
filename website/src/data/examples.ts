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
      "Small applications that show how to connect, initialize, subscribe, and use one shared structure.",
  },
  {
    id: "conflicts",
    title: "Conflict rules",
    description:
      "Similar interactions that use different merge and arbitration rules.",
  },
  {
    id: "composition",
    title: "Composition and presence",
    description:
      "Applications with several channels, nested components, or temporary collaboration data.",
  },
  {
    id: "specialized",
    title: "Specialized interfaces",
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
      "The build-guide application uses typed initialization, shared cards, a counter, and presence.",
    structures: ["SharedMap", "SharedCounter", "Presence"],
    payoff:
      "One Lustre effect loop handles local and remote card moves.",
  },
  {
    id: "dice_lustre",
    name: "Collaborative dice",
    group: "foundation",
    summary:
      "A small Gleam browser client that shares one last-write-wins die value.",
    structures: ["SharedMap"],
    payoff:
      "Two tabs use the same pure core as the BEAM client. They converge and recover after reconnection.",
  },
  {
    id: "clap_counter_lustre",
    name: "Clap counter",
    group: "foundation",
    summary:
      "A one-channel test of concurrent PN-counter increments over WebRTC without server sequencing.",
    structures: ["PnCounter"],
    payoff:
      "Several tabs preserve all clap increments without a server connection.",
  },
  {
    id: "grocery_triptych_lustre",
    name: "Grocery triptych",
    group: "conflicts",
    summary:
      "One interface applies the same add and remove interaction to three set types.",
    structures: ["GSet", "TwoPSet", "OrSet"],
    payoff:
      "Remove milk and add it again to compare grow-only, tombstone, and observed-remove rules.",
  },
  {
    id: "drum_machine_lustre",
    name: "Drum machine",
    group: "conflicts",
    summary:
      "A shared step sequencer with independent pattern edits and quorum-controlled tempo.",
    structures: ["OrSet", "PactMap"],
    payoff:
      "Pattern edits appear at once. A tempo change waits for all connected clients.",
  },
  {
    id: "tournament_bracket_lustre",
    name: "Tournament bracket",
    group: "conflicts",
    summary:
      "Seven atomic registers retain all submitted match results and select one official winner per match.",
    structures: ["RegisterCollection", "Presence"],
    payoff:
      "Conflicting reports select one CAS winner and retain the other submission.",
  },
  {
    id: "work_queue_lustre",
    name: "Work queue",
    group: "conflicts",
    summary:
      "A job-dispatch board that uses consensus queues and locks for its columns.",
    structures: ["OrderedCollection", "TaskManager", "SharedSequence"],
    payoff:
      "One worker receives each claim. Queued work and dispatcher ownership recover after disconnection.",
  },
  {
    id: "release_checklist_lustre",
    name: "Release checklist",
    group: "conflicts",
    summary:
      "A release room with an OR-set checklist, a first-writer-wins captain, and a quorum-controlled target.",
    structures: ["OrSet", "Claims", "PactMap"],
    payoff:
      "Checks converge at once. One captain receives a concurrent claim and can publish after all gates approve.",
  },
  {
    id: "retro_board_lustre",
    name: "Retro board",
    group: "composition",
    summary:
      "A note wall uses five channels for add-wins notes, conflict-free vote totals, ordered columns, and presence.",
    structures: ["OrMap", "SharedSequence", "Presence"],
    payoff:
      "Concurrent notes and votes remain. The interface identifies cross-channel moves as non-atomic operations.",
  },
  {
    id: "sudoku_lustre",
    name: "Collaborative Sudoku",
    group: "composition",
    summary:
      "A typed document uses four durable structures. The presence tier provides cursors and typing indicators.",
    structures: ["SharedMap", "OrSet", "Claims", "SharedCounter", "Presence"],
    payoff:
      "Cells, notes, givens, mistakes, and presence each use a suitable conflict model.",
  },
  {
    id: "showcase_lustre",
    name: "Nested app showcase",
    group: "composition",
    summary:
      "The page mounts four independent applications as typed child maps in one document with one presence roster.",
    structures: ["Child maps", "SharedText", "SharedSequence", "Claims", "OrMap"],
    payoff:
      "Panels switch without reconnection. They keep separate namespaces and share document services.",
  },
  {
    id: "playlist_lustre",
    name: "Collaborative playlist",
    group: "specialized",
    summary:
      "A reorderable list that uses SharedSequence move, replace, insert, and delete operations.",
    structures: ["SharedSequence"],
    payoff:
      "Concurrent moves and replacements converge. The application reports stale-index errors.",
  },
  {
    id: "text_lustre",
    name: "Shared text editor",
    group: "specialized",
    summary:
      "A text area uses grapheme indexes, anchors, IME handling, shared cursors, and a reusable MVU component.",
    structures: ["SharedText", "Presence"],
    payoff:
      "Small text operations converge without replacing the document or moving the local caret.",
  },
  {
    id: "pixel_canvas_lustre",
    name: "Pixel canvas",
    group: "specialized",
    summary:
      "A 64×64 bitmap that shows high-volume offline OR-map convergence.",
    structures: ["OrMap"],
    payoff:
      "Two disconnected painters reconnect and produce the same image from sparse delta merges.",
  },
];

const repositoryBase =
  "https://github.com/tylerbutler/watershed/tree/main/examples";

export function exampleSource(example: Example): string {
  return `${repositoryBase}/${example.id}`;
}
