import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { mkdir, mkdtemp, readFile, rm } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { isDeepStrictEqual } from "node:util";

import { runCodecConsumer } from "./source.mjs";

const directory = dirname(fileURLToPath(import.meta.url));
const repository = resolve(directory, "../..");
const defaultOutputRoot = join(directory, ".output");
const reference = {
  package: "@fluidframework/tree",
  version: "3.1.0",
  commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
};
const expectedArrayObservations = JSON.parse(readFileSync(
  join(directory, "expected-array-observations.json"),
  "utf8",
));
const requiredItemIds = [
  "fixed",
  "empty",
  "optional",
  "initial-forest-compressed",
  "initial-build-compressed",
  "simple-uncompressed",
  "message-point-replacement",
  "message-nested-scalar",
  "message-optional-set",
  "message-optional-clear",
  "message-detached-repair",
  "summary-initial",
  "summary-settled-detached",
  "summary-native-authored",
  "summary-restored-detached",
  "message-map-set",
  "summary-map-restored",
  "message-array-sequence",
  "message-array-native-authored",
  "message-array-advanced-rename",
  "message-array-advanced-aad",
  "message-array-advanced-move-in-remove",
  "message-array-advanced-insert-move-out",
  "message-array-advanced-nested",
  "summary-array-retained-history",
  "summary-array-full-summary",
  "summary-array-peer-history",
  "summary-schema-initial",
  "summary-schema-peer-before-upgrade",
  "summary-schema-upgrade-tail",
  "identifier-explicit-custom",
  "identifier-generated-uuid",
  "identifier-message-compressed",
  "identifier-summary-finalized",
  "identifier-summary-unfinalized",
  "identifier-retained-repair",
  "identifier-post-load-edit",
  "identifier-native-initial-summary",
];
const point = (x, y) => ({
  type: "org.watershed.shared-tree.m1.Point",
  fields: {
    x: [{ type: "com.fluidframework.leaf.number", value: x }],
    y: [{ type: "com.fluidframework.leaf.number", value: y }],
  },
});
const rootField = {
  type: "org.watershed.shared-tree.m1.Root",
  fields: {
    title: [{ type: "com.fluidframework.leaf.string", value: "" }],
    enabled: [{ type: "com.fluidframework.leaf.boolean", value: false }],
    rating: [{ type: "com.fluidframework.leaf.number", value: 0 }],
    marker: [{ type: "com.fluidframework.leaf.null", value: null }],
    point: [point(0, 0)],
  },
};
const visibleRoot = ({ title = "", pointValue = { x: 0, y: 0 }, note } = {}) => ({
  title,
  enabled: false,
  rating: 0,
  marker: null,
  ...(note === undefined ? {} : { note }),
  point: pointValue,
});
const visibleMap = {
  set: "value",
  "replace-on-reconnect": { inner: "pending" },
  "remote-crossing": "sequenced",
  nested: {
    before: "value",
    after: "continued",
  },
};
const firstRevision = "8f95be09-8376-4ff7-8755-ccd7e8124b07";
const firstSession = "8f95be09-8376-4ff7-8755-ccd7e8124b06";
const secondRevision = "a0693eac-892a-4396-86f7-ad20dc1cade2";
const nativeRevision = "30000000-0000-4000-8000-000000000003";
const pointRemoval = {
  major: firstRevision,
  minor: 1,
  tree: point(7, 0),
};
const numberRemoval = {
  major: secondRevision,
  minor: 1,
  tree: {
    type: "com.fluidframework.leaf.number",
    value: 0,
  },
};
const settledHistory = {
  trunk: [
    {
      revision: firstRevision,
      session: firstSession,
      sequenceNumber: 4,
      indexInBatch: null,
    },
    {
      revision: secondRevision,
      session: secondRevision,
      sequenceNumber: 6,
      indexInBatch: null,
    },
  ],
  peers: [{
    session: secondRevision,
    base: "root",
    revisions: [secondRevision],
  }],
};
const expectedObservations = [
  { id: "fixed", kind: "schema", nodes: 6, rootKind: "Value" },
  { id: "empty", kind: "schema", nodes: 0, rootKind: "Forbidden" },
  { id: "optional", kind: "schema", nodes: 6, rootKind: "Optional" },
  {
    id: "initial-forest-compressed",
    kind: "fieldBatch",
    fields: [[rootField]],
  },
  {
    id: "initial-build-compressed",
    kind: "fieldBatch",
    fields: [[rootField]],
  },
  {
    id: "simple-uncompressed",
    kind: "fieldBatch",
    fields: [[{
      type: "com.fluidframework.leaf.string",
      value: "native",
    }]],
  },
  {
    id: "message-point-replacement",
    kind: "message",
    decoded: true,
    beforeApply: visibleRoot(),
    afterApply: visibleRoot({ pointValue: { x: 10, y: 20 } }),
    continued: "upstream-continuation",
  },
  {
    id: "message-nested-scalar",
    kind: "message",
    decoded: true,
    beforeApply: visibleRoot(),
    afterApply: visibleRoot({ pointValue: { x: 7, y: 0 } }),
    continued: "upstream-continuation",
  },
  {
    id: "message-optional-set",
    kind: "message",
    decoded: true,
    beforeApply: visibleRoot(),
    afterApply: visibleRoot({ note: "native-note" }),
    continued: "upstream-continuation",
  },
  {
    id: "message-optional-clear",
    kind: "message",
    decoded: true,
    beforeApply: visibleRoot({ note: "seed" }),
    afterApply: visibleRoot(),
    continued: "upstream-continuation",
  },
  {
    id: "message-detached-repair",
    kind: "message",
    decoded: true,
    beforeApply: visibleRoot({ note: "seed" }),
    afterApply: visibleRoot(),
    continued: "upstream-continuation",
  },
  {
    id: "summary-initial",
    kind: "summary",
    visible: visibleRoot(),
    removed: [],
    history: {
      trunk: [{
        revision: "8f95be09-8376-4ff7-8755-ccd7e8124b06",
        session: "8f95be09-8376-4ff7-8755-ccd7e8124b06",
        sequenceNumber: 2,
        indexInBatch: null,
      }],
      peers: [{
        session: "50000000-0000-4000-8000-000000000005",
        base: "8f95be09-8376-4ff7-8755-ccd7e8124b06",
        revisions: [],
      }],
    },
    continued: "upstream-continuation",
  },
  {
    id: "summary-schema-initial",
    kind: "summary",
    visible: visibleRoot(),
    removed: [],
    history: {
      trunk: [{
        revision: "8f95be09-8376-4ff7-8755-ccd7e8124b06",
        session: "8f95be09-8376-4ff7-8755-ccd7e8124b06",
        sequenceNumber: 2,
        indexInBatch: null,
      }],
      peers: [{
        session: "50000000-0000-4000-8000-000000000005",
        base: "8f95be09-8376-4ff7-8755-ccd7e8124b06",
        revisions: [],
      }],
    },
    continued: "upstream-continuation",
  },
  {
    id: "summary-settled-detached",
    kind: "summary",
    visible: visibleRoot({ pointValue: { x: 10, y: 20 } }),
    removed: [pointRemoval, numberRemoval],
    history: settledHistory,
    continued: "upstream-continuation",
  },
  {
    id: "summary-native-authored",
    kind: "summary",
    visible: visibleRoot({
      title: "watershed-native-summary",
      pointValue: { x: 10, y: 20 },
    }),
    removed: [
      {
        major: nativeRevision,
        minor: 1,
        tree: {
          type: "com.fluidframework.leaf.string",
          value: "",
        },
      },
      pointRemoval,
      numberRemoval,
    ],
    history: {
      trunk: [
        ...settledHistory.trunk,
        {
          revision: nativeRevision,
          session: nativeRevision,
          sequenceNumber: 7,
          indexInBatch: null,
        },
      ],
      peers: settledHistory.peers,
    },
    continued: "upstream-continuation",
  },
  {
    id: "summary-restored-detached",
    kind: "summary",
    visible: visibleRoot({ pointValue: { x: 10, y: 20 } }),
    removed: [pointRemoval, numberRemoval],
    history: settledHistory,
    continued: "upstream-continuation",
  },
  {
    id: "message-map-set",
    kind: "message",
    decoded: true,
    beforeApply: visibleMap,
    afterApply: {
      ...visibleMap,
      native: "value",
    },
    continued: true,
  },
  {
    id: "summary-map-restored",
    kind: "summary",
    visible: visibleMap,
    removed: [
      {
        major: "8f95be09-8376-4ff7-8755-ccd7e8124b0c",
        minor: 19,
        tree: {
          type: "com.fluidframework.leaf.string",
          value: "before",
        },
      },
      {
        major: "8f95be09-8376-4ff7-8755-ccd7e8124b0d",
        minor: 23,
        tree: {
          type: "com.fluidframework.leaf.string",
          value: "before",
        },
      },
    ],
    history: {
      trunk: [
        {
          revision: "8f95be09-8376-4ff7-8755-ccd7e8124b0c",
          session: firstSession,
          sequenceNumber: 16,
          indexInBatch: null,
        },
        {
          revision: "8f95be09-8376-4ff7-8755-ccd7e8124b0d",
          session: firstSession,
          sequenceNumber: 17,
          indexInBatch: null,
        },
        {
          revision: "a0693eac-892a-4396-86f7-ad20dc1cade3",
          session: secondRevision,
          sequenceNumber: 19,
          indexInBatch: null,
        },
        {
          revision: "a0693eac-892a-4396-86f7-ad20dc1cade4",
          session: secondRevision,
          sequenceNumber: 21,
          indexInBatch: null,
        },
      ],
      peers: [{
        session: secondRevision,
        base: "a0693eac-892a-4396-86f7-ad20dc1cade4",
        revisions: [],
      }],
    },
    continued: true,
  },
  ...expectedArrayObservations.observations,
];

