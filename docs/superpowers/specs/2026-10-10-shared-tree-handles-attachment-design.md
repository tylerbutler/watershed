# SharedTree Handles and Live Attachment Design

**Status:** Tasks 1-9 are accepted locally as of 2026-10-13. The final code
range ends at `c0fff951e128776c3f670d22f017482dc24d00c4`; the implementation
plan records the source/native/codec/service/browser commands, run IDs,
counts, review closures and execution rulings. M7 remains partial. No hosted
workflow or release publication is part of this local acceptance.

**Parent:** [Native SharedTree design](2026-09-21-shared-tree-design.md),
M7 application and container lifecycle.

**Plan:** [Handles and live attachment](../plans/2026-10-10-shared-tree-handles-attachment.md).

## 1. Outcome and boundary

Enable upstream, native JavaScript, and native BEAM clients to store Fluid
channel handles in SharedTree, create detached maps and trees while a container
is open, and attach their dependency graphs through a reference from a visible
DDS. Include references between declared datastores in the same container.
Clients must resolve the referenced channels, edit them, reconnect, publish
summaries, and load those summaries through another implementation.

SharedTree owns schema, values, edits, and retained tree history. The document
runtime owns channel and datastore identity, handle binding, attachment,
message order, and resolution. A handle leaf identifies a Fluid object; it does
not embed that object's data in the referring tree.

The supported target kinds for this slice are SharedMap and SharedTree channels.
Declare a secondary datastore factory with a SharedMap entry point and the
existing map/tree registry. Use that factory for native-authored secondary
datastores and register it with the upstream test application's code loader.
This provides a cross-datastore lifecycle without adding a general application
factory framework.

Preserve the existing `root` alias, bootstrap map API, and fixed-layout
`create_tree_container` behavior. The graph profile extends an existing
container through declared channels and datastores. New alias authoring is a
separate feature; handles can reference physical datastore/channel paths without
an alias. Continue processing and preserving supported inbound aliases.

This slice excludes blob handles and pending blob payloads, arbitrary Fluid
object implementations, datastore-entry-point handles as tree leaves,
cross-container references, arbitrary application factories, production token
services, disk recovery, shared/persisted branches, and GC sweep. These are
Watershed profile boundaries, not claims about upstream's full capabilities.

## 2. Checked upstream behavior

The checked source is Fluid 3.1.0 at
`c3c5bf0ecd313362e83fe8a02b7d39e7e0736960`. Use this source rather than current
documentation to settle behavior.

| Contract | Pinned source |
| --- | --- |
| Handle leaf schema holds `IFluidHandle`; its identifier is `com.fluidframework.leaf.handle` and its stored value kind is `3`. | `packages/dds/tree/src/simple-tree/leafNodeSchema.ts`, `simple-tree/api/schemaStatics.ts`, and native `tree/schema.gleam`'s existing comparison parser |
| Serialization calls `bind.bind(handle)` before emitting a serialized handle. Decoding resolves legacy relative paths with the serializer's context. | `packages/dds/shared-object-base/src/serializer.ts`, `FluidSerializer.bindAndEncodeHandle` and `decodeValue` |
| A visible DDS attaches an incoming handle graph. An invisible DDS retains pending bindings. Graph traversal marks local visibility before recursion, then binds the object to its datastore. | `packages/dds/shared-object-base/src/handle.ts`, `SharedObjectHandle.bind` and `attachGraph` |
| Staging mode suppresses binding until the runtime commits staged work. This is a runtime feature, not proof that ordinary SharedTree transactions share its semantics. | `packages/dds/shared-object-base/src/handle.ts`, `SharedObjectHandle.bind` |
| Datastore visibility attaches bound handles and propagates through the datastore context. The code imposes no same-datastore restriction. | `packages/runtime/datastore/src/dataStoreRuntime.ts`, `bindChannel`, `bind`, and `makeVisibleAndAttachGraph` |
| A decoded remote handle resolves through the container's routing context; `get()` returns a promise. | `packages/runtime/runtime-utils/src/remoteFluidObjectHandle.ts` |
| The SharedTree test suite rejects attaching a tree during that tree's active transaction. | `packages/dds/tree/src/test/shared-tree/sharedTree.spec.ts`, `throws an error if attaching during a transaction` |
| SharedTree supports local edits and completed transactions in an attach summary. Its incomplete-transaction attach test is skipped and supplies no acceptance evidence. | The same file, attach-summary tests |

