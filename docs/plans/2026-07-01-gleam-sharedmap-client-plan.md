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
⚠️ **Superseded (2026-07-02):** a `packages/watershed_core` + `watershed` +
`watershed_js` split was tried, but Gleam git dependencies require a
`gleam.toml` at the repo root and can't target a sub-package, which broke
consuming `watershed` as a git dep. Reverted to a single root `watershed`
package: the pure core, OTP runtime, and JS runtime all ship as modules under
`watershed/`, gated with `@target`. Slimming the JS dependency tree is deferred
to publishing the core as its own repo/package if it's ever needed.
**M6 complete** (2026-07-02): `examples/dice_cli`, an Erlang-target dice CLI
joining the same session as `dice_lustre` through the `watershed` OTP client
API (connect → root → subscribe loop, edits via set/delete). The token gap was
closed the preferred way: `watershed.dev_token` is now public on the erlang
target, matching `watershed_js.dev_token` 1:1 (plus `dev_token_test`).
**M7 complete** (2026-07-02, branch `feat/m7-handles`): Fluid-compatible
handle values and nested SharedMaps, per the detailed companion plan
`2026-07-02-m7-handle-support-plan.md` (see its status header for outcome
notes). Public API: `create_map` (detached until its handle is stored),
`handle_of`, `is_handle`, `resolve` on both targets; handles serialize as the
modern `Plain`-embedded `{"type":"__fluid_handle__","url":"/<address>"}`
marker (byte-frozen against the TS oracle), attach rides an opaque watershed
`attach` op (no levee changes), summaries are multi-channel (blob v2, v1 still
loads), and the kernel needed zero changes — proven by six new oracle corpus
fixtures and five live integration scenarios (nested convergence, recursive
attach closure, reconnect mid-attach, summary v2 bootstrap, multi-channel
`load_version`), all green and stable against `just server`.


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
✅ **Done (2026-07-01):** the `examples/dice_lustre` Lustre SPA is the exit
example; its quick-start was verified from a clean checkout (wiped
`build/node_modules/dist`, `npm install` → `npm run build` → bundle, then the
headless smoke test passed against a fresh `just server`). The
no-gap-after-bootstrap invariant is asserted in `runtime_core.bootstrap` (see
the risk note below).

**M6 — Erlang client example.** ✅ Done (2026-07-02); see the status note at
the top. Original scope: scaffold `examples/dice_cli`, an
Erlang-target (`target = "erlang"`) counterpart to `dice_lustre` that joins the
*same* session (`dev-tenant` / `dice` on `127.0.0.1:4000`) using the existing
`watershed` OTP client API — proving the pure core drives both runtimes over
one document. The client API already exists (`src/watershed.gleam`, all
`@target(erlang)`; mirrors `watershed_js`); the example just wires it into a
runnable program:

- `watershed.connect` → `root` → `subscribe` (returns a `Subject(MapEvent)`, not
  a JS callback) → loop on `process.receive` re-reading optimistic state; edits
  via `set`/`delete` (async sends), reads via `get`/`entries` (blocking calls).
- Use `127.0.0.1`, not `"localhost"` — the Erlang inet resolver stalls ~8s on
  AAAA lookup and levee drops the socket as idle (see `integration_test.gleam`
  L44 note).
- **Token gap:** there is no Erlang `dev_token` in the public API (JS-only via
  `watershed_js.dev_token`). Either copy the HS256 `mint_token`/`base64url`
  helpers from `test/watershed/integration_test.gleam:445-487`, or — preferred —
  promote a public `watershed.dev_token` so the Erlang example matches the JS
  one 1:1.
- Deps: `watershed` (path) + `gleam_stdlib`, `gleam_json`, `gleam_crypto`.
- Exit: with `just server` up and a `dice_lustre` tab open, rolling from the
  Erlang CLI converges in the browser and vice-versa (the `events` subject
  fires on remote rolls).

