# SharedTree runtime compression and chunking

**Status:** Implemented and locally accepted on 2026-10-15. The accepted
implementation baseline is `75ecdceb`; publication is bounded by the separate
compression extension profile and the evidence below.

**Implementation plan:** [Compression and chunking](../plans/2026-10-14-shared-tree-compression.md).

## 1. Goal and scope

Let native Watershed JavaScript and BEAM clients consume the runtime-compressed
and chunked operations emitted by the pinned Fluid 3.1.0 client. Prove live
collaboration, history catch-up, reconnect, summary continuation, and explicit
checkpoint recovery, not just decompression of an isolated payload.

This is the next client-compatibility slice after the accepted M7 profile.
It is inbound-first: native operations remain uncompressed, with their existing
submission and acknowledgement behavior. Peers continue using
`RouterliciousDocumentServiceFactory` against the same pinned Floodgate.
Changing drivers, servers, or server protocols is not part of this work.

### Global constraints

- Fluid packages remain `3.1.0`; upstream source remains `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960`.
- Floodgate remains `0eb493fc46d1bb9baf1151a6ccdde93544e057e7`.
- The Spillway dependency remains `25f515cf67027e4b2db2344c3abb2141056e45fc`; preserve compression in an owned ingress envelope, not an external type patch.
- Production decoding and normalization run on both JavaScript and BEAM; no Fluid runtime or JavaScript-only codec is a production dependency.
- Native outbound compression/chunking, other compression algorithms, and additional upstream client versions are out of scope.
- Incremental FieldBatch chunks, incremental summary writing, GC sweep, arbitrary factories, and general snapshot compatibility are out of scope.
- Keep the legacy `test/fixtures/shared_tree/profile.json` bytes and its `29fe106785ec1705cd1ac4d45de8e88f9a6cc89487c3b7cd1df6ad65b318b1de` digest unchanged; publish this extension in a separate generated compression profile.
- Preserve the existing tree codec versions, declared container layouts, typed application API, pending-edit ownership, and explicit failure behavior.

## 2. Why this comes before the remaining extensions

The current oracle disables runtime operation compression with
`minimumBatchSizeInBytes: Infinity`. Ordinary pinned runtime options instead
enable LZ4 compression at **614400 bytes (600 KiB)** and use
**204800-byte (200 KiB)** chunks when the compressed result is still too large.
An otherwise compatible collaborator can therefore fail after a sufficiently
large insertion without changing its schema or opting into an exotic API.

Do not infer chunk coverage from a large, repetitive string. Compression can
make that string smaller than one chunk. Acceptance needs both a highly
compressible workload and deterministic high-entropy content whose actual
compressed representation crosses the default chunk threshold.

This is unrelated to runtime ID compression and distinct from SharedTree's
incremental FieldBatch representation. The latter is a separate, opt-in codec
extension, not a prerequisite for this slice.

## 3. Source contract and current obstacles

