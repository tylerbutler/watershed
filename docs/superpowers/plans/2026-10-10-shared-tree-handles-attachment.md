# SharedTree Handles and Live Attachment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `subagent-driven-development` or `executing-plans` to implement this plan
> task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> Execution started on 2026-10-10 with user authorization to work on `main`
> and make task commits. Task 1 discovery and Task 2 native handle leaves
> and Task 3 map-only datastore graphs are complete; Tasks 4-9 remain pending.
> The dated execution record below separates source proof
> from native acceptance.
> Do not restart completed M0-M6 or Lustre tasks.

**Goal:** Interoperate with pinned upstream handle-valued SharedTree leaves and
runtime-owned live attachment of maps/trees across declared datastores.

**Architecture:** Extend the existing pure tree values/codecs with typed Fluid
references. Extend `runtime_core`'s binding, detached-object, attachment and
batching behavior using executable upstream observations. Preserve the root
bootstrap contract while adding a declared secondary map/tree datastore.

**Tech Stack:** Dual-target Gleam, existing startest/fixture runners, Node tests,
pinned Fluid 3.1.0 source probes, existing client drivers and owned Floodgate
service infrastructure.

**Spec:** [Handles and live attachment design](../specs/2026-10-10-shared-tree-handles-attachment-design.md).

## Global Constraints

- Preserve pure Gleam SharedTree semantics on JavaScript and BEAM.
- Keep Fluid 3.1.0, source `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960`,
  Floodgate `0eb493fc46d1bb9baf1151a6ccdde93544e057e7`, and
  `minVersionForCollab` `2.117.0`.
- Keep Message V7, SharedTreeChange V5, ModularChange V5, Schema V2, and
  nonincremental FieldBatch V2.
- Preserve the existing root alias, bootstrap-map API, and fixed-layout native
  container creator.
- Preserve M1-M6 contracts, existing DDS APIs, runtime-local branch ownership,
  and application-owned revertibles.
- Keep the Fluid SDK development-only; add no production dependency, package
  dependency, or lockfile change.
- Implement handle values in the tree and attachment/binding in the document
  runtime; the pure tree kernel performs no I/O or channel creation.
- Support same-container SharedMap and SharedTree channel references across
  declared datastores; do not claim arbitrary Fluid application support.
- Validate a local submission before committing its candidate state or sending
  any of its messages; transport acceptance is not a rollback boundary.
- Preserve document compressor advancement and upstream allocation order;
  never finalize a creation range merely because a local edit allocated IDs.
- Match pinned upstream binding, attach-summary, transaction, and retained-GC
  observations; do not infer them from visible-value convergence.
- Required gates must execute upstream, JavaScript, BEAM, and their service
  cases with zero skips; a skipped upstream test supplies no proof.
- Apply ASD-STE100 to Gleam comments/error strings, not Markdown prose.
- Do not hand-edit generated fixtures, `.code-map/`, apm-managed files, or the
  pinned reference checkout.

## Scope decisions

| Approach | Decision |
| --- | --- |
| Handle leaves pointing only to existing channels | Insufficient for the selected live-attachment scope. |
| Same-datastore creation and attachment only | Useful as a first test cycle, but not the final acceptance boundary. Upstream supports cross-datastore graphs. |
| Runtime binding graphs with a declared secondary factory | Chosen. Provides upstream-aligned channel/datastore lifecycle without a general factory/layout framework. |

Support SharedMap and SharedTree channel handles in the same container.
Preserve existing inbound aliases; exclude new alias authoring,
datastore-entry-point leaves, blobs/pending payloads, arbitrary Fluid objects,
cross-container references, production authentication, and disk recovery.
These exclusions describe this profile, not upstream's full capabilities.

Task 1 is a required discovery gate. Its output includes exact upstream
outcomes and serialization order for binding removal, cycles, transactions,
branches, attach IDs, and retained GC. Complete that table and reconcile it
with the spec before Task 2. If a probe exposes a scope/API conflict, record
the evidence and revise the contract before implementing it. Do not replace an
unmeasured behavior with a guessed invariant or a success-shaped refusal.

## Execution and baseline

Planning baseline is clean `main` at `90d993f2`; no implementation ran while
writing this plan. Establish the actual execution base and obtain workspace
consent at execution time. Prefer a linked worktree; do not implement or commit
on `main` without explicit authorization. This planning request does not
authorize pushes, merges, hosted workflows, or publishing.

Before Task 1, read `AGENTS.md`, the spec, and the current M7 roadmap. Record the
execution base and this plan's progress ledger. Run:

```sh
node tools/shared-tree-oracle/source.mjs verify
just shared-tree-test
node --test tools/shared-tree-oracle/source.test.mjs \
  tools/shared-tree-oracle/container-foundations.test.mjs \
  tools/shared-tree-oracle/creation.test.mjs
```

Missing dependencies justify restoring the existing locked dependencies.
Do not install them in advance or modify lockfiles to work around registry
policy. Record baseline failures with their actual command/output before
changing code; they do not waive a feature's required gate.

One owner changes shared runtime/history paths at a time. Every task records a
focused RED/GREEN cycle and ends with a scoped review and a coherent commit
when commits are authorized. Review the final complete range before acceptance.

## File map

| Files | Responsibility |
| --- | --- |
| `tools/shared-tree-oracle/upstream-lifecycle.spec.ts` | New pinned-source handle/attachment/retention probes |
| `tools/shared-tree-oracle/source.mjs`, `source.test.mjs`, `generate.mjs`, `generate.test.mjs` | Injection identity, bounded probe command, generated case registration and raw-evidence validation |
| `src/watershed/handle.gleam` | Pure reference type, marker/path context, serialization |
| `src/watershed/tree/types.gleam`, `schema.gleam`, `forest.gleam`, `identifier.gleam`, `codec.gleam`, `codec/field_batch.gleam`, `codec/summary.gleam` | Handle leaf and all value/retention/codec consumers |
| `src/watershed/runtime_core.gleam`, `channel.gleam` | Binding graph, detached datastores/channels, lifecycle and candidate submissions |
| `src/watershed/tree/runtime.gleam`, `tree_kernel.gleam` | Document-context tree creation and attach snapshot/promotion |
| `src/watershed/wire/op.gleam`, `wire/fluid_container.gleam`, `wire/fluid_document.gleam`, `wire/fluid_summary.gleam`, `wire/summary.gleam` | Contextual tree/datastore attaches, summaries, routing and GC |
| `src/watershed/runtime.gleam`, `runtime_beam.gleam`, `src/watershed.gleam`, `src/watershed_beam.gleam` | Matching lifecycle APIs and ownership checks |
| `test/watershed/tree/lifecycle_fixture.gleam`, existing `fixtures.gleam`, `kernel_fixture.gleam`, `runtime_fixture.gleam` | Native executable fixture and value registration |
| `test/watershed/shared_tree_handle_test.gleam`, `shared_tree_attachment_test.gleam`, existing schema/codec/summary/runtime tests | Focused semantic, lifecycle and refusal coverage |
| `test/watershed/tree/client_protocol.gleam`, `client_js.gleam`, `client_beam.gleam`, `test/watershed/shared_tree_client_test.gleam` | Real native client-owned channels, datastores and selected tree operations |
| `tools/shared-tree-oracle/lifecycle-interop.mjs`, `lifecycle-interop.test.mjs`, existing schema/service/client/interop/summary modules | Service profile, measured scenarios, raw publication/transport validation |
| `README.md`, oracle README, root spec/roadmap, this plan | Public APIs, supported profile and dated acceptance |
| `justfile`, `.github/workflows/shared-tree.yml`, `.github/workflows/shared-tree-interop.yml` | Permanent non-skipping native and service gates |

