# SharedTree Arrays and Moves Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add upstream-compatible SharedTree arrays, range edits, and
identity-preserving moves within and between compatible arrays on JavaScript
and BEAM.

**Architecture:** Extend the existing persistent forest and closed modular
field dispatch with the pinned sequence-field algebra. Resolve existing
string-list paths into field/index steps before authoring changes, and keep
cross-field move effects inside one changeset-scoped reconciliation context.
Reuse the current runtime, compressor, summary, oracle, and service pipeline.

**Tech Stack:** Dual-target Gleam; startest; Node test runner;
`@fluidframework/tree` 3.1.0 source and published-package oracles; pinned
Floodgate; existing `just` and GitHub Actions gates.

**Spec:** [SharedTree arrays and moves](../specs/2026-09-26-shared-tree-arrays-design.md).
Also read the [approved parent design](../specs/2026-09-21-shared-tree-design.md)
and the [M2 design](../specs/2026-09-24-shared-tree-dynamic-maps-design.md).

## Global Constraints

- Production SharedTree semantics must run in pure Gleam on JavaScript and BEAM.
- Upstream TypeScript packages are development/test dependencies, not a production tree engine.
- Use `@fluidframework/tree` version `3.1.0`.
- Use Fluid Framework commit `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960` (`client_v3.1.0`).
- Use Floodgate commit `0eb493fc46d1bb9baf1151a6ccdde93544e057e7`.
- Keep `minVersionForCollab` at `2.117.0`.
- Keep Message V7, SharedTreeChange V5, ModularChange V5, and Sequence field V3.
- Keep the fixed layout: root alias `root` -> `A`, map `/A/root`, tree `/A/_C`.
- Keep `FieldPath = List(String)` and the existing object/map API signatures.
- Preserve existing DDS behavior and the M1/M2 interoperability cases.
- Reject unsupported semantic formats and operations; do not approximate their meaning.
- Keep `TreeChanged(local)` as the public tree event.
- Existing Watershed document encodings require no backward compatibility or migration.
- Apply ASD-STE100 to Gleam comments and error strings, not to Markdown prose.
- Do not edit apm-managed files, `.code-map/`, or generated website snippets.

---

## 1. Starting point and execution rules

Task 1 execution baseline: `8fef0a7f`.
The M1 completion checklist and M2 final acceptance checklist are closed.
M3 is the next numbered milestone. M4 and selected M7 work are parallel
opportunities, not part of this plan.

The user selected existing string-list paths with array-aware traversal.
Review the companion design before executing this plan. Task 1 has a second
review gate for source evidence; no native sequence implementation precedes
that gate.

At planning time, `apm.lock.yaml` had an unrelated modification. Preserve it.
Do not stage entire directories or use `git add -A` to commit this work.
The commit commands below are execution instructions, not claims that this
planning task created commits.

Work directly on `main` with small tested commits. Do not create an execution
worktree or branch. Use the versions in `mise.toml` and the existing lockfiles.
Do not install dependencies during planning. During execution, restore a
missing dependency after the relevant command reports it, using the existing
lockfile; do not change versions to bypass a missing tool.

Each numbered task ends with a tested deliverable and a commit boundary.
Within a test matrix, take one row through red, implementation, and green
before starting the next row. A full sequence rebaser is not a five-minute
coding step; the rows below divide it into reviewable behavior changes.

### Dependency order

```text
design approval
      |
1 source oracle + contract review
      |
2 array values, schema, read-only forest/content codec
      |
3 counted forest deltas and retained identity
      |
4 sequence marks and editor
      |
5 composition, inversion, move-effect context
      |
6 rebase and dependent-field reprocessing
      |
7 modular integration and authored array edits
      |
8 sequence V3 messages and retained-summary codecs
      |
9 history, kernel, reconnect, and atomicity
      |
10 native facades and command clients
      |
11 mixed-client service and persistence proof
      |
12 supported profile and release closure
```

Tasks 2-3 and the standalone algebra in Tasks 4-6 could use separate owners
after Task 1. Default to the ordered lane above. Do not introduce parallel
edits to `change.gleam`, schema dispatch, codec dispatch, history, or runtimes.
Assign one integration owner if M4 begins in another worktree.

### Existing constraints that the implementation must remove

| Current code | M3 requirement |
| --- | --- |
| `tree/types.gleam:10-27` has string paths and object/map values and edits. | Retain paths and add array values and explicit range operations. |
| `tree/schema.gleam:25-47` supports Required/Optional and Leaf/Object/Map. | Recognize the captured sequence primary field as an array node without accepting arbitrary sequence fields. |
| `tree/forest.gleam:537-559` requires each mark to have count one. | Validate counted ranges and distinguish sequence cardinality from singleton fields. |
| `tree/forest.gleam:808-917` advances and mutates one child at a time. | Apply multi-node detach/attach with correct cursor movement across both passes. |
| `tree/forest.gleam:1151-1185` traverses named singleton fields. | Resolve array indices in node context and retain literal numeric map keys. |
| `tree/change.gleam:2380-2456` wraps each ancestor with child index zero. | Use resolved field/index steps, including nonzero array positions. |
| `tree/change.gleam:2483-2509` drops Generic child indices when building deltas. | Emit skips for actual child indices and reject invalid ordering. |
| `tree/codec/field_batch.gleam:740-895` constructs singleton structural fields before schema classification. | Retain raw field lists until schema-aware classification, including empty arrays. |
| `tree/codec.gleam:693-793` rejects `"Sequence"` changes. | Dispatch to the checked Sequence V3 codec. |
| `interop.mjs` pins profile bytes and validates named report sections. | Regenerate the supported profile and require array-specific artifacts; changing a feature label alone is insufficient. |

Line numbers describe the planning baseline. Locate the named functions again
before editing.

## 2. File map and ownership

### Native implementation

| File | Responsibility |
| --- | --- |
| `src/watershed/tree/types.gleam` | `ArrayValue` and explicit array edits; unchanged `FieldPath`. |
| `src/watershed/tree/schema.gleam` | Sequence cardinality, array schema classification, element validation, fixed stored/view compatibility. |
| `src/watershed/tree/forest.gleam` | Ordered children, path resolution, counted deltas, node identity and detached ranges. |
| `src/watershed/tree/sequence_field.gleam` (new) | Mark types, checked construction, range helpers, editor, pruning, revision replacement, removed roots and delta conversion. |
| `src/watershed/tree/sequence_field/moves.gleam` (new) | Typed move effects, interval queries, dependencies and invalidations shared across fields. |
| `src/watershed/tree/sequence_field/compose.gleam` (new) | Sequential composition and its move-chain handling. |
| `src/watershed/tree/sequence_field/invert.gleam` (new) | Inversion, rollback cell identity and allocation watermarks. |
| `src/watershed/tree/sequence_field/rebase.gleam` (new) | Concurrent reconciliation and child changes following moved nodes. |
| `src/watershed/tree/change.gleam` | Closed Sequence dispatch, common-ancestor merging, generic conversion, move worklist. |
| `src/watershed/tree/codec/field_batch.gleam` | Lossless raw structural fields and typed array content. |
| `src/watershed/tree/codec/sequence_field.gleam` (new) | Sequence V3 wire encoding/decoding, using caller-supplied atom and child codecs. |
| `src/watershed/tree/codec.gleam` | Sequence dispatch and compressor/child callback integration. |
| `src/watershed/tree/codec/summary.gleam`, `tree/summary.gleam` | Forest, retained changes, detached ranges, and summary restoration. |
| `src/watershed/tree/history.gleam`, `tree/runtime.gleam`, `tree_kernel.gleam` | Sequence reconciliation, retained repair, read helpers, and candidate-state atomicity. |
| `src/watershed/runtime_core.gleam`, `runtime.gleam`, `runtime_beam.gleam` | Array reads and existing edit submission on both targets. |
| `src/watershed.gleam`, `src/watershed_beam.gleam` | Five matching array operations. |

The top-level `sequence_field.gleam` contains types and low-level operations;
it does not import its algorithm submodules. `change.gleam` imports those
submodules. The sequence codec must not import its parent `codec.gleam`.
These rules avoid Gleam import cycles without a new plugin framework.

### Oracle, clients, and evidence

Modify the existing files:

```text
tools/shared-tree-oracle/schema.mjs
tools/shared-tree-oracle/source.mjs
tools/shared-tree-oracle/source.test.mjs
tools/shared-tree-oracle/generate.mjs
tools/shared-tree-oracle/generate.test.mjs
tools/shared-tree-oracle/service.mjs
tools/shared-tree-oracle/codec-interop.mjs
tools/shared-tree-oracle/codec-interop.test.mjs
tools/shared-tree-oracle/runtime-interop.mjs
tools/shared-tree-oracle/runtime-interop.test.mjs
tools/shared-tree-oracle/client-interop.mjs
tools/shared-tree-oracle/client-interop.test.mjs
tools/shared-tree-oracle/interop-scenarios.mjs
tools/shared-tree-oracle/interop-scenarios.test.mjs
tools/shared-tree-oracle/summary-interop.mjs
tools/shared-tree-oracle/summary-interop.test.mjs
tools/shared-tree-oracle/creation.mjs
tools/shared-tree-oracle/creation.test.mjs
tools/shared-tree-oracle/interop.mjs
tools/shared-tree-oracle/interop.test.mjs
test/watershed/tree/fixtures.gleam
test/watershed/tree/change_fixture_codec.gleam
test/watershed/tree/codec_export.gleam
test/watershed/tree/document_summary_fixture.gleam
test/watershed/tree/kernel_fixture.gleam
test/watershed/tree/client_protocol.gleam
test/watershed/tree/client_js.gleam
test/watershed/tree/client_beam.gleam
test/watershed/shared_tree_fixture_test.gleam
test/watershed/shared_tree_client_test.gleam
test/watershed/facade_parity_test.gleam
smoke/shared_tree.mjs
```

Create `tools/shared-tree-oracle/upstream-array.spec.ts` and
`upstream-sequence.spec.ts`. Keep upstream source imports in those injected
probes; keep the published-package scenario schema in `schema.mjs`.

