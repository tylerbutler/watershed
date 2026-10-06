# SharedTree local branching

**Date:** 2026-10-05
**Status:** Runtime-local scope and checkout-registry architecture approved in
conversation. Task 1 captured the pinned contract. User review selected
upstream-compatible independent cross-checkout callback edits instead of the
original refusal boundary; native implementation has not started.
**Milestone:** M6, local branching only.
**Parent:** [Native SharedTree interoperability](2026-09-21-shared-tree-design.md)
and [M5 undo and redo](2026-10-02-shared-tree-undo-redo-design.md).

## 1. Scope

Expose local forks of a resolved SharedTree on JavaScript and BEAM. Applications
can edit a fork without changing the document, explicitly rebase it onto another
checkout, and merge its divergent edits into a related checkout. Merging into
the document submits ordinary SharedTree operations.

Include:

- Forks of the document checkout and nested forks of local checkouts.
- The existing object, map, array, move, and Identifier operations.
- Synchronous checkout-local transactions and stable node constraints, with
  independent edits to other checkouts during a transaction callback.
- Explicit rebase and merge between related checkouts in the same runtime,
  document, and tree.
- Checkout-scoped change and commit subscriptions, application-owned undo/redo,
  and one-shot revertible factories.
- Disposal, history and repair-data retention, and runtime shutdown.
- Reconnect in the same runtime and fresh-load proof after merged edits.
- Pinned upstream observations, both native targets, and real-service proof.

Exclude shared or persisted branches, new branch wire messages, historical
revision checkout, schema edits on forks, cross-runtime or cross-tree merge,
async transactions, offline-authoring guarantees, portable revertibles,
clone-to-view, `revertTo`, preview-diff APIs, and richer Lustre bindings.

Do not implement the experimental `createSharedBranch` APIs. Do not turn private
peer branches or revertible records into public handles.

## 2. Compatibility boundary

Keep the existing pins:

| Contract | Pin |
| --- | --- |
| Upstream package | `@fluidframework/tree` 3.1.0 |
| Fluid source | `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960` (`client_v3.1.0`) |
| Floodgate | `0eb493fc46d1bb9baf1151a6ccdde93544e057e7` |
| `minVersionForCollab` | `2.117.0` |
| Codecs | Message V7, SharedTreeChange V5, ModularChange V5, Schema V2 |
| Layout | Existing fixed bootstrap-map/tree container |

Production semantics remain pure Gleam. Upstream packages are development/test
dependencies, not a production branch engine. Preserve M1-M5, native creation,
and the existing main-checkout API.

The current M5 full-build and standalone browser limitation is a separate
release prerequisite: pnpm rejects existing checklist lockfile registry URLs.
M6 design and oracle work can proceed; final acceptance cannot silently waive
the build/browser gates.

## 3. Evidence before native implementation

Read and probe these pinned sources:

| Source under `packages/dds/tree/src/` | Contract |
| --- | --- |
| `simple-tree/api/tree.ts` | Public local fork, rebase, merge, and lifetime |
| `shared-tree/treeCheckout.ts` | Forest/schema cloning, shared allocator, transaction guards, commit events, revertibles, and disposal |
| `shared-tree-core/branch.ts` | Ancestry, rebase, common revisions, merge, and append kinds |
| `shared-tree-core/editManager.ts` | Branch retention and collaboration-window trimming |
| `shared-tree/sharedTree.ts` | Submission, sequencing, summaries, and branch retention |
| `test/shared-tree/treeCheckout.spec.ts` and `test/shared-tree-core/branch.spec.ts` | Observable behavior and edge cases |

The pinned public comments and implementation are not identical: merge comments
mention committing open transactions, while `TreeCheckout.merge` rejects open
transactions. Capture executable behavior, record the discrepancy, and follow
the tested implementation. Similarly, distinguish internal idempotent branch
disposal from public checkout disposal.

An oracle review gate precedes native branch code. Capture exact commit
boundaries, revisions, encoded changes, events, disposal results, allocation,
and persistence observations. Do not assume a merge is one transaction or one
commit; the core merge appends surviving source commits.

Normalize upstream private storage into stable semantic observations, as in
the transaction corpus. Keep exact protocol bytes as separate raw evidence.
Native runners receive scenario inputs, not expected observations. Final-value
equality alone does not prove branch behavior.

The upstream schema-divergence observation is required source-only evidence.
Its fork-local schema authoring and drop-on-rebase result are outside the native
contract. Native rebase comparison includes every other row and uses one named
projection exception for this row. The native gate separately requires the
explicit branch-schema refusal and atomic-state proof; it must not present that
refusal as upstream-equivalent behavior.

## 4. Architecture

### Checkout identity and ownership

Extend the opaque facade `SharedTree` with an internal checkout selector:
document checkout or runtime-local checkout ID. Existing resolution returns the
document selector. Fork returns another `SharedTree`, allowing existing reads,
edits, transactions, and subscriptions to use the fork without parallel public
APIs for every field operation.

