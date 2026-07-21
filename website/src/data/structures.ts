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
  /**
   * Dedicated demo page, for structures whose interaction doesn't fit the
   * shared gauge demo (e.g. SharedDirectory's tree). When set, the structure is
   * excluded from the family's shared live demo and its plate links here
   * instead.
   */
  demoHref?: string;
}

export interface Category {
  slug: string;
  name: string;
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
    tagline: "One number that many people can add to at once, without conflicts.",
    rule: "everyone sends +/− changes instead of overwriting, so simultaneous edits just add up",
    optimistic: "your change shows next to the confirmed total right away",
    summary: "only one number needs saving, since every change is an add",
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
    tagline: "A count-up-only counter that stays correct even if an update arrives twice.",
    rule: "each client keeps its own tally; the totals combine safely even if a change arrives twice",
    optimistic:
      "your increment overlays the total in magenta until it’s confirmed",
    summary: "each client’s running tally reloads intact",
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
    tagline: "A counter that goes up and down and survives duplicate or out-of-order updates.",
    rule: "keeps separate up and down tallies, so it can move both ways and still shrug off duplicates",
    optimistic: "adds and subtractions can be re-sent without being counted twice",
    summary: "per-client tallies survive reconnect and repeated delivery",
    how: [
      "A single G-counter can only grow, which rules out decrements. A PN counter restores them by pairing two G-counters: a positive ledger and a negative ledger, each keyed by replica. The value you read is the positive sum minus the negative sum.",
      "Because each half is a max-merge CRDT, the whole thing is order- and duplicate-independent. A decrement re-delivered after reconnect is absorbed idempotently — the demo frames this as a cut-and-fill earthwork balance and lets you re-send a sequenced delta to watch the merge shrug it off. An op-based counter needs the runtime's sequence-number dedup to survive that; here the merge alone is enough.",
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
    tagline: "A set you can only add to — the simplest one that always agrees.",
    rule: "an add-only set; once something is in, it stays, and merging is a plain union",
    optimistic:
      "your addition shows in magenta until it’s confirmed",
    summary: "the confirmed set reloads as a permanent record",
    how: [
      "The simplest set CRDT. Elements can be added but never removed. Merging two replicas is a plain union — commutative, associative, and idempotent — so adds arrive in any order, any number of times, and everyone converges on the same membership.",
      "Removal is simply not expressible, which is exactly what makes a G-set trivially correct. When you do need removal, you layer tombstones on top — that is the 2P-set and OR-set below.",
    ],
    useCases: [
      "Append-only registries: recorded events, observed device IDs, seen keys",
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
    tagline: "A set you can remove from, but a removed item never comes back.",
    rule: "supports removal, but once an item is removed it can never be added again",
    optimistic:
      "adds and removals show in magenta until they’re confirmed",
    summary: "current items and removed ones reload together",
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
    tagline: "A set where add, remove, and add-again all work — the everyday choice.",
    rule: "add, remove, and add again all work; if an add and a remove race, the add wins",
    optimistic:
      "your change overlays the list in magenta until it’s confirmed",
    summary: "current members and their removal history reload intact",
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
    tagline: "A shared key/value map where the most recent write to a key wins.",
    rule: "for each key, the most recent write wins, decided by server order",
    optimistic:
      "your writes show instantly, then lock in once the server confirms them",
    summary: "entries reload with the exact keys a Fluid app expects",
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
    tagline: "A map where editing a key and deleting it at once won’t lose the edit.",
    rule: "delete a key while someone else edits it, and the edit survives — the write wins",
    optimistic: "deleted rows stay readable until the delete is confirmed",
    summary: "entries remember their edit history, not just the current value",
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
  {
    id: "directory",
    name: "SharedDirectory",
    module: "directory_kernel",
    kind: "DDS",
    onHomepage: false,
    demoHref: "/directory",
    tagline: "SharedMap with folders — nested groups of keys, each folder keeping its own identity.",
    rule: "like SharedMap, but with folders; each folder keeps its identity even if it’s deleted and remade",
    optimistic: "folder and key edits show immediately until the server confirms them",
    summary: "the whole folder tree reloads intact",
    how: [
      "SharedDirectory is SharedMap made recursive, and a byte-compatible port of Fluid Framework’s. Every folder node has its own last-write-wins key/value store plus a named set of child folders, addressed by absolute path — /surveys, /surveys/intake. Storage resolves exactly like SharedMap: each set is sequenced, highest sequence number wins per key.",
      "The hard part isn’t the storage — it’s hierarchical identity. A folder can be created by two clients at the same instant, deleted, and recreated under the same path, and every replica must still agree on which folder is which. The kernel models that identity explicitly from creator ids, create-sequence data, and each op’s reference sequence number, so a stale op targeting an old instance of a path is ignored while concurrent same-name creates merge into a single folder. That is what a flat map cannot express.",
    ],
    useCases: [
      "Nested, collaboratively-edited state: document trees, project/site hierarchies, scene graphs",
      "Fluid Framework interop where SharedDirectory wire-format compatibility matters",
      "Anywhere a flat map’s keys want structure — folders of readings, grouped settings",
    ],
  },
];

const sequences: Structure[] = [
  {
    id: "sequence",
    name: "SharedSequence",
    module: "sequence_kernel",
    kind: "CRDT",
    onHomepage: true,
    demoHref: "/sequence",
    tagline:
      "An ordered list many people can edit at once — insert, move, and reorder without losing anyone’s changes.",
    rule: "each item keeps a stable identity, so concurrent inserts, moves, and deletes merge instead of fighting over index numbers",
    optimistic:
      "your edit shows immediately in magenta; items slide when the sequenced order lands",
    summary: "the sequenced list reloads intact; pending edits replay on top",
    how: [
      "A shared sequence holds an ordered list of JSON values. You address an edit by index — insert at 2, move 4 to 1 — but the index only records intent. Underneath, every item carries a stable identity, and the CRDT delta that ships is expressed against identities, not positions. That is what lets two replicas edit the same region concurrently and still converge: a move follows the item it named rather than whatever later occupies its slot, and two inserts at one position both survive in a deterministic order.",
      "The lattice merge is duplicate- and order-tolerant: a delta delivered twice, or after its neighbors, is absorbed without disturbing the list. Local edits apply optimistically and ride the sequenced stream as deltas; if the server rejects one, it rolls back and the remaining pending edits replay over the sequenced base.",
      "Replace is composed rather than native: it deletes the visible item and inserts the replacement at the same position as one collaborative operation — one pending entry, one wire op, one event. Unlike SharedMap or SharedDirectory, this is not a Fluid Framework port; the wire format is watershed’s own.",
    ],
    useCases: [
      "Shared itineraries, checklists, and ordered plans edited by many hands",
      "Reorderable collections — playlists, priority queues, kanban lanes — where a move must not clobber a concurrent edit",
      "The ordered substrate beneath a future collaborative-text DDS",
    ],
  },
];

const transforms: Structure[] = [
  {
    id: "json_ot",
    name: "JSON OT",
    module: "json_ot",
    kind: "OT",
    onHomepage: false,
    demoHref: "/json-ot",
    tagline: "One shared JSON document that many people can edit at once and always agree on.",
    rule: "one shared JSON document; simultaneous edits are adjusted to fit around each other",
    optimistic: "you edit instantly; your in-flight change is adjusted as other people’s confirmed edits arrive",
    summary: "the document reloads to the same value everywhere, list positions and all",
    how: [
      "watershed’s json_ot kernel is a faithful port of the ottypes json0 algebra — the operational-transform model behind ShareDB. Instead of merging keys by rule, it edits one shared JSON document with a small algebra of operations addressed by a path into the tree: set a key, insert or delete a list item, splice a string.",
      "It runs the single-op-in-flight client protocol: a client applies an edit optimistically and sends it, keeping at most one op in flight. A Fluid-compatible server sequences every op, and concurrent ops are transformed past one another — a concurrent list insert has its index shifted — so all replicas reach byte-identical state, indices and all. This is the other convergence family: not merge, but transform.",
    ],
    useCases: [
      "Collaboratively edited structured documents — JSON trees, outlines, form models changed by many clients at once",
      "Cases where last-write-wins would clobber a concurrent edit but you want one shared document rather than per-key CRDTs",
      "Interop with ottypes / ShareDB json0 clients",
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
    tagline: "First come, first served ownership of named slots — no takebacks.",
    rule: "the first client to claim a slot owns it; every later claim is refused",
    optimistic: "a claim only shows as yours once it has actually won — never before",
    summary: "who owns what reloads intact",
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
    tagline: "Single-value cells you can read as first-writer-wins or most-recent-wins.",
    rule: "read the first uncontested write, or the most recent one — your choice, per read",
    optimistic:
      "writes stay hidden until confirmed, then settle as the winner or a kept version",
    summary: "every competing version is kept, so either read rule still works later",
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
    tagline: "A shared queue where the first client to grab an item holds it.",
    rule: "items come out in the order the server received them; first to grab one holds it",
    optimistic: "queue changes stay hidden until the server confirms them",
    summary: "the queue and who holds what reload intact",
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
    rule: "the first client to volunteer gets the task; the rest wait in line",
    optimistic:
      "volunteering only shows once it’s confirmed; one client wins and the rest queue",
    summary: "assignments and the waiting list survive reconnect",
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
    tagline: "A map where a value takes effect only after everyone required agrees.",
    rule: "a value takes effect only once every required client has signed off",
    optimistic: "a pending proposal blocks competing ones until it’s accepted or dropped",
    summary: "accepted values and pending sign-offs save and restore together",
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
    tagline: "Numbers that many hands move at once.",
    lede: [
      "Counters are the gentlest introduction to convergence, because addition does not care about order. Send each change as a signed delta instead of a new total, and simultaneous edits simply add up — there is nothing to overwrite.",
      "They climb in guarantee: a server-sequenced scalar, then a grow-only lattice that stays correct even when a delta is delivered twice, then a signed counter built from two of those lattices so it can move in both directions offline.",
    ],
    structures: counters,
  },
  {
    slug: "sets",
    name: "Sets",
    tagline: "Lists of things, as people add and remove at the same time.",
    lede: [
      "A set looks simple until two clients disagree about whether an element belongs. These are a short course in that problem: the more removal you want, the more causal bookkeeping you pay for.",
      "Start with add-only union, add irreversible tombstones, then reach the observed-remove set that lets you add, remove, and add again while staying convergent.",
    ],
    structures: sets,
  },
  {
    slug: "maps",
    name: "Maps",
    tagline: "Keyed state, resolved two different ways.",
    lede: [
      "Maps are where most collaborative apps keep their state, and where the choice of conflict model is most visible. watershed’s maps span that choice.",
      "SharedMap resolves each key by server order and is wire-compatible with Fluid Framework. OR-map keeps causal dots per entry so a concurrent write survives a delete — correctness over simplicity when last-write-wins would drop data. SharedDirectory makes SharedMap recursive: folders of keys and nested folders, with a hierarchical identity that survives concurrent creation and delete-then-recreate.",
    ],
    structures: maps,
  },
  {
    slug: "sequences",
    name: "Sequences",
    tagline: "Ordered lists that stay ordered while everyone rearranges them.",
    lede: [
      "Order is the hardest thing to agree on. An index is only meaningful against one version of a list — the moment two people insert, move, or delete concurrently, “position 3” names different items on different screens.",
      "Sequences resolve that by giving every item a stable identity beneath its index. Positions are how you address an edit; identities are how edits merge. Concurrent inserts at one spot both land, a move follows the item rather than the slot, and every replica converges on the same order.",
    ],
    structures: sequences,
  },
  {
    slug: "coordination",
    name: "Coordination",
    tagline: "Deciding who owns what, and agreeing before acting.",
    lede: [
      "The last family is not about merging values but about arbitrating decisions: who holds a resource, who runs a task, what everyone has agreed to. Reads here are often non-optimistic, because showing an outcome you might lose is worse than showing nothing.",
      "They ascend from first-writer-wins ownership through versioned registers, FIFO queues, and task failover to a quorum-consensus map that will not commit a value until every required client signs off.",
    ],
    structures: coordination,
  },
  {
    slug: "transforms",
    name: "Transforms",
    tagline: "One shared document, kept in agreement as everyone edits.",
    lede: [
      "The families above converge by merge rules — each replica applies the same commutative rule and lands the same state. This family converges the other way: operational transform, where concurrent ops are rewritten to account for one another.",
      "watershed’s json_ot kernel is a faithful port of the ottypes json0 algebra with the single-op-in-flight client protocol: every client edits one shared JSON document optimistically, a Fluid-compatible server sequences each op, and concurrent ops are transformed past one another so all replicas reach identical state, indices and all.",
    ],
    structures: transforms,
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
