# SharedTree interoperability oracle

This development-only package runs actual Fluid SharedTree code. It is not a
production dependency. The runtime gate tests DDS-level native outbound and
replay. The summary gate checks fresh full-hierarchy artifacts on both native
targets and, in its focused service mode, actual native publication and
continuation by fresh clients.

The public collaboration test uses an in-memory service. The source capture uses
upstream's deterministic DDS test runtimes. Container fixtures use complete
upstream containers on the local upstream service, with the same runtime
configuration as the separately verified real Floodgate preflight.

## Reference

| Item | Pin |
| --- | --- |
| `fluid-framework`, `@fluidframework/tree`, `@fluidframework/local-driver` | `3.1.0` |
| Other direct `@fluidframework/*` service dependencies | `3.1.0` |
| Source tag | `client_v3.1.0` |
| Source commit | `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960` |
| Source package manager | `pnpm@11.15.1`, from the pinned manifest |
| Source Node requirement | `>=22.22.2` |
| Floodgate source commit | `0eb493fc46d1bb9baf1151a6ccdde93544e057e7` |

The release uses Node-only test tooling. Its dependencies and build outputs stay
under the ignored `.reference/` directory. The npm lockfile covers this package's
published dependencies; the pinned upstream lockfile covers its source build.

## Run

From the Watershed repository root:

```sh
npm --prefix tools/shared-tree-oracle ci
npm --prefix tools/shared-tree-oracle test
npm --prefix tools/shared-tree-oracle run source:prepare
npm --prefix tools/shared-tree-oracle run source:verify
npm --prefix tools/shared-tree-oracle run source:capture
npm --prefix tools/shared-tree-oracle run codec:interop
npm --prefix tools/shared-tree-oracle run runtime:interop
npm --prefix tools/shared-tree-oracle run summary:interop
npm --prefix tools/shared-tree-oracle run summary:interop -- --service floodgate --local
```

The default summary gate exports all four input-only `summary-writer-matrix`
persistence states on JavaScript and BEAM. Each exporter decodes the captured
hierarchy, replays the supplied sequenced tail, captures a new summary through
the production core, re-encodes it, and checks the declared continuation edit,
restored root, and sequence.
The coordinator checks the pinned reference, complete scenario IDs, both
targets, hierarchy shape, and snapshot/publication positions. It uses owned
temporary artifacts and rejects missing, stale, or incomplete output.
For each target, it also creates ordinary upstream documents directly from
fresh native retained-history snapshots (including detached branches and a
non-tree tail). The upstream reader must restore the tree, author a new edit,
and have an independent upstream peer observe it. A separate pinned upstream
summary with a 9 KiB split SharedMap value must load and re-encode on both
native targets.

The optional Floodgate mode requires the same local checkout and tools as
`preflight` below. It creates a fresh upstream document, then tests all nine
upstream/JavaScript/BEAM writer-to-reader combinations against published
versions. Each reader opens an ordinary connection, edits, and has a separate
upstream peer observe the change. Native writers publish their own hierarchies
over the existing transport and HTTP storage; the coordinator does not upload
on their behalf. It checks the published commit, protocol snapshot sequence,
and matching acknowledgement separately. This fixed-profile test is not the
wider service scheduling matrix or arbitrary-container compatibility.
It also sets a zero-jitter automatic policy on an ordinarily loaded BEAM tree:
an acknowledged edit must not publish a checkpoint, while explicit BEAM
publication in the nine-cell matrix remains available.

The capture is written to `.output/source/source-smoke.json`. To choose an output
directory, pass an absolute path:

```sh
npm --prefix tools/shared-tree-oracle run source:capture -- /tmp/watershed-tree-capture
```

`source:prepare` installs only the upstream tree's dependency closure and the
workspace root, with `--frozen-lockfile`. It invokes the exact pnpm version
through `npm exec`; it does not depend on the host's Corepack-selected version.
Browser downloads are disabled because this oracle does not run a browser.

The source runner builds upstream's `compile` task and ESM tests, then runs only
the injected oracle with Mocha. It supplies upstream's
`allow-ff-test-exports` Node condition. It does not run the release's unrelated
lint, API-report, benchmark, or snapshot suites.

### Checkout ownership

