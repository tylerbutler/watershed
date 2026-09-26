# SharedTree Dynamic Maps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add upstream-compatible Fluid 3.1.0 dynamic map nodes to Watershed's
native SharedTree implementation on JavaScript and BEAM.

**Architecture:** Represent each map entry as the existing upstream-compatible
optional field under an arbitrary field key. Extend the current schema, forest,
change, codec, history, kernel, facade, and interoperability paths without
adding a second map engine or a general field-kind plugin system.

**Tech Stack:** Gleam on Erlang and JavaScript; startest and gleeunit; Node test
runner; pinned `@fluidframework/tree` 3.1.0 source oracle; the existing
Floodgate interoperability service.

**Spec:** [SharedTree dynamic maps](../specs/2026-09-24-shared-tree-dynamic-maps-design.md)

## Global Constraints

- M1 Task 16 and every M1 completion item must pass before M2 release closure.
- Production SharedTree semantics must run in pure Gleam on JavaScript and BEAM.
- Upstream TypeScript packages remain development and test dependencies.
- Use `@fluidframework/tree` version `3.1.0`.
- Use Fluid Framework commit
  `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960`
  (`client_v3.1.0`).
- Keep the M1 container, service, runtime, compressor, Message V7,
  ModularChange V5, and full-summary profiles unless the oracle disproves an
  assumed encoding.
- Support named maps at the root, in object fields, and under map keys.
- Support recursive maps whose values can be M1 leaves, fixed objects, or
  supported map nodes.
- Return map keys and entries in `watershed/canonical_json.compare` order.
- Keep `TreeChanged(local)` as the only public tree event.
- Do not add arrays, moves, map-wide clear, Fluid-handle leaves, schema
  evolution, transactions, undo/redo, branching, incremental summaries,
  Lustre bindings, or disk-backed pending-state recovery.
- Reject unsupported semantics. Do not approximate upstream behavior.
- Apply ASD-STE100 to Gleam comments and error strings. Use normal prose in
  Markdown and JavaScript.
- Do not edit apm-managed files, generated
  `website/src/generated/snippets.json`, or `.code-map/`.
- Do not add co-author trailers to commits.

---

## 1. Entry gate and dependency order

The original entry gate required M1 Task 16 to supply these recipes before
Tasks 2 through 9:

```sh
rtk proxy just shared-tree-oracle-check
rtk proxy just shared-tree-test
rtk proxy just shared-tree-interop
rtk proxy just test
rtk proxy just build
rtk proxy just lint
```

At the time this plan was written, `shared-tree-test`,
`shared-tree-interop`, and `.github/workflows/shared-tree.yml` were still part
of open M1 Task 16. M2 implementation later proceeded while the M1 release
record remained open. M2 release closure waited for the merged local gates and
hosted Task 16 evidence.

Execute M2 in this order:

```text
1 oracle contract --------+
                           |
M1 release gate -----------+
                           |
                           v
                    2 schema/value
                           |
                           v
                       3 forest
                           |
                           v
                     4 map changes
                           |
                           v
                  5 codecs + summaries
                           |
                           v
                  6 kernel + facades
                           |
                           v
                  7 command clients
                           |
                           v
                8 mixed-client interop
                           |
                           v
                  9 permanent gates
```

Keep Tasks 2 through 9 ordered. Task 3 consumes the map types and schema API
from Task 2, so parallel branches would only create avoidable merge work.

## 2. File map

### Oracle and generated evidence

| Path | Responsibility |
| --- | --- |
| `tools/shared-tree-oracle/schema.mjs` | Export the M1 schema unchanged and add the named M2 map schema, initializer, view configuration, and datastore factory. |
| `tools/shared-tree-oracle/upstream-map.spec.ts` | Capture map schema, forest, field algebra, modular changes, history, message, and summary observations from pinned source. |
| `tools/shared-tree-oracle/source.mjs` | Inject and run the map source probe in the pinned checkout. |
| `tools/shared-tree-oracle/generate.mjs` | Validate and publish required map corpus cases. |
| `tools/shared-tree-oracle/interop-scenarios.mjs` | Define deterministic map schedules and upstream map commands. |
| `tools/shared-tree-oracle/client-interop.mjs` | Run map schedules through upstream, JS, and BEAM clients. |
| `tools/shared-tree-oracle/summary-interop.mjs` | Add map states to the cross-writer summary matrix. |
| `test/fixtures/shared_tree/manifest.json` | Generated manifest entries and native coverage declarations. Do not edit by hand. |
| `test/fixtures/shared_tree/cases/*.json` | Generated map fixtures. Do not edit by hand. |

### Native tree implementation

| Path | Responsibility |
| --- | --- |
| `src/watershed/tree/types.gleam` | Add `MapValue`, `MapSet`, and `MapDelete`. |
| `src/watershed/tree/schema.gleam` | Decode, compare, and validate map-node schema and map content. |
| `src/watershed/tree/forest.gleam` | Store map nodes, traverse arbitrary keys, and return canonical entries. |
| `src/watershed/tree/change.gleam` | Convert explicit map edits into existing per-key `OptionalField` changes. |
| `src/watershed/tree/codec.gleam` | Decode and encode map values in message and summary content where required by fixtures. |
| `src/watershed/tree/codec/summary.gleam` | Decode and encode map forest chunks and schema data where this module owns the format. |
| `src/watershed/tree/summary.gleam` | Preserve map values and detached map content in full summaries. |
| `src/watershed/tree_kernel.gleam` | Add pure map reads and retain the current edit lifecycle. |
| `src/watershed/runtime_core.gleam` | Expose checked map reads through the document core. |
| `src/watershed/runtime.gleam` | Expose JavaScript runtime map reads and reuse `tree_edit` for map edits. |
| `src/watershed/runtime_beam.gleam` | Expose BEAM runtime map reads and reuse `TreeEdit` for map edits. |
| `src/watershed.gleam` | Add JavaScript public map operations. |
| `src/watershed_beam.gleam` | Add BEAM public map operations. |

### Native tests and clients

