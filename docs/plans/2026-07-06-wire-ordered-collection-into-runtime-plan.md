# Plan: Wire `ordered_collection_kernel` into the runtime

**Date:** 2026-07-06
**Status:** 📋 Proposed — not started. Depends on a new **client-leave /
disconnect hook** that does not exist anywhere in the runtime today.
**Repo:** `claude-workspace/watershed`
**Companion docs:**
`2026-07-03-ordered-collection-kernel-plan.md` (the kernel itself),
`2026-07-06-wire-pn-counter-into-runtime-plan.md` (the mechanical template),
`2026-07-06-runtime-kernel-wiring-order.md` (sequencing).

## Context

`ordered_collection_kernel` (`src/watershed/ordered_collection_kernel.gleam`,
fully read) is a pure port of FluidFramework's `ConsensusOrderedCollection`: a
FIFO job queue where `acquire` removes the head into per-client job tracking,
and `complete`/`release` finish or return a held item. It has kernel unit +
fuzz tests but **zero references outside its own file**.

Unlike `pact_map`, it **does** have a normal optimistic lifecycle
(`apply_remote`, `ack_local`, `rollback`, `apply_stashed_op`), plus detached
helpers (`add_detached`, `acquire_detached`). So the op-path wiring is
**mechanical** and follows the `pn_counter` template. The genuinely new piece
is **disconnect handling**.

### Public API (verified)

| Fn | Signature (abridged) | Notes |
|----|----------------------|-------|
| `new` / `from_summary` | `(queue, jobs)` | summary = FIFO queue + job dict |
| `summary_queue` / `summary_jobs` | | key-sorted jobs |
| `size` | `-> Int` | |
| `add` / `acquire` / `complete` / `release` | build an `OrderedOp` | pure op constructors |
| `add_detached` | `(value) -> #(state, events)` | local pre-attach apply |
| `acquire_detached` | `(acquire_id) -> #(state, events, AcquireOutcome)` | |
| `apply_add` / `apply_acquire` / `apply_complete` / `apply_release` | sequenced applies | |
| `apply_remote` | `(op, author) -> #(state, events)` | remote sequenced path |
| `ack_local` | `(op, author) -> #(state, events, Option(AcquireOutcome))` | own-op ack; acquire yields the item |
| `ack_local_acquire` | `(acquire_id, author) -> #(state, events, AcquireOutcome)` | |
| `remove_client` | `(owner: Option(Int)) -> #(state, events)` | **disconnect:** re-releases the leaver's held jobs to the queue |
| `on_disconnect_notify` | `(owner) -> List(OrderedEvent)` | notification-only `LocalReleased` events |
| `rollback` / `apply_stashed_op` | | offline/reconnect support |

`OrderedOp = Add(value) | Acquire(id) | Complete(id) | Release(id)`.
`OrderedEvent = Added(value, newly_added, local) | Acquired(value, owner, local)
| Completed(value, local) | LocalReleased(value, intentional)`.
`AcquireOutcome = AcquiredItem(acquire_id, value) | QueueEmpty`.

### `acquire_id` generation

`acquire`/`complete`/`release` are keyed by an `acquire_id: String`. The
runtime must mint a unique id per acquire (reuse `ids.uuid_v4`, already
target-split per the M7 handles work) and hand it back to the caller so
`complete`/`release` can reference the held job. Decide the ergonomics:
either the runtime returns the id from `ordered_acquire`, or the caller passes
one in. **Recommend runtime-minted, returned via the acquire reply /
`AcquireOutcome`.**

## The new piece: client-leave / disconnect

**There is no client-leave/disconnect wiring anywhere in the runtime** —
confirmed by grep: `remove_client` / `on_disconnect` / `remove_member` /
`scrub_not_in_quorum` are referenced only in kernels, never in
`runtime_core.gleam` / `runtime.gleam` / `runtime_js.gleam`. Even the wired
`task_manager` and `claims` kernels expose disconnect fns that are never
called. The only "disconnect" in `src/` is transport-level socket reconnect
(`transport_ffi.mjs`), which is unrelated.

For `ordered_collection` this matters for **correctness**: if a client
acquires a job and then disconnects, its held item must be **re-released** to
the queue so another client can take it (`remove_client`), and locally the
holder should be notified (`on_disconnect_notify` → `LocalReleased`).

### What a leave hook needs

FluidFramework drives this off **quorum/membership `removeMember`** events on
the ordering service. In watershed today the runtime has no membership feed. To
wire disconnect we need, at minimum:

1. **A membership signal.** Determine what levee/spillway emits on client
   leave (a `clientLeave`/quorum-remove message, or a signal). *Verify against
   spillway/levee before designing the codec* — this is the key unknown.
