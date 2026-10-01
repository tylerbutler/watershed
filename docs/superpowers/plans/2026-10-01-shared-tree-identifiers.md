# Native SharedTree Identifier Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development or superpowers:executing-plans to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for
> tracking. Read the contracts and constraints before assigning a task.

**Goal:** Read, author, synchronize, and summarize Fluid 3.1.0 Identifier
fields on JavaScript and BEAM, preserving the existing transaction oracle
instead of replacing its Identifier fields with ordinary fields.

**Architecture:** Keep identifier contents as `StringValue` and use the
document's existing `fluid_ids.Compressor`. Preserve the Identifier field
kind in schema metadata, enforce its read-only semantics, and generate
defaults only when authoring new content. Pass explicit ID contexts through
FieldBatch decoding and encoding, including builds, refreshers, forests,
and historical commits.

**Tech Stack:** Dual-target Gleam, startest, Node's test runner, the pinned
Fluid source/package oracle, and the existing Floodgate interoperability gates.

**Spec:** This plan extends the Identifier-field boundary of the
[SharedTree design](../specs/2026-09-21-shared-tree-design.md) and supplies a
prerequisite for the [transaction design](../specs/2026-09-29-shared-tree-transactions-design.md).
Section 2 below defines this extension's behavioral contract. The
[transaction implementation plan](2026-09-29-shared-tree-transactions.md)
remains the authority for completing transaction Tasks 8–11.

**Status:** Planning only. No Identifier implementation accompanies this
document. The user requested a plan for a follow-up session.

## Global Constraints

- Production semantics must run in pure Gleam on JavaScript and BEAM.
- Upstream TypeScript packages remain development and test dependencies.
- Use `@fluidframework/tree` version `3.1.0`.
- Use Fluid Framework commit
  `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960` (`client_v3.1.0`).
- Use Floodgate commit `0eb493fc46d1bb9baf1151a6ccdde93544e057e7`.
- Keep `minVersionForCollab` at `2.117.0`.
- Keep Message V7, SharedTreeChange V5, ModularChange V5, Schema V2, and
  nonincremental FieldBatch V2.
- Preserve the fixed container layout and existing M1–M4 interoperability.
- Preserve transaction Tasks 2–7, including constraint author order,
  revision squashing, reference preservation, and BEAM deferred delivery.
- Reject corrupt or unsupported input with typed errors. Do not substitute a
  guessed ID, empty value, generated UUID, or successful no-op.
- Generate expected observations from pinned upstream behavior. Do not edit
  expected results to match the native implementation.
- Keep the transaction oracle's `sf.identifier` fields and complete
  Identifier-bearing builds, refreshers, summaries, and messages.
- Do not add a second compressor, per-tree allocator, random-ID default
  provider, or JavaScript-only Identifier engine.
- Do not change upstream versions, registry policy, or dependency lockfile
  URLs to get a failing gate to pass.
- Apply ASD-STE100 to Gleam comments and error strings, not Markdown prose.
- Do not edit `.code-map/`, generated website snippets, or apm-managed files.
- Never stage `.superpowers/` reports or session artifacts.
- Before each commit, inspect the staged diff and exclude unrelated work.
  Directory-wide `git add` examples below assume only that task's files
  changed; use explicit paths in a shared or dirty worktree.
- Do not add co-author trailers, amend existing commits, or push without
  authorization.

---

## 1. Starting point and execution handoff

Planning baseline:
`afc32c65d6169bcc8392c20ed81edaf72bfc5ceb`
(`fix(tree): propagate reconnect settlement errors`).

The tracked worktree was clean when this plan was researched. The previous
implementation used `main` with explicit user approval. Check the execution
session's workspace and user instructions before choosing its branch; do not
assume a future checkout has the same state.

### Existing work to preserve

| Area | Current implementation |
| --- | --- |
| Document IDs | `fluid_ids.gleam` already allocates, finalizes, serializes, decompresses, and normalizes session/op-space IDs. |
| Transactions | Pure nested state, runtime-core routing, both callback APIs, single BEAM caller ownership, deferred remote delivery, and reconnect cleanup are implemented. |
| Constraint identity | Constraints use forest references, not user-visible identifier strings. Nested constraints compose at their author boundary. |
| Rollback | Abort preserves ongoing local compressor advancement and the forest's nonserialized reference watermark. Summary/document state restores. |
| No-op finish | `NoCommit(state, compressor)` returns restored state and the base compressor. Consumers must install both. |
| Reference promotion | Finish preserves attached and retained detached references while canonicalizing revision and repair metadata. |
| Transaction proof | Parent Tasks 8–11 remain incomplete. The native persistence/corpus gate exposed the Identifier boundary. |

### Correct the earlier blocker diagnosis

The transaction oracle's `Point.id` uses `sf.identifier`. The pinned
`schemaFactory.ts` defines this as a read-only field containing a **string**.
Its default provider also constructs an ordinary string leaf.

The committed transaction fixture contains no
`com.fluidframework.node.identifier` nodes. That name appears in a native
rejection branch, but it is not the representation that blocks these
fixtures. Do not create an `IdentifierValue` variant in `TreeValue` or enable
an invented node schema to work around this.

The actual missing pieces are:

1. Stored/view support for the persisted `"Identifier"` field kind.
2. Immutable field behavior and default generation during local construction.
3. FieldBatch's special `value: 0` representation, which can contain a literal
   string or an op-space compressed integer.
4. Compressor/originator context at every decoder that can encounter that
   representation.
5. Identifier-aware outbound encoding, including originatorless summaries.

### Known environment blockers

The preceding Task 8 investigation reported that `source:verify` rejected the
owned injected `watershedCodecs.spec.ts` as stale, and that the transaction
injection was absent. The checkout itself was at the pinned commit with no
tracked diff. Task 1 below repairs this using the documented injection
workflow; do not discard unrelated reference changes.

The preceding Task 7 build reached browser dependency installation and hit
the active supply-chain URL policy. Existing pnpm lockfiles contain Microsoft
feed URLs. Do not rewrite them or bypass the policy. Record a remaining build
block separately from Identifier test results. Reproduce any claimed
pre-existing failure at the execution baseline before calling it baseline.

### Execution order

```text
1 pinned Identifier contract and reproducible capture
           |
2 schema identity and read-only field semantics
           |
3 contextual FieldBatch decoding and encoding
           |
4 wire, forest summary, and history context integration
           |
5 local defaults and container initialization
           |
6 native transaction, recovery, and oracle parity
           |
7 mixed-client persistence and permanent gates
           |
resume transaction plan Tasks 8 -> 9 -> 10 -> 11
```

Use one integration owner for Tasks 2–5. They share schema, validation,
compressor, and codec contracts. Do not parallelize changes to those contracts.
Each task ends with a testable deliverable and a scoped commit. Run focused
tests while iterating; run the full gates at closure.

## 2. Identifier support contract

### 2.1 Values, field kinds, and identity

- Represent the content of an Identifier field as `StringValue(String)`.
- Preserve `"Identifier"` in Schema V2 serialization. Do not serialize it as
  `"Value"` just because both require one child.
- Support Identifier object fields whose allowed type is the pinned string
  leaf, `com.fluidframework.leaf.string`.
