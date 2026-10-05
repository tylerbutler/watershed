# SharedTree Local Branching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Stop at the Task 1 contract gate before implementing native branching.

**Goal:** Complete the runtime-local M6 slice with isolated editable forks, explicit rebase and merge, checkout-scoped undo, and safe lifetime on JavaScript and BEAM.

**Architecture:** A runtime-owned checkout registry gives each local fork an isolated forest and retained ancestry while sharing the document allocator. Opaque `SharedTree` handles select the document checkout or a local checkout; the existing field APIs operate on either. Only a merge into the document checkout enters the normal sequenced submission path.

**Tech Stack:** Dual-target Gleam, startest, Node test runner, pinned Fluid source/package oracle, pinned Floodgate, existing `just` and GitHub Actions gates.

**Spec:** [SharedTree local branching](../specs/2026-10-05-shared-tree-local-branching-design.md), approved in conversation on 2026-10-05. At the Task 1 review gate, the user selected upstream-compatible independent cross-checkout callback edits instead of the original refusal boundary.

## Global constraints

- Production semantics remain pure Gleam on JavaScript and BEAM.
- Upstream packages are development/test dependencies, not a production branch engine.
- Keep `@fluidframework/tree` 3.1.0.
- Keep Fluid source `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960` (`client_v3.1.0`).
- Keep Floodgate `0eb493fc46d1bb9baf1151a6ccdde93544e057e7`.
- Keep `minVersionForCollab` at `2.117.0`.
- Keep Message V7, SharedTreeChange V5, ModularChange V5, and Schema V2.
- Keep the existing fixed bootstrap-map/tree container layout.
- Preserve M1-M5, Identifier, native creation, and the existing main-checkout API.
- Exclude shared/persisted branches, branch wire messages, historical checkout, branch schema authoring, cross-runtime/tree merge, async transactions, portable revertibles, clone-to-view, `revertTo`, preview diffs, and richer Lustre bindings.
- Do not add an offline-authoring guarantee or a Watershed-managed undo stack.
- Apply ASD-STE100 to Gleam comments/error strings, not Markdown prose.
- Generate fixtures through the oracle; do not hand-edit generated output, `.code-map/`, or apm-managed files.
- Reject unsupported behavior explicitly and atomically; do not approximate pinned semantics.

---

## 1. Baseline and execution discipline

Planning baseline: `a608c778` (`docs(tree): record M5 acceptance limits`).
Read `AGENTS.md`, the spec, the current parent roadmap, and both M5 plans.
Record the actual execution HEAD and working-tree status before edits.

This planning session uses the user's in-place checkout. Do not create a branch,
worktree, stash, commit, or push without user authorization. During execution,
use the user's selected workspace and commit policy; the suggested commit
messages below are boundaries, not permission to commit.

Use test-first cycles within each task: add one named failing behavior, run it,
implement the smallest complete behavior, rerun it, then add the next case.
Do not build an entire task before checking its first failure. Review each
task's diff and contracts before dependent work starts.

The baseline M5 build/browser limitation is separate from branching:
`just build` and `just shared-tree-checklist` hit a pnpm policy/lockfile mismatch.
Design and oracle work may proceed, but final acceptance must run these gates
and either pass or report a reproduced baseline blocker. Do not disable policy,
rewrite unrelated lockfiles, or claim M6 release acceptance from partial gates.

### Dependency order

```text
1 pinned oracle + reviewed executable contract
                    |
2 pure ancestry and retention
                    |
3 isolated forest and reconcile operations
                    |
4 shared allocation, transactions, undo
                    |
5 runtime-core checkout routing and publication
                /       \
6 JavaScript facade     7 BEAM facade
                \       /
8 native lifecycle, recovery, summary matrix
                    |
9 mixed-client / real-service proof
                    |
10 permanent gates and documentation
                    |
11 full regression and M6 acceptance
```

Tasks 2-5 have one integration owner: history, kernel, allocation, events, and
runtime-core cannot evolve independently. Tasks 6 and 7 can overlap only after
Task 5 fixes interfaces and they have separate file ownership. No subagents are
required by this plan.

## 2. File map

| Files | Responsibility |
| --- | --- |
| `src/watershed/tree/types.gleam` | Internal checkout selector and local checkout ID; public status where shared across targets |
| `src/watershed/tree/history.gleam` | Local ancestry, common revisions, reconciliation, rollback retention, and branch pins |
| `src/watershed/tree_kernel.gleam` | Isolated forest/schema/repair state, atomic rebase and merge |
| New `src/watershed/tree/branch.gleam` | Pure checkout-registry entries and lifecycle reducer; reuse history and kernel algorithms |
| `src/watershed/tree/runtime.gleam`, `transaction.gleam` | Contextual authoring, shared compressor, checkout-local transactions with independent cross-checkout callback edits |
| `src/watershed/runtime_core.gleam` | Registry ownership, checkout selection, normal document submission and recovery |
| `src/watershed/channel.gleam` | Internal event scope only if necessary; no new routed channel kind |
| `src/watershed/runtime.gleam`, `runtime_beam.gleam` | Target-specific handle routing, subscribers, delivery locks, cleanup |
| `src/watershed.gleam`, `watershed_beam.gleam` | Compatible `SharedTree` selector, fork/rebase/merge/status/disposal |
| New `tools/shared-tree-oracle/upstream-branch.spec.ts` | Pinned executable branch observations |
| Existing oracle source/generate/schema/interop files and tests | Capture, normalize, validate, generate, and gate branch evidence |
| New `test/watershed/tree/branch_fixture.gleam` | Complete input-only native branch corpus runner |
| New `test/watershed/shared_tree_branch_test.gleam` | Pure/kernel and corpus acceptance |
| Existing runtime/facade/history/summary tests | Checkout routing and preservation of M1-M5 |
| `test/watershed/tree/client_protocol.gleam`, `client_js.gleam`, `client_beam.gleam` | Real native branch commands in the interop clients |
| `README.md`, oracle README, parent roadmap, CI workflows, `justfile` | Supported local profile and permanent enforcement |

