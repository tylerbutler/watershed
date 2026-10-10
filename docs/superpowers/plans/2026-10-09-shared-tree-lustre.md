# SharedTree Lustre Consumer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development`
> or `executing-plans` task-by-task. Historical completion records are not tasks
> to restart. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add safe SharedTree transaction and commit/revertible effects and a
browser example with application-owned undo/redo.

**Architecture:** The existing Lustre adapter wraps native APIs and queues
messages through microtasks. It acquires callback-only factories synchronously.
The checklist owns its stacks and composes bulk edits through native
transactions; the tree kernel and container profile do not change.

**Tech Stack:** JavaScript-target Gleam, Lustre, gleeunit, native runtime/sluice
test seams, existing Node tests and two-context Chromium gate.

**Spec:** [Approved Lustre design](../specs/2026-10-09-shared-tree-lustre-design.md).

## Global Constraints

- Preserve pure Gleam SharedTree semantics on JavaScript and BEAM.
- Keep Fluid 3.1.0, source `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960`,
  Floodgate `0eb493fc46d1bb9baf1151a6ccdde93544e057e7`, and
  `minVersionForCollab` `2.117.0`.
- Keep Message V7, SharedTreeChange V5, ModularChange V5, and Schema V2.
- Keep the existing fixed bootstrap-map/tree container layout.
- Preserve existing adapter APIs, DDS behavior, and M1-M6 contracts.
- No production Fluid SDK dependency, new package dependency, or lockfile change.
- All adapter work starts at effect execution. Every message constructor and
  dispatch runs in a microtask, not inside a native callback or Lustre update.
- Acquire a native one-shot revertible factory before its callback returns.
- Preserve typed transaction results and explicit acquisition, registration,
  reversion, and disposal errors.
- Applications own stacks and retained handles; no package-owned undo stack.
- Apply ASD-STE100 to Gleam comments/error strings, not Markdown prose.
- Do not edit generated fixtures, `.code-map/`, or apm-managed files.

## Execution

Baseline: clean `main` at `69d1fa0f`. The user explicitly authorized in-place
implementation and incremental commits without attribution trailers. Approval
covers the design and the written spec/plan; do not add routine approval gates.
Do not push or dispatch hosted workflows.

Tasks are ordered: Task 2 consumes Task 1's exact interfaces. One implementation
owner works at a time. Keep test-first cycles small and record RED/GREEN
commands and output. Run the package suite once at each commit boundary.
Prefer existing fixtures and transport seams; no production test-only hooks.

## File map

| Files | Responsibility |
| --- | --- |
| `watershed_lustre/src/watershed_lustre/tree.gleam` | Effects and safe captured commit type |
| `watershed_lustre/test/watershed_lustre/tree_test.gleam` | Real-runtime scheduling, transactions, commit lifetime and lifecycle |
| `watershed_lustre/README.md` | Public effect signatures, ownership and queued-message lifetime |
| `examples/shared_tree_checklist_lustre/src/shared_tree_checklist_lustre.gleam` | UI integration, model-owned stacks, cleanup and bulk transaction |
| `examples/shared_tree_checklist_lustre/src/shared_tree_checklist_lustre/history.gleam` | Small application-specific history reducer, if extraction is needed |
| Checklist Gleam tests and `smoke/browser.mjs` | Stack behavior and full browser acceptance |
| Checklist README and root `README.md` | Example operation and accurate M7 scope |
| Parent roadmap and this plan | Current scope and dated local evidence |

### Task 1: Add safe effects and adapter lifecycle tests

**Files:** Modify the adapter, its `tree_test.gleam`, and the Lustre README
from the file map. A test helper under `watershed_lustre/test/` is permitted
only if required to reuse the native runtime seam.

**Consumes:** `watershed.tree_transaction`, `subscribe_tree_commits`,
`tree_revert`, `tree_dispose_revertible`, `unsubscribe`, and native
`TreeCommitEvent`, `TreeTransactionError`, and outcome types.

**Produces:** Exactly `CommitEvent`, `transaction`, `subscribe_commits`,
`revert`, and `dispose_revertible` with signatures in the spec. Existing
`unsubscribe` handles returned commit tokens. Task 2 must not invent another
factory-lifetime wrapper.

- [ ] Add a failing transaction laziness test with a cell counting callback
  executions. Construct the effect and assert zero executions. Perform it
  and assert one execution but no synchronous message; after a microtask assert
  the typed result. Run `cd watershed_lustre && gleam test`.
- [ ] Implement the transaction wrapper at the effect boundary:

  ```gleam
  use dispatch <- effect.from
  let outcome = watershed.tree_transaction(tree, constraints, callback)
  queue_microtask(fn() { dispatch(completed(outcome)) })
  ```

  Rerun, then add/verify abort rollback, generic success value and callback error,
  invalid constraint, and one composed outer commit for two real edits.
- [ ] Add a failing real-runtime subscription test: construct but do not run
  `subscribe_commits`, edit, and assert no messages. Run the effect, edit again,
  assert no synchronous constructors or dispatch, flush and assert
  `Ok(CommitEvent(DefaultCommit, True, Some(handle)))` with a valid handle.
  This detects a factory incorrectly deferred beyond its native callback.
- [ ] Implement immediate factory acquisition and deferred safe records.
  Queue the captured commit before registering settlement. Deliver acquisition
  errors through `committed` and registration errors through `settled`.
  Test actual default/undo/redo, remote commits without local handles,
  settlement, no factory for schema events, and unsubscribe.
