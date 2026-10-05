# Task 10 report: transaction profile and permanent gates

## Status

DONE_WITH_CONCERNS

Task 10 publishes the synchronous single-tree transaction and stable
node-existence-constraint slice. It does not close undo/redo support labels,
Task 11, or the full M5 release.

## Changed files

- `.github/workflows/shared-tree.yml`
  - Renamed the oracle and native steps to describe the complete supported
    SharedTree profile.
- `.github/workflows/shared-tree-interop.yml`
  - Renamed the oracle and three-client steps to describe the complete
    supported profile.
- `README.md`
  - Added API-accurate Gleam examples for a committed callback, a typed abort,
    and `NodeInDocument`.
  - Documented nesting, event and commit behavior, sequenced constraint checks,
    and deferred transaction features.
- `docs/superpowers/plans/2026-09-21-shared-tree.md`
  - Marked only the transaction-boundary and stable-constraint slice as
    published.
  - Left undo/redo profile closure and final M5 regression closure open.
- `docs/superpowers/plans/2026-09-29-shared-tree-transactions.md`
  - Marked Task 10 complete with focused RED/GREEN and generation evidence.
  - Left Task 11 open.
- `test/fixtures/shared_tree/manifest.json`
  - Added generated `inventory.transactionContract` metadata.
- `test/fixtures/shared_tree/profile.json`
  - Added `synchronous-single-tree-transactions` and
    `stable-node-existence-constraints`.
  - Removed the false `public-transactions` exclusion.
  - Added explicit exclusions for asynchronous, cross-tree,
    schema-in-transaction, `noChange`, metadata, and post-processor features.
  - Preserved `undo-redo` and the existing combined
    `async-cross-tree-transactions` exclusion.
- `tools/shared-tree-oracle/README.md`
  - Documented the published transaction profile, evidence, semantics, and
    exclusions.
- `tools/shared-tree-oracle/gates.test.mjs`
  - Added permanent workflow-name assertions for the supported profile.
- `tools/shared-tree-oracle/generate.mjs`
  - Generated transaction-contract metadata from the service-owned feature
    arrays.
- `tools/shared-tree-oracle/generate.test.mjs`
  - Added the failing-then-passing transaction-contract assertion.
- `tools/shared-tree-oracle/interop.mjs`
  - Updated the pinned profile digest to
    `08bc0e39dcb8c399d477b70ee183d42f5fbd69e842aa7642befe38e7246aff6b`.
- `tools/shared-tree-oracle/interop.test.mjs`
  - Required the exact transaction support and exclusion profile and new
    digest.
- `tools/shared-tree-oracle/service.mjs`
  - Made transaction support and exclusion labels explicit and reusable.
- `tools/shared-tree-oracle/service.test.mjs`
  - Required the supported transaction labels, the removal of the false public
    exclusion, the explicit deferred labels, and unchanged undo/redo exclusion.

`justfile` was not changed because its existing commands already select the
transaction cases through the full SharedTree suites and coordinator.

## TDD evidence

### RED command

```bash
cd tools/shared-tree-oracle && node --test --test-name-pattern='service profile names supported transactions|manifest records complete native runners|committed profile is hashed|hosted gates name the supported profile' service.test.mjs generate.test.mjs interop.test.mjs gates.test.mjs
```

Exit status: `1`

Exact test output:

```text
✖ hosted gates name the supported profile and install the configured rebar tool (2.930773ms)
✖ manifest records complete native runners and actual wire field kinds (324.873438ms)
✖ the committed profile is hashed and every compatibility pin is validated (14.586637ms)
✖ service profile names supported transactions and their limits (1.703397ms)
ℹ tests 4
ℹ suites 0
ℹ pass 0
ℹ fail 4
ℹ cancelled 0
ℹ skipped 0
ℹ todo 0
ℹ duration_ms 1140.403857

✖ failing tests:

test at gates.test.mjs:70:1
✖ hosted gates name the supported profile and install the configured rebar tool (2.930773ms)
  AssertionError [ERR_ASSERTION]: The input did not match the regular expression /name: Supported SharedTree profile validators/.

test at generate.test.mjs:3663:1
✖ manifest records complete native runners and actual wire field kinds (324.873438ms)
  AssertionError [ERR_ASSERTION]: Expected values to be strictly deep-equal:
  + actual - expected

  + undefined
  - {
  -   cases: [
  -     'transaction-callbacks',
  -     'transaction-constraints',
  -     'transaction-wire',
  -     'transaction-history'
  -   ],
  -   excludedFeatures: [
  -     'asynchronous-transactions',
  -     'cross-tree-transactions',
  -     'schema-upgrades-in-transactions',
  -     'no-change-constraints',
  -     'transaction-metadata',
  -     'transaction-post-processors'
  -   ],
  -   supportedFeatures: [
  -     'synchronous-single-tree-transactions',
  -     'stable-node-existence-constraints'
  -   ]
  - }

test at interop.test.mjs:4788:1
✖ the committed profile is hashed and every compatibility pin is validated (14.586637ms)
  AssertionError [ERR_ASSERTION]: Expected values to be strictly deep-equal:
  + actual - expected
  ... Skipped lines

    [
      'fixed-object-schema',
      'primitive-leaves',
      'optional-string',
      'nested-object',
  ...
      'strict-view-object-map-schema-evolution',
  -   'synchronous-single-tree-transactions',
  -   'stable-node-existence-constraints'
    ]

test at service.test.mjs:28:1
✖ service profile names supported transactions and their limits (1.703397ms)
  AssertionError [ERR_ASSERTION]: Missing support: synchronous-single-tree-transactions
```

