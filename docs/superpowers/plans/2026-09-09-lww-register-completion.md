# LWWRegister Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the standalone string-valued LWWRegister by exposing its sequenced and peer-to-peer public APIs, adding Sluice and relay lifecycle coverage, wiring Lustre effects, proving the kernel with an independent fuzz oracle, and documenting the finished feature.

**Architecture:** Keep the shipped `lww_register_kernel`, channel, wire, runtime-core, digest, persistence, and website implementation unchanged. Add thin type-specific facades that delegate every state transition to the existing core, then use the established GCounter and MvRegister integration patterns for typed handles, subscriptions, effects, test drivers, and replayable fuzzing. Preserve the register's timestamp and winning author as replicated metadata even when the visible string does not change.

**Tech Stack:** Gleam on Erlang and JavaScript, `lattice_registers >= 1.1.0 and < 2.0.0`, startest, qcheck, Sluice, the CRDT simulator, the real Node relay harness, Lustre effects, and the existing Trellis/Just validation commands.

**Spec:** `docs/superpowers/specs/2026-09-09-lattice-dds-expansion-design.md`

**Current state:** Commits `60d91ab` and `2a22e0a` completed the clock, kernel, channel, wire, runtime-core, digest, persistence, and anti-entropy work. Commit `5a30796` completed the website demo. This plan starts at the public facade boundary and does not repeat those tasks.

## Global Constraints

- Keep all dependencies on Hex; do not introduce local-path dependencies.
- Keep `lattice_registers = ">= 1.1.0 and < 2.0.0"` unchanged.
- Preserve existing channel tags, operation formats, and public behavior.
- Support sequenced APIs on Erlang and JavaScript; do not add a BEAM p2p driver.
- Keep register values as `String` in this release.
- Keep mutation errors observable through `Result`; do not use fire-and-forget APIs for LWWRegister writes.
- The public API supplies the runtime wall clock. Callers do not supply timestamps.
- A local write uses `max(wall_clock, last_seen + 1)` through the existing kernel.
- Equal timestamps resolve by replica ID. Do not reproduce that merge rule outside the kernel or the independent test oracle.
- A same-value write still creates and replicates newer metadata but emits no visible-value event.
- Summary/import paths preserve winner metadata and restore `last_seen`; a joining client keeps its own local writer identity.
- Lustre callbacks must dispatch through the existing microtask helpers. Effect construction must not mutate document state.
- Do not modify website files or `website/src/generated/snippets.json`.
- Do not stage unrelated `apm.yml` or `apm.lock.yaml` changes.

---

### Task 1: Expose the JavaScript sequenced facade and typed fields

**Files:**
- Modify: `src/watershed/schema.gleam`
- Modify: `src/watershed/runtime.gleam`
- Modify: `src/watershed.gleam`
- Modify: `test/watershed/schema_test.gleam`
- Create: `test/watershed/sluice/lww_register_js_test.gleam`

**Interfaces:**
- Consumes: `runtime_core.lww_register_set(Core, String, String, Int) -> Result(#(Core, EditOutcome), RuntimeError)` and `runtime_core.lww_register_value(Core, String) -> Result(String, Nil)`.
- Produces: `schema.LwwRegisterChannel`, opaque `watershed.LwwRegister`, create/resolve/handle/read/write/subscription functions, and JavaScript callback-based typed `ensure_lww_register`.

- [ ] **Step 1: Add compile-failing schema and public-facade tests**

Add the phantom-type test to `test/watershed/schema_test.gleam`:

```gleam
pub fn lww_register_channel_field_test() -> Nil {
  let field: schema.ChannelField(Nil, schema.LwwRegisterChannel) =
    schema.channel_field("status")
  schema.channel_field_key(field) |> expect.to_equal("status")
}
```

Create `test/watershed/sluice/lww_register_js_test.gleam` using `mv_register_js_test.gleam` as the fixture pattern. Add tests with these exact behaviors:

```gleam
@target(javascript)
pub fn public_lww_register_create_resolve_write_and_subscribe_test() -> Nil {
  // Connect A and B, create on A, store the handle in a typed root field,
  // resolve on B, write "first" then "second", and assert both read Ok("second").
  // Capture Changed("", "first") and Changed("first", "second").
  // Write "second" again and assert the event list does not grow.
}

@target(javascript)
pub fn ensure_lww_register_waits_and_adopts_test() -> Nil {
  // Assert the callback is empty before sluice.settle/advance.
  // Create through ensure on A, write "ready", then ensure on B.
  // Assert both handles encode to the same address and B reads Ok("ready").
}

@target(javascript)
pub fn reconnect_preserves_pending_lww_write_test() -> Nil {
  // Drop A, write "offline" on A, write "online" on B, rejoin A,
  // settle, and assert both replicas converge without restamping A's operation.
}

@target(javascript)
pub fn lww_register_wrong_kind_handle_fails_reads_and_writes_test() -> Nil {
  // Resolve the root map handle as an LWW register using the normal handle
  // convention, then assert value and set return errors rather than defaults.
}
```

