# SharedTree Transaction Foundations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add synchronous single-tree transactions with nested commit/abort and
sequenced node-existence constraints to the native SharedTree facades.

**Architecture:** Author callback edits against an isolated transaction-local
tree and compressor state, emit one public change event after outer success,
and append one composed commit only when the outer scope succeeds. Extend the existing
modular change algebra and V5 codec with node-existence constraints so every
client can suppress a transaction whose constrained node was removed before
sequencing.

**Tech Stack:** Dual-target Gleam; startest; Node test runner;
`@fluidframework/tree` 3.1.0 published-package and source oracles; pinned
Floodgate; existing `just` and GitHub Actions gates.

**Spec:** [SharedTree transaction foundations](../specs/2026-09-29-shared-tree-transactions-design.md).
Also read the [parent design](../specs/2026-09-21-shared-tree-design.md),
[arrays design](../specs/2026-09-26-shared-tree-arrays-design.md), and
[schema evolution design](../specs/2026-09-26-shared-tree-schema-evolution-design.md).

## Reconciliation (2026-10-04)

**Current status:** Tasks 1-9 are implemented. Task 10 (supported-profile and
permanent-gate closure) and Task 11 (current full-regression closure) remain
open. The task bodies below are retained as the historical test-first execution
record; an unchecked historical substep is not evidence that its named source
surface is absent.

Current code exposes synchronous single-tree transactions on JavaScript at
`src/watershed.gleam:627` and BEAM at `src/watershed_beam.gleam:739`.
`src/watershed/tree/transaction.gleam:35-508` contains the pure nested state,
and `test/watershed/shared_tree_transaction_test.gleam:476-1661` covers outer
commit, abort, savepoints, constraints, identity, and wire execution. The
oracle requires transaction callback, constraint, reconnect, and reload
sections in `tools/shared-tree-oracle/interop.mjs:86-90`.

The release claim is not closed. `test/fixtures/shared_tree/profile.json:250`
and `tools/shared-tree-oracle/service.mjs:101` still list
`public-transactions` as excluded, and the public README still describes
transactions as deferred. The thin Lustre adapter
`watershed_lustre/src/watershed_lustre/tree.gleam` has no transaction effect,
and no user-facing example demonstrates the callback API. Those consumer
surfaces were not part of Tasks 1-9, but they must not be implied by this plan.

Undo and redo are now implemented separately; references below that call them
unimplemented describe the 2026-09-29 planning baseline. See
[the undo/redo plan](2026-10-02-shared-tree-undo-redo.md) for its still-open
profile and regression closure.

No test, service, build, or hosted workflow was run for this docs-only
reconciliation. Existing test and gate files prove coverage is present, not
that the gates pass at the current revision.

## Global Constraints

- Production SharedTree semantics must run in pure Gleam on JavaScript and BEAM.
- Upstream TypeScript packages remain development and test dependencies.
- Use `@fluidframework/tree` version `3.1.0`.
- Use Fluid Framework commit `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960` (`client_v3.1.0`).
- Use Floodgate commit `0eb493fc46d1bb9baf1151a6ccdde93544e057e7`.
- Keep `minVersionForCollab` at `2.117.0`.
- Keep Message V7, SharedTreeChange V5, ModularChange V5, and Schema V2.
- Preserve the existing fixed container layout.
- Preserve M1-M4 behavior and interoperability evidence.
- Reject unsupported operations instead of approximating their meaning.
- Apply ASD-STE100 to Gleam comments and error strings, not to Markdown prose.
- Do not edit generated files, `.code-map/`, or apm-managed files.

---

## 1. Starting point and execution rules

Planning baseline: `2a33f6a` (`docs(tree): define transaction foundations`).
The worktree was clean after that commit. Record the execution worktree and
starting revision before Task 1. Do not edit the pinned Fluid checkout except
through the existing source-injection and capture commands.

Use an isolated worktree for execution. Restore dependencies only after a
relevant command reports that they are missing. Use existing lockfiles.

Each task ends with a testable deliverable and a commit. Use test-first steps:
add one named failing case, run it, implement the smallest complete behavior,
and run it again before adding the next row in the matrix. Do not stage
unrelated files.

At the planning baseline, this plan covered only the approved
transaction-foundation slice. It still excludes `noChange`, revert
constraints, schema upgrades in transactions, asynchronous transactions,
custom metadata, post-processors, and cross-tree atomicity. Undo and redo were
deferred from this plan but have since been implemented under the separate
undo/redo plan.

### Identifier prerequisite for Task 8

Tasks 2–7 remain implemented through `afc32c65`. The Identifier prerequisite
is complete through `bdc6f2a2`, `81917395`, `a76991a1`, `1f4edf9b`,
`98e95385`, `d81740ea`, `fb2bb53b`, and `f5d57d7e`.

The [Identifier support plan](2026-10-01-shared-tree-identifiers.md) now proves
native schema and FieldBatch support, compressed message values, originatorless
summary values, all mixed-client authorship directions, nine summary
writer/reader reload cells with post-load authoring, and native-created first
summaries. The local 300-schedule service run
`aa20c5fe-b0ca-47d0-b3db-b384440a57e8` and creation run
`b350cf7f-e90e-405c-8453-db9888392d19` passed.

Tasks 8 and 9 were subsequently completed. The next unchecked work is Task 10,
then Task 11. Keep the oracle's Identifier fields and complete builds,
refreshers, and summaries. Do not substitute ordinary string fields or strip
content to make parity pass. Identifier values use ordinary string leaves;
they do not require a new `TreeValue` node kind.

The historical Identifier closure recorded `just lint` passing, an unrelated
browser timeout in `just test`, a pnpm tarball URL policy stop in `just build`,
and no hosted workflow. Those dated results are not current validation.

### Archived baseline constraints

Every row below names a planning-baseline gap that has since been implemented.
Keep the table as design history; use the reconciliation section and current
source for status.

| Source at planning time | Required change |
| --- | --- |
| `tree/change.gleam:40-65` | Store node-existence constraints and aggregate explicit violation state. |
| `tree/change.gleam:1745-2100` | Compose, invert, and rebase constraints with the existing object/map/sequence algebra. |
| `tree/change.gleam:1731-1743` | Suppress constrained field effects after explicit violation while preserving required builds. |
| `tree/codec.gleam:742-775` | Decode nonzero `violations` instead of rejecting it. Keep `noChangeConstraint` unsupported. |
| `tree/codec.gleam:1266-1281` | Decode `nodeExistsConstraint` and preserve its violated flag. |
| `tree/codec.gleam:1448-1785` | Encode violation counts and node constraints in ModularChange V5. |
| `tree/runtime.gleam:247-283` | Split edit authoring from normal history append so transaction-local edits can reuse validation and allocation. |
| `tree_kernel.gleam:518-575` | Append one composed outer transaction change and expose constraint-target helpers. |
| `runtime_core.gleam:3763-3935` | Route edits to active transaction state and submit only the outer commit. |
| `runtime.gleam:2255-2355` | Add begin/commit/abort wrappers and callback-safe transaction routing. |
| `runtime_beam.gleam:212-510,1800-2145` | Add internal transaction messages and defer remote delivery until the outer scope ends. |
| `watershed.gleam:486-735` and `watershed_beam.gleam:600-875` | Add the public generic callback API and stable constraint type. |

Line numbers identify the planning baseline. Locate the named declarations
again before editing.

### Dependency order

```text
1 pinned transaction oracle and source-contract review
                         |
2 modular constraint model and V5 codec
                         |
3 constraint compose/invert/rebase/application semantics
                         |
4 pure transaction-local state and edit authoring split
                         |
5 kernel and runtime-core transaction integration
                    /         \
6 JavaScript callback       7 BEAM callback and deferral
                    \         /
8 reconnect, summary, and native facade parity
                         |
9 mixed-client and real-service proof
                         |
10 permanent gates and supported-profile closure
                         |
11 full regression closure
```

Tasks 6 and 7 can proceed in parallel after Task 5 if they have separate file
ownership. Keep Tasks 2-5 under one integration owner because they share the
change, codec, kernel, and runtime-core contracts.

## 2. File map