Create focused native tests and input-only adapters as named in the tasks.
Do not convert the old object-only fixture runners into array engines.
When adding a sum constructor requires an exhaustive-match update in an
object-only helper returning `Result`, return a typed unsupported-profile
error. For observation helpers returning plain `Json`, add recursive
`json.array` encoding for `ArrayValue` without changing their existing
object/leaf output. Do not add a panic or serialize an array as an object.

Generated committed outputs:

```text
test/fixtures/shared_tree/cases/array-schema-content.json
test/fixtures/shared_tree/cases/array-forest-delta.json
test/fixtures/shared_tree/cases/sequence-field-editor.json
test/fixtures/shared_tree/cases/sequence-compose-invert.json
test/fixtures/shared_tree/cases/sequence-rebase.json
test/fixtures/shared_tree/cases/array-modular-algebra.json
test/fixtures/shared_tree/cases/array-codecs.json
test/fixtures/shared_tree/cases/array-history.json
test/fixtures/shared_tree/cases/array-invalid.json
test/fixtures/shared_tree/manifest.json
test/fixtures/shared_tree/profile.json
```

Only the oracle writes these JSON files. Register native semantic coverage
for a case after its input-only runner passes on both targets.

## 3. Reference sources and required corpus

Use source at the exact commit in Global Constraints. The planning
investigation verified these paths in
`packages/dds/tree/src/feature-libraries/sequence-field/`:

- `types.ts`, `utils.ts`, `markQueue.ts`, `markListFactory.ts`.
- `sequenceFieldEditor.ts`, `sequenceFieldToDelta.ts`.
- `compose.ts`, `invert.ts`, `rebase.ts`, `moveEffectTable.ts`.
- `replaceRevisions.ts`, `prune.ts`, `relevantRemovedRoots.ts`, `filterEdits.ts`.
- `formatV2.ts`, `formatV3.ts`, `sequenceFieldCodecV3.ts`,
  `sequenceFieldCodecs.ts`.
- `sequenceFieldChangeHandler.ts`, `sequenceFieldChangeRebaser.ts`.

Also inspect the modular-schema cross-field manager and edit builder called by
those files, the simple-tree array implementation, and their adjacent tests.
Start with the executable source, not a translation of the upstream folder
layout. The [pinned array merge guide](https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/dds/tree/docs/user-facing/array-merge-semantics.md)
explains gap and item identity. Current online API documentation may describe
a newer release and does not override captured 3.1.0 behavior.

### Corpus contract

Retain the existing fixture envelope: `formatVersion`, `reference`, `id`,
`domain`, `input`, `expected`, and `raw`. Each case must contain nonempty,
ID-matched input scenarios, observations, and source evidence.

| Case ID | Domain | Required observations |
| --- | --- | --- |
| `array-schema-content` | schema | Root/object/map/nested/recursive arrays; compatible and incompatible views; empty arrays; all allowed leaf types; exact schema and field-batch bytes. |
| `array-forest-delta` | forest | Multi-node build/detach/attach, indexed nested edits, cross-field transfer, rename/destroy ranges, refreshers, retained references, invalid overlap/cycle/bounds. |
| `sequence-field-editor` | field | Empty/nonempty insert, removal, same-field move in both directions and inside source range, paired cross-field endpoints, child index greater than zero. |
| `sequence-compose-invert` | field | All reachable mark families, split ranges, insert/remove cancellation, move chains, child changes, rollback and nonrollback inversion, revision replacement and prune. |
| `sequence-rebase` | field | Same-gap insertion, overlapping removals, insert/remove, move/edit, move/remove, competing and overlapping moves, empty-cell order, endpoint invalidation. |
| `array-modular-algebra` | modular | Generic/Sequence conversion, cross-array moves across different parents, common ancestors, nested maps/arrays, parent replacement, complete node/parent/alias tables. |
| `array-codecs` | codec | Sequence V3 bytes, Message V7, multi-element builds, empty content, edit-manager history, detached-field indexes, full summaries and decode-after-encode. |
| `array-history` | history | Pending chains, both acknowledgement orders, remote-between-pending, multiple inner commits, reconnect and repair, minimum-sequence advance, summary-tail replay. |
| `array-invalid` | invalid | Schema, edit, count, revision, endpoint, child, range and summary refusal; atomic native state and no partial readiness. |

Preserve raw bytes. Normalize nondeterministic IDs only with an explicit
mapping in the capture. Observe identity separately from visible value and
event count. A native runner receives `input`, never `expected` or `raw`.

---

### Task 1: Capture and review the pinned array contract

**Files:** Modify the oracle schema, source runner, generator, their tests,
and the oracle README. Create the two source probes and the nine generated
cases listed above.

**Interfaces:**
- Consumes: existing `reference`, injection ownership, `runSource`,
  `validateCapture`, fixture envelope, deterministic compressors, and
  `fixtures.assert_case`.
- Produces: the nine named cases; `input.schemas` in `array-schema-content`
  contains raw schema strings under `rootArray`, `objectArrays`, `mapArrays`,
  `recursiveArrays`, and `incompatibleArrays`.
- Produces: explicit no-op observations with visible state, emitted changes,
  revisions, events, and pending counts. The public source suppresses empty
  insert, empty remove, and empty same-array move completely; native Tasks 7
  and 9 implement this at the author/submission boundary.

- [x] **Step 1: Add a required-case regression before adding captures.**

Extend `generate.test.mjs` using the generator's existing exported
`requiredCases`:

```javascript
test("M3 requires sequence replay evidence", () => {
  assert.equal(new Map(requiredCases).get("sequence-rebase"), "field");
});
```

Run `node --test tools/shared-tree-oracle/generate.test.mjs`.
Expect the new assertion to fail because the array case is absent.

- [x] **Step 2: Define the named M3 oracle schema.**

Keep the M1/M2 schema exports unchanged. Add the following declarations to
`schema.mjs`, with `arrayFactory = new SchemaFactory("org.watershed.shared-tree.m3")`:

```javascript
export class ArrayPoint extends arrayFactory.object("Point", {
  label: arrayFactory.string,
  x: arrayFactory.number,
}) {}

export class Items extends arrayFactory.arrayRecursive("Items", [
  arrayFactory.string, arrayFactory.number,
  arrayFactory.boolean, arrayFactory.null,
  ArrayPoint, () => Items, () => ArrayMap,
]) {}

export class ArrayMap extends arrayFactory.mapRecursive("ArrayMap", [
  arrayFactory.string, ArrayPoint, () => Items, () => ArrayMap,
]) {}

export class Points extends arrayFactory.array("Points", ArrayPoint) {}

export class ArrayRoot extends arrayFactory.object("Root", {
  left: Items,
  right: Items,
  byKey: ArrayMap,
  narrow: Points,
}) {}

export const arrayTreeConfig = new TreeViewConfiguration({ schema: ArrayRoot });
export function initialArrayRoot() {
  return new ArrayRoot({
    left: new Items([]),
    right: new Items([]),
    byKey: new ArrayMap([]),
    narrow: new Points([]),
  });
}
export const arrayRootStore = defineTreeDataStore({
  type: "org.watershed.shared-tree.m3.root",
  config: arrayTreeConfig,
  initializer: initialArrayRoot,
});
```

Exercise construction before capture. If the pinned recursive constructor
requires a different initialization wrapper, change the wrapper, not the
allowed node set. Add separate view configurations for the root-array and
map-root captures.

- [x] **Step 3: Inject and execute the source probes.**

Add these exact owned injection paths to `source.mjs` and its ownership tests:

```text
packages/dds/tree/src/test/watershedArray.spec.ts
packages/dds/tree/src/test/watershedSequence.spec.ts
```

Use the existing array of injections for copying, verification, compilation,
and Mocha selection. Extend the corpus collection to read the new outputs.
Do not patch a tracked upstream file or bypass checkout verification.

The sequence probe must call real editors/rebasers/codecs, including paired
cross-field handlers. The array probe must also author through actual
SharedTree views, which can suppress or normalize an operation before it
reaches a low-level editor.

- [x] **Step 4: Capture the corpus rows in section 3.**

For each row, record the operation arguments, source identities, upstream
intermediate/final observations, complete deltas, and encoded bytes. Include:

```javascript
const orderedExamples = [
  { initial: ["A", "B", "C"], start: 0, end: 1, gap: 3,
    expected: ["B", "C", "A"] },
  { initial: ["A", "B", "C"], start: 0, end: 1, gap: 2,
    expected: ["B", "A", "C"] },
];
for (const example of orderedExamples) {
  const items = new Items(example.initial);
  items.moveRangeToIndex(example.gap, example.start, example.end);
  assert.deepEqual([...items], example.expected);
}
```

Also capture a move whose destination lies strictly inside the source range.
The low-level pinned editor emits split marks in that case; visible equality
does not prove an empty changeset.

- [x] **Step 5: Add strict generator refusal tests.**

Delete one observation, duplicate a scenario ID, replace the source commit,
remove a move endpoint, and corrupt one expected child value in separate
test inputs. Require the matching validator to reject each mutation. Check
that raw and normalized scenario IDs match exactly. Keep the accepted
format inventory in the generated capture, not a hand-edited fixture.

- [x] **Step 6: Generate and check from the pinned source.**

```sh
npm --prefix tools/shared-tree-oracle run source:verify
npm --prefix tools/shared-tree-oracle run generate
npm --prefix tools/shared-tree-oracle run check
npm --prefix tools/shared-tree-oracle test
```

If `source:verify` reports absent dependencies or checkout, use the documented
`npm ci` / `source:prepare` workflow and repeat. A capture without the real
source execution does not pass.

- [x] **Step 7: Review the contract before native implementation.**

Record in this task's execution notes the confirmed schema shape, primary
field key, Sequence V3 variants, field-batch shapes, no-op semantics,
compatible cross-array movement, cycle rejection, and cross-field dependency
rules. Confirm the proposed interfaces in Tasks 2-8 against that evidence.
Revise the plan before proceeding if any interface cannot represent a
captured result. Obtain independent review approval of this gate. The source
correction rounds do not satisfy this gate by themselves.

- [x] **Step 8: Commit the oracle and generated evidence.**

Stage the named source probes, runner/generator/schema changes, tests, README,
and the exact generated case/manifest paths.
Use `git commit -m "test(tree): capture array and sequence contracts"`.

