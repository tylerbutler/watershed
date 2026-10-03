# SharedTree Undo and Redo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete M5 with application-owned revertible handles that undo and redo local SharedTree commits after later local or remote edits.

**Architecture:** Extend the pure history with retained revertible branches, use the existing SharedTree inversion and rebase algebra to author one ordinary inverse commit, and emit separate local-commit and settlement events through `runtime_core`. JavaScript and BEAM convert those pure events into one-shot factories, runtime-local opaque handles, and asynchronous settlement callbacks while applications own their undo and redo stacks.

**Tech Stack:** Dual-target Gleam; startest; Node test runner; `@fluidframework/tree` 3.1.0 published-package and source oracles; pinned Floodgate; existing `just` and GitHub Actions gates.

**Spec:** [SharedTree undo and redo](../specs/2026-10-02-shared-tree-undo-redo-design.md)

## Global Constraints

- Production SharedTree semantics must run in pure Gleam on JavaScript and BEAM.
- Upstream TypeScript packages remain development and test dependencies.
- Use `@fluidframework/tree` version `3.1.0`.
- Use Fluid Framework commit `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960` (`client_v3.1.0`).
- Use Floodgate commit `0eb493fc46d1bb9baf1151a6ccdde93544e057e7`.
- Keep `minVersionForCollab` at `2.117.0`.
- Keep Message V7, SharedTreeChange V5, ModularChange V5, and Schema V2.
- Preserve the existing fixed container layout.
- Preserve M1-M4, Identifier, and transaction behavior and interoperability evidence.
- Reject unsupported operations instead of approximating their meaning.
- Apply ASD-STE100 to Gleam comments and error strings, not to Markdown prose.
- Do not edit generated files, `.code-map/`, or apm-managed files.

---

## 1. Starting point and execution rules

Planning baseline: `b06f795a` (`docs(tree): design undo and redo`).

The transaction-foundation slice is complete through `4dbb62d0`. Preserve its
constraint algebra, transaction boundaries, reconnect behavior, Identifier
support, and interoperability evidence.

Use test-first steps. Add one named failing case, run it, implement the
smallest complete behavior, and run it again before adding the next case.
Commit each task separately. Do not stage unrelated files.

Do not add a Watershed-managed undo stack. Do not serialize handles. Do not add
a second inversion or sequence algorithm. Reuse `shared_change.invert`,
`shared_change.rebase`, the history branch model, and ordinary local commit
submission.

### Dependency order

```text
1 pinned undo/redo oracle and corpus
                 |
2 commit metadata and retained history handles
                 |
3 pure inverse authoring and kernel events
                 |
4 runtime-core acquisition, reversion, and settlement
              /     \
5 JavaScript facade  6 BEAM facade
              \     /
7 recovery, summaries, and full native matrix
                 |
8 mixed-client and real-service proof
                 |
9 permanent gates and M5 profile closure
                 |
10 full regression closure
```

Tasks 5 and 6 can proceed in parallel after Task 4 if they have separate file
ownership. Keep Tasks 2-4 under one integration owner because they share
history, kernel, event, and runtime-core contracts.

## 2. File map

| File or group | Responsibility |
| --- | --- |
| `src/watershed/tree/types.gleam` | Commit kind, settlement outcome, and internal revertible identifiers. |
| `src/watershed/tree/history.gleam` | Retained revertible branches, inverse authoring, repeated reversion, disposal, and trimming pins. |
| `src/watershed/tree_kernel.gleam` | Retain/dispose/revert operations, forest application, and commit event derivation. |
| `src/watershed/channel.gleam` | Internal commit-applied and commit-settled channel events. |
| `src/watershed/runtime_core.gleam` | Revertible registry routing, transaction exclusion, local commit kinds, and settlement events. |
| `src/watershed/runtime.gleam` | JavaScript one-shot factories, callback registration, handle routing, and cleanup. |
| `src/watershed/runtime_beam.gleam` | BEAM actor messages, one-shot factories, callback registration, handle routing, and cleanup. |
| `src/watershed.gleam`, `src/watershed_beam.gleam` | Public types, subscriptions, opaque handles, revert, status, and disposal. |
| `tools/shared-tree-oracle/upstream-undo-redo.spec.ts` | Pinned source capture for factory, lifetime, commit kind, settlement, and rebase behavior. |
| Existing oracle source/generate/schema/client/interop/service files | Register, validate, run, and gate the undo/redo corpus and clients. |
| `test/watershed/tree/undo_fixture.gleam` | Input-only native corpus runner. |
| Existing history, kernel, runtime, facade, array, map, transaction, and summary tests | Focused native behavior and regression coverage. |

Do not introduce a public branch API, a generic command framework, or a second
event bus.

## 3. Shared implementation interfaces

Add declarations only when their owning task starts.

### Commit metadata, owned by Task 2

```gleam
pub type TreeCommitKind {
  DefaultCommit
  UndoCommit
  RedoCommit
}

pub type TreeCommitOutcome {
  FullyApplied
  FullyDropped
  NewContentOnly
}

pub type RevertibleId {
  RevertibleId(value: Int)
}
```

Add internal channel events without changing `tree_kernel.TreeEvent`:

```gleam
TreeCommitApplied(
  revision: fluid_ids.StableId,
  kind: tree_types.TreeCommitKind,
  local: Bool,
  revertible: Bool,
)

TreeCommitSettled(
  revision: fluid_ids.StableId,
  outcome: tree_types.TreeCommitOutcome,
)
```

Remote commits use `DefaultCommit`, `local: False`, and `revertible: False`.

### History retention, owned by Task 2

```gleam
pub fn retain_revertible(
  state: History,
  revision: fluid_ids.StableId,
  kind: tree_types.TreeCommitKind,
) -> Result(#(History, tree_types.RevertibleId), TreeError)

pub fn revertible_is_valid(
  state: History,
  id: tree_types.RevertibleId,
) -> Bool

pub fn dispose_revertible(
  state: History,
  id: tree_types.RevertibleId,
) -> Result(History, TreeError)
```

Each retained record keeps a branch position through the target commit and
pins the ancestry and rollback data needed by inversion. `retain_revertible`
rejects a second retained record for the same revision in one history.

