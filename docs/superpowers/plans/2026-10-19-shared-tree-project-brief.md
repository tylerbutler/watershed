# SharedTree Project Brief Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build matched Fluid and watershed live project-brief editors with nested objects, a milestone array, and ephemeral field-selection awareness, then compare their real source on the website.

**Architecture:** Each app owns its document lifecycle, typed schema, live form, and awareness integration. SharedTree persists content; Fluid signals and watershed ripples publish selection. Reuse the existing watershed presence driver and example infrastructure rather than adding SDK features or a shared form framework.

**Tech Stack:** Gleam, Lustre 5, watershed native SharedTree, React, TypeScript, Fluid 3.1.0, esbuild, Node's test runner, existing Chromium/CDP smoke helpers, Astro.

**Spec:** `docs/superpowers/specs/2026-10-19-shared-tree-project-brief-design.md`

## Global Constraints

- No Apply or Save buttons.
- Selection is advisory; simultaneous same-field editing is allowed.
- Each edit assigns a string property; do not promise character-level merging.
- Property edits must target the existing object's property.
- Milestones are the only array in the schema.
- No array reordering controls.
- Each inserted milestone receives a fresh UUID in its immutable application `id` field.
- Use node references for edits/removal and stable milestone IDs for keyed rendering and presence.
- Two-second heartbeat and 6.5-second expiry window in both apps.
- Presence must not edit the tree, produce a tree commit, or become part of a saved summary.
- Use `presence.Ripple` explicitly, not automatic server presence.
- Neither app claims to open the other's documents.
- No SDK changes without a separately reviewed concrete blocker.
- Development authentication only; never retry uncertain creation automatically.
- Chromium and both real local services are required for browser acceptance.
- Follow `AGENTS.md`; use STE only in Gleam source comments and error strings.
- Follow `.github/instructions/website-copy.instructions.md` for website prose.
- Source snippets use generated manifests and `SnippetBlock`; never edit generated JSON.
- Do not edit vendored skills/instructions, `.code-map/`, or the pinned item-counter upstream snapshot.
- Commit only task-owned paths, without Co-authored-by trailers.

## Repository evidence and implementation choices

Read these sources before implementing the corresponding task:

- `examples/shared_tree_item_counter_lustre/`: creation, opening, close races,
  isolated pnpm workspace, server entry point, and two-client browser gate.
- `examples/shared_tree_checklist_lustre/src/shared_tree_checklist_lustre/schema.gleam`:
  object declarations, typed properties, and duplicate application-ID checks.
- `examples/shared_tree_checklist_lustre/src/shared_tree_checklist_lustre/checklist.gleam`:
  capture array node references from a current read.
- `src/watershed/tree.gleam:505-658,731-807,918-941`: typed node/property APIs.
- `src/watershed/presence.gleam` and `src/watershed/presence_js.gleam`:
  ripple configuration, immediate metadata updates, expiry, and session identity.
- `watershed_lustre/src/watershed_lustre.gleam:1026-1061`: presence effects.
- `watershed_lustre/src/watershed_lustre/textarea.gleam`: existing IME binding
  suppression and `effect.before_paint` selection restoration. Borrow those
  browser techniques, not its CRDT diff/anchor algorithm.
- `examples/dice_lustre/src/dice_lustre.gleam`: diagnostics polling.
- `website/src/data/sharedtree-item-counter.ts`, its test, and the matching
  Astro page and browser test: source comparisons and responsive rendering.
- `website/scripts/test-files.mjs`: explicit test registration.

The Fluid SDK's high-level `IFluidContainer` does not expose `submitSignal`.
Do not reach through a private container property or cast it to a runtime.
Use the exported `Signaler` from `@fluid-experimental/data-objects@3.1.0` as a
second initial object beside SharedTree. Its public methods are
`submitSignal`, `onSignal`, and `offSignal`. It is an **experimental helper**,
which must be labeled as such in the README and comparison.

This choice was checked against Fluid's `client_v3.1.0` source:

- `experimental/framework/data-objects/src/signaler/signaler.ts`
- `experimental/framework/data-objects/src/signaler/README.md`
- `packages/framework/fluid-static/src/fluidContainer.ts`

Registry metadata confirmed that `@fluid-experimental/data-objects`,
`@fluidframework/azure-client`, and `@fluidframework/azure-local-service`
publish version `3.1.0`. Pin these and `fluid-framework` to `3.1.0`.
Use `InsecureTokenProvider` from `@fluidframework/test-runtime-utils@3.1.0`
for the AzureClient local development connection. The local service command
is `azure-local-service`; document that command rather than requiring users
to locate an unrelated Tinylicious installation.

## File map

Use `E = examples/shared_tree_project_brief_lustre` below. Every `E/...` path
is relative to that exact directory.

