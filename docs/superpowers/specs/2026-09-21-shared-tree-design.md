# Native SharedTree interoperability

**Date:** 2026-09-21
**Status:** Written specification approved on 2026-09-21.
**Deliverable:** A compatibility roadmap and an implementation plan for the first
end-to-end milestone. This work does not implement SharedTree.

## 1. Goal and decisions

Implement modern Fluid Framework SharedTree in native Gleam so that upstream
TypeScript clients, Watershed JavaScript clients, and Watershed BEAM clients can
edit the same document. SharedTree means `@fluidframework/tree`, not the deprecated
experimental tree packages.

The user approved an interoperability-first approach: establish the upstream
protocol and behavioral oracle, then build one complete tree-editing subset.
Later milestones expand that subset.

The user also removed a constraint from the initial proposal: Watershed has not
shipped, so existing Watershed documents need no compatibility support. Change
the document envelopes and storage format where required. Do not build a legacy
reader, migration framework, or parallel runtime just to preserve those formats.
Preserve the behavior of existing DDSes and their public APIs unless a task
identifies and obtains approval for a necessary API change.

### Global constraints

- Production SharedTree semantics must run in pure Gleam on JavaScript and BEAM.
- Upstream TypeScript packages are development/test dependencies, not a production tree engine.
- The initial upstream reference is `@fluidframework/tree` version `3.1.0`.
- The upstream source reference is `microsoft/FluidFramework` commit `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960` (`client_v3.1.0`).
- Existing Watershed document encodings require no backward compatibility or migration.
- Preserve existing DDS behavior while changing shared runtime and storage code.
- Scope the first milestone to an explicit container and schema profile; do not claim arbitrary Fluid document compatibility.
- Reject unsupported semantic formats and operations; do not approximate their meaning.
- SharedTree has a sequenced runtime in this project; peer-to-peer CRDT support is outside this design.
- Apply ASD-STE100 to Gleam comments and error strings, not to this design or other Markdown prose.
- Do not edit apm-managed files or `.code-map/`.

## 2. Evidence from the current implementation

Repository baseline: `9379499` (`chore: pin trellis version`).

| Current component | Reuse or required change |
| --- | --- |
| `src/watershed/channel.gleam` | Extend the closed sums for channel kinds, initialization, state, operations, events, and snapshots. Follow dispatch exhaustiveness, then check the non-type-driven codecs. |
| `src/watershed/runtime_core.gleam` | Reuse pure sequencing and bootstrap discipline. Extend document state for Fluid routing, ID allocation, and tree history requirements. |
| `src/watershed/runtime.gleam`, `runtime_beam.gleam` | Keep target-specific I/O and delivery outside the kernel. Wire both implementations in the same milestone. |
| `src/watershed/transport_ffi.mjs`, `transport_js.gleam` | The current JS transport uses Phoenix Channels. The service preflight must establish how an upstream Fluid driver reaches the same document; matching operation names does not establish socket-protocol compatibility. |
| `src/watershed/wire/op.gleam` | Replace the project-specific direct channel envelopes where Fluid container/datastore/channel routing requires a different format. Its existing comments disclaim a compatibility contract. |
| `src/watershed/wire/summary_blob.gleam` | Replace the version-4 Watershed-only snapshot representation where it cannot represent Fluid summaries. |
| `src/watershed/git_storage.gleam` | Extend beyond one `header` JSON blob to the required hierarchy of protocol, container, datastore, and DDS summary trees and blobs. |
| `src/watershed/sequence_kernel.gleam` | Reuse the local/sequenced/pending-state design experience, not `lattice_sequence` as a substitute for SharedTree changesets. |
| `src/watershed.gleam`, `src/watershed_beam.gleam`, `src/watershed/schema.gleam` | Add tree handles, schema-aware operations, reads, and subscriptions using the established facade conventions. Existing typed-map schemas do not implement SharedTree stored/view schemas. |
| `test/watershed/map_kernel_corpus_test.gleam`, `test/fixtures/corpus/` | Reuse the cross-language behavioral-corpus approach. Add wire and persistence fixtures, which the SharedMap corpus does not establish. |
| `test/watershed/fuzz/`, `src/watershed/sluice/core.gleam` | Reuse deterministic schedules, seed controls, and failure reproduction where their contracts fit tree operations. |

