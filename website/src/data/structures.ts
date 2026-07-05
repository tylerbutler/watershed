// ──────────────────────────────────────────────────────────────────────────
// watershed — data-structure catalog
// Single source of truth for the homepage field sheets and the /structures/*
// zoom-in pages. `rule`, `optimistic`, and `summary` reuse the homepage copy
// verbatim so the two surfaces never drift.
// ──────────────────────────────────────────────────────────────────────────

/** Merge model, matching the labels on the live demo picker. */
export type Kind = "DDS" | "CRDT" | "OT";

export interface Structure {
  /** Slug + anchor id; matches the demo picker `value` where one exists. */
  id: string;
  name: string;
  /** Gleam module path. */
  module: string;
  kind: Kind;
  /** Whether this structure appears in the homepage field-sheet stack. */
  onHomepage: boolean;
  /** One-line tagline for the detail-page header. */
  tagline: string;
  /** Merge / conflict rule (verbatim homepage copy). */
  rule: string;
  /** Optimistic behavior (verbatim homepage copy). */
  optimistic: string;
  /** Summary shape (verbatim homepage copy). */
  summary: string;
  /** How it works — one or more paragraphs, detail pages only. */
  how: string[];
  /** Best-fit use cases, detail pages only. */
  useCases: string[];
}

export interface Category {
  slug: string;
  name: string;
  /** Mono margin annotation, e.g. "Family 01 / 04". */
  index: string;
  /** Short header line for the category page and homepage group. */
  tagline: string;
  /** Lede paragraph(s) for the category page hero. */
  lede: string[];
  structures: Structure[];
}

const counters: Structure[] = [
  {
    id: "counter",
    name: "SharedCounter",
    module: "counter_kernel",
    kind: "DDS",
    onHomepage: true,
    tagline: "One integer, additive deltas, order-independent by construction.",
    rule: "increments commute, so concurrent adds converge on the sum",
    optimistic: "local deltas can be shown beside the committed value",
    summary: "a scalar summary is enough because every op is additive",
    how: [
      "A shared counter holds a single integer. Each client submits a signed delta — +5, −1 — rather than a new absolute value. Because addition commutes, the server can sequence those deltas in any order and every replica still lands on the same total.",
      "That is the whole trick: by shipping the change instead of the result, two clients incrementing at the same instant never clobber one another. A local delta renders immediately as an unsequenced Δ beside the committed value; when the sequencer stamps it, the pending delta folds into the total.",
    ],
    useCases: [
      "Live tallies: votes, reactions, attendees, items in a shared cart",
      "Running totals where concurrent +/− must never be lost and order does not matter",
      "Inventory or quota counters that many clients adjust at once",
    ],
  },
  {
    id: "gcounter",
    name: "G-Counter",
    module: "lattice_counters/g_counter",
    kind: "CRDT",
    onHomepage: true,
    tagline: "Per-replica grow-only tallies that merge by pairwise maximum.",
    rule: "per-replica grow-only counts merge by pairwise maximum",
    optimistic:
      "local increments overprint the total until their delta is sequenced",
    summary: "the counts dictionary reloads with each replica’s monotone tally",
    how: [
      "A grow-only counter keeps one monotone count per replica. Client A only ever raises A’s slot; client B only B’s. The visible value is the sum of every slot.",
      "Merging two states takes, for each replica, the larger of the two counts. That pairwise maximum is idempotent, so a delta delivered twice — after a reconnect, say — changes nothing the second time. The price is that a G-counter can only increase; it has no decrement.",
    ],
    useCases: [
      "Idempotent counters over at-least-once or unreliable delivery",
      "Distributed metrics where the same increment may arrive more than once",
      "The building block beneath the PN counter and other lattice counters",
    ],
  },
  {
    id: "pn",
    name: "PN Counter",
    module: "pn_counter_kernel",
    kind: "CRDT",
    onHomepage: true,
    tagline: "Two grow-only ledgers — fill and cut — netted into a signed value.",
    rule: "positive and negative grow-only ledgers join as a CRDT lattice",
    optimistic: "fill and cut deltas can be replayed without double-counting",
    summary: "replica-tagged tallies survive reconnect and duplicate delivery",
    how: [
      "A single G-counter can only grow, which rules out decrements. A PN counter restores them by pairing two G-counters: a positive ledger and a negative ledger, each keyed by replica. The value you read is the positive sum minus the negative sum.",
      "Because each half is a max-merge CRDT, the whole thing is order- and duplicate-independent. A decrement re-delivered after reconnect is absorbed idempotently — the demo frames this as a cut-and-fill earthwork balance and lets you re-send a sequenced delta to watch the merge shrug it off. An op-based counter could not survive that.",
    ],
    useCases: [
      "Counters that go up and down under unreliable delivery — reserve/release, like/unlike",
      "Collaborative budgets or capacity that both grows and shrinks concurrently",
      "Offline-first counters that reconcile on reconnect without dropping edits",
    ],
  },
];

