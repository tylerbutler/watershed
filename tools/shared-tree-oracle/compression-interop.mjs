import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { readFileSync, readdirSync } from "node:fs";
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { runCreatorProbe } from "./creation.mjs";
import {
  nativeAdapter,
  publishUpstreamSummary,
  serverHistory,
  until,
  upstreamAdapter,
} from "./interop-scenarios.mjs";
import {
  cleanupOwned,
  openSession,
  snapshot,
  tokenProvider,
  withLocalFloodgate,
} from "./service.mjs";

export const benchmarkFrameIds = ["benchmark-1mib", "benchmark-4mib"];

const directory = dirname(fileURLToPath(import.meta.url));
const repository = resolve(directory, "../..");
const fixturePath = resolve(repository, "test/fixtures/shared_tree/compression.json");
const outputDirectory = resolve(directory, ".output/compression");
const reportPath = resolve(outputDirectory, "benchmark.json");
const inputsDirectory = resolve(outputDirectory, "benchmark-inputs");
const warmupCount = 2;
const timedCount = 7;
const maxRatio = 8;
const maxOutputBytes = 16 * 1024 * 1024;
const spillwayRevision = "25f515cf67027e4b2db2344c3abb2141056e45fc";
const floodgateRevision = "0eb493fc46d1bb9baf1151a6ccdde93544e057e7";
const legacyProfileSha256 =
  "29fe106785ec1705cd1ac4d45de8e88f9a6cc89487c3b7cd1df6ad65b318b1de";
const compressionTargets = ["javascript", "erlang"];
const compressionCases = [
  "default-compressed",
  "default-chunked",
  "history-catchup",
  "reconnect-pending",
  "summary-continuation",
  "checkpoint-partial",
];
const defaultCompressionThreshold = 614400;
const defaultChunkSize = 204800;
const fluidSourceRevision = "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960";
const require = createRequire(import.meta.url);
const lz4js = require("lz4js");
const currentProfileBytes = readFileSync(resolve(
  repository, "test/fixtures/shared_tree/compression-profile.json",
));
const currentCorpusBytes = readFileSync(fixturePath);
const currentCorpus = JSON.parse(currentCorpusBytes);
const currentCompressionIdentity = Object.freeze({
  profileDigest: createHash("sha256").update(currentProfileBytes).digest("hex"),
  probeDigest: currentCorpus.probe.digest,
  sourceDigest: fluidSourceRevision,
  extensionDigest: createHash("sha256").update(currentCorpusBytes).digest("hex"),
});

function fail(message) {
  throw new Error(message);
}

export function median(samples) {
  if (samples.length === 0) fail("median requires samples");
  const ordered = samples.slice().sort((left, right) => left - right);
  return ordered[Math.floor(ordered.length / 2)];
}

export function validateBenchmarkReport(report) {
  for (const [target, measurements] of Object.entries(report.targets ?? {})) {
    for (const id of benchmarkFrameIds) {
      const measurement = measurements[id];
      if (!measurement || measurement.samplesMicroseconds?.length !== timedCount) {
        fail(`${target} ${id} must contain seven timed samples`);
      }
      if (measurement.outputMatches !== true) {
        fail(`${target} ${id} output did not match the captured producer bytes`);
      }
      if (measurement.medianMicroseconds !== median(measurement.samplesMicroseconds)) {
        fail(`${target} ${id} median does not match its samples`);
      }
    }
    const expectedRatio =
      measurements["benchmark-4mib"].medianMicroseconds /
      measurements["benchmark-1mib"].medianMicroseconds;
    if (Math.abs(measurements.ratio4MiBTo1MiB - expectedRatio) > 1e-12) {
      fail(`${target} ratio does not match its medians`);
    }
    if (measurements.ratio4MiBTo1MiB > maxRatio) {
      fail(`${target} ratio exceeds ${maxRatio}`);
    }
  }
  for (const target of ["javascript", "erlang"]) {
    if (!report.targets?.[target]) fail(`missing ${target} benchmark`);
  }
  return report;
}

function object(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail(`${label} must be an object`);
  }
  return value;
}

function array(value, label) {
  if (!Array.isArray(value)) fail(`${label} must be an array`);
  return value;
}

function string(value, label) {
  if (typeof value !== "string" || value.length === 0) {
    fail(`${label} must be a nonempty string`);
  }
  return value;
}

function integer(value, label) {
  if (!Number.isSafeInteger(value)) fail(`${label} must be an integer`);
  return value;
}

function digestString(value, length, label) {
  if (typeof value !== "string"
    || value.length !== length
    || !/^[0-9a-f]+$/.test(value)) {
    fail(`${label} must be a ${length}-character lowercase hexadecimal digest`);
  }
  return value;
}

function positiveInteger(value, label) {
  if (integer(value, label) <= 0) fail(`${label} must be positive`);
  return value;
}

function nonnegativeInteger(value, label) {
  if (integer(value, label) < 0) fail(`${label} must be nonnegative`);
  return value;
}

function exactTrue(value, label) {
  if (value !== true) fail(`${label} must be true`);
}

function validateRuntimeOptions(evidence, label) {
  const options = object(evidence.runtimeOptions, `${label} runtimeOptions`);
  if (options.mode !== "default-compression"
    || options.minimumBatchSizeInBytes !== defaultCompressionThreshold
    || options.chunkSizeInBytes !== defaultChunkSize
    || options.compressionAlgorithm !== "lz4") {
    fail(`${label} runtimeOptions do not record Fluid 3.1.0 defaults`);
  }
  string(options.summarizerHeuristics, `${label} summarizerHeuristics`);
  const capability = object(evidence.capability, `${label} capability`);
  exactTrue(capability.schemaActivationObserved, `${label} schema activation`);
  exactTrue(capability.compressionEnabled, `${label} compression capability`);
  integer(capability.refSeq, `${label} capability refSeq`);
  const schemaFlags = object(evidence.schemaFlags, `${label} schemaFlags`);
  exactTrue(schemaFlags.compression, `${label} schema compression flag`);
  exactTrue(schemaFlags.idCompressor, `${label} schema ID compressor flag`);
}

function validatePhysicalEvidence(evidence, label, caseId) {
  const messages = array(evidence.physicalMessages, `${label} physicalMessages`);
  if (messages.length === 0) fail(`${label} has no physical messages`);
  const seenSequences = new Set();
  const batchIds = new Set();
  let physicalWirePayloadBytes = 0;
  for (const [index, entry] of messages.entries()) {
    const message = object(entry, `${label} physical message ${index}`);
    const sequence = positiveInteger(
      message.sequenceNumber,
      `${label} physical sequence ${index}`,
    );
    if (seenSequences.has(sequence)) fail(`${label} duplicates physical sequence ${sequence}`);
    seenSequences.add(sequence);
    integer(message.clientSequenceNumber, `${label} physical CSN ${index}`);
    integer(message.referenceSequenceNumber, `${label} physical RSN ${index}`);
    string(message.clientId, `${label} physical clientId ${index}`);
    if (message.type !== "op") fail(`${label} physical message ${index} is not an operation`);
    object(message.metadata, `${label} physical metadata ${index}`);
    physicalWirePayloadBytes += positiveInteger(
      message.wirePayloadBytes,
      `${label} physical wire payload bytes ${index}`,
    );
    batchIds.add(string(message.batchId, `${label} physical batch identity ${index}`));
  }
  if (batchIds.size !== 1
    || !batchIds.has(string(evidence.finalBatchIdentity, `${label} final batch identity`))) {
    fail(`${label} physical messages do not share the final batch identity`);
  }
  const compressed = messages.filter(({ compression }) => compression === "lz4");
  if (compressed.length === 0) fail(`${label} has no observed lz4 compression`);
  const sizes = object(evidence.byteSizes, `${label} byteSizes`);
  const sourceBytes = positiveInteger(
    sizes.sourceUtf8Bytes,
    `${label} source UTF-8 bytes`,
  );
  const frameBytes = positiveInteger(sizes.lz4FrameBytes, `${label} LZ4 frame bytes`);
  const packedBytes = positiveInteger(
    sizes.packedContentsBase64Bytes,
    `${label} packedContents base64 bytes`,
  );
  const wireBytes = positiveInteger(
    sizes.physicalWirePayloadBytes,
    `${label} physical wire payload bytes`,
  );
  const decodedBytes = positiveInteger(
    sizes.decodedRuntimeBytes,
    `${label} decoded runtime bytes`,
  );
  digestString(sizes.decodedRuntimeSha256, 64, `${label} decoded runtime hash`);
  digestString(sizes.sourceSha256, 64, `${label} source hash`);
  if (sourceBytes <= defaultCompressionThreshold
    || decodedBytes <= defaultCompressionThreshold) {
    fail(`${label} serialized input did not cross the default compression threshold`);
  }
  if (physicalWirePayloadBytes !== wireBytes) {
    fail(`${label} wire bytes do not match observed physical payload bytes`);
  }
  if (frameBytes >= packedBytes || packedBytes >= wireBytes) {
    fail(`${label} LZ4, packed, and physical wire byte measures are inconsistent`);
  }
  const chunked = caseId !== "default-compressed";
  if (chunked) {
    if (messages.length < 2 || frameBytes <= defaultChunkSize) {
      fail(`${label} chunk evidence does not cross ${defaultChunkSize} bytes`);
    }
    messages.forEach((message, index) => {
      if (message.contentsType !== "chunkedOp"
        || message.chunkId !== index + 1
        || message.totalChunks !== messages.length
        || !Number.isSafeInteger(message.chunkPieceBytes)
        || message.chunkPieceBytes < 0
        || typeof message.chunkPieceSha256 !== "string"
        || !/^[0-9a-f]{64}$/.test(message.chunkPieceSha256)) {
        fail(`${label} physical chunk ${index} has invalid chunk IDs or count`);
      }
    });
  } else {
    if (messages.length !== 1 || frameBytes > defaultChunkSize
      || messages[0].contentsType === "chunkedOp") {
      fail(`${label} compressed unchunked evidence is invalid`);
    }
  }
  const delivery = object(evidence.deliveredSequences, `${label} deliveredSequences`);
  const delivered = array(delivery.delivered, `${label} delivered sequences`);
  const held = array(delivery.held, `${label} held sequences`);
  const partition = [...delivered, ...held];
  if (new Set(partition).size !== partition.length) {
    fail(`${label} delivered and held sequences contain duplicates`);
  }
  for (const sequence of [...delivered, ...held]) {
    integer(sequence, `${label} delivered or held sequence`);
    if (!seenSequences.has(sequence)) {
      fail(`${label} delivered sequence ${sequence} is not an observed physical message`);
    }
  }
  if (partition.length !== messages.length) {
    fail(`${label} delivered and held sequences do not cover the physical messages`);
  }
  const ordered = messages.map(({ sequenceNumber }) => sequenceNumber);
  if (delivered.some((sequence, index) =>
    index > 0 && sequence <= delivered[index - 1])
    || held.some((sequence, index) => index > 0 && sequence <= held[index - 1])) {
    fail(`${label} delivered and held sequence partitions are out of order`);
  }
  if (delivery.complete === true
    && (held.length !== 0 || delivered.join(",") !== ordered.join(","))) {
    fail(`${label} complete delivery does not include every physical message`);
  }
  if (caseId !== "checkpoint-partial"
    && (delivery.complete !== true
      || held.length !== 0
      || delivered.join(",") !== ordered.join(","))) {
    fail(`${label} final delivery is not complete`);
  }
  if (delivery.final !== messages.at(-1).sequenceNumber) {
    fail(`${label} final delivered sequence does not identify the final physical message`);
  }
  return { messages, delivered, held, ordered };
}