These sources establish the architectural split. They do not settle the exact
binding time for every tree edit, the fate of a removed binding, the wire order
of a cyclic cross-datastore graph, or retained-history GC routes. Task 1 captures
those behaviors through executable probes and writes a contract table before
native implementation begins.

Do not replace binding history with a scan of the final visible values. A DDS
can bind a handle while serializing a value that it later removes. Capture
whether upstream retains that dependency and reproduce the observed behavior.
Do not extend staging-mode guarantees to transactions or local branches without
an executable observation.

### Execution observations, 2026-10-10

These observations come from the registered
`packages/dds/tree/src/test/watershedLifecycle.spec.ts` injection. The generated
cases record its digest under `raw.source`. They establish the bounded Task 1
contract below, not native lifecycle support or arbitrary Fluid behavior.

| Case / scenario | Measured result | Raw evidence |
| --- | --- | --- |
| `handle-leaves` / root, object, map and array edits | Each executable edit has its own captured schema, initial typed root, edit arguments and matching observed output. Required and optional roots use handle-root schemas; the other edits use the `Root` object schema. All use the tagged `{"kind":"handle","value":{"type":"__fluid_handle__","url":"/B/child"}}` value. | `input.scenarios[].input`; `raw.serialization` kind `executable-edit` |
| `handle-leaves` / `same-target-handles` | A separately decoded handle wrapper is not the source wrapper, but both `get()` calls resolve the same live SharedMap instance, route, type and visible data. | `raw.serialization` kind `live-handle-resolution` |
| `handle-leaves` / `relative-path`, `escaped-path` | The same relative `child` marker resolves through two distinct live source datastore contexts to their respective maps. A real channel whose logical ID is `space and#hash` resolves from `/A/space%20and%23hash`; the decoded handle keeps the escaped path while the resolved target reports its logical channel path. | `raw.serialization` kinds `legacy-relative-resolution` and `escaped-live-resolution` |
| `handle-leaves` / `uncompressed-v2`, `schema-aware-v2` | Both scenarios contain executable FieldBatch V2 payloads, the captured stored Schema V2 document, source datastore context, tagged handle value and literal decoded nodes. Validation structurally decodes each payload and compares schema, payload and decoded value; it does not scan strings for marker text. | `input.scenarios[].codec` and the matching `raw.summaries` records |
| `handle-leaves` / `malformed-marker`, `unsupported-marker` | Genuine serializer calls throw for missing/non-string URLs and a late nested malformed marker. A pending marker decodes to a handle and is accepted by the tree, while the native profile refuses it. An unknown marker kind remains ordinary JSON and only tree assignment refuses it. External, traversal and invalid-escape URLs decode to handles upstream, fail target resolution in this document, and remain explicit stronger native-profile refusals. | `raw.serialization` kinds `serializer-outcomes` and `tree-assignment-outcome` |
| `live-channel-attachment` / `serialize-remove` | A detached map's attach-summary serialization binds its target. Removing that value before attaching the owner does not remove the binding: the target attaches while the owner's displayed value is absent. Merely setting and deleting the value without serialization did not attach the target in the earlier probe. | `raw.summaries` (`owner-before-removal`) and the matching `raw.messages` slice |
| `live-channel-attachment` / all seven positive scenarios | A distinct receiving client resolves the attached targets and reads their actual map/tree data. Nested references resolve their dependencies; self and two-channel cycles resolve back to the original DDS instance. The completed detached transaction loads with label `committed`. The serialized-then-removed target still resolves although the owner has no displayed reference. | `raw.serialization` kind `receiver-graph`; `expected.observations[].value.receiver`; decoded channel attach snapshots and reference operations |
| `live-channel-attachment`, `cross-datastore-attachment` / replay input | Each case includes the actual initial document snapshot, base64 blob bytes, protocol sequence, stored compressor, writer's ongoing compressor/session, runtime registry, entry point, and gap-free sequenced prefix. Each positive scenario has cumulative typed commands and an inclusive prefix checkpoint. These are attachment-snapshot inputs, not published-summary evidence. | `input.decoderInput`; `input.scenarios[].commands` and `.replay`; matching `raw.messages` slices |
| `cross-datastore-attachment` / all four scenarios | The receiving client reads the secondary map, resolves both sides of unpublished map/tree cycles, and resolves a secondary tree through both the primary tree and secondary entry-point map to the same DDS instance. Datastore snapshots carry the declared package and root channel; the later secondary tree arrives as a channel attach after that datastore is visible. | `raw.serialization` kind `receiver-graph`; datastore/channel snapshot metadata and live FieldBatch roots in `input.decoderInput.deliveryPrefix` |
| `cross-datastore-attachment` / `map-cycle`, `tree-cycle` | Two unpublished declared stores can reference each other. The captured batch contains allocation, the dependency store attach, the referring store attach, then the visible DDS operation. Each cycle has two genuine datastore attaches. | `raw.messages`; `expected.observations[].value.attachOrder` is checked against the actual nested message envelopes |
| `handle-transaction-branch` / `successful-transaction`, `aborted-transaction`, `nested-transaction` | Intermediate local reads contain the new handles while targets remain unattached and transport stays empty. Event counts do not advance before outer commit. Successful/nested commit attaches the target and the receiver sees the committed state. Rollback restores the prior reference, leaves its target unattached, and preserves the local compressor advancement made by the aborted edit. The target map's independent `independent: "survives-rollback"` edit survives. The nested map/array edits publish in one tree operation. | `history-checkpoint.stages`, `.events` and `.targets` in `raw.serialization`; actual `replay-transport` or empty `checkpoint` in `raw.messages`; `checkpoint-tree` in `raw.summaries`; `aborted-transaction.value.targetData` |
| `handle-transaction-branch` / `branch-before-merge`, `branch-after-merge`, `branch-dropped`, `branch-disposal` | Branch-only references are absent from the main and receiving trees, with no target attachment or transport. Merge attaches the target and updates both trees; disposing an unmerged checkout leaves its target unattached. | Typed named-checkout commands; `history-checkpoint.branches`, `.targets` and `.receiver`; matching sequenced slices |
| `handle-transaction-branch` / `handle-undo-peer-edit` | A separately loaded client edits the target map after changing from its read connection to a new write connection. Undo restores the parent's previous reference without removing the peer's target edit. The originally acquired insertion revertible changes from status `0` (valid) to `1` (disposed) through default revert; it is not acquired again or disposed a second time. | `input.decoderInput.sessions.receiverClientId` and `.receiverWriteClientId`; two DDS authors in `raw.messages`; revision-keyed refresher; `revertibleStatus` and `history-checkpoint` |
| `handle-transaction-branch`, `handle-retention` / history replay input | Both cases have the actual initial snapshot/blob/compressor/runtime input, exact cumulative creation/edit/transaction/checkout/revertible/publication commands, and contiguous sequenced prefixes. Sixteen checkpoints record actual writer, receiver, target and relevant branch state. Every retained publication's map/tree bytes match its sequenced graph, and fresh continuation is a later peer-authored map edit. | `input.decoderInput`; `input.scenarios[].commands` and `.replay`; `raw.serialization` kind `history-checkpoint`; `raw.summaries` kind `checkpoint-tree` and `published-document` |
| `handle-transaction-branch` / separate multi-tree identity document | Two actual trees share the document compressor. Channel creation reserves generations 1 and 3; schema commits reserve 2 and 4. Detached edits reserve 5 and 6. Attaching the right tree first finalizes all six reservations; an intervening detached left edit reserves generation 7 without finalizing it until left attachment. Subsequent writer and peer edits allocate in their respective sessions; undo uses the original detached edit's revision. | `input.identityReplay`; `successful-transaction.value.identityLifecycle.checkpoints[].compressor`; `raw.serialization` kind `identity-lifecycle`; `raw.messages` kind `identity-transport` |
| `handle-transaction-branch` / twelve identity checkpoints | The same channel, root node, checkout and anchor survive promotion, writer/peer edits and undo. The anchor remains at `rootFieldKey`, index 0. Independent checkpoint summaries decode to the measured tree state; attached checkpoints also match the sequenced receiver graph. | `identityLifecycle.checkpoints[].trees`: `.path`, `.sharedDocumentCompressor`, `.sameRoot`, `.sameCheckout`, `.sameAnchor`, `.anchor`, `.summary`; `.peer.trees` and `.peer.finalTrees` |
| Both history cases / local and receiver events | Local changed events contain actual encoded changes, stable revisions, `Default` or `Undo` kind and inverse-factory availability. Remote events are `Default`, nonlocal, with no factory or local change. Every measured main local commit settles `FullyApplied`; abort and nested intermediate stages add no commits. | `history-checkpoint.events.writer` and `.receiver`; `history-checkpoint.stages[].eventCounts`; source-local changes structurally compared with actual Message V7 commits |
| `handle-transaction-branch` / branch factory and channel-marker lifetime | Branch edits have one local event, an acquired inverse and no settlement, including after merge/disposal. Working inverses remain valid before merge and dispose on merge; dropped/disposed checkout inverses dispose immediately with the same-handle callback. Duplicate acquisition fails during the event; late acquisition fails outside it. The serialized branch marker resolves the existing document tree, not unmerged branch content. | `history-checkpoint.events.branches[].events`, `.settlements`, `.handles`; `branch-before-merge.value.branchHandle`; fork/edit reservation checks against preceding ongoing compressor state |
| `handle-transaction-branch` / detached inverse lifetime | Detached data edits expose an inverse factory and settle locally; schema initialization has no factory. The original acquired left-edit inverse survives both attachments and a peer edit, restores `left-detached`, and auto-disposes. Explicit final disposal disposes all remaining application-owned inverses without transport. | `identityLifecycle.checkpoints[].trees[].events`; `.revertible`; `.peer`; exact subscription/revert/disposal commands and the undo's revision-keyed string refresher |
| `live-channel-attachment` / `active-transaction`; `handle-transaction-branch` / `active-target` | A real document graph publication attempt throws the exact active-transaction error after submitting allocation and channel-attach transport. The target becomes attached, while both target and parent tree views enter the measured invalid state. The refusal is not atomic. | `raw.messages` records of kind `document-attachment`, including the target attach snapshot and sequenced transport |
| `handle-retention` / removal, undo, retained repair, branch disposal, revertible disposal | Each checkpoint publishes a full document summary. Stored GC bytes continue to route to the referenced target through the captured retention states. | `raw.summaries` records of kind `published-document`, with fetched tree/blob bytes, parsed GC, component metadata, and sequence boundaries |
| `handle-retention` / `unreferenced-datastore` | The removed secondary datastore remains non-root metadata with retained GC nodes and the frozen `1700000000000` unreferenced timestamp on both datastore and root-channel routes. | The published snapshot's `/gc/__gc_root` and `/.channels/P/.component` bytes |
| `handle-retention` / `fresh-load` | A fresh upstream client loads the named published version, resolves the target path from those stored bytes, and writes `continued: true`; the original writer observes the edit. The fresh checkout has no restored local events, inverses or revertible branches. | Published handle and stored snapshot/blob bytes plus the continuation observation and `freshLocalLifetime` |

