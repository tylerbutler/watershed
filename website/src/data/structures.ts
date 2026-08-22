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
    tagline: "One number that many people can change at once without conflicts.",
    rule: "each client sends a signed change instead of a replacement value, so concurrent changes add together",
    optimistic: "your change appears next to the confirmed total before sequencing",
    summary: "the summary stores one total because each operation is an addition",
    how: [
      "A shared counter holds one integer. Each client submits a signed delta (+5, −1) instead of a new value. Addition is commutative, so the server can sequence deltas in any order. Each replica calculates the same total.",
      "Two clients can increment at the same time without overwriting an update. The client shows a local delta as an unsequenced Δ beside the committed value. After sequencing, the client adds the pending delta to the total.",
    ],
    useCases: [
      "Live tallies: votes, reactions, attendees, items in a shared cart",
      "Running totals where concurrent increases and decreases must not be lost",
      "Inventory or quota counters that many clients adjust at once",
    ],
  },
  {
    id: "gcounter",
    name: "GCounter",
    module: "lattice_counters/g_counter",
    kind: "CRDT",
    onHomepage: true,
    tagline: "A counter that only increases and stays correct if an update arrives twice.",
    rule: "each client keeps a separate total, and repeated changes do not change the merged result",
    optimistic:
      "your increment overlays the total in magenta until the server confirms it",
    summary: "each client’s running tally reloads intact",
    how: [
      "A grow-only counter keeps one increasing count for each replica. Client A can only increase A’s slot, and client B can only increase B’s slot. The visible value is the sum of all slots.",
      "To merge two states, the counter selects the larger count for each replica. This operation is idempotent, so a repeated delta has no effect. A G-counter cannot decrease.",
    ],
    useCases: [
      "Idempotent counters over at-least-once or unreliable delivery",
      "Distributed metrics where the same increment may arrive more than once",
      "A base for the PN counter and other lattice counters",
    ],
  },
  {
    id: "pn",
    name: "PnCounter",
    module: "pn_counter_kernel",
    kind: "CRDT",
    onHomepage: true,
    tagline: "A counter that increases or decreases and accepts repeated or unordered updates.",
    rule: "separate positive and negative totals support both directions and make repeated deltas idempotent",
    optimistic: "a client can resend additions and subtractions without counting them twice",
    summary: "per-client tallies survive reconnect and repeated delivery",
    how: [
      "A G-counter cannot decrease. A PN counter adds decrements by combining two G-counters: one for positive changes and one for negative changes. Each replica has a slot in both counters. The value is the positive sum minus the negative sum.",
      "Each half uses a maximum-value merge. The result does not depend on update order, and repeated updates have no effect. An operation-based counter needs runtime deduplication for this safety. A PN counter gets the same safety from its merge operation.",
    ],
    useCases: [
      "Counters that increase and decrease under unreliable delivery, such as reserve and release or like and unlike",
      "Collaborative budgets or capacity that can increase and decrease concurrently",
      "Offline-first counters that reconcile on reconnect without dropping edits",
    ],
  },
];

