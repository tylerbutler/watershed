# Task 4 report — mark every source-backed website snippet and declare the manifest

## Summary

Every snippet the website builds from real source is now a named marker range
declared in `website/snippets.json`. Seventy new marker pairs wrap definitions
the TypeScript extractor used to find by matching a head line; twenty-three
existing pairs are untouched; one existing pair (`sharedtree-nest`) was split
because another sheet quotes part of the same block. The configuration holds
77 output ids over 94 markers in 31 files, and the generator turns it into a
complete manifest.

The frontend still runs the TypeScript extractor — Task 5 replaces it — so this
task also had to leave every rendered code string exactly as it was. It does,
with one deliberate exception recorded under Parity.

## Configuration

`website/snippets.json`

- `sourceRoot` is `..`, relative to the configuration file, so it resolves to
  the repository root.
- `markerRoots` names 35 authored source directories: `src`, `test`,
  `watershed_lustre/src`, `watershed_lustre/test`, `tools/website-samples/src`,
  and the `src`/`test` directory of every example package.
- `extensions` is `[".gleam", ".mjs"]`.
- One snippet carries a separator: `practice-unsettled-writes` keeps
  `"\n\n// ... and in the register event handler:\n"` exactly.

Marker roots are named per package rather than as `examples` because a built
package holds `build/dev/javascript/<pkg>/**/audio_ffi.mjs`, a verbatim copy of
the marked FFI module. Scanning `examples` whole would report the marker twice
and fail generation on any machine that has run `just build`.

## Complete mapping

