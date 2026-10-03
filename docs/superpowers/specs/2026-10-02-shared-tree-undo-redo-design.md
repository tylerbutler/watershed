# SharedTree undo and redo

**Date:** 2026-10-02
**Status:** Scope and architecture approved in conversation. The written design
and implementation plan require review before execution.
**Parent:** [Native SharedTree interoperability](2026-09-21-shared-tree-design.md)
and [SharedTree transaction foundations](2026-09-29-shared-tree-transactions-design.md).

## 1. Scope and decisions

Complete the M5 undo and redo profile with application-owned revertible
handles. An application can retain an eligible local commit, revert it after
later local or remote commits, retain the resulting undo commit, and revert
that commit to redo the original change.

This phase includes:

- Public commit metadata for default, undo, and redo commits.
- A one-shot revertible factory during eligible local commit events.
- Runtime-local revertible handles on JavaScript and BEAM.
- Explicit handle status, reversion, and disposal operations.
- Object, dynamic-map, array, move, and transaction commits.
- Inversion and rebase over later local and remote commits.
- Revert-time node constraints and sequenced commit outcomes.
- History and repair-data retention while a handle remains valid.
- Reconnect with live handles in the same process.
- Native JavaScript, native BEAM, upstream/native, and real-service proof.

Keep these features out of this phase:

- Persisted application undo or redo stacks.
- Recreating revertible handles after summary reload.
- Reverting schema commits.
- Reverting remote commits through a local event.
- Undo or redo during an active transaction.
- Cross-tree atomic undo.
- Shared branches and public local-branch APIs.
- The alpha `noChange` constraint.
- Custom metadata, labels, clone-to-view, and `revertTo` APIs.
- A Watershed-managed undo or redo stack.

Applications own their stacks and eviction policy. Watershed owns inversion,
rebasing, history retention, and disposal. This follows the stable
`@fluidframework/tree` 3.1.0 model without adding a Watershed-only summary or
wire format.

### Global constraints

- Production SharedTree semantics must run in pure Gleam on JavaScript and
  BEAM.
- Upstream TypeScript packages remain development and test dependencies.
- Use `@fluidframework/tree` version `3.1.0`.
- Use Fluid Framework commit
  `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960`
  (`client_v3.1.0`).
- Use Floodgate commit `0eb493fc46d1bb9baf1151a6ccdde93544e057e7`.
- Keep `minVersionForCollab` at `2.117.0`.
- Keep Message V7, SharedTreeChange V5, ModularChange V5, and Schema V2.
- Preserve the existing fixed container layout.
- Preserve M1-M4, Identifier, and transaction behavior and interoperability
  evidence.
- Reject unsupported operations instead of approximating their meaning.
- Apply ASD-STE100 to Gleam comments and error strings, not to Markdown prose.
- Do not edit generated files, `.code-map/`, or apm-managed files.

## 2. Upstream contract

The pinned Fluid implementation defines the behavioral contract. The
implementation plan must verify the installed package against the pinned source
checkout before it records corpus evidence.

Paths below are relative to
`tools/shared-tree-oracle/.reference/FluidFramework/packages/dds/tree/src/`.

| Source | Required behavior |
| --- | --- |
| `core/revertible.ts` | Define valid and disposed handles, one-shot factories, optional disposal after revert, and application-owned stacks. |
| `core/rebase/types.ts` | Distinguish default, undo, and redo commit kinds. |
| `shared-tree/treeCheckout.ts` | Create one revertible during an eligible event, retain the target commit, invert and rebase it, alternate undo and redo kinds, and dispose retained state. |
| `shared-tree-core/branch.ts` | Preserve commit kind on local branch appends. |
| `shared-tree-core/editManager.ts` | Retain commits that active revertibles still need when the collaboration window advances. |
| `feature-libraries/modular-schema/modularChangeFamily.ts` | Invert and rebase object, map, and sequence changes with repair data and constraints. |
| `feature-libraries/modular-schema/invert.ts` | Exchange apply-time and revert-time node constraints during inversion. |
| `feature-libraries/sequence-field/invert.ts` | Restore removed content and preserve move identity during inversion. |
| `shared-tree/sharedTree.ts` | Keep commits outside the collaboration window when a revertible or branch retains them. |
| `test/shared-tree/treeCheckout.spec.ts` | Define factory lifetime, disposal, undo, redo, transaction squashing, remote edits, and conflict behavior. |

### Eligible commits

Only a local data commit can provide a revertible factory. Eligible commits
include:

- A normal object, map, array, or move edit.
- One outer transaction commit, regardless of how many edits it contains.
- An undo commit produced by reverting a default or redo commit.
- A redo commit produced by reverting an undo commit.

