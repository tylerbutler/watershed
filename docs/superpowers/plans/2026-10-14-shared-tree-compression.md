# SharedTree Compression and Chunking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `subagent-driven-development` or `executing-plans` to implement this plan
> task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. This is one
> dependent runtime change; do not assign concurrent owners to core,
> persistence, and recovery.

**Goal:** Native JavaScript and BEAM clients consume pinned upstream runtime
LZ4/chunked operations through live delivery, replay, summary load, and explicit
restart recovery without requiring peers to disable operation compression.

**Architecture:** Preserve the outer compression marker in an owned wire
envelope and normalize physically ordered input once before existing container
routing and DDS application. Reassembly state belongs to the pure core and is
persisted through the upstream `/.chunks` summary shape. Keep native writes
uncompressed and prove the extension with a separate profile and live gate.

**Tech Stack:** Gleam on JavaScript and BEAM; existing startest tests, Sluice,
Node test runner, source-injected Fluid 3.1.0 oracle, Routerlicious driver, and
pinned Floodgate. A read-only pure-Gleam LZ4 frame decoder; no production Fluid
dependency or platform-specific compression backend.

**Spec:** [Runtime compression and chunking design](../specs/2026-10-14-shared-tree-compression-design.md).

**Status:** Complete and locally accepted on 2026-10-15. The implementation
baseline is `75ecdceb`. Fresh release acceptance used compression run
`a97eb0f7-bc49-4df4-a5e3-b270c355d4c3` with 12/12 cells, no skips, compression
profile SHA-256
`1c14161270e64cae5ea429a5c3bf69dac0653624d7b0ad4ad4df4ddea026ce7c`,
and corpus SHA-256
`d03edfd3fb97e39cde8934e703b44033d07cf40ad81c9e96ba5bb3fd14cb228d`.
This is local evidence; no hosted compression run is claimed.

## Global constraints

- Fluid packages remain `3.1.0`; upstream source remains `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960`.
- Floodgate remains `0eb493fc46d1bb9baf1151a6ccdde93544e057e7`.
- The Spillway dependency remains `25f515cf67027e4b2db2344c3abb2141056e45fc`; preserve compression in an owned ingress envelope, not an external type patch.
- Production decoding and normalization run on both JavaScript and BEAM; no Fluid runtime or JavaScript-only codec is a production dependency.
- Native outbound compression/chunking, other compression algorithms, and additional upstream client versions are out of scope.
- Incremental FieldBatch chunks, incremental summary writing, GC sweep, arbitrary factories, and general snapshot compatibility are out of scope.
- Keep the legacy `test/fixtures/shared_tree/profile.json` bytes and its `29fe106785ec1705cd1ac4d45de8e88f9a6cc89487c3b7cd1df6ad65b318b1de` digest unchanged; publish this extension in a separate generated compression profile.
- Preserve the existing tree codec versions, declared container layouts, typed application API, pending-edit ownership, and explicit failure behavior.

The implementation baseline for planning is
`7af05463a8d5e5323be4fd2794a43a9716da097c`. Verify the execution worktree and
actual revision before starting. This document is not execution approval.
Do not edit `.code-map/`, APM-managed instructions, or upstream production
source. Only the existing source tool may deploy owned test injections.

## File responsibilities

Line numbers below are navigation hints at the planning baseline; locate
declarations with `code-map` and read their current bodies before editing.

| Files | Responsibility |
| --- | --- |
| `tools/shared-tree-oracle/upstream-compression.spec.ts` (new) | Owned source probe, injected into `packages/runtime/container-runtime/src/test/watershedCompression.spec.ts`; use the real pinned compressor/splitter/remote processor and partial-summary representation. |
| `tools/shared-tree-oracle/source.mjs`, `source.test.mjs` | Register/hash/verify the additional injection; add a focused `compression-capture` command that builds/tests the container-runtime package without changing historical capture batches. |
| `tools/shared-tree-oracle/compression.mjs`, `compression.test.mjs` (new) | Validate/canonicalize captures and generate/check the separate corpus/profile; never regenerate the legacy profile. |
| `test/fixtures/shared_tree/compression.json`, `compression-profile.json` (new, generated) | Raw upstream wire/frame vectors, expected logical output, provenance, extension limits and case coverage. |
| `src/watershed/wire.gleam`, `wire/socket.gleam` | Envelope types and transport decoders; retain outer compression and original physical metadata. |
| `src/watershed/wire/lz4.gleam` (new) | Bounded LZ4 frame decoding only; frame/header validation and indexed output history. |
| `src/watershed/wire/fluid_inbound.gleam` (new) | Per-sender chunk state and normalization to an existing `fluid_container.DecodedBatch`. |
| `src/watershed/wire/fluid_container.gleam` | Recognize the runtime `"schema"` operation required to activate compression; keep ordinary routing here. |
| `src/watershed/runtime_core.gleam` | Order envelopes, advance physical position, apply complete logical batches atomically, and retain live normalization state. |
| `src/watershed/wire/fluid_document.gleam` | Read/write partial streams and capability metadata; apply narrow runtime-schema CAS changes and consume normalized batches for GC/batch bookkeeping. |
| `src/watershed/git_storage.gleam`, `runtime.gleam`, `runtime_beam.gleam`, `sluice_js.gleam`, `sluice/frame.gleam` | Carry envelopes through HTTP, bootstrap, live delivery, requestOps, and test transport without stripping compression. |
| `src/watershed/recovery.gleam` | Persist/restore partial peer streams with the existing explicit pending-tree checkpoint ownership. |
| `test/watershed/tree/compression_fixture.gleam` (new) | Read generated vectors and prepare production-core replay tests; no decoder or semantic expectations implemented in the helper. |
| `test/watershed/shared_tree_compression_test.gleam` (new) | LZ4 and normalizer tests on both targets. |
| Existing `shared_tree_container_test.gleam`, `shared_tree_runtime_test.gleam`, `shared_tree_document_summary_test.gleam`, `shared_tree_document_recovery_test.gleam`, `git_storage_test.gleam`, `facade_parity_test.gleam`, and `tree/runtime_fixture.gleam` under `test/watershed/` | Regressions at existing integration boundaries. |
| `smoke/shared_tree_bootstrap.mjs`, `smoke/shared_tree_storage.mjs` and their existing Gleam/FFI harnesses | Actual HTTP/bootstrap adapter coverage, including outer compression fields. |
| `tools/shared-tree-oracle/service.mjs`, `client-driver.mjs`, `delivery-gate.mjs` and their tests | Scoped upstream runtime settings, real native process lifecycle, and deterministic delivery controls; reuse existing mechanisms. |
| `tools/shared-tree-oracle/compression-interop.mjs`, `compression-interop.test.mjs` (new) | Strict dual-target live acceptance and decoder measurement reports. |
| `justfile`, `tools/shared-tree-oracle/package.json`, `.github/workflows/shared-tree-interop.yml` | Commands and manual workflow/artifact integration for the new gate. |
| `README.md`, `tools/shared-tree-oracle/README.md`, `docs/shared-tree-client-compatibility.md`, `docs/superpowers/plans/2026-09-21-shared-tree.md` | Publish only freshly proved support and preserve historical restrictions/results. |

