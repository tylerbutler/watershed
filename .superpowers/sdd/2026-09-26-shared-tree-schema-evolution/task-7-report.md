# Task 7 report: preserved schema context

## Result

SharedTree message and summary codecs now carry schema context through ordered
outer changes. Data runs use the schema active at their authoring point.
Schema changes advance that context for later data in the same commit. The
normal encoder rejects inverse schema changes without adding a new wire field.

Summary history now rewinds from the summarized schema to the initial retained
schema, decodes trunk commits forward, and starts each peer branch from its base
revision. Initialization history can therefore move from `EmptySchema` to a
fixed schema before decoding later data. Duplicate retained revisions use the
latest trunk occurrence, matching history reconciliation.

## Retained history and replay

Summary export now writes the current semantic outer history payload instead
of patching one modular change into retained wire data. It keeps retained custom
metadata, but retained content cannot override a rebased semantic change.

Restored history receipts now retain the original semantic commit. A later
duplicate can authenticate its contents after summary restore and append its
new sequence point without applying the change twice.

The schema-evolution history corpus now compares its full observation shape.
The previous exclusions for accepted messages, replay, continuation, and
historical decode are removed.

## Interoperability

The codec producer emits a distinct native `summary-schema-initial` artifact.
The pinned upstream consumer loads it, observes its retained history, and
continues editing it for both Erlang and JavaScript outputs.

The summary artifact coordinator also requires schema context in every native
summary. It accepts either the current Schema index or retained schema changes
in EditManager history and fails closed when both are absent.

## Verification

- Erlang focused codec and summary tests: 49 passed.
- JavaScript focused codec and summary tests: 49 passed.
- Erlang schema-evolution history tests: 41 passed.
- Codec and summary interop coordinator tests: 23 passed.
- Native summary artifact interop: four scenarios per target loaded; six
  retained-history continuation checks passed.
- `just shared-tree-codec-interop`: two targets, 18 items each passed upstream
  consumption.
- `git diff --check`: passed.

## Concerns

Restored receipts retain semantic commit content, but summaries still do not
retain the original transport reference and minimum sequence numbers. A replay
at a later sequence point can authenticate its contents; transport-field
authentication that requires those omitted fields remains unavailable.

## Fix round 1

### Result

Sequenced runtime messages now decode against the sender's schema at the
message reference point. The runtime reads the envelope originator first, then
reconstructs the authoring context from sequenced trunk history and the
sender's retained peer branch. A losing peer data change that uses a type
absent from the receiver's optimistic schema therefore reaches reconciliation
and is muted instead of failing during decode.

Restored receipts now recover the original authored commit from retained peer
history when the sequenced trunk contains its rebased form. This keeps receipt
authentication separate from trunk storage: the trunk remains empty for a
losing schema change, while a duplicate of the original authored commit still
authenticates after restore.

The schema-evolution fixture now executes native accepted-message capture,
reconnect replay, summary loading, tail replay, continuation, and historical
decode operations. It no longer substitutes the oracle's captured
`acceptedMessage`, `replay`, `continuation`, or `historicalDecode` values.
Mutation tests prove that changing the native tail or historical message
changes the reported observation.

The codec exporter now emits two additional native summaries:
`summary-schema-peer-before-upgrade` retains a peer branch authored before an
upgrade, and `summary-schema-upgrade-tail` retains two additive optional-field
schema eras. The pinned upstream consumer loads and continues editing both
artifacts for Erlang and JavaScript output. No wire or layout version changed,
and production changes remain pure Gleam.

### RED

- The losing-peer runtime regression failed because inbound decoding used the
  receiver's optimistic stored schema instead of the sender/reference history
  context.
- The restored muted-schema replay regression failed because the receipt held
  the empty rebased trunk commit rather than the original authored commit.
- Tail and historical-decode mutation tests initially produced unchanged
  output because the fixture copied those observations from the oracle.
- The first expanded codec interop run rejected the new summary artifact's
  resumed compressor session; the next run exposed an incompatible
  optional-root artifact. The final artifacts use a fresh consumer session and
  model the requested additive optional fields.

### GREEN

- `gleam test --target erlang -- shared_tree_codec shared_tree_summary shared_tree_history`:
  93 passed.
- `gleam test --target javascript -- shared_tree_codec shared_tree_summary shared_tree_history`:
  93 passed.
- `npm --prefix tools/shared-tree-oracle test`: 217 passed.
- `npm --prefix tools/shared-tree-oracle run summary:interop`: four scenarios
  per target and six retained-history continuation checks passed.
- `just shared-tree-codec-interop`: two targets, 20 items each passed pinned
  upstream consumption.
- Direct `gleam format --check` for every changed Gleam file, direct Prettier
  checks for both changed oracle files, `gleam build --target erlang`,
  `gleam build --target javascript`, and `git diff --check` passed.
- `just lint` was attempted twice, but Trellis stalled after starting its two
  `gleam format --check` jobs. The equivalent direct checks above completed.

### Files

- `src/watershed/runtime_core.gleam`
- `src/watershed/tree/codec.gleam`
- `src/watershed/tree/history.gleam`
- `src/watershed/tree/runtime.gleam`
- `src/watershed/tree/summary.gleam`
- `src/watershed/tree_kernel.gleam`
- `test/watershed/shared_tree_channel_test.gleam`
- `test/watershed/shared_tree_history_test.gleam`
- `test/watershed/tree/codec_export.gleam`
- `test/watershed/tree/schema_evolution_fixture.gleam`
- `tools/shared-tree-oracle/codec-interop.mjs`
- `tools/shared-tree-oracle/upstream-codecs.spec.ts`

### Self-review

The sequenced decoder is confined to inbound sequenced processing; local echo
and pending-submission decoding keep their existing behavior. Schema
reconstruction validates every old/new transition while rewinding and
advancing history. Receipt recovery matches by revision only within retained
peer commits and falls back to the rebased trunk commit when authored content
is unavailable. The final diff contains no generated manifest, debug output,
wire-version change, or broad formatting churn.

### Concerns

The fixture canonicalizes semantically equivalent native and upstream
field-batch shapes before comparison because their shape tables can differ.
The mutation tests and native load/replay paths guard against this becoming
captured-value substitution. Summaries also still omit original transport
reference and minimum sequence numbers, so restored authentication covers
semantic commit content rather than unavailable transport metadata.
