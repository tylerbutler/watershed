# LWWRegister DDS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task, inline without subagents. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose a standalone string-valued last-writer-wins register.

**Architecture:** Add a pure Lattice-backed register kernel and a small
clock helper. Track local writer identity separately from the merged
winner, then integrate the kernel through the existing sequenced and
p2p channel paths.

**Tech Stack:** Gleam, `lattice_registers`, `gleam_json`, startest, qcheck,
Sluice, the CRDT simulator, and Lustre.

**Spec:** `docs/superpowers/specs/2026-09-09-lattice-dds-expansion-design.md`

**Status:** Draft; implementation has not started. GCounter is the
recommended first delivery, not a code dependency.

## Global constraints

- Keep all dependencies on Hex; do not introduce local-path dependencies.
- LWWRegister requires `lattice_registers = ">= 1.1.0 and < 2.0.0"`.
- Preserve existing channel tags, operation formats, and public behavior.
- Support pure kernels on Erlang and JavaScript; do not add a BEAM p2p driver.
- Keep register values and map keys/values as `String` in this release.
- Keep new mutation errors observable through `Result`; do not use fire-and-forget APIs for fallible edits.
- Do not change website copy in these implementation plans.

The spec's lifecycle, clock, digest, and integration requirements apply
to every task. No dependency upgrade is required for this plan.

## Files and interfaces

Create `src/watershed/lww_clock.gleam`,
`src/watershed/lww_register_kernel.gleam`,
`test/watershed/lww_clock_test.gleam`,
`test/watershed/lww_register_kernel_test.gleam`,
`test/watershed/lww_register_channel_test.gleam`,
`test/watershed/fuzz/lww_register_model.gleam`, and
`test/watershed/lww_register_fuzz_test.gleam`.

```gleam
// In watershed/lww_clock:
pub type ClockError {
  InvalidTimestamp(value: Int)
  ClockExhausted
}

// In watershed/lww_register_kernel:
pub type LwwRegisterOperation {
  Set(value: String, timestamp: Int, delta: lww_register.LWWRegister(String))
}

pub type LwwRegisterEvent {
  Changed(previous_value: String, value: String)
}
```

`LwwRegisterState` stores local `replica_id`, sequenced and optimistic
registers, pending operations with message IDs, `next_pending_message_id`,
and `last_seen`. Use `KernelError` variants for unexpected acknowledgments,
unexpected rollbacks, malformed state, and a wrapped `ClockError`.

```text
lww_clock.next(Int, Int) -> Result(Int, ClockError)
new(ReplicaId) -> LwwRegisterState
value(LwwRegisterState) -> String
sequenced_value(LwwRegisterState) -> String
set(LwwRegisterState, String, Int)
  -> Result(#(LwwRegisterState, List(LwwRegisterEvent), LwwRegisterOperation, Int), KernelError)
p2p_set(LwwRegisterState, String, Int)
  -> Result(#(LwwRegisterState, List(LwwRegisterEvent), LwwRegisterOperation), KernelError)
```

Also expose `apply_remote`, `p2p_merge`, `ack_local`,
`ack_local_with_message_id`, `rollback`, `apply_stashed_operation`,
`summary`, `from_summary`, `from_sequenced`, and `check_cache_coherence`.
Merge/load paths that decode opaque timestamp metadata return `Result`
with an explicit error; do not copy an infallible signature and unwrap it.

### Task 1: Implement clocks and the pure register lifecycle

**Files:** Create the clock, kernel, and their test files. Read
`src/watershed/or_map_kernel.gleam` for its fresh-writer construction and
`src/watershed/pn_counter_kernel.gleam` for lifecycle conventions.

**Interfaces:** Produce `lww_clock.next` and the register kernel API above.
The kernel receives wall-clock milliseconds; it does not perform I/O.

- [ ] Add the clock tests:

```gleam
import startest/expect
import watershed/lww_clock

pub fn clock_advances_past_observed_time_test() -> Nil {
  lww_clock.next(100, 100) |> expect.to_equal(Ok(101))
  lww_clock.next(100, 3) |> expect.to_equal(Ok(101))
  lww_clock.next(100, 200) |> expect.to_equal(Ok(200))
  lww_clock.next(9_007_199_254_740_991, 1)
  |> expect.to_equal(Error(lww_clock.ClockExhausted))
  lww_clock.next(0, -1)
  |> expect.to_equal(Error(lww_clock.InvalidTimestamp(-1)))
}
```