**M7 — Handle support / nested DDS.** ✅ Done (2026-07-02) — designed and
implemented per `2026-07-02-m7-handle-support-plan.md`, which supersedes the
sketch below (notably: no `Shared` value type — handles are `Plain`-embedded
markers — and the kernel value model stayed bare `Json`). Original scope
follows. Today values
are `Plain` only: the kernel stores opaque `Json` and `wire.plain_value_decoder`
(`wire.gleam:765-771`) rejects any non-`Plain` value, so a value can be an inert
JSON object but never a *collaborative* nested map. This milestone adds Fluid
`{"type": "Shared", ...}` handle values so a SharedMap key can reference another
DDS (another SharedMap first), unlocking real nested/sibling collaborative
structures rather than last-writer-wins JSON blobs.

Scope to design before committing to an estimate:

- **Wire:** encode/decode the `Shared` value variant (an `IFluidHandle` route —
  a serialized handle path, e.g. `{"type":"__fluid_handle__","url":...}`), and
  decide how handles round-trip through the summary blob (`encode_summary_blob`
  currently assumes unwrapped `Plain` `Json`).
- **Kernel/value model:** the value type can no longer be bare `Json` — it must
  distinguish a plain value from a handle to a child channel. Handles bind by
  `address`, so this leans on the same per-map `address` mechanism M6's risk note
  describes for sibling maps (see the "Multiple maps per document" note below).
- **Runtime:** creating/attaching a child DDS means allocating a new `address`,
  routing its ops through the same submit/ack/sequence path, and lazily
  materializing the child map actor when a handle is first resolved.
- **Corpus parity (M2):** extend the TS oracle to emit handle scenarios so the
  Gleam kernel is proven byte-identical on `Shared` values too.
- **Risk:** this is where "out of scope: the full Fluid runtime" (`wire.gleam:766`)
  starts to bite — GC/reference-counting of unreferenced handles and detached
  attach semantics are the genuinely hard parts and may stay v-next.
- Exit: a client can `set(map, key, handle_to(child_map))`, a second client
  resolves the handle and both converge on edits to the *child* map.

