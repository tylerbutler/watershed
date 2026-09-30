# SharedTree constraint codec final fixes

## Final Review Fix

### Status

PASS. The shared Sequence V3 encoder again emits `effect` before `count`, which
restores the legacy bytes for constraint-free inserts, removes, and moves.
Transaction fixture observations still come from the real encoder. Their
normalized JSON is compared semantically, so upstream property order no longer
changes the production encoder contract. The anti-echo test remains active.

### RED

Added
`sequence_v3_codec_preserves_constraint_free_insert_bytes_test` before changing
the production encoder.

```bash
gleam format test/watershed/shared_tree_array_codec_test.gleam &&
gleam test --target erlang -- --test-name-filter=sequence_v3_codec_preserves_constraint_free_insert_bytes_test
```

Output:

```text
FAIL sequence_v3_codec_preserves_constraint_free_insert_bytes_test
Expected "[{\"count\":1,\"effect\":{\"insert\":{\"id\":1}},\"cellId\":1}]"
to equal
"[{\"effect\":{\"insert\":{\"id\":1}},\"count\":1,\"cellId\":1}]"
Tests: 1 failed (1)
```

The failure proves that the branch changed ordinary Sequence insert bytes from
the legacy `effect,count,cellId` order to `count,effect,cellId`.

### GREEN

Restored the legacy encoder order and ran the focused regression:

```bash
gleam test --target erlang -- --test-name-filter=sequence_v3_codec_preserves_constraint_free_insert_bytes_test
```

Output:

```text
Running 1 tests
✓ sequence_v3_codec_preserves_constraint_free_insert_bytes_test
Tests: 1 passed (1)
```

Ran the transaction fixture tests after changing normalized comparisons to
semantic JSON and retaining the byte anti-echo assertion:

```bash
gleam test --target erlang -- --test-name-filter=shared_tree_transaction_wire_
```

Output:

```text
Running 7 tests
✓ shared_tree_transaction_wire_decodes_constraints_test
✓ shared_tree_transaction_wire_requires_input_sections_test
✓ shared_tree_transaction_wire_rejects_unknown_context_test
✓ shared_tree_transaction_wire_rejects_malformed_compressor_test
✓ shared_tree_transaction_wire_observes_constraints_and_encoder_output_test
✓ shared_tree_transaction_wire_rejects_noncanonical_bytes_test
✓ shared_tree_transaction_wire_observes_independent_input_mutations_test
Tests: 7 passed (7)
```

Ran the required focused Erlang matrix:

```bash
gleam test --target erlang -- shared_tree_transaction shared_tree_codec shared_tree_codec_fixture shared_tree_array_codec
```

Output:

```text
Test Files: 4
Tests: 43 passed (43)
```

Ran the required focused JavaScript matrix:

```bash
gleam test --target javascript -- shared_tree_transaction shared_tree_codec shared_tree_codec_fixture shared_tree_array_codec
```

Output:

```text
Test Files: 4
Tests: 43 passed (43)
```

Formatting and diff validation:

```bash
gleam format --check src/watershed/tree/codec/sequence_field.gleam test/watershed/shared_tree_array_codec_test.gleam test/watershed/shared_tree_transaction_test.gleam
git diff --check
```

Output: no output; both commands exited 0.

The focused commands retain the pre-existing unused private fixture helper
warnings. The JavaScript command also retains the pre-existing unsafe-integer
warnings from array-kernel tests. This fix adds no warning.

### Files

- `src/watershed/tree/codec/sequence_field.gleam`
- `test/watershed/shared_tree_array_codec_test.gleam`
- `test/watershed/shared_tree_transaction_test.gleam`
- `.superpowers/sdd/plan/final-fix-report.md`

### Commit

- `0cb635c1095a7f6d91805fee146baf4edaba3b80`
  `fix(tree): preserve sequence wire order`

### Self-review

- Confirmed the production change is the one-line restoration of the legacy
  Sequence mark member order.
- Confirmed the exact-byte regression uses a constraint-free insert and fails
  for the reviewed branch behavior.
- Confirmed transaction JSON expectations remove only unsupported `builds` and
  `refreshers`, then compare normalized JSON semantically.
- Confirmed transaction `message` and `messageBytes` observations still come
  from `codec.encode_message`.
- Confirmed the anti-echo test supplies noncanonical input, rejects identical
  returned bytes, and verifies equivalent normalized JSON.
- Confirmed no fixture JSON, dependency manifest, `.code-map`, generated file,
  or apm-managed file changed.

### Concerns

Full compressed FieldBatch parity remains outside this constraint codec slice.
The captured `builds` and `refreshers` still require separate compressor-aware
identifier decoding and byte-stable compressed encoding.
