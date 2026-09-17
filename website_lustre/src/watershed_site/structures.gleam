import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type Kind {
  Dds
  Crdt
  Ot
}

pub type Entry {
  Entry(
    id: String,
    name: String,
    module_name: String,
    kind: Kind,
    tagline: String,
    rule: String,
    optimistic: String,
    summary: String,
    how: List(String),
    use_cases: List(String),
    demo_href: Option(String),
  )
}

pub type Family {
  Family(
    slug: String,
    name: String,
    tagline: String,
    lede: List(String),
    entries: List(Entry),
  )
}

pub fn all() -> List(Family) {
  [
    Family(
      "counters",
      "Counters",
      "Numbers that many hands move at once.",
      [
        "Counters are the gentlest introduction to convergence, because addition does not care about order. Send each change as a signed delta instead of a new total, and simultaneous edits simply add up; there is nothing to overwrite.",
        "They climb in guarantee: a server-sequenced scalar, then a grow-only lattice that stays correct even when a delta is delivered twice, then a signed counter built from two of those lattices so it can move in both directions offline.",
      ],
      [
        Entry(
          "counter",
          "SharedCounter",
          "counter_kernel",
          Dds,
          "One number that many people can add to at once, without conflicts.",
          "everyone sends +/− changes instead of overwriting, so simultaneous edits just add up",
          "your change shows next to the confirmed total right away",
          "only one number needs saving, since every change is an add",
          [
            "A shared counter holds a single integer. Each client submits a signed delta (+5, −1) rather than a new absolute value. Addition commutes, so the server can sequence deltas in any order and every replica lands on the same total.",
            "Shipping the change instead of the result is the whole trick: two clients incrementing at the same instant never clobber one another. A local delta renders immediately as an unsequenced Δ beside the committed value. When the sequencer stamps it, the pending delta folds into the total.",
          ],
          [
            "Live tallies: votes, reactions, attendees, items in a shared cart",
            "Running totals where concurrent +/− must never be lost and order does not matter",
            "Inventory or quota counters that many clients adjust at once",
          ],
          None,
        ),
        Entry(
          "gcounter",
          "GCounter",
          "g_counter_kernel",
          Crdt,
          "A count-up-only counter that stays correct even if an update arrives twice.",
          "each client keeps its own tally; the totals combine safely even if a change arrives twice",
          "your increment overlays the total in magenta until it's confirmed",
          "each client's running tally reloads intact",
          [
            "A grow-only counter keeps one monotone count per replica. Client A only ever raises A's slot; client B only B's. The visible value is the sum of every slot.",
            "Merging two states takes the larger count for each replica. That pairwise maximum is idempotent, so a delta delivered twice (after a reconnect, say) changes nothing the second time. The price: a G-counter can only increase. It has no decrement.",
          ],
          [
            "Idempotent counters over at-least-once or unreliable delivery",
            "Distributed metrics where the same increment may arrive more than once",
            "The building block beneath the PN counter and other lattice counters",
          ],
          None,
        ),
        Entry(
          "pn",
          "PnCounter",
          "pn_counter_kernel",
          Crdt,
          "A counter that goes up and down and survives duplicate or out-of-order updates.",
          "keeps separate up and down tallies, so it can move both ways and still shrug off duplicates",
          "adds and subtractions can be re-sent without being counted twice",
          "per-client tallies survive reconnect and repeated delivery",
          [
            "A single G-counter can only grow, which rules out decrements. A PN counter restores them by pairing two G-counters: a positive ledger and a negative ledger, each keyed by replica. The value you read is the positive sum minus the negative sum.",
            "Each half is a max-merge CRDT, so the whole thing is order- and duplicate-independent. A decrement re-delivered after reconnect is absorbed idempotently. The demo frames this as a cut-and-fill earthwork balance and lets you re-send a sequenced delta to watch the merge shrug it off. An op-based counter needs the runtime's sequence-number dedup to survive that; here the merge alone is enough.",
          ],
          [
            "Counters that go up and down under unreliable delivery (reserve/release, like/unlike)",
            "Collaborative budgets or capacity that both grows and shrinks concurrently",
            "Offline-first counters that reconcile on reconnect without dropping edits",
          ],
          None,
        ),
      ],
    ),
    Family(
      "sets",
      "Sets",
      "Lists of things, as people add and remove at the same time.",
      [
        "A set looks simple until two clients disagree about whether an element belongs. These are a short course in that problem: the more removal you want, the more causal bookkeeping you pay for.",
        "Start with add-only union, add irreversible tombstones, then reach the observed-remove set that lets you add, remove, and add again while staying convergent.",
      ],
      [
        Entry(
          "gset",
          "GSet",
          "g_set_kernel",
          Crdt,
          "A set you can only add to (the simplest one that always agrees).",
          "an add-only set; once something is in, it stays, and merging is a plain union",
          "your addition shows in magenta until it's confirmed",
          "the confirmed set reloads as a permanent record",
          [
            "The simplest set CRDT. Elements can be added but never removed. Merging two replicas is a plain union (commutative, associative, and idempotent), so adds arrive in any order, any number of times, and everyone converges on the same membership.",
            "Removal is not expressible, which is what makes a G-set trivially correct. When you need removal, you layer tombstones on top: the 2P-set and OR-set below.",
          ],
          [
            "Append-only registries: recorded events, observed device IDs, seen keys",
            "Deduplicated event logs where membership only ever grows",
            "The base layer for removable set CRDTs",
          ],
          None,
        ),
        Entry(
          "twopset",
          "TwoPSet",
          "two_p_set_kernel",
          Crdt,
          "A set you can remove from, but a removed item never comes back.",
          "supports removal, but once an item is removed it can never be added again",
          "adds and removals show in magenta until they're confirmed",
          "current items and removed ones reload together",
          [
            "A two-phase set layers a grow-only set of tombstones over a grow-only set of adds. An element is a member when it is in the add-set and absent from the tombstone-set.",
            "Both halves only grow, so merge is two unions and convergence is guaranteed. The trade-off is stark: once removed, an element can never be re-added, because the tombstone always wins. Concurrent add-versus-remove resolves remove-wins on every replica. A reset needs a fresh set rather than a shrinking op.",
          ],
          [
            "Membership where retirement is final: revoked credentials, decommissioned assets",
            "Audit or compliance sets where a removal must never silently reverse",
            "Cases where remove-wins is correct and re-adding is genuinely disallowed",
          ],
          None,
        ),
        Entry(
          "orset",
          "OrSet",
          "or_set_kernel",
          Crdt,
          "Add it, remove it, add it again: unlike a 2P-set, this one can bring an item back.",
          "add, remove, and add again all work; if an add and a remove race, the add wins",
          "your change overlays the list in magenta until it's confirmed",
          "current members and their removal history reload intact",
          [
            "An observed-remove set gets around the 2P-set's one-way removal: you can add, remove, and add again. Every add attaches a unique causal tag (a dot), and a remove only tombstones the tags it has actually observed.",
            "If one client removes an element while another concurrently adds it under a fresh tag, the new tag survives and the element stays (add-wins). That bookkeeping lets an item be removed and later re-added without giving up add-wins concurrency.",
          ],
          [
            "Collaborative selections, tags, labels, and shopping carts",
            "Durable roster membership edited concurrently by many clients; transient online presence belongs in ripples",
            "Any removable set where re-adding a just-removed item must work",
          ],
          None,
        ),
      ],
    ),
    Family(
      "registers",
      "Registers",
      "One shared value, and three different answers to a race.",
      [
        "A register is the smallest place collaboration can still go wrong: one cell, two writers, and no neutral meaning of “last.” The interesting part isn't storage. It's the rule that decides what survives.",
        "LWWRegister trusts timestamp and replica identity to select one winner without caring about delivery order. MvRegister refuses the forced choice and keeps concurrent answers until a writer who has seen them resolves them. RegisterCollection keeps every server-sequenced version so each read can choose the first uncontested write or the latest one.",
      ],
      [
        Entry(
          "lww-register",
          "LWWRegister",
          "lww_register_kernel",
          Crdt,
          "One shared string where the newest timestamp wins—and the author breaks a tie.",
          "the highest timestamp wins; equal timestamps break by replica ID, not arrival order",
          "your revision appears immediately while its timestamp waits to merge",
          "the winning value, timestamp, and author reload together",
          [
            "A last-writer-wins register stores one string plus the timestamp and replica ID that wrote it. Every replica merges by choosing the greater timestamp; if two writers use the same timestamp, the greater replica ID breaks the tie.",
            "That makes delivery order irrelevant, but it also makes the clock part of the data. The demo races two equal-time revisions, then re-delivers the winning delta: every client keeps the same winner and the duplicate changes nothing.",
          ],
          [
            "Offline settings where one deterministic winner is preferable to preserving every conflict",
            "Small shared labels, modes, or status fields with trustworthy logical clocks",
            "Cases where arrival order must not decide the winner",
          ],
          None,
        ),
        Entry(
          "mv-register",
          "MvRegister",
          "mv_register_kernel",
          Crdt,
          "One cell, several answers: concurrent revisions stay until someone resolves them.",
          "keep concurrent writes; a new write replaces only the history its author has seen",
          "your revision appears in magenta while the confirmed alternatives stay in ink",
          "tagged alternatives and the full causal clock survive reload, including retired history",
          [
            "Last-write-wins picks a winner. A multi-value register keeps the disagreement: two offline authors can write different revisions and every replica converges on both. The returned list is sorted for display, not ranked by time or preference.",
            "Resolution is an ordinary write after reading the alternatives. It replaces those observed revisions, not an unseen third writer. Equal text from concurrent authors still occupies two entries; an empty string is a value, not deletion.",
          ],
          [
            "Offline settings where silently dropping a revision would be a mistake",
            "Review workflows that ask a person to combine concurrent answers",
            "One shared string with an explicit conflict-resolution step",
          ],
          None,
        ),
        Entry(
          "registers",
          "RegisterCollection",
          "register_collection_kernel",
          Dds,
          "Single-value cells you can read as first-writer-wins or most-recent-wins.",
          "read the first uncontested write, or the most recent one (your choice, per read)",
          "writes stay hidden until confirmed, then settle as the winner or a kept version",
          "every competing version is kept, so either read rule still works later",
          [
            "A register holds a single value with two read strategies. An atomic read resolves the first non-concurrent writer (a consensus-flavored pick). A last-write-wins read returns the most recent version by sequence number.",
            "Concurrent versions are retained with their sequence numbers, so either policy can be applied at read time. Writes stay invisible until sequenced, then resolve as atomic winners or as retained versions.",
          ],
          [
            "Single-value cells that need a choice of conflict policy per read",
            "Config or setpoint values where you sometimes want first-writer, sometimes latest",
            "A coordination building block where retained versions matter",
          ],
          None,
        ),
      ],
    ),
    Family(
      "maps",
      "Maps",
      "Keyed state that picks a winner, keeps an edit, or grows into a tree.",
      [
        "Maps are where most collaborative apps keep their state, and where the choice of conflict model is most visible. watershed's maps span that choice.",
        "SharedMap resolves JSON and encoded-handle values by server order, following the last-write-wins design used by Fluid Framework. LWWMap lets each string key's timestamp outrank a later server SN, and keeps removals as tombstones. OR-map keeps causal dots per entry so a concurrent write survives a delete. SharedDirectory makes SharedMap recursive, with hierarchical identity that survives concurrent creation and delete-then-recreate.",
      ],
      [
        Entry(
          "map",
          "SharedMap",
          "map_kernel",
          Dds,
          "A shared key/value map where the most recent write to a key wins.",
          "for each key, the most recent write wins, decided by server order",
          "your writes show instantly, then lock in once the server confirms them",
          "confirmed entries reload with their keys and insertion order intact",
          [
            "watershed's flagship DDS follows Fluid Framework's SharedMap kernel design. Keys map to JSON values, including supported encoded handles. Each set is sequenced, and for a given key the write with the highest sequence number wins. Its inner set, delete, and clear payloads match the @fluidframework/map operation encoding.",
            "Concurrent writes resolve deterministically by server order rather than by a merge function. A local write renders immediately; the ack promotes it, and if a higher-SN write to the same key arrives it replaces the value. Reference-generated corpus tests cover map state, events, and convergence. Attach and summary formats remain watershed's own, so this does not imply drop-in Fluid container interoperability.",
            "Choose SharedMap for server-ordered JSON or handle state. Its summary keeps confirmed entries in insertion order, with no CRDT tombstones. LWWMap instead keeps strings, per-key timestamps, and tombstones, and reads keys in sorted order. Both can overwrite a concurrent losing value; neither preserves the disagreement for you.",
          ],
          [
            "Shared application state and settings objects edited by many clients",
            "Learning and testing server-ordered last-write-wins collaboration",
            "Key-value collaboration where a clear last-writer-wins rule is acceptable",
          ],
          None,
        ),
        Entry(
          "lww-map",
          "LWWMap",
          "lww_map_kernel",
          Crdt,
          "Shared string settings where a newer timestamp can beat a later server write.",
          "the greater per-key timestamp wins; at equal time, a tombstone beats a value and writer ID breaks a set/set tie",
          "your set or remove appears in magenta while confirmed entries stay in ink",
          "values, timestamps, and retained tombstones reload together; visible entries read in sorted-key order",
          [
            "Try racing two gate settings. A writes open with a newer timestamp, then B's closed gets the later server sequence number. LWWMap keeps open. SharedMap would keep closed: it follows server order, while LWWMap follows each key's timestamp through the sequenced runtime or the existing JavaScript CRDT mesh and relay paths.",
            "At equal time, the greater writer ID wins: B's closed beats A's open even though the values point the other way alphabetically. A tombstone still beats a value at the same time. That's different from OR-map's observed-remove, add-wins rule. Removal isn't unconditional remove-wins: an older write can't resurrect a tombstone, but a newer write can restore the key.",
            "The runtime supplies wall-clock time; the kernel advances it beyond the timestamp already observed or issued for that key, including pending edits and tombstones. Clock skew can still favor the writer whose clock is ahead. Last doesn't promise the most recent human action.",
            "You get string keys and string values, with set and remove. An empty string is a value. Unlike SharedMap's JSON values and supported encoded handles, LWWMap has no nested JSON or handle traversal, no clear, and no tombstone-pruning API. SharedMap reloads insertion order; LWWMap retains timestamped removals and returns visible entries sorted by key.",
            "Choose it when offline shared string settings need one deterministic winner and you can afford to lose another concurrent value. SharedMap also loses concurrent losing values. Neither is an MV register or a field-wise merge; use MvRegister when someone needs to read and resolve the disagreement.",
          ],
          [
            "Offline shared string settings with an acceptable deterministic single winner",
            "Per-key labels and modes that reconcile across the JavaScript mesh or relay",
            "String state where timestamps, rather than server sequence, should choose the winner",
          ],
          None,
        ),
        Entry(
          "ormap",
          "OrMap",
          "or_map_kernel",
          Crdt,
          "A map where editing a key and deleting it at once won't lose the edit.",
          "delete a key while someone else edits it, and the edit survives (the write wins)",
          "edits and removals show locally at once, with confirmed set members alongside",
          "entries remember their edit history, not just the current value",
          [
            "An OR-map applies the OR-set's observed-remove semantics to keyed entries. Each entry records causal dots; removing a key only tombstones the dots it has observed, so a concurrent write to the same key survives a delete (add-wins).",
            "Values can themselves be additive tallies, which turns the map into a keyed CRDT ledger. In the demo it appears as a stockpile ledger where striking a row hides it and re-opening submits a +0 delta to surface the retained tally.",
            "Switch the demo to string sets and each document gets a checklist. A adds draft while B adds reviewed: both members survive. Put those edits in SharedMap as separate JSON arrays instead and, in the same server order, only B's later whole array remains. A channel has one fixed, homogeneous mode: tallies, LWW registers, MV registers, or sets of strings. Switching between tallies and sets starts fresh OR-map replicas.",
            "In set mode, removing a member clears its observed add tags; removing a key also clears its observed members. An unseen concurrent addition survives. Removing the last member keeps a present empty set, while removing an absent member creates nothing. Add a removed key again and only its new members appear, even after an old delta is replayed. Causal metadata stays behind to enforce those removals; this is different from the tally mode's retained ledger.",
            "The ledger / string sets and MV registers views run separate instances of this same structure. Switching to MV registers preserves the ledger or checklist you've been editing.",
            "In MV-register mode, race two revisions under gate-mode and you'll see both answers. The OR-map keeps the key alive through remove/write concurrency; the MV register keeps alternatives inside that key. Resolve observed combines the selected client's alternatives in an ordinary write. It replaces only those observed revisions, so an unseen offline writer can still bring another answer.",
          ],
          [
            "Keyed ledgers edited offline or concurrently (stockpiles, inventories, per-key counters)",
            "Per-document string labels and checklists where concurrent member edits must merge",
            "Maps where deleting and concurrently updating a key must not lose the update",
            "A CRDT-correct alternative to SharedMap when last-write-wins would drop data",
          ],
          None,
        ),
        Entry(
          "directory",
          "SharedDirectory",
          "directory_kernel",
          Dds,
          "SharedMap with folders: nested groups of keys, each keeping its own identity.",
          "like SharedMap, but with folders; each folder keeps its identity even if it's deleted and remade",
          "folder and key edits show immediately until the server confirms them",
          "the whole folder tree reloads intact",
          [
            "SharedDirectory is SharedMap made recursive, modeled after Fluid Framework's SharedDirectory design. Every folder node has its own last-write-wins key/value store plus a named set of child folders, addressed by absolute path (/surveys, /surveys/intake). Storage resolves exactly like SharedMap: each set is sequenced, highest sequence number wins per key.",
            "The hard part is hierarchical identity, not storage. A folder can be created by two clients at the same instant, deleted, and recreated under the same path, and every replica must still agree on which folder is which. The kernel models that identity explicitly from creator ids, create-sequence data, and each op's reference sequence number. A stale op targeting an old instance of a path is ignored; concurrent same-name creates merge into a single folder. A flat map cannot express that.",
          ],
          [
            "Nested, collaboratively-edited state: document trees, project/site hierarchies, scene graphs",
            "Studying hierarchical identity and server-ordered folder collaboration",
            "Anywhere a flat map's keys want structure (folders of readings, grouped settings)",
          ],
          Some("/directory"),
        ),
      ],
    ),
    Family(
      "sequences",
      "Sequences",
      "Ordered lists that stay ordered while everyone rearranges them.",
      [
        "Order is the hardest thing to agree on. An index is only meaningful against one version of a list. The moment two people insert, move, or delete concurrently, “position 3” names different items on different screens.",
        "Sequences resolve that by giving every item a stable identity beneath its index. Positions are how you address an edit; identities are how edits merge. Concurrent inserts at one spot both land, a move follows the item rather than the slot, and every replica converges on the same order.",
      ],
      [
        Entry(
          "sequence",
          "SharedSequence",
          "sequence_kernel",
          Crdt,
          "An ordered list many people can edit at once: insert, move, and reorder without losing anyone's changes.",
          "each item keeps a stable identity, so concurrent inserts, moves, and deletes merge instead of fighting over index numbers",
          "your edit shows immediately in magenta; items slide when the sequenced order lands",
          "the sequenced list reloads intact; pending edits replay on top",
          [
            "A shared sequence holds an ordered list of JSON values. You address an edit by index (insert at 2, move 4 to 1), but the index only records intent. Underneath, every item has a stable identity, and the CRDT delta that ships is expressed against identities, not positions. Two replicas can therefore edit the same region concurrently and still converge: a move follows the item it named rather than whatever later occupies its slot, and two inserts at one position both survive in a deterministic order.",
            "The lattice merge is duplicate- and order-tolerant: a delta delivered twice, or after its neighbors, is absorbed without disturbing the list. Local edits apply optimistically and ride the sequenced stream as deltas; if the server rejects one, it rolls back and the remaining pending edits replay over the sequenced base.",
            "Replace is composed rather than native: it deletes the visible item and inserts the replacement at the same position as one collaborative operation (one pending entry, one wire op, one event). The identity-CRDT design and wire format are watershed's own.",
          ],
          [
            "Shared itineraries, checklists, and ordered plans edited by many hands",
            "Reorderable collections (playlists, priority queues, kanban lanes) where a move must not clobber a concurrent edit",
            "The ordered substrate beneath SharedText, the collaborative plain-text DDS built on the same identity lattice",
          ],
          Some("/sequence"),
        ),
        Entry(
          "text",
          "SharedText",
          "text_kernel",
          Crdt,
          "A string many people can type into at once: insert, delete, and replace characters without losing anyone's keystrokes.",
          "every grapheme keeps a stable identity, so concurrent insertions and overlapping edits merge instead of fighting over character offsets",
          "your keystroke shows immediately in magenta; the text reflows when the sequenced order lands",
          "the sequenced string reloads intact; pending edits replay on top",
          [
            "A shared text holds an ordered run of graphemes (user-perceived characters). You address an edit by grapheme index (insert at 6, delete 3..7, replace 0..5), but the index only records intent against your current view. Underneath, every grapheme has a stable identity, and the CRDT delta that ships is expressed against those identities, not offsets. Two typists can therefore edit the same word concurrently and still converge: an insertion lands beside the grapheme it named, and two insertions at one gap both survive in a deterministic order.",
            "Indexing is by grapheme, never by UTF-16 code unit. An emoji like 👨‍👩‍👧 or a combining sequence like é (e + ◌́) is one grapheme, one index, one identity. A cursor never splits a family emoji or strands a combining mark. The demo computes each edit as a single minimal grapheme span using Intl.Segmenter, so a keystroke becomes one insert, delete, or replace rather than a churn of code-unit diffs.",
            "Local edits apply optimistically and ride the sequenced stream as deltas; the visible string updates the instant you type. If the server rejects one it rolls back, and the remaining pending edits replay over the sequenced base. Replace is one collaborative operation (delete the span, insert the replacement at the same place), so it is a single pending entry, one wire op, one event, even across a range.",
            "Anchors are stable positions that survive concurrent edits: pin one to a grapheme's identity, keep editing around it, and resolve it back to a live index later. They are the basis for shared cursors and selections that don't drift when a neighbor inserts. The delta format is watershed's own, built on the same identity lattice as SharedSequence rather than Fluid's SharedString merge tree.",
          ],
          [
            "Collaborative notes, captions, and comment fields edited by many hands at once",
            "Live-typed labels and single-line fields where two people may touch the same word",
            "Anything needing shared cursors or selections that stay put as neighbors type (anchors track identities, not offsets)",
          ],
          Some("/text"),
        ),
      ],
    ),
    Family(
      "coordination",
      "Coordination",
      "Deciding who owns what, and agreeing before acting.",
      [
        "The last family arbitrates decisions rather than merging values: who holds a resource, who runs a task, what everyone has agreed to. Reads here are often non-optimistic, because showing an outcome you might lose is worse than showing nothing.",
        "They ascend from first-writer-wins ownership through FIFO queues and task failover to a quorum-consensus map that won't commit a value until every required client signs off.",
      ],
      [
        Entry(
          "claims",
          "Claims",
          "claims_kernel",
          Dds,
          "First come, first served ownership of named slots (no takebacks).",
          "the first client to claim a slot owns it; every later claim is refused",
          "a claim only shows as yours once it has actually won, never before",
          "who owns what reloads intact",
          [
            "A claims register assigns exclusive ownership of named slots. The first client whose claim is sequenced becomes the holder; every later claim is refused against the sequenced holder and its reference sequence number.",
            "Reads are non-optimistic by design: a filed claim never shows as the holder until it wins, so the UI can never display a claim you might lose. Magenta annotates only the in-flight claim. There is no unclaim op; releasing means tearing off a fresh sheet.",
          ],
          [
            "Exclusive resource ownership: locks, seat or room assignment, leader election",
            "Uniqueness constraints (one owner per key, arbitrated by the server)",
            "‘First one wins, no takebacks' allocation",
          ],
          None,
        ),
        Entry(
          "ordered",
          "OrderedCollection",
          "ordered_collection_kernel",
          Dds,
          "A shared queue where the first client to grab an item holds it.",
          "items come out in the order the server received them; first to grab one holds it",
          "queue changes stay hidden until the server confirms them",
          "the queue and who holds what reload intact",
          [
            "An ordered collection is a shared FIFO queue. Items are added, and clients acquire (dequeue) them; add, acquire, complete, and release are non-optimistic and resolve strictly in sequence order.",
            "When two clients race to acquire the same item, the first sequenced acquire holds it and the second resolves empty. The server order is the sole arbiter, so an item is never double-held.",
          ],
          [
            "Work queues and job dispatch with exactly-one-owner semantics",
            "Turn-taking and ordered task handoff between collaborators",
            "Anything needing deterministic FIFO ordering across clients",
          ],
          None,
        ),
        Entry(
          "tasks",
          "TaskManager",
          "task_manager_kernel",
          Dds,
          "Task assignment with a volunteer queue and automatic failover.",
          "the first client to volunteer gets the task; the rest wait in line",
          "volunteering only shows once it's confirmed; one client wins and the rest queue",
          "assignments and the waiting list survive reconnect",
          [
            "TaskManager builds on ordered semantics to coordinate who does what. Clients volunteer for named tasks; the first sequenced volunteer is assigned and later volunteers queue behind them in sequence order.",
            "If the assignee drops, the next queued volunteer takes over automatically. It is the coordination primitive for dividing exclusive work across an unreliable set of collaborators.",
          ],
          [
            "Distributing exclusive tasks across peers (leader-per-task, sharded work)",
            "Failover assignment where a backup should take over automatically",
            "Collaborative apps dividing responsibilities across clients",
          ],
          None,
        ),
        Entry(
          "pact",
          "PactMap",
          "pact_map_kernel",
          Dds,
          "A map where a value takes effect only after everyone required agrees.",
          "a value takes effect only once every required client has signed off",
          "a pending proposal blocks competing ones until it's accepted or dropped",
          "accepted values and pending sign-offs save and restore together",
          [
            "PactMap has watershed's strictest coordination rule: it reaches agreement before committing. Proposing a value and sequencing that set freezes the list of clients who must sign off, and each connected client auto-submits the accept ops it owes.",
            "The value becomes accepted only once the signoff list drains. Concurrent proposals for the same pact resolve to the first sequenced one; the competitor is dropped. The design is modeled after Fluid's quorum-consensus primitive.",
          ],
          [
            "Agreement before action: schema upgrades, feature-flag flips everyone must honor",
            "Config that must be consistent across all clients before it takes effect",
            "Decisions requiring explicit quorum rather than last-write-wins",
          ],
          None,
        ),
      ],
    ),
    Family(
      "transforms",
      "Transforms",
      "One shared document, kept in agreement as everyone edits.",
      [
        "The families above converge by merge rules: each replica applies the same commutative rule and lands the same state. This family converges the other way: operational transform, where concurrent ops are rewritten to account for one another.",
        "watershed's json_ot kernel is a faithful port of the ottypes json0 algebra with the single-op-in-flight client protocol. Every client edits one shared JSON document optimistically, a central server sequences each op, and concurrent ops are transformed past one another so all replicas reach identical state, indices and all. SharedRichText runs that same protocol over quill-delta's rich-text algebra (retain/insert/delete spans, attribute patches, embeds) for collaborative Quill editors. Both are OT-backed. SharedText, in the Sequences family, covers collaborative plain text with identity-based CRDT merge.",
      ],
      [
        Entry(
          "json_ot",
          "JsonOt",
          "json_ot",
          Ot,
          "One shared JSON document that many people can edit at once and always agree on.",
          "one shared JSON document; simultaneous edits are adjusted to fit around each other",
          "you edit instantly; your in-flight change is adjusted as other people's confirmed edits arrive",
          "the document reloads to the same value everywhere, list positions and all",
          [
            "watershed's json_ot kernel is a faithful port of the ottypes json0 algebra (the operational-transform model behind ShareDB). Instead of merging keys by rule, it edits one shared JSON document with a small algebra of operations addressed by a path into the tree: set a key, insert or delete a list item, splice a string.",
            "It runs the single-op-in-flight client protocol: a client applies an edit optimistically and sends it, keeping at most one op in flight. A central server sequences every op, and concurrent ops are transformed past one another (a concurrent list insert has its index shifted), so all replicas reach identical state, indices and all. This is the other convergence family: transform rather than merge.",
          ],
          [
            "Collaboratively edited structured documents (JSON trees, outlines, form models changed by many clients at once)",
            "Cases where last-write-wins would clobber a concurrent edit but you want one shared document rather than per-key CRDTs",
            "Studying the json0 algebra used by ottypes and ShareDB",
          ],
          Some("/json-ot"),
        ),
        Entry(
          "rich_text",
          "SharedRichText",
          "rich_text_kernel",
          Ot,
          "The json_ot protocol turned on rich text: three Quill editors, one document, real concurrent formatting.",
          "one shared rich-text document; concurrent typing, formatting, and deletes are transformed to fit around each other",
          "you edit instantly in Quill; your in-flight delta is adjusted as other people's confirmed edits arrive",
          "the document reloads to the same text, formatting, and embeds everywhere",
          [
            "SharedRichText runs the same single-op-in-flight client-transform protocol as json_ot, over a different algebra: a faithful port of rich-text/quill-delta. Operations retain, insert, or delete spans of text, each optionally carrying an attribute patch (bold, color, …) or wrapping an embed (an image) instead of plain text. Positions are counted in UTF-16 code units (the same units Quill and JavaScript strings use), so the runtime and the editor never disagree about where an edit lands.",
            "Each client keeps at most one op in flight; anything typed while it's outstanding composes into a single buffered op behind it. Remote deltas arrive already advanced into the client's optimistic view, and the runtime applies them incrementally to the editor rather than replacing the whole document. Cursor and selection positions are transformed through every local and remote edit the same way the text itself is. This is watershed's OT-backed rich text. SharedText is the CRDT-backed plain-text counterpart: it indexes graphemes by stable identity and converges by merge instead of transform.",
          ],
          [
            "Collaborative rich-text editors (Quill, and anything built on the quill-delta/rich-text algebra)",
            "Documents where formatting and embeds must survive concurrent edits, not just plain characters",
            "Teams already invested in the OT model (ShareDB-style) who want rich text alongside json_ot's structured documents",
          ],
          Some("/rich-text"),
        ),
      ],
    ),
  ]
}

