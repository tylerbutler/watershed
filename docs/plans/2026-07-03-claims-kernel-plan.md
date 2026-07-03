# Claims kernel port plan

**Date:** 2026-07-03
**Builds on:** `2026-07-03-dds-porting-complexity.md` (rated claims 2/10) and
`2026-07-03-kernel-fuzz-harness-plan.md` (F5 says each new kernel ships with a
fuzz model).
**Reference source:** `../FluidFramework/packages/dds/claims/src/`
(`claims.ts` 309 LOC, `interfaces.ts` 168 LOC, plus `claims.spec.ts` as the
behavioral oracle).

## Why claims is the next rung (and cell is skipped)

The porting ladder had cell (LWW register) before claims. Cell is skipped:
a LWW register is a single-key SharedMap, and `map_kernel` already covers that
pattern — anyone needing a cell can use a one-key map. Claims is the first
kernel that introduces a genuinely new conflict-resolution pattern:
**first-writer-wins with per-key sequence-number CAS**.

The survey's one-liner ("first sequenced op wins, later ones ignored")
undersells the current source. Since that note was written, claims grew an
experimental `compareAndSetClaim`, and both operations share one mechanism:

- Every committed entry stores `(value, sequence_number)` — the server
  sequence number of the op that set it.
- Every op carries a `ref_seq`. An op is **accepted** iff the key is unclaimed
  *or* `ref_seq == entry.sequence_number` (exact equality — the upstream test
  suite has a regression test proving `>=` is wrong).
- `trySetClaim` (write-once) sends `ref_seq = last seen SN`; since the client
  only submits when it has no committed entry, the op can only be accepted via
  the "unclaimed" arm — any concurrent winner necessarily has a newer SN.
- `compareAndSetClaim` sends `ref_seq = entry.sequence_number` as observed
  locally, so it succeeds only if no write was sequenced for that key since.

Two properties make claims a distinct rung from counter/map, and both
simplify the kernel:

1. **Reads are NOT optimistic.** `get`/`has` return only committed state.
   A pending local claim is invisible to reads until it wins. There is no
   pending-overlay/rebase machinery at all — the inverse of `map_kernel`.
2. **Acceptance is decided at sequencing time, identically for local and
   remote ops.** Every client evaluates the same rule against the same
   committed state, so convergence is by construction; the local-op path only
   additionally resolves the caller's pending outcome.

The genuinely new pattern for watershed is the **deferred outcome**: a local
claim's result ("did I win?") is unknowable until the op round-trips. The TS
class hands the caller a `Promise<ClaimConfirmation>`; the pure kernel instead
returns the outcome from `ack_local` and lets the runtime actor own promise/
subscriber plumbing. This is the same shape pact-map, ordered-collection, and
task-manager need, so getting the kernel⇄runtime contract right here pays
forward.

## Semantics inventory (from `claims.ts`)

Everything the kernel must reproduce:

| # | Behavior | Source |
|---|---|---|
| S1 | Op format `{type:"claim", key, value, refSeq}`; one op kind. | claims.ts:40 |
| S2 | Committed entry = `{value, sequenceNumber}`. | claims.ts:51 |
| S3 | Acceptance: `entry == undefined \|\| op.refSeq == entry.sequenceNumber`. | claims.ts:215 |
| S4 | Accepted op overwrites entry with `(op.value, envelope.sequenceNumber)` and emits `claimed(key)`. Rejected ops emit nothing. | claims.ts:217–223 |
| S5 | `trySetClaim`: if a committed entry exists, return `AlreadyClaimed(current)` synchronously — no op sent. Otherwise behaves as CAS. | claims.ts:105 |
| S6 | `compareAndSetClaim`: `refSeq = entry?.sequenceNumber ?? lastSequenceNumber`. | claims.ts:120 |
| S7 | At most one pending local claim per key; a second submit for the same key is a `UsageError`. Note ordering: `trySetClaim` checks committed state *before* the pending guard, so try-set on a committed key returns `AlreadyClaimed` even when a CAS for that key is pending. | claims.ts:140 |
| S8 | Detached: apply directly with `sequenceNumber = 0`, return `Accepted` synchronously. | claims.ts:124 |
| S9 | When a local op sequences: resolve its pending entry `Accepted(submitted value)` if it won, else `AlreadyClaimed(current committed value — may be absent)`. Pending entry is removed either way. | claims.ts:238 |
| S10 | A remote op winning a key we have a pending claim on does **not** disturb our pending entry — it resolves only when our own op sequences (and then loses). | claims.ts:225 |
| S11 | Rollback: remove the pending entry for the op's key, resolve `Aborted`. Missing pending entry is tolerated (no-op). | claims.ts:287 |
| S12 | Stashed op: re-register as pending (guards the key, no caller awaits) and resubmit the op verbatim (original `refSeq` preserved). | claims.ts:298 |
| S13 | Dispose: resolve all pending as `Aborted` and clear. | claims.ts:258 |
| S14 | Summary format: array of `{k, v, s}` — **sequence numbers are persisted**, because CAS `refSeq` matching must keep working after load. Loaded state has no pending entries. | claims.ts:171–190 |
| S15 | GC must see both committed and pending values (handle scanning). | claims.ts:270 |

