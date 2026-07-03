# PNCounter kernel plan — first lattice-backed (delta-CRDT) kernel

**Date:** 2026-07-03
**Builds on:** `2026-07-03-kernel-fuzz-harness-plan.md` (harness F1–F4), `2026-07-03-claims-kernel-plan.md` (op-rewriting-submit precedent), counter kernel as the shape template.
**Reference source:** *not* a Fluid TS file. Semantics come from the lattice library's PNCounter (`../lattice/packages/lattice_counters/src/lattice_counters/pn_counter.gleam`, plus `g_counter.gleam` and `lattice_core/replica_id.gleam` — consumed as the hex release `lattice_counters` 1.1.0) and behavioral parity with `src/watershed/counter_kernel.gleam` (the existing delta-based int counter, ported from Fluid's SharedCounter).

**Decisions already made:** depend on the hex release (not a path/git dep); the kernel exposes a single signed `update(amount)` entrypoint (counter parity), not an increment/decrement pair.

## Why this rung

Every existing kernel hand-rolls its reconciliation (counter: integer addition; map: pending-overlay rebase; claims: acceptance fold). PNCounter is the walking skeleton for a different foundation: back the kernel with a **state-based delta CRDT** whose `merge` is commutative, associative, and **idempotent**. The payoffs this rung is meant to prove:

1. **Ack/reconnect/duplicate paths become trivially safe.** Re-merging a delta that already applied is a no-op by construction — no double-count hazard on stash replay, resend, or ack.
2. **Summaries become mergeable.** A summary is just the sequenced CRDT state; loading is `merge(new(my_id), summary)` — no bespoke rebase.
3. **It forces the one harness gap CRDTs expose:** kernels are now *replica-identified*. The fuzz harness's `init: fn() -> state` gives clients no identity; two PN replicas sharing a `ReplicaId` silently lose increments under max-merge. Threading client identity through the harness (PN0) is a prerequisite every future lattice-backed kernel reuses.

## Semantics inventory

Lattice rows (PN) and counter-parity rows (CP):

| # | Behavior | Source |
|---|---|---|
| PN1 | `PNCounter` = two G-Counters (positive/negative); `value = Σpositive − Σnegative`. Opaque type. | pn_counter.gleam:30–31, 185–188 |
| PN2 | `merge` = pairwise **max** per replica key on each half; commutative, associative, **idempotent**. | pn_counter.gleam:197–205; g_counter.gleam:135–147 |
| PN3 | Delta mutators `try_increment_with_delta`/`try_decrement_with_delta` return `#(new_state, delta_state)` where the delta is a small PNCounter carrying the submitting replica's **cumulative** count on one half. Merging the delta ≡ merging the full state; a replica's later delta subsumes its earlier ones (monotone cumulative). | pn_counter.gleam:94–111, 157–174; g_counter.gleam:100–116 |
| PN4 | Negative `delta` → `Error(NegativeDelta(n))` from `try_*`; the non-`try_` variants **panic** (`let assert`). The kernel must route sign itself and only ever call `try_*` with non-negative magnitudes. | pn_counter.gleam:57–89, 120–152 |
| PN5 | `merge(a, b)` keeps **`a`'s `self_id`** — the re-branding idiom: `merge(new(my_id), other)` yields `other`'s counts under `my_id` identity. Needed because `self_id` is not publicly readable (`to_parts` is `@internal`). | g_counter.gleam:135–147, 239–253 |
| PN6 | JSON: versioned envelope `{"type":"pn_counter","v":1,"state":{...}}` via `to_json(counter) -> Json`; decoding is `from_json(String) -> Result(PNCounter, json.DecodeError)` — **string-in only; no embeddable `decode.Decoder(PNCounter)` is exposed**. | pn_counter.gleam:213–299 |
| PN7 | `ReplicaId` = opaque unvalidated string; structural equality; `new`/`to_string`/`to_json`/`decoder`. | lattice_core/replica_id.gleam |
| CP1 | Local update applies optimistically, appends to a FIFO pending queue, returns `#(state, events, op, message_id)`. | counter_kernel.gleam:58–76 |
| CP2 | `ack_local` pops the FIFO head, validating the op (and optionally message id) against it; empty queue / mismatch → `UnexpectedAck`. Value and events unchanged (ack transparency). | counter_kernel.gleam:95–144 |
| CP3 | `rollback` pops the **newest** pending entry (LIFO), validating op + message id; undoes its optimistic effect; emits a compensating event. | counter_kernel.gleam:159–193 |
| CP4 | `apply_stashed_op` re-applies a stashed op so it is optimistically visible and pending again. | counter_kernel.gleam:148–155 |
| CP5 | `from_summary` produces a clean state (no pending, message ids reset); `summary_*` extracts the persistable value. | counter_kernel.gleam:47–54 |
| CP6 | Events report the applied change and new value, including zero-amount local updates. | counter_kernel.gleam:60–76, 84–90 |