Total: **~3–4 weeks** for M1–M5, with M1+M2 de-risking the only semantically hard
part before any networking exists; M6–M7 are post-v1 extensions.

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
  no-gap-after-bootstrap invariant and fail loudly. ✅ **Implemented
  (2026-07-01):** `runtime_core.bootstrap` fails with a new
  `CoreError.HistoryGap` when replaying `initialMessages` leaves ops buffered
  past a gap (i.e. history does not start at SN 1), and both runtimes surface
  it loudly (BEAM panics, JS drives the cell to `Failed`). The live-catch-up
  truncation signal (earliest requestOps SN > `from + 1`) is a runtime/batch
  concern — ordinary ops legitimately arrive out of order in the pure core —
  so it stays out of scope here and is left for the REST escape hatch.
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
- **Summaries / snapshot load** — **IMPLEMENTED** (branch
  `feat/summaries-snapshot-load`). A client `summarize(document)` uploads the
  confirmed SharedMap state as a summary blob (git REST: blob + tree) and
  submits a `summarize` op; on (re)start the server restores `sequence_state`
  from the summary checkpoint, serves only *post-summary* `initialMessages`, and
  returns a `summaryContext {handle, sequenceNumber}` in the connect response.
  `runtime_core.bootstrap` now consumes it: fetch the summary blob by handle,
  seed `map_kernel` + `last_seen_sn = summaryContext.sequenceNumber`, then apply
  the post-summary deltas. Verified end-to-end against levee by
  `summary_bootstrap_test`. Two supporting fixes landed:
  - httpc `Connection: close` header (avoids sequential-request stall) and using
    the IP literal `127.0.0.1` (avoids ~8s inet6 `localhost` resolution stall).
  - **Server-side SN collision**: the levee `summaryAck` is minted at
    `assigned_sn + 1` but the sequencer was not advanced, so the next client op
    reused that SN and bootstrap replay dropped the post-summary delta. Fixed via
    spillway `reserve_sequence_number` (advances the sequence state past the
    ack's slot), wired through levee's `session.ex`.
  v1 requires the summarizing client to be caught up/quiescent (`is_synced`).

  Known follow-on gaps for summaries (post this change):
  - **JS/browser target summarize + snapshot-load** — **IMPLEMENTED** (branch
    `feat/summaries-snapshot-load`). `git_storage.gleam` is now a cross-target
    HTTP seam: shared request builders/decoders/blob codecs, with a target-split
    `send`/`get_json`/`post_json`. The erlang path stays synchronous
    (`gleam_httpc`); the JS path is asynchronous (`gleam_fetch`, returns
    `Promise`). `runtime_js.on_connect_success` awaits `git_storage.fetch_summary`
    when the connect response carries a `summaryContext`, seeding the core from
    the blob at the server-authoritative SN. `runtime_js.summarize/1` +
    `is_synced/1` (exposed on `watershed_js.Document`) upload the confirmed state
    and push a summarize op, mirroring the erlang API (summarize returns a
    `Promise(Result(String, String))`). JS dev-token/connect scopes include
    `summary:write`. Ops that arrive during the async fetch are dropped while
    `Connecting`; the gap they open is self-healing via the post-bootstrap
    `requestOps` catch-up.
  - **Summarize requires a quiescent client** — gated on `is_synced` (in-flight
    empty). No summarize-while-editing; the caller must retry once synced.
  - **Post-summary delta pagination** — **IMPLEMENTED** (branch
    `feat/summaries-snapshot-load`, 2026-07-02). levee serves `initialMessages`
    from its in-memory history capped at 1000 messages, so a document whose
    (post-summary) history outgrows the window arrives missing its prefix.
    `runtime_core.bootstrap` now returns `Bootstrapped`
    (`Complete | MissingPrefix(core, checkpoint, from, to)`) instead of failing:
    the runtime pages the missing range from `GET /deltas/:tenant_id/:id`
    (`git_storage.fetch_deltas`, cross-target: sync httpc / async fetch) and
    feeds it back via `runtime_core.resume_bootstrap`, repeating until
    contiguous — the checkpoint is only applied on completion so buffered ops
    can't be skipped. `HistoryGap` remains as the terminal error for a catch-up
    round that makes no progress (storage genuinely missing the range). Both
    runtimes wire it in (erlang: sync loop in `complete_bootstrap`; JS:
    recursive promise loop in `continue_bootstrap`). Verified by 4 new pure
    tests (fetch-range computation incl. summary seeding, multi-page resume,
    no-progress fatality) and a gated live `large_history_bootstrap_test`
    (1050 ops; server log confirms the fresh client paged `from=0 to=51` over
    REST and converged, incl. keys only present in the aged-out prefix).
  - **getVersions / historical summary selection** — **IMPLEMENTED**
    (2026-07-02, watershed branch `feat/summaries-snapshot-load` + levee branch
    `gleam`). levee already stored one summary record per summarize op; a new
    client-facing `GET /versions/:tenant_id/:id?count=N` (read_access, newest
    first, capped at 100) exposes them, mirroring the deltas endpoint. The
    client gains `git_storage.fetch_versions` (cross-target) plus
    `get_versions(document, count)` and `load_version(document, handle)` on
    both public APIs — `load_version` reads the historical snapshot blob by
    handle (a point-in-time read; entries + captured SN), reusing
    `fetch_summary`. Live bootstrap still consumes the server-authoritative
    latest summary via `summaryContext`. Verified by 4 levee controller tests
    and the gated `summary_versions_test` (two summarize rounds → newest-first
    listing with matching handles, `count` capping, historical reads of both
    snapshots).
