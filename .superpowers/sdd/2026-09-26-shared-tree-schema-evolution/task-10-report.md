# Task 10 report: mixed-client and cross-writer interoperability

## Status

Complete.

## Implementation

- Added explicit schema compatibility, upgrade, and view-opening commands to the
  shared protocol and both native command clients.
- Routed JavaScript and BEAM commands through their public facades. The upstream
  adapter uses ordinary Fluid views and the public compatibility and upgrade
  APIs.
- Added deterministic schema/data and schema/schema races for every directed
  mixed-client pair, both release orders, and causal upgrade-then-edit controls.
- Recorded concurrent reference sequence numbers, optimistic state, losing
  empty outer changes, rollback, final stored schema, and stale-view rejection.
- Added unacknowledged and accepted-before-drop reconnect cases for upstream,
  JavaScript, and BEAM clients.
- Added all nine upgraded-summary writer-reader cells. Each fresh reader loads
  real stored summary trees and blobs, checks compatibility, opens the optional
  view, writes the new field, and has another client observe the write.
- Added retained pre-upgrade peer state, operation-tail replay, and pending
  summary evidence. The pending-summary proof records that the upgrade remained
  local and that its accepted sequence followed the summary reference sequence.
- Added schema actions and transitions to deterministic seed-42 schedules and
  persisted them in replay artifacts.
- Added strict report validation for every required schema section, target,
  race, reconnect case, reload cell, observation, and artifact.

## Coverage

- Compatibility: upstream, JavaScript, and BEAM.
- Races: 27 cells across six directed mixed-client pairs.
  - 12 schema/data cells.
  - 12 schema/schema cells.
  - 3 causal upgrade-then-edit controls.
- Reconnect: both required cases for all three implementations.
- Reload: all nine writer-reader combinations.
- Seeded schedules: 200 generated and executed with seed 42.
  - 67 object schedules.
  - 67 map schedules.
  - 66 schema schedules.
- No skipped targets, service checks, corpus runs, cells, or divergences.

## Verification

- Required Node gate: 108 passed.
- `just shared-tree-interop`: passed.
- JavaScript SharedTree corpus: 571 passed.
- Erlang SharedTree corpus: 582 passed.
- Floodgate revision:
  `0eb493fc46d1bb9baf1151a6ccdde93544e057e7`.
- Fluid reference: `@fluidframework/tree` 3.1.0 at
  `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960`.
- Successful run:
  `48518109-9b7c-4532-9fd7-fc56a6c34e3b`.
- Persisted report:
  `tools/shared-tree-oracle/.output/interop/48518109-9b7c-4532-9fd7-fc56a6c34e3b/report.json`.

## Concerns

Current upstream Fluid garbage collection no longer exposes the detached causal
edit root after acknowledgement. The committed history fixture was regenerated
from the pinned upstream package, and the Gleam history projection normalizes
that acknowledged storage detail while retaining native internal evidence.

Floodgate logs expected warnings when Socket.IO transport-control packets pass
through its wire-protocol decoder. They did not skip or weaken the real-service
gate.

## Fix round 1

- Preserved native detached identities and removed values in raw observations.
  Cross-engine garbage-collection comparison now uses a separate measured
  projection and does not depend on a scenario ID.
- Captured the race loser before acknowledgement removes its reconciled pending
  commit. The evidence includes the empty outer changeset, its raw form,
  rollback schema and data, client identities, and separate schema and data
  notifications for both race families and release orders.
- Captured pending-summary state from the writer that holds the upgrade. The
  writer checkpoint includes stored schema, forest state, revisions, and
  originators; accepted upgrades come from decoded service history.
- Bound every reload cell to the selected version, root tree, schema blob, and
  forest blobs. Fresh-reader evidence is captured before continuation, includes
  explicit upgrade-tail replay, and retains the earlier peer commit and
  historical stored schema.
- Queued reconnect data behind each upgrade, retained original and resubmitted
  revision evidence, and proved ordered, exactly-once acceptance on all clients
  for both required disconnect cases.
- Bound schema artifacts to their run, profile, section, subject, document, and
  persisted result. Negative tests cover absent, mismatched, contradictory, and
  structurally empty evidence.

Verification:

- Required Node gate: 113 passed.
- `just shared-tree-interop`: passed.
- JavaScript SharedTree corpus: 573 passed.
- Erlang SharedTree corpus: 584 passed.
- Schema races: 27.
- Schema reconnect rows: 3, covering both cases for each implementation.
- Schema reload matrix: all nine writer-reader cells.
- Seeded schedules: 200 generated and executed with seed 42.
- Successful run:
  `d9fe95e2-d255-4d8b-ac8c-9301016ffe8a`.
- Persisted report:
  `tools/shared-tree-oracle/.output/interop/d9fe95e2-d255-4d8b-ac8c-9301016ffe8a/report.json`.

The pinned Fluid wire format can encode a revision differently from the native
runtime's stable revision. The evidence retains both representations and binds
acceptance by decoded operation content and originator identity instead of
inventing a shared revision value. Floodgate still logs its expected
Socket.IO transport-control decoder warnings.