#### Task 1 captured contract

- The corpus now has 38 cases. The 29 M1/M2 fixtures remain byte-for-byte
  unchanged, and the nine M3 cases are not listed as native semantic coverage.
- Stored arrays are object nodes whose `""` primary field has kind
  `"Sequence"`. The source messages carry Sequence V3 inside the pinned
  ModularChange V5 and Message V7 envelopes.
- Hydrated empty insert, empty remove, and empty same-array move produce zero
  commits, events, pending edits, revisions, and messages. The low-level
  editor still emits a zero-count Insert mark but emits empty changes for
  zero-count remove and move.
- Same-array destinations use pre-edit gaps. The captured interior move splits
  the source into `MoveOut(1)`, `MoveIn(3)`, `MoveOut(2)`.
- Compatible cross-array movement preserves hydrated object identity.
  Retained data and identity are recorded independently from visible values.
- Upstream clamps a removal end beyond the array length. Native code must
  reject it as documented and must not fabricate parity evidence for it.
- Existing object/root `tree_set` and `tree_clear` semantics remain separate
  from explicit map mutation APIs; both families later gain contextual
  traversal through array elements.
- Cross-field sequence work must use changeset-scoped, range-aware effects.
  Compose, invert, and rebase receive a normalized field identity so reads,
  including absent-range reads, can invalidate every dependent field.
- The array schema, codec, history, and invalid-input cases now replay only
  JSON-round-tripped inputs through exported source helpers. The compatibility
  case executes the declared `objectArrays` stored and view schemas.
- A separate source process replays every exported M3 domain twice without
  prior revision allocation. Both runs must match the captured result and each
  other. Sequence and modular replay reconstruct their ID compressor and
  revision codec only from serialized input.
- Sequence inputs state the pinned helper contract directly: local IDs come
  from operands, while compose and rebase accept allocator parameters but do
  not call them. They do not expose an allocator watermark or claim an
  allocation mutation.
- Codec inputs contain Message V7 bytes or complete summary trees and the
  required compressor context. Decoded Sequence V3 and modular graph
  observations are outputs, not operands. Modular observations include
  recursive builds, refreshers, destroys, complete IDs, and range content.
- Invalid-message cases run a valid control and malformed payload through the
  actual source decoder with the same restored context. The captured malformed
  mark and revision reach source assertions `0xac2` and `0x88d`.
- History inputs contain ordered local-edit, delivery, acknowledgement,
  reconnect, minimum-sequence, summary-load, tail, and continuation actions.
  Checkpoints preserve pending, trunk, peer, envelope, sequence, compressor,
  and retained-content evidence. Fixture-supplied reconnect identities make
  repeated source replay deterministic. Summary-tail observations come from
  restored source history and detached indexes; its input includes both wire
  envelopes and the continuation creation range used by an independent peer.
- Equal-valued and interior public moves are not no-ops even when visible
  values compare equal: they emit commits and change events. Only empty insert,
  empty remove, and empty same-array move are suppressed by the public wrapper.
- Task 1 source-contract review is complete. Independent review accepted the
  replay context, actual decoder controls, decoded content tables, and native
  signature corrections. The remaining history omission has a regression:
  changing a retained removal count changes the decoded history, with unchanged
  revision metadata and stored forest. Pending, trunk, and peer observations
  include commit changes, with peer bases referencing the shared trunk.
  Fresh-process replay and all 38 source cases pass; native coverage remains
  unclaimed.

### Task 2: Support read-only array schemas, values, paths, and content

**Files:** Modify `types.gleam`, `schema.gleam`, `forest.gleam`,
`codec/field_batch.gleam`, `test/watershed/tree/fixtures.gleam`, and
`shared_tree_fixture_test.gleam`. Create
`test/watershed/tree/array_fixture.gleam`,
`test/watershed/tree/array_schema_fixture.gleam`,
`test/watershed/shared_tree_array_schema_test.gleam`, and
`test/watershed/shared_tree_array_forest_test.gleam`.

**Interfaces:**
- Produces: `ArrayValue(schema_id: String, elements: List(TreeValue))`,
  `schema.Sequence`, and `schema.Array(elements: FieldSchema)`.
- Produces: `schema.array_element_schema(StoredSchema, String) ->
  Result(FieldSchema, TreeError)` and
  `schema.validate_array_elements(StoredSchema, String, List(TreeValue)) ->
  Result(Nil, TreeError)`.
- Produces: `forest.array_get(Forest, FieldPath, Int) ->
  Result(Option(TreeValue), TreeError)`,
  `forest.array_values(Forest, FieldPath) -> Result(List(TreeValue), TreeError)`,
  and `forest.array_type(Forest, FieldPath) -> Result(String, TreeError)`.
- Produces: `forest.FieldStep(field: String, index: Int)` and
  `forest.node_path(Forest, FieldPath) ->
  Result(List(FieldStep), TreeError)` for an attached node, including its
  `rootFieldKey` step.
- Test support: `array_fixture.stored(name: String) -> StoredSchema`,
  `array_fixture.view(name: String) -> ViewSchema`, and
  `array_fixture.view_id() -> StableId`. Read the named raw schemas from
  Task 1; do not copy fixture bytes into a second schema constant.

- [x] **Step 1: Write path and ordered-content regressions.**

Use these assertions in the new forest test, with the usual
`gleam/option`, `startest/expect`, forest, types, and array-fixture imports:

```gleam
pub fn shared_tree_array_forest_reads_ordered_elements_test() {
  let root = types.ArrayValue("org.watershed.shared-tree.m3.Items", [
    types.StringValue("B"),
    types.StringValue("A"),
    types.StringValue("B"),
  ])
  let assert Ok(state) =
    forest.new(array_fixture.view_id(), array_fixture.stored("rootArray"), Some(root))
  forest.read(state, []) |> expect.to_equal(Ok(Some(root)))
  forest.array_get(state, [], 1)
  |> expect.to_equal(Ok(Some(types.StringValue("A"))))
  forest.read(state, ["1"])
  |> expect.to_equal(Ok(Some(types.StringValue("A"))))
  forest.array_get(state, [], 3) |> expect.to_equal(Ok(None))
  forest.read(state, ["01"]) |> expect.to_be_error
  forest.node_path(state, ["1"])
  |> expect.to_equal(Ok([
    forest.FieldStep("rootFieldKey", 0),
    forest.FieldStep("", 1),
  ]))
}
```

Add the same traversal under a map with keys `"0"`, `"01"`, and `""`;
only the hop after reaching an `ArrayValue` interprets an index.

- [x] **Step 2: Run the targeted tests and observe the missing array boundary.**

```sh
gleam test --target erlang -- shared_tree_array_schema shared_tree_array_forest
gleam test --target javascript -- shared_tree_array_schema shared_tree_array_forest
```

The initial failure should name the missing array constructor/read interface,
not an unrelated dependency failure.

- [x] **Step 3: Implement schema-aware arrays and preserve full content lists.**

Add `ArrayValue` before adding array edits. Extend node allocation,
materialization, cycle/ownership checks, import/export, and schema
compatibility for ordered elements. Validate element types without requiring
a nonempty list. Restrict Sequence cardinality to the confirmed array shape.

In `field_batch.gleam`, use a private intermediate node:

```gleam
type RawNode {
  RawNode(
    schema_id: String,
    value: Option(JsonValue),
    fields: List(#(String, List(RawNode))),
  )
}
```

Decode compressed and uncompressed field shapes into this representation.
Classify using stored schema before constructing `TreeValue`: singleton
object/map fields retain their checks, the array primary field retains its
whole list, and an omitted empty primary field becomes an empty array only
for a confirmed array schema. Encode arrays through that primary field.
Keep schema-free decoding's existing behavior for old supported content;
return a located unsupported/invalid error where schema-free classification
cannot represent a multi-node field.

Implement one contextual path walker. Parse an array index by requiring
`int.to_string(parsed) == segment`, nonnegativity, and the safe-integer bound.
Do not apply that parser while visiting an object or map.

- [x] **Step 4: Add schema/content fixture execution and refusal tests.**

```gleam
pub fn shared_tree_array_schema_matches_upstream_test() {
  fixtures.assert_case("array-schema-content", array_schema_fixture.run)
}
```

`array_schema_fixture.run(input: Json) -> Result(Json, String)` must decode
and validate supplied schemas and content, execute the named compatibility
checks, and return the observed arrays in order. Test empty arrays, nested
map/array recursion, nonfinite leaves, invalid types, duplicate schema
declarations, malformed primary fields, and unsafe index strings.

Update exhaustive `TreeValue` matches in test helpers in this commit. Preserve
their old profile contracts; use the common tagged-value codec for new array
observations rather than adding another object-only JSON encoder.

- [x] **Step 5: Verify old and new read/content behavior.**

```sh
gleam test --target erlang -- shared_tree_array shared_tree_map_schema shared_tree_map_forest shared_tree_field_batch shared_tree_schema
gleam test --target javascript -- shared_tree_array shared_tree_map_schema shared_tree_map_forest shared_tree_field_batch shared_tree_schema
```

Expect nonzero execution on both targets and unchanged object/map observations.
Register `array-schema-content` as native-covered only now.

- [x] **Step 6: Commit this read-only deliverable.**

Stage the named files and generated coverage update.
Use `git commit -m "feat(tree): add array schemas and read-only content"`.

### Task 3: Apply counted forest deltas without losing identity

**Files:** Modify `forest.gleam`; extend `shared_tree_array_forest_test.gleam`.
Create `test/watershed/tree/array_forest_fixture.gleam`.

**Interfaces:**
- Consumes: the existing `forest.Mark`, `Build`, `DeltaData`, `NodeRef`,
  detached index, and Task 2 array node representation.
- Preserves: `forest.delta`, `apply_delta`, `locate`, `locate_detached`,
  `read_node`, `is_attached`, and `export_data`.
- Produces: `array_forest_fixture.run(Json) -> Result(Json, String)`.

- [x] **Step 1: Add the counted-delta fixture and identity tests.**

```gleam
pub fn shared_tree_array_forest_counted_delta_matches_upstream_test() {
  fixtures.assert_case("array-forest-delta", array_forest_fixture.run)
}
```

