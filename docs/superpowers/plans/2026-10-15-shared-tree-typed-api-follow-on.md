# Typed SharedTree Follow-on Implementation Plan

> **For agentic workers:** Use the executing-plans skill for inline execution.
> Use subagent-driven-development only if the user requests delegation.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend typed schema authoring with unions, recursion, and Identifier
defaults, then expose identity-bound typed live reads and edits.

**Architecture:** Extend the first milestone's descriptors without changing
their public type parameters. Add a pure typed live layer over structured,
checkout-scoped runtime requests and a core-owned anchor registry. Reuse the
existing compressor, tree edit/history engine, transactions, and subscriptions.

**Tech Stack:** Dual-target Gleam, startest, gleeunit in the browser example,
Node test runner, pinned Fluid source oracle, existing JS/BEAM facade clients,
and local Floodgate acceptance tooling.

**Spec:** [Approved follow-on design](../specs/2026-10-15-shared-tree-typed-api-follow-on-design.md).
Also read the [first design](../specs/2026-10-15-shared-tree-schema-authoring-design.md)
and [first plan](2026-10-15-shared-tree-schema-authoring.md).

## Global constraints

- Production code is pure Gleam on JavaScript and BEAM.
- No new production dependency, FFI, compiler plugin, or code generator.
- Keep `@fluidframework/tree` at `3.1.0` and Fluid commit `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960`.
- Keep the existing Schema V2 format and accepted interoperability profile.
- Preserve the first milestone's public builder signatures and low-level facade APIs.
- Use the existing compressor for Identifier defaults; no application-generated replacement IDs.
- Live references are runtime-local, tree-local, and checkout-local; never serialize them.
- Resolve and submit identity-bound edits in one runtime-core operation.
- Apply ASD-STE100 to Gleam comments and error strings, not Markdown or website prose.
- Do not edit apm-managed files, `.code-map/`, pinned upstream example bytes, or generated snippet JSON manually.
- Planning does not authorize implementation or changes to earlier pending work.

---

## Prerequisites, milestones, and execution

The first authoring plan must be implemented and accepted before this plan
starts. Its modules and tests do not exist at planning time. Do not treat their
proposed interfaces as current repository evidence.

Milestone A consists of Tasks 1–4: authoring extensions with independent
snapshot/construction acceptance. Milestone B consists of Tasks 5–10: live
references and runtime integration. Task 5's identity acceptance is a hard
dependency of live editing; a typed-path wrapper is not an acceptable substitute.
Do not expose an unproven reference API as stable while identity work continues.

Use an isolated worktree at execution time. Preserve unrelated work, including
the earlier comparison-comment/dedenting changes and both planning documents.
Do not install dependencies until a selected command reports them missing.
Read `AGENTS.md`; website edits also require the website copy instructions.

Each task is a reviewable commit boundary. Add only that task's files, use the
suggested intent as the commit subject, and include:

```text
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```

Run each new behavioral test red, implement its smallest complete behavior,
then run it green. Do not accept compile-fail fixtures that fail because of a
missing module, syntax error, or unrelated dependency.

## File structure

| Files | Responsibility |
| --- | --- |
| `src/watershed/tree/schema_builder.gleam` | Extend typed schema descriptors and expose internal codec/metadata accessors needed by live access. |
| `src/watershed/tree/live.gleam` | Target-independent typed views, references, property/collection operations, and subscriptions. |
| `src/watershed/tree/live_types.gleam` | Structured requests/responses, opaque tokens, reference status, and errors shared by live/core/wrappers. |
| `src/watershed/tree/live_anchor.gleam` | Pure anchor registry, ownership, interning, remapping, and tombstones. |
| `src/watershed/tree/forest.gleam`, `tree_kernel.gleam`, `tree/branch.gleam`, `tree/transaction.gleam` | Identity-to-path lookup and explicit identity mappings where reconciliation/promotion changes physical references. |
| `src/watershed/runtime_core.gleam` | Atomic typed request processing and anchor maintenance through every tree state transition. |
| `src/watershed/runtime.gleam`, `src/watershed/runtime_beam.gleam` | JS cell / BEAM actor request dispatch and subscription cleanup. |
| `src/watershed.gleam`, `src/watershed_beam.gleam` | Matching `tree_typed` binding entry points. |
| `test/watershed/shared_tree_schema_builder_test.gleam`, `shared_tree_schema_builder_codec_test.gleam` | Extend prerequisite tests for unions, lazy definitions, Identifier input/output. |
| `test/watershed/shared_tree_live_anchor_test.gleam`, `shared_tree_live_test.gleam` | Pure identity and typed live behavior on both targets. |
| `test/watershed/tree/typed_api_fixture.gleam` | Decode independent oracle scenario inputs and report native observations. |
| Existing `shared_tree_identifier_test.gleam`, `shared_tree_branch_test.gleam`, `shared_tree_transaction_test.gleam`, facade/runtime suites | Regression evidence for existing behavior and low-level edits affecting anchors. |
| `tools/shared-tree-oracle/upstream-typed-api.spec.ts` | Separate deterministic authoring and reference-lifetime source captures. |
| `tools/shared-tree-oracle/source.mjs`, `source.test.mjs` | Register the new injection and isolated corpus batch; preserve source verification. |
| `test/fixtures/shared_tree/typed-api-authoring.json`, `typed-api-live.json` | Generated independent evidence with exact reference identity. |
| `tools/compile-fail/incompatible_tree_union/`, `incompatible_tree_recursive/`, `incompatible_tree_live_property/`, `incompatible_tree_live_insert/`; `justfile` | Negative typing evidence using the existing fixture harness. |
| `test/watershed/tree/client_protocol.gleam`, `client_js.gleam`, `client_beam.gleam` | Typed operations in existing cross-runtime acceptance clients. |
| `tools/shared-tree-oracle/client-driver.mjs`, `client-interop.mjs` and their tests | Two-client service scenario using those typed operations. |
| `docs/shared-tree-schema-authoring.md`, new `docs/shared-tree-typed-live-api.md`, root README, oracle README | Public contracts, limitations, mapping from Fluid, and repeatable gates. |
| Item-counter example source/tests/README and website comparison data/snippet inputs | Adopt the live array API without changing persisted identity or lifecycle behavior. |

