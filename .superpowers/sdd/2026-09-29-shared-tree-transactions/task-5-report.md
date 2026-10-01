# Task 5 report: runtime-core transaction integration

**Date:** 2026-09-30
**Baseline:** `a3d34da1bf372fde8cd442af613d8c4c5c09a30a`
**Scope:** Task 5 only

## Outcome

Runtime core now owns one active transaction for one SharedTree address and
view. Existing tree reads and edits route through isolated transaction state.
Only outer commit appends normal pending history and submits a channel batch.
Abort and no-op restore committed document channels and summary compressor
state while preserving the Task 4 identity and ongoing-compressor invariants.

The implementation does not add the JavaScript or BEAM public callback APIs
from Tasks 6 and 7.

## RED

The baseline focused matrix passed before changes:

```text
Erlang:     151 passed
JavaScript: 140 passed
```

Named runtime lifecycle tests were added before runtime implementation. The
first Erlang RED run failed to compile because these required values did not
exist:

```text
runtime_core.begin_tree_transaction
runtime_core.commit_tree_transaction
runtime_core.abort_tree_transaction
runtime_core.tree_transaction_depth
transaction.begin_nested_with_constraints
transaction.depth
```

Later focused RED runs established three behavioral requirements:

- `summary_channels` returned committed snapshots while a transaction was
  active instead of returning a typed error.
- `is_synced` returned `True` while isolated transaction work existed.
- A nested constraint resolved against outer-authored content failed at finish
  because every constraint was applied against the outer base state.
- A net-zero array transaction reached outer submission with two authored
  revision records in one tagged commit. The pinned encoder rejected it because
  a tagged commit must contain only its commit revision.

## GREEN

The exact required matrix passed after implementation:

```bash
gleam test --target erlang -- shared_tree_runtime shared_tree_transaction shared_tree_array_kernel shared_tree_schema_evolution
gleam test --target javascript -- shared_tree_runtime shared_tree_transaction shared_tree_array_kernel shared_tree_schema_evolution
```

```text
Erlang:     159 passed
JavaScript: 148 passed
```

The directly affected reconnect and shared-core paths also passed:

```bash
gleam test --target erlang -- runtime_core roster lww_map_channel lww_register_channel
gleam test --target javascript -- runtime_core roster lww_map_channel lww_register_channel
```

```text
Erlang:     137 passed
JavaScript: 137 passed
```

Targeted formatting and diff checks passed:

```bash
gleam format --check <changed Gleam files>
git diff --check
```

`just format` stalled in Trellis after it launched both package format jobs.
The changed Gleam files were formatted directly and then checked.

## Runtime behavior

- `Core.active_tree_transaction` stores the tree address, immutable view, and
  pure transaction value.
- Matching reads, map reads, array reads, compatibility checks, retained
  snapshots, and history evidence select isolated transaction state.
- Matching edit batches call `transaction.apply_edit`, replace the active
  value, and return no events or outbound operations.
- Cross-tree edits and transactions, wrong-view nested begin, missing
  lifecycle calls, and invalid constraint paths return `TreeOperationFailed`
  with typed tree errors.
- Nested commit and abort do not publish events or operations.
- Outer commit calls the existing `submit_tree_commits` path once. Tests decode
  one grouped batch containing one ID allocation item and one tree operation.
- The composed change replaces all authored revision identities with the first
  outer revision before constraints, history append, and encoding. The
  compressor identity order still comes from document identity order, not UUID
  order.
- Outer abort installs the returned rollback state and ongoing compressor.
  Its serializable compressor state matches the base, while local compressor
  advancement remains observable.
- `NoCommit(state, compressor)` installs both returned values and emits no
  event, allocation, pending commit, or outbound operation.
- Schema upgrade, summary construction, reconnect adoption, resubmission, and
  sequenced inbound application reject while a transaction is active.
- Active transactions make `is_synced` and `wants_summary` false.

## API decisions and deviations

Task 4's unconstrained `begin_nested(Transaction) -> Transaction` remains
available. Task 5 adds:

```gleam
pub fn begin_nested_with_constraints(
  value: Transaction,
  constraints: List(change.ConstraintTarget),
) -> Result(Transaction, TreeError)

pub fn depth(value: Transaction) -> Int
```

The fallible helper validates nested targets against the current isolated
state. Transaction internals retain each constraint set with that authoring
state. This preserves outer author order for constraints on content authored
before nested begin. Nested abort truncates constraint sets at its savepoint.
The runtime does not duplicate constraint validation or composition logic.

`adopt_reconnect` changed from `Core` to `Result(Core, CoreError)`. It was the
existing infallible transition that could not satisfy the required explicit
guard. JavaScript and BEAM reconnect handlers now fail explicitly if the core
rejects the transition.

No `channel.gleam` change was needed. Existing `TreeEvent` coverage already
maps the one outer `TreeChanged` event. No schema-evolution test change was
needed because the runtime lifecycle suite directly verifies schema rejection.

## Files

Production:

- `src/watershed/runtime_core.gleam`
- `src/watershed/tree/transaction.gleam`
- `src/watershed/runtime.gleam`
- `src/watershed/runtime_beam.gleam`

Tests:

- `test/watershed/shared_tree_runtime_test.gleam`
- `test/watershed/shared_tree_transaction_test.gleam`
- `test/watershed/shared_tree_array_kernel_test.gleam`
- `test/watershed/runtime_core_test.gleam`
- `test/watershed/roster_test.gleam`
- `test/watershed/lww_map_channel_test.gleam`
- `test/watershed/lww_register_channel_test.gleam`

Plan and report:

- `docs/superpowers/plans/2026-09-29-shared-tree-transactions.md`
- `.superpowers/sdd/2026-09-29-shared-tree-transactions/task-5-report.md`

## Self-review

- Transaction state remains outside normal history until outer commit.
- Ordinary edit submission still uses the original immediate author-and-submit
  path and retains its existing batching behavior.
- All error paths return immutable core state to the caller; no broad catch or
  success-shaped fallback was added.
- Constraint identity uses the existing forest references and document
  identity order. No UUID ordering was introduced.
- Abort and no-op install Task 4's returned state instead of reconstructing it,
  preserving NodeRefs, allocation watermarks, array mutation flags, and
  compressor summary invariants.
- The reconnect signature change is wider than the brief's primary file list,
  but it is required to make the guard typed and explicit. Call-site changes
  are mechanical result handling only.

## Concerns

- Tasks 6 and 7 must call the new runtime-core lifecycle functions and, on
  BEAM, defer inbound actor messages while the outer callback is active. This
  task intentionally does not add those public or actor APIs.
- The repository-wide `just format` command stalled during this run. Targeted
  Gleam formatting completed successfully.
