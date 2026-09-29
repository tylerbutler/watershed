# SharedTree transaction foundations

**Date:** 2026-09-29
**Status:** Scope and architecture approved in conversation. Written design and
implementation plan require review before execution.
**Parent:** [Native SharedTree interoperability](2026-09-21-shared-tree-design.md),
the transaction-boundary and constraint portion of M5 in section 8.

## 1. Scope and decisions

Implement synchronous public transactions for one SharedTree. A transaction
groups data edits into one atomic SharedTree commit. It can abort without
submitting the edits. It can also require that selected nodes still exist when
the transaction is sequenced.

This is the first M5 slice. It includes:

- A callback API on the JavaScript and BEAM facades.
- Transactions on one SharedTree handle.
- Nested synchronous transactions on that same tree.
- Object, dynamic-map, array, and move edits.
- Atomic commit and abort behavior.
- The stable upstream `nodeInDocument` transaction constraint.
- One local change event after a successful outer commit.
- No local change event for an aborted or no-op transaction.
- One composed outer commit, one channel operation, and normal reconnect and
  summary behavior.
- Native JavaScript, native BEAM, upstream/native, and real-service proof.

Keep these features out of this slice:

- Undo and redo.
- Revert preconditions and revertible lifetime.
- Transactions across multiple SharedTree channels.
- Asynchronous transactions.
- Schema upgrades inside transactions.
- The alpha `noChange` constraint.
- Transaction labels, custom metadata, and post-processors.
- Shared branches and public local-branch APIs.

The user approved a callback API, a single-tree boundary, nested synchronous
scopes, the measured pinned event model, and the stable upstream constraint
subset. A callback error aborts the current scope. The outermost successful
scope produces the only synchronized commit and public change event.

### Global constraints

- Production SharedTree semantics must run in pure Gleam on JavaScript and BEAM.
- Upstream TypeScript packages remain development and test dependencies.
- Use `@fluidframework/tree` version `3.1.0`.
- Use Fluid Framework commit
  `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960`
  (`client_v3.1.0`).
- Use Floodgate commit `0eb493fc46d1bb9baf1151a6ccdde93544e057e7`.
- Keep `minVersionForCollab` at `2.117.0`.
- Keep Message V7, SharedTreeChange V5, ModularChange V5, and Schema V2.
- Preserve the existing fixed container layout.
- Preserve M1-M4 behavior and interoperability evidence.
- Reject unsupported operations instead of approximating their meaning.
- Apply ASD-STE100 to Gleam comments and error strings, not to Markdown prose.
- Do not edit generated files, `.code-map/`, or apm-managed files.

## 2. Upstream contract

The pinned Fluid implementation provides the behavioral and wire contract.
Planning must verify the installed package against the pinned source checkout
before generating the transaction corpus.

Paths below are relative to
`tools/shared-tree-oracle/.reference/FluidFramework/packages/dds/tree/src/`.

| Source | Required behavior |
| --- | --- |
| `simple-tree/api/tree.ts` | Run synchronous callbacks, expose callback success or rollback, and group the outer transaction into one synchronized change. |
| `simple-tree/api/transactionTypes.ts` | Define callback results and the stable `nodeInDocument` constraint. Preconditions are checked locally and again after sequencing. |
| `shared-tree-core/transaction.ts` | Support nested transaction scopes. Inner commit leaves the outer transaction active. Inner abort restores the inner savepoint. |
| `shared-tree/tree.ts` | Start the transaction, add constraints, run the callback, and commit or abort according to the callback result. |
| `shared-tree/treeCheckout.ts` | Resolve node constraints to node identity and add them to the authored modular change. |
| `feature-libraries/modular-schema/modularChangeTypes.ts` | Store node-existence constraints and the aggregate constraint-violation count. |
| `feature-libraries/modular-schema/modularChangeFamily.ts` | Compose, invert, and rebase constraints with field changes. Recompute violation state after rebasing. |
| `feature-libraries/modular-schema/modularChangeCodecV1.ts` | Encode node constraints and the violation count in ModularChange V5. |
| `feature-libraries/modular-schema/invert.ts` | Exchange apply-time and revert-time node constraints while inverting. |
| `shared-tree/sharedTreeChangeFamily.ts` | Classify explicit constraint violations separately from implicit schema conflicts. |
| `core/rebase/types.ts` | Apply no constrained field edits after an explicit violation while preserving required created content. |
| `test/shared-tree-core/transaction.spec.ts` | Define nesting, squashing, abort, and transaction-stack behavior. |
| `test/shared-tree/treeCheckout.spec.ts` and `test/simple-tree/api/transactionTypes.spec.ts` | Define public transaction and constraint behavior. |

