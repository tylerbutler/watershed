# Runtime kernel-wiring: suggested order of work

**Date:** 2026-07-06
**Repo:** `claude-workspace/watershed`
**Scope:** Wire the three implemented-but-unwired kernels into the runtime
(`pn_counter`, `pact_map`, `ordered_collection`) across both the Erlang
(`runtime.gleam`) and JS (`runtime_js.gleam`) runtimes.

This doc is the index + sequencing for three per-kernel plans:

- `2026-07-06-wire-pn-counter-into-runtime-plan.md` — ✅ done, template.
- `2026-07-06-wire-pact-map-into-runtime-plan.md` — 📋 proposed.
- `2026-07-06-wire-ordered-collection-into-runtime-plan.md` — 📋 proposed.

## Why an order matters

All three kernels touch the **same shared files** (`channel.gleam`,
`wire/ops.gleam`, `runtime_core.gleam`, `runtime.gleam`, `runtime_js.gleam`),
so the work is inherently **sequential** — parallel branches would collide on
every dispatch function. Beyond merge risk, two of the kernels need **new
runtime infrastructure** that does not exist today:

1. **Reaction auto-submit** (pact_map's `OweAccept` → outbound `Accept`). Today
   the only vehicle is json0's `take_outbound`/`collect_released_ops` loop,
   hard-coded to `JsonOtState`.
2. **Client-leave / disconnect hook** (pact_map's `remove_member`,
   ordered_collection's `remove_client`/`on_disconnect_notify`). **No leave
   wiring exists anywhere** — even wired `task_manager`/`claims` disconnect fns
   are never called. It also depends on an **unknown**: what membership-leave
   signal levee/spillway emits.

Sequencing isolates each new capability into its own reviewable step and keeps
the always-green build.

## Recommended order

### Phase 0 — `pn_counter` (DONE)

Pure optimistic kernel, no reactions, no disconnect. Established the mechanical
"add a kernel" checklist and surfaced the `LocalOpMeta` exhaustiveness gotcha.
546 tests pass on both targets. Use as the copy-paste template for the
mechanical parts below.

### Phase 1 — Generalize the released-ops buffer  *(new infra, no new kernel)*  (DONE)

Prep step that unblocks pact_map cleanly:

- Lift json0's single-purpose `take_outbound` into a **generic per-channel
  "owed outbound ops" buffer** at the channel-wrapper layer
  (`channel.gleam:788`), drained by the existing `collect_released_ops`
  (`runtime_core.gleam:487`) unchanged.
- json0 keeps working (its buffer becomes one producer among several).
- Deliverable: any kernel arm in `channel.apply_remote` can enqueue a follow-up
  op that the actor loop auto-submits with a fresh CSN + in-flight entry.
- Validation: existing json0 tests stay green; add a unit test for the generic
  buffer.

*Rationale for doing this first:* it is small, isolated, and keeps pact_map's
diff focused on kernel semantics rather than plumbing.

### Phase 2 — `pact_map` op path (Set/Accept, reactions)  (DONE)

Full per-kernel wiring except membership-leave. Uses the Phase 1 buffer for the
`OweAccept` → `Accept` follow-up, and reuses the existing `task_manager`
quorum-meta plumbing (`meta.quorum`/`meta.self`/`meta.seq`) already built in
`apply_remote_channel`. Ship convergence (pending → accepted) + a reaction
test. Leave-driven settling deferred to Phase 4.

Implemented: own `Set`/`Accept` apply on sequencing through the same
`apply_remote` path as remote ops (gated by `channel.applies_own_on_sequence`),
reclaiming only the in-flight entry. Runtime quorum is approximated as
`[self, author]`, so cross-client convergence is asserted at the channel level
(consistent quorum); the runtime test asserts the auto-`Accept` reaction.
558 tests pass on both targets; `just lint`/`just fuzz` green.

### Phase 3 — `ordered_collection` op path (Add/Acquire/Complete/Release)  (DONE)

Purely mechanical — it has the normal optimistic lifecycle
(`apply_remote`/`ack_local`/`rollback`/`apply_stashed_op`), so it follows the
pn_counter template directly. Adds acquire-id minting (`ids.uuid_v4`) and
returning the acquired item via `AcquireOutcome`. Disconnect deferred to
Phase 4.

*Phases 2 and 3 are independent in concept but share files, so do them
back-to-back on one branch, pact_map first (it also exercises Phase 1).* 

### Phase 4 — Shared client-leave / disconnect hook  *(new infra)*  (DONE)

The largest unknown; done last, once both kernels' op paths were green.

1. **Spike (resolved):** levee broadcasts a **sequenced `"leave"` system
   message** on client disconnect (`server/lib/levee/documents/session.ex`
   `generate_system_message("leave", ...)`): `clientId` is null, `contents`
   carries the departing client's id string, and it is stamped with
   `sequenceNumber` + `minimumSequenceNumber`. spillway models the same wire
   type (`message.MessageType.ClientLeave -> "leave"`). So a sequence-stamped
   leave carrier exists end-to-end — no new server/protocol work required. (The
   non-sequenced `signals.SystemSignal.LeaveSignal` path is *not* used; the
   sequenced op is the correct carrier because it carries `leave_seq`.)
2. Added `channel.on_leave(state, client_id, leave_seq)` dispatch: PactMap →
   `remove_member` (drains the leaver's outstanding signoffs so stuck pending
   values settle), ConsensusOrderedCollection → `remove_client` (re-releases the
   leaver's held jobs to the queue), TaskManager → `remove_client`; every other
   kernel is a no-op.
3. Runtime intake: `runtime_core.apply_one` now dispatches `"leave"` system
   messages to `handle_leave`, which decodes `contents` as the client-id string,
   maps it with `client_id_to_int`, and fans `channel.on_leave` out over every
   attached channel at `msg.sequence_number`, tagging the emitted events. This is
   intake-driven, so **both targets get it for free** — no new
   `runtime.gleam`/`runtime_js.gleam` verbs.
4. Tests: ordered_collection re-release + re-acquire on a sequenced leave, and a
   no-op leave for an unrelated client (runtime path); pact_map pending-value
   settles when its outstanding signer leaves (`channel.on_leave`). 571 tests
   pass on both targets; `just lint` clean.

Deferred: `ordered_collection.on_disconnect_notify` local notification for the
departing self (the leaver has already disconnected, so the remaining replicas'
re-release is the correctness-relevant path).

### Phase 5 — Final validation

`just build`, `just lint`, `just test`, `just fuzz` (FUZZ_ITERATIONS=5000).
Confirm both targets and that the kernel-level fuzz models
(`pact_map_model`, `ordered_collection_model`, which already include
reaction/leave capabilities) still pass.

## Dependency summary

```
Phase 0 pn_counter ─── done
Phase 1 released-ops buffer ──▶ Phase 2 pact_map op path
                                         │
Phase 3 ordered_collection op path ◀─────┘ (shared files, do back-to-back)
                                         │
Phase 4 shared leave hook ◀──────────────┴── needs Phases 2 & 3 green
   └─ spike: identify levee/spillway leave signal (BLOCKING unknown)
Phase 5 final validation
```

## Open questions to resolve with the maintainer

1. **Reaction buffering location** — generic channel-wrapper buffer (Option A,
   recommended) vs. threading a follow-up op through `apply_remote`'s return
   type vs. a kernel-owned owed buffer. (See pact_map plan.)
2. **Membership-leave signal** — **resolved:** levee emits a sequenced
   `"leave"` system message (`clientId: null`, `contents: <clientId>`, carrying
   `sequenceNumber`/`minimumSequenceNumber`); wired in Phase 4.
3. **Consensus own-op routing** — should own `Set`/`Accept` (pact_map) apply on
   sequencing via the same `apply_set`/`apply_accept` as remote ops, using
   `is_own_op` only to reclaim the in-flight entry? (Recommended.)
4. **Wire strings** — `"pactMap"` / `"orderedCollection"` chosen (camelCase,
   matching `taskManager`/`registerCollection`). Confirm no server-side
   `channelType` validation requires different strings (levee currently does
   not validate).
