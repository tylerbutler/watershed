# Runtime generalization plan: multi-kernel channels

**Date:** 2026-07-03
**Builds on:** `2026-07-03-dds-porting-complexity.md` (the porting ladder),
`2026-07-03-claims-kernel-plan.md` (whose runtime integration is deferred to
this plan).
**Scope:** make `runtime_core` + the two runtime actors route ops to any
kernel, so ported kernels (counter today, claims next, then the ladder) become
usable channels instead of standalone libraries.

## Current state: where the map coupling lives

`runtime_core.gleam` is hardcoded to `map_kernel` at every layer, and the
actors + wire formats inherit that:

| # | Coupling point | Location |
|---|---|---|
| P1 | `Core.channels` / `Core.detached` are `Dict(String, map_kernel.MapState)` | runtime_core.gleam:29–31 |
| P2 | `InFlightOp.op: MapOp`; ack matching (`same_shape`) pattern-matches map constructors | runtime_core.gleam:40, 544 |
| P3 | `Ingested` events are `#(String, MapEvent)`; actor `Subscribe` takes `Subject(MapEvent)` | runtime_core.gleam:63, runtime.gleam:124 |
| P4 | Attach handling rejects any `channel_type != "map"`; `seed_channels` / `remote_attach` build `map_kernel.from_sequenced` | runtime_core.gleam:335, 187, 399 |
| P5 | Local-edit API is map verbs only (`set`/`delete`/`clear`; actor `Put`/`Remove`/`RemoveAll`/`CreateMap`); reads are map reads (`get`/`keys`/`entries`/`size`) | runtime_core.gleam:599–691, 831–861 |
| P6 | `decode_op_contents` decodes every non-attach op as a **map envelope** — the wire has no per-op channel-type marker | wire/ops.gleam:269 |
| P7 | Snapshots are map-shaped everywhere: attach `snapshot` is `List(#(String, Json))`, summary blob v2 channel `entries` likewise, `Summary`/`summary_channels` types match | wire/ops.gleam:63, wire/summary_blob.gleam:20, runtime_core.gleam:66, 147 |
| P8 | Attach-dependency ordering scans handles via `map_kernel.entries` | runtime_core.gleam:735 |

Two pieces of groundwork already exist: `wire/ops.gleam` has complete
**counter op codecs** (`encode/decode_counter_envelope`) that nothing calls,
and the attach envelope already carries `channelType`. The wire vocabulary
anticipated this plan; only the routing didn't.

Both actors (`runtime.gleam` @target(erlang), `runtime_js.gleam`
@target(javascript)) wrap the same `runtime_core`, so the pure state machine
is the bulk of the work and the actors are mechanical mirrors.

## Design: a closed channel sum, dispatched in one module

### Chosen approach

New module `src/watershed/channel.gleam` owning three parallel sum types plus
one dispatch function per operation the runtime needs:

```gleam
pub type ChannelType {
  MapChannel
  CounterChannel
  ClaimsChannel
}
// with to_string/from_string mapping to wire.channel_type_* constants

pub type ChannelState {
  MapState(map_kernel.MapState)
  CounterState(counter_kernel.CounterState)
  ClaimsState(claims_kernel.ClaimsState)
}

pub type ChannelOp {
  MapOp(map_kernel.MapOp)
  CounterOp(counter_kernel.CounterOp)
  ClaimsOp(claims_kernel.ClaimOp)
}

pub type ChannelEvent {
  MapEvent(map_kernel.MapEvent)
  CounterEvent(counter_kernel.CounterEvent)
  ClaimsEvent(claims_kernel.ClaimEvent)
}
```

Dispatch functions (each a single `case` over the state/op pair; mismatched
pairs are a `WrongChannelType` error):

