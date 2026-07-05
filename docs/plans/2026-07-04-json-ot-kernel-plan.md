# JSON-OT kernel plan (json0 on the watershed sequencer)

**Date:** 2026-07-04
**Builds on:** `2026-07-03-dds-porting-complexity.md`,
`2026-07-03-kernel-fuzz-harness-plan.md` (TP1 needs fuzz coverage), and
`2026-07-03-runtime-generalization-plan.md` (kernel-agnostic sequencing).
**Reference source:** `ottypes/json0` (`json0.js` ~1k LOC transform matrix,
`json0.spec.js` as the behavioral oracle) and the Jupiter algorithm
(Nichols et al., 1995) as adapted by Fluid Framework's merge-tree.

## Thesis: the sequencer already provides everything OT needs

Watershed's per-connection state machine (`runtime_core.gleam`) rides
spillway's central sequencer. Each `SequencedDocumentMessage`
(`../spillway/src/spillway/types.gleam:95-101`) carries:

- `sequence_number` (SN) — a **single total order** over all ops.
- `client_sequence_number` (CSN) — FIFO ack matching per connection.
- `reference_sequence_number` (RSN) — the version the author had seen.
- `minimum_sequence_number` (MSN) — the GC watermark below which no op can
  still reference; the horizon past which transform history can be dropped.

This is exactly the Jupiter / Fluid substrate. Because a central server
imposes one total order, an OT kernel needs only **TP1** (transform property 1:
`xf(a,b)` and `xf(b,a)` converge for a *single* concurrency pair) and never
**TP2** (the client/client convergence puzzle that makes decentralized OT
hard). TP1-only OT is tractable and is precisely what json0 implements.

The existing kernels don't transform because CRDT/LWW merge rules make
concurrent ops commute by construction. JSON-OT is the same kernel *shape*
with a transform step swapped in where today's kernels apply directly.

## The fit with the existing kernel contract

Every kernel (`map_kernel.gleam`, `task_manager_kernel.gleam`, …) already:

1. splits `sequenced` (server-confirmed) from `pending` (unacked local ops),
2. applies remote ops against `sequenced`,
3. acks own ops in strict FIFO (`ack_local` / `ack_own_op`), and
4. round-trips a summary snapshot.

A JSON-OT kernel is the **client-transform (Jupiter)** variant of that
contract. Only two steps change:

- **apply remote op** → transform the incoming op *forward past the pending
  queue* before applying to `sequenced`, and symmetrically transform the
  pending queue *past the incoming op* so later acks line up. Today's kernels
  apply remote ops directly.
- **ack own op** → the just-sequenced op is our own head-of-pending; pop it.
  Remaining pending ops are already expressed against the new sequenced
  state because they were transformed as each intervening remote op arrived.

No change to the sequencing discipline, the wire envelope, or the server.
Levee/spillway stay kernel-agnostic; all transform logic lives client-side in
the kernel, exactly like every other DDS here.

## json0 semantics inventory

| # | Behavior | json0 source |
|---|---|---|
| J1 | An op is a list of **components**, each with a `p` path (JSON pointer: object keys as strings, array indices as ints). | json0 op model |
| J2 | Object ops: `oi` (insert), `od` (delete), replace = `{od,oi}` on one component. | `json0.apply` |
| J3 | List ops: `li` (insert), `ld` (delete), replace = `{ld,li}`, `lm` (move: `{p, lm:index}`). | `json0.apply` |
| J4 | Number op: `na` (add). Subtype-embedded ops: `t` (subtype name) + `o` (subtype op), e.g. `text0` for string edits inside a value. | `json0.apply` / subtypes |
| J5 | `transform(op, otherOp, side)` where `side ∈ {left,right}` breaks insert-at-same-index ties deterministically. | `json0.transform` |
| J6 | List-index transform: an `li`/`ld` at or before a peer index shifts that peer's index; `lm` transforms as a coordinated delete+insert. | `transformComponent` |
| J7 | Object-key transform: concurrent `oi`/`od` at the same path — deletes drop the peer's stale `od`, `side` breaks `oi/oi` ties. | `transformComponent` |
| J8 | Path-prefix rule: if one op operates on a subtree the other deleted, the descendant op is dropped (or rebased under a moved prefix). | `transformComponent` |
| J9 | `compose` and `invert` (invert needs the pre-image, so it is snapshot-assisted). Invert powers rollback. | `json0.compose` / `invert` |
| J10 | Subtype (`text0`) has its own `transform`/`apply`; the container defers to the registered subtype for `t`-components. | subtype registry |