In direct tests, start with three distinct `ArrayPoint`s, retain references to
elements 1 and 2, and apply a delta detaching both under consecutive atoms.
Attach both into a different array in the same delta. Assert that `locate` at
the new paths equals the original references, the source length decreases by
two, and editing a retained child changes the moved node.

- [x] **Step 2: Run both array-forest suites and require failure on count two.**

```sh
gleam test --target erlang -- shared_tree_array_forest
gleam test --target javascript -- shared_tree_array_forest
```

- [x] **Step 3: Implement counted range handling through both delta passes.**

Replace the global count-one rule with positive safe counts; nested child
fields still target one node per child-change mark. Check singleton field
cardinality against schema and completed state, not by prohibiting sequence
range marks.

For each mark, derive cursor movement from its input/output occupancy:

```text
detach pass:
  unchanged occupied range -> advance count
  detach occupied range   -> remove count, do not advance
  attach-only range       -> no input consumption

attach pass:
  attached range          -> insert count, advance count
  unchanged occupied range -> advance count
  detach-only range       -> no output consumption
```

Apply nested changes in the existing detach/pending/attach order. Increment
atom local IDs for each range element, with overflow checks. Validate input
bounds before expanding ranges. Keep the entire operation on candidate
forest state until all phases and schema checks succeed.

- [x] **Step 4: Cover interval overlap, repair, and rollback safety.**

Add direct tests for attach ranges `[id=0,count=2]` and `[id=1,count=2]`;
different start IDs do not make these disjoint. Repeat for detach, rename,
build, and destroy ranges. Check gaps, exhausted atom IDs, missing repair
roots, a destination inside the moved subtree, and nested child marks with
count greater than one.

Test move destinations encountered before their source field in traversal.
Test duplicate-valued elements using reference equality, not labels alone.
On each invalid delta, compare the original `ForestData` and references.

- [x] **Step 5: Run the forest regression boundary and commit.**

```sh
gleam test --target erlang -- shared_tree_array_forest shared_tree_forest shared_tree_map_forest
gleam test --target javascript -- shared_tree_array_forest shared_tree_forest shared_tree_map_forest
```

Register `array-forest-delta` after both targets pass.
Use `git commit -m "feat(tree): preserve identity in counted forest deltas"`.

### Task 4: Model and author checked sequence marks

**Files:** Create `src/watershed/tree/sequence_field.gleam`,
`test/watershed/tree/sequence_field_fixture.gleam`, and
`test/watershed/shared_tree_sequence_field_test.gleam`.

**Interfaces:** Define the shared pure representation here. It must represent
all Task 1 forms; it is not a new wire format.

```gleam
pub type Attach {
  Insert(id: AtomId)
  MoveIn(id: AtomId, final_endpoint: Option(AtomId))
}
pub type Detach {
  Remove(id: AtomId, id_override: Option(AtomId))
  MoveOut(
    id: AtomId,
    final_endpoint: Option(AtomId),
    id_override: Option(AtomId),
  )
}
pub type Effect {
  Noop
  Attach(effect: Attach)
  Detach(effect: Detach)
  AttachAndDetach(attach: Attach, detach: Detach)
  Rename(id_override: AtomId)
}
pub type Mark {
  Mark(
    count: Int,
    cell_id: Option(AtomId),
    effect: Effect,
    child: Option(AtomId),
  )
}
pub opaque type Changeset {
  Changeset(marks: List(Mark))
}
```

An effect's `AtomId.revision` represents its optional revision qualifier;
`cell_id` identifies the targeted empty cell. They are separate identities.
Aliases for `AtomId`, `TreeError`, and `StableId` come from existing modules.

Provide these checked functions:

```text
from_marks(List(Mark)) -> Result(Changeset, TreeError)
to_marks(Changeset) -> List(Mark)
split_mark(Mark, Int) -> Result(#(Mark, Mark), TreeError)
insert(index: Int, count: Int, first_cell: AtomId,
       revision: Option(StableId))
  -> Result(Changeset, TreeError)
remove(index: Int, count: Int, first_id: AtomId)
  -> Result(Changeset, TreeError)
move(source: Int, count: Int, destination_gap: Int,
     detach_id: AtomId, attach_id: AtomId)
  -> Result(Changeset, TreeError)
move_out(index: Int, count: Int, id: AtomId)
  -> Result(Changeset, TreeError)
move_in(index: Int, count: Int, id: AtomId, cell_id: AtomId)
  -> Result(Changeset, TreeError)
build_child_changes(List(#(Int, AtomId))) -> Result(Changeset, TreeError)
```

Also define the low-level delta result and converter in this task, since
the editor and subsequent inversion tests need them:

```gleam
pub type DeltaResult {
  DeltaResult(
    local: Option(forest.FieldDelta),
    global: List(forest.DetachedChange),
    rename: List(forest.Rename),
  )
}
```

`into_delta(change: Changeset, child_delta: fn(AtomId) ->
Result(List(#(String, forest.FieldDelta)), TreeError)) ->
Result(DeltaResult, TreeError)` translates the captured
`sequenceFieldToDelta.ts` behavior. It must not import `change.gleam`.

- [x] **Step 1: Write editor fixture and mark-splitting tests.**

```gleam
pub fn shared_tree_sequence_editor_matches_upstream_test() {
  fixtures.assert_case("sequence-field-editor", sequence_field_fixture.run_editor)
}

pub fn shared_tree_sequence_rejects_zero_count_marks_test() {
  sequence_field.from_marks([
    sequence_field.Mark(0, None, sequence_field.Noop, None),
  ])
  |> expect.to_be_error
}
```

`run_editor(Json) -> Result(Json, String)` decodes normalized input, calls
native editors, and returns normalized marks, allocation ranges, and deltas.
Use the empty mark list for an empty changeset. Cover an editor returning an
empty changeset without permitting a zero-count serialized mark.

- [x] **Step 2: Run the focused suite, then implement one editor at a time.**

```sh
gleam test --target erlang -- shared_tree_sequence_field
gleam test --target javascript -- shared_tree_sequence_field
```

Port the captured `sequenceFieldEditor.ts` behavior. Insert copies
`first_cell.local_id` into the effect ID but keeps `revision` as the separate
effect revision; a restored cell can have a different cell revision. Remove
identifies the removed cells. A move pairs endpoint identities and uses
pre-edit gaps, including split source marks for an interior destination. Child
edits emit a skip to each nonzero index.

- [x] **Step 3: Implement splitting and normalization checks.**

Split cell IDs, effect IDs, detach overrides, and final endpoints by the
same range offset. Do not copy a single child change across a multi-node
range. Merge adjacent marks only when all semantic metadata and identity
ranges permit it. Preserve no-op marks on empty cells when their identity
matters.

Implement delta conversion for the full mark sum, including empty-cell
effects, detached child changes, renames, and nested child callbacks. Compare
the emitted delta with source observations before applying it through
Task 3's forest.

Test every effect through split/rejoin and reject `split <= 0`,
`split >= count`, unsafe IDs, missing required empty-cell identities, and
multi-node child changes. Observe allocation watermarks as well as marks.

- [x] **Step 4: Verify editor evidence and commit.**

Run both focused suites, register `sequence-field-editor`, and use
`git commit -m "feat(tree): add checked sequence marks and editors"`.

### Task 5: Compose and invert sequence changes with move effects

**Files:** Create `sequence_field/moves.gleam`,
`sequence_field/compose.gleam`, and `sequence_field/invert.gleam`.
Extend `sequence_field.gleam`, `sequence_field_fixture.gleam`, and
`shared_tree_sequence_field_test.gleam`.

**Interfaces:**
- `moves.Context` is opaque and changeset-scoped. Its key consists of
  source/destination end, revision, first local ID, and count.
- `moves.Effect` records optional `modify_after`, moved detach effect,
  rebased child, final endpoint, and truncated endpoint information observed
  in Task 1. Keep a range basis when returning an offset query result.
- `moves.new() -> Context`; reads register the requesting field's
  dependency; changed writes invalidate dependent fields. Use the concrete
  key/effect types below, not arbitrary JSON.
- The context records moved-node and moved-key ownership notifications with
  normalized `FieldId` destinations. The modular coordinator consumes those
  notifications after field processing and reprocessing.
- `compose.compose(first, second, state, compose_child, context, moves)` returns
  `Result(#(sequence_field.Changeset, state, moves.Context), TreeError)`.
  `compose_child` has the existing optional-field callback shape:
  `fn(Option(AtomId), Option(AtomId), state) ->
  Result(#(AtomId, state), TreeError)`.
- `invert.invert(change, is_rollback, inverse_revision, state, alias, moves)`
  returns
  `Result(#(sequence_field.Changeset, state, moves.Context), TreeError)`;
  `inverse_revision` is `Option(StableId)`, and `alias` has type
  `fn(AtomId, state) -> Result(#(Int, state), TreeError)`.
- Modular inversion creates one alias state for the changeset, reserves the
  changeset maximum ID for each original revision in source order, and threads
  that state through every field inversion and reprocessing pass. Repeated
  atom and final-endpoint queries must return the same alias.

In `moves.gleam`, define:

```gleam
pub type Side { Source Destination }
pub type Key {
  Key(side: Side, revision: Option(StableId), local_id: Int)
}
pub type FieldId {
  FieldId(parent: Option(AtomId), field: String)
}
pub type Effect {
  Effect(
    modify_after: Option(AtomId),
    moved_effect: Option(sequence_field.Detach),
    rebased_child: Option(AtomId),
    endpoint: Option(AtomId),
    truncated_endpoint: Option(AtomId),
    truncated_endpoint_for_inner: Option(AtomId),
  )
}
pub type Query {
  Query(count: Int, effect: Option(Effect))
}
```

The checked move-table interfaces are:

```text
get(Context, Key, count: Int, dependent: Option(FieldId))
  -> Result(#(Query, Context), TreeError)
set(Context, Key, count: Int, Effect) -> Result(Context, TreeError)
on_move_in(Context, node: AtomId, destination: FieldId)
  -> Result(Context, TreeError)
move_key(Context, key: Key, count: Int, destination: FieldId)
  -> Result(Context, TreeError)
take_invalidated(Context) -> #(List(FieldId), Context)
```