Native active-target attachment will enforce a stronger refusal boundary than
the measured upstream failure. Whole-candidate validation must reject the
candidate before it changes state or submits allocation or attach transport.
Keep the upstream allocation, attach snapshot, and invalid-view evidence as the
raw compatibility observation, but do not require native failure-side-effect
parity. Accepted graph operations must still preserve the measured upstream
wire ordering.

Both active-target scenarios use separate documents. Their own
`input.decoderInput` and typed commands preserve the measured failed
submission; `replay.nativeBoundary` is `preflight-refusal`. The native runner
must not submit those captured failure tails as accepted candidates.

Graph validation decodes map headers, keyed FieldBatch roots, and the captured
optional-handle reference edits. It compares the resulting checkpoint graph
with the finite commands and measured receiver data. It does not implement a
second CRDT or general application runtime. Delta storage uses an empty
`traces` array; live joins and some operations include service `start`/`end`
traces, while other live operations omit the array. Validation checks those
trace shapes and compares the remaining
envelope without changing the captured identities, contents, or bytes.

The two map-only cross-datastore scenarios run before any tree is created.
Their commands do not require Task 4's tree APIs. The primary tree setup starts
in `tree-cross-datastore`; `tree-cycle` creates both detached trees before
initializing either, preserving the source's allocation order.