TP1 is the correctness bar: for every concurrent pair `(a,b)`,
`apply(apply(doc,a), transform(b,a,left)) == apply(apply(doc,b), transform(a,b,right))`.

## Kernel design

New module `src/watershed/json_ot_kernel.gleam`. Pure, side-effect-free,
runtime-unaware — same discipline as the other kernels.

### Types

```gleam
pub type JsonOtState {
  JsonOtState(
    /// Server-confirmed document (a JSON value tree).
    sequenced: json.Json,
    /// Unacked local ops, oldest first, each expressed against `sequenced`
    /// as remote ops are folded in.
    pending: List(JsonOtOp),
  )
}

/// An op is an ordered list of components (json0 shape).
pub type JsonOtOp =
  List(Component)

pub type Component {
  Component(path: List(PathKey), edit: Edit)
}

pub type PathKey {
  Key(String)   // object member
  Index(Int)    // array position
}

pub type Edit {
  ObjInsert(value: json.Json)             // oi
  ObjDelete(value: json.Json)             // od (value = pre-image, for invert)
  ListInsert(value: json.Json)           // li
  ListDelete(value: json.Json)           // ld
  ListMove(to: Int)                      // lm
  NumberAdd(delta: Float)                // na
  Subtype(name: String, op: json.Json)  // t/o, e.g. "text0"
}

pub type Side { Lft Rgt }

pub type JsonOtEvent {
  DocChanged(path: List(PathKey), local: Bool)
}

pub type KernelError {
  UnexpectedAck(detail: String)
  BadPath(detail: String)
  TransformConflict(detail: String)
}
```

### API surface

| Function | Signature (abbrev.) | Notes |
|---|---|---|
| `new` | `fn() -> JsonOtState` | Empty document (`json.null` or `object([])`). |
| `from_summary` / `summary` | `Json` round-trip | Summary is just the sequenced doc + SN (SN lives in the envelope, not the kernel). No pending is ever summarized. |
| `apply_op` | `fn(Json, JsonOtOp) -> Result(Json, KernelError)` | Pure document application (J2–J4). Shared by local + remote paths. |
| `transform` | `fn(a: JsonOtOp, b: JsonOtOp, side: Side) -> Result(JsonOtOp, KernelError)` | TP1 transform of `a` past `b` (J5–J8). Component-wise, right-multiplied over both op lists. |
| `local_edit` | `fn(state, JsonOtOp) -> Result(#(JsonOtState, JsonOtOp, List(JsonOtEvent)), KernelError)` | Apply optimistically, append to `pending`, return the op to send. |
| `apply_remote` | `fn(state, op) -> Result(#(JsonOtState, List(JsonOtEvent)), KernelError)` | Transform `op` past `pending` (side=right), apply to `sequenced`; transform `pending` past `op` (side=left). |
| `ack_local` | `fn(state, op) -> Result(#(JsonOtState, List(JsonOtEvent)), KernelError)` | Own op sequenced: pop `pending` head (must equal `op` after the transforms already folded in), apply to `sequenced`. |
| `compose` | `fn(a, b) -> Result(JsonOtOp, KernelError)` | J9, optional; used to batch resubmits. |
| `invert` | `fn(op, pre_image: Json) -> Result(JsonOtOp, KernelError)` | J9; powers rollback. `od`/`ld` already carry pre-images. |
| `rollback` | `fn(state, op) -> Result(#(JsonOtState, List(JsonOtEvent)), KernelError)` | Pop matching pending op, invert against sequenced, re-emit. |
| `subtype_transform` / `subtype_apply` | `text0` hooks | Registered by name; container defers on `Subtype` components. Ship `text0` first. |

