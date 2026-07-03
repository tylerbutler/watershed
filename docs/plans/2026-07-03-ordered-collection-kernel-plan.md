# ConsensusOrderedCollection (consensus queue) kernel port plan

**Date:** 2026-07-03
**Builds on:** `2026-07-03-dds-porting-complexity.md` (rated ordered-collection
4/10), `2026-07-03-claims-kernel-plan.md` (deferred-outcome shape), and
`2026-07-03-kernel-fuzz-harness-plan.md`.
**Reference source:**
`../FluidFramework/packages/dds/ordered-collection/src/`
(`consensusOrderedCollection.ts` 460 LOC, `consensusQueue.ts` 53,
`snapshotableArray.ts` 23, `interfaces.ts` 144, plus
`consensusOrderedCollection.spec.ts` 984 as the behavioral oracle).

> **Shared prerequisite with pact-map.** This kernel and pact-map both need two
> harness generalizations — **follow-on ops** (applying a sequenced op can
> enqueue a new op from that client) and **membership-leave as a sequenced
> event** (a disconnect has a sequence point and a deterministic state effect).
> The `kernel_fuzz.SequencedMeta` record already carries `connected_clients` and
> `min_sequence_number` with a comment naming these two kernels as the intended
> consumers, so the harness author front-loaded the *data*; the *interpreter*
> changes are still to be built. That work is specified in its own document —
> **`2026-07-03-fuzz-harness-consensus-extension-plan.md`** (F6 / CO0) — and is
> summarized as milestone CO0 below. Build it **once**, shared with pact-map,
> before either kernel's fuzz work.

## Why ordered-collection is this rung

Claims/CRC were consensus *registers* (last state wins by a per-key rule).
Ordered-collection is the first consensus *queue*: a FIFO whose add/acquire
order is decided by the server sequence, plus an **acquire → complete/release
lifecycle** with **owner tracking** and **re-release on disconnect**. The op
format is trivial (four one-field ops); all the complexity is in the lifecycle
and the disconnect edge.

It is again **non-optimistic**: the collection is not mutated until an op
sequences, so a local `acquire` doesn't remove anything locally until its op
comes back. The deferred outcome is the claims pattern once more: `acquire`
resolves to the acquired value, or `undefined` if the queue was empty when the
acquire sequenced.

Two genuinely new ingredients:

1. **Lifecycle with owner tracking.** An `acquire` removes the front item and
   records `acquireId → {value, owner=author}` in job-tracking. The owner later
   emits `complete` (drop it) or `release` (return it to the queue). Both
   tolerate a missing job entry (the item may have already been re-released).
2. **Re-release on disconnect.** When a client leaves, every item it holds
   returns to the queue, in a deterministic order tied to when its leave
   sequences. This is the membership-driven effect the harness extension exists
   for.

## Semantics inventory (from `consensusOrderedCollection.ts`)

| # | Behavior | Source |
|---|---|---|
| O1 | Four ops: `add{value}`, `acquire{acquireId}`, `complete{acquireId}`, `release{acquireId}`. `acquireId` is a uuid minted by the acquirer. | occ.ts:51–83 |
| O2 | State: a FIFO `data` (front = next removed) + `jobTracking: Map<acquireId, {value, owner}>` (owner = clientId, or undefined for local-unattached). | occ.ts:39–46,95 |
| O3 | `add`: detached → `addCore`. Attached → submit `add`. `addCore` = push to queue + emit `add(value, newlyAdded=true)`. | occ.ts:146,379 |
| O4 | `acquireCore(acquireId, clientId)`: if queue empty → undefined. Else remove front, record `jobTracking[acquireId]={value, clientId}`, emit `acquire(value, clientId)`, return `{acquireId, value}`. Runs identically on all clients. | occ.ts:384 |
| O5 | Local acquire ack resolves the promise with the acquired value (or undefined). This drives the caller's callback → complete/release. | occ.ts:356–360 |
| O6 | `completeCore(acquireId)`: if job present → delete + emit `complete(value)`. Missing → no-op (already re-released). | occ.ts:240 |
| O7 | `releaseCore(acquireId)`: if job present → delete + push value back to queue + emit `add(value, newlyAdded=false)`. Missing → no-op. | occ.ts:269 |
| O8 | `removeClient(clientId)`: for every job owned by `clientId`, delete + push value back to queue, then emit `add(newlyAdded=false)` for each — after all mutations, to keep event-reentrancy order stable. Ordering across items is deterministic. | occ.ts:415 |
| O9 | Disconnect wiring: `runtime.getQuorum().on("removeMember", clientId => removeClient(clientId))`. So each client re-releases the leaver's items when it processes that leave, at the leave's sequence point. | occ.ts:137 |
| O10 | `complete`/`release` are only submitted when `isActive()` (connected + delta-manager active); if inactive the item was already released to the queue by others' `removeClient`, so no op is sent. | occ.ts:225,249 |
| O11 | Detached acquire mints a uuid with `owner=undefined`; `summarizeCore` first calls `removeClient(undefined)` to flush local-unattached acquisitions back to the queue before snapshotting (attach loses in-flight local work). | occ.ts:208–211,403 |
| O12 | Rollback: resolve the pending promise `undefined` (acquire → false / add → resolved). No state to undo. | occ.ts:450 |
| O13 | Stashed op: resubmit with a no-op resolve (acquire promises resolve false). | occ.ts:438 |
| O14 | Summary: two blobs — `data.asArray()` (queue) and `[...jobTracking.entries()]`. Load restores both; asserts both empty pre-load. | occ.ts:208–219,282 |
| O15 | `onDisconnect` emits `localRelease(value, intentional=false)` for each locally-held job — a *notification*, not a state change (the actual re-release happens via O8 when the leave sequences). | occ.ts:304 |

