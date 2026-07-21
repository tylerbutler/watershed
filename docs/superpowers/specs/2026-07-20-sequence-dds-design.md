# Collaborative Sequence DDS Design

## Goal

Add an Array-like Watershed DDS for collaborative editing of ordered JSON
values. The DDS will use `lattice_sequence` so replicas can insert, delete,
move, and replace values optimistically and converge after sequencing.

This work also prepares the dependency graph for a later grapheme-aware text
DDS built with `lattice_text`.

## Scope

The first release includes:

- local filesystem dependencies for `lattice_core`, `lattice_sequence`,
  `lattice_text_core`, and `lattice_text`;
- a `Sequence<Json>` kernel;
- channel, wire, summary, attach, and runtime integration;
- Erlang and JavaScript runtime APIs;
- insert, delete, move, replace, values, and length operations;
- unit, convergence, wire, runtime, and model-based fuzz tests.

The first release excludes:

- `lattice_fugue` and `lattice_text_fugue`;
- a text-specific public API;
- cursor anchors;
- tombstone compaction and forwarding-map retention;
- compatibility with Fluid Framework's SharedSequence wire format.

## Dependency Wiring

Watershed will use these local dependencies:

```toml
lattice_core = { path = "../lattice/packages/lattice_core" }
lattice_sequence = { path = "../lattice/packages/lattice_sequence" }
lattice_text_core = { path = "../lattice/packages/lattice_text_core" }
lattice_text = { path = "../lattice/packages/lattice_text" }
```

The existing `lattice_counters`, `lattice_maps`, `lattice_registers`, and
`lattice_sets` dependencies will remain Hex dependencies. `lattice_core` must
use the local source because the local sequence and text packages declare
local path dependencies on it. Using Hex and path sources for the same package
name would create an inconsistent dependency graph.

The implementation will regenerate `manifest.toml` through Gleam's package
manager rather than editing the generated manifest by hand.

## Architecture

### Sequence kernel

Add `src/watershed/sequence_kernel.gleam`. The kernel will host
`lattice_sequence/sequence.Sequence(Json)` and remain pure and
runtime-independent.

The state will follow the existing lattice-backed kernels:

```text
SequenceState(
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

The kernel will expose fallible mutation functions. It will call
`try_insert_with_delta`, `try_delete_with_delta`, and `try_move_with_delta`
instead of lattice's asserting convenience functions.

### Operations

The kernel operation sum will contain:

```text
Insert(index, value, delta)
Delete(index, delta)
Move(from_index, to_index, delta)
Replace(index, value, delta)
```

The index fields record user intent for diagnostics. The CRDT delta is
authoritative when another replica applies an operation.

`lattice_sequence` directly supports insert, delete, and move. It has no
native replace operation. Watershed will implement replace by:

1. validating the target index;
2. deleting the visible item;
3. inserting the replacement at the same index;
4. merging the delete and insert deltas;
5. submitting one `Replace` channel operation.

This composition gives replace one pending entry, one wire operation, and one
event batch. It does not make replace a native lattice operation.

The move destination follows lattice's contract: `to_index` is interpreted
after removing the item at `from_index`.

### Events

The first event type will be:

```text
SequenceChanged(values: List(Json))
```

Local and remote edits will emit this event only when the optimistic visible
list changes. A state-shaped event avoids reporting an author's stale index as
the final position after concurrent edits. It also avoids ambiguous list diffs
when duplicate JSON values are present.

### Errors

The kernel will distinguish invalid edit requests from consistency failures.

- Invalid insert, delete, move, and replace indexes return explicit mutation
  errors.
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

Add Sequence variants to the closed channel sums:

- `SequenceChannel`;
- `InitSequence`;
- `SequenceState`;
- `SequenceOp`;
- `SequenceEvent`;
- `SequenceSummary`.

Extend all channel dispatch functions, including creation, type conversion,
summary creation and loading, attach handling, remote application,
acknowledgement, rollback, stash replay, local metadata, pending inspection,
and cache checks.

Because sequence items are arbitrary JSON values, handle discovery will scan
the optimistic visible list and return every nested handle address. This keeps
attach dependency ordering correct when a sequence contains DDS handles.

Detached attach will carry the optimistic sequence state. After the attach
operation is created, the kernel will promote that state to sequenced state
and clear pending operations, matching the attach behavior of the existing
optimistic lattice kernels.

## Runtime API

The runtime core and both target-specific facades will expose equivalent
operations:

```text
create_sequence
sequence_insert
sequence_delete
sequence_move
sequence_replace
sequence_values
sequence_length
```

Mutation functions on both facades will return `Result(Nil, String)` so invalid
indexes reach callers without panics. Read functions will return the optimistic
list and length.

The channel will use the runtime's existing replica identity when it creates a
new sequence or loads one from a summary. Loading will merge the stored state
into a fresh sequence branded with the joining replica's ID so future deltas
use the correct author.

## Wire and Summary Format

Add a distinct channel type string and op codecs in `watershed/wire/ops`.
Each op will carry:

- an operation tag;
- diagnostic intent fields such as indexes and inserted values;
- the encoded CRDT delta.

The delta will use `sequence.to_json(delta, fn(value) { value })`, convert that
JSON value to a string, and place the string in the op. Decoding will pass the
string to `sequence.from_json` with Watershed's JSON-value decoder. This
matches the existing lattice-backed wire convention.

Sequence summaries will use the same lattice envelope and encode the
sequenced state. The format remains Watershed-specific; it does not claim
Fluid SharedSequence compatibility.

## State Transitions

### Local edit

1. Validate the operation against the optimistic sequence.
2. Produce the updated optimistic sequence and sparse delta.
3. Append one pending entry with a local message ID.
4. Emit `SequenceChanged` if visible values changed.
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
3. Emit `SequenceChanged` only if the visible optimistic list changed.

### Rollback

1. Match the rejected op and message ID against the newest pending entry.
2. Remove that entry.
3. Rebuild `optimistic` from `sequenced` plus the remaining pending deltas.
4. Emit `SequenceChanged` if rollback changed the visible list.

## Testing

### Kernel tests

Cover:

- insert, delete, move, and replace;
- arbitrary JSON values and duplicate values;
- optimistic and sequenced reads;
- invalid indexes;
- FIFO acknowledgement and LIFO rollback;
- duplicate or subsumed remote deltas;
- stash replay;
- attach promotion;
- summary reload with a new replica ID;
- optimistic-cache coherence.

### Convergence tests

Use at least two replicas and cover:

- concurrent inserts at the same position;
- delete concurrent with move;
- concurrent moves;
- replace concurrent with insert, delete, and replace;
- different operation delivery orders;
- repeated delivery of the same delta.

All replicas must produce the same visible sequence after they receive the
same operation set.

### Integration tests

Add:

- wire round-trip and malformed-delta tests;
- channel attach and summary tests;
- runtime-core mutation and read tests;
- Erlang and JavaScript facade tests.

### Model-based fuzzing

Extend the existing fuzz harness with a sequence model. Generate only
model-valid indexes, then exercise local edits, sequencing, duplicate
delivery, rollback, reconnect and stash replay, and summary reload.

The harness will assert:

- all connected clients converge;
- each client's optimistic list matches its model;
- each kernel's optimistic cache equals sequenced state plus pending deltas.

## Future Text DDS

The next design can add a separate text channel backed by `lattice_text`.
That channel should expose grapheme-based insert, delete-range, replace-range,
substring, and anchor APIs rather than treating text as a generic JSON array.
Keeping the sequence kernel generic avoids locking the text API to
item-by-item array semantics.
