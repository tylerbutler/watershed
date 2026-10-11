import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { readFile, mkdir, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { parseArgs } from "node:util";
import { deserializeIdCompressor } from "@fluidframework/id-compressor/internal";
import { encodeCompactIdToString } from "@fluidframework/runtime-utils/internal";
import { CommitKind, RevertibleStatus, Tree } from "@fluidframework/tree/internal";
import {
  handleGraphStore,
  handleServiceStore,
  openSession,
  oldestSupportedClient,
  serviceConfig,
  snapshot,
  tokenProvider,
  withLocalFloodgate,
} from "./service.mjs";
import {
  decodeTreeSubmissions,
  nativeAdapter,
  publishUpstreamSummary,
  serverHistory,
  success,
  until,
} from "./interop-scenarios.mjs";
import {
  handleStoredSchema,
  handleTreeConfig,
  initialHandleRoot,
} from "./schema.mjs";

const sections = [
  "handleValues",
  "channelAttachment",
  "datastoreAttachment",
  "handleTransactionBranch",
  "handleRetention",
  "handleReconnect",
  "handleReloadMatrix",
];
const liveSections = sections.slice(0, 4);
const writers = ["upstream", "javascript", "erlang"];
const reference = {
  package: "@fluidframework/tree",
  version: "3.1.0",
  commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
};
const service = {
  implementation: "floodgate",
  revision: "0eb493fc46d1bb9baf1151a6ccdde93544e057e7",
};
const formats = {
  message: 7,
  sharedTreeChange: 5,
  modularChange: 5,
  schema: 2,
  fieldBatch: 2,
};
const contract = {
  reference,
  service,
  oldestSupportedClient,
  formats,
};
const channelAttributes = {
  map: {
    type: "https://graph.microsoft.com/types/map",
    snapshotFormatVersion: "0.2",
    packageVersion: "3.1.0",
  },
  tree: {
    type: "https://graph.microsoft.com/types/tree",
    snapshotFormatVersion: "0.0.0",
    packageVersion: "3.1.0",
  },
};

function hash(value) {
  const bytes = typeof value === "string" || Buffer.isBuffer(value)
    ? value
    : JSON.stringify(value);
  return createHash("sha256").update(bytes).digest("hex");
}

function taggedHandle(value) {
  return { kind: "handle", value };
}

function taggedHandleRoot(label) {
  return {
    kind: "object",
    schemaId: "org.watershed.shared-tree.handles.Root",
    fields: [
      ["label", { kind: "string", value: label }],
      ["links", {
        kind: "map",
        schemaId: "org.watershed.shared-tree.handles.Links",
        entries: [],
      }],
      ["sequence", {
        kind: "array",
        schemaId: "org.watershed.shared-tree.handles.Sequence",
        elements: [],
      }],
    ],
  };
}

function attributes(value) {
  return JSON.parse(JSON.stringify(value.attributes));
}

function parse(value) {
  if (typeof value !== "string") return value;
  try {
    return JSON.parse(value);
  } catch {
    return value;
  }
}

function jsonClone(value) {
  return value === undefined ? undefined : JSON.parse(JSON.stringify(value));
}

function deltaEvidence(messages) {
  return messages.map((message) => ({
    sequenceNumber: message.sequenceNumber,
    clientSequenceNumber: message.clientSequenceNumber,
    referenceSequenceNumber: message.referenceSequenceNumber,
    clientId: message.clientId,
    type: message.type,
    contents: structuredClone(message.contents),
    contentsSha256: hash(message.contents),
    ...(message.metadata === undefined ? {} : {
      metadata: structuredClone(message.metadata),
      metadataSha256: hash(message.metadata),
    }),
  }));
}

function submissionEvidence(writer, environment) {
  if (writer === "upstream") {
    return environment.upstreamSession.transportEvidence().outboundOccurrences
      .map(({ id, connectionId, submissions }) => ({
        id,
        connectionId,
        hash: hash(submissions),
        submissions: jsonClone(submissions),
      }));
  }
  const evidence = environment.adapters[writer].evidence();
  return evidence.outboundOccurrences.map(({
    id, connectionId, sequenceNumbers, byteLength, hash: gateHash, submissions,
  }) => ({
      id,
      connectionId,
      sequenceNumbers: sequenceNumbers ?? [],
      byteLength,
      hash: gateHash,
      submissions: jsonClone(submissions),
    }));
}

function submissionMessages(submitted) {
  return submitted.flatMap(({ submissions }) =>
    submissions.flatMap(({ clientId, messageBatches }) =>
      messageBatches.flat().filter(({ type }) => type === "op").map((message) => ({
        ...structuredClone(message),
        clientId,
      }))));
}

function operationItems(message) {
  const outer = parse(message.contents);
  if (outer?.type === "groupedBatch" && Array.isArray(outer.contents)) {
    return outer.contents.map(({ contents, metadata }) => ({ contents, metadata }));
  }
  return outer?.type === "component"
    ? [{ contents: outer, metadata: message.metadata }]
    : [];
}

function allocationEvidence(messages) {
  return messages.flatMap((message) =>
    operationItems(message).flatMap(({ contents }, innerIndex) => {
      if (contents?.type !== "idAllocation") return [];
      const ids = contents.contents?.ids;
      const first = ids?.first ?? ids?.firstGenCount;
      const last = ids?.last
        ?? (Number.isSafeInteger(first) && Number.isSafeInteger(ids?.count)
          ? first + ids.count - 1
          : undefined);
      return typeof contents.contents?.sessionId === "string"
        && Number.isSafeInteger(first) && Number.isSafeInteger(last)
        ? [{
          sequenceNumber: message.sequenceNumber,
          clientSequenceNumber: message.clientSequenceNumber,
          innerIndex,
          sessionId: contents.contents.sessionId,
          first,
          last,
        }]
        : [];
    }));
}

function containsString(value, expected) {
  if (typeof value === "string") {
    if (value.includes(expected)) return true;
    const decoded = parse(value);
    return decoded !== value && containsString(decoded, expected);
  }
  if (Array.isArray(value)) return value.some((item) => containsString(item, expected));
  return value && typeof value === "object"
    ? Object.values(value).some((item) => containsString(item, expected))
    : false;
}

function matchingObjects(value, predicate, matches = [], seen = new Set()) {
  const decoded = parse(value);
  if (!decoded || typeof decoded !== "object" || seen.has(decoded)) return matches;
  seen.add(decoded);
  if (predicate(decoded)) matches.push(decoded);
  for (const child of Object.values(decoded)) {
    matchingObjects(child, predicate, matches, seen);
  }
  return matches;
}

function attachmentRoutes(value, parents = []) {
  const decoded = parse(value);
  if (!decoded || typeof decoded !== "object") return [];
  if (decoded.type === "component"
    && typeof decoded.contents?.address === "string") {
    return attachmentRoutes(
      decoded.contents.contents,
      [...parents, decoded.contents.address],
    );
  }
  if (decoded.type === "attach") {
    const attachment = decoded.content ?? decoded.contents;
    const id = attachment?.id;
    if (typeof id !== "string") return [];
    const route = [...parents, id];
    const channels = attachment.snapshot?.entries?.find(
      ({ path, type }) => path === ".channels" && type === "Tree",
    )?.value?.entries ?? [];
    return [
      { id, path: `/${route.join("/")}` },
      ...channels.filter(({ type }) => type === "Tree").map(({ path }) => ({
        id: path,
        path: `/${[...route, path].join("/")}`,
      })),
      ...Object.values(decoded).flatMap((child) =>
        attachmentRoutes(child, route)),
    ];
  }
  return Object.values(decoded).flatMap((child) =>
    attachmentRoutes(child, parents));
}

function position(sequenceNumber, innerIndex) {
  return { sequenceNumber, innerIndex };
}

function comparePosition(left, right) {
  return left.sequenceNumber - right.sequenceNumber
    || left.innerIndex - right.innerIndex;
}

function dependencyEvidence(messages, targets) {
  const items = messages.flatMap((message) =>
    operationItems(message).map(({ contents }, innerIndex) => {
      const attaches = attachmentRoutes(contents);
      return {
        sequenceNumber: message.sequenceNumber,
        clientSequenceNumber: message.clientSequenceNumber,
        innerIndex,
        contents,
        attaches,
      };
    }));
  const allocations = allocationEvidence(messages);
  const targetOccurrences = Object.entries(targets).map(([target, { path }]) => {
    const occurrences = items.flatMap((item) => {
      const referenced = containsString(item.contents, path);
      const attaches = item.attaches.some(({ path: route }) => route === path);
      return attaches || referenced ? [{
        sequenceNumber: item.sequenceNumber,
        clientSequenceNumber: item.clientSequenceNumber,
        innerIndex: item.innerIndex,
        kind: attaches ? "attach" : item.attaches.length > 0
          ? "detached-reference" : "reference",
      }] : [];
    });
    return { target, path, occurrences };
  });
  const commits = decodeTreeSubmissions(messages).flatMap((submission) =>
    submission.commits.map(({ revision, originatorId, innerIndex }) => ({
      sequenceNumber: submission.outerSequenceNumber,
      clientSequenceNumber: submission.clientSequenceNumber,
      referenceSequenceNumber: submission.referenceSequenceNumber,
      innerIndex,
      revision,
      originatorId,
      allocations: submission.allocations,
    })));
  return { source: "sequenced", allocations, targets: targetOccurrences, commits };
}

function snapshotBlob(snapshotValue, node, name) {
  const id = node?.blobs?.[name];
  assert(typeof id === "string" && id.length > 0,
    `Published snapshot lacks blob ${name}`);
  const encoded = snapshotValue.blobs[id];
  assert(typeof encoded === "string", `Published snapshot lacks bytes for ${id}`);
  return { id, bytes: Buffer.from(encoded, "base64") };
}

function snapshotNode(snapshotValue, absolutePath) {
  const parts = absolutePath.split("/").filter(Boolean);
  assert(parts.length > 0, `Invalid snapshot path: ${absolutePath}`);
  let node = snapshotValue.tree.trees?.[".channels"]?.trees?.[parts[0]];
  assert(node, `Published snapshot lacks datastore path: ${absolutePath}`);
  for (const part of parts.slice(1)) {
    node = node.trees?.[".channels"]?.trees?.[part];
    assert(node, `Published snapshot lacks channel path: ${absolutePath}`);
  }
  return node;
}

function decodedBlob(snapshotValue, node, name) {
  return JSON.parse(snapshotBlob(snapshotValue, node, name).bytes.toString("utf8"));
}

function handlePath(value) {
  assert.equal(value?.type, "__fluid_handle__", "Stored graph value is not a handle");
  assert(typeof value.url === "string" && value.url.length > 0,
    "Stored graph handle lacks a path");
  return value.url;
}

function storedTreeGraph(snapshotValue, path) {
  const node = snapshotNode(snapshotValue, path);
  const forest = decodedBlob(
    snapshotValue,
    node.trees?.indexes?.trees?.Forest,
    "contents",
  );
  assert.equal(forest.keys?.[0], "rootFieldKey",
    `Stored tree ${path} lacks its root field`);
  const root = forest.fields?.data?.[0];
  assert(Array.isArray(root), `Stored tree ${path} lacks its root node`);
  const links = {};
  const map = Array.isArray(root[3]) ? root[3] : [];
  for (let index = 0; index < map.length; index += 2) {
    links[map[index]] = handlePath(map[index + 1]?.[0]);
  }
  return {
    label: root[1],
    optional: root[2]?.[0] === undefined ? null : handlePath(root[2][0]),
    links,
    sequence: (Array.isArray(root[4]) ? root[4] : []).map(handlePath),
  };
}

function storedMapGraph(snapshotValue, path) {
  const node = snapshotNode(snapshotValue, path);
  const header = decodedBlob(snapshotValue, node, "header").content;
  return Object.fromEntries(Object.entries(header).map(([key, entry]) => {
    const value = entry?.value;
    return [
      key,
      value?.type === "__fluid_handle__" ? handlePath(value) : value,
    ];
  }));
}

function snapshotSequence(snapshotValue) {
  const protocol = snapshotValue.tree.trees?.[".protocol"]
    ?? snapshotValue.tree.trees?.[".app"]?.trees?.[".protocol"];
  const attributes = decodedBlob(snapshotValue, protocol, "attributes");
  assert(Number.isSafeInteger(attributes.sequenceNumber)
    && attributes.sequenceNumber >= 0,
  "Published snapshot protocol attributes lack a reference sequence");
  return attributes.sequenceNumber;
}

function decodedSnapshotCompressor(snapshotValue) {
  const blob = snapshotBlob(snapshotValue, snapshotValue.tree, ".idCompressor");
  const encoded = JSON.parse(blob.bytes.toString("utf8"));
  assert(typeof encoded === "string" && encoded.length > 0,
    "Published snapshot compressor blob is invalid");
  const bytes = Buffer.from(encoded, "base64");
  assert.equal(bytes.toString("base64"), encoded,
    "Published snapshot compressor state is not canonical base64");
  assert.equal(bytes.length % 8, 0,
    "Published snapshot compressor state has an invalid byte length");
  const values = Array.from(
    { length: bytes.length / 8 },
    (_unused, index) => bytes.readDoubleLE(index * 8),
  );
  assert.equal(values[0], 2, "Published snapshot compressor format changed");
  assert.equal(values[1], 0,
    "Published snapshot compressor unexpectedly contains local state");
  const sessionCount = values[2];
  const clusterCount = values[3];
  assert(Number.isSafeInteger(sessionCount) && sessionCount > 0,
    "Published snapshot compressor has an invalid session count");
  assert(Number.isSafeInteger(clusterCount) && clusterCount > 0,
    "Published snapshot compressor has an invalid cluster count");
  assert.equal(values.length, 4 + sessionCount * 2 + clusterCount * 3,
    "Published snapshot compressor state has an invalid layout");
  let compressor;
  assert.doesNotThrow(() => {
    compressor = deserializeIdCompressor(
      encoded,
      "00000000-0000-4000-8000-000000000000",
    );
  }, "Published snapshot compressor cannot be deserialized");
  assert.equal(compressor.serialize(false), encoded,
    "Published snapshot compressor state does not round-trip");
  return { blob, encoded, bytes, compressor };
}

function snapshotCompressor(snapshotValue) {
  const { blob, bytes } = decodedSnapshotCompressor(snapshotValue);
  return {
    blobId: blob.id,
    sha256: hash(blob.bytes),
    stateSha256: hash(bytes),
    byteLength: bytes.length,
    formatVersion: new Float64Array(
      bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + 8),
    )[0],
  };
}

