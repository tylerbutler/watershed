# SDD ledger — plan: /home/tylerbu/.copilot/session-state/51d5454c-d724-451b-a9e6-5929993e8629/plan.md

Merge base: 70ded27
Spec: none; the approved plan is the authority.

## Preflight

| Task | Internal consistency | Shared interface |
| --- | --- | --- |
| 1. Snippet model and extractor | Tests precede implementation and cover all named validation cases. | Produces `Snippet`, definition extraction, and marker extraction for Tasks 2–6. |
| 2. Unified rendering | Descriptor is the only source for code, language, path, and URL. | Consumes Task 1; produces the rendering contract used by Tasks 3–5. |
| 3. Guide and concept migration | Whole definitions stay on `excerpt`; partial ranges move to markers; `section` is removed. | Consumes Tasks 1–2; shares example source files with Task 4. |
| 4. Practice migration | Catalog keeps prose; registry owns source imports and descriptors. | Consumes Tasks 1–2; shares marker conventions and source files with Task 3. |
| 5. Standalone compiled samples | Reuse examples first; one fixture package only for synthetic Gleam. | Consumes Tasks 1–2; produces the fixture inventory checked by Task 6. |
| 6. Drift gates | Checks only the final descriptor and marker conventions after migrations. | Depends on Tasks 3–5 and integrates with existing build/test commands. |
| 7. Stable copy claims | Removes unsupported precision without changing the website voice. | Runs after Tasks 3–5 so prose reflects final samples and paths. |
| 8. Validation | Commands and searches match the artifacts created by Tasks 1–7. | Depends on Tasks 6–7 and closes the branch. |
| Tasks 3 + 4 | Both can add markers to example source; ids must be unique within each file. | Ruling: use route/practice-qualified ids and let Task 4 preserve markers added by Task 3. Cost if wrong: duplicate marker failures during build. |
| Tasks 3–5 + 6 | Migration determines the literal allowlist that the gate enforces. | Ruling: derive the gate from explicit descriptor origins, not path-name heuristics. Cost if wrong: legitimate non-Gleam literals may be blocked or handwritten Gleam may escape detection. |
| Tasks 5 + 8 | A fixture package must be visible to Trellis before full validation. | Ruling: reuse an existing compiled example whenever possible; create one fixture package only for samples with no honest source home. Cost if wrong: unnecessary package maintenance or incomplete compilation coverage. |

Baseline: `just test` could not download Hex packages for nine example
projects. The core, `watershed_lustre`, `pixel_canvas_lustre`, and
`retro_tutorial_lustre` suites completed; the tutorial reported 10 passing
tests. Ruling: proceed with targeted tests and retry the complete suite during
final validation — the failures are dependency-fetch errors, not test
assertions. Cost if wrong: a pre-existing failure in an unavailable example
could be attributed to this branch later.

Task 1: fix round 1/5 (3 addressed, 0 open; commits 32adab3..5e6fd44)
Task 1: minor (deferred): `excerpt()` has no source-path argument; descriptor
migration will replace compatibility callers.
Task 1: complete (commits 70ded27..5e6fd44, review clean)
Task 2: Ruling: `devConstantsSnippet` may remain a transitional literal only
through Task 2 because Task 3 explicitly replaces every `section()` range with
named markers. Cost if wrong: the drift gate could misclassify extracted code.
Task 2: fix round 1/5 (2 addressed, 0 open; commits 681a836..f61bf2f)
Task 2: minor (deferred): extracted snippet URL ergonomics will be settled by
the full call-site migration rather than a speculative helper.
Task 2: complete (commits 5e6fd44..f61bf2f, review clean)
Task 3: complete (commit e97131b, review clean)
Task 4: complete (commit 31899fc, review clean)
Task 4: 17/17 practices migrated, 26 new tests, 8 markers across 6 files.
Task 4: `combine()` helper loses second extraction's origin — Task 6 gate
should treat combined descriptors as source-backed regardless.
Task 4: `excerpt()` still has no production callers (deprecated since Task 3).
Task 5: complete (commit 8d8aea7, review clean)
Task 5: 10 Gleam snippets migrated, 7 TS literals with syntax check, 27 new tests.
Task 5: One fixture package (tools/website-samples), Trellis-integrated.
Task 5: Homepage BEAM sample from dice_cli; sudoku_lustre for nest/per-kind.
Task 5: `excerpt()` still has no production callers (deprecated since Task 3).
Task 6: complete (commit 494f171, review pending)
Task 6: 7 drift gates, 206 tests, 12 negative/mutation cases.
Task 6: Wired into website prebuild and justfile test recipe.
Task 6: Explicit allowlists: 4 literal Gleam pages, 10 descriptor files, 4 marker dirs.
Task 6: `excerpt()` still has no production callers (deprecated since Task 3).
Task 7: complete (commit a0cdc15, review pending)
Task 7: 4 volatile counts replaced (Rigor, examples, testing); 1 banlist fix.
Task 7: 3 copy gates, 663 tests; wired into prebuild and justfile.
Task 7: `excerpt()` still has no production callers (deprecated since Task 3).
Task 6: `excerpt()` still has no production callers (deprecated since Task 3).