pub fn get(slug: String) -> Result(Family, Nil) {
  list.find(all(), fn(family) { family.slug == slug })
}

pub fn neighbours(slug: String) -> #(Result(String, Nil), Result(String, Nil)) {
  case slug {
    "counters" -> #(Ok("transforms"), Ok("sets"))
    "sets" -> #(Ok("counters"), Ok("registers"))
    "registers" -> #(Ok("sets"), Ok("maps"))
    "maps" -> #(Ok("registers"), Ok("sequences"))
    "sequences" -> #(Ok("maps"), Ok("coordination"))
    "coordination" -> #(Ok("sequences"), Ok("transforms"))
    "transforms" -> #(Ok("coordination"), Ok("counters"))
    _ -> #(Error(Nil), Error(Nil))
  }
}

pub fn description() -> String {
  let names =
    all()
    |> list.map(fn(family) { string.lowercase(family.name) })
    |> string.join(", ")
  "Field guide to watershed's collaborative data structures, grouped into families: "
  <> names
  <> ". How each converges, and what it is best for."
}

pub fn description_for(family: Family) -> String {
  let entry_names =
    family.entries
    |> list.map(fn(entry) { entry.name })
    |> string.join(", ")
  family.name
  <> " in watershed: "
  <> family.tagline
  <> " "
  <> entry_names
  <> ". How each works, its merge rule, and what it is best for."
}

pub fn kind_name(kind: Kind) -> String {
  case kind {
    Dds -> "DDS"
    Crdt -> "CRDT"
    Ot -> "OT"
  }
}

pub fn model_description(kind: Kind) -> String {
  case kind {
    Crdt -> "Conflict-free replicated data type: converges by merge"
    Ot ->
      "Operational transform: converges by transforming concurrent operations"
    Dds -> "Distributed data structure: converges by server order"
  }
}