No application-facing tree API or server change is needed. Keep normal routing
in `fluid_container`; do not create another routing, GC, or acknowledgement
implementation inside the decompressor.

## Shared interfaces and limits

These are proposed internal contracts, not a new public application API.
Task implementers must use the same names and ownership throughout.

```gleam
// In watershed/wire; existing imports supply the shared message types.
pub type SequencedEnvelope {
  SequencedEnvelope(
    message: SequencedDocumentMessage,
    compression: Option(String),
  )
}

pub type ConnectionEnvelope {
  ConnectionEnvelope(
    handshake: ConnectedMessage,
    initial_messages: List(SequencedEnvelope),
  )
}

pub type OperationEnvelopes {
  OperationEnvelopes(document_id: String, ops: List(SequencedEnvelope))
}
```

`ConnectionEnvelope.handshake.initial_messages` must be empty; only the outer
list is consumed. Existing plain-message entry points lift messages with
`compression: None` and delegate. Keep those adapters thin and testable.

```gleam
// In watershed/wire/lz4.
pub type Error {
  InvalidFrame
  UnsupportedFrameFeature(String)
  InvalidChecksum
  InvalidMatch
  OutputLimitExceeded
}

pub fn decompress(
  frame: BitArray,
  max_output_bytes: Int,
) -> Result(BitArray, Error)
```

```gleam
// In watershed/wire/fluid_inbound; Dict and Option are standard-library types.
pub opaque type State {
  State(
    limits: Limits,
    streams: Dict(String, Partial),
    buffered_bytes: Int,
  )
}

type Partial {
  Partial(
    reversed_pieces: List(String),
    received: Int,
    total: Option(Int),
    bytes: Int,
  )
}

pub type Limits {
  Limits(
    max_packed_bytes: Int,
    max_decoded_bytes: Int,
    max_buffered_bytes: Int,
    max_streams: Int,
    max_chunks: Int,
  )
}

pub type Payload {
  NonOperation
  Incomplete
  Complete(
    representative: SequencedDocumentMessage,
    batch: fluid_container.DecodedBatch,
  )
}

pub type Step {
  Step(state: State, payload: Payload)
}

pub type Error {
  UnsupportedCompression(String)
  InvalidPackedPayload(String)
  InvalidChunk(String)
  LimitExceeded(String)
  ContainerFailure(fluid_container.ContainerError)
}

pub fn default_limits() -> Limits
pub fn new(limits: Limits) -> State
pub fn step(
  state: State,
  envelope: wire.SequencedEnvelope,
) -> Result(Step, Error)
pub fn remove_client(state: State, client_id: String) -> State
pub fn partial_chunks(state: State) -> List(#(String, List(String)))
pub fn restore(
  limits: Limits,
  partials: List(#(String, List(String))),
) -> Result(State, Error)
```

`NonOperation` lets existing join/leave/summary/noop handling continue.
`Complete` contains an uncompressed representative and already-validated batch;
its physical context is the final message's context. Apply no logical batch
for `Incomplete`. Restored partials contain no total count because the upstream
blob does not store it; validate the declared total when the next chunk arrives.

Production limits are 16 MiB each for packed/reassembled UTF-8 bytes, decoded
output bytes, and aggregate buffered UTF-8 chunk bytes; 64 open streams; 128
chunks per stream. Use smaller injected limits for boundary tests. All byte
counts use UTF-8, not graphemes or JavaScript UTF-16 string length.

## Task 1: Capture the pinned operation contract

**Dependencies:** None.

**Files:** New upstream probe, `compression.mjs`/tests, two generated fixture
files; modify `source.mjs`/tests and add the fixture reader.

