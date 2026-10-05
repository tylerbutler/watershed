# SharedTree Schema Evolution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement upstream-compatible schema evolution for SharedTree objects
and dynamic maps on JavaScript and BEAM, including compatibility status,
explicit upgrades, concurrent schema/data conflicts, and persistence.

**Architecture:** Add an ordered schema/data change family above the existing
modular data algebra and carry it through the existing edit manager. Keep
visible and sequenced schema state paired with their forests. Bind application
views to facade handles, recheck compatibility at access time, and reuse the
document runtime, compressor, summary, and real-service infrastructure.

**Tech Stack:** Dual-target Gleam; startest; Node test runner;
`@fluidframework/tree` 3.1.0 published-package and source oracles; pinned
Floodgate; existing `just` and GitHub Actions gates.

**Spec:** [SharedTree schema evolution](../specs/2026-09-26-shared-tree-schema-evolution-design.md).
Also read the [parent design](../specs/2026-09-21-shared-tree-design.md)
and [M2 design](../specs/2026-09-24-shared-tree-dynamic-maps-design.md).

## Reconciliation — 2026-10-04

**Current status:** M4 is implemented for the published strict-view object and
dynamic-map subset. The numbered task checklists below are archived
red/green/commit instructions, not a live TODO list and not proof that every
historical command ran in the written order.

Current implementation evidence:

- `src/watershed/tree/schema.gleam:104,492-590` defines
  `Compatibility`, `compatibility`, `allows_superset`, `prepare_upgrade`, and
  `validate_upgrade`.
- `src/watershed/tree/shared_change.gleam:12-249` implements ordered outer
  schema/data changes, composition, inversion, effects, revision traversal,
  and data-only rebase. Schema-involved rebases intentionally mute the losing
  change rather than merge schemas.
- `src/watershed/tree/forest.gleam:301-307` replaces only the validated schema
  on an existing forest. History, kernel, runtime, codec, and summary paths now
  carry the outer change family.
- `src/watershed.gleam:550-598` and the matching BEAM facade provide
  `resolve_tree`, `open_tree`, `tree_compatibility`, and
  `tree_upgrade_schema`; `src/watershed/runtime_core.gleam:4167` owns atomic
  upgrade submission.
- `tools/shared-tree-oracle/upstream-schema-evolution.spec.ts` produces the
  four committed `schema-evolution-*` cases. The manifest registers all four
  for both native targets at
  `test/fixtures/shared_tree/manifest.json:290-293,321-324`.
- Native coverage spans
  `shared_tree_schema_evolution_test.gleam`,
  `shared_tree_shared_change_test.gleam`, and the forest, history, kernel,
  codec, runtime, summary, facade, and client suites named below.

The published feature flag is
`strict-view-object-map-schema-evolution`
(`test/fixtures/shared_tree/profile.json:243`). Array schema evolution, staged
upgrades, unknown-field adapters, data migrations, and additional upstream
versions remain excluded. The detailed historical release record is
`.superpowers/sdd/2026-09-26-shared-tree-schema-evolution/task-11-report.md`.
Its final local closure records the required M4 gates and a real-service run
with no skips or divergences, but also records that no hosted workflow ran and
that the final repository-wide `just test`/`just build` retries were blocked by
Hex API rate limits. This review did not rerun those gates.

## Global Constraints

- Production SharedTree semantics must run in pure Gleam on JavaScript and BEAM.
- Upstream TypeScript packages are development/test dependencies, not a production tree engine.
- Use `@fluidframework/tree` version `3.1.0`.
- Use Fluid Framework commit `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960` (`client_v3.1.0`).
- Use Floodgate commit `0eb493fc46d1bb9baf1151a6ccdde93544e057e7`.
- Keep `minVersionForCollab` at `2.117.0`.
- Keep Message V7, SharedTreeChange V5, ModularChange V5, and Schema V2.
- Keep the fixed layout: root alias `root` -> `A`, map `/A/root`, tree `/A/_C`.
- Preserve existing DDS behavior and the M1/M2 interoperability cases.
- Reject unsupported semantic formats and operations; do not approximate their meaning.
- Existing Watershed document encodings require no backward compatibility or migration.
- Keep `TreeChanged(local)` as the data-change notification.
- Apply ASD-STE100 to Gleam comments and error strings, not to Markdown prose.
- Do not edit apm-managed files, `.code-map/`, or generated website snippets.

---

## 1. Starting point and execution rules

The archived planning baseline was `f42deeca`
(`docs(tree): close M1 release gates`). At planning time, the working tree
already contained changes to `apm.lock.yaml`, the parent plan, and untracked M3
design/plan files. Those execution-time cautions are not standing prerequisites
for later review or maintenance.

This document originally planned the work. Its numbered-task boxes remain
archived instructions; use this reconciliation, the acceptance checklist, and
the Task 11 report for current status. The approved scope remains object/map
schema evolution under strict views.

M3 was not a prerequisite and has since landed. M4 uses the shared array-aware
schema and codec surfaces without claiming array schema evolution; that claim
still requires a separate array-evolution matrix.

Use an isolated worktree for execution. Record the starting revision and
tool versions from `mise.toml`. Restore dependencies only after a relevant
command reports missing dependencies, using existing lockfiles.

Each numbered task ends in a testable deliverable and commit boundary.
Within a matrix, take one named row through a failing test, implementation,
and passing test before moving on. The algorithms are larger than a single
five-minute step; the named rows are the test-first work units.

### Current constraints to remove

| Source at planning time | Required change |
| --- | --- |
| `tree/schema.gleam:309-368` | Keep strict `can_view`, add the distinct upgrade/equivalence relation and explicit upgrade preparation. |
| `tree/codec.gleam:58-66` | Move semantic schema and change types below the codec layer. |
| `tree/codec.gleam:408-466` | Preserve ordered changes and update the encoding context after schema changes. |
| `tree/history.gleam:17-63,93-117` | Store outer schema/data changes and return ordered effects. |
| `tree/history.gleam:665-861` | Retain common-prefix behavior while lifting rebase, inverse, and revision metadata traversal. |
| `tree_kernel.gleam:25-34,146-153` | Stop using one stored schema for both optimistic state and sequenced snapshots. |
| `tree_kernel.gleam:177-223` | Refresh and replay complete pending changes, not just modular data. |
| `tree/forest.gleam:241-326,351-390` | Distinguish attached validity from retained repair-content validity during schema rollback. |
| `tree/runtime.gleam:43-72` | Remove the post-initialization schema rejection only after history/kernel support lands. |
| `tree/summary.gleam:166-201,287-350` | Stop discarding schema changes and reconstructing semantics from stale wire copies. |
| `runtime_core.gleam:798-848,929-940` | Separate protocol bootstrap from a particular application view. |
| `runtime_core.gleam:3468-3590` | Reuse atomic submission and batch construction for schema commits without assuming every request allocates IDs. |
| `watershed.gleam:486-589` and BEAM counterparts | Carry the desired view in tree handles and recheck it on access. |

Line numbers identify the planning baseline. Find the named declarations again
before editing.

### Dependency order

```text
written design review
          |
1 pinned oracle and source-contract review
          |
2 compatibility and upgrade preparation
          |
3 outer schema/data algebra
          |
4 identity-preserving forest schema transitions
          |
5 lift history and all consumers, preserve data-only behavior
          |
6 kernel schema application and conflict reconciliation
          |
7 contextual codecs and semantic summary history
          |
8 atomic document submission and reconnect
          |
9 view-aware JS/BEAM facades and notifications
          |
10 mixed-client service and cross-writer persistence proof
          |
11 permanent gates and supported-profile closure
```

Tasks 2 and 3 can use separate owners after Task 1. Default to the ordered
sequence. Assign one owner to the M3/M4 integration surfaces:
`schema.gleam`, `codec.gleam`, `history.gleam`, `tree_kernel.gleam`,
`tree/runtime.gleam`, summary adapters, and runtime dispatch.

## 2. File map

