# Native SharedTree Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to implement
> this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> Read the specification and this plan before implementation. Stop at the M0
> review gate before implementing M1.

**Goal:** Enable upstream SharedTree 3.1.0, native Watershed JavaScript, and native
Watershed BEAM clients to edit, summarize, and reload the same schema-defined
object tree.

**Architecture:** Establish a pinned upstream oracle and a working service
profile before implementing native semantics. Extend Watershed's document
runtime for Fluid routing, ID compression, and hierarchical summaries, then
integrate a pure Gleam tree kernel with required/optional field rebasing and
retained edit history. Replace incompatible Watershed encodings without a legacy
format layer.

**Tech Stack:** Gleam on Erlang and JavaScript; existing startest/qcheck and sluice
infrastructure; Node test runner for orchestration; pinned Fluid 3.1.0 packages
and source for the development oracle; an explicitly verified Fluid-compatible
service.

**Spec:** [Native SharedTree interoperability](../specs/2026-09-21-shared-tree-design.md)

## Global Constraints

- Production SharedTree semantics must run in pure Gleam on JavaScript and BEAM.
- Upstream TypeScript packages are development/test dependencies, not a production tree engine.
- The initial upstream reference is `@fluidframework/tree` version `3.1.0`.
- The upstream source reference is `microsoft/FluidFramework` commit `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960` (`client_v3.1.0`).
- Existing Watershed document encodings require no backward compatibility or migration.
- Preserve existing DDS behavior while changing shared runtime and storage code.
- Scope the first milestone to an explicit container and schema profile; do not claim arbitrary Fluid document compatibility.
- Reject unsupported semantic formats and operations; do not approximate their meaning.
- SharedTree has a sequenced runtime in this project; peer-to-peer CRDT support is outside this design.
- Apply ASD-STE100 to Gleam comments and error strings, not to this design or other Markdown prose.
- Do not edit apm-managed files or `.code-map/`.

---

## 1. How to execute this plan

This is a large port with a deliberately small first supported profile. An object
field uses a changeset rebaser, detached registers, revision identities, and
history even when its visible conflict rule resembles a map.

M0 contains executable discovery work. M1 specifies module responsibilities,
interfaces, semantic cases, and integration steps. **Do not invent missing
upstream wire details from the Gleam interface examples.** Generate the profile
and fixtures in M0, review the resulting format inventory, and update any M1
interface that the evidence invalidates before implementation.

The code blocks below define initial tests and interface contracts, not a
replacement implementation of upstream algorithms. Each task names the pinned
source algorithms and required additional cases. A green smoke test alone does
not complete a task.

Use an isolated worktree for implementation. This planning change does not need
one. Do not install oracle dependencies or clone/build Fluid merely to review
this plan; do those actions in Task 1 after adding its manifests.

### Dependency order

```text
1 oracle + profile -> 2 real-service preflight -> 3 corpus and native replayer
                                                 |
                                      M0 review / go-no-go
                                                 |
                 4 IDs -----------+--------------+
                                  |
                 5 schema -> 6 forest -> 7 field algebra -> 8 modular changes
                                  |                              |
                                  +------------------------> 9 edit history
                                                               |
                                  4,5,6,8,9 -> 10 tree codecs + kernel
                                                               |
                                2,3,4 -> 11 Fluid document messages
                                                               |
                                  10,11 -> 12 channel/runtime integration
                                                               |
                                      12 -> 13 compatible summaries
                                                               |
                                      13 -> 14 facades + reconnect
                                                               |
                                      14 -> 15 mixed-client acceptance
                                                               |
                                      15 -> 16 regression gates + docs
```

Tasks 4 and 5 can proceed independently after M0. Avoid parallel edits to
`channel.gleam`, `runtime_core.gleam`, or the two runtime/facade pairs. This plan
does not require subagents.

### Task closure

For each task: add the listed failing case, establish that it fails for the
missing behavior, implement the task, run its focused cases on both targets,
review the diff, and commit only that task's files. Use the commit subjects in
the task headings' closing steps. Do not add co-author trailers.

Give new Gleam test functions a `shared_tree_` prefix. The focused command pair
throughout this plan is:

```sh
rtk proxy gleam test --target erlang -- --test-name-filter=shared_tree
rtk proxy gleam test --target javascript -- --test-name-filter=shared_tree
```

Confirm that the runner reports a nonzero executed test count. The equals sign
in `--test-name-filter=shared_tree` matters. Escalate to the root suites when a
task changes existing runtime/codec behavior; do not run the entire website
suite after each isolated tree-algebra edit.

## 2. File map

These are planned paths. Create a file with the task that supplies its behavior,
not an empty scaffold in an earlier task.

| Path | Responsibility |
| --- | --- |
| `tools/shared-tree-oracle/package.json`, `package-lock.json` | Isolated, exact-pinned upstream test dependencies and commands. Follow the existing `tools/shared-rich-text-oracle` package pattern. |
| `tools/shared-tree-oracle/schema.mjs` | One schema and initializer shared by oracle scenarios and the upstream service client. |
| `tools/shared-tree-oracle/oracle.test.mjs` | Oracle health, profile validation, fixture format, and regeneration tests. |
| `tools/shared-tree-oracle/generate.mjs` | Deterministic fixture generation/checking; refuse mismatched source or package versions. |
| `tools/shared-tree-oracle/source.mjs` | Prepare and verify the pinned upstream checkout and invoke its source-level oracle test. |
| `tools/shared-tree-oracle/upstream-oracle.spec.ts` | Source-level access to actual field algebra, edit-manager, compressor, and codec observations. Runs inside the reference checkout, not in production. |
| `tools/shared-tree-oracle/service.mjs` | Real-service upstream preflight and final mixed-client coordinator. |
| `tools/shared-tree-oracle/README.md` | Reproduction, source/package pins, supported profile, service requirements, and fixture provenance. |
| `test/fixtures/shared_tree/profile.json` | Generated codec/configuration/layout inventory and immutable reference identity. |
| `test/fixtures/shared_tree/manifest.json`, `cases/*.json` | Committed upstream-generated cases and coverage domains; filenames appear in the scenario matrix below. |
| `test/watershed/tree/fixtures.gleam` | Strict fixture decoding and normalized observation comparison. No production dependency on fixture types. |
| `src/watershed/fluid_ids.gleam` | Pure document-level compressor, session/stable/op ID conversion, allocation ranges, persistence. |
| `src/watershed/tree/types.gleam` | Shared tree values, edits, errors, revision/atom identity, and ordered sequence points. |
| `src/watershed/tree/schema.gleam` | Stored/view schema validation and the supported fixed-schema profile. |
| `src/watershed/tree/forest.gleam` | Attached and detached tree content, local references, and delta application. |
| `src/watershed/tree/optional_field.gleam` | Required/optional field edit algebra over active and detached registers. |
| `src/watershed/tree/change.gleam` | Modular nested changes, identity aliases, composition, inversion, rebasing, and deltas. |
| `src/watershed/tree/history.gleam` | Trunk/local/peer history, acknowledgements, reconnect, and retained revisions. |
| `src/watershed/tree/codec.gleam` | Tree message/schema/summary codecs for the profile. Split by message versus summary only if the implementation becomes difficult to review as one file. |
| `src/watershed/tree_kernel.gleam` | Pure adapter between tree state and Watershed's channel lifecycle. |
| `src/watershed/wire/fluid_container.gleam` | Container/datastore/channel envelopes, supported runtime messages, batch decoding. |
| `src/watershed/wire/fluid_summary.gleam` | Hierarchical summary representation and enclosing runtime/protocol metadata. |
| `test/watershed/shared_tree_*_test.gleam` | Focused tests for each native subsystem. |
| `test/watershed/shared_tree_client.gleam` | Dual-target command/observation runner for real-service acceptance. |
| `smoke/shared_tree.mjs` | Node orchestration entrypoint, analogous to the existing live JS smoke launchers. |
| `.github/workflows/shared-tree.yml` | Required, non-skipping interoperability gates. Add after the commands work. |

Existing files that require coordinated changes:

- `src/watershed/channel.gleam`, `wire.gleam`, `wire/op.gleam`.
- `src/watershed/handle.gleam` for real datastore/channel handle paths.
- `src/watershed/runtime_core.gleam`, `runtime.gleam`, `runtime_beam.gleam`.
- `src/watershed/git_storage.gleam`, `wire/summary_blob.gleam`.
- `src/watershed.gleam`, `src/watershed_beam.gleam`, `src/watershed/schema.gleam`.
- `src/watershed/sluice/core.gleam`, `sluice/frame.gleam` if batch metadata needs
  better fidelity.
- `src/watershed/crdt_core.gleam` and channel P2P dispatch only to make unsupported
  tree use explicit.
- Existing wire, storage, runtime, bootstrap, facade-parity, and integration tests.
- `justfile`, `.gitignore`, `README.md`; dependency manifests only when a verified
  service/transport requirement calls for a dependency change.

The current JS transport uses Phoenix Channels (`transport_ffi.mjs`), and
`docker-compose.yml` describes a Phoenix endpoint. **Do not assume the stock
Routerlicious driver speaks that transport.** Task 2 must settle the socket,
authentication, discovery, storage, and sequencing path before kernel work.

