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

## Fix Round 1

### Status

BLOCKED. The false transaction observation was removed, but the pinned codec
cannot round-trip either captured message unchanged.

### Changes

- `transaction_fixture.run_wire/1` now passes the supplied nonviolated and
  violated message bytes unchanged to `codec.decode_message/2`.
- The runner no longer removes `builds` or `refreshers`.
- The runner no longer compares only `changes` and `violations`.
- The runner returns the actual `codec.encode_message/2` JSON and
  `json.to_string/1` bytes for both variants.
- The exact-output test now compares encoder-produced JSON and bytes with both
  captured variants.
- Added a noncanonical-input regression that requires the observation to come
  from the encoder instead of echoing input bytes.

### Investigation

The first full decode fails before stored-schema classification:

```text
UnsupportedFeature("message.changeset[0].data.builds.trees", "identifier values")
```

The captured FieldBatch uses `{"type":0,"value":0}` for the `Point.id`
identifier field. `field_batch.decode_value/3` rejects `IdentifierValue`.
Correct decoding needs the message compressor to convert the session-space
integer through `fluid_ids.decompress/2`, but `field_batch.decode_with_schema/2`
accepts only the encoded value and optional stored schema.

Encoding is also insufficient for exact bytes. `field_batch.encode_with_schema/2`
only validates node kinds and then calls `field_batch.encode/1`, which always
emits the generic uncompressed shape table with an empty `identifiers` array.
It cannot reproduce the captured indexed identifiers, identifier-value shape,
or compressed shape table. Adding schema alone does not supply either missing
capability.

### Commands and output

No-echo regression before the runner change:

```bash
gleam test --target erlang -- --test-name-filter=shared_tree_transaction_wire_rejects_noncanonical_bytes_test
```

Output:

```text
FAIL shared_tree_transaction_wire_rejects_noncanonical_bytes_test
Expected Ok(...) to be Error
Tests: 1 failed (1)
```

Full unchanged-message probe after the runner change:

```bash
gleam test --target erlang -- --test-name-filter=shared_tree_transaction_wire_observes_constraints_and_exact_bytes_test
```

Output:

```text
FAIL shared_tree_transaction_wire_observes_constraints_and_exact_bytes_test
UnsupportedFeature("message.changeset[0].data.builds.trees", "identifier values")
Tests: 1 failed (1)
```

Focused dual-target transaction and codec matrix:

```bash
gleam test --target erlang -- shared_tree_transaction shared_tree_codec
gleam test --target javascript -- shared_tree_transaction shared_tree_codec
```

Output on each target:

```text
Tests: 25 passed | 3 failed (28)
```

The three failures are
`shared_tree_transaction_wire_decodes_constraints_test`,
`shared_tree_transaction_wire_observes_constraints_and_exact_bytes_test`, and
`shared_tree_transaction_wire_rejects_noncanonical_bytes_test`. Each fails on
the same unsupported FieldBatch identifier-value capability. Direct pinned V5
constraint codec coverage still passes on both targets.

### Self-review

- Confirmed no fixture message JSON or byte string is returned as an
  observation.
- Confirmed both supplied variants are decoded without mutation before any
  encoding attempt.
- Confirmed both output JSON values and byte strings come directly from
  `codec.encode_message/2`.
- Confirmed the compressor mutation check remains in place.
- Confirmed the failure is not solved by the existing stored-schema helpers:
  decoding needs compressor-aware identifier values, and exact encoding needs
  the captured compressed FieldBatch representation or an equivalent encoder.
- Did not broaden the constraint batch into compressor-aware, byte-stable
  FieldBatch codec work.

## Fix Round 2

### Status

PASS. The runner now decodes the supported normalized payload and returns only
the actual `codec.encode_message` JSON and serialized bytes.

### Changes

- The runner parses each captured message and removes only `builds` and
  `refreshers` before decode.
- Constraint observations still come from the decoded native `ChangeData`.
- The `message` and `messageBytes` observations come directly from
  `codec.encode_message` and `json.to_string`.