| Path | Responsibility |
| --- | --- |
| `test/watershed/shared_tree_map_schema_test.gleam` | Map schema and value validation. |
| `test/watershed/shared_tree_map_forest_test.gleam` | Map storage, traversal, ordering, and detached content. |
| `test/watershed/shared_tree_map_change_test.gleam` | Authored map changes and algebra fixtures. |
| `test/watershed/shared_tree_map_codec_test.gleam` | Message, content, and summary fixture parity. |
| `test/watershed/shared_tree_map_kernel_test.gleam` | Local, remote, conflict, history, and atomicity behavior. |
| `test/watershed/shared_tree_map_facade_test.gleam` | JavaScript and BEAM facade parity through shared helpers. |
| `test/watershed/shared_tree_client_test.gleam` | JSON command and map-value protocol coverage. |
| `test/watershed/tree/fixtures.gleam` | Decode and encode `MapValue` in generated fixtures. |
| `test/watershed/tree/client_protocol.gleam` | Add map commands and canonical result encoders. |
| `test/watershed/tree/client_js.gleam` | Execute map commands through the JavaScript facade. |
| `test/watershed/tree/client_beam.gleam` | Execute map commands through the BEAM facade. |

### Release surfaces

| Path | Responsibility |
| --- | --- |
| `README.md` | State the supported dynamic-map profile and exclusions. |
| `tools/shared-tree-oracle/README.md` | Document map fixtures, commands, and evidence. |
| `justfile` | Keep the existing SharedTree recipes and make them include M2 cases. |
| `.github/workflows/shared-tree.yml` | Run the same M2-aware required commands without skips. |

---

### Task 1: Capture the upstream dynamic-map contract

**Files:**
- Modify: `tools/shared-tree-oracle/schema.mjs`
- Create: `tools/shared-tree-oracle/upstream-map.spec.ts`
- Modify: `tools/shared-tree-oracle/source.mjs`
- Modify: `tools/shared-tree-oracle/generate.mjs`
- Modify: `tools/shared-tree-oracle/generate.test.mjs`
- Generated: `test/fixtures/shared_tree/manifest.json`
- Generated: `test/fixtures/shared_tree/cases/map-schema-content.json`
- Generated: `test/fixtures/shared_tree/cases/map-field-algebra.json`
- Generated: `test/fixtures/shared_tree/cases/map-history-codecs.json`

**Interfaces:**
- Consumes: the pinned source checkout and fixture envelope used by the M1
  `schema-validation`, `forest-delta`, `field-compose-invert-rebase`,
  `modular-nested-algebra`, `history-reconciliation`, and `tree-codecs` cases.
- Produces: three immutable map cases with reference commit, package version,
  format versions, raw upstream bytes, normalized inputs, and expected
  observations.

- [ ] **Step 1: Add the M2 schema to the public oracle schema module**

Keep every existing M1 export unchanged. Add named map classes and a root that
contains one map:

```javascript
const mapFactory = new SchemaFactory("org.watershed.shared-tree.m2");

export class MapPoint extends mapFactory.object("Point", {
  x: mapFactory.number,
  y: mapFactory.number,
}) {}

export class DynamicMap extends mapFactory.mapRecursive("DynamicMap", [
  mapFactory.string,
  mapFactory.number,
  mapFactory.boolean,
  mapFactory.null,
  MapPoint,
  () => DynamicMap,
]) {}

export class MapRoot extends mapFactory.object("Root", {
  items: DynamicMap,
}) {}

export const mapTreeConfig = new TreeViewConfiguration({ schema: MapRoot });

export function initialMapRoot() {
  return new MapRoot({ items: new DynamicMap([]) });
}

export const mapRootStore = defineTreeDataStore({
  type: "org.watershed.shared-tree.m2.root",
  config: mapTreeConfig,
  initializer: initialMapRoot,
});
```

Compile this declaration against Fluid 3.1.0. If `mapRecursive` requires the
recursive constructor data wrapper documented by its type declaration, use that
exact wrapper and keep the allowed type set unchanged.

- [ ] **Step 2: Write the source-level map probe**

Create `upstream-map.spec.ts` beside the existing source probes. Use the same
deterministic compressor, revision, fixture writer, and raw encoder helpers.
Generate these case IDs:

```typescript
const requiredMapCases = [
  "map-schema-content",
  "map-field-algebra",
  "map-history-codecs",
] as const;
```

`map-schema-content` must record:

- Named map schema-v2 bytes.
- Recursive map schema-v2 bytes.
- Root-map and object-contained-map schemas.
- Empty and populated cursor or chunk data.
- Keys `""`, `"2"`, `"10"`, `"01"`, `"__proto__"`, `"é"`, and `"水"`.
- Leaf, fixed-object, and nested-map values.
- Upstream `keys()` and `entries()` results as observations only.

`map-field-algebra` must record intermediate and final results for:

```typescript
[
  "set-absent",
  "replace-present",
  "delete-present",
  "delete-absent",
  "different-keys",
  "same-key-set-set-left-last",
  "same-key-set-set-right-last",
  "same-key-set-delete",
  "same-key-delete-set",
  "nested-edit-vs-replace",
  "nested-edit-vs-delete",
  "nested-map-independent",
  "nested-map-conflict",
]
```

For each conflict case, capture compose, invert, and both rebase directions.
Record field kind identifiers and raw field keys. Assert that no sequence-field
kind appears.

`map-history-codecs` must record:

- Message V7 bytes for set, replacement, and delete.
- ModularChange V5 bytes for map and nested-map edits.
- Pending-local and sequenced history.
- Detached content and refreshers after replacement and deletion.
- Reconnect resubmission bytes.
- Full summary bytes and a fresh upstream reload followed by another map edit.

- [ ] **Step 3: Register the probe with the pinned source runner**

Add one injection and include the compiled test in the corpus run:

```javascript
const mapSource = join(directory, "upstream-map.spec.ts");
export const mapInjectedTestPath =
  "packages/dds/tree/src/test/watershedMap.spec.ts";

const injections = new Map([
  [mapInjectedTestPath, mapSource],
]);
```

Preserve the existing injection entries. Add
`lib/test/watershedMap.spec.js` to the Mocha arguments when `corpus` is true.

- [ ] **Step 4: Make generator validation fail before fixtures exist**

Add the three IDs to the required case table and validate exact scenario IDs,
reference identity, format versions, nonempty raw evidence, and intermediate
observations. Add a generator unit test that removes one map scenario and
expects validation to reject it:

```javascript
const broken = structuredClone(validMapCase);
broken.input.scenarios.pop();
assert.throws(() => validateMapFieldCase(broken), /scenario/i);
```

- [ ] **Step 5: Run the oracle tests and confirm the new requirement fails**

Run:

```sh
npm --prefix tools/shared-tree-oracle test
npm --prefix tools/shared-tree-oracle run check
```

