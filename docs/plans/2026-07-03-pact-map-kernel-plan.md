# PactMap kernel port plan

**Date:** 2026-07-03
**Builds on:** `2026-07-03-dds-porting-complexity.md` (rated pact-map 4/10),
`2026-07-03-claims-kernel-plan.md` (consensus-kernel precedent), and
`2026-07-03-kernel-fuzz-harness-plan.md`.
**Reference source:** `../FluidFramework/packages/dds/pact-map/src/`
(`pactMap.ts` 440 LOC, `interfaces.ts` 90 LOC, plus `pactMap.spec.ts` 507 as the
behavioral oracle).

> **Shared prerequisite with ordered-collection.** PactMap needs the same two
> harness generalizations specified in
> **`2026-07-03-fuzz-harness-consensus-extension-plan.md`** (F6 / CO0) —
> **follow-on ops** (applying a sequenced op enqueues a new op from the applying
> client) and **membership-leave as a sequenced event**. PactMap is the *harder*
> consumer of both: its follow-on `accept` is emitted by **every** connected
> client that owes a signoff (not just one actor), and a client leaving can
> *settle* a proposal (not just re-release an item). The
> `kernel_fuzz.SequencedMeta` record already carries `connected_clients` and
> `min_sequence_number` precisely for this kernel — the data is there, the
> interpreter changes (CO0) are shared and should be built once.

## Why pact-map is this rung

Claims/CRC/ordered-collection reached consensus by *server order* alone — the
first (or earliest-covering) sequenced op wins, and every client agrees by
replaying the same log. PactMap is the first kernel whose consensus depends on
**membership**: a proposed value is not accepted until **every client that was
connected when the proposal was sequenced** has explicitly signed off (or
disconnected). This is the quorum/two-phase pattern, and it is the one new idea
the rung buys.

The value therefore lives in two phases per key:

1. **pending** — the `set` was sequenced; the proposed value is visible via
   `getPending`/`isPending` but *not* via `get`. A fixed list of
   `expectedSignoffs` (the connected quorum at set-sequencing time) must drain.
2. **accepted** — the last expected signoff arrived (an `accept` op) or the last
   expected signer left the quorum. `get` now returns it, stamped with the
   sequence number at which it settled.

Unlike claims/CRC/ordered-collection, `set` in the TS returns **`void`, not a
promise** — the caller does not await an outcome; it observes `pending`/
`accepted` events. So pact-map has **no deferred-outcome contract to port**;
its complexity is entirely the quorum bookkeeping and the two follow-on
mechanisms (accept ops, membership leaves).

## Semantics inventory (from `pactMap.ts`)

| # | Behavior | Source |
|---|---|---|
| P1 | Two ops: `set{key, value, refSeq}` (`value` may be `undefined` = delete) and `accept{key}`. `refSeq` = `deltaManager.lastSequenceNumber` at set creation, stamped on the op. | pactMap.ts:74–96,193 |
| P2 | Per-key state `Pact` = `{accepted?, pending?}` with at least one present. `accepted = {value, sequenceNumber}`, `pending = {value, expectedSignoffs: clientId[]}`. | pactMap.ts:32–69 |
| P3 | `set(key, value)`: early-exit if a pending proposal exists (only one in flight per key). Detached → `handleIncomingSet(key,value,0,0)` (via microtask). Attached → submit `set` with `refSeq`. | pactMap.ts:171 |
| P4 | `delete(key)` = `set(key, undefined)` guarded: no-op if key absent, pending, or already-accepted-undefined. | pactMap.ts:202 |
| P5 | Reads: `get` = accepted value; `getWithDetails` = accepted value + seq; `isPending`; `getPending` = pending value. | pactMap.ts:134–166 |
| P6 | `handleIncomingSet(key, value, refSeq, setSeq)`: `proposalValid = current===undefined \|\| (no pending && accepted.seq <= refSeq)`. Invalid → drop silently. | pactMap.ts:230–245 |
| P7 | Valid set: `expectedSignoffs =` all connected quorum members at set-sequencing time (includes the submitter). Write `{accepted: prior accepted, pending:{value, expectedSignoffs}}`, emit `pending`. | pactMap.ts:225,251–263 |
| P8 | If `expectedSignoffs` empty (detached only) → immediately `{accepted:{value, setSeq}}`, emit `accepted`. Else if *our* clientId ∈ signoffs → submit an `accept{key}` op. | pactMap.ts:265–283 |
| P9 | `handleIncomingAccept(key, clientId, seq)`: if no pending → ignore (already accepted, a late accept). Assert `clientId ∈ expectedSignoffs`. Remove it. If now empty → `{accepted:{pending.value, seq}}`, emit `accepted`. | pactMap.ts:286–314 |
| P10 | `handleQuorumRemoveMember(clientId)`: for every pending, remove `clientId` from its signoffs; if any empties → `{accepted:{value, clientLeaveSeq}}` (seq = `lastSequenceNumber`), emit `accepted`. | pactMap.ts:316–338 |
| P11 | Summary: `[...values.entries()]` — full pending (incl. `expectedSignoffs`) + accepted state. Load restores verbatim. | pactMap.ts:345–358 |
| P12 | reSubmit filter: drop a `set` op if the key now has a pending proposal or the op's `refSeq < accepted.seq` (stale). Else resubmit. | pactMap.ts:373–390 |
| P13 | `applyStashedOp` throws "not implemented"; `rollback` is not overridden (base default). So pact-map has **no stash and no rollback** capability. | pactMap.ts:437 |
| P14 | A newly joined client is **not** added to existing pending signoffs — the signoff set is frozen at set-sequencing time. | pactMap.ts:223 (getSignoffClients) |

