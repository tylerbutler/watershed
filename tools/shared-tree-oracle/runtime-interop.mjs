import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { fileURLToPath, pathToFileURL } from "node:url";
import { isDeepStrictEqual } from "node:util";
import { SummaryType } from "@fluidframework/driver-definitions/internal";
import {
  makeEnvironment, readMessages, readSnapshot,
} from "./container-corpus.mjs";
import { reference } from "./source.mjs";

const directory = dirname(fileURLToPath(import.meta.url));
const repository = resolve(directory, "../..");
const outputRoot = join(directory, ".output");
const scenarios = [
  "bootstrap-map-handle", "required-field", "optional-set",
  "optional-clear", "batched-commits",
];
const identity = {
  package: "@fluidframework/tree",
  version: reference.version,
  commit: reference.commit,
};
const object = (value) => value !== null && typeof value === "object"
  && !Array.isArray(value);

function requireValue(condition, detail) {
  if (!condition) throw new Error(`Invalid native runtime artifact: ${detail}`);
}

export function validateRuntimeArtifact(output, target, clientId) {
  requireValue(object(output) && output.target === target, `${target} target`);
  requireValue(isDeepStrictEqual(output.reference, identity), "reference");
  const value = output.artifact;
  requireValue(object(value) && value.formatVersion === 1, "formatVersion");
  requireValue(typeof value.clientId === "string" && value.clientId.length > 0
    && (clientId === undefined || value.clientId === clientId), "clientId");
  requireValue(typeof value.sessionId === "string" && value.sessionId.length > 0, "sessionId");
  requireValue(value.bootstrapPath === "/A/root" && value.treePath === "/A/_C",
    "canonical paths");
  const document = value.initialDocument;
  requireValue(object(document) && object(document.snapshot?.tree)
    && object(document.snapshot?.blobs)
    && Object.keys(document.snapshot.blobs).length > 0
    && Number.isSafeInteger(document.sequenceNumber)
    && Number.isSafeInteger(document.minimumSequenceNumber)
    && document.minimumSequenceNumber <= document.sequenceNumber
    && document.bootstrapPath === value.bootstrapPath
    && document.treePath === value.treePath, "initial document descriptor");
  requireValue(object(value.mapHeader) && object(value.mapHeader.content)
    && Array.isArray(value.mapHeader.blobs), "native SharedMap header");
  requireValue(Array.isArray(value.outbound)
    && isDeepStrictEqual(value.outbound.map(({ id }) => id), scenarios), "scenarios");
  for (const [index, operation] of value.outbound.entries()) {
    requireValue(operation.clientSequenceNumber === index + 1
      && Number.isSafeInteger(operation.referenceSequenceNumber)
      && operation.referenceSequenceNumber >= 0
      && operation.type === "op"
      && object(operation.contents), `${operation.id} outer operation`);
  }
  requireValue(object(value.root) && Array.isArray(value.treePositions)
    && Number.isSafeInteger(value.pendingCount)
    && Number.isSafeInteger(value.sequenceNumber), "observations");
  return value;
}

export function validateRuntimeResult(output, expectedRoot, expectedPositions, sequenceNumber) {
  const result = output.artifact;
  requireValue(isDeepStrictEqual(result.root, expectedRoot), "final root differs");
  requireValue(result.pendingCount === 0, "pending tree commits after own echoes");
  requireValue(isDeepStrictEqual(result.treePositions, expectedPositions),
    "tree history positions differ");
  requireValue(result.sequenceNumber === sequenceNumber, "sequence number differs");
  return result;
}

async function readArtifact(path, label) {
  let contents;
  try {
    contents = await readFile(path, "utf8");
  } catch (error) {
    throw new Error(`Missing ${label} artifact: ${path}`, { cause: error });
  }
  if (!contents.trim()) throw new Error(`Empty ${label} artifact: ${path}`);
  try {
    return JSON.parse(contents);
  } catch (error) {
    throw new Error(`Invalid ${label} artifact JSON: ${path}`, { cause: error });
  }
}

