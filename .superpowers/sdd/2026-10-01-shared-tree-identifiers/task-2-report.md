# Task 2 report: Identifier schema, immutability, and no-change algebra

## Implemented scope

- Added `schema.Identifier` as a distinct public cardinality and preserved the
  persisted `"Identifier"` field kind through Schema V2 decode and round trip.
- Enabled the native Identifier profile only for named object fields whose
  sole allowed type is `com.fluidframework.leaf.string`.
- Kept Identifier root, map, array-primary, non-string, union, handle, unknown,
  and other excluded schemas outside the native profile. Comparison decoding
  still accepts excluded schemas for compatibility analysis.
- Required persisted Identifier content to contain one string value. Missing
  and non-string content returns a typed validation error.
- Allowed Identifier-to-Value widening, rejected Value-to-Identifier
  narrowing, and allowed a wider Value view to read an active stored
  Identifier schema without gaining mutation rights.
- Rejected direct Identifier set, same-value set, and clear operations in
  `edit_destination` before change allocation. Kept an exhaustive
  `authored_field` rejection as a second invariant.
- Preserved containing-object replacement, explicit custom strings, duplicate
  custom strings on distinct nodes, node-reference identity, history,
  compressor state, events, and no-commit transaction restoration.
- Added `change.IdentifierField` as a zero-argument no-change field handler.
  Its canonical V1 encoding is `0`; native decode rejects every nonzero or
  nonnumeric payload.
- Implemented IdentifierField validation, revision traversal, delta,
  inversion, composition, rebase, pruning, revision replacement, muting,
  ownership, and fixture serialization. It allocates no atoms and emits no
  delta. Empty generic paths compose/rebase as no-change; concrete generic
  edits and mutable field-kind combinations are rejected.

This task does not implement contextual numeric FieldBatch identifiers or
Identifier default generation. Those remain owned by later tasks.

## TDD evidence

### RED: schema preservation

Commands:

```text
gleam test --target erlang -- shared_tree_identifier shared_tree_schema
gleam test --target javascript -- shared_tree_identifier shared_tree_schema
```

Both targets failed before production changes with:

```text
The module `watershed/tree/schema` does not have a `Identifier` value.
```

### RED: immutable local destination

Command:

```text
gleam test --target erlang -- shared_tree_identifier --test-name-filter=identifier_direct_set_is_atomic_error_test
```

Result before the destination guard:

```text
Running 1 tests
× identifier_direct_set_is_atomic_error_test
Pattern match failed, no pattern matched the value.
Tests: 1 failed (1)
```

The failure occurred because `tree_kernel.validate_edit` accepted a direct
Identifier assignment.

### RED: codec and algebra

Commands:

```text
gleam test --target erlang -- shared_tree_change shared_tree_codec --test-name-filter=identifier_field
gleam test --target javascript -- shared_tree_change shared_tree_codec --test-name-filter=identifier_field
```

Both targets failed before the field variant was added with:

```text
The module `watershed/tree/change` does not have a `IdentifierField` value.
```

The rebase test was also run before its implementation:

```text
gleam test --target erlang -- shared_tree_change --test-name-filter=identifier_field_rebases
```

Result:

```text
Running 1 tests
× shared_tree_change_identifier_field_rebases_as_no_change_test
Tests: 1 failed (1)
```

## Final verification

Startest CLI discovery confirmed both positional file filters and the
supported name filter:

```text
gleam test --target erlang -- --help
USAGE:
    gleam test -- [ ARGS ] [ --test-name-filter=<STRING> ]
```

Final Erlang command:

```text
gleam test --target erlang -- shared_tree_identifier shared_tree_schema shared_tree_schema_evolution shared_tree_change shared_tree_codec
```

Output:

```text
Test Files: 7
     Tests: 170 passed (170)
Duration: 5s
```

Final JavaScript command:

```text
gleam test --target javascript -- shared_tree_identifier shared_tree_schema shared_tree_schema_evolution shared_tree_change shared_tree_codec
```

Output:

```text
Test Files: 7
     Tests: 171 passed (171)
Duration: 17s
```

The rebase crossed the transaction constraint integration surface, so both
targets also ran:

```text
gleam test --target erlang -- shared_tree_transaction shared_tree_change_constraint shared_tree_array_change
gleam test --target javascript -- shared_tree_transaction shared_tree_change_constraint shared_tree_array_change
```

Each target reported:

```text
Test Files: 2
     Tests: 63 passed (63)
```

Formatting and patch checks:

```text
gleam format src/watershed/tree/schema.gleam src/watershed/tree/change.gleam src/watershed/tree/codec.gleam test/watershed/shared_tree_schema_test.gleam test/watershed/shared_tree_schema_evolution_test.gleam test/watershed/shared_tree_change_test.gleam test/watershed/shared_tree_codec_test.gleam test/watershed/shared_tree_identifier_test.gleam test/watershed/tree/identifier_fixture.gleam test/watershed/tree/array_codec_fixture.gleam test/watershed/tree/change_fixture_codec.gleam test/watershed/tree/array_change_fixture.gleam test/watershed/tree/map_change_fixture.gleam
git diff --check
```

Both commands exited successfully. `git diff --check` produced no output.

## Files

Production:

- `src/watershed/tree/schema.gleam`
- `src/watershed/tree/change.gleam`
- `src/watershed/tree/codec.gleam`

Acceptance and focused tests:

- `test/watershed/shared_tree_identifier_test.gleam`
- `test/watershed/tree/identifier_fixture.gleam`
- `test/watershed/shared_tree_schema_test.gleam`
- `test/watershed/shared_tree_schema_evolution_test.gleam`
- `test/watershed/shared_tree_change_test.gleam`
- `test/watershed/shared_tree_codec_test.gleam`

Exhaustive fixture adapters:

- `test/watershed/tree/array_change_fixture.gleam`
- `test/watershed/tree/array_codec_fixture.gleam`
- `test/watershed/tree/change_fixture_codec.gleam`
- `test/watershed/tree/map_change_fixture.gleam`

## Decisions

- The captured fixture is authoritative that upstream accepts some low-level
  non-string and union Identifier schemas. Tests record native rejection as a
  watershed profile restriction and do not claim upstream refusal.
- The native codec accepts numeric zero, including JSON `0.0`, as the
  canonical zero value and emits integer `0`. All other payload shapes and
  values return `CorruptData` at the field-change location.
- The active stored schema remains the authoring authority. A wider Value view
  can read stored Identifier content, but local edit validation still rejects
  mutation until a real schema upgrade changes the stored cardinality.
- IdentifierField survives algebra normalization as an explicit no-change
  dispatch marker instead of being erased or converted to Value/Optional.
- Rebasing onto the reviewed constraint series exposed two unrelated private
  helpers named `wrap_constraint_ancestors`. The transaction authoring helper
  now has the distinct name `wrap_authored_constraint_ancestors`; behavior is
  unchanged, and both constraint integration suites pass on both targets.

## Commits

- Pre-rebase implementation commit:
  `9bf1dcff feat(tree): preserve identifier field semantics`
- Final rebased and amended commit: this report's containing commit. Its hash
  is recorded in the task handoff because adding a hash here would change it.

## Concerns

- `just format` stalled in the Trellis wrapper after more than six minutes and
  was stopped. Running `gleam format` directly on every changed Gleam file
  completed successfully.
- Existing compile warnings remain in unrelated tests and fixture utilities:
  JavaScript unsafe-integer warning cases and unused private fixture helpers.
- No unresolved Task 2 behavior concern remains.