## Kernel design

New module `src/watershed/claims_kernel.gleam`, in the house style of
`counter_kernel.gleam` / `map_kernel.gleam`: pure, no process, every entry
point returns new state + events + outbound op / outcome.

### Types

```gleam
pub type ClaimsState {
  ClaimsState(
    /// Committed claims: value + SN of the op that set it (S2).
    claims: Dict(String, ClaimEntry),
    /// Pending local claims, keyed by claim key — at most one per key (S7).
    /// Value = the submitted value, needed to build the Accepted outcome (S9)
    /// and for handle scanning (S15). No queue: acceptance is decided by the
    /// sequenced op itself, not by pending-queue position.
    pending: Dict(String, Json),
  )
}

pub type ClaimEntry {
  ClaimEntry(value: Json, sequence_number: Int)
}

/// The one claim op as it travels over the wire (S1).
pub type ClaimOp {
  Claim(key: String, value: Json, ref_seq: Int)
}

pub type ClaimEvent {
  /// Emitted whenever a sequenced op is accepted (S4). `local` follows the
  /// watershed convention (map/counter events carry it; the TS event doesn't).
  Claimed(key: String, local: Bool)
}

/// Synchronous result of try_set_claim / compare_and_set_claim.
pub type SubmitResult {
  /// Op must be sent; outcome arrives via ack_local (TS "Pending").
  Submitted(state: ClaimsState, op: ClaimOp)
  /// try_set_claim found a committed entry — nothing sent (S5).
  AlreadyClaimed(current_value: Json)
}

/// The resolved outcome of a pending claim, returned from ack_local /
/// rollback for the runtime to deliver to whoever is waiting (replaces the
/// TS promise, S9/S11).
pub type ClaimOutcome {
  Accepted(value: Json)
  /// Lost the race. current committed value; None if the key ended up
  /// unclaimed (a lost trySetClaim against a rolled-back... in practice a
  /// lost op whose winner was itself rejected — TS models this as
  /// `T | undefined`).
  Lost(current_value: Option(Json))
  Aborted
}

pub type KernelError {
  /// Submit-side usage error (S7) — the TS UsageError, surfaced as data.
  AlreadyPendingLocally(key: String)
  /// A local ack/rollback arrived with no matching pending entry. The TS
  /// code tolerates this silently; the kernel is strict, matching the
  /// counter/map philosophy that a routing mismatch is fatal divergence.
  UnexpectedAck(op: ClaimOp, detail: String)
  UnexpectedRollback(op: ClaimOp, detail: String)
}
```

### API surface

| Function | Signature (abbrev.) | Notes |
|---|---|---|
| `new` | `fn() -> ClaimsState` | |
| `from_summary` | `fn(List(#(String, Json, Int))) -> ClaimsState` | Triples `(key, value, seq)` — SNs persisted per S14; pending empty. |
| `summary_entries` | `fn(ClaimsState) -> List(#(String, Json, Int))` | Committed only. |
| `get` / `has` | committed-only reads | Non-optimistic by design (S9/S10); doc-comment must say so loudly. |
| `try_set_claim` | `fn(state, key, value, last_seen_seq) -> Result(SubmitResult, KernelError)` | S5 + S7 ordering: committed check first, then pending guard. `ref_seq = last_seen_seq` when unclaimed. |
| `compare_and_set_claim` | `fn(state, key, value, last_seen_seq) -> Result(SubmitResult, KernelError)` | S6: `ref_seq = entry.seq` if committed, else `last_seen_seq`. |
| `set_detached` | `fn(state, key, value) -> ClaimsState` | S8: direct insert with seq 0. The runtime decides when the channel is detached (as it does for map). |
| `apply_remote` | `fn(state, op, seq) -> #(ClaimsState, List(ClaimEvent))` | S3/S4/S10. Rejected op: state unchanged, no events. |
| `ack_local` | `fn(state, op, seq) -> Result(#(ClaimsState, List(ClaimEvent), ClaimOutcome), KernelError)` | Same acceptance as apply_remote, plus: remove pending for key, return `Accepted(pending value)` or `Lost(committed value)` (S9). Emits `Claimed(key, True)` on acceptance — unlike map/counter, **acks emit events here**, because nothing was shown optimistically at submit. |
| `rollback` | `fn(state, op) -> Result(#(ClaimsState, ClaimOutcome), KernelError)` | S11; outcome always `Aborted`. Strict on missing pending (see KernelError note). |
| `apply_stashed_op` | `fn(state, op) -> Result(#(ClaimsState, ClaimOp), KernelError)` | S12: re-register pending with the op's value, return the op verbatim for resubmission. Errors if the key is already pending. |
| `abort_all` | `fn(state) -> #(ClaimsState, List(String))` | S13: clear pending, return the aborted keys so the runtime can resolve each waiter `Aborted`. |
| `pending_values` | `fn(state) -> List(Json)` | S15: pending values for handle scanning; committed values come via `summary_entries`. |

