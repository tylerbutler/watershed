# Task 10: Repository validation and documentation

## Status

Complete, with the independently reproduced root runtime-bootstrap baseline
failure recorded below. All website, deploy-contract, browser, build, lint,
and compile-fail gates passed. No subagents ran.

Validation date: 2026-09-19. Starting revision:
`ffda908` on `lustre-website-vertical-slice`.

## Changes

- Updated `website_lustre/README.md` for the complete native workflow, typed
  demo ownership, narrow FFI boundary, shared client build, snippets,
  validation, and historical rollback.
- Replaced obsolete `pnpm build` / `pnpm dev` instructions in the snippet
  contributor guide and the deleted rich-text demo path and shipped
  prerequisites in `docs/demo-ideas.md`.
- Marked the vertical-slice design's migration instructions as historical and
  linked the current workflow.
- Corrected `DESIGN.md` descriptions against shipped code and browser
  evidence: local font assets, the initial `SN 0` state, model-derived gauge
  strip, and retained per-structure state rather than one shared sequence
  stream. The survey-sheet direction and website copy remain unchanged.
- Kept the formatting-only change that `just format` made to
  `website_lustre/src/watershed_site/json_ot/view.gleam`. No behavior changed.
- Left the root `README.md` unchanged: it contains no obsolete Astro command.

Rollback source: `8a600a631d090338d6c4a6bf4a9047fed9c69e6e`, the last
revision containing `website/`, immediately before deletion in `3a4b75b`.
The README distinguishes source recovery from deployment: that revision
already uses the Lustre Netlify configuration. Prefer redeploying a
known-good historical artifact; an Astro rebuild needs a separate historical
checkout and the old build/deploy settings. This task did not deploy or
exercise a production rollback.

## Fresh command evidence

| Command | Result |
| --- | --- |
| `test ! -d website` | PASS |
| `! rg 'website/src\|astro-island\|@vite' website_lustre/src website_lustre/scripts tools/build-website-lustre.sh` | PASS; no matches |
| `git ls-files 'website/**' '*.astro'` | No tracked legacy tree or Astro pages |
| Extended active-source/build scan | PASS; no Astro, Vite, or old site paths in native sources, scripts, dependency files, Netlify config, workflow, or justfile |
| `just format` | PASS; one formatting-only source correction |
| `just website-lustre` | PASS |
| `(cd website_lustre && gleam test --target javascript)` | PASS; 190 tests |
| `node --test website_lustre/test/*.test.mjs` | PASS; 5 tests, no skips |
| `node --test website_lustre/test/netlify-deploy-contract.test.mjs` | PASS; 3 tests |
| `(cd website_lustre && CI=true pnpm run smoke)` | PASS; all 24 browser programs |
| `just build` | PASS; repository target builds, example bundles, and native website |
| `just lint` | PASS; full repository formatting check |
| `CI=true just test` | Baseline failure after passing preceding suites; details below |
| `just _test-compile-fail` | PASS; both invalid fixtures rejected with their expected type errors |
| `CI=true just _test-website-lustre` | PASS; fresh rebuild, 190 Gleam tests, 5 Node tests, all 24 browser programs |
| Final `just lint` and `git diff --check` | PASS |

The browser runs used the existing CI launch mode because this host lacks a
usable Chromium sandbox. `CI=true` also prevents a missing browser from
silently skipping the tests. No browser program skipped.

Tools: Gleam 1.18.1, Node 24.19.0, site pnpm 11.13.1, just 1.58.0.

The generated artifact contains **42 HTML pages and three redirects** for
the old foundations component, port, and workspace URLs. A comparison with
the last Astro tree accounted for all 45 historical page URLs. The previous
reports' count of 43 was not reused. Generated JS/CSS totals from the final
website gate: **1,471,100 bytes raw; 373,376 bytes gzip**, below the
2,200,000 / 520,000-byte limits. The deployment-filter contract follows all
eleven public entries into their non-hidden dependencies.

## Root baseline reproduction

`CI=true just test` passed the Trellis package suites, including 1,550 root
BEAM tests, then passed all 1,827 root JavaScript tests. It failed in the
next command, `node smoke/runtime_bootstrap.mjs`:

```text
AssertionError [ERR_ASSERTION]: Missing HTTP request /trees/
  at take (.../watershed/runtime_bootstrap_ffi.mjs:34:12)
  at start (.../watershed/runtime_bootstrap_ffi.mjs:42:5)
  at async run (.../watershed/runtime_bootstrap_ffi.mjs:48:35)
```

Reproduced from a new detached worktree at unchanged local `main`:

```sh
git worktree add --detach <evidence-parent>/task-10-main main
cd <evidence-parent>/task-10-main
git rev-parse HEAD
# ca36de7ec0278a0ae16323553177bd31f1dfebc9
git status --porcelain
# empty
gleam build --target javascript
# exit 0
node smoke/runtime_bootstrap.mjs
# exit 1: the same Missing HTTP request /trees/ assertion and stack
git status --porcelain
# empty
```

`smoke/runtime_bootstrap.mjs`, its Gleam harness and FFI, and
`src/watershed/runtime.gleam` also have no diff against that `main`.
No baseline code or test changed. The temporary worktree was removed after
recording the reproduction.