Expected: the unit tests pass, and `check` fails because the required map cases
have not been generated.

- [ ] **Step 6: Generate and inspect the pinned map corpus**

Run:

```sh
npm --prefix tools/shared-tree-oracle run source:prepare
npm --prefix tools/shared-tree-oracle run generate
```

Inspect all three generated files. Confirm that:

- Map schema uses the recorded schema-v2 map form.
- Each arbitrary key is represented by the recorded stored field schema.
- Changes use only field kinds supported or explicitly added by this plan.
- Delete-absent behavior is explicit.
- Nested edit versus replacement and deletion records detached identity.
- Message and summary versions match the M1 profile.

- [ ] **Step 7: Verify deterministic regeneration**

Run:

```sh
npm --prefix tools/shared-tree-oracle run check
git --no-pager diff --exit-code -- test/fixtures/shared_tree
```

Expected: both commands exit zero after generation.

- [ ] **Step 8: Commit the oracle contract**

```sh
git add tools/shared-tree-oracle/schema.mjs \
  tools/shared-tree-oracle/upstream-map.spec.ts \
  tools/shared-tree-oracle/source.mjs \
  tools/shared-tree-oracle/generate.mjs \
  tools/shared-tree-oracle/generate.test.mjs \
  test/fixtures/shared_tree/manifest.json \
  test/fixtures/shared_tree/cases/map-schema-content.json \
  test/fixtures/shared_tree/cases/map-field-algebra.json \
  test/fixtures/shared_tree/cases/map-history-codecs.json
git commit -m "test(tree): capture dynamic map contract"
```

---

### Task 2: Add map values and stored schema

**Files:**
- Modify: `src/watershed/tree/types.gleam`
- Modify: `src/watershed/tree/schema.gleam`
- Create: `test/watershed/shared_tree_map_schema_test.gleam`
- Modify: `test/watershed/tree/fixtures.gleam`
- Test: `test/watershed/shared_tree_fixture_test.gleam`

**Interfaces:**
- Consumes: `map-schema-content` from Task 1.
- Produces:

```gleam
pub type TreeValue {
  StringValue(String)
  NumberValue(Float)
  BooleanValue(Bool)
  NullValue
  ObjectValue(schema_id: String, fields: List(#(String, TreeValue)))
  MapValue(schema_id: String, entries: List(#(String, TreeValue)))
}

pub type NodeSchema {
  Leaf(kind: LeafKind)
  Object(fields: List(#(String, FieldSchema)))
  Map(entries: FieldSchema)
}

pub fn map_entry_schema(
  schema: StoredSchema,
  map_type: String,
) -> Result(FieldSchema, TreeError)
```

- [ ] **Step 1: Write failing schema and value tests**

Add tests for the exact schema bytes in `map-schema-content`:

```gleam
pub fn shared_tree_map_schema_decodes_named_and_recursive_maps_test() {
  let assert Ok(stored) = schema.stored_from_string(map_schema)
  schema.validate_root(stored, map_root()) |> expect.to_equal(Ok(Nil))
}

pub fn shared_tree_map_schema_rejects_duplicate_entries_test() {
  let assert Ok(stored) = schema.stored_from_string(map_schema)
  schema.validate_root(
    stored,
    MapValue(map_type, [
      #("same", StringValue("first")),
      #("same", StringValue("second")),
    ]),
  )
  |> expect.to_be_error
}

pub fn shared_tree_map_schema_compares_entry_views_test() {
  compatible(map_schema, changed_map_value_types)
  |> expect.to_be_error
}
```

Also test a recursive map containing another `MapValue`, an object value, every
M1 leaf kind, an empty key, and the Unicode keys from Task 1.

- [ ] **Step 2: Run the focused tests and confirm they fail to compile**

Run:

```sh
gleam test --target erlang -- shared_tree_map_schema
gleam test --target javascript -- shared_tree_map_schema
```

Expected: both targets fail because `MapValue`, `Map`, and
`map_entry_schema` do not exist.

- [ ] **Step 3: Add `MapValue` and fixture JSON support**

Extend the test fixture protocol with:

```json
{
  "kind": "map",
  "schemaId": "org.watershed.shared-tree.m2.DynamicMap",
  "entries": [
    ["key", {"kind": "string", "value": "value"}]
  ]
}
```

Decode entries as two-element arrays, reject duplicate keys, permit empty map
keys, and encode entries in canonical key order.

- [ ] **Step 4: Decode and validate map-node schema**

In `decode_node`, accept the exact `kind.map` form captured by Task 1. Add
`Map(entries)` and make `check_references` validate its allowed types.
Implement `map_entry_schema` with these errors:

```gleam
Error(InvalidEdit([], "node schema is not a map: " <> map_type))
Error(InvalidEdit([], "unknown map schema: " <> map_type))
```

Use a caller-supplied path when adapting these errors in forest and change code.

- [ ] **Step 5: Validate map values and view compatibility**

For `Map(entries)` with `MapValue(identifier, values)`:

- Confirm the identifiers match.
- Reject duplicate keys before validating values.
- Validate every value as `Some(value)` against the common entry field.
- Permit recursive references without walking the schema graph.
- Compare stored and view map entry schemas through `compare_field`.

Reject `MapValue` against leaf or object schema and reject `ObjectValue` against
map schema.

- [ ] **Step 6: Run focused and existing schema tests**

Run:

```sh
gleam test --target erlang -- shared_tree_map_schema shared_tree_schema shared_tree_fixture
gleam test --target javascript -- shared_tree_map_schema shared_tree_schema shared_tree_fixture
gleam format --check src test
```

Expected: all selected tests pass on both targets.

- [ ] **Step 7: Commit map schema support**

```sh
git add src/watershed/tree/types.gleam \
  src/watershed/tree/schema.gleam \
  test/watershed/shared_tree_map_schema_test.gleam \
  test/watershed/tree/fixtures.gleam \
  test/watershed/shared_tree_fixture_test.gleam
git commit -m "feat(tree): add dynamic map schemas"
```

---

### Task 3: Store and traverse map nodes in the forest

**Files:**
- Modify: `src/watershed/tree/forest.gleam`
- Create: `test/watershed/shared_tree_map_forest_test.gleam`
- Test: `test/watershed/shared_tree_forest_fixture_test.gleam`

**Interfaces:**
- Consumes: `MapValue`, `NodeSchema.Map`, and `schema.map_entry_schema` from
  Task 2.
- Produces:

```gleam
pub fn map_get(
  state: Forest,
  path: FieldPath,
  key: String,
) -> Result(Option(TreeValue), TreeError)

pub fn map_entries(
  state: Forest,
  path: FieldPath,
) -> Result(List(#(String, TreeValue)), TreeError)

pub fn map_type(
  state: Forest,
  path: FieldPath,
) -> Result(String, TreeError)
```

- [ ] **Step 1: Write failing allocation and materialization tests**

Construct this value through the Task 1 schema:

```gleam
MapValue(map_type, [
  #("__proto__", StringValue("safe")),
  #("水", ObjectValue(point_type, [
    #("x", NumberValue(1.0)),
    #("y", NumberValue(2.0)),
  ])),
  #("nested", MapValue(map_type, [
    #("answer", NumberValue(42.0)),
  ])),
])
```

Assert:

- `new` and `export_data` preserve the value.
- `read(state, ["水", "x"])` returns `1.0` for a root map.
- `read(state, ["nested", "answer"])` returns `42.0`.
- `map_entries(state, [])` returns canonical key order.
- Calling `map_entries` on an object or leaf returns `InvalidEdit`.

- [ ] **Step 2: Write failing delta and detached-content tests**

Use `forest.delta` to detach, attach, rename, and destroy map entries. Cover a
nested object edit applied after its map entry was detached. Compare against
the `map-schema-content` and `map-field-algebra` forest observations.

- [ ] **Step 3: Run the focused tests and confirm failure**

Run:

```sh
gleam test --target erlang -- shared_tree_map_forest
gleam test --target javascript -- shared_tree_map_forest
```

Expected: both targets fail because the forest has no map node representation.

- [ ] **Step 4: Add the internal map node**

Extend the private node sum:

```gleam
type Node {
  Leaf(value: TreeValue)
  Object(schema_id: String, fields: List(#(String, List(Int))))
  Map(schema_id: String, entries: List(#(String, List(Int))))
}
```

Use the same child-list representation as object fields. Map entries have zero
or one child because their stored field schema is optional.

- [ ] **Step 5: Make common field access schema-aware**

Update `children` and `set_children`:

- Objects call `schema.field_schema`.
- Maps call `schema.map_entry_schema`.
- Leaves reject child access.
- Empty map fields are removed from the stored entry list.
- Nonempty map fields are inserted or replaced without using a JavaScript
  object.

Update `walk` so each path segment can cross either a declared object field or
an arbitrary map key.

- [ ] **Step 6: Allocate and materialize map values**

Allocate each map entry after schema validation. Reject duplicate keys before
allocating child nodes. Materialize entries with
`canonical_json.compare`; apply the same ordering in `map_entries`.

Implement `map_type` by resolving the path and matching the internal node.
Implement `map_get` as a checked map-node lookup followed by the common field
materializer.

- [ ] **Step 7: Run forest and schema regression tests**

Run:

```sh
gleam test --target erlang -- shared_tree_map_forest shared_tree_forest shared_tree_map_schema
gleam test --target javascript -- shared_tree_map_forest shared_tree_forest shared_tree_map_schema
gleam format --check src test
```

Expected: all selected tests pass on both targets.

- [ ] **Step 8: Commit forest support**

```sh
git add src/watershed/tree/forest.gleam \
  test/watershed/shared_tree_map_forest_test.gleam \
  test/watershed/shared_tree_forest_fixture_test.gleam
git commit -m "feat(tree): store dynamic map nodes"
```

---

### Task 4: Author and rebase per-key map changes

**Files:**
- Modify: `src/watershed/tree/types.gleam`
- Modify: `src/watershed/tree/change.gleam`
- Create: `test/watershed/shared_tree_map_change_test.gleam`
- Modify: `test/watershed/shared_tree_change_fixture_test.gleam`
- Modify: `test/watershed/shared_tree_history_fixture_test.gleam`

**Interfaces:**
- Consumes: map-aware schema and forest functions from Tasks 2 and 3.
- Produces:

```gleam
pub type Edit {
  SetField(path: FieldPath, value: TreeValue)
  ClearField(path: FieldPath)
  MapSet(path: FieldPath, key: String, value: TreeValue)
  MapDelete(path: FieldPath, key: String)
}
```

All existing `change.edit`, `validate_edit`, `compose`, `invert`, `rebase`,
`replace_revisions`, `prune`, `into_delta`, `relevant_removed_roots`, and
`update_refreshers` signatures remain unchanged.

- [ ] **Step 1: Write failing authored-change tests**

Add tests that inspect `change.to_data`:

```gleam
let assert Ok(map_set) =
  change.edit(
    stored,
    forest,
    revision,
    MapSet(["items"], "key", StringValue("value")),
    order,
  )

let assert [#("items", GenericField([#(0, map_node)]))] =
  change.to_data(map_set).fields
let assert Ok(NodeChange(map_fields)) =
  change.to_data(map_set).nodes
  |> list.key_find(map_node)
let assert Ok(OptionalField(_)) = list.key_find(map_fields, "key")
```

Also assert that `MapDelete(["items"], "missing")` matches the exact no-op or
commit shape captured by Task 1.

- [ ] **Step 2: Write failing conflict and history fixture tests**

Run `map-field-algebra` and `map-history-codecs` through native fixture
adapters. Cover:

- Independent keys.
- Same-key set/set in both orders.
- Set/delete and delete/set in both orders.
- Nested object edit versus replacement and deletion.
- Nested map edit versus replacement and deletion.
- Compose, invert, and rebase outputs.
- Relevant removed roots and refreshers.

- [ ] **Step 3: Run the tests and confirm failure**

Run:

```sh
gleam test --target erlang -- shared_tree_map_change shared_tree_change_fixture shared_tree_history_fixture
gleam test --target javascript -- shared_tree_map_change shared_tree_change_fixture shared_tree_history_fixture
```

Expected: both targets fail because `MapSet` and `MapDelete` are not handled.

- [ ] **Step 4: Resolve explicit map edits to optional fields**

Add one helper:

```gleam
fn map_edit_destination(
  schema: StoredSchema,
  forest: forest.Forest,
  path: FieldPath,
  key: String,
  value: Option(TreeValue),
) -> Result(#(FieldSchema, FieldPath, String, Bool), TreeError)
```

It must:

1. Reject an empty or detached target path only when the target is not an
   attached map. A root map uses `[]`.