The following events do not provide a factory:

- Remote commits.
- Schema commits.
- No-op transactions.
- Explicitly suppressed changes with no local commit.
- Load and bootstrap notifications.

The factory is valid only while Watershed delivers its commit event. One
listener can call it once. A second call or a call after event delivery returns
an explicit error.

### Undo and redo kinds

Reverting a `DefaultCommit` or `RedoCommit` authors an `UndoCommit`. Reverting
an `UndoCommit` authors a `RedoCommit`.

Commit kind is local event metadata. It does not change SharedTreeChange V5,
ModularChange V5, or the Fluid channel operation. A remote client receives the
standard data change and reports it as a remote default commit because the
pinned wire format does not transmit the author's local undo or redo label.

### Concurrent changes

The revert operation inverts the retained commit and rebases the inverse over
all later commits on the current branch. Later changes outside the reverted
region remain visible. Object replacement, map set/delete, array insert/remove,
and move conflicts follow the pinned change-family behavior.

Revert-time node constraints can suppress the inverse after a concurrent
change removes a required node. Watershed reports that suppression to the
caller. It does not approximate the revert with path-based edits.

## 3. Public API

Add the same public types to the JavaScript and BEAM facades.

```gleam
pub type TreeCommitKind {
  DefaultCommit
  UndoCommit
  RedoCommit
}

pub type TreeRevertibleStatus {
  RevertibleValid
  RevertibleDisposed
}

pub type TreeCommitOutcome {
  FullyApplied
  FullyDropped
  NewContentOnly
}

pub opaque type TreeRevertible

pub type TreeRevertibleFactory =
  fn() -> Result(TreeRevertible, String)

pub type TreeCommitSettlement =
  fn(fn(TreeCommitOutcome) -> Nil) -> Result(Nil, String)

pub type TreeCommitEvent {
  TreeCommitEvent(
    kind: TreeCommitKind,
    local: Bool,
    get_revertible: Option(TreeRevertibleFactory),
    on_settled: Option(TreeCommitSettlement),
  )
}
```

Keep the current `subscribe_tree` API unchanged. Add a separate subscription
for commit metadata:

```gleam
pub fn subscribe_tree_commits(
  tree: SharedTree,
  handler: fn(TreeCommitEvent) -> Nil,
) -> SubscriptionToken
```

The BEAM facade exposes the same callback signature and subscription token.
Its actor runs commit handlers in a monitored delivery process so the actor can
service factory and settlement-registration requests while delivery remains
active.

Add handle operations:

```gleam
pub fn tree_revertible_status(
  revertible: TreeRevertible,
) -> TreeRevertibleStatus

pub fn tree_revert(
  revertible: TreeRevertible,
  dispose: Bool,
) -> Result(Nil, String)

pub fn tree_dispose_revertible(
  revertible: TreeRevertible,
) -> Result(Nil, String)
```

`tree_revert` is synchronous with local authoring. Success means Watershed
appended and submitted one local commit. It does not mean the sequencing
service accepted every field effect.

`on_settled` registers a callback for the local commit's final sequenced
outcome:

- `FullyApplied` means every change applied.
- `FullyDropped` means an implicit conflict dropped every change.
- `NewContentOnly` means an explicit constraint violation suppressed field
  effects while required created content remained.

Remote commit events have no settlement registration function because the
local runtime did not author those commits.

When `dispose` is `True`, Watershed disposes the handle after it authors the
revert commit. When it is `False`, the handle remains valid. The pinned source
permits repeated reversion of the same valid handle; each call authors another
inverse of the retained target commit.

`tree_dispose_revertible` is not idempotent. A second disposal returns an
explicit disposed-handle error, matching pinned 3.1.0 behavior.

## 4. Event delivery

Add commit events beside the current tree-change events. Do not replace
`SchemaChanged` and `TreeChanged`; existing subscribers must keep their current
behavior.

For one local data commit:

1. Apply the commit to optimistic state.
2. Create the ordinary tree-change events.
3. Deliver one commit event with local metadata.
4. Permit one factory call during that event.
5. Permit settlement callback registration during that event.
6. Invalidate the factory and settlement registration function after the
   handler returns.
7. Submit the standard channel operation.
8. Invoke registered settlement callbacks after sequencing determines the
   commit outcome.

The commit event and the existing tree-change event must expose the same final
state to reads. Intermediate transaction edits remain private. One successful
outer transaction produces one commit event and at most one revertible.