| File or group | Responsibility |
| --- | --- |
| `src/watershed/tree/change.gleam` | Modular constraint types, authoring, compose, invert, rebase, explicit-violation outcome. |
| `src/watershed/tree/codec.gleam` | ModularChange V5 constraint and violation encoding/decoding. |
| `src/watershed/tree/transaction.gleam` (new) | Pure nested transaction state, savepoints, authored changes, compressor snapshots, and commit/abort results. |
| `src/watershed/tree/runtime.gleam` | Reusable edit authoring without history append; outer transaction commit authoring. |
| `src/watershed/tree_kernel.gleam` | Constraint target resolution and one composed local history append. |
| `src/watershed/runtime_core.gleam` | Active transaction storage, transaction-aware reads/edits, outer submission, and state evidence. |
| `src/watershed/runtime.gleam` | JavaScript begin/commit/abort operations, cell routing, event fan-out, and outbound submission. |
| `src/watershed/runtime_beam.gleam` | BEAM transaction messages, actor state, deferred remote messages, event fan-out, and outbound submission. |
| `src/watershed.gleam`, `src/watershed_beam.gleam` | Public constraint/error types and callback API. |
| `tools/shared-tree-oracle/upstream-transaction.spec.ts` (new) | Pinned source capture for transaction, constraint, event, wire, and history behavior. |
| Existing oracle source/generate/schema/client/interop/service files | Register, validate, run, and gate the transaction corpus and clients. |
| `test/watershed/tree/transaction_fixture.gleam` (new) | Input-only native corpus runners. |
| `test/watershed/shared_tree_transaction_test.gleam` (new) | Pure transaction state and nested scope tests. |
| Existing change, codec, history, kernel, runtime, facade, summary, and array tests | Add focused constraint and integration coverage at existing boundaries. |

Do not introduce a second history implementation, a transaction-specific edit
DSL, or a generic runtime plugin framework.

## 3. Shared interfaces

Add declarations only when their owning task starts.

### Constraint data, owned by Task 2

```gleam
pub type NodeExistsConstraint {
  NodeExistsConstraint(violated: Bool)
}

pub type NodeChange {
  NodeChange(
    fields: List(#(String, FieldChange)),
    node_exists_constraint: Option(NodeExistsConstraint),
    node_exists_constraint_on_revert: Option(NodeExistsConstraint),
  )
}

pub type ChangeData {
  ChangeData(
    max_local_id: Int,
    revisions: List(RevisionInfo),
    fields: List(#(String, FieldChange)),
    nodes: List(#(AtomId, NodeChange)),
    parents: List(#(AtomId, ParentField)),
    aliases: List(#(AtomId, AtomId)),
    builds: List(forest.Build),
    destroys: List(forest.Destroy),
    refreshers: List(forest.Build),
    cross_field_keys: List(CrossFieldKey),
    constraint_violation_count: Int,
  )
}
```

Keep `noChangeConstraint` absent from the native type. Decoding it remains an
`UnsupportedFeature`.

### Constraint authoring, owned by Task 3

```gleam
pub type ConstraintTarget {
  ConstraintTarget(reference: forest.NodeRef, path: FieldPath)
}

pub fn resolve_constraint(
  visible: forest.Forest,
  path: FieldPath,
) -> Result(ConstraintTarget, TreeError)

pub fn add_node_exists_constraints(
  value: Changeset,
  visible: forest.Forest,
  targets: List(ConstraintTarget),
) -> Result(Changeset, TreeError)
```

`resolve_constraint` requires an attached node. `add_node_exists_constraints`
must verify that each stored reference still resolves to the same base node,
then add a nonviolated constraint to the node change identified by the base
path. Duplicate targets collapse to one constraint.

### Preview application, owned by Task 4

```gleam
pub fn apply_local_preview(
  state: TreeState,
  revision: fluid_ids.StableId,
  order: change.IdentityOrder,
  outer: shared_change.Changeset,
) -> Result(#(TreeState, ChangeEvents), TreeError)
```

This function rebinds and applies one local outer change to visible state,
updates `next_local_id`, and does not append normal history or local authoring
context. Ordinary `apply_local_change` reuses it before appending history.

### Pure transaction state, owned by Task 4

```gleam
pub opaque type Transaction

pub type Finish {
  NoCommit(
    state: tree_kernel.TreeState,
    compressor: fluid_ids.Compressor,
  )
  Commit(
    state: tree_kernel.TreeState,
    compressor: fluid_ids.Compressor,
    commit: history.Commit,
  )
}

pub fn begin(
  state: tree_kernel.TreeState,
  compressor: fluid_ids.Compressor,
  constraints: List(change.ConstraintTarget),
) -> Transaction

pub fn begin_nested(value: Transaction) -> Transaction

pub fn begin_nested_with_constraints(
  value: Transaction,
  constraints: List(change.ConstraintTarget),
) -> Result(Transaction, TreeError)

pub fn depth(value: Transaction) -> Int

pub fn state(value: Transaction) -> tree_kernel.TreeState

pub fn compressor(value: Transaction) -> fluid_ids.Compressor

pub fn apply_edit(
  value: Transaction,
  edit: tree_types.Edit,
) -> Result(Transaction, TreeError)

pub fn commit_nested(value: Transaction) -> Result(Transaction, TreeError)

pub fn abort_nested(
  value: Transaction,
) -> Result(Transaction, TreeError)

pub fn finish(
  value: Transaction,
) -> Result(#(Finish, tree_kernel.ChangeEvents), TreeError)

pub fn abort(
  value: Transaction,
) -> Result(#(tree_kernel.TreeState, fluid_ids.Compressor), TreeError)
```

`finish` composes authored changes, adds constraints, and appends one local
commit. `NoCommit` returns the restored base tree with the preserved
nonserialized forest allocation watermark and the base compressor. `abort`
restores the base tree and summary compressor state while retaining pinned
ongoing local compressor advancement. Intermediate edits and abort emit no
public data event. `finish` returns the one outer event when committed visible
data changed.

### Runtime-core API, owned by Task 5

```gleam
pub fn begin_tree_transaction(
  core: Core,
  address: String,
  view: tree_schema.ViewSchema,
  constraints: List(tree_types.FieldPath),
) -> Result(Core, CoreError)

pub fn commit_tree_transaction(
  core: Core,
  address: String,
) -> Result(#(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)), CoreError)

pub fn abort_tree_transaction(
  core: Core,
  address: String,
) -> Result(#(Core, List(#(String, ChannelEvent))), CoreError)

pub fn tree_transaction_depth(core: Core) -> Int
```

Existing tree read functions select the isolated state when the address matches
the active transaction. Existing tree edit submission routes matching edits to
`transaction.apply_edit`, returns no local events, and returns no outbound
operation until outer commit. Another tree address and schema upgrades return a
typed error while a transaction is active.

Task 5 changes `adopt_reconnect` from an infallible transition to
`Result(Core, CoreError)`. A reconnect cannot silently carry an active
transaction into a new connection epoch. Existing JavaScript, BEAM, and test
callers must handle the result.

### Public API, owned by Tasks 6 and 7

```gleam
pub type TreeTransactionConstraint {
  NodeInDocument(path: tree_types.FieldPath)
}

pub type TreeTransactionError(callback_error) {
  Aborted(callback_error)
  TransactionFailed(String)
}

pub fn tree_transaction(
  tree: SharedTree,
  constraints: List(TreeTransactionConstraint),
  callback: fn(SharedTree) -> Result(value, callback_error),
) -> Result(value, TreeTransactionError(callback_error))
```

## 4. Implementation tasks

### Task 1: Capture the pinned transaction and constraint contract

**Reconciled status:** Implemented. The pinned source adapter is
`tools/shared-tree-oracle/upstream-transaction.spec.ts`; the four generated
cases are registered in `test/fixtures/shared_tree/manifest.json`, and the
source contract is documented in `tools/shared-tree-oracle/README.md:806-862`.
The unchecked steps below are the archived red/green script, not current gate
results.

**Files:**
- Create: `tools/shared-tree-oracle/upstream-transaction.spec.ts`
- Modify: `tools/shared-tree-oracle/source.mjs`
- Modify: `tools/shared-tree-oracle/source.test.mjs`
- Modify: `tools/shared-tree-oracle/generate.mjs`
- Modify: `tools/shared-tree-oracle/generate.test.mjs`
- Modify: `tools/shared-tree-oracle/README.md`
- Generate: transaction corpus files, `manifest.json`, and capture metadata

**Interfaces:**
- Consumes: pinned Fluid source, existing source injection, schema catalog,
  corpus manifest, and observation normalization.
- Produces: exact transaction, constraint, event, wire, and history
  observations used by Tasks 2-9.

- [ ] **Step 1: Add failing source-registration and corpus-completeness tests.**

Export:

```javascript
export const transactionInjectedTestPath =
  "packages/dds/tree/src/test/watershedTransaction.spec.ts";
```

Require these corpus case IDs:

```javascript
const requiredTransactionCases = [
  "transaction-callbacks",
  "transaction-constraints",
  "transaction-wire",
  "transaction-history",
];
```

For each case, test rejection after removing the case, clearing observations,
removing `input`, or changing the pinned source commit.

Run:

```bash
node --test tools/shared-tree-oracle/source.test.mjs tools/shared-tree-oracle/generate.test.mjs
```

Expected red: missing transaction injection and missing required-case checks.

- [ ] **Step 2: Capture callback, nesting, and event behavior.**

Use the ordinary simple-tree `runTransaction` API. Record:

- successful object, map, array, and move edits;
- callback reads after each edit;
- one local changed event after outer success;
- no changed event after outer rollback;
- inner success followed by outer success;
- inner rollback followed by continued outer edits;
- a no-op callback;
- one final branch commit and submitted operation for each outer success.

Assert the nested transaction depth and commit count in the injected source
test, not only in normalized output.