- [ ] Add this author-identity regression in the kernel test file:

```gleam
import gleam/json
import lattice_core/replica_id
import lattice_registers/lww_register
import startest/expect
import watershed/lww_register_kernel as kernel

pub fn local_write_uses_local_author_after_reload_test() -> Nil {
  let remote = lww_register.new("remote", 100, replica_id.new("z"))
  let assert Ok(local) =
    kernel.from_summary(
      json.to_string(lww_register.to_json(remote)),
      replica_id.new("a"),
    )
  let assert Ok(#(_, _, kernel.Set(_, timestamp, delta), _)) =
    kernel.set(local, "local", 1)
  timestamp |> expect.to_equal(101)
  delta
  |> expect.to_equal(
    lww_register.new("local", 101, replica_id.new("a")),
  )
}
```

- [ ] Run `rtk proxy gleam test --target javascript -- lww_clock lww_register_kernel`;
  expect missing modules before implementation.
- [ ] Implement `next` by validating both inputs and checking exhaustion
  before addition, then returning `int.max(wall_clock, last_seen + 1)`.
  Initialize the register with the spec's shared empty-string bottom.
  Construct writes with `lww_register.new(value, stamp, state.replica_id)`.
- [ ] Decode timestamp metadata through `lww_register.to_json` using
  `decode.at(["state", "timestamp"], decode.int)`. Check its range and
  propagate errors. Observe timestamps on load, merge, and stash replay.
  Keep `last_seen` at its high-water mark after rollback.
- [ ] Add tests for concurrent equal-time writers `a` and `b`, both merge
  orders, same-value writes with no event, FIFO acknowledgments, LIFO
  rollback, wrong metadata, summary exclusion of pending edits, and
  duplicate stash replay without restamping.
- [ ] Add a full-state import followed by a lower-wall-clock local write;
  expect the local write to win. Add an empty-register snapshot test
  across two local replica IDs; expect identical replicated state.
- [ ] Run the clock and register selectors on both targets and commit
  with `feat: add LWWRegister kernel`.

### Task 2: Add channel, codec, and digest integration

**Files:** Modify `src/watershed/channel.gleam`,
`src/watershed/wire.gleam`, `src/watershed/wire/op.gleam`,
`src/watershed/runtime_core.gleam`, and `src/watershed/crdt_core.gleam`.
Create the register channel tests; extend
`test/watershed/wire_test.gleam`, `test/watershed/crdt_wire_test.gleam`,
and `test/watershed/crdt_core_test.gleam`.

**Interfaces:** Add `LwwRegisterChannel`, `InitLwwRegister`,
`LwwRegisterState`, `LwwRegisterOperation`, `LwwRegisterEvent`,
`LwwRegisterSnapshot`, and `LwwRegisterSetEdit(value, timestamp)` variants.
The core exposes `lww_register_set(core, address, value, timestamp)` with
the standard core edit result and `lww_register_value(core, address) ->
Result(String, Nil)`.

- [ ] Add a snapshot round-trip test and this channel contract test:

```gleam
import startest/expect
import watershed/channel

pub fn register_channel_contract_test() -> Nil {
  channel.type_to_string(channel.LwwRegisterChannel)
  |> expect.to_equal("lwwRegister")
  channel.string_to_type("lwwRegister")
  |> expect.to_equal(Ok(channel.LwwRegisterChannel))
  channel.supports_p2p(channel.LwwRegisterChannel)
  |> expect.to_be_true()
}
```

- [ ] Run `rtk proxy gleam test --target javascript -- lww_register_channel wire`
  and confirm missing variants before integration.
- [ ] Complete the spec's channel integration checklist. Represent
  snapshots with the Lattice register, not just its string. Update
  `crdt_core.init_for`, equality comparisons, error dispatch, attach,
  resubmission, and exhaustive test helpers. Keep stash, rollback, and
  cache checks in the kernel/harness tests.
- [ ] Encode `lwwRegisterSet` with string `value`, integer `timestamp`,
  and stringified Lattice `delta`. Require timestamp and value to agree
  with the fragment. Reject unsupported envelope versions, invalid
  authors for non-bottom writes, and timestamps outside the safe range.
- [ ] Add malformed-wire tests, then detached edit/attach, acknowledgment,
  reconnect, summary-load, and wrong-kind tests in the channel suite.