Before extracting a helper, find all its callers. Generalize only ancestry or
checkout routing needed by this feature; do not restructure unrelated large
modules. A branch registry is not a second event bus or generic command engine.

## 3. Contract sketches and gate ownership

Task 1 writes a checked contract table into this plan. The sketches below name
the integration points; their pure result payloads must be finalized from the
oracle before Task 2. Do not fabricate protocol details to keep these sketches.

```gleam
// src/watershed/tree/types.gleam
pub type LocalCheckoutId {
  LocalCheckoutId(value: Int)
}

pub type CheckoutSelector {
  DocumentCheckout
  LocalCheckout(id: LocalCheckoutId)
}
```

Runtime ownership, document identity, tree address, and selector together define
an origin. An integer ID alone is never a portable branch capability.

Public functions on both facades:

```text
tree_fork(tree: SharedTree) -> Result(SharedTree, String)
tree_rebase_onto(source: SharedTree, target: SharedTree) -> Result(Nil, String)
tree_merge(target: SharedTree, source: SharedTree, dispose_source: Bool)
  -> Result(Nil, String)
tree_branch_status(tree: SharedTree) -> TreeBranchStatus
tree_dispose_branch(tree: SharedTree) -> Result(Nil, String)

TreeBranchStatus = DocumentBranch | BranchValid | BranchDisposed
```

Keep selector fields private. Existing `resolve_tree`/`open_tree` produce
`DocumentCheckout`. Reads, edits, compatibility, transactions, subscriptions,
and reversion carry the selector internally without changing their public
field-operation signatures.

Proposed runtime-core entry points, owned by Task 5:

```text
fork_tree(core, address, source_selector, view)
  -> Result(#(Core, LocalCheckoutId), CoreError)
rebase_tree_onto(core, address, source_selector, target_selector)
  -> Result(#(Core, scoped_events), CoreError)
merge_tree(core, address, target_selector, source_selector, dispose_source)
  -> Result(#(Core, scoped_events, outbound_operations), CoreError)
dispose_tree_branch(core, address, selector) -> Result(Core, CoreError)
tree_branch_status(core, address, selector) -> TreeBranchStatus
```

The proposed `scoped_events` type is
`List(#(String, types.CheckoutSelector, channel.ChannelEvent))`;
`outbound_operations` is `List(wire.OutboundOperation)`. Task 1 confirms the
event payload contract and Task 5 implements it. Scope distinguishes main and
local delivery without changing wire routes. Document-only callers retain
their current API through small wrappers selecting `DocumentCheckout`.

## 4. Tasks

### Task 1: Capture the pinned branch contract and stop for review

**Files:** Create `tools/shared-tree-oracle/upstream-branch.spec.ts`; modify
`source.mjs`, `source.test.mjs`, `generate.mjs`, `generate.test.mjs`;
generate `test/fixtures/shared_tree/` through existing commands.
Update this plan's checked contract table before native work.

**Consumes:** Fluid/package pins and the existing capture/injection mechanism.
**Produces:** Input scenarios, stable observations, exact raw wire evidence,
validated branch fixtures, and reviewed pure/runtime contracts.

- [x] **Step 1: Add a failing source-registration test.**

  Follow the existing undo-source tests. Require the branch injection path
  `packages/dds/tree/src/test/watershedBranch.spec.ts`, exact version/commit,
  and a source digest. Run:

  ```bash
  rtk proxy node --test tools/shared-tree-oracle/source.test.mjs
  ```

  Expected red: branch injection is not registered, not a missing dependency.

- [x] **Step 2: Implement branch capture using real upstream checkouts.**

  Use the existing configured factory, fixed schema, `TestTreeProviderLite`,
  and capture writer patterns. The first behavior probe is:

  ```typescript
  const fork = view.fork();
  fork.root.title = "fork";
  assert.equal(view.root.title, "base");
  view.merge(fork);
  assert.equal(view.root.title, "fork");
  ```

  Add new source injection to the owned injection map. Do not patch upstream
  tracked files or capture backing B-trees/listener objects as semantic output.

- [x] **Step 3: Capture every required contract group incrementally.**

  | Case ID | Required observations |
  | --- | --- |
  | `local-branch-isolation` | Main and nested forks; attached/detached identity; parent disposal; no branch tree submission |
  | `local-branch-rebase` | Both edit orders, target unchanged, common revisions, optimistic main base |
  | `local-branch-merge` | Surviving revisions/encoded changes, event count/kind, preserved source, repeated/empty/self merges, default disposal |
  | `local-branch-transactions` | Guards, nested abort/commit, constraints, one outer commit, independent cross-checkout callback edits surviving source rollback |
  | `local-branch-undo` | Local factories, late/duplicate calls, undo/redo, merged target handles, original source handles, settlement registration/delivery |
  | `local-branch-allocation` | Shared compressor, interleaved Identifiers, abort/discard ranges, exact allocation traffic before/after merge |
  | `local-branch-retention` | Multiple pins, live revertible plus fork, MSN advancement, rebase/dispose release, repair content |
  | `local-branch-recovery` | Pending-main origin, reconnect, accepted-before-drop, unmerged summary exclusion, merged summary continuation |

  For each group, add validator mutation tests that delete an observation,
  revision, allocation range, event, or required row and require rejection.
  Use source-normalized semantic history plus separately retained raw messages.
  Register complete groups; do not advertise a partial projection as a complete
  native runner.