Preparation checks the exact source commit and package versions. It refuses
changed tracked files, unrelated untracked files, a symbolic-link checkout, and
an injected test whose contents differ from its committed oracle source.

Only `packages/dds/tree/src/test/watershedOracle.spec.ts`,
`watershedAlgebra.spec.ts`, `watershedForest.spec.ts`, and
`watershedModular.spec.ts`, `watershedHistory.spec.ts`, and
`watershedCodecs.spec.ts` in that same directory
are injected. They must match `upstream-oracle.spec.ts`,
`upstream-algebra.spec.ts`, `upstream-forest.spec.ts`, and
`upstream-modular.spec.ts`, `upstream-history.spec.ts`, and
`upstream-codecs.spec.ts`, respectively. If you
intentionally edit an oracle after preparing a checkout, review the old injected
copy and remove that one file before preparing again. Do not discard other
reference changes to make verification pass. Avoid code-map queries inside the
reference checkout: their generated cache is an unrelated untracked file.

The checkout excludes upstream's generated
`packages/dds/tree/src/test/snapshots/output/` directory. The release contains
snapshot filenames that differ only by capitalization, which collide on the
default macOS filesystem. No upstream source or algorithm is excluded or
modified.

### Failure behavior

Package mismatches, source changes, build failures, a failed source test, zero
tests, missing output, and incomplete captures all fail the command. A capture
is generated in an owned temporary directory and published only after validation
and another source-integrity check. Failure leaves any earlier capture intact;
an earlier file is not evidence that the failed invocation succeeded.

The Node tests cover these guards, including a producer subprocess that exits
nonzero and a producer that writes no case.

## Source smoke format

The smoke case initializes a number root, queues concurrent replacements from
two clients, records their pending values, and delivers the actual upstream
messages in order. It captures the settled values, full DDS summary, compressor
bytes, compressor format header, and selected codec dependency graph.

At the pinned commit, the explicit `minVersionForCollab` of `2.117.0` produces:

| Codec | Version |
| --- | --- |
| Message and EditManager | 7 |
| SharedTreeChange and ModularChange | 5 |
| Forest payload, Schema, DetachedFieldIndex, FieldBatch | 2 |
| Forest index metadata wrapper | 3 |
| Value and Optional fields | 2 |
| Sequence fields | 3 |
| Forbidden and Identifier fields | 1 |
| ID compressor serialization | 2 |

These values come from the captured codec graph and compressor header, not from
the npm major version. The raw message list includes ID allocations. The summary
is a DDS summary, not a complete Fluid container summary.

The object schema in `schema.mjs` is the planned M1 schema. Its tree-only
`rootStore` is an oracle health check. The service profile must instead create a
real SharedMap bootstrap channel with a `"tree"` handle. A passing smoke case
does not freeze that profile or satisfy the M0 exit gate.

## Real-service preflight

Install Watershed's root npm dependencies as well as this package's dependencies.
The native JavaScript probe uses the existing optional Phoenix peer dependency.
Gleam and Erlang must be on `PATH`; Docker is not required.

```sh
npm --prefix tools/shared-tree-oracle run preflight -- --service floodgate --local
```

The local runner verifies an owned Floodgate checkout at the pinned commit,
exports its Erlang shipment, and starts that shipment on a loopback port with a
random test credential and an isolated Shelf/DETS data directory. It checks
server health before connecting. It stops its own Erlang process and removes its
own data directory on completion. The Git bare-repository exception needed by
Gleam's Git dependency installer applies only to that build subprocess, not to
the user's Git configuration.

For an already running instance of the pinned server, omit `--local` and provide
`FLOODGATE_JWT_SECRET` and `FLOODGATE_REVISION`. `FLOODGATE_HTTP_URL` defaults to
`http://127.0.0.1:3000`; `FLOODGATE_SOCKET_URL` defaults to the same address, and
`FLOODGATE_TENANT_ID` defaults to `fluid`. The operator must ensure that a remote
instance actually runs the supplied revision. The current BEAM probe targets
the selected plain-HTTP development profile, not an HTTPS deployment.

The command must complete all of these operations:

1. Create and attach an upstream container with a real SharedMap root channel
   whose `"tree"` entry is a SharedTree handle.