2. **A sequenced leave carrier.** `remove_client`/`remove_member` take a
   `leave_seq`; the leave must arrive as (or be stamped with) a sequence number
   so all clients converge on the same re-release ordering.
3. **A runtime fan-out.** On a leave, iterate attached channels and call each
   channel's leave handler (new `channel.on_leave(state, client_id, seq)`
   dispatch), collecting events. This is the shared hook `pact_map.remove_member`
   also needs.

**Because the membership signal is an unknown that spans the whole stack, the
disconnect hook is treated as its own workstream** (see ordering doc). The
op-path wiring below does **not** depend on it and should land first; the
kernel is safe without leave handling (jobs simply stay held until the holder
returns), it is just not fully correct under real disconnects.

## Wiring surface — op path (mirrors pn_counter, mechanical)

1. **`wire.gleam`** — `pub const channel_type_ordered_collection = "orderedCollection"`.
2. **`channel.gleam`**
   - Add `Ordered*` to `ChannelType`/`Init`/`State`/`Op`/`Event`/`Snapshot`
     (`OrderedSnapshot(queue: List(Json), jobs: List(#(String, JobEntry)))`)
     and a `LocalOpMeta` variant if own-op ack needs to carry the acquire id /
     outcome routing (an `Acquire` ack yields an `AcquireOutcome` the caller
     wants). Add `OrderedMeta(...)` to the exhaustive ack-arm lists (same
     gotcha as pn_counter).
   - `apply_remote` arm → `apply_remote(op, meta.author)`.
   - `ack_local` arm → `ack_local(op, meta.self)`; surface the
     `Option(AcquireOutcome)` (needed so a local acquire returns its item).
   - `new`/`from_snapshot`/`snapshot`/`attach_snapshot` over
     `summary_queue`/`summary_jobs`. Detached edits: attach should carry
     optimistic detached adds/acquires (see the directory-DDS memory about
     which kernels carry optimistic detached edits — decide per this kernel;
     `add_detached`/`acquire_detached` exist, so treat like or_set/g_set which
     carry optimistic detached edits).
   - `same_shape`/`same_ordered_shape`, `same_snapshot`, `handle_addresses`
     (values may be arbitrary Json incl. handles → scan `Add` values and queue
     entries for handle addresses, mirroring the map kernel).
   - `encode_snapshot`/`snapshot_decoder` (+ `JobEntry` codec:
     `{value, owner:Option(Int)}`).
3. **`wire/ops.gleam`** — encode/decode `OrderedOp`:
   `{type:"orderedAdd", value}`, `{type:"orderedAcquire", acquireId}`,
   `{type:"orderedComplete", acquireId}`, `{type:"orderedRelease", acquireId}`.
   Extend `encode_channel_op` + `channel_op_decoder`; add envelope codecs.
4. **`runtime_core.gleam`** — `ordered_add`, `ordered_acquire` (mints id,
   returns `AcquireOutcome`), `ordered_complete`, `ordered_release`,
   `locate_ordered`, `tag_ordered_events`, reads `ordered_size`,
   `ordered_queue`, `ordered_jobs`.
5. **`runtime.gleam`** — `Msg`: `CreateOrderedCollection`, `OrderedAdd`,
   `OrderedAcquire(reply)`, `OrderedComplete`, `OrderedRelease`,
   `GetOrderedSize` + handlers + `InitOrderedCollection` import.
6. **`runtime_js.gleam`** — `create_ordered_collection`, `ordered_add`,
   `ordered_acquire`, `ordered_complete`, `ordered_release`, `ordered_size`.
7. **Tests** — `ordered_collection_channel_test.gleam`: FIFO convergence
   across two clients (add/acquire/complete/release), detached add then attach,
   snapshot round-trip, `same_shape` echo, acquire returns the head item.
   Extend `wire_test.gleam` with the four op envelope round-trips. Kernel fuzz
   (`ordered_collection_model`, includes disconnect/leave capability) already
   exists.

## Wiring surface — disconnect path (second workstream)

Once the shared leave hook exists (from the ordering doc):
- `channel.on_leave` dispatch arm → `remove_client(Some(client_id))` +
  optionally emit `on_disconnect_notify` locally for the departing self.
- Runtime fan-out iterates channels on the membership-leave message and tags
  the resulting `Added`/`LocalReleased` events.
- Test: client A acquires, "disconnects" (inject a sequenced leave), assert the
  item is re-released to the queue on client B and B can re-acquire it; assert A
  sees `LocalReleased`.

## Validation gates

`gleam build` (both targets), `just lint`, `just test`, `just fuzz`
(FUZZ_ITERATIONS=5000). Op-path tests must pass before the disconnect
workstream begins; disconnect tests gated on the shared leave hook.