- [x] **Step 4: Generate and verify deterministic source evidence.**

  ```bash
  rtk proxy npm --prefix tools/shared-tree-oracle run source:verify
  rtk proxy npm --prefix tools/shared-tree-oracle run source:inject
  rtk proxy npm --prefix tools/shared-tree-oracle run source:capture
  rtk proxy npm --prefix tools/shared-tree-oracle run generate
  rtk proxy npm --prefix tools/shared-tree-oracle run check
  rtk proxy node --test tools/shared-tree-oracle/source.test.mjs tools/shared-tree-oracle/generate.test.mjs
  ```

  Use `source:prepare` only if the pinned checkout is missing. Dependency
  restoration follows a missing-dependency failure, not speculative installs.

- [x] **Step 5: Resolve and record the contract gate.**

  Record concrete result types and named observations for: arbitrary related
  local targets; self operations; public double disposal; main disposal;
  descendant lifetime; merge commit/event boundaries; schema divergence;
  allocation-only traffic; branch callback settlement before/after merge;
  source-handle disposal; transaction allocation on abort.

  Public comments claim merge commits open transactions, while the checkout
  implementation rejects them. Preserve executable behavior and document the
  difference. Do not invent settlement callbacks for unsequenced commits.
  If public M5 events need an explicit branch-only availability distinction,
  define it here and update the spec before Task 5.

  #### Checked contract table

  These are pinned `@fluidframework/tree` 3.1.0 observations. They are not
  native support claims. The generated branch cases remain input and evidence
  fixtures only; neither native target registers a branch runner in Task 1.

  | Checked | Contract | Pinned executable result | Native contract decision |
  | --- | --- | --- | --- |
  | [x] | Related local targets | A local checkout can rebase onto or merge into a sibling local checkout. The target remains unchanged by rebase. Merging the sibling does not change main until that target is merged into main. | Allow only checkouts with the same runtime, document, tree, and live origin. Keep `Result(Nil, String)` and reject before mutation otherwise. |
  | [x] | Self operations | Self-rebase is a history-preserving no-op. Self-merge with `dispose_source: false` is a no-op. Self-merge with the default disposal disposes the checkout. | Match these results explicitly. |
  | [x] | Public double disposal | Calling `dispose()` twice on the public fork view succeeds twice; the second call is an idempotent no-op. | `tree_dispose_branch` is idempotent and returns `Ok(Nil)` for an already disposed local handle. |
  | [x] | Main disposal | Disposing the main view does not dispose the document checkout; another view opens on the same state. | `tree_dispose_branch` rejects `DocumentCheckout`; normal view/runtime shutdown remains separate. |
  | [x] | Descendant lifetime | Disposing a parent fork leaves its descendant live, editable, and independently pinned. | A child owns its ancestry pin and remains valid after parent disposal. |
  | [x] | Attached and detached identity | Main, parent, and nested forks retain the same attached node ID. Removing the left node on a fork leaves the main node attached with the same ID. Editing the detached fork node errors because it is not `InDocument`. | Preserve stable IDs across persistent forests. Keep detached repair data checkout-local and reject edits through detached node proxies. |
  | [x] | Merge boundaries and events | Two surviving source commits append two target commits and emit two local `Default` events with factories and encoded changes. Repeating the preserved-source merge emits no event. Empty merge disposes its source by default. Merge does not collapse the source commits into one transaction commit. | `scoped_events` has one target-scoped event per surviving source commit. `outbound_operations` contains only ordinary document operations when the target is main. |
  | [x] | Open transactions | Rebase rejects an active transaction on source or target. Merge rejects an active transaction on source or target. Fork rejects an active source transaction. The pinned implementation rejects rather than committing the transaction despite the public merge comment. | Reject active transactions atomically on every affected checkout. |
  | [x] | Node-existence constraint | A constrained source commit disappears when rebase finds that main replaced the guarded node. Source and target both retain the replacement and the source title returns to `base`. | Preserve commit constraints in local history and evaluate them during rebase. Drop a commit whose required node no longer exists. |
  | [x] | Cross-checkout transaction callback | Pinned upstream permits a callback running a source-fork transaction to edit main; the main edit succeeds and the source rollback does not undo it. | User-selected contract: match upstream. Each transaction owns one checkout; edits to another related live checkout commit independently. Commit and rollback preserve the other checkout's state, shared allocator advancement, events, and outbound work. No cross-checkout atomicity. |
  | [x] | Schema divergence | A fork can author a wider schema. Rebasing it onto an old-schema target drops the fork schema change and dependent edit; the target stays unchanged and the fork's wide view becomes incompatible. | Branch schema authoring remains excluded. Reject it before mutation; do not approximate the upstream drop behavior. |
  | [x] | Allocation traffic | A branch-only Identifier insertion advances the shared compressor but processes zero messages and zero ranges. A later main insertion publishes one range (`firstGenCount: 4`, `count: 4`) with only the main tree operation. Merge publishes a second range (`firstGenCount: 8`, `count: 3`) with the branch tree operation. Interleaved IDs are unique. A rolled-back branch transaction advances serialized compressor state and does not reuse its allocation. | All checkouts share the document compressor. A branch reservation alone emits no traffic. Main and merge publication must send the required reserved ranges before their referencing tree operations. |
  | [x] | Settlement before and after merge | A branch-local commit exposes a factory but has no settlement before merge. After merge into main and sequencing, both its source registration and the target merge registration receive `FullyApplied`. | Expose registration on local commits but never report local settlement. Deliver sequencing outcomes to both live registrations after publication. |
  | [x] | Revertible lifetime and source disposal | Preserved-source and merged-target handles remain `Valid` and checkout-scoped. Default source disposal changes its handle to `Disposed`; revert then errors. Duplicate and late factory calls error. Reverting the target handle produces an `Undo` handle; reverting that new handle restores `branch-change` as redo. | Keep one-shot factories and checkout origin. Disposal invalidates only handles owned by that checkout. A successful revert emits the handle for the inverse commit. |
  | [x] | Retention release and reclamation | A live descendant and revertible retain their required history after parent disposal. Rebase advances the descendant pin. Disposing the final handle and descendant, then sequencing three main edits, reduces main history from 9 commits to 1 and advances MSN from 16 to 22. | Each descendant and revertible owns a pin. Release each pin on disposal and let trunk trimming reclaim history after the final pin disappears. |
  | [x] | Pending-main fork and normal reconnect | A fork sees an optimistic pending main edit. A normal disconnected edit reconnects, sequences once, merges once, and reloads from the merged summary. Unmerged branch content is absent from the peer summary; a merged summary reader can continue editing with a standard V7 operation. | Keep branches in-process across normal reconnect and summaries document-only. |
  | [x] | Accepted-before-drop with a live fork | The peer accepts the main edit while author inbound processing is paused. The author disconnects, resumes inbound processing under the old identity, then reconnects. The live fork retains count `23`; one merge operation gives main and peer title `accepted-before-drop` and count `23`, then disposes the source. | Drain accepted acknowledgements before reconnect changes client identity. Keep the live fork usable and publish its merge once. |

  **Stop for user review.** If evidence requires broader scope, codec changes,
  or a different allocation model, revise the design instead of implementing.
  Suggested authorized commit: `test(tree): capture local branch contract`.