## Kernel design

New module `src/watershed/pact_map_kernel.gleam`. Pure; `set`/`accept`
application takes the processing client's own id, the connected quorum, and the
settling sequence number as explicit parameters (all runtime-owned, all already
present in `SequencedMeta`).

### Types

```gleam
pub type PactMapState {
  PactMapState(values: Dict(String, Pact))
}

pub type Pact {
  /// Invariant: at least one of accepted/pending is Some.
  Pact(accepted: Option(Accepted), pending: Option(Pending))
}

pub type Accepted {
  /// value is Option(Json): None models an accepted delete (TS `undefined`).
  Accepted(value: Option(Json), sequence_number: Int)
}

pub type Pending {
  Pending(value: Option(Json), expected_signoffs: List(Int))
}

pub type PactMapOp {
  Set(key: String, value: Option(Json), ref_seq: Int)
  Accept(key: String)
}

pub type PactMapEvent {
  Pending_(key: String)
  Accepted_(key: String)
}

/// What a client should do after applying a sequenced set: it may owe an
/// accept op (P8). apply_set returns this alongside events so the runtime /
/// harness can route the follow-on accept.
pub type SetReaction {
  /// This client owes an `accept{key}` op.
  OweAccept(op: PactMapOp)
  /// Nothing to send (not in signoffs, or already settled synchronously).
  NoReaction
}
```

### API surface

| Function | Signature (abbrev.) | Notes |
|---|---|---|
| `new` | `fn() -> PactMapState` | |
| `from_summary` / `summary_entries` | full `Pact` round-trip (P11) | Pending signoffs persisted; sorted by key. |
| `get` / `get_with_details` / `is_pending` / `get_pending` | reads (P5) | `get`/`get_with_details` are accepted-only; `getPending` is the pending overlay for the *pending value* specifically. |
| `keys` | `fn(state) -> List(String)` | Sorted. |
| `set` | `fn(state, key, value, last_seen_seq) -> Option(PactMapOp)` | P3: `None` if a pending proposal exists (early-exit, nothing sent); else `Some(Set(...))` with `ref_seq = last_seen_seq`. State unchanged (non-optimistic). |
| `delete` | `fn(state, key, last_seen_seq) -> Option(PactMapOp)` | P4 guards → `set(key, None, …)`. |
| `apply_set` | `fn(state, op, seq, connected, self_id) -> #(PactMapState, List(PactMapEvent), SetReaction)` | P6–P8. `connected` = quorum at sequencing time (`SequencedMeta.connected_clients`); `self_id` = the processing client. |
| `apply_accept` | `fn(state, key, from_client, seq) -> Result(#(PactMapState, List(PactMapEvent)), KernelError)` | P9. Strict `UnexpectedAccept` if `from_client ∉ signoffs` (the TS assert). Late accept with no pending → `Ok` no-op. |
| `remove_member` | `fn(state, client_id, leave_seq) -> #(PactMapState, List(PactMapEvent))` | P10. Drains `client_id` from every pending; settles any that empty. |

Note there is no `ack_local` distinct from `apply_set`: the TS processes local
and remote sets **identically** (the `local` flag drives no branch in
set/accept handling). The harness's `ack_local` for pact-map is therefore just
`apply_set` again (the follow-on `accept` a client owes for *its own* set is
emitted the same way as for a remote set — the submitter is in its own
signoffs, P7). This is a real simplification worth stating: **pact-map has no
optimistic/local special case at all.**

`KernelError` has one case, `UnexpectedAccept(key, client, detail)` — the ported
form of the TS assert. There is no `rollback`/`apply_stashed_op` (P13).

### Design decisions (and rejected alternatives)