const object = (value) => value !== null && typeof value === "object" && !Array.isArray(value);

function requireValue(condition, detail) {
  if (!condition) throw new Error(`Invalid native codec artifact: ${detail}`);
}

function containsValue(value, expected) {
  if (value === expected) return true;
  if (Array.isArray(value)) return value.some((item) => containsValue(item, expected));
  if (object(value)) return Object.values(value).some((item) => containsValue(item, expected));
  return false;
}

function identifierPayloads(value, field, label) {
  const payloads = [];
  function visit(item) {
    if (Array.isArray(item)) {
      const hasLabel = item.some((value, index) =>
        value === "label" && containsValue(item[index + 1], label));
      if (hasLabel) {
        item.forEach((value, index) => {
          if (value === field && Array.isArray(item[index + 1])) {
            payloads.push(item[index + 1]);
          }
        });
      }
      item.forEach(visit);
    } else if (object(item)) {
      Object.values(item).forEach(visit);
    }
  }
  visit(value);
  return payloads;
}

function identifierWireInput(item) {
  if (item.kind === "message") return item.encoded;
  const content = item.encoded?.tree?.indexes?.tree?.Forest?.tree?.contents?.content;
  requireValue(typeof content === "string", `${item.id} Identifier forest content`);
  try {
    return JSON.parse(content);
  } catch (error) {
    throw new Error(
      `Invalid native codec artifact: ${item.id} Identifier forest content`,
      { cause: error },
    );
  }
}