## Kernel design

New module `src/watershed/pn_counter_kernel.gleam`. Pure; no runtime/channel/wire integration (same scoping as claims — see Out of scope).

### Types

```gleam
import lattice_core/replica_id.{type ReplicaId}
import lattice_counters/pn_counter.{type PNCounter}

pub type PnCounterState {
  PnCounterState(
    replica_id: ReplicaId,
    /// Only sequenced (acked local + remote) deltas merged in. This is what
    /// summaries persist.
    sequenced: PNCounter,
    /// sequenced ⊔ all pending deltas — cached so reads are O(1) and so the
    /// next local delta's cumulative count is computed off the right base.
    optimistic: PNCounter,
    /// FIFO queue of in-flight local ops (oldest first), counter-style.
    pending: List(PendingDelta),
    next_pending_message_id: Int,
  )
}

pub type PendingDelta {
  PendingDelta(delta: PNCounter, amount: Int, message_id: Int)
}

/// The wire op: the CRDT delta plus the signed intent amount. The delta alone
/// would converge, but `amount` is kept for ack/rollback validation (CP2/CP3),
/// event reporting, oracle independence, and failure-dump readability.
pub type PnCounterOp {
  Update(amount: Int, delta: PNCounter)
}

pub type PnCounterEvent {
  /// `applied` is the actual observed value change (may differ from the op's
  /// nominal amount when a delta was already subsumed — then no event fires).
  Updated(applied: Int, new_value: Int)
}

pub type KernelError {
  UnexpectedAck(op: PnCounterOp, detail: String)
  UnexpectedRollback(op: PnCounterOp, detail: String)
}
```

### API surface

| Function | Signature (abbrev.) | Notes |
|---|---|---|
| `new` | `fn(ReplicaId) -> PnCounterState` | Both CRDTs `pn_counter.new(replica_id)`. |
| `value` | `fn(state) -> Int` | `pn_counter.value(state.optimistic)` — optimistic read, counter parity. |
| `sequenced_value` | `fn(state) -> Int` | Committed-only read; used by summary tests. |
| `update` | `fn(state, amount: Int) -> #(state, List(PnCounterEvent), PnCounterOp, Int)` | Sign-routes: `amount >= 0` → `try_increment_with_delta(optimistic, amount)`, else `try_decrement_with_delta(optimistic, -amount)` (PN4 — never calls a panicking variant; magnitudes are non-negative by construction so the `try_` error arm is unreachable, handled with `let assert Ok` + comment). Append `PendingDelta(delta, amount, id)`; emit `Updated(amount, new_value)` (CP6, incl. zero). |
| `apply_remote` | `fn(state, op) -> #(state, List(PnCounterEvent))` | `sequenced ⊔ delta` and `optimistic ⊔ delta` (lattice-law-safe: `(s ⊔ d) ⊔ P = (s ⊔ P) ⊔ d`). Event from optimistic value before/after; **no event when the merge was a no-op** (idempotent duplicate/subsumed delta). |
| `ack_local` / `ack_local_with_message_id` | `fn(state, op[, message_id]) -> Result(state, KernelError)` | Pop FIFO head; validate op's `amount`+`delta` (and message id in the `_with_message_id` variant) against it (CP2). Merge the delta into `sequenced` **only** — `optimistic` already contains it, so `observe` is unchanged (ack transparency). |
| `rollback` | `fn(state, op, message_id) -> Result(#(state, List(PnCounterEvent)), KernelError)` | Pop **newest** pending (CP3), validate; merge is not invertible, so recompute `optimistic = list.fold(remaining_pending, sequenced, merge)`; emit `Updated(-amount, new_value)`. |
| `apply_stashed_op` | `fn(state, op) -> #(state, List(PnCounterEvent), PnCounterOp, Int)` | Merge the op's delta into `optimistic` and re-pend it with a fresh message id, returning the **same** op. Idempotent if the delta already applied — the CRDT selling point (decision 3). |
| `summary` | `fn(state) -> Json` | `pn_counter.to_json(state.sequenced)` (PN6). Sequenced-only, like map's `sequenced_entries`. |
| `from_summary` | `fn(summary: String, ReplicaId) -> Result(PnCounterState, json.DecodeError)` | `pn_counter.from_json` then re-brand: `merge(pn_counter.new(replica_id), parsed)` (PN5). Pending empty, `optimistic = sequenced`, ids reset (CP5). |
| `check_cache_coherence` | `fn(state) -> Result(Nil, String)` | Test-facing invariant: cached `optimistic` equals `fold(merge, sequenced, pending deltas)` recomputed. Wired as the fuzz model's `check` hook. |

