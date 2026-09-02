# Task 2 Report: Configuration, Validation, and Manifest Encoding

## Commit

`c53bff1` — `feat(snippets): generate validated manifests`

## Files

### Created
- `src/source_snippets/config.gleam` — Version-1 JSON decoder with strict validation
- `src/source_snippets/generator.gleam` — Source-root scanning, inventory validation, composition
- `src/source_snippets/manifest.gleam` — Deterministic JSON encoding sorted by id
- `test/source_snippets/config_test.gleam` — 20 config decoder tests
- `test/source_snippets/generator_test.gleam` — 16 generator/manifest tests

### Modified
- `gleam.toml` — Added `simplifile` and `filepath` dependencies
- `manifest.toml` — Updated lockfile
- `.gitignore` — Added `/test/fixtures/gen`
- `src/source_snippets.gleam` — Re-exports `decode_config`, `generate`, `encode`

## Commands and Evidence

```
$ gleam test
58 passed, no failures

$ gleam format --check src/ test/
(exit 0, all formatted)
```

## API Choices

- **Config types**: `Config`, `SnippetSpec`, `ConfigError` — all in `config.gleam`
- **Generator types**: `GeneratedSnippet`, `GenerateError` — in `generator.gleam`
- **Manifest types**: `Manifest`, `ManifestEntry` — in `manifest.gleam`
- **Public API** via `source_snippets.gleam`: `decode_config/1`, `generate/1`, `encode/1`
- **`source_root`** resolved relative to config file directory, per spec
- **Marker/source paths** relative to source root
- **Separator** defaults to `"\n\n"` via optional JSON field
- **Orphan detection** validates every discovered marker is referenced
- **Cross-file duplicate markers** detected during inventory scan
- **Marker reuse** across output snippets is permitted (same marker in multiple specs)
- **Deterministic output** via `string.compare`-sorted manifest entries

## Self-Review

- All error types are Result-based, no panics
- Marker-only approach: no parser, no CLI framework, no JS bridge
- Real filesystem fixture tests, no mocks — fixtures created/deleted per test
- Deterministic: manifest entries sorted by id, encoding is stable
- Complete marker inventory validated before extraction begins
- Extension filtering excludes non-configured files from scan
- No unrelated files modified

## Concerns

- `list_files_recursive` is a manual recursive walk; `simplifile` may gain a
  built-in recursive listing in a future version that could replace it.
- Orphan detection reports only the first orphan found; multiple orphans require
  re-running after fixing the first. This matches the "fail fast" error style
  used throughout.
- The `encode` function uses `json.to_string` which produces compact (not
  pretty-printed) JSON. The spec shows pretty-printed output; if pretty-printing
  is needed later, a post-processing step or custom encoder would be required.

---

## Review Fix: Path Canonicalization and Descriptive Field Errors

### Commit

(see below)

### Finding 1: Path canonicalization (generator.gleam)

**Problem:** Inventory keys use canonical OS paths (from filesystem scan via
`make_relative`), but `SnippetSpec.source_path` is raw from JSON config. Paths
like `./src/main.gleam` or `src/../src/main.gleam` read successfully then
falsely return `MarkerNotFound` because `"src/main.gleam" != "./src/main.gleam"`.

**Fix:** Added `normalize_snippet_paths` in `generate` that runs
`filepath.expand` on each `SnippetSpec.source_path` before any inventory
comparison. This resolves `.` and `..` segments. Paths that escape the source
root (leading `..` after expansion) are rejected with a new
`InvalidSourcePath(snippet_id, source_path)` error. The normalized path becomes
the canonical repo-relative `sourcePath` in output.

**API decision:** Normalize-then-proceed for valid paths (`./src/main.gleam` →
`src/main.gleam`). Reject for paths that cannot be normalized (escape root).
`filepath.expand` returns `Error(Nil)` for `../escaped.gleam`, which maps
cleanly to `InvalidSourcePath`. No ambiguity: a path either resolves within
root or it does not.

**Tests added (3):**
- `generate_dot_slash_source_path_test` — `./src/main.gleam` resolves, output
  has clean `src/main.gleam`
- `generate_dotdot_source_path_test` — `src/../src/main.gleam` resolves
- `generate_escaping_path_rejected_test` — `../escaped.gleam` returns
  `InvalidSourcePath`

### Finding 2: Descriptive config field errors (config.gleam)

**Problem:** `FieldError(field, message)` was never constructed. All decode
failures (missing fields, wrong types) collapsed to `JsonSyntax("invalid JSON")`
because `json.parse` error was caught with a blanket `Error(_)`.

**Fix:** Pattern match on `json.DecodeError` variants:
- `UnableToDecode(errors)` → convert first `decode.DecodeError` to
  `FieldError(field, message)` with dot-path field names including array indices
  (e.g. `"snippets[0].id"`, `"version"`)
- `UnexpectedEndOfInput`, `UnexpectedByte`, `UnexpectedSequence` → remain
  `JsonSyntax("invalid JSON")`

`FieldError` is retained and now constructed. `JsonSyntax` is reserved for
malformed JSON text only.

**Tests added (7):**
- `decode_wrong_type_version_test` — string where int expected
- `decode_wrong_type_source_root_test` — int where string expected
- `decode_wrong_type_marker_roots_test` — string where array expected
- `decode_wrong_type_extensions_test` — string where array expected
- `decode_wrong_type_snippet_id_test` — int where string, path includes snippet
  context
- `decode_wrong_type_snippet_markers_test` — string where array, path includes
  snippet context
- `decode_missing_snippet_source_path_test` — missing field in snippet, path
  includes snippet context

**Tests updated (2):**
- `decode_missing_version_field_test` — now expects `FieldError("version", _)`
- `decode_missing_snippets_field_test` — now expects `FieldError("snippets", _)`

### Evidence

```
$ gleam test
68 passed, no failures (was 58)

$ gleam format --check src/ test/
(exit 0, all formatted)
```

RED witnessed before fix: 12 failures across both findings (missing field errors
returned `JsonSyntax`, path mismatches returned `MarkerNotFound`, escape
returned wrong error type). All 12 failures resolved by the implementation.
