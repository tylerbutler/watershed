# Lattice CRDT integration plan: MV register, G-set, and 2P-set

**Date:** 2026-07-04
**Builds on:** `2026-07-03-pn-counter-kernel-plan.md`,
`2026-07-03-or-map-kernel-plan.md`, and the integrated
`src/watershed/or_set_kernel.gleam` pattern.
**Reference source:** the hex lattice packages already depended on by
`gleam.toml`: `lattice_registers/mv_register`,
`lattice_sets/g_set`, and `lattice_sets/two_p_set`.

## Why these rungs

watershed already integrates the lattice-backed PN counter, OR-map, and OR-set.
The remaining small CRDTs in the current lattice dependency set are useful
follow-on rungs because they exercise three distinct semantics without requiring
new external dependencies:

1. **MV register** proves conflict-preserving register semantics: concurrent
   writes are surfaced as multiple values until a causally later write collapses
   them.
2. **G-set** is the simplest monotonic collection: add-only set union, useful as
   a small runtime/wire skeleton for future lattice channels.
3. **2P-set** adds irreversible tombstones: add/remove converge by set union, but
   removed elements can never become active again.

## Shared integration checklist

For each CRDT, follow the existing channel/runtime path used by `pn_counter` and
`or_set`:

1. Add a pure kernel module in `src/watershed/*_kernel.gleam`.
2. Extend `src/watershed/channel.gleam`:
   - `ChannelType`
   - `ChannelInit`
   - `ChannelState`
   - `ChannelOp`
   - `ChannelEvent`
   - `Snapshot`
   - `LocalOpMeta`
   - `new`, `from_snapshot`, `snapshot`, `attach_snapshot`, `attach_state`
   - `apply_remote`, `ack_local`, `same_shape`
3. Add channel type constants in `src/watershed/wire.gleam`.
4. Add op encode/decode support in `src/watershed/wire/ops.gleam`.
5. Add snapshot encode/decode support in `channel.encode_snapshot` and
   `channel.snapshot_decoder`.
6. Add runtime verbs in `src/watershed/runtime_core.gleam`.
7. Add JS wrappers in `src/watershed/runtime_js.gleam`.
8. Add OTP runtime wrappers in `src/watershed/runtime.gleam` if the channel is
   part of the public Erlang runtime API.
9. Add tests:
   - kernel unit tests
   - wire codec round-trips
   - runtime attach/summary/reconnect tests
   - fuzz/model tests for convergence, duplicate delivery, ack/rollback, and
     summary reload
10. Update the website demo:
    - import the compiled kernel/runtime modules in `website/src/scripts/demo.js`
    - add picker entries in `website/src/components/Demo.astro`
    - add replica panels, controls, merge-rule copy, race buttons, and duplicate
      replay where meaningful
    - update `website/src/components/DdsSections.astro` and architecture/rigor
      copy

Use the same state split as the existing lattice kernels unless a CRDT does not
need a replica identity:

```gleam
sequenced: Crdt,
optimistic: Crdt,
pending: List(PendingOp),
next_pending_message_id: Int,
```

Summaries store sequenced state only. Detached attach snapshots capture the
optimistic state. Remote delivery merges deltas into the sequenced base and then
ensures optimistic reads include sequenced plus still-pending local deltas.

## Plan 1: MV register

### Goal

Add a lattice-backed multi-value register channel that preserves concurrent
writes instead of picking a winner.

### Kernel

Create `src/watershed/mv_register_kernel.gleam`.

Use `lattice_registers/mv_register.MVRegister(String)` initially. The lattice
package has built-in JSON codecs for `String`, so avoid a generic JSON-value
register until the storage format is deliberately designed.

Proposed types:

```gleam
import lattice_core/replica_id.{type ReplicaId}
import lattice_registers/mv_register.{type MVRegister}

pub type MvRegisterState {
  MvRegisterState(
    replica_id: ReplicaId,
    sequenced: MVRegister(String),
    optimistic: MVRegister(String),
    pending: List(PendingOp),
    next_pending_message_id: Int,
  )
}

pub type PendingOp {
  PendingOp(op: MvRegisterOp, message_id: Int)
}

pub type MvRegisterOp {
  Set(value: String, delta: MVRegister(String))
}

pub type MvRegisterEvent {
  ValuesChanged(values: List(String))
}
```

Behavior:

- `new(replica_id)` initializes both CRDT states with
  `mv_register.new(replica_id)`.
- `values(state)` returns `mv_register.value(state.optimistic)`, sorted for
  stable display/tests if needed.
