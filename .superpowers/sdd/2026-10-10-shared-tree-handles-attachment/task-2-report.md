# Task 2 report: typed SharedTree handle leaves

## Status

Complete.

Implementation commit: `ffe6c50e` (`feat(tree): support Fluid handle leaves`)

The implementation preserves the Fluid 3.1.0 checkout and all existing codec
version pins. It does not add SDK production dependencies, change lockfiles,
edit generated or pinned fixture files, or publish a native lifecycle profile.

## Interfaces and behavior

### Pure references

`src/watershed/handle.gleam` now provides an opaque `Reference` and these public
functions:

- `reference_from_path`
- `reference_from_json`
- `reference_path`
- `reference_to_json`
- `bind_serialized_references`

A reference stores only a normalized absolute datastore/channel path. It does
not contain an SDK object, callback, promise, or runtime resolver.

`reference_from_path` accepts absolute datastore/channel paths such as
`/B/child`. It rejects incomplete paths, external URLs, traversal components,
malformed percent escapes, empty components, malformed markers, and unsupported
payloads.

`reference_from_json` uses the supplied source datastore context to resolve
legacy relative markers. The same `_C` marker resolves to `/A/_C` under `/A`
and `/B/_C` under `/B`. Context-free parsing returns the explicit error
`relative handle requires source-channel context`.

`bind_serialized_references` recursively traverses objects and arrays. It
normalizes genuine `__fluid_handle__` markers and leaves unrelated objects
unchanged. Any malformed marker, including one at the end of a nested payload,
fails the complete operation.

### Tree model and schema

- `TreeValue` has `HandleValue(handle.Reference)`.
- Public schemas have `HandleLeaf`.
- Fluid leaf code `3` maps to `HandleLeaf`.
- The canonical identifier is `com.fluidframework.leaf.handle`.
- Handle leaves participate in stored/view conversion, compatibility,
  allowed-superset checks, validation, and supported-profile checks.
- A handle leaf remains distinct from a string leaf.
- A leaf code and identifier mismatch remains an invalid schema.

### Forest, identifiers, and codecs

Handle values are retained by forest import/export and retained-value
validation. Identifier traversal treats them as identifier-neutral leaves.

FieldBatch support covers:

- uncompressed encoding and decoding;
- schema-aware compressed encoding and decoding;
- required and optional fields;
- object fields;
- map entries;
- array elements;
- build and refresher payloads;
- detached and retained forests;
- repair data;
- edit-manager history replay.

Pure FieldBatch decoding accepts absolute markers. A relative marker fails with
`CorruptData` at the handle location and the explicit source-context message.
Pending payloads fail as `UnsupportedHandle("pending handle payload")`.
Malformed leaf contents and wrong stored-schema kinds report their precise
`CorruptData` location.

The compressed encoder gained nested-array and extra-field shapes needed by the
pinned schema-aware capture. Shape discovery orders nested shapes first, which
reproduces the captured handle fixture indices and streams.

## Files

Production:

- `src/watershed/handle.gleam`
- `src/watershed/tree/types.gleam`
- `src/watershed/tree/schema.gleam`
- `src/watershed/tree/forest.gleam`
- `src/watershed/tree/identifier.gleam`
- `src/watershed/tree/codec/field_batch.gleam`

Tests and fixture consumers:

- `test/watershed/shared_tree_handle_test.gleam`
- `test/watershed/shared_tree_field_batch_test.gleam`
- `test/watershed/shared_tree_schema_evolution_test.gleam`
- `test/watershed/shared_tree_schema_test.gleam`
- `test/watershed/tree/array_change_fixture.gleam`
- `test/watershed/tree/array_codec_fixture.gleam`
- `test/watershed/tree/array_schema_fixture.gleam`
- `test/watershed/tree/change_fixture_codec.gleam`
- `test/watershed/tree/client_protocol.gleam`
- `test/watershed/tree/codec_export.gleam`
- `test/watershed/tree/document_summary_fixture.gleam`
- `test/watershed/tree/fixtures.gleam`
- `test/watershed/tree/identifier_fixture.gleam`
- `test/watershed/tree/kernel_fixture.gleam`
- `test/watershed/tree/map_forest_fixture.gleam`
- `test/watershed/tree/schema_evolution_fixture.gleam`
- `test/watershed/tree/transaction_fixture.gleam`

Every exhaustive fixture/client value consumer now handles the tagged
`{"kind":"handle","value":marker}` representation. The old canonical
unsupported-handle cases were removed. Unknown semantic kinds, mismatched leaf
identifiers, and identifier-node boundaries remain refusals.

## TDD evidence

### RED

The canonical schema/FieldBatch test and reference tests were added before
production support.

After correcting a test-only import typo, both required commands produced a
genuine compilation RED:

```text
gleam test --target erlang -- shared_tree_handle
exit 1: missing Reference, HandleValue, HandleLeaf, and reference functions

gleam test --target javascript -- shared_tree_handle
exit 1: missing Reference, HandleValue, HandleLeaf, and reference functions
```

These failures were caused by absent production interfaces, not invented
fixture observations or weakened expectations.

### GREEN

Final focused selections:

```text
gleam test --target erlang -- shared_tree_handle shared_tree_schema shared_tree_codec
94 passed, 0 failed

gleam test --target javascript -- shared_tree_handle shared_tree_schema shared_tree_codec
95 passed, 0 failed
```

