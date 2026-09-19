# Final whole-branch fix report

**Status:** Complete. Fixed all four Important findings and both Minor findings.
**Branch:** `lustre-website-vertical-slice`
**Starting commit:** `5d104b8`
**Date:** 2026-09-19

## Findings resolved

| Finding | Fix | Regression coverage |
| --- | --- | --- |
| SharedCounter bypasses delivery and link state | Replace the immediate broadcast with a typed counter operation and local message ID. Apply optimism only at the origin; acknowledge through the shared queue. Sequence A/C work while B is disconnected, then deliver B's catch-up before its queued submissions. Remove the obsolete counter-completion bypass. | Origin-only optimism, pending retirement, disconnected B increments/decrements, catch-up without double application, FIFO acknowledgment, queued race, and a live disconnected counter browser scenario. |
| PactMap fails with B disconnected | Deliver proposals and kernel-generated accept operations through the typed queue. Keep the three-member sign-off list when cutting B's transport. Retain the original sequence number on catch-up envelopes. Render the remaining signers, and treat a pending-proposal refusal as recoverable. | Separate proposal/accept deliveries; B's missing sign-off; competing offline proposal; cut after proposal; original acceptance sequence during catch-up; deferred delete; retry after a pending-proposal refusal; sign-off markup; live disconnect/reconnect. |
| Unavailable sequence race disables editing and Reset | Keep the existing phase and display the unavailable-scenario explanation. Distinguish a recoverable message from `Failed` in the deferred wrapper and convergence projection. Do not change delivery state when queueing cleanup work. Clear the explanation on a successful edit or Reset. | A one-waypoint route, unchanged state after RaceMove, working insertion and Reset, real deferred-effect execution, cleanup after the warning, and the complete browser interaction. |
| Thirteen routes lack skip targets | Add `id="content"` to the eleven main landmarks without IDs. Point the shared skip link to the existing `#index` on Patterns and `#catalog` on Examples, preserving both public fragments. | New smoke gate visits all 42 generated routes without JavaScript, checks a unique main target, and activates each skip link with the keyboard. |
| Homepage flow dots lack coordinates | Initialize the existing shared `setupDemo` geometry adapter after mounting the homepage app. | Browser assertions compare all four flow coordinates with measured node centers within 0.5 px, before and after a mobile-to-desktop resize. |
| Homepage OrSet link uses the wrong fragment | Change `/structures/sets#or-set` to `/structures/sets#orset`. | Rendered-link unit regression and browser navigation to the generated OrSet heading without JavaScript. |

## TDD evidence

Before implementation, the regressions reproduced the counter's premature
broadcast, missing PactMap delivery path, fabricated sign-offs, fatal sequence
race, missing sign-off text, and wrong OrSet URL. The browser regressions
confirmed all 13 missing skip targets, empty homepage flow coordinates, the
counter's disconnected broadcast, and disabled sequence recovery controls.

Browser validation then exposed a second sequence failure in the deferred
wrapper. A new effect-execution regression reproduced it before the wrapper
fix. A repeat-proposal regression also reproduced a fatal PactMap refusal
before the recovery fix. The final suite adds 13 Gleam tests, extends three
browser gates, and adds one route-wide browser gate.

## Final validation

| Check | Exact result |
| --- | --- |
| Targeted exported `_test` functions from `structure_demo_runtime_test`, `structure_demo_view_test`, `sequence_runtime_test`, `sequence_view_test`, and `home_view_test` | **63 passed, 0 failures** |
| `cd website_lustre && gleam test --target javascript`, after the final build | **203 passed, 0 failures** |
| `node --test website_lustre/test/*.test.mjs` | **5 passed, 0 failures, 0 skipped** |
| `just website-lustre` | **Passed**, generated all 42 routes and client bundles |
| Affected browser gates with `CI=true` | **15 passed**: skip-targets, home, structure-pages, sequence, mv-register, models, patterns, examples, sharedtree, sudoku, directory, counter-bug, json-ot, rich-text, text |
| `cd website_lustre && CI=true pnpm run smoke` | **25 of 25 gates passed**, sequential run, no skipped gates |
| `gleam format --check website_lustre/src website_lustre/test` | **Passed** |
| `git diff --check` | **Passed** |

The 63 targeted tests are a subset of the 203-test suite. The 15 affected
browser gates are a subset of the 25-gate smoke suite.

The targeted command used the existing compiled test modules:

```sh
cd website_lustre
node --input-type=module -e '
let count = 0;
for (const name of [
  "structure_demo_runtime_test", "structure_demo_view_test",
  "sequence_runtime_test", "sequence_view_test", "home_view_test"
]) {
  const tests = await import(`./build/dev/javascript/watershed_site/${name}.mjs`);
  for (const [name, test] of Object.entries(tests)) {
    if (name.endsWith("_test")) { await test(); count++; }
  }
}
console.log(`Targeted tests: ${count} passed, 0 failures`);
'
```

## Preserved constraints

Collaboration state and transitions remain in typed Gleam models. Browser
updates still execute runtime work through deferred Lustre effects, and
generation checks reject stale deliveries. This change adds no dependency or
JavaScript collaboration logic. It reuses the existing geometry adapter
without changing its FFI implementation.

The route, copy, style, no-JavaScript, and reduced-motion browser contracts
passed without fixture changes. Existing fragment names remain intact except
for the incorrect OrSet link. Review stayed in the main session; no subagents
were dispatched.

## Concerns

- One affected-gate run timed out in the existing rich-text embed scenario
  while another browser batch ran in parallel. The isolated rerun passed,
  and the final complete sequential smoke run passed. No rich-text runtime
  or test changes were needed.
- The successful production build emitted 21 existing warnings from build
  dependencies and root watershed sources/tests. None came from the changed
  website code.
- No outstanding review findings remain. No deployment or push was requested
  or performed.
