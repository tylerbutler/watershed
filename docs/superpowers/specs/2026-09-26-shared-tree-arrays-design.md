# SharedTree arrays and moves

**Date:** 2026-09-26
**Status:** Task 1 source evidence captured. M3 acceptance remains pending the
native implementation and its review gates.
**Milestone:** M3 in the [SharedTree roadmap](2026-09-21-shared-tree-design.md).
**Plan:** [Arrays and moves implementation plan](../plans/2026-09-26-shared-tree-arrays.md).
**Prerequisites:** M1 and M2 release closure, recorded at repository baseline
`f42deeca`.

## 1. Scope

Support named array nodes at the root, in object fields, in map entries, and in
other arrays. Elements can be the supported leaves, fixed objects, maps, or
arrays allowed by the stored schema. Include recursive array schemas and
recursive array/map combinations.

Expose reads, ordered value iteration, range insertion, range removal, and
same-array or cross-array range movement on JavaScript and BEAM. Both arrays in
a move belong to the same `SharedTree` view. A move preserves the identities of
its elements and their descendants.

Extend the existing edit history, reconnect, summary, container-creation, and
real-service evidence. A fresh upstream, JavaScript, or BEAM reader must load a
summary from each writer and continue editing it.

Keep these features out of M3: schema evolution, public transactions,
undo/redo, branching, handle-valued leaves, broader container layouts, Lustre
bindings, disk-backed pending-state recovery, and incremental summaries.
Internal inversion, rollback, composition, and repair remain necessary for
ordinary pending-commit reconciliation.

## 2. Global constraints

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

The committed profile already records Sequence V3. Adding arrays does not
justify changing the message profile or upgrading Fluid. Stop for a profile
decision if the source oracle contradicts these constraints.

### Captured Task 1 source evidence

The pinned 3.1.0 source corpus contains 38 cases: the prior 29 cases unchanged
and nine M3 cases. These observations define the upstream inputs and expected
results for later native runners; they do not constitute M3 acceptance.

- A named array is encoded as an object node with primary field key `""` and
  cardinality `"Sequence"`. There is no separate array node kind on the wire.
- Actual array messages use Sequence V3 inside ModularChange V5 and Message V7.
  Multi-element builds, empty content, detached indexes, retained history, and
  full summary blobs are preserved in the captured source evidence.
- Public hydrated empty insert, empty removal, and empty same-array move emit
  no commit, change event, node event, pending edit, revision, or message.
  Low-level editor behavior is not identical: a zero-count insert retains an
  Insert mark, while zero-count remove and move produce empty changes.
- Equal-valued moves and moves whose destination lies inside the source range
  can leave visible values unchanged while still emitting a commit and change
  event. They are not public no-ops; identity order and emitted move endpoints
  remain part of the contract.
- Same-array destinations are pre-edit gaps. A destination strictly inside the
  source range produces split low-level marks: `MoveOut(1)`, `MoveIn(3)`,
  `MoveOut(2)` for the captured three-item range.
- A compatible cross-array move preserves the hydrated object identity.
  Numeric-looking and empty map keys remain literal keys around nested arrays.
- Pinned `removeRange(1, 99)` clamps to the array end. Watershed intentionally
  rejects `end > length`; this is a native validation rule, not a parity claim
  for invalid upstream input.
- Schema compatibility evidence initializes the declared stored schema and
  requests the declared view schema. The `objectArrays` to `objectArrays`
  scenario no longer substitutes an `Items` root.
- The source replay boundary accepts only JSON data. Codec cases provide
  encoded messages or summaries plus compressor context; history cases provide
  ordered actions and complete summary-tail envelopes and creation ranges.
  Expected observations are never reused as replay operands.

These fixtures are source evidence, not native coverage. Add a case to the
native semantic-runner lists only after an input-only runner passes on both
targets. Task 1 remains pending independent review.

## 3. API and path behavior

Both native facades add these functions; `SharedTree` denotes the respective
facade's existing handle type:

```gleam
pub fn tree_array_get(
  tree: SharedTree,
  path: tree_types.FieldPath,
  index: Int,
) -> Result(Option(tree_types.TreeValue), String)

pub fn tree_array_values(
  tree: SharedTree,
  path: tree_types.FieldPath,
) -> Result(List(tree_types.TreeValue), String)

pub fn tree_array_insert(
  tree: SharedTree,
  path: tree_types.FieldPath,
  index: Int,
  values: List(tree_types.TreeValue),
) -> Result(Nil, String)

pub fn tree_array_remove(
  tree: SharedTree,
  path: tree_types.FieldPath,
  start: Int,
  end: Int,
) -> Result(Nil, String)

pub fn tree_array_move(
  tree: SharedTree,
  source_path: tree_types.FieldPath,
  source_start: Int,
  source_end: Int,
  destination_path: tree_types.FieldPath,
  destination_gap: Int,
) -> Result(Nil, String)
```