- [ ] **Step 3: Capture stable node-existence constraints.**

Create a constraint from a real `TreeNode`. Capture:

- local refusal when the node is already detached;
- success after the node moves within an array;
- success after a cross-array move;
- explicit violation when a concurrent removal sequences first;
- the resulting `constraintViolationCount`;
- retained created content and no visible constrained field effects.

Do not include alpha `noChange` or revert preconditions.

- [ ] **Step 4: Capture exact ModularChange V5 and SharedTreeChange V5 bytes.**

Record nonviolated and violated node constraints, nested node paths, duplicate
constraint inputs, builds, refreshers, and revision information. Capture
compose, invert, and rebase outcomes. The expected inverse must exchange
apply-time and revert-time node constraints even though public undo is absent.

- [ ] **Step 5: Capture reconnect, summary, and mixed-history behavior.**

Record one pending composed transaction, resubmission, acknowledgement, a
summary taken while it is pending, summary-plus-tail replay, and explicit
constraint violation during pending rebase. Include node identities and
retained detached content in every checkpoint.

- [ ] **Step 6: Regenerate and verify the source corpus.**

```bash
npm --prefix tools/shared-tree-oracle run source:verify
npm --prefix tools/shared-tree-oracle run source:capture
npm --prefix tools/shared-tree-oracle run generate
npm --prefix tools/shared-tree-oracle run check
node --test tools/shared-tree-oracle/source.test.mjs tools/shared-tree-oracle/generate.test.mjs
```

Expected green: all four transaction cases, exact pins, nonempty raw wire
evidence, and deterministic regeneration.

- [ ] **Step 7: Review and document the source contract.**

Document the exact source paths, event order, nested behavior, explicit
violation outcome, wire fields, and retained-build rule in the oracle README.
Resolve any mismatch with the approved spec before native implementation.

- [ ] **Step 8: Commit the oracle deliverable.**

```bash
git add tools/shared-tree-oracle test/fixtures/shared_tree
git commit -m "test(tree): capture transaction contract"
```

### Task 2: Add modular constraint types and V5 codec support

**Files:**
- Modify: `src/watershed/tree/change.gleam`
- Modify: `src/watershed/tree/codec.gleam`
- Create: `test/watershed/tree/transaction_fixture.gleam`
- Create: `test/watershed/shared_tree_transaction_test.gleam`
- Modify: `test/watershed/shared_tree_change_test.gleam`
- Modify: `test/watershed/shared_tree_codec_test.gleam`
- Modify: `test/watershed/shared_tree_codec_fixture_test.gleam`

**Interfaces:**
- Consumes: Task 1 transaction wire inputs.
- Produces: the section-3 constraint data model and lossless ModularChange V5
  encode/decode support.

- [x] **Step 1: Add input-only codec fixture tests.**

Add:

```gleam
pub fn run_wire(input: Json) -> Result(Json, String)
```

It decodes only fixture input, runs native decode/encode, and returns
normalized constraint fields. Add tests for nonviolated, violated, nested,
duplicate, and malformed constraints.

Run:

```bash
gleam test --target erlang -- shared_tree_transaction shared_tree_codec
gleam test --target javascript -- shared_tree_transaction shared_tree_codec
```

Expected red: nonzero `violations` and `nodeExistsConstraint` are unsupported.

- [x] **Step 2: Add constraint fields with explicit defaults.**

Extend `NodeChange` and `ChangeData` with the interfaces in section 3. Update
every constructor and pattern match. Use:

```gleam
NodeChange(
  fields: fields,
  node_exists_constraint: None,
  node_exists_constraint_on_revert: None,
)
```

and set `constraint_violation_count: 0` for existing changes.

- [x] **Step 3: Decode V5 constraint fields.**

Decode:

```json
{"nodeExistsConstraint":{"violated":false}}
```

Reject extra keys and non-Boolean `violated`. Decode top-level `violations` as
a nonnegative integer and preserve it. Continue to reject
`noChangeConstraint`.

- [x] **Step 4: Encode V5 constraint fields.**

Emit `nodeExistsConstraint` only when present. Emit `violations` only when the
count is greater than zero. Do not encode `node_exists_constraint_on_revert`;
the pinned V5 codec omits revert-only constraints.

- [x] **Step 5: Add malformed and round-trip tests.**

Cover negative/fractional violation counts, missing `violated`, extra keys,
constraint-only node changes, aliases, nested arrays, and violated changes with
builds. Assert exact JSON, not only semantic equality.

- [x] **Step 6: Run focused dual-target tests.**

```bash
gleam format --check src test
gleam test --target erlang -- shared_tree_transaction shared_tree_change shared_tree_codec shared_tree_codec_fixture
gleam test --target javascript -- shared_tree_transaction shared_tree_change shared_tree_codec shared_tree_codec_fixture
```

- [x] **Step 7: Commit the codec boundary.**

```bash
git add src/watershed/tree/change.gleam src/watershed/tree/codec.gleam test/watershed
git commit -m "feat(tree): decode transaction constraints"
```

**Completion evidence (2026-09-30):**

- Implementation commits:
  `765aa26f9f1cd1b803e6f510eacc362b591a9dd4`,
  `331cafb978343987c28f341f0ed234474a719e88`,
  `a66a104dd9ed7618bfdad3fd4470dad84bb4b12d`, and
  `a61cce4d2636bbf4ff138aac01da351fadae38ca`. Malformed-input,
  structural, and closure coverage is in
  `8b3adb917ecf7db13174a170133e6743dd50d8e5`.
- Native `NodeExistsConstraint` and aggregate violation state are complete.
  Pinned ModularChange V5 decode and encode support is complete.
- The input-only runner returns encoder-produced output after removing only
  unsupported FieldBatch `builds` and `refreshers`. Full compressed FieldBatch
  parity remains outside this task.
- These exact commands passed:

  ```bash
  gleam format --check src test
  gleam test --target erlang -- shared_tree_transaction shared_tree_change shared_tree_codec shared_tree_codec_fixture shared_tree_change_fixture
  gleam test --target javascript -- shared_tree_transaction shared_tree_change shared_tree_codec shared_tree_codec_fixture shared_tree_change_fixture
  just shared-tree-codec-interop
  just shared-tree-test
  ```

- The focused Erlang and JavaScript commands each passed 112 tests.
  Codec interoperability passed for 2 targets with 30 items per target.
  The SharedTree profile passed 756 tests and its owned smokes.
- At this historical checkpoint, Task 3 was next and transaction runtime and
  public APIs were still unimplemented. Later tasks below supersede that
  status.

### Task 3: Implement constraint authoring and algebra

**Files:**
- Modify: `src/watershed/tree/change.gleam`
- Modify: `src/watershed/tree/forest.gleam` only for a focused identity helper if existing `NodeRef` access is insufficient
- Modify: `test/watershed/shared_tree_transaction_test.gleam`
- Modify: `test/watershed/shared_tree_change_test.gleam`
- Modify: `test/watershed/shared_tree_array_change_test.gleam`
- Modify: `test/watershed/shared_tree_change_fixture_test.gleam`

**Interfaces:**
- Consumes: Task 2 constraint data.
- Produces: `resolve_constraint`, `add_node_exists_constraints`, and complete
  compose/invert/rebase/application semantics.

- [x] **Step 1: Add failing local target-resolution tests.**

Test an attached object, map, array element, moved node, duplicate path,
missing path, detached reference, and reference from another forest. The last
three return `InvalidEdit` without changing state.

- [x] **Step 2: Author constraint-only node paths.**

Use `forest.node_path` and the existing ancestor wrapping logic to construct a
node change at the constrained base node. Merge it into the composed
transaction change without replacing existing field changes. Verify that the
stored `NodeRef` still identifies the base node before adding the constraint.

- [x] **Step 3: Add failing compose and invert tests.**

Require:

- constraints survive composition with edits before and after them;
- duplicate constraints collapse;
- violation counts equal the number of violated constraints;
- inversion exchanges `node_exists_constraint` and
  `node_exists_constraint_on_revert`;
- existing data-only compose/invert output is unchanged.

- [x] **Step 4: Implement compose and invert propagation.**

Thread constraint fields through node merge, alias resolution, pruning, and
inverse construction. Recompute the aggregate count from node constraints
after each operation instead of incrementally trusting stale input.

- [x] **Step 5: Add failing rebase cases from the corpus.**

Cover unchanged node, same-node edit, move, remove, replace, remove-then-restore,
cross-array move, concurrent insert around the node, nested constrained node,
and already-violated input.

- [x] **Step 6: Implement rebase violation updates.**

Port the pinned modular constraint update rule into the existing rebase state.
A move preserves the constraint. A detach without reattachment marks it
violated. A restored same identity clears a violation only when the pinned
source does. Recompute `constraint_violation_count` after rebase.

- [x] **Step 7: Suppress visible field effects after explicit violation.**

When `constraint_violation_count > 0`, `into_delta` must preserve builds and
refreshers required by history but omit constrained field effects. Keep this
outcome distinct from an empty outer change and from schema conflict.

