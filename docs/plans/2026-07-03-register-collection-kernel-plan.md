# ConsensusRegisterCollection kernel port plan

**Date:** 2026-07-03
**Builds on:** `2026-07-03-dds-porting-complexity.md` (rated register-collection
3/10), `2026-07-03-claims-kernel-plan.md` (established the non-optimistic
deferred-outcome kernel shape this reuses), and
`2026-07-03-kernel-fuzz-harness-plan.md` (F5: each new kernel ships with a fuzz
model).
**Reference source:** `../FluidFramework/packages/dds/register-collection/src/`
(`consensusRegisterCollection.ts` 442 LOC, `interfaces.ts` 88 LOC, plus
`consensusRegisterCollection.spec.ts` as the behavioral oracle).

## Why register-collection is the next rung

Claims introduced first-writer-wins with per-key sequence-number CAS and the
**deferred outcome** (a local write's result is unknowable until its op
round-trips). ConsensusRegisterCollection (CRC) is the next rung because it
reuses that exact shape but adds **concurrent-version retention** and **two read
policies** — the one genuinely new idea here.

CRC is, like claims, **non-optimistic**: `read`/`readVersions`/`keys` return
committed state only; a local write is invisible until its op sequences. So
there is again no pending-overlay/rebase machinery. The port is essentially
"claims, but the acceptance rule keeps losers around as versions, and the CAS
comparison is `>=` not `==`."

Three properties define the rung, contrasted with claims:

1. **Every sequenced write is applied — winners *and* losers.** In claims a
   rejected op is dropped (state unchanged). In CRC a losing write does not
   update the linearizable `atomic` slot but *still* appends itself to the
   key's `versions` list. Reads then pick between them by policy.
