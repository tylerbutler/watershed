# SharedDirectory kernel port plan

**Date:** 2026-07-04
**Builds on:** `2026-07-03-dds-porting-complexity.md` (rated
SharedDirectory 5/10), `src/watershed/map_kernel.gleam` (storage pending
lifetimes, optimistic reads, FIFO ack, LIFO rollback), and
`2026-07-03-kernel-fuzz-harness-plan.md`.
**Reference source:** `../FluidFramework/packages/dds/map/src/directory.ts`
(`SharedDirectory` + `SubDirectory`, 2726 LOC), `interfaces.ts`, and the
directory-specific tests under `../FluidFramework/packages/dds/map/src/test/mocha/`.

## Why SharedDirectory is this rung

SharedDirectory is "SharedMap, but recursive": each directory node has a
SharedMap-like key/value store and a named set of child directories. The storage
side can reuse `map_kernel` almost directly. The new complexity is in
**hierarchical identity**:

1. Ops address a directory by absolute path, but must only apply to the current
   live instance of that path.
2. A subdirectory can be concurrently created by multiple clients, deleted, and
   recreated under the same name.
3. Local optimistic create/delete affects reachability and event visibility
   before the server sequences the operation.

The port should be a pure tree kernel, not a direct object graph port. It should
preserve the upstream semantics while making directory identity and pending
state explicit data.

## Semantics inventory (from `directory.ts`)

| # | Behavior | Source |
|---|---|---|
| D1 | Five ops: `set{path,key,value}`, `delete{path,key}`, `clear{path}`, `createSubDirectory{path,subdirName}`, `deleteSubDirectory{path,subdirName}`. | directory.ts:95–213 |
| D2 | Summary shape is recursive `IDirectoryDataObject`: per-node `storage`, `subdirectories`, and create info `ci = {csn, ccIds}`; large values may spill to blobs, but the semantic content is one recursive tree. | directory.ts:303–342,1016–1080 |
| D3 | Every node has sequenced storage plus local pending storage entries. Pending sets aggregate into key lifetimes; delete/clear terminate prior lifetimes. Optimistic reads overlay pending on sequenced. | directory.ts:215–256,1693–1823 |
| D4 | Local `set`, `delete`, and `clear` optimistically update reads immediately and submit ops when attached; detached mode mutates sequenced state directly. | directory.ts:1207–1281,1500–1587 |
| D5 | Remote storage ops target `getSequencedWorkingDirectory(path)`, not optimistic directories. Ops for non-sequenced or disposed directories are ignored. | directory.ts:635–654,847–915 |
| D6 | Local storage acks strictly match pending metadata: set pops from the matching lifetime, delete removes matching delete, clear pops the oldest pending clear, then updates sequenced storage. | directory.ts:1894–2069 |
| D7 | Remote storage events are suppressed when pending local data would mask the remote change in the optimistic view. Remote clear also emits valueChanged events for pending sets whose sequenced base changed. | directory.ts:1917–1952,1989–2007,2053–2067 |
| D8 | Subdirectory local create validates the name, uses a local sequence marker (`seq=-1`, `clientSeq=localCreationSeq`) when attached or `seq=0` when detached, and reuses/undisposes an existing disposed node if needed. | directory.ts:1294–1374 |
| D9 | Subdirectory iteration returns sequenced and pending child dirs that are not pending-deleted, ordered by seq/clientSeq: acknowledged or detached dirs before unacked local dirs; lower seq/clientSeq first. | directory.ts:344–380,1437–1473 |
| D10 | Remote create creates or reuses the child, records the creator id, commits it into sequenced children, suppresses event if a local pending subdir op masks it, and stamps seq/clientSeq on a pending local node when acked. | directory.ts:2080–2168 |
| D11 | Remote/local delete removes the sequenced child, recursively disposes the old tree, and removes matching pending delete on local ack. Remote delete event is suppressed if a pending local delete already hides it. | directory.ts:2178–2240 |
| D12 | `isMessageForCurrentInstanceOfSubDirectory` filters stale ops after delete/recreate: local metadata must target this instance, or the op author must be one of this directory's creators, or the directory was detached-created, or the op's reference sequence number must cover this directory's creation sequence. | directory.ts:2600–2619 |
| D13 | Deleting a subdirectory clears its sequenced data and descendants but retains pending data so a re-create/rollback can continue to reference the same local object. | directory.ts:2630–2645,2713–2725 |
| D14 | Resubmit only sends still-relevant pending entries. Create resubmit adds the current client id and undisposes the pending tree; delete resubmit requires the originally deleted subdirectory. | directory.ts:2260–2384 |
| D15 | Rollback is LIFO at runtime but per-key/per-subdir lookup in the node: storage rollbacks remove pending entries and emit compensating events; create rollback emits dispose + subDirectoryDeleted; delete rollback undisposes and re-exposes the prior tree. | directory.ts:2432–2588 |
| D16 | `applyStashedOp` replays the public API (`set`, `delete`, `clear`, create/delete subdir) against the current working directory, generating fresh local metadata. | directory.ts:982–1014 |

