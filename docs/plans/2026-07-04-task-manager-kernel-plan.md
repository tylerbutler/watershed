# TaskManager kernel port plan

**Date:** 2026-07-04
**Builds on:** `2026-07-03-dds-porting-complexity.md` (rated task-manager
5/10), `2026-07-03-ordered-collection-kernel-plan.md` (queue lifecycle and
membership-leave precedent), and
`2026-07-03-kernel-fuzz-harness-plan.md`.
**Reference source:** `../FluidFramework/packages/dds/task-manager/src/`
(`taskManager.ts` 922 LOC, `interfaces.ts` 191 LOC, plus `taskManager.spec.ts`,
`taskManager.rollback.spec.ts`, and `taskManager.fuzz.spec.ts` as behavioral
oracles).

## Why task-manager is this rung

TaskManager is a consensus FIFO **per task id**: clients volunteer for a task,
the first queued client owns it, abandon moves ownership to the next queued
client, and complete deletes the whole task queue. The wire format is tiny, but
the DDS is harder than ordered-collection because the public API has two
local-intent modes:

1. **One-shot volunteer** — resolve `true` once this client becomes assigned,
   resolve `false` if the task completes before assignment, reject if the client
   abandons or disconnects before assignment.
2. **Subscription** — keep volunteering across disconnect/reconnect until an
   explicit abandon or completion ends the subscription.

For the watershed kernel, keep these separate. The pure kernel owns only the
consensus queues and deterministic membership effects. Promise resolution,
read-only checks, reconnect policy, subscription bookkeeping, and event
listeners remain runtime/client-layer concerns built around the kernel events.

## Semantics inventory (from `taskManager.ts`)

| # | Behavior | Source |
|---|---|---|
| T1 | Three ops: `volunteer{taskId}`, `abandon{taskId}`, `complete{taskId}`. | taskManager.ts:36–54 |
| T2 | Consensus state is `taskQueues: Map<taskId, clientId[]>`; queue head is the assignee. | taskManager.ts:90–94 |
| T3 | Local pending ops are tracked per task as FIFO `latestPendingOps`; a local ack must match type and message id. | taskManager.ts:111–115,150–207 |
| T4 | `volunteerForTask`: if already optimistically queued and assigned, resolves `true` immediately. Detached auto-adds the placeholder/current client and resolves `true`. Connected attached path sends `volunteer` only if not `queuedOptimistically`. | taskManager.ts:309–416 |
| T5 | `subscribeToTask`: idempotent per task; sends a `volunteer` unless already optimistically queued. Detached subscribe adds placeholder, then on attach replaces/removes placeholder and re-volunteers if still subscribed. | taskManager.ts:422–530 |
| T6 | `abandon`: no-op unless optimistically queued or subscribed. Detached removes immediately. Attached submits `abandon` and emits the local abandon notification immediately. | taskManager.ts:536–552 |
| T7 | `complete`: only legal if `assigned(taskId)`; detached deletes immediately; attached+disconnected throws; attached+connected submits `complete`. | taskManager.ts:588–605 |
| T8 | `assigned` / `queued` are consensus reads for the local client, but return false while attached and disconnected. | taskManager.ts:558–575 |
| T9 | Applying `volunteer`: remove matching pending op if local, then append client to the task queue iff client is in quorum (or placeholder-detached path) and not already queued. Emit queue-change only if head changed. | taskManager.ts:150–168,758–785 |
| T10 | Applying `abandon`: remove matching pending op if local, emit local abandon-on-ack, remove that client from the task queue, delete empty queues, and emit queue-change if head changed. | taskManager.ts:171–190,787–807 |
| T11 | Applying `complete`: remove matching pending op if local, delete the whole task queue, emit completed. | taskManager.ts:193–213 |
| T12 | Quorum removeMember removes that client from every task queue. Disconnect emits `lost` for any locally-assigned task, then removes this client from all local queues immediately. | taskManager.ts:216–218,237–248,809–812 |
| T13 | Summary filters empty queues. If still placeholder-detached, remove placeholder from all queues before summarizing; otherwise replace placeholder with real client id. Load restores queues then scrubs clients not in quorum. | taskManager.ts:620–655,819–854 |
| T14 | Resubmit does not blindly resubmit. It removes the original pending op; if it was a `volunteer` and the latest remaining pending op for that task is not `abandon`, it submits a fresh `volunteer`. `abandon` and `complete` are not resubmitted. | taskManager.ts:675–698 |
| T15 | Stashed ops are ignored. Rollback pops the latest pending op for the task, requires message-id match, and emits rollback for that task. | taskManager.ts:886–914 |

