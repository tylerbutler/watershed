# Typed SharedTree Schema Authoring Implementation Plan

> **For agentic workers:** Use the executing-plans skill for inline execution.
> Use subagent-driven-development only if the user requests delegation.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace serialized native SharedTree schema declarations and parallel
snapshot decoders with typed Gleam descriptors that derive both.

**Architecture:** Add one pure `watershed/tree/schema_builder` module above
the existing persisted-schema boundary. Compile typed node/property/root
descriptors into existing stored/view schemas and typed root snapshot codecs.
Keep live tree operations and runtime facades unchanged.

**Tech Stack:** Dual-target Gleam, startest, existing compile-fail packages,
the pinned Fluid source oracle, gleeunit for the Lustre example, and Astro's
existing source-snippet generator.

**Spec:** [Approved design](../specs/2026-10-15-shared-tree-schema-authoring-design.md).

**Follow-on:** [Authoring extensions and identity-bound live access](2026-10-15-shared-tree-typed-api-follow-on.md)
is a separate plan, dependent on acceptance of this milestone.

## Global constraints

- Production code is pure Gleam on JavaScript and BEAM.
- No new production dependency, FFI, compiler plugin, or code generator.
- Keep `@fluidframework/tree` at `3.1.0` and Fluid commit `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960`.
- Keep the existing Schema V2 format and accepted interoperability profile.
- Preserve the current low-level schema and native facade APIs.
- Preserve `shared_tree_item_counter.StringArray` and the existing example behavior.
- Apply ASD-STE100 to Gleam comments and error strings, not Markdown or website prose.
- Do not edit apm-managed files, `.code-map/`, pinned upstream example bytes, or generated snippet JSON manually.
- Planning does not authorize implementation or changes to the earlier comment/dedenting work.

---

## Execution boundaries

This plan is not an instruction to start implementation. Obtain execution
approval separately and use an isolated worktree. The earlier comparison
comments and snippet whitespace fix are unrelated pending changes: do not
reset, silently overwrite, or include them in implementation commits.

Read `AGENTS.md` and the design first. Before modifying the website, also read
`.github/instructions/website-copy.instructions.md`. Use code-map to locate
current declarations and read source before editing; line numbers below are
navigation aids, not permanent boundaries.

Run each new test red before implementing its behavior. A missing import can
explain the first red result; after the module exists, regression tests must
fail on the intended output or validation behavior. Positive tests must compile
before interpreting compile-fail fixture results.

Use existing dependencies. Restore them only after a selected command reports
a missing package or tool. Each task is a review/commit boundary; commit only
its files and include:

```text
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```

## File structure

| File | Responsibility |
| --- | --- |
| `src/watershed/tree/schema_builder.gleam` | Public typed descriptors, derived codecs, definition collection, and compilation through existing validators. |
| `test/watershed/shared_tree_schema_builder_test.gleam` | Schema output, declaration validation, positive typing examples, pinned oracle comparisons. |
| `test/watershed/shared_tree_schema_builder_codec_test.gleam` | Snapshot round trips and path-bearing value failures. |
| `tools/compile-fail/incompatible_tree_property/` | Reject mismatched property getter types. |
| `tools/compile-fail/incompatible_tree_constructor/` | Reject mismatched object constructor argument types. |
| `tools/compile-fail/incompatible_tree_root/` | Reject values inconsistent with the compiled root type. |
| `justfile` | Register those fixtures in `_test-compile-fail`. |
| `tools/shared-tree-oracle/upstream-schema-evolution.spec.ts` | Add an independent schema-authoring capture using existing pinned-source extraction imports. |
| `test/fixtures/shared_tree/schema-authoring.json` | Generated, provenance-bearing schema-authoring observations; separate from operational corpus cases. |
| `tools/shared-tree-oracle/README.md` | Document capture and comparison commands. |
| `examples/shared_tree_item_counter_lustre/src/shared_tree_item_counter_lustre/schema.gleam` | Typed string-array declaration and application schema/codec wrappers. |
| `examples/shared_tree_item_counter_lustre/src/shared_tree_item_counter_lustre/counter.gleam` | Delegate snapshot decoding to the compiled descriptor. |
| `examples/shared_tree_item_counter_lustre/src/shared_tree_item_counter_lustre.gleam` | Handle schema/codec initialization errors without panicking; preserve lifecycle and edits. |
| `examples/shared_tree_item_counter_lustre/test/shared_tree_item_counter_lustre_test.gleam` | Preserve behavior and persisted schema identity. |
| `examples/shared_tree_item_counter_lustre/README.md` | Explain the new declaration and snapshot boundary. |
| `website/src/data/sharedtree-item-counter.ts` | Describe typed authoring rather than serialized schema setup. |
| `website/src/data/sharedtree-item-counter.test.ts` | Existing source attribution checks and targeted generated-snippet assertions. |
| `website/snippets.json` | Keep snippet IDs; adjust range composition only if source boundaries require it. |
| `README.md`, `docs/shared-tree-schema-authoring.md` | Public introduction, API usage, guarantees, and exclusions. |

