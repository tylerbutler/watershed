// ──────────────────────────────────────────────────────────────────────────
// watershed — practices catalog
// One entry per technique, each anchored to the ONE checked-in example that
// demonstrates it best. This is the inverse of the old /patterns page: not
// conventions that recur across apps, but one implementation practice paired
// with example code that demonstrates it. Snippets are source-backed
// descriptors from the practice registry — the registry imports each example
// source with `?raw` and extracts the relevant definition or marker range.
//
// Each practice is filed under the /guide step whose work it belongs to, and
// renders as field notes at the foot of that step. /patterns indexes them the
// other way — by problem theme — and `related` surfaces each one on the
// atlas and runtime sheets where its problem shows up.
// ──────────────────────────────────────────────────────────────────────────
import { examples, type Example } from "./examples";
import { steps, type StepSlug } from "./guide";
import { practiceSnippets } from "./practice-snippets.ts";
import type { Snippet } from "../lib/snippet.ts";

/** The problem themes /patterns groups by: what you're stuck on, not where
 *  the procedure happens to teach it. */
export const themes = [
  {
    slug: "architecture",
    title: "Architecture & composition",
    blurb:
      "Decide what the shell owns, what a component may touch, and which work must stay outside the app.",
  },
  {
    slug: "conflicts",
    title: "Conflicts & consistency",
    blurb:
      "Two clients change the same state at once. Keep the UI honest while the shared structure settles the result.",
  },
  {
    slug: "coordination",
    title: "Presence & coordination",
    blurb:
      "Some facts belong to the session, not the document: who's here, who drives, and what they need to tell each other.",
  },
  {
    slug: "testing",
    title: "Testing & diagnostics",
    blurb:
      "Reproduce the failures that matter, and read the runtime's own diagnostics before you guess at a sync bug.",
  },
] as const;

export type ThemeSlug = (typeof themes)[number]["slug"];

export interface Practice {
  /** Anchor slug, on the guide step this practice is filed under. */
  id: string;
  /** Section title. */
  title: string;
  /** The build-guide step whose work this practice belongs to. */
  step: StepSlug;
  /** The problem theme /patterns files this under. */
  theme: ThemeSlug;
  /** Routes of the atlas / runtime sheets where this practice's problem
   *  shows up, e.g. "/structures/sequences". Renders a field-notes strip
   *  on those pages. */
  related?: string[];
  /** `Example.id` of the app that demonstrates this practice. */
  example: string;
  /** One-sentence imperative rule. */
  rule: string;
  /** Two or three short paragraphs: why it holds, the failure it prevents. */
  body: string[];
  /** Source-backed snippet descriptor from the practice registry. */
  snippet: Snippet;
  /** Only for Testing-group patterns: the check that pins the claim. */
  testNote?: string;
}