function validateCommonSemantics(evidence, label, caseId) {
  const pending = object(evidence.pendingCounts, `${label} pendingCounts`);
  for (const field of ["before", "held", "after"]) {
    if (integer(pending[field], `${label} pending ${field}`) < 0) {
      fail(`${label} pending ${field} cannot be negative`);
    }
  }
  if (pending.after !== 0) {
    fail(`${label} pending counts do not prove settled native work`);
  }
  const commits = object(evidence.commitCounts, `${label} commitCounts`);
  const peerRevisions = array(commits.peerRevisions, `${label} peer revisions`);
  const peerTreeEvents = nonnegativeInteger(
    commits.peerTreeEvents,
    `${label} peer tree events`,
  );
  const peerCommitEvents = nonnegativeInteger(
    commits.peerCommitEvents,
    `${label} peer commit events`,
  );
  const historySettlements = nonnegativeInteger(
    commits.nativeHistorySettlements ?? 0,
    `${label} native history settlements`,
  );
  if (commits.peerLogicalBatches !== 1
    || peerRevisions.length !== 1
    || peerTreeEvents !== peerCommitEvents
    || (!["history-catchup", "checkpoint-partial"].includes(caseId)
      && peerCommitEvents !== 1)
    || (["history-catchup", "checkpoint-partial"].includes(caseId)
      && peerCommitEvents !== 0)
    || commits.nativeSubmissionOccurrences !== 1
    || commits.nativeLocalCommits !== 1
    || commits.nativeSettlements + historySettlements !== 1
    || commits.witnessCommitEvents < 1
    || string(
      commits.nativeSubmissionIdentity,
      `${label} native submission identity`,
    ) !== string(
      commits.settledSubmissionIdentity,
      `${label} settled submission identity`,
    )) {
    fail(`${label} logical commit counts do not prove exactly-once collaboration`);
  }
  if (new Set(peerRevisions.map((revision) =>
    string(revision, `${label} peer revision`))).size !== peerRevisions.length) {
    fail(`${label} peer revisions are missing or duplicated`);
  }
  const logical = object(evidence.logicalBatch, `${label} logicalBatch`);
  const baselineSequence = nonnegativeInteger(
    logical.baselineSequenceNumber,
    `${label} logical baseline sequence`,
  );
  const completedSequence = positiveInteger(
    logical.completedSequenceNumber,
    `${label} logical completion sequence`,
  );
  if (completedSequence <= baselineSequence
    || nonnegativeInteger(
      logical.pendingPositionsAfter,
      `${label} pending logical positions`,
    ) !== 0) {
    fail(`${label} logical completion and pending positions are inconsistent`);
  }
  const baselineHash = digestString(
    logical.baselineTreeSha256,
    64,
    `${label} baseline tree hash`,
  );
  const completedHash = digestString(
    logical.completedTreeSha256,
    64,
    `${label} completed tree hash`,
  );
  if (baselineHash === completedHash) fail(`${label} peer logical batch changed no tree state`);
  const baselineHistory = array(
    logical.baselineHistory,
    `${label} baseline native history`,
  );
  const baselinePendingRevisions = array(
    logical.baselinePendingRevisions,
    `${label} baseline pending revisions`,
  );
  const completedHistory = array(
    logical.completedHistory,
    `${label} completed native history`,
  );
  const newPeerHistory = array(
    logical.newPeerHistory,
    `${label} new peer native history`,
  );
  const validateHistoryPoint = (value, pointLabel) => {
    const point = object(value, pointLabel);
    string(point.revision, `${pointLabel} revision`);
    nonnegativeInteger(point.sequenceNumber, `${pointLabel} sequence`);
    nonnegativeInteger(point.indexInBatch, `${pointLabel} batch index`);
    return point;
  };
  baselineHistory.forEach((value, index) =>
    validateHistoryPoint(value, `${label} baseline history ${index}`));
  baselinePendingRevisions.forEach((revision, index) =>
    string(revision, `${label} baseline pending revision ${index}`));
  completedHistory.forEach((value, index) =>
    validateHistoryPoint(value, `${label} completed history ${index}`));
  newPeerHistory.forEach((value, index) =>
    validateHistoryPoint(value, `${label} new peer history ${index}`));
  if (baselineHistory.some(({ sequenceNumber }) =>
    sequenceNumber >= evidence.physicalMessages[0].sequenceNumber)
    || newPeerHistory.length !== 1
    || newPeerHistory[0].sequenceNumber
      !== evidence.physicalMessages.at(-1).sequenceNumber
    || completedSequence !== newPeerHistory[0].sequenceNumber
    || baselinePendingRevisions.includes(newPeerHistory[0].revision)
    || peerRevisions.join(",")
      !== newPeerHistory.map(({ revision }) => revision).join(",")) {
    fail(`${label} native history does not identify one peer commit at the final chunk`);
  }
  const baselineHistorySha256 = digestString(
    logical.baselineHistorySha256,
    64,
    `${label} baseline history hash`,
  );
  const baselineCompressorSha256 = digestString(
    logical.baselineCompressorSha256,
    64,
    `${label} baseline compressor allocation hash`,
  );
  const prefixObservations = array(
    logical.prefixObservations,
    `${label} prefix observations`,
  );
  const expectedPrefix = ["default-chunked", "summary-continuation", "checkpoint-partial"]
    .includes(caseId)
    ? evidence.physicalMessages.slice(0, -1)
      .map(({ sequenceNumber }) => sequenceNumber)
    : [];
  if (prefixObservations.map(({ sequenceNumber }) => sequenceNumber).join(",")
      !== expectedPrefix.join(",")) {
    fail(`${label} prefix observations do not cover the exact physical prefix`);
  }
  for (const observationValue of prefixObservations) {
    const observation = object(observationValue, `${label} prefix observation`);
    positiveInteger(observation.sequenceNumber, `${label} prefix sequence`);
    if (observation.treeSha256 !== baselineHash
      || observation.events !== 0
      || observation.commits !== 0
      || observation.historySha256 !== baselineHistorySha256
      || observation.compressorSha256 !== baselineCompressorSha256) {
      fail(`${label} partial chunk changed tree, events, history, or compressor allocation state`);
    }
  }
  const witness = object(evidence.witnessContent, `${label} witnessContent`);
  const literal = string(witness.literal, `${label} witness literal`);
  digestString(witness.sha256, 64, `${label} witness hash`);
  if (sha256(literal) !== witness.sha256) fail(`${label} witness literal hash does not match`);
  const peerEdit = string(witness.peerEdit, `${label} peer edit`);
  const nativeEdit = string(witness.nativeEdit, `${label} native edit`);
  if (!literal.includes(peerEdit) || !literal.includes(nativeEdit)) {
    fail(`${label} witness content does not contain both edit literals`);
  }
  const edits = object(evidence.bidirectionalEdits, `${label} bidirectionalEdits`);
  exactTrue(edits.peerObservedByNative, `${label} peer edit observed by native`);
  exactTrue(edits.nativeObservedByWitness, `${label} native edit observed by witness`);
  exactTrue(edits.nativeTreeMatchesUpstream, `${label} native tree matches upstream`);
  exactTrue(edits.witnessTreeMatchesNative, `${label} witness tree matches native`);
  const routes = array(evidence.gcRoutes, `${label} GC routes`);
  if (routes.length === 0 || !routes.every((route) =>
    typeof route === "string" && route.startsWith("/"))) {
    fail(`${label} GC routes are invalid`);
  }
}

function validateHistory(evidence, label, physicalSequences) {
  const history = object(evidence.history, `${label} history`);
  if (history.transport !== "http-delta") fail(`${label} history was not observed over HTTP`);
  integer(history.requestedFrom, `${label} history requestedFrom`);
  integer(history.requestedTo, `${label} history requestedTo`);
  if (history.requestedFrom >= history.requestedTo) fail(`${label} history range is empty`);
  const compressed = array(
    history.compressedSequences,
    `${label} compressed history sequences`,
  );
  if (compressed.length === 0
    || !compressed.every((sequence) => physicalSequences.includes(sequence))) {
    fail(`${label} HTTP history is not tied to observed compressed sequences`);
  }
  if (history.consumedThrough < physicalSequences.at(-1)) {
    fail(`${label} HTTP history was not consumed through the final compressed sequence`);
  }
  const requests = array(history.requests, `${label} history requests`);
  const matching = requests.filter((requestValue) => {
    const request = object(requestValue, `${label} history request`);
    if (request.method !== "GET" || request.status < 200 || request.status >= 300
      || typeof request.path !== "string" || !request.path.includes("/deltas/")) {
      return false;
    }
    const url = new URL(request.path, "http://localhost");
    return Number(url.searchParams.get("from")) === history.requestedFrom
      && Number(url.searchParams.get("to")) === history.requestedTo;
  });
  if (matching.length === 0) fail(`${label} has no successful matching HTTP delta request`);
  const responseSequences = matching.flatMap((request) =>
    array(request.responseEnvelopes, `${label} history response envelopes`)
      .map((envelope) => positiveInteger(
        object(envelope, `${label} history response envelope`).sequenceNumber,
        `${label} history response sequence`,
      )));
  if (responseSequences.some((sequence) =>
    sequence < history.requestedFrom || sequence >= history.requestedTo)) {
    fail(`${label} HTTP response sequence is outside the requested bounds`);
  }
  if (!compressed.every((sequence) => responseSequences.includes(sequence))) {
    fail(`${label} HTTP response envelopes do not cover compressed sequences`);
  }
}

function validateReconnect(evidence, label, physical) {
  if (evidence.pendingCounts.before < 1 || evidence.pendingCounts.held < 1) {
    fail(`${label} reconnect has no held pending native work`);
  }
  const reconnect = object(evidence.reconnect, `${label} reconnect`);
  exactTrue(reconnect.acknowledgementHeld, `${label} held acknowledgement`);
  exactTrue(reconnect.disconnected, `${label} disconnect`);
  positiveInteger(reconnect.caughtUpThrough, `${label} catch-up sequence`);
  if (reconnect.caughtUpThrough < physical.messages.at(-1).sequenceNumber) {
    fail(`${label} reconnect catch-up stops before the final physical sequence`);
  }
  exactTrue(reconnect.settledExactlyOnce, `${label} exactly-once settlement`);
  if (reconnect.submissionOccurrences !== 1) {
    fail(`${label} reconnect repeated or lost the native submission`);
  }
  if (string(reconnect.pendingActionId, `${label} pending action ID`)
      !== string(reconnect.settledActionId, `${label} settled action ID`)
    || reconnect.pendingActionId !== evidence.commitCounts.nativeActionId
    || reconnect.peerContentSha256 !== evidence.byteSizes.sourceSha256) {
    fail(`${label} reconnect did not settle the original pending identity or peer content`);
  }
}

function validateChunkStreams(streamsValue, label, physical, prefix) {
  const streams = array(streamsValue, `${label} chunk streams`);
  if (streams.length !== 1) fail(`${label} must contain one retained chunk stream`);
  const stream = object(streams[0], `${label} chunk stream`);
  if (stream.clientId !== physical.messages[0].clientId) {
    fail(`${label} chunk stream sender differs from the captured peer`);
  }
  const expected = physical.messages.slice(0, prefix.length)
    .map(({ chunkPieceSha256 }) => chunkPieceSha256);
  const pieces = array(stream.pieceSha256, `${label} chunk piece hashes`);
  pieces.forEach((piece, index) =>
    digestString(piece, 64, `${label} chunk piece hash ${index}`));
  if (pieces.join(",") !== expected.join(",")) {
    fail(`${label} chunk stream pieces do not match the selected physical prefix`);
  }
  return streams;
}

function validateSummary(evidence, label, physical) {
  const summary = object(evidence.summary, `${label} summary`);
  const nativeHandle = string(summary.nativeHandle, `${label} native summary handle`);
  if (string(summary.storedVersion, `${label} stored summary version`) !== nativeHandle
    || string(
      summary.freshNativeFetchedVersion,
      `${label} fresh native fetched summary version`,
    ) !== nativeHandle) {
    fail(`${label} summary handle is not the stored snapshot fetched by the fresh reader`);
  }
  digestString(
    summary.storedSnapshotSha256,
    64,
    `${label} stored snapshot hash`,
  );
  positiveInteger(summary.snapshotSequenceNumber, `${label} summary sequence`);
  exactTrue(summary.capabilityRetained, `${label} retained summary capability`);
  if (summary.chunksPath !== "/.chunks") fail(`${label} summary omits /.chunks`);
  const prefix = array(summary.selectedPrefix, `${label} selected summary prefix`);
  const expectedPrefix = physical.messages.slice(0, -1)
    .map(({ sequenceNumber }) => sequenceNumber);
  if (prefix.length === 0
    || prefix.join(",") !== expectedPrefix.join(",")
    || prefix.at(-1) >= summary.heldFinal
    || summary.heldFinal !== physical.messages.at(-1).sequenceNumber
    || summary.consumedWatermark !== prefix.at(-1)
    || summary.snapshotSequenceNumber !== prefix.at(-1)) {
    fail(`${label} summary prefix, held final chunk, and consumed watermark disagree`);
  }
  validateChunkStreams(summary.chunkStreams, `${label} source summary`, physical, prefix);
  validateChunkStreams(
    summary.publishedChunkStreams,
    `${label} published summary`,
    physical,
    prefix,
  );
  for (const field of ["upstreamRead", "nativeRead", "tailConsumed", "continuedEditing"]) {
    exactTrue(summary[field], `${label} summary ${field}`);
  }
  if (digestString(summary.upstreamTreeSha256, 64, `${label} upstream tree hash`)
      !== digestString(summary.nativeTreeSha256, 64, `${label} native tree hash`)) {
    fail(`${label} summary readers did not load the same completed tree`);
  }
}