Do not split the implementation into a registry framework or shared codec
package. The low-level `schema.gleam` validator remains the authority.

## Public interfaces used throughout

The design defines every public name. In this plan, `builder` means
`watershed/tree/schema_builder`, and `types` means `watershed/tree/types`.

```gleam
factory(String) -> Factory
string() -> Node(String)
number() -> Node(Float)
boolean() -> Node(Bool)
null() -> Node(Nil)
handle() -> Node(handle.Reference)
array(Factory, String, Node(a)) -> Node(List(a))
map(Factory, String, Node(a)) -> Node(Dict(String, a))
required(String, Node(a), fn(record) -> a) -> Property(record, a)
optional(String, Node(a), fn(record) -> Option(a))
  -> Property(record, Option(a))
object0(Factory, String) -> Node(Nil)
object1(Factory, String, fn(a) -> record, Property(record, a)) -> Node(record)
object2(Factory, String, fn(a, b) -> record,
        Property(record, a), Property(record, b)) -> Node(record)
root(Node(a)) -> Root(a)
optional_root(Node(a)) -> Root(Option(a))
compile(Root(a)) -> Result(Compiled(a), types.TreeError)
stored(Compiled(a)) -> schema.StoredSchema
view(Compiled(a)) -> schema.ViewSchema
encode(Compiled(a), a) -> Result(Option(types.TreeValue), types.TreeError)
decode(Compiled(a), Option(types.TreeValue)) -> Result(a, types.TreeError)
```

`object3` through `object8` extend `object2` with the corresponding constructor
arity and `Property(record, parameter_type)` arguments. No heterogeneous public
list or runtime property casts are permitted.

### Task 1: Compile leaf schemas and required/optional roots

**Files:** Create the implementation module and both root test modules.
**Consumes:** Existing schema parser, `schema.validate_root_field`, `TreeValue`,
`TreeError`, and `handle.Reference`.
**Produces:** All leaf, root, compilation, schema accessor, and codec functions
listed above. Define the private descriptor representation so composite
descriptors can add definitions in subsequent tasks.

- [ ] **1. Write the required string root test.**

```gleam
import gleam/option.{None, Some}
import startest/expect
import watershed/tree/schema
import watershed/tree/schema_builder as builder
import watershed/tree/types

pub fn shared_tree_schema_builder_string_root_test() {
  let assert Ok(compiled) =
    builder.string() |> builder.root |> builder.compile
  builder.encode(compiled, "hello")
  |> expect.to_equal(Ok(Some(types.StringValue("hello"))))
  builder.decode(compiled, Some(types.StringValue("hello")))
  |> expect.to_equal(Ok("hello"))
  builder.decode(compiled, None) |> expect.to_be_error
  schema.can_view(builder.stored(compiled), builder.view(compiled))
  |> expect.to_equal(Ok(Nil))
}
```

- [ ] **2. Run it red.**

```sh
gleam test --target javascript -- shared_tree_schema_builder
```

- [ ] **3. Add opaque descriptors and the compiler.**

