import { execFileSync } from "node:child_process";
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
];

const object = (value) => value !== null && typeof value === "object" && !Array.isArray(value);

function requireValue(condition, detail) {
  if (!condition) throw new Error(`Invalid native codec artifact: ${detail}`);
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
    requireValue(item.schemaProfile === undefined || item.schemaProfile === "map",
      `${item.id} schemaProfile`);
    requireValue(Object.hasOwn(item, "encoded"), `${item.id} encoded`);
    if (item.kind === "message" || item.kind === "summary") {
      requireValue(typeof item.compressor === "string" && item.compressor.length > 0,
        `${item.id} compressor`);
      requireValue(item.compressorMode === "ongoing" || item.compressorMode === "summary",
        `${item.id} compressorMode`);
      requireValue(typeof item.session === "string" && item.session.length > 0,
        `${item.id} session`);
    }
    if (item.kind === "message") {
      requireValue(object(item.initialSummary), `${item.id} initialSummary`);
      requireValue(Array.isArray(item.allocationRanges), `${item.id} allocationRanges`);
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
  return artifact;
}

function validateConsumerOutput(output, artifact, expectedIds) {
  requireValue(object(output) && output.formatVersion === 1, "consumer formatVersion");
  requireValue(JSON.stringify(output.reference) === JSON.stringify(reference),
    "consumer reference");
  requireValue(output.target === artifact.target, "consumer target");
  requireValue(Array.isArray(output.observations) && output.observations.length > 0,
    "consumer observations");
  requireValue(output.observations.length === artifact.items.length,
    "consumer observation count");
  const items = new Map(artifact.items.map((item) => [item.id, item]));
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
    if (item.kind === "summary") {
      requireValue(Array.isArray(observation.removed), `${observation.id} removed content`);
      requireValue(object(observation.history)
        && Array.isArray(observation.history.trunk)
        && Array.isArray(observation.history.peers),
      `${observation.id} history`);
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
      );
      if (expected !== null) {
        const expectedIds = new Set(expected.map(({ id }) => id));
        requireValue(
          isDeepStrictEqual(
            output.observations.filter(({ id }) => expectedIds.has(id)),
            expected,
          ),
          `${target} consumer observations differ from expected semantics`,
        );
      }
      results.push(output);
    }
    const [erlang, javascript] = results;
    requireValue(
      isDeepStrictEqual(erlang.observations, javascript.observations),
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