| Path | Responsibility |
| --- | --- |
| `E/gleam.toml`, `E/package.json`, `E/pnpm-workspace.yaml`, generated lockfiles, `E/.gitignore` | Isolated Gleam/JS example package and build/check commands |
| `E/src/shared_tree_project_brief_lustre/brief.gleam` | Records, initial values, milestone ID validation |
| `E/src/shared_tree_project_brief_lustre/schema.gleam` | Typed object/array/property descriptors |
| `E/src/shared_tree_project_brief_lustre/edits.gleam` | Node capture and durable edits |
| `E/src/shared_tree_project_brief_lustre/selection.gleam` | Field targets, metadata codec, invalidated-selection filtering |
| `E/src/shared_tree_project_brief_lustre/input.gleam` | Local text input state, composition, caret restoration |
| `E/src/shared_tree_project_brief_lustre.gleam` | Lifecycle, subscriptions, presence effects, keyed form |
| `E/src/shared_tree_project_brief_lustre_ffi.mjs` | Existing URL/proxy pattern and narrow DOM selection I/O |
| `E/index.html`, `E/serve.mjs`, `E/README.md` | Host document, reuse of existing proxy server, run instructions |
| `E/test/shared_tree_project_brief_lustre_test.gleam` | Gleeunit runner plus schema/domain tests |
| `E/test/edits_test.gleam`, `E/test/fixture.gleam`, `E/test/fixture_ffi.mjs` | Actual runtime fixture and identity-targeted mutation tests |
| `E/test/selection_test.gleam`, `E/test/input_test.gleam` | Presence codec/policy and input transition tests |
| `E/fluid/package.json`, `E/fluid/pnpm-workspace.yaml`, `E/fluid/tsconfig.json`, generated lockfile | Independently runnable Fluid package |
| `E/fluid/src/schema.ts`, `E/fluid/src/schema.test.ts` | Equivalent Fluid tree schema and invariants |
| `E/fluid/src/selection.ts`, `E/fluid/src/selection.test.ts` | Targets, metadata validation, signal/heartbeat adapter |
| `E/fluid/src/fluid.ts`, `E/fluid/src/edits.ts`, `E/fluid/src/edits.test.ts` | Container/view lifetime and captured-node mutations |
| `E/fluid/src/BriefInput.tsx`, `E/fluid/src/App.tsx`, `E/fluid/src/index.tsx` | React live form and composition-safe native inputs |
| `E/fluid/index.html`, `E/fluid/serve.mjs` | Fluid host document and static development server |
| `E/smoke/browser.mjs` | The same two-client acceptance scenarios run against both apps |
| `website/src/data/sharedtree-project-brief.ts`, `.test.ts` | Comparison rows with real source attribution |
| `website/src/pages/sharedtree/project-brief.astro` | Source comparison page |
| `website/scripts/sharedtree-project-brief-page.test.mjs` | Static/mobile/keyboard comparison-page gate |
| `website/snippets.json`, `website/scripts/test-files.mjs` | Source and test registration |
| `website/src/pages/sharedtree.astro`, `website/src/pages/sharedtree/item-counter.astro`, `website/src/data/examples.ts` | Discoverability links and example catalog |
| `justfile` | One gate per runnable app plus combined comparison gate |

Do not introduce a cross-framework shared UI package. Do not add dependencies
for field badges, dates, UUIDs, input reconciliation, or browser automation.
Use platform UUIDs, native inputs, CSS, and the repository's browser helpers.

## Task 1: Equivalent schemas with nested milestones

**Files:** Create the package manifests, both schemas, `brief.gleam`, the main
Gleeunit test runner, and `fluid/src/schema.test.ts` from the file map.

**Interfaces produced:**

```gleam
pub type Milestone { Milestone(id: String, title: String, completed: Bool) }
pub type Owner { Owner(name: String, email: String) }
pub type Schedule {
  Schedule(start: String, target: String, milestones: List(Milestone))
}
pub type Review { Review(reviewer: String, approved: Bool) }
pub type ProjectBrief {
  ProjectBrief(title: String, owner: Owner, schedule: Schedule, review: Option(Review))
}
pub fn initial(first_id: String, second_id: String) -> ProjectBrief
pub fn validate_unique_ids(items: List(Milestone)) -> Result(Nil, String)
```

`schema.configuration() -> builder.Root(ProjectBrief)` declares namespace
`shared_tree_project_brief`. Expose these typed property descriptors:

```text
brief_title(): Property(ProjectBrief, String)
owner(): Property(ProjectBrief, Owner)
owner_name(): Property(Owner, String)
owner_email(): Property(Owner, String)
schedule(): Property(ProjectBrief, Schedule)
schedule_start(): Property(Schedule, String)
schedule_target(): Property(Schedule, String)
milestones(): Property(Schedule, List(Milestone))
milestone_id(): Property(Milestone, String)
milestone_title(): Property(Milestone, String)
milestone_completed(): Property(Milestone, Bool)
review(): Property(ProjectBrief, Option(Review))
review_reviewer(): Property(Review, String)
review_approved(): Property(Review, Bool)
```

