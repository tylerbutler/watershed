# Task 11 report: supported schema-evolution profile

## Status

Complete.

The permanent gates now define the supported M4 profile as strict-view object
and map schema evolution. The generated profile and manifest record the exact
scope, both native targets run all four schema-evolution corpus cases, the
coordinator requires every schema report section, and the public documentation
describes the API, concurrency behavior, and exclusions.

M4 is closed for this restricted profile. M3 remains incomplete.

## Breaker prerequisites

Task 10 ended with two load-bearing findings. Both were fixed before the support
claim was changed.

1. Native persisted history validation now parses the complete diagnostic
   constructor structure. It requires a recognized `SchemaChange` or
   `DataChange`, validates the schema arguments or inner data changeset, and
   rejects operation-shaped arbitrary text such as
   `DataChange(invented ...)`.
2. Both native scanners now interpret a quote with the previous escape state
   before calculating the next state. Valid escaped quotes no longer corrupt
   string or delimiter tracking.

Regression coverage:

- `native persisted history rejects invented data constructors`
- `native schema diagnostics allow escaped quotes`
- `native persisted history allows escaped quotes`
- `native named data diagnostics preserve complete operation validation`
- `native named outer changesets preserve complete operation validation`

The last two tests were added after the real service exposed the JavaScript
printer's named `data:` and outer `changes:` fields. Support for those observed
forms remains structural; it does not restore token-based acceptance.

## Permanent profile and gates

The generated profile names
`strict-view-object-map-schema-evolution` as the supported feature. It retains
explicit exclusions for:

- arrays and array schema evolution
- staged schema upgrades
- unknown-field view adapters
- data migrations
- public transactions
- additional upstream versions
- shared branches
- garbage-collection sweep
- compressed operations
- chunked operations

Permanent tests require all four schema-evolution cases in source coverage and
in both native semantic runner lists:

- `schema-compatible-object-upgrade`
- `schema-equivalent-object-upgrade`
- `schema-incompatible-object-upgrade`
- `schema-compatible-map-upgrade`

The existing coordinator already required and validates:

- `schemaCompatibility`
- `schemaRaces`
- `schemaReconnect`
- `schemaReloadMatrix`
- `schemaTailReloadMatrix`

No workflow selector changes were necessary. The existing SharedTree commands
already execute the expanded Node gates, source corpus, both native targets,
and real-service coordinator.

The `just lint` recipe did require a correction discovered during final
validation. Its root `gleam format --check` recursively traversed generated
dependency trees and did not terminate in a populated checkout. It now passes
every tracked `.gleam` file explicitly, which preserves workspace coverage and
excludes untracked build dependencies.

## Generated metadata

The profile was captured through a real pinned Floodgate preflight, copied to
the committed fixture, and used to regenerate the manifest.

- Profile SHA-256:
  `6410448d2e0abcb1dc905a67f6d6ad197003805e92151b9e9ff8795963229bf5`
- Fluid package: `@fluidframework/tree` 3.1.0
- Fluid source commit:
  `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960`
- Floodgate revision:
  `0eb493fc46d1bb9baf1151a6ccdde93544e057e7`
- `minVersionForCollab`: `2.117.0`
- Alias and layout: `root` to datastore `A`, bootstrap map `/A/root`,
  SharedTree `/A/_C`
- Message and EditManager codec: V7
- SharedTreeChange and ModularChange codec: V5
- Schema codec: V2

The Fluid and Floodgate pins, layout, codec versions, compressor format,
container metadata, and M1/M2 feature support did not change.

## Documentation

The root README and oracle README now document:

- `open_tree`
- compatibility inspection
- explicit schema upgrade
- strict `resolve_tree`
- equivalent upgrade no-op behavior
- rejection of invalid and outside-profile upgrades
- stale strict-handle invalidation
- schema notifications
- sequenced snapshot behavior
- initialized-document scope
- schema/data concurrency and losing upgrades
- application schema versions versus package versions
- local authoring restrictions separately from upstream `can_upgrade`

The compatibility claim excludes staged upgrades, unknown-field adapters,
arrays, migrations, public transactions, and additional upstream versions.
There was no website copy pass.

The parent roadmap links the schema-evolution design and plan, marks M4 complete
for the restricted profile, preserves the concurrent M3 notes, and does not
mark M3 complete.

## Real-service evidence

Successful run:

- Run ID: `1e8a12e0-4ff7-4dcb-b5f6-3acd03d0e34e`
- Report:
  `tools/shared-tree-oracle/.output/interop/1e8a12e0-4ff7-4dcb-b5f6-3acd03d0e34e/report.json`
- Profile digest:
  `6410448d2e0abcb1dc905a67f6d6ad197003805e92151b9e9ff8795963229bf5`
- Deterministic cases: 147
- Reconnect cases: 12
- Refusal cases: 24
- Compatibility rows: 3
- Schema race cells: 27
- Schema reconnect rows: 3
- Schema reload matrix: all nine writer-reader cells
- Schema tail reload matrix: all nine writer-reader cells
- Seeded schedules: 200 at seed 42
- JavaScript native corpus: 573
- Erlang native corpus: 584
- Skips: none
- Divergences: none

Two earlier real-service attempts correctly found missing native printer forms:

- `51469b08-b256-4d1c-ad1b-fe99f1d0feaa` rejected the named inner `data:`
  field.
- `407d4ada-ac4c-4b9e-9b0f-d4725e59b2d1` rejected the named outer `changes:`
  field.

Each failure received a failing regression before the parser was extended.