- [ ] **Step 2: Run the new JavaScript tests and confirm the API is missing**

Run:

```bash
rtk gleam test --target javascript -- schema lww_register_js
```

Expected: compilation fails because `schema.LwwRegisterChannel` and the public LWWRegister functions do not exist.

- [ ] **Step 3: Add the schema marker and JavaScript runtime operations**

In `src/watershed/schema.gleam`, add beside the other scalar channel phantom types:

```gleam
/// A string cell whose greatest timestamp and replica ID select one winner.
pub type LwwRegisterChannel
```

In `src/watershed/runtime.gleam`, add:

```gleam
@target(javascript)
pub fn lww_register_set(
  runtime: Runtime,
  address: String,
  value: String,
) -> Result(Nil, String) {
  edit_sequence_with_result(runtime.cell, fn(core) {
    runtime_core.lww_register_set(
      core,
      address,
      value,
      transport_js.now_milliseconds(),
    )
  })
}

@target(javascript)
pub fn lww_register_value(
  runtime: Runtime,
  address: String,
) -> Result(String, Nil) {
  read(runtime.cell, Error(Nil), runtime_core.lww_register_value(_, address))
}

@target(javascript)
pub fn create_lww_register(runtime: Runtime) -> Result(String, String) {
  create_channel(runtime, channel.InitLwwRegister, "create_lww_register")
}
```

Use `edit_sequence_with_result`; do not use `edit`, because clock and channel failures must reach the caller.

- [ ] **Step 4: Add the JavaScript facade type and operations**

In `src/watershed.gleam`, import `watershed/lww_register_kernel`, then add:

```gleam
@target(javascript)
pub opaque type LwwRegister {
  LwwRegister(runtime: runtime.Runtime, address: String)
}

@target(javascript)
pub fn create_lww_register(
  document: Document(root),
) -> Result(LwwRegister, String)

@target(javascript)
pub fn lww_register_handle_of(register: LwwRegister) -> Json

@target(javascript)
pub fn resolve_lww_register(
  document: Document(root),
  value: Json,
) -> Result(LwwRegister, String)

@target(javascript)
pub fn lww_register_set(
  register: LwwRegister,
  value: String,
) -> Result(Nil, String)

@target(javascript)
pub fn lww_register_value(
  register: LwwRegister,
) -> Result(String, Nil)

@target(javascript)
pub fn subscribe_lww_register(
  register: LwwRegister,
  handler: fn(lww_register_kernel.LwwRegisterEvent) -> Nil,
) -> SubscriptionToken
```

Follow `GCounter` for create/resolve/handle mechanics and `subscribe_mv_register` for the event filter. The subscription must return `Some(inner)` only for `channel.LwwRegisterEvent(inner)`.

- [ ] **Step 5: Add JavaScript typed field helpers**

Add:

```gleam
@target(javascript)
pub fn set_lww_register_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.LwwRegisterChannel),
  register: LwwRegister,
) -> Nil

@target(javascript)
pub fn resolve_lww_register_field(
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.LwwRegisterChannel),
) -> Result(Option(LwwRegister), String)

@target(javascript)
pub fn ensure_lww_register(
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.LwwRegisterChannel),
  done: fn(Result(LwwRegister, String)) -> Nil,
) -> Nil
```

Implement them with `put_channel_field`, `get_channel_field`, and `ensure_channel`, matching the existing GCounter functions. Preserve the facade's current handle convention: resolution validates the handle marker and address; read or mutation reports a channel-kind mismatch.

- [ ] **Step 6: Make every event narrowing match exhaustive**

Search `src/watershed.gleam` for matches on `channel.ChannelEvent`. Add `channel.LwwRegisterEvent(_) -> None` to unrelated subscriptions and the positive `Some(inner)` branch to `subscribe_lww_register`. Do not combine the positive branch into a catch-all.

- [ ] **Step 7: Run the JavaScript facade tests**

Run:

```bash
rtk gleam test --target javascript -- schema lww_register_js
rtk gleam format --check src test
```

Expected: the focused schema and Sluice tests pass, and formatting reports no changes.

- [ ] **Step 8: Commit the JavaScript facade**

```bash
rtk git add src/watershed/schema.gleam src/watershed/runtime.gleam src/watershed.gleam test/watershed/schema_test.gleam test/watershed/sluice/lww_register_js_test.gleam
rtk git commit -m "feat: expose LWWRegister JavaScript API"
```