```gleam
pub fn channel_type(state: ChannelState) -> ChannelType
pub fn new(t: ChannelType) -> ChannelState
pub fn from_snapshot(t: ChannelType, snapshot: Snapshot) -> Result(ChannelState, Nil)
pub fn snapshot(state: ChannelState) -> Snapshot            // sequenced-only view
pub fn apply_remote(state, op, meta: SequencedMeta)
  -> Result(#(ChannelState, List(ChannelEvent)), ChannelError)
pub fn ack_local(state, op, meta: SequencedMeta)
  -> Result(#(ChannelState, List(ChannelEvent), Option(Resolution)), ChannelError)
pub fn same_shape(ours: ChannelOp, echoed: ChannelOp) -> Bool
pub fn handle_addresses(state: ChannelState) -> List(String)  // P8: attach deps
pub fn encode_op(address: String, op: ChannelOp) -> Json      // delegates to wire/ops
pub fn op_decoder(t: ChannelType) -> Decoder(ChannelOp)
```

`SequencedMeta` mirrors the fuzz-harness record: `SequencedMeta(seq: Int,
last_seen_sn: Int)` today, extended with min-seq/connected-client data when
pact-map/ordered-collection arrive. Map and counter ignore it; claims consumes
`seq` (entry SNs) — threading it from day one is the same pay-it-forward
decision the fuzz plan already made.

### Rejected alternatives

- **Record-of-closures "channel objects"** (a `Channel` record whose functions
  capture kernel state and return new records). Avoids the sums, but ops
  arrive as wire JSON and sit in the in-flight queue as data — they'd need
  type erasure via `Dynamic` or re-encoding, losing exhaustiveness checking,
  which is the main thing the compiler gives us when the ladder adds a kernel
  (add a variant → the compiler lists every dispatch site to update).
- **One dict per kernel type** (`map_channels`, `counter_channels`, …).
  Superficially simpler, but every address-keyed code path (attach, ack
  routing, summary order, handle resolution) would need N lookups and the
  cross-type collision rules become implicit. The sum keeps "one address, one
  channel" structural.
- **Generalizing `runtime_core` over a type parameter.** Gleam generics can't
  express "a dict of *differently*-typed kernels", which is the actual
  requirement. Parametrism solves homogeneous, not heterogeneous.

### The snapshot problem (P7)

Snapshots are the one place the map shape leaked into **persisted formats**,
so this is a format-versioning problem, not just a refactor:

```gleam
pub type Snapshot {
  MapSnapshot(entries: List(#(String, Json)))
  CounterSnapshot(value: Int)
  ClaimsSnapshot(entries: List(#(String, Json, Int)))  // seq numbers persisted
}
```

No formats have external consumers (nothing outside this repo reads the wire
or the blobs, and stored documents are disposable), so these are clean cuts,
not migrations:

- **Attach op:** keep `{type:"attach", address, channelType, snapshot}` but
  make the `snapshot` payload channel-type-dependent (decoder selected by the
  `channelType` field, which already exists). The map payload happens to stay
  the same shape as today.
- **Summary blob:** bump to **v3**: per-channel `{address, type, data}` where
  `data` is the type-dependent payload. Writer and loader are v3-only — the
  v2 decoder is deleted, not carried, and levee storage is reset rather than
  migrated. The bump itself is schema hygiene (the module's contract is
  "reject what you don't understand, cleanly"), not compatibility.
- `runtime_core.Summary` and `summary_channels` change to
  `List(#(String, Snapshot))` accordingly.

### Op decoding is type-directed by address (P6)

The `{address, contents}` op envelope carries no channel type. We *could* add
one (no external consumer constrains the wire format), but it would be
redundant with — and could contradict — the channel registry, which is the
authoritative source of a channel's type. So decoding becomes two-stage, the
way Fluid itself routes:

1. `wire/ops.decode_op_contents` returns attach ops fully decoded (it has
   `channelType`) but channel ops only as `#(address, Dynamic)`.
2. `runtime_core.handle_op` looks up the channel's `ChannelType` by address
   (channels are always attached before their ops arrive — an op for an
   unknown address is already an `UnknownChannel` error) and runs
   `channel.op_decoder(type)` on the contents. Decode failure stays
   `BadOpContents`.

This also fixes a latent bug class for free: today a counter-shaped op payload
would mis-decode or error as a map op; after this, decoding is always against
the right grammar.