- Object nodes containing these fields can appear at the document root or
  inside supported object, map, and array structures.
- Retain existing unsupported placements unless the pinned source corpus
  proves that the public profile needs them. This plan does not promise
  arbitrary low-level Identifier root/map field schemas.
- Accept explicit user strings, including non-UUID strings and duplicate
  values. Fluid places the uniqueness obligation for custom IDs on the user.
- Allow more than one Identifier field on an object.
- Generate a missing identifier when inserting new object content. Do not
  generate identifiers while loading, validating, reading, rebasing, or
  decoding persisted content.
- Reject direct assignment and clearing of an attached Identifier field,
  including same-value assignment. Replacing its containing object is a new
  node insertion and can provide or generate that new object's identifiers.
- Keep `NodeRef`, compressed document IDs, revision IDs, and user-visible
  Identifier strings distinct. Two nodes with equal custom strings remain
  different nodes for moves, references, and `NodeInDocument` constraints.

### 2.2 FieldBatch and ID contexts

The pinned `SpecialField.Identifier` value-shape discriminator is numeric
zero. A decoder must distinguish it from the identifiers table, whose
integer entries name schema types and field keys.

| Encoded Identifier content | Required behavior |
| --- | --- |
| Literal string | Preserve its bytes; UUID parsing is not required to read it. |
| Safe integer in a message | Convert op-space to session-space using the message's author session, then decompress with the document compressor. |
| Final safe integer in a forest summary | Resolve without assuming an author session. Use the summary's compressor state. |
| Negative integer in an originatorless summary | Return a typed error. Do not interpret it using the reader's local session. |
| Unknown ID, missing creation range, fraction, unsafe integer, Boolean, null, array, or object | Return a typed error at the encoded value's location, without partial state changes. |

Encoding must follow the pinned `encodePossiblyCompressedId` behavior:

- Preserve arbitrary strings and UUIDs unknown to the compressor as strings.
- For a known stable UUID, use `recompress` and `to_op`.
- A message may encode a known negative op-space ID because its originator is
  available.
- A summary may encode only a finalized numeric ID. If a known ID remains
  negative in op-space, write its stable string instead.
- Do not allocate or finalize IDs merely to make an encoder succeed.
- Leave the current uncompressed encoder valid for contexts without stored
  schema. Add Identifier-specific encoding to the schema-aware path; do not
  rebuild the general compressed-shape optimizer.

Strings in Identifier fields may include externally supplied UUIDv5 values.
Read them as strings. Do not relax `fluid_ids.StableId` to accept UUIDv5, and
do not add Fluid's optional historical-summary healing mode in this scope.

### 2.3 Defaults and allocation

Use the existing document compressor:

```gleam
use #(compressor, local) <- result.try(fluid_ids.generate(compressor))
use stable <- result.try(fluid_ids.decompress(compressor, local))
let identifier = types.StringValue(fluid_ids.stable_id_to_string(stable))
```

The implementation must map `IdError` into the existing typed tree error
boundary with a literal location and explanation. Do not return an empty ID.

Materialize defaults in an immutable candidate before strict content
validation and before recording an authored change. Publish the candidate
compressor only when the edit succeeds. The Task 1 oracle must establish
allocation order across identifier defaults and commit revisions, including
multiple identifier fields and nested object construction.

Only new content receives defaults: `SetField` replacements, `MapSet` values,
`ArrayInsert` elements, and initial container roots. Moves and removals must
not mint identifiers. Public reads use the existing tree read APIs.

Preserve the distinction between:

- an invalid edit that returns no successful authored state;
- an authored edit that later rolls back and preserves ongoing local
  compressor advancement;
- an outer no-op that returns the base compressor under the existing
  transaction contract.

Do not call `take_creation_range` or `finalize` inside an ordinary local edit
or callback. Keep allocation emission at the existing outer submission
boundary. Initial container summaries must use the pinned originatorless
encoding rule rather than invent a sequenced allocation operation.

### 2.4 Schema evolution and change algebra

Keep the existing monotonic schema comparison rules:

- Identifier to required string can widen.
- Required string to Identifier does not widen.
- Changing Identifier to another field kind must not preserve Identifier
  read-only/default behavior after the stored schema changes.
- Wider views must not grant mutation rights that the active stored
  Identifier schema forbids.
- Do not add schema upgrades inside transactions.

The pinned Identifier field change handler is a no-change handler. Its
canonical V1 encoding is `0`. It cannot author nested edits. Add a
zero-argument `IdentifierField` constructor to `change.FieldChange` to
preserve this dispatch. Do not route it through mutable value/optional
replacement handlers or serialize it as a generic field.

The upstream `unitCodec` ignores its encoded argument when decoding. The
native boundary may remain stricter by accepting canonical `0` only, provided
the supported-profile documentation names that restriction and the native
encoder emits `0`. Do not claim byte-preserving support for arbitrary
noncanonical payloads.

### 2.5 Exclusions

This plan does not add handles, incremental FieldBatch chunks, arbitrary
container layouts, `Tree.shortId`, an identifier index, global uniqueness
checks for user IDs, a detached JavaScript-style node-builder API, UUIDv5
healing, undo/redo, or asynchronous/cross-tree transactions.

Completion closes Identifier-field interoperability for the declared
profile. It does not establish compatibility with every Fluid SharedTree
feature or document.

## 3. Source and file map

Line numbers below identify the planning baseline. Use `code-map` and read
current source before editing; do not apply changes by stale offsets.

### Native boundaries

| File | Responsibility and current gap |
| --- | --- |
| `src/watershed/tree/schema.gleam` | Already parses `IdentifierKind` for comparisons, but rejects it from the stored/view profile and maps its public field to ordinary `Required`. |
| `src/watershed/tree/types.gleam` | Existing `StringValue`, `ObjectValue`, and `Edit` representation. No new Identifier value variant is required. |
| `src/watershed/fluid_ids.gleam` | Reuse `generate`, `decompress`, `recompress`, `to_op`, `from_op`, creation ranges, and serialization. |
| `src/watershed/tree/codec/field_batch.gleam:330–338,764–785` | Both shape parsing and value decoding reject Identifier values. Recursive decoding currently has no compressor/originator argument. |
| `src/watershed/tree/codec.gleam:1403–1416,1865–1880` | Build/refresher FieldBatch calls omit ID context even though the enclosing codec has compressor and originator data. |
| `src/watershed/tree/codec/summary.gleam:197,251–322` | Forest decoding and encoding lack contextual Identifier support. History already has commit/session contexts; do not replace them with the forest context. |
| `src/watershed/tree/change.gleam:5557–5661` | Destination validation and field authoring currently treat public required fields as mutable. Preserve Identifier semantics here. |
| `src/watershed/tree/runtime.gleam:257–337` | Ordinary and transaction preview authoring share validation/allocation; both currently validate before any default materialization. |
| `src/watershed/tree/identifier.gleam` (new) | One focused helper for materializing missing Identifier defaults in new content. Do not put wire compression logic here. |
| `src/watershed/tree_kernel.gleam` | Strict kernel validation, local previews, remote application, snapshots, and identity preservation. It must not generate defaults on replay. |
| `src/watershed/runtime_core.gleam` | Document compressor ownership, ordered allocations, transaction submission, resubmit, and snapshot-point summary selection. |
| `src/watershed/container.gleam:128–138` | Initial content validation currently rejects missing defaults before initial document construction. |
| `src/watershed/wire/fluid_document.gleam:33–51,143–162` | Initial summary starts with supplied content and a fresh compressor. Wire in default materialization and its resulting compressor together. |
| `test/watershed/tree/transaction_fixture.gleam:296,346–365` | The wire-only runner strips builds/refreshers. Remove this workaround after contextual decoding succeeds. |