---

### Task 2: Expose the BEAM sequenced facade

**Files:**
- Modify: `src/watershed/runtime_beam.gleam`
- Modify: `src/watershed_beam.gleam`
- Create: `test/watershed/sluice/lww_register_test.gleam`

**Interfaces:**
- Consumes: `schema.LwwRegisterChannel` and the sequenced runtime-core operations from Task 1.
- Produces: BEAM request/reply create, write, read, resolve, typed field, ensure, and subject-based subscription APIs.

- [ ] **Step 1: Write the failing BEAM Sluice tests**

Create `test/watershed/sluice/lww_register_test.gleam`, following `mv_register_test.gleam`. Add:

```gleam
@target(erlang)
pub fn public_lww_register_ensure_write_subscribe_and_reconnect_test() -> Nil {
  // Spawn ensure_lww_register because the BEAM call waits for sequencing.
  // Resolve the typed handle on B, subscribe on A, then write from A and B.
  // Assert subject events and converged reads. Drop/rejoin B and assert its
  // pending write is retained and converges after reconnect.
}

@target(erlang)
pub fn public_lww_register_simultaneous_ensures_share_one_field_test() -> Nil {
  // Start ensure on A and B concurrently, settle the rig, and assert both
  // resolved handles encode to the same address.
}

@target(erlang)
pub fn public_lww_register_same_value_write_emits_no_event_test() -> Nil {
  // Write "ready", drain the first event, write "ready" again, settle,
  // assert the read succeeds and process.receive(subject, 0) is Error(Nil).
}
```

- [ ] **Step 2: Run the BEAM test and confirm the API is missing**

```bash
rtk gleam test --target erlang -- lww_register_test
```

Expected: compilation fails on missing `watershed_beam` LWWRegister symbols.

- [ ] **Step 3: Add BEAM runtime messages**

In `src/watershed/runtime_beam.gleam`, add these `Message` variants:

```gleam
SetLwwRegister(
  address: String,
  value: String,
  reply: Subject(Result(Nil, String)),
)
GetLwwRegisterValue(
  address: String,
  reply: Subject(Result(String, Nil)),
)
CreateLwwRegister(reply: Subject(Result(String, String)))
```

Handle them with:

```gleam
SetLwwRegister(address, value, reply) ->
  edit_sequence_with_result(state, reply, fn(core) {
    runtime_core.lww_register_set(
      core,
      address,
      value,
      now_milliseconds(),
    )
  })

GetLwwRegisterValue(address, reply) -> {
  process.send(
    reply,
    read(state, Error(Nil), runtime_core.lww_register_value(_, address)),
  )
  actor.continue(state)
}

CreateLwwRegister(reply) ->
  create_channel(state, reply, InitLwwRegister, "create_lww_register")
```

Do not make `SetLwwRegister` fire-and-forget.

- [ ] **Step 4: Add the BEAM facade type and operations**

In `src/watershed_beam.gleam`, add the opaque type and public functions:

```gleam
@target(erlang)
pub opaque type LwwRegister {
  LwwRegister(runtime: process.Subject(runtime_beam.Msg), address: String)
}

@target(erlang)
pub fn create_lww_register(
  document: Document(root),
) -> Result(LwwRegister, String)

@target(erlang)
pub fn lww_register_handle_of(register: LwwRegister) -> Json

@target(erlang)
pub fn resolve_lww_register(
  document: Document(root),
  value: Json,
) -> Result(LwwRegister, String)

@target(erlang)
pub fn lww_register_set(
  register: LwwRegister,
  value: String,
) -> Result(Nil, String)

@target(erlang)
pub fn lww_register_value(
  register: LwwRegister,
) -> Result(String, Nil)

@target(erlang)
pub fn subscribe_lww_register(
  register: LwwRegister,
) -> Subject(lww_register_kernel.LwwRegisterEvent)
```

Use `process.call` for create, set, and read. Use `subscribe_narrowed` for events.

- [ ] **Step 5: Add the BEAM typed field helpers**

Add `set_lww_register_field`, `resolve_lww_register_field`, and:

```gleam
@target(erlang)
pub fn ensure_lww_register(
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.LwwRegisterChannel),
) -> Result(LwwRegister, String)
```

Match the synchronous `ensure_g_counter` implementation. Update all BEAM event-filtering matches so `LwwRegisterEvent` is handled explicitly.

- [ ] **Step 6: Run both sequenced facade suites**

```bash
rtk gleam test --target erlang -- lww_register_test
rtk gleam test --target javascript -- lww_register_js
rtk gleam format --check src test
```

Expected: both target-specific Sluice suites pass.

- [ ] **Step 7: Commit the BEAM facade**