History validation extends that bounded decoder to the measured nested
map/sequence insertions, optional clears, revision-keyed undo refreshers, peer
map edits, and summary membership/proposal/acknowledgement messages. Refresher
leaves must match the node removed under the referenced revision. Exact
command sequences are checked against independently decoded transport and
checkpoint forests, not a scan for handle marker text. Published snapshots
are checked at their own reference sequence, before fresh-client edits.

Identity validation replays the exact twelve-checkpoint schedule through the
pinned compressor. It compares ongoing and summary serialization, cloned
unfinalized ranges, stable channel/revision IDs, detached attach-history
payloads, and writer/peer allocation messages. IDs come from compressor
allocation order, never UUID sorting or timestamps. Root and checkout
comparisons are actual source-object references bound to those channels.

Local event metadata uses SerializedChange V1 with session-space revisions;
the message stream uses Message V7 with originator-relative op-space
revisions. Validation resolves both to stable revisions and decodes generic
and schema-aware FieldBatch builds before comparing commit atoms and values.
An isolated unattached serializer sink captures event handles without
publishing branch-only bindings. Branch-only settlements remain empty rather
than borrowing the main merge event's settlement.

The original Task 1 checklist has been audited against all five cases.
Seven non-skipping source probes, 239 source/generator/codec tests and all 68
byte-reproduced cases close the discovery gate. The original 63 cases,
manifest and native profile are unchanged. Tasks 2-9 must still implement and
prove the native APIs, codecs, persistence and service matrices.

