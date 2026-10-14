# SharedTree Typed Application API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make SharedTree the single, checked, typed tree API for Gleam applications, with identity-bound node handles and a real Lustre consumer, without waiting for or expanding the remaining M7 lifecycle slices.

**Architecture:** Add a target-independent typed vocabulary over the existing stored/view schemas and internal `TreeValue` representation. Extend the existing runtime with atomic reference-bound access, then change both facades to expose `SharedTree(schema, record)` and typed `tree_*` operations. Migrate existing facade callers and the SharedTree Lustre checklist; keep the runtime, wire formats, transaction machinery, and application-owned history.

**Tech Stack:** Gleam, the existing JavaScript and Erlang runtimes, Lustre, startest/gleeunit, existing compile-fail fixtures, and the pinned SharedTree interoperability harness.

**Spec:** [Native SharedTree design](../specs/2026-09-21-shared-tree-design.md), especially sections 5, 6, and M7 in section 8; [accepted handles/attachment design](../specs/2026-10-10-shared-tree-handles-attachment-design.md) for the supported lifecycle and handle boundary.

**Status:** Approved for implementation on 2026-10-13. The user authorized
commits to `main` as each bounded task passed its required review and gates.
All seven tasks and final review are complete. The serial acceptance gates
passed on `39040d6e`; final review found one closed-actor root-access bug,
fixed and verified in `90739e50`. The implementation range is
`87ce132e..90739e50`. This authorization excludes pushes, hosted workflows,
releases, and scope outside this plan.

**Baseline:** `87ce132e858d90c07c1e0f31a1cae0f5a9a3ef7d`. The accepted implementation underneath it is `c0fff951e128776c3f670d22f017482dc24d00c4`.

## Global Constraints

- Keep JavaScript and BEAM behavior equivalent; only their existing subscription and effect mechanisms differ.
- Keep Fluid 3.1.0 at `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960` and Floodgate at `0eb493fc46d1bb9baf1151a6ccdde93544e057e7`.
- Preserve Message V7, TreeChange V5, Modular V5, Schema V2, FieldBatch V2, and minimum collaboration version 2.117.0.
- Add no dependencies, generator, proxy-object system, plugin registry, or second runtime. New compile-fail fixture manifests may copy the existing local-package dependency pattern.
- Expose only `SharedTree(schema, record)` through the application facades. Replace their raw path/`TreeValue` read and edit signatures; do not add `TypedTree`, raw/typed conversion functions, deprecated raw aliases, or a parallel untyped tree facade.
- Treat this as an intentional breaking application API migration within the current experimental SharedTree profile. Migrate all repository callers, fixtures, bindings, and active documentation in the same slice. Keep raw schemas, paths, values, and edit machinery in the existing protocol/runtime layers.
- Static types do not replace stored/view compatibility checks, validation of local edits, or validation after remote schema changes.
- Resolve operation targets from tree identity, not saved JSON paths, application IDs, array indices, equal values, UUID order, or timestamps.
- A rejected operation changes no visible state, pending commits, compressor state, subscriptions, or outbound messages. Preserve the existing transaction rollback allocation rule; do not apply this local-edit rule to change that established rollback behavior.
- Preserve local/remote event distinctions, revisions, inverse acquisition windows, disposal callbacks, and settlement outcomes.
- Preserve existing handle binding and source-datastore context. A Fluid channel handle is not a forest node reference.
- STE applies only to Gleam comments and error strings. Follow `AGENTS.md`; do not edit APM-managed files, `.code-map/`, or generated fixture/snippet bytes.
- Do not declare all of M7 complete, dispatch hosted workflows, publish a release, or push as part of this plan.

---

## 1. Scope and decisions for review

The public tree API is **SharedTree, which is typed**. Applications supply a checked schema definition when creating, opening, or resolving a tree. They use the resulting `SharedTree(schema, record)` directly for reads, edits, subscriptions, transactions, branches, and handle storage. They do not open an untyped tree and then opt into another API.

The first slice uses **hand-authored typed fields and record adapters**,
following the existing `TypedMap` declaration pattern. A generator is not
needed to test the API against a real application. The user approved this
declaration choice and the single typed SharedTree surface before source work.

Included:

- Checked typed views over existing schemas.
- String, number, boolean, null, and supported handle-valued fields.
- Separate required and optional field access; read-only identifier fields.
- Typed immutable record snapshots and explicit new-node builders.
- Live, identity-bound object, map, and array access.
- Typed field updates and existing collection operations, including identity-bound item removal and movement.
- Existing transaction, event, branch, undo/redo, and close behavior, without a new history abstraction.
- Migration of existing constructors, handle-field helpers, facade tests/probes, website runtime, Lustre effects, and the checklist to the single typed surface.

Excluded:

- Schema-to-Gleam generation, TypeScript-style proxies, and a universal record-builder arity family.
- Arbitrary factories/layouts, new aliases, datastore-entry-point leaves, blob/pending-payload and cross-container handles, arbitrary Fluid object implementations.
- Production authentication, durable pending-state recovery, GC sweep, or persistent/shared branches.
- New field-level event payloads or reactive subscriptions that the current kernel cannot substantiate.
- Implicit schema upgrades, whole-record live replacement as a convenience update, and automatic application undo-stack management.
- A separate `TypedTree` handle, `tree_typed_*` operations, raw escape hatches, and backward-compatible untyped application reads/edits.

### Approval gate

The user approved sections 1-4 on 2026-10-13: hand-authored adapters,
reference-bound access, the names and types below, separate snapshots and
construction inputs, and migration of every active caller. SharedTree itself
is typed. The approval did not add a generator or a broader
application/container API.

## 2. Why an identity task comes first

The current public facades expose `tree_get`, `tree_set`, and collection operations through `FieldPath`; this plan replaces those application signatures. The pure forest already has opaque `NodeRef` values, `locate`, `read_node`, and `is_attached`; the kernel exposes `reference_at`, `read_reference`, and `ensure_attached`.

The missing boundary is **an operation that resolves a captured reference against the current selected checkout and applies the edit in the same runtime operation**. A typed wrapper around a saved path would look safe while still editing the wrong item after a reorder. A BEAM implementation that reads a path in one actor request and edits it in another would have the same race.

Add that boundary; do not change changeset or rebase algorithms. Begin with an attached-tree traversal to recover a reference's current path. Do not introduce a parent index before measuring a need for it.

A typed node is local to its originating runtime, channel, checkout, and view. It follows moves within that checkout. It does not become a persistent identifier across close/reload, nor can it be transferred to a fork by copying its reference. Capture a new node in the destination checkout.

Removed or replaced nodes must never retarget to a replacement at the same path. The first API permits live access only while the node is attached. Retained data and undo continue using the existing kernel; a reference may become usable again if undo reattaches the same retained identity. Test that behavior rather than inventing a resurrection mapping.

## 3. Proposed API contract

These are new interfaces, not claims that the functions already exist. All names below must stay consistent across tasks.

### 3.1 Pure declarations: `watershed/tree/typed`

This module contains schema declarations and value adapters for SharedTree. It does not expose a second tree handle or a separate tree access API. Keep `TreeValue` conversion here for codec/building work; application tree operations accept typed descriptors and inputs rather than encoded values.

```gleam
pub type Required
pub type Optional

pub type Error {
  AccessFailed(reason: String)
  DecodeFailed(reason: String)
  InvalidDeclaration(reason: String)
  MissingRequired(field: String)
}

pub opaque type Codec(a)
pub opaque type NodeCodec(schema, record)
pub opaque type Builder(schema, input)
pub opaque type Schema(schema, record)
pub opaque type Field(schema, a, cardinality)
pub opaque type IdentifierField(schema)
pub opaque type ChildField(parent, child, record, cardinality)
pub opaque type ArrayField(parent, item, record)
pub opaque type MapField(parent, item, record)
```