Connecting to a Fluid-compatible sequencing service proves transport
compatibility. It does not prove compatibility with a Fluid container's
operations or persisted SharedTree state.

## 3. Chosen approach

Build vertically, with protocol evidence before algorithm implementation:

1. Run the pinned upstream implementation with the declared profile.
2. Capture operations, summaries, ID allocation, and observable behavior.
3. Implement the corresponding pure Gleam representations and algorithms.
4. Integrate those algorithms into the document runtime on both targets.
5. Run mixed-client editing and cross-writer reload scenarios.

A core-first port would defer discovery of container-format problems. A full
Fluid runtime port would delay useful tree editing behind unrelated features.
The chosen approach implements the container functionality the declared profile
requires and makes unsupported capabilities explicit.

Do not translate the upstream directory structure file for file. Use persistent
Gleam data structures and focused modules. Preserve upstream edit semantics,
identity, and encodings even where the internal representation differs.

## 4. First milestone: the supported profile

### Container

Use an upstream-created container with a fixed, documented datastore/channel
layout containing one SharedTree. Include and implement any bootstrap DDS that
the selected upstream container construction actually creates. Do not assume
that naming a tree as an initial object removes its enclosing runtime state.

For the first service profile, use a real upstream SharedMap bootstrap channel
with a `"tree"` handle entry. Watershed's `root(document)` API assumes a map;
resolve that map through the container registry rather than inserting a phantom
`"root"` map while loading a tree-only document. Handle serialization must support
the profile's datastore/channel paths. These bootstrap handles are distinct
from the deferred feature of handle-valued leaves inside the SharedTree schema.

The profile records the container construction, package versions, channel
attributes, datastore addresses and aliases, schema identifiers, and runtime
options. Commit the oracle package lockfile and generated profile manifest.
Record protocol/schema version metadata separately from npm package versions.

Choose ordinary supported upstream options. Disable optional compression,
chunking, or other container features only through supported configuration, and
record each restriction in the profile. Grouped or batched messages that remain
possible under that configuration are part of the milestone.

Use a real Fluid-compatible service for the acceptance run. Begin with an
upstream-only preflight against the repository's Floodgate development service.
Use an upstream reference service as a control if that preflight fails. A
service or `spillway` limitation becomes an explicit prerequisite with a
reproduction; do not change the acceptance test to a mock to hide it.

The milestone requires an actual successful service configuration before it can
pass. It does not claim support for every Fluid service or hosted relay.

### Tree schema and edits

Support fixed stored schemas containing:

- Nested object nodes with stable, namespace-qualified schema identifiers.
- String, finite number, boolean, and null leaf values.
- Required fields and optional fields, with absence distinct from null.
- A declared root field and the cardinality required by the upstream profile.

Support assigning a leaf, replacing a nested object, setting an optional field,
and clearing an optional field. Resolve local path-based convenience calls to
the relevant tree identity before constructing a changeset. A JSON path is not
an adequate operation identity under concurrent replacement or removal.

The fixture application declares at least a root object with two independent
scalar fields, an optional field, and a nested object with two scalar fields.
That layout permits independent edits, conflicting edits, and parent/child
conflicts without adding arrays to the first milestone.

Honor the pinned upstream behavior for operations on removed objects. Retain
detached content and associated identity/history for as long as the supported
collaboration behavior requires it. Do not implement nested object editing as
whole-document last-writer-wins JSON replacement.

### Lifecycle

Support optimistic local edits, remote delivery, acknowledgements, ordered
catch-up, and reconnect with in-memory pending edits. A new client must start
from a summary and replay the subsequent operation tail.

Both native targets must load upstream-written summaries. Each native target
must also publish a summary that a fresh upstream client can load and continue
editing. Reading an exported JSON value does not meet this requirement.

Native creation of a new Fluid container and crash recovery of unsent edits
from local disk are later milestones. Reconnect in this milestone keeps the
current process's pending state.