```bash
rtk git add src/watershed/runtime_beam.gleam src/watershed_beam.gleam test/watershed/sluice/lww_register_test.gleam
rtk git commit -m "feat: expose LWWRegister BEAM API"
```

---

### Task 3: Expose the peer-to-peer CRDT API and prove mesh lifecycle behavior

**Files:**
- Modify: `src/watershed/p2p.gleam`
- Modify: `src/watershed/crdt_js.gleam`
- Modify: `test/watershed/crdt_core_test.gleam`
- Modify: `test/watershed/p2p_lifecycle_test.gleam`

**Interfaces:**
- Consumes: `channel.InitLwwRegister`, `channel.LwwRegisterSetEdit(value, timestamp)`, and the completed CRDT-core snapshot/digest/anti-entropy support.
- Produces: `p2p.lww_register_root`, typed `crdt_js` set/read/subscribe functions, and lifecycle coverage through the public browser facade.

- [ ] **Step 1: Write failing CRDT facade tests**

Add focused JavaScript tests that use `p2p_fake`/the existing CRDT simulator rather than calling the kernel directly:

```gleam
pub fn lww_register_public_mesh_converges_concurrent_writes_test() -> Nil {
  // Create A and B from p2p.lww_register_root(), attach both, write distinct
  // strings before settling the mesh, then assert both public reads and
  // digests converge. Equal-timestamp tie-breaking remains pinned by the
  // kernel/channel tests, where the timestamp can be supplied directly.
}

pub fn lww_register_same_value_newer_metadata_crosses_three_peer_chain_test() -> Nil {
  // A -> B -> C chain. Write one value, synchronize, then write the same value
  // at a newer logical timestamp. Assert no Changed event on B/C, but exported
  // digests change and all three digests converge after anti-entropy.
}

pub fn lww_register_late_join_and_import_preserve_author_and_clock_test() -> Nil {
  // Join C after a winner exists. Assert C reads the winner. Make C write with
  // a wall clock lower than the imported timestamp and assert its operation is
  // still newer and identifies C as author after convergence.
}

pub fn lww_register_duplicate_and_reordered_delivery_is_idempotent_test() -> Nil {
  // Deliver the same delta twice and race the two delivery orders. Assert one
  // visible event per value change and identical final digests.
}

pub fn lww_register_wrong_kind_and_closed_document_fail_test() -> Nil {
  // Reinterpret a non-LWW handle through the existing test seam and assert
  // ChannelTypeMismatch; close a valid document and assert DocumentClosed for
  // both lww_register_value and lww_register_set.
}
```

- [ ] **Step 2: Run the focused JavaScript tests and confirm missing symbols**

```bash
rtk gleam test --target javascript -- crdt_core p2p_lifecycle
```

Expected: compilation fails because `lww_register_root` and the `crdt_js` functions are missing.

- [ ] **Step 3: Add the typed p2p root**

In `src/watershed/p2p.gleam`, add:

```gleam
/// The root kind for a peer-to-peer last-writer-wins register document.
pub fn lww_register_root() -> CrdtKind(schema.LwwRegisterChannel) {
  CrdtKind(channel.InitLwwRegister)
}
```

- [ ] **Step 4: Add CRDT mutation, read, and subscription functions**

In `src/watershed/crdt_js.gleam`, import `watershed/lww_register_kernel` and add:

```gleam
@target(javascript)
pub fn lww_register_set(
  handle: Handle(schema.LwwRegisterChannel),
  value: String,
) -> Result(Nil, P2pError) {
  mutate(
    handle,
    channel.LwwRegisterSetEdit(value, transport_js.now_milliseconds()),
  )
}

@target(javascript)
pub fn lww_register_value(
  handle: Handle(schema.LwwRegisterChannel),
) -> Result(String, P2pError)

@target(javascript)
pub fn subscribe_lww_register(
  handle: Handle(schema.LwwRegisterChannel),
  handler: fn(lww_register_kernel.LwwRegisterEvent) -> Nil,
) -> Subscription
```

For reads, call the existing `read(handle, channel.LwwRegisterChannel, reader)` helper. That helper reports `ChannelTypeMismatch` before the reader runs; the reader extracts `lww_register_kernel.value` from `channel.LwwRegisterState`. The subscription returns `Some(inner)` only for `channel.LwwRegisterEvent(inner)`.

- [ ] **Step 5: Update exhaustive CRDT state and event matches**

Run the compiler and update every closed `ChannelState` or `ChannelEvent` match in `crdt_js.gleam`. Unrelated readers keep their existing unreachable fallback convention after `read` verifies the channel type. Do not add a user-visible default to `lww_register_value`.

- [ ] **Step 6: Run the mesh and lifecycle tests on JavaScript**

