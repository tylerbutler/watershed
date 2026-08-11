# Retro board demo plan — add-wins notes and conflict-free tallies

**Date:** 2026-08-08
**Builds on:** `2026-07-03-or-map-kernel-plan.md` (shipped), `2026-07-06-lustre-integration-plan.md` (LU1–LU3), `2026-07-06-typed-presence-plan.md`, `examples/playlist_lustre` (the `SharedSequence` reorder patterns transfer directly).
**Benchmark:** Miro / EasyRetro / Metro Retro. A sticky-note wall is the canonical "many people editing the same board at once" app, and every one of them has a concurrent-add bug story.

**Prerequisite work: none.** Justification for that claim is in decision 2 below — it is the reason this plan does not use `PnCounter`.

## Decisions already made (flagged — confirm before RB1)

1. **Two `OrMap` channels, one per mode.** `notes` in `RegisterMode` (note id → encoded note JSON) and `votes` in `TallyMode` (note id → signed tally). `or_map_kernel` fixes the mode per channel (`OrMapState.mode`, set at `ensure_or_map` time), so the split is forced — and it is a happy accident, because the demo ends up showing both of the kernel's value modes side by side in one app.
2. **Votes use `OrMap` tally mode, not `PnCounter`.** A design choice, not a workaround: one `PnCounter` channel per note means a channel create on every sticky note and N subscriptions to manage, while `TallyMode` gives per-key PN-counter leaves in a single channel with a single subscription — which is what the mode is for. It also shows both OR-map value modes side by side in one app. *(This decision was originally also justified by `subscribe_pn_counter` being missing from the facades; that gap has since been closed — commit `5cea5d6` added it to `watershed.gleam`, `watershed_js.gleam`, and `watershed_lustre` — so the design argument now stands alone. Confirmed at implementation time, 2026-08-10.)*
3. **Column membership lives on the note, ordering lives in a `SharedSequence` per column.** The note record carries its column id; each column has a sequence of note ids giving display order. A move is a delete from one sequence plus an insert into another plus a register update on the note. This is *not* atomic, and the plan does not pretend otherwise — see "The move is not atomic" below.
4. **Notes are never hard-deleted by default; `or_map_remove` is the explicit "delete" action.** This keeps the observed-remove path exercised (the pixel canvas deliberately avoids it) and sets up the demo's second teaching moment: concurrent edit-vs-delete.
5. **Presence is in scope, not optional.** A retro board without "who else is here" reads as a single-player app, and `presence.color_for` / `short_name` already exist to make it cheap.

## Why this demo

Three of watershed's kinds have properties that only become legible under *simultaneous* action, and a retro board is an app where simultaneous action is the normal case rather than a contrived stress test — everyone types their cards during the same 90 seconds, then everyone votes during the same 30.

The two moments worth building the demo around:

**Concurrent add.** Two people add a card in the same instant. Under a naive last-writer-wins map keyed by index or count, one card disappears. Under an add-wins OR-map, both survive. This is a bug the reader has personally hit in some other tool.

**Concurrent vote.** Two people upvote the same card while a third downvotes it. Under `get` → `+1` → `set`, votes are silently lost — which is exactly the `counter-bug` page the website already argues in prose (`website/src/pages/counter-bug.astro`). Tally mode makes the correct version demonstrable rather than asserted. Consider linking the two directly.

## Data model

```gleam
pub type Board

pub const notes: ChannelField(Board, schema.OrMapChannel) = ...   // RegisterMode
pub const votes: ChannelField(Board, schema.OrMapChannel) = ...   // TallyMode
pub const went_well: ChannelField(Board, schema.SequenceChannel) = ...
pub const to_improve: ChannelField(Board, schema.SequenceChannel) = ...
pub const action_items: ChannelField(Board, schema.SequenceChannel) = ...
```

Three fixed columns, declared statically. Dynamic columns would mean a `SharedDirectory` of sequences — a defensible v2, but it buys no new collaborative behaviour and costs a whole channel-lifecycle story.

**Note encoding** (`Register` leaves hold `String`, so this is JSON-encoded on the way in and decoded on the way out):

```json
{ "text": "deploys are still scary", "column": "to_improve", "author": "tyler", "created": 1754... }
```

`created` is a client clock and is used **only** as a tiebreaker for rendering notes that are not yet in a column sequence. It is not trusted for ordering across clients; the sequence is the ordering authority.