Use a private `Node(a)` representation with identifier, collected node
definitions, declaration errors, an encoder `fn(a) -> TreeValue`, and a decoder
`fn(TreeValue) -> Result(a, TreeError)`. A `Root(a)` has analogous root-field
metadata and optional snapshot codecs. A `Compiled(a)` stores both validated
low-level schemas and the root codecs. Keep raw constructor fields private.

Construct leaf schema definitions with existing `schema.Leaf` / `LeafKind`
values. Render persisted leaf codes as number `0`, string `1`, boolean `2`,
handle `3`, and null `4`, with their existing
`com.fluidframework.leaf.*` identifiers. Use Gleam JSON constructors, never
JSON string concatenation.

Compilation returns the first declaration error, normalizes and sorts
definitions, renders Schema V2, then calls both existing schema parsers.
Repeated equivalent definitions coalesce; conflicting definitions return
`InvalidSchema` before dictionary insertion. Normalize object-field order for
definition comparison. Define rendering for `Object`, `Array`, and `Map` now
using the existing low-level variants, without exposing composite constructors
until their tests are in place.

Wrap encode/decode with `schema.validate_root_field`. Preserve its existing
`TreeError`, including paths. Unexpected decoder variants return
`CorruptData(location, detail)` rather than panicking or supplying defaults.

- [ ] **4. Add leaf and root matrix rows one at a time, red then green.**

| Input | Expected |
| --- | --- |
| `number()` with `1.5` | `Some(NumberValue(1.5))`, then `1.5`. |
| `boolean()` with `True` | `Some(BooleanValue(True))`, then `True`. |
| `null()` with `Nil` | `Some(NullValue)`, not root absence. |
| `handle()` with a validated `/B/child` reference | Same reference on decode, without resolution or attachment. |
| Required string root with a number or no value | Error, not coerced text or empty string. |
| Optional string root with `None` / `Some("x")` | Absent root / present string. |
| Optional null root with `None` / `Some(Nil)` | Distinct `None` / `Some(NullValue)` snapshots. |
| Non-finite numeric snapshot | Existing finite-number validation error. |

Use `handle.reference_from_path("/B/child")` for the handle test. For numeric
edge cases, use repository-supported target-specific test construction only;
do not add production FFI to manufacture NaN or infinity.

- [ ] **5. Run both targets and formatting checks, then commit the task.**

```sh
gleam test --target erlang -- shared_tree_schema_builder
gleam test --target javascript -- shared_tree_schema_builder
gleam format --check src/watershed/tree/schema_builder.gleam test/watershed/shared_tree_schema_builder_test.gleam test/watershed/shared_tree_schema_builder_codec_test.gleam
```

Suggested commit: `feat(tree): add typed schema roots`.

### Task 2: Named arrays, maps, and deterministic composition

**Files:** Modify the builder and its two test modules.
**Consumes:** Task 1's `Node(a)`, root compiler, and low-level content validator.
**Produces:** `factory`, `array`, and `map` with the signatures above; stable
scoped names and deterministic collection snapshots.

- [ ] **1. Add and run this test red.**

```gleam
pub fn shared_tree_schema_builder_array_round_trip_test() {
  let assert Ok(compiled) =
    builder.array(builder.factory("com.example"), "Words", builder.string())
    |> builder.root
    |> builder.compile
  let expected =
    Some(types.ArrayValue("com.example.Words", [
      types.StringValue("first"),
      types.StringValue("second"),
    ]))
  builder.encode(compiled, ["first", "second"])
  |> expect.to_equal(Ok(expected))
  builder.decode(compiled, expected)
  |> expect.to_equal(Ok(["first", "second"]))
}
```

```sh
gleam test --target javascript -- shared_tree_schema_builder
```

- [ ] **2. Implement scoped array/map descriptors.**

Join the factory scope and explicit name with `"."`. Keep invalid-scope/name
errors in descriptor metadata until `compile`; constructing an invalid
descriptor must not panic. Arrays encode to `ArrayValue(identifier, values)`;
maps encode to `MapValue(identifier, sorted_entries)`.

Render array definitions as a single unnamed field with `"Sequence"`
cardinality. Render map entries with `"Optional"` cardinality. Include
transitive child definitions. Map decoding must validate duplicate keys before
`dict.from_list`. Sort encoded map keys with the existing Gleam string ordering;
do not introduce locale-sensitive or JavaScript object-key ordering.