Keep each new module focused. Do not introduce a second branch, transaction,
schema-compatibility, or node-ID engine.

## Task 1: Capture the pinned authoring and reference contracts

**Consumes:** Existing `source.mjs` injection/verification infrastructure,
`upstream-branch.spec.ts` test-provider patterns, Identifier fixtures, and
Fluid's pinned `extractPersistedSchema`/`Tree` APIs.
**Produces:** Two independently captured fixture documents. No native authoring
or runtime implementation changes belong in this task.

- [ ] **1. Add a dedicated source injection and batch.**

Register `upstream-typed-api.spec.ts` as
`packages/dds/tree/src/test/watershedTypedApi.spec.ts`, using the existing
injection map and allowed-untracked verification. Add a separate final batch
to `sourceTestBatches(true)` so new identity allocations cannot change earlier
batch outputs. Do not add it to `source:capture`'s default smoke publication.

Update `source.test.mjs` to exercise registration/injection behavior through
its existing controlled checkout tests, not by grepping source text.

```sh
node --test tools/shared-tree-oracle/source.test.mjs
```

- [ ] **2. Capture authoring schemas and construction observations.**

Use imports and runtime helpers from the pinned tree source, not the current
web documentation. Include:

| Case | Observation |
| --- | --- |
| String/object heterogeneous union in object/map/array/root | Allowed IDs and actual decoded variants. |
| Reordered union alternatives | Equivalent persisted schema. |
| Direct and mutual recursive object/container definitions | Finite persisted definition graph. |
| Optional recursive property versus null | Actual absent/present behavior. |
| Missing Identifier in new nested content | Materialized value and compressor allocation evidence. |
| Explicit custom Identifier | Exact preserved string. |
| Two nodes with the same custom Identifier | Distinct node identity despite equal strings. |
| Generated IDs during commit/abort/reconciliation | Allocation and survival according to the existing pinned runtime, not an assumed no-allocation rule. |

The authoring fixture envelope is:

```typescript
{
  formatVersion: 1,
  reference: {
    package: "@fluidframework/tree",
    version: "3.1.0",
    commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
  },
  scenarios: [
    {
      id: "union-object-array",
      input: {
        alternatives: ["string", "Point"],
        operations: [{ op: "insert", index: 0, value: { kind: "Point", label: "A" } }],
      },
      observations: { survivingLabels: ["A"], variantKinds: ["Point"] },
    },
  ],
}
```

Implement the complete case matrix with executable extraction and runtime
observations; the sample shows the envelope, not a substitute expected result.

- [ ] **3. Capture reference behavior separately from final snapshots.**

Use `TestTreeProviderLite` and the existing branch test patterns. Keep actual
upstream node objects in a local reference table. Test `===` between saved and
newly looked-up nodes, node status, and edit outcomes. Record data-only scenario
inputs and normalized observations; native runners must not read expected
observations to decide which operations to execute.

Required scenarios: insert-before, reorder, cross-parent move, remove/undo,
equal-content replacement, equal-Identifier replacement, root replacement,
transaction commit/abort, reconciliation after a competing edit, reconnect,
fork/rebase/merge with source retained/disposed, and schema invalidation.
Record removed-node behavior even where this API deliberately refuses more
than Fluid. Mark those projection differences by name.

- [ ] **4. Capture, inspect, and regenerate deterministically.**

```sh
npm --prefix tools/shared-tree-oracle run source:verify
node --input-type=module -e 'import { runSource } from "./tools/shared-tree-oracle/source.mjs"; await runSource("tools/shared-tree-oracle/.output/typed-api", { corpus: true });'
cp tools/shared-tree-oracle/.output/typed-api/typed-api-authoring.json test/fixtures/shared_tree/typed-api-authoring.json
cp tools/shared-tree-oracle/.output/typed-api/typed-api-live.json test/fixtures/shared_tree/typed-api-live.json
```

Repeat the capture and use `cmp` on both files. Existing `source:capture`
publishes only its smoke file; do not change its publication contract.
Document the exact commands. Suggested commit: `test(tree): capture typed API contracts`.

## Task 2: Typed heterogeneous unions

**Consumes:** First milestone `Node(a)` / `Compiled(a)` and Task 1 schemas.
**Produces:** `Variant(sum)`, `variant`, and `union` from design section 3.

- [ ] **1. Write a positive round-trip test and run it red.**