## Kernel design

New module `src/watershed/directory_kernel.gleam`. It should reuse the
`map_kernel` storage algorithm, but not embed `MapState` directly unless doing so
keeps rollback/event behavior exact. The directory-specific state must track
node identity, path reachability, create sequence metadata, and child pending
ops.

### Types

```gleam
pub type DirectoryState {
  DirectoryState(root: DirectoryNode, next_local_create_seq: Int)
}

pub type DirectoryNode {
  DirectoryNode(
    path: String,
    create: CreateInfo,
    creators: List(Int),
    disposed: Bool,
    storage: StorageState,
    subdirs: Dict(String, DirectoryNode),
    pending_subdirs: List(PendingSubdir),
  )
}

pub type StorageState {
  StorageState(
    sequenced: Dict(String, Json),
    insertion_order: List(String),
    pending: List(PendingStorage),
  )
}

pub type PendingStorage {
  PendingLifetime(key: String, sets: List(Json), message_ids: List(Int))
  PendingDelete(key: String, message_id: Int)
  PendingClear(message_id: Int)
}

pub type PendingSubdir {
  PendingCreate(name: String, node_id: String, message_id: Int)
  PendingDelete(name: String, deleted_node: DirectoryNode, message_id: Int)
}

pub type CreateInfo {
  CreateInfo(seq: Int, client_seq: Int)
}

pub type DirectoryOp {
  Set(path: String, key: String, value: Json)
  Delete(path: String, key: String)
  Clear(path: String)
  CreateSubDirectory(path: String, name: String)
  DeleteSubDirectory(path: String, name: String)
}

pub type DirectoryEvent {
  ValueChanged(path: String, key: String, previous_value: Option(Json), local: Bool)
  Cleared(path: String, local: Bool)
  SubDirectoryCreated(path: String, local: Bool)
  SubDirectoryDeleted(path: String, local: Bool)
  Disposed(path: String)
  Undisposed(path: String)
}

pub type SequencedMeta {
  SequencedMeta(author: Int, sequence_number: Int, reference_sequence_number: Int, client_sequence_number: Int)
}
```

Use a `node_id` or equivalent stable local identity in pending metadata. Path
alone is not enough because delete/recreate can produce multiple lifetimes at
the same path.

### API surface

