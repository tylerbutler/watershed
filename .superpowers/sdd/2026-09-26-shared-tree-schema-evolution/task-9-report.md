# Task 9 report: expose view-aware APIs on both native facades

## Status

Complete.

## Implementation

- Added `open_tree`, `tree_compatibility`, and `tree_upgrade_schema` to the JavaScript and BEAM facades.
- Bound an immutable application view to each `SharedTree` handle.
- Kept `resolve_tree` strict and made `open_tree` permit an incompatible view for inspection and upgrade.
- Added view-aware runtime and actor operations for every application tree read, write, clear, and map accessor.
- Checked compatibility and performed each requested operation in one runtime-core or actor transaction.
- Invalidated old handles after an incompatible schema upgrade while permitting recovery through a newly opened handle.
- Added raw tree restore APIs so protocol and summary restoration do not manufacture or require an application view.
- Restored summary trees from the stored document view ID while retaining strict application access at the facade boundary.
- Made remote schema incompatibility non-fatal to the document and other DDS channels.
- Projected remote schema notifications from the final reconciled state, before data notifications, and installed local schema state before callbacks.

## Coverage

- Facade parity for the three new APIs.
- JavaScript and BEAM view lifecycle, compatibility, upgrade, stale-handle rejection, and new-handle recovery.
- Atomic guards for tree and map reads and writes.
- Equivalent schema upgrades without notifications.
- Raw restore and incompatible bootstrap seed behavior.
- Remote schema event final state and ordering.
- Continued SharedMap access after a tree becomes incompatible.
- Reload of an already-upgraded tree from a document summary.
- Existing SharedTree storage, bootstrap, creation, and DDS behavior.

## Verification

- Focused Erlang matrix: 133 passed.
- Focused JavaScript matrix: 122 passed.
- Full SharedTree Erlang gate: 596 passed.
- Full SharedTree JavaScript gate: 585 passed.
- SharedTree storage smoke: passed.
- SharedTree bootstrap smoke: passed.
- SharedTree creation smoke: passed.
- Direct `gleam format --check` for all changed Gleam files: passed.
- `git diff --check`: passed.

## Concern

Repository-wide `just format` and bare `gleam format --check` stalled in Trellis fan-out in this environment. Both processes were stopped. Direct formatting checks for every changed Gleam file passed, and the full SharedTree gate passed.
