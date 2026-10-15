# Typed SharedTree schema authoring

Declare a native tree's schema and snapshot codecs together with
`watershed/tree/schema_builder`. Your application still defines its Gleam
records. The compiler checks property getter types against constructor
arguments and the value you pass to `encode`.

## A string array

The item-counter example declares its document like this:

```gleam
import watershed/tree/schema_builder as builder
import watershed/tree/types

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

The persisted type identifier is `shared_tree_item_counter.StringArray`.
Factory scopes and local names must be nonempty. A factory joins them with
`.`; it does not generate names. Descriptors from different factories can
compose.

Compile the descriptor once during initialization. Keep the resulting
`Compiled(a)` for creation, opening, encoding, and decoding. Check compilation
errors before starting a connection or creating a document.

## Records and properties

```gleam
import gleam/option.{type Option}
import watershed/tree/schema_builder as builder

pub type Card {
  Card(title: String, owner: Option(String))
}

pub fn card() -> builder.Node(Card) {
  builder.object2(
    builder.factory("com.example.board"),
    "Card",
    Card,
    builder.required("title", builder.string(), fn(card: Card) { card.title }),
    builder.optional("owner", builder.string(), fn(card: Card) { card.owner }),
  )
}
```

Use `object0` for an empty object with a `Nil` snapshot. `object1` through
`object8` accept a constructor and the corresponding number of properties.
Constructor arguments stay in declaration order; the builder sorts persisted
field names. Duplicate property names and conflicting definitions of the same
node identifier cause compilation errors. Equivalent repeated definitions
coalesce, so you can reuse a child descriptor in several fields.

Gleam checks the constructor/getter types, not their meaning. Supply getters
that return the corresponding constructor arguments. Swapping two getters
with the same value type can compile while changing your data.
For lawful pairs, decoding an encoded value returns the original value.

## Roots, absence, and null

`root(node)` produces a required root. `optional_root(node)` produces an
optional root whose snapshot type is `Option(a)`.

| Declaration | Snapshot type | Encoding |
| --- | --- | --- |
| `root(string())` | `String` | `Some(StringValue(text))` |
| `optional_root(string())` | `Option(String)` | `None` or `Some(StringValue(text))` |
| `root(null())` | `Nil` | `Some(NullValue)` |
| `optional_root(null())` | `Option(Nil)` | `None` or `Some(NullValue)` |

An optional property omits `None`; a present property must have its declared
node type. In particular, an optional string does not accept a null leaf.
An optional null property distinguishes absent `None` from present
`Some(Nil)`.

## Checked snapshots and errors

`encode(compiled, value)` returns `Result(Option(TreeValue), TreeError)`.
`decode(compiled, snapshot)` returns `Result(a, TreeError)`. Both use the
existing native content validator. Required roots reject absence; invalid
snapshots report errors rather than empty containers or default values.

```gleam
case builder.encode(compiled, []) {
  Error(error) -> report_tree_error(error)
  Ok(initial_root) -> create_document(initial_root)
}
```

Use your application's error handlers in place of the illustrative
`report_tree_error` and `create_document` functions. Preserve the full
`TreeError`, including paths and diagnostic details, when formatting it for
your UI. Do not treat failed reads as zero entries.

Arrays preserve order. Maps use `Dict(String, a)` and encode entries in sorted
key order. The validator rejects duplicate map keys and object fields before
the decoder converts them to dictionaries or records. It also checks unknown
fields, missing required fields, node identifiers, leaf kinds, and finite
numbers.

The leaf descriptors are `string`, `number` (`Float`), `boolean`, `null`, and
`handle`. Handle codecs preserve validated `handle.Reference` values without
resolving or attaching them. Document runtimes retain responsibility for
handle attachment.

## Heterogeneous unions

`union` combines typed branches without adding a persisted node type. Each
`variant(node, inject, project)` supplies a constructor into an application
sum type and a projector back to that branch:

```gleam
pub type Choice {
  Text(String)
  Count(Float)
}

pub fn choice() -> builder.Node(Choice) {
  builder.union([
    builder.variant(builder.string(), Text, fn(value) {
      case value { Text(text) -> Some(text) Count(_) -> None }
    }),
    builder.variant(builder.number(), Count, fn(value) {
      case value { Count(number) -> Some(number) Text(_) -> None }
    }),
  ])
}
```

Unions work in roots, properties, arrays, and maps. Nested unions flatten their
allowed type sets; reordering alternatives does not change the stored schema.
Compilation rejects empty unions and overlapping branch type identifiers.
Branches cannot distinguish two values with the same persisted type by
inspecting their contents.

Encoding requires exactly one matching projector. Decoding selects the branch
by persisted type identifier. For each branch, `project(inject(value))` must
return `Some(value)`, and all other branch projectors must return `None`.
Gleam checks the function types, not these laws; test the pairs with application
values. Missing or ambiguous projections return errors, never a default branch.

## Native create, open, and read

The native facade APIs keep their signatures:

```gleam
// After checking builder.encode(compiled, initial_value):
watershed.create_tree_container(
  create_config,
  builder.stored(compiled),
  initial_root,
)

// On an already connected document:
watershed.create_tree(
  document,
  builder.stored(compiled),
  initial_root,
  builder.view(compiled),
)
```

`create_tree_container` on JavaScript returns a promise of the creation
result; the BEAM facade returns the result. Creation does not connect the
document. To open an existing document, connect, resolve the root, get its
`"tree"` handle, and call `resolve_tree` with `builder.view(compiled)`.

After `tree_get(tree, [])` succeeds, pass its `Option(TreeValue)` result to
`builder.decode(compiled, snapshot)`. The
[item-counter application](../examples/shared_tree_item_counter_lustre)
shows the corresponding Lustre effects, subscriptions, cleanup, and error
handling. It retains the compiled descriptor in application state.

Decoded records and lists are snapshots. Reconstructing a record or changing
a local list does not submit an edit. Continue to use the native edit,
transaction, and subscription APIs. Typed live references belong to a
separate milestone.

## Fluid mapping and scope

| Fluid authoring form | Gleam descriptor |
| --- | --- |
| `SchemaFactory("scope")` | `factory("scope")` |
| Primitive schema | Corresponding leaf function |
| `sf.array("Name", element)` | `array(factory, "Name", element)` |
| `sf.map("Name", value)` | `map(factory, "Name", value)` |
| `sf.object("Name", fields)` | `object0` through `object8` |
| Implicit required field | `required(key, node, getter)` |
| `sf.optional(node)` | `optional(key, node, getter)` or `optional_root(node)` |
| Allowed-type array | `union([variant(node, inject, project), ...])` |
| View configuration | `view(compiled)` plus the existing native open API |

This milestone excludes recursive declarations,
Identifier defaults, anonymous names, custom codecs, schema migration,
code generation, and typed live node references. The low-level native schema
API retains its existing capabilities. Object descriptors support at most
eight properties. This layer uses the same Schema V2 format and does not
expand the accepted interoperability profile.

The independent [authoring oracle](../tools/shared-tree-oracle/README.md#typed-schema-authoring-capture)
compares generated schemas with `@fluidframework/tree` 3.1.0 at commit
`c3c5bf0ecd313362e83fe8a02b7d39e7e0736960`. Native codec and schema tests run on
both JavaScript and BEAM.