## 3. Global constraints

- Preserve pure Gleam SharedTree semantics on JavaScript and BEAM.
- Keep Fluid 3.1.0, source `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960`,
  Floodgate `0eb493fc46d1bb9baf1151a6ccdde93544e057e7`, and
  `minVersionForCollab` `2.117.0`.
- Keep Message V7, SharedTreeChange V5, ModularChange V5, Schema V2, and
  nonincremental FieldBatch V2.
- Preserve the existing root alias, bootstrap-map API, and fixed-layout native
  container creator.
- Preserve M1-M6 contracts, existing DDS APIs, runtime-local branch ownership,
  and application-owned revertibles.
- Keep the Fluid SDK development-only; add no production dependency, package
  dependency, or lockfile change.
- Implement handle values in the tree and attachment/binding in the document
  runtime; the pure tree kernel performs no I/O or channel creation.
- Support same-container SharedMap and SharedTree channel references across
  declared datastores; do not claim arbitrary Fluid application support.
- Validate a local submission before committing its candidate state or sending
  any of its messages; transport acceptance is not a rollback boundary.
- Preserve document compressor advancement and upstream allocation order;
  never finalize a creation range merely because a local edit allocated IDs.
- Match pinned upstream binding, attach-summary, transaction, and retained-GC
  observations; do not infer them from visible-value convergence.