### Design decisions (and rejected alternatives)

1. **Cached `optimistic` alongside `sequenced`, coherence-checked.** Reads are O(1) and — more importantly — `update` must compute the next delta's *cumulative* count off `sequenced ⊔ pending`, so that base is needed on every submit anyway. *Rejected:* recompute-on-read (O(pending × replicas) per read, and still needs the same fold at submit time); *rejected:* keeping only `optimistic` (summaries must exclude pending, ack must merge into a committed base, and AddClient joins would leak pending state). The redundancy is disciplined by `check_cache_coherence` running as the fuzz `check` hook after every command.
2. **Ops carry `amount` *and* `delta`.** *Rejected — amount-only ops:* `apply_remote` would have to use add-semantics, forfeiting idempotence and the entire reason to use a CRDT; it would just be `counter_kernel` with extra steps. *Rejected — delta-only ops:* the fuzz oracle could no longer independently sum intents (recovering an amount from a cumulative delta requires per-replica bookkeeping — i.e., reimplementing the CRDT, no longer independent); ack/rollback lose the counter-parity amount validation; JSON failure dumps become unreadable dictionaries. The delta is authoritative for state; the amount is metadata for validation/events/oracle.
3. **Merge-based `apply_stashed_op`, not re-increment.** Counter routes stashed ops back through `increment` (CP4), which double-counts if the op had in fact already been sequenced into the summary the client reloaded from. Merging the op's cumulative delta is idempotent under exactly that duplication — this is the headline safety property of the rung, and it gets both a dedicated unit test and a fuzz path. Consequence for the fuzz model: a *generated* stashed op has no valid delta, so the model fabricates the next cumulative delta via the kernel's update path and must hand the **rewritten** op back to the harness for routing — which existing `Capabilities.apply_stashed: fn(state, op) -> state` cannot express. See harness change H2; without it, other clients would receive a delta-less op and diverge.
4. **`from_summary` re-brands via `merge(new(my_id), parsed)` (PN5).** The parsed summary carries the *summarizer's* `self_id`; a joining client that kept it would submit future deltas under the summarizer's replica key and collide. `PNCounter` is opaque with no public `self_id` accessor/setter, so the merge idiom (g_counter.merge keeps `a`'s self_id) is the only clean route — and it doubles as a demonstration of merge-as-load. *Rejected:* asking lattice for a `with_replica_id` setter (works, but an upstream API change shouldn't gate the walking skeleton).
5. **Single signed `update(amount)`; sign routed inside the kernel; only `try_*` lattice calls.** Counter-parity API (`increment(-3)` works there), and it fences lattice's panicking non-`try_` variants (PN4) entirely out of reach. *Rejected:* separate `increment`/`decrement` with non-negative contracts — pushes the panic hazard to callers and diverges from counter's shape for no benefit. (Decision confirmed with the user.)
6. **`apply_remote` is event-silent on no-op merges; local `update` always emits.** A duplicate/subsumed remote delta changes nothing — emitting `Updated(0, v)` for every idempotent re-merge is noise, and "applied change" is the honest event payload for max-merge. Local `update` keeps counter's emit-even-on-zero behavior (CP6). Flagged in Open questions since it's the one deliberate divergence from counter's event contract.
7. **`replica_id` kept as an explicit state field.** The kernel never strictly needs to read it back (lattice mutators use the internal `self_id`), but it is unrecoverable from the opaque `PNCounter`, and tests/debugging want to assert identity. Cheap, explicit, kept.

## Harness extension: client identity threading (PN0)