```bash
rtk gleam test --target javascript -- crdt_core p2p_lifecycle
rtk gleam test --target javascript -- lww_register_channel crdt_wire wire
rtk gleam format --check src test
```

Expected: public reads, writes, subscriptions, snapshot import, duplicate delivery, digest convergence, and close/type errors pass.

- [ ] **Step 7: Commit the peer-to-peer facade**

```bash
rtk git add src/watershed/p2p.gleam src/watershed/crdt_js.gleam test/watershed/crdt_core_test.gleam test/watershed/p2p_lifecycle_test.gleam
rtk git commit -m "feat: expose LWWRegister peer API"
```

---

### Task 4: Add real relay lifecycle coverage

**Files:**
- Modify: `test/watershed/relay_integration.gleam`
- Modify: `tools/relay/test.mjs`

**Interfaces:**
- Consumes: `p2p.lww_register_root`, `crdt_js.lww_register_set`, `crdt_js.lww_register_value`, `crdt_js.subscribe_lww_register`, and the existing real relay/signaling process harness.
- Produces: a typed LWWRegister relay client and an end-to-end scenario that proves fallback, replay, restart, and late-join behavior over the shipped relay protocol.

- [ ] **Step 1: Add a failing Node relay scenario**

Extend `tools/relay/test.mjs` with a new room and assertions that call LWW-specific harness exports:

```js
const lwwA = relay.start_lww(
  harness,
  "auto",
  lwwRoom,
  "a",
  signalingUrl,
  relayUrl,
);
const lwwB = relay.start_lww(
  harness,
  "auto",
  lwwRoom,
  "b",
  signalingUrl,
  relayUrl,
);

relay.lww_set(lwwA, "first");
// Settle sockets/mesh with the existing condition-based helpers.
assert.equal(relay.lww_value(lwwB), "first");
```

Continue the scenario through relay outage, one offline write on each client, relay restart, replay, and a late client. Assert final values and digests converge, and assert a post-import write by the late client succeeds.

- [ ] **Step 2: Run the relay test and confirm missing harness exports**

```bash
rtk just relay-test
```

Expected: the Node scenario fails because `start_lww`, `lww_set`, and `lww_value` do not exist.

- [ ] **Step 3: Add a parallel typed LWW client to the Gleam harness**

Keep the existing PN-counter `Client` unchanged. Add:

```gleam
@target(javascript)
pub type LwwClient {
  LwwClient(
    document: CrdtDocument(schema.LwwRegisterChannel),
    connection: CrdtConnection,
    statuses: Cell(List(String)),
    readies: Cell(List(String)),
    events: Cell(List(String)),
  )
}
```

Add `start_lww` by copying only the generic connection setup from `start_with_deadline`, changing the root to `p2p.lww_register_root()` and subscribing through `crdt_js.subscribe_lww_register`. Render events as `previous <> "->" <> value`.

Add plain JS-facing helpers:

```gleam
@target(javascript)
pub fn lww_set(client: LwwClient, value: String) -> String

@target(javascript)
pub fn lww_value(client: LwwClient) -> String

@target(javascript)
pub fn lww_digest(client: LwwClient) -> String

@target(javascript)
pub fn lww_events(client: LwwClient) -> List(String)
```

Return the existing rendered error string from `lww_set` on failure; do not throw inside the harness.

- [ ] **Step 4: Complete the relay scenario**

Cover these observable states with the existing process-management helpers in `tools/relay/test.mjs`:

1. `Auto` without a relay remains usable through p2p fallback.
2. Both clients attach when the relay appears.
3. A confirmed register value survives checkpoint/reconnect.
4. Writes made during relay outage replay after restart.
5. Replayed and duplicate envelopes do not create duplicate visible events.
6. A late client converges on the same value and digest.
7. The late client's next local write becomes the winner and reaches the other clients.

Do not change the relay protocol, envelope version, or server implementation.

- [ ] **Step 5: Run the real relay gate**

```bash
rtk just relay-test
```

Expected: the existing PN-counter scenario and the new LWWRegister scenario both pass.

- [ ] **Step 6: Commit relay coverage**

```bash
rtk git add test/watershed/relay_integration.gleam tools/relay/test.mjs
rtk git commit -m "test: cover LWWRegister relay lifecycle"
```

---

### Task 5: Add sequenced and CRDT Lustre effects

**Files:**
- Modify: `watershed_lustre/src/watershed_lustre.gleam`
- Modify: `watershed_lustre/src/watershed_lustre/crdt.gleam`
- Modify: `watershed_lustre/test/watershed_lustre_test.gleam`
- Modify: `watershed_lustre/test/watershed_lustre/crdt_test.gleam`