- [x] **Step 8: Run algebra and array identity tests on both targets.**

```bash
gleam test --target erlang -- shared_tree_transaction shared_tree_change shared_tree_array_change shared_tree_change_fixture
gleam test --target javascript -- shared_tree_transaction shared_tree_change shared_tree_array_change shared_tree_change_fixture
```

- [x] **Step 9: Commit constraint semantics.**

```bash
git add src/watershed/tree/change.gleam src/watershed/tree/forest.gleam test/watershed
git commit -m "feat(tree): enforce node constraints"
```

**Completion evidence (2026-09-30):**

- Constraint authoring and modular algebra are complete.
- The focused Erlang and JavaScript commands each passed 125 tests.
- Task review and subsequent scoped corrective reviews passed.
- At this historical checkpoint, Task 4 was next and unimplemented.
- Repository-wide `just build` and `just test` remain blocked only by the
  reported existing pnpm lockfile validation issue.

### Task 4: Add pure nested transaction state

**Files:**
- Create: `src/watershed/tree/transaction.gleam`
- Modify: `src/watershed/tree/runtime.gleam`
- Modify: `src/watershed/tree_kernel.gleam`
- Modify: `test/watershed/shared_tree_transaction_test.gleam`
- Modify: `test/watershed/shared_tree_kernel_test.gleam`
- Modify: `test/watershed/shared_tree_array_kernel_test.gleam`

**Interfaces:**
- Consumes: Task 3 constraint algebra, existing edit validation, identity
  allocation, and local history append.
- Produces: the pure transaction API in section 3 and reusable edit authoring.

- [x] **Step 1: Add failing single-scope commit and abort tests.**

Start from a tree and compressor, apply two edits, and assert callback-visible
state without public events. Before finish, assert normal pending history is
unchanged. Finish must append one pending commit and return one final event.
Abort must restore tree, history, identity, and summary compressor equality
without an event. After an authored edit, preserve the pinned advancement of
the ongoing local compressor state without emitting an allocation range.

- [x] **Step 2: Split edit authoring from history append.**

Add an internal authoring result:

```gleam
pub type AuthoredEdit {
  AuthoredEdit(
    state: tree_kernel.TreeState,
    change: shared_change.Changeset,
    events: tree_kernel.ChangeEvents,
    compressor: fluid_ids.Compressor,
  )
}

pub fn author_edit_change(
  state: tree_kernel.TreeState,
  edit: Edit,
  compressor: fluid_ids.Compressor,
) -> Result(Option(AuthoredEdit), TreeError)
```

`author_edit_change` allocates a revision and calls
`tree_kernel.apply_local_preview`. Ordinary `author_edit` then appends the
returned change through `tree_kernel.apply_local_change` from the pre-edit
state. Empty edits return `None` and preserve the compressor.

- [x] **Step 3: Implement outer transaction state.**

Store base/current tree and compressor, authored outer changes, constraint
targets, and a savepoint stack. `apply_edit` uses `author_edit_change`, updates
only current isolated state, records the change, and suppresses preview events.

- [x] **Step 4: Add and implement nested savepoints.**

Test two nested levels, inner success, inner abort, outer continuation, and
outer abort after inner success. Each savepoint stores current tree,
authored-change length, and event position. Aborting a savepoint preserves
ongoing local compressor advancement.

- [x] **Step 5: Compose and append the outer success.**

`finish` composes authored changes in order, adds constraints against the base
forest, and appends one commit. If there is no effective data change, return `NoCommit` with restored
tree state, the base compressor, and no pending history.

- [x] **Step 6: Reject unsupported transaction operations.**

Add tests for schema upgrades, a constraint that becomes detached before the
callback starts, and commit/abort at depth zero. Use typed errors and leave
state usable.

- [x] **Step 7: Run pure transaction and kernel tests.**

```bash
gleam test --target erlang -- shared_tree_transaction shared_tree_kernel shared_tree_array_kernel
gleam test --target javascript -- shared_tree_transaction shared_tree_kernel shared_tree_array_kernel
```

- [x] **Step 8: Commit the pure transaction engine.**

```bash
git add src/watershed/tree/transaction.gleam src/watershed/tree/runtime.gleam src/watershed/tree_kernel.gleam test/watershed
git commit -m "feat(tree): add nested transactions"
```

**Completion evidence (2026-09-30):**

- Added pure `watershed/tree/transaction` state with outer commit and abort,
  nested savepoints, constraint validation and authoring, no-commit handling,
  and one final event.
- Split edit authoring from history append through `AuthoredEdit`,
  `author_edit_change`, `author_local_change`, and `apply_local_preview`.
  Ordinary authoring still appends from the pre-edit state.
- Preview application carries the authored revision, advances local IDs, and
  leaves normal pending history unchanged. Final composition uses compressor
  identity keys. It does not sort revisions by UUID or allocation time.
- Inner abort restores its tree, authored-change count, and event position. It
  keeps ongoing local compressor advancement. Outer abort restores the base
  tree and history, keeps ongoing local compressor advancement, and leaves
  summary compressor serialization unchanged.
- `finish` and `abort` reject open nested scopes. Nested commit and abort reject
  depth zero. The returned immutable transaction remains usable after an
  error.
- Empty transactions return `NoCommit` with the base tree and compressor.
  Rolled-back no-op transactions also preserve the invisible forest allocation
  watermark so discarded references cannot alias later nodes. Same-value
  identity edits remain real commits. Net-zero array mutations retain the
  array event flag and emit one final local tree event.
- `begin` returns `Result(Transaction, TreeError)` instead of the infallible
  signature in section 3. This is the smallest typed boundary that validates
  resolved constraints before any edit can run.
- Schema upgrades are not representable by the closed `tree_types.Edit`
  surface. Task 4 does not add a schema edit variant. Defensive outer-change
  checks return `UnsupportedFeature("tree.transaction", "schema changes are not supported")`.
- RED evidence: the focused Erlang suite failed because the transaction module
  and preview APIs did not exist. The first GREEN pass then exposed the missing
  net-zero array mutation event, which failed with
  `ChangeEvents([], False)` instead of
  `ChangeEvents([TreeChanged(True)], True)`.
- These exact required commands each passed 61 tests:

  ```bash
  gleam test --target erlang -- shared_tree_transaction shared_tree_kernel shared_tree_array_kernel
  gleam test --target javascript -- shared_tree_transaction shared_tree_kernel shared_tree_array_kernel
  ```

- Expanded ordinary-authoring coverage passed 42 tests on each target:

  ```bash
  gleam test --target erlang -- shared_tree_map_kernel shared_tree_channel shared_tree_summary_codec
  gleam test --target javascript -- shared_tree_map_kernel shared_tree_channel shared_tree_summary_codec
  ```

- `gleam format --check src test` and `git diff --check` passed.
- Task 5 runtime integration and public callback APIs remain unimplemented.

**Review fix round 1 evidence (2026-09-30):**

- Added permanent regressions for preview `NodeRef` identity across outer
  finish, pending reconciliation, and local acknowledgement.
- Added nested and outer abort regressions that retain a discarded node
  reference, insert a replacement at the same path, and require a distinct
  reference plus rejection of the stale constraint target.
- RED on both targets:

  ```text
  gleam test --target erlang -- shared_tree_transaction
  17 passed, 3 failed

  gleam test --target javascript -- shared_tree_transaction
  17 passed, 3 failed
  ```

  Finish assigned B's retained reference to C, and both rollback forms reused
  node ID 4 for the replacement.
- Outer finish still applies the composed change to the base to derive the
  canonical commit, history, repair data, detached identities, and events.
  It then promotes preview node IDs into that canonical forest. Preview-only
  intermediate detached trees are dropped, canonical-only repair trees are
  allocated above the preview watermark, and exported `ForestData` must match
  the canonical application exactly.
- Nested and outer abort restore document and history state while preserving
  the maximum nonserialized forest node-allocation watermark. Discarded nodes
  are not retained, and their IDs cannot alias later nodes in the same view.
- The former full `TreeState` equality assertion on outer abort now compares
  visible data, history, snapshot state, and surviving base references. Full
  equality is no longer correct because the invisible allocator watermark
  must advance.
- Required focused commands passed 64 tests on each target:

  ```bash
  gleam test --target erlang -- shared_tree_transaction shared_tree_kernel shared_tree_array_kernel
  gleam test --target javascript -- shared_tree_transaction shared_tree_kernel shared_tree_array_kernel
  ```

- Focused forest, history, map, channel, and summary coverage passed 189 tests
  on each target:

  ```bash
  gleam test --target erlang -- shared_tree_forest shared_tree_array_forest shared_tree_map_forest shared_tree_history shared_tree_history_resubmit shared_tree_map_kernel shared_tree_channel shared_tree_summary_codec shared_tree_summary shared_tree_document_summary
  gleam test --target javascript -- shared_tree_forest shared_tree_array_forest shared_tree_map_forest shared_tree_history shared_tree_history_resubmit shared_tree_map_kernel shared_tree_channel shared_tree_summary_codec shared_tree_summary shared_tree_document_summary
  ```