- [ ] Add failing revert/disposal laziness tests using a real retained handle.
  Construct each effect, assert unchanged tree/handle status; perform it and
  assert the mutation/status change with no synchronous messages; flush and
  assert `Ok(Nil)`. Implement these thunks and test disposed-handle errors:

  ```gleam
  perform(fn() { watershed.tree_revert(revertible, dispose) }, completed)
  perform(fn() { watershed.tree_dispose_revertible(revertible) }, completed)
  ```

- [ ] Cover previously missing `open`, `read_root`, `subscribe`, `unsubscribe`
  scheduling/lifecycle with the same native fixture. Document that already
  queued messages can arrive after unsubscribe, close disposes handles, and
  the app owns disposal/stack state.
- [ ] Run `cd watershed_lustre && gleam test` and
  `gleam format --check watershed_lustre/src watershed_lustre/test`.
  Commit the focused deliverable as `feat(lustre): bind tree undo and transactions`.

### Task 2: Integrate application-owned history and prove it in browsers

**Files:** Modify checklist app, its Gleam tests, browser smoke and README,
root README and parent roadmap from the file map. Create the small checklist
`history.gleam` only if needed for a directly testable reducer; it is not a
package-level undo manager.

**Consumes:** Task 1's exact effects and `CommitEvent` type, native status
queries, latest `tree_get` snapshots, checklist decode/edit functions, and
existing browser CDP helpers.

**Produces:** A runnable example with complete application-owned history and
current local acceptance evidence. M7 remains explicitly partial.

- [ ] Add a failing history test for the routing invariant:

  ```text
  default A -> undo [A], redo []
  undo B    -> undo [A], redo [B]
  redo C    -> undo [C, A], redo [B]
  default D -> undo [D, C, A], redo [], dispose [B]
  remote    -> no stack change
  ```

  Drive real handles where required; pure reducer tests may use generic
  entries if the application reducer is generic. Run
  `cd examples/shared_tree_checklist_lustre && gleam test`.
- [ ] Subscribe to commits when the tree opens, retain both subscription
  tokens, route local kinds into model-owned stacks and dispose cleared redo
  entries. Add Undo, Redo and Clear history controls; show stack counts.
  Gate history actions during outstanding local work. Keep failed revert
  entries rather than popping them on the optimistic request:

  ```text
  request -> mark in progress, run tree.revert(handle, True, ...)
  Ok      -> remove consumed handle, keep emitted inverse on opposite stack
  Error   -> keep original stack entry, display error, clear in-progress
  ```

  Cover redo invalidation, disposed-handle pruning, empty actions, failed
  acquisition/settlement paths, clearing and late captured handles after close.
- [ ] Add a failing bulk-action test: latest snapshot with two incomplete
  items yields one outer commit and one undo restores both. Implement
  Complete all with `tree.transaction`; read/decode the latest tree in its
  callback, set only false completion fields, preserve all other fields.
  An all-complete snapshot authors no commit. Surface abort/runtime errors
  instead of mapping them to success.
- [ ] Add Close: unsubscribe both tokens, dispose both lists, close the native
  document, clear history and disable edits. Keep cleanup errors visible.
  Reload must recover document data but start with empty local stacks.
- [ ] Extend `smoke/browser.mjs` with assertions for move-up, bulk completion,
  one-step undo/redo, peer text-edit preservation during local undo,
  redo invalidation after a new local edit, clear-history without data
  mutation, close, and reload with empty stacks. Continue checking item IDs,
  exact values/order, errors and drained pending work in both contexts.
  Preserve existing race and CRUD coverage; no skipped run is acceptance.
- [ ] Run the focused package/Node tests, build and browser gate:

  ```sh
  cd examples/shared_tree_checklist_lustre && gleam test
  node --test examples/shared_tree_checklist_lustre/test/*.test.mjs
  cd examples/shared_tree_checklist_lustre && pnpm run build
  just shared-tree-checklist
  ```

  Reuse an existing compatible loopback Floodgate if one is running. If the
  gate lacks its service, use the repository's owned pinned local-service
  mechanism; do not kill or reconfigure another user's process. Record the
  actual browser run and errors, not just a command's skipped-success exit.
- [ ] Update the three related READMEs/roadmap with the implemented consumer
  slice and its limits. Commit verified app chunks as
  `feat(checklist): add local undo and bulk completion`.
- [ ] Run combined release coverage:

  ```sh
  cd watershed_lustre && gleam test
  cd examples/shared_tree_checklist_lustre && gleam test
  gleam format --check watershed_lustre/src watershed_lustre/test \
    examples/shared_tree_checklist_lustre/src \
    examples/shared_tree_checklist_lustre/test
  node --test examples/shared_tree_checklist_lustre/test/*.test.mjs
  just shared-tree-checklist
  ```

  These consumer-only changes do not require a new service interop profile or
  a repeated M6 300-schedule matrix. Run broader tests only if a change reaches
  shared runtime code or focused evidence reveals a regression.
  Record dated commands/results and completion in this plan after review.

## Acceptance record

Implementation evidence will be recorded here after the two tasks and their
reviews. Initial adapter baseline: `cd watershed_lustre && gleam test`,
89 passed with no failures on `69d1fa0f`.