const sets: Structure[] = [
  {
    id: "gset",
    name: "G-Set",
    module: "g_set_kernel",
    kind: "CRDT",
    onHomepage: true,
    tagline: "Add-only membership; merge is a plain set union.",
    rule: "grow-only set union; every recorded benchmark remains forever",
    optimistic:
      "local marks print as magenta overprint until their add delta is sequenced",
    summary: "the sequenced set reloads as permanent registry facts",
    how: [
      "The simplest set CRDT. Elements can be added but never removed. Merging two replicas is a plain union — commutative, associative, and idempotent — so adds arrive in any order, any number of times, and everyone converges on the same membership.",
      "Removal is simply not expressible, which is exactly what makes a G-set trivially correct. When you do need removal, you layer tombstones on top — that is the 2P-set and OR-set below.",
    ],
    useCases: [
      "Append-only registries: recorded benchmarks, observed device IDs, seen keys",
      "Deduplicated event logs where membership only ever grows",
      "The base layer for removable set CRDTs",
    ],
  },
  {
    id: "twopset",
    name: "2P-Set",
    module: "two_p_set_kernel",
    kind: "CRDT",
    onHomepage: true,
    tagline: "Adds plus tombstones; a removal wins permanently.",
    rule: "two grow-only sets join; tombstones permanently beat active membership",
    optimistic:
      "local place or retire deltas overprint the ledger until sequenced",
    summary: "active markers and retired tombstones reload together",
    how: [
      "A two-phase set layers a second grow-only set — of tombstones — over a grow-only set of adds. An element is a member when it is in the add-set and absent from the tombstone-set.",
      "Both halves only grow, so merge is two unions and convergence is guaranteed. The trade-off is stark: once removed, an element can never be re-added, because the tombstone always wins. Concurrent add-versus-remove resolves remove-wins on every replica, and a reset needs a fresh set rather than a shrinking op.",
    ],
    useCases: [
      "Membership where retirement is final: revoked credentials, decommissioned assets",
      "Audit or compliance sets where a removal must never silently reverse",
      "Cases where remove-wins is correct and re-adding is genuinely disallowed",
    ],
  },
  {
    id: "orset",
    name: "OR-Set",
    module: "or_set_kernel",
    kind: "CRDT",
    onHomepage: true,
    tagline: "Observed-remove with unique add tags; add-wins, re-add works.",
    rule: "observed-remove with add-wins tags under concurrent clear and re-mark",
    optimistic:
      "local marker changes overprint the roster until their delta is sequenced",
    summary: "live tags and tombstones reload under the joining replica identity",
    how: [
      "An observed-remove set fixes the 2P-set’s fatal flaw: you can add, remove, and add again. Every add attaches a unique causal tag (a dot), and a remove only tombstones the tags it has actually observed.",
      "So if one client removes an element while another concurrently adds it under a fresh tag, the new tag survives and the element stays — add-wins. That extra bookkeeping is why the OR-set is the workhorse removable set across collaborative apps.",
    ],
    useCases: [
      "Collaborative selections, tags, labels, and shopping carts",
      "Presence and roster sets edited concurrently by many clients",
      "Any removable set where re-adding a just-removed item must work",
    ],
  },
];

