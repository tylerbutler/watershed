# SharedTree constraint wire Tasks 1-3 report

## Status

Complete. Tasks 1, 2, and 3 were implemented in order as one TDD batch. The
branch was committed only after the focused Erlang and JavaScript suites were
green.

## Implementation

### Task 1: input-only transaction wire runner

- Added `watershed/tree/transaction_fixture.run_wire/1`.
- Loads only the `transaction-wire` fixture input supplied by the caller.
- Requires exactly the top-level `messageBytes`, `compressor`, `context`,
  `operands`, and `scenarios` sections.
- Requires one `modular-v5-shared-tree-v5` scenario and the pinned Message V7,
  SharedTreeChange V5, ModularChange V5, and `2.117.0` context.
- Parses and validates every serialized compressor with its declared session
  ID, including the `over` compressor that is not observed in this execution
  unit.
- Decodes the nonviolated and violated message changes, extracts one
  `DataChange`, and derives violation counts and node constraints from native
  state.
- Verifies the codec-owned `changes` and `violations` sections after encoding,
  checks compressor serialization before and after, and preserves the original
  opaque FieldBatch `builds` and `refreshers` bytes.
- Added strict missing-section, unknown-context, malformed-compressor, native
  observation, and exact-byte tests.

### Task 2: native constraint data model

- Added `NodeExistsConstraint(violated: Bool)`.
- Expanded `NodeChange` with `node_exists_constraint` and
  `node_exists_constraint_on_revert`.
- Expanded `ChangeData` with `constraint_violation_count`.
- Migrated all compiling source and test constructors to explicit defaults.
- Preserved native node constraint fields when existing node records are
  rebuilt.
- Kept constraint-only nodes during pruning.
- Added the structural invariant that the aggregate count cannot be negative.
- Did not add constraint algebra, target resolution, transaction state, runtime
  integration, or public APIs.
- Extended normalized fixture state parsing and encoding for the new keys while
  retaining the legacy normalized fixture shape when constraints are absent.

### Task 3: pinned ModularChange V5 codec support

- Decodes absent `violations` as zero and nonnegative present values into
  native state.
- Continues to reject `noChangeConstraint`.
- Strictly decodes `nodeExistsConstraint` as an object containing only the
  Boolean `violated` member.
- Sets `node_exists_constraint_on_revert` to `None` on pinned V5 decode.
- Encodes `nodeExistsConstraint` for field-bearing and constraint-only node
  changes.
- Does not encode `node_exists_constraint_on_revert`.
- Encodes aggregate `violations` only when nonzero, preserving existing bytes
  when constraints are absent.
- Added direct pinned V5 coverage for strict decoding, constraint-only nodes,
  nonzero and zero aggregate counts, and omission of the native-only revert
  field.

## Files changed

- `src/watershed/tree/change.gleam`
- `src/watershed/tree/codec.gleam`
- `test/watershed/shared_tree_array_change_test.gleam`
- `test/watershed/shared_tree_change_fixture_test.gleam`
- `test/watershed/shared_tree_change_test.gleam`
- `test/watershed/shared_tree_codec_fixture_test.gleam`
- `test/watershed/shared_tree_codec_test.gleam`
- `test/watershed/shared_tree_map_change_test.gleam`
- `test/watershed/shared_tree_shared_change_test.gleam`
- `test/watershed/shared_tree_transaction_test.gleam`
- `test/watershed/tree/array_change_fixture.gleam`
- `test/watershed/tree/change_fixture_codec.gleam`
- `test/watershed/tree/codec_export.gleam`
- `test/watershed/tree/map_change_fixture.gleam`
- `test/watershed/tree/schema_evolution_fixture.gleam`
- `test/watershed/tree/transaction_fixture.gleam`

No generated fixture JSON, `.code-map`, dependency manifest, or apm-managed
file was changed.

## TDD evidence

### RED

1. Task 1 missing runner:

   ```bash
   gleam test --target erlang -- --test-name-filter=shared_tree_transaction_wire_
   ```

   Result: compilation failed with `Unknown module` for
   `watershed/tree/transaction_fixture`, as required.

2. Task 1 source-backed constraint decode:

   ```bash
   gleam test --target erlang -- --test-name-filter=shared_tree_transaction_wire_decodes_constraints_test
   gleam test --target javascript -- --test-name-filter=shared_tree_transaction_wire_decodes_constraints_test
   ```

   Result on both targets: failed because
   `nodeExistsConstraint` was reported as unsupported.