**Interfaces:**
- Consumes: JavaScript sequenced facade functions from Task 1 and peer-to-peer functions from Task 3.
- Produces: deferred sequenced ensure/subscription effects and a deferred CRDT subscription effect. Writes continue to use the existing generic `crdt.perform` thunk.

- [ ] **Step 1: Add failing effect tests**

Extend the existing Lustre suites with tests named for these contracts:

```gleam
pub fn lww_register_sequenced_subscription_dispatches_on_a_microtask_test() -> Promise(Nil)
pub fn ensure_lww_register_does_not_mutate_during_update_test() -> Promise(Nil)
pub fn lww_register_crdt_subscription_and_write_are_lazy_test() -> Promise(Nil)
pub fn lww_register_same_value_write_dispatches_outcome_without_change_test() -> Promise(Nil)
pub fn lww_register_unsubscribe_stops_later_events_test() -> Promise(Nil)
```

For every test:

- construct the effect and assert the message sink is empty;
- call `effect.perform`;
- assert synchronous callbacks have still not reached the sink;
- drain microtasks with the suite's `promise.wait(0)` helper;
- assert the exact `Changed(previous_value, value)`, subscription handle, or `Result` messages;
- use a real solo CRDT document or Sluice rig, not a mocked kernel.

- [ ] **Step 2: Run the Lustre suite and confirm missing wrappers**

```bash
cd watershed_lustre
rtk gleam test --target javascript
cd ..
```

Expected: compilation fails on missing LWWRegister effect functions.

- [ ] **Step 3: Add sequenced effect wrappers**

In `watershed_lustre/src/watershed_lustre.gleam`, import `watershed/lww_register_kernel` and add:

```gleam
pub fn subscribe_lww_register(
  register: watershed.LwwRegister,
  to_msg to_msg: fn(lww_register_kernel.LwwRegisterEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let _ =
    watershed.subscribe_lww_register(register, fn(event) {
      queue_microtask(fn() { dispatch(to_msg(event)) })
    })
  Nil
}

pub fn ensure_lww_register(
  document: watershed.Document(root),
  typed_map: watershed.TypedMap(s),
  field: schema.ChannelField(s, schema.LwwRegisterChannel),
  to_msg to_msg: fn(Result(watershed.LwwRegister, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed.ensure_lww_register(document, typed_map, field, fn(outcome) {
    queue_microtask(fn() { dispatch(to_msg(outcome)) })
  })
}
```

- [ ] **Step 4: Add the CRDT subscription wrapper**

In `watershed_lustre/src/watershed_lustre/crdt.gleam`, add:

```gleam
pub fn subscribe_lww_register(
  handle: Handle(schema.LwwRegisterChannel),
  subscribed subscribed: fn(Subscription) -> msg,
  event event: fn(lww_register_kernel.LwwRegisterEvent) -> msg,
) -> Effect(msg) {
  subscribe(crdt_js.subscribe_lww_register(handle, _), subscribed, event)
}
```

Use the existing generic write effect:

```gleam
crdt.perform(
  fn() { crdt_js.lww_register_set(register, "ready") },
  Outcome,
)
```

Do not add a type-specific write wrapper.

- [ ] **Step 5: Run and format the Lustre package**

```bash
cd watershed_lustre
rtk gleam test --target javascript
rtk gleam format --check src test
cd ..
```

Expected: all existing and new Lustre tests pass.

- [ ] **Step 6: Commit the Lustre bindings**

```bash
rtk git add watershed_lustre/src/watershed_lustre.gleam watershed_lustre/src/watershed_lustre/crdt.gleam watershed_lustre/test/watershed_lustre_test.gleam watershed_lustre/test/watershed_lustre/crdt_test.gleam
rtk git commit -m "feat: add LWWRegister Lustre effects"
```

---

### Task 6: Add the independent fuzz model and planted faults

**Files:**
- Create: `test/watershed/fuzz/lww_register_model.gleam`
- Create: `test/watershed/lww_register_fuzz_test.gleam`
- Modify: `test/watershed/fuzz_replay_test.gleam`

**Interfaces:**
- Consumes: the complete pure `lww_register_kernel` lifecycle.
- Produces: a replayable `KernelModel`, an oracle independent of Lattice merge, generated convergence coverage, deterministic causal scripts, and tests proving that author-retention and clock-restoration faults are detectable.

- [ ] **Step 1: Define the model command and observation in a failing test import**

In `lww_register_fuzz_test.gleam`, import the not-yet-created model and require:

```gleam
pub type LwwCommand {
  LwwCommand(
    value: String,
    wall_clock: Int,
    timestamp: Option(Int),
    delta: Option(lww_register.LWWRegister(String)),
  )
}

pub type Observation {
  Observation(value: String, timestamp: Int, author: String)
}
```