A query returns the first uniform segment within the requested range; callers
continue with the remaining segment. Offset identity fields from the stored
range basis. Invalidate dependencies only when their observed effect changes.
Pass a normalized `FieldId` into compose, invert, and rebase. Register the
requesting field on present and absent range reads; do not evaluate one
endpoint of a cross-field move without its changeset-scoped dependency state.
Rebase records both node-parent and cross-field-key relocation. Compose
normalizes moved node IDs before recording their new parent and rejects
`move_key`, matching the pinned source. Inversion ignores both notifications
and stores an inverted child ID rather than a compose/rebase `Effect` in its
cross-field table.

In `sequence_field.gleam`, define the algebra context without importing
`change.gleam`:

```gleam
pub type AlgebraContext {
  AlgebraContext(
    compare_atoms: fn(AtomId, AtomId) -> Result(Order, TreeError),
    revision_index: fn(StableId) -> Result(Option(Int), TreeError),
    rollback_of: fn(StableId) -> Result(Option(StableId), TreeError),
  )
}
```

Import `Order` from `gleam/order`. `change.gleam` supplies the comparator from
its validated `IdentityOrder`, and the metadata callbacks from its revision
context. The fixture runner supplies the captured equivalents. Keep identity
ordering and revision chronology separate; use the callback that the pinned
algorithm requires at each comparison.

- [x] **Step 1: Add composition/inversion oracle assertions.**

```gleam
pub fn shared_tree_sequence_compose_invert_matches_upstream_test() {
  fixtures.assert_case(
    "sequence-compose-invert",
    sequence_field_fixture.run_compose_invert,
  )
}
```

Add a move-table test in which one field reads an absent destination range,
another writes that range, and `take_invalidated` returns the first field.
A read of the middle of a larger range must offset endpoint IDs from the
stored basis. Add relocation tests that move a child to a different parent,
move a source key during rebase, normalize a moved child alias during compose,
and reject a compose-time key relocation.

- [x] **Step 2: Run the focused suite and implement counted composition.**

Use aligned mark queues. Split at the next input/output range boundary using
Task 4 helpers; do not expand marks into positional JSON edits.

Take these rows through red/green:

| Row | Required result |
| --- | --- |
| Skip with insert/remove | Correct input/output lengths and trailing skip normalization. |
| Insert then remove | Upstream cancellation/retained-cell result, including repair roots. |
| Child then remove | Nested edit remains associated with detached content. |
| Move then child edit | Child callback targets the moved node's endpoint. |
| Move then move | Correct final endpoints and move-chain normalization. |
| Move-in then remove | Required attach-and-detach form. |
| Move-in then move-out | Required rename form and endpoint effects. |
| Partial-overlap ranges | Correct split IDs and effect-table ranges. |

- [x] **Step 3: Implement inversion and revision-sensitive helpers.**

Invert effects, cell identities, overrides, and move endpoints according to
Task 1. Rollback restores the original empty-cell identity; ordinary
inversion uses its captured inverse revision behavior. Preserve the returned
allocation watermark and nested child associations.

Add `replace_revisions`, `prune`, and `relevant_removed_roots` to the shared
sequence module. Each must visit cell IDs, both attach/detach effects, final
endpoints, overrides, and child IDs. Collect every required element of a
removed range, not only its first ID.

- [x] **Step 4: Compare full observations and conservation properties.**

For each valid invertible fixture, apply the original delta then its inverse
to a forest and compare attached values and captured retained identities.
Also compare normalized changesets with upstream: round-trip values alone
cannot expose a lost cell ID. Test nonlexical revision order and an inverse
allocation at the safe-integer boundary.

- [x] **Step 5: Verify and commit.**

Run the focused sequence suite on both targets and the old optional-field
suite. Register `sequence-compose-invert`.
Use `git commit -m "feat(tree): compose and invert sequence changes"`.

### Task 6: Rebase sequence ranges and coordinate moved child changes

**Files:** Create `sequence_field/rebase.gleam`; extend the move context,
sequence helpers, input-only runner, and sequence tests.

**Interfaces:**
- Consumes: Task 4 marks and Task 5 move effects.
- Produces: `rebase.rebase(change, over, state, rebase_child, context, moves)` returning
  `Result(#(sequence_field.Changeset, state, moves.Context), TreeError)`.
  `context` is Task 5's `sequence_field.AlgebraContext`.
- Define `sequence_field.AttachState { Attached DetachedNode }`.
  The child callback is
  `fn(Option(AtomId), Option(AtomId), sequence_field.AttachState, state) ->
  Result(#(Option(AtomId), state), TreeError)`.
- Produces: `sequence_field_fixture.run_rebase(Json) -> Result(Json, String)`.

- [x] **Step 1: Add the upstream rebase case and mutation guard.**

```gleam
pub fn shared_tree_sequence_rebase_matches_upstream_test() {
  fixtures.assert_case("sequence-rebase", sequence_field_fixture.run_rebase)
}
```

Mutate one supplied destination gap and one child callback result in separate
inputs. Assert that the runner's output changes or returns a located error.
This prevents a runner from replaying expected final arrays instead of using
its operation arguments.

- [x] **Step 2: Implement occupied/empty cell alignment.**

Run the sequence suite red before implementation. Handle same-gap inserts,
insert/remove, overlapping removals, and edits on already empty cells first.
Use upstream revision metadata and compressor order for identity comparisons.
Do not sort insertions by UUID or by application labels.

For the three-client empty-array insertion example, capture and check both
intermediate states and the final order. The pinned guide describes later
sequenced insertion groups preceding earlier groups; the source fixture is
the acceptance oracle.

- [x] **Step 3: Implement move-related rebase rows.**

Take one row through red/green at a time:

```text
move vs nested edit
move vs remove, both sequencing orders
two moves of the same node, both orders
partially overlapping moved ranges
move into a gap concurrently receiving an insert
move chain across three arrays
move across different parent objects
move vs removal/replacement of a source or destination ancestor
child edit on a detached node involved in a move chain
```

Query and update source/destination effects in the shared context. Transfer
rebased child changes to the correct endpoint. Reprocess invalidated fields
until no dependency remains unresolved; do not stop after an arbitrary
number of passes. Reject malformed endpoint references rather than returning
an unchanged successful changeset.

- [x] **Step 4: Verify detached-state and child-callback observations.**

Compare the complete normalized rebase result, callback inputs/outputs,
retained roots, move effects, and resulting forest. Include equal-valued
elements whose reference identities differ. Native convergence is an
additional property, not the expected-output source.

- [x] **Step 5: Verify and commit.**

Run both sequence suites, register `sequence-rebase`, and use
`git commit -m "feat(tree): rebase sequence moves and child edits"`.

### Task 7: Integrate sequence algebra and author atomic array edits

**Files:** Modify `types.gleam`, `change.gleam`,
`test/watershed/tree/change_fixture_codec.gleam`, and relevant exhaustive
test helpers. Create
`test/watershed/tree/array_change_fixture.gleam` and
`test/watershed/shared_tree_array_change_test.gleam`.

**Interfaces:**
- Add the three `Edit` constructors exactly as specified in the design.
- Add `SequenceField(sequence_field.Changeset)` to `change.FieldChange`.
- Preserve `change.edit`, `edit_from`, `validate_edit`, `compose`, `invert`,
  `rebase`, `into_delta`, `replace_revisions`, `prune`,
  `relevant_removed_roots`, and `update_refreshers`.
- Consume Task 4's `sequence_field.into_delta` and `DeltaResult` in the
  existing `DeltaParts` path. Collect a child's own global and rename
  results at the modular level as the existing optional branch does.
- Produce `array_change_fixture.run(Json) -> Result(Json, String)`.

- [x] **Step 1: Add modular-array fixture and nonzero-index regressions.**

```gleam
pub fn shared_tree_array_modular_algebra_matches_upstream_test() {
  fixtures.assert_case("array-modular-algebra", array_change_fixture.run)
}
```

Author `SetField(["left", "2", "x"], NumberValue(9.0))` against three points.
Assert that only the third point changes and that the generic ancestor
contains index `2` under `""`. Repeat with an array under map key `"01"` and
with a map entry inside an array element.

- [x] **Step 2: Add every closed-sum dispatch branch.**

Run the change suites red. Add Sequence support to validation, identity
revision discovery, child enumeration, compose/rebase/invert, alias
resolution, revision replacement, pruning, delta conversion, repair-root
enumeration, and refreshers. Update the normalized test changeset codec.

For Generic/Sequence interaction, convert generic indexed children with
`build_child_changes`; keep their actual indices. Test both operand orders.
For pure generic deltas, emit explicit skips between child positions.
Do not retain the current index-dropping mapping.

- [x] **Step 3: Share cross-field effects at the modular operation level.**

Initialize one move context for a complete modular compose, invert, or rebase
operation, not one per field. Track stable field identities through parent
node/field pairs. After processing fields, reprocess invalidated field
results with updated endpoint information. Include nested fields and both
orders of source/destination discovery.

For inversion, initialize one reserved alias context for the complete modular
changeset. Reserve the changeset maximum ID once for each original revision in
source order, then thread the same alias state through every field. Test two
source revisions with equal local IDs and split cross-field endpoints.

Apply move ownership notifications at the modular boundary. Rebase updates
both node-parent and cross-field-key ownership maps. Compose normalizes moved
node IDs through its alias table before updating node-parent ownership and
returns an error for a moved cross-field key. Do not apply a notification
twice when an invalidated field is processed again.

Preserve the existing public `change` API and `IdentityOrder`. Use the move
context as internal state; do not add a production field-kind registry.

- [x] **Step 4: Author inserts and removals from validated destinations.**

Check target kind, index/range, allowed element types, and allocation
capacity before producing a commit. Resolve array ancestry with
`forest.node_path`, build new element ranges, and place sequence marks under
the primary field. Apply Task 1's recorded no-op policy.

Reject `SetField`/`ClearField` targeting a numeric array slot; permit those
operations below the slot on ordinary fields. Preserve whole-array
replacement at an object/map field.

- [x] **Step 5: Author one changeset for a cross-array move.**

