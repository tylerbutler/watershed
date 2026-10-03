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
