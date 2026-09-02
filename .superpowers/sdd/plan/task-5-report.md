# Task 5 Report — Migrate standalone Gleam samples to source-backed descriptors

## Status: COMPLETE

**Commit:** `8d8aea7` — `feat(website): migrate standalone snippets to source-backed descriptors (Task 5)`

## Tests

- 86 pass, 0 fail (all snippet tests: snippet, snippet-markers, practice-snippets, standalone-snippets)
- 27 new tests in `standalone-snippets.test.ts`
- Website build: 36 pages, 0 errors

### RED/GREEN evidence

- **RED:** 10 failures before registry existed — `ERR_MODULE_NOT_FOUND` on
  missing `standalone-snippets.ts`, inline Gleam detected in all 4 surfaces,
  TS snippet import syntax not parseable in function scope.
- **GREEN:** All 27 tests pass after creating registry, fixture, markers,
  and migrating pages.

### Build evidence

- `pnpm build` — 36 pages, 0 errors, 4.77s
- `gleam build --target javascript` (fixture) — compiled, warnings only (unused functions expected)
- `gleam check` (dice_cli) — compiled
- `gleam check` (sudoku_lustre) — compiled

## Source mapping

| Snippet ID | Surface | Source file | Method |
|---|---|---|---|
| homepage-beam | CodeSample.astro | examples/dice_cli/src/dice_cli.gleam | marker |
| optimistic-local | runtime/optimistic.astro | tools/website-samples/src/website_samples/optimistic_sample.gleam | marker |
| p2p-config | runtime/p2p.astro | tools/website-samples/src/website_samples/p2p_sample.gleam | marker |
| sharedtree-declare | sharedtree.astro | tools/website-samples/src/website_samples/board_schema.gleam | marker |
| sharedtree-bootstrap | sharedtree.astro | tools/website-samples/src/website_samples/board_app.gleam | marker |
| sharedtree-read-write | sharedtree.astro | tools/website-samples/src/website_samples/board_app.gleam | marker |
| sharedtree-record | sharedtree.astro | tools/website-samples/src/website_samples/board_app.gleam | marker |
| sharedtree-events | sharedtree.astro | tools/website-samples/src/website_samples/board_app.gleam | marker |
| sharedtree-nest | sharedtree.astro | examples/sudoku_lustre/src/sudoku_lustre/document_schema.gleam | marker |
| sharedtree-per-kind | sharedtree.astro | examples/sudoku_lustre/src/sudoku_lustre/component.gleam | marker |
| ts-declare | sharedtree.astro | (literal) | explicit literal |
| ts-root | sharedtree.astro | (literal) | explicit literal |
| ts-read-write | sharedtree.astro | (literal) | explicit literal |
| ts-record | sharedtree.astro | (literal) | explicit literal |
| ts-nest | sharedtree.astro | (literal) | explicit literal |
| ts-events | sharedtree.astro | (literal) | explicit literal |
| ts-gaps | sharedtree.astro | (literal) | explicit literal |

## Fixture package

- `tools/website-samples/` — JavaScript-target Gleam package
- Dependencies: watershed (path), watershed_lustre (path), lustre, gleam_stdlib, gleam_json, gleam_javascript
- 4 source modules: board_schema, board_app, optimistic_sample, p2p_sample
- Trellis integration: excluded from @release, test, build-erlang, bundle; included in build-javascript

## Markers added (4 files)

| File | Marker ID |
|---|---|
| examples/dice_cli/src/dice_cli.gleam | homepage-beam |
| examples/sudoku_lustre/src/sudoku_lustre/document_schema.gleam | sharedtree-nest |
| examples/sudoku_lustre/src/sudoku_lustre/component.gleam | sharedtree-per-kind |
| tools/website-samples/src/website_samples/board_schema.gleam | sharedtree-declare |
| tools/website-samples/src/website_samples/board_app.gleam | sharedtree-bootstrap, sharedtree-read-write, sharedtree-record, sharedtree-events |
| tools/website-samples/src/website_samples/optimistic_sample.gleam | optimistic-local |
| tools/website-samples/src/website_samples/p2p_sample.gleam | p2p-config |

## TypeScript check mechanism