function validateIdentifierEncoding(item) {
  const encoding = item.identifierEncoding;
  requireValue(object(encoding)
    && typeof encoding.field === "string"
    && typeof encoding.label === "string"
    && (encoding.representation === "number" || encoding.representation === "string")
    && typeof encoding.stableId === "string",
  `${item.id} Identifier encoding`);
  const payloads = identifierPayloads(
    identifierWireInput(item),
    encoding.field,
    encoding.label,
  );
  requireValue(payloads.length === 1, `${item.id} Identifier payload`);
  const payload = payloads[0];
  const valid = encoding.representation === "number"
    ? typeof payload[1] === "number"
    : payload[1] === encoding.stableId;
  requireValue(valid, `${item.id} Identifier payload representation`);
  requireValue(
    containsValue(item.expected, encoding.stableId)
      && containsValue(item.expected, encoding.label),
    `${item.id} Identifier expected resolution`,
  );
}

function comparableObservation(observation) {
  if (!observation.id?.startsWith("summary-array-")) return observation;
  const {
    rawInput: _rawInput,
    emitted: _emitted,
    ...semantic
  } = observation;
  return semantic;
}

export function validateNativeArtifact(artifact) {
  requireValue(object(artifact) && artifact.formatVersion === 1, "formatVersion");
  requireValue(JSON.stringify(artifact.reference) === JSON.stringify(reference), "reference");
  requireValue(artifact.target === "erlang" || artifact.target === "javascript", "target");
  requireValue(Array.isArray(artifact.items) && artifact.items.length > 0, "items");
  const ids = new Set();
  for (const item of artifact.items) {
    requireValue(object(item) && typeof item.id === "string" && item.id.length > 0, "item id");
    requireValue(!ids.has(item.id), `duplicate item ${item.id}`);
    ids.add(item.id);
    requireValue(["schema", "fieldBatch", "message", "summary"].includes(item.kind),
      `${item.id} kind`);
    requireValue(item.schemaProfile === undefined
      || item.schemaProfile === "map"
      || item.schemaProfile === "array"
      || item.schemaProfile === "identifier",
      `${item.id} schemaProfile`);
    requireValue(Object.hasOwn(item, "encoded"), `${item.id} encoded`);
    if (item.kind === "message" || item.kind === "summary") {
      requireValue(typeof item.compressor === "string" && item.compressor.length > 0,
        `${item.id} compressor`);
      requireValue(item.compressorMode === "ongoing" || item.compressorMode === "summary",
        `${item.id} compressorMode`);
      requireValue(typeof item.session === "string" && item.session.length > 0,
        `${item.id} session`);
      if (item.schemaProfile === "identifier") {
        requireValue(object(item.expected), `${item.id} expected Identifier semantics`);
      }
    }
    if (item.kind === "message") {
      requireValue(object(item.initialSummary), `${item.id} initialSummary`);
      requireValue(Array.isArray(item.allocationRanges), `${item.id} allocationRanges`);
      if (item.schemaProfile === "array") {
        requireValue(Array.isArray(item.encoded) && item.encoded.length > 0,
          `${item.id} encoded messages`);
        requireValue(Array.isArray(item.sequencing)
          && item.sequencing.length >= item.encoded.length,
        `${item.id} sequencing`);
        requireValue(Array.isArray(item.expectedGraphs)
          && item.expectedGraphs.length === item.encoded.length,
        `${item.id} expected graphs`);
        if (item.id.startsWith("message-array-advanced-")) {
          requireValue(Array.isArray(item.nativeGraphs)
            && item.nativeGraphs.length === item.encoded.length,
          `${item.id} native graphs`);
        }
      } else {
        for (const field of [
          "sequenceNumber", "referenceSequenceNumber", "minimumSequenceNumber",
        ]) {
          requireValue(Number.isSafeInteger(item[field]) && item[field] >= 0,
            `${item.id} ${field}`);
        }
        requireValue(item.indexInBatch === null
          || (Number.isSafeInteger(item.indexInBatch) && item.indexInBatch >= 0),
        `${item.id} indexInBatch`);
      }
    }
    if (item.id === "identifier-message-compressed"
      || item.id === "identifier-summary-finalized"
      || item.id === "identifier-summary-unfinalized") {
      validateIdentifierEncoding(item);
    }
  }
  return artifact;
}