## 3. Upstream references

Use this prefix for the source paths named below:

```text
https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/
```

| Area | Source paths relative to that commit |
| --- | --- |
| Public oracle setup | `examples/utils/import-testing/src/test/apiExamples.spec.ts`; `packages/dds/tree/src/test/treeDataStore.spec.ts` |
| Deterministic tree runtimes | `packages/dds/tree/src/test/utils.ts` (`TestTreeProviderLite`); `src/test/mocksForOpBunching.ts` relative to the tree package |
| Codec selection | Tree `src/test/shared-tree/sharedTreeCodecTree.spec.ts`; `src/shared-tree-core/messageCodecs.ts`; `src/codec/versioned/` |
| Field algebra | Tree `src/feature-libraries/optional-field/optionalField.ts`, `requiredField.ts`, `optionalFieldChangeTypes.ts`, `optionalFieldCodecV2.ts` |
| Field laws | Tree `src/test/feature-libraries/optional-field/optionalChangeRebaser.test.ts`, `optionalField.spec.ts`, `optionalFieldSnapshots.test.ts` |
| Nested changes | Tree `src/feature-libraries/modular-schema/modularChangeFamily.ts`, `modularChangeTypes.ts`, `invert.ts`, `prune.ts`, `defaultRevisionReplacer.ts` |
| Commit/history | Tree `src/shared-tree-core/editManager.ts`, `branch.ts`, `defaultResubmitMachine.ts`, `editManagerCodecs.ts` |
| Stored content | Tree `src/feature-libraries/forest-summary/`, `schema-index/`, `detachedFieldIndexSummarizer.ts`; `src/core/` delta and forest contracts |
| IDs | `packages/runtime/id-compressor/src/` and its tests; the compressor README explains session/op spaces and clusters |
| Container wire | `packages/runtime/container-runtime/src/messageTypes.ts`, `opLifecycle/`, `summary/`; `packages/runtime/runtime-definitions/src/` |
| Tree summary | Tree `src/shared-tree-core/summaryTypes.ts`; `src/shared-tree/sharedTree.ts` and its summarizable registrations |

Do not depend on `@fluidframework/tree/internal/test` for `TestTreeProviderLite`.
The inspected entrypoint exports `baseTreeModel`, not that helper, and warns
about missing test dependencies. The source-level oracle runs inside a checkout
of the pinned release with its own dependencies.

## 4. Mandatory corpus

Task 3 creates these named cases. Compound cases include each delivery order as
a separate schedule with its own intermediate observations.

| File under `cases/` | Domain and required observation |
| --- | --- |
| `schema-profile.json` | Exact stored schema, schema identifiers, root cardinality, primitive encodings, and incompatible views. |
| `schema-validation.json` | Task 5's schema-only compatibility and value checks, with raw schema strings and input-only native replay. |
| `bootstrap-map-handles.json` | Real root-map discovery, the `"tree"` handle, hierarchical paths, SharedMap op/summary encoding, and missing/wrong-kind bootstrap rejection. |
| `independent-fields.json` | A edits `title`, B edits `enabled`; preserve both edits. |
| `same-field-both-orders.json` | A/B write `title`; compare local pending views and both server orders. |
| `optional-set-clear.json` | Set/clear both orders, absent clear, and re-add. |
| `null-and-absence.json` | Required null leaf versus optional string absence; invalid cross-type assignment. |
| `nested-independent.json` | Edits to `point.x` and `point.y`; preserve both. |
| `parent-child-both-orders.json` | Replace `point` versus edit the original `point.x`; capture detached state as well as visible state. |
| `detached-child-edit.json` | Retain a reference to a removed object, edit it upstream, and verify retained content across reconciliation and reload. |
| `multiple-pending.json` | At least three local commits, a remote commit between deliveries, and ack matching. |
| `batched-commits.json` | Multiple inner commits under the selected batching configuration; record outer and inner sequence positions. |
| `reconnect-before-ack.json` | Disconnect before observing an ack; distinguish server-accepted from never-submitted edits. |
| `summary-tail.json` | Load at S, publish at P where P > S, replay every operation in the interval and later tail. |
| `summary-writer-matrix.json` | Reload and continue editing for each writer/reader combination. Native outputs are added by the acceptance runner, never fabricated by the upstream generator. |
| `id-ranges.json` | Two sessions, local/final forms, eager IDs, interleaved ranges, cluster growth, normalization, and serialized restoration. |
| `field-compose-invert-rebase.json` | Optional/required field algebra and register movement, including simultaneous swaps. |
| `modular-nested-algebra.json` | Nested field changes, aliases, revision replacement, detached builds/refreshers, and pruning. |
| `history-window.json` | Peer branches, stale reference positions, min-sequence advancement, and retained repair data. |
| `unicode-and-numbers.json` | Empty/non-ASCII field keys where the schema permits them, supplementary Unicode, finite doubles, and ID integer precision limits. |
| `invalid-profile.json` | Unsupported versions, array/map schema, malformed allocation, missing blobs, unknown required messages, and atomic refusal. |

A case may contain multiple subcases. Do not equate the number of files with the
number of executions. Record coverage by case ID, target, and comparison domain.

---

## M0: establish the compatibility contract

### Task 1: pin and exercise the real upstream oracle

Implementation: the pinned npm collaboration test and source capture run on the
current `sharedtree` branch, as requested. Source compilation uses upstream's
`build:compile` rather than its full lint/API-report build, and isolated Mocha
uses the required `allow-ff-test-exports` Node condition. The runner obtains
pnpm 11.15.1 through npm exec and excludes only the upstream generated snapshot
output directory to avoid a macOS filename case collision. See the oracle README
for reproduction and the observed codec versions. Full corpus generation and
`--check` remain Task 3 work; no success profile is inferred from this smoke case.

**Files:** Create the oracle package, schema, source runner, upstream oracle test,
oracle tests, and README from the file map. Modify `.gitignore` to ignore only
the oracle package's `node_modules/`, its owned reference checkout, and temporary
output. Do not add a broad ignore for all tools or all fixtures.

**Interfaces:**

- `schema.mjs` exports `Point`, `Root`, `treeConfig`, `rootStore`, and `initialRoot`.
- `source.mjs` supports `prepare`, `verify`, and `generate`; it verifies the exact
  commit before invoking any source-level test.
- `generate.mjs --check` compares newly generated artifacts with committed ones
  without rewriting them; a mismatch exits nonzero.

- [x] **1. Add the smallest upstream collaboration test.**

Use the public construction pattern verified in `apiExamples.spec.ts`:

```js
import assert from "node:assert/strict";
import test from "node:test";
import {
  startEphemeralService,
  cleanupEphemeralService,
} from "@fluidframework/local-driver/alpha";
import { rootStore } from "./schema.mjs";

test("two upstream clients edit the same object tree", async () => {
  const service = startEphemeralService();
  try {
    const client = service.defaultClient;
    const a = await client.createAttachedContainer(rootStore);
    const b = await client.loadContainer(a.id, rootStore);
    a.data.root.title = "upstream";
    b.data.root.point.x = 7;
    await service.synchronize();
    assert.equal(a.data.root.title, "upstream");
    assert.equal(b.data.root.title, "upstream");
    assert.equal(a.data.root.point.x, 7);
    assert.equal(b.data.root.point.x, 7);
  } finally {
    await cleanupEphemeralService();
  }
});
```

- [x] **2. Add the isolated package manifest, install, and run the failing test.**

Use exact `3.1.0` dependencies for `fluid-framework`,
`@fluidframework/tree`, and `@fluidframework/local-driver`. Add a service driver
in Task 2 only after selecting the actual service path. Scripts:

```json
{
  "type": "module",
  "private": true,
  "scripts": {
    "test": "node --test oracle.test.mjs",
    "generate": "node generate.mjs",
    "check": "node generate.mjs --check",
    "source:prepare": "node source.mjs prepare",
    "source:verify": "node source.mjs verify",
    "preflight": "node service.mjs preflight",
    "interop": "node service.mjs interop"
  },
  "dependencies": {
    "@fluidframework/local-driver": "3.1.0",
    "@fluidframework/tree": "3.1.0",
    "fluid-framework": "3.1.0"
  }
}
```

```sh
rtk proxy npm --prefix tools/shared-tree-oracle install
rtk proxy npm --prefix tools/shared-tree-oracle test
```

Expected initial failure: missing `schema.mjs`, not a network or dependency
failure. Resolve install/tool failures before calling this the red test.

- [x] **3. Implement the shared schema.**

```js
import {
  SchemaFactory,
  TreeViewConfiguration,
  defineTreeDataStore,
} from "fluid-framework/alpha";

const sf = new SchemaFactory("org.watershed.shared-tree.m1");
export class Point extends sf.object("Point", {
  x: sf.number,
  y: sf.number,
}) {}
export class Root extends sf.object("Root", {
  title: sf.string,
  enabled: sf.boolean,
  rating: sf.number,
  marker: sf.null,
  note: sf.optional(sf.string),
  point: Point,
}) {}
export const treeConfig = new TreeViewConfiguration({ schema: Root });
export function initialRoot() {
  return new Root({
    title: "",
    enabled: false,
    rating: 0,
    marker: null,
    point: new Point({ x: 0, y: 0 }),
  });
}
export const rootStore = defineTreeDataStore({
  type: "org.watershed.shared-tree.m1.root",
  config: treeConfig,
  initializer: initialRoot,
});
```