Use the pinned
[operation lifecycle sources](https://github.com/microsoft/FluidFramework/tree/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/runtime/container-runtime/src/opLifecycle)
as the format authority. In that directory, `opCompressor.ts`,
`opDecompressor.ts`, `opSplitter.ts`, and `remoteMessageProcessor.ts` establish:

1. Group a batch before compression.
2. Serialize its singleton content inside a JSON array, UTF-8 encode it, apply
   `lz4js` frame compression, and base64 encode it into `packedContents`.
3. Put `"compression": "lz4"` on the outer sequenced message.
4. Split an oversized compressed runtime message into 1-based `chunkedOp`
   messages, retaining original metadata/compression on the final chunk.
5. On receipt, reassemble, decompress, ungroup, and unpack, in that order.

Reassembly is per sender client ID. Different senders may interleave. The
completed operation uses the final physical chunk's sequence number, client
sequence number, reference sequence number, and timestamp. An empty final chunk
is legal. A member's leave clears its incomplete stream.

The pinned container runtime loads and writes root
[`/.chunks`](https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/runtime/container-runtime/src/summary/summaryFormat.ts#L216).
Its JSON shape is `[string, string[]][]`: sender ID and received string pieces.
A summary taken between chunks must retain the prefix for a later reader.
This narrow summary extension belongs here even though broader snapshot
consumption is scheduled next.

The current native path has three separate obstacles:

- `wire/socket.gleam` rejects an outer compression field. The shared
  `SequencedDocumentMessage` type cannot retain it.
- `runtime_core.gleam` treats each sequenced operation as an immediately
  decodable batch and retains raw messages in replay/out-of-order state.
- `wire/fluid_document.gleam` independently decodes operation contents for GC
  references and batch bookkeeping. Fixing only the tree apply path leaves
  persistence inconsistent.

There is also an activation dependency. The pinned runtime can send a runtime
`"schema"` operation before enabling compression on an existing document.
[`summary/documentSchema.ts`](https://github.com/microsoft/FluidFramework/blob/c3c5bf0ecd313362e83fe8a02b7d39e7e0736960/packages/runtime/container-runtime/src/summary/documentSchema.ts)
defines its compare-and-swap semantics. Merely preserving a flag in newly
created summaries does not cover a default peer joining a native-created
document whose schema does not yet advertise compression.

## 4. Architecture

### 4.1 Retain the transport envelope

Add an owned `wire.SequencedEnvelope` containing the existing shared message
plus `Option(String)` compression. Keep unsupported algorithm names until
normalization so the user receives an explicit unsupported-compression error,
not a generic socket parse failure.

Add connection and operation envelope adapters. A connection envelope contains
ordinary shared handshake metadata and its authoritative list of enveloped
initial messages. The embedded handshake's `initial_messages` is empty:
there must not be two replay lists that can disagree.

Add enveloped HTTP delta fetching without changing existing shared-message
callers unnecessarily. Switch every native runtime ingress to the enveloped
path: initial messages, JS and BEAM live operations, historical delta pages,
requestOps, bootstrap buffering, and Sluice test delivery. Existing
shared-message helpers may lift uncompressed messages into envelopes, but all
application and replay paths delegate to one core ingestion implementation.

### 4.2 One bounded normalizer

Add `wire/fluid_inbound.gleam`, a pure state machine ahead of the existing
container routing decoder. It consumes one physically ordered envelope and
returns either an incomplete chunk or one complete decoded runtime batch.
It does not apply DDS changes, update sequence numbers, or own reconnect.

Its order is reassembly, base64/LZ4/UTF-8/JSON decoding, then the existing
`fluid_container.decode` and profile validation. Current 3.1.0 compressed
writers produce a singleton JSON array; require that shape. Continue
supporting the existing plain grouped and singleton forms.

Explicitly refuse unknown algorithms, malformed packed envelopes, nested
compression, and historical multi-message compressed/placeholder forms.
Do not copy the upstream reader's legacy heuristics and thereby promise
unassessed old-client compatibility. The old heuristic that treats an
unmarked `packedContents` object as compressed is not added in this slice.
Capture a clear negative fixture for each excluded form.

Use a focused read-only pure-Gleam LZ4 frame decoder. A verified cross-target
package is not currently established in this repository; separate JS and
NIF-based BEAM backends would add divergent validation and deployment
requirements. Implement no encoder, public compression API, or general
algorithm registry. The source capture defines the emitted frame flags.
Support every frame shape produced by the pinned compressor within the limits,
including compressed/uncompressed blocks and overlapping matches. Validate
frame/header checksums and advertised lengths; refuse unsupported dictionary
or frame features explicitly.

Use byte-oriented bounded output with indexed history, not whole-output
concatenation per decoded byte or a repeatedly scanned list. Benchmark the
actual large fixture on both targets before selecting this implementation for
release; a functional but quadratic decoder does not satisfy the design.

### 4.3 Physical sequence, logical batch

`Core` owns live normalizer state. Order and deduplicate physical envelopes
before changing that state. Every chunk advances raw sequence continuity and
minimum-sequence bookkeeping. Only completion invokes logical batch
validation, ID allocation finalization, DDS application, batch identity
recording, acknowledgement matching, and tree commit events.

Use the final chunk's representative sequencing context and restored original
metadata. Preserve grouped operation indexes, original batch identity, empty
batch meaning, and allocation-before-use ordering. Do not stamp a batch ID onto
each partial chunk or confuse a grouped inner CSN with its representative CSN.

Pass the already-decoded logical result to document persistence. Batch/GC
bookkeeping must not decode a raw compressed payload again. Raw physical
counters and last-message metadata still advance once for each physical
message. Apply a completed batch atomically: failure returns an error without
publishing a partially updated core or summary.

Recovery's sequenced and optimistic cores must each have the appropriate
immutable normalizer state. Normalize once per physical message for each
independent core state, not twice against one destructively consumed stream.

### 4.4 Summaries, reconnect, and checkpoints

`DocumentSummary` retains validated partial streams, seeds the core normalizer
on load, and receives the post-step state when advancing. The core is the
authoritative live state; persistence is a snapshot, not another decoder.
Write `/.chunks` only when nonempty, in the pinned upstream shape. A loaded
array of strings determines the next chunk ID; the first tail message supplies
the declared total, which must be consistent with the retained prefix.

Preserve negotiated document-schema compression capability metadata even
though native writes remain uncompressed. Do not enable unrelated schema
features, rewrite version floors, or drop unknown-but-permitted metadata.

Consume the runtime `"schema"` operation needed to activate compression.
Validate its version, reference sequence, supported runtime feature set, and
compatibility information against the pinned controller. Accept a change only
when its proposed `refSeq` equals the current document schema's `refSeq`, then
store the operation's sequence number as the new schema `refSeq`. A stale
proposal is a CAS rejection, not a document failure; a future/invalid reference
or unsupported feature is an explicit error. Process proposals in the pinned
order and capture that behavior rather than replacing it with a blind JSON
merge. This is container runtime schema control, not additional SharedTree
stored/view schema evolution. Native clients consume the required change;
they do not propose unrelated runtime upgrades.

A transport disconnect does not erase prefixes belonging to other senders.
A sequenced sender leave does. Ordinary live/bootstrap load requires the full
prefix from a summary or replay; do not use upstream's special
`allowInitialPartialChunkStream` history-window behavior to hide missing data.

Explicit pending checkpoints include partial peer streams through their
document summary. Restore on either target must continue those streams before
acknowledging/resubmitting pending native edits. Do not broaden the existing
checkpoint exclusions for pending ordinary DDS edits, attachment/alias work,
transactions, branches, or automatic journaling.

### 4.5 Resource and failure boundary

The proposed extension has fixed internal limits, recorded in its generated
profile. They are acceptance boundaries, not claims about every Fluid client:

| Limit | Value | What is counted |
| --- | --- | --- |
| Packed/reassembled payload | 16 MiB | UTF-8 bytes of the serialized reassembled runtime payload, before base64 expansion is decoded |
| Decoded payload | 16 MiB | Decompressed UTF-8 bytes, checked during LZ4 output, before JSON parsing |
| Buffered partial streams | 16 MiB total | UTF-8 bytes of retained chunk contents across all senders |
| Open partial streams | 64 | Distinct senders with incomplete streams |
| Chunks per stream | 128 | Declared total and received prefix length |

These extend the existing 16 MiB bootstrap-buffer precedent to the new
allocation surfaces. Existing transport/bootstrap limits still apply; this
does not promise a 16 MiB live message or arbitrary large native submissions.
Test exact-limit and one-over behavior with smaller injected internal limits,
and exercise genuine default-threshold workloads with production limits.
There is no new application configuration API.

Reject invalid base64, invalid UTF-8, truncated frames, invalid offsets or
checksums, JSON roots of the wrong shape, duplicate/out-of-order chunk IDs,
inconsistent totals, missing senders/prefixes, and every exceeded limit.
Report a categorized core/load/recovery error with sender/sequence context;
never skip the operation, reset the tree to empty, or mark a partial load ready.

## 5. Acceptance and publication

Use an additional generated `compression-profile.json` and `compression.json`
corpus beside the frozen legacy profile. Capture provenance includes pinned
packages/source, injected probe digest, raw physical messages, decoded logical
expectations, actual byte sizes, frame features, and partial-summary blobs.
Native expected results must come from upstream behavior, not a second
handwritten version of the native algorithm.

The live gate requires an upstream writer, upstream witness, and native
reader/editor for each target. Require default-threshold compressed-but-
unchunked and genuinely chunked traffic, native edits observed upstream,
catch-up from history, reconnect with pending native work, native summary to
fresh upstream/native readers, and restart continuation from partial streams.
Include a native-created document joined by a default-configured peer, its
observed runtime schema activation, and subsequent compressed edits.
Small-threshold scenarios are supplementary, never substitutes for default
settings. Deterministic prefix control must record its delivery boundaries;
timing sleeps are not evidence that a client stopped between chunks.

Fail on missing service, skipped cells, missing targets, stale run IDs,
different profile/probe digests, fake uncompressed traffic, or omitted required
evidence. Keep local results distinct from hosted workflow runs.

Release changes R03, and the relevant R09/R11/R12 qualifications, only after
the new gate passes. R04 remains unchanged. Keep the historical M7 profile and
acceptance records intact.

The accepted local run is
`a97eb0f7-bc49-4df4-a5e3-b270c355d4c3`: 12/12 cells passed with no skips on
the pinned defaults. It binds compression profile SHA-256
`1c14161270e64cae5ea429a5c3bf69dac0653624d7b0ad4ad4df4ddea026ce7c`,
corpus SHA-256
`d03edfd3fb97e39cde8934e703b44033d07cf40ad81c9e96ba5bb3fd14cb228d`,
probe SHA-256
`9c25674c5dcc06ff9b6fc8049560d1b633fcbce6e29512b02de799df580277c0`,
Fluid source `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960`, Spillway
`25f515cf67027e4b2db2344c3abb2141056e45fc`, Floodgate
`0eb493fc46d1bb9baf1151a6ccdde93544e057e7`, and legacy profile SHA-256
`29fe106785ec1705cd1ac4d45de8e88f9a6cc89487c3b7cd1df6ad65b318b1de`.
No hosted compression run is claimed.

## 6. Following work

After this slice, prioritize ordinary upstream snapshot/reference consumption
through real storage bootstrap, then common typed union/record access and
targeted JSON/domain-helper proof, then array schema evolution and selected
policy extensions. Start representative measurements now, but schedule
incremental FieldBatch encoding, incremental writing, and reclamation from
measured need. Generated schemas and broader durability follow those ordinary
collaboration gaps. Shared branches, arbitrary factories, and exotic handles
remain demand-driven; production authentication remains a shipping requirement.