### Ack outcomes reach the caller (P3 extension, needed for claims)

Map and counter acks are silent (optimism already showed the result). Claims
acks *produce the answer* (`Accepted`/`Lost`). Generalize the ack path:

- `channel.ack_local` returns `Option(Resolution)`;
  `Resolution = ClaimResolved(key: String, outcome: claims_kernel.ClaimOutcome)`
  (a sum with one variant for now — task-manager and the consensus kernels
  will add theirs).
- `runtime_core.handle_sequenced`'s `Ingested` grows a
  `resolutions: List(#(String, Resolution))` field (address-tagged, like
  events).
- The **actors** keep a registry `Dict(#(String, String), Subject(ClaimOutcome))`
  (address+key → waiter), populated at submit, drained by resolutions, and
  flushed with `Aborted` on shutdown. On *reconnect*, pending claims are
  **not** aborted — in-flight ops are resubmitted (`resubmit`), so the waiter
  just waits longer; only terminal failure (`Failed` phase, `Shutdown`)
  aborts. This matches the TS dispose-only abort (claims plan S13).

### Local op metadata (P2 extension, needed for counter)

Counter's `ack_local_with_message_id` validates a local message id that never
goes on the wire. That's per-kernel *local* metadata, so it lives in the
in-flight entry, not in `ChannelOp`:

```gleam
InFlightOp(client_id:, csn:, address: String, op: ChannelOp, meta: LocalOpMeta)
pub type LocalOpMeta {
  NoMeta
  CounterMeta(message_id: Int)
}
```

`channel.ack_local` takes the meta and dispatches to
`ack_local_with_message_id` for counters.

### Per-kernel verbs, not a generic mutation API (P5)

The actor `Msg` API stays **typed per kernel** — a generic
`Mutate(address, ChannelOp)` would push op construction and type errors onto
callers. Additions:

- `CreateCounter(reply)`, `CreateClaims(reply)` alongside `CreateMap` (all
  routing to a generalized `create_detached(core, address, channel_type)`).
- `IncrementCounter(address, amount)`.
- `TrySetClaim(address, key, value, reply: Subject(ClaimSubmitReply))` /
  `CompareAndSetClaim(...)` where `ClaimSubmitReply` covers the synchronous
  outcomes (`AlreadyClaimed`, `AlreadyPendingLocally`, `WrongChannelType`)
  and `Pending` (outcome later, via a `Subject(ClaimOutcome)` carried in the
  message — the actor-world stand-in for the TS promise).
- Reads: `GetCounterValue(address, reply)`, `GetClaim(address, key, reply)`,
  `HasClaim(...)`. Existing map reads keep their names and now return
  `WrongChannelType`-shaped defaults (`None`/`[]`) on non-map channels; the
  corresponding `runtime_core` functions return `Result` with a new
  `CoreError.WrongChannelType(address, expected: ChannelType, actual: ChannelType)`.
- `Subscribe` takes `Subject(ChannelEvent)` (breaking; see migration).

The root channel stays a map (`root_address` seeded as `MapChannel`) — it is
the document's namespace and handles to other channels live in it, unchanged.

### Detached channels and attach (P4, P8)

- `create_detached` takes a `ChannelType`; `Core.detached` becomes
  `Dict(String, ChannelState)`.
- Detached **claims** edits route to `claims_kernel.set_detached` (seq-0
  entries, per the claims plan S8); detached counter edits apply optimistically
  and the attach snapshot is just the current value.
- Attach snapshots use `channel.snapshot`; on attach the channel is rebuilt
  via `from_snapshot` exactly as maps are today (`from_sequenced` semantics:
  detached state becomes confirmed state).
- Handle scanning for attach-dependency ordering becomes
  `channel.handle_addresses`: map scans entries (as today), claims scans
  committed **and pending** values (claims plan S15), counter returns `[]`.

## What deliberately does NOT change

- The sequencing discipline (CSN/RSN, dedupe by SN, FIFO ack matching,
  out-of-order buffer, bootstrap/catch-up) is kernel-agnostic already and is
  untouched. The refactor swaps the *payload* types flowing through it.