2. Load a peer and exchange edits in both directions.
3. Use a dedicated upstream summarizer client to upload and publish a full
   summary; match the acknowledgement to the stored document head.
4. Read every sequenced message through the official delta-storage API, in
   sequence order, and fetch every blob of the published snapshot.
5. Close the original clients, reload the published state in a fresh client,
   and acknowledge another edit.
6. Join that same document over Phoenix using Watershed's JavaScript transport
   and its BEAM Aquamarine transport. Both use the existing Gleam connection
   decoder and must identify the exact published summary.

The native probes verify the transport and summary-discovery path only. They do
not load a tree into Watershed or claim native tree-edit interoperability.

Successful output contains `result.json`, `profile.json`, and `capture.json`
under `.output/service/`. `--output <absolute-directory>` selects another
directory. Failure names its stage, exits nonzero, and publishes no new success
result. Credentials and authorization headers are not part of these artifacts.
The committed profile is `test/fixtures/shared_tree/profile.json`.

### Observed profile requirements

The stock Routerlicious driver uses Socket.IO; both native targets use Phoenix
against the same Floodgate document and storage. Discovery and whole-summary
upload are disabled. RestLess is enabled. The delta URL must be
`/deltas/{tenantId}/{documentId}`: attach replaces the final URL segment with
the server-assigned document ID. The superficially similar
`/documents/{tenantId}/{documentId}/deltas` route breaks that rewrite.

Runtime ID compression and grouped batches are enabled. Wire compression is
disabled through its supported infinite threshold, which also prevents chunked
ops. JSON records that threshold as the string `"Infinity"`, not `null`.
Interactive clients disable automatic summarization; the dedicated summarizer
uses `disableHeuristics` and publishes on demand.

The actual summary contains runtime format 1, document schema 1, ID compressor
format 2, and GC metadata version 3. GC sweep is disabled, but GC metadata cannot
be omitted: Task 13 must preserve it. The profile records the observed full blob
paths, including protocol data, aliases, recent batches, datastore metadata,
bootstrap map, and tree indexes.

The pinned server logs warnings for some Socket.IO control packets and logs
`Failed to eval` during SIGTERM shutdown. These messages were observed even on
successful preflights; the command's stage assertions and exit status determine
the outcome.

## Conformance corpus

After installing and preparing the pinned source:

```sh
just shared-tree-oracle
just shared-tree-oracle-check
gleam test --target erlang -- --test-name-filter=shared_tree
gleam test --target javascript -- --test-name-filter=shared_tree
```

`generate` produces all 26 named cases under `test/fixtures/shared_tree/cases/`
and their manifest. `check` regenerates them in an owned temporary directory and
compares the complete file set and every byte without changing the fixtures.
Missing files, extra files, incomplete observations, and changed outputs fail.
Negative cases can print upstream `Failed Assertion` diagnostics; the enclosing
test must catch the specific refusal and verify its recorded outcome.
The real-service `profile.json` is independently generated by preflight; corpus
generation preserves it and checks its codec and compressor selection against
the source capture.

Source cases use upstream DDS runtimes, field algebra, forest application, and
ID compressors. Container cases use the real upstream loader, runtime, driver,
SharedMap bootstrap, and SharedTree. They include actual grouped envelopes,
pending-local-state strings, hierarchical summaries, original base64 blob bytes,
and sequenced history. The local service is not evidence of server compatibility;
that is the separate Floodgate preflight's job.

The isolated producer subprocesses use seeded entropy and a fixed `Date`. Only
the container producer freezes the performance clock, after imports finish:
upstream benchmark imports calibrate that clock and require it to advance.
Real timers and an external process timeout still bound container failures.
No identities are removed, renamed, or sorted. The preload refuses an unmarked
process and is never loaded by the real-service preflight.

All producers and validators finish before publication. Each complete case file
is replaced by rename, then the manifest is replaced last; the fixture directory
is never removed. This is not a transactional switch of the whole corpus. If
publication is interrupted, rerun generation and `check` before using it.