`Codec(a)` encodes and decodes leaf values and records its allowed leaf identifiers. `NodeCodec(schema, record)` identifies and decodes a node into an immutable application record. `Builder(schema, input)` constructs a new `TreeValue`; its input need not be the decoded record type. This matters for generated identifier fields: construction can omit an identifier that reads must expose.

`Schema(schema, record)` holds the existing strict `ViewSchema` and root `NodeCodec`; it does not author or upgrade stored schemas.

Public declaration functions:

```gleam
pub fn string() -> Codec(String)
pub fn number() -> Codec(Float)
pub fn boolean() -> Codec(Bool)
pub fn null() -> Codec(Nil)
pub fn handle() -> Codec(handle.Reference)
pub fn encode(codec: Codec(a), value: a) -> Result(types.TreeValue, Error)
pub fn decode(codec: Codec(a), value: types.TreeValue) -> Result(a, Error)

pub fn node(
  identifier: String,
  decode: fn(types.TreeValue) -> Result(record, Error),
) -> Result(NodeCodec(schema, record), Error)

pub fn builder(
  identifier: String,
  encode: fn(input) -> Result(types.TreeValue, Error),
) -> Result(Builder(schema, input), Error)

pub fn build(
  builder: Builder(schema, input),
  value: input,
) -> Result(types.TreeValue, Error)

pub fn schema(
  view: tree_schema.ViewSchema,
  root: NodeCodec(schema, record),
) -> Result(Schema(schema, record), Error)

pub fn required(key: String, codec: Codec(a)) -> Field(schema, a, Required)
pub fn optional(key: String, codec: Codec(a)) -> Field(schema, a, Optional)
pub fn identifier(key: String) -> IdentifierField(schema)
pub fn required_child(key: String, codec: NodeCodec(child, record))
  -> ChildField(parent, child, record, Required)
pub fn optional_child(key: String, codec: NodeCodec(child, record))
  -> ChildField(parent, child, record, Optional)
pub fn array_field(key: String, array_type: String, item: NodeCodec(item, record))
  -> ArrayField(parent, item, record)
pub fn map_field(key: String, map_type: String, item: NodeCodec(item, record))
  -> MapField(parent, item, record)
```

Keep constructors private. The facades use these target-independent accessors and validators:

```gleam
pub fn schema_view(definition: Schema(s, r)) -> tree_schema.ViewSchema
pub fn schema_root(definition: Schema(s, r)) -> NodeCodec(s, r)
pub fn node_identifier(codec: NodeCodec(s, r)) -> String
pub fn decode_node(codec: NodeCodec(s, r), value: types.TreeValue) -> Result(r, Error)
pub fn builder_identifier(builder: Builder(s, input)) -> String
pub fn field_key(field: Field(s, a, c)) -> String
pub fn field_is_optional(field: Field(s, a, c)) -> Bool
pub fn encode_field(field: Field(s, a, c), value: a) -> Result(types.TreeValue, Error)
pub fn decode_field(field: Field(s, a, c), value: types.TreeValue) -> Result(a, Error)
pub fn identifier_key(field: IdentifierField(s)) -> String
pub fn child_key(field: ChildField(s, child, r, c)) -> String
pub fn child_codec(field: ChildField(s, child, r, c)) -> NodeCodec(child, r)
pub fn child_is_optional(field: ChildField(s, child, r, c)) -> Bool
pub fn array_key(field: ArrayField(s, item, r)) -> String
pub fn array_identifier(field: ArrayField(s, item, r)) -> String
pub fn array_codec(field: ArrayField(s, item, r)) -> NodeCodec(item, r)
pub fn map_key(field: MapField(s, item, r)) -> String
pub fn map_identifier(field: MapField(s, item, r)) -> String
pub fn map_codec(field: MapField(s, item, r)) -> NodeCodec(item, r)
pub fn validate_field(view: tree_schema.ViewSchema, owner: String, field: Field(s, a, c))
  -> Result(Nil, Error)
pub fn validate_identifier(view: tree_schema.ViewSchema, owner: String, field: IdentifierField(s))
  -> Result(Nil, Error)
pub fn validate_child(view: tree_schema.ViewSchema, owner: String, field: ChildField(s, child, r, c))
  -> Result(Nil, Error)
pub fn validate_array(view: tree_schema.ViewSchema, owner: String, field: ArrayField(s, item, r))
  -> Result(Nil, Error)
pub fn validate_map(view: tree_schema.ViewSchema, owner: String, field: MapField(s, item, r))
  -> Result(Nil, Error)
```

Descriptor checking uses `tree_schema.view_to_stored`, `root_field_schema`, `node_schema`, `field_schema`, `map_entry_schema`, and `array_element_schema`. Check the owner identifier, cardinality, and allowed value identifiers before access. Never infer a schema from a Gleam record name.

### 3.2 Pure reference operations: `watershed/tree/node`

```gleam
pub type Edit {
  SetField(key: String, value: types.TreeValue)
  ClearField(key: String)
  MapSet(key: String, value: types.TreeValue)
  MapDelete(key: String)
  ArrayInsert(index: Int, values: List(types.TreeValue))
  ArrayRemove(start: Int, end: Int)
  ArrayMove(
    start: Int,
    end: Int,
    destination: forest.NodeRef,
    destination_gap: Int,
  )
  RemoveNode(child: forest.NodeRef)
  MoveNode(
    child: forest.NodeRef,
    destination: forest.NodeRef,
    before: Option(forest.NodeRef),
  )
}

pub fn resolve(
  state: tree_kernel.TreeState,
  source: forest.NodeRef,
  edit: Edit,
) -> Result(types.Edit, types.TreeError)
```

Array ranges keep the existing half-open `[start, end)` convention. Positional insertion/range methods address the current sequence at call time. `RemoveNode` and `MoveNode` instead identify the captured item, and verify its current direct parent. `before: None` means the current end of the destination array; `Some(reference)` must be a current direct child of that destination.

Resolve source, child, destination, and optional sibling from one current tree state. Preserve the current native no-op and schema-validation behavior. Do not submit an edit if resolution fails.

### 3.3 Matching public facades

Change the existing `SharedTree` type in both `watershed` and `watershed_beam`; do not wrap it in a second public tree type:

```gleam
pub opaque type SharedTree(schema, record)
pub opaque type TreeNode(schema, record)
pub opaque type TreeArray(item, record)
pub opaque type TreeMap(item, record)
```

`SharedTree` stores the existing runtime, address, and checkout selector plus its checked `typed.Schema`. Each node/collection carries that origin, a reference, and the relevant descriptor. Do not cache paths or decoded records. The node and collection types are access handles within SharedTree, not independent tree APIs.

#### Creation and resolution

Replace the existing constructor signatures on both targets:

```gleam
pub fn create_tree(
  document: Document(root),
  definition: typed.Schema(s, r),
  builder: typed.Builder(s, input),
  initial_root: Option(input),
) -> Result(SharedTree(s, r), typed.Error)
pub fn create_tree_in(
  document: Document(root),
  store: DataStore,
  definition: typed.Schema(s, r),
  builder: typed.Builder(s, input),
  initial_root: Option(input),
) -> Result(SharedTree(s, r), typed.Error)
pub fn resolve_tree(
  document: Document(root), value: Json, definition: typed.Schema(s, r),
) -> Result(SharedTree(s, r), typed.Error)
pub fn open_tree(
  document: Document(root), value: Json, definition: typed.Schema(s, r),
) -> Result(SharedTree(s, r), typed.Error)

pub fn set_tree_field(
  map: TypedMap(owner),
  field: ChannelField(owner, schema.TreeChannel),
  tree: SharedTree(s, r),
) -> Nil
pub fn resolve_tree_field(
  document: Document(root),
  map: TypedMap(owner),
  field: ChannelField(owner, schema.TreeChannel),
  definition: typed.Schema(s, r),
) -> Result(Option(SharedTree(s, r)), typed.Error)
```