## Kernel design

New module `src/watershed/task_manager_kernel.gleam`. It is pure and
non-optimistic for committed queues, but it also carries minimal local pending
metadata so `queued_optimistically`, strict local acks, rollback, and resubmit
can match the TS behavior.

### Types

```gleam
pub type TaskManagerState {
  TaskManagerState(
    /// task id -> FIFO client queue; head owns the task.
    queues: Dict(String, List(Int)),
    /// task id -> FIFO local pending ops for this client.
    pending: Dict(String, List(PendingOp)),
  )
}

pub type TaskManagerOp {
  Volunteer(task_id: String)
  Abandon(task_id: String)
  Complete(task_id: String)
}

pub type PendingOp {
  PendingOp(kind: PendingKind, message_id: Int)
}

pub type PendingKind {
  PendingVolunteer
  PendingAbandon
  PendingComplete
}

pub type TaskManagerEvent {
  QueueChanged(task_id: String, old_assignee: Option(Int), new_assignee: Option(Int))
  Assigned(task_id: String)
  Lost(task_id: String)
  Completed(task_id: String)
  Abandoned(task_id: String)
  RolledBack(task_id: String)
}

pub type VolunteerOutcome {
  AssignedNow
  Waiting
  CompletedBeforeAssignment
  AbandonedBeforeAssignment
  DisconnectedBeforeAssignment
  RolledBackBeforeAssignment
}
```

Use `Int` client ids to match the existing watershed fuzz harness and consensus
kernels. Runtime integration can map Fluid client ids to stable ints at the same
boundary that already supplies sequencing metadata.

### API surface

| Function | Signature (abbrev.) | Notes |
|---|---|---|
| `new` | `fn() -> TaskManagerState` | Empty queues and pending. |
| `from_summary` / `summary_queues` | queue round-trip | Sort by task id; omit empty queues. Pending is never summarized. |
| `assigned` / `queued` | `fn(state, task_id, self_id, connected) -> Bool` | Return false when attached+disconnected by passing `connected = False`; detached callers use the detached helpers instead. |
| `queued_optimistically` | `fn(state, task_id, self_id) -> Bool` | T4/T6: queue membership adjusted by latest pending op. |
| `volunteer` | `fn(state, task_id, self_id, message_id) -> #(TaskManagerState, Option(TaskManagerOp), VolunteerOutcome)` | If already queued optimistically and assigned, no op + `AssignedNow`; if already queued optimistically but not assigned, no op + `Waiting`; otherwise record pending volunteer and return op. |
| `volunteer_detached` | `fn(state, task_id, self_id) -> #(TaskManagerState, List(TaskManagerEvent), VolunteerOutcome)` | Auto-apply volunteer with no pending. |
| `abandon` | `fn(state, task_id, self_id, message_id) -> #(TaskManagerState, Option(TaskManagerOp), List(TaskManagerEvent))` | No-op unless queued optimistically; otherwise record pending abandon and return op. Runtime emits/rejects the one-shot promise immediately from the returned event/outcome. |
| `abandon_detached` | immediate remove | T6 detached path. |
| `complete` | `fn(state, task_id, self_id, message_id) -> Result(#(TaskManagerState, TaskManagerOp), TaskManagerError)` | Error if not assigned; otherwise record pending complete and return op. |
| `complete_detached` | immediate delete | T7 detached path. |
| `apply_remote` | `fn(state, op, author, quorum) -> #(TaskManagerState, List(TaskManagerEvent))` | Applies T9–T11 with `local = False`. |
| `ack_local` | `fn(state, op, author, message_id, quorum) -> Result(#(TaskManagerState, List(TaskManagerEvent)), TaskManagerError)` | Strictly matches and removes the oldest pending op for that task before applying T9–T11. |
| `remove_client` | `fn(state, client_id) -> #(TaskManagerState, List(TaskManagerEvent))` | T12 quorum-leave effect over all queues, deterministic task-id order. |
| `on_disconnect` | `fn(state, self_id) -> #(TaskManagerState, List(TaskManagerEvent))` | Emit `Lost` for locally-assigned tasks, then remove self from all queues immediately. |
| `replace_placeholder` | `fn(state, placeholder, real_id) -> TaskManagerState` | Attach summary/path helper; if `real_id` already present, drop placeholder instead of duplicating. |
| `scrub_not_in_quorum` | `fn(state, quorum) -> #(TaskManagerState, List(TaskManagerEvent))` | Load/attach helper; removes queued clients absent from quorum. |
| `resubmit` | `fn(state, op, message_id, next_message_id) -> Result(#(TaskManagerState, Option(TaskManagerOp), Option(PendingOp)), TaskManagerError)` | T14: remove original pending; only a volunteer may create a fresh volunteer pending op. |
| `rollback` | `fn(state, op, message_id) -> Result(#(TaskManagerState, List(TaskManagerEvent)), TaskManagerError)` | T15: pop latest pending op, require id match. |
| `apply_stashed_op` | `fn(state, op) -> #(TaskManagerState, Option(TaskManagerOp))` | Always `None`; stashed ops are ignored. |