- Required gates must execute upstream, JavaScript, BEAM, and their service
  cases with zero skips; a skipped upstream test supplies no proof.
- Apply ASD-STE100 to Gleam comments/error strings, not Markdown prose.
- Do not hand-edit generated fixtures, `.code-map/`, apm-managed files, or the
  pinned reference checkout.

## 4. Native handle values

Add `HandleLeaf` to `tree/schema.LeafKind` and
`HandleValue(handle.Reference)` to `tree/types.TreeValue`.
`handle.Reference` is an opaque, pure reference to a supported absolute
datastore/channel path. It contains no runtime, callback, promise, or SDK
object. Tree schema compatibility must distinguish it from `StringLeaf`.

Use these pure interfaces in the existing `watershed/handle` module:

```gleam
pub opaque type Reference

pub fn reference_from_path(path: String) -> Result(Reference, HandleError)

pub fn reference_from_json(
  value: Json,
  context_path: String,
) -> Result(Reference, HandleError)

pub fn reference_path(reference: Reference) -> String

pub fn reference_to_json(reference: Reference) -> Json

pub fn bind_serialized_references(
  value: Json,
  context_path: String,
) -> Result(Json, HandleError)
```

Reuse the existing marker/path validation and contextual decoding. Encode the
upstream `{"type":"__fluid_handle__","url":"/B/child"}` marker. Keep the upstream
rules for percent escapes, absolute paths, and legacy relative paths; Task 1
must capture equivalent-path/equality behavior before defining normalization.
Pass the source datastore's context to legacy relative decoding. Do not use the
containing tree field's path as the Fluid handle context.

Use `bind_serialized_references` at the runtime/summary decoding boundary,
after parsing a channel's JSON payload or summary blob and before invoking
context-free tree codecs. It converts serialized relative handle markers to
supported absolute markers through the existing path helpers. Context-free
FieldBatch codecs accept absolute references and return an explicit context
error for relative references. This preserves their signatures while matching
upstream's contextual serializer layer.

A parsed marker supplies a document-relative address, not proof of its original
container. Do not claim that copied JSON can prove foreign-container provenance.
Facade objects remain runtime-bound; operations that accept a local datastore
object must reject an object from a different runtime. Local references to
unknown targets produce an explicit resolution or submission error.

Handle leaves work at a required/optional root, in object fields, map entries,
and array elements. Existing set, clear, insert, move, transaction, branch, and
undo operations use them without adding a parallel edit algebra. Leaf values
remain opaque references: two trees pointing at a map do not own that map's
contents or undo its later edits.

Wire/summary support covers compressed and uncompressed nonincremental
FieldBatch V2, builds, refreshers, repair data, retained detached tree nodes,
and edit-manager history. Existing fixture and client value records add:

```json
{"kind":"handle","value":{"type":"__fluid_handle__","url":"/B/child"}}
```

## 5. Runtime graph and creation

Keep the graph in `runtime_core`, alongside its existing detached-channel and
in-flight state. Extend the existing dependency traversal and batching helpers.
Do not introduce a second runtime or a general graph framework.

Track unpublished datastores separately from registered, visible datastores.
Track handle bindings at the upstream-observed serialization boundaries.
Attachment state must distinguish unpublished objects, objects made visible
locally with a pending attach, and objects whose attach has sequenced. Reuse
`detached`, registered channels, and in-flight records where they represent
those states; add only the missing datastore/binding state.