| output id | source | markers |
| --- | --- | --- |
| `foundations-lifecycle-assemble` | `examples/retro_tutorial_lustre/src/retro_tutorial_lustre.gleam` | `retro-app-assemble` |
| `foundations-lifecycle-bootstrap` | `examples/retro_tutorial_lustre/src/retro_tutorial_lustre.gleam` | `retro-app-bootstrap-effect` |
| `foundations-lifecycle-connect` | `watershed_lustre/src/watershed_lustre.gleam` | `watershed-lustre-connect` |
| `foundations-lifecycle-ensure-channel` | `src/watershed.gleam` | `watershed-ensure-channel` |
| `foundations-lifecycle-ensured-arms` | `examples/retro_tutorial_lustre/src/retro_tutorial_lustre.gleam` | `lifecycle-ensured-arms` |
| `foundations-lifecycle-readiness` | `examples/retro_tutorial_lustre/src/retro_tutorial_lustre.gleam` | `update-readiness` |
| `foundations-schema-channel-field-type` | `src/watershed/schema.gleam` | `schema-channel-field-type` |
| `foundations-schema-child-field-type` | `src/watershed/schema.gleam` | `schema-child-field-type` |
| `foundations-schema-field-error` | `src/watershed/schema.gleam` | `schema-field-error` |
| `foundations-schema-field-type` | `src/watershed/schema.gleam` | `schema-field-type` |
| `foundations-schema-get-field` | `src/watershed.gleam` | `watershed-get-field` |
| `foundations-schema-player-schema` | `examples/scoreboard_cli/src/scoreboard_cli.gleam` | `scoreboard-player-schema` |
| `foundations-schema-stamp` | `src/watershed.gleam` | `watershed-stamp` |
| `foundations-schema-sudoku-fields` | `examples/sudoku_lustre/src/sudoku_lustre/document_schema.gleam` | `sudoku-schema-cells`, `sudoku-schema-notes`, `sudoku-schema-givens`, `sudoku-schema-mistakes` |
| `foundations-schema-text-child` | `examples/showcase_lustre/src/showcase_lustre/document_schema.gleam` | `showcase-schema-text` |
| `foundations-schema-title-field` | `examples/retro_tutorial_lustre/src/retro_tutorial_lustre/document_schema.gleam` | `retro-schema-title` |
| `foundations-topology-create-map` | `src/watershed.gleam` | `watershed-create-map` |
| `foundations-topology-handle-of` | `src/watershed.gleam` | `watershed-handle-of` |
| `foundations-topology-resolve` | `src/watershed.gleam` | `watershed-resolve` |
| `foundations-topology-resolve-child` | `src/watershed.gleam` | `watershed-resolve-child` |
| `foundations-topology-root-typed` | `src/watershed.gleam` | `watershed-root-typed` |
| `guide-connect-assemble` | `examples/retro_tutorial_lustre/src/retro_tutorial_lustre.gleam` | `retro-app-assemble` |
| `guide-connect-bootstrap` | `examples/retro_tutorial_lustre/src/retro_tutorial_lustre.gleam` | `retro-app-bootstrap-effect` |
| `guide-connect-dev-constants` | `examples/retro_tutorial_lustre/src/retro_tutorial_lustre.gleam` | `guide-connect-dev-constants` |
| `guide-connect-init` | `examples/retro_tutorial_lustre/src/retro_tutorial_lustre.gleam` | `retro-app-init` |
| `guide-connect-main` | `examples/retro_tutorial_lustre/src/retro_tutorial_lustre.gleam` | `retro-app-main` |
| `guide-connect-readiness` | `examples/retro_tutorial_lustre/src/retro_tutorial_lustre.gleam` | `update-readiness` |
| `guide-notes-add-clicked` | `examples/retro_tutorial_lustre/src/retro_tutorial_lustre.gleam` | `guide-notes-add-clicked` |
| `guide-notes-add-note` | `examples/retro_tutorial_lustre/src/retro_tutorial_lustre/board.gleam` | `retro-board-add-note` |
| `guide-notes-codec` | `examples/retro_tutorial_lustre/src/retro_tutorial_lustre/note.gleam` | `retro-note-to-json`, `retro-note-from-register` |
| `guide-notes-note-entries` | `examples/retro_tutorial_lustre/src/retro_tutorial_lustre/board.gleam` | `retro-board-note-entries` |
| `guide-notes-note-record` | `examples/retro_tutorial_lustre/src/retro_tutorial_lustre/note.gleam` | `retro-note-type`, `retro-note-id` |
| `guide-notes-ordering` | `examples/retro_tutorial_lustre/src/retro_tutorial_lustre/board.gleam` | `retro-board-notes-in-column`, `retro-board-by-created-then-id` |
| `guide-notes-unfiled` | `examples/retro_tutorial_lustre/src/retro_tutorial_lustre/board.gleam` | `retro-board-unfiled` |
| `guide-presence-announce` | `examples/retro_tutorial_lustre/src/retro_tutorial_lustre.gleam` | `retro-app-announce-focus` |
| `guide-presence-effect` | `examples/retro_tutorial_lustre/src/retro_tutorial_lustre.gleam` | `retro-app-presence-effect`, `retro-app-current-presence` |
| `guide-presence-events` | `examples/retro_tutorial_lustre/src/retro_tutorial_lustre.gleam` | `guide-presence-events` |
| `guide-presence-focus-clicked` | `examples/retro_tutorial_lustre/src/retro_tutorial_lustre.gleam` | `guide-presence-focus-clicked` |
| `guide-presence-focus-names` | `examples/retro_tutorial_lustre/src/retro_tutorial_lustre.gleam` | `retro-app-focus-names` |
| `guide-presence-payload` | `examples/retro_tutorial_lustre/src/retro_tutorial_lustre.gleam` | `retro-app-presence-type`, `retro-app-encode-presence`, `retro-app-presence-decoder` |
| `guide-presence-remote-peers` | `examples/retro_tutorial_lustre/src/retro_tutorial_lustre.gleam` | `retro-app-remote-peers` |
| `guide-testing-add-race` | `examples/retro_tutorial_lustre/test/convergence_test.gleam` | `retro-convergence-add-race` |
| `guide-testing-board-of` | `examples/retro_tutorial_lustre/test/convergence_test.gleam` | `retro-convergence-board-of` |
| `guide-testing-room` | `examples/retro_tutorial_lustre/test/convergence_test.gleam` | `retro-convergence-room`, `retro-convergence-channels-of` |
| `guide-testing-vote-race` | `examples/retro_tutorial_lustre/test/convergence_test.gleam` | `retro-convergence-vote-race` |
| `guide-votes-card` | `examples/retro_tutorial_lustre/src/retro_tutorial_lustre/board.gleam` | `retro-board-card` |
| `guide-votes-orphan-test` | `examples/retro_tutorial_lustre/test/board_test.gleam` | `retro-board-test-orphan-tallies` |
| `guide-votes-vote-clicks` | `examples/retro_tutorial_lustre/src/retro_tutorial_lustre.gleam` | `guide-votes-vote-clicks` |
| `guide-votes-vote-entries` | `examples/retro_tutorial_lustre/src/retro_tutorial_lustre/board.gleam` | `retro-board-vote-entries` |
| `guide-votes-vote-ops` | `examples/retro_tutorial_lustre/src/retro_tutorial_lustre/board.gleam` | `retro-board-upvote`, `retro-board-downvote`, `retro-board-change-votes` |
| `homepage-beam` | `examples/dice_cli/src/dice_cli.gleam` | `homepage-beam` |
| `optimistic-local` | `tools/website-samples/src/website_samples/optimistic_sample.gleam` | `optimistic-local` |
| `p2p-config` | `tools/website-samples/src/website_samples/p2p_sample.gleam` | `p2p-config` |
| `practice-anchors-not-offsets` | `examples/text_lustre/src/text_lustre/component.gleam` | `practice-anchors-refresh-anchor` |
| `practice-authoritative-channel` | `examples/retro_board_lustre/src/retro_board_lustre/board.gleam` | `practice-authoritative-render-column` |
| `practice-claims-seeding` | `examples/sudoku_lustre/src/sudoku_lustre/component.gleam` | `practice-claims-seed-givens` |
| `practice-deterministic-death` | `examples/work_queue_lustre/test/queue_semantics_test.gleam` | `practice-deterministic-death-test` |
| `practice-diagnostics-first` | `examples/dice_lustre/src/dice_lustre.gleam` | `practice-diagnostics-line` |
| `practice-fallible-edits` | `examples/playlist_lustre/src/playlist_lustre/component.gleam` | `practice-fallible-move`, `practice-fallible-mutate`, `practice-fallible-record` |
| `practice-ffi-surface` | `examples/pixel_canvas_lustre/src/pixel_canvas_lustre.gleam` | `practice-ffi-connected` |
| `practice-presence-idiom` | `examples/retro_tutorial_lustre/src/retro_tutorial_lustre.gleam` | `retro-app-presence-effect`, `retro-app-remote-peers` |
| `practice-protocol-on-ripples` | `examples/grocery_triptych_lustre/src/grocery_triptych_lustre/scenario_protocol.gleam` | `practice-protocol-matches-run`, `practice-protocol-from-self`, `practice-protocol-should-acknowledge` |
| `practice-pure-modules` | `examples/grocery_triptych_lustre/src/grocery_triptych_lustre/refresh_guard.gleam` | `practice-pure-state`, `practice-pure-idle`, `practice-pure-request`, `practice-pure-flush` |
| `practice-quorum-pending-roster` | `examples/drum_machine_lustre/src/drum_machine_lustre.gleam` | `practice-quorum-pending` |
| `practice-realtime-out-of-band` | `examples/drum_machine_lustre/src/drum_machine_lustre/audio_ffi.mjs` | `practice-realtime-tick` |
| `practice-relay-decorator` | `examples/clap_counter_lustre/src/clap_counter_lustre.gleam` | `practice-relay-config`, `practice-relay-with-relay` |
| `practice-shared-core-two-runtimes` | `examples/dice_cli/src/dice_cli.gleam` | `practice-shared-core-event-loop` |
| `practice-stamp-schema` | `examples/scoreboard_cli/src/scoreboard_cli.gleam` | `practice-stamp-schema` |
| `practice-typedmap-panels` | `examples/showcase_lustre/src/showcase_lustre.gleam` | `practice-typedmap-bootstrap-effect` |
| `practice-unsettled-writes` | `examples/tournament_bracket_lustre/src/tournament_bracket_lustre.gleam` | `practice-unsettled-report`, `practice-unsettled-atomic` · separator `\n\n// ... and in the register event handler:\n` |
| `sharedtree-bootstrap` | `tools/website-samples/src/website_samples/board_app.gleam` | `sharedtree-bootstrap` |
| `sharedtree-declare` | `tools/website-samples/src/website_samples/board_schema.gleam` | `sharedtree-declare` |
| `sharedtree-events` | `tools/website-samples/src/website_samples/board_app.gleam` | `sharedtree-events` |
| `sharedtree-nest` | `examples/sudoku_lustre/src/sudoku_lustre/document_schema.gleam` | `sudoku-schema-head`, `sudoku-schema-cells`, `sudoku-schema-notes`, `sudoku-schema-givens`, `sudoku-schema-mistakes` |
| `sharedtree-per-kind` | `examples/sudoku_lustre/src/sudoku_lustre/component.gleam` | `sharedtree-per-kind` |
| `sharedtree-read-write` | `tools/website-samples/src/website_samples/board_app.gleam` | `sharedtree-read-write` |
| `sharedtree-record` | `tools/website-samples/src/website_samples/board_app.gleam` | `sharedtree-record` |