**Vote encoding:** `or_map_increment(votes, note_id, 1)` / `(votes, note_id, -1)`. Reads come back as `Tally(Int)`.

**Per-user vote budget** — a real retro gives everyone N votes. Track spent votes in **local state only**, not in the document. A shared budget is a coordination problem (two clients concurrently spending the last vote both succeed) and solving it properly means `Claims` or `PactMap`, which is a different demo. The README should say this out loud: the budget is advisory UI, and the tally is the only thing that converges.

## The move is not atomic

Dragging a note between columns is three ops across two channel kinds. There is no transaction spanning them. Under concurrent moves of the same note by two clients, the reachable end states include the note's `column` field disagreeing with which sequence contains its id — including the note appearing in two column sequences at once.

**Resolution rule, applied at render time:** the note's `column` register is authoritative; a note id appearing in a sequence whose name does not match the note's `column` field is skipped when rendering that column. A note whose `column` names a sequence that does not contain its id renders at the end of that column, ordered by `created`. This makes every reachable state render sensibly without inventing a transaction.

The garbage entries are left in the sequences rather than repaired, because repair-on-render means every client issuing corrective ops on every render and those clients fighting each other. Say this in the README. It is a genuinely interesting limitation and hiding it would be worse than the limitation.

## Rungs

- **RB1 — scaffold + connect.** New `examples/retro_board_lustre/` on the `playlist_lustre` template; `justfile` install/build stanzas. `connect_dev`, both `ensure_or_map` calls with their respective modes, three `ensure_sequence` calls. Gate: two tabs connect and log a ready board.
- **RB2 — notes, add-wins.** Add a note, render three columns, `subscribe_or_map` on `notes`. No ordering yet — render by `created` within column. Gate: two tabs add a note within the same tick; **both** notes survive on both tabs. This is the headline assertion; make it a convergence test, not just a manual check.
- **RB3 — votes, tally mode.** Vote buttons, `or_map_increment`, tally rendering, local budget UI. Gate: two tabs upvote the same note concurrently and land on +2; a concurrent up and down land on 0.
- **RB4 — ordering.** Wire the three `SharedSequence` channels, drag-to-reorder within a column, `sequence_move`. Gate: reorder in one tab, other tab follows.
- **RB5 — cross-column move + the render rule.** Drag between columns; implement the authoritative-register render rule above. Gate: concurrent cross-column moves of the same note from two tabs leave both tabs rendering the note exactly once, in the same column.
- **RB6 — delete, and edit-vs-delete.** `or_map_remove`; a note deleted while a peer is editing it. Gate: document the observed behaviour (which the OR-map's add-wins bias determines) in the README — do not assert a behaviour before observing it.
- **RB7 — presence.** Roster of participants via `presence_js` + `presence.color_for` / `short_name`.
- **RB8 — README + smoke test.** Include the non-atomic-move discussion and the advisory-budget caveat.
- **RB9 — drag-and-drop via the `dnd` hex package.** *(Added at implementation time, 2026-08-10.)* RB4/RB5 shipped with ↑/↓ buttons and a per-card "→ column" control — the proven `playlist_lustre` pattern — so every gate stays testable without drag. This rung layers the [`dnd` package](https://hex.pm/packages/dnd) (v2.1.3, `dnd/groups`, a Lustre port of Elm's `dnd-list`) on top rather than hand-rolling HTML5 DnD: the library runs the gesture and the ghost, but both operations are configured `Unaltered` so it never reorders anything — on `DragEnd` the app reads the drag `info`, resolves endpoints by element id, and reuses the exact button-move channel ops (register rewritten only on an actual column change, since the note record is whole-record LWW). Mouse-only; buttons remain the touch path; the package's two-tap touch mode is a possible follow-up. Gate: a drag between columns in one tab follows in the other; the concurrent-move gate is RB5's, unchanged.

## Testing strategy

- **Convergence tests** (`test/convergence_test.gleam`, two in-process clients over `sluice`) for each of the four conflict scenarios that the rungs gate on: concurrent add, concurrent vote, concurrent cross-column move, edit-vs-delete. These are the demo's actual claims and they should be executable.
- **Note codec property test:** round-trip encode/decode, including text with quotes, newlines, and emoji.
- **Render-rule unit test:** feed the resolution rule the pathological states enumerated above (note in two sequences; note in none; column field disagreeing with sequence membership) and assert each renders exactly once.
- **Smoke test** on the `sudoku_lustre` pattern.
