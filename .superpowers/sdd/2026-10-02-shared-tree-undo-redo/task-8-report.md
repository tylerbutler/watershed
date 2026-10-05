# Task 8 report: mixed-client undo and redo through Floodgate

## Base and service identity

- Base commit: `492221c4 test(tree): prove live undo identity`
- Branch: `main`
- Floodgate revision: `0eb493fc46d1bb9baf1151a6ccdde93544e057e7`
- Fluid Framework package: `@fluidframework/tree` `3.1.0`
- Fluid Framework source commit: `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960`
- Required schedule gate: 300 schedules, seed 42

## RED evidence

Command:

```text
node --test tools/shared-tree-oracle/client-driver.test.mjs tools/shared-tree-oracle/client-interop.test.mjs tools/shared-tree-oracle/summary-interop.test.mjs tools/shared-tree-oracle/interop.test.mjs tools/shared-tree-oracle/service.test.mjs
```

Result: 99 tests, 97 passed, 2 failed, 0 skipped.

Representative failures:

```text
TypeError: channel.retainLastLocalCommit is not a function
```

```text
AssertionError [ERR_ASSERTION]: Missing expected exception: section
```

The first failure proves the named-handle client protocol was absent. The
second proves the acceptance validator did not require undo/redo report
sections.

## Test mapping

| Requirement | Test |
| --- | --- |
| Exact named-handle commands | `undo helpers send explicit named-handle commands` |
| Required report sections | `undo and redo coverage rejects missing sections and observations` |
| Three implementations and pairings | `undo and redo coverage rejects missing sections and observations` |
| Both sequence orders and all five field families | `undo and redo coverage rejects missing sections and observations` |
| Native live-handle reconnect | `undo and redo coverage rejects missing sections and observations` |
| Undo/redo 3x3 reload matrix | `undo and redo coverage rejects missing sections and observations` |
| Settlement and outbound evidence | `undo and redo coverage rejects missing sections and observations` |
| No remote revertible factory | `undo and redo coverage rejects missing sections and observations` |
| Seeded retain/revert lifecycle | `seeded release evidence matches every generated action and sequenced commit` and the 300-schedule live gate |

## Changed files

- `test/watershed/tree/client_protocol.gleam`
  - Adds the explicit `retainLastLocalCommit` and `revert` operations and commit
    evidence in checkpoints.
- `test/watershed/tree/client_js.gleam`
  - Acquires revertible factories during local commit delivery, owns named
    handles, performs reverts, and reports kind, status, settlement, outbound,
    and final-state evidence.
- `test/watershed/tree/client_beam.gleam`
  - Adds equivalent client-owned behavior through a child-owned handle-store
    process.
- `test/watershed/shared_tree_client_test.gleam`
  - Updates the checkpoint protocol expectation for commit evidence.
- `tools/shared-tree-oracle/client-driver.mjs`
  - Adds the exact named-handle requests and preserves subprocess stderr on
    client exit.
- `tools/shared-tree-oracle/client-driver.test.mjs`
  - Covers the exact JSON-lines operations and response decoding.
- `tools/shared-tree-oracle/interop-scenarios.mjs`
  - Adds three implementation pairings, five field families, both sequence
    orders, live-handle reconnect, and seeded retain/undo/redo/dispose actions.
- `tools/shared-tree-oracle/summary-interop.mjs`
  - Adds undo and redo summary publication plus the 3x3 writer-reader reload
    matrix.
- `tools/shared-tree-oracle/interop.mjs`
  - Produces and strictly validates all four required undo/redo sections.
- `tools/shared-tree-oracle/interop.test.mjs`
  - Adds complete report fixtures and negative mutations for missing sections,
    implementations, pairings, orders, field rows, reload cells, and
    settlement observations.

## GREEN evidence

### Exact five Node test files

```text
node --test tools/shared-tree-oracle/client-driver.test.mjs tools/shared-tree-oracle/client-interop.test.mjs tools/shared-tree-oracle/summary-interop.test.mjs tools/shared-tree-oracle/interop.test.mjs tools/shared-tree-oracle/service.test.mjs
```

```text
tests 99
pass 99
fail 0
skipped 0
duration_ms 103434.315941
```

### Pinned Floodgate interoperability gate

```text
just shared-tree-interop
```

Exit status: 0.

```text
runId: 22c6c869-7046-4215-bfe5-37f6eaad971a
service: floodgate 0eb493fc46d1bb9baf1151a6ccdde93544e057e7
profileDigest: 588a2f41621f4f352497915168a5dc8af55140721066a04f217ab03e639a1813
javascript corpus: 954 executed
erlang corpus: 972 executed
skipped: []
divergences: []
```

Report:
`tools/shared-tree-oracle/.output/interop/22c6c869-7046-4215-bfe5-37f6eaad971a/report.json`

### Create interoperability gate

```text
just shared-tree-create-interop
```

Exit status: 0.

```text
runId: 4ccb17e0-b76e-4659-8930-b080a817dc7a
report: tools/shared-tree-oracle/.output/creation/4ccb17e0-b76e-4659-8930-b080a817dc7a/report.json
service: floodgate 0eb493fc46d1bb9baf1151a6ccdde93544e057e7
```

### Additional build check

```text
just build
```

The Gleam targets compiled, including the JavaScript and Erlang native clients.
The unrelated `shared_tree_checklist_lustre` bundle then failed during
`pnpm install` because the existing lockfile contains registry tarball URLs
rejected by the active pnpm policy. No dependency manifest or lockfile changed
in Task 8.

The live gate preserved representative task-caused failure artifacts while the
implementation was corrected:

- `tools/shared-tree-oracle/.output/interop/0bbd9f07-ff90-4ffe-8575-d6a953e8b4da/failure.json`
- `tools/shared-tree-oracle/.output/interop/282b35bc-f651-4cb7-a0cb-5b5c5eef42e6/failure.json`
- `tools/shared-tree-oracle/.output/interop/69acb018-952b-4b36-8b74-348d33ad204e/failure.json`

## Row counts

| Section | Required and observed |
| --- | ---: |
| `undoRedoKinds.implementations` | 3 |
| `undoRedoConcurrent` | 30 |
| `undoRedoReconnect` | 2 |
| `undoRedoReloadMatrix` cells | 18 |
| Seeded schedules | 300, seed 42 |
| Skipped rows | 0 |
| Divergences | 0 |

## Self-review

- Clients acquire factories only inside local commit callbacks. The coordinator
  sends named requests and never constructs a handle.
- JavaScript, BEAM, and upstream adapters use the same named-handle lifecycle.
- Reconnect tests keep the original native handle live across reconnection.
- Reload readers prove historical handles are absent, author a fresh edit,
  retain a fresh handle, and undo that edit.
- Concurrent scenarios cover object, map, array, move, and transaction changes
  in both sequence orders for all three pairings.
- Seeded artifacts now include handle lifecycle evidence, and the pinned
  300-schedule run completed without skips or divergences.
- Successful revert responses report one authored outbound operation. This is
  based on the successful authored commit, not a timing-sensitive sample of the
  connected client's pending queue.
- No production dependency, profile pin, service pin, or lockfile changed.

## Fix round 1

Base: `eaa1c686`

### RED evidence

Representative failing tests and live artifacts proved each review gap before
the implementation changed:

- `revertibleStatus` was absent from the native protocol.
- BEAM and JavaScript revert responses returned a constant outbound count and
  inferred the authored kind.
- Whole-tree mutations that lost the peer edit still passed convergence-only
  checks.
- Missing, duplicate, mislabeled, wrong-run, wrong-document, and error-shaped
  undo/redo artifacts were accepted.
- Fake writer versions, summary sequences, and load observations were accepted.
- Historical retain checks caught unrelated errors.
- Seeded lifecycle records could be missing, duplicated, or reordered.
- Generated lifetimes were fixed tails and failure cleanup discarded partial
  observations.

The live iterations also preserved the task-caused failures that exposed
canonical map ordering, discarded upstream summary sequence evidence, BEAM
mailbox settlement ordering, missing quiescent schedule barriers, fast
acknowledgements, and a missing lifecycle label.

