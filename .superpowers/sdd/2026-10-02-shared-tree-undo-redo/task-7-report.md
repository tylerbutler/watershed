# Task 7 report: Native field, recovery, summary, and reload behavior

## Status

Implemented and verified on `main`.

## Acceptance matrix

Every field row runs on Erlang and JavaScript through the exact Task 7
multi-selector commands. The shared harness asserts a literal snapshot, the
authored commit kind, the exact applied-event count, and a
`FullyApplied` settlement for the target, later, and undo commits.

| Brief row | Test |
| --- | --- |
| Object set / different field set | `shared_tree_undo_object_set_preserves_later_field_test` |
| Object replacement / child edit | `shared_tree_undo_object_replacement_pins_child_edit_conflict_test` |
| Map set / different key set | `shared_tree_undo_map_set_preserves_later_key_test` |
| Map delete / same key set | `shared_tree_undo_map_delete_pins_later_overwrite_test` |
| Array insert / later insert | `shared_tree_undo_array_insert_preserves_later_insert_test` |
| Array remove / later move | `shared_tree_undo_array_remove_restores_identity_at_pinned_position_test` |
| Same-array move / later insert | `shared_tree_undo_same_array_move_preserves_pinned_order_test` |
| Cross-array move / later remove | `shared_tree_undo_cross_array_move_pins_remove_conflict_test` |
| Transaction / remote unrelated edit | `shared_tree_undo_transaction_reverts_as_one_commit_after_remote_edit_test` |
| Identifier field / remote unrelated edit | `identifier_undo_preserves_value_and_allocation_after_remote_edit_test` |

The Identifier row also redoes the insertion and proves the generated
Identifier and allocation remain stable. The pinned cross-array conflict
result restores `left` to `[left-a, left-b]` and leaves `right` empty.

## Recovery, retention, and summary matrix

| Brief requirement | Test |
| --- | --- |
| Reconnect with a live retained handle, receive a later edit, and revert | `retained_revertible_reconnects_and_reverts_after_later_change_test` |
| Pending undo accepted before drop deduplicates by revision, applies once, settles once, and does not resubmit | `pending_undo_accepted_before_drop_applies_and_settles_once_test` |
| MSN cannot trim either live pin; disposing one handle releases only its commit; the other stays usable until disposal | `shared_tree_history_multiple_revertibles_release_only_disposed_pin_test` |
| Disposing a retained pending-prefix handle releases its rollback records at the next minimum advance | `shared_tree_history_pending_revertible_pins_prefix_rollbacks_test` |
| Undo and redo summaries reload, invalidate old runtime-local handles, and continue editing | `shared_tree_undo_redo_summary_reload_continues_without_old_handles_test` |
| Reload emits no historical facade commit event or factory; a new local commit supplies a new factory | `summary_reload_emits_no_historical_commit_factory_and_new_edit_does_test` in the JavaScript and BEAM runtime suites |
| A summary taken while undo is pending contains sequenced state only; the tail then applies and editing continues | `pending_undo_summary_keeps_sequenced_state_then_applies_tail_test` |

The retention tests use the pure history API because commit and rollback-record
trimming are history internals. Reconnect and summary lifetime tests use the
public runtime-core and document APIs. The JavaScript and BEAM facade tests
subscribe before the reloaded seed connects, observe no historical commit
event, then acquire a valid handle from the next local commit's event-scoped
factory.

## TDD evidence

### Representative RED

All named Task 7 tests were added before the shared acceptance harness.

Command:

```text
gleam test --target javascript -- shared_tree_undo shared_tree_history shared_tree_history_resubmit shared_tree_document_summary shared_tree_summary shared_tree_array_kernel shared_tree_map_kernel shared_tree_transaction shared_tree_identifier
```

Exit code: `1`

Representative output:

```text
error: Unknown module

The module `watershed/tree/undo_acceptance` could not be found.
```

The compiler reported the missing import for every newly added Task 7 entry
point. This established RED before helper implementation.

### Identifier snapshot correction RED

During final self-review, the Identifier row was strengthened from selected
field reads to complete literal snapshots.

Command:

```text
gleam test --target erlang -- shared_tree_identifier
```

Exit code: `1`

Exact relevant output:

```text
Failed Tests: 1

FAIL  identifier_undo_preserves_value_and_allocation_after_remote_edit_test
Test Files: 1
     Tests: 44 passed | 1 failed (45)
```

The generated point stores authored fields before the generated Identifier.
The expected literal was corrected to the native field order, then verified on
both targets.

### Identifier snapshot correction GREEN

Commands:

```text
gleam test --target erlang -- shared_tree_identifier
gleam test --target javascript -- shared_tree_identifier
```

Exit code: `0` for each command.