```gleam
import gleam/option.{None, Some}
import startest/expect
import watershed/tree/schema_builder as builder
import watershed/tree/types

type Choice { Text(String) Count(Float) }

fn choice() -> builder.Node(Choice) {
  builder.union([
    builder.variant(builder.string(), Text, fn(value) {
      case value { Text(text) -> Some(text) Count(_) -> None }
    }),
    builder.variant(builder.number(), Count, fn(value) {
      case value { Count(number) -> Some(number) Text(_) -> None }
    }),
  ])
}

pub fn typed_union_round_trip_test() {
  let assert Ok(compiled) = choice() |> builder.root |> builder.compile
  builder.encode(compiled, Text("hello"))
  |> expect.to_equal(Ok(Some(types.StringValue("hello"))))
  builder.decode(compiled, Some(types.NumberValue(2.0)))
  |> expect.to_equal(Ok(Count(2.0)))
}
```

```sh
gleam test --target javascript -- shared_tree_schema_builder
```

- [ ] **2. Make private node encoders fallible and represent allowed-type sets.**

Preserve all public prerequisite signatures. Lift primitive/container/object
encoders to return `Result`, compose errors with `result.try`, and update
required/optional root adapters. Keep typed branch functions in closures;
only schema metadata is type-erased.

Each `Variant(sum)` provides schema metadata, a fallible encoder that returns
`None` when its projector does not match, and a decoder that injects its
decoded child. Require exactly one encoding match. Decode using the native
type identifier; never try branches until one happens to decode successfully.

- [ ] **3. Add rejection and composition tests red/green.**

Empty unions and overlapping identifier sets fail schema compilation.
Zero/multiple matching projectors fail encoding. Unknown variants fail decode.
Cover nested unions, unions in required/optional properties and collections,
cross-factory alternatives, and deterministic output under reordered alternatives.
Compare supported schemas with Task 1's independently captured forms.

- [ ] **4. Add the union compile-fail fixture, then run both targets.**

Create `tools/compile-fail/incompatible_tree_union` using the prerequisite
fixture manifest pattern and register it in `_test-compile-fail`. Its source
imports the builder and `Some` and deliberately mismatches the decoded branch
and injector argument:

```gleam
pub fn invalid() {
  builder.variant(builder.string(), fn(value: Float) { value }, fn(value) {
    Some(value)
  })
}
```

Require the observed String/Float compiler mismatch rather than any nonzero
build status. Keep this negative guarantee in Milestone A.

```sh
gleam test --target erlang -- shared_tree_schema_builder
gleam test --target javascript -- shared_tree_schema_builder
just _test-compile-fail
```

Suggested commit: `feat(tree): add typed schema unions`.

## Task 3: Lazy named recursion

**Consumes:** Task 2's definition graph/allowed types and fallible codecs.
**Produces:** `lazy(Factory, String, fn() -> Node(a)) -> Node(a)`.

- [ ] **1. Add the design's `Outline` declaration as a real test fixture.**

Use the exact recursive declaration in design section 4, then add:

```gleam
pub fn typed_recursive_round_trip_test() {
  let assert Ok(compiled) = outline() |> builder.root |> builder.compile
  let value = Outline("root", [Outline("left", []), Outline("right", [])])
  let assert Ok(encoded) = builder.encode(compiled, value)
  builder.decode(compiled, encoded) |> expect.to_equal(Ok(value))
}
```

Run the Task 2 JS selector red.

- [ ] **2. Separate lazy metadata edges from typed codec evaluation.**

Represent a lazy edge with its claimed name and a thunk yielding concrete
schema metadata. Compilation uses visiting/visited tables and validates each
encountered thunk result before coalescing its concrete definition. A seen
identifier is not permission to skip conflict checking.

Reject a thunk returning another lazy edge, a primitive, a multi-type union,
or a differently named container. Only descend into a concrete definition's
children on its first graph visit. Keep encoder/decoder thunks typed, forcing
them as finite data requires them; do not eagerly unroll recursive closures.

- [ ] **3. Add mutual recursion, lazy union branches, and failure cases.**

Cover an array-mediated `Outline`, two mutually recursive record types,
an optional recursive child, and a union containing a concrete lazy branch.
Round-trip a depth-100 value and a broad value with repeated child types.
Assert deterministic finite schema output and conflict errors for same-name
incompatible lazy declarations.

Add a required self-cycle schema case and follow the existing parser's
acceptance without inventing an empty value or weakening required fields.
Invalid descriptor/schema combinations must return errors, not loop.

- [ ] **4. Add recursive type rejection and run both schema-builder selectors.**

Create/register `tools/compile-fail/incompatible_tree_recursive` using the
existing fixture harness. The deliberately invalid declaration is:

```gleam
pub fn invalid() -> builder.Node(String) {
  builder.lazy(builder.factory("com.example"), "Wrong", fn() {
    builder.number()
  })
}
```

Require the intended `Node(String)` / `Node(Float)` mismatch and run
`just _test-compile-fail` alongside both target selectors. Keep this negative
guarantee in Milestone A.

Suggested commit: `feat(tree): support named recursive schemas`.

## Task 4: Identifier fields and construction codecs — Milestone A