### Task 2: Add pure local ancestry and independent retention

**Files:** Modify `tree/types.gleam`, `tree/history.gleam`;
create `test/watershed/shared_tree_branch_test.gleam`; extend
`shared_tree_history_test.gleam` and `shared_tree_history_resubmit_test.gleam`.

**Consumes:** Task 1 checked ancestry and lifetime contract.
**Produces:** Retained local checkout heads, shared-revision reconciliation, and
pins that coexist with pending/peer/revertible retention.

- [x] **Step 1: Add `local_branch_fork_pins_optimistic_head_test`.**

  Start with one trunk commit and one pending edit; retain a fork at the
  optimistic head. Advance MSN and assert its exact base/revisions remain
  available. Run the named test on each target:

  ```bash
  rtk proxy gleam test --target erlang -- local_branch_fork_pins_optimistic_head
  rtk proxy gleam test --target javascript -- local_branch_fork_pins_optimistic_head
  ```

- [x] **Step 2: Implement local ancestry using existing reconciliation.**

  Add explicit local checkout records and lifecycle operations. Reuse
  `rebase_branch`, common-prefix handling, rollback generation, and identity
  rebinding where valid. Its current target is a sequenced list: extend path
  reconciliation to related local heads without inventing sequence numbers for
  branch commits. Keep sequenced metadata separate from ancestry.

  ```text
  fork ancestry = source current head + independent retention pin
  rebase source = target ancestry + rebased divergent source commits
  merge target = target ancestry + surviving rebased source commits
  dispose source = release source pin, not descendant/revertible pins
  ```

- [x] **Step 3: Add independent-pin and revision tests one at a time.**

  Required names: `local_branch_descendant_survives_parent_disposal_test`,
  `local_branch_dispose_preserves_revertible_pin_test`,
  `local_branch_rebase_advances_only_its_pin_test`,
  `local_branch_merge_removes_common_revisions_test`.
  Assert retained ancestry and repair/rollback references, not just visible
  values. Do not preserve an entire document history unconditionally.

- [x] **Step 4: Verify both targets and review history regressions.**

  ```bash
  rtk proxy gleam test --target erlang -- shared_tree_branch shared_tree_history shared_tree_history_resubmit
  rtk proxy gleam test --target javascript -- shared_tree_branch shared_tree_history shared_tree_history_resubmit
  ```

  Suggested authorized commit: `feat(tree): retain local branch ancestry`.

  **Completion record (2026-10-05):** Task 2 adds pure local checkout ancestry,
  independent occurrence pins, related-local rebase and merge reconciliation,
  and checkout disposal. Review fixes exclude target revisions across divergent
  paths, keep replay receipts from moving local ancestry pins, and omit replay
  receipts from semantic ancestry paths even after the original occurrence is
  trimmed. Bounded replay-receipt points live in history snapshots only while
  their trunk entries remain retained. The twelve
  named branch tests and the existing history and resubmit selectors pass on
  Erlang and JavaScript. This does not register a native branch runner or claim
  the later M6 forest, runtime, facade, transaction, undo, allocation, recovery,
  or interop work.

### Task 3: Implement isolated forests and atomic rebase/merge

**Files:** Create `src/watershed/tree/branch.gleam`; modify
`tree_kernel.gleam` and the history interfaces required by Task 2; extend
`shared_tree_branch_test.gleam`.

**Consumes:** Retained related heads and Task 1 field/conflict observations.
**Produces:** Pure fork state, atomic rebase result, and merge result containing
surviving commits and kernel events.

- [ ] **Step 1: Add the isolation RED using the existing kernel fixture setup.**

  Fork a tree, set its title, and require the main title, pending list, detached
  identities, and event stream to remain unchanged. Assert fork and main share
  initial node IDs, not aliased mutable forests.

- [ ] **Step 2: Implement fork and related-head reconciliation.**

  Copy persistent forest/schema/repair state, retain source ancestry, and start
  independent local subscriptions/revertibles. Do not call summary restore,
  regenerate IDs, or inherit a source undo registry by copying `TreeState`.

  ```text
  prepare(source, target)
    -> validate origin + lifetime + transaction/schema guards
    -> compute ancestry reconciliation with existing change algebra
    -> apply net effects to candidate forest
    -> validate candidate history/forest
    -> return candidate states and events
  ```

  Publish candidates only after every fallible operation succeeds. Rebase
  returns a changed source and unchanged target; preserved-source merge follows
  the Task 1 observation, not an assumed implicit rebase of the source.