### Inverse authoring, owned by Task 3

```gleam
pub type RevertAuthoring {
  RevertAuthoring(
    history: History,
    commit: Commit,
    kind: tree_types.TreeCommitKind,
  )
}

pub fn author_revert(
  state: History,
  id: tree_types.RevertibleId,
  revision: fluid_ids.StableId,
  order: change.IdentityOrder,
) -> Result(RevertAuthoring, TreeError)
```

`author_revert` does not append the returned commit. It inverts the retained
target with `is_rollback: False`, rebases that inverse over the current head,
and returns `UndoCommit` for a default or redo target and `RedoCommit` for an
undo target. A valid handle can author more than one revert.

### Kernel operations, owned by Task 3

```gleam
pub fn retain_revertible(
  state: TreeState,
  revision: fluid_ids.StableId,
  kind: tree_types.TreeCommitKind,
) -> Result(#(TreeState, tree_types.RevertibleId), TreeError)

pub fn revertible_is_valid(
  state: TreeState,
  id: tree_types.RevertibleId,
) -> Bool

pub fn dispose_revertible(
  state: TreeState,
  id: tree_types.RevertibleId,
) -> Result(TreeState, TreeError)

pub fn revert(
  state: TreeState,
  id: tree_types.RevertibleId,
  revision: fluid_ids.StableId,
  order: change.IdentityOrder,
) -> Result(#(TreeState, history.Commit, tree_types.TreeCommitKind, ChangeEvents), TreeError)
```

`revert` applies the inverse through the ordinary forest and history append
path. It does not dispose the handle.

### Runtime-core operations, owned by Task 4

```gleam
pub fn retain_tree_revertible(
  core: Core,
  address: String,
  revision: fluid_ids.StableId,
  kind: tree_types.TreeCommitKind,
) -> Result(#(Core, tree_types.RevertibleId), CoreError)

pub fn tree_revertible_is_valid(
  core: Core,
  address: String,
  id: tree_types.RevertibleId,
) -> Bool

pub fn dispose_tree_revertible(
  core: Core,
  address: String,
  id: tree_types.RevertibleId,
) -> Result(Core, CoreError)

pub fn revert_tree(
  core: Core,
  address: String,
  id: tree_types.RevertibleId,
) -> Result(#(Core, List(#(String, ChannelEvent)), wire.OutboundOperation), CoreError)
```

`revert_tree` rejects an active transaction, mints one revision, appends one
local commit, emits `TreeCommitApplied`, and returns one ordinary outbound
operation.

### Public API, owned by Tasks 5 and 6

Each target runtime owns its opaque handle, event closure values, and
subscription token. The facade exposes target-specific aliases so runtime
modules do not import facade modules.

```gleam
pub type TreeRevertibleStatus {
  RevertibleValid
  RevertibleDisposed
}

pub opaque type TreeRevertible

pub type TreeRevertibleFactory =
  fn() -> Result(TreeRevertible, String)

pub type TreeCommitSettlement =
  fn(fn(tree_types.TreeCommitOutcome) -> Nil) -> Result(Nil, String)

pub type TreeCommitEvent {
  TreeCommitEvent(
    kind: tree_types.TreeCommitKind,
    local: Bool,
    get_revertible: Option(TreeRevertibleFactory),
    on_settled: Option(TreeCommitSettlement),
  )
}

pub fn subscribe_tree_commits(
  tree: SharedTree,
  handler: fn(TreeCommitEvent) -> Nil,
) -> SubscriptionToken

pub fn tree_revertible_status(
  revertible: TreeRevertible,
) -> TreeRevertibleStatus

pub fn tree_revert(
  revertible: TreeRevertible,
  dispose: Bool,
) -> Result(Nil, String)

pub fn tree_dispose_revertible(
  revertible: TreeRevertible,
) -> Result(Nil, String)
```

Both facades use the callback signature above. The BEAM actor runs registered
handlers in a monitored delivery process so it can service factory and
settlement-registration requests before it closes the event.

## 4. Implementation tasks

### Task 1: Capture and verify the pinned undo/redo contract

**Files:**
- Create: `tools/shared-tree-oracle/upstream-undo-redo.spec.ts`
- Modify: `tools/shared-tree-oracle/source.mjs`
- Modify: `tools/shared-tree-oracle/source.test.mjs`
- Modify: `tools/shared-tree-oracle/generate.mjs`
- Modify: `tools/shared-tree-oracle/generate.test.mjs`
- Modify: `tools/shared-tree-oracle/README.md`
- Generate: undo/redo corpus files, `manifest.json`, and capture metadata

**Interfaces:**
- Consumes: pinned Fluid source, existing source injection, corpus manifest,
  schema catalog, and observation normalization.
- Produces: exact factory, status, repeated revert, commit-kind, settlement,
  field-kind, reconnect, and reload observations used by Tasks 2-8.

- [ ] **Step 1: Add failing source-registration tests.**

Export:

```javascript
export const undoRedoInjectedTestPath =
  "packages/dds/tree/src/test/watershedUndoRedo.spec.ts";
```

Require these case IDs:

```javascript
const requiredUndoRedoCases = [
  "revertible-lifetime",
  "undo-redo-kinds",
  "undo-redo-fields",
  "undo-redo-constraints",
  "undo-redo-reconnect",
];
```

For each case, test rejection after removing the case, clearing observations,
removing `input`, or changing the pinned source commit.

Run:

```bash
node --test tools/shared-tree-oracle/source.test.mjs tools/shared-tree-oracle/generate.test.mjs
```

Expected red: missing undo/redo injection and required-case checks.

- [ ] **Step 2: Capture factory and lifetime behavior.**

In the injected source test, register two changed listeners and record:

```typescript
view.events.on("changed", (metadata, getRevertible) => {
  observations.push({
    kind: metadata.kind,
    local: metadata.isLocal,
    factory: getRevertible !== undefined,
  });
});
```

Capture:

- one factory during a local data event;
- no factory for a schema event or remote event;
- one successful factory call;
- a duplicate call error;
- a late call error;
- `Valid` before revert;
- default disposal after revert;
- `Valid` after `revert(false)`;
- repeated `revert(false)` on the same handle;
- an error after a second disposal or revert of a disposed handle.

