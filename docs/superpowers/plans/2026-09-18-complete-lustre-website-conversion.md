# Complete Lustre Website Conversion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `website_lustre` the only website implementation, with every collaboration demo owned by idiomatic Lustre applications and no production or test dependency on the Astro site.

**Architecture:** Preserve the approved page-scoped application architecture from the vertical-slice design. Static documents remain Lustre SSG output. Interactive demos use typed Gleam models, messages, pure updates, `watershed_lustre.perform` or `watershed_lustre.after` effects, and shared static/client views. JavaScript FFI is limited to DOM geometry, Web Animations, Quill integration, and browser APIs that Lustre does not expose.

**Tech Stack:** Gleam 1.18.1, Lustre 5.7, Lustre SSG, `watershed`, `watershed_lustre`, official Lustre dev tools, Djot, gleeunit, Puppeteer, Node 24, pnpm 11.13.1.

**Spec:** `docs/superpowers/specs/2026-09-04-lustre-website-vertical-slice-design.md`

## Global Constraints

- Preserve all public routes, redirects, metadata, copy, protected names, no-JavaScript content, and established visual design.
- Keep collaboration state, transitions, and error handling in Gleam.
- Run mutable watershed and `sluice_js` operations only inside deferred Lustre effects.
- Keep FFI narrow: it may measure or animate DOM geometry, assign browser properties, and adapt Quill, but it must not own collaboration state or construct the demo markup.
- Render effect and projection failures in the affected demo.
- Reuse one typed view for the SSG initial state and the mounted client application.
- Write Gleam comments and error strings in Simplified Technical English. Keep website prose in the established voiced style.
- Do not change source-snippet marker semantics or edit generated snippet output by hand.
- Do not add dependencies unless the existing platform and standard library cannot provide the required behavior.
- Do not add Co-authored-by trailers to commits.

---

### Task 1: Add Shared Demo Timing and Delivery Primitives

**Files:**
- Create: `website_lustre/src/watershed_site/demo/timing.gleam`
- Create: `website_lustre/src/watershed_site/demo/flow.gleam`
- Test: `website_lustre/test/demo_timing_test.gleam`
- Test: `website_lustre/test/demo_flow_test.gleam`

**Interfaces:**
- Produces: `timing.delay_ms(pace_quarters: Int, jitter: Bool, sample: Int) -> Int`
- Produces: `timing.next_sample(seed: Int) -> #(Int, Int)`
- Produces: `flow.Flow(id: Int, from: Endpoint, to: Endpoint, label: String)`
- Produces: `flow.Endpoint` constructors `Replica(String)` and `Sequencer`
- Produces: `flow.add`, `flow.remove`, and `flow.in_flight`

- [ ] **Step 1: Write failing timing tests**

```gleam
pub fn pace_uses_quarter_seconds_test() {
  timing.delay_ms(4, False, 99)
  |> should.equal(1000)
}

pub fn jitter_is_bounded_test() {
  timing.delay_ms(4, True, 0)
  |> should.equal(700)
  timing.delay_ms(4, True, 10_000)
  |> should.equal(1300)
}
```

- [ ] **Step 2: Run the timing tests**

Run: `cd website_lustre && gleam test --target javascript -- --test-name-filter=pace_uses_quarter_seconds_test`

Expected: FAIL because `watershed_site/demo/timing` does not exist.

- [ ] **Step 3: Implement deterministic timing**

Use integer arithmetic only. Clamp `pace_quarters` to at least one. Without jitter, return `pace_quarters * 250`. With jitter, map the sample to `-30%..+30%` and clamp the final delay to at least 50 ms.

- [ ] **Step 4: Write and implement flow tests**

```gleam
pub fn removing_one_flow_keeps_the_other_test() {
  let first = flow.Flow(1, flow.Replica("a"), flow.Sequencer, "set")
  let second = flow.Flow(2, flow.Sequencer, flow.Replica("b"), "deliver")
  [first, second]
  |> flow.remove(1)
  |> should.equal([second])
}
```

Run: `cd website_lustre && gleam test --target javascript -- demo_flow`

Expected after implementation: PASS.

- [ ] **Step 5: Run formatting and commit**

Run: `gleam format --check website_lustre/src website_lustre/test`

Commit:

```bash
git add website_lustre/src/watershed_site/demo website_lustre/test/demo_*_test.gleam
git commit -m "refactor(website): share demo timing primitives"
```

