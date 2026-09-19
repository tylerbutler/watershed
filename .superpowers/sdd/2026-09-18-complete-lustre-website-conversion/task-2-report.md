# Task 2 report: native structure demo

## Status

Complete. The homepage, structure-family sheets, and MV-register page now mount one typed Lustre application. The production `website_lustre` tree no longer imports the legacy `website/src/scripts/demo.ts` controller.

## Files changed

### Added

- `website_lustre/src/watershed_site/client/structure_demo.gleam`
- `website_lustre/src/watershed_site/client/structure_demo_ffi.mjs`
- `website_lustre/src/watershed_site/structure_demo/family.gleam`
- `website_lustre/src/watershed_site/structure_demo/model.gleam`
- `website_lustre/src/watershed_site/structure_demo/runtime.gleam`
- `website_lustre/test/structure_demo_runtime_test.gleam`
- `website_lustre/test/structure_demo_view_test.gleam`

### Moved

- `website_lustre/src/watershed_site/mv_register/view.gleam`
  to `website_lustre/src/watershed_site/structure_demo/view.gleam`

### Modified

- `website_lustre/gleam.toml`
- `website_lustre/manifest.toml`
- `website_lustre/src/watershed_site/client/home.gleam`
- `website_lustre/src/watershed_site/client/home_ffi.mjs`
- `website_lustre/src/watershed_site/client/mv_register.gleam`
- `website_lustre/src/watershed_site/client/structure_sheet.gleam`
- `website_lustre/src/watershed_site/page.gleam`
- `website_lustre/src/watershed_site/view/document.gleam`
- `website_lustre/src/watershed_site/view/home.gleam`
- `website_lustre/src/watershed_site/view/mv_register.gleam`
- `website_lustre/src/watershed_site/view/structure_sheet.gleam`
- `website_lustre/test/mv_register_view_test.gleam`

### Deleted

- `website_lustre/src/watershed_site/client/mv_register_ffi.mjs`
- `website_lustre/src/watershed_site/client/structure_sheet_ffi.mjs`

`route.gleam` and `tools/build-website-lustre.sh` did not need changes. Their existing route script names and bundle entry points already matched the new Gleam clients.

## Architecture

`structure_demo/model.gleam` defines the closed `Structure` type, typed replica-state variants, typed operation envelopes, delivery scopes, pending operations, flow markers, log entries, phases, and the shared application model.

`structure_demo/runtime.gleam` owns initialization, selection, panel state, link state, reset generations, delivery scheduling, projections, and the kernel-backed behavior contracts. It uses `watershed_lustre.perform` for deferred initialization and counter work and `watershed_lustre.after` for delivery scheduling. Every scheduled delivery carries a generation; stale messages return `effect.none()`.

The MV-register reconnect path follows the runtime order used by the legacy demo: the sequencer first delivers operations that Client B missed, then submits Client B's locally authored operation. All three replicas start from one serialized kernel summary. This avoids treating three separately authored copies of `"Survey datum"` as concurrent values.

`structure_demo/view.gleam` contains the shared demo rig and Lustre handlers. `structure_demo/family.gleam` contains the client-safe structure-sheet plate subtree. Splitting the family subtree from the server page shell prevents browser bundles from importing Node-only build dependencies through the page renderer.

The route adapters mount the same application with different initial structures:

- Homepage: `Map` at `#home-structure-demo-mount`
- MV-register page: `MvRegister` at `#mv-register-demo-mount`
- Structure sheets: first eligible family structure at `#structure-sheet-mount`

The family panel open state and OR-map mode now live in the Lustre model. The deleted structure-sheet FFI no longer owns a panel state machine.

The document renderer gained an inline fallback guard. Static markup stays inert and hidden while JavaScript is disabled. If a route bundle fails to mount within three seconds, the guard reveals the existing failure message. A mounted Lustre view marks its demo root with `data-mounted`.

The homepage FFI now handles only the narrow gauge-strip mirror and hero drift. It does not start the legacy demo controller.

## API rulings

- The brief names `runtime_core.OutboundOperation` for `CounterOperation`. The public type returned by the installed runtime is `wire.OutboundOperation`, so the model uses that real public type.
- `lattice_core` is a direct `website_lustre` dependency because typed replica initialization calls `replica_id.new`. Relying on the transitive dependency produced a compiler warning.
- MV-register replicas must load one shared `summary` through `from_summary`. Calling `p2p_set` independently on each replica creates separate causal dots for the same displayed baseline.
- The structure-family client cannot import `view/structure_sheet.gleam`: that server renderer reaches Node-only `simplifile` code through the build stack. The pure `structure_demo/family.gleam` subtree is shared by SSR and the browser application instead.
- The browser tests use the repository's existing `CI=1` launcher path so Puppeteer passes `--no-sandbox` on this host.

