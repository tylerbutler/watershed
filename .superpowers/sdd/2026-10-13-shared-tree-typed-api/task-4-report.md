# Task 4 report: typed SharedTree facade

## Result

Implemented the typed application facade on JavaScript and BEAM. The public
tree handle is now `SharedTree(schema, record)`, with typed `TreeNode`,
`TreeArray`, and `TreeMap` handles. No parallel `TypedTree`, `tree_typed_*`,
or public raw edit family was added.

The facade now carries its schema definition through resolve, open, create,
fork, transactions, subscriptions, branches, revertibles, and channel-field
resolution. Reads and writes validate the runtime view, node owner, field
cardinality, allowed identifiers, checkout, and handle origin before access.
Collection reads decode one captured snapshot and fail on malformed members.

## RED

Before implementation:

- `gleam test --target javascript -- shared_tree_typed_` failed because the
  typed facade types and operations did not exist.
- `gleam test --target erlang -- shared_tree_typed_` failed for the same
  missing BEAM interfaces.
- The four new negative fixtures initially demonstrated the old or incomplete
  signatures rather than the required schema/value/cardinality guarantees.

During migration, the targeted runtime suite found a real adapter regression:
identifier fields were treated as structural children. The test failed with
`field is not a structural child: id`. The test-only facade adapter now reads
identifier, leaf, child, and map fields through the matching typed descriptor.

## GREEN

Final verification:

```text
gleam check --target javascript
Compiled

gleam check --target erlang
Compiled

gleam test --target javascript -- shared_tree_typed_ shared_tree_array_facade shared_tree_map_facade shared_tree_creation
53 passed

gleam test --target erlang -- shared_tree_typed_ shared_tree_array_facade shared_tree_map_facade shared_tree_creation
55 passed

gleam test --target javascript -- shared_tree_runtime_js sluice_driver_js
22 passed

gleam test --target erlang -- shared_tree_runtime_beam
48 passed

gleam test --target javascript -- sluice
91 passed

just _test-compile-fail
10 expected failures accepted, including all eight new target/package checks
```

The existing suite still emits unrelated warnings for unreachable patterns,
JavaScript unsafe-integer test literals, empty target-specific modules, and
unused private test helpers.

## Typed behavior covered

- Required and optional field reads and writes.
- Present null versus absent optional fields.
- Handle leaf decoding.
- Structural child capture and mutation.
- Identifier reads and generated identifier construction.
- Array and map reads, insertion, setting, deletion, movement, and node
  identity.
- Runtime rejection of a declaration with the correct phantom owner but the
  wrong leaf type.
- Optional and required singleton roots, plus array, map, and leaf roots.
- Runtime schema mismatch, incompatible inspection, explicit upgrade,
  transactions, branches, subscriptions, revertibles, reload, closed
  documents, foreign views/origins, and malformed remote values through the
  migrated facade suites.
- Creation validation before allocation or network submission.

## Files

Facade and descriptors:

- `src/watershed.gleam`
- `src/watershed_beam.gleam`
- `src/watershed/tree/typed.gleam`

Tests and adapters:

- `test/watershed/shared_tree_typed_facade_test.gleam`
- `test/watershed/tree/facade_fixture.gleam`
- `test/watershed/tree/typed_facade_fixture.gleam`
- `test/watershed/shared_tree_array_facade_test.gleam`
- `test/watershed/shared_tree_map_facade_test.gleam`
- `test/watershed/shared_tree_creation_api_test.gleam`
- `test/watershed/shared_tree_creation_probe.gleam`
- `test/watershed/shared_tree_runtime_js_test.gleam`
- `test/watershed/shared_tree_runtime_beam_test.gleam`
- `test/watershed/sluice/driver_js_test.gleam`
- `test/watershed/tree/client_js.gleam`
- `test/watershed/tree/client_beam.gleam`

Compile-fail harness:

- `justfile`
- `tools/compile-fail/typed_tree_wrong_schema/`
- `tools/compile-fail/typed_tree_wrong_value/`
- `tools/compile-fail/typed_tree_required_clear/`
- `tools/compile-fail/shared_tree_raw_edit/`

## Concerns and follow-up

- This is an intentionally breaking application API. The Lustre, example, and
  website-runtime consumers remain for Tasks 5 and 6, as required.
- `typed.NodeCodec` now records all allowed runtime identifiers internally so
  supported union collections can validate actual member owners. Public
  constructors still create the contracted singleton declarations.
- The raw oracle operation shape is preserved only in the test adapter. There
  is no public escape hatch.
- Protocol and kernel machinery were not changed.

## Important finding fix wave

All five Important findings from `task-4-review-report.md` are fixed.

- Collection declarations now require the same complete identifier set and
  cardinality as the codec, independent of identifier order. This applies to
  array/map fields and `tree_as_array`/`tree_as_map`.
- The test oracle creation adapters validate and preserve the supplied stored
  schema. Exact typed inputs still use the public typed constructors. Compatible
  raw oracle inputs that cannot be represented by those constructors use the
  existing lower runtime creation APIs, then reacquire the typed handle. Invalid
  schema/view pairs fail before allocation.
