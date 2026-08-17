# Demo ideas backlog

**Started:** 2026-08-08

Candidate example apps for `examples/`, kept here so they survive between sessions. Five have been promoted to full plans:

- `docs/plans/2026-08-08-pixel-canvas-demo-plan.md` — `OrMap` register mode, zero prerequisites
- `docs/plans/2026-08-08-retro-board-demo-plan.md` — `OrMap` both modes + `SharedSequence` + presence, zero prerequisites
- `docs/plans/2026-08-08-grocery-triptych-demo-plan.md` — `GSet` | `TwoPSet` | `OrSet`, **shipped, GT1–GT6**, `examples/grocery_triptych_lustre/`
- `docs/plans/2026-08-08-work-queue-demo-plan.md` — `OrderedCollection` + `TaskManager`, **shipped, WQ1–WQ7**, `examples/work_queue_lustre/`
- `docs/plans/2026-08-08-drum-machine-demo-plan.md` — `OrSet` + `PactMap`, **shipped, DM1–DM7**

And the gaps those plans surfaced have their own plan:

- `docs/plans/2026-08-08-facade-parity-sweep-plan.md` — FP1–FP6, **shipped**
- `docs/plans/2026-08-09-consensus-replay-quorum-plan.md` — **client half fixed**; a replaying client no longer rebuilds a consensus quorum from its present-day roster. What remains is the roster at a summary checkpoint, which is a floodgate change. `TaskManager` turned out never to have been affected.

One plan is not a demo but a way of presenting them:

- `docs/plans/2026-08-08-showcase-composition-plan.md` — SC1–SC8, existing examples composed as nested child maps in one document, one connection, one presence roster. Zero prerequisites; the work is refactoring examples into MVU components.

## Why this list exists: kind coverage

Coverage across `examples/` and the website demos as of 2026-08-08, updated 2026-08-11 as pixel canvas, retro board, and the clap counter shipped, and again as the release checklist shipped.

| State | Kinds |
|---|---|
| Well demoed | `SharedMap`, typed maps, `SharedSequence`, `SharedText`, `SharedCounter`, presence, ripples, `OrSet`, `GSet`, `TwoPSet`, `OrderedCollection`, `TaskManager`, `PactMap`, `RegisterCollection`, `OrMap` (pixel canvas, retro board), `PnCounter` (clap counter), `Claims` (sudoku, release checklist) |
| One site only | `SharedDirectory` + `JsonOt` (website pages only), `SharedRichText` (website only) |
| **No demo** | none |

`PactMap` came off the bottom row with the drum machine; `OrMap` and `PnCounter` came off it with the pixel canvas / retro board and the clap counter respectively; `Claims` moved from "one site only" to "well demoed" with the release checklist's captain seat and compare-and-set take-over. Every kind now has at least one example — the remaining gaps are the "one site only" row (getting `SharedDirectory`, `JsonOt`, and `SharedRichText` proper Lustre examples) and the unwired `GCounter` primitive noted under the clap counter below, which is a library gap rather than a demo gap.

## Two corrections worth not re-learning

Both of these were mis-assumed during the brainstorm that produced this list, and both would have produced a broken plan:

1. **`PactMap` is a quorum protocol, not a last-writer-wins map.** A set becomes *pending* with a frozen signoff list captured from the connected quorum, and only becomes accepted once that list drains via accept ops or membership leaves (`src/watershed/pact_map_kernel.gleam:1-5`). It is wrong for anything wanting fast uncoordinated writes, and right for "this setting changes only when the room agrees".
2. **`TaskManager` and `OrderedCollection` are consensus primitives, not collections you store things in.** `TaskManager` is a lock queue over named roles; `OrderedCollection` is a non-optimistic FIFO job queue with `acquire`/`complete`/`release`. Neither is a card store. See the work-queue plan for the full argument.

## Known gaps

