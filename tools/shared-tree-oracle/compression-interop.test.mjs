import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  benchmarkFrameIds,
  median,
  validateBenchmarkReport,
  validateCompressionFixtureResults,
  validateCompressionResults,
} from "./compression-interop.mjs";

const directory = dirname(fileURLToPath(import.meta.url));
const repository = resolve(directory, "../..");
const validatorRunId = "validator-only-run";
const validatorProfileDigest = "a".repeat(64);
const validatorProbeDigest = "b".repeat(64);
const validatorSourceDigest = "c".repeat(40);
const validatorExtensionDigest = "d".repeat(64);
const cases = [
  "default-compressed",
  "default-chunked",
  "history-catchup",
  "reconnect-pending",
  "summary-continuation",
  "checkpoint-partial",
];

function syntheticPhysicalMessages(caseId, target) {
  const chunked = caseId !== "default-compressed";
  const count = chunked ? 3 : 1;
  return Array.from({ length: count }, (_, index) => ({
    sequenceNumber: 100 + index,
    clientSequenceNumber: 20 + index,
    referenceSequenceNumber: 99,
    clientId: `upstream-${target}-${caseId}`,
    type: "op",
    compression: index === count - 1 ? "lz4" : null,
    metadata: { batch: index === count - 1 },
    contentsType: chunked ? "chunkedOp" : "groupedBatch",
    wirePayloadBytes: chunked ? 180_100 : 180_100,
    chunkPieceBytes: chunked ? 180_000 : null,
    chunkPieceSha256: chunked ? `${index + 1}`.repeat(64).slice(0, 64) : null,
    chunkId: chunked ? index + 1 : null,
    totalChunks: chunked ? count : null,
    batchId: `${target}-${caseId}-batch`,
  }));
}