Fluid exports `Milestone`, `Owner`, `Schedule`, `Review`, `ProjectBrief`,
`treeConfiguration`, `initial(firstId, secondId)`, and `validateUniqueIds`.
Use equivalent fields, not a JSON-string blob or a map of serialized records.
The initializer returns construction data accepted by `view.initialize`.

- [ ] **1. Add isolated manifests and failing schema tests.** Follow the
  item-counter's JS-target Gleam dependencies; add `gleam_json` directly because
  the selection codec will import it. Root pnpm scripts include `test` for
  `gleam test --target javascript` and `test:browser` for the shared gate.
  Fluid scripts include `check` (`tsc --noEmit`), `test`
  (`node --experimental-strip-types --test src/*.test.ts`), `build`,
  `serve`, and `service` (`azure-local-service`). Use React 19, esbuild,
  TypeScript, and matching type packages; retain a resolved lockfile. Use
  `erasableSyntaxOnly` and `.ts` imports for Node-run TS tests, no enums or
  parameter properties.

  ```gleam
  pub fn nested_brief_round_trip_test() {
    let initial = brief.initial("first", "second")
    let assert Ok(compiled) = builder.compile(schema.configuration())
    let assert Ok(encoded) = builder.encode_new(compiled, initial)
    let assert Ok(decoded) = builder.decode(compiled, encoded)
    let assert True = decoded == initial
    let assert 2 = list.length(decoded.schedule.milestones)
    let assert None = decoded.review
  }
  ```

  Add a round trip with `Some(Review("", False))` and empty/incomplete strings.
  Add rejection of duplicate milestone IDs at snapshot decoding, following
  the checklist's checked constructor pattern. Fluid tests construct a
  detached `new ProjectBrief(initial("first", "second"))` and verify nested
  mutation and duplicate-ID validation.

- [ ] **2. Run the tests red.** From `E`, run
  `gleam test --target javascript`; from `E/fluid`, run `pnpm test`.
  Install only after creating manifests. Confirm failures name the missing
  declarations, not broken dependency resolution.
- [ ] **3. Implement the records and descriptors.** Use compositional `object`
  for a checked schedule constructor and fixed-arity builders where simpler.
  Choose identical sample text in both initializers: title `Release brief`,
  owner `Alex` / `alex@example.test`, start `2026-11-02`, target `2026-11-16`,
  milestones `Agree scope` and `Ship preview`, both incomplete. Generate IDs
  only on creation/append, never while rendering or decoding.
- [ ] **4. Run both schema suites and Fluid `pnpm check` green.** Confirm an
  absent review and a present empty review remain distinct.
- [ ] **5. Commit task-owned files:** `feat(examples): define project brief trees`.

## Task 2: Identity-targeted watershed edits

**Files:** Create `edits.gleam`, `test/fixture.gleam`,
`test/fixture_ffi.mjs`, and `test/edits_test.gleam`.

**Consumes:** Task 1 records and descriptors.

**Produces:**

```gleam
// In test/fixture.gleam:
pub type Fixture {
  Fixture(document: watershed.Document(Nil), tree: tree.Tree(brief.ProjectBrief))
}
pub fn new(initial: brief.ProjectBrief) -> Fixture

// In edits.gleam:
pub type RenderState {
  RenderState(
    value: brief.ProjectBrief,
    root: tree.Ref(brief.ProjectBrief),
    owner: tree.Ref(brief.Owner),
    schedule: tree.Ref(brief.Schedule),
    milestones: tree.Ref(List(brief.Milestone)),
    milestone_nodes: List(#(String, tree.Ref(brief.Milestone))),
    review: Option(tree.Ref(brief.Review)),
  )
}
pub fn capture(handle: tree.Tree(brief.ProjectBrief))
  -> Result(RenderState, error.Error)
pub fn append(schedule: tree.Ref(brief.Schedule), id: String)
  -> Result(Nil, error.Error)
pub fn remove(
  array: tree.Ref(List(brief.Milestone)),
  item: tree.Ref(brief.Milestone),
) -> Result(Nil, error.Error)
```

Leaf edits call `tree.set(captured_ref, typed_property, value)` directly.
`append` reads the current array when the action runs and inserts one
`Milestone(id, "", False)` at its current length. Review add/remove sets
`Some(Review("", False))` / `None` on the captured root.

- [ ] **1. Write failing runtime tests with the actual native tree.** Adapt
  the item-counter test's `fluid_document.initial_tree` /
  `runtime_core.document_seed` / `connect_via_seed` fixture to ProjectBrief.
  Complete the real fixture first; do not mock `tree.set`.

  ```gleam
  pub fn captured_milestone_survives_neighbor_removal_test() {
    let fixture = fixture.new(brief.initial("first", "second"))
    let assert Ok(before) = edits.capture(fixture.tree)
    let assert [#(_, first), #(_, second)] = before.milestone_nodes
    let assert Ok(Nil) = edits.remove(before.milestones, first)
    let assert Ok(Nil) = tree.set(second, schema.milestone_title(), "Still second")
    let assert Ok(after) = tree.read_root(fixture.tree)
    let assert [brief.Milestone("second", "Still second", False)] =
      after.schedule.milestones
    watershed.close(fixture.document)
  }
  ```

  Also capture a review, remove it, add a fresh review, and assert setting the
  old ref fails without modifying the replacement. Repeat that stale-ref
  test for milestones. Verify changing owner name preserves email, schedule,
  title, and review. Do not hardcode a raw error string; assert structured
  invalid-reference failure.
