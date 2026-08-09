# Consensus replay quorum — a settled pact is unreadable to anyone who joins later

**Date:** 2026-08-09
**Found by:** building DM6/DM7 of `docs/plans/2026-08-08-drum-machine-demo-plan.md`. The demo works with three tabs open and breaks the moment a fourth opens — or the moment any tab reloads.
**Severity:** correctness, and worse than FP1. FP1 made a quorum accept too early; this made a document **unjoinable** once a `PactMap` key had been agreed.
**Status:** **client half fixed** (CR1–CR4 below). One server-side piece remains — the roster at a checkpoint — plus the reconnect gap that shares its missing input. See "What remains".

## The bug

`runtime_core.handle_sequenced` (`src/watershed/runtime_core.gleam:918`) stamps every sequenced op with

```gleam
quorum: quorum_of(core, message_client_id),
```

and `quorum_of` (`:311`) derives that list from `core.members` — **the roster as it stands right now**, plus self and the op's author. That is correct for an op arriving live. It is wrong for an op being *replayed*, because bootstrap replay (`:196`) runs the whole historical message list through the same function, against the joining client's present-day roster rather than the roster each op was originally sequenced against.

So a client replaying a `PactMap` `Set` recomputes its signoff list from a room that did not exist when the `Set` was sequenced. The consequences compound:

1. **The joiner writes itself into a quorum it was never part of.** `quorum_of` unions `self` in. The historical `Accept`s from the clients that really did sign off drain those entries, and the joiner is left waiting on itself for a proposal that settled before it connected. `pact_map_get` returns `None` forever.
2. **Its owed `Accept` poisons the peers.** `apply_set` returns `OweAccept` when the caller is in the signoff list, and the runtime auto-submits it. That `Accept` reaches clients who settled the pact long ago; `apply_accept` (`src/watershed/pact_map_kernel.gleam:190`) answers `UnexpectedAccept`, which `channel` turns into `CorruptRemoteOp` and `runtime_core` into `AckMismatch`. Against a live floodgate server the joining client dies with:

   ```
   bootstrap failed: AckMismatch(detail: "client was not expected to sign off")
   ```
3. **Membership churn breaks it in the other direction too.** A client that has since *left* is absent from the joiner's roster, so its historical `Accept` is unexpected on arrival. A client that joined *after* the `Set` is present in the roster but never signed off, so the pact stays pending forever.

The one-sentence version: **replaying the op log does not reproduce the state the op log produced, because consensus state depends on a roster that is not in the log.**

## Reproduction

Three clients agree a tempo, a fourth joins. Before the fix:

```
A accepted?  pending=no
D pending?   yes
D waiting on [903365845]     <- D's own client id
D keys: ["bpm"]
```

After: `D pending? no`, `D waiting on nothing`. Verified against a live floodgate server too, where the symptom was the `AckMismatch` above rather than silence — a reloaded tab now connects cleanly and reads the agreed tempo.

Regression tests:

- `a_settled_pact_replays_intact_for_a_late_joiner_test` (`test/watershed/sluice/driver_js_test.gleam`) — the library-level guard, including a signer that has since left, which a roster-only fix would still have broken.
- `a_late_joiner_reads_the_agreed_tempo_test` (`examples/drum_machine_lustre/test/quorum_test.gleam`) — the demo's own.
- `task_manager_replays_the_same_queue_for_a_late_joiner_test` — see the blast-radius note below.

## The fix that landed

**CR1 — membership is checkpoint state.** `Summary` grows a `members` field, and `bootstrap` seeds `Core.members` from it rather than from the handshake's `initialClients`. Replayed `join`/`leave` advance it, machinery that already existed and was already right — `handle_join`'s own docstring states the rule ("a join only widens the quorum for ops sequenced after it"); nothing consulted it.

**CR2 — the live-path defences are live-path only.** `quorum_of` unioned self and the op's author into every quorum to cover a join lost or reordered against the op that follows it. That is a live hazard; replay reads a complete ordered log where nothing can be missing, and "we know self is live" is exactly the false premise for an op sequenced before we joined. A new `Core.replaying` gates them.

**CR3 — `replaying` is scoped to the fold, not to the bootstrap.** It is set and cleared inside `replay` itself. The obvious alternative — set it at `bootstrap`, clear it at the hand-off — leaks: `settle_reconnect` reaches `Ready` without ever passing through `settle_bootstrap`, so a reconnect would have disarmed `quorum_of` for the rest of the session. A flag that turns off safety checks must not depend on someone remembering to turn it back on.

`settle_bootstrap` adopts the handshake roster on `Complete` — once, however many pages the history took — which bounds the damage from the still-missing checkpoint roster to the replay window.

## What remains

