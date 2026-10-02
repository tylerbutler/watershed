# Task 8 report: native transaction recovery proof

**Date:** 2026-09-30
**Baseline:** `afc32c65d6169bcc8392c20ed81edaf72bfc5ceb`
**Outcome:** blocked by the pinned corpus/native codec contract

## Corpus verification

The committed transaction corpus contains all four required cases:

- `transaction-callbacks`
- `transaction-constraints`
- `transaction-wire`
- `transaction-history`

The manifest points to all four files. Each file pins
`@fluidframework/tree@3.1.0` and Fluid commit
`c3c5bf0ecd313362e83fe8a02b7d39e7e0736960`. The repository keeps Floodgate
commit `0eb493fc46d1bb9baf1151a6ccdde93544e057e7`,
Message/SharedTreeChange/ModularChange `7/5/5`, Schema `2`, and
`minVersionForCollab: 2.117.0`.

The corpus/source validation tests passed:

```bash
node --test tools/shared-tree-oracle/source.test.mjs \
  tools/shared-tree-oracle/generate.test.mjs
```

```text
Tests: 98 passed
```

These tests prove registration, required-case validation, nonempty input and
observations, exact source identity checks in controlled checkouts, executable
transaction wire operands, callback field coverage, constraint convergence and
retained evidence, and summary continuation inputs.

The installed oracle package versions are all `3.1.0`. The local Fluid checkout
is clean at the pinned commit and exact `client_v3.1.0` tag.

## Source checkout deviation

The existing local reference checkout is not ready for source capture:

```bash
npm --prefix tools/shared-tree-oracle run source:verify
npm --prefix tools/shared-tree-oracle run check
```

Both commands stop at:

```text
The injected oracle test has unexpected content:
packages/dds/tree/src/test/watershedCodecs.spec.ts
```

The current transaction injection is absent from that checkout. The checkout
still has no tracked source changes and remains at the correct Fluid commit.
The user instruction forbids editing the pinned checkout except through the
existing source injection and capture commands. Those commands verify owned
injections before replacing them, so they cannot repair this stale local
injection state. I did not clean or rewrite the checkout.

Task 1 Step 6 is therefore not proved in this execution. The committed corpus
validators pass, but deterministic source regeneration was not rerun.

## RED

I added strict fixture registrations for:

```gleam
run_callbacks
run_constraints
run_history
```

and ran:

```bash
gleam test --target erlang -- shared_tree_fixture
```

The expected RED compile failure named the three missing functions. No
production code existed before the test.

## Blocking source-contract mismatch

The pinned transaction source uses:

```text
id: sf.identifier
```

The captured transaction schema records the field as `Identifier`, and the
callback, constraint, and history observations include exact submitted
messages, created builds, retained builds, summaries, and continuation
messages containing those identifier nodes.

The native field-batch codec explicitly rejects this data:

```text
IdentifierValue -> UnsupportedFeature(..., "identifier values")
type_id == identifier_node -> UnsupportedFeature(..., "identifier nodes")
```

The existing `run_wire` runner avoids that unsupported contract by deleting
`builds` and `refreshers` before native decode. That is sufficient for the
Task 2 constraint-field probe, but it cannot produce Task 8's required complete
observations. In particular, it cannot measure or round-trip:

- exact transaction callback submitted messages;
- created and retained builds in a violated transaction;
- the pinned transaction summary forest;
- the summary tail and continuation containing identifier nodes.

Returning fixture expected output, counting fields from expected output, or
continuing to strip the unsupported data would violate the Task 8 brief.
Changing the expected corpus to use ordinary strings would violate the
instruction not to reauthor expected output. Adding Identifier field-batch
support would expand the native supported profile beyond the approved
transaction design and is not a tightly coupled Task 8 bug.

This is an irreconcilable design mismatch for Task 8 as currently specified.
The binding decision must be one of:

1. Expand the native profile to support Fluid Identifier nodes, then implement
   the three complete runners.
2. Recapture the pinned transaction corpus with an ordinary string identity
   field while keeping stable node identity observations separate. This changes
   the pinned expected outputs and requires explicit design approval.

