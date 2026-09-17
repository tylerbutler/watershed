# LWWMap DDS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task, inline without subagents. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose a string-to-string LWW-map with convergent timestamped
deletion, integrate it into the website's maps family, and demonstrate how
its conflict rules differ from SharedMap.

**Architecture:** Use Lattice's existing deterministic map merge, generate
single-key fragments with its public API, and wrap those fragments in a
pure Watershed kernel. Reuse the LWW clock helper and existing channel
infrastructure, with explicit tombstone and digest handling. Extend the
existing three-client website demo with the compiled kernel and reuse the
structure catalog for the maps page and homepage field sheet.

**Tech Stack:** Gleam, `lattice_maps` 2.0.0 or compatible 2.x,
`gleam_json`, startest, qcheck, Sluice, CRDT simulator, Lustre, Astro, and
the website's existing Node/Puppeteer test tools.

**Spec:** `docs/superpowers/specs/2026-09-09-lattice-dds-expansion-design.md`

**Status:** Shipped. Lattice 2.0.0 resolved the upstream tie-break blocker,
and the completed library and website work now passes the release gates.

**Blocker resolution (2026-09-11):** Equal-time writes compare writer IDs in
UTF-8 byte order on both Erlang and JavaScript. Tombstones beat active values
at the same timestamp. Watershed accepts only v3 summaries. The focused
Unicode and writer contracts pass on both targets.