function snapshotMetadata(snapshotValue) {
  return decodedBlob(snapshotValue, snapshotValue.tree, ".metadata");
}

function snapshotEvidence(snapshotValue, targets) {
  const targetEvidence = Object.fromEntries(Object.entries(targets).map(
    ([name, target]) => {
      const node = snapshotNode(snapshotValue, target.path);
      const storedAttributes = decodedBlob(snapshotValue, node, ".attributes");
      return [name, {
        path: target.path,
        treeId: node.id,
        attributes: storedAttributes,
        attributesSha256: hash(JSON.stringify(storedAttributes)),
        graph: storedAttributes.type === channelAttributes.map.type
          ? storedMapGraph(snapshotValue, target.path)
          : storedTreeGraph(snapshotValue, target.path),
      }];
    },
  ));
  const mainPath = "/A/_C";
  return {
    referenceSequenceNumber: snapshotSequence(snapshotValue),
    compressor: snapshotCompressor(snapshotValue),
    main: {
      path: mainPath,
      graph: storedTreeGraph(snapshotValue, mainPath),
    },
    targets: targetEvidence,
  };
}

async function fetchSnapshot(session) {
  const documentService = await session.documentServiceFactory
    .createDocumentService(session.container.resolvedUrl);
  try {
    const storage = await documentService.connectToStorage();
    const versions = await storage.getVersions(null, 1);
    assert.equal(versions.length, 1, "Lifecycle publication lacks one current version");
    const captured = await snapshot(storage);
    return {
      version: versions[0].id,
      treeSha256: hash(captured.tree),
      blobs: Object.fromEntries(
        Object.entries(captured.blobs).map(([id, bytes]) =>
          [id, hash(Buffer.from(bytes, "base64"))]),
      ),
      raw: captured,
    };
  } finally {
    documentService.dispose();
  }
}

async function createEnvironment(config, runId, section, writer, constructors) {
  const environment = {
    adapters: {},
    containers: [],
    creator: undefined,
    documentId: undefined,
    jwt: undefined,
    natives: [],
    peerSession: undefined,
    runId,
    upstreamSession: undefined,
  };
  let failure;
  try {
    environment.creator = await constructors.openSession(
      config,
      environment.containers,
      undefined,
      false,
      { store: handleServiceStore },
    );
    environment.documentId = environment.creator.container.resolvedUrl.id;
    await publishUpstreamSummary(
      config,
      environment.containers,
      environment.documentId,
      `Task 8 ${section}:${writer} bootstrap`,
      { store: handleServiceStore },
    );
    environment.upstreamSession = await constructors.openSession(
      config,
      environment.containers,
      environment.documentId,
      false,
      { store: handleServiceStore },
    );
    environment.peerSession = await constructors.openSession(
      config,
      environment.containers,
      environment.documentId,
      false,
      { store: handleServiceStore },
    );
    const { jwt } = await tokenProvider(config).fetchOrdererToken(
      config.tenantId,
      environment.documentId,
    );
    environment.jwt = jwt;
    if (writer !== "upstream") {
      const adapter = await constructors.nativeAdapter(writer, config, {
        runId,
        documentId: environment.documentId,
        tenant: config.tenantId,
        viewSchema: JSON.stringify(handleStoredSchema),
      }, jwt);
      environment.natives.push(adapter);
      environment.adapters[writer] = adapter;
    }
    await Promise.all(environment.natives.map((adapter) => adapter.awaitSynced()));
    return environment;
  } catch (error) {
    failure = error;
    error.lifecycle = { section, writer };
    error.message = `${section}:${writer}: ${error.message}`;
    throw error;
  } finally {
    if (failure) await closeEnvironment(environment, failure);
  }
}

async function openNativePeer(environment, config, target, constructors) {
  let adapter;
  try {
    adapter = await constructors.nativeAdapter(target, config, {
      runId: environment.runId,
      documentId: environment.documentId,
      tenant: config.tenantId,
      viewSchema: JSON.stringify(handleStoredSchema),
    }, environment.jwt);
    await adapter.awaitSynced();
    return adapter;
  } catch (error) {
    if (adapter) {
      try {
        await adapter.close();
      } catch (cleanupError) {
        error.cleanupErrors = [...(error.cleanupErrors ?? []), cleanupError];
      }
    }
    throw error;
  }
}

async function closeEnvironment(environment, originalError) {
  const errors = [];
  for (const native of environment.natives.toReversed()) {
    try {
      await native.close();
    } catch (error) {
      errors.push(error);
    }
  }
  for (const container of environment.containers.toReversed()) {
    try {
      if (!container.closed) container.dispose();
    } catch (error) {
      errors.push(error);
    }
  }
  if (errors.length === 0) return;
  if (originalError) originalError.cleanupErrors = errors;
  else throw new AggregateError(errors, "Lifecycle environment cleanup failed");
}

async function synchronize(environment) {
  const upstream = [
    environment.creator.container,
    environment.upstreamSession.container,
    environment.peerSession.container,
  ];
  await until(() => {
    const sequences = upstream.map(({ deltaManager }) =>
      deltaManager.lastSequenceNumber
    );
    return upstream.every((container) =>
      !container.isDirty
        && container.deltaManager.inbound.length === 0
        && container.deltaManager.outbound.length === 0
    ) && sequences.every((sequence) => sequence === sequences[0]);
  }, "lifecycle upstream synchronization");
  await Promise.all(environment.natives.map((adapter) => adapter.awaitSynced()));
}

async function nativeCommand(adapter, request) {
  return success(
    await adapter.client.request(request),
    `${adapter.implementation} ${request.command ?? request.op}`,
  ).result;
}

async function createUpstreamTree(data, label) {
  const tree = await data.createTree();
  const view = tree.viewWith(handleTreeConfig);
  view.initialize(initialHandleRoot());
  view.root.label = label;
  return { tree, view };
}

async function createUpstreamDataStore(session) {
  const router = await session.runtime.createDataStore(handleGraphStore.type);
  return router.entryPoint.get();
}

async function authorUpstream(section, environment, label) {
  const data = environment.upstreamSession.data;
  const replies = [];
  if (section === "handleValues") {
    const map = await data.createMap();
    map.set("value", label);
    const localHistoryCount = (await serverHistory(environment.creator)).length;
    data.view.root.link = map.handle;
    data.view.root.links.set("map", map.handle);
    data.view.root.sequence.insertAtEnd(map.handle);
    return {
      targets: { map: { path: map.handle.absolutePath, attributes: attributes(map) } },
      local: { mapValue: map.get("value") },
      localHistoryCount,
      replies,
    };
  }
  if (section === "channelAttachment") {
    const map = await data.createMap();
    const created = await createUpstreamTree(data, `${label}-tree`);
    map.set("value", label);
    map.set("self", map.handle);
    map.set("tree", created.tree.handle);
    created.view.root.link = map.handle;
    const local = {
      mapValue: map.get("value"),
      treeLabel: created.view.root.label,
      selfPath: map.get("self").absolutePath,
      treePath: map.get("tree").absolutePath,
    };
    const localHistoryCount = (await serverHistory(environment.creator)).length;
    data.view.root.link = map.handle;
    data.view.root.links.set("map", map.handle);
    data.view.root.links.set("tree", created.tree.handle);
    data.view.root.links.set("removed", created.tree.handle);
    data.view.root.sequence.insertAtEnd(map.handle, created.tree.handle);
    data.view.root.links.delete("removed");
    created.view.dispose();
    return {
      targets: {
        map: { path: map.handle.absolutePath, attributes: attributes(map) },
        tree: { path: created.tree.handle.absolutePath, attributes: attributes(created.tree) },
      },
      local,
      localHistoryCount,
      replies,
    };
  }
  const secondary = await createUpstreamDataStore(environment.upstreamSession);
  const map = await secondary.createMap();
  const created = await createUpstreamTree(secondary, `${label}-tree`);
  map.set("value", label);
  map.set("self", map.handle);
  map.set("tree", created.tree.handle);
  created.view.root.link = map.handle;
  secondary.root.set("map", map.handle);
  secondary.root.set("tree", created.tree.handle);
  secondary.root.set("removed", map.handle);
  const local = {
    mapValue: map.get("value"),
    treeLabel: created.view.root.label,
    datastorePath: secondary.handle.absolutePath,
  };
  const localHistoryCount = (await serverHistory(environment.creator)).length;
  data.view.root.link = secondary.handle;
  data.view.root.links.set("map", map.handle);
  data.view.root.links.set("tree", created.tree.handle);
  data.view.root.sequence.insertAtEnd(map.handle, created.tree.handle);
  await synchronize(environment);
  const additional = await secondary.createMap();
  additional.set("value", `${label}-visible`);
  secondary.root.set("additional", additional.handle);
  secondary.root.delete("removed");
  created.view.dispose();
  return {
    factory: handleGraphStore.type,
    targets: {
      datastore: {
        path: secondary.handle.absolutePath,
        attributes: attributes(secondary.root),
      },
      map: { path: map.handle.absolutePath, attributes: attributes(map) },
      tree: { path: created.tree.handle.absolutePath, attributes: attributes(created.tree) },
      additional: {
        path: additional.handle.absolutePath,
        attributes: attributes(additional),
      },
    },
    local,
    localHistoryCount,
    replies,
  };
}

async function authorNative(section, environment, writer, label) {
  const adapter = environment.adapters[writer];
  const replies = [];
  const command = async (request) => {
    const result = await nativeCommand(adapter, request);
    replies.push({ request, result });
    return result;
  };
  await command({ command: "root-map", name: "bootstrap" });
  const store = section === "datastoreAttachment" ? "secondary" : undefined;
  if (store) await command({ command: "create-data-store", name: store });
  const entry = store
    ? await command({ command: "data-store-root", store, name: "entry" })
    : null;
  const map = await command({
    command: "create-map",
    ...(store ? { store } : {}),
    name: "target-map",
  });
  await command({
    command: "shared-map-set",
    name: "target-map",
    key: "value",
    value: label,
  });
  if (section === "handleValues") {
    const localHistoryCount = (await serverHistory(environment.creator)).length;
    await command({
      command: "set", path: ["link"], value: taggedHandle(map),
    });
    await command({
      command: "map-set", path: ["links"], key: "map", value: taggedHandle(map),
    });
    await command({
      command: "array-insert", path: ["sequence"], index: 0,
      values: [taggedHandle(map)],
    });
    return {
      targets: { map: { path: map.url } },
      local: {
        mapValue: (await adapter.client.sharedMapGet("target-map", "value")).value,
      },
      localHistoryCount,
      replies,
    };
  }
  const tree = await command({
    command: "create-tree",
    ...(store ? { store } : {}),
    name: "target-tree",
    schema: handleStoredSchema,
    view: handleStoredSchema,
    initialRoot: taggedHandleRoot(`${label}-tree`),
  });
  await command({
    command: "shared-map-set", name: "target-map", key: "self", value: map,
  });
  await command({
    command: "shared-map-set", name: "target-map", key: "tree", value: tree,
  });
  await command({
    command: "set", tree: "target-tree", path: ["link"], value: taggedHandle(map),
  });
  const local = {
    mapValue: (await adapter.client.sharedMapGet("target-map", "value")).value,
    treeLabel: (await adapter.client.read(["label"], "target-tree")).value.value,
    selfPath: (await adapter.client.sharedMapGet("target-map", "self")).value.url,
    treePath: (await adapter.client.sharedMapGet("target-map", "tree")).value.url,
  };
  const localHistoryCount = (await serverHistory(environment.creator)).length;
  if (section === "channelAttachment") {
    await command({ command: "set", path: ["link"], value: taggedHandle(map) });
    for (const [key, value] of [["map", map], ["tree", tree], ["removed", tree]]) {
      await command({
        command: "map-set", path: ["links"], key, value: taggedHandle(value),
      });
    }
    await command({
      command: "array-insert", path: ["sequence"], index: 0,
      values: [taggedHandle(map), taggedHandle(tree)],
    });
    await command({ command: "map-delete", path: ["links"], key: "removed" });
    return {
      targets: { map: { path: map.url }, tree: { path: tree.url } },
      local,
      localHistoryCount,
      replies,
    };
  }
  await command({
    command: "shared-map-set", name: "entry", key: "map", value: map,
  });
  await command({
    command: "shared-map-set", name: "entry", key: "tree", value: tree,
  });
  await command({
    command: "shared-map-set", name: "entry", key: "removed", value: map,
  });
  await command({ command: "set", path: ["link"], value: taggedHandle(entry) });
  await command({
    command: "map-set", path: ["links"], key: "map", value: taggedHandle(map),
  });
  await command({
    command: "map-set", path: ["links"], key: "tree", value: taggedHandle(tree),
  });
  await command({
    command: "array-insert", path: ["sequence"], index: 0,
    values: [taggedHandle(map), taggedHandle(tree)],
  });
  await synchronize(environment);
  const additional = await command({
    command: "create-map", store, name: "additional-map",
  });
  await command({
    command: "shared-map-set", name: "additional-map",
    key: "value", value: `${label}-visible`,
  });
  await command({
    command: "shared-map-set", name: "entry", key: "additional", value: additional,
  });
  await command({
    command: "shared-map-delete", name: "entry", key: "removed",
  });
  return {
    factory: handleGraphStore.type,
    targets: {
      datastore: { path: entry.url },
      map: { path: map.url },
      tree: { path: tree.url },
      additional: { path: additional.url },
    },
    local,
    localHistoryCount,
    replies,
  };
}