The alpha construction API belongs to this pinned test harness. Its release tag
does not extend the production compatibility claim to experimental tree features.

- [x] **4. Implement source verification and low-level capture.**

Use an owned checkout at `tools/shared-tree-oracle/.reference/FluidFramework`.
`source.mjs prepare` clones `client_v3.1.0`, verifies the commit SHA, and installs
using the checkout's documented package-manager configuration and lockfiles.
Refuse to overwrite an existing checkout with another HEAD or user changes.
On later runs, allow the one owned injected oracle test only when its content
matches this repository's source; reject unrelated changes to reference source.

Copy only the owned `upstream-oracle.spec.ts` into the reference tree's
`packages/dds/tree/src/test/watershedOracle.spec.ts`. That test uses existing
source helpers and codec factories. Preserve attribution for any copied
upstream test code. Build with the release's actual scripts:

```sh
rtk proxy pnpm --dir tools/shared-tree-oracle/.reference/FluidFramework/packages/dds/tree run build
rtk proxy pnpm --dir tools/shared-tree-oracle/.reference/FluidFramework/packages/dds/tree run build:test:esm
rtk proxy pnpm --dir tools/shared-tree-oracle/.reference/FluidFramework/packages/dds/tree exec mocha --grep "Watershed oracle"
```

The source runner must set an absolute output directory and capture failure
status. Do not depend on an unverified installed-package private file path.
Use `getCodecTreeForSharedTreeFormat` and `jsonableCodecTree`, as the upstream
codec-tree test does, to record the selected codec dependency graph.

- [x] **5. Make version and corruption checks executable.**

Require generation to fail for a changed checkout SHA, a resolved tree package
other than 3.1.0, an absent output case, or a source test that exits nonzero.
The fixture generator must not replace these failures with empty data.
Record the actual oldest-supported-client setting, message/schema/forest/
history/field codec versions, and compressor serialization version.

- [x] **6. Run the oracle test and commit.**

Expected: two upstream clients converge; source verification succeeds; invalid
source/package identities fail. Commit subject:
`test(tree): pin upstream interoperability oracle`.

### Task 2: establish one real-service profile

Implementation: Floodgate commit
`0eb493fc46d1bb9baf1151a6ccdde93544e057e7` passes the upstream create/edit/
summary/reload case, the official delta-storage read, and native JavaScript
and BEAM Phoenix joins to the same document and published summary. No transport
bridge is needed. The committed profile records the actual formats and paths.
The stock driver's attach rewrite requires `/deltas/{tenantId}/{documentId}`.
An explicit summarizer client avoids depending on asynchronous leader startup.
Runtime GC metadata version 3 is present even with sweep disabled and belongs
to Task 13's required enclosing-summary metadata. Native probes are in
`test/watershed/shared_tree_transport_probe.gleam`; they do not implement tree
loading or edits.

**Files:** Create `tools/shared-tree-oracle/service.mjs`; extend its package
manifest/lockfile and README. Modify the service fixture configuration only as
required. Record service identity and endpoint protocol in `profile.json`.

**Consumes:** `rootStore` and the pinned upstream packages.
**Produces:** A reproducible `preflight` command that creates a real document,
loads it from two upstream clients, edits it, persists it, and loads it from a
fresh client.

The tree-only `rootStore` in Task 1 is an oracle health check. For the supported
service profile, construct one root datastore with a **real upstream SharedMap
bootstrap channel** whose `"tree"` entry holds the SharedTree handle. Use
`treeConfig` and `initialRoot` unchanged for that tree. This preserves
Watershed's map-root facade contract without synthesizing a map that upstream
never created. Pin `@fluidframework/map` to `3.1.0` when adding the bootstrap.
Keep this construction in `service.mjs` and use it for container-format fixtures;
do not label tree-only health-check snapshots as the service profile.

- [x] **1. Write preflight result assertions.**

The service runner returns and writes this diagnostic result on success:

```js
assert.equal(result.referenceVersion, "3.1.0");
assert.equal(result.transportVerified, true);
assert.equal(result.created, true);
assert.equal(result.peerObservedEdit, true);
assert.equal(result.summaryPublished, true);
assert.equal(result.freshClientObservedEdit, true);
assert.equal(result.mockService, false);
```

These fields report completed operations, not selected options. On failure,
print the failed stage and error, exit nonzero, and do not write a success result.

- [x] **2. Probe Floodgate's actual protocol.**

Use the current development service with a fresh document ID and explicit test
credentials supplied through the environment. Establish the stock driver's
socket protocol, authentication, URL resolution, document creation, delta
storage, and summary publication behavior. Do not put access tokens or
authorization headers in committed fixtures.

```sh
rtk proxy npm --prefix tools/shared-tree-oracle run preflight -- --service floodgate
```

Expected initially: either an upstream-only pass or a named protocol failure.
The existing Phoenix transport makes a direct stock-driver success unproven.
An upstream in-memory service does not satisfy this task.

- [x] **3. Resolve the service path before proceeding.**

If stock Fluid and Floodgate interoperate, lock that service revision and driver
configuration. If they do not, run the same upstream case against an actual
upstream reference service to distinguish a service mismatch from an oracle bug.
Document the minimum external prerequisite: a compatible server endpoint, native
transport support, or a correctly implemented Fluid driver.

A transport-only driver is permissible; a bridge that translates or resolves
tree edits using a TypeScript tree on behalf of the native clients is not.
Any new transport must have the same production capability on JS and BEAM.
If this requires an independent service/transport project, stop and obtain its
plan and completed prerequisite before M1. Do not guess its implementation here.

- [x] **4. Freeze the profile manifest from observed behavior.**

The generator writes this schema, with actual populated values:

```ts
type Profile = {
  formatVersion: 1;
  reference: { package: "@fluidframework/tree"; version: "3.1.0"; commit: string };
  service: { implementation: string; revision: string; transport: string };
  container: {
    runtimeOptions: Record<string, unknown>;
    oldestSupportedClient: string;
    channelAttributes: Record<string, unknown>;
    dataStoreTypes: string[];
    bootstrapChannelTypes: string[];
  };
  codecTree: unknown;
  compressorFormat: unknown;
  supportedFeatures: string[];
  excludedFeatures: string[];
};
```

This TypeScript type describes a generated artifact, not production Gleam state.
`unknown` is appropriate at this recording boundary; native codecs later decode
the recorded structures into concrete types. Do not guess version numbers from
the npm major version.

- [x] **5. Re-run preflight and commit the evidence.**

Required: real-service create/edit/summary/reload, an immutable service reference,
and an explicit JS/BEAM transport path. Commit subject:
`test(tree): establish real-service compatibility profile`.

### Task 3: generate the corpus and strict native fixture reader

Implementation: `generate.mjs` assembles the named source/algebra and complete
container cases. The native reader accepts only pinned, manifest-listed cases
and compares complete observations; native semantic runners remain unimplemented.
The oracle README contains the codec/runtime/summary inventory and ownership
table for Tasks 4-16. Source and container fixtures preserve raw upstream data
and carry the initial state and wire inputs needed by an input-only runner.

The pinned public API refuses edits made through an already removed reference.
The detached-child case therefore includes both that refusal and a delayed peer
edit authored while the node was attached, which updates retained content and
survives reload. Unsupported wire data invalidates the upstream public view;
the oracle records fail-stop behavior separately from internal state preservation.
The local container service supplies repeatable protocol artifacts, not a
substitute for Task 2's real-service evidence.
The field case records simultaneous child-change mapping and the pinned forest
visitor's refusal of a direct occupied two-way rename; it does not manufacture
a successful application through a test-owned lowering.

**Files:** Create the fixture manifest/cases, `test/watershed/tree/fixtures.gleam`,
and `test/watershed/shared_tree_fixture_test.gleam`. Extend both oracle generators
and tests. Add `shared-tree-oracle` and `shared-tree-oracle-check` recipes.

**Interfaces:**

```gleam
// test/watershed/tree/fixtures.gleam
pub type Case {
  Case(
    id: String,
    domain: String,
    input: Json,
    expected: Json,
    reference_version: String,
  )
}
pub fn load(name: String) -> Result(Case, String)
pub fn assert_case(
  name: String,
  run: fn(Json) -> Result(Json, String),
) -> Nil
```

`assert_case` decodes the fixture, calls the supplied native domain runner, and
compares complete normalized observations with the upstream expectation.
It reports the first differing JSON path and case ID. Domain runners are added
with the native tasks; no absent runner counts as success.

- [x] **1. Add strict fixture-reader tests.**

```gleam
pub fn shared_tree_fixture_missing_case_is_error_test() {
  fixtures.load("not-a-real-case")
  |> expect.to_be_error
}
```

Add cases for the wrong fixture version, a mismatched reference version, missing
observations, an empty manifest, and malformed JSON. Confirm failure before
implementing the reader.

- [x] **2. Generate the named corpus.**