Add tests for operation JSON round trips with both empty and filled timestamp/delta slots.

- [ ] **Step 2: Run the fuzz selector and confirm the model is missing**

```bash
rtk gleam test --target erlang -- lww_register_fuzz
```

Expected: compilation fails because `watershed/fuzz/lww_register_model` does not exist.

- [ ] **Step 3: Implement command generation and JSON codecs**

Create `lww_register_model.gleam`. Generate short strings and wall clocks that include:

- repeated visible values;
- equal clocks across clients;
- clocks lower than previously observed values;
- `0` and small positive timestamps that shrink well.

Encode commands as:

```json
{
  "value": "ready",
  "wall_clock": 7,
  "timestamp": 8,
  "delta": "<stringified lattice envelope>"
}
```

Use `null` for unfilled `timestamp` and `delta`. Decode the Lattice envelope with `lww_register.from_json`; reject malformed filled deltas.

- [ ] **Step 4: Implement the kernel adapter**

Implement `KernelModel` functions with these rules:

- `init(id)` calls `lww_register_kernel.new(replica_id.new("client-" <> int.to_string(id)))`;
- `submit` calls `lww_register_kernel.set(state, value, wall_clock)` and rewrites the routed command with the returned timestamp and delta;
- `apply_remote` reconstructs `lww_register_kernel.Set(value, timestamp, delta)` and calls `apply_remote`;
- `ack_local` calls `ack_local` with the reconstructed operation;
- `rollback` reads the newest pending message ID and calls `rollback`;
- `apply_stashed` calls `apply_stashed_operation` with the original operation, never `set`, so it cannot restamp;
- `load_from_synced` serializes `summary` and calls `from_summary` with the joining client's replica ID;
- `check` is `Some(lww_register_kernel.check_cache_coherence)`.

- [ ] **Step 5: Implement the independent oracle**

Do not call `lww_register.merge`, `lww_register.value`, `lww_register.to_json` on expected state, or a production digest helper. Fold the sequenced log and choose the greatest literal pair:

```text
(timestamp, "client-" <> client_id)
```

Use timestamp first and author string second. Return `Observation(value, timestamp, author)`. Keep metadata in the observation so a same-value newer write is not mistaken for no change.

The production observation may decode `state.value`, `state.timestamp`, and `state.replica_id` from `json.to_string(lww_register_kernel.summary(state))`; the expected oracle must derive them only from routed command fields and log authors.

- [ ] **Step 6: Add generated and deterministic lifecycle tests**

Add:

```gleam
pub fn lww_register_generated_convergence_test() -> Nil
pub fn lww_register_causal_scripts_test() -> Nil
pub fn lww_register_operation_json_round_trip_test() -> Nil
pub fn lww_register_oracle_tracks_metadata_only_writes_test() -> Nil
```

Configure three clients and nonzero rollback/stashed-operation weights. Deterministic scripts must cover:

1. concurrent equal-time writes delivered in both orders;
2. a same-value newer write;
3. a lower wall clock after summary import;
4. rollback followed by another local write;
5. stash replay without a new timestamp;
6. disconnect, write, reconnect, and resubmit;
7. late client addition;
8. duplicate remote delivery.

- [ ] **Step 7: Add the author-retention planted fault**

Construct a buggy `KernelModel` whose load path rebuilds local state using the winning author's replica ID instead of the joining client's ID. Run a script where client A establishes a winner, client B loads it, then B writes. Assert `kernel_fuzz.try_run_script` returns `Error(_)`.

The test must fail if the harness cannot distinguish the faulty model:

```gleam
case kernel_fuzz.try_run_script(buggy, 3, script) {
  Error(_) -> Nil
  Ok(_) -> panic as "expected winner-author reuse to fail the harness"
}
```

- [ ] **Step 8: Add the clock-reset planted fault**

Construct a buggy load path that preserves the register value but resets `last_seen` to `0`. Use a confirmed timestamp greater than the next generated wall clock, then make the joining client write. Require `try_run_script` to fail because the new operation does not advance beyond imported metadata.

- [ ] **Step 9: Register model replay support**

In `test/watershed/fuzz_replay_test.gleam`, import `watershed/fuzz/lww_register_model` and add:

```gleam
"lww_register" -> replay_with(lww_register_model.model(), content, path)
```

- [ ] **Step 10: Run both-target kernel and fuzz validation**

```bash
rtk gleam test --target erlang -- lww_clock lww_register_kernel lww_register_fuzz fuzz_replay
rtk gleam test --target javascript -- lww_clock lww_register_kernel lww_register_fuzz fuzz_replay
rtk gleam format --check src test
```

