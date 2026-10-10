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

## FIX ROUND1

**Review base:** `5b5efc58`

### Findings addressed

1. **The README fork/edit example used a nonexistent API.**
   Replaced both `result.then` calls with `result.try`.

2. **The preserved-source example leaked a checkout on error.**
   Wrapped every post-fork operation in one result pipeline. Any error now
   attempts `tree_dispose_branch(draft)` and returns the original workflow
   error even if cleanup also fails. The successful preserved-source path still
   merges with `dispose_source: False`, continues editing, rebases, and finishes
   with a disposing merge.

3. **Branch evidence was not bound to the accepted run or profile.**
   Every one of the five branch sections now records the current run ID and
   profile digest. Every branch row writes a verified `local-branch` artifact
   containing the complete captured row, including raw client, service,
   transport, storage, and continuation evidence. The final validator requires
   those artifacts, verifies their run, digest, kind, subject, and document
   scope, and compares the report row with the immutable captured artifact.
   `artifactReferences` now includes every branch-row artifact.

### TDD RED/GREEN

#### README public examples

Added a permanent gate that extracts both Gleam blocks from the README local
branch section, writes them as a temporary module in the existing compiled
`tools/website-samples` package, and runs the Gleam compiler against the live
public Watershed API.

RED command:

```text
node --test --test-name-pattern='README local branch examples compile' tools/shared-tree-oracle/gates.test.mjs
```

Correct RED:

```text
error: Unknown module value
result.then
The module `gleam/result` does not have a `then` value.
tests 1, pass 0, fail 1
```

GREEN after the README fixes:

```text
tests 1, pass 1, fail 0
```

The complete permanent gate file then passed:

```text
node --test tools/shared-tree-oracle/gates.test.mjs
tests 10, pass 10, fail 0
```

#### Current-run, current-profile artifact binding

Added behavior-specific mutations for:

- each of the five branch sections copied from another run;
- each section copied with another profile digest;
- missing artifacts in each section;
- verified branch artifact claims carrying a prior run ID;
- verified branch artifact claims carrying a prior profile digest.

RED command:

```text
node --test --test-name-pattern='branch sections reject copied|branch sections require verified' tools/shared-tree-oracle/interop.test.mjs
```

Correct RED:

```text
branch sections reject copied prior-run and prior-profile evidence:
Missing expected exception
branch sections require verified captured artifacts:
Missing expected exception
tests 2, pass 0, fail 2
```

GREEN commands and results:

```text
node --test --test-name-pattern='a complete current-run report|branch sections reject copied|branch sections require verified|branch artifacts reject' tools/shared-tree-oracle/interop.test.mjs
tests 4, pass 4, fail 0

node --test --test-name-pattern='local branch|branch sections|branch artifacts|complete current-run' tools/shared-tree-oracle/interop.test.mjs
tests 24, pass 24, fail 0

node --test --test-name-pattern='kind source artifacts|artifact evidence|artifact coordinator|branch sections|branch artifacts|complete current-run' tools/shared-tree-oracle/interop.test.mjs
tests 6, pass 6, fail 0
```

### Final verification

```text
npm --prefix tools/shared-tree-oracle run check
Verified 63 upstream SharedTree cases

npm --prefix tools/shared-tree-oracle test
tests 534, pass 534, fail 0, skipped 0
```

`git diff --check` passed for both committed chunks.

### Fix commits

- `48739310` — `docs(tree): fix local branch examples`
- `d4c0194a` — `test(tree): bind branch reports to artifacts`

The concurrent Task 11 runtime fix `b2e10a17` is not part of these staged
changes. No Task 11 implementation, final acceptance documentation, schema,
codec, profile-version, dependency, or lockfile change was made in this round.

### Round 1 concerns

None in Task 10 scope. Task 11 still owns final repository and release
acceptance.