---

### Task 2: Replace the Generic Structure Demo with a Lustre Application

**Files:**
- Create: `website_lustre/src/watershed_site/structure_demo/model.gleam`
- Create: `website_lustre/src/watershed_site/structure_demo/runtime.gleam`
- Create: `website_lustre/src/watershed_site/structure_demo/view.gleam`
- Create: `website_lustre/src/watershed_site/client/structure_demo.gleam`
- Modify: `website_lustre/src/watershed_site/view/structure_sheet.gleam`
- Modify: `website_lustre/src/watershed_site/view/home.gleam`
- Modify: `website_lustre/src/watershed_site/route.gleam`
- Modify: `tools/build-website-lustre.sh`
- Delete: `website_lustre/src/watershed_site/client/structure_sheet_ffi.mjs`
- Delete: `website_lustre/src/watershed_site/client/mv_register_ffi.mjs`
- Test: `website_lustre/test/structure_demo_runtime_test.gleam`
- Test: `website_lustre/test/structure_demo_view_test.gleam`
- Test: `website_lustre/test/browser/home.mjs`
- Test: `website_lustre/test/browser/structure-pages.mjs`
- Test: `website_lustre/test/browser/mv-register.mjs`

**Interfaces:**
- Produces: `model.Structure` with one constructor per current picker value.
- Produces: `model.Model` containing selected structure, three typed replicas, pending operations, sequence number, flow list, latency, jitter, link state, log, generation, and visible error.
- Produces: `runtime.init(selected: Structure) -> #(Model, Effect(Msg))`
- Produces: `runtime.update(model: Model, message: Msg) -> #(Model, Effect(Msg))`
- Produces: `view.view(model: Model, options: Options) -> Element(Msg)`
- Produces: `view.static(selected: Structure, options: Options) -> Element(Nil)`

- [ ] **Step 1: Add failing model and transition tests**

Cover these behavior contracts with named tests:

```gleam
pub fn map_race_uses_later_sequence_number_test()
pub fn counter_race_keeps_both_increments_test()
pub fn duplicate_pn_delta_is_absorbed_test()
pub fn or_set_concurrent_add_survives_observed_remove_test()
pub fn two_p_set_tombstone_wins_test()
pub fn claim_loser_stays_uncommitted_test()
pub fn ordered_collection_second_acquire_is_empty_test()
pub fn cut_link_queues_local_and_remote_work_test()
pub fn reset_invalidates_old_delivery_test()
```

Use the real kernel APIs. Do not duplicate merge rules in test helpers.

- [ ] **Step 2: Run the new runtime test**

Run: `cd website_lustre && gleam test --target javascript -- structure_demo_runtime`

Expected: FAIL because the modules do not exist.

- [ ] **Step 3: Implement the typed model**

Use a closed `Structure` custom type and structure-specific replica states in a `ReplicaState` custom type. Do not use dynamic dictionaries to imitate TypeScript's `OperationByDds`. Keep envelope variants typed:

```gleam
pub type Operation {
  MapOperation(map_kernel.MapOperation)
  CounterOperation(runtime_core.OutboundOperation)
  GCounterOperation(g_counter_kernel.GCounterOperation)
  PnOperation(pn_counter_kernel.PnCounterOperation)
  OrMapOperation(or_map_kernel.OrMapOperation)
  LwwMapOperation(lww_map_kernel.LwwMapOperation)
  LwwRegisterOperation(lww_register_kernel.LwwRegisterOperation)
  MvRegisterOperation(mv_register_kernel.MvRegisterOperation)
  OrSetOperation(or_set_kernel.OrSetOperation)
  GSetOperation(g_set_kernel.GSetOperation)
  TwoPSetOperation(two_p_set_kernel.TwoPSetOperation)
  ClaimOperation(claims_kernel.ClaimOperation)
  RegisterOperation(register_collection_kernel.WriteOperation)
  OrderedOperation(ordered_collection_kernel.OrderedOperation)
  TaskOperation(task_manager_kernel.TaskManagerOperation)
  PactOperation(pact_map_kernel.PactMapOperation)
}
```

- [ ] **Step 4: Implement deferred runtime effects**

Follow `website_lustre/src/watershed_site/guide_race/runtime.gleam`:

- `update` only prepares typed commands.
- `watershed_lustre.perform` creates, mutates, acknowledges, or projects kernel state.
- `watershed_lustre.after` schedules delivery and flow cleanup.
- Every scheduled message carries `generation`.
- A stale generation returns `effect.none()`.
- Errors become `Failed(String)` messages and visible model state.

- [ ] **Step 5: Implement the shared view**

Move the static rig markup now in `mv_register/view.gleam` into `structure_demo/view.gleam`. Use Lustre event handlers rather than `data-*` lookup for controls. Retain stable `data-testid` attributes for browser tests. Keep `data-*` attributes only when CSS or the narrow animation FFI reads them.

- [ ] **Step 6: Mount the same app on home, structure sheets, and MV register**

Use route-specific mount IDs and initial structures:

- home: `Map`
- `/mv-register/`: `MvRegister`
- structure family sheets: the first structure in the family; toggles dispatch `SelectStructure`.

The family panel open/close state belongs in Lustre. Remove the JavaScript panel state machine.

- [ ] **Step 7: Run targeted unit and browser tests**

Run:

```bash
cd website_lustre
gleam test --target javascript -- structure_demo
cd ..
just website-lustre
node website_lustre/test/browser/home.mjs
node website_lustre/test/browser/structure-pages.mjs
node website_lustre/test/browser/mv-register.mjs
```

Expected: all pass; `rg 'website/src/scripts/demo' website_lustre/src` returns no matches.

- [ ] **Step 8: Commit**

```bash
git add website_lustre tools/build-website-lustre.sh
git commit -m "feat(website): move structure demos into Lustre"
```

---

### Task 3: Make the Homepage Client Fully Lustre-Owned

**Files:**
- Create: `website_lustre/src/watershed_site/client/home.gleam` if Task 2 did not replace it
- Create: `website_lustre/src/watershed_site/client/home_ffi.mjs`
- Modify: `website_lustre/src/watershed_site/view/home.gleam`
- Delete: legacy `home_ffi.mjs` implementation that imports Astro scripts
- Test: `website_lustre/test/home_view_test.gleam`
- Test: `website_lustre/test/browser/home.mjs`

**Interfaces:**
- Consumes: `structure_demo.runtime` and `structure_demo.view`
- FFI produces only `startHeroDrift() -> Nil` and `stopHeroDrift() -> Nil`

- [ ] **Step 1: Add failing ownership and markup tests**

Assert that the generated home page has one `#home-demo-mount`, the static demo fallback, an accessible convergence-model navigation label, and no script path containing `_astro` or `website/src`.

- [ ] **Step 2: Replace the entry module**

Start a Lustre application whose model composes structure-demo state with homepage-only gauge-strip state. Gauge-strip values must derive from the structure-demo model, not a `MutationObserver`.

- [ ] **Step 3: Narrow the FFI**

Keep contour geometry and `requestAnimationFrame` in FFI. Accept the SVG root and reduced-motion state as arguments. Do not query or mutate demo controls from FFI.

- [ ] **Step 4: Validate**

Run:

```bash
cd website_lustre && gleam test --target javascript -- home
cd .. && just website-lustre
node website_lustre/test/browser/home.mjs
```

Expected: PASS and no homepage import from `website/src`.

- [ ] **Step 5: Commit**

```bash
git add website_lustre
git commit -m "feat(website): make homepage demo native Lustre"
```

---

### Task 4: Migrate JSON OT and Sequence Demos

**Files:**
- Create: `website_lustre/src/watershed_site/json_ot/runtime.gleam`
- Modify: `website_lustre/src/watershed_site/json_ot/view.gleam`
- Replace: `website_lustre/src/watershed_site/client/json_ot.gleam`
- Delete: `website_lustre/src/watershed_site/client/json_ot_ffi.mjs`
- Create: `website_lustre/src/watershed_site/sequence/runtime.gleam`
- Modify: `website_lustre/src/watershed_site/sequence/view.gleam`
- Replace: `website_lustre/src/watershed_site/client/sequence.gleam`
- Delete: `website_lustre/src/watershed_site/client/sequence_ffi.mjs`
- Test: `website_lustre/test/json_ot_runtime_test.gleam`
- Test: `website_lustre/test/sequence_runtime_test.gleam`
- Test: `website_lustre/test/browser/json-ot.mjs`
- Test: `website_lustre/test/browser/sequence.mjs`

