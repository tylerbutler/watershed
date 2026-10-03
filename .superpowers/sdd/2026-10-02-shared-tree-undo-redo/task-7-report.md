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
| MSN cannot trim either live pin; disposing one handle releases only its commit and repair data; the other stays usable until disposal | `shared_tree_history_multiple_revertibles_release_only_disposed_pin_test` |
| Undo and redo summaries reload, invalidate old runtime-local handles, and continue editing | `shared_tree_undo_redo_summary_reload_continues_without_old_handles_test` |
| A summary taken while undo is pending contains sequenced state only; the tail then applies and editing continues | `pending_undo_summary_keeps_sequenced_state_then_applies_tail_test` |

The retention test uses the pure history API because commit and repair-data
trimming are history internals. Reconnect and summary lifetime tests use the
public runtime-core and document APIs. Reload creates a fresh runtime without
recreating historical handles; no historical commit event is replayed, so no
old event-scoped factory is recreated.

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
- Verified the pure history test proves both live pins survive MSN advancement,
  then proves each disposal independently releases its commit and repair data.
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
- Reload lifetime is proved at the public runtime-core/document boundary named
  by the brief's file list. It does not add separate JS or BEAM facade test
  files; those public facade event and handle contracts remain covered by
  Tasks 5 and 6.
