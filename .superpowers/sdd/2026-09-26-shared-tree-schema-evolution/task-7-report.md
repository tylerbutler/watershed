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

## Fix round 2

### Result

Sequenced decoding now reads the message revision before selecting schema
context. Remote messages still reconstruct context from their reference point
and retained peer branch. Local acknowledgments instead reconstruct the local
authored branch up to, but not including, the acknowledged revision. This
preserves an acknowledged schema upgrade for a later same-reference data
acknowledgment that uses a newly introduced node type.

Schema reconstruction now applies each revision once while retaining every
sequenced occurrence. A replayed duplicate schema commit can therefore keep
its later sequence point without rewinding or advancing the same semantic
transition twice. The same rule is used by runtime authoring context and
summary history encoding and decoding.

The history fixture now stores the encoded summary entry and restores it
through `summary.decode`, `tree_summary.from_wire`, and `runtime.restore`.
Tail replay decodes the captured message bytes before delivery to the restored
tree. Historical decoded changes are compared as canonical semantic change
types and payload values. Summary comparison now retains canonical schema and
EditManager history instead of reducing the summary to its entry type.

### RED

- `shared_tree_bridge_decodes_after_duplicate_schema_replay_test` failed with
  `schema history does not reach the sequenced schema`.
- `shared_tree_bridge_decodes_local_data_ack_after_same_reference_upgrade_test`
  failed while decoding data that used the new `Extra` node type.
- Routing every fixture delivery through the wire path exposed that ordinary
  concurrent schema scenarios encode queued commits from later optimistic
  state. The final fixture change confines mandatory wire decode to the
  requested restored-summary tail path while preserving existing semantic
  scheduling elsewhere.

### GREEN

- Erlang focused codec, summary, history, and runtime tests: 107 passed.
- JavaScript focused codec, summary, history, and runtime tests: 107 passed.
- Focused codec and summary interop tests: 23 passed.
- Native summary artifact interop: four scenarios per target loaded; six
  retained-history continuation checks passed.
- `just shared-tree-codec-interop`: two targets, 20 items each passed pinned
  upstream consumption.
- `git diff --check` and direct `gleam format --check` passed.
- The full oracle test command passed 216 of 217 tests. Its unrelated
  missing-executable assertion received `EACCES` instead of the expected
  `ENOENT` in this environment.

### Files

- `src/watershed/tree/codec.gleam`
- `src/watershed/tree/codec/summary.gleam`
- `src/watershed/tree/history.gleam`
- `src/watershed/tree/runtime.gleam`
- `src/watershed/tree_kernel.gleam`
- `test/watershed/shared_tree_channel_test.gleam`
- `test/watershed/tree/schema_evolution_fixture.gleam`

### Self-review

The duplicate handling changes only schema-context traversal; trunk entries and
their sequence points remain intact for replay and retention. Local context
uses original authored pending commits and stops before the target revision,
while remote context continues to use peer/reference reconstruction. The
runtime first performs context-free structural decoding, then performs the
schema-aware decode against the reconstructed authoring schema. The fixture
keeps native and upstream field-batch representation differences out of the
comparison but retains semantic change kinds, payload values, summary schema,
history, roots, and mutation-sensitive bytes.

### Concerns

Sequenced messages are structurally decoded before their schema-aware decode,
so this path performs two pure codec passes. This avoids guessing a final
schema from optimistic receiver state and does not change the wire format.
The full oracle suite still has the environment-specific `EACCES` versus
`ENOENT` assertion described above; the focused interop suites and required
codec gate pass.

## Fix round 3

### Result

Historical-decode comparison now projects the decoded native changes back
through the production wire encoder and compares the complete canonical wire
change. The projection retains data values, revision and local identities,
field positions, builds, destroys, nested node types, field names, and list
order. Self-describing field batches are decoded to canonical tree values so
native and upstream shape tables can differ without hiding semantic changes.

Summary-tail replay now parses each captured `_tailBytes` envelope and sends
its exact `contents`, reference sequence number, sequence number, minimum
sequence number, and batch index through production decode and receive paths
for every active client. It does not regenerate bytes from queued semantic
commits. Tail-byte mutation changes the continuation, and corrupt bytes fail.

Pending local operations now retain their original authored commit context
separately from the rebased pending branch. A local schema acknowledgment can
therefore reconcile as a muted change after a concurrent winner, while the
next same-reference data acknowledgment still decodes with the original
`Extra` schema. Remote messages continue to use peer/reference reconstruction.

### RED

- The semantic projection treated changes with different numeric values and
  local identities as equal.
- Replacing captured tail content did not affect continuation because replay
  regenerated wire bytes from semantic commits, and corrupt captured bytes
  were not consumed.
