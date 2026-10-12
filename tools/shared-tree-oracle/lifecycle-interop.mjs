import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { readFile, mkdir, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { parseArgs } from "node:util";
import { deserializeIdCompressor } from "@fluidframework/id-compressor/internal";
import { SummaryType } from "@fluidframework/driver-definitions/internal";
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
import { lifecycleDecodeFieldBatch } from "./generate.mjs";
import { storageResponseIdentity } from "./delivery-gate.mjs";

const sections = [
  "handleValues",
  "channelAttachment",
  "datastoreAttachment",
  "handleTransactionBranch",
  "handleRetention",
  "handleReconnect",
  "handleReloadMatrix",
];
const liveSections = sections.slice(0, 5);
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
    minimumSequenceNumber: message.minimumSequenceNumber,
    timestamp: message.timestamp,
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

function transportOperationIdentity({
  clientId, clientSequenceNumber, referenceSequenceNumber, contents, metadata,
}) {
  return {
    clientId, clientSequenceNumber, referenceSequenceNumber,
    contents: parse(contents), metadata: jsonClone(metadata),
  };
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

function snapshotGc(snapshotValue) {
  const gc = snapshotValue.tree.trees?.gc
    ?? snapshotValue.tree.trees?.[".app"]?.trees?.gc;
  return decodedBlob(snapshotValue, gc, "__gc_root");
}

function snapshotComponents(snapshotValue) {
  const components = [];
  const visit = (node, path = "") => {
    if (node?.blobs?.[".component"] !== undefined) {
      components.push({
        path,
        value: decodedBlob(snapshotValue, node, ".component"),
      });
    }
    for (const [name, child] of Object.entries(node?.trees ?? {})) {
      visit(child, `${path}/${name}`);
    }
  };
  visit(snapshotValue.tree);
  return components;
}

function fieldBatchHandleMarkers(batch, keys, label) {
  const markers = [];
  const visit = (node) => {
    if (node.type === "com.fluidframework.leaf.handle") {
      assert.equal(node.fields.size, 0, `${label} retained handle has fields`);
      markers.push({ type: "__fluid_handle__", url: handlePath(node.value) });
    }
    for (const field of node.fields.values()) for (const child of field) visit(child);
  };
  for (const field of lifecycleDecodeFieldBatch(batch, keys, label).values()) {
    for (const node of field) visit(node);
  }
  return markers;
}

function retainedHistoryCommit(commit) {
  assert(Number.isSafeInteger(commit.revision)
    && Number.isSafeInteger(commit.sequenceNumber)
    && typeof commit.sessionId === "string"
    && Array.isArray(commit.change),
  "Retained history commit lacks its session, sequence or change identity");
  return {
    revision: commit.revision,
    sessionId: commit.sessionId,
    sequenceNumber: commit.sequenceNumber,
    ...(commit.indexInBatch === undefined ? {} : { indexInBatch: commit.indexInBatch }),
    changeSha256: hash(commit.change),
  };
}

function retainedBlobMarkers(decoded, path) {
  if (/Forest\/contents$/i.test(path)) {
    return fieldBatchHandleMarkers(decoded.fields, decoded.keys, `Retained ${path}`);
  }
  if (!/EditManager\/String$/i.test(path)) return [];
  assert.deepEqual(Object.keys(decoded).sort(), ["branches", "trunk", "version"],
    "Retained history has unrelated properties");
  const markers = [];
  for (const commit of decoded.trunk) {
    retainedHistoryCommit(commit);
    assert(Object.keys(commit).every((key) =>
      ["revision", "sessionId", "sequenceNumber", "indexInBatch", "change", "customMetadata"].includes(key)),
    "Retained history commit has unrelated properties");
    for (const component of commit.change) {
      assert(component.data && Array.isArray(component.data.changes),
        "Retained history lacks a modular data change");
      for (const kind of ["builds", "refreshers"]) {
        const batch = component.data[kind];
        if (batch === undefined) continue;
        assert(Array.isArray(batch.builds) && Array.isArray(batch.trees?.data),
          `Retained history ${kind} lacks its FieldBatch mappings`);
        markers.push(...fieldBatchHandleMarkers(
          batch.trees,
          batch.trees.data.map((_, index) => String(index)),
          `Retained history ${kind}`,
        ));
      }
    }
  }
  return markers;
}

function snapshotRetentionHandles(snapshotValue, treePath, targetPath) {
  const tree = snapshotNode(snapshotValue, treePath);
  const evidence = [];
  const visit = (node, path = "") => {
    for (const [name, id] of Object.entries(node?.blobs ?? {})) {
      const bytes = Buffer.from(snapshotValue.blobs[id], "base64");
      const blobPath = `${path}/${name}`;
      if (/(Forest|Repair|EditManager|Detached)/i.test(blobPath)) {
        const decoded = JSON.parse(bytes.toString("utf8"));
        let kind = "metadata";
        let history = [];
        let branches = [];
        if (/EditManager\/String$/i.test(blobPath)) {
          assert.equal(decoded.version, 7,
            "Stored retained history has another version");
          assert(Array.isArray(decoded.trunk) && Array.isArray(decoded.branches),
            "Stored retained history lacks trunk or branch ancestry");
          kind = "history";
          branches = decoded.branches;
          history = decoded.trunk.map(retainedHistoryCommit);
        } else if (/Forest\/contents$/i.test(blobPath)) {
          assert.equal(decoded.version, 2,
            "Stored retained forest has another version");
          assert(Array.isArray(decoded.fields?.data),
            "Stored retained forest lacks field data");
          kind = "forest";
        } else if (/DetachedFieldIndexBlob$/i.test(blobPath)) {
          assert.equal(decoded.version, 2,
            "Stored detached-field index has another version");
          assert(Array.isArray(decoded.data),
            "Stored detached-field index lacks entries");
          kind = "detached";
        }
        const markers = retainedBlobMarkers(decoded, blobPath);
        evidence.push({
          path: blobPath,
          blobId: id,
          sha256: hash(bytes),
          kind,
          markers,
          history,
          branches,
          targetPresent: markers.some(({ url }) => url === targetPath),
        });
      }
    }
    for (const [name, child] of Object.entries(node?.trees ?? {})) {
      visit(child, `${path}/${name}`);
    }
  };
  visit(tree);
  return evidence;
}

function summaryEntryEvidence(entry) {
  if (entry?.type === SummaryType.Tree) {
    return {
      type: "tree",
      entries: Object.entries(entry.tree).map(([name, child]) =>
        [name, summaryEntryEvidence(child)]),
    };
  }
  if (entry?.type === SummaryType.Blob) {
    const bytes = Buffer.from(entry.content);
    return { type: "blob", base64: bytes.toString("base64") };
  }
  if (entry?.type === SummaryType.Handle) {
    return {
      type: "handle",
      handleType: entry.handleType,
      path: entry.handle,
    };
  }
  assert.fail("Unsupported retention summary entry");
}

function submittedSummaryEvidence(receipts, treeId) {
  assert(Array.isArray(receipts) && receipts.length > 0,
    "Native publication lacks actual upload receipts");
  const blobs = new Map();
  const trees = new Map();
  for (const receipt of receipts) {
    assert.equal(receipt.method, "POST", "Native publication upload has another method");
    assert.equal(receipt.status, 201, "Native publication upload did not succeed");
    for (const direction of ["request", "response"]) {
      assert.equal(typeof receipt[`${direction}Body`], "string",
        `Native publication lacks ${direction} bytes`);
      assert.equal(hash(Buffer.from(receipt[`${direction}Body`], "base64")),
        receipt[`${direction}Hash`], `Native publication ${direction} hash differs`);
    }
    const request = JSON.parse(Buffer.from(receipt.requestBody, "base64").toString("utf8"));
    const response = JSON.parse(Buffer.from(receipt.responseBody, "base64").toString("utf8"));
    assert.equal(typeof response.sha, "string", "Native upload lacks its returned ID");
    if (/\/git\/blobs\/?$/.test(receipt.path)) {
      assert.equal(request.encoding, "base64", "Native upload uses another blob encoding");
      blobs.set(response.sha, request.content);
    } else {
      assert(/\/git\/trees\/?$/.test(receipt.path) && Array.isArray(request.tree),
        "Native publication receipt is not a tree upload");
      trees.set(response.sha, request.tree);
    }
  }
  const active = new Set();
  const build = (id) => {
    const entries = trees.get(id);
    assert(entries && !active.has(id), "Native uploaded summary tree is missing or cyclic");
    active.add(id);
    const names = entries.map(({ path }) => decodeURIComponent(path));
    assert.equal(new Set(names).size, names.length,
      "Native uploaded summary has duplicate child paths");
    const result = {
      type: "tree",
      entries: entries.map(({ path, type, sha }) => {
        const name = decodeURIComponent(path);
        assert.equal(typeof sha, "string", "Native uploaded summary entry lacks its ID");
        if (type === "tree") return [name, build(sha)];
        assert(type === "blob" && blobs.has(sha),
          "Native uploaded summary blob is missing or has another kind");
        return [name, { type: "blob", base64: blobs.get(sha) }];
      }),
    };
    active.delete(id);
    return result;
  };
  return build(treeId);
}

function summaryRetentionEvidence(summary, targetPath) {
  const handles = [];
  const markers = [];
  const history = [];
  const branchAncestry = [];
  const visit = (entry, path = "") => {
    if (entry?.type === "handle") {
      handles.push({
        path,
        handleType: entry.handleType,
        target: entry.path,
      });
      return;
    }
    if (entry?.type === "blob") {
      if (!/(Forest\/contents|EditManager\/String)$/i.test(path)) return;
      const bytes = Buffer.from(entry.base64, "base64");
      const decoded = JSON.parse(bytes.toString("utf8"));
      for (const marker of retainedBlobMarkers(decoded, path)) {
        markers.push({ path, ...marker });
      }
      if (/EditManager\/String$/i.test(path)) {
        assert.equal(decoded.version, 7,
          "Published retained history has another version");
        assert(Array.isArray(decoded.trunk) && Array.isArray(decoded.branches),
          "Published retained history lacks trunk or branch ancestry");
        branchAncestry.push(...decoded.branches);
        history.push(...decoded.trunk.map((commit) => ({
          path, ...retainedHistoryCommit(commit),
        })));
      }
      return;
    }
    assert.equal(entry?.type, "tree", "Retention summary entry has another kind");
    for (const [name, child] of entry.entries) visit(child, `${path}/${name}`);
  };
  visit(summary);
  return {
    sha256: hash(summary),
    handles,
    markers,
    history,
    branchAncestry,
    targetMarkers: markers.filter(({ url }) => url === targetPath),
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

function watchRetention(view) {
  const events = [];
  let capture = false;
  let retained;
  const off = view.events.on("changed", (metadata, getRevertible) => {
    const event = {
      kind: CommitKind[metadata.kind],
      local: metadata.isLocal,
      factoryAvailable: getRevertible !== undefined,
      acquired: false,
    };
    if (capture && metadata.isLocal && getRevertible !== undefined) {
      retained = getRevertible((disposed) => {
        event.disposed = disposed === retained;
        event.status = RevertibleStatus[disposed.status];
      });
      capture = false;
      event.acquired = true;
      event.status = RevertibleStatus[retained.status];
    }
    events.push(event);
  });
  return {
    captureNext() {
      capture = true;
    },
    events,
    retained() {
      assert(retained, "Retention edit did not expose an inverse");
      return retained;
    },
    off,
  };
}

async function retentionCheckpointStateUpstream(authored, id) {
  const continued = authored.target.get("continued");
  return {
    id,
    graph: visibleHandleRoot(authored.view),
    target: {
      path: authored.target.handle.absolutePath,
      attached: authored.target.isAttached?.() ?? false,
      value: authored.target.get("value"),
      ...(continued === undefined ? {} : { continued }),
    },
    lifetime: {
      branches: authored.branch === undefined ? 0 : 1,
      revertible: authored.revertible === undefined
        ? "Missing"
        : RevertibleStatus[authored.revertible.status],
      events: structuredClone(authored.watch.events),
    },
  };
}

async function retentionCheckpointStateNative(authored, id) {
  const checkpoint = await authored.command({
    command: "checkpoint",
    tree: "retention-tree",
  });
  const revertible = authored.revertibleReceipt.status === "Valid"
    ? await authored.command({
      op: "revertibleStatus",
      tree: "retention-tree",
      name: authored.revertibleName,
    })
    : authored.revertibleReceipt;
  const link = await authored.adapter.client.read(["link"], "retention-tree");
  const continued = (await authored.adapter.client.sharedMapGet(
    "retention-target",
    "continued",
  )).value;
  return {
    id,
    graph: {
      label: (await authored.adapter.client.read(
        ["label"],
        "retention-tree",
      )).value.value,
      ...(link.present ? { link: handleValue(link).url } : {}),
      links: [],
      sequence: [],
    },
    target: {
      path: authored.target.url,
      value: (await authored.adapter.client.sharedMapGet(
        "retention-target",
        "value",
      )).value,
      ...(continued === undefined ? {} : { continued }),
    },
    lifetime: {
      branches: authored.branchReceipt.status === "BranchValid" ? 1 : 0,
      branch: structuredClone(authored.branchReceipt),
      revertible: revertible.status,
      inverse: structuredClone(revertible),
      checkpoint,
    },
  };
}

async function authorRetentionUpstream(environment, label) {
  const data = environment.upstreamSession.data;
  const created = await createUpstreamTree(data, `${label}-document`);
  data.bootstrap.set("retention", created.tree.handle);
  await synchronize(environment);
  const target = await data.createMap();
  target.set("value", "before");
  created.view.root.link = target.handle;
  await synchronize(environment);
  const watch = watchRetention(created.view);
  return {
    document: created.tree,
    view: created.view,
    target,
    watch,
    branch: undefined,
    revertible: undefined,
    secondary: undefined,
    replies: [],
    async remove() {
      watch.captureNext();
      created.view.root.link = undefined;
      await synchronize(environment);
      this.revertible = watch.retained();
    },
    async undo() {
      watch.captureNext();
      this.revertible.revert(true);
      await synchronize(environment);
      this.revertible = watch.retained();
    },
    async retainAndRedo() {
      this.branch = created.view.fork();
      watch.captureNext();
      this.revertible.revert(true);
      await synchronize(environment);
      this.revertible = watch.retained();
    },
    async disposeBranch() {
      this.branch.dispose();
      this.branch = undefined;
    },
    async disposeRevertible() {
      this.revertible.dispose();
    },
    async unreferenceDataStore() {
      const secondary = await createUpstreamDataStore(environment.upstreamSession);
      data.bootstrap.set("retention-secondary", secondary.handle);
      await synchronize(environment);
      data.bootstrap.delete("retention-secondary");
      await synchronize(environment);
      this.secondary = secondary;
    },
    async restore() {
      created.view.root.link = target.handle;
      await synchronize(environment);
    },
    state(id) {
      return retentionCheckpointStateUpstream(this, id);
    },
  };
}

async function authorRetentionNative(environment, writer, label) {
  const adapter = environment.adapters[writer];
  const replies = [];
  const command = async (request) => {
    const result = await nativeCommand(adapter, request);
    replies.push({ request, result });
    return result;
  };
  await command({ command: "root-map", name: "retention-root" });
  const document = await command({
    command: "create-tree",
    name: "retention-tree",
    schema: handleStoredSchema,
    view: handleStoredSchema,
    initialRoot: taggedHandleRoot(`${label}-document`),
  });
  await command({
    command: "shared-map-set",
    name: "retention-root",
    key: "retention",
    value: document,
  });
  await synchronize(environment);
  const target = await command({
    command: "create-map",
    name: "retention-target",
  });
  await command({
    command: "shared-map-set",
    name: "retention-target",
    key: "value",
    value: "before",
  });
  await command({
    command: "set",
    tree: "retention-tree",
    path: ["link"],
    value: taggedHandle(target),
  });
  await synchronize(environment);
  await command({ command: "subscribe", tree: "retention-tree" });
  return {
    adapter,
    command,
    document,
    target,
    replies,
    branchReceipt: { name: "retaining", status: "Missing" },
    revertibleReceipt: { name: "retention-removal", status: "Missing" },
    revertibleName: "retention-removal",
    secondary: undefined,
    async remove() {
      await command({
        command: "clear",
        tree: "retention-tree",
        path: ["link"],
      });
      this.revertibleReceipt = await command({
        op: "retainLastLocalCommit",
        tree: "retention-tree",
        name: "retention-removal",
      });
      await synchronize(environment);
    },
    async undo() {
      await command({
        op: "revert",
        tree: "retention-tree",
        name: this.revertibleName,
        dispose: true,
      });
      this.revertibleReceipt = await command({
        op: "retainLastLocalCommit",
        tree: "retention-tree",
        name: "retention-redo",
      });
      this.revertibleName = "retention-redo";
      await synchronize(environment);
    },
    async retainAndRedo() {
      this.branchReceipt = await command({
        op: "fork",
        tree: "retention-tree",
        source: "main",
        name: "retaining",
      });
      await command({
        op: "revert",
        tree: "retention-tree",
        name: this.revertibleName,
        dispose: true,
      });
      this.revertibleReceipt = await command({
        op: "retainLastLocalCommit",
        tree: "retention-tree",
        name: "retention-final",
      });
      this.revertibleName = "retention-final";
      await synchronize(environment);
    },
    async disposeBranch() {
      this.branchReceipt = await command({
        op: "disposeBranch",
        tree: "retention-tree",
        name: "retaining",
      });
    },
    async disposeRevertible() {
      this.revertibleReceipt = await command({
        op: "disposeRevertible",
        tree: "retention-tree",
        name: this.revertibleName,
      });
    },
    async unreferenceDataStore() {
      const secondary = await command({
        command: "create-data-store",
        name: "retention-secondary",
      });
      await command({
        command: "shared-map-set",
        name: "retention-root",
        key: "retention-secondary",
        value: secondary,
      });
      await synchronize(environment);
      await command({
        command: "shared-map-delete",
        name: "retention-root",
        key: "retention-secondary",
      });
      await synchronize(environment);
      this.secondary = secondary;
    },
    async restore() {
      await command({
        command: "set",
        tree: "retention-tree",
        path: ["link"],
        value: taggedHandle(target),
      });
      await synchronize(environment);
    },
    state(id) {
      return retentionCheckpointStateNative(this, id);
    },
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

function publicationEvidence(writer, publication) {
  return writer === "upstream"
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
}

async function publishRetentionCheckpoint(
  config,
  environment,
  writer,
  authored,
  id,
) {
  await synchronize(environment);
  const local = await authored.state(id);
  const publication = writer === "upstream"
    ? await publishUpstreamSummary(
      config,
      environment.containers,
      environment.documentId,
      `Task 8 handleRetention:${writer}:${id}`,
      { store: handleServiceStore },
    )
    : await environment.adapters[writer].summarizePublication();
  await synchronize(environment);
  const stored = await fetchSnapshot(environment.creator);
  const targets = {
    document: {
      path: authored.document.handle?.absolutePath ?? authored.document.url,
      attributes: channelAttributes.tree,
    },
    target: {
      path: authored.target.handle?.absolutePath ?? authored.target.url,
      attributes: channelAttributes.map,
    },
    ...(authored.secondary === undefined ? {} : {
      secondary: {
        path: authored.secondary.handle?.absolutePath ?? authored.secondary.url,
        attributes: channelAttributes.map,
      },
    }),
  };
  const uploads = writer === "upstream" ? undefined
    : environment.adapters[writer].evidence().http.filter(({ method, path, status }) =>
      method === "POST" && status === 201 && /\/git\/(?:blobs|trees)\/?$/.test(path));
  const summary = writer === "upstream"
    ? summaryEntryEvidence(publication.summaryTree)
    : submittedSummaryEvidence(uploads, stored.raw.tree.trees[".app"].id);
  const targetNode = snapshotNode(stored.raw, targets.target.path);
  local.target.attached = true;
  local.target.attachment = {
    path: targets.target.path,
    treeId: targetNode.id,
    attributes: decodedBlob(stored.raw, targetNode, ".attributes"),
  };
  return {
    ...local,
    publication: {
      ...publicationEvidence(writer, publication),
      ...(uploads === undefined ? {} : { uploads }),
    },
    snapshot: {
      version: stored.version,
      treeSha256: stored.treeSha256,
      blobs: stored.blobs,
      evidence: {
        referenceSequenceNumber: snapshotSequence(stored.raw),
        compressor: snapshotCompressor(stored.raw),
        gc: snapshotGc(stored.raw),
        components: snapshotComponents(stored.raw),
        attributes: Object.fromEntries(Object.entries(targets).map(
          ([name, target]) => [
            name,
            decodedBlob(
              stored.raw,
              snapshotNode(stored.raw, target.path),
              ".attributes",
            ),
          ],
        )),
        graph: storedTreeGraph(stored.raw, targets.document.path),
        retainedHandles: snapshotRetentionHandles(
          stored.raw,
          targets.document.path,
          targets.target.path,
        ),
        retainedSummary: summaryRetentionEvidence(
          summary,
          targets.target.path,
        ),
      },
    },
    summary,
    rawSnapshot: stored.raw,
  };
}

function upstreamLoaderEvidence(observations) {
  const versions = observations.find(({ operation }) =>
    operation === "getVersions");
  assert.equal(versions?.count, 1,
    "Fresh upstream loader did not select one storage version");
  const tree = observations.find(({ operation }) =>
    operation === "getSnapshotTree");
  assert(tree?.id, "Fresh upstream loader lacks a fetched snapshot tree");
  return {
    selectedVersion: versions.versions[0].id,
    versionReceipt: structuredClone(versions),
    treeReceipt: structuredClone(tree),
    fetchedBlobs: observations.filter(({ operation }) =>
      operation === "readBlob").map(({ id, hash: sha256, byteLength }) => ({
      id,
      sha256,
      byteLength,
    })),
  };
}

function nativeLoaderEvidence(transport) {
  const receipts = transport.http.filter(({ status }) => status === 200);
  const versionReceipt = receipts.find(({ storageResponse }) =>
    storageResponse?.kind === "commit");
  assert(versionReceipt, "Fresh native loader lacks a selected commit receipt");
  const treeReceipt = receipts.find(({ storageResponse }) =>
    storageResponse?.kind === "tree"
      && storageResponse.requestedId === versionReceipt.storageResponse.treeId);
  assert(treeReceipt, "Fresh native loader lacks its selected tree receipt");
  const fetchedBlobs = receipts.filter(({ path }) =>
    /\/git\/blobs\/[^/?]+/.test(path)).map((receipt) => {
    const response = JSON.parse(
      Buffer.from(receipt.responseBody, "base64").toString("utf8"),
    );
    const bytes = Buffer.from(response.content, response.encoding);
    return {
      id: decodeURIComponent(receipt.path.match(/\/git\/blobs\/([^/?]+)/)[1]),
      sha256: hash(bytes),
      byteLength: bytes.length,
      responseHash: receipt.responseHash,
    };
  });
  return {
    selectedVersion: versionReceipt.storageResponse.requestedId,
    versionReceipt: structuredClone(versionReceipt),
    treeReceipt: structuredClone(treeReceipt),
    fetchedBlobs,
  };
}

function validateRetentionLoader(name, writer, continuation, rawSnapshot, targets, summary) {
  const fetched = new Map();
  const expectedBlobs = { ...rawSnapshot.blobs };
  if (writer === "upstream") {
    assert(Array.isArray(continuation.storage),
      `${name} fresh loader lacks actual storage observations`);
    assert.deepEqual(continuation.loader, upstreamLoaderEvidence(continuation.storage),
      `${name} fresh loader receipts differ from actual storage observations`);
    const { versionReceipt, treeReceipt } = continuation.loader;
    const decode = (receipt) => {
      assert.equal(typeof receipt.responseBody, "string",
        `${name} fresh loader receipt lacks response bytes`);
      const bytes = Buffer.from(receipt.responseBody, "base64");
      assert.equal(hash(bytes), receipt.hash,
        `${name} fresh loader receipt response hash differs`);
      return JSON.parse(bytes.toString("utf8"));
    };
    const versions = decode(versionReceipt);
    assert.equal(versions.length, 1, `${name} fresh loader selected multiple versions`);
    assert.equal(versions[0].id, continuation.loadedVersion,
      `${name} fresh loader version body names another publication`);
    assert.equal(versions[0].treeId, rawSnapshot.tree.id,
      `${name} fresh loader version body names another tree`);
    assert.equal(treeReceipt.request[0].id, versions[0].id,
      `${name} fresh loader tree request used another version`);
    assert.deepEqual(decode(treeReceipt), rawSnapshot.tree,
      `${name} fresh loader fetched another snapshot tree`);
    for (const receipt of continuation.storage.filter(({ operation }) =>
      operation === "readBlob")) {
      assert.equal(typeof receipt.responseBody, "string",
        `${name} fresh loader blob lacks actual bytes`);
      const bytes = Buffer.from(receipt.responseBody, "base64");
      assert.equal(hash(bytes), receipt.hash,
        `${name} fresh loader blob response hash differs`);
      fetched.set(receipt.id, bytes);
    }
  } else {
    assert.deepEqual(continuation.loader, nativeLoaderEvidence(continuation.transport),
      `${name} fresh loader receipts differ from actual HTTP transport`);
    const receipts = continuation.transport.http.filter(({ path, status }) =>
      status === 200 && /\/git\/(?:commits|trees|blobs)\//.test(path));
    const trees = new Map();
    for (const receipt of receipts) {
      assert.equal(receipt.method, "GET", `${name} fresh loader used another HTTP method`);
      assert.equal(typeof receipt.responseBody, "string",
        `${name} fresh loader HTTP receipt lacks response bytes`);
      const bytes = Buffer.from(receipt.responseBody, "base64");
      assert.equal(hash(bytes), receipt.responseHash,
        `${name} fresh loader HTTP response hash differs`);
      const identity = storageResponseIdentity(receipt.path, bytes);
      assert.deepEqual(receipt.storageResponse, identity,
        `${name} fresh loader HTTP receipt identity differs from its body`);
      const body = JSON.parse(bytes.toString("utf8"));
      const match = receipt.path.match(/\/git\/(commits|trees|blobs)\/([^/?]+)/);
      const id = decodeURIComponent(match[2]);
      assert.equal(body.sha, id, `${name} fresh loader body names another requested ID`);
      if (match[1] === "trees") trees.set(id, body.tree);
      if (match[1] === "blobs") {
        fetched.set(id, Buffer.from(body.content, body.encoding));
      }
    }
    const version = continuation.loader.versionReceipt.storageResponse;
    assert.equal(version.requestedId, continuation.loadedVersion,
      `${name} fresh loader HTTP request selected another version`);
    assert.equal(version.treeId, rawSnapshot.tree.id,
      `${name} fresh loader HTTP commit names another tree`);
    const build = (id) => {
      const entries = trees.get(id);
      assert(entries, `${name} fresh loader did not fetch tree ${id}`);
      assert(entries.every(({ type }) => type === "blob" || type === "tree"),
        `${name} fresh loader tree has an unsupported entry`);
      return {
        id,
        blobs: Object.fromEntries(entries.filter(({ type }) => type === "blob")
          .map(({ path, sha }) => [path, sha])),
        trees: Object.fromEntries(entries.filter(({ type }) => type === "tree")
          .map(({ path, sha }) => [path, build(sha)])),
      };
    };
    const physical = build(version.treeId);
    const app = physical.trees[".app"];
    assert(app, `${name} fresh loader lacks its physical application tree`);
    const projected = {
      id: physical.id,
      blobs: { ...physical.blobs, ...app.blobs },
      trees: {
        ...app.trees, ...physical.trees,
        ".app": { id: app.id, blobs: {}, trees: {} },
      },
    };
    const withoutMetadata = ({ id, blobs, trees }) => ({
      id, blobs,
      trees: Object.fromEntries(Object.entries(trees).map(([path, child]) =>
        [path, withoutMetadata(child)])),
    });
    assert.deepEqual(projected, withoutMetadata(rawSnapshot.tree),
      `${name} fresh loader tree hierarchy differs from publication bytes`);
    const shadowProtocol = summary.entries.find(([path]) => path === ".protocol")?.[1];
    assert(shadowProtocol?.type === "tree" && app.trees[".protocol"],
      `${name} native publication lacks its application protocol tree`);
    assert.deepEqual(
      Object.keys(app.trees[".protocol"].blobs).sort(),
      shadowProtocol.entries.map(([path]) => path).sort(),
      `${name} fresh loader application protocol tree differs from publication`,
    );
    for (const [path, entry] of shadowProtocol.entries) {
      assert.equal(entry.type, "blob",
        `${name} fresh loader application protocol entry has another kind`);
      expectedBlobs[app.trees[".protocol"].blobs[path]] = entry.base64;
    }
  }
  for (const [id, bytes] of fetched) {
    assert(expectedBlobs[id] !== undefined,
      `${name} fresh loader fetched an unrelated blob ${id}`);
    assert.equal(bytes.toString("base64"), expectedBlobs[id],
      `${name} fresh loader fetched bytes differ for ${id}`);
  }
  const document = snapshotNode(rawSnapshot, targets.document.path);
  const target = snapshotNode(rawSnapshot, targets.target.path);
  const store = `/${targets.document.path.split("/")[1]}`;
  const bootstrap = snapshotNode(rawSnapshot, `${store}/root`);
  const required = [
    rawSnapshot.tree.blobs[".idCompressor"],
    rawSnapshot.tree.trees.gc.blobs.__gc_root,
    bootstrap.blobs.header,
    document.blobs[".attributes"],
    document.trees.indexes.trees.Forest.blobs.contents,
    document.trees.indexes.trees.EditManager.blobs.String,
    document.trees.indexes.trees.Schema.blobs.SchemaString,
    target.blobs[".attributes"],
    target.blobs.header,
  ];
  for (const id of required) {
    assert(fetched.has(id), `${name} fresh loader did not read required publication blob ${id}`);
  }
}

async function retentionFreshContinuation(
  config,
  context,
  environment,
  writer,
  authored,
  publication,
) {
  const expectedDocument = authored.document.handle?.absolutePath
    ?? authored.document.url;
  const expectedTarget = authored.target.handle?.absolutePath
    ?? authored.target.url;
  if (writer === "upstream") {
    const fresh = await context.constructors.openSession(
      config,
      environment.containers,
      environment.documentId,
      false,
      { store: handleServiceStore, observeStorage: true },
    );
    try {
      const documentHandle = fresh.data.bootstrap.get("retention");
      const tree = await documentHandle.get();
      const view = tree.viewWith(handleTreeConfig);
      const watch = watchRetention(view);
      const targetHandle = view.root.link;
      const target = await targetHandle.get();
      const historyBefore = await serverHistory(environment.creator);
      const before = {
        document: documentHandle.absolutePath,
        target: targetHandle.absolutePath,
        value: target.get("value"),
      };
      const localStacks = {
        events: structuredClone(watch.events),
        pendingOutbound: fresh.container.deltaManager.outbound.length,
        dirty: fresh.container.isDirty,
      };
      target.set("continued", true);
      await until(() =>
        !fresh.container.isDirty
          && fresh.container.deltaManager.inbound.length === 0
          && fresh.container.deltaManager.outbound.length === 0,
      "fresh upstream continuation submission");
      await synchronize(environment);
      const loader = upstreamLoaderEvidence(fresh.storageObservations);
      const result = {
        implementation: writer,
        loadedVersion: loader.selectedVersion,
        loader,
        storage: structuredClone(fresh.storageObservations),
        before,
        after: {
          continued: target.get("continued"),
        },
        localStacks,
        transport: fresh.transportEvidence(),
        sequenced: deltaEvidence(
          (await serverHistory(environment.creator)).slice(historyBefore.length),
        ),
      };
      watch.off();
      view.dispose();
      assert.equal(before.document, expectedDocument);
      assert.equal(before.target, expectedTarget);
      return result;
    } finally {
      fresh.container.dispose();
    }
  }
  const fresh = await context.constructors.nativeAdapter(writer, config, {
    runId: context.runId,
    documentId: environment.documentId,
    tenant: config.tenantId,
    viewSchema: JSON.stringify(handleStoredSchema),
  }, environment.jwt);
  environment.natives.push(fresh);
  try {
    await fresh.awaitSynced();
    await nativeCommand(fresh, { command: "root-map", name: "fresh-root" });
    const document = (await nativeCommand(fresh, {
      command: "shared-map-get",
      name: "fresh-root",
      key: "retention",
    })).value;
    await nativeCommand(fresh, {
      command: "open-tree",
      name: "fresh-tree",
      handle: document,
      view: handleStoredSchema,
    });
    const target = handleValue(await fresh.client.read(["link"], "fresh-tree"));
    await nativeCommand(fresh, {
      command: "open-map",
      name: "fresh-target",
      handle: target,
    });
    const localStacks = await nativeCommand(fresh, {
      command: "checkpoint",
      tree: "fresh-tree",
    });
    const probes = [];
    for (const request of [
      { op: "disposeBranch", tree: "fresh-tree", name: "retaining" },
      ...["retention-removal", "retention-redo", "retention-final"].map((name) =>
        ({ op: "revertibleStatus", tree: "fresh-tree", name })),
    ]) {
      const response = await fresh.client.request(request);
      assert.equal(response.ok, false, "Fresh load revived an old branch or inverse");
      probes.push({ request, response });
    }
    const historyBefore = await serverHistory(environment.creator);
    const before = {
      document: document.url,
      target: target.url,
      value: (await fresh.client.sharedMapGet("fresh-target", "value")).value,
    };
    await fresh.client.sharedMapSet("fresh-target", "continued", true);
    await synchronize(environment);
    assert.equal(before.document, expectedDocument);
    assert.equal(before.target, expectedTarget);
    const transport = fresh.evidence();
    const loader = nativeLoaderEvidence(transport);
    return {
      implementation: writer,
      loadedVersion: loader.selectedVersion,
      loader,
      before,
      after: {
        continued: (await fresh.client.sharedMapGet(
          "fresh-target",
          "continued",
        )).value,
      },
      localStacks: {
        events: localStacks.events,
        commits: localStacks.commits,
        probes,
      },
      transport,
      sequenced: deltaEvidence(
        (await serverHistory(environment.creator)).slice(historyBefore.length),
      ),
    };
  } finally {
    await fresh.close();
    environment.natives = environment.natives.filter(
      (candidate) => candidate !== fresh,
    );
  }
}

async function observeRetentionUpstreamPeer(session, targets) {
  const documentHandle = session.data.bootstrap.get("retention");
  const tree = await documentHandle.get();
  const view = tree.viewWith(handleTreeConfig);
  const targetHandle = view.root.link;
  const target = await targetHandle.get();
  const observed = {
    document: documentHandle.absolutePath,
    target: targetHandle.absolutePath,
    value: target.get("value"),
    continued: target.get("continued"),
  };
  view.dispose();
  assert.equal(observed.document, targets.document.path);
  assert.equal(observed.target, targets.target.path);
  return observed;
}

async function observeRetentionNativePeer(adapter, targets) {
  await nativeCommand(adapter, { command: "root-map", name: "retention-root" });
  const document = (await nativeCommand(adapter, {
    command: "shared-map-get",
    name: "retention-root",
    key: "retention",
  })).value;
  await nativeCommand(adapter, {
    command: "open-tree",
    name: "retention-observed",
    handle: document,
    view: handleStoredSchema,
  });
  const target = handleValue(
    await adapter.client.read(["link"], "retention-observed"),
  );
  await nativeCommand(adapter, {
    command: "open-map",
    name: "retention-target",
    handle: target,
  });
  const observed = {
    document: document.url,
    target: target.url,
    value: (await adapter.client.sharedMapGet("retention-target", "value")).value,
    continued:
      (await adapter.client.sharedMapGet("retention-target", "continued")).value,
  };
  assert.equal(observed.document, targets.document.path);
  assert.equal(observed.target, targets.target.path);
  return observed;
}

async function runRetentionRow(config, context, writer) {
  const environment = await createEnvironment(
    config,
    context.runId,
    "handleRetention",
    writer,
    context.constructors,
  );
  let failure;
  try {
    const label = `handleRetention-${writer}-${context.runId.slice(0, 8)}`;
    const historyBefore = await serverHistory(environment.creator);
    const authored = writer === "upstream"
      ? await authorRetentionUpstream(environment, label)
      : await authorRetentionNative(environment, writer, label);
    const checkpoints = [];
    checkpoints.push(await publishRetentionCheckpoint(
      config, environment, writer, authored, "before-removal",
    ));
    await authored.remove();
    checkpoints.push(await publishRetentionCheckpoint(
      config, environment, writer, authored, "after-removal",
    ));
    await authored.undo();
    checkpoints.push(await publishRetentionCheckpoint(
      config, environment, writer, authored, "after-undo",
    ));
    await authored.retainAndRedo();
    checkpoints.push(await publishRetentionCheckpoint(
      config, environment, writer, authored, "retained-repair",
    ));
    await authored.disposeBranch();
    checkpoints.push(await publishRetentionCheckpoint(
      config, environment, writer, authored, "branch-disposal",
    ));
    await authored.disposeRevertible();
    checkpoints.push(await publishRetentionCheckpoint(
      config, environment, writer, authored, "revertible-disposal",
    ));
    await authored.unreferenceDataStore();
    checkpoints.push(await publishRetentionCheckpoint(
      config, environment, writer, authored, "unreferenced-datastore",
    ));
    await authored.restore();
    const fresh = await publishRetentionCheckpoint(
      config, environment, writer, authored, "fresh-load",
    );
    fresh.continuation = await retentionFreshContinuation(
      config,
      context,
      environment,
      writer,
      authored,
      fresh,
    );
    checkpoints.push(fresh);
    await synchronize(environment);
    const targets = {
      document: {
        path: authored.document.handle?.absolutePath ?? authored.document.url,
        attributes: channelAttributes.tree,
      },
      target: {
        path: authored.target.handle?.absolutePath ?? authored.target.url,
        attributes: channelAttributes.map,
      },
      secondary: {
        path: authored.secondary.handle?.absolutePath ?? authored.secondary.url,
        attributes: channelAttributes.map,
      },
    };
    const peers = {
      upstream: await observeRetentionUpstreamPeer(
        environment.peerSession,
        targets,
      ),
    };
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
        peers[target] = await observeRetentionNativePeer(peer, targets);
      } finally {
        await peer?.close();
      }
    }
    const history = await serverHistory(environment.creator);
    const submitted = submissionEvidence(writer, environment);
    const sequenced = deltaEvidence(history.slice(historyBefore.length));
    const row = {
      formatVersion: 1,
      runId: context.runId,
      writer,
      documentId: environment.documentId,
      contract,
      factory: handleServiceStore.type,
      targets,
      peer: {
        expectedImplementations: requiredPeerImplementations(writer),
        observations: peers,
      },
      raw: {
        intent: { section: "handleRetention", writer, label },
        nativeReplies: authored.replies,
        submitted,
        sequenced,
        dependencies: dependencyEvidence(sequenced, targets),
      },
      retention: {
        checkpoints: checkpoints.map(({ rawSnapshot, ...checkpoint }) =>
          jsonClone(checkpoint)),
      },
      writerClientIds: writer === "upstream"
        ? [environment.upstreamSession.container.clientId]
        : [...environment.adapters[writer].clientIds],
      artifacts: [],
    };
    const artifact = {
      formatVersion: 1,
      runId: context.runId,
      section: "handleRetention",
      writer,
      documentId: row.documentId,
      contract,
      raw: row.raw,
      targets,
      peers,
      retention: {
        checkpoints,
      },
    };
    const relative = `handleRetention/${writer}.json`;
    const bytes = `${JSON.stringify(artifact)}\n`;
    await mkdir(join(context.output, "handleRetention"), { recursive: true });
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

async function runRow(config, context, section, writer) {
  if (section === "handleRetention") {
    return runRetentionRow(config, context, writer);
  }
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
    const published = publicationEvidence(writer, publication);
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
        publication: published,
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
  const submittedOperations = outbound.map(transportOperationIdentity);
  const sequencedOperations = row.raw.sequenced
    .filter(({ type, clientId }) =>
      type === "op" && row.writerClientIds.includes(clientId))
    .map(transportOperationIdentity);
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

function validateCompressorAllocations(
  name,
  row,
  artifactSnapshot,
  referenceSequenceNumber = Number.POSITIVE_INFINITY,
) {
  const { compressor } = decodedSnapshotCompressor(artifactSnapshot);
  const throughCheckpoint = ({ sequenceNumber }) =>
    sequenceNumber <= referenceSequenceNumber;
  const allocations = row.raw.dependencies.allocations.filter(throughCheckpoint);
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
  for (const commit of row.raw.dependencies.commits.filter(throughCheckpoint)) {
    const generation = finalizedGeneration(commit.revision, commit.originatorId);
    requireEarlierAllocation(commit.originatorId, generation, commit);
  }
  for (const message of row.raw.sequenced.filter(throughCheckpoint)) {
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

function gcNode(gc, path, label) {
  const node = gc?.gcNodes?.[path];
  assert(node, `${label} GC lacks route ${path}`);
  assert(Array.isArray(node.outboundRoutes),
    `${label} GC route ${path} lacks outbound routes`);
  return node;
}

function validateRetentionGc(name, checkpoint, targets) {
  const gc = checkpoint.snapshot.evidence.gc;
  const documentStore = `/${targets.document.path.split("/").filter(Boolean)[0]}`;
  const expected = {
    "/": [documentStore],
    [documentStore]: [
      targets.target.path,
      `${documentStore}/_C`,
      targets.document.path,
      `${documentStore}/root`,
    ],
    [targets.target.path]: [documentStore],
    [`${documentStore}/_C`]: [documentStore],
    [targets.document.path]: [documentStore, targets.target.path],
    [`${documentStore}/root`]: [
      documentStore,
      `${documentStore}/_C`,
      targets.document.path,
    ],
  };
  if (["unreferenced-datastore", "fresh-load"].includes(checkpoint.id)) {
    const secondaryStore =
      `/${targets.secondary.path.split("/").filter(Boolean)[0]}`;
    expected[secondaryStore] = [targets.secondary.path];
    expected[targets.secondary.path] = [secondaryStore];
  }
  assert.deepEqual(
    Object.keys(gc.gcNodes).sort(),
    Object.keys(expected).sort(),
    `${name} ${checkpoint.id} GC node set differs`,
  );
  for (const [path, routes] of Object.entries(expected)) {
    const node = gcNode(gc, path, `${name} ${checkpoint.id}`);
    assert.deepEqual(
      [...node.outboundRoutes].sort(),
      [...routes].sort(),
      `${name} ${checkpoint.id} GC routes differ for ${path}`,
    );
  }
  const reachable = new Set(["/"]);
  const pending = ["/"];
  while (pending.length > 0) {
    const path = pending.shift();
    for (const route of gc.gcNodes[path].outboundRoutes) {
      if (!reachable.has(route)) {
        reachable.add(route);
        pending.push(route);
      }
    }
  }
  for (const [path, node] of Object.entries(gc.gcNodes)) {
    if (reachable.has(path)) {
      assert.equal(node.unreferencedTimestampMs, undefined,
        `${name} ${checkpoint.id} reachable GC node has an unreferenced timestamp`);
    } else {
      assert(Number.isFinite(node.unreferencedTimestampMs)
        && node.unreferencedTimestampMs > 0,
      `${name} ${checkpoint.id} unreachable GC node lacks a timestamp`);
    }
  }
  if (checkpoint.id === "unreferenced-datastore"
    || checkpoint.id === "fresh-load") {
    const secondaryStore =
      `/${targets.secondary.path.split("/").filter(Boolean)[0]}`;
    assert.equal(
      gc.gcNodes[secondaryStore].unreferencedTimestampMs,
      gc.gcNodes[targets.secondary.path].unreferencedTimestampMs,
      `${name} ${checkpoint.id} unreferenced component timestamps differ`,
    );
  }
}

async function validateRetentionRow(name, row, artifacts) {
  assert.equal(row.formatVersion, 1, `${name} row format changed`);
  assert.equal(row.runId, artifacts.runId, `${name} row run identity changed`);
  validateContract(row.contract, `${name} row`);
  assert.equal(row.factory, handleServiceStore.type,
    `${name} primary factory differs from the pinned contract`);
  assert.deepEqual(
    Object.keys(row.targets).sort(),
    ["document", "secondary", "target"],
    `${name} retention target identity set changed`,
  );
  for (const [target, descriptor] of Object.entries(row.targets)) {
    assert.deepEqual(descriptor.attributes,
      target === "document" ? channelAttributes.tree : channelAttributes.map,
    `${name} fixed target attributes contract differs for ${target}`);
  }
  if (row.writer !== "upstream") {
    assert(Array.isArray(row.raw.nativeReplies) && row.raw.nativeReplies.length > 0,
      `${name} native lifetime receipts are missing`);
  }
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
  assert.deepEqual(artifact.peers, row.peer.observations,
    `${name} artifact peer observations differ`);
  const expectedIds = [
    "before-removal",
    "after-removal",
    "after-undo",
    "retained-repair",
    "branch-disposal",
    "revertible-disposal",
    "unreferenced-datastore",
    "fresh-load",
  ];
  assert.deepEqual(
    row.retention.checkpoints.map(({ id }) => id),
    expectedIds,
    `${name} checkpoint coverage changed`,
  );
  assert.equal(artifact.retention.checkpoints.length, expectedIds.length,
    `${name} artifact checkpoint coverage changed`);
  for (const [index, checkpoint] of row.retention.checkpoints.entries()) {
    const captured = artifact.retention.checkpoints[index];
    const { rawSnapshot, ...artifactCheckpoint } = captured;
    assert.deepEqual(checkpoint, artifactCheckpoint,
      `${name} ${checkpoint.id} report differs from its raw artifact`);
    assert.equal(checkpoint.snapshot.version, checkpoint.publication.version,
      `${name} ${checkpoint.id} publication names another fetched version`);
    assert.equal(checkpoint.snapshot.treeSha256, hash(rawSnapshot.tree),
      `${name} ${checkpoint.id} stored tree hash differs`);
    assert.deepEqual(
      checkpoint.snapshot.blobs,
      Object.fromEntries(Object.entries(rawSnapshot.blobs).map(
        ([id, encoded]) => [id, hash(Buffer.from(encoded, "base64"))],
      )),
      `${name} ${checkpoint.id} stored blob hashes differ`,
    );
    assert.equal(
      checkpoint.snapshot.evidence.referenceSequenceNumber,
      snapshotSequence(rawSnapshot),
      `${name} ${checkpoint.id} storage reference sequence differs`,
    );
    assert.deepEqual(
      checkpoint.snapshot.evidence.compressor,
      snapshotCompressor(rawSnapshot),
      `${name} ${checkpoint.id} finalized compressor evidence differs`,
    );
    assert.deepEqual(
      checkpoint.snapshot.evidence.gc,
      snapshotGc(rawSnapshot),
      `${name} ${checkpoint.id} fetched GC routes differ`,
    );
    assert.deepEqual(
      checkpoint.snapshot.evidence.components,
      snapshotComponents(rawSnapshot),
      `${name} ${checkpoint.id} component metadata differs`,
    );
    assert.deepEqual(
      checkpoint.snapshot.evidence.attributes,
      Object.fromEntries(Object.entries(row.targets)
        .filter(([target]) =>
          target !== "secondary"
            || ["unreferenced-datastore", "fresh-load"].includes(checkpoint.id))
        .map(([target, descriptor]) => [
          target,
          decodedBlob(
            rawSnapshot,
            snapshotNode(rawSnapshot, descriptor.path),
            ".attributes",
          ),
        ])),
      `${name} ${checkpoint.id} channel attributes differ`,
    );
    for (const [target, storedAttributes] of Object.entries(
      checkpoint.snapshot.evidence.attributes,
    )) {
      assert.deepEqual(
        storedAttributes,
        row.targets[target].attributes,
        `${name} ${checkpoint.id} persisted attributes differ for ${target}`,
      );
    }
    assert.deepEqual(
      checkpoint.snapshot.evidence.graph,
      storedTreeGraph(rawSnapshot, row.targets.document.path),
      `${name} ${checkpoint.id} stored graph differs`,
    );
    assert.deepEqual(
      checkpoint.snapshot.evidence.retainedHandles,
      snapshotRetentionHandles(
        rawSnapshot,
        row.targets.document.path,
        row.targets.target.path,
      ),
      `${name} ${checkpoint.id} forest/repair/history handle evidence differs`,
    );
    assert.deepEqual(
      checkpoint.snapshot.evidence.retainedSummary,
      summaryRetentionEvidence(checkpoint.summary, row.targets.target.path),
      `${name} ${checkpoint.id} retained summary evidence differs`,
    );
    if (row.writer !== "upstream") {
      assert.deepEqual(checkpoint.summary, submittedSummaryEvidence(
        checkpoint.publication.uploads, rawSnapshot.tree.trees[".app"].id,
      ), `${name} ${checkpoint.id} summary differs from actual publication uploads`);
    }
    validatePublication(name, {
      writer: row.writer,
      raw: {
        sequenced: row.raw.sequenced,
        publication: checkpoint.publication,
      },
      snapshot: checkpoint.snapshot,
    }, rawSnapshot);
    const metadata = snapshotMetadata(rawSnapshot);
    assert.equal(metadata.createContainerRuntimeVersion, reference.version,
      `${name} ${checkpoint.id} persisted runtime metadata version differs`);
    assert.equal(
      metadata.documentSchema.info.minVersionForCollab,
      oldestSupportedClient,
      `${name} ${checkpoint.id} persisted minimum client differs`,
    );
    const lastMessage = row.raw.sequenced.find(({ sequenceNumber }) =>
      sequenceNumber === metadata.lastMessage.sequenceNumber);
    assert.equal(metadata.lastMessage.timestamp, lastMessage?.timestamp,
      `${name} ${checkpoint.id} reference timestamp differs from service receipt`);
    assert.deepEqual(snapshotFactory(rawSnapshot, row.targets.document.path), {
      packagePath: [handleServiceStore.type],
      summaryFormatVersion: 2,
      isRootDataStore: true,
    }, `${name} ${checkpoint.id} component-root metadata differs`);
    const localLink = checkpoint.graph.link ?? null;
    assert.equal(checkpoint.snapshot.evidence.graph.optional, localLink,
      `${name} ${checkpoint.id} independently measured graph differs from storage`);
    validateRetentionGc(name, checkpoint, row.targets);
    assert.equal(checkpoint.target.attached, true,
      `${name} ${checkpoint.id} target is not attached`);
    assert.deepEqual(checkpoint.target.attachment, {
      path: row.targets.target.path,
      treeId: snapshotNode(rawSnapshot, row.targets.target.path).id,
      attributes: row.targets.target.attributes,
    }, `${name} ${checkpoint.id} target attachment receipt differs`);
    assert(
      checkpoint.snapshot.evidence.retainedHandles.some(
        ({ path }) => /Forest/i.test(path),
      ),
      `${name} ${checkpoint.id} lacks forest handle evidence`,
    );
    if (["after-removal", "retained-repair", "branch-disposal"].includes(
      checkpoint.id,
    )) {
      assert(
        checkpoint.snapshot.evidence.retainedHandles.some(
          ({ kind, markers }) =>
            kind === "history"
              && markers.some(({ url }) => url === row.targets.target.path),
        ),
        `${name} ${checkpoint.id} retained history lost the target handle marker`,
      );
      assert(
        checkpoint.snapshot.evidence.retainedSummary.targetMarkers.length > 0,
        `${name} ${checkpoint.id} retained summary lost the target handle marker`,
      );
    }
    validateCompressorAllocations(
      `${name} ${checkpoint.id}`,
      row,
      rawSnapshot,
      checkpoint.snapshot.evidence.referenceSequenceNumber,
    );
  }
  const checkpoints = Object.fromEntries(
    row.retention.checkpoints.map((checkpoint) => [checkpoint.id, checkpoint]),
  );
  const revisions = (checkpoint) => {
    const retained = checkpoint.snapshot.evidence.retainedHandles.find(
      ({ kind }) => kind === "history",
    );
    assert(retained, `${name} ${checkpoint.id} lacks decoded retained history`);
    const stored = retained.history.map(({ revision }) => revision);
    const rawSnapshot = artifact.retention.checkpoints.find(({ id }) =>
      id === checkpoint.id).rawSnapshot;
    const commits = JSON.parse(Buffer.from(
      rawSnapshot.blobs[retained.blobId], "base64",
    )).trunk;
    const wire = decodeTreeSubmissions(row.raw.sequenced);
    const undo = row.writer === "upstream" ? undefined
      : row.raw.nativeReplies.find(({ request }) =>
        request.op === "revert" && request.name === "retention-removal");
    if (row.writer !== "upstream") {
      assert(undo?.result.authoredKind === "Undo",
        `${name} native undo lifetime receipt is missing`);
    }
    const { compressor } = decodedSnapshotCompressor(rawSnapshot);
    for (const commit of commits) {
      const submission = wire.find(({ outerSequenceNumber }) =>
        outerSequenceNumber === commit.sequenceNumber);
      const original = submission?.commits.find(({ revision, originatorId }) =>
        revision === commit.revision && originatorId === commit.sessionId);
      assert(original, `${name} retained commit identity differs from service history`);
      assert(commit.sequenceNumber <= checkpoint.publication.referenceSequenceNumber,
        `${name} retained commit exceeds its publication sequence`);
      const expectedChange = structuredClone(original.changeset);
      if (undo?.result.submittedRevisions.includes(compressor.decompress(commit.revision))) {
        for (const component of expectedChange) delete component.data?.refreshers;
      }
      assert.deepEqual(commit.change, expectedChange,
        `${name} retained history changeset differs from its sequenced commit`);
    }
    assert.deepEqual(
      checkpoint.snapshot.evidence.retainedSummary.branchAncestry,
      retained.branches,
      `${name} ${checkpoint.id} summary branch ancestry differs from storage`,
    );
    if (row.writer === "upstream") {
      assert(retained.branches.length > 0
        && retained.branches.every((entry) =>
          Array.isArray(entry)
            && entry.length === 2
            && entry[0] === commits.at(-1).sessionId
            && entry[1]?.base === stored.at(-1)
            && Array.isArray(entry[1].commits)
            && entry[1].commits.length === 0),
      `${name} ${checkpoint.id} upstream ancestry is not a peer-base suffix`);
    } else {
      assert.deepEqual(retained.branches, [],
        `${name} ${checkpoint.id} persisted a local branch root`);
    }
    assert.deepEqual(
      checkpoint.snapshot.evidence.retainedSummary.history.map(
        ({ path, ...commit }) => commit,
      ), retained.history,
      `${name} ${checkpoint.id} summary history ancestry differs from storage`,
    );
    return stored;
  };
  const beforeRevisions = revisions(checkpoints["before-removal"]);
  const removedRevisions = revisions(checkpoints["after-removal"]);
  const undoRevisions = revisions(checkpoints["after-undo"]);
  const repairRevisions = revisions(checkpoints["retained-repair"]);
  assert.deepEqual(removedRevisions.slice(0, -1), beforeRevisions,
    `${name} removal history lost its ancestry`);
  assert.deepEqual(undoRevisions.slice(0, -1), removedRevisions,
    `${name} undo history lost its ancestry`);
  assert.deepEqual(repairRevisions.slice(0, -1), undoRevisions,
    `${name} retained repair history lost its ancestry`);
  for (const id of [
    "branch-disposal",
    "revertible-disposal",
    "unreferenced-datastore",
  ]) {
    assert.deepEqual(revisions(checkpoints[id]), repairRevisions,
      `${name} ${id} changed retained document ancestry`);
  }
  const freshRevisions = revisions(checkpoints["fresh-load"]);
  const freshBase = freshRevisions.slice(0, -1);
  const dropped = repairRevisions.length - freshBase.length;
  assert(dropped >= 0, `${name} fresh history added an unobserved ancestor`);
  assert.deepEqual(freshBase, repairRevisions.slice(dropped),
    `${name} fresh history is not a contiguous retained ancestry suffix`);
  const freshRawSnapshot = artifact.retention.checkpoints.at(-1).rawSnapshot;
  const protocol = decodedBlob(
    freshRawSnapshot,
    freshRawSnapshot.tree.trees[".protocol"],
    "attributes",
  );
  const referenceMessage = row.raw.sequenced.find(({ sequenceNumber }) =>
    sequenceNumber === protocol.sequenceNumber);
  assert.equal(protocol.minimumSequenceNumber,
    referenceMessage?.minimumSequenceNumber,
  `${name} fresh history minimum differs from its sequenced receipt`);
  const repairSnapshot = artifact.retention.checkpoints[3].rawSnapshot;
  const retainedHistory = checkpoints["retained-repair"]
    .snapshot.evidence.retainedHandles.find(({ kind }) => kind === "history");
  const repairTrunk = JSON.parse(Buffer.from(
    repairSnapshot.blobs[retainedHistory.blobId], "base64",
  ).toString("utf8")).trunk;
  assert(repairTrunk.slice(0, dropped).every(({ sequenceNumber }) =>
    Number.isSafeInteger(sequenceNumber)
      && sequenceNumber <= protocol.minimumSequenceNumber),
  `${name} fresh history trimmed an ancestor above the observed minimum`);
  assert(!repairRevisions.includes(freshRevisions.at(-1)),
    `${name} fresh continuation lacks a new history revision`);
  if (row.writer !== "upstream") {
    for (const checkpoint of row.retention.checkpoints) {
      assert(checkpoint.lifetime.checkpoint,
        `${name} ${checkpoint.id} native lifetime checkpoint is missing`);
      assert(Array.isArray(checkpoint.lifetime.checkpoint.events)
        && Array.isArray(checkpoint.lifetime.checkpoint.commits),
      `${name} ${checkpoint.id} native lifetime queues are missing`);
    }
    const resultFor = (operation, name) => {
      const reply = row.raw.nativeReplies.findLast(({ request }) =>
        (request.op ?? request.command) === operation
          && (name === undefined || request.name === name));
      assert(reply, `${name} native lifetime receipt is missing for ${operation}`);
      assert.equal(reply.request.tree, "retention-tree",
        `${name} native lifetime receipt has another checkout owner`);
      if (name !== undefined) {
        assert.equal(reply.result.name, name,
          `${name} native lifetime result names another object`);
      }
      if (operation === "fork") {
        assert.equal(reply.request.source, "main",
          `${name} native fork request has another source`);
        assert.equal(reply.result.source, reply.request.source,
          `${name} native fork source differs from its result`);
      }
      return reply.result;
    };
    const { compressor } = decodedSnapshotCompressor(freshRawSnapshot);
    for (const [inverse, id, kind] of [
      ["retention-removal", "after-removal", "Default"],
      ["retention-redo", "after-undo", "Undo"],
      ["retention-final", "retained-repair", "Redo"],
    ]) {
      const acquired = resultFor("retainLastLocalCommit", inverse);
      assert.equal(acquired.factoryAvailable, true,
        `${name} ${inverse} acquisition lacks its event factory`);
      assert.equal(acquired.status, "Valid",
        `${name} ${inverse} acquisition has another status`);
      assert.equal(acquired.kind, kind, `${name} ${inverse} acquired another commit kind`);
      assert(Number.isSafeInteger(acquired.eventId)
        && typeof acquired.actionId === "string" && acquired.actionId.length > 0,
      `${name} ${inverse} acquisition lacks its event identity`);
      const event = checkpoints[id].lifetime.checkpoint.commits.find((commit) =>
        commit.type === "commit" && commit.eventId === acquired.eventId);
      assert(event && event.actionId === acquired.actionId
        && (event.branch ?? event.tree) === "retention-tree",
      `${name} ${inverse} acquisition lacks its checkout owner event`);
      assert.equal(event.revision, acquired.revision,
        `${name} ${inverse} commit event revision differs from acquisition`);
      assert.equal(event.kind, acquired.kind,
        `${name} ${inverse} commit event kind differs from acquisition`);
      assert.equal(event.factoryAvailable, true,
        `${name} ${inverse} commit event did not expose its factory`);
      assert.equal(event.handleAcquired, true,
        `${name} ${inverse} commit event did not acquire its inverse`);
      assert.equal(event.local, true,
        `${name} ${inverse} commit event is not local`);
      const retained = checkpoints[id].snapshot.evidence.retainedHandles.find(
        ({ kind }) => kind === "history",
      ).history.at(-1);
      assert.equal(acquired.revision, compressor.decompress(retained.revision),
        `${name} ${inverse} acquisition names another stable revision`);
      const reverted = resultFor(
        inverse === "retention-final" ? "disposeRevertible" : "revert", inverse,
      );
      assert.equal(reverted.status, "Disposed",
        `${name} ${inverse} lifetime did not end in disposal`);
      if (inverse !== "retention-final") {
        assert.equal(reverted.authoredKind, kind === "Default" ? "Undo" : "Redo",
          `${name} ${inverse} reverted with another commit kind`);
        const next = resultFor("retainLastLocalCommit",
          inverse === "retention-removal" ? "retention-redo" : "retention-final");
        assert.deepEqual(reverted.authoredEventIds, [next.eventId],
          `${name} ${inverse} revert authored another acquisition event`);
        assert.equal(reverted.actionId, next.actionId,
          `${name} ${inverse} revert authored another action`);
        assert.deepEqual(reverted.submittedRevisions, [next.revision],
          `${name} ${inverse} revert submitted another stable revision`);
      }
    }
    assert.equal(resultFor("fork", "retaining").status, "BranchValid",
      `${name} retaining branch creation lacks its actual status`);
    assert.equal(resultFor("fork", "retaining").source, "main",
      `${name} retaining branch creation has another source`);
    assert.equal(resultFor("disposeBranch", "retaining").status, "BranchDisposed",
      `${name} retaining branch disposal lacks its actual status`);
    assert.equal(
      resultFor("disposeRevertible", "retention-final").status,
      "Disposed",
      `${name} final inverse disposal lacks its actual status`,
    );
    assert.deepEqual(checkpoints["retained-repair"].lifetime.branch,
      resultFor("fork", "retaining"),
    `${name} retained repair branch receipt differs`);
    assert.deepEqual(checkpoints["branch-disposal"].lifetime.branch,
      resultFor("disposeBranch", "retaining"),
    `${name} branch disposal receipt differs`);
    assert.deepEqual(checkpoints["revertible-disposal"].lifetime.inverse,
      resultFor("disposeRevertible", "retention-final"),
    `${name} inverse disposal receipt differs`);
  }
  assert.equal(checkpoints["before-removal"].graph.link, row.targets.target.path,
    `${name} before-removal graph names another target`);
  assert.equal("link" in checkpoints["after-removal"].graph, false,
    `${name} reference removal remained visible`);
  assert.equal(checkpoints["after-removal"].lifetime.revertible, "Valid",
    `${name} removal inverse was not retained`);
  assert.equal(checkpoints["after-undo"].graph.link, row.targets.target.path,
    `${name} undo did not restore the target`);
  assert.equal(checkpoints["retained-repair"].lifetime.branches, 1,
    `${name} retained repair branch is missing`);
  assert.equal("link" in checkpoints["retained-repair"].graph, false,
    `${name} redo did not remove the main reference`);
  assert.equal(checkpoints["branch-disposal"].lifetime.branches, 0,
    `${name} branch disposal did not end its lifetime`);
  assert.equal(checkpoints["branch-disposal"].lifetime.revertible, "Valid",
    `${name} branch disposal also disposed the inverse`);
  assert.equal(checkpoints["revertible-disposal"].lifetime.revertible, "Disposed",
    `${name} inverse disposal did not end its lifetime`);
  const secondaryId = row.targets.secondary.path.split("/").filter(Boolean)[0];
  const secondaryGc = gcNode(
    checkpoints["unreferenced-datastore"].snapshot.evidence.gc,
    `/${secondaryId}`,
    `${name} unreferenced-datastore`,
  );
  const secondaryRootGc = gcNode(
    checkpoints["unreferenced-datastore"].snapshot.evidence.gc,
    row.targets.secondary.path,
    `${name} unreferenced-datastore`,
  );
  assert(Number.isFinite(secondaryGc.unreferencedTimestampMs)
    && secondaryGc.unreferencedTimestampMs > 0,
  `${name} unreferenced datastore timestamp is missing`);
  assert.equal(
    secondaryRootGc.unreferencedTimestampMs,
    secondaryGc.unreferencedTimestampMs,
    `${name} unreferenced datastore component timestamp differs`,
  );
  const initialUnreference = snapshotMetadata(
    artifact.retention.checkpoints[6].rawSnapshot,
  ).lastMessage.timestamp;
  assert.equal(secondaryGc.unreferencedTimestampMs, initialUnreference,
    `${name} initial unreference timestamp differs from measured server time`);
  const freshSecondaryGc = gcNode(
    checkpoints["fresh-load"].snapshot.evidence.gc, `/${secondaryId}`,
    `${name} fresh-load`,
  );
  assert.equal(freshSecondaryGc.unreferencedTimestampMs,
    secondaryGc.unreferencedTimestampMs,
  `${name} unreferenced datastore timestamp changed while unreachable`);
  assert.deepEqual(
    snapshotFactory(
      artifact.retention.checkpoints[6].rawSnapshot,
      row.targets.secondary.path,
    ),
    {
      packagePath: [handleGraphStore.type],
      summaryFormatVersion: 2,
      isRootDataStore: false,
    },
    `${name} unreferenced datastore component metadata differs`,
  );
  const fresh = checkpoints["fresh-load"];
  assert.equal(fresh.graph.link, row.targets.target.path,
    `${name} fresh publication did not restore the target route`);
  assert(fresh.continuation.loader,
    `${name} fresh load lacks loader storage receipts`);
  assert.equal(fresh.continuation.loadedVersion, fresh.publication.version,
    `${name} fresh load selected another publication`);
  assert.equal(
    fresh.continuation.loader.selectedVersion,
    fresh.publication.version,
    `${name} fresh loader receipt selected another publication`,
  );
  const freshRaw = artifact.retention.checkpoints.at(-1).rawSnapshot;
  validateRetentionLoader(
    name, row.writer, fresh.continuation, freshRaw, row.targets, fresh.summary,
  );
  assert.deepEqual(fresh.continuation.before, {
    document: row.targets.document.path,
    target: row.targets.target.path,
    value: "before",
  }, `${name} fresh load resolved another target`);
  assert.equal(fresh.continuation.after.continued, true,
    `${name} fresh load did not author its continuation`);
  assert(fresh.continuation.transport,
    `${name} fresh continuation transport is missing`);
  assert(fresh.continuation.transport.outboundOccurrences.length > 0,
    `${name} fresh continuation transport has no outbound submission`);
  const submittedContinuation = submissionMessages(
    fresh.continuation.transport.outboundOccurrences,
  );
  assert.equal(submittedContinuation.length, 1,
    `${name} fresh continuation has another submission count`);
  const freshClientId = submittedContinuation[0].clientId;
  assert(!row.writerClientIds.includes(freshClientId),
    `${name} fresh continuation used the old writer client`);
  const continuationReceipts = fresh.continuation.sequenced;
  assert(continuationReceipts.length > 0,
    `${name} fresh continuation lacks server receipts`);
  const firstSequence = continuationReceipts[0].sequenceNumber;
  const lastSequence = continuationReceipts.at(-1).sequenceNumber;
  assert(firstSequence > fresh.publication.referenceSequenceNumber,
    `${name} fresh continuation receipt precedes publication`);
  assert.deepEqual(continuationReceipts,
    row.raw.sequenced.filter(({ sequenceNumber }) =>
      sequenceNumber >= firstSequence && sequenceNumber <= lastSequence),
    `${name} fresh continuation receipts differ from full server history`);
  const acceptedContinuation = row.raw.sequenced.filter(({ type, clientId }) =>
    type === "op" && clientId === freshClientId);
  assert.deepEqual(continuationReceipts.filter(({ type, clientId }) =>
    type === "op" && clientId === freshClientId), acceptedContinuation,
    `${name} fresh continuation operation differs from full server history`);
  assert.deepEqual(
    submittedContinuation.map(transportOperationIdentity),
    acceptedContinuation.map(transportOperationIdentity),
    `${name} fresh continuation outbound correspondence differs`,
  );
  const [storeId, targetId] = row.targets.target.path.split("/").filter(Boolean);
  assert.deepEqual(parse(submittedContinuation[0].contents), {
    type: "component",
    contents: {
      address: storeId,
      contents: {
        type: "op",
        content: {
          address: targetId,
          contents: { type: "set", key: "continued", value: { type: "Plain", value: true } },
        },
      },
    },
  }, `${name} fresh continuation submission names another target or value`);
  assert.deepEqual(fresh.continuation.localStacks.events, [],
    `${name} fresh load revived local event state`);
  if (row.writer === "upstream") {
    assert.equal(fresh.continuation.localStacks.pendingOutbound, 0,
      `${name} fresh upstream load revived pending outbound state`);
    assert.equal(fresh.continuation.localStacks.dirty, false,
      `${name} fresh upstream load revived dirty state`);
  } else {
    assert.deepEqual(fresh.continuation.localStacks.commits, [],
      `${name} fresh native load revived local commit state`);
    const probes = fresh.continuation.localStacks.probes;
    assert(Array.isArray(probes) && probes.length === 4,
      `${name} fresh native load lacks branch and inverse lifetime probes`);
    assert.deepEqual(probes.map(({ request }) => request), [
      { op: "disposeBranch", tree: "fresh-tree", name: "retaining" },
      ...["retention-removal", "retention-redo", "retention-final"].map((name) =>
        ({ op: "revertibleStatus", tree: "fresh-tree", name })),
    ], `${name} fresh lifetime probes name other objects`);
    for (const { request, response } of probes) {
      assert.equal(response.ok, false, `${name} fresh load revived a local lifetime`);
      assert.equal(response.error.code, "facade-error",
        `${name} fresh lifetime probe failed outside the public facade`);
      assert.equal(response.error.operation, request.op,
        `${name} fresh lifetime refusal names another operation`);
      assert.equal(response.error.message,
        request.op === "disposeBranch"
          ? `Unknown branch: ${request.name}` : `Unknown revertible handle: ${request.name}`,
        `${name} fresh lifetime probe did not establish an absent object`);
    }
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
  for (const [implementation, peer] of Object.entries(row.peer.observations)) {
    assert.deepEqual(peer, {
      document: row.targets.document.path,
      target: row.targets.target.path,
      value: "before",
      continued: true,
    }, `${name} ${implementation} fresh continuation differs`);
  }
}

async function validateRow(name, row, artifacts) {
  if (name === "handleTransactionBranch") {
    return validateTransactionBranchRow(name, row, artifacts);
  }
  if (name === "handleRetention") {
    return validateRetentionRow(name, row, artifacts);
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
    : scenario.match(/^(handleValues|channelAttachment|datastoreAttachment|handleTransactionBranch|handleRetention):(upstream|javascript|erlang)$/);
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