**Pulled-forward M7 slice:** After Task 15, native container creation is available
on JavaScript and BEAM through `create_tree_container`. It publishes a complete
initial summary to pinned Floodgate and returns a server-assigned ID for the
existing token/connect flow. The layout stays fixed at alias `root` -> `A`,
map `/A/root`, and tree `/A/_C`; callers supply a checked schema and initial root
within the existing subset. This does not include live channel attachment,
broader layouts, or crash recovery. See `examples/shared_tree_cli` and the
`shared-tree-create-interop` gate. Task 16's permanent gates and profile
documentation are wired, including creation coverage. Its broad regression
closure remains blocked by Hex API rate limits, and hosted CI has not yet run.
The M1 release checklist remains open.

### Deferred public features

Defer arrays and moves, dynamic map nodes, schema evolution, Fluid-handle leaf
values, user-facing transactions, undo/redo, branching, native container
creation beyond the fixed-layout operation above, and optimized incremental
summary writing.

These API deferrals do not remove internal protocol requirements. Implement
composition, inversion, rebasing, detached content, and batch processing when
the supported edits require them. Support the wire forms reachable through the
declared upstream operations. Reject a peer's use of an excluded semantic
feature instead of corrupting the document.

## 5. Architecture and responsibilities

### Fluid document layer

The document layer owns container/datastore/channel routing, message-batch
boundaries, runtime system operations, and document-level summary metadata.
ID compression belongs to document state, not to a connection-local string hash
or a tree-only allocator.

Process ID allocation in the same sequenced order as its dependent changes.
Keep compressor session IDs distinct from transport client IDs. Normalize
session-space and operation-space IDs at their defined boundaries. Preserve the
compressor state required by summaries and reconnect.

Carry the complete sequencing metadata the tree edit manager requires, including
reference and minimum sequence numbers and ordering within a grouped message.
Do not assume that one tree commit always corresponds to one outer server
message.

Update the existing runtime rather than adding a second complete runtime for
old document formats. Keep Fluid-specific decoding out of individual application
examples and out of the tree's pure editing algorithms.

### Pure tree layer

Separate these responsibilities without designing a general plugin framework:

| Responsibility | Required state or behavior |
| --- | --- |
| Schema | Stored definitions, field cardinality, allowed node types, and compatibility checks for the supported view. |
| Forest | Attached and detached content, node references, field traversal, and applying tree deltas. |
| Changes | Required/optional field changes, nested modular changes, IDs, revision metadata, composition, inversion, and rebasing. |
| Edit history | Sequenced history, local pending commits, peer/reference context, acknowledgements, resubmission, and collaboration-window retention. |
| Codecs | Versioned schema, content, changeset, history, and detached-field encodings. |
| Kernel adapter | Local edits, remote application, acknowledgement, rollback, snapshots, and events in Watershed's channel contract. |

Keep the stored schema distinct from an application's desired view schema.
Although the first milestone forbids schema upgrades, it must recognize an
incompatible stored schema and report that condition before exposing a writable
view.

Start with straightforward persistent structures. Optimize only after recording
correctness and performance results. Simplicity does not permit dropping
detached edits or relevant history.

### Public interfaces

Expose a tree handle on both facades, explicit schema-aware reads and edits, and
subscriptions. Return typed errors from the tree layer; adapt them at existing
facade boundaries using repository conventions.

Do not promise TypeScript-style proxy objects in Gleam. Typed record builders,
generated schema bindings, and fine-grained application adapters can follow once
the native semantics work. The first API must still validate the stored schema
and each local edit.

Tree channels remain unsupported by the peer-to-peer runtime. Exhaustive matches
in CRDT dispatch must reject that use, rather than assign tree state an unrelated
merge implementation.

## 6. Errors and persistence

An invalid local edit returns an error without changing the visible tree,
pending queue, compressor allocation state, emitted events, or outbound messages.
Validate before allocating commit IDs, or restore the candidate state on failure.

Unsupported versions, invalid references, malformed ID ranges, incompatible
schemas, and corrupt summaries report their location and relevant version or
identity. Stop the affected document before exposing partially applied state.
Keep the existing recoverable transport-error path separate from semantic
corruption.

Follow upstream tolerance rules for harmless extra envelope properties. Rejecting
unsupported semantics does not justify a stricter parser than the declared
upstream format.