Ranges are half-open: `[start, end)`. Insert and move destinations are gaps in
the author's current array, before the operation. For `[A, B, C]`, moving
`[0, 1)` to gap `3` produces `[B, C, A]`; moving it to gap `2` produces
`[B, A, C]`. Do not subtract the source length from a destination before
passing it to the sequence editor.

Validate integer arguments in the safe range `0..9_007_199_254_740_991`.
Inserts require `index <= length`; removals require
`start <= end <= length`; moves check both arrays and both ranges. A valid
nonnegative read index at or beyond the length returns `Ok(None)`. A negative
or unsafe read index returns an error. Wrong-kind and missing array targets
return errors.

Within an array, path segments use canonical ASCII decimal indices: `"0"`,
`"1"`, `"12"`. Reject `"-1"`, `"+1"`, `"01"`, `"1.0"`, whitespace, and
out-of-safe-range integers. Within objects and maps, those strings remain
literal field names or keys. In particular, a map key `"0"` does not become an
array index. Empty map keys remain keys; the array's internal empty-string
field key is not an application path segment.

Examples:

```text
["left", "2", "title"]     object field in the third array element
["byKey", "0"]            literal map key "0"
["byKey", "0", "1"]       second element of an array under map key "0"
["matrix", "1", "0"]      first element of the second nested array
```

`tree_get` and existing map operations traverse arrays. A missing final array
index returns `None`; traversing through a missing element returns an error.
`tree_set` and `tree_clear` can edit object/map fields below array elements.
They do not assign or clear an array slot: use array insert/remove operations.
Setting an object field to an entire `ArrayValue` remains a supported field
replacement with new content identity.

An empty insertion, empty removal, or empty same-array move must follow the
captured public behavior: validate its target and arguments, then suppress the
revision, commit, events, pending state, and outbound message. Apply this at the
author/submission boundary; a low-level editor alone cannot enforce it. Do not
add a general visible-equality shortcut because an interior move can be visibly
unchanged while still carrying split move marks and identity semantics.

## 4. Representation and stored schema

Add:

```gleam
ArrayValue(schema_id: String, elements: List(TreeValue))

ArrayInsert(path: FieldPath, index: Int, values: List(TreeValue))
ArrayRemove(path: FieldPath, start: Int, end: Int)
ArrayMove(
  source_path: FieldPath,
  source_start: Int,
  source_end: Int,
  destination_path: FieldPath,
  destination_gap: Int,
)
```

Add `Sequence` to schema cardinality and `Array(elements: FieldSchema)` to
the native node-schema sum. Capture the schema-v2 representation rather than
inventing an `"array"` wire node kind. The expected upstream representation
is an object node whose empty-string primary field has kind `"Sequence"`.
Task 1 must confirm the exact shape, including empty arrays.

Accept sequence fields only in that array-node shape in M3. Keep document root
and ordinary object/map field cardinalities unchanged. Recursive validation
must examine definitions and references without expanding the schema graph.

Store array nodes as a schema identifier and an ordered list of existing
forest node IDs. Do not key elements by their positions in a map. Do not
normalize, sort, or deduplicate array elements. Equal values can have distinct
identities.

## 5. Forest and path resolution

Keep the persistent forest and its detach-before-attach traversal. Extend
counted marks, range bounds, detached indexes, refreshers, rename, destroy,
import, and export for sequence fields.

Before building a changeset, resolve a path into field/index steps. An object
or map hop selects index zero in its named field. An array hop selects the
requested index in the primary field `""`. Include the root field step. Reuse
this resolution for reads and ancestor wrapping; do not independently parse
numeric segments in codecs, facades, and edit builders.

Moving existing node IDs through the detached index must preserve `NodeRef`
equality within one forest lineage. References from another view remain
invalid. Reload tests compare persisted atom/revision relationships and
behavior, not equality of process-local `NodeRef` values across imports.

Check range overlaps across the full interval, not only the first atom of a
counted mark. A failed destination check, duplicate attachment, cycle, or
missing detached root must leave the input state unchanged.

## 6. Sequence changes and modular integration

Port the behavior of the pinned sequence field into pure Gleam. The required
mark families include no-op/skip, insert, remove, move-in, move-out,
attach-and-detach, and rename, together with empty-cell IDs, revision
qualifiers, detach overrides, final move endpoints, and nested child changes.

Do not substitute `lattice_sequence`, the existing sequence DDS, JSON array
patches, or delete-and-insert for this algebra. Those implementations do not
establish SharedTree equivalence.