Generated `test/fixtures/shared_tree/*` files change only through the generator.
The file map identifies ownership, not permission to refactor every listed
file. Search exhaustive `TreeValue`/`LeafKind` matches after adding the variants
and change each consumer that handles the new value.

## Dependency and interface review

| Tasks | Produced/consumed contract | Required check |
| --- | --- | --- |
| 1 -> 2-8 | Five source cases, exact binding/order/GC observations | Downstream assertions use the captured contract rather than coordinator claims. |
| 2 -> 3-8 | `handle.Reference`, `HandleValue`, tagged client value | Schema, codecs, fixtures and clients use the same type/marker and datastore context. |
| 3 -> 4-8 | Detached store state and candidate attachment preparation | Tree attachment extends the same planner; no second attach queue or identity allocator. |
| 4 -> 5-8 | Contextual tree attach snapshot and stable promotion | Transactions, undo and reconnect preserve the captured identities and history. |
| 5 -> 6,8 | Binding at tree publication boundaries | Facades and service clients do not attach by scanning their displayed values. |
| 3,4,5 -> 7 | Registered metadata, tree state and retained references | Summaries include sequenced objects and upstream-retained GC sources, not arbitrary local roots. |
| 6,7 -> 8 | Public native APIs and actual persisted bytes | Each client owns its runtime; the validator reconstructs measured storage and transport. |
| 8 -> 9 | Zero-skip service/corpus/reload evidence | Only proven support enters the generated profile and documentation. |

### Task 1: Capture the pinned handle and attachment contract

**Files:** Create `tools/shared-tree-oracle/upstream-lifecycle.spec.ts`.
Modify `source.mjs`, `source.test.mjs`, `generate.mjs`, `generate.test.mjs`,
and oracle README. The registered injector writes the reference checkout;
do not edit its tracked source.

**Interfaces:**

- Consume the existing source injection map, `reference`, deterministic
  environment, pinned test providers, `FluidSerializer`, and real runtime
  factory helpers.
- Produce cases `handle-leaves`, `live-channel-attachment`,
  `cross-datastore-attachment`, `handle-transaction-branch`,
  `handle-retention`, each with native input, measured observations and raw
  upstream data.
- Register injected path
  `packages/dds/tree/src/test/watershedLifecycle.spec.ts`.
- Add `runLifecycleSource(output)` and CLI command
  `node source.mjs lifecycle-capture <output-directory>`. It uses the existing
  compile/test runner and invokes only `lib/test/watershedLifecycle.spec.js`
  with `--fail-zero`, deterministic IDs and the existing version pins.
- Add `requiredLifecycleCases` and `validateLifecycleCase` in `generate.mjs`.
  Complete fixture generation remains `just shared-tree-oracle`.
- Each case has `input.scenarios` and `expected.observations` arrays with
  matching unique scenario IDs. Its raw section includes `messages`,
  `serialization`, `summaries`, and the source identity/digest. Bind each
  observation to its measured message or storage record. Cases with no
  submission at a checkpoint record an empty message slice and an explicit
  measured checkpoint, not a fabricated attach.
- Give `cross-datastore-attachment` map-only scenarios
  `map-cross-datastore` and `map-cycle`, and tree scenarios
  `tree-cross-datastore` and `tree-cycle`. This lets Task 3 compare complete
  map scenarios without claiming Task 4's tree behavior.

- [x] Add Node regressions for missing injection, incorrect source digest,
  absent raw serialization/attach/summary evidence, and omitted observations.
  Require validation of a measured positive source capture as well as mutations:

  ```js
  import assert from "node:assert/strict";
  import { readFile } from "node:fs/promises";
  import { test } from "node:test";
  import { validateLifecycleCase } from "./generate.mjs";

  test("live attachment requires the raw attach that its observation names", async () => {
    const value = JSON.parse(await readFile(
      new URL("../../test/fixtures/shared_tree/cases/live-channel-attachment.json", import.meta.url),
      "utf8",
    ));
    validateLifecycleCase(value);
    const changed = structuredClone(value);
    changed.raw.messages = [];
    assert.throws(() => validateLifecycleCase(changed), /raw.*attach/i);
  });
  ```

  Land this test after the first genuine capture exists; the initial RED is the
  missing validator, not an unrelated file-not-found error. Add source registry
  REDs first so the probe can generate that positive capture.

- [x] Register the injector and write source probes with the existing
  `SchemaFactory`, map/tree factory registry and raw-message capture helpers.
  Use this schema in the source probe and export the equivalent service schema
  in Task 8:

  ```ts
  const sf = new SchemaFactory("org.watershed.shared-tree.handles");
  class Links extends sf.map("Links", sf.handle) {}
  class Sequence extends sf.array("Sequence", sf.handle) {}
  class Root extends sf.object("Root", {
    label: sf.string,
    link: sf.optional(sf.handle),
    links: Links,
    sequence: Sequence,
  }) {}
  ```

- [x] Probe required/optional root leaves; object/map/array handle edits;
  different handle instances for the same object; relative and escaped paths;
  uncompressed and schema-aware V2 encoding; malformed/unsupported markers.
  Record both serialized paths and resolved target identities.
- [x] Probe detached map/tree edits, serialize-then-remove bindings,
  nested dependencies, self-references, two-channel cycles, and completed
  transactions before tree attachment. Capture raw attach summaries, ID ranges,
  local visibility, submitted messages and a receiving client's loaded values.
- [x] Create the declared secondary graph datastore with the existing upstream
  runtime factory mechanism. Probe a reference to its map and to its tree;
  attach a second channel after datastore visibility; probe mutual references
  across two datastores. Record package/component metadata and the actual
  datastore/channel attach order, including entry-point membership.
- [x] Probe successful/aborted/nested handle transactions; attempting to attach
  an actively transacting target tree; branch-only references before/after
  merge, dropped changes, branch disposal; handle undo while a peer edits the
  referenced target. Record actual binding timing and all data/lifecycle
  side effects. Do not assert that abort detaches a target unless measured.
- [x] Capture summary/GC before and after removal, undo, retained repair data,
  branch disposal and revertible disposal. Include an attached, then
  unreferenced secondary datastore. Load summaries through fresh upstream
  clients and record resolution/continuation.
- [x] Run the bounded source capture, then its validators:

  ```sh
  node tools/shared-tree-oracle/source.mjs lifecycle-capture \
    tools/shared-tree-oracle/.output/lifecycle
  node --test tools/shared-tree-oracle/source.test.mjs \
    tools/shared-tree-oracle/generate.test.mjs
  just shared-tree-oracle
  just shared-tree-oracle-check
  ```

  Require five generated cases, unchanged source/version identity, and no
  skipped probe. Copy the observed outcome table into the spec with fixture
  IDs and raw paths. A source helper change must not alter existing captures'
  deterministic ID stream; give this probe its own process/test batch.
- [x] Review the source observations and contract before Task 2. Commit the
  producer, validators, generated output and checked contract as
  `test(tree): capture handle attachment lifecycle`.

### Task 2: Add typed handle leaves across schema, forest and codecs

**Files:** Modify `handle.gleam`, `tree/types.gleam`, `tree/schema.gleam`,
`tree/forest.gleam`, `tree/identifier.gleam`, `tree/codec.gleam`,
`tree/codec/field_batch.gleam`, `tree/codec/summary.gleam`,
`test/watershed/tree/fixtures.gleam`, existing schema/codec tests.
Create `test/watershed/shared_tree_handle_test.gleam`.