- [ ] **2. Run `cd E && gleam test --target javascript` red.**
- [ ] **3. Implement capture and mutation functions.** Acquire nested refs with
  `required_root`, `child`, and `optional_child`. Capture milestone refs with
  `array_node`; pair IDs read from those refs, not a stale separately zipped
  index list. Remove with `array_remove_node`, not `array_remove(index, end)`.
  Propagate every Result and stop on a failed read.
- [ ] **4. Run the targeted package suite green.**
- [ ] **5. Commit:** `feat(examples): edit brief nodes by identity`.

## Task 3: Selection metadata and ephemeral adapters

**Files:** Create `selection.gleam`, `test/selection_test.gleam`,
`fluid/src/selection.ts`, and `fluid/src/selection.test.ts`.

**Consumes:** The brief snapshot and milestone IDs from Tasks 1-2.

**Produces:** Matching target/metadata codecs and selection invalidation policy.

```typescript
export type FixedField =
  | "title" | "owner.name" | "owner.email"
  | "schedule.start" | "schedule.target"
  | "review.reviewer" | "review.approved";
export type Field =
  | { kind: "fixed"; field: FixedField }
  | { kind: "milestone"; id: string; field: "title" | "completed" };
export interface SelectionMetadata {
  name: string;
  color: "blue" | "green" | "amber" | "violet";
  token: number;
  selected: Field | null;
}
export interface Peer {
  sessionId: string;
  metadata: SelectionMetadata;
}
export interface PresenceSession {
  update(metadata: SelectionMetadata): void;
  stop(): void;
}
export interface SeenPeer {
  metadata: SelectionMetadata;
  seenAt: number;
}
export function receive(
  peers: Map<string, SeenPeer>,
  sessionId: string,
  metadata: SelectionMetadata,
  now: number,
): Map<string, SeenPeer>;
export function expire(
  peers: Map<string, SeenPeer>,
  now: number,
): Map<string, SeenPeer>;
```

Gleam uses an equivalent `Field` sum type, `Metadata` record, `encode`,
`decoder`, `available(field, brief) -> Bool`, and a pure view policy that
suppresses invalidated `(session_id, token)` selections. Convert targets to
deterministic `data-field` keys: fixed paths unchanged, milestone targets as
`milestone/<id>/<field>`.

Fluid exports `startPresence(signaler, container, initial, onPeers, onError)`
returning `PresenceSession`. The signaler's parameter type is `ISignaler`;
the container parameter is `IFluidContainer`. Keep the pure roster reducer
separate from timer/signal wiring inside this file so Node tests need no DOM.

- [ ] **1. Write failing codec and policy cases in both languages.** Include
  valid fixed/milestone/null selections, malformed targets and colors, duplicate
  user names with distinct sessions, stale selections after review removal,
  and a selected milestone whose preceding neighbor disappears.

  ```typescript
  test("expiry removes a peer only after its refreshed liveness window", () => {
    const metadata: SelectionMetadata = {
      name: "Alex", color: "blue", token: 1,
      selected: { kind: "fixed", field: "owner.name" },
    };
    const peers = receive(new Map(), "session-b", metadata, 1_000);
    const refreshed = receive(peers, "session-b", metadata, 3_000);
    assert.equal(expire(refreshed, 9_499).size, 1);
    assert.equal(expire(refreshed, 9_500).size, 0);
  });
  ```

  Define `receive` and `expire` as exported pure functions over a map of
  `{metadata, seenAt}` in the Fluid selection module. Use a monotonic clock
  supplied as a number. Equal tokens refresh liveness; lower tokens must not
  restore an older selection. The same metadata/token repeats on heartbeats.
  Test that invalidated review tokens cannot reappear after recreation and
  that a new focus token can.
- [ ] **2. Run the two package suites red.**
- [ ] **3. Implement the pure metadata and filtering policy.** Increment a
  session-local token on focus changes, including clearing selection. Clamp
  names to a documented reasonable display length; accept only the four
  color tokens and let CSS map them to colors. Never render signal content
  as HTML or take session identity from payload metadata.
- [ ] **4. Implement the small Fluid signal adapter.** Use one named signal,
  `project-brief-selection`, the SDK-stamped sender client ID, and
  `onSignal`/`offSignal`. Send immediately on update/connection and every
  2,000 ms while connected. Sweep expiry on the same timer using 6,500 ms.
  Clear its remote map on local disconnect and reannounce on reconnect.
  Remove listeners and cancel the interval on stop. Ignore unrelated signal
  names; report malformed messages for this signal through `onError`, without
  replacing valid document content or crashing the editor.