## Test history and final results

TDD red run:

```text
cd website_lustre && gleam test --target javascript -- structure_demo_runtime
```

Result: failed because `watershed_site/structure_demo/model`, `runtime`, and `view` did not exist.

The reconnect regression test also failed before the shared-summary fix: Client C retained `"Survey datum"` while Clients A and B converged on the two new alternatives.

Final commands:

```text
just format
```

Result: all Trellis format tasks passed.

```text
cd website_lustre && gleam check --target javascript
```

Result: compiled successfully.

```text
cd website_lustre && gleam test --target javascript -- structure_demo
```

Result: `123 passed, no failures`.

```text
just website-lustre
```

Result: all browser bundles built, 68 assets copied per bundle, and all native pages generated in `website_lustre/dist`.

```text
CI=1 node website_lustre/test/browser/home.mjs
```

Result: `PASS: Homepage SharedMap demo converges without Astro runtime.`

```text
CI=1 node website_lustre/test/browser/structure-pages.mjs
```

Result: `PASS: counters, sets, registers, maps, sequences, coordination, transforms structure page static parity.`

```text
CI=1 node website_lustre/test/browser/mv-register.mjs
```

Result: `PASS: MV register parity, offline resolution, replay, reset, and fallbacks.`

```text
rg 'website/src/scripts/demo' website_lustre/src
```

Result: no matches.

```text
git diff --check
```

Result: no whitespace errors.

## Commits

- `eef1bef feat(website): move structure demos into Lustre`

The commit has no `Co-authored-by` trailer.

## Remaining concerns

- The named browser suite exercises homepage map convergence, MV-register reconnect and resolution, counter panel selection, and OR-map mode switching. The other family panels retain their typed views and kernel contract tests but do not have equivalent browser interaction coverage.
- The fallback guard applies to every `[data-demo-fallback]` node rendered by the native site. It is inert when no such node exists.
- `just website-lustre` still reports existing dependency and unrelated repository warnings during its broader build. The new `website_lustre` modules pass `gleam check` without warnings.

## Self-review

- Confirmed every current picker value has a `Structure` constructor and matching typed replica and operation variants.
- Confirmed home, MV-register, and structure sheets use the shared client launcher and route-specific mount IDs.
- Confirmed family open state, selection, and OR-map mode survive Lustre renders without the deleted JavaScript panel controller.
- Confirmed stale delivery messages cannot alter a reset generation.
- Confirmed the reconnect order preserves concurrent MV-register alternatives and reset discards old work.
- Confirmed SSR parity, mobile fit, no-JavaScript content, blocked-bundle fallbacks, and the absence of Astro runtime scripts through the named browser tests.
- Confirmed no production import of `website/src/scripts/demo.ts` remains.

## Fix round 1/5

### Status and commit

All ten Important findings and both Minor findings are fixed in implementation
commit `3fcf0684696810edd8627c9150a34da4ca22d884`
(`fix(website): complete native structure demos`). The commit has no
`Co-authored-by` trailer.

### Files changed

- `website_lustre/src/watershed_site/client/structure_demo.gleam`
- `website_lustre/src/watershed_site/client/structure_demo_ffi.mjs`
- `website_lustre/src/watershed_site/route.gleam`
- `website_lustre/src/watershed_site/structure_demo/family.gleam`
- `website_lustre/src/watershed_site/structure_demo/model.gleam`
- `website_lustre/src/watershed_site/structure_demo/runtime.gleam`
- `website_lustre/src/watershed_site/structure_demo/view.gleam`
- `website_lustre/test/browser/home.mjs`
- `website_lustre/test/browser/mv-register.mjs`
- `website_lustre/test/browser/structure-pages.mjs`
- `website_lustre/test/route_test.gleam`
- `website_lustre/test/structure_demo_runtime_test.gleam`
- `website_lustre/test/structure_demo_view_test.gleam`

### Decisions

- Client B now owns the disconnected boundary. Operations from A and C are
  sequenced and applied to A and C while B is offline, then retained as
  B-only catch-up work. B-authored operations remain parked. Reconnect queues
  catch-up before B's local submissions, preserving FIFO acknowledgement
  order for consecutive MV-register writes.