**Consumes:** Existing source verification/injection mechanism; pinned
`opCompressor.ts`, `opDecompressor.ts`, `opSplitter.ts`,
`remoteMessageProcessor.ts`, `summary/summaryFormat.ts`, and
`summary/documentSchema.ts`.

**Produces:**

- `source.mjs compression-capture <directory>`: write raw source observations
  under that directory; fail unless packages, source, and injected hash match.
- `compression.mjs generate|check`: canonical generation or byte comparison of
  the two new fixture files, without calling the legacy generator.
- `validateCompressionCapture(value: unknown): CompressionCapture` in
  `compression.mjs`; malformed/incomplete captures throw descriptive errors.
- Test helper `compression_fixture.frame(id: String) ->
  Result(#(BitArray, BitArray), String)` for actual compressed/decoded bytes.
  `compression_fixture.envelopes(id: String) ->
  Result(List(wire.SequencedEnvelope), String)` is completed in Task 2.

- [x] **Write contract-validator failures.** Read the captured JSON as a
  template, clone it, and assert rejection when its source hash, required case,
  measured chunk count, or default threshold is removed/changed:

  ```js
  import assert from "node:assert/strict";
  import { readFile } from "node:fs/promises";
  import test from "node:test";
  import { validateCompressionCapture } from "./compression.mjs";

  const capture = JSON.parse(await readFile(new URL(
    "../../test/fixtures/shared_tree/compression.json", import.meta.url,
  ), "utf8"));

  test("default threshold is part of the captured contract", () => {
    const changed = structuredClone(capture);
    changed.defaults.minimumBatchSizeInBytes = 1;
    assert.throws(() => validateCompressionCapture(changed), /threshold/);
  });
  ```

- [x] **Run red:** `node --test tools/shared-tree-oracle/compression.test.mjs`.
  Initially expect missing module/corpus; after scaffolding, require an
  assertion failure when validation is bypassed, not a permanently broken
  import. Do not commit until the behavioral tests run and pass.
- [x] **Implement the capture and validator.** Inject the new probe into the
  container-runtime test package, not the tree test package. Extend the owned
  injection registry and verify allowlist; build that package with its existing
  `build:compile` and `build:test:esm` scripts and run only
  `lib/test/watershedCompression.spec.js` through the existing pinned pnpm/mocha
  launcher. Leave old source-test batches and their outputs unchanged.
- [x] **Record concrete data, not inferred output.** The corpus has
  `formatVersion: 1`, `upstream`, `probe`, `defaults`, `limits`, `frames`, and
  `cases`. A frame has `id`, `compressedBase64`, `decodedBase64`, and observed
  frame flags. A case has `id`, raw `messages`, expected normalized runtime
  messages, measured byte sizes, and optional initial/partial summaries.
  Negative policy cases carry an explicit `expectedNativeError`, not a claim
  that upstream refuses its own legacy format.
- [x] **Cover the exact producer paths.** Require plain singleton/group,
  default compressed singleton/group, default chunked group, two interleaved
  senders, empty final chunk, empty group, ID allocation before tree use,
  handle-valued edits, and a partial-summary prefix/tail. Add mutated negative
  vectors for unmarked packed content, unknown algorithm, multi-message
  compressed arrays, missing prefix, malformed frames, and nested compression.
  Capture a native-format document without `compressionLz4`, an accepted
  activation `"schema"` message, stale competing proposals, future/invalid
  references, and the post-activation summary and compressed operation.
  Preserve the pinned controller's proposal-array ordering and CAS outcome.
  Capture block literals, overlap, multi-block matches, UTF-8, and checksum
  failures. Save the emitted flags rather than guessing the LZ4 dialect.
- [x] **Generate and run green:**

  ```bash
  node tools/shared-tree-oracle/source.mjs verify
  node tools/shared-tree-oracle/source.mjs compression-capture tools/shared-tree-oracle/.output/compression-source
  node tools/shared-tree-oracle/compression.mjs generate
  node --test tools/shared-tree-oracle/compression.test.mjs tools/shared-tree-oracle/source.test.mjs
  node tools/shared-tree-oracle/compression.mjs check
  ```

  `generate` reads that fixed output directory. The extension profile records
  its corpus hash, source/probe identities, legacy profile digest, exact
  thresholds/limits, supported forms and exclusions. Large live run artifacts
  stay ignored; commit only deterministic vectors needed by native tests.
- [x] **Commit checkpoint:** `test(tree): capture compressed runtime contract`.
  Stage only the owned source tool/probe, new generator/tests, fixture helper,
  and two generated compression files. Confirm the legacy profile digest.

**Exit:** A clean checkout can run native vector tests from the committed
corpus. Re-capture requires the real pinned source and reproduces those bytes.

## Task 2: Retain compression through every ingress envelope

**Dependencies:** Task 1.

**Files:** `wire.gleam`, `wire/socket.gleam`, `git_storage.gleam`,
`sluice/frame.gleam`, `sluice_js.gleam`; fixture reader/runtime fixture and
existing container/storage tests.

**Consumes:** Shared interface types above and the raw corpus.

**Produces:**

```gleam
// In watershed/wire/socket.
pub fn sequenced_envelope_decoder() -> Decoder(wire.SequencedEnvelope)
pub fn connection_envelope_decoder() -> Decoder(wire.ConnectionEnvelope)
pub fn operation_envelopes_decoder() -> Decoder(wire.OperationEnvelopes)
```