Expected: generated runs converge, deterministic scripts pass, both planted faults are detected, and replay dispatch recognizes `lww_register`.

- [ ] **Step 11: Commit the model**

```bash
rtk git add test/watershed/fuzz/lww_register_model.gleam test/watershed/lww_register_fuzz_test.gleam test/watershed/fuzz_replay_test.gleam
rtk git commit -m "test: fuzz LWWRegister lifecycle"
```

---

### Task 7: Document and validate the complete LWWRegister

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/plans/2026-09-09-lww-register-dds.md`
- Verify: all files changed by Tasks 1-6

**Interfaces:**
- Consumes: the completed sequenced, peer-to-peer, relay, Lustre, and fuzz APIs.
- Produces: user-facing guidance, an accurate shipped-status record, and final evidence that the feature works on both targets.

- [ ] **Step 1: Add README examples and semantics**

Add LWWRegister beside GCounter and MvRegister:

```gleam
let assert Ok(status) = watershed.create_lww_register(document)
let assert Ok(Nil) = watershed.lww_register_set(status, "ready")
watershed.lww_register_value(status)
// Ok("ready")
```

Document these points in normal repository prose:

- the initial value is `""`;
- values are strings in this release;
- each write combines wall-clock milliseconds with a monotone logical clock;
- the greatest timestamp wins and replica ID breaks equal timestamps;
- writing the current value can advance replicated metadata without a visible event;
- typed fields use `schema.LwwRegisterChannel` and `ensure_lww_register`;
- p2p documents use `p2p.lww_register_root()`;
- browser CRDT writes use `crdt_js.lww_register_set`;
- this single-value CRDT is distinct from the consensus register collection and from per-key LWWMap behavior.

- [ ] **Step 2: Mark the original implementation plan accurately**

Update `docs/superpowers/plans/2026-09-09-lww-register-dds.md`:

- mark Tasks 1 and 2 shipped with commits `60d91ab` and `2a22e0a`;
- point Tasks 3 and 4 to this completion plan;
- remove the stale statement that implementation has not started;
- record the website demo commit `5a30796` as completed follow-up work, without adding website work to the remaining scope.

- [ ] **Step 3: Run targeted sequenced and CRDT suites**

```bash
rtk gleam test --target erlang -- schema lww_register_channel lww_register_test runtime_core crdt_core p2p_lifecycle
rtk gleam test --target javascript -- schema lww_register_channel lww_register_js runtime_core crdt_core p2p_lifecycle
```

Expected: all focused API, lifecycle, and core regression tests pass.

- [ ] **Step 4: Run binding, relay, and fuzz gates**

```bash
cd watershed_lustre
rtk gleam test --target javascript
cd ..
rtk just relay-test
rtk just fuzz
```

Expected: Lustre tests, real relay lifecycle, and the full fuzz sweep pass.

- [ ] **Step 5: Run repository validation**

```bash
rtk just format
rtk just lint
rtk just test
rtk just build
rtk git diff --check
```

Expected: every command exits zero. If the known `smoke/runtime_bootstrap.mjs` failure (`Missing HTTP request /trees/`) still occurs on unmodified `main`, record it as a baseline failure; do not change unrelated runtime-bootstrap code in this feature.

- [ ] **Step 6: Review scope and generated files**

```bash
rtk git status --short
rtk git diff --stat
```

Confirm that:

- no website file changed;
- no generated snippet manifest is staged;
- `apm.yml` and `apm.lock.yaml` remain unstaged;
- channel tags and wire formats did not change;
- every public write remains fallible;
- both planted-fault tests fail when their fault is present and pass for the production model.

- [ ] **Step 7: Commit documentation and status**

```bash
rtk git add README.md docs/superpowers/plans/2026-09-09-lww-register-dds.md
rtk git commit -m "docs: complete LWWRegister integration"
```

## Completion Criteria

LWWRegister is complete only when all of the following are true:

1. JavaScript and BEAM sequenced consumers can create, resolve, store, ensure, read, write, and subscribe through typed public APIs.
2. JavaScript peer-to-peer consumers can create an LWWRegister root, read, write, and subscribe through `crdt_js`.
3. Equal-time conflicts converge by replica ID regardless of delivery order.
4. Same-value newer writes change digest/persistence metadata without emitting a visible-value event.
5. Late join, reconnect, snapshot import, duplicate delivery, mesh forwarding, and real relay restart/replay preserve value, timestamp, and author.
6. Lustre effects defer dispatch and do not mutate during effect construction.
7. The independent fuzz oracle detects dropped metadata, wrong local-author restoration, and reset logical clocks.
8. README and plan status match the shipped API.
9. Relevant focused suites pass on both targets, and repository validation is green apart from any separately confirmed baseline failure.