export function validateConsumerOutput(
  output,
  artifact,
  expectedIds,
  expectedSummaries = [],
) {
  requireValue(object(output) && output.formatVersion === 1, "consumer formatVersion");
  requireValue(JSON.stringify(output.reference) === JSON.stringify(reference),
    "consumer reference");
  requireValue(output.target === artifact.target, "consumer target");
  requireValue(Array.isArray(output.observations) && output.observations.length > 0,
    "consumer observations");
  requireValue(output.observations.length === artifact.items.length,
    "consumer observation count");
  const items = new Map(artifact.items.map((item) => [item.id, item]));
  const summaries = new Map(expectedSummaries.map((item) => [item.id, item]));
  const ids = new Set();
  for (const observation of output.observations) {
    requireValue(object(observation) && typeof observation.id === "string",
      "consumer observation id");
    requireValue(!ids.has(observation.id), `duplicate consumer observation ${observation.id}`);
    ids.add(observation.id);
    const item = items.get(observation.id);
    requireValue(item !== undefined, `unexpected consumer observation ${observation.id}`);
    requireValue(observation.kind === item.kind,
      `${observation.id} consumer kind`);
    if (item.schemaProfile === "identifier") {
      requireValue(
        isDeepStrictEqual(observation, item.expected),
        `${observation.id} expected Identifier semantics`,
      );
    }
    if (item.kind === "summary") {
      requireValue(Array.isArray(observation.removed), `${observation.id} removed content`);
      requireValue(object(observation.history)
        && Array.isArray(observation.history.trunk)
        && Array.isArray(observation.history.peers),
      `${observation.id} history`);
      const expectedSummary = summaries.get(observation.id);
      if (expectedSummary !== undefined) {
        requireValue(
          isDeepStrictEqual(comparableObservation(observation), expectedSummary),
          `${observation.id} expected summary semantics`);
      }
    }
    if (observation.id === "message-map-set") {
      requireValue(observation.decoded === true, "message-map-set decoded");
      requireValue(object(observation.beforeApply)
        && !Object.hasOwn(observation.beforeApply, "native"),
      "message-map-set before state");
      requireValue(object(observation.afterApply)
        && observation.afterApply.native === "value",
      "message-map-set applied state");
      requireValue(observation.continued === true, "message-map-set continuation");
    }
    if (observation.id === "summary-map-restored") {
      requireValue(object(observation.visible)
        && object(observation.visible.nested)
        && observation.visible.nested.after === "continued",
      "summary-map-restored visible state");
      requireValue(observation.removed.length === 2,
        "summary-map-restored removed content");
      requireValue(observation.history.trunk.length === 4,
        "summary-map-restored trunk history");
      requireValue(observation.continued === true,
        "summary-map-restored continuation");
    }
    if (observation.id.startsWith("message-array-")) {
      requireValue(observation.decoded === true, `${observation.id} decoded`);
      requireValue(Array.isArray(observation.graphs)
        && observation.graphs.length === item.encoded.length,
      `${observation.id} graphs`);
      requireValue(object(observation.beforeApply)
        && object(observation.afterApply),
      `${observation.id} visible states`);
      if (observation.id.startsWith("message-array-advanced-")) {
        requireValue(Array.isArray(observation.features)
          && observation.features.length > 0,
        `${observation.id} advanced features`);
        requireValue(object(observation.effect)
          && observation.effect.effect?.result?.accepted === true
          && !isDeepStrictEqual(
            observation.effect.effect.before,
            observation.effect.effect.after,
          )
          && (observation.effect.followOn === undefined
            || (observation.effect.followOn.result?.accepted === true
              && !isDeepStrictEqual(
                observation.effect.effect.after,
                observation.effect.followOn.after,
              ))),
        `${observation.id} applied effect evidence`);
        requireValue(object(observation.continuation)
          && Array.isArray(observation.continuation.messages)
          && observation.continuation.messages.every(({ encoded, graphs }) =>
            object(encoded) && Array.isArray(graphs) && graphs.length > 0)
          && typeof observation.continuation.compressor === "string"
          && typeof observation.continuation.session === "string",
        `${observation.id} continuation wire evidence`);
      } else {
        requireValue(object(observation.continued)
          && observation.continued.rangeMoveIdentity === true
          && observation.continued.nestedEdit === "upstream-nested",
        `${observation.id} continuation`);
        requireValue(object(observation.continuation)
          && Array.isArray(observation.continuation.messages)
          && observation.continuation.messages.length >= 2
          && observation.continuation.messages.every(({ encoded, graphs }) =>
            object(encoded) && Array.isArray(graphs) && graphs.length > 0)
          && typeof observation.continuation.compressor === "string"
          && typeof observation.continuation.session === "string",
        `${observation.id} continuation wire evidence`);
      }
    }
    if (observation.id === "summary-array-retained-history"
      || observation.id === "summary-array-full-summary"
      || observation.id === "summary-array-peer-history") {
      requireValue(object(observation.rawInput)
        && typeof observation.rawInput.schema === "string"
        && typeof observation.rawInput.forest === "string"
        && typeof observation.rawInput.compressor === "string",
      `${observation.id} raw input evidence`);
      requireValue(object(observation.emitted)
        && object(observation.emitted.schemaSemantics)
        && typeof observation.emitted.compressor === "string",
      `${observation.id} emitted evidence`);
      requireValue(object(observation.schema)
        && isDeepStrictEqual(observation.emitted.schemaSemantics, observation.schema),
      `${observation.id} emitted schema semantics`);
      requireValue(typeof observation.restoredCompressor === "string",
        `${observation.id} restored compressor`);
      requireValue(object(observation.visible), `${observation.id} visible`);
      requireValue(object(observation.continued)
        && observation.continued.rangeMoveIdentity === true
        && observation.continued.nestedEdit === "upstream-nested",
      `${observation.id} continuation`);
      requireValue(observation.history.trunk.length > 0,
        `${observation.id} retained history`);
      requireValue(observation.history.trunk.every(({ changes }) =>
        Array.isArray(changes) && changes.length > 0),
      `${observation.id} retained trunk changes`);
      requireValue(observation.history.peers.every(({ commits }) =>
        Array.isArray(commits)),
      `${observation.id} retained peer changes`);
      if (observation.id === "summary-array-retained-history") {
        requireValue(observation.removed.length > 0,
          `${observation.id} detached content`);
      }
      if (observation.id === "summary-array-peer-history") {
        requireValue(observation.history.peers.some(({ commits }) =>
          commits.length > 0
          && commits.every(({ changes }) =>
            Array.isArray(changes) && changes.length > 0)
          && commits.some(({ changes }) =>
            changes.some(({ type, data }) =>
              type === "data" && object(data)
              && Array.isArray(data.refreshers) && data.refreshers.length > 0))),
        `${observation.id} nonempty peer changes`);
      }
    }
    if (observation.id === "summary-schema-peer-before-upgrade") {
      requireValue(observation.history.peers.some((peer) =>
        peer.base !== "root" && peer.revisions.length > 0),
      "summary-schema-peer-before-upgrade retained pre-upgrade peer branch");
      requireValue(observation.continued === "upstream-continuation",
        "summary-schema-peer-before-upgrade continuation");
    }
    if (observation.id === "summary-schema-upgrade-tail") {
      requireValue(observation.history.trunk.length >= 3,
        "summary-schema-upgrade-tail retained schema tail");
      requireValue(observation.continued === "upstream-continuation",
        "summary-schema-upgrade-tail continuation");
    }
    if (observation.id === "identifier-explicit-custom") {
      requireValue(observation.visible?.child?.id === "literal-custom-id",
        "identifier explicit custom ID");
    }
    if (observation.id === "identifier-generated-uuid"
      || observation.id === "identifier-summary-finalized") {
      requireValue(observation.visible?.child?.id
        === "10000000-0000-4000-8000-000000000004",
      `${observation.id} generated UUID`);
    }
    if (observation.id === "identifier-message-compressed") {
      requireValue(observation.decoded === true
        && observation.afterApply?.child?.id
          === "10000000-0000-4000-8000-000000000004"
        && observation.afterApply?.child?.label === "message",
      "identifier compressed message");
    }
    if (observation.id === "identifier-summary-unfinalized") {
      requireValue(typeof observation.visible?.child?.id === "string"
        && observation.visible.child.label === "unfinalized",
      "identifier unfinalized summary fallback");
    }
    if (observation.id === "identifier-retained-repair") {
      requireValue(observation.removed.some(({ tree }) =>
        tree?.fields?.child?.[0]?.fields?.id?.[0]?.value
          === "retained-custom-id"),
      "identifier retained repair");
    }
    if (observation.id === "identifier-post-load-edit") {
      requireValue(observation.continued === "upstream-continuation",
        "identifier post-load edit");
    }
    if (observation.id === "identifier-native-initial-summary") {
      requireValue(observation.continued?.insertedLabel === "upstream-default"
        && observation.continued.generatedIdentifier === true
        && observation.continued.noCollision === true,
      "identifier native initial summary continuation");
    }
  }
  requireValue(expectedIds.length === ids.size
    && expectedIds.every((id) => ids.has(id)), "required scenario IDs");
  return output;
}