Use seeded upstream source helpers to record field algebra and edit-manager
state. Use complete upstream containers for runtime envelopes and summary
fixtures. Preserve original raw blobs and operations in addition to normalized
observations. Normalize random session IDs only through a recorded bijection;
do not sort operation lists or discard revision identities.

Use deterministic schedules with explicit `edit`, `deliver`, `disconnect`,
`reconnect`, `summarize`, `load`, and `check` steps. For each check, record visible
data, applicable event observations, pending commits, relevant detached content,
and IDs/history needed by that domain. Avoid requiring the native forest's
private in-memory layout to match upstream's.

- [x] **3. Implement fixture checks and reproducible regeneration.**

`generate --check` generates into an owned temporary directory, compares file
sets and content, and removes only that directory after inspection. The command
must fail when a single expected file or observation changes.

```sh
rtk proxy npm --prefix tools/shared-tree-oracle run generate
rtk proxy npm --prefix tools/shared-tree-oracle run check
rtk proxy gleam test --target erlang -- --test-name-filter=shared_tree
rtk proxy gleam test --target javascript -- --test-name-filter=shared_tree
```

- [x] **4. Review the M0 contract before native implementation.**

Record a coverage table linking the generated codec families, runtime messages,
summary paths, and service requirements to Tasks 4-16. Identify reachable generic
field changes and detached-register moves even though user-facing arrays/moves
are excluded. Reject accidental experimental shared-branch formats.

If a selected runtime option still emits compression, chunks, GC messages,
schema upgrades, or other excluded behavior, either implement the required
behavior in a named task or narrow the supported upstream configuration through
a supported option and regenerate the corpus. Obtain approval if this changes
the specification's capabilities.

- [x] **5. Commit and stop at the review gate.**

Commit subject: `test(tree): capture wire and merge conformance corpus`.

**M0 exit gate:** pinned oracle; strict, nonempty reproducible corpus; successful
real-service preflight; complete codec/runtime inventory; no unresolved
service/transport prerequisite. Do not begin Task 4 with this gate blocked.

---

## M1: native object-tree interoperability

### Task 4: implement document-level ID compression

Implementation: the M0 review gate was released for Task 4. The native compressor
now runs on JavaScript and BEAM, with opaque identities, persistent allocation
state, range finalization, eager IDs, normalization, UUID conversion, and
format-2 persistence. The test-only adapter in `test/watershed/tree/id_fixture.gleam`
receives only fixture input and compares the complete output. The extended
upstream case adds creation-range and serialization comparisons, both cluster
growth paths, pending-state restoration, UUID carry across reserved bits, and
large numeric offsets.

**Files:** Create `src/watershed/fluid_ids.gleam` and
`test/watershed/shared_tree_ids_test.gleam`; add the test-only fixture adapter.

**Interfaces:** Opaque `SessionId`, `StableId`, `SessionSpaceId`, `OpId`, and
`Compressor`; concrete `CreationRange` and typed `IdError`. Session ID parsing
validates UUID syntax/version. Session-space IDs and op-space IDs have different
types even when both encode as integers.

```gleam
pub fn session_id(raw: String) -> Result(SessionId, IdError)
pub fn new(session: SessionId) -> Compressor
pub fn generate(
  state: Compressor,
) -> Result(#(Compressor, SessionSpaceId), IdError)
pub fn take_creation_range(
  state: Compressor,
) -> #(Compressor, Option(CreationRange))
pub fn finalize(
  state: Compressor,
  range: CreationRange,
) -> Result(Compressor, IdError)
pub fn to_op(state: Compressor, id: SessionSpaceId) -> Result(OpId, IdError)
pub fn from_op(
  state: Compressor,
  id: OpId,
  origin: SessionId,
) -> Result(SessionSpaceId, IdError)
pub fn decompress(state: Compressor, id: SessionSpaceId) -> Result(StableId, IdError)
pub fn serialize(state: Compressor, include_local: Bool) -> Result(Json, IdError)
pub fn deserialize(data: Json, session: SessionId) -> Result(Compressor, IdError)
```

`serialize` returns a JSON string containing the upstream base64 bytes, not a
JSON compressor object. `deserialize` requires the saved session for local-state
restoration and a new session for a summary. `recompress`, typed numeric
constructors/accessors, creation-range JSON codecs, and `take_unfinalized_range`
complete the ID conversion and reconnect surfaces. `with_cluster_size` selects
the next range's reservation; restoration resets this transient setting to 512,
as upstream does.

- [x] **1. Add a same-session identity preservation test.**

```gleam
pub fn shared_tree_id_finalization_preserves_identity_test() {
  let assert Ok(session) =
    fluid_ids.session_id("11111111-1111-4111-8111-111111111111")
  let assert Ok(#(state, local)) =
    fluid_ids.new(session) |> fluid_ids.generate
  let assert Ok(before) = fluid_ids.decompress(state, local)
  let assert #(state, Some(range)) = fluid_ids.take_creation_range(state)
  let assert Ok(state) = fluid_ids.finalize(state, range)
  let assert Ok(after) = fluid_ids.decompress(state, local)
  after |> expect.to_equal(before)
}
```

- [x] **2. Implement the allocator from the pinned compressor contract.**

Represent clusters, session allocation ranges, local allocations, and finalized
ranges. Implement the exact range-finalization order and cluster extension rules.
Do not replace this with UUID hashing or a local monotonic integer.

Perform UUID arithmetic using a representation that preserves the full UUID
payload on both targets, such as bytes or bounded integer limbs. Respect UUID
version/variant bits. JS numbers cannot represent a 128-bit integer or arbitrary
BEAM-sized integers; reject wire IDs outside the supported safe integer domain.
Return an allocation error before exhausting that domain, without changing the
compressor state.

- [x] **3. Add the `id-ranges` fixture adapter and negative cases.**

Fold fixture actions through `generate`, `take_creation_range`, `finalize`,
normalization, and persistence. Compare stable UUIDs and both numeric spaces
with upstream. Cover interleaved sessions, duplicate/out-of-order ranges,
cluster boundaries, eager final IDs, summaries without local pending state, and
local restore with pending state.

- [x] **4. Run the focused pair and commit.**

The focused pair passes 33 tests on each target. Corpus guard tests pass, and
`rtk just shared-tree-oracle-check` reproduces all 20 upstream cases. Review
found a missing UUID-exhaustion check for restored pending IDs; a failing
regression test and the fix now cover it on both targets.

Commit subject: `feat(tree): implement Fluid ID compression`.

### Task 5: implement tree values and fixed-schema validation

Implementation: pure Gleam schema-v2 decoding, default fixed-view compatibility,
and recursive root/field validation run on JavaScript and BEAM. Raw-string
entry points detect duplicate declarations before JSON parsing loses them;
the `Json` entry points remain convenience APIs. `validate_root_field` adds
explicit root-absence validation. The schema-only `schema-validation` case
contains 31 upstream checks and leaves the original summary-backed
`schema-profile` case unchanged. Task 6 has not started.

**Files:** Create `tree/types.gleam`, `tree/schema.gleam`, and
`test/watershed/shared_tree_schema_test.gleam`. Extend the oracle source,
generator guards, required-case loader, and README; generate the additional
case and updated manifest.

**Interfaces:**

```gleam
// tree/types.gleam
pub type FieldPath = List(String)
pub type TreeValue {
  StringValue(String)
  NumberValue(Float)
  BooleanValue(Bool)
  NullValue
  ObjectValue(schema_id: String, fields: List(#(String, TreeValue)))
}
pub type Edit {
  SetField(path: FieldPath, value: TreeValue)
  ClearField(path: FieldPath)
}
pub type TreeError {
  InvalidSchema(detail: String)
  InvalidEdit(path: FieldPath, detail: String)
  UnsupportedFormat(family: String, version: String)
  CorruptData(location: String, detail: String)
  InvalidHistory(detail: String)
}
pub type SequencePoint {
  SequencePoint(sequence_number: Int, index_in_batch: Int)
}
```

In `schema.gleam`, define opaque `StoredSchema` and `ViewSchema`, concrete
`FieldSchema(cardinality, allowed_types)`, `Required`/`Optional` cardinality, and
object/leaf node definitions. Export:

```gleam
pub fn stored_from_json(data: Json) -> Result(StoredSchema, TreeError)
pub fn view_from_json(data: Json) -> Result(ViewSchema, TreeError)
pub fn stored_from_string(raw: String) -> Result(StoredSchema, TreeError)
pub fn view_from_string(raw: String) -> Result(ViewSchema, TreeError)
pub fn can_view(stored: StoredSchema, view: ViewSchema) -> Result(Nil, TreeError)
pub fn validate_root(schema: StoredSchema, value: TreeValue) -> Result(Nil, TreeError)
pub fn validate_root_field(
  schema: StoredSchema,
  value: Option(TreeValue),
) -> Result(Nil, TreeError)
pub fn validate_field(
  schema: StoredSchema,
  parent_type: String,
  field: String,
  value: Option(TreeValue),
) -> Result(Nil, TreeError)
```

- [x] **1. Add fixture-driven schema refusal and acceptance tests.**