**Interfaces:**
- Each runtime produces `init`, `update`, and a typed `Model` and `Msg`.
- Each view produces `view(model, include_noscript)` and `static()`.

- [ ] **Step 1: Write failing JSON OT convergence tests**

Cover concurrent object inserts, transformed array positions, stale delivery rejection after reset, and visible failure state.

- [ ] **Step 2: Port JSON OT state transitions**

Translate `website/src/scripts/json-ot-demo.ts` into typed messages and deferred kernel effects. The update function must not read the DOM.

- [ ] **Step 3: Write failing sequence tests**

Cover concurrent insert ordering, remove/insert interaction, pending display, reset generation, and both replicas converging.

- [ ] **Step 4: Port sequence state transitions**

Use the real sequence kernel and the shared timing/flow modules.

- [ ] **Step 5: Validate both demos**

Run:

```bash
cd website_lustre
gleam test --target javascript -- json_ot_runtime
gleam test --target javascript -- sequence_runtime
cd ..
just website-lustre
node website_lustre/test/browser/json-ot.mjs
node website_lustre/test/browser/sequence.mjs
```

- [ ] **Step 6: Commit**

```bash
git add website_lustre
git commit -m "feat(website): migrate OT and sequence demos"
```

---

### Task 5: Migrate Text and Rich-Text Demos with Narrow Editor FFI

**Files:**
- Create: `website_lustre/src/watershed_site/text/runtime.gleam`
- Modify: `website_lustre/src/watershed_site/text/view.gleam`
- Replace: `website_lustre/src/watershed_site/client/text.gleam`
- Replace: `website_lustre/src/watershed_site/client/text_ffi.mjs`
- Create: `website_lustre/src/watershed_site/rich_text/runtime.gleam`
- Modify: `website_lustre/src/watershed_site/rich_text/view.gleam`
- Replace: `website_lustre/src/watershed_site/client/rich_text.gleam`
- Replace: `website_lustre/src/watershed_site/client/rich_text_ffi.mjs`
- Test: `website_lustre/test/text_runtime_test.gleam`
- Test: `website_lustre/test/rich_text_runtime_test.gleam`
- Test: `website_lustre/test/browser/text.mjs`
- Test: `website_lustre/test/browser/rich-text.mjs`

**Interfaces:**
- Text FFI may assign custom-element properties and subscribe to browser custom events.
- Rich-text FFI exposes an opaque editor handle plus `mount`, `applyRemote`, `setEnabled`, and `destroy`.
- Rich-text FFI dispatches typed editor-change payloads back to Lustre; it does not call watershed kernels.

- [ ] **Step 1: Add failing text runtime tests**

Cover concurrent inserts, cursor payload forwarding, reset generation, and editor startup failure.

- [ ] **Step 2: Implement text as a Lustre application**

The model owns both document handles, connection state, cursors, and visible errors. Use the existing `watershed-textarea` custom element only as a rendering adapter.

- [ ] **Step 3: Add failing rich-text runtime tests**

Cover local Quill delta submission, one-operation-in-flight gating, remote transform/application, acknowledgement, reconnect/reset, and adapter failure.

- [ ] **Step 4: Implement rich-text runtime and adapter**

Port `rich-text-adapter.js` behavior into the narrow FFI surface. Keep Quill's DOM and delta conversion in JavaScript. Move sequencing, pending operation state, and kernel calls into Gleam effects.

- [ ] **Step 5: Validate**

Run:

```bash
cd website_lustre
gleam test --target javascript -- text_runtime
gleam test --target javascript -- rich_text_runtime
cd ..
just website-lustre
node website_lustre/test/browser/text.mjs
node website_lustre/test/browser/rich-text.mjs
```

- [ ] **Step 6: Commit**

```bash
git add website_lustre
git commit -m "feat(website): migrate text demos to Lustre"
```

---

### Task 6: Move Snippets, Motion, and Catalog Authority out of Astro

**Files:**
- Move: `website/snippets.json` to `website_lustre/snippets.json`
- Move: `website/src/scripts/motion.js` to `website_lustre/assets/scripts/motion.js`
- Move or regenerate: `website/src/generated/snippets.json` to `website_lustre/src/generated/snippets.json`
- Modify: `tools/build-website-lustre.sh`
- Modify: `website_lustre/dev/watershed_site/build.gleam`
- Modify: `website_lustre/src/watershed_site.gleam`
- Modify: all `website_lustre/test/*.gleam` manifest paths
- Replace Astro parity-source tests with Lustre-owned catalog snapshots.
- Test: `website_lustre/test/snippet_test.gleam`
- Test: `website_lustre/test/content_test.gleam`
- Test: `website_lustre/test/practice_test.gleam`
- Test: `website_lustre/test/runtime_index_test.gleam`