Resolve source and destination against the same pre-edit forest. Check
destination compatibility for each moved node, not schema-identifier
equality between the two arrays. Reject a destination inside the moved
subtree and out-of-view references.

For one field, call the same-array editor. For different fields, allocate
paired endpoint ranges and merge both changes through their common ancestor
into one modular graph. If the destination's positional path changes when
the source detaches, retain the originally resolved destination identity.
Do not locate the destination again using its old string path.

- [x] **Step 6: Assert atomicity and old-profile behavior.**

For each invalid range, incompatible element, cycle, stale target, and
exhausted allocation, compare the accepted forest, pending history, next
local ID, and caller-held compressor before/after. Add a valid move between
different named array schemas that accept the moved elements.

```sh
gleam test --target erlang -- shared_tree_array_change shared_tree_change shared_tree_map_change
gleam test --target javascript -- shared_tree_array_change shared_tree_change shared_tree_map_change
```

Register `array-modular-algebra` after both targets pass.
Use `git commit -m "feat(tree): integrate atomic array edits and moves"`.

### Task 8: Encode Sequence V3 messages and retained summaries

**Files:** Create `src/watershed/tree/codec/sequence_field.gleam` and
`test/watershed/tree/array_codec_fixture.gleam`.
Modify `codec.gleam`, `codec/summary.gleam`, `summary.gleam`,
`test/watershed/tree/codec_export.gleam`, the codec/runtime oracle drivers and
their tests. Create `test/watershed/shared_tree_array_codec_test.gleam`.

**Interfaces:**
- Preserve the schema-aware public message/modular/summary codec APIs and
  `codec.DecodeContext` / `EncodeContext`.
- The sequence codec accepts the existing lossless `JsonValue`, an opaque
  caller state, and atom/child decoding callbacks, and returns
  `Result(#(sequence_field.Changeset, state), TreeError)`.
- The encode path accepts a checked sequence changeset and caller-supplied
  atom/child encoding callbacks, and returns `Result(Json, TreeError)`.
  Define these signatures in the module without importing parent codec
  state types; use polymorphic callback state to avoid an import cycle.
- Produce `array_codec_fixture.run(Json) -> Result(Json, String)`.

- [x] **Step 1: Add the codec fixture and unsupported-version tests.**

```gleam
pub fn shared_tree_array_codecs_match_upstream_test() {
  fixtures.assert_case("array-codecs", array_codec_fixture.run)
}
```

Begin with one source-generated insert message containing more than one
element, one cross-array move, and one moved child change. Run both array
codec suites and confirm `"Sequence"` dispatch is the failing boundary.

- [x] **Step 2: Implement the exact V3 wire grammar.**

Use captured `formatV3.ts`/`sequenceFieldCodecV3.ts` behavior for counts,
cell IDs, revisions, endpoints, overrides, rename, attach-and-detach, and
nested child payloads. Convert revisions only through the compressor-aware
callbacks. Preserve child node and parent ownership in the modular tables.

Reject zero/negative/unsafe counts, invalid marks, conflicting effects,
malformed atom tuples, duplicate child ownership, missing referenced nodes,
and unsupported field versions with their JSON location. Follow the pinned
codec's extra-property tolerance; do not impose a new blanket policy.

- [x] **Step 3: Exercise full summary data, not only message round trips.**

Decode and encode retained sequence commits in edit-manager trunk and peer
branches, detached array elements, range indexes, refreshed moved content,
and empty/multi-element forests. Use Task 2's schema-aware field batches for
builds and summary content. Keep full-summary publication and the existing
protocol/container metadata.

Assert that a summary excludes unacknowledged local array edits. Preserve the
snapshot sequence even when publication happens later.

- [x] **Step 4: Prove both codec directions through upstream.**

Extend the existing exporter and `codec-interop.mjs` so actual upstream
decoders consume native array messages and retained-history summaries.
Have the upstream reader author a move or nested edit after loading.
Compare its exact state, not only successful parsing.

```sh
gleam test --target erlang -- shared_tree_array_codec shared_tree_codec shared_tree_field_batch shared_tree_summary
gleam test --target javascript -- shared_tree_array_codec shared_tree_codec shared_tree_field_batch shared_tree_summary
npm --prefix tools/shared-tree-oracle run codec:interop
npm --prefix tools/shared-tree-oracle run runtime:interop
```

- [x] **Step 5: Register coverage and commit.**

Register `array-codecs` only after both native runs and bidirectional
upstream consumption pass.
Use `git commit -m "feat(tree): encode sequence messages and summaries"`.

### Task 9: Preserve array history, reconnect, and failure atomicity

**Files:** Modify `history.gleam`, `tree/runtime.gleam`, `tree_kernel.gleam`,
and the existing runtime core only where a test exposes a required dispatch
or repair change. Create `test/watershed/tree/array_history_fixture.gleam`,
`test/watershed/tree/array_invalid_fixture.gleam`, and
`test/watershed/shared_tree_array_kernel_test.gleam`.

**Interfaces:**
- Add `tree_kernel.array_get(TreeState, FieldPath, Int) ->
  Result(Option(TreeValue), TreeError)` and
  `array_values(TreeState, FieldPath) -> Result(List(TreeValue), TreeError)`.
- Preserve local/remote/acknowledgement and history entry points, including
  `tree_runtime.author_edit` and ordered receive.
- Produce the two input-only runners, each with
  `run(Json) -> Result(Json, String)`.

- [x] **Step 1: Add history and invalid-input oracle cases.**

```gleam
pub fn shared_tree_array_history_matches_upstream_test() {
  fixtures.assert_case("array-history", array_history_fixture.run)
}

pub fn shared_tree_array_invalid_input_is_atomic_test() {
  fixtures.assert_case("array-invalid", array_invalid_fixture.run)
}
```

Run the new kernel suites on both targets before changing history.
Reuse existing pending/peer sequencing drivers; do not write a second
sequencer or pass expected observations into a driver.

- [x] **Step 2: Exercise pending chains and move repair.**

Create at least three local pending commits: insert several nodes, move a
subrange to another array, then edit one moved child. Deliver a remote
insert/remove between pending commits. Cover both acknowledgement orders,
two inner commits in one outer message, and a non-tree sequence gap.

Keep ID allocation messages ahead of dependent operations. Finalize received
creation ranges when sequencing allocation messages, including the author's
delivery, and derive identity order from the receiving compressor. Do not
finalize a local creation range merely because an edit was authored.

- [x] **Step 3: Verify reconnect with original identities and repair content.**

Cover accepted-before-ack, never-submitted, interleaved pending moves, and a
second interruption during catch-up. Compare original and resubmitted
revision/batch IDs. Rebuild every required detached range refresher from
the correct sequenced predecessor, including child edits before and after
the move. Do not substitute current optimistic content.

Advance the collaboration window while peers and pending commits still
reference moved/removed nodes. Retain required history and repair content.
Do not add reclamation heuristics in M3.

- [x] **Step 4: Verify events and full error atomicity.**

For invalid edits compare visible and sequenced state, pending commits,
allocation watermarks, compressor serialization, emitted events, and output
messages. At runtime level, assert no outbound submit occurred.

For valid no-visible-change operations, assert Task 1's event and commit
policy instead of assuming one event per method call. Empty insert, empty
remove, and empty same-array move validate first, then return before accepted
revision allocation, history insertion, event publication, or outbound
submission. An all-suppressed batch changes nothing; a mixed batch preserves
the order of real commits. Do not suppress an operation only because its
visible values compare equal. An acknowledgement must not emit a second local
event. Malformed remote sequence data must stop the affected document through
its existing error path before partial readiness or partial batch state
appears.

- [x] **Step 5: Run the regression boundary and commit.**

```sh
gleam test --target erlang -- shared_tree_array_kernel shared_tree_history shared_tree_kernel shared_tree_runtime shared_tree_map_kernel
gleam test --target javascript -- shared_tree_array_kernel shared_tree_history shared_tree_kernel shared_tree_runtime shared_tree_map_kernel
```

Register `array-history` and `array-invalid`.
Use `git commit -m "feat(tree): reconcile array history and reconnect"`.

### Task 10: Expose both facades and the command-client protocol

**Files:** Modify both public facades, `runtime_core.gleam`,
`runtime.gleam`, `runtime_beam.gleam`, the three command-client files,
`shared_tree_client_test.gleam`, and `facade_parity_test.gleam`.
Create `test/watershed/shared_tree_array_facade_test.gleam`.

**Interfaces:**
- Implement the five public signatures in design section 3 unchanged.
- Runtime core reads:
  `tree_array_get(Core, address: String, FieldPath, Int) ->
  Result(Option(TreeValue), CoreError)` and
  `tree_array_values(Core, address: String, FieldPath) ->
  Result(List(TreeValue), CoreError)`.
  Wrap tree-layer failures with `TreeOperationFailed(address, error)`, as
  the neighboring map reads do. Convert errors to strings only at the
  existing runtime/facade boundary.
- JS runtime wrappers take `(Runtime, address, ...)`.
  BEAM uses equivalent request/reply functions and two read message variants.
  Mutations use the existing `tree_edit` / `TreeEdit` path.
- Protocol additions:
  `ArrayGet(FieldPath, Int)`, `ArrayValues(FieldPath)`,
  `ArrayInsert(FieldPath, Int, List(TreeValue))`,
  `ArrayRemove(FieldPath, Int, Int)`, and
  `ArrayMove(FieldPath, Int, Int, FieldPath, Int)`.

- [x] **Step 1: Add protocol decoding and round-trip tests.**

Use this exact command shape:

```json
{
  "requestId": 7,
  "command": "array-move",
  "sourcePath": ["left"],
  "sourceStart": 1,
  "sourceEnd": 3,
  "destinationPath": ["byKey", "0"],
  "destinationGap": 0
}
```

`array-get` uses `path` and `index`; `array-insert` uses `path`, `index`,
and `values`; `array-remove` uses `path`, `start`, and `end`.
`array-values` needs only `path`. Tagged array values use
`kind`, `schemaId`, and `elements` from the design.

Test missing fields, noninteger numbers, unsafe integers, negative indices,
invalid values, empty arrays, and nested map/array values. Preserve array
order and distinguish a missing element from `NullValue`.

