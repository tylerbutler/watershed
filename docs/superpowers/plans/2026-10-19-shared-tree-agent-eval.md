# SharedTree Agent Eval Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a portable Vally capability eval that compares agents implementing the same collaborative incident board with Watershed SharedTree and Fluid SharedTree.

**Architecture:** Share the task, browser scenarios, report contract, and comparison runner. Supply separate Gleam/Lustre and TypeScript/React starters with completed UI shells and unfinished native models. Use Vally's Docker task/grade separation, hidden native probes, and real local services; keep completed implementations outside agent-visible assets.

**Tech Stack:** Node >=22.14.0, Vally 0.19.0, Node's test runner, Gleam/Lustre, TypeScript/React, existing esbuild tooling, Chromium/CDP, Podman with Compose and a verified Docker-compatible client for Vally.

**Spec:** `docs/superpowers/specs/2026-10-19-shared-tree-agent-eval-design.md`

## Global Constraints

- "The first eval is API-focused."
- "Use idiomatic Gleam/Lustre for Watershed and TypeScript/React for Fluid."
- "Do not modify either SDK to make a candidate pass."
- "Neither app needs to open the other SDK's documents."
- "Publish these requirements to the agent. Hidden tests vary inputs and schedules, not the requirements."
- "Do not copy the complete host repository into the agent workspace."
- "Use deterministic executable checks, not an LLM judge, for the v1 verdict."
- "Do not retry agent failures."
- "The operator supplies trial count and agent budgets to the runner; record their resolved values and reject a comparison with mismatched settings."
- No paid agent runs until benchmark self-validation succeeds and the operator supplies model, budgets, trial count, and runtime authentication.
- Keep the benchmark self-contained under `evals/shared-tree-app/`; no root npm dependency changes.
- Keep unprepared Gleam manifests as `gleam.toml.in`, materializing `gleam.toml` only in generated workspaces. Trellis discovers committed Gleam packages; it must not try to build unfinished eval starters or private validation fixtures.
- Use repository-native public APIs. Do not add an API compatibility wrapper.
- Reuse browser/service plumbing by extracting or copying the relevant repository-owned utilities into this portable package; do not import upward into `examples/` or root `smoke/` from the finished benchmark.
- Do not copy the existing project-brief model or schema into agent environments.
- Do not edit generated `.code-map/`, APM-managed instructions, or website files.
- This is development tooling; no user-facing library changelog entry.
- Execute inline and commit directly on `main`, as requested by the user.
- Use Podman as the container engine. Vally's backend remains named `docker`;
  verify the client/socket/Compose compatibility before container trials.

## Repository evidence and external contracts

Read these sources before implementing their corresponding tasks:

| Purpose | Source |
| --- | --- |
| Typed schema declarations | `docs/shared-tree-schema-authoring.md` |
| Native property/array edits and subscriptions | `src/watershed/tree.gleam`, particularly `set`, `child`, `array_node`, `array_move_before`, `observe`, `unsubscribe` |
| Native create/open | `src/watershed.gleam`: `create_tree_container`, `open_tree` |
| Lustre lifecycle effects | `watershed_lustre/src/watershed_lustre/tree.gleam`: `create_dev`, `open`, `observe`, `dispose` |
| Existing app lifecycle and local-service setup | `examples/shared_tree_project_brief_lustre/README.md` and its main Gleam module |
| Fluid lifecycle | `examples/shared_tree_project_brief_lustre/fluid/src/fluid.ts` |
| Fluid schema conventions | `examples/shared_tree_project_brief_lustre/fluid/src/schema.ts` |
| Existing browser plumbing | `smoke/cdp.mjs`, `examples/shared_tree_project_brief_lustre/smoke/conditions.mjs`, and its `browser.mjs` |
| Vally staging and command grader | https://microsoft.github.io/vally/guides/writing-eval-specs/ and https://microsoft.github.io/vally/reference/graders/run-command/ |
| Vally Docker backend | https://microsoft.github.io/vally/reference/cli/docker/ |

Vally source inspected while planning: `microsoft/vally` revision
`d3c50cbc67e2e69efa961c7a62eede35e18409b1`, whose core/CLI manifests name
version `0.19.0`. Resolve an exact published build during Task 1 and verify
the documented contracts. If that build lacks required Docker/staging
behavior, stop and report the discrepancy instead of silently using local
execution or exposing hidden tests.

## Files and ownership

Paths below are relative to `evals/shared-tree-app/`.