## Kernel design

New module `src/watershed/ordered_collection_kernel.gleam`. Backing data is a
plain FIFO list; `consensusQueue.ts`'s `SnapshotableQueue` (push/shift) maps
directly to append/`list` head. (Stack/other orderings are out of scope — only
the queue variant is used.)

### Types

```gleam
pub type OrderedState {
  OrderedState(
    /// FIFO queue, front (next to remove) = head.
    queue: List(Json),
    /// acquireId → held item. Owner is the acquiring client id, or None for a
    /// local-unattached acquisition.
    jobs: Dict(String, JobEntry),
  )
}

pub type JobEntry {
  JobEntry(value: Json, owner: Option(Int))
}

pub type OrderedOp {
  Add(value: Json)
  Acquire(acquire_id: String)
  Complete(acquire_id: String)
  Release(acquire_id: String)
}

pub type OrderedEvent {
  /// newly_added distinguishes a fresh add (True) from a re-release / return
  /// to queue (False), mirroring the TS `add(value, newlyAdded)` flag.
  Added(value: Json, newly_added: Bool, local: Bool)
  Acquired(value: Json, owner: Option(Int), local: Bool)
  Completed(value: Json, local: Bool)
  /// Notification only (O15): a locally-held item will be re-released when the
  /// leave sequences. Carries no state change.
  LocalReleased(value: Json, intentional: Bool)
}

/// Deferred outcome of a local acquire: the acquired item, or None if the
/// queue was empty when the acquire sequenced (O4/O5).
pub type AcquireOutcome {
  AcquiredItem(acquire_id: String, value: Json)
  QueueEmpty
}
```

### API surface

| Function | Signature (abbrev.) | Notes |
|---|---|---|
| `new` | `fn() -> OrderedState` | |
| `from_summary` | `fn(List(Json), List(#(String, JobEntry))) -> OrderedState` | O14 two-blob round-trip. |
| `summary_queue` / `summary_jobs` | committed snapshot halves | O14. |
| `size` | `fn(state) -> Int` | Queue length. |
| `add` | `fn(state, value) -> OrderedOp` | Attached submit; state unchanged (non-optimistic). |
| `add_detached` | `fn(state, value) -> #(OrderedState, List(OrderedEvent))` | O3 `addCore`. |
| `acquire` | `fn(acquire_id) -> OrderedOp` | Attached submit. `acquire_id` supplied by the runtime (see decision 1); state unchanged. |
| `acquire_detached` | `fn(state, acquire_id) -> #(OrderedState, List(OrderedEvent), AcquireOutcome)` | O4 with `owner=None`. |
| `apply_add` | `fn(state, value) -> #(OrderedState, List(OrderedEvent))` | O3 `addCore`. |
| `apply_acquire` | `fn(state, acquire_id, author) -> #(OrderedState, List(OrderedEvent), Option(Json))` | O4. Returns the acquired value (None if empty) so `ack_local` can build the outcome. |
| `apply_complete` | `fn(state, acquire_id) -> #(OrderedState, List(OrderedEvent))` | O6; no-op if job absent. |
| `apply_release` | `fn(state, acquire_id) -> #(OrderedState, List(OrderedEvent))` | O7; no-op if job absent. |
| `remove_client` | `fn(state, owner) -> #(OrderedState, List(OrderedEvent))` | O8/O11: re-release all items owned by `owner` (an `Int` id, or `None` for the unattached flush), deterministic order, events after mutations. |
| `ack_local_acquire` | `fn(state, acquire_id, author) -> #(OrderedState, List(OrderedEvent), AcquireOutcome)` | O5: `apply_acquire` + wrap the outcome. |
| `rollback` | `fn(state, op) -> #(OrderedState, AcquireOutcome)` | O12: state unchanged; outcome `QueueEmpty` (acquire resolves false / add resolves). |
| `apply_stashed_op` | `fn(state, op) -> #(OrderedState, OrderedOp)` | O13: state unchanged, op verbatim. |