- [x] **Step 2: Implement facade wrappers after tests fail.**

The JavaScript move wrapper is:

```gleam
@target(javascript)
pub fn tree_array_move(
  tree: SharedTree,
  source_path: tree_types.FieldPath,
  source_start: Int,
  source_end: Int,
  destination_path: tree_types.FieldPath,
  destination_gap: Int,
) -> Result(Nil, String) {
  runtime.tree_edit(
    tree.runtime,
    tree.address,
    tree_types.ArrayMove(
      source_path,
      source_start,
      source_end,
      destination_path,
      destination_gap,
    ),
  )
}
```

Implement the BEAM wrapper through `runtime_beam.tree_edit` using its
existing handle field names. Add only the two new read request/reply paths;
do not add separate endpoint messages for a cross-array move.

- [x] **Step 3: Extend both command clients through public APIs.**

Map each command to the respective public facade. Preserve request
correlation, connection observations, `await-synced`, and error reporting.
The upstream adapter must accept the same logical command shape.

Adjust `client_protocol.decode_path` to permit empty object/map keys as
already supported by the tree API. Do not reject keys before node context
is known; the production path walker decides whether a segment is a valid
array index. Retain numeric map keys as strings.

- [x] **Step 4: Prove facade parity and lifecycle behavior.**

Test disconnected/not-ready handles, valid root and nested arrays, array
elements under maps, move compatibility, and both target subscriptions.
Ensure the five public names appear in the existing parity mechanism.
Do not add a special tree API to the P2P CRDT runtime.

```sh
gleam test --target erlang -- shared_tree_array_facade shared_tree_client facade_parity
gleam test --target javascript -- shared_tree_array_facade shared_tree_client facade_parity
npm --prefix tools/shared-tree-oracle test
```

- [x] **Step 5: Commit the public boundary.**

Use `git commit -m "feat(tree): expose array operations on both targets"`.

### Task 11: Prove mixed-client arrays, moves, and summary continuation

**Files:** Modify the oracle service, scenario catalogue, client/summary
drivers, combined coordinator, their tests, and `smoke/shared_tree.mjs`.
Modify `tools/shared-tree-oracle/creation.mjs` and `creation.test.mjs` to
cover an array-bearing schema without changing production creation layout
or adding a new creator.

**Interfaces:**
- Export `arrayServiceStore` from `service.mjs` through the existing
  `createServiceStore(arrayTreeConfig, initialArrayRoot)` mechanism.
- Extend the existing report with `arrayReload` using the same three writer
  and reader IDs as object/map matrices.
- Export `runArrayReloadMatrix` and `validateArrayResults` beside the current
  map matrix functions.
- Keep `requiredScenarioCells`, `generateSchedules`, replay validation, and
  the combined coordinator as the single acceptance path.

- [x] **Step 1: Require the deterministic family catalogue before execution.**

Add the following family IDs:

```javascript
const arrayFamilies = [
  "array-independent-insert",
  "array-same-gap-insert",
  "array-insert-remove",
  "array-overlapping-remove",
  "array-move-child-edit",
  "array-move-delete",
  "array-competing-moves",
  "array-overlapping-moves",
  "array-cross-parent-move",
  "array-ancestor-replace",
  "array-recursive-map-path",
  "array-reconnect-pending",
  "array-summary-tail",
];
```

Use the existing author-pair expansion helpers. Run conflict families in both
release orders and rotate upstream/JavaScript/BEAM roles. Require all three
implementations as authors, not just readers of upstream changes.

Add a test that removes one required array cell from a report and requires
rejection. Derive the exact required cell set from the catalogue; do not
accept a report solely because its total case count is large enough.

- [x] **Step 2: Add public upstream and native array adapters.**

For the upstream adapter, call the actual view methods:

```javascript
destination.moveRangeToIndex(
  command.destinationGap,
  command.sourceStart,
  command.sourceEnd,
  source,
);
```

Resolve both arrays before the call. Convert observations recursively using
the tagged array shape without sorting elements. Canonicalize only
object/map keys. Native adapters send Task 10 commands; neither adapter
computes expected CRDT state for another client.

Capture retained upstream object references before movement and check them
afterwards. Where process-local native references are not exposed through
the facade, combine pure-kernel identity evidence with wire atom
relationships and a later targeted child edit.

- [x] **Step 3: Add seeded arrays without reducing M1/M2 coverage.**

Make default `iterations = 300`. Preserve the existing object/map schedule
prefix and append the array schedules. Select the profile in the collection
generator, then generate one schedule from explicit `(seed, index, profile)`:

```javascript
const legacyCount = 2 * Math.floor(iterations / 3);
const profile = index < legacyCount
  ? (index % 2 === 0 ? "object" : "map")
  : "array";
const schedule = generateSchedule({ seed, index, profile });
```

Leave `scheduleSubSeed(seed, index)`, author rotation, old action builders,
and indices unchanged for the legacy prefix. Compare the new default's first
200 schedules byte-for-byte with the prior 200-schedule generator in a
regression test. Add 100 array schedules with range lengths greater than one,
interior destinations, nested edits, and reconnect. For custom iteration
counts, append any remainder to the array allocation and report each count.

For the optional deep gate, use 7,500 schedules to retain 2,500 per profile.
Update generator accounting, CLI defaults, `justfile`, report validation, and
replay format tests together. Replay regenerates from its stored
`(seed, index, profile)`, not from `index + 1` or a reconstructed iteration
total. Validate profile membership before dispatch. An array replay artifact
must retain both paths, all indices, release order, intermediate checkpoints,
and the first difference path.

- [x] **Step 4: Extend refusal scenarios without rejecting supported arrays.**

The old excluded-array schema is no longer a valid refusal case. Replace
its semantic role with a genuinely unsupported sequence placement or
malformed sequence payload. Keep schema evolution, handles, and unknown
version refusals. Test malformed range counts, missing endpoints, bad child
ownership, invalid schema/content, and corrupt retained summaries.
Assert typed error and stopped document state, not just process exit.

- [x] **Step 5: Implement the nine-cell array persistence matrix.**

Use each of upstream, JavaScript, and BEAM as writer and reader. Each written
state contains empty/nested arrays, a moved object, a deleted range with
retained history, duplicate-valued objects, a map under an array, and an
array under numeric/empty map keys.

For each cell:

```text
publish and acknowledge a summary at sequence S
author a later array tail at sequence T > S
close the writer when the scenario requires independence
open a fresh reader at the selected summary and replay the tail
compare the exact tagged tree and required retained metadata
author a new range move and a nested child edit from that reader
open an independent peer and verify exact resulting values and order
record the selected summary, S, publication point, T, and continuation
```

Corrupt the continuation value in a unit test and require validation failure.
Checking element presence or array length alone is insufficient.

Also run an array-bearing fixed-layout native creation from each native
creator, followed by fresh upstream/JS/BEAM readers and continued edits.
Retain the existing six object-profile cells and add six array-profile cells.
Key creation results by profile, creator, and reader so one profile cannot
stand in for another. Reuse the current creation harness and strict
creator/reader validation; require twelve cells in its combined report.

- [x] **Step 6: Run the complete real-service gate.**

Before the combined service run, update the supported/excluded capability
declarations and regenerate `test/fixtures/shared_tree/profile.json` through
the existing preflight capture path. Update digest expectations from those
bytes. M3 acceptance must reject a profile that still declares arrays
unsupported.

```sh
npm --prefix tools/shared-tree-oracle test
just shared-tree-interop
just shared-tree-create-interop
```

Use the existing isolated pinned Floodgate launcher. Require the nine
`arrayReload` cells, all named array deterministic cells, preserved M1/M2
matrices, 300 seeded schedules with 100 per profile, and all three targets.
Require all twelve creation cells in its separate report. No skip, empty
corpus, or absent service may produce a success report.

Reopen and validate current-run artifacts before publishing `report.json`.
Include array artifacts in upload discovery and current-run identity checks.
Cleanup failure remains a failed run.

- [x] **Step 7: Commit the evidence path.**

Stage only the named oracle/smoke/recipe changes and regenerated fixtures.
Use `git commit -m "test(tree): prove mixed-client array interoperability"`.

### Task 12: Publish the M3 profile and close its release gates

**Files:** Modify `README.md`, `tools/shared-tree-oracle/README.md`,
`justfile`, `.github/workflows/shared-tree.yml`,
`.github/workflows/shared-tree-interop.yml`, the parent roadmap, and this
plan's execution/acceptance record.
Update the existing `examples/shared_tree_cli/README.md` if it describes a
schema restriction that this release removes; do not turn M3 into a new
application project.

**Interfaces:**
- Consumes: complete array implementation, nine source cases, current-run
  service evidence, and the existing native/manual-interoperability workflows.
- Produces: an accurate supported profile and a release record tied to the
  implemented revision, profile digest, local artifacts, and hosted run.

- [x] **Step 1: Regenerate and publish the supported profile.**

In `service.mjs`, add positive array schema/range edit/move capabilities and
remove only their old exclusions. Preserve M1/M2 capabilities and deferred
M4-M8 features. Regenerate profile bytes using the existing preflight capture
path and update the coordinator's digest after regeneration.

Document:

```text
Fluid 3.1.0 and the fixed service/container profile
named and recursive arrays with ordered values
half-open removal/move ranges and pre-edit destination gaps
contextual decimal path indices; literal object/map keys
same-tree compatible cross-array movement
identity, reconnect, and full-summary guarantees
the five matching native APIs
the remaining unsupported features
```

Retain source-scope STE comments and normal Markdown prose. Keep website
copy outside this backend milestone.

- [x] **Step 2: Keep the workflow split and require current M3 evidence.**

The fast native workflow remains automatic on pull requests and `main`.
The source/service interoperability workflow remains manually dispatched.
Do not turn it into an automatic expensive job without a separate decision.

Update the service step name to M1/M2/M3, its test expectations, and the
artifact validator coverage. Preserve the creation gate and evidence upload
on success or failure.

- [x] **Step 3: Run the release commands from the final integrated tree.**

```sh
just shared-tree-oracle-check
just shared-tree-test
just shared-tree-interop
just shared-tree-create-interop
just test
just build
just lint
```