- `gleam format --check src test` and `git diff --check` passed.
- No Task 5 runtime state, facade, callback, or public transaction API was
  added.

**Review fix round 2 evidence (2026-09-30):**

- Added a permanent regression for nested insertion, nested abort, no-op outer
  finish, and a later transaction from the returned state. It verifies that
  the discarded reference stays invalid, the discarded constraint is
  rejected, the replacement gets a different reference, the surviving base
  reference is unchanged, snapshot and history are unchanged, the compressor
  is the base compressor, and no event or pending commit exists.
- RED on both targets failed to compile because the required state could not be
  returned by the bare `NoCommit` constructor:

  ```text
  Expected no arguments, got 2
  ```

- `NoCommit` now carries the restored tree state and base compressor. Both
  no-op branches use one helper that restores base-visible state and history
  while preserving the maximum nonserialized forest allocation watermark.
  Ordinary empty transactions still return the exact base state and
  compressor.
- The required focused commands passed 65 tests on each target:

  ```bash
  gleam test --target erlang -- shared_tree_transaction shared_tree_kernel shared_tree_array_kernel
  gleam test --target javascript -- shared_tree_transaction shared_tree_kernel shared_tree_array_kernel
  ```

- This intentionally changes the internal Task 4 `Finish` interface from a
  bare `NoCommit` tag to
  `NoCommit(state: tree_kernel.TreeState, compressor: fluid_ids.Compressor)`.
  Task 5 must install both returned values while emitting no operation, event,
  or pending commit.
- `gleam format --check src test` and `git diff --check` passed.
- At this historical checkpoint, Task 5 remained unimplemented.

### Task 5: Integrate transactions with runtime core

**Files:**
- Modify: `src/watershed/runtime_core.gleam`
- Modify: `src/watershed/channel.gleam` if exhaustive evidence or event handling requires it
- Modify: `test/watershed/shared_tree_runtime_test.gleam`
- Modify: `test/watershed/shared_tree_array_kernel_test.gleam`
- Modify: `test/watershed/shared_tree_schema_evolution_test.gleam`

**Interfaces:**
- Consumes: Task 4 pure transaction API.
- Produces: the runtime-core API in section 3 and transaction-aware existing
  tree read/edit functions.

- [x] **Step 1: Add failing runtime-core lifecycle tests.**

Test begin, intermediate reads without events, nested begin/abort, one outer
commit event, outer abort without events, no-op, wrong address, wrong view,
schema upgrade rejection, and calls outside an active transaction.

- [x] **Step 2: Store one active single-tree transaction in `Core`.**

Add:

```gleam
active_tree_transaction:
  Option(#(String, tree_schema.ViewSchema, tree_transaction.Transaction))
```

Initialize it to `None` in every core constructor and restore path.

- [x] **Step 3: Route reads and edits through active state.**

When the address matches, existing reads use `tree_transaction.state`.
Matching edits call `tree_transaction.apply_edit`, replace the active
transaction, return no events, and return `[]` outbound. Another address
returns `TreeOperationFailed` with a literal cross-tree error.

- [x] **Step 4: Implement begin, nested begin, commit, and abort.**

Resolve `NodeInDocument` paths before invoking `transaction.begin`. Nested
begin requires the same address and view. Inner commit/abort update only active
state. Outer commit calls existing `submit_tree_commits` once. Outer abort
restores the core tree and summary compressor state, retains pinned ongoing
local compressor advancement, and returns no events.

- [x] **Step 5: Preserve batch and allocation invariants.**

Assert one outer commit produces one tree operation plus its required
allocation item in one container batch. No-op and abort produce no allocation
message or outbound operation. An abort after authored edits can retain local
compressor advancement. Existing ordinary edit batching remains unchanged.

- [x] **Step 6: Add schema and reconnect guards.**

`submit_tree_upgrade`, summary creation, reconnect transition, and resubmission
must reject or defer while a transaction is active. The pure core does not
silently discard active transaction state.

- [x] **Step 7: Run runtime-core and schema regression tests.**

```bash
gleam test --target erlang -- shared_tree_runtime shared_tree_transaction shared_tree_array_kernel shared_tree_schema_evolution
gleam test --target javascript -- shared_tree_runtime shared_tree_transaction shared_tree_array_kernel shared_tree_schema_evolution
```

- [x] **Step 8: Commit runtime-core integration.**

```bash
git add src/watershed/runtime_core.gleam src/watershed/channel.gleam test/watershed
git commit -m "feat(tree): submit atomic transactions"
```

**Results (2026-09-30):**

- `Core` now stores one active transaction with its tree address and immutable
  view. Matching reads and retained snapshots use isolated state. Matching
  edits update only the transaction and emit no event or outbound operation.
- Outer commit installs one composed pending commit and submits one grouped
  allocation-plus-tree batch. Nested commit and abort update only the active
  transaction. Outer abort and no-op install the state and compressor returned
  by Task 4 without adding pending history.
- Before the composed outer commit reaches the existing encoder, its authored
  revisions are replaced with the single outer commit revision. This preserves
  identity order while satisfying the pinned tagged-change wire contract.
- Nested constraint begin uses a new fallible
  `begin_nested_with_constraints` helper. The pure transaction records each
  constraint set with its authoring state, so a nested constraint on content
  authored earlier by the outer transaction follows author order. Nested abort
  removes only constraint sets authored in that scope.
- Schema upgrade, summary channel capture, document summary capture, pending
  summary evidence, reconnect adoption, resubmission, and sequenced inbound
  application return typed errors while a transaction is active.
  `is_synced` and `wants_summary` are false during an active transaction.
- `adopt_reconnect` now returns `Result(Core, CoreError)`. The JavaScript and
  BEAM runtimes fail the reconnect explicitly on error. Existing core tests
  unwrap the result on their transaction-free paths.
- `channel.gleam` and the schema-evolution test did not need changes. Event
  mapping already covered `TreeChanged`, and the runtime lifecycle tests cover
  schema rejection directly.
- RED first failed to compile on the missing runtime-core lifecycle API and
  nested constraint helper. Behavioral RED runs then exposed unguarded summary
  channels, synchronized-state reporting during a transaction, and the need to
  retain nested constraint authoring state. An array integration RED also
  exposed multiple revision records in the composed tagged commit.
- The required focused matrix passed 159 tests on Erlang and 148 tests on
  JavaScript. Reconnect-signature regressions passed 137 tests on each target.
- Targeted `gleam format --check` and `git diff --check` passed. The repository
  `just format` command stalled in Trellis after starting both format jobs, so
  the changed Gleam files were formatted directly.

**Review fix evidence (2026-09-30):**

- Added transaction regressions for a nested constraint authored after an
  outer array insertion and for a retained detached `NodeRef` across finish,
  remote reconciliation, and local acknowledgement.
- On the untouched `5abf36e0` baseline, both targets failed the corrected
  transaction regressions with 23 passed and 3 failed:

  ```bash
  gleam test --target erlang -- shared_tree_transaction
  gleam test --target javascript -- shared_tree_transaction
  ```

  The failures showed the constrained `B` removal at count 0, the unconstrained
  `Z` removal at count 1, and the detached `A` reference becoming invalid after
  finish.
- `ConstraintSet` now retains its authored change boundary. Finish emits each
  set as a constraint-only operand at that boundary before composing and
  squashing the outer transaction. Constraint atom IDs start above the
  authored transaction watermark.
- Revision replacement now returns the exact old-to-squashed atom map.
  Preview identity promotion uses its reverse lookup for canonical detached
  keys, so retained repair nodes keep their preview node identities.
- The required focused matrix passed:

  ```bash
  gleam test --target erlang -- shared_tree_runtime shared_tree_transaction shared_tree_array_kernel shared_tree_schema_evolution
  gleam test --target javascript -- shared_tree_runtime shared_tree_transaction shared_tree_array_kernel shared_tree_schema_evolution
  ```

  Erlang passed 162 tests. JavaScript passed 151 tests.
- Direct change, forest, and history coverage also passed 225 tests on each
  target:

  ```bash
  gleam test --target erlang -- shared_tree_change shared_tree_forest shared_tree_array_forest shared_tree_map_forest shared_tree_history
  gleam test --target javascript -- shared_tree_change shared_tree_forest shared_tree_array_forest shared_tree_map_forest shared_tree_history
  ```

**Review fix round 2 evidence (2026-09-30):**

- Added two permanent regressions for a nested constraint committed without a
  later edit. After `[A, B, Z]` becomes `[C, A, B, Z]`, remote removal of `B`
  must produce one violation and remote removal of `Z` must produce none.
- On the untouched `639022a3` baseline, both targets ran 28 transaction tests
  with 26 passed and 2 failed:

  ```bash
  gleam test --target erlang -- shared_tree_transaction
  gleam test --target javascript -- shared_tree_transaction
  ```

  The constrained `B` removal produced 0 violations. The unconstrained `Z`
  removal produced 1.