The Gleam reader validates manifest membership, canonical paths, pinned
identities, and nonempty observations on both targets. `assert_case` gives only
`input` to a runner and compares its complete result with `expected`, including
the first differing JSON path on failure. Necessary initial state and replay
bytes therefore live in `input`; `raw` preserves supporting evidence. Tasks 4
and 5 add the native `id-ranges` and `schema-validation` runners on both targets.
Task 6 adds the input-only `forest-delta` runner. The foundation wave adds
`field-compose-invert-rebase`, `modular-nested-algebra`,
`container-foundations`, and `summary-foundations`. Task 9 adds the input-only
`history-reconciliation` runner. Task 10 adds the input-only `tree-codecs`
and `tree-kernel` runners. The runtime fixture adds input-only
`bootstrap-map-handles` and `batched-commits` runners. All twelve cases are registered on both targets. The input-only `summary-tail`
semantic runner and fresh document-summary artifact gate now cover complete
document restoration and native capture; the separate service mode covers
published writer-to-reader persistence.

### Complete summary restoration inputs

`summary-writer-matrix.input.persistenceStates` adds four whole-container
snapshots with contiguous operation tails and explicit continuation edits.
The corresponding upstream observations are separate in
`expected.persistenceObservations`; a native runner must not read them.

| State | What the snapshot exercises |
| --- | --- |
| `initial` | Empty tree history at a nonzero document sequence. |
| `concurrent-detached` | Concurrent parent replacement and child editing, retained detached fields, trunk commits, and peer branch bases. |
| `after-peer-leave` | Changed protocol membership, grouped edits, a bootstrap-map handle, and a later summary number. |
| `after-nontree-tail` | Document progress beyond the tree's retention watermark, after sequenced bootstrap-map edits. |

Each snapshot is published by upstream and loaded by a fresh upstream reader.
That reader authors a continuation, and another client must observe it. These
are restoration inputs, not evidence of native document loading or publication.
The existing `tree-codecs` inputs additionally cover retained initialization
schema changes and a peer branch with nonempty commits.

The last state matters: `SharedTreeCore.processMessages` advances the tree edit
manager's minimum sequence only when it processes tree envelopes. A summary can
therefore contain trunk commits older than `.protocol/attributes`'s minimum
sequence. A native loader must not reject or prematurely evict that history.
The document snapshot point is also not the sequence of its last tree commit.

The production conversion must follow these pinned-source contracts:

| State | Source and ownership rule |
| --- | --- |
| Tree history | `shared-tree-core/editManager.ts`: restore the trunk first, then each peer branch from its recorded base. `"root"` denotes the new sentinel, not a UUID. Summary generation trims according to the tree's own retention state. |
| Detached index | `core/tree/detachedFieldIndex.ts` and `util/idAllocator.ts`: `maxId` is the last allocated root ID; the next allocation is `maxId + 1`, even when no detached entries remain. |
| Loaded repair lifetime | `shared-tree/treeCheckout.ts`, `load()`: associate loaded detached roots with the restored trunk tip so later trimming can reclaim them. Leaving every latest-relevant revision absent changes retention. |
| Compressor | `containerRuntime.ts`, `addContainerStateToSummary`: serialize without local state. The document owns it; individual tree snapshots do not. |
| Runtime metadata | `containerRuntime.ts`, `addMetadataToSummary`: preserve creation metadata, advance the summary-attempt number, and derive the last processed message and document schema. Explicit schema control uses `message: {sequenceNumber: -1}` plus `lastMessage`. |
| Batch identities | `opLifecycle/duplicateBatchDetector.ts`: persist `[sequenceNumber, batchId]` pairs. On an inbound batch, remove entries strictly below its minimum sequence, then detect duplicates using the effective batch ID. |
| Protocol | `container-loader/src/protocol.ts`: restore full quorum members, proposals, values, and snapshot attributes. A hashed membership list alone cannot reproduce this state. |
| Routes and GC | Container aliases, datastore/channel metadata, and `gc/__gc_root` describe the graph at capture. Preserve immutable configuration, but regenerate changed routes and retain relevant unreferenced timestamps; disabling sweep does not permit omitting GC. |

Tree source paths above are relative to `packages/dds/tree/src/`; container
runtime paths are relative to `packages/runtime/container-runtime/src/`. All
references use the pinned source commit, not the currently released package.

### Native runtime interoperability