**Consumes:** Existing `tree/identifier.gleam` materialization and
`schema.validate_root_construction`, plus recursive/union descriptors.
**Produces:** `Identifier { Generate Assigned(String) }`,
`identifier(String, fn(record) -> Identifier) -> Property(record, Identifier)`,
and `encode_new(Compiled(a), a) -> Result(Option(TreeValue), TreeError)`.

- [ ] **1. Add strict/new-content encoding tests and run red.**

```gleam
type Item {
  Item(id: builder.Identifier, label: String)
}

fn item() -> builder.Node(Item) {
  builder.object2(
    builder.factory("com.example"),
    "Item",
    Item,
    builder.identifier("id", fn(value) { value.id }),
    builder.required("label", builder.string(), fn(value) { value.label }),
  )
}

pub fn typed_identifier_construction_test() {
  let assert Ok(compiled) = item() |> builder.root |> builder.compile
  builder.encode(compiled, Item(builder.Generate, "new"))
  |> expect.to_be_error
  builder.encode_new(compiled, Item(builder.Generate, "new"))
  |> expect.to_equal(Ok(Some(types.ObjectValue("com.example.Item", [
    #("label", types.StringValue("new")),
  ]))))
  builder.decode(compiled, Some(types.ObjectValue("com.example.Item", [
    #("id", types.StringValue("custom")),
    #("label", types.StringValue("new")),
  ])))
  |> expect.to_equal(Ok(Item(builder.Assigned("custom"), "new")))
}
```

- [ ] **2. Implement a private encode mode, not another allocator.**

The normal mode rejects `Generate`. Construction mode omits that property,
propagates recursively, and uses construction validation. `Assigned` emits its
exact string in either mode. Strict decode requires the native string field.
Compile only native object Identifier cardinality with the string leaf type.

Do not weaken normal `encode` validation to accommodate construction input.
No empty-string convention, application UUID creation, or mutation of records
is permitted.

- [ ] **3. Exercise native insertion and transaction allocation behavior.**

Use the existing Identifier tests' setup and compressor observations to insert
construction snapshots. Read back `Assigned` values, including recursively
nested fields and union branches. Confirm pure repeated `encode_new` produces
the same unallocated snapshot. Compare commit/abort/default allocation with
Task 1, including any preserved allocator watermark; do not assume abort means
no IDs were reserved.

- [ ] **4. Publish the authoring extension contract and run Milestone A gates.**

Update `docs/shared-tree-schema-authoring.md` with union mapping laws, named
lazy-reference rules, and strict snapshot versus new-content encoding. Include
the `Identifier` input/output limitation explicitly.

```sh
gleam test --target erlang -- shared_tree_schema_builder shared_tree_identifier
gleam test --target javascript -- shared_tree_schema_builder shared_tree_identifier
just _test-compile-fail
```

Suggested commit: `feat(tree): add typed identifier construction`.
Milestone A can release independently; live access is not yet exposed.

## Task 5: Prove and maintain node identity

**Consumes:** Forest `NodeRef`, kernel/branch reference APIs, transaction
promotion machinery, and Task 1 identity observations.
**Produces:** `live_anchor` registry, identity-to-current-path lookup, explicit
remapping/invalidation transitions, and the complete identity test matrix.

- [ ] **1. Add a low-level identity characterization before changing behavior.**

In `shared_tree_live_anchor_test.gleam`, use existing kernel/transaction/branch
test setup to save `reference_at` for an object in an array. Insert before it,
move it, reconcile, undo a removal, and promote a transaction. Call
`read_reference` and `ensure_attached` after each transition.

Record actual failures as tests for the required public behavior. Do not infer
stability merely because `NodeRef` is opaque. Use distinct objects with equal
labels and duplicate assigned Identifiers to rule out value-based matching.

- [ ] **2. Add these pure registry interfaces and tests.**

```gleam
new() -> Registry
open(Registry, branch.Origin, types.CheckoutSelector)
  -> #(Registry, live_types.ViewToken)
acquire(Registry, live_types.ViewToken, forest.NodeRef)
  -> Result(#(Registry, live_types.AnchorToken), live_types.LiveError)
resolve(Registry, branch.Origin, types.CheckoutSelector,
        live_types.AnchorToken, forest.Forest)
  -> Result(forest.NodeRef, live_types.LiveError)
status(Registry, branch.Origin, types.CheckoutSelector,
       live_types.AnchorToken, forest.Forest)
  -> Result(live_types.ReferenceStatus, live_types.LiveError)
close(Registry, live_types.ViewToken) -> Registry
```

`Registry`, `ViewToken`, and `AnchorToken` constructors are opaque outside their
defining modules. Define `ReferenceStatus` as
`Attached | Removed | Deleted | Invalidated`.

Intern repeated acquisitions for one view/node. Validate runtime/tree origin,
checkout, and token lifetime on every resolution. Keep tombstones so removed
or discarded content never retargets a later node. Closing a view drops its
registry entries and is idempotent.

- [ ] **3. Add identity-to-path lookup without a stale path cache.**

```gleam
// In forest; kernel and branch add matching checkout-aware adapters.
path_of_reference(Forest, NodeRef) -> Result(types.FieldPath, types.TreeError)
```

Traverse actual attached node IDs from the forest root. Return an error if the
node is detached or invalid. Do not materialize a JSON snapshot and search for
equal data. Preserve map keys and array indices using existing path semantics.