Exact result for each target:

```text
Test Files: 1
     Tests: 45 passed (45)
```

## Required final GREEN

### Erlang acceptance suite

Command:

```text
gleam test --target erlang -- shared_tree_undo shared_tree_history shared_tree_history_resubmit shared_tree_document_summary shared_tree_summary shared_tree_array_kernel shared_tree_map_kernel shared_tree_transaction shared_tree_identifier
```

Exit code: `0`

Exact result:

```text
Test Files: 11
     Tests: 238 passed (238)
Started at: 01:04:18
  Duration: 16s (discover 96ms, collect 1ms, tests 16s, reporters 15ms)
```

### JavaScript acceptance suite

Command:

```text
gleam test --target javascript -- shared_tree_undo shared_tree_history shared_tree_history_resubmit shared_tree_document_summary shared_tree_summary shared_tree_array_kernel shared_tree_map_kernel shared_tree_transaction shared_tree_identifier
```

Exit code: `0`

Exact result:

```text
Test Files: 11
     Tests: 238 passed (238)
Started at: 01:04:35
  Duration: 46s (discover 506ms, collect 2ms, tests 46s, reporters 4ms)
```

### SharedTree codec interoperability

Command:

```text
just shared-tree-codec-interop
```

Exit code: `0`

Exact result:

```text
SharedTree codec interoperability passed: 2 targets, 38 items each
```

### Full SharedTree gate

Command:

```text
just shared-tree-test
```

Exit code: `0`

Exact result:

```text
Test Files: 48
     Tests: 969 passed (969)
Started at: 01:07:13
  Duration: 1m (discover 930ms, collect 3ms, tests 1m, reporters 11ms)
shared tree storage smoke: ok
{"targets":["javascript","erlang"],"createRequests":34,"redirectRequests":0,"webSocketConnections":0}
```

## Files

- `test/watershed/tree/undo_acceptance.gleam`
- `test/watershed/shared_tree_undo_test.gleam`
- `test/watershed/shared_tree_history_test.gleam`
- `test/watershed/shared_tree_history_resubmit_test.gleam`
- `test/watershed/shared_tree_document_summary_test.gleam`
- `test/watershed/shared_tree_summary_test.gleam`
- `test/watershed/shared_tree_array_kernel_test.gleam`
- `test/watershed/shared_tree_map_kernel_test.gleam`
- `test/watershed/shared_tree_transaction_test.gleam`
- `test/watershed/shared_tree_identifier_test.gleam`
- `.superpowers/sdd/2026-10-02-shared-tree-undo-redo/task-7-report.md`

## Self-review

- Verified all ten matrix rows use the same target-neutral runtime harness and
  are selected by both exact target commands.
- Verified each matrix row checks the optimistic and settled literal snapshot,
  commit kind, exactly two authoring events, and one `FullyApplied`
  settlement.
- Verified transaction undo is one `UndoCommit` after a genuine remote map
  edit.
- Verified Identifier undo and redo preserve the generated value and complete
  literal tree state after a genuine remote edit.
- Verified reconnect keeps the retained handle valid after catch-up and
  preserves the later remote field.
- Verified accepted-before-drop sequencing settles once, resubmits nothing,
  and duplicate delivery produces no event or second effect.
- Verified the multiple-handle history test proves both live pins survive MSN
  advancement, then proves each disposal independently releases its commit.
- Verified the pending-prefix history test reads the rollback revision list
  before and after disposal and minimum advancement, proving that rollback
  records are released rather than only invalidating the handle.
- Verified undo and redo summaries load through a new runtime, old handles are
  invalid there, and each loaded runtime authors and settles a new edit.
- Verified a pending-undo summary exposes the sequenced target state, then
  accepts the pending undo revision as tail and continues editing.
- Verified coupled pre-existing array and summary assertions now separate
  commit metadata, settlement events, and ordinary tree-change events.

## Concerns

- The final commands retain pre-existing warnings for two unused private codec
  helpers, two JavaScript-only unused map-facade helpers, and two unsafe
  JavaScript integer fixtures. Task 7 adds no warning category.
- The repository retains the pre-existing warnings listed above. The new
  history inspection function is internal API used only by tests.

## Fix round 1

### Findings addressed

1. Array remove, same-array move, and cross-array move now capture node
   references before the target edit and compare them with the references at
   the expected settled positions after undo. Literal optimistic and settled
   snapshots remain in the same cases.
2. The Identifier case now authors a second generated point after redo. It
   asserts a different generated Identifier, settles the commit, delivers it
   to the peer, and checks that both runtimes interpret the two identifiers
   without collision.
3. The transaction and Identifier cases now assert the later local
   `DefaultCommit`, two authoring events, its `FullyApplied` settlement, and the
   exact two-event remote application contract.
