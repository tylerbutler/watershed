# Task 1 storage continuation report

## Status

DONE

This completes the bounded storage, document GC, published reload, and real
active-target proof slice. It does not complete Task 1 or M7.

## Implementation

- Replaced the attach-snapshot-plus-tail `fresh-load` observation with eight
  real full-document publications:
  - `before-removal`
  - `after-removal`
  - `after-undo`
  - `retained-repair`
  - `branch-disposal`
  - `revertible-disposal`
  - `unreferenced-datastore`
  - `fresh-load`
- Each publication records:
  - acknowledged summary handle
  - reference, summary, and acknowledgement sequence boundaries
  - fetched snapshot tree
  - every referenced stored blob as base64 bytes
  - protocol snapshot sequence number
  - parsed document metadata, document GC, and datastore component metadata
- The fresh client loads the named published version, resolves the target from
  that version, writes `continued: true`, and the original writer observes it.
- Replaced both mock-only active transaction observations with real document
  graph publication attempts. They run after the stable case streams so the
  attempts do not perturb the earlier scenario allocation order.
- Strengthened lifecycle validation to reject:
  - missing or empty stored blobs
  - publication/version substitution
  - invalid sequence boundaries
  - metadata not derived from stored bytes
  - wrong GC checkpoints
  - wrong target routes
  - arbitrary GC summary bytes
  - mock active-target descriptors
  - substituted parent/target data
  - missing active-target transport or allocation evidence
- Updated the design's measured-observation table. The remaining Task 1 gates
  are still explicit.

## Measured source evidence

Pinned source: Fluid `3.1.0` at
`c3c5bf0ecd313362e83fe8a02b7d39e7e0736960`.

The retention publications have these snapshot sequence numbers and blob
counts:

| Checkpoint | Snapshot sequence | Stored blobs |
| --- | ---: | ---: |
| `before-removal` | 4 | 23 |
| `after-removal` | 9 | 23 |
| `after-undo` | 14 | 23 |
| `retained-repair` | 19 | 23 |
| `branch-disposal` | 23 | 23 |
| `revertible-disposal` | 27 | 23 |
| `unreferenced-datastore` | 33 | 25 |
| `fresh-load` | 38 | 25 |

At every checkpoint, the publication reference sequence equals the stored
snapshot sequence. The summary operation is the next sequence, and the
acknowledgement is the sequence after that.

The attached-then-unreferenced datastore is `/P`, with entry point `/P/root`.
Stored GC has `unreferencedTimestampMs: 1700000000000` on both routes.
Component metadata records:

- `/A`: package `org.watershed.shared-tree.m7.graph`, root datastore `true`
- `/P`: package `org.watershed.shared-tree.m7.graph`, root datastore `false`

The final published version is
`4f573206-4cbd-447c-89a7-d27caa0aee3f`, snapshot sequence 38. The fresh client
resolved `/A/b33114ac-1482-463a-9599-b66a30887095` from that publication and
the writer observed `continued: true`.

Both real active-target attempts measured the same contract:

- exact error:
  `Cannot attach while a transaction is in progress. Commit or abort the transaction before attaching.`
- target path `/A/_F`
- target attachment changed from `false` to `true`
- transport contained one ID allocation and the target channel attach snapshot
- target and parent tree views entered the upstream invalid state

This proves that the upstream refusal is not atomic.

## TDD evidence

### RED

Command:

```sh
node --test --test-name-pattern='retention checkpoints publish|fresh load names|retention validator rejects empty|active target records|active target validator rejects' tools/shared-tree-oracle/generate.test.mjs
```

Result before implementation: 5 tests, 0 passed, 5 failed.

The failures were the intended missing evidence:

- no `published-document` records
- no stored snapshot/blob bytes
- no published-version reload binding
- no real `document-attachment` record
- validators accepted substituted mock descriptors and routes

### GREEN

Command:

```sh
node --test --test-name-pattern='retention checkpoints publish|fresh load names|retention validator rejects|active target records|active target validator rejects' tools/shared-tree-oracle/generate.test.mjs
```

Result: 6 tests, 6 passed, 0 failed.

## Validation

```sh
node tools/shared-tree-oracle/source.mjs lifecycle-capture \
  tools/shared-tree-oracle/.output/lifecycle
```

Result: 6 upstream lifecycle tests passed. The expected upstream telemetry
reports the measured invalid-tree state when the two failed active-target
containers close.

```sh
just shared-tree-oracle
```

Result: generated 68 upstream SharedTree cases.

```sh
node --test tools/shared-tree-oracle/source.test.mjs \
  tools/shared-tree-oracle/generate.test.mjs
```

Result: 156 tests passed, 0 failed.

```sh
just shared-tree-oracle-check
```

Result: verified byte reproduction for 68 upstream SharedTree cases.

Additional checks:

```sh
git diff --check
node --check tools/shared-tree-oracle/generate.mjs
node --check tools/shared-tree-oracle/generate.test.mjs
```

Result: all passed.

Verbose logs are in ignored workspace files:

- `tools/shared-tree-oracle/.output/task-1-storage-capture.log`
- `tools/shared-tree-oracle/.output/task-1-storage-regenerate.log`
- `tools/shared-tree-oracle/.output/task-1-storage-node-tests.log`
- `tools/shared-tree-oracle/.output/task-1-storage-byte-check.log`

## Files changed

- `tools/shared-tree-oracle/upstream-lifecycle.spec.ts`
- `tools/shared-tree-oracle/generate.mjs`
- `tools/shared-tree-oracle/generate.test.mjs`
- the five generated lifecycle fixtures
- `docs/superpowers/specs/2026-10-10-shared-tree-handles-attachment-design.md`
- this report

No dependency, lock, native runtime, pinned reference source, or generated
manifest input changed.

## Self-review

- Confirmed that stored metadata is re-derived from fetched blob bytes during
  validation instead of trusting producer descriptors.
- Confirmed that the fresh client names and loads the acknowledged publication.
- Confirmed that active-target validation binds the error, route, parent data,
  target state, transport, attach snapshot, and allocation evidence.
- Confirmed that the full-document publication helpers use existing pinned
  loader, runtime, local service, and summarizer APIs.
- Confirmed that Task 1 and M7 remain open.

## Remaining gates

The next bounded continuation still needs leaf decoding/resolution, complete
replay inputs, and the remaining identity, serialization-context, and
event-lifetime measurements. Native Tasks 2–9 remain unstarted.

## Review fixes, round 1

The three bounded validator and evidence findings in
`storage-fix-brief.md` are fixed. Task 1 and M7 remain incomplete.

### Actual-fixture RED

Command:

```sh
node --test \
  --test-name-pattern='corrupt target header|contradictory protocol watermark|different genuine publication|empty attach snapshot|empty allocation payload' \
  tools/shared-tree-oracle/generate.test.mjs
```

Result before validator fixes: 7 tests, 0 passed, 7 failed. Each mutation was
accepted by the validator:

- non-JSON bytes replaced the fresh publication's target SharedMap header
- protocol sequence `38` was replaced with `0`
- the fresh publication was replaced with the genuine `after-removal`
  publication while descriptor copies were updated
- the attach snapshot was replaced with `{}` in both observation and raw
  evidence for both active-target cases
- the allocation payload was replaced with `{}` in both copies for both
  active-target cases

The continuation capture test also failed before the producer change:

```sh
node --test --test-name-pattern='captures its published target' \
  tools/shared-tree-oracle/generate.test.mjs
```

Result: 1 test, 0 passed, 1 failed with `missing publication association`.

### Source capture and observations

Commands:

```sh
node tools/shared-tree-oracle/source.mjs lifecycle-capture \
  tools/shared-tree-oracle/.output/lifecycle
just shared-tree-oracle
```