function failureOf(callback) {
  try {
    callback();
    return "";
  } catch (error) {
    return String(error);
  }
}

function watchHistory(view, owner) {
  const events = [];
  const handles = [];
  const off = view.events.on("changed", (metadata, getRevertible) => {
    const event = {
      id: `${owner}-event-${events.length + 1}`,
      owner,
      local: metadata.isLocal,
      kind: CommitKind[metadata.kind],
      factoryAvailable: getRevertible !== undefined,
      acquired: false,
      duplicateError: "",
      disposed: false,
    };
    if (metadata.isLocal && getRevertible !== undefined) {
      let handle;
      handle = getRevertible((disposed) => {
        event.disposed = disposed === handle;
        event.status = RevertibleStatus[disposed.status];
      });
      event.acquired = true;
      event.status = RevertibleStatus[handle.status];
      event.duplicateError = failureOf(() => getRevertible());
      handles.push({ event, handle });
    }
    events.push(event);
  });
  return { events, handles, off };
}

function visibleHandleRoot(view) {
  return {
    label: view.root.label,
    ...(view.root.link === undefined
      ? {}
      : { link: view.root.link.absolutePath }),
    links: [...view.root.links].map(([key, value]) => [key, value.absolutePath]),
    sequence: [...view.root.sequence].map(({ absolutePath }) => absolutePath),
  };
}

async function historyPeerEdit(environment, value) {
  const parent = await environment.peerSession.data.bootstrap.get("history").get();
  const view = parent.viewWith(handleTreeConfig);
  const target = await view.root.link.get();
  target.set("peer", value);
  view.dispose();
  await synchronize(environment);
  return {
    parent: parent.handle.absolutePath,
    target: target.handle.absolutePath,
    value: target.get("peer"),
  };
}

async function authorTransactionBranchUpstream(environment, label) {
  const data = environment.upstreamSession.data;
  const replies = [];
  const created = await createUpstreamTree(data, `${label}-document`);
  data.bootstrap.set("history", created.tree.handle);
  await synchronize(environment);
  const main = watchHistory(created.view, "document");
  let historyCursor = (await serverHistory(environment.creator)).length;
  const settledEvidence = async () => {
    const history = await serverHistory(environment.creator);
    const sequenced = deltaEvidence(history.slice(historyCursor));
    historyCursor = history.length;
    const commits = dependencyEvidence(sequenced, targets).commits;
    return {
      revisions: commits.map(({ revision }) => revision),
      settlements: commits.map(({
        sequenceNumber,
        clientSequenceNumber,
        referenceSequenceNumber,
        revision,
      }) => ({
        sequenceNumber,
        clientSequenceNumber,
        referenceSequenceNumber,
        revision,
      })),
    };
  };
  const steps = [];
  const targets = {
    document: {
      path: created.tree.handle.absolutePath,
      attributes: attributes(created.tree),
    },
  };
  const addTarget = async (name, target) => {
    targets[name] = {
      path: target.handle.absolutePath,
      attributes: attributes(target),
    };
    data.bootstrap.set(`history-${name}`, target.handle);
    await synchronize(environment);
  };

  const successful = await data.createMap();
  successful.set("value", `${label}-successful`);
  const successfulBefore = main.events.length;
  const successfulHandlesBefore = main.handles.length;
  const successfulResult = Tree.runTransaction(created.view, () => {
    created.view.root.link = successful.handle;
    return "successful-callback";
  });
  await addTarget("successful", successful);
  const successfulSettled = await settledEvidence();
  const successfulHandles = main.handles.slice(successfulHandlesBefore);
  for (const { handle } of successfulHandles) handle.dispose();
  steps.push({
    id: "successful-transaction",
    transaction: { callbackResult: successfulResult },
    target: successful.handle.absolutePath,
    events: main.events.slice(successfulBefore),
    ...successfulSettled,
    tree: visibleHandleRoot(created.view),
  });
  const aborted = await data.createMap();
  const abortedBefore = main.events.length;
  const abortedResult = Tree.runTransaction(created.view, () => {
    created.view.root.link = aborted.handle;
    aborted.set("independent", "survives-rollback");
    return Tree.runTransaction.rollback;
  });
  steps.push({
    id: "aborted-transaction",
    outcome: abortedResult === Tree.runTransaction.rollback
      ? "aborted"
      : "committed",
    target: aborted.handle.absolutePath,
    targetAttached: aborted.isAttached?.() ?? false,
    targetValue: aborted.get("independent"),
    events: main.events.slice(abortedBefore),
    tree: visibleHandleRoot(created.view),
  });
  await addTarget("aborted", aborted);
  await settledEvidence();

  const nested = await data.createMap();
  nested.set("value", `${label}-nested`);
  const nestedBefore = main.events.length;
  const nestedHandlesBefore = main.handles.length;
  let innerResult;
  const outerResult = Tree.runTransaction(created.view, () => {
    created.view.root.links.set("nested", nested.handle);
    innerResult = Tree.runTransaction(created.view, () => {
      created.view.root.sequence.insertAtEnd(nested.handle);
      return "nested-inner-callback";
    });
    return "nested-outer-callback";
  });
  await addTarget("nested", nested);
  const nestedSettled = await settledEvidence();
  const nestedHandles = main.handles.slice(nestedHandlesBefore);
  for (const { handle } of nestedHandles) handle.dispose();
  steps.push({
    id: "nested-transaction",
    transaction: { outerResult, innerResult },
    target: nested.handle.absolutePath,
    events: main.events.slice(nestedBefore),
    ...nestedSettled,
    tree: visibleHandleRoot(created.view),
  });

  const branchTarget = await data.createMap();
  branchTarget.set("value", `${label}-branch`);
  const branch = created.view.fork();
  const branchWatch = watchHistory(branch, "branch:working");
  const beforeBranchTransport = submissionEvidence("upstream", environment).length;
  branch.root.link = branchTarget.handle;
  const branchHandle = {
    type: "__fluid_handle__",
    url: created.tree.handle.absolutePath,
  };
  steps.push({
    id: "branch-before-merge",
    target: branchTarget.handle.absolutePath,
    document: created.tree.handle.absolutePath,
    marker: branchHandle,
    branch: visibleHandleRoot(branch),
    main: visibleHandleRoot(created.view),
    events: structuredClone(branchWatch.events),
    transportDelta: submissionEvidence("upstream", environment).length
      - beforeBranchTransport,
  });
  const branchInverse = branchWatch.handles.at(-1);
  created.view.merge(branch);
  await addTarget("branch", branchTarget);
  steps.push({
    id: "branch-after-merge",
    target: branchTarget.handle.absolutePath,
    main: visibleHandleRoot(created.view),
    inverse: {
      event: branchInverse?.event,
      status: branchInverse
        ? RevertibleStatus[branchInverse.handle.status]
        : "Missing",
    },
  });
  branchWatch.off();

  for (const id of ["branch-dropped", "branch-disposal"]) {
    const target = await data.createMap();
    target.set("value", `${label}-${id}`);
    const local = created.view.fork();
    const watcher = watchHistory(local, `branch:${id}`);
    const beforeTransport = submissionEvidence("upstream", environment).length;
    local.root.link = target.handle;
    const inverse = watcher.handles.at(-1);
    const branchBeforeCleanup = visibleHandleRoot(local);
    let discard;
    if (id === "branch-dropped") {
      const beforeStatus = inverse
        ? RevertibleStatus[inverse.handle.status]
        : "Missing";
      inverse?.handle.revert(true);
      discard = {
        beforeStatus,
        afterStatus: inverse
          ? RevertibleStatus[inverse.handle.status]
          : "Missing",
        disposedSameHandle: inverse?.event.disposed ?? false,
        branch: visibleHandleRoot(local),
        events: structuredClone(watcher.events.slice(1)),
      };
    }
    local.dispose();
    steps.push({
      id,
      target: target.handle.absolutePath,
      targetAttached: target.isAttached?.() ?? false,
      main: visibleHandleRoot(created.view),
      events: structuredClone(watcher.events),
      branchBeforeCleanup,
      ...(discard === undefined ? {} : { discard }),
      transportDelta: submissionEvidence("upstream", environment).length
        - beforeTransport,
      inverse: {
        acquired: inverse !== undefined,
        status: inverse ? RevertibleStatus[inverse.handle.status] : "Missing",
        disposed: inverse?.event.disposed ?? false,
      },
    });
    await addTarget(id === "branch-dropped" ? "dropped" : "disposed", target);
    watcher.off();
  }

  const undoTarget = await data.createMap();
  undoTarget.set("value", `${label}-undo`);
  const undoBefore = main.handles.length;
  created.view.root.link = undoTarget.handle;
  await addTarget("undo", undoTarget);
  const insertion = main.handles[undoBefore];
  assert(insertion, "Upstream handle insertion did not expose an inverse factory");
  const peer = await historyPeerEdit(environment, "survives-insertion-undo");
  const beforeStatus = RevertibleStatus[insertion.handle.status];
  insertion.handle.revert(true);
  await synchronize(environment);
  const afterStatus = RevertibleStatus[insertion.handle.status];
  steps.push({
    id: "handle-undo-peer-edit",
    target: undoTarget.handle.absolutePath,
    referringPath: created.view.root.link?.absolutePath,
    peer,
    targetValue: undoTarget.get("peer"),
    inverse: {
      event: insertion.event,
      beforeStatus,
      afterStatus,
      disposedSameHandle: insertion.event.disposed,
    },
  });

  main.off();
  created.view.dispose();
  return {
    targets,
    local: { mapValue: `${label}-successful`, treeLabel: `${label}-document` },
    localHistoryCount: 0,
    replies,
    history: { steps, events: main.events },
  };
}