`create_tree_container` also takes `(config, definition, builder, initial_root)` instead of `(config, stored, initial_root)`. JS returns `Promise(Result(String, typed.Error))`; BEAM returns `Result(String, typed.Error)`. Derive the stored creation schema from `tree_schema.view_to_stored(typed.schema_view(definition))`, verify the builder's root identifier, and encode the initial input before allocating or making a service request. Preserve the accepted container layout and native identifier-construction rules.

`resolve_tree` checks stored/view compatibility without upgrading. Preserve `open_tree`'s inspection/explicit-upgrade use: it carries the typed definition even when the stored schema is incompatible, and reads/edits fail until compatibility permits them. No constructor returns an untyped handle, and no bind/raw conversion function is needed.

#### Reads and edits

Replace the existing application read/edit functions with this shared surface:

```gleam
pub fn tree_root(tree: SharedTree(s, r))
  -> Result(Option(TreeNode(s, r)), typed.Error)
pub fn tree_read_root(tree: SharedTree(s, r))
  -> Result(Option(r), typed.Error)
pub fn tree_set_root(
  tree: SharedTree(s, r), builder: typed.Builder(s, input), value: input,
) -> Result(Nil, typed.Error)
pub fn tree_clear_root(tree: SharedTree(s, r)) -> Result(Nil, typed.Error)
pub fn tree_read(node: TreeNode(s, r)) -> Result(r, typed.Error)

pub fn tree_get(node: TreeNode(s, r), field: typed.Field(s, a, typed.Required))
  -> Result(a, typed.Error)
pub fn tree_get_optional(node: TreeNode(s, r), field: typed.Field(s, a, typed.Optional))
  -> Result(Option(a), typed.Error)
pub fn tree_set(node: TreeNode(s, r), field: typed.Field(s, a, c), value: a)
  -> Result(Nil, typed.Error)
pub fn tree_clear(node: TreeNode(s, r), field: typed.Field(s, a, typed.Optional))
  -> Result(Nil, typed.Error)
pub fn tree_identifier(node: TreeNode(s, r), field: typed.IdentifierField(s))
  -> Result(String, typed.Error)

pub fn tree_child(node: TreeNode(s, r), field: typed.ChildField(s, child, value, c))
  -> Result(Option(TreeNode(child, value)), typed.Error)
pub fn tree_set_child(
  node: TreeNode(s, r),
  field: typed.ChildField(s, child, value, c),
  builder: typed.Builder(child, input),
  value: input,
) -> Result(Nil, typed.Error)
pub fn tree_clear_child(
  node: TreeNode(s, r),
  field: typed.ChildField(s, child, value, typed.Optional),
) -> Result(Nil, typed.Error)

pub fn tree_array(node: TreeNode(s, r), field: typed.ArrayField(s, item, value))
  -> Result(TreeArray(item, value), typed.Error)
pub fn tree_as_array(node: TreeNode(s, r), item: typed.NodeCodec(item, value))
  -> Result(TreeArray(item, value), typed.Error)
pub fn tree_array_nodes(array: TreeArray(item, value))
  -> Result(List(TreeNode(item, value)), typed.Error)
pub fn tree_array_get(array: TreeArray(item, value), index: Int)
  -> Result(Option(value), typed.Error)
pub fn tree_array_values(array: TreeArray(item, value))
  -> Result(List(value), typed.Error)
pub fn tree_array_insert(
  array: TreeArray(item, value),
  gap: Int,
  builder: typed.Builder(item, input),
  values: List(input),
) -> Result(Nil, typed.Error)
pub fn tree_array_remove(array: TreeArray(item, value), start: Int, end: Int)
  -> Result(Nil, typed.Error)
pub fn tree_array_move(
  source: TreeArray(item, value),
  start: Int,
  end: Int,
  destination: TreeArray(item, value),
  destination_gap: Int,
) -> Result(Nil, typed.Error)
pub fn tree_array_remove_node(array: TreeArray(item, value), node: TreeNode(item, value))
  -> Result(Nil, typed.Error)
pub fn tree_array_move_before(
  source: TreeArray(item, value),
  node: TreeNode(item, value),
  destination: TreeArray(item, value),
  before: Option(TreeNode(item, value)),
) -> Result(Nil, typed.Error)

pub fn tree_map(node: TreeNode(s, r), field: typed.MapField(s, item, value))
  -> Result(TreeMap(item, value), typed.Error)
pub fn tree_as_map(node: TreeNode(s, r), item: typed.NodeCodec(item, value))
  -> Result(TreeMap(item, value), typed.Error)
pub fn tree_map_get(map: TreeMap(item, value), key: String)
  -> Result(Option(value), typed.Error)
pub fn tree_map_node(map: TreeMap(item, value), key: String)
  -> Result(Option(TreeNode(item, value)), typed.Error)
pub fn tree_map_entries(map: TreeMap(item, value))
  -> Result(List(#(String, value)), typed.Error)
pub fn tree_map_keys(map: TreeMap(item, value))
  -> Result(List(String), typed.Error)
pub fn tree_map_set(
  map: TreeMap(item, value),
  key: String,
  builder: typed.Builder(item, input),
  value: input,
) -> Result(Nil, typed.Error)
pub fn tree_map_delete(map: TreeMap(item, value), key: String)
  -> Result(Nil, typed.Error)

pub fn tree_transaction(
  tree: SharedTree(s, r),
  constraints: List(TreeTransactionConstraint),
  callback: fn(SharedTree(s, r)) -> Result(value, callback_error),
) -> Result(value, TreeTransactionError(callback_error))
```

Subsequent operations use the definition's strict view and recheck it through the current selected checkout. Missing optional fields return `None`; null leaves decode as present `Nil`. A missing required child is `MissingRequired`, not `None`. Identifier fields are read-only and cannot be passed to `tree_set`.

`array_field` and `map_field` are conveniences for required collection fields. For an optional collection, capture it through `optional_child` and convert its present node with `tree_as_array`/`tree_as_map`. The same conversions support map/array roots. Verify the actual node kind/identifier and item types; do not just attach another phantom tag. Leaf roots use their node codec. Explicit root replacement uses a matching typed builder, invalidates old root/descendant handles, and follows the existing schema rules. `tree_clear_root` checks root cardinality and rejects clearing a required root without mutation.

Collection value reads decode one current snapshot: array values come from one reference-bound read of the entire array, and map entries from one reference-bound entries read. `tree_read_root` reads and decodes the root from one current selected-state read. Do not assemble a purported snapshot by reading each node in separate actor requests. Node-list reads provide live handles, not a frozen list of decoded records.

#### Existing lifecycle operations

Keep the existing lifecycle names and behavior, and make their tree arguments generic:

```gleam
pub fn tree_fork(tree: SharedTree(s, r)) -> Result(SharedTree(s, r), String)
pub fn tree_rebase_onto(source: SharedTree(s, r), target: SharedTree(s, r))
  -> Result(Nil, String)
pub fn tree_merge(
  target: SharedTree(s, r), source: SharedTree(s, r), dispose_source: Bool,
) -> Result(Nil, String)
pub fn tree_branch_status(tree: SharedTree(s, r)) -> TreeBranchStatus
pub fn tree_dispose_branch(tree: SharedTree(s, r)) -> Result(Nil, String)
pub fn tree_compatibility(tree: SharedTree(s, r))
  -> Result(tree_schema.Compatibility, String)
pub fn tree_upgrade_schema(tree: SharedTree(s, r)) -> Result(Nil, String)
pub fn tree_handle_of(tree: SharedTree(s, r)) -> Json
```

`subscribe_tree`, `subscribe_tree_commits`, and retained/history diagnostic helpers also take `SharedTree(s, r)` directly. Preserve their target-specific callbacks/subjects, result types, and inverse acquisition windows. `TreeRevertible` and its operations remain unchanged. Diagnostics may expose protocol evidence; they do not provide an untyped edit handle.

