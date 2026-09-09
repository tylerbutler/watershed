# LWWMap DDS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task, inline without subagents. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose a string-to-string LWW-map with convergent timestamped deletion.

**Architecture:** Use Lattice's existing deterministic map merge, generate
single-key fragments with its public API, and wrap those fragments in a
pure Watershed kernel. Reuse the LWW clock helper and existing channel
infrastructure, with explicit tombstone and digest handling.

**Tech Stack:** Gleam, `lattice_maps` 1.1.0 or compatible newer,
`gleam_json`, startest, qcheck, Sluice, CRDT simulator, and Lustre.

**Spec:** `docs/superpowers/specs/2026-09-09-lattice-dds-expansion-design.md`

**Status:** Draft; implementation has not started.

**Prerequisite:** Task 1 of
`docs/superpowers/plans/2026-09-09-lww-register-dds.md` supplies
`lww_clock.next(Int, Int) -> Result(Int, ClockError)`. Complete that task
before this kernel; the standalone register's facade is not a dependency.

## Global constraints

- Keep all dependencies on Hex; do not introduce local-path dependencies.
- LWWMap requires `lattice_maps = ">= 1.1.0 and < 2.0.0"`.
- Preserve existing channel tags, operation formats, and public behavior.
- Support pure kernels on Erlang and JavaScript; do not add a BEAM p2p driver.
- Keep register values and map keys/values as `String` in this release.
- Do not expose LWW-map tombstone pruning or accept pruned map states.
- Keep new mutation errors observable through `Result`; do not use fire-and-forget APIs for fallible edits.
- Do not change website copy in these implementation plans.

## Files and interfaces

Create `src/watershed/lww_map_kernel.gleam`,
`test/watershed/lww_map_kernel_test.gleam`,
`test/watershed/lww_map_channel_test.gleam`,
`test/watershed/fuzz/lww_map_model.gleam`, and
`test/watershed/lww_map_fuzz_test.gleam`.

```gleam
pub type LwwMapOperation {
  Set(key: String, value: String, timestamp: Int, delta: lww_map.LWWMap)
  Remove(key: String, timestamp: Int, delta: lww_map.LWWMap)
}

pub type LwwMapEvent {
  ValueChanged(key: String, previous_value: Option(String), value: Option(String))
}
```

`LwwMapState` contains sequenced and optimistic maps, pending operations
with message IDs, `next_pending_message_id`, and a per-key timestamp
dictionary. Accept `ReplicaId` in `new`/load interfaces for channel
consistency, but do not add it to Lattice's map payload or its tie rule.
Define kernel errors for unexpected ack/rollback, malformed state,
unsupported pruning, and wrapped `ClockError`.

```text
new(ReplicaId) -> LwwMapState
get(LwwMapState, String) -> Result(String, Nil)
entries(LwwMapState) -> List(#(String, String))
keys(LwwMapState) -> List(String)
set(LwwMapState, String, String, Int)
  -> Result(#(LwwMapState, List(LwwMapEvent), LwwMapOperation, Int), KernelError)
remove(LwwMapState, String, Int)
  -> Result(#(LwwMapState, List(LwwMapEvent), LwwMapOperation, Int), KernelError)
```

Add `p2p_set`/`p2p_remove` with the same arguments and a result triple
without a message ID. Also implement `apply_remote`, `p2p_merge`,
`ack_local`, `ack_local_with_message_id`, `rollback`,
`apply_stashed_operation`, `summary`, `from_summary`, `from_sequenced`,
and `check_cache_coherence`. Merge/load operations return `Result` when
checking clock metadata and pruning state.

### Task 1: Establish the Lattice merge contract

**Files:** Create the map kernel test file for dependency contract tests;
this task does not import the future kernel. Read `gleam.toml`,
`manifest.toml`, and the installed LWW-map implementation. Do not change
dependencies or generated manifests.

**Interfaces:** Consume the released `lattice_maps` API. Document its
deterministic equal-time behavior in executable contract tests.

- [ ] Add this regression:

```gleam
import lattice_maps/lww_map
import startest/expect

pub fn equal_timestamp_values_converge_test() -> Nil {
  let a = lww_map.set(lww_map.new(), "k", "a", 10)
  let b = lww_map.set(lww_map.new(), "k", "b", 10)
  lww_map.get(lww_map.merge(a, b), "k") |> expect.to_equal(Ok("b"))
  lww_map.get(lww_map.merge(b, a), "k") |> expect.to_equal(Ok("b"))
}

pub fn equal_timestamp_remove_wins_test() -> Nil {
  let a = lww_map.set(lww_map.new(), "k", "value", 10)
  let b = lww_map.remove(lww_map.new(), "k", 10)
  lww_map.get(lww_map.merge(a, b), "k") |> expect.to_equal(Error(Nil))
  lww_map.get(lww_map.merge(b, a), "k") |> expect.to_equal(Error(Nil))
}
```

