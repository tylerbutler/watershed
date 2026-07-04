# Fluid DDS → Gleam porting complexity assessment

**Date:** 2026-07-03
**Source surveyed:** `FluidFramework/packages/dds/` (local checkout)
**Purpose:** Planning input for which DDS kernels to port next in watershed.

## Scope and method

Ratings assume the watershed approach: port each DDS as a **pure functional
kernel** (state + apply-op + pending-state rebase), not the Fluid runtime
plumbing around it. Ratings are 1–10, driven by the intrinsic complexity of
each DDS's merge semantics, informed by source size as a secondary signal.

Already done in watershed:

- ✅ **counter** — `src/watershed/counter_kernel.gleam`
- ✅ **map** (SharedMap) — `src/watershed/map_kernel.gleam`
- ✅ **claims** — `src/watershed/claims_kernel.gleam`
- ✅ **register-collection** — `src/watershed/register_collection_kernel.gleam`
- ✅ **pact-map** — `src/watershed/pact_map_kernel.gleam`
- ✅ **ordered-collection** — `src/watershed/ordered_collection_kernel.gleam`

## Ratings

| DDS | Rating | Src LOC | Status | Notes |
|---|---|---|---|---|
| shared-summary-block | 1 | 252 | — | No ops at all; just a serialized blob in the summary. Trivial, and probably pointless to port. |
| counter | 1 | 438 | ✅ done | Commutative increments — no conflict resolution. |
| cell | 2 | 640 | skip | Single last-writer-wins register. Skipped: a one-key SharedMap gives the same semantics, and `map_kernel` is done. |
| claims | 2 | 595 | ✅ done | First-writer-wins plus experimental CAS via per-key sequence numbers (`ref_seq` equality check). Reads are non-optimistic — no rebase machinery. `src/watershed/claims_kernel.gleam`; plan `2026-07-03-claims-kernel-plan.md`. |
| register-collection | 3 | 638 | ✅ done | Consensus register retaining concurrent versions, with atomic/LWW read policies. Implemented in `src/watershed/register_collection_kernel.gleam` with unit + fuzz coverage. Plan: `2026-07-03-register-collection-kernel-plan.md`. |
| ink | 3 | 999 | skip | Append-only stroke data; deprecated upstream. |
| pact-map | 4 | 667 | ✅ done | Value accepted only once all connected clients have seen it. Implemented in `src/watershed/pact_map_kernel.gleam` with quorum/accept unit + fuzz coverage. Plan: `2026-07-03-pact-map-kernel-plan.md`. |
| ordered-collection | 4 | 874 | ✅ done | Consensus queue with acquire/complete/release lifecycle and re-release when a holder disconnects. Implemented in `src/watershed/ordered_collection_kernel.gleam` with unit + fuzz coverage. Plan: `2026-07-03-ordered-collection-kernel-plan.md`. |
| task-manager | 5 | 1208 | — | Op format is simple (volunteer/abandon); complexity is in connection-state transitions, queue-position tracking, subscription mode. |
| map (SharedMap) | 3 | (part of 4801) | ✅ done | Per-key LWW with pending-state rebase. |
| map (SharedDirectory) | 5 | (part of 4801) | — | Nested subdirectories, create/delete conflict resolution, pending-local-state rebasing — where most of the package's complexity lives. |
| legacy-dds | 5 | 1799 | skip | SharedArray (insert/delete/move) + SharedSignal. Explicitly legacy upstream. |
| matrix | 7 | 2676 | — | Two permutation vectors built on merge-tree internals, sparse 2D storage, handle recycling, switchable LWW/FWW cell-write policies. Blocked on a sequence CRDT. |
| merge-tree | 9 | 14153 | — | Sequence CRDT: segment block tree, partial lengths, ordinals, segment GC ("zamboni"), local references, obliterate. Aggressively imperative/perf-tuned — a Gleam version is a redesign (persistent rope / finger tree), not a translation. |
| sequence | 9 | 7230 | — | SharedString etc. layered on merge-tree, plus interval collections with notoriously subtle rebase semantics (endpoint sliding under concurrent edits). ~6 once merge-tree exists. |
| tree | 10 | 77804 | — | SharedTree: stored-vs-view schema system, forest, compositional changeset rebasing, undo/redo, ID compression. Multi-year project in any language. |