### Finding resolution

1. Native clients now measure authored commit events and submitted progress.
   Kinds come from the corresponding local commit event. Reconnect checks the
   named handle status before revert. The coordinator validates measurements
   instead of supplying counts or kinds.
2. Every deterministic undo/redo cell asserts explicit authored, concurrent,
   undone, redone, and final whole trees. The peer edit remains present.
   Reconnect undo restores the captured baseline. Negative mutations prove that
   wrong convergence and lost peer state fail.
3. Kind, concurrent, reconnect, and reload rows are bound to unique verified
   run, document, artifact, measured payload, and raw observation evidence.
   Validation checks exact events, factories, statuses, settlements, counts,
   flags, and errors.
4. All 18 reload cells prove the exact published summary commit and snapshot
   sequence through `storageLoad` or native `loadRequests` evidence. The
   upstream publisher now preserves the submitted reference sequence.
5. Reload readers first require `retainLastLocalCommit("historical")` to fail
   with the exact no-local-commit diagnostic. Loaded observations must contain
   no historical local commit or factory before a fresh edit is retained and
   undone.
6. Seeded artifacts persist ordered lifecycle records. Validation binds every
   retain, undo, redo, and dispose result to commit events, accepted
   settlements, handle transitions, and measured submission counts.
7. Seed 42 schedules integrate legal lifetimes across all five profiles around
   release/acknowledgement, reconnect, and summary/reload spans. Coverage
   includes intervening edits, array transactions, quiescent barriers, and
   explicit disposal.
8. Deterministic, reload, and seeded failures drain best-effort observations
   before cleanup and preserve the primary error, identity, handles, kinds,
   settlements, schedule or cell, and event trace.

### GREEN evidence

```text
node --test tools/shared-tree-oracle/client-driver.test.mjs tools/shared-tree-oracle/client-interop.test.mjs tools/shared-tree-oracle/summary-interop.test.mjs tools/shared-tree-oracle/interop.test.mjs tools/shared-tree-oracle/service.test.mjs
```

102 passed, 0 failed, 0 skipped.

```text
gleam test --target javascript -- shared_tree_client
gleam test --target erlang -- shared_tree_client
```

19 passed per target.

```text
just shared-tree-interop
```

Exit status: 0.

```text
runId: 62798a45-7f90-473b-9aba-abcc295cc3f5
undoRedoKinds.implementations: 3
undoRedoConcurrent: 30
undoRedoReconnect: 2
undoRedoReloadMatrix cells: 18
seeded schedules: 300, seed 42
skipped: 0
```

Report:
`tools/shared-tree-oracle/.output/interop/62798a45-7f90-473b-9aba-abcc295cc3f5/report.json`

```text
just shared-tree-create-interop
```

Exit status: 0.

Report:
`tools/shared-tree-oracle/.output/creation/cf81bc8d-9610-487a-bb7f-c498f9f5e249/report.json`

One unrelated Floodgate synchronization timeout occurred in a schema schedule
with no undo/redo actions during an earlier retry. The successful pinned run
completed all required cells and schedules.

## Fix round 2

Base: `83880c9a`

### RED evidence

Five focused review tests failed before the implementation changed:

- synchronized report and measured mutations could hide changed concurrent
  trees and commit traces;
- kind rows did not resolve their source artifacts;
- reload rows accepted a lower snapshot sequence copied into both the report
  and measured claim;
- seeded lifecycle rows accepted missing factory events, missing accepted
  revisions, failed settlements, and success-shaped errors;
- a failed client drain discarded observations and checkpoints from surviving
  clients.

Result: 5 tests, 0 passed, 5 failed.

### Finding resolution

1. JavaScript and BEAM clients assign monotonic local commit-event IDs. Revert
   responses return the authored event IDs and the submitted revisions that
   belong to the retained commit's originator. Counts come from those arrays,
   and validation requires exactly one authored event and one submitted
   revision.
2. Validators derive concurrent trees, commit traces, reconnect state, reload
   state, and kind coverage from raw checkpoints, lifecycle responses, event
   traces, and sequenced history. Kind rows resolve and validate their source
   artifacts. Coordinated report and measured mutations no longer pass when
   raw evidence disagrees.
3. Reload evidence records the publication version, publication reference
   sequence, consumed snapshot sequence, and replay start. Validation requires
   exact equality for the published and consumed snapshot identity, then checks
   the replay boundary separately.
4. Seeded retain, undo, redo, settlement, and dispose records now correlate to
   factory events, authored event IDs, submitted revisions, accepted sequenced
   operations, settlements, and handle transitions. Error-shaped successes and
   failed settlements fail validation.
5. Deterministic, reconnect, reload writer and reader, and seeded failure paths
   use all-settled drains. They retain successful client observations, rejected
   clients' attached checkpoints, the original primary error, and separate
   drain errors.

The final live gate also exposed two report-collection defects. Kind rows reuse
verified concurrent artifacts, so the collector now adds each source artifact
once while preserving duplicate rejection for primary artifacts. Reconnect
validation now selects the target implementation from the raw checkpoint's
observation list.

### GREEN evidence

Focused review tests: 5 passed, 0 failed.

```text
gleam test --target javascript -- shared_tree_client
gleam test --target erlang -- shared_tree_client
```

20 passed per target.

```text
node --test tools/shared-tree-oracle/client-driver.test.mjs tools/shared-tree-oracle/client-interop.test.mjs tools/shared-tree-oracle/summary-interop.test.mjs tools/shared-tree-oracle/interop.test.mjs tools/shared-tree-oracle/service.test.mjs
```

108 passed, 0 failed, 0 skipped.

```text
just shared-tree-interop
```

Exit status: 0.

```text
runId: 4cb348d3-df49-4d06-ac6b-d2d66b333273
undoRedoKinds.implementations: 3
undoRedoConcurrent: 30
undoRedoReconnect: 2
undoRedoReloadMatrix cells: 18
seeded schedules: 300, seed 42
javascript corpus: 956
erlang corpus: 974
skipped: 0
divergences: 0
```

Report:
`tools/shared-tree-oracle/.output/interop/4cb348d3-df49-4d06-ac6b-d2d66b333273/report.json`

```text
just shared-tree-create-interop
```

Exit status: 0.

```text
runId: 248840f9-35c2-41b2-8cf4-bc84d436f4cc
cells: 18
skipped: 0
divergences: 0
```

Report:
`tools/shared-tree-oracle/.output/creation/248840f9-35c2-41b2-8cf4-bc84d436f4cc/report.json`

### Failed runs and replay

- `1af16e22-beff-4902-bdf8-3bf868a6a7ff` exposed a BEAM deadlock caused by
  querying history inside the synchronous commit callback.
- `74cdc6a7-64d1-4f3b-8db5-a6a22aad8277` exposed global revision-delta
  counting when a peer submitted concurrently.
- Replay `23368fa2-2b07-4af6-83fd-c9057448b699` passed after revision evidence
  was scoped to the retained commit's originator.
- `b417e705-1e98-4af9-9ea2-a93e1bc80aed` exposed duplicate evidence requests
  for kind rows that reuse concurrent artifacts.
- `e634768b-b1dc-4e78-8003-a32221c5fb95` exposed reconnect validation against
  a nonexistent top-level `wholeTree` instead of the target raw observation.

No infrastructure-only transient retry was required for the final successful
interop or create-interop runs.

## Fix round 3

Base: `8c229a9c`

### RED evidence

The five review counterexamples failed before the implementation changed:

```text
tests 5
pass 0
fail 5
```

- A revert could claim one outbound operation from history while the client
  sent the operation twice.
- A kind row could reference an incomplete source artifact.
- Reload validation could accept copied publication and load scalars without
  observing the reader's storage response.
- Seeded BEAM evidence could replace or remove the Default revision and still
  pass through null-revision correlation.
- One failed client could discard surviving Undo checkpoints at the settle
  boundary.

### Finding resolution