`npm run runtime:interop` creates fresh pinned upstream containers and gives
each native target the real initial snapshot, server delivery prefix, and its
own connected transport identity. The native core emits a SharedMap handle set,
a required-field edit, an optional set and clear, and a grouped three-edit
batch with ID allocation. The upstream container consumes each outbound
message unchanged at its own checkpoint, resolves the handle, and authors a
continuation edit. The native core then replays the actual server messages,
including its own echoes and the peer's allocation, and checks the final root,
pending count, outer identities, and per-tree sequence positions. A second
upstream container loads the native SharedMap header through its normal DDS
loader and checks integer-key insertion order and handle resolution. The
coordinator rejects missing, stale, incomplete, or divergent output and
removes only its own temporary directory. This is a local-driver DDS/runtime
test, not native publication of a full Fluid document summary.

### Native codec interoperability

`npm run codec:interop` runs the native exporter on Erlang and JavaScript, then
passes each fresh artifact to the pinned source consumer. The consumer decodes
schema and FieldBatch output, applies native-authored messages, loads native
DDS tree-index summaries, and makes another accepted upstream edit. The
coordinator requires all 14 scenario IDs, compares both targets with fixed
semantic expectations, rejects empty or stale artifacts, and removes its owned
temporary output.

The FieldBatch writer uses four fixed V2 shapes: a generic node, a field array,
a polymorphic selector, and a constant-null node. Null is stored in the shape,
not the data stream, because the pinned decoder treats a literal data-stream
null as an out-of-bounds value. This is a schema-independent writer, not a
compression optimizer.

This gate proves codec-level interoperability for the selected profile. It does
not add the task 10b kernel, publish complete Fluid documents, run the service,
or satisfy tasks 11-15.

### Field algebra and foundation scope

The expanded `modular-nested-algebra` case preserves its six original encoded
observations and adds input-only structural operations and forest schedules.
It records aliases, node parents, revision allocation, full deltas, and retained
content for nested edits, both parent/child orders, composition, rollback/undo,
revision replacement, pruning, and repair content. Its 60 observations also
cover optional-root set/clear, null versus absence, both nested composition
orders, a delayed child edit after two parent replacements, a child named
`rootFieldKey`, and nested detached-delta traversal. Separate real compressor
sessions supply revision IDs whose numeric order differs from their UUID order;
the native boundary must use that explicit context. The late modular
capture runs after the forest capture without registering another Mocha test,
which would change the deterministic entropy consumed by earlier captures.

The original synthetic alias fixture exposes one pinned-upstream refusal:
revision replacement leaves a dangling child reference, and delta conversion
throws `0x9ca`. The oracle checks that exact failure; it does not turn arbitrary
exceptions into expected results. Real composed nested edits are separate
positive cases. Both native targets replay the complete expanded case from
`input` alone. The pure schedules cover nested editing and algebra, not history,
reloads, or runtime interoperability. The lifecycle cases remain unregistered.

### History reconciliation scope

`history-reconciliation` records 16 schedules from the pinned `EditManager`.
They cover local acknowledgement, stale peer branches, multiple pending edits,
same-field and parent/child conflicts in both orders, same-sequence inner
positions, non-tree sequence gaps, minimum-sequence trimming, settled snapshot
restore, accepted-before-ack replay, never-submitted work, detached repair
content, and compressed revision order that differs from UUID order.

The native runner builds every observation from `input`. Reconciliation uses an
explicit state-threaded rollback allocator; each allocation carries the stable
revision and the complete checked identity order in force at that point.
Snapshots reject pending local commits and restore only validated settled
history. Resubmission is pure: it preserves pending revisions, adds repair
content per commit, and rejects duplicate, missing, or extraneous repair data.
This scope does not add production history codecs, a document kernel, runtime
facades, transport behavior, or summary publication.

`tree/change` supplies checked modular state, local edits, balanced composition,
rollback/undo inversion, tagged rebasing, revision replacement, pruning, repair
content, and forest deltas. `from_data` and `edit` require an `IdentityOrder`
built from explicit stable-ID/ordering-key pairs. Changesets retain that context;
composition and rebasing reject incompatible mappings. Temporal revision
metadata still has its separate role in rollback and inverse allocation.
Before using a newly allocated inverse or replacement revision, reconstruct
the checked change with `from_data(to_data(change), extended_order)`.