Forks retain the same definition and receive their own checkout origin. Capture nodes in the fork; do not copy handles across checkouts. Transactions pass a `SharedTree(s, r)` with the same definition into the existing candidate-state callback. Preserve `Aborted(callback_error)` and `TransactionFailed`. Keep `NodeInDocument` constraints' current meaning; this slice does not invent a typed constraint family.

### 3.4 Application example

```gleam
pub type Item
pub type ItemState {
  ItemState(id: String, text: String, completed: Bool)
}

pub fn text() -> typed.Field(Item, String, typed.Required) {
  typed.required("text", typed.string())
}

pub fn completed() -> typed.Field(Item, Bool, typed.Required) {
  typed.required("completed", typed.boolean())
}

fn rename(
  item: watershed.TreeNode(Item, ItemState),
  value: String,
) -> Result(Nil, typed.Error) {
  watershed.tree_set(item, text(), value)
}
```

Here `ItemState` illustrates the checklist's existing `checklist.Item` record; the migration reuses that record rather than adding a duplicate. Define the schema tag in the declaration module separately from the application's record. A live node follows identity; the returned record is a snapshot.

## 4. File ownership and task dependencies

| Task | Files and responsibility | Prerequisites |
| --- | --- | --- |
| 1 | New `src/watershed/tree/typed.gleam`; new `test/watershed/shared_tree_typed_schema_test.gleam` and `test/watershed/tree/typed_fixture.gleam`: pure descriptors, codecs, builders, and reusable test declarations. | Approval gate |
| 2 | `src/watershed/tree/forest.gleam`, `src/watershed/tree_kernel.gleam`; new `src/watershed/tree/node.gleam` and `test/watershed/shared_tree_node_test.gleam`; existing array identity tests: reference resolution only. | Approval gate |
| 3 | `src/watershed/runtime_core.gleam`, `src/watershed/runtime.gleam`, `src/watershed/runtime_beam.gleam`; new `test/watershed/shared_tree_node_runtime_test.gleam`: atomic selected-view access and runtime routing. | 2 |
| 4 | `src/watershed.gleam`, `src/watershed_beam.gleam`; new typed facade tests; existing facade tests/probes/clients, compile-fail fixtures, and `justfile`: replace the public tree API and migrate those callers. | 1, 3 |
| 5 | `watershed_lustre/src/watershed_lustre/tree.gleam`, `watershed_lustre/test/watershed_lustre/tree_test.gleam`: migrate existing effects to typed SharedTree and generalize the thunk helper. | 4 |
| 6 | Checklist declaration module, `checklist.gleam`, app, tests, and browser smoke under `examples/shared_tree_checklist_lustre/`; `tools/website-runtime/src/website_runtime.gleam`: consumer migration and proof without a redesign. | 5 |
| 7 | Root and binding/example READMEs, parent roadmap, targeted docs gate, and this plan: documented support and combined acceptance. | 1-6 |

Tasks 1 and 2 may proceed independently after approval. Task 3 owns the runtime files exclusively; Task 4 owns both facades and the test/probe/client migration. Tasks 4-6 form one breaking migration: finish them before the full repository acceptance gate, without publishing an intermediate raw/typed compatibility facade. Do not overlap other lifecycle or core changes with these integration tasks. A new directory or package is not needed.

## Task 1: Pure typed declarations, codecs, and builders

**Files:** Create `src/watershed/tree/typed.gleam`, `test/watershed/shared_tree_typed_schema_test.gleam`, and `test/watershed/tree/typed_fixture.gleam`.

**Consumes:** Existing `tree_schema` and `tree/types`; no runtime or FFI.

**Produces:** Section 3.1, with a shared `Codec(a)` implementation and checked declaration metadata. The fixture supplies checklist/item tags, their codecs/builders, and their view schema for later target-specific tests.

- [x] Write leaf round-trip and wrong-type tests. Include this real failure rather than asserting only a constructor's existence:

  ```gleam
  pub fn shared_tree_typed_string_decode_rejects_number_test() {
    typed.decode(typed.string(), types.NumberValue(1.0))
    |> expect.to_equal(Error(typed.DecodeFailed("expected a string leaf")))
  }
  ```

  Also cover present null versus absent optional fields, finite number boundaries, supported handle references, malformed declaration identifiers, and mismatched root/schema identifiers. Test node decoding against wrong node identifiers and unordered object fields.

- [x] Run both targets and observe the missing typed module/functions:

  ```sh
  gleam test --target erlang -- --test-name-filter=shared_tree_typed_
  gleam test --target javascript -- --test-name-filter=shared_tree_typed_
  ```

- [x] Implement the opaque codecs and descriptors. Use direct `TreeValue` matching, not JSON stringify/parse adapters. The string codec's core is:

  ```gleam
  case value {
    types.StringValue(text) -> Ok(text)
    _ -> Error(DecodeFailed("expected a string leaf"))
  }
  ```

  Store the canonical leaf identifier with each codec. Expose the opaque accessors listed in section 3.1. `schema` checks the declared root against `view_to_stored(view)`; field/collection access checks the corresponding owner/member definition. A declaration cannot silently widen the runtime view.

- [x] Define fixture records and construction inputs separately. Use the current checklist's three item fields for the ordinary-string-ID case. Add an identifier-bearing case whose builder omits the generated identifier while its decoder requires the resulting string. Leave assignment to the existing native construction/allocator path; do not reject permitted missing construction identifiers with a read-state validator.

- [x] Run the two commands above to green, then format only the new Gleam files and commit the three explicit paths:

  ```sh
  gleam format src/watershed/tree/typed.gleam test/watershed/shared_tree_typed_schema_test.gleam test/watershed/tree/typed_fixture.gleam
  git add src/watershed/tree/typed.gleam test/watershed/shared_tree_typed_schema_test.gleam test/watershed/tree/typed_fixture.gleam
  git commit -m "feat(tree): add typed declarations and value adapters"
  ```

## Task 2: Resolve live node identity without cached paths

**Files:** Modify `src/watershed/tree/forest.gleam`, `src/watershed/tree_kernel.gleam`, and `test/watershed/shared_tree_array_forest_test.gleam`; create `src/watershed/tree/node.gleam` and `test/watershed/shared_tree_node_test.gleam`.

**Consumes:** Existing `forest.NodeRef`, forest storage, and kernel state.

**Produces:**

```gleam
// In forest:
pub fn attached_path(state: Forest, reference: NodeRef)
  -> Result(types.FieldPath, types.TreeError)
pub fn array_references(state: Forest, reference: NodeRef)
  -> Result(List(NodeRef), types.TreeError)

// In tree_kernel:
pub fn reference_path(state: TreeState, reference: forest.NodeRef)
  -> Result(types.FieldPath, types.TreeError)
pub fn array_references(state: TreeState, reference: forest.NodeRef)
  -> Result(List(forest.NodeRef), types.TreeError)
```

Also produce `node.Edit` and `node.resolve` from section 3.2.

- [x] Extend the existing `shared_tree_array_forest_moves_counted_duplicate_objects_by_identity_test`. Its `moved`, `first_reference`, and `second_reference` are already genuine moved identities for equal-valued objects. Add:

  ```gleam
  forest.attached_path(moved, first_reference)
  |> expect.to_equal(Ok(["right", "0"]))
  forest.attached_path(moved, second_reference)
  |> expect.to_equal(Ok(["right", "1"]))
  ```

  Add distinct tests for same-array reorder, parent move, map keys including numeric strings/Unicode/empty keys, detached and destroyed nodes, replacement at the old path, foreign view IDs, and array child/sibling membership.

- [x] Run the exact existing regression on both targets; it must fail because the accessor is missing:

  ```sh
  gleam test --target erlang -- --test-name-filter=shared_tree_array_forest_moves_counted_duplicate_objects_by_identity_test
  gleam test --target javascript -- --test-name-filter=shared_tree_array_forest_moves_counted_duplicate_objects_by_identity_test
  ```