| Files | Responsibility |
| --- | --- |
| `package.json`, `pnpm-lock.yaml`, `.gitignore`, `README.md` | Standalone tooling package, exact dependencies, generated-artifact exclusions, operator instructions |
| `task.md`, `contract.json` | Shared public requirements, action definitions, selectors, and required check IDs |
| `lib/contract.mjs`, `lib/report.mjs` | Contract validation and strict versioned result handling |
| `watershed/`, `fluid/` | Agent-visible starter templates and native model interfaces |
| `validation/solutions/{watershed,fluid}/` | Maintainer-only correct models |
| `validation/mutations.mjs` | Deliberate candidate defects used to test the graders |
| `graders/{watershed,fluid}/` | Hidden SDK-specific schema/identity/subscription checks |
| `graders/browser.mjs`, `graders/scenarios.mjs`, `graders/main.mjs` | Shared browser acceptance and grading orchestration |
| `lib/cdp.mjs`, `lib/conditions.mjs`, `lib/services.mjs`, `lib/barrier.mjs` | Portable browser/process plumbing and real transport delivery barrier |
| `prepare.mjs`, `lib/staging.mjs`, `lib/sdk.mjs` | Pinned SDK selection, allowlisted workspace assembly, integrity hashes |
| `docker/{Dockerfile,compose.yaml,egress.conf}` | Non-root trial images, fresh services, restricted networking |
| `generate.mjs`, `run.mjs`, `compare.mjs` | Vally spec generation, matched execution, manifest-based comparison |
| `test/*.test.mjs` | Tooling tests; explicit integration tests use real containers/services |

SDK paths passed by the operator are inputs, never committed absolute paths.
Use generated `.work/` and `results/` directories, ignored by Git. Put hidden
assets in a separate generated evaluation input directory from the starter
source; do not stage the package root as agent-visible files.

## Execution dependencies

Task 1 precedes the remaining tasks. Task 2 defines both shell contracts.
Tasks 3 and 4 depend on Task 2 and produce SDK-specific validation fixtures.
Task 5 depends on Tasks 3 and 4. Task 6 consumes the native starter dependency
requirements from Tasks 2-4. Task 7 depends on Tasks 5 and 6. Task 8 depends on
Task 7. Task 9 depends on Task 8. Execute serially by default; no delegation
is required.

### Task 1: Public task contract and strict grading reports

**Files:** Create `package.json`, `pnpm-lock.yaml`, `.gitignore`, `task.md`,
`contract.json`, `lib/contract.mjs`, `lib/report.mjs`,
`test/contract.test.mjs`, `test/report.test.mjs`.

**Interfaces:**

```js
// lib/contract.mjs
export function validateContract(value) {} // returns validated contract; throws on invalid input
export function requiredCheckIds(contract) {} // string[]

// lib/report.mjs
export function validateReport(value, contract) {} // returns validated report; throws
export function verdict(report, contract) {} // "passed" | "failed" | "invalid"
export function summarize(reports, contract) {} // group rates, valid/invalid counts
```

Use this JSON report shape, with no omitted required checks:

```json
{
  "version": 1,
  "runId": "watershed-0001",
  "sdk": "watershed",
  "classification": "agent",
  "checks": [
    {
      "id": "local.assignee-remove",
      "passed": false,
      "durationMs": 12,
      "evidence": "Assignee remains present after removal"
    }
  ]
}
```

Allowed classifications: `agent`, `infrastructure`. A complete successful
trial uses `agent`; `infrastructure` produces `invalid`, never a pass.
Reject duplicate/unknown/missing IDs, non-boolean outcomes, negative or
nonfinite durations, invalid SDK names, and empty failure evidence. During
build failure, mark checks that could not run as failed with the build error
as evidence, not omitted or skipped. Store a separate manifest from Task 8.

- [x] **Step 1:** Write failing report tests with the native Node runner:

```js
import assert from "node:assert/strict";
import test from "node:test";
import { validateReport, verdict } from "../lib/report.mjs";

const contract = { version: 1, checks: [
  { id: "build.native", group: "build" },
  { id: "collaboration.remote", group: "collaboration" },
] };
const report = {
  version: 1, runId: "fluid-0001", sdk: "fluid", classification: "agent",
  checks: contract.checks.map(({ id }) => ({
    id, passed: true, durationMs: 1, evidence: "Observed expected state",
  })),
};

test("missing collaboration check cannot pass", () => {
  assert.throws(() => validateReport({
    ...report, checks: report.checks.slice(0, 1),
  }, contract), /missing/i);
});
test("infrastructure outcome is invalid even with passing checks", () => {
  assert.equal(verdict({
    ...report, classification: "infrastructure",
  }, contract), "invalid");
});
```

- [x] **Step 2:** Run `node --test test/contract.test.mjs test/report.test.mjs`
  from the package directory. Confirm failure because the modules do not exist.
- [x] **Step 3:** Implement the validators and report functions. Write the full
  public task from the spec, including move-before/append semantics, immutable
  identity, missing-target behavior, whole-property strings, optional absence,
  create-once, and error visibility. Define check IDs for each requirement in
  the spec's grading table; use stable IDs rather than positional indices.
- [x] **Step 4:** Add contract tests that require IDs covering build, native
  model, CRUD, moves, identity, live collaboration, concurrency, late join,
  reopen, lifecycle, and visible errors. Confirm incomplete reports fail and
  required-group failure cannot become an overall pass.
- [x] **Step 5:** Add exact tooling dependencies to the standalone manifest:
  Vally core and CLI `0.19.0`, YAML parsing for generated specs, and `ws` for
  CDP. Resolve and lock compatible exact releases; use `pnpm install` after
  manifest creation. Use `"test": "node --test test/*.test.mjs"` and a separate
  `"test:integration"` script for browser/service/container checks. Check the
  installed Vally help for its actual `lint`, Docker, and eval arguments.