**Interfaces:** Produce the four `Reference` functions and
`bind_serialized_references(value: Json, context_path: String) ->
Result(Json, HandleError)` from spec section 4, `HandleValue(handle.Reference)`,
and `HandleLeaf`. Preserve existing codec signatures. Tagged native values use
the exact `kind: "handle"` record in the spec; reference context comes from the
source datastore.

- [x] Add a failing canonical handle-schema test and a FieldBatch round trip:

  ```gleam
  import gleam/option.{Some}
  import startest/expect
  import watershed/handle
  import watershed/tree/codec/field_batch
  import watershed/tree/schema
  import watershed/tree/types

  const handle_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.handle\":{\"kind\":{\"leaf\":3}}},\"root\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.handle\"]}}"

  pub fn shared_tree_handle_leaf_schema_and_field_batch_test() {
    let assert Ok(stored) = schema.stored_from_string(handle_schema)
    let assert Ok(reference) = handle.reference_from_path("/B/child")
    let value = types.HandleValue(reference)
    schema.validate_root(stored, value) |> expect.to_equal(Ok(Nil))
    schema.validate_root(stored, types.StringValue("/B/child"))
    |> expect.to_be_error()
    let assert Ok(encoded) =
      field_batch.encode_with_schema([[value]], Some(stored))
    field_batch.decode_with_schema(encoded, Some(stored))
    |> expect.to_equal(Ok([[value]]))
  }
  ```

- [x] Run the RED on both targets:

  ```sh
  gleam test --target erlang -- shared_tree_handle
  gleam test --target javascript -- shared_tree_handle
  ```

  Expect missing new variants/functions first, then the former unsupported
  handle schema/codec boundary. Remove the canonical handle case from the old
  unsupported-feature tests; keep mismatched leaf identifiers and unknown
  semantic kinds as refusals.
- [x] Implement `Reference` using existing marker/path validation. Resolve
  legacy relative values through the source datastore context. Preserve the
  path/equality rules captured in Task 1 and explicit malformed/pending errors.
  Do not call runtime resolution from schema or forest functions.
- [x] Implement `bind_serialized_references` with the existing recursive JSON
  traversal and marker/path helpers. Normalize relative serialized handles only
  when the runtime supplies the source datastore context; context-free
  FieldBatch decoding rejects them with a context error. Test the same `_C`
  marker under `/A` and `/B`, producing `/A/_C` and `/B/_C`, and reject a
  malformed marker nested at the end of a payload.
- [x] Implement `HandleLeaf` in public and comparison schema conversion,
  validation, compatibility and allowed-superset logic. Add `HandleValue` to
  forest value import/export, retained validation, identifier traversal and
  all compressed/uncompressed FieldBatch/repair/history codecs.
- [x] Add direct refusals for external URLs, path traversal, malformed percent
  escapes, unsupported payloads, malformed handle leaf contents and wrong
  schema kinds. Add equivalent-instance/path cases from the source fixture.
  Assert the error variant/location, not merely a boolean failure.
- [x] Register tagged fixture decoding/encoding and replay
  `handle-leaves` through production codecs. Keep the raw upstream encoding
  comparison in addition to the native round trip.
- [x] Run both focused target selections, the upstream consumer and corpus check:

  ```sh
  gleam test --target erlang -- shared_tree_handle shared_tree_schema shared_tree_codec
  gleam test --target javascript -- shared_tree_handle shared_tree_schema shared_tree_codec
  just shared-tree-codec-interop
  just shared-tree-oracle-check
  ```

- [x] Commit as `feat(tree): support Fluid handle leaves`.

**Task 2 acceptance, 2026-10-10:** Implemented at `ffe6c50e`, with the
zero-width compressed-field correction at `5921b19c`. Both targets first
failed on the missing reference and leaf interfaces. Final selections
(`shared_tree_handle shared_tree_field_batch shared_tree_schema shared_tree_codec`)
passed 131 Erlang and 132 JavaScript tests. Codec interoperability consumed
38 items on each target; the corpus check executed seven lifecycle probes and
reproduced all 68 upstream cases. `just lint` passed.

The task review found compressed optional nulls and arrays of zero-width
nodes losing their element count. The correction uses the existing integer
count representation, with failing-then-passing null and structural-node
regressions on both targets. Scoped review and fresh focused runs verified
both regressions. No native attachment/profile acceptance is claimed here.

### Task 3: Extend binding graphs and declared datastore creation

**Files:** Modify `runtime_core.gleam`, `channel.gleam`,
`wire/fluid_container.gleam`, `wire/op.gleam`.
Create `test/watershed/shared_tree_attachment_test.gleam` and
`test/watershed/tree/lifecycle_fixture.gleam`; modify fixture registration.

**Interfaces:**

- Keep `create_detached(core, address, init)` for existing DDS callers.
- Add `create_detached_data_store(core: Core, id: String) ->
  Result(Core, CoreError)` for the declared graph factory and its detached root
  SharedMap.
- Add `new_channel_address_in(core: Core, store_id: String, channel_id: String)
  -> Result(String, CoreError)`, accepting a registered or local unpublished
  datastore and rejecting duplicate/alias identity conflicts.
- Add `prepare_attachments(core: Core, source_address: String,
  references: List(handle.Reference)) ->
  Result(#(Core, List(fluid_container.MessageKind)), CoreError)`.
  The returned core is a candidate: callers commit it only together with a
  validated referring operation. It does not allocate CSNs or send messages.
- Add `lifecycle_fixture.run(input: Json) -> Result(Json, String)` and
  `lifecycle_fixture.run_case(id: String, input: Json) -> Result(Json, String)`.
  Native fixture replay must execute production runtime transitions.
- Add test helper `lifecycle_fixture.assert_scenario(case_id: String,
  scenario_id: String) -> Nil`. It loads the named case with `fixtures.load`,
  executes only that input scenario through production transitions, and compares
  the whole matching expected observation with `fixtures.first_difference`.
  Missing/duplicate scenario IDs fail; it does not copy expected fields into
  actual output.

- [x] Add a failing map-only lifecycle replay with exact raw message/order
  comparison:

  ```gleam
  import watershed/tree/lifecycle_fixture

  pub fn shared_tree_cross_datastore_map_attachment_test() {
    lifecycle_fixture.assert_scenario(
      "cross-datastore-attachment",
      "map-cross-datastore",
    )
  }

  pub fn shared_tree_cross_datastore_map_cycle_test() {
    lifecycle_fixture.assert_scenario(
      "cross-datastore-attachment",
      "map-cycle",
    )
  }
  ```

  Before Task 4, compare only these complete map scenarios. A full-case runner
  rejects unsupported tree scenarios; do not register a partial runner as
  accepting the full case. Task 4 enables the complete attachment cases.
- [x] Run both targets with `-- shared_tree_attachment`; confirm the production
  failure is unpublished-store creation/attachment, not fixture dispatch.
- [x] Add only missing detached datastore metadata and binding state to `Core`.
  Preserve published routing and the original root alias. Track binding edges
  at measured serialization boundaries, including removed-but-retained edges.
  Extend `has_channel`/route lookup to local datastores without making them
  visible or persistent on creation.
- [x] Extend the existing visited traversal for channel/datastore graphs.
  Mark candidate local visibility before recursion to terminate cycles.
  Generate datastore snapshots for newly visible stores, channel attaches for
  visible stores, and no duplicate attach for repeated references. Preserve the
  entry-point and package requirements captured in Task 1.