Results: 6 upstream lifecycle tests passed; the corpus regenerated
successfully.

The fresh-load record now binds:

- publication handle and stored snapshot sequence
- loaded tree path and target path
- target state before and after the fresh reader's edit
- writer target state before and after receipt
- raw continuation transport
- continuation route, key, value, client ID, reference sequence, sequence, and
  publication handle

The measured continuation is the target-map `continued = true` operation at
reference sequence 42 and sequence 43, after publication acknowledgement 40.
The fresh publication protocol attributes contain minimum sequence 36 and
snapshot sequence 38. Its target header is a canonical SharedMap `0.2`
summary whose stored value is `before`.

The active-target validator now parses the real SharedTree attach summary,
requires its `active-target` forest state, and validates the document
compressor allocation payload (`sessionId`, positive creation range, requested
cluster size, and local ranges). Empty snapshots and allocations are rejected
independently for `active-transaction` and `active-target`.

### GREEN

Focused command:

```sh
node --test \
  --test-name-pattern='lifecycle validator registers|retention checkpoints publish|fresh load|retention validator rejects|active target|empty attach snapshot|empty allocation payload' \
  tools/shared-tree-oracle/generate.test.mjs
```

Result: 14 tests passed, 0 failed.

The generated-fixture regressions also reject a false continuation and a
continuation operation retargeted away from the published target.

Final commands:

```sh
node --test tools/shared-tree-oracle/source.test.mjs \
  tools/shared-tree-oracle/generate.test.mjs
just shared-tree-oracle-check
git diff --check
node --check tools/shared-tree-oracle/generate.mjs
node --check tools/shared-tree-oracle/generate.test.mjs
```

Results:

- 165 Node tests passed, 0 failed, 0 skipped
- byte reproduction passed for all 68 upstream SharedTree cases
- diff and JavaScript syntax checks passed

### Contract qualification

The measured upstream active-target refusal remains raw evidence: upstream
submits allocation and attach transport, attaches the target, and poisons both
views before it throws. Native code will enforce the stronger global
whole-candidate-validation boundary: preflight refusal before state or
transport changes. This is an explicit stronger refusal boundary, not a claim
of exact upstream failure-side-effect parity. Accepted graph operations must
still preserve upstream wire ordering.

### Fix self-review

- Stored snapshot sequence now comes from canonical parsed protocol attributes,
  and the publication boundaries are checked against that value.
- Only required JSON storage blobs are parsed as JSON; unrelated legitimate
  non-JSON blob encodings remain accepted.
- Fresh-load proof is publication-specific and binds stored target state to the
  captured continuation operation and writer receipt.
- Active-target proof validates attach and allocation payload contents, not
  envelope names alone.
- Fixtures were regenerated through the oracle; no generated fixture was
  edited by hand.
- Pins, cases, profile, process isolation, and the source-only support boundary
  are unchanged.

## Review fixes, round 2

The scoped re-review accepted the stored header and protocol fix, but found
that publication substitution and malformed active-target payloads still
passed. Both remaining findings are fixed without changing the producer or
regenerating fixtures.

### RED

Command:

```sh
node --test \
  --test-name-pattern='different genuine publication|non-forest attach payload|malformed creation range' \
  tools/shared-tree-oracle/generate.test.mjs
```

Result before the round-two validator fixes: 5 tests, 0 passed, 5 failed.

- The genuine `after-removal` publication was accepted after updating every
  fresh-load descriptor copy: loaded version, snapshot sequence, document GC,
  publication handle/sequence/acknowledgement, continuation publication handle,
  and stored blob list. Raw continuation transport was unchanged.
- Both active scenarios accepted the nonempty forest text
  `not a SharedTree forest: active-target` in raw and observation copies.
- Both active scenarios accepted allocation payloads with an empty session ID,
  `firstGenCount: -100`, and `localIdRanges: ["not a range"]` in both copies.

### Fix