Nine markers are referenced by two outputs each: `update-readiness`,
`retro-app-bootstrap-effect`, `retro-app-assemble`, `retro-app-presence-effect`,
`retro-app-remote-peers`, and the four `sudoku-schema-*` channel fields. That is
allowed by design — one range, two sheets.

## Marker placement rules applied

- A start marker sits above the definition's `///` doc comment, so the doc
  comment is part of the snippet, exactly as the old extractor rendered it.
- Noncontiguous definitions get one marker each, and the output lists them in
  order rather than swallowing the code between them. `guide-votes-vote-ops`,
  for example, is three markers, not one range over `upvote`, `downvote`, and
  whatever sits between them.
- `sharedtree-nest` was one range covering the Sudoku schema's tag, two plain
  fields, and four channel fields. The schema sheet quotes only the four
  channel fields, and ranges cannot nest, so the block is now five adjacent
  ranges: `sudoku-schema-head` plus the four fields. Both outputs compose from
  those ranges and render byte-identical code.
- The JavaScript `tick` function in
  `examples/drum_machine_lustre/src/drum_machine_lustre/audio_ffi.mjs` carries
  `practice-realtime-tick`, and `.mjs` is a configured extension.

## RED → GREEN

RED — `tools/source-snippets/test/source_snippets/watershed_config_test.gleam`
written first, before any marker or configuration existed:

```
79 passed, 8 failures
let assert Ok(text) = simplifile.read(config_path)   value: Error(Enoent)
let assert Ok(generated) = generator.generate(config_path)
    value: Error(ConfigReadError("../../website/snippets.json"))
```

The eight failures are the new tests: configuration decodes, source root
resolves to the repository root, every marker root exists, the complete
77-id inventory, the per-area counts (50 guide/foundations, 17 practices,
3 homepage/runtime, 7 SharedTree), every configured source file exists,
generation produces the same 77 ids, and every generated snippet holds
marker-free code.

GREEN — after the markers and `website/snippets.json`:

```
cd tools/source-snippets && gleam test
87 passed, no failures
```

## Parity method and results

Two independent comparisons, both run from a descriptor table that mirrors
every `snippetFromDefinition`, `snippetFromMarker`, and `combineSnippets` call
in the registries and the guide, foundations, and runtime pages.

1. **Frontend parity.** The current `snippet.ts` was run over the sources
   before and after marking, for all 77 outputs. Result: 77 of 77 identical.
   This is what keeps the live site honest until Task 5 lands.
2. **Generator parity.** `gleam run -m source_snippets/cli -- ../../website/snippets.json <tmp>`
   produced a manifest whose `code` values were compared with the same
   baseline. Result: 69 of 77 byte-identical; 8 differ by exactly one added
   leading line, `@target(javascript)`.

The eight are `foundations-topology-{root-typed,handle-of,create-map,resolve,resolve-child}`,
`foundations-schema-{get-field,stamp}`, and `foundations-lifecycle-ensure-channel`
— all in `src/watershed.gleam`. `gleam format` binds a comment to the item
below it, so a start marker written between `@target(javascript)` and its doc
comment moves above the attribute and the attribute joins the range. The old
extractor silently dropped that line because it only walked up over `//`
comments. Including it is the more accurate rendering of the definition, and
the difference is one line in each case with the rest byte-identical. Nothing
in the generated JSON was hand-edited.

Two boundaries were fixed rather than worked around: the nested
`sharedtree-nest` range (split into five), and the whole-file schema listing on
`guide/connect` (below).

## Changes outside the sources and the configuration

The brief scoped this task to sources plus the configuration. Four frontend
edits were needed to keep the branch honest at this commit:

1. `website/src/lib/snippet.ts` — `extractDefinition` now stops its comment
   walk at a marker directive. Without it, every marker placed above a doc
   comment would be quoted back to the reader as part of the definition. The
   guard is what makes frontend parity 77 of 77.