Add `git_storage.fetch_enveloped_deltas` with the same named inputs as
`fetch_deltas`, returning `Result(List(wire.SequencedEnvelope), StorageError)`
on BEAM and `Promise(Result(List(wire.SequencedEnvelope), StorageError))`
on JS. Preserve the old helper for existing callers; do not implement a second
HTTP client. Add `compression_fixture.envelopes` using the new decoder.

- [x] **Write red tests at the actual wire boundary:**

  ```gleam
  pub fn shared_tree_compression_preserves_outer_marker_test() -> Nil {
    let assert Ok(messages) =
      compression_fixture.envelopes("default-compressed-single")
    let assert [first, ..] = messages
    first.compression |> expect.to_equal(Some("lz4"))
  }
  ```

  Add tests for an unknown string algorithm retained for later refusal,
  non-string compression rejected, all physical fields/metadata preserved,
  wrapped and bare operation lists, connection initial messages stored exactly
  once, and plain shared-message lift/encode round trips.
- [x] **Run red on both targets:**

  ```bash
  gleam test --target erlang -- shared_tree_compression shared_tree_container git_storage
  gleam test --target javascript -- shared_tree_compression shared_tree_container git_storage
  ```

- [x] **Implement the types and adapters.** Factor the shared physical-field
  decoder so old strict uncompressed callers and new envelopes cannot drift.
  Parse handshake metadata without processing its initial messages through the
  old rejecting decoder; store those messages only in the envelope list.
  Enveloped delta fetching reuses URL/auth/response/error handling. Extend
  Sluice encoding to retain the outer field; update existing fixture record
  constructors with `compression: None` where the type gains that field.
  Never insert a private marker into `contents`.
- [x] **Run green and inspect actual serialized JSON.** Assert the field is
  outermost, not inside grouped items or DDS contents. Ensure the old plain
  tests and existing decoder refusals still pass. Production actor switching
  waits for Task 5; this task does not claim runtime support.
- [x] **Commit checkpoint:** `refactor(wire): retain sequenced compression`.

**Exit:** Raw compressed messages survive all transport codecs. No dependency
pin, server type, or native outbound operation changes.

## Task 3: Implement bounded cross-target LZ4 frame decoding

**Dependencies:** Task 1; independent of Task 2 after capture.

**Files:** New `wire/lz4.gleam`; compression tests/fixture reader;
decoder-only benchmark command in `compression-interop.mjs` with its tests.

**Consumes:** `compression_fixture.frame`, captured frame features, and the
`lz4.decompress` interface above.

**Produces:** The bounded decoder and a `compression-interop.mjs benchmark`
command that writes a decoder measurement report under
`.output/compression/benchmark.json`. This command does not require Floodgate.

- [x] **Write a vector equality test and a real refusal test:**

  ```gleam
  pub fn shared_tree_compression_lz4_matches_upstream_test() -> Nil {
    let assert Ok(#(compressed, decoded)) =
      compression_fixture.frame("overlap-match")
    lz4.decompress(compressed, 16 * 1024 * 1024)
    |> expect.to_equal(Ok(decoded))
  }

  pub fn shared_tree_compression_lz4_enforces_output_limit_test() -> Nil {
    let assert Ok(#(compressed, decoded)) =
      compression_fixture.frame("overlap-match")
    lz4.decompress(compressed, bit_array.byte_size(decoded) - 1)
    |> expect.to_equal(Error(lz4.OutputLimitExceeded))
  }
  ```

  Add exact-limit success, empty/literal/multi-block/UTF-8 vectors, truncated
  headers/blocks/length extensions, zero and out-of-window offsets,
  cross-block history where permitted, invalid flags/dictionary use, bad
  header/block/content checksums, incorrect content length, and trailing data.
- [x] **Run red:** the two-target `gleam test ... -- shared_tree_compression`
  commands from Task 2 must fail before the decoder exists.
- [x] **Implement the minimum frame reader.** Read fixed-width little-endian
  fields and length extensions with bounds checks. Check magic/version,
  descriptor checksum, permitted block sizes/flags, optional lengths/checksums,
  and end marker. For block tokens, copy literals, read a positive 16-bit
  offset, extend match length, then copy from already-emitted output with
  overlap semantics. Enforce limits before allocation and after each extension.
  Keep checksum arithmetic explicitly 32-bit on both targets.
- [x] **Use bounded indexed history.** Store output in indexed chunks and a
  bounded working tail; resolve back-references without scanning the entire
  output or concatenating the accumulated byte array per byte. Keep history
  within the LZ4 window where independent blocks permit it. The decoder is
  read-only and has no routing, JSON, base64, or native FFI dependency.
- [x] **Run green and measure:**

  ```bash
  gleam test --target erlang -- shared_tree_compression
  gleam test --target javascript -- shared_tree_compression
  node tools/shared-tree-oracle/compression-interop.mjs benchmark
  ```

  Generate deterministic 1 MiB and 4 MiB decoded workloads through the pinned
  producer for this measurement. Run two warmups and seven timed decodes per
  size/target, validate output before reporting, and save medians. Time the
  decoder itself: JS through the compiled export and BEAM with `timer:tc`,
  not child-process startup. Require the 4 MiB median to be at most eight
  times the 1 MiB median on each target, and record absolute time. This is an
  anti-quadratic gate, not a published throughput guarantee. On failure,
  repair the output representation; do not lower test sizes or add a JS-only
  fast path.
- [x] **Commit checkpoint:** `feat(wire): decode bounded LZ4 frames`.

**Exit:** Both targets agree with actual pinned encoder output and enforce
malformed-input/allocation boundaries.