1. JavaScript, BEAM, and upstream clients record outbound operations at their
   native transport boundary. Each record includes a send ID, stable client
   instance ID, transport client ID and sequence, decoded originator/revision
   operation ID, authored event ID, classification, and raw payload. A retry
   keeps the same originator/revision ID and receives the
   `reconnect-retry` classification. Validators count only records classified
   as `original`, require one original send, and bind the accepted server
   operation to the exact original or retry transport occurrence.
2. One recursive validator checks each kind row's complete source artifact:
   phase checkpoints, expected trees, final tree, lifecycle, event and
   settlement traces, factories, statuses, counts, accepted operations,
   concurrent retain results, and handle transitions.
3. Publication evidence stores the native summarize response or upstream
   summary acknowledgement. Native reader evidence comes from the proxied Git
   blob response that contains the decoded `.protocol/attributes` body.
   Upstream reader evidence comes from the storage driver's `readBlob`
   response. Version and snapshot sequence must match. Replay start remains a
   separate value derived from delivery, handshake, or delta-storage records.
4. BEAM commit and settlement evidence carries a stable action ID. Seeded
   validation scopes events by the adapter instance ID, joins event ID plus
   revision or action ID, decodes raw accepted operations, and rejects
   duplicate originator/revision IDs. `sequencedHistory` cannot replace raw
   accepted operations.
5. Checkpoint collection uses `Promise.allSettled`. It stores each fulfilled
   observation and each rejected client's partial checkpoint before queue
   drainage. The primary error receives the combined checkpoint and
   per-client errors. Cleanup appends errors without replacing the primary
   failure.

### Raw evidence shapes

The successful pinned run recorded an upstream reconnect retry in
`seeded/107.json`:

```json
{
  "authoredEventIds": [7],
  "submittedRevisions": ["518"],
  "outboundRecords": [
    {
      "sendId": 4,
      "classification": "original",
      "operationId": "revision:23615654-0f21-406c-b888-ac7e75de5d2c:518",
      "clientInstanceId": "9cbf8399-6183-4c99-9f76-1afc8ca9397d",
      "clientId": "F91D0B86ADB6F3F05CF69040AF43497A",
      "clientSequenceNumber": 1,
      "authoredEventId": 7
    },
    {
      "sendId": 5,
      "classification": "reconnect-retry",
      "operationId": "revision:23615654-0f21-406c-b888-ac7e75de5d2c:518",
      "clientInstanceId": "9cbf8399-6183-4c99-9f76-1afc8ca9397d",
      "clientId": "516981E1151387FC2A91A5E7F967EB68",
      "clientSequenceNumber": 1,
      "authoredEventId": 7
    }
  ]
}
```

The server accepted the retry transport occurrence once:

```json
{
  "operationId": "revision:23615654-0f21-406c-b888-ac7e75de5d2c:518",
  "clientId": "516981E1151387FC2A91A5E7F967EB68",
  "clientSequenceNumber": 1,
  "outerSequenceNumber": 20,
  "commits": [
    {
      "revision": 518,
      "originatorId": "23615654-0f21-406c-b888-ac7e75de5d2c"
    }
  ]
}
```

The JavaScript writer to Erlang reader undo reload recorded independent
publication and load identities:

```json
{
  "publication": {
    "version": "2e9190958150974c3da5eb7f394ebd63f11c0fde",
    "snapshotSequenceNumber": 8,
    "referenceSequenceNumber": 8
  },
  "rawLoadIdentity": {
    "loadedVersion": "2e9190958150974c3da5eb7f394ebd63f11c0fde",
    "snapshotSequenceNumber": 8,
    "observationIndex": 4
  },
  "replayStartSequenceNumber": 8,
  "replayEvidence": "native-handshake"
}
```

The settle-boundary regression records the primary error with:

```text
checkpoint.observations:
  upstream fulfilled checkpoint
  javascript fulfilled checkpoint with surviving Undo commit
  erlang partial checkpoint with surviving Undo commit
clientErrors:
  erlang -> original primary error
```

### GREEN evidence

Focused review tests:

```text
tests 5
pass 5
fail 0
skipped 0
duration_ms 18992.282187
```

Native client suites:

```text
gleam test --target javascript -- shared_tree_client
20 passed

gleam test --target erlang -- shared_tree_client
20 passed
```

Exact five Node files:

```text
node --test tools/shared-tree-oracle/client-driver.test.mjs tools/shared-tree-oracle/client-interop.test.mjs tools/shared-tree-oracle/summary-interop.test.mjs tools/shared-tree-oracle/interop.test.mjs tools/shared-tree-oracle/service.test.mjs
```

```text
tests 112
pass 112
fail 0
skipped 0
duration_ms 149611.732341
```

Storage-response boundary tests:

```text
node --test tools/shared-tree-oracle/delivery-gate.test.mjs
tests 12
pass 12
fail 0
```

Pinned Floodgate interoperability gate:

```text
TMPDIR=/home/tylerbu/.copilot/session-state/639fae85-1eeb-4848-adc3-c4b99863f12c/files/tmp-round3 just shared-tree-interop
```

Exit status: 0.

```text
runId: 86cc410f-8ec1-4383-9735-da0eec5454d9
profileDigest: 588a2f41621f4f352497915168a5dc8af55140721066a04f217ab03e639a1813
undoRedoKinds.implementations: 3
undoRedoConcurrent: 30
undoRedoReconnect: 2
undoRedoReloadMatrix cells: 18
seeded schedules: 300, seed 42
javascript corpus: 956
erlang corpus: 974
skipped: 0
divergences: 0
```

Report:
`tools/shared-tree-oracle/.output/interop/86cc410f-8ec1-4383-9735-da0eec5454d9/report.json`

Create interoperability gate:

```text
TMPDIR=/home/tylerbu/.copilot/session-state/639fae85-1eeb-4848-adc3-c4b99863f12c/files/tmp-round3 just shared-tree-create-interop
```

Exit status: 0.

```text
runId: 5129f9f0-d2e0-4289-a4d3-38a9f1c2d568
cells: 18
skipped: 0
divergences: 0
```

Report:
`tools/shared-tree-oracle/.output/creation/5129f9f0-d2e0-4289-a4d3-38a9f1c2d568/report.json`

### Concerns

The host `/tmp` filesystem had no free inodes because old Watershed test
directories remained there. All final commands used the session `TMPDIR`
shown above. One pinned retry stopped on the existing Erlang schema-reload
continuation timeout before seeded acceptance. The next run completed the same
300 schedules with no skips or divergences.

## Fix round 4

### RED evidence

The five new counterexamples failed before the implementation changes:

```text
tests 5
pass 0
fail 5
skipped 0
duration_ms 9204.08572
```

The failures covered:

- a same-transport duplicate with a forged `reconnect-retry` label;
- made-up BEAM stable revisions, missing raw accepted payloads, missing
  sequenced history, and a null revision paired with a forged action ID;
- a wrong loaded tree, false retained factory, removed local-event factory,
  and `Valid` post-undo status;
- a changed raw selected blob response with unchanged copied load fields;
- a second checkpoint-collection failure that discarded the first collection's
  surviving `Undo` observation.

### Implementation

Outbound evidence now records `transportId`, `connectionEpoch`, and
`stableRevision` for every native send occurrence. Repeated operation IDs on
the same transport are classified as `duplicate-send`; only the same operation
on a different observed transport can be a `reconnect-retry`. Validation
rejects duplicate send IDs, same-transport duplicates, and retry labels without
a later transport epoch.

Revert results now carry an exact action ID. The validator joins that action ID,
the authored event ID, the stable submitted revision, the outbound raw payload,
the settlement, and the server-accepted raw operation. BEAM events with no
revision can use the exact action ID join, but null revisions no longer act as
a wildcard. Accepted operations are decoded during validation from preserved
raw server payloads; the pre-derived `acceptedOperations` field must equal that
decode.

Reconnect artifacts now preserve the retained response and the raw
before-disconnect, after-reconnect, and post-undo status observations. Reload
artifacts preserve the loaded tree, expected published tree, final restored
tree, fresh `Default` factory, and post-undo status.