- [x] Wire map handle serialization and the existing `attach_dependencies`
  callers through the shared candidate preparation, then the existing
  submission stamping. Keep non-tree DDS errors and event behavior intact.
  Apply contextual serialized-handle binding before decoding an incoming
  channel payload; later tree/summary tasks reuse that boundary.
- [x] Keep error preparation pure. Test malformed last dependencies, unknown
  targets, duplicate store/channel IDs, and unsupported package identities with
  snapshots of core state, CSN, compressor and in-flight counts before/after.
  Existing non-tree DDS attachment tests must keep their measured behavior.
- [x] Add source-backed tests for bound-then-removed references, root-to-map
  graphs, two-way/cyclic datastore references and resolving an unloaded channel
  after an incoming datastore attach. Preserve the package/attribute bytes.
- [x] Run:

  ```sh
  gleam test --target erlang -- shared_tree_attachment shared_tree_container handle
  gleam test --target javascript -- shared_tree_attachment shared_tree_container handle
  node --test tools/shared-tree-oracle/container-foundations.test.mjs
  ```

- [x] Commit as `feat(runtime): prepare bound datastore attachment graphs`.

**Task 3 acceptance, 2026-10-10:** Implemented at `b022cee3` and corrected at
`a9a5756e`. Map-only replay executes production cores from the captured
document, compressor and command inputs, and compares complete raw transport,
snapshot bytes, ordering and receiver serialization. Mixed tree cases still
refuse until Task 4.

Review identified swallowed nested-reference errors, missing later channel
attaches in published local stores, and incomplete raw comparison. All three
were corrected and the scoped re-review found no significant issues.
Final attachment suites passed 17 tests per target, the Task 3 selections
passed 68 per target, runtime-core regressions passed 116 per target, and
the container-foundations Node suite passed three tests. Reconnect checks
compare preserved identities and consume the resubmission acknowledgement.

### Task 4: Create and attach trees with document context

**Files:** Modify `tree/runtime.gleam`, `tree_kernel.gleam`,
`runtime_core.gleam`, `channel.gleam`, `wire/op.gleam`,
`wire/summary.gleam`, `wire/fluid_document.gleam`,
native lifecycle fixture and attachment/runtime/summary tests.

**Interfaces:**

- Add `create_detached_tree(core: Core, address: String,
  stored: tree_schema.StoredSchema, initial_root: Option(tree_types.TreeValue),
  view_id: fluid_ids.StableId) -> Result(Core, CoreError)`.
- Add `tree_runtime.create_detached(stored: schema.StoredSchema,
  initial_root: Option(types.TreeValue), view_id: fluid_ids.StableId,
  compressor: fluid_ids.Compressor, sequence_number: Int,
  minimum_sequence_number: Int) ->
  Result(#(tree_kernel.TreeState, fluid_ids.Compressor), types.TreeError)`.
- Add `tree_runtime.snapshot_for_attach(state: tree_kernel.TreeState,
  compressor: fluid_ids.Compressor) ->
  Result(tree_kernel.TreeSnapshot, types.TreeError)`.
- Add `wire_op.encode_tree_attach(route: fluid_container.Route,
  snapshot: tree_kernel.TreeSnapshot, compressor: fluid_ids.Compressor) ->
  Result(fluid_container.MessageKind, fluid_container.ContainerError)`.
  Reuse hierarchical tree summary encoders; do not put a tree in a generic
  `header` blob.
- Contextual tree attach decoding receives the document compressor, local view
  identity, source datastore context and enclosing sequence/minimum numbers
  before creating a `channel.TreeSnapshot`. Parse and bind handle markers in
  each tree summary blob before invoking context-free tree codecs. Keep
  context-free map/other DDS decoding intact.

- [x] Add the full source-backed attach tests:

  ```gleam
  import watershed/tree/fixtures
  import watershed/tree/lifecycle_fixture

  pub fn shared_tree_live_channel_attachment_test() {
    fixtures.assert_case(
      "live-channel-attachment",
      lifecycle_fixture.run_case("live-channel-attachment", _),
    )
  }

  pub fn shared_tree_cross_datastore_tree_attachment_test() {
    fixtures.assert_case(
      "cross-datastore-attachment",
      lifecycle_fixture.run_case("cross-datastore-attachment", _),
    )
  }
  ```

- [x] Run both target selections and confirm tree creation/document-context
  attach fails. Implement the initial snapshot helper using the document
  compressor and schema construction validation; reuse it from the fixed
  creator only where that removes the existing duplicated initialization.
- [x] Preserve identities through detached edits and attach promotion.
  Snapshot the state/retention that upstream captures, including completed
  local transactions and identifiers; preserve edits after snapshot capture.
  Do not generate a new forest from the displayed root on ack.
- [x] Extend tree lookup and checkout operations to local detached trees,
  including reads, edits, subscriptions, transactions and local handle
  resolution. Detached edits update local tree state and deliver measured
  local events without transport submission; publication takes the attach
  path only when upstream's binding rule makes the channel visible.
- [x] Extend the candidate attachment planner with contextual tree snapshots
  and identifier allocation dependencies. Decode newly attached trees only
  after their required allocation and datastore context exists.
  Initialize/check tree checkout registries on remote and local attachment.
- [x] Refuse attachment of an actively transacting target tree with an explicit
  tree/lifecycle error. Test a group whose final tree snapshot is corrupt,
  mismatched attributes, missing allocation, duplicate identity and wrong ack
  snapshot. No prior group state or event may escape those refusals.
- [x] Test multiple attached trees sharing one compressor, preserving
  identifiers and node identities through concurrent allocations and later
  attachment. Assert exact source-backed allocation order and final IDs.
- [x] Run:

  ```sh
  gleam test --target erlang -- shared_tree_attachment shared_tree_runtime shared_tree_summary shared_tree_document_summary
  gleam test --target javascript -- shared_tree_attachment shared_tree_runtime shared_tree_summary shared_tree_document_summary
  node smoke/shared_tree_creation.mjs
  just shared-tree-codec-interop
  ```

- [x] Commit as `feat(tree): attach native trees with document identity`.

**Task 4 acceptance, 2026-10-11:** Foundations and schema-race corrections
landed in `fc77d751` through `c60b6e3b`; identity/history/event recovery landed
in `5c352a58`. Native replay compares complete source-backed attachment
transport and receiver state, plus twelve checkpoint summary envelopes/blob
strings, compressor reservations/final identities, stable checkout/root/anchor
tokens, local/remote events, settlements, and the selected detached inverse.
Production promotion keeps retained history rather than rebuilding visible data.

Review found lost promoted history, repeated sibling shape traversal, and
missing detached settlements. Corrections and failing-first regressions close
those findings. Additional summary regressions preserve window-start batches,
peer ancestry, and retained replay receipts. The spec records the narrow
loadability exception for a pinned Fluid summary that omits its peer base.
Captured lifecycle checkpoint bytes remain unchanged.

Fresh serial acceptance passed 1143 Erlang and 1116 JavaScript tests through
`just shared-tree-test`, including the JS/BEAM reconnect tests and
storage/bootstrap/creation smokes. Pinned codec consumers passed 38 items per
target; lint and whitespace checks passed. Final scoped re-review found no
remaining original Task 4 blocker. Facade factory-lifetime checks remain in
Task 6; graph publication, retained GC, and real-service proof remain in
Tasks 5–9. This acceptance does not complete M7.

### Task 5: Bind references at publication, transaction and branch boundaries