| File or group | Responsibility |
| --- | --- |
| `src/watershed/tree/schema.gleam` | Schema state, compatibility, superset comparison, strict view check, upgrade preparation. |
| `src/watershed/tree/shared_change.gleam` (new) | Ordered outer change family, schema inverse marker, ordered effects, data traversal. |
| `src/watershed/tree/change.gleam` | Existing modular data semantics; only expose metadata helpers required by the outer family. |
| `src/watershed/tree/forest.gleam` | Schema replacement with preserved node identity and safe retained-content handling. |
| `src/watershed/tree/history.gleam` | Outer commits, rollback/rebase, pending, peer, receipts, resubmission. |
| `src/watershed/tree_kernel.gleam` | Visible/sequenced schema application, snapshots, schema events. |
| `src/watershed/tree/codec.gleam` | Outer wire conversion, sequential schema context, inverse-encoding refusal. |
| `src/watershed/tree/codec/field_batch.gleam` | Historical schema-aware object/map classification. |
| `src/watershed/tree/codec/summary.gleam` | Retained trunk/peer encoding contexts and existing summary layout. |
| `src/watershed/tree/summary.gleam` | Lossless semantic history load/write. |
| `src/watershed/tree/runtime.gleam` | Author, encode, receive, refresh, and resubmit outer commits. |
| `src/watershed/runtime_core.gleam` | Atomic schema submission, raw bootstrap, view-aware access checks. |
| `src/watershed/runtime.gleam`, `runtime_beam.gleam` | Existing target-specific state, request/reply, transport, and fan-out paths. |
| `src/watershed.gleam`, `src/watershed_beam.gleam` | Immutable view-bound handles and public compatibility/upgrade APIs. |
| `src/watershed/channel.gleam` | Outer-commit comparisons and exhaustive operation/event handling. |
| `tools/shared-tree-oracle/upstream-schema-evolution.spec.ts` (new) | Source-backed compatibility, algebra, history, codec, and summary captures. |
| `tools/shared-tree-oracle/schema.mjs` | Published-package application schema versions. |
| Existing oracle generation, client, scenario, summary, and gate files | Extend current harnesses rather than create another coordinator. |
| `test/watershed/tree/schema_evolution_fixture.gleam` (new) | Input-only native replay for the new corpus domains. |
| `test/watershed/shared_tree_schema_evolution_test.gleam` (new) | Compatibility, upgrade, and refusal tests. |
| `test/watershed/shared_tree_shared_change_test.gleam` (new) | Outer algebra and revision tests. |
| Existing forest, history, kernel, codec, runtime, summary, and facade tests | Add evolution cases at the boundaries they exercise. |

Keep pure implementation changes in these existing responsibility boundaries.
Do not introduce a generic change-family interface, a schema registry service,
or a second document runtime.

## 3. Shared interfaces

These are the task-to-task contracts. Add the declarations when their owning
task starts; do not scaffold unused functions ahead of it.

### Schema API, owned by Task 2

```gleam
pub type SchemaState {
  EmptySchema
  FixedSchema(StoredSchema)
}

pub type Compatibility {
  Compatibility(
    can_view: Bool,
    can_upgrade: Bool,
    is_equivalent: Bool,
  )
}

pub fn compatibility(
  stored: StoredSchema,
  view: ViewSchema,
) -> Result(Compatibility, TreeError)

pub fn allows_superset(
  original: StoredSchema,
  candidate: StoredSchema,
) -> Result(Bool, TreeError)

pub fn prepare_upgrade(
  stored: StoredSchema,
  view: ViewSchema,
) -> Result(Option(StoredSchema), TreeError)

pub fn validate_upgrade(
  before: StoredSchema,
  after: StoredSchema,
) -> Result(Nil, TreeError)

pub fn view_to_stored(view: ViewSchema) -> StoredSchema
```

`prepare_upgrade` returns `Ok(None)` for a semantic no-op and `Ok(Some(target))`
for a supported upgrade. It reports an incompatible or outside-profile
transition as a typed error. It allocates nothing.

`validate_upgrade` checks the forward superset relation and the supported
transition profile. Use it for authored/live forward upgrades, not for
internal rollback or retained initialization history.

Do not conflate upstream `allows_superset` with the M4 authoring profile.
`prepare_upgrade` must also reject transformations of an existing node kind,
even if upstream's repository relation permits them. Local schema
initialization remains in the existing creation path.

### Outer change API, owned by Task 3

```gleam
pub type TreeChange {
  DataChange(change.Changeset)
  SchemaChange(
    before: schema.SchemaState,
    after: schema.SchemaState,
    is_inverse: Bool,
  )
}

pub opaque type Changeset {
  Changeset(changes: List(TreeChange))
}

pub type TaggedChange {
  TaggedChange(
    revision: Option(fluid_ids.StableId),
    rollback_of: Option(fluid_ids.StableId),
    change: Changeset,
  )
}

pub type Effect {
  DataDelta(forest.Delta)
  SchemaDelta(
    before: schema.SchemaState,
    after: schema.SchemaState,
    is_inverse: Bool,
  )
}

pub fn empty() -> Changeset
pub fn from_data(data: change.Changeset) -> Changeset
pub fn from_changes(items: List(TreeChange)) -> Result(Changeset, TreeError)
pub fn to_changes(value: Changeset) -> List(TreeChange)
pub fn compose(changes: List(TaggedChange)) -> Result(Changeset, TreeError)
pub fn invert(
  value: TaggedChange,
  is_rollback: Bool,
  inverse_revision: fluid_ids.StableId,
) -> Result(Changeset, TreeError)
pub fn rebase(
  value: TaggedChange,
  over: TaggedChange,
  context: change.RebaseContext,
) -> Result(Changeset, TreeError)
pub fn effects(value: TaggedChange) -> Result(List(Effect), TreeError)
pub fn identity_revisions(value: Changeset) -> List(fluid_ids.StableId)
pub fn revision_infos(value: TaggedChange) -> List(change.RevisionInfo)
pub fn max_local_id(value: Changeset) -> Int
pub fn rebind_identity_order(
  value: Changeset,
  order: change.IdentityOrder,
  tagged_revisions: List(fluid_ids.StableId),
) -> Result(Changeset, TreeError)
```

`from_changes` normalizes adjacent data runs using `compose`, preserving schema
boundaries. `empty()` means no outer changes. `from_data(change.empty())`
retains one data subchange. Do not identify those two forms.

`max_local_id` takes the maximum across data runs, or `-1` when there are none.
Schema changes have commit revisions but no modular atom IDs.
`revision_infos` retains outer revision/rollback metadata even when there is
no data subchange.

### History and kernel contracts, owned by Tasks 5-6

```gleam
pub type Commit {
  Commit(
    revision: fluid_ids.StableId,
    originator: fluid_ids.SessionId,
    change: shared_change.Changeset,
  )
}

pub type HistoryUpdate {
  HistoryUpdate(
    history: History,
    effects: List(shared_change.Effect),
    sequenced_effects: List(shared_change.Effect),
    trimmed_revisions: List(fluid_ids.StableId),
  )
}
```

Keep `history.MintRevision(state)` returning the current modular
`change.IdentityOrder`; the outer family reuses it.

Add these kernel operations:

```gleam
pub fn compatibility(
  state: TreeState,
  view: schema.ViewSchema,
) -> Result(schema.Compatibility, TreeError)

pub fn apply_local_change(
  state: TreeState,
  revision: fluid_ids.StableId,
  authored: shared_change.Changeset,
) -> Result(#(TreeState, history.Commit, List(TreeEvent)), TreeError)
```

`tree_kernel.apply_local` remains the data-edit convenience wrapper. It authors
with `change.edit_from`, wraps the result, and delegates to
`apply_local_change`. `stored_schema(state)` returns the visible schema.
Snapshots return the sequenced schema.

### Public handles, owned by Task 9

Both opaque `SharedTree` records gain `view: tree_schema.ViewSchema`.
Both public facades expose:

```gleam
pub fn open_tree(
  document: Document(root),
  value: Json,
  view: tree_schema.ViewSchema,
) -> Result(SharedTree, String)

pub fn tree_compatibility(
  tree: SharedTree,
) -> Result(tree_schema.Compatibility, String)

pub fn tree_upgrade_schema(tree: SharedTree) -> Result(Nil, String)
```

Keep existing `resolve_tree`, reads, writes, map operations, handles, and
subscription signatures. `open_tree` checks routing and channel kind but not
`can_view`. `resolve_tree` also requires `can_view`.

## 4. Required oracle matrix

Use stable schema identifiers in namespace `org.watershed.shared-tree.m4`.
Schema-version labels identify application configurations, not node IDs.
Use a separate `SchemaFactory` per application version so classes with the
same schema identifier can have different definitions.

The base `Root` has `title: string`, `point: Point`, optional `note: string`,
and `items: Items`. `Point` has required numeric `x` and `y`.
`Items` is a dynamic map of `string | Point`. Define these candidate profiles:

| Label | Change from base |
| --- | --- |
| `v1` | Base schema. |
| `optional` | Add optional numeric `score` on `Root`. |
| `object-union` | Widen `Root.note` to `string | number`. |
| `map-union` | Widen `Items` entries to `string | Point | number`. |
| `optional-title` | Change required `Root.title` to optional. |
| `root-union` | Permit `Root | string` at the required root. |
| `optional-root` | Change required root to optional. |
| `combined` | Include all field upgrades above, with optional `Root | string` root. |
| `narrow` | Remove `Point` from the map entry union. |
| `new-required` | Add required `score: number` to the existing `Root`. |

