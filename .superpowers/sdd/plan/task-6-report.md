# Task 6 Report — Add drift gates to existing commands

## Status: COMPLETE (review findings addressed)

**Original commit:** `494f171` — `feat(website): add drift gates for source-backed snippet system (Task 6)`
**Review fix commit:** see git log

## Architecture

A single test file (`website/src/data/drift-gates.test.ts`) implements seven
dependency-free gates using only `node:test`, `node:assert`, and `node:fs`.
Each gate catches one category of drift. Negative tests prove every gate fires
for fabricated invalid data; positive tests validate the codebase is clean.

### Gates

| # | Gate | Checks |
|---|------|--------|
| 1 | Source paths exist | Every `?raw` import and `paths` object value in registries and pages resolves to a real file at repo root |
| 2 | Marker uniqueness | Every `docs:snippet-start`/`end` ID across all `.gleam` sources has exactly one start and one end |
| 3 | Marker completeness | Every marker referenced by a descriptor file exists in source |
| 4 | No orphan markers | Every marker in source is referenced by at least one descriptor file |
| 5 | Literal Gleam policy | `snippetFromLiteral` with `"gleam"` only in explicitly allowlisted modules |
| 6 | Registry source-backing | `practice-snippets.ts` has no `snippetFromLiteral`; `standalone-snippets.ts` has no literal Gleam |
| 7 | Source-backed sourcePath | Registry `paths` objects have non-empty, repo-relative values |
| 8 | No unregistered imports | Authored modules outside the allowlists may not add `?raw` Gleam imports |
| 9 | Import/path agreement | Every `paths` object value has a matching `?raw` import in the same file |

## Review findings addressed

### 1. `hasLiteralGleamCall` balanced-call scanner (was: cross-call regex)

The previous regex `snippetFromLiteral\([\s\S]*?, "gleam"` was greedy across
calls — a non-Gleam literal followed later by an unrelated `"gleam"` string
could false-positive. Replaced with a dependency-free balanced-call scanner
that finds each `snippetFromLiteral(` site, walks parentheses and template
literal depth to isolate the first argument, then inspects the second argument
token directly. Supports multiline template literals with embedded expressions.

### 2. Source-file identity in marker inventory

`scanAllMarkers` now returns per-file occurrence records (`MarkerOccurrence[]`
per ID) instead of merging across files. This enables direct diagnostics for:
- **Start/end split across files:** start in one `.gleam`, end in another.
- **End-before-start (reversed pair):** end marker on a lower line than start
  in the same file.

Both are surfaced as structured diagnostics and tested by dedicated negative
mutation cases.

### 3. Scope bypass closed — all authored modules scanned

Gates 3 (literal Gleam policy) and 6 (unregistered Gleam imports) now scan
**all authored website source modules** (`src/**/*.astro`, `src/**/*.ts`),
excluding tests and the extractor implementation, rather than only
`src/pages/**/*.astro`. A new `src/data/*.ts` or `src/components/*.ts` module
can no longer evade the gates. Exempt files are controlled by
`GATE_EXEMPT_PATTERNS`.

## Allowlists and policy

### LITERAL_GLEAM_ALLOWLIST

Pages that may use `snippetFromLiteral` with `"gleam"` — each has illustrative
Gleam without compiled source:

| Page | Reason |
|------|--------|
| `src/pages/guide/connect.astro` | watershed_beam comparison |
| `src/pages/guide/votes.astro` | lossy counter illustration |
| `src/pages/guide/testing.astro` | scripted delivery illustration |
| `src/pages/runtime/presence.astro` | presence config illustration |

A reverse check ensures every allowlisted page actually uses literal Gleam,
preventing stale allowlist entries.

### SNIPPET_DESCRIPTOR_FILES

Files that use `?raw` imports with snippet extractors:

- `src/data/practice-snippets.ts` — centralized practice registry
- `src/data/standalone-snippets.ts` — centralized standalone registry
- 8 Astro pages with direct extraction

### MARKER_SOURCE_DIRS

Directories scanned for docs markers: `examples/`, `tools/website-samples/`,
`src/`, `watershed_lustre/src/`.

### GATE_EXEMPT_PATTERNS

Files excluded from scope-wide gates (they define or test the snippet system):

- `*.test.ts` — test suites
- `drift-gates.test.*` — this file
- `*/lib/snippet.ts` — the extractor implementation
- `*/lib/snippet-markers.test.*` — marker test suite