## Additional proof attempted

Before confirming the codec mismatch, I wrote real runtime-core tests for:

- one multi-edit transaction resubmitted once and acknowledged once;
- stable map-node identity through reconnect;
- no event on acknowledgement or duplicate delivery;
- accepted-before-drop deduplication with no resubmit.

The pending resubmit test passed. The accepted-before-drop test first failed
because its second edit targeted a field absent from the selected map schema;
after correcting the test to use a second real map edit, the implementation
path was ready to rerun. I removed these uncommitted tests because Task 8 cannot
reach its corpus gate and the user requested one exact complete commit, not a
partial proof commit.

## Deviations

- No Task 9 service or client files were changed.
- No expected fixture output was edited.
- No pinned checkout file was cleaned or rewritten.
- No full build or full `just test` was run.
- The exact Task 8 dual-target and `just` gates were not run because the
  required corpus runners cannot be implemented against the current native
  codec contract.
- The tracked plan remains unchanged. Task 8 and Task 1 Step 6 remain
  unchecked.
- No commit was created.

## Worktree

All exploratory tracked changes were removed. The repository is back to the
Task 8 baseline with no tracked diff from this execution.

## Resumed implementation after Identifier completion

**Date:** 2026-10-02
**Baseline:** `6c803bfb`
**Outcome:** blocked by the pinned observation representation

The earlier Identifier blocker is obsolete. The resumed baseline decodes,
authors, and persists the transaction schema's Identifier fields. A focused
Erlang baseline passed 128 tests across the fixture, history-resubmit, summary,
document-summary, client, and transaction test files.

### Resumed RED

I registered `run_callbacks`, `run_constraints`, and `run_history` in
`shared_tree_fixture_test.gleam`, then ran:

```bash
gleam test --target erlang -- test/watershed/shared_tree_fixture_test.gleam
```

The expected compile-time RED named all three absent functions.

### Native callback execution proof

I implemented an exploratory `run_callbacks` adapter from fixture input only.
It reconstructed the pinned schema and initial tree, materialized Identifier
values through the native compressor, executed every callback scenario through
`watershed/tree/transaction`, encoded the submitted commit through the native
Message V7 codec, and collected visible state, identities, events, allocation,
detached repairs, and history.

The adapter independently reproduced the pinned callback values, event count,
commit count, pending count, submitted message, final tree, stable identities,
allocation prefix, summary compressor, and detached content. The first
remaining comparison failure was:

```text
$.observations[0].history.pending[0].changes[0].change.aliases[0]
```

The mismatch is representational. The pinned callback observation serializes
private upstream TypeScript objects, including:

- hash-map backing arrays under `_root`, `_maxNodeSize`, and `isShared`;
- schema listener objects under `_events` and `events`;
- upstream alias tables that are not stored by the native modular-change
  representation;
- private field-change objects rather than the native normalized change data.

The native change contains the same authored field effects, builds, parents,
moves, revisions, and visible result, but it does not contain those TypeScript
implementation objects. They cannot be recovered from the fixture input or
from the native runtime state.

### Binding conflict

Task 8 requires complete pinned observations from fixture input and forbids a
second simulator or returning captured expected output. Exact callback history
parity now requires one of those forbidden approaches:

1. emulate private `@fluidframework/tree` TypeScript container internals in a
   second Gleam serializer; or
2. copy the captured private objects from `expected` or `raw`.

The plan and design contain no normalization ruling for these private
structures. The native model intentionally uses a different representation,
so this is not an Identifier or codec support gap and cannot be fixed by
wiring another native path.

I stopped before implementing constraints/history adapters or persistence
tests because Step 1 cannot satisfy its exact contract without violating the
binding constraints. All exploratory tracked changes and the temporary debug
module were removed. The worktree is clean at `6c803bfb`; no commit was
created, and Task 8 remains unchecked.

## Controller-ruling continuation

**Date:** 2026-10-02
**Baseline:** `6c803bfb`
**Outcome:** incomplete; callback history normalization remains RED