- Visible commands defer typed messages through `watershed_lustre.perform`.
  The result applies against the latest model and carries the current
  generation. Delivery and flow cleanup use generation-tagged
  `watershed_lustre.after` messages, so stale work cannot cross selection or
  reset boundaries.
- Replay retains the last eligible sequenced operation and re-applies it as a
  duplicate remote delivery under its original sequence number. Replay does
  not increment the sequence counter or restore MV-register alternatives that
  a later resolution removed.
- Structure instances retain replica state, pending work, sequence numbers,
  flows, logs, and replay metadata across panel close/reopen and structure
  selection. OR-map instance switching restores the prior OR-map state.
- Every current picker structure now has live Lustre commands, typed kernel
  delivery, model-derived values, and an interactive browser check. Set row
  classes are also model-derived so G-set, OR-set, and 2P-set expose the
  correct visible action.
- MV-register drafts are controlled model state. Click and Enter submit the
  current draft.
- Structure routes load `home.css`, which owns the shared rig and control
  styles, in addition to `structure-sheet.css`.
- Runtime failures render with `role="alert"` independently of the link state.
  Link copy and `aria-pressed` derive from `model.link_up`.
- Playback speed is separate from hop latency. Jitter is sampled for delivery,
  flows render from the model and expire through tagged cleanup effects, and
  field-note visibility is model state.
- Family skip links use the active structure's after-demo target.

### Regression coverage

- Gleam transition tests cover two offline B writes in submission and
  acknowledgement order, continued A/C progress while B is disconnected,
  catch-up ordering, replay delivery with the original sequence, resolved
  alternative retention, controlled drafts, and visible failures.
- Homepage browser coverage cuts B's link, verifies link copy and
  `aria-pressed`, and proves A/C progress remains visible.
- MV-register browser coverage submits by Enter, performs two B writes while
  disconnected, checks catch-up before local acknowledgement, and verifies
  replay produces another delivery without allocating a sequence number.
- Structure-page browser coverage opens every implemented family variant,
  checks that its command is visible and enabled, invokes it, and observes the
  sequence counter advance. It also checks route styles, counter interaction,
  and OR-map state retention.

### Commands and outcomes

```text
cd website_lustre && gleam test --target javascript -- structure_demo
```

Result: `128 passed, no failures`.

```text
just website-lustre
```

Result: passed; all four JavaScript bundles built, 68 assets were copied for
each bundle, and the native pages were generated in `website_lustre/dist`.
The command still prints pre-existing dependency deprecation and unrelated
repository warnings.

```text
CI=1 node website_lustre/test/browser/home.mjs
```

Result: `PASS: Homepage SharedMap demo converges without Astro runtime.`

```text
CI=1 node website_lustre/test/browser/structure-pages.mjs
```

Result: `PASS: counters, sets, registers, maps, sequences, coordination, transforms structure page static parity.`

```text
CI=1 node website_lustre/test/browser/mv-register.mjs
```

Result: `PASS: MV register parity, offline resolution, replay, reset, and fallbacks.`

```text
rg 'website/src/scripts/demo' website_lustre/src
```

Result: no matches.

```text
git diff --check
```

Result: no whitespace errors.

### Self-review

- Re-read all ten Important and both Minor findings after the final browser
  fix and matched each finding to implementation and regression coverage.
- Confirmed visible controls dispatch deferred messages rather than mutating
  kernels in DOM or FFI code.
- Confirmed the FFI only positions model-rendered flow markers and does not
  own state, sequencing, delivery, or panel behavior.
- Confirmed disconnected delivery scopes cannot block A/C and reconnect
  processes B-only catch-up before B-authored work.
- Confirmed replay is duplicate delivery, not a newly sequenced operation.
- Confirmed structure and OR-map instance changes retain state while Reset is
  the explicit destructive action.
- Confirmed rendered values, row action visibility, link accessibility state,
  errors, flows, field notes, and drafts derive from the Lustre model.
- Confirmed the required targeted tests, build, browser suites, legacy-import
  search, and whitespace check all pass from the committed implementation.

### Remaining concerns

`just website-lustre` continues to report dependency deprecation warnings and
unrelated warnings from the wider repository. This round introduces no known
functional concern.

## Fix round 2/5

### Status

All nine items left open by the fix-round-1 re-review are fixed.

### Architecture and causal fixes