Native storage evidence now records the selected response chain:

```text
commit version -> root tree -> .protocol tree -> attributes blob
```

The raw load identity includes the commit, root tree, protocol tree, blob,
response hash, and snapshot sequence. Replay start remains separate. Upstream
readers continue to bind their selected version, tree, and `readBlob` identity
at the service boundary.

Checkpoint failures now merge prior fulfilled collections, the failing
collection's fulfilled and partial observations, and the later drain without
overwriting the primary checkpoint.

### Representative raw evidence

The successful Erlang reconnect row records:

```text
retained:
  eventId: 1
  actionId: a3423208-ff57-4280-8ece-f59f69ede6c6
  revision: 9f86f312-04e6-455d-b47d-66add5e54ecd
  sendId: 1
  classification: original
  operationId: revision:9f86f312-04e6-455d-b47d-66add5e54ecd:-1
  clientInstanceId: b095147b-efb6-4922-9681-b2f00c44dd75
  transportId: 80FC5B57AEF3DE27ACC6F32EF211B4B5
  connectionEpoch: 1
  stableRevision: 9f86f312-04e6-455d-b47d-66add5e54ecd

undo:
  actionId: 3bda86fb-05a1-4023-8dde-eff1a9405857
  authoredEventIds: [2]
  submittedRevisions: [9f86f312-04e6-455d-b47d-66add5e54ece]
  classification: original
  transportId: 8EB596A572600B8A833A593A6D632F26
  stableRevision: 9f86f312-04e6-455d-b47d-66add5e54ece

reconnectLifecycle:
  beforeDisconnect.status: Valid
  afterReconnect.status: Valid
  postUndo.status: Disposed
```

The successful JavaScript reload row records:

```text
rawLoadIdentity:
  loadedVersion: 58acc2852ae1da0f7117ce9c4325e03aa56413cb
  rootTreeId: ba4665f4050d77a8b8baec62e7f36a945fffa745
  protocolTreeId: bd973fec0906b2e0491247dcfec62acc8a4ec7ae
  blobId: cca6011baa96641a1a1765212dba1f99a4d2959f
  responseHash: 746c120824341e42ade0114f686219c95fb6dc09760ee96739bc9364c1f28a39
  snapshotSequenceNumber: 8
postUndoStatus: Disposed
loadedTreeEqualsFinal: true
```

The two-collection failure regression preserves the first `Undo` checkpoint
before the later partial checkpoint in `error.checkpoint.observations`.

### GREEN evidence

Focused review tests:

```text
tests 5
pass 5
fail 0
skipped 0
duration_ms 10055.736853
```

Native client suites:

```text
gleam test --target javascript -- shared_tree_client
20 passed

gleam test --target erlang -- shared_tree_client
20 passed
```

Exact five Node files:

```text
node --test tools/shared-tree-oracle/client-driver.test.mjs tools/shared-tree-oracle/client-interop.test.mjs tools/shared-tree-oracle/summary-interop.test.mjs tools/shared-tree-oracle/interop.test.mjs tools/shared-tree-oracle/service.test.mjs
```

```text
tests 117
pass 117
fail 0
skipped 0
duration_ms 167198.613057
```

Storage-response boundary tests:

```text
node --test tools/shared-tree-oracle/delivery-gate.test.mjs
tests 13
pass 13
fail 0
skipped 0
duration_ms 936.394101
```

Pinned Floodgate interoperability gate:

```text
TMPDIR=/home/tylerbu/.copilot/session-state/639fae85-1eeb-4848-adc3-c4b99863f12c/files/tmp-round4 just shared-tree-interop
```

Exit status: 0.

```text
runId: ca44d197-746e-46d8-8efb-bcbdfd624ba3
profileDigest: 588a2f41621f4f352497915168a5dc8af55140721066a04f217ab03e639a1813
undoRedoKinds.implementations: 3
undoRedoConcurrent: 30
undoRedoReconnect: 2
undoRedoReloadMatrix cells: 18
seeded schedules: 300, seed 42
javascript corpus: 956
erlang corpus: 974
skipped: 0
divergences: 0
```

Report:
`tools/shared-tree-oracle/.output/interop/ca44d197-746e-46d8-8efb-bcbdfd624ba3/report.json`

Create interoperability gate:

```text
TMPDIR=/home/tylerbu/.copilot/session-state/639fae85-1eeb-4848-adc3-c4b99863f12c/files/tmp-round4 just shared-tree-create-interop
```

Exit status: 0.

```text
runId: 360d5d6f-196a-4e23-8dcb-9768c540d8dc
profileDigest: 588a2f41621f4f352497915168a5dc8af55140721066a04f217ab03e639a1813
cells: 18
skipped: 0
divergences: 0
```

Report:
`tools/shared-tree-oracle/.output/creation/360d5d6f-196a-4e23-8dcb-9768c540d8dc/report.json`

### Concerns

The first pinned run reached final validation and exposed an overconstraint that
required native HTTP storage evidence for the upstream reader. Upstream now
uses its actual service `getVersions`, tree, and `readBlob` response identity;
native readers require the HTTP commit/tree/blob chain.

Two later pinned attempts ended before a successful report: one stopped during
the existing refusal matrix without a coordinator failure artifact, and one
exposed a BEAM event with a null revision before its retained action resolved.
The exact action ID join handles that valid BEAM shape without restoring a null
revision wildcard. The final 300-schedule run passed with no skips or
divergences.

## Fix round 5

### Scope

This round closes the final five reproduced false-pass classes:

1. Outbound multiplicity now comes from gateway-observed connection
   occurrences. A retry requires another observed connection epoch. Mutable
   payload classifications cannot turn a duplicate on one transport into a
   retry.
2. Upstream and native actions carry `revisionResolution` with the exact action
   ID, local wire revision when available, and decompressed stable revision.
   Validation decodes preserved server payloads, matches the accepted wire
   operation, and proves that the stable UUID is inside its accepted allocation
   range. A null commit-event revision is valid only through this exact action
   resolution.
3. Reconnect and reload claims are checked against raw events, statuses,
   factories, checkpoints, and storage responses. Reload compares the reader
   tree with both the writer publication checkpoint and the final restored
   tree.
4. Snapshot identity is derived from the selected commit, root tree, protocol
   tree, attributes blob, response hash, and snapshot sequence at the actual
   storage boundary. Replay start remains separate.
5. Collection failures preserve the original merged checkpoint as
   `primaryCheckpoint`. Later cleanup observations are appended separately as
   `drainCheckpoint` across deterministic, reconnect, reload writer/reader, and
   seeded paths.

Upstream action evidence remains attached to the runtime after the action
returns. If the runtime later resubmits that operation after reconnect, the
same action evidence gains the new observed send and connection epoch. This is
required when the server accepts the retry rather than the first transport
occurrence.

### RED evidence

The five exact review counterexamples failed before the implementation:

```text
node --test --test-name-pattern='round 5' tools/shared-tree-oracle/interop.test.mjs
tests 5
pass 0
fail 5
```

The mutations cover a forged same-transport retry label, coordinated stable
revision fabrication, copied reload lifecycle trees, copied storage identity
with an unchanged raw response, and replacement of an earlier successful
checkpoint by a later failure.

### Representative raw evidence

Successful seeded schedule 227 records one original occurrence and one
reconnect retry for the same accepted operation:

```text
index: 227
template: schema-reconnect-summary
actionId: event-7
localRevision: 518
stableRevision: 66fd18b2-1a67-4040-91f2-e0b2983c5d0e
outboundRecords: 2
transportConnections:
  - epoch: 1
    connectionId: 469112599303BDAA452E0221A50C05E6
  - epoch: 2
    connectionId: 256E2FA598B3B2E6E710C5ABA633820F
```

The accepted operation is decoded from `raw.acceptedOperationPayloads`. Its
wire revision and originator are joined to `revisionResolution`, the authored
event, settlement, outbound payload, and accepted allocation. The stable UUID
is not read from `raw.acceptedOperations` or `sequencedHistory`.