The declared graph datastore type is
`org.watershed.shared-tree.m7.graph`. Its upstream factory uses the existing
`defineDataStore` mechanism with a SharedMap entry point and
`sharedObjectRegistryFromIterable([SharedMap, SharedTree])`. Its package
identity must match the captured factory registration. Native callers do not
submit arbitrary package strings.

Public facades gain matching JS/BEAM lifecycle APIs:

```gleam
pub opaque type DataStore

pub fn create_data_store(
  document: Document(root),
) -> Result(DataStore, String)

pub fn data_store_root(store: DataStore) -> Result(SharedMap, String)

pub fn create_map_in(
  document: Document(root),
  store: DataStore,
) -> Result(SharedMap, String)

pub fn create_tree(
  document: Document(root),
  stored: tree_schema.StoredSchema,
  initial_root: Option(tree_types.TreeValue),
  view: tree_schema.ViewSchema,
) -> Result(SharedTree, String)

pub fn create_tree_in(
  document: Document(root),
  store: DataStore,
  stored: tree_schema.StoredSchema,
  initial_root: Option(tree_types.TreeValue),
  view: tree_schema.ViewSchema,
) -> Result(SharedTree, String)
```

`create_tree` uses the current bootstrap datastore.
`create_tree_in` and `create_map_in` check datastore/runtime ownership.
Creation requires a ready writable document but sends no attach or channel
operation. Existing `handle_of`, `tree_handle_of`, `bind_handle`, `resolve`,
`open_tree`, and `resolve_tree` remain the handle/resolution APIs.
`data_store_root` gives callers a channel handle through `handle_of`; this
slice does not add a datastore-entry-point leaf type.

When a visible DDS serializes a new binding, prepare the attachment graph and
the referring edit as one candidate submission. Validate target identities,
schemas, attributes, context, snapshots, and transaction restrictions before
committing it. Preserve the upstream order of allocation, datastore/channel
attaches, and referencing edits. Capture that order; do not assume that every
graph admits a strict topological order, because cycles are valid.

For a newly visible datastore, its attach snapshot includes its bound entry
point and channels according to upstream's rules. Avoid sending both the same
channel in the datastore snapshot and a redundant channel attach.
For an already visible datastore, a new channel uses a channel attach.
Preserve pending edits made after the captured attach snapshot.

On a malformed incoming group, keep the previous core, tree checkouts,
compressor, routes, and event state. Validate duplicate identities and echoed
attach contents through existing group/ack checks. Reconnect resubmits pending
allocation/attach/reference messages through the existing reconnect barrier;
it must not invent a fresh identity for an already accepted object.

## 6. Tree attachment, transactions, and branches

A detached tree needs document-context creation and an attach snapshot of its
local state, including identifiers and retained data. Generic
`channel.attach_snapshot` and `wire_op.encode_attach` cannot replace this with
a generic header blob or reconstruct only the visible root.

Use the document compressor for creation and editing across all trees. Keep
tree checkout and revertible identity stable through attachment where the
pinned probe demonstrates that behavior. Attaching a tree with its active
transaction is an explicit error; do not accept it because a skipped upstream
test describes an intended future capability.

Keep the current synchronous single-tree transaction scope. Handle insertion
can require document lifecycle messages, but that does not make target-DDS edits
part of the tree's atomic transaction. Capture successful, aborted, nested, and
failed transactions with new handle references. Record when each target becomes
visible, whether its attach survives an abort, and whether the referring commit
exists. Separate tree rollback from attachment side effects.

Apply the same rule to local branches: capture binding visibility before merge,
after merge, after discarded edits, and after branch disposal. A branch handle
is a view of a checkout in an existing channel; it does not become a new Fluid
channel on serialization. The current `tree_handle_of` encodes the channel
address even for a local checkout. Preserve that API: resolving its marker
opens the underlying document channel, not the local branch or its
unmerged content.

Undoing a handle insertion changes the referring tree. It must not detach or
delete an attached target. A peer's edits to that target survive local undo.
Runtime-local handles and subscriptions stay local; fresh load reconstructs
document state and routing without reviving old application stacks or branches.