## Task 4: Normalize chunks and complete runtime batches

**Dependencies:** Tasks 2 and 3.

**Files:** New `wire/fluid_inbound.gleam`; compression tests and corpus helper.

**Consumes:** The envelope, decoder, existing
`fluid_container.decode(contents, metadata)` and `validate_profile_batch`.

**Produces:** `State`, `Payload`, `Step`, `Error`, and all `fluid_inbound`
functions in the shared interface section.

- [x] **Write the incomplete-prefix assertion first:**

  ```gleam
  pub fn shared_tree_compression_prefix_has_no_batch_test() -> Nil {
    let assert Ok([first, ..]) =
      compression_fixture.envelopes("default-chunked-group")
    let assert Ok(fluid_inbound.Step(state, fluid_inbound.Incomplete)) =
      fluid_inbound.step(
        fluid_inbound.new(fluid_inbound.default_limits()),
        first,
      )
    fluid_inbound.partial_chunks(state)
    |> list.length
    |> expect.to_equal(1)
  }
  ```

  Fold the remaining envelopes with `step` and require exactly one `Complete`
  result, matching captured logical output, final physical context, restored
  metadata, grouped indexes and batch identity.
- [x] **Run red:** both target compression-test commands.
- [x] **Implement reassembly before decompression.** Key streams by client ID,
  enforce 1-based next ID, stable total, all limits, and final metadata fields.
  Concatenate pieces once on completion. Accept an empty final piece, remove
  completed state, and retain other senders. `restore` validates duplicate
  senders, nonempty prefixes, lengths/counts and aggregate bounds; it does not
  invent a total count absent from `/.chunks`.
- [x] **Implement the complete path.** Decode base64 with existing
  `gleam/bit_array` helpers, then LZ4, UTF-8, and singleton JSON-array content.
  Reject unknown algorithm, unmarked packed content, multi-message compressed
  arrays/placeholders, nested compression, and unsupported original types.
  Normalize to the existing ordinary runtime envelope before the existing
  container decoder. Do not mutate outer document message type into an inner
  `"component"` type; preserve the native document-operation boundary.
- [x] **Exercise every state transition.** Test two interleaved senders, plain
  messages between their chunks, duplicate/missing/out-of-order IDs, changed
  totals, null sender, leave cleanup through `remove_client`, unknown final
  compression, restored prefix/tail, empty groups and exact/one-over limits.
  Include multibyte text so byte-limit tests cannot pass with grapheme counts.
  Error results must not expose an advanced state.
- [x] **Run green:** both target compression suites plus
  `shared_tree_container`. Verify normalization yields one validated batch,
  never per-chunk partial DDS changes.
- [x] **Commit checkpoint:** `feat(wire): normalize compressed chunk streams`.

**Exit:** Pure normalization matches the pinned contract, independently of
runtime sequence/recovery behavior.

## Task 5: Integrate physical sequencing, persistence, and native adapters

**Dependencies:** Task 4.

**Files:** `runtime_core.gleam`, `wire/fluid_container.gleam`,
`wire/fluid_document.gleam`, JS/BEAM runtime and storage/Sluice adapters;
runtime, document-summary, facade/storage tests and bootstrap/storage smoke
harnesses.

**Consumes:** `fluid_inbound.Step`, the enveloped transport functions, and the
existing core `handle_sequenced`/`apply_one`/`handle_operation` behavior.

**Produces:**

```gleam
// In runtime_core; legacy plain functions delegate to these paths.
pub fn handle_envelope(
  core: Core,
  envelope: wire.SequencedEnvelope,
) -> Result(#(Core, Ingested), CoreError)

pub fn bootstrap_document_enveloped(
  connected: wire.ConnectionEnvelope,
  summary: fluid_document.DocumentSummary,
) -> Result(Bootstrapped, CoreError)

pub fn resume_bootstrap_envelopes(
  core: Core,
  checkpoint checkpoint: Int,
  deltas deltas: List(wire.SequencedEnvelope),
) -> Result(Bootstrapped, CoreError)

// In fluid_document; old advance delegates through the plain normalizer.
pub fn inbound_state(summary: DocumentSummary) -> fluid_inbound.State
pub fn advance_inbound(
  summary: DocumentSummary,
  physical: wire.SequencedEnvelope,
  normalized: fluid_inbound.Step,
) -> Result(DocumentSummary, SummaryError)

pub fn apply_runtime_schema(
  summary: DocumentSummary,
  contents: Json,
  sequence_number: Int,
) -> Result(DocumentSummary, SummaryError)
```

Add `Core.inbound: fluid_inbound.State` and store envelopes in out-of-order
state. Add a contextual inbound-error `CoreError` variant; map it through
existing actor/load notification paths, preserving target parity.
Add `fluid_container.RuntimeSchemaChange(contents: Json)` to `MessageKind`;
its syntactic decoder accepts the pinned runtime `"schema"` message shape.