async function authorTransactionBranchNative(environment, writer, label) {
  const adapter = environment.adapters[writer];
  const replies = [];
  const command = async (request) => {
    const result = await nativeCommand(adapter, request);
    replies.push({ request, result });
    return result;
  };
  await command({ command: "root-map", name: "bootstrap" });
  const document = await command({
    command: "create-tree",
    name: "history-tree",
    schema: handleStoredSchema,
    view: handleStoredSchema,
    initialRoot: taggedHandleRoot(`${label}-document`),
  });
  await command({
    command: "shared-map-set",
    name: "bootstrap",
    key: "history",
    value: document,
  });
  await synchronize(environment);
  await command({ command: "subscribe", tree: "history-tree" });
  const steps = [];
  const targets = {
    document: { path: document.url, attributes: channelAttributes.tree },
  };
  const createMap = async (name, value) => {
    const map = await command({ command: "create-map", name });
    await command({
      command: "shared-map-set", name, key: "value", value,
    });
    return map;
  };
  const publishTarget = async (name, target) => {
    targets[name] = { path: target.url, attributes: channelAttributes.map };
    await command({
      command: "shared-map-set",
      name: "bootstrap",
      key: `history-${name}`,
      value: target,
    });
    await synchronize(environment);
  };
  const checkpoint = async () => command({
    command: "checkpoint", tree: "history-tree",
  });

  const successful = await createMap("history-successful", `${label}-successful`);
  const successfulResult = await command({
    command: "transaction",
    tree: "history-tree",
    constraints: [],
    edits: [{ op: "set", path: ["link"], value: taggedHandle(successful) }],
    result: "commit",
  });
  const successfulInverse = await command({
    op: "retainLastLocalCommit",
    tree: "history-tree",
    name: "successful-edit",
  });
  await publishTarget("successful", successful);
  const successfulCheckpoint = await checkpoint();
  await command({
    op: "disposeRevertible",
    tree: "history-tree",
    name: "successful-edit",
  });
  steps.push({
    id: "successful-transaction",
    target: successful.url,
    transaction: successfulResult,
    inverse: successfulInverse,
    checkpoint: successfulCheckpoint,
  });
  const aborted = await createMap("history-aborted", `${label}-aborted`);
  await command({
    command: "shared-map-set",
    name: "history-aborted",
    key: "independent",
    value: "survives-rollback",
  });
  const abortedResult = await command({
    command: "transaction",
    tree: "history-tree",
    constraints: [],
    edits: [{ op: "set", path: ["link"], value: taggedHandle(aborted) }],
    result: "abort",
  });
  steps.push({
    id: "aborted-transaction",
    target: aborted.url,
    transaction: abortedResult,
    targetValue: (await adapter.client.sharedMapGet(
      "history-aborted",
      "independent",
    )).value,
    checkpoint: await checkpoint(),
  });
  await publishTarget("aborted", aborted);

  const nested = await createMap("history-nested", `${label}-nested`);
  const nestedResult = await command({
    command: "transaction",
    tree: "history-tree",
    constraints: [],
    edits: [
      {
        op: "map-set", path: ["links"], key: "nested",
        value: taggedHandle(nested),
      },
      {
        op: "transaction",
        constraints: [],
        edits: [{
          op: "array-insert", path: ["sequence"], index: 0,
          values: [taggedHandle(nested)],
        }],
        result: "commit",
      },
    ],
    result: "commit",
  });
  await publishTarget("nested", nested);
  steps.push({
    id: "nested-transaction",
    target: nested.url,
    transaction: nestedResult,
    checkpoint: await checkpoint(),
  });

  const branchTarget = await createMap("history-branch", `${label}-branch`);
  await command({ op: "fork", tree: "history-tree", source: "main", name: "working" });
  const branchEdit = await command({
    op: "branchEdit",
    tree: "history-tree",
    branch: "working",
    edit: { kind: "object-set", path: ["link"], value: taggedHandle(branchTarget) },
  });
  const branchRetained = await command({
    op: "retainLastLocalCommit",
    tree: "history-tree",
    branch: "working",
    name: "working-edit",
  });
  steps.push({
    id: "branch-before-merge",
    target: branchTarget.url,
    document: document.url,
    marker: document,
    edit: branchEdit,
    inverse: branchRetained,
    checkpoint: await checkpoint(),
  });
  const merged = await command({
    op: "mergeBranch",
    tree: "history-tree",
    target: "main",
    source: "working",
    dispose: true,
  });
  const mergeInverse = await command({
    op: "retainLastLocalCommit",
    tree: "history-tree",
    name: "merge-edit",
  });
  await publishTarget("branch", branchTarget);
  const mergeCheckpoint = await checkpoint();
  await command({
    op: "disposeRevertible",
    tree: "history-tree",
    name: "merge-edit",
  });
  steps.push({
    id: "branch-after-merge",
    target: branchTarget.url,
    merge: merged,
    inverse: mergeInverse,
    checkpoint: mergeCheckpoint,
  });

  for (const [id, branchName] of [
    ["branch-dropped", "dropped"],
    ["branch-disposal", "disposed"],
  ]) {
    const target = await createMap(`history-${branchName}`, `${label}-${id}`);
    await command({
      op: "fork", tree: "history-tree", source: "main", name: branchName,
    });
    const edit = await command({
      op: "branchEdit",
      tree: "history-tree",
      branch: branchName,
      edit: { kind: "object-set", path: ["link"], value: taggedHandle(target) },
    });
    const retained = await command({
      op: "retainLastLocalCommit",
      tree: "history-tree",
      branch: branchName,
      name: `${branchName}-edit`,
    });
    const discard = id === "branch-dropped"
      ? await command({
        op: "revert",
        tree: "history-tree",
        name: `${branchName}-edit`,
        dispose: true,
      })
      : undefined;
    const disposed = await command({
      op: "disposeBranch", tree: "history-tree", name: branchName,
    });
    steps.push({
      id,
      target: target.url,
      edit,
      inverse: retained,
      ...(discard === undefined ? {} : { discard }),
      disposed,
      checkpoint: await checkpoint(),
    });
    await publishTarget(branchName, target);
  }

  const undoTarget = await createMap("history-undo", `${label}-undo`);
  await command({
    command: "set",
    tree: "history-tree",
    path: ["link"],
    value: taggedHandle(undoTarget),
  });
  const retained = await command({
    op: "retainLastLocalCommit",
    tree: "history-tree",
    name: "insertion",
  });
  await publishTarget("undo", undoTarget);
  const peer = await historyPeerEdit(environment, "survives-insertion-undo");
  const beforeStatus = await command({
    op: "revertibleStatus", tree: "history-tree", name: "insertion",
  });
  const reverted = await command({
    op: "revert",
    tree: "history-tree",
    name: "insertion",
    dispose: true,
  });
  await synchronize(environment);
  const undoCheckpoint = await checkpoint();
  steps.push({
    id: "handle-undo-peer-edit",
    target: undoTarget.url,
    peer,
    inverse: { retained, beforeStatus, reverted },
    checkpoint: undoCheckpoint,
  });

  let readiness;
  try {
    await until(async () => {
      readiness = await adapter.client.request({
        command: "pending-summary-evidence",
      });
      return readiness.ok === true;
    }, `${writer} transaction history summary readiness`);
  } catch (error) {
    throw new Error(
      `${error.message}: ${JSON.stringify({ readiness, undoCheckpoint })}`,
      { cause: error },
    );
  }
  return {
    targets,
    local: { mapValue: `${label}-successful`, treeLabel: `${label}-document` },
    localHistoryCount: 0,
    replies,
    history: { steps },
  };
}

function handleValue(value) {
  assert.equal(value.present, true, "Peer handle field is absent");
  assert.equal(value.value.kind, "handle", "Peer field is not a handle");
  return value.value.value;
}

async function observeNativePeer(adapter, section) {
  if (section === "datastoreAttachment") {
    const secondary = handleValue(await adapter.client.read(["link"]));
    await adapter.client.openMap("peer-entry", secondary);
    const map = (await adapter.client.sharedMapGet("peer-entry", "map")).value;
    const tree = (await adapter.client.sharedMapGet("peer-entry", "tree")).value;
    const additional =
      (await adapter.client.sharedMapGet("peer-entry", "additional")).value;
    await adapter.client.openMap("peer-map", map);
    await adapter.client.openMap("peer-additional", additional);
    await adapter.client.openTree("peer-tree", tree, handleStoredSchema);
    return {
      targets: {
        datastore: { path: secondary.url },
        map: { path: map.url },
        tree: { path: tree.url },
        additional: { path: additional.url },
      },
      values: {
        map: (await adapter.client.sharedMapGet("peer-map", "value")).value,
        tree: (await adapter.client.read(["label"], "peer-tree")).value.value,
        additional:
          (await adapter.client.sharedMapGet("peer-additional", "value")).value,
        removed: await adapter.client.sharedMapGet("peer-entry", "removed"),
      },
      graph: {
        main: {
          optional: secondary.url,
          links: {
            map: handleValue(await adapter.client.mapGet(["links"], "map")).url,
            tree: handleValue(await adapter.client.mapGet(["links"], "tree")).url,
          },
          sequence: [
            handleValue(await adapter.client.arrayGet(["sequence"], 0)).url,
            handleValue(await adapter.client.arrayGet(["sequence"], 1)).url,
          ],
        },
        entry: {
          map: map.url,
          tree: tree.url,
          additional: additional.url,
          removed: (await adapter.client.sharedMapGet("peer-entry", "removed")).present,
        },
        map: {
          self: (await adapter.client.sharedMapGet("peer-map", "self")).value.url,
          tree: (await adapter.client.sharedMapGet("peer-map", "tree")).value.url,
        },
        tree: {
          optional: handleValue(await adapter.client.read(["link"], "peer-tree")).url,
        },
      },
    };
  }
  const map = handleValue(await adapter.client.read(["link"]));
  await adapter.client.openMap("peer-map", map);
  const result = {
    targets: { map: { path: map.url } },
    values: {
      map: (await adapter.client.sharedMapGet("peer-map", "value")).value,
      mapLink: handleValue(await adapter.client.mapGet(["links"], "map")).url,
      arrayLink: handleValue(await adapter.client.arrayGet(["sequence"], 0)).url,
    },
    graph: {
      main: {
        optional: map.url,
        links: {
          map: handleValue(await adapter.client.mapGet(["links"], "map")).url,
        },
        sequence: [
          handleValue(await adapter.client.arrayGet(["sequence"], 0)).url,
        ],
      },
    },
  };
  if (section === "channelAttachment") {
    const tree = handleValue(await adapter.client.mapGet(["links"], "tree"));
    await adapter.client.openTree("peer-tree", tree, handleStoredSchema);
    result.targets.tree = { path: tree.url };
    result.values.tree = (await adapter.client.read(["label"], "peer-tree")).value.value;
    result.values.removed = await adapter.client.mapGet(["links"], "removed");
    result.graph.main.links.tree = tree.url;
    result.graph.main.links.removed = result.values.removed.present;
    result.graph.main.sequence.push(
      handleValue(await adapter.client.arrayGet(["sequence"], 1)).url,
    );
    result.graph.map = {
      self: (await adapter.client.sharedMapGet("peer-map", "self")).value.url,
      tree: (await adapter.client.sharedMapGet("peer-map", "tree")).value.url,
    };
    result.graph.tree = {
      optional: handleValue(await adapter.client.read(["link"], "peer-tree")).url,
    };
  }
  return result;
}

async function observeUpstreamPeer(session, section) {
  if (section === "datastoreAttachment") {
    const secondaryHandle = session.data.view.root.link;
    const secondary = await secondaryHandle.get();
    const mapHandle = secondary.get("map");
    const treeHandle = secondary.get("tree");
    const additionalHandle = secondary.get("additional");
    const map = await mapHandle.get();
    const tree = await treeHandle.get();
    const additional = await additionalHandle.get();
    const view = tree.viewWith(handleTreeConfig);
    const result = {
      targets: {
        datastore: {
          path: secondaryHandle.absolutePath,
          attributes: attributes(secondary),
        },
        map: { path: mapHandle.absolutePath, attributes: attributes(map) },
        tree: { path: treeHandle.absolutePath, attributes: attributes(tree) },
        additional: {
          path: additionalHandle.absolutePath,
          attributes: attributes(additional),
        },
      },
      values: {
        map: map.get("value"),
        tree: view.root.label,
        additional: additional.get("value"),
        removed: secondary.has("removed"),
      },
      graph: {
        main: {
          optional: secondaryHandle.absolutePath,
          links: {
            map: session.data.view.root.links.get("map").absolutePath,
            tree: session.data.view.root.links.get("tree").absolutePath,
          },
          sequence: [...session.data.view.root.sequence]
            .map((handle) => handle.absolutePath),
        },
        entry: {
          map: mapHandle.absolutePath,
          tree: treeHandle.absolutePath,
          additional: additionalHandle.absolutePath,
          removed: secondary.has("removed"),
        },
        map: {
          self: map.get("self").absolutePath,
          tree: map.get("tree").absolutePath,
        },
        tree: { optional: view.root.link.absolutePath },
      },
    };
    view.dispose();
    return result;
  }
  const mapHandle = session.data.view.root.link;
  const map = await mapHandle.get();
  const result = {
    targets: {
      map: { path: mapHandle.absolutePath, attributes: attributes(map) },
    },
    values: {
      map: map.get("value"),
      mapLink: session.data.view.root.links.get("map").absolutePath,
      arrayLink: session.data.view.root.sequence[0].absolutePath,
    },
    graph: {
      main: {
        optional: mapHandle.absolutePath,
        links: {
          map: session.data.view.root.links.get("map").absolutePath,
        },
        sequence: [...session.data.view.root.sequence]
          .map((handle) => handle.absolutePath),
      },
    },
  };
  if (section === "channelAttachment") {
    const treeHandle = session.data.view.root.links.get("tree");
    const tree = await treeHandle.get();
    const view = tree.viewWith(handleTreeConfig);
    result.targets.tree = {
      path: treeHandle.absolutePath,
      attributes: attributes(tree),
    };
    result.values.tree = view.root.label;
    result.values.removed = session.data.view.root.links.has("removed");
    result.graph.main.links.tree = treeHandle.absolutePath;
    result.graph.main.links.removed = result.values.removed;
    result.graph.map = {
      self: map.get("self").absolutePath,
      tree: map.get("tree").absolutePath,
    };
    result.graph.tree = { optional: view.root.link.absolutePath };
    view.dispose();
  }
  return result;
}

async function observeHistoryUpstreamPeer(session, targets) {
  const documentHandle = session.data.bootstrap.get("history");
  const tree = await documentHandle.get();
  const view = tree.viewWith(handleTreeConfig);
  const observed = {
    document: documentHandle.absolutePath,
    tree: visibleHandleRoot(view),
    targets: {},
  };
  for (const name of [
    "successful", "aborted", "nested", "branch", "dropped", "disposed", "undo",
  ]) {
    const handle = session.data.bootstrap.get(`history-${name}`);
    const target = await handle.get();
    observed.targets[name] = {
      path: handle.absolutePath,
      ...(target.has("value") ? { value: target.get("value") } : {}),
      ...(target.has("peer") ? { peer: target.get("peer") } : {}),
    };
  }
  view.dispose();
  assert.deepEqual(
    Object.fromEntries(Object.entries(observed.targets)
      .map(([name, value]) => [name, value.path])),
    Object.fromEntries([
      "successful", "aborted", "nested", "branch", "dropped", "disposed", "undo",
    ]
      .map((name) => [name, targets[name].path])),
    "History upstream peer resolved another target identity",
  );
  return observed;
}

