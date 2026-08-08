# Work queue demo plan — consensus dispatch, and what happens when a worker dies

**Date:** 2026-08-08
**Builds on:** `2026-07-06-wire-ordered-collection-into-runtime-plan.md` (✅ complete, commit `f874be5` — runtime ops and the client-leave path), `2026-07-04-task-manager-kernel-plan.md`, `2026-07-06-lustre-integration-plan.md`, `docs/plans/2026-08-08-facade-parity-sweep-plan.md` (FP3 — the one real prerequisite).
**Benchmark:** Sidekiq / Oban dashboards, and Fluid's own `ConsensusOrderedCollection` sample. The UI reads as a kanban board; the semantics are a distributed job queue, and that coincidence is what makes the demo work.

## Correction to the framing this came from

This was originally sketched as "a kanban board on `TaskManager`". That was wrong about both kernels, and the plan is shaped by the correction:

- **`TaskManager` is not a to-do store.** It is a consensus lock queue — "a pure consensus queue kernel for Fluid TaskManager semantics" with per-task FIFO queues of *clients volunteering* (`src/watershed/task_manager_kernel.gleam:1-6`). A "task" is a job that exactly one client may hold at a time. There is nowhere to put a card's text.
- **`OrderedCollection` is not a z-order or a card list.** It is a consensus FIFO work queue with `add` / `acquire` / `complete` / `release`, and it is explicitly **non-optimistic**: "attached adds/acquires/completes/releases only change committed state when their ops sequence" (`src/watershed/ordered_collection_kernel.gleam:1-6`).

A card store built on these would be fighting both kernels. But a **job dispatch board** is exactly what they model — and it renders naturally as three columns (Queued → In progress → Done), so the demo still looks like the kanban board that was originally wanted, while the columns are literally the kernel's states rather than a convention layered on top.

**This is also the only demo on the roadmap where the interesting event is a client *dying*.** Nothing else in `examples/` exercises `on_disconnect_notify` / `remove_client`. Closing a tab mid-job and watching the job return to the queue on its own is a claim no other watershed example makes.

## Prerequisite work — one rung, not four

**Corrected 2026-08-08.** An earlier draft of this plan claimed the ordered-collection op surface and `complete_task` were missing from the facades and budgeted three rungs to add them. That was wrong — the result of grepping by prefix guess (`ordered_collection_*`, `task_*`), which misses `ordered_*` and `complete_task`. A full `pub fn` inventory diff shows:

- `ordered_add` / `ordered_acquire` / `ordered_complete` / `ordered_release` / `ordered_size` — **present on both facades.**
- `complete_task` / `abandon_task` / `volunteer_for_task` / `task_assigned` / `task_queued` / `task_queues` — **present on both facades.**

The only genuine gap is:

| Gap | Present at | Missing from |
|---|---|---|
| `subscribe_ordered_collection` | events reach `runtime_core.gleam:3224` | both facades **and** `watershed_lustre` |

That is FP3 in `docs/plans/2026-08-08-facade-parity-sweep-plan.md`, carried here as WQ1. Without it the queue is write-and-poll only — an app can add and acquire but cannot learn that a peer acquired something, which for a dispatch board is fatal. `subscribe_task_manager` already exists on both facades and in `watershed_lustre`, so the role half needs nothing.

The audit command that produces this reliably is at the end of the parity plan. Use it rather than prefix greps.

## Decisions already made (flagged — confirm before WQ1)

1. **`OrderedCollection` is the job queue; `TaskManager` is the long-running-lane lock.** They are not redundant. The queue hands out discrete units of work FIFO, one acquirer each. `TaskManager` answers a different question — "which single client currently owns *this named ongoing role*" — and the demo models exactly one such role: **the dispatcher**, the client that generates new jobs. Exactly one tab generates work; close it and another tab takes the role over. Two kernels, two genuinely different jobs, one screen.
2. **Non-optimistic UI is honest UI.** Because acquires only commit on sequencing, a clicked "Claim" button must render as *pending* until the op sequences and may then resolve to "someone else got it". Do not fake an optimistic transition and roll it back — the losing-acquire path is one of the most interesting things this demo shows, and disguising it would waste it.
3. **Jobs are self-contained payloads in the queue, not references into a map.** `ordered_add` takes a `Json` value; put the whole job in it (`{id, label, created}`). A side map of job metadata would add a second channel with no new semantics and reintroduce the atomicity problem the retro board already documents.
4. **Simulated work, with a visible duration.** An acquired job holds for a few seconds (a timer) before `ordered_complete`. Without a dwell time there is no window in which to kill a worker, and the kill is the payload of the demo.
5. **No presence.** The roster here is the set of clients holding jobs, which the queue state already tells you. A second, softer notion of "who's here" would muddy it.

