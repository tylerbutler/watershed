# Typed SharedTree API: authoring extensions and live references

**Date:** 2026-10-15
**Status:** Written design approved in conversation. Implementation remains a
separate task.
**Prerequisite:** [Typed schema authoring](2026-10-15-shared-tree-schema-authoring-design.md)
and its [implementation plan](../plans/2026-10-15-shared-tree-schema-authoring.md).
The prerequisite is planned, not implemented.

## 1. Deliverables and limits

This follow-on has two independently releasable milestones:

1. Extend typed authoring with heterogeneous unions, named recursion, and
   identifier fields with construction-time defaults.
2. Add typed live reads and edits through checkout-scoped node identities,
   including lifecycle handling, transactions, branches, and invalidation.

The second milestone depends on the first's descriptor/codec changes. It is
not a proxy layer that turns Gleam records into mutable Fluid objects.

Still excluded: anonymous/structural naming, generic field defaults, code
generation, schema migration/adaptation, persistent or shared branches,
portable node references, async transactions, reinserting existing nodes as
new content, and expansion of the accepted native interoperability profile.
The first plan's object0–object8 limit is unchanged.

## 2. Existing foundations

- `tree/schema.gleam` already supports allowed-type sets, recursive stored
  definitions, Identifier cardinality, strict view checks, and supported
  upgrades.
- `tree/identifier.gleam` already materializes missing identifiers through the
  document compressor for new values/edits.
- `tree/forest.gleam:34-40,1608-1637` defines view-scoped `NodeRef`, lookup,
  node reads, and attachment checks.
- `tree_kernel.gleam` exposes references and constraint resolution, and
  preserves allocation watermarks around transaction previews.
- `tree/branch.gleam` owns checkout identity and reference lookup.
- `runtime_core.gleam` owns checkout-aware read/edit submission and transaction
  dispatch. Runtime wrappers and facades exist separately for JS and BEAM.
- Public tree edits currently address paths. An index path is not a stable
  identity after insertion, removal, or move.

A forest `NodeRef` is a foundation, not proof of public reference stability.
Reconciliation, transaction preview promotion, undo, and branch operations must
be observed and tested before promising identity-bound behavior.

Fluid guidance:

- [Schema definition](https://fluidframework.com/docs/data-structures/tree/schema-definition)
- [Reading and editing](https://fluidframework.com/docs/data-structures/tree/reading-and-editing)
- [SchemaFactory](https://fluidframework.com/docs/api/tree/schemafactory-class)

Use the installed/source oracle at `@fluidframework/tree` `3.1.0`, commit
`c3c5bf0ecd313362e83fe8a02b7d39e7e0736960`, for executable contracts. Current
web documentation includes later/beta APIs and is not release evidence.

## 3. Unions

Add opaque `Variant(sum)` and these builder functions:

```gleam
variant(node: Node(a), inject: fn(a) -> sum, project: fn(sum) -> Option(a))
  -> Variant(sum)
union(variants: List(Variant(sum))) -> Node(sum)
```

A union does not create a new persisted node identifier. It supplies the
union of its branches' allowed identifiers wherever it is used.

Encoding requires exactly one projector to return `Some`. Zero or multiple
matches are explicit value errors, not a default variant or first-match rule.
Decode dispatches by the native leaf/container type identifier, decodes the
matching branch, then injects the result into the application sum type.

Compilation rejects empty unions and overlapping branch identifier sets.
Two branches cannot distinguish themselves using the contents of nodes with
the same persisted type ID. Nested unions flatten their allowed-type sets;
ordering does not change the persisted schema.

As with constructor/getter pairs, the compiler cannot prove laws about
arbitrary inject/project functions. Document those laws and test lawful pairs.
Do not use `Dynamic`, unsafe casts, or JSON round trips to erase branch types.

The first plan's private single-node-identifier representation must become an
allowed-type set plus a graph of definitions. Its private encoders must become
fallible. Existing public `Node(a)` and `encode` signatures remain unchanged.

## 4. Named recursion

Add:

```gleam
lazy(factory: Factory, name: String, resolve: fn() -> Node(a)) -> Node(a)
```

Example:

```gleam
pub type Outline {
  Outline(label: String, children: List(Outline))
}

pub fn outline() -> builder.Node(Outline) {
  let factory = builder.factory("com.example")
  let self = builder.lazy(factory, "Outline", outline)
  builder.object2(
    factory,
    "Outline",
    Outline,
    builder.required("label", builder.string(), fn(value) { value.label }),
    builder.required(
      "children",
      builder.array(factory, "Children", self),
      fn(value) { value.children },
    ),
  )
}
```

The thunk must return a concrete named object, array, or map with the exact
declared identifier. It cannot return an alias-only lazy reference or a union
with multiple identifiers. Recursive unions instead contain lazy branches
that resolve to concrete named containers.

Compile with explicit visiting/visited state keyed by identifier. Resolve each
distinct lazy occurrence once, check its claimed identifier and definition,
and compare conflicts even when the identifier was already seen. Traverse a
concrete definition's descendants only once. Recursion must terminate without
discarding checks on conflicting declarations.

Keep schema metadata traversal separate from typed codec functions. Thunks are
pure, deterministic declarations. Codec recursion follows finite input data,
not an eagerly expanded schema. Mutual recursion is supported. Required cycles
with no finite inhabitant are not a reason to silently rewrite cardinalities;
follow the existing schema validator for their acceptance.

## 5. Identifier construction

Add:

```gleam
pub type Identifier {
  Generate
  Assigned(String)
}

identifier(key: String, get: fn(record) -> Identifier)
  -> Property(record, Identifier)
encode_new(schema: Compiled(a), value: a)
  -> Result(Option(types.TreeValue), types.TreeError)
```

Identifier properties compile to native Identifier fields with the string leaf
as their only allowed type. They are object properties, not identifier roots,
array elements, or map entry cardinalities.

Strict `encode` requires `Assigned` and preserves its exact string. Strict
`decode` always returns `Assigned(actual_id)` and rejects a missing identifier.
`Generate` is not a possible result of a successful snapshot read.

`encode_new` omits a `Generate` property and validates with
`schema.validate_root_construction`. This mode propagates through nested
objects, arrays, maps, and union branches. It does not allocate IDs or change
the compressor. The existing runtime authoring/creation path materializes
identifiers when content is inserted.

No empty-string sentinel, application UUID generation, mutation of the caller's
record, or forced uniqueness check is allowed. User-assigned identifiers need
not be unique; the API must not confuse them with node identity. Decode after
insertion is how an application obtains generated values.

The snapshot type contains `Identifier`, so the type alone does not distinguish
new input from read output. This is deliberate and additive: adopting separate
input/output record types would require another constructor/property API.
Document the stronger runtime guarantee that successful reads contain only
`Assigned`.

## 6. Live API architecture

Add a pure `watershed/tree/live` module for typed codecs and navigation, with
opaque `View(a)`, `Ref(a)`, and `Subscription` types. It must not import either
runtime facade. Target-specific facades supply an internal backend through
callbacks that send structured requests to the shared core.

Expose matching entry points:

```gleam
// watershed on JS; watershed_beam on BEAM
tree_typed(tree: SharedTree, schema: builder.Compiled(a))
  -> Result(live.View(a), live_types.LiveError)
```

Place shared request, token, status, and error types in
`watershed/tree/live_types`, avoiding a dependency cycle between the core and
the typed live module. Do not parse existing error strings to infer lifecycle
states. Existing untyped public APIs remain unchanged.

Binding checks the supplied compiled schema against both the handle's view and
the checkout's current stored schema. Every subsequent operation rechecks the
current view before reading or authoring.

### Root snapshots and composite references

```gleam
read_root(View(a)) -> Result(a, LiveError)
replace_root(View(a), a) -> Result(Nil, LiveError)
replace_root_new(View(a), a) -> Result(Nil, LiveError)
required_root(View(a)) -> Result(Ref(a), LiveError)
optional_root(View(Option(a))) -> Result(Option(Ref(a)), LiveError)
read(Ref(a)) -> Result(a, LiveError)
status(Ref(a)) -> Result(ReferenceStatus, LiveError)
dispose(View(a)) -> Result(Nil, LiveError)
```

References are for composite nodes: objects, arrays, and maps. Leaf values
remain ordinary typed values, as in Fluid. Primitive roots use `read_root` and
root replacement, not composite references. Cardinality/kind mismatches return
explicit errors, including using `required_root` on an optional root.

`read` returns a snapshot. Mutating or reconstructing that Gleam value does not
edit the document. Explicit write operations submit native edits.

### Property and child access

```gleam
get(Ref(record), builder.Property(record, a)) -> Result(a, LiveError)
set(Ref(record), builder.Property(record, a), a) -> Result(Nil, LiveError)
set_new(Ref(record), builder.Property(record, a), a) -> Result(Nil, LiveError)
child(Ref(record), builder.Property(record, a)) -> Result(Ref(a), LiveError)
optional_child(Ref(record), builder.Property(record, Option(a)))
  -> Result(Option(Ref(a)), LiveError)
narrow(Ref(sum), builder.Node(a)) -> Result(Option(Ref(a)), LiveError)
```

Optional `set(..., None)` clears the property; required fields cannot be cleared.
`child` requires a present required composite property. `optional_child`
requires an optional composite property. `narrow` retains identity when the
current union node matches the requested branch.

Check that a property is actually declared by the reference's node descriptor,
including key, allowed types, and cardinality. A record type can be reused by
multiple schemas; matching a phantom record parameter alone is insufficient.
Properties representing Identifier fields are read-only through `set` and
`set_new`, matching Fluid's identifier field API. Replacing an object with new
content remains distinct from mutating its identifier.

Expose an internal builder bridge for property root codecs, field definitions,
and allowed types. Keep descriptor constructors opaque; do not let the live
layer invent an unchecked descriptor from a field name.

### Collections

```gleam
array_get(Ref(List(a)), Int) -> Result(Option(a), LiveError)
array_node(Ref(List(a)), Int) -> Result(Option(Ref(a)), LiveError)
array_insert(Ref(List(a)), Int, List(a)) -> Result(Nil, LiveError)
array_insert_new(Ref(List(a)), Int, List(a)) -> Result(Nil, LiveError)
array_remove(Ref(List(a)), Int, Int) -> Result(Nil, LiveError)
array_move(Ref(List(a)), Int, Int, Ref(List(a)), Int)
  -> Result(Nil, LiveError)
map_get(Ref(Dict(String, a)), String) -> Result(Option(a), LiveError)
map_node(Ref(Dict(String, a)), String) -> Result(Option(Ref(a)), LiveError)
map_set(Ref(Dict(String, a)), String, a) -> Result(Nil, LiveError)
map_set_new(Ref(Dict(String, a)), String, a) -> Result(Nil, LiveError)
map_delete(Ref(Dict(String, a)), String) -> Result(Nil, LiveError)
```

Indices, ranges, and move destinations follow existing native semantics,
including half-open removal ranges. Node lookups reject leaf-valued entries
with a kind error; absent entries return `None`.

Move validates both references inside one runtime request. They must refer to
the same runtime, document/tree, and checkout. Existing native schema/move
validation decides destination compatibility. An attached `Ref` is not new
input: no insertion or set API accepts it as a value.

## 7. Identity, runtime atomicity, and lifetime

The core owns an anchor registry scoped to each typed view. Each entry identifies
the runtime instance, tree origin, checkout, and logical node identity. Intern
repeated acquisitions of the same view/node. Do not key anchors by an array
index, a current path, a record value, or an Identifier field.

Reuse forest `NodeRef` where its stability is proven. Where replay/promotion
changes physical references, update anchors from explicit identity mappings
produced by those transitions. Never recover identity by searching for equal
values, matching user identifiers, or choosing the occupant of an old path.
Before release, every supported transition must either preserve the physical
reference or supply a tested old-to-new identity mapping.

Anchor resolution, schema/lifecycle checks, current path derivation, and edit
submission occur in one core operation. A read-resolve/write split across JS
callbacks or BEAM actor messages is forbidden. Initial identity-to-path lookup
may traverse the forest; a reverse index is not required for this milestone.
Do not introduce a stale path cache to optimize it.

Reference state is `Attached`, `Removed`, `Deleted`, or `Invalidated`.
`read` and edits require `Attached`. Removed retained nodes cannot be edited
through this API. Undo can reattach the same retained identity and make the
reference usable again. Destroyed/pruned nodes become terminal `Deleted`;
aborted preview-only nodes become terminal `Invalidated`. Replacing a node
with equal content creates a different identity and cannot revive a reference.

| Transition | Required result |
| --- | --- |
| Insert before / reorder / supported cross-parent move | Existing reference follows the same node. |
| Remove a node | Reference reports `Removed`; reads/edits fail. |
| Undo the removal while repair data survives | Same reference becomes `Attached`. |
| Root/property/map-entry replacement | Old node is removed; newly acquired node has a different identity. |
| Successful transaction preview promotion | References to surviving preview nodes map to committed identities. |
| Abort or failed transaction | Original anchors remain correct; preview-only anchors are invalidated. |
| Reconciliation / reconnect in the same runtime | Surviving node references remain correct. |
| Fork | New view/checkout; references are not transferable. |
| Rebase or merge | Preserve references to surviving nodes in each retained checkout; disposed source checkout rejects access. |
| Incompatible schema upgrade | Report incompatibility; do not silently change the typed descriptor. |
| Typed-view disposal | Cancel subscriptions and release anchor bookkeeping; leave document/branch open. |
| Runtime shutdown / fresh load | Old references fail; they are not portable. |

References do not pin detached repair data or collaboration history. Keep
tombstone bookkeeping only until typed-view disposal; never reuse its tokens.
Typed-view disposal is idempotent. Other lifecycle errors remain explicit.

Typed operations compose inside existing synchronous tree transactions. Fork,
merge, rebase, and undo use existing native APIs; do not add a parallel history
engine. Low-level operations must update the same anchor registry, not bypass
it merely because they were not initiated by a typed wrapper.

## 8. Errors and subscriptions

Define structured `LiveError` variants for invalid schema/value, incompatible
view, wrong property/cardinality/kind, invalid reference state, closed view,
disposed checkout, closed runtime, foreign origin, and a runtime failure
with its existing diagnostic detail. Keep schema/value errors as `TreeError`.

Add:

```gleam
observe(View(a), fn(Result(a, LiveError)) -> Nil)
  -> Result(Subscription, LiveError)
observe_node(Ref(a), fn(Result(a, LiveError)) -> Nil)
  -> Result(Subscription, LiveError)
unsubscribe(Subscription) -> Nil
```

Implement these as conservative invalidation plus fresh typed reads over the
existing checkout-scoped tree subscriptions. They are not promises of Fluid's
exact `nodeChanged` / `treeChanged` event granularity or counts. No initial
callback is implicit: callers explicitly read initial state.

Callbacks see committed runtime state and explicit read/incompatibility errors.
Delegate exception reporting and callback edit restrictions to the existing
native subscription contract. Disposal/unsubscribe prevents future callbacks,
including subscriptions delivered late. Do not cache snapshots as authority.

## 9. Acceptance and global constraints

Authoring evidence includes dual-target codec tests, positive/negative
compile-time examples, overlapping/empty union rejection, unresolved/conflicting
lazy definitions, mutual recursion, optional/null cases, and recursive
construction defaults. Pure encoding must allocate no document IDs.

Live evidence includes property type rejection, wrong-schema properties sharing
one record type, retained identity across all transitions above, foreign-runtime
and checkout rejection, transactional atomicity, no partial array insertion,
and both runtime wrappers. Pinned upstream captures must observe reference
identity and lifecycle, not just equal final snapshots.

Use the existing local service acceptance machinery for a two-client proof of
move/reconciliation/default-ID behavior, reconnect, and fresh reload. Fresh
loads recover data, not old live-reference tokens. Record stronger refusal
boundaries separately from upstream-equivalent behavior.

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