Capture additional raw stored-schema cases for metadata, duplicate keys,
ordering, unused definitions, and required cycles; those cases are not
published-package application configurations.

### Corpus files

Create four generated, committed corpus entries:

| ID and file under `test/fixtures/shared_tree/` | Domain | Required observations |
| --- | --- | --- |
| `schema-evolution-compatibility.json` | `schema` | Status flags, discrepancies, upgrade/no-op/refusal, no data rewriting. |
| `schema-evolution-algebra.json` | `tree` | Ordered compose/invert/rebase, inverse refusal, empty outer changes, revision metadata. |
| `schema-evolution-history.json` | `history` | Optimistic and sequenced schemas, conflicts, pending/peer identities, rollback, events. |
| `schema-evolution-codecs.json` | `codec` | Messages, mixed data/schema runs, history branches, summary blobs and continuation. |

Each file uses the existing envelope:
`formatVersion`, `reference`, `id`, `domain`, `input`, `expected`, and `raw`.
Keep raw schema strings and wire messages. Native runners receive only `input`;
they must not read `expected` to derive a result.

Each `input` has a schema catalog and a list of named scenarios. History inputs
also include sessions, compressor allocation actions, and explicit sequence
points. Record `referenceSequenceNumber`, `minimumSequenceNumber`, and
`indexInBatch`, rather than inferring them from array positions.

Required history scenario IDs:

```text
upgrade-then-edit-causal
edit-then-upgrade-causal
schema-data-schema-first
schema-data-data-first
schema-schema-left-first
schema-schema-right-first
same-upgrade-concurrent
pending-upgrade-dependent-data-loses
pending-data-remote-upgrade
ack-common-prefix-keeps-upgrade
empty-conflict-acknowledged
rollback-retains-new-type-content
old-view-invalidated
new-view-reopens
reconnect-upgrade-unacknowledged
reconnect-upgrade-accepted-before-drop
summary-before-pending-upgrade
summary-upgrade-plus-tail
historical-peer-schema-context
```

For each checkpoint, compare visible schema, sequenced schema, visible root,
pending revisions and outer changes, trunk/peer revisions, detached identities,
and compatibility. Record upstream notifications as oracle evidence, but test
the documented native schema/data notification contract separately; Gleam does
not promise the TypeScript proxy event API.

---

## Task 1: Capture and review the pinned schema-evolution contract

**Files:**
- Create: `tools/shared-tree-oracle/upstream-schema-evolution.spec.ts`
- Modify: `tools/shared-tree-oracle/source.mjs`, `source.test.mjs`
- Modify: `tools/shared-tree-oracle/schema.mjs`
- Modify: `tools/shared-tree-oracle/generate.mjs`, `generate.test.mjs`
- Modify: `tools/shared-tree-oracle/README.md`
- Generate: the four corpus files in section 4, `manifest.json`, and existing capture metadata.

**Interfaces:**
- Consumes: pinned source, `TestTreeProviderLite`, existing source injection and corpus validation.
- Produces: the schema catalog, scenario inputs, expected observations, raw wire evidence, and a reviewed contract for Tasks 2-10.

- [ ] **1. Add a failing injection-registration test.**

Add an exported `schemaEvolutionInjectedTestPath` constant to the source
adapter's contract, then test the expected path:

```javascript
assert.equal(
  schemaEvolutionInjectedTestPath,
  "packages/dds/tree/src/test/watershedSchemaEvolution.spec.ts",
);
```

Add generation tests that remove each required scenario, schema catalog
entry, and raw schema message and assert rejection. For each new case, mutate
`reference.commit`, remove `input`, and replace the observation list with `[]`.
The validator must reject all four mutations.

Run:

```bash
node --test tools/shared-tree-oracle/source.test.mjs tools/shared-tree-oracle/generate.test.mjs
```

Expected red: missing injection export or missing required-case validation.

- [ ] **2. Implement the source injection and published schema catalog.**

Register the source file in the existing injection map and verify it with the
same allowed-untracked and content checks as the other injected tests.
Generate old/new classes with the same identifiers in separate factories:

```typescript
function applicationSchema(includeScore: boolean) {
  const sf = new SchemaFactory("org.watershed.shared-tree.m4");
  class Point extends sf.object("Point", { x: sf.number, y: sf.number }) {}
  class Items extends sf.map("Items", [sf.string, Point]) {}
  const fields = {
    title: sf.string,
    point: Point,
    note: sf.optional(sf.string),
    items: Items,
  };
  const Root = includeScore
    ? sf.object("Root", { ...fields, score: sf.optional(sf.number) })
    : sf.object("Root", fields);
  return { Root, Point, Items, config: new TreeViewConfiguration({ schema: Root }) };
}
```

Create the remaining section-4 configurations by changing the named field
or root in its own factory. Keep options non-staged and strict.

- [ ] **3. Capture compatibility and explicit upgrades.**

For each profile, capture `extractPersistedSchema`, ordinary view compatibility,
the result of `upgradeSchema()`, raw submitted messages, and root content before
and after. Assert that opening a view does not itself submit an upgrade.
Equivalent requests must submit no schema message.

Capture refused narrowing, new-required-field, optional-to-required, node-kind
replacement, and unsupported sequence/handle cases in a separate refusal
matrix. Mark upstream-supported but M4-excluded operations as profile
restrictions, not as upstream failures.

- [ ] **4. Capture outer algebra and the section-4 history scenarios.**

Use `SharedTreeChangeFamily`, not just `ModularChangeFamily`. Include:

```typescript
const conflict = family.rebase(
  tagChange(schemaChange, schemaRevision),
  tagChange(dataChange, dataRevision),
  revisionMetadataSourceFromInfo([]),
);
assert.deepEqual(conflict, { changes: [] });
```

Also check the opposite direction, schema/schema, empty operand behavior,
and the common-prefix acknowledgement path through the real edit manager.
Capture `data -> schema -> data` and multiple schema boundaries in one
internal changeset without adding a public transaction API.

For rollback, author an upgrade that introduces a new node type, author data
using it, then deliver the competing earlier edit. Capture attached and
detached content, schema rollback, and the resulting pending changes.

- [ ] **5. Capture wire and summary contexts.**

Record inverse schema encoding refusal, old/new schema bytes, schema-only
commits, empty outer commits, peer branches before the upgrade, and a
summary while an upgrade remains pending. Capture initialization history
with `EmptySchema` so the migration does not lose M1 bootstrap semantics.

Record whether decoding an incoming concurrent change needs its authoring
schema rather than the current visible schema. The native decoder must be
able to reach the outer conflict rule without first rejecting valid data
that belongs to the losing schema.

- [ ] **6. Regenerate and verify the corpus.**

```bash
npm --prefix tools/shared-tree-oracle run source:verify
npm --prefix tools/shared-tree-oracle run source:capture
npm --prefix tools/shared-tree-oracle run generate
npm --prefix tools/shared-tree-oracle run check
node --test tools/shared-tree-oracle/source.test.mjs tools/shared-tree-oracle/generate.test.mjs
```

Expected green: all four cases, complete scenario IDs, exact version pins,
nonempty raw evidence, and deterministic regeneration.

- [ ] **7. Review the source contract before native work.**

Record the reference source paths, capture case IDs, schema restrictions,
context needed for historical data, and rollback repair-content behavior in
the oracle README. Resolve any difference from this design before Task 2.
Do not replace a mismatching upstream result with a native expectation.

- [ ] **8. Commit the oracle deliverable.**

Stage only the files above and the generated corpus outputs.

```bash
git commit -m "test(tree): capture schema evolution contract"
```

## Task 2: Add compatibility status and checked upgrade preparation

**Files:**
- Modify: `src/watershed/tree/schema.gleam`
- Create: `test/watershed/shared_tree_schema_evolution_test.gleam`
- Create: `test/watershed/tree/schema_evolution_fixture.gleam`
- Modify: `test/watershed/shared_tree_schema_test.gleam`
- Modify: `test/watershed/shared_tree_map_schema_test.gleam`

**Interfaces:**
- Consumes: Task 1's compatibility corpus and current `StoredSchema`/`ViewSchema`.
- Produces: section 3's schema API and the fixture runner
  `run_compatibility(Json) -> Result(Json, String)`.

- [ ] **1. Add the input-only corpus test.**

```gleam
import watershed/tree/fixtures
import watershed/tree/schema_evolution_fixture

pub fn shared_tree_schema_evolution_compatibility_test() -> Nil {
  fixtures.assert_case(
    "schema-evolution-compatibility",
    schema_evolution_fixture.run_compatibility,
  )
}
```