2. **Atomic CAS uses `>=`, not `==`.** A write wins the atomic slot iff it was
   made with knowledge of the current atomic version
   (`refSeq >= atomic.sequenceNumber`) — the *earliest* op that supersedes the
   prior version wins, and every client agrees because they replay the same
   sequenced order. Claims' exact `==` was a write-once guard; CRC's `>=` is a
   linearizable register. (See design decision 2 for why this difference is
   real and observable, unlike claims' `>=`-vs-`==` which was not.)
3. **Version pruning is history GC.** When a write arrives whose author already
   knew a version (`refSeq >= version.sequenceNumber`), that version is dropped
   from the front of the list before the new one is appended. This keeps
   `versions` bounded to genuinely-concurrent values.

The deferred outcome is simpler than claims': a write resolves to a bare
`isWinner: Bool` (did it win the atomic slot?), derivable purely from applying
the op at ack time. No pending value needs carrying, because the op already
carries its own value — which lets the kernel drop pending state entirely (see
design decision 4).

## Semantics inventory (from `consensusRegisterCollection.ts`)

| # | Behavior | Source |
|---|---|---|
| R1 | One op kind: `write{key, value, refSeq}`. `refSeq` = `deltaManager.lastSequenceNumber` at op creation, stamped on the op (not the envelope's referenceSequenceNumber, which resubmit rewrites). | crc.ts:167 |
| R2 | Committed per-key state = `{atomic: {value, seq}, versions: [{value, seq}, …]}`. Every key with data has ≥1 version. | crc.ts:32–49 |
| R3 | `processInboundWrite(key, value, refSeq, seq)` runs identically for local and remote. `isWinner = data===undefined \|\| refSeq >= atomic.seq`. | crc.ts:352,362 |
| R4 | Winner: overwrite `atomic = {value, seq}` (creating the register with empty versions if new). Loser: leave atomic; assert data exists. | crc.ts:363–376 |
| R5 | Prune: `while versions[0].seq <= refSeq: versions.shift()` — drop versions the writer already knew. | crc.ts:379–381 |
| R6 | Then always push `{value, seq}` onto versions (winner and loser alike). | crc.ts:383,400 |
| R7 | Events: `atomicChanged(key, value, local)` iff winner; `versionChanged(key, value, local)` always. Emitted after state mutation. | crc.ts:403–406 |
| R8 | `read(key, Atomic)` = `atomic.value`. `read(key, LWW)` = last element of versions. Default policy Atomic. | crc.ts:225–238 |
| R9 | `readVersions(key)` = all version values (or undefined). `keys()` = all keys. No delete: keys only grow. | crc.ts:240–247 |
| R10 | `write`: detached → `processInboundWrite(key, value, 0, 0)`, resolve `true` synchronously. Attached → submit op, resolve `isWinner` on ack. | crc.ts:156–217 |
| R11 | Local ack: run `processInboundWrite` (same as remote), then resolve the pending promise with `isWinner`. | crc.ts:311–329 |
| R12 | Rollback: no state to undo (nothing mutated until ack); resolve the pending promise `false`. | crc.ts:423–432 |
| R13 | Stashed op: resubmit the original op verbatim (refSeq preserved), assign a fresh pending id. | crc.ts:434–441 |
| R14 | Summary: the whole `data` map — atomic + every version, **with sequence numbers** (CAS/pruning must keep working after load). Loaded state has no pending. Old "Shared" register values rejected on load. | crc.ts:249–274 |
| R15 | Detached invariant: refSeq and seq are both 0 when unattached. Monotonicity: pushed seq ≥ last version's seq. | crc.ts:386–397 |

## Kernel design

New module `src/watershed/register_collection_kernel.gleam`, house style of
`claims_kernel.gleam`: pure, no process, every entry point returns new state +
events + outbound op / outcome. It is deliberately close to `claims_kernel` so a
reader who knows claims can diff the two.

### Types

```gleam
pub type RegisterState {
  RegisterState(registers: Dict(String, Register))
}

pub type Register {
  /// atomic = linearizable winner; versions = all still-concurrent values in
  /// submit (sequence) order, front = oldest. Invariant: versions non-empty.
  Register(atomic: VersionedValue, versions: List(VersionedValue))
}

pub type VersionedValue {
  VersionedValue(value: Json, sequence_number: Int)
}

/// The one write op on the wire (R1). `ref_seq` is the author's last-seen
/// sequence number at creation time, computed by the runtime, never generated.
pub type WriteOp {
  Write(key: String, value: Json, ref_seq: Int)
}

pub type RegisterEvent {
  /// Winner only — the atomic (linearizable) value changed (R7).
  AtomicChanged(key: String, value: Json, local: Bool)
  /// Every accepted-into-versions write (R7).
  VersionChanged(key: String, value: Json, local: Bool)
}

/// Which value `read` returns (R8). Atomic is the default, matching TS.
pub type ReadPolicy {
  Atomic
  Lww
}
```

Note there is **no `pending` field and no `KernelError`**. See design
decision 4.

### API surface

| Function | Signature (abbrev.) | Notes |
|---|---|---|
| `new` | `fn() -> RegisterState` | |
| `from_summary` | `fn(List(#(String, Register))) -> RegisterState` | R14 round-trip; atomic + versions + seqs restored. |
| `summary_registers` | `fn(RegisterState) -> List(#(String, Register))` | Sorted by key for stable snapshots. |
| `read` | `fn(state, key, ReadPolicy) -> Option(Json)` | R8. Committed-only (doc-comment says so loudly, à la claims). |
| `read_versions` | `fn(state, key) -> Option(List(Json))` | R9. |
| `keys` | `fn(state) -> List(String)` | Sorted. |
| `write` | `fn(state, key, value, last_seen_seq) -> WriteOp` | R10 attached path: build the op with `ref_seq = last_seen_seq`. State unchanged (non-optimistic). Multiple concurrent writes to a key are legal — no per-key guard, unlike claims. |
| `write_detached` | `fn(state, key, value) -> #(RegisterState, List(RegisterEvent))` | R10 detached: `apply_write(key, value, 0, 0)`. |
| `apply_remote` | `fn(state, op, seq) -> #(RegisterState, List(RegisterEvent))` | R3–R7. |
| `ack_local` | `fn(state, op, seq) -> #(RegisterState, List(RegisterEvent), Bool)` | R11: identical application to remote, plus returns `isWinner` as the deferred outcome. Total (never errors) — see decision 4. |
| `rollback` | `fn(state, op) -> #(RegisterState, Bool)` | R12: state unchanged, outcome `False`. |
| `apply_stashed_op` | `fn(state, op) -> #(RegisterState, WriteOp)` | R13: state unchanged, return op verbatim to resubmit. |

Shared internal `apply_write(state, key, value, ref_seq, seq) -> #(RegisterState,
Bool, List(RegisterEvent))` implements R3–R7 once; `apply_remote`, `ack_local`,
and `write_detached` all call it, so "local and remote application are
identical" is true in code, not just review — exactly as `apply_sequenced` did
for claims.

### Design decisions (and rejected alternatives)

1. **Reads committed-only, non-optimistic** — inherited wholesale from claims.
   The doc-comment must shout it, because the tempting map-style port (show the
   local write immediately) is wrong and the test suite is built to catch it.
2. **`>=` atomic CAS is observable here, so it is pinned by the fuzz model** (a
   contrast worth stating, because claims' analogous choice was *not*). In a
   single-DDS fuzz model a client's `ref_seq` is its own delivered cursor,
   which *can* equal a key's atomic sequence number (deliver the winning write,
   then write again). So planting `>` for `>=` makes a non-concurrent rewrite
   wrongly lose, and the model diverges. Claims' `>=`-vs-`==` was unreachable in
   a single-DDS model and needed a hand-written unit test; CRC's boundary does
   not — but port a unit test for it anyway for documentation.
3. **Both winners and losers append a version.** The most likely porting bug is
   "only push a version on winners" (conflating atomic with versions). R6 is
   explicit that the push is unconditional; the version-pruning + LWW-read tests
   pin it.
4. **No pending state; `ack_local` is total.** Claims needed `pending` for its
   one-per-key guard, to carry the submitted value into the `Accepted` outcome,
   and for handle-scanning GC. CRC needs none of these: concurrent writes to a
   key are *allowed* (no guard), the outcome is a bare `isWinner` the ack
   recomputes, and the op is self-describing so in-flight-value GC reads the
   runtime's resend queue, not kernel state. Because there is no per-key
   invariant a stray ack could corrupt, a total `ack_local` cannot mask a
   routing bug the way claims' could — so the strictness claims bought with a
   `KernelError` buys nothing here, and the simpler total signature wins.
   *Rejected:* mirroring claims' `pending` dict keyed by a local write id purely
   for symmetry — it would be dead bookkeeping.
5. **Values are `Json`**, matching claims/map. `null` is a legitimate value; the
   old "Shared" wrapper (R14's rejected-on-load case) is a pre-0.17 artifact
   watershed never emits, so `from_summary` simply takes plain values.
6. **`versions` is a Gleam list, pruned at the front, appended at the back.**
   Front pruning is `list.drop_while`; the append is O(n) but version lists are
   tiny (bounded by concurrency width). No deque needed.

## Test plan (TDD — tests first per house rules)

### 1. `test/watershed/register_collection_kernel_test.gleam` — ported unit suite

Port `consensusRegisterCollection.spec.ts` describe-by-describe, translated to
the pure API (mock-runtime "process messages" becomes explicit
`apply_remote`/`ack_local` with hand-assigned SNs):

- **Detached:** read empty → None; `write_detached` visible immediately at seq
  0 via both policies; summary round-trips the seq-0 register and a subsequent
  attached write against it CASes on the persisted seq.
- **Single client:** `write` produces an op but `read` still None
  (non-optimistic — the test that catches a map-style port) → `ack_local` with
  SN → `isWinner = True`, value visible via Atomic and LWW, `AtomicChanged` +
  `VersionChanged` emitted.
- **Concurrent writes / atomic linearizability:** two clients write a key with
  overlapping refSeqs; the earlier-sequenced write that knew the prior atomic
  wins the atomic slot on every client; the later stale write (refSeq < atomic
  seq) loses atomic but appends a version; Atomic read agrees across clients,
  LWW read returns the last-sequenced value. Include the exact
  three-write schedule from the spec's atomic-vs-LWW divergence test.
- **Version retention + pruning:** N concurrent writers produce N versions;
  a write whose refSeq covers earlier versions prunes them (R5) before pushing;
  `readVersions` matches the expected surviving set; the `>=` prune boundary is
  exercised at equality (`version.seq == refSeq` prunes).
- **`>=` atomic boundary (decision 2):** a rewrite with `refSeq == atomic.seq`
  wins (knew the exact current value); `refSeq < atomic.seq` loses. Port even
  though the fuzz model also covers it.
- **Rollback / stash:** rollback leaves state untouched and outcome `False`;
  stashed op returns byte-identical (same refSeq) and, once sequenced, applies
  normally.
- **Summary:** round-trip preserves atomic, every version, and all sequence
  numbers; a load followed by a concurrent write prunes/CASes using persisted
  seqs; JSON null round-trips.

### 2. Fuzz/property coverage

CRC needs **no harness extension** — it is non-optimistic, emits no follow-on
ops, and is membership-independent, so it plugs into the existing F1–F4 harness
exactly like claims. Ship `test/watershed/fuzz/register_collection_model.gleam`
+ a `_fuzz_test.gleam` in the same PR.

Model shape (mirrors `claims_model.gleam`):
- `op` = `WriteCommand(key, value, ref_seq)` with `ref_seq` a slot `gen_op`
  leaves 0 and `submit` fills from `SubmitMeta.last_seen_seq` via
  `register_collection_kernel.write`. `submit` always routes an op (no
  suppression case — every write is legal), so `ack_preserves_view` is `False`
  (acking a winning write first makes it visible; a legitimate change).
- `observe` = `summary_registers` (atomic + versions + seqs) — the full
  committed state, so convergence is exact.
- `oracle` = an **independent** fold of `apply_write` over the sequenced log,
  reimplemented in the model (NOT delegated to the kernel), so a kernel bug in
  pruning or the version push diverges from it at the next `Synchronize`.
- Capabilities: `load_from_synced` = summary round-trip (F2); `rollback`
  supplied (F3, state-unchanged); `apply_stashed` supplied (F3).

Properties:
- **Convergence:** every client's full register state (atomic + versions +
  seqs) equals client 0's after full delivery.
- **Oracle:** committed state equals the independent fold — catches pruning /
  version-push corruption even when clients agree.
- **Atomic linearizability:** the atomic value for each key equals the value of
  the earliest-sequenced write whose refSeq covered the then-current atomic —
  computable from the log independently of the kernel.
- **Version boundedness:** after full sync, every key's `versions` contains
  exactly the values not yet superseded by a later-refSeq write (no unbounded
  growth) — the pruning invariant.

Mutation check per fuzz-plan doctrine, both must be caught and shrunk:
- Plant `>` for `>=` in the atomic CAS (decision 2 says this is now reachable).
- Plant "only push a version on winners" (drop the unconditional push, R6).

## Out of scope

- **Runtime integration.** Same boundary as counter/claims: `runtime_core`'s
  channel dict is map-only; wiring CRC in needs the kernel-sum-type
  generalization (its own task, see `2026-07-03-runtime-generalization-plan.md`).
  The `isWinner` outcome and event list exist so integration needs no kernel
  change.
- **Wire encoding, GC wiring, event/promise plumbing** — runtime concerns.

## Milestones

**RC1 — Core semantics (½–1 day).** Types + `new`/`from_summary`/
`summary_registers`/`read`/`read_versions`/`keys` + `write`/`write_detached` +
`apply_write`/`apply_remote`/`ack_local`. Unit tests first (detached,
single-client, concurrent/atomic, versions/pruning, `>=` boundary).
Exit: those groups pass, including the atomic-vs-LWW divergence schedule.

**RC2 — Lifecycle edges + summary (¼ day).** `rollback`, `apply_stashed_op`,
summary round-trip test; every R1–R15 row traceable to a test.
Exit: full ported suite green.

**RC3 — Fuzz/property (½ day).** Model + properties above on the existing
harness. Mutation check (both plants caught and shrunk).
Exit: 1000 seeded runs green; both planted bugs caught.

Total: **~2 days**, consistent with the 3/10 rating and the claims precedent.

## Open questions

- Should `read`'s default policy be encoded as `read(state, key)` +
  `read_with_policy(state, key, policy)`, or a single `read(state, key, policy)`
  requiring the caller to pass `Atomic`? Leaning single-arg-with-explicit-policy
  (no default) since Gleam has no default args and an explicit `Atomic` at every
  call site is clearer than a hidden default; revisit at review.
- `VersionedValue` is structurally identical to claims' `ClaimEntry`. Worth a
  shared `dds/versioned.gleam`? Deferred — two copies is not yet duplication
  worth a module, and the semantics may still diverge.
</content>
</invoke>