- [ ] **Step 3: Capture commit kinds and settlement outcomes.**

Record the event sequence:

```text
DefaultCommit -> UndoCommit -> RedoCommit
```

Register `metadata.events.on("settled", ...)` during each local event. Capture
`FullyApplied`, `FullyDropped`, and `NewContentOnly` from pinned cases. Assert
the settlement callback fires once and only after sequencing.

- [ ] **Step 4: Capture field and transaction behavior.**

Use the existing object, dynamic-map, array, move, Identifier, and transaction
schemas. Capture:

- object set and replacement;
- map set and delete;
- array insert and remove;
- same-array and cross-array move;
- one outer transaction reverted as one unit;
- later unrelated local and remote edits;
- overlapping remote edits in both sequence orders;
- revert-time node constraint satisfaction and violation.

Record snapshots, emitted events, commit kinds, settlement outcomes, retained
handle status, and canonical encoded changes.

- [ ] **Step 5: Capture reconnect and reload behavior.**

Keep one handle alive across disconnect and reconnect in the same view, then
revert it. Publish and load summaries after committed undo and redo. Assert the
loaded document contains the committed result and exposes no handle for an old
commit.

- [ ] **Step 6: Generate and verify the corpus.**

```bash
npm --prefix tools/shared-tree-oracle run source:prepare
npm --prefix tools/shared-tree-oracle run source:verify
npm --prefix tools/shared-tree-oracle run generate
npm --prefix tools/shared-tree-oracle run check
npm --prefix tools/shared-tree-oracle test
```

Expected green: every required case is present, nonempty, pinned, and stable.

- [ ] **Step 7: Commit the oracle contract.**

```bash
git add tools/shared-tree-oracle test/fixtures/shared_tree
git commit -m "test(tree): capture undo and redo contract"
```

### Task 2: Add commit metadata and retained history handles

**Files:**
- Modify: `src/watershed/tree/types.gleam`
- Modify: `src/watershed/tree/history.gleam`
- Modify: `src/watershed/channel.gleam`
- Modify: `test/watershed/shared_tree_history_test.gleam`
- Modify: `test/watershed/shared_tree_channel_test.gleam`

**Interfaces:**
- Consumes: Task 1 factory, disposal, and repeated-revert observations.
- Produces: `TreeCommitKind`, `TreeCommitOutcome`, `RevertibleId`,
  `retain_revertible`, `revertible_is_valid`, `dispose_revertible`, and
  internal commit events.

- [ ] **Step 1: Write failing type and channel-event tests.**

Add tests that construct and match:

```gleam
let kind = tree_types.UndoCommit
let outcome = tree_types.NewContentOnly
let event =
  channel.TreeCommitApplied(revision, kind, True, True)
```

Add a second case for:

```gleam
channel.TreeCommitSettled(revision, tree_types.FullyApplied)
```

Run:

```bash
gleam test --target erlang -- shared_tree_channel
gleam test --target javascript -- shared_tree_channel
```

Expected red: the types and channel variants do not exist.

- [ ] **Step 2: Add commit metadata types.**

Add the exact declarations from section 3 to
`src/watershed/tree/types.gleam`. Extend exhaustive matches in
`src/watershed/channel.gleam` without routing these events through
`tree_kernel.TreeEvent`.

- [ ] **Step 3: Write failing retention tests.**

In `shared_tree_history_test.gleam`, append and sequence commits A, B, and C.
Retain B:

```gleam
let assert Ok(#(retained, id)) =
  history.retain_revertible(state, revision_b, tree_types.DefaultCommit)
let assert True = history.revertible_is_valid(retained, id)
```

Advance the minimum sequence number beyond B and assert B remains available
for the retained record. Dispose the handle, advance the minimum again, and
assert the old branch can trim. Add duplicate-revision and double-disposal
errors.

Run:

```bash
gleam test --target erlang -- shared_tree_history
gleam test --target javascript -- shared_tree_history
```

Expected red: retention functions are missing.

- [ ] **Step 4: Store retained branch positions in history.**

Extend the opaque history with:

```gleam
type RevertibleRecord {
  RevertibleRecord(
    id: tree_types.RevertibleId,
    revision: fluid_ids.StableId,
    kind: tree_types.TreeCommitKind,
    base: BranchBase,
    commits: List(BranchCommit),
  )
}
```

Add:

```gleam
revertibles: List(RevertibleRecord),
next_revertible_id: Int,
```

Initialize and restore them as empty runtime-local state. Do not add them to
`HistorySnapshot`.

- [ ] **Step 5: Pin retained history during trimming.**

Before selecting the new history base, cap the trim point at the earliest base
required by a live revertible. Preserve rollback entries whose source nodes
appear in a retained branch:

```gleam
fn retained_nodes(state: History) -> List(Int) {
  state.revertibles
  |> list.flat_map(fn(record) {
    list.map(record.commits, fn(commit) { commit.node_id })
  })
}
```

Include those nodes in `prune_rollbacks`. Disposal removes the record so the
next `advance_minimum` can release it.

- [ ] **Step 6: Run focused history and channel tests.**

```bash
gleam test --target erlang -- shared_tree_history shared_tree_channel
gleam test --target javascript -- shared_tree_history shared_tree_channel
```

- [ ] **Step 7: Commit retained history support.**

```bash
git add src/watershed/tree/types.gleam src/watershed/tree/history.gleam src/watershed/channel.gleam test/watershed/shared_tree_history_test.gleam test/watershed/shared_tree_channel_test.gleam
git commit -m "feat(tree): retain undo history"
```

### Task 3: Author inverse commits and expose kernel operations

**Files:**
- Modify: `src/watershed/tree/history.gleam`
- Modify: `src/watershed/tree_kernel.gleam`
- Create: `test/watershed/tree/undo_fixture.gleam`
- Create: `test/watershed/shared_tree_undo_test.gleam`
- Modify: `test/watershed/shared_tree_kernel_test.gleam`
- Modify: `test/watershed/shared_tree_fixture_test.gleam`

**Interfaces:**
- Consumes: Task 2 retained records and Task 1 canonical changes.
- Produces: `author_revert`, kernel retain/status/dispose/revert operations,
  native corpus execution, and field-independent inverse authoring.

