import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { decompress } from "./node_modules/lz4js/lz4.js";

import {
  compressionSourceIdentity,
  reference,
} from "./source.mjs";

const directory = dirname(fileURLToPath(import.meta.url));
const sourcePath = resolve(directory, ".output/compression-source/compression.json");
const fixturePath = resolve(directory, "../../test/fixtures/shared_tree/compression.json");
const profilePath = resolve(
  directory,
  "../../test/fixtures/shared_tree/compression-profile.json",
);
const legacyProfilePath = resolve(directory, "../../test/fixtures/shared_tree/profile.json");
const legacyProfileDigest =
  "29fe106785ec1705cd1ac4d45de8e88f9a6cc89487c3b7cd1df6ad65b318b1de";

const requiredCases = [
  "plain-singleton",
  "plain-group",
  "default-compressed-singleton",
  "default-compressed-group",
  "default-chunked-group",
  "interleaved-senders",
  "empty-final-chunk",
  "empty-group",
  "id-allocation-before-tree-use",
  "handle-valued-edits",
  "partial-summary-prefix-tail",
  "unmarked-packed-content",
  "unknown-algorithm",
  "multi-message-compressed-array",
  "missing-prefix",
  "malformed-frame",
  "nested-compression",
  "native-format-without-compression-lz4",
  "schema-activation",
  "stale-competing-proposals",
  "future-schema-reference",
  "invalid-schema-reference",
  "post-activation-compressed-operation",
];

const requiredFrames = [
  "literal-block",
  "overlapping-match",
  "multi-block-match",
  "utf8",
  "benchmark-1mib",
  "benchmark-4mib",
];

const negativeCases = [
  "unmarked-packed-content",
  "unknown-algorithm",
  "multi-message-compressed-array",
  "missing-prefix",
  "malformed-frame",
  "nested-compression",
  "future-schema-reference",
  "invalid-schema-reference",
];
const upstreamObservedCases = negativeCases.slice(0, 6);
const nonemptyCases = [
  "plain-singleton",
  "plain-group",
  "default-compressed-singleton",
  "default-compressed-group",
  "default-chunked-group",
  "interleaved-senders",
  "empty-final-chunk",
  "empty-group",
  "id-allocation-before-tree-use",
  "handle-valued-edits",
  "partial-summary-prefix-tail",
  "schema-activation",
  "stale-competing-proposals",
  "post-activation-compressed-operation",
];
const directCompressedCases = [
  "default-compressed-singleton",
  "default-compressed-group",
  "id-allocation-before-tree-use",
  "handle-valued-edits",
  "post-activation-compressed-operation",
];
const runtimeMessageCases = requiredCases.filter((id) => ![
  "native-format-without-compression-lz4",
  "schema-activation",
  "stale-competing-proposals",
  "future-schema-reference",
  "invalid-schema-reference",
].includes(id));
const routedTreeCases = [
  "default-compressed-singleton",
  "default-compressed-group",
  "default-chunked-group",
  "partial-summary-prefix-tail",
  "post-activation-compressed-operation",
];

function fail(message) {
  throw new Error(`Invalid compression capture: ${message}`);
}

function object(value, name) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    fail(`${name} must be an object`);
  }
  return value;
}

function array(value, name) {
  if (!Array.isArray(value)) fail(`${name} must be an array`);
  return value;
}

function integer(value, name) {
  if (!Number.isInteger(value) || value < 0) fail(`${name} must be a non-negative integer`);
  return value;
}

function string(value, name) {
  if (typeof value !== "string" || value.length === 0) fail(`${name} must be a string`);
  return value;
}

function boolean(value, name) {
  if (typeof value !== "boolean") fail(`${name} must be a boolean`);
  return value;
}

function sequencedMessage(value, name) {
  const message = object(value, name);
  string(message.clientId, `${name}.clientId`);
  for (const field of [
    "clientSequenceNumber",
    "minimumSequenceNumber",
    "referenceSequenceNumber",
    "sequenceNumber",
    "timestamp",
  ]) {
    integer(message[field], `${name}.${field}`);
  }
  string(message.type, `${name}.type`);
  object(message.contents, `${name}.contents`);
  if (message.metadata !== undefined) object(message.metadata, `${name}.metadata`);
  if (message.compression !== undefined) string(message.compression, `${name}.compression`);
  return message;
}