- [x] **Write physical-versus-logical failures.** Add test helper
  `compression_fixture.core_case(id: String) ->
  Result(#(runtime_core.Core, List(wire.SequencedEnvelope)), String)`.
  It builds a real `DocumentSummary` and core from the capture's initial
  snapshot using `runtime_fixture.read`/bootstrap; it contains no decoder or
  apply logic. Then assert:

  ```gleam
  pub fn shared_tree_compression_partial_advances_only_position_test() -> Nil {
    let assert Ok(#(before, [first, ..])) =
      compression_fixture.core_case("default-chunked-group")
    let assert Ok(#(after, ingested)) =
      runtime_core.handle_envelope(before, first)
    after.last_seen_sequence_number
    |> expect.to_equal(first.message.sequence_number)
    ingested.events |> expect.to_equal([])
    ingested.resolutions |> expect.to_equal([])
    after.in_flight |> expect.to_equal(before.in_flight)
  }
  ```

  Assert tree content, finalized compressor ranges, pending count, and recent
  batch/GC references are unchanged until completion. Full completion must
  match the captured tree and commit identity, exactly once.
- [x] **Run red:**

  ```bash
  gleam test --target erlang -- shared_tree_compression shared_tree_runtime shared_tree_document_summary git_storage facade_parity
  gleam test --target javascript -- shared_tree_compression shared_tree_runtime shared_tree_document_summary git_storage facade_parity
  ```

- [x] **Refactor the core apply boundary, not the DDS kernel.** Deduplicate and
  order before `step`; preserve contiguous physical sequence/minimum-sequence
  updates for every message. Move `check_batch`, ack matching, allocation,
  logical batch retention and DDS dispatch behind `Complete`. Pass its decoded
  batch into `handle_operation` instead of decoding again. Preserve existing
  grouped atomicity and all own-ack/resubmission identity checks. System
  handlers still run; `handle_leave` clears only that sender's partial stream.
  Supply the post-leave state in `Step` before persistence snapshots it.
- [x] **Integrate summary state in the same commit.** Read/write optional
  `/.chunks` with the exact `[sender, string[]][]` shape; seed `Core.inbound`
  from it. `advance_inbound` advances physical attributes/last-message data
  once, uses `Complete.batch` for GC/batch changes, and snapshots post-step
  partials. Never feed a raw compressed/chunked payload into GC decoding.
  Preserve compression capability flags and existing permitted metadata.
  Keep full summary writing. Old plain `advance` uses this same mechanism
  seeded from its summary, not a second compressed reader.
- [x] **Handle compression activation, not general schema upgrades.**
  Core routing recognizes `RuntimeSchemaChange` as document metadata work,
  not a DDS edit. `advance_inbound` calls `apply_runtime_schema` once for each
  such logical item against the current persisted metadata. Validate the
  captured controller contract:
  matching schema `refSeq` accepts and stores the physical operation sequence;
  stale CAS proposals leave the schema unchanged; future/invalid references,
  unsupported versions/features and invalid feature values fail explicitly.
  Match proposal-array ordering, supported feature checks and compatibility
  information without a blind JSON merge. No GC route or tree commit is
  generated for a schema-only operation. Do not apply it separately in core
  routing and again in summary advance.
  Seeded test cores without persisted document metadata must refuse this
  operation explicitly; production document bootstrap supplies that metadata.
  Native clients do not propose unrelated feature changes.
- [x] **Switch all native ingestion together.** Initial connection messages,
  JS `buffer_bootstrap`/live delivery, BEAM `operation_message`/apply loop,
  HTTP catch-up, requestOps and Sluice frames use envelopes. Change bootstrap
  buffering types without dropping byte/count/generation protections.
  Existing plain core bootstrap entry points lift input and share the same
  internal implementation. Audit native callers of old transport decoders so
  no live or replay route still rejects/strips the outer field.
- [x] **Complete the integration matrix.** Test an out-of-order buffered final
  chunk, duplicate physical deliveries before/after completion, two senders,
  empty group, pending native edit while peer chunks arrive, grouped
  allocation/tree operations, handle-route GC updates, sender leave,
  summary-at-prefix encode/decode/tail, malformed saved prefixes and preserved
  schema flags. Include activation of compression on native-created documents,
  concurrent/stale proposals, invalid future references, and summary reload
  after activation. A failed complete batch leaves the caller's core/summary
  unchanged. Capture a real operation in a mock HTTP delta response and in
  connection initial messages, not just direct core calls.
- [x] **Run green:** repeat the two-target commands, then
  `node smoke/shared_tree_bootstrap.mjs` and
  `node smoke/shared_tree_storage.mjs`. Check all ordinary non-tree DDS
  regressions affected by the shared apply path with `just shared-tree-test`.
- [x] **Commit checkpoint:** `feat(runtime): ingest compressed peer batches`.

**Exit:** Live, bootstrap, HTTP replay, GC, and full summaries share one correct
normalization/apply path on both targets.

## Task 6: Preserve partial streams through explicit checkpoint recovery

**Dependencies:** Task 5.

**Files:** `recovery.gleam`, recovery/runtime tests, fixture helper; change
existing client probe files only if new observations are actually needed.

**Consumes:** Chunk-aware `DocumentSummary`, core normalizer state, existing
`recovery.capture(core, tenant, document)` and restore/replay entry points.

**Produces:** Existing checkpoint APIs with partial-stream preservation; no new
public checkpoint API, automatic journal, or widened pending-DDS scope.

- [x] **Write the loss-of-prefix test.** Starting from
  `core_case("partial-summary")`, ingest a strict prefix, capture, restore,
  apply the recorded tail through `handle_envelope`, and compare against
  uninterrupted application. Assert both the checkpoint summary's `/.chunks`
  and the restored normalizer contain the prefix before the tail arrives.
  Exercise the existing capture API directly:

  ```gleam
  let assert Ok(saved) = recovery.capture(partial, "default", "tree")
  let assert Ok(restore_view_id) =
    fluid_ids.stable_id("70000000-0000-4000-8000-000000000008")
  let assert Ok(restored) = recovery.restore(
    saved,
    "default",
    "tree",
    restore_view_id,
  )
  restored.inbound
    |> fluid_inbound.partial_chunks
    |> list.length
    |> expect.to_equal(1)
  ```

  Restore using the existing recovery-test session/schema setup. Do not hide
  checkpoint decoding inside a new alternate loader.