function validateCheckpoint(result, evidence, label, physical) {
  if (evidence.pendingCounts.before < 1 || evidence.pendingCounts.held < 1) {
    fail(`${label} checkpoint has no pending native work`);
  }
  const checkpoint = object(evidence.checkpoint, `${label} checkpoint`);
  string(checkpoint.artifact, `${label} checkpoint artifact`);
  const prefix = array(checkpoint.strictPrefix, `${label} checkpoint strict prefix`);
  const suffix = array(checkpoint.heldSuffix, `${label} checkpoint held suffix`);
  if (prefix.length === 0 || suffix.length === 0
    || prefix.at(-1) === physical.messages.at(-1).sequenceNumber
    || prefix.at(-1) >= suffix[0]) {
    fail(`${label} checkpoint prefix does not end before the final chunk`);
  }
  if (prefix.join(",") !== physical.delivered.join(",")
    || suffix.join(",") !== physical.held.join(",")) {
    fail(`${label} checkpoint prefix and suffix do not match delivery controls`);
  }
  exactTrue(
    checkpoint.prefixEndsBeforeFinalChunk,
    `${label} checkpoint prefix boundary`,
  );
  if (checkpoint.processSignal !== "SIGKILL" || checkpoint.processExited !== true) {
    fail(`${label} checkpoint did not kill the native process with SIGKILL`);
  }
  positiveInteger(checkpoint.processPid, `${label} killed process PID`);
  if (checkpoint.processExitCode !== null
    || checkpoint.summarySequenceNumber !== prefix.at(-1)
    || checkpoint.consumedWatermark !== prefix.at(-1)) {
    fail(`${label} checkpoint summary sequence and consumed prefix watermark disagree`);
  }
  validateChunkStreams(
    checkpoint.chunkStreams,
    `${label} checkpoint summary`,
    physical,
    prefix,
  );
  if (checkpoint.restoredTarget !== result.restoreTarget
    || result.restoreTarget === result.target
    || !compressionTargets.includes(result.restoreTarget)) {
    fail(`${label} checkpoint restore target is not the opposite native target`);
  }
  for (const field of ["tailConsumed", "pendingSettled", "continuedEditing"]) {
    exactTrue(checkpoint[field], `${label} checkpoint ${field}`);
  }
  digestString(checkpoint.restoredTreeSha256, 64, `${label} restored tree hash`);
  const pendingRevision = string(
    checkpoint.originalPendingRevision,
    `${label} original pending revision`,
  );
  if (string(checkpoint.settledRevision, `${label} settled revision`)
      !== pendingRevision
    || string(checkpoint.pendingBatchId, `${label} pending batch identity`)
      !== string(
        checkpoint.acknowledgementBatchId,
        `${label} acknowledgement batch identity`,
      )) {
    fail(`${label} checkpoint did not settle the saved pending revision and batch`);
  }
  const historyPoint = object(
    checkpoint.settledHistoryPoint,
    `${label} settled history point`,
  );
  if (positiveInteger(
    checkpoint.acknowledgementSequenceNumber,
    `${label} acknowledgement sequence`,
  ) !== positiveInteger(
    historyPoint.sequenceNumber,
    `${label} settled history sequence`,
  )
    || nonnegativeInteger(
      historyPoint.indexInBatch,
      `${label} settled history batch index`,
    ) !== 0
    || checkpoint.liveSettlementEvents !== 0
    || string(
      checkpoint.continuationRevision,
      `${label} continuation revision`,
    ) === pendingRevision) {
    fail(`${label} checkpoint settlement history is mixed with continuation work`);
  }
}

function validateLiveProvenance(result, label) {
  const provenance = object(result.provenance, `${label} provenance`);
  if (provenance.kind !== "live-capture") {
    fail(`${label} provenance is not a live capture`);
  }
  const rawPath = resolve(string(provenance.rawArtifact, `${label} raw artifact`));
  const pathWithinOutput = relative(outputDirectory, rawPath);
  if (pathWithinOutput === ".."
    || pathWithinOutput.startsWith(`..${sep}`)
    || resolve(
      outputDirectory,
      result.runId,
      result.target,
      result.caseId,
      "raw.json",
    ) !== rawPath) {
    fail(`${label} raw artifact is outside the current live run cell`);
  }
  const rawBytes = readFileSync(rawPath);
  if (digestString(provenance.rawSha256, 64, `${label} raw artifact hash`)
      !== sha256(rawBytes)) {
    fail(`${label} raw artifact hash differs from the captured bytes`);
  }
  const raw = JSON.parse(rawBytes);
  const messages = array(raw.serverHistory, `${label} raw server history`);
  const actualPhysical = physicalMessages(messages);
  if (JSON.stringify(actualPhysical) !== JSON.stringify(result.evidence.physicalMessages)) {
    fail(`${label} physical evidence differs from the raw live capture`);
  }
  const actualSizes = capturedBatchMeasurements(
    messages,
    result.evidence.byteSizes.sourceSha256,
  );
  if (JSON.stringify(actualSizes) !== JSON.stringify(result.evidence.byteSizes)) {
    fail(`${label} byte measures differ from the raw live compressed stream`);
  }
  const same = (actual, expected, claim) => {
    if (JSON.stringify(actual) !== JSON.stringify(expected)) {
      fail(`${label} ${claim} differs from the hashed raw capture`);
    }
  };
  const lifecycle = {
    "default-compressed": [raw.baselineNative, raw.nativeAfterPeer],
    "default-chunked": [raw.baselineNative, raw.nativeAfterPeer],
    "history-catchup": [raw.baselineNative, raw.freshAfterPeer],
    "reconnect-pending": [raw.pending, raw.settled],
    "summary-continuation": [raw.initialNative, raw.sourceAfterPeer],
    "checkpoint-partial": [raw.batchBaseline, raw.restoredAfterPeer],
  }[result.caseId];
  assert(lifecycle?.every(Boolean), `${label} raw lifecycle checkpoints are missing`);
  const [baseline, completion] = lifecycle;
  const baselineHistory = nativeHistoryPoints(baseline.history);
  const baselinePendingRevisions = (baseline.history.pending ?? [])
    .map(({ revision }) => revision);
  const completedHistory = nativeHistoryPoints(completion.history);
  const baselineRevisions = new Set([
    ...baselineHistory.map(({ revision }) => revision),
    ...baselinePendingRevisions,
  ]);
  const newPeerHistory = completedHistory.filter(({ revision }) =>
    !baselineRevisions.has(revision));
  const logical = result.evidence.logicalBatch;
  same(logical.baselineHistory, baselineHistory, "baseline native history");
  same(logical.baselinePendingRevisions, baselinePendingRevisions,
    "baseline pending revisions");
  same(logical.completedHistory, completedHistory, "completed native history");
  same(logical.newPeerHistory, newPeerHistory, "new peer native history");
  same(logical.baselineSequenceNumber, baseline.sequenceNumber,
    "logical baseline sequence");
  same(logical.completedSequenceNumber, newPeerHistory[0]?.sequenceNumber,
    "logical completion sequence");
  same(logical.baselineHistorySha256, sha256(JSON.stringify(baselineHistory)),
    "baseline history hash");
  same(logical.baselineCompressorSha256, baseline.compressorSha256,
    "baseline compressor allocation hash");
  if (completion.sequenceNumber < actualPhysical.at(-1).sequenceNumber) {
    fail(`${label} raw native completion stops before the final physical message`);
  }
  if (raw.boundary) {
    const rawPrefix = raw.boundary.prefixObservations.map((observation) => ({
      sequenceNumber: observation.sequenceNumber,
      treeSha256: sha256(JSON.stringify(observation.wholeTree)),
      events: observation.events.length,
      commits: observation.commits.length,
      historySha256: historySha256(observation.history),
      compressorSha256: observation.compressorSha256,
    }));
    same(logical.prefixObservations, rawPrefix, "prefix observations");
    if (result.caseId === "checkpoint-partial") {
      same(
        result.evidence.deliveredSequences.delivered,
        raw.boundary.deliveredSequences,
        "controlled delivered prefix",
      );
      same(
        result.evidence.deliveredSequences.held,
        raw.boundary.heldSequences,
        "controlled held suffix",
      );
    }
  }
  if (result.caseId === "history-catchup") {
    const rawRequests = raw.nativeEvidence.http.filter(
      ({ method, path, status }) =>
        method === "GET"
        && path.includes("/deltas")
        && status >= 200
        && status < 300,
    );
    same(result.evidence.history.requests, rawRequests, "HTTP delta requests");
    same(
      result.evidence.history.consumedThrough,
      raw.freshAfterPeer.sequenceNumber,
      "HTTP consumed watermark",
    );
  }
  if (result.caseId === "summary-continuation") {
    const summary = result.evidence.summary;
    same(summary.nativeHandle, raw.publication.version, "published summary handle");
    same(summary.storedVersion, raw.publishedSummary.version, "stored summary version");
    same(
      summary.storedSnapshotSha256,
      raw.publishedSummary.snapshotSha256,
      "stored snapshot hash",
    );
    const fetchedVersions = raw.freshNative.http.flatMap(({ method, path, status }) => {
      const match = path.match(/\/commits\/([^/?]+)$/);
      return method === "GET" && status >= 200 && status < 300 && match
        ? [match[1]]
        : [];
    });
    if (!fetchedVersions.includes(summary.freshNativeFetchedVersion)) {
      fail(`${label} fresh native did not fetch the claimed summary version`);
    }
    same(
      summary.publishedChunkStreams,
      chunkStreamEvidence(raw.publishedSummary.chunkStreams),
      "stored summary chunk streams",
    );
  }
  if (result.caseId === "checkpoint-partial") {
    const checkpoint = result.evidence.checkpoint;
    const pending = raw.batchBaseline.history.pending;
    same(pending.length, 1, "saved pending revision count");
    same(checkpoint.originalPendingRevision, pending[0].revision,
      "saved pending revision");
    same(checkpoint.pendingBatchId, raw.checkpointBatchId,
      "saved pending batch identity");
    same(checkpoint.acknowledgementBatchId, messageBatchId(raw.acknowledgement),
      "acknowledgement batch identity");
    same(
      checkpoint.acknowledgementSequenceNumber,
      raw.acknowledgement.sequenceNumber,
      "acknowledgement sequence",
    );
    same(checkpoint.settledHistoryPoint, raw.settledHistoryPoint,
      "settled native history point");
    same(
      checkpoint.liveSettlementEvents,
      raw.restoredSettled.commits.filter(({ type }) => type === "settlement").length,
      "live settlement event count",
    );
    const continuation = raw.continuedRestored.commits.find(
      ({ type, local }) => type === "commit" && local === true,
    );
    same(checkpoint.continuationRevision, continuation?.revision,
      "continuation revision");
  }
}

function validateCompressionMatrix(results, runId, profileDigest, artifactKind) {
  string(runId, "runId");
  digestString(profileDigest, 64, "profileDigest");
  if (!Array.isArray(results) || results.length !== 12) {
    fail("compression result matrix must contain twelve (12) cells");
  }
  const expected = new Set(compressionTargets.flatMap((target) =>
    compressionCases.map((caseId) => `${target}:${caseId}`)));
  let commonProbe;
  let commonSource;
  let commonExtension;
  for (const [index, value] of results.entries()) {
    const result = object(value, `result ${index}`);
    const target = string(result.target, `result ${index} target`);
    const caseId = string(result.caseId, `result ${index} caseId`);
    const key = `${target}:${caseId}`;
    if (!expected.has(key)) fail(`duplicate or unexpected compression cell ${key}`);
    expected.delete(key);
    if (result.artifactKind !== artifactKind) {
      fail(`${key} artifactKind must be ${artifactKind}`);
    }
    if (result.runId !== runId) fail(`${key} runId is stale`);
    if (result.profileDigest !== profileDigest) fail(`${key} profileDigest is stale`);
    digestString(result.probeDigest, 64, `${key} probeDigest`);
    digestString(result.sourceDigest, 40, `${key} sourceDigest`);
    digestString(result.extensionDigest, 64, `${key} extensionDigest`);
    if (artifactKind === "live") {
      for (const field of ["probeDigest", "sourceDigest", "extensionDigest"]) {
        if (result[field] !== currentCompressionIdentity[field]) {
          fail(`${key} ${field} is stale`);
        }
      }
      if (profileDigest !== currentCompressionIdentity.profileDigest) {
        fail(`${key} profileDigest is not the current verified compression profile`);
      }
      validateLiveProvenance(result, key);
    }
    commonProbe ??= result.probeDigest;
    commonSource ??= result.sourceDigest;
    commonExtension ??= result.extensionDigest;
    if (result.probeDigest !== commonProbe) fail(`${key} probeDigest differs from the run`);
    if (result.sourceDigest !== commonSource) fail(`${key} sourceDigest differs from the run`);
    if (result.extensionDigest !== commonExtension) {
      fail(`${key} extensionDigest differs from the run`);
    }
    string(result.documentId, `${key} documentId`);
    exactTrue(result.passed, `${key} passed`);
    if (result.skipped !== false) fail(`${key} was skipped`);
    const evidence = object(result.evidence, `${key} evidence`);
    validateRuntimeOptions(evidence, key);
    const physical = validatePhysicalEvidence(evidence, key, caseId);
    validateCommonSemantics(evidence, key, caseId);
    const sequences = physical.messages.map(({ sequenceNumber }) => sequenceNumber);
    if (caseId === "history-catchup") validateHistory(evidence, key, sequences);
    if (caseId === "reconnect-pending") validateReconnect(evidence, key, physical);
    if (caseId === "summary-continuation") validateSummary(evidence, key, physical);
    if (caseId === "checkpoint-partial") {
      validateCheckpoint(result, evidence, key, physical);
    } else if (result.restoreTarget !== undefined) {
      fail(`${key} unexpectedly records a restoreTarget`);
    }
  }
  if (expected.size > 0) fail(`missing compression cells: ${[...expected].join(", ")}`);
  return results;
}