A summary describes one consistent sequenced point. It excludes unacknowledged
local edits while retaining the sequenced history and detached data necessary
for subsequent changes. Include the schema, forest, edit-manager state,
detached-field indexes, ID compressor, and enclosing runtime metadata required
by the pinned profile.

The reader must resolve summary trees, blobs, and references that the upstream
profile emits. The native writer may produce full summaries before it supports
incremental output. Do not copy stale container or protocol metadata into a new
summary merely because the tree content changed.

Keep the existing distinction between the sequence point represented by a
summary and the later sequence point of its publication. Replay the intervening
tail without gaps or duplicate application.

## 7. Acceptance and evidence

Maintain four separate claims:

| Claim | Required evidence |
| --- | --- |
| Behavioral parity | Matching upstream observations for a specified edit schedule. |
| Codec interoperability | Native output consumed by upstream and upstream output consumed by native code. Self-round-trip tests alone are insufficient. |
| Persistence interoperability | Fresh clients of all three implementations load summaries from each writer and continue editing. |
| Service interoperability | Mixed clients complete the scenarios through a real service, not only an in-memory sequencer. |

The first milestone's mandatory scenario matrix includes:

1. Independent edits to separate fields and nested fields.
2. Concurrent writes to the same field in both sequencing orders.
3. Optional set versus clear, repeated clear, and null versus absence.
4. Parent replacement versus a concurrent child edit in both orders.
5. An edit to retained removed content followed by the relevant upstream
   reconciliation and summary/reload behavior.
6. Several local pending commits with remote commits delivered between them.
7. Reconnect before acknowledgement, including the case where the server
   accepted a commit before the connection failed.
8. Summary-plus-tail bootstrap while other clients continue editing.
9. Upstream-to-native and native-to-upstream summary loading, followed by writes.
10. ID ranges from multiple sessions, eager/final IDs, reconnect, and restoration.
11. Batched messages, duplicates, out-of-order transport delivery, and gap repair.
12. Unsupported schema/format and malformed-input refusal without partial state.
13. JS/BEAM equivalence for Unicode keys and strings, finite numeric values, and
    safe integer boundaries used by the wire format.

Record observations at intermediate checkpoints, not only at final convergence.
Separate visible-value equality from identity, retained state, and event checks.
Preserve wire representation in fixtures; normalize only nondeterministic
identifiers for which the oracle records an explicit mapping.

Use deterministic regression cases and seeded interleaving tests. Reuse the
existing test infrastructure where it fits. Convergence among native clients
does not establish agreement with upstream.

Do not let a required interoperability job pass after skipping its service,
upstream dependencies, BEAM runner, or corpus. The implementation plan must name
the commands and required outputs for each gate.

## 8. Roadmap

| Milestone | Deliverable and exit condition |
| --- | --- |
| M0: protocol contract | A pinned upstream harness, supported-profile manifest, real-service preflight, and generated behavioral/wire/summary corpus. Record the codec dependency graph and runtime requirements before native implementation. |
| M1: object-tree interoperability | The complete first milestone in sections 4-7, on both targets, with cross-writer reload and mixed-client acceptance. |
| M2: dynamic maps | Map-node schema and editing semantics, key iteration, concurrent set/delete, and interoperability fixtures. |
| M3: arrays and moves | Sequence-field changesets, insert/remove/move, moves between compatible arrays, identity retention, and edit/delete/move races. Reuse no existing sequence algorithm without proving upstream equivalence. |
| M4: schema evolution | Stored/view compatibility, supported schema changes, mixed-version clients, and concurrent schema/data edit handling. |
| M5: transactions and undo/redo | Public transaction boundaries and constraints, abort semantics, revertible lifetime, redo, and remote edits during undo. |
| M6: branching | Local fork/rebase/merge first. Treat experimental shared branches as a separate profile/version decision, not a prerequisite for ordinary SharedTree. |
| M7: application and container lifecycle | Native document creation, broader declared container layouts, Fluid handles, richer typed APIs, Lustre bindings/examples, and crash-recoverable pending state. Split these into individual plans when scheduled. |
| M8: scale and supported versions | Measured forest/history performance, safe reclamation, incremental summary writing, additional upstream versions, and automated compatibility regression runs. |