- Finish now composes constraint-only changes at their recorded author
  boundaries. It uses the next authored revision at a pre-edit boundary and
  the final authored revision at the trailing boundary. Constraint atom IDs
  start after the authored transaction watermark, so the fix adds no revision
  allocation and creates no atom collisions.
- A transaction with constraints but no data still returns `NoCommit`.
- The required focused matrix passed 153 tests on Erlang and 164 tests on
  JavaScript:

  ```bash
  gleam test --target erlang -- shared_tree_runtime shared_tree_transaction shared_tree_array_kernel shared_tree_schema_evolution
  gleam test --target javascript -- shared_tree_runtime shared_tree_transaction shared_tree_array_kernel shared_tree_schema_evolution
  ```

- Direct change and tree-kernel coverage passed 133 tests on each target:

  ```bash
  gleam test --target erlang -- shared_tree_change shared_tree_change_constraint shared_tree_kernel
  gleam test --target javascript -- shared_tree_change shared_tree_change_constraint shared_tree_kernel
  ```

### Task 6: Expose the JavaScript callback API

**Files:**
- Modify: `src/watershed/runtime.gleam`
- Modify: `src/watershed.gleam`
- Modify: `test/watershed/shared_tree_runtime_js_test.gleam`
- Modify: `test/watershed/shared_tree_array_facade_test.gleam`
- Modify: `test/watershed/shared_tree_map_facade_test.gleam`
- Modify: `test/watershed/facade_parity_test.gleam`

**Interfaces:**
- Consumes: Task 5 runtime-core lifecycle.
- Produces: the JavaScript public API in section 3.

- [x] **Step 1: Add failing facade type and callback tests.**

Cover success value, typed callback error, setup error, nested success, nested
abort handled by the outer callback, callback reads after each edit, one
subscriber event after outer success, no subscriber event after abort, no-op,
wrong tree, and schema-upgrade rejection.

- [x] **Step 2: Add runtime begin/commit/abort wrappers.**

Each wrapper reads the runtime cell, requires ready state, calls the matching
runtime-core function, updates the cell before fan-out, and sends outbound only
for outer commit.

- [x] **Step 3: Implement the generic public callback.**

Use this control flow:

```gleam
use <- result.try(
  runtime.begin_tree_transaction(tree.runtime, tree.address, tree.view, paths)
  |> result.map_error(TransactionFailed),
)
case callback(tree) {
  Ok(value) ->
    runtime.commit_tree_transaction(tree.runtime, tree.address)
    |> result.map(fn(_) { value })
    |> result.map_error(TransactionFailed)
  Error(error) ->
    case runtime.abort_tree_transaction(tree.runtime, tree.address) {
      Ok(_) -> Error(Aborted(error))
      Error(runtime_error) -> Error(TransactionFailed(runtime_error))
    }
}
```

If abort itself fails, return `TransactionFailed` rather than hiding the runtime
error behind `Aborted`.

- [x] **Step 4: Verify synchronous event reentrancy.**

The one subscriber callback after outer success must read final committed
state. No subscriber callback runs for intermediate edits or abort. Reentrant
edits during the commit event follow the existing runtime event rules.

- [x] **Step 5: Run JavaScript facade and parity tests.**

```bash
gleam test --target javascript -- shared_tree_runtime_js shared_tree_array_facade shared_tree_map_facade facade_parity
```

- [x] **Step 6: Commit the JavaScript facade.**

```bash
git add src/watershed/runtime.gleam src/watershed.gleam \
  test/watershed/shared_tree_runtime_js_test.gleam \
  test/watershed/shared_tree_array_facade_test.gleam \
  test/watershed/shared_tree_map_facade_test.gleam \
  test/watershed/facade_parity_test.gleam \
  docs/superpowers/plans/2026-09-29-shared-tree-transactions.md
git commit -m "feat(tree): expose JS transactions"
```

**Actual evidence (2026-09-30):**

- RED: the exact JavaScript matrix failed to compile because
  `watershed.tree_transaction`, its public constructors, and the three runtime
  lifecycle wrappers did not exist.
- GREEN: the exact JavaScript matrix passed 27 tests. It covers callback
  values, typed aborts and setup failures, nested commit and abort, isolated
  reads, invalid-edit rollback, constraints, no-op, wrong tree and view,
  schema rejection, one final-state event, array and map edits, and reentrant
  outbound order.
- The commit wrapper installs rollback state when runtime-core commit fails.
  A deterministic array composition failure verifies that the next transaction
  can begin and commit.
- Target-aware Erlang facade parity passed 7 tests while the BEAM callback API
  was still deferred to Task 7.
- Targeted formatting and `git diff --check` passed.

**Review fix evidence (2026-09-30):**

- A callback that moved the JavaScript runtime to `Reconnecting` stranded its
  active scope because commit and abort only handled `Ready`. The regression
  covered an inner successful callback, an outer callback error, retained outer
  savepoint state, full rollback, reconnect, and a later successful
  transaction. Commit now aborts the current scope before returning the
  connection-phase error. Abort unwinds the current scope and preserves the
  core-bearing phase.
- Array facade reads and edits used the address-only runtime functions. A
  same-address handle with a different immutable view could read, insert,
  remove, and move inside another handle's transaction. JavaScript and Erlang
  array facades now use view-aware read and edit routes. The JavaScript
  regression rejects both array reads and all three array edits.
- The valid `[A, B, C]` -> insert `X` -> move `X` -> remove `B` transaction
  failed while squashing revisions. Its move cross-field parent retained an
  alias, and revision replacement tried to remap that alias after aliases were
  removed. Cross-field parents now normalize through the existing alias table
  before replacement. The pure regression verifies retained node identities,
  remapped move keys and parents, exact codec re-encoding, remote replay, and
  final `[A, C, X]`.
- RED: the focused JavaScript run produced three failures. The offline callback
  still exposed the inner edit, the other-view array read returned `A`, and the
  pure sequence failed with
  `CorruptData("revision replacement", "identity was not visited")`.
- GREEN: the Task 6 JavaScript facade matrix passed 29 tests. Erlang array/map
  facade parity passed 15 tests. The transaction, change, kernel, array-kernel,
  and array-change matrix passed 199 tests on each target.

### Task 7: Expose the BEAM callback API and defer remote delivery

**Files:**
- Modify: `src/watershed/runtime_beam.gleam`
- Modify: `src/watershed_beam.gleam`
- Modify: `test/watershed/shared_tree_runtime_beam_test.gleam`
- Modify: `test/watershed/shared_tree_array_facade_test.gleam`
- Modify: `test/watershed/shared_tree_map_facade_test.gleam`
- Modify: `test/facade_parity_test.gleam`

**Interfaces:**
- Consumes: Task 5 runtime-core lifecycle.
- Produces: the BEAM public API in section 3 and ordered deferred remote
  delivery.

- [x] **Step 1: Add failing BEAM callback and interleaving tests.**

Mirror Task 6 cases. Add a controlled remote operation between two callback
edits. The callback must not see it. After outer commit or abort, the actor
applies the remote operation in arrival order.

- [x] **Step 2: Add internal actor messages.**

Add:

```gleam
TreeTransactionBegin(address, view, constraints, reply)
TreeTransactionCommit(address, reply)
TreeTransactionAbort(address, reply)
```

The replies use existing `Result` and outbound/event types. These constructors
remain internal to `runtime_beam`.

- [x] **Step 3: Track deferred remote messages.**

Extend actor state with a FIFO list for sequenced remote delivery received
while `tree_transaction_depth(core) > 0`. Do not defer local transaction
messages, subscriber calls, shutdown, or the transaction timeout path.

- [x] **Step 4: Drain deferred delivery after outer completion.**

After outer commit or abort, process deferred remote messages through the same
handler used during normal operation. Preserve arrival order. Stop and enter
the repository-standard failed/suspended state if replay reports a semantic or
transport error.

- [x] **Step 5: Implement the BEAM public callback.**

Call begin through `process.call`, run the callback in the caller process, then
call commit or abort. Map callback and runtime errors exactly as in Task 6.

- [x] **Step 6: Run BEAM facade and parity tests.**

```bash
gleam test --target erlang -- shared_tree_runtime_beam shared_tree_array_facade shared_tree_map_facade facade_parity
```

- [x] **Step 7: Commit the BEAM facade.**

```bash
git add src/watershed/runtime_beam.gleam src/watershed_beam.gleam test/watershed test/facade_parity_test.gleam
git commit -m "feat(tree): expose BEAM transactions"
```

**Actual evidence (2026-09-30):**

- RED: the exact Erlang matrix failed to compile because
  `watershed_beam.tree_transaction`, its public constructors, and the three
  `runtime_beam` lifecycle wrappers did not exist.
- GREEN: the exact Erlang matrix passed 41 tests. It covers generic callback
  values and errors, nested commit and abort, constraints, no-op, wrong view,
  reconnect unwind, array operations, one outer submission, caller exit
  cleanup, semantic replay failure, and transport failure.