**Interfaces:**
- Snippet generator input: `website_lustre/snippets.json`
- Generated manifest: `website_lustre/src/generated/snippets.json`
- Build argument default: `./src/generated/snippets.json`

- [ ] **Step 1: Change tests to the new manifest path and verify failure**

Run: `cd website_lustre && gleam test --target javascript -- snippet`

Expected: FAIL because the manifest has not moved.

- [ ] **Step 2: Move snippet authority and update the generator**

Preserve every snippet ID and marker root. Update AGENTS.md and tool documentation that names the old paths.

- [ ] **Step 3: Move motion ownership**

Copy the existing visible-by-default, reduced-motion-safe behavior unchanged. Load it as a static site asset rather than reading from `website/` during the SSG build.

- [ ] **Step 4: Replace live Astro catalog comparisons**

Convert the current Astro TypeScript catalogs used by parity tests into reviewed JSON fixtures or typed Gleam expectations under `website_lustre/test/fixtures/`. The tests must compare current Lustre catalogs to those committed contracts and must not read `../website`.

- [ ] **Step 5: Validate**

Run:

```bash
just snippets
just website-lustre
cd website_lustre && gleam test --target javascript
cd ..
rg 'website/' website_lustre tools/build-website-lustre.sh
```

Expected: remaining matches refer only to historical documentation scheduled for Task 7.

- [ ] **Step 6: Commit**

```bash
git add AGENTS.md website_lustre tools/build-website-lustre.sh tools/source-snippets
git commit -m "refactor(website): move site authority to Lustre"
```

---

### Task 7: Remove Astro and Obsolete TypeScript

**Files:**
- Delete: `website/`
- Modify: `pnpm-workspace.yaml`
- Modify: root and website CI workflows
- Modify: `justfile`
- Modify: `website_lustre/scripts/netlify-build.sh`
- Modify: `website_lustre/README.md`
- Modify: `docs/superpowers/specs/2026-09-04-lustre-website-vertical-slice-design.md` only to mark the parallel-Astro phase complete
- Modify: tests and fixtures whose names still imply a live Astro dependency

**Interfaces:**
- Root website build: `just website-lustre`
- Root website test: `just _test-website-lustre`
- Source snippets: `just snippets`

- [ ] **Step 1: Add a deletion contract test**

Extend `website_lustre/test/netlify-deploy-contract.test.mjs` to assert:

```js
assert.equal(existsSync(resolve(repoRoot, "website")), false);
assert.doesNotMatch(build, /--dir website install/);
assert.doesNotMatch(build, /astro build/);
```

- [ ] **Step 2: Delete the Astro tree**

Use targeted deletion of the resolved `website/` directory only after Task 6 proves no active references remain.

- [ ] **Step 3: Remove Astro install and workspace configuration**

Netlify installs only the root/Gleam dependencies and `website_lustre` browser dependencies. Remove Astro-specific scripts, checks, and workflow cache keys.

- [ ] **Step 4: Rename parity fixtures and messages**

Use `site-*-contract.json` names. Preserve the approved values; only the authority and terminology change.

- [ ] **Step 5: Validate**

Run:

```bash
rg 'astro|Astro|website/' website_lustre justfile netlify.toml .github tools
just website-lustre
node --test website_lustre/test/netlify-deploy-contract.test.mjs
```