### Synchronous callback behavior

Edits inside the callback are immediately visible to reads on the same
transactional view. Remote changes cannot interleave with the synchronous
callback. Public change subscribers do not observe the intermediate edits.

An inner transaction uses the current transaction state as its base. Inner
success keeps its changes in the outer scope. Inner failure restores the state
at the start of the inner scope. The outer callback can continue after handling
that result.

Only the outermost success submits a change. Its edits are composed in authoring
order. A callback failure restores the state from the start of that scope. An
outer failure restores the pre-transaction state without a public change event.

A successful transaction with no effective changes produces no commit,
allocation, outbound message, or additional event.

### Node-existence constraints

The stable upstream transaction constraint requires a selected node to remain
in the document. Identity, not its original path, defines the node. Moving the
node does not violate the constraint. Removing or replacing it does.

Validate every constraint before the callback starts. A missing or detached
node is incorrect API use and prevents the callback from running.

Encode each constraint in the transaction's modular data change. Rebase must
update its violation state. When the sequenced base no longer contains a
constrained node, every client treats the transaction as explicitly violated.
No constrained field edit becomes visible. Created detached content and repair
data that the wire contract requires must remain available for later history
and decoding.

Do not replace this behavior with a local preflight check. A local-only check
cannot detect a concurrent removal that sequences before the transaction.

## 3. Public API

Add a public constraint type to both facades:

```gleam
pub type TreeTransactionConstraint {
  NodeInDocument(path: tree_types.FieldPath)
}
```

Add a generic transaction error:

```gleam
pub type TreeTransactionError(callback_error) {
  Aborted(callback_error)
  TransactionFailed(String)
}
```

Add the transaction function:

```gleam
pub fn tree_transaction(
  tree: SharedTree,
  constraints: List(TreeTransactionConstraint),
  callback: fn(SharedTree) -> Result(value, callback_error),
) -> Result(value, TreeTransactionError(callback_error))
```

The callback receives a SharedTree with the same address and immutable view.
Reads and data edits through that handle use the active isolated transaction
state. Existing tree read and edit functions remain the editing API; do not add
a transaction-specific edit builder.

`Aborted` contains the callback error. `TransactionFailed` reports setup,
constraint, composition, runtime, or transport errors. Errors must identify
unsupported schema edits, cross-tree use, and invalid transaction state.

Nested calls are valid only for the same SharedTree address and runtime. A
transaction call for another tree while a scope is active returns
`TransactionFailed` before its callback runs.

Schema upgrade functions return an explicit unsupported-operation error while
a transaction is active. This slice does not compose schema and transaction
changes.

## 4. Architecture

### Transaction-local state

Add a pure transaction module beside the existing tree history. It owns:

- The base tree state for the outer transaction.
- The current isolated tree state.
- The base and current compressor state.
- Authored changes in callback order.
- Resolved node identities for constraints.
- A stack of nested savepoints.

The isolated state must not append to normal pending history. It must not send
channel operations. It must not update the document's committed runtime state
until the outer transaction commits.

Do not implement abort by appending ordinary pending commits and restoring a
snapshot later. That approach exposes temporary history entries, complicates
reconnect and ID accounting, and can leak events or outbound work.