The controller ruling removed the private-object blocker. I normalized the
pinned oracle history at its injected Fluid 3.1.0 source, regenerated all 50
fixtures, and committed the result:

```text
3386433d test(tree): normalize transaction oracle history
```

The source and generator suites passed 111 tests. Deterministic generation
verified all 50 cases.

### Transaction allocation RED and GREEN

The named RED was:

```bash
gleam test --target erlang -- shared_tree_transaction
```

```text
38 tests: 37 passed, 1 failed
identifier_transaction_allocates_one_outer_revision_test
```

The failure proved that internal edits consumed persistent compressor IDs and
shifted Identifier defaults. The fix reserves one real outer transaction
revision, uses a shadow compressor for distinct internal compose revisions,
and materializes Identifier values only from the real compressor. This keeps
the per-edit compose graph while preserving the outer allocation contract.

The authored FieldBatch path also used the generic uncompressed shape grammar.
I added the schema-supported canonical Fluid V2 object/leaf shape-table path,
including Identifier compression, while retaining the existing generic
fallback for map, array, recursive, and unsupported schemas.

The GREEN matrix was:

```bash
gleam test --target erlang -- shared_tree_field_batch
gleam test --target javascript -- shared_tree_field_batch
gleam test --target erlang -- shared_tree_transaction
gleam test --target javascript -- shared_tree_transaction
```

```text
FieldBatch: 33 passed on each target
Transaction: 38 passed on each target
```

The implementation was committed as:

```text
0b2d7e49 fix(tree): preserve transaction allocation parity
```

### Current corpus RED

The callback runner executes from input through the native runtime and now
matches allocation, visible state, identity, events, retained content, and the
authored canonical message before history graph comparison. The focused run is:

```bash
gleam test --target erlang -- shared_tree_fixture
```

```text
23 tests: 20 passed, 3 failed
callback: aliases[3].target.localId
constraints: runner not implemented
history: runner not implemented
```

The native stable history serializer now emits the normalized semantic shape.
The remaining callback difference is the composed alias/parent graph: native
composition resolves intermediate alias chains and allocates 15 aliases with
`maxId` 32; pinned Fluid retains intermediate chains and allocates 16 aliases
with `maxId` 33. The visible delta, builds, identities, compressor state, and
message field effects agree. This is not yet normalized to a deliberate common
semantic projection, so callback parity remains RED.

### Remaining work

- Normalize alias and parent evidence at the oracle source and native adapter
  without retaining private intermediate IDs, then regenerate and revalidate.
- Implement input-only constraint and history runners.
- Add pending resubmit, sequenced-summary tail continuation, explicitly
  violated continuation, and accepted-before-drop deduplication proofs.
- Run the full dual-target and `just` validation matrix.
- Update only Task 1 and Task 8 evidence that is genuinely re-proved.

## Step 1 closure

The callback RED moved from the original semantic alias mismatch to one exact
nested-rollback allocation mismatch:

```text
transaction-callbacks:
  nested-rollback submitted message
  expected build/insert local ID 9 and maxId 11
  native build/insert local ID 3 and maxId 5
```

The transaction now keeps one cumulative local atom watermark across nested
rollback. An aborted nested scope restores visible state but does not reuse its
consumed local IDs. The callback corpus then passed completely.

The constraints runner exposed two additional source-level requirements:

- duplicate aliases must be removed by final semantic target, not only when
  adjacent;
- parent and node graph evidence must use root-first semantic topology before
  anonymous atom renumbering.

Both the pinned source capture and native projection now apply those rules.
The generator rejects duplicate final alias targets, changed alias targets,
changed parent targets, sparse anonymous IDs, and private TypeScript graph
state. All transaction fixtures were regenerated through:

```text
npm --prefix tools/shared-tree-oracle run source:inject
npm --prefix tools/shared-tree-oracle run source:capture
npm --prefix tools/shared-tree-oracle run generate
```

The native transaction path also needed wire-identity fixes that normalization
does not hide:

- compressed detached build roots infer their actual root field schema;
- FieldBatch shape identifier collection does not recursively double-count
  child shapes;
- cross-array graph authoring reserves Fluid's intermediate allocation
  watermark;
- constraint path atoms are reserved before authored field edits;
- constraint composition uses those reserved low IDs instead of appending new
  graph IDs after the edits.

The constraints runner executes detached refusal, same-array move,
cross-array move, duplicate constraints, concurrent removal, pending rebase,
resubmission, acknowledgement, retained builds, and convergence through native
transaction and history APIs. Its exact reconnect messages and semantic
history now match the pinned capture.

The history runner uses only fixture input. It:

- validates the required scenario and action sequence;
- reconstructs pending and explicitly violated writer history through native
  transaction and history paths;
- decodes the supplied sequenced summary and compressor;
- proves the tail fails before its captured allocation ranges are finalized;
- reloads the summary after finalizing those ranges and applies the tail;
- materializes the continuation Identifier before authoring its transaction;
- validates the continuation creation range;
- reloads a fresh peer, applies the tail and continuation envelopes, and
  observes convergence.

Mutation coverage rejects changed scenario IDs and actions, invalid
compressors, missing allocation ranges, malformed summaries, malformed tail
messages, and malformed continuation messages. A changed continuation edit
changes the native observation.

Final focused evidence:

```text
gleam test --target erlang -- shared_tree_fixture
26 passed

gleam test --target javascript -- shared_tree_fixture
26 passed

gleam test --target erlang -- shared_tree_transaction shared_tree_field_batch
71 passed

gleam test --target javascript -- shared_tree_transaction shared_tree_field_batch
71 passed

node --test tools/shared-tree-oracle/source.test.mjs tools/shared-tree-oracle/generate.test.mjs
112 passed

npm --prefix tools/shared-tree-oracle run source:verify
passed

npm --prefix tools/shared-tree-oracle run check
verified 50 cases
```

Oracle/common normalization commit:

```text
eb6b7762 test(tree): canonicalize transaction history graphs
```

Task 8 Step 1 is green on both targets. Persistence Steps 2-4 have not started.

The tracked worktree currently contains the registered fixture tests and the
incomplete callback/constraint/history adapter only. Task 8 remains unchecked.

## Step 1 review fixes

**Date:** 2026-10-02
**Reviewed range:** `6c803bfb..ce8abda5`
**Implementation head before this report:** `a97ef2ba75bac844c6d3f899631d4d7264a138cc`
**Outcome:** all six Important findings fixed and verified

### Commits

```text
329a471f8f3d31beca7da76ac672dc123fe51a4d fix(tree): preserve revision after nested abort
39585de0cf679f3d539b748943d27332f686a2eb fix(tree): retain native transaction evidence
c6dde1b5c657d81714c7c4c9dd4a25601f5798e6 fix(tree): scope compressed field batches
a97ef2ba75bac844c6d3f899631d4d7264a138cc style(tree): format transaction fixture
```

No commit has a `Co-authored-by` trailer.

### 1. Nested rollback revision and allocation contract

The failing case starts a nested scope before the outer transaction has an
authored change, inserts a node with a generated Identifier, aborts the nested
scope, and then inserts a different node before finishing. Before the fix, the
shadow revision compressor reused the aborted Identifier's stable ID as the
outer commit revision.

The regression test is:

```text
identifier_nested_abort_preserves_outer_revision_test
```

The RED failure was:

```text
Expected "00000000-0000-4000-8000-000000000002"
to not equal "00000000-0000-4000-8000-000000000002"
```

`abort_nested` now realigns the shadow revision compressor with the advanced
real compressor when the savepoint restores zero authored changes. It retains
the consumed allocation watermark and prevents a revision from colliding with
an Identifier allocated by the aborted edit.

### 2. Suppressed field-operation evidence

The prior stable history projection retained only each field name and kind.
For an explicitly violated transaction, this erased the suppressed `label`
replacement and sequence insertion even though the commit retained them.