- [ ] **5. Add fake-clock adapter checks.** A fake Signaler records sends and
  invokes registered listeners. Assert immediate sends, heartbeat refresh,
  no send while disconnected, reconnect announcement, and no callbacks after
  stop. Test the watershed application policy against driver `presence.State`
  and `presence.Changed` values; do not reimplement driver expiry.
- [ ] **6. Run both suites green and commit:**
  `feat(examples): track ephemeral field selections`.

## Task 4: Runnable watershed live form

**Files:** Create `input.gleam`, `test/input_test.gleam`, the main app, FFI,
`index.html`, `serve.mjs`, and initial `README.md`. Complete root build scripts.

**Consumes:** Typed RenderState, schema, selection metadata, existing
`watershed_lustre/tree` and presence effects.

**Produces:** A runnable Floodgate-backed editor at `http://127.0.0.1:8080`.

The local input module's interface is:

```gleam
pub type Transition { Transition(input: Input, publish: Option(String)) }
pub fn new(value: String) -> Input
pub fn remote(input: Input, value: String) -> Input
pub fn changed(input: Input, value: String) -> Transition
pub fn composition_started(input: Input) -> Input
pub fn composition_ended(input: Input, value: String) -> Transition
pub fn selected(input: Input, start: Int, end: Int) -> Input
```

`remote` always updates the remembered resolved value, but while composing the
view omits its value binding. `changed` publishes outside composition unless it
is the duplicate of the just-ended composition; clear that duplicate sentinel
when consuming it or on a subsequent different edit. Selection offsets are
native UTF-16 offsets, not grapheme indices.

- [ ] **1. Write failing input-state tests.** Define a small local input
  model, not a generic form controller:

  ```gleam
  pub type Input {
    Input(
      value: String,
      composing: Bool,
      composition_end: Option(String),
      selection: Option(#(Int, Int)),
    )
  }
  ```

  Test normal input produces one property assignment, intermediate
  composition produces none, remote snapshots do not change the composing
  DOM binding, and composition end followed by the duplicate final input
  produces one assignment. A later real keystroke must still publish.
  Assert remote updates do not alter another input's local state.
- [ ] **2. Run `gleam test --target javascript` red.**
- [ ] **3. Implement lifecycle from the item-counter, not by copying its
  busy-click gate.** `create_dev` receives `schema.configuration()` and
  `brief.initial(id.uuid_v4(), id.uuid_v4())`. Keep a returned document ID
  before connecting. Use `connect_dev`, then `tree.open`. Register tree
  observation before the initial capture, and capture snapshots/refs together
  on every change through `tree.perform`.

  Do not block or discard rapid input events behind `busy: Bool`.
  Update the local value immediately and schedule each property edit with
  its captured ref. Keep pending/error state separately. A failed edit is
  shown, and the next checked snapshot reconciles the displayed value.
- [ ] **4. Wire presence through existing effects.**

  ```gleam
  let config =
    presence.config(selection.encode, selection.decoder())
    |> presence.with_mode(presence.Ripple)
  ```

  Start through `watershed_lustre.presence`, update through
  `update_presence`, and stop through `stop_presence`. Exclude the local
  entry by `presence_js.local_session`, not user name/key. Handle both
  State and Changed events. Surface driver failures. Use diagnostics polling
  at the existing 250 ms cadence to gate offline editing and clear stale
  visible peers on local disconnect. Recreate the presence handle after a
  lost session so its cached remote roster does not reappear on reconnect.
  Stop polling/rescheduling after close.
- [ ] **5. Render stable native inputs and keyed milestone rows.** Keep input
  IDs and element positions stable. Use `keyed` rows with milestone IDs;
  event handlers capture the corresponding node ref. Focus/blur dispatch
  metadata, including checkboxes. Add badges beside fields, not as children
  that replace the input. Use label `for`/input `id`, visible names, and
  `aria-describedby` for selection status.

  During composition omit the Lustre value binding entirely, following the
  existing textarea pattern. Decode DOM UTF-16 selection offsets from input,
  select, click, and keyboard events. For a remote replacement of the
  focused field, restore the saved range with `effect.before_paint`; clamp
  against the native element's `value.length`, not Gleam grapheme length.
  Skip unchanged selections and never call `focus()` to restore a caret.
  Bind normal string inputs with `attribute.value` outside composition.
- [ ] **6. Implement visible error/close states.** Close must stop presence,
  unsubscribe tree observation, and close the document. Late subscriptions
  are immediately disposed; late document handles are closed. Do not discard
  the result of in-flight creation. Display current connection state and
  disable edits when not ready. Keep a `data-tree-change-count` counter on
  actual tree observation for the presence-only browser assertion.