- Exported and reused the existing structural FieldBatch field parser.
- The fresh publication now parses the published SharedTree forest and requires
  the current root `link` field to contain exactly the loaded target handle.
  Historical and GC occurrences do not satisfy this check.
- Active attach validation now parses the genuine summary tree, metadata,
  schema, forest FieldBatch, detached index, and edit-manager record. The
  measured forest must contain the `active-target` label structurally.
- Allocation validation now reuses `assertCreationRange`.
- The allocation session must equal the attach edit-manager session, and the
  measured attach revision must fall inside that creation range.

No producer code changed, so no source recapture or corpus regeneration was
needed.

### GREEN and final validation

Focused command:

```sh
node --test \
  --test-name-pattern='different genuine publication|non-forest attach payload|malformed creation range|lifecycle validator registers|active target records a real' \
  tools/shared-tree-oracle/generate.test.mjs
```

Result: 7 tests passed, 0 failed.

Final commands:

```sh
node --test tools/shared-tree-oracle/source.test.mjs \
  tools/shared-tree-oracle/generate.test.mjs
node --test tools/shared-tree-oracle/codec-interop.test.mjs
just shared-tree-oracle-check
```

Results:

- 169 source/generator tests passed, 0 failed, 0 skipped
- 13 codec-interoperability tests passed, 0 failed, 0 skipped
- byte reproduction passed for all 68 upstream SharedTree cases

### Round-two self-review

- Publication identity is derived from the current live forest field, not a
  path substring or copied descriptor.
- Attach state is derived from parsed FieldBatch structure, not text presence.
- Allocation structure uses the shared complete creation-range validator.
- Allocation and attachment are joined through the measured author session and
  revision range.
- No fixture, producer, pin, dependency, lock, profile, or support boundary
  changed.
- Task 1 and M7 remain open.

## Round 4: nested-array progress guard

The round-three decoder could loop forever when an array-backed `a` shape used
a child `c` shape that consumed no input. The exact fresh-publication mutation
changed the captured handle leaf from `c.value: true` to `false` while retaining
the encoded handle. The child returned a node without advancing the inner
stream, so the enclosing loop kept appending nodes.

The regression runs the mutated fixture in a subprocess with a two-second
timeout. This keeps the test runner responsive and distinguishes the intended
validation failure from a hung decoder. The first test-harness attempt passed a
file URL as a path and failed with `ENOENT`; after correcting the harness, the
valid RED was:

```sh
node --test \
  --test-name-pattern='non-advancing nested array|numeric zero-width array' \
  tools/shared-tree-oracle/generate.test.mjs
```

Result before the guard: 2 tests, 1 passed, 1 failed. The mutation subprocess
timed out with `ETIMEDOUT`, so it did not match the required
`non-advancing nested array` rejection.

The fix records the inner offset before each array-backed child decode and
requires the offset to increase. The separate numeric-count representation is
unchanged. The captured fresh publication contains a numeric zero-width array,
and the positive regression verifies that it remains accepted.

GREEN for the same focused command: 2 tests passed, 0 failed.

Final command:

```sh
node --test tools/shared-tree-oracle/source.test.mjs \
  tools/shared-tree-oracle/generate.test.mjs \
  tools/shared-tree-oracle/codec-interop.test.mjs
```

Result: 190 tests passed, 0 failed, 0 skipped.

### Round-four self-review

- The guard is inside the only array-backed decode loop that can repeat without
  consuming a field key.
- Numeric-count zero-width arrays still use their existing bounded item count
  and empty-stream assertion.
- No source capture, fixture, producer, pin, dependency, lock, profile, or
  native behavior changed.
- Task 1 and M7 remain open.

## Review fixes, round 3

The round-two use of `fieldBatchFieldPayloads` was not structural decoding. It
recursively scanned payloads and did not enforce the forest key-to-field map or
the encoded shape stream. The two remaining review findings are fixed by a
bounded strict decoder for the captured FieldBatch V2 forms.