- The actor defers complete sequenced `"op"` batches while any transaction
  scope is active. This keeps allocation and SharedTree operation messages in
  one FIFO. The actor drains that FIFO through the normal operation handler
  after outer commit or abort.
- The outer caller owns the actor transaction through a process monitor.
  Caller exit aborts every remaining scope and drains deferred delivery. Commit
  or abort in reconnecting, catching-up, or suspended phases unwinds the
  current scope while preserving any enclosing scope.
- A deferred semantic failure returns an error and enters the existing failed
  or suspended state. A commit transport failure returns an error and enters
  reconnecting state. An abort failure with an active scope fails the actor
  instead of leaving a stranded transaction.
- JavaScript facade and common parity coverage passed 29 tests after
  `tree_transaction` moved out of the JS-only facade exceptions.
- `just lint` and `just test` passed. The full test gate included 2387 root
  Erlang tests, 2653 root JavaScript tests, 120 source-snippet tests, 2360
  website Node tests, and 42 browser integration tests.
- `just build` passed the Gleam build stages, then the existing
  `shared_tree_checklist_lustre` bundle install failed because 28 lockfile
  tarball URLs use Microsoft package feeds that the active supply-chain policy
  rejects. Task 7 did not change dependencies, pins, formats, or lockfiles.

**Reviewed-fix evidence (2026-09-30, baseline `7cbcf6a9`):**

- RED: `gleam test --target erlang -- shared_tree_runtime_beam` crashed the
  actor when a deferred sequence gap made `requestOps` return
  `Error("gap request refused")`. Isolated abort and no-op commit reproductions
  both reached the panic in `request_operations`.
- RED: the controlled two-process reproduction read the owner callback's
  uncommitted `"owner"` value from the nonowner process instead of returning
  `Error("tree transaction uses another caller")`. Its nonowner edit also
  entered the owner's transaction.
- RED: `gleam test --target erlang -- shared_tree_map_facade` passed 8 tests
  and failed the early-handshake nested transaction test because the actor
  reported `"failed"` instead of retaining `"reconnecting"` until the callback
  unwound.
- GREEN: the Erlang Task 7 matrix passed 44 tests:
  `shared_tree_runtime_beam`, `shared_tree_array_facade`,
  `shared_tree_map_facade`, and `facade_parity`.
- GREEN: JavaScript parity passed 29 tests:
  `shared_tree_runtime_js`, `shared_tree_array_facade`,
  `shared_tree_map_facade`, and `facade_parity`. The reconnect-adjacent
  presence selection passed 17 Erlang tests.
- Every same-address actor tree read and edit now checks the reply subject's
  owner while a callback transaction is active. This includes view, map,
  array, retained snapshot, compatibility, history, and schema-upgrade routes.
  Other processes receive an explicit error; the owner can continue, and
  ordinary access resumes after the scope ends.
- A successful reconnect handshake received during an active callback is held
  in actor state. The actor adopts it after the outer scope aborts, commits, or
  is cleaned up after caller exit, preserving the core and pending state.
- `requestOps` transport failures now return through deferred replay and use
  the existing failed, reconnecting, or suspended transition. Abort and no-op
  commit return a transaction failure instead of losing the actor callee.

**Remaining reconnect-order fix evidence (2026-09-30, baseline `128c9f42`):**

- RED: `gleam test --target erlang -- shared_tree_map_facade` passed 9 tests
  and failed 3 controlled reconnect cases. With a checkpoint equal to the
  retained sequence, complete post-handshake operation batches were discarded
  while the actor remained reconnecting. The outer abort and commit paths both
  finished with the remote value absent, and a bad retained batch did not
  replace the callback abort with a transaction failure.
- GREEN: the actor retains operation batches only after the current-generation
  reconnect handshake is held by an active transaction. Old-generation and
  pre-handshake operations remain ignored. After the outer scope unwinds, the
  actor adopts the handshake and replays retained batches FIFO through the
  normal sequenced-operation handler before replying.
- The permanent cases cover an allocation-bearing first batch, two sequence
  numbers in order, nested scopes with inner commit and outer abort, the outer
  commit cleanup path, obsolete old-connection and pre-handshake operations,
  and a replay error that must return `TransactionFailed` and fail the actor.
- The focused map selection passed 12 tests. The Task 7 Erlang and
  reconnect-adjacent selection passed 64 tests:
  `shared_tree_runtime_beam`, `shared_tree_array_facade`,
  `shared_tree_map_facade`, `facade_parity`, and `presence`.

**Settlement transport fix evidence (2026-09-30, baseline `7f4342a1`):**

- RED: `gleam test --target erlang -- shared_tree_map_facade` passed 12 tests
  and failed the controlled reconnect settlement case. An unacknowledged tree
  edit survived reconnect, the held checkpoint stayed ahead until replayed
  join and leave messages closed the reconnect barrier, and the resubmit
  `submitOp` returned `Error("resubmit refused")`. The outer callback still
  returned `Aborted(Stop)` because `settle_reconnect_state` discarded that
  transport result.
- GREEN: `settle_reconnect_state` now returns its state and `Result` together.
  Handshake adoption and normal operation delivery propagate that result, so
  deferred FIFO replay stops before the callback reply and reports
  `TransactionFailed("resubmit refused")`. The actor remains reconnecting with
  one pending tree edit, and the optimistic `"retained"` value remains
  readable.
- The focused Task 7 and reconnect-adjacent Erlang selection passed 65 tests:
  `shared_tree_runtime_beam`, `shared_tree_array_facade`,
  `shared_tree_map_facade`, `facade_parity`, and `presence`. Scoped `gleam
  format` and `git diff --check` also passed.

### Task 8: Prove reconnect, summary, and native facade parity

**Files:**
- Modify: `test/watershed/shared_tree_history_resubmit_test.gleam`
- Modify: `test/watershed/shared_tree_summary_test.gleam`
- Modify: `test/watershed/shared_tree_document_summary_test.gleam`
- Modify: `test/watershed/shared_tree_client_test.gleam`
- Modify: `test/watershed/shared_tree_runtime_js_test.gleam`
- Modify: `test/watershed/shared_tree_runtime_beam_test.gleam`
- Modify: `test/watershed/shared_tree_fixture_test.gleam`
- Modify: `test/watershed/tree/transaction_fixture.gleam`

**Interfaces:**
- Consumes: Tasks 2-7 complete native behavior.
- Produces: dual-target corpus parity, reconnect evidence, and summary
  continuation before service work.

- [x] **Step 1: Add corpus runners for callbacks, constraints, and history.**

Add:

```gleam
pub fn run_callbacks(input: Json) -> Result(Json, String)
pub fn run_constraints(input: Json) -> Result(Json, String)
pub fn run_history(input: Json) -> Result(Json, String)
```

They must use fixture input only and report complete observations.

- [x] **Step 2: Add pending resubmit tests.**

Author one multi-edit transaction, disconnect before acknowledgement, reconnect,
and assert one resubmitted commit, one acknowledgement, no duplicate local
event, and stable node identity.

- [x] **Step 3: Add summary-plus-tail tests.**

Take a summary while a transaction is pending. Assert the summary contains
sequenced state only. Load it in a fresh runtime, apply the tail transaction,
and continue editing. Repeat for a transaction that later becomes explicitly
violated.

- [x] **Step 4: Add accepted-before-drop tests.**

Deliver the transaction to the service, drop the sender before local
acknowledgement, reconnect, and assert deduplication by revision and one visible
effect.

- [x] **Step 5: Run native corpus and persistence gates.**

```bash
gleam test --target erlang -- shared_tree_transaction shared_tree_history_resubmit shared_tree_summary shared_tree_document_summary shared_tree_client shared_tree_fixture
gleam test --target javascript -- shared_tree_transaction shared_tree_history_resubmit shared_tree_summary shared_tree_document_summary shared_tree_client shared_tree_fixture
just shared-tree-codec-interop
just shared-tree-test
```

- [x] **Step 6: Commit native persistence proof.**

```bash
git add test/watershed
git commit -m "test(tree): prove transaction recovery"
```

### Task 9: Prove mixed-client transactions through Floodgate

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
- Produces: required transaction sections in local and hosted interop reports.

- [x] **Step 1: Add failing command-protocol tests.**

Add explicit actions:

```json
{"op":"transaction","edits":[...],"constraints":[{"type":"nodeInDocument","path":["items","0"]}],"result":"commit"}
{"op":"transaction","edits":[...],"constraints":[],"result":"abort"}
```

Clients return callback observations, events, commit revision, outbound count,
and final tree. Coordinators must not author changes for clients.

- [x] **Step 2: Require transaction report sections.**

Require:

```javascript
const requiredTransactionSections = [
  "transactionCallbacks",
  "transactionConstraints",
  "transactionReconnect",
  "transactionReloadMatrix",
];
```

Test rejection after removing a section, target, race ordering, reload cell, or
observation.