- `update` no longer executes deferred messages recursively. Kernel creation,
  local mutation, delivery, acknowledgement, reset, and fallible projection
  validation run inside thunks passed to `watershed_lustre.perform`. Tagged
  result messages apply completed transitions and discard stale generations.
- Client B's offline MV-register writes are rolled back on reconnect. B applies
  all missed sequenced work first, then re-authors its local writes in original
  submission order. The final write therefore observes both catch-up and the
  preceding local write, and acknowledgements remain FIFO.
- Replay records the latest eligible sequenced operation and its original
  sequence number. Re-delivery does not allocate a new sequence number or
  restore an alternative removed by a later resolution.
- G-counter, PN-counter, OR-map, and OR-set replicas load one shared baseline
  summary under distinct local replica IDs. Their first delivered deltas no
  longer merge separately authored copies of the displayed baseline.
- Projection validation reports replica/type and map-decoding failures through
  `visible_error` instead of replacing them with a successful default display.

### Interaction and motion fixes

- LWW-map, LWW-register, OR-map set, and OR-map MV-register controls use
  controlled typed key/value drafts when they create operations.
- Family skip links retain the open plate's after-demo anchor while an OR-map
  subview is selected.
- Jitter samples a random value in the configured range for each scheduled
  hop instead of alternating by sequence parity.
- Flow markers use model playback timing, FFI-derived endpoints, a real CSS
  travel animation, timed cleanup, and a reduced-motion end-state.

### Regression evidence

- MV tests assert exact catch-up, resubmission, sequencing, acknowledgement,
  and log order for two offline B writes.
- Replay tests assert that the retained replay sequence is the latest one and
  that replay leaves the sequence counter and resolved value unchanged.
- CRDT baseline tests deliver the first post-baseline G-counter, PN-counter,
  OR-map, and OR-set operation and assert the baseline is counted once.
- The deferred-effect test asserts the model is unchanged before the returned
  effect runs.
- Projection tests inject a replica/type mismatch and assert the visible error.
- Structure-page browser coverage types a non-preset LWW-map key and value and
  observes both in the rendered state.
- MV-register browser coverage checks catch-up-before-resubmit order, latest
  replay, sampled jitter range, and visible flow movement over time.

### Commands and outcomes

```text
cd website_lustre && gleam check --target javascript
```

Result: compiled successfully.

```text
cd website_lustre && gleam test --target javascript -- structure_demo
```

Result: `131 passed, no failures`.

```text
just website-lustre
```

Result: passed; all four JavaScript bundles built, 68 assets were copied for
each bundle, and the native pages were generated in `website_lustre/dist`.

```text
CI=1 node website_lustre/test/browser/home.mjs
CI=1 node website_lustre/test/browser/structure-pages.mjs
CI=1 node website_lustre/test/browser/mv-register.mjs
```

Result: all three Task 2 browser suites passed.

```text
git diff --check
```

Result: no whitespace errors.

### Remaining concerns

`just website-lustre` still prints the existing dependency deprecation and
unrelated wider-repository warnings. This round adds no known functional
concern.

## Fix round 3/5

### Status

All eight items from the fix-round-2 re-review are fixed.

### Queue and reconnect fixes

- Deferred commands now enter one serialized work queue. Each effect returns
  the model it read and the model it produced. The reducer applies the kernel
  fields to the current model and keeps any controlled input or timing value
  that changed while the effect ran. A completed effect cannot replace newer
  commands with its captured model.
- Reconnect places every B-only catch-up delivery before B's queued local
  submissions. MV-register reconnect rolls back B's pending writes, applies
  the complete A/C catch-up set, re-authors B's writes in submission order, and
  keeps unrelated pending work.
- Offline A/C sequencing now records flows and the latest replay operation on
  the same path as connected sequencing.
- Restoring an instance with pending work always schedules a delivery for the
  restored generation. Stale timers remain generation-gated.

### Projection and race fixes

- Shared-map projection validation checks all three rendered gauges on all
  three replicas. Type mismatches for every other structure still fail through
  the structure/replica validation before the view reads them.
- `RunRace` now submits real visible operations for all 17 structures. The
  structure-page browser suite clicks the race control for every family demo
  and waits for its sequence counter to advance.

### Regression evidence

- MV-register tests cover a B write, an intervening offline A delivery, a
  second B write, reconnect, FIFO acknowledgements, and convergence.
- Map reconnect tests prove A's catch-up sequences before B's resubmitted
  write.
- Offline sequencing tests prove the second A/C operation becomes the retained
  replay.
- An asynchronous effect test starts two commands before the first result
  arrives and proves both edits survive.