2. Call `forest.map_type` to prove the target node kind.
3. Call `schema.map_entry_schema` and validate `value`.
4. Read the current entry with `forest.map_get`.
5. Return `#(entry_schema, path, key, current == None)`.

Route `MapSet` and `MapDelete` through `authored_field`. The resulting
`FieldChange` must be `OptionalField`; reject any oracle result that uses a
different field kind until the design is reviewed.

- [ ] **Step 5: Keep existing modular algebra unchanged**

Do not add a map-specific compose or rebase function. Extend exhaustive
`Edit` matches and any value traversal only. The existing field-map functions
must process arbitrary map keys because they already key changes by `String`.

If a fixture fails inside optional-field algebra, first reduce it to an M1
optional-field case. Change `optional_field.gleam` only when the pinned fixture
proves an M1 bug rather than a map-specific expectation.

- [ ] **Step 6: Prove invalid edits do not allocate**

Add tests for wrong node kind, disallowed value type, detached map reference,
and unknown schema. Call `validate_edit`, then `apply_local` with a fixed
identity order. Assert the original snapshot, pending history, and next local
identifier remain unchanged.

- [ ] **Step 7: Run algebra and history regression tests**

Run:

```sh
gleam test --target erlang -- shared_tree_map_change shared_tree_change shared_tree_history
gleam test --target javascript -- shared_tree_map_change shared_tree_change shared_tree_history
gleam format --check src test
```

Expected: map fixtures and all existing object-field algebra tests pass.

- [ ] **Step 8: Commit map change support**

```sh
git add src/watershed/tree/types.gleam \
  src/watershed/tree/change.gleam \
  test/watershed/shared_tree_map_change_test.gleam \
  test/watershed/shared_tree_change_fixture_test.gleam \
  test/watershed/shared_tree_history_fixture_test.gleam
git commit -m "feat(tree): rebase dynamic map edits"
```

---

### Task 5: Decode and write map messages and summaries

**Files:**
- Modify: `src/watershed/tree/codec.gleam`
- Modify: `src/watershed/tree/codec/summary.gleam`
- Modify: `src/watershed/tree/summary.gleam`
- Create: `test/watershed/shared_tree_map_codec_test.gleam`
- Modify: `test/watershed/shared_tree_codec_fixture_test.gleam`
- Modify: `test/watershed/shared_tree_summary_codec_test.gleam`
- Modify: `test/watershed/shared_tree_document_summary_test.gleam`

**Interfaces:**
- Consumes: `map-history-codecs`, `MapValue`, `NodeSchema.Map`, and
  `OptionalField` map changes.
- Produces: existing message and summary APIs that accept map schema, content,
  pending history, detached values, and refreshers.

- [ ] **Step 1: Write failing message codec fixture tests**

Decode each map Message V7 fixture, compare its `ChangeData` with the expected
map key and `OptionalField`, encode it again, and compare canonical JSON with
the upstream bytes. Include set, replacement, delete, nested object edit, and
nested map edit.

- [ ] **Step 2: Write failing summary fixture tests**

For upstream-written map summaries, assert:

- Stored schema decodes to `NodeSchema.Map`.
- Empty and populated maps restore as `MapValue`.
- Detached replaced and deleted map values remain available to history.
- A decoded snapshot re-encodes to the expected full-summary structure.

For native-written summaries, run the existing summary export adapter and
assert the artifact contains the map schema, forest, detached index, edit
manager, compressor, and enclosing document metadata.

- [ ] **Step 3: Run focused codec tests and confirm failure**

Run:

```sh
gleam test --target erlang -- shared_tree_map_codec shared_tree_codec_fixture shared_tree_summary_codec
gleam test --target javascript -- shared_tree_map_codec shared_tree_codec_fixture shared_tree_summary_codec
```

Expected: schema or forest content decoding rejects map nodes.

- [ ] **Step 4: Extend content codecs**

Add the exact map content branch captured in Task 1 to the module that owns
forest chunk conversion. Preserve:

- Map schema identifier.
- Raw key strings.
- Empty versus present optional fields.
- Child order required by the wire format.
- Detached IDs and latest relevant revisions.

Do not sort raw encoded fields if the upstream format preserves a required
order. Sort only the public or normalized `MapValue` representation.

- [ ] **Step 5: Reuse optional-field message encoding**

If Task 1 confirms `fieldKind: "Optional"`, keep
`decode_field_entries` and `encode_field_map` unchanged except for map value
support in builds and refreshers. Add an assertion test that rejects a
map-specific invented field kind:

```gleam
decode_message(message_with_field_kind("Map"), context)
|> expect.to_equal(
  Error(UnsupportedFeature(
    "message.changeset.changes[0].fieldKind",
    "field kind Map",
  )),
)
```

Use the actual fixture location string if nesting differs.

- [ ] **Step 6: Run codec interoperability**

Run:

```sh
gleam test --target erlang -- shared_tree_map_codec shared_tree_codec shared_tree_summary
gleam test --target javascript -- shared_tree_map_codec shared_tree_codec shared_tree_summary
npm --prefix tools/shared-tree-oracle run codec:interop
```

Expected: native decoders consume upstream map bytes, and upstream consumes
native map messages and summary payloads.

- [ ] **Step 7: Commit map codec support**

```sh
git add src/watershed/tree/codec.gleam \
  src/watershed/tree/codec/summary.gleam \
  src/watershed/tree/summary.gleam \
  test/watershed/shared_tree_map_codec_test.gleam \
  test/watershed/shared_tree_codec_fixture_test.gleam \
  test/watershed/shared_tree_summary_codec_test.gleam \
  test/watershed/shared_tree_document_summary_test.gleam
git commit -m "feat(tree): encode dynamic map state"
```

---

### Task 6: Expose map operations through the kernel and facades

**Status:** Complete on 2026-09-25 in `bc0e269`, `505658d`, and `f7f8f6a`.
Both native facades expose all five map operations through the existing tree
edit lifecycle. The kernel tests cover visible reads and local edits; runtime
and facade tests cover allocation atomicity, delivery, acknowledgement,
resubmission, canonical ordering, and retained reads during reconnect.
The SharedTree gate passes on both targets. Tasks 7–9 remain open.