- [ ] **Step 1: Write a failing default-to-undo history test.**

Create commits A and B where B changes one object field. Retain B, append C on
another field, and call:

```gleam
let assert Ok(history.RevertAuthoring(_, inverse, tree_types.UndoCommit)) =
  history.author_revert(state, id, inverse_revision, order)
```

Assert the inverse revision is `inverse_revision`, the target revision remains
B, and rebasing over C preserves C.

Run:

```bash
gleam test --target erlang -- shared_tree_undo
gleam test --target javascript -- shared_tree_undo
```

Expected red: `author_revert` does not exist.

- [ ] **Step 2: Implement inverse authoring with existing algebra.**

Locate the retained target and current head. Use:

```gleam
shared_change.invert(
  shared_change.TaggedChange(
    Some(target.commit.revision),
    None,
    target.commit.change,
  ),
  False,
  inverse_revision,
)
```

Rebase the inverse over every later commit with the existing rebase context and
identity order. Do not use `rollback_for`, because rollback inversion uses
`is_rollback: True`.

- [ ] **Step 3: Add redo and repeated-revert tests.**

Retain an `UndoCommit` and assert `author_revert` returns `RedoCommit`. Call
`author_revert` twice with different fresh revisions on one still-valid handle
and assert both calls succeed. Dispose it and assert the next call fails.

- [ ] **Step 4: Write failing kernel forest tests.**

Build a tree with object, map, and array content. Retain one local commit,
append an unrelated commit, and call `tree_kernel.revert`. Assert:

- one returned commit;
- one derived `UndoCommit`;
- one set of visible change events;
- unrelated content remains;
- the retained handle remains valid.

- [ ] **Step 5: Implement kernel operations.**

Delegate retention and disposal to history. For `revert`:

1. Call `history.author_revert`.
2. Apply the authored inverse with the supplied identity order.
3. Append it through `history.append_local`.
4. Update visible state, authoring schemas, and local ID state through the same
   helpers as ordinary local edits.
5. Return the commit kind and existing `ChangeEvents`.

- [ ] **Step 6: Add native corpus runner.**

`test/watershed/tree/undo_fixture.gleam` must accept Task 1 inputs and return
only native observations. Cover object, map, array, move, transaction,
constraint, repeated-revert, and status cases.

Register the runner in `shared_tree_fixture_test.gleam`. Compare canonical JSON
against the generated fixtures on both targets.

- [ ] **Step 7: Run history, kernel, and corpus tests.**

```bash
gleam test --target erlang -- shared_tree_undo shared_tree_history shared_tree_kernel shared_tree_fixture
gleam test --target javascript -- shared_tree_undo shared_tree_history shared_tree_kernel shared_tree_fixture
```

- [ ] **Step 8: Commit pure undo and redo semantics.**

```bash
git add src/watershed/tree/history.gleam src/watershed/tree_kernel.gleam test/watershed/tree/undo_fixture.gleam test/watershed/shared_tree_undo_test.gleam test/watershed/shared_tree_kernel_test.gleam test/watershed/shared_tree_fixture_test.gleam
git commit -m "feat(tree): author undo and redo commits"
```

### Task 4: Integrate revertibles and settlement into runtime core

**Files:**
- Modify: `src/watershed/runtime_core.gleam`
- Modify: `src/watershed/tree/runtime.gleam`
- Modify: `src/watershed/channel.gleam`
- Modify: `test/watershed/shared_tree_runtime_test.gleam`
- Modify: `test/watershed/shared_tree_history_resubmit_test.gleam`

**Interfaces:**
- Consumes: Task 3 kernel operations and internal channel events.
- Produces: runtime-core acquisition, status, disposal, reversion, local commit
  kinds, settlement outcomes, reconnect retention, and ordinary outbound
  operations.

- [ ] **Step 1: Write failing acquisition and reversion tests.**

After one ordinary local edit, extract the revision from the returned
`TreeCommitApplied` event:

```gleam
let assert Ok(#(core, id)) =
  runtime_core.retain_tree_revertible(
    core,
    address,
    revision,
    tree_types.DefaultCommit,
  )
let assert True =
  runtime_core.tree_revertible_is_valid(core, address, id)
```

Call `revert_tree` and assert one `UndoCommit` event, one outbound operation,
and restored visible data.

Expected red: runtime-core functions and commit events are missing.

- [ ] **Step 2: Emit commit-applied events for every tree append.**

Ordinary edits and outer transaction commits emit:

```gleam
channel.TreeCommitApplied(revision, tree_types.DefaultCommit, True, True)
```

Revert commits use their derived kind. Schema commits set `revertible: False`.
Remote commits emit `DefaultCommit`, `local: False`, and `revertible: False`.
Keep current `TreeChanged` and `SchemaChanged` events unchanged.

- [ ] **Step 3: Route acquisition, status, disposal, and reversion.**

Resolve the tree channel, delegate to the kernel, replace its state, and map
`TreeError` through the repository-standard `CoreError` path. Reject
`revert_tree` when `tree_transaction_depth(core) > 0`.

Mint the inverse revision with the same compressor and identity-order path used
by ordinary tree edits. Encode and submit the returned commit through
`tree_runtime.encode_commit`.

- [ ] **Step 4: Write failing settlement tests.**

Sequence a local commit in three cases:

```gleam
tree_types.FullyApplied
tree_types.FullyDropped
tree_types.NewContentOnly
```

Assert local acknowledgement emits exactly one:

```gleam
channel.TreeCommitSettled(revision, outcome)
```

and removes its pending settlement state.

- [ ] **Step 5: Derive settlement from sequenced constraint status.**

Add a pure helper:

```gleam
pub fn commit_outcome(
  change: shared_change.Changeset,
) -> tree_types.TreeCommitOutcome
```

Map satisfied to `FullyApplied`, implicit violation to `FullyDropped`, and
explicit violation to `NewContentOnly`. Use the sequenced form of the commit,
not optimistic visible equality.

- [ ] **Step 6: Preserve handles across reconnect and resubmit.**

Reconnect must keep runtime-local history retention and handle IDs. When a
pending revert commit resubmits, it keeps its revision, kind, and one settlement
event. Accepted-before-drop deduplicates by revision.

