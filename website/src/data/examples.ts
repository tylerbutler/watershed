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
  checks: string;
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
      "The complete application from the build guide: typed bootstrap, shared cards, a counter, and presence.",
    structures: ["SharedMap", "SharedCounter", "Presence"],
    payoff:
      "Local and remote card moves pass through one declared Lustre effect loop.",
    checks: "Manual two-tab run; source is compiled by the website guide",
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
    checks: "Headless live-server convergence and reconnect smoke",
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
    checks: "Two real browser peers converge through the reference signaling service",
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
    checks: "Sluice convergence, scenario state, and browser smoke tests",
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
    checks: "Sluice convergence, quorum, and live-server smoke tests",
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
    checks: "Sluice convergence, bracket unit, and live-server smoke tests",
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
    checks: "Queue semantics, worker-death convergence, and server smoke tests",
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
    checks: "Sluice convergence, board/codec, and live-server smoke tests",
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
    checks: "Sluice convergence and browser smoke tests",
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
    checks: "Composition, roster, partition, and multi-panel convergence tests",
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
    checks: "Headless concurrent move/replace and reconnect smoke",
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
    checks: "Headless convergence smoke plus manual caret and IME checks",
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
    checks: "Sluice convergence, grid unit, and browser smoke tests",
  },
];

const repositoryBase =
  "https://github.com/tylerbutler/watershed/tree/main/examples";

export function exampleSource(example: Example): string {
  return `${repositoryBase}/${example.id}`;
}