Remote commits produce a commit event with `local: False`,
`kind: DefaultCommit`, no factory, and no settlement registration function.
This lets applications observe history without treating another client's
commit as locally undoable.

If multiple commit subscribers exist, Watershed must define which subscriber
can acquire the one revertible. Match the pinned 3.1.0 rule: the first factory
call wins, regardless of listener registration order. Other factory calls
return a duplicate-acquisition error. The implementation must not retain one
copy per listener.

## 5. Revertible state and lifetime

Each runtime owns a revertible registry. A public handle contains enough
runtime identity and handle identity to route operations without exposing a
revision or branch implementation.

Each registry entry stores:

- The target revision.
- The target commit kind.
- The retained commit or branch position needed for inversion.
- The repair data needed to restore removed content.
- The ancestry needed to rebase the inverse to the current head.
- Valid or disposed status.

The runtime also stores settlement callbacks for unsequenced local commits.
Acknowledgement or rebased sequencing invokes each callback once and then
removes it.

Creating a handle pins only the history that the inverse needs. It must not pin
the complete document history when a smaller retained prefix or branch record
is sufficient.

Disposal:

1. Marks the handle disposed.
2. Releases its retained commit, repair data, and ancestry references.
3. Lets normal collaboration-window trimming remove data that no other handle,
   pending commit, peer branch, or retained receipt needs.
4. Invokes no tree-change or commit event.

Closing the document or disposing its runtime disposes every handle. A handle
cannot move to another runtime, document, tree address, or reloaded view.

### Reconnect

A live handle survives disconnect and reconnect in the same runtime process.
Pending resubmission and catch-up can rebase the retained inverse when the
application later calls `tree_revert`.

Reconnect must not serialize the handle. It preserves the in-memory registry
and the retained history that the registry references.

### Summary and reload

Undo and redo commits are ordinary SharedTree commits. Their resulting document
state, repair data required by retained wire history, and summary behavior use
the existing formats.

Summary reload does not recreate handles or application stacks. A handle from
the old runtime becomes disposed when that runtime closes. The new runtime can
create revertibles only for new eligible local commits.

## 6. Inversion and rebase

Add a pure history operation that accepts a retained target, the current
history head, a fresh revision, and the current identity order. It returns an
authored inverse commit and updated retention state, or a `TreeError` for
invalid history, missing repair data, identity-order failure, or unsupported
content.

The operation must:

1. Find the retained target commit.
2. Invert its complete SharedTree change with a fresh revision.
3. Exchange apply-time and revert-time node constraints.
4. Rebase the inverse over every later commit in causal order.
5. Preserve later unrelated edits.
6. Recompute explicit constraint violations.
7. Apply the inverse to the current forest.
8. Append one local commit with the derived undo or redo kind.
9. Report the final constraint outcome when sequencing settles the commit.

Use the existing change-family inversion and rebase functions. Do not add a
second object, map, or sequence undo algorithm.

The inverse must use the document compressor identity order. Do not infer
identity order from UUID values or authoring time.

### Transactions

One outer transaction commit is one revertible unit. Reverting it restores the
transaction's complete composed data change as one new commit. An application
cannot retain or revert an inner savepoint.

`tree_revert` returns an error while any transaction is active on that runtime.
It does not append a revert operation to transaction-local state.

### Suppression

When explicit revert constraints fail after rebasing:

- Apply no constrained field effects.
- Preserve created content and repair data that the pinned wire contract
  requires.
- Author and submit the standard revert commit.
- Emit local commit metadata for that authored commit.
- Report `NewContentOnly` when the commit settles.
- Emit ordinary tree-change events only for visible effects that apply.
- Keep or dispose the original handle according to the caller's `dispose`
  argument.

An implicit schema conflict reports `FullyDropped`. A satisfied change reports
`FullyApplied`. Watershed derives these outcomes from the pinned constraint
status, not from visible value equality.

## 7. Runtime integration

### Pure kernel

The tree kernel owns:

- Commit-kind metadata for local appends.
- Pure inverse authoring.
- Application of the rebased inverse.
- Change-event derivation.
- The settled commit outcome.

The history module owns:

- Revertible retention records.
- Ancestry and repair-data pinning.
- Inversion targets.
- Release during disposal and history trimming.

The change modules keep ownership of field-specific inversion and rebase
semantics.

### JavaScript runtime

The JavaScript runtime stores the revertible registry with the existing mutable
runtime state. The event dispatcher activates the one-shot factory before it
calls subscribers. It also permits settlement callback registration. The
dispatcher invalidates both functions after delivery.

Handle operations route through the owning runtime. A handle from another
runtime returns a wrong-runtime error before it changes state.