- [x] Implement attached-path lookup within the forest's private node representation. Validate the reference using `reference_id`, traverse only attached roots, produce object/map keys unchanged and array indices with `int.to_string`, and return `InvalidEdit` rather than looking in a replacement node. Do not materialize values and compare them to identify the target.

  Mark the known lookup ceiling once at the helper:

  ```gleam
  // ponytail: O(n) attached-path lookup. Add a parent index if profiling shows a bottleneck.
  ```

  `node.resolve` converts the current source path into the existing edit type. For example:

  ```gleam
  use path <- result.try(tree_kernel.reference_path(state, source))
  case edit {
    SetField(key, value) -> Ok(types.SetField(list.append(path, [key]), value))
    ClearField(key) -> Ok(types.ClearField(list.append(path, [key])))
    MapSet(key, value) -> Ok(types.MapSet(path, key, value))
    MapDelete(key) -> Ok(types.MapDelete(path, key))
    ArrayInsert(index, values) -> Ok(types.ArrayInsert(path, index, values))
    ArrayRemove(start, end) -> Ok(types.ArrayRemove(path, start, end))
    ArrayMove(start, end, destination, gap) -> {
      use target <- result.try(tree_kernel.reference_path(state, destination))
      Ok(types.ArrayMove(path, start, end, target, gap))
    }
    RemoveNode(child) -> resolve_remove(state, source, child)
    MoveNode(child, destination, before) ->
      resolve_move(state, source, child, destination, before)
  }
  ```

  Define the private helpers in this task:

  ```gleam
  fn resolve_remove(
    state: tree_kernel.TreeState, source: forest.NodeRef, child: forest.NodeRef,
  ) -> Result(types.Edit, types.TreeError)
  fn resolve_move(
    state: tree_kernel.TreeState, source: forest.NodeRef, child: forest.NodeRef,
    destination: forest.NodeRef, before: Option(forest.NodeRef),
  ) -> Result(types.Edit, types.TreeError)
  ```

  They derive the current child index from direct array references, verify membership, and emit one existing `ArrayRemove`/`ArrayMove`. Resolve the destination gap before removal, as the existing native move API requires. Preserve native self/no-op behavior.

- [x] Run the identity regression and all `shared_tree_node_` tests on both targets. Include removal/undo reattachment using the existing retained identity tests; never create a value-equality fallback for an invalid reference.

- [x] Format the five owned paths and commit them as `feat(tree): resolve attached node references`.

## Task 3: Atomic reference-bound runtime access on both targets

**Files:** Modify `src/watershed/runtime_core.gleam`, `src/watershed/runtime.gleam`, `src/watershed/runtime_beam.gleam`; create `test/watershed/shared_tree_node_runtime_test.gleam`.

**Consumes:** Task 2's reference lookup and `node.Edit`. Uses the current `checked_selected_tree_state` and `submit_tree_edits_view_on`.

**Produces:** Core helpers with a common `(core, address, selector, view)` prefix:

```gleam
pub fn tree_node_reference_view_on(
  core: Core, address: String, selector: tree_types.CheckoutSelector,
  view: tree_schema.ViewSchema, path: tree_types.FieldPath,
) -> Result(Option(forest.NodeRef), CoreError)
pub fn tree_node_read_view_on(
  core: Core, address: String, selector: tree_types.CheckoutSelector,
  view: tree_schema.ViewSchema, reference: forest.NodeRef,
  relative_path: tree_types.FieldPath,
) -> Result(Option(tree_types.TreeValue), CoreError)
pub fn tree_node_child_view_on(
  core: Core, address: String, selector: tree_types.CheckoutSelector,
  view: tree_schema.ViewSchema, reference: forest.NodeRef,
  relative_path: tree_types.FieldPath,
) -> Result(Option(forest.NodeRef), CoreError)
pub fn tree_node_array_references_view_on(
  core: Core, address: String, selector: tree_types.CheckoutSelector,
  view: tree_schema.ViewSchema, reference: forest.NodeRef,
) -> Result(List(forest.NodeRef), CoreError)
pub fn tree_node_map_entries_view_on(
  core: Core, address: String, selector: tree_types.CheckoutSelector,
  view: tree_schema.ViewSchema, reference: forest.NodeRef,
) -> Result(List(#(String, tree_types.TreeValue)), CoreError)
pub fn submit_tree_node_edit_view_on(
  core: Core, address: String, selector: tree_types.CheckoutSelector,
  view: tree_schema.ViewSchema, reference: forest.NodeRef, edit: node.Edit,
) -> Result(#(Core, List(ScopedTreeEvent), List(wire.OutboundOperation)), CoreError)
```

Platform adapters mirror the five core read helpers with `runtime` replacing `core` and `String` errors, retaining the exact function names and remaining parameter/result types. JS takes `Runtime`; BEAM takes `Subject(Msg)`. The mutation adapters are:

```gleam
// In runtime.gleam, with the existing javascript target annotation:
pub fn tree_node_edit_view_on(
  runtime: Runtime, address: String, selector: tree_types.CheckoutSelector,
  view: tree_schema.ViewSchema, reference: forest.NodeRef, edit: node.Edit,
) -> Result(Nil, String)

// In runtime_beam.gleam:
pub fn tree_node_edit_view_on(
  runtime: Subject(Msg), address: String, selector: tree_types.CheckoutSelector,
  view: tree_schema.ViewSchema, reference: forest.NodeRef, edit: node.Edit,
) -> Result(Nil, String)
```

- [x] Write a runtime regression that captures an item, receives a peer reorder, and edits the captured item. Compare both the item identity and sequenced output, not only the final JSON. Add a rejection test that captures an item, replaces/removes it, and attempts the edit; assert unchanged snapshots, pending history, compressor serialization, event list, and transport submissions.

- [x] Run `shared_tree_node_` tests on both targets and establish the missing-helper failure:

  ```sh
  gleam test --target erlang -- --test-name-filter=shared_tree_node_
  gleam test --target javascript -- --test-name-filter=shared_tree_node_
  ```

- [x] Implement core access against the current selected state, including an active transaction's candidate. The mutation boundary is:

  ```gleam
  use state <- result.try(checked_selected_tree_state(core, address, selector, view))
  use operation <- result.try(
    node.resolve(state, reference, edit)
    |> result.map_error(fn(error) { TreeOperationFailed(address, error) }),
  )
  submit_tree_edits_view_on(core, address, selector, view, [operation])
  ```

  Both steps use the same `core`; do not allocate or publish during resolution. For reads, append a validated relative path to `reference_path` and use the existing kernel read. Capture absent optional children as `None`, but do not turn a detached/invalid reference into absence.

- [x] Wire the JS cell read/mutation helpers and BEAM messages. Follow `TreeReadView`, `TreeEditView`, `read_transaction_tree`, `transaction_tree_access`, and `queue_or_send`. Include initialization, reconnecting, closed, owner-access, and call-failure cases in the BEAM exhaustive matches. Resolve and edit in one actor request; never expose a read-path-then-write sequence.

- [x] Run both filtered suites plus `just shared-tree-test`. Verify local branches, transaction abort, nested commit, incompatible remote schema, readiness, close, and detached attachment promotion. Commit the four owned paths as `feat(tree): add atomic node-bound runtime operations`.

## Task 4: Make SharedTree typed on JavaScript and BEAM

**Files:** Modify `src/watershed.gleam`, `src/watershed_beam.gleam`, `justfile`; create `test/watershed/shared_tree_typed_facade_test.gleam` and the four compile-fail fixture packages below. Migrate the existing callers in:

- `test/watershed/shared_tree_array_facade_test.gleam`
- `test/watershed/shared_tree_map_facade_test.gleam`
- `test/watershed/shared_tree_creation_api_test.gleam`
- `test/watershed/shared_tree_creation_probe.gleam`
- `test/watershed/shared_tree_runtime_js_test.gleam`
- `test/watershed/shared_tree_runtime_beam_test.gleam`
- `test/watershed/sluice/driver_js_test.gleam`
- `test/watershed/tree/client_js.gleam`
- `test/watershed/tree/client_beam.gleam`

