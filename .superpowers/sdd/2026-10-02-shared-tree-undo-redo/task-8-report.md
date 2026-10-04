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