async function observeHistoryNativePeer(adapter, targets) {
  await nativeCommand(adapter, { command: "root-map", name: "history-root" });
  const document = (await nativeCommand(adapter, {
    command: "shared-map-get", name: "history-root", key: "history",
  })).value;
  await nativeCommand(adapter, {
    command: "open-tree",
    name: "history-observed",
    handle: document,
    view: handleStoredSchema,
  });
  const observed = {
    document: document.url,
    tree: {
      label: (await adapter.client.read(["label"], "history-observed")).value.value,
      link: handleValue(
        await adapter.client.read(["link"], "history-observed"),
      ).url,
      links: {
        nested: handleValue(
          await adapter.client.mapGet(["links"], "nested", "history-observed"),
        ).url,
      },
      sequence: [
        handleValue(
          await adapter.client.arrayGet(["sequence"], 0, "history-observed"),
        ).url,
      ],
    },
    targets: {},
  };
  for (const name of [
    "successful", "aborted", "nested", "branch", "dropped", "disposed", "undo",
  ]) {
    const handle = (await nativeCommand(adapter, {
      command: "shared-map-get",
      name: "history-root",
      key: `history-${name}`,
    })).value;
    await nativeCommand(adapter, {
      command: "open-map", name: `history-${name}`, handle,
    });
    const value = await adapter.client.sharedMapGet(`history-${name}`, "value");
    const peer = await adapter.client.sharedMapGet(`history-${name}`, "peer");
    observed.targets[name] = {
      path: handle.url,
      ...(value.present ? { value: value.value } : {}),
      ...(peer.present ? { peer: peer.value } : {}),
    };
  }
  assert.deepEqual(
    Object.fromEntries(Object.entries(observed.targets)
      .map(([name, value]) => [name, value.path])),
    Object.fromEntries([
      "successful", "aborted", "nested", "branch", "dropped", "disposed", "undo",
    ]
      .map((name) => [name, targets[name].path])),
    "History native peer resolved another target identity",
  );
  return observed;
}

async function activeTargetEvidence(config, context, writer) {
  const environment = await createEnvironment(
    config,
    context.runId,
    "handleTransactionBranch-active",
    writer,
    context.constructors,
  );
  let failure;
  try {
    const historyBefore = await serverHistory(environment.creator);
    if (writer === "upstream") {
      const parent = await createUpstreamTree(
        environment.upstreamSession.data,
        "active-parent",
      );
      environment.upstreamSession.data.bootstrap.set("history", parent.tree.handle);
      await synchronize(environment);
      const target = await createUpstreamTree(
        environment.upstreamSession.data,
        "active-target",
      );
      const parentBefore = visibleHandleRoot(parent.view);
      const targetBefore = visibleHandleRoot(target.view);
      let transactionEntered = false;
      const error = failureOf(() => Tree.runTransaction(target.view, () => {
        transactionEntered = true;
        parent.view.root.link = target.tree.handle;
      }));
      await synchronize(environment);
      const history = await serverHistory(environment.creator);
      const evidence = {
        documentId: environment.documentId,
        exception: "pinned-upstream-invalidates-after-attachment-attempt",
        error,
        transactionEntered,
        parent: {
          before: parentBefore,
          afterError: failureOf(() => visibleHandleRoot(parent.view)),
        },
        target: {
          path: target.tree.handle.absolutePath,
          attachedBefore: false,
          attachedAfter: target.tree.isAttached(),
          before: targetBefore,
          afterError: failureOf(() => visibleHandleRoot(target.view)),
        },
        raw: {
          submitted: submissionEvidence(writer, environment),
          sequenced: deltaEvidence(history.slice(historyBefore.length)),
        },
      };
      return evidence;
    }

    const adapter = environment.adapters[writer];
    await nativeCommand(adapter, { command: "root-map", name: "active-root" });
    const parent = await nativeCommand(adapter, {
      command: "create-tree",
      name: "active-parent",
      schema: handleStoredSchema,
      view: handleStoredSchema,
      initialRoot: taggedHandleRoot("active-parent"),
    });
    await nativeCommand(adapter, {
      command: "shared-map-set",
      name: "active-root",
      key: "history",
      value: parent,
    });
    await synchronize(environment);
    const target = await nativeCommand(adapter, {
      command: "create-tree",
      name: "active-target",
      schema: handleStoredSchema,
      view: handleStoredSchema,
      initialRoot: taggedHandleRoot("active-target"),
    });
    const before = {
      parent: await adapter.client.read(["link"], "active-parent"),
      target: await adapter.client.read(["label"], "active-target"),
      checkpoint: await adapter.client.checkpoint("active-parent"),
      runtime: await nativeCommand(adapter, { command: "runtime-state-evidence" }),
      submitted: submissionEvidence(writer, environment),
      historyCount: (await serverHistory(environment.creator)).length,
    };
    const refusal = await adapter.client.request({
      command: "active-target-preflight",
      tree: "active-parent",
      target: "active-target",
    });
    await synchronize(environment);
    const after = {
      parent: await adapter.client.read(["link"], "active-parent"),
      target: await adapter.client.read(["label"], "active-target"),
      checkpoint: await adapter.client.checkpoint("active-parent"),
      runtime: await nativeCommand(adapter, { command: "runtime-state-evidence" }),
      submitted: submissionEvidence(writer, environment),
      historyCount: (await serverHistory(environment.creator)).length,
    };
    return {
      documentId: environment.documentId,
      exception: "native-atomic-preflight-refusal",
      targetPath: target.url,
      refusal: structuredClone(refusal.result ?? refusal),
      before,
      after,
      raw: {
        submitted: submissionEvidence(writer, environment),
        sequenced: deltaEvidence(
          (await serverHistory(environment.creator)).slice(historyBefore.length),
        ),
      },
    };
  } catch (error) {
    failure = error;
    throw error;
  } finally {
    await closeEnvironment(environment, failure);
  }
}

function expectedGraph(name, targets) {
  const main = {
    optional: targets.datastore?.path ?? targets.map.path,
    links: { map: targets.map.path },
    sequence: [targets.map.path],
  };
  if (name === "handleValues") return { main };
  main.links.tree = targets.tree.path;
  main.sequence.push(targets.tree.path);
  if (name === "channelAttachment") {
    return {
      main: { ...main, links: { ...main.links, removed: false } },
      map: { self: targets.map.path, tree: targets.tree.path },
      tree: { optional: targets.map.path },
    };
  }
  return {
    main,
    entry: {
      map: targets.map.path,
      tree: targets.tree.path,
      additional: targets.additional.path,
      removed: false,
    },
    map: { self: targets.map.path, tree: targets.tree.path },
    tree: { optional: targets.map.path },
  };
}

function expectedSnapshotGraph(name, graph) {
  const snapshot = {
    main: {
      optional: graph.main.optional,
      links: Object.fromEntries(
        Object.entries(graph.main.links).filter(([, value]) => value !== false),
      ),
      sequence: graph.main.sequence,
    },
  };
  if (name !== "handleValues") {
    snapshot.map = { self: graph.map.self, tree: graph.map.tree };
    snapshot.tree = { optional: graph.tree.optional };
  }
  if (name === "datastoreAttachment") snapshot.entry = graph.entry;
  return snapshot;
}

async function runRow(config, context, section, writer) {
  const environment = await createEnvironment(
    config,
    context.runId,
    section,
    writer,
    context.constructors,
  );
  let failure;
  try {
    const label = `${section}-${writer}-${context.runId.slice(0, 8)}`;
    const historyBefore = await serverHistory(environment.creator);
    const authored = section === "handleTransactionBranch"
      ? writer === "upstream"
        ? await authorTransactionBranchUpstream(environment, label)
        : await authorTransactionBranchNative(environment, writer, label)
      : writer === "upstream"
        ? await authorUpstream(section, environment, label)
        : await authorNative(section, environment, writer, label);
    for (const [name, target] of Object.entries(authored.targets)) {
      target.attributes = structuredClone(
        name === "tree" || name === "document"
          ? channelAttributes.tree
          : channelAttributes.map,
      );
    }
    await synchronize(environment);
    const peers = {
      upstream: section === "handleTransactionBranch"
        ? await observeHistoryUpstreamPeer(environment.peerSession, authored.targets)
        : await observeUpstreamPeer(environment.peerSession, section),
    };
    const publication = writer === "upstream"
      ? await publishUpstreamSummary(
        config,
        environment.containers,
        environment.documentId,
        `Task 8 ${section}:${writer} publication`,
        { store: handleServiceStore },
      )
      : await environment.adapters[writer].summarizePublication();
    await synchronize(environment);
    const history = await serverHistory(environment.creator);
    const stored = await fetchSnapshot(environment.creator);
    for (const target of ["javascript", "erlang"]) {
      if (target === writer) continue;
      let peer;
      try {
        peer = await openNativePeer(
          environment,
          config,
          target,
          context.constructors,
        );
        peers[target] = section === "handleTransactionBranch"
          ? await observeHistoryNativePeer(peer, authored.targets)
          : await observeNativePeer(peer, section);
      } finally {
        await peer?.close();
      }
    }
    const submitted = submissionEvidence(writer, environment);
    const sequenced = deltaEvidence(history.slice(historyBefore.length));
    const graph = section === "handleTransactionBranch"
      ? {
        document: authored.targets.document.path,
        final: peers.upstream.tree,
        targets: Object.fromEntries(Object.entries(authored.targets)
          .map(([name, target]) => [name, target.path])),
      }
      : expectedGraph(section, authored.targets);
    const storedEvidence = snapshotEvidence(stored.raw, authored.targets);
    const publicationEvidence = writer === "upstream"
      ? {
        kind: "summary-ack",
        version: publication.summaryAckOp.contents.handle,
        acknowledgementSequenceNumber: publication.summaryAckOp.sequenceNumber,
        referenceSequenceNumber: publication.summaryReferenceSequenceNumber,
        response: structuredClone(publication.summaryAckOp),
      }
      : {
        kind: "native-publication-response",
        version: publication.version,
        referenceSequenceNumber: publication.snapshotSequenceNumber,
        response: structuredClone(publication),
      };
    const row = {
      formatVersion: 1,
      runId: context.runId,
      writer,
      documentId: environment.documentId,
      contract,
      factory: authored.factory ?? handleServiceStore.type,
      targets: authored.targets,
      local: authored.local,
      peer: {
        expectedImplementations: writers.filter(
          (implementation) => implementation === "upstream" || implementation !== writer,
        ),
        observations: peers,
      },
      raw: {
        intent: { section, writer, label },
        nativeReplies: authored.replies,
        submitted,
        sequenced,
        dependencies: dependencyEvidence(sequenced, authored.targets),
        publication: publicationEvidence,
        historyBeforeCount: historyBefore.length,
        historyAfterLocalCount: authored.localHistoryCount,
      },
      snapshot: {
        version: stored.version,
        treeSha256: stored.treeSha256,
        blobs: stored.blobs,
        evidence: storedEvidence,
      },
      graph,
      ...(authored.history ? {
        history: await (async () => {
          const activeTarget = await activeTargetEvidence(
            config,
            context,
            writer,
          );
          return {
            ...authored.history,
            activeTarget,
            steps: [
              ...authored.history.steps.slice(0, 3),
              { id: "active-target", ...activeTarget },
              ...authored.history.steps.slice(3),
            ],
          };
        })(),
      } : {}),
      writerClientIds: writer === "upstream"
        ? [environment.upstreamSession.container.clientId]
        : [...environment.adapters[writer].clientIds],
      artifacts: [],
    };
    const artifact = {
      formatVersion: 1,
      runId: context.runId,
      section,
      writer,
      documentId: row.documentId,
      contract,
      raw: row.raw,
      targets: row.targets,
      factory: row.factory,
      graph,
      peers,
      ...(row.history ? { history: row.history } : {}),
      snapshot: stored.raw,
    };
    const relative = `${section}/${writer}.json`;
    const bytes = `${JSON.stringify(artifact)}\n`;
    await mkdir(join(context.output, section), { recursive: true });
    await writeFile(join(context.output, relative), bytes, { mode: 0o600 });
    context.artifacts.files[relative] = { sha256: hash(bytes) };
    row.artifacts.push({ path: relative, sha256: hash(bytes) });
    return row;
  } catch (error) {
    failure = error;
    throw error;
  } finally {
    await closeEnvironment(environment, failure);
  }
}

function snapshotFactory(snapshotValue, path) {
  const storeId = path.split("/").filter(Boolean)[0];
  const store = snapshotValue.tree.trees?.[".channels"]?.trees?.[storeId];
  const component = decodedBlob(snapshotValue, store, ".component");
  return {
    packagePath: JSON.parse(component.pkg),
    summaryFormatVersion: component.summaryFormatVersion,
    isRootDataStore: component.isRootDataStore,
  };
}

function validateContract(value, label) {
  assert.deepEqual(value, contract, `${label} pins or formats changed`);
}