### Summary ancestry safety exception

The pinned Fluid 3.1.0 edit manager can emit an unloadable summary after a
retained local inverse, a peer edit, and a later local acknowledgement that
advances the minimum. Its collaboration-window trunk omits the peer branch's
base, and its fresh loader fails with assertion `0xad7`.

Native summaries keep the contiguous trunk suffix from the earliest peer base
that would otherwise be omitted. This preserves loadable peer ancestry without
changing the authoritative retained history or restoring runtime-local inverses.
It is a narrow byte-parity exception for the defective upstream schedule.
Existing captured lifecycle checkpoint bytes remain the regression baseline.
Native snapshot replay receipts also cover only commits in the emitted trunk.

## 7. Persistence and GC

Use the existing hierarchical document summary and attach snapshot machinery.
Include the attributes and package metadata of newly attached channels and
datastores. Preserve existing datastore components, immutable aliases, protocol
metadata, compressor state, and prior-summary references.

Generate GC routes from the same supported reference traversal that the
runtime uses, with a distinct retention input. Current visible values are not
the complete retained tree state. Capture upstream routes before and after
reference removal, undo, retained repair/history, branch disposal, and
revertible disposal. Include the retained sources upstream reports and preserve
unreferenced timestamps that the existing profile retains.

Do not fix missing routes by declaring all secondary datastores roots or by
rooting every live local branch in persisted GC metadata. Root status and
retention routes must follow the captured upstream summary.
GC sweep and reclamation remain outside this slice.

Fresh writer/reader acceptance must check the actual stored tree and blob
bytes, root/package metadata, exact GC routes, referenced target paths,
compressor identities, and a subsequent write. Comparing a summary descriptor
with another descriptor from the same coordinator is insufficient.

## 8. Acceptance

Task 1 produces five generated cases:

| Case | Required observations |
| --- | --- |
| `handle-leaves` | Stored/view leaf kinds, path context, reference equality, object/map/array/root values, schema-aware and uncompressed codec forms, malformed/unsupported reference refusals |
| `live-channel-attachment` | Detached maps/trees, local edits, binding time, removed bindings, self/cyclic graphs, attach summaries and identifiers, errors during a target transaction |
| `cross-datastore-attachment` | Declared secondary factory, entry point and multiple channels, datastore vs channel attaches, mutual references, exact serialized paths and ordering |
| `handle-transaction-branch` | Successful/aborted/nested transactions, branch merge/disposal, binding visibility, commit/factory lifetime, undo without target-data rollback |
| `handle-retention` | Visible and retained references, disposal, actual summary bytes, GC routes and cross-client reload/continuation |

Run native semantic runners on both targets and upstream consumers of
native-produced codecs and attach/summary data. Add mutation tests that reject
missing raw attach messages, reordered dependencies, incorrect targets,
invented revisions, malformed stored snapshots, wrong GC routes, and a claimed
reload that never loaded its published bytes.

The real-service gate covers three writers and three readers
(`upstream`, `javascript`, `erlang`) across three checkpoints:
same-datastore channel attachment, cross-datastore attachment, and committed
handle undo/redo. Require all 27 writer/checkpoint/reader cells and continuing
writes. Include accepted-before-disconnect resubmission and bounded schedules
with seed `42` and `300` iterations.

The generated/service profile records the accepted JavaScript and Erlang
boundary: five native lifecycle cases, SharedMap and SharedTree targets, the
declared graph datastore, seven report sections, 27 reload cells, and 300
schedules at seed 42.
Record dated commands, case/cell counts, run identifiers, and zero-skip results.
The website/checklist remains a regression gate; it does not prove handle or
cross-datastore interoperability. M7 remains partial after this slice because
richer typed consumers, arbitrary factories and layouts, blobs, cross-container
graphs, GC sweep, production authentication, and disk recovery remain separate
work.