- [x] **Step 6:** Run the two test files, inspect their full output, and commit:
  `test(eval): define SharedTree benchmark contract`.

### Task 2: Matched native UI shells and unfinished model interfaces

**Files:** Create `watershed/{package.json,gleam.toml.in,index.html,build.mjs}`,
`watershed/src/incident_eval/{domain,shell,model,schema}.gleam`,
`watershed/src/incident_eval_ffi.mjs`, `watershed/AGENTS.md`,
`fluid/{package.json,tsconfig.json,index.html,build.mjs,AGENTS.md}`,
`fluid/src/{domain.ts,App.tsx,index.tsx,model.ts,schema.ts}`,
`test/integration/{shells,services,serve}.test.mjs`,
`public/{serve,smoke}.mjs`, `lib/{cdp,conditions,services}.mjs`,
`docker/compose.yaml`. Include native dependency lockfiles. Starter AGENTS
restrictions apply to evaluated-agent submissions, not benchmark maintenance,
as confirmed by the operator.

**Interfaces:**

Use the following action union for the JS contract; represent it with
corresponding constructors in Gleam:

```ts
export type Action =
  | { type: "add-incident"; id: string; title: string }
  | { type: "title"; id: string; value: string }
  | { type: "status"; id: string; value: "open" | "investigating" | "resolved" }
  | { type: "assignee"; id: string; value: string | null }
  | { type: "remove-incident"; id: string }
  | { type: "move-incident"; id: string; before: string | null }
  | { type: "add-step"; incident: string; id: string; label: string }
  | { type: "step-label"; incident: string; id: string; value: string }
  | { type: "step-done"; incident: string; id: string; value: boolean }
  | { type: "remove-step"; incident: string; id: string }
  | { type: "move-step"; incident: string; id: string; before: string | null };

export interface Step { id: string; label: string; done: boolean }
export interface Incident {
  id: string; title: string; status: "open" | "investigating" | "resolved";
  assignee?: string; steps: Step[];
}
export interface Board { incidents: Incident[] }
export interface State {
  phase: "opening" | "ready" | "disconnected" | "closed" | "error";
  documentId: string | null; board: Board; errors: string[];
}
export interface Config {
  endpoint: string; documentId: string | null; clientId: string;
}
export interface Session {
  read(): State;
  apply(action: Action): void;
  subscribe(listener: () => void): () => void;
  close(): void;
}
// fluid/src/model.ts: agent-owned
export async function start(config: Config): Promise<Session>;
```

In Gleam, `domain.gleam` owns the equivalent `Board`, `Incident`, `Step`,
`Status`, `Action`, `State`, and `Config` types. `assignee` uses `Option(String)`.
Gleam config adds the native HTTP/socket/tenant/development-secret fields.
Keep model state and internal messages opaque:

```gleam
pub fn init(config: domain.Config) -> #(Model, Effect(Msg))
pub fn update(model: Model, message: Msg) -> #(Model, Effect(Msg))
pub fn apply(model: Model, action: domain.Action) -> #(Model, Effect(Msg))
pub fn close(model: Model) -> #(Model, Effect(Msg))
pub fn read(model: Model) -> domain.State
```

Those are exported declarations to implement in `model.gleam`; no semicolon
declarations go into actual Gleam files. The unfinished model returns a
visible `Not implemented` error and no SDK session. It must compile without
claiming readiness. The Fluid unfinished `start` rejects with that same
message. Candidate schema modules contain no completed board declaration.

Establish the browser/service interfaces here so Tasks 3-4 can run before
the full scenario suite:

```js
export async function startServices({ sdk, root, runId }) {}
// => { appUrl, health(), diagnostics(), close() }
export async function launchBrowser({ executable }) {}
// => { context(), close() }; context => isolated storage + page wrapper
export async function wait(label, probe, predicate, timeoutMs) {}
```

- [x] **Step 1:** Write a browser shell check that injects an SDK-free fake
  model through a test-only entry point. Assert selectors for incident rows,
  title, status, assignee, step rows/labels/completion, add/remove, move-up/down,
  connection state, errors, and Close. Use IDs in selectors, never array indices.
  Assert empty state and multi-row rendering. Fake-model tests must not access
  either SharedTree SDK.
- [x] **Step 2:** Run the shell integration test and confirm a missing entry or
  selector fails. Do not treat a missing browser as a successful skipped test.
- [x] **Step 3:** Implement the two shells against their native interfaces.
  React subscribes/unsubscribes with its lifecycle; Lustre maps model messages
  into shell messages and forwards effects. Generate IDs in the shell with the
  existing UUID facilities. Update the URL after successful creation. Disable
  durable actions outside `ready`. Close remains inert after its first call.
  Show errors with `role="alert"`. Supply a shell-only adapter for serializing
  snapshots/actions in hidden browser checks; do not serialize tree operations.
  Port the small existing CDP/condition utilities into this package rather
  than adding a browser automation framework.