| Function | Signature (abbrev.) | Notes |
|---|---|---|
| `new` | `fn() -> DirectoryState` | Root has path `/`, create seq 0, not disposed. |
| `from_summary` / `summary_tree` | recursive tree round-trip | Preserve storage order, child order, create seq/clientSeq and creators. Pending is not summarized. |
| `get_working_directory` | optimistic path lookup | Uses pending subdir entries and disposed state. |
| `get_sequenced_directory` | sequenced-only path lookup | Used by `apply_remote`/`ack_local`, matching D5. |
| storage reads | `get` / `has` / `entries` / `keys` / `size` with path | Reuse `map_kernel` optimistic rules per node. |
| subdir reads | `subdirectories` / `has_subdirectory` / `count_subdirectory` | Optimistic children sorted by `seqDataComparator`. |
| `set` / `delete` / `clear` | attached local ops | Mutate pending storage, emit local events, return `DirectoryOp` + message id. |
| `*_detached` | detached local ops | Mutate sequenced storage or children directly; no pending. |
| `create_subdirectory` | local create | Validates name, creates/reuses/undisposes pending node, appends `PendingCreate`, emits created, returns op. |
| `delete_subdirectory` | local delete | If optimistically absent return false; otherwise append `PendingDelete`, emit deleted + dispose events, return op. |
| `apply_remote` | `fn(state, op, SequencedMeta) -> #(state, events)` | Routes through sequenced directory and stale-instance filter. |
| `ack_local` | `fn(state, op, message_id, SequencedMeta) -> Result(#(state, events), KernelError)` | Strict pending match for storage/subdir ops. |
| `rollback` | `fn(state, op, message_id) -> Result(#(state, events), KernelError)` | LIFO-compatible but searches the affected key/subdir as upstream does. |
| `resubmit` | `fn(state, op, message_id, self_id, next_message_id) -> Result(#(state, Option(#(state, op, message_id))), KernelError)` | Only resubmits still-present pending entries; create resubmit adds current creator id and undisposes. |
| `apply_stashed_op` | `fn(state, op, self_id, next_message_id) -> Result(#(state, List(events), Option(#(op, message_id))), KernelError)` | Replays through public local API, generating new pending metadata. |
| `check_invariants` | `fn(state) -> Result(Nil, KernelError)` | No duplicate visible child names; every child path matches parent; disposed children not reachable optimistically unless pending metadata needs them. |

### Design decisions

1. **Use `map_kernel` semantics per node, not a flat path map.** A flat
   `Dict(#(path,key), value)` would miss per-directory iteration order and clear
   semantics. Each node needs its own storage pending list and insertion order.
2. **Model stale-instance filtering explicitly.** D12 is the core correctness
   rule for delete/recreate races. The kernel should store creator ids and
   create sequence data and take `reference_sequence_number` in `SequencedMeta`
   so remote ops can be ignored deterministically when they target an old
   directory lifetime.
3. **Keep optimistic and sequenced path lookup separate.** Local API calls use
   optimistic reachability; sequenced delivery uses only sequenced directories.
   Merging these helpers is the easiest way to process ops on a pending local
   directory out of order.
4. **Preserve disposed nodes in pending metadata.** A pending delete must be
   rollbackable, and a deleted/recreated directory may keep pending local
   storage. Do not eagerly discard node state just because the path is hidden.
5. **Event output is part of the kernel contract.** Directory has subtle
   suppression rules around pending masks and reachability. Returning explicit
   events lets unit tests pin behavior without an event-emitter wrapper.
6. **Client ids are `Int`, matching other consensus kernels.** Runtime
   integration can map Fluid string client ids to ints at the delivery boundary.

## Test plan (TDD — tests first)

### 1. `test/watershed/directory_kernel_test.gleam`

Port focused upstream unit groups into pure transitions:

- **Local/detached API:** root set/get/delete/clear, nested create/set,
  invalid subdir names, detached mutations commit directly and summarize.
- **Storage parity with `map_kernel`:** pending set lifetimes, delete/clear
  termination, optimistic iteration order, remote set/delete/clear suppression,
  local ack transparency, and rollback compensation events.
- **Path routing:** ops for missing, disposed, pending-only, or stale directory
  instances are ignored; ops for current sequenced instances apply.
- **Subdirectory create/delete:** local create visible immediately; duplicate
  create does not duplicate; local delete hides and emits dispose; remote create
  can reuse/undispose; remote delete disposes and clears sequenced descendants.
- **Concurrent same-name create:** two clients create `/b`; both converge to one
  visible `/b` whose creators include both clients, with deterministic child
  ordering.
- **Delete/recreate races:** create `/a`, delete `/a`, recreate `/a`, then
  deliver old set/delete ops against the former `/a`; stale ops are ignored
  unless their reference sequence covers the new directory creation.
- **Subdir iteration order:** acknowledged children before unacked local
  children; lower seq/clientSeq first; delete/readd moves the child to its new
  lifetime position.