- A busy-instance test gives Map and MV-register pending work, restores Map,
  and observes a `Deliver` message tagged with the new generation.
- Projection and race tests cover the invalid non-primary map gauge and every
  structure constructor.

### Commands and outcomes

```text
cd website_lustre && gleam test --target javascript -- structure_demo
```

Result: `139 passed, no failures`.

```text
cd website_lustre && gleam check --target javascript
```

Result: compiled successfully.

```text
just website-lustre
```

Result: passed; all four JavaScript bundles built, 68 assets were copied for
each bundle, and the native pages were generated in `website_lustre/dist`.

```text
CI=1 node website_lustre/test/browser/home.mjs
CI=1 node website_lustre/test/browser/structure-pages.mjs
CI=1 node website_lustre/test/browser/mv-register.mjs
```

Result: all three Task 2 browser suites passed.

```text
git diff --check
```

Result: no whitespace errors.

### Remaining concerns

`just website-lustre` still prints the existing dependency deprecation and
unrelated wider-repository warnings. This round adds no known functional
concern.

## Fix round 4/5

### Status

Fixed the three remaining findings from the fix-round-3 re-review. No
subagents were dispatched.

### Changes

- Before sequencing a new offline A/C write, drain earlier A/C submissions
  in queue order. Keep their B-only catch-up entries and leave B's local
  submissions parked. This prevents an MV-register acknowledgement from
  bypassing an older write from the same origin. Reconnect still applies
  catch-up before rebasing B's local writes.
- Dispatch two member additions for the OR-map string-set race: A adds
  `draft` and B adds `reviewed` to `inspection-brief`. Keep the tally-mode
  remove/increment race unchanged.
- Track delivery ownership with `delivery_armed` and schedule delivery only
  in `finish_deferred`. Ordinary completions, projections, and flow cleanup
  cannot add a second timer. Keep ownership while a fired delivery waits in
  the deferred queue; release it when that delivery completes. Reset, mode
  changes, and structure selection start a new generation without inherited
  timer ownership. A restored busy instance arms one new-generation timer.
  Old-generation messages remain no-ops.

### Exact regressions

- For both A and C: submit `first` while connected, cut B's link before
  delivery, then submit `second` from the same origin. Assert FIFO log order,
  A/C progress while B stays isolated, no visible error, no stranded kernel
  writes, sequence number 2, and optimistic/sequenced convergence on `second`
  after reconnect. A separate test keeps B's two-write cut-between-submissions
  case covered. The MV browser suite repeats the A and C scenarios.
- Assert separate optimistic `draft` and `reviewed` sets before delivery and
  the exact union `["draft", "reviewed"]` on all three replicas afterward.
  Assert two sequenced operations, empty pending queues, and no mode error.
  The structure-page browser suite checks the same union in string-set mode
  before its existing state-retention checks.
- Execute real deferred and timer effects and count emitted `Deliver`
  messages. Assert one timer across multiple completions, one successor
  after delivery with remaining work, and none after the queue drains.
  Switch Map to busy MV-register and back; assert one timer per generation,
  stale-message rejection, and delivery of the restored Map edit. Also
  exercise a fired timer queued behind an in-flight projection.
- Keep the previous regressions. Delivery-draining test helpers now fail
  on an error or lack of queue progress instead of looping on stranded work.

### Verification evidence

The pre-fix regression run reported `140 passed, 4 failures`: same-origin
FIFO, string-set union, duplicate timers, and duplicate timers on restoration.
The final targeted run reported `145 passed, no failures`.

| Command | Result |
| --- | --- |
| `cd website_lustre && gleam test --target javascript -- structure_demo` | 145 passed, no failures |
| `cd website_lustre && gleam check --target javascript` | Passed |
| `just website-lustre` | Four browser bundles built, 68 assets copied per bundle, native pages generated |
| `CI=1 node website_lustre/test/browser/home.mjs` | Passed |
| `CI=1 node website_lustre/test/browser/structure-pages.mjs` | Passed, including string-set race semantics |
| `CI=1 node website_lustre/test/browser/mv-register.mjs` | Passed, including same-origin cut-link FIFO |
| `rg 'website/src/scripts/demo' website_lustre/src` | No matches |
| `git diff --check` | Passed |

### Remaining concerns

The build still reports the existing dependency deprecations and unrelated
wider-repository warnings. No known remaining defect in the three requested
fixes. This round uses one commit without a `Co-authored-by` trailer.