- [x] **Step 4:** Add local build/test scripts using the existing esbuild and
  Gleam patterns. Materialize `.in` manifests in temporary workspaces for tests.
  Keep the browser styles minimal and identical in capability. Provide
  `startServices` and a support-service Compose file for native integration
  tests: pin a Floodgate source revision/image, use its memory backend and
  `/health` route, and pin the Fluid local-service package. The host
  `docker-compose.yml` is configuration prior art, not a portable import.
  Resolve Floodgate's current `main` to a full SHA before building; record the
  SHA and resulting image digest rather than retaining a moving branch.
  Give each test a unique Compose project, fresh state, ephemeral ports, and
  a public URL reachable by its browser. Test readiness before loading the app.
- [x] **Step 5:** Run shell checks for both frameworks. Build both unfinished
  starters and assert that their behavior tests fail on `Not implemented`.
  Commit: `feat(eval): add matched native app starters`.

### Task 3: Watershed validation model and hidden native checks

**Files:** Create `validation/solutions/watershed/{model,schema}.gleam`,
`graders/watershed/native.gleam`, `graders/watershed/probe.mjs`,
`test/watershed.integration.test.mjs`.

**Consumes:** Task 2's immutable domain and shell contracts.

**Produces:** A private passing model; a native probe entry point:

```js
// graders/watershed/probe.mjs
export async function probeWatershed({ page, record }) {}
// page is the Task 5 CDP page wrapper; record accepts a Task 1 check result.
```

The candidate exports a native inspection accessor from its model:

```gleam
pub fn native_tree(model: Model) -> Option(tree.Tree(domain.Board))
pub fn native_document(model: Model) -> Option(watershed.Document(Nil))
```

Include these signatures in the public starter instructions. They expose
existing native handles, not a diagnostic result the grader must trust.

- [ ] **Step 1:** Write checks that create two incidents with two steps, remove
  an assignee, move an incident, move a step, and then edit the original captured
  native refs. Assert the same IDs and expected values. After deletion, assert
  the old ref is detached and another node is unchanged. Validate a real
  `Tree(Board)` schema with nested object/array fields and optional assignee.
  Record native IDs/refs before and after property edits to catch subtree
  replacement even when snapshot equality passes.
- [ ] **Step 2:** Run `node --test test/watershed.integration.test.mjs` against
  the unfinished starter. Confirm failures are behavior failures, not missing
  test imports or incompatible compiled entry points.
- [ ] **Step 3:** Implement the private schema with `schema_builder.object`,
  required/optional properties, and arrays. Implement the private model with
  native create/open, typed refs, `tree.set`, `tree.array_insert`,
  `tree.array_remove_node`, and `tree.array_move_before`. Use captured identity
  or resolve the current ID at action time, never a retained list index.
  Use native observers and actual subscription cleanup. Call `watershed.close`
  on close and on a late-arriving document after close. Surface create/open
  errors and never retry uncertain creation.
- [ ] **Step 4:** Prove that error state remains visible for failed creation
  and opening, and that closing prevents queued app callbacks from reactivating
  the session. Check native subscriptions, not only a shell `closed` flag.
- [ ] **Step 5:** Overlay the private solution only in grader-validation
  workspaces. Run native checks successfully, restore the unfinished starter
  as the agent-visible fixture, and commit:
  `test(eval): validate Watershed native tree usage`.

### Task 4: Fluid validation model and hidden native checks

**Files:** Create `validation/solutions/fluid/{model,schema}.ts`,
`graders/fluid/native.ts`, `graders/fluid/probe.mjs`,
`test/fluid.integration.test.mjs`.

**Consumes:** Task 2's `Action`, `Board`, `State`, `Config`, `Session`.

**Produces:**

```ts
import type { IFluidContainer, TreeView } from "fluid-framework";
import type { BoardNode } from "./schema.ts";
// agent-owned model.ts: accessors documented in starter
export function nativeView(session: Session): TreeView<typeof BoardNode>;
export function nativeContainer(
  session: Session,
): IFluidContainer;
```

The candidate exports its root schema as `BoardNode` from `schema.ts`.
For the unfinished starter, declare a valid empty object schema named
`BoardNode`, without any incident fields, and make these accessors throw
`Not implemented`. The candidate replaces that empty declaration with the
required board schema. Hidden probes must narrow/check the actual schema
before reading incident fields, so an unchanged empty declaration fails with
schema evidence rather than a probe compilation error.

```js
// graders/fluid/probe.mjs
export async function probeFluid({ page, record }) {}
```

- [ ] **Step 1:** Write native checks using real Fluid trees for nested schema,
  optional absence, property edits, original node identity across moves, and
  disposed subscriptions. Use the same values and expected snapshots as Task 3.
  Example identity assertion:

```ts
const original = view.root.incidents[0];
session.apply({ type: "move-incident", id: original.id, before: null });
assert.equal(view.root.incidents.at(-1), original);
session.apply({ type: "title", id: original.id, value: "Mitigated" });
assert.equal(original.title, "Mitigated");
```