- [ ] Run `rtk proxy gleam test --target javascript -- lww_map_kernel`.
  Expect these contract tests to pass on the current 1.1.0 implementation.
  Its left-biased doc comment is stale; `choose_winner` implements the
  deterministic rule. A failure is a dependency/source discrepancy to
  investigate before adding the kernel, not a reason to patch merge in
  Watershed.
- [ ] Run the map contract and existing OR-map selectors on both targets:

```bash
rtk proxy gleam test --target erlang -- lww_map_kernel or_map
rtk proxy gleam test --target javascript -- lww_map_kernel or_map
```

- [ ] Commit with `test: cover Lattice LWWMap merge contract`.

### Task 2: Implement the map kernel and tombstone lifecycle

**Files:** Create `src/watershed/lww_map_kernel.gleam`; extend its test
file. Consume `src/watershed/lww_clock.gleam` from the register plan.

**Interfaces:** Produce the map API defined above. The map has no clear,
prune, arbitrary JSON, or replica-ID tie-break API.

- [ ] Add tests for set/get, sorted entries, remove, remove-absent, and
  set-after-remove. In the remove-absent case require a tombstone and an
  outbound operation, but no visible-change event.
- [ ] Add this restoration regression in a test module importing
  `gleam/json`, `lattice_core/replica_id`, `lattice_maps/lww_map`,
  `startest/expect`, and `watershed/lww_map_kernel as kernel`:

```gleam
pub fn reload_observes_tombstone_time_test() -> Nil {
  let removed = lww_map.remove(lww_map.new(), "k", 100)
  let assert Ok(state) =
    kernel.from_summary(
      json.to_string(lww_map.to_json(removed)),
      replica_id.new("b"),
    )
  let assert Ok(#(state, _, kernel.Set(_, _, timestamp, _), _)) =
    kernel.set(state, "k", "restored", 1)
  timestamp |> expect.to_equal(101)
  kernel.get(state, "k") |> expect.to_equal(Ok("restored"))
}
```

- [ ] Run the map kernel selector and confirm missing kernel behavior.
- [ ] Build local fragments with these existing API calls, where
  `timestamp` comes from `lww_clock.next` for the edited key:

```gleam
let set_fragment = lww_map.set(lww_map.new(), key, value, timestamp)
let remove_fragment = lww_map.remove(lww_map.new(), key, timestamp)
```

  Merge the relevant fragment into optimistic state. Queue it for
  sequenced mode or commit it to both states for p2p mode.
- [ ] Decode timestamps from the `state.entries` array in
  `lww_map.to_json`. Observe active entries and tombstones on remote
  edits, summary load, stash replay, and snapshot import. Reject nonzero
  `pruned_timestamp`, nonpositive/unsafe entry timestamps, and duplicate
  keys in incoming envelopes. Zero is reserved for the empty map's
  watermark; an entry at zero would be discarded by Lattice's merge.
- [ ] Implement observed-value events over the sorted union of visible
  keys before and after a merge. Metadata-only writes/removals update
  state and clocks without a visible event.
- [ ] Add strict ack and rollback matching, cache reconstruction,
  pending-summary exclusion, detached promotion, duplicate delivery, and
  replay-without-restamping tests. Preserve clock high-water marks through
  rollback.
- [ ] Test two keys so a large timestamp on `a` does not advance `b`'s
  per-key clock. Test reordered set/remove fragments and full-state merges.
- [ ] Run map/clock kernel selectors on both targets and commit with
  `feat: add LWWMap kernel`.

### Task 3: Integrate channels, wire, and canonical state

**Files:** Modify `src/watershed/channel.gleam`,
`src/watershed/wire.gleam`, `src/watershed/wire/op.gleam`,
`src/watershed/runtime_core.gleam`, and `src/watershed/crdt_core.gleam`.
Create the map channel test file; extend the wire, CRDT-wire, CRDT-core,
and persistence tests.

**Interfaces:** Add `LwwMapChannel`, `InitLwwMap`, `LwwMapState`,
`LwwMapOperation`, `LwwMapEvent`, `LwwMapSnapshot`,
`LwwMapSetEdit(key, value, timestamp)`, and
`LwwMapRemoveEdit(key, timestamp)`. Add core `lww_map_set` and
`lww_map_remove` edits with timestamp arguments and the standard core edit
result; add `lww_map_get -> Result(String, Nil)`, `lww_map_entries ->
List(#(String, String))`, and `lww_map_keys -> List(String)` reads.

- [ ] Add channel tag/summary round trips and detached edit/attach tests.
  Assert the tag is `lwwMap` and tombstones survive a summary round trip.
- [ ] Run the map-channel and wire selectors before adding dispatch.
- [ ] Complete the shared spec's integration checklist, including
  `crdt_core.init_for`, p2p snapshot merge, wrong-kind errors,
  acknowledgment metadata, resubmission, and exhaustive helpers. Exercise
  stash and rollback through the kernel/harness contracts.