const maps: Structure[] = [
  {
    id: "map",
    name: "SharedMap",
    module: "map_kernel",
    kind: "DDS",
    onHomepage: true,
    tagline: "Last-write-wins per key by server sequence number.",
    rule: "server-sequenced last write wins per key",
    optimistic:
      "local writes can render optimistically until the sequencer stamps them",
    summary: "JSON entries reload with the same keys the Fluid wire op names",
    how: [
      "watershed’s flagship DDS, and a byte-compatible port of Fluid Framework’s SharedMap. Keys map to JSON values. Each set is sequenced, and for a given key the write with the highest sequence number wins.",
      "Concurrent writes resolve deterministically by server order rather than by a merge function. A local write renders immediately; the ack promotes it, and if a higher-SN write to the same key arrives it replaces the value. Because the summary uses the same key names as the Fluid wire ops, it is interchangeable with Fluid’s own.",
    ],
    useCases: [
      "Shared application state and settings objects edited by many clients",
      "Fluid Framework interop where wire-format compatibility matters",
      "Key-value collaboration where a clear last-writer-wins rule is acceptable",
    ],
  },
  {
    id: "ormap",
    name: "OR-Map",
    module: "or_map_kernel",
    kind: "CRDT",
    onHomepage: true,
    tagline: "Observed-remove keyed entries; a concurrent write survives a delete.",
    rule: "observed-remove with add-wins delivery under concurrent strike",
    optimistic: "struck rows can stay readable until the op is ordered",
    summary: "entries retain their causal dots, not just their visible value",
    how: [
      "An OR-map applies the OR-set’s observed-remove semantics to keyed entries. Each entry carries causal dots; removing a key only tombstones the dots it has observed, so a concurrent write to the same key survives a delete — add-wins.",
      "Values can themselves be additive tallies, which turns the map into a keyed CRDT ledger. In the demo it appears as a stockpile ledger where striking a row hides it and re-opening submits a +0 delta to surface the retained tally.",
    ],
    useCases: [
      "Keyed ledgers edited offline or concurrently — stockpiles, inventories, per-key counters",
      "Maps where deleting and concurrently updating a key must not lose the update",
      "A CRDT-correct alternative to SharedMap when last-write-wins would drop data",
    ],
  },
];

const coordination: Structure[] = [
  {
    id: "claims",
    name: "Claims",
    module: "claims_kernel",
    kind: "DDS",
    onHomepage: true,
    tagline: "First-writer-wins, write-once ownership of named slots.",
    rule: "first writer wins against the sequenced holder and reference SN",
    optimistic: "reads stay non-optimistic until the filed claim resolves",
    summary: "holder values reload with their sequence numbers intact",
    how: [
      "A claims register assigns exclusive ownership of named slots. The first client whose claim is sequenced becomes the holder; every later claim is refused against the sequenced holder and its reference sequence number.",
      "Reads are non-optimistic by design — a filed claim never shows as the holder until it actually wins, so the UI can never display a claim you might lose. Magenta annotates only the in-flight claim. There is no unclaim op; releasing means tearing off a fresh sheet.",
    ],
    useCases: [
      "Exclusive resource ownership: locks, seat or room assignment, leader election",
      "Uniqueness constraints — one owner per key, arbitrated by the server",
      "‘First one wins, no takebacks’ allocation",
    ],
  },
  {
    id: "registers",
    name: "Register collection",
    module: "register_collection_kernel",
    kind: "DDS",
    onHomepage: true,
    tagline: "Single-value cells with a choice of atomic or last-write-wins reads.",
    rule: "atomic reads pick the first non-concurrent write; LWW reads pick the latest version",
    optimistic:
      "writes stay invisible until sequenced, then resolve as atomic winners or retained versions",
    summary: "atomic and concurrent versions persist with sequence numbers",
    how: [
      "A register holds a single value with two read strategies. An atomic read resolves the first non-concurrent writer — a consensus-flavored pick — while a last-write-wins read returns the most recent version by sequence number.",
      "Concurrent versions are retained with their sequence numbers, so either policy can be applied at read time. Writes stay invisible until sequenced, then resolve as atomic winners or as retained versions.",
    ],
    useCases: [
      "Single-value cells that need a choice of conflict policy per read",
      "Config or setpoint values where you sometimes want first-writer, sometimes latest",
      "A coordination building block where retained versions matter",
    ],
  },
  {
    id: "ordered",
    name: "Ordered collection",
    module: "ordered_collection_kernel",
    kind: "DDS",
    onHomepage: true,
    tagline: "A shared FIFO queue; the first acquire holds the item.",
    rule: "adds and acquires resolve in FIFO sequence order",
    optimistic: "attached queue ops stay invisible until their SN arrives",
    summary: "queued items and held jobs reload with ownership intact",
    how: [
      "An ordered collection is a shared FIFO queue. Items are added, and clients acquire (dequeue) them; add, acquire, complete, and release are non-optimistic and resolve strictly in sequence order.",
      "When two clients race to acquire the same item, the first sequenced acquire holds it and the second resolves empty. The server order is the sole arbiter, so an item is never double-held.",
    ],
    useCases: [
      "Work queues and job dispatch with exactly-one-owner semantics",
      "Turn-taking and ordered task handoff between collaborators",
      "Anything needing deterministic FIFO ordering across clients",
    ],
  },
  {
    id: "tasks",
    name: "TaskManager",
    module: "task_manager_kernel",
    kind: "DDS",
    onHomepage: false,
    tagline: "Task assignment with a volunteer queue and automatic failover.",
    rule: "the first sequenced volunteer is assigned; the rest queue in order",
    optimistic:
      "volunteering is non-optimistic; the race assigns one and queues the rest",
    summary: "assignments and the volunteer queue persist across reconnect",
    how: [
      "TaskManager builds on ordered semantics to coordinate who does what. Clients volunteer for named tasks; the first sequenced volunteer is assigned and later volunteers queue behind them in sequence order.",
      "If the assignee drops, the next queued volunteer takes over automatically. It is the coordination primitive for dividing exclusive work across an unreliable set of collaborators.",
    ],
    useCases: [
      "Distributing exclusive tasks across peers — leader-per-task, sharded work",
      "Failover assignment where a backup should take over automatically",
      "Collaborative apps dividing responsibilities across clients",
    ],
  },
  {
    id: "pact",
    name: "Pact map",
    module: "pact_map_kernel",
    kind: "DDS",
    onHomepage: true,
    tagline: "Consensus map: a value is accepted only after a quorum signs off.",
    rule: "sets become accepted only after the frozen signoff list drains",
    optimistic: "pending proposals block competing sets until accepted or dropped",
    summary: "accepted values and pending signoffs round-trip together",
    how: [
      "A pact map is the strongest coordination structure here — it reaches agreement before committing. Proposing a value and sequencing that set freezes the list of clients who must sign off, and each connected client auto-submits the accept ops it owes.",
      "The value becomes accepted only once the signoff list drains. Concurrent proposals for the same pact resolve to the first sequenced one; the competitor is dropped. This is Fluid’s quorum-consensus primitive.",
    ],
    useCases: [
      "Agreement before action: schema upgrades, feature-flag flips everyone must honor",
      "Config that must be consistent across all clients before it takes effect",
      "Decisions requiring explicit quorum rather than last-write-wins",
    ],
  },
];