**Files:**
- Modify: `src/watershed/tree_kernel.gleam`
- Modify: `src/watershed/runtime_core.gleam`
- Modify: `src/watershed/runtime.gleam`
- Modify: `src/watershed/runtime_beam.gleam`
- Modify: `src/watershed.gleam`
- Modify: `src/watershed_beam.gleam`
- Create: `test/watershed/shared_tree_map_kernel_test.gleam`
- Create: `test/watershed/shared_tree_map_facade_test.gleam`
- Modify: `test/watershed/facade_parity_test.gleam`
- Modify: `test/watershed/shared_tree_runtime_test.gleam`
- Modify: `test/watershed/tree/runtime_fixture.gleam`

**Interfaces:**
- Consumes: `MapSet`, `MapDelete`, `forest.map_get`, and
  `forest.map_entries`.
- Produces:

```gleam
pub fn map_get(
  state: TreeState,
  path: FieldPath,
  key: String,
) -> Result(Option(TreeValue), TreeError)

pub fn map_entries(
  state: TreeState,
  path: FieldPath,
) -> Result(List(#(String, TreeValue)), TreeError)
```

Both public facade modules produce the five functions specified in the design:
`tree_map_get`, `tree_map_set`, `tree_map_delete`, `tree_map_keys`, and
`tree_map_entries`.

- [x] **Step 1: Write failing pure-kernel tests**

Cover local set, replacement, delete, repeated delete, nested object edit,
nested map edit, remote receive, acknowledgement, duplicate delivery, and
reconnect resubmission. Assert `TreeChanged(True)` for visible local changes,
`TreeChanged(False)` for visible remote changes, and no event for a captured
upstream no-op.

- [x] **Step 2: Write the allocation atomicity test**

Capture before and after:

```gleam
let assert Ok(before_snapshot) = tree_kernel.snapshot(state)
let before_history = tree_kernel.history_view(state)
let assert Error(InvalidEdit(_, _)) =
  tree_kernel.apply_local(
    state,
    revision,
    order,
    MapSet(["items"], "bad", disallowed_value),
  )
tree_kernel.snapshot(state) |> expect.to_equal(Ok(before_snapshot))
tree_kernel.history_view(state) |> expect.to_equal(before_history)
```

Repeat for `MapSet` against an object path and `MapDelete` against a leaf path.

- [x] **Step 3: Write failing facade parity tests**

Assert that `watershed.gleam` and `watershed_beam.gleam` export the same map
functions with the same argument and result types. Exercise keys
`""`, `"__proto__"`, `"2"`, `"10"`, `"01"`, `"é"`, and `"水"` and expect
canonical ordering.

- [x] **Step 4: Add pure kernel reads**

Delegate `tree_kernel.map_get` and `tree_kernel.map_entries` to the visible
forest. Implement keys as:

```gleam
tree_kernel.map_entries(state, path)
|> result.map(fn(entries) { list.map(entries, fn(entry) { entry.0 }) })
```

Keep map writes on the existing `validate_edit` and `apply_local` path.

- [x] **Step 5: Add runtime-core reads**

Add:

```gleam
pub fn tree_map_get(
  core: Core,
  address: String,
  path: tree_types.FieldPath,
  key: String,
) -> Result(Option(tree_types.TreeValue), CoreError)

pub fn tree_map_entries(
  core: Core,
  address: String,
  path: tree_types.FieldPath,
) -> Result(List(#(String, tree_types.TreeValue)), CoreError)
```

Use the existing `tree_channel` lookup and wrap errors in
`TreeOperationFailed(address, error)`.

- [x] **Step 6: Add target runtime reads**

For JavaScript, add synchronous read wrappers beside `tree_read`. For BEAM, add
`TreeMapGet` and `TreeMapEntries` actor messages and wrappers beside `TreeRead`.
Writes continue through `tree_edit` with `MapSet` and `MapDelete`.

- [x] **Step 7: Add public facade operations**

Implement matching functions in both facade modules:

```gleam
pub fn tree_map_set(tree, path, key, value) {
  runtime.tree_edit(tree.runtime, tree.address, tree_types.MapSet(path, key, value))
}

pub fn tree_map_delete(tree, path, key) {
  runtime.tree_edit(tree.runtime, tree.address, tree_types.MapDelete(path, key))
}
```

Map getters and entry readers call the new runtime read functions. Derive keys
from entries so both targets use one ordering implementation.

- [x] **Step 8: Run kernel, runtime, and facade tests**

Run:

```sh
gleam test --target erlang -- shared_tree_map_kernel shared_tree_map_facade facade_parity
gleam test --target javascript -- shared_tree_map_kernel shared_tree_map_facade facade_parity
gleam format --check src test
```

Expected: all selected tests pass on both targets.

- [x] **Step 9: Commit the public map API**

```sh
git add src/watershed/tree_kernel.gleam \
  src/watershed/runtime_core.gleam \
  src/watershed/runtime.gleam \
  src/watershed/runtime_beam.gleam \
  src/watershed.gleam \
  src/watershed_beam.gleam \
  test/watershed/shared_tree_map_kernel_test.gleam \
  test/watershed/shared_tree_map_facade_test.gleam \
  test/watershed/facade_parity_test.gleam
git commit -m "feat(tree): expose dynamic map operations"
```

---

### Task 7: Extend the dual-target command clients

**Status:** Complete on 2026-09-25 in `7c2a6bd`. The shared protocol accepts
all five direct map commands and recursive map values, rejects duplicate map
entries, and emits canonical key and entry results. Both target clients route
through the public Task 6 facades. The Node driver exposes correlated map
helpers with empty-key, Unicode-key, reverse-reply, and facade-error coverage.
Focused tests pass on both Gleam targets, and all 200 oracle Node tests pass.
The repository-wide suite reached the package matrix, but Hex API rate limits
blocked dependency resolution for eight unchanged example packages. Tasks 8–9
remain open.

**Files:**
- Modify: `test/watershed/tree/client_protocol.gleam`
- Modify: `test/watershed/tree/client_js.gleam`
- Modify: `test/watershed/tree/client_beam.gleam`
- Modify: `test/watershed/shared_tree_client_test.gleam`
- Modify: `tools/shared-tree-oracle/client-driver.mjs`
- Modify: `tools/shared-tree-oracle/client-driver.test.mjs`

**Interfaces:**
- Consumes: the public facade functions from Task 6.
- Produces these JSON commands:

```json
{"requestId":1,"command":"map-get","path":["items"],"key":"a"}
{"requestId":2,"command":"map-set","path":["items"],"key":"a","value":{"kind":"string","value":"x"}}
{"requestId":3,"command":"map-delete","path":["items"],"key":"a"}
{"requestId":4,"command":"map-keys","path":["items"]}
{"requestId":5,"command":"map-entries","path":["items"]}
```

