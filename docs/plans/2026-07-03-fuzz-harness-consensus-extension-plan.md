# Fuzz harness consensus extension plan (F6 / CO0)

**Date:** 2026-07-03
**Builds on:** `2026-07-03-kernel-fuzz-harness-plan.md` (F1–F5 — this is the F6
milestone that plan's F5 anticipated: *"if the quorum modeling needs more than
the connected-client set … extend the meta record then — the signature is
already threaded"*).
**Consumed by:** `2026-07-03-pact-map-kernel-plan.md` and
`2026-07-03-ordered-collection-kernel-plan.md`, both of which call this work
**CO0** and depend on it for their fuzz milestones.
**Reference source:** `test/watershed/fuzz/kernel_fuzz.gleam` (the harness being
extended), `../FluidFramework/packages/dds/{pact-map,ordered-collection}/src/`.

## Why the harness needs extending

The F1–F4 harness assumes a kernel whose only inputs are **generated ops** and
whose only membership signal is a client dropping out of the convergence check.
That holds for counter, map, claims, and register-collection: every op is
fuzzer-generated, applying an op never produces another op, and a disconnect has
no *sequenced* effect on anyone else's state.

pact-map and ordered-collection both break those two assumptions, in the same
two ways:

1. **Follow-on ops.** Applying a sequenced op makes a client owe a *new* op.
   - *pact-map:* when a `set` sequences, **every** connected client in the
     proposal's signoff set emits its own `accept{key}` — a fan-out.
   - *ordered-collection:* when a client's own `acquire` sequences and succeeds,
     **that** client emits a `complete` or `release` — a single-actor follow-on
     driven by the acquirer's callback.
   The current interpreter's `deliver_one` returns only new state; there is no
   channel for "this delivery produced an op to send."

2. **Membership-leave as a sequenced event.** A disconnect is not just an
   exclusion; it has a *position in the total order* and a deterministic effect
   every client applies when it reaches that position.
   - *pact-map:* the leaver is removed from every pending proposal's signoffs;
     any that empty **settle** (accepted at the leave's sequence number, P10).
   - *ordered-collection:* every item the leaver holds **returns to the queue**
     (O8), at the leave's sequence point.
   The current `Disconnect` moves in-flight ops to `resend` and marks the client
   disconnected — it produces no sequenced state change on other clients.

The `kernel_fuzz.SequencedMeta` record already carries `connected_clients` and
`min_sequence_number` — the harness author front-loaded the *data* these kernels
need (a `set` snapshots `connected_clients` into its signoff set; nothing more
from the meta is required — the per-client ack tracking F5 speculated about is
handled by the kernels' own `expectedSignoffs`/`jobs` state, not the meta). What
remains is the *interpreter* plumbing: this plan.

## Design: two optional capabilities + interpreter changes

Both additions follow the harness's established pattern — **optional
`Capabilities` fields**, `None` for kernels that don't use them — so counter,
map, claims, and register-collection are behaviorally unchanged (they gain two
`None` fields in their model constructors and one mechanical oracle-signature
tweak; see Migration).

### Capability 1: reactive (follow-on) ops

```gleam
/// After a delivered op is applied (remote apply or local ack), the delivering
/// client may owe follow-on ops. Runs against the POST-apply state.
///   - self_id  : the delivering client's index (who owes the follow-on)
///   - is_local : True if this was an ack of our own op, False for a remote apply
/// Returns ops to enqueue from `self_id`, exactly as if it had submitted them
/// (routed to inbox if connected, else resend — reusing ClientOp's routing).
/// Reaction ops bypass `submit`: they are final wire ops with no SubmitMeta
/// rewrite (pact-map `accept` and ordered-collection `complete`/`release` carry
/// no ref_seq), and are non-optimistic (no local state change until they
/// sequence back), so no optimistic-apply step is needed.
react: Option(fn(state, op, SequencedMeta, Int, Bool) -> List(op))
```

- **pact-map** `react`: if the op is a `Set` and, in the post-apply state, the
  key's pending signoff set contains `self_id`, return `[Accept(key)]`; else
  `[]`. Fires on both local ack and remote apply (`is_local` is ignored — any
  signoff client owes an accept, including the submitter, which is in its own
  signoffs).
- **ordered-collection** `react`: if the op is an `Acquire(id, disposition)`,
  `is_local` is `True`, and the post-apply `jobs` contains `id` owned by
  `self_id` (i.e. the acquire actually took an item — a `QueueEmpty` acquire
  leaves no job), return `[Complete(id)]` or `[Release(id)]` per the
  disposition; else `[]`. The disposition rides on the *model* op (like claims'
  `ClaimCommand` vs `ClaimOp`), stripped before it reaches the kernel.

Because the reaction inspects post-apply state to decide, it needs no extra
bookkeeping: "did my acquire succeed" and "am I a signer" are both readable from
the state the delivery just produced.

**Termination.** Reaction graphs are shallow DAGs: a `set` → accepts (which
produce no reactions); an `acquire` → one complete/release (which produce none).
Depth ≤ 2, bounded fan-out. The interpreter still guards with a round cap (see
`synchronize` below) so a *model* bug that reacts unboundedly fails loudly
instead of hanging.

### Capability 2: membership-leave as a sequenced event

```gleam
/// Apply a client-leave at its sequence point. `leaver` is the departed
/// client's index; `meta.sequence_number` is the leave's position (the
/// analog of the ClientLeave message's SN — pact-map stamps settled values
/// with it, P10). Pure state transition; produces no ops (neither kernel's
/// leave effect emits one — re-release and settle are state changes).
remove_member: Option(fn(state, Int, SequencedMeta) -> state)
```

The leave enters the total order as a new **log-entry kind**. The interpreter's
`inbox`/`log` change from `List(#(Int, op))` to `List(LogEntry(op))`:

```gleam
pub type LogEntry(op) {
  OpEntry(client: Int, op: op)
  LeaveEntry(client: Int)
}
```

`Disconnect(client)`, when the model has a `remove_member` capability, keeps its
current behavior (move the client's in-flight *inbox* ops to `resend`) **and**
appends a `LeaveEntry(client)` to the inbox tail — so the leave sequences after
the ops currently awaiting sequencing, mirroring a server sequencing a
ClientLeave after the client's last delivered op. When the model has no
`remove_member` capability, `Disconnect` is byte-identical to today (no
`LeaveEntry`), so counter/map/claims/CRC logs never contain leaves.

Delivery dispatches on entry kind:
- `OpEntry` authored by the delivering client → `ack_local` (+ `react`,
  `is_local = True`).
- `OpEntry` by another client → `apply_remote` (+ `react`, `is_local = False`).
- `LeaveEntry(leaver)` → `remove_member(state, leaver, meta)` if the capability
  is present, else a cursor-only advance. Every *connected* client processes the
  leave when it reaches that position; the leaver (disconnected) is excluded
  from convergence anyway, and re-derives a consistent state by replaying the
  log — including its own leave — on reconnect. Idempotency makes this safe:
  pact-map's signoff filter and ordered-collection's owner filter are both
  no-ops when re-applied (the id is already drained / owns no jobs).

### `synchronize` becomes a fixpoint

Today `synchronize` is one pass: sequence all inbox → deliver all → validate.
With follow-on ops, one delivery pass can refill the inbox (the accepts a `set`
provoked land after the sequence step), so a single pass no longer reaches
quiescence. Generalize to a loop:

```
repeat:
  if inbox empty AND every connected client is delivered to log end: stop
  sequence_n(all inbox)
  deliver_all_connected            # may enqueue reaction ops
  guard: round_count < CAP else Error("did not reach quiescence")
then validate_convergence
```

For non-reactive kernels this terminates on the first iteration (delivery
enqueues nothing), so their behavior is unchanged. Worked example (pact-map,
2 clients A, B):

1. `ClientOp(A, Set(k,v))`, `Synchronize`.
2. Round 1: sequence the set; A acks it (react → A owes `Accept(k)`), B applies
   it (react → B owes `Accept(k)`). Inbox now `[Accept@A, Accept@B]`.
3. Round 2: sequence both accepts; delivering them drains signoffs; the second
   to arrive empties the set → `accepted`. Reactions from accepts: none.
4. Round 3: inbox empty, all delivered → stop. Convergence holds: both see the
   value accepted at the second accept's SN.

## What is deliberately *not* changed

- **`SequencedMeta` is not extended.** `connected_clients` is the only new datum
  either kernel reads, and it is already present. F5's "per-client ack tracking"
  lives in the kernels' `expectedSignoffs`/`jobs`, not the meta.
- **`submit`/`SubmitMeta` are untouched.** Reaction ops are final and skip
  submit; generated ops still flow through `submit` as today.
- **Disconnect's resend semantics are untouched.** The in-flight-ops-to-resend
  behavior stays; `LeaveEntry` is purely additive.
- **No new failure-fixture format.** Scripts serialize as `Command`s (F4), and
  `Disconnect` already round-trips; `LogEntry`/leaves are runtime state, never
  serialized. The F4 JSON codecs need no change.

## Validation additions

- **Convergence** (unchanged mechanism): after a fixpoint `Synchronize`, every
  connected client's `observe` equals the reference client's — now exercised
  across leave-driven settling / re-release.
- **Oracle** (signature migration): the oracle now receives the full ordered
  `List(LogEntry(op))` so it can replay leaves. pact-map's oracle folds sets
  into pending-with-frozen-signoffs and drains on accepts/leaves;
  ordered-collection's folds add/acquire/complete/release/leave. A `log_ops`
  helper (`fn(List(LogEntry(op))) -> List(#(Int, op))` dropping leaves) keeps the
  existing kernels' oracles a one-line change.
- **Kernel-specific invariants** ride the existing optional `check` hook
  (ordered-collection's *conservation*: every added value is in exactly one of
  queue / held / completed; pact-map's *signoff monotonicity*: signoff sets only
  shrink and never gain a late joiner).

## Migration (existing models)

Mechanical, all in `test/watershed/fuzz/`:

1. `Capabilities` gains `react: None, remove_member: None` in
   `counter_model`, `map_model`, `claims_model`, and (when it lands)
   `register_collection_model`.
2. Each existing `oracle` changes from `fn(log) { … }` to
   `fn(entries) { let log = kernel_fuzz.log_ops(entries) … }` — one line.
3. No changes to `op_to_json`/`op_decoder`, `submit`, `apply_remote`,
   `ack_local`, or any command generator.

A parity gate protects the migration: the existing counter/map/claims/CRC fuzz
suites must stay green (same seeds, same iteration counts) after the refactor,
proving the `LogEntry`/fixpoint changes are behavior-preserving for
non-reactive kernels.

## Test plan (TDD)

Extend `test/watershed/fuzz/` tests before the interpreter changes:

- **Interpreter unit tests** (`kernel_fuzz_test.gleam` additions), using a tiny
  purpose-built reactive model (not a real kernel) so the mechanics are tested
  in isolation:
  - A `set`-like op whose `react` returns one follow-on; assert `Synchronize`
    reaches quiescence in the expected number of rounds and both clients
    converge.
  - A `LeaveEntry` delivered to two clients applies `remove_member` on both at
    the same SN; assert the leaver is excluded and survivors converge.
  - The round-cap guard: a deliberately non-terminating `react` produces an
    `Error("did not reach quiescence")`, not a hang.
  - Reaction routing under disconnect: a client that owes a follow-on but is
    disconnected routes it to `resend`, and it replays on `Reconnect`.
- **Parity tests:** re-run counter/map/claims/CRC fuzz at a fixed seed before
  and after; identical pass.
- **Consumer smoke tests:** once pact-map / ordered-collection models exist
  (their own plans), a hand-written script per kernel exercising the full
  set→fan-out-accept→accepted and acquire→complete/release→leave-re-release
  paths, asserted green — the concrete acceptance criteria for CO0.

Mutation checks (harness-level, both caught and shrunk):
- Break the fixpoint (`synchronize` does a single pass): pact-map fails to reach
  `accepted`, convergence/oracle mismatch at the appended final `Synchronize`.
- Drop `remove_member` dispatch on `LeaveEntry` (advance cursor only): a
  proposal waiting only on a leaver never settles; ordered-collection loses the
  leaver's items — both caught by the oracle.

## Milestones

**F6a — `LogEntry` + `remove_member` (½–1 day).** Refactor `inbox`/`log` to
`List(LogEntry(op))`; add the capability, `Disconnect` leave-generation (gated),
leave delivery dispatch, `log_ops` helper, oracle signature migration. Parity
tests green.
Exit: interpreter unit tests for leave delivery + the parity gate pass.

**F6b — reactive ops + fixpoint `synchronize` (½–1 day).** Add the `react`
capability, follow-on routing (shared with `ClientOp`), the fixpoint loop + round
cap. Interpreter unit tests for reactions/quiescence pass.
Exit: reactive-model unit tests + round-cap mutation check pass; parity still
green.

**F6c — consumer wiring hooks (folds into the pact-map / ordered-collection fuzz
milestones).** No new harness code — this is the point where PM3 / CO3 supply
`react`/`remove_member` in their models and the smoke tests above go green.

Total: **~1–1.5 days** of harness work (F6a+F6b), after which pact-map and
ordered-collection fuzz coverage is a per-kernel model cost with no further
interpreter changes. Sequence it **before whichever of pact-map /
ordered-collection is ported first**; register-collection needs none of it and
can proceed in parallel.

## Open questions / risks

- **Fixpoint cost.** Each reactive `Synchronize` now runs multiple
  sequence/deliver rounds; with invariants on and `observe` re-computed per
  delivery, long scripts get costlier on BEAM. Mitigate as the base plan
  suggests (cap script length ~60, sample invariants) and only fixpoint when a
  reactive capability is present.
- **Reconnect-with-same-id vs. TS new-clientId.** The harness keeps a client's
  index across Disconnect/Reconnect, whereas Fluid assigns a new clientId on
  reconnect. Replaying leaves is idempotent so convergence still holds, but a
  reconnected client re-acquiring an item it previously held (same id) is a
  scenario TS never produces. Documented as a known modeling boundary (the base
  plan's disconnect-semantics caveat); if a kernel ever depends on
  clientId-freshness, model reconnect as a *new* index instead of a new
  capability.
- **Should `remove_member` be allowed to emit follow-on ops?** Neither current
  consumer needs it (leave effects are pure state changes). Kept `-> state` for
  simplicity; if a future kernel needs leave-triggered ops, widen to
  `-> #(state, List(op))` then — a localized change.
- **`react` on `LeaveEntry`.** Not supported (leaves take no `react`). No
  consumer needs a leave to trigger a follow-on op; add if one appears.
</content>