```gleam
pub fn shared_tree_schema_oracle_test() -> Nil {
  fixtures.assert_case("schema-validation", run_schema_case)
}
```

Implement `run_schema_case: fn(Json) -> Result(Json, String)` in this test module:
decode the fixture's stored/view schemas and candidate values, call the
validators, and encode the complete ordered acceptance observations. Decode
failures and unexpected errors fail the runner instead of becoming expected
refusals. Native negative tests assert typed errors and paths.

- [x] **2. Implement the subset without conflating absent and null.**

Validate duplicate schema identifiers and object field names, required fields,
unknown fields, allowed node types, root cardinality, and finite numbers.
Refuse array/map/handle/identifier-field schema capabilities not in the profile.
Recognize exact upstream leaf identifiers rather than inventing serialized names.
Distinguish an unsupported valid schema from corrupt schema bytes.

- [x] **3. Add negative tests before local mutation exists.**

Required clear, null into a string field, missing required child fields,
wrong nested object type, non-finite numbers, and unsupported view versions must
return errors. A supported fixed view over matching stored schema must succeed.

- [x] **4. Run the focused pair and commit.**

The focused suite passes 57 tests on Erlang and 58 on JavaScript, including
the schema-only oracle replay. Eight generator guard tests pass, and
`rtk just shared-tree-oracle-check` reproduces all 21 cases. The original
20 case files remain unchanged. Correctness review found no blocking issues.

Commit subject: `feat(tree): validate native object-tree schemas`.

### Task 6: implement the persistent forest and detached content

**Files:** Create `tree/forest.gleam` and
`test/watershed/shared_tree_forest_test.gleam`. Extend shared types with revision
and atom identities, using `fluid_ids.StableId` for resolved revision identity.

**Interfaces:**

```gleam
// tree/types.gleam
pub type AtomId {
  AtomId(revision: Option(StableId), local_id: Int)
}
```

An `AtomId` identifies changeset content in its revision context; it is not a
JSON path or a substitute for all local forest references.

In `forest.gleam`, define opaque `Forest`, `NodeRef`, `DetachedIndex`, and `Delta`.
A `NodeRef` belongs to one forest/view instance; a reference from another view
must be rejected. Export:

```gleam
pub fn new(schema: StoredSchema, root: TreeValue) -> Result(Forest, TreeError)
pub fn read(state: Forest, path: FieldPath) -> Result(Option(TreeValue), TreeError)
pub fn locate(state: Forest, path: FieldPath) -> Result(NodeRef, TreeError)
pub fn read_node(state: Forest, node: NodeRef) -> Result(TreeValue, TreeError)
pub fn apply_delta(state: Forest, delta: Delta) -> Result(Forest, TreeError)
pub fn visible_root(state: Forest) -> Result(TreeValue, TreeError)
```

Define `Delta` with typed build, attach, detach, nested-field-change, rename/
alias, and destroy instructions required by the corpus. Keep delta construction
inside native tree modules; the application facade must not accept arbitrary
deltas. Add typed forest export/import data for Task 10, including detached roots.

- [ ] **1. Add the detached-content regression.**

Use the generated `detached-child-edit` case to create a forest, retain a local
reference to the original `point`, replace that field, and apply the old child's
edit. The new visible point stays unchanged; reading the retained original
reference reflects the edit. Export/import must preserve the relevant retained
content, while old process-local `NodeRef` values need not survive reload.

- [ ] **2. Implement atomic delta application.**

Construct candidate persistent state, validate references and cardinality, then
return it. An error returns no partial state. Keep per-field order where the
protocol requires it. Support building detached content before attachment.
Apply logically simultaneous register moves against the same input state.

- [ ] **3. Add primitive, nested, and malformed-delta checks.**

Check every primitive, absent optional fields, repeated reads, replacement
identity, duplicate attach, missing source/destination, cyclic ownership, and
invalid references. No optimization may discard a removed node still referenced
by history.

- [ ] **4. Run the focused pair and commit.**

Commit subject: `feat(tree): retain attached and detached forest state`.

### Task 7: port required/optional field edit algebra

**Files:** Create `tree/optional_field.gleam` and
`test/watershed/shared_tree_field_test.gleam`.

**Interfaces:** Match the upstream register model:

```gleam
pub type RegisterId {
  Active
  Detached(AtomId)
}
pub type Replacement {
  Replacement(
    was_empty: Bool,
    source: Option(RegisterId),
    detach_id: AtomId,
  )
}
pub type FieldChange {
  FieldChange(
    moves: List(#(AtomId, AtomId)),
    child_changes: List(#(RegisterId, AtomId)),
    replacement: Option(Replacement),
  )
}
```

Export `set`, `clear`, `compose`, `invert`, `rebase`, and `replace_revisions`.
Use typed context parameters for revision metadata, child-change callbacks, and
ID allocation wherever the corresponding upstream handler requires them. M0
must record those dependencies; do not drop them to make an interface shorter.
The initial editor contracts are:

```gleam
pub fn set(was_empty: Bool, fill: AtomId, detach: AtomId) -> FieldChange
pub fn clear(was_empty: Bool, detach: AtomId) -> FieldChange
```

The algebra contracts consume and return `Result(FieldChange, TreeError)`;
composition consumes an ordered list of revision-tagged changes, inversion
consumes the original tagged change and repair context, and rebasing consumes
the authored change, the tagged base change, and revision context.

- [ ] **1. Add the upstream algebra corpus as a failing test.**

```gleam
pub fn shared_tree_field_algebra_matches_upstream_test() {
  fixtures.assert_case("field-compose-invert-rebase", run_field_case)
}
```

`run_field_case` decodes typed register changes and invokes the named algebra
function from each fixture action. It compares canonical register maps and
revision-aware results, not only the current field value.

- [ ] **2. Port the field handlers in dependency order.**

Start with editor output and revision replacement; add composition, inversion,
then rebasing from the pinned `optionalField.ts` implementation. Required fields
reuse optional-field algebra and reject empty results through their schema
contract, as upstream `requiredField.ts` does.

Preserve the distinction between `Active`, no source, and a detached source.
For the selected V2 encoding, active register encodes as null while an omitted
replacement source means clear; these cannot share one decoder branch.

- [ ] **3. Cover the full supported register behavior.**

Include set/set both orders; set/clear; clear/set; clear of empty; nested child
edits through replacement; detach/reattach during rebase; simultaneous register
swaps; duplicate source/destination rejection; and revision remapping.
Detached-register moves are required even though public array moves are deferred.

- [ ] **4. Exercise the algebra laws with upstream expectations.**

Compare composing A then B with applying A then B in the same context. Compare
applying A then its valid inverse with restored observable/retained state.
Run the upstream rebase axioms that apply to the supported changes, including
their documented preconditions. Do not impose a generic commutative CRDT law.

- [ ] **5. Run the focused pair and commit.**

Commit subject: `feat(tree): port optional-field change algebra`.

### Task 8: compose and rebase nested modular changes

**Files:** Create `tree/change.gleam` and
`test/watershed/shared_tree_change_test.gleam`.

**Interfaces:** Define opaque `Changeset`, concrete `TaggedChange`, `RevisionInfo`,
`RepairContext`, and `RebaseContext`. These contexts contain the upstream
revision/repair information the supported modular algorithm requires; they are
not empty marker types. Export:

```gleam
pub fn edit(
  schema: StoredSchema,
  forest: Forest,
  revision: StableId,
  operation: Edit,
) -> Result(Changeset, TreeError)
pub fn compose(
  changes: List(TaggedChange),
  context: RebaseContext,
) -> Result(Changeset, TreeError)
pub fn invert(
  change: TaggedChange,
  repair: RepairContext,
) -> Result(Changeset, TreeError)
pub fn rebase(
  change: Changeset,
  over: TaggedChange,
  context: RebaseContext,
) -> Result(Changeset, TreeError)
pub fn into_delta(change: TaggedChange) -> Result(Delta, TreeError)
```

The state must represent max local ID, ordered revision metadata, field changes,
node changes, node-to-parent mapping, node aliases, and builds/destroys/refreshers
reachable in the profile. Include generic field changes used by nested edits.
For constraint or cross-field structures outside the profile, prove absence in
M0 and reject their presence; do not parse and discard them.

- [ ] **1. Add the parent/child conflict and modular algebra tests.**

```gleam
pub fn shared_tree_nested_change_algebra_matches_upstream_test() {
  fixtures.assert_case("modular-nested-algebra", run_change_case)
}
```

The adapter encodes resulting changesets, deltas, and applied forest observations.
Compare identity aliases as well as visible values.

- [ ] **2. Implement local editing and delta production.**

Resolve the target in the current forest, validate against stored schema, create
build/detach identities, and construct the actual required/optional change.
Nested edits reference the original target node even if a peer replaces its
parent before sequencing.

- [ ] **3. Port modular composition/inversion/rebase.**

Follow the pinned modular family and field-handler callbacks. Preserve aliases
when two changes identify the same node with different atom IDs. Keep revision
replacement and repair content consistent across compose, invert, rebase, and
prune. Map Gleam field kinds through a closed sum; do not create a plugin registry.

- [ ] **4. Run all nested-object corpus schedules.**