### Non-Gleam literal distinction

The gates distinguish external illustrative TypeScript, shell, TOML, and text
literals from local Gleam. Only `"gleam"` language triggers the literal policy
gate. The balanced-call scanner in `hasLiteralGleamCall` inspects the actual
second argument of each individual `snippetFromLiteral(...)` call.

## Negative tests (mutation cases)

| Gate | Mutation | Proved by |
|------|----------|-----------|
| Source path | Fabricated nonexistent path | `rejects a nonexistent path` |
| Marker uniqueness | Duplicate start marker | `catches duplicate start markers` |
| Marker uniqueness | Duplicate end marker | `catches duplicate end markers` |
| Marker completeness | Missing end | `catches missing end marker` |
| Marker completeness | Missing start | `catches missing start marker` |
| Marker structure | Start/end split across files | `detects start/end split across files` |
| Marker structure | Reversed pair (end before start) | `detects end-before-start (reversed pair)` |
| Literal Gleam | `snippetFromLiteral(..., "gleam", ...)` | `detects snippetFromLiteral with gleam language` |
| Literal Gleam | Multiline template literal | `detects multiline snippetFromLiteral with gleam` |
| Literal Gleam | Template literal with expressions | `detects gleam in multiline template literal with embedded expressions` |
| Literal Gleam | Non-Gleam then unrelated "gleam" | `does not false-positive on non-Gleam literal followed by unrelated gleam string` |
| Literal Gleam | New data module with literal call | `catches literal Gleam call in a hypothetical new data module` |
| Literal Gleam | TypeScript not flagged | `ignores snippetFromLiteral with typescript language` |
| Literal Gleam | Shell not flagged | `ignores snippetFromLiteral with sh language` |
| Literal Gleam | TOML not flagged | `ignores snippetFromLiteral with toml language` |
| Literal Gleam | Text not flagged | `ignores snippetFromLiteral with text language` |
| Source path empty | Empty string in paths | `rejects empty string as a valid path` |
| Scope bypass | Raw Gleam import in unknown module | `detects ?raw .gleam import in unknown module` |

## Command wiring

### Website prebuild

`package.json` `prebuild` script now runs drift gates before `astro build`:

```
cd .. && gleam build --target javascript && ... && cd ../website && node --strip-types --test src/data/drift-gates.test.ts
```

### Root justfile

New `_test-website-snippets` recipe added to the `test` dependency chain:

```
test: _test-gleam _test-js _test-compile-fail _test-website-snippets
```

The recipe runs all five snippet test suites:
`test:snippet`, `test:snippet-markers`, `test:practice-snippets`,
`test:standalone-snippets`, `test:drift-gates`.

## Validation

- 321 drift gate tests pass (up from 206)
- 88 existing snippet tests pass (21 + 11 + 26 + 30)
- `pnpm build` — 36 pages built, 0 errors
- Total: 409 tests pass across all snippet test suites

## Files changed (2)

| File | Change |
|------|--------|
| `website/src/data/drift-gates.test.ts` | Balanced-call scanner, per-file marker inventory, full-scope module scan, 7 new mutation tests |
| `.superpowers/sdd/plan/task-6-report.md` | Updated to reflect review fixes |

## Concerns

- **Combined descriptors.** The `combine()` helper in `practice-snippets.ts`
  preserves the first snippet's origin (always definition or marker), so all
  combined descriptors are source-backed by construction. Gate 6 verifies this
  by checking practice-snippets.ts has no `snippetFromLiteral` calls at all.
  The origin model was not changed — the existing behavior is sufficient.

- **`excerpt()` still has no production callers.** Deprecated since Task 3.
  The drift gates do not exercise it.

- **Prebuild latency.** The drift gate suite adds ~600ms to `pnpm build`.
  This is acceptable for a build-time check; the gates run before Astro
  starts and fail fast on the first broken gate.

- **Marker orphan check scope.** The orphan check covers
  `examples/`, `tools/website-samples/`, `src/`, and `watershed_lustre/src/`.
  Markers in other directories (if any were added) would not be detected. This
  matches the current marker source surface.

- **Template literal parser depth.** The balanced-call scanner handles nested
  template expressions (`${...}`) and quoted strings inside arguments, but does
  not handle tagged template literals or deeply unusual AST shapes. All current
  call sites in the codebase use simple template literals or string literals and
  pass the scanner's mutation tests.