Expected: no active Astro runtime/build dependency; historical migration documentation may remain.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor(website): remove Astro implementation"
```

---

### Task 8: Fix Visual, Asset, and Accessibility Regressions

**Files:**
- Modify: `website_lustre/assets/styles/site.css`
- Modify: `website_lustre/assets/styles/home.css`
- Modify: `website_lustre/assets/styles/structure-sheet.css`
- Modify: `website_lustre/src/watershed_site/view/document.gleam`
- Modify: `website_lustre/src/watershed_site/view/home.gleam`
- Modify: relevant browser tests

**Interfaces:**
- No new public code interface.

- [ ] **Step 1: Add browser assertions for known regressions**

At 1280x800 and 390x844 assert:

- `document.documentElement.scrollWidth == innerWidth`
- every font response on `/structures/maps/` is 200
- the mobile home demo has no gap over 320 px between visible rig regions
- the Maps H1 computed size is at least 36 px at 390 px width
- the convergence-model navigation has an accessible label
- scrollable `pre` elements have `tabindex="0"`

- [ ] **Step 2: Fix absolute asset URLs**

Document stylesheets must reference `/fonts/...`, never route-relative `fonts/...`.

- [ ] **Step 3: Fix layout and hierarchy**

Remove the flow-layer minimum height that creates the mobile void. Constrain wide demo children with `min-width: 0` and viewport-safe widths. Restore the mobile H1 scale.

- [ ] **Step 4: Fix accessibility parity**

Add the missing navigation label and focusability for scrollable code. Increase interactive demo targets to at least 44x44 CSS pixels when that does not change the established layout.

- [ ] **Step 5: Validate desktop and mobile browser suites**

Run: `cd website_lustre && pnpm run smoke`

Expected: PASS with no local 404, no root overflow, and all new assertions passing.

- [ ] **Step 6: Commit**

```bash
git add website_lustre
git commit -m "fix(website): restore visual and accessibility parity"
```

---

### Task 9: Reduce Bundle Duplication

**Files:**
- Modify: `tools/build-website-lustre.sh`
- Modify: `website_lustre/gleam.toml`
- Modify: `website_lustre/test/assets_test.gleam`
- Modify: `website_lustre/test/browser/site.mjs`

**Interfaces:**
- Build must emit shared chunks once and page entries that import them.

- [ ] **Step 1: Add an asset budget test**

Fail when total generated JavaScript and CSS exceeds 2.2 MB raw or 520 KB gzip. Record per-entry sizes in the assertion message.

- [ ] **Step 2: Build all client entries in one official Lustre CLI invocation**

Pass every entry module to the build tool once. Remove repeated builds that duplicate runtime and kernel code across independently bundled outputs.

- [ ] **Step 3: Remove unused route assets**

Each document includes only its route stylesheet and client entry. Static pages include neither demo bundles nor demo CSS.

- [ ] **Step 4: Validate the budget**

Run:

```bash
just website-lustre
cd website_lustre && gleam test --target javascript -- assets
```

Expected: PASS under the budget.

- [ ] **Step 5: Commit**

```bash
git add tools/build-website-lustre.sh website_lustre
git commit -m "perf(website): share Lustre client bundles"
```

---

### Task 10: Complete Repository Validation and Documentation

**Files:**
- Modify: `website_lustre/README.md`
- Modify: root `README.md` or contributor docs only where they still instruct Astro commands
- Modify: `DESIGN.md` only if shipped behavior changed from its current contract

**Interfaces:**
- No new code interface.

- [ ] **Step 1: Prove no legacy implementation remains**

Run:

```bash
test ! -d website
! rg 'website/src|astro-island|@vite' website_lustre/src website_lustre/scripts tools/build-website-lustre.sh
```

- [ ] **Step 2: Run format and targeted website validation**

Run:

```bash
just format
just website-lustre
cd website_lustre && gleam test --target javascript
cd .. && node --test website_lustre/test/netlify-deploy-contract.test.mjs
cd website_lustre && pnpm run smoke
```

- [ ] **Step 3: Run root validation**

Run:

```bash
just build
just lint
just test
```

If `just test` reaches the known unchanged `smoke/runtime_bootstrap.mjs` baseline failure, verify it against unchanged `main` before reporting it. Any website, Gleam, JavaScript, browser, or deploy-contract failure must be fixed.

- [ ] **Step 4: Re-run the design critique evidence**

Build and inspect `/`, `/structures/maps/`, `/directory/`, `/guide/race/`, `/json-ot/`, `/rich-text/`, `/sequence/`, and `/text/` at desktop and mobile sizes. Confirm no console errors except an externally unavailable analytics request.

- [ ] **Step 5: Update documentation**

Document only the Lustre workflow, typed demo architecture, narrow FFI policy, snippet paths, and validation commands. Remove rollback instructions that depend on a live Astro tree; use the last Astro commit as the rollback source instead.

- [ ] **Step 6: Commit**

```bash
git add README.md DESIGN.md website_lustre docs justfile
git commit -m "docs(website): document native Lustre site"
```