export function validateCompressionFixtureResults(results, runId, profileDigest) {
  return validateCompressionMatrix(
    results,
    runId,
    profileDigest,
    "validator-only-synthetic",
  );
}

export function validateCompressionResults(results, runId, profileDigest) {
  return validateCompressionMatrix(results, runId, profileDigest, "live");
}

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");

function selectedFrames(capture) {
  return benchmarkFrameIds.map((id) => {
    const entry = capture.frames.find((frame) => frame.id === id);
    if (!entry) fail(`missing captured frame ${id}`);
    const compressed = Buffer.from(entry.compressedBase64, "base64");
    const decoded = Buffer.from(entry.decodedBase64, "base64");
    if (decoded.length !== entry.measurements.decodedBytes) {
      fail(`${id} decoded size does not match capture metadata`);
    }
    return { id, entry, compressed, decoded };
  });
}

async function javascriptMeasurements(frames) {
  const [{ BitArray }, lz4] = await Promise.all([
    import(pathToFileURL(resolve(repository, "build/dev/javascript/prelude.mjs"))),
    import(pathToFileURL(resolve(
      repository,
      "build/dev/javascript/watershed/watershed/wire/lz4.mjs",
    ))),
  ]);
  const measurements = {};
  for (const frame of frames) {
    const input = new BitArray(new Uint8Array(frame.compressed));
    const decode = () => {
      const decoded = lz4.decompress(input, maxOutputBytes);
      if (decoded.constructor.name !== "Ok") fail(`javascript refused ${frame.id}`);
      return Buffer.from(decoded[0].rawBuffer);
    };
    for (let index = 0; index < warmupCount; index += 1) {
      if (!decode().equals(frame.decoded)) fail(`javascript warmup output differs for ${frame.id}`);
    }
    const samplesMicroseconds = [];
    for (let index = 0; index < timedCount; index += 1) {
      const started = performance.now();
      const output = decode();
      samplesMicroseconds.push((performance.now() - started) * 1000);
      if (!output.equals(frame.decoded)) fail(`javascript output differs for ${frame.id}`);
    }
    measurements[frame.id] = {
      decodedBytes: frame.decoded.length,
      compressedBytes: frame.compressed.length,
      warmups: warmupCount,
      samplesMicroseconds,
      medianMicroseconds: median(samplesMicroseconds),
      outputMatches: true,
    };
  }
  measurements.ratio4MiBTo1MiB =
    measurements["benchmark-4mib"].medianMicroseconds /
    measurements["benchmark-1mib"].medianMicroseconds;
  return measurements;
}

