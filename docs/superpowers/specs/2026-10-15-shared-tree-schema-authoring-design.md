# Typed SharedTree schema authoring

**Date:** 2026-10-15
**Status:** Written design approved in conversation. Implementation remains a
separate task.

**Follow-on:** [Authoring extensions and live references](2026-10-15-shared-tree-typed-api-follow-on-design.md)
defines the deferred capabilities without expanding this milestone.

## 1. Goal and scope

Replace hand-written schema-v2 JSON and parallel snapshot decoders with one
typed declaration. Use Fluid's `SchemaFactory` as a semantic guide, not as a
class API to reproduce in Gleam.

The first milestone supports:

- The five existing leaf kinds: string, number, boolean, null, and handle.
- Explicitly named arrays and string-keyed maps with one element/value type.
- Explicitly named objects with required and optional properties.
- Required and optional roots.
- Derived stored/view schemas and typed snapshot encoding/decoding.
- Pure Gleam implementations on JavaScript and BEAM.
- Migration of the item-counter example and its source-backed comparison.

The first milestone excludes heterogeneous unions, recursive declarations,
identifier fields and their automatic defaults, structural/anonymous naming,
custom codecs, code generation, schema migrations, and live typed node
references or edits. Existing low-level APIs retain their existing features.
Authoring support does not widen the native interoperability profile.

## 2. Existing code and upstream references

Read these sources before implementation:

| Source | Relevant contract |
| --- | --- |
| `src/watershed/tree/schema.gleam` | Validated `StoredSchema` / `ViewSchema`, persisted schema-v2 parsing, content validation, strict compatibility, upgrades. |
| `src/watershed/tree/types.gleam` | `TreeValue`, `TreeError`, and snapshot structure. |
| `src/watershed/schema.gleam:430-675` | Existing typed properties, record constructors, getters, and arity-specific builders for the separate typed-map layer. |
| `watershed_lustre/src/watershed_lustre/tree.gleam` | Creation/open/read effects already accept the low-level schema/value types. |
| `examples/shared_tree_item_counter_lustre/src/shared_tree_item_counter_lustre/schema.gleam` | The serialized array schema this work should replace. |
| `examples/shared_tree_item_counter_lustre/src/shared_tree_item_counter_lustre/counter.gleam` | The hand-written snapshot decoder this work should replace. |
| `tools/shared-tree-oracle/schema.mjs` | Existing upstream schema fixture helpers. |
| `test/fixtures/shared_tree/profile.json` | Accepted upstream package, protocol, and feature profile. |

Fluid documentation:

- [Schema definition](https://fluidframework.com/docs/data-structures/tree/schema-definition)
- [SchemaFactory API](https://fluidframework.com/docs/api/tree/schemafactory-class)

Those pages describe the current SDK, including APIs outside this milestone.
Implementation evidence must use the repository's pinned
`@fluidframework/tree` version `3.1.0` and commit
`c3c5bf0ecd313362e83fe8a02b7d39e7e0736960`, not assume that current beta/alpha
documentation describes that version.

## 3. Chosen approach

Add `src/watershed/tree/schema_builder.gleam`. Keep the existing
`watershed/tree/schema` module as the low-level persisted-schema boundary.
Do not reuse typed-map schema encoders: they encode independent map values,
not native tree nodes. Reuse their constructor/property pattern instead.

Alternative approaches considered:

1. JSON/schema builders alone remove string literals but leave application
   values and decoders disconnected from the declaration.
2. Typed descriptors derive both the schema and codecs. This is the chosen
   approach and needs no compiler plugin or production dependency.
3. Generated Gleam bindings can reduce declarations further, but introduce a
   generator, generated-file policy, and another build step.

Gleam cannot derive a record declaration from a runtime descriptor. Applications
still define their records, then supply a constructor and property getters.
The compiler checks the property value types against that constructor. A
descriptor is not a mutable view into a tree.

## 4. Public API

All types below are opaque. Functions are proposed public signatures, not
claims that they already exist.

```gleam
Factory
Node(a)
Property(record, a)
Root(a)
Compiled(a)

factory(scope: String) -> Factory
string() -> Node(String)
number() -> Node(Float)
boolean() -> Node(Bool)
null() -> Node(Nil)
handle() -> Node(handle.Reference)

array(factory: Factory, name: String, element: Node(a))
  -> Node(List(a))
map(factory: Factory, name: String, value: Node(a))
  -> Node(Dict(String, a))

required(key: String, node: Node(a), get: fn(record) -> a)
  -> Property(record, a)
optional(key: String, node: Node(a), get: fn(record) -> Option(a))
  -> Property(record, Option(a))

object0(factory: Factory, name: String) -> Node(Nil)
object1(factory: Factory, name: String, construct: fn(a) -> record,
        p1: Property(record, a)) -> Node(record)
object2(factory: Factory, name: String, construct: fn(a, b) -> record,
        p1: Property(record, a), p2: Property(record, b)) -> Node(record)
```

Continue the established arity-specific pattern through `object8`.
`object0` represents an empty object with the value `Nil`. Do not add a
heterogeneous property list, unsafe casts, or a separate fluent builder.
The eight-property limit is explicit; lifting it is a separate API decision.

```gleam
root(node: Node(a)) -> Root(a)
optional_root(node: Node(a)) -> Root(Option(a))
compile(root: Root(a)) -> Result(Compiled(a), types.TreeError)

stored(schema: Compiled(a)) -> schema.StoredSchema
view(schema: Compiled(a)) -> schema.ViewSchema
encode(schema: Compiled(a), value: a)
  -> Result(Option(types.TreeValue), types.TreeError)
decode(schema: Compiled(a), value: Option(types.TreeValue))
  -> Result(a, types.TreeError)
```

Root codecs deliberately accept/return `Option(TreeValue)`, matching native
creation and root reads. A required root always encodes to `Some`; decoding
`None` is an error. An optional root encodes/decodes `None` as an absent root.
An absent optional value is not a `NullValue`.

Example declaration:

```gleam
import gleam/option.{type Option}
import watershed/tree/schema_builder as builder

pub type Card {
  Card(title: String, owner: Option(String))
}

pub fn card() -> builder.Node(Card) {
  let factory = builder.factory("com.example.board")
  builder.object2(
    factory,
    "Card",
    Card,
    builder.required("title", builder.string(), fn(card) { card.title }),
    builder.optional("owner", builder.string(), fn(card) { card.owner }),
  )
}
```

The item-counter declaration becomes:

```gleam
pub fn definition() -> Result(builder.Compiled(List(String)), types.TreeError) {
  builder.array(
    builder.factory("shared_tree_item_counter"),
    "StringArray",
    builder.string(),
  )
  |> builder.root
  |> builder.compile
}
```

Preserve the resulting identifier `shared_tree_item_counter.StringArray`.

## 5. Descriptor and compilation invariants

Descriptors contain a type identifier, definitions needed by their children,
and typed encode/decode functions. Properties contain field metadata and typed
record accessors. Object builders combine these without erasing the public
value type.

Compilation performs these steps once:

1. Collect the root and transitively included node definitions.
2. Validate factory scopes and local names as nonempty strings. Join them with
   a period, following Fluid's explicit naming convention. Do not generate IDs.
3. Coalesce repeated definitions with the same identifier and equivalent wire
   structure, including a shared child used in multiple properties.
4. Reject an identifier associated with conflicting definitions. Compare
   normalized structure, not declaration order or closure identity.
5. Reject duplicate object keys before any dictionary conversion can discard
   evidence of the duplicate.
6. Sort node identifiers and object property keys for deterministic schema JSON.
   Keep constructor arguments and getters in declared order.
7. Render the existing schema-v2 representation and pass it through
   `schema.stored_from_json` and `schema.view_from_json`.
8. Return the validated schemas and root codec together as `Compiled(a)`.

Do not add a second compatibility checker or new persisted schema format.
Validation failure returns `TreeError`; no public builder panics.

Equivalent repeated definitions are deliberately accepted. Fluid's named
factory instances can be distinct even when their definitions agree; this
pure Gleam API has no object-identity rule. It rejects conflicting wire
definitions, not repeated evaluations of an identical declaration.

For persisted rendering, leaf identifiers/codes come from the pinned native
profile. Arrays use the unnamed sequence primary field, not a JSON `array`
kind. Maps use an optional entry field. Object fields and roots use required
or optional cardinality as declared.

## 6. Value codec contract

`encode` first constructs a `TreeValue` snapshot from the typed value, then
validates it against the compiled stored schema before returning it.
`decode` validates the complete root field before invoking its typed decoder.
Reuse `schema.validate_root_field`, including its path-bearing `TreeError`
results. Descriptor shape mismatches must also return explicit `TreeError`
values; do not substitute empty containers or default values.

Required behavior:

- Strings, booleans, null, and handles preserve their native value variants.
- Numbers are `Float`, matching `NumberValue`; non-finite values are rejected.
- Arrays preserve order and check their schema identifier.
- Maps decode into `Dict(String, a)` only after duplicate-key validation.
  Encode map entries in sorted key order for deterministic snapshots.
- Objects check their schema identifier, required fields, unknown fields,
  duplicate fields, and each field's value type.
- Optional properties encode `None` by omitting the property. Missing decodes
  as `None`; present values use the declared node decoder.
- Explicit null is a value described by `builder.null()`. It is not shorthand
  for absence, including inside optional properties.
- An optional nullable field distinguishes absence from a present null:
  `None` versus `Some(Nil)`.
- Schemas from different factories can compose. Reusing a descriptor across
  multiple parents is supported.

For lawful user-provided constructors/getters, `decode(encode(value))` returns
the original value. Gleam verifies types, not the semantic relationship
between an arbitrary constructor and its getters. Document that limitation
and use constructor/getter pairs that satisfy it in examples.

Handle snapshot codecs preserve `handle.Reference`; they do not attach or
resolve handles. The existing document runtime still owns attachment rules.

## 7. Integration and compatibility

Creation, opening, reading, editing, schema upgrades, events, transactions,
and both runtime facades retain their current signatures and semantics.
Applications pass `stored(compiled)`, `view(compiled)`, and `encode(compiled,
initial)` to those APIs and decode returned root snapshots explicitly.

The item-counter source should no longer declare serialized schema JSON or
pattern-match arrays to implement its own decoder. Keep its existing edit
preparation and submission model. A small compatibility wrapper around the
compiled codec can preserve its application-level `Result(..., String)`
boundary, using a named error formatter rather than discarding error details.

Keep the existing snippet IDs and update extraction markers around the new
declarations so the website comparison displays the authoring API. Explain
the distinction between typed snapshots and live typed nodes. Do not edit
the pinned upstream example, its digests, or generated snippet JSON manually.

## 8. Acceptance evidence

- Unit tests cover every leaf, empty/nonempty arrays and maps, nested objects,
  required/optional roots, and optional-versus-null semantics on both targets.
- Schema tests cover deterministic output, cross-factory composition, shared
  children, conflicting names, duplicate keys, and nonempty names/scopes.
- Failure cases cover wrong node identifiers, missing required fields,
  unknown/duplicate fields and keys, wrong leaf kinds, and non-finite numbers.
- Compile-fail fixtures prove wrong property/getter types, wrong constructor
  argument types, and wrong encoded root value types cannot compile.
- Positive compilation examples prevent a uniformly unusable API from
  satisfying only negative tests.
- A pinned Fluid oracle produces persisted schemas for the supported forms.
  Native generated schemas agree semantically with those schemas. Do not
  compare irrelevant JSON ordering or assume a parser round trip proves
  upstream agreement.
- The item-counter retains its existing persisted schema identity and behavior.
  Its tests and source-backed website comparison exercise the new API.

## 9. Global constraints

- Production code is pure Gleam on JavaScript and BEAM.
- No new production dependency, FFI, compiler plugin, or code generator.
- Keep `@fluidframework/tree` at `3.1.0` and Fluid commit `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960`.
- Keep the existing Schema V2 format and accepted interoperability profile.
- Preserve the current low-level schema and native facade APIs.
- Preserve `shared_tree_item_counter.StringArray` and the existing example behavior.
- Apply ASD-STE100 to Gleam comments and error strings, not Markdown or website prose.
- Do not edit apm-managed files, `.code-map/`, pinned upstream example bytes, or generated snippet JSON manually.
- Planning does not authorize implementation or changes to the earlier comment/dedenting work.
