# GCounter, LWWRegister, and LWWMap DDS Design

**Status:** Approved for implementation. LWWMap release is blocked by the
cross-target Unicode tie discrepancy recorded in its
[implementation plan](../plans/2026-09-09-lww-map-dds.md).

**Scope update (2026-09-10):** LWWMap delivery includes website integration,
a demo in the maps family, and a comparison with SharedMap. This extends
the original library-only scope for LWWMap; it does not reopen the shipped
GCounter or LWWRegister plans.

## Goal and scope

Add three first-class DDSs to Watershed: `GCounter`, `LwwRegister`, and
`LwwMap`. Each must work through the server-sequenced JavaScript and BEAM
APIs and the existing JavaScript CRDT API, including its mesh and relay
paths. Include typed handles, subscriptions, summaries, persistence, and
Lustre bindings.

Keep the first register and map APIs string-valued. Lattice's installed
register codecs and LWW-map API support strings; a generic JSON layer would
add codec and handle-discovery work that these additions do not need.

Implement each DDS as a separate change. Broader OR-map composition is a
follow-up, described below, rather than a prerequisite.

## Existing implementation

The channel infrastructure already hosts seven mergeable DDS kinds.
`src/watershed/channel.gleam` defines the closed state, operation, event,
snapshot, initializer, and p2p-edit sums. The sequenced and CRDT cores route
through that module. New DDSs need variants and dispatch branches, not a
new transport or a pluggable channel framework.

Use these current files as references. Older sequence/text plans predate
the runtime rename and contain paths that no longer exist.

| Responsibility | Current source |
|---|---|
| Optimistic state, acknowledgments, rollback, merge | `src/watershed/pn_counter_kernel.gleam` |
| LWW author identity and logical timestamps | `src/watershed/or_map_kernel.gleam` |
| Channel registration and lifecycle dispatch | `src/watershed/channel.gleam` |
| Sequenced state machine | `src/watershed/runtime_core.gleam` |
| JavaScript runtime and facade | `src/watershed/runtime.gleam`, `src/watershed.gleam` |
| BEAM actor and facade | `src/watershed/runtime_beam.gleam`, `src/watershed_beam.gleam` |
| Operation codecs and type strings | `src/watershed/wire/op.gleam`, `src/watershed/wire.gleam` |
| P2p eligibility, roots, merge, digest | `src/watershed/p2p.gleam`, `src/watershed/crdt_core.gleam` |
| CRDT wire and browser facade | `src/watershed/crdt_wire.gleam`, `src/watershed/crdt_js.gleam` |
| Typed channel fields | `src/watershed/schema.gleam` |
| Sequenced and CRDT effects | `watershed_lustre/src/watershed_lustre.gleam`, `watershed_lustre/src/watershed_lustre/crdt.gleam` |

## Approach

Use small, type-specific kernels backed by the installed Lattice packages.
This follows Watershed's existing dispatch model and keeps distinct
semantics visible in the API.

Two alternatives do not meet this goal. A PN-counter with a positive-only
application convention does not provide a grow-only channel contract.
A one-key OR-map can provide register behavior, but retains key-removal and
mode machinery that a standalone register does not need. A generic CRDT
channel would require a larger public type and codec design before any of
these three DDSs could ship.

## Global constraints

- Keep all dependencies on Hex; do not introduce local-path dependencies.
- GCounter requires `lattice_counters = ">= 1.1.0 and < 2.0.0"`.
- LWWRegister requires `lattice_registers = ">= 1.1.0 and < 2.0.0"`.
- LWWMap requires `lattice_maps = ">= 1.1.0 and < 2.0.0"`.
- Preserve existing channel tags, operation formats, and public behavior.
- Support pure kernels on Erlang and JavaScript; do not add a BEAM p2p driver.
- Keep register values and map keys/values as `String` in this release.
- Do not expose LWW-map tombstone pruning or accept pruned map states.
- Keep new mutation errors observable through `Result`; do not use fire-and-forget APIs for fallible edits.
- Include LWWMap website copy and its shared maps-family demo as specified
  below. Keep unrelated website copy and the other two plans unchanged.

### LWW-map dependency contract