Provide counted-mark splitting and normalization, composition, inversion,
rebasing, revision replacement, pruning, relevant-removed-root enumeration,
refresher repair, and delta conversion. Preserve the distinction between an
occupied cell and an empty cell with retained identity.

Cross-array movement requires coordination across fields. Use a
changeset-scoped move-effect table with range queries, dependency tracking, and
reprocessing of fields invalidated by later endpoint information. Preserve
child edits that follow a moved node and updates to move chains. Do not assume
that one field's rebaser can decide a move in isolation, or that two passes
always suffice.

Extend the closed `change.FieldChange` sum with `SequenceField`. Keep the
existing external `change`, history, and kernel entry points. Handle
Generic/Sequence conversions in both directions at nonzero child indices.
Thread compressor-derived `IdentityOrder` through sequence operations.
Allocation order, UUID string order, and chronological revision order are not
interchangeable.

A cross-array move validates both paths and destination element compatibility
against one pre-edit forest, then creates one modular changeset and one
history commit. Reject a destination inside the moved subtree before
allocation. Do not implement the two endpoints through separate facade calls.

## 7. Codecs, history, and persistence

Decode and encode Sequence V3 through the existing Message V7 / ModularChange
V5 context, including nested node callbacks and compressed revision IDs.
Unsupported formats still return located typed errors.

The field-batch codec currently reduces structural fields to singleton
`TreeValue`s. Replace that internal reduction with a raw node representation
whose fields contain lists of raw nodes. Classify those nodes against the
stored schema after decoding. This preserves empty arrays and multiple
elements without misclassifying an object or map.

Keep the public typed value format separate from upstream bytes. The test
client uses:

```json
{
  "kind": "array",
  "schemaId": "org.watershed.shared-tree.m3.Items",
  "elements": [
    {"kind": "string", "value": "A"},
    {"kind": "string", "value": "B"}
  ]
}
```

Continue to derive summaries from sequenced state, not the optimistic view.
Retain sequence detached roots, move endpoints, and required peer history.
Replay summary tails from the snapshot sequence point. Preserve creation
ranges and original batch/revision identity during reconnect.

Invalid edits must not change the accepted forest, history, allocator,
compressor, events, or outbound messages. Transient allocation on immutable
candidate state is acceptable only when an error prevents that candidate
from becoming the accepted state.

## 8. Required proof

The implementation plan defines nine source-corpus cases, deterministic
conflict families, and a nine-cell array summary writer/reader matrix.
Separate four claims:

1. Behavioral parity at intermediate checkpoints, including identities and
   detached content.
2. Bidirectional codec interoperability with actual pinned upstream readers.
3. Persistence interoperability, with a new edit after each fresh reload and
   an independent peer verifying its exact value and resulting tree.
4. Mixed-client operation through the real pinned Floodgate service.

Include insert/insert, insert/remove, overlapping removes, move/edit,
move/delete, competing moves, partial-overlap moves, ancestor
replacement/removal, cross-array moves, recursive arrays/maps, pending chains,
acknowledgement loss, and summary-plus-tail continuation.

Compare ordered arrays without sorting. Include duplicate-valued objects to
prove identity, Unicode/numeric map keys around array paths, empty arrays,
multi-node ranges, safe-integer rejection, and malformed or incomplete move
metadata. Refusal tests must distinguish a valid newly supported array from
an unsupported sequence field placement or corrupt sequence payload.

M3 must retain the M1/M2 deterministic and seeded coverage. Add 100 required
array schedules to the existing 200 object/map schedules rather than reducing
their allocation. The default becomes 300 schedules, with seed `42`.
Generate and replay one schedule from explicit `(seed, index, profile)` input.
Do not infer its profile from a truncated iteration total. Regenerate the
supported profile through the existing preflight path before M3 acceptance;
an acceptance report cannot use profile bytes that still exclude arrays.

## 9. Review gates

Task 1 provides the source evidence for the executable oracle contract. Review
that output before Tasks 2 onward:
schema bytes, counted deltas, Sequence V3 forms, move-effect dependencies,
no-op behavior, error behavior, and the native module signatures.

M3 acceptance remains blocked until the input-only native runners pass on both
targets and the remaining review gates in this section are complete.

If the oracle requires additional internal semantics to support the listed
public operations, include them before proceeding. If it requires a profile
change or a public scope change, obtain approval and revise both documents.
Do not replace missing evidence with hard-coded expected output.

M4 schema work and M7 facade consumers can proceed independently only with
agreed ownership of schema, change dispatch, codecs, and runtime files. This
plan uses one dependency-ordered integration lane and does not schedule those
other milestones.
