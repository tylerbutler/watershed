# Task 10 report: publish the local M6 profile and permanent gates

**Status:** DONE_WITH_CONCERNS

## Implementation

- Published the six required runtime-local branch support labels.
- Published explicit exclusions for shared and persisted branches, branch wire
  APIs, branch schema authoring, cross-runtime or cross-tree merge, portable
  branch handles and revertibles, and historical checkouts.
- Registered all eight `local-branch-*` corpus cases in both JavaScript and
  Erlang native semantic runner inventories.
- Added a branch manifest contract that requires the five complete Task 9
  service sections, both native targets, seed 42, and 300 schedules.
- Updated the pinned profile digest to
  `51a465c9e685197b578eaa1a53cea84aa2da955da1000855fa5214534fb84608`.
- Added permanent committed-artifact and workflow-label gates.
- Documented fork/edit/rebase/merge, disposal and preserved-source merge,
  best-effort cleanup, application-owned branch undo with queued dispatch,
  settlement, memory pins, ready/reconnect behavior, schema refusal, and fresh
  reload loss.
- Updated the local branching spec, plan, parent roadmap, and workflow labels.
  Task 11 remains open. No hosted workflow was dispatched.

The parent-owned lockfile-only repair `a77cb140` is in the review range but is
not part of the Task 10 staged files or Task 10 commits.

## TDD RED/GREEN record

1. **Support and exclusion labels**
   - RED:
     `node --test --test-name-pattern='service profile publishes the local M6 branch boundary' tools/shared-tree-oracle/service.test.mjs`
   - Result: failed at module load because `branchExcludedFeatures` was not
     exported.
   - GREEN: same command passed, 1/1.

2. **Complete branch manifest and native runners**
   - RED:
     `node --test --test-name-pattern='manifest records complete native runners and actual wire field kinds' tools/shared-tree-oracle/generate.test.mjs`
   - Result: failed because `branchContract` still said no native runner was
     registered and lacked support, exclusion, and service-report metadata.
   - GREEN: same command passed, 1/1, after registering all eight cases on both
     targets and publishing the service contract.

3. **Committed generated artifacts**
   - RED:
     `node --test --test-name-pattern='committed profile and corpus publish the complete local branch contract' tools/shared-tree-oracle/gates.test.mjs`
   - Result: failed because the committed profile had none of the six labels.
   - GREEN: after oracle generation, the same command passed, 1/1.

4. **Stale profile digest**
   - RED:
     `node --test --test-name-pattern='the committed profile is hashed and every compatibility pin is validated' tools/shared-tree-oracle/interop.test.mjs`
   - Result: rejected the new committed bytes: actual digest
     `51a465c9...fb84608`, expected `df753f54...aae9c68`.
   - GREEN: after updating the pinned digest and exact profile expectations,
     the same command passed, 1/1.

5. **Workflow publication labels**
   - RED:
     `node --test --test-name-pattern='hosted erlang gates install the configured rebar tool' tools/shared-tree-oracle/gates.test.mjs`
   - Result: rejected the old M5 workflow labels.
   - GREEN: after changing labels only, with triggers unchanged, the same
     command passed, 1/1.

## Verification

- Focused publication tests: 4 passed, 0 failed.
- Focused interoperability publication tests: 2 passed, 0 failed.
- `npm --prefix tools/shared-tree-oracle run generate`: generated 63 cases.
- `npm --prefix tools/shared-tree-oracle run check`: verified 63 cases.
- Full `npm --prefix tools/shared-tree-oracle test`:
  - First run: 529 passed, 1 failed. The failure was a stale Task 5 exclusion
    expectation for `public-local-branch-apis`.
  - After removing that obsolete expectation, the focused profile tests passed
    2/2.
  - Final full run: **530 passed, 0 failed, 0 skipped**.
- Generated JSON parsed successfully. The committed profile SHA-256 is
  `51a465c9e685197b578eaa1a53cea84aa2da955da1000855fa5214534fb84608`.
- `git diff --check` passed.

The parent independently reported that, after `a77cb140`, `just build` passed
all Gleam families and all 18 bundles, and `just shared-tree-checklist` passed
with installed Chromium and pinned Floodgate. Those are Task 11 evidence, not
Task 10 verification.

## Files

- `.github/workflows/shared-tree.yml`
- `.github/workflows/shared-tree-interop.yml`
- `README.md`
- `docs/superpowers/plans/2026-09-21-shared-tree.md`
- `docs/superpowers/plans/2026-10-05-shared-tree-local-branching.md`
- `docs/superpowers/specs/2026-10-05-shared-tree-local-branching-design.md`
- `test/fixtures/shared_tree/manifest.json`
- `test/fixtures/shared_tree/profile.json`
- `tools/shared-tree-oracle/README.md`
- `tools/shared-tree-oracle/gates.test.mjs`
- `tools/shared-tree-oracle/generate.mjs`
- `tools/shared-tree-oracle/generate.test.mjs`
- `tools/shared-tree-oracle/interop.mjs`
- `tools/shared-tree-oracle/interop.test.mjs`
- `tools/shared-tree-oracle/service.mjs`
- `tools/shared-tree-oracle/service.test.mjs`

## Self-review

- Confirmed all exact pinned versions, codec versions, bootstrap/tree layout,
  and `minVersionForCollab` remain unchanged.
- Confirmed no dependency manifest, Task 10-unrelated lockfile, apm-managed
  file, `.code-map` file, production Gleam module, example source, or
  `progress.md` was changed.
- Confirmed workflow trigger policy is unchanged: native PR/main plus manual
  dispatch; service interoperability remains manual only.
- Confirmed the docs do not promise persisted branches, disk recovery,
  offline authoring, managed undo stacks, schema authoring, or portable
  handles.
- Confirmed Task 11 remains open and Task 10 does not claim M6 release closure.

## Concerns

The parent found one M6-caused, out-of-Task-10 JavaScript regression:
`unsubscribe_of_another_subscriber_keeps_the_current_snapshot_test`. The
checkout-aware subscriber guard currently changes non-tree SharedMap snapshot
delivery, while tree and commit subscriptions intentionally cancel a later
callback after unsubscription. The unchanged execution base reproduces the
narrow test failure only after the M6 production commit. Task 11 owns the
targeted production fix and full regression closure. Task 10 profile and oracle
gates are green and do not waive this issue.