### Pinned upstream authority

All paths in this table are relative to
`tools/shared-tree-oracle/.reference/FluidFramework/packages/dds/tree/src/`.

| Path | Inspect and capture |
| --- | --- |
| `simple-tree/api/schemaFactory.ts:741–769` | Read-only string, optional construction input, defaults, custom IDs, duplicate IDs, multiple Identifier fields. |
| `simple-tree/api/identifierDefaultProvider.ts` | Hydrated document allocation versus detached/global allocation. Native scope uses document-backed construction. |
| `feature-libraries/node-identifier/nodeIdentifierManager.ts` | Generate, stabilize, localize, and try-localize semantics. |
| `feature-libraries/default-schema/defaultFieldKinds.ts:35–68` | Single multiplicity, no-change handler, schema upgrade direction. |
| `feature-libraries/default-schema/noChangeCodecs.ts` and `codec/codec.ts:418–426` | Canonical zero payload and upstream permissive unit decoding. |
| `feature-libraries/chunked-forest/codec/format/formatV1.ts:62–66` | `SpecialField.Identifier = 0`. |
| `feature-libraries/chunked-forest/codec/schemaBasedEncode.ts:147–178` | Identifier-specific string-leaf shape. |
| `feature-libraries/chunked-forest/codec/nodeEncoder.ts:71–79` | Compress only Identifier values selected by schema. |
| `feature-libraries/chunked-forest/codec/chunkDecoding.ts:237–277` | String passthrough and contextual integer decoding. |
| `util/compressedIds.ts:73–99,110–160` | Message versus summary numeric encoding, originatorless normalization, string fallback. |
| `test/simple-tree/identifierIndex.spec.ts` | User-ID duplication and identity-related behavior; reference only, do not implement an index. |

### Tests and oracle plumbing

- Extend existing schema, field-batch, codec, summary, creation, runtime,
  transaction, and facade tests at their current boundaries.
- Add `test/watershed/shared_tree_identifier_test.gleam` for default-generation
  and cross-boundary Identifier cases.
- Add `test/watershed/tree/identifier_fixture.gleam` for input-only corpus
  execution and shared Identifier schema construction.
- Add `tools/shared-tree-oracle/upstream-identifier.spec.ts` as a dedicated
  source capture. Register it in `source.mjs`, source capture assembly,
  `generate.mjs`, and their tests using the existing transaction pattern.
- Extend `upstream-codecs.spec.ts`, `codec-interop.mjs`, and
  `test/watershed/tree/codec_export.gleam` so pinned upstream consumes native
  Identifier output. Inspect their existing item protocol before extending it.
- Extend service/client/summary fixtures through the existing
  `schema.mjs`, `client-driver.mjs`, `client-interop.mjs`,
  `summary-interop.mjs`, `interop-scenarios.mjs`, `interop.mjs`, and
  `service.mjs`, with their named tests.

## 4. Shared implementation interfaces

These signatures define ownership between tasks. Keep old context-free codec
functions as wrappers for existing callers. Add contextual functions rather
than silently choosing an originator.

### Schema, owned by Task 2

Preserve field behavior in the existing public field definition:

```gleam
pub type Cardinality {
  Required
  Optional
  Sequence
  Identifier
}
```

`FieldSchema(Identifier, [string_leaf])` has single cardinality plus
Identifier semantics. Audit all exhaustive `Cardinality` matches, including
test fixtures. Do not refactor the whole schema representation for this
extension.

Keep `schema.validate_root`, `validate_root_field`, `validate_subtree`, and
`validate_field` strict: stored tree content must include its identifier.
Default materialization is a separate authoring operation.

### FieldBatch, owned by Task 3

Define the context in `field_batch.gleam`, not `codec.gleam`, to avoid an
import cycle:

```gleam
pub type IdContext {
  MessageIds(
    compressor: fluid_ids.Compressor,
    originator: fluid_ids.SessionId,
  )
  SummaryIds(compressor: fluid_ids.Compressor)
}

pub fn decode_with_context(
  encoded: Json,
  stored: Option(schema.StoredSchema),
  ids: IdContext,
) -> Result(List(List(TreeValue)), TreeError)

pub fn encode_with_context(
  fields: List(List(TreeValue)),
  stored: Option(schema.StoredSchema),
  ids: IdContext,
) -> Result(Json, TreeError)
```

Existing `decode` and `decode_with_schema` retain their arity. They can read
literal Identifier strings without context, but must reject compressed
numeric Identifier values if no context exists. Existing uncompressed
`encode` functions remain usable. Private traversal may take
`Option(IdContext)` so context-free wrappers cannot invent a compressor.

### Forest summaries, owned by Task 4

Add these contextual entry points beside existing wrappers:

```gleam
pub fn decode_forest_with_context(
  encoded: Json,
  stored: schema.StoredSchema,
  compressor: fluid_ids.Compressor,
) -> Result(ForestSummary, TreeError)

pub fn encode_forest_with_context(
  value: ForestSummary,
  stored: schema.StoredSchema,
  compressor: fluid_ids.Compressor,
) -> Result(Json, TreeError)
```

Full summary encode/decode must call these, using `SummaryIds`.
Message builds and refreshers use the enclosing `ChangeContext` purpose and
originator. Historical summary commits must honor the ID mode used by their
existing summary codec; a fresh reader session is not an author session.

### Default materialization, owned by Task 5

In `watershed/tree/identifier.gleam`:

```gleam
pub fn materialize_value(
  stored: schema.StoredSchema,
  value: types.TreeValue,
  compressor: fluid_ids.Compressor,
) -> Result(#(types.TreeValue, fluid_ids.Compressor), types.TreeError)

pub fn materialize_edit(
  stored: schema.StoredSchema,
  edit: types.Edit,
  compressor: fluid_ids.Compressor,
) -> Result(#(types.Edit, fluid_ids.Compressor), types.TreeError)
```

The helper fills missing Identifier object fields, recurses through supplied
objects/maps/arrays, and leaves explicit values intact. It must not fill
ordinary missing required fields, add optional objects, normalize custom
strings, or change any forest state.

`materialize_edit` handles value-bearing `SetField`, `MapSet`, and
`ArrayInsert`. For clear/delete/remove/move operations it returns the original
edit and compressor. Callers perform destination validation and strict
validation on the candidate before recording it.

### Corpus adapter, owned by Tasks 1 and 6

Use one input-only entry point:

```gleam
pub fn run(input: Json) -> Result(Json, String)
```

Its input contains versioned, explicit actions and the initial schema,
content, compressor state, sessions, and sequencing required to execute
them. Its output contains measured observations. Fixture test code alone
compares that output to `fixture.expected`.

Do not pass `expected`, `raw` observations, or a precomputed final tree to the
runner. Source-side capture must include executable inputs, not merely a list
of scenario labels.