**Files:** Modify `runtime_core.gleam`, tree runtime/kernel/history code only
where the source contract requires it, existing transaction/branch/undo tests,
and `lifecycle_fixture.gleam`.

**Interfaces:** Consume Task 3's candidate preparation and Task 4's contextual
tree attachment. Preserve `submit_tree_commits`, `tree_transaction`, checkout
selectors, commit kinds and retained handles. Produce the full
`handle-transaction-branch` native proof; all tree publication paths use the
same binding rule. Compose the source-backed publication and identity runners,
the separate active-target preflight runner, and actual JS/BEAM facade lifetime
tests. Do not return copied expected observations to manufacture a full JSON
result: the spec explicitly excludes upstream failure-side-effect parity.

- [x] Add the failing source-backed boundary tests:

  ```gleam
  import watershed/tree/lifecycle_fixture

  pub fn shared_tree_handle_publication_boundary_replay_test() {
    lifecycle_fixture.assert_publication_replay("handle-transaction-branch")
  }

  pub fn shared_tree_multiple_tree_identity_lifecycle_test() {
    lifecycle_fixture.assert_identity_replay("handle-transaction-branch")
  }

  pub fn shared_tree_handle_publication_active_target_preflight_test() {
    lifecycle_fixture.assert_publication_active_target_preflight(
      "handle-transaction-branch",
    )
  }
  ```

  Publication replay must compare the complete emitted transport prefix,
  cumulative transaction/branch values, compressor state, local serialized
  changes, remote events and scoped settlements. Identity replay must compare
  all twelve captured summaries and identity checkpoints. Actual facade tests
  must prove duplicate/late inverse acquisition refusal, same-handle disposal
  callbacks and branch-marker resolution to the document channel. A pure-core
  inverse status check is not a substitute for those runtime observations.

- [x] Run on both targets. Trace every tree commit producer: direct edits,
  outer transaction commits, undo/redo, branch merge, reconnect resubmission
  and schema operations. Route supported handle-bearing publications through
  the shared planner. Do not bind on an optimistic UI update or by reading only
  the final root.
- [x] Prepare attachment messages and tree edits before stamping a submission.
  Use existing group metadata, CSNs, in-flight equality and reconnect barriers.
  Follow measured cyclic order and allocation context; do not reorder messages
  to satisfy an assumed acyclic algorithm.
- [x] Implement the measured successful/aborted/nested transaction behavior.
  Keep data rollback and lifecycle side effects separate. Test failure of a
  target's active transaction and a corrupt last dependency before a parent
  submission; preserve error visibility and existing compressor rollback rules.
- [x] Implement measured branch binding before/after merge and disposal.
  Preserve `tree_handle_of`'s existing channel-address behavior for a local
  checkout. Resolving that marker opens the document channel, not the fork;
  it does not create a channel or publish the fork's unmerged edits.
  Schema authoring on branches and cross-tree transactions remain excluded.
- [x] Verify that undo removes/replaces the parent reference but leaves the
  attached target and peer-authored target edits intact. Check commit kind,
  inverse factory acquisition, target identity and disposal, not only values.
- [x] Run:

  ```sh
  gleam test --target erlang -- shared_tree_attachment shared_tree_transaction shared_tree_branch shared_tree_undo
  gleam test --target javascript -- shared_tree_attachment shared_tree_transaction shared_tree_branch shared_tree_undo
  ```

- [x] Commit as `feat(runtime): bind tree handles at publication boundaries`.

Task 5 accepted after scoped publication and facade reviews. Final integrated
gate: 1152 Erlang and 1124 JavaScript SharedTree tests, all three native storage,
bootstrap and creation smokes; generic core/wire/LWW coverage: 274 per target;
pinned codec interoperability: 38 items per target. Exact standalone map GC
and original logical batch IDs now survive source-backed comparison and
repeated reconnects. Lint and whitespace checks passed. Twenty unrelated
legacy Sluice/workspace failures reproduce on unchanged HEAD; the two
metadata-dropping acknowledgement helpers found during the full run are fixed.
This is local evidence, not hosted acceptance.

### Task 6: Expose matching JS and BEAM lifecycle APIs

**Files:** Modify `runtime.gleam`, `runtime_beam.gleam`,
`watershed.gleam`, `watershed_beam.gleam`, JS/BEAM runtime tests,
`facade_parity_test.gleam`, root README.

**Interfaces:** Expose the exact `DataStore`, `create_data_store`,
`data_store_root`, `create_map_in`, `create_tree`, and `create_tree_in`
signatures from spec section 5 on both facades. JS and BEAM lifecycle calls
return `Result`; neither creates a new HTTP container. Keep
`create_tree_container`'s existing target-specific result/promise contract.
Preserve existing handle and resolver functions rather than adding another
handle wrapper.

- [ ] Add lifecycle API names to the tree/datastore parity inventory and make
  both runtimes fail at the missing behavior. Extend existing real-runtime
  tests with this operation sequence:

  ```text
  ready document
  create_data_store -> local store and local root map, zero submissions
  create_tree_in -> local tree, zero submissions
  tree_set on local tree -> changed local value, zero submissions
  set(root(document), "secondary", handle_of(data_store_root(store)))
  set(data_store_root(store), "tree", tree_handle_of(local_tree))
  deliver measured attaches/reference messages
  peer resolve -> exact tree/target values and stable identifiers
  peer edit -> both clients observe the change
  ```

  Use the actual API wrappers and existing transport/actor test fixtures.
  Record submit counts at each step; a name-only parity test is not acceptance.
- [ ] Implement runtime calls with checked writable/ready state and typed core
  errors mapped through existing facade conventions. Require
  `schema.can_view(stored, view)` before returning a locally created tree view.
  Preserve existing resolution retry behavior for references awaiting attach.
- [ ] Reject foreign-runtime datastore objects, stores from closed documents,
  duplicate identities, incompatible views and invalid initial content.
  Assert unchanged runtime, compressor and submission count on each refusal.
  Do not claim copied marker JSON has verifiable foreign-container provenance.
- [ ] Verify subscriptions, commit factories, disposal and close for newly
  attached channels on both targets. BEAM actor calls must not bypass
  transaction ownership; JS must not run attachment work in callback delivery.
- [ ] Document detached creation, implicit graph attachment, source context,
  ready/writable requirements, and profile limits beside the API inventory.
- [ ] Run:

  ```sh
  gleam test --target erlang -- shared_tree_runtime facade_parity
  gleam test --target javascript -- shared_tree_runtime facade_parity
  cd watershed_lustre && gleam test
  ```

- [ ] Commit as `feat(api): expose detached tree and datastore lifecycle`.

### Task 7: Persist graph metadata and upstream-retained GC routes

**Files:** Modify `wire/fluid_document.gleam`, `wire/fluid_summary.gleam`,
`wire/summary.gleam`, tree snapshot/retention reference traversal,
`channel.gleam`, summary tests, lifecycle fixture,
`tools/shared-tree-oracle/summary-interop.mjs` and its tests.

**Interfaces:** Preserve `fluid_document.capture`, `encode`, `decode` and
`CaptureRouting`. Add one shared supported-reference traversal for tree values
and retained snapshot/history data. Attachment consumes binding edges;
GC consumes measured retained state. They must not conflate those lifetimes.
Produce the full `handle-retention` runner.

- [ ] Add a source-backed failing retention/GC test:

  ```gleam
  import watershed/tree/fixtures
  import watershed/tree/lifecycle_fixture

  pub fn shared_tree_handle_retained_gc_and_reload_test() {
    fixtures.assert_case(
      "handle-retention",
      lifecycle_fixture.run_case("handle-retention", _),
    )
  }
  ```

