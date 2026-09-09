# GCounter DDS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task, inline without subagents. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose a grow-only counter as a first-class sequenced and p2p DDS.

**Architecture:** Add a pure `g_counter_kernel` backed by
`lattice_counters/g_counter`. Extend the existing closed channel sums,
runtime APIs, CRDT roots, typed handles, and Lustre subscriptions.

**Tech Stack:** Gleam on Erlang and JavaScript, Lattice, startest, qcheck,
Sluice, and the existing CRDT simulator.

**Spec:** `docs/superpowers/specs/2026-09-09-lattice-dds-expansion-design.md`

**Status:** Shipped. Commits `0008150`, `e21a906`, `8ee2875`, `646ba45`, plus `1289d59` for the website demo (beyond the plan's scope).

## Global constraints

- Keep all dependencies on Hex; do not introduce local-path dependencies.
- GCounter requires `lattice_counters = ">= 1.1.0 and < 2.0.0"`.
- Preserve existing channel tags, operation formats, and public behavior.
- Support pure kernels on Erlang and JavaScript; do not add a BEAM p2p driver.
- Keep new mutation errors observable through `Result`; do not use fire-and-forget APIs for fallible edits.
- Do not change website copy in these implementation plans.

The remaining integration and lifecycle requirements in the spec apply
to every task. No dependency change is needed for this plan.

## Files and interfaces

Create `src/watershed/g_counter_kernel.gleam`,
`test/watershed/g_counter_kernel_test.gleam`,
`test/watershed/g_counter_channel_test.gleam`,
`test/watershed/fuzz/g_counter_model.gleam`, and
`test/watershed/g_counter_fuzz_test.gleam`.

The pure kernel's public vocabulary is:

```gleam
pub type GCounterOperation {
  Increment(amount: Int, delta: g_counter.GCounter)
}

pub type GCounterEvent {
  Updated(applied: Int, new_value: Int)
}

pub type EditError {
  NegativeIncrement(amount: Int)
}
```

`GCounterState` contains `replica_id`, `sequenced`, `optimistic`, `pending`,
and `next_pending_message_id`. Pending entries contain the operation and
message ID. Use the `KernelError` variants `UnexpectedAck(operation,
detail)` and `UnexpectedRollback(operation, detail)` for consistency errors.

Required local signatures:

```text
new(ReplicaId) -> GCounterState
value(GCounterState) -> Int
sequenced_value(GCounterState) -> Int
increment(GCounterState, Int)
  -> Result(#(GCounterState, List(GCounterEvent), GCounterOperation, Int), EditError)
p2p_increment(GCounterState, Int)
  -> Result(#(GCounterState, List(GCounterEvent), GCounterOperation), EditError)
```

Provide `apply_remote`, `p2p_merge`, `ack_local`,
`ack_local_with_message_id`, `rollback`, `apply_stashed_operation`,
`summary`, `from_summary`, `from_sequenced`, and `check_cache_coherence`
with the PN-counter kernel's signatures, replacing its state, event,
operation, and Lattice types with GCounter equivalents.

### Task 1: Implement the pure counter and lifecycle

**Files:** Create the kernel and kernel test files above. Read
`src/watershed/pn_counter_kernel.gleam` and the installed
`build/packages/lattice_counters/src/lattice_counters/g_counter.gleam`.

**Interfaces:** Consume Lattice's fallible increment/delta API and merge.
Produce the kernel API defined above; do not expose decrement.

- [x] Add these initial tests:

```gleam
import lattice_core/replica_id
import startest/expect
import watershed/g_counter_kernel as kernel

pub fn negative_increment_is_rejected_test() -> Nil {
  kernel.increment(kernel.new(replica_id.new("a")), -1)
  |> expect.to_equal(Error(kernel.NegativeIncrement(-1)))
}

pub fn independent_increments_merge_once_test() -> Nil {
  let assert Ok(#(a, _, _, _)) =
    kernel.increment(kernel.new(replica_id.new("a")), 2)
  let assert Ok(#(_, _, operation, _)) =
    kernel.increment(kernel.new(replica_id.new("b")), 3)
  let #(a, _) = kernel.apply_remote(a, operation)
  let #(a, events) = kernel.apply_remote(a, operation)
  kernel.value(a) |> expect.to_equal(5)
  kernel.sequenced_value(a) |> expect.to_equal(3)
  events |> expect.to_equal([])
  kernel.check_cache_coherence(a) |> expect.to_equal(Ok(Nil))
}
```

- [x] Run `rtk proxy gleam test --target javascript -- g_counter_kernel`.
  Expect a missing-module failure before implementation.
- [x] Use `g_counter.try_increment_with_delta` for nonnegative mutations.
  Queue the produced fragment for sequenced edits. For p2p edits, merge
  it into both states without a pending entry. Emit `Updated(after -
  before, after)` only when the visible value changes.
- [x] Add FIFO acknowledgment and LIFO rollback tests with two pending
  increments; reject wrong IDs, amounts, fragments, and empty queues.
  Rebuild rollback state by folding the remaining fragments over the
  sequenced base.
- [x] Add summary reload under replica `b` after `a` wrote 2. Increment
  `b` by 3 and merge; expect 5. Rebrand loads with
  `g_counter.merge(g_counter.new(local_id), decoded)`.
- [x] Add zero, duplicate stash replay, pending-summary exclusion, and
  direct p2p-merge tests. Stash replay must return the original operation.
- [x] Run the kernel selector on both targets:

```bash
rtk proxy gleam test --target erlang -- g_counter_kernel
rtk proxy gleam test --target javascript -- g_counter_kernel
```

- [x] Commit the kernel and its tests with `feat: add GCounter kernel`.

### Task 2: Register the channel and sequenced core operations

**Files:** Modify `src/watershed/channel.gleam`,
`src/watershed/wire.gleam`, `src/watershed/wire/op.gleam`,
`src/watershed/runtime_core.gleam`, `src/watershed/crdt_core.gleam`,
and existing exhaustive test helpers in `test/watershed/crdt_core_test.gleam`.
Create `test/watershed/g_counter_channel_test.gleam`; extend
`test/watershed/wire_test.gleam`.

**Interfaces:** Produce `GCounterChannel`, `InitGCounter`,
`GCounterState`, `GCounterOperation`, `GCounterEvent`,
`GCounterSnapshot`, and `GCounterIncrementEdit(amount)` channel variants.
Expose `runtime_core.g_counter_increment(core, address, amount)` with the
standard core edit result and `g_counter_value(core, address) ->
Result(Int, Nil)`.

- [x] Add the channel round-trip test:

```gleam
import gleam/json
import lattice_core/replica_id
import startest/expect
import watershed/channel
import watershed/g_counter_kernel as kernel

pub fn g_counter_snapshot_round_trip_test() -> Nil {
  let assert Ok(#(state, _, operation, _)) =
    kernel.increment(kernel.new(replica_id.new("a")), 4)
  let assert Ok(state) = kernel.ack_local(state, operation)
  let snapshot = channel.GCounterSnapshot(state.sequenced)
  let assert Ok(decoded) =
    json.parse(
      json.to_string(channel.encode_snapshot(snapshot)),
      channel.snapshot_decoder(channel.GCounterChannel),
    )
  channel.same_snapshot(snapshot, decoded) |> expect.to_be_true()
  channel.type_to_string(channel.GCounterChannel)
  |> expect.to_equal("gCounter")
}
```

- [x] Run `rtk proxy gleam test --target javascript -- g_counter_channel wire`
  and confirm the new variants are missing.
- [x] Complete the spec's channel lifecycle checklist, including local
  metadata, attach promotion, resubmission, and `crdt_core.init_for`.
  Exercise stash, rollback, and cache checks through the kernel harness.
  Extend exhaustive matches rather than adding catch-all success cases.
- [x] Encode `gCounterIncrement` with `amount` and a stringified
  `g_counter.to_json(delta)`. Validate nonnegative intent and decoded
  per-replica counts; reject wrong type/version and malformed fragments.
  The fragment is cumulative, so do not require its count to equal the
  intent amount.
- [x] Add runtime-core cases using the bootstrap fixture in
  `test/watershed/pn_counter_channel_test.gleam`: detached increment 4,
  attach through a root-map handle, increment 2, acknowledge, and reload.
  Expect no outbound op while detached and value 6 after reload.
- [x] Add negative-edit tests that preserve the core, pending queue, and
  outbound sequence number. Map `NegativeIncrement` to the existing
  caller-visible core error path.
- [x] Run the channel, wire, core, and p2p selectors together on each target:

```bash
rtk proxy gleam test --target erlang -- g_counter wire runtime_core crdt_core p2p
rtk proxy gleam test --target javascript -- g_counter wire runtime_core crdt_core p2p
```

- [x] Commit with `feat: register GCounter channel`.

### Task 3: Expose sequenced and CRDT APIs

**Files:** Modify `src/watershed/runtime.gleam`,
`src/watershed/runtime_beam.gleam`, `src/watershed.gleam`,
`src/watershed_beam.gleam`, `src/watershed/schema.gleam`,
`src/watershed/p2p.gleam`, and `src/watershed/crdt_js.gleam`.
Extend `test/watershed/schema_test.gleam`,
`test/watershed/sluice/driver_test.gleam`,
`test/watershed/sluice/driver_js_test.gleam`,
`test/watershed/crdt_core_test.gleam`, and
`test/watershed/crdt_js_test.gleam`.

**Interfaces:** Add opaque facade `GCounter` and phantom
`schema.GCounterChannel`. Both sequenced facades expose `create_g_counter`,
`resolve_g_counter`, `g_counter_handle_of`, `g_counter_increment ->
Result(Nil, String)`, `g_counter_value -> Result(Int, Nil)`,
`subscribe_g_counter`, and `set_g_counter_field`,
`resolve_g_counter_field`, `ensure_g_counter`, following existing
PN-counter parameter and subscription conventions.

The CRDT API uses `Handle(schema.GCounterChannel)` and exposes
`g_counter_increment -> Result(Nil, P2pError)`, `g_counter_value ->
Result(Int, P2pError)`, and `subscribe_g_counter`. Add this root:

```gleam
pub fn g_counter_root() -> CrdtKind(schema.GCounterChannel) {
  CrdtKind(channel.InitGCounter)
}
```

- [x] Write Sluice cases through both facades: create, attach a typed field,
  resolve from a second client, increment 2 and 3, and observe 5.
  Assert a negative edit returns an error and submits nothing.
- [x] Run the relevant driver/schema selectors and confirm missing API errors.
- [x] Add result-returning runtime calls. BEAM edits need a reply subject;
  do not copy PN-counter's fire-and-forget update message. Use the existing
  fallible text-edit request/reply pattern.
- [x] Add the p2p root and typed facade functions through `mutate` and
  `read`. Extend typed subscription event filtering. Reject wrong-kind
  handles with the established error, not a zero fallback.
- [x] Add two-replica and three-peer-chain CRDT cases. Check value and
  digest after duplicate delivery, a late join, and snapshot export/import.
  Verify differing local `self_id` values do not prevent equal digests.
- [x] Run the driver, schema, CRDT, and p2p selectors together on each
  applicable target. Include existing persistence and relay-lifecycle
  selectors when extending those scenarios.
- [x] Commit with `feat: expose GCounter runtime APIs`.

### Task 4: Add effects, model coverage, and documentation

**Files:** Modify `watershed_lustre/src/watershed_lustre.gleam`,
`watershed_lustre/src/watershed_lustre/crdt.gleam`,
`watershed_lustre/test/watershed_lustre/crdt_test.gleam`, and `README.md`.
Create the model and fuzz test files listed above. Extend the existing
sequenced subscription tests under `watershed_lustre/test/`.

**Interfaces:** Add `subscribe_g_counter` in both effect modules and
`ensure_g_counter` in the sequenced module. Keep mutations behind the
existing generic effect-perform API.

- [x] Add subscription tests for an increment, cancellation, and deferred
  dispatch. Use an effect-perform thunk:

```gleam
crdt.perform(fn() { crdt_js.g_counter_increment(counter, 2) }, Outcome)
```

- [x] Run `rtk proxy gleam test` from `watershed_lustre/` before and after
  adding the wrappers. Assert no mutation occurs when the effect is
  constructed and no callback dispatch occurs inside `update`.
- [x] Implement the existing `KernelModel` interface in
  `test/watershed/fuzz/g_counter_model.gleam`. Use
  `pn_counter_model.gleam` for its harness contract, but generate
  nonnegative amounts and use an independent sum-of-sequenced-intents
  oracle. Include duplicates, reconnect/stash, rollback, and summary load.
- [x] Add planted faults that drop an increment and replay an increment
  twice. Require the model to detect both faults; a test that reuses
  Lattice merge as its oracle cannot establish this.
- [x] Update the README's supported types and add a create/increment/read
  example. Explain grow-only confirmed state, negative rejection, and
  possible rollback of optimistic state.
- [x] Run the targeted GCounter, facade, and CRDT tests on both targets,
  the Lustre suite, and `rtk proxy gleam format --check src test` plus
  the corresponding Lustre source/test format check.
- [x] Commit with `feat: complete GCounter bindings`.
