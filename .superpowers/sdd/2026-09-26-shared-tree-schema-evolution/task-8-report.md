# Task 8 report: atomic schema submission and reconnect

## Result

SharedTree now validates a requested schema upgrade before it allocates a
revision. Equivalent views return the original core with no events or outbound
operations. Valid upgrades use the document compressor, append one schema
commit, and share the existing grouped batch construction with data edits.
Local ID ranges remain unfinalized until the normal acknowledgement path.

Reconnect rebuilding now replays pending outer commits in order from the
sequenced forest. It advances the scratch schema at each inner schema boundary,
refreshes the first data run strictly, treats later detached roots as optional,
and compares both the replayed root and schema with the optimistic state.
Resubmission encodes each pending commit with its own reconstructed authoring
context. Schema-only commits and empty losing commits remain present.

## Tests

New runtime regressions cover:

- equivalent upgrades without allocation or submission;
- invalid upgrades without changes to the compressor, CSN, in-flight state, or
  pending history;
- atomic schema batches and schema events;
- unacknowledged reconnect replay;
- acknowledgement before disconnect;
- duplicate acknowledgement;
- dependent data authored after an upgrade;
- losing upgrades resubmitted as empty commits.

History resubmission tests also require schema-only and empty conflict commits
to survive.

The initial no-op test failed because `submit_tree_upgrade` did not exist. The
implemented API then passed the focused suite. The existing schema-evolution
history corpus continued to cover dependent data, losing upgrades, duplicate
delivery, and summary-plus-tail restoration.

## Verification

- Required focused Erlang target: 113 passed.
- Required focused JavaScript target: 102 passed.
- Full `just shared-tree-test` gate: 589 Erlang tests and 578 JavaScript tests
  passed; storage, bootstrap, and creation smoke tests passed.
- Direct `gleam format --check` for all changed Gleam files passed.
- `git diff --check` passed.

## Concerns

`just lint` stalled in Trellis after starting its two `gleam format --check`
jobs and was stopped after ten minutes. The direct format check for every
changed Gleam file completed successfully.

## Fix round 1

Reconnect resubmission now encodes each current pending commit from the schema
at its sequenced-state replay start. The replay advances that context through
preceding current commits and through schema changes inside each outer commit.
This lets a client lose one pending upgrade, author another upgrade on the
winning schema, reconnect, and resubmit both commits successfully.

Pending replay and history refresher reconstruction now also retain roots
detached by earlier data runs in the same outer commit as internally available.
A later data run can restore such a root across an intervening schema change
without emitting a redundant refresher.

### RED

- The competing-upgrade reconnect regression failed when resubmission could
  not encode the later upgrade from the rebased winning schema.
- The data/schema/data regression rebuilt the restoring data run with a
  refresher for the title root detached by the first run.

### GREEN

- Focused Erlang runtime/history resubmit: 115 passed.
- Focused JavaScript runtime/history resubmit: 104 passed.
- Full `just shared-tree-test`: 591 Erlang tests and 580 JavaScript tests
  passed; storage, bootstrap, and creation smoke tests passed.
- Changed Gleam files pass `gleam format --check`; `git diff --check` passes.