The test adapter checks the original V5 inputs against the full structural
inputs, which preserve identities lost by wire encoding. Its V5/V2 encoding is
limited to the original fixture forms and is not a production codec. Mutations
exercise operation operands, repair content, aliases, detached-only edits, and
revision ordering without reading `raw` or expected observations. Task 10a now
owns the production codec modules; task 10b still owns the pure kernel.

The expanded `field-compose-invert-rebase` case contains 24 ordered
observations. It covers pairwise composition, rollback and undo inversion,
rebasing with child callbacks, field deltas, and revision replacement. The
native adapter executes the supplied operation arguments and compares register
identities, callback traces, and allocator results. Its V2 decoding is test-only;
the task 10a production codecs are separate.

`src/watershed/tree/optional_field.gleam` implements the shared required/optional
field algebra. Child callbacks return candidate state through typed results.
Composition retains first-seen source-revision groups for unmatched moves.
Native algebra-law tests also check retained node references through the real
forest, including rollback, undo, and atomic refusals.
The schema/forest boundary rejects a required field left empty. Simultaneous
register mappings remain valid algebra even though the forest rejects direct
transfers around an occupied rename cycle.

Two narrower cases follow the five original container captures, so their
additional operations do not change the earlier captures' deterministic IDs:

- `container-foundations` covers envelope structure, ordered batch metadata,
  allocation data, attach/alias messages, contextual handles, and bootstrap-map
  bytes. It uses pinned upstream runtime consumers for encoding evidence.
- `summary-foundations` covers snapshot paths and bytes, nested Git entries,
  binary content, prior-summary tree/blob handles, and reference refusals. It
  invokes the pinned `SummaryTreeUploadManager`.

The two runtime cases now have native replay comparisons and the local-driver
interop gate above. `summary-tail`, native document publication, and real-service
mixed-client acceptance remain separate work.

The sequenced runtime uses canonical datastore/channel paths and rejects the
old direct envelope. Document-only handle resolution requires absolute paths;
`bind_handle(document, source_handle, value)` supplies the source context for
relative markers. Independent P2P helpers retain their single-segment contract.

### Hierarchical storage foundations

`fluid_summary` materializes snapshot trees and resolves summary handles against
an explicit prior summary. Blob content stays in `BitArray`; a summary handle
names a prior-summary path, not a Git object ID.

`git_storage.fetch_hierarchy` accepts a published commit ID and reads its tree
and blobs. A missing commit is an error. `stage_hierarchy` validates a resolved
tree, writes blobs and nested trees, and returns the staged root tree ID. It
does not publish a document summary or create a commit. Failed uploads may leave
unreferenced immutable objects on the server.

Run the controlled HTTP probe from the repository root:

```sh
node smoke/shared_tree_storage.mjs
```

The probe exercises the real JavaScript and BEAM storage APIs against a local
Historian-shaped server. It fetches, stages, and refetches the complete captured
`summary-tail` snapshot, comparing every path, kind, and blob byte, alongside
binary, escaped-name, empty-tree, and failure probes. It also runs as part of
`just test` and does not require a running Floodgate instance. Existing
`fetch_summary` and `upload_summary` callers still use the single-header format;
Task 13 replaces that path after the runtime and tree codecs can form a complete
document summary.

### Forest delta source contract

The `forest-delta` case runs the pinned `ObjectForest`, anchor visitor,
`DetachedFieldIndex`, and `applyDelta` implementation directly. Its 16
input-only scenarios cover optional primitive roots, fixed Root/Point and
KeyProbe objects, replacement and retained anchors, detached ranges, ordered
renames, refreshers, destruction metadata, copy behavior, and refused missing or
occupied sources.

Each action produces one checkpoint. Accepted checkpoints contain the visible
root, named reference status and value, detached atom/root/revision/value data,
and the next detached-root ID. Rejected final actions contain
`accepted: false` and `state: null`; raw evidence keeps the upstream error and
readable post-failure forest/index state. Revision identities are normalized
through the real ID compressor to stable UUIDs. Object fields use UTF-8 byte
ordering.

The copy action rebuilds a forest from its actual roots and clones the detached
index. The native runner performs typed export/import under a fresh view ID and
compares all checkpoints on Erlang and JavaScript. This is an in-memory copy
check, not a summary codec test. The case does not claim atomic upstream failure,
public detached editing, simultaneous cyclic rename support, or SharedTree
document interoperability.

