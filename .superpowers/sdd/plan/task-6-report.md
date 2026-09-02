# Task 6 report — generate manifests before docs

## Summary

Reconciled command wiring to the approved public names, moved marker
enforcement fully into Gleam, relocated the watershed-specific config test out
of the generic package, and added the generate-from-scratch and atomic
preservation integration tests.

653 lines deleted, 237 added (net −416). The generic `tools/source-snippets`
package no longer knows about watershed pages, paths, or id inventories.

## Command wiring

| Surface | Before | After |
| --- | --- | --- |
| `website/package.json` | `pnpm snippets` | `pnpm generate:snippets` (canonical) |
| `justfile` | `just website-snippets` | `just snippets` (canonical), `website-snippets` alias retained |
| `predev` | `pnpm snippets` | `pnpm generate:snippets` |
| `prebuild` | `pnpm snippets` | `pnpm generate:snippets` |
| `_test-website-snippets` | depends on `website-snippets` | depends on `snippets`, runs `test:snippet-config` |

## Marker enforcement moved to Gleam

Gate 2 (marker integrity) removed from `drift-gates.test.ts`. It duplicated
validation the Gleam generator already performs during `generate:snippets`:
marker uniqueness, start/end pairing, cross-file splits, reversed pairs, and
orphan markers. These are now caught at generation time, before the manifest
is written.

Removed helpers: `findGleamFiles`, `findRepositoryGleamFiles`, `parseMarkers`,
`scanAllMarkers`, `collectMarkerReferences`, `configuredMarkers`,
`configuredMarkerSources`, `MARKER_SOURCE_DIRS`, `MarkerOccurrence` interface.
Also removed the dead `findAstroPages` helper (dead since `e888a76`).

Removed import: `execFileSync` from `node:child_process`.

## Retained frontend gates

| Gate | Purpose |
| --- | --- |
| 1 | Every rendered snippet id is declared and generated |
| 3 | Literal Gleam only on allowlisted pages |
| 4 | Registries are source-backed |
| 5 | Only the loader reads the generated manifest |
| 6 | No `?raw` imports of `.gleam` or `.mjs` |
| 8 | Only SnippetBlock renders Astro `<Code>` |
| 9 | Snippets built by the extractor, never by hand |
| 10 | Config entries select markers or whole file, not both |

## Generic package cleanup

`watershed_config_test.gleam` removed from `tools/source-snippets/test/`.
It hardcoded watershed page names, area counts, and the 78-id inventory.
The generic package tests (98 passing) exercise extraction, config decoding,
generation, and the CLI without referencing any repository-specific content.

## New integration test

`website/scripts/snippet-config.test.mjs` — 11 assertions in 4 suites:

### Configuration resolves to the repository (3 tests)
- `sourceRoot` resolves to a directory with `gleam.toml` and `examples/`
- Every `markerRoot` exists
- Extensions include `.gleam` and `.mjs`

### Inventory counts by area (5 tests)
- Guide and foundations: 51
- Practices: 17
- Homepage/runtime/p2p: 3
- SharedTree: 7
- Total: 78

### Generate from scratch (1 test)
- Deletes the manifest, regenerates via the real CLI, verifies:
  - The manifest exists afterward
  - Version is 1
  - Generated ids match configured ids exactly
  - Every entry has non-empty code with no leaked marker directives

### Atomic preservation (2 tests)
- Generates a good manifest, mutates the `retro-app-assemble` end marker,
  attempts regeneration (which fails), then verifies the prior manifest
  content is byte-identical.

Wired into `pnpm test:snippet-config` and `just _test-website-snippets`.

## Trellis exclusions (verified, no changes needed)

| Exclusion | `tools/source-snippets` | Correct |
| --- | --- | --- |
| `@release` | excluded | internal tool, not a product |
| `test` | NOT excluded | has tests that run on Erlang |
| `build-erlang` | NOT excluded | targets Erlang |
| `build-javascript` | excluded | targets Erlang, not JS |
| `bundle` | excluded | no `pnpm run build` script |

## Builds and tests

| Command | Result |
| --- | --- |
| `just snippets` | generated |
| `pnpm generate:snippets` | generated |
| `cd tools/source-snippets && gleam test` | 98 passed, no failures |
| `just _test-website-snippets` | 1853 passed across 9 suites, 0 failures |
| `cd website && pnpm build` | prebuild + build, 36 pages |
| `just lint` | clean across every package |

Suite breakdown:

| Suite | Tests |
| --- | --- |
| `test:snippet` | 31 |
| `test:snippet-manifest` | 172 |
| `test:practice-snippets` | 29 |
| `test:standalone-snippets` | 39 |
| `test:drift-gates` | 898 |
| `test:copy-gates` | 667 |
| `test:global-styles` | 1 |
| `test:netlify-contract` | 5 |
| `test:snippet-config` | 11 |
| **Total** | **1853** |

## Commit

`0c636f4` — `build(snippets): generate manifests before docs`

## Concerns

1. **The `website-snippets` alias is retained.** Other documentation or
   scripts outside the repository may reference it. The alias adds one line
   and avoids a breaking change for anyone with muscle memory.

2. **The 78-id two-way check is now split across two surfaces.** The drift
   gates enforce that every rendered id is configured and vice versa (Gate 1).
   The integration test enforces the 78-count inventory by area. Neither is
   redundant: Gate 1 catches a missing rendered id, the integration test
   catches a category of id that was never rendered at all.

3. **The atomic preservation test mutates a real fixture.** It picks the first
   marker-based snippet in the config, removes its end marker, and restores
   it in the `after` hook. A crash between the write and the restore would
   leave a broken source file. The risk is low — the test is single-threaded
   and the fixture is version-controlled — but it is worth knowing.

4. **`findAstroPages` was dead code since `e888a76`.** Removed in this task
   rather than carried further.

---