### Decoder source evidence

The implementation follows the pinned Fluid 3.1.0 decoder behavior in:

- `feature-libraries/forest-summary/codec.ts`: forest `keys` and decoded fields
  have equal cardinality and pair by index
- `feature-libraries/chunked-forest/codec/chunkDecodingGeneric.ts`: every
  top-level field is a complete shape-indexed stream
- `feature-libraries/chunked-forest/codec/chunkDecoding.ts`: shape `a` decodes a
  nested array; shape `c` decodes node type, value, fixed fields, and extra
  fields in order
- `feature-libraries/chunked-forest/codec/format/formatV1.ts`: node value and
  field shape semantics

The local validator supports only the captured `a` and `c` shapes. It rejects
other shape discriminants explicitly rather than guessing.

### RED

Command:

```sh
node --test \
  --test-name-pattern='live root field key|missing encoded field keys|value-free string shape|duplicate keys and invalid shape' \
  tools/shared-tree-oracle/generate.test.mjs
```

Result before the decoder change: 6 tests, 0 passed, 6 failed.

Accepted mutations were:

- fresh publication forest keys changed from `["rootFieldKey"]` to
  `["repair-2"]` without changing encoded fields
- both active scenarios changed forest keys to `[]` while retaining two encoded
  fields
- both active scenarios changed the string leaf shape from `value: true` to
  `value: false` while retaining the encoded string
- duplicate top-level field keys, duplicate fixed node field keys, and an
  out-of-range used shape reference

### Fix

The strict decoder now:

- validates the exact forest and FieldBatch V2 envelopes
- validates identifier and shape indices
- requires forest key/data cardinality and unique field keys
- decodes only used `a` nested-array and `c` node shapes
- applies `c.value` consumption rules
- decodes fixed and extra fields in shape order
- rejects duplicate node field keys
- requires each encoded stream to be consumed completely
- returns the field map keyed by the forest's actual `keys`

Fresh-load validation inspects only the decoded `rootFieldKey` root and its
decoded `link` field. It cannot satisfy the check with `repair-2`, retained
history, or detached content. Active-target validation inspects the decoded
root's `label` field and therefore rejects key, shape, and value-consumption
corruption.

The recursive helper remains private to its pre-existing Identifier artifact
check and is no longer used by lifecycle storage validation.

No producer code changed, so no source capture or fixture regeneration was
needed.

### GREEN and final validation

Focused command:

```sh
node --test \
  --test-name-pattern='lifecycle validator registers|fresh-load validator|live root field key|active target|attach snapshot|allocation|non-forest|encoded field keys|value-free string|duplicate keys' \
  tools/shared-tree-oracle/generate.test.mjs
```

Result: 19 tests passed, 0 failed.

Final commands:

```sh
node --test tools/shared-tree-oracle/source.test.mjs \
  tools/shared-tree-oracle/generate.test.mjs
node --test tools/shared-tree-oracle/codec-interop.test.mjs
just shared-tree-oracle-check
git diff --check
node --check tools/shared-tree-oracle/generate.mjs
node --check tools/shared-tree-oracle/generate.test.mjs
node --check tools/shared-tree-oracle/codec-interop.mjs
```

Results:

- 175 source/generator tests passed, 0 failed, 0 skipped
- 13 codec-interoperability tests passed, 0 failed, 0 skipped
- byte reproduction passed for all 68 upstream SharedTree cases
- diff and JavaScript syntax checks passed

### Round-three self-review

- Current live state is derived from the decoded `rootFieldKey` only.
- Key cardinality, uniqueness, shape references, value consumption, and full
  stream consumption are enforced.
- Detached and retained fields are decoded for integrity but cannot substitute
  for the live root.
- Unsupported FieldBatch forms fail explicitly.
- Allocation validation from round 2 is unchanged.
- No fixture, producer, pin, dependency, lock, profile, or support boundary
  changed.
- Task 1 and M7 remain open.