function normalizedRuntimeResult(value, name) {
  const result = object(value, name);
  if (result.type !== "fullBatch") fail(`${name}.type must be fullBatch`);
  boolean(result.groupedBatch, `${name}.groupedBatch`);
  array(result.messages, `${name}.messages`).forEach((message, index) =>
    sequencedMessage(message, `${name}.messages[${index}]`));
  return result;
}

function documentSchema(value, name, integerReference = true) {
  const schema = object(value, name);
  integer(schema.version, `${name}.version`);
  if (integerReference) {
    integer(schema.refSeq, `${name}.refSeq`);
  } else if (typeof schema.refSeq !== "number" || !Number.isFinite(schema.refSeq)) {
    fail(`${name}.refSeq must be a number`);
  }
  const info = object(schema.info, `${name}.info`);
  string(info.minVersionForCollab, `${name}.info.minVersionForCollab`);
  const runtime = object(schema.runtime, `${name}.runtime`);
  boolean(runtime.explicitSchemaControl, `${name}.runtime.explicitSchemaControl`);
  for (const field of ["compressionLz4", "opGroupingEnabled"]) {
    if (runtime[field] !== undefined) boolean(runtime[field], `${name}.runtime.${field}`);
  }
  return schema;
}

function chunkSummary(value, name, maxStreams = 64, maxChunks = 128) {
  const entries = array(value, name);
  if (entries.length === 0 || entries.length > maxStreams) {
    fail(`${name} must contain between 1 and ${maxStreams} streams`);
  }
  const senders = new Set();
  entries.forEach((value, index) => {
    const entry = array(value, `${name}[${index}]`);
    if (entry.length !== 2) fail(`${name}[${index}] must be a sender and chunk-prefix tuple`);
    const sender = string(entry[0], `${name}[${index}] sender`);
    if (senders.has(sender)) fail(`${name} has duplicate sender ${sender}`);
    senders.add(sender);
    const prefixes = array(entry[1], `${name}[${index}] chunk prefixes`);
    if (prefixes.length === 0 || prefixes.length > maxChunks) {
      fail(`${name}[${index}] must contain between 1 and ${maxChunks} chunk prefixes`);
    }
    prefixes.forEach((prefix, chunkIndex) =>
      string(prefix, `${name}[${index}] chunk prefix ${chunkIndex}`));
  });
  return entries;
}

function uniqueById(values, name) {
  const result = new Map();
  for (const value of values) {
    const entry = object(value, `${name} entry`);
    const id = string(entry.id, `${name} id`);
    if (result.has(id)) fail(`${name} has duplicate id ${id}`);
    result.set(id, entry);
  }
  return result;
}

function decodedBase64Length(value, name) {
  string(value, name);
  const bytes = Buffer.from(value, "base64");
  if (bytes.toString("base64") !== value) fail(`${name} is not canonical base64`);
  return bytes.byteLength;
}

function lz4Frame(value, name) {
  string(value, name);
  const bytes = Buffer.from(value, "base64");
  if (bytes.toString("base64") !== value) fail(`${name} is not canonical base64`);
  if (bytes.byteLength < 11
    || bytes[0] !== 0x04
    || bytes[1] !== 0x22
    || bytes[2] !== 0x4d
    || bytes[3] !== 0x18) {
    fail(`${name} is not an LZ4 frame`);
  }
  const flagByte = bytes[4];
  const blockDescriptorByte = bytes[5];
  let offset = 7;
  let blockCount = 0;
  let hasUncompressedBlock = false;
  while (offset + 4 <= bytes.byteLength) {
    const size = bytes.readUInt32LE(offset);
    offset += 4;
    if (size === 0) break;
    const blockSize = size & 0x7fffffff;
    if (offset + blockSize > bytes.byteLength) fail(`${name} has a truncated LZ4 block`);
    blockCount += 1;
    hasUncompressedBlock ||= (size & 0x80000000) !== 0;
    offset += blockSize;
  }
  if (offset !== bytes.byteLength) fail(`${name} has trailing or incomplete LZ4 frame bytes`);
  let decoded;
  try {
    decoded = Buffer.from(decompress(bytes));
  } catch {
    fail(`${name} cannot be decompressed as an LZ4 frame`);
  }
  return {
    decoded,
    flags: {
      flagByte,
      blockDescriptorByte,
      version: flagByte >>> 6,
      blockIndependence: (flagByte & 0x20) !== 0,
      blockChecksum: (flagByte & 0x10) !== 0,
      contentSize: (flagByte & 0x08) !== 0,
      contentChecksum: (flagByte & 0x04) !== 0,
      dictionaryId: (flagByte & 0x01) !== 0,
      maxBlockCode: blockDescriptorByte >>> 4,
      blockCount,
      hasUncompressedBlock,
    },
  };
}

