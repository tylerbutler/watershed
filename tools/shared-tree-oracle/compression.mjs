import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

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

function observedChunkCount(entry) {
  return array(entry.messages, `${entry.id}.messages`).filter((message) => {
    const contents = object(message, `${entry.id} message`).contents;
    return contents !== null
      && typeof contents === "object"
      && !Array.isArray(contents)
      && contents.type === "chunkedOp";
  }).length;
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
    || probe.digest !== compressionSourceIdentity.digest) {
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
  const activation = object(probe.schemaActivation, "schema activation");
  if (activation.accepted !== true
    || activation.proposal === undefined
    || activation.postActivationSummary === undefined
    || !Array.isArray(activation.staleCompetingProposals)
    || activation.staleCompetingProposals.length !== 2
    || activation.staleArrayResult !== false) {
    fail("schema activation and ordered CAS observations are incomplete");
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
    decodedBase64Length(frame.compressedBase64, `${id}.compressedBase64`);
    const decodedLength = decodedBase64Length(frame.decodedBase64, `${id}.decodedBase64`);
    const measurements = object(frame.measurements, `${id}.measurements`);
    if (measurements.decodedBytes !== decodedLength) {
      fail(`${id} decoded byte measurement does not match its vector`);
    }
    const flags = object(frame.flags, `${id}.flags`);
    integer(flags.blockCount, `${id}.flags.blockCount`);
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
    array(entry.messages, `${id}.messages`);
    array(entry.expected, `${id}.expected`);
    const measurements = object(entry.measurements, `${id}.measurements`);
    for (const field of ["sourceBytes", "packedBytes", "decodedBytes", "chunkCount"]) {
      integer(measurements[field], `${id}.${field}`);
    }
    const actualChunks = observedChunkCount(entry);
    if (measurements.chunkCount !== actualChunks) {
      fail(`${id} measured chunk count ${measurements.chunkCount} does not match ${actualChunks}`);
    }
  }
  for (const id of negativeCases) {
    string(cases.get(id).expectedNativeError, `${id}.expectedNativeError`);
  }
  if (cases.get("default-chunked-group").measurements.chunkCount < 2) {
    fail("default-chunked-group must contain multiple measured chunks");
  }
  if (cases.get("default-compressed-singleton").measurements.sourceBytes <= 614400
    || cases.get("default-compressed-group").measurements.sourceBytes <= 614400
    || cases.get("default-chunked-group").measurements.sourceBytes <= 614400) {
    fail("default compression cases must cross the captured threshold");
  }
  if (!Array.isArray(cases.get("partial-summary-prefix-tail").partialSummary)
    || cases.get("partial-summary-prefix-tail").partialSummary.length === 0) {
    fail("partial-summary-prefix-tail must carry a real partial summary");
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
