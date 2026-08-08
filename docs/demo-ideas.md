# Demo ideas backlog

**Started:** 2026-08-08

Candidate example apps for `examples/`, kept here so they survive between sessions. Five have been promoted to full plans:

- `docs/plans/2026-08-08-pixel-canvas-demo-plan.md` — `OrMap` register mode, zero prerequisites
- `docs/plans/2026-08-08-retro-board-demo-plan.md` — `OrMap` both modes + `SharedSequence` + presence, zero prerequisites
- `docs/plans/2026-08-08-grocery-triptych-demo-plan.md` — `GSet` | `TwoPSet` | `OrSet`, one `watershed_lustre` rung first
- `docs/plans/2026-08-08-work-queue-demo-plan.md` — `OrderedCollection` + `TaskManager`, one subscribe rung first
- `docs/plans/2026-08-08-drum-machine-demo-plan.md` — `OrSet` + `PactMap`, **half of it blocked on a correctness fix**

And the gaps those plans surfaced have their own plan:

- `docs/plans/2026-08-08-facade-parity-sweep-plan.md` — FP1–FP6

## Why this list exists: kind coverage

Coverage across `examples/` and the website demos as of 2026-08-08.

| State | Kinds |
|---|---|
| Well demoed | `SharedMap`, typed maps, `SharedSequence`, `SharedText`, `SharedCounter`, presence, ripples |
| One site only | `OrSet`, `Claims` (sudoku), `SharedDirectory` + `JsonOt` (website pages only), `SharedRichText` (website only) |
| **No demo** | `OrMap`, `PnCounter`, `PactMap`, `OrderedCollection`, `RegisterCollection`, `TaskManager`, `GSet`, `TwoPSet` |

The three promoted plans take `OrMap`, `OrderedCollection`, and `TaskManager` off the bottom row.

## Two corrections worth not re-learning

Both of these were mis-assumed during the brainstorm that produced this list, and both would have produced a broken plan:

1. **`PactMap` is a quorum protocol, not a last-writer-wins map.** A set becomes *pending* with a frozen signoff list captured from the connected quorum, and only becomes accepted once that list drains via accept ops or membership leaves (`src/watershed/pact_map_kernel.gleam:1-5`). It is wrong for anything wanting fast uncoordinated writes, and right for "this setting changes only when the room agrees".
2. **`TaskManager` and `OrderedCollection` are consensus primitives, not collections you store things in.** `TaskManager` is a lock queue over named roles; `OrderedCollection` is a non-optimistic FIFO job queue with `acquire`/`complete`/`release`. Neither is a card store. See the work-queue plan for the full argument.

## Known gaps

Full detail and rungs in `docs/plans/2026-08-08-facade-parity-sweep-plan.md`. Summary, worst first:

- **`PactMap` quorum is a placeholder** (FP1) — a **correctness** bug, not an ergonomics one. `runtime_core.gleam:815–818` fabricates the signoff list as `[self, author]`; there is no membership roster, and the handshake's `initial_clients` (`wire/socket.gleam:238`) is decoded and never read anywhere. With three clients, the third is never asked to sign off, so `PactMap` behaves as an ack-delayed LWW map. Kernel is correct; wiring is stubbed.
- **`SharedRichText` is absent from `watershed_js.gleam`** (FP2) — zero occurrences, while `watershed.gleam` has the full set and `runtime_js.gleam` has the runtime functions ready. The proof it hurts: `website/src/scripts/rich-text-demo.ts:34–39` imports `runtime_js.mjs`, `channel.mjs`, and `handle.mjs` directly, because the public API cannot express the demo.
- **No `subscribe_pn_counter` / `subscribe_pact_map` / `subscribe_ordered_collection`** (FP3) on either facade or in `watershed_lustre`, though all three kinds' events already reach the runtime. Those kinds are write-and-poll only.
- **`PactMap` pending details unreachable** (FP4) — no way to read `Pending.expected_signoffs`, so no UI can say what a pending value is waiting for.
- **`watershed_lustre` holes** (FP5) — missing `ensure_*` / `subscribe_*` for `directory`, `g_set`, `two_p_set`, `json_ot`. Apps using those kinds must hand-roll the microtask deferral the package exists to own.