- [ ] **7. Add host/build/server files and run checks.** Reuse
  `startChecklistServer({appRoot})` rather than copying its proxy. Reuse
  existing URL/proxy FFI behavior, adding only narrow selection DOM I/O.
  Root build script compiles Gleam and bundles the new main module with
  esbuild. Run `gleam test --target javascript` and `pnpm build`; start the
  app briefly and confirm it serves. Full live browser assertions are Task 6.
- [ ] **8. Commit:** `feat(examples): add live watershed brief editor`.

## Task 5: Runnable Fluid live form

**Files:** Create `fluid.ts`, `edits.ts`, `edits.test.ts`, `BriefInput.tsx`,
`App.tsx`, `index.tsx`, `fluid/index.html`, and `fluid/serve.mjs`.
Complete Fluid build scripts and the paired README instructions.

**Consumes:** Task 1 Fluid schema and Task 3 signal adapter.

**Produces:** An independently runnable React editor at
`http://127.0.0.1:8081`, with its local Fluid service at port 7070.

- [ ] **1. Write failing captured-object tests.** Use a detached Fluid
  ProjectBrief for identity tests: capture the second milestone object,
  remove its neighbor, then edit the captured title. Assert the surviving ID
  and value. Test review remove/recreate and removed milestone edits through
  the app mutation helpers; the helper must reject a removed object rather
  than locate another object at its former index. Check status using the
  selected SDK's exported `Tree.status`/`TreeStatus` API.
- [ ] **2. Run `cd E/fluid && pnpm test` red.**
- [ ] **3. Implement creation/loading with typed initial objects.**

  ```typescript
  import { Signaler } from "@fluid-experimental/data-objects";
  import { SharedTree, type ContainerSchema } from "fluid-framework";

  export const containerSchema = {
    initialObjects: { brief: SharedTree, selection: Signaler },
  } satisfies ContainerSchema;
  ```

  Create/load with AzureClient, local `InsecureTokenProvider`, endpoint
  `http://localhost:7070`, and compatibility mode `"2.0.0"` as in the existing
  reference. Initialize the detached tree view before attaching. Put the
  attach result in the URL and never automatically repeat uncertain attach.
  Use `viewWith(treeConfiguration)` and initialize only on new creation.
  Do not reinitialize a loaded document or silently upgrade its schema.
- [ ] **4. Implement edits as direct node property assignments.** Append with
  the public array insertion API and a fresh `crypto.randomUUID()`.
  Remove by finding the captured object in the current array immediately
  before removal; reject if absent. A captured object reference, not an
  index or just the application ID, is the edit target.
- [ ] **5. Subscribe to the live root and render the form.** Subscribe to the
  root's subtree change event (`Tree.on(root, "treeChanged", ...)`) so nested
  mutations rerender. Save and invoke its unsubscribe callback. Include a
  revision counter in React state; do not use unchanged live-root identity as
  the only render trigger. Key milestone rows by immutable application IDs.
  Run `validateUniqueIds` before initializing and after each tree callback;
  show invalid content as an error and disable editing rather than rendering
  ambiguous keyed rows. Increment `data-tree-change-count` only for tree
  callbacks.
- [ ] **6. Use native inputs with explicit composition handling.** In
  `BriefInput`, keep the DOM node in `useRef`, avoid a React-controlled value
  write during composition, and conditionally reconcile in `useLayoutEffect`.
  This is the essential write, not a whole-input replacement:

  ```typescript
  const input = ref.current;
  if (input && !composing.current && input.value !== value) {
    const focused = document.activeElement === input;
    const start = input.selectionStart;
    const end = input.selectionEnd;
    const direction = input.selectionDirection ?? "none";
    input.value = value;
    if (focused && start !== null && end !== null) {
      input.setSelectionRange(
        Math.min(start, value.length),
        Math.min(end, value.length),
        direction,
      );
    }
  }
  ```

  Publish ordinary input immediately. Composition end publishes the completed
  value once; suppress only its duplicate follow-up input, not subsequent
  typing. Use native focus/blur callbacks for presence and the Task 3 adapter
  for badges. Checkboxes use `checked`/change and the same field targeting.
- [ ] **7. Implement lifecycle cleanup and errors.** Subscribe to container
  connected/disconnected/disposed events, gate offline edits, and surface
  edit/connection/selection errors. Stop presence, unsubscribe tree events,
  dispose the tree view and container, and guard late asynchronous creation
  and loading completions. Do not let React development effect replay create
  two documents: create the session once outside component mount effects and
  hand it to the renderer.
- [ ] **8. Run `pnpm test`, `pnpm check`, and `pnpm build` green.** Serve
  the bundle with a small Node static server; reuse the existing example
  static-server entry point if it serves the required root safely without
  starting a second proxy implementation. Document `pnpm service` separately
  from the static app server.
- [ ] **9. Commit:** `feat(examples): add matched Fluid brief editor`.

## Task 6: Two-client acceptance for both apps

**Files:** Create `E/smoke/browser.mjs`; modify `justfile` and `E/README.md`.