function syntheticCell(target, caseId) {
  const restoreTarget = target === "javascript" ? "erlang" : "javascript";
  const physicalMessages = syntheticPhysicalMessages(caseId, target);
  const sequences = physicalMessages.map(({ sequenceNumber }) => sequenceNumber);
  const cell = {
    artifactKind: "validator-only-synthetic",
    target,
    ...(caseId === "checkpoint-partial" ? { restoreTarget } : {}),
    caseId,
    runId: validatorRunId,
    profileDigest: validatorProfileDigest,
    probeDigest: validatorProbeDigest,
    sourceDigest: validatorSourceDigest,
    extensionDigest: validatorExtensionDigest,
    documentId: `validator-${target}-${caseId}`,
    passed: true,
    skipped: false,
    evidence: {
      runtimeOptions: {
        mode: "default-compression",
        minimumBatchSizeInBytes: 614400,
        chunkSizeInBytes: 204800,
        compressionAlgorithm: "lz4",
        summarizerHeuristics: "legacy-preserved",
      },
      capability: {
        schemaActivationObserved: true,
        compressionEnabled: true,
        refSeq: 80,
      },
      physicalMessages,
      byteSizes: {
        sourceUtf8Bytes: 900_000,
        lz4FrameBytes: caseId === "default-compressed" ? 135_000 : 405_000,
        packedContentsBase64Bytes:
          caseId === "default-compressed" ? 180_000 : 540_000,
        physicalWirePayloadBytes:
          caseId === "default-compressed" ? 180_100 : 540_300,
        decodedRuntimeBytes: 900_900,
        decodedRuntimeSha256: "f".repeat(64),
        sourceSha256: "e".repeat(64),
      },
      deliveredSequences: {
        held: caseId === "checkpoint-partial" ? sequences.slice(1) : [],
        delivered: caseId === "checkpoint-partial" ? sequences.slice(0, 1) : sequences,
        final: sequences.at(-1),
        complete: caseId !== "checkpoint-partial",
      },
      pendingCounts: { before: 1, held: 1, after: 0 },
      commitCounts: {
        peerLogicalBatches: 1,
        peerTreeEvents: 1,
        peerCommitEvents: 1,
        peerRevisions: ["peer-edit"],
        nativeSubmissionOccurrences: 1,
        nativeLocalCommits: 1,
        nativeSettlements: 1,
        nativeActionId: `native-${target}-${caseId}`,
        settledActionId: `native-${target}-${caseId}`,
        nativeSubmissionIdentity: `submission-${target}-${caseId}`,
        settledSubmissionIdentity: `submission-${target}-${caseId}`,
        witnessCommitEvents: 1,
      },
      logicalBatch: {
        baselineSequenceNumber: 99,
        completedSequenceNumber: sequences.at(-1),
        pendingPositionsAfter: 0,
        prefixObservations: sequences.slice(0, -1).map((sequenceNumber) => ({
          sequenceNumber,
          treeSha256: "1".repeat(64),
          events: 0,
          commits: 0,
        })),
        baselineTreeSha256: "1".repeat(64),
        completedTreeSha256: "2".repeat(64),
      },
      finalBatchIdentity: `${target}-${caseId}-batch`,
      gcRoutes: ["/", "/default"],
      schemaFlags: { compression: true, idCompressor: true },
      witnessContent: {
        literal: `peer-${caseId}|native-${target}`,
        sha256: createHash("sha256")
          .update(`peer-${caseId}|native-${target}`)
          .digest("hex"),
        peerEdit: `peer-${caseId}`,
        nativeEdit: `native-${target}`,
      },
      bidirectionalEdits: {
        peerObservedByNative: true,
        nativeObservedByWitness: true,
        nativeTreeMatchesUpstream: true,
        witnessTreeMatchesNative: true,
      },
      history: {
        transport: "http-delta",
        requestedFrom: 81,
        requestedTo: 103,
        compressedSequences: sequences,
        consumedThrough: sequences.at(-1),
        requests: [{
          method: "GET",
          path: `/deltas/fluid/document?from=81&to=103`,
          status: 200,
          responseEnvelopes: sequences.map((sequenceNumber) => ({ sequenceNumber })),
        }],
      },
      reconnect: {
        acknowledgementHeld: true,
        disconnected: true,
        caughtUpThrough: 103,
        settledExactlyOnce: true,
        submissionOccurrences: 1,
        pendingActionId: `native-${target}-${caseId}`,
        settledActionId: `native-${target}-${caseId}`,
        peerContentSha256: "e".repeat(64),
      },
      summary: {
        nativeHandle: "summary-validator",
        snapshotSequenceNumber: sequences.at(-2),
        capabilityRetained: true,
        chunksPath: "/.chunks",
        chunkStreams: [{
          clientId: `upstream-${target}-${caseId}`,
          pieceSha256: physicalMessages.slice(0, -1)
            .map(({ chunkPieceSha256 }) => chunkPieceSha256),
        }],
        publishedChunkStreams: [{
          clientId: `upstream-${target}-${caseId}`,
          pieceSha256: physicalMessages.slice(0, -1)
            .map(({ chunkPieceSha256 }) => chunkPieceSha256),
        }],
        selectedPrefix: sequences.slice(0, -1),
        heldFinal: sequences.at(-1),
        consumedWatermark: sequences.at(-2),
        upstreamRead: true,
        nativeRead: true,
        tailConsumed: true,
        continuedEditing: true,
        upstreamTreeSha256: "2".repeat(64),
        nativeTreeSha256: "2".repeat(64),
      },
      checkpoint: {
        artifact: `${target}-${caseId}.checkpoint.json`,
        strictPrefix: sequences.slice(0, 1),
        heldSuffix: sequences.slice(1),
        summarySequenceNumber: sequences[0],
        consumedWatermark: sequences[0],
        chunkStreams: [{
          clientId: `upstream-${target}-${caseId}`,
          pieceSha256: [physicalMessages[0].chunkPieceSha256],
        }],
        prefixEndsBeforeFinalChunk: true,
        processSignal: "SIGKILL",
        processExited: true,
        processPid: 12345,
        processExitCode: null,
        restoredTarget: restoreTarget,
        tailConsumed: true,
        pendingSettled: true,
        continuedEditing: true,
        restoredTreeSha256: "2".repeat(64),
      },
    },
  };
  return cell;
}

function syntheticCompleteResults() {
  return ["javascript", "erlang"].flatMap((target) =>
    cases.map((caseId) => syntheticCell(target, caseId)));
}

test("benchmarks the captured exact-size producer frames", () => {
  assert.deepEqual(benchmarkFrameIds, ["benchmark-1mib", "benchmark-4mib"]);
});

test("uses the middle of seven ordered measurements", () => {
  assert.equal(median([9, 7, 3, 5, 1, 11, 13]), 7);
});