### Design decisions

1. **Client-transform (Jupiter), not server-transform.** The server would
   otherwise need per-document op history and transform logic, breaking the
   kernel-agnostic sequencer invariant this repo maintains
   (`runtime-generalization-plan.md`). Client-transform keeps all OT logic in
   the pure kernel and needs *nothing* from levee beyond the SN/RSN it already
   stamps.

2. **RSN is redundant on the fast path, load-bearing on reconnect.** On a live
   connection the client already knows its unacked ops (`pending`), so incoming
   remotes are transformed past that local queue — RSN is not consulted. RSN
   *is* needed to rebase pending ops on **reconnect / history catch-up**
   (`runtime_core.gleam` `catch_up` / `handle_sequenced`): ops the client sent
   before the gap must be transformed past every op in `(RSN, head]`.

3. **Pre-images travel with deletes.** `od`/`ld` carry the deleted value so
   `invert` (and therefore rollback) needs no external snapshot, matching json0
   and keeping the kernel pure.

4. **`side` from author identity, not wall clock.** Break insert-at-same-index
   ties by comparing the two ops' authors' sequencing order (own pending op is
   always `left` vs an incoming remote), giving a stable, replicated tie-break.

5. **Start with `text0` as the only subtype.** It covers collaborative strings
   inside JSON values (the common ShareDB use case) and is small. Additional
   subtypes register through the same hook later.

## Runtime / wire integration (the standard "add a kernel" checklist)

Follow the checklist documented at the top of `channel.gleam`:

- **`wire/ops`** — add the JSON-OT channel-op wire codec (encode/decode a
  component list). Envelope, CSN/RSN/SN stay untouched.
- **`channel.gleam`** — add `JsonOtChannel` to `ChannelType`, `ChannelInit`,
  and the parallel state/op/event/snapshot sums; extend
  `encode_snapshot`/`snapshot_decoder` for the sequenced document.
- **`runtime.gleam` + `runtime_js.gleam`** — actor/runtime verbs for
  `local_edit` (submit) and document reads.
- **fuzz model** — new `test/watershed/fuzz/json_ot_model.gleam` with an op
  generator (weighted across obj/list/number/text0 components at random paths)
  and a reference oracle: a naive last-writer document is *not* a valid oracle
  for OT, so the oracle is **convergence** — all replicas that receive the same
  sequenced op stream must land on byte-identical `sequenced` JSON.

## Test strategy

1. **json0 spec port.** Translate `json0.spec.js` transform cases into
   `test/watershed/json_ot_kernel_test.gleam` — these are the authoritative
   TP1 pairs.
2. **TP1 property fuzz.** For random doc + concurrent op pair `(a,b)`, assert
   `apply(apply(doc,a), xf(b,a,left)) == apply(apply(doc,b), xf(a,b,right))`.
   Wire into the existing fuzz harness (`FUZZ_ITERATIONS`, `just fuzz`).
3. **Multi-client convergence fuzz.** Reuse `script_gen`/`kernel_fuzz` to drive
   N clients through the runtime against one sequencer and assert final-document
   equality — the end-to-end proof the sequencer + kernel deliver OT.