Each runtime owns a checkout registry. A local entry owns its forest, fixed
stored schema, ancestry/head, branch-local commits, transaction state, and
subscription/revertible bookkeeping. It refers to the same document allocator
and tree origin as its siblings. Use explicit internal selector types, not
synthetic channel addresses or serialized handles.

The document checkout remains the only sequenced channel and summary writer.
Local checkout entries must not enter the routed channel registry, bootstrap
map, wire channel attributes, or document snapshots.

A tentative lifecycle surface on both facades is:

```text
tree_fork(tree) -> Result(SharedTree, String)
tree_rebase_onto(source, target) -> Result(Nil, String)
tree_merge(target, source, dispose_source) -> Result(Nil, String)
tree_branch_status(tree) -> checkout status
tree_dispose_branch(tree) -> Result(Nil, String)
```

Use `dispose_source: True` for the documented default merge pattern, consistent
with upstream. Final internal result types and event shapes are fixed at the
oracle/contract gate, not guessed from these sketches.

### Pure history and forest

Reuse `shared_change.compose`, `shared_change.invert`, and
`shared_change.rebase`. Generalize the existing ancestry reconciliation only
where needed for local checkout paths, without replacing peer reconciliation
with a second branch algorithm.

Fork captures the current optimistic document or local checkout head, including
unacknowledged edits. The forest and detached repair state are isolated through
persistent state, not JSON export/import or summary restore. It must retain the
actual ancestry and stable node identities.

Explicit rebase changes the source checkout, not the target. A local checkout
does not automatically change when the document receives remote commits.
Merge computes the source changes relative to the target and applies the pinned
result atomically. Already shared revisions are not submitted twice.

### Allocation

All checkouts use one document compressor and revision allocator. Do not clone
allocator state at fork, generate a branch-specific session, reuse IDs after
disposal, or reset allocation after a branch transaction abort. Interleaved
branch, main, rollback, and Identifier authoring must remain collision-free.

Branch edits emit no tree operations. Capture whether ordinary allocation-only
messages occur before merge and follow the pinned result; “local branch” does
not imply zero document-wide allocation traffic. Merge publishes the required
allocation ranges ahead of operations that reference them, including ranges
reserved by edits that were later discarded.

### Runtime dispatch

Resolve checkout identity once at each runtime boundary. Route all supported
reads, authoring, map/array/move helpers, compatibility checks, transactions,
commit subscriptions, and reversion through that resolution. Main-only
operations such as summaries and routed history diagnostics stay main-only.
Avoid one branch-specific copy of each field API.

JavaScript cell updates and BEAM actor messages must preserve checkout identity
through callback delivery and deferred work. Keep the existing event-delivery
locks for commit and settlement notifications. Transaction callbacks may edit
another checkout independently; their completion must install only the owning
checkout's transaction result, not overwrite the registry, allocator, events,
or outbound work produced by another checkout during the callback.

## 5. Behavioral contract

- Fork and rebase reject an active transaction on either affected checkout.
  Merge rejects active transactions on source or target.
- Each transaction remains synchronous and owns one checkout. Match pinned
  upstream by allowing its callback to edit another live checkout in the same
  runtime, document, and tree. The other edit follows that checkout's normal
  authoring and publication path; it is not part of the first transaction.
  Commit or rollback affects only the owning checkout. In particular, a main
  edit made during a fork transaction survives that transaction's rollback.
  Preserve the shared allocator's advancement and the other checkout's forest,
  history, events, and outbound operations on both commit and rollback.
  Cross-checkout atomicity and cross-tree transactions remain excluded.
- The document checkout cannot be rebased onto a local checkout.
- Reject unrelated runtime, document, or tree origins before changing either
  checkout, allocating IDs, delivering events, or queuing operations.
- Probe self-rebase, self-merge, empty merge, repeated merge, and preserved-source
  merge before assigning their exact no-op/disposal behavior.
- Schema edits on a fork return an explicit unsupported-operation error.
  A schema change arriving on main follows the pinned rebase/merge compatibility
  behavior; reject unsupported schema reconciliation atomically rather than
  ignoring the changed schema. The refusal leaves checkout lifetime, forest,
  history, allocator, events, and outbound state unchanged.
- Disposing a checkout releases its own pins, subscriptions, and revertibles.
  Descendants keep independent ancestry pins and remain usable if supported by
  the pinned checkout contract; this is a required oracle case.
- Runtime close invalidates all local checkouts. Summary reload creates no old
  branches, handles, subscriptions, or application stacks.
- Apply the existing ready-phase discipline to authoring and publishing.
  Reconnect retains branches in-process; no new offline-authoring API is added.

Errors follow existing facade/runtime conventions. Failed rebase or merge must
not leave partial forest, history, allocator, event, or outbound state.

## 6. Undo, events, and settlement

Revertibles identify a checkout as well as a runtime and tree address. Acquiring
one on a fork cannot make it refer to the main checkout. Fork does not duplicate
existing application stacks; cross-checkout handle cloning remains excluded.