The upstream capture and native runner now serialize a common semantic
`operation` payload for every field change:

- Generic child changes retain child indexes and atom IDs.
- Value and Optional changes retain moves, child changes, and replacement
  source/detach data.
- Sequence changes retain marks, cells, effects, endpoints, overrides, and
  child changes.
- Identifier fields retain an explicit empty operation object.

The generator now rejects any normalized field that lacks this payload. The
focused oracle regression is:

```text
transaction history retains field operation payloads
```

All four transaction fixtures were regenerated from the pinned Fluid source.

### 3. Native callback events

`run_callbacks` no longer constructs
`ChangeEvents([TreeChanged(True)], True)` for every commit. The callback
execution path carries the `ChangeEvents` returned by
`transaction.finish` into serialization. Rollback and no-commit paths still
produce the native empty event result.

The exact callback corpus passes with the native events on both targets.

### 4. Native invalid edit

The `invalid-edit-rollback` scenario now calls:

```gleam
transaction.apply_edit(open, types.ArrayRemove(["left"], -1, 1))
```

It requires an `InvalidEdit` result before aborting. An unexpected error or a
successful edit fails the runner. The source capture and native observation
also record `nativeFailure: true`, and the generator requires it.

The focused oracle regression is:

```text
transaction callbacks record native invalid-edit failure
```

### 5. Native resubmission and continuation wire

The history runner now encodes the commit returned by
`tree_kernel.resubmit_commits` and reports that native Message V7 value in
`reconnectMessages`. It no longer copies `tailEnvelope.contents` into the
observation.

The continuation path now:

1. authors the continuation through the native transaction API;
2. encodes the resulting native commit;
3. validates the supplied upstream continuation envelope as decodable wire
   evidence;
4. finalizes the native continuation creation range on the peer;
5. replaces only the peer envelope contents with the native encoded commit;
6. replays that native continuation on the peer.

The pinned source capture records `resubmittedMessage` and
`nativeContinuation`. Generator validation binds those fields to the captured
reconnect and continuation envelopes. The focused oracle regression is:

```text
transaction history records native resubmission and continuation wire
```

### 6. FieldBatch validation and encoding scope

Compressed shape-table encoding is now selected only when the stored schema
declares an Identifier field. Identifier-free schemas continue through the
pre-existing contextual generic encoder, which preserves ordinary
nontransaction bytes.

Before compressed encoding, every detached tree is validated with
`schema.validate_subtree`. This rejects unknown object fields and duplicate
object fields instead of silently dropping them while walking declared fields.

Focused regressions:

```text
shared_tree_codec_field_batch_keeps_ordinary_context_bytes_test
shared_tree_codec_field_batch_rejects_unknown_and_duplicate_compressed_fields_test
```

Both tests failed before the implementation. The ordinary-byte test received
the new one-shape compressed form instead of the established five-shape
contextual form. The validation test received `Ok` for malformed objects.

### Verification

Final targeted Gleam matrix:

```bash
gleam test --target erlang -- \
  shared_tree_transaction shared_tree_field_batch shared_tree_fixture
gleam test --target javascript -- \
  shared_tree_transaction shared_tree_field_batch shared_tree_fixture
```

```text
Erlang:     100 passed
JavaScript: 100 passed
```

Oracle source and corpus tests:

```bash
node --test \
  tools/shared-tree-oracle/source.test.mjs \
  tools/shared-tree-oracle/generate.test.mjs
npm --prefix tools/shared-tree-oracle run source:verify
npm --prefix tools/shared-tree-oracle run check
```

```text
115 tests passed
source:verify passed
Verified 50 upstream SharedTree cases
```

Formatting and lint:

```bash
gleam format --check src test
just lint
```

```text
exit 0
```

`just format` stalled inside `trellis run format` after both package format
commands started. I stopped that process, formatted the five changed Gleam
files directly with `gleam format`, and then ran the repository formatting and
lint checks above successfully.

The test output contains pre-existing warnings for two JavaScript unsafe
integer literals and several unused private test helpers. No new warning was
introduced by these fixes.