1. **`self_id` and `connected` are parameters, not kernel state.** Whether this
   client owes an accept (P8) depends on the *processing* client's identity, and
   the signoff set (P7) is the *connected quorum at sequencing time* — both are
   runtime/quorum facts already in `SequencedMeta` (`client_id` is the op
   author; the processing client's own id and `connected_clients` come from the
   harness). The kernel stays a pure function of its inputs. *Rejected:*
   threading a container/quorum handle into the kernel — it would drag runtime
   state into a pure module, the mistake `map_kernel`'s header warns against.
2. **`expectedSignoffs` frozen at set time (P14).** `apply_set` snapshots
   `connected` into the pending record and never consults live membership again;
   only `remove_member`/`apply_accept` drain it. A late joiner is invisible to
   an in-flight proposal. This is the crux correctness property and gets a
   dedicated test.
3. **Membership leave is a first-class kernel entry point** (`remove_member`),
   not an op. In the TS it is a quorum event with the ClientLeave sequence
   number; the kernel models it as `remove_member(client_id, leave_seq)` and the
   harness (CO0) invokes it when a disconnect sequences, so `accepted.seq`
   matches the leave's position on every client. *Rejected:* modeling leaves as
   synthetic ops in the log — `remove_member` touches *all* keys at once, unlike
   a keyed op, so a dedicated entry point is clearer and matches P10's loop.
4. **`value: Option(Json)` throughout.** `undefined` (delete) is a first-class
   accepted value, and `getPending` must distinguish "pending delete" from "no
   pending" — exactly why the TS keeps `isPending` separate. `Option(Json)`
   with an outer `Option` for pending/accepted-presence models both layers.
5. **No deferred outcome, no promise.** `set` returns only the op to send (or
   `None`); results surface as `Pending_`/`Accepted_` events. This is the one
   consensus kernel where the claims deferred-outcome contract does **not**
   apply — worth stating so a reader doesn't invent a `SetOutcome`.
6. **`accept` is strict, `set` is lenient.** An unexpected `accept` (P9 assert)
   is a routing/quorum bug → `KernelError`. An invalid `set` (P6) is an ordinary
   losing proposal → dropped silently. This mirrors the TS exactly and matches
   the house rule (crash on impossible states, drop on legitimately-lost ops).

## Follow-on ops and membership — the CO0 dependency

PactMap's convergence *cannot* be tested without both CO0 capabilities:

- **Accept ops (reactive, fan-out).** When a `set` sequences, every connected
  client in `expectedSignoffs` emits its own `accept{key}`. The harness must let
  `apply_set` (called per delivering client) enqueue that client's follow-on
  accept. This is a *fan-out* follow-on — N clients each emit — heavier than
  ordered-collection's single-actor follow-on, but the same interpreter hook.
- **Membership leave as a sequenced event.** A `Disconnect` must, at its
  sequence point, invoke `remove_member(leaver, leave_seq)` on every client so
  proposals that were only waiting on the leaver settle identically everywhere.

Because these are exactly ordered-collection's CO0 needs, **build CO0 once**
(see the ordered-collection plan) and consume it here. If CO0 lands first via
ordered-collection, pact-map's fuzz milestone has no harness cost.

## Test plan (TDD — tests first per house rules)

### 1. `test/watershed/pact_map_kernel_test.gleam` — ported unit suite

Port `pactMap.spec.ts`, translated to the pure API (hand-assigned SNs, explicit
`connected`/`self_id`, explicit `remove_member` calls for leaves):

- **Detached:** `set` with empty quorum accepts immediately at seq 0 (P8);
  `get` returns it; `getPending`/`isPending` false; delete guards (P4).
- **Single-client attached:** `set` → `apply_set` puts it pending, emits
  `pending`, and returns `OweAccept` for the sole signer; applying that
  client's `accept` empties signoffs → accepted at the accept's seq, emits
  `accepted`; `get` now returns it while before it was `undefined`.
- **Two-client acceptance:** both must accept; after one accept the value is
  still pending; after the second it is accepted at the second accept's seq;
  `getWithDetails` reports that seq.
- **Frozen signoffs (decision 2):** client C joins after a proposal goes
  pending; C's (hypothetical) accept is *not* required and an accept from C is
  an `UnexpectedAccept` error; the proposal settles on the original quorum only.
- **Competing sets:** a second `set` on a key with a pending proposal is
  dropped (`set` returns `None`); a `set` whose `refSeq < accepted.seq` is an
  invalid proposal and dropped (P6); a `set` that knows the current accepted
  value (`refSeq >= accepted.seq`) goes pending.
- **Leave-driven acceptance (P10):** a pending proposal waiting on two signers;
  one leaves via `remove_member` → still pending; the other leaves → accepted at
  the second leave's seq, emits `accepted`; a mix of one accept + one leave also
  settles.