**Correction:** an earlier version of this section claimed the `OrderedCollection` op surface and `complete_task` were missing from the facades. They are present on both. That came from grepping by prefix guess (`ordered_collection_*`, `task_*`), which misses `ordered_*` and `complete_task`. Audit by full `pub fn` inventory diff — the command is at the end of the parity plan.

The "full typed-layer parity across 14 kinds" milestone covered channel *lifecycle* and is genuinely complete. Operations, subscriptions, and **runtime semantics** are three further axes nobody swept.

---

## Ideas

### ✅ Promoted — Grocery list triptych — `GSet` | `TwoPSet` | `OrSet`

→ `docs/plans/2026-08-08-grocery-triptych-demo-plan.md`

Three panels, identical UI, same interactions, wired to three different set kinds, diverging live. Remove "milk", then re-add it: the `TwoPSet` panel refuses (tombstone), the `OrSet` panel accepts, the `GSet` panel never removed it in the first place.

**Prerequisite corrected:** this was listed as zero-prerequisite. It is not — `watershed_lustre` lacks `ensure_g_set` / `subscribe_g_set` / `ensure_two_p_set` / `subscribe_two_p_set` (FP5). They exist on `watershed_js`, so it is one thin rung, carried as GT1.

### ✅ Promoted — Drum machine / step sequencer — `OrSet` + `PactMap`

→ `docs/plans/2026-08-08-drum-machine-demo-plan.md`

A 16×4 step grid, each track an `OrSet` of active step indices; everyone jams on the same loop. Convergence becomes *audible*.

**Two corrections from scoping it:**

- **The quorum half is blocked on FP1.** `PactMap` does not currently implement room-wide quorum (see the gaps above), so a "the room must agree" demo would show the audience something that is not happening. The plan splits at DM5: steps and audio ship first, the quorum tempo waits for the fix.
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

### Clap counter — `PnCounter`

Medium-style claps. Trivially small, and the most direct possible stress test of a single counter under high concurrency: hold the button down in four tabs and watch the number stay correct.

The right vehicle for closing the `subscribe_pn_counter` gap, since it needs nothing else. Would pair well as an inline widget on the website's `counter-bug` page — the broken version and the correct version side by side on the page that already makes the argument in prose.

**Prerequisites:** `subscribe_pn_counter`.
**Cost:** very low.

### Tournament bracket — `RegisterCollection`

Each match result is a register owned by one referee; refs report their own results with no coordination. `RegisterCollection` is "a collection of registers, each written by one owner", and a bracket is the one application where that is the obvious model rather than a contrivance.

Retires the last no-demo kind that none of the other ideas here reach.

**Prerequisites:** none — `subscribe_register_collection` exists on both facades and in `watershed_lustre`.
**Cost:** low-medium. Bracket layout is fiddly CSS with no collaborative content.

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

---

## Rough ordering

Revised after the parity audit. **FP1 and FP2 arguably outrank every demo here** — one is a correctness bug in a shipped kind, the other is why the flagship website demo imports private modules. Demos are how they were found; they should not be how they get postponed.

1. **FP2 — rich text on the JS facade.** Self-contained, and its acceptance test (rewriting the website demo against the public API) removes an embarrassment from the public site.
2. **Pixel canvas** — genuinely zero prerequisites, best story-per-hour, hardest visual proof. Ship something while the fixes land.
3. **FP1 — the quorum roster.** Correctness. Investigate floodgate's join-message surface first; if joins are not emitted this becomes a server plan, and knowing that early matters for the drum machine.
4. **Grocery triptych** — one thin `watershed_lustre` rung, three kinds cleared, best teaching artifact.
5. **FP3 + FP5** — the missing subscribes and the Lustre fill-in. Unblocks the work queue, the clap counter, and half the backlog.
6. **Retro board** — zero prerequisites, most realistic app, two conflict scenarios worth showing.
7. **Work queue** — after FP3. Retires the two largest untouched kernels; the only demo about failure recovery.
8. **Clap counter** — after FP3, nearly free, and has a home on the existing `counter-bug` page.
9. **Drum machine** — DM1–DM5 any time after FP5; DM6–DM7 only after FP1 and FP4.
10. Everything else, as appetite allows.