**The gap (verified):** `kernel_fuzz.KernelModel.init` is `fn() -> state` (kernel_fuzz.gleam:78), called from `new_sim` (kernel_fuzz.gleam:139–149) identically for every client, and `Capabilities.load_from_synced` is `fn(state) -> state` (kernel_fuzz.gleam:68), called from `add_client` (kernel_fuzz.gleam:470–496) on client 0's state with no identity for the joiner. A PN model built this way would give every client the same `ReplicaId`; concurrent `+3` and `+5` from two clients max-merge to one replica key and lose an increment — and `load_from_synced` without a joiner identity would clone client 0's replica id into the new client. Precedent for this kind of surgical harness generalization: `SubmitMeta` threading into `submit` (commit ff3eb06) and `ack_preserves_view` + Option-returning submit (c15bde8).

### H1 — thread client identity into `init` and `load_from_synced`

```gleam
// kernel_fuzz.gleam — KernelModel
init: fn() -> state,                              // before
init: fn(Int) -> state,                           // after: the client's index,
                                                  // stable for the sim's lifetime

// kernel_fuzz.gleam — Capabilities
load_from_synced: Option(fn(state) -> state),     // before
load_from_synced: Option(fn(state, Int) -> state) // after: 2nd arg = the NEW
                                                  // client's identity
```

Interpreter changes:
- `new_sim`: build clients with `list.index_map` so each gets `model.init(i)`.
- `add_client`: the joiner's identity is `list.length(sim.clients)` (indices are append-only and never reused, so it is fresh and unique); pass it as `load_from_synced(client0.state, new_id)`.

Client identity is the harness's `Int` index; the PN model maps it to `replica_id.new("client-" <> int.to_string(id))`. Existing models ignore the new parameters.

### H2 — let `apply_stashed` rewrite the routed op

```gleam
// kernel_fuzz.gleam — Capabilities
apply_stashed: Option(fn(state, op) -> state),        // before
apply_stashed: Option(fn(state, op) -> #(state, op)), // after: routed op may be
                                                      // rewritten, mirroring submit
```

Interpreter change: `stashed_op` (kernel_fuzz.gleam:564–594) currently applies the raw generated op and routes it verbatim to inbox/resend (:579–585); after H2 it routes the **returned** op. Rationale (decision 3): `rollback_op` already rolls back the *submit-rewritten* op (kernel_fuzz.gleam:544–551), but `StashedOp` routes the generated op unchanged, which is unusable for any kernel whose wire ops carry submit-time-computed content (PN deltas today; any future lattice kernel tomorrow).

### Mechanical updates (H1 + H2)

| File | Change |
|---|---|
| `test/watershed/fuzz/kernel_fuzz.gleam` | The type + `new_sim`/`add_client`/`stashed_op` changes above; doc-comment updates. |
| `test/watershed/fuzz/counter_model.gleam` | `init: fn(_) { counter_kernel.new() }` (:113); `load_from_synced(state, _id)` (:106); `apply_stashed` returns `#(state, op)` (:101–104, same op). |
| `test/watershed/fuzz/map_model.gleam` | `init` (:192); `load_from_synced` (:185). |
| `test/watershed/fuzz/claims_model.gleam` | `init` (:190); `load_from_synced` (:183). |
| `test/watershed/fuzz/kernel_fuzz_test.gleam` | toy `sum_model` `init` (:27). |
| `test/watershed/fuzz/add_client_test.gleam` | toy `init` (:33); three `load_from_synced` closures gain `_id` (:47, :60ish, :72). |
| `test/watershed/fuzz/disconnect_test.gleam` | toy `init` (:27). |
| `test/watershed/fuzz/rollback_stash_test.gleam` | toy `init` (:40). |

(`model_add_client_test.gleam`, `fuzz_replay_test.gleam`, `script_gen.gleam` construct no `KernelModel` literals — no changes.)

### New harness tests (PN0 exit gate)

- `init` receives distinct indices 0..n−1 (toy model records its argument; assert per-client).
- `AddClient` passes a fresh identity (`== list.length(clients)` before the join) to `load_from_synced`.
- `StashedOp` routes the **rewritten** op (toy model rewrites; assert the inbox op differs from the generated one and convergence uses the rewrite).

## Dependency

Add to `gleam.toml` `[dependencies]` (kernel is production `src/` code, not dev-only):