## 5. Implementation tasks

### Task 1: Capture and verify the pinned Identifier contract

**Files:**
- Create: `tools/shared-tree-oracle/upstream-identifier.spec.ts`
- Modify: `tools/shared-tree-oracle/source.mjs`
- Modify: `tools/shared-tree-oracle/source.test.mjs`
- Modify: `tools/shared-tree-oracle/generate.mjs`
- Modify: `tools/shared-tree-oracle/generate.test.mjs`
- Modify: `tools/shared-tree-oracle/upstream-codecs.spec.ts`
- Modify: `tools/shared-tree-oracle/README.md`
- Generate: Identifier case files, manifest entries, and capture metadata
  under `test/fixtures/shared_tree/` through the existing generator

**Interfaces:**
- Consumes: the pinned source/package and existing injection/capture protocol.
- Produces: cases `identifier-schema`, `identifier-values`,
  `identifier-field-batches`, and `identifier-persistence`, each with
  input-only executable actions and upstream observations.

- [ ] **Step 1: Record execution state and run the existing source checks.**

  ```bash
  git status --short
  git rev-parse HEAD
  npm --prefix tools/shared-tree-oracle run source:verify
  npm --prefix tools/shared-tree-oracle run check
  ```

  Do not declare the corpus reproducible if these commands fail.

- [ ] **Step 2: Repair only verified stale owned injections, if present.**

  The known reported path is
  `tools/shared-tree-oracle/.reference/FluidFramework/packages/dds/tree/src/test/watershedCodecs.spec.ts`.
  Compare it with `tools/shared-tree-oracle/upstream-codecs.spec.ts` and
  inspect its tracked/untracked status:

  ```bash
  git -C tools/shared-tree-oracle/.reference/FluidFramework status --short
  git diff --no-index -- \
    tools/shared-tree-oracle/.reference/FluidFramework/packages/dds/tree/src/test/watershedCodecs.spec.ts \
    tools/shared-tree-oracle/upstream-codecs.spec.ts
  ```

  A diff exit status of 1 means the files differ. Confirm the old file is an
  owned injection before removing that exact file as documented in the
  oracle README. Preserve a copy in the execution session's artifacts.
  Then run `npm --prefix tools/shared-tree-oracle run source:prepare`.
  Review each further stale injection separately. Do not use `git clean`,
  reset the reference repository, or modify tracked upstream source.

- [ ] **Step 3: Add failing corpus registration and completeness tests.**

  Require all four case IDs. Remove one case, its compressor, a numeric-ID
  action, and one expected observation in separate mutation tests; each
  mutated capture must fail validation.

  ```javascript
  assert.throws(
    () => validateCapture(withoutIdentifierCase(capture, "identifier-field-batches")),
    /identifier-field-batches/,
  );
  ```

  Implement `withoutIdentifierCase` as a test-local copy/filter using the
  existing capture shape. Do not weaken the validator to make this test pass.

- [ ] **Step 4: Capture the following exact scenario matrix.**

  | Case | Scenarios and observations |
  | --- | --- |
  | `identifier-schema` | Valid object Identifier string field; two Identifier fields; non-string and union restrictions; Identifier-to-Value widening; forbidden reverse upgrade; canonical Identifier field change encoding. |
  | `identifier-values` | Supplied custom string, empty string, UUID, duplicate custom strings, omitted default, multiple defaults, nested object/map/array insertion, direct assignment refusal, clear refusal, parent replacement. Record allocation order relative to revisions. |
  | `identifier-field-batches` | `value: 0` literal strings; local negative op IDs; remote finalized IDs; eager final IDs; unknown UUID string fallback; same ID encoded for message and summary; unfinalized summary string fallback; numeric originatorless refusal; invalid payload shapes. |
  | `identifier-persistence` | Initial summary with generated defaults; native-compatible summary plus tail; pending transaction abort; nested abort; retry/resubmit; remove-and-retain repair data; replacement with equal custom ID; node moves. |

  Use upstream assertions on local refusal and immutable data, not only
  normalized output. Record the original error separately from the native
  error category; target-specific exception wording is not a parity contract.

- [ ] **Step 5: Make the input actions sufficient for native execution.**

  Define explicit action records, for example:

  ```json
  {
    "op": "insert",
    "path": ["items"],
    "index": 0,
    "value": {
      "schema": "org.watershed.shared-tree.identifiers.Point",
      "fields": {"label": "generated"}
    }
  }
  ```

  Publish the complete action schema in the oracle README. Include schema
  JSON, initial tree, fixed sessions, initial compressor serialization,
  ID-range delivery, and message/summary purpose in fixture input. Use
  `createIdCompressor` with recorded sessions; do not replace generated IDs
  with labels in output.

- [ ] **Step 6: Run capture, generation, validation, and reproducibility.**

  ```bash
  npm --prefix tools/shared-tree-oracle run source:verify
  npm --prefix tools/shared-tree-oracle run source:capture
  npm --prefix tools/shared-tree-oracle run generate
  npm --prefix tools/shared-tree-oracle run check
  node --test tools/shared-tree-oracle/source.test.mjs tools/shared-tree-oracle/generate.test.mjs
  ```

  Run capture and generation again. Existing transaction scenario semantics
  must remain unchanged; explain generated differences rather than accepting
  an unexplained corpus rewrite. Stop before native changes if the captured
  allocation schedule contradicts section 2.

- [ ] **Step 7: Commit the source contract.**

  ```bash
  git add tools/shared-tree-oracle test/fixtures/shared_tree
  git commit -m "test(tree): capture identifier contract"
  ```

### Task 2: Preserve Identifier schema and immutable field semantics

**Files:**
- Modify: `src/watershed/tree/schema.gleam`
- Modify: `src/watershed/tree/change.gleam`
- Modify: `src/watershed/tree/codec.gleam`
- Modify: `test/watershed/shared_tree_schema_test.gleam`
- Modify: `test/watershed/shared_tree_schema_evolution_test.gleam`
- Modify: `test/watershed/shared_tree_change_test.gleam`
- Modify: `test/watershed/shared_tree_codec_test.gleam`
- Create: `test/watershed/shared_tree_identifier_test.gleam`
- Create: `test/watershed/tree/identifier_fixture.gleam`

**Interfaces:**
- Consumes: `identifier-schema` and the pinned no-change field handler.
- Produces: `schema.Identifier` field metadata, strict Identifier content
  validation, immutable local destinations, and Identifier V1 no-change
  codec/algebra support.

