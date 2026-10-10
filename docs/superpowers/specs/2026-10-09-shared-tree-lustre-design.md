# SharedTree Lustre transactions and application-owned undo

## Scope and approval

The user selected the Lustre consumer slice of M7 and approved this design on
2026-10-09, including specification/plan files, implementation, and incremental
commits directly to `main`. This does not close the whole M7 milestone.

Extend the existing `watershed_lustre/tree` effects and browser checklist.
Reuse native transactions, commit subscriptions, revertible handles, and
settlement; do not build a second undo engine or change tree semantics.

## Constraints

- Preserve pure Gleam SharedTree semantics on JavaScript and BEAM.
- Keep Fluid 3.1.0, source `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960`,
  Floodgate `0eb493fc46d1bb9baf1151a6ccdde93544e057e7`, and
  `minVersionForCollab` `2.117.0`.
- Keep Message V7, SharedTreeChange V5, ModularChange V5, and Schema V2.
- Keep the existing fixed bootstrap-map/tree container layout.
- Preserve existing adapter APIs, DDS behavior, and M1-M6 contracts.
- No production Fluid SDK dependency, new package dependency, or lockfile change.
- All adapter work starts at effect execution. Every message constructor and
  dispatch runs in a microtask, not inside a native callback or Lustre update.
- Acquire a native one-shot revertible factory before its callback returns.
- Preserve typed transaction results and explicit acquisition, registration,
  reversion, and disposal errors.
- Applications own stacks and retained handles; no package-owned undo stack.
- Apply ASD-STE100 to Gleam comments/error strings, not Markdown prose.
- Do not edit generated fixtures, `.code-map/`, or apm-managed files.

## Adapter contract

Add the following to `watershed_lustre/tree`:

```gleam
pub type CommitEvent {
  CommitEvent(
    kind: tree_types.TreeCommitKind,
    local: Bool,
    revertible: Option(watershed.TreeRevertible),
  )
}

pub fn transaction(
  tree: watershed.SharedTree,
  constraints: List(watershed.TreeTransactionConstraint),
  callback: fn(watershed.SharedTree) -> Result(value, callback_error),
  completed: fn(
    Result(value, watershed.TreeTransactionError(callback_error)),
  ) -> msg,
) -> Effect(msg)

pub fn subscribe_commits(
  tree: watershed.SharedTree,
  subscribed: fn(watershed.SubscriptionToken) -> msg,
  committed: fn(Result(CommitEvent, String)) -> msg,
  settled: fn(Result(tree_types.TreeCommitOutcome, String)) -> msg,
) -> Effect(msg)

pub fn revert(
  revertible: watershed.TreeRevertible,
  dispose: Bool,
  completed: fn(Result(Nil, String)) -> msg,
) -> Effect(msg)

pub fn dispose_revertible(
  revertible: watershed.TreeRevertible,
  completed: fn(Result(Nil, String)) -> msg,
) -> Effect(msg)
```

`subscribe_commits` acquires eligible local factories synchronously. It queues
the captured event before registering settlement so an immediate settlement
cannot arrive before the captured commit. Factory failure becomes
`committed(Error(...))`; registration failure becomes `settled(Error(...))`.
The acquired handle remains delivered to the application if registration
fails. Remote and schema commits carry no revertible. No callback-only factory
escapes into a queued application message.

Use the existing `unsubscribe` effect for either subscription token. Removing a
subscription prevents future native callbacks; messages already queued may
still arrive. Document close disposes runtime-owned handles. Applications must
dispose unused handles, including handles delivered after they stop accepting
history. Reads and pure status queries remain on the native facade.

## Checklist integration

The existing UI keeps its visual identity and native controls. Add Undo, Redo,
Complete all, Clear history, and Close controls with truthful disabled states.
Keep the existing add/edit/toggle/delete/reorder operations.

The application model owns undo and redo lists. Captured local default commits
push undo and dispose/clear redo; undo commits push redo; redo commits push undo.
Remote commits never become local undo entries. A new default commit after undo
invalidates redo. Reversion consumes a handle only on success; an error retains
the stack entry and is displayed.

Complete all reads the latest tree during effect execution and changes only
incomplete items in one synchronous transaction. One outer commit gives one
undo step. If every item is already complete, it authors no commit.
Do not prepare bulk edits from a stale rendered snapshot.

Serialize local history actions while their effects are outstanding. Display
settlement failures and non-fully-applied outcomes, rather than treating an
optimistic callback result as sequenced acceptance. Prune disposed handles from
available history. Clearing history releases both lists without editing data.
Close removes both subscriptions, releases retained handles, closes the
document, clears history, and disables editing. A reload opens committed state
with empty local history; it does not restore the previous stacks.

## Proof and exclusions

Adapter tests use the existing in-memory native runtime/transport seams. Prove
effect laziness, deferred message constructors and dispatch, callback-window
acquisition, default/undo/redo kinds, transaction grouping and abort rollback,
explicit errors, settlement delivery, unsubscribe, close, and existing
open/read/change-subscription scheduling. Use real native operations, not
fabricated commit events.

Extend the existing two-context Chromium gate. Prove bulk transaction undo and
redo, preservation of an intervening peer edit, redo invalidation after a new
local edit, history clearing, close, reload with empty history, and move-up as
well as the existing operation/race checks. No skipped browser run counts as
acceptance.

Broader layouts, live attach/aliases, handle-valued leaves, production
authentication, disk recovery, generated typed schemas, branch effects, and
persisted stacks remain separate M7 work. The adapter does not add async
transactions, offline authoring, or managed undo guarantees. Existing native
interop remains the semantic proof; this slice adds consumer scheduling and
real-browser evidence, not a new wire profile.