function directCompressedBytes(entry) {
  const messages = array(entry.messages, `${entry.id}.messages`);
  if (messages.length !== 1) fail(`${entry.id} must contain one compressed envelope`);
  const contents = object(messages[0], `${entry.id} message`).contents;
  const envelope = object(contents, `${entry.id} compressed contents`);
  const packed = string(envelope.packedContents, `${entry.id}.packedContents`);
  return lz4Frame(packed, `${entry.id}.packedContents`).decoded.byteLength;
}

function observedChunkCount(entry) {
  return array(entry.messages, `${entry.id}.messages`).filter((message) => {
    const contents = object(message, `${entry.id} message`).contents;
    return contents !== null
      && typeof contents === "object"
      && !Array.isArray(contents)
      && contents.type === "chunkedOp";
  }).length;
}

function sameJson(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

function sharedTreeOperation(message, name, context) {
  if (message.type !== "component") return undefined;
  const component = object(message.contents, `${name}.contents`);
  if (component.address !== context.dataStoreAddress) {
    fail(`${name} does not use its captured SharedTree datastore route`);
  }
  const datastore = object(component.contents, `${name}.contents.contents`);
  if (datastore.type !== "op") fail(`${name} must contain a datastore operation`);
  const channel = object(datastore.content, `${name}.contents.contents.content`);
  if (channel.address !== context.channelAddress) {
    fail(`${name} does not use its captured SharedTree channel route`);
  }
  const operation = object(channel.contents, `${name} SharedTree operation`);
  if (!Array.isArray(operation.changeset) || operation.changeset.length === 0
    || operation.version !== 7
    || typeof operation.originatorId !== "string") {
    fail(`${name} must contain a real version-7 SharedTree edit`);
  }
  return operation;
}

function chunkedPackedEnvelope(entry) {
  const messages = array(entry.messages, `${entry.id}.messages`);
  let serialized = "";
  let total;
  messages.forEach((message, index) => {
    const chunk = object(
      object(message.contents, `${entry.id} message ${index} contents`).contents,
      `${entry.id} message ${index} chunk`,
    );
    if (chunk.chunkId !== index + 1) fail(`${entry.id} chunk IDs must be consecutive`);
    total ??= chunk.totalChunks;
    if (chunk.totalChunks !== total) fail(`${entry.id} chunk total changed`);
    serialized += chunk.contents;
  });
  if (total !== messages.length) fail(`${entry.id} chunk total does not match its stream`);
  return object(JSON.parse(serialized), `${entry.id} reassembled packed envelope`);
}

export function validateCompressionCapture(value) {
  const capture = object(value, "capture");
  if (capture.formatVersion !== 1) fail("formatVersion must be 1");

  const upstream = object(capture.upstream, "upstream");
  if (upstream.version !== reference.version
    || upstream.commit !== reference.commit
    || upstream.package !== "@fluidframework/container-runtime") {
    fail("upstream source identity does not match the pinned package and commit");
  }

  const probe = object(capture.probe, "probe");
  if (probe.path !== compressionSourceIdentity.path
    || probe.digest !== compressionSourceIdentity.digest
    || probe.treePath !== compressionSourceIdentity.treePath
    || probe.treeDigest !== compressionSourceIdentity.treeDigest) {
    fail("probe source identity does not match the owned injection");
  }
  const bootstrap = object(probe.bootstrapSnapshot, "bootstrap snapshot");
  if (bootstrap.kind !== "container-runtime-root-blob-context"
    || bootstrap.blobEncoding !== "utf8-json") {
    fail("bootstrap snapshot context must describe container-runtime root JSON blobs");
  }
  integer(bootstrap.sequenceNumber, "bootstrap snapshot sequence number");
  const rootBlobs = object(bootstrap.rootBlobs, "bootstrap snapshot root blobs");
  if (rootBlobs[".metadata"] === undefined || rootBlobs[".chunks"] === undefined) {
    fail("bootstrap snapshot must contain /.metadata and /.chunks observations");
  }
  const metadataBlob = object(rootBlobs[".metadata"], "bootstrap metadata blob");
  documentSchema(metadataBlob.documentSchema, "bootstrap metadata document schema");
  chunkSummary(rootBlobs[".chunks"], "bootstrap chunks blob");
  const activation = object(probe.schemaActivation, "schema activation");
  if (activation.accepted !== true
    || activation.proposal === undefined
    || activation.postActivationSummary === undefined
    || !Array.isArray(activation.staleCompetingProposals)
    || activation.staleCompetingProposals.length !== 2
    || activation.staleArrayResult !== false) {
    fail("schema activation and ordered CAS observations are incomplete");
  }
  documentSchema(activation.initialSchema, "schema activation initial schema");
  documentSchema(activation.proposal, "schema activation proposal");
  documentSchema(activation.postActivationSummary, "schema activation summary");
  documentSchema(activation.staleSummary, "schema activation stale summary");
  activation.staleCompetingProposals.forEach((schema, index) =>
    documentSchema(schema, `schema activation stale proposal ${index}`));
  const callbacks = array(activation.callbacks, "schema activation callbacks");
  if (callbacks.length !== 1) fail("schema activation must record one callback");
  documentSchema(callbacks[0], "schema activation callback");
  for (const [field, integerReference] of [
    ["futureReference", true],
    ["invalidReference", false],
  ]) {
    const observation = object(activation[field], `schema activation ${field}`);
    string(observation.error, `schema activation ${field} error`);
    documentSchema(
      observation.proposal,
      `schema activation ${field} proposal`,
      integerReference,
    );
  }
  const treeState = object(probe.treeState, "SharedTree tree state");
  if (treeState.kind !== "source-produced-shared-tree-channel-state"
    || treeState.completeness !== "channel-summary-contexts-not-full-container-snapshots") {
    fail("SharedTree tree state must be honestly labeled channel context");
  }
  const treeWorkloads = uniqueById(
    array(treeState.workloads, "SharedTree tree state workloads"),
    "SharedTree tree state workloads",
  );
  for (const [id, workload] of treeWorkloads) {
    const context = object(workload.context, `${id} SharedTree context`);
    if (context.kind !== "shared-tree-channel-summary-context"
      || context.completeness !== "channel-summary-and-id-compressor-not-container-snapshot") {
      fail(`${id} SharedTree context must not claim to be a full container snapshot`);
    }
    string(context.provenance, `${id} SharedTree context provenance`);
    string(context.sessionId, `${id} SharedTree context sessionId`);
    string(context.dataStoreAddress, `${id} SharedTree context datastore`);
    string(context.channelAddress, `${id} SharedTree context channel`);
    object(context.summary, `${id} SharedTree context summary`);
    string(context.compressor, `${id} SharedTree context compressor`);
    const initialization = array(
      context.initializationMessages,
      `${id} SharedTree initialization messages`,
    );
    if (initialization.length === 0) {
      fail(`${id} SharedTree context must include source-produced initialization`);
    }
    const operations = array(workload.operations, `${id} SharedTree workload operations`);
    if (operations.length === 0) fail(`${id} SharedTree workload has no operations`);
    operations.forEach((operation, index) => {
      const evidence = object(operation, `${id} SharedTree operation ${index}`);
      if (!/^[0-9a-f]{64}$/.test(evidence.sha256)) {
        fail(`${id} SharedTree operation ${index} has no source digest`);
      }
      boolean(
        evidence.hasAllocationPrelude,
        `${id} SharedTree operation ${index} allocation prelude`,
      );
    });
  }

  const defaults = object(capture.defaults, "defaults");
  if (defaults.minimumBatchSizeInBytes !== 614400) {
    fail("default compression threshold must be 614400 bytes");
  }
  if (defaults.chunkSizeInBytes !== 204800 || defaults.compressionAlgorithm !== "lz4") {
    fail("default chunk size and compression algorithm do not match Fluid 3.1.0");
  }

  const limits = object(capture.limits, "limits");
  for (const field of ["maxPackedBytes", "maxDecodedBytes", "maxBufferedBytes"]) {
    if (limits[field] !== 16 * 1024 * 1024) fail(`${field} must be 16 MiB`);
  }
  if (limits.maxStreams !== 64 || limits.maxChunks !== 128) {
    fail("stream and chunk limits do not match the extension profile");
  }

  const frames = uniqueById(array(capture.frames, "frames"), "frames");
  for (const id of requiredFrames) {
    if (!frames.has(id)) fail(`required frame ${id} is missing`);
  }
  for (const [id, frame] of frames) {
    const inspected = lz4Frame(frame.compressedBase64, `${id}.compressedBase64`);
    const decodedLength = decodedBase64Length(frame.decodedBase64, `${id}.decodedBase64`);
    const decoded = Buffer.from(frame.decodedBase64, "base64");
    if (!inspected.decoded.equals(decoded)) {
      fail(`${id} LZ4 frame does not decode to its recorded bytes`);
    }
    const measurements = object(frame.measurements, `${id}.measurements`);
    if (measurements.compressedBytes !== Buffer.from(frame.compressedBase64, "base64").byteLength) {
      fail(`${id} compressed byte measurement does not match its vector`);
    }
    if (measurements.decodedBytes !== decodedLength) {
      fail(`${id} decoded byte measurement does not match its vector`);
    }
    const flags = object(frame.flags, `${id}.flags`);
    for (const [field, expected] of Object.entries(inspected.flags)) {
      if (flags[field] !== expected) fail(`${id}.flags.${field} does not match its frame`);
    }
  }
  if (object(frames.get("benchmark-1mib").measurements, "benchmark-1mib measurements")
    .decodedBytes !== 1024 * 1024) {
    fail("benchmark-1mib must decode to exactly 1 MiB");
  }
  if (object(frames.get("benchmark-4mib").measurements, "benchmark-4mib measurements")
    .decodedBytes !== 4 * 1024 * 1024) {
    fail("benchmark-4mib must decode to exactly 4 MiB");
  }
  if (object(frames.get("multi-block-match").flags, "multi-block-match flags")
    .blockCount < 2) {
    fail("multi-block-match must contain multiple emitted LZ4 blocks");
  }
  if (object(frames.get("literal-block").flags, "literal-block flags")
    .hasUncompressedBlock !== true) {
    fail("literal-block must contain an emitted uncompressed LZ4 block");
  }

  const cases = uniqueById(array(capture.cases, "cases"), "cases");
  for (const id of requiredCases) {
    if (!cases.has(id)) fail(`required case ${id} is missing`);
  }
  for (const [id, entry] of cases) {
    const messages = array(entry.messages, `${id}.messages`);
    messages.forEach((message) => object(message, `${id} message`));
    const expected = array(entry.expected, `${id}.expected`);
    expected.forEach((result) => object(result, `${id} expected result`));
    const measurements = object(entry.measurements, `${id}.measurements`);
    for (const field of ["sourceBytes", "packedBytes", "decodedBytes", "chunkCount"]) {
      integer(measurements[field], `${id}.${field}`);
    }
    const actualChunks = observedChunkCount(entry);
    if (measurements.chunkCount !== actualChunks) {
      fail(`${id} measured chunk count ${measurements.chunkCount} does not match ${actualChunks}`);
    }
  }
  for (const id of runtimeMessageCases) {
    const entry = cases.get(id);
    entry.messages.forEach((message, index) => {
      const sequenced = sequencedMessage(message, `${id} message ${index}`);
      const contents = sequenced.contents;
      if (contents.type === "chunkedOp") {
        const chunk = object(contents.contents, `${id} message ${index} chunk`);
        const chunkId = integer(chunk.chunkId, `${id} message ${index} chunkId`);
        const totalChunks = integer(
          chunk.totalChunks,
          `${id} message ${index} totalChunks`,
        );
        if (chunkId < 1 || totalChunks < chunkId || totalChunks > limits.maxChunks) {
          fail(`${id} message ${index} has invalid chunk limits`);
        }
        if (typeof chunk.contents !== "string") {
          fail(`${id} message ${index} chunk contents must be a string`);
        }
      }
    });
    entry.expected.forEach((result, index) =>
      normalizedRuntimeResult(result, `${id} expected result ${index}`));
  }
  for (const id of nonemptyCases) {
    const entry = cases.get(id);
    if (entry.messages.length === 0 || entry.expected.length === 0) {
      fail(`${id} must contain messages and expected output`);
    }
  }
  for (const id of negativeCases) {
    string(cases.get(id).expectedNativeError, `${id}.expectedNativeError`);
  }
  for (const id of upstreamObservedCases) {
    const observation = object(cases.get(id).upstreamObservation, `${id}.upstreamObservation`);
    if (observation.status === "accepted") {
      array(observation.result, `${id}.upstreamObservation.result`);
    } else if (observation.status === "rejected") {
      string(observation.error, `${id}.upstreamObservation.error`);
    } else {
      fail(`${id}.upstreamObservation must record accepted or rejected status`);
    }
  }
  for (const id of directCompressedCases) {
    const entry = cases.get(id);
    if (entry.measurements.decodedBytes !== directCompressedBytes(entry)) {
      fail(`${id} decoded byte measurement does not match its compressed frame`);
    }
  }
  if (cases.get("default-chunked-group").measurements.chunkCount < 2) {
    fail("default-chunked-group must contain multiple measured chunks");
  }
  if (cases.get("default-compressed-singleton").measurements.sourceBytes <= 614400
    || cases.get("default-compressed-group").measurements.sourceBytes <= 614400
    || cases.get("default-chunked-group").measurements.sourceBytes <= 614400) {
    fail("default compression cases must cross the captured threshold");
  }
  const defaultChunks = cases.get("default-chunked-group");
  const chunkEnvelope = chunkedPackedEnvelope(defaultChunks);
  const chunkFrame = string(
    chunkEnvelope.packedContents,
    "default-chunked-group reassembled packed contents",
  );
  if (Buffer.from(chunkFrame, "base64").byteLength <= defaults.chunkSizeInBytes) {
    fail("default-chunked-group compressed frame must cross the actual chunk threshold");
  }
  for (const id of routedTreeCases) {
    const entry = cases.get(id);
    const caseContext = object(entry.treeContext, `${id} tree context`);
    const workloadId = string(caseContext.workloadId, `${id} tree context workloadId`);
    const workload = treeWorkloads.get(workloadId);
    if (workload === undefined) fail(`${id} references a missing SharedTree workload`);
    const context = object(workload.context, `${id} SharedTree context`);
    if (caseContext.kind !== context.kind
      || caseContext.completeness !== context.completeness
      || caseContext.statePath !== `probe.treeState.workloads.${workloadId}.context`) {
      fail(`${id} tree context does not match its source-produced SharedTree state`);
    }
    const sourceOperationIndexes = array(
      caseContext.sourceOperationIndexes,
      `${id} source operation indexes`,
    );
    sourceOperationIndexes.forEach((index, position) => {
      integer(index, `${id} source operation index ${position}`);
    });
    if (id === "default-compressed-singleton") {
      string(caseContext.requiredPrelude, `${id} required prelude`);
      const firstOperation = object(
        array(workload.operations, `${id} source operations`)[0],
        `${id} source operation 0`,
      );
      if (firstOperation.hasAllocationPrelude !== true) {
        fail(`${id} must identify its source-produced ID allocation prelude`);
      }
    }
    const normalized = entry.expected.flatMap((result) =>
      array(result.messages, `${id} expected messages`));
    const operations = normalized
      .map((message, index) =>
        sharedTreeOperation(message, `${id} expected message ${index}`, context))
      .filter((operation) => operation !== undefined);
    if (operations.length === 0) fail(`${id} has no routed SharedTree edits`);
    const sourceOperations = array(workload.operations, `${id} source workload`)
      .filter((_, index) => sourceOperationIndexes.includes(index));
    if (operations.length !== sourceOperationIndexes.length
      || operations.length !== sourceOperations.length
      || !operations.every((operation, index) => {
        const evidence = object(sourceOperations[index], `${id} source operation ${index}`);
        return digest(JSON.stringify(canonical(operation))) === evidence.sha256;
      })) {
      fail(`${id} normalized SharedTree edits differ from the source-produced workload`);
    }
  }
  const partial = cases.get("partial-summary-prefix-tail");
  const initialSummary = chunkSummary(
    partial.initialSummary,
    "partial-summary-prefix-tail initial summary",
    limits.maxStreams,
    limits.maxChunks,
  );
  const partialSummary = chunkSummary(
    partial.partialSummary,
    "partial-summary-prefix-tail partial summary",
    limits.maxStreams,
    limits.maxChunks,
  );
  const delivery = object(partial.delivery, "partial-summary-prefix-tail delivery");
  const prefixLength = integer(
    delivery.prefixLength,
    "partial-summary-prefix-tail prefixLength",
  );
  const tailLength = integer(
    delivery.tailLength,
    "partial-summary-prefix-tail tailLength",
  );
  const partialMessages = array(partial.messages, "partial-summary-prefix-tail messages");
  if (prefixLength < 1 || tailLength < 1
    || partialMessages.length !== prefixLength + tailLength) {
    fail("partial-summary-prefix-tail delivery lengths do not match its messages");
  }
  const prefixPieces = partialMessages.slice(0, prefixLength).map((message, index) =>
    object(
      object(message.contents, `partial-summary-prefix-tail prefix ${index}`).contents,
      `partial-summary-prefix-tail prefix chunk ${index}`,
    ).contents);
  const sender = partialMessages[0].clientId;
  const expectedSummary = [[sender, prefixPieces]];
  if (!sameJson(initialSummary, expectedSummary)
    || !sameJson(partialSummary, expectedSummary)
    || !sameJson(rootBlobs[".chunks"], expectedSummary)) {
    fail("partial-summary-prefix-tail summaries do not match the captured prefix");
  }
  const nextChunk = object(
    object(
      partialMessages[prefixLength].contents,
      "partial-summary-prefix-tail next message",
    ).contents,
    "partial-summary-prefix-tail next chunk",
  );
  if (nextChunk.chunkId !== prefixLength + 1
    || nextChunk.totalChunks !== partialMessages.length) {
    fail("partial-summary-prefix-tail tail does not start with the next chunk");
  }
  documentSchema(
    cases.get("native-format-without-compression-lz4").initialSummary,
    "native-format-without-compression-lz4 initial summary",
  );
  const schemaActivationCase = cases.get("schema-activation");
  const schemaActivationMessage = object(
    schemaActivationCase.messages[0],
    "schema-activation message",
  );
  if (schemaActivationMessage.type !== "schema") {
    fail("schema-activation message type must be schema");
  }
  integer(schemaActivationMessage.sequenceNumber, "schema-activation message sequenceNumber");
  array(schemaActivationMessage.contents, "schema-activation message contents")
    .forEach((schema, index) =>
      documentSchema(schema, `schema-activation proposal ${index}`));
  documentSchema(schemaActivationCase.expected[0], "schema-activation expected result");
  const staleCase = cases.get("stale-competing-proposals");
  staleCase.messages.forEach((schema, index) =>
    documentSchema(schema, `stale-competing-proposals message ${index}`));
  const staleResult = object(
    staleCase.expected[0],
    "stale-competing-proposals expected result",
  );
  boolean(staleResult.accepted, "stale-competing-proposals accepted result");
  documentSchema(staleResult.summary, "stale-competing-proposals summary");
  for (const id of ["future-schema-reference", "invalid-schema-reference"]) {
    const message = object(cases.get(id).messages[0], `${id} message`);
    string(message.error, `${id} error`);
    documentSchema(message.proposal, `${id} proposal`, id !== "invalid-schema-reference");
  }
  const allocationMessages = cases.get("id-allocation-before-tree-use").expected
    .flatMap((result) => array(result.messages, "allocation expected messages"));
  if (allocationMessages.length !== 2
    || allocationMessages[0].type !== "idAllocation"
    || allocationMessages[1].type !== "component") {
    fail("id-allocation-before-tree-use must normalize allocation before tree operation");
  }
  const range = object(allocationMessages[0].contents, "allocation range");
  string(range.sessionId, "allocation range sessionId");
  const ids = object(range.ids, "allocation range ids");
  if (!Number.isInteger(ids.firstGenCount) || ids.firstGenCount < 1
    || !Number.isInteger(ids.count) || ids.count < 1
    || !Number.isInteger(ids.requestedClusterSize) || ids.requestedClusterSize < 1
    || !Array.isArray(ids.localIdRanges)) {
    fail("allocation range must be a valid IdCreationRange");
  }
  const componentContents = object(
    object(allocationMessages[1].contents, "tree component contents").contents,
    "tree channel envelope",
  );
  const treeOperation = object(
    object(componentContents.content, "tree channel content").contents,
    "tree operation",
  );
  string(treeOperation.originatorId, "tree operation originatorId");
  if (!Array.isArray(treeOperation.changeset) || treeOperation.changeset.length === 0) {
    fail("tree operation must contain real SharedTree changes");
  }
  const schemaCase = cases.get("schema-activation");
  const operationCase = cases.get("post-activation-compressed-operation");
  const association = object(operationCase.activation, "post-activation association");
  const schemaMessage = object(schemaCase.messages[0], "schema activation message");
  const schemaSummary = object(schemaCase.expected[0], "schema activation result");
  const operationMessage = object(operationCase.messages[0], "post-activation message");
  integer(association.sequenceNumber, "post-activation association sequenceNumber");
  integer(association.schemaRefSeq, "post-activation association schemaRefSeq");
  integer(operationMessage.sequenceNumber, "post-activation message sequenceNumber");
  integer(
    operationMessage.referenceSequenceNumber,
    "post-activation message referenceSequenceNumber",
  );
  if (association.caseId !== schemaCase.id
    || association.sequenceNumber !== schemaMessage.sequenceNumber
    || association.schemaRefSeq !== schemaSummary.refSeq
    || operationMessage.sequenceNumber <= association.sequenceNumber
    || operationMessage.referenceSequenceNumber < association.schemaRefSeq) {
    fail("post-activation operation must continue the accepted schema activation");
  }
  return value;
}

function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value).sort().map((key) => [key, canonical(value[key])]),
    );
  }
  return value;
}