A successful native reload row records:

```text
publication.version: 5268f46a7a3e7e004823fa879d3820c8008c4497
publication.snapshotSequenceNumber: 8
rawLoadIdentity.commitId: 5268f46a7a3e7e004823fa879d3820c8008c4497
rawLoadIdentity.rootTreeId: 752782d2773e5737a54222e8febefeb0f02b8e7c
rawLoadIdentity.protocolTreeId: 26669b9943ffa346adbc4c9fca791615ffa31a76
rawLoadIdentity.blobId: cca6011baa96641a1a1765212dba1f99a4d2959f
rawLoadIdentity.responseHash: 9a8eca9df3d807f1855fe4defb1c24828725a82811d4dabb7294e81d62a5a570
rawLoadIdentity.snapshotSequenceNumber: 8
replayStartSequenceNumber: 8
postUndoStatus: Disposed
loadedTreeEqualsFinal: true
```

The identity is reconstructed from
`raw.boundaryStorageResponses`; copied `loadEvidence` values are checked
against, but cannot replace, those responses.

Failure evidence uses this shape:

```text
error.checkpoint === error.primaryCheckpoint
error.primaryCheckpoint.observations: all fulfilled observations available at
  the original collection boundary, including the failing collection's partial
  observations
error.drainCheckpoint.observations: later cleanup drain only
```

### GREEN evidence

Focused review tests:

```text
tests 5
pass 5
fail 0
skipped 0
duration_ms 17108.145411
```

Native client suites:

```text
gleam test --target javascript -- shared_tree_client
20 passed

gleam test --target erlang -- shared_tree_client
20 passed
```

Exact five Node files:

```text
node --test tools/shared-tree-oracle/client-driver.test.mjs tools/shared-tree-oracle/client-interop.test.mjs tools/shared-tree-oracle/summary-interop.test.mjs tools/shared-tree-oracle/interop.test.mjs tools/shared-tree-oracle/service.test.mjs
```

```text
tests 122
pass 122
fail 0
skipped 0
duration_ms 248116.155606
```

Storage and transport boundary tests:

```text
node --test tools/shared-tree-oracle/delivery-gate.test.mjs
tests 14
pass 14
fail 0
skipped 0
duration_ms 713.912936
```

Pinned Floodgate interoperability gate:

```text
TMPDIR=/home/tylerbu/.copilot/session-state/639fae85-1eeb-4848-adc3-c4b99863f12c/files/tmp-round5 just shared-tree-interop
```

Exit status: 0.

```text
runId: 92f2b012-9e92-495b-a5f5-6eae3aaa5a4c
profileDigest: 588a2f41621f4f352497915168a5dc8af55140721066a04f217ab03e639a1813
undoRedoKinds.implementations: 3
undoRedoConcurrent: 30
undoRedoReconnect: 2
undoRedoReloadMatrix cells: 18
seeded schedules: 300, seed 42
javascript corpus: 956
erlang corpus: 974
skipped: 0
divergences: 0
```

Report:
`tools/shared-tree-oracle/.output/interop/92f2b012-9e92-495b-a5f5-6eae3aaa5a4c/report.json`

Create interoperability gate:

```text
TMPDIR=/home/tylerbu/.copilot/session-state/639fae85-1eeb-4848-adc3-c4b99863f12c/files/tmp-round5 just shared-tree-create-interop
```

Exit status: 0.

```text
runId: ecd3df6d-745c-477a-9470-606963ca0944
profileDigest: 588a2f41621f4f352497915168a5dc8af55140721066a04f217ab03e639a1813
cells: 18
skipped: 0
divergences: 0
```

Report:
`tools/shared-tree-oracle/.output/creation/ecd3df6d-745c-477a-9470-606963ca0944/report.json`

### Concerns

Several full runs were useful failures before the final pass:

- `f39338f7-1c70-4223-a667-487c18970165` exposed that upstream checkpoint
  history preserves the local wire revision while action evidence carries the
  decompressed stable UUID.
- `2f881a86-7d98-4bfd-b7b5-468dd6548bab` exposed the same valid local-to-stable
  transition in an earlier seeded checkpoint.
- `77716631-9cfd-4838-b1e6-26af818e67ae` exposed inconsistent global versus
  action-local epoch numbering in producer evidence.
- `d1ab89d2-8eb7-4cda-9185-5d4a33a4c033` exposed an operation accepted only
  after a later reconnect retry; action evidence now preserves that retry.
- `d02d52b9-c691-4cac-a309-8dd943113d87` stopped in the existing live schema
  reload matrix because an Erlang continuation was not observed. The retry
  passed that matrix and the complete gate.

Floodgate continues to emit its existing decode warnings for transport-control
and non-event Socket.IO frames. They did not cause skips or divergences in the
successful runs.

## Completion pass after review cap

Base: `d9f404e8` on current `main`. This pass used no branch, worktree,
subagent, or reviewer. Tasks 1-7, the public undo/redo API, dependency versions,
and service/profile pins remain unchanged.

### Findings and root-cause fixes

1. **Duplicate retry transport pairs.** The validator compared each retry with
   the original connection, so two sends on the second connection both counted
   as retries. It now compares with the preceding observed connection and
   requires an increasing epoch for a retry. The native collector also retains
   matching raw occurrences that have no corresponding client send record.
   Previously, filtering by matched records could erase an unreported duplicate.
   Both native binding and upstream normalization use the corrected retry rule.
2. **Exact compressor reconstruction.** Allocation-range membership allowed a
   client to substitute another allocated UUID. The service now captures the
   initial compressor serialization when it creates the document. The
   validator restores that state with the pinned ID compressor, applies raw
   accepted allocation operations in sequence, and decompresses the accepted
   wire revision in the accepted originator's session. It compares that result
   with the action's stable revision. Positive final-space IDs and negative
   local IDs have separate adversarial cases. Neither copied history nor a
   nullable event revision supplies the accepted identity.
3. **Lifecycle field joins.** Reconnect and reload now join the authored kind,
   handle name/status, retained kind/status, factory acquisition, settlement,
   authored count, and outbound count to their action evidence. Reconnect
   validates the final checkpoint's events against the event trace and runs
   the Undo action checks against that checkpoint. Settlement validation rejects
   a contradictory outcome for the same action even when another observation
   says `FullyApplied`.
4. **Request-bound storage responses.** Native storage evidence includes the
   response bytes from the HTTP boundary. Validation recomputes SHA-256,
   decodes identity from the actual request path and body, and joins the
   selected commit, root tree, protocol tree, and attributes blob. It rejects
   conflicting responses to the same object request. Upstream storage evidence
   records the request arguments and raw response bytes for versions, snapshots,
   and blobs. Validation binds the selected snapshot request to its version
   and tree and derives the snapshot sequence from the blob bytes. Injected
   HTTP responses now carry the hash and status of the bytes the reader receives.
5. **Reconnect failure history.** Synchronization now uses the same
   all-settled collector as checkpoints, including each rejected client's
   partial observation. The reconnect runner records successful phases as
   they finish, merges them with the failing phase before cleanup, and retains
   that object as both `checkpoint` and `primaryCheckpoint`. Cleanup observations
   go into `drainCheckpoint`. An executable runner test replaces the earlier
   reliance on helper assertions and source-text matching.

### RED/GREEN evidence

Commands using temporary fixtures ran with:

```text
TMPDIR=/home/tylerbu/.copilot/session-state/f0314904-8ed9-4e5b-8ddb-7339a023eb18/files/tmp
```

Each command below ran before its corresponding fix and then after it.
The first compressor test attempt hit a test setup error because it tried to
replace the frozen artifact's `raw` property. After correcting the test to
mutate its contents, RED showed the intended false pass.