Use existing fixture decoders for JSON shapes, exact keys, locations, and
tagged values. The runner decodes each supplied stored/view string, calls
the new API, and serializes status and error classifications. It must not
invoke upstream or load oracle observations.

- [ ] **2. Run the focused tests and confirm the missing status behavior.**

```bash
gleam test --target erlang -- shared_tree_schema_evolution shared_tree_schema shared_tree_map_schema
gleam test --target javascript -- shared_tree_schema_evolution shared_tree_schema shared_tree_map_schema
```

- [ ] **3. Add the distinct compatibility relation.**

Keep the current exact-view comparison as `can_view`. Compute upgrade
compatibility separately:

```gleam
pub fn compatibility(
  stored: StoredSchema,
  view: ViewSchema,
) -> Result(Compatibility, TreeError) {
  let target = view_to_stored(view)
  use can_upgrade <- result.try(allows_superset(stored, target))
  use reverse <- result.try(allows_superset(target, stored))
  use can_view <- result.try(case can_view(stored, view) {
    Ok(Nil) -> Ok(True)
    Error(InvalidSchema(_)) -> Ok(False)
    Error(error) -> Error(error)
  })
  Ok(Compatibility(can_view, can_upgrade, can_view && can_upgrade && reverse))
}
```

Propagate non-compatibility errors rather than turning them into `False`.

- [ ] **4. Implement repository superset comparison one row at a time.**

Compare type sets as sets. Compare root multiplicity and allowed types.
For object fields, treat a missing field as the semantic forbidden/empty
field during comparison, without enabling arbitrary forbidden fields in
application schemas. For maps, compare the common entry field.

The monotonic field relation is:

```text
Required -> Required: old types subset of new types
Required -> Optional: old types subset of new types
Optional -> Optional: old types subset of new types
Optional -> Required: false
missing object field -> Optional: true
missing object field -> Required: false
present ordinary field -> missing: false
```

Run the source-captured never-type cases through the upstream comparison
algorithm before applying the ordinary table. Required cycles without a
finite escape are impossible; an optional recursive link permits a finite
tree. Track the current recursion stack rather than marking all visited
types as impossible.

Visit all original definitions, including unused and detached-only types.
Preserve metadata and original persisted JSON, but do not make metadata
differences into structural compatibility failures.

- [ ] **5. Implement upgrade preparation and typed refusals.**

```gleam
pub fn prepare_upgrade(
  stored: StoredSchema,
  view: ViewSchema,
) -> Result(Option(StoredSchema), TreeError) {
  let target = view_to_stored(view)
  use status <- result.try(compatibility(stored, view))
  case status.can_upgrade {
    False -> Error(InvalidSchema("stored schema cannot upgrade to this view"))
    True -> {
      use reverse <- result.try(allows_superset(target, stored))
      case reverse {
        True -> Ok(None)
        False ->
          validate_upgrade(stored, target)
          |> result.map(fn(_) { Some(target) })
      }
    }
  }
}
```

Implement `validate_upgrade` with a checked superset test followed by a
private `check_supported_upgrade`. The latter rejects existing-node kind
changes, excluded field/leaf kinds, and profile expansion beyond the supported
object/map schemas. Neither function rewrites schemas or data. Checking
equivalence before the profile transition guard preserves the upstream no-op
rule.

- [ ] **6. Add exact regressions, rerun both commands, and commit.**

Assert: optional additions are upgradeable but not viewable before upgrade;
old strict views are not viewable after the addition; reordered sets produce
the same flags; narrowing is not upgradeable; duplicate declarations remain
errors; equivalent upgrade preparation returns `None`.

```bash
git add src/watershed/tree/schema.gleam test/watershed/shared_tree_schema_evolution_test.gleam test/watershed/tree/schema_evolution_fixture.gleam test/watershed/shared_tree_schema_test.gleam test/watershed/shared_tree_map_schema_test.gleam
git commit -m "feat(tree): classify schema compatibility and upgrades"
```

## Task 3: Implement the outer schema/data change family

**Files:**
- Create: `src/watershed/tree/shared_change.gleam`
- Create: `test/watershed/shared_tree_shared_change_test.gleam`
- Modify: `test/watershed/tree/schema_evolution_fixture.gleam`
- Modify: `src/watershed/tree/change.gleam` only for required metadata accessors.

**Interfaces:**
- Consumes: section 3 schema types and existing modular `change` functions.
- Produces: section 3 outer-change API and
  `run_algebra(Json) -> Result(Json, String)`.

- [ ] **1. Add a failing outer-empty distinction test and corpus replay.**

```gleam
pub fn shared_tree_outer_empty_is_not_empty_modular_test() -> Nil {
  shared_change.to_changes(shared_change.empty())
  |> expect.to_equal([])
  shared_change.to_changes(shared_change.from_data(change.empty()))
  |> expect.to_equal([shared_change.DataChange(change.empty())])
}

pub fn shared_tree_schema_evolution_algebra_test() -> Nil {
  fixtures.assert_case(
    "schema-evolution-algebra",
    schema_evolution_fixture.run_algebra,
  )
}
```

- [ ] **2. Run the focused tests.**

```bash
gleam test --target erlang -- shared_tree_shared_change
gleam test --target javascript -- shared_tree_shared_change
```

- [ ] **3. Implement the types and composition.**

Walk ordered outer changes. Accumulate tagged data subchanges. At each schema
subchange, call `change.compose` for the accumulated run, append the schema
subchange unchanged, and reset the run. Flush the last run at the end.
Skip absent runs; do not drop present empty data changes.

Preserve each outer revision and `rollback_of` when tagging a data run.
Do not compose data across schema boundaries.

- [ ] **4. Implement inversion and rebase.**

Invert each data item with `change.invert`; invert schema by swapping
`before`/`after` and setting `is_inverse: True`; then reverse the item list.

The rebase dispatch must use this order:

```gleam
case to_changes(value.change), to_changes(over.change) {
  [], _ -> Ok(value.change)
  _, [] -> Ok(value.change)
  value_items, over_items -> {
    case has_schema(value_items) || has_schema(over_items) {
      True -> Ok(empty())
      False -> rebase_data_pair(value, over, context)
    }
  }
}
```

Define private `has_schema(List(TreeChange)) -> Bool`.
Define `rebase_data_pair(TaggedChange, TaggedChange, change.RebaseContext)`
to require one normalized data item per operand, delegate to `change.rebase`,
and wrap the result. Report invalid normalization with `InvalidHistory`.
Do not interpret concurrent schema conflicts as document corruption.

- [ ] **5. Implement effect and revision traversal.**

`effects` maps data items through `change.into_delta` and schema items to
`SchemaDelta`, preserving order. Map identity rebinding over data items;
keep schema items unchanged. Retain the outer commit revision in history
even when `identity_revisions` has no inner data revisions.

Implement `revision_infos` by collecting tagged outer revisions and data
revision infos, preserving deterministic order and checking conflicting
rollback metadata in the existing history helper. Implement `max_local_id`
without inventing schema atom allocations.

- [ ] **6. Complete the source matrix and commit.**

Require both orders of schema/data conflict, schema/schema conflict, empty
operands, inversion order, metadata-only schema payloads, and data-only parity.
Keep the modular algebra's existing tests unchanged.

```bash
git add src/watershed/tree/shared_change.gleam test/watershed/shared_tree_shared_change_test.gleam test/watershed/tree/schema_evolution_fixture.gleam
git commit -m "feat(tree): add schema-aware shared change algebra"
```

If `change.gleam` needed a metadata accessor, stage that exact file too.

## Task 4: Add identity-preserving forest schema transitions

**Files:**
- Modify: `src/watershed/tree/forest.gleam`
- Modify: `test/watershed/shared_tree_forest_test.gleam`
- Modify: `test/watershed/tree/schema_evolution_fixture.gleam`

**Interfaces:**
- Consumes: checked stored schemas and the Task 1 rollback/retained-content evidence.
- Produces:

```gleam
pub fn stored_schema(state: Forest) -> schema.StoredSchema
pub fn replace_schema(
  state: Forest,
  stored: schema.StoredSchema,
) -> Result(Forest, TreeError)
```

The replacement operation is internal. Public monotonicity checks belong in
`prepare_upgrade`; internal inverses must be able to restore the prior schema.

- [ ] **1. Add a failing identity test.**

Build a forest with the `v1` schema and a point. Save the point reference,
exported data, and detached counter. Replace its schema with `optional`.
Assert the original reference still reads the same point and the exported
data and counters are identical.

The assertion body is:

```gleam
let assert Ok(reference) = forest.locate(before, ["point"])
let assert Ok(data) = forest.export_data(before)
let assert Ok(after) = forest.replace_schema(before, upgraded)
forest.read_node(after, reference)
|> expect.to_equal(forest.read_node(before, reference))
forest.export_data(after) |> expect.to_equal(Ok(data))
```

Obtain `before` and `upgraded` from the named `v1`/`optional` input catalog
and tagged initial root in `schema-evolution-history`.

- [ ] **2. Run the forest and schema tests on both targets.**

```bash
gleam test --target erlang -- shared_tree_forest shared_tree_schema_evolution
gleam test --target javascript -- shared_tree_forest shared_tree_schema_evolution
```

- [ ] **3. Replace only the schema field and validate the attached result.**

Use the existing persistent record update. Do not implement replacement via
`export_data`/`import_data`, which would rebuild node identity.

```gleam
pub fn replace_schema(
  state: Forest,
  stored: schema.StoredSchema,
) -> Result(Forest, TreeError) {
  use root <- result.try(visible_root(state))
  use _ <- result.try(schema.validate_root_field(stored, root))
  Ok(Forest(..state, schema: stored))
}
```

Schema-only additive transitions must not create nodes, destroy detached
content, or emit a data delta.

- [ ] **4. Add rollback repair-content regression before relaxing validation.**

Replay the Task 1 case in which a losing upgrade introduced a new node type.
Assert that attached content matches the restored schema and the detached
new-type content keeps its identity and value.

Split the current full validation into attached-schema validity and retained
structural integrity. Preserve checks for duplicate IDs, references, finite
leaves, detached-index consistency, and malformed field shapes. Check new
authored content against its authoring schema before it enters history.
Do not validate historical repair content against a later application view.

In delta processing, validate inserted/attached content under the schema
active for that data run. Permit retained historical content to survive an
inverse transition without accepting it as an active root or a new local edit.
Carry historical schema context through the codec work in Task 7; do not add
schema definitions to a document as a side effect of validation.

- [ ] **5. Verify failure atomicity and commit.**

Try replacing the schema with `new-required` against content without `score`.
Require an error and unchanged original forest/reference.

```bash
git add src/watershed/tree/forest.gleam test/watershed/shared_tree_forest_test.gleam test/watershed/tree/schema_evolution_fixture.gleam
git commit -m "feat(tree): preserve forest identity across schema transitions"
```

## Task 5: Lift the edit manager and consumers to outer changes

**Files:**
- Modify: `src/watershed/tree/history.gleam`
- Modify: `src/watershed/tree_kernel.gleam`
- Modify: `src/watershed/tree/runtime.gleam`
- Modify: `src/watershed/tree/codec.gleam`
- Modify: `src/watershed/tree/summary.gleam`
- Modify: `src/watershed/channel.gleam`
- Modify: affected existing `test/watershed/shared_tree_*_test.gleam` and
  `test/watershed/tree/*_fixture.gleam` / `*_export.gleam` consumers.

**Interfaces:**
- Consumes: `shared_change` and `forest.replace_schema`.
- Produces: `history.Commit` and `HistoryUpdate` from section 3, with the
  existing data-only suite still passing.

This is one atomic internal type migration. Do not create a second edit
manager or keep parallel legacy/new commit stores.

- [ ] **1. Add a data-only envelope regression before migrating types.**

Use existing history input schedules, wrap each authored modular changeset
with `shared_change.from_data`, and compare the same visible deltas, revision
orders, pending queues, acknowledgements, and resubmission outputs.
Assert a schema-only commit retains its revision even though it has no
modular revisions or atom allocations.

- [ ] **2. Run history, kernel, codec, and runtime tests.**

```bash
gleam test --target erlang -- shared_tree_history shared_tree_kernel shared_tree_codec shared_tree_runtime
gleam test --target javascript -- shared_tree_history shared_tree_kernel shared_tree_codec shared_tree_runtime
```

Expected red: outer commit payload/type mismatches or missing effect handling.

- [ ] **3. Change all history storage to the outer type.**

Update `Commit`, `RollbackEntry`, `RebaseResult`, tagged commit helpers,
composition, inversion, rebase, and receipt comparison. Replace
`Option(forest.Delta)` outputs with ordered effect lists. Preserve the current
common-prefix elimination and rollback cache keyed by branch-node identity.

Use `shared_change.revision_infos` in history's `rebase_context` collector;
do not inspect only the first data run. Use `shared_change.rebind_identity_order`
with the complete set of outer and inner revisions.

- [ ] **4. Adapt dependent callers in the same change.**

Wrap authored data in `tree_kernel.apply_local`. Map ordered `DataDelta`
effects through the existing forest application path. Move `SchemaState`
references from the codec to `schema`, and `TreeChange` references to
`shared_change`.

Temporarily keep the explicit live-schema refusal in `tree/runtime.gleam`
until Task 6 implements schema effects. Preserve complete schema entries in
wire structures; do not collapse them to empty modular data to compile.
Historical schema commits can exist in native history without replaying them
against the already-materialized summary forest.

At this type-migration boundary, change `summary.decode_commit` to wrap its
complete decoded item list instead of projecting out schema entries. Task 7
owns historical encoding/decoding contexts and removal of the stale-wire
rewrite logic; this task must not retain the data-only projection.

Adjust `channel.operations_equal` for the outer payload and preserve its
semantic comparison rules. Search compile errors for the other exhaustive
consumers; do not add catch-all matches.

- [ ] **5. Adapt fixtures without changing upstream expectations.**

Data-only fixture constructors should use:

```gleam
history.Commit(revision, originator, shared_change.from_data(modular))
```

Keep fixture data-delta output projections unchanged where they test M1/M2.
For outer tests, serialize the complete ordered list, including empty outer
changes. Do not manufacture schema events in old data-only scenarios.

- [ ] **6. Run the complete native SharedTree gate and commit.**

```bash
just shared-tree-test
```

Expected green: both targets, owned storage/bootstrap/creation smokes, and
facade parity. Stage the exact migrated source and test files after reviewing
the diff, then:

```bash
git commit -m "refactor(tree): retain outer changes in edit history"
```

## Task 6: Apply schema changes through kernel reconciliation

**Files:**
- Modify: `src/watershed/tree_kernel.gleam`
- Modify: `src/watershed/tree/runtime.gleam`
- Modify: `src/watershed/tree/history.gleam`
- Modify: `test/watershed/shared_tree_kernel_test.gleam`
- Modify: `test/watershed/shared_tree_history_test.gleam`
- Modify: `test/watershed/tree/schema_evolution_fixture.gleam`

**Interfaces:**
- Consumes: ordered `HistoryUpdate` effects and outer commit metadata.
- Produces: schema-aware `apply_local_change`, receipt/rebase, snapshots,
  `SchemaChanged(local)`, and `run_history(Json) -> Result(Json, String)`.

- [ ] **1. Add the history corpus test and a pending-summary regression.**

```gleam
pub fn shared_tree_schema_evolution_history_test() -> Nil {
  fixtures.assert_case(
    "schema-evolution-history",
    schema_evolution_fixture.run_history,
  )
}
```

In `summary-before-pending-upgrade`, apply the local schema change and inspect
both `stored_schema(state)` and `snapshot_parts(snapshot(state))`.
The former must contain `score`; the latter must still contain the base schema.

- [ ] **2. Run the history/kernel selectors and confirm a semantic failure.**

```bash
gleam test --target erlang -- shared_tree_history shared_tree_kernel
gleam test --target javascript -- shared_tree_history shared_tree_kernel
```

- [ ] **3. Pair schema state with each forest.**

Replace the ambiguous `TreeState.stored` with visible and sequenced schema
state, or derive each from its corresponding forest accessor. Prefer deriving
it when that avoids storing the same schema twice.

Implement one ordered effect fold in the kernel:

```gleam
list.try_fold(effects, before, fn(current, effect) {
  case effect {
    shared_change.DataDelta(delta) -> forest.apply_delta(current, delta)
    shared_change.SchemaDelta(_, schema.FixedSchema(after), _) ->
      forest.replace_schema(current, after)
    shared_change.SchemaDelta(_, schema.EmptySchema, _) ->
      Error(types.UnsupportedFeature(
        "tree.schema",
        "live transition to an uninitialized tree",
      ))
  }
})
```

The empty-state branch is for excluded live deinitialization, not summary
history. Retain initialization schema changes when restoring edit history.
Task 1 must prove normal initialized M4 reconciliation does not require
applying a live empty-schema state. If it does, stop and amend the profile
and forest representation before accepting this refusal.

Use a candidate forest for the complete effect sequence and publish neither
it nor events on failure. Check attached validity at appropriate completed
data/schema boundaries, without invalidating historical repair content.
Do not impose an uncaptured compare-and-swap check on wire `before` schemas;
upstream applies the rebased `after` schema.

