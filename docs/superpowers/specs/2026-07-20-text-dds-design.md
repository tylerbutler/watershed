# Collaborative Text DDS Design

## Goal

Add a `SharedText` Watershed DDS for collaborative plain-text editing. The DDS
will use `lattice_text` so replicas can insert, delete ranges, replace ranges,
and append text optimistically and converge after sequencing. All indexes are
grapheme indexes, so emoji and combining sequences count as one unit.

## Prerequisite

This design builds on the collaborative sequence DDS plan
(`docs/superpowers/plans/2026-07-20-collaborative-sequence-dds.md`). It assumes
that plan is implemented first: the local `lattice_text` dependency is linked,
and the kernel, channel, wire, and runtime patterns it establishes exist.

## Scope

The first release includes:

- a `Text` kernel backed by `lattice_text/text`;
- channel, wire, summary, attach, and runtime integration;
- Erlang and JavaScript runtime APIs;
- insert, delete-range, replace-range, append, value, length, and substring
  operations;
- cursor anchors with JSON codecs;
- unit, convergence, wire, runtime, and model-based fuzz tests.

The first release excludes:

- rich-text formatting and attributes;
- `move` and single-grapheme `delete` operations;
- range-delta events;
- tombstone compaction (`compact` and `remove_forwardings`);
- `lattice_fugue` and `lattice_text_fugue`;
- compatibility with Fluid Framework's SharedString wire format;
- presence-based shared cursors. Anchors ship in this release; the presence
  wiring is a later phase.

## Architecture

### Text kernel

Add `src/watershed/text_kernel.gleam`. The kernel will host
`lattice_text/text.Text` and remain pure and runtime-independent.

The state will mirror the sequence kernel:

```text
TextState(
  replica_id,
  sequenced,
  optimistic,
  pending,
  next_pending_message_id,
)
```

- `sequenced` contains acknowledged local and remote deltas. Summaries persist
  this state.
- `optimistic` contains `sequenced` plus all pending local deltas. Reads use
  this state.
- `pending` is a FIFO list of local operations and message IDs.
- `next_pending_message_id` identifies local acknowledgements and rollbacks.

The kernel will call lattice's fallible API: `try_insert_with_delta`,
`try_delete_range_with_delta`, and `try_replace_range_with_delta`. Append uses
`append_with_delta`, which cannot fail.

### Operations

The kernel operation sum will contain:

```text
Insert(index, value, delta)
DeleteRange(start, end, delta)
ReplaceRange(start, end, value, delta)
Append(value, delta)
```

The index fields record user intent for diagnostics. The CRDT delta is
authoritative when another replica applies an operation. `lattice_text`
supports every operation natively, including atomic range deltas, so no
operation needs composition in Watershed.

Empty edits succeed without side effects. After validating indexes, an insert
or append of the empty string, a delete of an empty range, and a replacement
of an empty range with the empty string each return success without creating
a pending entry, emitting an event, or submitting a channel op.

### Events

The first event type will be:

```text
TextChanged(value: String)
```

Local and remote edits will emit this event only when the optimistic visible
string changes. A state-shaped event avoids reporting an author's stale index
as the final position after concurrent edits. Editors re-render or diff
locally.

### Errors

The kernel will distinguish invalid edit requests from consistency failures.

- An invalid insert index maps `sequence.InsertError` to
  `InsertOutOfBounds(index, length)`.
- An invalid delete or replace range maps `RangeOutOfBounds(start, end,
  length)` to `DeleteRangeOutOfBounds` or `ReplaceRangeOutOfBounds`.
- A malformed remote delta fails stage-two wire decoding and becomes
  `BadOpContents` before kernel dispatch.
- An acknowledgement that does not match the oldest pending entry becomes
  `UnexpectedAck`.
- A rollback that does not match the newest pending entry becomes an explicit
  rollback error.

Runtime facades will preserve these failures through their existing error
conventions. The implementation will not panic on caller-provided indexes or
silently ignore malformed operations.

## Channel Integration

Add Text variants to the closed channel sums:

- `TextChannel`;
- `InitText`;
- `TextState`;
- `TextOp`;
- `TextEvent`;
- `TextSummary`;
- `TextMeta`.

Extend all channel dispatch functions, including creation, type conversion,
summary creation and loading, attach handling, remote application,
acknowledgement, rollback, stash replay, local metadata, pending inspection,
and cache checks.

Text holds only graphemes, never DDS handles, so `handle_addresses` returns
the empty list.

Detached attach will carry the optimistic text state. After the attach
operation is created, the kernel will promote that state to sequenced state
and clear pending operations, matching the attach behavior of the existing
optimistic lattice kernels.

## Runtime API

The runtime core and both target-specific facades will expose equivalent
operations:

```text
create_text
resolve_text
text_handle_of
text_insert
text_delete_range
text_replace_range
text_append
text_value
text_length
text_substring
text_anchor_at
text_resolve_anchor
text_start_anchor
text_end_anchor
anchor_to_json
anchor_from_json
```