- [ ] **Step 2:** Run `node --test test/fluid.integration.test.mjs` against the
  unfinished starter and confirm a model behavior failure.
- [ ] **Step 3:** Implement private schemas using `SchemaFactory` and
  `TreeViewConfiguration`. Use `SharedTree` as a container initial object,
  `AzureClient` local mode, initialize only a newly created view, and attach
  once. Open existing documents without initialization. Observe real tree
  events and dispose the view and container on close. Follow the selected
  SDK's actual exported move API; verify its index/gap semantics with moves
  in both directions and a self-move.
- [ ] **Step 4:** Check native tree/container cleanup after close, failed
  attach/open, and closure during initialization. Keep credentials
  development-only and errors visible.
- [ ] **Step 5:** Run native checks against the private solution, confirm
  the unfinished starter still fails, and commit:
  `test(eval): validate Fluid native tree usage`.

### Task 5: Shared browser acceptance and verified concurrency

**Files:** Modify `lib/{cdp,conditions,services}.mjs`; create `lib/barrier.mjs`,
`graders/{scenarios,browser,main}.mjs`,
`test/{conditions,barrier,grading}.test.mjs`,
`test/browser.integration.test.mjs`.

**Interfaces:**

```js
export async function startServices({ sdk, root, runId }) {}
// => { appUrl, health(), diagnostics(), close() }
export async function launchBrowser({ executable }) {}
// => { context(), close() }; context => isolated storage + page wrapper
export async function wait(label, probe, predicate, timeoutMs) {}
export async function createBarrier({ clients }) {}
// => { hold(), waitForSubmissions(count), release(), evidence(), close() }
export async function runScenarios({ sdk, services, browser, record }) {}
export async function grade({ sdk, workspace, runId, output }) {}
// => validated report, writes JSON atomically before emitting verdict marker
```

Keep the browser/page wrapper small: `goto`, `evaluate`, `click`, `fill`,
`select`, `snapshot`, `errors`, `close`, and transport evidence collection.
Implement actions with actual DOM events and native controls, not direct model
calls. Native probes remain a separate check layer.

- [ ] **Step 1:** Write deadline and barrier tests:

```js
test("barrier rejects sequential delivery as concurrency evidence", async () => {
  const barrier = await createBarrier({ clients: fakeClients });
  await barrier.hold();
  fakeClients.deliverRemote("a", "b");
  await assert.rejects(barrier.waitForSubmissions(2), /delivery|barrier/i);
});
test("late successful probe still exceeds its deadline", async () => {
  await assert.rejects(wait("late", async () => {
    await new Promise(resolve => setTimeout(resolve, 30));
    return true;
  }, Boolean, 5), /late|timed out/i);
});
```

Define `fakeClients` in the test as an event-emitting transport fixture with
`submission`, `remote-delivery`, and `closed` events. It validates harness
accounting only, not SDK convergence.

- [ ] **Step 2:** Run `node --test test/conditions.test.mjs test/barrier.test.mjs`
  and confirm missing module/function failures.
- [ ] **Step 3:** Extend Task 2's CDP/service utilities with transport evidence
  collection and scenario diagnostics. Check process ownership with explicit
  child handles, finite startup waits, reserved ports, and `finally` cleanup.
  Require a working Chromium. Do not stop pre-existing processes.
- [ ] **Step 4:** Implement real delivery control in the trusted service
  proxy. Hold incoming operation delivery to both browser clients while
  allowing their local submissions and required connection control messages.
  Record real operation submissions and release only after both arrive.
  Keep SDK payloads unchanged. Add SDK-specific frame classification behind
  this harness interface, using actual captured transport traffic rather than
  a guessed message format. If either SDK cannot establish the barrier,
  fail the concurrency check with transport evidence.
- [ ] **Step 5:** Implement scenarios for CRUD, assignee removal, both move
  directions, stale identity, no refresh remote updates, distinct-field
  concurrency, concurrent inserts, same-field convergence, late join, reopen,
  and Close. Assert concurrent submissions before convergence and do not
  require either transient local value to remain observable after delivery.
  Preserve winner independence for concurrent moves by not grading a
  prescribed conflicting-move result.
- [ ] **Step 6:** Run all shared scenarios against both private solutions.
  Verify reopen after the other client receives the edit, from a new context,
  after closing the original clients. Test actual native service error paths.
  Record page errors and unhandled rejections as failures.
- [ ] **Step 7:** Run `graders/main.mjs` against a deliberately broken
  candidate; require nonzero exit and a complete failing JSON report.
  Run against both solutions; require valid passing reports and the marker
  `SHARED_TREE_EVAL_ALL_REQUIRED_PASSED`. Commit:
  `test(eval): grade shared two-client behavior`.

### Task 6: Portable allowlisted workspace preparation

**Files:** Create `prepare.mjs`, `lib/{staging,sdk}.mjs`,
`test/{staging,sdk}.test.mjs`.

**Interfaces:**