Shared internal: `apply_sequenced(state, op, seq) -> #(ClaimsState, Bool)`
implementing S3/S4 once; `apply_remote` and `ack_local` both call it, which
makes "local and remote acceptance are identical" true in the code, not just
in review.

### Design decisions (and rejected alternatives)

1. **`last_seen_seq` is a parameter, not kernel state.** The TS code reads
   `deltaManager.lastSequenceNumber` (container-wide). Per the established
   doctrine in `map_kernel`'s header, the runtime actor owns sequencing
   concerns — `runtime_core` already tracks `last_seen_sn` and passes SNs into
   `apply_remote_channel`, so the value is at hand. *Rejected:* tracking a
   channel-local `last_seen_seq` inside `ClaimsState` (updated on every
   sequenced apply). It would also be correct — the acceptance rule only tests
   equality against an entry's SN, and any stale-but-seen SN loses to a
   concurrent winner's necessarily-newer SN — but it duplicates runtime state
   and silently diverges from the TS op contents on the wire.
2. **Exact-equality acceptance.** `ref_seq == entry.sequence_number`, never
   `>=`. Upstream's "CAS rejects when refSeq is greater than entry
   sequenceNumber" test (claims.spec.ts:420) documents the bug the equality
   check fixes; port that test.
3. **Strict `KernelError` where TS is lenient.** TS silently ignores a
   `resolvePending`/`rollback` with no pending entry ("unexpected edge
   cases"). Watershed kernels crash the runtime on ack mismatches (counter,
   map both do); claims follows suit. If the stashed-op path later proves a
   legitimate lenient case, the runtime can choose to ignore the error — the
   kernel stays strict.
4. **`ClaimOutcome` replaces promises.** The kernel returns the outcome from
   `ack_local`/`rollback`/`abort_all`; the runtime layer (out of scope here)
   maps outcomes to whatever async surface it exposes. This contract is the
   reusable piece for pact-map/ordered-collection/task-manager.
5. **Values are `Json`**, matching `map_kernel`. `null` is a legitimate
   claimed value — this is why `has` exists and why `SubmitResult.
   AlreadyClaimed` carries `Json` (the committed value, which may be JSON
   null) while `Lost` carries `Option(Json)` (the key may be genuinely
   unclaimed). Upstream round-trips `null`/`undefined` explicitly; Gleam
   collapses `undefined` into JSON null, which is an acceptable, documented
   divergence.
6. **No insertion-order tracking.** Unlike map, claims has no iterator API in
   the TS source — only `get`/`has`. `summary_entries` order just needs to be
   deterministic (sort by key) for stable snapshots.

## Test plan (TDD — tests first per house rules)

### 1. `test/watershed/claims_kernel_test.gleam` — ported unit suite

Port `claims.spec.ts` describe-by-describe, translated to the pure API
(no mock runtimes: "process messages" becomes explicit `apply_remote`/
`ack_local` calls with hand-assigned SNs):

- **Detached:** get/has on empty state; `set_detached` visible immediately
  with seq 0; summary round-trips seq-0 entries and CAS against a loaded
  seq-0 entry works (`ref_seq = 0` equality path).
- **Single client:** submit → not visible via `get` (non-optimistic — this
  is the test that would have caught a map-style port) → ack with SN →
  `Accepted`, visible, `Claimed(key, True)` emitted; try_set on committed
  key → sync `AlreadyClaimed`, no op; duplicate pending → 
  `AlreadyPendingLocally`.
- **Multi-client FWW:** two clients race a key; earlier-sequenced op wins on
  every client; loser's `ack_local` yields `Lost(Some(winner value))`;
  rejected remote op leaves state unchanged and emits nothing; independent
  keys don't interact; remote win with local pending (S10): pending survives
  the remote apply, resolves `Lost` at own ack.