- [ ] Add digest tests for identical strings at timestamps 1 and 2 and
  for identical strings/timestamps with different winner replica IDs.
  Digests must differ before merging and agree after merging. Do not
  strip the winner's `replica_id` as if it were a local cursor.
- [ ] Add a three-peer-chain test where a same-value newer write causes
  no subscription event but reaches the third peer through anti-entropy.
  Extend persistence coverage so the new timestamp survives export/import.
- [ ] Run the register, clock, wire, runtime-core, CRDT-core, and p2p
  selectors together on both targets. Commit with
  `feat: register LWWRegister channel`.

### Task 3: Expose runtime and typed APIs

**Files:** Modify `src/watershed/runtime.gleam`,
`src/watershed/runtime_beam.gleam`, `src/watershed.gleam`,
`src/watershed_beam.gleam`, `src/watershed/schema.gleam`,
`src/watershed/p2p.gleam`, and `src/watershed/crdt_js.gleam`.
Extend the schema, Sluice driver, CRDT-JS, and p2p tests.

**Interfaces:** Add opaque `LwwRegister` and
`schema.LwwRegisterChannel`. Sequenced facades expose
`create_lww_register`, `resolve_lww_register`, `lww_register_handle_of`,
`lww_register_set -> Result(Nil, String)`, `lww_register_value ->
Result(String, Nil)`, `subscribe_lww_register`, and typed
`set_lww_register_field`, `resolve_lww_register_field`,
`ensure_lww_register`.

The CRDT facade exposes `lww_register_set -> Result(Nil, P2pError)`,
`lww_register_value -> Result(String, P2pError)`, and
`subscribe_lww_register` on `Handle(schema.LwwRegisterChannel)`.

- [ ] Add two-client Sluice tests for create, typed attach/resolve, set,
  subscribe, and reconnect. The public setters take a string, not a
  caller-supplied timestamp; runtime code supplies the wall clock.
- [ ] Run the driver/schema selectors to expose the missing APIs.
- [ ] Add result-returning JS calls and BEAM request/reply edit messages,
  using the fallible text-edit path as a reference. Preserve clock errors
  in the returned error string and existing runtime notifications.
- [ ] Add the p2p root:

```gleam
pub fn lww_register_root() -> CrdtKind(schema.LwwRegisterChannel) {
  CrdtKind(channel.InitLwwRegister)
}
```

- [ ] Implement CRDT mutation through the existing `mutate` helper with
  `channel.LwwRegisterSetEdit(value, transport_js.now_milliseconds())`.
  Add typed reads and subscriptions without silent fallback values.
- [ ] Exercise mesh and relay-lifecycle cases through the CRDT facade.
  Confirm late join, snapshot reload, and a subsequent local write retain
  the correct writer identity and converge.
- [ ] Run the affected driver, schema, p2p, CRDT-JS, and relay-lifecycle
  selectors on the applicable targets. Commit with
  `feat: expose LWWRegister runtime APIs`.

### Task 4: Add effects, a model, and user documentation

**Files:** Modify both Lustre effect modules, their existing subscription
test suites, and `README.md`. Create the model and fuzz files listed above.

**Interfaces:** Add `subscribe_lww_register` to both effect modules and
`ensure_lww_register` to the sequenced bindings. Reuse generic effect
execution for writes:

```gleam
crdt.perform(fn() { crdt_js.lww_register_set(register, "ready") }, Outcome)
```

- [ ] Add effect tests for deferred subscription dispatch, cancellation,
  write failure, and no mutation while constructing an effect. Run the
  existing Lustre suite before adding wrappers, then after.
- [ ] Implement `KernelModel` using an independent maximum
  `(timestamp, replica_id)` oracle over writes. Generate same-time writes,
  repeated values, backward wall clocks, rollback, stash, and summary load.
  Generate unique write stamps per author; conflicting payloads with the
  same author and timestamp violate the writer contract.
- [ ] Add a planted author-retention fault and a planted clock-reset fault.
  Require the model to distinguish both from a correct kernel.
- [ ] Update README with create/set/read and typed field examples.
  Explain the initial empty string, string-only payload, timestamp plus
  author tie-break, and the difference from consensus register collections.
- [ ] Run both-target register/clock/model and integration selectors, the
  Lustre suite from `watershed_lustre/`, and source/test format checks.
- [ ] Commit with `feat: complete LWWRegister bindings`.