Floodgate emitted its expected Socket.IO transport-control decoder warnings.
They did not skip or weaken the gate.

## Acceptance evidence

- [x] **The source oracle covers the approved object/map schema profile.**
  The generated source inventory and permanent manifest gate require all four
  approved schema-evolution corpus IDs.
- [x] **`can_view`, `can_upgrade`, and `is_equivalent` match the pinned
  source.** Compatibility rows cover upstream, JavaScript, and BEAM against the
  generated pinned profile.
- [x] **Equivalent upgrades allocate nothing and submit/emit nothing.**
  Equivalent-upgrade unit and corpus cases assert the no-op result, unchanged
  revision state, no outbound operation, and no notification.
- [x] **Invalid and outside-profile local upgrades leave state unchanged.**
  Refusal tests and the 24 real-service refusal cases retain schema, forest,
  history, pending state, and notifications.
- [x] **Ordered schema/data changes survive codecs, history, and summaries.**
  Codec interoperability, native history validation, post-upgrade reload, and
  earlier-summary tail replay pass for both targets.
- [x] **Inverse schema changes remain internal and cannot be encoded.**
  Encoder refusal tests reject inverse schema changes while rollback tests
  exercise their internal application.
- [x] **Schema/data and schema/schema races match upstream in both orders.**
  The real-service report contains all 27 required race cells.
- [x] **Causal and common-prefix cases do not become false conflicts.**
  Causal upgrade-then-edit controls and common-prefix transformation tests pass.
- [x] **Muted commits retain identity through acknowledgement and reconnect.**
  Race and reconnect evidence binds original, accepted, and reconciled
  revisions and originators.
- [x] **Rollback preserves required detached content and node identity.**
  Native rollback tests and race artifacts retain detached content and stable
  identity evidence.
- [x] **Snapshots pair sequenced schema, forest, history, and compressor
  state.** Summary validators bind every component to the selected sequence
  and reject mixed or stale artifacts.
- [x] **Old strict handles cannot read or write after incompatible upgrades.**
  Handle invalidation tests reject both operations after the view becomes
  incompatible.
- [x] **View incompatibility does not stop an otherwise valid document.**
  Ordinary document state remains available while strict resolution refuses
  the incompatible view.
- [x] **JS and BEAM expose matching APIs and notification semantics.**
  Shared protocol, facade tests, native corpus cases, and real-service rows pass
  for both targets.
- [x] **A fresh compatible handle can continue editing after invalidation.**
  Reload and continuation tests resolve a new strict handle and observe its
  write.
- [x] **Both targets consume upstream schema operations and publish consumable
  output.** Dual-target corpus and real-service writer-reader matrices pass.
- [x] **All nine summary writer/reader combinations continue editing.**
  Both post-upgrade and earlier-summary matrices contain nine validated cells.
- [x] **Real-service reconnect and accepted-before-drop cases pass.**
  All three implementation rows contain both reconnect cases and exact
  one-to-one accepted operation mappings.
- [x] **Required gates fail on missing artifacts, targets, scenarios, or
  service.** Coordinator and artifact mutation tests cover each omission and
  mismatch class.
- [x] **Existing DDS behavior and M1/M2 interoperability remain intact.**
  SharedTree tests, codec interoperability, the full native corpus, and the
  complete deterministic and seeded suites pass.
- [x] **The supported profile names the M4 limits without claiming M3 or M5
  work.** The generated profile, both READMEs, and the parent roadmap state the
  restricted profile and explicit exclusions.

## Validation

Successful commands:

- `gleam format --check src test`
- `npm --prefix tools/shared-tree-oracle run generate`
- `npm --prefix tools/shared-tree-oracle run check`
- `npm --prefix tools/shared-tree-oracle test`: 247 passed
- `just shared-tree-test`: Erlang 601 passed, JavaScript 590 passed; storage,
  bootstrap, and creation smoke tests passed
- `just shared-tree-codec-interop`: two targets, 20 items each
- `just shared-tree-interop`: real-service run above
- `just build`
- `just lint`
- `WATERSHED_REQUIRE_BROWSER=1 node scripts/run-browser-tests.mjs` from
  `website/`
- `git diff --check`

`just test` was run twice and investigated:

1. The first run passed the Gleam, JavaScript, compile-fail, and other website
   suites, then timed out in
   `guide race styles reach dynamically created notes` while waiting for a
   transient flow marker. The complete required Chromium suite passed on an
   immediate direct rerun. Task 11 changed no website runtime or test file.
2. A later full rerun followed `just clean`, which removed every package build
   cache. Seven independent Lustre examples then failed concurrently while
   resolving dependencies because the Hex API rate limit was exceeded. The
   root Watershed suite passed 601 tests, `shared_tree_cli` passed 14,
   `watershed_lustre` passed 54, and the packages that resolved before the
   limit passed. This is a reproduced external package-registry failure, not a
   code or assertion failure.

The dedicated tests that cover every Task 11 change pass. The full repository
test command has no remaining branch-caused failure, but its last invocation
did not return success because of the external Hex rate limit.

## CI status

All evidence in this report is local. No hosted GitHub Actions workflow was run,
so this report does not claim a hosted CI pass.

## Concerns

The workspace formatter's old recursive behavior was sensitive to populated
dependency trees; the lint recipe now checks only tracked Gleam files.

The final `just test` retry was blocked by the Hex API rate limit after caches
were intentionally cleaned while investigating lint. Hosted CI still needs to
provide the independent release signal.