- `sequenced_values(state)` returns the committed-only values.
- `set(state, value)` uses `mv_register.set_with_delta(state.optimistic, value)`,
  appends a pending op, emits `ValuesChanged`.
- `apply_remote(state, op)` merges the op delta into `sequenced`, rebuilds or
  updates `optimistic`, and emits only if the visible value set changed.
- `ack_local_with_message_id` validates FIFO pending op + message id, merges the
  delta into `sequenced`, drops the pending entry, and emits no event.
- `rollback` pops the newest pending entry, validates it, rebuilds optimistic
  from sequenced plus remaining pending deltas, and emits changed values.
- `from_sequenced(summary, replica_id)` should parse the summary and rebrand by
  merging it into `mv_register.new(replica_id)`, matching the PN counter loading
  pattern.

### Runtime API

Add these to `runtime_core.gleam`:

```gleam
pub fn mv_register_set(core: Core, address: String, value: String)
pub fn mv_register_values(core: Core, address: String) -> List(String)
```

Add JS wrappers in `runtime_js.gleam`:

```gleam
pub fn mv_register_set(runtime: Runtime, address: String, value: String) -> Nil
pub fn mv_register_values(runtime: Runtime, address: String) -> List(String)
```

### Wire and snapshot format

- Channel type string: `"mv-register"`.
- Op type string: `"mvRegisterSet"`.
- Encode op deltas as `json.string(json.to_string(mv_register.to_json(delta)))`,
  matching the existing stringified CRDT delta style.
- Decode with `mv_register.from_json`.
- Snapshot payload can store the stringified `mv_register.to_json(sequenced)`
  value.

### Tests

- Concurrent A/B writes retain both values.
- A later write after observing both concurrent values causally supersedes them
  and collapses to one value.
- Duplicate delta delivery is a no-op.
- Rollback restores the prior optimistic value set.
- Summary reload preserves entries and version vector.
- Reconnect/resubmit does not duplicate entries.

### Website demo

- Picker label: `MV register` tagged `CRDT`.
- Terrain: **revision slate** or **field note cell**.
- Baseline: empty, or one value such as `"Survey datum"`.
- Controls: client A/B write alternate station notes.
- Race: A writes `"raise crest"` while B writes `"arm pump"`; both values remain
  visible as concurrent alternatives after sequencing.
- Add a “resolve after seeing both” action that writes
  `"raise crest + arm pump"` and demonstrates causal supersession collapsing the
  conflict set.

## Plan 2: G-set

### Goal

Add a grow-only string set channel for permanent facts/markers.

### Kernel

Create `src/watershed/g_set_kernel.gleam`.

Use `lattice_sets/g_set.GSet(String)`.

Proposed types:

```gleam
import lattice_sets/g_set.{type GSet}

pub type GSetState {
  GSetState(
    sequenced: GSet(String),
    optimistic: GSet(String),
    pending: List(PendingOp),
    next_pending_message_id: Int,
  )
}

pub type PendingOp {
  PendingOp(op: GSetOp, message_id: Int)
}

pub type GSetOp {
  Add(element: String, delta: GSet(String))
}

pub type GSetEvent {
  ElementAdded(element: String)
}
```

Behavior:

- `new()` initializes both CRDT states with `g_set.new()`.
- `values(state)` returns `g_set.value(state.optimistic)` as a sorted list.
- `add(state, element)` uses `g_set.add_with_delta`, appends a pending op, and
  emits `ElementAdded` only if the optimistic visible set changed.
- `apply_remote` merges the delta into sequenced and optimistic, emitting only
  for newly visible elements.
- `ack_local_with_message_id` validates FIFO pending op + message id and merges
  the delta into sequenced.
- `rollback` rebuilds optimistic from sequenced plus remaining pending deltas.
- There is intentionally no remove verb.

### Runtime API

Add these to `runtime_core.gleam`:

```gleam
pub fn g_set_add(core: Core, address: String, element: String)
pub fn g_set_contains(core: Core, address: String, element: String) -> Bool
pub fn g_set_values(core: Core, address: String) -> List(String)
```

Add JS wrappers in `runtime_js.gleam`:

```gleam
pub fn g_set_add(runtime: Runtime, address: String, element: String) -> Nil
pub fn g_set_contains(runtime: Runtime, address: String, element: String) -> Bool
pub fn g_set_values(runtime: Runtime, address: String) -> List(String)
```

### Wire and snapshot format

- Channel type string: `"g-set"`.
- Op type string: `"gSetAdd"`.
- Encode op deltas as `json.string(json.to_string(g_set.to_json(delta)))`.
- Decode with `g_set.from_json`.
- Snapshot stores stringified `g_set.to_json(sequenced)`.