export const practices: Practice[] = [
  {
    id: "relay-decorator",
    title: "Treat the server as an optional decorator",
    step: "connect",
    theme: "architecture",
    related: ["/runtime/p2p", "/structures/counters"],
    example: "clap_counter_lustre",
    rule: "A peer-to-peer app may use a relay for durability, but it should not need one to start.",
    body: [
      "The clap counter has no sequencer, tenant, or token. If the URL names a relay, one function adds it to the peer-to-peer config.",
      "The app still becomes ready when that relay is down. It reports the outage instead of turning an optional service into a hidden requirement.",
    ],
    snippet: practiceSnippets["relay-decorator"],
  },
  {
    id: "shared-core-two-runtimes",
    title: "One shared core, two runtimes",
    step: "connect",
    theme: "architecture",
    example: "dice_cli",
    rule: "Keep the shared core portable by connecting to the same document from the BEAM and the browser.",
    body: [
      "dice_cli and dice_lustre edit the same floodgate document. They share the kernel, wire format, and runtime core; only the outer program changes. The browser uses an MVU update function, while the BEAM client uses a receive loop.",
      "The CLI connects to 127.0.0.1 instead of localhost. Erlang's resolver stalls about eight seconds on the AAAA lookup, long enough for the server to drop the connection.",
    ],
    snippet: practiceSnippets["shared-core-two-runtimes"],
  },
  {
    id: "diagnostics-first",
    title: "Sample diagnostics on every event",
    step: "connect",
    theme: "testing",
    related: ["/runtime/optimistic", "/runtime/reconnect"],
    example: "dice_lustre",
    rule: "Put the runtime's diagnostics on screen before you debug synchronization.",
    body: [
      "The smallest browser example updates one diagnostics line after every event. It shows the connection phase, client id, sequence numbers, queued operations, and resubmit checkpoint.",
      "Those values tell you where to look. A stuck in_flight count, a growing buffer, and a connection that never reaches synced point to different problems that application state cannot show.",
    ],
    snippet: practiceSnippets["diagnostics-first"],
  },
  {
    id: "quorum-pending-roster",
    title: "Propose on release, render the pending signoff",
    step: "votes",
    theme: "conflicts",
    related: ["/structures/coordination", "/runtime/optimistic"],
    example: "drum_machine_lustre",
    rule: "Send one consensus proposal per gesture, then show whose approval is still missing.",
    body: [
      "A PactMap stores the tempo and accepts a change after every connected client approves it. The slider sends its proposal on release. Sending one on every pointer move would overwhelm a protocol that allows only one pending proposal.",
      "While the group decides, the UI disables the slider and names the clients that have not approved. A short poll catches changes that the kernel does not report as events.",
    ],
    snippet: practiceSnippets["quorum-pending-roster"],
  },
  {
    id: "realtime-out-of-band",
    title: "Keep latency-critical loops out of the update path",
    step: "presence",
    theme: "architecture",
    example: "drum_machine_lustre",
    rule: "Let a real-time loop read a plain snapshot. Do not make it wait on the application.",
    body: [
      "The audio engine runs in an FFI module. Every 25 ms, it schedules the steps due in the next 100 ms against the audio clock. Gleam pushes pattern updates into a plain array, so document delays cannot become audio jitter.",
      "Background tabs create another trap: browsers slow timers while the audio clock keeps moving. When the tab returns, the scheduler resets its timing instead of playing every missed step at once.",
    ],
    snippet: practiceSnippets["realtime-out-of-band"],
  },
  {
    id: "presence-idiom",
    title: "The minimal presence idiom",
    step: "presence",
    theme: "coordination",
    related: ["/runtime/presence"],
    example: "retro_tutorial_lustre",
    rule: "Declare one presence effect, use one typed payload, and remove the local session before the roster enters your model.",
    body: [
      "The tutorial retro board shows the smallest complete presence setup. One effect starts the driver with an encoder and decoder. A helper removes the local session from the roster before the app stores it.",
      "watershed includes the local session on purpose; each app decides whether to show it. The richer cursors and avatar lists in other examples use the same setup with more data.",
    ],
    snippet: practiceSnippets["presence-idiom"],
  },
  {
    id: "protocol-on-ripples",
    title: "Ride an application protocol on ripples",
    step: "presence",
    theme: "coordination",
    related: ["/runtime/presence"],
    example: "grocery_triptych_lustre",
    rule: "Send short-lived coordination over ripples, not through a document channel.",
    body: [
      "The triptych's guided scenarios ask two tabs to choose a driver and exchange invitations, acknowledgements, and status updates. Ripples deliver those messages with a run id, and the document stores none of them.",
      "Plain functions match runs, ignore the sender's own messages, choose acknowledgements, and reject unknown message types. That keeps the protocol testable without a server.",
    ],
    snippet: practiceSnippets["protocol-on-ripples"],
  },
  {
    id: "pure-modules",
    title: "Extract pure modules; test without a server",
    step: "testing",
    theme: "testing",
    example: "grocery_triptych_lustre",
    rule: "Move decisions into pure modules so most tests need no document, sluice, or server.",
    body: [
      "The triptych separates decisions from effects. Its protocol, scenario state, and guards run as ordinary unit tests. The small refresh guard below uses a generation counter to discard an old refresh after a newer one arrives.",
      "Convergence and browser tests still cover behavior that needs a runtime. They stay small because pure tests cover the decision branches.",
    ],
    snippet: practiceSnippets["pure-modules"],
    testNote:
      "Six test files (protocol, scenario state, guards, actions) run pure, alongside one sluice convergence file and the smoke tier.",
  },
  {
    id: "ffi-surface",
    title: "Hand a rendering surface to FFI, and bootstrap on Connected",
    step: "connect",
    theme: "architecture",
    related: ["/foundations/lifecycle"],
    example: "pixel_canvas_lustre",
    rule: "Let an FFI module own the canvas pixels, and create shared channels only after the connection opens.",
    body: [
      "Lustre renders an empty canvas; an FFI module owns its byte buffer and 2D context. The view keeps the canvas size fixed because changing it erases the pixels. The FFI module looks up the context when it needs it, so mount order does not need another effect.",
      "The app creates its shared channel after Connected, not after GotHandle. A handle can resolve before the connection is ready, which would leave the app painting a canvas that no peer can see.",
    ],
    snippet: practiceSnippets["ffi-surface"],
  },
  {
    id: "fallible-edits",
    title: "Fallible edits render; never assert on a mutation",
    step: "notes",
    theme: "conflicts",
    related: ["/structures/sequences", "/runtime/optimistic"],
    example: "playlist_lustre",
    rule: "Handle every index-based edit as fallible. A peer may change the list between render and click.",
    body: [
      "A remote insert or delete can make a rendered index stale before the user clicks. The playlist sends every sequence edit through one helper and shows the runtime error in a banner instead of asserting success.",
      "The runtime refuses an index outside the list. It does not clamp the index, because that could move or delete the wrong track.",
    ],
    snippet: practiceSnippets["fallible-edits"],
  },
  {
    id: "authoritative-channel",
    title: "When a move is not atomic, crown one channel authoritative",
    step: "notes",
    theme: "conflicts",
    related: ["/structures/sequences", "/structures/coordination"],
    example: "retro_board_lustre",
    rule: "A move across channels is not atomic. Choose one source of truth and reconcile the rest while rendering.",
    body: [
      "Dragging a sticky note takes three operations across two channel types. The note's column field decides where it belongs. The view skips an id in the wrong column, puts missing ids at the end, and sends unknown columns to an unfiled strip.",
      "The view does not write repairs. If every client tried to clean up while rendering, they could fight over more operations. The next user move removes the stale id from the other columns.",
    ],
    snippet: practiceSnippets["authoritative-channel"],
  },
  {
    id: "stamp-schema",
    title: "Stamp the schema; refuse bad reads",
    step: "notes",
    theme: "architecture",
    related: ["/structures/maps", "/foundations/schema"],
    example: "scoreboard_cli",
    rule: "Fill and stamp a typed map before attaching it, so an incompatible reader gets an error.",
    body: [
      "The scoreboard has a root map, a roster, and one typed child map for each player. It fills a new player map in one write, stamps the schema version, then attaches the map to the roster.",
      "That stamp protects future readers from decoding the map with the wrong schema. Child lookup also retries because a remote handle may arrive before the operation that attaches its map.",
    ],
    snippet: practiceSnippets["stamp-schema"],
  },
  {
    id: "typedmap-panels",
    title: "Panels take a TypedMap, never a root",
    step: "connect",
    theme: "architecture",
    related: ["/structures/maps", "/foundations/topology"],
    example: "showcase_lustre",
    rule: "Give a reusable component a typed map, whether that map is a root or a child. Keep document-wide effects in the shell.",
    body: [
      "The showcase mounts four examples as panels in one document. Each panel accepts a TypedMap and cannot tell whether it received the root or a child map. The shell creates one child field for each panel.",
      "The shell also owns presence, offline mode, and summary policy because they affect the whole document. If panels started their own copies, presence messages could mix and the panels could compete over one shared setting.",
    ],
    snippet: practiceSnippets["typedmap-panels"],
  },
  {
    id: "claims-seeding",
    title: "Seed idempotently with Claims",
    step: "connect",
    theme: "conflicts",
    related: ["/structures/coordination", "/foundations/lifecycle"],
    example: "sudoku_lustre",
    rule: "Let every client seed the same initial values through first-writer-wins claims.",
    body: [
      "Every Sudoku client runs the same loop over the given cells. claim_once keeps the first value for each cell and ignores later attempts, so the clients settle on one puzzle without electing an initializer.",
      "Use this for initial values that must be written once. The shared structure settles duplicate work, so the app needs no separate setup protocol.",
    ],
    snippet: practiceSnippets["claims-seeding"],
  },
  {
    id: "anchors-not-offsets",
    title: "Anchors, not offsets",
    step: "notes",
    theme: "conflicts",
    related: ["/structures/sequences"],
    example: "text_lustre",
    rule: "Store an anchor instead of a text offset, then resolve its current position after each edit.",
    body: [
      "The editor turns each input into a small insert, delete, or replace. Remote edits would make saved integer positions stale, so bookmarks, carets, and shared cursors all use anchors that resolve to the current grapheme index.",
      "Anchor bias decides which nearby text a caret or selection follows as edits arrive. If an anchor no longer resolves, the app removes the marker instead of guessing.",
    ],
    snippet: practiceSnippets["anchors-not-offsets"],
  },
  {
    id: "unsettled-writes",
    title: "Show writes that have not settled",
    step: "votes",
    theme: "conflicts",
    related: ["/structures/coordination", "/runtime/optimistic"],
    example: "tournament_bracket_lustre",
    rule: "When writes are not optimistic, show them as pending until the confirming event arrives.",
    body: [
      "A RegisterCollection stores each match result under the Atomic policy, which chooses one compare-and-swap winner. Local writes stay hidden until the server orders them, so the bracket shows a submitted result as awaiting confirmation.",
      "VersionChanged reports every ordered submission, including the ones that lose. AtomicChanged reports only the winner and updates the official bracket. The log keeps the competing reports visible.",
    ],
    snippet: practiceSnippets["unsettled-writes"],
  },
  {
    id: "deterministic-death",
    title: "Test client death deterministically",
    step: "testing",
    theme: "testing",
    related: ["/structures/coordination", "/runtime/reconnect"],
    example: "work_queue_lustre",
    rule: "Test a client dying mid-job with an in-process disconnect that produces the same leave event as the server.",
    body: [
      "The work queue promises to recover when a client disappears. If a worker dies, the job returns to the queue. If the dispatcher dies, the next client takes over. An automated test needs to prove both transitions.",
      "sluice_js.disconnect produces the same leave event that the server would, so the test runs in process and on demand. A live smoke test covers the remaining boundary: whether floodgate notices a vanished socket and sends that event.",
    ],
    snippet: practiceSnippets["deterministic-death"],
    testNote:
      "The same harness asserts a dispatcher promotion arrives as a queue event, not an assignment, pinning the event shape of recovery rather than just its outcome.",
  },
];