Required upstream checks:

```text
just shared-tree-codec-interop
SharedTree codec interoperability passed: 2 targets, 38 items each

just shared-tree-oracle-check
7 lifecycle probes passed
Verified 68 upstream SharedTree cases
```

Final format/lint check:

```text
just lint
git ls-files -z '*.gleam' | xargs -0 gleam format --check
exit 0
```

`just format` stalled while Trellis was running. It was stopped. The changed
Gleam files were formatted directly, and the repository format check above
passed.

The pre-task unchanged baseline was:

```text
just shared-tree-test
passed

Node tests
62 passed
```

## Fixture and corpus evidence

The existing pinned
`test/fixtures/shared_tree/cases/handle-leaves.json` capture was not edited.
The new tests decode its tagged native values and replay its exact source-backed
observations through production schemas, codecs, tree state, and edit APIs.

Coverage includes:

1. required-root initialization;
2. optional root set;
3. optional root clear;
4. object field set;
5. map entry set;
6. array insertion.

The tests preserve both checks:

- native tagged-value round trips; and
- structural comparison with captured uncompressed and schema-aware FieldBatch
  payloads, including shape indices, value streams, and handle marker paths.

The oracle check confirms all seven lifecycle probes and all 68 pinned upstream
cases. Its expected active-target disconnect stack trace is diagnostic output;
the command exits successfully.

## Self-review

- Reviewed all exhaustive `TreeValue` and leaf-kind consumers identified by the
  compiler.
- Confirmed handle and string schemas cannot match through leaf code alone.
- Confirmed pure decoding never performs runtime resolution.
- Confirmed relative paths require an explicit source datastore context.
- Confirmed a late malformed marker fails recursive normalization atomically.
- Confirmed compressed and uncompressed payloads preserve absolute marker
  paths.
- Confirmed fixture execution uses production schema, codec, forest, state, and
  edit paths rather than expected-only data.
- Ran `git diff --check`; it passed.
- Reviewed the changed-file list and found no dependency, lock, generated
  fixture, pinned checkout, apm-managed, or Task 3 lifecycle-profile changes.

## Known warnings and unresolved gaps

Existing warnings remain unchanged:

- two unused private functions in `test/watershed/tree/codec_export.gleam`;
- JavaScript unsafe-integer warnings from pinned fixtures;
- two unused private functions in map façade tests.

There are no known Task 2 gaps. Native attachment lifecycle publication remains
out of scope for this task and was not started.

## Corrective follow-up: zero-width nested arrays

### Root cause

The compressed encoder represented every nested array as
`VArray(child_data)`. That representation is length-delimited by consumed
stream values. A null leaf and an empty structural node consume no values, so
one present optional item and any number of array items all encoded as the same
empty array. The decoder correctly interpreted that empty stream as zero
items.

The shared encoder now uses the FieldBatch integer-count form when a non-empty
nested collection has zero encoded width. It keeps the source-compatible array
form for value-consuming children and empty collections. The fix applies to
optional and sequence fields, array-node contents, handle-activated
compression, and identifier-activated compression without checking for a
specific leaf or node kind.

### RED

The regressions were added before the production change. Both targets
reproduced the data loss:

```text
gleam test --target erlang -- shared_tree_field_batch
35 passed, 2 failed

shared_tree_codec_field_batch_round_trips_zero_width_null_fields_test
received: items = [], optional field absent
expected: items = [NullValue, NullValue], optional field = NullValue

shared_tree_codec_field_batch_round_trips_zero_width_structures_test
received: items = [], optional field absent
expected: two Empty nodes and one present optional Empty node

gleam test --target javascript -- shared_tree_field_batch
35 passed, 2 failed
```

The first regression uses a handle-bearing object. The second uses an
identifier field to activate the compressed path and proves the problem is
structural, not specific to null leaves.

### GREEN

Final focused selections:

```text
gleam test --target erlang -- shared_tree_handle shared_tree_field_batch shared_tree_schema shared_tree_codec
131 passed, 0 failed

gleam test --target javascript -- shared_tree_handle shared_tree_field_batch shared_tree_schema shared_tree_codec
132 passed, 0 failed
```

Required upstream checks:

```text
just shared-tree-codec-interop
SharedTree codec interoperability passed: 2 targets, 38 items each

just shared-tree-oracle-check
7 passing
Verified 68 upstream SharedTree cases
```

Formatting and diff checks:

```text
git diff --check
exit 0

git ls-files -z '*.gleam' | xargs -0 gleam format --check
exit 0
```

### Corrective self-review

- Confirmed the failure on Erlang and JavaScript before changing production
  code.
- Confirmed the shared cause at both nested-array encoder sites and the existing
  integer-count decoder path.
- Used one generic encoding helper. It does not special-case null or handles.
- Confirmed optional nulls, null arrays, optional empty objects, and arrays of
  empty objects retain their cardinality.
- Confirmed identifier-only schemas use the corrected compressed path.
- Kept `VArray(data)` for value-consuming children and for empty collections,
  preserving genuine source encoding.
- Re-ran the pinned handle schema-aware payload comparison through the focused
  handle tests.
- Reviewed the diff: two source/test files plus this report; no dependencies,
  profile changes, generated files, or fixture edits.
- Did not start Task 3.
