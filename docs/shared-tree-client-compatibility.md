# SharedTree client compatibility

Watershed JavaScript and BEAM clients can collaborate with a real Fluid
SharedTree client using the Routerlicious driver **within the profile below**.
That includes edits in both directions, concurrent edits, reconnect, native
creation, and summary/reload continuation. It does not mean that an arbitrary
Fluid application, schema, client setting, or package version will work.

This report inventories the pinned upstream client surface, including features
outside our existing fixture inventory. **Coverage means that a capability has
a disposition, not that it is implemented or demonstrated.** In particular,
an unassessed row is not a compatibility promise.

## Baseline and operating envelope

| Item | Audited baseline |
| --- | --- |
| Fluid packages | `3.1.0`, including `@fluidframework/tree`, `fluid-framework`, and `@fluidframework/routerlicious-driver` |
| Upstream source | [`c3c5bf0ecd313362e83fe8a02b7d39e7e0736960`][upstream] |
| Watershed compression implementation baseline | `75ecdceb` |
| Legacy profile | [`test/fixtures/shared_tree/profile.json`][profile], SHA-256 `29fe106785ec1705cd1ac4d45de8e88f9a6cc89487c3b7cd1df6ad65b318b1de` |
| Compression extension | [`compression-profile.json`][compression-profile], SHA-256 `1c14161270e64cae5ea429a5c3bf69dac0653624d7b0ad4ad4df4ddea026ce7c`; corpus SHA-256 `d03edfd3fb97e39cde8934e703b44033d07cf40ad81c9e96ba5bb3fd14cb228d` |
| Recorded compression evidence | Run `a97eb0f7-bc49-4df4-a5e3-b270c355d4c3`, 12/12 local cells; Floodgate `0eb493fc46d1bb9baf1151a6ccdde93544e057e7`; no hosted compression run claimed |