3. Task 2 model test:

   ```bash
   gleam test --target erlang -- --test-name-filter=shared_tree_change_constraint_data_round_trips_test
   ```

   Result: compilation failed because `NodeChange` still accepted one argument
   and `ChangeData` had no `constraint_violation_count` field.

4. Task 3 encoding test after decode support:

   ```bash
   gleam test --target erlang -- --test-name-filter=shared_tree_transaction_wire_decodes_constraints_test
   ```

   Result: failed with `encoded transaction changes differ from input`, proving
   that decode was active while constraint encoding was still absent.

### GREEN

Task 1 validation harness:

```bash
gleam test --target erlang -- --test-name-filter=shared_tree_transaction_wire_requires_input_sections_test
gleam test --target javascript -- --test-name-filter=shared_tree_transaction_wire_requires_input_sections_test
```

Result: 1 passed on each target.

Task 2 native model:

```bash
gleam test --target erlang -- --test-name-filter=shared_tree_change_constraint_data_round_trips_test
```

Result: 1 passed.

Task 3 source-backed decode and encode:

```bash
gleam test --target erlang -- --test-name-filter=shared_tree_transaction_wire_decodes_constraints_test
gleam test --target javascript -- --test-name-filter=shared_tree_transaction_wire_decodes_constraints_test
```

Result: 1 passed on each target.

Exact observations and bytes:

```bash
gleam test --target erlang -- --test-name-filter=shared_tree_transaction_wire_observes_constraints_and_exact_bytes_test
gleam test --target javascript -- --test-name-filter=shared_tree_transaction_wire_observes_constraints_and_exact_bytes_test
```

Result: 1 passed on each target.

Direct pinned V5 codec coverage:

```bash
gleam test --target erlang -- --test-name-filter=shared_tree_codec_constraints_round_trip_pinned_v5_test
gleam test --target javascript -- --test-name-filter=shared_tree_codec_constraints_round_trip_pinned_v5_test
```

Result: 1 passed on each target.

Final focused matrix:

```bash
gleam format src test
gleam test --target erlang -- shared_tree_transaction shared_tree_change shared_tree_codec shared_tree_codec_fixture
gleam test --target javascript -- shared_tree_transaction shared_tree_change shared_tree_codec shared_tree_codec_fixture
```

Result:

- Erlang: 105 passed, 0 failed.
- JavaScript: 105 passed, 0 failed.
- `git diff --check`: passed.

The test output still contains pre-existing warnings for two unused private
fixture-export helpers and JavaScript unsafe-integer literals in array-kernel
tests. No new warning was introduced by this batch.

## Commit

- `765aa26f9f1cd1b803e6f510eacc362b591a9dd4`
  `feat(tree): decode transaction constraints`

The implementation commit is a green state and includes the required
co-author trailer.

## Self-review

- Confirmed all `NodeChange` and direct `ChangeData` construction sites under
  `src` and `test` compile with explicit defaults.
- Confirmed record rebuilds preserve native constraint fields where no
  constraint algebra is performed.
- Confirmed constraint-only nodes survive pruning and encode as
  `{"nodeExistsConstraint":{"violated":false}}` or the corresponding true
  value.
- Confirmed zero aggregate counts omit `violations`.
- Confirmed native-only revert constraints survive native fixture
  normalization and are omitted from pinned V5 wire encoding.
- Confirmed strict constraint objects reject extra members.
- Confirmed all three serialized fixture compressors are validated.
- Confirmed the diff does not include generated fixture JSON, `.code-map`,
  dependency changes, or apm-managed files.

The review found two gaps before the final verification: the `over` compressor
was not parsed, and normalized fixture state defaulted the new fields without
accepting their explicit JSON representation. Both were fixed and covered
before the implementation commit.

## Concerns

The transaction fixture contains FieldBatch identifier values that the current
restricted FieldBatch codec does not decode. This execution unit keeps that
unrelated limitation outside scope: the runner removes only `builds` and
`refreshers` while exercising the native transaction constraint codec, verifies
the re-encoded `changes` and `violations` sections, and preserves those opaque
FieldBatch bytes exactly. Full identifier-aware FieldBatch decoding remains a
separate concern and was not added here.