2. `website/src/lib/snippet.ts` — new `sourceWithoutMarkers`, used by the
   whole-file schema listing on `guide/connect`. That listing renders
   `document_schema.gleam` verbatim, and the file now carries the
   `retro-schema-title` pair. A marker range cannot cover the whole file: the
   formatter moves a directive written above a `////` module doc comment below
   it, which would drop the header from the listing. Stripping the directives
   reproduces the file as it stood before this task, verified byte-for-byte
   against `git show HEAD:`.
3. `website/src/data/standalone-snippets.ts` (and its test) — `sharedtree-nest`
   composes the five adjacent ranges.
4. `website/src/data/drift-gates.test.ts` — `collectMarkerReferences` now also
   reads `website/snippets.json`, which is a descriptor: it names every marker
   the generator composes. Without this the orphan gate fails for all 70 new
   markers. The "referenced marker exists" gate checks a non-`.gleam` marker
   against its own source, because the Gleam scan cannot see the FFI module.
   The repo-wide scan now skips `tools/source-snippets/`, which was already
   failing the gate at `b1209ce`: the generator package is build tooling, and
   its suite writes synthetic marker fixtures that nothing quotes.

`tools/source-snippets/README.md` marker placement guidance was corrected: it
told the reader to put the start marker below the doc comment, which is the
opposite of this repository's convention and of what the formatter produces.

## Builds and tests

| Command | Result |
| --- | --- |
| `cd tools/source-snippets && gleam test` | 87 passed, no failures |
| `cd tools/source-snippets && gleam format --check src test` | clean |
| `trellis run build-erlang` | 4 packages ok |
| `trellis run build-javascript` | 19 packages ok |
| `trellis run test` | 15 packages ok, every suite green |
| `just _test-website-snippets` | 23 + 11 + 29 + 30 + 885 + 667 + 1 passed, 0 failed |
| `just lint` | 23 packages ok |
| `cd website && pnpm build` | 36 pages, complete |
| `grep -ro 'docs:snippet' website/dist` | 0 matches |

External Hex behaviour, not hidden: the first two `trellis run build-javascript`
runs reported `FAILED` for packages whose dependency resolution had not been
cached, each after ~62 seconds — the same Hex API limit recorded in the
baseline. Every one of them built on a later run with no source change; the
third full fan-out was green across all nineteen packages. `showcase_lustre`
still pays a 63 second resolution cost on a cold cache.

## Self-review

- Every source diff is an insertion of comment lines. The only deletions in any
  `.gleam` or `.mjs` file are the two `sharedtree-nest` directive lines, and
  the code they wrapped is unchanged.
- All 24 changed source files pass `gleam format --check`, and the markers were
  re-validated after formatting: 83 balanced pairs across changed files, no
  nesting, no duplicates, no unterminated ranges.
- No generated JSON is committed. The manifest was written to a scratch path
  outside the repository; `website/src/generated/` is untouched, and
  `git status` shows only the intended files.
- Output ids are route- or practice-qualified and stable. Marker ids are
  source-qualified where two sheets share a range, so no id encodes which page
  happens to quote it today.
- The inventory is complete by construction: the descriptor table was checked
  against every extractor call in the registries and the eight pages, and the
  Gleam test pins all 77 ids plus per-area counts.

## Concerns

1. **`@target(javascript)` in eight snippets.** Documented above. It is a
   one-line improvement in fidelity, but it is a rendering change that lands
   when Task 5 switches the frontend to the manifest. Worth a look at the
   built `/foundations/topology` and `/foundations/schema` pages then.
2. **Marker roots are listed per package.** Thirty-five entries where five
   would do, because the generator's scan does not skip `build/` or
   `node_modules/`. A new example package needs its `src` and `test` added
   here, and nothing fails until a snippet quotes it. A generator-side ignore
   list would let the roots collapse back to `examples`.
3. **A whole-file listing cannot be a marker range.** The formatter will not
   keep a directive above a `////` module doc comment. Task 6 forbids
   `.gleam?raw` imports in authored modules, so the `guide/connect` schema
   listing needs an answer then — either a config entry that composes the file
   from adjacent ranges without its header, or a whole-file mode in the
   generator.
4. **The repository configuration test lives in the generic package.** As the
   plan specified, but it couples `source_snippets` to watershed's own layout:
   the suite now fails if `website/snippets.json` moves.