- [ ] **4. Preserve physical identity or produce explicit mappings at every transition.**

Use the characterization failures to identify exactly where existing physical
references change. Extend those transition results with:

```gleam
pub type IdentityChange {
  Promote(before: forest.NodeRef, after: forest.NodeRef)
  Discard(reference: forest.NodeRef)
  Forget(reference: forest.NodeRef)
}
```

`Promote` translates surviving preview/replayed identity, `Discard` invalidates
preview-only content, and `Forget` marks destroyed content deleted. Apply them
to the anchor registry at state publication, not after callbacks.

Reuse explicit node-origin/allocation information from the forest/change
application and existing preview promotion. If replay rebuilds a surviving
subtree, retain a mapping from its authored build identity and descendant
identity during replay; never derive a map from current position or content.
Map descendants as well as the inserted subtree root. Preserve allocation
watermarks so aborted IDs cannot become replacement identities.

Add registry remapping:

```gleam
apply_changes(Registry, branch.Origin, types.CheckoutSelector,
              List(IdentityChange)) -> Result(Registry, live_types.LiveError)
```

Reject conflicting mappings instead of silently assigning one node's anchors
to another. A missing mapping for a surviving identity is a failing gate, not
permission to weaken the API to typed paths.

- [ ] **5. Complete the identity matrix and run it on both targets.**

Cover all design section 7 transitions with the same native action inputs as
Task 1. Add descendants of moved/replayed nodes, duplicated custom identifiers,
equal-content replacements, removed retained content, destroyed repair data,
and live references acquired from a transaction preview.

```sh
gleam test --target erlang -- shared_tree_live_anchor shared_tree_branch shared_tree_transaction
gleam test --target javascript -- shared_tree_live_anchor shared_tree_branch shared_tree_transaction
```

Suggested commit: `feat(tree): preserve live node anchors`.
No live edit facade may ship until this matrix passes without identity
projection exceptions.

## Task 6: Atomic typed requests in the shared runtime core

**Consumes:** Task 5 anchor registry and existing checkout-aware edit submission.
**Produces:** Structured live requests/responses/errors and a single core
request processor. Existing low-level transitions maintain anchors too.

- [ ] **1. Define structured requests and errors in `live_types`.**

Request constructors cover binding/disposal, root read/replacement, reference
acquisition/read/status, property read/set/child acquisition, collection
read/edit/node acquisition, narrowing, and a two-anchor array move.

Use opaque tokens instead of public numeric IDs. Supply field schema metadata
for property operations; compare it with the actual bound node definition.
Token acquisitions return the actual node type and snapshot with the token,
allowing the typed layer to check/decode its evidence.

Use this shared protocol; `FieldProof` is the key plus native field definition
derived from a typed property, not a bypass of actual-node validation:

```gleam
pub type FieldProof {
  FieldProof(key: String, definition: schema.FieldSchema)
}

pub type Request {
  Bind(schema.ViewSchema)
  Close(ViewToken)
  RootRead(ViewToken)
  RootReplace(ViewToken, Option(types.TreeValue))
  RootAcquire(ViewToken, schema.Cardinality)
  Read(AnchorToken)
  Status(AnchorToken)
  PropertyRead(AnchorToken, FieldProof)
  PropertySet(AnchorToken, FieldProof, Option(types.TreeValue))
  ChildAcquire(AnchorToken, FieldProof)
  ArrayRead(AnchorToken, Int)
  ArrayAcquire(AnchorToken, Int)
  ArrayInsert(AnchorToken, Int, List(types.TreeValue))
  ArrayRemove(AnchorToken, Int, Int)
  ArrayMove(AnchorToken, Int, Int, AnchorToken, Int)
  MapRead(AnchorToken, String)
  MapAcquire(AnchorToken, String)
  MapSet(AnchorToken, String, types.TreeValue)
  MapDelete(AnchorToken, String)
  Narrow(AnchorToken, List(String))
}

pub type NodeEvidence {
  NodeEvidence(
    anchor: AnchorToken,
    identifier: String,
    snapshot: types.TreeValue,
  )
}

pub type Response {
  Bound(ViewToken)
  Done
  Snapshot(Option(types.TreeValue))
  Acquired(Option(NodeEvidence))
  ReferenceState(ReferenceStatus)
}
```

`Bind` returns `Bound`; successful edits/disposal return `Done`; reads return
`Snapshot`; acquisitions/narrowing return `Acquired`; status returns
`ReferenceState`. Missing optional fields/entries use `None`. Required
acquisitions reject absence. All acquisitions reject leaves before issuing a
token. Mismatched protocol responses become explicit internal errors in the
typed adapter, not successful empty results.

Strict versus construction encoding is selected before sending snapshots;
both submit through the same existing native construction/materialization
path. Do not add a second allocator or a wire-level typed-operation format.

Define these error categories without parsing strings:

```gleam
pub type LiveError {
  InvalidSchema(types.TreeError)
  InvalidValue(types.TreeError)
  IncompatibleView
  WrongProperty(key: String)
  WrongCardinality
  WrongKind(expected: String, actual: String)
  InvalidReference(ReferenceStatus)
  ClosedView
  DisposedCheckout
  ClosedRuntime
  ForeignOrigin
  RuntimeFailure(detail: String)
}
```

- [ ] **2. Add the atomic processor and a red stale-index regression.**