## Data model

```gleam
pub type Dispatch

pub const queue: ChannelField(Dispatch, schema.OrderedCollectionChannel) = ...
pub const roles: ChannelField(Dispatch, schema.TaskManagerChannel) = ...
pub const completed: ChannelField(Dispatch, schema.SequenceChannel) = ...
```

`completed` is an ordinary `SharedSequence` append log — the Done column. The consensus kernels deliberately do not retain completed jobs (`apply_complete` drops the job entry), so the demo needs somewhere to put history, and an append-only sequence is the least interesting possible choice, which is correct here.

**Job payload:** `{"id": "j-...", "label": "resize image 41", "created": 1754...}`.
**Role id:** the single constant `"dispatcher"`.

## Screen

Three columns plus a status strip.

- **Queued** — `ordered_size` and the pending queue, newest at the bottom. Fed by whichever client holds the dispatcher role.
- **In progress** — jobs currently acquired, labelled with the acquiring client (short id, coloured by `presence.color_for` for consistency with the other examples). The local client's own job has a **Complete** button and a **Release** button.
- **Done** — the `completed` sequence.

Status strip: connection state, this tab's client id, whether this tab holds the dispatcher role, and a **Become dispatcher** button (`volunteer_for_task`) that is disabled while `task_assigned` is true for another client.

The demo instruction, printed on the page: *open three tabs, then close the one marked "dispatcher"*.

## Rungs

**WQ1 is independently useful and should land even if the example slips.**

- **WQ1 — `subscribe_ordered_collection`** (FP3 slice). Both facades plus `watershed_lustre`, on the `subscribe_or_map` template (unconditional microtask deferral, caller-supplied `to_msg`). Gate: a test observes `OrderedEvent`s for add / acquire / complete / release.
- **WQ2 — scaffold + connect.** `examples/work_queue_lustre/` on the `playlist_lustre` template; `justfile` stanzas; all three channels ensured. Gate: two tabs connect and render three empty columns.
- **WQ3 — dispatcher role.** `volunteer_for_task` / `abandon_task` / `task_assigned`, the status strip, and job generation on a timer while the role is held. Gate: three tabs, exactly one is dispatcher; abandon it and another tab picks it up.
- **WQ4 — claim, work, complete.** `ordered_acquire` with the **pending** UI state from decision 2, the simulated dwell timer, `ordered_complete`, and an append to `completed`. Gate: two tabs racing to claim the same job — exactly one wins, the loser's button resolves to a visible "taken" state.
- **WQ5 — the kill.** Close a tab holding a job; assert the job returns to Queued in the surviving tabs without anyone doing anything. Also cover the dispatcher-tab kill from WQ3. Gate: both recoveries observed with no manual intervention.
- **WQ6 — release.** Voluntary `ordered_release` as the graceful counterpart to WQ5.
- **WQ7 — README + smoke test.** Lead with the corrected mental model — that these two kernels are consensus primitives, not card stores — because a reader arriving at a three-column board will assume otherwise.

## Testing strategy

- **Facade test (WQ1)** lives with the existing per-kind facade tests, both targets, and gates landing the subscribe independently of the example.
- **Race test:** two in-process `sluice` clients issue `ordered_acquire` for the same job in the same tick; assert exactly one `AcquireOutcome` succeeds and the other observes the job as taken.
- **Disconnect test:** client A acquires, client A is removed (`remove_client` / the runtime's leave path), assert client B observes the job back in the queue. This is the assertion WQ5 demonstrates visually and it should exist as a test — it is the one behaviour here that a reader is least likely to believe without proof.
- **Role handoff test:** A volunteers, A leaves, B's queued volunteer is promoted.
- **Smoke test** on the `sudoku_lustre` pattern.

## Risk

WQ5 depends on the client-leave path (`on_disconnect_notify` / `remove_client`) behaving end-to-end through **floodgate**, not just in-process through `sluice`. The client side is in good shape: `runtime_core.handle_leave` (`:606–635`) fans a sequenced `"leave"` out over every attached channel at a deterministic `leave_seq`, which is exactly what re-releasing an acquired job requires. The untested link is whether floodgate actually emits those leave messages, and on what timeout after an ungraceful socket close.

Validate during WQ2 — a throwaway two-client script that acquires and then hard-closes one socket — **before** building WQ3 and WQ4 on the assumption that it works. If it does not, that becomes its own plan (and note it would also block FP1 in the parity sweep, which needs the same server-side membership signalling) and the demo stops at WQ6 with the kill deferred.

Related: `runtime_core` handles only `"op"` and `"leave"` system messages — there is no join handling and no membership roster. The leave path this demo depends on works without one, but see FP1 in the parity plan for what the missing roster breaks elsewhere.
