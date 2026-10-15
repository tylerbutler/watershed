import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";

import {
  benchmarkFrameIds,
  median,
  validateBenchmarkReport,
  validateCompressionResults,
} from "./compression-interop.mjs";

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
    payloadBytes: chunked ? 180_000 : 180_000,
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
        sourceBytes: 900_000,
        compressedBytes: caseId === "default-compressed" ? 180_000 : 540_000,
        decodedBytes: 900_000,
        highEntropyInputBytes: 900_000,
        highEntropySha256: "e".repeat(64),
      },
      deliveredSequences: {
        held: caseId === "checkpoint-partial" ? sequences.slice(1) : [],
        delivered: caseId === "checkpoint-partial" ? sequences.slice(0, 1) : sequences,
        final: sequences.at(-1),
      },
      pendingCounts: { before: 1, held: 1, after: 0 },
      commitCounts: {
        peerLogicalBatches: 1,
        nativeSubmitted: 1,
        nativeSettled: 1,
        witnessObserved: 1,
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
      },
      history: {
        transport: "http-delta",
        requestedFrom: 81,
        requestedTo: 103,
        compressedSequences: sequences,
      },
      reconnect: {
        acknowledgementHeld: true,
        disconnected: true,
        caughtUpThrough: 103,
        settledExactlyOnce: true,
        submissionOccurrences: 1,
      },
      summary: {
        nativeHandle: "summary-validator",
        capabilityRetained: true,
        chunksPath: "/.chunks",
        chunkStreams: [{
          clientId: `upstream-${target}-${caseId}`,
          pieces: ["prefix"],
        }],
        upstreamRead: true,
        nativeRead: true,
        tailConsumed: true,
        continuedEditing: true,
      },
      checkpoint: {
        artifact: `${target}-${caseId}.checkpoint.json`,
        strictPrefix: sequences.slice(0, 1),
        heldSuffix: sequences.slice(1),
        prefixEndsBeforeFinalChunk: true,
        processSignal: "SIGKILL",
        processExited: true,
        restoredTarget: restoreTarget,
        tailConsumed: true,
        pendingSettled: true,
        continuedEditing: true,
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
  assert.throws(() => validateCompressionResults(
    [], validatorRunId, validatorProfileDigest,
  ), /missing|twelve|12/i);
  const skipped = syntheticCompleteResults();
  skipped[0].skipped = true;
  assert.throws(() => validateCompressionResults(
    skipped, validatorRunId, validatorProfileDigest,
  ), /skipped/i);
});

test("accepts a complete explicitly synthetic validator-only matrix", () => {
  const results = syntheticCompleteResults();
  assert.equal(validateCompressionResults(
    results, validatorRunId, validatorProfileDigest,
  ), results);
});

test("rejects missing and duplicate matrix cells", () => {
  const missing = syntheticCompleteResults();
  missing.pop();
  assert.throws(() => validateCompressionResults(
    missing, validatorRunId, validatorProfileDigest,
  ), /missing|twelve|12/i);

  const duplicate = syntheticCompleteResults();
  duplicate[11] = structuredClone(duplicate[0]);
  assert.throws(() => validateCompressionResults(
    duplicate, validatorRunId, validatorProfileDigest,
  ), /duplicate/i);
});

test("rejects stale run, profile, probe, source, and extension identities", () => {
  for (const [field, value] of [
    ["runId", "stale-run"],
    ["profileDigest", "1".repeat(64)],
    ["probeDigest", "not-a-digest"],
    ["sourceDigest", "not-a-revision"],
    ["extensionDigest", "not-a-digest"],
  ]) {
    const results = syntheticCompleteResults();
    results[0][field] = value;
    assert.throws(() => validateCompressionResults(
      results, validatorRunId, validatorProfileDigest,
    ), new RegExp(field, "i"));
  }
});

test("rejects fake compressed and undersized chunk evidence", () => {
  const uncompressed = syntheticCompleteResults();
  uncompressed[0].evidence.physicalMessages[0].compression = null;
  assert.throws(() => validateCompressionResults(
    uncompressed, validatorRunId, validatorProfileDigest,
  ), /compression|lz4/i);

  const tooSmall = syntheticCompleteResults();
  const chunked = tooSmall.find(({ caseId }) => caseId === "default-chunked");
  chunked.evidence.byteSizes.compressedBytes = 200_000;
  assert.throws(() => validateCompressionResults(
    tooSmall, validatorRunId, validatorProfileDigest,
  ), /chunk|204800|compressed/i);

  const onePhysical = syntheticCompleteResults();
  const one = onePhysical.find(({ caseId }) => caseId === "default-chunked");
  one.evidence.physicalMessages = one.evidence.physicalMessages.slice(-1);
  one.evidence.deliveredSequences.delivered =
    one.evidence.physicalMessages.map(({ sequenceNumber }) => sequenceNumber);
  assert.throws(() => validateCompressionResults(
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
    assert.throws(() => validateCompressionResults(
      results, validatorRunId, validatorProfileDigest,
    ), pattern);
  }
});

test("ties delivered sequences, bytes, chunk IDs, batches, and literal witness hashes to observations", () => {
  for (const mutate of [
    (cell) => cell.evidence.deliveredSequences.final = 999,
    (cell) => cell.evidence.physicalMessages[1].chunkId = 3,
    (cell) => cell.evidence.physicalMessages[2].batchId = "different-batch",
    (cell) => cell.evidence.byteSizes.compressedBytes = 700_000,
    (cell) => cell.evidence.witnessContent.sha256 = "bad",
    (cell) => cell.evidence.commitCounts.peerLogicalBatches = 2,
  ]) {
    const results = syntheticCompleteResults();
    const cell = results.find(({ target, caseId }) =>
      target === "javascript" && caseId === "default-chunked");
    mutate(cell);
    assert.throws(() => validateCompressionResults(
      results, validatorRunId, validatorProfileDigest,
    ), /sequence|chunk|batch|bytes|hash|logical/i);
  }
});