```toml
lattice_counters = ">= 1.1.0 and < 2.0.0"
```

Hex-published, pure Gleam, targets erlang+javascript, `gleam >= 1.7.0`, stdlib/gleam_json ranges compatible with watershed's. Pulls `lattice_core` transitively (for `replica_id`). `manifest.toml` regenerates via `gleam deps download`.

## Test plan (TDD — tests first per house rules)

### 1. `test/watershed/pn_counter_kernel_test.gleam` — unit suite

Mirrors `counter_kernel_test.gleam` structure (helper `ack`/`rollback` unwrappers, `expect_unexpected_*`).

**Counter-parity groups** (each maps to a CP row):
- new state is zero; empty pending; `sequenced_value == value == 0`.
- `update` optimistic visibility: positive, negative, zero amounts; op carries the amount and a delta; message ids increment; `Updated(amount, new_value)` events.
- `apply_remote` from another replica applies its delta and emits the applied diff; `pending` untouched.
- Cross-replica concurrent updates converge: A `+10`, B `+20`, exchange ops in both orders → both read 30; mixed-sign: A `+10`, B `−4` → 6.
- `ack_local` FIFO: value unchanged, head popped, out-of-order ack → `UnexpectedAck`; `ack_local_with_message_id` metadata validation; ack on empty pending → error.
- `rollback` newest-only, metadata validation, rollback across interleaved remote ops preserves the remote contribution (the `optimistic` recompute test), rollback on empty → error, compensating `Updated(-amount, …)` event.

**CRDT-specific groups** (each maps to a PN row):
- **Idempotent duplicate delta (PN2/decision 3):** `apply_remote` the same op twice → value unchanged after the second, and no second event; `apply_stashed_op` of an op whose delta is already in `optimistic` → value unchanged, but op re-pends and returns the same op.
- **Cumulative subsumption (PN3):** replica A's second delta merged *without* its first still yields A's full contribution — pins the cumulative-delta contract the oracle relies on.
- **Sign routing (PN4):** `update(-5)` decrements via the negative half; alternating signs keep both halves' cumulative counts independent (assert via `summary` JSON structure).
- **Summary round-trip preserving per-replica structure (PN5/PN6/CP5):** A applies local `+3`, acks it, applies remote `+4` from B; `summary` → `from_summary(json, replica_id.new("c"))` gives value 7 with empty pending; the loaded client's subsequent `+1` lands under `"c"`'s key, not A's or B's (assert by summarizing again and inspecting `counts` keys) — the re-branding test, which also pins lattice's keep-`a`'s-id merge behavior.
- **Summary excludes pending:** un-acked local delta absent from `summary`; `from_summary` of it + late `apply_remote` of that same op still converges (mergeable-summary property).
- **`check_cache_coherence`** holds across a scripted update/remote/ack/rollback sequence.

### 2. Fuzz: `test/watershed/fuzz/pn_counter_model.gleam` + `test/watershed/pn_counter_fuzz_test.gleam`

Model shape (parallels `counter_model.gleam`; differences flagged):

- **Op type** — claims-style slot-filling command:
  ```gleam
  pub type PnCommand {
    PnCommand(amount: Int, delta: Option(PNCounter))
  }
  ```
  `gen_op`: amounts in `[-10, 10]` via `n % 21 - 10` (counter parity, shrink-friendly), `delta: None`.