function produceTarget(target, path, inputPath) {
  execFileSync("gleam", [
    "run", "--target", target, "-m", "watershed/tree/runtime_export",
  ], {
    cwd: repository,
    env: {
      ...process.env,
      WATERSHED_TREE_RUNTIME_INPUT: inputPath,
      WATERSHED_TREE_RUNTIME_OUTPUT: path,
      WATERSHED_TREE_RUNTIME_TARGET: target,
    },
    stdio: ["ignore", "ignore", "inherit"],
    timeout: 120_000,
  });
}

async function waitFor(predicate, label) {
  const deadline = Date.now() + 30_000;
  while (!await predicate()) {
    if (Date.now() > deadline) throw new Error(`Timed out: ${label}`);
    await delay(25);
  }
}

function snapshotSummary(snapshot, node) {
  return {
    type: SummaryType.Tree,
    tree: {
      ...Object.fromEntries(Object.entries(node.blobs).map(([name, id]) => {
        assert.equal(typeof snapshot.blobs[id], "string", `Missing snapshot blob ${id}`);
        return [name, {
          type: SummaryType.Blob,
          content: Buffer.from(snapshot.blobs[id], "base64"),
        }];
      })),
      ...Object.fromEntries(Object.entries(node.trees).map(([name, child]) =>
        [name, snapshotSummary(snapshot, child)])),
    },
  };
}

export async function loadNativeMapHeader(snapshot, nativeHeader) {
  const environment = makeEnvironment();
  try {
    const documentId = `native-header-${randomUUID()}`;
    const summary = snapshotSummary(snapshot, snapshot.tree);
    const app = { type: SummaryType.Tree, tree: { ...summary.tree } };
    const protocol = app.tree[".protocol"];
    assert(protocol, "Missing snapshot protocol summary");
    delete app.tree[".protocol"];
    const map = app.tree[".channels"]?.tree.A?.tree[".channels"]?.tree.root;
    assert(map?.tree.header, "Missing SharedMap header in snapshot");
    map.tree.header = {
      type: SummaryType.Blob,
      content: JSON.stringify(nativeHeader),
    };
    const resolved = await environment.urlResolver.resolve({
      url: `http://localhost:3000/${documentId}`,
    });
    const created = await environment.documentServiceFactory.createContainer({
      type: SummaryType.Tree,
      tree: { ".protocol": protocol, ".app": app },
    }, resolved);
    created.dispose();
    const upstream = await environment.open(documentId);
    assert.deepEqual([...upstream.data.bootstrap.keys()],
      ["2", "10", "z", "01", "tree"], "Native SharedMap header property order");
    const handle = upstream.data.bootstrap.get("tree");
    assert.equal(handle?.absolutePath, "/A/_C", "Native SharedMap header handle path");
    assert.equal(await handle.get(), upstream.data.tree,
      "Native SharedMap header handle failed real DDS resolution");
    return true;
  } finally {
    await environment.close();
  }
}