`add`/`complete`/`release` acks carry no outcome (the TS resolve value is
`undefined` for them), so a single `ack_local` that dispatches on op kind and
returns `Option(AcquireOutcome)` (Some only for `Acquire`) is the clean shape;
`apply_remote` dispatches the same four kinds with no outcome.

Deterministic-ordering note for O8: iterate `jobs` in a stable order (sort by
`acquire_id`) so every client re-releases a leaver's items into the queue in the
same order and converges. The TS relies on Map insertion order + per-client
disconnect sequencing; the kernel makes the order explicit and total.

### Design decisions (and rejected alternatives)

1. **`acquire_id` is a runtime-supplied parameter, not kernel-minted.** The TS
   mints a uuid inside the DDS. A pure kernel cannot mint uuids; the runtime
   (or fuzz model) supplies a unique id, exactly as it supplies sequence
   numbers. The fuzz model uses a deterministic counter so shrinking stays
   reproducible. *Rejected:* an FFI uuid call inside the kernel — it would make
   the kernel impure and its tests non-deterministic.
2. **Non-optimistic, no pending state.** Like claims/CRC, nothing is mutated
   until an op sequences, so there is no pending overlay. The deferred outcome
   (`AcquireOutcome`) is recomputed at ack from `apply_acquire`; the kernel
   stores no per-acquire pending record. Missing-job tolerance (O6/O7) means a
   `complete`/`release` for an already-returned item is a legitimate no-op, not
   an error — so `apply_complete`/`apply_release` are total, and `ack_local`
   for them cannot fail. (Contrast claims' strict acks: there the ack protected
   a one-per-key invariant; here the tolerated no-op *is* the spec.)
3. **`remove_client` is the membership effect, driven by the harness's leave
   event.** It is a pure function `(state, owner) -> (state, events)`; the
   harness decides *when* to call it (when a leave sequences) and threads the
   result. This keeps all the disconnect subtlety (O8/O9/O11) in one testable
   pure function.
4. **`isActive` gating (O10) is a runtime concern, not the kernel's.** The
   kernel always produces the complete/release op when asked; the runtime
   decides whether to send it based on connection state. The fuzz model
   approximates this by only emitting complete/release for jobs the client still
   believes it owns. *Rejected:* modeling `isActive` in the kernel — it is pure
   connection state the runtime already owns.
5. **`localRelease` is an event, not a state transition** (O15). It is emitted
   by a separate `on_disconnect_notify(state, self_id) -> List(OrderedEvent)`
   helper the runtime calls; it never mutates state. Kept as a helper so the
   event surface is complete, but it is out of the convergence-critical path.
6. **Values are `Json`.** Same as every other kernel.

## Follow-on ops and the harness extension (shared milestone CO0)

> Full specification: **`2026-07-03-fuzz-harness-consensus-extension-plan.md`**.
> This section states only what ordered-collection needs from it.

The convergence-critical new capability: after a local `acquire` sequences and
resolves, the acquirer runs its callback and emits **either** a `complete`
**or** a `release` op. The current fuzz harness has no channel for "applying a
sequenced op produces a new op." Ordered-collection's follow-on is a *local
decision by the acquirer* (simpler than pact-map, where *every* signoff client
emits an accept). The extension, built once and shared with pact-map:

- **Reactive ops:** extend the interpreter so a delivery step can enqueue
  follow-on ops from the delivering client into its inbox/resend. For
  ordered-collection, the acquire command carries a generated `disposition`
  (`Complete | Release`); when the acquirer acks a *successful* acquire, the
  model emits the corresponding follow-on op. A `QueueEmpty` acquire emits
  nothing.
- **Membership-leave as a sequenced event:** give `Disconnect` a sequence point
  whose delivery invokes `remove_client(leaver_id)` on every client (via a
  synthetic op or a dedicated interpreter branch), so re-release converges.
  `SequencedMeta.connected_clients` already lets `apply_*` see the quorum.

CO0 designs and lands these interpreter changes with counter/map/claims/CRC
models unaffected (they supply neither capability). This is the one place the
4/10 rating is spent.

## Test plan (TDD — tests first per house rules)

### 1. `test/watershed/ordered_collection_kernel_test.gleam` — ported unit suite

Port `consensusOrderedCollection.spec.ts`, translated to the pure API:

- **Detached:** add then acquire returns the value at seq 0; acquire on empty →
  `QueueEmpty`; `summary` after a detached acquire flushes the unattached job
  back to the queue (O11) via `remove_client(None)`.