test("requires validated output and linear-enough target scaling", () => {
  const report = {
    targets: {
      javascript: {
        "benchmark-1mib": { samplesMicroseconds: [1, 2, 3, 4, 5, 6, 7], medianMicroseconds: 4, outputMatches: true },
        "benchmark-4mib": { samplesMicroseconds: [8, 9, 10, 11, 12, 13, 14], medianMicroseconds: 11, outputMatches: true },
        ratio4MiBTo1MiB: 2.75,
      },
      erlang: {
        "benchmark-1mib": { samplesMicroseconds: [2, 3, 4, 5, 6, 7, 8], medianMicroseconds: 5, outputMatches: true },
        "benchmark-4mib": { samplesMicroseconds: [12, 13, 14, 15, 16, 17, 18], medianMicroseconds: 15, outputMatches: true },
        ratio4MiBTo1MiB: 3,
      },
    },
  };
  assert.equal(validateBenchmarkReport(report), report);

  const quadratic = structuredClone(report);
  quadratic.targets.javascript.ratio4MiBTo1MiB = 8.01;
  assert.throws(() => validateBenchmarkReport(quadratic), /javascript.*ratio/i);

  const wrongOutput = structuredClone(report);
  wrongOutput.targets.erlang["benchmark-4mib"].outputMatches = false;
  assert.throws(() => validateBenchmarkReport(wrongOutput), /erlang.*output/i);
});

test("an empty or skipped matrix cannot pass", () => {
  assert.throws(() => validateCompressionFixtureResults(
    [], validatorRunId, validatorProfileDigest,
  ), /missing|twelve|12/i);
  const skipped = syntheticCompleteResults();
  skipped[0].skipped = true;
  assert.throws(() => validateCompressionFixtureResults(
    skipped, validatorRunId, validatorProfileDigest,
  ), /skipped/i);
});

test("accepts a complete explicitly synthetic validator-only matrix", () => {
  const results = syntheticCompleteResults();
  assert.equal(validateCompressionFixtureResults(
    results, validatorRunId, validatorProfileDigest,
  ), results);
  assert.throws(() => validateCompressionResults(
    results, validatorRunId, validatorProfileDigest,
  ), /artifactKind|live/i);
});

test("rejects missing and duplicate matrix cells", () => {
  const missing = syntheticCompleteResults();
  missing.pop();
  assert.throws(() => validateCompressionFixtureResults(
    missing, validatorRunId, validatorProfileDigest,
  ), /missing|twelve|12/i);

  const duplicate = syntheticCompleteResults();
  duplicate[11] = structuredClone(duplicate[0]);
  assert.throws(() => validateCompressionFixtureResults(
    duplicate, validatorRunId, validatorProfileDigest,
  ), /duplicate/i);
});

test("live validation binds identities to current verified inputs", () => {
  const profileDigest = createHash("sha256").update(readFileSync(resolve(
    repository, "test/fixtures/shared_tree/compression-profile.json",
  ))).digest("hex");
  const corpus = JSON.parse(readFileSync(resolve(
    repository, "test/fixtures/shared_tree/compression.json",
  )));
  const current = {
    probeDigest: corpus.probe.digest,
    sourceDigest: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
    extensionDigest: createHash("sha256").update(readFileSync(resolve(
      repository, "test/fixtures/shared_tree/compression.json",
    ))).digest("hex"),
  };
  for (const [field, value] of [
    ["runId", "stale-run"],
    ["profileDigest", "1".repeat(64)],
    ["probeDigest", "0".repeat(64)],
    ["sourceDigest", "0".repeat(40)],
    ["extensionDigest", "0".repeat(64)],
  ]) {
    const results = syntheticCompleteResults();
    for (const result of results) {
      result.artifactKind = "live";
      result.profileDigest = profileDigest;
      Object.assign(result, current);
    }
    results[0][field] = value;
    assert.throws(() => validateCompressionResults(
      results, validatorRunId, profileDigest,
    ), new RegExp(field, "i"));
  }
});

test("relabeling synthetic rows cannot pass live validation", () => {
  const results = syntheticCompleteResults();
  for (const result of results) result.artifactKind = "live";
  assert.throws(() => validateCompressionResults(
    results, validatorRunId, validatorProfileDigest,
  ), /profileDigest|probeDigest|sourceDigest|extensionDigest|provenance/i);
});