function validateTransportBinding(name, row) {
  for (const [index, occurrence] of row.raw.submitted.entries()) {
    assert(Number.isSafeInteger(occurrence.id) && occurrence.id > 0,
      `${name} submitted occurrence ${index} lacks an ID`);
    assert(typeof occurrence.connectionId === "string"
      && occurrence.connectionId.length > 0,
    `${name} submitted occurrence ${index} lacks a transport identity`);
    assert.match(occurrence.hash, /^[a-f0-9]{64}$/,
      `${name} submitted occurrence ${index} lacks its actual hash`);
    assert(Array.isArray(occurrence.submissions)
      && occurrence.submissions.length > 0,
    `${name} submitted occurrence ${index} lacks raw submissions`);
  }
  const outbound = submissionMessages(row.raw.submitted);
  assert(outbound.length > 0, `${name} raw submitted operations are missing`);
  assert(outbound.every(({ clientId }) => row.writerClientIds.includes(clientId)),
    `${name} outbound operation has another writer identity`);
  const comparable = ({
    clientId,
    clientSequenceNumber,
    referenceSequenceNumber,
    contents,
    metadata,
  }) => ({
    clientId,
    clientSequenceNumber,
    referenceSequenceNumber,
    contents: parse(contents),
    metadata: jsonClone(metadata),
  });
  const submittedOperations = outbound.map(comparable);
  const sequencedOperations = row.raw.sequenced
    .filter(({ type, clientId }) =>
      type === "op" && row.writerClientIds.includes(clientId))
    .map(comparable);
  assert.deepEqual(
    submittedOperations,
    sequencedOperations,
    `${name} complete ordered outbound correspondence differs from service history`,
  );
  const derived = dependencyEvidence(row.raw.sequenced, row.targets);
  assert.deepEqual(row.raw.dependencies, derived,
    `${name} allocation/attach dependency order differs from raw sequenced bytes`);
  for (const target of derived.targets) {
    const attachments = target.occurrences.filter(({ kind }) => kind === "attach");
    const references = target.occurrences.filter(({ kind }) => kind === "reference");
    assert.equal(attachments.length, 1,
      `${name} raw attachment is missing or repeated: ${target.path}`);
    assert(references.length > 0,
      `${name} raw attachment/reference target is missing: ${target.path}`);
    assert(comparePosition(attachments[0], references[0]) < 0,
      `${name} target was externally referenced before attachment: ${target.path}`);
  }
  assert(derived.commits.length > 0,
    `${name} raw sequenced revisions are missing`);
}

function validatePublication(name, row, artifactSnapshot) {
  const publication = row.raw.publication;
  assert.equal(publication.version, row.snapshot.version,
    `${name} publication response names another fetched version`);
  assert.equal(
    publication.referenceSequenceNumber,
    row.snapshot.evidence.referenceSequenceNumber,
    `${name} publication reference sequence differs from fetched storage`,
  );
  if (row.writer === "upstream") {
    assert.equal(publication.kind, "summary-ack",
      `${name} upstream publication is not a summary acknowledgement`);
    const acknowledgement = row.raw.sequenced.find(({ sequenceNumber }) =>
      sequenceNumber === publication.acknowledgementSequenceNumber);
    assert.equal(acknowledgement?.type, "summaryAck",
      `${name} acknowledgement sequence is not a summaryAck operation`);
    assert.equal(parse(acknowledgement.contents)?.handle, publication.version,
      `${name} summaryAck identifies another version`);
    assert.equal(publication.response.sequenceNumber,
      publication.acknowledgementSequenceNumber,
    `${name} summary acknowledgement response names another sequence`);
    assert.equal(publication.response.contents?.handle, publication.version,
      `${name} summary acknowledgement response names another version`);
    const proposalSequenceNumber = parse(acknowledgement.contents)
      ?.summaryProposal?.summarySequenceNumber;
    assert.equal(
      publication.response.contents?.summaryProposal?.summarySequenceNumber,
      proposalSequenceNumber,
      `${name} summary acknowledgement response names another proposal`,
    );
    assert.equal(acknowledgement.referenceSequenceNumber, proposalSequenceNumber,
      `${name} summary acknowledgement does not reference its proposal`);
    const proposal = row.raw.sequenced.find(({ sequenceNumber }) =>
      sequenceNumber === proposalSequenceNumber);
    assert.equal(proposal?.type, "summarize",
      `${name} summary proposal is not a summarize operation`);
    assert(typeof proposal.clientId === "string" && proposal.clientId.length > 0,
      `${name} summarize proposal lacks its client identity`);
    assert(Number.isSafeInteger(proposal.clientSequenceNumber)
      && proposal.clientSequenceNumber > 0,
    `${name} summarize proposal lacks its client sequence identity`);
    assert.equal(proposal.referenceSequenceNumber,
      publication.referenceSequenceNumber,
    `${name} summarize proposal names another reference sequence`);
  } else {
    assert.equal(publication.kind, "native-publication-response",
      `${name} native publication was misclassified as an acknowledgement`);
    assert.equal(publication.response.version, publication.version,
      `${name} native publication response names another version`);
    assert.equal(
      publication.response.snapshotSequenceNumber,
      publication.referenceSequenceNumber,
      `${name} native publication response names another reference sequence`,
    );
    assert.equal("acknowledgementSequenceNumber" in publication, false,
      `${name} native publication invented a summary acknowledgement`);
  }
  assert.equal(snapshotSequence(artifactSnapshot), publication.referenceSequenceNumber,
    `${name} fetched snapshot has another reference sequence`);
}

function validatePeerEvidence(name, row) {
  const expectedImplementations = requiredPeerImplementations(row.writer);
  assert.deepEqual(
    [...row.peer.expectedImplementations].sort(),
    [...expectedImplementations].sort(),
    `${name} peer implementation policy differs`,
  );
  assert.deepEqual(
    Object.keys(row.peer.observations).sort(),
    [...expectedImplementations].sort(),
    `${name} peer implementation coverage differs`,
  );
  for (const [implementation, observation] of Object.entries(row.peer.observations)) {
    assert.deepEqual(observation.graph, row.graph,
      `${name} ${implementation} loaded graph edges differ`);
    for (const [target, expected] of Object.entries(row.targets)) {
      assert.equal(observation.targets[target]?.path, expected.path,
        `${name} ${implementation} target path differs for ${target}`);
      if (observation.targets[target]?.attributes !== undefined) {
        assert.deepEqual(
          observation.targets[target].attributes,
          expected.attributes,
          `${name} ${implementation} attributes differ for ${target}`,
        );
      }

    }
    assert.equal(observation.values.map, row.local.mapValue,
      `${name} ${implementation} map value differs`);
    if (name !== "handleValues") {
      assert.equal(observation.values.tree, row.local.treeLabel,
        `${name} ${implementation} tree value differs`);
      const removed = observation.values.removed?.present
        ?? observation.values.removed;
      assert.equal(removed, false,
        `${name} ${implementation} removed binding remains visible`);
    }
    if (name === "datastoreAttachment") {
      assert.equal(
        observation.values.additional,
        `${row.raw.intent.label}-visible`,
        `${name} ${implementation} additional-channel value differs`,
      );
    }
  }
}

function requiredPeerImplementations(writer) {
  assert(writers.includes(writer), `Unknown lifecycle writer: ${writer}`);
  return writers.filter(
    (implementation) =>
      implementation === "upstream" || implementation !== writer,
  );
}

function requiredSectionWriters(name, selection, diagnosticWriter) {
  assert(selection && typeof selection === "object",
    `${name} section lacks an intentional writer selection`);
  if (diagnosticWriter === undefined) {
    assert.equal(selection.kind, "all",
      `${name} complete section writer selection changed`);
    return writers;
  }
  assert(writers.includes(diagnosticWriter),
    `${name} diagnostic selected an unknown writer`);
  assert.deepEqual(
    selection,
    { kind: "writer", writer: diagnosticWriter },
    `${name} diagnostic writer selection changed`,
  );
  return [diagnosticWriter];
}

function numericStableId(value) {
  const uuid = BigInt(`0x${value.replaceAll("-", "")}`);
  const upper = 0xffffffffffffn << 76n;
  const middle = 0xfffn << 64n;
  const lower = 0x3fffffffffffffffn;
  return ((uuid & upper) >> 6n) | ((uuid & middle) >> 2n) | (uuid & lower);
}

function compactAttachmentNumber(id, prefix) {
  const alphabet = Array.from({ length: 64 }, (_unused, digit) =>
    encodeCompactIdToString(digit)).join("");
  let number = -1;
  for (const character of id.slice(prefix.length)) {
    const digit = alphabet.indexOf(character);
    assert(digit >= 0, "Attachment compact identity contains an invalid digit");
    number = (number + 1) * 64 + digit;
    assert(Number.isSafeInteger(number), "Attachment compact identity is too large");
  }
  assert(number >= 0 && encodeCompactIdToString(number, prefix) === id,
    "Attachment compact identity is not canonical");
  return number;
}

function validateCompressorAllocations(name, row, artifactSnapshot) {
  const { compressor } = decodedSnapshotCompressor(artifactSnapshot);
  const allocations = row.raw.dependencies.allocations;
  const generationOf = (stable, originatorId) => {
    const offset = numericStableId(stable) - numericStableId(originatorId);
    assert(offset >= 0n && offset < BigInt(Number.MAX_SAFE_INTEGER),
      `${name} compressor revision has another originator identity`);
    return Number(offset) + 1;
  };
  const finalizedGeneration = (revision, originatorId) => {
    assert(Number.isSafeInteger(revision),
      `${name} compressor revision lacks an identity`);
    assert(typeof originatorId === "string",
      `${name} compressor revision originator identity is missing`);
    let stable;
    assert.doesNotThrow(() => {
      const finalized = compressor.normalizeToSessionSpace(revision, originatorId);
      assert(finalized >= 0, "Published identity is not finalized");
      stable = compressor.decompress(finalized);
    }, `${name} compressor revision lacks its finalized originator identity`);
    const generation = generationOf(stable, originatorId);
    if (revision < 0) {
      assert.equal(generation, -revision,
        `${name} compressor revision has another finalized identity`);
    }
    return generation;
  };
  const requireEarlierAllocation = (originatorId, generation, use) => {
    assert(allocations.some((allocation) =>
      allocation.sessionId === originatorId
        && generation >= allocation.first && generation <= allocation.last
        && comparePosition(allocation, use) < 0),
    `${name} allocation must precede use of its exact identity context`);
  };
  for (const allocation of allocations) {
    assert(Number.isSafeInteger(allocation.innerIndex)
      && allocation.innerIndex >= 0 && allocation.first > 0
      && allocation.last >= allocation.first,
    `${name} allocation identity context is invalid`);
    finalizedGeneration(-allocation.first, allocation.sessionId);
    finalizedGeneration(-allocation.last, allocation.sessionId);
  }
  for (const commit of row.raw.dependencies.commits) {
    const generation = finalizedGeneration(commit.revision, commit.originatorId);
    requireEarlierAllocation(commit.originatorId, generation, commit);
  }
  for (const message of row.raw.sequenced) {
    for (const [innerIndex, { contents }] of operationItems(message).entries()) {
      const use = position(message.sequenceNumber, innerIndex);
      for (const attachment of matchingObjects(contents, ({ type }) =>
        type === "attach")) {
        const { id, snapshot: attachedSnapshot } =
          attachment.content ?? attachment.contents;
        let stable;
        if (row.writer === "upstream") {
          if (/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/.test(id)) {
            stable = id;
          } else if (id.startsWith("_") || attachment.contents !== undefined) {
            const number = compactAttachmentNumber(id, id.startsWith("_") ? "_" : "");
            // Odd IDs use the document compressor; even IDs are detached-local names.
            if (number % 2 === 1) {
              stable = compressor.decompress((number - 1) / 2);
            }
          }
        }
        if (stable !== undefined) {
          const finalized = compressor.tryRecompress(stable);
          assert(Number.isSafeInteger(finalized) && finalized >= 0,
            `${name} attachment lacks its finalized compressor identity`);
          const allocation = allocations.find(({ sessionId, first, last }) => {
            const offset = numericStableId(stable) - numericStableId(sessionId);
            return offset >= BigInt(first - 1) && offset < BigInt(last);
          });
          assert(allocation, `${name} attachment allocation identity context is missing`);
          assert.equal(compressor.decompress(finalized), stable,
            `${name} attachment compressor identity differs`);
          requireEarlierAllocation(
            allocation.sessionId,
            generationOf(stable, allocation.sessionId),
            use,
          );
        }
        for (const commit of matchingObjects(attachedSnapshot, (value) =>
          Number.isSafeInteger(value.revision)
            && typeof (value.sessionId ?? value.originatorId) === "string")) {
          const originatorId = commit.sessionId ?? commit.originatorId;
          const generation = finalizedGeneration(commit.revision, originatorId);
          requireEarlierAllocation(originatorId, generation, use);
        }
      }
    }
  }
}