All of FP1–FP6 shipped on 2026-08-08 (`docs/plans/2026-08-08-facade-parity-sweep-plan.md`): the real quorum roster, rich text on the JS facade, the three missing subscribes, the pending-signoff accessors, and the `watershed_lustre` fill-in. Both facades also expose `client_id` now, so a client can find itself in a list a kernel reports about the room.

One gap remains, and it is not a facade gap: **the roster at a summary checkpoint** — `docs/plans/2026-08-09-consensus-replay-quorum-plan.md`.

**Correction worth not re-learning:** an earlier version of this section claimed the `OrderedCollection` op surface and `complete_task` were missing from the facades. They were present on both. That came from grepping by prefix guess (`ordered_collection_*`, `task_*`), which misses `ordered_*` and `complete_task`. Audit by full `pub fn` inventory diff — the command is at the end of the parity plan, and `facade_parity_test.gleam` now enforces it mechanically.

The "full typed-layer parity across 14 kinds" milestone covered channel *lifecycle*. Operations, subscriptions, and **runtime semantics** were three further axes nobody had swept; the third is where both FP1 and the replay-quorum bug lived.

---

## Ideas

### ✅ Shipped: Grocery list triptych, `GSet` | `TwoPSet` | `OrSet`

→ `docs/plans/2026-08-08-grocery-triptych-demo-plan.md`, `examples/grocery_triptych_lustre/`

Three panels, one interaction, three set kinds. Remove `"milk"` and add it back: `TwoPSet` tombstones it, `OrSet` accepts it, `GSet` keeps it.

GT1–GT6 are complete. The FP5 prerequisite shipped before the example implementation, so there is no blocker note to carry here.

### ✅ Shipped — Drum machine / step sequencer — `OrSet` + `PactMap`

→ `docs/plans/2026-08-08-drum-machine-demo-plan.md`, `examples/drum_machine_lustre/`

DM1–DM7 are all in. The quorum tempo works for a live room and is covered by
three-client tests; building it turned up
`docs/plans/2026-08-09-consensus-replay-quorum-plan.md`, which is exactly what
this demo was supposed to do.

A 16×4 step grid, each track an `OrSet` of active step indices; everyone jams on the same loop. Convergence becomes *audible*.

**The correction worth keeping:**

- **Acceptance is automatic, not a vote.** `channel.gleam:726` auto-submits the `OweAccept` op — no client ever chooses to agree. The UI must read "waiting on 1 of 3 clients", never "2 of 3 agreed". An earlier sketch of this idea proposed the latter, which would misrepresent the protocol.

Also worth knowing: watershed converges state, not time, so clients are **not** phase-locked. The plan builds for per-client phase and says so in the UI rather than attempting clock sync.

### Chat with reactions — `SharedSequence` + `OrMap` + ripples

Message log as an append-only sequence, reactions as an `OrMap` (`message_id:emoji` → tally), typing indicators as ripples.

The clearest possible illustration of **durable ops vs ephemeral ripples**: typing indicators evaporate and are never in the summary, messages are never lost. That distinction is currently explained only in prose on `/guide/ripples`. Chat is also the most relatable collaborative app there is, which matters for a landing-page demo.

**Prerequisites:** none.
**Cost:** low-medium. Overlaps the retro board heavily on `OrMap` tally usage — build it after, and only if the reaction/ripple contrast is worth a second app.

### Live poll / audience Q&A — `OrSet` + `PnCounter` + `GSet`

Questions in an `OrSet`, votes per question, and a grow-only set of who has voted. `GSet` is *genuinely* correct for the voted-set rather than a toy choice — you can never un-vote, so grow-only is the honest model.

Doubles as real tooling for a conference talk about watershed, which is a nice property for a demo to have.

**Prerequisites:** `subscribe_pn_counter`, unless votes go in an `OrMap` tally like the retro board — in which case none, but then it stops being a `PnCounter` demo.

### ✅ Shipped: Clap counter — `PnCounter`

→ `examples/clap_counter_lustre/`

Medium-style claps. Trivially small, and the most direct possible stress test of a single counter under high concurrency: hold the button down in four tabs and watch the number stay correct.