| Finding | Command following `node --test` | RED | GREEN |
| --- | --- | --- | --- |
| Duplicate retry pair | `--test-name-pattern='completion rejects duplicate' tools/shared-tree-oracle/interop.test.mjs` | 1 failed: `Missing expected exception` | 1 passed |
| Omitted raw duplicate | `--test-name-pattern='completion preserves unmatched' tools/shared-tree-oracle/interop.test.mjs` | 1 failed: `1 !== 2`, unreported duplicate disappeared | 1 passed |
| Exact compressor identity | `--test-name-pattern='completion reconstructs' tools/shared-tree-oracle/interop.test.mjs` | 1 failed: `Missing expected exception` for another allocated UUID | 1 passed, negative and positive wire IDs |
| Lifecycle fields | `--test-name-pattern='completion joins' tools/shared-tree-oracle/interop.test.mjs` | 17 failed, 2 passed; 16 previously accepted field mutations plus parent failure | All field mutations rejected |
| Final checkpoint join | `--test-name-pattern='completion joins reconnect events' tools/shared-tree-oracle/interop.test.mjs` | 1 failed: `Missing expected exception` | 1 passed |
| Contradictory settlements | `--test-name-pattern='completion joins reconnect and reload' tools/shared-tree-oracle/interop.test.mjs` | Both added contradictory-settlement subtests failed with `Missing expected exception` | Both passed |
| Storage request/body binding | `--test-name-pattern='completion binds' tools/shared-tree-oracle/summary-interop.test.mjs` | 9 failed, 1 passed; copied hashes/sequences and another snapshot request passed validation | All request/body mutations rejected |
| Conflicting storage response | `--test-name-pattern='completion binds native' tools/shared-tree-oracle/summary-interop.test.mjs` | Added subtest failed with `Missing expected exception` | Added subtest passed |
| Fail-fast synchronization | `--test-name-pattern='completion preserves every partial' tools/shared-tree-oracle/interop.test.mjs` | Actual kinds: `Default, Default, Default`; expected also `Undo, Redo` | 1 passed with both partial observations |
| Actual reconnect failure path | `--test-name-pattern='completion reconnect failure' tools/shared-tree-oracle/interop.test.mjs` | `The primary checkpoint lost the successful edited phase` | 1 passed with earlier phase, partial Undo, and separate drain |

Combined focused command:

```text
node --test --test-name-pattern='completion' tools/shared-tree-oracle/interop.test.mjs tools/shared-tree-oracle/summary-interop.test.mjs
tests 38
pass 38
fail 0
skipped 0
duration_ms 25874.496953
```

The round-5 test that treated a null event revision as acceptable despite a
different final-checkpoint revision now expects rejection. The first full
Node run exposed that obsolete expectation: 170 tests, 169 passed, 1 failed.
The focused rerun of the revised test passed.

### Changed files

- `tools/shared-tree-oracle/interop.mjs`: transport, compressor, lifecycle,
  checkpoint, and settlement validation.
- `tools/shared-tree-oracle/interop-scenarios.mjs`: raw duplicate preservation,
  retry classification, initial compressor evidence, all-settled
  synchronization, and reconnect failure history.
- `tools/shared-tree-oracle/service.mjs`: creation-time compressor capture and
  upstream storage request/response observations.
- `tools/shared-tree-oracle/delivery-gate.mjs`: raw native storage response bytes
  and delivered-response hash/status.
- `tools/shared-tree-oracle/summary-interop.mjs`: request/hash-bound storage
  decoding and compressor evidence in reload artifacts.
- `tools/shared-tree-oracle/interop.test.mjs`: adversarial regressions, executable
  reconnect failure coverage, and protocol-valid UUID/allocation fixtures.
- `tools/shared-tree-oracle/summary-interop.test.mjs`: raw-byte/request mutations
  and consistent native storage fixtures.
- `tools/shared-tree-oracle/service.test.mjs`: observed request and raw-response
  contract.
- `tools/shared-tree-oracle/delivery-gate.test.mjs`: response bytes, hashes, and
  injection-boundary checks.
- This report: appended completion evidence; prior evidence remains intact.

### Full gates

Exact five Node files:

```text
node --test tools/shared-tree-oracle/client-driver.test.mjs tools/shared-tree-oracle/client-interop.test.mjs tools/shared-tree-oracle/summary-interop.test.mjs tools/shared-tree-oracle/interop.test.mjs tools/shared-tree-oracle/service.test.mjs
tests 160
pass 160
fail 0
skipped 0
duration_ms 442917.567277
```

Transport/storage boundary suite:

```text
node --test tools/shared-tree-oracle/delivery-gate.test.mjs
tests 14
pass 14
fail 0
skipped 0
duration_ms 1461.966524
```

Create interoperability gate:

```text
TMPDIR=/home/tylerbu/.copilot/session-state/f0314904-8ed9-4e5b-8ddb-7339a023eb18/files/tmp just shared-tree-create-interop
exit status: 0
runId: 28822486-a6de-453e-93a2-edf608b20bd1
service: floodgate 0eb493fc46d1bb9baf1151a6ccdde93544e057e7
profileDigest: 588a2f41621f4f352497915168a5dc8af55140721066a04f217ab03e639a1813
cells: 18
skipped: 0
divergences: 0
```

Report:
`tools/shared-tree-oracle/.output/creation/28822486-a6de-453e-93a2-edf608b20bd1/report.json`

Pinned Floodgate interoperability gate:

```text
TMPDIR=/home/tylerbu/.copilot/session-state/f0314904-8ed9-4e5b-8ddb-7339a023eb18/files/tmp just shared-tree-interop
exit status: 0
runId: 227906cc-54ee-4093-8890-5a943fcf6b33
service: floodgate 0eb493fc46d1bb9baf1151a6ccdde93544e057e7
profileDigest: 588a2f41621f4f352497915168a5dc8af55140721066a04f217ab03e639a1813
undoRedoKinds.implementations: 3
undoRedoConcurrent: 30
undoRedoReconnect: 2
undoRedoReloadMatrix cells: 18
seeded schedules: 300, seed 42
javascript corpus: 956
erlang corpus: 974
skipped: 0
divergences: 0
```

Report:
`tools/shared-tree-oracle/.output/interop/227906cc-54ee-4093-8890-5a943fcf6b33/report.json`

I added the final negative-case guards while that live run was in progress.
After it finished, I reopened its 811 artifact references with
`createArtifactEvidence` and called `validateInteropReport` using the final
source, the pinned profile, seed 42, and 300 iterations. That validation exited
0 with the same counts above. The final five-file Node run and delivery suite
also used the final implementation.

### Remaining diagnostics

The pinned service emitted its existing Socket.IO transport-control decode
warnings. Upstream Fluid also emitted `0x92a` assertion telemetry for document
`413E5FCB3878DF65FC7739692E216A6B` during seeded schedule 12, from the bootstrap
creator and a summarizer. The gate continued, verified all three measured
clients, and reported no skipped schedules or divergences. This pass does not
change upstream Fluid or suppress that telemetry.

Session logs remain under
`/home/tylerbu/.copilot/session-state/f0314904-8ed9-4e5b-8ddb-7339a023eb18/files/`.
I removed the completed unit-test fixture directories from the session
`TMPDIR`; live gate artifacts remain in `.output`.

### Self-review

The review traces report claims back to separate observations: transport
occurrences and connection epochs; creation-time compressor bytes plus raw
accepted allocations and wire operations; local events and final checkpoints;
and storage request arguments/paths plus response bytes. Derived classifications,
`revisionResolution`, `sequencedHistory`, copied load identities, and
success-shaped row fields do not establish those identities on their own.
The new tests include valid controls before mutation and check the previously
accepted evidence rather than source spelling.

The final review covered the complete diff from `d9f404e8`, including all
shared-validator callers. It confirmed that retry classification cannot add
transport evidence, allocation membership cannot substitute for decompression,
an unrelated successful settlement cannot hide a contradictory outcome, and
copied storage identity fields cannot replace hash-checked response bytes.
Reconnect cleanup retains the original merged primary checkpoint. No generated,
`.code-map`, or apm-managed file is part of the commit.

## Fix follow-up after independent review of 81c679ec

I reproduced both Important findings on `81c679ec` and fixed them on current
`main`. I used no branch, worktree, subagent, or reviewer. The findings correct
two claims in the preceding completion pass: upstream connection evidence still
came from normalized records, and deleting derived storage metadata could skip
validation of preserved response bytes.