- **Summary/load:** recursive storage + subdirs + create info round-trip,
  pending excluded, old/no-create-info summaries load with seq 0 semantics.
- **Rollback/resubmit/stash:** storage and subdir rollbacks match upstream
  events; resubmit filters deleted/stale pending ops; stash replays through the
  local API and creates fresh pending metadata.

### 2. Fuzz/property coverage

Ship `test/watershed/fuzz/directory_model.gleam` and
`test/watershed/directory_fuzz_test.gleam`.

Start with a bounded tree:

- paths generated from `/`, `/a`, `/b`, `/a/x`, `/b/y`;
- keys `k0..k3`;
- ops weighted toward storage ops, with create/delete subdir frequent enough to
  hit stale-instance cases.

Model shape:

- `op` = the five `DirectoryOp` variants plus submit-time metadata slots for
  `reference_sequence_number` and `client_sequence_number`.
- `submit` fills path from the client's optimistic tree; if a target path is not
  reachable, it drops the command.
- `observe` = canonical recursive summary of visible sequenced state: sorted
  paths, per-node storage entries in iteration order, and child names in
  directory order.
- `oracle` = independent recursive tree interpreter with the same path-instance
  rules, not delegated to the kernel.
- Capabilities: summary round-trip, rollback, resubmit, stashed ops.

Properties:

- **Convergence:** after full sync, every client's canonical recursive summary
  matches.
- **Oracle:** visible sequenced tree equals the independent interpreter.
- **Per-node map law:** every live node's storage state satisfies the existing
  map-kernel oracle for its local op subsequence.
- **Reachability:** no disposed directory is reachable through
  `get_working_directory`; every reachable node's path is unique.
- **Create/delete lifetime safety:** stale ops cannot mutate a recreated
  directory unless their refSeq covers that directory's create seq.
- **Order stability:** key order and subdirectory order are deterministic across
  clients after full delivery.

Mutation checks:

- Plant "remote delivery uses optimistic path lookup" — stale/pending directory
  ops mutate the wrong node and oracle diverges.
- Plant "drop create info from summary" — load + post-summary stale op diverges.
- Plant "dispose deletes pending storage" — rollback/recreate loses pending data.
- Plant "duplicate same-name creates produce two children" — convergence or
  unique-path invariant fails.

## Out of scope

- Runtime channel integration, public `IDirectory` object wrappers, event
  emitters, handle serialization/GC, large-value blob splitting, and wire
  codecs.
- Performance optimizations for huge directory trees; start with persistent
  recursive records and stable sorted traversals.
- Back-compat quirks beyond loading old summaries without `ci`; old storage blob
  layout can be normalized before calling `from_summary`.

## Milestones

**SD1 — Storage-on-tree core (1 day).** Directory node type, path helpers,
summary round-trip, storage reads/writes/acks/rollback by reusing map-kernel
logic.
Exit: root and nested storage tests pass, including pending masks and iteration
order.

**SD2 — Subdirectory lifecycle (1–1.5 days).** Create/delete, disposed/undisposed
state, create info, optimistic vs sequenced path lookup, stale-instance filter.
Exit: create/delete/recreate and subdir-order tests pass.

**SD3 — Resubmit/stash + fuzz (1–1.5 days).** Resubmit filtering, stashed op
replay, bounded-tree fuzz model, oracle, mutation checks.
Exit: 1000 seeded runs green; all mutation checks fail as expected.

Total: **~3–4 days**, consistent with the 5/10 rating and with storage semantics
already available from `map_kernel`.

## Open questions

- Should `directory_kernel` call into `map_kernel` directly for storage, or copy
  the small storage state so directory-specific events/path fields can stay
  first-class? Leaning copy/extract a shared internal helper only after the
  tests reveal real duplication.
- Should create-info `ccIds` preserve every concurrent creator for runtime
  parity, or can the kernel store only the predicate needed by D12? Leaning full
  creator list because summary parity and stale-op filtering both use it.

## Status (2026-07-05)