Record exact revision, commands, exit statuses, test counts, profile digest,
and artifact paths. Expected service output includes all deterministic
families, object/map/array nine-cell reload matrices, 300/300 schedules with
100 per profile, and zero skipped/divergent results.

Do not waive a failure because an old memory describes a historical baseline.
If a failure appears unrelated, reproduce it on the recorded unchanged
baseline in an isolated worktree and report the evidence. M3 release remains
open until the required gate passes or the user approves an explicit change
to its acceptance criteria.

- [x] **Step 4: Audit production boundaries and the final diff.**

```sh
rg -n '@fluidframework|fluid-framework|shared-tree-oracle|\.reference/FluidFramework' src watershed_lustre
git --no-pager diff --check
git --no-pager status --short
```

Production code must not import the TypeScript oracle or the existing
sequence DDS as its array engine. Inspect any documentation-only matches.
Confirm generated corpus changes have generator sources, no generated
website/cache file is staged, and unrelated `apm.lock.yaml` changes remain
untouched.

- [ ] **Step 5: Obtain hosted evidence for the integrated revision.**

After the approved integration/push workflow, run the existing manual
interoperability workflow for that revision and inspect its run:

```sh
branch=$(git branch --show-current)
head=$(git rev-parse HEAD)
started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
test -n "$branch"
gh workflow run shared-tree-interop.yml --ref "$branch"
run_id=$(gh run list --workflow shared-tree-interop.yml \
  --branch "$branch" --commit "$head" --event workflow_dispatch --limit 5 \
  --json databaseId,createdAt \
  --jq ".[] | select(.createdAt >= \"$started\") | .databaseId" | head -1)
test -n "$run_id"
gh run watch "$run_id" --exit-status
gh run view "$run_id" --json headSha,conclusion,jobs,url
```

If dispatch has not appeared in the run list yet, repeat the lookup, not
the dispatch. Record the branch/run ID and verify `headSha`. Require the
automatic native check and manual interoperability/creation gates to pass.
Download and inspect the current-run array artifacts; a green older M2 run
is not M3 evidence. Do not push or merge merely to satisfy this planning
document without the normal integration approval.

- [x] **Step 6: Commit profile documentation and release evidence.**

Use `git commit -m "docs(tree): publish array and move interoperability"`.
Mark the acceptance checklist below only after its corresponding evidence
exists. Update the parent roadmap to link this completed milestone; do not
mark M4 or the remaining M7 work complete.

#### Task 12 local execution record

The local implementation and service evidence end at
`df67063`. The profile and workflow
publication is `c9d4249d16c446b63dd4e4f679ae38c04b688112`. Four later fixes close
the service harness defects found by the release gates:

- `243401c8f8eb9b7a2dcf6c458859dd76fec5d8b2` classifies M2 and M3 adapter
  nodes by stored schema instead of constructor identity.
- `9d4d61bf20500d9097dd6fe3a62e6f491d21db65` fixes array schedule evidence,
  continuation expectations, and related service sequencing.
- `b9dc01b5a75e45435077369f2d3aced1ca86a3c1` makes each malformed Sequence V3
  refusal reach its intended invariant.
- `df67063` adds family-aware retained identity checks, reader-specific
  persisted reload evidence, deterministic creation sequencing, action-failure
  replay validation, and operation-level seeded array conflicts.

Hosted evidence remains pending an approved integration and push.

The existing preflight/profile path regenerated
`/tmp/watershed-m3-profile/profile.json`. It matched
`test/fixtures/shared_tree/profile.json` byte-for-byte. The SHA-256 digest is
`d0cc4a5e3fd47dc942cbaeb56604160fb75f5ba18c704b356b89d22e65747112`.
The other preflight artifacts are
`/tmp/watershed-m3-profile/result.json` and
`/tmp/watershed-m3-profile/capture.json`.

The first preflight attempt failed because the ignored upstream checkout held
a stale injected `watershedCodecs.spec.ts`. Removing that single generated
injection and rerunning `source:prepare` restored the pinned checkout; source
verification then confirmed Fluid commit
`c3c5bf0ecd313362e83fe8a02b7d39e7e0736960` and all packages at 3.1.0. The
second preflight passed every required operation and produced the profile
match above.

| Command | Exit/result | Counts and evidence |
| --- | --- | --- |
| `just shared-tree-oracle-check` | 0 | All 38 committed source cases regenerated and matched. |
| `just shared-tree-test` | 0 | 660 Erlang and 649 JavaScript tests passed; storage, bootstrap, and creation smokes passed. |
| `npm --prefix tools/shared-tree-oracle test` | 0 | 264 passed, zero failed or skipped; includes the final M3 report, artifact, adapter, continuation, action-failure replay, retained-identity, and distinct Sequence-refusal validators. |
| `just shared-tree-interop` | 0 | Run `4eebef1e-9404-4e9b-8b53-4590e982f8f7`; report at `tools/shared-tree-oracle/.output/interop/4eebef1e-9404-4e9b-8b53-4590e982f8f7/report.json`. The real-service run completed 279 deterministic cells (75 object, 72 map, 132 array), 12 reconnect results, 34 refusal results, nine object/map/array reload cells each, and 300/300 schedules with 100 per profile. Corpus results were 644 Erlang and 633 JavaScript. The report references 654 artifacts and records zero skips or divergences. |
| `just shared-tree-create-interop` | 0 | Run `7f337b33-9417-4740-805e-7cacfbc4e672`; report at `tools/shared-tree-oracle/.output/creation/7f337b33-9417-4740-805e-7cacfbc4e672/report.json`. All twelve object/array creator-reader cells loaded the initial summary, continued editing, reloaded summary plus tail, and produced zero skips or divergences. |
| `just test` | 0 | Main package: 2,214 Erlang and 2,480 JavaScript tests. The other package, website, compile-fail, smoke, and browser suites passed. |
| `just build` | 0 | Erlang, JavaScript, and serial bundle builds passed. |
| `just lint` | 0 | The root formatter now checks `src` and `test` directly, then Trellis checks all 26 auto-discovered non-root members. This avoids scanning the ignored Fluid reference checkout while preserving all repository Gleam sources. All 27 checks passed. |

The automatic/native and manual/service workflow split is unchanged. Both
workflows now name M1/M2/M3 acceptance explicitly, and the manual workflow runs
the oracle/report/artifact validator suite before source and service work. The
manual workflow still preserves interop and creation output on success or
failure.

The production-boundary search found no Fluid SDK, oracle, or pinned-checkout
reference under `src` or `watershed_lustre`. `actionlint` passed both workflow
files. `git diff --check` passed, generated website/cache files are not staged,
and the final worktree is clean after each commit.

---

## 4. Acceptance checklist and requirement map

| Requirement | Implementing tasks | Required evidence |
| --- | --- | --- |
| Array schema, leaves, nested maps/arrays and recursion | 1, 2 | `array-schema-content`, schema-aware content round trips. |
| Unchanged string paths and numeric map keys | 2, 7, 10 | Nonzero-index and map-key regressions on both targets. |
| Counted forest deltas and retained identity | 3 | `array-forest-delta`, reference and interval-overlap assertions. |
| Sequence marks/editor, including interior destinations | 4 | `sequence-field-editor`, split-ID and watermark checks. |
| Composition, inversion, rollback and move chains | 5 | `sequence-compose-invert`, complete normalized observations. |
| Concurrent move/edit/delete semantics | 6, 7, 9 | `sequence-rebase`, modular and history cases. |
| Cross-array move in one atomic commit | 7, 9 | Paired endpoints, common ancestors, no partial state/output. |
| Generic/Sequence conversion and indexed child deltas | 7 | `array-modular-algebra`, both operand orders and index 2. |
| Message/content/summary compatibility | 2, 8 | `array-codecs`, actual upstream consumption in both directions. |
| Pending state, reconnect and allocation ordering | 9, 11 | `array-history`, accepted-before-ack and retained-repair evidence. |
| Invalid local/remote data handling | 1, 7-11 | `array-invalid`, no allocation/event/output changes or partial readiness. |
| Matching JavaScript/BEAM facade/client behavior | 10 | Parity tests and native authored service cases. |
| Fresh summary loading and continued editing | 11 | Nine array writer/reader cells, exact-value fresh-peer continuation. |
| Native creation stays compatible with array schemas | 11 | Both creators and three fresh reader implementations. |
| No M1/M2 or other DDS regression | 2-12 | Retained old cases, 100 old schedules per profile, full gates. |
| Accurate scope and permanent evidence | 12 | Regenerated profile, documentation, local and hosted release record. |

- [x] The proposed M3 design and Task 1 source contract received review.
- [x] All nine required source cases have native semantic runners on both targets.
- [x] Array values preserve order and distinguish equal-valued element identities.
- [x] Existing object/map paths and APIs retain their behavior.
- [x] Moves preserve nodes and descendants across compatible arrays.
- [x] Sequence composition, inversion, rebase, repair, and codecs match upstream.
- [x] Invalid operations leave state, allocation, events, and output unchanged.
- [x] Pending chains and reconnect preserve revision/batch identity and content.
- [x] All object/map/array summary cells load and continue editing.
- [x] All three client implementations author real-service array operations.
- [x] The default run preserves 100 object and 100 map schedules and adds 100 array schedules.
- [x] Native creation supports the declared array schema profile.
- [x] No required target, source, corpus, service, or persistence result is skipped.
- [ ] Full repository gates and the required hosted gates pass for the integrated revision.
- [x] Documentation names the exact supported profile and remaining exclusions.

## 5. Stop conditions

Stop and revise the design or contract rather than reducing these cases if:

- The pinned source needs a different public range/path rule or wire profile.
- A mark form reachable from the supported edits cannot fit the chosen types.
- Cross-field effects require coordination that the modular worklist omits.
- A port matches visible arrays but loses moved/detached identity or repair data.
- The native encoder round-trips locally but upstream rejects it.
- A service/client dependency prevents a required matrix cell from running.
- Another milestone changes shared schema, codec, history, or runtime
  interfaces without an agreed integration contract.

The planning deliverable adds no native implementation and claims no M3
runtime or service results.