The root manifest currently resolves `lattice_maps` 1.1.0. Its LWW-map
comments describe a left-biased tie rule, but `choose_winner` uses a
deterministic rule: tombstones beat values; between two values, the
lexicographically greater string wins. The published
[`lattice_maps-v1.1.0` source](https://github.com/tylerbutler/lattice/blob/lattice_maps-v1.1.0/packages/lattice_maps/src/lattice_maps/lww_map.gleam)
confirms that implementation. However, the value comparison is not
target-independent for all Unicode strings: equal-time U+E000/U+10000
writes select different winners on JavaScript and Erlang. The published
1.1.2 release also retains this defect. Add focused equal-timestamp
regressions, including this pair with one common expected winner on both
targets. A corrected upstream release is required before shipping under
this design. Do not reproduce Lattice's merge algorithm in Watershed.

LWW-map has no native `set_with_delta` API in that release. Produce a
single-key fragment with `set(new(), ...)` or `remove(new(), ...)`, then
join it into the local state. This uses existing Lattice operations without
shipping the whole map on each edit.

## Semantics

| DDS | Initial value | Edits | Conflict rule | Wire channel tag |
|---|---|---|---|---|
| `GCounter` | `0` | Increment by a nonnegative integer | Per-replica maximum, then sum | `gCounter` |
| `LwwRegister` | `""` | Set a string | Maximum timestamp, then replica ID | `lwwRegister` |
| `LwwMap` | Empty map | Set a string; remove a key | Per-key maximum timestamp; Lattice's tie rule | `lwwMap` |

GCounter rejects negative amounts without changing state or submitting an
operation. Zero is valid; it emits no visible-change event but can use the
existing operation-returning channel contract. The public API has no
decrement function. Rollback of a rejected optimistic increment can lower
the local visible value; confirmed CRDT state remains grow-only.

Register writes of the current value still create a newer timestamp and an
outbound operation, but emit no visible-change event. Initialize every
register with the same bottom value: `lww_register.new("", 0,
replica_id.new(""))`. Keep the local writer's replica ID in kernel state,
separate from the winning register's author.

Map removal of an absent key still creates a tombstone. A later write that
has observed that tombstone can restore the key with a larger timestamp.
Set/remove at the same timestamp resolves to removal. Two equal-timestamp
sets resolve by string value, not replica ID. Document this difference
from LWWRegister. Map iteration and event batches use sorted keys.

## LWW clocks and author identity

Add a small pure `lww_clock.gleam` module with
`next(last_seen: Int, wall_clock: Int) -> Result(Int, ClockError)`.
Choose `max(wall_clock, last_seen + 1)`. Accept nonnegative timestamps up
to `9_007_199_254_740_991`; report `InvalidTimestamp` or `ClockExhausted`
instead of overflowing JavaScript's exact-integer range.

The runtime supplies its existing wall-clock milliseconds. The register
tracks one high-water mark; the map tracks one per key. The kernel must
observe metadata from deltas, summary loads, stash replay, and full-state
imports, including map tombstones. Rollback does not rewind an issued
timestamp. A same-value write can advance the clock without an event.

Lattice's `lww_register.set` preserves the register's current author.
After a merge that author can belong to another peer. Create each local
write with `lww_register.new(value, timestamp, local_replica_id)` instead,
then merge. Do not use the PN-counter's rebranding trick for registers:
the stored winner's replica ID participates in conflict resolution.

Read opaque timestamp metadata through the published JSON codecs. Keep
decoder failures explicit; do not default a failed timestamp read to zero.
Reuse this clock policy, not the current OR-map summary-loading shortcut
that starts its clock empty. Changing existing OR-map behavior is outside
these plans.

## Kernel lifecycle

Each kernel stores sequenced state, optimistic state, a FIFO pending list,
and the next local message ID. Its local operation contains the CRDT
fragment and enough intent metadata for diagnostics and acknowledgment
matching. The fragment controls remote state.

1. A sequenced local edit updates optimistic state and queues the operation.
2. A local acknowledgment checks the oldest operation and message ID,
   joins its fragment into sequenced state, and emits no duplicate event.
3. A remote operation joins into sequenced and optimistic state, then emits
   the observed visible difference.
4. Rollback checks the newest pending entry and rebuilds optimistic state
   from sequenced state plus the remaining fragments.
5. Stash replay reuses the original fragment and timestamp. It does not
   generate another increment or restamp a register write.
6. Detached attach promotes the optimistic snapshot and clears pending
   entries. Ordinary summaries contain confirmed state only.
7. P2p edits commit to both states without pending entries or synthetic
   acknowledgments. Full-state merge uses the same join.

GCounter summary loads merge into `g_counter.new(local_replica_id)` to
preserve the joining writer's identity. LWW loads preserve winner metadata
and restore local clock observations. Local clock bookkeeping is not
replicated state and does not belong in the CRDT digest.

## Integration contract

For each DDS, extend `ChannelType`, `ChannelInit`, `ChannelState`,
`ChannelOperation`, `ChannelEvent`, `Snapshot`, and `P2pEdit`. Check
`LocalOperationMeta` and the acknowledgment dispatch as well.

Complete these channel functions: `new`, `from_snapshot`, `snapshot`,
`attach_snapshot`, `attach_state`, `apply_remote`, `ack_local`,
`apply_p2p_local`, `apply_p2p_remote`, `merge_p2p_snapshot`, `same_shape`,
`same_snapshot`, `handle_addresses`, `encode_snapshot`, and
`snapshot_decoder`. Scalar/string content yields no nested handle
addresses. Update the runtime core's submission, reconnection,
`resubmit`, and event paths as required. Rollback, stash replay, and
cache checks are kernel/harness contracts; do not invent runtime
services for hooks that the runtime does not currently expose.

The sequenced facades expose create, resolve, handle encoding, typed field
set/resolve/ensure, reads, fallible edits, and typed subscriptions.
Retain their existing JS callback and BEAM subject conventions.

Add typed p2p roots and browser read/edit/subscription functions. Extend
`crdt_core.init_for` so newly announced or imported snapshots can create
the new types. Use the existing CRDT envelopes, bounds, and opaque relay
transport. Applications using new kinds must choose a compatibility token
that excludes clients without those kinds; do not claim mixed-version
interoperability merely because the transport envelope is unchanged.

Use `gCounterIncrement`, `lwwRegisterSet`, `lwwMapSet`, and `lwwMapRemove`
operation tags. Encode fragments as stringified Lattice envelopes, as the
other kernels do. Validate tags, versions, payload types, timestamps, and
fragment/intent agreement before dispatch. Reject malformed data through
the existing decoder and channel error paths.

Lustre subscriptions must defer dispatch through the existing helpers.
Fallible edits use existing effect-perform thunks; do not mutate during
`update` or add a new effect framework.

## Digest and persistence

`crdt_core.merge_relevant` already removes GCounter's local `self_id`.
Retain that behavior for a standalone counter. Preserve LWW-register
timestamp and replica ID: equal visible strings can have different future
merge behavior.

Add an LWW-map projection that sorts the encoded entry array. Keep keys,
values, timestamps, tombstones, and the pruning watermark. Reject nonzero
watermarks in this release because Watershed has no causal-stability
protocol for pruning. Never reduce a digest to visible map entries.

Cover metadata-only changes in anti-entropy and persistence tests. A
silent subscription does not imply unchanged replicated state.

## LWWMap website integration

Add LWWMap beside SharedMap and OR-map on `/structures/maps`, using the
existing three-client `Demo.astro` rig and compiled Watershed kernel.
Register `lww-map` in the structure catalog and demo picker. Include its
homepage field sheet and update the maps-family introduction, merge-rule
caption, and field notes. Keep the homepage's live SharedMap demo focused
on SharedMap. No standalone demo page or new demo framework is required.

Show string edits, key removal and restoration, pending and confirmed
entries, and the winning per-key timestamps and tombstones. Use the
existing race, replay, delay/jitter, cut-link, and reset controls. Label the
rig as an in-page sequenced demonstration of a CRDT kernel, not as a live
mesh connection.

The default race must demonstrate a higher-timestamp write winning even
though the sequencer stamps it before a lower-timestamp write. Also offer
equal-time set/set and remove/set races: the lexicographically greater
string wins the former; the tombstone wins the latter. Replaying the
losing write must not restore a deleted key. A new write after observing
the tombstone must restore it with a higher timestamp. Browser coverage
must exercise these interactions, view switching, reconnect, and reset
with queued operations.

Explain what "last" means for each map: SharedMap uses server sequence
order; LWWMap uses per-key timestamps and deterministic ties, independent
of delivery order. Compare JSON values with strings, set/delete/clear
with set/remove, insertion order with sorted keys, and visible-entry
summaries with retained timestamp/tombstone metadata. Explain clock skew
and the per-key logical clock; do not promise that wall-clock timestamps
identify the last human action.

Both maps choose a whole value for a conflicting key. LWWMap does not
preserve concurrent alternatives or merge fields inside a value. Its
equal-time remove-wins rule differs from OR-map's observed-remove
add-wins rule, and its value-based tie differs from LWWRegister's
replica-ID tie. Keep these distinctions in the website copy and README.
The LWWMap plan's website task defines the comparison and acceptance cases.

## OR-map composition: what is missing

The restriction is in Watershed's adapter, not a missing transport.
The original adapter exposed `TallyMode` and `RegisterMode`. The first
composition follow-up adds `OrSetMode`, mapped to Lattice's existing
`OrSetSpec`, with `SetMembers(List(String))` values. It reuses the OR-map
channel, handles, roots, typed fields, and subscriptions.

Set mode adds member-level add/remove operations. Removing an absent
member is a no-op; removing the last member leaves an empty key. Removing
a key clears its observed members and outer-key tags, while concurrent
unseen additions survive. Re-add and stale replay must not restore removed
members. This differs from SharedMap's whole-value replacement and from
the existing tally mode's retained cumulative count.

Both sequenced facades expose fallible `or_map_add_member`,
`or_map_remove_member`, and `or_map_remove_key` methods. The last preserves
the legacy `or_map_remove` signature by providing a result-returning
companion. JS CRDT and the existing Lustre effects expose the same
behavior. Member updates emit `SetMembersUpdated`; key removal emits
`KeyRemoved`. Metadata-only changes replicate without a visible event.

The internal `or_map_set_leaf` helper handles author rebasing, strict
native codecs, safe per-key member/outer-key counter floors, and observed
member clearing. Native mutation replacement state is not authoritative:
the kernel applies the authored delta to its current state. Retained
inactive leaves need the same validation and counter observation as active
ones. Counter-only reservations in sequenced state survive rollback and
same-writer reload without including pending tags or members.

Released Lattice merge/apply paths discard `remove_bounds` inconsistently.
For set mode, the helper retains the per-key version-vector join from both
inputs, including history for active keys. Native Lattice still merges
keys and members. Full-state merge, delta application, rebranding, replay,
and clock-seed paths use this same correction. Canonical digests keep the
removal history, tags, and tombstones; only authoring cursors are excluded.
Tally/register modes remain unchanged, and pruning remains unsupported.

The maps-family inline demo adds a set/tally control within the existing
OR-map view. Changing that control starts fresh demo replicas, not a
production mode conversion. It distinguishes missing keys from empty sets
and demonstrates member races, key removal, replay, and SharedMap's
whole-value behavior without adding a separate DDS.

Lattice already supports GCounter, PNCounter, LWWRegister, MVRegister,
GSet, TwoPSet, and ORSet leaves. Its OR-map selects one `CrdtSpec` for
the map. The internal tagged union does not establish arbitrary mixed
types per key, nested maps, or Sequence/Text leaves. In particular,
Lattice's `Crdt` union excludes maps, so adding a standalone LWWMap will
not make it an OR-map value.

Broader homogeneous leaf support needs:

1. New modes with typed reads, edits, and events, plus mode mismatch errors.
2. Corresponding wire tags and snapshot spec decoding, keeping existing
   PN-counter and string-register encodings unchanged.
3. Leaf-aware author/counter state after removal, re-add, rollback, summary
   load, and stash replay; copying one pending-queue pattern is insufficient.
4. Canonical digest handling for each leaf's causal state, with set-array
   ordering and MV-register version history where applicable.
5. Sequenced, p2p, facade, and Lustre coverage for the added modes.

No separate channel per leaf is required. Adding a standalone DDS is also
not a prerequisite for using that Lattice leaf inside OR-map. Reuse kernel
policy where it applies, but do not embed complete DDS kernels as OR-map
values: that would duplicate pending queues and sequencing state.

Set mode is independent of the three plans below; it does not complete or
unblock LWWMap. Other leaf modes remain future composition work. Select
them explicitly rather than building a generic heterogeneous-map
abstraction.

## Delivery and acceptance

Implement GCounter first to establish the registration pattern, then
LWWRegister and its clock helper, then LWWMap.
Each plan includes its own complete integration and regression coverage.
LWWMap also requires the maps-family demo and comparison above before it
can be marked shipped.

- [GCounter plan](../plans/2026-09-09-g-counter-dds.md)
- [LWWRegister plan](../plans/2026-09-09-lww-register-dds.md)
- [LWWMap plan](../plans/2026-09-09-lww-map-dds.md)

For each type, demonstrate visible and digest convergence under reordered
and duplicate delivery, late join, restart/import, and mesh forwarding.
Cover wrong-type input, malformed fragments, FIFO acknowledgments, LIFO
rollback, unchanged visible values with changed metadata, and both target
facades. Use the existing startest, qcheck, Sluice, CRDT simulator, and
Lustre suites rather than adding test tools.
