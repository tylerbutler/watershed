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

For larger records, `object` accepts a list of `property` descriptors and a
typed reader callback, with no fixed property count:

```gleam
let title = builder.required("title", builder.string(), fn(v: Card) { v.title })
let owner = builder.optional("owner", builder.string(), fn(v: Card) { v.owner })
builder.object(factory, "Card", [
  builder.property(title),
  builder.property(owner),
], fn(reader) {
  use title <- result.try(builder.read_property(reader, title))
  use owner <- result.try(builder.read_property(reader, owner))
  Ok(Card(title, owner))
})
```

`read_property` checks the property against the declaration. A property from
another record is a type error; an undeclared key or mismatched field
definition returns a schema error. The callback never handles raw tree values.

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

## Named recursion

Use `lazy(factory, name, resolve)` for a named recursive edge. The resolver is
a pure declaration function, not a value loader:

```gleam
pub type Outline {
  Outline(label: String, children: List(Outline))
}

pub fn outline() -> builder.Node(Outline) {
  let f = builder.factory("com.example")
  let self = builder.lazy(f, "Outline", outline)
  builder.object2(
    f,
    "Outline",
    Outline,
    builder.required("label", builder.string(), fn(v: Outline) { v.label }),
    builder.required(
      "children",
      builder.array(f, "Children", self),
      fn(v: Outline) { v.children },
    ),
  )
}
```

The resolver must return a concrete named object, array, or map with the exact
claimed identifier. Alias-only lazy chains, leaves, differently named
containers, and multi-type unions are rejected. Recursive union branches
can themselves be lazy. Mutual recursion and optional recursive children
work the same way.

Compilation checks a finite definition graph, including conflicting
declarations of an already-seen name. Encoding and decoding follow finite
values instead of expanding the schema. Required cycles retain their declared
cardinalities and follow the native validator; the builder does not invent an
empty value for a type with no finite inhabitant.

## Identifier fields and new content

`identifier(key, getter)` declares a native Identifier object property whose
application value is `builder.Identifier`:

```gleam
pub type Item {
  Item(id: builder.Identifier, label: String)
}

pub fn item() -> builder.Node(Item) {
  builder.object2(
    builder.factory("com.example"),
    "Item",
    Item,
    builder.identifier("id", fn(v: Item) { v.id }),
    builder.required("label", builder.string(), fn(v: Item) { v.label }),
  )
}
```

`Assigned(string)` preserves the exact string, including empty strings and
duplicate custom identifiers. Identifier strings are not node identity.
`Generate` asks the document compressor for an identifier when new content is
inserted.

Strict `encode` rejects `Generate`. `encode_new(compiled, value)` omits those
properties and validates a construction snapshot. It propagates through
objects, optional properties, collections, unions, and recursive values.
Repeated calls produce the same unallocated snapshot: the builder does not
allocate IDs, mutate records, or generate application UUIDs. Pass the result
to native document creation or insertion; the existing runtime materializes
the missing fields through the document compressor.

Strict `decode` rejects missing identifiers and returns only `Assigned` values.
Input and output share the same record type, so the type alone does not
distinguish construction input from read output. Successful reads have the
stronger runtime guarantee that no Identifier is `Generate`. Read after
insertion to obtain generated values.

Transaction rollback restores document content but can retain compressor
advancement. It does not promise that an allocated identifier can be reused.
Identifier cardinality is only available on object properties, not roots or
collection entry declarations.

## Native create, open, and read

The native facades accept a schema-scoped `typed.Schema(s, r)` and a matching
`typed.Builder(s, input)`, not raw stored and view schemas. The item-counter
example supplies these adapters through `document_schema.declaration()` and
`document_schema.builder()`:

```gleam
import gleam/option.{Some}
import shared_tree_item_counter_lustre/schema as document_schema

watershed.create_tree_container(
  create_config,
  document_schema.declaration(),
  document_schema.builder(),
  Some(document_schema.initial()),
)

// On an already connected document:
watershed.create_tree(
  document,
  document_schema.declaration(),
  document_schema.builder(),
  Some(document_schema.initial()),
)
```

`create_tree_container` on JavaScript returns a promise of the creation
result; the BEAM facade returns the result. Creation does not connect the
document. To open an existing document, connect, resolve the root, get its
`"tree"` handle, and call `resolve_tree` with
`document_schema.declaration()` as its final argument.