- Empty adapter inserts now build from the declared collection item set and
  reach the native operation, preserving valid-gap no-op and invalid-gap
  validation behavior.
- JavaScript and BEAM adapter errors now pass typed facade errors through the
  same `typed_error` helper.
- Both direct typed target tests now call `tree_array_remove_node` and
  `tree_array_move_before`. They cover equal decoded siblings, cross-parent
  movement, removed/replaced array and map nodes, root/child/collection stale
  handles, foreign runtime/channel/checkout handles, strict-view mismatch,
  closed and independently reacquired documents, optional children, handles,
  generated identifiers, root array/map/leaf access, and typed root
  replacement/required-root clear.

### RED

The named tests failed against `89cad496` for the intended reasons:

```text
gleam test --target javascript -- shared_tree_typed_
21 passed | 1 failed
shared_tree_typed_collection_declarations_require_complete_item_set_test:
Expected Ok(Nil) to be Error

gleam test --target javascript -- shared_tree_array_facade
4 passed | 1 failed
shared_tree_array_facade_js_operations_test:
Expected Error("collection insert is empty") to equal Ok(Nil)

gleam test --target erlang -- shared_tree_array_facade
4 passed | 1 failed
shared_tree_array_facade_beam_operations_test:
Expected Error("collection insert is empty") to equal Ok(Nil)
```

The new stored-schema mismatch assertions in both detached lifecycle suites
also distinguish the supplied schema from the view-derived schema and require
unchanged runtime observations before allocation.

### GREEN

Exact final commands and results:

```text
gleam test --target javascript -- shared_tree_typed_
22 passed

gleam test --target erlang -- shared_tree_typed_
21 passed

gleam test --target javascript -- shared_tree_array_facade
5 passed

gleam test --target erlang -- shared_tree_array_facade
5 passed

gleam test --target javascript -- shared_tree_map_facade
17 passed

gleam test --target erlang -- shared_tree_map_facade
18 passed

gleam test --target javascript -- shared_tree_creation
10 passed

gleam test --target erlang -- shared_tree_creation
12 passed

gleam test --target javascript -- shared_tree_runtime_js
22 passed

gleam test --target erlang -- shared_tree_runtime_beam
48 passed

just _test-compile-fail
10 expected failures accepted

git diff --check
exit 0
```

Formatting:

```text
gleam format src/watershed/tree/typed.gleam \
  test/watershed/shared_tree_typed_schema_test.gleam \
  test/watershed/shared_tree_typed_facade_test.gleam \
  test/watershed/shared_tree_array_facade_test.gleam \
  test/watershed/shared_tree_runtime_js_test.gleam \
  test/watershed/shared_tree_runtime_beam_test.gleam \
  test/watershed/tree/facade_fixture.gleam \
  test/watershed/tree/typed_facade_fixture.gleam
exit 0
```

### Concerns

- Verification still emits the pre-existing unreachable-pattern,
  JavaScript-safe-integer, and unused-private-helper warnings listed above.
- The untracked `docs/superpowers/plans/2026-10-13-shared-tree-typed-api.md`
  present before this fix wave was not modified or included.

## Fix round 2: traversal error parity

The test adapter now sends every typed facade error from captured map and array
traversal through `typed_error`. Schema lookup errors and other existing
low-level string errors keep their prior conversion.

### RED

The new stale captured-map traversal assertions failed on both targets before
the conversion fix:

```text
gleam test --target javascript -- shared_tree_map_facade
17 passed | 1 failed
shared_tree_map_facade_js_stale_traversal_unwraps_access_error_test:
Expected Error("AccessFailed(reason: \"TreeOperationFailed(address: \\\"A/_C\\\", error: InvalidEdit(path: [], detail: \\\"node is not attached\\\"))\")")
to equal Error("TreeOperationFailed(address: \"A/_C\", error: InvalidEdit(path: [], detail: \"node is not attached\"))")

gleam test --target erlang -- shared_tree_map_facade
18 passed | 1 failed
shared_tree_map_facade_beam_stale_traversal_unwraps_access_error_test:
Expected Error("AccessFailed(\"TreeOperationFailed(\\\"A/_C\\\", InvalidEdit([], \\\"node is not attached\\\"))\")")
to equal Error("TreeOperationFailed(\"A/_C\", InvalidEdit([], \"node is not attached\"))")
```

The assertions now live in the focused
`shared_tree_map_facade_*_stale_traversal_unwraps_access_error_test` cases and
expect each runtime's existing low-level reason without the `AccessFailed`
constructor.

### GREEN

Exact covering commands and results:

```text
gleam test --target javascript -- shared_tree_array_facade shared_tree_map_facade shared_tree_runtime_js
Test Files: 3
Tests: 45 passed (45)

gleam test --target erlang -- shared_tree_array_facade shared_tree_map_facade shared_tree_runtime_beam
Test Files: 3
Tests: 72 passed (72)

gleam format test/watershed/tree/facade_fixture.gleam test/watershed/shared_tree_map_facade_test.gleam
exit 0

git diff --check
exit 0
```

The commands emitted the same pre-existing unreachable-pattern,
JavaScript-safe-integer, unused-private-helper, and expected rescued callback
diagnostic output described above.