export const categories: Category[] = [
  {
    slug: "counters",
    name: "Counters",
    index: "Family 01 / 04",
    tagline: "Numbers that many hands move at once.",
    lede: [
      "Counters are the gentlest introduction to convergence, because addition does not care about order. Send each change as a signed delta instead of a new total, and simultaneous edits simply add up — there is nothing to overwrite.",
      "The three here climb in guarantee: a server-sequenced scalar, then a grow-only lattice that stays correct even when a delta is delivered twice, then a signed counter built from two of those lattices so it can move in both directions offline.",
    ],
    structures: counters,
  },
  {
    slug: "sets",
    name: "Sets",
    index: "Family 02 / 04",
    tagline: "Membership under concurrent add and remove.",
    lede: [
      "A set looks simple until two clients disagree about whether an element belongs. These three are a short course in that problem: the more removal you want, the more causal bookkeeping you pay for.",
      "Start with add-only union, add irreversible tombstones, then reach the observed-remove set that lets you add, remove, and add again while staying convergent.",
    ],
    structures: sets,
  },
  {
    slug: "maps",
    name: "Maps",
    index: "Family 03 / 04",
    tagline: "Keyed state, resolved two different ways.",
    lede: [
      "Maps are where most collaborative apps keep their state, and where the choice of conflict model is most visible. watershed ships two, at opposite ends of that choice.",
      "SharedMap resolves each key by server order and is wire-compatible with Fluid Framework. OR-map keeps causal dots per entry so a concurrent write survives a delete — correctness over simplicity when last-write-wins would drop data.",
    ],
    structures: maps,
  },
  {
    slug: "coordination",
    name: "Coordination",
    index: "Family 04 / 04",
    tagline: "Deciding who owns what, and agreeing before acting.",
    lede: [
      "The last family is not about merging values but about arbitrating decisions: who holds a resource, who runs a task, what everyone has agreed to. Reads here are often non-optimistic, because showing an outcome you might lose is worse than showing nothing.",
      "They ascend from first-writer-wins ownership through versioned registers, FIFO queues, and task failover to a quorum-consensus map that will not commit a value until every required client signs off.",
    ],
    structures: coordination,
  },
];

export const structuresBySlug: Record<string, Category> = Object.fromEntries(
  categories.map((c) => [c.slug, c]),
);

/** name → { slug, id } for cross-linking the homepage field sheets. */
export const structureLinks: Record<string, { slug: string; id: string }> =
  Object.fromEntries(
    categories.flatMap((c) =>
      c.structures.map((s) => [s.name, { slug: c.slug, id: s.id }]),
    ),
  );