Mutation functions on both facades will return `Result(Nil, String)` so invalid
indexes reach callers without panics. `text_value` and `text_length` will
return the optimistic string and grapheme count. `text_substring` will return
`Result(String, String)` because its range can be invalid.

Edits will route through a `TextOpFailed(address, detail)` core error and
result-returning runtime paths, matching the sequence plan's
`edit_sequence_with_result` helpers. Edits will never route through the
panicking `edit` path.

The channel will use the runtime's existing replica identity when it creates a
new text or loads one from a summary. Loading will merge the stored state into
a fresh text branded with the joining replica's ID so future deltas use the
correct author.

The schema module will add a `TextChannel` phantom kind with typed field
support.

### Anchors

Anchors are pure reads over the kernel's optimistic state. They create no
channel ops and change no summary format. The kernel exposes anchor functions
over its optimistic text; the runtime core and facades delegate to them.

- `text_anchor_at(index, bias)` wraps `try_anchor_at` and returns an opaque
  `TextAnchor`. The bias argument mirrors lattice's `Bias` sum: `Before`
  attaches the anchor to the following grapheme and `After` attaches it to the
  preceding one. The facades re-export these two constructors.
- `text_resolve_anchor(anchor)` wraps `try_resolve_anchor` and returns the
  current grapheme index.
- `text_start_anchor` and `text_end_anchor` return the document boundary
  anchors.
- `anchor_to_json` and `anchor_from_json` let anchors travel between replicas,
  for example through presence for shared cursors.

An out-of-bounds anchor index returns an explicit error. A stale anchor —
lattice's `UnknownAnchorTarget` — returns an error telling the caller to
re-anchor.

## Wire and Summary Format

Add the channel type string `"text"` and op codecs in `watershed/wire/ops`.
Each op will carry:

- an operation tag: `textInsert`, `textDeleteRange`, `textReplaceRange`, or
  `textAppend`;
- diagnostic intent fields such as indexes and inserted strings;
- the encoded CRDT delta.

The delta will use `text.to_json`, convert that JSON value to a string, and
place the string in the op. Decoding will pass the string to `text.from_json`.
This matches the existing lattice-backed wire convention.

Text summaries will use the same lattice envelope and encode the sequenced
state. The format remains Watershed-specific; it does not claim Fluid
SharedString compatibility.

## State Transitions

### Local edit

1. Validate the operation against the optimistic text.
2. Produce the updated optimistic text and sparse delta.
3. Append one pending entry with a local message ID.
4. Emit `TextChanged` if the visible string changed.
5. Submit one channel op.

### Local acknowledgement

1. Match the sequenced op and message ID against the oldest pending entry.
2. Merge the delta into `sequenced`.
3. Remove the pending entry.
4. Keep `optimistic` unchanged because it already contains the delta.

### Remote operation

1. Merge the remote delta into `sequenced`.
2. Rebuild `optimistic` by replaying pending deltas over the new sequenced
   base.
3. Emit `TextChanged` only if the visible optimistic string changed.

### Rollback

1. Match the rejected op and message ID against the newest pending entry.
2. Remove that entry.
3. Rebuild `optimistic` from `sequenced` plus the remaining pending deltas.
4. Emit `TextChanged` if rollback changed the visible string.

## Testing

### Kernel tests

Cover:

- insert, delete-range, replace-range, and append;
- multi-grapheme content: emoji, combining sequences, and mixed scripts;
- optimistic and sequenced reads, including substring;
- invalid indexes and ranges;
- FIFO acknowledgement and LIFO rollback;
- duplicate or subsumed remote deltas;
- stash replay;
- attach promotion;
- summary reload with a new replica ID;
- optimistic-cache coherence;
- anchor creation, resolution, boundary anchors, JSON round-trips, stability
  across concurrent edits, and stale-anchor errors.

### Convergence tests

Use at least two replicas and cover:

- concurrent inserts at the same index;
- overlapping delete-range and replace-range;
- append concurrent with insert;
- different operation delivery orders;
- repeated delivery of the same delta.

All replicas must produce the same visible string after they receive the same
operation set.

### Integration tests

Add:

- wire round-trip and malformed-delta tests;
- channel attach and summary tests;
- runtime-core mutation and read tests;
- Erlang and JavaScript facade tests, including Sluice end-to-end convergence.

### Model-based fuzzing

Extend the fuzz harness with a text model. Generate only model-valid indexes
and ranges over a grapheme-heavy alphabet that includes emoji and combining
sequences. Exercise local edits, sequencing, duplicate delivery, rollback,
reconnect and stash replay, and summary reload.

The harness will assert:

- all connected clients converge;
- each client's optimistic string matches its model;
- each kernel's optimistic cache equals sequenced state plus pending deltas.

## Future Work

Later phases can add presence-based shared cursors built on anchor JSON
codecs, rich-text attributes, range-delta events for large-document editors,
and tombstone compaction with forwarding-map retention.