- The map op wire format stays as-is. Nothing external depends on it (it
  happens to match TS `@fluidframework/map` ops, which keeps the corpus
  tests' vocabulary aligned with the TS oracle), and changing it buys
  nothing — this is inertia, not a compatibility constraint.
- Kernels stay pure and runtime-unaware — this plan adds no kernel changes
  beyond what the claims plan already specifies. If a kernel change turns out
  to be needed mid-implementation, that's a signal the seam is in the wrong
  place; stop and revisit.

## Milestones

Each milestone updates **both actors** (`runtime.gleam`, `runtime_js.gleam`)
before it closes — the twins must not drift, and the website demo runs on the
JS target.

**R1 — Cut the seam, map-only (2–3 days).** Introduce `channel.gleam` with
only the `Map*` variants; mechanically refactor `runtime_core`, both actors,
`wire/ops` (two-stage op decode), and summary blob v3 (v2 decoder deleted,
fixtures regenerated) against it. `Subscribe` moves to `ChannelEvent`.
**Zero behavior change** — the full existing test suite (`runtime_core_test`,
`integration_test`, `wire_test`) must pass with only type-level and fixture
updates. This is the risky, purely-structural step, done with no new
semantics to hide bugs in.

**R2 — Onboard counter (1–2 days).** Add `Counter*` variants; route the
already-written counter codecs; `LocalOpMeta.CounterMeta`; `CreateCounter` /
`IncrementCounter` / `GetCounterValue`; `CounterSnapshot` in attach + summary
v3. Tests: runtime_core counter round-trip (submit → ack, remote apply,
reconnect resubmit restamps counter ops), mixed-document integration test
(root map holding a handle to a counter channel), summary round-trip with
mixed channel types. Counter is the cheapest proof that the seam handles a
second kernel with a *differently shaped* snapshot (Int vs entries).

**R3 — Outcome plumbing + claims (2–3 days).** Requires claims kernel C1–C2
done. Add `Claims*` variants, claim op codec in `wire/ops`
(`{type:"claim", key, value, refSeq}`), `SequencedMeta` consumption,
`Resolution` path through `Ingested`, actor waiter registry with
abort-on-shutdown (not on reconnect), `TrySetClaim`/`CompareAndSetClaim`/
`GetClaim` verbs, `ClaimsSnapshot` with persisted SNs. Tests: two-runtime
integration race (both actors claim one key against a live levee, loser gets
`Lost`), reconnect-with-pending-claim resubmit, summary round-trip preserving
claim SNs.

**R4 — Demo + docs sweep (½–1 day).** Migrate the website convergence demo's
counter view onto the real counter channel (it currently predates runtime
support), update module docs that say "map channels" (`runtime_core` header,
`wire.gleam` header, `channel_type_map` doc comment), and add a short
"adding a kernel" checklist to `channel.gleam`'s module doc — the compiler
finds the dispatch sites, the checklist covers the non-compiler ones (wire
codec, summary payload, actor verbs, fuzz model).

Total: **~1–1.5 weeks**, R1 being the half that needs the most care.

## Risks and open questions

- **R1 is a wide mechanical refactor** touching ~2900 lines across
  runtime_core + two actors. Mitigation: it changes types, not logic; the
  existing test suite is the harness; do it as one PR with no semantic
  changes mixed in.
- **`Subscribe` type change is breaking** for anything holding a
  `Subject(MapEvent)` — the website demo and tests. Accepted; migration is
  wrapping the match in a `MapEvent(..)` destructure.
- **Consensus kernels will stretch `SequencedMeta`** (quorum/connected-client
  tracking for pact-map, ordered-collection). The record is threaded
  everywhere after R1, so extending it is additive; actual quorum state
  tracking in `Core` is future work sized with those kernels.
- **Should reads go through a `ChannelView` sum instead of per-kernel verbs?**
  Deferred — per-kernel verbs are better typed for the current three kernels;
  revisit if the verb count gets silly around task-manager.
