# Task 3 Report: CLI and atomic output

## Status

Complete. All 79 tests pass. `gleam format --check` clean.

## Files changed

| Action | Path |
|--------|------|
| Modified | `tools/source-snippets/gleam.toml` — added `argv >= 1.0.0 and < 2.0.0` |
| Created | `tools/source-snippets/src/source_snippets/cli.gleam` |
| Created | `tools/source-snippets/src/source_snippets/system.gleam` |
| Created | `tools/source-snippets/test/source_snippets/cli_test.gleam` |
| Created | `tools/source-snippets/README.md` |

## TDD — RED evidence

After writing `cli_test.gleam` (before any implementation):

```
error: Unknown module
  ┌─ test/source_snippets/cli_test.gleam:4:1
No module has been found with the name `source_snippets/cli`.
```

## Tests (11 new, 79 total)

| Test | Covers |
|------|--------|
| `run_zero_args_test` | `WrongArgumentCount(0)` |
| `run_one_arg_test` | `WrongArgumentCount(1)` |
| `run_extra_args_test` | `WrongArgumentCount(3)` |
| `run_success_test` | valid generation, output file created |
| `run_creates_parent_dir_test` | nested output path, parent created |
| `run_no_dir_component_test` | bare filename output, no false directory error |
| `run_preserves_output_on_failure_test` | atomic write — existing output unchanged on error |
| `run_replaces_output_on_success_test` | atomic write — output updated on success |
| `run_black_box_bad_marker_test` | end-to-end fixture; error message contains path + marker |
| `format_error_wrong_count_test` | `format_error` includes arg count |
| `format_error_output_write_test` | `format_error` includes path |

## Design notes

- `ensure_parent` matches on `""` and `"."` to skip directory creation for
  bare filename output paths (`filepath.directory_name("foo.json")` returns `""`).
- `system.gleam` contains only the single `@external(erlang, "erlang", "halt")`
  FFI declaration; no other Erlang externals are used.
- The `run/1` function is pure in the argument-count sense and is fully
  testable without subprocess invocation.
- `format_error/1` is exported so callers can inspect the diagnostic in tests
  and the message format is covered by tests.

## Concerns

- The black-box bad-marker test verifies the diagnostic for `OrphanMarker`
  (the existing `bb` marker becomes orphaned when the config is rewritten to
  reference `ghost-marker`). `MarkerNotFound` would require a config where the
  marker root is empty, which the orphan check precedes anyway; the current
  approach is consistent with the generator's error ordering.
- `system.halt(1)` in `main` terminates the Erlang VM. Tests call `run/1`
  directly and never reach `main`, so `halt` is never invoked from the test
  suite.