```js
export async function resolveSdk({ sdk, source, revision }) {}
// => { sdk, revision, packages, sourceFiles, docs, toolchain }
export async function prepare({ sdk, source, revision, out }) {}
// => { agentRoot, gradingRoot, integrityManifest, sdkManifest, docsManifest }
export async function verifyIntegrity({ workspace, manifest }) {}
// => { passed, evidence }; compare protected paths and reject unexpected files
```

The runner materializes an SDK dependency tree under the generated agent
workspace, including the selected source/build packages and lockfile-resolved
dependencies. For Watershed, stage the library `src/`, `watershed_lustre/src/`,
required manifests/assets, and allowlisted docs; exclude their example and
test directories. Resolve path dependencies inside the staged tree. For Fluid,
pack/build the requested local workspace packages and stage their required
dependencies and public source/docs; reject mixed versions or registry
fallback for packages selected from the local SDK build.

- [ ] **Step 1:** Write a staging test with a temporary fake host checkout:

```js
test("does not stage answers, history, or sibling starter", async () => {
  const prepared = await prepare(fixtureOptions);
  const names = await listRelativeFiles(prepared.agentRoot);
  assert.ok(names.includes("src/model.ts"));
  assert.ok(!names.some(name =>
    /(^|\/)(\.git|validation|graders|examples)(\/|$)/.test(name)));
  assert.ok(!names.includes("src/incident_eval/model.gleam"));
});
```

Define `fixtureOptions` with `sdk: "fluid"`, a temporary fake source root,
a fixed fake revision, and a temporary output path. `listRelativeFiles` is
a test helper using `fs.readdir({ recursive: true })` and normalized paths.

- [ ] **Step 2:** Run `node --test test/staging.test.mjs test/sdk.test.mjs`;
  confirm missing preparation logic fails.
- [ ] **Step 3:** Implement explicit source/docs allowlists, reject symlink
  escapes and paths outside selected roots, and hash staged files. Separate
  hidden staging input from agent-visible directories. Preserve the complete
  original SDK revision in the manifest even though `.git` is absent.
- [ ] **Step 4:** Materialize `gleam.toml.in` with staged relative dependencies
  and exact lockfiles. Keep generated workspaces outside Trellis discovery.
  Include clear configuration errors for missing local packages, dirty source
  revisions, unresolved dependencies, and unsupported toolchains. Require
  clean SDK inputs for comparison runs.
- [ ] **Step 5:** Test protected file edits, unexpected files, and changes to
  dependency/build configuration. Overlay only candidate-owned model/schema
  files and candidate test files onto a trusted grader workspace. Never
  execute an agent-modified build script as the grading authority.
- [ ] **Step 6:** Copy the standalone benchmark package into temporary fake
  Watershed and Fluid host layouts and confirm preparation does not depend on
  the host cwd or example paths. Repeat with real explicitly supplied SDK
  checkouts before calling portability validated.
- [ ] **Step 7:** Run preparation tests and commit:
  `feat(eval): prepare isolated native SDK workspaces`.

### Task 7: Vally Docker task/grade environments

**Files:** Create `docker/{Dockerfile,egress.conf}`,
modify `docker/compose.yaml`,
`test/isolation.integration.test.mjs`; update `lib/services.mjs`,
`prepare.mjs` as needed for container paths.

**Consumes:** Prepared workspace and grading roots, SDK manifests.

**Produces:** Digest-addressed non-root task/grade images and trial-specific
Compose service resources usable through Vally's documented backend options.

- [ ] **Step 1:** Write an isolation integration test that launches the
  prepared starter in a task container and tries to read a known host-only
  canary, the other starter, hidden tests, and validation solutions. Assert
  failure. The canary contains a harmless generated test value, not a secret.
  Also assert that `curl https://github.com` cannot download example source
  while the intended local service remains responsive.
- [ ] **Step 2:** Run `node --test test/isolation.integration.test.mjs`.
  Missing Docker is an explicit failed preflight, never a skip/pass.
- [ ] **Step 3:** Build images containing exact Vally core/CLI versions,
  non-root user, POSIX shell, Node, Git, coreutils, native toolchains,
  preinstalled dependencies, and Chromium in the grading image. No host
  repository mounts, host home mounts, Docker socket, or privileged mode.
  Provide only generated task/grading inputs to the respective Vally roles.
  Vally 0.19.0 hardcodes the `docker` executable, including `context inspect`.
  Use a Docker-compatible client connected to Podman's socket and verify
  those operations; do not assume that aliasing `docker` to `podman` works.
- [ ] **Step 4:** Configure fresh support-service state per trial through
  Vally's `compose-file` option. Make the grade role use its own fresh service
  state so no agent background process or service mutation becomes trusted
  grader infrastructure. Local collaboration/reopen checks share one service
  lifetime within grading.
- [ ] **Step 5:** Enforce an internal task network with no general external
  egress. Permit executor model/authentication requests through a controlled
  runtime gateway whose credentials remain outside the agent workspace.
  The gateway permits only the selected provider's required request routes,
  not arbitrary URL fetching, CONNECT tunnels, or package downloads.
  Test the chosen Copilot SDK provider configuration with this route.
  If isolation cannot preserve runtime access without general tool egress,
  stop and report that blocker rather than claiming isolation.