- [x] **Run red:** both targets with
  `-- shared_tree_document_recovery shared_tree_compression shared_tree_runtime`.
- [x] **Carry state through canonical and optimistic recovery cores.**
  Retain partials through the embedded document summary. Keep version 1 if
  its existing summary representation can carry the additional blob; test
  old version-1 checkpoints without that blob. If an actual outer-schema
  change is unavoidable, stop for a separately reviewed version decision
  rather than silently changing the meaning of version 1.
- [x] **Test pending-edit interactions.** Use genuine accepted-before-ack,
  never-submitted, and interleaved-pending cases with a peer chunk stream.
  A prefix must not acknowledge a native edit or allocate peer IDs early.
  After restore, complete peer state first as dictated by physical replay,
  recognize accepted logical batches once, resubmit only remaining native
  work, and continue ID allocation correctly. Test sender leave after restore,
  repeated capture, malformed/over-limit partial blobs, and restoration on
  the other target through the later live gate.
- [x] **Run green:** the two-target focused suites and
  `just shared-tree-recovery-interop`. The old gate remains unchanged evidence
  for its original contract; new cross-target chunk scenarios are Task 7.
- [x] **Commit checkpoint:** `fix(recovery): retain partial peer chunks`.

**Exit:** Explicit recovery does not silently discard an accepted peer prefix,
and existing capture exclusions/identity guarantees are intact.

## Task 7: Prove default-threshold mixed-client collaboration

**Dependencies:** Tasks 5 and 6.

**Files:** Finish `compression-interop.mjs`/tests; scoped `service.mjs`
options/tests; reuse `client-driver.mjs`, `delivery-gate.mjs` and tests.

**Consumes:** Existing `openSession`, genuine upstream driver sessions,
`startClient`, explicit checkpoint commands, and the extension profile.

**Produces:** `validateCompressionResults(results: unknown, runId: string,
profileDigest: string): CompressionResult[]` and command:

```bash
node tools/shared-tree-oracle/compression-interop.mjs interop --local-floodgate
```

The gate writes raw wire, controls, summaries/checkpoints and validated results
to `.output/compression/<runId>/`. It does not use `interop.mjs`'s legacy
validator or reinterpret its disabled-compression settings.

- [x] **Write validator failures before running a service.** Require the
  Cartesian product of two native targets and these six cases:

  | Case ID | Required observation |
  | --- | --- |
  | `default-compressed` | Native-created document, observed runtime schema activation by a default-configured peer, compressed unchunked traffic at 614400/204800 settings, and native edit observed by an upstream witness. |
  | `default-chunked` | Deterministic high-entropy group actually split at default settings; one logical batch after all chunks. |
  | `history-catchup` | Fresh native bootstrap consumes compressed/chunked HTTP delta history after the saved snapshot. |
  | `reconnect-pending` | Held native acknowledgement/pending work, disconnect, chunked peer progress, catch-up and exactly-once settlement. |
  | `summary-continuation` | Native summary retains capability/chunk state; fresh upstream and native readers load it, consume a tail and continue editing. |
  | `checkpoint-partial` | Capture between peer chunks, kill the native process, restore on the opposite target, consume tail, settle pending edits and continue. |

  Test missing/duplicate cells, `skipped`, stale run/profile/probe identity,
  fake compressed evidence, too-small input, a claimed chunk case with one
  physical message, missing HTTP history observation, absent process kill,
  missing upstream witness, and dropped summary/checkpoint evidence.

  ```js
  import assert from "node:assert/strict";
  import test from "node:test";
  import { validateCompressionResults } from "./compression-interop.mjs";

  test("an empty or skipped matrix cannot pass", () => {
    assert.throws(() => validateCompressionResults(
      [], "validator-only-run", "a".repeat(64),
    ), /missing|twelve|12/i);
  });
  ```

  Construct validator-only synthetic complete results for the mutation tests;
  label them synthetic and never save them as live acceptance. Each result
  requires `target`, `restoreTarget` for checkpoint cases, `caseId`, `runId`,
  `profileDigest`, `probeDigest`, `documentId`, `passed: true`, `skipped: false`
  and `evidence`. Evidence includes `runtimeOptions`, `physicalMessages`,
  `byteSizes`, `deliveredSequences`, `pendingCounts`, `commitCounts`,
  `witnessContent`, and case-specific history/summary/checkpoint observations.
- [x] **Run red:** `node --test tools/shared-tree-oracle/compression-interop.test.mjs`.
- [x] **Add a scoped runtime-options selection to `openSession`.** The new
  gate uses upstream default compression/chunk size while retaining unrelated
  legacy layout/summarizer controls. Legacy callers retain their existing
  options. Record effective options and document-schema capability flags;
  neither a smaller artificial threshold nor forcing compression off counts
  as default coverage.
- [x] **Use real traffic and deterministic control.** Reuse existing gate
  hold/release/summary injection mechanisms and genuine upstream captured
  frames. If a frame holds multiple operations, release only complete
  protocol frames and prove the selected prefix ends before the final chunk.
  Add an operation-aware hold selector only if the current controls cannot
  select that boundary; test its exact delivered/held sequence list. Never
  fabricate service sequence numbers, replace chunked traffic with native
  synthetic messages, or use sleep timing as proof. Keep separate case
  artifacts for any captured-summary injection used to select a prefix.