Closed the `subscribe_pn_counter` demo gap: `PnCounter` was fully present on both facades but exercised by nothing in `examples/` until this shipped. The smoke test's headline assertion is concurrent, uncoordinated increments from two clients converging on the true sum with no lost update, surviving a forced reconnect.

**`PnCounter`, not a grow-only counter.** `lattice_counters` (the vendored CRDT library) ships `g_counter.gleam`, but nothing in `src/watershed/` wires it up — there's no `g_counter_kernel.gleam`, no `GCounter` type on either facade, no schema `ChannelField` variant, no runtime dispatch. Claps only ever go up; the app calls `pn_counter_update` with positive amounts only and never exercises the decrement path, but the kernel underneath is the full P/N lattice. Wiring up a real `GCounter` kind is its own small plan, not a prerequisite for this one — see `docs/demo-ideas.md`'s own history below for that discussion.

Not yet done: wiring the same widget onto the website's `counter-bug` page (broken-vs-correct side by side) — left as follow-on, low cost.

**Prerequisites:** `subscribe_pn_counter` (shipped).
**Cost:** very low.

### ✅ Shipped: Tournament bracket — `RegisterCollection`

→ `examples/tournament_bracket_lustre/`

Each match result is a register owned by one referee; refs report their own results with no coordination. `RegisterCollection` is "a collection of registers, each written by one owner", and a bracket is the one application where that is the obvious model rather than a contrivance.

Retired the last no-demo kind that none of the other ideas here reach. Fixed 8-player single-elimination (7 matches, 3 rounds), `Atomic` read policy, presence roster, and a convergence test for the payoff scenario: two tabs reporting the same match with different results concurrently, converging on one official winner while the loser's submission stays visible via `register_versions`.

### Shared form with field claims — typed layer + schema + `Claims`

A multi-field form where each field can be claimed: "Tyler is editing this field, it's locked". Sudoku already uses `Claims`, but for a game — this is the business-app framing, and more importantly it is the demo that puts the **typed layer and schema** in the foreground. Those are selling points with no example that centres them (`scoreboard_cli` uses them, but the CLI framing buries them).

**Prerequisites:** none.
**Cost:** low.

### Standup notes TUI — `OrMap` + `SharedText`, Erlang target

Three terminals converging on the same document. The CLI examples are thin (`dice_cli`, `scoreboard_cli`) and they are the only evidence that the pure core is genuinely target-agnostic rather than a browser trick. A TUI where three terminals visibly converge is a stronger version of that argument than either existing CLI demo.

**Prerequisites:** none, though a TUI library choice for Gleam-on-BEAM needs research.
**Cost:** medium, mostly in unfamiliar terrain.

### Collaborative spreadsheet — `SharedDirectory` + `JsonOt`

Hierarchical namespace maps to sheet → row → cell; formulas as `JsonOt`. The most impressive-looking thing on the list and the only idea that would exercise `SharedDirectory` as a real hierarchy rather than a documentation page.

**Prerequisites:** FP5 — `watershed_lustre` has neither `ensure_directory`/`subscribe_directory` nor `ensure_json_ot`/`subscribe_json_ot`.
**Cost: heavy.** Formula evaluation, dependency graphs, and cell selection are a lot of non-watershed code. Only worth it if a flagship demo is wanted for a launch, and probably not before then.

### Collaborative rich-text editor — `SharedRichText`

Not on the original list, but FP2 makes the case. `SharedRichText` is fully present on the BEAM facade and entirely absent from the JS one, and the existing website demo works only by importing private modules. Once FP2 lands, a proper Lustre rich-text example — the Quill bridge the website demo already prototypes, packaged the way `watershed_lustre/textarea` packaged the plain-text one — is mostly extraction rather than invention.

**Prerequisites:** FP2, then FP5's `ensure_rich_text` / `subscribe_rich_text`.
**Cost:** medium, and much of it already written in `website/src/scripts/rich-text-demo.ts`.