test("rejects fake compressed and undersized chunk evidence", () => {
  const uncompressed = syntheticCompleteResults();
  uncompressed[0].evidence.physicalMessages[0].compression = null;
  assert.throws(() => validateCompressionFixtureResults(
    uncompressed, validatorRunId, validatorProfileDigest,
  ), /compression|lz4/i);

  const tooSmall = syntheticCompleteResults();
  const chunked = tooSmall.find(({ caseId }) => caseId === "default-chunked");
  chunked.evidence.byteSizes.lz4FrameBytes = 200_000;
  assert.throws(() => validateCompressionFixtureResults(
    tooSmall, validatorRunId, validatorProfileDigest,
  ), /chunk|204800|compressed/i);

  const onePhysical = syntheticCompleteResults();
  const one = onePhysical.find(({ caseId }) => caseId === "default-chunked");
  one.evidence.physicalMessages = one.evidence.physicalMessages.slice(-1);
  one.evidence.deliveredSequences.delivered =
    one.evidence.physicalMessages.map(({ sequenceNumber }) => sequenceNumber);
  assert.throws(() => validateCompressionFixtureResults(
    onePhysical, validatorRunId, validatorProfileDigest,
  ), /physical|chunk/i);
});

test("rejects missing case-specific HTTP, reconnect, witness, summary, and checkpoint proof", () => {
  for (const [caseId, field, pattern] of [
    ["history-catchup", "history", /history|http/i],
    ["reconnect-pending", "reconnect", /reconnect|acknowledgement/i],
    ["default-compressed", "witnessContent", /witness/i],
    ["summary-continuation", "summary", /summary|chunks/i],
    ["checkpoint-partial", "checkpoint", /checkpoint|kill|SIGKILL/i],
  ]) {
    const results = syntheticCompleteResults();
    const cell = results.find((entry) =>
      entry.target === "javascript" && entry.caseId === caseId);
    delete cell.evidence[field];
    assert.throws(() => validateCompressionFixtureResults(
      results, validatorRunId, validatorProfileDigest,
    ), pattern);
  }
});

test("ties delivered sequences, bytes, chunk IDs, batches, and literal witness hashes to observations", () => {
  for (const mutate of [
    (cell) => cell.evidence.deliveredSequences.final = 999,
    (cell) => cell.evidence.physicalMessages[1].chunkId = 3,
    (cell) => cell.evidence.physicalMessages[2].batchId = "different-batch",
    (cell) => cell.evidence.byteSizes.physicalWirePayloadBytes = 700_000,
    (cell) => cell.evidence.byteSizes.decodedRuntimeBytes = 1,
    (cell) => cell.evidence.witnessContent.sha256 = "bad",
    (cell) => cell.evidence.commitCounts.peerLogicalBatches = 2,
  ]) {
    const results = syntheticCompleteResults();
    const cell = results.find(({ target, caseId }) =>
      target === "javascript" && caseId === "default-chunked");
    mutate(cell);
    assert.throws(() => validateCompressionFixtureResults(
      results, validatorRunId, validatorProfileDigest,
    ), /sequence|chunk|batch|bytes|hash|logical/i);
  }
});

test("rejects contradictory delivery, history, reconnect, summary, and checkpoint lifecycles", () => {
  const mutations = [
    ["default-chunked", (cell) => {
      cell.evidence.deliveredSequences.delivered = [];
      cell.evidence.deliveredSequences.held =
        cell.evidence.physicalMessages.map(({ sequenceNumber }) => sequenceNumber);
    }, /complete|delivered|held/i],
    ["default-chunked", (cell) => {
      cell.evidence.deliveredSequences.delivered.push(
        cell.evidence.deliveredSequences.delivered[0],
      );
    }, /duplicate|partition/i],
    ["history-catchup", (cell) => {
      cell.evidence.history.requests = [];
    }, /request|http/i],
    ["history-catchup", (cell) => {
      cell.evidence.history.requests[0].responseEnvelopes = [];
    }, /response|sequence/i],
    ["reconnect-pending", (cell) => {
      cell.evidence.reconnect.caughtUpThrough =
        cell.evidence.physicalMessages[0].sequenceNumber;
    }, /catch-up|final/i],
    ["summary-continuation", (cell) => {
      cell.evidence.summary.chunkStreams[0].clientId = "unrelated-sender";
    }, /sender|client/i],
    ["summary-continuation", (cell) => {
      cell.evidence.summary.publishedChunkStreams[0].pieceSha256 = ["0".repeat(64)];
    }, /published|piece|prefix/i],
    ["checkpoint-partial", (cell) => {
      cell.evidence.checkpoint.summarySequenceNumber =
        cell.evidence.checkpoint.strictPrefix[0] - 1;
    }, /summary|prefix|watermark/i],
  ];
  for (const [caseId, mutate, pattern] of mutations) {
    const results = syntheticCompleteResults();
    const cell = results.find(({ target, caseId: current }) =>
      target === "javascript" && current === caseId);
    mutate(cell);
    assert.throws(() => validateCompressionFixtureResults(
      results, validatorRunId, validatorProfileDigest,
    ), pattern);
  }
});