### BEAM runtime

The BEAM actor owns the same registry, retention state, commit subscribers, and
settlement callbacks. For each commit event, it starts one monitored delivery
process that calls the registered handlers in subscription order. While that
process runs, the actor services acquisition and settlement-registration
requests for the active event ID and defers unrelated messages. Completion or
process exit closes the event, invalidates both functions, and resumes deferred
messages.

The actor must reject late factory calls, duplicate acquisition, and reversion
during a transaction. Remote delivery keeps mailbox order. Reversion authors
one local commit before the actor processes later messages.

Do not keep a caller blocked while waiting for network acknowledgement.
`tree_revert` completes after local authoring and submission, like existing
tree edits. Settlement callbacks run after ordered delivery determines the
outcome.

## 8. Error behavior

Return an explicit error for:

- A factory call after event delivery.
- A second factory call for the same commit.
- A disposed handle.
- A handle from another runtime or tree.
- A missing retained commit or repair record.
- A schema commit.
- Reversion during an active transaction.
- Unsupported schema evolution in the target change.
- Identity-order, inversion, rebase, forest, codec, or submission failure.

Do not convert an internal failure into `NewContentOnly`. That outcome means
the pinned change algebra found an explicit constraint violation.

After every error, the runtime must remain usable. A failed revert must not
leave a pending commit, allocation range, outbound operation, partial forest
change, event, or half-disposed handle.

## 9. Oracle and corpus

Extend the existing SharedTree oracle instead of adding a separate TypeScript
engine. Capture:

- Commit-event metadata and factory availability.
- Factory use during and after event delivery.
- Duplicate acquisition.
- Status before and after revert and disposal.
- Default to undo and undo to redo transitions.
- Optional disposal after applied and suppressed reverts.
- Fully applied, fully dropped, and new-content-only settlement outcomes.
- Object set and replacement.
- Dynamic-map set and delete.
- Array insert, remove, and move.
- Moves between compatible arrays.
- One composed transaction commit.
- Later unrelated local edits.
- Later unrelated remote edits.
- Overlapping remote edits.
- Revert-time node constraint suppression.
- Reconnect before revert.
- Summary and reload after committed undo and redo.

The corpus must record snapshots, commit kinds, factory availability, handle
status, settlement outcomes, emitted events, and canonical wire changes where
the pinned public or source API exposes them.

Do not normalize away detached content, repair data, revision metadata,
constraint state, or move identities.

## 10. Interoperability

Local deterministic tests must prove:

- Native JavaScript and native BEAM produce the same snapshots and outcomes.
- Native inversion matches the pinned source corpus.
- Undo and redo results survive summary round trips.
- Reconnect preserves live handles in the same process.
- Reload creates no handles for old commits.
- Disposed handles release trim eligibility.

Real-service tests must cover:

- Native author, later upstream edit, native undo and redo.
- Upstream author, later native edit, upstream undo and redo.
- Concurrent native and upstream edits where each client reverts only its own
  local commit.
- A native transaction reverted as one unit after a remote edit.
- Array move and removal races.
- Reconnect before native undo.
- Native-created and upstream-created fixed-layout containers.

Remote commits remain non-revertible on the receiving client. Interoperability
tests must not manufacture local handles for remote revisions.

## 11. Acceptance

The phase is complete when:

- JavaScript and BEAM expose the approved public API.
- Eligible local commit events provide one one-shot factory.
- Applications can implement undo and redo stacks without Watershed-managed
  stack state.
- Default, undo, and redo kinds alternate according to the pinned model.
- Object, map, array, move, and transaction commits revert correctly.
- Later unrelated remote edits remain visible.
- Fully applied, fully dropped, and new-content-only outcomes match the oracle.
- Pinned overlapping-edit and constraint outcomes match the oracle.
- Live handles survive reconnect and become invalid on runtime close.
- Summary reload preserves document state without recreating handles.
- Disposal releases retained history safely.
- Existing M1-M4, Identifier, transaction, creation, summary, and browser
  behavior remains intact.
- Local and hosted interoperability gates pass without skipped target,
  service, or corpus rows.
- Documentation marks M5 complete and keeps M6-M8 deferred.

## 12. Deferred work

M6 local branching can reuse parts of the retained-ancestry machinery, but it
requires its own design and plan. Do not expose the private revertible branch
as a public branch API.

M7 crash-recoverable pending state can persist application choices in a later
profile. This phase keeps revertible handles process-local.

M8 reclamation work can optimize retained history after measurements. This
phase must release disposed handles correctly and avoid retaining unrelated
history, but it does not add a new incremental summary or garbage collector.