SharedTree TypeScript snippets use explicit `snippetFromLiteral` with `"typescript"`
language. Syntax checking uses `new Function(code)` in the test suite, which
verifies each snippet is parseable JavaScript (TypeScript types are runtime API
calls, not annotations). Import statements are stripped for the syntax check since
`import` is module-level-only syntax. `fluid-framework` is not added as a dependency.

## Files changed (19)

| File | Change |
|---|---|
| `examples/dice_cli/src/dice_cli.gleam` | +2 marker lines (homepage-beam) |
| `examples/sudoku_lustre/src/sudoku_lustre/document_schema.gleam` | +2 marker lines, +4 inline comments |
| `examples/sudoku_lustre/src/sudoku_lustre/component.gleam` | +2 marker lines (sharedtree-per-kind) |
| `gleam.toml` | Trellis exclusions for tools/website-samples |
| `tools/website-samples/.gitignore` | New: /build |
| `tools/website-samples/gleam.toml` | New: JS-target fixture package |
| `tools/website-samples/manifest.toml` | New: dependency manifest |
| `tools/website-samples/src/website_samples.gleam` | New: package root |
| `tools/website-samples/src/website_samples/board_schema.gleam` | New: Board phantom type + fields |
| `tools/website-samples/src/website_samples/board_app.gleam` | New: bootstrap, read/write, record, events |
| `tools/website-samples/src/website_samples/optimistic_sample.gleam` | New: optimistic set + get |
| `tools/website-samples/src/website_samples/p2p_sample.gleam` | New: CRDT config |
| `website/package.json` | +1 test:standalone-snippets script |
| `website/src/components/CodeSample.astro` | Replaced inline Gleam with registry lookup |
| `website/src/data/standalone-snippets.ts` | New: registry module (10 Gleam + 7 TS) |
| `website/src/data/standalone-snippets.test.ts` | New: 27 tests |
| `website/src/pages/runtime/optimistic.astro` | Replaced snippetFromLiteral with registry |
| `website/src/pages/runtime/p2p.astro` | Replaced snippetFromLiteral with registry |
| `website/src/pages/sharedtree.astro` | Replaced 7 inline Gleam consts + 7 inline TS consts with registry lookups |

## Self-review

- **All Gleam snippets source-backed:** Every handwritten Gleam string in the
  four target surfaces replaced with a marker extraction from compiled source.
- **One fixture package:** `tools/website-samples` is the single fixture for
  synthetic snippets. Homepage BEAM sample comes from existing dice_cli.
- **TypeScript stays literal:** SharedTree TypeScript uses explicit
  `snippetFromLiteral` with syntax checking. No fluid-framework dependency added.
- **Snippet intent preserved:** The extracted code demonstrates the same API
  patterns as the original handwritten strings. Minor differences: the homepage
  sample now shows the full dice_cli main+run flow instead of a condensed
  synthetic version; the sharedtree record snippet now includes the surrounding
  `write_card` function rather than bare `use` syntax.
- **No copy changes:** Prose on all pages untouched except the source note in
  sharedtree.astro's g-note block (updated to reflect fixture source).
- **SnippetBlock not used for sharedtree:** The sharedtree page uses a custom
  `st-pair` grid layout with paired Code blocks, not the standard SnippetBlock.
  CodeSample.astro also uses custom layout. Both use `Code code={snippet.code}`.

## Concerns

- **Homepage sample is longer.** The dice_cli marker captures main() + run(),
  which is ~50 lines vs the original 35-line synthetic sample. The original was
  a condensed fantasy showing a simplified flow; the real code is more verbose
  but honest. The figcaption was updated to say "examples/dice_cli · erlang
  target" instead of "examples · erlang + javascript targets."
- **sudoku_lustre document_schema inline comments.** Added inline comments
  (`// last write wins, per key`, etc.) to match the original snippet's editorial
  intent. These are accurate descriptions of each channel's merge policy.
- **Gleam compiler hint.** `gleam check` on sudoku_lustre shows "Move the
  comment above the doc comment" for the `// docs:snippet-start` marker placed
  before a `///` doc comment. This is a style hint, not an error, and is
  inherent to the marker-above-doc-comment pattern already used in Task 3/4.
- **`excerpt()` still has no production callers.** Deprecated since Task 3.
