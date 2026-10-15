import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { readdirSync } from "node:fs";
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
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
  let payloadBytes = 0;
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
    nonnegativeInteger(message.payloadBytes, `${label} physical payload bytes ${index}`);
    payloadBytes += message.payloadBytes;
    batchIds.add(string(message.batchId, `${label} physical batch identity ${index}`));
  }
  if (batchIds.size !== 1
    || !batchIds.has(string(evidence.finalBatchIdentity, `${label} final batch identity`))) {
    fail(`${label} physical messages do not share the final batch identity`);
  }
  const compressed = messages.filter(({ compression }) => compression === "lz4");
  if (compressed.length === 0) fail(`${label} has no observed lz4 compression`);
  const sizes = object(evidence.byteSizes, `${label} byteSizes`);
  const sourceBytes = positiveInteger(sizes.sourceBytes, `${label} source bytes`);
  const compressedBytes = positiveInteger(sizes.compressedBytes, `${label} compressed bytes`);
  positiveInteger(sizes.decodedBytes, `${label} decoded bytes`);
  positiveInteger(sizes.highEntropyInputBytes, `${label} high-entropy input bytes`);
  digestString(sizes.highEntropySha256, 64, `${label} high-entropy input hash`);
  if (sourceBytes <= defaultCompressionThreshold) {
    fail(`${label} input did not cross the default compression threshold`);
  }
  if (payloadBytes !== compressedBytes) {
    fail(`${label} compressed bytes do not match observed physical payload bytes`);
  }
  const chunked = caseId !== "default-compressed";
  if (chunked) {
    if (sizes.highEntropyInputBytes <= defaultCompressionThreshold) {
      fail(`${label} high-entropy chunk input did not cross the default threshold`);
    }
    if (messages.length < 2 || compressedBytes <= defaultChunkSize) {
      fail(`${label} chunk evidence does not cross ${defaultChunkSize} bytes`);
    }
    messages.forEach((message, index) => {
      if (message.contentsType !== "chunkedOp"
        || message.chunkId !== index + 1
        || message.totalChunks !== messages.length) {
        fail(`${label} physical chunk ${index} has invalid chunk IDs or count`);
      }
    });
  } else {
    if (messages.length !== 1 || compressedBytes > defaultChunkSize
      || messages[0].contentsType === "chunkedOp") {
      fail(`${label} compressed unchunked evidence is invalid`);
    }
  }
  const delivery = object(evidence.deliveredSequences, `${label} deliveredSequences`);
  const delivered = array(delivery.delivered, `${label} delivered sequences`);
  const held = array(delivery.held, `${label} held sequences`);
  for (const sequence of [...delivered, ...held]) {
    integer(sequence, `${label} delivered or held sequence`);
    if (!seenSequences.has(sequence)) {
      fail(`${label} delivered sequence ${sequence} is not an observed physical message`);
    }
  }
  if (new Set([...delivered, ...held]).size !== messages.length) {
    fail(`${label} delivered and held sequences do not cover the physical messages`);
  }
  if (delivery.final !== messages.at(-1).sequenceNumber) {
    fail(`${label} final delivered sequence does not identify the final physical message`);
  }
  return { messages, delivered, held };
}