```gleam
live_request(
  core: Core,
  address: String,
  selector: types.CheckoutSelector,
  handle_view: schema.ViewSchema,
  request: live_types.Request,
) -> Result(
  #(Core, live_types.Response, List(ScopedTreeEvent),
    List(wire.OutboundOperation)),
  live_types.LiveError,
)
```

Seed nodes A and B; acquire B; perform an untyped insert before A; request a
property set through B's anchor. Assert only B changes, the submitted edit
addresses B's current location, and A/the inserted node do not change.

- [ ] **3. Resolve and author within one core state transition.**

The processor validates ownership, checkout status, handle/compiled/current
schema compatibility, anchor attachment, and expected property/container kind.
It derives the current path and routes through existing native edit submission
before returning. Two-anchor moves resolve both under the same state.

Use the active transaction's visible state when present. Validate complete
encoded batches before submission; a failing array element cannot leave a
partial insertion. Delegate Identifier materialization to the existing path.

- [ ] **4. Maintain anchors through untyped edits and inbound changes.**

Attach registry updates to state publication shared by typed/untyped edits,
remote reconciliation, transaction commit/abort, undo, merge/rebase, and
checkout disposal. Anchor maintenance cannot depend on a typed wrapper having
initiated the operation.

Read-only status can report removed/deleted nodes; read/edit requests must
reject them. Same-valued replacement and a reused Identifier string cannot
change which logical node an anchor identifies.

- [ ] **5. Add error/atomicity cases and run the native selectors.**

Test foreign tree/runtime/checkout, closed view, incompatible schema,
wrong property with the same record type, removed/destroyed references, and
multi-value edit failure. Compare forest/outbound operations before and after
refused edits; preserve the pinned compressor reservation semantics.

```sh
gleam test --target erlang -- shared_tree_live shared_tree_runtime
gleam test --target javascript -- shared_tree_live shared_tree_runtime
```

Suggested commit: `feat(tree): dispatch atomic anchored operations`.

## Task 7: Typed live API and both native facades

**Consumes:** Task 6 requests and all descriptor/root/property codecs.
**Produces:** The complete typed read/edit/navigation API from design section 6
and `tree_typed` on JS and BEAM.

- [ ] **1. Expose a narrow internal builder bridge.**

Add internal functions:

```gleam
property_root(Property(record, a)) -> Root(a)
property_definition(Property(record, a)) -> #(String, schema.FieldSchema)
allowed_types(Node(a)) -> List(String)
```

Also expose internal root-cardinality metadata for `Compiled(a)`. These
functions reveal validated descriptor metadata, not constructors for unchecked
properties. An optional property's root codec must preserve absence semantics.

- [ ] **2. Bind the pure live module through backend callbacks.**

`live.gleam` must import neither runtime facade. Its internal backend accepts
structured requests and returns structured responses; the facades close over
their existing runtime, address, selector, and handle view.

```gleam
// Internal live-module adapter; not an application construction API.
pub type Backend {
  Backend(
    request: fn(live_types.Request) ->
      Result(live_types.Response, live_types.LiveError),
    subscribe: fn(fn() -> Nil) ->
      Result(fn() -> Nil, live_types.LiveError),
  )
}

bind(builder.Compiled(a), Backend) -> Result(View(a), live_types.LiveError)

// Matching signatures in watershed and watershed_beam.
tree_typed(tree: SharedTree, schema: builder.Compiled(a))
  -> Result(live.View(a), live_types.LiveError)
```

JS processes the request synchronously against its current cell and publishes
core results before events. BEAM sends one actor request, performs the same
pure transition, then replies. It must not make separate resolve/edit calls.
`bind` sends `Bind` and stores the returned view token. The backend subscription
returns a cleanup function; the typed subscription owns it and invokes it once
when unsubscribing or disposing its view. Mark adapter exports `@internal`.

- [ ] **3. Add typed root/property tests red, then implement them.**

Use a compiled `Card` object and a native tree from the existing facade test
harness. The essential public behavior is:

```gleam
let assert Ok(view) = facade.tree_typed(tree, compiled)
let assert Ok(card) = live.required_root(view)
let assert Ok(Nil) = live.set(card, title_property, "Updated")
let assert Ok("Updated") = live.get(card, title_property)
let assert Ok(snapshot) = live.read(card)
snapshot.title |> expect.to_equal("Updated")
```

Run this with `facade` imported as the target's actual module. Define typed
properties once and reuse them in the object descriptor and live calls.
Reject mismatching property metadata even if its record/value type parameters
match. Identifier property writes return an explicit refusal.

For required/optional child refs, derive a child codec from the property's
root codec. Optional navigation unwraps the optional read result without
casts. Root/child leaf acquisition is a kind error, not a fake node reference.
Narrowing checks the actual node identifier and branch declaration while
retaining its anchor.

- [ ] **4. Implement collections and construction-aware writes.**

Implement all collection signatures from design section 6. Check kind and
cardinality explicitly. New-content methods call `encode_new`; normal methods
use strict `encode`. Preserve optional absence versus explicit null.

Snapshots supplied to setters are new content, even if equal to existing
content. A live reference is not accepted as an insertable value. Moves use
the explicit two-reference operation and retain source node identity.

- [ ] **5. Run both runtime/facade paths and commit.**