Add cases to `shared_tree_history_resubmit_test.gleam` for a live original
handle and a pending undo commit.

- [ ] **Step 7: Run runtime-core tests on both targets.**

```bash
gleam test --target erlang -- shared_tree_runtime shared_tree_history_resubmit
gleam test --target javascript -- shared_tree_runtime shared_tree_history_resubmit
```

- [ ] **Step 8: Commit runtime-core integration.**

```bash
git add src/watershed/runtime_core.gleam src/watershed/tree/runtime.gleam src/watershed/channel.gleam test/watershed/shared_tree_runtime_test.gleam test/watershed/shared_tree_history_resubmit_test.gleam
git commit -m "feat(tree): route revertible commits"
```

### Task 5: Expose JavaScript revertible handles and commit subscriptions

**Files:**
- Modify: `src/watershed/runtime.gleam`
- Modify: `src/watershed.gleam`
- Modify: `test/watershed/shared_tree_runtime_js_test.gleam`
- Modify: `test/watershed/shared_tree_array_facade_test.gleam`
- Modify: `test/watershed/shared_tree_map_facade_test.gleam`
- Modify: `test/watershed/shared_tree_creation_api_test.gleam`

**Interfaces:**
- Consumes: Task 4 internal commit events and runtime-core functions.
- Produces: JavaScript `TreeCommitEvent`, one-shot factory, settlement
  registration, opaque handles, status, revert, disposal, and runtime cleanup.

- [ ] **Step 1: Write failing public facade tests.**

Subscribe before a local edit:

```gleam
let token =
  watershed.subscribe_tree_commits(tree, fn(event) {
    transport_js.set_cell(events, [event, ..transport_js.get_cell(events)])
  })
```

Assert one local `DefaultCommit` event with `Some(get_revertible)` and
`Some(on_settled)`. Assert a remote event has neither function.

Run:

```bash
gleam test --target javascript -- shared_tree_runtime_js shared_tree_array_facade shared_tree_map_facade
```

Expected red: the public subscription and types do not exist.

- [ ] **Step 2: Add JavaScript runtime types and facade aliases.**

Use:

```gleam
// src/watershed/runtime.gleam
pub opaque type TreeRevertible {
  TreeRevertible(
    runtime: Runtime,
    address: String,
    id: tree_types.RevertibleId,
  )
}

pub type TreeCommitEvent {
  TreeCommitEvent(
    kind: tree_types.TreeCommitKind,
    local: Bool,
    get_revertible: Option(fn() -> Result(TreeRevertible, String)),
    on_settled: Option(
      fn(fn(tree_types.TreeCommitOutcome) -> Nil) -> Result(Nil, String),
    ),
  )
}
```

In `watershed.gleam`, expose aliases for `runtime.TreeRevertible` and
`runtime.TreeCommitEvent`, then add the exact public functions from section 3.

- [ ] **Step 3: Implement one-shot acquisition during event delivery.**

When `runtime` dispatches an eligible local `TreeCommitApplied`, create a cell:

```gleam
let active = transport_js.new_cell(True)
let acquired = transport_js.new_cell(False)
```

The factory rejects inactive or acquired state. On success it calls
`runtime_core.retain_tree_revertible`, stores the new core, marks acquired, and
returns `TreeRevertible`. After all commit subscribers return, mark the factory
inactive.

Do not create one retained record per subscriber. The first successful factory
call wins.

- [ ] **Step 4: Implement settlement registration and delivery.**

During the local event, `on_settled` appends callbacks under the commit
revision. Reject late registration. On `TreeCommitSettled`, call each callback
once, report callback exceptions through the existing JavaScript callback error
path, and remove the revision entry.

Do not permit tree edits from inside a settlement callback to interrupt event
delivery. Use the same callback boundary as existing subscribers.

- [ ] **Step 5: Implement status, revert, and disposal.**

`tree_revertible_status` reads current runtime-core state. `tree_revert` calls
`runtime_core.revert_tree`, stores the returned core, fans out returned events,
submits the outbound operation, and disposes after successful authoring when
requested. `tree_dispose_revertible` calls the core disposal function and
returns an error on a second call.

- [ ] **Step 6: Add transaction, creation, and cleanup tests.**

Assert:

- reversion during `tree_transaction` returns an error and changes nothing;
- one outer transaction supplies one revertible;
- close disposes handles and settlement registrations;
- a native-created fixed-layout tree supports the public API;
- `unsubscribe` stops commit events.

- [ ] **Step 7: Run JavaScript facade tests.**

```bash
gleam test --target javascript -- shared_tree_runtime_js shared_tree_array_facade shared_tree_map_facade shared_tree_creation_api shared_tree_transaction
```

- [ ] **Step 8: Commit JavaScript facade support.**

```bash
git add src/watershed/runtime.gleam src/watershed.gleam test/watershed/shared_tree_runtime_js_test.gleam test/watershed/shared_tree_array_facade_test.gleam test/watershed/shared_tree_map_facade_test.gleam test/watershed/shared_tree_creation_api_test.gleam
git commit -m "feat(tree): expose JavaScript undo and redo"
```

### Task 6: Expose BEAM revertible handles and commit subscriptions

**Files:**
- Modify: `src/watershed/runtime_beam.gleam`
- Modify: `src/watershed_beam.gleam`
- Modify: `test/watershed/shared_tree_runtime_beam_test.gleam`
- Modify: `test/watershed/shared_tree_array_facade_test.gleam`
- Modify: `test/watershed/shared_tree_map_facade_test.gleam`
- Modify: `test/watershed/shared_tree_creation_api_test.gleam`

**Interfaces:**
- Consumes: Task 4 internal commit events and runtime-core functions.
- Produces: BEAM `TreeCommitEvent`, one-shot factory, settlement registration,
  opaque handles, status, revert, disposal, actor cleanup, and facade parity.

- [ ] **Step 1: Write failing actor and facade tests.**

Subscribe through the BEAM facade, make one local edit, and assert one event
with an available factory and settlement registration function. Add a remote
event case with neither function.

Run:

```bash
gleam test --target erlang -- shared_tree_runtime_beam shared_tree_array_facade shared_tree_map_facade
```

Expected red: BEAM commit subscription and handle messages do not exist.