### Native persistent forest

`src/watershed/tree/forest.gleam` stores attached and detached nodes in persistent
Gleam data structures. Give `new` and `import_data` a fresh `StableId` for each
independent view or fork. The forest performs no random generation or compressor
allocation. A `NodeRef` belongs to the accepted state sequence of that view;
replacement changes identity, detachment preserves it, and destruction or a
different view makes the reference invalid.

The root uses `Option(TreeValue)`, including absent optional roots and explicit
null leaves. `read` distinguishes absent optional fields from invalid paths.
`validate_subtree` checks retained content without imposing document root types.

Native tree modules construct checked `Delta` values. The forest applies
builds, detach passes, ordered root transfers, attach passes, and destruction to
candidate state, then checks schema and ownership. Errors return no candidate.
Global changes can update an old detached child without changing its replacement.
Refreshers reconstruct missing content only when needed. Self-renames are no-ops;
occupied cyclic transfers and duplicate attachments are errors. These internal
operations do not provide an application API for editing removed objects.

`export_data` and `import_data` preserve detached atom identities, root IDs,
latest-relevant revisions, and the allocation watermark. They do not persist
local `NodeRef` values or read/write Fluid summary bytes. History-driven
collection and wire codecs remain later tasks. The original
`detached-child-edit` case still requires those later runtime components.

### Native ID compression

`src/watershed/fluid_ids.gleam` implements the document compressor in pure Gleam.
It distinguishes session UUIDs, stable UUIDs, session-space integers, and op-space
integers with opaque types. Callers receive a candidate state on success and a
typed error on invalid ranges, unknown IDs, UUID collisions, or corrupt persistence
data. No compressor operation mutates the input state.

The `id-ranges` adapter executes only `input` through that native API. Its
comparisons include creation ranges and exact serialized base64 strings, plus
numeric and UUID observations. The upstream producer supplies explicit restore
bytes and session IDs in the input. The added traces cover interleaved cluster
splits, extension of the last document cluster, eager IDs, pending IDs across
restoration, UUID carry across version/variant positions, and offsets above
`2^52`. Generator checks reject missing trace steps or restoration inputs.

The selected serialization format is version 2: little-endian float64 integer
fields and a 122-bit UUID payload without its fixed version/variant bits.
The native implementation uses four bounded integer limbs for that payload.
It rejects unsafe wire integers and UUID-space exhaustion on both targets.
Local generation stops before its next-range cursor would exceed the safe
integer domain.

`serialize(state, true)` includes local pending state; `serialize(state, false)`
writes sequenced state for a summary. `deserialize` requires the saved session
when restoring local state and a new session when loading a summary. Range
reservation size is transient and resets to 512 after restoration, matching
upstream. The document runtime will adopt this module in Task 11; Task 4 does
not yet enable native SharedTree editing.

### Native fixed-schema validation

`src/watershed/tree/schema.gleam` validates schema-v2 definitions and tree values
in pure Gleam. Stored schemas and desired view schemas have separate opaque
types. Both use the persisted schema format; the view API does not accept
JavaScript `TreeViewConfiguration` objects.

The supported definitions are objects, required (`Value`) and optional fields,
and the canonical string, finite-number, boolean, and null leaves. Array,
map, handle, identifier-field, and unknown semantic kinds return typed errors.
Malformed JSON or schema shapes, unsupported versions, incompatible schemas,
and invalid values have distinct error variants and location details.

Use `stored_from_string` and `view_from_string` for schema blobs. These entry
points check the original JSON for duplicate declarations, including names
written with different escape sequences. The `*_from_json` convenience APIs
cannot recover duplicate names a caller's JSON parser has discarded.

`can_view` checks the ordinary fixed view without upgrades or permissive
unknown-field options. It compares field cardinality and allowed-type sets
without relying on JSON member order. Unused extra definitions and persisted
metadata do not prevent viewing; differences in shared definitions still can.
The opaque schema retains the persisted data for later codec work.