const sets: Structure[] = [
  {
    id: "gset",
    name: "GSet",
    module: "g_set_kernel",
    kind: "CRDT",
    onHomepage: true,
    tagline: "A set that only accepts additions.",
    rule: "an add-only set; after an element is added, it remains, and merging uses union",
    optimistic:
      "your addition shows in magenta until the server confirms it",
    summary: "the confirmed set reloads as a permanent record",
    how: [
      "A G-set only adds elements. To merge two replicas, it calculates their union. Union is commutative, associative, and idempotent. Thus, additions can arrive in any order or more than once.",
      "The absence of removal makes the merge simple. The 2P-set and OR-set add removal metadata.",
    ],
    useCases: [
      "Append-only registries: recorded events, observed device IDs, seen keys",
      "Deduplicated event logs where membership only grows",
      "The base layer for removable set CRDTs",
    ],
  },
  {
    id: "twopset",
    name: "TwoPSet",
    module: "two_p_set_kernel",
    kind: "CRDT",
    onHomepage: true,
    tagline: "A set that permits one permanent removal for each item.",
    rule: "supports one permanent removal for each item",
    optimistic:
      "adds and removals show in magenta until the server confirms them",
    summary: "current items and removed ones reload together",
    how: [
      "A two-phase set has a grow-only add set and a grow-only tombstone set. An element is present when it is in the add set and not in the tombstone set.",
      "Both sets merge by union. After removal, an element cannot be added again because its tombstone remains. For concurrent addition and removal, removal wins on each replica. To reset an element, use a new set.",
    ],
    useCases: [
      "Membership where retirement is final: revoked credentials, decommissioned assets",
      "Audit or compliance sets where a removal must remain final",
      "Cases where remove-wins is correct and later addition is not allowed",
    ],
  },
  {
    id: "orset",
    name: "OrSet",
    module: "or_set_kernel",
    kind: "CRDT",
    onHomepage: true,
    tagline: "A set that supports addition, removal, and later addition.",
    rule: "add, remove, and add again all work; if addition and removal occur concurrently, addition wins",
    optimistic:
      "your change overlays the list in magenta until the server confirms it",
    summary: "current members and their removal history reload intact",
    how: [
      "An observed-remove set supports addition after removal. The kernel gives each addition a unique causal tag, also called a dot. A removal adds tombstones only for tags that the client has observed.",
      "If one client removes an element while another client adds it with a new tag, the new tag remains. Thus, addition wins this conflict. Use an OR-set for removable shared collections.",
    ],
    useCases: [
      "Collaborative selections, tags, labels, and shopping carts",
      "Durable roster membership edited concurrently by many clients; transient online presence belongs in ripples",
      "Removable sets that must support addition after removal",
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
    tagline: "A shared key-value map in which the last sequenced write to a key wins.",
    rule: "for each key, the last write in server order wins",
    optimistic:
      "your writes appear before confirmation and become final after server sequencing",
    summary: "confirmed entries reload with their keys and insertion order intact",
    how: [
      "watershed’s SharedMap follows Fluid Framework’s SharedMap kernel design. Keys contain JSON values. The server sequences each set operation. For each key, the write with the highest sequence number wins. The set, delete, and clear payloads match the @fluidframework/map operation encoding.",
      "Server order resolves concurrent writes. A local write appears before confirmation. An acknowledgment confirms it, but a later write to the same key can replace it. Reference-generated tests cover map state, events, and convergence. watershed uses its own attachment and summary formats, so it does not provide Fluid container compatibility.",
    ],
    useCases: [
      "Shared application state and settings objects edited by many clients",
      "Learning and testing server-ordered last-write-wins collaboration",
      "Key-value collaboration where a last-write-wins rule is acceptable",
    ],
  },
  {
    id: "ormap",
    name: "OrMap",
    module: "or_map_kernel",
    kind: "CRDT",
    onHomepage: true,
    tagline: "A map in which a concurrent edit survives deletion of the same key.",
    rule: "delete a key while someone else edits it, and the edit survives (the write wins)",
    optimistic: "deleted rows stay readable until the server confirms the delete",
    summary: "the summary stores current entries and their edit history",
    how: [
      "An OR-map applies observed-remove rules to keyed entries. Each entry has causal dots. Removing a key adds tombstones only for observed dots. A concurrent write uses a new dot and therefore survives deletion.",
      "Values can be additive totals. In this mode, the map acts as a keyed CRDT ledger. The demo uses this mode for a stockpile ledger.",
    ],
    useCases: [
      "Keyed ledgers edited offline or concurrently (stockpiles, inventories, per-key counters)",
      "Maps where deleting and concurrently updating a key must not lose the update",
      "A CRDT alternative to SharedMap when last-write-wins would lose data",
    ],
  },
  {
    id: "directory",
    name: "SharedDirectory",
    module: "directory_kernel",
    kind: "DDS",
    onHomepage: false,
    demoHref: "/directory",
    tagline: "SharedMap with folders: nested key groups in which each folder keeps its identity.",
    rule: "like SharedMap, but with folders; each folder keeps its identity after deletion and recreation",
    optimistic: "folder and key edits appear at once until the server confirms them",
    summary: "the whole folder tree reloads intact",
    how: [
      "SharedDirectory is a recursive SharedMap modeled after Fluid Framework’s SharedDirectory design. Every folder node has a last-write-wins key-value store and a named set of child folders. Absolute paths such as /surveys and /surveys/intake address the folders. Storage follows the SharedMap rule: the server sequences each set, and the highest sequence number wins for each key.",
      "The kernel must preserve hierarchical identity. Two clients can create a folder at the same time. A client can delete and recreate that folder at the same path. Each replica must still identify the same folder instance. The kernel derives identity from creator IDs, creation sequence data, and each operation’s reference sequence number. It ignores a stale operation that targets an old path instance. Concurrent creates with the same name merge into one folder. A flat map cannot represent this identity.",
    ],
    useCases: [
      "Nested collaborative state: document trees, project and site hierarchies, scene graphs",
      "Studying hierarchical identity and server-ordered folder collaboration",
      "Grouped keys such as folders of readings or grouped settings",
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
      "An ordered list that supports concurrent insert, move, replace, and delete operations.",
    rule: "each item has a stable identity, so concurrent operations merge without depending on old indices",
    optimistic:
      "your edit appears at once in magenta; items move when the sequenced order arrives",
    summary: "the sequenced list reloads intact; pending edits replay on top",
    how: [
      "A shared sequence contains an ordered list of JSON values. An application specifies an edit by index, such as insert at 2 or move 4 to 1. The operation records the item’s stable identity instead of its position. The kernel applies a move to the same item after concurrent edits. Two inserts at the same position both remain in a deterministic order.",
      "The merge accepts repeated deltas and deltas in any order. Local edits appear before confirmation. If the server rejects an edit, the client reverses it and reapplies the remaining pending edits to confirmed state.",
      "Replace is a combined operation. It deletes the visible item and inserts a replacement at the same position. The client records one pending entry, one wire operation, and one event. watershed defines this CRDT design and wire format.",
    ],
    useCases: [
      "Shared itineraries, checklists, and ordered plans edited by many users",
      "Reorderable collections where a move must not overwrite a concurrent edit, such as playlists, priority queues, and kanban lanes",
      "The ordered base for SharedText, which uses the same identity lattice",
    ],
  },
  {
    id: "text",
    name: "SharedText",
    module: "text_kernel",
    kind: "CRDT",
    onHomepage: false,
    demoHref: "/text",
    tagline:
      "A shared string that preserves concurrent insert, delete, and replace operations.",
    rule: "each grapheme has a stable identity, so concurrent edits merge without depending on old character offsets",
    optimistic:
      "your keystroke appears at once in magenta; the text reflows when the sequenced order arrives",
    summary: "the sequenced string reloads intact; pending edits replay on top",
    how: [
      "A shared text contains an ordered sequence of graphemes, or user-perceived characters. An application specifies an edit by grapheme index. The operation records stable grapheme identities instead of offsets. Thus, two users can edit the same word concurrently. Insertions at the same gap both remain in a deterministic order.",
      "Indices count graphemes, not UTF-16 code units. A family emoji or a letter with a combining accent is one grapheme with one identity. A cursor cannot split the grapheme. The demo uses Intl.Segmenter to express each edit as one small grapheme span.",
      "Local edits appear before confirmation. If the server rejects an edit, the client reverses it and reapplies the remaining pending edits to confirmed state. Replace is one operation that deletes a span and inserts its replacement.",
      "Anchors identify stable positions. An application can attach an anchor to a grapheme identity and later resolve it to the current index. Shared cursors and selections use anchors to remain stable during concurrent edits. watershed defines the delta format on the same identity lattice as SharedSequence.",
    ],
    useCases: [
      "Collaborative notes, captions, and comment fields edited by many users",
      "Live labels and single-line fields where two users can edit the same word",
      "Shared cursors or selections that must keep their positions during nearby edits",
    ],
  },
];

const transforms: Structure[] = [
  {
    id: "json_ot",
    name: "JsonOt",
    module: "json_ot",
    kind: "OT",
    onHomepage: false,
    demoHref: "/json-ot",
    tagline: "One JSON document that supports concurrent edits with consistent results.",
    rule: "one shared JSON document; simultaneous edits adjust their paths and positions against each other",
    optimistic: "local edits appear at once; the client adjusts an in-flight change when confirmed peer edits arrive",
    summary: "the document reloads to the same value everywhere, including list positions",
    how: [
      "watershed’s json_ot kernel ports the ottypes json0 algebra used by ShareDB. It edits one JSON document with operations addressed by a path in the tree. Operations can set a key, insert or delete a list item, or splice a string.",
      "The client protocol permits one in-flight operation. A client applies an edit before confirmation and then sends it. The server sequences all operations. Clients transform concurrent operations against one another, such as by shifting a list index. All replicas then reach the same state.",
    ],
    useCases: [
      "Collaboratively edited structured documents (JSON trees, outlines, form models changed by many clients at once)",
      "Cases where last-write-wins would overwrite a concurrent edit but the application needs one shared document instead of per-key CRDTs",
      "Studying the json0 algebra used by ottypes and ShareDB",
    ],
  },
  {
    id: "rich_text",
    name: "SharedRichText",
    module: "rich_text_kernel",
    kind: "OT",
    onHomepage: false,
    demoHref: "/rich-text",
    tagline: "Rich-text operational transform for concurrent Quill editing.",
    rule: "one shared rich-text document; concurrent typing, formatting, and deletion operations transform their positions against each other",
    optimistic: "local Quill edits appear at once; the client adjusts an in-flight delta when confirmed peer edits arrive",
    summary: "the document reloads to the same text, formatting, and embeds everywhere",
    how: [
      "SharedRichText uses the same one-operation-in-flight protocol as json_ot with the rich-text/quill-delta algebra. Operations retain, insert, or delete text spans. They can also change attributes or insert an embed. Positions use UTF-16 code units, which are the units used by Quill and JavaScript strings.",
      "Each client keeps no more than one operation in flight. The client combines later input into one buffered operation. The runtime applies remote deltas to the editor without replacing the document. It also transforms cursor and selection positions through all edits. SharedText is the plain-text CRDT alternative. It indexes graphemes by stable identity and uses merge instead of transform.",
    ],
    useCases: [
      "Collaborative rich-text editors (Quill, and anything built on the quill-delta/rich-text algebra)",
      "Documents where plain characters, formatting, and embeds must survive concurrent edits",
      "Applications that use the ShareDB-style OT model and need rich text with json_ot structured documents",
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
    tagline: "First-writer-wins ownership of named slots without release.",
    rule: "the first client to claim a slot owns it; the server refuses each later claim",
    optimistic: "a claim appears as yours only after server confirmation",
    summary: "who owns what reloads intact",
    how: [
      "A claims register assigns exclusive ownership of named slots. The first sequenced claim becomes the holder. The structure refuses each later claim based on the current holder and reference sequence number.",
      "The client does not show a claim as the holder before confirmation. Magenta marks only the in-flight claim. The structure has no release operation. Use a new claims register to reset ownership.",
    ],
    useCases: [
      "Exclusive resource ownership: locks, seat or room assignment, leader election",
      "Uniqueness constraints (one owner per key, arbitrated by the server)",
      "Permanent first-writer-wins allocation",
    ],
  },
  {
    id: "registers",
    name: "RegisterCollection",
    module: "register_collection_kernel",
    kind: "DDS",
    onHomepage: true,
    tagline: "Single-value cells with first-writer-wins or last-write-wins reads.",
    rule: "read the first uncontested write, or the most recent one (your choice, per read)",
    optimistic:
      "writes stay hidden until confirmed, then settle as the winner or a kept version",
    summary: "every competing version is kept, so either read rule still works later",
    how: [
      "A register holds a single value with two read strategies. An atomic read selects the first non-concurrent writer. A last-write-wins read returns the most recent version by sequence number.",
      "The kernel retains concurrent versions with their sequence numbers, so the application can select either policy at read time. The client hides writes until sequencing, then shows the atomic winner or retained versions.",
    ],
    useCases: [
      "Single-value cells that need a choice of conflict policy per read",
      "Configuration or setpoint values that need either the first writer or the latest writer",
      "A coordination building block where retained versions matter",
    ],
  },
  {
    id: "ordered",
    name: "OrderedCollection",
    module: "ordered_collection_kernel",
    kind: "DDS",
    onHomepage: true,
    tagline: "A shared FIFO queue in which one client acquires each item.",
    rule: "items leave in the order the server received them; the first client to acquire an item holds it",
    optimistic: "queue changes stay hidden until the server confirms them",
    summary: "the queue and item owners reload intact",
    how: [
      "An ordered collection is a shared FIFO queue. Clients add, acquire, complete, and release items. The client shows these operations only after confirmation and resolves them in sequence order.",
      "If two clients acquire the same item, the first sequenced operation gets it. The second operation returns no item. Thus, two clients cannot hold the same item.",
    ],
    useCases: [
      "Work queues and job dispatch with exactly-one-owner semantics",
      "Turn-taking and ordered task handoff between collaborators",
      "Collections that need deterministic FIFO ordering across clients",
    ],
  },
  {
    id: "tasks",
    name: "TaskManager",
    module: "task_manager_kernel",
    kind: "DDS",
    onHomepage: false,
    tagline: "Task assignment with a volunteer queue and failover.",
    rule: "the first client to volunteer gets the task; the rest wait in line",
    optimistic:
      "the client shows each volunteer after server confirmation; one client wins and the rest queue",
    summary: "assignments and the waiting list survive reconnect",
    how: [
      "TaskManager builds on ordered semantics to coordinate who does what. Clients volunteer for named tasks; the first sequenced volunteer is assigned and later volunteers queue behind them in sequence order.",
      "If the assignee disconnects, the next queued volunteer takes over. Use TaskManager to divide exclusive work among clients that can disconnect.",
    ],
    useCases: [
      "Distributing exclusive tasks across peers (leader-per-task, sharded work)",
      "Failover assignment where a backup takes over after disconnection",
      "Collaborative apps dividing responsibilities across clients",
    ],
  },
  {
    id: "pact",
    name: "PactMap",
    module: "pact_map_kernel",
    kind: "DDS",
    onHomepage: true,
    tagline: "A map that applies a value only after all required clients agree.",
    rule: "a value takes effect only once every required client has signed off",
    optimistic: "a pending proposal blocks competing ones until clients accept it or the server drops it",
    summary: "the summary saves and restores accepted values and pending signoffs",
    how: [
      "A pact map requires agreement before it commits a value. When the server sequences a proposal, it fixes the list of required clients. Each connected client submits its acceptance operation.",
      "The map accepts the value after all required clients respond. For concurrent proposals, the first sequenced proposal wins. watershed models this design after Fluid’s quorum-consensus primitive.",
    ],
    useCases: [
      "Agreement before action, such as schema upgrades or feature-flag changes that all clients must honor",
      "Config that must be consistent across all clients before it takes effect",
      "Decisions that require explicit quorum",
    ],
  },
];

export const categories: Category[] = [
  {
    slug: "counters",
    name: "Counters",
    tagline: "Numbers that many clients change at the same time.",
    lede: [
      "Addition does not depend on order. Send each counter change as a signed delta instead of a new total. Concurrent changes then add together without overwriting.",
      "SharedCounter uses server sequencing. GCounter accepts repeated deltas but can only increase. PnCounter combines two grow-only counters so that it can increase or decrease.",
    ],
    structures: counters,
  },
  {
    slug: "sets",
    name: "Sets",
    tagline: "Collections that support concurrent additions and removals.",
    lede: [
      "Two clients can disagree about whether a set contains an element. Removal requires more causal metadata than addition.",
      "GSet supports only addition. TwoPSet adds permanent removals. OrSet supports addition after removal.",
    ],
    structures: sets,
  },
  {
    slug: "maps",
    name: "Maps",
    tagline: "Keyed state with different conflict rules.",
    lede: [
      "Collaborative applications commonly store keyed state in maps. The selected map type determines how it resolves concurrent changes.",
      "SharedMap uses server order and last-write-wins. OR-map stores causal dots so that a concurrent write survives deletion. SharedDirectory adds nested folders and stable folder identity.",
    ],
    structures: maps,
  },
  {
    slug: "sequences",
    name: "Sequences",
    tagline: "Ordered lists that accept concurrent changes.",
    lede: [
      "An index identifies a position in one version of a list. After concurrent insert, move, or delete operations, the same index can identify different items on different clients.",
      "Sequences give each item a stable identity. Applications specify edits by position, but the structures merge edits by identity. Concurrent inserts remain, and a move follows the selected item.",
    ],
    structures: sequences,
  },
  {
    slug: "coordination",
    name: "Coordination",
    tagline: "Structures for ownership, queues, and agreement.",
    lede: [
      "Coordination structures decide who holds a resource, who runs a task, or which value all clients accept. These structures often wait for confirmation before they show a result.",
      "The family includes first-writer-wins claims, versioned registers, FIFO queues, task failover, and quorum-controlled values.",
    ],
    structures: coordination,
  },
  {
    slug: "transforms",
    name: "Transforms",
    tagline: "One shared document that remains consistent during concurrent edits.",
    lede: [
      "Operational transform rewrites concurrent operations to account for one another. This differs from structures that merge state or deltas with a commutative rule.",
      "json_ot ports the ottypes json0 algebra and uses a one-operation-in-flight protocol. SharedRichText uses the same protocol with the quill-delta rich-text algebra. SharedText is a plain-text alternative that uses an identity-based CRDT merge.",
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