const exampleById = new Map<string, Example>(examples.map((e) => [e.id, e]));

// The two CLI examples live in the repo but not in the browser-example
// catalog, so they carry their display names here.
const cliExampleNames: Record<string, string> = {
  dice_cli: "Dice CLI",
  scoreboard_cli: "Scoreboard CLI",
};

/** The catalog entry the practice is anchored to, if it is a browser example. */
export function exampleForPractice(practice: Practice): Example | null {
  return exampleById.get(practice.example) ?? null;
}

/** Display name for the anchoring example, catalog or not. */
export function practiceExampleName(practice: Practice): string {
  const name =
    exampleForPractice(practice)?.name ?? cliExampleNames[practice.example];
  if (!name) {
    throw new Error(
      `practice ${practice.id} names unknown example ${practice.example}`,
    );
  }
  return name;
}

/** GitHub link to the source file backing this practice's snippet. */
export function practiceSourceUrl(practice: Practice): string {
  return `https://github.com/tylerbutler/watershed/tree/main/${practice.snippet.sourcePath}`;
}

/** example id → the practices it demonstrates, for /examples chips. */
export const practicesByExample: Record<string, Practice[]> = {};
for (const practice of practices) {
  (practicesByExample[practice.example] ??= []).push(practice);
}

/** guide step slug → the practices filed under it, in catalog order. */
export const practicesByStep: Record<StepSlug, Practice[]> = Object.fromEntries(
  steps.map((step) => [
    step.slug,
    practices.filter((practice) => practice.step === step.slug),
  ]),
) as Record<StepSlug, Practice[]>;

/** Deep link to a practice, on the guide step that renders it. */
export function practiceHref(practice: Practice): string {
  return `/guide/${practice.step}#${practice.id}`;
}

/** theme slug → the practices filed under it, in catalog order. */
export const practicesByTheme: Record<ThemeSlug, Practice[]> = Object.fromEntries(
  themes.map((theme) => [
    theme.slug,
    practices.filter((practice) => practice.theme === theme.slug),
  ]),
) as Record<ThemeSlug, Practice[]>;

/** The practice with this id, for inline field-note callouts. Throws at build
 *  time on a stale id, so a renamed practice cannot leave a dead callout. */
export function practiceById(id: string): Practice {
  const practice = practices.find((p) => p.id === id);
  if (!practice) {
    throw new Error(`no practice with id ${id}`);
  }
  return practice;
}

/** The practices whose problem shows up on the given sheet route, e.g.
 *  "/structures/sequences" — for the field-notes strip on atlas and runtime
 *  pages. */
export function relatedPractices(page: string): Practice[] {
  return practices.filter((practice) => practice.related?.includes(page));
}