- [ ] **Step 2: Add actor messages.**

Add messages equivalent to:

```gleam
SubscribeTreeCommits(
  address: String,
  handler: fn(TreeCommitEvent) -> Nil,
  reply: Subject(SubscriptionToken),
)
UnsubscribeTreeCommits(token: SubscriptionToken)
RetainTreeRevertible(
  address: String,
  revision: fluid_ids.StableId,
  kind: tree_types.TreeCommitKind,
  event_id: Int,
  reply: Subject(Result(tree_types.RevertibleId, String)),
)
RegisterTreeSettlement(
  revision: fluid_ids.StableId,
  event_id: Int,
  handler: fn(tree_types.TreeCommitOutcome) -> Nil,
  reply: Subject(Result(Nil, String)),
)
RevertTree(
  address: String,
  id: tree_types.RevertibleId,
  dispose: Bool,
  reply: Subject(Result(Nil, String)),
)
DisposeTreeRevertible(
  address: String,
  id: tree_types.RevertibleId,
  reply: Subject(Result(Nil, String)),
)
```

Track commit subscribers, the active event ID, one acquisition flag, the
monitored delivery process, and unrelated messages deferred during delivery.

- [ ] **Step 3: Add BEAM runtime types and facade aliases.**

Use:

```gleam
// src/watershed/runtime_beam.gleam
pub opaque type TreeRevertible {
  TreeRevertible(
    runtime: Subject(Msg),
    address: String,
    id: tree_types.RevertibleId,
  )
}

pub opaque type SubscriptionToken {
  SubscriptionToken(runtime: Subject(Msg), id: Int)
}

pub type TreeCommitEvent {
  TreeCommitEvent(
    kind: tree_types.TreeCommitKind,
    local: Bool,
    get_revertible: Option(fn() -> Result(TreeRevertible, String)),
    on_settled: Option(
      fn(fn(tree_types.TreeCommitOutcome) -> Nil) -> Result(Nil, String),
    ),
  )
}
```

In `watershed_beam.gleam`, expose aliases for the runtime types and add
`subscribe_tree_commits`, `unsubscribe`, status, revert, and disposal
functions with the same public behavior as the JavaScript facade.

- [ ] **Step 4: Implement callback delivery, one-shot acquisition, and settlement registration.**

For each commit event, start one monitored process that calls registered
handlers in subscription order and reports `CommitDeliveryFinished(event_id)`.
The factory and settlement closures send actor messages and wait for replies.
While delivery runs, the actor services only requests for that event and the
delivery completion or down messages; queue unrelated messages in arrival
order. Reject a stale event ID, a second acquisition, and registration after
delivery. Store settlement callbacks by revision. Invoke and remove them when
`TreeCommitSettled` arrives.

After delivery completes or the process exits, invalidate the event and replay
deferred messages in their original order.

- [ ] **Step 5: Implement revert, disposal, and cleanup.**

Route through Task 4 runtime-core functions. Submit one outbound operation
after a successful revert. Dispose after authoring when requested. Runtime
shutdown disposes all handles and drops pending settlement callbacks.

- [ ] **Step 6: Add transaction, reconnect, and caller-exit tests.**

Assert:

- active transactions reject reversion;
- one transaction commit supplies one handle;
- reconnect preserves a live handle;
- caller exit during event delivery cannot leave the factory active;
- actor shutdown makes handles disposed;
- double disposal returns an error.

- [ ] **Step 7: Run BEAM facade tests.**

```bash
gleam test --target erlang -- shared_tree_runtime_beam shared_tree_array_facade shared_tree_map_facade shared_tree_creation_api shared_tree_transaction
```

- [ ] **Step 8: Commit BEAM facade support.**

```bash
git add src/watershed/runtime_beam.gleam src/watershed_beam.gleam test/watershed/shared_tree_runtime_beam_test.gleam test/watershed/shared_tree_array_facade_test.gleam test/watershed/shared_tree_map_facade_test.gleam test/watershed/shared_tree_creation_api_test.gleam
git commit -m "feat(tree): expose BEAM undo and redo"
```

### Task 7: Prove native field, recovery, summary, and reload behavior

**Files:**
- Modify: `test/watershed/shared_tree_undo_test.gleam`
- Modify: `test/watershed/shared_tree_history_test.gleam`
- Modify: `test/watershed/shared_tree_history_resubmit_test.gleam`
- Modify: `test/watershed/shared_tree_document_summary_test.gleam`
- Modify: `test/watershed/shared_tree_summary_test.gleam`
- Modify: `test/watershed/shared_tree_array_kernel_test.gleam`
- Modify: `test/watershed/shared_tree_map_kernel_test.gleam`
- Modify: `test/watershed/shared_tree_transaction_test.gleam`
- Modify: `test/watershed/shared_tree_identifier_test.gleam`

**Interfaces:**
- Consumes: Tasks 1-6 complete native API and corpus.
- Produces: full native acceptance evidence across field kinds, reconnect,
  trimming, summary continuation, and runtime-local handle lifetime.

- [ ] **Step 1: Add the complete field matrix.**

For each target, cover:

| Original commit | Later change | Expected revert |
| --- | --- | --- |
| Object set | Different field set | Original field restored; later field preserved |
| Object replacement | Child edit | Pinned replacement conflict result |
| Map set | Different key set | Original key restored; later key preserved |
| Map delete | Same key set | Pinned overwrite result |
| Array insert | Later insert | Original cells removed; later cells preserved |
| Array remove | Later move | Restored identity and pinned position |
| Same-array move | Later insert | Pinned order |
| Cross-array move | Later remove | Pinned conflict result |
| Transaction | Remote unrelated edit | Whole transaction reverted as one commit |
| Identifier field | Remote unrelated edit | Identifier value and allocation remain valid |

Each case must assert snapshot, commit kind, event count, and settlement outcome.

- [ ] **Step 2: Add reconnect tests.**

Create and retain a handle, disconnect, author or receive later changes,
reconnect, and revert. Add a pending undo accepted before drop and assert one
effect and one settlement callback after deduplication.

- [ ] **Step 3: Add history-trimming tests.**

Advance MSN beyond a retained target and prove reversion still works. Dispose
the handle, advance MSN again, and prove the old commit and repair data can
trim. Keep another handle alive to prove disposal releases only its own pin.