- [x] **Assert semantics as well as wire shapes.** Save physical sequence/CSN/
  RSN/metadata, real compressed/decoded sizes, chunk IDs/counts, final batch
  identity, delivered prefix, pending counts, commit/event counts, GC handle
  routes, schema flags, summary `/.chunks`, checkpoints and witness content.
  Bound tree-event assertions around the peer edit, excluding reconnect
  status events. Require bidirectional continuation and zero lost/duplicated
  native submissions. The opposite-target checkpoint cell is named by its
  source target and records the restore target explicitly.
- [x] **Run green:** Node validator/service/delivery-gate tests, then the live
  command above. Require **12/12** current-run cells, no skips. Save local
  service/source/extension identities and report any unsupported limits
  explicitly. Fixture or synthetic-validator results are not a live pass.
- [x] **Commit checkpoint:** `test(tree): prove compressed peer collaboration`.

**Exit:** Both target clients collaborate with actual default-compression
upstream peers across live and persisted lifecycle paths.

## Task 8: Wire release gates and publish the new boundary

**Dependencies:** Task 7.

**Files:** `justfile`, oracle `package.json`, manual interop workflow, root and
oracle READMEs, matrix and current roadmap. Keep the design/plan aligned with
any reviewed execution changes and record the accepted revision/digests.

**Consumes:** Validated extension profile/corpus and complete Task 7 artifacts.

**Produces:** `just shared-tree-compression-interop` for native tests,
compression corpus check and live acceptance; an oracle
`compression:interop` script; manual workflow execution/artifact steps.
The existing `just shared-tree-test` automatically includes the new Gleam
tests through its `shared_tree` selector.

- [x] **Write gate-command contract tests.** Assert the new recipe invokes
  both target runners and the compression gate, and the workflow uploads
  `.output/compression/` even after failure. Extend existing recipe/workflow
  tests where present; otherwise inspect the explicit invocation in review
  rather than adding a general workflow-testing framework.
- [x] **Add only the required commands:**

  ```make
  shared-tree-compression-interop:
      gleam test --target erlang -- shared_tree_compression shared_tree_runtime shared_tree_document_summary shared_tree_document_recovery
      gleam test --target javascript -- shared_tree_compression shared_tree_runtime shared_tree_document_summary shared_tree_document_recovery
      node tools/shared-tree-oracle/compression.mjs check
      node tools/shared-tree-oracle/compression-interop.mjs interop --local-floodgate
  ```

  Add a manual workflow step calling that recipe and the compression artifact
  directory. Do not automatically dispatch a hosted run or change the old
  profile's service checks.
- [x] **Run targeted release acceptance:**

  ```bash
  node tools/shared-tree-oracle/source.mjs verify
  npm --prefix tools/shared-tree-oracle test
  just shared-tree-test
  just shared-tree-compression-interop
  just shared-tree-interop
  just shared-tree-create-interop
  just shared-tree-layout-interop
  just shared-tree-lifecycle-interop
  just shared-tree-recovery-interop
  just shared-tree-alias-interop
  ```

  These existing client/layout/lifecycle/recovery gates cover the shared
  ingress/persistence paths modified here. Do not rerun source generation to
  make unrelated historical fixtures appear fresh.
- [x] **Run final repository regression because core ingestion changed:**
  `just build`, `just test`, and `just lint`. Repair regressions caused by this
  work. Missing required service/tooling is a blocked gate, not a passed skip.
- [x] **Publish narrowly.** Change R03 from refusal to the exact supported
  inbound forms/limits and new evidence. Qualify R09/R11/R12 with chunk state
  and recovery proof. R04 incremental FieldBatch support stays unchanged.
  Explain uncompressed native outbound, the preserved legacy profile, new
  extension digest, excluded historical forms, and unchanged server scope.
  Record default-setting **12/12** local acceptance only if observed; hosted
  status stays unclaimed unless separately dispatched and completed.
- [x] **Inspect and commit:** confirm the frozen profile checksum, new
  deterministic generation check, links, `git diff --check`, complete diff
  and expected file list. Commit only implementation-owned files with
  `feat(tree): publish compressed inbound compatibility`. Do not amend
  historical acceptance or add co-author trailers.

**Exit:** The new claim is durable, discoverable, reproducible, and bounded.
Runtime operation compression is no longer blocked merely by an ordinary
peer's default size-triggered behavior within this extension profile.

## Dependency and review checkpoints

Task 1 precedes envelope and decoder work. Tasks 2 and 3 can be developed
independently after the capture, but share the compression test file: keep one
owner or coordinate an explicit handoff. Task 4 joins them; Tasks 5-8 are
sequential. No fleet-wide parallel runtime edit is appropriate.

Review each commit against its exit condition before continuing. In particular:
Task 1 fixes the producer dialect; Task 3 rejects quadratic decoding; Task 5
must include summary/GC integration with core support; Task 6 must preserve
prefixes rather than refuse all mid-stream checkpoints; Task 7 must prove real
default-triggered wire behavior; Task 8 alone publishes support.

The next implementation plan after acceptance addresses ordinary upstream
snapshot/reference consumption through storage bootstrap. It is not another
compression layer, a native outbound optimization, or an incremental writer.