### Findings and changes

1. **Upstream transport capture.** `openSession` now observes the returned
   driver's `connectToDeltaStream` and `submit` calls for both newly created and
   loaded documents. A completed connection call records its own connection ID,
   epoch, and handshake client ID before any send. Submission capture clones the
   driver's messages and associates them with that connection. Session readers
   receive cloned snapshots, so later normalization cannot change the captured
   observations. The adapter binds normalized records through the existing
   `bindOutboundTransport` helper. Neither normalization nor
   `outboundTransportEvidence` creates connection events.

   A local Floodgate probe exposed another consequence of the old boundary:
   `deltaManager.submitOp` can fire on a read connection for a queued operation
   that never reaches the driver. The first probe timed out waiting for that
   nonexistent transport occurrence. I removed this source of send records;
   the adapter now normalizes actual driver submissions and refreshes retained
   action evidence at checkpoints. The repeated probe covered create, load,
   edit, reconnect, and undo through the real driver and passed for both
   sessions.

   A subsequent full run exposed a required distinction: a handle can be
   retained while the coordinator holds the outbound queue. Waiting for an
   actual send at that point deadlocks the scenario. A new live regression
   reproduced this failure. Retain/revert now read the stable revision from
   the runtime compressor and return without inventing a send. Until the
   driver submits the operation, raw send arrays remain empty and the measured
   outbound count stays zero. Checkpoints fill in evidence after release.
   Final acceptance still reconstructs the exact revision from accepted wire
   operations and compressor state, and rejects missing send evidence.

2. **Storage validation without derived metadata.** `nativeStorageLoad` selects
   successful GET responses by the actual commit/tree/blob request path. It
   requires the raw bytes, recomputes their hash, parses the response, and checks
   repeated requests for conflicting hashes before selecting the load chain.
   `storageResponse` is an optional identity claim to compare with the decoded
   body. Removing it cannot skip validation. The same checks cover ordinary
   content blobs whose bodies contain no snapshot sequence.

   The first full interoperability run exposed the matching producer defect:
   `DeliveryGate` also saved response bytes only when it decoded snapshot
   metadata. I added failing HTTP-boundary tests, then made byte capture depend
   on the request path. Streamed, held, and injected responses now retain the
   bytes delivered to the reader. Capture uses the existing 8 MiB HTTP bound;
   larger responses fail the request instead of dropping its evidence.

### RED/GREEN evidence

Temporary fixtures used:

```text
TMPDIR=/home/tylerbu/.copilot/session-state/f0314904-8ed9-4e5b-8ddb-7339a023eb18/files/tmp
```

Storage RED, before changing `nativeStorageLoad`:

```text
node --test --test-name-pattern='review follow-up validates raw storage' tools/shared-tree-oracle/summary-interop.test.mjs
tests 6; pass 0; fail 6; skipped 0
```

The conflicting duplicate with its `storageResponse` deleted failed with
`Missing expected exception`. Missing bytes, a copied hash, and conflicting
non-attributes blob bodies also failed with `Missing expected exception`.
The valid control with all derived identities omitted failed with
`Native reader lacks the selected commit response identity`.

Storage GREEN, including adjacent request/body and replay tests:

```text
node --test --test-name-pattern='review follow-up validates raw storage|completion binds native|native .* (identity|replay|summary)' tools/shared-tree-oracle/summary-interop.test.mjs
tests 19; pass 19; fail 0; skipped 0
duration_ms 2058.140592
```

Transport RED, after exporting the existing helper for direct regression
coverage but before changing its behavior:

```text
node --test --test-name-pattern='review follow-up (upstream|captures upstream)' tools/shared-tree-oracle/interop.test.mjs tools/shared-tree-oracle/service.test.mjs
tests 4; pass 0; fail 4; skipped 0
```

The adversary first confirmed rejection of a same-connection duplicate, then
changed the second normalized record's client IDs, relabeled it as a retry, and
regenerated evidence without adding a raw connection. RED was
`Missing expected exception`. The create and load driver-boundary tests failed
with `Opening a driver connection was not captured before any submission`,
`0 !== 1`. These tests also check message-copy isolation and a genuine second
connection after reconnect.

Transport GREEN:

```text
node --test --test-name-pattern='review follow-up (upstream|captures upstream)|completion (rejects duplicate|preserves unmatched)|storage observation' tools/shared-tree-oracle/interop.test.mjs tools/shared-tree-oracle/service.test.mjs
tests 7; pass 7; fail 0; skipped 0
duration_ms 9138.791002
```

Combined focused coverage after switching normalization to driver submissions:

```text
node --test --test-name-pattern='review follow-up|completion (rejects duplicate|preserves unmatched)|storage observation' tools/shared-tree-oracle/interop.test.mjs tools/shared-tree-oracle/service.test.mjs tools/shared-tree-oracle/summary-interop.test.mjs
tests 13; pass 13; fail 0; skipped 0
duration_ms 10825.608979
```

The executable live probe used `withLocalFloodgate`, `openSession`, and
`upstreamAdapter` to run the actions described above. It asserted one raw send
per action, different observed transport IDs before/after reconnect, and
membership in the session's captured connection records. Its final exit status
was 0; both sessions reported three observed connections.

HTTP collector RED, after the first full gate exposed missing content-blob
bytes:

```text
node --test --test-name-pattern='review follow-up captures storage bytes' tools/shared-tree-oracle/delivery-gate.test.mjs
tests 6; pass 0; fail 6; skipped 0
```

Streamed, held, injected, and greater-than-1-MiB responses failed with
`Raw storage bytes were dropped because the body has no snapshot identity`.
The greater-than-8-MiB case failed with `Missing expected rejection`.

HTTP collector GREEN:

```text
node --test tools/shared-tree-oracle/delivery-gate.test.mjs
tests 20; pass 20; fail 0; skipped 0
duration_ms 871.115802
```

A bounded live rerun of `runTransactionReloadMatrix` through
`withLocalFloodgate` then passed all nine writer/reader cells (exit 0).

Final combined focused coverage, including the HTTP collector:

```text
node --test --test-name-pattern='review follow-up|completion (rejects duplicate|preserves unmatched)|storage observation' tools/shared-tree-oracle/interop.test.mjs tools/shared-tree-oracle/service.test.mjs tools/shared-tree-oracle/summary-interop.test.mjs tools/shared-tree-oracle/delivery-gate.test.mjs
tests 19; pass 19; fail 0; skipped 0
duration_ms 8849.581938
```

Held-action RED/GREEN:

```text
node --test --test-name-pattern='review follow-up retains held' tools/shared-tree-oracle/service.test.mjs
RED: tests 1; pass 0; fail 1; skipped 0
     Timed out: upstream retained edit outbound send
GREEN: tests 1; pass 1; fail 0; skipped 0
       duration_ms 18973.665176
```

This test runs real upstream retain and revert actions with the outbound queue
paused. It checks empty raw send arrays and zero measured sends before release,
then one observed send after release, synchronization, and checkpoint capture.
I removed the obsolete allocation-range helper from the adapter; report
acceptance keeps its exact compressor reconstruction.

Before the final full gate, a bounded live run of `runUndoRedoScenarios` and
`runUndoRedoReloadMatrix` passed all 3 kind rows, 30 concurrent rows, 2 reconnect
rows, and 18 reload cells. Final focused coverage added the held-action and
compressor regression:

```text
node --test --test-name-pattern='review follow-up|completion (rejects duplicate|preserves unmatched|reconstructs)|storage observation' tools/shared-tree-oracle/interop.test.mjs tools/shared-tree-oracle/service.test.mjs tools/shared-tree-oracle/summary-interop.test.mjs tools/shared-tree-oracle/delivery-gate.test.mjs
tests 21; pass 21; fail 0; skipped 0
duration_ms 26123.984197
```

### Changed files

- `tools/shared-tree-oracle/service.mjs`: driver-boundary observation for create
  and load, with cloned session evidence.