Upstream report:
[tylerbutler/lattice#182](https://github.com/tylerbutler/lattice/issues/182).

**Scope update (2026-09-10):** Website integration, the maps-family demo,
and an explicit SharedMap comparison are required deliverables, not
follow-up work. Task 6 covers them.

**Prerequisite (complete):** Task 1 of
`docs/superpowers/plans/2026-09-09-lww-register-dds.md` supplies
`lww_clock.next(Int, Int) -> Result(Int, ClockError)`. Reuse the shipped
helper; the standalone register's facade is not a dependency.

## Global constraints

- Keep all dependencies on Hex; do not introduce local-path dependencies.
- LWWMap requires `lattice_maps = ">= 2.0.0 and < 3.0.0"`.
- Preserve existing channel tags, operation formats, and public behavior.
- Support pure kernels on Erlang and JavaScript; do not add a BEAM p2p driver.
- Keep register values and map keys/values as `String` in this release.
- Do not expose LWW-map tombstone pruning or accept pruned map states.
- Keep new mutation errors observable through `Result`; do not use fire-and-forget APIs for fallible edits.
- Include LWWMap website copy and its shared maps-family demo as specified
  below. Keep unrelated website copy and the other two plans unchanged.
- Follow `.github/instructions/website-copy.instructions.md`; preserve the
  site's voice and protected names. Keep assistive text plain and literal.
- Use the compiled Watershed kernel for the demo, not a JavaScript merge
  implementation. Reuse the existing rig; do not add a demo framework.
- If website copy quotes source, use markers, `website/snippets.json`,
  `sourceSnippet`, and `SnippetBlock`. Do not edit or commit the generated
  snippet manifest or use raw source imports.

## Files and interfaces

Create `src/watershed/lww_map_kernel.gleam`,
`test/watershed/lww_map_kernel_test.gleam`,
`test/watershed/lww_map_channel_test.gleam`,
`test/watershed/fuzz/lww_map_model.gleam`, and
`test/watershed/lww_map_fuzz_test.gleam`.

```gleam
pub type LwwMapOperation {
  Set(key: String, value: String, timestamp: Int, delta: lww_map.LWWMap)
  Remove(key: String, timestamp: Int, delta: lww_map.LWWMap)
}

pub type LwwMapEvent {
  ValueChanged(key: String, previous_value: Option(String), value: Option(String))
}
```

`LwwMapState` contains sequenced and optimistic maps, pending operations
with message IDs, `next_pending_message_id`, and a per-key timestamp
dictionary. Accept `ReplicaId` in `new` and load interfaces, bind the Lattice
map to that writer, and retain writer provenance for tie resolution.
Define kernel errors for unexpected ack/rollback, malformed state,
unsupported pruning, and wrapped `ClockError`.

```text
new(ReplicaId) -> LwwMapState
get(LwwMapState, String) -> Result(String, Nil)
entries(LwwMapState) -> List(#(String, String))
keys(LwwMapState) -> List(String)
set(LwwMapState, String, String, Int)
  -> Result(#(LwwMapState, List(LwwMapEvent), LwwMapOperation, Int), KernelError)
remove(LwwMapState, String, Int)
  -> Result(#(LwwMapState, List(LwwMapEvent), LwwMapOperation, Int), KernelError)
```

Add `p2p_set`/`p2p_remove` with the same arguments and a result triple
without a message ID. Also implement `apply_remote`, `p2p_merge`,
`ack_local`, `ack_local_with_message_id`, `rollback`,
`apply_stashed_operation`, `summary`, `from_summary`, `from_sequenced`,
and `check_cache_coherence`. Merge/load operations return `Result` when
checking clock metadata and pruning state.

### Task 1: Establish the Lattice merge contract

**Files:** Create the map kernel test file for dependency contract tests;
this task does not import the future kernel. Read `gleam.toml`,
`manifest.toml`, and the installed LWW-map implementation. Do not change
dependencies or generated manifests.

**Interfaces:** Consume the released `lattice_maps` API. Document its
deterministic equal-time behavior in executable contract tests.

- [ ] Add contract tests for equal-time active writes choosing the greater
  writer ID in UTF-8 byte order. Equal-time removal beats an active value.
  Reject v1/v2 summaries and include Unicode writer IDs on both targets.
- [ ] Run `rtk proxy gleam test --target javascript -- lww_map_kernel`.
  Expect writer, tombstone, v3-only, and Unicode contracts to pass with
  `lattice_maps` 2.0.0. Treat a failure as a dependency discrepancy;
  do not patch merge policy in Watershed.
- [ ] Run the map contract and existing OR-map selectors on both targets:

```bash
rtk proxy gleam test --target erlang -- lww_map_kernel or_map
rtk proxy gleam test --target javascript -- lww_map_kernel or_map
```

- [ ] Commit with `test: cover Lattice LWWMap merge contract`.

### Task 2: Implement the map kernel and tombstone lifecycle

**Files:** Create `src/watershed/lww_map_kernel.gleam`; extend its test
file. Consume `src/watershed/lww_clock.gleam` from the register plan.

**Interfaces:** Produce the map API defined above. The map has no clear,
prune, arbitrary JSON, or replica-ID tie-break API.

- [ ] Add tests for set/get, sorted entries, remove, remove-absent, and
  set-after-remove. In the remove-absent case require a tombstone and an
  outbound operation, but no visible-change event.
- [ ] Add this restoration regression in a test module importing
  `gleam/json`, `lattice_core/replica_id`, `lattice_maps/lww_map`,
  `startest/expect`, and `watershed/lww_map_kernel as kernel`:

```gleam
pub fn reload_observes_tombstone_time_test() -> Nil {
  let removed = lww_map.remove(lww_map.new(), "k", 100)
  let assert Ok(state) =
    kernel.from_summary(
      json.to_string(lww_map.to_json(removed)),
      replica_id.new("b"),
    )
  let assert Ok(#(state, _, kernel.Set(_, _, timestamp, _), _)) =
    kernel.set(state, "k", "restored", 1)
  timestamp |> expect.to_equal(101)
  kernel.get(state, "k") |> expect.to_equal(Ok("restored"))
}
```

- [ ] Run the map kernel selector and confirm missing kernel behavior.
- [ ] Build local fragments with these existing API calls, where
  `timestamp` comes from `lww_clock.next` for the edited key:

```gleam
let set_fragment = lww_map.set(lww_map.new(), key, value, timestamp)
let remove_fragment = lww_map.remove(lww_map.new(), key, timestamp)
```

  Merge the relevant fragment into optimistic state. Queue it for
  sequenced mode or commit it to both states for p2p mode.
- [ ] Decode timestamps from the `state.entries` array in
  `lww_map.to_json`. Observe active entries and tombstones on remote
  edits, summary load, stash replay, and snapshot import. Reject nonzero
  `pruned_timestamp`, nonpositive/unsafe entry timestamps, and duplicate
  keys in incoming envelopes. Zero is reserved for the empty map's
  watermark; an entry at zero would be discarded by Lattice's merge.
- [ ] Implement observed-value events over the sorted union of visible
  keys before and after a merge. Metadata-only writes/removals update
  state and clocks without a visible event.
- [ ] Add strict ack and rollback matching, cache reconstruction,
  pending-summary exclusion, detached promotion, duplicate delivery, and
  replay-without-restamping tests. Preserve clock high-water marks through
  rollback.
- [ ] Test two keys so a large timestamp on `a` does not advance `b`'s
  per-key clock. Test reordered set/remove fragments and full-state merges.
- [ ] Run map/clock kernel selectors on both targets and commit with
  `feat: add LWWMap kernel`.

### Task 3: Integrate channels, wire, and canonical state

**Files:** Modify `src/watershed/channel.gleam`,
`src/watershed/wire.gleam`, `src/watershed/wire/op.gleam`,
`src/watershed/runtime_core.gleam`, and `src/watershed/crdt_core.gleam`.
Create the map channel test file; extend the wire, CRDT-wire, CRDT-core,
and persistence tests.

**Interfaces:** Add `LwwMapChannel`, `InitLwwMap`, `LwwMapState`,
`LwwMapOperation`, `LwwMapEvent`, `LwwMapSnapshot`,
`LwwMapSetEdit(key, value, timestamp)`, and
`LwwMapRemoveEdit(key, timestamp)`. Add core `lww_map_set` and
`lww_map_remove` edits with timestamp arguments and the standard core edit
result; add `lww_map_get -> Result(String, Nil)`, `lww_map_entries ->
List(#(String, String))`, and `lww_map_keys -> List(String)` reads.

- [ ] Add channel tag/summary round trips and detached edit/attach tests.
  Assert the tag is `lwwMap` and tombstones survive a summary round trip.
- [ ] Run the map-channel and wire selectors before adding dispatch.
- [ ] Complete the shared spec's integration checklist, including
  `crdt_core.init_for`, p2p snapshot merge, wrong-kind errors,
  acknowledgment metadata, resubmission, and exhaustive helpers. Exercise
  stash and rollback through the kernel/harness contracts.
- [ ] Encode `lwwMapSet` and `lwwMapRemove` with intent fields and a
  stringified single-key fragment. Require the fragment to contain exactly
  that key and matching value/tombstone/timestamp, with zero pruning
  watermark. Full snapshots may contain multiple distinct keys.
- [ ] Add the canonical projection:

```gleam
"lww_map" ->
  map_member(value, "state", fn(state) {
    map_member(state, "entries", ordered)
  })
```

  Reuse the existing private helpers in `crdt_core.gleam`. Preserve
  timestamps, null tombstone values, and the watermark.
- [ ] Add digest tests for different entry-array orders and different
  tombstones with identical visible maps. Equivalent state must hash the
  same; different retained history must not.
- [ ] Add a three-peer-chain metadata-only removal case and a persistence
  round trip. The third peer must receive the tombstone even when the
  intermediate peer emits no visible event.
- [ ] Run map, clock, wire, runtime-core, CRDT-core, and persistence
  selectors on both applicable targets. Commit with
  `feat: register LWWMap channel`.

### Task 4: Expose facades and effects

**Files:** Modify `src/watershed/runtime.gleam`,
`src/watershed/runtime_beam.gleam`, `src/watershed.gleam`,
`src/watershed_beam.gleam`, `src/watershed/schema.gleam`,
`src/watershed/p2p.gleam`, `src/watershed/crdt_js.gleam`, and both Lustre
effect modules. Extend schema, Sluice driver, CRDT-JS, relay-lifecycle,
and Lustre subscription tests.

**Interfaces:** Add opaque `LwwMap` and phantom `schema.LwwMapChannel`.
Sequenced facades expose create/resolve/handle/typed-field/ensure helpers
using the `lww_map` stem, `lww_map_set` and `lww_map_remove` returning
`Result(Nil, String)`, `lww_map_get -> Result(String, Nil)`,
`lww_map_entries -> List(#(String, String))`, `lww_map_keys ->
List(String)`, and `subscribe_lww_map`.

CRDT functions use `Handle(schema.LwwMapChannel)` and return `P2pError`
for document/handle/edit errors. `lww_map_get` returns
`Result(Result(String, Nil), P2pError)` to distinguish a missing key from
a failed read. Wrap entries/keys in an outer `Result` as well.

- [ ] Add two-client create/typed-attach/resolve/edit tests through both
  sequenced facades. Include removal and restoration after reconnect.
- [ ] Run driver and schema selectors before implementing these APIs.
- [ ] Use existing wall-clock functions in JS and BEAM runtimes. Add
  reply subjects for fallible BEAM mutations rather than fire-and-forget
  messages. Preserve wrong-channel and clock failures.
- [ ] Add `p2p.lww_map_root()` returning
  `CrdtKind(channel.InitLwwMap)`, typed CRDT read/edit/subscription
  functions, and tests using the existing mesh and relay setup.
- [ ] Add `subscribe_lww_map` to both Lustre modules and
  `ensure_lww_map` to the sequenced module. Use effect-perform thunks:

```gleam
crdt.perform(fn() { crdt_js.lww_map_set(map, "status", "ready") }, Outcome)
```

- [ ] Test cancellation, deferred dispatch, and mutation only when the
  effect runs. Run the targeted facade tests on applicable targets and
  `rtk proxy gleam test` from `watershed_lustre/`.
- [ ] Commit with `feat: expose LWWMap APIs and bindings`.

### Task 5: Add a merge-independent model and document semantics

**Files:** Create the model and fuzz test files listed above; modify
`README.md`.

**Interfaces:** Implement the existing `KernelModel` contract. Keep a
reference dictionary of per-key winning timestamp and optional string;
do not use Lattice merge as the model's winner function.

- [ ] Test the oracle's equal-time table before wiring it to the harness:

| Left at time 10 | Right at time 10 | Expected winner |
|---|---|---|
| writer A: `"z"` | writer B: `"a"` | writer B: `"a"` |
| writer B: `"a"` | tombstone | tombstone |
| tombstone | writer B: `"a"` | tombstone |
| tombstone | tombstone | tombstone |

- [ ] Generate repeated keys, equal timestamps across clients, backward
  clocks, absent-key removal, rollback, replay, and summary reload. Check
  visible entries and retained tombstones as well as cache coherence.
- [ ] Add planted left-biased-merge and dropped-tombstone faults; require
  the model to detect each one.
- [ ] Update README with set/get/remove examples and the difference from
  `SharedMap` and OR-map register mode, using Task 6's comparison contract.
  State that equal-time deletion wins, equal-time values compare by writer ID,
  keys are sorted for reads, and pruning is unavailable.
- [ ] Run map/model/clock and affected integration selectors on both
  targets, the Lustre suite, and source/test format checks.
- [ ] Commit with `test: cover LWWMap convergence`.

### Task 6: Integrate the website and demonstrate the SharedMap distinction

**Files:**
- Modify: `website/src/data/structures.ts` (map catalog entry, SharedMap
  cross-comparison, maps-family lede).
- Modify: `website/src/components/Demo.astro` (picker, panels, captions,
  scoped styles and accessible controls).
- Modify: `website/src/scripts/demo.js` (compiled-kernel integration and
  the existing demo lifecycle).
- Modify: `website/src/scripts/tutorial.js` (LWWMap field notes).
- Modify: `website/src/scripts/demo/boot.test.mjs` (kernel-backed cases).
- Create: `website/scripts/lww-map-demo.test.mjs` (browser coverage).
- Modify: `website/package.json` (the `test:lww-map-demo` script).
- Read: `website/src/components/StructureCategory.astro`,
  `website/src/pages/structures/maps.astro`, and
  `website/scripts/mv-register-demo.test.mjs`.

`StructureCategory.astro` derives its picker from the catalog. Add the
LWWMap entry with `onHomepage: true` and no `demoHref`, so it joins the
maps-family rig rather than linking to a separate page. Preserve the
homepage live demo's `views={["map"]}` configuration.

**Interfaces:** Consume the kernel from Task 2, including
`set`/`remove`, `ack_local_with_message_id`, `apply_remote`, `entries`,
`summary`, and `from_summary`. Use the existing demo operation wrapper
`{ operation, messageId, epoch }` for the `lww-map` view. Preserve the
kernel's `Result` failures instead of returning empty success-shaped
views.

Use `[data-lww-map-key]` and `[data-lww-map-input]` for labeled string
inputs, `[data-lww-map-write]` and `[data-lww-map-remove]` for edits, and
`[data-lww-map-entries]` / `[data-lww-map-confirmed]` for JSON-formatted,
sorted optimistic/confirmed entry lists on each client. Show timestamps
and tombstones in `[data-lww-map-metadata]`. The active view's labeled
`select[data-lww-map-race]` has `timestamp`, `writer-tie`, and `remove-tie`
options; the existing `[data-race]` button starts the selected case.
Keep string rendering on `textContent`, including strings that look like
HTML.

**Comparison contract:** Put these distinctions in the LWWMap and SharedMap
catalog explanations and keep the README consistent. The maps-family lede,
demo caption, and field notes must name timestamp order versus server order.

| Question | SharedMap | LWWMap |
|---|---|---|
| Which write wins? | The later operation in the server's sequence for that key | The greater per-key timestamp, independent of arrival or server order |
| What breaks a tie? | The server assigns a total order | The greater writer ID wins between active equal-time writes; a tombstone beats a value |
| What can a value contain? | JSON values, including supported encoded handles | Strings only; no nested JSON or handle traversal |
| Which edits exist? | Set, delete, and clear | Set and remove; no clear or pruning API |
| What does deletion retain? | No CRDT tombstone in the map summary | A timestamped tombstone; older writes cannot resurrect the key, but a newer write can |
| What survives reload? | Confirmed entries and insertion order | Values, timestamps, and tombstones; visible entries read in sorted-key order |
| Where can it converge? | Through the ordered sequenced runtime | Through either the sequenced runtime or the existing JS CRDT mesh/relay paths |
| What does it sacrifice? | A concurrent value for the same key can be overwritten | A concurrent value can also be lost; this is not an MV register or a field-wise merge |

Explain that the runtime supplies wall-clock time and the kernel advances
it past the observed per-key timestamp. Clock skew can still favor a writer
whose clock is ahead; "last" does not guarantee the most recent human
action. Equal-time removal is not unconditional remove-wins. Contrast it
with OR-map's observed-remove add-wins behavior and LWWRegister's author
tie-break. State that this demo uses an in-page sequencer, not real peers.

- [ ] **Step 1: Add a failing kernel-backed demo regression.**
  Add the imports below to `boot.test.mjs`, which already imports `replica`,
  `json`, `test`, and `assert`. Exercise the actual kernels in both orders:

```javascript
import * as lwwMapKernel from "../../../../build/dev/javascript/watershed/watershed/lww_map_kernel.mjs";
import * as mapKernel from "../../../../build/dev/javascript/watershed/watershed/map_kernel.mjs";

test("LWWMap uses timestamps while SharedMap uses stream order", () => {
  const newer = lwwMapKernel.p2p_set(
    lwwMapKernel.new$(replica.new$("a")), "gate-mode", "open", 1_001,
  );
  const older = lwwMapKernel.p2p_set(
    lwwMapKernel.new$(replica.new$("b")), "gate-mode", "closed", 1_000,
  );
  assert.ok(newer.isOk());
  assert.ok(older.isOk());
  const writes = [
    [newer[0][2], new mapKernel.Set("gate-mode", json.string("open"))],
    [older[0][2], new mapKernel.Set("gate-mode", json.string("closed"))],
  ];
  for (const order of [writes, [...writes].reverse()]) {
    let lww = lwwMapKernel.new$(replica.new$("observer"));
    let shared = mapKernel.new$();
    for (const [fragment, operation] of order) {
      const applied = lwwMapKernel.apply_remote(lww, fragment);
      assert.ok(applied.isOk());
      [lww] = applied[0];
      [shared] = mapKernel.apply_remote(shared, operation);
    }
    assert.equal(lwwMapKernel.get(lww, "gate-mode")[0], "open");
    assert.equal(
      json.to_string(mapKernel.get(shared, "gate-mode")[0]),
      json.to_string(order.at(-1)[1].value),
    );
    const before = json.to_string(lwwMapKernel.summary(lww));
    const replayed = lwwMapKernel.apply_remote(lww, older[0][2]);
    assert.ok(replayed.isOk());
    assert.equal(json.to_string(lwwMapKernel.summary(replayed[0][0])), before);
  }
});
```

  Add a source-wiring assertion for `lww_map_kernel.mjs` and the
  `ddsId === "lww-map"` delivery branch, following the existing LWW-register
  wiring assertion. Run `rtk proxy pnpm --dir website run test:demo-boot`;
  the kernel contract should pass after Tasks 1-5, while missing website
  wiring must fail. Source matching alone is not behavioral coverage.

- [ ] **Step 2: Add the browser contract before the UI.**
  Create `lww-map-demo.test.mjs` with the existing MV-register browser
  test's `findBrowser`, `WATERSHED_WEBSITE_URL`, page-error capture, and
  `try/finally` browser cleanup. Chromium is required; do not silently skip.
  Add `"test:lww-map-demo": "node --test scripts/lww-map-demo.test.mjs"`.
  On `/structures/maps`, select `lww-map` by keyboard and use this
  observation helper:

```javascript
async function settled(page, entries) {
  await page.waitForFunction((expected) => {
    const views = [...document.querySelectorAll(
      "[data-lww-map-entries], [data-lww-map-confirmed]",
    )];
    return views.length === 6
      && views.every((view) => view.textContent === JSON.stringify(expected))
      && document.querySelector("[data-status] .converged");
  }, { timeout: 15_000 }, entries);
}
```

  Seed `gate-mode = "surveyed"` at time 100 through the kernel and load
  the summary for all three clients. Each scenario starts after reset
  has restored that baseline. Disable ingress jitter for deterministic
  race assertions; test jitter separately for eventual convergence.

| Race choice | Submit from A first | Submit from B second, before either observes the other | Settled entries |
|---|---|---|---|
| `timestamp` | Set `gate-mode = "open"` at `T + 1` | Set `gate-mode = "closed"` at `T` | `[["gate-mode","open"]]` |
| `writer-tie` | Set `gate-mode = "open"` at `T` as writer A | Set `gate-mode = "closed"` at `T` as writer B | `[["gate-mode","closed"]]` |
| `remove-tie` | Remove `gate-mode` at `T` | Set `gate-mode = "open"` at `T` | `[]`, with a tombstone at `T` |

  Choose a safe `T` above all three clients' observed/issued timestamps
  for `gate-mode`, including pending edits and tombstones. Do not copy
  the register helper's scalar `last_seen` assumption onto a per-key map.
  Assert the logged SN order and timestamps as well as the resulting
  entries; the timestamp race must visibly defeat last-in-stream order.
  Before UI implementation, the browser test must fail on the absent
  picker/control, not on a server or browser setup error.

- [ ] **Step 3: Wire the existing rig to the compiled kernel.**
  Add `lww-map` to `ALL_VIEWS`, picker cells, active-view handling, merge
  rules, render dispatch, pending counts, snapshots/convergence status,
  and per-client state. Initialize from a real kernel summary. Render
  optimistic entries in magenta and confirmed entries in ink; keep a
  removed key's metadata visible. Use `summary` plus the kernel's load/read
  path for confirmed observations rather than treating optimistic values
  as confirmed. Decode display metadata from the published summary format.
  Do not duplicate the merge policy in JavaScript.

  Route edits through the existing `submit`/`deliver` stream. Ack the
  origin by message ID and apply the fragment on the other clients.
  Extend op descriptions, replay eligibility and stored replay operation,
  cut-link held/catch-up queues, stale-epoch rejection, reset, and button
  enablement. Duplicate replay calls remote merge even on the origin;
  it must not attempt to ack an already-acked operation.

  Reset creates fresh baseline states and invalidates only the LWWMap
  epoch, including delayed, held, catch-up, and replay operations. It is
  a demo reset, not a public clear or tombstone-pruning operation. Switching
  views preserves state and must not reset SharedMap, OR-map, or registers.
  Use existing styles and reduced-motion behavior, labeled inputs,
  keyboard controls, and live status output.

- [ ] **Step 4: Complete the catalog and comparison copy.**
  Add `id: "lww-map"`, `name: "LWWMap"`, `module: "lww_map_kernel"`,
  `kind: "CRDT"`, and `onHomepage: true` next to SharedMap. Fill its rule,
  optimistic behavior, summary, how-it-works, and use-case fields from the
  comparison contract. Recommend it for offline shared string settings
  where a deterministic single winner is acceptable; recommend SharedMap
  for server-ordered JSON/handle state. Add reciprocal links between the
  `#map` and `#lww-map` explanations through the demo captions. Update the
  family lede and tutorial recipe without rewriting unrelated structures.

- [ ] **Step 5: Complete lifecycle and regression coverage.**
  Extend the browser test to replay the losing write after the remove
  race, require the tombstone to remain, and then write `"restored"` with
  the ordinary UI. Require a higher timestamp and convergence. Cover
  independent keys, an empty string, and literal `<b>text</b>` input.
  Cut B's link, edit both sides, reconnect, and require pending entries to
  drain. Reset while messages are held and delayed, reconnect, and verify
  stale messages cannot change the baseline. Switch to SharedMap and
  OR-map, use their race controls, then return to the retained LWWMap state.
  Assert no page errors. On `/`, confirm the LWWMap catalog link exists
  while the live demo remains SharedMap-only.

  From the repository root, run the existing targeted Node suites and
  website build:

```bash
rtk proxy pnpm --dir website run test:demo-boot
rtk proxy pnpm --dir website build
```

  Serve that build with
  `rtk proxy pnpm --dir website preview --host 127.0.0.1 --port 4321`,
  then run both browser files in one Node invocation from `website/`:

```bash
rtk proxy node --test scripts/lww-map-demo.test.mjs scripts/mv-register-demo.test.mjs
```

  The website build includes snippet generation and drift/copy gates.
  Stop the preview process after the browser run. Do not mark LWWMap
  shipped until the library tasks, website build, and browser scenarios
  are complete. Commit with `feat: add LWWMap website demo`.

## Execution record

Implementation is on `feat/lww-map`. The checklists above preserve the
implementation recipe; this record gives the current result.

| Area | Result |
|---|---|
| Clock and dependency contracts | Fixed the shared clock's missing safe-integer upper bound. Lattice 2.0.0 resolves ties by writer ID in target-independent UTF-8 order; Unicode contracts pass. |
| Kernel | Added strict v3 decoding, per-key clocks, pending/confirmed state, rollback/stash/summary lifecycle, and canonical key/event ordering. Native merge remains unchanged. |
| Core integration | Added channel and acknowledgment variants, wire codecs, runtime-core edits, digest projection, and metadata-only propagation/persistence coverage. |
| Public APIs and Lustre | Added JS/BEAM typed APIs, CRDT roots/read/edit/subscriptions, mesh/relay lifecycle coverage, and deferred Lustre bindings. |
| Independent model and README | Added intent-based oracle, generated schedules, replay support, clock/reload scenarios, and planted-fault detection; documented the public APIs and map differences. |
| Website | Added the maps-family view and catalog entry, three controlled races, replay/restoration, queued-message reset, and SharedMap comparison. The homepage live demo remains SharedMap-only. |

Final assembled validation:

| Gate | Result |
|---|---|
| Targeted Erlang integration | 449 passed |
| Targeted JavaScript integration | Passed, including the Unicode and writer-tie contracts |
| Lustre | 76 passed |
| Real relay | 321 checks passed |
| Website demo-boot | 7 passed |
| Website build | 44 pages built, including snippet/drift/copy gates |
| Combined LWWMap/MV-register Chromium scenarios | 3 passed, none skipped |
| Gleam formatting and diff whitespace | Passed |

Kernel/core, public API/Lustre, and website reviews completed. The Lattice
2.0.0 upgrade removed the Unicode blocker. The reviews found no additional
significant issues. Browser previews have been stopped.

`node smoke/runtime_bootstrap.mjs` also reports
`Missing HTTP request /trees/`. An isolated archive of unchanged `HEAD`
reproduced the same error. Its fixture and storage paths were not changed
by this work; that pre-existing failure remains outside this plan.

The upstream Unicode issue is resolved. Watershed continues to use Lattice's
native merge without a local replacement.
