# Plan: Gleam-only SharedMap client for Levee

**Date:** 2026-07-01
**Status:** In progress — reviewed 2026-07-01 against `document_channel.ex`,
`session.ex`, `leveeDeltaConnection.ts`, and spillway/dewdrop sources; wire
contract and runtime sections updated with confirmed payload shapes.
**Repo:** `claude-workspace/watershed` (new sibling repo, water theme).
**M1 complete** (2026-07-01): pure `watershed/map_kernel` ported from
`mapKernel.ts`, 28 unit tests + 5 qcheck properties (convergence across
authorship/submit-timing interleavings, ack transparency, rebase
equivalence, get/entries agreement) at 1000 iterations each, all passing.
**M2 complete** (2026-07-01): TS oracle harness landed on
`feat/map-corpus-harness` (FluidFramework checkout,
`packages/dds/map/src/test/mocha/corpusGenerator.spec.ts` +
`corpusScenarios.ts`); 20 generated scenario files copied to
`test/fixtures/corpus/` and replayed by
`test/watershed/map_kernel_corpus_test.gleam` (multi-client sim over a
global FIFO queue, asserting entries incl. iteration order, per-client
event streams between checks, and convergence). All 20 match the TS
oracle; regenerate via the fixtures README.
**M3 complete** (2026-07-01): `watershed/wire` codecs over spillway
types (git dep on spillway `main`; `document_id`→`id` rename,
`lastSeenSequenceNumber` as a codec argument, local `OutboundOp` for
client-authored ops since spillway's `DocumentMessage` is parse-side);
pure `watershed/runtime_core` state machine (bootstrap with the
checkpoint/join-push dedupe, SN dedupe, fatal gaps pending M4, CSN/RSN
stamping, FIFO ack matching); `watershed/runtime` OTP actor + dedicated
channel-receiver process over aquamarine (roost codec needs
`?vsn=2.0.0` on the socket path); public API in `watershed.gleam`
(connect/root/set/delete/clear/get/entries/subscribe/close). 89 tests:
36 wire+core unit tests plus a live integration test
(`WATERSHED_INTEGRATION=1 gleam test` against `just server`) where two
clients converge on concurrent edits incl. a same-key LWW race, and a
third client bootstraps from history — verified against the levee dev
server. Nack/gap/close-while-connected all crash loudly per the M3
policy; M4 replaces those paths with reconnect/reconcile.
**M4 complete** (2026-07-01): resilience landed in the pure core + actor.
`runtime_core` now buffers out-of-order ops (ascending, deduped) instead of
crashing on gaps, returning `Ingested(events, request_ops_from)` so the
runtime sends an in-band `requestOps` on the first op of a new gap and the
buffer drains as it fills. In-flight entries became
`InFlight(client_id, csn, op)`, so ack-matching by the head's own identity
unifies normal acks with reconnect reconciliation; `adopt_reconnect` swaps in
the fresh client_id while keeping kernel/pending/in-flight/last_seen intact
(sequenced state survives a reconnect — `lastSeenSequenceNumber` pushes only
the delta), and `resubmit` re-stamps survivors with fresh CSNs. The
`watershed/runtime` actor gained a `Reconnecting`/`Ready(core, resubmit_at)`
phase machine: a mid-session close (or retryable nack) respawns the receiver,
re-handshakes, reconciles old-client-id acks from the catch-up stream, then
resubmits leftovers once `last_seen` reaches the reconnect checkpoint; edits
made while (re)connecting apply optimistically and defer their push to that
resubmit, so nothing is lost or duplicated. Fatal nacks (scope/size/hard
limit) still crash; a self-scheduled `noop` heartbeat advances the server MSN.
93 tests (4 new pure reconnect tests: reconcile-then-resubmit,
all-reconciled, missed-delta events, ordered restamp) plus the rewritten gap
test (buffer + single requestOps + contiguous drain). A gated live
integration test (`reconnect_converges_test`) drops a client's channel
mid-burst via the `watershed.force_reconnect` fault-injection hook, then edits
during reconnect and from a peer, and asserts both clients (and a fresh
history-bootstrapping third) converge with no lost/duplicated ops — verified
green against `just server` (94 tests total, stable across repeated runs).
**M5 spike** (2026-07-01): proved a Gleam-end-to-end browser client is feasible
by reusing the pure core unchanged. Erlang-only modules (`runtime`,
`watershed`, live integration test) are gated with `@target(erlang)` so
`gleam build --target javascript` compiles just the pure core plus a new JS
stack: `watershed/transport_js` (+ `transport_ffi.mjs`) wraps the official
phoenix.js client and mints an HS256 dev JWT via a self-contained JS
HMAC-SHA256; `watershed/runtime_js` is a callback/mutable-cell port of the OTP
runtime driving the *same* `runtime_core`/`wire`/`map_kernel`;
`watershed_js` is the public browser API. `examples/dice_lustre` is a Lustre SPA
(entire client is Gleam) that bundles with esbuild. A headless Node smoke test
(`examples/dice_lustre/src/smoke.gleam`) drove two JS clients against a live
`just server` — concurrent edits, a same-key LWW race, and a forced mid-session
reconnect with edits applied during the drop — and both converged identically,
green across repeated runs. Follow-on for productization: split the pure core
into its own package so a JS app doesn't compile the erlang runtime tree.


## Goal

A Gleam library (BEAM target) providing a `SharedMap` that multiple Gleam clients
can edit concurrently through a levee server, with optimistic local reads,
convergence guaranteed by server sequencing, and reconnect safety.

**Out of scope for v1:**

- Interop with TS levee-client documents (those ride the real Fluid container
  runtime and carry double-enveloped ops, batch metadata, and container-runtime
  snapshot formats). The inner map op format is kept byte-identical to the TS
  `@fluidframework/map` ops so an interop layer later only has to add the outer
  datastore envelope. (Footnote for that future layer: the Fluid runtime
  JSON-*stringifies* op contents in places, so interop may also need a
  stringify step on top of the structural match.)
- Summaries/snapshots — v1 documents bootstrap from the `initialMessages`
  field of `connect_document_success` (full op replay from the session's
  history). See the retention caveat under open questions.
- Offline op stashing and the rollback API.
- msgpack serialization (JSON only).
- Signals/presence (cheap follow-on via `submitSignal`).

## Architecture

Three layers, mirroring the separation the TS code has (`mapKernel.ts` vs
`map.ts` vs the driver), but with a pure functional core:

```
┌─────────────────────────────────────────────┐
│  Public API: connect, map handle, subscribe │
├─────────────────────────────────────────────┤
│  Runtime actor ("delta manager")            │   OTP actor
│  handshake · CSN/RSN · inbound ordering ·   │
│  catch-up · resubmit · nack · event fan-out │
├──────────────────────┬──────────────────────┤
│  map_kernel (PURE)   │  wire (PURE)         │
│  sequenced + pending │  levee channel       │
│  LWW merge, acks     │  payload codecs      │
├──────────────────────┴──────────────────────┤
│  aquamarine (channel client, roost codec)   │
└─────────────────────────────────────────────┘
```

- **`map_kernel`** — pure port of the semantics in FluidFramework's
  `packages/dds/map/src/mapKernel.ts`. No process, no side effects; every
  operation returns `#(State, List(Event), List(OutboundOp))`.
- **`runtime`** — one actor per document connection. Owns the aquamarine
  channel, the kernel state, and subscriber subjects.
- **`wire`** — encoders/decoders for levee's document-channel payloads,
  reusing `spillway/types` and `spillway/message` (`ConnectMessage`,
  `ConnectedMessage`, `SequencedDocumentMessage`) so client and server can't
  drift. If those types need adjustments for client use, upstream them to
  spillway rather than duplicating.

New repo following the water theme, `target = "erlang"`, startest + qcheck to
match spillway/beryl conventions.

## Wire contract (confirmed against `server/lib/levee_web/channels/document_channel.ex`)

| Direction | Event                      | Payload                                                                                       |
| --------- | -------------------------- | --------------------------------------------------------------------------------------------- |
| join      | Phoenix topic `document:{tenant}:{doc}` (colon separator; `/` fails join with `invalid_topic`) | — |
| →         | `connect_document`         | required: `tenantId`, `id` (not `documentId`), `client`, `mode`, `token`; also send `versions` (server negotiates against `["^0.1.0", "^1.0.0"]`); optional `lastSeenSequenceNumber` triggers automatic delta catch-up push |
| ←         | `connect_document_success` | `ConnectedMessage`: `clientId`, `checkpointSequenceNumber`, `initialClients`, `initialMessages` (full in-memory op history, chronological), service config |
| ←         | `connect_document_error`   | `{code, message}` — HTTP-style codes (401 auth, 403 scope, 400 malformed)                      |
| →         | `submitOp`                 | `{clientId, messageBatches: [[DocumentMessage]]}` — max 100 ops per submission (server nacks above that) |
| ←         | `op`                       | `{documentId, op: [SequencedDocumentMessage]}` (keyed by `documentId`, not `clientId`)         |
| →         | `requestOps`               | `{from: sn}` — in-band delta catch-up; response arrives as a normal `op` event                 |
| →         | `noop`                     | `{clientId, referenceSequenceNumber}` — MSN heartbeat                                          |
| ←         | `nack`                     | `{clientId: "", nacks: [{operation, sequenceNumber, content: {code, type, message}}]}`         |

Notes confirmed against the server:

- The Phoenix socket itself is unauthenticated (`user_socket.ex` accepts all
  connections); the JWT rides in the `connect_document` payload. spillway's
  `ConnectMessage.document_id` maps to wire key `id` — the codec needs that
  rename.
- Sequenced ops echo `clientSequenceNumber` back
  (`session_logic.build_sequenced_op`), so acks can be matched exactly by
  `(client_id, csn)`.
- The op stream also carries system types beyond `join`/`leave`/`noop`:
  `summarize`, `summaryAck`, `summaryNack` (and spillway defines
  `propose`/`accept`/etc.). Only `type == "op"` reaches the kernel; everything
  else just advances `last_seen_sn`.

**Document format (the Gleam-only simplification):**
`DocumentMessage.contents = {address: channel_id, contents: map_op}` — one
envelope level, where `map_op` is byte-identical to the TS format:

```json
{ "type": "set", "key": "k", "value": { "type": "Plain", "value": ... } }
{ "type": "delete", "key": "k" }
{ "type": "clear" }
```

Levee sequences contents opaquely, so nothing server-side changes.

## Kernel design

State and transitions, translated from `mapKernel.ts`:

```gleam
pub type MapState {
  MapState(
    sequenced: Dict(String, Json),
    insertion_order: List(String),        // JS-Map-like iteration order
    pending: List(PendingEntry),          // ordered, oldest first
  )
}

pub type PendingEntry {
  PendingLifetime(key: String, sets: List(Json))  // consecutive sets to a key
  PendingDelete(key: String)
  PendingClear
}

pub fn set(state, key, value)    -> #(MapState, List(Event), MapOp)
pub fn delete(state, key)        -> #(MapState, List(Event), MapOp)
pub fn clear(state)              -> #(MapState, List(Event), MapOp)
pub fn get(state, key)           -> Option(Json)   // optimistic overlay read
pub fn apply_remote(state, op)   -> #(MapState, List(Event))
pub fn ack_local(state, op)      -> MapState       // commit pending → sequenced
pub fn entries(state)            -> List(#(String, Json))
```

Decisions baked in:

- **Values are `gleam/json.Json`** for v1 (serializable, structurally
  comparable in tests). A typed generic wrapper can layer on later.
- **Ack matching by CSN at the runtime, FIFO in the kernel.** The TS kernel
  matches acks to pending entries by JS reference identity
  (`pendingEntry === localOpMetadata`) because the Fluid runtime round-trips an
  object reference. An inbound sequenced message is "ours" iff its `client_id`
  matches our connection's — and the server echoes `clientSequenceNumber` back
  on sequenced ops, so the runtime matches acks exactly by `(client_id, csn)`
  against the in-flight queue. Inside the kernel, pop the corresponding head
  pending entry (per-key FIFO for sets within a lifetime, matching the TS
  `shift()` + identity-assert behavior). Assert-fail loudly on CSN or FIFO
  mismatch, same as the TS asserts.
- **Event suppression rules** ported exactly: remote changes masked by local
  pending ops emit nothing; local clear emits `Cleared` plus per-key
  `ValueChanged` events.
- **Insertion-order iteration** via an explicit key-order list, since Gleam
  `Dict` is unordered. Preserves the TS iterator contract: sequenced entries
  first (in insertion order), then un-acked pending lifetimes, with pending
  deletes/clears respected.

## Runtime actor

Messages in: public API calls, aquamarine inbound frames, subscriber
(un)registration. Responsibilities:

1. **Handshake** — join topic, send `connect_document`, hold ops until
   `connect_document_success`, record `client_id` and
   `checkpointSequenceNumber`, then bootstrap from the response's
   `initialMessages` (full history, chronological — no `requestOps(from: 0)`
   round-trip needed). One subtlety, pinned by a test:
   `checkpointSequenceNumber` equals the SN of our *own join message*, which
   arrives as a separate `op` push right after the success event and is *not*
   in `initialMessages` — treat the checkpoint as "already seen" so the join
   push dedupes cleanly.
2. **Outbound** — stamp each op with the next CSN and current last-seen SN as
   RSN (the client half of `spillway/sequencing`'s discipline: CSN strictly
   increasing per connection, RSN ≤ last seen SN), send via `submitOp`, keep
   `#(csn, DocumentMessage)` in an in-flight queue. Cap submissions at the
   server's 100-ops-per-batch limit.
3. **Inbound ordering** — track `last_seen_sn`; **dedupe by SN is a general
   invariant** (drop any op with SN ≤ last_seen_sn), because `initialMessages`
   and catch-up pushes overlap by design. Buffer out-of-order ops; on a gap,
   `requestOps(from: last_seen_sn)`. Route each contiguous op to the kernel
   (`ack_local` for ours, `apply_remote` otherwise); system message types
   (`join`/`leave`/`noop`/`summarize`/`summaryAck`/`summaryNack`) only advance
   `last_seen_sn`.
4. **Reconnect** — on channel close: rejoin and re-handshake (new `client_id`)
   passing `lastSeenSequenceNumber` in `connect_document`, which makes the
   server push delta catch-up automatically (no explicit `requestOps` needed;
   the SN-dedupe invariant absorbs the overlap with `initialMessages`). Then
   resubmit the in-flight queue in order with **fresh CSNs under the new
   client_id** — this is not just safe but required: the server resets
   `last_csn` to 0 on every `client_join`. Remap the in-flight queue so
   ack-matching still works. Before resubmitting, reconcile against the
   catch-up stream: ops from the *old* client_id that already got sequenced
   must be acked, not resubmitted (see nack hazard below). This is the
   trickiest state machine in the project; it gets its own test suite.
5. **Heartbeat** — periodic `noop` with current RSN when idle, so the server's
   MSN advances.
6. **Nacks** — v1 policy: on *any* nack, reconnect and reconcile rather than
   blind-resubmit. The server sequences ops in a batch until the first failure
   and **persists the sequenced prefix to history/storage without broadcasting
   it** (`session.ex` `process_ops`), so those ops reappear via catch-up and a
   naive resubmit (which gets a fresh, higher CSN the server will accept)
   would duplicate them. Reconciliation: catch up, identify which in-flight
   ops landed under the old client_id (match by `clientId` + `csn`), ack
   those, resubmit only the rest. On non-retryable nacks (bad scope, size),
   crash the actor with a descriptive error — supervisor restarts and
   re-syncs. BEAM idiom, avoids silent divergence.
7. **Events** — fan out kernel events to subscriber `Subject(MapEvent)`s.

## Public API sketch

```gleam
let assert Ok(doc) = levee_map.connect(
  url: "ws://localhost:4000/socket",
  tenant: "default", document: "dice", token: jwt,
)
let map = levee_map.root(doc)                    // channel_id "root"
levee_map.set(map, "die", json.int(4))
let value = levee_map.get(map, "die")
let events = levee_map.subscribe(map)            // Subject(MapEvent)
```

## Milestones

**M1 — Kernel (3–5 days).** Pure kernel + unit tests + qcheck properties:
(a) *convergence* — any interleaving of the same sequenced op stream yields
equal state on all clients; (b) *ack transparency* — acking your own ops never
changes the optimistic view; (c) *rebase equivalence* — optimistic view ≡
sequenced state with pending ops replayed. Exit: properties pass at high
iteration counts.

**M2 — Shared test corpus (2–3 days).** A TS harness in the FluidFramework
repo drives the real `MapKernel` (via `SharedMap` + `MockContainerRuntimeFactory`)
through scripted scenarios — set-racing-clear, delete-vs-remote-set,
interleaved acks, multi-key lifetimes, iteration order — and dumps
`{scenario, steps, observations}` JSON. The Gleam test suite replays the same
files against `map_kernel` and asserts identical states, iteration order, and
events. Exit: Gleam kernel matches the TS oracle on every scenario.

> The harness lives on the `feat/map-corpus-harness` branch of the
> FluidFramework workspace checkout, under
> `packages/dds/map/src/test/mocha/corpus/`. Generated corpus JSON is copied
> into this repo (or the new client repo) as test fixtures.

**M3 — Wire + happy-path runtime (4–6 days).** Codecs against
`spillway/message` types; runtime actor doing handshake → submit → ack →
remote-apply against a live levee dev server (`just server`). Exit: two Gleam
clients converge on concurrent edits; integration test in CI.

**M4 — Resilience (4–6 days).** Gap detection + `requestOps` catch-up,
reconnect/resubmit state machine with client_id remap and old-client-id
reconciliation (see nack hazard in the runtime section), nack policy, noop
heartbeat. Test by killing the channel mid-burst — including mid-*batch*, to
exercise the sequenced-but-not-broadcast prefix case — and asserting
convergence + no lost/duplicated ops.

**M5 — Polish + example (3–4 days).** Public API, docs, and a Gleam
dice-roller mirroring `levee-example` — ideally Lustre so the demo is Gleam
end-to-end. Exit: README quick-start works from scratch against `just server`.

Total: **~3–4 weeks**, with M1+M2 de-risking the only semantically hard part
before any networking exists.

## Open questions / risks

Resolved by the 2026-07-01 server-code review (details now baked into the
wire-contract and runtime sections above):

- ~~Exact join-topic and `connect_document` payload shape~~ — confirmed from
  `document_channel.ex` and `leveeDeltaConnection.ts`; see the wire table.
  Still worth extracting into a fixture set the way
  `phoenix_channel_fixtures` does for beryl, so the Gleam client and levee
  test against identical frames.
- ~~`requestOps` bounds~~ — **confirmed and silent**: `get_ops_since` reads
  only the in-memory `op_history`, capped at 1000 ops
  (`@max_history_size`), and truncation is undetectable in-band — old ops are
  filtered out with no error (the only signal is the earliest returned SN
  being > `from + 1`). On session restart, history reloads only post-summary
  deltas. All deltas *do* persist to storage, so the v1 escape hatch for docs
  past 1000 ops is the REST endpoint `GET /deltas/:tenant_id/:id`, not
  "create docs fresh". v1 can ship without it but should assert the
  no-gap-after-bootstrap invariant and fail loudly.
- **Nacked batches partially sequence** — confirmed server behavior, now
  drives the nack policy in the runtime section (reconnect + reconcile, never
  blind-resubmit).

Still open:

- ~~aquamarine reply-matching caveat~~ — validated in M3: the roost codec
  path against real Phoenix works (join reply matching, pushes, receives)
  with no workaround needed. One gotcha found and fixed: Phoenix only
  speaks the V2 array frames roost emits when the websocket URL carries
  `?vsn=2.0.0`.
- ~~M2 harness branch~~ — `feat/map-corpus-harness` exists on the
  FluidFramework workspace checkout with the generator committed; corpus
  fixtures are copied into `test/fixtures/corpus/` here (M2 complete).
- **Multiple maps per document** work naturally via `address`, but v1 ships
  with just the root map to keep the API small.