- [x] **Step 1: Write failing protocol tests**

Extend `Command`:

```gleam
MapGet(FieldPath, String)
MapSet(FieldPath, String, TreeValue)
MapDelete(FieldPath, String)
MapKeys(FieldPath)
MapEntries(FieldPath)
```

Tests must accept empty map keys, reject missing or non-string keys, reject
duplicate map-value entries, and round-trip nested `MapValue`.

- [x] **Step 2: Add canonical result encoders**

Add:

```gleam
pub fn encode_map_entries(
  entries: List(#(String, TreeValue)),
) -> Json
```

Encode an array of `[key, value]` pairs. Sort with
`canonical_json.compare` before encoding. Encode keys as a JSON string array.

- [x] **Step 3: Run protocol tests and confirm failure**

Run:

```sh
gleam test --target erlang -- shared_tree_client
gleam test --target javascript -- shared_tree_client
```

Expected: both targets fail on missing map command and `MapValue` branches.

- [x] **Step 4: Implement protocol decoding**

Keep `decode_path` unchanged for map paths. Add `decode_key` that accepts every
string, including `""`:

```gleam
fn decode_key(data: Dynamic) -> Result(String, ProtocolError) {
  required(data, "key", decode.string)
}
```

Add a `"map"` value branch with `schemaId` and `entries`. Reject duplicate keys
without rejecting empty keys.

- [x] **Step 5: Execute map commands on both targets**

In `client_js.gleam` and `client_beam.gleam`, map commands call the matching
facade function. Encode `map-get` with `encode_read`, map keys as a JSON array,
and map entries with `encode_map_entries`.

- [x] **Step 6: Extend the Node client driver**

Add methods:

```javascript
mapGet(path, key)
mapSet(path, key, value)
mapDelete(path, key)
mapKeys(path)
mapEntries(path)
```

Each method sends one command, checks the correlated response ID, and returns
the decoded result. Add driver tests for empty and Unicode keys and facade
errors.

- [x] **Step 7: Run client tests on both targets**

Run:

```sh
gleam test --target erlang -- shared_tree_client
gleam test --target javascript -- shared_tree_client
npm --prefix tools/shared-tree-oracle test
gleam format --check test
```

Expected: protocol, driver, and both command-client implementations pass.

- [x] **Step 8: Commit command-client support**

```sh
git add test/watershed/tree/client_protocol.gleam \
  test/watershed/tree/client_js.gleam \
  test/watershed/tree/client_beam.gleam \
  test/watershed/shared_tree_client_test.gleam \
  tools/shared-tree-oracle/client-driver.mjs \
  tools/shared-tree-oracle/client-interop.test.mjs
git commit -m "test(tree): drive dynamic map clients"
```

---

### Task 8: Prove mixed-client map interoperability

**Status:** Complete in `c6b22e8`, `735e27f`, `29455e8`, `e321866`, `af0c0d0`,
and `09eeb48`. The real-service gate covers 72 M2 deterministic cells, 100
seeded map schedules in the 200-schedule run, replayable failures, and all nine
map summary writer-reader cells.

**Files:**
- Modify: `tools/shared-tree-oracle/interop-scenarios.mjs`
- Modify: `tools/shared-tree-oracle/client-interop.mjs`
- Modify: `tools/shared-tree-oracle/interop.mjs`
- Modify: `tools/shared-tree-oracle/interop.test.mjs`
- Modify: `tools/shared-tree-oracle/summary-interop.mjs`
- Modify: `tools/shared-tree-oracle/summary-interop.test.mjs`
- Modify: `smoke/shared_tree.mjs`
- Modify: `test/fixtures/shared_tree/manifest.json`

**Interfaces:**
- Consumes: map-capable upstream adapter and native command clients.
- Produces: deterministic schedules, failure artifacts, replay support, and
  measured claims for behavior, service, reconnect, and summaries.

- [x] **Step 1: Add deterministic map schedules**

Add named schedules:

```javascript
[
  "map-independent-keys",
  "map-same-key-set-set",
  "map-set-delete",
  "map-nested-object-replace",
  "map-nested-delete-edit",
  "map-recursive-conflict",
  "map-reconnect-pending",
  "map-summary-tail",
]
```

Each schedule records the author, operation, release order, expected
intermediate checkpoint, expected final map, and expected event locality.
Generate both sequencing orders for every same-key conflict.

- [x] **Step 2: Extend the upstream adapter**

Resolve the M2 map tree with `mapTreeConfig`. Implement the same five logical
commands as the native clients. Convert upstream nodes to the fixture
`MapValue` representation and sort observed entries only in the normalized
comparison output.

- [x] **Step 3: Add failure replay coverage**

Include map commands and map checkpoints in `failure.json`. Add a unit test
that mutates one nested map value and proves replay validation reports the
exact action index and path.

- [x] **Step 4: Run focused in-memory mixed-client tests**

Run:

```sh
npm --prefix tools/shared-tree-oracle test
node smoke/shared_tree.mjs \
  --profile test/fixtures/shared_tree/profile.json \
  --iterations 20 \
  --seed 42
```

Expected: every deterministic schedule and seeded run completes with matching
upstream, JavaScript, and BEAM checkpoints.

- [x] **Step 5: Add the cross-writer summary matrix**

For each writer in `upstream`, `javascript`, and `beam`, publish a map state
containing:

- Independent scalar keys.
- A fixed object entry.
- A nested map entry.
- A deleted entry with retained history.
- Unicode and prototype-like keys.

Open each artifact with every reader, verify the state, make a new map edit,
publish or sequence it, and verify a fresh peer observes it. This gives nine
writer-reader combinations.

- [x] **Step 6: Run real-service interop**

Start the isolated pinned Floodgate service through the M1 command, then run:

```sh
rtk proxy just shared-tree-interop
```

Expected: the report includes every required map schedule, all three client
types as authors and readers, reconnect evidence, summary continuation, and no
skipped service or target result.

- [x] **Step 7: Mark native corpus coverage**

After both native targets pass the three Task 1 cases, add them to the
generated manifest's native semantic coverage source in `generate.mjs` and
regenerate:

```sh
npm --prefix tools/shared-tree-oracle run generate
npm --prefix tools/shared-tree-oracle run check
```

Confirm the manifest lists `map-schema-content`, `map-field-algebra`, and
`map-history-codecs` for JavaScript and Erlang.