- [ ] **Step 3: Add each field/conflict case from the corpus.**

  Cover object set/replacement, map set/delete, array insert/remove,
  same-array and cross-array moves. For each, run unrelated and overlapping
  changes in both orders. Assert snapshots, node IDs, changesets, and revision
  boundaries. Required refusal cases: unrelated origin, disposed source/target,
  main rebase, active transactions, branch schema edits, and unsupported schema
  reconciliation after a main schema change.

- [ ] **Step 4: Verify pure branch and existing field tests.**

  ```bash
  rtk proxy gleam test --target erlang -- shared_tree_branch shared_tree_array_kernel shared_tree_map_kernel shared_tree_schema_evolution
  rtk proxy gleam test --target javascript -- shared_tree_branch shared_tree_array_kernel shared_tree_map_kernel shared_tree_schema_evolution
  ```

  Suggested authorized commit: `feat(tree): reconcile isolated local checkouts`.

### Task 4: Wire shared allocation, branch transactions, and revertibles

**Files:** Modify `tree/branch.gleam`, `tree/runtime.gleam`,
`tree/transaction.gleam`, `tree/history.gleam`, `tree_kernel.gleam`;
extend branch, Identifier, transaction, and undo tests.

**Consumes:** Pure branch states; shared document compressor;
`author_edit`, `author_revert`, and existing transaction reducer.
**Produces:** Contextual branch authoring, isolated undo/redo, and correct
allocation ranges for later document publication.

- [ ] **Step 1: Add shared-allocation RED.**

  Interleave main edit, fork A Identifier insert, fork B Identifier insert,
  aborted branch transaction, fork A move, main edit, and both merges.
  Require unique stable IDs and revisions, preserved moved IDs, and captured
  compressor/range observations matching Task 1.

- [ ] **Step 2: Reuse contextual authoring with one allocator.**

  ```text
  author(branch state, document compressor, edit)
    -> candidate branch state + candidate document compressor + local events
  publish merge
    -> ordinary commits + required outstanding allocation ranges
  ```

  Never fork a compressor. Track discarded reserved ranges according to the
  captured upstream allocation/abort rules. No branch tree operation is
  submitted during authoring; allocation-only behavior follows the oracle.

- [ ] **Step 3: Add branch transaction and undo cycles.**

  Required tests: `local_branch_transaction_is_one_outer_commit_test`,
  `local_branch_nested_abort_preserves_identifier_allocation_test`,
  `local_branch_undo_is_checkout_scoped_test`,
  `local_branch_disposal_invalidates_only_its_revertibles_test`.
  Confirm one-shot factories, default/undo/redo kinds, repeated revert without
  disposal, constraint outcomes, and the Task 1 settlement contract.

  Add `local_branch_transaction_abort_preserves_main_callback_edit_test` and
  `local_branch_transaction_commit_preserves_main_callback_edit_test`.
  In a fork transaction, edit main through its own handle, then abort or commit
  the fork transaction. Require the main edit, its revision, event, and
  publication to survive both outcomes. Add the reverse main-to-fork case and
  a sibling-fork case; those independent local edits must not submit tree
  operations. Each transaction owns only its selected checkout. Do not turn
  fork edits into ordinary document pending entries or roll back allocator
  reservations when the owning transaction aborts.

- [ ] **Step 4: Verify the coupled allocation/undo suites.**

  ```bash
  rtk proxy gleam test --target erlang -- shared_tree_branch shared_tree_identifier shared_tree_transaction shared_tree_undo
  rtk proxy gleam test --target javascript -- shared_tree_branch shared_tree_identifier shared_tree_transaction shared_tree_undo
  ```

  Suggested authorized commit: `feat(tree): author branch edits with shared identity`.

### Task 5: Integrate checkout selection into runtime-core

**Files:** Modify `runtime_core.gleam`, `tree/branch.gleam`,
`channel.gleam` only for internal event scope; extend
`shared_tree_runtime_test.gleam` and branch tests.

**Consumes:** Tasks 2-4 pure operations and Task 1 finalized event contract.
**Produces:** Concrete runtime-core interfaces from section 3, checkout-aware
read/edit/transaction/undo routing, and normal wire publication on main merge.

- [ ] **Step 1: Add core isolation and merge-submission RED.**

  Require branch edits to change only the branch. Merge into main must emit the
  captured surviving commits and allocations, in the captured boundaries.
  Merging into another local checkout emits no tree operation.

- [ ] **Step 2: Add the registry and central selector resolution.**

  Keep branch state out of `Core.channels` and document summaries. Resolve
  `DocumentCheckout` through the existing channel and local IDs through the
  registry. Preserve origin checks and ready-phase behavior.

  ```text
  resolve checkout -> checked state
  run pure operation -> candidate state/compressor/events
  install candidate -> scope events to checkout
  if target is main -> existing submit_tree_commits path
  otherwise -> no tree outbound operations
  ```

  Inventory all tree entry points with code-map plus scoped search, including
  path resolution, maps/arrays/moves, compatibility, transactions, subscribers,
  history diagnostics, settlement routing, and revertible status/disposal.
  Document-only wrappers must select main; there is no silent fallback from a
  missing branch ID to the document checkout.