- After the concurrent schema winner, decoding the same-reference local data
  acknowledgment failed at `message.changeset[0].data.builds.trees` with
  `unknown node schema: Extra`.
- The concurrent schema acknowledgment regression initially could not reach
  reconciliation until its rollback identities were allocated from a
  disjoint, prefinalized session range.

### GREEN

- `gleam test --target erlang -- shared_tree_codec shared_tree_summary shared_tree_history shared_tree_channel`:
  112 passed.
- `gleam test --target javascript -- shared_tree_codec shared_tree_summary shared_tree_history shared_tree_channel`:
  112 passed.
- `node --test tools/shared-tree-oracle/codec-interop.test.mjs tools/shared-tree-oracle/summary-interop.test.mjs`:
  23 passed.
- `npm --prefix tools/shared-tree-oracle run summary:interop`: four scenarios
  per target loaded; six retained-history continuation checks passed.
- `just shared-tree-codec-interop`: two targets, 20 items each passed pinned
  upstream consumption.
- `git diff --check` and direct Gleam formatting checks passed.

### Files

- `src/watershed/tree/history.gleam`
- `test/watershed/shared_tree_channel_test.gleam`
- `test/watershed/shared_tree_history_test.gleam`
- `test/watershed/tree/schema_evolution_fixture.gleam`

### Self-review

The authored context exists only while local commits are pending. It starts
from the exact trunk visible when the pending run begins and appends each
original acknowledged commit, while `local_base` continues to track the
rebased branch used for reconciliation. Snapshots still reject pending state,
so this transient context does not add a summary format.

Historical comparison derives native semantics from the decoded change rather
than from the original bytes. Captured bytes remain a separate observation and
are the only input to restored-tail delivery. Duplicate sequence points stay
in history, while the existing revision deduplication prevents repeated schema
application.

### Concerns

Canonical comparison intentionally normalizes FieldBatch shape-table encoding
to nested tree values. It preserves semantic values, types, identities,
positions, builds, destroys, and structure, but does not require byte-identical
shape-table layouts between native and upstream implementations.

## Fix round 4

### Result

Canonical history projection now treats JSON strings as leaf values. It parses
only known encoded message containers, then normalizes actual FieldBatch v2
objects identified by their `version`, `identifiers`, `shapes`, and `data`
members. The projection still canonicalizes shape-table layouts, object member
order, identities, positions, fields, builds, destroys, metadata, and outer
change order, but strings such as `{"a":1,"b":2}` and
`{ "b":2, "a":1 }` remain distinct.

Pending local runs now retain the exact schema that was visible before their
first authored commit. Acknowledged commits from the same run remain as the
ordered authored prefix, while the rebased pending branch and `local_base`
continue to track reconciliation separately. Own-ack decoding starts from the
immutable schema plus that authored prefix, so minimum-sequence trimming cannot
change its context. Restored snapshots start without pending state and capture
a new immutable context when the next local run begins, so the summary format
does not change.

### RED

- `gleam test --target erlang -- shared_tree_history shared_tree_channel`
  ran 66 tests and failed the three new regressions.
- Both trim regressions failed with
  `schema change does not match its authoring context`.
- The projection regression showed that the two differently formatted,
  differently ordered JSON-looking string leaves compared equal.

### GREEN

- Erlang focused history, channel/runtime, codec, and summary tests: 214 passed.
- JavaScript focused history, channel/runtime, codec, and summary tests:
  203 passed.
- Focused codec and summary interop tests: 23 passed.
- Native summary artifact interop: four scenarios per target loaded; six
  retained-history continuation checks passed.
- `just shared-tree-codec-interop`: two targets, 20 items each passed pinned
  upstream consumption.
- `gleam format --check` for all changed Gleam files and `git diff --check`
  passed.

### Files

- `src/watershed/tree/history.gleam`
- `src/watershed/tree_kernel.gleam`
- `test/watershed/shared_tree_channel_test.gleam`
- `test/watershed/shared_tree_history_test.gleam`
- `test/watershed/tree/schema_evolution_fixture.gleam`

### Self-review

Wire normalization no longer has a generic string-to-JSON path. Encoded
message strings are parsed only at named observation fields, and FieldBatch
normalization requires the complete v2 container shape before decoding it.
This prevents ordinary leaf names or values from entering the structural
normalizer.

The immutable local schema is set only when the first pending commit is
authored, survives remote rebases and history trimming, and clears when the
pending run ends. Historical local revisions that are no longer pending still
use retained-history reconstruction. Rebinding now also covers the retained
authored prefix.

### Concerns

Pending commits are intentionally excluded from snapshots, so their immutable
authoring schema is not serialized. A restored tree has no pending run and
captures a fresh context on its next local edit. If pending operations are ever
added to the summary contract, that contract must serialize the matching
authoring schema at the same time.