- Tests independently normalize the captured messages, preserve their property
  order for exact byte assertions, and compare encoder output with those
  normalized expected values.
- The noncanonical-input test remains and now proves that returning input bytes
  would fail.
- Sequence marks now encode in the captured upstream order: `count`, `effect`,
  then `cellId`. This was required for exact bytes after FieldBatch
  normalization and is covered by the existing upstream array codec fixture.

### Deliberate FieldBatch normalization

The captured `builds` and `refreshers` contain identifier values that the
current FieldBatch codec cannot decode without compressor-aware identifier
support. Reproducing those sections byte-for-byte also requires the compressed
shape-table encoder that is not part of this constraint codec slice. The
controller ruling therefore keeps that separate work out of scope: this runner
removes only those unsupported members and exercises the complete supported
Message V7, SharedTreeChange V5, and ModularChange V5 constraint payload.

### Commands and output

Normalized expectation before the runner fix:

```bash
gleam test --target erlang -- --test-name-filter=shared_tree_transaction_wire_observes_constraints_and_exact_bytes_test
```

Output:

```text
FAIL shared_tree_transaction_wire_observes_constraints_and_exact_bytes_test
UnsupportedFeature("message.changeset[0].data.builds.trees", "identifier values")
Tests: 1 failed (1)
```

Runner normalization before canonical Sequence mark ordering:

```bash
gleam format test/watershed/tree/transaction_fixture.gleam test/watershed/shared_tree_transaction_test.gleam && gleam test --target erlang -- --test-name-filter=shared_tree_transaction_wire_
gleam test --target javascript -- --test-name-filter=shared_tree_transaction_wire_
```

Output on each target:

```text
Tests: 4 passed | 2 failed (6)
```

The two failures were the exact-byte and noncanonical-input tests. Both showed
the encoder's `effect`, `count`, `cellId` order differed from the captured
upstream `count`, `effect`, `cellId` order.

Focused Erlang transaction and codec suites:

```bash
gleam test --target erlang -- shared_tree_transaction shared_tree_codec shared_tree_codec_fixture shared_tree_array_codec
```

Output:

```text
Test Files: 4
Tests: 36 passed (36)
```

Focused JavaScript transaction and codec suites:

```bash
gleam test --target javascript -- shared_tree_transaction shared_tree_codec shared_tree_codec_fixture shared_tree_array_codec
```

Output:

```text
Test Files: 4
Tests: 36 passed (36)
```

Diff validation:

```bash
git diff --check
```

Output: no output, exit 0.

The focused commands retain the pre-existing unused private fixture helper
warnings. The JavaScript command also retains the pre-existing unsafe-integer
warnings from array-kernel tests. This fix adds no warning.

Full repository gate:

```bash
just test
```

Output:

```text
source_snippets               ok
watershed                     ok
shared_tree_cli               ok
watershed_lustre              ok
drum_machine_lustre           FAILED
grocery_triptych_lustre       FAILED
json_workspace_lustre         FAILED
project_room_lustre           FAILED
retro_board_lustre            FAILED
retro_tutorial_lustre         FAILED
shared_tree_checklist_lustre  FAILED
```

Each failed example stopped during dependency resolution with:

```text
error: Hex API failure
The rate limit for the Hex API has been exceeded
```

The repository package and all focused transaction/codec packages completed
successfully before the external Hex rate-limit failure.

### Self-review

- Confirmed the runner never returns fixture message JSON or byte strings.
- Confirmed both output variants come from the encoder after normalized decode.
- Confirmed the expected JSON and bytes are independently derived from the
  captured input by removing only `builds` and `refreshers`.
- Confirmed the anti-echo test changes insignificant input whitespace and
  requires canonical encoder bytes.
- Confirmed compressor serialization is unchanged before and after each
  decode/encode operation.
- Confirmed no fixture JSON, dependency manifest, generated file, `.code-map`,
  or apm-managed file changed.