- [ ] **Step 3: Add atomicity and scope refusal REDs.**

  Snapshot core, registry, compressor, events, and outbound queue before an
  invalid merge/rebase; assert all are identical after failure. Refuse branch
  schema authoring. Cross-selector transaction callback edits use the selected
  checkout's normal path and commit independently. On transaction completion,
  install only its owning checkout's candidate; preserve the current registry,
  shared compressor, scoped events, and outbound queue from independent edits.
  Verify main callback edits submit ordinary document operations exactly once,
  while sibling-fork callback edits submit no tree operation. Verify existing
  main operations still use the original routing envelope.

- [ ] **Step 4: Verify core and recovery compatibility.**

  ```bash
  rtk proxy gleam test --target erlang -- shared_tree_branch shared_tree_runtime shared_tree_transaction shared_tree_history_resubmit
  rtk proxy gleam test --target javascript -- shared_tree_branch shared_tree_runtime shared_tree_transaction shared_tree_history_resubmit
  ```

  Suggested authorized commit: `feat(tree): route runtime operations by checkout`.

### Task 6: Expose JavaScript branch handles through existing field APIs

**Files:** Modify `src/watershed/runtime.gleam`, `src/watershed.gleam`;
extend `shared_tree_runtime_js_test.gleam`, map/array facade tests, branch tests.

**Consumes:** Task 5 core interfaces and scoped events.
**Produces:** Section 3 public lifecycle functions, selector-bearing opaque
`SharedTree`/revertible handles, and JS event delivery/cleanup.

- [ ] **Step 1: Add facade RED for fork/edit/rebase/merge.**

  ```text
  main = resolve existing tree
  fork = tree_fork(main)
  edit fork through existing object/map/array APIs
  assert main unchanged
  tree_rebase_onto(fork, main)
  tree_merge(main, fork, True)
  assert fork status BranchDisposed and main contains the merged edit
  ```

  Add callback counters asserting main subscribers never receive an isolated
  fork edit and branch subscribers never receive an unreconciled remote edit.
  Run the Task 4 independent callback-edit cases through real JavaScript
  handles; verify owning-checkout rollback leaves the other edit and its
  notification intact.

- [ ] **Step 2: Carry the selector through every tree runtime call.**

  Extend private handles without exposing numeric IDs. Validate both runtime
  identities before invoking the core. Use the existing synchronous event
  boundary and one-shot acquisition cells, now keyed by checkout. Do not
  route subscriptions with made-up address suffixes.

- [ ] **Step 3: Add JS lifetime and reentrancy tests.**

  Retain main and branch handles, dispose one fork, and require main handles
  to remain valid. Test nested fork lifetime, preserved-source merge,
  unsubscribe, close, double disposal, late factory calls, callback exceptions,
  and queued application undo messages. A callback must not replace the state
  returned by merge/rebase with a stale cell snapshot.

- [ ] **Step 4: Verify JavaScript facade regressions.**

  ```bash
  rtk proxy gleam test --target javascript -- shared_tree_branch shared_tree_runtime_js shared_tree_array_facade shared_tree_map_facade shared_tree_creation_api shared_tree_transaction
  ```

  Suggested authorized commit: `feat(tree): expose JavaScript local branches`.

### Task 7: Expose matching BEAM branch handles and actor delivery

**Files:** Modify `runtime_beam.gleam`, `watershed_beam.gleam`;
extend `shared_tree_runtime_beam_test.gleam`, facade and branch tests.

**Consumes:** Task 5 contracts; same public surface as Task 6.
**Produces:** BEAM actor messages, checkout-scoped subscribers/revertibles,
cleanup, and matching facade semantics.

- [ ] **Step 1: Add actor/facade RED for the same lifecycle.**

  Use a native BEAM runtime and real synchronous calls, not a JS adapter.
  Assert main isolation, nested fork, explicit rebase, merge/disposal,
  active-transaction lifecycle refusal, independent cross-checkout callback
  edits surviving commit and rollback, and main/branch subscription separation.

- [ ] **Step 2: Add checkout-bearing actor requests.**

  ```text
  ForkTree(address, selector, view, reply)
  RebaseTreeOnto(address, source, target, reply)
  MergeTree(address, target, source, dispose_source, reply)
  TreeBranchStatus(address, selector, reply)
  DisposeTreeBranch(address, selector, reply)
  ```

  Existing edit/read/transaction/revert/subscription requests carry selectors.
  Both source and target must be validated in the receiving actor. During
  monitored commit/settlement callback delivery, service only the permitted
  event-scoped factory and settlement requests; replay deferred work in order
  afterward. During transaction callback execution, service independent edits
  to other related live checkouts without deadlock and retain their state when
  installing the owning checkout's transaction result.

- [ ] **Step 3: Add BEAM-specific lifetime tests.**

  Cover caller exit during factory delivery, runtime shutdown, unsubscribe,
  disposed branch requests, callback failure, reentrant operations, and two
  subscribers competing for one factory. Descendant pins and main revertibles
  remain independent of the disposed parent's actor bookkeeping.

- [ ] **Step 4: Verify BEAM and facade parity.**

  ```bash
  rtk proxy gleam test --target erlang -- shared_tree_branch shared_tree_runtime_beam shared_tree_array_facade shared_tree_map_facade shared_tree_creation_api shared_tree_transaction facade_parity
  ```

  Suggested authorized commit: `feat(tree): expose BEAM local branches`.

### Task 8: Close the native corpus, retention, recovery, and summary matrix

**Files:** Create `test/watershed/tree/branch_fixture.gleam`; modify
`test/watershed/shared_tree_fixture_test.gleam`;
branch, history, summary, runtime, transaction, and Identifier tests.
Register native coverage in the oracle generator only after passing it.

**Consumes:** Public APIs and the complete Task 1 corpus.
**Produces:** Full dual-target branch runner and lifecycle/persistence evidence.