- [ ] **Step 6:** Run task then grade with Vally Docker using a no-model
  deterministic executor fixture supported by the installed version. Verify
  that hidden assets appear only after task completion, artifacts export
  before cleanup, and secrets do not enter manifests or logs. If the
  deterministic executor requires a plugin, use the installed core's mock
  executor via a small validation-only package, excluded from agent inputs.
- [ ] **Step 7:** Confirm image core version equals host core version, record
  image digests, and commit:
  `feat(eval): isolate Vally task and grading roles`.

### Task 8: Vally specs, matched runner, and comparison output

**Files:** Create `generate.mjs`, `run.mjs`, `compare.mjs`,
`test/{generate,run,compare}.test.mjs`; update `package.json`, `README.md`.

**Interfaces:**

```js
export function buildSpec({ sdk, prepared, model, reasoningEffort, limits }) {}
// => Vally eval spec object; emitted with YAML.stringify
export async function runPair(options) {}
// options require sources/revisions, model, reasoningEffort, runs, limits, out
export function compare(manifestsAndReports) {}
// => valid/invalid counts, overall/group pass rates, raw metrics by SDK
```

CLI contract:

```sh
node run.mjs \
  --watershed-source /absolute/watershed \
  --watershed-revision FULL_COMMIT_SHA \
  --fluid-source /absolute/FluidFramework \
  --fluid-revision FULL_COMMIT_SHA \
  --model OPERATOR_MODEL --reasoning-effort OPERATOR_EFFORT \
  --runs OPERATOR_TRIAL_COUNT --max-agent-duration OPERATOR_DURATION \
  --max-tokens OPERATOR_TOKEN_BUDGET --out /absolute/results
```

Values in uppercase are required operator inputs, not defaults or literal
values to put in a generated spec. Validate duration syntax and positive
integer counts before any process launches.

- [ ] **Step 1:** Write generation tests proving both specs share the task
  hash, check contract, model, reasoning effort, runs, and constraints; only
  SDK-specific paths and commands differ. Reject missing budgets.
- [ ] **Step 2:** Write comparison tests:

```js
test("mismatched models cannot produce comparative rates", () => {
  assert.throws(() => compare([
    fixtureRun({ sdk: "watershed", model: "one" }),
    fixtureRun({ sdk: "fluid", model: "two" }),
  ]), /model/i);
});
test("invalid trial remains visible without counting as agent failure", () => {
  const summary = compare([
    fixtureRun({ sdk: "watershed", outcome: "invalid" }),
    fixtureRun({ sdk: "fluid", outcome: "passed" }),
  ]);
  assert.equal(summary.watershed.invalidTrials, 1);
  assert.equal(summary.watershed.validTrials, 0);
  assert.equal(summary.watershed.passRate, null);
});
```

Implement `fixtureRun` as a complete in-test manifest/report builder using
Task 1's full required check list. Do not relax validation for test fixtures.

- [ ] **Step 3:** Run `node --test test/generate.test.mjs test/run.test.mjs
  test/compare.test.mjs` and confirm absent runner functions fail.
- [ ] **Step 4:** Generate specs using actual Vally fields:

```js
const spec = {
  name: `shared-tree-app-${sdk}`,
  version: "1.0",
  type: "capability",
  defaults: {
    executor: "copilot-sdk", model, reasoning_effort: reasoningEffort, runs: 1,
  },
  agent_environment: {
    files: [{ src: prepared.agentRoot, dest: "." }],
  },
  grading_environment: {
    files: [{ src: prepared.gradingRoot, dest: ".vally-grading" }],
  },
  stimuli: [{
    name: "incident-response-board",
    prompt,
    constraints: {
      max_agent_duration: limits.agentDuration,
      max_tokens: limits.maxTokens,
    },
    graders: [{
      type: "run-command",
      config: {
        command: "node",
        args: [".vally-grading/graders/main.mjs", "--sdk", sdk],
        expected_exit_code: 0,
        stdout_contains: "SHARED_TREE_EVAL_ALL_REQUIRED_PASSED",
        timeout: "10m",
      },
    }],
    tags: { api: "shared-tree", sdk, track: "core" },
  }],
  scoring: { threshold: 1 },
};
```

`prompt` combines shared `task.md` with the selected starter's commands.
Pass `reasoningEffort` into `buildSpec` explicitly. Set `defaults.timeout` to
the operator's working limit plus a 60-second executor cleanup grace, and
record both limits. Grade timeout is separate. The outer runner controls repetitions
and alternates SDK order; each generated Vally trial uses `runs: 1`.

- [ ] **Step 5:** Invoke the installed Vally CLI with argument arrays,
  `--backend docker`, task/grade image digests, selected networks, support
  Compose file, `--max-retries 0`, `--workers 1`, `--require-pass`, and
  `--eval-spec`. Vally otherwise defaults to two retries, which violates
  the trial policy. Validate generated specs with the installed
  Vally linter before execution. Preserve raw Vally outputs and the exact
  effective spec alongside benchmark reports.