- **CAS:** succeeds on unclaimed key; succeeds when unchallenged; concurrent
  CAS — first sequenced wins, second `Lost`; **the `>=` regression** —
  three-op schedule from claims.spec.ts:420 where the loser's `ref_seq` is
  *older* than the entry's SN and an accidentally-newer `ref_seq` must also
  lose; CAS on key with pending claim → error; try_set on committed key with
  CAS pending → sync `AlreadyClaimed`, not error (S7 ordering).
- **Rollback / stash / abort:** rollback removes pending and returns
  `Aborted`; rollback with no pending → `UnexpectedRollback`; stashed op
  re-registers pending (duplicate submit then errors) and the returned op is
  byte-identical (same `ref_seq`); `abort_all` returns all pending keys and
  clears them.
- **Summary:** round-trip preserves values *and sequence numbers*; CAS after
  load uses the persisted SN; JSON null value round-trips with `has == True`.

### 2. Fuzz/property coverage

Per fuzz-plan F5, ship `test/watershed/fuzz/claims_model.gleam` +
`claims_fuzz_test.gleam` in the same PR **if the harness (F1) has landed**;
otherwise write `claims_kernel_property_test.gleam` in the existing
eager/lazy/observer style and migrate at F5. Either way the properties are:

- **Convergence:** after full delivery, all clients' committed maps
  (values *and* sequence numbers) are equal.
- **Oracle:** committed state equals a direct fold of the sequenced log with
  rule S3 — catches pending-bookkeeping corruption even when clients agree.
- **At-most-one-winner:** for any set of concurrent `try_set_claim`s on one
  key, exactly the earliest-sequenced one reports `Accepted`; every other
  reports `Lost` with the winner's value.
- **Ack outcome totality:** every submitted op eventually produces exactly
  one outcome; pending is empty after full sync.

Harness integration wrinkle to resolve during F5 onboarding: `KernelModel.
submit` is `fn(state, op) -> state`, but claims must compute `ref_seq` at
submit time from the client's delivered cursor. Extend the model with a
`SubmitMeta(last_seen_seq: Int)` argument (the fuzz plan already anticipates
meta-record growth for the consensus kernels); counter/map models ignore it.
Also note `gen_op` should generate `(kind, key, value)` commands — `ref_seq`
is computed, never generated, or shrinking will produce unreachable ops.

## Out of scope

- **Runtime integration.** `runtime_core.Core.channels` is
  `Dict(String, map_kernel.MapState)` — map-only, and counter is likewise not
  wired in yet. Generalizing channels to a kernel-sum type is its own task;
  this port stops at kernel + tests, same as counter did. The `ClaimOutcome`
  contract and `abort_all`/`pending_values` exist so that integration needs
  no kernel changes.
- **Event/promise plumbing, GC wiring** — runtime concerns; the kernel
  exposes the data (`ClaimOutcome`, `pending_values`) they'll need.
- **Wire encoding.** `wire.gleam` codecs for the claim op envelope land with
  runtime integration, not before.

## Milestones

**C1 — Core semantics (½–1 day).** Types + `new`/`from_summary`/
`summary_entries`/`get`/`has` + `try_set_claim`/`compare_and_set_claim`/
`set_detached` + `apply_sequenced`/`apply_remote`/`ack_local`. Unit tests
written first (detached, single-client, FWW, CAS groups).
Exit: those four test groups pass, including the `>=` regression schedule.

**C2 — Lifecycle edges (½ day).** `rollback`, `apply_stashed_op`,
`abort_all`, `pending_values`; remaining unit groups.
Exit: full ported suite green; every S1–S15 row traceable to a test.

**C3 — Fuzz/property (½–1 day).** Model + properties above (harness if
available, hand-rolled otherwise). Mutation check per fuzz-plan doctrine:
plant `>=` in the acceptance rule and "forget to store the new SN on accept"
— both must be caught and shrunk.
Exit: 1000 seeded runs green; both planted bugs caught.

Total: **~2 days**, consistent with the 2/10 rating.

## Open questions

- Should `Lost` be named `AlreadyClaimed` to mirror TS terminology exactly?
  (Kept distinct here to avoid the name clash with the synchronous
  `SubmitResult.AlreadyClaimed`; revisit at review.)
- Does the runtime want `Claimed` events for *rejected local* claims (e.g.
  to update UI)? TS says no (S4); the `Lost` outcome carries enough for the
  caller. Sticking with TS unless a demo needs otherwise.