function validateCommonSemantics(evidence, label) {
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
  if (commits.peerLogicalBatches !== 1
    || commits.nativeSubmitted !== 1
    || commits.nativeSettled !== 1
    || commits.witnessObserved !== 1) {
    fail(`${label} logical commit counts do not prove exactly-once collaboration`);
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
}

function validateReconnect(evidence, label) {
  if (evidence.pendingCounts.before < 1 || evidence.pendingCounts.held < 1) {
    fail(`${label} reconnect has no held pending native work`);
  }
  const reconnect = object(evidence.reconnect, `${label} reconnect`);
  exactTrue(reconnect.acknowledgementHeld, `${label} held acknowledgement`);
  exactTrue(reconnect.disconnected, `${label} disconnect`);
  positiveInteger(reconnect.caughtUpThrough, `${label} catch-up sequence`);
  exactTrue(reconnect.settledExactlyOnce, `${label} exactly-once settlement`);
  if (reconnect.submissionOccurrences !== 1) {
    fail(`${label} reconnect repeated or lost the native submission`);
  }
}

function validateSummary(evidence, label) {
  const summary = object(evidence.summary, `${label} summary`);
  string(summary.nativeHandle, `${label} native summary handle`);
  exactTrue(summary.capabilityRetained, `${label} retained summary capability`);
  if (summary.chunksPath !== "/.chunks") fail(`${label} summary omits /.chunks`);
  const streams = array(summary.chunkStreams, `${label} summary chunk streams`);
  if (streams.length === 0) fail(`${label} summary has no retained chunk stream`);
  for (const [index, streamValue] of streams.entries()) {
    const stream = object(streamValue, `${label} summary stream ${index}`);
    string(stream.clientId, `${label} summary stream client ${index}`);
    if (array(stream.pieces, `${label} summary stream pieces ${index}`).length === 0) {
      fail(`${label} summary stream ${index} has no prefix pieces`);
    }
  }
  for (const field of ["upstreamRead", "nativeRead", "tailConsumed", "continuedEditing"]) {
    exactTrue(summary[field], `${label} summary ${field}`);
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
  if (checkpoint.restoredTarget !== result.restoreTarget
    || result.restoreTarget === result.target
    || !compressionTargets.includes(result.restoreTarget)) {
    fail(`${label} checkpoint restore target is not the opposite native target`);
  }
  for (const field of ["tailConsumed", "pendingSettled", "continuedEditing"]) {
    exactTrue(checkpoint[field], `${label} checkpoint ${field}`);
  }
}

export function validateCompressionResults(results, runId, profileDigest) {
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
    if (result.runId !== runId) fail(`${key} runId is stale`);
    if (result.profileDigest !== profileDigest) fail(`${key} profileDigest is stale`);
    digestString(result.probeDigest, 64, `${key} probeDigest`);
    digestString(result.sourceDigest, 40, `${key} sourceDigest`);
    digestString(result.extensionDigest, 64, `${key} extensionDigest`);
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
    validateCommonSemantics(evidence, key);
    const sequences = physical.messages.map(({ sequenceNumber }) => sequenceNumber);
    if (caseId === "history-catchup") validateHistory(evidence, key, sequences);
    if (caseId === "reconnect-pending") validateReconnect(evidence, key);
    if (caseId === "summary-continuation") validateSummary(evidence, key);
    if (caseId === "checkpoint-partial") {
      validateCheckpoint(result, evidence, key, physical);
    } else if (result.restoreTarget !== undefined) {
      fail(`${key} unexpectedly records a restoreTarget`);
    }
  }
  if (expected.size > 0) fail(`missing compression cells: ${[...expected].join(", ")}`);
  return results;
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
    const packed = contents?.packedContents;
    const payloadBytes = chunk
      ? Buffer.byteLength(chunk.contents)
      : typeof packed === "string"
        ? Buffer.from(packed, "base64").byteLength
        : Buffer.byteLength(JSON.stringify(contents));
    return {
      sequenceNumber: message.sequenceNumber,
      clientSequenceNumber: message.clientSequenceNumber,
      referenceSequenceNumber: message.referenceSequenceNumber,
      clientId: message.clientId,
      type: message.type,
      compression: message.compression ?? chunk?.originalCompression ?? null,
      metadata: message.metadata ?? chunk?.originalMetadata ?? {},
      contentsType: chunk ? "chunkedOp" : contents?.type ?? "packedContents",
      payloadBytes,
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

function documentEvidence(document) {
  return {
    documentId: document.documentId,
    nativeCreated: document.nativeCreated,
    ...(document.creation ? { creation: document.creation } : {}),
  };
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
  physical,
  sourceText,
  highEntropy,
  delivered,
  held = [],
  pending = { before: 0, held: 0, after: 0 },
  witnessContent,
}) {
  const compressedBytes = physical.reduce((total, message) =>
    total + message.payloadBytes, 0);
  return {
    runtimeOptions: observedRuntimeOptions(writerSession),
    capability: {
      schemaActivationObserved: activation.observed,
      compressionEnabled: schema.compressionLz4 === true,
      refSeq: schema.refSeq,
    },
    physicalMessages: physical,
    byteSizes: {
      sourceBytes: Buffer.byteLength(JSON.stringify(sourceText)),
      compressedBytes,
      decodedBytes: Buffer.byteLength(JSON.stringify(sourceText)),
      highEntropyInputBytes: Buffer.byteLength(highEntropy),
      highEntropySha256: sha256(highEntropy),
    },
    deliveredSequences: {
      held,
      delivered,
      final: physical.at(-1).sequenceNumber,
    },
    pendingCounts: pending,
    commitCounts: {
      peerLogicalBatches: 1,
      nativeSubmitted: 1,
      nativeSettled: 1,
      witnessObserved: 1,
    },
    finalBatchIdentity: physical.at(-1).batchId,
    gcRoutes: actualRoutes(writerSession),
    schemaFlags: {
      compression: schema.compressionLz4 === true,
      idCompressor: schema.idCompressorMode === "on",
    },
    witnessContent,
    bidirectionalEdits: {
      peerObservedByNative: true,
      nativeObservedByWitness: true,
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
      assert(JSON.stringify((await fresh.checkpoint()).wholeTree).includes(sourceText.slice(0, 64)),
        `${target} fresh native did not consume HTTP history`);
      const nativeRating = 107;
      await fresh.set(["rating"], nativeRating);
      await fresh.awaitSynced();
      await clients.witness.awaitSynced();
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
        physical: batch.physical,
        sourceText,
        highEntropy: sourceText,
        delivered: batch.physical.map(({ sequenceNumber }) => sequenceNumber),
        witnessContent,
      });
      evidence.history = {
        transport: "http-delta",
        requestedFrom: before + 1,
        requestedTo: batch.physical.at(-1).sequenceNumber + 1,
        compressedSequences: batch.physical.map(({ sequenceNumber }) => sequenceNumber),
        requests: delta,
        handshakeInjection: nativeEvidence.injections.find(
          ({ mutation }) => mutation === "omit-initial-messages",
        ),
      };
      await writeCellArtifact(runDirectory, target, caseId, "raw.json", {
        document: documentEvidence(document),
        summary, nativeEvidence, serverHistory: batch.messages,
        activation,
      });
      return {
        artifactKind: "live",
        target, caseId, runId, ...identities,
        documentId: document.documentId, passed: true, skipped: false, evidence,
      };
    }

    const before = (await clients.writer.checkpoint()).sequenceNumber;
    const sourceText = caseId === "default-compressed"
      ? `compressed-${target}-` + "c".repeat(640_000)
      : deterministicText(`${target}:${caseId}`, 640_000);
    const peerHash = sha256(sourceText);
    const writerClientId = clients.writerSession.container.clientId;
    const beforeNativeEvidence = clients.native.evidence().delivered.length;
    await clients.writer.set(["title"], sourceText);
    const writerCheckpoint = await clients.writer.awaitSynced();
    const batch = await observedPeerBatch(
      clients.writerSession, writerClientId, before,
    );
    await clients.native.awaitSynced(batch.physical.at(-1).sequenceNumber);
    const nativeAfterPeer = await clients.native.checkpoint();
    assert(JSON.stringify(nativeAfterPeer.wholeTree).includes(sourceText.slice(0, 64)),
      `${target} native missed the compressed peer edit`);
    const nativeRating = caseId === "default-compressed" ? 101 : 102;
    const outboundBefore = clients.native.evidence().outboundOccurrences.length;
    await clients.native.set(["rating"], nativeRating);
    await clients.native.awaitSynced();
    await clients.witness.awaitSynced();
    const nativeAfterEdit = await clients.native.checkpoint();
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
      physical: batch.physical,
      sourceText,
      highEntropy: sourceText,
      delivered: batch.physical.map(({ sequenceNumber }) => sequenceNumber),
      witnessContent,
    });
    await writeCellArtifact(runDirectory, target, caseId, "raw.json", {
      document: documentEvidence(document),
      writerCheckpoint, nativeAfterPeer, nativeAfterEdit,
      nativeEvidence, serverHistory: batch.messages, activation,
    });
    return {
      artifactKind: "live",
      target, caseId, runId, ...identities,
      documentId: document.documentId, passed: true, skipped: false, evidence,
    };
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