```sh
gleam test --target erlang -- shared_tree_live facade_parity
gleam test --target javascript -- shared_tree_live facade_parity
```

Suggested commit: `feat(tree): expose typed live operations`.

## Task 8: Lifecycle, transaction/branch integration, and observation

**Consumes:** Typed views/references, the anchor publication path, and existing
native transaction, checkout, revertible, and subscription behavior.
**Produces:** All lifecycle guarantees and both observation functions from
design sections 7–8.

- [ ] **1. Add transition tests using the same saved references.**

For each case, acquire once, perform the native transition, and use that saved
reference afterward. A new lookup is not a substitute for proving stability.
Assert:

| Case | Result |
| --- | --- |
| Move/reconciliation/reconnect | Same attached node; no retarget. |
| Remove then undo | `Removed` then `Attached` for the same identity. |
| Equal-data/equal-Identifier replacement | Old reference stays removed. |
| Successful transaction | Surviving preview references become valid committed references. |
| Aborted transaction | Preexisting refs remain correct; preview-only refs are `Invalidated`. |
| Fork and edits in each checkout | Independent refs and data. |
| Rebase/merge | Surviving identity preserved; disposed-source access refused. |
| Incompatible upgrade | Explicit incompatibility, not automatic descriptor rebinding. |
| View disposal/runtime shutdown | Explicit lifetime error; no accidental document close. |

Pure core coverage is required on both targets; add wrapper cases where actor
or callback behavior differs.

- [ ] **2. Implement observation through existing invalidation subscriptions.**

```gleam
observe(View(a), fn(Result(a, LiveError)) -> Nil)
  -> Result(Subscription, LiveError)
observe_node(Ref(a), fn(Result(a, LiveError)) -> Nil)
  -> Result(Subscription, LiveError)
unsubscribe(Subscription) -> Nil
```

The backend supplies existing checkout subscriptions and cleanup callbacks.
Re-read after committed state publication; do not emit from preview mutation.
Do not imply exact Fluid per-node event counts. Initial reads remain explicit.

Test a callback observing an updated snapshot, removed-node/incompatible-view
errors, no callback after unsubscribe/dispose, late subscription cleanup,
and exception reporting through the existing native policy.

- [ ] **3. Implement deterministic disposal and non-pinning references.**

View disposal cancels its subscriptions and frees anchor/tombstone bookkeeping
without closing the native document or branch. Repeated disposal succeeds.
Anchors do not extend repair-data/history retention: prune a removed node
through the existing retention path and observe terminal `Deleted`.

- [ ] **4. Run lifecycle/transaction/branch gates and commit.**

```sh
gleam test --target erlang -- shared_tree_live shared_tree_transaction shared_tree_branch shared_tree_undo
gleam test --target javascript -- shared_tree_live shared_tree_transaction shared_tree_branch shared_tree_undo
```

Suggested commit: `feat(tree): complete typed live lifecycles`.

## Task 9: Static typing and independent behavioral acceptance

**Consumes:** Completed authoring/live APIs and Task 1's independent fixtures.
**Produces:** Compile-fail checks and a fixture runner that cannot manufacture
success from expected output.

- [ ] **1. Add positive compiled examples before negative fixtures.**

Cover unions, the recursive `Outline`, generated/assigned IDs, typed object
properties, optional children, union narrowing, maps, arrays, and typed moves.
All must compile on the intended target before negative diagnostics count.

- [ ] **2. Retain the two authoring fixtures and add two live fixtures.**

Tasks 2–3 already register the union/recursive fixtures. Re-run their intended
diagnostics alongside these new live packages. The four deliberate errors are:

```gleam
// incompatible_tree_union: injector expects Float, node decodes String.
builder.variant(builder.string(), fn(value: Float) { value }, fn(value) {
  Some(value)
})
```

```gleam
// incompatible_tree_recursive: return type disagrees with the thunk.
pub fn bad() -> builder.Node(String) {
  builder.lazy(builder.factory("com.example"), "Wrong", fn() {
    builder.number()
  })
}
```

```gleam
// incompatible_tree_live_property: the property has another record type.
pub fn bad(ref: live.Ref(Card), field: builder.Property(Person, String)) {
  live.get(ref, field)
}
```

```gleam
// incompatible_tree_live_insert: live references are not snapshot input.
pub fn bad(items: live.Ref(List(Card)), card: live.Ref(Card)) {
  live.array_insert(items, 0, [card])
}
```

Include imports and concrete `Card` / `Person` record declarations so only
the intended type mismatch fails. Copy dependency structure from the existing
fixture packages, not a new test framework. Register each in
`justfile:_test-compile-fail`; match observed type diagnostics, not just exit
status. Existing Trellis wildcard exclusions already cover the directories.

- [ ] **3. Implement the native scenario runner and mutation checks.**

In `typed_api_fixture.gleam`, decode scenario action inputs, execute actual
authoring/core/live operations, and return normalized observations. Match
Task 1's authoring and live documents, reference pins, and exact scenario-ID
sets. Include explicit named projections for stronger removed-node refusal
and conservative event counts; none may hide identity mismatches.

Change an operation target, move destination, union variant, or Identifier
request in controlled inputs and prove the native observations change or the
operation errors. Do not compute native results from expected observations.

- [ ] **4. Run all targeted gates and deterministic oracle comparison.**