function erlangSamples(compressedPath, decodedPath) {
  const erlangBuild = resolve(repository, "build/dev/erlang");
  const codePaths = readdirSync(erlangBuild, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .flatMap((entry) => ["-pa", resolve(erlangBuild, entry.name, "ebin")]);
  const quote = (value) => value.replaceAll("\\", "\\\\").replaceAll("\"", "\\\"");
  const expression = `
    {ok, Frame} = file:read_file("${quote(compressedPath)}"),
    {ok, Expected} = file:read_file("${quote(decodedPath)}"),
    Decode = fun() -> 'watershed@wire@lz4':decompress(Frame, ${maxOutputBytes}) end,
    lists:foreach(fun(_) -> {ok, Expected} = Decode() end, lists:seq(1, ${warmupCount})),
    Samples = lists:map(fun(_) ->
      {Micros, {ok, Output}} = timer:tc(Decode),
      true = (Output =:= Expected),
      Micros
    end, lists:seq(1, ${timedCount})),
    io:format("~p~n", [Samples]),
    halt().
  `;
  const output = execFileSync("erl", [
    ...codePaths, "-noshell", "-eval", expression,
  ], { cwd: repository, encoding: "utf8", maxBuffer: 1024 * 1024 });
  return output.trim().slice(1, -1).split(",").map(Number);
}

async function erlangMeasurements(frames) {
  const measurements = {};
  await mkdir(inputsDirectory, { recursive: true });
  try {
    for (const frame of frames) {
      const compressedPath = resolve(inputsDirectory, `${frame.id}.lz4`);
      const decodedPath = resolve(inputsDirectory, `${frame.id}.decoded`);
      await Promise.all([
        writeFile(compressedPath, frame.compressed),
        writeFile(decodedPath, frame.decoded),
      ]);
      const samplesMicroseconds = erlangSamples(compressedPath, decodedPath);
      measurements[frame.id] = {
        decodedBytes: frame.decoded.length,
        compressedBytes: frame.compressed.length,
        warmups: warmupCount,
        samplesMicroseconds,
        medianMicroseconds: median(samplesMicroseconds),
        outputMatches: true,
      };
    }
  } finally {
    await rm(inputsDirectory, { recursive: true, force: true });
  }
  measurements.ratio4MiBTo1MiB =
    measurements["benchmark-4mib"].medianMicroseconds /
    measurements["benchmark-1mib"].medianMicroseconds;
  return measurements;
}

export async function runBenchmark() {
  const capture = JSON.parse(await readFile(fixturePath, "utf8"));
  const frames = selectedFrames(capture);
  execFileSync("gleam", ["build", "--target", "javascript"], {
    cwd: repository,
    stdio: "inherit",
  });
  const javascript = await javascriptMeasurements(frames);
  execFileSync("gleam", ["build", "--target", "erlang"], {
    cwd: repository,
    stdio: "inherit",
  });
  const erlang = await erlangMeasurements(frames);
  const report = validateBenchmarkReport({
    formatVersion: 1,
    generatedAt: new Date().toISOString(),
    identity: {
      fluid: capture.upstream,
      probe: {
        path: capture.probe.path,
        sha256: capture.probe.digest,
        treePath: capture.probe.treePath,
        treeSha256: capture.probe.treeDigest,
      },
      spillwayRevision,
      floodgateRevision,
      legacyProfileSha256,
      frames: Object.fromEntries(frames.map((frame) => [frame.id, {
        compressedBytes: frame.compressed.length,
        compressedSha256: sha256(frame.compressed),
        decodedBytes: frame.decoded.length,
        decodedSha256: sha256(frame.decoded),
      }])),
    },
    protocol: {
      warmupsPerTargetAndSize: warmupCount,
      timedRunsPerTargetAndSize: timedCount,
      maximumRatio4MiBTo1MiB: maxRatio,
      processStartupExcluded: true,
    },
    targets: { javascript, erlang },
  });
  await mkdir(outputDirectory, { recursive: true });
  await writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`);
  return report;
}

function deterministicText(seed, length) {
  let value = "";
  for (let index = 0; value.length < length; index += 1) {
    value += createHash("sha512").update(`${seed}:${index}`).digest("base64");
  }
  return value.slice(0, length);
}

function creationRoot(title = "native compression creation") {
  return {
    kind: "object",
    schemaId: "org.watershed.shared-tree.m1.Root",
    fields: [
      ["title", { kind: "string", value: title }],
      ["enabled", { kind: "boolean", value: true }],
      ["rating", { kind: "number", value: 1 }],
      ["marker", { kind: "null" }],
      ["point", {
        kind: "object",
        schemaId: "org.watershed.shared-tree.m1.Point",
        fields: [
          ["x", { kind: "number", value: 3 }],
          ["y", { kind: "number", value: -4 }],
        ],
      }],
    ],
  };
}

function nestedJson(value) {
  let current = value;
  for (let depth = 0; depth < 4 && typeof current === "string"; depth += 1) {
    try {
      current = JSON.parse(current);
    } catch {
      break;
    }
  }
  return current;
}

function messageContents(message) {
  return nestedJson(message.contents);
}

function messageBatchId(message) {
  if (typeof message.metadata?.batchId === "string") return message.metadata.batchId;
  const contents = messageContents(message);
  if (contents?.type !== "groupedBatch") return undefined;
  return contents.contents?.map((entry) => entry.metadata?.batchId)
    .find((batchId) => typeof batchId === "string");
}

function capturedCompressionPayload(messages) {
  const contents = messages.map(messageContents);
  const chunked = contents[0]?.type === "chunkedOp";
  const packedEnvelope = chunked
    ? nestedJson(contents.map((entry) => entry.contents.contents).join(""))
    : contents[0];
  const packedContents = string(
    packedEnvelope?.packedContents,
    "captured packedContents",
  );
  const frame = Buffer.from(packedContents, "base64");
  const decoded = Buffer.from(lz4js.decompress(frame));
  JSON.parse(decoded.toString("utf8"));
  return { chunked, contents, packedContents, frame, decoded };
}

function findStringBySha256(value, expected) {
  if (typeof value === "string") return sha256(value) === expected ? [value] : [];
  if (Array.isArray(value)) {
    return value.flatMap((entry) => findStringBySha256(entry, expected));
  }
  if (value && typeof value === "object") {
    return Object.values(value).flatMap((entry) =>
      findStringBySha256(entry, expected));
  }
  return [];
}

function capturedBatchMeasurements(messages, sourceSha256) {
  const payload = capturedCompressionPayload(messages);
  const decodedValue = JSON.parse(payload.decoded.toString("utf8"));
  const sourceMatches = findStringBySha256(decodedValue, sourceSha256);
  assert.equal(
    sourceMatches.length,
    1,
    "Captured decoded runtime payload does not contain one expected source value",
  );
  return {
    sourceUtf8Bytes: Buffer.byteLength(sourceMatches[0]),
    lz4FrameBytes: payload.frame.length,
    packedContentsBase64Bytes: Buffer.byteLength(payload.packedContents),
    physicalWirePayloadBytes: messages.reduce((total, message) =>
      total + Buffer.byteLength(JSON.stringify(message.contents)), 0),
    decodedRuntimeBytes: payload.decoded.length,
    decodedRuntimeSha256: sha256(payload.decoded),
    sourceSha256,
  };
}

function isSchemaMessage(message) {
  const contents = messageContents(message);
  return contents?.type === "schema"
    || contents?.type === "groupedBatch"
      && contents.contents?.some((entry) => nestedJson(entry.contents)?.type === "schema");
}

function physicalMessages(messages) {
  const selected = messages.filter((message) => {
    const contents = messageContents(message);
    return message.compression === "lz4"
      || contents?.packedContents !== undefined
      || contents?.type === "chunkedOp";
  });
  assert(selected.length > 0,
    `No compressed physical messages were observed: ${JSON.stringify(
      messages.map((message) => ({
        sequenceNumber: message.sequenceNumber,
        clientId: message.clientId,
        compression: message.compression,
        type: message.type,
        contentsType: messageContents(message)?.type,
        contentsKeys: Object.keys(messageContents(message) ?? {}),
        contentsBytes: Buffer.byteLength(JSON.stringify(message.contents)),
      })),
    )}`);
  const final = selected.at(-1);
  const batchId =
    `${final.clientId}:${final.clientSequenceNumber}:${final.sequenceNumber}`;
  return selected.map((message) => {
    const contents = messageContents(message);
    const chunk = contents?.type === "chunkedOp" ? contents.contents : undefined;
    return {
      sequenceNumber: message.sequenceNumber,
      clientSequenceNumber: message.clientSequenceNumber,
      referenceSequenceNumber: message.referenceSequenceNumber,
      clientId: message.clientId,
      type: message.type,
      compression: message.compression ?? chunk?.originalCompression ?? null,
      metadata: message.metadata ?? chunk?.originalMetadata ?? {},
      contentsType: chunk ? "chunkedOp" : contents?.type ?? "packedContents",
      wirePayloadBytes: Buffer.byteLength(JSON.stringify(message.contents)),
      chunkPieceBytes: chunk ? Buffer.byteLength(chunk.contents) : null,
      chunkPieceSha256: chunk ? sha256(chunk.contents) : null,
      chunkId: chunk?.chunkId ?? null,
      totalChunks: chunk?.totalChunks ?? null,
      batchId,
    };
  });
}

function sessionSchema(session) {
  const schema = Reflect.get(session.runtime, "sessionSchema");
  assert(schema && typeof schema === "object", "Pinned runtime exposed no session schema");
  return structuredClone(schema);
}

function frameSequences(frames) {
  return frames.flatMap(({ sequenceNumbers = [] }) => sequenceNumbers);
}

function witnessedLiteral(session, peerHash, nativeRating) {
  const observed = {
    titleSha256: sha256(session.data.view.root.title),
    rating: session.data.view.root.rating,
  };
  assert.equal(observed.titleSha256, peerHash, "Upstream witness missed the peer title");
  assert.equal(observed.rating, nativeRating, "Upstream witness missed the native edit");
  const literal = JSON.stringify(observed);
  return {
    literal,
    sha256: sha256(literal),
    peerEdit: peerHash,
    nativeEdit: `"rating":${nativeRating}`,
  };
}

function actualRoutes(session) {
  return [
    session.data.bootstrap.handle.absolutePath,
    session.data.tree.handle.absolutePath,
  ];
}

function observedRuntimeOptions(session) {
  return {
    mode: session.effectiveRuntimeOptions.compression.mode,
    minimumBatchSizeInBytes:
      session.effectiveRuntimeOptions.compression.minimumBatchSizeInBytes,
    chunkSizeInBytes: session.effectiveRuntimeOptions.compression.chunkSizeInBytes,
    compressionAlgorithm:
      session.effectiveRuntimeOptions.compression.compressionAlgorithm,
    summarizerHeuristics:
      session.effectiveRuntimeOptions.summaryOptions.summaryConfigOverrides?.state
        ?? "runtime-default",
  };
}

function deepValuesNamed(value, name, found = []) {
  if (!value || typeof value !== "object") return found;
  if (Array.isArray(value)) {
    if (value.length === 2 && value[0] === name) found.push(value[1]);
    for (const entry of value) deepValuesNamed(entry, name, found);
    return found;
  }
  for (const [key, entry] of Object.entries(value)) {
    if (key === name) found.push(entry);
    deepValuesNamed(entry, name, found);
  }
  return found;
}

function summaryChunkStreams(evidence) {
  const values = deepValuesNamed(evidence, ".chunks");
  const parsed = values.flatMap((value) => {
    const encoded = typeof value?.base64 === "string"
      ? Buffer.from(value.base64, "base64").toString("utf8")
      : value?.content ?? value;
    const current = nestedJson(encoded);
    return Array.isArray(current) ? current : [];
  });
  return parsed.flatMap((entry) =>
    Array.isArray(entry)
      && typeof entry[0] === "string"
      && Array.isArray(entry[1])
      && entry[1].every((piece) => typeof piece === "string")
      ? [{ clientId: entry[0], pieces: entry[1] }]
      : []);
}

function storedSnapshotChunkStreams(captured) {
  const streams = [];
  const visit = (tree) => {
    const chunkBlob = tree.blobs?.[".chunks"];
    if (typeof chunkBlob === "string") {
      const encoded = captured.blobs[chunkBlob];
      assert(typeof encoded === "string", "Published /.chunks blob bytes are missing");
      const parsed = nestedJson(Buffer.from(encoded, "base64").toString("utf8"));
      assert(Array.isArray(parsed), "Published /.chunks blob has another shape");
      streams.push(...parsed.map(([clientId, pieces]) => ({ clientId, pieces })));
    }
    for (const child of Object.values(tree.trees ?? {})) visit(child);
  };
  visit(captured.tree);
  return streams;
}

function chunkStreamEvidence(streams) {
  return streams.map(({ clientId, pieces }) => ({
    clientId,
    pieceSha256: pieces.map(sha256),
  }));
}

async function pendingChunkStreamCount(native) {
  return summaryChunkStreams(await native.pendingSummaryEvidence()).length;
}

async function publishedSummaryEvidence(session, expectedVersion) {
  const service = await session.documentServiceFactory
    .createDocumentService(session.container.resolvedUrl);
  try {
    const storage = await service.connectToStorage();
    const versions = await storage.getVersions(null, 1);
    assert.equal(versions.length, 1, "Published compression summary has no current version");
    assert.equal(versions[0].id, expectedVersion,
      "Storage current version differs from the native publication");
    const captured = await snapshot(storage);
    return {
      version: versions[0].id,
      chunkStreams: storedSnapshotChunkStreams(captured),
      snapshotSha256: sha256(JSON.stringify(captured)),
    };
  } finally {
    service.dispose();
  }
}

async function compressionIdentity() {
  const [profileBytes, corpusBytes] = await Promise.all([
    readFile(resolve(repository, "test/fixtures/shared_tree/compression-profile.json")),
    readFile(fixturePath),
  ]);
  const capture = JSON.parse(corpusBytes);
  return {
    profileDigest: sha256(profileBytes),
    extensionDigest: sha256(corpusBytes),
    probeDigest: capture.probe.digest,
    sourceDigest: fluidSourceRevision,
  };
}

async function createUpstreamDocument(config, containers) {
  const creator = await openSession(config, containers);
  return {
    creator,
    documentId: creator.container.resolvedUrl.id,
    nativeCreated: false,
  };
}

async function createNativeDocument(config, target, schema) {
  const { jwt } = await tokenProvider(config).fetchStorageToken(config.tenantId);
  const created = await runCreatorProbe(target, {
    baseUrl: config.httpUrl,
    tenant: config.tenantId,
    token: jwt,
    schema,
    root: creationRoot(),
    expected: "success",
  });
  assert.equal(created.ok, true, `${target} did not create the compression document`);
  return {
    documentId: created.documentId,
    nativeCreated: true,
    creation: created,
  };
}

async function openLiveClients(
  config,
  containers,
  target,
  schema,
  runId,
  caseId,
  document,
) {
  let writerSession = await openSession(
    config,
    containers,
    document.documentId,
    false,
    { cache: false, runtimeOptionMode: "default-compression" },
  );
  const witnessSession = await openSession(
    config,
    containers,
    document.documentId,
    false,
    { cache: false, runtimeOptionMode: "default-compression" },
  );
  const token = (await tokenProvider(config).fetchOrdererToken(
    config.tenantId,
    document.documentId,
  )).jwt;
  const native = await nativeAdapter(target, config, {
    runId,
    documentId: document.documentId,
    tenant: config.tenantId,
    viewSchema: schema,
  }, token);
  let writer = upstreamAdapter(writerSession);
  const witness = upstreamAdapter(witnessSession);
  await Promise.all([writer.awaitSynced(), witness.awaitSynced(), native.awaitSynced()]);
  await writer.set(["point", "x"], 10 + compressionCases.indexOf(caseId));
  await writer.awaitSynced();
  await until(() => sessionSchema(writerSession).compressionLz4 === true,
    `${target} ${caseId} runtime compression schema activation`);
  const activationSummary = await publishUpstreamSummary(
    config,
    containers,
    document.documentId,
    `${target} ${caseId} compression activation`,
    { runtimeOptionMode: "default-compression" },
  );
  writerSession.container.dispose();
  writerSession = await openSession(
    config,
    containers,
    document.documentId,
    false,
    { cache: false, runtimeOptionMode: "default-compression" },
  );
  writer = upstreamAdapter(writerSession);
  await Promise.all([writer.awaitSynced(), witness.awaitSynced(), native.awaitSynced()]);
  assert.equal(sessionSchema(writerSession).compressionLz4, true,
    `${target} ${caseId} reloaded writer did not activate compression`);
  return {
    writerSession,
    witnessSession,
    writer,
    witness,
    native,
    token,
    descriptor: {
      runId,
      documentId: document.documentId,
      tenant: config.tenantId,
      viewSchema: schema,
    },
    activationSummary,
  };
}

async function writeCellArtifact(runDirectory, target, caseId, name, value) {
  const path = join(runDirectory, target, caseId, name);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 });
  return path;
}

async function liveCellResult({
  runDirectory,
  target,
  caseId,
  runId,
  identities,
  documentId,
  evidence,
  raw,
  restoreTarget,
}) {
  const rawArtifact = await writeCellArtifact(
    runDirectory,
    target,
    caseId,
    "raw.json",
    raw,
  );
  return {
    artifactKind: "live",
    target,
    ...(restoreTarget === undefined ? {} : { restoreTarget }),
    caseId,
    runId,
    ...identities,
    documentId,
    passed: true,
    skipped: false,
    provenance: {
      kind: "live-capture",
      rawArtifact,
      rawSha256: sha256(await readFile(rawArtifact)),
    },
    evidence,
  };
}

function documentEvidence(document) {
  return {
    documentId: document.documentId,
    nativeCreated: document.nativeCreated,
    ...(document.creation ? { creation: document.creation } : {}),
  };
}

function sequencePoint(value) {
  const match = String(value).match(
    /SequencePoint\((?:sequence_number:\s*)?(\d+),\s*(?:index_in_batch:\s*)?(\d+)\)/,
  );
  assert(match, `Native history has an invalid sequence point: ${value}`);
  return {
    sequenceNumber: Number(match[1]),
    indexInBatch: Number(match[2]),
  };
}

function nativeHistoryPoints(history) {
  assert(Array.isArray(history?.trunk), "Native checkpoint lacks trunk history");
  return history.trunk.map(({ commit, point }) => ({
    revision: string(commit?.revision, "native history revision"),
    ...sequencePoint(point),
  }));
}

function historySha256(history) {
  return sha256(JSON.stringify(nativeHistoryPoints(history)));
}

function summaryBlob(summary, name) {
  const visit = (entry) => {
    if (entry?.type !== "tree") return undefined;
    for (const [key, child] of entry.entries ?? []) {
      if (key === name && child?.type === "blob") {
        return Buffer.from(child.base64, "base64");
      }
      const nested = visit(child);
      if (nested !== undefined) return nested;
    }
    return undefined;
  };
  const found = visit(summary.tree);
  assert(found, `Pending summary lacks ${name}`);
  return found;
}

async function compressorSha256(native) {
  return sha256(summaryBlob(await native.pendingSummaryEvidence(), ".idCompressor"));
}

async function observedPeerBatch(session, writerClientId, beforeSequence) {
  const history = await serverHistory(session);
  const messages = history.filter((message) =>
    message.clientId === writerClientId
    && message.sequenceNumber > beforeSequence);
  return {
    history,
    messages,
    physical: physicalMessages(messages),
  };
}

function commonEvidence({
  writerSession,
  schema,
  activation,
  messages,
  physical,
  delivered,
  held = [],
  pending = { before: 0, held: 0, after: 0 },
  witnessContent,
  baseline,
  peerCompletion,
  nativeLocal,
  nativeSettlement,
  witnessCompletion,
  upstreamPeerCompletion,
  upstreamFinalCompletion,
  prefixObservations = [],
  nativeSubmissionOccurrences,
  nativeSubmissionIdentity,
  settledSubmissionIdentity,
  settlementActionId,
  pendingPositionsAfter,
  baselineCompressorSha256 = baseline.compressorSha256,
  settlementProof,
}) {
  const baselineTreeSha256 = sha256(JSON.stringify(baseline.wholeTree));
  const completedTreeSha256 = sha256(JSON.stringify(peerCompletion.wholeTree));
  const upstreamPeerTreeSha256 =
    sha256(JSON.stringify(upstreamPeerCompletion.wholeTree));
  const nativeFinalTreeSha256 =
    sha256(JSON.stringify(nativeSettlement.wholeTree));
  const upstreamFinalTreeSha256 =
    sha256(JSON.stringify(upstreamFinalCompletion.wholeTree));
  const witnessTreeSha256 =
    sha256(JSON.stringify(witnessCompletion.wholeTree));
  const baselineHistory = nativeHistoryPoints(baseline.history);
  const completedHistory = nativeHistoryPoints(peerCompletion.history);
  const baselinePendingRevisions = (baseline.history.pending ?? [])
    .map(({ revision }) => string(revision, "native pending history revision"));
  const baselineRevisions = new Set([
    ...baselineHistory.map(({ revision }) => revision),
    ...baselinePendingRevisions,
  ]);
  const newPeerHistory = completedHistory.filter(({ revision }) =>
    !baselineRevisions.has(revision));
  assert.equal(newPeerHistory.length, 1,
    "Native history did not add exactly one peer revision");
  assert.equal(
    newPeerHistory[0].sequenceNumber,
    physical.at(-1).sequenceNumber,
    "Native history did not sequence the peer revision at the final chunk",
  );
  const peerCommits = peerCompletion.commits.filter(
    ({ type, local }) => type === "commit" && local === false,
  );
  const localCommits = nativeLocal.commits.filter(
    ({ type, local }) => type === "commit" && local === true,
  );
  assert.equal(localCommits.length, 1, "Native edit did not produce one local commit");
  const settlements = nativeSettlement.commits.filter(
    ({ type, actionId }) =>
      type === "settlement"
      && actionId === (settlementActionId ?? localCommits[0].actionId),
  );
  const nativeHistorySettlements = settlementProof === undefined ? 0 : 1;
  assert.equal(settlements.length + nativeHistorySettlements, 1,
    `Native edit did not produce one settlement proof: ${JSON.stringify({
      local: localCommits,
      observed: nativeSettlement.commits,
      settlementProof,
    })}`);
  return {
    runtimeOptions: observedRuntimeOptions(writerSession),
    capability: {
      schemaActivationObserved: activation.observed,
      compressionEnabled: schema.compressionLz4 === true,
      refSeq: schema.refSeq,
    },
    physicalMessages: physical,
    byteSizes: capturedBatchMeasurements(messages, witnessContent.peerEdit),
    deliveredSequences: {
      held,
      delivered,
      final: physical.at(-1).sequenceNumber,
      complete: held.length === 0
        && delivered.length === physical.length,
    },
    pendingCounts: pending,
    commitCounts: {
      peerLogicalBatches: newPeerHistory.length,
      peerTreeEvents: peerCompletion.events.filter(
        ({ kind, local }) => kind === "data" && local === false,
      ).length,
      peerCommitEvents: peerCommits.length,
      peerRevisions: newPeerHistory.map(({ revision }) => revision),
      nativeSubmissionOccurrences,
      nativeLocalCommits: localCommits.length,
      nativeSettlements: settlements.length,
      nativeHistorySettlements,
      nativeActionId: localCommits[0].actionId,
      settledActionId: settlements[0]?.actionId ?? settlementProof.revision,
      nativeSubmissionIdentity:
        nativeSubmissionIdentity ?? localCommits[0].actionId,
      settledSubmissionIdentity:
        settledSubmissionIdentity ?? settlements[0]?.actionId,
      witnessCommitEvents: witnessCompletion.commits.filter(
        ({ type, local }) => type === "commit" && local === false,
      ).length,
    },
    logicalBatch: {
      baselineSequenceNumber: baseline.sequenceNumber,
      completedSequenceNumber: newPeerHistory[0].sequenceNumber,
      pendingPositionsAfter,
      baselineHistory,
      baselinePendingRevisions,
      completedHistory,
      newPeerHistory,
      baselineHistorySha256: sha256(JSON.stringify(baselineHistory)),
      baselineCompressorSha256,
      baselineTreeSha256,
      completedTreeSha256,
      prefixObservations: prefixObservations.map((observation) => ({
        sequenceNumber: observation.sequenceNumber,
        treeSha256: sha256(JSON.stringify(observation.wholeTree)),
        events: observation.events.length,
        commits: observation.commits.length,
        historySha256: historySha256(observation.history),
        compressorSha256: observation.compressorSha256,
      })),
    },
    finalBatchIdentity: physical.at(-1).batchId,
    gcRoutes: actualRoutes(writerSession),
    schemaFlags: {
      compression: schema.compressionLz4 === true,
      idCompressor: schema.idCompressorMode === "on",
    },
    witnessContent,
    bidirectionalEdits: {
      peerObservedByNative: completedTreeSha256 === upstreamPeerTreeSha256,
      nativeObservedByWitness: witnessTreeSha256 === upstreamFinalTreeSha256,
      nativeTreeMatchesUpstream: completedTreeSha256 === upstreamPeerTreeSha256,
      witnessTreeMatchesNative:
        witnessTreeSha256 === nativeFinalTreeSha256
        && witnessTreeSha256 === upstreamFinalTreeSha256,
    },
  };
}

async function activationEvidence(session, history) {
  const messages = history.filter(isSchemaMessage);
  const proposal = messages.map(messageContents).flatMap((contents) =>
    contents?.type === "schema"
      ? [contents.contents]
      : contents?.type === "groupedBatch"
        ? contents.contents
          .map((entry) => nestedJson(entry.contents))
          .filter((entry) => entry?.type === "schema")
          .map((entry) => entry.contents)
        : []).at(0);
  const schema = {
    ...sessionSchema(session),
    refSeq: proposal?.refSeq,
  };
  return {
    schema,
    observed: schema.compressionLz4 === true
      && messages.length > 0,
    messages,
  };
}

async function runSimpleCell(context, caseId) {
  const {
    config, target, schema, runId, runDirectory, identities,
  } = context;
  const containers = [];
  const natives = [];
  let error;
  try {
    const document = caseId === "default-compressed"
      ? await createNativeDocument(config, target, schema)
      : await createUpstreamDocument(config, containers);
    const clients = await openLiveClients(
      config, containers, target, schema, runId, caseId, document,
    );
    natives.push(clients.native);
    const baselineNative = await clients.native.checkpoint();
    baselineNative.compressorSha256 = await compressorSha256(clients.native);
    await clients.writer.checkpoint();
    await clients.witness.checkpoint();
    if (caseId === "history-catchup") {
      const summary = await publishUpstreamSummary(
        config,
        containers,
        document.documentId,
        `${target} history baseline`,
        { runtimeOptionMode: "default-compression" },
      );
      const before = summary.summaryReferenceSequenceNumber;
      const sourceText = deterministicText(`${target}:${caseId}`, 640_000);
      const peerHash = sha256(sourceText);
      const writerClientId = clients.writerSession.container.clientId;
      await clients.writer.set(["title"], sourceText);
      await clients.writer.awaitSynced();
      const batch = await observedPeerBatch(
        clients.writerSession, writerClientId, before,
      );
      const upstreamAfterPeer = await clients.writer.checkpoint();
      await clients.native.close();
      natives.pop();
      const fresh = await nativeAdapter(target, config, {
        ...clients.descriptor,
        runId: `${runId}-${caseId}-fresh`,
      }, clients.token, {
        configureGate(gate) {
          gate.inject({
            documentId: document.documentId,
            mutation: "omit-initial-messages",
            expectedStage: "history-catchup",
            direction: "inbound",
            kind: "connect",
            transform(payload) {
              const short = payload[0] === "connect_document_success";
              const connection = short ? payload[1] : payload[4];
              assert(Array.isArray(connection.initialMessages));
              connection.initialMessages = [];
              return payload;
            },
          });
        },
      });
      natives.push(fresh);
      await fresh.awaitSynced(batch.physical.at(-1).sequenceNumber);
      const freshAfterPeer = await fresh.checkpoint();
      assert.deepEqual(
        freshAfterPeer.wholeTree,
        upstreamAfterPeer.wholeTree,
        `${target} fresh native did not consume the complete HTTP history tree`,
      );
      const nativeRating = 107;
      const outboundBefore = fresh.evidence().outboundOccurrences.length;
      await fresh.set(["rating"], nativeRating);
      await fresh.awaitSynced();
      await Promise.all([clients.writer.awaitSynced(), clients.witness.awaitSynced()]);
      const freshAfterEdit = await fresh.checkpoint();
      const upstreamFinal = await clients.writer.checkpoint();
      const witnessFinal = await clients.witness.checkpoint();
      const witnessContent = witnessedLiteral(
        clients.witnessSession, peerHash, nativeRating,
      );
      const activation = await activationEvidence(
        clients.writerSession, batch.history,
      );
      const nativeEvidence = fresh.evidence();
      const delta = nativeEvidence.http.filter(({ path, method, status }) =>
        method === "GET" && path.includes("/deltas")
          && status >= 200 && status < 300);
      assert(
        delta.length > 0,
        `${target} fresh native made no HTTP delta request: `
          + JSON.stringify(nativeEvidence.http.map(({ method, path, status }) => ({
            method, path, status,
          }))),
      );
      const evidence = commonEvidence({
        writerSession: clients.writerSession,
        schema: activation.schema,
        activation,
        messages: batch.messages,
        physical: batch.physical,
        delivered: batch.physical.map(({ sequenceNumber }) => sequenceNumber),
        witnessContent,
        baseline: baselineNative,
        peerCompletion: freshAfterPeer,
        nativeLocal: freshAfterEdit,
        nativeSettlement: freshAfterEdit,
        witnessCompletion: witnessFinal,
        upstreamPeerCompletion: upstreamAfterPeer,
        upstreamFinalCompletion: upstreamFinal,
        nativeSubmissionOccurrences:
          fresh.evidence().outboundOccurrences.length - outboundBefore,
        pendingPositionsAfter: await pendingChunkStreamCount(fresh),
      });
      const deltaRequest = delta.find(({ responseEnvelopes = [] }) =>
        batch.physical.every(({ sequenceNumber }) =>
          responseEnvelopes.some((message) =>
            message.sequenceNumber === sequenceNumber)));
      assert(deltaRequest, `${target} HTTP delta response omitted compressed envelopes`);
      const deltaUrl = new URL(deltaRequest.path, "http://localhost");
      evidence.history = {
        transport: "http-delta",
        requestedFrom: Number(deltaUrl.searchParams.get("from")),
        requestedTo: Number(deltaUrl.searchParams.get("to")),
        compressedSequences: batch.physical.map(({ sequenceNumber }) => sequenceNumber),
        consumedThrough: freshAfterPeer.sequenceNumber,
        requests: delta,
        handshakeInjection: nativeEvidence.injections.find(
          ({ mutation }) => mutation === "omit-initial-messages",
        ),
      };
      return liveCellResult({
        runDirectory, target, caseId, runId, identities,
        documentId: document.documentId,
        evidence,
        raw: {
          document: documentEvidence(document),
          summary, nativeEvidence, serverHistory: batch.messages,
          activation, baselineNative, upstreamAfterPeer, freshAfterPeer,
          freshAfterEdit, upstreamFinal, witnessFinal,
        },
      });
    }

    const before = (await clients.writer.checkpoint()).sequenceNumber;
    const sourceText = caseId === "default-compressed"
      ? `compressed-${target}-` + "c".repeat(640_000)
      : deterministicText(`${target}:${caseId}`, 640_000);
    const peerHash = sha256(sourceText);
    const writerClientId = clients.writerSession.container.clientId;
    const beforeNativeEvidence = clients.native.evidence().delivered.length;
    if (caseId === "default-chunked") await clients.native.holdInbound();
    await clients.writer.set(["title"], sourceText);
    const writerCheckpoint = await clients.writer.awaitSynced();
    const batch = await observedPeerBatch(
      clients.writerSession, writerClientId, before,
    );
    const upstreamAfterPeer = await clients.writer.checkpoint();
    let prefixObservations = [];
    let boundary;
    if (caseId === "default-chunked") {
      boundary = await heldChunkPrefix(
        clients.native,
        batch.physical,
        target,
        caseId,
        sha256(JSON.stringify(baselineNative.wholeTree)),
        baselineNative.compressorSha256,
      );
      prefixObservations = boundary.prefixObservations;
      await clients.native.client.gate.release("inbound");
    }
    await clients.native.awaitSynced(batch.physical.at(-1).sequenceNumber);
    const nativeAfterPeer = await clients.native.checkpoint();
    assert.deepEqual(nativeAfterPeer.wholeTree, upstreamAfterPeer.wholeTree,
      `${target} native missed the complete compressed peer state`);
    const nativeRating = caseId === "default-compressed" ? 101 : 102;
    const outboundBefore = clients.native.evidence().outboundOccurrences.length;
    await clients.native.set(["rating"], nativeRating);
    await clients.native.awaitSynced();
    await Promise.all([clients.writer.awaitSynced(), clients.witness.awaitSynced()]);
    const nativeAfterEdit = await clients.native.checkpoint();
    const upstreamFinal = await clients.writer.checkpoint();
    const witnessFinal = await clients.witness.checkpoint();
    const witnessContent = witnessedLiteral(
      clients.witnessSession, peerHash, nativeRating,
    );
    const activation = await activationEvidence(
      clients.writerSession, batch.history,
    );
    const nativeEvidence = clients.native.evidence();
    const deliveredFrames = nativeEvidence.delivered.slice(beforeNativeEvidence)
      .filter(({ direction, kind }) => direction === "inbound" && kind === "op");
    const delivered = frameSequences(deliveredFrames)
      .filter((sequence) => batch.physical.some(({ sequenceNumber }) =>
        sequenceNumber === sequence));
    assert.deepEqual(
      [...new Set(delivered)].sort((left, right) => left - right),
      batch.physical.map(({ sequenceNumber }) => sequenceNumber),
      `${target} native delivery evidence missed compressed physical messages`,
    );
    assert.equal(
      nativeEvidence.outboundOccurrences.length - outboundBefore,
      1,
      `${target} native edit did not submit exactly once`,
    );
    const evidence = commonEvidence({
      writerSession: clients.writerSession,
      schema: activation.schema,
      activation,
      messages: batch.messages,
      physical: batch.physical,
      delivered: batch.physical.map(({ sequenceNumber }) => sequenceNumber),
      witnessContent,
      baseline: baselineNative,
      peerCompletion: nativeAfterPeer,
      nativeLocal: nativeAfterEdit,
      nativeSettlement: nativeAfterEdit,
      witnessCompletion: witnessFinal,
      upstreamPeerCompletion: upstreamAfterPeer,
      upstreamFinalCompletion: upstreamFinal,
      prefixObservations,
      nativeSubmissionOccurrences:
        nativeEvidence.outboundOccurrences.length - outboundBefore,
      pendingPositionsAfter: await pendingChunkStreamCount(clients.native),
    });
    return liveCellResult({
      runDirectory, target, caseId, runId, identities,
      documentId: document.documentId,
      evidence,
      raw: {
        document: documentEvidence(document),
        writerCheckpoint, baselineNative, upstreamAfterPeer,
        nativeAfterPeer, nativeAfterEdit, upstreamFinal, witnessFinal,
        nativeEvidence, serverHistory: batch.messages, activation,
        ...(boundary ? { boundary } : {}),
      },
    });
  } catch (caught) {
    error = caught;
    throw caught;
  } finally {
    for (const native of natives.toReversed()) {
      try {
        await native.close();
      } catch (cleanupError) {
        if (!error) throw cleanupError;
      }
    }
    cleanupOwned(containers, error);
  }
}

async function heldChunkPrefix(
  native,
  physical,
  target,
  caseId,
  baselineTreeSha256,
  baselineCompressorSha256,
) {
  await until(() => {
    const evidence = native.evidence();
    const sequences = new Set(frameSequences(evidence.currentlyHeld));
    return physical.every(({ sequenceNumber }) => sequences.has(sequenceNumber));
  }, `${target} ${caseId} held chunk frames`);
  const evidence = native.evidence();
  const finalSequence = physical.at(-1).sequenceNumber;
  const chunkFrames = evidence.currentlyHeld.filter(({ direction, kind, sequenceNumbers }) =>
    direction === "inbound"
    && kind === "op"
    && sequenceNumbers.some((sequence) =>
      physical.some(({ sequenceNumber }) => sequenceNumber === sequence)));
  const prefixFrames = chunkFrames.filter(({ sequenceNumbers }) =>
    sequenceNumbers.length > 0
    && sequenceNumbers.every((sequence) => sequence < finalSequence));
  assert(prefixFrames.length > 0,
    `${target} ${caseId} has no complete protocol frame before the final chunk`);
  const prefixObservations = [];
  for (const frame of prefixFrames) {
    await native.client.gate.release("inbound", { messageIds: [frame.id] });
    const watermark = Math.max(...frame.sequenceNumbers);
    let observation;
    await until(async () => {
      observation = await native.checkpoint();
      return observation.sequenceNumber >= watermark;
    }, `${target} ${caseId} consumed prefix through ${watermark}`);
    assert.equal(
      sha256(JSON.stringify(observation.wholeTree)),
      baselineTreeSha256,
      `${target} ${caseId} changed tree before the final chunk`,
    );
    assert.deepEqual(observation.events, [],
      `${target} ${caseId} emitted a tree event before the final chunk`);
    assert.deepEqual(observation.commits, [],
      `${target} ${caseId} emitted a commit before the final chunk`);
    observation.compressorSha256 = await compressorSha256(native);
    assert.equal(
      observation.compressorSha256,
      baselineCompressorSha256,
      `${target} ${caseId} changed compressor allocation state before the final chunk`,
    );
    prefixObservations.push(observation);
  }
  const delivered = native.evidence().delivered.filter(({ id }) =>
    prefixFrames.some((frame) => frame.id === id));
  const held = native.evidence().currentlyHeld.filter(({ direction, kind }) =>
    direction === "inbound" && kind === "op");
  const deliveredSequences = frameSequences(delivered)
    .filter((sequence) => physical.some(({ sequenceNumber }) =>
      sequenceNumber === sequence));
  const heldSequences = frameSequences(held)
    .filter((sequence) => physical.some(({ sequenceNumber }) =>
      sequenceNumber === sequence));
  assert(deliveredSequences.length > 0 && heldSequences.includes(finalSequence),
    `${target} ${caseId} did not retain the final chunk`);
  assert(deliveredSequences.at(-1) < finalSequence,
    `${target} ${caseId} prefix reached the final chunk`);
  return {
    prefixFrames,
    deliveredSequences,
    heldSequences,
    prefixObservations,
    controls: native.evidence().controls,
  };
}

async function runPartialCell(context, caseId) {
  const {
    config, target, schema, runId, runDirectory, identities,
  } = context;
  const restoreTarget = target === "javascript" ? "erlang" : "javascript";
  const containers = [];
  const natives = [];
  let error;
  try {
    const document = await createUpstreamDocument(config, containers);
    const clients = await openLiveClients(
      config, containers, target, schema, runId, caseId, document,
    );
    natives.push(clients.native);
    const initialNative = await clients.native.checkpoint();
    initialNative.compressorSha256 = await compressorSha256(clients.native);
    await clients.witness.checkpoint();
    const before = (await clients.writer.checkpoint()).sequenceNumber;
    const sourceText = deterministicText(`${target}:${caseId}`, 640_000);
    const peerHash = sha256(sourceText);
    const writerClientId = clients.writerSession.container.clientId;
    await clients.native.holdInbound();
    let pendingBefore = 0;
    let pendingHeld = 0;
    let batchBaseline = initialNative;
    let nativeLocal = initialNative;
    if (caseId === "checkpoint-partial") {
      await clients.native.holdOutbound();
      await clients.native.set(["rating"], 106);
      const pending = await clients.native.checkpoint();
      pending.compressorSha256 = await compressorSha256(clients.native);
      nativeLocal = pending;
      batchBaseline = pending;
      pendingBefore = pending.pendingTreeCount;
      pendingHeld = pending.inflightSubmissionCount;
      assert(pendingBefore > 0 && pendingHeld > 0,
        `${target} checkpoint cell did not hold native pending work`);
    }
    await clients.writer.set(["title"], sourceText);
    await clients.writer.awaitSynced();
    const batch = await observedPeerBatch(
      clients.writerSession, writerClientId, before,
    );
    const upstreamAfterPeer = await clients.writer.checkpoint();
    const boundary = await heldChunkPrefix(
      clients.native,
      batch.physical,
      target,
      caseId,
      sha256(JSON.stringify(batchBaseline.wholeTree)),
      batchBaseline.compressorSha256,
    );
    const activation = await activationEvidence(
      clients.writerSession, batch.history,
    );
    if (caseId === "summary-continuation") {
      let pendingSummary;
      let streams;
      await until(async () => {
        pendingSummary = await clients.native.pendingSummaryEvidence();
        streams = summaryChunkStreams(pendingSummary);
        return streams.length > 0;
      }, `${target} partial chunk summary state`);
      await writeCellArtifact(
        runDirectory, target, caseId, "pending-summary.json", pendingSummary,
      );
      const publication = await clients.native.summarizePublication();
      assert.equal(
        publication.snapshotSequenceNumber,
        boundary.deliveredSequences.at(-1),
        `${target} native summary did not publish the consumed chunk prefix`,
      );
      const publishedSummary = await publishedSummaryEvidence(
        clients.writerSession,
        publication.version,
      );
      await clients.native.client.gate.release("inbound");
      await clients.native.awaitSynced(batch.physical.at(-1).sequenceNumber);
      const sourceAfterPeer = await clients.native.checkpoint();
      const freshUpstreamSession = await openSession(
        config,
        containers,
        document.documentId,
        false,
        { cache: false, runtimeOptionMode: "default-compression" },
      );
      const freshUpstream = upstreamAdapter(freshUpstreamSession);
      const freshNative = await nativeAdapter(target, config, {
        ...clients.descriptor,
        runId: `${runId}-${caseId}-fresh`,
      }, clients.token);
      natives.push(freshNative);
      await Promise.all([
        freshUpstream.awaitSynced(batch.physical.at(-1).sequenceNumber),
        freshNative.awaitSynced(batch.physical.at(-1).sequenceNumber),
      ]);
      const freshUpstreamAfterPeer = await freshUpstream.checkpoint();
      const freshNativeAfterPeer = await freshNative.checkpoint();
      assert.deepEqual(freshNativeAfterPeer.wholeTree, freshUpstreamAfterPeer.wholeTree,
        `${target} fresh native did not load the published prefix and actual tail`);
      const nativeRating = 105;
      const outboundBefore = freshNative.evidence().outboundOccurrences.length;
      await freshNative.set(["rating"], nativeRating);
      await freshNative.awaitSynced();
      await Promise.all([
        freshUpstream.awaitSynced(),
        clients.writer.awaitSynced(),
        clients.witness.awaitSynced(),
      ]);
      const freshNativeAfterEdit = await freshNative.checkpoint();
      const upstreamAfterNative = await clients.writer.checkpoint();
      const witnessAfterNative = await clients.witness.checkpoint();
      await freshUpstream.set(["point", "y"], 205);
      await freshUpstream.awaitSynced();
      const continuedUpstream = await freshUpstream.checkpoint();
      await Promise.all([
        freshNative.awaitSynced(continuedUpstream.sequenceNumber),
        clients.witness.awaitSynced(continuedUpstream.sequenceNumber),
      ]);
      const continuedNative = await freshNative.checkpoint();
      const freshNativeEvidence = freshNative.evidence();
      const fetchedPublication = freshNativeEvidence.http.find(({ method, path, status }) =>
        method === "GET"
        && status >= 200
        && status < 300
        && path.endsWith(`/commits/${publication.version}`));
      assert(fetchedPublication,
        `${target} fresh native did not fetch the published summary version`);
      const witnessContent = witnessedLiteral(
        clients.witnessSession, peerHash, nativeRating,
      );
      const evidence = commonEvidence({
        writerSession: clients.writerSession,
        schema: activation.schema,
        activation,
        messages: batch.messages,
        physical: batch.physical,
        delivered: batch.physical.map(({ sequenceNumber }) => sequenceNumber),
        witnessContent,
        baseline: initialNative,
        peerCompletion: sourceAfterPeer,
        nativeLocal: freshNativeAfterEdit,
        nativeSettlement: freshNativeAfterEdit,
        witnessCompletion: witnessAfterNative,
        upstreamPeerCompletion: upstreamAfterPeer,
        upstreamFinalCompletion: upstreamAfterNative,
        prefixObservations: boundary.prefixObservations,
        nativeSubmissionOccurrences:
          freshNative.evidence().outboundOccurrences.length - outboundBefore,
        pendingPositionsAfter: await pendingChunkStreamCount(clients.native),
      });
      evidence.summary = {
        nativeHandle: publication.version,
        storedVersion: publishedSummary.version,
        storedSnapshotSha256: publishedSummary.snapshotSha256,
        freshNativeFetchedVersion: publication.version,
        snapshotSequenceNumber: publication.snapshotSequenceNumber,
        capabilityRetained: activation.schema.compressionLz4 === true,
        chunksPath: "/.chunks",
        chunkStreams: chunkStreamEvidence(streams),
        publishedChunkStreams:
          chunkStreamEvidence(publishedSummary.chunkStreams),
        selectedPrefix: boundary.deliveredSequences,
        heldFinal: boundary.heldSequences.at(-1),
        consumedWatermark: boundary.prefixObservations.at(-1).sequenceNumber,
        upstreamRead:
          freshUpstreamAfterPeer.sequenceNumber >= batch.physical.at(-1).sequenceNumber,
        nativeRead:
          freshNativeAfterPeer.sequenceNumber >= batch.physical.at(-1).sequenceNumber,
        tailConsumed:
          freshNativeAfterPeer.sequenceNumber >= batch.physical.at(-1).sequenceNumber,
        continuedEditing:
          sha256(JSON.stringify(continuedNative.wholeTree))
            === sha256(JSON.stringify(continuedUpstream.wholeTree))
          && sha256(JSON.stringify(continuedNative.wholeTree))
            !== sha256(JSON.stringify(freshNativeAfterEdit.wholeTree)),
        upstreamTreeSha256:
          sha256(JSON.stringify(freshUpstreamAfterPeer.wholeTree)),
        nativeTreeSha256:
          sha256(JSON.stringify(freshNativeAfterPeer.wholeTree)),
      };
      await writeCellArtifact(runDirectory, target, caseId, "summary.json", {
        pendingSummary, publication, publishedSummary, boundary,
      });
      return liveCellResult({
        runDirectory, target, caseId, runId, identities,
        documentId: document.documentId,
        evidence,
        raw: {
          serverHistory: batch.messages,
          sourceNative: clients.native.evidence(),
          freshNative: freshNativeEvidence,
          activation, initialNative, upstreamAfterPeer, sourceAfterPeer,
          freshUpstreamAfterPeer, freshNativeAfterPeer, freshNativeAfterEdit,
          upstreamAfterNative, witnessAfterNative, continuedNative,
          continuedUpstream, pendingSummary, publication, publishedSummary,
          boundary,
        },
      });
    }

    const checkpointReply = await clients.native.client.request({
      command: "pending-checkpoint",
    });
    assert.equal(checkpointReply.ok, true, `${target} pending checkpoint failed`);
    const checkpoint = checkpointReply.result;
    assert.equal(checkpoint.submissions.length, 1,
      `${target} checkpoint must retain one pending native submission`);
    const checkpointBatchId = string(
      checkpoint.submissions[0].batchId,
      `${target} checkpoint pending batch identity`,
    );
    assert.equal(
      checkpoint.summary.sequenceNumber,
      boundary.deliveredSequences.at(-1),
      `${target} checkpoint summary did not capture the consumed prefix`,
    );
    const checkpointStreams = summaryChunkStreams(checkpoint.summary);
    const checkpointPath = await writeCellArtifact(
      runDirectory, target, caseId, "checkpoint.json", checkpoint,
    );
    const originalInstance = clients.native.instanceId;
    const crash = await clients.native.client.crash();
    await clients.native.close();
    natives.pop();
    const restored = await nativeAdapter(restoreTarget, config, {
      ...clients.descriptor,
      runId: `${runId}-${caseId}-restore-${restoreTarget}`,
      pendingCheckpoint: checkpoint,
    }, clients.token, {
      configureGate(gate) {
        gate.hold("outbound", "op");
      },
    });
    natives.push(restored);
    assert.notEqual(restored.instanceId, originalInstance);
    let restoredAfterPeer;
    await until(async () => {
      restoredAfterPeer = await restored.checkpoint();
      return restoredAfterPeer.sequenceNumber >= batch.physical.at(-1).sequenceNumber;
    }, `${restoreTarget} restored native consumed the held final chunk`);
    await restored.releaseOutbound();
    await restored.awaitSynced(batch.physical.at(-1).sequenceNumber);
    await Promise.all([clients.writer.awaitSynced(), clients.witness.awaitSynced()]);
    const restoredSettled = await restored.checkpoint();
    const pendingHistory = batchBaseline.history.pending;
    assert.equal(pendingHistory.length, 1,
      `${target} saved checkpoint must retain one pending native revision`);
    const originalPendingRevision = string(
      pendingHistory[0].revision,
      `${target} saved pending revision`,
    );
    const settledHistoryPoint = nativeHistoryPoints(restoredSettled.history)
      .find(({ revision }) => revision === originalPendingRevision);
    assert(settledHistoryPoint,
      `${restoreTarget} native history lacks the saved pending revision`);
    const settlementHistory = await serverHistory(clients.writerSession);
    const acknowledgementMessages = settlementHistory.filter((message) =>
      messageBatchId(message) === checkpointBatchId);
    assert.equal(acknowledgementMessages.length, 1,
      `${restoreTarget} history must contain one acknowledgement for the saved batch`);
    const acknowledgement = acknowledgementMessages[0];
    assert.equal(
      acknowledgement.sequenceNumber,
      settledHistoryPoint.sequenceNumber,
      `${restoreTarget} saved revision history point differs from its acknowledgement`,
    );
    const upstreamAfterSettlement = await clients.writer.checkpoint();
    const witnessAfterSettlement = await clients.witness.checkpoint();
    await restored.set(["point", "y"], 206);
    await restored.awaitSynced();
    await Promise.all([clients.writer.awaitSynced(), clients.witness.awaitSynced()]);
    const continuedUpstream = await clients.writer.checkpoint();
    await restored.awaitSynced(continuedUpstream.sequenceNumber);
    const continuedRestored = await restored.checkpoint();
    assert.equal(restoredSettled.pendingTreeCount, 0);
    assert.equal(restoredSettled.inflightSubmissionCount, 0);
    const witnessContent = witnessedLiteral(
      clients.witnessSession, peerHash, 106,
    );
    const restoredEvidence = restored.evidence();
    const matchingOccurrences = restoredEvidence.outboundOccurrences.filter(
      (occurrence) => JSON.stringify(occurrence).includes(checkpointBatchId),
    );
    const continuationCommit = continuedRestored.commits.find(
      ({ type, local }) => type === "commit" && local === true,
    );
    assert(continuationCommit,
      `${restoreTarget} continuation lacks its own local commit observation`);
    assert.notEqual(continuationCommit.revision, originalPendingRevision,
      `${restoreTarget} continuation reused the saved pending revision`);
    const evidence = commonEvidence({
      writerSession: clients.writerSession,
      schema: activation.schema,
      activation,
      messages: batch.messages,
      physical: batch.physical,
      delivered: boundary.deliveredSequences,
      held: boundary.heldSequences,
      pending: { before: pendingBefore, held: pendingHeld, after: 0 },
      witnessContent,
      baseline: batchBaseline,
      peerCompletion: restoredAfterPeer,
      nativeLocal,
      nativeSettlement: restoredSettled,
      witnessCompletion: witnessAfterSettlement,
      upstreamPeerCompletion: upstreamAfterSettlement,
      upstreamFinalCompletion: upstreamAfterSettlement,
      prefixObservations: boundary.prefixObservations,
      nativeSubmissionOccurrences: matchingOccurrences.length,
      nativeSubmissionIdentity: checkpointBatchId,
      settledSubmissionIdentity: checkpointBatchId,
      pendingPositionsAfter: await pendingChunkStreamCount(restored),
      settlementProof: {
        revision: originalPendingRevision,
        sequenceNumber: acknowledgement.sequenceNumber,
      },
    });
    evidence.checkpoint = {
      artifact: checkpointPath,
      strictPrefix: boundary.deliveredSequences,
      heldSuffix: boundary.heldSequences,
      summarySequenceNumber: checkpoint.summary.sequenceNumber,
      consumedWatermark: boundary.prefixObservations.at(-1).sequenceNumber,
      chunkStreams: chunkStreamEvidence(checkpointStreams),
      prefixEndsBeforeFinalChunk: true,
      processSignal: crash.signal,
      processExited: crash.exited,
      processPid: crash.pid,
      processExitCode: crash.exitCode,
      restoredTarget: restoreTarget,
      tailConsumed:
        restoredAfterPeer.sequenceNumber >= batch.physical.at(-1).sequenceNumber,
      pendingSettled:
        restoredSettled.pendingTreeCount === 0
        && restoredSettled.inflightSubmissionCount === 0,
      continuedEditing:
        sha256(JSON.stringify(continuedRestored.wholeTree))
          === sha256(JSON.stringify(continuedUpstream.wholeTree))
        && sha256(JSON.stringify(continuedRestored.wholeTree))
          !== sha256(JSON.stringify(restoredSettled.wholeTree)),
      restoredTreeSha256: sha256(JSON.stringify(restoredSettled.wholeTree)),
      originalPendingRevision,
      settledRevision: settledHistoryPoint.revision,
      pendingBatchId: checkpointBatchId,
      acknowledgementBatchId: messageBatchId(acknowledgement),
      acknowledgementSequenceNumber: acknowledgement.sequenceNumber,
      settledHistoryPoint,
      liveSettlementEvents: restoredSettled.commits.filter(
        ({ type }) => type === "settlement",
      ).length,
      continuationRevision: continuationCommit.revision,
    };
    return liveCellResult({
      runDirectory, target, restoreTarget, caseId, runId, identities,
      documentId: document.documentId,
      evidence,
      raw: {
        serverHistory: batch.messages, boundary,
        sourceNative: clients.native.evidence(),
        restoredNative: restoredEvidence, activation,
        initialNative, batchBaseline, nativeLocal, upstreamAfterPeer,
        checkpoint, checkpointStreams, crash, restoredAfterPeer,
        restoredSettled, settlementHistory, acknowledgement,
        originalPendingRevision, settledHistoryPoint,
        upstreamAfterSettlement, witnessAfterSettlement,
        continuedRestored, continuedUpstream,
        checkpointBatchId, matchingOccurrences,
      },
    });
  } catch (caught) {
    error = caught;
    throw caught;
  } finally {
    for (const native of natives.toReversed()) {
      try {
        await native.close();
      } catch (cleanupError) {
        if (!error) throw cleanupError;
      }
    }
    cleanupOwned(containers, error);
  }
}

async function runReconnectCell(context) {
  const {
    config, target, schema, runId, runDirectory, identities,
  } = context;
  const caseId = "reconnect-pending";
  const containers = [];
  const natives = [];
  let error;
  try {
    const document = await createUpstreamDocument(config, containers);
    const clients = await openLiveClients(
      config, containers, target, schema, runId, caseId, document,
    );
    natives.push(clients.native);
    const baselineNative = await clients.native.checkpoint();
    baselineNative.compressorSha256 = await compressorSha256(clients.native);
    await clients.witness.checkpoint();
    const before = (await clients.writer.checkpoint()).sequenceNumber;
    await clients.native.holdInbound();
    const outboundBefore = clients.native.evidence().outboundOccurrences.length;
    const nativeRating = 104;
    await clients.native.set(["rating"], nativeRating);
    await until(() => clients.native.evidence().currentlyHeld.some(
      ({ direction, kind }) => direction === "inbound" && kind === "op",
    ), `${target} held native acknowledgement`);
    const pending = await clients.native.checkpoint();
    pending.compressorSha256 = await compressorSha256(clients.native);
    assert(pending.pendingTreeCount > 0, `${target} native work was not pending`);
    await clients.native.client.gate.disconnect();
    const sourceText = deterministicText(`${target}:${caseId}`, 640_000);
    const peerHash = sha256(sourceText);
    const writerClientId = clients.writerSession.container.clientId;
    await clients.writer.set(["title"], sourceText);
    await clients.writer.awaitSynced();
    const batch = await observedPeerBatch(
      clients.writerSession, writerClientId, before,
    );
    const upstreamAfterPeer = await clients.writer.checkpoint();
    await clients.native.client.gate.reconnect();
    await clients.native.awaitSynced(batch.physical.at(-1).sequenceNumber);
    await Promise.all([clients.writer.awaitSynced(), clients.witness.awaitSynced()]);
    const settled = await clients.native.checkpoint();
    const upstreamFinal = await clients.writer.checkpoint();
    const witnessFinal = await clients.witness.checkpoint();
    assert.equal(settled.pendingTreeCount, 0);
    assert.equal(settled.inflightSubmissionCount, 0);
    const nativeEvidence = clients.native.evidence();
    const occurrences =
      nativeEvidence.outboundOccurrences.length - outboundBefore;
    assert.equal(occurrences, 1, `${target} native pending edit was submitted more than once`);
    const witnessContent = witnessedLiteral(
      clients.witnessSession, peerHash, nativeRating,
    );
    const activation = await activationEvidence(
      clients.writerSession, batch.history,
    );
    const evidence = commonEvidence({
      writerSession: clients.writerSession,
      schema: activation.schema,
      activation,
      messages: batch.messages,
      physical: batch.physical,
      delivered: batch.physical.map(({ sequenceNumber }) => sequenceNumber),
      pending: {
        before: pending.pendingTreeCount,
        held: pending.inflightSubmissionCount,
        after: settled.pendingTreeCount,
      },
      witnessContent,
      baseline: pending,
      peerCompletion: settled,
      nativeLocal: pending,
      nativeSettlement: settled,
      witnessCompletion: witnessFinal,
      upstreamPeerCompletion: upstreamAfterPeer,
      upstreamFinalCompletion: upstreamFinal,
      nativeSubmissionOccurrences: occurrences,
      pendingPositionsAfter: await pendingChunkStreamCount(clients.native),
    });
    const pendingCommit = pending.commits.find(
      ({ type, local }) => type === "commit" && local === true,
    );
    const settlement = settled.commits.find(({ type }) => type === "settlement");
    assert(pendingCommit && settlement,
      `${target} reconnect lacks pending and settlement commit identities`);
    evidence.reconnect = {
      acknowledgementHeld: true,
      disconnected: true,
      caughtUpThrough: settled.sequenceNumber,
      settledExactlyOnce: occurrences === 1,
      submissionOccurrences: occurrences,
      pendingActionId: pendingCommit.actionId,
      settledActionId: settlement.actionId,
      peerContentSha256: peerHash,
    };
    return liveCellResult({
      runDirectory, target, caseId, runId, identities,
      documentId: document.documentId,
      evidence,
      raw: {
        serverHistory: batch.messages, baselineNative, pending, settled,
        upstreamAfterPeer, upstreamFinal, witnessFinal,
        nativeEvidence, activation,
      },
    });
  } catch (caught) {
    error = caught;
    throw caught;
  } finally {
    for (const native of natives.toReversed()) {
      try {
        await native.close();
      } catch (cleanupError) {
        if (!error) throw cleanupError;
      }
    }
    cleanupOwned(containers, error);
  }
}

async function runCompressionCell(context, caseId) {
  if (caseId === "reconnect-pending") return runReconnectCell(context);
  if (caseId === "summary-continuation" || caseId === "checkpoint-partial") {
    return runPartialCell(context, caseId);
  }
  return runSimpleCell(context, caseId);
}

export async function runCompressionInterop() {
  const runId = randomUUID();
  const runDirectory = join(outputDirectory, runId);
  const identities = await compressionIdentity();
  assert.equal(
    sha256(await readFile(resolve(repository, "test/fixtures/shared_tree/profile.json"))),
    legacyProfileSha256,
  );
  const schemaFixture = JSON.parse(await readFile(resolve(
    repository,
    "test/fixtures/shared_tree/cases/schema-profile.json",
  )));
  const schema = schemaFixture.input.summary.tree.indexes.tree.Schema
    .tree.SchemaString.content;
  await mkdir(runDirectory, { recursive: true });
  for (const target of compressionTargets) {
    execFileSync("gleam", ["build", "--target", target], {
      cwd: repository,
      stdio: "inherit",
    });
  }
  const results = await withLocalFloodgate(async (config) => {
    const rows = [];
    for (const target of compressionTargets) {
      for (const caseId of compressionCases) {
        rows.push(await runCompressionCell({
          config, target, schema, runId, runDirectory, identities,
        }, caseId));
      }
    }
    return rows;
  });
  validateCompressionResults(results, runId, identities.profileDigest);
  const report = {
    formatVersion: 1,
    runId,
    generatedAt: new Date().toISOString(),
    identities: {
      ...identities,
      spillwayRevision,
      floodgateRevision,
      legacyProfileSha256,
    },
    results,
  };
  await writeFile(join(runDirectory, "results.json"),
    `${JSON.stringify(report, null, 2)}\n`, { mode: 0o600 });
  return { report, runDirectory };
}

async function main() {
  if (process.argv[2] === "benchmark" && process.argv.length === 3) {
    const report = await runBenchmark();
    console.log(JSON.stringify({
      report: reportPath,
      javascript: report.targets.javascript.ratio4MiBTo1MiB,
      erlang: report.targets.erlang.ratio4MiBTo1MiB,
    }));
    return;
  }
  if (process.argv[2] === "interop"
    && process.argv[3] === "--local-floodgate"
    && process.argv.length === 4) {
    const { report, runDirectory } = await runCompressionInterop();
    console.log(JSON.stringify({
      runId: report.runId,
      cells: report.results.length,
      report: join(runDirectory, "results.json"),
    }));
    return;
  }
  fail("usage: node compression-interop.mjs benchmark | interop --local-floodgate");
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await main();
}