function validateStoredEvidence(name, row, artifactSnapshot) {
  const measured = snapshotEvidence(artifactSnapshot, row.targets);
  assert.deepEqual(row.snapshot.evidence, measured,
    `${name} snapshot descriptor differs from persisted bytes`);
  assert.equal(row.snapshot.treeSha256, hash(artifactSnapshot.tree),
    `${name} snapshot tree hash differs from persisted bytes`);
  assert.deepEqual(
    row.snapshot.blobs,
    Object.fromEntries(Object.entries(artifactSnapshot.blobs).map(
      ([id, bytes]) => [id, hash(Buffer.from(bytes, "base64"))],
    )),
    `${name} snapshot blob hashes differ from persisted bytes`,
  );
  assert.equal(measured.compressor.formatVersion, 2,
    `${name} fetched compressor format changed`);
  validateCompressorAllocations(name, row, artifactSnapshot);
  const metadata = snapshotMetadata(artifactSnapshot);
  assert.equal(
    metadata.documentSchema?.info?.minVersionForCollab,
    oldestSupportedClient,
    `${name} persisted minimum collaboration version differs`,
  );
  assert.equal(metadata.createContainerRuntimeVersion, reference.version,
    `${name} persisted container runtime version differs`);
  assert.deepEqual(snapshotFactory(artifactSnapshot, "/A"), {
    packagePath: [handleServiceStore.type],
    summaryFormatVersion: 2,
    isRootDataStore: true,
  }, `${name} primary datastore factory metadata differs`);
  const expected = expectedSnapshotGraph(name, row.graph);
  for (const [target, evidence] of Object.entries(measured.targets)) {
    assert.deepEqual(evidence.attributes, row.targets[target].attributes,
      `${name} persisted attributes differ for ${target}`);
  }
  assert.deepEqual({
    optional: measured.main.graph.optional,
    links: measured.main.graph.links,
    sequence: measured.main.graph.sequence,
  }, expected.main, `${name} persisted main-tree graph differs`);
  assert.deepEqual(measured.targets.map.graph, {
    value: row.local.mapValue,
    ...(expected.map ?? {}),
  }, `${name} persisted map value or graph differs`);
  if (name !== "handleValues") {
    assert.equal(measured.targets.tree.graph.optional, expected.tree.optional,
      `${name} persisted mutual tree edge differs`);
  }
  if (name === "datastoreAttachment") {
    assert.deepEqual(measured.targets.datastore.graph, {
      map: expected.entry.map,
      tree: expected.entry.tree,
      additional: expected.entry.additional,
    }, `${name} persisted datastore entry graph differs`);
    assert.equal(measured.targets.additional.graph.value,
      row.peer.observations.upstream.values.additional,
    `${name} persisted additional-channel value differs`);
    assert.deepEqual(snapshotFactory(artifactSnapshot, row.targets.datastore.path), {
      packagePath: [handleGraphStore.type],
      summaryFormatVersion: 2,
      isRootDataStore: false,
    }, `${name} persisted factory differs from the pinned contract`);
  }
}

async function validateTransactionBranchRow(name, row, artifacts) {
  assert.equal(row.formatVersion, 1, `${name} row format changed`);
  assert.equal(row.runId, artifacts.runId, `${name} row run identity changed`);
  validateContract(row.contract, `${name} row`);
  assert.equal(row.factory, handleServiceStore.type,
    `${name} primary factory differs from the pinned contract`);
  assert.deepEqual(
    Object.keys(row.targets).sort(),
    [
      "aborted",
      "branch",
      "disposed",
      "document",
      "dropped",
      "nested",
      "successful",
      "undo",
    ],
    `${name} attached target identity set changed`,
  );
  validateTransportBinding(name, row);
  assert.equal(row.artifacts.length, 1, `${name} row lacks one raw artifact`);
  const descriptor = row.artifacts[0];
  const registered = artifacts.files[descriptor.path];
  assert(registered, `${name} raw artifact is missing: ${descriptor.path}`);
  assert.equal(registered.sha256, descriptor.sha256,
    `${name} raw artifact digest changed`);
  const bytes = await readFile(join(artifacts.root, descriptor.path));
  assert.equal(hash(bytes), descriptor.sha256,
    `${name} persisted artifact bytes changed`);
  const artifact = JSON.parse(bytes.toString("utf8"));
  assert.equal(artifact.runId, row.runId, `${name} artifact run identity changed`);
  assert.equal(artifact.documentId, row.documentId,
    `${name} artifact document identity changed`);
  validateContract(artifact.contract, `${name} artifact`);
  assert.deepEqual(artifact.raw, jsonClone(row.raw),
    `${name} report raw evidence differs from its persisted artifact`);
  assert.deepEqual(artifact.targets, row.targets,
    `${name} artifact target identities differ`);
  assert.deepEqual(artifact.graph, row.graph,
    `${name} artifact graph contract differs`);
  assert.deepEqual(artifact.peers, row.peer.observations,
    `${name} artifact peer observations differ`);
  assert.deepEqual(artifact.history, row.history,
    `${name} artifact history evidence differs`);
  validatePublication(name, row, artifact.snapshot);
  validateCompressorAllocations(name, row, artifact.snapshot);
  const metadata = snapshotMetadata(artifact.snapshot);
  assert.equal(metadata.createContainerRuntimeVersion, reference.version,
    `${name} persisted runtime metadata version differs`);
  assert.equal(
    metadata.documentSchema.info.minVersionForCollab,
    oldestSupportedClient,
    `${name} persisted minimum client differs`,
  );
  for (const [target, expected] of Object.entries(row.targets)) {
    assert.deepEqual(
      row.snapshot.evidence.targets[target]?.attributes,
      expected.attributes,
      `${name} persisted attributes differ for ${target}`,
    );
  }

  const expectedSteps = [
    "successful-transaction",
    "aborted-transaction",
    "nested-transaction",
    "active-target",
    "branch-before-merge",
    "branch-after-merge",
    "branch-dropped",
    "branch-disposal",
    "handle-undo-peer-edit",
  ];
  const active = row.history.activeTarget;
  assert.deepEqual(row.history.steps.map(({ id }) => id), expectedSteps,
    `${name} history step coverage changed`);
  const byId = Object.fromEntries(row.history.steps.map((step) => [step.id, step]));
  const successful = byId["successful-transaction"];
  const aborted = byId["aborted-transaction"];
  const nested = byId["nested-transaction"];
  if (row.writer === "upstream") {
    assert.equal(
      successful.transaction?.callbackResult,
      "successful-callback",
      `${name} successful transaction callback result changed`,
    );
  } else {
    assert.equal(successful.transaction?.outcome, "committed",
      `${name} successful handle transaction did not commit`);
  }
  assert(
    aborted.outcome === "aborted"
      || aborted.transaction?.outcome === "aborted",
    `${name} aborted handle transaction did not abort`,
  );
  assert.equal(aborted.targetValue, "survives-rollback",
    `${name} aborted transaction lost its independent target edit`);
  if (row.writer === "upstream") {
    assert.deepEqual(nested.transaction, {
      outerResult: "nested-outer-callback",
      innerResult: "nested-inner-callback",
    }, `${name} nested transaction callback result changed`);
  } else {
    assert.equal(nested.transaction?.outcome, "committed",
      `${name} nested handle transaction did not commit`);
  }
  assert.equal(
    row.raw.dependencies.commits.length > 0,
    true,
    `${name} actual tree revisions are missing`,
  );
  assert.equal(
    new Set(row.raw.dependencies.commits.map(({ revision }) => revision)).size,
    row.raw.dependencies.commits.length,
    `${name} tree revision identities are not unique`,
  );

  const beforeMerge = byId["branch-before-merge"];
  const afterMerge = byId["branch-after-merge"];
  assert.equal(beforeMerge.target, row.targets.branch.path,
    `${name} branch edit names another target`);
  if (row.writer === "upstream") {
    const validateUpstreamTransaction = (step, label) => {
      assert(Array.isArray(step.revisions) && step.revisions.length > 0,
        `${name} ${label} transaction lacks an actual revision`);
      assert.equal(new Set(step.revisions).size, step.revisions.length,
        `${name} ${label} transaction revisions are not unique`);
      const knownRevisions = new Set(
        row.raw.dependencies.commits.map(({ revision }) => revision),
      );
      assert.equal(step.revisions.every((revision) => knownRevisions.has(revision)),
        true, `${name} ${label} transaction revision is absent from transport`);
      assert.equal(step.settlements.length, step.revisions.length,
        `${name} ${label} transaction lacks its actual settlement`);
      assert.deepEqual(
        step.settlements.map(({ revision }) => revision),
        step.revisions,
        `${name} ${label} transaction settlement names another revision`,
      );
      assert.equal(step.settlements.every((settlement) =>
        Number.isSafeInteger(settlement.sequenceNumber)
          && Number.isSafeInteger(settlement.clientSequenceNumber)
          && Number.isSafeInteger(settlement.referenceSequenceNumber)),
      true, `${name} ${label} transaction settlement lacks wire identity`);
      const event = step.events.find(({ acquired }) => acquired);
      assert(event, `${name} ${label} transaction lacks event acquisition`);
      assert.match(event.duplicateError, /same revertible|more than once/i,
        `${name} ${label} transaction allowed duplicate event acquisition`);
      assert.equal(event.disposed, true,
        `${name} ${label} transaction inverse disposal was not observed`);
      assert.equal(event.status, "Disposed",
        `${name} ${label} transaction inverse disposal left a valid handle`);
    };
    validateUpstreamTransaction(successful, "successful");
    validateUpstreamTransaction(nested, "nested");
    assert.equal(beforeMerge.transportDelta, 0,
      `${name} branch-only edit reached document transport`);
    assert.equal(beforeMerge.events.some(({ factoryAvailable, acquired }) =>
      factoryAvailable === true && acquired === true), true,
      `${name} branch edit lacks its actual inverse factory`);
    assert.equal(afterMerge.main.link, row.targets.branch.path,
      `${name} merged branch handle is absent from the document`);
  } else {
    const { compressor } = decodedSnapshotCompressor(artifact.snapshot);
    const stableWireRevisions = row.raw.dependencies.commits
      .map(({ revision }) => Number(revision))
      .filter(Number.isSafeInteger)
      .map((revision) => compressor.decompress(revision));
    const successfulCommit = successful.checkpoint.commits.find(
      ({ type }) => type === "commit",
    );
    assert(successfulCommit,
      `${name} successful transaction lacks its actual commit event`);
    assert.equal(successfulCommit.handleAcquired, true,
      `${name} successful transaction lacks actual event acquisition`);
    assert.equal(successful.inverse.factoryAvailable, true,
      `${name} successful transaction lacks its actual inverse factory`);
    assert.equal(typeof successful.inverse.revision, "string",
      `${name} successful transaction lacks its actual revision`);
    assert.equal(successfulCommit?.actionId, successful.inverse.actionId,
      `${name} successful transaction event names another action`);
    assert.equal(successfulCommit?.eventId, successful.inverse.eventId,
      `${name} successful transaction event names another factory`);
    assert.equal(stableWireRevisions.includes(successful.inverse.revision), true,
      `${name} successful transaction revision is absent from transport`);
    assert.equal(beforeMerge.edit.outboundCount, 0,
      `${name} branch-only edit reached document transport`);
    assert.equal(beforeMerge.inverse.factoryAvailable, true,
      `${name} branch edit lacks its actual inverse factory`);
    assert.equal(afterMerge.merge.disposed, true,
      `${name} merged branch lifetime did not end`);
    assert.equal(typeof afterMerge.inverse.revision, "string",
      `${name} merged branch lacks an actual document revision`);
    assert.equal(afterMerge.inverse.factoryAvailable, true,
      `${name} merged branch lacks its actual inverse factory`);
    const mergedCommit = afterMerge.checkpoint.commits.find(
      ({ type }) => type === "commit",
    );
    assert.equal(mergedCommit?.actionId, afterMerge.inverse.actionId,
      `${name} merged branch event names another action`);
    assert.equal(mergedCommit?.eventId, afterMerge.inverse.eventId,
      `${name} merged branch event names another factory`);
    assert.equal(mergedCommit?.handleAcquired, true,
      `${name} merged branch lacks actual event acquisition`);
    assert.equal(stableWireRevisions.includes(afterMerge.inverse.revision), true,
      `${name} merged branch revision is not owned by the document compressor`);
    assert.equal(afterMerge.checkpoint.commits.some(({ type, outcome }) =>
      type === "settlement" && outcome === "FullyApplied"),
    true, `${name} merged branch lacks its actual settlement`);
  }
  assert.equal(beforeMerge.document, row.targets.document.path,
    `${name} branch handle names another document`);
  assert.equal(beforeMerge.marker.url ?? beforeMerge.marker.absolutePath,
    row.targets.document.path,
  `${name} branch marker does not serialize the owning document channel`);

  for (const id of ["branch-dropped", "branch-disposal"]) {
    const step = byId[id];
    assert.equal(
      step.target,
      row.targets[id === "branch-dropped" ? "dropped" : "disposed"].path,
      `${name} ${id} cleanup publication names another target`,
    );
    if (row.writer === "upstream") {
      assert.equal(step.transportDelta, 0,
        `${name} ${id} reached document transport`);
      assert.equal(step.inverse.acquired, true,
        `${name} ${id} lacks event-scoped inverse acquisition`);
      if (id === "branch-dropped") {
        assert.equal(step.discard.disposedSameHandle, true,
          `${name} branch-dropped discard did not dispose its actual inverse`);
        assert.equal(step.discard.afterStatus, "Disposed",
          `${name} branch-dropped discard left its inverse valid`);
        assert.notEqual(step.discard.branch.link, step.target,
          `${name} branch-dropped discard retained the branch edit`);
        assert.equal(step.discard.events.some(({ kind }) => kind === "Undo"), true,
          `${name} branch-dropped discard lacks its actual Undo event`);
      } else {
        assert.equal("discard" in step, false,
          `${name} branch-disposal was misclassified as an edit discard`);
        assert.equal(step.branchBeforeCleanup.link, step.target,
          `${name} branch-disposal did not retain its edit until disposal`);
      }
    } else {
      assert.equal(step.edit.outboundCount, 0,
        `${name} ${id} reached document transport`);
      assert.equal(step.inverse.factoryAvailable, true,
        `${name} ${id} lacks event-scoped inverse acquisition`);
      assert.equal(step.disposed.status, "BranchDisposed",
        `${name} ${id} lifetime did not end`);
      if (id === "branch-dropped") {
        assert.equal(step.discard.authoredKind, "Undo",
          `${name} branch-dropped discard did not author an Undo commit`);
        assert.equal(step.discard.status, "Disposed",
          `${name} branch-dropped discard left its inverse valid`);
      } else {
        assert.equal("discard" in step, false,
          `${name} branch-disposal was misclassified as an edit discard`);
      }
    }
  }

  const undo = byId["handle-undo-peer-edit"];
  assert.equal(undo.target, row.targets.undo.path,
    `${name} insertion inverse names another target`);
  assert.equal(undo.peer.target, row.targets.undo.path,
    `${name} independent peer edited another target`);
  assert.equal(undo.peer.value, "survives-insertion-undo",
    `${name} independent peer target edit was lost after insertion undo`);
  if (row.writer === "upstream") {
    assert.equal(undo.inverse.event.factoryAvailable, true,
      `${name} insertion event lacks its actual inverse factory`);
    assert.equal(undo.inverse.event.acquired, true,
      `${name} insertion inverse was not acquired from its event`);
    assert.equal(undo.inverse.disposedSameHandle, true,
      `${name} insertion disposal callback received another inverse`);
    assert.notEqual(undo.inverse.beforeStatus, undo.inverse.afterStatus,
      `${name} insertion inverse lifetime did not change`);
  } else {
    assert.equal(undo.inverse.retained.factoryAvailable, true,
      `${name} insertion inverse factory was not acquired`);
    assert.equal(undo.inverse.reverted.authoredKind, "Undo",
      `${name} insertion inverse did not author an Undo commit`);
    assert.equal(undo.inverse.reverted.submittedRevisions.length, 1,
      `${name} insertion inverse did not submit one actual revision`);
  }
  for (const [implementation, peer] of Object.entries(row.peer.observations)) {
    assert.equal(peer.document, row.targets.document.path,
      `${name} ${implementation} resolved another document`);
    assert.equal(peer.targets.undo.path, row.targets.undo.path,
      `${name} ${implementation} resolved another undo target`);
    assert.equal(peer.targets.undo.peer, "survives-insertion-undo",
      `${name} ${implementation} lost the peer target edit`);
  }
  const expectedPeers = requiredPeerImplementations(row.writer);
  assert.deepEqual(
    [...row.peer.expectedImplementations].sort(),
    [...expectedPeers].sort(),
    `${name} peer implementation policy differs`,
  );
  assert.deepEqual(
    Object.keys(row.peer.observations).sort(),
    [...expectedPeers].sort(),
    `${name} peer implementation coverage differs`,
  );

  assert.notEqual(active.documentId, row.documentId,
    `${name} active-target exception reused the history document`);
  if (row.writer === "upstream") {
    assert.equal(
      active.exception,
      "pinned-upstream-invalidates-after-attachment-attempt",
      `${name} upstream active-target exception changed`,
    );
    assert.match(active.error, /transaction is in progress/i,
      `${name} upstream active-target attempt did not refuse`);
    assert.equal(active.transactionEntered, true,
      `${name} upstream active-target transaction was not entered`);
    assert.equal(active.target.attachedBefore, false,
      `${name} upstream active target started attached`);
    assert.equal(active.target.attachedAfter, true,
      `${name} pinned upstream failure side effect was not measured`);
    assert(active.raw.submitted.length > 0 && active.raw.sequenced.length > 0,
      `${name} upstream active-target side effects lack raw transport`);
  } else {
    assert.equal(active.exception, "native-atomic-preflight-refusal",
      `${name} native active-target exception changed`);
    assert.equal(active.refusal.refused, true,
      `${name} native active-target preflight did not refuse`);
    assert.match(active.refusal.error, /transaction|another tree/i,
      `${name} native active-target refusal lacks its measured reason`);
    assert.equal(active.refusal.after, active.refusal.before,
      `${name} native preflight mutated runtime state while the target was active`);
    assert.deepEqual(active.after.runtime, active.before.runtime,
      `${name} active callback runtime fingerprint changed`);
    assert.deepEqual(active.after.parent, active.before.parent,
      `${name} native refusal changed the parent checkout`);
    assert.deepEqual(active.after.target, active.before.target,
      `${name} native refusal changed the target checkout`);
    assert.deepEqual(active.after.checkpoint, active.before.checkpoint,
      `${name} native refusal changed event or commit queues`);
    assert.deepEqual(active.after.submitted, active.before.submitted,
      `${name} native refusal reached transport`);
    assert.equal(active.after.historyCount, active.before.historyCount,
      `${name} native refusal changed service history`);
  }
}