- [x] **Step 3: Run deterministic mixed-client scenarios.**

Use JS/upstream, BEAM/upstream, and JS/BEAM pairs. Each implementation authors
commit and abort cases. Run concurrent constrained transaction versus node
remove in both sequencing orders. Include same-array and cross-array node
moves as nonviolating controls.

- [x] **Step 4: Run reconnect and nine writer/reader cells.**

For each writer in `upstream`, `javascript`, `erlang`, publish a summary after
a constrained transaction. Each reader loads it, verifies history and node
identity, authors another transaction, and exposes the result to a peer.

- [x] **Step 5: Extend seeded schedules.**

Add transaction start/edit/commit/abort, nested scopes, node moves, constrained
removals, disconnects, acknowledgements, and summary reloads. Keep the seed,
schedule, constraints, callback result, and event trace in failure artifacts.
Run 300 schedules with seed 42 in the required gate.

- [x] **Step 6: Run local real-service gates.**

```bash
node --test tools/shared-tree-oracle/client-driver.test.mjs tools/shared-tree-oracle/client-interop.test.mjs tools/shared-tree-oracle/summary-interop.test.mjs tools/shared-tree-oracle/interop.test.mjs tools/shared-tree-oracle/service.test.mjs
just shared-tree-interop
```

Expected: pinned service identity; all three implementations; both constraint
race orders; reconnect evidence; nine reload cells; no skipped required target,
service, or corpus.

- [x] **Step 7: Commit interoperability proof.**

```bash
git add tools/shared-tree-oracle test/fixtures/shared_tree
git commit -m "test(tree): prove transaction interoperability"
```

**Task 9 evidence (2026-10-02):**

- Commits: `6eb9f24b`, `195a6a3d`, and `bb078942`.
- `node --test` over the five oracle suites: 97 passed.
- `just shared-tree-interop`: passed 300 seeded schedules with seed 42 and no
  skipped target, service, or corpus. Run `ef34e6a5` reports 3 callback pairs,
  6 constraint race cells, 2 reconnect cases, 9 reload cells, and 120 seeded
  transactions.
- Gleam client tests passed on both targets.
- The reload matrix gates are falsifiable: mutation checks for
  `nodeIdentityVerified` and `historyVerified` failed against the real service,
  then were reverted.
- Upstream fires a local change event for each edit and for rollback, so the
  one-event rule is asserted for the native authors. Atomicity for all three
  implementations uses the sequenced `acceptedCommitCount`.
- `historyVerified` matches the composed commit by content because upstream
  reports session-local compressed IDs and the BEAM reader evicts its trunk
  below the loaded base.

### Task 10: Close permanent gates and document the transaction profile

**Reconciled status:** Complete for the transaction slice. The generated and
service profiles publish synchronous single-tree transactions and stable
node-existence constraints. Task 11 still owns final regression closure, and
the undo/redo plan owns its support labels.

**Files:**
- Modify: `tools/shared-tree-oracle/generate.mjs`, `interop.mjs`, `service.mjs`
- Modify: their tests and `tools/shared-tree-oracle/gates.test.mjs`
- Generate: `test/fixtures/shared_tree/profile.json`, `manifest.json`, capture metadata
- Modify: `tools/shared-tree-oracle/README.md`
- Modify: `README.md`
- Modify: `.github/workflows/shared-tree.yml`
- Modify: `.github/workflows/shared-tree-interop.yml`
- Modify: `justfile` only if existing commands do not select the new required cases
- Modify: `docs/superpowers/plans/2026-09-21-shared-tree.md`

**Interfaces:**
- Consumes: Tasks 1-9 passing evidence.
- Produces: an accurate supported transaction claim and permanent enforcement.

- [x] **Step 1: Add failing profile and gate assertions.**

Require support labels for synchronous single-tree transactions and stable
node-existence constraints. Keep async, cross-tree, schema-in-transaction,
`noChange`, metadata, and post-processors explicit exclusions. Undo/redo
profile labels belong to the undo/redo plan's Task 9 and must not be added or
removed implicitly by this task.

Focused RED evidence: the transaction profile, generated transaction contract,
and supported-profile workflow-name assertions all failed before the profile
owner and workflows changed.

- [x] **Step 2: Regenerate profile metadata.**

```bash
npm --prefix tools/shared-tree-oracle run generate
npm --prefix tools/shared-tree-oracle run check
```

Preserve every version, codec, layout, and M1-M4 feature claim.

- [x] **Step 3: Document the public API and limits.**

Show one committed callback, one aborted callback with typed error, and a
`NodeInDocument` constraint. Explain nested scopes, one outer local event and
network commit, no abort event, sequenced constraint checks, and deferred
features.

- [x] **Step 4: Update the parent roadmap.**

Mark the transaction-boundary and stable-constraint slice implemented. Do not
close the full milestone here; the parent roadmap and the undo/redo plan own
the broader milestone wording.

- [x] **Step 5: Run Task 10 focused permanent-gate checks.**

```bash
cd tools/shared-tree-oracle && node --test \
  --test-name-pattern='service profile names supported transactions|manifest records complete native runners|committed profile is hashed|hosted gates name the supported profile' \
  service.test.mjs generate.test.mjs interop.test.mjs gates.test.mjs
npm --prefix tools/shared-tree-oracle run generate
npm --prefix tools/shared-tree-oracle run check
```

The full oracle, native, codec, and service commands remain deferred to the
combined transaction/undo validation and this plan's Task 11, as directed for
this release sequence.

- [x] **Step 6: Commit profile and documentation closure.**

```bash
git add tools/shared-tree-oracle test/fixtures/shared_tree README.md .github/workflows justfile docs/superpowers/plans/2026-09-21-shared-tree.md
git commit -m "docs(tree): define transaction support"
```

### Task 11: Run full regression closure

**Files:**
- Modify only files required to fix regressions caused by Tasks 1-10.
- Do not change unrelated failing tests or baseline behavior.

**Interfaces:**
- Consumes: all transaction implementation and permanent gates.
- Produces: final M5 transaction-foundation acceptance evidence.

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

Use a focused Conventional Commit message that names the corrected transaction
behavior. Do not create an empty closure commit.

## 5. Acceptance checklist

The unchecked boxes remain release acceptance, not an inventory of implemented
functions or tests. Close them only with Task 10 profile changes and Task 11
validation evidence.

- [ ] One outer success produces one composed SharedTree commit.
- [ ] Outer abort restores values, identities, history, and summary compressor
      state while preserving pinned ongoing local compressor advancement.
- [ ] Nested success and abort match the pinned upstream observations.
- [ ] One outer commit event and no abort event match the pinned upstream model.
- [ ] Node-existence constraints use identity and survive node moves.
- [ ] A concurrent node removal suppresses constrained edits on every client.
- [ ] Explicit violation remains distinct from an empty or implicit-conflict change.
- [ ] Constraint codec bytes match ModularChange V5.
- [ ] Object, map, array, and move edits work in one transaction.
- [ ] Schema upgrades and cross-tree transactions fail without partial state.
- [ ] No-op transactions do not allocate or submit. Aborted transactions
      preserve pinned local compressor advancement but emit no allocation range
      or outbound operation.
- [ ] JavaScript and BEAM expose matching generic callback APIs.
- [ ] BEAM defers remote operations until the synchronous outer scope ends.
- [ ] Reconnect resubmits one transaction without duplicate effects.
- [ ] Summaries use sequenced state and continue with transaction tail ops.
- [ ] Upstream, native JavaScript, and native BEAM clients author and continue constrained transactions through pinned Floodgate.
- [ ] All nine summary writer/reader combinations continue editing.
- [ ] Required gates fail on missing artifacts, targets, scenarios, or service.
- [ ] Existing M1-M4 behavior and native container creation remain intact.
- [ ] Transaction documentation distinguishes this implemented slice from the
      separately implemented but not yet profile-closed undo/redo slice and
      from still-deferred transaction features.

## 6. Review matrix and stop conditions

| Design requirement | Owning tasks |
| --- | --- |
| Callback, nesting, outer event, and abort | 1, 4, 6, 7 |
| Stable node-existence constraints | 1, 2, 3, 5 |
| Exact V5 wire behavior | 1, 2, 8 |
| One outer commit and no-op allocation rule | 4, 5, 6, 7 |
| Object, map, array, and move coverage | 1, 3, 4, 8, 9 |
| Reconnect and summary continuation | 1, 8, 9 |
| JS/BEAM facade parity | 6, 7, 8 |
| Real-service and cross-writer proof | 9 |
| Permanent profile and CI gates | 10, 11 |

Stop and revise the design before continuing if the pinned source shows any of
these results:

- a stable constraint other than `nodeInDocument` is required for ordinary
  transaction correctness;
- node movement violates `nodeInDocument`;
- explicit violation is encoded as an empty outer change;
- the V5 codec writes revert-only node constraints;
- nested abort closes the outer transaction;
- asynchronous delivery is required to implement the synchronous callback;
- a valid data-only transaction requires schema changes in the same outer
  commit.
