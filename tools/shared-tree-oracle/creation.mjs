import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { dirname, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { parseArgs, promisify } from "node:util";
import {
  createIdCompressor,
  toIdCompressorWithCore,
} from "@fluidframework/id-compressor/internal";
import { convertSummaryTreeToWholeSummaryTree } from "@fluidframework/server-services-client";
import {
  floodgateRevision,
  cleanupOwned,
  openSession,
  serviceConfig,
  snapshot,
  tokenProvider,
  withLocalFloodgate,
} from "./service.mjs";
import {
  canonicalValue,
  decodeTreeSubmissions,
  freshReload,
  nativeAdapter,
  publishUpstreamSummary,
  serverHistory,
  settle,
  upstreamAdapter,
} from "./interop-scenarios.mjs";

const execute = promisify(execFile);
const repository = resolve(import.meta.dirname, "../..");
const logicalCodePackage = "watershed-shared-tree";
const dataStoreType = "org.watershed.shared-tree.m1.bootstrap";
const requiredTreeIndexes = [
  "DetachedFieldIndex",
  "EditManager",
  "Forest",
  "Schema",
];
const creationReaders = ["javascript", "erlang", "upstream"];
const creationTargets = ["javascript", "erlang"];
const creationCells = creationTargets.flatMap((creator) =>
  creationReaders.map((reader) => `${creator}:${reader}`));

function summaryEntry(root, path) {
  let entry = root;
  for (const name of path) {
    assert.equal(entry?.type, 1, `Creation summary path is not a tree: ${path.join("/")}`);
    entry = entry.tree[name];
    assert(entry, `Creation summary path is missing: ${path.join("/")}`);
  }
  return entry;
}

function jsonBlob(root, path) {
  const entry = summaryEntry(root, path);
  assert.equal(entry.type, 2, `Creation summary path is not a blob: ${path.join("/")}`);
  const content = typeof entry.content === "string"
    ? entry.content
    : Buffer.from(entry.content).toString("utf8");
  return JSON.parse(content);
}

function summaryPaths(root, prefix = "") {
  assert.equal(root.type, 1, `Creation summary entry is not a tree: ${prefix || "/"}`);
  const paths = [];
  for (const [name, entry] of Object.entries(root.tree)) {
    const path = `${prefix}/${name}`;
    paths.push(path);
    if (entry.type === 1) paths.push(...summaryPaths(entry, path));
  }
  return paths;
}

function storedSnapshotPaths(root, prefix = "") {
  const paths = [];
  for (const name of Object.keys(root.blobs)) paths.push(`${prefix}/${name}`);
  for (const [name, entry] of Object.entries(root.trees)) {
    const path = `${prefix}/${name}`;
    paths.push(path);
    paths.push(...storedSnapshotPaths(entry, path));
  }
  return paths;
}

function storedJsonBlob(snapshotValue, path) {
  let tree = snapshotValue.tree;
  for (const name of path.slice(0, -1)) {
    tree = tree.trees[name];
    assert(tree, `Persisted initial summary path is missing: ${path.join("/")}`);
  }
  const id = tree.blobs[path.at(-1)];
  assert.equal(typeof id, "string",
    `Persisted initial summary blob is missing: ${path.join("/")}`);
  return JSON.parse(Buffer.from(snapshotValue.blobs[id], "base64").toString("utf8"));
}

function storedJsonBlobAtAny(snapshotValue, paths) {
  for (const path of paths) {
    let tree = snapshotValue.tree;
    for (const name of path.slice(0, -1)) {
      tree = tree?.trees[name];
      if (!tree) break;
    }
    const id = tree?.blobs[path.at(-1)];
    if (typeof id === "string") {
      return {
        path,
        value: JSON.parse(
          Buffer.from(snapshotValue.blobs[id], "base64").toString("utf8"),
        ),
      };
    }
  }
  assert.fail(`Persisted initial summary is missing every candidate: ${
    paths.map((path) => path.join("/")).join(", ")
  }`);
}

function wholeSummaryEntries(entries) {
  return entries.flatMap((entry) => [
    entry,
    ...(entry.value?.type === "tree" ? wholeSummaryEntries(entry.value.entries) : []),
  ]);
}

function compressorObservation(bytes) {
  assert.equal(bytes.byteLength % 8, 0, "Initial compressor has an invalid byte length");
  const number = (index) => bytes.readDoubleLE(index * 8);
  const version = number(0);
  const hasLocalState = number(1) === 1;
  const sessionCount = number(2);
  const clusterCount = number(3);
  assert(Number.isSafeInteger(sessionCount) && sessionCount >= 0,
    "Initial compressor has an invalid session count");
  assert(Number.isSafeInteger(clusterCount) && clusterCount >= 0,
    "Initial compressor has an invalid cluster count");
  const clusterOffset = 4 + sessionCount * 2;
  const clusters = Array.from({ length: clusterCount }, (_unused, index) => {
    const offset = clusterOffset + index * 3;
    return {
      sessionIndex: number(offset),
      capacity: number(offset + 1),
      count: number(offset + 2),
    };
  });
  return {
    encoding: "base64",
    byteLength: bytes.length,
    hash: createHash("sha256").update(bytes).digest("hex"),
    version,
    hasLocalState,
    sessionCount,
    clusterCount,
    clusters,
  };
}

function emptyCompressorContract() {
  const serialized = toIdCompressorWithCore(createIdCompressor(
    "11111111-1111-4111-8111-111111111111",
  )).serialize(false);
  return {
    serialized,
    ...compressorObservation(Buffer.from(serialized, "base64")),
  };
}

function rootState(session) {
  const root = session.data.view.root;
  return {
    title: root.title,
    enabled: root.enabled,
    rating: root.rating,
    marker: root.marker,
    note: root.note ?? null,
    point: { x: root.point.x, y: root.point.y },
  };
}

async function waitFor(predicate, stage, milliseconds = 15_000) {
  const deadline = Date.now() + milliseconds;
  while (!await predicate()) {
    assert(Date.now() < deadline, `Timed out: ${stage}`);
    await new Promise((resolveWait) => setTimeout(resolveWait, 25));
  }
}

export function inspectCreationSummary(summary, {
  documentId,
  freshReaderLoaded,
  freshReaderContinuedEditing,
} = {}) {
  assert.equal(summary?.type, 1, "Initial combined summary must be a tree");
  const protocol = summaryEntry(summary, [".protocol"]);
  const app = summaryEntry(summary, [".app"]);
  assert.deepEqual(Object.keys(summary.tree).sort(), [".app", ".protocol"],
    "Initial combined summary must contain only .app and .protocol");

  const attributes = jsonBlob(protocol, ["attributes"]);
  const quorumMembers = jsonBlob(protocol, ["quorumMembers"]);
  const quorumProposals = jsonBlob(protocol, ["quorumProposals"]);
  const quorumValues = jsonBlob(protocol, ["quorumValues"]);
  const code = quorumValues.find(([key]) => key === "code")?.[1];
  assert(code, "Initial quorum has no code value");

  const metadata = jsonBlob(app, [".metadata"]);
  const aliases = jsonBlob(app, [".aliases"]);
  const compressorSerialized = jsonBlob(app, [".idCompressor"]);
  assert.equal(typeof compressorSerialized, "string", "Initial compressor is not base64");
  const compressorBytes = Buffer.from(compressorSerialized, "base64");
  assert(compressorBytes.length >= 8, "Initial compressor is too short");
  const historyCodec = jsonBlob(app, [
    ".channels", "A", ".channels", "_C", "indexes", "EditManager", "String",
  ]);
  const schema = jsonBlob(app, [
    ".channels", "A", ".channels", "_C", "indexes", "Schema", "SchemaString",
  ]);
  const forest = jsonBlob(app, [
    ".channels", "A", ".channels", "_C", "indexes", "Forest", "contents",
  ]);
  const detachedFields = jsonBlob(app, [
    ".channels", "A", ".channels", "_C", "indexes",
    "DetachedFieldIndex", "DetachedFieldIndexBlob",
  ]);
  const bootstrap = jsonBlob(app, [".channels", "A", ".channels", "root", "header"]);
  const component = jsonBlob(app, [".channels", "A", ".component"]);
  const mapAttributes = jsonBlob(app, [
    ".channels", "A", ".channels", "root", ".attributes",
  ]);
  const treeAttributes = jsonBlob(app, [
    ".channels", "A", ".channels", "_C", ".attributes",
  ]);
  const paths = summaryPaths(app);
  const gcTreePresent = app.tree.gc !== undefined;
  const gcNodes = gcTreePresent
    ? Object.fromEntries(Object.entries(jsonBlob(app, ["gc", "__gc_root"]).gcNodes)
      .map(([route, value]) => [route, value.outboundRoutes]))
    : null;
  const dataStoreRoute = `/${aliases.find(([alias]) => alias === "root")?.[1]}`;
  const treeRoute = bootstrap.content?.tree?.value?.url;
  const createPayload = {
    summary: convertSummaryTreeToWholeSummaryTree(undefined, app),
    sequenceNumber: attributes.sequenceNumber,
    values: quorumValues,
    enableDiscovery: false,
    generateToken: false,
    isEphemeralContainer: false,
    enableAnyBinaryBlobOnFirstSummary: true,
  };

  return {
    formatVersion: 1,
    documentId,
    sequenceNumber: attributes.sequenceNumber,
    minimumSequenceNumber: attributes.minimumSequenceNumber,
    aliases,
    bootstrapHandle: bootstrap.content?.tree?.value?.url,
    codePackage: code.value?.package,
    codeQuorum: {
      approvalSequenceNumber: code.approvalSequenceNumber,
      commitSequenceNumber: code.commitSequenceNumber,
      sequenceNumber: code.sequenceNumber,
    },
    idCompressorMode: metadata.documentSchema?.runtime?.idCompressorMode,
    compressor: compressorObservation(compressorBytes),
    emptyCompressorContract: emptyCompressorContract(),
    history: {
      trunk: historyCodec.trunk,
      branches: historyCodec.branches,
    },
    historyCodecVersion: historyCodec.version,
    freshReaderLoaded,
    freshReaderContinuedEditing,
    metadata,
    runtimePackageVersion: metadata.createContainerRuntimeVersion,
    dataStoreType: JSON.parse(component.pkg)[0],
    routes: {
      dataStore: dataStoreRoute,
      map: `${dataStoreRoute}/root`,
      tree: treeRoute,
    },
    gc: {
      feature: metadata.gcFeature,
      treePresent: gcTreePresent,
      nodes: gcNodes,
    },
    channelAttributes: {
      map: mapAttributes,
      tree: treeAttributes,
    },
    treeState: {
      history: historyCodec,
      schema,
      forest,
      detachedFields,
    },
    summaryPaths: paths,
    initialCombinedSummary: summary,
    createPayload,
    protocol: {
      attributes,
      quorumMembers,
      quorumProposals,
      quorumValues,
    },
  };
}

export function validateCreationCapture(capture) {
  assert.equal(capture.sequenceNumber, 0);
  assert.equal(capture.minimumSequenceNumber, 0);
  assert.deepEqual(capture.aliases, [["root", "A"]]);
  assert.equal(capture.bootstrapHandle, "/A/_C");
  assert.equal(capture.codePackage, logicalCodePackage);
  assert.equal(capture.idCompressorMode, "on");
  assert.deepEqual(capture.history, { trunk: [], branches: [] });
  assert.equal(capture.freshReaderLoaded, true);
  assert.equal(capture.freshReaderContinuedEditing, true);
  assert.deepEqual(capture.codeQuorum, {
    approvalSequenceNumber: 0,
    commitSequenceNumber: 0,
    sequenceNumber: 0,
  });
  assert.deepEqual(capture.protocol.quorumMembers, []);
  assert.deepEqual(capture.protocol.quorumProposals, []);
  assert.equal(capture.metadata.lastMessage, undefined,
    "Initial metadata must not contain a fabricated lastMessage");
  assert.deepEqual(capture.metadata.message, { sequenceNumber: -1 });
  assert.equal(capture.metadata.summaryNumber, 1);
  assert.equal(capture.metadata.summaryFormatVersion, 1);
  assert.equal(capture.metadata.gcFeature, 3);
  assert.equal(capture.metadata.sweepEnabled, false);
  assert.equal(capture.metadata.documentSchema?.version, 1);
  assert.equal(capture.metadata.documentSchema?.refSeq, 0);
  assert.equal(capture.metadata.documentSchema?.info?.minVersionForCollab, "2.117.0");
  assert.equal(capture.metadata.documentSchema?.runtime?.explicitSchemaControl, true);
  assert.equal(capture.metadata.documentSchema?.runtime?.opGroupingEnabled, true);
  assert.equal(capture.dataStoreType, dataStoreType);
  assert.deepEqual(capture.routes, {
    dataStore: "/A",
    map: "/A/root",
    tree: "/A/_C",
  });
  assert.deepEqual(capture.gc, {
    feature: 3,
    treePresent: false,
    nodes: null,
  });
  assert(Number.isInteger(capture.historyCodecVersion));
  assert.equal(capture.compressor.version, 2);
  assert.equal(capture.compressor.hasLocalState, false);
  assert.equal(capture.compressor.sessionCount, 1);
  assert.equal(capture.compressor.clusterCount, 1);
  assert.deepEqual(capture.compressor.clusters, [{
    sessionIndex: 0,
    capacity: 513,
    count: 1,
  }]);
  assert.deepEqual(capture.emptyCompressorContract, {
    serialized: "AAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
    encoding: "base64",
    byteLength: 32,
    hash: "497d0d90f9a77f1d67f0567e67f7ed60f9d324cde0db266e51afd4b25cf24fa4",
    version: 2,
    hasLocalState: false,
    sessionCount: 0,
    clusterCount: 0,
    clusters: [],
  });
  assert.deepEqual(capture.treeState.history, {
    trunk: [],
    branches: [],
    version: 7,
  });
  assert.deepEqual(capture.treeState.detachedFields, {
    version: 2,
    data: [],
    maxId: 0,
  });
  for (const index of requiredTreeIndexes) {
    assert(capture.summaryPaths.includes(
      `/.channels/A/.channels/_C/indexes/${index}`,
    ), `Initial summary is missing ${index}`);
  }
  assert.equal(capture.createPayload.sequenceNumber, 0);
  assert.deepEqual(capture.createPayload.values, capture.protocol.quorumValues);
  const entries = wholeSummaryEntries(capture.createPayload.summary.entries);
  assert(entries.every((entry) => entry.value !== undefined),
    "Initial create payload must not contain summary handles");
  assert(!entries.some(({ path }) => path === ".app"),
    "Create payload must not contain an extra .app wrapper");
  assert.equal(typeof capture.documentId, "string");
  assert(capture.documentId.length > 0);
  assert.equal(capture.createResponse?.documentId, capture.documentId,
    "Create response document ID does not match the attached document");
  assert.equal(capture.persistedInitialSummary?.sequenceNumber, 0);
  assert.equal(capture.persistedInitialSummary?.minimumSequenceNumber, 0);
  assert.equal(typeof capture.persistedInitialSummary?.version?.id, "string");
  assert(capture.persistedInitialSummary.paths.includes("/.app"));
  assert(capture.persistedInitialSummary.paths.includes("/.protocol/attributes"));
  assert.equal(capture.freshLoad?.initialSummaryRemainedHeadAfterEdit, true);
  assert(capture.freshLoad.storageObservations.some(({ operation, done, sequenceNumbers }) =>
    operation === "readMessages" && done === true && sequenceNumbers.length === 0),
  "Fresh reader did not observe an empty initial delta tail");
  return capture;
}

export function validateCreationInteropReport(report) {
  assert.equal(report?.formatVersion, 1, "Unsupported creation report format");
  assert.equal(typeof report.runId, "string", "Creation report has no run ID");
  assert(report.runId.length > 0, "Creation report has an empty run ID");
  assert.match(report.profileDigest, /^[0-9a-f]{64}$/,
    "Creation report has an invalid profile digest");
  assert.equal(report.service?.implementation, "floodgate",
    "Creation report used another service");
  assert.equal(report.service?.simulated, false,
    "Creation report used a simulated service");
  assert.equal(typeof report.service?.revision, "string",
    "Creation report has no service revision");
  assert(Array.isArray(report.cells), "Creation report has no cells");
  assert.deepEqual(
    report.cells.map(({ creator, reader }) => `${creator}:${reader}`).sort(),
    creationCells.toSorted(),
    "Creation report does not contain the strict six-cell matrix",
  );
  const documentIds = new Map();
  for (const cell of report.cells) {
    assert.equal(cell.runId, report.runId, "Creation cell belongs to another run");
    assert.equal(cell.profileDigest, report.profileDigest,
      "Creation cell belongs to another profile");
    assert.equal(typeof cell.documentId, "string", "Creation cell has no document ID");
    assert(cell.documentId.length > 0, "Creation cell has an empty document ID");
    const previous = documentIds.get(cell.creator);
    if (previous === undefined) documentIds.set(cell.creator, cell.documentId);
    else assert.equal(cell.documentId, previous,
      "Creation reader cells do not share the creator document");
    for (const field of [
      "nativeCreated",
      "loadedInitialSummary",
      "continuedEditing",
      "peerObservedEdit",
      "reloadedSummaryAndTail",
    ]) {
      assert.equal(cell[field], true, `Creation cell lacks ${field} evidence`);
    }
    assert.deepEqual(Object.keys(cell.evidence ?? {}).sort(), [
      "continuation",
      "creation",
      "initialLoad",
      "summaryReload",
      "upstreamContinuation",
    ], "Creation cell has incomplete evidence");
    for (const path of Object.values(cell.evidence)) {
      assert.equal(typeof path, "string", "Creation evidence path is not a string");
      assert(path.length > 0 && !path.startsWith("/") && !path.split("/").includes(".."),
        "Creation evidence path is outside the run directory");
    }
  }
  assert.equal(documentIds.size, creationTargets.length,
    "Creation report has incomplete creator targets");
  assert.notEqual(documentIds.get("javascript"), documentIds.get("erlang"),
    "Creation targets reused another run's document ID");
  assert.deepEqual(report.skipped, [], "Creation report contains skipped cells");
  assert.deepEqual(report.divergences, [], "Creation report contains divergences");
  return report;
}

function matrixTree({
  title = "native creation",
  enabled = true,
  rating = 17.5,
  note,
  point = { x: 3, y: -4 },
} = {}) {
  return canonicalValue({
    present: true,
    value: {
      kind: "object",
      schemaId: "org.watershed.shared-tree.m1.Root",
      fields: [
        ["enabled", { kind: "boolean", value: enabled }],
        ["marker", { kind: "null" }],
        ...(note === undefined ? [] : [
          ["note", { kind: "string", value: note }],
        ]),
        ["point", {
          kind: "object",
          schemaId: "org.watershed.shared-tree.m1.Point",
          fields: [
            ["x", { kind: "number", value: point.x }],
            ["y", { kind: "number", value: point.y }],
          ],
        }],
        ["rating", { kind: "number", value: rating }],
        ["title", { kind: "string", value: title }],
      ],
    },
  });
}

function matrixExpectedStages(creator, conflictWinner) {
  const rating = creator === "javascript" ? 31 : 32;
  return [
    ["all-authors", matrixTree({
      title: `${creator}-upstream`, enabled: false, rating,
    })],
    ["optional-set", matrixTree({
      title: `${creator}-upstream`, enabled: false, rating,
      note: `${creator}-optional`,
    })],
    ["optional-clear", matrixTree({
      title: `${creator}-upstream`, enabled: false, rating,
    })],
    ["nested-edit", matrixTree({
      title: `${creator}-upstream`, enabled: false, rating,
      point: { x: 8, y: -4 },
    })],
    ["parent-replacement", matrixTree({
      title: `${creator}-upstream`, enabled: false, rating,
      point: { x: 13, y: 21 },
    })],
    ["conflict", matrixTree({
      title: conflictWinner, enabled: false, rating,
      point: { x: 13, y: 21 },
    })],
  ];
}

function assertCheckpointTree(checkpoint, expectedTree, label) {
  for (const observation of checkpoint.observations) {
    validateObservation(
      observation,
      observation.implementation,
      expectedTree,
      0,
      `${label}:${observation.implementation}`,
    );
  }
}

function stringField(tree, name) {
  const field = tree?.value?.fields?.find(([key]) => key === name)?.[1];
  assert.equal(field?.kind, "string", `Tree field ${name} is not a string`);
  return field.value;
}

function validateArtifactBinding(artifact, cell, kind) {
  assert.equal(artifact?.formatVersion, 1, `${kind} evidence has another format`);
  assert.equal(artifact.kind, kind, `${kind} evidence has another kind`);
  assert.equal(artifact.runId, cell.runId, `${kind} evidence belongs to another run`);
  assert.equal(artifact.profileDigest, cell.profileDigest,
    `${kind} evidence belongs to another profile`);
  assert.equal(artifact.creator, cell.creator,
    `${kind} evidence belongs to another creator`);
  assert.equal(artifact.documentId, cell.documentId,
    `${kind} evidence belongs to another document`);
}

function validateObservation(observation, reader, expectedTree, minimumSequence, label) {
  assert.equal(observation?.implementation, reader, `${label} has another reader`);
  assert(Number.isSafeInteger(observation.sequenceNumber)
    && observation.sequenceNumber >= minimumSequence,
  `${label} has an invalid sequence`);
  assert.equal(observation.pendingTreeCount, 0, `${label} has pending tree commits`);
  assert.equal(observation.inflightSubmissionCount, 0,
    `${label} has in-flight submissions`);
  assert.deepEqual(observation.wholeTree, expectedTree, `${label} has another tree`);
}

export async function validateCreationInteropEvidence(
  report,
  runDirectory,
  { readArtifact = readFile } = {},
) {
  validateCreationInteropReport(report);
  const root = resolve(runDirectory);
  const cache = new Map();
  const load = async (relative, label) => {
    if (cache.has(relative)) return cache.get(relative);
    const path = resolve(root, relative);
    assert(path.startsWith(`${root}/`), `${label} evidence escaped the run directory`);
    let artifact;
    try {
      artifact = JSON.parse(await readArtifact(path, "utf8"));
    } catch (error) {
      throw new Error(`${label} evidence is missing or corrupt: ${relative}`, {
        cause: error,
      });
    }
    cache.set(relative, artifact);
    return artifact;
  };

  for (const cell of report.cells) {
    const creation = await load(cell.evidence.creation, "creation");
    validateArtifactBinding(creation, cell, "creation");
    assert(creation.readers?.includes(cell.reader),
      "creation evidence does not include this reader");
    assert.equal(creation.nativeCreated, true, "creation evidence is not native");
    assert.deepEqual(
      canonicalValue({ present: true, value: creation.root }),
      matrixTree(),
      "creation evidence has another initial tree",
    );

    const initial = await load(cell.evidence.initialLoad, "initial-load");
    validateArtifactBinding(initial, cell, "initial-load");
    assert.equal(initial.reader, cell.reader, "initial-load evidence has another reader");
    assert.equal(initial.stored?.sequenceNumber, 0,
      "initial-load evidence did not load the initial summary");
    assert.equal(initial.stored?.minimumSequenceNumber, 0,
      "initial-load evidence has another minimum sequence");
    assert.deepEqual(initial.stored?.aliases, [["root", "A"]],
      "initial-load evidence has another root alias");
    assert.equal(initial.stored?.bootstrapHandle, "/A/_C",
      "initial-load evidence has another bootstrap handle");
    validateObservation(
      initial.observation,
      cell.reader,
      matrixTree(),
      0,
      "initial-load evidence",
    );

    const continuation = await load(cell.evidence.continuation, "continuation");
    validateArtifactBinding(continuation, cell, "continuation");
    assert.equal(continuation.reader, cell.reader,
      "continuation evidence has another reader");
    assert([
      `${cell.creator}-javascript-conflict`,
      `${cell.creator}-erlang-conflict`,
    ].includes(continuation.conflictWinner),
    "continuation evidence has an invalid conflict winner");
    assert(continuation.firstEditAllocations?.some(({ allocations }) =>
      allocations?.some(({ first, last }) =>
        Number.isSafeInteger(first) && Number.isSafeInteger(last) && first <= last)),
    "continuation evidence has no first-edit allocation");
    const expectedStages = matrixExpectedStages(cell.creator, continuation.conflictWinner);
    assert.equal(continuation.stages?.length, expectedStages.length,
      "continuation evidence has incomplete edit stages");
    let sequence = initial.observation.sequenceNumber;
    for (const [index, [name, expectedTree]] of expectedStages.entries()) {
      const stage = continuation.stages[index];
      assert.equal(stage?.name, name, "continuation evidence has another edit stage");
      validateObservation(
        stage.observation,
        cell.reader,
        expectedTree,
        sequence + 1,
        `${name} evidence`,
      );
      sequence = stage.observation.sequenceNumber;
    }

    const reload = await load(cell.evidence.summaryReload, "summary-reload");
    validateArtifactBinding(reload, cell, "summary-reload");
    assert.equal(reload.reader, cell.reader, "summary-reload evidence has another reader");
    assert.equal(typeof reload.version, "string", "summary-reload evidence has no version");
    assert(Number.isSafeInteger(reload.nativeSummaryReferenceSequenceNumber),
      "summary-reload evidence has no native summary reference");
    assert(Number.isSafeInteger(reload.tailSequenceNumber)
      && reload.tailSequenceNumber > reload.nativeSummaryReferenceSequenceNumber,
    "summary-reload evidence has no sequenced tail after the native summary");
    assert.equal(reload.tailSubmission?.outerSequenceNumber, reload.tailSequenceNumber,
      "summary-reload evidence has another tail submission");
    const tailTree = matrixTree({
      title: continuation.conflictWinner,
      enabled: false,
      rating: cell.creator === "javascript" ? 31 : 32,
      note: `${cell.creator}-after-native-summary`,
      point: { x: 13, y: 21 },
    });
    assert.deepEqual(reload.expectedTree, tailTree,
      "summary-reload evidence expected another tail state");
    validateObservation(
      reload.reloaded?.observation,
      cell.reader,
      tailTree,
      reload.tailSequenceNumber,
      "summary-reload evidence",
    );
    assert.equal(reload.reloaded?.author, cell.reader,
      "summary-reload evidence has another reader author");
    assert(JSON.stringify(reload.reloaded?.selectedSummaryRequests).includes(reload.version),
      "summary-reload evidence did not select the native summary");

    const upstream = await load(
      cell.evidence.upstreamContinuation,
      "upstream-summary-continuation",
    );
    validateArtifactBinding(upstream, cell, "upstream-summary-continuation");
    assert.equal(upstream.reader, cell.reader,
      "upstream-summary-continuation evidence has another reader");
    const summarySequence = upstream.upstreamSummary?.summaryAckOp?.sequenceNumber;
    assert(Number.isSafeInteger(summarySequence),
      "upstream-summary-continuation evidence has no summary acknowledgement");
    validateObservation(
      upstream.observation,
      cell.reader,
      matrixTree({
        title: `${cell.creator}-after-upstream-summary`,
        enabled: false,
        rating: cell.creator === "javascript" ? 31 : 32,
        note: `${cell.creator}-after-native-summary`,
        point: { x: 13, y: 21 },
      }),
      summarySequence + 1,
      "upstream-summary-continuation evidence",
    );

    const derived = {
      nativeCreated: creation.nativeCreated === true,
      loadedInitialSummary: initial.stored.sequenceNumber === 0,
      continuedEditing: sequence > initial.observation.sequenceNumber,
      peerObservedEdit: continuation.stages.every(({ observation }) =>
        observation.pendingTreeCount === 0 && observation.inflightSubmissionCount === 0),
      reloadedSummaryAndTail:
        reload.reloaded.observation.sequenceNumber >= reload.tailSequenceNumber,
    };
    for (const [field, value] of Object.entries(derived)) {
      assert.equal(cell[field], value, `Creation cell contradicts ${field} evidence`);
    }
  }
  return report;
}

export async function inspectPersistedInitialSummary(session) {
  const service = await session.documentServiceFactory.createDocumentService(
    session.container.resolvedUrl,
  );
  try {
    const storage = await service.connectToStorage();
    const versions = await storage.getVersions(null, 1);
    assert.equal(versions.length, 1, "Native-created document has no initial summary");
    const captured = await snapshot(storage);
    const attributes = storedJsonBlob(captured, [".protocol", "attributes"]);
    const aliases = storedJsonBlobAtAny(captured, [
      [".app", ".aliases"],
      [".aliases"],
    ]);
    const bootstrap = storedJsonBlobAtAny(captured, [
      [".app", ".channels", "A", ".channels", "root", "header"],
      [".channels", "A", ".channels", "root", "header"],
    ]);
    return {
      version: versions[0],
      aliasesPath: aliases.path,
      bootstrapPath: bootstrap.path,
      sequenceNumber: attributes.sequenceNumber,
      minimumSequenceNumber: attributes.minimumSequenceNumber,
      aliases: aliases.value,
      bootstrapHandle: bootstrap.value.content?.tree?.value?.url,
    };
  } finally {
    service.dispose();
  }
}

export async function captureCreation(config) {
  const containers = [];
  let scenarioError;
  try {
    const creator = await openSession(config, containers, undefined, false, {
      codeDetails: { package: logicalCodePackage },
      observeCreateContainer: true,
    });
    const creation = creator.storageObservations.find(
      ({ operation }) => operation === "createContainer",
    );
    assert(creation, "The driver did not expose its createContainer summary");
    const documentId = creator.container.resolvedUrl?.id;
    assert.equal(creation.documentId, documentId,
      "The create response did not identify the attached document");

    const storageService = await creator.documentServiceFactory.createDocumentService(
      creator.container.resolvedUrl,
    );
    let initialVersion;
    let initialSnapshot;
    try {
      const storage = await storageService.connectToStorage();
      const versions = await storage.getVersions(null, 1);
      assert.equal(versions.length, 1, "Created document has no initial summary");
      initialVersion = versions[0];
      initialSnapshot = await snapshot(storage);
    } finally {
      storageService.dispose();
    }

    const fresh = await openSession(config, containers, documentId, false, {
      cache: false,
      observeStorage: true,
    });
    const initialRoot = rootState(fresh);
    fresh.data.view.root.title = "creation-continuation";
    await waitFor(() =>
      creator.data.view.root.title === "creation-continuation"
      && !creator.container.isDirty
      && !fresh.container.isDirty,
    "fresh upstream continuation");

    const verificationService = await fresh.documentServiceFactory.createDocumentService(
      fresh.container.resolvedUrl,
    );
    let latestVersion;
    try {
      const storage = await verificationService.connectToStorage();
      [latestVersion] = await storage.getVersions(null, 1);
    } finally {
      verificationService.dispose();
    }
    assert.equal(latestVersion?.id, initialVersion.id,
      "A follow-up summary replaced the initial summary before verification");

    const capture = inspectCreationSummary(creation.summary, {
      documentId,
      freshReaderLoaded: true,
      freshReaderContinuedEditing: true,
    });
    capture.createResponse = { documentId: creation.documentId };
    const persistedAttributes = storedJsonBlob(initialSnapshot, [".protocol", "attributes"]);
    capture.persistedInitialSummary = {
      version: initialVersion,
      sequenceNumber: persistedAttributes.sequenceNumber,
      minimumSequenceNumber: persistedAttributes.minimumSequenceNumber,
      paths: storedSnapshotPaths(initialSnapshot.tree),
      snapshot: initialSnapshot,
    };
    capture.freshLoad = {
      initialRoot,
      continuedRoot: rootState(fresh),
      storageObservations: fresh.storageObservations,
      initialSummaryRemainedHeadAfterEdit: latestVersion?.id === initialVersion.id,
    };
    validateCreationCapture(capture);
    return capture;
  } catch (error) {
    scenarioError = error;
    throw error;
  } finally {
    cleanupOwned(containers, scenarioError);
  }
}

function json(value) {
  return `${JSON.stringify(value, (_key, item) => {
    if (item instanceof Uint8Array) {
      return { encoding: "base64", content: Buffer.from(item).toString("base64") };
    }
    return item;
  }, 2)}\n`;
}

async function writeRunArtifact(runDirectory, relative, value) {
  assert(!relative.startsWith("/") && !relative.split("/").includes(".."),
    "Creation artifact path escaped its run directory");
  const path = resolve(runDirectory, relative);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, json(value), { mode: 0o600 });
  return relative;
}