- [ ] **4. Wire local and remote outer changes through the same path.**

For live forward `FixedSchema -> FixedSchema` effects, call
`schema.validate_upgrade` on the effect's recorded before/after pair before
application. Validate supported peer operations even when the receiver's
application view is incompatible. Inverse effects bypass the forward-only
monotonicity rule. Preserve captured initialization changes in summaries
without treating their transient narrowing as an application upgrade.

`apply_local_change` appends the full commit to history, applies returned
effects, and computes events from the before/after state. `receive` applies
`sequenced_effects` to the sequenced forest and `effects` to the visible forest.
Return no partial allocation or history update on error.

After this works, remove `wire_to_commit`'s live-schema rejection and replace
its data-flattening implementation with checked `shared_change.from_changes`.
An empty outer commit is valid and retains its envelope/revision.

- [ ] **5. Test conflicts, rollback, and causal order row by row.**

Replay both orders of schema/data and schema/schema races. Require the exact
upstream losing outer change, pending queue, and rollback sequence.
Verify dependent data does not survive a losing upgrade by being silently
revalidated against a different schema.

For causal upgrade-then-edit, require both operations to survive. For the
common-prefix acknowledgement case, require no spurious conflict.
For muted commits, require normal acknowledgement and no duplicate resubmit.

- [ ] **6. Add event and atomicity checks.**

Emit `SchemaChanged(local)` only when the completed visible schema differs.
Emit `TreeChanged(local)` only when visible data differs. If both differ,
schema precedes data. An acknowledgement that leaves visible state unchanged
emits neither. A rollback can emit a schema event.

Compare forest, schema, history, next local ID, compressor, and events around
an invalid local transition. Replay malformed ordered effects and require
the original state to remain the only returned usable state.

- [ ] **7. Rerun selectors and commit.**

```bash
git add src/watershed/tree_kernel.gleam src/watershed/tree/runtime.gleam src/watershed/tree/history.gleam test/watershed/shared_tree_kernel_test.gleam test/watershed/shared_tree_history_test.gleam test/watershed/tree/schema_evolution_fixture.gleam
git commit -m "feat(tree): reconcile schema and data changes"
```

## Task 7: Preserve schema context in messages and summaries

**Files:**
- Modify: `src/watershed/tree/codec.gleam`
- Modify: `src/watershed/tree/codec/field_batch.gleam`
- Modify: `src/watershed/tree/codec/summary.gleam`
- Modify: `src/watershed/tree/summary.gleam`
- Modify: existing SharedTree codec/summary tests and exports.
- Modify: `test/watershed/tree/schema_evolution_fixture.gleam`
- Modify: `tools/shared-tree-oracle/codec-interop.mjs`, `codec-interop.test.mjs`
- Modify: `tools/shared-tree-oracle/summary-interop.mjs`, `summary-interop.test.mjs`

**Interfaces:**
- Consumes: outer `TreeChange`, complete native history, and Task 1 context captures.
- Produces: bidirectional schema/data message consumption, semantic retained
  summaries, and `run_codecs(Json) -> Result(Json, String)`.

- [ ] **1. Add source-corpus replay and inverse-encoding refusal tests.**

```gleam
pub fn shared_tree_schema_evolution_codecs_test() -> Nil {
  fixtures.assert_case(
    "schema-evolution-codecs",
    schema_evolution_fixture.run_codecs,
  )
}
```

Build an inverted schema change through `shared_change.invert`, then call the
normal encoder. Require a typed error at the schema change location.
Do not serialize an `isInverse` field.

- [ ] **2. Run codec/summary selectors on both targets.**

```bash
gleam test --target erlang -- shared_tree_codec shared_tree_summary
gleam test --target javascript -- shared_tree_codec shared_tree_summary
```

- [ ] **3. Encode ordered runs with the right schema.**

Replace `encode_changes_value`'s independent map with a fold carrying the
current optional stored schema. Data uses that context; schema emits
`{old,new}`, rejects `is_inverse`, and changes the context for later data.

Keep numeric/version checks and upstream tolerance for harmless properties.
Preserve schema metadata and empty outer lists. Do not change Message V7 or
introduce schema-generation numbers on the wire.

- [ ] **4. Decode and classify historical content before active-view checks.**

Separate raw field-batch structural decoding from schema-dependent
object/map classification. The latter must use the schema active at the
data run's authoring point. Walk schema subchanges in order within a commit.

For a concurrent incoming message, obtain its base context from sequenced
history and the sender's peer/reference branch, not from the receiver's
optimistic schema. For summary peer branches, start at the peer base.
Use captured old/new schemas to move between those points. Only use a
context-free structural decode where the upstream format supplies enough
information; do not guess map-vs-object from an empty field list.

Reject malformed content at its actual wire location. A valid losing change
must reach rebase and become an empty outer change rather than stop the
document because the receiver currently has another schema.

- [ ] **5. Replace lossy retained-history conversion.**

Verify that the Task 5 `summary.decode_commit` migration keeps all outer
changes, then bind all data-run identities under the correct historical
contexts. Keep a regression that fails if schema changes become `None`.
`summary.encode_commit` must encode the current outer history payload instead
of trying to patch a single modular change into the old raw list.

Preserve original custom metadata and captured harmless envelope properties
where the existing contract keeps them. Retained-wire metadata may accompany
semantic history; it must not override a rebased change's contents.

Serialize the sequenced schema and forest from the same snapshot point.
Include retained schema-bearing trunk/peer commits and detached data.
Keep existing protocol/container metadata and publication-point handling.

- [ ] **6. Test historical initialization and multiple schema eras.**

Load an M1 summary with initialization schema entries, then edit it.
Load a summary with a peer branch based before an upgrade. Load an upgraded
summary with a tail that introduces another optional field. Write each back
and require upstream to load and continue editing.

Check corruption cases: malformed schema-v2 bytes, absent definitions, invalid
field kind, unsupported node-kind transformation, future codec version, and
an inverse schema write attempt. None may produce a usable partial snapshot.

- [ ] **7. Run upstream consumption gates and commit.**

```bash
just shared-tree-codec-interop
node --test tools/shared-tree-oracle/codec-interop.test.mjs tools/shared-tree-oracle/summary-interop.test.mjs
```

The codec gate must include new native outputs consumed by upstream, not only
native self-round-trips. Stage the exact changed files, then:

```bash
git commit -m "feat(tree): preserve schema context in wire and summaries"
```

## Task 8: Submit upgrades atomically and preserve them on reconnect

**Files:**
- Modify: `src/watershed/tree/runtime.gleam`
- Modify: `src/watershed/tree_kernel.gleam`
- Modify: `src/watershed/tree/history.gleam`
- Modify: `src/watershed/runtime_core.gleam`
- Modify: `test/watershed/shared_tree_runtime_test.gleam`,
  `shared_tree_runtime_js_test.gleam`, `shared_tree_runtime_beam_test.gleam`
- Modify: `test/watershed/shared_tree_history_resubmit_test.gleam`
- Modify: `test/watershed/tree/runtime_fixture.gleam`,
  `schema_evolution_fixture.gleam`

**Interfaces:**
- Consumes: checked upgrades, outer commits, contextual encoders.
- Produces:

```gleam
pub fn author_upgrade(
  state: tree_kernel.TreeState,
  view: schema.ViewSchema,
  compressor: fluid_ids.Compressor,
) -> Result(
  #(
    tree_kernel.TreeState,
    Option(history.Commit),
    List(tree_kernel.TreeEvent),
    fluid_ids.Compressor,
  ),
  TreeError,
)

pub fn submit_tree_upgrade(
  core: Core,
  address: String,
  view: tree_schema.ViewSchema,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
)
```

- [ ] **1. Add a failing no-op allocation regression.**

Request an equivalent schema upgrade through `submit_tree_upgrade`.
Assert the returned core equals the input, with empty events and outbound
operations. Compare compressor serialization, next client sequence number,
in-flight batches, and pending history.

```gleam
let assert Ok(#(after, events, outbound)) =
  runtime_core.submit_tree_upgrade(before, address, matching_view)
after |> expect.to_equal(before)
events |> expect.to_equal([])
outbound |> expect.to_equal([])
```

Use the existing runtime fixture bootstrap to supply `before`, its routed tree
address, and a view decoded from the bootstrap schema.

- [ ] **2. Run runtime/reconnect tests.**

```bash
gleam test --target erlang -- shared_tree_runtime shared_tree_history_resubmit
gleam test --target javascript -- shared_tree_runtime shared_tree_history_resubmit
```

Confirm the selected modules contain the new cases; a selector matching no
tests does not establish a result.

- [ ] **3. Author the schema commit only after validation.**