### Whiteboard / diagram editor — `OrMap` + `SharedSequence` + presence

Shapes in an `OrMap`, z-order in a sequence, live cursors. Standard, strong, and the thing people expect to see. But it is the pixel canvas's story (visual convergence) at several times the cost, so it should not be built until the pixel canvas has shipped and proven the story is worth deepening.

### Jukebox — extend `examples/playlist_lustre`

Add `OrMap` tally votes to the existing playlist and re-sort by score. The cheapest item on the entire list — it reuses a working example and adds one channel.

Good filler work, but it makes an existing example more complicated rather than adding a new claim, so it ranks below anything that clears a no-demo kind.

### Collaborative JSON workspace: `SharedDirectory` + `JsonOt` + presence

A project tree whose directories contain named JSON documents. Selecting a
document opens a structured property editor, and presence shows which path each
peer has open. Two clients can change nested values while disconnected, then
rejoin and converge through the same JSON OT path that the website demonstrates
today.

This is the smaller alternative to the spreadsheet. It demonstrates directory
creation, deletion, and recreation plus concurrent JSON edits without formula
evaluation, dependency graphs, or a grid widget. The payoff test should combine
the two important races: recreate a directory while another client still holds
its old instance, and edit separate paths in one JSON document before
reconnecting.

**Prerequisites:** none. FP5 shipped the Lustre directory and JSON OT effects.
**Cost:** medium.

### RFC publishing room: `SharedRichText` + `PactMap` + presence

A shared RFC draft with rich-text formatting and one published-revision slot.
Authors edit the draft without coordination. Publishing copies the current
revision into a `PactMap`, where it stays pending until every client in the
frozen signoff list has acknowledged the sequenced value.

The UI must describe protocol acknowledgement, not human approval. Watershed
submits accept operations automatically, so controls such as "approve" or
"vote" would teach the wrong model. The useful contrast is immediate,
optimistic drafting beside a publication state that the room has not settled
yet.

This gives `SharedRichText` a proper Lustre example and reuses the Quill bridge
already prototyped on the website. A deterministic test can hold one client's
frames, assert that publication remains pending, then deliver its
acknowledgement and observe acceptance.

**Prerequisites:** none. FP2 and FP5 shipped the public JS and Lustre surfaces.
**Cost:** medium.

### Incident command board: `Claims` + `SharedSequence` + `OrMap`

An incident room with claimed responder roles, an ordered event timeline, and a
shared resource board. `Claims` decides concurrent attempts to take the same
role at sequencing time. A deliberate compare-and-set handoff transfers a role
from one responder to another; presence can show who remains connected without
pretending that disconnect automatically releases durable ownership.

The headline race is two responders claiming incident commander at once. One
wins, the loser sees the committed owner, and both clients append follow-up
events to the same timeline. The resource board can use `OrMap` register mode
for items whose edits should survive concurrent remove and update.

This combines coordination with ordinary collaborative state in a familiar
operational setting. Keep the incident model fixed and small so the example
does not turn into a ticketing system.

**Prerequisites:** none.
**Cost:** medium.

### Browser and BEAM control room: typed document across both targets

Run one existing typed application in a browser and expose the same document
through a small BEAM terminal client. The terminal can list state, submit one
mutation, go offline, reconnect, and print the converged snapshot while the
browser renders each change.

This makes the target-independence claim visible. The current CLI and browser
examples use separate applications, so visitors must infer that both runtimes
can join the same room. Reusing the Flowboard schema would avoid inventing
another domain and keep the new code focused on transport and runtime parity.

The payoff check starts one sluice or live floodgate room, connects one client
through each facade, performs concurrent edits, and compares their final typed
snapshots.

**Prerequisites:** choose an existing example schema that can move into a small
shared package without coupling its UI to the BEAM client.
**Cost:** low.

### Collaborative form builder: `SharedDirectory` + `JsonOt` + `Claims`