Not DDSes (no rating):

- **shared-object-base** — runtime harness (channel/summary/delta plumbing);
  watershed's `runtime.gleam` / `runtime_core.gleam` is the equivalent layer,
  designed on its own terms.
- **test-dds-utils** — test infra; its fuzz model (random op interleavings
  against a reference model) is worth stealing as inspiration for kernel tests.

## Gleam-specific considerations

- **Immutability mostly helps.** The optimistic-local-state + rebase pattern
  every DDS uses ("apply locally, reconcile when the op comes back sequenced")
  is naturally a pure fold over ops — cleaner in Gleam than the TS originals,
  which interleave it with event emitters and mutation.
- **The hard ones are hard for a different reason.** merge-tree/matrix/tree
  lean on mutable arrays, in-place tree surgery, and cache-friendly layouts.
  A faithful port is the wrong move; the Gleam version should keep the
  *semantics* but use persistent structures (RRB-style rope or finger tree
  for sequences).
- **Deterministic kernels are highly testable** via op-interleaving tests:
  every kernel should pass "any sequenced interleaving converges" property
  tests before wiring into the runtime.

## Recommended porting ladder

With counter, SharedMap, claims, register-collection, pact-map, and
ordered-collection done, the remaining ladder shifts from low-cost consensus
kernels toward connection-state behavior, hierarchy, and sequence CRDTs:

1. ~~cell~~ — skipped: a single-key map covers the LWW-register pattern.
2. ~~claims~~ (2) — ✅ done: first-writer-wins + per-key-seq CAS; introduced the
   deferred-outcome contract (`2026-07-03-claims-kernel-plan.md`).
3. ~~register-collection~~ (3) — ✅ done: concurrent-version retention + read policies.
   Reuses claims' non-optimistic deferred-outcome shape; needs **no harness
   extension**. Plan: `2026-07-03-register-collection-kernel-plan.md`.
4. ~~pact-map~~ (4) — ✅ done: quorum/ack consensus pattern.
   Plan: `2026-07-03-pact-map-kernel-plan.md`.
5. ~~ordered-collection~~ (4) — ✅ done: consensus queue lifecycle.
   Plan: `2026-07-03-ordered-collection-kernel-plan.md`.
6. **task-manager** (5) — connection-state-dependent behavior. This is now the
   next low-to-mid-complexity Fluid DDS rung. Plan:
   `2026-07-04-task-manager-kernel-plan.md`.
7. **map: SharedDirectory** (5) — hierarchical namespace on the existing map kernel.
   Plan: `2026-07-04-shared-directory-kernel-plan.md`.
8. **merge-tree redesign** (9) — persistent sequence CRDT; unlocks sequence (9→~6) and matrix (7).
9. **tree** (10) — only if there's a compelling product need.

Rungs 2–7 cover every conflict-resolution pattern in the Fluid catalog
(commutative, LWW, FWW, consensus, queue lifecycle) at low individual cost.

**Sequencing note (completed rungs 4–5).** pact-map and ordered-collection both
needed two shared fuzz-harness generalizations — *follow-on ops* (applying a
sequenced op enqueues a new op) and *membership-leave as a sequenced event* —
specified in `2026-07-03-fuzz-harness-consensus-extension-plan.md` (F6 / CO0).
Those kernels now have dedicated fuzz suites:
`test/watershed/pact_map_fuzz_test.gleam` and
`test/watershed/ordered_collection_fuzz_test.gleam`.