Call `prepare_upgrade` first. Return the input tuple with `None` for a no-op.
Otherwise allocate one revision through the existing document compressor,
construct a forward schema change, and call `apply_local_change`.

```gleam
shared_change.from_changes([
  shared_change.SchemaChange(
    schema.FixedSchema(tree_kernel.stored_schema(state)),
    schema.FixedSchema(target),
    False,
  ),
])
```

Factor the existing revision-allocation steps out of `author_edit` only as
needed to share them with `author_upgrade`. Preserve the current immutable
failure path and compressor ordering.

- [ ] **4. Reuse the core's batch construction.**

Extract the commit-to-outbound portion of `submit_tree_edits` into one private
helper used by data and schema submissions. Keep allocation before dependent
tree messages, grouping metadata, batch IDs, CSNs, and in-flight tracking.
Do not finalize local ID ranges during editing.

Short-circuit the no-op before requiring a creation range. Preserve atomic
candidate state until encoding and batch construction succeed.

- [ ] **5. Replay and refresh pending outer commits in order.**

Update `tree_kernel.resubmit_commits` to walk each commit and each data/schema
subchange against a scratch state starting from the sequenced state.
Apply schema transitions to that scratch state between data runs.

Use the pinned outer-family refresher rules: include required refreshers for
the first data run; avoid re-emitting roots already supplied or detached by
earlier runs; preserve builds and atom IDs. Extend the existing checked
refresher path with an explicit required/optional mode only where this needs
it. Missing required repair content remains an error.

Encode each pending commit with the schema at its own replay start, updating
the context at its inner schema boundaries. Do not encode the pending list
using the final optimistic schema for every commit.

Compare the replayed visible schema as well as the root with current visible
state. Preserve schema-only and empty conflict commits in resubmission.
Continue using the existing accepted-before-disconnect deduplication paths.

- [ ] **6. Test reconnect and failure atomicity, then commit.**

Cover unacknowledged schema commits, accepted-before-drop, pending data
dependent on an upgrade, a losing upgrade, duplicate acknowledgement, and
resume after summary-plus-tail catch-up. Invalid local upgrades must leave
allocation, CSN, output, events, and in-flight state unchanged.

```bash
git commit -m "feat(tree): submit and reconnect schema upgrades"
```

Stage only the runtime, kernel/history, and test files changed in this task.

## Task 9: Expose view-aware APIs on both native facades

**Files:**
- Modify: `src/watershed.gleam`, `src/watershed_beam.gleam`
- Modify: `src/watershed/runtime.gleam`, `src/watershed/runtime_beam.gleam`
- Modify: `src/watershed/runtime_core.gleam`, `src/watershed/tree/runtime.gleam`
- Modify: `src/watershed/tree_kernel.gleam`, `src/watershed/channel.gleam`
- Modify: `test/watershed/facade_parity_test.gleam`
- Modify: `test/watershed/shared_tree_map_facade_test.gleam`,
  `shared_tree_client_test.gleam`, `shared_tree_runtime_test.gleam`,
  `shared_tree_runtime_js_test.gleam`, `shared_tree_runtime_beam_test.gleam`
- Modify: `smoke/shared_tree_bootstrap.mjs`

**Interfaces:**
- Consumes: `submit_tree_upgrade`, status query, schema events.
- Produces: section 3 public APIs and runtime request/reply equivalents.

- [ ] **1. Add failing lifecycle and facade-parity tests.**

On the same document, open `v1` and `optional` handles before upgrading.
The `v1` handle can read. The `optional` handle can inspect compatibility
and upgrade but cannot read yet.

After upgrading through `optional`, require:

```text
optional.tree_compatibility = {canView:true, canUpgrade:true, isEquivalent:true}
optional.tree_get = success
v1.tree_compatibility.canView = false
v1.tree_get / tree_set / tree_clear / map access = compatibility error
document connection = usable
bootstrap SharedMap access = usable
```

Repeat through JS and BEAM facades, not only through the kernel.

- [ ] **2. Run facade/bootstrap tests on both targets.**

```bash
gleam test --target erlang -- facade_parity shared_tree_map_facade shared_tree_client shared_tree_runtime
gleam test --target javascript -- facade_parity shared_tree_map_facade shared_tree_client shared_tree_runtime
node smoke/shared_tree_bootstrap.mjs
```

Add new cases to the existing modules selected by the repository's test
runner; check discovery output rather than relying on a new filename prefix.

- [ ] **3. Separate raw protocol restore from strict view opening.**

Add `tree_kernel.restore_unviewed(snapshot, view_id, local_session)` returning
`Result(TreeState, TreeError)`. It imports supported stored state and history
without an application view. Implement existing strict `restore` as
`can_view` followed by this operation, preserving its old refusal behavior.

Add the analogous `tree/runtime.restore_unviewed(snapshot, view_id, compressor)`
and use it for document bootstrap. Remove the requirement to manufacture an
application view from the stored schema just to load a tree channel.
Keep route, channel type, schema format, summary integrity, and compressor
validation before document readiness.

- [ ] **4. Bind immutable views to handles and guard access.**

Add the `view` field to both `SharedTree` records. Implement `open_tree`,
`tree_compatibility`, and `tree_upgrade_schema`. Keep `resolve_tree` strict.

Pass the handle view with each runtime tree request. Perform `can_view`
inside the same core operation or BEAM actor message that performs the
read/write; a separate status read followed by a write would allow an
intervening schema transition.

Guard `tree_get`, `tree_set`, `tree_clear`, `tree_map_get`, `tree_map_set`,
`tree_map_delete`, `tree_map_entries`, and `tree_map_keys`. Keep raw kernel
reads for internal reconciliation and snapshot work; those are not
application view accessors.

- [ ] **5. Wire schema notifications without converting view mismatch into failure.**

Pass `SchemaChanged(local)` through the existing channel event wrapper and
subscription paths. Mutate runtime state before callbacks run.
The event does not contain a cached compatibility status for one handle;
applications call `tree_compatibility` with their own view.

Use the existing runtime error adapters for local view errors. A valid remote
upgrade must continue to advance the document while an old strict handle
becomes unavailable. Unsupported remote semantics and corrupt messages still
use the existing fatal document path.

- [ ] **6. Test callback order, recovery, and existing DDS behavior.**

Inside a schema callback, query compatibility and read through the new handle.
Require the final state. Verify `TreeChanged` does not fire for schema-only
upgrades and equivalent requests do not notify.

Open a new compatible handle after invalidation and continue editing.
Keep the old handle invalid; do not mutate its schema behind the caller.
Repeat with a document loaded from an already-upgraded summary.

```bash
just shared-tree-test
```

- [ ] **7. Commit the public deliverable.**

Stage the exact facade/runtime/channel/test files, then:

```bash
git commit -m "feat(tree): expose schema-aware tree views"
```

## Task 10: Prove mixed-client and cross-writer interoperability

**Files:**
- Modify: `test/watershed/tree/client_protocol.gleam`, `client_js.gleam`, `client_beam.gleam`
- Modify: `tools/shared-tree-oracle/client-driver.mjs`, `client-driver.test.mjs`
- Modify: `tools/shared-tree-oracle/interop-scenarios.mjs`, `interop-scenarios.test.mjs`
- Modify: `tools/shared-tree-oracle/client-interop.mjs`, `client-interop.test.mjs`
- Modify: `tools/shared-tree-oracle/summary-interop.mjs`, `summary-interop.test.mjs`
- Modify: `tools/shared-tree-oracle/interop.mjs`, `interop.test.mjs`
- Modify: `tools/shared-tree-oracle/service.mjs`, `service.test.mjs`
- Modify: `test/watershed/tree/summary_export.gleam`, `summary_fixture.gleam`

**Interfaces:**
- Consumes: native public APIs and published-package schema configurations.
- Produces: required schema-evolution sections in the existing service report,
  complete writer/reader evidence, and deterministic reproduction artifacts.

- [ ] **1. Extend command clients with failing protocol tests.**

Use explicit actions:

```json
{"op":"schema-compatibility","view":"optional"}
{"op":"schema-upgrade","view":"optional"}
{"op":"open-view","view":"v1"}
```

The shared client protocol validates view labels against the input profile.
JS and BEAM command clients call their public facades.
The upstream client creates the corresponding ordinary view and calls
`compatibility` or `upgradeSchema`. Do not synthesize schema operations in
the coordinator on behalf of a client.

- [ ] **2. Add missing-report tests before service scenarios.**

Require these report sections:

```javascript
const requiredSchemaSections = [
  "schemaCompatibility",
  "schemaRaces",
  "schemaReconnect",
  "schemaReloadMatrix",
];
```

