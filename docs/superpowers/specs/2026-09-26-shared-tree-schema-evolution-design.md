# SharedTree schema evolution

**Date:** 2026-09-26
**Status:** Scope and architecture approved in conversation. Written design and
implementation plan require review before execution.
**Parent:** [Native SharedTree interoperability](2026-09-21-shared-tree-design.md),
M4 in section 8.

## 1. Scope and decisions

Implement schema evolution for the existing object and dynamic-map profiles.
M1 and M2 provide the execution baseline. M3 arrays are a parallel workstream,
not a prerequisite. Coordinate the common schema, changeset, codec, and runtime
interfaces with M3 before either workstream changes them.

The user approved:

- Explicit additive object/map upgrades and stored/view compatibility inspection.
- An ordered schema/data changeset layer above the existing modular data algebra.
- The pinned upstream behavior for concurrent schema/data changes.
- A schema-status notification separate from `TreeChanged(local)`.
- Old strict views becoming unavailable without stopping a valid document.
- Deferring arrays, staged upgrades, unknown-field view adapters, data migrations,
  and public transactions.

Keep the existing strict view configuration. Do not add
`allowUnknownOptionalFields`, staged allowed types, staged optional fields,
schema adapters, generated bindings, or a migration language in this milestone.

"Mixed-version clients" means different application schema versions using the
same pinned Fluid protocol. M4 does not expand the supported npm-version range.
A valid old client may lose access after an upgrade. Success does not require
every old view to keep writing.

### Global constraints

- Production SharedTree semantics must run in pure Gleam on JavaScript and BEAM.
- Upstream TypeScript packages are development/test dependencies, not a production tree engine.
- Use `@fluidframework/tree` version `3.1.0`.
- Use Fluid Framework commit `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960` (`client_v3.1.0`).
- Use Floodgate commit `0eb493fc46d1bb9baf1151a6ccdde93544e057e7`.
- Keep `minVersionForCollab` at `2.117.0`.
- Keep Message V7, SharedTreeChange V5, ModularChange V5, and Schema V2.
- Keep the fixed layout: root alias `root` -> `A`, map `/A/root`, tree `/A/_C`.
- Preserve existing DDS behavior and the M1/M2 interoperability cases.
- Reject unsupported semantic formats and operations; do not approximate their meaning.
- Existing Watershed document encodings require no backward compatibility or migration.
- Keep `TreeChanged(local)` as the data-change notification.
- Apply ASD-STE100 to Gleam comments and error strings, not to Markdown prose.
- Do not edit apm-managed files, `.code-map/`, or generated website snippets.

## 2. Upstream contract

Planning used the installed package source and the verified source checkout.
`npm --prefix tools/shared-tree-oracle run source:verify` confirmed the package
versions and source commit. The package copies of the change family,
change codec, compatibility checker, and schema comparison code matched the
reference checkout.

Paths below are relative to
`tools/shared-tree-oracle/.reference/FluidFramework/packages/dds/tree/src/`.

| Source | Required behavior |
| --- | --- |
| `shared-tree/sharedTreeChangeFamily.ts` | Compose adjacent data runs, retain intervening schema changes, reverse inner-change order on inversion, and treat schema-bearing rebases as conflicts. |
| `shared-tree/sharedTreeChangeCodecs.ts` | While encoding, change the schema context after each schema subchange. Preserve the ordered list. |
| `feature-libraries/schema-edits/schemaChangeCodecs.ts` | Encode `{old,new}`. Decode with `isInverse = false`. Reject encoding an inverse schema change. |
| `simple-tree/api/schemaCompatibilityTester.ts` | `canView`, `canUpgrade`, and `isEquivalent` are distinct properties. |
| `simple-tree/api/discrepancies.ts` | Ordinary, non-staged views compare allowed types and field kinds exactly. A view with an added optional field still needs an upgrade. |
| `feature-libraries/modular-schema/comparison.ts` | Check a proposed superset against all stored definitions, including definitions needed by detached content. |
| `feature-libraries/modular-schema/isNeverTree.ts` | Account for impossible required fields and recursive definitions without infinite recursion. |
| `feature-libraries/optional-field/optionalField.ts` | Required-to-optional is a permitted monotonic field-kind change. |
| `shared-tree/schematizingTreeView.ts` | Equivalent upgrades do not submit changes. Recompute compatibility when stored schema changes. |
| `shared-tree/treeCheckout.ts` | Apply schema/data subchanges in order; inverse schema changes can restore a narrower schema during reconciliation. |
| `test/shared-tree/sharedTreeChangeFamily.spec.ts` | Empty outer changes and schema conflicts have specific algebraic behavior. |

### Concurrency is a conflict, not a schema merge

When both outer changes are nonempty, rebasing either a schema-bearing change
over another change, or another change over a schema-bearing change, produces
an empty outer changeset. This includes additive changes and schema/schema
races. An empty outer change is not the same value as one empty modular data
change.

Preserve the existing history's common-prefix optimization. Causally ordered
changes must not become conflicts merely because retained history contains a
schema change. Keep muted commits and their identities until normal
acknowledgement and collaboration-window processing permit removal.

Do not retry or union a losing upgrade automatically. The application can
inspect current compatibility and request another upgrade from the new base.

## 3. Supported upgrades and compatibility

Support these schema transitions while preserving identifiers and existing
node kinds:

| Transition | M4 behavior |
| --- | --- |
| Add an optional object field | Explicit upgrade; existing content remains unchanged. |
| Widen allowed types for an existing object field | Explicit upgrade; write new types only after the local upgrade applies. |
| Widen allowed types for dynamic-map entries | Explicit upgrade; retain the existing per-key data algebra. |
| Change an object field or root from required to optional | Explicit upgrade; clearing becomes available under the upgraded view. |
| Widen root allowed types | Explicit upgrade; the current root stays unchanged. |
| Add definitions required by those transitions | Preserve the definitions in schema operations and summaries. |
| Equivalent schema, reordered declarations, or metadata-only difference | Preserve upstream no-op upgrade behavior. |
| Narrow types, add a required field to an existing object, or optional-to-required | Refuse the local upgrade without allocating or submitting a commit. |

Compatibility comparison must follow the upstream relation, including unused
definitions and impossible recursive types. The profile's authoring limits are
a separate check. For example, upstream's repository-superset relation can
accept an object-to-map transformation, but M4 does not author or apply that
transformation. Report `UnsupportedFeature` rather than treating it as an
implemented operation. Document that `can_upgrade` describes the upstream
schema relation and does not override the declared profile.

Keep `can_view(stored, view)` as the existing strict convenience check. Add
a status query returning `can_view`, `can_upgrade`, and `is_equivalent`.
An initialized M4 document does not need a new `can_initialize` public API.
Preserve the empty schema representation in retained initialization history.
Do not broaden native creation or initialization.

## 4. Architecture

### Shared changes and history

Add one pure `tree/shared_change.gleam` module above `tree/change.gleam`.
The latter remains the modular data algebra. The new module owns ordered
schema/data subchanges, composition, inversion, rebase, revision traversal, and
ordered application effects.

Move semantic schema-state and inner-change types out of `tree/codec.gleam`.
Codecs depend on the semantic types, not the reverse. Change `history.Commit`
to carry the outer changeset. Use that same type for trunk, pending, peer,
rollback, receipt, and resubmission state.

History must return ordered schema/data effects instead of squeezing a
reconciliation into one forest delta. Keep revision allocation and identity
ordering in their existing document-compressor paths.

### Forest and kernel

Keep visible and sequenced schema state separate, just as the kernel already
keeps visible and sequenced forests separate. An optimistic upgrade changes
the visible schema. A snapshot uses the sequenced schema and sequenced forest.

Replace the forest's schema without exporting and reimporting the forest.
Preserve node references, detached identities, and allocation counters.
During reconciliation, apply effects to a candidate state in order and expose
only the completed state.

Rollback can leave repair content whose types are absent from the restored
active schema. Separate attached-content validation from retained-content
validation. Preserve structural checks and the historical schema context
needed to classify retained object/map content; do not discard repair content
or require it all to match the current application view. The source oracle
must cover this case before the forest changes.

### View lifecycle and public API

Treat the application view as immutable handle state. Add the view to both
facades' opaque `SharedTree` records. Do not make one handle's view schema
the channel's global stored schema.

Retain `resolve_tree(document, handle, view)` as the strict convenience API.
Add `open_tree(document, handle, view)` to obtain a handle for compatibility
inspection and explicit upgrade even when the view cannot yet read data.

Add:

```gleam
tree_compatibility(tree: SharedTree)
  -> Result(tree_schema.Compatibility, String)

tree_upgrade_schema(tree: SharedTree) -> Result(Nil, String)
```

Existing reads and writes check the handle's view against the current visible
stored schema on each call. Do not rely on the check performed when the handle
opened. A stale handle returns a compatibility error. It can still query
compatibility and receive schema notifications.

The protocol state can load and receive a supported schema without a matching
application view. Keep unsupported schema encodings and corrupt messages fatal
at the document boundary. Application-view incompatibility alone is not
semantic corruption.

### Events and errors

Add `SchemaChanged(local: Bool)` to `tree_kernel.TreeEvent`. Emit it after a
completed transition changes the visible schema, including rollback. Preserve
`TreeChanged(local)` for visible data changes. If a completed transition changes
both, deliver the schema notification first, then the data notification.
Callbacks must see the final state. Do not expose temporary schema changes
inside one reconciliation.

Equivalent upgrade requests emit no events or outbound messages and consume no
IDs. Other invalid local requests return typed errors through the existing
facade string-error adapters without changing core state.

### Wire, summaries, and reconnect

Retain schema entries in native history. The current raw retained-wire copy
cannot substitute for semantic history after rebase.

Encode each data run under its applicable schema context. Keep inverse schema
changes internal. For retained peer branches, derive the branch's schema
context from its base and ordered changes, not from the summary's final schema.

Replay pending upgrades and data in order during reconnect. Retain no-op
conflict commits for deduplication and acknowledgement. Capture summaries from
sequenced state even while an upgrade is pending.

## 5. Alternatives rejected

A schema-message special case in the runtime would leave the data-only edit
manager unable to roll back or rebase schema changes. It would also lose
historical schema meaning when loading summaries.

A new schema-aware runtime or generic pluggable change-family framework would
duplicate routing, compressor, persistence, and reconnection work. Use the
existing runtime and one concrete outer change module.

Automatic schema union, automatic retries, and transactions that guarantee an
upgrade wins against concurrent edits would disagree with the pinned source.

## 6. Acceptance

Require evidence for compatibility flags, local upgrade/no-op/refusal behavior,
outer algebra, schema/data races in both sequencing orders, schema/schema races,
causal upgrade-then-edit, pending rollback, old-view invalidation, and recovery
with a new view.

Cover both native targets, upstream/native message consumption, real-service
mixed clients, reconnect before acknowledgement, accepted-before-disconnect
deduplication, and all nine summary writer/reader combinations. Compare schema,
visible data, pending revisions, retained identities, and native notifications
at intermediate checkpoints.

Do not claim M4 complete from convergence alone, self-round-trips, a feature
label, or a skipped service test. Require the companion plan's source-contract
review before native implementation and its final acceptance checklist before
closing the milestone.