A form designer with sections in a directory tree, a JSON OT schema for each
section, and claims on fields undergoing structural edits. One user can reorder
or rename a section while another edits validation rules inside a different
section.

The example should focus on schema design rather than form submission. Claims
protect edits that need one temporary owner, while JSON OT merges independent
property changes and the directory models section hierarchy. The UI must show
that a pending claim has no committed owner until sequencing resolves it.

This uses the same underrepresented structures as the JSON workspace but makes
the typed-layer and coordination story stronger. Build one of the two, not
both, unless users need both a minimal primitive demo and a business-app demo.

**Prerequisites:** none.
**Cost:** medium-high.

### Open planning poker: `RegisterCollection` + presence

Give each participant one named estimate register. Estimates sequence without
optimistic display, and every concurrent submission remains available through
the register's version history even though the atomic read settles on one
official value.

This is open estimation, not a secret ballot. Register values are shared state,
so a reveal phase would require encryption or a trusted server and would bury
the data-structure lesson. The useful race is one participant submitting from
two sessions at once: everyone converges on the atomic estimate while the
losing submission stays inspectable.

Compared with the tournament bracket, this removes bracket mechanics and puts
register ownership, committed-only reads, and retained conflicts at the center.

**Prerequisites:** none.
**Cost:** low.

### ✅ Shipped: Release checklist — `OrSet` + `Claims` + `PactMap`

→ `examples/release_checklist_lustre/`

A fixed release room where an `OrSet` records completed checks, `Claims`
selects one release captain, and a `PactMap` carries the release target once all
connected clients have acknowledged it. Concurrent completion and reopening of
checks use observed-remove semantics instead of a last-write-wins boolean.

The demo must keep checklist completion separate from publication. `PactMap`
does not collect human votes; clients acknowledge the pending value
automatically. The UI can show "waiting for 1 connected client" while a paused
tab delays publication, then settle when that client resumes or leaves the
quorum.

This is a compact developer-tool framing for three distinct rules: add/remove
membership, first-writer ownership, and quorum-settled configuration.

### Offline field notebook: `OrMap` + `SharedText` + presence

A notebook for observers who lose connectivity during field work. Each
observation has an ID and structured metadata in an `OrMap`; a shared text log
holds narrative notes. Presence shows active observers only while they are
connected and never enters durable summaries.

The scripted scenario partitions two clients, lets each add observations and
edit notes, then reconnects both. Their structured records and text converge,
while stale presence entries expire. That puts offline recovery, mixed channel
composition, and durable-versus-ephemeral state in one small app.

Keep maps and geolocation out of the first version. A list of observations, a
text panel, and an offline toggle prove the claim without adding external APIs
or a mapping library.

**Prerequisites:** none.
**Cost:** medium.

---

## Rough ordering

Revised 2026-08-09, after FP1–FP6 and the drum machine landed. The same principle still applies: **correctness outranks demos, and demos are how the correctness bugs get found.**

1. **Pixel canvas** — genuinely zero prerequisites, best story-per-hour, hardest visual proof.
2. **Retro board** — zero prerequisites, most realistic app, two conflict scenarios worth showing.
3. **Clap counter** — nearly free, and has a home on the existing `counter-bug` page.
4. **Showcase composition** — SC1–SC8, once there are enough panels to be worth composing.
5. Everything else, as appetite allows.

Not a demo, and ahead of all of them if summaries are close: **`docs/plans/2026-08-09-summary-bootstrap-plan.md`** (SB1–SB8). It carries the goal every recent consensus fix was in service of — joining a document should cost recent history, not all of it — and it absorbs the two pieces the replay-quorum plan left open. SB1 is cheap and worth doing regardless: it either confirms or clears a suspected checkpoint-boundary bug in shipped behaviour.

**Done:** FP1–FP6 (facade parity sweep), grocery triptych GT1–GT6, drum machine DM1–DM7, work queue WQ1–WQ7, consensus replay quorum (client half), pixel canvas, retro board, clap counter.