The failures were the intended behavior gaps: obsolete workflow labels, absent
generated transaction metadata, absent positive transaction labels, and the
service profile's false exclusion.

### GREEN command

```bash
cd tools/shared-tree-oracle && node --test --test-name-pattern='service profile names supported transactions|manifest records complete native runners|committed profile is hashed|hosted gates name the supported profile' service.test.mjs generate.test.mjs interop.test.mjs gates.test.mjs
```

Exit status: `0`

Exact output:

```text
✔ hosted gates name the supported profile and install the configured rebar tool (3.517156ms)
✔ manifest records complete native runners and actual wire field kinds (609.17501ms)
✔ the committed profile is hashed and every compatibility pin is validated (46.024943ms)
✔ service profile names supported transactions and their limits (2.126427ms)
ℹ tests 4
ℹ suites 0
ℹ pass 4
ℹ fail 0
ℹ cancelled 0
ℹ skipped 0
ℹ todo 0
ℹ duration_ms 1918.372142
```

## Generation evidence

### Generate

```bash
npm --prefix tools/shared-tree-oracle run generate
```

Exit status: `0`

Successful completion:

```text
Generated 55 upstream SharedTree cases
```

The command rebuilt the pinned Fluid test source, ran the object, algebra,
forest, schema-evolution, transaction, array, Identifier, undo/redo, map, and
serialized-input captures, and regenerated the committed manifest and profile.
The pinned upstream probes printed their existing `Bug in Fluid Framework:
Failed Assertion` diagnostic lines while their expected refusal cases passed.

### Check

```bash
npm --prefix tools/shared-tree-oracle run check
```

Exit status: `0`

Successful completion:

```text
Verified 55 upstream SharedTree cases
```

### Diff check

```bash
git --no-pager diff --check
```

Exit status: `0`

No output.

## Preserved values and scope

- `@fluidframework/tree`: `3.1.0`
- Fluid commit: `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960`
- Floodgate commit: `0eb493fc46d1bb9baf1151a6ccdde93544e057e7`
- `minVersionForCollab`: `2.117.0`
- Message: V7
- SharedTreeChange: V5
- ModularChange: V5
- Schema: V2
- Fixed alias, datastore, bootstrap-map, and tree paths unchanged
- M1-M4 support labels unchanged
- `undo-redo` exclusion unchanged
- All undo/redo cases and manifest contract unchanged

## Concerns and deferred validation

- Before edits, the user-recorded full oracle baseline was:
  `npm --prefix tools/shared-tree-oracle test` with 451 tests, 441 passing, and
  10 known failures. This task did not rerun or fix those later-M5 failures.
- Per the task instruction, these long combined commands were deferred:
  - `npm --prefix tools/shared-tree-oracle test`
  - `just shared-tree-test`
  - `just shared-tree-codec-interop`
  - `just shared-tree-interop`
  - full repository build, lint, and test commands
- No hosted workflow was invoked.
- The generated profile keeps `async-cross-tree-transactions` for compatibility
  and also adds separate asynchronous and cross-tree exclusions so the release
  boundary is explicit.
- Undo/redo support labels remain unchanged for the separate undo/redo Task 9.
- Task 11 remains open for the combined transaction regression closure.

## Self-review

- Confirmed only Task 10 files changed.
- Confirmed generated files were produced by the generator, not edited by hand.
- Confirmed no `.code-map`, apm-managed, dependency, or production Gleam files
  changed.
- Confirmed the README examples use the actual public `tree_transaction`,
  `TreeTransactionError`, `Aborted`, `TransactionFailed`, `NodeInDocument`,
  `SharedTree`, `tree_set`, and `FieldPath` shapes.
- Confirmed the roadmap does not claim full M5 closure.