Execute `nested-independent`, `parent-child-both-orders`, and
`detached-child-edit`, including repeated replace/edit/rebase cycles.
Add negative tests for alias cycles, missing builds, invalid parent references,
and reused local IDs with incompatible meaning.

- [ ] **5. Run the focused pair and commit.**

Commit subject: `feat(tree): rebase nested object changes`.

### Task 9: implement edit history and pending-commit reconciliation

**Files:** Create `tree/history.gleam` and
`test/watershed/shared_tree_history_test.gleam`.

**Interfaces:** Define `Commit(revision, originator, change)`, opaque `History`,
`HistorySnapshot`, and `HistoryUpdate(history, delta)`. Export:

```gleam
pub fn new() -> History
pub fn append_local(
  state: History,
  commit: Commit,
) -> Result(HistoryUpdate, TreeError)
pub fn receive(
  state: History,
  commit: Commit,
  point: SequencePoint,
  reference_sequence_number: Int,
  minimum_sequence_number: Int,
) -> Result(HistoryUpdate, TreeError)
pub fn pending(state: History) -> List(Commit)
pub fn snapshot(state: History) -> Result(HistorySnapshot, TreeError)
pub fn restore(snapshot: HistorySnapshot) -> Result(History, TreeError)
```

Add a resubmission function that returns the pending commits and retained revision
identities after reconciling a replayed server tail. Its exact wire metadata is
provided by Task 11; tree revisions must not change merely because client
sequence numbers change after reconnect.

- [ ] **1. Test multiple pending commits and peer history.**

```gleam
pub fn shared_tree_history_pending_matches_upstream_test() {
  fixtures.assert_case("multiple-pending", run_history_case)
}

pub fn shared_tree_history_window_matches_upstream_test() {
  fixtures.assert_case("history-window", run_history_case)
}
```

- [ ] **2. Implement the trunk, local branch, and necessary peer branches.**

Port the relevant edit-manager behavior: interpret a remote change in its author
context, rebase it onto the trunk, reconcile local pending changes, and report
one final forest delta. Match self acknowledgements by revision and supported
runtime metadata. Never identify a tree commit only by an integer hash of the
transport client ID.

- [ ] **3. Preserve the collaboration window.**

Retain the revisions and detached repair state needed by outstanding local and
peer changes. Use minimum sequence numbers and the pinned history rules when
advancing the base. A safe first implementation may retain more history, but it
must still write an upstream-valid summary and honor reference contexts.
Record a memory ceiling before relying on indefinite retention; do not silently
discard history when the ceiling is reached.

- [ ] **4. Test resubmission and atomic reconciliation.**

Replay a server-accepted commit after a lost acknowledgement and verify it is
not applied or emitted a second time. Replay a never-submitted commit and verify
exactly one subsequent submission. Test two inner commits sharing an outer
sequence number. Do not expose temporary rollback/rebase states to observers.

- [ ] **5. Run the focused pair and commit.**

Commit subject: `feat(tree): reconcile sequenced and pending history`.

### Task 10: implement tree codecs and the pure kernel

**Files:** Create `tree/codec.gleam`, `tree_kernel.gleam`,
`test/watershed/shared_tree_codec_test.gleam`, and
`test/watershed/shared_tree_kernel_test.gleam`.

**Interfaces:** Codecs consume the profile's explicit version selection and
document compressor. `DecodeContext` supplies originator/revision/session
context; `EncodeContext` supplies schema and whether output is a message or
summary. Do not decode compressed revision IDs without that context.

```gleam
// tree_kernel.gleam
pub opaque type TreeState
pub opaque type TreeSnapshot
pub type TreeEvent {
  TreeChanged(local: Bool)
}
pub fn restore(
  snapshot: TreeSnapshot,
  view: ViewSchema,
) -> Result(TreeState, TreeError)
pub fn read(state: TreeState, path: FieldPath) -> Result(Option(TreeValue), TreeError)
pub fn validate_edit(state: TreeState, edit: Edit) -> Result(Nil, TreeError)
pub fn apply_local(
  state: TreeState,
  revision: StableId,
  originator: SessionId,
  edit: Edit,
) -> Result(#(TreeState, Commit, List(TreeEvent)), TreeError)
pub fn receive(
  state: TreeState,
  commit: Commit,
  point: SequencePoint,
  reference_sequence_number: Int,
  minimum_sequence_number: Int,
) -> Result(#(TreeState, List(TreeEvent)), TreeError)
pub fn snapshot(state: TreeState) -> Result(TreeSnapshot, TreeError)
```

The opaque snapshot consists of stored schema, sequenced forest, detached index,
and history. The document-level compressor remains outside it.

- [ ] **1. Add raw upstream decode and native encode consumption tests.**

```gleam
pub fn shared_tree_kernel_matches_upstream_test() {
  fixtures.assert_case("same-field-both-orders", run_kernel_case)
}
```

The codec suite reads raw upstream operations and summaries, not the corpus's
normalized edit actions. Export native-encoded operations to the oracle for
actual upstream decoding/application. A native encode/decode round trip is an
additional check, not interoperability evidence.

- [ ] **2. Implement the profile's codec family as a closed version dispatch.**

Use the observed version dependency graph, including message versus changeset
versus optional-field versions. The inspected upstream message envelope includes
`revision`, `originatorId`, `changeset`, and a version; some versions also support
custom metadata. Preserve tolerated extra envelope properties as required, but
refuse unknown semantic versions.

Implement stored schema, tree content, detached-field index, and edit-manager
codecs. These are not a JSON rendering of visible `TreeValue`.
Use real upstream loaders as the authority for native encoding acceptance.

- [ ] **3. Implement the kernel around schema, forest, and history.**

`validate_edit` runs before runtime ID allocation. `apply_local` builds a commit,
updates pending history/visible forest, and returns its event. `receive` performs
remote or acknowledgement reconciliation. Compare the externally visible state
before/after the atomic transition; suppress acknowledgements that change
nothing. Keep retained-state changes even when no visible event occurs.

- [ ] **4. Run the object-only corpus and corruption cases.**

The public event contract is whole-tree invalidation, normalized from upstream
batch-level observations. Do not claim parity with upstream's complete
node-specific event API. Check error-state invariants and absence of emitted
messages/events after invalid local input.

- [ ] **5. Run the focused pair and commit.**

Commit subject: `feat(tree): add native SharedTree kernel and codecs`.

### Task 11: implement Fluid container routing and runtime messages

**Files:** Create `wire/fluid_container.gleam` and
`test/watershed/shared_tree_container_test.gleam`. Modify `wire/op.gleam`,
`wire.gleam`, `handle.gleam`, relevant socket codecs, and their tests.

**Interfaces:** Use a concrete `Route(data_store_id, channel_id)` and a typed
closed sum for supported container messages. Keep opaque DDS payload JSON only
until the registry identifies the channel codec.

```gleam
pub type RoutedOperation {
  RoutedOperation(
    route: Route,
    contents: Json,
    index_in_batch: Int,
  )
}
pub fn decode(
  contents: Json,
  metadata: Option(Json),
) -> Result(List(ContainerMessage), ContainerError)
pub fn encode(message: ContainerMessage) -> Result(Json, ContainerError)
```

`ContainerMessage` includes routed operations, ID allocation, datastore/channel
attach and alias operations required by the profile, and any required runtime
metadata messages found at M0. `ContainerError` names unsupported message kinds,
invalid routing, malformed batches, and unsupported compression.

- [ ] **1. Add raw envelope cases before replacing current encoding.**

Test the captured upstream envelope hierarchy, attach attributes, aliases,
batched operations, and allocation-before-dependent-commit ordering.
Include two datastores with the same channel ID to prevent accidental flat-key
collision even if the first service profile uses only one datastore.
Add `bootstrap-map-handles`: load the actual upstream map and tree handle,
resolve a multi-segment handle, and reject missing or wrong-kind root channels.

- [ ] **2. Replace the direct document channel wrapper.**

Implement the profile's real `component`/datastore/channel routing. Do not treat
the existing `{address, contents}` wrapper as the entire Fluid container op.
Preserve actual outer metadata and per-inner-message positions.

Replace `handle.gleam`'s single-segment URL restriction with validated Fluid
handle paths and context-aware resolution. Retain the existing facade convention
of representing serialized handles as `Json`. Test escaping, relative versus
absolute paths emitted by the profile, same channel names in different stores,
and refusal of paths outside the document. Do not flatten a handle to its last
segment.

- [ ] **3. Separate sequencing from channel dispatch.**

One outer server message advances the global sequence watermark once, even when
it contains multiple inner messages. Validate the complete supported batch
before committing mutations. Include system operations that do not target a
DDS in acknowledgement, minimum-sequence, and retry accounting.

- [ ] **4. Update existing DDS encoders and fixtures.**

Replace old envelope fixtures rather than adding a legacy decoder. Keep each
existing DDS payload/merge rule unchanged unless its new enclosing Fluid
attributes require an explicit adjustment. Assign Watershed-specific type
identifiers to structures that do not implement an upstream DDS.
The bootstrap SharedMap is a required upstream DDS in this profile: prove its
handle value and summary encoding with upstream, rather than assuming the
existing SharedMap behavioral corpus establishes wire compatibility.

