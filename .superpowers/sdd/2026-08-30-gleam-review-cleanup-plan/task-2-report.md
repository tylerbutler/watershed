# Task 2 report: return `Result` from fallible helpers

## Result
Done.

## Changes
- `test/watershed/crdt_js_browser_smoke.gleam`
  - `document_of`, `value`, `digest`, `replica`, and `peer_count` now return `Result`.
  - Callers now handle `Ok`/`Error` explicitly with assertions in ready handling, wait predicates, and the final report.
- `test/watershed/ordered_collection_channel_test.gleam`
  - `added_value` and `acquired_value` now return `Result(String, Nil)`.
  - Call sites now assert `Ok(...)` before comparing values.
- `test/watershed/rich_text_test.gleam`
  - `get` now returns the underlying `list.key_find` result.
  - Optional callers now branch on `Ok`/`Error` explicitly.

## Commands and results
- `gleam format test/watershed/crdt_js_browser_smoke.gleam test/watershed/ordered_collection_channel_test.gleam test/watershed/rich_text_test.gleam`
  - Exit code `0`.
- `gleam test`
  - Exit code `0`.
  - Warnings only from unrelated pre-existing files, including `test/watershed/crdt_core_test.gleam`, `test/watershed/json_ot_apply_test.gleam`, and `test/watershed/crdt_relay_lifecycle_test.gleam`.
- `gleam test --target javascript watershed`
  - Exit code `0`.
  - Same class of unrelated warnings; no failures.

## Files changed
- `test/watershed/crdt_js_browser_smoke.gleam`
- `test/watershed/ordered_collection_channel_test.gleam`
- `test/watershed/rich_text_test.gleam`
- `.superpowers/sdd/2026-08-30-gleam-review-cleanup-plan/task-2-report.md`

## Concerns
- The test run still emits pre-existing warnings in unrelated modules.
- Untracked plan files and `examples_gleam_files.txt` were left untouched.