**Consumes:** The two runnable apps. Both expose the following DOM contract:

```text
[data-runtime-status]             creating|connecting|ready|disconnected|failed|closed
[data-document-id]                document ID
[data-tree-change-count]          actual tree callbacks, not renders
input[data-field="owner.name"]    same scheme for every fixed string field
[data-milestone-id="<id>"]        keyed milestone row
[data-selection-for="<key>"]      remote selector names for a field
[data-action="add-milestone"]
[data-action="remove-milestone"]  scoped to a milestone row
[data-action="add-review"]
[data-action="remove-review"]
[data-action="close"]
[data-error]                     visible failures
```

The milestone input key is `milestone/<id>/title` or
`milestone/<id>/completed`. Do not use a display index in selectors.

- [ ] **1. Add the failing gate before making browser-specific fixes.** Accept
  `--implementation=watershed` or `--implementation=fluid`; default to both.
  Reuse `smoke/cdp.mjs`, isolated browser contexts, `withPage`, and
  `startChecklistServer`. Preflight every required bundle/service and require
  Chromium. Record browser errors and unhandled rejections per page.
  The Fluid static server must serve the Fluid directory, not the Gleam app.

  Include a condition-based waiter and genuine browser input:

  ```javascript
  await a("Runtime.evaluate", {
    expression: 'document.querySelector(\'input[data-field="owner.name"]\').focus()',
  });
  await a("Input.insertText", { text: "Morgan" });
  // Keep A focused while B edits schedule.target.
  await b("Runtime.evaluate", {
    expression: 'document.querySelector(\'input[data-field="schedule.target"]\').focus()',
  });
  await b("Input.insertText", { text: "2026-11-23" });
  ```

  Read the native input values, active element, and selection ranges in
  predicates. A test that only inspects the JSON model is insufficient.
- [ ] **2. Run each gate and record real failures.** Start the local services
  with the documented commands; do not silently skip a missing prerequisite.
  Do not kill an existing shared service. Start only test-owned app/browser
  processes and clean up those exact processes and temporary profiles.
- [ ] **3. Cover all ten spec acceptance cases.** In particular:
  preserve actual node identity and a non-collapsed selection while a remote
  field and badge change; permit same-field contention without predicting
  the winner; check IME event handling and duplicate input suppression; remove
  and recreate review; remove the milestone preceding the selected one and
  verify its input/badge still use the original ID; append while a peer edits
  an existing item; remove the selected item; test late join, heartbeat,
  expiry, disconnect/reconnect, reload, and close.

  For expiry, terminate/disconnect B without blur while A stays connected,
  record A's last received selection, and wait for disappearance with an
  8.5-second bound (6.5-second TTL plus the two-second sweep allowance).
  No hard sleep should stand in for an assertion.

  For presence-only activity, wait for initial content to settle, capture
  `data-tree-change-count`, change focus and allow a heartbeat, then assert
  the counter is unchanged in both clients. Reload only after delivery/saved
  state is established; retain the same document URL.
- [ ] **4. Fix only demonstrated integration defects.** Keep DOM corrections
  in each app's input/lifecycle boundary, not in SharedTree or the presence
  driver. Repeat the affected scenario, then the full paired gate.
- [ ] **5. Add root recipes and exact README commands.**

  ```just
  shared-tree-project-brief:
      cd examples/shared_tree_project_brief_lustre && corepack pnpm run build
      node examples/shared_tree_project_brief_lustre/smoke/browser.mjs --implementation=watershed

  shared-tree-project-brief-fluid:
      cd examples/shared_tree_project_brief_lustre/fluid && corepack pnpm run build
      node examples/shared_tree_project_brief_lustre/smoke/browser.mjs --implementation=fluid

  shared-tree-project-brief-comparison: shared-tree-project-brief shared-tree-project-brief-fluid
  ```

  Explain required Floodgate and Fluid service processes, ports 8080/8081,
  shared URLs within each implementation, development-only credentials,
  advisory selection, IME exception, string assignment conflicts, and the
  experimental Fluid Signaler. Trellis discovers the new Gleam package;
  do not add it to test exclusions or a handwritten member list.
- [ ] **6. Run both pure suites, Fluid type-check, and
  `just shared-tree-project-brief-comparison` green.**
- [ ] **7. Commit:** `test(examples): gate live brief collaboration`.

## Task 7: Source comparison, registration, and final checks

**Files:** Create the website data/test, Astro page, and browser test listed in
the file map. Modify snippet/test registries, discoverability links, example
catalog, and source files only to add extraction markers.

**Consumes:** Working, tested apps. No upstream source snapshot is involved.

**Produces:** Six comparison rows:
`schema`, `lifecycle`, `observe`, `edits`, `milestones`, `presence`.