- [ ] **5. Run focused and existing wire suites on both targets; commit.**

Commit subject: `feat(runtime): route Fluid container messages`.

### Task 12: integrate tree channels into both runtimes

**Files:** Modify `channel.gleam`, `runtime_core.gleam`, `runtime.gleam`,
`runtime_beam.gleam`, `crdt_core.gleam`, and sluice codecs/core as needed.
Create `test/watershed/shared_tree_runtime_test.gleam`.

**Interfaces:** Add `TreeChannel`, `InitTree`, tree state/operation/event/snapshot
variants, and tree local metadata to the existing channel sums. Extend
`SequencedMeta` with an inner-message position and non-lossy author identity
where needed; preserve the existing integer identity fields for unrelated
consensus DDSes.

The document core owns the compressor, route registry, necessary runtime
metadata, and pending system messages. Tree snapshots do not duplicate the
document compressor.

Replace `seed_channels`' unconditional missing-root-map insertion when loading
an existing container. The loader must locate the profile's real bootstrap map
and retain its route in document state. Both facade `root` functions resolve
that route instead of constructing an unverified address `"root"`. A missing or
wrong-kind required root fails bootstrap before readiness. Keep new native
map-document initialization distinct from loading an existing container, so
ordinary existing DDS creation behavior does not disappear.

- [ ] **1. Add a runtime test covering allocation and tree submission.**

```gleam
pub fn shared_tree_runtime_allocates_before_submitting_commit_test() {
  fixtures.assert_case("batched-commits", run_runtime_case)
}
```

The adapter drives the actual runtime core and serializes its outbound messages,
then compares message ordering, IDs, observed events, and final tree state.

- [ ] **2. Wire local edit validation and allocation as one transition.**

Validate the edit first, generate its revision ID in a candidate compressor,
build the tree commit, enqueue any required allocation message before dependent
content, and publish the new core state only on success. Invalid edits leave the
compressor, pending queues, forest, events, and CSN allocation unchanged.

- [ ] **3. Wire remote delivery and acknowledgements.**

Finalize allocation messages before decoding dependent compressed IDs. Route
each inner operation to the right tree with its originator session and complete
sequence/reference/minimum metadata. Track outer transport submission identities
separately from tree revisions and ID compressor sessions.

- [ ] **4. Update cross-cutting dispatch and test transport behavior.**

Follow every compiler error from the new closed-sum variants. Check
`supports_p2p`, P2P snapshots, digests, replay, rollback, attach, and snapshot
serialization explicitly. Return the existing unsupported-P2P error for tree
channels. Do not add a tree merge implementation to `crdt_core`.

Teach sluice the observed outer/inner batching and metadata rules needed by the
tests; it must not pretend a grouped message is several distinct server sequence
numbers. Keep the real-service gate independent of sluice.

- [ ] **5. Run both runtime suites and the existing bootstrap smoke; commit.**

```sh
rtk proxy gleam test --target erlang
rtk proxy gleam test --target javascript
rtk proxy node smoke/runtime_bootstrap.mjs
```

If an unrelated baseline fails, reproduce it on the implementation branch's
unchanged baseline and record that evidence. Do not assume an old remembered
failure still applies. Commit subject:
`feat(runtime): host native SharedTree on both targets`.

### Task 13: read and publish compatible summaries

**Files:** Create `wire/fluid_summary.gleam` and
`test/watershed/shared_tree_summary_test.gleam`. Modify `git_storage.gleam`,
`wire/summary_blob.gleam`, runtime bootstrap/summary paths, and existing storage
tests/bootstrap harness.

**Interfaces:**

```gleam
pub type SummaryEntry {
  SummaryTree(entries: List(#(String, SummaryEntry)))
  SummaryBlob(bytes: BitArray)
  SummaryHandle(path: String, kind: HandleKind)
}
pub type HandleKind {
  TreeHandle
  BlobHandle
}
pub opaque type DocumentSummary
pub fn decode(
  tree: SummaryEntry,
  resolved: Dict(String, SummaryEntry),
) -> Result(DocumentSummary, SummaryError)
pub fn encode(summary: DocumentSummary) -> Result(SummaryEntry, SummaryError)
```

`DocumentSummary` includes the consistent sequence point, protocol/container/
datastore metadata, channel snapshots, compressor state, and the membership
information needed by existing DDSes. `SummaryError` distinguishes missing,
cyclic, wrong-kind, malformed, and unsupported entries.

- [ ] **1. Fail on an actual upstream summary with the current loader.**

Use `summary-tail` and verify that the current single-`header` loader cannot
satisfy the required tree. The replacement test then requires full decoding,
restoration, and subsequent tail application.

- [ ] **2. Replace the Watershed-only summary layout.**

Implement the recorded hierarchy and metadata, including SharedTree's
`indexes` subtree and relevant version metadata. Resolve handles by their
actual summary/storage meaning; do not assume every handle is a Git object SHA.
Keep binary blob content lossless.

Extend storage reads/writes to trees and blobs while reusing existing
authentication, HTTP status/error reporting, commit lookup, and delta fetching.
Remove obsolete version-4-only storage code after its callers move. Do not write
a version-4 migration reader.

- [ ] **3. Publish one consistent sequenced document state.**

Take compressor, tree history, forest, detached content, route registry, and
protocol metadata at the same sequence point. Exclude pending local edits.
Regenerate changing metadata; copy only data proven immutable under the profile.
Honor the difference between snapshot sequence S and publication sequence P.

Write a full valid summary first. Reading upstream incremental handles remains
required if the profile can produce them.

- [ ] **4. Test both directions with upstream loaders.**

For each native target, publish a summary after replacement and detached edits.
Load it with an upstream client, read the tree, make another edit, and have the
native client observe it. Load an upstream summary with each native target and
continue editing. Include a tail between snapshot and publication.

- [ ] **5. Test failure atomicity and existing DDS persistence; commit.**

Missing blob, invalid base64, cyclic handle, wrong schema, bad compressor data,
and unsupported codec must not expose a ready document. Run the existing
summary/storage/runtime tests after updating their format fixtures.
Commit subject: `feat(tree): persist interoperable Fluid summaries`.

### Task 14: expose both facades and complete reconnect

**Files:** Modify `src/watershed.gleam`, `src/watershed_beam.gleam`,
`src/watershed/schema.gleam`, both runtimes, and
`test/watershed/facade_parity_test.gleam`. Add
`test/watershed/shared_tree_facade_test.gleam` and
`test/watershed/shared_tree_client.gleam`.

**Interfaces:** Both facades expose opaque `SharedTree` and these operations,
using each facade's existing `Document` type:

```gleam
pub fn resolve_tree(
  document: Document(root),
  value: Json,
  view: ViewSchema,
) -> Result(SharedTree, String)
pub fn tree_get(
  tree: SharedTree,
  path: FieldPath,
) -> Result(Option(TreeValue), String)
pub fn tree_set(
  tree: SharedTree,
  path: FieldPath,
  value: TreeValue,
) -> Result(Nil, String)
pub fn tree_clear(tree: SharedTree, path: FieldPath) -> Result(Nil, String)
pub fn tree_handle_of(tree: SharedTree) -> Json
```

Both facades already use `Document(root)` and JSON handle markers; preserve
those conventions and the root-tag invariant. JS subscription follows the
callback convention;
BEAM subscription returns the existing subject-style event stream:

```gleam
// JavaScript
pub fn subscribe_tree(tree: SharedTree, handler: fn(TreeEvent) -> Nil) -> Nil
// BEAM
pub fn subscribe_tree(tree: SharedTree) -> Subject(TreeEvent)
```

Add the tree phantom channel kind and typed-field setter/resolver. The resolver
requires `ViewSchema` because a channel handle alone does not prove that an
application can view its stored schema.

```gleam
pub fn set_tree_field(
  map: TypedMap(s),
  field: ChannelField(s, schema.TreeChannel),
  tree: SharedTree,
) -> Nil
pub fn resolve_tree_field(
  document: Document(root),
  map: TypedMap(s),
  field: ChannelField(s, schema.TreeChannel),
  view: ViewSchema,
) -> Result(Option(SharedTree), String)
```

After readiness, read the `"tree"` handle from the real bootstrap root map and
resolve it with the declared view. Do not hard-code a generated channel ID or
add a fake map to make this call sequence work.

The first milestone resolves the upstream-created tree. Do not add fake
`create_tree` or `ensure_tree` functions that appear to support the deferred
native-creation lifecycle. Add a parity-test entry that states this supported
lifecycle subset on both targets without weakening checks for existing kinds.

- [ ] **1. Add facade reads/edits and schema refusal tests.**

Resolve the correct tree and reject a mismatched channel kind or incompatible
view. Exercise set/clear/nested replacement and subscriptions on both facades.
Check that `tree_clear` on a required field returns an error and changes nothing.

- [ ] **2. Implement reconnect with stable compressor and commit identity.**

Preserve the compressor session and pending tree history across transport
reconnect. Bootstrap the summary/tail, reconcile already-sequenced revisions,
then resubmit only what remains with valid current transport metadata.
Do not reset IDs when the transport client ID changes.

