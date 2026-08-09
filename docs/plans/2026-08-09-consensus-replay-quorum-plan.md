# Consensus replay quorum — a settled pact is unreadable to anyone who joins later

**Date:** 2026-08-09
**Found by:** building DM6/DM7 of `docs/plans/2026-08-08-drum-machine-demo-plan.md`. The demo works with three tabs open and breaks the moment a fourth opens — or the moment any tab reloads.
**Severity:** correctness, and worse than FP1. FP1 made a quorum accept too early; this makes a document **unjoinable** once a `PactMap` key has been agreed.
**Status:** diagnosed and reproduced, not fixed. The fix is a wire/protocol decision, not a local patch.

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

Pinned as a characterization test — `known_bug_a_late_joiner_cannot_read_an_agreed_tempo_test` in `examples/drum_machine_lustre/test/quorum_test.gleam`. It asserts the *wrong* behaviour on purpose so the suite stays green; when this plan lands, the assertions flip to `Some(json.int(128))` / `should.be_false` and the `known_bug_` prefix comes off.

Three clients agree a tempo, a fourth joins:

```
A accepted?  pending=no
D pending?   yes
D waiting on [903365845]     <- D's own client id
D keys: ["bpm"]
```

Reproduced against a live floodgate server too, where it presents as the `AckMismatch` above rather than as silence. Both symptoms, one cause.

## Blast radius

`meta.quorum` has exactly three consumers, all in `src/watershed/channel.gleam`:

| Line | Kernel | Exposure |
|---|---|---|
| `:704` | `pact_map_kernel.apply_set` | confirmed broken |
| `:620` | `task_manager_kernel.apply_remote` | same shape — unverified, and the work-queue demo is its first real consumer |
| `:1002` | `task_manager_kernel.ack_local` | local ack path, likely the same |

`OrderedCollection` and `Claims` do not take a quorum and are unaffected. Every other kind is a lattice or an OT structure whose replay is roster-independent by construction.

**The `TaskManager` case should be checked before the work-queue demo is built**, not after — it is item 7 in `docs/demo-ideas.md` and would hit this on its first reload.

## Why there is no local fix

The tempting patch is to stop the joiner injecting itself: drop the `set.insert(self)` union while replaying pre-join history. It fixes the reproduction above and nothing else. Clients that left between the `Set` and the join still produce `UnexpectedAccept`; clients that joined in that window still wedge the pact pending. It converts a loud, obvious failure into a quiet, conditional one, which is the wrong direction for a consensus protocol.

The signoff list has to come from the log. Three ways to get it there, in increasing order of cost:

1. **Server stamps the roster on the sequenced `Set`.** Floodgate knows the connected set at sequencing time — that is where `initialClients` comes from. Adding the frozen list to the sequenced envelope makes replay exact, for every replica, forever. Requires a floodgate change and a wire-format addition, and it is the only option that is actually correct.
2. **Checkpoint pact state and never replay consensus ops.** `pact_map_kernel.from_summary` already exists; the gap is that the summary a joining client receives does not carry it (or is not being used). This is narrower than (1) and does not fix replay from a checkpoint that predates the `Set` — it moves the window rather than closing it.
3. **Author stamps the roster on the `Set` op.** No server change, but a client's roster is its own belief about the room, and two clients can hold different ones. It replaces a time-skew bug with a consistency bug.

**(1) is the answer, and it needs a floodgate-side decision**, which is why this is a plan rather than a patch. (2) is worth doing regardless as a performance measure and would shrink the exposure window in the meantime.

## What the drum machine does about it in the meantime

DM1–DM5 are untouched: the pattern is four `OrSet`s and replays perfectly. DM6/DM7 ship with the tempo quorum working for a live room — proposal, stall, signoff drain, leave-drain, all verified with three clients — and the README states plainly that a client joining after a tempo has been agreed cannot read it, with a pointer here.

That is an honest position for a demo whose whole argument is "show, don't claim", but it is not one to leave standing. The demo exists to force exactly this class of bug into the open, and it did.