- [ ] **3. Add these schema and codec checks, each red before implementation.**

| Case | Expected |
| --- | --- |
| Empty and populated array | Stable identifier and preserved order. |
| Map created from entries in reverse order | Sorted snapshot entries; equivalent decoded `Dict`. |
| Map containing `""`, `"__proto__"`, `"2"`, and `"10"` keys | No special object-key interpretation. |
| Array of maps, map of arrays | Transitive definitions and nested round trip. |
| Wrong array/map schema identifier | Error. |
| Duplicate map key in raw snapshot | Error before dictionary conversion. |
| Empty scope or local name | Compilation error. |
| Scope containing periods | Exact prefix composition, without generated names. |
| Reordered equivalent declarations | Byte-identical `json.to_string(schema.stored_to_json(...))`. |
| Same identifier used for array and map | Compilation error, not last-definition-wins behavior. |

The conflicting-definition test becomes expressible through two object
properties in Task 3; retain that matrix row there rather than adding a public
registry API solely for tests.

- [ ] **4. Run the Task 1 dual-target selectors and commit.**

Suggested commit: `feat(tree): add typed collection schemas`.

### Task 3: Typed object properties and record builders

**Files:** Modify the builder and both test modules.
**Consumes:** Typed child descriptors and the compiled-root pipeline.
**Produces:** `Property(record, a)`, `required`, `optional`, and `object0` through
`object8`.

- [ ] **1. Add and run this object round-trip test red.**

```gleam
import gleam/option.{type Option, None, Some}

type Card {
  Card(title: String, owner: Option(String))
}

fn card_node() -> builder.Node(Card) {
  builder.object2(
    builder.factory("com.example"),
    "Card",
    Card,
    builder.required("title", builder.string(), fn(card) { card.title }),
    builder.optional("owner", builder.string(), fn(card) { card.owner }),
  )
}

pub fn shared_tree_schema_builder_optional_property_test() {
  let assert Ok(compiled) = card_node() |> builder.root |> builder.compile
  let expected =
    Some(types.ObjectValue("com.example.Card", [
      #("title", types.StringValue("Ship it")),
    ]))
  builder.encode(compiled, Card("Ship it", None))
  |> expect.to_equal(Ok(expected))
  builder.decode(compiled, expected)
  |> expect.to_equal(Ok(Card("Ship it", None)))
}
```

```sh
gleam test --target javascript -- shared_tree_schema_builder
```

- [ ] **2. Implement properties and `object0` / `object1` / `object2`.**

Use the typed-map `Prop`/`recordN` code as a pattern, not as an encoder to call.
A property should expose private operations sufficient to derive field
metadata, decode one field into its constructor argument, and encode a field
from its record getter. Required properties always emit an entry. Optional
properties omit `None` and decode only missing fields as `None`.

Combine each property's child definitions and declaration errors. Preserve
constructor argument order while emitting object field entries and schema
field declarations in sorted key order. Reject duplicate property keys at
compile time even when their definitions match. `object0` uses `Nil` as its
value and only accepts an empty object snapshot.

- [ ] **3. Extend the same typed pattern through `object8`.**

Every builder's constructor has exactly the property's argument types:

```gleam
object3(
  Factory,
  String,
  fn(a, b, c) -> record,
  Property(record, a),
  Property(record, b),
  Property(record, c),
) -> Node(record)
```

Continue with distinct type parameters through `h`. Do not replace constructor
typing with a list of dynamic values. Add positive compile-and-round-trip
examples for every arity; use distinguishable field values and intentionally
nonalphabetical declaration order to catch constructor-position mistakes.

- [ ] **4. Add negative and composition matrix rows red/green.**

Cover missing required fields, unknown fields, duplicate raw fields, wrong
leaf kinds, wrong object identifiers, nested error paths, and optional-null
`None` versus `Some(Nil)`. Optional string fields must reject `NullValue`.

For schema compilation, test two properties sharing the same child descriptor,
two equivalent independently evaluated child definitions, a conflicting
same-name child definition, duplicate property names, and children from
different factories. Verify shared leaves appear once in rendered schema JSON.
Compare definitions independently of declaration order.

