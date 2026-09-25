# SharedTree dynamic maps

**Date:** 2026-09-24
**Status:** Design approved on 2026-09-24.
**Milestone:** M2 in the native SharedTree interoperability roadmap.
**Depends on:** Completed M1 Task 16 and the M1 completion checklist.

## 1. Goal and scope

Add Fluid Framework 3.1.0 dynamic map nodes to Watershed's native SharedTree
implementation. Upstream TypeScript clients, Watershed JavaScript clients, and
Watershed BEAM clients must edit, summarize, reload, and continue editing the
same maps.

M2 supports:

- Named map schemas at the document root, in object fields, and as map values.
- Recursive schemas in which map entries can contain compatible map nodes.
- Map values drawn from the M1 leaf and fixed-object kinds plus supported map
  node kinds.
- Per-key get, set, delete, key iteration, and entry iteration.
- Existing path-based reads and nested edits through map entries.
- Concurrent edits, reconnect, summaries, and mixed-client service operation.

M2 does not include arrays, moves, Fluid-handle leaf values, schema evolution,
transactions, undo/redo, branching, incremental summaries, richer typed
bindings, Lustre integration, or crash recovery from disk. It does not expose
the alpha map-wide `clear` operation or alpha-only get-or-create helpers.

M1 remains a hard prerequisite. Oracle preparation can identify future work,
but no M2 native implementation begins until Task 16 and every M1 completion
item pass.

## 2. Compatibility contract

The M2 reference remains:

- `@fluidframework/tree` version `3.1.0`.
- `microsoft/FluidFramework` commit
  `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960`
  (`client_v3.1.0`).
- The fixed container, service, runtime, compressor, message, and summary
  profile established by M1.

The oracle must determine and record:

- The schema-v2 representation of named and recursive map nodes.
- The stored field schema used for arbitrary map keys.
- Forest and chunk representations for empty and populated maps.
- Modular changes for insert, replacement, delete, and nested edits.
- Message V7 encoding and edit-manager state.
- Summary encoding and reload behavior.
- Conflict results for concurrent operations.
- Behavior for deletion of an absent key.
- Behavior for edits to values removed or replaced by concurrent operations.

Native code must follow captured upstream behavior. Public TypeScript API
signatures and current implementation details are supporting evidence, not the
wire or semantic contract.

## 3. Public API

Both native facades add equivalent operations:

```gleam
pub fn tree_map_get(
  tree: SharedTree,
  path: tree_types.FieldPath,
  key: String,
) -> Result(Option(tree_types.TreeValue), String)

pub fn tree_map_set(
  tree: SharedTree,
  path: tree_types.FieldPath,
  key: String,
  value: tree_types.TreeValue,
) -> Result(Nil, String)

pub fn tree_map_delete(
  tree: SharedTree,
  path: tree_types.FieldPath,
  key: String,
) -> Result(Nil, String)

pub fn tree_map_keys(
  tree: SharedTree,
  path: tree_types.FieldPath,
) -> Result(List(String), String)

pub fn tree_map_entries(
  tree: SharedTree,
  path: tree_types.FieldPath,
) -> Result(List(#(String, tree_types.TreeValue)), String)
```

`path` identifies the map node. `key` remains separate from the path for direct
map operations. Existing path traversal treats map keys as path segments after
the traversal reaches a map node. A caller can therefore edit an object field
inside a map entry with the existing `tree_set` operation, or address a nested
map with the explicit map operations.

`tree_map_keys` and `tree_map_entries` sort keys with
`watershed/canonical_json.compare`. Fluid does not guarantee iteration order.
Watershed publishes canonical order so JavaScript and BEAM return the same
lists. Interoperability tests compare map membership and values rather than
requiring upstream iteration to use Watershed's order.

The existing `TreeChanged(local)` subscription event remains the only public
tree event in M2.

## 4. Data model and schema

Extend `TreeValue` with a named map value:

```gleam
MapValue(schema_id: String, entries: List(#(String, TreeValue)))
```

The constructor representation permits deterministic serialization and
cross-target comparison. Validation rejects duplicate keys. Public reads and
exports return canonical key order.

Extend stored and view schema nodes:

```gleam
pub type NodeSchema {
  Leaf(kind: LeafKind)
  Object(fields: List(#(String, FieldSchema)))
  Map(entries: FieldSchema)
}
```

Every key in a map node uses the same stored field schema. M2 accepts the
upstream map cardinality captured by the oracle. The expected cardinality is
optional because each key can be absent, but implementation must not encode
that assumption before the fixture records it.

Schema decoding must accept the captured schema-v2 map form, retain its
persisted representation, validate all referenced node identifiers, and reject
unsupported map field kinds. `can_view` compares map entry schemas with the
same stored/view rules used for object fields. Recursive schema references are
valid. Schema validation must terminate without recursively expanding the
schema graph.

Content validation applies the map entry schema to each key/value pair. Map
keys are arbitrary strings unless the oracle reports an upstream restriction.
Coverage includes empty strings, Unicode, numeric-looking keys, and keys such as
`"__proto__"` that can expose unsafe JavaScript object handling.

## 5. Forest and references

Extend the forest's internal node representation with a map node that records
its schema identifier and child field roots by key. Object nodes retain their
declared field behavior. Map nodes accept any key that passes the common map
entry schema.

The forest must support:

- Allocation, import, export, and validation of map nodes.
- Empty maps and maps containing leaves, objects, and nested maps.
- Path traversal through map keys.
- Map-node lookup for facade reads and edits.
- Canonically ordered key and entry reads.
- Detach, attach, rename, destroy, and refresher processing for map entries.
- Stable node references for values stored under map keys.

Map entries use the existing field-delta machinery. A map deletion detaches the
entry value instead of erasing identity and repair data. Concurrent nested edits
must continue to target the original node identity after another client replaces
or deletes the map entry, according to the captured upstream reconciliation
rules.

The forest must not store map content in a JavaScript object. Use persistent
Gleam collections and the existing canonical comparator so special property
names and target-specific object ordering cannot change behavior.

## 6. Changes and history

Add explicit internal edits:

```gleam
MapSet(path: FieldPath, key: String, value: TreeValue)
MapDelete(path: FieldPath, key: String)
```

The change builder performs these steps:

1. Resolve `path` to an attached map node.
2. Find the map node's stored entry schema.
3. Validate the key and candidate value.
4. Determine whether the key is present.
5. Allocate build and detach identities only after validation succeeds.
6. Emit an `OptionalField` change under the map key.
7. Add nested node and parent metadata through the existing modular format.

M2 reuses `optional_field.gleam` for each key. It does not add a dedicated map
changeset or a general field-kind registry. Existing modular composition,
inversion, rebasing, pruning, revision replacement, detached roots, refreshers,
and history reconciliation remain responsible for the result.

Different keys behave as independent fields. Edits to the same key follow the
captured optional-field conflict semantics. The oracle must cover set/set,
set/delete, delete/set, nested edit/replacement, and nested edit/deletion in
both sequence orders and from both authoring states.

History, acknowledgement, reconnect, and resubmission keep their current
interfaces. M2 extends their evidence with map commits and retained map values.
The implementation must preserve map keys when it rebuilds repair data from
detached content.

## 7. Codecs and summaries

The schema, forest, and summary codecs gain map-node support. The oracle must
show whether Message V7 and ModularChange V5 need new branches. If upstream
encodes map edits as existing optional fields under arbitrary field keys, the
native message codec reuses that representation without a map-specific tag.

Decoders must:

- Reject duplicate map keys and duplicate field changes.
- Reject unsupported map field kinds and unsupported format versions.
- Report the location of malformed schema, content, changes, and summaries.
- Preserve harmless extra envelope properties according to M1 rules.
- Avoid partial document readiness after semantic corruption.

Encoders must:

- Produce schema-v2 bytes accepted by the pinned upstream client.
- Encode empty and populated map nodes in the captured forest format.
- Preserve revision, atom, parent, and detached-field identities.
- Produce full summaries that all three clients can load and continue editing.

M2 keeps full-summary writing. Incremental summaries remain in M8.

## 8. Validation and atomic errors

Invalid local operations return a typed `TreeError` without changing:

- Visible or sequenced forest state.
- Pending history.
- Commit or atom allocation state.
- Compressor allocation state.
- Emitted events.
- Outbound messages.

Errors include:

- The target path does not identify an attached map node.
- The entry value is not allowed by the map schema.
- The map schema or referenced node schema is unknown.
- The target reference is stale or detached.
- Stored content contains duplicate keys.
- The stored map field kind or format version is unsupported.
- Wire or summary data contains malformed map content.

Deleting an absent key follows the oracle result. The facade returns no boolean
because Fluid cannot report whether a distributed deletion ultimately removed
a value.

## 9. Oracle and fixture coverage

Extend the existing oracle rather than adding a second fixture pipeline. Add a
map schema and initializer beside the M1 schema, source-level probes beside the
current algebra, forest, modular, history, and codec probes, and map scenarios
to the mixed-client driver.

The committed corpus must include:

1. Schema decoding for named, nested, root, union-valued, and recursive maps.
2. Empty, singleton, and multi-entry forest content.
3. Set of an absent key and replacement of a present key.
4. Delete of a present key and repeated delete of an absent key.
5. Concurrent edits to different keys.
6. Same-key set/set in both sequencing orders.
7. Same-key set/delete and delete/set in both sequencing orders.
8. Several pending local map edits crossed by remote map edits.
9. Nested object edits against concurrent entry replacement and deletion.
10. Nested map edits at independent and conflicting keys.
11. Edits to retained removed values, including summary and reload.
12. Reconnect before acknowledgement and accepted-before-disconnect recovery.
13. Summary-plus-tail bootstrap while another client edits the map.
14. Upstream, native JavaScript, and native BEAM summaries loaded by each
    implementation, followed by map edits.
15. Empty, Unicode, numeric-looking, and prototype-like keys.
16. Invalid schema, duplicate keys, malformed changes, and corrupt summaries.
17. JavaScript and BEAM equality for values, identities, errors, and canonical
    iteration.

Each case records intermediate observations. Tests distinguish visible equality
from identity, detached state, events, messages, and persisted bytes.

## 10. Integration and acceptance

M2 extends the existing SharedTree channel, runtime, facade, summary, and
service paths. It does not add another channel kind, document runtime, workflow,
or service profile.

The implementation plan must keep these responsibilities separate:

| Area | Responsibility |
| --- | --- |
| Oracle | Capture map schema, content, changes, history, codec, summary, and service behavior. |
| Schema and forest | Represent and validate map nodes, traverse keys, and retain detached content. |
| Change algebra | Build per-key optional-field edits and prove existing algebra against map cases. |
| Codec and summary | Read and write upstream-compatible map schema and content. |
| Kernel and facades | Expose explicit map operations with atomic validation and matching target APIs. |
| Interoperability | Prove mixed-client concurrent editing, reconnect, and cross-writer reload. |

The existing permanent commands remain the release gates:

```sh
rtk proxy just shared-tree-oracle-check
rtk proxy just shared-tree-test
rtk proxy just shared-tree-interop
rtk proxy just test
rtk proxy just build
rtk proxy just lint
```

The implementation plan can use narrower tests while a task is in progress.
M2 is complete only when the commands above pass with nonzero SharedTree tests
and without skipped targets, corpus domains, or service checks.

## 11. Exit criteria

M2 is complete when:

- M1 Task 16 and the M1 completion checklist pass before M2 implementation.
- The supported profile includes named and recursive dynamic map schemas.
- Map values can contain M1 leaves, fixed objects, and supported map nodes.
- Both native targets expose matching explicit map operations.
- Keys and entries use canonical cross-target ordering.
- Per-key set, replacement, and delete match upstream conflict behavior.
- Nested edits preserve upstream identity and detached-content behavior.
- Invalid edits leave all observable and allocation state unchanged.
- Native clients consume upstream map operations and summaries.
- Upstream consumes JavaScript- and BEAM-written map operations and summaries.
- All nine writer-reader summary combinations load and continue map editing.
- Reconnect and resubmission preserve pending map edits without duplication.
- The real-service mixed-client gate covers independent and conflicting map
  edits.
- Existing object-tree and non-tree behavior passes regression coverage.
- Documentation states the M2 map profile and its deferred features.
