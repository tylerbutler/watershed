# Task 4 Report: Dedicated SharedTree Checklist Page

## Status

Complete. The website now has a dedicated `/sharedtree/checklist` page with two
production SharedTree replicas connected to the in-page Sluice rig.

## Implementation

- Added `website/src/components/SharedTreeChecklistDemo.astro`.
  - Two replica articles with client IDs `a` and `b`.
  - Required `data-st-*` hooks, canonical output, pending badges, sequencer,
    operation log, flow layer, pace and jitter controls, race, step, settle,
    reset, status, `noscript`, and failed-import fallback.
  - Flat 1px linework, no panel radius or shadows.
  - Magenta marks pending rows, ink marks sequenced rows, and waterline remains
    reserved for links and operation paths.
- Added `website/src/scripts/shared-tree-checklist-demo.ts`.
  - Uses `createSluiceRig`, `demoSeed`, the generated `websiteRuntime`
    SharedTree checklist bridge, and `ResultValue`.
  - Opens and stores one opaque checklist handle per client.
  - Reads generated records into plain `{ id, text, completed }` objects.
  - Rebuilds only each checklist list and preserves an active edit's text,
    focus, and selection during a render.
  - Routes add, edit, toggle, move, race, step, settle, and reset through the
    shared rig. Every generated `Result` is checked with `expectOk`.
  - The race resets to the seed, submits Client A's `publish-survey` edit and
    Client B's `inspect-spillway` move before delivery, and converges to:
    `review-field-notes`, `inspect-spillway`, `publish-survey`, with
    `publish-survey` reading `publish revised survey`.
- Added `website/src/pages/sharedtree/checklist.astro`.
  - Links back to `/sharedtree`.
  - Explains the production SharedTree kernel, in-page Sluice, seeded native
    container, and the Floodgate/two-tab Lustre counterpart.
  - Links directly to the live demo and
    `examples/shared_tree_checklist_lustre`.
- Updated `website/src/pages/sharedtree.astro`.
  - Preserves the typed-map comparison's scope.
  - Describes the current native SharedTree browser facade and its remaining
    demo exclusions.
  - Adds a prominent `/sharedtree/checklist` link.
- Updated the generated-runtime policy gate to register the new dedicated demo
  and the previously committed SharedTree rig tests as named bridge consumers.
- Regenerated `tools/website-runtime/manifest.toml` so the already-declared
  local `shared_tree_checklist_lustre` dependency is recorded reproducibly.

## Responsive and Keyboard Self-Review

### Desktop

- The rig uses equal `minmax(0, 1fr)` replica columns around the central
  sequencer.
- Replica cards, list rows, controls, canonical values, and the operation log
  all constrain long content instead of widening the page.
- Pending and sequenced states use the required semantic colors.

### Mobile

- At 940px the rig becomes Client A, sequencer, Client B in one column.
- At 480px add controls and move controls stack vertically, and scenario
  buttons become full width.
- The hero reduces display stretch and size below 30rem to protect the Sheet
  frame.
- Coarse-pointer controls have at least 3rem height.

### Keyboard and Assistive States

- All actions use native inputs and buttons and inherit the global 2px
  magenta `:focus-visible` outline.
- Enter adds a draft item and commits an item edit; blur also commits edits.
- Toggle controls expose the client, item text, and completion state.
- Move buttons expose the client, item text, and direction, and disable at the
  first and last rows.
- Reset and fallback assistive text is literal.
- The status and operation log use live regions without replacing native
  control behavior.

## Verification

- Task 4 external acceptance gate: passed.
- SharedTree bridge and Sluice rig tests: 12 passed.
- `pnpm check:types`: passed.
- `node --strip-types --test src/data/copy-gates.test.ts`: passed.
- `node --strip-types --test src/data/drift-gates.test.ts`: passed.
- Impeccable mechanical detector: no findings.
- `pnpm build`: passed, including the full website unit suite and Astro build.
- Built route check: `website/dist/sharedtree/checklist/index.html` exists and
  contains the live checklist section.
- `git diff --check`: passed.

## Concerns

None.

## Round 1 Fixes

- Qualified the comparison page consistently as watershed's typed-map layer.
  The description, headings, body copy, gaps section, conclusion, and table
  framing now keep that scope explicit.
- Kept the native facade contrast narrow: browser-created object, array, and
  map trees, array moves, schema compatibility checks, and schema upgrades.
  Transactions, undo and redo, branching, arbitrary checklist layouts, and
  production token issuance remain stated limits.
- Preserved keyboard focus across checklist list replacement for text inputs,
  toggle checkboxes, and move buttons by stable item ID and control identity.
  A move button keeps its direction while enabled; at the list boundary,
  focus moves to the opposite direction for the same item so keyboard use can
  continue.
- Extended the real-browser demo checks with the SharedTree checklist
  convergence path and focused toggle/repeated-move keyboard coverage.

### Round 1 Verification

- `node --test /home/tylerbu/.copilot/session-state/516e97b7-7902-4b9a-9ef4-4137500e6b6f/files/task-4-acceptance.test.mjs`
  — passed, 1 test.
- `node --strip-types --test src/scripts/demo/website-runtime-contract.test.ts src/scripts/demo/sluice-rig.test.ts src/scripts/demo/sluice-transport.test.ts`
  — passed, 22 tests.
- `pnpm check:types` — passed.
- `node --strip-types --test src/data/copy-gates.test.ts` — passed, 822
  tests.
- `node --strip-types --test src/data/drift-gates.test.ts` — passed, 1,092
  tests.
- `pnpm build` — passed, including 2,360 unit tests and 46 built pages.
- `pnpm test:integration:browser:required` — passed, including 2,360 unit
  tests, 46 built pages, and 36 browser tests.
- `git diff --check` — passed.

### Round 1 Concerns

`just test` was also attempted as a broader repository check. The core
`watershed` package passed, and `shared_tree_checklist_lustre` passed all 6
tests. Eight unrelated Lustre example packages could not resolve dependencies
because the Hex API rate limit was exceeded, so the full matrix stopped before
the website packages. The required Task 4 acceptance, bridge, type, copy,
drift, build, and browser gates above all passed independently.

## Round 2 Fix

- Corrected the hero lede to describe watershed as the `typed-map layer`,
  matching the rest of the comparison page.

### Round 2 Verification

- `node --strip-types --test src/data/copy-gates.test.ts` — passed, 822
  tests.
- `pnpm check:types` — passed.