- [ ] **Step 1: Add an executable schema helper and a failing acceptance test.**

  Start `identifier_fixture.gleam` with this complete schema helper:

  ```gleam
  import gleam/json
  import watershed/tree/schema

  pub const point_type = "org.watershed.shared-tree.identifiers.Point"

  pub fn stored() -> schema.StoredSchema {
    let assert Ok(value) = schema.stored_from_json(json.object([
      #("version", json.int(2)),
      #("nodes", json.object([
        #("com.fluidframework.leaf.string",
          json.object([#("kind", json.object([#("leaf", json.int(1))]))])),
        #(point_type, json.object([#("kind", json.object([
          #("object", json.object([
            #("id", field("Identifier", "com.fluidframework.leaf.string")),
            #("label", field("Value", "com.fluidframework.leaf.string")),
          ])),
        ]))])),
      ])),
      #("root", field("Value", point_type)),
    ]))
    value
  }

  fn field(kind: String, type_id: String) -> json.Json {
    json.object([
      #("kind", json.string(kind)),
      #("types", json.array([type_id], json.string)),
    ])
  }
  ```

  Verify the Schema V2 key shape against the captured source schema before
  using the helper. The new test must assert round-trip schema preservation,
  not merely successful parsing:

  ```gleam
  pub fn identifier_schema_preserves_field_kind_test() {
    let stored = identifier_fixture.stored()
    schema.field_schema(stored, identifier_fixture.point_type, "id")
    |> expect.to_equal(Ok(schema.FieldSchema(
      schema.Identifier,
      ["com.fluidframework.leaf.string"],
    )))
    schema.stored_to_json(stored)
    |> schema.stored_from_json
    |> expect.to_equal(Ok(stored))
  }
  ```

- [ ] **Step 2: Run the test before adding schema support.**

  ```bash
  gleam test --target erlang -- shared_tree_identifier shared_tree_schema
  gleam test --target javascript -- shared_tree_identifier shared_tree_schema
  ```

  Expected red: missing `schema.Identifier` or rejected Identifier schema.

- [ ] **Step 3: Preserve field kind without weakening strict validation.**

  Add the `Identifier` variant, map `IdentifierKind` to it, and permit the
  proven object-field profile. Update the supported-view checks and all
  cardinality matches. Require one string child for persisted content.
  Retain comparison-only handling of unsupported/impossible schemas.

  Adjust existing rejection tests surgically: do not remove the entire
  unsupported-semantics list. Keep forbidden/unknown/handle/unsupported
  placement cases and replace only the now-supported Identifier object case.

- [ ] **Step 4: Add failing direct-edit and schema-widening cases.**

  Test names:

  ```text
  identifier_direct_set_is_atomic_error_test
  identifier_same_value_set_is_atomic_error_test
  identifier_clear_is_atomic_error_test
  identifier_parent_replacement_is_allowed_test
  identifier_duplicate_custom_strings_remain_distinct_nodes_test
  identifier_to_value_upgrade_preserves_content_test
  value_to_identifier_upgrade_is_rejected_test
  wider_view_cannot_mutate_stored_identifier_test
  ```

  Assert tree data, NodeRefs, pending history, compressor serialization,
  events, and outbound operations around rejected edits. Validating existing
  stored content must continue to succeed.

- [ ] **Step 5: Implement field immutability at local authoring boundaries.**

  `change.edit_destination` must reject assignment/clear to an Identifier
  field before `authored_field` allocates repair/build atoms. Add an
  exhaustive Identifier error branch in `authored_field` as a second
  invariant check. Do not reject insertion of a containing object with an
  explicit identifier, and do not reject a valid remote build.

- [ ] **Step 6: Add canonical no-change codec/algebra coverage.**

  Decode and encode a field entry with
  `{"fieldKind":"Identifier","change":0}` at the captured location.
  Use the native `IdentifierField` no-change variant. Its delta is empty,
  inversion is no-change, and it
  does not allocate atoms or authorize child edits. Exercise composition
  with generic paths and reject unsupported concrete kind combinations
  rather than turning them into mutable value fields.

- [ ] **Step 7: Run the focused pair and commit.**

  ```bash
  gleam test --target erlang -- shared_tree_identifier shared_tree_schema shared_tree_schema_evolution shared_tree_change shared_tree_codec
  gleam test --target javascript -- shared_tree_identifier shared_tree_schema shared_tree_schema_evolution shared_tree_change shared_tree_codec
  git add src/watershed/tree test/watershed
  git commit -m "feat(tree): preserve identifier field semantics"
  ```

### Task 3: Add contextual Identifier FieldBatch support

**Files:**
- Modify: `src/watershed/tree/codec/field_batch.gleam`
- Modify: `test/watershed/shared_tree_field_batch_test.gleam`
- Modify: `test/watershed/shared_tree_identifier_test.gleam`
- Modify: `test/watershed/tree/identifier_fixture.gleam`
- Modify `src/watershed/fluid_ids.gleam` only if a named upstream case proves
  the existing normalization primitives insufficient

**Interfaces:**
- Consumes: Task 1 numeric/literal corpus, Task 2 stored Identifier schema,
  existing compressor normalization.
- Produces: `IdContext`, `decode_with_context`, and `encode_with_context`
  from section 4, with context-free wrappers preserved.

- [ ] **Step 1: Add a literal-shape test before changing either rejection.**

  Build this FieldBatch as JSON in the existing `encoded_batch` test helper:

  ```json
  {
    "version": 2,
    "identifiers": [],
    "shapes": [
      {"c": {"type": "com.fluidframework.leaf.string", "value": 0}}
    ],
    "data": [[0, "customer-17"]]
  }
  ```

  Expected native value: `[[StringValue("customer-17")]]`. Include `""`,
  UUIDv4, UUIDv5, and non-ASCII custom strings. The schema/field-key
  identifiers substitution table must remain unaffected.

- [ ] **Step 2: Observe red, then thread the explicit context.**

  ```bash
  gleam test --target erlang -- shared_tree_field_batch shared_tree_identifier
  gleam test --target javascript -- shared_tree_field_batch shared_tree_identifier
  ```

  Change both `decode_node_shape` and `decode_value`. Propagate optional ID
  context through recursive node, fixed-field, polymorphic, and array
  decoding. Literal Identifier strings do not need a compressor.

- [ ] **Step 3: Add numeric-ID tests with a real compressor.**

  Build a sender using session
  `11111111-1111-4111-8111-111111111111`. Generate an ID, record its stable
  string, and encode its op-space integer. Build a distinct receiver with
  session `22222222-2222-4222-8222-222222222222`; deliver the actual creation
  range before decoding with `MessageIds(receiver, sender_session)`.

  Assert the decoded string equals the sender's decompressed ID. Remove the
  creation range and require a typed failure. Repeat after finalization and
  with a receiver whose own allocation space could otherwise make the same
  negative integer appear valid.

  Add explicit summary tests for finalized IDs and rejected negative IDs,
  including the receiver-local cluster-aligned case from the pinned
  normalization contract.

- [ ] **Step 4: Implement typed numeric decoding.**

  Message decoding follows:

  ```text
  JSON integer -> checked OpId -> from_op(compressor, id, originator)
               -> decompress -> StringValue
  ```

  Summary decoding checks finality before normalization. A safe positive
  op-space ID must still resolve to allocated content; safe integer syntax
  alone is insufficient. No-context numeric input returns
  `UnsupportedFeature` explaining that an ID decoding context is required.
  Invalid input with a supplied context returns `CorruptData`.

- [ ] **Step 5: Add Identifier-aware encoding without a general optimizer.**

  Keep existing generic shapes. Add a string-leaf shape with `value: 0`
  for fields that the stored schema marks Identifier. Thread the relevant
  field definition through recursive encoding so ordinary UUID-valued string
  fields do not get compressed by accident.

  For known UUIDs call `recompress` then `to_op`. Summary context emits the
  original stable string if the op ID remains negative. Unknown UUIDs and
  custom strings pass through unchanged. Encoding must leave both local and
  summary compressor serialization unchanged.

