# Task 6 report: kernel schema reconciliation

## Result

SharedTree now applies ordered schema and data effects through one atomic kernel
path for local commits, acknowledgements, remote commits, rebases, and rollback.
The visible and sequenced schemas are derived from their corresponding forests,
so pending schema changes remain visible without leaking into snapshots.

The runtime bridge now retains complete ordered outer changes, including schema
changes and empty commits. Forward live fixed-schema changes validate their
recorded before/after pair. Inverse schema effects bypass that monotonicity
check. Live transitions to an empty schema remain unsupported.

## Events and atomicity

The kernel exposes `SchemaChanged(local)` alongside `TreeChanged(local)`.
Completed schema changes are emitted before completed tree changes. Failed
ordered effect sequences return an error without publishing candidate state,
history, allocation, or events.

## History corpus

The native history driver replays all 19 schema-evolution scenarios through the
real kernel and history implementation. It covers causal edits, both conflict
orders, common-prefix acknowledgement, rollback, reconnect replay, pending
summary separation, view compatibility, initialization history, identity
encoding, and event order.

The Task 6 assertion projects out `acceptedMessage`, `replay`, `continuation`,
and `historicalDecode`. Those fields require contextual wire or summary
encoding and remain owned by Task 7. All schema, forest, pending, outer, trunk,
peer, rollback, compatibility, identity, and event observations are compared.

## Additional directly coupled files

The public event variant required exhaustive handlers in
`test/watershed/tree/client_beam.gleam` and
`test/watershed/tree/client_js.gleam`. The removed runtime schema refusal also
required updating the obsolete bridge assertion in
`test/watershed/shared_tree_channel_test.gleam`. These changes are part of Task
6 because the repository does not compile or pass the SharedTree suite without
them.

## Verification

- `gleam test --target erlang -- shared_tree_history shared_tree_kernel`:
  61 passed.
- `gleam test --target javascript -- shared_tree_history shared_tree_kernel`:
  61 passed.
- `just shared-tree-test`: Erlang 552 passed, JavaScript 541 passed, storage and
  bootstrap smoke tests passed.
- `git diff --check`: passed.

## Fix round 1

### Result

Later-sequenced duplicate commits now retain their sequencing record without
reapplying the commit to the sequenced forest. They rebase pending commits
against the updated trunk instead. Revision lookups use the latest retained
occurrence, and snapshot validation accepts repeated identical commits while
still rejecting conflicting content or originators. A replay of `A -> B` can
therefore arrive while `B -> C` is pending without regressing the visible
schema or emitting a remote schema event, and the resulting snapshot restores.

The history fixture no longer changes observed schemas, roots, commit arrays,
revision numbers, compatibility details, retained content, or events by
scenario ID. It now models reconnect catch-up order, view-listener lifetimes,
multi-effect event boundaries, observation roles, retained repair content, and
revision encoding from executed state and action metadata. The Task 7-owned
projection exclusions remain unchanged.

### RED

- `gleam test --target erlang -- shared_tree_history shared_tree_kernel`
  failed three new regressions:
  - replaying an acknowledged schema commit over a pending schema change
    emitted `SchemaChanged(False)` and regressed the visible schema;
  - a later replay produced two trunk entries that `history.restore` rejected;
  - renaming scenario IDs changed derived observations.

### GREEN

- `gleam test --target erlang -- shared_tree_history shared_tree_kernel`:
  64 passed.
- `gleam test --target javascript -- shared_tree_history shared_tree_kernel`:
  64 passed.
- `just shared-tree-test`: Erlang 555 passed, JavaScript 544 passed, storage
  smoke passed, and bootstrap/creation smoke passed for both targets.

### Files

- `src/watershed/tree/history.gleam`
- `src/watershed/tree_kernel.gleam`
- `test/watershed/shared_tree_history_test.gleam`
- `test/watershed/shared_tree_kernel_test.gleam`
- `test/watershed/tree/schema_evolution_fixture.gleam`

### Self-review

- Replay reconciliation remains atomic: candidate history, forests, events,
  allocation, and rollback state are returned only after every effect succeeds.
- Repeated retained revisions must contain the same commit. Conflicting content
  and conflicting originators still fail snapshot restoration.
- The fixture uses scenario IDs only as output labels and error context. Two
  rename mutations prove that changing IDs does not change derived output.

### Concerns

Retained replay entries intentionally keep more than one sequence point for the
same revision because the pinned upstream history corpus observes both. All
revision-based ancestry lookups therefore resolve the latest occurrence.