- [ ] **Step 1: Add input-only corpus runner RED.**

  ```gleam
  pub fn local_branch_merge_matches_pinned_observations_test() {
    fixtures.assert_case("local-branch-merge", fn(input) {
      branch_fixture.run("local-branch-merge", input)
    })
  }
  ```

  Define `branch_fixture.run(name: String, input: Json) -> Result(Json, String)`.
  Expected observations belong only to the test assertion side. Never consume
  fixture `raw` or `expected` while running native scenarios. If a semantic
  projection is necessary, normalize both sides under a reviewed contract and
  require every observation/field row, rather than selecting easy cases.

- [ ] **Step 2: Implement each of the eight runner groups.**

  Drive real pure or public operations as specified by Task 1. Assert revisions,
  encoded changes, snapshots, node IDs, allocator state, events, handles,
  transaction constraints, and source/target lifetime. Require both targets
  and all rows before updating `nativeSemanticRunners`.

- [ ] **Step 3: Add recovery and retention tests incrementally.**

  Required tests:
  `local_branch_msn_preserves_fork_and_revertible_repair_test`,
  `local_branch_reconnect_preserves_pending_origin_test`,
  `local_branch_merge_accepted_before_drop_is_not_duplicated_test`,
  `local_branch_unmerged_changes_do_not_enter_summary_test`,
  `local_branch_reloaded_summary_has_no_old_checkout_test`.

  Take summaries with live unmerged branches and pending merges. Verify only
  sequenced main state is present, then apply the tail and continue editing.
  Dispose one of several branches and advance MSN; prove only unreferenced
  ancestry/repair data can trim.

- [ ] **Step 4: Run the native acceptance gates.**

  ```bash
  rtk proxy just shared-tree-test
  rtk proxy just shared-tree-codec-interop
  ```

  Suggested authorized commit: `test(tree): prove native local branch lifecycle`.

### Task 9: Prove local-branch merges through pinned Floodgate

**Files:** Modify `tools/shared-tree-oracle/client-driver.mjs` and tests,
`interop-scenarios.mjs`, `client-interop.mjs`, `summary-interop.mjs`,
`interop.mjs`, `service.mjs` and their tests; reuse the schemas in `schema.mjs`;
modify native client protocol/drivers.

**Consumes:** Task 1 upstream branches, Tasks 6-8 native branches, existing
coordinator/raw artifact validation.
**Produces:** Mandatory branch sections, mixed-client schedules, and summary
writer/reader evidence tied to actual native I/O.

- [ ] **Step 1: Add command protocol RED for actual client-owned branches.**

  ```json
  {"op":"fork","source":"main","name":"draft"}
  {"op":"branchEdit","branch":"draft","edit":{"kind":"object-set","value":"draft"}}
  {"op":"rebaseBranch","source":"draft","target":"main"}
  {"op":"mergeBranch","target":"main","source":"draft","dispose":true}
  {"op":"disposeBranch","name":"draft"}
  ```

  Add branch retain/revert commands using the existing handle protocol.
  Name lookup is client-local; coordinators must not simulate checkouts,
  generate changesets, or supply native IDs.

- [ ] **Step 2: Require complete branch report sections with mutation REDs.**

  ```javascript
  const requiredLocalBranchSections = [
    "localBranchIsolation",
    "localBranchConcurrent",
    "localBranchLifetime",
    "localBranchReconnect",
    "localBranchReloadMatrix",
  ];
  ```

  Reject missing sections, target, field row, order, source/target trace,
  allocation, exact merge message, factory outcome, settlement observation
  required by the captured contract, service identity, or continuation cell.
  Derive report rows from raw evidence, not coordinators' asserted booleans.

- [ ] **Step 3: Run deterministic pair scenarios.**

  Pair upstream/JS, upstream/BEAM, JS/BEAM. For each supported field kind and
  transaction: A forks and edits; B edits main; A rebases or directly merges.
  Run unrelated and overlapping edits in both orders, preserved-source repeated
  merge, and branch undo before merge. Require no remote visibility before
  merge and exact surviving revisions afterward.

- [ ] **Step 4: Prove reconnect and persistence.**

  Reconnect each native writer with live branches and a pending-main origin.
  For writers upstream/JS/BEAM, summarize before merge and after merge; each
  upstream/JS/BEAM reader reloads and continues editing. This is 18 required
  writer/reader-stage cells. All readers have no historical local branches.
  Include merged undo/redo continuation and accepted-before-drop deduplication.

- [ ] **Step 5: Extend the existing seeded schedule and run gates.**

  Add fork, edit, nested fork, rebase, merge, disposal, branch undo/redo, and
  summary actions. Retain branch names, ancestry, commit kinds, ranges, and
  event trace in failure artifacts. Keep 300 schedules and seed 42:

  ```bash
  rtk proxy node --test tools/shared-tree-oracle/client-driver.test.mjs tools/shared-tree-oracle/client-interop.test.mjs tools/shared-tree-oracle/summary-interop.test.mjs tools/shared-tree-oracle/interop.test.mjs tools/shared-tree-oracle/service.test.mjs
  rtk proxy just shared-tree-interop
  rtk proxy just shared-tree-create-interop
  ```

  No skipped targets/service or proxy coordinator success. Suggested authorized
  commit: `test(tree): prove local branch merge interoperability`.

### Task 10: Publish the local M6 profile and permanent gates

**Files:** Modify `generate.mjs`, `service.mjs`, `interop.mjs`, their tests,
`gates.test.mjs`; generate fixture profile/manifest; update both READMEs,
parent roadmap, this plan, `.github/workflows/shared-tree.yml`,
`.github/workflows/shared-tree-interop.yml`, and `justfile` only if required.

**Consumes:** Complete native and real-service evidence.
**Produces:** Accurate supported local-branch contract and permanent enforcement.