### Authoring edits

Split the existing local authoring path into two layers:

1. Author and apply one edit against a supplied tree and compressor state.
2. Append a completed outer change to normal history and submit it.

Ordinary edits use both layers immediately. Transaction edits use only the
first layer and record the authored change. This keeps edit validation,
identity allocation, forest updates, schema checks, and array move behavior
shared between ordinary and transactional edits.

Each nested savepoint records the current isolated tree, compressor, authored
change count, and event position. Inner abort restores those values. Inner
success removes only the savepoint.

The transaction must use the same identity ordering rules as ordinary edits.
Do not infer ordering from UUIDs or allocation time.

### Outer commit

On outer success:

1. Compose the authored data changes in callback order.
2. Add the resolved node-existence constraints to the correct node changes.
3. Rebind the composed change with the document compressor identity order.
4. Append one local history commit.
5. Replace the document tree and compressor state with the committed result.
6. Encode and submit one SharedTree channel operation in the normal container
   batch.

If composition is empty, restore the base compressor and finish without a
commit. A no-op transaction must not reserve a document ID range.

Emit one local data-change event after the outer commit when the composed
transaction changes visible data. Subscriber reads during that event must
observe the committed final state.

### Abort and rollback

On abort, restore the scope's savepoint. If the restored visible data differs
from the callback-visible data, do not publish a public tree-change event.

An inner abort does not end the outer transaction. An outer abort removes the
active transaction state completely. It leaves no pending commit, receipt,
peer branch, allocation range, outbound operation, or summary change.

The runtime must remain usable after every reported transaction error. Do not
use a broad catch that converts internal faults into successful aborts.

### Runtime integration

The JavaScript runtime stores the active transaction in its existing mutable
runtime state. The BEAM runtime stores the same semantic state in its actor
loop. Both targets must use the pure transaction module for state transitions.

While a transaction callback is active:

- Reads for its tree use isolated state.
- Data edits for its tree author against isolated state.
- Edits or transactions for another tree fail.
- Incoming remote operations cannot change the transaction base.
- Reconnect and summary publication do not observe partial transaction state.

The BEAM facade can use internal begin, edit, commit, and abort actor messages
to implement the public callback. Those messages are not public API. The
JavaScript facade can use equivalent runtime functions around its callback.
The JavaScript callback blocks remote dispatch naturally. The BEAM actor must
defer incoming remote operations while the outer transaction is active, then
apply them after commit or abort in mailbox order. Do not rebase the synchronous
callback over a remote operation that arrived between two callback calls.

## 5. Change algebra and wire format

Extend the native modular change model with the supported constraint fields:

- A node-existence constraint on a node change.
- A node-existence constraint used when the change is inverted.
- An aggregate explicit violation count.

The codec must preserve the pinned ModularChange V5 representation. Do not add
a Watershed-only wrapper around the SharedTree operation.

Composition must retain constraints and combine their violation counts.
Inversion must exchange apply-time and revert-time constraints even though
public undo is deferred. Rebase must update node-existence violation state when
the target branch detaches, removes, restores, or moves the constrained node.

An explicit violation is not an empty outer change. Preserve the constrained
data change and its violation count in history and wire data. Application
suppresses its constrained field effects according to the upstream outcome
rules. This distinction is required for convergence, summaries, reconnect, and
future undo work.

Constraint support applies to object, map, and array nodes, including nodes
moved within or between compatible arrays. A path is only the authoring input.
All later checks use stable node identity.

## 6. Events and errors

Keep `TreeChanged(local)` as the public data event.

- Intermediate callback edits emit no public data event.
- Inner commit and abort emit no public data event.
- A successful outer commit emits one local event when visible data changed.
- An outer abort emits no public data event.
- A no-op transaction emits no transaction-specific event.
- A sequenced constraint violation emits a remote data-change event only when
  the visible state changes during reconciliation.