M0 precedes M1. Each later milestone requires M1 and its own approved design and
plan. Map/sequence/schema development can proceed independently only after
agreeing changeset and codec interfaces; a sequence-field rebaser is not a
prerequisite for the first object-only schema.

### Parallel implementation

With the M0 contract, IDs, fixed schemas, and forest complete, the remaining M1
work can use three lanes: tree semantics, container-protocol foundations, and
summary/storage foundations. Agree their interfaces and file ownership before
starting concurrent work.

Keep field algebra, modular changes, edit history, and the tree codecs/kernel
in dependency order within the semantics lane. The container lane can develop
envelope decoding, routing, batches, and handle resolution without interpreting
tree changesets. The storage lane can develop lossless tree/blob I/O and summary
reference resolution without constructing a complete document snapshot.
Neither foundation lane alone proves native runtime or persistence
interoperability.

After the three lanes deliver their tested boundaries, one integration owner
completes container dispatch and both runtimes, then compatible document
summaries, facades/reconnect, mixed-client acceptance, and permanent gates.
Keep shared channel/runtime/facade edits coordinated; the parallel split does
not relax sequencing, atomicity, or cross-writer requirements. The
[implementation plan](../plans/2026-09-21-shared-tree.md#parallel-workstreams-and-integration)
defines the task slices, file ownership, and integration gates.

After M1 and interface agreement, maps and array/sequence algorithms are
candidates for parallel development, as are native container creation and
stable-facade consumers such as Lustre bindings. Coordinate schema evolution
with supported field kinds. Undo/redo, branching, crash recovery, and
reclamation share history/runtime state and need coordinated ownership rather
than independent edits to those paths. The separate-design and interoperability
requirements still apply to these later milestones.

## 9. Risk controls and stop conditions

**Protocol scope:** A successful raw tree corpus does not excuse a failing
container/service test. Stop at M0 if no real-service profile works; report the
external dependency and keep the native port blocked.

**Version scope:** Pin the complete oracle dependency graph. Do not label the
result compatible with all Fluid 2.x/3.x releases. Expand support through another
version profile and its corpus.

**Algorithm scope:** Same-field last-writer-wins behavior does not make the
subsystem a map. Parent/child conflicts, detached edits, history, and serialized
identity are mandatory even in the restricted milestone.

**Runtime scope:** Container batches, compressor allocation, and minimum sequence
numbers may require changes in `spillway`. Use an explicit dependency change and
pin; do not invent missing metadata or infer it from unrelated counters.

**Unbounded work:** No calendar estimate follows from the old repository
complexity rating. Size the implementation after M0 identifies the actual
reachable formats. If M0 invalidates the proposed module contracts, revise the
M1 plan before proceeding.

## 10. Source references

All source links below use the selected release commit. Some upstream READMEs
warn that they are stale; executable codecs and their tests take precedence.

- [SharedTree package and support-level guidance](https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/dds/tree/README.md)
- [Container message kinds](https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/runtime/container-runtime/src/messageTypes.ts)
- [ID compressor](https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/runtime/id-compressor/README.md)
- [SharedTree message codec versions](https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/dds/tree/src/shared-tree-core/messageCodecs.ts)
- [SharedTree message encoding and ID context](https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/dds/tree/src/shared-tree-core/messageCodecV1ToV4.ts)
- [SharedTree summary structure](https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/dds/tree/src/shared-tree-core/summaryTypes.ts)
- [Object edit merge semantics](https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/dds/tree/docs/user-facing/object-merge-semantics.md)
- [Required and optional field implementation](https://github.com/microsoft/FluidFramework/tree/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/dds/tree/src/feature-libraries/optional-field)
- [Modular changesets](https://github.com/microsoft/FluidFramework/tree/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/dds/tree/src/feature-libraries/modular-schema)
- [Public SharedTree documentation](https://fluidframework.com/docs/data-structures/tree)
- [Earlier Watershed complexity assessment](../../plans/2026-07-03-dds-porting-complexity.md)

## 11. Specification review

The implementation plan must account for the user-approved scope, removal of
legacy-format compatibility, both native targets, the restricted profile, and
the four independent acceptance claims. M0 resolves format and service details
through executable evidence; it must not silently expand or reduce M1.

No production code changes are part of this planning deliverable.
