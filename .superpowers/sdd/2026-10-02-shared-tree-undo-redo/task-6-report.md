# Task 6 report: BEAM revertible handles and commit subscriptions

## Status

Implemented and verified on `main`.

Commit: `21bc2604 feat(tree): expose BEAM undo and redo`

## Implementation

- Added runtime-owned BEAM `TreeRevertible`, `TreeCommitEvent`,
  `TreeRevertibleStatus`, and callback `SubscriptionToken` types.
- Added facade-owned `watershed_beam.TreeCommitEvent` construction by
  translating runtime events. The facade aliases the opaque runtime handle and
  token.
- Added callback commit subscription and unsubscribe without changing the
  existing subject-based `subscribe_tree`.
- Added one monitored delivery process per commit event. It invokes handlers in
  the existing subscription order.
- Restricted the actor during delivery to the active event's acquisition and
  settlement requests plus matching completion or monitor-down messages.
  Unrelated messages are replayed in arrival order after event invalidation.
- Shared one one-shot acquisition state across all handlers. Remote events
  expose neither callback.
- Added revision-keyed settlement callbacks. The actor removes them before one
  ordered callback process invokes them.
- Added status, disposal, and revert actor requests. Revert authors one
  operation, sends one submission, rejects active transactions through
  `runtime_core`, and optionally disposes only after successful authoring.
- Preserved handles across reconnect. Actor shutdown makes handles report
  disposed and drops actor-owned settlements.
- Added a transaction-finish continuation so deferred sequenced operations
  cannot overtake active commit delivery.

## Files

- `src/watershed/runtime_beam.gleam`
- `src/watershed_beam.gleam`
- `test/watershed/shared_tree_runtime_beam_test.gleam`
- `test/watershed/shared_tree_array_facade_test.gleam`
- `test/watershed/shared_tree_map_facade_test.gleam`
- `test/watershed/shared_tree_creation_api_test.gleam`

## TDD evidence

### RED

Command:

```text
gleam test --target erlang -- shared_tree_runtime_beam shared_tree_array_facade shared_tree_map_facade
```

Exit code: `1`

Exact relevant output:

```text
error: Unknown module value
666 │     watershed_beam.subscribe_tree_commits(tree, fn(event) {
    │                    ^^^^^^^^^^^^^^^^^^^^^^ Did you mean `subscribe_tree`?

The module `watershed_beam` does not have a `subscribe_tree_commits` value.

error: Unknown module value
667 │       let assert watershed_beam.TreeCommitEvent(
    │                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

The module `watershed_beam` does not have a `TreeCommitEvent` value.

error: Unknown module value
681 │     watershed_beam.tree_revert(first, False) |> expect.to_be_error()
    │                    ^^^^^^^^^^^ Did you mean `tree_get`?

The module `watershed_beam` does not have a `tree_revert` value.

error: Unknown module value
1891 │     runtime_beam.subscribe_tree_commits(actor, "A/_C", fn(event) {
     │                  ^^^^^^^^^^^^^^^^^^^^^^

The module `watershed/runtime_beam` does not have a
`subscribe_tree_commits` value.
```

### First GREEN

Command:

```text
gleam test --target erlang -- shared_tree_runtime_beam shared_tree_array_facade shared_tree_map_facade
```

Exit code: `0`

Exact result:

```text
Running 48 tests
Test Files: 3
     Tests: 48 passed (48)
Started at: 00:03:07
  Duration: 2s (discover 21ms, collect 1ms, tests 2s, reporters 695µs)
```

### Required final GREEN

Command:

```text
gleam test --target erlang -- shared_tree_runtime_beam shared_tree_array_facade shared_tree_map_facade shared_tree_creation_api shared_tree_transaction
```

Exit code: `0`

Exact result:

```text
Running 92 tests
Test Files: 5
     Tests: 92 passed (92)
Started at: 00:30:16
  Duration: 3s (discover 31ms, collect 933µs, tests 3s, reporters 1ms)
```

### JavaScript parity

Command:

```text
gleam test --target javascript -- shared_tree_array_facade shared_tree_map_facade shared_tree_creation_api shared_tree_transaction
```

Exit code: `0`

Exact result:

```text
Running 63 tests
Test Files: 4
     Tests: 63 passed (63)
Started at: 00:30:31
  Duration: 2s (discover 181ms, collect 1ms, tests 1s, reporters 1ms)
```

### Build and formatting

Commands:

```text
gleam format --check src/watershed/runtime_beam.gleam src/watershed_beam.gleam test/watershed/shared_tree_runtime_beam_test.gleam test/watershed/shared_tree_array_facade_test.gleam test/watershed/shared_tree_map_facade_test.gleam test/watershed/shared_tree_creation_api_test.gleam
gleam build --target erlang
git --no-pager diff --check
```

Exit code: `0` for each command.

`gleam build --target erlang` exact result:

```text
Compiled in 3.62s
```

## Self-review

- Verified the facade constructs its own public event and does not expose the
  runtime event constructor.
- Verified callback tokens are separate from subject subscriptions and
  unsubscribe is effective before the next event.
- Verified one worker shares one factory across handlers; the first
  acquisition succeeds and duplicate or late calls fail.