async function heldChunkPrefix(native, physical, target, caseId) {
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
  await native.client.gate.release("inbound", {
    messageIds: prefixFrames.map(({ id }) => id),
  });
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
    const before = (await clients.writer.checkpoint()).sequenceNumber;
    const sourceText = deterministicText(`${target}:${caseId}`, 640_000);
    const peerHash = sha256(sourceText);
    const writerClientId = clients.writerSession.container.clientId;
    await clients.native.holdInbound();
    let pendingBefore = 0;
    let pendingHeld = 0;
    if (caseId === "checkpoint-partial") {
      await clients.native.holdOutbound();
      await clients.native.set(["rating"], 106);
      const pending = await clients.native.checkpoint();
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
    const boundary = await heldChunkPrefix(
      clients.native, batch.physical, target, caseId,
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
      await clients.native.client.gate.release("inbound");
      await clients.native.awaitSynced(batch.physical.at(-1).sequenceNumber);
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
      assert.equal(sha256(freshUpstreamSession.data.view.root.title), peerHash);
      assert(JSON.stringify((await freshNative.checkpoint()).wholeTree)
        .includes(sourceText.slice(0, 64)));
      const nativeRating = 105;
      await freshNative.set(["rating"], nativeRating);
      await freshNative.awaitSynced();
      await clients.witness.awaitSynced();
      await freshUpstream.set(["enabled"], false);
      await freshUpstream.awaitSynced();
      await freshNative.awaitSynced();
      const witnessContent = witnessedLiteral(
        clients.witnessSession, peerHash, nativeRating,
      );
      const evidence = commonEvidence({
        writerSession: clients.writerSession,
        schema: activation.schema,
        activation,
        physical: batch.physical,
        sourceText,
        highEntropy: sourceText,
        delivered: batch.physical.map(({ sequenceNumber }) => sequenceNumber),
        witnessContent,
      });
      evidence.summary = {
        nativeHandle: publication.version,
        capabilityRetained: activation.schema.compressionLz4 === true,
        chunksPath: "/.chunks",
        chunkStreams: streams,
        upstreamRead: true,
        nativeRead: true,
        tailConsumed: true,
        continuedEditing: true,
      };
      await writeCellArtifact(runDirectory, target, caseId, "summary.json", {
        pendingSummary, publication, boundary,
      });
      await writeCellArtifact(runDirectory, target, caseId, "raw.json", {
        serverHistory: batch.messages,
        sourceNative: clients.native.evidence(),
        freshNative: freshNative.evidence(),
        activation,
      });
      return {
        artifactKind: "live",
        target, caseId, runId, ...identities,
        documentId: document.documentId, passed: true, skipped: false, evidence,
      };
    }

    const checkpointReply = await clients.native.client.request({
      command: "pending-checkpoint",
    });
    assert.equal(checkpointReply.ok, true, `${target} pending checkpoint failed`);
    const checkpoint = checkpointReply.result;
    const checkpointPath = await writeCellArtifact(
      runDirectory, target, caseId, "checkpoint.json", checkpoint,
    );
    const originalInstance = clients.native.instanceId;
    await clients.native.client.crash();
    await clients.native.close();
    natives.pop();
    const restored = await nativeAdapter(restoreTarget, config, {
      ...clients.descriptor,
      runId: `${runId}-${caseId}-restore-${restoreTarget}`,
      pendingCheckpoint: checkpoint,
    }, clients.token);
    natives.push(restored);
    assert.notEqual(restored.instanceId, originalInstance);
    await restored.awaitSynced(batch.physical.at(-1).sequenceNumber);
    assert(JSON.stringify((await restored.checkpoint()).wholeTree)
      .includes(sourceText.slice(0, 64)));
    await restored.set(["enabled"], false);
    await restored.awaitSynced();
    await clients.witness.awaitSynced();
    const settled = await restored.checkpoint();
    assert.equal(settled.pendingTreeCount, 0);
    assert.equal(settled.inflightSubmissionCount, 0);
    const witnessContent = witnessedLiteral(
      clients.witnessSession, peerHash, 106,
    );
    const evidence = commonEvidence({
      writerSession: clients.writerSession,
      schema: activation.schema,
      activation,
      physical: batch.physical,
      sourceText,
      highEntropy: sourceText,
      delivered: boundary.deliveredSequences,
      held: boundary.heldSequences,
      pending: { before: pendingBefore, held: pendingHeld, after: 0 },
      witnessContent,
    });
    evidence.checkpoint = {
      artifact: checkpointPath,
      strictPrefix: boundary.deliveredSequences,
      heldSuffix: boundary.heldSequences,
      prefixEndsBeforeFinalChunk: true,
      processSignal: "SIGKILL",
      processExited: true,
      restoredTarget: restoreTarget,
      tailConsumed: true,
      pendingSettled: true,
      continuedEditing: true,
    };
    await writeCellArtifact(runDirectory, target, caseId, "raw.json", {
      serverHistory: batch.messages, boundary,
      sourceNative: clients.native.evidence(),
      restoredNative: restored.evidence(), activation, settled,
    });
    return {
      artifactKind: "live",
      target, restoreTarget, caseId, runId, ...identities,
      documentId: document.documentId, passed: true, skipped: false, evidence,
    };
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
    const before = (await clients.writer.checkpoint()).sequenceNumber;
    await clients.native.holdInbound();
    const outboundBefore = clients.native.evidence().outboundOccurrences.length;
    const nativeRating = 104;
    await clients.native.set(["rating"], nativeRating);
    await until(() => clients.native.evidence().currentlyHeld.some(
      ({ direction, kind }) => direction === "inbound" && kind === "op",
    ), `${target} held native acknowledgement`);
    const pending = await clients.native.checkpoint();
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
    await clients.native.client.gate.reconnect();
    await clients.native.awaitSynced(batch.physical.at(-1).sequenceNumber);
    await clients.witness.awaitSynced();
    const settled = await clients.native.checkpoint();
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
      physical: batch.physical,
      sourceText,
      highEntropy: sourceText,
      delivered: batch.physical.map(({ sequenceNumber }) => sequenceNumber),
      pending: {
        before: pending.pendingTreeCount,
        held: pending.inflightSubmissionCount,
        after: settled.pendingTreeCount,
      },
      witnessContent,
    });
    evidence.reconnect = {
      acknowledgementHeld: true,
      disconnected: true,
      caughtUpThrough: settled.sequenceNumber,
      settledExactlyOnce: occurrences === 1,
      submissionOccurrences: occurrences,
    };
    await writeCellArtifact(runDirectory, target, caseId, "raw.json", {
      serverHistory: batch.messages, pending, settled, nativeEvidence, activation,
    });
    return {
      artifactKind: "live",
      target, caseId, runId, ...identities,
      documentId: document.documentId, passed: true, skipped: false, evidence,
    };
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