- [ ] **5. Run both target selectors and commit.**

Suggested commit: `feat(tree): derive typed object schema codecs`.

### Task 4: Prove the compile-time guarantees

**Files:** Create the three compile-fail packages from the file map; modify
`justfile:_test-compile-fail`. Existing Trellis exclusion globs already cover
`tools/compile-fail/*`; do not add individual workspace entries.
**Consumes:** Task 3's public types and positive tests.
**Produces:** Repeatable checks that fail only when the intended type guarantee
is absent, with no false success from syntax or dependency errors.

- [ ] **1. Run the positive typing tests before adding negative fixtures.**

```sh
gleam test --target javascript -- shared_tree_schema_builder
```

- [ ] **2. Add each package manifest with the existing fixture pattern.**

Use this structure, substituting each package's actual name:

```toml
name = "incompatible_tree_root"
version = "1.0.0"
licences = ["MIT"]
gleam = ">= 1.7.0"
target = "javascript"

[dependencies]
gleam_stdlib = ">= 0.62.0 and < 2.0.0"
watershed = { path = "../../.." }
```

Include a minimal source module per package:

```gleam
// incompatible_tree_property
import watershed/tree/schema_builder as builder
pub type Note { Note(count: Int) }
pub fn invalid() -> builder.Property(Note, String) {
  builder.required("count", builder.string(), fn(note) { note.count })
}
```

```gleam
// incompatible_tree_constructor
import gleam/int
import watershed/tree/schema_builder as builder
pub type Note { Note(count: Int) }
pub fn invalid() -> builder.Node(Note) {
  builder.object1(
    builder.factory("com.example"),
    "Note",
    Note,
    builder.required(
      "count",
      builder.string(),
      fn(note) { int.to_string(note.count) },
    ),
  )
}
```

```gleam
// incompatible_tree_root
import watershed/tree/schema_builder as builder
pub fn invalid(schema: builder.Compiled(String)) {
  builder.encode(schema, 42)
}
```

- [ ] **3. Build each fixture and inspect the actual diagnostic.**

```sh
(cd tools/compile-fail/incompatible_tree_property && gleam build --target javascript)
(cd tools/compile-fail/incompatible_tree_constructor && gleam build --target javascript)
(cd tools/compile-fail/incompatible_tree_root && gleam build --target javascript)
```

Run these commands from the repository root. Expected: a
String/Int type mismatch at the getter, property/constructor, or encode call,
respectively. Fix any unrelated error before recording the expected diagnostic.

- [ ] **4. Add recipe checks using the existing exit-status-plus-diagnostic pattern.**

Capture compiler output, require a nonzero exit status, and match the observed
type mismatch rather than accepting any compiler failure. Use distinctive
type names or String/Int diagnostic lines from Step 3. Each check must report
unexpected success and unexpected failure separately.

```sh
just _test-compile-fail
```

Expected: existing fixtures and all three new fixtures are rejected for their
stated type errors. Suggested commit: `test(tree): enforce schema authoring types`.

### Task 5: Compare generated schemas with the pinned Fluid authoring API

**Files:** Modify `tools/shared-tree-oracle/upstream-schema-evolution.spec.ts`,
`tools/shared-tree-oracle/README.md`, and
`test/watershed/shared_tree_schema_builder_test.gleam`. Create the generated
`test/fixtures/shared_tree/schema-authoring.json`.
**Consumes:** Existing injected-source imports of `SchemaFactory`,
`extractPersistedSchema`, and `FluidClientVersion`; the existing source capture
runner, version checks, and allowed injection paths.
**Produces:** An independently captured, provenance-bearing fixture for the
supported authoring subset, consumed by native tests on both targets.

- [ ] **1. Add a separate capture test to the existing injected schema source.**

Do not change its schema-evolution cases, random/session ID stream, corpus
manifest, or supported profile. The new test only extracts schemas and writes
an additional output file.

Use the existing helper, whose implementation is:

```typescript
function persisted(schema: ImplicitFieldSchema): unknown {
  return extractPersistedSchema(schema, FluidClientVersion.v2_117, () => false);
}
```

The independently declared Fluid cases must include each primitive root,
required and optional string roots, a named string array, a named number map,
an object with required and optional fields, an empty object, nested
array/map/object combinations, a repeated child type, and cross-factory
composition. Give native declarations the same explicit names.

Example capture declaration:

```typescript
const sf = new SchemaFactory("com.example.authoring");
class Words extends sf.array("Words", sf.string) {}
class Card extends sf.object("Card", {
  title: sf.string,
  owner: sf.optional(sf.string),
}) {}
const observations = [
  { id: "string-array", schema: persisted(Words) },
  { id: "card", schema: persisted(Card) },
  { id: "optional-string-root", schema: persisted(sf.optional(sf.string)) },
];
```

Write a deterministic JSON document containing `formatVersion: 1`, the exact
package/version/commit reference, and the observations. Validate the absolute
output path and reference environment with the existing test's pattern. The
file name is `schema-authoring.json`.

- [ ] **2. Capture and commit the independent fixture using existing tooling.**

```sh
npm --prefix tools/shared-tree-oracle run source:verify
node --input-type=module -e 'import { runSource } from "./tools/shared-tree-oracle/source.mjs"; await runSource("tools/shared-tree-oracle/.output/schema-authoring", { corpus: true });'
cp tools/shared-tree-oracle/.output/schema-authoring/schema-authoring.json test/fixtures/shared_tree/schema-authoring.json
```

Prepare the verified source only if the selected command reports it missing.
Do not install packages merely to run planning or native unit tests.
Use `runSource` directly with `corpus: true`: the default `source:capture`
command does not run the schema-evolution source batch, and its publication
helper retains only `source-smoke.json`. Do not change that helper's contract
for this task.

- [ ] **3. Add native fixture comparison tests and watch them fail on a deliberate mismatch.**

Read the fixture with existing development dependency `simplifile` and decode
its envelope with `gleam/dynamic/decode`. Assert all reference values and the
exact expected case-ID set, so a missing case cannot silently reduce coverage.
For each native declaration, parse the independently captured schema using
`schema.stored_from_json`.

Check both semantic equivalence and the actual normalized persisted
representation. Two-way `schema.allows_superset` alone is insufficient because
unused definitions and metadata can be overlooked by compatibility checks.
Normalize JSON object order for comparison, but do not remove field kinds,
allowed types, type identifiers, or node definitions. Include a test showing
the comparator rejects a changed array/map element type.

- [ ] **4. Run the native tests and verify deterministic recapture.**

```sh
gleam test --target erlang -- shared_tree_schema_builder
gleam test --target javascript -- shared_tree_schema_builder
node --input-type=module -e 'import { runSource } from "./tools/shared-tree-oracle/source.mjs"; await runSource("tools/shared-tree-oracle/.output/schema-authoring", { corpus: true });'
cmp test/fixtures/shared_tree/schema-authoring.json tools/shared-tree-oracle/.output/schema-authoring/schema-authoring.json
```

Document these commands in the oracle README. Suggested commit:
`test(tree): compare authoring schemas with Fluid`.

### Task 6: Replace the item-counter blob and publish the authoring API

**Files:** Modify the example's three source modules, tests, and README; website
comparison data/tests and snippet configuration as needed; root README.
Create `docs/shared-tree-schema-authoring.md`.
**Consumes:** The completed descriptor/compiler API and its type guarantees.
**Produces:** A runnable migrated example and accurate source-backed
documentation without a hand-maintained schema blob or snapshot decoder.

- [ ] **1. Add schema identity and typed round-trip tests before migration.**

Preserve these existing observations:

```gleam
let assert Ok(compiled) = document_schema.definition()
builder.encode(compiled, [])
|> expect.to_equal(
  Ok(Some(types.ArrayValue("shared_tree_item_counter.StringArray", []))),
)
builder.decode(
  compiled,
  Some(types.ArrayValue("shared_tree_item_counter.StringArray", [
    types.StringValue("first"),
  ])),
)
|> expect.to_equal(Ok(["first"]))
```

