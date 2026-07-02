# Task 3 Report — Multi-channel runtime_core (M7a)

## Implementation summary
- Replaced `runtime_core`'s single-kernel state with multi-channel state: attached `channels`, `channel_order`, detached local-only maps, multi-variant `InFlight`, and tagged ingest/edit events.
- Added fatal `UnknownChannel` and `DuplicateAttach` handling.
- Updated bootstrap/resume/replay to seed from multi-channel summaries, guarantee an attached `root`, and materialize channels from replayed attach ops.
- Added detached-channel creation and multi-address reads/writes.
- Implemented attach dependency submission for handle-bearing sets using post-order DFS with visited-set cycle protection; detached dependencies are attached before the referencing set.
- Own attach acks now pop the in-flight attach without mutating channel state; channel op acks still rebase via `map_kernel.ack_local`.
- Re-stamped reconnect resubmits for both attach and channel ops while preserving queue order.
- Added `summary_channels` and updated summary upload/load plumbing in `runtime`, `runtime_js`, `git_storage`, and `wire` to carry channel lists instead of flattening.
- Kept compile-only runtime/public wrappers root-only for edits/reads/events as requested.

## Tests and results
- Targeted: `gleam test runtime_core` — 36/36 passed.
- Full suite: `gleam test` — 131/131 passed.
- Also ran `gleam format` on changed Gleam files and `git diff --check` (clean).

## Files changed
- `src/watershed/runtime_core.gleam`
- `src/watershed/runtime.gleam`
- `src/watershed/runtime_js.gleam`
- `src/watershed/git_storage.gleam`
- `src/watershed/wire.gleam`
- `test/watershed/runtime_core_test.gleam`
- `.superpowers/sdd/task-3-report.md`

## Self-review
- Reviewed the diff against the task brief requirements and verified each required behavior with targeted tests.
- Added focused coverage for remote attach application, fatal unknown/duplicate channel behavior, detached edits, recursive/cyclic attach submission order, attach ack handling, reconnect resubmit ordering, and multi-channel bootstrap paths.
- Ran an explicit review pass after implementation; one high-signal issue was found in the JavaScript runtime (`handle_sequenced` errors were being swallowed) and fixed so fatal inbound channel errors now terminate consistently instead of being ignored.
- Left `map_kernel.gleam` unchanged.

## Concerns
- No functional concerns after validation.
- Existing unrelated working-tree changes in `src/watershed/handle.gleam` and `test/watershed/handle_test.gleam` were left untouched and are not part of this task's commit.

## Task 3 fix addendum
- Fixed `same_attach_shape` in `src/watershed/runtime_core.gleam` to compare attach snapshot values by key after normalizing JSON values, so value mismatches now fail while JSON object key-order differences still pass.
- Added `attach_ack_value_mismatch_is_fatal_test` in `test/watershed/runtime_core_test.gleam`.
- Commands/results:
  - `gleam test runtime_core` — 37 tests passed.
  - `gleam test` — 132 tests passed.

## Task 3 final review fix addendum
- Fixed `src/watershed/wire.gleam` so explicit attach envelopes only decode when `channelType == "map"`; unknown channel types now fail with `ChannelType`.
- Fixed v1 summary fallback to always load as `ChannelSnapshot(address: "root", channel_type: "map", ...)`.
- Updated `test/watershed/wire_test.gleam` with focused coverage for unknown attach channel types and the v1 root-address fallback.
- Commands/results:
  - `gleam format src/watershed/wire.gleam test/watershed/wire_test.gleam` — succeeded.
  - `gleam test -- test/watershed/wire_test.gleam` — 30/30 passed.
  - `gleam test` — 132/132 passed.