- [ ] **Step 4: Add summary and reload tests.**

Publish summaries after undo and redo. Load them on both targets, verify final
state, and continue editing. Assert the new runtime has no handle or factory for
the historical commit.

Take a summary while an undo commit is pending. Assert the summary contains
sequenced state only, then apply the tail and continue editing.

- [ ] **Step 5: Run native acceptance gates.**

```bash
gleam test --target erlang -- shared_tree_undo shared_tree_history shared_tree_history_resubmit shared_tree_document_summary shared_tree_summary shared_tree_array_kernel shared_tree_map_kernel shared_tree_transaction shared_tree_identifier
gleam test --target javascript -- shared_tree_undo shared_tree_history shared_tree_history_resubmit shared_tree_document_summary shared_tree_summary shared_tree_array_kernel shared_tree_map_kernel shared_tree_transaction shared_tree_identifier
just shared-tree-codec-interop
just shared-tree-test
```

- [ ] **Step 6: Commit native acceptance proof.**

```bash
git add test/watershed
git commit -m "test(tree): prove native undo and redo"
```

### Task 8: Prove mixed-client undo and redo through Floodgate

**Files:**
- Modify: `tools/shared-tree-oracle/client-driver.mjs`
- Modify: `tools/shared-tree-oracle/client-driver.test.mjs`
- Modify: `test/watershed/tree/client_js.gleam`
- Modify: `test/watershed/tree/client_beam.gleam`
- Modify: `tools/shared-tree-oracle/interop-scenarios.mjs`
- Modify: `tools/shared-tree-oracle/schema.mjs`
- Modify: `tools/shared-tree-oracle/client-interop.mjs`
- Modify: `tools/shared-tree-oracle/client-interop.test.mjs`
- Modify: `tools/shared-tree-oracle/summary-interop.mjs`
- Modify: `tools/shared-tree-oracle/summary-interop.test.mjs`
- Modify: `tools/shared-tree-oracle/interop.mjs`
- Modify: `tools/shared-tree-oracle/interop.test.mjs`
- Modify: `tools/shared-tree-oracle/service.mjs`
- Modify: `tools/shared-tree-oracle/service.test.mjs`

**Interfaces:**
- Consumes: native public APIs and Task 1 upstream scenario definitions.
- Produces: required undo/redo sections in local and hosted interop reports.

- [ ] **Step 1: Add failing command-protocol tests.**

Add explicit client actions:

```json
{"op":"retainLastLocalCommit","name":"edit"}
{"op":"revert","name":"edit","dispose":true}
{"op":"retainLastLocalCommit","name":"undo"}
{"op":"revert","name":"undo","dispose":true}
```

Clients return snapshots, local commit kinds, factory availability, handle
status, settlement outcomes, outbound counts, and final tree. Coordinators must
not author changes or construct handles for clients.

- [ ] **Step 2: Require undo/redo report sections.**

Require:

```javascript
const requiredUndoRedoSections = [
  "undoRedoKinds",
  "undoRedoConcurrent",
  "undoRedoReconnect",
  "undoRedoReloadMatrix",
];
```

Test rejection after removing a section, implementation, race ordering,
field-kind row, reload cell, or settlement observation.

- [ ] **Step 3: Run deterministic mixed-client scenarios.**

Use JS/upstream, BEAM/upstream, and JS/BEAM pairs. In each pair:

1. Client A authors and retains a local commit.
2. Client B authors an unrelated or overlapping commit.
3. Client A undoes.
4. Client A retains the undo commit.
5. Client A redoes.

Cover object, map, array, move, and transaction changes in both sequence
orders. Assert B never receives a factory for A's commits.

- [ ] **Step 4: Run reconnect and reload matrices.**

Reconnect each native implementation with a live handle before undo. For each
writer in `upstream`, `javascript`, and `erlang`, publish a summary after undo
and after redo. Each reader loads it, verifies state, confirms no historical
handle exists, authors a new local commit, acquires a new handle, and undoes it.

- [ ] **Step 5: Extend seeded schedules.**

Add retain, dispose, undo, redo, overlapping edits, disconnects,
acknowledgements, transactions, and summary reloads. Keep the seed, schedule,
handle names, commit kinds, settlement outcomes, and event trace in failure
artifacts. Run 300 schedules with seed 42 in the required gate.

- [ ] **Step 6: Run local real-service gates.**

```bash
node --test tools/shared-tree-oracle/client-driver.test.mjs tools/shared-tree-oracle/client-interop.test.mjs tools/shared-tree-oracle/summary-interop.test.mjs tools/shared-tree-oracle/interop.test.mjs tools/shared-tree-oracle/service.test.mjs
just shared-tree-interop
just shared-tree-create-interop
```

Expected: pinned service identity; all three implementations; required field
rows and sequence orders; reconnect evidence; all reload cells; no skipped
target, service, corpus, settlement, or handle-lifetime row.

- [ ] **Step 7: Commit interoperability proof.**

```bash
git add tools/shared-tree-oracle test/watershed/tree test/fixtures/shared_tree
git commit -m "test(tree): prove undo and redo interoperability"
```

### Task 9: Close permanent gates and document the M5 profile

**Files:**
- Modify: `tools/shared-tree-oracle/generate.mjs`
- Modify: `tools/shared-tree-oracle/interop.mjs`
- Modify: `tools/shared-tree-oracle/service.mjs`
- Modify: their tests and `tools/shared-tree-oracle/gates.test.mjs`
- Generate: `test/fixtures/shared_tree/profile.json`, `manifest.json`, capture metadata
- Modify: `tools/shared-tree-oracle/README.md`
- Modify: `README.md`
- Modify: `.github/workflows/shared-tree.yml`
- Modify: `.github/workflows/shared-tree-interop.yml`
- Modify: `justfile` only if existing commands do not select the new required cases
- Modify: `docs/superpowers/plans/2026-09-21-shared-tree.md`
- Modify: `docs/superpowers/plans/2026-09-29-shared-tree-transactions.md`

**Interfaces:**
- Consumes: Tasks 1-8 passing evidence.
- Produces: an accurate full M5 support claim and permanent enforcement.