- [ ] Run both targets and inspect the first missing exact route/blob/property.
  Extend metadata capture for sequenced secondary datastores and trees.
  Keep local unpublished stores out of document publication.
- [ ] Replace map-only GC reference extraction with the shared supported
  traversal. Use source-datastore context for relative markers in map/tree
  content. Include the forest, detached repair data and edit-manager retained
  sources required by Task 1; preserve upstream root status and timestamps.
  Do not turn all secondary stores or local branches into persisted roots.
- [ ] Apply `bind_serialized_references` to parsed summary blobs with their
  source datastore context before tree decoding. Test legacy relative handles
  in two datastores; re-encoding must preserve the captured upstream absolute
  paths without guessing the context from the reader's bootstrap map.
- [ ] Test routes before removal, after removal with retained history, undo,
  branch disposal and handle disposal. Check the exact outgoing route sets and
  reference paths, not whether `gcNodes` exists.
- [ ] Add actual hierarchical summary round-trip/reload tests for two trees,
  two datastores and a cyclic handle graph. Preserve components, channel
  attributes, alias immutability, compressor session/final IDs and retained
  values. Load from fetched bytes and perform a continuing edit.
- [ ] Extend upstream summary consumers so native attach/summary bytes pass
  the pinned loader. Reject publication descriptors pointing at different
  trees/blobs, wrong factory packages and wrong routes.
- [ ] Run:

  ```sh
  gleam test --target erlang -- shared_tree_summary shared_tree_document_summary shared_tree_attachment
  gleam test --target javascript -- shared_tree_summary shared_tree_document_summary shared_tree_attachment
  node --test tools/shared-tree-oracle/summary-interop.test.mjs
  node smoke/shared_tree_storage.mjs
  node smoke/shared_tree_bootstrap.mjs
  ```

- [ ] Commit as `feat(storage): persist handle graphs and retained routes`.

### Task 8: Prove live lifecycle through real upstream/JS/BEAM clients

**Files:** Create `tools/shared-tree-oracle/lifecycle-interop.mjs` and
`lifecycle-interop.test.mjs`. Modify `schema.mjs`, `service.mjs`,
`client-driver.mjs`, `interop-scenarios.mjs`, `interop.mjs`,
native client protocol/implementations/tests and summary consumers.

**Interfaces:**

- `lifecycle-interop.mjs` exports async `runLifecycleInterop(options)`,
  `validateLifecycleSection(name, section, artifacts)`, and
  `validateLifecycleReport(report, artifacts)`. Section validation checks a
  complete measured section; final report validation requires all seven
  sections and calls those same validators. Neither accepts a skipped section
  as complete. Its CLI supports
  `--local-floodgate --iterations 300 --seed 42` and uses the existing owned
  service lifecycle. Add a bounded `--scenario <id>` selector for debugging.
- Required report sections are `handleValues`, `channelAttachment`,
  `datastoreAttachment`, `handleTransactionBranch`, `handleRetention`,
  `handleReconnect`, and `handleReloadMatrix`.
- Register the Task 1 schema in `schema.mjs` and the declared secondary factory
  `org.watershed.shared-tree.m7.graph` with a SharedMap entry point and the
  existing map/tree registry in the code loader.
- Native client commands own real facade objects:

  ```json
  {"command":"create-data-store","name":"secondary"}
  {"command":"create-map","store":"secondary","name":"target-map"}
  {"command":"create-tree","store":"secondary","name":"target-tree","schema":{"version":2,"nodes":{"com.fluidframework.leaf.string":{"kind":{"leaf":1}}},"root":{"kind":"Value","types":["com.fluidframework.leaf.string"]}},"initialRoot":{"kind":"string","value":"start"},"view":{"version":2,"nodes":{"com.fluidframework.leaf.string":{"kind":{"leaf":1}}},"root":{"kind":"Value","types":["com.fluidframework.leaf.string"]}}}
  {"command":"open-tree","name":"selected","handle":{"type":"__fluid_handle__","url":"/B/child"},"view":{"version":2,"nodes":{"com.fluidframework.leaf.string":{"kind":{"leaf":1}}},"root":{"kind":"Value","types":["com.fluidframework.leaf.string"]}}}
  ```

  These commands illustrate a string-valued target tree. Handle-bearing
  parent scenarios use the full Task 1 graph schema. Opening a tree uses its
  actual returned handle rather than assuming the illustrative `/B/child`
  identity. Creation replies include actual handles; named stores/trees live in each
  native client, not in a coordinator simulation. Existing editing/history
  commands gain an optional selected-tree name while retaining their current
  default tree for old scenarios.

- [ ] Add genuine producer/validator tests before the expensive service run.
  Generate a bounded same-datastore section with real clients and require the
  shared section validator to accept it. Mutate that same artifact:

  ```js
  await validateLifecycleSection(
    "channelAttachment", report.channelAttachment, artifacts,
  );
  const changed = structuredClone(report.channelAttachment);
  changed.raw.submitted = [];
  await assert.rejects(
    () => validateLifecycleSection("channelAttachment", changed, artifacts),
    /submitted.*attach|raw.*attach/i,
  );
  ```

  Add independent mutations for wrong target paths, omitted/reordered
  allocations and attaches, invented revision/ack identities, false
  accepted-before-disconnect claims, missing reload cells, modified raw storage
  bytes and incorrect GC routes. Keep a valid captured positive for each
  section. A validator that only rejects absent booleans is insufficient.
- [ ] Implement the selected-object protocol using public native facades on
  both targets. Unknown names, malformed handle records, wrong runtime
  objects, closed channels and incompatible views return structured errors.
  The coordinator issues commands and measures results; it does not create
  native IDs, build changesets, emulate attachment, or rewrite client state.
- [ ] Run upstream/JS/BEAM handle edits for object/map/array values and
  same-datastore detached map/tree creation. Check local visibility, no early
  transport, exact attach snapshots, stable identities and peer resolution.
- [ ] Run each writer's declared secondary datastore graph. Cover root/map/tree
  references, additional channels after datastore visibility, removed binding
  edges and cycles. Validate actual factory/attributes and raw ordering.
- [ ] Run transaction/branch/undo/retention cases with new references and peer
  target edits. Capture real commits, factories, target identities and
  settlements; preserve old M5/M6 event and isolation semantics.
- [ ] Hold real attach/reference acknowledgement delivery, prove the service
  accepted the messages using raw deltas, then disconnect and reconnect.
  Require one logical target after resubmission, preserved IDs/paths, correctly
  drained pending work and unchanged peer data. Also cover disconnect before
  acceptance. Do not simulate acceptance with a local pending counter.
- [ ] Publish and fetch the actual storage for all writer/reader cells:

  ```js
  const writers = ["upstream", "javascript", "erlang"];
  const readers = ["upstream", "javascript", "erlang"];
  const checkpoints = [
    "same-datastore",
    "cross-datastore",
    "handle-undo-redo",
  ];
  const expectedCells = writers.flatMap((writer) =>
    checkpoints.flatMap((checkpoint) =>
      readers.map((reader) => `${writer}:${checkpoint}:${reader}`)));
  assert.equal(expectedCells.length, 27);
  ```

  Require exact cell coverage and unique IDs. Each reader loads the published
  bytes, resolves targets, checks schema/value/order/identifiers/GC and authors
  a continuing write observed by another implementation. Do not compare two
  copied coordinator projections as proof of a load.