For each section, remove it from an otherwise valid report and assert failure.
Remove one target, one race ordering, and one writer/reader cell in separate
tests. Zero observations or skipped required cells must fail.

- [ ] **3. Run deterministic mixed-client races.**

Exercise JS/upstream, BEAM/upstream, and JS/BEAM pairs with each side authoring
the upgrade in separate cases. Keep all clients at protocol version 3.1.0.
Control delivery so schema/data and schema/schema races run in both orders.
Record reference sequence numbers to prove concurrency.

Check the losing empty outer change and intermediate rollback, not just the
final root. Include causal upgrade-then-edit as a control that must not lose
the edit. Keep old-view invalidation separate from document corruption.

- [ ] **4. Run reconnect and all nine writer/reader combinations.**

For each writer in `upstream`, `javascript`, `erlang`, publish an upgraded
summary. For each reader in the same set, load it, inspect compatibility,
open the matching view, write the new field or map type, and observe that
write from another client.

Also publish while a local upgrade is pending and prove that the summary
contains the sequenced schema. Replay the operation tail across the upgrade.
Include a retained peer branch from the earlier schema era.

Use real stored summary trees/blobs and fresh readers. Exported JSON
comparisons are insufficient.

- [ ] **5. Add seeded schedules to the existing generator.**

Include compatible data edits, attempted explicit upgrades, controlled
disconnects, acknowledgements, and summary reloads. Keep view labels and
schema transitions in the failure artifact along with seed and schedule.
Do not silently retry a losing upgrade.

Run 200 schedules with seed 42 for the required gate. Keep 5000 schedules in
the existing manual deep command.

- [ ] **6. Run the real-service gates.**

```bash
node --test tools/shared-tree-oracle/client-driver.test.mjs tools/shared-tree-oracle/interop-scenarios.test.mjs tools/shared-tree-oracle/client-interop.test.mjs tools/shared-tree-oracle/summary-interop.test.mjs tools/shared-tree-oracle/interop.test.mjs tools/shared-tree-oracle/service.test.mjs
just shared-tree-interop
```

Expected: pinned service identity; all three implementations; all required
schema report sections; both race orderings; reconnect evidence; nine
reload cells with continued writes; no skipped target/service/corpus.

If the service prerequisite fails, retain the reproduction and report the
gate blocked. Do not substitute an in-memory sequencer.

- [ ] **7. Commit the interoperability proof.**

Stage changed harness/client files and committed deterministic regression
fixtures, not transient server logs or credentials.

```bash
git commit -m "test(tree): prove schema evolution interoperability"
```

## Task 11: Close permanent gates and document the supported profile

**Current status:** Complete for the restricted M4 profile. See the
reconciliation above and the Task 11 report for recorded evidence and caveats.

**Files:**
- Modify: `tools/shared-tree-oracle/service.mjs`, `generate.mjs`, `interop.mjs`
- Modify: their existing tests and `tools/shared-tree-oracle/gates.test.mjs`
- Generate: `test/fixtures/shared_tree/profile.json`, `manifest.json`, captured metadata
- Modify: `tools/shared-tree-oracle/README.md`, `README.md`
- Modify: `.github/workflows/shared-tree.yml`, `.github/workflows/shared-tree-interop.yml`
  only if the existing commands do not already include the new required cases.
- Modify: `justfile` only if required selectors need adjustment.
- Modify: `docs/superpowers/plans/2026-09-21-shared-tree.md` after preserving other work.

**Interfaces:**
- Consumes: Tasks 1-10 passing evidence.
- Produces: an accurate restricted M4 compatibility claim and permanent checks.

- [ ] **1. Add failing profile/gate assertions.**

The supported features list must distinguish object/map schema evolution
from staged upgrades and array schema evolution. Keep exclusions explicit.
Require the four new corpus IDs in native and source coverage.
Require the service report's schema sections in the existing coordinator.

Do not replace a broad `"schema-evolution"` exclusion with an unqualified
support label; use a label that describes the object/map, strict-view subset.

- [ ] **2. Regenerate profile metadata and update pins derived from it.**

Generate the profile through the current oracle workflow. Update the
coordinator's profile digest and exact-profile tests from the generated bytes.
Preserve the Fluid/Floodgate pins, codec versions, layout, and existing M1/M2
feature support. Do not change `minVersionForCollab` to make a case pass.

```bash
npm --prefix tools/shared-tree-oracle run generate
npm --prefix tools/shared-tree-oracle run check
```

- [ ] **3. Document the actual API and concurrency behavior.**

Show `open_tree`, compatibility inspection, explicit upgrade, and strict
`resolve_tree`. Explain that a wider ordinary view is not automatically
viewable, an old handle can become unavailable, and an upgrade can lose to a
concurrent data edit.

Document the no-op rule, schema notifications, sequenced snapshot behavior,
the initialized-document scope, and the difference between application schema
versions and package versions. State the authoring restrictions separately
from upstream `can_upgrade`.

Keep staged upgrades, unknown-field adapters, arrays, migration, public
transactions, and additional upstream versions out of the compatibility claim.
Do not perform a website copy pass for this backend milestone.

- [ ] **4. Run final validation without skipped prerequisites.**

```bash
gleam format --check src test
npm --prefix tools/shared-tree-oracle test
just shared-tree-test
just shared-tree-codec-interop
just shared-tree-interop
just test
just build
just lint
```

Run targeted commands during preceding tasks. This broad run is the release
closure after shared runtime/history changes. Record actual failures and
investigate whether this branch caused them. Do not assume a historical
baseline failure still applies without reproducing it on the relevant base.

- [ ] **5. Close the acceptance checklist only with recorded evidence.**

Update the parent roadmap's M4 status and link this plan and design. Preserve
concurrent M3 notes and do not mark M3 complete. Record CI status separately
from local results; a local pass is not a hosted CI pass.

- [ ] **6. Commit the profile and documentation changes.**

```bash
git commit -m "docs(tree): define schema evolution support"
```

Stage only the regenerated profile/manifest, associated validators/gates,
and documentation or configuration changed by this task.

## 5. M4 acceptance checklist

- [x] The source oracle covers the approved object/map schema profile.
- [x] `can_view`, `can_upgrade`, and `is_equivalent` match the pinned source.
- [x] Equivalent upgrades allocate nothing and submit/emit nothing.
- [x] Invalid and outside-profile local upgrades leave state unchanged.
- [x] Ordered schema/data changes survive codecs, history, and summaries.
- [x] Inverse schema changes remain internal and cannot be encoded.
- [x] Schema/data and schema/schema races match upstream in both orders.
- [x] Causal and common-prefix cases do not become false conflicts.
- [x] Muted commits retain identity through acknowledgement and reconnect.
- [x] Rollback preserves required detached content and node identity.
- [x] Snapshots pair sequenced schema, forest, history, and compressor state.
- [x] Old strict handles cannot read or write after incompatible upgrades.
- [x] View incompatibility does not stop an otherwise valid document.
- [x] JS and BEAM expose matching APIs and notification semantics.
- [x] A fresh compatible handle can continue editing after invalidation.
- [x] Both targets consume upstream schema operations and publish consumable output.
- [x] All nine summary writer/reader combinations continue editing.
- [x] Real-service reconnect and accepted-before-drop cases pass.
- [x] Required gates fail on missing artifacts, targets, scenarios, or service.
- [x] Existing DDS behavior and M1/M2 interoperability remain intact.
- [x] The supported profile names the M4 limits without claiming M3 or M5 work.

## 6. Review checklist and stop conditions

Before implementation, check the companion design against the task interfaces.
Before closing the milestone, check each acceptance item against a named test
or report cell.

| Design requirement | Owning tasks |
| --- | --- |
| Strict compatibility, monotonic upgrades, no-op/refusal | 1, 2, 8 |
| Outer algebra and schema conflict semantics | 1, 3, 5, 6 |
| Identity, detached content, and inverse schema application | 4, 6, 7 |
| Sequenced snapshots and historical schema contexts | 6, 7, 10 |
| Atomic output, revision allocation, and reconnect | 5, 8, 10 |
| Immutable view-bound handles and schema notifications | 6, 9 |
| Both targets, upstream consumption, and real-service evidence | 1, 7, 9, 10 |
| Restricted support claim, permanent gates, M3 coordination | 1, 11 |

Stop and revise the contract if the pinned oracle requires a live empty-schema
transition, an unmodeled historical field-batch context, or retained content
that the current representation cannot preserve. Those are representation
requirements, not opportunities to skip data or broaden catch-all errors.

Coordinate with M3 if its changes have altered the named types or paths.
Do not overwrite its dispatch changes. The integration review must include
all field kinds actually compiled into the resulting branch, even though
M4's interoperability claim stays limited to objects and maps.