async function validateRow(name, row, artifacts) {
  if (name === "handleTransactionBranch") {
    return validateTransactionBranchRow(name, row, artifacts);
  }
  assert.equal(row.formatVersion, 1, `${name} row format changed`);
  assert.equal(row.runId, artifacts.runId, `${name} row run identity changed`);
  validateContract(row.contract, `${name} row`);
  assert(Array.isArray(row.raw.submitted) && row.raw.submitted.length > 0,
    `${name} raw submitted attach/reference evidence is missing`);
  assert(Array.isArray(row.raw.sequenced) && row.raw.sequenced.length > 0,
    `${name} sequenced service delta evidence is missing`);
  assert.equal(row.raw.historyAfterLocalCount, row.raw.historyBeforeCount,
    `${name} detached local edits reached transport before attachment`);
  assert(row.raw.sequenced.some(({ clientId }) => row.writerClientIds.includes(clientId)),
    `${name} service history lacks the writer client identity`);
  for (const [target, expected] of Object.entries(row.targets)) {
    assert.deepEqual(
      expected.attributes,
      target === "tree" ? channelAttributes.tree : channelAttributes.map,
      `${name} independently pinned attributes differ for ${target}`,
    );
  }
  if (name === "datastoreAttachment") {
    assert.equal(row.factory, handleGraphStore.type,
      "datastoreAttachment factory differs from the declared graph factory");
  } else {
    assert.equal(row.factory, handleServiceStore.type,
      `${name} primary factory differs from the pinned contract`);
  }
  assert.deepEqual(row.graph, expectedGraph(name, row.targets),
    `${name} expected graph differs from target identities`);
  validateTransportBinding(name, row);
  validatePeerEvidence(name, row);
  assert.equal(row.artifacts.length, 1, `${name} row lacks one raw artifact`);
  const descriptor = row.artifacts[0];
  const registered = artifacts.files[descriptor.path];
  assert(registered, `${name} raw artifact is missing: ${descriptor.path}`);
  assert.equal(registered.sha256, descriptor.sha256,
    `${name} raw artifact digest changed`);
  const bytes = await readFile(join(artifacts.root, descriptor.path));
  assert.equal(hash(bytes), descriptor.sha256,
    `${name} persisted artifact bytes changed`);
  const artifact = JSON.parse(bytes.toString("utf8"));
  assert.equal(artifact.runId, row.runId,
    `${name} artifact run identity changed`);
  assert.equal(artifact.documentId, row.documentId,
    `${name} artifact document identity changed`);
  validateContract(artifact.contract, `${name} artifact`);
  assert.deepEqual(artifact.raw, jsonClone(row.raw),
    `${name} report raw evidence differs from its persisted artifact`);
  assert.deepEqual(artifact.targets, row.targets,
    `${name} artifact target identities differ`);
  assert.deepEqual(artifact.graph, row.graph,
    `${name} artifact graph contract differs`);
  assert.deepEqual(artifact.peers, row.peer.observations,
    `${name} artifact peer observations differ`);
  validatePublication(name, row, artifact.snapshot);
  validateStoredEvidence(name, row, artifact.snapshot);
}

export async function validateLifecycleSection(
  name,
  section,
  artifacts,
  { diagnosticWriter } = {},
) {
  assert(liveSections.includes(name), `Lifecycle section is not implemented: ${name}`);
  assert(section && typeof section === "object", `${name} section is missing`);
  assert.equal(section.name, name, `${name} section name changed`);
  assert.equal(section.runId, artifacts.runId, `${name} section run identity changed`);
  validateContract(section.contract, `${name} section`);
  assert.equal(section.skipped, false, `${name} section is skipped`);
  const requiredWriters = requiredSectionWriters(
    name,
    section.selection,
    diagnosticWriter,
  );
  assert(Array.isArray(section.expectedWriters),
    `${name} section lacks declared writers`);
  assert.deepEqual(
    [...section.expectedWriters].sort(),
    [...requiredWriters].sort(),
    `${name} section declared writers differ from its intentional selection`,
  );
  assert.deepEqual(
    section.rows.map(({ writer }) => writer).sort(),
    [...requiredWriters].sort(),
    `${name} required writer coverage differs`,
  );
  for (const row of section.rows) {
    assert.equal(row.runId, section.runId, `${name} row run identity changed`);
    await validateRow(name, row, artifacts);
  }
  return section;
}

export async function validateLifecycleReport(report, artifacts) {
  assert(report && typeof report === "object", "Lifecycle report is missing");
  assert.equal(report.formatVersion, 1, "Lifecycle report format changed");
  assert.equal(report.runId, artifacts.runId, "Lifecycle report run identity changed");
  validateContract(report.contract, "Lifecycle report");
  assert.deepEqual(
    Object.keys(report.sections ?? {}).sort(),
    [...sections].sort(),
    "Lifecycle report must contain all seven required sections",
  );
  for (const name of sections) {
    assert.notEqual(report.sections[name]?.skipped, true,
      `Lifecycle required section is skipped: ${name}`);
    await validateLifecycleSection(name, report.sections[name], artifacts);
  }
  return report;
}

export async function runLifecycleInterop({
  bounded = false,
  config = serviceConfig(),
  constructors = { nativeAdapter, openSession },
  output = join(import.meta.dirname, ".output/lifecycle", randomUUID()),
  scenario,
} = {}) {
  const runId = randomUUID();
  const selected = scenario === undefined
    ? null
    : scenario.match(/^(handleValues|channelAttachment|datastoreAttachment|handleTransactionBranch):(upstream|javascript|erlang)$/);
  if (scenario !== undefined) {
    assert(selected, "Lifecycle scenario must be <section>:<writer>");
  }
  assert(
    selected || bounded === true,
    "Full seven-section lifecycle execution is not implemented",
  );
  const selectedSections = selected ? [selected[1]] : liveSections;
  const selectedWriters = selected ? [selected[2]] : writers;
  const selection = selected
    ? { kind: "writer", writer: selected[2] }
    : { kind: "all" };
  const context = {
    artifacts: {
      formatVersion: 1,
      runId,
      root: resolve(output),
      files: {},
    },
    constructors,
    output: resolve(output),
    runId,
  };
  await mkdir(context.output, { recursive: true });
  const report = {
    formatVersion: 1,
    runId,
    contract,
    bounded: true,
    sections: {},
  };
  for (const name of selectedSections) {
    const section = {
      name,
      runId,
      contract,
      skipped: false,
      selection,
      expectedWriters: selectedWriters,
      rows: [],
    };
    for (const writer of selectedWriters) {
      const row = await runRow(config, context, name, writer);
      row.runId = runId;
      section.rows.push(row);
    }
    const validationContext = selected
      ? { diagnosticWriter: selected[2] }
      : {};
    await validateLifecycleSection(
      name,
      section,
      context.artifacts,
      validationContext,
    );
    report.sections[name] = section;
  }
  await writeFile(
    join(context.output, "report.json"),
    `${JSON.stringify(report, null, 2)}\n`,
    { mode: 0o600 },
  );
  return {
    report,
    artifacts: context.artifacts,
    output: context.output,
    validationContext: selected
      ? { diagnosticWriter: selected[2] }
      : {},
  };
}

async function main(args) {
  const { values } = parseArgs({
    args,
    options: {
      "local-floodgate": { type: "boolean", default: false },
      output: { type: "string" },
      scenario: { type: "string" },
    },
  });
  assert(values.scenario,
    "Bounded Task 8 execution requires --scenario; full seven-section execution is not implemented");
  const run = (config) => runLifecycleInterop({
    config,
    ...(values.output ? { output: values.output } : {}),
    scenario: values.scenario,
  });
  const captured = values["local-floodgate"]
    ? await withLocalFloodgate(run)
    : await run(serviceConfig());
  console.log(JSON.stringify({
    runId: captured.report.runId,
    bounded: true,
    sections: Object.keys(captured.report.sections),
    writers: Object.values(captured.report.sections)
      .flatMap(({ rows }) => rows.map(({ writer }) => writer)),
    output: captured.output,
  }, null, 2));
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