Array event bookkeeping continues to track applied array mutations rather than
final value equality. Abort and constraint reconciliation must preserve that
rule.

Use typed core errors for invalid state and unsupported operations. Facades can
adapt runtime details to `TransactionFailed(String)`. Error strings must use
short, literal terms and identify the failed operation.

## 7. Oracle and test corpus

Add a transaction domain to the SharedTree oracle. Generate expected
observations from the pinned upstream implementation. Native runners consume
fixture input only.

The corpus must include:

| Case | Required observations |
| --- | --- |
| Single commit | Intermediate callback reads, one outer local event, one final commit, one operation, and exact final tree and identity state. |
| Outer abort | Intermediate callback reads, no public event, restored tree and identity state, no submitted commit, and no retained allocation. |
| Nested success | Inner reads, one outer event, one outer commit, and author-order composition. |
| Nested abort | Inner rollback to its savepoint, continued outer edits, and one final outer commit. |
| No-op | No commit, allocation, operation, or additional event. |
| Invalid edit | Exact callback error behavior and an unchanged transaction state when the callback aborts. |
| Node exists | A node can move and still satisfy the constraint. A missing or detached node fails before callback execution. |
| Concurrent delete | A remote removal sequenced first marks the constraint violated and suppresses the transaction's field edits on all clients. |
| Created content | Explicit violation preserves the required detached build and repair evidence without exposing constrained edits. |
| Field coverage | Object set/delete, map set/delete, array insert/remove/replace, and same-array and cross-array moves. |
| Reconnect | One pending composed transaction resubmits once and acknowledges without duplicate effects. |
| Summary | A pending transaction is excluded from sequenced summary state and continues correctly after summary plus tail replay. |
| Mixed clients | Upstream authors and reads constrained transactions with native JavaScript and BEAM peers through pinned Floodgate. |

Record complete observations. Include visible values, node identity, retained
history, constraint state, allocation ranges, events, encoded operations, and
summary continuation.

## 8. Validation and acceptance

The implementation plan must name exact commands and expected outputs for:

- Pinned source and package verification.
- Oracle generation and validation.
- Constraint codec round trips and refusal cases.
- Pure algebra tests on JavaScript and BEAM.
- Pure history and kernel tests on JavaScript and BEAM.
- JavaScript facade transaction tests.
- BEAM facade transaction tests.
- Existing M1-M4 SharedTree profile tests.
- Mixed-client local Floodgate tests.
- Hosted interoperability and summary continuation.
- Native container creation regression tests.
- Root JavaScript and Erlang test suites.
- Formatting, lint, and build gates.

Acceptance requires:

- [ ] One outer success produces one composed SharedTree commit.
- [ ] Outer abort restores values, identities, history, and compressor state.
- [ ] Nested success and abort match the pinned upstream observations.
- [ ] One outer commit event and no abort event match the pinned upstream model.
- [ ] Node-existence constraints use identity and survive node moves.
- [ ] A concurrent node removal suppresses constrained edits on every client.
- [ ] Explicit violation remains distinct from an empty or implicit-conflict
      change.
- [ ] Object, map, array, and move edits work in one transaction.
- [ ] Schema upgrades and cross-tree transactions fail without partial state.
- [ ] Reconnect resubmits one transaction without duplication.
- [ ] Summaries use sequenced state and continue with transaction tail ops.
- [ ] Upstream, native JavaScript, and native BEAM clients author and continue
      constrained transactions through pinned Floodgate.
- [ ] M1-M4 profile, service, creation, build, lint, and regression gates pass.

## 9. Deferred work

The next M5 design can add undo and redo after this transaction foundation is
complete. It must define revertible lifetime, repair retention, selective undo,
redo after remote changes, revert constraints, event grouping, and summary and
reconnect behavior.

Later designs can add the alpha `noChange` constraint, transaction metadata,
post-processors, asynchronous transactions, schema changes inside transactions,
and cross-tree atomicity. None of those features is implied by this slice.