### Design decisions

1. **Kernel includes pending-op metadata, but not promises/subscriptions.**
   `latestPendingOps` affects whether a volunteer/abandon op should be sent,
   whether a local ack is valid, rollback, and resubmit. That is kernel state.
   Promise listeners and `subscribedTasks` are control-plane state; keep them in
   the runtime wrapper as reactions to `Assigned`, `Lost`, `Completed`,
   `Abandoned`, and `RolledBack`.
2. **`subscribeToTask` is a wrapper policy over `volunteer` + reconnect.** The
   pure queue kernel should not know "subscribed"; it exposes enough events and
   `queued_optimistically` for a wrapper to decide whether to call `volunteer`
   after reconnect/attach.
3. **Membership is explicit input.** `apply_volunteer` only appends an author if
   that author is in the supplied quorum. This preserves TS behavior without a
   runtime handle inside the kernel.
4. **Local disconnect is a state transition, quorum leave is a sequenced/shared
   transition.** `on_disconnect(self)` models the local immediate removal and
   `Lost` notifications. `remove_client(leaver)` models the deterministic
   quorum event every client processes. Tests must cover both paths because they
   intentionally happen at different times upstream.
5. **Summary never contains pending.** Pending ops are local delivery metadata;
   only consensus queues survive summaries. Placeholder replacement/removal is
   modeled as explicit helper functions so attach behavior can be unit-tested
   without dragging in runtime state.
6. **Strict ack/rollback errors.** A local ack or rollback for a missing/mismatched
   pending op is a routing bug and returns `TaskManagerError`, matching TS
   asserts. Remote no-ops are tolerant where the DDS is tolerant: duplicate
   volunteers do not duplicate queue entries, missing abandons do nothing.

## Test plan (TDD — tests first)

### 1. `test/watershed/task_manager_kernel_test.gleam`

Port the upstream unit suite into pure state transitions:

- **Volunteer / wait / abandon:** single-client volunteer is non-visible until
  ack; two clients queue FIFO; first abandon promotes the second; duplicate
  volunteer does not duplicate the client.
- **Optimistic guards:** immediate second `volunteer` while pending sends no
  second op; `abandon` while a volunteer is pending records an abandon and
  `queued_optimistically` becomes false; abandon + immediate reacquire follows
  pending-op ordering.
- **Complete:** only assigned clients can create `complete`; applying complete
  deletes the whole task queue; waiting one-shot volunteers observe
  `CompletedBeforeAssignment`; subscribed clients are removed from the queue.