Reuse Task 1's test declarations and add supported-profile declarations alongside the existing `test/watershed/tree/` client helpers as needed. Search all Gleam callers at execution time for any additional facade use; include it in this migration rather than retaining an old overload. Lustre callers belong to Task 5; checklist and website-runtime callers belong to Task 6 because the website runtime depends on both packages.

**Consumes:** Task 1's typed descriptors and Task 3's runtime adapters.

**Produces:** The single `SharedTree(s, r)` surface in section 3.3, with matching names, generic parameters, and error behavior on both targets. The listed test/probe/client callers compile against it; protocol and kernel tests retain their low-level coverage.

- [x] Write one shared behavior assertion with JS/BEAM setup following `shared_tree_array_facade_test.gleam`. Cover typed required/optional reads, null, field writes, structural children, collection reads/writes, identifier reads, and handle leaves. Make this the primary wrong-value test:

  ```gleam
  // The following call belongs in a compile-fail fixture, not a runtime test.
  watershed.tree_set(item, text(), 42)
  ```

  Runtime tests must additionally reject a field declaration that uses the right phantom tag but the wrong runtime owner/type/cardinality. A phantom tag alone is not runtime validation.

- [x] Run `shared_tree_typed_` tests on both targets and observe missing facade interfaces. Create fixtures:

  - `tools/compile-fail/typed_tree_wrong_schema/{gleam.toml,src/typed_tree_wrong_schema.gleam}`: `Field(Other, String, Required)` against `TreeNode(Item, ItemState)`.
  - `tools/compile-fail/typed_tree_wrong_value/{gleam.toml,src/typed_tree_wrong_value.gleam}`: `42` against a string field.
  - `tools/compile-fail/typed_tree_required_clear/{gleam.toml,src/typed_tree_required_clear.gleam}`: a required field passed to `tree_clear`.
  - `tools/compile-fail/shared_tree_raw_edit/{gleam.toml,src/shared_tree_raw_edit.gleam}`: the old `tree_set(tree, ["text"], types.StringValue("value"))` call with `tree: SharedTree(Item, ItemState)`. Require a `SharedTree`/`TreeNode` or descriptor/value type mismatch, proving the old application edit signature no longer exists.

  Each source is a small annotated function whose body contains only the relevant misuse. Mirror the existing fixture manifests with `watershed = { path = "../../.." }`. Extend `_test-compile-fail` to require the expected type mismatch (`Other`/`Field`, `Int`/`String`, `Required`/`Optional`, or the old raw edit's argument types) and reject syntax/import failures as false positives. Build each fixture on both targets.

  Use separate `@target(javascript)` and `@target(erlang)` imports and misuse functions: JS calls `watershed`, BEAM calls `watershed_beam`. An Erlang build failing because a JS-only facade function is unavailable is not the intended type-safety result.

- [x] Change the existing opaque `SharedTree` to carry its generic definition alongside runtime/address/selector origin. Implement typed create/open/resolve and channel-field helpers at that boundary, without an intermediate public untyped handle or automatic upgrade. Implement `TreeNode`, `TreeArray`, and `TreeMap` with origin metadata and descriptors. Check field owner, cardinality, and allowed identifiers before each typed field operation. Encode/build before submitting; preserve access errors as `AccessFailed` and decoding errors as `DecodeFailed`.

  The typed setter's final steps are:

  ```gleam
  use value <- result.try(typed.encode_field(field, value))
  runtime.tree_node_edit_view_on(
    node.runtime, node.address, node.selector, node.view,
    node.reference, tree_node.SetField(typed.field_key(field), value),
  )
  |> result.map_error(typed.AccessFailed)
  ```

  Validate descriptors before these steps. `typed.encode_field` consumes Task 1's field codec; `tree_node` aliases `watershed/tree/node`.

  For collection writes, verify the builder's runtime identifier agrees with the collection item codec, build all inputs before submission, and let existing native construction rules assign identifiers. For movement, verify source/item/destination/sibling have the same runtime, address, selector, and bound view before forwarding references.

- [x] Replace path-based facade reads/edits, rather than adding `tree_typed_*` companions. Migrate the listed consumers to schema definitions, typed root/node capture, field descriptors, and typed builders. Preserve the existing oracle client operation inputs and observations by adapting them to declared typed nodes/collections inside the test clients; do not weaken the interop corpus or add a public raw adapter. Tests of malformed raw schemas/values continue through the existing lower-level runtime/kernel interfaces.

- [x] Add parity cases for two equal-valued siblings, moved parents, collection replacement, foreign documents/channels/checkouts, stale schema, closed documents, and reacquisition after reload. Keep `TreeNode` identity local; do not serialize it into `TreeValue.HandleValue`. Verify actual node identifiers before field access, optional child/collection deletion, root array/map/leaf access, typed root replacement/clear, read-only identifiers, canonical map key order, and complete errors for malformed remote data. A collection decoder must report an incompatible element, not filter it out. Creation must reject a mismatched root builder before allocation or a service request.

- [x] Make the existing lifecycle operations accept the generic `SharedTree` directly. Preserve the definition through fork and transaction callbacks; keep `Aborted(callback_error)` and `TransactionFailed` separate. Test subscriptions, schema inspection/explicit upgrade, handle-field round trips, and branch history without converting to another tree type. `open_tree` must permit compatibility inspection while incompatible reads/edits still fail.

- [x] Run both typed suites, the migrated map/array/creation facade suites on both targets, and `just _test-compile-fail`. Verify no facade declaration exports `TypedTree`, `tree_typed_*`, or a replacement raw access family. Commit the explicit facade/consumer/test/fixture/harness paths as `feat(tree)!: make SharedTree the typed application API`.

## Task 5: Lustre effects without a new lifecycle layer

**Files:** Modify `watershed_lustre/src/watershed_lustre/tree.gleam` and `watershed_lustre/test/watershed_lustre/tree_test.gleam`.

**Consumes:** Task 4's typed JS `SharedTree` facade. Reuses current subscriptions, commit capture, and `queue_microtask`.

**Produces:**

```gleam
pub fn perform(
  operation: fn() -> Result(value, error),
  completed: fn(Result(value, error)) -> msg,
) -> Effect(msg)
pub fn create(
  config: container.CreateConfig,
  definition: typed.Schema(s, r),
  builder: typed.Builder(s, input),
  initial_root: Option(input),
  created: fn(Result(String, typed.Error)) -> msg,
) -> Effect(msg)
pub fn create_dev(
  base_url: String,
  tenant: String,
  secret: String,
  definition: typed.Schema(s, r),
  builder: typed.Builder(s, input),
  initial_root: Option(input),
  created: fn(Result(String, typed.Error)) -> msg,
) -> Effect(msg)
pub fn open(
  document: watershed.Document(root),
  definition: typed.Schema(s, r),
  opened: fn(Result(watershed.SharedTree(s, r), typed.Error)) -> msg,
) -> Effect(msg)
pub fn read_root(
  tree: watershed.SharedTree(s, r),
  read: fn(Result(Option(r), typed.Error)) -> msg,
) -> Effect(msg)
pub fn transaction(
  tree: watershed.SharedTree(s, r),
  constraints: List(watershed.TreeTransactionConstraint),
  callback: fn(watershed.SharedTree(s, r)) -> Result(value, callback_error),
  completed: fn(Result(value, watershed.TreeTransactionError(callback_error))) -> msg,
) -> Effect(msg)
```

Replace the existing creation/open/read/transaction signatures; do not add typed/untyped variants. `subscribe` and `subscribe_commits` accept `SharedTree(s, r)` directly with their existing callbacks. Generalize the existing `perform` result type; its old `Result(Nil, String)` callers remain valid. Do not add one effect wrapper per typed collection operation when a thunk already expresses it.

- [x] Extend existing promise-based effect tests. For each migrated effect, assert construction performs no access/mutation and no callback construction; performing the effect uses current state; delivered messages are deferred and emitted once.

  Extend the existing test `Msg` with `TypedPerformed(Result(String, typed.Error))`, import `watershed/tree/typed`, and add:

  ```gleam
  pub fn typed_perform_is_lazy_and_dispatches_once_test() -> Promise(Nil) {
    let calls = transport_js.new_cell(0)
    let sink = transport_js.new_cell([])
    let pending = tree.perform(fn() {
      transport_js.set_cell(calls, transport_js.get_cell(calls) + 1)
      Ok("read")
    }, TypedPerformed)
    let assert 0 = transport_js.get_cell(calls)
    run(pending, sink)
    let assert 1 = transport_js.get_cell(calls)
    let assert [] = messages(sink)
    use _ <- promise.await(promise.wait(0))
    let assert [TypedPerformed(Ok("read"))] = messages(sink)
    let assert 1 = transport_js.get_cell(calls)
    promise.resolve(Nil)
  }
  ```

- [x] Run `cd watershed_lustre && gleam test`; the new generic signatures/result types must initially fail, not a transport or dependency setup.

- [x] Implement thunk execution inside `effect.from`, followed by `queue_microtask` dispatch. Migrate `open` through the existing channel-handle resolution flow with the definition, and migrate creation through the typed constructor. `read_root` calls `watershed.tree_read_root` for one current decoded snapshot; absent roots remain `None`. Route field writes through `perform(fn() { watershed.tree_set(item, field, value) }, completed)` and use the same thunk boundary for collection operations. Transactions and subscriptions use typed SharedTree directly.

- [x] Prove commit factories are still acquired during the synchronous source event, before dispatch is deferred. Reuse existing `subscribe_commits`; only the delivered application message is delayed. Keep undo/redo/history ownership in the application.

- [x] Migrate the existing binding tests to typed definitions/builders, preserving subscription/history coverage. Run all Lustre package tests, then commit the two files as `feat(lustre)!: use the typed SharedTree API`.

## Task 6: Migrate the checklist and prove identity-based actions

**Files:** Create `examples/shared_tree_checklist_lustre/src/shared_tree_checklist_lustre/typed_schema.gleam`; modify the existing `checklist.gleam`, main app, `test/shared_tree_checklist_lustre_test.gleam`, `test/history_runtime_test.gleam`, and `smoke/browser.mjs`. Also modify `tools/website-runtime/src/website_runtime.gleam`, whose package depends on the migrated bindings and checklist. Keep `schema.gleam`'s stored schema/initial-document layout unchanged.

**Consumes:** Typed descriptors/facades and Task 5's effects.

**Produces:** The same checklist UX and service profile using typed application access. The declaration module exports `Checklist`/`Item` phantom tags, the root definition/decoder/builder, item decoder/builder, `title`, `text`, `completed`, and `items` descriptors. Reuse `checklist.Checklist` and `checklist.Item` for decoded records.

- [x] Add an app-level race regression: capture the action target, reorder it remotely, then rename/toggle/delete/move that captured item. Assert both its physical identity and its displayed record. Add removal/replacement races that visibly refuse instead of targeting the item now occupying its index.

  The action under test should become:

  ```gleam
  tree.perform(
    fn() { watershed.tree_set(item, typed_schema.text(), text) },
    renamed,
  )
  ```

  `item` is a captured `TreeNode(typed_schema.Item, checklist.Item)`; `renamed` is the existing action-completion message adapted to `typed.Error`. Do not rebuild `["items", saved_index, "text"]` inside it.

- [x] Run `cd examples/shared_tree_checklist_lustre && gleam test`; establish the new action regression before migration.

- [x] Add the hand-authored declaration module. Reuse the current domain records, trimming/empty-text checks, and duplicate application-ID validation. Distinguish its plain `"id"` string from native `Identifier` fields. Move source-backed shape decoding into the reusable typed adapters without relaxing these domain checks.

  Keep live node handles for action targets separately from decoded record snapshots. Reconcile displayed records/handles from current typed reads after events. Application IDs remain render/domain keys, not an authority to retarget a stale node.

- [x] Migrate model/message tree annotations to `SharedTree(typed_schema.Checklist, checklist.Checklist)`. Migrate creation/open/read and individual actions through the existing effect names and typed definitions/builders. Keep grouped completion in one existing transaction; keep application-owned undo/redo, redo invalidation, disposal errors, clear/close draining, reconnect, and reload. New sessions reacquire handles. Update `test/history_runtime_test.gleam` to use the same typed surface. Do not change CSS, copy, navigation, or bootstrap layouts.

- [x] Migrate the website runtime's SharedTree state and actions to the same typed definitions and identity-bound operations. Preserve its exported JSON/browser contract and error reporting. Compile it after the checklist and bindings, using `cd tools/website-runtime && gleam build`; this package's dependencies make it a Task 6 integration check, not a Task 4 prerequisite.

- [x] Extend the actual two-context browser test with the captured-target reorder and removed-target refusal. Preserve all existing creation, CRUD, grouped transaction, history, close, and reload assertions. Run:

  ```sh
  cd examples/shared_tree_checklist_lustre && gleam test && corepack pnpm run build
  ```

  Then run `just shared-tree-checklist` from the repository root against an owned pinned loopback Floodgate. Require real Chrome/Chromium execution and a PASS marker; the recipe's absent-browser skip is not acceptance. Use the existing development-only `FLOODGATE_ALLOWED_ORIGINS=*` setting for its random-port app origin, never as a production authentication change. Stop only the server owned by this run.

  Commit only the declared example and website-runtime paths, including the migrated history-runtime tests, as `refactor(example): use the typed SharedTree API`.

## Task 7: Documentation and combined acceptance

**Files:** Modify `README.md`, `watershed_lustre/README.md`, `examples/shared_tree_checklist_lustre/README.md`, `docs/superpowers/specs/2026-09-21-shared-tree-design.md`, `tools/shared-tree-oracle/gates.test.mjs`, and this plan.

**Consumes:** All earlier tasks. No new feature or source pin is introduced here.

**Produces:** Accurate public examples, regression checks, and evidence for this typed application slice. Broader M7 remains partial.

- [x] Replace active raw facade examples with declaration, typed creation/resolution, root capture, required/optional read, typed update, and direct subscription/history on `SharedTree(s, r)`. Document the breaking migration from path/`TreeValue` calls; do not document an opt-in TypedTree wrapper or raw escape. Add compile checks to the existing docs gate, following its `README local branch examples compile against the public Gleam API` test. Update its existing branch examples to preserve schema/record types. Its failure before the example/API lands must be a missing-contract failure, not an unrelated old test.

- [x] Document snapshot versus live-node versus Fluid-handle identity; runtime validation despite static tags; builder input versus decoded record; identifier ownership; required/optional/null behavior; current-index operations versus captured-node operations; errors after removal/schema change/close; and handle reacquisition after reload.

  Explain that there is no new per-field event promise. Show `tree.perform` with a thunk and existing subscription/revertible disposal, using the same typed SharedTree handle. Update the roadmap's accepted typed slice without removing the other open M7 items. Update active README and binding documentation across the repository; retain historical plans/specs as records of their accepted stages, and explain the public API change in the parent roadmap.

- [x] Run the covering acceptance serially on frozen source. Do not parallelize compiles/fixture production/service proofs sharing output directories:

  ```sh
  just shared-tree-oracle-check
  just shared-tree-test
  npm --prefix tools/shared-tree-oracle run source:capture
  npm --prefix tools/shared-tree-oracle test
  just shared-tree-lifecycle-interop
  just shared-tree-create-interop
  just shared-tree-interop
  just build
  just test
  just lint
  just shared-tree-checklist
  ```

  The final browser command needs the owned pinned service described in Task 6. Full Node uses the package script's unrestricted `--test-concurrency=1`; genuine source capture precedes it. Required service/browser dependencies must execute, not skip.

- [x] Verify the actual evidence: the existing 68-case profile/pins are unchanged; both native targets pass; lifecycle has all seven sections, 27 unique writer/reader reload cells and 300 unique actual handle schedules; creation has 18 unique cells; legacy executes 300 distinct schedules; required cases report no skips/divergences. Intentional legacy refusal scenarios are not a failed-gate count. Record fresh test counts rather than asserting the old totals after adding tests.

  Also require the new typed facade parity tests, all eight target/fixture compile-fail checks, construction-identifier proof, migrated constructor/handle-field/branch/subscription callers, website-runtime build, real browser target-identity race/refusal assertions, and complete application history/close/reload behavior. Add a public-surface regression check in the docs gate that rejects `TypedTree` exports, `tree_typed_*` functions, and raw facade read/edit signatures. Existing low-level raw-profile proof alone is not evidence that the single typed surface was exercised.

- [x] Perform a bounded final review against sections 1-3 and the table below. Inspect all changed runtime/facade paths, verify examples actually compile, and resolve material findings before marking checkboxes complete. Commit documentation only after source acceptance; use `docs(tree): document typed application API`. Record code range, gate commands, report paths/run IDs, outcomes, and any explicit scope changes here. Do not claim hosted CI or a published release.

### Task 7 execution record

Task 7 completed against source frozen at `39040d6e`; the accepted
implementation range is `87ce132e..39040d6e`. Documentation and gate changes
introduced no runtime algorithm, dependency, pin, fixture-byte, website design,
or public API change.

Fresh passing evidence:

- `just shared-tree-oracle-check`: 68 pinned source cases.
- `just shared-tree-test`: 1,220 BEAM tests and 1,193 JavaScript tests, plus
  storage, bootstrap, and creation smokes.
- `npm --prefix tools/shared-tree-oracle run source:capture`: genuine pinned
  Fluid 3.1.0 source capture at
  `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960`.
- `npm --prefix tools/shared-tree-oracle test`: 825 passed, zero failed or
  skipped, with the package's unrestricted serial test command.
- `just shared-tree-lifecycle-interop`: run
  `24897ab1-ef64-4818-affd-0029866c9a7a`, report
  `tools/shared-tree-oracle/.output/lifecycle/289f449e-3bd0-422d-a24e-3a778e031532/report.json`;
  seven sections, 27 expected/actual/unique reload cells, 300
  requested/actual/unique handle schedules, no skip.
- `just shared-tree-create-interop`: run
  `c5157609-85bd-479a-8277-21f00d0b4c01`, report
  `tools/shared-tree-oracle/.output/creation/c5157609-85bd-479a-8277-21f00d0b4c01/report.json`;
  18 actual/unique cells, no skip or divergence. Its native prerequisites
  passed 29 BEAM and 27 JavaScript tests.
- `just shared-tree-interop`: run
  `de4d8388-8fb9-4701-9718-fef8204f6c60`, report
  `tools/shared-tree-oracle/.output/interop/de4d8388-8fb9-4701-9718-fef8204f6c60/report.json`;
  300 requested/generated/executed distinct schedules, 1,176 JavaScript and
  1,203 BEAM corpus cases, 42 intentional refusals, zero skips and zero
  divergences.
- `just build`, `just test`, and `just lint` passed. `just test` included all
  eight typed target/fixture compile-fail checks. The primary native suites
  passed 2,780 BEAM and 3,031 JavaScript tests; the checklist passed 16 tests,
  `watershed_lustre` passed 106 tests, and the website runtime passed seven.
- The explicit website-runtime build/test and checklist Lustre test passed.
- `WATERSHED_CHROME=/usr/bin/google-chrome just shared-tree-checklist` ran
  against an owned attached Floodgate at
  `0eb493fc46d1bb9baf1151a6ccdde93544e057e7` and passed the two-context
  captured-identity, refusal, history, close, and reload assertions. The exact
  service process was stopped, port 4000 was closed, and its owned data was
  removed.

The Copilot session artifacts retain the complete logs at
`files/typed-shared-tree/artifacts/task-7-final-*` after workspace cleanup.
The profile remains Fluid 3.1.0 at
`c3c5bf0ecd313362e83fe8a02b7d39e7e0736960` with Floodgate
`0eb493fc46d1bb9baf1151a6ccdde93544e057e7`. Broader M7 remains partial. No
push, hosted workflow, release, dependency, pin, schema, runtime, fixture, or
generated-byte change was made during Task 7.

### Final review and closure

The whole-range review of `87ce132e..65bbf353` found one material issue:
BEAM root read, set, and optional clear operations used an unmonitored actor
call and could panic after close. Commit `90739e50` routes the two shared
root request boundaries through the existing monitored `call_runtime`.
Each operation still sends one request; root snapshots still read one
selected state. The scoped fix review found no remaining material issue.

The new BEAM regressions first reproduced all three `Noproc` panics after
waiting for the real actor to terminate. They now return typed access errors.
Fresh verification on `90739e50` passed the closed-root regressions on both
targets, all ten typed facade tests, 210 runtime tests, 24 node tests,
`just shared-tree-test` (1,223 BEAM and 1,194 JavaScript), `just build`,
`just test` (2,783 BEAM and 3,032 JavaScript core tests), and `just lint`.
These are post-review covering checks; the upstream service gate results
above describe the frozen `39040d6e` run, not a later rerun.

Two execution decisions preserve the approved contract:

- Leaf-root codecs support canonical leaf identifiers rather than rejecting
  leaf-root schemas. If that interpretation is wrong, the leaf declarations
  need a compatibility change.
- Internal checked builder metadata supports the heterogeneous identifier
  sets already permitted by the profile. A mixed insert remains one native
  commit, and public constructor signatures stay unchanged. If that choice
  is wrong, builder internals need rework.

Final review is complete. Broader M7 remains partial; no push, hosted workflow,
or release occurred.

## 5. Requirement-to-task coverage

| Requirement | Delivering tasks and evidence |
| --- | --- |
| Hand-authored, checked typed declarations; no generator | 1; pure codec/declaration tests |
| SharedTree is the only application tree API; no raw/typed split | 4-7; generic facade/lifecycle contracts, raw-edit compile-fail fixture, and public-surface docs gate |
| All repository callers migrate without changing wire/browser contracts | 4-7; facade/probe/client/binding/example builds and existing interop/browser gates |
| Static owner/value/cardinality safety | 4; three type-safety compile-fail fixtures on both targets |
| Runtime schema/declaration compatibility, including peer upgrades | 1, 3, 4; live facade rejection tests |
| Node identity through moves and replacement/removal | 2-4; equal-valued identity tests and atomic runtime tests |
| No stale read-path/write race on BEAM | 3; one-message mutation routing and actor tests |
| Object/child/map/array/handle access | 1, 4; both-target facade cases and current profile proofs |
| Construction inputs differ from read records; native IDs stay native | 1, 4; identifier-bearing insert/read test |
| Existing event, transaction, inverse, branch and disposal semantics | 3-6; covering native/binding/app suites and browser history |
| Effects are lazy and delivery is deferred | 5; promise tests and unchanged commit acquisition window |
| Real consumer and fresh-handle reload | 6; checklist tests and two-context browser |
| Current wire/service profile remains supported | 7; source/native/Node/lifecycle/creation/legacy gates |
| Honest M7 boundaries and reproducible evidence | 7; docs, final review, and recorded outcomes |

## 6. Execution handoff

Review the proposed contract before starting implementation. The plan can then be executed task-by-task with fresh scoped reviews, or inline with review checkpoints. Neither choice authorizes extra lifecycle slices, a generator, remote publication, or speculative API extensions.