async function produceTarget(target, output) {
  execFileSync("gleam", [
    "run", "--target", target, "-m", "watershed/tree/codec_export",
  ], {
    cwd: repository,
    env: { ...process.env, WATERSHED_TREE_CODEC_OUTPUT: output },
    stdio: "inherit",
    timeout: 120_000,
  });
}

async function replayContinuation(target, artifact, consumer, output) {
  execFileSync("gleam", [
    "run", "--target", target, "-m", "watershed/tree/codec_continuation",
  ], {
    cwd: repository,
    env: {
      ...process.env,
      WATERSHED_TREE_CODEC_INPUT: artifact,
      WATERSHED_TREE_CODEC_CONSUMER: consumer,
      WATERSHED_TREE_CODEC_CONTINUATION_OUTPUT: output,
    },
    stdio: "inherit",
    timeout: 120_000,
  });
  return readJson(output, `${target} native continuation`);
}

async function readJson(path, label) {
  try {
    return JSON.parse(await readFile(path, "utf8"));
  } catch (error) {
    throw new Error(`Could not read ${label}: ${path}`, { cause: error });
  }
}

export async function runCodecInterop({
  outputRoot = defaultOutputRoot,
  produce = produceTarget,
  consume = runCodecConsumer,
  expectedIds = requiredItemIds,
  expected = expectedObservations,
} = {}) {
  await mkdir(outputRoot, { recursive: true });
  const temporary = await mkdtemp(join(resolve(outputRoot), "codec-interop-"));
  const results = [];
  try {
    for (const target of ["erlang", "javascript"]) {
      const artifactPath = join(temporary, `${target}.json`);
      const consumerOutput = join(temporary, `${target}-consumer`);
      await produce(target, artifactPath);
      const artifact = validateNativeArtifact(
        await readJson(artifactPath, `${target} artifact`),
      );
      requireValue(artifact.target === target, `${target} artifact target`);
      await consume(artifactPath, consumerOutput);
      const observationPath = join(consumerOutput, "codec-observations.json");
      const output = validateConsumerOutput(
        await readJson(observationPath, `${target} consumer output`),
        artifact,
        expectedIds,
        expected?.filter(({ id }) => id.startsWith("summary-array-")) ?? [],
      );
      const sourceContinuation = output.observations.find(
        ({ id }) => id === "message-array-sequence",
      )?.continued;
      let nativeContinuation = null;
      if (sourceContinuation !== undefined) {
        const continuationPath = join(temporary, `${target}-continuation.json`);
        nativeContinuation = await replayContinuation(
          target,
          artifactPath,
          observationPath,
          continuationPath,
        );
        requireValue(object(nativeContinuation)
          && nativeContinuation.decodedMessages >= 2
          && object(sourceContinuation)
          && isDeepStrictEqual(nativeContinuation.visible, sourceContinuation.visible),
        `${target} native continuation replay`);
      }
      if (expected !== null) {
        const expectedIds = new Set(expected.map(({ id }) => id));
        requireValue(
          isDeepStrictEqual(
            output.observations
              .filter(({ id }) => expectedIds.has(id))
              .map(comparableObservation),
            expected,
          ),
          `${target} consumer observations differ from expected semantics`,
        );
      }
      results.push({ ...output, nativeContinuation });
    }
    const [erlang, javascript] = results;
    requireValue(
      isDeepStrictEqual(
        erlang.observations.map(comparableObservation),
        javascript.observations.map(comparableObservation),
      )
        && isDeepStrictEqual(erlang.nativeContinuation, javascript.nativeContinuation),
      "target observations differ",
    );
    return {
      targetCount: results.length,
      itemCount: erlang.observations.length,
    };
  } finally {
    await rm(temporary, { recursive: true, force: true });
  }
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  runCodecInterop()
    .then((result) => {
      console.log(
        `SharedTree codec interoperability passed: ${result.targetCount} targets, `
          + `${result.itemCount} items each`,
      );
    })
    .catch((error) => {
      console.error(error);
      process.exitCode = 1;
    });
}