The upstream peer must use compatible named schema identities, container
factories/layouts, and the [oracle's runtime settings][service]. The frozen
legacy profile still disables runtime operation compression with
`minimumBatchSizeInBytes: Infinity`. The separate compression extension accepts
inbound Fluid 3.1.0 LZ4 singleton and grouped messages, per-sender chunked LZ4
messages, empty final chunks, and `/.chunks` prefix continuation at the pinned
defaults of 614400-byte compression and 204800-byte chunks. Native submissions
remain uncompressed. The driver and server scope are unchanged: discovery,
long-polling downgrade, and whole-summary upload stay disabled, RestLess stays
enabled, and the evidence uses the same pinned Floodgate.

The extension caps packed, reassembled, and decoded payloads at 16 MiB; caps
all buffered partial streams at 16 MiB; and permits at most 64 streams and 128
chunks per stream. It rejects unmarked packed contents, algorithms other than
LZ4, legacy multi-message compressed arrays, nested compression, and missing
partial prefixes. These boundaries do not claim older historical Fluid forms.

Tree-side incremental encoding must also stay disabled. The pinned upstream
[default incremental policy][up-incremental] returns false; opting into
incremental encoding is outside the profile. This is a separate setting from
runtime operation compression.

The default container has alias `root` pointing to datastore `A`, bootstrap
SharedMap `/A/root` with a `"tree"` handle, and SharedTree `/A/_C`. Declared
additional datastores/maps/trees and their handle graphs are also covered;
arbitrary executable factories and application layouts are not.

`oldestSupportedClient: 2.117.0` is container metadata, **not tested Fluid 2.x
support**. The codec profile includes Schema V2, FieldBatch V2, Message V7,
SharedTreeChange/ModularChange V5, sequence-field V3, and compressor format V2.
See the profile for all nested versions.

The common service in the recorded evidence is Floodgate: the upstream driver
uses Socket.IO and Watershed uses Phoenix. This is evidence of client
interoperation, not a claim that Watershed's built-in transport connects
directly to every service supported by the upstream driver. Cross-server
compatibility is outside this report.

## Reading the matrix

Implementation and evidence are independent. **Implemented** means the stated
native slice exists; **Partial** means important restrictions remain;
**Unsupported** means the audited application API or profile excludes it;
**Unassessed** means its end-to-end behavior has not been established here;
**N/A** means it is not a cross-language runtime requirement.

The JS and BEAM columns are separate assessments of the two facades and their
adapters, not an assumption that shared kernel code proves parity. Where they
agree, that agreement applies only to the row's stated slice.

Evidence abbreviations:

- **N:** native tests. Tests for a kernel or declaration do not alone prove
  public-facade or real-service behavior.
- **O:** pinned upstream observations/codec comparisons. These do not alone
  prove real-client collaboration.
- **L:** recorded live-service interoperability, with the directions and
  lifecycle phases described by the linked gate and acceptance record.
- **I:** inspected implementation/API contract only; **unproven** as an
  interoperability claim.

Impact abbreviations:

- **Blocker:** conditional collaboration blocker. The condition can prevent
  load, replay, view access, or correct interpretation; the row names it.
- **Local:** native application API difference, not evidence of a new
  incompatible wire operation.
- **Operational:** lifecycle, durability, or scale restriction; it can coexist
  with a blocker.
- **Within slice:** no known incompatibility inside the stated, evidenced slice.
- **Unknown:** peer-consumption impact is unassessed.
- **N/A:** language-only or implementation detail.

**Local authoring and peer consumption are different questions.** A missing
native convenience method does not prove that its upstream output is rejected.
Conversely, a method that looks local may generate a different schema, commit,
or persisted representation. The report does not promote source-level
similarity to live proof.

## Schemas and content

| ID | Upstream capability / tier | JS | BEAM | Evidence | Direction, impact, and remaining boundary |
| --- | --- | --- | --- | --- | --- |
| S01 | Primitive leaves, required/optional roots and object fields (public) | Implemented | Implemented | N/O/L [schemas][schema-evidence], [core gate][core-gate] | Within slice: string, finite number, boolean, null, and supported handle leaves; absent optional content is not null. Primitive-root declarations have N evidence, not a dedicated live creator matrix for every root kind. |
| S02 | Named fixed objects and nested fields (public) | Implemented | Implemented | N/O/L [schema][schema], [core gate][core-gate] | Within slice for matching persisted names/fields. A JavaScript class name is not the stored schema identity. |
| S03 | Allowed-type unions and recursive schemas (public/beta) | Partial | Partial | N/O/L for declared recursive map/array profiles; N [typed declarations][typed-tests] | The kernel stores union type sets; the public `typed.schema` root requires one allowed identifier. Public single-identifier field/collection declarations cannot stand in for arbitrary unions; internal dynamic-union fixtures are not a public union API. Blocker for opening such a typed view, not proof of a wire-decoder failure. Add public typed union declarations and their peer/reload evidence. |
| S04 | Dynamic maps, per-key edits, arbitrary keys (public) | Implemented | Implemented | N/O/L [map tests][map-tests], [core gate][core-gate] | Within slice for leaves, objects, and declared recursive values. Native key/entry iteration uses canonical UTF-8 order; do not assume JavaScript enumeration order. |
| S05 | Named recursive arrays, range edits, identity-preserving moves (public) | Implemented | Implemented | N/O/L [array tests][array-tests], [core gate][core-gate] | Within slice, including compatible cross-array moves and detached repair. Local range validation differs from upstream; see A09. |
| S06 | Record nodes and record-schema factories (beta/alpha) | Unassessed | Unassessed | I [upstream stored conversion][up-stored], [record implementation][up-record] | Upstream records persist as the same optional-entry map schema, not a distinct persisted `record` kind. Native maps are relevant prior art, but no record-proxy/API or dedicated record peer matrix is claimed. Assess actual schemas, typed access, concurrent assignments/deletions, and reload before promising support. |
| S07 | Identifier fields and generated defaults (public) | Implemented | Implemented | N/O/L [Identifier cases][identifier-evidence], [creation gate][creation-gate] | Within slice: generated/default and caller-supplied strings, immutable attached fields, compressor-aware messages, and reload. Custom strings need not be unique; node identity remains separate. |
| S08 | General defaults, stored-key renames, schema metadata (public/alpha) | Partial | Partial | I/N [typed API][typed], [schema tests][schema-evidence], [upstream conversion][up-stored] | Local: hand-authored builders/decoders and stored keys replace JS default-provider/class behavior. The schema parser preserves persisted JSON and checks metadata shape. Exhaustive upstream default-provider, renamed-field, and persisted-metadata round trips are unproven; do not treat all metadata as a new wire feature or claim all combinations work. |
| S09 | Compatibility checks and explicit object/map upgrades (public/beta) | Partial | Partial | N/O/L [evolution cases][evolution-evidence], [core gate][core-gate] | Within the strict-view object/map slice. Native `Compatibility` exposes view/upgrade/equivalence, not upstream's complete discrepancy API. Array evolution and staged/adapted views remain excluded. |
| S10 | Staged upgrades, unknown-field views, schema migrations (beta/alpha) | Unsupported | Unsupported | N/O [evolution cases][evolution-evidence], I [schema][schema] | Blocker when the application requires an excluded view/upgrade; source schemas can sometimes reduce to ordinary supported stored schemas, which is not proof of the richer feature. Keep peers in the strict profile; add schema/data race and reload proof for extensions. |

### Schema notes

S03 is an application-access restriction as well as a proof gap. The
[typed implementation][typed] checks an exact singleton root allowed-type set;
collection declarations must account for the complete allowed item set.
[The heterogeneous-array tests][typed-facade-tests] exercise internal checked
builder/union facilities, not an unrestricted public union declaration.
Do not cite them as proof that arbitrary `JsonAsTree.Tree` roots are supported.

A whole-record decoder can still interpret union-valued content under a
supported singleton root. The restriction is on declaring a union root or
using the checked, identity-bound field/collection APIs with a complete union,
not evidence that every nested union prevents loading or reading the tree.

For S06, [upstream `getStoredSchema`][up-stored] treats `NodeKind.Map` and
`NodeKind.Record` together. A blanket "record wire type unsupported" diagnosis
would be wrong. For S10, `allowUnknownOptionalFields` is a view policy, not
itself another persisted node kind. Its lack of a native view adapter must not
be confused with rejection of every document authored using that option.

## Native application API

| ID | Upstream capability / tier | JS | BEAM | Evidence | Direction, impact, and remaining boundary |
| --- | --- | --- | --- | --- | --- |
| A01 | Schema factories, view creation, typed reads/builders (public/alpha) | Partial | Partial | N [typed schema][typed-tests], [typed facades][typed-facade-tests] | Local: one `SharedTree(schema, record)` API with hand-authored persisted schema and decoding/building, not JS class/proxy emulation or generated schema declarations. See S03 for limits that prevent view access. |
| A02 | Node type/identity/lifetime inspection and traversal (public/alpha) | Partial | Partial | N [node tests][node-tests], I [JS][js], [BEAM][beam] | Native captured node/array/map handles follow identity; retained snapshots and node type are available. No general `Tree.parent/key/status/contains/children` facade or equivalent JS status taxonomy. Native handles must not be treated as portable short IDs. Local API difference; detached/deleted-node behavior stays bounded by native tests. |
| A03 | Tree/view/node events and commit subscriptions (public/beta/alpha) | Partial | Partial | N/O/L [kernel][kernel], [transactions][transaction-evidence], [lifecycle gate][lifecycle-gate] | Native tree/schema events and commit/settlement subscriptions exist. JS tree subscriptions use callbacks/tokens; BEAM tree subscriptions return Subjects, while commit subscriptions use callbacks/tokens. No node-scoped JS delta/event payload parity. Local, not a different collaborative document. |
| A04 | Indexes, identifier index, dirty tracking, reactive observations (beta/alpha) | Unsupported | Unsupported | I [facades][js], [typed][typed], [upstream API][up-api] | No native counterparts to `createTreeIndex`, `createIdentifierIndex`, `trackDirtyNodes`, or automatic observation tracking. Local; reading/deriving an application index is not a missing tree wire format. |
| A05 | Unhydrated node construction, clone, import-before-attachment (public/beta/alpha) | Partial | Partial | N [typed builders][typed-tests], L [lifecycle gate][lifecycle-gate] | Builders insert values; detached SharedMap/SharedTree channel graphs exist. These are not JS unhydrated node objects, `Tree.create/clone`, or transferable detached node identity. Local, with target attachment rejected during active transactions. |
| A06 | Concise/verbose/compressed import/export and handle replacement (beta/alpha) | Unsupported | Unsupported | I [facades][js], [upstream API][up-api] | No public counterparts to the upstream serialization utility suite. Internal wire/summary codecs are not an application import/export API. Local; consumption of an imported value still depends on S01-S10 and R01-R04. |
| A07 | Independent, non-container tree/view APIs (beta/alpha) | Unsupported | Unsupported | I [upstream API][up-api], [facades][js] | No public `createIndependentTree*`, `independentView`, or `ViewContent` API. Runtime-local forks are not independent documents. Local. |
| A08 | Map clear and get-or-insert conveniences (alpha) | Unsupported authoring; peer unassessed | Unsupported authoring; peer unassessed | I [upstream map][up-map], [native map tests][map-tests] | Upstream `getOrInsert*` uses get/set; `clear` deletes each key inside a transaction. No native map-wide helper or dedicated upstream-clear service scenario. Do not assert a distinct unsupported clear opcode. Add focused proof before expanding the profile's map-wide-clear claim. |
| A09 | JS array methods, iterators, and range-clamping behavior (public/alpha) | Partial | Partial | N/O [array cases][array-evidence], I [upstream array][up-array] | Native get/list/insert/remove/move cover the supported edits. No JS `splice/pop/shift/unshift/findLast` surface. Upstream removal clamps an oversized end; native APIs reject invalid ranges. Local behavior difference, not evidence of failed replay of a valid upstream range edit. |
| A10 | Insertion-gap anchors (`ArrayPlaceAnchor`) (alpha) | Unsupported | Unsupported | I [upstream API][up-api], [facades][js] | Captured-item `tree_array_move_before` is supported, but is not a persistent insertion-gap anchor with `index`/`dispose`. Local; add anchor lifetime/concurrency semantics separately. |
| A11 | Schema introspection, JSON Schema, compatibility snapshots (alpha/beta) | Partial | Partial | I/N [schema][schema], [upstream API][up-api] | Native persisted-schema parsing and compatibility checks exist, not `getJsonSchema/getSimpleSchema`, schema-code generation, disk snapshots, or the upstream import/export/compare utility suite. Local; generated schema-to-Gleam ergonomics remain follow-up work. |
| A12 | Forest selection, validators, codec-write overrides (beta/alpha) | Partial | Partial | I [profile][profile], [upstream options][up-options] | Native implementation/validation is fixed, not configurable with upstream forest/validator objects. Local implementation choices are N/A; incompatible codec/version overrides can be blockers under R01. Extra upstream history retention needs separate scale proof. |
| A13 | TS type computation, nominal brands, class customization (all tiers) | N/A | N/A | I [exports][up-entry], [typed][typed] | Type operators, unsafe recursive declaration helpers, `instanceof`, JS subclasses, and proxy property syntax are not language-parity requirements. Their resulting persisted schema/content is still assessed by other rows. |

## Transactions, history, and branching

| ID | Upstream capability / tier | JS | BEAM | Evidence | Direction, impact, and remaining boundary |
| --- | --- | --- | --- | --- | --- |
| H01 | Synchronous transactions, nesting, rollback, node-existence constraints (public) | Implemented within slice | Implemented within slice | N/O/L [transaction tests][transaction-evidence], [core gate][core-gate] | Within a single tree/checkout. JS captures callback exceptions and aborts; BEAM's facade uses callback `Result` aborts and does not provide the same exception wrapper. No cross-tree atomicity promise. |
| H02 | Async transactions and richer callback protocols (beta/alpha) | Unsupported authoring; peer unassessed | Unsupported authoring; peer unassessed | I [facades][js], [BEAM][beam], [upstream API][up-api] | Local: no async transaction facade or upstream callback-result object protocol. Do not infer that an async upstream transaction always creates a distinct wire format; assess its actual final commit/constraints before a peer claim. |
| H03 | No-change constraints, transaction labels/metadata/post-processors (beta/alpha) | Unsupported | Unsupported | I [profile][profile], [transaction implementation][transactions] | Native authoring is limited to node-in-document constraints; no native labels, custom metadata, or `minimize` post-processor contract. Peer consumption of each richer combination is unproven, not automatically implied by basic transactions. |
| H04 | Application-owned undo/redo and revertible lifetime (public) | Implemented within slice | Implemented within slice | N/O/L [undo tests][undo-evidence], [core gate][core-gate] | Object/map/array/move/transaction reversion, default commit kinds, local handle disposal, reconnect, and sequenced outcomes. Applications own stacks; restored document state does not revive old handles. |
| H05 | Revertible clone, revert-to/rewind, custom revert metadata (alpha) | Unsupported | Unsupported | I [profile][profile], [upstream API][up-api] | Local authoring differences; peer output of advanced history manipulation needs its own proof. Schema undo, remote-commit undo, undo during a transaction, and cross-tree atomic undo are outside the native profile. |
| H06 | Local forks, rebase, merge, disposal, checkout-local transactions (beta/alpha) | Implemented within slice | Implemented within slice | N/O/L [branch tests][branch-evidence], [core gate][core-gate] | Within related checkouts of the same runtime/tree. Live reconnect retains local handles; merged edits survive summary/reload. Unmerged local branches are not shared or persisted. |
| H07 | Change export/apply, branch-history introspection, historical checkouts (alpha) | Unsupported | Unsupported | I [facades][js], [upstream API][up-api] | No public equivalents to `applyChange`, net-change calculation, missing-edit checks, parent-commit navigation, or `rewindTo`. Diagnostic `tree_history_evidence` is not that application API. Local; raw imported changes require separate semantic validation/proof. |
| H08 | Checkout-local schema authoring and schema-divergent rebase (alpha) | Unsupported | Unsupported | O [branch cases][branch-evidence], I [deferred decision][roadmap] | Native branch schema authoring is refused. Upstream can drop a fork's wider schema and dependent edits on rebase; that observed behavior is not a supported native feature. Main-tree upgrades remain governed by S09/S10. |
| H09 | Shared/persisted branches and branch wire APIs (alpha) | Unsupported | Unsupported | I [profile][profile], [upstream API][up-api], [summary decoder][summary-codec] | Blocker if a document requires the excluded shared-branch persistence/messages. Keep `enableSharedBranches` off. Do not confuse EditManager peer-branch history or native local forks with this feature. |

## Runtime, container, and durability

| ID | Upstream capability / tier | JS | BEAM | Evidence | Direction, impact, and remaining boundary |
| --- | --- | --- | --- | --- | --- |
| R01 | Selected tree/container codecs and package versions (internal contract) | Implemented within pin | Implemented within pin | N/O/L [profile][profile], [codec gate][codec-gate], [core gate][core-gate] | Blocker for unsupported semantic formats/versions. There is no compatibility promise for Fluid 2.x, later 3.x, arbitrary codec overrides, or old Watershed development encodings. |
| R02 | Runtime ID compressor, allocation order, Identifier strings (internal contract) | Implemented within slice | Implemented within slice | N/O/L [ID tests][id-tests], [Identifier cases][identifier-evidence] | Finalize allocation ranges on sequenced delivery; use receiver compressor identity order, not UUID sorting. Contextual message compression and stored summary compressor state are supported; `Tree.shortId`/indexes are separate local APIs. |
| R03 | Grouped batches versus compressed/chunked operations (internal contract) | Implemented within extension | Implemented within extension | N/O/L [compression profile][compression-profile], [compression gate][compression-gate] | Inbound Fluid 3.1.0 plain singleton/grouped, LZ4 singleton/grouped, per-sender chunked LZ4, empty-final-chunk, and partial-prefix continuation are supported within the published limits. Native outbound remains plain. Unmarked packed contents, non-LZ4, legacy multi-message arrays, nested compression, and missing prefixes are refused. |
| R04 | Nonincremental FieldBatch V2 versus incremental chunks (alpha/internal) | Partial | Partial | N/O/L [field-batch codec][field-batch], [codec gate][codec-gate] | Blocker when a peer/summary uses incremental chunk shapes: the native decoder explicitly rejects discriminator `e`. Nonincremental uncompressed/schema-aware forms are supported. `TreeCompressionStrategy.Compressed` alone is not the unsupported runtime-op compression of R03. |
| R05 | Bootstrap routing, factories, initial and attached layouts (alpha/internal) | Partial | Partial | N/O/L [document runtime][document], [layout gate][layout-gate] | Default and declared map/tree graphs are supported. Blocker for required unsupported channel types/layout contracts. Some metadata/layouts may decode. A general application factory/plugin framework is [out of scope for now](#container-factory-scope-decision--2026-10-16), with no scheduled milestone. |
| R06 | Same-container map/tree handle leaves and attachment graphs (public/internal) | Implemented within slice | Implemented within slice | N/O/L [handle implementation][handles], [lifecycle gate][lifecycle-gate] | Supported relative/source-context binding, escaped routes, cycles, cross-datastore references, retained routes, transactions/branches, reconnect, and reload. Detached targets attach through the runtime before the referring edit. |
| R07 | Blob, external/cross-container, pending-payload handles (public/internal) | Unsupported | Unsupported | I/N/O [handles][handles], [lifecycle cases][lifecycle-evidence] | Blocker when content requires a non-channel or external target. Ordinary supported handle leaves are not excluded; neither are summary-level blob/tree references, which are a different concept. |
| R08 | Native creation and datastore alias publication (alpha/internal) | Implemented within slice | Implemented within slice | N/O/L [creation gate][creation-gate], [alias gate][alias-gate] | Native creators produce loadable documents; aliases settle on their own acknowledgements and survive reconnect/reload. JS alias claims return a promise; BEAM waits for a Result and has a bounded call timeout, not cancellation of accepted claims. Production token-service integration is not proved by development credentials. |
| R09 | Summary load, full writing, previous-summary references (internal contract) | Partial | Partial | N/O/L for full load/write/tail, ordinary tree/blob references, and `/.chunks`; [reference bootstrap gate][reference-bootstrap], [summary resolution][summary-tests], [compression gate][compression-gate] | Upstream `fullTree: false` summaries reuse unchanged subtrees and schema blobs; fresh native readers fetch the reused Git IDs through real storage bootstrap, consume the tail, and continue editing. Native full summaries and validated partial chunk prefixes remain supported. Declared layouts only; no incremental native writer, opt-in incremental FieldBatch chunks, or automatic native tree summarizer. |
| R10 | Retained history, detached content, GC metadata and sweep (internal contract) | Partial | Partial | N/O/L [document tests][document-tests], [lifecycle gate][lifecycle-gate] | GC metadata/routes are preserved and updated; native GC sweep is excluded. Native retained handles/undo/branches constrain reclamation. Do not enable destructive upstream sweep and assume interoperability has been established. |
| R11 | Catch-up, reconnection, duplicate acknowledgement, resubmission (internal contract) | Implemented within slice | Implemented within slice | N/O/L [client gate][client-gate], [core gate][core-gate], [compression gate][compression-gate] | Pending tree state/compressor remain live; replay and session barriers precede resubmission. Physical chunk sequence advances independently from logical batch application, and reconnect/history catch-up retains complete per-sender prefixes. Missing prefixes, corrupt history, or authorization refusal produce an explicit failure/suspension, not a writable partial tree. |
| R12 | Explicit pending-tree restart checkpoints (native lifecycle) | Implemented within slice | Implemented within slice | N/L [recovery gate][recovery-gate], [recovery tests][recovery-tests], [compression gate][compression-gate] | Application-stored JSON supports target-switch/process-kill recovery, accepted native prefixes, retained peer chunk prefixes, later accepted edits, and continued allocation. The compression matrix kills the writer and restores each checkpoint on the opposite target before consuming the tail and settling the original pending edit. No automatic journal, mixed-DDS pending recovery, detached graph persistence, or restoration of subscriptions/branches/undo handles. Pending attachment/alias work must settle before capture. |
| R13 | Offline edits and portable local application history (lifecycle) | Unsupported | Unsupported | I/N [facades][js], [recovery documentation][readme-recovery] | Operational: new tree edits require readiness; reconnect retaining existing edits is not offline authoring. No persisted/shared undo stack or portable branch/revertible handles. |
| R14 | Capacity, throughput, bounded memory, safe reclamation (implementation) | Unassessed guarantees | Unassessed guarantees | I [limits][readme-limits], [M8 scope][roadmap] | Operational: no published capacity/throughput/bounded-memory guarantee. Existing schedules are not capacity measurements. Measure realistic workloads and retained-state lifetimes before setting limits. |

### Container factory scope decision — 2026-10-16

**Decision:** A general application runtime/datastore factory and plugin
framework is out of scope for now. It has no assigned milestone or delivery
commitment. Revisit it if a concrete application needs it.

This refers to Fluid container and datastore factories, not SharedTree's
`SchemaFactory` for declaring tree schemas. Upstream Fluid supports the general
mechanism: its [container loader][up-container-loader] calls the host's
`codeLoader.load(codeDetails)` to obtain a runtime factory; its
[datastore context][up-datastore-factory] resolves stored package paths through
registered factories and instantiates the selected datastore. The application
supplies those implementations, their DDS registrations, initialization logic,
and entry points. Upstream also fails when a required factory is absent; it is
not a universal viewer for unknown Fluid applications.

Snapshots contain persisted data and type/package identifiers, not the
application's executable factory code. Watershed reads supported storage and
routing directly without executing upstream JavaScript factories. Multiple
trees, independent schemas, aliases, and connected or cyclic declared map/tree
graphs already work within the published profile.

Broader factory support would let a host supply application-specific loading,
lazy creation, object discovery, and entry-point behavior for existing Fluid
applications outside those conventions. For example, Watershed does not invoke
an application's `getBoard()` entry point to discover its task tree. An explicit
adapter or broader declared layout might suffice when the underlying channels
are supported maps and trees; compatible unfamiliar metadata may already
decode, without a general interoperability guarantee. Other DDS types or
custom collaboration protocols would also need their own codecs and semantics.
Factory support alone would not supply those.

If a consumer requires this, assess a narrow application adapter or declared
layout extension before designing a general plugin framework. This decision
does not propose executing arbitrary JavaScript on BEAM, expand current layout
support, or make factory support a prerequisite for M8 persistence work.

## Upstream domain helpers

These are real upstream client exports, not extra DDS implementations. They
were missing from a gaps summary based only on the existing profile labels.

| ID | Upstream capability / tier | JS | BEAM | Evidence | Direction, impact, and remaining boundary |
| --- | --- | --- | --- | --- | --- |
| D01 | `JsonAsTree` / `FluidSerializableAsTree` (alpha/beta) | Unassessed | Unassessed | I [JSON source][up-json], [serializable source][up-serializable] | Composite recursive record/array/leaf schemas, with handles added in the serializable domain. No native helper suite or end-to-end domain matrix; S03 singleton typed-root access and S06 record access matter. Ordinary JSON stored inside another DDS is not evidence for these tree domains. |
| D02 | `PlainText` / `FormattedText`, code-point helpers (alpha) | Unassessed | Unassessed | I [plain text source][up-text], [formatted text source][up-formatted] | Composite arrays/objects, stored-key aliases, format/atom schemas, anchors, and event helpers. No native equivalent or text-domain collaboration proof. Their names do not establish either a new text opcode or automatic compatibility with Watershed's separate text/rich-text DDSs. |
| D03 | `TableSchema` / `System_TableSchema` (beta) | Unassessed | Unassessed | I [table source][up-table] | Generated object/Identifier/record/array schemas with indexing and transaction/constraint helpers. No table-domain native API or peer/reload proof. Reuse ordinary semantics only after validating the actual generated schema and commits. |
| D04 | `ExtensibleUnionNode` and enum/singleton helpers (beta) | Unsupported helpers; peer unassessed | Unsupported helpers; peer unassessed | I [union source][up-union], [upstream API][up-api] | Enum/singleton wrappers reduce to schemas that can be declared by hand; extensible unions also use renamed stored keys and unknown-optional-field view policy. No equivalent helper or domain-specific proof. Assess S03/S08/S10 rather than declaring every union a new wire type. |
| D05 | `Component` composition/memoization (alpha) | N/A helper | N/A helper | I [component source][up-component] | Local JS composition/configuration machinery, not a collaborative component protocol. Generated configuration/content remains subject to the other rows. Watershed's own component SDK is not evidence for this upstream helper. |

## Evidence map

Evidence below is historical unless explicitly stated otherwise. This audit
verified the installed package/source pin; it did **not** rerun the native
suites or live service matrices. Reproducible gates and tracked acceptance
records are the durable references; ignored `.output` files are supplemental.

| Evidence | What it establishes, and what it does not |
| --- | --- |
| [M7 supported-profile acceptance][acceptance] | Recorded local object/map/array/move/schema/Identifier/history acceptance, 300 schedules, 18 creation cells, 12 layout cells, seven lifecycle sections/27 reload cells/300 schedules, 16 alias cells, and 32 recovery cells under the profile digest above. Not arbitrary schemas or package versions. |
| [`just shared-tree-test`][recipes] | Native selected suites and HTTP/storage/bootstrap/creation smokes on both targets. This does not itself run a real Fluid peer. |
| [Codec gate][codec-gate] | Native/upstream codec consumption/export for the selected formats. Not a live-client or arbitrary-version result. |
| [Core service gate][core-gate] and [client gate][client-gate] | Upstream, native JS, and BEAM authors; concurrency, focused reconnect, and object/map/array/Identifier/schema/history summary continuation within declared scenarios. Not all possible compositions of supported features. |
| [Creation][creation-gate] and [layout][layout-gate] | Both native creators, fresh upstream/JS/BEAM readers, edits, native summaries, and continued editing for the specified schemas/layouts. Not every root kind or arbitrary factory. |
| [Lifecycle gate][lifecycle-gate] | Handle values, attachment, cross-datastore graphs, transaction/branch binding, retention, reconnect, reload, and generated schedules. Not blobs, cross-container targets, or arbitrary domain helpers. |
| [Alias gate][alias-gate] and [recovery gate][recovery-gate] | Target-specific claim/reconnect/reload behavior and bounded pending-tree disk recovery. Not automatic journaling or preservation of all application state. |
| [Native CI][native-workflow] / [manual service workflow][service-workflow] | Existing automation entry points. Workflow presence is not a fresh run, hosted acceptance result, or branch-protection configuration. |

## Frozen profile label crosswalk

The profile remains byte-for-byte unchanged. The labels are a historical
contract vocabulary, not a complete API inventory. Each label below maps to a
matrix row; grouped labels share a boundary, not necessarily identical proof.

### Supported labels

| Labels | Rows / qualification |
| --- | --- |
| `fixed-object-schema`, `primitive-leaves`, `optional-string`, `nested-object` | S01-S02 |
| `dynamic-map-schema`, `per-key-map-edits`, `recursive-map-values`, `canonical-map-iteration` | S03-S04 |
| `recursive-array-values`, `range-array-edits`, `cross-array-moves` | S03, S05, A09 |
| `identifier-fields`, `identifier-defaults`, `identifier-compression`, `identifier-summary-reload` | S07, R02; not all upstream identifier utilities |
| `bootstrap-map-handle` | R05-R06 |
| `grouped-batches` | R03; not compressed/chunked operations |
| `gc-metadata` | R10; not sweep |
| `strict-view-object-map-schema-evolution` | S09; not array/staged evolution |
| `handle-valued-tree-leaves`, `detached-shared-map-and-tree-creation`, `implicit-attachment-graphs`, `declared-cross-datastore-references`, `retained-handle-routes` | A05, R06; channel graphs, not JS detached node builders |
| `new-alias-authoring`, `declared-initial-container-layouts` | R05, R08 |
| `synchronous-single-tree-transactions`, `stable-node-existence-constraints` | H01 |
| `application-owned-revertibles`, `default-undo-redo-commit-kinds`, `runtime-local-handle-lifetime`, `reconnect-with-live-handles`, `object-map-array-move-transaction-undo-redo`, `sequenced-commit-outcomes` | H04, R11; no persisted application stack |
| `runtime-local-checkouts`, `local-fork-rebase-merge`, `checkout-scoped-transactions-and-revertibles`, `branch-and-revertible-history-retention`, `local-branch-reconnect`, `merged-branch-summary-continuation` | H06, R10-R11; not shared/persisted branches |

### Excluded labels

| Labels | Rows / qualification |
| --- | --- |
| `array-schema-evolution`, `staged-schema-upgrades`, `unknown-field-view-adapters`, `data-migrations` | S09-S10 |
| `additional-upstream-versions` | R01; unassessed versions, not proof they all fail |
| `gc-sweep` | R10 |
| `compressed-ops`, `chunked-ops` | R03 |
| `incremental-field-batch-chunks` | R04; not all compressed FieldBatches |
| `identifier-handles`, `tree-short-id`, `identifier-index`, `custom-identifier-global-uniqueness`, `uuidv5-healing` | S07, A02, A04, R02; does not exclude ordinary handle-valued leaves |
| `arbitrary-container-layouts`, `arbitrary-datastore-factories` | R05 |
| `detached-node-builder` | A05; detached channel graphs exist |
| `blob-handles`, `cross-container-handles` | R07; does not exclude summary references |
| `production-authentication` | R08; development credentials are not production token lifecycle evidence |
| `pending-state-disk-recovery` | R12-R13: broader pending-state recovery remains excluded, but explicit application-stored pending-tree checkpoints are implemented and live-proven. Do not read this label as "no disk recovery exists." |
| `richer-typed-handle-consumers` | A01-A02: the typed SharedTree API and identity-bound collection handles are implemented; this broad label does not remove that accepted slice or promise every upstream typed API. |
| `persisted-undo-redo-stacks`, `schema-undo`, `remote-commit-undo`, `undo-during-transactions`, `cross-tree-atomic-undo`, `custom-revert-metadata`, `clone-to-view`, `revert-to` | H04-H05, R13 |
| `asynchronous-transactions`, `cross-tree-transactions`, `schema-upgrades-in-transactions`, `no-change-constraints`, `transaction-metadata`, `transaction-post-processors`, `async-cross-tree-transactions` | H01-H03; cross-tree atomicity is outside the native contract, not an assertion that every listed operation is an upstream single-tree feature |
| `shared-branches`, `persisted-branches`, `branch-wire-apis`, `branch-schema-authoring`, `cross-runtime-or-tree-merge`, `portable-branch-handles-and-revertibles`, `historical-checkouts` | H05-H09, R13 |

Map-wide clear, generated schema declarations, automatic tree summarization,
and offline authoring also have matrix rows even though they are not explicit
feature-array labels. Absence from an exclusion array is not support.

## Prioritized gaps and next proof

This is an implementation/proof backlog, not a promise to implement every
upstream API. Priorities reflect client collaboration impact, not estimates.

The [runtime compression/chunking slice](superpowers/plans/2026-10-14-shared-tree-compression.md)
is implemented and locally accepted. Its separate extension profile leaves the
legacy profile frozen and removes ordinary default size-triggered inbound
compression from the blocker list. R04 remains unchanged: opt-in incremental
FieldBatch chunks are still excluded and are not runtime operation compression.

**Storage bootstrap/reference consumption, 2026-10-16:** The local
[reference-bootstrap regression][reference-bootstrap] now covers actual
upstream tree/blob handles and both native storage readers. Its nine-cell
retained-summary matrix checks snapshot-plus-tail loading and fresh-reader
continuation. The existing Git hierarchy reader needed no runtime changes.
The complete summary and acceptance-validator suites passed after generating
the retained-graph artifacts. This closes the ordinary-reference proof gap
within the declared layouts; R09 stays partial for its remaining writer and
encoding restrictions.

| Priority | Rows | Trigger / current restriction | Required implementation or proof |
| --- | --- | --- | --- |
| Accepted slice | R09 | Ordinary upstream snapshot references now have storage-bootstrap proof on both targets. | Keep the reference-backed reload gate permanent. Broader reference/configuration forms need their own proof; incremental native writing remains separate. |
| 2 | S03, S06, A08-A09, D01-D04 | Common typed union/record access or JSON/domain-helper outputs lack native access or dedicated proof. | Public typed union/record access where needed; actual upstream commits and bidirectional author/read/reload scenarios. Do not assume a local API omission means persisted-data rejection. |
| 3 | S09-S10 | A consumer needs array evolution or a richer schema policy. Use strict object/map upgrades meanwhile. | Array schema/data races and reload matrices first; choose additional policies by consumer need. |
| 4; measure now | R04, R09-R10, R14 | Opt-in incremental FieldBatch chunks, incremental writing, or retained-state scale. Keep the current encoding/full-summary/no-sweep boundaries. | Baseline realistic workloads now; schedule each codec/persistence/reclamation change from measured need and prove retained handle/history safety. R04 is not bundled with default runtime compression. |
| 5; demand-driven | A02-A07, A10-A13, R12-R13 | Missing native observation/traversal/index/builder/import/export or generated declarations and broader durability. | Add requested ergonomics behind the ordinary-client gaps; broaden persistence with explicit ownership/lifetimes. Preserve the implemented typed API and explicit pending-tree checkpoint slice. |
| Out of scope for now; revisit on concrete need | R05 | A general application runtime/datastore factory and plugin framework. | No scheduled phase. Start with an application adapter or declared-layout extension if a consumer requires it; see the factory scope decision above. |
| Demand-driven | R05, R07, H02-H03, H05, H07-H09 | An application actually needs a broader declared layout, exotic handles, shared branches, or richer transaction/history behavior. | Define each selected loading/wire/lifetime contract and prove it; these can be blockers for that application without outranking ordinary supported-client traffic by default. |
| Demand-driven | R01 | A collaborator upgrades packages or changes codec write settings. Pin Fluid 3.1.0. | Explicit additional-version/configuration matrices and format validation; metadata version floors alone do not establish support. |

Production authentication remains a release prerequisite (R08), not a deferred
optional API. None of this ordering expands current support, reopens accepted
M7 work, or changes the frozen profile's labels.

## Upstream coverage appendix

### Inventory method and scope

The published entry points contain **334 distinct exported names** after
deduplicating re-exports: 73 public, 84 beta, 173 alpha, and four legacy-beta
additions. Counts identify the audited source inventory, **not a percentage of
compatible APIs**. The public/beta/alpha/legacy reports and entry points were
read as API inventories, including behavior-bearing members, inherited
interfaces, callable properties, overloads, namespaces, and runtime values
sharing a name with a type.

Sources: [entry points][up-entry], [public report][up-public],
[beta report][up-beta], [alpha report][up-api],
[legacy public report][up-legacy-public], [legacy beta report][up-legacy].
The [internal index][up-index] supplies relevant implementation contracts, not
an obligation to port every private helper.

The [`fluid-framework` aggregator][up-aggregator] re-exports the tree alpha
surface and wraps SharedTree/configured-tree construction. Its unrelated
audience/presence/service-client and other DDS APIs are outside this SharedTree
audit. The construction wrappers are accounted for by R01/R05/R08/A12; they
are not evidence that arbitrary Fluid static-container schemas are supported.

The tables below enumerate all exported names. A type listed with a runtime
family describes that family's input/output contract, not a separate
implemented native type. System/unsafe/erased/recursive type helpers inherit
the relevant family's semantic boundary and are A13 for TypeScript syntax.

### Public exports

| Family / rows | Exported names |
| --- | --- |
| Schema declaration and content: S01-S08, A01, A13 | `AllowedTypes`, `FieldKind`, `FieldProps`, `FieldSchema`, `FieldSchemaMetadata`, `ImplicitAllowedTypes`, `ImplicitFieldSchema`, `LeafSchema`, `NodeKind`, `NodeSchemaMetadata`, `NodeSchemaOptions`, `SchemaFactory`, `SchemaFactory_base`, `SchemaStatics`, `SimpleNodeSchemaBase`, `TreeLeafValue` |
| Tree/view lifetime, reads, events: S09, A01-A03, R05-R06 | `ITree`, `ITreeConfigurationOptions`, `ITreeViewConfiguration`, `SchemaCompatibilityStatus`, `Tree`, `TreeChangeEvents`, `TreeNode`, `TreeNodeApi`, `TreeStatus`, `TreeView`, `TreeViewConfiguration`, `TreeViewEvents`, `ViewableTree` |
| Collections: S04-S05, A09, A13 | `IterableTreeArrayContent`, `MapNodeInsertableData`, `ReadonlyArrayNode`, `TreeArrayNode`, `TreeMapNode`, `TreeObjectNode` |
| Transactions/revertibles: H01, H04 | `CommitKind`, `CommitMetadata`, `NodeInDocumentConstraint`, `Revertible`, `RevertibleFactory`, `RevertibleStatus`, `RunTransaction`, `TransactionConstraint`, `rollback` |
| Type-level schema/insertable machinery: A13, with S03/A05 restrictions | `Input`, `InsertableTreeFieldFromImplicitField`, `InsertableTreeNodeFromAllowedTypes`, `InsertableTreeNodeFromImplicitAllowedTypes`, `InsertableTypedNode`, `InternalTreeNode`, `InternalTypes`, `IsUnion`, `LazyItem`, `MakeNominal`, `NodeFromSchema`, `NumberKeys`, `ObjectFromSchemaRecord`, `RestrictiveReadonlyRecord`, `RestrictiveStringRecord`, `System_Unsafe`, `TreeFieldFromImplicitField`, `TreeNodeFromImplicitAllowedTypes`, `TreeNodeSchema`, `TreeNodeSchemaClass`, `TreeNodeSchemaCore`, `TreeNodeSchemaNonClass`, `Unenforced`, `Unhydrated`, `UnionToIntersection`, `ValidateRecursiveSchema`, `ValidateRecursiveSchemaTemplate`, `WithType`, `typeSchemaSymbol` |

### Beta exports

| Family / rows | Exported names |
| --- | --- |
| Schema factory/metadata/policy: S03, S06, S08-S10, A01/A11/A13 | `AllowedTypeMetadata`, `AllowedTypesFull`, `AllowedTypesFullEvaluated`, `AllowedTypesFullFromMixed`, `AllowedTypesFullFromMixedUnsafe`, `AllowedTypesMetadata`, `AnnotatedAllowedType`, `AnnotatedAllowedTypeUnsafe`, `AnnotatedAllowedTypes`, `AnnotatedAllowedTypesUnsafe`, `ObjectSchemaOptions`, `SchemaCompatibilityStatusBeta`, `SchemaDiscrepancy`, `SchemaFactoryBeta`, `SchemaStaticsBeta`, `SchemaUpgrade` |
| Collection/events: S06, A03/A09 | `ArrayNodeDeltaOp`, `ArrayNodeInsertOp`, `ArrayNodeRemoveOp`, `ArrayNodeRetainOp`, `ArrayNodeTreeChangedDeltaOp`, `ArrayNodeTreeChangedRetainOp`, `NodeChangedData`, `NodeChangedDataDelta`, `NodeChangedDataProperties`, `NodeChangedDataTreeDelta`, `TreeChangeEventsBeta`, `TreeRecordNode`, `TreeRecordNodeUnsafe` |
| Transactions and local branches: H02-H06 | `RunTransactionParamsBeta`, `TransactionCallbackStatusBeta`, `TransactionResultFailed`, `TransactionResultSuccess`, `TransactionValueResult`, `TransactionVoidResult`, `TreeBranch`, `TreeContextBeta`, `TreeViewBeta`, `UntypedTreeView`, `VoidTransactionCallbackStatusBeta`, `WithValue` |
| Construction and utilities: A05-A07/A11/A12, R01/R05 | `CodecWriteOptionsBeta`, `ConciseTree`, `ForestOptions`, `ForestType`, `ForestTypeExpensiveDebug`, `ForestTypeOptimized`, `ForestTypeReference`, `KeyEncodingOptions`, `SharedTreeOptionsBeta`, `TreeBeta`, `TreeEncodingOptions`, `asBeta`, `configuredSharedTreeBeta`, `createIndependentTreeBeta`, `createIndependentTreeView` |
| Index and compatibility snapshot tools: A04/A11 | `IdentifierIndex`, `SnapshotFileSystem`, `SnapshotSchemaCompatibilityOptions`, `TreeIndex`, `TreeIndexKey`, `TreeIndexNodes`, `TreeIndexKeyFieldSelector`, `createIdentifierIndex`, `createTreeIndex`, `snapshotSchemaCompatibility` |
| Domains: D01/D03/D04 | `ExtensibleUnionNode`, `FluidSerializableAsTree`, `System_TableSchema`, `TableSchema`, `adaptEnum`, `enumFromStrings`, `singletonSchema` |
| Type-level helpers: A13, S03/S06 for content | `AnnotateAllowedTypesList`, `AnnotateAllowedTypesListUnsafe`, `FixRecursiveArraySchema`, `JsonCompatible`, `JsonCompatibleObject`, `PopUnion`, `RecordNodeInsertableData`, `UnannotateAllowedTypeUnsafe`, `UnannotateAllowedTypesList`, `UnannotateAllowedTypesListUnsafe`, `UnionToTuple` |

### Alpha and legacy exports

| Family / rows | Exported names |
| --- | --- |
| Schema declarations and representations: S01-S03/S06/S08-S10, A01/A11/A13 | `AllowedTypesFullUnsafe`, `ArrayNodeCustomizableSchema`, `ArrayNodeCustomizableSchemaAlpha`, `ArrayNodeCustomizableSchemaUnsafe`, `ArrayNodePojoEmulationSchema`, `ArrayNodeSchema`, `FieldHasDefaultAlpha`, `FieldHasDefaultAlphaUnsafe`, `FieldPropsAlpha`, `FieldSchemaAlpha`, `FieldSchemaAlphaUnsafe`, `MapNodeCustomizableSchema`, `MapNodeCustomizableSchemaUnsafe`, `MapNodePojoEmulationSchema`, `MapNodeSchema`, `NodeProvider`, `NodeSchemaOptionsAlpha`, `ObjectNodeSchema`, `ObjectNodeSchemaWorkaround`, `ObjectSchemaOptionsAlpha`, `RecordNodeCustomizableSchema`, `RecordNodePojoEmulationSchema`, `RecordNodeSchema`, `SchemaFactoryAlpha`, `SchemaStaticsAlpha`, `SchemaType`, `SimpleAllowedTypeAttributes`, `SimpleArrayNodeSchema`, `SimpleFieldSchema`, `SimpleLeafNodeSchema`, `SimpleMapNodeSchema`, `SimpleNodeSchema`, `SimpleNodeSchemaBaseAlpha`, `SimpleObjectFieldSchema`, `SimpleObjectNodeSchema`, `SimpleRecordNodeSchema`, `SimpleTreeSchema`, `StagedSchemaUpgradePolicy`, `StagedSchemaUpgradePolicyFactory`, `StagedUpgradeStatus`, `StringSchema`, `TreeSchema`, `TreeViewConfigurationAlpha`, `ValueSchema`, `evaluateLazySchema`, `normalizeAllowedTypes` |
| Schema conversion/snapshot utilities: A11, S08-S10 | `JsonArrayNodeSchema`, `JsonFieldSchema`, `JsonLeafNodeSchema`, `JsonLeafSchemaType`, `JsonMapNodeSchema`, `JsonNodeSchema`, `JsonNodeSchemaBase`, `JsonObjectNodeSchema`, `JsonRecordNodeSchema`, `JsonRefPath`, `JsonSchemaId`, `JsonSchemaRef`, `JsonSchemaType`, `JsonStringKeyPatternProperties`, `JsonTreeSchema`, `TreeSchemaEncodingOptions`, `checkCompatibility`, `comparePersistedSchema`, `decodeSchemaCompatibilitySnapshot`, `encodeSchemaCompatibilitySnapshot`, `exportCompatibilitySchemaSnapshot`, `extractPersistedSchema`, `generateSchemaFromSimpleSchema`, `getJsonSchema`, `getSimpleSchema`, `importCompatibilitySchemaSnapshot`, `persistedToSimpleSchema` |
| Tree/view construction, traversal, serialization: A02/A05-A07/A12, R01/R04-R05/R08, H09 | `CodecName`, `CodecWriteOptions`, `CreateIndependentTreeAlphaOptions`, `FluidClientVersion`, `FormatValidator`, `FormatValidatorBasic`, `FormatValidatorNoOp`, `FormatVersion`, `HandleConverter`, `ICodecOptions`, `ITreeAlpha`, `ITreeViewConfigurationAlpha`, `IncrementalEncodingPolicy`, `IndependentViewOptions`, `IndependentViewTelemetryOptions`, `SharedTreeAlpha`, `SharedTreeFormatOptions`, `SharedTreeOptions`, `TreeAlpha`, `TreeCompressionStrategy`, `TreeDataStoreOptions`, `TreeParsingOptions`, `TreeViewAlpha`, `VerboseTree`, `VerboseTreeNode`, `ViewContent`, `asAlpha`, `cloneWithReplacements`, `configuredSharedTreeAlpha`, `createIndependentTreeAlpha`, `createIndependentTreeViewAlpha`, `defineTreeDataStore`, `incrementalEncodingPolicyForAllowedTypes`, `incrementalSummaryHint`, `independentInitializedView`, `independentView`, `instantiateTreeFirstTime`, `replaceConciseTreeHandles`, `replaceHandles`, `replaceVerboseTreeHandles` |
| Observations, identifiers, collection additions: A02-A04/A09-A10 | `ArrayPlaceAnchor`, `DirtyTreeMap`, `DirtyTreeStatus`, `ObservationResults`, `TreeArrayNodeAlpha`, `TreeIdentifierUtils`, `TreeMapNodeAlpha`, `createArrayInsertionAnchor`, `trackDirtyNodes` |
| Transactions/history: H01-H08 | `ChangeMetadata`, `CommitOutcome`, `CommitRevision`, `CustomMetadataTree`, `LabelTree`, `LocalChangeMetadata`, `LocalCommitEvents`, `NoChangeConstraint`, `RemoteChangeMetadata`, `RevertOptionsAlpha`, `RevertToOptionsAlpha`, `RevertibleAlpha`, `RevertibleAlphaFactory`, `RunTransactionParamsAlpha`, `TransactionCallbackStatusAlpha`, `TransactionConstraintAlpha`, `TransactionLabels`, `TransactionPostProcessor`, `TreeBranchAlpha`, `TreeBranchCommitMetadata`, `TreeBranchEvents`, `TreeBranchHistory`, `TreeContextAlpha`, `UntypedTreeViewAlpha`, `VoidTransactionCallbackStatusAlpha`, `minimize` |
| Domain/composition helpers: D01-D02/D05 | `Component`, `FormattedText`, `JsonAsTree`, `PlainText`, `codePointCount`, `utf16LengthForCodePoints` |
| Erased/insertable/unknown-schema type machinery: A13, S03/A05/A06 boundaries | `ErasedNode`, `ErasedSchema`, `ErasedSchemaSubclassable`, `FactoryContent`, `FactoryContentObject`, `Insertable`, `InsertableContent`, `InsertableField`, `InsertableObjectFromSchemaRecordAlpha`, `InsertableObjectFromSchemaRecordAlphaUnsafe`, `JsonCompatibleReadOnly`, `JsonCompatibleReadOnlyObject`, `ReadSchema`, `ReadableField`, `UnsafeUnknownSchema`, `allowUnused`, `contentSchemaSymbol`, `eraseSchemaDetails`, `eraseSchemaDetailsSubclassable` |
| Legacy-beta construction additions: R01/R05/R08, A12/A13 | `SharedTree`, `SharedTreeAttributes`, `SharedTreeFactoryType`, `configuredSharedTreeBetaLegacy`. Legacy/public adds no distinct names to the public inventory. Legacy factories are not independently proved configurations merely because the selected internal factory works. |

### Behavior-bearing member coverage

Overloads are grouped by behavior; a static and instance factory spelling does
not create two independent compatibility claims. Inherited members map to their
base family. Protected constructors/brands/type-check members and JS collection
prototype details are A13, not unlisted runtime gaps.

| Owner / member group | Disposition |
| --- | --- |
| `SchemaFactory`: constructor/scope, `object/objectRecursive`, `array/arrayRecursive`, `map/mapRecursive`, `getStructuralType`, `identifier`; `SchemaStatics`: leaf constants, `leaves`, `optional/optionalRecursive`, `required/requiredRecursive` | S01-S08, A01/A13. Structural names must match actual stored identifiers; JS constructors/classes are not native APIs. |
| `SchemaFactoryBeta`: `record/recordRecursive`, `scopedFactory`, `types/typesRecursive`, `staged/stagedRecursive`; alpha `objectAlpha/objectRecursiveAlpha`, `arrayAlpha`, `mapAlpha`, `recordAlpha`, `scopedFactoryAlpha`, `withDefault/withDefaultRecursive`, `stagedOptional/stagedOptionalRecursive` | S03/S06/S08-S10. Metadata/default/staging arguments inherit their rows rather than a blanket factory support claim. |
| `FieldSchema`: `allowedTypes/allowedTypeSet`, `kind`, `props`, `metadata`, `requiresValue`; alpha `allowedTypesFull/allowedTypesIdentifiers`, `simpleAllowedTypes`, `isStagedOptional`, `persistedMetadata`; annotated types `evaluate/evaluateSet/evaluateIdentifiers`, metadata/type collections | S03/S08-S10, A11/A13. Simple node/field schema properties (`fields`, `storedKey`, definitions/root, kind/leaf kind, metadata, allowed types, unknown-field policy) follow the same rows. |
| `TreeNodeSchemaCore`/class/nonclass: `childTypes`, `createFromInsertable/create`, identifier/info, implicitly-constructable flag, constructors; schema `Symbol.hasInstance` guards | A01/A05/A13. Resulting content is S01-S08. |
| `Tree`/`TreeNodeApi`: `is`, `schema`, `parent`, `key`, `status`, `contains`, `shortId`, `on`, `runTransaction` | A02-A04, H01. Do not equate an Identifier string with `shortId`. |
| `TreeView`/`ViewableTree`: `viewWith`, `initialize`, root read/write, schema, compatibility (`canInitialize/canUpgrade/canView/isEquivalent`), `upgradeSchema`, events, disposal; config constructor/schema/`enableSchemaValidation`/`preventAmbiguity` | S01-S03/S09-S10, A01/A03/A12. Alpha `stagedUpgradePolicy`/`isStagedUpgradeEnabled` and beta discrepancies are S09-S10/A11. |
| `TreeArrayNode`: `insertAt/insertAtStart/insertAtEnd/push`, `removeAt/removeRange`, `moveToStart/moveToEnd/moveToIndex`, `moveRangeToStart/moveRangeToEnd/moveRangeToIndex`, `values`, `spread` and iterable content | S05/A09; all source-array overloads belong to the cross-array movement boundary. Inherited indexed reads, length, iteration, and read-only array helpers are A09/A13. |
| `TreeArrayNodeAlpha`: `at`, `findLast/findLastIndex`, `pop/shift/splice/unshift`; `ArrayPlaceAnchor.index/dispose` | A09-A10, not a claim of JS method parity. |
| `TreeMapNode` and inherited map members: get/has/size, `set/delete`, `entries/keys/values/forEach`, iterator; alpha `clear/getOrInsert/getOrInsertComputed`; record dynamic properties/iterator | S04/S06, A08/A13. Map-key ordering and record property enumeration are not interchangeable guarantees. |
| `TreeChangeEvents*`: `nodeChanged/treeChanged`, `changedProperties`/`delta`, array delta `count/type/subtreeChanged`; `TreeViewEvents`: `rootChanged/schemaChanged/commitApplied`; branch `changed` | A03, H04/H06. Native coalesced mutation events are not upstream per-node deltas. |
| `TreeBeta`/`TreeAlpha`: `create/clone`, `context`, `exportConcise/importConcise`, `exportVerbose/importVerbose`, `exportCompressed/importCompressed`, `tagContentSchema`, `key2`, `child/children`, `on`, `trackObservations/trackObservationsOnce` | A02-A07, A13. `TreeIdentifierUtils` callable/create/getShort/shorten/lengthen are S07/A02/A04; only the declared Identifier-field slice is proved. |
| `TreeIndex` read-only map and `dispose`, identifier-index map, dirty map get/set/status, observation result/unsubscribe | A04; no native automatically maintained equivalent. |
| `RunTransaction` callable overloads and rollback; context/view `runTransaction/runTransactionAsync`; params label/`customMetadata`/`postProcessor`/preconditions; callback success/value/rollback and revert preconditions | H01-H03. Native Result callbacks are a different API contract. |
| `Revertible.status/revert/dispose`, factory disposal callback; alpha clone/options/`customMetadata`; commit `isLocal`, kind, revision, `getChange/getRevertible`, events/settled, label/labels, `LabelTree.sublabels`, custom metadata children | H04-H05, A03. Native remote commit events do not grant remote undo factories. |
| `UntypedTreeView*`: fork/merge/`rebaseOnto`/dispose/isView/isBranch, `hasRootSchema`, `applyChange`, `computeNetChangeIfRebasedOnto`, `isMissingEditsFrom`, `revertTo/rewindTo`; branchHistory `getHead`/length and commit getParent/revision/custom/customTree | H06-H08, A07. Historical and raw-change tools are not the native diagnostic history export. |
| `ITreeAlpha`: `createSharedBranch`, `getSharedBranchIds/getSharedBranchName`, `viewSharedBranchWith`, `exportSimpleSchema/exportVerbose` | H09/A06/A11. Ordinary local fork/merge does not cover shared-branch methods. |
| SharedTree options: `minVersionForCollab`, `writeVersionOverrides`, `allowPossiblyIncompatibleWriteVersionOverrides`, `jsonValidator`, forest, `treeEncodeType`, `shouldEncodeIncrementally`, `enableSharedBranches`, `healUnresolvableIdentifiersOnDecode`, `retainHistory`, `validateCommitsOnFirstSubmission`, `validateRebasedCommitsBeforeResubmission` | A12, R01-R04/R10/H09. Every relevant write format must stay inside the pinned envelope. |
| Independent tree options, logger/`idCompressor`, `ViewContent` schema/tree/idCompressor; tree datastore config/initializer/key/registry; `KeyEncodingOptions.allStoredKeys/knownStoredKeys/usePropertyKeys` and encoding `keys` | A06-A07, R02/R05/R08. Not arbitrary datastore factory support or an upstream import/export API in the native facade. |
| `StagedSchemaUpgradePolicy*`: `includeAlreadyEnabledUpgrades/includeStaged/includeStagedOptional`, `enabledStagedUpgrades`, permissive/restrictive | S10. This includes the `AllowedTypeMetadata.stagedSchemaUpgrade`, `FieldPropsAlpha.stagedOptionalUpgrade`, and simple-schema `isStaged` properties. |
| Snapshot filesystem `join/mkdirSync/readdirSync/readFileSync/writeFileSync`; snapshot options `fileSystem`, `minVersionForCollaboration`, `mode`, `rejectSchemaChangesWithNoVersionChange`, `rejectVersionsWithNoSchemaChange`, schema/version, `snapshotDirectory`, `snapshotFileNameFormat`, `snapshotUnchangedVersions`, `versionComparer` | A11. These are local schema-version audit tools, not proof of cross-version collaboration. |
| Schema representations: metadata `custom/description`, persisted metadata, JSON Schema `items`, `patternProperties` (`"^.*$"`), `additionalProperties`, properties/required, `$ref`, type/`_treeNodeSchemaKind`; simple `leafKind`; `TreeSchemaEncodingOptions.requireFieldsWithDefaults`; `FieldProps.defaultProvider` | S08-S10/A11. Representation types are not new collaboration formats by themselves; field default behavior needs the S08 qualification. |
| `PlainText`: `characterCount`, characters/`charactersCopy`/fullString, insertAt/removeRange, `createInsertionAnchor`, `onCharactersChanged`, `fromString`, text/count/type/`formattingChanged` delta members | D02, A03/A09-A10. Code-point utilities are local helpers, not the separate Watershed text DDS. |
| `FormattedText`: content/format atoms, schema creation, `charactersWithFormatting/getString/getUniformRun`, `insertAt/insertWithFormattingAt/reformat/formatRange/onContentChanged`, `fromCharacter/fromString` | D02. Formatting atoms can compose other schemas; no native text-domain claim follows from primitive array coverage. |
| `TableSchema`: column/row/table factories, id/props/cell, rows/columns, `getCell/getColumn/getRow`, `insertColumns/insertRows`, `removeCell/removeColumns/removeRows/setCell`, row/column keys; system createColumnSchema/createRowSchema/createTableSchema, rearrangeable-list moves, `schemaFactory`/props options | D03. Type-level system helpers inherit the table boundary, not independent API-parity gaps. |
| `JsonAsTree` and `FluidSerializableAsTree`: primitive/tree unions, object/array schemas and classes, recursive declaration workarounds | D01/S03/S06/A13. No dedicated domain continuation claim. |
| `ExtensibleUnionNode`: createSchema/create, isValid/union; enum/singleton generated factories | D04/S03/S08/S10. |
| `Component`: compose/memoize/configure, components/config/getComponent/getComposed/getConfigured | D05/A13; local JS configuration. |
| Runtime enum values: `FieldKind.Required/Optional/Identifier`, `NodeKind.Array/Leaf/Map/Object/Record`, `TreeStatus.New/InDocument/Removed/Deleted`, `RevertibleStatus.Valid/Disposed`, `CommitKind.Default/Undo/Redo`, `CommitOutcome.FullyApplied/FullyDropped/NewContentOnly` | S01-S07/A02/H04. Native result/status types are not identical JS enums; no additional native feature is implied by listing variants. |
| Encoding enum values: `TreeCompressionStrategy.Compressed/CompressedIncremental/Uncompressed`; `FluidClientVersion.v2_0/v2_43/v2_52/v2_73/v2_74/v2_80/v2_117`; `ValueSchema.Boolean/FluidHandle/Null/Number/String`; `SchemaType.Stored/View` | R01-R04/S01/A11. Version-selector constants are not supported-version claims. |
| `System_Unsafe`, `InternalTypes`, unsafe/customizable/POJO schema variants, erased schema helpers, `_typeCheck`, `[schemaIdentifierBrand]`, `[typeSchemaSymbol]`, `[Symbol.hasInstance]`, `[Symbol.iterator]`, `[Symbol.toStringTag]`, insertion/recursive utility aliases | A13 plus their corresponding schema/collection/builder rows. Inherited map/array/node behavior and `implicitlyConstructable` are accounted for above; none authorizes unsupported content. |

## Maintenance

Update the affected rows, coverage mappings, and evidence references when a
package pin, schema/runtime scope, facade behavior, or proof changes. New
supported claims need matching evidence for the relevant target, direction,
and lifecycle phase. Keep known gaps and unassessed impact distinct.

This report interprets the existing contract; it does not silently amend
`profile.json`. Profile-label changes require updating their source in
`service.mjs`, regeneration, and renewed evidence under the resulting digest.
Keep historical acceptance records intact and identify the profile they prove.

[profile]: ../test/fixtures/shared_tree/profile.json
[compression-profile]: ../test/fixtures/shared_tree/compression-profile.json
[service]: ../tools/shared-tree-oracle/service.mjs
[roadmap]: superpowers/plans/2026-09-21-shared-tree.md
[acceptance]: superpowers/plans/2026-09-21-shared-tree.md#m7-supported-profile-acceptance--2026-10-14
[recipes]: ../justfile
[js]: ../src/watershed.gleam
[beam]: ../src/watershed_beam.gleam
[typed]: ../src/watershed/tree/typed.gleam
[schema]: ../src/watershed/tree/schema.gleam
[kernel]: ../src/watershed/tree_kernel.gleam
[transactions]: ../src/watershed/tree/transaction.gleam
[handles]: ../src/watershed/handle.gleam
[container-codec]: ../src/watershed/wire/fluid_container.gleam
[field-batch]: ../src/watershed/tree/codec/field_batch.gleam
[summary-codec]: ../src/watershed/tree/codec/summary.gleam
[document]: ../src/watershed/wire/fluid_document.gleam
[up-container-loader]: https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/loader/container-loader/src/container.ts#L2412-L2491
[up-datastore-factory]: https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/runtime/container-runtime/src/dataStoreContext.ts#L602-L695
[typed-tests]: ../test/watershed/shared_tree_typed_schema_test.gleam
[typed-facade-tests]: ../test/watershed/shared_tree_typed_facade_test.gleam
[node-tests]: ../test/watershed/shared_tree_node_test.gleam
[map-tests]: ../test/watershed/shared_tree_map_kernel_test.gleam
[array-tests]: ../test/watershed/shared_tree_array_facade_test.gleam
[id-tests]: ../test/watershed/shared_tree_ids_test.gleam
[summary-tests]: ../test/watershed/shared_tree_summary_test.gleam
[reference-bootstrap]: ../tools/shared-tree-oracle/summary-interop.test.mjs
[document-tests]: ../test/watershed/shared_tree_document_summary_test.gleam
[recovery-tests]: ../test/watershed/shared_tree_document_recovery_test.gleam
[schema-evidence]: ../test/watershed/shared_tree_schema_test.gleam
[array-evidence]: ../test/fixtures/shared_tree/cases/array-schema-content.json
[identifier-evidence]: ../test/fixtures/shared_tree/cases/identifier-values.json
[evolution-evidence]: ../test/fixtures/shared_tree/cases/schema-evolution-compatibility.json
[transaction-evidence]: ../test/watershed/shared_tree_transaction_test.gleam
[undo-evidence]: ../test/watershed/shared_tree_undo_test.gleam
[branch-evidence]: ../test/fixtures/shared_tree/cases/local-branch-rebase.json
[lifecycle-evidence]: ../test/fixtures/shared_tree/cases/handle-leaves.json
[codec-gate]: ../tools/shared-tree-oracle/codec-interop.mjs
[core-gate]: ../tools/shared-tree-oracle/interop.mjs
[client-gate]: ../tools/shared-tree-oracle/client-interop.mjs
[creation-gate]: ../tools/shared-tree-oracle/creation.mjs
[layout-gate]: ../tools/shared-tree-oracle/layout-interop.mjs
[lifecycle-gate]: ../tools/shared-tree-oracle/lifecycle-interop.mjs
[alias-gate]: ../tools/shared-tree-oracle/alias-interop.mjs
[recovery-gate]: ../tools/shared-tree-oracle/recovery-interop.mjs
[compression-gate]: ../tools/shared-tree-oracle/compression-interop.mjs
[native-workflow]: ../.github/workflows/shared-tree.yml
[service-workflow]: ../.github/workflows/shared-tree-interop.yml
[readme-recovery]: ../README.md#recover-pending-tree-edits
[readme-limits]: ../README.md#limits
[upstream]: https://github.com/microsoft/FluidFramework/tree/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960
[up-entry]: https://github.com/microsoft/FluidFramework/tree/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/dds/tree/src/entrypoints
[up-index]: https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/dds/tree/src/index.ts
[up-api]: https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/dds/tree/api-report/tree.alpha.api.md
[up-public]: https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/dds/tree/api-report/tree.public.api.md
[up-beta]: https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/dds/tree/api-report/tree.beta.api.md
[up-legacy-public]: https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/dds/tree/api-report/tree.legacy.public.api.md
[up-legacy]: https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/dds/tree/api-report/tree.legacy.beta.api.md
[up-aggregator]: https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/framework/fluid-framework/src/index.ts
[up-stored]: https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/dds/tree/src/simple-tree/toStoredSchema.ts
[up-record]: https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/dds/tree/src/simple-tree/node-kinds/record/recordNode.ts
[up-map]: https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/dds/tree/src/simple-tree/node-kinds/map/mapNode.ts
[up-array]: https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/dds/tree/src/simple-tree/node-kinds/array/arrayNode.ts
[up-options]: https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/dds/tree/src/shared-tree/sharedTree.ts
[up-incremental]: https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/dds/tree/src/feature-libraries/chunked-forest/codec/incrementalEncodingPolicy.ts
[up-json]: https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/dds/tree/src/jsonDomainSchema.ts
[up-serializable]: https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/dds/tree/src/serializableDomainSchema.ts
[up-text]: https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/dds/tree/src/text/textDomain.ts
[up-formatted]: https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/dds/tree/src/text/textDomainFormatted.ts
[up-table]: https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/dds/tree/src/tableSchema.ts
[up-union]: https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/dds/tree/src/extensibleUnionNode.ts
[up-component]: https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/dds/tree/src/componentApi.ts