- [ ] **Step 6: Add malformed and round-trip coverage.**

  Cover missing stream entries, extra entries, Boolean/null/object/array
  values, fractional and unsafe integers, unknown sessions/IDs, missing
  ranges, wrong originator, and recursive shapes. Check native encode to
  native decode and pinned encode to native decode separately. The next task
  proves native encode to upstream decode.

  Keep the unsupported handle, incremental chunk, and synthetic
  `com.fluidframework.node.identifier` refusals intact.

- [ ] **Step 7: Run and commit the isolated codec layer.**

  ```bash
  gleam test --target erlang -- shared_tree_field_batch shared_tree_identifier shared_tree_ids
  gleam test --target javascript -- shared_tree_field_batch shared_tree_identifier shared_tree_ids
  git add src/watershed/tree/codec/field_batch.gleam test/watershed
  git commit -m "feat(tree): encode compressed identifier values"
  ```

### Task 4: Wire ID context through operations and summaries

**Files:**
- Modify: `src/watershed/tree/codec.gleam`
- Modify: `src/watershed/tree/codec/summary.gleam`
- Modify: `src/watershed/tree/runtime.gleam`
- Modify: `src/watershed/tree/summary.gleam` where snapshot context enters codecs
- Modify: `src/watershed/wire/fluid_document.gleam` where document compressor enters summaries
- Modify: `test/watershed/shared_tree_codec_test.gleam`
- Modify: `test/watershed/shared_tree_summary_codec_test.gleam`
- Modify: `test/watershed/shared_tree_document_summary_test.gleam`
- Modify: `test/watershed/tree/codec_export.gleam`
- Modify: `tools/shared-tree-oracle/upstream-codecs.spec.ts`
- Modify: `tools/shared-tree-oracle/codec-interop.mjs` and its tests

**Interfaces:**
- Consumes: contextual FieldBatch functions.
- Produces: complete Identifier-bearing message/build/refresher/forest/history
  decode and encode, including native output accepted by pinned upstream.

- [ ] **Step 1: Add failing full-message and full-summary tests.**

  Use unmodified `transaction-wire` input `messageBytes`, `compressor`, and
  `context`. Decode the full message, including builds and refreshers.
  Assert literal ID values, build IDs, constraint state, and revision
  metadata. Do not call `without_unsupported_field_batches`.

  Load the complete captured Identifier summary with its recorded document
  compressor into a fresh-session reader. Assert root data and retained
  detached data, not just schema acceptance.

- [ ] **Step 2: Thread operation context into both build paths.**

  At `decode_builds`, select `MessageIds(context.compressor,
  change_context.originator)` for messages and `SummaryIds` for summary
  purpose. Apply the same rule when the helper decodes refreshers.
  Mirror it at `encode_builds`.

  Use the outer message's original author session. The transport client ID,
  receiving compressor session, and commit revision are not substitutes.

- [ ] **Step 3: Add contextual forest entry points and wire full summaries.**

  Implement the two forest functions in section 4. Update full summary
  decode/encode and private string wrappers to use them. Keep context-free
  functions explicit about unsupported numeric Identifier content.

  During document load, deserialize the snapshot compressor before decoding
  its forest/history. During summary creation, use the compressor at the same
  sequenced point as the forest. Do not serialize an optimistic current
  compressor with an older forest.

- [ ] **Step 4: Prove historical and repair content paths.**

  Cover trunk and peer-branch builds, refreshers, removed Identifier-bearing
  nodes, and a schema/data transition that widens Identifier to Value.
  Use each historical change's correct schema and purpose. Do not decode
  historical builds with the latest view alone.

  Corrupt one numeric ID in a later build and require the enclosing message
  or summary to fail atomically.

- [ ] **Step 5: Extend native-to-upstream codec consumption.**

  Add Identifier-profile export items to `codec_export.gleam` and the
  existing upstream consumer's schema/profile dispatch. Required items:
  explicit custom ID, default-generated UUID, compressed message ID,
  finalized summary ID, unfinalized summary string fallback, retained repair
  tree, and a subsequent edit after load.

  Compare encoded Identifier fields and complete decoded semantics. Do not
  require unrelated shape-table indices to match a different valid encoder.

- [ ] **Step 6: Run both targets and the external consumer.**

  ```bash
  gleam test --target erlang -- shared_tree_identifier shared_tree_field_batch shared_tree_codec shared_tree_summary_codec shared_tree_document_summary
  gleam test --target javascript -- shared_tree_identifier shared_tree_field_batch shared_tree_codec shared_tree_summary_codec shared_tree_document_summary
  just shared-tree-codec-interop
  ```

  An unavailable upstream consumer is a blocked gate, not a passing native
  round-trip.

- [ ] **Step 7: Commit complete context propagation.**

  ```bash
  git add src/watershed/tree src/watershed/wire/fluid_document.gleam test/watershed tools/shared-tree-oracle
  git commit -m "feat(tree): preserve identifiers on wire and load"
  ```

### Task 5: Generate defaults during authoring and container creation

**Files:**
- Create: `src/watershed/tree/identifier.gleam`
- Modify: `src/watershed/tree/runtime.gleam`
- Modify: `src/watershed/tree/schema.gleam` only for shared construction validation
- Modify: `src/watershed/container.gleam`
- Modify: `src/watershed/wire/fluid_document.gleam`
- Modify: `test/watershed/shared_tree_identifier_test.gleam`
- Modify: `test/watershed/shared_tree_runtime_test.gleam`
- Modify: `test/watershed/shared_tree_transaction_test.gleam`
- Modify: `test/watershed/shared_tree_creation_test.gleam`
- Modify: `test/watershed/shared_tree_creation_api_test.gleam`
- Modify: `test/watershed/shared_tree_array_facade_test.gleam`
- Modify: `test/watershed/shared_tree_map_facade_test.gleam`

**Interfaces:**
- Consumes: Identifier schema metadata, existing document compressor,
  contextual encoding, and captured default-allocation order.
- Produces: `materialize_value` and `materialize_edit`; ordinary edits,
  transactions, and initial containers share their default behavior.

- [ ] **Step 1: Add a failing default-generation unit test.**

  Use the schema helper from Task 2:

  ```gleam
  pub fn identifier_missing_value_uses_document_compressor_test() {
    let assert Ok(session) =
      fluid_ids.session_id("11111111-1111-4111-8111-111111111111")
    let base = fluid_ids.new(session)
    let assert Ok(#(expected_compressor, local)) = fluid_ids.generate(base)
    let assert Ok(stable) = fluid_ids.decompress(expected_compressor, local)
    let input = types.ObjectValue(
      identifier_fixture.point_type,
      [#("label", types.StringValue("new"))],
    )
    let assert Ok(#(value, compressor)) =
      identifier.materialize_value(identifier_fixture.stored(), input, base)
    let assert types.ObjectValue(_, fields) = value
    list.key_find(fields, "id")
    |> expect.to_equal(Ok(types.StringValue(
      fluid_ids.stable_id_to_string(stable),
    )))
    compressor |> expect.to_equal(expected_compressor)
    schema.validate_root(identifier_fixture.stored(), value)
    |> expect.to_equal(Ok(Nil))
  }
  ```