- **Disconnected / read-only boundary:** kernel tests cover `assigned`/`queued`
  returning false when `connected = False`; runtime-only read-only permission
  errors are documented as out of scope.
- **Membership removal:** `remove_client` removes a leaver from every task and
  emits queue changes/promotions in stable task-id order.
- **Local disconnect:** `on_disconnect` emits `Lost` for every locally assigned
  task and removes the local client from all queues immediately.
- **Detached / attach:** detached volunteer/abandon/complete apply immediately;
  placeholder replacement preserves assignment when a real id exists; missing
  real id removes placeholder and emits lost via queue change; subscribed
  wrapper can re-volunteer after attach.
- **Summary:** round-trip keeps non-empty queues in order, omits empty queues,
  scrubs clients not in quorum on load, and carries no pending ops.
- **Rollback / resubmit / stash:** rollback removes the latest pending op and
  emits `RolledBack`; rollback of volunteer/subscribe resolves false at wrapper
  level; resubmit only reissues volunteers when not superseded by a pending
  abandon; stashed ops are ignored.

### 2. Fuzz/property coverage

Ship `test/watershed/fuzz/task_manager_model.gleam` and
`test/watershed/task_manager_fuzz_test.gleam`.

Model shape:

- `op` = `Volunteer(task) | Abandon(task) | Complete(task)`.
- Commands may also include `Disconnect(client)` / `Reconnect(client)` if the
  current harness can model membership; otherwise start with connected-only
  convergence and add membership once the CO0 leave-event path is available.
- `observe` = sorted `summary_queues(state)`.
- `oracle` = independent per-task FIFO fold over the sequenced log, including
  `remove_client` events, not delegated to the kernel.
- Capabilities: summary round-trip, rollback, resubmit, ignored stashed ops.

Properties:

- **Convergence:** after full sync, every client's sorted queue summary matches.
- **FIFO assignment:** for each task, the assignee is the earliest queued client
  not removed by abandon/complete/disconnect.
- **No duplicates:** a client appears at most once in a given task queue.
- **Completion clears waiters:** after a complete, no pre-complete queued client
  remains unless it volunteered again after the complete.
- **Pending transparency:** local pending volunteer/abandon/complete changes
  `queued_optimistically` but not `summary_queues` until ack.

Mutation checks:

- Plant "allow duplicate volunteer entries" — no-duplicates property fails.
- Plant "abandon only removes queue head" — FIFO/oracle diverges when a waiting
  client abandons.
- Plant "complete removes only the assignee" — completion-clears-waiters fails.

## Out of scope

- Runtime wrapper for promises, subscriptions, read-only checks, reconnect
  policy, Fluid client-id mapping, event emitter wiring, and channel
  registration.
- Wire encoding beyond the `TaskManagerOp` shape.
- Cross-DDS task execution callbacks; the kernel only decides queue ownership.

## Milestones

**TM1 — Core queue semantics (1 day).** Types, reads, summary, volunteer,
abandon, complete, remote apply, local ack. Unit tests first for FIFO,
duplicates, optimistic guards, and complete.
Exit: core connected-state tests pass and every T1–T11 row has coverage.

**TM2 — Membership, attach, rollback/resubmit (1 day).** `remove_client`,
`on_disconnect`, placeholder helpers, scrub-on-load, rollback, resubmit, stash.
Exit: detached/attach, disconnect, and rollback suites pass.

**TM3 — Fuzz/property model (1 day).** Connected convergence/oracle first, then
membership disconnects if the harness supports leave events.
Exit: 1000 seeded runs green; mutation checks fail as expected.

Total: **~3 days**, consistent with the 5/10 rating. Runtime integration is a
separate task because subscription and promise behavior belongs above the pure
kernel.

## Open questions

- Should the runtime map Fluid client ids to `Int` globally, or should this
  kernel use `String` client ids and adapt the fuzz harness? The plan chooses
  `Int` for consistency with existing kernel models.
- Should wrapper-level subscription state live in a later
  `task_manager_client.gleam`, or wait until the runtime-generalization work can
  host all DDS client APIs uniformly?