```sh
just _test-compile-fail
gleam test --target erlang -- shared_tree_schema_builder shared_tree_live
gleam test --target javascript -- shared_tree_schema_builder shared_tree_live
node --test tools/shared-tree-oracle/source.test.mjs
node --input-type=module -e 'import { runSource } from "./tools/shared-tree-oracle/source.mjs"; await runSource("tools/shared-tree-oracle/.output/typed-api", { corpus: true });'
cmp test/fixtures/shared_tree/typed-api-authoring.json tools/shared-tree-oracle/.output/typed-api/typed-api-authoring.json
cmp test/fixtures/shared_tree/typed-api-live.json tools/shared-tree-oracle/.output/typed-api/typed-api-live.json
```

Suggested commit: `test(tree): enforce typed live contracts`.

## Task 10: Runnable example, service proof, and public documentation

**Consumes:** Accepted typed APIs and existing two-client JS/BEAM test clients.
**Produces:** A migrated item-counter, a live service scenario, and truthful
public documentation. No protocol-version or supported-profile expansion.

- [ ] **1. Convert item-counter operations to the live array API.**

Keep its string-array descriptor, namespace, create/connect/open flow,
development auth warning, URL ID, cleanup, and user-visible controls.
Bind the existing tree with `tree_typed`, obtain its root array reference,
and use typed array insert/remove and root reads. Derive count from shared
data, never button clicks. Remove obsolete manual snapshot/edit glue only
where the new operations replace it.

Retain tests for insert-at-start, zero-length removal no-op, wrong-root errors,
cleanup, and explicit failures. Update source markers and the native comparison
copy so it distinguishes live references from snapshot values and explains
their runtime-local lifetime.

```sh
(cd examples/shared_tree_item_counter_lustre && gleam test && pnpm run build)
just snippets
(cd website && node --strip-types --test src/data/sharedtree-item-counter.test.ts src/lib/snippet-manifest.test.ts)
```

- [ ] **2. Add typed commands to the existing acceptance clients and driver.**

Extend `client_protocol.gleam`, `client_js.gleam`, and `client_beam.gleam` with
typed bind/acquire/read/set/move/status commands. Keep reference tokens in each
client process; never serialize native tokens to the driver. The driver uses
client-local labels such as `"saved-B"`, which each client resolves locally.

Add a `typed-live` scenario to `client-interop.mjs` and a `--scenario typed-live`
selector that leaves existing default scenarios intact. Exercise:

1. Two clients load a schema with a heterogeneous array and Identifier fields.
2. One saves a reference to B while the other inserts/moves nearby content.
3. The saved reference edits B after sequencing; A and the new node stay unchanged.
4. Construction defaults allocate distinct generated values through the native runtime.
5. Remove/undo and local fork/rebase/merge preserve the specified identity rules.
6. Reconnect retains surviving runtime-local references.
7. Fresh load preserves data/assigned identifiers but obtains new local references.

Reuse the owned transport gate to control ordering. Compare exact identity
observations and emitted native operations as well as final data. Add driver
tests for the new action responses and rejected stale labels.

- [ ] **3. Run targeted service acceptance with explicit ownership.**

```sh
node --test tools/shared-tree-oracle/client-driver.test.mjs tools/shared-tree-oracle/client-interop.test.mjs
just shared-tree-test
npm --prefix tools/shared-tree-oracle run client:interop -- --local-floodgate --scenario typed-live
just shared-tree-item-counter
```

Use an existing approved local Floodgate or explicitly start an owned instance
with repository tooling. Do not stop a shared service. Missing service/browser
prerequisites are blockers, not passing live evidence.

- [ ] **4. Publish docs and verify the whole affected feature.**

Create `docs/shared-tree-typed-live-api.md`. Explain snapshot versus reference
types, field descriptors, union narrowing, generated IDs, read-only Identifier
properties, composite-only refs, index-versus-identity semantics, branch/runtime
ownership, disposal, and conservative subscriptions. Include a Fluid mapping
table and the full lifetime/refusal matrix. Link from the root README and
authoring guide; document new oracle/service commands.

```sh
gleam test --target erlang -- shared_tree
gleam test --target javascript -- shared_tree
just _test-compile-fail
(cd website && pnpm build)
```

Suggested commit: `docs(tree): publish typed live SharedTree API`.

## Acceptance coverage

| Requirement | Tasks |
| --- | --- |
| Pinned upstream semantics and deterministic evidence | 1, 9 |
| Union typing, disjointness, and mapping failures | 2, 9 |
| Named/mutual recursion and finite compilation | 3, 9 |
| Strict snapshots versus construction defaults | 4, 7, 9 |
| Stable identities and explicit preview/replay mappings | 5, 6, 8 |
| Atomic edits, wrong-property refusal, both runtime wrappers | 6, 7 |
| Root/property/collection APIs and union narrowing | 7, 9 |
| Transactions, undo, branches, disposal, invalidation | 5, 6, 8 |
| Conservative observation and late cleanup | 8 |
| Runnable example, website snippets, service proof, documentation | 10 |

Completion requires both native targets, intended negative diagnostics,
independent fixture comparisons, and the named service/browser checks. Report
unrun gates explicitly. Neither passing snapshot tests nor a new node lookup
after each edit proves that a previously saved reference preserved identity.