- [ ] **Step 2: Run red and implement the pure materializer.**

  ```bash
  gleam test --target erlang -- shared_tree_identifier
  gleam test --target javascript -- shared_tree_identifier
  ```

  Resolve object definitions through `schema.node_schema`. Traverse their
  fields in the order proven by Task 1. Generate only absent Identifier
  fields. Preserve input collection order, explicit strings, and ordinary
  optional-field absence. Validate malformed supplied content rather than
  overwriting it with defaults.

- [ ] **Step 3: Integrate ordinary and preview authoring once.**

  Both `author_edit` and `author_edit_change` currently perform early strict
  validation. Refactor that shared preparation so missing Identifier fields
  can materialize before strict validation, while destination errors remain
  atomic. Avoid a second generation pass through the ordinary wrapper.

  Required flow:

  ```text
  supplied edit + current compressor
    -> materialize candidate inserted content
    -> validate destination and complete candidate
    -> allocate revision in captured order
    -> author/apply preview
    -> ordinary append OR transaction-local retention
  ```

  If the pinned capture places revision allocation differently, record and
  apply that exact schedule before implementing this step. Do not obtain
  equal visible values by accepting different allocator histories.

- [ ] **Step 4: Cover edit routes and immutable failures.**

  Required named cases:

  ```text
  identifier_nested_defaults_follow_pinned_order_test
  identifier_explicit_strings_do_not_allocate_test
  identifier_invalid_insert_preserves_compressor_test
  identifier_move_preserves_value_and_node_reference_test
  identifier_transaction_abort_preserves_local_advancement_test
  identifier_nested_abort_does_not_reuse_reference_test
  identifier_noop_finish_restores_base_compressor_test
  identifier_retry_reuses_authored_value_test
  ```

  An explicit-ID edit still allocates its normal commit revision; assert
  that it allocates no extra **identifier** ID, not that the whole edit uses
  zero IDs.

- [ ] **Step 5: Integrate initial root defaults without fake sequencing.**

  Let `fluid_document.initial_tree` materialize supplied initial content using
  its session's compressor, then build the snapshot and `DocumentSummary`
  from the resulting values and compressor. Adjust `container.prepare` so it
  accepts omitted Identifier defaults but still rejects invalid initial data
  before network I/O.

  Encode initial summary IDs with the originatorless rule. Unfinalized IDs
  remain literal strings; do not finalize them solely for compression.
  Prove a fresh upstream reader can load the resulting first summary and
  continue editing without collisions.

- [ ] **Step 6: Verify parity and creation paths.**

  ```bash
  gleam test --target erlang -- shared_tree_identifier shared_tree_runtime shared_tree_transaction shared_tree_creation shared_tree_array_facade shared_tree_map_facade
  gleam test --target javascript -- shared_tree_identifier shared_tree_runtime shared_tree_transaction shared_tree_creation shared_tree_array_facade shared_tree_map_facade
  just shared-tree-create-test
  ```

  No new public facade method is needed for reading string IDs. Existing
  insertion APIs accept omitted Identifier fields in newly supplied objects.
  Verify the same behavior through both public facades.

- [ ] **Step 7: Commit default authoring.**

  ```bash
  git add src/watershed/tree src/watershed/container.gleam src/watershed/wire/fluid_document.gleam test/watershed
  git commit -m "feat(tree): generate identifier field defaults"
  ```

### Task 6: Prove native persistence and remove the transaction workaround

**Files:**
- Modify: `test/watershed/tree/identifier_fixture.gleam`
- Modify: `test/watershed/shared_tree_identifier_test.gleam`
- Modify: `test/watershed/shared_tree_fixture_test.gleam`
- Modify: `test/watershed/tree/transaction_fixture.gleam`
- Modify: `test/watershed/shared_tree_transaction_test.gleam`
- Modify: `test/watershed/shared_tree_history_resubmit_test.gleam`
- Modify: `test/watershed/shared_tree_summary_test.gleam`
- Modify: `test/watershed/shared_tree_document_summary_test.gleam`
- Modify: `tools/shared-tree-oracle/generate.test.mjs` for required runner/input gates

**Interfaces:**
- Consumes: complete Identifier authoring and wire support.
- Produces: complete input-only Identifier corpus parity, full transaction
  wire decoding, and proof that the parent Task 8 Identifier blocker is gone.

- [ ] **Step 1: Register the four Identifier cases as required native runners.**

  Implement `identifier_fixture.run(input)` from section 4. It must execute
  supplied actions and report actual schema, values, IDs, compressor states,
  encoded messages, allocation ranges, events, pending history, detached
  content, and summary continuation for the observations each case requires.

  Add runner-sensitivity tests that change an input ID, originator, allocation
  range, or edit. The native output must change or report the correct error.

- [ ] **Step 2: Remove build/refresher stripping and update wire assertions.**

  Delete `without_unsupported_field_batches` and its use from
  `transaction_fixture.gleam`. Decode and re-encode complete
  `transaction-wire` operands, including created and retained content.
  Adjust the test normalization only for explicitly permitted encoding
  differences, not for missing semantic fields.

  Add a mutation that changes one Identifier value inside a build and another
  that removes a required allocation range; each must be observable by the
  native runner.

- [ ] **Step 3: Add recovery and summary continuation tests.**

  Author an Identifier-bearing node in a multi-edit transaction, then cover:

  - disconnect before acknowledgement, resubmit, and one acknowledgement;
  - accepted-before-drop deduplication with unchanged authored ID;
  - summary at the sequenced point while local work is pending;
  - fresh-session load, ordered allocation range, tail transaction, further edit;
  - explicit constraint violation that hides visible effects but retains
    required created/repair content;
  - equal custom ID strings on different nodes, one constrained and one
    removed, proving constraints do not compare identifier strings.

  Assert reference stability separately from identifier string equality.
  Omit the tail allocation deliberately and require atomic failure.

- [ ] **Step 4: Run the native gates without a live-service shortcut.**

  ```bash
  gleam test --target erlang -- shared_tree_identifier shared_tree_transaction shared_tree_history_resubmit shared_tree_summary shared_tree_document_summary shared_tree_fixture
  gleam test --target javascript -- shared_tree_identifier shared_tree_transaction shared_tree_history_resubmit shared_tree_summary shared_tree_document_summary shared_tree_fixture
  just shared-tree-codec-interop
  just shared-tree-test
  ```

  These commands do not close parent Task 8 unless its callback, constraint,
  and history runners also produce all required observations. Mark the
  Identifier prerequisite complete without claiming unrelated recovery proof.

- [ ] **Step 5: Commit native proof.**

  ```bash
  git add test/watershed tools/shared-tree-oracle/generate.test.mjs
  git commit -m "test(tree): prove identifier recovery parity"
  ```

### Task 7: Prove mixed-client support and close the Identifier profile

