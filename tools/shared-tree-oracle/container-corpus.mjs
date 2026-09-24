import assert from "node:assert/strict";
import { once } from "node:events";
import { mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { ConnectionState, LoaderHeader } from "@fluidframework/container-definitions/internal";
import {
  createDetachedContainer,
  loadExistingContainer,
} from "@fluidframework/container-loader/internal";
import { ContainerRuntime } from "@fluidframework/container-runtime/internal";
import { DriverHeader } from "@fluidframework/driver-definitions/internal";
import {
  createLocalResolverCreateNewRequest,
  LocalDocumentServiceFactory,
  LocalResolver,
} from "@fluidframework/local-driver/internal";
import { makeCodeLoader, rootDataStoreId } from "@fluidframework/runtime-utils/internal";
import { LocalDeltaConnectionServer } from "@fluidframework/server-local-server";
import { Tree } from "@fluidframework/tree/internal";
import {
  oldestSupportedClient,
  runtimeOptions,
  serviceStore,
  summarizerRuntimeOptions,
} from "./service.mjs";
import { reference } from "./source.mjs";
import { captureContainerFoundations } from "./container-foundations.mjs";
import { captureSummaryFoundations } from "./summary-foundations.mjs";

const identity = {
  package: "@fluidframework/tree",
  version: reference.version,
  commit: reference.commit,
};

function json(value) {
  return `${JSON.stringify(value, (_key, item) => {
    if (item === Infinity) return "Infinity";
    if (typeof item === "bigint") return { encoding: "decimal", content: item.toString() };
    if (item instanceof Uint8Array) {
      return { encoding: "base64", content: Buffer.from(item).toString("base64") };
    }
    return item;
  }, 2)}\n`;
}

async function waitFor(predicate, stage, milliseconds = 30_000) {
  return new Promise((resolve, reject) => {
    let done = false;
    const timer = setTimeout(() => {
      done = true;
      reject(new Error(`Timed out: ${stage}`));
    }, milliseconds);
    async function poll() {
      if (done) return;
      try {
        if (await predicate()) {
          done = true;
          clearTimeout(timer);
          resolve();
        } else {
          setTimeout(poll, 0);
        }
      } catch (error) {
        done = true;
        clearTimeout(timer);
        reject(error);
      }
    }
    poll();
  });
}

async function within(promise, stage, milliseconds = 30_000) {
  let timer;
  try {
    return await Promise.race([
      promise,
      new Promise((_resolve, reject) => {
        timer = setTimeout(() => reject(new Error(`Timed out: ${stage}`)), milliseconds);
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}

function rootState(session) {
  const { root } = session.data.view;
  return {
    title: root.title,
    enabled: root.enabled,
    rating: root.rating,
    marker: root.marker,
    note: root.note,
    point: { x: root.point.x, y: root.point.y },
  };
}

function pendingTreeCommits(session) {
  const kernel = Reflect.get(session.data.tree, "kernel");
  assert(kernel && typeof kernel === "object", "Missing pinned SharedTree kernel");
  const manager = Reflect.get(kernel, "editManager");
  assert.equal(manager?.constructor.name, "EditManager", "Unexpected pinned edit manager");
  const commits = manager.getLocalCommits("main");
  assert(Array.isArray(commits), "Missing local tree commits");
  return commits.length;
}

function deliveryPrefix(snapshot, messages, firstSequenceNumber) {
  const attributesId = snapshot.tree.trees[".protocol"]?.blobs.attributes;
  assert.equal(typeof attributesId, "string", "Missing protocol attributes");
  const attributes = JSON.parse(Buffer.from(snapshot.blobs[attributesId], "base64"));
  const prefix = messages.filter(({ sequenceNumber }) =>
    sequenceNumber > attributes.sequenceNumber && sequenceNumber < firstSequenceNumber);
  assert.deepEqual(prefix.map(({ sequenceNumber }) => sequenceNumber),
    Array.from({ length: firstSequenceNumber - attributes.sequenceNumber - 1 },
      (_, index) => attributes.sequenceNumber + index + 1),
    "Incomplete runtime delivery prefix");
  return prefix;
}

function runtimeProfile() {
  return {
    oldestSupportedClient,
    enableRuntimeIdCompressor: runtimeOptions.enableRuntimeIdCompressor,
    compressionOptions: {
      minimumBatchSizeInBytes: "Infinity",
      compressionAlgorithm: runtimeOptions.compressionOptions.compressionAlgorithm,
    },
    opGroupingEnabled: true,
    summaryConfiguration: "dedicated-summarizer-disable-heuristics",
  };
}

function caseRecord(id, domain, schedules, observations, raw, extraInput = {}) {
  return {
    formatVersion: 1,
    reference: identity,
    id,
    domain,
    input: {
      service: "LocalDeltaConnectionServer",
      runtimeProfile: runtimeProfile(),
      schedules,
      ...extraInput,
    },
    expected: { observations },
    raw,
  };
}

export function makeEnvironment() {
  const server = LocalDeltaConnectionServer.create();
  const documentServiceFactory = new LocalDocumentServiceFactory(server);
  const urlResolver = new LocalResolver();
  const containers = new Set();

  async function open(documentId, { create = false, summarizing = false } = {}) {
    let runtime;
    const codeLoader = makeCodeLoader(
      async (type) => {
        assert.equal(type, serviceStore.type, "Unexpected data store type");
        return serviceStore;
      },
      oldestSupportedClient,
      async (parameters) => {
        const loaded = await ContainerRuntime.loadRuntime2({
          context: parameters.context,
          registry: parameters.registry,
          provideEntryPoint: parameters.provideEntryPoint,
          existing: parameters.existing,
          oldestSupportedClient: parameters.minVersionForCollab,
          runtimeOptions: summarizing ? summarizerRuntimeOptions : runtimeOptions,
        });
        runtime = loaded.runtime;
        if (!parameters.existing) {
          const store = await runtime.createDataStore(parameters.newContainerRootType);
          assert.equal(await store.trySetAlias(rootDataStoreId), "Success");
        }
        return runtime;
      },
      serviceStore,
    );
    const properties = {
      urlResolver,
      documentServiceFactory,
      codeLoader,
      configProvider: {
        getRawConfig: (name) => name === "Fluid.Container.ForceWriteConnection" ? true : undefined,
      },
    };
    const container = create
      ? await createDetachedContainer({
        ...properties,
        codeDetails: { package: "watershed-tree-oracle" },
      })
      : await loadExistingContainer({
        ...properties,
        request: {
          url: `http://localhost:3000/${documentId}`,
          headers: summarizing ? {
            [LoaderHeader.cache]: false,
            [LoaderHeader.clientDetails]: {
              capabilities: { interactive: false },
              type: "summarizer",
            },
            [DriverHeader.summarizingClient]: true,
          } : {},
        },
      });
    containers.add(container);
    const data = await container.getEntryPoint();
    if (create) {
      await container.attach(createLocalResolverCreateNewRequest(documentId));
    }
    await waitFor(() => {
      assert(!container.closed, "Container closed before connecting");
      return container.connectionState === ConnectionState.Connected;
    }, `${documentId} connection`);
    assert(runtime, "Container runtime was not loaded");
    return { container, data, runtime };
  }

  function dispose(session) {
    if (!session.container.closed) session.container.dispose();
    containers.delete(session.container);
  }

  async function close() {
    for (const container of containers) container.dispose();
    containers.clear();
    await server.close();
  }

  return { server, documentServiceFactory, urlResolver, open, dispose, close };
}

async function synchronize(environment, sessions, stage) {
  let stablePasses = 0;
  await waitFor(async () => {
    await delay(0);
    const dirty = sessions.some(({ container }) =>
      !container.closed
      && container.connectionState !== ConnectionState.Disconnected
      && container.deltaManager.readOnlyInfo.readonly !== true
      && container.isDirty);
    const queued = sessions.some(({ container }) =>
      container.deltaManager.inbound.length > 0
      || container.deltaManager.outbound.length > 0);
    if (!dirty && !queued && !await environment.server.hasPendingWork()) {
      stablePasses += 1;
    } else {
      stablePasses = 0;
    }
    return stablePasses >= 2;
  }, stage);
}

export async function readMessages(environment, resolvedUrl) {
  const service = await environment.documentServiceFactory.createDocumentService(resolvedUrl);
  try {
    const deltaStorage = await service.connectToDeltaStorage();
    const stream = deltaStorage.fetchMessages(1, undefined);
    const messages = [];
    for (;;) {
      const chunk = await within(stream.read(), "delta storage read");
      if (chunk.done) return messages;
      messages.push(...chunk.value);
    }
  } finally {
    service.dispose();
  }
}

export async function readSnapshot(environment, resolvedUrl) {
  const service = await environment.documentServiceFactory.createDocumentService(resolvedUrl);
  try {
    const storage = await service.connectToStorage();
    const versions = await storage.getVersions(null, 1);
    const tree = await storage.getSnapshotTree();
    assert(tree, "Published snapshot is missing");
    const blobs = {};
    async function visit(node) {
      for (const id of Object.values(node.blobs)) {
        if (!(id in blobs)) {
          blobs[id] = Buffer.from(await storage.readBlob(id)).toString("base64");
        }
      }
      for (const child of Object.values(node.trees)) await visit(child);
    }
    await visit(tree);
    const snapshot = { version: versions[0], tree, blobs, blobEncoding: "base64" };
    validateContainerSnapshotProfile(snapshot);
    return snapshot;
  } finally {
    service.dispose();
  }
}

export function validateContainerSnapshotProfile(snapshot) {
  assert.equal(snapshot.blobEncoding, "base64", "snapshot blobEncoding");
  const metadataId = snapshot.tree.blobs[".metadata"];
  assert.equal(typeof metadataId, "string", "Missing .metadata blob");
  const metadataBytes = snapshot.blobs[metadataId];
  assert.equal(typeof metadataBytes, "string", "Missing .metadata blob bytes");
  const metadata = JSON.parse(Buffer.from(metadataBytes, "base64"));
  assert.equal(
    metadata.documentSchema.info.minVersionForCollab,
    oldestSupportedClient,
    "minVersionForCollab",
  );
  assert.equal(
    metadata.documentSchema.runtime.idCompressorMode,
    "on",
    "idCompressorMode",
  );
  assert.equal(
    metadata.documentSchema.runtime.opGroupingEnabled,
    true,
    "opGroupingEnabled",
  );
  assert.equal(
    metadata.documentSchema.runtime.compressionLz4,
    undefined,
    "compressionLz4",
  );
  assert.equal(metadata.summaryFormatVersion, 1, "summaryFormatVersion");
  assert.equal(metadata.gcFeature, 3, "gcFeature");

  const compressorId = snapshot.tree.blobs[".idCompressor"];
  assert.equal(typeof compressorId, "string", "Missing .idCompressor blob");
  const compressorBytes = snapshot.blobs[compressorId];
  assert.equal(typeof compressorBytes, "string", "Missing .idCompressor blob bytes");
  assert(Buffer.from(compressorBytes, "base64").length > 0, "Empty .idCompressor blob");

  const schemaTree = snapshot.tree.trees[".channels"]?.trees.A
    ?.trees[".channels"]?.trees._C
    ?.trees.indexes?.trees.Schema;
  assert(schemaTree, "Missing SharedTree indexes/Schema tree");
  const schemaId = schemaTree.blobs.SchemaString;
  assert.equal(typeof schemaId, "string", "Missing SchemaString blob");
  const schemaBytes = snapshot.blobs[schemaId];
  assert.equal(typeof schemaBytes, "string", "Missing SchemaString blob bytes");
  const schema = JSON.parse(Buffer.from(schemaBytes, "base64"));
  return { metadata, schema };
}

function snapshotPaths(tree, prefix = "") {
  const paths = [];
  for (const name of Object.keys(tree.blobs)) paths.push(`${prefix}/${name}`);
  for (const [name, child] of Object.entries(tree.trees)) {
    const childPrefix = `${prefix}/${name}`;
    paths.push(childPrefix);
    paths.push(...snapshotPaths(child, childPrefix));
  }
  return paths;
}

async function captureRaw(environment, session) {
  const [messages, snapshot] = await Promise.all([
    readMessages(environment, session.container.resolvedUrl),
    readSnapshot(environment, session.container.resolvedUrl),
  ]);
  assert(messages.length > 0, "Container history is empty");
  assert(Object.keys(snapshot.blobs).length > 0, "Container snapshot has no blobs");
  return { messages, snapshot, snapshotPaths: snapshotPaths(snapshot.tree) };
}

export async function publishSummary(environment, documentId, reason) {
  const summarizer = await environment.open(documentId, { summarizing: true });
  assert(summarizer.data.ISummarizer, "Summary entry point has no ISummarizer");
  const result = summarizer.data.ISummarizer.summarizeOnDemand({ reason, fullTree: true });
  const submitted = await within(result.summarySubmitted, `${reason} submission`);
  assert(submitted.success, `Summary submission failed: ${submitted.error?.message ?? submitted.error}`);
  const broadcast = await within(result.summaryOpBroadcasted, `${reason} broadcast`);
  assert(broadcast.success, `Summary broadcast failed: ${broadcast.error?.message ?? broadcast.error}`);
  const acknowledged = await within(result.receivedSummaryAckOrNack, `${reason} acknowledgement`);
  assert(acknowledged.success,
    `Summary acknowledgement failed: ${acknowledged.error?.message ?? acknowledged.error}`);
  return { summarizer, submitted: submitted.data, broadcast: broadcast.data, acknowledged: acknowledged.data };
}

function parseContents(contents) {
  if (typeof contents !== "string") return contents;
  try {
    return JSON.parse(contents);
  } catch {
    return contents;
  }
}

function groupedCommits(messages) {
  const groups = [];
  for (const message of messages) {
    const contents = parseContents(message.contents);
    if (contents?.type !== "groupedBatch" || !Array.isArray(contents.contents)) continue;
    groups.push({
      outerSequenceNumber: message.sequenceNumber,
      outerClientSequenceNumber: message.clientSequenceNumber,
      outerReferenceSequenceNumber: message.referenceSequenceNumber,
      commits: contents.contents.map((commit, innerPosition) => ({
        innerPosition,
        contents: commit.contents,
        metadata: commit.metadata,
      })),
    });
  }
  return groups;
}

function groupedWireMessages(messages, minimumCommits) {
  return messages.filter((message) => {
    const contents = parseContents(message.contents);
    return contents?.type === "groupedBatch"
      && Array.isArray(contents.contents)
      && contents.contents.length >= minimumCommits;
  });
}

function messagesContaining(messages, value) {
  const encoded = typeof value === "string" ? value : JSON.stringify(value);
  return messages.filter((message) => JSON.stringify(message).includes(encoded));
}

async function rejection(operation) {
  let rejected;
  try {
    await operation();
  } catch (error) {
    rejected = error;
  }
  assert(rejected instanceof Error, "Operation did not reject");
  return rejected.message;
}

async function treeFromBootstrap(bootstrap, expectedType) {
  const handle = bootstrap.get("tree");
  assert.equal(typeof handle?.get, "function", "Bootstrap tree handle is missing");
  const tree = await handle.get();
  assert.equal(tree.attributes.type, expectedType, "Bootstrap handle is not a tree");
  return tree;
}

function outerIdentity(message) {
  return {
    clientId: message.clientId,
    clientSequenceNumber: message.clientSequenceNumber,
    referenceSequenceNumber: message.referenceSequenceNumber,
    sequenceNumber: message.sequenceNumber,
    minimumSequenceNumber: message.minimumSequenceNumber,
  };
}

async function captureBootstrap(environment) {
  const documentId = "bootstrap-map-handles";
  const writer = await environment.open(documentId, { create: true });
  const reader = await environment.open(documentId);
  try {
    await synchronize(environment, [writer, reader], "bootstrap initialization");
    const mapEvents = [];
    reader.data.bootstrap.on("valueChanged", (change) => mapEvents.push(change.key));
    const initialSnapshot = await readSnapshot(environment, writer.container.resolvedUrl);
    const originalHandle = writer.data.tree.handle;
    const valid = {
      schedule: "valid-bootstrap",
      bootstrapPath: reader.data.bootstrap.handle.absolutePath,
      treePath: reader.data.tree.handle.absolutePath,
      bootstrapType: reader.data.bootstrap.attributes.type,
      treeType: reader.data.tree.attributes.type,
      handleResolvedToTree: await reader.data.bootstrap.get("tree").get() === reader.data.tree,
      root: rootState(reader),
    };

    writer.data.bootstrap.delete("tree");
    await synchronize(environment, [writer, reader], "missing bootstrap delivery");
    const missingRoot = rootState(reader);
    const missing = await rejection(() =>
      treeFromBootstrap(reader.data.bootstrap, reader.data.tree.attributes.type));
    assert.match(missing, /^Bootstrap tree handle is missing/);

    writer.data.bootstrap.set("tree", writer.data.bootstrap.handle);
    await synchronize(environment, [writer, reader], "wrong bootstrap delivery");
    const wrongRoot = rootState(reader);
    const wrongKind = await rejection(() =>
      treeFromBootstrap(reader.data.bootstrap, reader.data.tree.attributes.type));
    assert.match(wrongKind, /^Bootstrap handle is not a tree/);

    writer.data.bootstrap.set("tree", originalHandle);
    await synchronize(environment, [writer, reader], "bootstrap restoration");
    const summary = await publishSummary(environment, documentId, "bootstrap map handles");
    const raw = await captureRaw(environment, writer);
    raw.sharedMapMessages = messagesContaining(raw.messages, "tree");
    const [deleted, wrong, restored] = raw.sharedMapMessages;
    assert.deepEqual(mapEvents, ["tree", "tree", "tree"], "SharedMap invalidation order");
    raw.bootstrapRejections = { missing, wrongKind };
    raw.summary = {
      submitted: summary.submitted,
      broadcast: summary.broadcast,
      acknowledged: summary.acknowledged,
    };
    assert(raw.sharedMapMessages.length > 0, "SharedMap tree-handle operations were not captured");
    environment.dispose(summary.summarizer);

    return caseRecord(
      documentId,
      "container",
      [
        {
          id: "valid-bootstrap",
          steps: [
            { load: documentId },
            { check: "root SharedMap resolves the tree handle at its hierarchical path" },
          ],
        },
        {
          id: "missing-tree-handle",
          steps: [
            { edit: 'delete bootstrap["tree"]' },
            { deliver: "all" },
            { check: "bootstrap view rejects the missing tree handle" },
          ],
        },
        {
          id: "wrong-tree-handle-kind",
          steps: [
            { edit: 'set bootstrap["tree"] to the SharedMap handle' },
            { deliver: "all" },
            { check: "bootstrap view rejects a non-SharedTree handle" },
          ],
        },
      ],
      [
        { checkpoint: "valid-bootstrap", ...valid, pendingCount: 0, treePositions: [],
          invalidated: false },
        { checkpoint: "missing-tree-handle", rejection: "missing-tree-handle",
          root: missingRoot, pendingCount: 0, treePositions: [],
          outer: outerIdentity(deleted), invalidated: true },
        { checkpoint: "wrong-tree-handle-kind", rejection: "wrong-tree-handle-kind",
          root: wrongRoot, pendingCount: 0, treePositions: [],
          outer: outerIdentity(wrong), invalidated: true },
        { checkpoint: "restored-tree-handle", root: rootState(reader), pendingCount: 0,
          treePositions: [], outer: outerIdentity(restored), invalidated: true,
          handleResolvedToTree: true },
      ],
      raw,
      {
        decoderInput: {
          initialSnapshot,
          deliveryPrefix: deliveryPrefix(initialSnapshot, raw.messages,
            raw.sharedMapMessages[0].sequenceNumber),
          bootstrapMessages: raw.sharedMapMessages,
        },
      },
    );
  } finally {
    environment.dispose(writer);
    environment.dispose(reader);
  }
}

async function captureBatchedCommits(environment) {
  const documentId = "batched-commits";
  const writer = await environment.open(documentId, { create: true });
  const reader = await environment.open(documentId);
  try {
    await synchronize(environment, [writer, reader], "batched case initialization");
    const initialSnapshot = await readSnapshot(environment, writer.container.resolvedUrl);
    const writerInput = {
      initialClientId: writer.container.clientId,
      sessionId: writer.runtime.idCompressor.localSessionId,
      compressor: writer.runtime.idCompressor.serialize(true),
    };
    let localInvalidated = false;
    let peerInvalidated = false;
    Tree.on(writer.data.view.root, "treeChanged", () => { localInvalidated = true; });
    Tree.on(reader.data.view.root, "treeChanged", () => { peerInvalidated = true; });
    writer.runtime.orderSequentially(() => {
      writer.data.view.root.title = "batched";
      writer.data.view.root.enabled = true;
      writer.data.view.root.rating = 3;
    });
    const localCheckpoint = {
      checkpoint: "local-after-batch",
      root: rootState(writer),
      pendingCount: pendingTreeCommits(writer),
    };
    await synchronize(environment, [writer, reader], "batched commits delivery");
    const peerCheckpoint = {
      checkpoint: "peer-after-delivery",
      root: rootState(reader),
      pendingCount: pendingTreeCommits(reader),
    };
    const summary = await publishSummary(environment, documentId, "batched commits");
    const raw = await captureRaw(environment, writer);
    raw.groupedCommits = groupedCommits(raw.messages).filter(({ commits }) => commits.length >= 3);
    const groupedMessages = groupedWireMessages(raw.messages, 3);
    const outer = outerIdentity(groupedMessages[0]);
    writerInput.clientId = writer.container.clientId;
    const treePositions = [0, 1, 2].map((indexInBatch) =>
      ({ sequenceNumber: outer.sequenceNumber, indexInBatch }));
    localCheckpoint.invalidated = localInvalidated;
    localCheckpoint.outer = {
      clientId: writerInput.clientId,
      clientSequenceNumber: outer.clientSequenceNumber,
      referenceSequenceNumber: outer.referenceSequenceNumber,
    };
    localCheckpoint.treePositions = [];
    peerCheckpoint.invalidated = peerInvalidated;
    peerCheckpoint.outer = outer;
    peerCheckpoint.treePositions = treePositions;
    assert.equal(groupedMessages.length, 1, "Expected one runtime batch");
    assert.equal(groupedMessages[0].clientId, writerInput.clientId,
      "Runtime batch author differs from connected writer");
    raw.summary = {
      submitted: summary.submitted,
      broadcast: summary.broadcast,
      acknowledged: summary.acknowledged,
    };
    assert(raw.groupedCommits.length > 0, "No grouped batch with three inner commits was captured");
    environment.dispose(summary.summarizer);

    return caseRecord(
      documentId,
      "runtime",
      [{
        id: "three-tree-commits-one-runtime-batch",
        steps: [
          { edit: "set title, enabled, and rating inside runtime.orderSequentially" },
          { deliver: "one grouped outer operation" },
          { check: "record outer sequence number and each inner position" },
        ],
      }],
      [
        localCheckpoint,
        peerCheckpoint,
      ],
      raw,
      {
        writer: writerInput,
        localEdits: [
          { path: ["title"], value: { kind: "string", value: "batched" } },
          { path: ["enabled"], value: { kind: "boolean", value: true } },
          { path: ["rating"], value: { kind: "number", value: 3 } },
        ],
        decoderInput: {
          initialSnapshot,
          deliveryPrefix: deliveryPrefix(initialSnapshot, raw.messages,
            groupedMessages[0].sequenceNumber),
          groupedWireMessages: groupedMessages,
        },
      },
    );
  } finally {
    environment.dispose(writer);
    environment.dispose(reader);
  }

}

async function captureReconnect(environment) {
  const documentId = "reconnect-before-ack";
  const writer = await environment.open(documentId, { create: true });
  const reader = await environment.open(documentId);
  try {
    await synchronize(environment, [writer, reader], "reconnect case initialization");
    const initialSnapshot = await readSnapshot(environment, writer.container.resolvedUrl);

    const acceptedClientId = writer.container.clientId;
    assert(acceptedClientId, "Writer has no client id");
    const beforeAcceptedEdit = await readMessages(environment, writer.container.resolvedUrl);
    const beforeAcceptedSequence = beforeAcceptedEdit.at(-1)?.sequenceNumber ?? 0;
    await writer.container.deltaManager.outbound.pause();
    writer.data.view.root.title = "accepted-before-ack";
    await waitFor(() => writer.container.deltaManager.outbound.length > 0,
      "accepted-before-ack outbound queue");
    await writer.container.deltaManager.inbound.pause();
    writer.container.deltaManager.outbound.resume();
    await waitFor(() => reader.data.view.root.title === "accepted-before-ack",
      "peer observation before writer ack");
    assert(writer.container.isDirty, "Writer observed its ack before the forced disconnect");
    const acceptedHistory = await readMessages(environment, writer.container.resolvedUrl);
    const acceptedMessages = acceptedHistory.filter((message) =>
      message.sequenceNumber > beforeAcceptedSequence && message.type === "op");
    assert(acceptedMessages.length > 0, "Server did not accept the first reconnect edit");
    const acceptedPendingLocalState = await writer.container.getPendingLocalState();
    const acceptedConnectionId = acceptedMessages.at(-1).clientId;
    assert(acceptedConnectionId, "Accepted edit has no connection client id");

    const serverDisconnect = once(writer.container, "disconnected");
    environment.documentServiceFactory.disconnectClient(
      acceptedConnectionId,
      "accepted before local ack",
    );
    await within(serverDisconnect, "server-accepted disconnect");
    writer.container.deltaManager.inbound.resume();
    await waitFor(() => writer.container.connectionState === ConnectionState.Connected,
      "server-accepted reconnect");
    await synchronize(environment, [writer, reader], "server-accepted reconciliation");
    const acceptedRoot = rootState(reader);

    await writer.container.deltaManager.outbound.pause();
    const beforeQueuedEdit = await readMessages(environment, writer.container.resolvedUrl);
    writer.data.view.root.note = "never-submitted-before-reconnect";
    await waitFor(() => writer.container.deltaManager.outbound.length > 0,
      "never-submitted outbound queue");
    const queuedOutboundMessages = writer.container.deltaManager.outbound.length;
    const neverSubmittedPendingLocalState = await writer.container.getPendingLocalState();
    const whileQueued = await readMessages(environment, writer.container.resolvedUrl);
    assert.equal(whileQueued.length, beforeQueuedEdit.length,
      "The never-submitted edit reached the server before reconnect");

    const localDisconnect = once(writer.container, "disconnected");
    writer.container.disconnect();
    await within(localDisconnect, "never-submitted disconnect");
    writer.container.connect();
    await waitFor(() => writer.container.connectionState === ConnectionState.Connected,
      "never-submitted reconnect");
    writer.container.deltaManager.outbound.resume();
    await synchronize(environment, [writer, reader], "never-submitted resubmission");
    const resubmittedHistory = await readMessages(environment, writer.container.resolvedUrl);
    const queuedSequence = whileQueued.at(-1)?.sequenceNumber ?? 0;
    const neverSubmittedMessages = resubmittedHistory.filter(
      ({ sequenceNumber, type }) => sequenceNumber > queuedSequence && type === "op",
    );
    assert(neverSubmittedMessages.length > 0, "The queued edit was not resubmitted after reconnect");

    const summary = await publishSummary(environment, documentId, "reconnect before ack");
    const raw = await captureRaw(environment, writer);
    raw.acceptedBeforeAckMessages = acceptedMessages;
    raw.acceptedBeforeAckClientIds = {
      containerClientId: acceptedClientId,
      sequencedMessageClientId: acceptedConnectionId,
    };
    raw.neverSubmitted = {
      messagesBeforeEdit: beforeQueuedEdit.length,
      messagesWhileQueued: whileQueued.length,
      outboundQueueLength: queuedOutboundMessages,
      submittedBeforeReconnect: false,
      messagesAfterReconnect: neverSubmittedMessages,
    };
    raw.summary = {
      submitted: summary.submitted,
      broadcast: summary.broadcast,
      acknowledged: summary.acknowledged,
    };
    environment.dispose(summary.summarizer);

    return caseRecord(
      documentId,
      "history",
      [
        {
          id: "server-accepted-before-ack",
          steps: [
            { edit: "set title while writer inbound is paused" },
            { deliver: "server and peer only" },
            { disconnect: "writer before its ack is processed" },
            { reconnect: "writer with the accepted commit still pending locally" },
            { check: "accepted commit reconciles without duplication" },
          ],
        },
        {
          id: "never-submitted-before-reconnect",
          steps: [
            { edit: "set note while writer outbound is paused" },
            { check: "delta storage does not contain the edit" },
            { disconnect: "writer before outbound submission" },
            { reconnect: "writer and resume outbound processing" },
            { deliver: "resubmitted commit" },
            { check: "both clients observe the edit" },
          ],
        },
      ],
      [
        {
          checkpoint: "server-accepted-before-ack",
          status: "accepted-before-ack",
          serverAccepted: true,
          writerObservedAckBeforeDisconnect: false,
          root: acceptedRoot,
        },
        {
          checkpoint: "never-submitted-before-reconnect",
          status: "never-submitted",
          serverAcceptedBeforeReconnect: false,
          root: rootState(reader),
        },
      ],
      raw,
      {
        replayInput: {
          initialSnapshot,
          acceptedBeforeAck: {
            pendingLocalState: {
              encoding: "utf8",
              content: acceptedPendingLocalState,
            },
            sequencedMessages: acceptedMessages,
          },
          neverSubmitted: {
            pendingLocalState: {
              encoding: "utf8",
              content: neverSubmittedPendingLocalState,
            },
            sequencedMessagesAfterReconnect: neverSubmittedMessages,
          },
        },
      },
    );
  } finally {
    if (writer.container.deltaManager.inbound.paused) writer.container.deltaManager.inbound.resume();
    if (writer.container.deltaManager.outbound.paused) writer.container.deltaManager.outbound.resume();
    environment.dispose(writer);
    environment.dispose(reader);
  }
}

async function captureSummaryTail(environment) {
  const documentId = "summary-tail";
  const editor = await environment.open(documentId, { create: true });
  const peer = await environment.open(documentId);
  const summarizer = await environment.open(documentId, { summarizing: true });
  let firstReload;
  let laterReload;
  try {
    editor.data.view.root.title = "state-at-s";
    await synchronize(environment, [editor, peer], "summary-tail initialization");
    const stateAtS = rootState(editor);
    assert(summarizer.data.ISummarizer, "Summary entry point has no ISummarizer");
    await summarizer.container.deltaManager.outbound.pause();
    const result = summarizer.data.ISummarizer.summarizeOnDemand({
      reason: "summary tail with data before publication",
      fullTree: true,
    });
    const submitted = await within(result.summarySubmitted, "summary-tail submission");
    assert(submitted.success,
      `Summary submission failed: ${submitted.error?.message ?? submitted.error}`);
    assert(summarizer.container.deltaManager.outbound.length > 0,
      "Summary operation was not held before publication");
    const referenceSequenceNumber = submitted.data.referenceSequenceNumber;

    editor.data.view.root.title = "edit-between-s-and-p";
    await synchronize(environment, [editor, peer], "data edit between S and P");
    assert.equal(peer.data.view.root.title, "edit-between-s-and-p");
    const messagesBeforePublication = await readMessages(
      environment,
      editor.container.resolvedUrl,
    );
    const dataEditSequenceNumbers = new Set(messagesBeforePublication
      .filter(({ sequenceNumber, type }) =>
        sequenceNumber > referenceSequenceNumber && type === "op")
      .map(({ sequenceNumber }) => sequenceNumber));
    assert(dataEditSequenceNumbers.size > 0,
      "The edit after S did not reach the service before publication");

    summarizer.container.deltaManager.outbound.resume();
    const broadcast = await within(result.summaryOpBroadcasted, "summary-tail broadcast");
    assert(broadcast.success,
      `Summary broadcast failed: ${broadcast.error?.message ?? broadcast.error}`);
    const acknowledged = await within(
      result.receivedSummaryAckOrNack,
      "summary-tail acknowledgement",
    );
    assert(acknowledged.success,
      `Summary acknowledgement failed: ${acknowledged.error?.message ?? acknowledged.error}`);
    const publicationSequenceNumber = acknowledged.data.summaryAckOp.sequenceNumber;
    assert(referenceSequenceNumber < publicationSequenceNumber,
      "Summary publication did not advance beyond its reference sequence");

    const messagesAtPublication = await readMessages(environment, editor.container.resolvedUrl);
    const interval = messagesAtPublication
      .filter(({ sequenceNumber }) =>
        sequenceNumber > referenceSequenceNumber
        && sequenceNumber <= publicationSequenceNumber)
      .map((message) => ({
        dataEdit: dataEditSequenceNumbers.has(message.sequenceNumber),
        message,
      }));
    assert(interval.some(({ dataEdit }) => dataEdit),
      "No data edit was sequenced between summary reference and publication");
    const snapshotAtS = await readSnapshot(environment, editor.container.resolvedUrl);

    environment.dispose(summarizer);
    firstReload = await environment.open(documentId);
    assert.equal(firstReload.data.view.root.title, "edit-between-s-and-p");
    const replayedAtPublication = rootState(firstReload);

    firstReload.data.view.root.point.y = 21;
    await synchronize(environment, [editor, peer, firstReload], "later summary tail edit");
    environment.dispose(firstReload);
    firstReload = undefined;

    laterReload = await environment.open(documentId);
    assert.equal(laterReload.data.view.root.title, "edit-between-s-and-p");
    assert.equal(laterReload.data.view.root.point.y, 21);
    const raw = await captureRaw(environment, laterReload);
    raw.summary = {
      referenceSequenceNumber,
      submitted: submitted.data,
    };
    raw.publication = {
      sequenceNumber: publicationSequenceNumber,
      broadcast: broadcast.data,
      acknowledged: acknowledged.data,
    };
    raw.summaryToPublicationMessages = interval;
    raw.laterTailMessages = raw.messages.filter(
      ({ sequenceNumber }) => sequenceNumber > publicationSequenceNumber,
    );

    return caseRecord(
      documentId,
      "summary",
      [{
        id: "data-edit-between-summary-and-publication",
        steps: [
          { summarize: "capture snapshot at S while summarizer outbound is paused" },
          { edit: "set title after S" },
          { deliver: "data edit to the server before the summary operation" },
          { summarize: "resume summary publication at P" },
          { load: "fresh upstream reader from the published summary and replay S..P" },
          { check: "reader observes the between-S-and-P edit" },
          { edit: "set point.y after publication" },
          { deliver: "later tail" },
          { load: "second fresh upstream reader" },
          { check: "reader observes the replayed edit and later tail" },
        ],
      }],
      [
        {
          checkpoint: "summary-captured",
          sequenceNumber: referenceSequenceNumber,
          root: stateAtS,
        },
        {
          checkpoint: "replayed-through-publication",
          sequenceNumber: publicationSequenceNumber,
          replayedSequenceNumbers: interval.map(({ message }) => message.sequenceNumber),
          root: replayedAtPublication,
        },
        {
          checkpoint: "later-edit-after-reload",
          root: rootState(laterReload),
        },
      ],
      raw,
      {
        replayInput: {
          snapshotAtS,
          summaryReferenceSequenceNumber: referenceSequenceNumber,
          publicationSequenceNumber,
          summaryToPublicationMessages: interval.map(({ message }) => message),
          laterTailMessages: raw.laterTailMessages,
        },
      },
    );
  } finally {
    if (summarizer.container.deltaManager.outbound.paused) {
      summarizer.container.deltaManager.outbound.resume();
    }
    environment.dispose(editor);
    environment.dispose(peer);
    if (!summarizer.container.closed) environment.dispose(summarizer);
    if (firstReload !== undefined) environment.dispose(firstReload);
    if (laterReload !== undefined) environment.dispose(laterReload);
  }
}

async function capturePersistenceStates(environment) {
  const documentId = "summary-persistence";
  const writer = await environment.open(documentId, { create: true });
  const peer = await environment.open(documentId);
  const states = [];
  const observations = [];
  let summarizer;
  let reader;

  async function record(id) {
    const snapshot = await readSnapshot(environment, writer.container.resolvedUrl);
    const attributes = JSON.parse(Buffer.from(
      snapshot.blobs[snapshot.tree.trees[".protocol"].blobs.attributes], "base64",
    ));
    reader = await environment.open(documentId);
    await synchronize(environment, [writer, reader], `${id} reader catch-up`);
    const before = rootState(reader);
    assert.deepEqual(before, rootState(writer), `${id}: fresh reader differs`);
    const rating = before.rating + 1;
    reader.data.view.root.rating = rating;
    await synchronize(environment, [writer, reader], `${id} continuation`);
    assert.equal(writer.data.view.root.rating, rating, `${id}: continuation was not observed`);
    const messages = await readMessages(environment, writer.container.resolvedUrl);
    states.push({
      id,
      snapshot,
      sequenceNumber: attributes.sequenceNumber,
      minimumSequenceNumber: attributes.minimumSequenceNumber,
      continuationEdit: { path: ["rating"], value: { kind: "number", value: rating } },
      tail: messages.filter(({ sequenceNumber }) => sequenceNumber > attributes.sequenceNumber),
    });
    observations.push({
      id, before, after: rootState(reader), continuationObserved: true,
    });
    environment.dispose(reader);
    reader = undefined;
  }

  try {
    await synchronize(environment, [writer, peer], "persistence initialization");
    const initial = await publishSummary(environment, documentId, "persistence empty history");
    summarizer = initial.summarizer;
    await record("initial");
    environment.dispose(summarizer);
    summarizer = undefined;
    await Promise.all([
      writer.container.deltaManager.inbound.pause(),
      peer.container.deltaManager.inbound.pause(),
    ]);
    writer.data.view.root.point = { x: 10, y: 20 };
    peer.data.view.root.point.y = 7;
    writer.container.deltaManager.inbound.resume();
    peer.container.deltaManager.inbound.resume();
    await synchronize(environment, [writer, peer], "persistence concurrent replacement");
    const first = await publishSummary(environment, documentId, "persistence retained state");
    summarizer = first.summarizer;
    await record("concurrent-detached");
    const departedPeer = peer.container.clientId;
    environment.dispose(peer);
    environment.dispose(summarizer);
    summarizer = undefined;
    await synchronize(environment, [writer], "persistence peer leave");
    writer.runtime.orderSequentially(() => {
      writer.data.view.root.title = "after-peer-leave";
      writer.data.view.root.enabled = true;
      writer.data.bootstrap.set("self", writer.data.bootstrap.handle);
    });
    await synchronize(environment, [writer], "persistence grouped metadata changes");
    const second = await publishSummary(environment, documentId, "persistence advanced state");
    summarizer = second.summarizer;
    await record("after-peer-leave");
    environment.dispose(summarizer);
    summarizer = undefined;
    await synchronize(environment, [writer], "persistence readers leave");
    for (const value of [1, 2]) {
      writer.data.bootstrap.set("historyFence", value);
      await synchronize(environment, [writer], "persistence history fence");
    }
    const third = await publishSummary(environment, documentId, "persistence non-tree tail");
    summarizer = third.summarizer;
    await record("after-nontree-tail");
    return { states, observations, departedPeer };
  } finally {
    for (const session of [reader, summarizer, peer, writer]) {
      if (session !== undefined && !session.container.closed) environment.dispose(session);
    }
  }
}

async function captureWriterMatrix(environment) {
  const documentId = "summary-writer-matrix";
  const writer = await environment.open(documentId, { create: true });
  let summarizer;
  let reader;
  let reload;
  try {
    writer.data.view.root.title = "upstream-writer";
    writer.data.view.root.point.x = 8;
    await synchronize(environment, [writer], "writer matrix initial edit");
    const published = await publishSummary(environment, documentId, "upstream writer matrix");
    summarizer = published.summarizer;
    const summary = {
      submitted: published.submitted,
      broadcast: published.broadcast,
      acknowledged: published.acknowledged,
    };
    const writerSnapshot = await readSnapshot(environment, writer.container.resolvedUrl);
    const publicationSequenceNumber = published.acknowledged.summaryAckOp.sequenceNumber;
    environment.dispose(writer);
    environment.dispose(summarizer);
    summarizer = undefined;

    reader = await environment.open(documentId);
    assert.equal(reader.data.view.root.title, "upstream-writer");
    assert.equal(reader.data.view.root.point.x, 8);
    const readerLoadedRoot = rootState(reader);
    reader.data.view.root.enabled = true;
    await synchronize(environment, [reader], "writer matrix continuation edit");
    environment.dispose(reader);
    reader = undefined;

    reload = await environment.open(documentId);
    assert.equal(reload.data.view.root.title, "upstream-writer");
    assert.equal(reload.data.view.root.point.x, 8);
    assert.equal(reload.data.view.root.enabled, true);
    const raw = await captureRaw(environment, reload);
    raw.summary = summary;
    const laterTailMessages = raw.messages.filter(
      ({ sequenceNumber }) => sequenceNumber > publicationSequenceNumber,
    );
    const persistence = await capturePersistenceStates(environment);

    return {
      ...caseRecord(
        documentId,
        "summary",
        [{
          id: "upstream-writer-upstream-reader",
          steps: [
            { edit: "upstream writer sets title and point.x" },
            { summarize: "publish upstream summary" },
            { load: "fresh upstream reader" },
            { check: "reader observes summary state" },
            { edit: "reader sets enabled" },
            { deliver: "later edit" },
            { load: "second fresh upstream reader" },
            { check: "reload observes summary state and later edit" },
          ],
        }],
        [
          {
            checkpoint: "upstream-reader-loaded-summary",
            writer: "upstream",
            reader: "upstream",
            root: readerLoadedRoot,
          },
          {
            checkpoint: "upstream-reader-reload-after-edit",
            writer: "upstream",
            reader: "upstream",
            root: rootState(reload),
          },
        ],
        raw,
        {
          nativeCells: [
            { writer: "upstream", reader: "native", status: "unimplemented" },
            { writer: "native", reader: "upstream", status: "unimplemented" },
            { writer: "native", reader: "native", status: "unimplemented" },
          ],
          upstreamWriterInput: {
            snapshot: writerSnapshot,
            publicationSequenceNumber,
            laterTailMessages,
          },
          persistenceStates: persistence.states,
          departedPeer: persistence.departedPeer,
        },
      ),
      expected: {
        persistenceObservations: persistence.observations,
        observations: [
          {
            checkpoint: "upstream-reader-loaded-summary",
            writer: "upstream",
            reader: "upstream",
            root: readerLoadedRoot,
          },
          {
            checkpoint: "upstream-reader-reload-after-edit",
            writer: "upstream",
            reader: "upstream",
            root: rootState(reload),
          },
        ],
        writerMatrix: [{
          writer: "upstream",
          reader: "upstream",
          status: "implemented",
          reloadAndEdit: true,
        }],
      },
    };
  } finally {
    if (!writer.container.closed) environment.dispose(writer);
    if (summarizer !== undefined) environment.dispose(summarizer);
    if (reader !== undefined) environment.dispose(reader);
    if (reload !== undefined) environment.dispose(reload);
  }
}

export async function captureContainers(outputDirectory) {
  const environment = makeEnvironment();
  try {
    const cases = [
      await captureBootstrap(environment),
      await captureBatchedCommits(environment),
      await captureReconnect(environment),
      await captureSummaryTail(environment),
      await captureWriterMatrix(environment),
    ];
    const foundations = [
      await captureContainerFoundations(cases),
      await captureSummaryFoundations(cases),
    ];
    cases.push(...foundations);
    await mkdir(outputDirectory, { recursive: true });
    await writeFile(join(outputDirectory, "container-cases.json"), json(cases));
    return cases;
  } finally {
    await environment.close();
  }
}