Exercise both server-accepted/lost-ack and never-submitted cases. Report unrecoverable
reference-history or session-state loss explicitly; do not discard edits and
present a synchronized document.

- [ ] **3. Add the dual-target acceptance runner.**

Use one logical JSON-lines command protocol for both compiled targets:

```json
{"requestId":1,"command":"read","path":["title"]}
{"requestId":2,"command":"set","path":["title"],"value":{"kind":"string","value":"native"}}
{"requestId":3,"command":"clear","path":["note"]}
{"requestId":4,"command":"summarize"}
{"requestId":5,"command":"disconnect"}
{"requestId":6,"command":"reconnect"}
```

Connection configuration comes from the environment and a run-specific document
descriptor written by the coordinator. Responses include `requestId`,
`ok`/typed error details, the represented sequence point, and observations.
Keep diagnostic logs off stdout. Implement `await-synced`/checkpoint commands
through actual pending/runtime state, not fixed sleeps.

Use test-only FFI for Node/Erlang process I/O if necessary. Tree operations must
go through the production facades on both targets.

- [ ] **4. Run facade parity and reconnect scenarios; commit.**

Commit subject: `feat(tree): expose dual-target tree editing and reconnect`.

### Task 15: prove mixed-client and cross-writer interoperability

**Files:** Extend `tools/shared-tree-oracle/service.mjs`; create
`smoke/shared_tree.mjs`; extend the runner and integration corpus/report format.

**Interfaces:** `service.mjs interop` starts or connects to the declared real
service, creates one upstream document, launches both native clients, and returns
a machine-readable coverage report. Own processes by explicit handles/PIDs and
clean up only run-owned documents/files/processes.

- [ ] **1. Write a gate that rejects partial coverage.**

```js
const targets = ["upstream", "javascript", "erlang"];
for (const writer of targets) {
  for (const reader of targets) {
    assert.equal(report.reload[writer][reader].loaded, true);
    assert.equal(report.reload[writer][reader].continuedEditing, true);
  }
}
assert.deepEqual(report.skipped, []);
assert.equal(report.realService, true);
assert.equal(report.divergences.length, 0);
```

Each matrix entry must come from a fresh reader, not a still-connected client
that already has the state. Force the loader to consume the selected writer's
summary plus its tail; replaying full history from the document's origin does
not prove summary compatibility.

- [ ] **2. Run the scenario matrix with controlled delivery.**

Use explicit synchronization barriers and supported connection pause controls.
Keep server sequencing real; a test transport proxy may delay or disconnect
traffic but must not rewrite tree payloads or compute native state.

Exercise edits authored by each of the three implementations, not just an
upstream writer and two native readers. After each quiescent checkpoint, compare
the whole typed tree, pending state, and the domain's required retained identity
observations. Use raw operation evidence when native/upstream state diverges.

- [ ] **3. Exercise failure paths in a separate document.**

Test invalid local edits and unsupported-profile loads. Inject malformed wire
data only into run-owned test documents. Confirm explicit failure and no
ready/success observation. A failure must not hang the coordinator until an
unbounded timeout.

- [ ] **4. Add seeded schedules and reproducible failures.**

Start with the deterministic cases, then generate at least 200 schedules for
the normal gate and 5,000 for a deep run. Use fixed, recorded seeds and shrink or
persist the failing schedule. Counts are coverage settings, not performance
claims. Keep all three implementations in the comparison.

- [ ] **5. Run the required service command and commit.**

```sh
rtk proxy node smoke/shared_tree.mjs --profile test/fixtures/shared_tree/profile.json --iterations 200 --seed 42
```

Required result: all mandatory cases, both native targets, all nine summary
writer/reader cells, zero skips, and no divergences. Commit subject:
`test(tree): prove three-client SharedTree interoperability`.

### Task 16: wire permanent gates and document the supported profile

**Files:** Modify `justfile`, `README.md`, the oracle README, and module docs.
Create `.github/workflows/shared-tree.yml`. Update directly affected examples or
fixtures if the document-format change requires it; avoid unrelated website work.

**Interfaces:** Recipes:

```just
shared-tree-oracle:
    npm --prefix tools/shared-tree-oracle run generate

shared-tree-oracle-check:
    npm --prefix tools/shared-tree-oracle run check

shared-tree-test:
    gleam test --target erlang -- --test-name-filter=shared_tree
    gleam test --target javascript -- --test-name-filter=shared_tree

shared-tree-interop:
    gleam test --target erlang -- --test-name-filter=shared_tree
    gleam test --target javascript -- --test-name-filter=shared_tree
    node smoke/shared_tree.mjs --profile test/fixtures/shared_tree/profile.json --iterations 200 --seed 42
```

The client runner is a test module, so this recipe uses `gleam test` to create
its artifacts on both targets. A production-only build does not compile `test/`.

- [ ] **1. Make required jobs fail instead of skip.**

Separate fast corpus/native gates from the real-service job so normal kernel
development does not need a service. In the required service job, missing BEAM,
upstream packages, corpus, or service is a failure. Start an isolated service
with a pinned revision; do not tear down another user's development server.

Check the pinned source checkout and `npm ci` lock before oracle regeneration.
Use existing repository toolchain configuration. Keep nightly/deep fuzzing a
separate command using the same runner.

- [ ] **2. Document the exact compatibility claim.**

State the upstream release, container profile, supported object/primitive schema,
read/edit/reconnect/summarize behavior, and the deferred APIs. Explain how to
resolve an upstream-created tree and report unsupported schema/version errors.
Distinguish service support from DDS-format support and P2P CRDT support.

Remove or update the wire/storage comments that say no compatibility contract
exists. Explain that old Watershed development documents must be recreated.
Document full-summary writing and the current memory/performance limits without
claiming arbitrary-document or feature parity.

- [ ] **3. Run regression coverage for shared-runtime changes.**

```sh
rtk proxy just shared-tree-oracle-check
rtk proxy just shared-tree-test
rtk proxy just shared-tree-interop
rtk proxy just test
rtk proxy just build
rtk proxy just lint
```

The broad commands belong here because envelope, storage, channel sums, and
runtime changes affect existing DDSes, examples, and Lustre users. Diagnose new
failures; record independently reproduced baseline failures rather than
silencing them.

- [ ] **4. Audit the production dependency boundary and commit.**

Confirm that production Gleam/JS modules neither import the oracle nor delegate
tree state to Fluid npm code. Verify that both facades pass the same semantic
cases and that unsupported P2P paths return explicit errors.
Commit subject: `docs(tree): publish supported interoperability profile`.

---

## 5. M1 completion checklist

- [ ] M0 profile and service requirements remain the ones approved at the gate.
- [ ] Pure tree and compressor semantics execute on JavaScript and BEAM.
- [ ] Each mandatory corpus domain has native cases on both targets.
- [ ] Native operations are accepted by upstream, not only by native decoders.
- [ ] Real upstream/native clients can each author concurrent edits.
- [ ] Parent replacement and removed-child edits preserve upstream behavior.
- [ ] Reconnect does not duplicate, lose, or silently abandon pending edits.
- [ ] All nine summary writer/reader combinations load and continue editing.
- [ ] Summary-plus-tail replay uses the snapshot point, not publication time.
- [ ] Invalid local edits cause no state/allocation/event/output change.
- [ ] Unsupported/corrupt documents report errors without partial readiness.
- [ ] Required jobs execute with no skipped target, service, or corpus.
- [ ] Existing DDS behavior passes its regression suites after format replacement.
- [ ] Documentation names the restricted profile and deferred capabilities.
- [ ] No production dependency uses upstream TypeScript as the native tree engine.

## 6. Later plans

Use the specification's M2-M8 roadmap. Write each feature's own design and
implementation plan when scheduled, using the working M1 oracle and real-service
gate. In particular:

| Next area | Earliest prerequisite | Additional proof |
| --- | --- | --- |
| Dynamic maps | M1 | Per-key set/delete, nested values, iteration and summary parity. |
| Arrays and moves | M1 | Sequence-field algebra, cross-array movement, identity, concurrent move/delete/edit races. |
| Schema evolution | M1 | Stored/view compatibility and schema/data races across supported client profiles. |
| Transactions and undo/redo | M1 plus each supported edited field kind | Constraints, atomic abort, selective undo, redo after remote changes, retained repair data. |
| Local branching | Working modular history | Fork/rebase/merge and branch lifetime without prematurely reclaiming history. |
| Shared branches | Separate version/profile decision | Explicit support for the experimental shared-branch wire family; no accidental opt-in. |
| Native container creation | M1 container read/write contract | Bootstrap/attach/alias lifecycle and upstream loading of native-created documents. |
| Lustre and typed schema UX | Stable native facade | Deferred effects, schema safety, subscriptions, and one real collaborative example. |
| Crash-recoverable pending state | M1 reconnect | Restored compressor session, unsent changes, resubmission, and accepted-before-crash deduplication. |
| Scale and incremental summaries | Measured M1/M3 workloads | Bounded retained history, safe reclamation, operation costs, and cross-version persistence. |

Do not publish calendar estimates based on the old DDS complexity table.
Estimate after the M0 inventory and again after field algebra/history pass their
upstream corpus. Those are the first points where the remaining implementation
cost has useful evidence.