- [ ] Run each bounded real section through `validateLifecycleSection` before
  the full wrapper. Require `validateLifecycleReport` on the complete generated
  report with all seven sections. Then run:

  ```sh
  gleam test --target erlang -- shared_tree_client
  gleam test --target javascript -- shared_tree_client
  node --test tools/shared-tree-oracle/client-driver.test.mjs \
    tools/shared-tree-oracle/client-interop.test.mjs \
    tools/shared-tree-oracle/interop.test.mjs \
    tools/shared-tree-oracle/interop-scenarios.test.mjs \
    tools/shared-tree-oracle/lifecycle-interop.test.mjs
  node tools/shared-tree-oracle/lifecycle-interop.mjs \
    --local-floodgate --iterations 300 --seed 42
  just shared-tree-create-interop
  just shared-tree-interop
  ```

  Require 27 reload cells, 300 schedules, all seven sections, zero skips and
  no divergences. Use a compatible running loopback service or the existing
  pinned owned service mechanism; do not kill/reconfigure another user's
  service. Clean up only the processes/data this run owns.
- [ ] Commit verified client/scenario chunks as
  `test(interop): prove handle and attachment lifecycle`.

### Task 9: Publish proven profile and record release acceptance

**Files:** Modify generated-profile producer and service manifest definitions,
`justfile`, native/service SharedTree workflows, root/oracle READMEs,
parent design/roadmap and this plan. Generated profile changes come from
`just shared-tree-oracle`; preserve the original profile/version pins.

**Interfaces:** Publish only the exact accepted handle/map/tree/declared-store
scope. Add recipe `shared-tree-lifecycle-interop` for Task 8's non-skipping CLI.
Wire lifecycle service acceptance into the existing manually dispatched
SharedTree service workflow; do not dispatch that workflow while executing
this plan. Existing native CI must include the new generated cases and runners.

- [ ] Add profile/gate regressions:

  ```js
  assert.deepEqual(profile.lifecycle.nativeTargets, ["javascript", "erlang"]);
  assert.equal(profile.lifecycle.seed, 42);
  assert.equal(profile.lifecycle.iterations, 300);
  assert.equal(profile.lifecycle.reloadCells, 27);
  assert.deepEqual(profile.lifecycle.targetKinds, ["SharedMap", "SharedTree"]);
  assert.equal(profile.lifecycle.datastoreType, "org.watershed.shared-tree.m7.graph");
  ```

  Define this `lifecycle` profile record in the generator and service producer
  together. Require all five generated cases and seven report sections;
  unavailable source/runner/service must fail the gate.
- [ ] Update feature inclusions/exclusions without declaring the whole M7
  complete or promising arbitrary layouts, blobs, aliases, production tokens
  or disk recovery. Document JS/BEAM lifecycle signatures, runtime ownership,
  binding timing, retained routes and transaction limitations from the checked
  contract. Preserve the fixed creator's existing examples.
- [ ] Run the combined acceptance commands on the final source:

  ```sh
  just shared-tree-oracle-check
  just shared-tree-test
  node --test tools/shared-tree-oracle/*.test.mjs
  just shared-tree-lifecycle-interop
  just shared-tree-create-interop
  just shared-tree-interop
  just build
  just test
  just lint
  just shared-tree-checklist
  ```

  Run the smallest focused commands while developing; this is the final
  runtime/persistence release boundary. Required browser/service commands
  must execute rather than exit successfully after a skip. Record the final
  code range; a later material runtime fix requires its covering gates again.
- [ ] Review the complete implementation and resolve material findings.
  Record dated source/native/codec/service/browser commands, run IDs, exact
  case/schedule/reload-cell counts and errors in this plan. Identify local
  evidence as local; workflow definitions do not establish hosted acceptance.
- [ ] Update the parent roadmap with the completed scope and remaining M7
  items only after the gates pass. Commit as
  `docs(tree): publish accepted handle attachment profile`.

## Planning self-review

| Spec requirement | Tasks |
| --- | --- |
| Checked upstream semantics and unsupported/skipped boundaries | 1 |
| Handle schema, pure values, marker context and every codec consumer | 2 |
| Binding history, cycles and declared cross-datastore lifecycle | 3, 4, 5 |
| Document compressor, detached edits, contextual attach and stable identity | 4 |
| Transaction/branch/undo lifetime and rollback distinctions | 1, 5 |
| Matching native APIs, runtime ownership and error behavior | 6 |
| Hierarchical bytes, metadata, retained GC and fresh continuation | 7, 8 |
| Raw transport/storage binding, reconnect and 27 reload cells | 8 |
| Non-skipping permanent profile/gates, regressions and honest M7 status | 9 |

The source capture is the prerequisite for unsettled empirical behavior.
Exact interfaces above define the proposed native boundary; reconcile them
against Task 1 rather than claiming those unexecuted probes already passed.
Implementation, generated profiles and acceptance remain pending.

## Execution record, 2026-10-10

Execution started at `90d993f2`. The supplied plan, spec, and parent links were
committed as `db86a94a`. The user authorized the current `main` checkout and task
commits, not merges, pushes, publishing, or hosted workflows.

The baseline commands above completed successfully: pinned source verification,
the existing native SharedTree recipe, and 62 Node baseline tests with no
failures or skips. The native selections ran 1084 Erlang and 1057 JavaScript
tests.

The Task 1 implementation worker failed with an internal error after leaving
partial edits, without a report or commit. Direct recovery corrected
already-visible cycle scenarios, a locally authored edit labeled as a peer
edit, incorrect nested message-order extraction, stale capture digests, and an
unserialized removed-dependency scenario. The producer now captures five
source-only cases in an isolated process. The spec records the measured
checkpoints and their limitations.

Preliminary recovery was committed as `80e4d09a`
(`test(tree): start handle lifecycle discovery`). A scoped review found five
evidence-validation gaps and two incorrectly associated records. The commit
corrected them, and a scoped re-review marked all seven findings addressed.
That review did not accept the complete Task 1 contract.

Current recovery evidence:

| Command | Result |
| --- | --- |
| Bounded `source.mjs lifecycle-capture` | Five source tests executed and passed, with no skips. |
| `just shared-tree-oracle` | Generated 68 cases, including five new source-only lifecycle cases. |
| `just shared-tree-oracle-check` | All 68 cases reproduced byte-for-byte. |
| Source/generate Node suite after the scoped fixes | 173 passed, no failures or skips. |
| Native fixture-loader selections after the scoped fixes | 22 Erlang and 22 JavaScript tests passed. |
| `just shared-tree-test` during recovery, before validator-only fixes | 1084 Erlang and 1057 JavaScript tests passed; storage, bootstrap and creation smokes completed. |

The existing negative source corpus prints caught upstream assertion
diagnostics; target compilers also report existing unused-function and
JavaScript unsafe-integer fixture warnings. These are not skipped gates.
The generated supported profile and its 37 native semantic runners per target
are unchanged.

### Subsequent discovery slices

Storage proof completed through `ad521e18`, with actual published document
versions, fetched hierarchical snapshot/blob bytes, protocol sequences,
document GC and fresh-client continuation. Leaf proof completed through
`a46c77e0`, with executable per-edit schemas/initial roots, real handle
resolution and structurally decoded FieldBatch input.

The two attachment cases now contain executable initial document state,
writer compressor/session context, complete sequenced prefixes, cumulative
typed commands and distinct receiving-client graph observations. Validators
decode actual map headers, keyed tree forests and reference operations,
compare command/checkpoint graphs, and enforce allocation/dependency/reference
order. Map-only datastore scenarios run before any tree creation. Active-target
failure replay has its own document input and the documented native atomic
preflight-refusal boundary.

