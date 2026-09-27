# Task 5 Report: Outer Changes in Edit History

## Status

Complete.

Commit: `8904145bb5317905b3bc54e987c6ade40ce3a445`

Subject: `refactor(tree): retain outer changes in edit history`

## Implementation

- Changed `history.Commit`, rollback entries, branch rebase results, receipts,
  snapshots, pending queues, and resubmission output to retain
  `shared_change.Changeset`.
- Replaced optional single forest deltas in `HistoryUpdate` with ordered
  `effects` and `sequenced_effects` lists.
- Routed history composition, inversion, rebase, effect conversion, revision
  metadata collection, identity traversal, and identity-order rebinding
  through `shared_change`.
- Preserved common-prefix elimination by commit revision and preserved the
  rollback cache key based on branch-node identity.
- Included the allocated rollback revision and the complete outer and inner
  revision set when rebinding rollback changes.
- Wrapped locally authored modular changes with `shared_change.from_data`.
- Applied ordered data effects through the existing forest delta path.
  Schema effects still return the explicit pre-Task-6 refusal in the kernel,
  and runtime wire decoding still refuses live schema changes.
- Updated resubmission repair collection and refresher replacement to traverse
  each data item without removing or changing schema items.
- Moved codec schema state values to `schema.SchemaState` and wire change
  values to `shared_change.TreeChange`.
- Changed runtime wire conversion to retain the outer envelope, including an
  empty outer change, while preserving the explicit live-schema refusal.
- Changed summary decoding to retain and normalize the complete ordered wire
  item list. Summary encoding preserves complete schema-bearing commits and
  keeps the existing data-only stale-wire rewrite behavior.
- Updated fixture and test consumers to use outer commits. Data-only M1/M2
  fixture projections remain unchanged. The history fixture can apply a fixed
  schema effect with `forest.replace_schema` and serializes non-data outer
  changes without flattening them.

## Files

- `src/watershed/tree/codec.gleam`
- `src/watershed/tree/history.gleam`
- `src/watershed/tree/runtime.gleam`
- `src/watershed/tree/summary.gleam`
- `src/watershed/tree_kernel.gleam`
- `test/watershed/shared_tree_channel_test.gleam`
- `test/watershed/shared_tree_codec_test.gleam`
- `test/watershed/shared_tree_history_fixture_test.gleam`
- `test/watershed/shared_tree_history_resubmit_test.gleam`
- `test/watershed/shared_tree_history_test.gleam`
- `test/watershed/shared_tree_kernel_test.gleam`
- `test/watershed/shared_tree_map_change_test.gleam`
- `test/watershed/shared_tree_map_codec_test.gleam`
- `test/watershed/shared_tree_summary_codec_test.gleam`
- `test/watershed/tree/codec_export.gleam`
- `test/watershed/tree/history_fixture.gleam`
- `test/watershed/tree/kernel_fixture.gleam`

## TDD Evidence

### RED

- Added `shared_change.from_data` envelopes to existing history tests and
  history fixture inputs before production changes.
- Added
  `shared_tree_history_schema_only_commit_retains_outer_revision_test`.
- Both required focused commands failed with the expected errors:
  `history.Commit` required `change.Changeset`, and `HistoryUpdate` did not
  have an `effects` field.

### GREEN

- `gleam test --target erlang -- shared_tree_history shared_tree_kernel shared_tree_codec shared_tree_runtime`
  passed: 172 tests.
- `gleam test --target javascript -- shared_tree_history shared_tree_kernel shared_tree_codec shared_tree_runtime`
  passed: 161 tests.
- `just shared-tree-test` passed:
  - Erlang: 547 tests.
  - JavaScript: 536 tests.

## Commands and Results

- Baseline focused Erlang command: 171 passed.
- Baseline focused JavaScript command: 160 passed.
- RED focused Erlang command: failed on outer commit type mismatches and the
  missing `HistoryUpdate.effects` field.
- RED focused JavaScript command: failed on the same expected errors.
- Focused Erlang GREEN command: 172 passed.
- Focused JavaScript GREEN command: 161 passed.
- `just shared-tree-test`: Erlang 547 passed; JavaScript 536 passed.
- `gleam format --check <migrated files>`: passed.
- `git diff --check`: passed.

## Self-review

- No parallel legacy and outer history stores or generic edit manager were
  added.
- No schema item is projected to empty modular data in history, runtime wire
  types, codec types, summary decoding, or summary encoding.
- Data-only fixture output remains in its prior shape, and the existing
  upstream fixture comparisons pass unchanged.
- Common-prefix comparison still uses commit revision identity.
- Rollback reuse still uses `BranchCommit.node_id`.
- Revision collection uses `shared_change.revision_infos` for every ordered
  item, not only the first data run.
- Exhaustive schema/data matches were added at each changed boundary. No
  catch-all variant match was introduced.
- The diff contains only migration source and directly affected tests and
  fixtures.

## Concerns

- Live schema effects remain intentionally unavailable. Runtime rejects wire
  schema changes, and the kernel rejects a schema effect before changing
  forest state. Task 6 owns visible and sequenced schema application.
- Task 7 still owns historical encoding contexts and removal of the retained
  data-only stale-wire rewrite path.

## Fix round 1

### Status

Complete.

Subject: `fix(tree): track mixed-run build availability`

### Implementation

- Added a nonempty history resubmission regression that splits a real scalar
  edit into a build run, a schema boundary, and an attach run.
- Changed repair-root discovery to walk outer items in execution order and
  carry builds forward across data runs.
- Changed refresher replacement to use the same forward-only availability
  model. A data run can use builds from its own run or an earlier run, but it
  cannot use a build from a later run.
- Applied the same repair-root and refresher logic in `tree_kernel.gleam`.
- Kept schema items unchanged and did not add schema effect application.

### Files

- `src/watershed/tree/history.gleam`
- `src/watershed/tree_kernel.gleam`
- `test/watershed/shared_tree_history_resubmit_test.gleam`

### TDD evidence

#### RED

- `gleam test --target erlang -- shared_tree_history_resubmit`
  failed only
  `shared_tree_history_resubmits_prior_run_build_without_repair_test` with
  `required repair content is missing`.
- `gleam test --target javascript -- shared_tree_history_resubmit`
  failed with the same expected error.

#### GREEN

- `gleam test --target erlang -- shared_tree_history shared_tree_kernel shared_tree_history_resubmit`
  passed: 57 tests.
- `gleam test --target javascript -- shared_tree_history shared_tree_kernel shared_tree_history_resubmit`
  passed: 57 tests.
- `just shared-tree-test` passed:
  - Erlang: 548 tests.
  - JavaScript: 537 tests.
  - Storage, bootstrap, and creation smokes passed.
- `gleam format --check` on the changed Gleam files passed.
- `git diff --check` passed.

### Self-review

- Repair validation and refresher replacement both use the same
  execution-ordered build calculation.
- Schema boundaries preserve build availability without applying schema
  effects.
- Future data-run builds are not visible to earlier runs.
- Existing single-run and data-only resubmission tests remain unchanged and
  pass.
- The change is limited to history, the corresponding kernel helpers, and
  the regression test.

### Concerns

- The first complete gate run reached the final creation smoke, where its
  nested Erlang probe was killed without a compiler or assertion error. The
  creation smoke passed immediately in isolation, and a fresh complete gate
  passed. The failure was not reproducible.
- Live schema effect application remains intentionally deferred to Task 6.
