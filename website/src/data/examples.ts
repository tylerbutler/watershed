export type PatternId =
  | "ready-bootstrap"
  | "typed-bootstrap"
  | "channel-loop"
  | "conflict-modeling"
  | "scope-ownership"
  | "durable-ephemeral"
  | "pending-errors"
  | "payoff-tests";

export interface Pattern {
  id: PatternId;
  title: string;
  rule: string;
  why: string;
  useWhen: string;
}

export const patterns: Pattern[] = [
  {
    id: "ready-bootstrap",
    title: "Gate bootstrap on readiness",
    rule:
      "Keep the document handle when it arrives, but attach or ensure channels only after the connection handshake succeeds.",
    why:
      "The handle is useful for diagnostics and document-scoped services before the handshake, but channel creation needs a ready connection. Treating those two callbacks as one event creates first-load races.",
    useWhen:
      "Every browser app that connects to a remote watershed document.",
  },
  {
    id: "typed-bootstrap",
    title: "Declare an idempotent document shape",
    rule:
      "Put fields in a typed schema and let every client run the same ensure effects.",
    why:
      "A schema gives each slot one name and one channel kind. Idempotent ensure calls make joining an existing document and creating a new one the same application path.",
    useWhen:
      "A document has more than one field, a nested map, or code that should survive refactoring without stringly typed keys.",
  },
  {
    id: "channel-loop",
    title: "Close the channel loop",
    rule:
      "Resolve the handle, take an initial snapshot, subscribe, and route local and remote changes through the same snapshot and render path.",
    why:
      "The initial snapshot renders existing state immediately. One change path prevents optimistic local edits and sequenced remote edits from drifting into separate UI implementations.",
    useWhen:
      "A Lustre model mirrors any shared channel value.",
  },
  {
    id: "conflict-modeling",
    title: "Model the conflict, not the screen",
    rule:
      "Choose the structure whose merge or arbitration rule matches the domain instead of rebuilding that rule with application checks.",
    why:
      "A map, sequence, OR-set, counter, claim, and consensus queue can render similarly while resolving races differently. The data model should make the intended losing and winning writes explicit.",
    useWhen:
      "Selecting a channel kind or deciding whether two values belong in one atomic operation.",
  },
  {
    id: "scope-ownership",
    title: "Scope effects to their owner",
    rule:
      "The shell owns document-wide effects; nested components receive a typed map or channel and lift their messages into the parent.",
    why:
      "Presence, reconnect, diagnostics, and summary policy affect the whole document even when a button appears inside one panel. Keeping them in the shell prevents duplicate drivers and misleading local controls.",
    useWhen:
      "A collaborative feature should run both standalone and inside a larger document.",
  },
  {
    id: "durable-ephemeral",
    title: "Separate durable state from signals",
    rule:
      "Put replayable application state in document channels and transient awareness in presence or ripples.",
    why:
      "Selections, cursors, and typing indicators should expire with a session. Storing them beside durable edits bloats summaries and resurrects stale activity on reconnect.",
    useWhen:
      "Adding presence, cursors, typing indicators, hover state, or other short-lived collaboration.",
  },
  {
    id: "pending-errors",
    title: "Show what has not settled",
    rule:
      "Render optimistic, confirmed, non-optimistic, and rejected mutations as distinct states.",
    why:
      "Some structures expose a local guess immediately; consensus structures intentionally wait for sequencing. Index-based edits can also fail after a concurrent change. The UI must not turn every click into fake committed state.",
    useWhen:
      "A mutation can be pending, lose arbitration, or reject stale input.",
  },
  {
    id: "payoff-tests",
    title: "Test the payoff race",
    rule:
      "Name the concurrency claim, reproduce it deterministically with sluice, and reserve live smoke tests for network and browser boundaries.",
    why:
      "A generic two-client test can pass while the example's actual story is broken. Scripted delivery makes the important race repeatable; a live server check covers reconnect and transport behavior that an in-process sequencer cannot.",
    useWhen:
      "An example claims convergence, recovery, arbitration, or duplicate-delivery safety.",
  },
];

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
  patterns: PatternId[];
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
    patterns: [
      "ready-bootstrap",
      "typed-bootstrap",
      "channel-loop",
      "conflict-modeling",
      "durable-ephemeral",
      "pending-errors",
    ],
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
    patterns: [
      "ready-bootstrap",
      "channel-loop",
      "conflict-modeling",
      "pending-errors",
      "payoff-tests",
    ],
    checks: "Headless live-server convergence and reconnect smoke",
  },
  {
    id: "clap_counter_lustre",
    name: "Clap counter",
    group: "foundation",
    summary:
      "A one-channel stress test for concurrent increments using a state-based PN counter, peer to peer over WebRTC with no server sequencing it.",
    structures: ["PN Counter"],
    payoff:
      "Held buttons in several tabs add every clap without a lost update, and no server ever sees one.",
    patterns: ["ready-bootstrap", "conflict-modeling", "pending-errors", "payoff-tests"],
    checks: "Two real browser peers converge through the reference signaling service",
  },
  {
    id: "grocery_triptych_lustre",
    name: "Grocery triptych",
    group: "conflicts",
    summary:
      "One add/remove interaction applied to three set kinds so their semantics cannot hide behind different UIs.",
    structures: ["G-Set", "2P-Set", "OR-Set"],
    payoff:
      "Remove and re-add milk: grow-only, tombstone, and observed-remove behavior diverge exactly as modeled.",
    patterns: [
      "ready-bootstrap",
      "typed-bootstrap",
      "channel-loop",
      "conflict-modeling",
      "pending-errors",
      "payoff-tests",
    ],
    checks: "Sluice convergence, scenario state, and browser smoke tests",
  },
  {
    id: "drum_machine_lustre",
    name: "Drum machine",
    group: "conflicts",
    summary:
      "A shared step sequencer pairing uncoordinated pattern edits with quorum-controlled tempo.",
    structures: ["OR-Set", "PactMap"],
    payoff:
      "Pattern edits land immediately while tempo waits for every connected signer; convergence becomes audible.",
    patterns: [
      "ready-bootstrap",
      "typed-bootstrap",
      "channel-loop",
      "conflict-modeling",
      "pending-errors",
      "payoff-tests",
    ],
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
    patterns: [
      "ready-bootstrap",
      "typed-bootstrap",
      "channel-loop",
      "conflict-modeling",
      "durable-ephemeral",
      "pending-errors",
      "payoff-tests",
    ],
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
    patterns: [
      "ready-bootstrap",
      "typed-bootstrap",
      "channel-loop",
      "conflict-modeling",
      "pending-errors",
      "payoff-tests",
    ],
    checks: "Queue semantics, worker-death convergence, and server smoke tests",
  },
  {
    id: "retro_board_lustre",
    name: "Retro board",
    group: "composition",
    summary:
      "A five-channel sticky-note wall with add-wins notes, conflict-free vote tallies, ordered columns, and presence.",
    structures: ["OR-Map", "SharedSequence", "Presence"],
    payoff:
      "Concurrent notes and votes survive; cross-channel moves render honestly without pretending to be atomic.",
    patterns: [
      "ready-bootstrap",
      "typed-bootstrap",
      "channel-loop",
      "conflict-modeling",
      "durable-ephemeral",
      "pending-errors",
      "payoff-tests",
    ],
    checks: "Sluice convergence, board/codec, and live-server smoke tests",
  },
  {
    id: "sudoku_lustre",
    name: "Collaborative Sudoku",
    group: "composition",
    summary:
      "A typed document combining four durable structures with cursors and typing indicators in the presence tier.",
    structures: ["SharedMap", "OR-Set", "Claims", "SharedCounter", "Presence"],
    payoff:
      "Cell edits, pencil marks, givens, mistakes, and live awareness each use the conflict model they need.",
    patterns: [
      "ready-bootstrap",
      "typed-bootstrap",
      "channel-loop",
      "conflict-modeling",
      "scope-ownership",
      "durable-ephemeral",
      "pending-errors",
      "payoff-tests",
    ],
    checks: "Sluice convergence and browser smoke tests",
  },
  {
    id: "showcase_lustre",
    name: "Nested app showcase",
    group: "composition",
    summary:
      "Four independently runnable applications mounted as typed child maps inside one document and one presence roster.",
    structures: ["Child maps", "SharedText", "SharedSequence", "Claims", "OR-Map"],
    payoff:
      "Panels switch without reconnecting, stay namespace-isolated, and share document-wide services safely.",
    patterns: [
      "ready-bootstrap",
      "typed-bootstrap",
      "channel-loop",
      "conflict-modeling",
      "scope-ownership",
      "durable-ephemeral",
      "pending-errors",
      "payoff-tests",
    ],
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
    patterns: [
      "ready-bootstrap",
      "typed-bootstrap",
      "channel-loop",
      "conflict-modeling",
      "scope-ownership",
      "pending-errors",
      "payoff-tests",
    ],
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
    patterns: [
      "ready-bootstrap",
      "typed-bootstrap",
      "channel-loop",
      "conflict-modeling",
      "scope-ownership",
      "durable-ephemeral",
      "pending-errors",
      "payoff-tests",
    ],
    checks: "Headless convergence smoke plus manual caret and IME checks",
  },
  {
    id: "pixel_canvas_lustre",
    name: "Pixel canvas",
    group: "specialized",
    summary:
      "A 64×64 bitmap that makes high-volume offline OR-map convergence visible without reading an assertion.",
    structures: ["OR-Map"],
    payoff:
      "Two disconnected painters rejoin and produce the same picture by joining sparse deltas.",
    patterns: [
      "ready-bootstrap",
      "typed-bootstrap",
      "channel-loop",
      "conflict-modeling",
      "scope-ownership",
      "pending-errors",
      "payoff-tests",
    ],
    checks: "Sluice convergence, grid unit, and browser smoke tests",
  },
];

const repositoryBase =
  "https://github.com/tylerbutler/watershed/tree/main/examples";

export function exampleSource(example: Example): string {
  return `${repositoryBase}/${example.id}`;
}

export function examplesForPattern(patternId: PatternId): Example[] {
  return examples.filter((example) => example.patterns.includes(patternId));
}

export const patternById: Record<PatternId, Pattern> = Object.fromEntries(
  patterns.map((pattern) => [pattern.id, pattern]),
) as Record<PatternId, Pattern>;