- **SD1 — Storage-on-tree: DONE.**
- **SD2 — Subdirectory lifecycle: DONE.**
- **SD3 — Resubmit/stash + fuzz: PARTIAL.** The fuzz model, oracle, and harness
  wiring are in place; `just test` (default fuzz depth) is green (512 tests). A
  deep sweep (`FUZZ_ITERATIONS=5000 gleam test`) still finds rare convergence
  divergences in **one** class — subdirectory *instance aliasing* under stash +
  disconnect + concurrent create/delete/recreate of the same name.

  Several instance-aliasing bugs were fixed this milestone: a `committed` flag on
  pending creates (delete/recreate disambiguation), D10 (remote create keeps the
  author's pending marker), a create-absorption **storage merge** (a live
  optimistic subdir create absorbed into a concurrently-created sequenced
  instance now merges its storage writes into the surviving instance instead of
  dropping them), and an FF-faithful storage-ack rule (`targetSubdir === this`:
  an ack is a stale no-op unless its id is a live pending in the *current*
  instance at the path).

  **Remaining root cause:** storage pending lives inside *per-instance node
  copies* (pending-create nodes and sequenced nodes) and is moved/split/dropped
  across instance transitions, whereas observers always apply remote ops to the
  single sequenced node per path. The faithful fix is a refactor to FF's
  single-`SubDirectory`-object-per-path model: one node per path holds both
  sequenced and pending storage, with create/delete lifecycle as flags/creator
  ids on that same node — storage is never copied between instances. This is the
  "stable local identity" direction noted above and touches `optimistic_child`/
  `put_optimistic_child`, `create_subdirectory`/`delete_subdirectory`,
  `remote_create_subdir`/`remote_delete_subdir`, and `ack_create_subdir`/
  `ack_delete_subdir`. Tracked as a dedicated follow-up.

## Status (2026-07-06) — single-node refactor + resubmit fidelity

- **SD3 — Resubmit/stash + fuzz: still PARTIAL, materially improved.** The
  single-node refactor above was carried out: each path now holds one node whose
  storage is shared across the fold/delete/recreate lifecycle (a `folded` marker
  keeps the pending-create node in sync with sequenced writes), and
  `optimistic_child` falls back to the retained (disposed) marker node when a
  concurrent delete clears the sequenced slot, mirroring FF's
  `getOptimisticSubDirectory(getIfDisposed=true)`. This fixed a **storage
  copy-drift convergence bug** (sequenced writes to a folded subdir were lost
  when a remote delete cleared the slot, then an ack re-inserted a stale-empty
  marker).

  The fuzz harness also gained a `resubmit` capability wired into `reconnect`,
  mirroring a DDS's `reSubmitCore`: on reconnect each queued op is re-stamped to
  the client's current reference sequence number and **dropped if its target
  instance no longer exists** (the kernel's `resubmit` filter). Previously the
  harness resent stashed ops with a stale `ref_seq`, making the kernel's
  instance-identity check (`is_message_for_current_instance`) resolve differently
  across clients — a real convergence divergence, now fixed.

  `just test`/`just build`/`just lint` green (512). Deep sweeps
  (`FUZZ_ITERATIONS=5000`) now pass on most runs and the previously-reproducing
  fixtures converge, but a **rare residual instance-aliasing divergence** still
  appears at ~5000–20000 iterations: a `Set` on a subdir instance commits on one
  client but not another because the surviving instance's identity
  (`creators`/`create.seq`) is built differently after extreme concurrent
  create/delete/recreate + stash/reconnect.

  **Remaining root cause (refined):** the pure kernel approximates FF's single
  mutable `SubDirectory` object identity with a `(create.seq, creators, ref_seq)`
  heuristic. FF additionally runs a precise `clientIds`/`seqData` lifecycle —
  notably `clearSubDirectorySequencedData` (clears `clientIds`, re-adds the local
  client, resets `seqData.seq = -1` on dispose) and the seqData re-stamp in
  `processCreateSubDirectoryMessage` — that the kernel does not fully replicate. A
  naive port of the `clientIds` reset was attempted and **regressed** the baseline
  (it fixed some cases while breaking others), confirming the fix must port the
  whole lifecycle coherently rather than one rule at a time. Tracked as the
  remaining SD3 follow-up.

