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