- [ ] Encode `lwwMapSet` and `lwwMapRemove` with intent fields and a
  stringified single-key fragment. Require the fragment to contain exactly
  that key and matching value/tombstone/timestamp, with zero pruning
  watermark. Full snapshots may contain multiple distinct keys.
- [ ] Add the canonical projection:

```gleam
"lww_map" ->
  map_member(value, "state", fn(state) {
    map_member(state, "entries", ordered)
  })
```

  Reuse the existing private helpers in `crdt_core.gleam`. Preserve
  timestamps, null tombstone values, and the watermark.
- [ ] Add digest tests for different entry-array orders and different
  tombstones with identical visible maps. Equivalent state must hash the
  same; different retained history must not.
- [ ] Add a three-peer-chain metadata-only removal case and a persistence
  round trip. The third peer must receive the tombstone even when the
  intermediate peer emits no visible event.
- [ ] Run map, clock, wire, runtime-core, CRDT-core, and persistence
  selectors on both applicable targets. Commit with
  `feat: register LWWMap channel`.

### Task 4: Expose facades and effects

**Files:** Modify `src/watershed/runtime.gleam`,
`src/watershed/runtime_beam.gleam`, `src/watershed.gleam`,
`src/watershed_beam.gleam`, `src/watershed/schema.gleam`,
`src/watershed/p2p.gleam`, `src/watershed/crdt_js.gleam`, and both Lustre
effect modules. Extend schema, Sluice driver, CRDT-JS, relay-lifecycle,
and Lustre subscription tests.

**Interfaces:** Add opaque `LwwMap` and phantom `schema.LwwMapChannel`.
Sequenced facades expose create/resolve/handle/typed-field/ensure helpers
using the `lww_map` stem, `lww_map_set` and `lww_map_remove` returning
`Result(Nil, String)`, `lww_map_get -> Result(String, Nil)`,
`lww_map_entries -> List(#(String, String))`, `lww_map_keys ->
List(String)`, and `subscribe_lww_map`.

CRDT functions use `Handle(schema.LwwMapChannel)` and return `P2pError`
for document/handle/edit errors. `lww_map_get` returns
`Result(Result(String, Nil), P2pError)` to distinguish a missing key from
a failed read. Wrap entries/keys in an outer `Result` as well.

- [ ] Add two-client create/typed-attach/resolve/edit tests through both
  sequenced facades. Include removal and restoration after reconnect.
- [ ] Run driver and schema selectors before implementing these APIs.
- [ ] Use existing wall-clock functions in JS and BEAM runtimes. Add
  reply subjects for fallible BEAM mutations rather than fire-and-forget
  messages. Preserve wrong-channel and clock failures.
- [ ] Add `p2p.lww_map_root()` returning
  `CrdtKind(channel.InitLwwMap)`, typed CRDT read/edit/subscription
  functions, and tests using the existing mesh and relay setup.
- [ ] Add `subscribe_lww_map` to both Lustre modules and
  `ensure_lww_map` to the sequenced module. Use effect-perform thunks:

```gleam
crdt.perform(fn() { crdt_js.lww_map_set(map, "status", "ready") }, Outcome)
```

- [ ] Test cancellation, deferred dispatch, and mutation only when the
  effect runs. Run the targeted facade tests on applicable targets and
  `rtk proxy gleam test` from `watershed_lustre/`.
- [ ] Commit with `feat: expose LWWMap APIs and bindings`.

### Task 5: Add a merge-independent model and document semantics

**Files:** Create the model and fuzz test files listed above; modify
`README.md`.

**Interfaces:** Implement the existing `KernelModel` contract. Keep a
reference dictionary of per-key winning timestamp and optional string;
do not use Lattice merge as the model's winner function.

- [ ] Test the oracle's equal-time table before wiring it to the harness:

| Left at time 10 | Right at time 10 | Expected winner |
|---|---|---|
| `"a"` | `"b"` | `"b"` |
| `"b"` | tombstone | tombstone |
| tombstone | `"b"` | tombstone |
| tombstone | tombstone | tombstone |

- [ ] Generate repeated keys, equal timestamps across clients, backward
  clocks, absent-key removal, rollback, replay, and summary reload. Check
  visible entries and retained tombstones as well as cache coherence.
- [ ] Add planted left-biased-merge and dropped-tombstone faults; require
  the model to detect each one.
- [ ] Update README with set/get/remove examples and the difference from
  `SharedMap` and OR-map register mode. State that equal-time deletion
  wins, equal-time values compare lexicographically, keys are sorted for
  reads, and pruning is unavailable.
- [ ] Run map/model/clock and affected integration selectors on both
  targets, the Lustre suite, and source/test format checks.
- [ ] Commit with `test: cover LWWMap convergence`.