- **Add/acquire ordering:** interleaved adds and acquires across clients; the
  server order dictates who acquires what; two clients racing `acquire` on a
  one-item queue — earlier-sequenced wins the item, the later gets `QueueEmpty`.
- **Lifecycle:** acquire → complete drops the item (not re-queued); acquire →
  release returns it to the *back* of the queue and it becomes acquirable
  again; complete/release of an already-returned item is a no-op (O6/O7).
- **Re-release on disconnect (O8):** a client acquires two items then leaves;
  both return to the queue in deterministic order; a second client can then
  acquire them; a complete arriving from the departed client for a re-released
  item is a tolerated no-op.
- **Rollback / stash:** rollback of a local acquire yields `QueueEmpty` and
  leaves the queue intact; stashed op returns verbatim and applies normally
  when sequenced.
- **Summary:** round-trip preserves queue order *and* job-tracking (owners
  included); load asserts empty-before; a post-load acquire/complete works.

### 2. Fuzz/property coverage (requires CO0)

Ship `test/watershed/fuzz/ordered_collection_model.gleam` +
`_fuzz_test.gleam` **after CO0 lands**. Until then, write a hand-rolled
multi-client property test in the eager/lazy style for the add/acquire/lifecycle
core (no disconnect), and migrate at CO0.

Model shape:
- `op` = the four `OrderedOp`s; acquire commands carry a deterministic
  `acquire_id` (counter) and a `disposition` for the follow-on (decision, CO0).
- `observe` = `#(queue, sorted jobs)` — full committed state.
- `oracle` = an independent fold of `apply_add`/`apply_acquire`/`apply_complete`/
  `apply_release`/`remove_client` over the sequenced log (including synthetic
  leave events), reimplemented in the model.
- Capabilities: `load_from_synced` (F2 summary round-trip), `rollback`,
  `apply_stashed`.

Properties:
- **Convergence:** every client's `#(queue, jobs)` equals client 0's after full
  sync (including after disconnects/re-releases).
- **Oracle:** committed state equals the independent fold.
- **Conservation:** every added value is, at every `Synchronize`, in exactly one
  of {queue, some job's held value, completed-set} — nothing is duplicated or
  lost across acquire/release/re-release. This is the property that catches a
  release that forgets to delete the job, or a re-release that drops the value.
- **At-most-one-acquirer:** each `acquire_id` acquires at most one value; each
  queued value is acquired by at most one live job at a time.

Mutation check (both caught and shrunk):
- Plant "release deletes the job but forgets to re-queue the value"
  (conservation fails).
- Plant "remove_client re-queues but forgets to delete the job" (duplication →
  conservation fails).

## Out of scope

- **Runtime integration** (kernel-sum channel type; see runtime-generalization
  plan), **`isActive`/connection gating** (decision 4), **uuid minting**
  (decision 1), **wire encoding, GC, promise plumbing** — all runtime concerns.
- **Non-queue orderings** (stack, etc.) — only the consensus *queue* is used
  upstream.

## Milestones

**CO0 — Harness reactive-ops + membership extension (1 day, SHARED with
pact-map).** Interpreter support for follow-on ops and leave-as-sequenced-event;
existing models unaffected. Do this once for both kernels.
Exit: existing fuzz suites still green; a smoke script exercises a follow-on op.

**CO1 — Core semantics (½–1 day).** Types + `new`/summary/`size` + `add`/
`acquire` (+ detached) + `apply_add`/`apply_acquire` + `ack_local_acquire`.
Unit tests first (detached, ordering, races).
Exit: detached + add/acquire-ordering groups pass.

**CO2 — Lifecycle + disconnect (½–1 day).** `apply_complete`/`apply_release`/
`remove_client`/`rollback`/`apply_stashed_op`/`on_disconnect_notify`; remaining
unit groups.
Exit: full ported suite green; every O1–O15 row traceable to a test.

**CO3 — Fuzz/property (½–1 day, needs CO0).** Model + properties + conservation
+ mutation check.
Exit: 1000 seeded runs green; both planted bugs caught.

Total: **~3 days** (CO0 shared with pact-map — ~2 days if CO0 is already
landed), consistent with the 4/10 rating.

## Open questions

- Should the queue be a plain `List(Json)` (O(n) append) or a two-list amortized
  queue? Items counts are small in tests; start with `List`, note the swap point
  if a large-queue benchmark ever matters.
- Model the callback disposition as part of the acquire command (chosen above)
  or as a separate follow-up command the fuzzer schedules independently? The
  former keeps acquire→disposition causally linked and shrinks better; revisit
  if independent scheduling surfaces a bug class the coupled form misses.
</content>