The example's native record is `TreeValue`, so `tree_read_root(tree)` returns
an `Option(TreeValue)` that `builder.decode(compiled, snapshot)` can decode.
Other native declarations can decode their own application record directly.
The [item-counter application](../examples/shared_tree_item_counter_lustre)
shows the corresponding Lustre effects, subscriptions, cleanup, and error
handling.

Decoded records and lists are snapshots. Reconstructing a record or changing
a local list does not submit an edit.

## Typed live access

Import `watershed/tree as live` and bind an existing native tree with
`watershed.tree_typed(tree, compiled)`. On BEAM, use
`watershed_beam.tree_typed` with the same compiled descriptor. Keep the
property descriptors used to build your object so you can use them for reads
and writes:

```gleam
let assert Ok(view) = watershed.tree_typed(tree, compiled)
let assert Ok(item) = live.required_root(view)
let assert Ok(Nil) = live.set(item, label_property, "Renamed")
let assert Ok(label) = live.get(item, label_property)
```

`read_root` and `read` return snapshots. A `Ref(a)` instead identifies an
object, array, or map in one runtime and checkout. Saved references follow
surviving nodes through insertions and moves; they do not follow the old
index or a matching Identifier string. Leaves remain values, not references.
Use `optional_root` and `optional_child` for optional composite fields,
`array_node` and `map_node` for collection entries, and `narrow` for a
composite union branch.

Explicit edits use `replace_root`, `set`, `array_insert`, `array_remove`,
`array_move`, `map_set`, and `map_delete`. The construction variants
`replace_root_new`, `set_new`, `array_insert_new`, and `map_set_new` accept
`Generate` identifiers. Ordinary writes use strict snapshot encoding.
Identifier properties themselves are read-only.

When an action targets a saved item reference, use `array_remove_node` or
`array_move_before` instead of looking up its current index. Both resolve the
item's identity and array membership in the edit itself, so preceding remote
insertions cannot redirect the action. Pass `None` as `before` to append; a
reference from another document or checkout is rejected.

The same `Tree(a)` supports typed operations, `transaction`, `fork`, `merge`,
and `rebase_onto`. An abort restores the content and invalidates references to
preview-only nodes; it does not make those node identities available for later
insertions. Callback errors retain their application type inside `Aborted`;
exceptions roll back and return `TransactionFailed`. Use `KeepSource` or
`DisposeSource` to choose whether merging retains the source checkout.

`status` reports `Attached`, `Removed`, `Deleted`, or `Invalidated`.
Only attached references can be read or edited. Retained removed nodes can
reattach on undo; references do not keep repair data alive.

`observe` and `observe_node` re-read typed snapshots after native commits.
Their callbacks receive `Result` values, including removal and schema errors,
not a promise of Fluid's exact per-node event counts. `unsubscribe` cancels
one observation. Callbacks can read committed state and cancel observations,
but cannot submit reentrant edits. `dispose(view)` cancels that view's
observations and releases its anchors without closing the native tree. Both
cleanup operations are idempotent. Closed handles, disposed checkouts, runtime
shutdown, incompatible schemas, and foreign references return structured
`Error` values from `watershed/tree/error`. Invalid edits retain the original
`TreeError`, including its path and details. Connection readiness, timeouts,
transaction ownership, and reentrant writes have distinct error variants;
`error.to_string` formats them for display without discarding the typed value.

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
| Recursive schema reference | `lazy(factory, name, resolve)` |
| `sf.identifier` | `identifier(key, getter)` |
| View configuration | `view(compiled)` plus the existing native open API |

This milestone excludes anonymous names, custom codecs, schema migration,
code generation, and typed live node references. The low-level native schema
API retains its existing capabilities. The arity constructors support up to
eight properties; `object` has no fixed property limit. This layer uses the
same Schema V2 format and does not expand the accepted interoperability profile.

The independent [authoring oracle](../tools/shared-tree-oracle/README.md#typed-schema-authoring-capture)
compares generated schemas with `@fluidframework/tree` 3.1.0 at commit
`c3c5bf0ecd313362e83fe8a02b7d39e7e0736960`. Native codec and schema tests run on
both JavaScript and BEAM.