- [ ] **Step 1: Add failing profile/gate assertions.**

  Require feature labels:

  ```text
  runtime-local-checkouts
  local-fork-rebase-merge
  checkout-scoped-transactions-and-revertibles
  branch-and-revertible-history-retention
  local-branch-reconnect
  merged-branch-summary-continuation
  ```

  Require all eight corpus IDs and both full native runners. Reject stale
  generated digests or report omissions. Keep shared/persisted branches,
  branch wire APIs, branch schema authoring, cross-runtime merge, portable
  handles, and historical checkout explicitly unsupported.

- [ ] **Step 2: Generate metadata and run validator gates.**

  ```bash
  rtk proxy npm --prefix tools/shared-tree-oracle run generate
  rtk proxy npm --prefix tools/shared-tree-oracle run check
  rtk proxy npm --prefix tools/shared-tree-oracle test
  ```

- [ ] **Step 3: Document the public lifecycle and resource contract.**

  Show a fork edited through existing APIs, an explicit rebase, merge with
  disposal, preserved-source merge, and disposal on a failed workflow. Include
  branch-local application-owned undo stacks and the verified settlement
  semantics. Explain memory pins, ready-phase rules, reconnect, schema
  divergence, and reload loss without promising disk recovery.

- [ ] **Step 4: Wire the existing workflow gates and roadmap.**

  Keep native checks on PR/main and real-service acceptance manual. Do not
  trigger a hosted workflow without user authorization. Publish only the local
  M6 slice and link this design/plan; shared branches remain a separate scope.
  Suggested authorized commit: `docs(tree): publish local branching profile`.

### Task 11: Run full regression closure and reconcile acceptance

**Files:** Fix only regressions caused by M6; record evidence in this plan and
the parent roadmap. Do not create an empty implementation closure commit.

**Consumes:** Tasks 1-10 and their named acceptance evidence.
**Produces:** Honest M6 status, pinned report IDs, and any remaining blockers.

- [ ] **Step 1: Run formatting, oracle, native, and codec gates.**

  ```bash
  rtk proxy gleam format --check src test
  rtk proxy npm --prefix tools/shared-tree-oracle run check
  rtk proxy npm --prefix tools/shared-tree-oracle test
  rtk proxy just shared-tree-test
  rtk proxy just shared-tree-codec-interop
  ```

- [ ] **Step 2: Run service, creation, repository, and browser gates.**

  ```bash
  rtk proxy just shared-tree-interop
  rtk proxy just shared-tree-create-interop
  rtk proxy just test
  rtk proxy just build
  rtk proxy just lint
  rtk proxy just shared-tree-checklist
  ```

  Investigate each failure against the unchanged execution baseline. A previous
  baseline report does not substitute for reproduction. Do not waive the
  registry-policy limitation or conflate website browser coverage with the
  standalone SharedTree gate.

- [ ] **Step 3: Audit section 5 against named tests and raw reports.**

  Record native test names, targets, source digests, service/version identity,
  scenario coverage, 18 reload cells, seed/schedule counts, and report IDs.
  Mark implementation and release acceptance separately when blocked.

- [ ] **Step 4: Review and commit only authorized regression fixes/docs.**

  Confirm no private branch state entered wire/summaries, no new production
  Fluid dependency, no unrelated changes, and no M7/M8 claim. Suggested
  authorized documentation commit: `docs(tree): record local branch acceptance`.

## 5. Acceptance matrix

Every row requires evidence; unchecked means not yet accepted.

| Contract | Owning tasks | Accepted |
| --- | --- | --- |
| Pinned executable behavior, comment discrepancies, raw/normalized separation | 1 | [ ] |
| Isolated document forks and nested local forks, stable node/Identifier identity | 2-4, 8 | [ ] |
| Explicit rebase changes source only; main receives no implicit branch edits | 3, 5-9 | [ ] |
| Object/map/array/move/transaction merge and both conflict orders | 3-4, 8-9 | [ ] |
| Shared revisions deduplicate, preserved-source and repeated merges match oracle | 1-3, 8-9 | [ ] |
| Shared allocator, abandoned ranges, allocation-before-use, no branch tree traffic | 1, 4-5, 8-9 | [ ] |
| Checkout-scoped transactions, factories, undo/redo, and truthful settlement | 1, 4-8 | [ ] |
| Atomic origin/lifetime/schema/transaction refusal; no main rebase | 3-7 | [ ] |
| Descendant lifetime and independent branch/revertible retention beyond MSN | 1-2, 8 | [ ] |
| JS/BEAM matching facade and callback/actor cleanup | 6-8 | [ ] |
| In-process reconnect, pending-main origin, accepted-before-drop deduplication | 5, 8-9 | [ ] |
| Unmerged data absent from summaries; 18 reload cells continue without old branches | 8-9 | [ ] |
| Mandatory source/native/service/report coverage and permanent profile gates | 9-10 | [ ] |
| Existing M1-M5 and creation intact; full build and standalone browser accepted | 11 | [ ] |
| No shared branches, branch codecs, portable handles, or broader milestone claims | 1, 10-11 | [ ] |

## 6. Stop conditions

Stop and revise the spec/plan when:

- The pinned local behavior requires a package, codec, service, or summary-format
  change.
- Merge event/settlement behavior cannot fit the approved checkout-scoped
  subscription contract without a public behavior decision.
- The ancestry implementation would need a second changeset/rebase engine or
  would discard required common-revision/repair information.
- Cross-checkout allocation cannot preserve existing Identifier and abort
  behavior under one document compressor.
- Native corpus parity requires expected-output copying or upstream private
  storage simulation.
- A live fork or revertible loses ancestry/repair state under trimming,
  reconnect, parent disposal, or summary generation.

Bring the executable evidence to the user. Do not expand M6 scope, weaken
validators, or check acceptance boxes to get past a stop condition.