**The checkpoint roster — now a prerequisite for enabling summaries at all**, see CR4 below. `Summary.members` is plumbed but the summary blob does not carry it, so both runtimes pass `[]`. Replay from sequence number zero is exact (nobody had joined at zero); replay from a checkpoint under-reports the room by everyone already present, and a proposal sequenced after the checkpoint but before the joiner arrives still reconstructs against a too-small quorum. Since summaries are the intended steady state — replay from zero grows without bound — **this is the piece that matters**, and it is a floodgate + `git_storage` change: write the connected roster at the checkpoint SN alongside the per-kernel snapshots that are already there.

One thing that makes the remaining window narrow: `pact_map_kernel.summary_entries` returns the whole `Pact`, *including* `pending` with its `expected_signoffs` (`:63-65`), and `channel.gleam:461` snapshots it. A frozen signoff list already survives summarization. Only proposals sequenced after the checkpoint need the roster.

**The reconnect gap.** `adopt_reconnect` still replaces the roster immediately, so ops sequenced during a disconnect are replayed against the post-reconnect room. Same time-shift, much shorter window, and it needs the same missing input — the roster at `last_seen_sn`. Deliberately left alone rather than half-fixed.

## Blast radius

`meta.quorum` has three consumers in `src/watershed/channel.gleam`:

| Line | Kernel | Verdict |
|---|---|---|
| `:704` | `pact_map_kernel.apply_set` | was broken, fixed |
| `:620` | `task_manager_kernel.apply_remote` | **was never broken — and not by design** |
| `:1002` | `task_manager_kernel.ack_local` | same |

`TaskManager` reads membership only as a guard on the op's author (`task_manager_kernel.gleam:359`), and `quorum_of` unioned the author in unconditionally — so **the guard could never fail**. It was dead code holding a live invariant, and the defensive union that caused the `PactMap` bug is what hid it.

**CR4 makes it live everywhere.** `SequencedMeta` now carries `roster` — the room at the op's sequence point, with no defensive additions — alongside `quorum`, and `TaskManager` takes the former. The two want opposite safety directions, which is why they cannot be the same list: a signoff list that over-includes is safe (it waits for someone who is already gone, and a `leave` drains them), while a membership *test* that over-includes silently passes for a client that is not there. `a_volunteer_from_a_non_member_is_dropped_test` is the first test in the codebase that can observe this guard rejecting anything.

What it protects: `remove_client` on a sequenced `"leave"` is the only thing that frees a role whose holder walked away, so a client that reached a queue without ever being a member could hold one indefinitely.

### CR4 raises the stakes on the checkpoint roster

This is the consequence to keep in view. A live guard is only consistent if every replica agrees on the roster, and today they do — rosters are built from sequenced `join`/`leave`, which every replica processes in the same order.

**Except in the summarized-bootstrap window.** A client seeding `members` from a checkpoint that carries no roster under-reports the room, and would then *drop* replayed volunteers from clients who joined before the checkpoint — while every other replica kept them. That is queue divergence, where before CR4 the same gap only produced too-small `PactMap` quorums.

`task_manager_kernel.from_summary` means volunteers from before the checkpoint arrive as snapshot state rather than replayed ops, so the window is only volunteers sequenced *after* the checkpoint by clients who joined *before* it. Narrow, and real.

So: **the checkpoint roster is no longer optional once summaries are enabled.** It was already the right thing for `PactMap`; it is now a hard prerequisite for turning summaries on at all. Land them together.

`OrderedCollection` and `Claims` take no quorum. Every other kind is a lattice or an OT structure whose replay is roster-independent by construction.

## Options considered, and why the roster went where it did

The first sketch of this plan said the signoff list had to be stamped onto the sequenced `Set` by the server. That was overbuilt. The machinery to track membership over time already existed and was already correct — `handle_join` / `handle_leave` fold sequenced membership changes into `Core.members` during replay, and `handle_join`'s docstring states the right rule. Nothing read it, because `bootstrap` overwrote the seed with the room as it is now.

So the rule the fix settles on is the one every kernel already follows:

> **`members` is checkpoint state: seeded from the snapshot, advanced by the log. Never seeded from "now."**

Membership was the one piece of sequence-point state that had been special-cased into a live read. Three alternatives were rejected:

- **Stamp the roster on every sequenced `Set`.** Correct, and a wire-format change per op to carry state that one snapshot per checkpoint conveys just as exactly.
- **Have the author stamp its own roster on the op.** No server change, but a client's roster is its own belief about the room. Two clients can hold different ones; this trades a time-skew bug for a consistency bug.
- **Just stop the joiner injecting itself** — drop the `set.insert(self)` union and change nothing else. Fixes the headline reproduction and leaves the rest: a client that left between the `Set` and the join still produces `UnexpectedAccept`, and one that joined in that window still wedges the pact pending. It converts a loud failure into a quiet, conditional one, which is the wrong direction for a consensus protocol.

## What the drum machine does about it

Nothing special any more — DM6/DM7 work, including across reloads, and the README no longer carries a limitation section. DM1–DM5 were never affected: the pattern is four `OrSet`s and replays perfectly.

The demo exists to force exactly this class of bug into the open, and it did.