- **`init`** (H1): `fn(id) { pn_counter_kernel.new(replica_id.new("client-" <> int.to_string(id))) }` — *the* difference from counter.
- **`submit`**: calls `update(state, amount)`; returns `#(state, Some(PnCommand(amount, Some(delta))))` — an op **rewrite** (claims precedent). Never `None`.
- **`apply_remote` / `ack_local`**: unwrap `delta` (a `None` here is a model wiring bug — fail loudly); map `KernelError` to its `detail` string like counter_model.gleam:62–72.
- **`observe`**: `pn_counter_kernel.value` (an `Int`, so `canonicalize: None`).
- **`ack_preserves_view: True`** (optimistic kernel; ack merges into `sequenced` only).
- **`check: Some(check_cache_coherence)`** — runs after *every* command on *every* client, the strongest per-step probe in the suite.
- **Oracle (independent — never touches `merge`):** sum of sequenced ops' intent **amounts**: `list.fold(log, 0, fn(t, e) { t + { e.1 }.amount })`. Soundness argument (goes in the module doc): merged value = Σ over replicas of that replica's max cumulative = Σ of per-replica amount sums, **provided** every sequenced delta's cumulative is monotone per replica and computed off a base containing all of that replica's prior sequenced-or-pending deltas. That holds by construction: `submit`/`apply_stashed` compute deltas off `optimistic` inside the kernel, per-client op order is FIFO through inbox → resend → log, and rolled-back ops never reach the log (and the subsequent recompute rebases the next cumulative correctly).
- **Capabilities — all four:**
  - `load_from_synced` (H1 signature): `summary → json string → from_summary` real round-trip with `replica_id.new("client-" <> int.to_string(id))` — exercises PN6.
  - `oracle` as above.
  - `rollback`: like counter_model.gleam:88–97 — read newest pending's message id from `state.pending`, call kernel `rollback`, leave state untouched on mismatch so regressions surface as convergence failures, not harness panics.
  - `apply_stashed` (H2 signature): fabricate the missing delta through the kernel — call `update(state, amount)` to get the next cumulative delta computed off `optimistic`, then return `#(state, PnCommand(amount, Some(delta)))`. State-identical to a genuine merge-based stash of that delta, and keeps the routed op valid for `apply_remote`/`ack_local` on every peer. The kernel's merge-based `apply_stashed_op` duplicate-idempotence is pinned by unit tests; fuzz exercises the full stash **routing** path.
- **`op_to_json` / `op_decoder`:** `{"amount": Int, "delta": null | String}` where the delta is **double-encoded** — `json.string(json.to_string(pn_counter.to_json(d)))` out; back via `decode.string |> decode.then(pn_counter.from_json ...)` — because lattice exposes only string-based `from_json`, no composable `decode.Decoder(PNCounter)` (PN6; upstream issue to be filed). Dumped scripts mostly contain pre-submit ops (`delta: null`), but replayed `StashedOp`/`RollbackOp` fixtures must round-trip totally.
- **Fuzz test file:** mirrors `counter_fuzz_test.gleam` — `client_count = 3`, weights = `Weights(..script_gen.default_weights(), rollback_op: 8, stashed_op: 8)` (opting in; defaults are 0), `kernel_fuzz.run(model, config_from_env(), 3, script_gen.script_generator(model.gen_op, 3, weights()))`.

### 3. Mutation checks (PN3 exit criteria — plant, observe catch, revert)

| # | Planted mutation | Caught by |
|---|---|---|
| M1 | `ack_local` pops pending but **skips merging the delta into `sequenced`** | `check` hook immediately (cached `optimistic` ⊋ recomputed); independently, the next `AddClient` joins from an under-counted summary → convergence failure at `Synchronize`. |
| M2 | `apply_remote` merges into `sequenced` but **not `optimistic`** | `check` hook immediately; also convergence (stale reads) at `Synchronize`. |
| M3 | `rollback` pops pending but **skips the `optimistic` recompute** | Convergence at next `Synchronize` *and* oracle mismatch; `check` hook too. |
| M4 | Delta computed off `sequenced` instead of `optimistic` (per-op count, not cumulative — breaks PN3) | Oracle mismatch at `Synchronize`: two in-flight ops from one client max-merge to only the larger, so merged value < sum of amounts. |
| M5 | `init` ignores the client id (constant replica id — precisely the pre-PN0 world) | Oracle mismatch/convergence: concurrent ops from two clients collide under max-merge. Also add as a planted-bug harness test in the style of `add_client_test.gleam`'s `model_with_buggy_load_from_synced` (:67) — the proof H1 was necessary. |

M1–M3 double as justification for shipping the `check` hook rather than relying on convergence alone: the hook catches them one command after the fault with a per-client message, so shrunk scripts stay minimal.

## Out of scope

- **Runtime/channel/wire integration** — no `channel.gleam`/`runtime_core` wiring, no wire op envelope, no summary-blob plumbing. Same scoping as claims; a follow-on plan integrates lattice kernels once the runtime-generalization work lands.
- **Other lattice types** (maps, registers, sets) — this is deliberately the walking skeleton; the harness changes (H1/H2) are the reusable part.
- **Upstream lattice changes** — no `decode.Decoder(PNCounter)`, no `with_replica_id`; tracked as a lattice issue, worked around here.
- **Garbage-collecting replica entries** for departed clients (G-Counter state grows with replica count; irrelevant at kernel scope).