- **Late accept (P9):** an `accept` arriving after the value already accepted is
  a tolerated no-op (not an error).
- **Delete:** `delete` proposes `undefined`, goes pending, accepts to an
  accepted-`None`; `get` returns `None`, `isPending` false; a second `delete` on
  an already-accepted-`None` key is a no-op (P4).
- **Summary:** round-trip preserves accepted (value+seq) *and* pending
  (value + expectedSignoffs); a loaded client can receive an accept/leave that
  settles a persisted pending proposal.

### 2. Fuzz/property coverage (requires CO0)

Ship `test/watershed/fuzz/pact_map_model.gleam` + `_fuzz_test.gleam` **after
CO0**. Until then, a hand-rolled multi-client property test covering set →
fan-out accept → accepted, plus leave-driven settling, in the eager/lazy style.

Model shape:
- `op` = `Set(key, value, ref_seq)` | `Accept(key)`; `ref_seq` slot filled by
  `submit` from `SubmitMeta.last_seen_seq`; a `set` on a pending key routes no
  op (`None`). `Accept` ops are *reactive* — emitted by `apply_set` per signoff
  client (CO0 fan-out), never generated directly.
- `observe` = `summary_entries` (accepted value+seq + pending value+signoffs) —
  the full state, so convergence is exact.
- `oracle` = an **independent** replay of the quorum protocol over the sequenced
  log + leave events (reimplemented in the model): fold sets into pending with
  frozen signoffs, drain on accept/leave, settle when empty. Catches a kernel
  that, e.g., forgot to freeze signoffs or settled on the wrong seq.
- Capabilities: `load_from_synced` (F2 summary round-trip); **no** `rollback`,
  **no** `apply_stashed` (P13).

Properties:
- **Convergence:** every client's per-key `{accepted, pending}` equals client
  0's after full sync (all accepts delivered, all leaves processed).
- **Oracle:** committed state equals the independent protocol replay.
- **Signoff monotonicity:** a pending proposal's `expectedSignoffs` only ever
  shrinks, and its membership is a subset of the quorum captured at set time — a
  late joiner never appears in it.
- **Settlement seq correctness:** an accepted value's `sequenceNumber` equals
  the seq of the accept/leave that emptied its signoffs — the value future sets'
  `refSeq` is compared against.

Mutation check (both caught and shrunk):
- Plant "recompute signoffs from *current* connected set on each accept" instead
  of freezing (decision 2 / P14) — diverges under a mid-proposal join.
- Plant "settle at the set's seq instead of the settling accept/leave seq"
  (P9/P10) — the oracle's settlement-seq check fails.

## Out of scope

- **Runtime integration** (kernel-sum channel type; runtime-generalization
  plan), **quorum/connection wiring** beyond the `connected`/`self_id`/leave
  parameters, **wire encoding, GC, event plumbing** — runtime concerns.
- **Rollback / stashed ops** — pact-map has neither (P13); the kernel exposes no
  such entry points.

## Milestones

**CO0 — Harness reactive-ops + membership extension (SHARED, see
ordered-collection plan).** Fan-out follow-on accepts + leave-as-sequenced-event.
Build once; if already landed for ordered-collection, pact-map's PM3 has no
harness cost.

**PM1 — Core protocol (1 day).** Types + reads + `set`/`delete` + `apply_set`
(pending/immediate-accept/reaction) + `apply_accept`. Unit tests first
(detached, single/two-client acceptance, frozen signoffs, competing sets).
Exit: those groups pass, including the frozen-signoffs error case.

**PM2 — Leaves + summary (½ day).** `remove_member`, summary round-trip, delete
edges, late-accept tolerance; remaining unit groups.
Exit: full ported suite green; every P1–P14 row traceable to a test.

**PM3 — Fuzz/property (1 day, needs CO0).** Model + oracle + properties +
mutation check.
Exit: 1000 seeded runs green; both planted bugs caught.

Total: **~2.5 days** (plus shared CO0), consistent with the 4/10 rating.

## Open questions

- Event constructor names `Pending_`/`Accepted_` collide awkwardly with the
  `Pending`/`Accepted` state records. Rename events to `WentPending`/
  `WentAccepted`? Leaning yes; settle at review.
- Does watershed want `getWithDetails` as a separate function or fold it into a
  richer `get` return? Kept separate to mirror TS and keep `get` a plain
  `Option(Json)`.
- Should `remove_member` also fire when a client that never joined the quorum
  "leaves" (idempotent no-op)? The TS filter is naturally idempotent; the kernel
  should be too — a `remove_member` for an id in no signoff list is a no-op, not
  an error. Confirmed by P10's filter semantics; noted so a test pins it.
</content>
