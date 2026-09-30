# SharedTree constraint codec Task 4 report

## Status

Complete. Task 4 adds permanent malformed-input, structural round-trip, and
fixture input-observation coverage. It closes the standalone SharedTree
constraint codec phase without adding constraint algebra, target resolution,
transaction runtime behavior, or public APIs.

The pinned Message V7, SharedTreeChange V5, and ModularChange V5 formats remain
unchanged. `noChangeConstraint` remains unsupported. The runner still removes
only unsupported FieldBatch `builds` and `refreshers` before codec execution.

## Changes

### Malformed input coverage

`test/watershed/shared_tree_codec_test.gleam` now rejects these violation
counts at `modular.violations`:

```json
{"violations":-1}
{"violations":1.5}
{"violations":"1"}
{"violations":true}
```

It also rejects these malformed node constraints at the node constraint
location:

```json
{"nodeExistsConstraint":{}}
{"nodeExistsConstraint":{"violated":"false"}}
{"nodeExistsConstraint":{"violated":false,"extra":true}}
{"nodeExistsConstraint":null}
```

`{"noChangeConstraint":{"violated":false}}` continues to return
`UnsupportedFeature` at `modular.noChangeConstraint`.

### Structural round trips

Direct ModularChange V5 tests now cover:

- a constraint-only node change;
- a constrained node with a nested object field;
- a constrained node inside a sequence field;
- an alias that resolves to a constrained node;
- a violated change with both builds and refreshers;
- exact omission of zero `violations`;
- exact omission of native `node_exists_constraint_on_revert`;
- exact encoded JSON for constraint-only, nested, array, and alias cases;
- exact top-level members and native round-trip preservation for builds,
  refreshers, and a nonzero violation count.

### Runner input observation

`test/watershed/shared_tree_transaction_test.gleam` independently mutates:

- nonviolated `violated: false` to `true`;
- violated top-level `violations: 1` to `0`;
- the nonviolated compressor session ID;
- `modularChange: 5` to `4`;
- the nonviolated message revision byte from `4` to `3`.

Each mutation must make `run_wire` return an error or a different observation.

The compressor-session mutation exposed a real gap: the validated session ID
affected compressor construction but was not represented in the normalized
observation. `transaction_fixture.run_wire/1` now includes canonical,
validated nonviolated and violated compressor session IDs under
`compressorSessions`. Message JSON and bytes still come only from the real
encoder.

## TDD evidence

### RED

Malformed violation counts were added before changing behavior. Existing
strict decoding was already green, so a temporary mutation changed
`violations` decoding from `nonnegative_integer` to `integer`:

```bash
gleam test --target erlang -- --test-name-filter=shared_tree_codec_rejects_malformed_violation_counts_test
```

Result: failed on the negative count because the expected
`modular.violations` corrupt-data error was absent.

Malformed node constraints were added before changing behavior. Existing
strict decoding was already green, so a temporary mutation allowed an
additional `extra` member:

```bash
gleam test --target erlang -- --test-name-filter=shared_tree_codec_rejects_malformed_node_constraints_test
```

Result: failed with a pattern-match failure when the extra-member input was
accepted.

Structural round-trip cases were added before changing behavior. A temporary
mutation removed `nodeExistsConstraint` encoding:

```bash
gleam test --target erlang -- --test-name-filter=shared_tree_codec_structural_constraints_round_trip_exact_json_test
```

Result: failed because the encoder returned an empty node object instead of
the exact constraint object.

The runner mutation test failed against the unmodified runner:

```bash
gleam test --target erlang -- --test-name-filter=shared_tree_transaction_wire_observes_independent_input_mutations_test
```

Result:

```text
compressor session mutation was not observed
Tests: 1 failed (1)
```

All temporary codec mutations were restored before the final green runs.

### GREEN

Focused new behavior:

```bash
gleam test --target erlang -- --test-name-filter=shared_tree_codec_rejects_malformed_violation_counts_test
gleam test --target erlang -- --test-name-filter=shared_tree_codec_rejects_malformed_node_constraints_test
gleam test --target erlang -- --test-name-filter=shared_tree_codec_structural_constraints_round_trip_exact_json_test
gleam test --target erlang -- --test-name-filter=shared_tree_codec_alias_constraint_omits_revert_constraint_test
gleam test --target erlang -- --test-name-filter=shared_tree_codec_violated_change_keeps_build_members_test
gleam test --target erlang -- --test-name-filter=shared_tree_transaction_wire_observes_independent_input_mutations_test
```

Result: each focused test passed.

## Closure gates

These exact commands passed:

```bash
gleam format --check src test
gleam test --target erlang -- shared_tree_transaction shared_tree_change shared_tree_codec shared_tree_codec_fixture shared_tree_change_fixture
gleam test --target javascript -- shared_tree_transaction shared_tree_change shared_tree_codec shared_tree_codec_fixture shared_tree_change_fixture
just shared-tree-codec-interop
just shared-tree-test
```

Results:

- focused Erlang: 112 passed, 0 failed;
- focused JavaScript: 112 passed, 0 failed;
- codec interoperability: 2 targets, 30 items per target;
- SharedTree profile: 756 passed, 0 failed, plus all owned smokes.

The first codec interop attempt reported missing existing oracle dependencies.
After `npm --prefix tools/shared-tree-oracle ci --no-audit --no-fund`, it
reported the missing pinned Fluid checkout. After
`npm --prefix tools/shared-tree-oracle run source:prepare`, the gate passed.
No dependency manifest or lockfile changed. No Hex rate limit occurred.

The commands retain pre-existing warnings for two unused private codec export
helpers and JavaScript unsafe-integer test literals. This task adds no warning.

## Parent plan

Only Task 2 in
`docs/superpowers/plans/2026-09-29-shared-tree-transactions.md` was marked
complete. Its evidence records the implementation commits and exact closure
commands.

The plan states that native constraint state and pinned V5 codec support are
complete. Task 3 constraint authoring and algebra remains next. Transaction
runtime behavior and public APIs remain unimplemented. M5 remains incomplete,
and public support claims are unchanged.

## Files changed

- `test/watershed/shared_tree_codec_test.gleam`
- `test/watershed/shared_tree_transaction_test.gleam`
- `test/watershed/tree/transaction_fixture.gleam`
- `docs/superpowers/plans/2026-09-29-shared-tree-transactions.md`

No generated fixture, dependency manifest, `.code-map`, or apm-managed file
was changed.

## Concerns

Full compressed FieldBatch parity remains out of scope. The captured
`builds` and `refreshers` contain identifier values that need separate
compressor-aware FieldBatch decoding and byte-stable compressed encoding.
This task does not reopen that ruling.