async function prepareTarget(target) {
  const environment = makeEnvironment();
  let service;
  let connection;
  try {
    const documentId = `native-${target}-${randomUUID()}`;
    const writer = await environment.open(documentId, { create: true });
    const reader = await environment.open(documentId);
    const url = writer.container.resolvedUrl;
    const snapshot = await readSnapshot(environment, url);
    const attributesId = snapshot.tree.trees[".protocol"].blobs.attributes;
    const attributes = JSON.parse(Buffer.from(snapshot.blobs[attributesId], "base64"));
    service = await environment.documentServiceFactory.createDocumentService(url);
    connection = await service.connectToDeltaStream({
      mode: "write",
      details: { capabilities: { interactive: true } },
      permission: [],
      scopes: ["doc:read", "doc:write"],
      user: { id: "watershed-native", name: "watershed-native" },
    });
    const nacks = [];
    connection.on("nack", (reason) => nacks.push(reason));
    let prefix;
    await waitFor(async () => {
      if (nacks.length > 0) throw new Error(`Native operation nack: ${JSON.stringify(nacks)}`);
      prefix = (await readMessages(environment, url))
        .filter(({ sequenceNumber }) => sequenceNumber > attributes.sequenceNumber);
      return prefix.some(({ type, data }) =>
        type === "join" && JSON.parse(data).clientId === connection.clientId);
    }, `${target} native connection join`);
    assert.deepEqual(prefix.map(({ sequenceNumber }) => sequenceNumber),
      prefix.map((_, index) => attributes.sequenceNumber + index + 1),
      "Native bootstrap prefix has a gap");
    return {
      clientId: connection.clientId,
      input: {
        clientId: connection.clientId,
        sessionId: randomUUID(),
        decoderInput: {
          initialSnapshot: snapshot,
          deliveryPrefix: prefix,
          groupedWireMessages: [],
        },
        replayMessages: [],
      },
      async consume(artifact) {
        await loadNativeMapHeader(snapshot, artifact.mapHeader);
        const mapEvents = [];
        reader.data.bootstrap.on("valueChanged", (change, local) => {
          mapEvents.push({ key: change.key, local });
        });
        const expectedStages = [
          { title: "", enabled: false, rating: 0, note: undefined },
          { title: "native-required", enabled: false, rating: 0, note: undefined },
          { title: "native-required", enabled: false, rating: 0, note: "native-note" },
          { title: "native-required", enabled: false, rating: 0, note: undefined },
          { title: "native-batched", enabled: true, rating: 3, note: undefined },
        ];
        for (const [index, operation] of artifact.outbound.entries()) {
          connection.submit([{
            clientSequenceNumber: operation.clientSequenceNumber,
            referenceSequenceNumber: operation.referenceSequenceNumber,
            type: operation.type,
            contents: JSON.stringify(operation.contents),
            metadata: operation.metadata ?? undefined,
          }]);
          await waitFor(async () => {
            if (nacks.length > 0) throw new Error(`Native operation nack: ${JSON.stringify(nacks)}`);
            assert(!reader.container.closed, "Upstream consumer closed while reading native edits");
            const messages = await readMessages(environment, url);
            const sequenced = messages.some((message) =>
              message.clientId === connection.clientId
              && message.clientSequenceNumber === operation.clientSequenceNumber);
            const root = reader.data.view.root;
            const expected = expectedStages[index];
            return sequenced && root.title === expected.title
              && root.enabled === expected.enabled && root.rating === expected.rating
              && root.note === expected.note;
          }, `${target} upstream ${operation.id}`);
        }
        assert.deepEqual(mapEvents, [{ key: "tree", local: false }],
          "Upstream SharedMap did not apply the native handle set");
        const handle = reader.data.bootstrap.get("tree");
        assert.equal(await handle.get(), reader.data.tree, "Native SharedMap handle was not loaded");
        reader.data.view.root.point.x = 42;
        await waitFor(async () => {
          if (nacks.length > 0) throw new Error(`Native operation nack: ${JSON.stringify(nacks)}`);
          const messages = await readMessages(environment, url);
          return messages.some((message) =>
            message.clientId === reader.container.clientId
              && message.sequenceNumber > prefix.at(-1).sequenceNumber
              && JSON.stringify(message.contents).includes("changeset"));
        }, `${target} upstream continuation`);
        const messages = await readMessages(environment, url);
        const replayMessages = messages.filter(({ sequenceNumber }) =>
          sequenceNumber > prefix.at(-1).sequenceNumber);
        const own = replayMessages.filter(({ clientId, type }) =>
          clientId === connection.clientId && type === "op");
        assert.deepEqual(own.map(({ clientSequenceNumber }) => clientSequenceNumber),
          [1, 2, 3, 4, 5], "Native outbound did not sequence as five outer operations");
        for (const [index, message] of own.entries()) {
          const outbound = artifact.outbound[index];
          assert.equal(message.referenceSequenceNumber, outbound.referenceSequenceNumber,
            `${outbound.id}: outer reference identity changed`);
          assert.deepEqual(typeof message.contents === "string"
            ? JSON.parse(message.contents) : message.contents, outbound.contents,
          `${outbound.id}: native container contents changed`);
          assert.deepEqual(message.metadata ?? null, outbound.metadata,
            `${outbound.id}: native outer metadata changed`);
        }
        const continuation = replayMessages.filter(({ clientId, type, contents }) =>
          clientId === reader.container.clientId && type === "op"
            && JSON.stringify(contents).includes("changeset"));
        assert.equal(continuation.length, 1, "Expected one upstream continuation edit");
        const positions = [
          ...own.slice(1).flatMap((message, index) =>
            Array.from({ length: index === 3 ? 3 : 1 }, (_, indexInBatch) =>
              ({ sequenceNumber: message.sequenceNumber, indexInBatch }))),
          { sequenceNumber: continuation[0].sequenceNumber, indexInBatch: 0 },
        ];
        return {
          root: {
            title: reader.data.view.root.title,
            enabled: reader.data.view.root.enabled,
            rating: reader.data.view.root.rating,
            marker: reader.data.view.root.marker,
            point: { x: reader.data.view.root.point.x, y: reader.data.view.root.point.y },
          },
          treePositions: positions,
          sequenceNumber: replayMessages.at(-1).sequenceNumber,
          replayMessages,
        };
      },
      async close() {
        connection.dispose();
        service.dispose();
        await environment.close();
      },
    };
  } catch (error) {
    connection?.dispose();
    service?.dispose();
    await environment.close();
    throw error;
  }
}