- [ ] **1. Write the failing comparison data test.** Require all six rows,
  nonempty source-backed snippets in each language, and GitHub source links
  under this repository's new example path. Require milestone identity and
  ephemeral awareness excerpts, not just schema declarations.

  ```typescript
  assert.deepEqual(projectBriefRows.map(row => row.id), [
    "schema", "lifecycle", "observe", "edits", "milestones", "presence",
  ]);
  for (const row of projectBriefRows) {
    for (const side of ["fluid", "watershed"] as const) {
      for (const snippet of row[side]) {
        assert.ok(isSourceBacked(snippet));
        assert.ok(snippet.code.trim());
        assert.match(snippet.sourcePath,
          /^examples\/shared_tree_project_brief_lustre\//);
        assert.match(snippet.sourceUrl ?? "",
          /^https:\/\/github.com\/tylerbutler\/watershed\/blob\/main\//);
      }
    }
  }
  ```

  Import `projectBriefRows` from the new data module and `isSourceBacked`
  from the existing snippet helper. Run with the website's Node TS runner.
- [ ] **2. Add source markers and manifest entries together.** Use IDs
  `project-brief-<side>-<row>` for the six rows and two sides, adding a
  suffix if one row needs multiple excerpts. Mark complete declarations or
  case branches; do not omit enclosing syntax necessary to understand the
  edit. Put the Gleam presence excerpt around explicit ripple configuration
  and update wiring, and the Fluid excerpt around Signaler usage.

  Reuse the existing manifest schema:

  ```json
  {
    "id": "project-brief-watershed-schema",
    "sourcePath": "examples/shared_tree_project_brief_lustre/src/shared_tree_project_brief_lustre/schema.gleam",
    "language": "gleam",
    "markers": ["project-brief-watershed-schema"]
  }
  ```

  The schema is documented in `tools/source-snippets/README.md`; use
  `"language": "typescript"` for Fluid entries. Run `just snippets` immediately;
  missing/orphaned markers are failures, not warnings.
- [ ] **3. Implement data rows with attribution and accurate explanations.**
  Use `sourceSnippet` and `withSourceUrl`; both sides link to this repository.
  Explain object identity, immutable snapshots vs live views, optional review,
  nested milestone array, and awareness outside the operation stream. State
  the experimental status of Fluid's Signaler helper and separate service
  setup. Do not suggest that SharedSequence provides the same nested schema.
- [ ] **4. Build the page using Sheet and SnippetBlock.** Follow the existing
  two-column source comparison and mobile stacking. Describe trying two
  fields at once, and label same-field string assignment honestly. Reuse the
  house typography/tokens, keyboard-focus styles, and code overflow behavior.
  Do not embed a new website-hosted live runtime or introduce React into the
  Astro site just to show this comparison.
- [ ] **5. Add catalog/links and register both tests.** Link the new page from
  the SharedTree hub and item-counter page. Add the example in the
  composition/presence group with `SharedTree` and `Presence` structures.
  Add the data test to `nodeTestFiles` and the page test to
  `browserTestFiles`; leave existing item-counter provenance tests unchanged.
- [ ] **6. Add a no-JS page browser gate.** Follow
  `sharedtree-item-counter-page.test.mjs`: verify six paired sections,
  local source links, desktop 1440px/mobile 390px layout without document
  overflow, keyboard access to source blocks, and visible focus. Verify
  links back to the hub and item-counter comparison.
- [ ] **7. Run focused checks, then final integration.**

  ```sh
  just snippets
  cd examples/shared_tree_project_brief_lustre && gleam test --target javascript
  cd fluid && pnpm test && pnpm check && pnpm build
  ```

  From the repository root:

  ```sh
  just shared-tree-project-brief-comparison
  cd website && pnpm check:types
  node --strip-types --test src/data/sharedtree-project-brief.test.ts src/data/sharedtree-item-counter.test.ts
  pnpm build
  ```

  Serve the built site with the existing preview workflow and run
  `node --test scripts/sharedtree-project-brief-page.test.mjs` with
  `WATERSHED_REQUIRE_BROWSER=1` and the correct `WATERSHED_WEBSITE_URL`.
  Also run the website test-registry and snippet-config tests so new tests
  cannot be accidentally omitted from normal validation.

- [ ] **8. Review the spec against browser evidence and commit:**
  `docs(website): compare live SharedTree object editors`.

## Self-review and execution gates

- Tasks 1-2 cover schema, optionality, milestones, and node identity.
- Task 3 covers ephemeral metadata, liveness, session attribution, and stale
  selection filtering. No durable presence DDS or SDK work is necessary.
- Tasks 4-5 produce the two runnable live surfaces and handle IME, caret,
  errors, offline gating, and disposal.
- Task 6 checks the requested behavior on actual editing surfaces, including
  the newly approved array scenario, using both services.
- Task 7 covers generated source excerpts, comparison copy, discoverability,
  test registration, and website integration.

Do not call the example complete on pure tests alone. If a required service,
SDK API, browser, or observed concurrency behavior blocks acceptance, report
the exact failure and keep the corresponding checkbox open. Do not weaken
the acceptance gate or silently broaden the SDK change scope.