- [ ] **Step 6:** Preflight service/browser/toolchain availability before the
  agent. Classify candidate compile/action failures as agent failures.
  Classify independent service health failures as invalid. No automatic
  replacement trials. Capture raw SDK diagnostics so a timeout does not
  decide classification on its own.
- [ ] **Step 7:** Record revision/package/toolchain/docs/image manifests,
  candidate diffs, trajectory, timings, and reports. Extract metrics from
  Vally's actual result schema; use `null` with an explanation when absent.
  Report cost only with complete matching provider cost identity. Compute
  wall time for agent execution separately from preparation and grading.
  Preserve all raw records; never claim statistical significance from a
  small pilot.
- [ ] **Step 8:** Test the CLI with a deterministic fake Vally subprocess:
  fail on unsuccessful exits, absent reports, missing markers, malformed
  artifacts, model/budget/task-hash mismatches, and unsupported result
  formats. Then run a real no-model Docker validation trial for each SDK.
  Commit: `feat(eval): run and compare matched SharedTree trials`.

### Task 9: Benchmark fault injection, documentation, and acceptance

**Files:** Create `validation/mutations.mjs`,
`test/validation.integration.test.mjs`; finish `README.md`.

**Consumes:** Trusted solutions, shared/native graders, staging, Docker runner.

**Produces:** A benchmark that proves it rejects plausible wrong solutions
before an agent comparison begins.

- [ ] **Step 1:** Write a table-driven rejection test:

```js
for (const defect of [
  "local-only", "serialized-root", "replace-subtree", "stale-index",
  "ignore-remote", "reset-on-open", "leak-subscription", "edit-shell",
]) {
  test(`rejects ${defect}`, async () => {
    for (const sdk of ["watershed", "fluid"]) {
      const report = await validateMutant({ sdk, defect });
      assert.equal(verdict(report, contract), "failed");
      assert.ok(report.checks.some(check => !check.passed));
    }
  });
}
```

Implement `validateMutant({sdk, defect})` in the test helper by preparing a
fresh validation workspace, overlaying the corresponding private solution,
applying `validation/mutations.mjs`, and running the full trusted grader.
Each mutant changes one behavior. Verify expected failed check IDs so a
syntax error cannot count as successful detection of stale identity.

- [ ] **Step 2:** Confirm the rejection tests fail before implementing the
  mutations. Add variants that replace a tree field with serialized data,
  retain a stale index, omit an observer, initialize on every open, omit
  cleanup, and modify protected UI assets. Use private fixture implementations,
  not text substitutions dependent on incidental source formatting.
- [ ] **Step 3:** Add failure-injection runs for absent Chromium, service
  startup failure, interrupted service during grading, invalid reports,
  late successful probes, and attempted workspace escape. Assert nonpassing
  results with explicit evidence and the correct agent/infrastructure class.
- [ ] **Step 4:** Verify unfinished starters compile, native probes fail
  against them, private solutions pass, and the mutated solutions fail for
  their intended reasons. Prove the real concurrency checks reject a run
  where delivery occurred before both submissions.
- [ ] **Step 5:** Document dependency preparation, Docker image build and
  digests, source/revision selection, runtime credential environment names,
  generated workspace inspection, self-validation, actual run commands,
  result interpretation, invalid-trial handling, and cleanup ownership.
  Explain that the native language/framework differences remain a confound.
  Do not include credential values or completed model instructions.
- [ ] **Step 6:** Run the complete standalone unit suite, both native
  builds, integration self-validation, generated-spec lint, and portability
  checks from both repository contexts. Record exact commands and observed
  counts in the implementation handoff. If a real Fluid checkout, Docker, or
  provider setup is unavailable, name the unverified requirement and stop
  short of claiming readiness.
- [ ] **Step 7:** Commit: `test(eval): prove benchmark rejects broken apps`.
  Ask the operator for explicit model/budgets/trial count before a paid pilot.
  A successful no-model fixture run is harness validation, not evidence of
  agent performance.

## Plan self-review

| Spec requirement | Implementation task |
| --- | --- |
| One shared task and native language implementations | 1-4 |
| Working shells, unfinished candidate schema/model, public smoke checks | 2 |
| Native nested schema, property edits, optional absence, identity | 3-4 |
| Real services, two contexts, concurrent submissions, winner-independent checks | 5 |
| Late join, delivered-state reopen, Close, visible errors | 3-5 |
| Portable SDK selection, clean pinned sources, no host examples | 6 |
| Hidden grader staging and enforced isolation | 6-7 |
| No general agent egress, executor runtime access, secret-free artifacts | 7 |
| Vally spec validation and task/grade behavior | 7-8 |
| Matched limits, alternating order, retained invalid trials, raw metrics | 8 |
| Baseline solutions, faulty candidates, portability, no paid runs before validation | 9 |

Review types when implementing: shared snapshot/action fields must match their
Gleam equivalents and the selectors in `contract.json`. Hidden native probes
must inspect actual SDK handles, never candidate-generated success diagnostics.
All plan commands describe future implementation validation; none imply that
the benchmark or its containers exist yet.