`validate_root`, `validate_root_field`, `validate_field`, and `validate_subtree` check nested values
without allocating IDs or changing state. Pass `None` to validate absence and
`Some(NullValue)` for a present null leaf. Required clears, duplicate or unknown
object fields, wrong node types, and non-finite numbers fail. Finite doubles
are not limited to the compressor's safe-integer range. Validation accepts
negative zero; the later insertion layer must normalize it to positive zero
as upstream does.

The `schema-validation` fixture contains 31 checks from upstream schema
extraction, compatibility comparison, and field validation. Its native runner
receives only `input` and compares the complete ordered acceptance results.
Native tests check error variants and paths, corrupt data, duplicate names,
and JavaScript NaN/infinities outside the JSON fixture. The original
`schema-profile` summary remains unchanged and awaits the later forest/codec
tasks. Task 5 does not enable tree edits or summary loading.

### Compatibility inventory and implementation owners

The generated manifest records observed field kinds, codec versions, tree-index
metadata, document schema, and service summary paths. Index metadata versions
are distinct from the codecs of the blobs they describe: notably the forest's
index metadata is version 3 while its content codec is version 2.

| Surface | Evidence | Native plan tasks |
| --- | --- | --- |
| Session/op IDs, eager IDs, interleaved allocation, restoration, precision boundaries | `id-ranges`; allocation messages and compressor blobs throughout | 4, 11 |
| Fixed schema, required null, optional absence, Unicode keys and finite numbers | `schema-validation` (native), `schema-profile`, `null-and-absence`, `unicode-and-numbers`, `invalid-profile` | 5, 10 |
| Forest, detached roots, repair content, parent/child replacement | `forest-delta` (native), `parent-child-both-orders`, `detached-child-edit`, forest and detached-index summaries | 6, 13 |
| Value/Optional v2, register moves, simultaneous register swaps | `field-compose-invert-rebase`, `optional-set-clear`, conflicting writes | 7, 10 |
| Modular v5, generic nested fields, aliases, replacement revisions, builds/refreshers/pruning | `modular-nested-algebra` (native), `nested-independent` | 8, 10 |
| SharedTreeChange v5, Message/EditManager v7; pending revisions, stale peers and min-sequence | `history-reconciliation` (native); `multiple-pending`, `history-window`, both-order cases | 9, 10 |
| Real root map, `"tree"` handle, SharedMap op/header, hierarchical addresses | `bootstrap-map-handles` | 11, 12, 14 |
| Grouped runtime messages, inner positions, ID allocation, runtime document schema | `batched-commits`, full container history | 11, 12 |
| Accepted-before-ack and never-submitted reconnect states | `history-reconciliation` (native); `reconnect-before-ack` | 9, 11, 14 |
| Snapshot at S, data edit before publication at P, complete interval and later tail | `summary-tail` | 13 |
| Aliases, recent batches, datastore/channel metadata, protocol quorum and attributes, GC metadata v3 | Full container snapshots plus `profile.json` paths | 11, 13 |
| Upstream-written summary reload and further editing; native cells explicitly absent | `summary-writer-matrix` | 13, 15 |
| Strict corpus comparison and both-target reader | Manifest, generator guard tests, Gleam fixture tests | 16 |
| Stock-driver create/edit/summary/reload and both native Phoenix joins | Pinned real-service preflight | 12, 14, 15 |

`ModularEditBuilder.Generic` is reachable through nested edits even with arrays
excluded. Detached-register movement is also required independently of a public
move API. The dependency graph includes Sequence v3, Forbidden v1, and Identifier
v1; presence in that graph does not authorize user-facing arrays, maps, or
experimental shared branches. The fixed profile excludes those schemas, wire
compression/chunking, sweep, and schema evolution.

Two upstream behaviors matter for native error handling. Public edits through a
removed-node reference are refused; a peer edit authored while the node was
still attached can nevertheless update retained detached content and survive
reload. Invalid wire messages invalidate the public view. The oracle separately
observes internal forest, schema, history, and compressor state to distinguish
that fail-stop behavior from partially applying a malformed change.

The field algebra also maps child changes through a simultaneous register swap.
Directly applying the corresponding occupied two-way detached rename cycle to
the pinned forest visitor is refused (`0x7cf`). Both outcomes are recorded; the
oracle does not replace that refusal with a test-written scratch-register
algorithm.