- Verified a delivery-process exit invalidates closures and unblocks deferred
  actor requests.
- Verified remote events have `None` for both local-only functions.
- Verified settlement callbacks run once after delivery and duplicate
  sequencing does not call them again.
- Verified transaction reversion fails, one transaction commit produces one
  handle and one submission, and reconnect retains handles.
- Verified successful revert applies the inverse, sends one operation, and
  optional disposal makes a later disposal fail.
- Verified actor shutdown makes retained handles report disposed.
- Verified ordinary tree subscriptions still use subjects and do not receive
  internal commit metadata.

## Concerns

- `just lint` is blocked by three pre-existing unformatted files:
  `test/watershed/tree/client_beam.gleam`,
  `test/watershed/tree/client_js.gleam`, and
  `test/watershed/tree/client_protocol.gleam`. All six changed files pass
  `gleam format --check`.
- `just build` reaches the example bundles, then fails because
  `examples/shared_tree_checklist_lustre/pnpm-lock.yaml` contains 28 tarball
  URLs rejected by the active pnpm supply-chain policy. The Erlang package
  build passes.
- The verified commands retain existing warnings for two unused private codec
  test helpers and JavaScript unsafe-integer fixtures. This task adds no new
  warning category.

## Fix round 1

### Findings

- Settlement callbacks were removed once from actor state, but they ran in one
  unprotected worker. If an earlier callback exited, later callbacks did not
  run.
- The delivery-process exit test proved one deferred read only. It did not
  prove FIFO replay for multiple distinguishable messages queued while
  delivery was active.
- The shutdown path disposed retained handles, but no test registered a
  settlement callback and then stopped the actor before acknowledgement.

### Files

- `src/watershed/runtime_beam.gleam`
- `test/watershed/shared_tree_runtime_beam_test.gleam`
- `test/watershed/shared_tree_map_facade_test.gleam`
- `.superpowers/sdd/2026-10-02-shared-tree-undo-redo/task-6-report.md`

### RED

Added the three focused tests before the actor change:

- `shared_tree_map_facade_beam_settlement_callback_failure_isolated_test`
- strengthened
  `commit_delivery_exit_invalidates_factory_and_replays_messages_test`
- `shared_tree_map_facade_beam_shutdown_drops_pending_settlement_test`

Command:

```text
gleam test --target erlang -- shared_tree_runtime_beam shared_tree_array_facade shared_tree_map_facade shared_tree_creation_api shared_tree_transaction
```

Exit code: `1`

Exact result:

```text
Running 94 tests
Failed Tests: 1

FAIL  shared_tree_map_facade_beam_settlement_callback_failure_isolated_test
Expected Error(Nil) to equal Ok(FullyApplied)

- Expected
+ Received

- Ok(FullyApplied)
+ Error(Nil)
Test Files: 5
     Tests: 93 passed | 1 failed (94)
```

The deferred FIFO and shutdown tests passed against the existing actor. The
RED failure isolated the missing callback-failure boundary.

### Implementation

Each settlement callback now runs in its own unlinked monitored process. The
settlement worker waits for that process to exit before it starts the next
callback. This preserves registration order, contains callback exits, and
keeps the existing once-only removal before delivery.

The delivery-exit regression now blocks the delivery worker, queues
`unsubscribe`, `read`, `edit`, and `read` from one sender, terminates the
worker, and proves the reads observe `native` then `queued`. The shutdown
regression registers `on_settled`, stops the actor before acknowledgement,
waits for actor exit, and proves the callback stays silent.

### GREEN

Command:

```text
gleam test --target erlang -- shared_tree_runtime_beam shared_tree_array_facade shared_tree_map_facade shared_tree_creation_api shared_tree_transaction
```

Exit code: `0`

Exact result:

```text
Running 94 tests
Test Files: 5
     Tests: 94 passed (94)
```

JavaScript parity:

```text
gleam test --target javascript -- shared_tree_array_facade shared_tree_map_facade shared_tree_creation_api shared_tree_transaction
```

Exit code: `0`

Exact result:

```text
Running 63 tests
Test Files: 4
     Tests: 63 passed (63)
```

Additional verification:

```text
gleam build --target erlang
gleam format --check src/watershed/runtime_beam.gleam test/watershed/shared_tree_runtime_beam_test.gleam test/watershed/shared_tree_map_facade_test.gleam
git --no-pager diff --check
```

Exit code: `0` for each command.

`gleam build --target erlang` exact result:

```text
Compiled in 0.34s
```

### Self-review

- Verified a terminating callback cannot prevent a later callback from
  receiving the same settlement outcome.
- Verified callback processes run serially, so registration order is
  preserved rather than only spawn order.
- Verified settlement callbacks are still deleted from actor state before
  asynchronous delivery, so duplicate acknowledgements cannot redeliver them.
- Verified the monitored commit-delivery protocol and active event
  invalidation are unchanged.
- Verified deferred messages are sent by one process and replayed as
  `unsubscribe`, first read, edit, second read.
- Verified shutdown occurs after settlement registration and before the
  unacknowledged submission can settle.

### Concerns

- The verified commands retain the pre-existing unused private test-helper
  warnings and JavaScript unsafe-integer warnings documented above. This fix
  adds no warning category.