**Files:**
- Modify: `tools/shared-tree-oracle/schema.mjs`
- Modify: `tools/shared-tree-oracle/client-driver.mjs` and its tests
- Modify: `test/watershed/tree/client_js.gleam`
- Modify: `test/watershed/tree/client_beam.gleam`
- Modify: `tools/shared-tree-oracle/interop-scenarios.mjs`
- Modify: `tools/shared-tree-oracle/client-interop.mjs` and its tests
- Modify: `tools/shared-tree-oracle/summary-interop.mjs` and its tests
- Modify: `tools/shared-tree-oracle/interop.mjs` and its tests
- Modify: `tools/shared-tree-oracle/service.mjs` and its tests
- Modify: `tools/shared-tree-oracle/generate.mjs`, `generate.test.mjs`, and `gates.test.mjs`
- Modify: `tools/shared-tree-oracle/README.md`, `README.md`
- Modify: `.github/workflows/shared-tree.yml` and `.github/workflows/shared-tree-interop.yml` only where existing command selection misses required Identifier cases
- Modify: `docs/superpowers/plans/2026-09-29-shared-tree-transactions.md`
- Generate: profile, manifest, and captured case metadata through the generator

**Interfaces:**
- Consumes: native Identifier proof and the existing mixed-client protocol.
- Produces: enforced Identifier profile claims, service evidence, and a
  precise handoff to unfinished transaction work.

- [ ] **Step 1: Add failing required-section and client-authorship tests.**

  Require `identifierFields` and `identifierReloadMatrix` sections using the
  existing report-validation conventions. Reject a report after removing
  either native target, an upstream-authored case, a failure observation,
  or any writer/reader cell. Coordinators schedule commands; the real
  clients must create defaults and emit their own operations.

- [ ] **Step 2: Exercise both authorship directions and nine reload cells.**

  Run upstream/JavaScript, upstream/BEAM, and JavaScript/BEAM pairs. Each client
  authors a missing-default insertion and an explicit-string insertion.
  Peers observe the same string IDs, values, and constraint behavior.
  Move nodes within and between arrays; replace one node with another using
  the same custom ID and verify distinct reference identity.

  For each writer in `upstream`, `javascript`, `erlang`, publish an
  Identifier-bearing summary. Each of the three readers loads it, authors a
  fresh Identifier-bearing node, and exposes that edit to a peer. Add a
  native-created first-summary case through the creation interop harness.

- [ ] **Step 3: Add Identifier-specific protocol failure cases.**

  Missing allocation, wrong originator, corrupt integer value, and negative
  originatorless summary data must fail without partial readiness or state
  mutation. Preserve all existing profile refusal cases.

- [ ] **Step 4: Run required local service and creation gates.**

  ```bash
  npm --prefix tools/shared-tree-oracle test
  npm --prefix tools/shared-tree-oracle run check
  just shared-tree-codec-interop
  just shared-tree-test
  just shared-tree-interop
  just shared-tree-create-interop
  ```

  `just shared-tree-interop` currently runs 300 schedules with seed 42.
  Extend its schedules to include default and explicit Identifier insertions
  alongside the existing operations. Preserve seed, schedule, ranges,
  originator, encoded data, and failure observation in artifacts.

  Hosted evidence requires its existing authorized workflow and credentials.
  Do not publish, push, or trigger an external workflow without appropriate
  authorization. Record missing hosted evidence as incomplete.

- [ ] **Step 5: Document the supported feature without overclaiming.**

  Add generated/default and explicit-ID examples. Explain read-only fields,
  duplicate custom IDs, parent replacement, ordinary string reads, ID
  compression, and summary context. List the exclusions from section 2.5.
  Keep Identifier strings distinct from `NodeInDocument` identity.

  Generate profile labels from the source generator only after the required
  gates pass. Do not hand-edit generated profile/manifest files.

- [ ] **Step 6: Run full regression closure and record failures honestly.**

  ```bash
  just test
  just build
  just lint
  ```

  If `just build` encounters the known supply-chain policy block, preserve
  the denial and report it. Do not alter registry URLs or install through
  another path to evade the policy. Do not infer that a failure is baseline
  from this plan alone.

- [ ] **Step 7: Commit scoped closure and resume the parent plan.**

  ```bash
  git add tools/shared-tree-oracle test/watershed test/fixtures/shared_tree README.md .github/workflows docs/superpowers/plans/2026-09-29-shared-tree-transactions.md
  git commit -m "docs(tree): define identifier interoperability"
  ```

  Update the parent plan with the exact Identifier commits, gate results,
  open external blockers, and the next unchecked task. Resume at transaction
  Task 8, then complete Tasks 9–11. Do not recapture its Identifier fields
  as ordinary strings and do not mark M5 undo/redo complete.

## 6. Acceptance and review checklist

| Requirement | Owning tasks | Evidence needed |
| --- | --- | --- |
| Actual pinned representation, reproducible capture | 1 | Source verification, repeated generation, case completeness tests |
| Identifier schema retained, one string child | 2 | Schema round-trip, malformed and placement refusals |
| Immutable fields, correct widening | 2 | Set/clear/same-value refusal and stored/view upgrade tests |
| Literal and compressed values | 3 | Sender/receiver normalization and string passthrough cases |
| Message versus summary distinction | 3, 4 | Negative message decode, summary string fallback, originatorless negative refusal |
| Full build/refresher/history decoding | 4, 6 | Complete transaction wire operands, mutation-sensitive runner |
| Defaults share document allocation | 5 | Exact captured order, invalid-edit atomicity, multi-field defaults |
| Container creation includes defaults | 5, 7 | Native first summary read and continued editing by upstream |
| Rollback, no-op, reconnect preserve contracts | 5, 6 | Compressor, reference, history, event, and outbound assertions |
| Identifier equality is not node identity | 2, 6, 7 | Duplicate custom IDs with independent constraints/replacement |
| Native output accepted upstream | 4, 7 | Codec consumer and live clients, not only native round-trip |
| All nine persistence combinations | 7 | Writer/reader matrix with post-load authoring |
| Accurate permanent profile | 7 | Missing-case/target/cell failures, regenerated labels, docs |
| Existing behavior preserved | 2–7 | Focused pairs and full closure results |
| Parent transaction work resumes | 6, 7 | Explicit Task 8 handoff; no false M5 completion claim |

Before calling this plan complete, confirm:

- [ ] No decoder uses a fresh reader session for a sender-local ID.
- [ ] No summary emits a negative compressed Identifier ID.
- [ ] No decoder or encoder generates/finalizes IDs to repair input.
- [ ] Custom strings survive unchanged; no new uniqueness restriction exists.
- [ ] Defaults run once on insertion and never again on retry, replay, or load.
- [ ] All pure and public behavior passes on both targets.
- [ ] Complete transaction builds/refreshers are no longer stripped.
- [ ] Real upstream clients consume native messages and summaries.
- [ ] Unsupported features and unverified external gates remain explicit.
- [ ] The parent transaction plan still distinguishes implemented APIs from
      complete persistence, service, and release acceptance.

## 7. Follow-up session prompt

> Implement `docs/superpowers/plans/2026-10-01-shared-tree-identifiers.md`
> task by task. Start by checking the current worktree and pinned oracle
> injections. Preserve the transaction implementation through `afc32c65` and
> do not replace Identifier fields in the oracle with ordinary strings.
> Use test-first, dual-target changes and the real upstream consumer gates.
> Keep execution reports outside version control. After Identifier acceptance,
> resume the unchecked Tasks 8–11 in
> `docs/superpowers/plans/2026-09-29-shared-tree-transactions.md`.
> Do not bypass dependency policy or claim complete Fluid compatibility.