4. JavaScript and BEAM facade tests subscribe before reload connects. They
   assert that reload emits no historical commit event or factory, then assert
   that the next local `DefaultCommit` supplies a usable new factory.
5. `history.inspect_rollback_revisions` exposes only rollback revision IDs for
   internal tests. The pending-prefix retention test checks the exact retained
   rollback IDs before disposal and an empty list after disposal and minimum
   advancement.
6. The summary reload case now asserts `DefaultCommit`, `UndoCommit`, and
   `RedoCommit` authoring events, exact event counts, and `FullyApplied`
   settlements before each summary capture.
7. The pending-tail case now compares the complete remote event list:
   `TreeCommitApplied(DefaultCommit, local: False, revertible: False)` followed
   by `TreeChanged(False)`. It also applies the same tail to the original
   pending runtime and asserts the authored `UndoCommit` receives one
   `FullyApplied` settlement.
8. This report now separates commit trimming, rollback-record release,
   runtime-core handle invalidity, and public facade factory lifetime.

### Files

- `src/watershed/tree/history.gleam`
- `test/watershed/tree/undo_acceptance.gleam`
- `test/watershed/shared_tree_history_test.gleam`
- `test/watershed/shared_tree_runtime_js_test.gleam`
- `test/watershed/shared_tree_runtime_beam_test.gleam`
- `.superpowers/sdd/2026-10-02-shared-tree-undo-redo/task-7-report.md`

### Test mapping

| Finding | Tests |
| --- | --- |
| Array identity | `shared_tree_undo_array_remove_restores_identity_at_pinned_position_test`, `shared_tree_undo_same_array_move_preserves_pinned_order_test`, `shared_tree_undo_cross_array_move_pins_remove_conflict_test` |
| Identifier allocation after redo | `identifier_undo_preserves_value_and_allocation_after_remote_edit_test` |
| Later remote commit events | `shared_tree_undo_transaction_reverts_as_one_commit_after_remote_edit_test`, `identifier_undo_preserves_value_and_allocation_after_remote_edit_test` |
| Reload event/factory lifetime | `summary_reload_emits_no_historical_commit_factory_and_new_edit_does_test` in `shared_tree_runtime_js_test.gleam` and `shared_tree_runtime_beam_test.gleam` |
| Rollback-record release | `shared_tree_history_pending_revertible_pins_prefix_rollbacks_test` |
| Summary event contract | `shared_tree_undo_redo_summary_reload_continues_without_old_handles_test` |
| Pending-tail event contract | `pending_undo_summary_keeps_sequenced_state_then_applies_tail_test` |

### RED

Command:

```text
gleam test --target javascript -- shared_tree_undo shared_tree_history shared_tree_history_resubmit shared_tree_document_summary shared_tree_summary shared_tree_array_kernel shared_tree_map_kernel shared_tree_transaction shared_tree_identifier
```

Exit code: `1`

Representative output:

```text
error: Unknown module value
1519 │   history.inspect_rollback_revisions(pinned.history)

The module `watershed/tree/history` does not have a
`inspect_rollback_revisions` value.
```

This failure came from the focused rollback-release assertions before the
inspection function existed.

### GREEN

Exact Task 7 Erlang command:

```text
Test Files: 11
     Tests: 238 passed (238)
```

Exact Task 7 JavaScript command:

```text
Test Files: 11
     Tests: 238 passed (238)
```

Facade reload checks:

```text
gleam test --target javascript -- shared_tree_runtime_js
Test Files: 1
     Tests: 12 passed (12)

gleam test --target erlang -- shared_tree_runtime_beam
Test Files: 1
     Tests: 28 passed (28)
```

Codec interoperability:

```text
SharedTree codec interoperability passed: 2 targets, 38 items each
```

Full SharedTree gate:

```text
Test Files: 48
     Tests: 970 passed (970)
shared tree storage smoke: ok
{"targets":["javascript","erlang"],"createRequests":34,"redirectRequests":0,"webSocketConnections":0}
```

### Self-review

- The array checks compare `forest.NodeRef` values, not equal visible values.
- The Identifier check proves post-redo allocation by generating and
  round-tripping another Identifier through a peer.
- The transaction and Identifier cases no longer discard later authoring,
  settlement, or remote application events.
- The facade tests register observers before connection and acquire the new
  handle during the event-scoped factory lifetime.
- The rollback inspection returns revision IDs only. It does not expose
  changesets, node IDs, or mutable history internals.
- The pending-tail assertion compares the whole event list and checks the
  original local undo settlement separately.
- No undo, redo, summary, or facade runtime behavior changed in production.
  Production code adds only the internal read-only rollback inspection.