function serialized(value) {
  return `${JSON.stringify(canonical(value), null, 2)}\n`;
}

function digest(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

async function generatedFiles() {
  const capture = JSON.parse(await readFile(sourcePath, "utf8"));
  validateCompressionCapture(capture);
  const corpus = serialized(capture);
  const legacyBytes = await readFile(legacyProfilePath);
  if (digest(legacyBytes) !== legacyProfileDigest) {
    throw new Error("Legacy shared-tree profile digest changed");
  }
  const profile = serialized({
    formatVersion: 1,
    name: "Fluid 3.1.0 SharedTree inbound compression extension",
    corpus: {
      path: "compression.json",
      sha256: digest(corpus),
    },
    upstream: capture.upstream,
    probe: {
      path: capture.probe.path,
      sha256: capture.probe.digest,
      treePath: capture.probe.treePath,
      treeSha256: capture.probe.treeDigest,
    },
    legacyProfile: {
      path: "profile.json",
      sha256: legacyProfileDigest,
    },
    defaults: capture.defaults,
    limits: capture.limits,
    supportedForms: [
      "plain singleton runtime message",
      "plain grouped runtime batch",
      "lz4 compressed singleton runtime message",
      "lz4 compressed grouped runtime batch",
      "per-sender chunked lz4 runtime message",
      "empty final chunk",
      "empty grouped batch",
      "partial /.chunks summary continuation",
      "runtime schema compression activation",
    ],
    exclusions: [
      "native outbound compression or chunking",
      "unmarked packed contents",
      "compression algorithms other than lz4",
      "legacy multi-message compressed arrays",
      "missing partial chunk prefixes",
      "nested compression",
      "incremental FieldBatch",
      "incremental summary writing",
      "GC sweep",
      "arbitrary factories",
      "public tree API changes",
    ],
  });
  return { corpus, profile };
}

export async function generateCompressionFixtures({ check = false } = {}) {
  const files = await generatedFiles();
  for (const [path, expected] of [
    [fixturePath, files.corpus],
    [profilePath, files.profile],
  ]) {
    if (check) {
      let actual;
      try {
        actual = await readFile(path, "utf8");
      } catch {
        throw new Error(`Generated compression fixture is missing: ${path}`);
      }
      if (actual !== expected) {
        throw new Error(`Generated compression fixture is stale: ${path}`);
      }
    } else {
      await writeFile(path, expected);
    }
  }
}

async function main() {
  const [command] = process.argv.slice(2);
  if (command === "generate") {
    await generateCompressionFixtures();
  } else if (command === "check") {
    await generateCompressionFixtures({ check: true });
  } else {
    throw new Error("Usage: node compression.mjs generate|check");
  }
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