- [x] **Step 8: Commit interoperability coverage**

```sh
git add tools/shared-tree-oracle/interop-scenarios.mjs \
  tools/shared-tree-oracle/client-interop.mjs \
  tools/shared-tree-oracle/interop.mjs \
  tools/shared-tree-oracle/interop.test.mjs \
  tools/shared-tree-oracle/summary-interop.mjs \
  tools/shared-tree-oracle/summary-interop.test.mjs \
  tools/shared-tree-oracle/generate.mjs \
  smoke/shared_tree.mjs \
  test/fixtures/shared_tree/manifest.json
git commit -m "test(tree): prove dynamic map interoperability"
```

---

### Task 9: Publish the M2 profile and run permanent gates

**Status:** Complete in `adf7815`. The M2 profile digest is
`a13390fcfcb551c142eee272db78b18fa899e9f2e7dc608e2ca71be06fee8fc2`.

**Files:**
- Modify: `README.md`
- Modify: `tools/shared-tree-oracle/README.md`
- Modify: `justfile` only if M1 recipes do not already include every M2 case
- Modify: `.github/workflows/shared-tree.yml` for the fast native gate
- Modify: `.github/workflows/shared-tree-interop.yml` for the manually
  dispatched real-service gate

**Interfaces:**
- Consumes: all M2 implementation and evidence from Tasks 1 through 8.
- Produces: documented support boundaries and required non-skipping release
  gates.

- [x] **Step 1: Update the supported profile**

Document:

- Named dynamic maps at root, object fields, and map entries.
- Leaf, fixed-object, and recursive-map values.
- Explicit `tree_map_get`, `tree_map_set`, `tree_map_delete`,
  `tree_map_keys`, and `tree_map_entries`.
- Canonical native iteration order.
- Per-key conflict, reconnect, and full-summary support.
- The pinned Fluid release and fixed container/service profile.
- Deferred arrays, map-wide clear, handles, schema evolution, transactions,
  undo/redo, branching, incremental summaries, Lustre bindings, and disk
  recovery.

- [x] **Step 2: Audit the production dependency boundary**

Run:

```sh
rg -n "@fluidframework|fluid-framework" src watershed_lustre examples
rg -n "node_modules|shared-tree-oracle|\\.reference/FluidFramework" src
```

Expected: no production Gleam or JavaScript module imports the oracle or Fluid
packages as the native map engine. Test tools and documentation references are
allowed.

- [x] **Step 3: Verify facade and target parity**

Run:

```sh
gleam test --target erlang -- shared_tree_map facade_parity
gleam test --target javascript -- shared_tree_map facade_parity
```

Expected: both targets execute a nonzero map test count and expose the same map
operations.

- [x] **Step 4: Run the complete release gate**

Run in this order:

```sh
rtk proxy just shared-tree-oracle-check
rtk proxy just shared-tree-test
rtk proxy just shared-tree-interop
rtk proxy just test
rtk proxy just build
rtk proxy just lint
```

Expected:

- Oracle regeneration is clean.
- Both native targets pass the SharedTree map cases.
- Real-service interop includes all required map schedules and summary cells.
- No target, corpus, or service gate skips.
- Existing DDS, runtime, storage, example, and Lustre coverage does not gain a
  new failure.

If `just test` reproduces the known unchanged
`smoke/runtime_bootstrap.mjs` failure with `Missing HTTP request /trees/`,
verify it on the M1 baseline commit and record it as baseline evidence. Do not
silence it or weaken the M2 gate.

- [x] **Step 5: Review the final diff**

Check:

```sh
git --no-pager diff --check
git --no-pager diff --stat HEAD~8..HEAD
git --no-pager status --short
```

Confirm generated fixtures are the only generated files committed, no
`.code-map/` file changed, and the unrelated `apm.lock.yaml` modification is
not staged.

- [x] **Step 6: Commit documentation and gate updates**

```sh
git add README.md tools/shared-tree-oracle/README.md justfile \
  .github/workflows/shared-tree.yml \
  .github/workflows/shared-tree-interop.yml
git commit -m "docs(tree): publish dynamic map profile"
```

If `justfile` or the workflow required no change, omit that path from
`git add`.

---

## 3. Final M2 acceptance checklist

- [x] M1 Task 16 and the M1 completion checklist passed before M2 release closure.

M2 implementation proceeded while the M1 release record was open. The merged
local and hosted gates supplied the missing M1 closure evidence before this M2
release record closed.
- [x] The pinned oracle generated all three required map corpus cases.
- [x] Schema-v2 named, root, nested, union-valued, and recursive maps decode.
- [x] Map values support M1 leaves, fixed objects, and supported map nodes.
- [x] Duplicate map keys fail before allocation or state change.
- [x] Root and nested map paths traverse on JavaScript and BEAM.
- [x] Public map get, set, delete, keys, and entries match across facades.
- [x] Native key and entry lists use canonical UTF-8 key order.
- [x] Different-key edits remain independent.
- [x] Same-key set/set and set/delete match upstream in both sequence orders.
- [x] Nested edit versus replacement and deletion preserves upstream identity.
- [x] Removed map values retain required repair data and history.
- [x] Reconnect resubmits pending map edits without loss or duplication.
- [x] Native clients consume upstream map messages and summaries.
- [x] Upstream consumes JavaScript- and BEAM-written map messages and summaries.
- [x] All nine summary writer-reader combinations load and continue editing.
- [x] Real-service tests include upstream, JavaScript, and BEAM map authors.
- [x] Malformed and unsupported map data stop the affected document without
  partial readiness.
- [x] Existing object-tree and non-tree regression suites retain their behavior.
- [x] Production modules have no Fluid npm or oracle dependency.
- [x] Documentation names the supported M2 profile and deferred features.

### Task 9 verification

- `just shared-tree-oracle-check`: passed.
- `just shared-tree-test`: passed, including 511 Erlang and 511 JavaScript
  SharedTree tests plus storage, bootstrap, and creation smokes.
- `just shared-tree-interop`: passed with no skipped M2 result.
- `gleam test --target erlang -- shared_tree_map facade_parity`: 44 passed.
- `gleam test --target javascript -- shared_tree_map facade_parity`: 44 passed.
- `just test`: passed after the Hex API rate limit cleared.
- `just build`: passed after the remaining packages downloaded.
- `just lint`: passed with the ignored pinned reference checkout moved outside
  the repository for the format scan, then restored unchanged.