4. **Reconnect rebase.** Explicit tests that pending ops sent before a history
   gap converge after catch-up (design decision #2).
5. **Rollback / invert** round-trips: `apply` then `invert` restores the doc.

## Effort & sequencing

| Rung | Work | Rough size |
|---|---|---|
| 1 | `apply_op` + document model + object/list/number components | small |
| 2 | `transform` matrix (J5–J8), json0 spec port, TP1 fuzz | **large — the real cost** |
| 3 | Kernel wrapper (`local_edit`/`apply_remote`/`ack_local`) + pending rebase | medium |
| 4 | `text0` subtype + hooks | small–medium |
| 5 | wire/channel/runtime/fuzz integration + convergence tests | medium |
| 6 | reconnect rebase + rollback/invert | medium |

The plumbing (rungs 1, 3, 5, 6) is routine for this repo. **Rung 2 is where the
difficulty lives**: a correct, TP1-satisfying transform. Port json0 rather than
deriving fresh, and treat the ported spec + TP1 fuzz as the acceptance gate.

## Implementation status & deviations

Rungs 1–6 are implemented on branch `json-ot-kernel`. Two deviations from the
sketch above matter:

- **Single-inflight, not `pending: List`.** The kernel is the client-transform
  (Jupiter/ShareDB) *single-inflight* variant: one `inflight` op plus a
  composed `buffer` of not-yet-sent local ops, rather than an unbounded
  `pending` queue. On `ack_local` the buffer is released as the next outbound op
  (fixed at `ref_seq = ack seq`), stashed in the kernel's `outbound` field and
  pulled by `channel.take_outbound`. The runtime drains released ops in
  `runtime_core.collect_released_ops` after apply+drain in `handle_sequenced`,
  stamping each with a fresh CSN and sending via the normal outbound path. This
  is the buffer-release mechanism added to the core actor loop.
- **Envelope carries RSN *and* MSN.** `spillway/types.SequencedDocumentMessage`
  already exposes `reference_sequence_number` and `minimum_sequence_number`, so
  MSN is threaded through `channel.SequencedMeta.min_seq` rather than derived.

User-facing API: `watershed.create_json_ot` / `submit_json_ot` / `json_ot_view`
/ `subscribe_json_ot` (erlang) and `runtime_js.create_json_ot` / `submit_json_ot`
/ `json_ot_view` (javascript). Convergence is proved by the bespoke
`json_ot_kernel_converge_test` (json0 ops are state-dependent, so the static
`KernelModel` fuzz harness does not fit).

### Rung 6 (reconnect rebase + rollback)

- **Reconnect rebase needs no json0-specific code.** The generic
  `runtime_core.resubmit` / `restamp_in_flight` re-sends an unacked op with a
  fresh CSN and envelope RSN but leaves the json0 wire op's internal `ref_seq`
  and components untouched. Receivers rebase it past `(ref_seq, head]` via the
  transform window — the same window the convergence harness already exercises
  (clients submit at a stale `ref_seq` while other clients' ops interleave
  ahead of them). So the existing convergence proof covers the reconnect-gap
  case; design decision #2 holds without extra threading.
- **Rollback is the kernel's pure `invert`.** Deletes carry their pre-image
  (`od`/`ld`), so `invert(op)` restores the prior document with no external
  snapshot. There is no live nack→rollback verb in the runtime (no kernel here
  has one); the capability is proved by `json_ot_invert_test` round-trips
  (obj/list/number/replace/move + compose + double-invert identity).

## Non-goals

- **TP2 / decentralized OT.** The central sequencer makes it unnecessary; do
  not build it.
- **Server-side transform in levee.** Keeps the sequencer kernel-agnostic.
- **Subtypes beyond `text0`** in the first cut.
- **Presence/cursor transforms** (a separate concern from document OT).
- **json1** (arbitrary subtree moves, document-free invert) — a future
  successor, sketched in `2026-07-04-json1-ot-speclet.md`. It reuses this
  kernel's substrate and assumes json0 ships first. Build it only if json0's
  limits bite.

## Open questions

1. Do we want json0 wire-compatibility with ShareDB (same JSON component
   encoding) so existing tooling interops, or a watershed-native encoding?
2. Should `text0` reuse an existing Gleam text-OT, or port ottypes `text0`
   directly for spec parity?
3. MSN-driven history GC: the kernel itself is history-free (client-transform),
   but reconnect rebase needs the runtime to retain ops back to the client's
   own last-acked SN — confirm that horizon against `minimum_sequence_number`.