export async function runRuntimeInterop({
  outputRoot: root = outputRoot,
  prepare = prepareTarget,
  produce = produceTarget,
  consume,
} = {}) {
  await mkdir(root, { recursive: true });
  const temporary = await mkdtemp(join(resolve(root), "runtime-interop-"));
  try {
    const results = [];
    for (const target of ["erlang", "javascript"]) {
      const context = await prepare(target);
      try {
        const inputPath = join(temporary, `${target}-input.json`);
        await writeFile(inputPath, JSON.stringify(context.input));
        const output = join(temporary, `${target}.json`);
        await produce(target, output, inputPath);
        const initial = await readArtifact(output, `${target} initial`);
        const outbound = validateRuntimeArtifact(initial, target, context.clientId);
        requireValue(outbound.pendingCount === 6
          && outbound.treePositions.length === 0
          && isDeepStrictEqual(outbound.root, {
            title: "native-batched", enabled: true, rating: 3, marker: null,
            point: { x: 0, y: 0 },
          }), `${target} native optimistic tree state`);
        if (context.input.sessionId) {
          requireValue(outbound.sessionId === context.input.sessionId,
            `${target} stale compressor session`);
        }
        if (context.input.decoderInput) {
          requireValue(isDeepStrictEqual(outbound.initialDocument.snapshot,
            JSON.parse(JSON.stringify(context.input.decoderInput.initialSnapshot))),
          `${target} stale initial document`);
          requireValue(outbound.sequenceNumber ===
            (context.input.decoderInput.deliveryPrefix.at(-1)?.sequenceNumber
              ?? outbound.initialDocument.sequenceNumber),
          `${target} native bootstrap sequence point`);
        }
        const observed = await (consume ?? context.consume)(outbound);
        const replayPath = join(temporary, `${target}-replay.json`);
        await writeFile(inputPath, JSON.stringify({
          ...context.input, replayMessages: observed.replayMessages ?? [],
        }));
        await produce(target, replayPath, inputPath);
        const replay = await readArtifact(replayPath, `${target} replay`);
        const final = validateRuntimeArtifact(replay, target, context.clientId);
        requireValue(isDeepStrictEqual(final.outbound, outbound.outbound),
          `${target} stale or changed native outbound`);
        validateRuntimeResult(replay, observed.root, observed.treePositions,
          observed.sequenceNumber);
        results.push({ target, scenarioCount: final.outbound.length });
      } finally {
        await context.close?.();
      }
    }
    return { targetCount: results.length, scenarios: scenarios.length };
  } finally {
    await rm(temporary, { recursive: true, force: true });
  }
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  runRuntimeInterop()
    .then((result) => {
      console.log(`SharedTree runtime interoperability passed: ${result.targetCount} targets, `
        + `${result.scenarios} native scenarios each`);
    })
    .catch((error) => {
      console.error(error);
      process.exitCode = 1;
    });
}