- `tools/shared-tree-oracle/interop-scenarios.mjs`: normalize actual sends, bind
  to captured connections, and refresh action evidence at checkpoints.
- `tools/shared-tree-oracle/summary-interop.mjs`: validate raw responses without
  relying on the presence of derived storage metadata.
- `tools/shared-tree-oracle/delivery-gate.mjs`: capture storage response bytes
  without derived metadata and fail requests that exceed the evidence bound.
- `tools/shared-tree-oracle/service.test.mjs`: create/load capture, independent
  connection epochs, cloned submissions, and real held-action coverage.
- `tools/shared-tree-oracle/interop.test.mjs`: the forged-client retry regression.
- `tools/shared-tree-oracle/summary-interop.test.mjs`: missing-metadata conflict,
  optional-claim control, missing bytes/hash, and non-attributes blob regressions.
- `tools/shared-tree-oracle/delivery-gate.test.mjs`: streamed, held, injected,
  large-response, and oversized-response capture regressions.
- This report: appended evidence; previous sections remain intact.

### Full tests and gates

```text
node --test tools/shared-tree-oracle/client-driver.test.mjs tools/shared-tree-oracle/client-interop.test.mjs tools/shared-tree-oracle/summary-interop.test.mjs tools/shared-tree-oracle/interop.test.mjs tools/shared-tree-oracle/service.test.mjs
tests 170; pass 170; fail 0; skipped 0
duration_ms 468711.562889

node --test tools/shared-tree-oracle/delivery-gate.test.mjs
tests 14; pass 14; fail 0; skipped 0
duration_ms 1457.146502
```

After the HTTP collector fix, I reran the exact five-file command: 170 tests,
170 passes, 0 failures, 0 skips, `duration_ms 426246.659645`. The final delivery
suite has 20 passes, as recorded above.

After the held-action fix, the final exact five-file run passed:

```text
node --test tools/shared-tree-oracle/client-driver.test.mjs tools/shared-tree-oracle/client-interop.test.mjs tools/shared-tree-oracle/summary-interop.test.mjs tools/shared-tree-oracle/interop.test.mjs tools/shared-tree-oracle/service.test.mjs
tests 171; pass 171; fail 0; skipped 0
duration_ms 366697.067498
```

Creation gate before the HTTP collector fix:

```text
TMPDIR=/home/tylerbu/.copilot/session-state/f0314904-8ed9-4e5b-8ddb-7339a023eb18/files/tmp just shared-tree-create-interop
exit status: 0
runId: b560966b-575c-4a58-8b61-87ce8bd04899
service: floodgate 0eb493fc46d1bb9baf1151a6ccdde93544e057e7
profileDigest: 588a2f41621f4f352497915168a5dc8af55140721066a04f217ab03e639a1813
cells: 18; skipped: 0; divergences: 0
```

Report:
`tools/shared-tree-oracle/.output/creation/b560966b-575c-4a58-8b61-87ce8bd04899/report.json`

The same creation command passed again after the collector fix, run
`1ac3439d-73d9-4306-bcf1-2c184aac4a2f`, with 18 cells, 0 skips, and 0
divergences, using the same service revision and profile digest. Report:
`tools/shared-tree-oracle/.output/creation/1ac3439d-73d9-4306-bcf1-2c184aac4a2f/report.json`

The final-source creation run also exited 0:
`6e775a3d-946d-4d68-8cc4-9fc8eac9123c`, 18 cells, 0 skips, 0 divergences, and
the same service revision/profile digest. Report:
`tools/shared-tree-oracle/.output/creation/6e775a3d-946d-4d68-8cc4-9fc8eac9123c/report.json`

The first `just shared-tree-interop` run,
`247f6e45-b071-433d-aad0-ed7813f59e34`, exited 1 during the transaction reload
matrix with `Storage observation lacks raw response bytes`. The failure
artifact remains at
`tools/shared-tree-oracle/.output/interop/247f6e45-b071-433d-aad0-ed7813f59e34/failure.json`.
This prompted the collector RED/GREEN cycle above.

The second full run, `9f0f66e7-5aea-4ee8-ad29-aa01d017efb6`, reached undo/redo
kinds and exited 1 with `Timed out: upstream retained edit outbound send`.
Its artifact is
`tools/shared-tree-oracle/.output/interop/9f0f66e7-5aea-4ee8-ad29-aa01d017efb6/undo-redo-failure/undo-redo-kinds_upstream.json`.
This prompted the held-action RED/GREEN cycle above.

The final full gate passed on the final implementation:

```text
TMPDIR=/home/tylerbu/.copilot/session-state/f0314904-8ed9-4e5b-8ddb-7339a023eb18/files/tmp just shared-tree-interop
exit status: 0
runId: 70e347d4-d553-4ca8-928e-41d570a72cf0
reference: @fluidframework/tree 3.1.0
reference commit: c3c5bf0ecd313362e83fe8a02b7d39e7e0736960
service: floodgate 0eb493fc46d1bb9baf1151a6ccdde93544e057e7
profileDigest: 588a2f41621f4f352497915168a5dc8af55140721066a04f217ab03e639a1813
undoRedoKinds.implementations: 3
undoRedoConcurrent: 30
undoRedoReconnect: 2
undoRedoReloadMatrix cells: 18
seeded schedules requested/generated/executed: 300/300/300, seed 42
seeded profiles: 60 each for object, map, schema, array, identifier
javascript corpus: 956
erlang corpus: 974
skipped: 0
divergences: 0
```

Report:
`tools/shared-tree-oracle/.output/interop/70e347d4-d553-4ca8-928e-41d570a72cf0/report.json`

### Auxiliary coverage and concerns

I also ran:

```text
node --test tools/shared-tree-oracle/interop-scenarios.test.mjs tools/shared-tree-oracle/delivery-gate.test.mjs
tests 88; pass 79; fail 9; skipped 0
```

All nine failures came from the additional scenario suite. I reran that suite
with a Node `registerHooks` load hook supplying
`git show 81c679ec:tools/shared-tree-oracle/interop-scenarios.mjs`, without
changing the worktree. The baseline produced 74 tests, 65 passes, and the same
nine failures. I compared the failure-name arrays with `assert.deepEqual`.
The failures cover two outdated decoder expectations, four incomplete upstream
adapter doubles, an incomplete native reconnect double, and two outdated
seeded-schedule expectations. I left these unrelated baseline failures intact.
The final-source rerun of `node --test
tools/shared-tree-oracle/interop-scenarios.test.mjs` also produced 74 tests,
65 passes, and the same nine failure names.

The local service continues to emit Socket.IO transport-control decode warnings
and shutdown diagnostics. The probe and creation gate exited 0 despite those
messages. No diagnostic suppression or service changes are part of this fix.

The final interoperability run also emitted upstream `0x92a` telemetry for
schedule 87, document `23A61126B73B8D19BE444AE84EBA750D`, from an unmeasured
interactive client and a summarizer. Neither identified client appeared in
the schedule's measured checkpoints. All three measured implementations
finished at sequence 21 without read errors, and the schedule passed. This
upstream diagnostic remains a concern; this change does not suppress it.

Logs for this pass use the `review-` prefix under
`/home/tylerbu/.copilot/session-state/f0314904-8ed9-4e5b-8ddb-7339a023eb18/files/`.

### Self-review

I traced the service factory's create/load paths, all upstream adapter callers,
native and upstream transport binding, and both callers of
`nativeStorageLoad`. Connection creation and send capture happen before report
normalization, with no data flow from normalized records back into the captured
session history. The validator still counts unmatched raw duplicate sends.
The storage scan checks relevant GET bodies even when the identity decoder
returns no snapshot metadata; conflict detection uses the request's object kind
and decoded ID. I reviewed the complete diff from `81c679ec` after the final
gate, including the producer changes and held-action behavior. Empty
pre-submission evidence cannot satisfy final acceptance. The exact accepted
compressor reconstruction, lifecycle joins, and primary failure-checkpoint
preservation remain in place. No generated, `.code-map`, apm-managed, or public
Gleam API files changed.