| Command | Latest graph-slice result |
| --- | --- |
| Bounded `source.mjs lifecycle-capture` | Six executed source tests passed, no skips. |
| `just shared-tree-oracle` | Generated all 68 cases. |
| Source/generate/codec Node suites | 214 passed, no failures or skips. |
| Focused graph self-review regressions | 15 passed, no failures or skips. |
| `just shared-tree-oracle-check` | All 68 cases reproduced byte-for-byte. |
| Original corpus/profile comparison against `a46c77e0` | All 63 non-lifecycle cases, manifest and native profile unchanged. |

Lifecycle IDs changed as measured after adding real peers and moving primary
tree creation after the map-only checkpoints. Regeneration includes those
changes; no fixture bytes or IDs were normalized by hand.

### History replay continuation

Transaction/branch and retention replay inputs now include actual initial
document storage, compressor/session context, complete delivery prefixes,
exact cumulative commands, and sixteen writer/receiver checkpoints. Attached
targets resolve on the receiver; aborted and unmerged targets remain local.
Checkpoint forests and published map/tree bytes are decoded separately from
the source's visible-value records.

Intermediate transaction stages preserve deferred attachment/transport and
the rollback's retained local compressor advancement. Nested map/array edits
publish in one tree operation. Undo restores the prior reference through a
revision-keyed refresher while preserving a peer-authored target edit. The
peer's read-to-write connection change is captured explicitly; the original
insertion revertible auto-disposes on default revert. The active-target history
scenario now has its own failed-publication replay document and the same
native preflight-refusal boundary as the live attachment case.

Self-review added regressions for synchronized false receiver checkpoints,
missing/gapped input, command/lifetime omissions, fabricated branch attachment
observations, unrelated undo refreshers, incorrect publication/target bytes,
and invalid trace actions. The existing nested-visible test now checks its
two distinct source records. A child-process array-progress check retains its
exact decoder-error assertion with a ten-second timeout: measured module
startup took roughly two seconds, while the failing decode took 25 ms.

| Command | History-slice result |
| --- | --- |
| Bounded `source.mjs lifecycle-capture` | Six executed source tests passed, no skips. |
| `just shared-tree-oracle` | Generated all 68 cases. |
| Source/generate/codec Node suites | 228 passed, no failures or skips. |
| Focused history and related regression selections | 28 passed, no failures or skips. |
| `just shared-tree-oracle-check` | All 68 cases reproduced byte-for-byte. |
| Original corpus/profile comparison against `b8d7f11e` | All 63 non-lifecycle cases, manifest and native profile unchanged. |

**Task 1 remains open.** Multi-tree document-compressor identity and the
remaining commit/factory/revertible/event lifetime evidence precede the final
original-checklist audit and contract review. Tasks 2-9 have not started. The
generated profile and native semantic runners still exclude this lifecycle
support; M7 remains partial.

### Task 1 completion: identity/events and contract audit

The final source probe records twelve checkpoints in a separate actual
document. Two trees share its compressor, attach in reverse creation order,
retain root/checkout/anchor identity, accept interleaved detached and
writer/peer edits, and undo an original detached edit through the same
application-owned inverse. Every checkpoint has exact cumulative commands,
ongoing/summary compressor bytes, cloned reservations, actual events and
independent summary bytes. The complete raw prefix binds writer and peer
allocations, attach snapshots, string edits and revision-keyed undo repair.

The sixteen history checkpoints now include actual local/remote changed
events, stable revisions, factory availability, local settlements and branch
inverse lifetimes. Aborted and nested intermediate stages produce no commits;
an independent target-map edit survives referring-tree rollback. Branch-only
inverses do not settle, dispose with the same-handle callback after merge or
checkout disposal, and enforce the single-acquisition/event-window boundary.
Serialized local-checkout markers resolve the existing document channel,
not unmerged content. Fresh loads restore no application-owned inverse or
local branch stacks.

Finite validation replays the pinned compressor and structurally compares
session-space local events with originator-relative Message V7 commits.
Detached history is checked against attach snapshots; string undo refreshers
must identify the field removed by the original detached event. Branch fork
and edit reservations are checked against the prior ongoing compressor,
including discarded commits that never publish.

| Original Task 1 checklist | Checked evidence |
| --- | --- |
| Registry, digest and missing-evidence regressions | `source.test.mjs` owned-injection checks; positive and mutation checks in `generate.test.mjs`; all five cases have `raw.source` and observation associations. |
| Registered pinned producer and declared schema | `source.mjs` lifecycle injector and isolated `--fail-zero` runner; `upstream-lifecycle.spec.ts` `Root`, `Links`, `Sequence` and declared graph factory. |
| Leaf values, identity, paths, codecs and refusals | `handle-leaves`: executable per-edit inputs; live wrapper/relative/escaped resolution; structurally decoded V2 codecs; actual serializer/assignment outcomes and explicit native refusals. |
| Detached edits, removed bindings, nested/self/cyclic graphs, completed transactions | `live-channel-attachment`: exact commands, attach summaries/ranges and real receiver graphs; `input.identityReplay` adds stable multi-tree promotion and inverse lifetime. |
| Declared secondary datastore, metadata, membership and order | `cross-datastore-attachment`: complete map-only and tree scenarios, receiver identity, component/package metadata and decoded datastore/channel attach order. |
| Transactions, active target, branch merge/drop/disposal and peer undo | `handle-transaction-branch`: stage reads/counts, target state, actual events/settlements/factories, branch marker resolution and peer-owned target edit; separate active-target failure replay. |
| Published summaries, retained GC, unreferenced datastore and fresh continuation | `handle-retention`: eight named fetched publications, stored hierarchical bytes, exact GC/component metadata, fresh load and continuing edit with empty restored local lifetime. |
| Non-skipping capture, complete generation and byte reproduction | Seven source probes; 239 covering Node tests; all 68 cases generated and reproduced; original 63 cases, manifest and native profile byte-identical against `d0c23704`. |
| Contract review before Task 2 | Direct source/validator self-review and coherent mutation regressions; checked spec and README preserve stronger native atomic preflight refusal and bounded supported scope. |

| Command | Final Task 1 result |
| --- | --- |
| Bounded `source.mjs lifecycle-capture` | Seven source tests executed and passed, no skips. |
| `just shared-tree-oracle` | All 68 cases generated. |
| Source/generate/codec Node suites | 239 passed, 0 failures or skips. |
| Focused lifecycle/history/identity/event selections | 55 passed, 0 failures or skips. |
| `just shared-tree-oracle-check` | All 68 cases reproduced byte-for-byte. |
| Existing native fixture-loader selections | 22 Erlang and 22 JavaScript tests passed; input-loader checks only, not lifecycle semantic support. |
| Artifact boundary and whitespace checks | Original 63 cases, manifest and native profile unchanged; `git diff --check` clean. |

Self-review caught an initially unbound dropped-branch revision: a different
valid compressor revision could impersonate that commit if all event copies
were changed together. The regression failed before the fix; validation now
replays the fork/edit reservations and checks the exact commit atoms. Missing
identity input, replaced objects, fabricated reservations, intermediate event
publication, false factories/settlements and revived fresh-load stacks also
have real-fixture mutation checks.

**Task 1 is complete.** Its nine checklist items and the final identity/event
brief are checked against source evidence. Native Tasks 2-9 have not started,
the lifecycle support profile is not promoted, and M7 remains partial.