### Tests

- Concurrent adds converge by union.
- Adding the same element twice is idempotent.
- Duplicate delivery is a no-op.
- Rollback removes only the newest unacked optimistic add.
- Summary reload preserves values.
- Detached attach includes optimistic additions.

### Website demo

- Picker label: `G-set` tagged `CRDT`.
- Terrain: **permanent benchmark registry**.
- Controls: “Mark benchmark” buttons for fixed IDs.
- No remove button; copy explicitly says grow-only.
- Race: A marks `BM-17`, B marks `BM-22`; both appear everywhere after
  sequencing.
- Duplicate replay button demonstrates re-delivery does not duplicate entries.

## Plan 3: 2P-set

### Goal

Add a two-phase set channel where elements can be added and tombstoned once, but
never re-added to the active set.

### Kernel

Create `src/watershed/two_p_set_kernel.gleam`.

Use `lattice_sets/two_p_set.TwoPSet(String)`.

Proposed types:

```gleam
import lattice_sets/two_p_set.{type TwoPSet}

pub type TwoPSetState {
  TwoPSetState(
    sequenced: TwoPSet(String),
    optimistic: TwoPSet(String),
    pending: List(PendingOp),
    next_pending_message_id: Int,
  )
}

pub type PendingOp {
  PendingOp(op: TwoPSetOp, message_id: Int)
}

pub type TwoPSetOp {
  Add(element: String, delta: TwoPSet(String))
  Remove(element: String, delta: TwoPSet(String))
}

pub type TwoPSetEvent {
  ElementAdded(element: String)
  ElementRemoved(element: String)
  ElementTombstoned(element: String)
}
```

Behavior:

- `new()` initializes both CRDT states with `two_p_set.new()`.
- `values(state)` returns active values only:
  `two_p_set.value(state.optimistic)`.
- `contains(state, element)` returns active membership only.
- `add(state, element)` uses `two_p_set.add_with_delta`.
- `remove(state, element)` uses `two_p_set.remove_with_delta`; removing an
  unseen element is valid and creates a preemptive tombstone.
- Re-adding a tombstoned element is allowed at the lattice layer but remains
  inactive. The runtime/UI should surface this as “tombstoned” rather than a
  successful active add.
- `apply_remote`, `ack_local_with_message_id`, and `rollback` follow the same
  pending-delta pattern as G-set.
- Add a read helper for tombstone visibility if the UI needs it. If the lattice
  package does not expose tombstones directly, either add a kernel-side event
  when remove ops apply or store a summarized tombstone list derived from a
  small wrapper around the lattice JSON representation.

### Runtime API

Add these to `runtime_core.gleam`:

```gleam
pub fn two_p_set_add(core: Core, address: String, element: String)
pub fn two_p_set_remove(core: Core, address: String, element: String)
pub fn two_p_set_contains(core: Core, address: String, element: String) -> Bool
pub fn two_p_set_values(core: Core, address: String) -> List(String)
```

Optional, if tombstone reads are exposed:

```gleam
pub fn two_p_set_tombstoned(core: Core, address: String, element: String) -> Bool
```

Add JS wrappers in `runtime_js.gleam`.

### Wire and snapshot format

- Channel type string: `"two-p-set"`.
- Op type strings: `"twoPSetAdd"` and `"twoPSetRemove"`.
- Encode op deltas as `json.string(json.to_string(two_p_set.to_json(delta)))`.
- Decode with `two_p_set.from_json`.
- Snapshot stores stringified `two_p_set.to_json(sequenced)`.

### Tests

- Add then remove removes active membership.
- Remove then add keeps the element inactive.
- Concurrent add/remove converges to removed because tombstone wins.
- Duplicate remove is idempotent.
- Rollback restores active membership when rolling back a pending remove.
- Summary reload preserves tombstones, not just active values.
- Reconnect/resubmit preserves permanent removals.

### Website demo

- Picker label: `2P-set` tagged `CRDT`.
- Terrain: **retired marker ledger**.
- UI shows active markers and retired/tombstoned markers.
- Controls: “Place marker”, “Retire marker”, and “Try re-place retired marker”.
- Race: A retires `stake-3` while B places or re-places `stake-3`; tombstone
  wins and every replica converges on inactive.
- Copy contrasts it with OR-set: unlike OR-set, retired markers cannot be
  re-opened.

## Recommended implementation order

1. **G-set**: smallest surface area, add-only, and the simplest runtime/wire
   path.
2. **2P-set**: same set-shaped plumbing plus tombstone semantics.
3. **MV register**: requires causal/version-vector semantics and a more careful
   demo narrative.