Preserve default/undo/redo labels and one-shot factory rules for branch-local
authoring. Disposal invalidates only the disposed checkout's handles, not those
on related live checkouts.

Probe merge event counts and kinds, original versus merged handle lifetime,
rebase notifications, and settlement callback registration for unsequenced
branch commits. Do not report `FullyApplied` merely because a local fork edit
changed its forest. Any settlement result must be backed by the pinned contract
and an actual sequencing observation where sequencing is required.

The oracle gate must resolve whether branch commit subscriptions expose the M5
settlement registration function before merge, how merge creates target
factories, and what happens to source registrations on disposal. Record this
explicitly before runtime/facade tasks; do not silently drop callbacks or invent
a “settled locally” outcome.

An accepted settlement registration is independent of the commit subscription
that created it on both JavaScript and BEAM targets. Unsubscribing stops future
commit and change notifications, including later callbacks from a delivery
snapshot, but does not cancel an already-registered settlement callback. That
callback runs exactly once when the commit settles. Checkout disposal cancels
registrations owned by that checkout, and runtime close cancels all remaining
registrations and queued settlement callbacks.

## 7. Retention and persistence

Local checkout ancestry pins coexist with pending edits, peer histories, and M5
revertibles. Minimum-sequence advancement cannot reclaim a live checkout's base,
rollback ancestry, or repair content. Rebase may advance a pin only after the
new ancestry and forest are installed. Disposal releases only that checkout's
retention; the next trimming pass can reclaim unreferenced data.

Summaries remain sequenced document state. Unmerged fork content and local
checkout registry entries are not persisted. Do not confuse a runtime retention
pin with a new summary branch format. Use the pinned summary behavior for
retained history and allocation metadata.

After merge, upstream, JavaScript, and BEAM summary readers must load the
document, continue editing, and confirm that no historical fork reappears.
Reconnect must preserve a fork made from pending main edits, reconcile those
edits after accepted-before-drop recovery, and allow one nonduplicated merge.

### Deferred future work: checkout-local schema authoring

**Status: DEFERRED, not discarded.** The pinned
`local-branch-rebase`/`schema-divergence` observation is the reference evidence
for a future design. It shows a fork authoring a wider schema and rebase onto an
old-schema target dropping the incompatible schema change and its dependent
edit. The
[parent roadmap follow-up](../plans/2026-09-21-shared-tree.md#deferred-branch-schema-work)
tracks future approval and acceptance. The current local-branch contract
continues to reject schema authoring before mutation.

Future authorization must define and prove:

1. Atomic schema authoring on a local checkout, including rollback and failure
   behavior.
2. Rebase compatibility and the exact rule that drops an incompatible schema
   change and every dependent edit without changing the target.
3. Native JavaScript and BEAM parity for authoring, rebase, events, errors, and
   checkout lifetime.
4. Allocator, revertible, settlement, descendant, disposal, and runtime-close
   behavior while a branch owns a divergent schema.
5. Wire and summary boundaries: no branch schema persistence or publication
   before merge, explicit publication behavior at merge, and reload without a
   historical checkout.

This item is future work only. It does not weaken the current refusal gate or
claim upstream-equivalent native behavior.

## 8. Acceptance

Require named evidence for:

1. Fork isolation, nested forks, stable node/Identifier identity, and shared
   allocator correctness.
2. Rebase and merge for object, map, array, same-array/cross-array move, and
   transaction changes, with unrelated and overlapping edits in both orders.
   The upstream schema-divergence row remains required source-only evidence.
3. Common-revision deduplication, preserved-source repeated merge, empty and
   self operations, and atomic refusal cases, including branch schema authoring
   refusal with unchanged checkout lifetime, forest, history, allocator,
   events, and outbound state.
   Merge observations use public notification metadata and actual outbound
   lists. An advertised revertible factory must produce a valid retained
   revertible. Self-rebase history is read after rebase.
4. Branch-local undo/redo, target merge factories, source disposal, callback
   scope, and honest settlement behavior. Independent cross-checkout callback
   edits survive the owning transaction's commit or rollback on both targets.
5. Retention beyond MSN with multiple branches and independent revertibles,
   including parent disposal while a descendant is live.
6. In-process reconnect, pending-main fork origins, and accepted-before-drop
   merge recovery.
7. Unmerged-branch summary exclusion and all three-writer/three-reader
   continuation cells after merged edits.
8. Both native targets, exact standard wire evidence, and pinned-service
   upstream/native convergence.
9. Permanent gates rejecting missing scenarios, targets, raw artifacts, event
   observations, allocation evidence, or reload cells.

Isolation evidence retains a node reference before removal, reads the detached
node through that reference, checks attachment refusal through the reference
API, and rereads the document after refusal and after rejected document-view
disposal.
10. Existing M1-M5 behavior, creation, full build, and standalone browser
    acceptance without claiming shared branches or other M7/M8 features.

Stop and revise the contract if the required local behavior needs a codec,
service, package-version, or summary-format change; a second changeset engine;
portable handles; or expected-output copying. Design approval is not evidence
that those expansions are allowed.