## Milestones

**PN0 — Harness identity threading + stash rewrite (½ day).**
H1 + H2 signature changes in `kernel_fuzz.gleam`; mechanical updates to the 8 files listed; new harness tests (distinct init ids, fresh AddClient id, stash-rewrite routing).
*Exit:* `just test` green (all existing models/fixtures unaffected — existing fixtures in `test/fixtures/fuzz_failures/` still replay); the three new harness tests pass.

**PN1 — Core kernel semantics (1 day).**
Add `lattice_counters` dep. `new`/`value`/`sequenced_value`/`update`/`apply_remote` + events + `check_cache_coherence`. Unit tests first: parity groups 1–4 plus idempotent-duplicate, cumulative-subsumption, sign-routing.
*Exit:* those unit groups green; `just build` succeeds on **both targets** (first kernel with an external dep — the JS-target build of `src/` proves lattice compiles there; the test suite itself is erlang-only today).

**PN2 — Lifecycle edges (½ day).**
`ack_local`(+`_with_message_id`)/`rollback`/`apply_stashed_op`/`summary`/`from_summary`. Remaining unit groups (FIFO ack, LIFO rollback + recompute, stash idempotence, summary round-trip/re-branding/excludes-pending).
*Exit:* full unit suite green; every PN/CP row traceable to a named test.

**PN3 — Fuzz model + mutations (1 day).**
`pn_counter_model.gleam` + `pn_counter_fuzz_test.gleam`; oracle soundness note in module doc; run M1–M5, confirm each is caught and shrinks to a readable fixture, revert.
*Exit:* `just fuzz` (5000 iterations) green; all five mutations caught; a captured PN failure fixture replays via `fuzz_replay_test` conventions.

Total: **~3 days.**

## Files to create

- `src/watershed/pn_counter_kernel.gleam`
- `test/watershed/pn_counter_kernel_test.gleam`
- `test/watershed/fuzz/pn_counter_model.gleam`
- `test/watershed/pn_counter_fuzz_test.gleam`

## Files to modify

- `gleam.toml` (+ `manifest.toml` via `gleam deps download`)
- `test/watershed/fuzz/kernel_fuzz.gleam` (H1/H2)
- `test/watershed/fuzz/counter_model.gleam`, `map_model.gleam`, `claims_model.gleam` (mechanical)
- `test/watershed/fuzz/kernel_fuzz_test.gleam`, `add_client_test.gleam`, `disconnect_test.gleam`, `rollback_stash_test.gleam` (mechanical + new PN0 tests)

## Verification

```sh
gleam deps download                            # resolve lattice_counters from hex
just test                                      # fast profile: unit + 200-iteration fuzz
just fuzz                                      # deep profile: FUZZ_ITERATIONS=5000
FUZZ_ITERATIONS=1000 FUZZ_SEED=42 gleam test   # pinned reproducible run
just build                                     # erlang + javascript targets
just ci                                        # format + lint + test + build
```

Mutation-check verification: plant each of M1–M5, run `just test`, confirm the failure fixture lands in `test/fixtures/fuzz_failures/` and names the expected check (hook / convergence / oracle), revert, confirm green. Keep one interesting shrunk script as a permanent regression via `fuzz_replay_test`.

## Open questions

- **Event silence on no-op remote merges (decision 6)** diverges from counter's always-emit contract. Settle at review whether runtime event consumers would rather see `Updated(0, v)` for duplicates.
- **Model op `delta: Option(PNCounter)` vs a placeholder empty delta.** `Option` is honest (pre-submit ops genuinely have none) but adds unwrap arms; claims used a `0` placeholder for `ref_seq`. Leaning `Option` since a bogus placeholder *delta* is a live footgun under merge, unlike a bogus int.
- **Upstream lattice improvements** (non-blocking; issue to be filed on tylerbutler/lattice): expose embeddable `decode.Decoder` values (e.g. `pn_counter.decoder()`), and possibly a `with_replica_id` re-brand helper so `from_summary` doesn't lean on merge's keep-`a`'s-id detail (documented at g_counter.gleam:145, but pinned by a watershed unit test either way).
- **Replica-id naming scheme** `"client-" <> index` lives in the fuzz model only; runtime integration will need real client ids (`ids.gleam`). No kernel change required — `ReplicaId` is an opaque string.