The example suite uses gleeunit, not startest: express these assertions with
its existing `let assert` style when adding them. Compare its compiled stored
schema semantically against the old schema represented as test JSON data;
do not retain the old blob in production source.

```sh
cd examples/shared_tree_item_counter_lustre && gleam test
```

- [ ] **2. Replace the schema declaration and route decoding through it.**

Implement the design's `definition()` declaration. Prefer compiling once
during application initialization and retaining the `Compiled(List(String))`
in model/config state for create/open/decode. Store a structured error as a
failed application state if compilation or initial encoding fails; do not add
`let assert` to exported application schema functions.

Use `builder.stored`, `builder.view`, and `builder.encode` at the existing
create/open boundaries. Preserve the existing tree.create_dev authentication,
document ID/URL flow, open/read subscriptions, cleanup, busy handling, and
half-open removal range. Keep snapshots and explicit native edit submission.

Replace `counter.decode`'s shape matcher with delegation to
`builder.decode(compiled, Some(value))`. Its signature may accept the compiled
descriptor; update all callers and existing tests together. Preserve the
`Result(..., String)` application boundary with a named formatter that
retains the full `TreeError` information. Do not turn failed reads into zero.

- [ ] **3. Run the example's existing action and malformed-root tests.**

```sh
cd examples/shared_tree_item_counter_lustre && gleam test && pnpm run build
```

Expected: insertion at index zero, empty removal no-op, first-item removal,
and rejection of wrong/non-string roots all retain their existing behavior.

- [ ] **4. Update source-backed snippets and comparison copy.**

Keep `item-counter-watershed-definition` and
`item-counter-watershed-schema` marker references valid; combine or reposition
their ranges without nesting. Preserve explanatory comments comparing the
new declaration with `sf.array`, and preserve the other existing snippet IDs.
The source generator's orphan checks must still pass.

Replace the comparison's claim that serialized JSON is application setup
with a description of typed descriptors and checked snapshots. State that
native edits remain explicit; do not suggest that list snapshots are live
Fluid nodes. Keep attribution and upstream snapshot digests unchanged.

```sh
just snippets
cd website && node --strip-types --test src/data/sharedtree-item-counter.test.ts src/lib/snippet-manifest.test.ts
```

Add a targeted test that obtains the generated schema snippet and confirms
it includes the new declaration's source-backed range. Do not assert prose
wording or directly edit the generated manifest.

- [ ] **5. Write public usage documentation and validate the affected surfaces.**

The guide must show the item-counter declaration, a two-property record,
required/optional roots, absence versus explicit null, encode/decode error
handling, handle preservation, and create/open/read integration using existing
facade signatures. Include a Fluid-to-Gleam mapping table and the first
milestone's exclusions and eight-property limit. Explain constructor/getter
laws and the difference between typed snapshots and live node references.
Link it from the root README's SharedTree section and the example README.

```sh
gleam test --target erlang -- shared_tree
gleam test --target javascript -- shared_tree
just _test-compile-fail
(cd examples/shared_tree_item_counter_lustre && gleam test && pnpm run build)
(cd website && pnpm build)
```

Run the commands from the repository root. Report missing-tool or
dependency blockers accurately; do not label skipped upstream or browser
checks as verified. Suggested commit: `docs(tree): publish typed schema authoring`.

## Completion checklist

- [ ] Every supported descriptor has a positive typed use and value round trip.
- [ ] Both targets execute the schema and codec test matrices.
- [ ] Invalid declarations fail compilation to `Compiled(a)`, not by panic.
- [ ] Invalid snapshots return errors with useful paths and no defaults.
- [ ] Property, constructor, and root misuse produce the intended compiler errors.
- [ ] Pinned Fluid capture agrees with independently authored native declarations.
- [ ] Item-counter persisted identity, actions, errors, and lifecycle remain intact.
- [ ] No production schema blob or parallel item-counter snapshot decoder remains.
- [ ] Website snippets quote the compiled example and retain their source attribution.
- [ ] Existing low-level APIs and the accepted interoperability profile are unchanged.
- [ ] No deferred union, recursion, identifier-default, or live-node API slipped in.