The root command stops before its compile-fail and website recipes, so both
ran separately and passed. This is not a claim that `just test` is green.

## Desktop/mobile inspection

DEGRADED: single-context design assessment, as requested; no subagents.

Built output was served through the existing loopback static-server helper.
The inspection verified the server's HTTP response, opened a fresh page for
each route/viewport, waited for fonts and mounted controls, captured full-page
and top/demo screenshots, and collected console, page-error, response, and
request-failure events. Desktop was 1440 x 1000; mobile was 390 x 844 with
touch emulation. Direct image inspection covered all eight route pairs.

| Route | Desktop and mobile evidence |
| --- | --- |
| `/` | Survey contours, title, sheet frame, seeded three-client map, controls, responsive stacking |
| `/structures/maps/` | Family navigation, 39px mobile heading, plate hierarchy, opened SharedMap panel |
| `/directory/` | Folder-identity hero, three tree replicas, sequencer, race and sample-tree controls |
| `/guide/race/` | Step navigation, guide prose, ready boards, seeded note, race controls and neighboring sheets |
| `/json-ot/` | Title wrapping, JSON document controls, three replicas and pending counts |
| `/rich-text/` | Three mounted Quill editors, canonical values, scenario controls and mobile stacking |
| `/sequence/` | Waypoint linework, three ordered routes, selection controls and mobile stacking |
| `/text/` | Grapheme-rich editors, anchors, both mounted custom-element editors and mobile stacking |

All 16 loads returned HTTP 200, fit their viewport without root horizontal
overflow, loaded local fonts, and had no page errors, failed local requests,
or local HTTP error responses. No Astro island, Vite script, or legacy asset
node appeared. The full smoke suite separately exercised edits, races,
convergence, resets, keyboard/focus behavior, reduced motion, no-JavaScript
content, and failed-start fallbacks.

Unlike the smoke helper, this inspection did **not** stub analytics.
Every page recorded only the external Tinylytics script returning HTTP 404
with `net::ERR_ABORTED`:

```text
https://tinylytics.app/embed/uhk_zvSq2fBb_T2hTaLx/min.js?hits&events&beacon
```

The localhost site remained functional. No analytics configuration changed.
All temporary browser pages and loopback servers closed after inspection.

### Design critique evidence

The survey-sheet identity remains coherent across the inspected routes:
Archivo headings, monospaced instrument labels, white paper, ink rules,
magenta pending state, blue links, and visible replica evidence. Desktop
rigs make the sequencer relationship legible; mobile stacks retain that
ordering. The typed state and convergence labels remain the primary feedback.
The family navigation and inline demo toggles reduce the initial choice load.
Dense technical explanations and long vertical mobile rigs remain tradeoffs
of this documentation/demo surface, not new styling changes.

The generated-output detector ran after direct visual assessment:

```sh
node .claude/skills/impeccable/scripts/detect.mjs --json website_lustre/dist
```

It exited 2 with two advisories: Quill's Helvetica fallback in
`rich_text.css:7`, and the sequence field-note's 3px magenta annotation rule
in `styles/sequence.css:199`. Neither warrants replacing the existing editor
or the approved annotation treatment. Its HTML parser dependencies were
unavailable, so this CLI result is explicitly a degraded regex scan, not a
complete contrast or accessibility audit.

The browser detector also injected and ran in fresh desktop pages for `/`,
`/structures/maps/`, `/rich-text/`, and `/sequence/`. It reported 11, 10, 11,
and 7 advisories respectively. Most refer to intentional uppercase survey
annotations. The generic gradient warning points at `body`, not a visible
gradient heading. Remaining non-blocking readability advisories are the
10.56px DDS/CRDT badges on map jump links and long control-hint lines on the
rich-text and sequence demos. The homepage legend's border-padding warning
did not correspond to clipped text in the screenshots. No visual redesign
or fixture re-recording was made to satisfy generic detector preferences.
The injected overlays existed only in the temporary headless pages; no
user-visible overlay remains.

Questions skipped: this was the specified autonomous validation task, not a
request to choose a new design direction.

## Evidence files and concerns

Full logs, the inspection script, network JSON, detector results, and
screenshots remain under:

```text
/home/tylerbu/.copilot/session-state/d2ce7b31-7fc0-452e-baaa-95c37f541089/files/task-10/
```

Key files: `format.log`, `website-build.log`, `website-tests.log`,
`node-contracts.log`, `netlify-deploy-contract.log`, `browser-smoke.log`,
`root-build.log`, `root-lint.log`, `root-test.log`, `compile-fail.log`,
`website-gate.log`, `main-build.log`, `main-runtime-bootstrap.log`,
`legacy-proof.log`, `format-scope.log`, `browser-inspection.json`, `browser-inspection.log`,
`design-detector.json`, `design-detector.log`, `browser-detector.json`,
and `screenshots/*-review.jpg` plus the original PNGs.

The verified runtime-bootstrap baseline prevents a green aggregate root test
command. The external Tinylytics script is unavailable. Compiler/dependency
warnings remain; none came from Task 10 behavior changes. The deterministic
design scan has the limits noted above. Production deployment and rollback
were not performed; deploy configuration and artifact preservation passed
their local contracts.