function creationInput() {
  return {
    kind: "object",
    schemaId: "org.watershed.shared-tree.m1.Root",
    fields: [
      ["title", { kind: "string", value: "native creation" }],
      ["enabled", { kind: "boolean", value: true }],
      ["rating", { kind: "number", value: 17.5 }],
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

async function creationSchema() {
  const fixture = JSON.parse(await readFile(resolve(
    repository,
    "test/fixtures/shared_tree/cases/schema-profile.json",
  )));
  return fixture.input.summary.tree.indexes.tree.Schema.tree.SchemaString.content;
}

function probeObservation(stdout) {
  const prefix = "WATERSHED_TREE_CREATION=";
  const line = stdout.split(/\r?\n/).find((value) => value.startsWith(prefix));
  assert(line, `Native creation probe emitted no result: ${stdout}`);
  return JSON.parse(line.slice(prefix.length));
}

async function runCreatorProbe(target, {
  baseUrl,
  tenant,
  token,
  schema,
  root,
  expected,
}) {
  const env = {
    ...process.env,
    WATERSHED_TREE_CREATION_URL: baseUrl,
    WATERSHED_TREE_CREATION_TENANT: tenant,
    WATERSHED_TREE_CREATION_TOKEN: token,
    WATERSHED_TREE_CREATION_SCHEMA: schema,
    WATERSHED_TREE_CREATION_ROOT: JSON.stringify(root),
    WATERSHED_TREE_CREATION_EXPECT: expected,
  };
  let result;
  if (target === "javascript") {
    const moduleUrl = pathToFileURL(resolve(
      repository,
      "build/dev/javascript/watershed/watershed/shared_tree_creation_probe.mjs",
    )).href;
    result = await execute(process.execPath, [
      "--input-type=module",
      "--eval",
      `const probe = await import(${JSON.stringify(moduleUrl)}); await probe.main();`,
    ], { cwd: repository, env, timeout: 60_000 });
  } else {
    result = await execute("gleam", [
      "run", "--target", "erlang", "-m", "watershed/shared_tree_creation_probe",
    ], { cwd: repository, env, timeout: 60_000 });
  }
  assert(!result.stdout.includes(token), `${target} creation probe echoed its token`);
  assert(!result.stderr.includes(token), `${target} creation probe echoed its token`);
  return probeObservation(result.stdout);
}

async function rejectInvalidInitializer(target, schema, root) {
  let requests = 0;
  const server = createServer((_request, response) => {
    requests += 1;
    response.writeHead(500);
    response.end();
  });
  await new Promise((resolveListen) => server.listen(0, "127.0.0.1", resolveListen));
  const address = server.address();
  assert(address && typeof address === "object");
  const invalid = structuredClone(root);
  invalid.fields[0][1] = { kind: "number", value: 1 };
  try {
    const result = await runCreatorProbe(target, {
      baseUrl: `http://127.0.0.1:${address.port}`,
      tenant: "tenant",
      token: "invalid-initializer-token",
      schema,
      root: invalid,
      expected: "failure",
    });
    assert.equal(result.ok, false, `${target} accepted an invalid initializer`);
    assert.equal(requests, 0, `${target} sent an invalid initializer to the service`);
    return { rejected: true, createRequests: requests };
  } finally {
    await new Promise((resolveClose, rejectClose) =>
      server.close((error) => error ? rejectClose(error) : resolveClose()));
  }
}

async function cleanupScenario(natives, containers, originalError) {
  const errors = [];
  for (const native of natives.toReversed()) {
    try {
      await native.close();
    } catch (error) {
      errors.push(error);
    }
  }
  for (const container of containers.toReversed()) {
    try {
      if (!container.closed) container.dispose();
    } catch (error) {
      errors.push(error);
    }
  }
  if (errors.length === 0) return;
  if (originalError) {
    originalError.cleanupErrors = [...(originalError.cleanupErrors ?? []), ...errors];
    return;
  }
  throw new AggregateError(errors, "Creation interop cleanup failed");
}

async function runCreatorMatrix(config, context, creator, schema, root) {
  const containers = [];
  const natives = [];
  let scenarioError;
  try {
    const { jwt: creationToken } =
      await tokenProvider(config).fetchStorageToken(config.tenantId);
    const created = await runCreatorProbe(creator, {
      baseUrl: config.httpUrl,
      tenant: config.tenantId,
      token: creationToken,
      schema,
      root,
      expected: "success",
    });
    assert.equal(created.ok, true, `${creator} did not create a document`);
    const documentId = created.documentId;
    assert.equal(typeof documentId, "string");
    assert(documentId.length > 0);
    const creationPath = await writeRunArtifact(
      context.runDirectory,
      `${creator}/creation.json`,
      {
        formatVersion: 1,
        kind: "creation",
        runId: context.runId,
        profileDigest: context.profileDigest,
        creator,
        documentId,
        readers: creationReaders,
        nativeCreated: true,
        root,
      },
    );

    const { jwt } = await tokenProvider(config).fetchOrdererToken(
      config.tenantId,
      documentId,
    );
    const upstreamSession = await openSession(
      config,
      containers,
      documentId,
      false,
      { cache: false, observeStorage: true },
    );
    const upstream = upstreamAdapter(upstreamSession);
    for (const target of creationTargets) {
      natives.push(await nativeAdapter(target, config, {
        runId: context.runId,
        documentId,
        tenant: config.tenantId,
        viewSchema: schema,
      }, jwt));
    }
    const adapters = {
      upstream,
      javascript: natives[0],
      erlang: natives[1],
    };
    const expectedInitial = canonicalValue({ present: true, value: root });
    const initial = await settle(adapters);
    for (const observation of initial.observations) {
      assert.deepEqual(observation.wholeTree, expectedInitial,
        `${creator}:${observation.implementation} changed the initial tree`);
    }
    const stored = await inspectPersistedInitialSummary(upstreamSession);
    assert.equal(stored.sequenceNumber, 0);
    assert.equal(stored.minimumSequenceNumber, 0);
    assert.deepEqual(stored.aliases, [["root", "A"]]);
    assert.equal(stored.bootstrapHandle, "/A/_C");

    const initialPaths = {};
    for (const observation of initial.observations) {
      initialPaths[observation.implementation] = await writeRunArtifact(
        context.runDirectory,
        `${creator}/${observation.implementation}/initial-load.json`,
        {
          formatVersion: 1,
          kind: "initial-load",
          runId: context.runId,
          profileDigest: context.profileDigest,
          creator,
          reader: observation.implementation,
          documentId,
          stored,
          observation,
        },
      );
    }

    await adapters.javascript.set(["enabled"], false);
    const firstEdit = await settle(adapters);
    assertCheckpointTree(firstEdit, matrixTree({ enabled: false }), "first edit");
    const historyAfterFirstEdit = decodeTreeSubmissions(await serverHistory(upstreamSession));
    assert(historyAfterFirstEdit.some(({ allocations }) => allocations.length > 0),
      `${creator} first native edit did not allocate IDs`);

    const rating = creator === "javascript" ? 31 : 32;
    const editStages = [];
    await adapters.upstream.set(["title"], `${creator}-upstream`);
    await adapters.erlang.set(["rating"], rating);
    const allAuthors = await settle(adapters);
    assertCheckpointTree(allAuthors, matrixTree({
      title: `${creator}-upstream`, enabled: false, rating,
    }), "all authors");
    editStages.push({ name: "all-authors", checkpoint: allAuthors });
    await adapters.javascript.set(["note"], `${creator}-optional`);
    const optionalSet = await settle(adapters);
    assertCheckpointTree(optionalSet, matrixTree({
      title: `${creator}-upstream`,
      enabled: false,
      rating,
      note: `${creator}-optional`,
    }), "optional set");
    editStages.push({ name: "optional-set", checkpoint: optionalSet });
    await adapters.upstream.clear(["note"]);
    const cleared = await settle(adapters);
    assertCheckpointTree(cleared, matrixTree({
      title: `${creator}-upstream`, enabled: false, rating,
    }), "optional clear");
    editStages.push({ name: "optional-clear", checkpoint: cleared });
    await adapters.erlang.set(["point", "x"], 8);
    const nested = await settle(adapters);
    assertCheckpointTree(nested, matrixTree({
      title: `${creator}-upstream`,
      enabled: false,
      rating,
      point: { x: 8, y: -4 },
    }), "nested edit");
    editStages.push({ name: "nested-edit", checkpoint: nested });
    await adapters.javascript.set(["point"], { x: 13, y: 21 });
    const replaced = await settle(adapters);
    assertCheckpointTree(replaced, matrixTree({
      title: `${creator}-upstream`,
      enabled: false,
      rating,
      point: { x: 13, y: 21 },
    }), "parent replacement");
    editStages.push({ name: "parent-replacement", checkpoint: replaced });
    await adapters.javascript.holdOutbound();
    await adapters.erlang.holdOutbound();
    await adapters.javascript.set(["title"], `${creator}-javascript-conflict`);
    await adapters.erlang.set(["title"], `${creator}-erlang-conflict`);
    await adapters.javascript.releaseOutbound();
    await adapters.erlang.releaseOutbound();
    const continued = await settle(adapters);
    const conflictWinner = stringField(continued.observations[0].wholeTree, "title");
    assert([
      `${creator}-javascript-conflict`,
      `${creator}-erlang-conflict`,
    ].includes(conflictWinner), `${creator} conflict produced another winner`);
    assertCheckpointTree(continued, matrixTree({
      title: conflictWinner,
      enabled: false,
      rating,
      point: { x: 13, y: 21 },
    }), "conflict");
    editStages.push({ name: "conflict", checkpoint: continued });
    const continuationHistory = await serverHistory(upstreamSession);
    const continuationSubmissions = decodeTreeSubmissions(continuationHistory);

    const continuationPaths = {};
    for (const observation of continued.observations) {
      continuationPaths[observation.implementation] = await writeRunArtifact(
        context.runDirectory,
        `${creator}/${observation.implementation}/continuation.json`,
        {
          formatVersion: 1,
          kind: "continuation",
          runId: context.runId,
          profileDigest: context.profileDigest,
          creator,
          reader: observation.implementation,
          documentId,
          observation,
          conflictWinner,
          stages: editStages.map(({ name, checkpoint }) => ({
            name,
            observation: checkpoint.observations.find((item) =>
              item.implementation === observation.implementation),
          })),
          firstEditAllocations: historyAfterFirstEdit,
          serviceHistory: continuationHistory,
          treeSubmissions: continuationSubmissions,
        },
      );
    }

    const writer = creator;
    const nativeSummaryReferenceSequenceNumber =
      continued.observations[0].sequenceNumber;
    const version = await adapters[writer].summarize();
    assert.equal(typeof version, "string", `${writer} returned no summary version`);
    const tailAuthor = writer === "javascript" ? "erlang" : "javascript";
    await adapters[tailAuthor].set(["note"], `${creator}-after-native-summary`);
    const afterTail = await settle(adapters);
    const expectedReload = matrixTree({
      title: conflictWinner,
      enabled: false,
      rating,
      note: `${creator}-after-native-summary`,
      point: { x: 13, y: 21 },
    });
    assertCheckpointTree(afterTail, expectedReload, "native summary tail");
    const afterTailHistory = await serverHistory(upstreamSession);
    const tailSubmission = decodeTreeSubmissions(afterTailHistory).find(
      ({ outerSequenceNumber, clientId }) =>
        outerSequenceNumber > nativeSummaryReferenceSequenceNumber
        && adapters[tailAuthor].clientIds.has(clientId),
    );
    assert(tailSubmission, `${creator} has no sequenced tree tail after native summary`);
    const tailSequenceNumber = tailSubmission.outerSequenceNumber;
    const reloadPaths = {};
    for (const reader of creationReaders) {
      const reloaded = await freshReload(
        config,
        context,
        documentId,
        reader,
        jwt,
        expectedReload,
      );
      assert(JSON.stringify(reloaded.selectedSummaryRequests).includes(version),
        `${creator}:${reader} did not select the native summary`);
      reloadPaths[reader] = await writeRunArtifact(
        context.runDirectory,
        `${creator}/${reader}/summary-reload.json`,
        {
          formatVersion: 1,
          kind: "summary-reload",
          runId: context.runId,
          profileDigest: context.profileDigest,
          creator,
          reader,
          documentId,
          version,
          tailAuthor,
          nativeSummaryReferenceSequenceNumber,
          tailSequenceNumber,
          tailSubmission,
          expectedTree: expectedReload,
          reloaded,
        },
      );
    }

    const upstreamSummary = await publishUpstreamSummary(
      config,
      containers,
      documentId,
      `Native creation continuation ${creator}`,
    );
    await adapters.upstream.set(["title"], `${creator}-after-upstream-summary`);
    const upstreamContinuation = await settle(adapters);
    const expectedUpstreamContinuation = matrixTree({
      title: `${creator}-after-upstream-summary`,
      enabled: false,
      rating,
      note: `${creator}-after-native-summary`,
      point: { x: 13, y: 21 },
    });
    assertCheckpointTree(
      upstreamContinuation,
      expectedUpstreamContinuation,
      "upstream summary continuation",
    );
    const upstreamContinuationPaths = {};
    for (const observation of upstreamContinuation.observations) {
      upstreamContinuationPaths[observation.implementation] =
        await writeRunArtifact(
          context.runDirectory,
          `${creator}/${observation.implementation}/upstream-summary-continuation.json`,
          {
            formatVersion: 1,
            kind: "upstream-summary-continuation",
            runId: context.runId,
            profileDigest: context.profileDigest,
            creator,
            reader: observation.implementation,
            documentId,
            upstreamSummary,
            observation,
          },
        );
    }

    return creationReaders.map((reader) => ({
      creator,
      reader,
      runId: context.runId,
      profileDigest: context.profileDigest,
      documentId,
      nativeCreated: true,
      loadedInitialSummary: true,
      continuedEditing: true,
      peerObservedEdit: true,
      reloadedSummaryAndTail: true,
      evidence: {
        creation: creationPath,
        initialLoad: initialPaths[reader],
        continuation: continuationPaths[reader],
        summaryReload: reloadPaths[reader],
        upstreamContinuation: upstreamContinuationPaths[reader],
      },
    }));
  } catch (error) {
    scenarioError = error;
    throw error;
  } finally {
    await cleanupScenario(natives, containers, scenarioError);
  }
}

export async function runCreationInterop(config, {
  outputDirectory = resolve(repository, "tools/shared-tree-oracle/.output/creation"),
} = {}) {
  const runId = randomUUID();
  const runDirectory = resolve(outputDirectory, runId);
  const profileBytes = await readFile(resolve(
    repository,
    "test/fixtures/shared_tree/profile.json",
  ));
  const profileDigest = createHash("sha256").update(profileBytes).digest("hex");
  const schema = await creationSchema();
  const root = creationInput();
  await mkdir(runDirectory, { recursive: true });
  await execute("gleam", ["build", "--target", "javascript"], {
    cwd: repository,
    timeout: 30 * 60_000,
  });
  await execute("gleam", ["build", "--target", "erlang"], {
    cwd: repository,
    timeout: 30 * 60_000,
  });

  const invalidInitializers = {};
  for (const target of creationTargets) {
    invalidInitializers[target] = await rejectInvalidInitializer(target, schema, root);
  }
  await writeRunArtifact(runDirectory, "invalid-initializers.json", invalidInitializers);

  const context = { runId, runDirectory, profileDigest, viewSchema: schema };
  const cells = [];
  for (const creator of creationTargets) {
    cells.push(...await runCreatorMatrix(config, context, creator, schema, root));
  }
  const report = {
    formatVersion: 1,
    runId,
    profileDigest,
    service: {
      implementation: "floodgate",
      revision: config.revision,
      simulated: false,
    },
    cells,
    skipped: [],
    divergences: [],
  };
  await validateCreationInteropEvidence(report, runDirectory);
  const reportPath = resolve(runDirectory, "report.json");
  await writeFile(reportPath, json(report), { mode: 0o600 });
  console.log(JSON.stringify({ runId, report: reportPath }));
  return report;
}

export async function runCreationInteropCommand(args, {
  cwd = process.cwd(),
  environment = process.env,
  runInterop = runCreationInterop,
  withLocalFloodgate: runWithLocalFloodgate = withLocalFloodgate,
} = {}) {
  const { values, positionals } = parseArgs({
    args,
    allowPositionals: false,
    strict: true,
    options: {
      "local-floodgate": { type: "boolean", default: false },
      output: { type: "string" },
    },
  });
  assert.deepEqual(positionals, [], "Creation interop does not accept positionals");
  const options = {
    outputDirectory: values.output === undefined
      ? resolve(repository, "tools/shared-tree-oracle/.output/creation")
      : resolve(cwd, values.output),
  };
  if (values["local-floodgate"]) {
    return runWithLocalFloodgate((config) => runInterop(config, options));
  }
  const config = serviceConfig(environment);
  assert.equal(config.revision, floodgateRevision,
    "Creation interop requires the pinned Floodgate revision");
  return runInterop(config, options);
}

export async function runCreationCommand(args, {
  capture = captureCreation,
  serviceConfig: loadServiceConfig = serviceConfig,
  withLocalFloodgate: runWithLocalFloodgate = withLocalFloodgate,
  runInterop = runCreationInterop,
} = {}) {
  const [command, ...rest] = args;
  if (command === "interop") {
    return runCreationInteropCommand(rest, {
      runInterop,
      withLocalFloodgate: runWithLocalFloodgate,
    });
  }
  const { values, positionals } = parseArgs({
    args: rest,
    allowPositionals: true,
    strict: true,
    options: {
      "local-floodgate": { type: "boolean", default: false },
      output: { type: "string", default: "tools/shared-tree-oracle/.output/creation" },
    },
  });
  assert.equal(command, "capture",
    "Usage: creation.mjs capture [--local-floodgate] [--output path]");
  assert.deepEqual(positionals, [],
    "Usage: creation.mjs capture [--local-floodgate] [--output path]");
  const captured = values["local-floodgate"]
    ? await runWithLocalFloodgate(capture)
    : await capture(loadServiceConfig());
  validateCreationCapture(captured);
  const artifact = resolve(values.output, "capture.json");
  await mkdir(dirname(artifact), { recursive: true });
  await writeFile(artifact, json(captured));
  console.log(JSON.stringify({ documentId: captured.documentId, artifact }));
  return captured;
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  runCreationCommand(process.argv.slice(2)).catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