- [ ] **Step 1: Add failing profile and gate assertions.**

Require support labels for:

```text
application-owned revertibles
default/undo/redo commit kinds
runtime-local handle lifetime
reconnect with live handles
object/map/array/move/transaction undo and redo
sequenced commit outcomes
```

Keep persisted stacks, schema undo, remote-commit undo, undo during
transactions, cross-tree atomic undo, branches, `noChange`, custom metadata,
clone, and `revertTo` as explicit exclusions.

- [ ] **Step 2: Regenerate profile metadata.**

```bash
npm --prefix tools/shared-tree-oracle run generate
npm --prefix tools/shared-tree-oracle run check
```

Preserve every version, codec, layout, and M1-M4 feature claim.

- [ ] **Step 3: Document the public API and stack pattern.**

Show one commit subscription that:

1. Acquires a revertible from a local default commit.
2. Pushes undo commits to a redo stack.
3. Pushes default and redo commits to an undo stack.
4. Disposes the redo stack after a new default commit.
5. Registers a settlement callback.

Explain runtime-local lifetime, reconnect, reload, disposal, repeated
`revert(False)`, remote events without factories, and transaction exclusion.

- [ ] **Step 4: Update the parent roadmap and transaction handoff.**

Mark M5 complete for public transaction boundaries, constraints, revertible
lifetime, undo, redo, and remote edits during undo. Link the design and this
plan. Keep branching and M6-M8 deferred.

Update the transaction plan's handoff so it no longer says undo/redo remains
unimplemented.

- [ ] **Step 5: Run permanent gate tests.**

```bash
npm --prefix tools/shared-tree-oracle test
just shared-tree-test
just shared-tree-codec-interop
just shared-tree-interop
just shared-tree-create-interop
```

- [ ] **Step 6: Commit profile and documentation closure.**

```bash
git add tools/shared-tree-oracle test/fixtures/shared_tree README.md .github/workflows justfile docs/superpowers/plans/2026-09-21-shared-tree.md docs/superpowers/plans/2026-09-29-shared-tree-transactions.md
git commit -m "docs(tree): close undo and redo profile"
```

### Task 10: Run full regression closure

**Files:**
- Modify only files required to fix regressions caused by Tasks 1-9.
- Do not change unrelated failing tests or baseline behavior.

**Interfaces:**
- Consumes: all undo/redo implementation and permanent gates.
- Produces: final M5 acceptance evidence.

- [ ] **Step 1: Run formatting and focused gates.**

```bash
gleam format --check src test
npm --prefix tools/shared-tree-oracle test
just shared-tree-test
just shared-tree-codec-interop
```

- [ ] **Step 2: Run service, creation, and complete repository gates.**

```bash
just shared-tree-interop
just shared-tree-create-interop
just test
just build
just lint
```

Investigate each failure against the execution base. A known baseline report is
not evidence until the unchanged base reproduces the same failure.

- [ ] **Step 3: Verify the acceptance matrix.**

Check every item in section 5 against a named test, corpus observation, or
interop report cell. Do not close an item from final-value equality alone.

- [ ] **Step 4: Commit only regression fixes, if any.**

Use a focused Conventional Commit message that names the corrected undo or redo
behavior. Do not create an empty closure commit.

## 5. Acceptance checklist

- [ ] Eligible local data commits provide one one-shot revertible factory.
- [ ] Schema and remote commits provide no factory.
- [ ] Duplicate and late factory calls return explicit errors.
- [ ] A handle reports valid and disposed status correctly.
- [ ] Revert disposes by default; `dispose: False` keeps the handle valid.
- [ ] A valid handle can author repeated revert commits.
- [ ] A second disposal and any operation on a disposed handle return errors.
- [ ] Default and redo commits revert to undo commits.
- [ ] Undo commits revert to redo commits.
- [ ] Object, map, array, move, Identifier, and transaction commits revert.
- [ ] One transaction commit reverts as one unit.
- [ ] Later unrelated local and remote edits remain visible.
- [ ] Overlapping edit behavior matches the pinned source corpus.
- [ ] Revert-time explicit violations report `NewContentOnly`.
- [ ] Implicit conflicts report `FullyDropped`.
- [ ] Satisfied commits report `FullyApplied`.
- [ ] Settlement callbacks fire once after sequencing.
- [ ] Reversion during an active transaction fails without partial state.
- [ ] Live handles survive reconnect in the same runtime.
- [ ] Accepted-before-drop revert commits deduplicate by revision.
- [ ] Summary reload preserves committed undo/redo state but creates no old handles.
- [ ] Disposal releases retained history and repair data safely.
- [ ] JavaScript and BEAM expose matching public behavior.
- [ ] Upstream, native JavaScript, and native BEAM clients preserve convergence through pinned Floodgate.
- [ ] All required summary writer/reader cells continue editing.
- [ ] Required gates fail on missing artifacts, targets, scenarios, settlements, or service.
- [ ] Existing M1-M4, Identifier, transaction, creation, and browser behavior remains intact.
- [ ] Documentation marks M5 complete without claiming M6-M8 features.

## 6. Review matrix and stop conditions

| Design requirement | Owning tasks |
| --- | --- |
| Pinned factory, kind, status, and settlement contract | 1 |
| Runtime-local retention and disposal | 2, 4, 5, 6, 7 |
| Inversion and rebase over later changes | 1, 3, 7, 8 |
| Object, map, array, move, Identifier, and transaction coverage | 1, 3, 7, 8 |
| One-shot factory and application-owned stacks | 4, 5, 6, 9 |
| Sequenced outcomes | 1, 4, 5, 6, 8 |
| Reconnect and reload lifetime | 1, 4, 7, 8 |
| JavaScript and BEAM parity | 5, 6, 7 |
| Real-service and cross-writer proof | 8 |
| Permanent profile and CI gates | 9, 10 |

Stop and revise the design before continuing if the pinned source shows any of
these results:

- stable undo requires a wire-format change;
- remote commits receive local revertible factories;
- handle state must survive summary reload;
- reversion during an active transaction is supported;
- `noChange`, clone, custom metadata, or shared branches are required for the
  approved stable profile;
- a field kind needs an inversion algorithm that differs from the existing
  SharedTree change family.
